local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- Heuristic spam detector for the LookingForGroup channel & listing titles:
-- gold-selling / boosting / RMT, which drown out real recruitment. Conservative
-- on purpose (a "Hide spam" toggle can turn it off), and GDKP — a legit pug loot
-- system — is deliberately NOT treated as spam.
local Spam = {}

local SPAM_WORDS = {
    "wts", "w t s", "wtb", "w t b",
    "selling", "buying", "sell gold", "buy gold", "cheap gold", "gold seller",
    "boost", "boosting", "boosted",
    "carry", "carries",
    "powerlevel", "power level", "leveling service", "lvl boost", "level boost",
    "rmt", "real money", "usd", "eur ",
    "discord.gg", "discord .gg", ".gg/",
    "http", "www.", ".com", ".net", ".store", ".shop", ".gold",
}

local SPAM_PATTERNS = {
    "%d+%s?g%f[%A]",   -- "500g", "350 g"  (gold price)
    "%d+%s?gold",      -- "500 gold"
    "[%$€£]%s?%d",     -- "$10", "€5"
    "%d+%s?usd",       -- "10 usd"
}

function Spam.IsSpam(text)
    if not text or text == "" then
        return false
    end
    local t = Utils.SafeLower(text)
    for _, word in ipairs(SPAM_WORDS) do
        if string.find(t, word, 1, true) then
            return true
        end
    end
    for _, pattern in ipairs(SPAM_PATTERNS) do
        if string.find(t, pattern) then
            return true
        end
    end
    return false
end

_G[ADDON_NAME .. "_Spam"] = Spam
return Spam
