local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Chat = _G[ADDON_NAME .. "_Chat"]

local L = Localization.L

-- Whispers and invites: built here, sent only from a click (the game requires a hardware event for both).
local Messaging = {}

local function RoleNames(set)
    local parts = {}
    for _, role in ipairs(Needs.ROLES) do
        if set[role] then
            parts[#parts + 1] = L(role == "tank" and "ROLE_TANK" or role == "heal" and "ROLE_HEAL" or "ROLE_DPS")
        end
    end
    return table.concat(parts, "/")
end
Messaging.RoleNames = RoleNames

-- string.gsub reads '%' in a replacement as a capture: a player's "50%" would raise.
local function Fill(template, tokens)
    local msg = template:gsub("{(%w+)}", function(token)
        local v = tokens[token]
        return v ~= nil and tostring(v) or nil
    end)
    return Utils.Trim(msg:gsub("%s+", " "))
end

-- The one-line summary of a listing, the same for my LFG post and for a listing heard on the network.
function Messaging.PostText(kind, activityName, roles, level, comment)
    local roleText = RoleNames(roles or {})
    local text
    if kind == "lfg" then
        text = L("POST_LFG", activityName, roleText ~= "" and roleText or L("ROLE_DPS"), tonumber(level) or 0)
    else
        text = L("POST_LFM", activityName, roleText ~= "" and roleText or L("POST_ANY_ROLE"))
    end
    comment = Utils.Trim(comment)
    if comment ~= "" then
        text = text .. " - " .. comment
    end
    return text
end

-- To a group leader: who I am. To a player looking for a group: an offer to join mine.
function Messaging.BuildWhisper(partyLens, entry)
    local db = partyLens.db
    local className = UnitClass("player")
    local level = UnitLevel("player")
    local tokens = {
        name = (entry.name or ""):match("^%S+") or "",
        class = (not Utils.IsSecret(className)) and className or "",
        level = (not Utils.IsSecret(level)) and level or "",
        activity = entry.activity or "",
        comment = db.comment or "",
    }
    if entry.type == "lfg" then
        local listing = partyLens:GetListing()
        local offered = entry.roles or {}
        local wanted = (listing.active and listing.type == "lfm") and Needs.FromCounts(listing.missing) or offered
        local both = {}
        for _, role in ipairs(Needs.ROLES) do
            both[role] = (wanted[role] and offered[role]) or nil
        end
        tokens.role = RoleNames(Needs.IsEmpty(both) and wanted or both)
        tokens.activity = listing.active and listing.name or tokens.activity
        return Fill(L("WHISPER_RECRUIT"), tokens)
    end
    tokens.role = RoleNames(db.roles)
    local template = (db.whisperTemplate ~= "" and db.whisperTemplate) or L("WHISPER_TEMPLATE")
    return Fill(template, tokens)
end

function Messaging.SendWhisper(partyLens, entry)
    local message = Messaging.BuildWhisper(partyLens, entry)
    if message == "" or not entry.name then
        return false, "empty"
    end
    Utils.SendChat(message, "WHISPER", entry.name)
    partyLens:Notice(L("WHISPER_SENT", entry.name, message))
    return true
end

-- Opens the edit box on the full name; "/w First Surname text" would whisper "First" the word "Surname".
function Messaging.OpenWhisper(partyLens, entry)
    if not (ChatFrameUtil and ChatFrameUtil.SendTell and entry.name) then
        return false
    end
    ChatFrameUtil.SendTell(entry.name)
    local box = ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    if box and box.Insert then
        box:Insert(Utils.CHAT_SIGN .. Messaging.BuildWhisper(partyLens, entry))
    end
    return true
end

function Messaging.Invite(partyLens, name)
    if not Roster.CanInvite() then
        partyLens:Notice(L("NOTICE_CANNOT_INVITE"))
        return false, "cannot_invite"
    end
    if Roster.IsInGroup(name) then
        return false, "in_group"
    end
    C_PartyInfo.InviteUnit(name)
    partyLens:Notice(L("NOTICE_INVITED", name))
    return true
end

-- The LFG channel's number, joining it when it is missing (CHAT_MSG_CHANNEL only fires for a joined channel,
-- and the channel is opt-in).
function Messaging.LFGChannel(partyLens, join)
    local found = Chat.RefreshLFGChannel(partyLens)
    if found then
        return found.id
    end
    local name = join and Chat.LFGJoinName()
    if name then
        JoinPermanentChannel(name)
        C_Timer.After(2, function() Chat.RefreshLFGChannel(partyLens) end)
    end
    return nil
end

_G[ADDON_NAME .. "_Messaging"] = Messaging
return Messaging
