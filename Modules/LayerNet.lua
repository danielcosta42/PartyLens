local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local L = Localization.L
local LayerNet = {}

-- ===========================================================================
-- The layer-hopping network engine.
--
-- A player toggles BEACON on to become a node: the addon scans public chat for
-- people asking for a layer, and if the beacon is on the requested layer it
-- silently invites them (a party invite by name pulls the invitee onto the
-- inviter's layer) and whispers instructions. Everything the beacon does is kept
-- INVISIBLE to the beacon player — no party join/leave spam, no whisper popups.
--
-- Coordination + presence ride a hidden custom chat channel (custom channels are
-- realm-wide / cross-layer; hidden addon messages over a CHANNEL are disabled on
-- this client, so we use a normal channel filtered out of the chat frames).
-- ===========================================================================

-- The mesh rides hidden ADDON messages over the realm-wide LookingForGroup
-- channel (the same transport the Browse mesh uses — proven on this client and
-- NOT hardware-gated, unlike a visible SendChatMessage to a CHANNEL). Its own
-- prefix keeps it separate from the Browse ("PartyLens") traffic.
LayerNet.PREFIX = "PLLnet"            -- addon-message prefix for the layer mesh
LayerNet.NET_PROTO = "PLL1"           -- payload protocol tag
LayerNet.TICK = 5
LayerNet.SYNC_INTERVAL = 30           -- presence/sighting broadcast cadence (numbering sync)
LayerNet.MAX_PER_MINUTE = 4           -- invite/whisper cap (mirrors autopilot)
LayerNet.CONTACT_COOLDOWN = 90        -- per-name cooldown
LayerNet.NODE_TTL = 150               -- a node counts as "online" if heard within this
LayerNet.REQUEST_TTL = 60             -- an inbound request stays "open" this long
LayerNet.MY_REQUEST_TTL = 120         -- my own layer request stays active/re-broadcast this long
LayerNet.PARTY_HOLD = 40              -- auto-uninvite an invitee still around after this (they hop fast)
LayerNet.LOG_MAX = 20                 -- recent-activity log lines kept

local function CFG(partyLens)
    partyLens.db.layer = partyLens.db.layer or {}
    local c = partyLens.db.layer
    c.channels = c.channels or { trade = true, general = true, lookingforgroup = true, world = true }
    if c.whisper == nil then c.whisper = true end -- default on (marketing); backfills old saves
    if c.hideParty == nil then c.hideParty = true end -- hide the party frame while beaconing
    c.hops = c.hops or 0
    return c
end

-- Runtime (never persisted).
local function RT(partyLens)
    if not partyLens.layernet then
        partyLens.layernet = {
            contacts = {},      -- [key] = lastContactEpoch
            actionTimes = {},   -- rolling window of invite/whisper times
            requests = {},      -- [key] = { name, req, t } open layer requests (for UI)
            nodes = {},         -- [key] = { name, ordinal, zoneUID, mapID, beacon, t } mesh peers heard
            party = {},         -- [key] = invitedAt  (names we invited, for auto-clean)
            pendingKick = {},   -- [key] = true  lingerers to UninviteUnit on a hardware event
            log = {},           -- recent activity ({ t, text }) — operator visibility
            myRequest = nil,    -- { req, spec, t, lastNet } my own active layer request
            lastSync = 0,       -- last time we broadcast our sighting to the mesh
            ticker = nil,
        }
    end
    return partyLens.layernet
end

-- Recent-activity log so the (silent) beacon operator can SEE it working.
function LayerNet.Log(partyLens, text)
    local rt = RT(partyLens)
    table.insert(rt.log, 1, { t = time(), text = text })
    for i = LayerNet.LOG_MAX + 1, #rt.log do
        rt.log[i] = nil
    end
    LayerNet.Refresh(partyLens)
end

local function Key(name)
    return Utils.SafeLower(Utils.PlayerShortName(name or ""))
end

local function SameAsPlayer(name)
    return Key(name) == Key(UnitName("player") or "")
end

-- ---------------------------------------------------------------------------
-- Request parsing
-- ---------------------------------------------------------------------------
local TRIGGERS = { "layer", "camada" }
local BLACKLIST = {
    "wts", "wtb", "lfm", "lfg", "boost", "gdkp", "enchant", "guild", "raid",
    "what layer", "which layer", "qual layer", "que layer", "no layer",
}
-- Ignore only NON-request addon chatter: NWB posts layer/buff INFO ("[NWB] Layer 3
-- ...") that would parse as a phantom request, and "[partylens]"/"[pll" are our own
-- signed lines / mesh proto (handled over the mesh, not re-parsed from chat). We do
-- NOT ignore competitor hop addons (OpenLayer "<ol>", AutoLayer): their users' layer
-- requests are fair game — whoever invites first wins the client, so we race for them.
local IGNORE_PREFIX = { "[nwb]", "[partylens]", "[pll" }
local INVERT = { "not", "except", "other than", "menos", "exceto", "fora de" }
local ANY = { "any layer", "any is fine", "any works", "qualquer layer", "qualquer camada", "tanto faz" }
-- Layer-hop intent words for the DEDICATED layer channel, where people drop the
-- (redundant) word "layer" and just say "inv 5", "hop me", "pull to 3". Whole-word
-- matched, so "inv" won't hit "invasion".
local HOP_WORDS = { "inv", "invite", "hop", "pull", "port", "puxa", "puxar", "any", "qualquer" }
-- Cross-posted LFG/recruit spam that shares the layer channel — role/class/raid
-- words never appear in a real "get me to layer N" request, so if we see one it's
-- not a layer request (used only in the permissive layer-channel path).
local IMPLIED_SPAM = {
    "heal", "heals", "healer", "dps", "tank", "tanks", "gs", "ilvl", "gearscore",
    "druid", "hunter", "mage", "priest", "warrior", "warlock", "rogue", "paladin", "shaman",
    "kara", "karazhan", "ssc", "tk", "gruul", "mag", "team", "teams", "heroic", "hc",
}

local function StripColors(msg)
    msg = string.gsub(msg or "", "|c%x%x%x%x%x%x%x%x", "")
    msg = string.gsub(msg, "|r", "")
    return msg
end

-- Returns { any=bool, exclude=bool, layers={ [n]=true } } for a layer request, or nil.
-- `implied` = the line came from a DEDICATED layer channel, so we don't require the
-- word "layer" (a bare number / "any" / a hop word is enough), but we still demand a
-- request signal AND reject cross-posted LFG spam so plain chatter isn't mistaken.
function LayerNet.ParseRequest(msg, implied)
    local text = StripColors(msg)
    local lower = Utils.SafeLower(text)

    for _, pre in ipairs(IGNORE_PREFIX) do
        if string.sub(lower, 1, #pre) == pre then
            return nil
        end
    end
    local hasTrigger = Utils.ContainsAnyWord(lower, TRIGGERS)
    if not implied and not hasTrigger then
        return nil
    end
    if Utils.ContainsAny(lower, BLACKLIST) then
        return nil
    end

    local layers, hasNum = {}, false
    for a, b in string.gmatch(lower, "(%d+)%s*%-%s*(%d+)") do
        a, b = tonumber(a), tonumber(b)
        if a and b then
            if a > b then a, b = b, a end
            for n = a, math.min(b, 99) do layers[n] = true; hasNum = true end
        end
    end
    -- Standalone numbers too, UNCONDITIONALLY: a mixed "layer 5 or 10-12" must
    -- keep the 5 (the range loop above only caught 10-12).
    for n in string.gmatch(lower, "%d+") do
        n = tonumber(n)
        if n and n > 0 and n < 100 then layers[n] = true; hasNum = true end
    end

    -- An explicit "any layer" intent wins over incidental digits (times/prices
    -- like "8-11pm") and also blocks a stray "except" from inverting the request.
    local anyIntent = Utils.ContainsAny(lower, ANY)

    -- Dedicated-layer-channel gating: drop LFG cross-posts, and require a real
    -- request signal (a number, an "any", the word "layer", or a hop word) so
    -- random chatter ("thanks", "gg") in that channel isn't taken as a request.
    if implied then
        if Utils.ContainsAnyWord(lower, IMPLIED_SPAM) then
            return nil
        end
        if not hasTrigger and not anyIntent and not hasNum
            and not Utils.ContainsAnyWord(lower, HOP_WORDS) then
            return nil
        end
    end

    return {
        any = anyIntent or not hasNum,
        exclude = (not anyIntent) and Utils.ContainsAnyWord(lower, INVERT),
        layers = layers,
    }
end

-- Does my current layer ordinal satisfy this request?
local function Matches(req, myOrdinal)
    -- "any layer" needs no knowledge of our own ordinal (the invite physically
    -- pulls the requester onto our layer regardless), so it matches even before
    -- we've sighted an NPC. Only the specific/exclude branches need the ordinal.
    if req.any then
        return true
    end
    if not myOrdinal then
        return false
    end
    if req.exclude then
        return not req.layers[myOrdinal]
    end
    return req.layers[myOrdinal] == true
end

-- Does my CURRENT layer satisfy this request? Prefers an EXACT, frame-independent
-- match on the absolute zoneUID the requester resolved ("layer 5" -> that layer's
-- zoneUID in the shared set), so we can never pull someone to the wrong physical
-- layer just because two clients number layers slightly differently. Falls back to
-- the ordinal compare only when no target zoneUID is available (a bare public-chat
-- number from a non-mesh requester) — best-effort there, but the mesh path is exact.
local function RequestMatches(partyLens, req, targetZoneUID, reqMapID, strict)
    if req.any then
        return true
    end
    if targetZoneUID and targetZoneUID > 0 then
        local cur = Layer.Current(partyLens)
        if not cur.zoneUID then
            return false -- can't confirm which layer I'm on
        end
        -- zoneUIDs are unique only PER MAP (they're one field of a creature GUID),
        -- and the mesh is realm-wide — a matching integer on a DIFFERENT map is a
        -- different physical layer, so require the same map before trusting it.
        if reqMapID and cur.mapID ~= reqMapID then
            return false
        end
        if req.exclude then
            return cur.zoneUID ~= targetZoneUID
        end
        return cur.zoneUID == targetZoneUID
    end
    -- No resolved target zoneUID. For a MESH request (strict) that means the
    -- requester couldn't map its number to a layer, so its bare number can't be
    -- trusted against our ordinal — decline rather than risk a wrong-layer pull.
    -- A bare public-chat request has no better signal, so fall back to a best-effort
    -- ordinal match (sound for genuinely co-located, same-set clients).
    if strict then
        return false
    end
    return Matches(req, Layer.Current(partyLens).ordinal)
end

-- ---------------------------------------------------------------------------
-- Anti-spam (parallel to the autopilot limiter, own runtime)
-- ---------------------------------------------------------------------------
local function CanContact(rt, name)
    local last = rt.contacts[Key(name)]
    return not last or (time() - last) >= LayerNet.CONTACT_COOLDOWN
end

local function WithinRate(rt)
    local now, kept = time(), {}
    for _, t in ipairs(rt.actionTimes) do
        if now - t < 60 then kept[#kept + 1] = t end
    end
    rt.actionTimes = kept
    return #kept < LayerNet.MAX_PER_MINUTE
end

local function RecordContact(rt, name)
    rt.contacts[Key(name)] = time()
    rt.actionTimes[#rt.actionTimes + 1] = time()
end

-- ---------------------------------------------------------------------------
-- Engage: invite the requester + whisper instructions (silent for the beacon)
-- ---------------------------------------------------------------------------
local function DoInvite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        pcall(InviteUnit, name)
    end
end

-- Chat message filters hide the whisper TEXT but WoW still opens a temporary
-- conversation window/tab for the target. Close it so the beacon stays silent.
-- Only closes auto-created TEMPORARY whisper windows (never the user's own).
function LayerNet.CloseWhisperWindow(name)
    if not name or name == "" then
        return
    end
    local short = Utils.SafeLower(Utils.PlayerShortName(name))
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.isTemporary and f.chatType == "WHISPER" and f.chatTarget
            and Utils.SafeLower(Utils.PlayerShortName(f.chatTarget)) == short then
            pcall(FCF_Close, f)
        end
    end
end

-- Schedule a window close shortly after the whisper (the temp window opens async).
local function SilenceWhisperFor(name)
    LayerNet.CloseWhisperWindow(name)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() LayerNet.CloseWhisperWindow(name) end)
    end
end

function LayerNet.Engage(partyLens, name, req)
    local rt = RT(partyLens)
    if not name or name == "" or SameAsPlayer(name) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    -- Party already full: a name-invite would be silently rejected by the server.
    -- Bail BEFORE spending a cooldown/rate slot or logging a phantom "invited" —
    -- CleanParty frees hopper slots and the tick retry re-engages once there's room.
    if ((GetNumGroupMembers and GetNumGroupMembers()) or 0) >= 5 then
        return
    end
    if not Roster.CanInvite() or Roster.IsInGroup(name) then
        return
    end
    if not CanContact(rt, name) or not WithinRate(rt) then
        return
    end

    local cfg = CFG(partyLens)
    local short = Utils.PlayerShortName(name)
    local cur = Layer.Current(partyLens)
    DoInvite(short)
    -- Instruction whisper is opt-in (default off). Whispering at all opens a chat
    -- tab on the beacon's client, so silence-first we skip it; when enabled, the
    -- signed echo is filtered AND the conversation window is closed.
    if cfg.whisper then
        Utils.SendChat(L("LAYER_WHISPER", cur.ordinal or "?"), "WHISPER", nil, short)
        SilenceWhisperFor(short)
    end

    RecordContact(rt, name)
    rt.party[Key(name)] = time()
    cfg.hops = (cfg.hops or 0) + 1
    LayerNet.Log(partyLens, L("LAYER_LOG_INVITED", short, cur.ordinal or "?"))
end

-- ---------------------------------------------------------------------------
-- Inbound chat: record the request (for the UI) and, as a beacon, engage on match
-- ---------------------------------------------------------------------------
local CHANNEL_KEY = { trade = "trade", general = "general", world = "world",
    lookingforgroup = "lookingforgroup", ["services"] = "trade" }

-- source: "trade"|"general"|"world"|"lookingforgroup"|"guild"|"whisper" (already gated by caller)
function LayerNet.OnRequest(partyLens, msg, sender, source)
    if not sender or sender == "" or SameAsPlayer(sender) then
        return
    end
    -- The dedicated layer channel gets permissive parsing (bare numbers / hop words).
    local req = LayerNet.ParseRequest(msg, source == "layer")
    if not req then
        return
    end
    local rt = RT(partyLens)
    local key = Key(sender)
    local isNew = rt.requests[key] == nil
    -- Public-chat / whisper requests carry no resolved target zoneUID (the sender
    -- isn't on our mesh), so matching for these falls back to the ordinal compare.
    rt.requests[key] = { name = Utils.PlayerShortName(sender), req = req, t = time(), source = source }

    -- Log every NEWLY-seen request (deduped per sender for REQUEST_TTL) so the
    -- operator can SEE the addon reading the channel — even when the beacon is off
    -- or the request is for a layer we're not on (so no invite fires).
    if isNew then
        LayerNet.Log(partyLens, L("LAYER_LOG_SEEN", Utils.PlayerShortName(sender), LayerNet.RequestText(req)))
    end

    local cfg = CFG(partyLens)
    if cfg.beacon then
        if source == "whisper" then
            SilenceWhisperFor(sender) -- close the incoming whisper window too
        end
        if RequestMatches(partyLens, req, nil, nil, false) then
            LayerNet.Engage(partyLens, sender, req)
        end
    end
    LayerNet.Refresh(partyLens)
end

-- ---------------------------------------------------------------------------
-- Addon mesh (cross-layer, invisible): presence sync + layer requests ride
-- hidden ADDON messages over the realm-wide LookingForGroup channel.
--
--   PLL1|S|<mapID>|<zoneUID>|<ordinal>|<beacon>   presence / layer sighting
--   PLL1|R|<mapID>|<zoneUID>|<spec>               a layer request (spec: "any"|"5"|"5,7"|"!4")
--
-- Every sighting we hear grows our shared zoneUID set (Layer.MergeSeen), so the
-- friendly layer NUMBERS converge across all PartyLens users on the realm — my
-- "Layer 5" becomes your "Layer 5". Requests are cross-layer, so a beacon on the
-- wanted layer can invite a requester standing on any other layer.
-- ---------------------------------------------------------------------------
local function LFGChannelNumber()
    local n = GetChannelName and GetChannelName("LookingForGroup")
    return (type(n) == "number" and n > 0) and n or nil
end

-- Fire-and-forget addon broadcast over the LFG channel (invisible, cross-layer).
local function SendNet(payload)
    local num = LFGChannelNumber()
    if not num then
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then
        return false
    end
    pcall(send, LayerNet.PREFIX, payload, "CHANNEL", num)
    return true
end

function LayerNet.RegisterPrefix()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then
        pcall(register, LayerNet.PREFIX)
    end
end

-- Encode a parsed request { any, exclude, layers } to a compact spec string.
local function SpecFromReq(req)
    if not req or req.any then
        return "any"
    end
    local nums = {}
    for n in pairs(req.layers or {}) do
        nums[#nums + 1] = n
    end
    table.sort(nums)
    local s = table.concat(nums, ",")
    if s == "" then
        return "any"
    end
    return req.exclude and ("!" .. s) or s
end

-- Decode a spec string back to a request table (inverse of SpecFromReq).
local function ReqFromSpec(spec)
    spec = spec or ""
    if spec == "" or spec == "any" then
        return { any = true, layers = {} }
    end
    local exclude = string.sub(spec, 1, 1) == "!"
    local layers, has = {}, false
    for n in string.gmatch(spec, "%d+") do
        n = tonumber(n)
        if n and n > 0 and n < 100 then
            layers[n] = true
            has = true
        end
    end
    if not has then
        return { any = true, layers = {} }
    end
    return { any = false, exclude = exclude, layers = layers }
end

-- Broadcast our current layer sighting to the mesh (presence + numbering sync).
-- No-op until we've detected a zoneUID. Callers gate this to active participants
-- (beacon / requester) so idle clients don't chatter.
function LayerNet.BroadcastSighting(partyLens)
    local cur = Layer.Current(partyLens)
    if not cur.zoneUID then
        return
    end
    local cfg = CFG(partyLens)
    -- S|mapID|curZoneUID|beacon|<full sorted zoneUID set> — sharing the WHOLE set
    -- (not just our current layer) is what actually makes numbering converge across
    -- clients: everyone ends up with the union of active layers, so ordinals agree.
    SendNet(table.concat({
        LayerNet.NET_PROTO, "S", tostring(cur.mapID or 0), tostring(cur.zoneUID or 0),
        cfg.beacon and "1" or "0", Layer.SeenCSV(partyLens, cur.mapID),
    }, "|"))
end

-- Merge a comma-separated zoneUID list into our shared set (numbering convergence).
local function MergeCSV(partyLens, mapID, csv)
    if not mapID or mapID <= 0 or not csv or csv == "" then
        return
    end
    local list = {}
    for z in string.gmatch(csv, "%d+") do
        list[#list + 1] = tonumber(z)
    end
    if #list > 0 then
        Layer.MergeSeen(partyLens, mapID, list)
    end
end

-- Record a heard mesh peer. Ordinals are computed in OUR frame from the zoneUID
-- (Stats/matching) — we never trust the peer's own numbering.
local function RecordNode(partyLens, sender, mapID, zoneUID, isBeacon)
    RT(partyLens).nodes[Key(sender)] = {
        name = Utils.PlayerShortName(sender),
        zoneUID = zoneUID,
        mapID = mapID,
        beacon = isBeacon and true or false,
        t = time(),
    }
end

-- Inbound addon-mesh message (CHAT_MSG_ADDON over the LFG channel).
--   S|mapID|curZone|beacon|setCSV        presence + full sighting set
--   R|mapID|curZone|spec|targetZone      a layer request (targetZone = wanted layer's zoneUID, or 0)
function LayerNet.OnAddonMessage(partyLens, prefix, text, _, sender)
    if prefix ~= LayerNet.PREFIX or not sender or sender == "" or SameAsPlayer(sender) then
        return
    end
    local proto, kind, mapID, zoneUID, f5, f6 = strsplit("|", text or "")
    if proto ~= LayerNet.NET_PROTO then
        return
    end
    mapID, zoneUID = tonumber(mapID), tonumber(zoneUID)
    -- 0/0 means the peer hasn't sighted an NPC yet — don't pollute the shared set.
    if mapID and zoneUID and mapID > 0 and zoneUID > 0 then
        Layer.MergeSeen(partyLens, mapID, { zoneUID })
    end
    if kind == "S" then
        MergeCSV(partyLens, mapID, f6) -- full set -> convergence
        RecordNode(partyLens, sender, mapID, zoneUID, f5 == "1")
        LayerNet.Refresh(partyLens)
    elseif kind == "R" then
        local targetZone = tonumber(f6)
        if targetZone and targetZone > 0 then
            Layer.MergeSeen(partyLens, mapID, { targetZone }) -- learn the wanted layer's id
        else
            targetZone = nil
        end
        RecordNode(partyLens, sender, mapID, zoneUID, false)
        local req = ReqFromSpec(f5)
        local rt = RT(partyLens)
        rt.requests[Key(sender)] = {
            name = Utils.PlayerShortName(sender), req = req, t = time(),
            source = "net", targetZone = targetZone, mapID = mapID,
        }
        if CFG(partyLens).beacon and RequestMatches(partyLens, req, targetZone, mapID, true) then
            LayerNet.Engage(partyLens, sender, req)
        end
        LayerNet.Refresh(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Silent party auto-cleanup: invitees should hop then leave; drop stragglers so
-- the party stays open. Timer-driven, BUT UninviteUnit is #hwevent-gated on this
-- client (unlike InviteUnit) — calling it from the timer raises ADDON_ACTION_BLOCKED.
-- So we QUEUE stragglers here and actually remove them from FlushPendingKick, which
-- runs on real mouse events (hardware-blessed) — silent, no error popup.
-- ---------------------------------------------------------------------------
local function CleanParty(partyLens)
    if not Roster.CanInvite() then
        return
    end
    local rt = RT(partyLens)
    local now = time()
    rt.pendingKick = rt.pendingKick or {}
    -- rt.party[key] is +invitedAt while pending, then flipped to -joinedAt the
    -- first tick we see them in-group. The hold clock runs from JOIN, so a slow
    -- accept can't get auto-uninvited the instant they finally arrive.
    for key, ts in pairs(rt.party) do
        if Roster.IsInGroup(key) then
            if ts >= 0 then
                rt.party[key] = -now -- just joined: start the hold clock now
            elseif (now - (-ts)) >= LayerNet.PARTY_HOLD then
                rt.party[key] = nil
                rt.pendingKick[key] = true -- drained on a hardware event
            end
        elseif ts >= 0 and (now - ts) >= LayerNet.PARTY_HOLD then
            rt.party[key] = nil -- never showed up; stop tracking (no uninvite needed)
        end
    end
end

-- Remove ONE queued straggler. UninviteUnit is hardware-event-gated, so this only
-- ever runs from a real mouse event (see the WorldFrame hook in InstallFilters) —
-- the operator generates those constantly during play, so the party still drains,
-- silently and without the ADDON_ACTION_BLOCKED popup a timer call would raise.
function LayerNet.FlushPendingKick(partyLens)
    if not CFG(partyLens).beacon then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local rt = RT(partyLens)
    local q = rt.pendingKick
    if not q then
        return
    end
    for key in pairs(q) do
        q[key] = nil
        if UninviteUnit and Roster.IsInGroup(key) then
            pcall(UninviteUnit, key)
        end
        return -- one per hardware event is plenty
    end
end

-- ---------------------------------------------------------------------------
-- Party-frame hide ("magic" silence): a beacon forms groups to hop people, so
-- hide the party unit frames while beaconing. Uses SetAlpha(0) + EnableMouse
-- (visual only) rather than :Hide() — SetAlpha isn't combat-blocked and doesn't
-- taint the secure path the way hiding a protected frame does. Re-applied on
-- roster changes because the game re-shows/re-lays-out frames when the group
-- changes. Covers both classic (PartyMemberFrameN) and modern (PartyFrame/
-- CompactPartyFrame) layouts; missing ones are simply skipped.
-- ---------------------------------------------------------------------------
-- Party unit-frame containers to hide. Covers the default Blizzard frames plus
-- the popular replacement UIs (people run these instead of the Blizzard frames),
-- since the "party frame" is whatever addon the player uses. Unknown frames are
-- simply skipped; add more names as they turn up via "/partylens layerframe".
local PARTY_FRAME_NAMES = {
    -- Blizzard (classic + modern)
    "PartyFrame", "CompactPartyFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
    -- ElvUI
    "ElvUF_Party", "ElvUF_PartyGroup1",
    -- Shadowed Unit Frames
    "SUFHeaderparty", "SUFHeaderpartyHeader",
    -- Others
    "GwPartyFrame", "PitBull4_Groups_Party", "SArena",
}
local hookedPartyFrames = {}
local function ApplyPartyHide(partyLens, hide)
    local a = hide and 0 or 1
    -- The party unit frames are SECURE (Blizzard CompactUnitFrames, ElvUI oUF
    -- SecureUnitButtons, etc.). SetAlpha is cosmetic and safe on them, but
    -- EnableMouse is a PROTECTED method — calling it on a secure frame from our
    -- (insecure) timer raises ADDON_ACTION_BLOCKED ("protected function UNKNOWN()").
    -- So: always SetAlpha (the actual hide), and only touch EnableMouse on
    -- UNPROTECTED frames while out of combat.
    local inCombat = InCombatLockdown and InCombatLockdown()
    for _, name in ipairs(PARTY_FRAME_NAMES) do
        local f = _G[name]
        if f and f.SetAlpha then
            -- Lazily hook OnShow so any re-show (roster change / ElvUI relayout)
            -- re-applies the hidden alpha while beaconing. Setting alpha doesn't
            -- fire OnShow, so there's no recursion.
            if not hookedPartyFrames[name] and f.HookScript then
                hookedPartyFrames[name] = true
                f:HookScript("OnShow", function(self)
                    local c = CFG(partyLens)
                    if c.beacon and c.hideParty then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end
            pcall(f.SetAlpha, f, a)
            local protected = f.IsProtected and f:IsProtected()
            if f.EnableMouse and not protected and not inCombat then
                pcall(f.EnableMouse, f, not hide)
            end
        end
    end
end

-- Applies the current desired party-frame state (hidden iff beaconing + opted in).
function LayerNet.RefreshPartyHide(partyLens)
    local cfg = CFG(partyLens)
    ApplyPartyHide(partyLens, cfg.beacon and cfg.hideParty)
end

-- Called from GROUP_ROSTER_UPDATE: re-hide (the game re-shows frames on change)
-- and let CleanParty/Refresh react to who joined/left.
function LayerNet.OnRosterUpdate(partyLens)
    if CFG(partyLens).beacon then
        LayerNet.RefreshPartyHide(partyLens)
    end
    LayerNet.Refresh(partyLens)
end

-- ---------------------------------------------------------------------------
-- Tick: prune, (beacon) announce + clean.
-- ---------------------------------------------------------------------------
local function Prune(rt)
    local now = time()
    for k, r in pairs(rt.requests) do
        if (now - r.t) > LayerNet.REQUEST_TTL then rt.requests[k] = nil end
    end
    for k, n in pairs(rt.nodes) do
        if (now - n.t) > LayerNet.NODE_TTL then rt.nodes[k] = nil end
    end
end

function LayerNet.Tick(partyLens)
    local rt = RT(partyLens)
    local cfg = CFG(partyLens)
    Prune(rt)
    Layer.PruneSeen(partyLens) -- age out dead layers on a fixed cadence (keeps ordinals aligned)
    -- Presence / numbering sync: broadcast our sighting (a hidden ADDON message,
    -- which is NOT hardware-gated — unlike a visible SendChatMessage to a CHANNEL)
    -- so everyone's layer NUMBERS converge. Only active participants chatter.
    if cfg.beacon or rt.myRequest then
        if (time() - (rt.lastSync or 0)) >= LayerNet.SYNC_INTERVAL then
            rt.lastSync = time()
            LayerNet.BroadcastSighting(partyLens)
        end
    end
    -- Keep my own layer request alive on the mesh (invisible) until it's served
    -- or expires, so a beacon that arrives on my wanted layer later still pulls me.
    -- Clear it once my group GREW past its size at request time (someone pulled me
    -- in) or the TTL lapses. (Comparing to the recorded baseline, not ">0", so a
    -- requester who was already grouped isn't dropped on the very next tick.)
    if rt.myRequest then
        local sz = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        if sz > (rt.myRequest.size0 or 0)
            or (time() - (rt.myRequest.t or 0)) > LayerNet.MY_REQUEST_TTL then
            rt.myRequest = nil
        elseif (time() - (rt.myRequest.lastNet or 0)) >= LayerNet.SYNC_INTERVAL then
            LayerNet.SendMyRequest(partyLens, false)
        end
    end
    if cfg.beacon then
        CleanParty(partyLens)
        -- Re-engage still-open requests: Engage is otherwise only fired once, from
        -- the inbound chat event. A transient guard there (combat, rate cap, per-name
        -- cooldown, no invite rights, momentarily-full party) drops the invite while
        -- the request stays "open" for REQUEST_TTL, so retry here until it clears or
        -- expires. Engage is idempotent (its own cooldown/rate/in-group guards).
        for _, r in pairs(rt.requests) do
            if RequestMatches(partyLens, r.req, r.targetZone, r.mapID, r.source == "net") then
                LayerNet.Engage(partyLens, r.name, r.req)
            end
        end
        LayerNet.RefreshPartyHide(partyLens) -- catch-all re-hide (survives resets)
    end
    LayerNet.Refresh(partyLens)
end

function LayerNet.Start(partyLens)
    LayerNet.RegisterPrefix() -- so CHAT_MSG_ADDON fires for our mesh prefix
    local rt = RT(partyLens)
    if rt.ticker then
        return
    end
    if C_Timer and C_Timer.NewTicker then
        rt.ticker = C_Timer.NewTicker(LayerNet.TICK, function() LayerNet.Tick(partyLens) end)
    end
    LayerNet.Tick(partyLens)
    LayerNet.RefreshPartyHide(partyLens) -- honor a persisted beacon state on load
end

-- ---------------------------------------------------------------------------
-- Beacon toggle (bound to a right-click on the Layer tab / button)
-- ---------------------------------------------------------------------------
function LayerNet.SetBeacon(partyLens, on)
    local cfg = CFG(partyLens)
    cfg.beacon = on and true or false
    local rt = RT(partyLens)
    rt.lastSync = 0 -- announce our presence to the mesh on the next tick
    if cfg.beacon then
        Utils.Print(L("LAYER_BEACON_ON"))
        LayerNet.Tick(partyLens)
    else
        Utils.Print(L("LAYER_BEACON_OFF"))
    end
    LayerNet.RefreshPartyHide(partyLens) -- hide/restore the party frames
    LayerNet.Refresh(partyLens)
end

function LayerNet.ToggleBeacon(partyLens)
    LayerNet.SetBeacon(partyLens, not CFG(partyLens).beacon)
end

-- ---------------------------------------------------------------------------
-- Requester side: "I want to hop to a layer." Two prongs so I get pulled either
-- way: (1) an INVISIBLE mesh request so every PartyLens beacon on the wanted
-- layer auto-invites me (cross-layer), and (2) ONE signed, human-readable line
-- in public chat so manual inviters / other layer addons help too — and everyone
-- sees the addon's name. The request stays active for MY_REQUEST_TTL, re-pinging
-- the mesh each tick. Must be triggered by a HARDWARE event (button/slash): the
-- visible post uses SendChatMessage to a CHANNEL, which is click-gated here.
-- ---------------------------------------------------------------------------
local function FirstLayer(req)
    local nums = {}
    for n in pairs(req.layers or {}) do
        nums[#nums + 1] = n
    end
    table.sort(nums)
    return nums[1]
end

-- Push my active request onto the mesh; optionally also post the visible chat
-- line (only from a hardware event, so we pass includeVisible=false from timers).
function LayerNet.SendMyRequest(partyLens, includeVisible)
    local mr = RT(partyLens).myRequest
    if not mr then
        return
    end
    local cur = Layer.Current(partyLens)
    -- Resolve the primary requested NUMBER to its absolute zoneUID in MY (converged)
    -- frame, and send THAT so the beacon matches on zoneUID identity, not on a bare
    -- number the two clients might disagree about. 0 = unresolved / any.
    local target = 0
    if not mr.req.any then
        local n = FirstLayer(mr.req)
        if n then
            target = Layer.ZoneUIDAt(partyLens, cur.mapID, n) or 0
        end
    end
    SendNet(table.concat({
        LayerNet.NET_PROTO, "R", tostring(cur.mapID or 0), tostring(cur.zoneUID or 0),
        mr.spec, tostring(target),
    }, "|"))
    mr.lastNet = time()
    if includeVisible then
        local num = LFGChannelNumber()
        if num then
            local line
            if mr.req.any then
                line = L("LAYER_REQ_CHAT_ANY")
            elseif mr.req.exclude then
                line = L("LAYER_REQ_CHAT_EXCEPT", FirstLayer(mr.req) or "?")
            else
                line = L("LAYER_REQ_CHAT", FirstLayer(mr.req) or "?")
            end
            Utils.SendChat(line, "CHANNEL", nil, num)
        end
    end
end

-- Start (or replace) my own layer request. `spec`: "any", "" (=any), a number,
-- "5,7", or "!4". Call from a click/slash. Records the group size now so the tick
-- only cancels the request once the group actually GROWS (I've been pulled).
function LayerNet.RequestLayer(partyLens, spec)
    local req = ReqFromSpec(tostring(spec or ""))
    local rt = RT(partyLens)
    rt.myRequest = {
        req = req, spec = SpecFromReq(req), t = time(), lastNet = 0,
        size0 = (GetNumGroupMembers and GetNumGroupMembers()) or 0,
    }
    LayerNet.SendMyRequest(partyLens, true)
    LayerNet.Log(partyLens, L("LAYER_LOG_REQUESTED", LayerNet.RequestText(req)))
    LayerNet.Refresh(partyLens)
end

function LayerNet.CancelRequest(partyLens)
    RT(partyLens).myRequest = nil
    LayerNet.Refresh(partyLens)
end

-- My active request (or nil) — for the panel.
function LayerNet.MyRequest(partyLens)
    return RT(partyLens).myRequest
end

-- ---------------------------------------------------------------------------
-- Stats (marketing: live network counters)
-- ---------------------------------------------------------------------------
function LayerNet.Stats(partyLens)
    local rt = RT(partyLens)
    local cur = Layer.Current(partyLens)
    -- nodes = every PartyLens peer heard (network reach). covered = distinct layers
    -- a BEACON is actually sitting on (a hoppable destination), numbered in OUR
    -- converged frame via the shared zoneUID set (not the peer's raw ordinal).
    local nodes, coveredSet = 0, {}
    for _, n in pairs(rt.nodes) do
        nodes = nodes + 1
        if n.beacon and n.mapID and n.zoneUID then
            local ord = Layer.OrdinalOf(partyLens, n.mapID, n.zoneUID)
            if ord then coveredSet[ord] = true end
        end
    end
    if CFG(partyLens).beacon and cur.ordinal then
        coveredSet[cur.ordinal] = true
        nodes = nodes + 1 -- count myself
    end
    local covered = 0
    for _ in pairs(coveredSet) do covered = covered + 1 end
    local openReq = 0
    for _ in pairs(rt.requests) do openReq = openReq + 1 end
    return {
        nodes = nodes,
        layersCovered = covered,
        hops = CFG(partyLens).hops or 0,
        openRequests = openReq,
        myLayer = cur.ordinal,
        myLayerCount = cur.count,
    }
end

-- The layers we know about on our CURRENT map, for the picker. Each entry:
-- { ordinal, zoneUID, isCurrent, hasBeacon, nodes }. hasBeacon = a node is live on
-- that layer right now (a real hoppable destination); isCurrent = the layer I'm on.
function LayerNet.KnownLayers(partyLens)
    local cur = Layer.Current(partyLens)
    local mapID = cur.mapID
    local rt = RT(partyLens)
    local beaconOn, nodeCount = {}, {}
    for _, n in pairs(rt.nodes) do
        if n.mapID == mapID and n.zoneUID then
            nodeCount[n.zoneUID] = (nodeCount[n.zoneUID] or 0) + 1
            if n.beacon then beaconOn[n.zoneUID] = true end
        end
    end
    if CFG(partyLens).beacon and cur.zoneUID then
        beaconOn[cur.zoneUID] = true -- I'm a live beacon on my own layer
    end
    local out = {}
    for i, z in ipairs(Layer.KnownZones(partyLens, mapID)) do
        out[i] = {
            ordinal = i,
            zoneUID = z,
            isCurrent = (z == cur.zoneUID),
            hasBeacon = beaconOn[z] == true,
            nodes = nodeCount[z] or 0,
        }
    end
    return out
end

-- Open requests seen on chat, newest first (for the UI list).
function LayerNet.OpenRequests(partyLens)
    local rt = RT(partyLens)
    local list = {}
    for _, r in pairs(rt.requests) do
        list[#list + 1] = r
    end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return list
end

-- Human label for a parsed request: "any", "L3", "L3, L5", or "≠ L4".
function LayerNet.RequestText(req)
    if not req then
        return ""
    end
    if req.any then
        return L("LAYER_ANY")
    end
    local nums = {}
    for n in pairs(req.layers or {}) do
        nums[#nums + 1] = n
    end
    table.sort(nums)
    for i, n in ipairs(nums) do
        nums[i] = "L" .. n
    end
    local s = table.concat(nums, ", ")
    return req.exclude and ("\226\137\160 " .. s) or s
end

-- Recent activity log (newest first).
function LayerNet.RecentLog(partyLens)
    return RT(partyLens).log or {}
end

-- Beacon status for the panel: (text, isWarning). Explains why it is / isn't
-- inviting, so a silent beacon is never a mystery.
function LayerNet.Status(partyLens)
    local cfg = CFG(partyLens)
    if not cfg.beacon then
        return L("LAYER_STATUS_OFF"), false
    end
    local cur = Layer.Current(partyLens)
    if not cur.ordinal then
        return L("LAYER_STATUS_NOLAYER"), true
    end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n >= 5 then
        return L("LAYER_STATUS_FULL"), true
    end
    return L("LAYER_STATUS_LISTENING", cur.ordinal, n), false
end

-- Harvest a layer sighting from a unit (target/mouseover/nameplate). On a change
-- refresh the UI and, if we're an active participant, push our new layer to the
-- mesh right away (a hidden ADDON message — not hardware-gated) so beacons/peers
-- learn our current layer the moment we hop, and numbering stays converged.
function LayerNet.Observe(partyLens, unit)
    if Layer.Observe(partyLens, unit) then
        local rt = RT(partyLens)
        if CFG(partyLens).beacon or rt.myRequest then
            rt.lastSync = time()
            LayerNet.BroadcastSighting(partyLens)
        end
        LayerNet.Refresh(partyLens)
    end
end

-- Routes a CHAT_MSG_CHANNEL line from an enabled PUBLIC channel
-- (Trade/General/World/LFG) into a layer request. PartyLens-to-PartyLens
-- coordination rides hidden addon messages (OnAddonMessage), not visible chat.
function LayerNet.OnChannelChat(partyLens, msg, sender, baseName)
    local lname = Utils.SafeLower(baseName or "")
    local source
    -- A dedicated layer channel (named "Layer"/"Camada") is where hopping happens;
    -- flag it so ParseRequest accepts bare "5" / "inv 4" without the word "layer".
    if string.find(lname, "layer", 1, true) or string.find(lname, "camada", 1, true) then
        source = "layer"
    elseif string.find(lname, "trade", 1, true) or string.find(lname, "com\195\169rcio", 1, true) then
        source = "trade"
    elseif string.find(lname, "world", 1, true) then
        source = "world"
    elseif string.find(lname, "lookingforgroup", 1, true) or string.find(lname, "procurando", 1, true) then
        source = "lookingforgroup"
    elseif string.find(lname, "general", 1, true) or string.find(lname, "geral", 1, true) then
        source = "general"
    end
    -- Custom/server channels (e.g. "World", "Global", "LFG", "OpenLayer") don't
    -- match the four named types but are exactly where layer hopping happens — scan
    -- them too. Enabled by default (channels.channel is nil, not false); ParseRequest
    -- still requires a "layer"/"camada" trigger, so non-layer chatter is ignored.
    if not source then
        source = "channel"
    end
    local channels = CFG(partyLens).channels
    if channels and channels[source] == false then
        return
    end
    LayerNet.OnRequest(partyLens, msg, sender, source)
end

-- UI hook (implemented by UIMain when the Layer tab exists).
function LayerNet.Refresh(partyLens)
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.RefreshLayer then
        UIMain.RefreshLayer(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Silencing filters (registered once; each no-ops while the beacon is off)
-- ---------------------------------------------------------------------------
local function BuildSystemPatterns()
    local names = {
        "ERR_INVITE_PLAYER_S", "ERR_JOINED_GROUP_S", "ERR_DECLINE_GROUP_S",
        "ERR_LEFT_GROUP_S", "ERR_LEFT_GROUP_YOU", "ERR_GROUP_DISBANDED",
        "ERR_ALREADY_IN_GROUP_S", "ERR_RAID_MEMBER_ADDED_S", "ERR_RAID_MEMBER_REMOVED_S",
    }
    local patterns = {}
    for _, g in ipairs(names) do
        local s = _G[g]
        if type(s) == "string" then
            -- Escape Lua magic chars, then turn %s / %d format tokens into captures.
            local p = string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            p = string.gsub(p, "%%%%[sd]", ".+")
            patterns[#patterns + 1] = p
        end
    end
    return patterns
end

function LayerNet.InstallFilters(partyLens)
    if LayerNet._filtersInstalled then
        return
    end
    LayerNet._filtersInstalled = true
    local sysPatterns = BuildSystemPatterns()

    -- Party join/leave/decline spam.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if not CFG(partyLens).beacon then
            return false
        end
        for _, p in ipairs(sysPatterns) do
            if string.match(msg, p) then
                return true
            end
        end
        return false
    end)

    -- Our own outgoing instruction whispers: hide the sender-side echo when it's
    -- our signed "[PartyLens]:" line OR simply addressed to someone we invited.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(_, _, msg, target)
        if not CFG(partyLens).beacon then
            return false
        end
        if string.sub(msg or "", 1, #Utils.CHAT_SIGN) == Utils.CHAT_SIGN then
            return true
        end
        if RT(partyLens).party[Key(target or "")] then
            return true
        end
        return false
    end)

    -- Incoming whispers: hide layer-request lines AND any follow-up ("ty",
    -- "which one?") from people currently in our request/invite flow, so the
    -- beacon stays silent (AutoLayer leaves these visible).
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", function(_, _, msg, author)
        if not CFG(partyLens).beacon then
            return false
        end
        if LayerNet.ParseRequest(msg) then
            return true
        end
        local rt = RT(partyLens)
        local k = Key(author or "")
        if rt.party[k] or rt.requests[k] then
            return true
        end
        return false
    end)

    -- Message filters can't stop WoW from OPENING a temporary whisper tab. Hook
    -- the window-opener and immediately close any whisper tab spawned for someone
    -- in our layer flow — the piece AutoLayer is missing. (Only temp windows.)
    if FCF_OpenTemporaryWindow and hooksecurefunc then
        hooksecurefunc("FCF_OpenTemporaryWindow", function(chatType, chatTarget)
            if not CFG(partyLens).beacon or chatType ~= "WHISPER" or not chatTarget then
                return
            end
            local rt = RT(partyLens)
            local k = Key(chatTarget)
            if rt.party[k] or rt.requests[k] then
                LayerNet.CloseWhisperWindow(chatTarget)
            end
        end)
    end

    -- Hardware-event drain for the auto-uninvite: UninviteUnit is #hwevent-gated,
    -- so it can't run from the timer. WorldFrame OnMouseDown fires on real clicks
    -- (which a playing beacon generates constantly), giving us a blessed context to
    -- remove one queued straggler at a time — silently, no ADDON_ACTION_BLOCKED.
    if WorldFrame and WorldFrame.HookScript then
        pcall(WorldFrame.HookScript, WorldFrame, "OnMouseDown", function()
            LayerNet.FlushPendingKick(partyLens)
        end)
    end
end

_G[ADDON_NAME .. "_LayerNet"] = LayerNet
return LayerNet
