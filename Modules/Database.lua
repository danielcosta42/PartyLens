local ADDON_NAME = ...

-- The Forever line starts from a clean save: nothing of the Anniversary schema (specs, autopilot tiers,
-- reputation, layer beacon, Group Finder keys) means anything here.
local Database = {}

Database.SCHEMA = 100

local function Defaults()
    return {
        schemaVersion = Database.SCHEMA,
        roles = { tank = false, heal = false, dps = true },
        comment = "",
        whisperTemplate = "",
        filters = {
            roles = { tank = false, heal = false, dps = false },
            type = "all",
            activityType = "all",
            activity = "",
            query = "",
            onlyOpen = true,
            hideSpam = true,
        },
        blacklist = {},
        listing = {
            type = "lfm",
            activity = "",
            label = "",
            want = { tank = 1, heal = 1, dps = 3 },
            comment = "",
        },
        joinLFGChannel = true,
        alertOnMatch = false,
        animations = true,
        minimap = { hide = false, angle = 225 },
        ui = {},
        alertDismissed = {},
    }
end

-- Fills what is missing, at any depth, without touching what the player chose.
local function Backfill(into, from)
    for key, value in pairs(from) do
        if into[key] == nil then
            into[key] = value
        elseif type(value) == "table" and type(into[key]) == "table" then
            Backfill(into[key], value)
        end
    end
end

function Database.EnsureDB(partyLens)
    if type(PartyLensDB) ~= "table" or (tonumber(PartyLensDB.schemaVersion) or 0) < Database.SCHEMA then
        PartyLensDB = {}
    end
    Backfill(PartyLensDB, Defaults())
    partyLens.db = PartyLensDB
    return PartyLensDB
end

_G[ADDON_NAME .. "_Database"] = Database
return Database
