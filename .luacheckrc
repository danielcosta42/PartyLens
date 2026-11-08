-- luacheck for PartyLens on WoW: Forever (interface 16001, Lua 5.1).
--
-- Undefined globals are errors. read_globals is every engine global the core reads: it doubles as the API
-- inventory, each name checked against the client's Blizzard_APIDocumentationGenerated (a namespace function
-- there) or known from FrameXML / the Lua environment WoW adds (strsplit, wipe, time, ...). A new one goes here
-- only after that check.
--
-- CI runs `luacheck Modules Core.lua UI`. Out of it: the vendored ChehulNet copies (danielcosta42/chehulnet owns
-- them) and the harnesses' stubs. The UI (UI/) adds its own engine globals in the files["UI/"] block below.

std = "lua51"
max_line_length = 120
codes = true
self = false -- an unused implicit self in a method is the method shape, not a mistake

globals = {
    "PartyLensDB",
    "PartyLens",
    "SlashCmdList",
    "SLASH_PARTYLENS1",
    "SLASH_PARTYLENS2",
    "BINDING_HEADER_PARTYLENS",
    "BINDING_NAME_PARTYLENS_TOGGLE",
}

read_globals = {
    -- Lua environment WoW adds
    "strsplit", "wipe", "time", "date", "issecretvalue", "geterrorhandler",
    -- frames and chat frames
    "CreateFrame", "DEFAULT_CHAT_FRAME", "ChatFrameUtil", "WhoFrame",
    -- constants
    "RAID_CLASS_COLORS", "WHO_TAG_EXACT",
    -- client and time
    "GetLocale", "GetTime", "GetServerTime",
    -- units and names
    "Ambiguate", "UnitName", "UnitFullName", "UnitClass", "UnitLevel", "UnitExists", "UnitGUID", "UnitIsUnit",
    "UnitIsPlayer", "UnitPlayerControlled", "UnitGroupRolesAssigned", "UnitIsGroupLeader", "UnitIsGroupAssistant",
    "UnitDistanceSquared", "UnitIsVisible", "GetPlayerInfoByGUID", "UnitIsAFK", "UnitAffectingCombat",
    -- group, guild, instance
    "GetNumGroupMembers", "IsInGroup", "IsInRaid", "IsInGuild", "IsInInstance",
    -- channels
    "GetChannelName", "JoinPermanentChannel", "EnumerateServerChannels",
    -- namespaces
    "C_AddOns", "C_ChatInfo", "C_FriendList", "C_Map", "C_NameUtil", "C_PartyInfo", "C_PlayerInfo", "C_QuestLog",
    "C_Timer",
}

-- The UI: the widget side of the client on top of the core's list, each name checked the same way (frames and
-- regions from FrameXML; C_Sound.PlaySound in the client's SoundDocumentation; SOUNDKIT from FrameXML, used
-- guarded). The ptBR table in UI/Locale.lua is one long string per line.
files["UI/"] = {
    globals = { "PartyLens_UI" },
    read_globals = {
        "UIParent", "GameTooltip", "Minimap", "UISpecialFrames", "STANDARD_TEXT_FONT", "tinsert",
        "GetCursorPosition", "C_Sound", "SOUNDKIT",
    },
}
files["UI/Locale.lua"] = { max_line_length = false }

exclude_files = {
    ".release/",
    "Libs/",
    "tools/",
    "Modules/ChehulNet.lua",
}
