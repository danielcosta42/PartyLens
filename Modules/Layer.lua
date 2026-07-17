local ADDON_NAME = ...

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

-- The npcID (field 6 of a creature GUID) for a unit, or nil — identifies WHICH
-- creature it is (world boss, rare), independent of which layer it's on. Same GUID
-- parse as the layer detection, just the next field.
function Layer.NpcIDFromUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then
        return nil
    end
    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return nil
    end
    return tonumber(npcID)
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

-- Layer SEGMENT (continent): layers are numbered INDEPENDENTLY per segment (Azeroth vs
-- Outland), so "layer 3" in Orgrimmar is NOT the "layer 3" a Shattrath beacon sits on.
-- A cross-segment hop request is a wrong-world match. We reuse the SAME <AZ>/<OL> request
-- tag AutoLayer uses, so the two addons filter each other's tagged requests correctly.
-- Detection walks the map's parent chain to the continent map, with overrides for the BC
-- starting zones whose continent map differs from their layer segment. Continent mapIDs and
-- overrides are AutoLayer's (maintained for this exact client).
Layer.SEGMENT_MAPS = { [947] = "AZ", [1945] = "OL" }
Layer.SEGMENT_OVERRIDES = {
    [1941] = "OL", [1942] = "OL", [1943] = "OL", [1947] = "OL",
    [1950] = "OL", [1954] = "OL", [1957] = "OL",
}

-- Cache by mapID: a map's continent is STATIC, so this never needs invalidating. `false`
-- marks "resolved to no segment" so we don't re-walk (e.g. arenas/instances with no map).
local _segCache = {}
function Layer.Segment(unit)
    unit = unit or "player"
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit(unit)
    if not mapID then
        return nil
    end
    if _segCache[mapID] ~= nil then
        return _segCache[mapID] or nil
    end
    local seg
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapID and guard < 30 do
        guard = guard + 1
        if Layer.SEGMENT_OVERRIDES[info.mapID] then
            seg = Layer.SEGMENT_OVERRIDES[info.mapID]
            break
        end
        if Layer.SEGMENT_MAPS[info.mapID] then
            seg = Layer.SEGMENT_MAPS[info.mapID]
            break
        end
        if not info.parentMapID or info.parentMapID == 0 then
            break
        end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    _segCache[mapID] = seg or false
    return seg
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
    -- When NWB has an authoritative current-layer reading, it OWNS `currentZoneUID`
    -- (Layer.Current latches it). Our raw harvest still fills the seen set above, but we
    -- must NOT overwrite `current` with a possibly-junk zoneUID from a non-city creature
    -- — that would fight the NWB latch and thrash `currentSince` on every nameplate.
    local _, nwbZone = Layer.NWBCurrent()
    if nwbZone and zoneUID ~= nwbZone then
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

-- ---------------------------------------------------------------------------
-- NovaWorldBuffs alignment (optional). NWB is the community-standard layer
-- numbering: it derives its zoneID from the SAME creature-GUID field we do, and
-- numbers layers by sorted-zoneID index — but over a FULLER, realm-shared set,
-- so a physical layer we call "3" (of 4 we've seen) is NWB's "5" (of more). When
-- NWB is installed we defer to ITS number so PartyLens shows and matches the same
-- "Layer N" everyone else does; when it's absent we use our own ordinal (fully
-- standalone). NWB isn't a global — it's an AceAddon object, fetched by name.
-- ---------------------------------------------------------------------------
local _nwb
local function GetNWB()
    if _nwb then
        return _nwb
    end
    local LibStub = _G.LibStub
    if not LibStub then
        return nil
    end
    local ok, ace = pcall(LibStub, "AceAddon-3.0", true)
    if not ok or not ace or not ace.GetAddon then
        return nil
    end
    local ok2, nwb = pcall(ace.GetAddon, ace, "NovaWorldBuffs", true)
    if ok2 and nwb and nwb.GetLayerNum and nwb.getLayerZoneID then
        _nwb = nwb
        return nwb
    end
    return nil
end

-- Is NovaWorldBuffs installed and exposing the API we defer to? (diagnostics/UI hint)
function Layer.HasNWB()
    return GetNWB() ~= nil
end

-- NWB's layer number for a zoneUID (nil if NWB absent or it doesn't know it).
function Layer.NWBNumber(zoneUID)
    local nwb = GetNWB()
    if not nwb or not zoneUID then
        return nil
    end
    local ok, n = pcall(nwb.GetLayerNum, nwb, zoneUID)
    if ok and type(n) == "number" and n > 0 then
        return n
    end
    return nil
end

-- NWB's OWN reading of the layer the player is standing on RIGHT NOW: returns
-- (layerNumber, zoneID) — the exact number shown on NWB's minimap plus that layer's
-- zoneID. This is the authoritative source for MY current layer, because NWB derives
-- it from its VALIDATED, realm-shared layer set (only real capital-city NPCs), whereas
-- our own detection harvests from ANY creature and can latch onto a junk/stale zoneUID
-- that isn't in NWB's set — which is exactly why `GetLayerNum(ourZoneUID)` was
-- returning 0 and we fell back to our own "Layer 1". Returns nil when NWB is absent or
-- hasn't resolved a layer yet (e.g. no city NPC targeted since the last zone change).
function Layer.NWBCurrent()
    local nwb = GetNWB()
    if not nwb or not nwb.getCurrentLayerNum or not nwb.getLayerZoneID then
        return nil
    end
    local ok, num = pcall(nwb.getCurrentLayerNum, nwb)
    if not ok or type(num) ~= "number" or num <= 0 then
        return nil
    end
    local ok2, zone = pcall(nwb.getLayerZoneID, nwb, num)
    if ok2 and type(zone) == "number" and zone > 0 then
        return num, zone
    end
    return num, nil
end

-- Ordinal (1-based) of a zoneUID — NWB's number when it knows this layer, else our
-- own sorted-index within the map's seen set.
function Layer.OrdinalOf(partyLens, mapID, zoneUID)
    if not zoneUID then
        return nil
    end
    local nwbNum = Layer.NWBNumber(zoneUID)
    if nwbNum then
        return nwbNum
    end
    for i, z in ipairs(SortedZoneUIDs(DB(partyLens), mapID)) do
        if z == zoneUID then
            return i
        end
    end
    return nil
end

-- How many distinct layers exist (the "N of M" denominator) — NWB's realm-wide
-- count when present, else how many we've personally seen on this map.
function Layer.CountOnMap(partyLens, mapID)
    local nwb = GetNWB()
    if nwb and nwb.data and nwb.data.layers then
        local n = 0
        for _ in pairs(nwb.data.layers) do
            n = n + 1
        end
        if n > 0 then
            return n
        end
    end
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
    -- Defer to NWB's OWN current-layer reading when it has one — it's the number the
    -- player sees on NWB, from NWB's validated set — so we never disagree with NWB about
    -- "which layer am I on". We also LATCH our identity onto NWB's exact zoneID so (a) our
    -- mesh broadcasts carry the same zoneUID a non-NWB PartyLens user reads from the same
    -- validated NPC (they still match), and (b) our numbering can't drift onto a junk
    -- zoneUID harvested from a non-city creature NWB filters out (the "Layer 1" bug).
    local nwbNum, nwbZone = Layer.NWBCurrent()
    if nwbNum and nwbZone and layerDB.currentZoneUID ~= nwbZone then
        layerDB.currentMap = mapID
        layerDB.currentZoneUID = nwbZone
        layerDB.seen[mapID] = layerDB.seen[mapID] or {}
        layerDB.seen[mapID][nwbZone] = time()
        layerDB.currentSince = time() -- real layer change: reset the "on this layer since"
    end
    local zoneUID = layerDB.currentZoneUID
    return {
        mapID = mapID,
        zoneUID = zoneUID,
        ordinal = nwbNum or Layer.OrdinalOf(partyLens, mapID, zoneUID),
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
    -- Prefer NWB's number->zoneUID so resolving "layer 5" targets the exact layer
    -- the community calls 5 (consistent with OrdinalOf using NWB's number).
    local nwb = GetNWB()
    if nwb then
        local ok, z = pcall(nwb.getLayerZoneID, nwb, ordinal)
        if ok and type(z) == "number" and z > 0 then
            return z
        end
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
