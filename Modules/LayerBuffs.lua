local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local L = Localization.L
local LayerBuffs = {}

-- ===========================================================================
-- Per-layer WORLD-BUFF board. Tells a hopper WHICH LAYER to go to for the world
-- buffs. Two data seams feed one per-layer picture:
--
--   1. NATIVE (our own mesh identity) — we detect a buff dropping on OUR CURRENT
--      layer from the combat log (SPELL_AURA_APPLIED with a world-buff spellID on a
--      player = the drop hand-in just happened here; this is how NWB detects too) or
--      from a capital-city control yell, tag it to our layer's zoneUID, and broadcast
--      it over the LayerNet mesh (kind "B"). So a PartyLens user WITHOUT NWB, or on
--      another layer, still learns where the buffs are.
--   2. NWB (fallback / enrichment) — when NovaWorldBuffs is installed we READ its
--      per-layer timers (NWB.data.layers[zoneUID].rendTimer/onyTimer/onyNpcDied/...)
--      live at query time. NWB already runs its own realm sync + the hard faction/
--      layer/duration validation, so this fills in layers no PartyLens user reported.
--      NWB-sourced entries are LOCAL ONLY (never re-broadcast — NWB already syncs
--      them, and each NWB user reads their own copy), so we don't double-distribute.
--
-- Buffs split into two NATURES, and "where to go" means different things for each:
--   * DROP buffs (Rend/Ony/Nef/Zan): you can only GET them at the drop instant, in
--     the city. So we only surface them while ACTIONABLE — "boss killed, buff coming"
--     (NWB's npcDied state) or freshly dropped (a few minutes) — then they disappear,
--     so we never send someone chasing a buff they already missed.
--   * STABLE buffs (Songflower, Terokkar/Hellfire zone control): re-obtainable, so we
--     surface them for as long as they're actually up.
-- ===========================================================================

-- Fixed buff durations (seconds). NWB's *CooldownTime constants are the RESPAWN
-- window (when the NEXT buff can drop), NOT the buff's own duration — so we keep the
-- real durations here for computing when an ACTIVE buff on people expires.
LayerBuffs.DUR = {
    rend = 3600,   -- Warchief's Blessing: 1h
    ony = 7200,    -- Rallying Cry of the Dragonslayer: 2h
    nef = 7200,
    dragon = 7200, -- native Rallying Cry (can't tell Ony from Nef by spellID alone)
    zan = 7200,    -- Spirit of Zandalar: 2h
    song = 3600,   -- Songflower Serenade: 1h
}

LayerBuffs.ACTIONABLE_WINDOW = 300 -- a DROP buff shows for this long after it dropped
LayerBuffs.PENDING_TTL = 900       -- "boss killed, buff coming" shows for this long
LayerBuffs.HELLFIRE_WINDOW = 3600  -- treat a Hellfire capture as "held" for this long
LayerBuffs.STABLE_MAX = 7200       -- absolute cap on how long a stable entry lingers
LayerBuffs.BROADCAST_THROTTLE = 30 -- min seconds between our mesh broadcasts per buff

-- Buff catalog. `kind`: "drop" (only actionable at the drop instant) or "stable"
-- (re-obtainable while up). `short` is the chip/tooltip label key; `name` the full
-- name key. `dropWord`/`stableWord` decide the chip glyph nature.
LayerBuffs.CATALOG = {
    rend   = { key = "rend",   kind = "drop",   nameKey = "LB_REND",   shortKey = "LB_REND_S" },
    ony    = { key = "ony",    kind = "drop",   nameKey = "LB_ONY",    shortKey = "LB_ONY_S" },
    nef    = { key = "nef",    kind = "drop",   nameKey = "LB_NEF",    shortKey = "LB_NEF_S" },
    dragon = { key = "dragon", kind = "drop",   nameKey = "LB_DRAGON", shortKey = "LB_DRAGON_S" },
    zan    = { key = "zan",    kind = "drop",   nameKey = "LB_ZAN",    shortKey = "LB_ZAN_S" },
    song   = { key = "song",   kind = "stable", nameKey = "LB_SONG",   shortKey = "LB_SONG_S" },
    terok  = { key = "terok",  kind = "stable", nameKey = "LB_TEROK",  shortKey = "LB_TEROK_S" },
    hellfire = { key = "hellfire", kind = "stable", nameKey = "LB_HELLFIRE", shortKey = "LB_HELLFIRE_S" },
}

-- Combat-log spellID -> buff key (the fresh full-duration application is the drop
-- signal). Ony and Nef share the Rallying Cry spellID, so a bare aura can't tell them
-- apart -> we record the generic "dragon"; NWB (when present) refines it to ony/nef.
LayerBuffs.SPELL_BUFF = {
    [16609] = "rend", [355366] = "rend",
    [22888] = "dragon", [355363] = "dragon",
    [24425] = "zan", [355365] = "zan",
    [15366] = "song",
}

-- Hellfire Peninsula capture yells, PER FACTION — a zone buff is only good for the
-- faction that CONTROLS the towers, so we only ever record MY faction's capture (if I'm
-- Horde and hear the Alliance NPC, that means I LOST it, not gained it). Matched
-- case-insensitively as substrings; enUS canonical phrases + a couple of ptBR fragments
-- (best-effort — a miss on other locales just falls back to the NWB read, which is also
-- faction-gated). NWB stores hellfireRep only for your own faction, so the read is safe.
local HELLFIRE_YELLS = {
    Horde = {
        "hellfire citadel is ours",       -- Nazgrel (Horde captured)
        "cidadela das chamas infernais",  -- ptBR (best-effort)
    },
    Alliance = {
        "feast of corruption is no more", -- Force Commander Danath Trollbane (Alliance captured)
        "festim da corrup",               -- ptBR (best-effort)
    },
}

-- Terokkar Spirit Towers control faction, as NWB stores it in `terokFaction`
-- (2 = Alliance controls, 3 = Horde controls). The towers buff only helps the
-- controlling faction, so we surface it only when MINE matches.
local TEROK_FACTION = { Alliance = 2, Horde = 3 }

-- The player's faction ("Horde"/"Alliance"), cached (it never changes in a session).
local _faction
local function PlayerFaction()
    if _faction == nil then
        _faction = (UnitFactionGroup and UnitFactionGroup("player")) or false
    end
    return _faction or nil
end

local function RT(partyLens)
    if not partyLens.layerbuffs then
        partyLens.layerbuffs = {
            live = {},      -- [id] = entry  self/mesh native detections (broadcast, TTL)
            lastCast = {},  -- [buffKey] = last mesh-broadcast epoch (throttle)
        }
    end
    return partyLens.layerbuffs
end

local function LN()
    return _G[ADDON_NAME .. "_LayerNet"]
end

-- Server epoch — realm-synchronised across all clients, so an absolute expiry we send
-- over the mesh means the same instant on every client (unlike time(), the client wall
-- clock the presence gossip has to send as a relative age).
local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

-- Compact, readable remaining time: "4h05m" (>= 1h, minutes zero-padded so it reads as
-- a clock), "42m" (< 1h), "<1m" (about to expire). Beats a bare "245m".
function LayerBuffs.FmtTime(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 60 then
        return "<1m"
    end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then
        return string.format("%dh%02dm", h, m)
    end
    return m .. "m"
end

-- ---------------------------------------------------------------------------
-- NovaWorldBuffs read (live, at query time — always fresh, local only)
-- ---------------------------------------------------------------------------
local _nwb
local function GetNWB()
    if _nwb then
        return _nwb
    end
    local LibStub = _G.LibStub
    if not LibStub then
        return nil
    end
    local ok, ace = pcall(LibStub, "AceAddon-3.0", true)
    if not ok or not ace or not ace.GetAddon then
        return nil
    end
    local ok2, nwb = pcall(ace.GetAddon, ace, "NovaWorldBuffs", true)
    if ok2 and nwb and nwb.data then
        _nwb = nwb
        return nwb
    end
    return nil
end

-- Push a normalised buff entry into `out` (a list). Keyed later by ordinal in the
-- caller. `dropAt`/`expiry` are server epochs; `status` is "pending" or "active".
local function Emit(out, buffKey, zoneUID, mapID, status, dropAt, expiry, source)
    out[#out + 1] = {
        buffKey = buffKey, zoneUID = zoneUID, mapID = mapID,
        status = status, dropAt = dropAt, expiry = expiry, source = source,
    }
end

-- Read one NWB layer table (`ld`) for a given zoneUID into `out`. Wrapped so a shape
-- change in a future NWB never errors us — a bad field just yields no entry.
local function ReadNWBLayer(nwb, out, zoneUID, mapID, ld, now)
    if type(ld) ~= "table" then
        return
    end
    -- Rend: a plain drop timer (no "killed, pending" phase).
    local rt2 = tonumber(ld.rendTimer)
    if rt2 and rt2 > 0 then
        Emit(out, "rend", zoneUID, mapID, "active", rt2, rt2 + LayerBuffs.DUR.rend, "nwb")
    end
    -- Ony / Nef: prefer the "boss killed, buff imminent" state (npcDied > timer and
    -- still within NWB's respawn window) — that's the genuinely actionable signal —
    -- else the last drop time.
    local onyCd = tonumber(nwb.onyCooldownTime) or 21600
    local od, ot = tonumber(ld.onyNpcDied), tonumber(ld.onyTimer)
    if od and ot and od > ot and (now - od) < onyCd then
        Emit(out, "ony", zoneUID, mapID, "pending", od, nil, "nwb")
    elseif ot and ot > 0 then
        Emit(out, "ony", zoneUID, mapID, "active", ot, ot + LayerBuffs.DUR.ony, "nwb")
    end
    local nefCd = tonumber(nwb.nefCooldownTime) or 28800
    local nd, nt = tonumber(ld.nefNpcDied), tonumber(ld.nefTimer)
    if nd and nt and nd > nt and (now - nd) < nefCd then
        Emit(out, "nef", zoneUID, mapID, "pending", nd, nil, "nwb")
    elseif nt and nt > 0 then
        Emit(out, "nef", zoneUID, mapID, "active", nt, nt + LayerBuffs.DUR.nef, "nwb")
    end
    -- Terokkar Spirit Towers: field is the CONTROL END server-time; terokFaction says
    -- WHO controls (2 = Alliance, 3 = Horde). The buff only helps the controlling
    -- faction, and NWB syncs this field from BOTH factions, so surface it only when the
    -- controller is MINE (else I'd be told to hop for a buff the enemy holds).
    local terok = tonumber(ld.terokTowers)
    local mine = TEROK_FACTION[PlayerFaction() or ""]
    if terok and terok > now and mine and tonumber(ld.terokFaction) == mine then
        Emit(out, "terok", zoneUID, mapID, "active", nil, terok, "nwb")
    end
    -- Hellfire towers: the field is the CAPTURE time; treat it as held for a window.
    local hell = tonumber(ld.hellfireRep)
    if hell and hell > 0 and (now - hell) < LayerBuffs.HELLFIRE_WINDOW then
        Emit(out, "hellfire", zoneUID, mapID, "active", hell, hell + LayerBuffs.HELLFIRE_WINDOW, "nwb")
    end
end

-- All buffs NWB currently knows, as normalised entries (each with its zoneUID). Read
-- live so it always reflects NWB's latest sync. Empty when NWB is absent.
local function ReadNWB(partyLens, now)
    local nwb = GetNWB()
    local out = {}
    if not nwb or not nwb.data then
        return out
    end
    local capMap = Layer.CAPITAL_MAP or 0
    if nwb.isLayered and type(nwb.data.layers) == "table" then
        for zoneUID, ld in pairs(nwb.data.layers) do
            local z = tonumber(zoneUID)
            if z and z > 0 then
                ReadNWBLayer(nwb, out, z, capMap, ld, now)
            end
        end
    else
        -- Non-layered realm: NWB stores the timers globally. Attach them to whatever
        -- layer we're standing on (there's effectively one).
        local cur = Layer.Current(partyLens)
        if cur.zoneUID and cur.zoneUID > 0 then
            ReadNWBLayer(nwb, out, cur.zoneUID, cur.mapID or capMap, nwb.data, now)
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Recording + broadcasting native detections
-- ---------------------------------------------------------------------------
local function IDOf(zoneUID, buffKey)
    return tostring(zoneUID) .. ":" .. buffKey
end

-- UI hook (implemented by UIMain when the Layer tab exists).
function LayerBuffs.Refresh(partyLens)
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.RefreshLayer then
        UIMain.RefreshLayer(partyLens)
    end
end

-- Record a buff (from our own detection or the mesh) into rt.live. Drop-buff records
-- carry dropAt (for the actionable window); stable records carry an expiry.
local function Record(partyLens, buffKey, mapID, zoneUID, dropAt, expiry, source, spotter)
    local cat = LayerBuffs.CATALOG[buffKey]
    if not cat or not zoneUID or zoneUID <= 0 or not mapID or mapID <= 0 then
        return false
    end
    if mapID and zoneUID then
        Layer.MergeSeen(partyLens, mapID, { zoneUID }) -- so the buff's layer can be numbered
    end
    local rt = RT(partyLens)
    local id = IDOf(zoneUID, buffKey)
    local prev = rt.live[id]
    local now = Now()
    rt.live[id] = {
        buffKey = buffKey, zoneUID = zoneUID, mapID = mapID,
        dropAt = dropAt, expiry = expiry, status = "active",
        source = source, spotter = spotter, t = now,
    }
    -- "New" = we didn't already have this buff on this layer (for the alert throttle).
    local isNew = not prev or (now - (prev.t or 0)) > LayerBuffs.ACTIONABLE_WINDOW
    return isNew
end

-- Broadcast a native detection to the mesh so PL users without NWB / on other layers
-- learn it: B|mapID|zoneUID|buffKey|expiry. Expiry is a server epoch (realm-synced).
-- Only NATIVE (self) detections are broadcast — NWB-sourced ones stay local.
function LayerBuffs.Cast(partyLens, buffKey, mapID, zoneUID, expiry)
    local ln = LN()
    if ln and ln.Broadcast and mapID and zoneUID and mapID > 0 and zoneUID > 0 then
        ln.Broadcast(table.concat({
            ln.NET_PROTO, "B", tostring(mapID), tostring(zoneUID), buffKey, tostring(expiry or 0),
        }, "|"), "B:" .. buffKey) -- realm-wide too, coalesced per buff (latest sighting)
    end
end

-- Detect + record + broadcast a buff dropping/held on MY CURRENT layer. Throttled per
-- buff so a burst of aura events (many players getting the buff at once) sends once.
-- SILENT (no chat line): the buff is on MY layer, so I'm already here and getting it —
-- the chip indicator is the surface. The value is broadcasting it to OTHER players.
local function DetectOnMyLayer(partyLens, buffKey, dur)
    local cur = Layer.Current(partyLens)
    if not cur.zoneUID or cur.zoneUID <= 0 or not cur.mapID or cur.mapID <= 0 then
        return
    end
    local now = Now()
    local expiry = now + (dur or LayerBuffs.DUR[buffKey] or 3600)
    local isNew = Record(partyLens, buffKey, cur.mapID, cur.zoneUID, now, expiry, "self",
        Utils.PlayerShortName(UnitName("player") or ""))
    local rt = RT(partyLens)
    if (now - (rt.lastCast[buffKey] or 0)) >= LayerBuffs.BROADCAST_THROTTLE then
        rt.lastCast[buffKey] = now
        LayerBuffs.Cast(partyLens, buffKey, cur.mapID, cur.zoneUID, expiry)
    end
    if isNew then
        LayerBuffs.Refresh(partyLens)
    end
end

-- Native combat-log hook: a world-buff aura just landed on a player -> it dropped on
-- MY layer right now. Call from COMBAT_LOG_EVENT_UNFILTERED.
function LayerBuffs.OnCombatLog(partyLens)
    if not CombatLogGetCurrentEventInfo then
        return
    end
    local _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_AURA_APPLIED" and subEvent ~= "SPELL_AURA_REFRESH" then
        return
    end
    local buffKey = spellID and LayerBuffs.SPELL_BUFF[spellID]
    if not buffKey then
        return
    end
    -- Rend (Warchief's Blessing) is Horde-only — an Alliance hopper can't get it, so
    -- don't put it on their board even if a nearby Horde carries it.
    if buffKey == "rend" and PlayerFaction() == "Alliance" then
        return
    end
    -- Only trust an application on an actual PLAYER (the buff is gained by players at
    -- the city hand-in). destGUID starts with "Player-".
    if type(destGUID) == "string" and string.sub(destGUID, 1, 7) == "Player-" then
        DetectOnMyLayer(partyLens, buffKey)
    end
end

-- Native yell hook: MY faction just captured Hellfire (only my faction's NPC yells its
-- own victory, so this only fires when the buff is good for ME). Call from
-- CHAT_MSG_MONSTER_YELL with the message text.
function LayerBuffs.OnMonsterYell(partyLens, msg)
    local lower = Utils.SafeLower(msg or "")
    if lower == "" then
        return
    end
    local phrases = HELLFIRE_YELLS[PlayerFaction() or ""]
    if not phrases then
        return
    end
    for _, phrase in ipairs(phrases) do
        if string.find(lower, phrase, 1, true) then
            DetectOnMyLayer(partyLens, "hellfire", LayerBuffs.HELLFIRE_WINDOW)
            return
        end
    end
end

-- A buff heard from another PartyLens user over the mesh (kind "B").
function LayerBuffs.OnMesh(partyLens, mapID, zoneUID, buffKey, expiry)
    if not LayerBuffs.CATALOG[buffKey] then
        return
    end
    expiry = tonumber(expiry)
    local dur = LayerBuffs.DUR[buffKey] or LayerBuffs.HELLFIRE_WINDOW
    -- Recover the original drop time from the expiry the sender broadcast (expiry =
    -- dropAt + duration). Drop buffs need it for the actionable window; harmless for
    -- stable buffs (their relevance is driven by the expiry).
    local dropAt = expiry and (expiry - dur) or nil
    if Record(partyLens, buffKey, tonumber(mapID), tonumber(zoneUID), dropAt, expiry, "mesh") then
        LayerBuffs.Refresh(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Query
-- ---------------------------------------------------------------------------
-- Is a normalised entry currently RELEVANT to surface?
--   drop  -> only while pending (boss killed) or freshly dropped (actionable window)
--   stable-> while its expiry is in the future
local function IsRelevant(entry, now)
    local cat = LayerBuffs.CATALOG[entry.buffKey]
    if not cat then
        return false
    end
    if cat.kind == "drop" then
        if entry.status == "pending" then
            return entry.dropAt and (now - entry.dropAt) < LayerBuffs.PENDING_TTL
        end
        return entry.dropAt and (now - entry.dropAt) <= LayerBuffs.ACTIONABLE_WINDOW
    end
    -- stable
    if entry.expiry then
        return entry.expiry > now and (now - (entry.dropAt or entry.expiry - LayerBuffs.STABLE_MAX)) < LayerBuffs.STABLE_MAX
    end
    return false
end

-- Merge NWB + live entries for the whole map into a per-ordinal table:
--   result[ordinal] = { [buffKey] = displayEntry }
-- Dedup rules: NWB's Ony/Nef refinement beats the native generic "dragon"; otherwise
-- the fresher / more-informative entry wins.
local function BuildByOrdinal(partyLens, now)
    local byOrd = {}
    local function consider(entry)
        if not IsRelevant(entry, now) then
            return
        end
        local ord = Layer.OrdinalOf(partyLens, entry.mapID, entry.zoneUID)
        if not ord then
            return
        end
        byOrd[ord] = byOrd[ord] or {}
        local slot = byOrd[ord]
        local existing = slot[entry.buffKey]
        if not existing then
            slot[entry.buffKey] = entry
        else
            -- Prefer a pending (more urgent) drop state, then a known expiry, then fresher.
            local better = (entry.status == "pending" and existing.status ~= "pending")
                or ((entry.expiry or 0) > (existing.expiry or 0))
            if better then
                slot[entry.buffKey] = entry
            end
        end
    end

    for _, e in pairs(ReadNWB(partyLens, now)) do
        consider(e)
    end
    for _, e in pairs(RT(partyLens).live) do
        consider(e)
    end

    -- Drop the generic native "dragon" wherever NWB gave the specific Ony/Nef on the
    -- same layer (avoids showing "Ony/Nef" alongside "Onyxia").
    for _, slot in pairs(byOrd) do
        if slot.dragon and (slot.ony or slot.nef) then
            slot.dragon = nil
        end
    end
    return byOrd
end

-- Buffs relevant on a given layer ordinal, for the chip/tooltip. Returns:
--   { hasUrgent, hasStable, list = { {buffKey, name, short, urgent, status, remaining} } }
-- `urgent` = a drop buff (pending/fresh) that wants attention NOW.
function LayerBuffs.ForOrdinal(partyLens, ordinal, byOrd)
    byOrd = byOrd or BuildByOrdinal(partyLens, Now())
    local slot = byOrd[ordinal]
    local out = { hasUrgent = false, hasStable = false, list = {} }
    if not slot then
        return out
    end
    local now = Now()
    for buffKey, e in pairs(slot) do
        local cat = LayerBuffs.CATALOG[buffKey]
        local urgent = cat.kind == "drop"
        local remaining
        if e.status == "pending" then
            remaining = nil
        elseif e.expiry then
            remaining = math.max(0, e.expiry - now)
        end
        out.list[#out.list + 1] = {
            buffKey = buffKey,
            name = L(cat.nameKey),
            short = L(cat.shortKey),
            kind = cat.kind,
            urgent = urgent,
            status = e.status,
            remaining = remaining,
            source = e.source,
        }
        if urgent then
            out.hasUrgent = true
        else
            out.hasStable = true
        end
    end
    -- Urgent first, then by most time remaining.
    table.sort(out.list, function(a, b)
        if a.urgent ~= b.urgent then
            return a.urgent
        end
        return (a.remaining or math.huge) < (b.remaining or math.huge)
    end)
    return out
end

-- Pre-build the whole map once (so RefreshHopChips can pass it to ForOrdinal per chip
-- without recomputing the NWB read + relevance for every layer).
function LayerBuffs.Snapshot(partyLens)
    return BuildByOrdinal(partyLens, Now())
end

-- Every relevant buff across all layers, newest first (for /partylens buffs + future
-- board). Each entry gets its ordinal in our frame.
function LayerBuffs.Active(partyLens)
    local now = Now()
    local byOrd = BuildByOrdinal(partyLens, now)
    local out = {}
    for ord, slot in pairs(byOrd) do
        for buffKey, e in pairs(slot) do
            local cat = LayerBuffs.CATALOG[buffKey]
            out[#out + 1] = {
                ordinal = ord, buffKey = buffKey, name = L(cat.nameKey), kind = cat.kind,
                status = e.status, source = e.source,
                remaining = (e.status ~= "pending" and e.expiry) and math.max(0, e.expiry - now) or nil,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.ordinal ~= b.ordinal then
            return a.ordinal < b.ordinal
        end
        return a.buffKey < b.buffKey
    end)
    return out
end

-- Prune stale live entries. Called on the LayerNet tick cadence.
function LayerBuffs.Prune(partyLens)
    local rt = partyLens.layerbuffs
    if not rt then
        return
    end
    local now = Now()
    for id, e in pairs(rt.live) do
        local cat = LayerBuffs.CATALOG[e.buffKey]
        local dead
        if not cat then
            dead = true
        elseif cat.kind == "drop" then
            dead = not (e.dropAt and (now - e.dropAt) < LayerBuffs.PENDING_TTL)
        else
            dead = not (e.expiry and e.expiry > now)
        end
        if dead then
            rt.live[id] = nil
        end
    end
end

_G[ADDON_NAME .. "_LayerBuffs"] = LayerBuffs
return LayerBuffs
