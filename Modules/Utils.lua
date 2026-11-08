local ADDON_NAME = ...
local Utils = {}

function Utils.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff35f0c5PartyLens|r " .. tostring(message))
end

-- A secret value (12.x restrictions, chat lockdown) errors when compared, concatenated or indexed: every event
-- entry point drops its event when any argument it uses is one.
function Utils.IsSecret(...)
    if not issecretvalue then
        return false
    end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then
            return true
        end
    end
    return false
end

function Utils.SafeLower(value)
    return string.lower(tostring(value or ""))
end

function Utils.Trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utils.ContainsAny(text, words)
    for _, word in ipairs(words or {}) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

-- Whole word for an ASCII word, so "mage" misses "damage" and "lfg" misses "lfgroup"; a non-ASCII word (CJK, an
-- accented alias) has no letter boundary to test and falls back to a plain substring.
function Utils.ContainsWord(text, word)
    if not word or word == "" then
        return false
    end
    if string.find(word, "^[%w]+$") then
        return string.find(text, "%f[%w]" .. word .. "%f[%W]") ~= nil
    end
    return string.find(text, word, 1, true) ~= nil
end

function Utils.ContainsAnyWord(text, words)
    for _, word in ipairs(words or {}) do
        if Utils.ContainsWord(text, word) then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Names. On WoW: Forever every event sender is "First Surname" (sometimes "First Surname-Realm"), UnitName gives
-- only the first name, and whispers and invites go to "First Surname". One canonical spelling for display and
-- for targets, its lowercase as the table key.
-- ---------------------------------------------------------------------------
function Utils.HasSurnames()
    return C_PlayerInfo ~= nil and C_PlayerInfo.ShouldDisplaySurname ~= nil
        and C_PlayerInfo.ShouldDisplaySurname() == true
end

-- Mirrors ChehulNet's MyShortName: the way every addon-message sender writes me.
function Utils.MyName()
    if Utils.HasSurnames() then
        local first, surname = UnitFullName("player")
        if not Utils.IsSecret(first, surname) and first and surname and surname ~= "" then
            return first .. " " .. surname
        end
    end
    local name = UnitName("player")
    if Utils.IsSecret(name) then
        return ""
    end
    return name or ""
end

-- "First Surname-Realm" whispers as "First Surname" on Forever (the mesh's rule); a name with no surname keeps
-- a foreign realm, which it needs to be reached.
function Utils.FullName(name)
    if Utils.IsSecret(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    local surnamed = name:match("^(%S+ %S+)%-%S+$")
    if surnamed then
        return surnamed
    end
    return Ambiguate(name, "none")
end

function Utils.NameKey(name)
    local full = Utils.FullName(name)
    return full and string.lower(full) or nil
end

function Utils.IsMe(name)
    local key = Utils.NameKey(name)
    return key ~= nil and key == Utils.NameKey(Utils.MyName())
end

-- Two spellings of one person. A group unit may give the first name alone where chat gives the surname too
-- (GuildOS issue #48), so a side without a surname matches on the first name.
function Utils.SameName(a, b)
    local ka, kb = Utils.NameKey(a), Utils.NameKey(b)
    if not ka or not kb then
        return false
    end
    if ka == kb then
        return true
    end
    if ka:find(" ", 1, true) and kb:find(" ", 1, true) then
        return false
    end
    return ka:match("^[^%s%-]+") == kb:match("^[^%s%-]+")
end

-- A group unit's name as chat would write it, or nil when the client keeps it secret.
function Utils.UnitFullName(unit)
    local first, second = UnitFullName(unit)
    if Utils.IsSecret(first, second) or type(first) ~= "string" or first == "" then
        return nil
    end
    if not first:find(" ", 1, true) and Utils.HasSurnames() and type(second) == "string" and second ~= "" then
        return first .. " " .. second
    end
    return first
end

function Utils.IsPlayerUnit(unit)
    local same = UnitIsUnit(unit, "player")
    if Utils.IsSecret(same) then
        return false
    end
    return same and true or false
end

function Utils.ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then
        return c.r, c.g, c.b, c.colorStr or string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return 1, 1, 1, "ffffffff"
end

-- ---------------------------------------------------------------------------
-- Sending. Visible chat needs a hardware event on Forever, so SendChat is only ever reached from a click.
-- Addon messages do not, but nothing leaves from an instance or a chat lockdown.
-- ---------------------------------------------------------------------------
-- The sign on every visible line PartyLens writes, so another PartyLens reading the LFG channel knows the
-- poster runs it.
Utils.CHAT_SIGN = "[PartyLens]: "

-- Clamped to 255 bytes on a UTF-8 boundary: the server cuts blind and would split an accented letter.
function Utils.SendChat(message, chatType, target)
    message = tostring(message or "")
    if message == "" then
        return false
    end
    if message:sub(1, #Utils.CHAT_SIGN) ~= Utils.CHAT_SIGN then
        message = Utils.CHAT_SIGN .. message
    end
    if #message > 255 then
        local cut = 255
        while cut > 0 do
            local b = message:byte(cut + 1)
            if b and b >= 0x80 and b < 0xC0 then
                cut = cut - 1
            else
                break
            end
        end
        message = message:sub(1, cut)
    end
    C_ChatInfo.SendChatMessage(message, chatType, nil, target)
    return true
end

function Utils.InInstance()
    local inside = IsInInstance()
    return (not Utils.IsSecret(inside)) and inside == true
end

function Utils.InLockdown()
    local lock = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    return (not Utils.IsSecret(lock)) and lock == true
end

function Utils.CanSendAddon()
    return not Utils.InInstance() and not Utils.InLockdown()
end

_G[ADDON_NAME .. "_Utils"] = Utils
return Utils
