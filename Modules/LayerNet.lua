local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local Net = _G[ADDON_NAME .. "_Net"]

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
-- Coordination + presence ride hidden addon messages (see Modules/Net.lua).
-- Addon messages over the CHANNEL distribution are BLOCKED on this client
-- (SendAddonMessage returns 4), so there is NO automatic realm-wide hidden bus:
-- presence/sightings sync over GUILD + SAY proximity, while the REALM-WIDE reach
-- for "get me to layer N" comes from the requester's signed VISIBLE post (which
-- is hardware-gated but every beacon scans it). See /partylens netdiag.
-- ===========================================================================

-- The mesh sends hidden ADDON messages via Net (guild + proximity). Its own
-- prefix keeps it separate from the Browse ("PartyLens") traffic.
LayerNet.PREFIX = "PLLnet"            -- addon-message prefix for the layer mesh
LayerNet.NET_PROTO = "PLL1"           -- payload protocol tag
LayerNet.TICK = 5
LayerNet.SYNC_INTERVAL = 30           -- presence/sighting broadcast cadence (numbering sync)
LayerNet.PRESENCE_INTERVAL = 60       -- idle layer-presence cadence (feeds the occupancy map); under NODE_TTL
LayerNet.MAX_PER_MINUTE = 10          -- invites/min (racing to win clients; still bounded)
LayerNet.CONTACT_COOLDOWN = 90        -- per-name cooldown
LayerNet.NODE_TTL = 600               -- a node counts as "online" if heard within this (long,
                                      -- because realm-wide presence is sparse/click-flushed —
                                      -- otherwise real peers flicker out between rare flushes)
LayerNet.GOSSIP_INTERVAL = 120        -- how often to gossip known nodes realm-wide (multi-hop, aged)
LayerNet.GOSSIP_MAX = 8               -- nodes per gossip digest (fits the ~255-char channel line)
LayerNet.BRIDGE_COOLDOWN = 20         -- min gap between party-bridge bursts (cross-layer seeding)
LayerNet.REQUEST_TTL = 60             -- an inbound request stays "open" this long
LayerNet.MY_REQUEST_TTL = 120         -- my own layer request stays active/re-broadcast this long
LayerNet.PARTY_HOLD = 40              -- auto-uninvite an invitee still around after this (they hop fast)
LayerNet.LOG_MAX = 20                 -- recent-activity log lines kept
LayerNet.PARK_GRACE = 90             -- keep auto-beacon on this long after the last "parked/idle"
                                      -- signal, so it doesn't flicker between e.g. fishing casts

-- Beacon-service ranks by LIFETIME hops served — a visible status reward for running
-- a node (and the signal a requester carries to earn hop priority under contention).
LayerNet.RANKS = {
    { min = 1000, key = "LAYER_RANK_LEGEND" },
    { min = 250,  key = "LAYER_RANK_WARDEN" },
    { min = 75,   key = "LAYER_RANK_GUARDIAN" },
    { min = 20,   key = "LAYER_RANK_GUIDE" },
    { min = 1,    key = "LAYER_RANK_HELPER" },
}
function LayerNet.Rank(hops)
    for _, r in ipairs(LayerNet.RANKS) do
        if (hops or 0) >= r.min then
            return L(r.key), r.min
        end
    end
    return nil -- no rank until the first hop served
end

local function CFG(partyLens)
    partyLens.db.layer = partyLens.db.layer or {}
    local c = partyLens.db.layer
    c.channels = c.channels or { trade = true, general = true, lookingforgroup = true, world = true }
    if c.whisper == nil then c.whisper = true end -- default on (marketing); backfills old saves
    if c.hideParty == nil then c.hideParty = true end -- hide the party frame while beaconing
    if c.autoBeacon == nil then c.autoBeacon = true end -- park-and-help ON by default (opt-out);
                                                        -- maximizes node supply, painless + silent
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
            lastGossip = 0,     -- last time we gossiped our directly-heard nodes realm-wide
            lastParked = nil,   -- last time we looked "parked/idle" (auto-beacon grace window)
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
    -- Diagnostic: with `/partylens hopdebug` on, log WHY an invite doesn't fire, so a
    -- beacon's otherwise-silent guards (party full, cooldown, no rights...) are visible
    -- while testing. No-op when hopdebug is off.
    local function bail(reason)
        if CFG(partyLens).hopdebug then
            LayerNet.Log(partyLens, "skip " .. Utils.PlayerShortName(name) .. ": " .. reason)
        end
    end
    if InCombatLockdown and InCombatLockdown() then
        return bail("combat")
    end
    -- Party already full: a name-invite would be silently rejected by the server.
    -- Bail BEFORE spending a cooldown/rate slot or logging a phantom "invited" —
    -- CleanParty frees hopper slots and the tick retry re-engages once there's room.
    if ((GetNumGroupMembers and GetNumGroupMembers()) or 0) >= 5 then
        return bail("party full")
    end
    if not Roster.CanInvite() then
        return bail("no invite rights (not group leader)")
    end
    if Roster.IsInGroup(name) then
        return bail("already in my group")
    end
    if not CanContact(rt, name) then
        return bail("per-name cooldown")
    end
    if not WithinRate(rt) then
        return bail("rate cap")
    end

    -- INVITE FIRST — literally the first action after the guards, before ANY other
    -- work (layer lookup, whisper, logging), so we beat other layer addons reacting
    -- to the same line. Every millisecond here decides who gets the client.
    local short = Utils.PlayerShortName(name)
    DoInvite(short)

    -- Everything below is post-invite bookkeeping (doesn't gate the invite).
    local cfg = CFG(partyLens)
    local cur = Layer.Current(partyLens)
    if cfg.whisper then
        Utils.SendChat(L("LAYER_WHISPER", cur.ordinal or "?"), "WHISPER", nil, short)
        SilenceWhisperFor(short)
    end
    RecordContact(rt, name)
    rt.party[Key(name)] = time()
    -- hops is counted on the actual JOIN (CleanParty), not here — an invite that's
    -- declined / never accepted shouldn't inflate "hops served".
    LayerNet.Log(partyLens, L("LAYER_LOG_INVITED", short, cur.ordinal or "?"))
end

-- ---------------------------------------------------------------------------
-- Inbound chat: record the request (for the UI) and, as a beacon, engage on match
-- ---------------------------------------------------------------------------
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

    -- OPTIMISTIC INVITE FIRST: the moment we have a matching request, fire the invite
    -- BEFORE any bookkeeping or UI repaint. The UI refresh (chips/stats/log) is the
    -- slow part; running it before the invite is exactly what let other layer addons
    -- beat us to the client. Public-chat/whisper requests have no mesh target zoneUID,
    -- so matching falls back to the ordinal compare.
    local cfg = CFG(partyLens)
    if cfg.beacon and RequestMatches(partyLens, req, nil, nil, false) then
        LayerNet.Engage(partyLens, sender, req)
    end

    -- Post-invite bookkeeping: record the request, log it once, silence the whisper.
    local rt = RT(partyLens)
    local key = Key(sender)
    local isNew = rt.requests[key] == nil
    rt.requests[key] = { name = Utils.PlayerShortName(sender), req = req, t = time(), source = source }
    if cfg.beacon and source == "whisper" then
        SilenceWhisperFor(sender)
    end
    if isNew then
        LayerNet.Log(partyLens, L("LAYER_LOG_SEEN", Utils.PlayerShortName(sender), LayerNet.RequestText(req)))
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

-- Fire-and-forget hidden addon broadcast to the layer mesh. CHANNEL is blocked
-- on this client, so route over the buses that deliver from a timer: GUILD
-- (guildmates) + SAY proximity (same area / same layer neighbours). Instrumented
-- via Net.Stats so it can never fail silently again.
-- Guild + current party/raid + SAY proximity = the fast, automatic LOCAL delivery.
-- When `realmKey` is given, ALSO queue the same payload on the realm-wide bus
-- (dedicated addon channel, click-flushed) coalesced under LayerNet.PREFIX..realmKey
-- so a random PartyLens user across the realm eventually gets it too. Only the
-- LATEST payload per key is kept, so this can't flood the channel.
local function SendNet(payload, realmKey)
    local sentGuild = Net.Guild(LayerNet.PREFIX, payload)
    local sentGroup = Net.Group(LayerNet.PREFIX, payload)
    local sentNear = Net.Proximity(LayerNet.PREFIX, payload)
    if realmKey and Net.Realm then
        Net.Realm(LayerNet.PREFIX, payload, LayerNet.PREFIX .. ":" .. realmKey)
    end
    return sentGuild or sentGroup or sentNear
end

function LayerNet.RegisterPrefix()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then
        pcall(register, LayerNet.PREFIX)
    end
end

-- Public broadcast over the mesh. Pass a realmKey to also reach realm-wide (the
-- world-boss radar passes "W:<npc>", reputation passes "VD"). Without it, local only.
function LayerNet.Broadcast(payload, realmKey)
    return SendNet(payload, realmKey)
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

-- Broadcast our current layer sighting to the mesh (presence + numbering sync +
-- occupancy). No-op until we've detected a zoneUID. Callers gate the cadence:
-- active participants (beacon/requester) chatter fast; idle users share slower.
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
    }, "|"), "S") -- realm-wide too (coalesced to my latest seen-set)
end

-- Build the SD node digest: "SD|name:map:zone:beacon:age;..." of the nodes we know,
-- beacons first then freshest, aged, capped to fit the ~255-char line. Returns nil when
-- we know nothing shareable. Shared by GossipNodes (realm), BridgeToGroup (party) and
-- BridgeForward (yell) so every path emits the exact same wire format.
local function BuildNodeDigest(partyLens)
    local now = time()
    local list = {}
    for _, n in pairs(RT(partyLens).nodes) do
        -- ALL known nodes — first-hand AND relayed — so data spreads MULTI-HOP
        -- (anti-entropy gossip). Each entry carries the node's AGE; the age grows ~one
        -- gossip cycle per relay, so an item dies once older than NODE_TTL. Combined
        -- with "freshest wins" on receive, this can't loop forever.
        if n.name and n.zoneUID and n.mapID and not SameAsPlayer(n.name)
            and (now - (n.t or 0)) < LayerNet.NODE_TTL then
            list[#list + 1] = n
        end
    end
    if #list == 0 then
        return nil
    end
    table.sort(list, function(a, b)
        if (a.beacon and true) ~= (b.beacon and true) then
            return a.beacon and true or false -- beacons first (most useful to share)
        end
        return (a.t or 0) > (b.t or 0) -- then most-recently heard
    end)
    local parts, used = {}, 0
    for i = 1, #list do
        if #parts >= LayerNet.GOSSIP_MAX then
            break
        end
        local n = list[i]
        -- name:mapID:zoneUID:beacon:ageSeconds (names are letters-only -> ':'/';' safe)
        local age = math.max(0, math.min(now - (n.t or now), 99999))
        local entry = table.concat({
            n.name, tostring(n.mapID), tostring(n.zoneUID), n.beacon and "1" or "0", tostring(age),
        }, ":")
        local add = #entry + (used > 0 and 1 or 0) -- +1 for the ';' separator
        if used + add > 220 then -- keep the whole channel line under the ~255 limit
            break
        end
        parts[#parts + 1] = entry
        used = used + add
    end
    if #parts == 0 then
        return nil
    end
    return table.concat({ LayerNet.NET_PROTO, "SD", table.concat(parts, ";") }, "|")
end

-- Gossip our node digest out over the realm bus (YELL), so a single flush teaches many
-- peers at once (multi-hop epidemic spread — see the age/freshest-wins scheme above).
local function GossipNodes(partyLens)
    if not Net.Realm then
        return
    end
    local payload = BuildNodeDigest(partyLens)
    if payload then
        Net.Realm(LayerNet.PREFIX, payload, LayerNet.PREFIX .. ":SD")
    end
end

-- BRIDGE (cross-layer seeding via a shared party). A hop party is a GUARANTEED
-- cross-layer link: while a hopper is being pulled they briefly share the beacon's
-- group but still stand on their ORIGINAL layer. So on any roster change we push our
-- whole node digest over PARTY (cross-layer, reliable, targeted) — and the receiver's
-- SD handler re-YELLs it onto THEIR layer (BridgeForward), seeding a layer neither of
-- our own YELLs could reach. Cooldown-gated so a burst of roster updates fires once.
local function BridgeToGroup(partyLens)
    if not (IsInGroup and IsInGroup()) then
        return
    end
    if IsInInstance and IsInInstance() then
        return -- inside a dungeon/raid/BG everyone shares one instance: no layer to bridge
    end
    local rt = RT(partyLens)
    local now = time()
    if rt.lastBridge and (now - rt.lastBridge) < LayerNet.BRIDGE_COOLDOWN then
        return
    end
    local payload = BuildNodeDigest(partyLens)
    if not payload then
        return
    end
    rt.lastBridge = now
    Net.Group(LayerNet.PREFIX, payload)
end
LayerNet.BridgeToGroup = BridgeToGroup

-- Receiver half of the bridge: a digest that arrived over PARTY/RAID came from someone
-- who shares our group but is (probably) on ANOTHER layer — the beacon that invited us,
-- or a hopper who just joined. Re-YELL what we now know onto OUR current layer, which
-- their YELL couldn't reach. One-shot per join (cooldown), and only PARTY/RAID digests
-- trigger it — a YELLed digest never re-bridges, so this can't loop.
local function BridgeForward(partyLens)
    local rt = RT(partyLens)
    local now = time()
    if rt.lastBridgeFwd and (now - rt.lastBridgeFwd) < LayerNet.BRIDGE_COOLDOWN then
        return
    end
    local payload = BuildNodeDigest(partyLens)
    if not payload then
        return
    end
    rt.lastBridgeFwd = now
    Net.Yell(LayerNet.PREFIX, payload)
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
-- `via` is "direct" (we heard the peer's own S) or "gossip" (another peer relayed
-- them). For gossip, `age` is how many seconds ago the ORIGIN was actually seen (it
-- grew by ~one gossip cycle at each relay hop), so the peer's effective last-seen is
-- now-age, NOT now. Anti-entropy merge: keep whichever record is FRESHEST. A direct
-- hear (last-seen = now) always wins; a gossip only updates when it's strictly fresher
-- than what we already hold. That's what bounds the epidemic — you never accept, nor
-- re-share (see GossipNodes), a version older than one you have — so it can't loop, and
-- once age passes NODE_TTL the item is dropped everywhere.
local function RecordNode(partyLens, sender, mapID, zoneUID, isBeacon, via, age)
    local key = Key(sender)
    local nodes = RT(partyLens).nodes
    local existing = nodes[key]
    local seenAt = (via == "gossip") and (time() - (tonumber(age) or 0)) or time()
    if via == "gossip" and existing and (existing.t or 0) >= seenAt then
        return -- we already hold an equal-or-fresher record; don't age it backwards
    end
    nodes[key] = {
        name = Utils.PlayerShortName(sender),
        zoneUID = zoneUID,
        mapID = mapID,
        beacon = isBeacon and true or false,
        t = seenAt,
        direct = via ~= "gossip",
    }
end

-- Inbound addon-mesh message (CHAT_MSG_ADDON over the LFG channel).
--   S|mapID|curZone|beacon|setCSV        presence + full sighting set
--   R|mapID|curZone|spec|targetZone      a layer request (targetZone = wanted layer's zoneUID, or 0)
function LayerNet.OnAddonMessage(partyLens, prefix, text, dist, sender)
    if prefix ~= LayerNet.PREFIX or not sender or sender == "" or SameAsPlayer(sender) then
        return
    end
    local proto, kind, mapID, zoneUID, f5, f6, f7 = strsplit("|", text or "")
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
        RecordNode(partyLens, sender, mapID, zoneUID, f5 == "1", "direct")
        LayerNet.Refresh(partyLens)
    elseif kind == "R" then
        local req = ReqFromSpec(f5)
        local targetZone = tonumber(f6)
        if not (targetZone and targetZone > 0) then
            targetZone = nil
        end
        -- OPTIMISTIC INVITE FIRST — before merging sets / recording nodes / repaint.
        if CFG(partyLens).beacon then
            if RequestMatches(partyLens, req, targetZone, mapID, true) then
                LayerNet.Engage(partyLens, sender, req)
            elseif CFG(partyLens).hopdebug then
                -- Show the numbering both sides see, so a wrong-layer request is obvious.
                local mine = Layer.Current(partyLens)
                LayerNet.Log(partyLens, "no-match " .. Utils.PlayerShortName(sender)
                    .. ": wants z=" .. tostring(targetZone or "any") .. " map=" .. tostring(mapID)
                    .. " | me z=" .. tostring(mine.zoneUID or "?") .. " map=" .. tostring(mine.mapID or "?"))
            end
        end
        -- Post-invite bookkeeping.
        if targetZone then
            Layer.MergeSeen(partyLens, mapID, { targetZone }) -- learn the wanted layer's id
        end
        RecordNode(partyLens, sender, mapID, zoneUID, false, "direct")
        RT(partyLens).requests[Key(sender)] = {
            name = Utils.PlayerShortName(sender), req = req, t = time(),
            source = "net", targetZone = targetZone, mapID = mapID,
            hops = tonumber(f7) or 0, -- their served-hops, for reciprocity priority
        }
        LayerNet.Refresh(partyLens)
    elseif kind == "SD" then
        -- Presence gossip: "SD|name:map:zone:beacon:age;..." — merge the second-hand
        -- nodes a peer relayed, so one flush from anyone makes many peers visible, and
        -- they keep relaying onward (multi-hop anti-entropy). `age` (5th field) is how
        -- long ago the origin was seen; it grows per hop so items die past NODE_TTL.
        -- Re-split the raw text (digest sits where mapID/zoneUID would be, now nil'd).
        -- Missing age (older-format senders) is treated as fresh (age 0).
        local _, _, digest = strsplit("|", text or "")
        if digest and digest ~= "" then
            for item in string.gmatch(digest, "[^;]+") do
                local nm, mp, zn, bc, ag = strsplit(":", item)
                mp, zn = tonumber(mp), tonumber(zn)
                if nm and nm ~= "" and mp and zn and mp > 0 and zn > 0 and not SameAsPlayer(nm) then
                    Layer.MergeSeen(partyLens, mp, { zn }) -- learn the relayed layer's id
                    RecordNode(partyLens, nm, mp, zn, bc == "1", "gossip", tonumber(ag) or 0)
                end
            end
            LayerNet.Refresh(partyLens)
            -- CROSS-LAYER BRIDGE: a digest over PARTY/RAID came from a groupmate who is
            -- (probably) on another layer — a hopper mid-pull or the beacon. Re-YELL what
            -- we now know onto OUR layer to seed a layer their YELL can't reach. Only
            -- PARTY/RAID triggers it (a YELLed digest never re-bridges → no loop).
            if dist == "PARTY" or dist == "RAID" then
                BridgeForward(partyLens)
            end
        end
    elseif kind == "W" then
        -- World-boss sighting: W|mapID|bossZoneUID|npcID|hp. The boss's zoneUID was
        -- already merged above, so its layer can be numbered in our frame.
        local WB = _G[ADDON_NAME .. "_WorldBoss"]
        if WB and WB.OnMeshSighting then
            WB.OnMeshSighting(partyLens, mapID, zoneUID, tonumber(f5), tonumber(f6), Utils.PlayerShortName(sender))
        end
    elseif kind == "V" or kind == "VD" then
        -- Reputation: V|targetName (one vouch) or VD|name1,name2,... (voter's digest).
        -- Fields aren't numeric, so hand the RAW text to Reputation to re-split.
        local Rep = _G[ADDON_NAME .. "_Reputation"]
        if Rep and Rep.OnMesh then
            Rep.OnMesh(partyLens, kind, text, sender)
        end
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
    local cfg = CFG(partyLens)
    local now = time()
    rt.pendingKick = rt.pendingKick or {}
    -- rt.party[key] is +invitedAt while pending, then flipped to -joinedAt the
    -- first tick we see them in-group. The hold clock runs from JOIN, so a slow
    -- accept can't get auto-uninvited the instant they finally arrive.
    for key, ts in pairs(rt.party) do
        if Roster.IsInGroup(key) then
            if ts >= 0 then
                rt.party[key] = -now -- just joined: start the hold clock now
                -- A REAL hop: count it (once, on join) and log it. key is a lowercased
                -- short name — capitalise it for the log line.
                cfg.hops = (cfg.hops or 0) + 1
                LayerNet.Log(partyLens, L("LAYER_LOG_HOPPED", key:sub(1, 1):upper() .. key:sub(2)))
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
    -- Cross-layer seeding: push our node digest to the (new) party over PARTY, so a
    -- hopper mid-pull relays it onward to their origin layer (see BridgeToGroup).
    BridgeToGroup(partyLens)
    LayerNet.Refresh(partyLens)
end

-- Am I "parked / semi-idle" — a natural moment to donate my char as a hop node?
--   IsResting()      -> in ANY capital city or inn (rested area) — the main park spot.
--   UnitIsAFK()      -> flagged away anywhere.
--   channeling Fish  -> fishing, the canonical semi-idle activity.
local function ParkedIdle(partyLens)
    if IsResting and IsResting() then
        return true
    end
    if UnitIsAFK and UnitIsAFK("player") then
        return true
    end
    if UnitChannelInfo then
        local nm = UnitChannelInfo("player")
        if nm and nm ~= "" and nm == (PROFESSIONS_FISHING or "Fishing") then
            return true
        end
    end
    return false
end

-- Auto-beacon ("park and help"): whenever I'm parked in a city/inn or idle (fishing,
-- AFK), automatically become a hop node — zero effort, fully silenced. Starts only when
-- SOLO (never hijacks a real group I formed) but stays on through its own transient
-- hopper party; a grace window smooths brief idle drops (e.g. between fishing casts).
-- Driven from the tick, so SetBeacon runs `quiet`.
local function AutoBeaconApply(partyLens)
    local cfg = CFG(partyLens)
    if not cfg.autoBeacon then
        return
    end
    local rt = RT(partyLens)
    local now = time()
    if ParkedIdle(partyLens) then
        rt.lastParked = now
    end
    local parked = (rt.lastParked and (now - rt.lastParked) <= LayerNet.PARK_GRACE) and true or false

    local groupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local beaconing = cfg.beacon and true or false
    -- Stay on through a grown group ONLY if the extra members are hoppers WE invited
    -- (tracked in rt.party) — not a real group we formed while parked. Otherwise
    -- auto-beacon would start pulling strangers into your real party.
    local onlyHoppers = groupSize <= 1
    if not onlyHoppers and beaconing then
        onlyHoppers = true
        for i = 1, groupSize - 1 do
            local nm = UnitName("party" .. i)
            if nm and not rt.party[Key(nm)] then
                onlyHoppers = false
                break
            end
        end
    end

    local want = (parked and onlyHoppers) and true or false
    if want ~= beaconing then
        -- ON by default, so tell the user ONCE (the first time it actually kicks in)
        -- what's happening and how to opt out — then never again.
        if want and not cfg.autoBeaconNoticed then
            cfg.autoBeaconNoticed = true
            Utils.Print(L("LAYER_AUTOBEACON_NOTICE"))
        end
        LayerNet.SetBeacon(partyLens, want, true) -- quiet: no chat spam, no re-tick
    end
end

-- I was just pulled by a beacon (my group grew while a hop request was active): vouch
-- the group leader that helped me. Beaconing thus earns real, corroborated, hard-to-fake
-- trust — the supply-side reward. Once per target (Reputation.Vouch guards re-vouch).
-- Opt-out: db.layer.autoVouch = false.
local function ThankHelper(partyLens)
    if CFG(partyLens).autoVouch == false then
        return
    end
    local leader
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitIsGroupLeader and UnitIsGroupLeader(u) then
            leader = UnitName(u)
            break
        end
    end
    if leader and leader ~= "" and not SameAsPlayer(leader) then
        local Rep = _G[ADDON_NAME .. "_Reputation"]
        if Rep and Rep.Vouch then
            Rep.Vouch(partyLens, leader)
        end
    end
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
    AutoBeaconApply(partyLens) -- park-and-help: (de)activate the beacon by location
    -- Presence / numbering sync: broadcast our sighting (a hidden ADDON message,
    -- which is NOT hardware-gated — unlike a visible SendChatMessage to a CHANNEL)
    -- so everyone's layer NUMBERS converge AND the realm-wide occupancy map can see
    -- which layers people are on. Active participants (beacon/requester) chatter at
    -- the full cadence; idle users share their layer at a slower cadence so the map
    -- reflects the whole network, not just beacons (opt-out: db.layer.shareLayer=false).
    local active = cfg.beacon or rt.myRequest
    if active or cfg.shareLayer ~= false then
        local interval = active and LayerNet.SYNC_INTERVAL or LayerNet.PRESENCE_INTERVAL
        if (time() - (rt.lastSync or 0)) >= interval then
            rt.lastSync = time()
            LayerNet.BroadcastSighting(partyLens)
        end
    end
    -- Gossip every node we know (first-hand AND relayed) realm-wide, each tagged with
    -- its age, so presence spreads MULTI-HOP (anti-entropy) — reaching peers we never
    -- hear directly, even cross-zone via guildmates who relay onward. Age grows per hop
    -- so items self-expire past NODE_TTL; "freshest wins" on receive stops any loop.
    if cfg.shareLayer ~= false and (time() - (rt.lastGossip or 0)) >= LayerNet.GOSSIP_INTERVAL then
        rt.lastGossip = time()
        GossipNodes(partyLens)
    end
    -- Keep my own layer request alive on the mesh (invisible) until it's served
    -- or expires, so a beacon that arrives on my wanted layer later still pulls me.
    -- Clear it once my group GREW past its size at request time (someone pulled me
    -- in) or the TTL lapses. (Comparing to the recorded baseline, not ">0", so a
    -- requester who was already grouped isn't dropped on the very next tick.)
    if rt.myRequest then
        local sz = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        if sz > (rt.myRequest.size0 or 0) then
            rt.myRequest = nil
            ThankHelper(partyLens) -- pulled: vouch the beacon that helped me hop
        elseif (time() - (rt.myRequest.t or 0)) > LayerNet.MY_REQUEST_TTL then
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
        -- Under contention (rate cap / limited slots), serve requesters who have served
        -- more hops themselves FIRST — the reciprocity reward for running a beacon.
        local pending = {}
        for _, r in pairs(rt.requests) do
            pending[#pending + 1] = r
        end
        table.sort(pending, function(a, b) return (a.hops or 0) > (b.hops or 0) end)
        for _, r in ipairs(pending) do
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
    LayerNet.ApplyErrorSpeech(partyLens) -- ...and re-mute the error voice if beaconing
end

-- ---------------------------------------------------------------------------
-- Beacon toggle (bound to a right-click on the Layer tab / button)
-- Party/invite/join SOUND EFFECTS to silence while beaconing — the invite-accepted
-- "boop", the sound when someone joins, and the race/gender error voice sounds. The
-- error-speech CVar (below) doesn't cover the invite/join notification sounds, so we
-- also MuteSoundFile these specific ids (the tested set for exactly this scenario).
-- MuteSoundFile is per-session (cleared on reload), so it's re-applied from Start.
local MUTE_SOUNDS = {
    567490, 567451, -- invite sent / invite accepted
    539839, 540356, 540778, 540941, 540984, 542585, 542862, 540287, 540579,
    541222, 542952, 542659, 539901, 541298, 543146, 543174, -- join / "they can't join our group"
    539218, 539307, 539481, 539729, -- ...AlreadyInGroup (BE/Draenei)
    539272, 539274, 539663, 539503, 539844, 539947, 540320, 540404, 540798,
    540559, 540933, 540967, 541188, 541258, 542828, 542912, 543102, -- ...CantInvite (all races)
}

-- ---------------------------------------------------------------------------
-- Silence the beacon's party churn: mute the error voice-over ("they can't join
-- our group") AND the invite/join sound effects while beaconing. The error-speech
-- CVar original is saved in the DB (survives /reload) so we restore exactly what
-- the player had; the sound-file mutes are per-session, re-applied on load.
-- ---------------------------------------------------------------------------
function LayerNet.ApplyErrorSpeech(partyLens)
    local cfg = CFG(partyLens)
    if SetCVar and GetCVar then
        if cfg.beacon then
            if cfg.errorSpeechSaved == nil then
                cfg.errorSpeechSaved = GetCVar("Sound_EnableErrorSpeech") or "1"
            end
            pcall(SetCVar, "Sound_EnableErrorSpeech", "0")
        elseif cfg.errorSpeechSaved ~= nil then
            pcall(SetCVar, "Sound_EnableErrorSpeech", cfg.errorSpeechSaved)
            cfg.errorSpeechSaved = nil
        end
    end
    if MuteSoundFile and UnmuteSoundFile then
        local fn = cfg.beacon and MuteSoundFile or UnmuteSoundFile
        for _, id in ipairs(MUTE_SOUNDS) do
            pcall(fn, id)
        end
    end
end

function LayerNet.SetBeacon(partyLens, on, quiet)
    local cfg = CFG(partyLens)
    cfg.beacon = on and true or false
    local rt = RT(partyLens)
    rt.lastSync = 0 -- announce our presence to the mesh on the next tick
    LayerNet.ApplyErrorSpeech(partyLens)

    if cfg.beacon then
        -- `quiet` = driven by auto-beacon from inside a tick: skip the chat line and the
        -- immediate re-Tick (the ongoing tick already runs the beacon block below).
        if not quiet then
            Utils.Print(L("LAYER_BEACON_ON"))
            LayerNet.Tick(partyLens)
        end
    elseif not quiet then
        Utils.Print(L("LAYER_BEACON_OFF"))
    end
    LayerNet.RefreshPartyHide(partyLens) -- hide/restore the party frames
    LayerNet.Refresh(partyLens)
end

function LayerNet.ToggleBeacon(partyLens)
    CFG(partyLens).autoBeacon = false -- pressing the beacon button = take manual control
    LayerNet.SetBeacon(partyLens, not CFG(partyLens).beacon)
end

-- Toggle "auto-beacon in the capital" (park-and-help). Applies immediately so the user
-- sees it take effect without waiting for the next tick.
function LayerNet.ToggleAutoBeacon(partyLens)
    local cfg = CFG(partyLens)
    cfg.autoBeacon = not cfg.autoBeacon
    Utils.Print(cfg.autoBeacon and L("LAYER_AUTOBEACON_ON") or L("LAYER_AUTOBEACON_OFF"))
    AutoBeaconApply(partyLens)
    LayerNet.Refresh(partyLens)
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
    -- A "fixed" request (e.g. a world-boss hop) already knows the EXACT target
    -- map + zoneUID — it may be on a DIFFERENT map than where I'm standing, so use
    -- those directly instead of resolving against my current map.
    local reqMap = mr.fixedMap or cur.mapID or 0
    local target = 0
    if mr.fixedTarget then
        target = mr.fixedTarget
    elseif not mr.req.any then
        local n = FirstLayer(mr.req)
        if n then
            target = Layer.ZoneUIDAt(partyLens, cur.mapID, n) or 0
        end
    end
    -- Field 4 is MY zoneUID *on reqMap*. For a map-pinned (fixed) request — e.g. a
    -- world-boss hop — the boss's map differs from the one I'm standing on, so my
    -- current zoneUID does NOT belong to reqMap. Send 0 (the sentinel the receiver
    -- rejects at OnAddonMessage's `zoneUID > 0` guard) rather than leak a foreign
    -- standing-map zoneUID into the boss map's seen-set and corrupt its ordinals.
    local myZoneOnReqMap = mr.fixedMap and 0 or (cur.zoneUID or 0)
    local payload = table.concat({
        LayerNet.NET_PROTO, "R", tostring(reqMap), tostring(myZoneOnReqMap),
        mr.spec, tostring(target),
        -- Append-only: my lifetime hops served, so a contended beacon can serve
        -- contributors first (reciprocity). Self-reported (low-value perk to spoof).
        tostring(CFG(partyLens).hops or 0),
    }, "|")
    SendNet(payload, "R") -- realm-wide too, so a beacon anywhere on the realm can answer

    -- Direct-deliver to the beacons we ALREADY know about. The broadcast above only
    -- reaches a cross-layer / cross-guild beacon via the realm bus, which is
    -- CLICK-FLUSHED (eventual) — and SAY proximity can't cross layers — so a request
    -- to a beacon on another layer can sit undelivered until the requester happens to
    -- click in the 3D world. A hidden addon WHISPER delivers instantly from a timer
    -- (cross-layer, cross-guild), so whisper the request straight to every known
    -- beacon that can serve it. The beacon re-checks the match itself before inviting.
    if Net.Whisper then
        for _, n in pairs(RT(partyLens).nodes) do
            if n.beacon and n.name and not SameAsPlayer(n.name) then
                local serves = mr.req.any
                if not serves and target > 0 and n.zoneUID and n.mapID == reqMap then
                    if mr.req.exclude then
                        serves = n.zoneUID ~= target
                    else
                        serves = n.zoneUID == target
                    end
                end
                if serves then
                    Net.Whisper(LayerNet.PREFIX, payload, n.name)
                end
            end
        end
    end
    if CFG(partyLens).hopdebug then
        LayerNet.Log(partyLens, "sending req: want z=" .. tostring(target) .. " map=" .. tostring(reqMap)
            .. " (I'm on z=" .. tostring(cur.zoneUID or "?") .. ")")
    end
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

-- Request a hop to a SPECIFIC map+layer identity (e.g. a world boss on another
-- zone). Unlike RequestLayer, the target zoneUID is pinned, so a beacon on the
-- boss's own map+layer matches exactly — even though I'm standing somewhere else.
function LayerNet.RequestLayerFor(partyLens, mapID, zoneUID)
    if not (mapID and zoneUID and mapID > 0 and zoneUID > 0) then
        return
    end
    Layer.MergeSeen(partyLens, mapID, { zoneUID }) -- so the target layer can be numbered
    local ord = Layer.OrdinalOf(partyLens, mapID, zoneUID)
    local req = { any = false, exclude = false, layers = {} }
    if ord then
        req.layers[ord] = true
    end
    local rt = RT(partyLens)
    rt.myRequest = {
        req = req,
        spec = ord and tostring(ord) or "1", -- never "any": we want the exact target
        t = time(), lastNet = 0,
        size0 = (GetNumGroupMembers and GetNumGroupMembers()) or 0,
        fixedMap = mapID, fixedTarget = zoneUID,
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
    -- Key beacon presence by ORDINAL (the same NWB-aware number the chips + the
    -- "Layers covered" stat use), NOT by raw zoneUID: a peer beacon's zoneUID can
    -- differ from NWB's layer-N zoneUID (a server layer has different zoneUIDs per
    -- zone), so matching raw zoneUIDs against ZoneUIDAt(i) missed their dot even
    -- though Stats counted them. OrdinalOf is map-agnostic under NWB, so drop the
    -- n.mapID filter too.
    local beaconAt, nodeCount, beaconZone, beaconMap = {}, {}, {}, {}
    for _, n in pairs(rt.nodes) do
        if n.zoneUID then
            local ord = Layer.OrdinalOf(partyLens, n.mapID, n.zoneUID)
            if ord then
                nodeCount[ord] = (nodeCount[ord] or 0) + 1
                if n.beacon then
                    beaconAt[ord] = true
                    -- Remember the beacon's EXACT zoneUID/mapID so a hop request can
                    -- pin it (match by identity, immune to number disagreements).
                    beaconZone[ord] = n.zoneUID
                    beaconMap[ord] = n.mapID
                end
            end
        end
    end
    if CFG(partyLens).beacon and cur.ordinal then
        beaconAt[cur.ordinal] = true -- I'm a live beacon on my own layer
    end
    -- Number the picker with the SAME scheme as the big "Your layer" display:
    -- Layer.CountOnMap / Layer.ZoneUIDAt defer to NWB when installed, so chip "L6" is
    -- NWB's layer 6 and the gold current-layer chip lands on Layer.Current().ordinal
    -- (fixing "I'm on Layer 6 but the picker golds L5"). Falls back to our own sorted
    -- set when NWB is absent.
    local out = {}
    local count = Layer.CountOnMap(partyLens, mapID)
    for i = 1, count do
        local z = Layer.ZoneUIDAt(partyLens, mapID, i)
        if z then
            out[#out + 1] = {
                ordinal = i,
                zoneUID = z,
                isCurrent = (z == cur.zoneUID),
                hasBeacon = beaconAt[i] == true,
                nodes = nodeCount[i] or 0,
                beaconZoneUID = beaconZone[i],
                beaconMapID = beaconMap[i],
            }
        end
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
    -- The dedicated ChehulMesh realm-wide channel carries structured mesh posts,
    -- routed to OnAddonMessage by LibChehulMesh (Mesh:Register). Never treat it as a
    -- human layer channel — its "layer" substring would otherwise mis-parse posts.
    if string.find(lname, "chehulmesh", 1, true) then
        return
    end
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
    -- A generous set of party/invite/instance churn strings the beacon generates by
    -- forming + disbanding groups. Missing globals are simply skipped, so listing
    -- candidates that don't exist on this client is safe (and keeps it localised).
    local names = {
        -- Invite / join / leave / disband
        "ERR_INVITE_PLAYER_S", "ERR_JOINED_GROUP_S", "ERR_DECLINE_GROUP_S",
        "ERR_LEFT_GROUP_S", "ERR_LEFT_GROUP_YOU", "ERR_GROUP_DISBANDED",
        "ERR_ALREADY_IN_GROUP_S", "ERR_ALREADY_IN_GROUP",
        "ERR_RAID_MEMBER_ADDED_S", "ERR_RAID_MEMBER_REMOVED_S",
        "ERR_UNINVITE_PLAYER_S", "ERR_INVITED_TO_GROUP_SS",
        -- "You aren't in a party." and friends
        "ERR_NOT_IN_GROUP", "ERR_NOT_IN_RAID", "ERR_NOT_IN_INSTANCE_GROUP",
        "ERR_NOT_LEADER", "ERR_TARGET_NOT_IN_GROUP_S", "ERR_TARGET_NOT_IN_PARTY_S",
        "ERR_TARGET_NOT_IN_RAID_S",
        -- Invite failures (offline / wrong faction / full / self / restricted)
        "ERR_BAD_PLAYER_NAME_S", "ERR_PLAYER_WRONG_FACTION", "ERR_PLAYER_NOT_FOUND_S",
        "ERR_PARTY_FULL", "ERR_GROUP_FULL", "ERR_RAID_FULL",
        "ERR_CANNOT_INVITE_SELF", "ERR_INVITE_RESTRICTED", "ERR_INVITE_IN_COMBAT",
        -- Difficulty reset spam from party form/disband
        "ERR_DUNGEON_DIFFICULTY_CHANGED_S", "ERR_RAID_DIFFICULTY_CHANGED_S",
        "ERR_LEGACY_RAID_DIFFICULTY_CHANGED", "ERR_SHARED_DIFFICULTY_CHANGED_S",
        -- Loot method announced when a party forms
        "ERR_SET_LOOT_FREEFORALL", "ERR_SET_LOOT_GROUP", "ERR_SET_LOOT_ROUNDROBIN",
        "ERR_SET_LOOT_NBG", "ERR_SET_LOOT_THRESHOLD_S", "ERR_SET_LOOT_MASTER",
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

    -- Shared matcher for the party-churn system strings.
    local function isChurn(msg)
        if not msg then
            return false
        end
        for _, p in ipairs(sysPatterns) do
            if string.match(msg, p) then
                return true
            end
        end
        return false
    end

    -- Party join/leave/decline/"you aren't in a party"/difficulty spam in the chat frame.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        return CFG(partyLens).beacon and isChurn(msg) or false
    end)

    -- The SAME churn also flashes as red center-screen error text (UIErrorsFrame) and
    -- fires the error voice-over. Swallow the red text here while beaconing; the voice
    -- is muted via the Sound_EnableErrorSpeech CVar toggled in SetBeacon.
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local origAddMessage = UIErrorsFrame.AddMessage
        UIErrorsFrame.AddMessage = function(self, msg, ...)
            if CFG(partyLens).beacon and isChurn(msg) then
                return
            end
            return origAddMessage(self, msg, ...)
        end
    end

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
