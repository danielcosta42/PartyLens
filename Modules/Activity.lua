local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

local Activity = {}

Activity.ACTIVITY_ALIASES = {
    { key = "karazhan", name = "Karazhan", aliases = { "kara", "karazhan" }, raid = true },
    { key = "gruul", name = "Gruul", aliases = { "gruul", "grull" }, raid = true },
    { key = "magtheridon", name = "Magtheridon", aliases = { "magtheridon", "mag", "maggy" }, raid = true },
    { key = "ssc", name = "Serpentshrine Cavern", aliases = { "ssc", "serpentshrine" }, raid = true },
    { key = "tk", name = "Tempest Keep", aliases = { "tk", "tempest keep", "the eye" }, raid = true },
    { key = "hyjal", name = "Hyjal", aliases = { "hyjal", "mount hyjal" }, raid = true },
    { key = "bt", name = "Black Temple", aliases = { "bt", "black temple" }, raid = true },
    { key = "za", name = "Zul'Aman", aliases = { "za", "zul'aman", "zulaman" }, raid = true },
    { key = "swp", name = "Sunwell Plateau", aliases = { "swp", "sunwell" }, raid = true },

    { key = "ramparts", name = "Hellfire Ramparts", aliases = { "ramparts", "ramps", "rampa" } },
    { key = "bf", name = "The Blood Furnace", aliases = { "blood furnace", "bf" } },
    { key = "shh", name = "The Shattered Halls", aliases = { "shattered halls", "shh", "sh" } },
    { key = "sp", name = "The Slave Pens", aliases = { "slave pens", "sp" } },
    { key = "ub", name = "The Underbog", aliases = { "underbog", "ub" } },
    { key = "sv", name = "The Steamvault", aliases = { "steamvault", "sv" } },
    { key = "mt", name = "Mana-Tombs", aliases = { "mana tombs", "mana-tombs", "mt" } },
    { key = "ac", name = "Auchenai Crypts", aliases = { "auchenai", "crypts", "ac" } },
    { key = "sethekk", name = "Sethekk Halls", aliases = { "sethekk", "sethekk halls", "seth" } },
    { key = "slabs", name = "Shadow Labyrinth", aliases = { "shadow labs", "shadow labyrinth", "slabs", "sl" } },
    { key = "mech", name = "The Mechanar", aliases = { "mechanar", "mech" } },
    { key = "bot", name = "The Botanica", aliases = { "botanica", "bot" } },
    { key = "arc", name = "The Arcatraz", aliases = { "arcatraz", "arc" } },
    { key = "ohb", name = "Old Hillsbrad", aliases = { "old hillsbrad", "ohb", "hillsbrad" } },
    { key = "bm", name = "The Black Morass", aliases = { "black morass", "bm" } },
    { key = "mgt", name = "Magisters' Terrace", aliases = { "magisters", "terrace", "mgt", "mgterrace" } },
}

-- Detects the heroic flag using word boundaries so common words like "with",
-- "fresh" or "push" do not trip a bare "h " substring (the old behaviour).
local function LooksHeroic(text)
    if string.find(text, "heroic", 1, true) then -- covers "heroic" and "heroica"
        return true
    end
    -- Standalone "hc" or single-letter "h" abbreviations (e.g. "h ramps", "hc sv").
    if string.find(text, "%f[%a]hc%f[%A]") or string.find(text, "%f[%a]h%f[%A]") then
        return true
    end
    return false
end

function Activity.GuessActivity(message)
    local text = Utils.SafeLower(message)
    local heroic = LooksHeroic(text)

    for _, activity in ipairs(Activity.ACTIVITY_ALIASES) do
        for _, alias in ipairs(activity.aliases) do
            if string.find(text, alias, 1, true) then
                if heroic and not activity.raid then
                    -- Heroic 5-mans are dungeons, not raids: the third return
                    -- value is the raid flag and must stay false here.
                    return "Heroic " .. activity.name, activity.key, false
                end
                return activity.name, activity.key, activity.raid
            end
        end
    end

    if string.find(text, "raid", 1, true) then
        return "Raid", "raid", true
    end

    if heroic then
        return "Heroic Dungeon", "heroic", false
    end

    return "Outro", "other", false
end

_G[ADDON_NAME .. "_Activity"] = Activity
return Activity
