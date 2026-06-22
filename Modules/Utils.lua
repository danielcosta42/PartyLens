local ADDON_NAME = ...
local Utils = {}

function Utils.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff35f0c5PartyLens|r " .. tostring(message))
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
