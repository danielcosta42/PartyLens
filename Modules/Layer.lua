local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- Standalone layer detection — no NWB / AutoLayer dependency.
--
-- Technique (reverse-engineered from NWB, reimplemented from scratch): a creature
-- GUID is "Creature-0-<serverID>-<instanceID>-<zoneUID>-<npcID>-<spawnUID>". The
-- 5th dash-field (zoneUID) is unique per physical zone-instance = per LAYER. We
-- harvest it from any non-player-controlled creature we target / mouseover / see,
-- record the raw zoneUID per map, and map it to a stable 1-based ordinal (the
-- sorted position of that zoneUID among all zoneUIDs we've seen on that map) — so
-- "Layer 1" is the smallest zoneUID, "Layer 2" the next, etc.
--
-- Pure string parsing: NO GetPlayerInfoByGUID (engine-agnostic; safe on this
-- modern-engine Anniversary client). Player/pet/guardian units are rejected —
-- they carry the OWNER's home-layer zoneUID and would corrupt detection.
local Layer = {}

-- Capital-city UI-map that anchors the friendly ordinal (most stable place to
-- detect, since it's where hopping happens). Shattrath on TBC.
Layer.CAPITAL_MAP = 1955

-- A raw zoneUID we consider stale/unknown after this long without re-sighting
-- (layers get recycled as the server rebalances). Kept generous.
Layer.SEEN_TTL = 6 * 3600

local function DB(partyLens)
    local db = partyLens.db
    db.layer = db.layer or {}
    db.layer.seen = db.layer.seen or {} -- [mapID] = { [zoneUID] = lastSeenEpoch }
    return db.layer
end

-- Extract the zoneUID (layer discriminator) from a unit's creature GUID, or nil.
function Layer.ZoneUIDFromUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then
        return nil -- players / pets / guardians carry the wrong (owner's) layer
    end
    local guid = UnitGUID(unit)
    if not guid then
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

-- The map we're currently on (best-effort; falls back to 0). Cached for ~1s so
-- harvesting from a burst of nameplates in a city stays cheap.
local _mapCache, _mapCacheAt = nil, 0
function Layer.CurrentMap()
    local now = (GetTime and GetTime()) or 0
    if _mapCache and (now - _mapCacheAt) < 1 then
        return _mapCache
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and id then
            _mapCache, _mapCacheAt = id, now
            return id
        end
    end
    return _mapCache or 0
end

-- Records a zoneUID sighting for a map and (if it's our current map) updates the
-- live current-layer reading. Returns true if the current layer changed.
local function Record(partyLens, mapID, zoneUID)
    local layerDB = DB(partyLens)
    local mapSeen = layerDB.seen[mapID]
    if not mapSeen then
        mapSeen = {}
        layerDB.seen[mapID] = mapSeen
    end
    local isNew = mapSeen[zoneUID] == nil
    mapSeen[zoneUID] = time()

    -- Only the map we're standing on defines "our current layer".
    if mapID ~= Layer.CurrentMap() then
        return false
    end
    local prevZone = layerDB.currentZoneUID
    layerDB.currentMap = mapID
    layerDB.currentZoneUID = zoneUID
    layerDB.currentSince = layerDB.currentSince or time()
    if prevZone ~= zoneUID then
        layerDB.currentSince = time()
    end
    return isNew or prevZone ~= zoneUID
end

-- Harvests the layer from a unit (target/mouseover/nameplate). Returns true if the
-- current-layer reading changed (so callers can refresh UI / re-broadcast).
function Layer.Observe(partyLens, unit)
    local zoneUID = Layer.ZoneUIDFromUnit(unit)
    if not zoneUID then
        return false
    end
    return Record(partyLens, Layer.CurrentMap(), zoneUID)
end

-- Sorted list of the zoneUIDs known on a map (ascending) — the ordinal basis.
-- PURE: depends only on WHICH zoneUIDs are known, never on WHEN each was last
-- seen, so two clients holding the same set always compute the SAME ordinals
-- (the cross-client contract). Staleness is handled separately by Layer.PruneSeen
-- on a fixed cadence, not as a side effect of this lookup.
local function SortedZoneUIDs(layerDB, mapID)
    local mapSeen = layerDB.seen[mapID]
    if not mapSeen then
        return {}
    end
    local list = {}
    for zoneUID in pairs(mapSeen) do
        list[#list + 1] = zoneUID
    end
    table.sort(list)
    return list
end

-- Ordinal (1-based) of a zoneUID within a map's sorted set, or nil.
function Layer.OrdinalOf(partyLens, mapID, zoneUID)
    if not zoneUID then
        return nil
    end
    for i, z in ipairs(SortedZoneUIDs(DB(partyLens), mapID)) do
        if z == zoneUID then
            return i
        end
    end
    return nil
end

-- How many distinct layers we've seen on a map (the "N of M" denominator).
function Layer.CountOnMap(partyLens, mapID)
    return #SortedZoneUIDs(DB(partyLens), mapID)
end

-- Public accessor: the sorted zoneUIDs known on a map (ordinal = index). For the UI.
function Layer.KnownZones(partyLens, mapID)
    return SortedZoneUIDs(DB(partyLens), mapID)
end

-- The player's current layer, as { zoneUID, ordinal, mapID, count, fresh }.
-- `ordinal` is the friendly number (nil until we've sighted an NPC); `zoneUID` is
-- the absolute identity used for exact addon-to-addon matching.
function Layer.Current(partyLens)
    local layerDB = DB(partyLens)
    local mapID = layerDB.currentMap or Layer.CurrentMap()
    local zoneUID = layerDB.currentZoneUID
    return {
        mapID = mapID,
        zoneUID = zoneUID,
        ordinal = Layer.OrdinalOf(partyLens, mapID, zoneUID),
        count = Layer.CountOnMap(partyLens, mapID),
        since = layerDB.currentSince,
        isCapital = mapID == Layer.CAPITAL_MAP,
    }
end

-- Merge a peer's observed zoneUIDs (shared over the mesh) so our ordinals converge
-- with theirs — layer numbers only agree between players who've seen the same set.
-- REFRESHES the timestamp on every hear (not just first insert): a layer anyone is
-- actively broadcasting never ages out, and truly-dead layers age out on every
-- client at ~the same time, keeping the sorted set (and thus ordinals) aligned.
function Layer.MergeSeen(partyLens, mapID, zoneUIDs)
    if not mapID or type(zoneUIDs) ~= "table" then
        return
    end
    local layerDB = DB(partyLens)
    layerDB.seen[mapID] = layerDB.seen[mapID] or {}
    local now = time()
    for _, z in ipairs(zoneUIDs) do
        z = tonumber(z)
        if z and z > 0 then
            layerDB.seen[mapID][z] = now
        end
    end
end

-- The absolute zoneUID at a given 1-based ordinal on a map (nil if we haven't seen
-- that many layers). Lets a requester resolve "layer N" to its zoneUID identity so
-- matching can be frame-independent (exact) instead of trusting bare numbers.
function Layer.ZoneUIDAt(partyLens, mapID, ordinal)
    if not ordinal then
        return nil
    end
    return SortedZoneUIDs(DB(partyLens), mapID)[ordinal]
end

-- Comma-separated sorted zoneUIDs for a map — broadcast so peers converge on the
-- FULL set, not just whatever layer each is currently standing on. Bounded by a
-- BYTE budget (not an element count) so the assembled S message stays under the
-- 255-byte SendAddonMessage limit regardless of how wide the zoneUID integers are
-- (an over-length addon message is rejected wholesale). Lowest zoneUIDs go first,
-- so clients share the same low prefix and low layer numbers still converge; and
-- real invites stay correct regardless (they match on exact zoneUID identity, not
-- the ordinal). A capital realistically has a handful of live layers, far under this.
function Layer.SeenCSV(partyLens, mapID, maxBytes)
    local list = SortedZoneUIDs(DB(partyLens), mapID)
    maxBytes = maxBytes or 210 -- ~255 minus room for the "PLL1|S|<map>|<zone>|<b>|" header
    local out, used = {}, 0
    for i = 1, #list do
        local s = tostring(list[i])
        local add = #s + (i > 1 and 1 or 0) -- +1 for the joining comma
        if used + add > maxBytes then
            break
        end
        out[#out + 1] = s
        used = used + add
    end
    return table.concat(out, ",")
end

-- Drop zoneUIDs not seen within SEEN_TTL, across all maps. Called on a fixed
-- cadence (NOT per ordinal-lookup) so ordinals stay stable between refreshes.
function Layer.PruneSeen(partyLens)
    local layerDB = DB(partyLens)
    local now = time()
    for _, mapSeen in pairs(layerDB.seen) do
        for zoneUID, seenAt in pairs(mapSeen) do
            if (now - (seenAt or 0)) > Layer.SEEN_TTL then
                mapSeen[zoneUID] = nil
            end
        end
    end
end

_G[ADDON_NAME .. "_Layer"] = Layer
return Layer
