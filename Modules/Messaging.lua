local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local Messaging = {}

-- In Lua string.gsub the REPLACEMENT string is interpreted: a '%' must be
-- followed by a digit (capture ref) or another '%', else it raises "invalid use
-- of '%' in replacement string". Our tokens are filled with user free-text
-- (comment, spec, activity...), so any '%' the player types (e.g. "50% off")
-- would crash message building. Double every '%' before it lands in a replacement.
local function EscRepl(s)
    return (string.gsub(tostring(s or ""), "%%", "%%%%"))
end

-- Readable role token(s) for {role}: all roles the player offers (derived from
-- their specs), e.g. "heal/dps". Falls back to the single db.role.
local function RoleText(db)
    local mr = db.myRoles
    if mr then
        local parts = {}
        if mr.tank then parts[#parts + 1] = "tank" end
        if mr.heal then parts[#parts + 1] = "heal" end
        if mr.dps then parts[#parts + 1] = "dps" end
        if #parts > 0 then
            return table.concat(parts, "/")
        end
    end
    return db.role or ""
end

function Messaging.BuildMessageForLeader(db, leader, activity)
    local _, classFile = UnitClass("player")
    local className = db.className or select(1, UnitClass("player")) or ""
    local spec = db.spec or ""
    local role = RoleText(db)
    local comment = db.comment or ""
    local msg = db.template or Localization.L("TEMPLATE_LABEL")

    msg = string.gsub(msg, "{class}", EscRepl(className))
    msg = string.gsub(msg, "{classFile}", EscRepl(classFile or ""))
    msg = string.gsub(msg, "{spec}", EscRepl(spec))
    msg = string.gsub(msg, "{role}", EscRepl(role))
    msg = string.gsub(msg, "{comment}", EscRepl(comment))
    msg = string.gsub(msg, "{leader}", EscRepl(Utils.PlayerShortName(leader)))
    msg = string.gsub(msg, "{activity}", EscRepl(activity or ""))
    msg = string.gsub(msg, "%s+", " ")
    return Utils.Trim(msg)
end

-- Builds the short whisper the autopilot fires at a recruiting leader when in
-- "find a group" mode. Tokens: {class} {spec} {role} {activity} {comment}.
function Messaging.BuildAutopilotFind(db, activity)
    local ap = db.autopilot or {}
    local className = db.className or select(1, UnitClass("player")) or ""
    local role = RoleText(db)
    local spec = db.spec or ""
    local template = ap.findTemplate or Localization.L("AP_WHISPER_FIND")

    local msg = template
    msg = string.gsub(msg, "{class}", EscRepl(className))
    msg = string.gsub(msg, "{spec}", EscRepl(spec))
    msg = string.gsub(msg, "{role}", EscRepl(role))
    msg = string.gsub(msg, "{activity}", EscRepl(activity or ""))
    msg = string.gsub(msg, "{comment}", EscRepl(db.comment or ""))
    msg = string.gsub(msg, "%s+", " ")
    return Utils.Trim(msg)
end

function Messaging.SendWhisper(partyLens, entry)
    if not entry or not entry.leader then
        return
    end

    local message = Messaging.BuildMessageForLeader(partyLens.db, entry.leader, entry.activity)
    if message == "" then
        Utils.Print(Localization.L("NO_MESSAGE"))
        return
    end

    Utils.SendChat(message, "WHISPER", nil, entry.leader)
    Utils.Print(Localization.L("WHISPER_SENT", Utils.PlayerShortName(entry.leader), message))
end

function Messaging.OpenWhisper(partyLens, entry)
    if not entry or not entry.leader then
        return
    end

    ChatFrame_OpenChat("/w " .. entry.leader .. " " .. Utils.CHAT_SIGN
        .. Messaging.BuildMessageForLeader(partyLens.db, entry.leader, entry.activity))
end

function Messaging.JoinLookingForGroup()
    JoinPermanentChannel("LookingForGroup")
    Utils.Print(Localization.L("LFG_JOIN_ATTEMPT"))
end

_G[ADDON_NAME .. "_Messaging"] = Messaging
return Messaging
