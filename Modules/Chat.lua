local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local LocalizedKeywords = _G[ADDON_NAME .. "_LocalizedKeywords"]
local Spam = _G[ADDON_NAME .. "_Spam"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- The radar's ear on the LookingForGroup channel.
local Chat = {}

local PLAYER_PHRASES = {
    "need group", "need grp", "need a group", "lf group", "looking for group", "procuro grupo", "busco grupo",
    "preciso de grupo", "preciso grupo",
}

-- Words that only a group being formed writes. "need", "precisa" and the like are weaker: they count only next to
-- a role, an activity or a quest (Chat.GuessType), or chatter like "where the locks at when you need em" is a group.
local RECRUIT_PHRASES = {
    "lfm", "forming", "montando", "recrutando", "vaga", "vagas", "1 more", "2 more", "3 more", "4 more", "mais 1",
}

-- A guild recruiting members, not a group: only the words a guild ad has and a group post does not ("discord" or
-- "dkp" show up in group posts too, so they are not here).
local GUILD_PHRASES = { "guild", "guilda", "guilds", "guilde", "gilde", "recruit", "recruiting", "recruta" }

local QUEST_PHRASES = {
    "quest", "quests", "elite quest", "group quest", "attune", "attunement", "prequest", "pre-quest", "missao",
    "missão", "missoes", "missões",
}

local function HasRoleWord(text)
    for _, words in pairs(LocalizedKeywords.GetRoleKeywords()) do
        if Utils.ContainsAnyWord(text, words) then
            return true
        end
    end
    return false
end

-- "lf1m".."lf9m", or "lf" right before a role ("LF healer for RoL").
local function LooksLFM(text)
    if text:find("%f[%w]lf%d?m%f[%W]") then
        return true
    end
    for _, words in pairs(LocalizedKeywords.GetRoleKeywords()) do
        for _, w in ipairs(words) do
            if text:find("%f[%w]lf%s+" .. w:gsub("%p", "%%%0") .. "%f[%W]") then
                return true
            end
        end
    end
    return false
end

-- "lfg" or "lfm" for a line, or nil when it is neither. `named` = the line names an activity or a quest.
function Chat.GuessType(text, named)
    local hasLFG = Utils.ContainsAnyWord(text, LocalizedKeywords.GetLFGKeywords())
    local strong = LooksLFM(text) or Utils.ContainsAnyWord(text, RECRUIT_PHRASES)
    local need = Utils.ContainsAnyWord(text, LocalizedKeywords.GetLFMKeywords())
    if not hasLFG and not strong and not need then
        return nil
    end
    if Utils.ContainsAny(text, PLAYER_PHRASES) then
        return "lfg"
    end
    if strong then
        return "lfm"
    end
    if need and (named or HasRoleWord(text)) then
        return "lfm"
    end
    return hasLFG and "lfg" or nil
end

-- A guild's recruiting ad: its tag in angle brackets ("<Ashen>") or the words guilds use.
local function IsGuildAd(text)
    return text:find("<[^<>]+>") ~= nil or Utils.ContainsAnyWord(text, GUILD_PHRASES)
end

local function GuessActivityType(text, activity)
    if activity then
        return activity.type
    end
    if Utils.ContainsAnyWord(text, QUEST_PHRASES) then
        return "quest"
    end
    return "other"
end

-- The channel's name is localized, so it is recognized by its words (lowercase; Cyrillic and CJK as written,
-- string.lower leaves them alone).
local LFG_CHANNEL_WORDS = {
    "lookingforgroup", "looking for group", "lfg", "procurandogrupo", "procurando", "suchenachgruppe",
    "recherchedegroupe", "buscargrupo", "cercagruppo", "ПоискСпутников", "파티찾기", "寻求组队", "尋求組隊", "找团",
}

function Chat.IsLFGChannel(channelName, baseName)
    return Utils.ContainsAny(Utils.SafeLower((baseName or "") .. " " .. (channelName or "")), LFG_CHANNEL_WORDS)
end

Chat.MAX_CHANNELS = 20

-- The joined channel the radar listens to, as { id, name }, or nil.
function Chat.FindLFGChannel()
    for i = 1, Chat.MAX_CHANNELS do
        local id, name = GetChannelName(i)
        if not Utils.IsSecret(id, name) and type(id) == "number" and id > 0 and type(name) == "string"
            and Chat.IsLFGChannel(name) then
            return { id = id, name = name }
        end
    end
end

-- Re-reads it and fires LFG_CHANNEL_CHANGED when it changed. Returns it.
function Chat.RefreshLFGChannel(partyLens)
    local found, old = Chat.FindLFGChannel(), partyLens.lfgChannel
    if (found and found.id) ~= (old and old.id) or (found and found.name) ~= (old and old.name) then
        partyLens.lfgChannel = found
        partyLens:Fire("LFG_CHANNEL_CHANGED", found and { id = found.id, name = found.name } or nil)
    end
    return found
end

-- The name to join it by: the server's own (localized) channel list when the client gives it, the English name
-- only on an English client, where it is the right one (anywhere else it would make a custom channel).
function Chat.LFGJoinName()
    for _, name in ipairs(EnumerateServerChannels and { EnumerateServerChannels() } or {}) do
        if type(name) == "string" and not Utils.IsSecret(name) and Chat.IsLFGChannel(name) then
            return name
        end
    end
    local locale = GetLocale()
    if locale == "enUS" or locale == "enGB" then
        return "LookingForGroup"
    end
end

-- Parses a line into the fields an entry takes, or nil. Exposed for the harnesses.
function Chat.Parse(msg)
    local isAddonUser = false
    local sign = Utils.CHAT_SIGN
    if msg:sub(1, #sign) == sign then
        isAddonUser = true
        msg = Utils.Trim(msg:sub(#sign + 1))
    end
    local text = Utils.SafeLower(msg)
    local activity = Activity.Guess(text)
    local quest = Utils.ContainsAnyWord(text, QUEST_PHRASES)
    local kind = Chat.GuessType(text, activity ~= nil or quest)
    -- No group: chatter, or a guild recruiting members (unless it forms a run that names a dungeon or raid).
    if not kind or (not activity and IsGuildAd(text)) then
        return nil
    end
    return {
        type = kind,
        roles = Needs.Guess(text),
        activityKey = activity and activity.key or nil,
        activity = activity and activity.name or L("ACTIVITY_OTHER"),
        activityType = GuessActivityType(text, activity),
        message = msg,
        isAddonUser = isAddonUser,
        isSpam = Spam.IsSpam(msg),
    }
end

-- CHAT_MSG_CHANNEL(text, sender, language, channelName, sender2, flags, zoneChannelID, channelIndex, baseName,
-- languageID, lineID, guid). Any argument it reads arriving secret drops the line.
function Chat.HandleChatMessage(partyLens, msg, sender, _, channelName, _, _, _, _, baseName, _, _, guid)
    if Utils.IsSecret(msg, sender, channelName, baseName, guid) then
        return
    end
    if type(msg) ~= "string" or type(sender) ~= "string" or not Chat.IsLFGChannel(channelName, baseName) then
        return
    end
    local key = Utils.NameKey(sender)
    if not key or Utils.IsMe(sender) then
        return
    end
    local data = Chat.Parse(msg)
    if not data then
        return
    end
    data.key, data.name, data.source = key, Utils.FullName(sender), "chat"
    data.channel = baseName or channelName
    if not partyLens.lfgChannel then
        Chat.RefreshLFGChannel(partyLens)
    end
    if type(guid) == "string" and guid ~= "" then
        local _, classFile = GetPlayerInfoByGUID(guid)
        if not Utils.IsSecret(classFile) then
            data.classFile = classFile
        end
    end
    return Entry.Upsert(partyLens, data)
end

_G[ADDON_NAME .. "_Chat"] = Chat
return Chat
