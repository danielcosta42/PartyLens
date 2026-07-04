local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Roster = _G[ADDON_NAME .. "_Roster"]

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

    if cfg.role == "build" then
        intent = "lfm"
        local need = Roster.Needed(partyLens)
        local parts = {}
        if need.tank > 0 then parts[#parts + 1] = "tank" end
        if need.heal > 0 then parts[#parts + 1] = "heal" end
        if need.dps > 0 then parts[#parts + 1] = "dps" end
        role = (#parts > 0) and table.concat(parts, "+") or "any"
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

    return table.concat({
        Comm.PROTOCOL,
        intent,
        role,
        cfg.activityType or "any",
        label,
        tostring(cfg.minIlvl or 0),
        classFile or "",
        tostring(level or 0),
    }, "|")
end

-- Sends one intent broadcast over the LookingForGroup channel (hidden). No-op if
-- the channel isn't joined yet (EnsureLFGChannel handles that on login).
function Comm.Broadcast(partyLens)
    local channelNumber = GetChannelName and GetChannelName("LookingForGroup")
    if type(channelNumber) ~= "number" or channelNumber == 0 then
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then
        return false
    end
    pcall(send, Comm.PREFIX, Comm.BuildPayload(partyLens), "CHANNEL", channelNumber)
    return true
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
    local protocol, intent, role, activityType, label, ilvl, classFile, level = strsplit("|", text)
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
    })
end

_G[ADDON_NAME .. "_Comm"] = Comm
return Comm
