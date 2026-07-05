local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local LocalizedKeywords = _G[ADDON_NAME .. "_LocalizedKeywords"]
local Spam = _G[ADDON_NAME .. "_Spam"]

local Chat = {}

local PLAYER_GROUP_PHRASES = {
    "need group",
    "need grp",
    "need a group",
    "lf group",
    "looking for group",
    "procuro grupo",
    "busco grupo",
    "preciso de grupo",
    "preciso grupo",
}

local GROUP_RECRUIT_PHRASES = {
    "lfm",
    "lf1m",
    "lf2m",
    "lf3m",
    "lf4m",
    "forming",
    "montando",
    "recrutando",
    "vaga",
    "vagas",
    -- "more"/"mais" alone matched inside words like "anymore"/"demais"; use the
    -- explicit recruiting forms instead.
    "1 more",
    "2 more",
    "3 more",
    "need more",
    "mais 1",
    "mais um",
    "+1",
}

local GUILD_RECRUIT_PHRASES = {
    "guild",
    "guilda",
    "guilds",
    "recruit",
    "recruiting",
    "recrutando",
    "recruta",
    "core",
    "raid core",
    "progress",
    "progression",
    "progressao",
    "progressão",
    "semi-hardcore",
    "hardcore",
    "casual",
    "apply",
    "application",
    "discord",
    "loot council",
    "dkp",
}

local QUEST_PHRASES = {
    "quest",
    "quests",
    "elite quest",
    "group quest",
    "daily",
    "dailies",
    "attune",
    "attunement",
    "prequest",
    "pre quest",
    "pre-quest",
    "missao",
    "missão",
    "missoes",
    "missões",
}

local NEED_WORDS = {
    "need",
    "needs",
    "precisa",
    "precisamos",
}

local function HasAnyRoleWord(text)
    for _, words in pairs(LocalizedKeywords.GetRoleKeywords()) do
        if Utils.ContainsAny(text, words) then
            return true
        end
    end
    return false
end

local function GuessIntent(text, hasLFG, hasLFM)
    if Utils.ContainsAny(text, PLAYER_GROUP_PHRASES) then
        return "player"
    end

    if Utils.ContainsAny(text, GROUP_RECRUIT_PHRASES) then
        return "group"
    end

    if hasLFM and Utils.ContainsAny(text, NEED_WORDS) and HasAnyRoleWord(text) then
        return "group"
    end

    if hasLFG then
        return "player"
    end

    return "group"
end

local function GuessContentType(text, isRaid, activityKey)
    if Utils.ContainsAny(text, GUILD_RECRUIT_PHRASES) then
        return "guild"
    end

    -- A concretely recognised dungeon/raid wins over the (looser) quest
    -- heuristic, so e.g. "LFM Kara attune run" is not mis-filed as a quest and
    -- dropped from the default Raid/Dungeon view.
    if isRaid then
        return "raid"
    end

    if activityKey and activityKey ~= "other" then
        return "dungeon"
    end

    if Utils.ContainsAny(text, QUEST_PHRASES) then
        return "quest"
    end

    return "other"
end

local function LooksLikeLFGChannel(channelName, baseName)
    local channel = Utils.SafeLower((baseName or "") .. " " .. (channelName or ""))
    return string.find(channel, "lookingforgroup", 1, true)
        or string.find(channel, "looking for group", 1, true)
        or string.find(channel, "procurando", 1, true)
        or string.find(channel, "lfg", 1, true)
        or string.find(channel, "找团", 1, true)
end

function Chat.HandleChatMessage(partyLens, msg, sender, _, channelName, _, _, _, channelNumber, baseName, _, lineID, guid)
    if not LooksLikeLFGChannel(channelName, baseName) then
        return
    end

    -- Realm-wide mesh recognition: a PartyLens user's posts are signed, so a
    -- signed LFG line means the poster runs the addon. Flag them (the "PL" badge
    -- + trusted merge in Entry) and strip the sign so parsing/display see the
    -- clean line. No addon-message transport needed — this rides the visible post
    -- every client already scans, which is how we reach realm-wide.
    local isAddonUser = false
    local sign = Utils.CHAT_SIGN
    if msg and string.sub(msg, 1, #sign) == sign then
        isAddonUser = true
        msg = Utils.Trim(string.sub(msg, #sign + 1))
    end

    local text = Utils.SafeLower(msg)
    local lfgKeywords = LocalizedKeywords.GetLFGKeywords()
    local lfmKeywords = LocalizedKeywords.GetLFMKeywords()
    local hasLFG = Utils.ContainsAny(text, lfgKeywords)
    local hasLFM = Utils.ContainsAny(text, lfmKeywords)
    
    if not hasLFG and not hasLFM then
        return
    end

    local intent = GuessIntent(text, hasLFG, hasLFM)

    local activityName, activityKey, isRaid = Activity.GuessActivity(msg)
    local activityType = GuessContentType(text, isRaid, activityKey)
    local needs = Needs.GuessNeeds(msg)
    local id = "chat:" .. tostring(lineID or guid or sender or "") .. ":" .. tostring(channelNumber or "")

    local classFile
    if guid and GetPlayerInfoByGUID then
        local _, englishClass = GetPlayerInfoByGUID(guid)
        classFile = englishClass
    end

    Entry.AddOrUpdateEntry(partyLens, {
        id = id,
        source = "chat",
        leader = sender,
        leaderDisplay = Utils.PlayerShortName(sender),
        classFile = classFile,
        activity = activityName,
        activityKey = activityKey,
        activityType = activityType,
        isRaid = isRaid,
        intent = intent,
        message = msg,
        channelName = baseName or channelName,
        timestamp = time(),
        open = true,
        isAddonUser = isAddonUser,
        needs = table.concat(needs, ", "),
        isSpam = Spam and Spam.IsSpam(msg) or false,
    })
end

_G[ADDON_NAME .. "_Chat"] = Chat
return Chat
