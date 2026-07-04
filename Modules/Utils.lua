local ADDON_NAME = ...
local Utils = {}

function Utils.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff35f0c5PartyLens|r " .. tostring(message))
end

-- Brand sign prepended to every VISIBLE chat message PartyLens sends (whispers,
-- channel / party / raid announces) so recipients can tell it came from the
-- addon. Plain text (no color escape) so it survives every channel. NOT applied
-- to the hidden addon-comm mesh — that carries its own binary protocol.
Utils.CHAT_SIGN = "[PartyLens]: "

-- Signed wrapper around SendChatMessage. Every outgoing chat send routes through
-- here so the sign is applied in exactly one place. Idempotent (won't double-sign)
-- and drops empty messages.
function Utils.SendChat(message, chatType, language, target)
    message = tostring(message or "")
    if message == "" then
        return
    end
    if string.sub(message, 1, #Utils.CHAT_SIGN) ~= Utils.CHAT_SIGN then
        message = Utils.CHAT_SIGN .. message
    end
    -- SendChatMessage caps at 255 BYTES and blind-cuts the tail, which can split
    -- a multi-byte UTF-8 char (ptBR accents, CJK). Clamp on a code-point boundary
    -- so the sign is preserved and no stray continuation byte is left behind.
    if #message > 255 then
        local cut = 255
        while cut > 0 do
            local b = string.byte(message, cut + 1)
            if b and b >= 0x80 and b < 0xC0 then
                cut = cut - 1 -- next byte is a UTF-8 continuation; back off the split
            else
                break
            end
        end
        message = string.sub(message, 1, cut)
    end
    SendChatMessage(message, chatType, language, target)
end

function Utils.SafeLower(value)
    return string.lower(tostring(value or ""))
end

function Utils.Trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

function Utils.PlayerShortName(name)
    if not name or name == "" then
        return UNKNOWN or "Unknown"
    end
    if Ambiguate then
        return Ambiguate(name, "short")
    end
    return string.gsub(name, "%-.*$", "")
end

function Utils.ContainsAny(text, words)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

-- Whole-word match for an ASCII word so e.g. "mage" doesn't match "damage" and
-- "lock" doesn't match "block". Non-ASCII words (CJK class names) have no letter
-- boundaries, so they fall back to a plain substring match.
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

function Utils.SecondsAgo(timestamp)
    local age = math.max(0, time() - (timestamp or time()))
    if age < 60 then
        return age .. "s"
    end
    if age < 3600 then
        return math.floor(age / 60) .. "m"
    end
    return math.floor(age / 3600) .. "h"
end

function Utils.ClassColoredName(name, classFile)
    local CLASS_COLORS = {
        WARRIOR = "C79C6E",
        PALADIN = "F58CBA",
        HUNTER = "ABD473",
        ROGUE = "FFF569",
        PRIEST = "FFFFFF",
        SHAMAN = "0070DE",
        MAGE = "69CCF0",
        WARLOCK = "9482C9",
        DRUID = "FF7D0A",
    }
    local color = CLASS_COLORS[classFile or ""] or "FFD100"
    return "|cff" .. color .. Utils.PlayerShortName(name) .. "|r"
end

-- UTF-8-aware uppercase: string.upper only handles ASCII, so accented Latin
-- letters (á, ç, ã, …) would stay lowercase and look broken in UPPERCASE section
-- headers. Map the common ones explicitly. Non-Latin scripts are left as-is.
local UPPER_ACCENTS = {
    ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["ä"] = "Ä",
    ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
    ["í"] = "Í", ["ì"] = "Ì", ["î"] = "Î", ["ï"] = "Ï",
    ["ó"] = "Ó", ["ò"] = "Ò", ["ô"] = "Ô", ["õ"] = "Õ", ["ö"] = "Ö",
    ["ú"] = "Ú", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü",
    ["ç"] = "Ç", ["ñ"] = "Ñ",
}

function Utils.Upper(value)
    local s = string.upper(tostring(value or ""))
    s = string.gsub(s, "[\194-\223][\128-\191]", function(c)
        return UPPER_ACCENTS[c] or c
    end)
    return s
end

_G[ADDON_NAME .. "_Utils"] = Utils
return Utils
