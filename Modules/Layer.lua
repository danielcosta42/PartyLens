local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- My layer. A creature's GUID is "Creature-0-<server>-<instance>-<zoneUID>-<npc>-<spawn>"; the zoneUID is one
-- physical copy of the zone, a layer. It is read off any NPC targeted, moused over or shown with a nameplate,
-- never off a player, pet or guardian (they carry their owner's home layer). Layers are numbered per map by
-- sorting the zoneUIDs this client knows there: a local label, the zoneUID is the identity.
local Layer = {}

Layer.SEEN_TTL = 2 * 3600

local function State(partyLens)
    partyLens.layerState = partyLens.layerState or { seen = {} } -- seen[mapID][zoneUID] = time()
    return partyLens.layerState
end

function Layer.CurrentMap()
    local id = C_Map.GetBestMapForUnit("player")
    if Utils.IsSecret(id) then
        return nil
    end
    return id
end

function Layer.ZoneUIDFromUnit(unit)
    if Utils.IsSecret(unit) or not UnitExists(unit) then
        return nil
    end
    local isPlayer, controlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
    if Utils.IsSecret(isPlayer, controlled) or isPlayer or controlled then
        return nil
    end
    local guid = UnitGUID(unit)
    if Utils.IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return nil
    end
    zoneUID = tonumber(zoneUID)
    if not zoneUID or zoneUID == 0 then
        return nil
    end
    return zoneUID
end

-- Remembers a zoneUID I saw on a map, for the numbering. Only my own sightings: a number fed by the network
-- could be spoofed into "layer 31 of 31".
local function Note(partyLens, mapID, zoneUID)
    local seen = State(partyLens).seen
    seen[mapID] = seen[mapID] or {}
    seen[mapID][zoneUID] = time()
end

-- A sighting from a unit; true when my layer changed.
function Layer.Observe(partyLens, unit)
    if Utils.InInstance() then
        return false
    end
    local zoneUID = Layer.ZoneUIDFromUnit(unit)
    local mapID = Layer.CurrentMap()
    if not zoneUID or not mapID then
        return false
    end
    local st = State(partyLens)
    Note(partyLens, mapID, zoneUID)
    if st.mapID == mapID and st.zoneUID == zoneUID then
        return false
    end
    st.mapID, st.zoneUID, st.since = mapID, zoneUID, time()
    partyLens:Fire("LAYER_CHANGED", Layer.Current(partyLens))
    return true
end

local function Sorted(partyLens, mapID)
    local list = {}
    for zoneUID in pairs(State(partyLens).seen[mapID] or {}) do
        list[#list + 1] = zoneUID
    end
    table.sort(list)
    return list
end

function Layer.OrdinalOf(partyLens, mapID, zoneUID)
    for i, z in ipairs(Sorted(partyLens, mapID)) do
        if z == zoneUID then
            return i
        end
    end
end

function Layer.KnownZones(partyLens, mapID)
    return Sorted(partyLens, mapID)
end

-- { mapID, zoneUID, ordinal, count, since, inInstance }. A reading from another map, or from inside an
-- instance, is no layer for where I stand now.
function Layer.Current(partyLens)
    local st = State(partyLens)
    local mapID = Layer.CurrentMap()
    local inInstance = Utils.InInstance()
    local zoneUID = (not inInstance and mapID and st.mapID == mapID) and st.zoneUID or nil
    return {
        mapID = mapID,
        zoneUID = zoneUID,
        ordinal = zoneUID and Layer.OrdinalOf(partyLens, mapID, zoneUID) or nil,
        count = mapID and #Sorted(partyLens, mapID) or 0,
        since = zoneUID and st.since or nil,
        inInstance = inInstance,
    }
end

function Layer.Prune(partyLens)
    local now = time()
    for _, zones in pairs(State(partyLens).seen) do
        for zoneUID, at in pairs(zones) do
            if now - at > Layer.SEEN_TTL then
                zones[zoneUID] = nil
            end
        end
    end
end

_G[ADDON_NAME .. "_Layer"] = Layer
return Layer
