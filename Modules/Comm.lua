local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Net = _G[ADDON_NAME .. "_Net"]

-- PartyLens "mesh": addon users broadcast a compact, structured LFG/LFM intent
-- over the LookingForGroup channel as HIDDEN addon messages (invisible in chat).
-- Other PartyLens users parse it into rich entries (no text guessing), flag them
-- as `isAddonUser`, prioritize them, and can match instantly. This is the
-- network-effect incentive: running the addon gets you found and grouped faster.
local Comm = {}

Comm.PREFIX = "PartyLens"
Comm.PROTOCOL = "1"
-- How often an armed client re-broadcasts its intent (addon messages share the
-- chat throttle, so keep this modest). Slightly above the prune horizon / 2.
Comm.BROADCAST_INTERVAL = 30

local function SameAsPlayer(sender)
    return Utils.SafeLower(Utils.PlayerShortName(sender or ""))
        == Utils.SafeLower(Utils.PlayerShortName(UnitName("player") or ""))
end

-- Registers the addon-message prefix so CHAT_MSG_ADDON fires for our traffic.
function Comm.Init()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then
        pcall(register, Comm.PREFIX)
    end
end

-- Builds the wire payload from the current autopilot intent:
--   "1|<lfg|lfm>|<role(s)>|<dungeon|raid|any>|<activity label>|<ilvl>|<class>|<level>"
-- For lfg, role is the player's own role; for lfm it's the still-needed roles
-- joined by "+" (so the receiver knows which slots are open). The trailing
-- class + level fields are APPEND-ONLY (protocol stays "1"): older clients
-- simply ignore the extra fields, and we tolerate their absence when parsing —
-- so the mesh stays cross-version compatible while newer clients get accurate,
-- lookup-free class/level for every fellow PartyLens user.
function Comm.BuildPayload(partyLens)
    local cfg = partyLens.db.autopilot
    local intent, role
    -- Live-composition fields (LFM only): filled "t.h.d" and target "t.h.d" per role.
    local compFilled, compTarget = "", ""

    if cfg.role == "build" then
        intent = "lfm"
        local need, snap = Roster.Needed(partyLens)
        local parts = {}
        if need.tank > 0 then parts[#parts + 1] = "tank" end
        if need.heal > 0 then parts[#parts + 1] = "heal" end
        if need.dps > 0 then parts[#parts + 1] = "dps" end
        role = (#parts > 0) and table.concat(parts, "+") or "any"
        -- Broadcast the live composition so receivers can show "T1/1 H0/1 D2/3":
        -- filled now, and target = filled + still-needed per role.
        compFilled = (snap.tank or 0) .. "." .. (snap.heal or 0) .. "." .. (snap.dps or 0)
        compTarget = ((snap.tank or 0) + (need.tank or 0)) .. "."
            .. ((snap.heal or 0) + (need.heal or 0)) .. "."
            .. ((snap.dps or 0) + (need.dps or 0))
    else
        intent = "lfg"
        -- The player's roles are derived from their spec(s) — broadcast all of
        -- them ("heal+dps") so recruiters know every slot we can fill.
        local mr = partyLens.db.myRoles
        local parts = {}
        if mr then
            if mr.tank then parts[#parts + 1] = "tank" end
            if mr.heal then parts[#parts + 1] = "heal" end
            if mr.dps then parts[#parts + 1] = "dps" end
        end
        role = (#parts > 0) and table.concat(parts, "+") or (cfg.myRole or "dps")
    end

    local label = Utils.Trim(cfg.activityFilter or "")
    if label == "" then
        label = "any"
    end
    -- Strip any pipe just in case an activity name ever contained one.
    label = string.gsub(label, "|", " ")

    local _, classFile = UnitClass("player")
    local level = (UnitLevel and UnitLevel("player")) or 0

    -- My current layer (map + zoneUID), so receivers can flag me "reachable on your
    -- layer". Layer loads after Comm, so fetch it lazily at broadcast time.
    local zoneUID, mapID = 0, 0
    local Layer = _G[ADDON_NAME .. "_Layer"]
    if Layer and Layer.Current then
        local cur = Layer.Current(partyLens)
        zoneUID, mapID = cur.zoneUID or 0, cur.mapID or 0
    end

    return table.concat({
        Comm.PROTOCOL,
        intent,
        role,
        cfg.activityType or "any",
        label,
        tostring(cfg.minIlvl or 0),
        classFile or "",
        tostring(level or 0),
        -- Append-only (protocol stays "1"): layer + live composition.
        tostring(zoneUID),
        tostring(mapID),
        compFilled,
        compTarget,
    }, "|")
end

-- Sends one intent broadcast to other PartyLens users (hidden addon message).
--
-- The old code sent over the CHANNEL distribution, which is BLOCKED for addon
-- messages on this client (returns 4) — every broadcast was dropped silently.
-- There is no automatic realm-wide hidden bus, so we advertise over the buses
-- that actually deliver from a timer: the GUILD (guildmates running PartyLens)
-- and SAY proximity (nearby users at city / auction-house hubs). Realm-wide
-- reach still comes from our SIGNED visible LFG posts, which every PartyLens
-- user already scans. Instrumented via Net.Stats — never silent again.
function Comm.Broadcast(partyLens)
    local payload = Comm.BuildPayload(partyLens)
    local sentGuild = Net.Guild(Comm.PREFIX, payload)
    local sentNear = Net.Proximity(Comm.PREFIX, payload)
    -- Also realm-wide (coalesced to my latest LFG state) so a random PartyLens user
    -- gets the STRUCTURED, trusted class/level entry — not just the text-guessed one
    -- reconstructed from the visible LFG post.
    if Net.Realm then
        Net.Realm(Comm.PREFIX, payload, Comm.PREFIX .. ":lfg")
    end
    return sentGuild or sentNear
end

-- Called from the autopilot tick: re-broadcast while armed, throttled. Build mode
-- goes quiet once the group is full (nothing to advertise).
function Comm.Heartbeat(partyLens)
    local rt = partyLens.autopilot
    if not rt or not rt.armed then
        return
    end
    if (time() - (rt.lastBroadcast or 0)) < Comm.BROADCAST_INTERVAL then
        return
    end
    if partyLens.db.autopilot.role == "build" then
        local need = Roster.Needed(partyLens)
        if need.total <= 0 then
            return
        end
    end
    rt.lastBroadcast = time()
    Comm.Broadcast(partyLens)
end

local function ParsePayload(text)
    if type(text) ~= "string" then
        return nil
    end
    local protocol, intent, role, activityType, label, ilvl, classFile, level,
        zoneUID, mapID, compFilled, compTarget = strsplit("|", text)
    if protocol ~= Comm.PROTOCOL then
        return nil
    end
    return {
        intent = intent,
        role = role or "",
        activityType = activityType or "any",
        label = label or "",
        ilvl = tonumber(ilvl) or 0,
        -- Trailing fields are absent from older-client broadcasts; nil is fine.
        classFile = (classFile ~= nil and classFile ~= "") and classFile or nil,
        level = tonumber(level),
        zoneUID = tonumber(zoneUID),
        mapID = tonumber(mapID),
        compFilled = (compFilled ~= nil and compFilled ~= "") and compFilled or nil,
        compTarget = (compTarget ~= nil and compTarget ~= "") and compTarget or nil,
    }
end

-- Handles an incoming PartyLens addon message: turns it into a rich, trusted
-- entry flagged isAddonUser (so it ranks high and shows the "PL" badge).
function Comm.OnMessage(partyLens, prefix, text, _, sender)
    if prefix ~= Comm.PREFIX or not sender or sender == "" then
        return
    end
    if SameAsPlayer(sender) then
        return
    end
    local data = ParsePayload(text)
    if not data then
        return
    end

    local isLFM = data.intent == "lfm"
    local activityType = (data.activityType == "raid") and "raid" or "dungeon"
    local activityName = (data.label ~= "" and data.label ~= "any") and data.label or nil
    local rolesReadable = string.gsub(data.role or "", "%+", ", ")

    local message
    if isLFM then
        message = "LFM " .. rolesReadable .. (activityName and (" - " .. activityName) or "")
    else
        message = (data.role ~= "" and data.role or "?") .. " LF " .. (activityName or "group")
    end

    -- Live group composition (LFM only): "t.h.d" filled + target -> structured comp
    -- the receiver renders as "T1/1 H0/1 D2/3", plus a real fill bar (size/max).
    local comp, numMembers, maxMembers
    if isLFM and data.compFilled and data.compTarget then
        local ft, fh, fd = strsplit(".", data.compFilled)
        local tt, th, td = strsplit(".", data.compTarget)
        comp = {
            t = tonumber(ft) or 0, h = tonumber(fh) or 0, d = tonumber(fd) or 0,
            tMax = tonumber(tt) or 0, hMax = tonumber(th) or 0, dMax = tonumber(td) or 0,
        }
        numMembers = comp.t + comp.h + comp.d
        maxMembers = comp.tMax + comp.hMax + comp.dMax
    end

    Entry.AddOrUpdateEntry(partyLens, {
        id = "addon:" .. Utils.PlayerShortName(sender),
        source = "addon",
        isAddonUser = true,
        leader = sender,
        leaderDisplay = Utils.PlayerShortName(sender),
        -- Trusted class + level straight from the mesh (no /who needed).
        classFile = data.classFile,
        level = data.level,
        intent = isLFM and "group" or "player",
        activity = activityName or (activityType == "raid" and "Raid" or "Dungeon"),
        activityType = activityType,
        -- For an LFG broadcast, role is the player's OWN role (used by build-mode
        -- matching). For LFM, it's the recruiter's open slots -> needs.
        role = (not isLFM) and data.role or nil,
        needs = isLFM and rolesReadable or "",
        message = message,
        timestamp = time(),
        open = true,
        -- Live composition + fill, and sender's layer for the reachable-now badge.
        comp = comp,
        numMembers = numMembers,
        maxMembers = maxMembers,
        senderZoneUID = (data.zoneUID and data.zoneUID > 0) and data.zoneUID or nil,
        senderMapID = (data.mapID and data.mapID > 0) and data.mapID or nil,
    })
end

_G[ADDON_NAME .. "_Comm"] = Comm
return Comm
