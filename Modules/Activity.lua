local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- WoW: Forever's dungeons and raids: vanilla, plus the new dungeons (GuildOS Data/ForeverDungeons.lua for the
-- instance ids, Lodestar's Guides/Dungeons for the names). The new ones carry no level range: no source gives
-- one yet. Aliases are lowercase; the longest alias found in a line wins, so "dm east" beats "dm".
local Activity = {}

Activity.LIST = {
    { key = "rfc", name = "Ragefire Chasm", type = "dungeon", minLevel = 13, maxLevel = 18,
        aliases = { "rfc", "ragefire", "ragefire chasm", "flammenschlund", "gouffre de ragefeu", "sima ígnea" } },
    { key = "wc", name = "Wailing Caverns", type = "dungeon", minLevel = 17, maxLevel = 24,
        aliases = { "wc", "wailing caverns", "höhlen des wehklagens", "cavernes des lamentations",
            "cuevas de los lamentos" } },
    { key = "dm", name = "The Deadmines", type = "dungeon", minLevel = 17, maxLevel = 26,
        aliases = { "dm", "vc", "deadmines", "minas mortas", "todesminen", "mortemines", "minas de la muerte" } },
    { key = "sfk", name = "Shadowfang Keep", type = "dungeon", minLevel = 22, maxLevel = 30,
        aliases = { "sfk", "shadowfang", "burg schattenfang", "donjon d'ombrecroc", "castillo de colmillo oscuro" } },
    { key = "bfd", name = "Blackfathom Deeps", type = "dungeon", minLevel = 24, maxLevel = 32,
        aliases = { "bfd", "blackfathom", "tiefschwarze grotte", "profondeurs de brassenoire",
            "cavernas de brazanegra" } },
    { key = "stocks", name = "The Stockade", type = "dungeon", minLevel = 24, maxLevel = 32,
        aliases = { "stocks", "stockade", "stockades", "verlies" } },
    { key = "gnomer", name = "Gnomeregan", type = "dungeon", minLevel = 29, maxLevel = 38,
        aliases = { "gnomer", "gnomeregan" } },
    { key = "rfk", name = "Razorfen Kraul", type = "dungeon", minLevel = 29, maxLevel = 38,
        aliases = { "rfk", "razorfen kraul", "kral der klingenhauer", "kraal de tranchebauge", "horado rajacieno" } },
    { key = "sm", name = "Scarlet Monastery", type = "dungeon", minLevel = 28, maxLevel = 45,
        aliases = { "sm", "scarlet", "scarlet monastery", "mosteiro escarlate", "scharlachrotes kloster",
            "monastère écarlate", "monasterio escarlata" } },
    { key = "smgy", name = "Scarlet Monastery: Graveyard", type = "dungeon", minLevel = 28, maxLevel = 38,
        aliases = { "sm gy", "smgy", "sm graveyard", "graveyard" } },
    { key = "smlib", name = "Scarlet Monastery: Library", type = "dungeon", minLevel = 29, maxLevel = 39,
        aliases = { "sm lib", "smlib", "sm library", "library" } },
    { key = "smarm", name = "Scarlet Monastery: Armory", type = "dungeon", minLevel = 32, maxLevel = 42,
        aliases = { "sm arm", "smarm", "sm armory", "armory", "armoury" } },
    { key = "smcath", name = "Scarlet Monastery: Cathedral", type = "dungeon", minLevel = 35, maxLevel = 45,
        aliases = { "sm cath", "smcath", "sm cathedral", "cathedral", "cath" } },
    { key = "rfd", name = "Razorfen Downs", type = "dungeon", minLevel = 37, maxLevel = 46,
        aliases = { "rfd", "razorfen downs", "hügel der klingenhauer", "souilles de tranchebauge",
            "zahúrda rajacieno" } },
    { key = "ulda", name = "Uldaman", type = "dungeon", minLevel = 41, maxLevel = 51,
        aliases = { "ulda", "uld", "uldaman" } },
    { key = "zf", name = "Zul'Farrak", type = "dungeon", minLevel = 44, maxLevel = 54,
        aliases = { "zf", "zul'farrak", "zulfarrak", "zul farrak" } },
    { key = "mara", name = "Maraudon", type = "dungeon", minLevel = 46, maxLevel = 55,
        aliases = { "mara", "maraudon" } },
    { key = "st", name = "The Temple of Atal'Hakkar", type = "dungeon", minLevel = 50, maxLevel = 56,
        aliases = { "st", "sunken temple", "atal'hakkar", "atalhakkar", "templo submerso", "versunkene tempel",
            "temple englouti", "templo sumergido" } },
    { key = "brd", name = "Blackrock Depths", type = "dungeon", minLevel = 52, maxLevel = 60,
        aliases = { "brd", "blackrock depths", "profundezas rocha negra", "schwarzfelstiefen",
            "profondeurs de rochenoire", "profundidades de roca negra" } },
    { key = "lbrs", name = "Lower Blackrock Spire", type = "dungeon", minLevel = 55, maxLevel = 60,
        aliases = { "lbrs", "lower blackrock", "lower spire" } },
    { key = "ubrs", name = "Upper Blackrock Spire", type = "dungeon", minLevel = 55, maxLevel = 60, size = 10,
        aliases = { "ubrs", "upper blackrock", "upper spire" } },
    { key = "dme", name = "Dire Maul: East", type = "dungeon", minLevel = 55, maxLevel = 60,
        aliases = { "dme", "dm east", "dm:e", "dire maul east" } },
    { key = "dmw", name = "Dire Maul: West", type = "dungeon", minLevel = 57, maxLevel = 60,
        aliases = { "dmw", "dm west", "dm:w", "dire maul west" } },
    { key = "dmn", name = "Dire Maul: North", type = "dungeon", minLevel = 57, maxLevel = 60,
        aliases = { "dmn", "dm north", "dm:n", "dire maul north", "dm tribute", "tribute run" } },
    { key = "diremaul", name = "Dire Maul", type = "dungeon", minLevel = 55, maxLevel = 60,
        aliases = { "dire maul", "düsterbruch", "hache-tripes", "la masacre" } },
    { key = "scholo", name = "Scholomance", type = "dungeon", minLevel = 58, maxLevel = 60,
        aliases = { "scholo", "scholomance" } },
    { key = "strat", name = "Stratholme", type = "dungeon", minLevel = 58, maxLevel = 60,
        aliases = { "strat", "strath", "stratholme", "strat live", "strat ud", "baron run" } },

    { key = "dalaran", name = "City of Dalaran", type = "dungeon", instanceID = 2959, isNew = true,
        aliases = { "dalaran", "city of dalaran", "cidade de dalaran", "dala" } },
    { key = "rol", name = "Ruins of Lordaeron", type = "dungeon", instanceID = 2999, isNew = true,
        aliases = { "rol", "ruins of lordaeron", "lordaeron", "ruínas de lordaeron", "ruinas de lordaeron" } },
    { key = "excavation", name = "Excavation Site: Wetlands", type = "dungeon", instanceID = 2998, isNew = true,
        aliases = { "excavation", "excavation site", "excavation site wetlands", "escavação" } },
    { key = "thanes", name = "The Hall of Thanes", type = "dungeon", instanceID = 3065, isNew = true,
        aliases = { "thanes", "hall of thanes", "salão dos thanes" } },
    { key = "mistmantle", name = "Manor Mistmantle", type = "dungeon", instanceID = 3109, isNew = true,
        aliases = { "mistmantle", "manor mistmantle" } },
    { key = "drowned", name = "The Drowned City", type = "dungeon", isNew = true,
        aliases = { "drowned city", "the drowned city" } },
    { key = "kroldok", name = "Krol'dok Stronghold", type = "dungeon", isNew = true,
        aliases = { "krol'dok", "kroldok", "krol dok" } },
    { key = "alcaz", name = "Alcaz Prison", type = "dungeon", isNew = true,
        aliases = { "alcaz", "alcaz prison" } },
    { key = "blackmaw", name = "Blackmaw Hold", type = "dungeon", isNew = true,
        aliases = { "blackmaw", "blackmaw hold" } },
    { key = "shapers", name = "Shaper's Terrace", type = "dungeon", isNew = true,
        aliases = { "shaper's terrace", "shapers terrace", "shaper terrace" } },

    { key = "mc", name = "Molten Core", type = "raid", minLevel = 60, maxLevel = 60, size = 40,
        aliases = { "mc", "molten core", "núcleo derretido", "geschmolzener kern", "cœur du magma",
            "núcleo de magma" } },
    { key = "ony", name = "Onyxia's Lair", type = "raid", minLevel = 60, maxLevel = 60, size = 40,
        aliases = { "ony", "onyxia", "onyxia's lair", "covil de onyxia", "onyxias hort", "repaire d'onyxia",
            "guarida de onyxia" } },
    { key = "zg", name = "Zul'Gurub", type = "raid", minLevel = 60, maxLevel = 60, size = 20,
        aliases = { "zg", "zul'gurub", "zulgurub", "zul gurub" } },
    { key = "bwl", name = "Blackwing Lair", type = "raid", minLevel = 60, maxLevel = 60, size = 40,
        aliases = { "bwl", "blackwing lair", "blackwing", "covil asa negra", "pechschwingenhort",
            "repaire de l'aile noire", "guarida alanegra" } },
    { key = "aq20", name = "Ruins of Ahn'Qiraj", type = "raid", minLevel = 60, maxLevel = 60, size = 20,
        aliases = { "aq20", "aq 20", "ruins of ahn'qiraj", "raq" } },
    { key = "aq40", name = "Temple of Ahn'Qiraj", type = "raid", minLevel = 60, maxLevel = 60, size = 40,
        aliases = { "aq40", "aq 40", "aq", "temple of ahn'qiraj", "taq" } },
    { key = "naxx", name = "Naxxramas", type = "raid", minLevel = 60, maxLevel = 60, size = 40,
        aliases = { "naxx", "naxxramas" } },
}

Activity.byKey = {}
for _, a in ipairs(Activity.LIST) do
    a.size = a.size or 5
    Activity.byKey[a.key] = a
end

function Activity.Get(key)
    return key and Activity.byKey[key] or nil
end

-- The activity a line names, or nil. Whole words for ASCII aliases ("st" never inside "first").
function Activity.Guess(message)
    local text = Utils.SafeLower(message)
    local best, bestLen = nil, 0
    for _, a in ipairs(Activity.LIST) do
        for _, alias in ipairs(a.aliases) do
            if #alias > bestLen and Utils.ContainsWord(text, alias) then
                best, bestLen = a, #alias
            end
        end
    end
    return best
end

-- Sorted for a picker: dungeons by level (the new ones, levelless, after them), then raids.
function Activity.Sorted()
    local out = {}
    for _, a in ipairs(Activity.LIST) do
        out[#out + 1] = {
            key = a.key, name = a.name, type = a.type, minLevel = a.minLevel, maxLevel = a.maxLevel,
            size = a.size, isNew = a.isNew == true, instanceID = a.instanceID,
        }
    end
    local function rank(a)
        return (a.type == "raid" and 1000 or 0) + (a.minLevel or 99)
    end
    table.sort(out, function(a, b)
        if rank(a) ~= rank(b) then
            return rank(a) < rank(b)
        end
        return a.name < b.name
    end)
    return out
end

-- Wanted totals including the leader, by group size.
function Activity.DefaultWant(key)
    local size = (Activity.Get(key) or {}).size or 5
    if size >= 40 then
        return { tank = 4, heal = 8, dps = 28 }
    elseif size >= 20 then
        return { tank = 2, heal = 4, dps = 14 }
    elseif size >= 10 then
        return { tank = 2, heal = 3, dps = 5 }
    end
    return { tank = 1, heal = 1, dps = 3 }
end

_G[ADDON_NAME .. "_Activity"] = Activity
return Activity
