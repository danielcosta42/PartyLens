local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local Messaging = {}

function Messaging.BuildMessageForLeader(db, leader, activity)
    local _, classFile = UnitClass("player")
    local className = db.className or select(1, UnitClass("player")) or ""
    local spec = db.spec or ""
    local role = db.role or ""
    local comment = db.comment or ""
    local msg = db.template or Localization.L("TEMPLATE_LABEL")

    msg = string.gsub(msg, "{class}", className)
    msg = string.gsub(msg, "{classFile}", classFile or "")
    msg = string.gsub(msg, "{spec}", spec)
    msg = string.gsub(msg, "{role}", role)
    msg = string.gsub(msg, "{comment}", comment)
    msg = string.gsub(msg, "{leader}", Utils.PlayerShortName(leader))
    msg = string.gsub(msg, "{activity}", activity or "")
    msg = string.gsub(msg, "%s+", " ")
    return Utils.Trim(msg)
end

-- Builds the short whisper the autopilot fires at a recruiting leader when in
-- "find a group" mode. Tokens: {class} {spec} {role} {activity} {comment}.
function Messaging.BuildAutopilotFind(db, activity)
    local ap = db.autopilot or {}
    local className = db.className or select(1, UnitClass("player")) or ""
    local role = ap.myRole or db.role or ""
    local spec = db.spec or ""
    local template = ap.findTemplate or Localization.L("AP_WHISPER_FIND")

    local msg = template
    msg = string.gsub(msg, "{class}", className)
    msg = string.gsub(msg, "{spec}", spec)
    msg = string.gsub(msg, "{role}", role)
    msg = string.gsub(msg, "{activity}", activity or "")
    msg = string.gsub(msg, "{comment}", db.comment or "")
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

    SendChatMessage(message, "WHISPER", nil, entry.leader)
    Utils.Print(Localization.L("WHISPER_SENT", Utils.PlayerShortName(entry.leader), message))
end

function Messaging.OpenWhisper(partyLens, entry)
    if not entry or not entry.leader then
        return
    end

    ChatFrame_OpenChat("/w " .. entry.leader .. " " .. Messaging.BuildMessageForLeader(partyLens.db, entry.leader, entry.activity))
end

function Messaging.JoinLookingForGroup()
    JoinPermanentChannel("LookingForGroup")
    Utils.Print(Localization.L("LFG_JOIN_ATTEMPT"))
end

_G[ADDON_NAME .. "_Messaging"] = Messaging
return Messaging
