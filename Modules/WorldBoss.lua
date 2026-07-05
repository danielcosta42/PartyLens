local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local L = Localization.L
local WorldBoss = {}

-- ===========================================================================
-- World-boss & rare radar. Reuses the layer-detection GUID parse (field 6 = npcID)
-- to recognise notable creatures, shares each sighting over the LayerNet mesh with
-- the LAYER it's on, and lets people hop to that layer via the beacon we already
-- have. Practical (where's the boss?) AND marketing (a public "up on layer N!").
-- ===========================================================================

WorldBoss.SIGHTING_TTL = 600      -- a sighting stays "active" this long (seconds)
WorldBoss.BROADCAST_THROTTLE = 45 -- min seconds between our mesh broadcasts per boss
WorldBoss.ALERT_COOLDOWN = 120    -- min seconds between chat/sound alerts per boss

-- npcID -> { name (English fallback), kind = "boss"|"elite" }. The live UnitName is
-- preferred when we detect one ourselves; the fallback covers mesh-only sightings.
WorldBoss.CATALOG = {
    [18728] = { name = "Doom Lord Kazzak", kind = "boss" },
    [17711] = { name = "Doomwalker", kind = "boss" },
    [18733] = { name = "Fel Reaver", kind = "elite" },
}

local function RT(partyLens)
    if not partyLens.worldboss then
        partyLens.worldboss = {
            sightings = {}, -- [npcID] = { npcID, name, kind, mapID, zoneUID, hp, t, spotter }
            lastCast = {},  -- [npcID] = last mesh-broadcast epoch (throttle)
            lastAlert = {}, -- [npcID] = last chat/sound alert epoch
        }
    end
    return partyLens.worldboss
end

local function LN()
    return _G[ADDON_NAME .. "_LayerNet"]
end

local function Ordinal(partyLens, mapID, zoneUID)
    if not zoneUID then
        return nil
    end
    return Layer.OrdinalOf(partyLens, mapID, zoneUID)
end

-- UI hook (implemented by UIMain when the Layer tab exists).
function WorldBoss.Refresh(partyLens)
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.RefreshLayer then
        UIMain.RefreshLayer(partyLens)
    end
end

-- Record a sighting (local or from the mesh) and alert if it's newly up.
local function Record(partyLens, npcID, mapID, zoneUID, hp, spotter, name)
    local cat = WorldBoss.CATALOG[npcID]
    if not cat then
        return
    end
    local rt = RT(partyLens)
    if mapID and zoneUID and mapID > 0 and zoneUID > 0 then
        Layer.MergeSeen(partyLens, mapID, { zoneUID }) -- so the boss's layer can be numbered
    end
    local prev = rt.sightings[npcID]
    local isNew = not prev or (time() - (prev.t or 0)) > WorldBoss.SIGHTING_TTL
    rt.sightings[npcID] = {
        npcID = npcID,
        name = (name and name ~= "" and name) or (prev and prev.name) or cat.name,
        kind = cat.kind,
        mapID = mapID,
        zoneUID = zoneUID,
        hp = hp,
        t = time(),
        spotter = spotter,
    }
    -- Chat + sound alert, throttled, on a genuinely fresh sighting.
    if isNew and (time() - (rt.lastAlert[npcID] or 0)) >= WorldBoss.ALERT_COOLDOWN then
        rt.lastAlert[npcID] = time()
        local ord = Ordinal(partyLens, mapID, zoneUID)
        Utils.Print(L("WB_ALERT", rt.sightings[npcID].name, ord or "?"))
        if PlaySound then
            pcall(PlaySound, 8959) -- RaidWarning
        end
    end
    -- Only force a repaint for a NEW sighting (so the banner pops immediately);
    -- live hp / expiry are picked up by the Layer tab's 1.5s refresh ticker, so we
    -- don't repaint on every mouseover/nameplate during a boss fight.
    if isNew then
        WorldBoss.Refresh(partyLens)
    end
end

-- Detect a catalog creature from a unit we see (target / mouseover / nameplate).
function WorldBoss.Observe(partyLens, unit)
    if not Layer.NpcIDFromUnit then
        return
    end
    local npcID = Layer.NpcIDFromUnit(unit)
    if not npcID or not WorldBoss.CATALOG[npcID] then
        return
    end
    if UnitIsDead and UnitIsDead(unit) then
        return -- a corpse: don't advertise a dead boss
    end
    local zoneUID = Layer.ZoneUIDFromUnit(unit)
    local mapID = Layer.CurrentMap()
    local hp = 0
    if UnitHealthMax then
        local mx = UnitHealthMax(unit) or 0
        if mx > 0 then
            hp = math.floor((UnitHealth(unit) or 0) / mx * 100 + 0.5)
        end
    end
    Record(partyLens, npcID, mapID, zoneUID, hp, Utils.PlayerShortName(UnitName("player") or ""), UnitName(unit))

    -- Share it with the mesh (throttled) so the whole network learns where it is.
    local rt = RT(partyLens)
    if (time() - (rt.lastCast[npcID] or 0)) >= WorldBoss.BROADCAST_THROTTLE then
        rt.lastCast[npcID] = time()
        local ln = LN()
        if ln and ln.Broadcast and mapID and zoneUID and mapID > 0 and zoneUID > 0 then
            ln.Broadcast(table.concat({
                ln.NET_PROTO, "W", tostring(mapID), tostring(zoneUID), tostring(npcID), tostring(hp),
            }, "|"), "W:" .. npcID) -- realm-wide too, coalesced per boss (latest sighting)
        end
    end
end

-- A sighting heard from another PartyLens user over the mesh.
function WorldBoss.OnMeshSighting(partyLens, mapID, zoneUID, npcID, hp, spotter)
    if not npcID or not WorldBoss.CATALOG[npcID] then
        return
    end
    Record(partyLens, npcID, mapID, zoneUID, hp, spotter, nil)
end

-- Active sightings, newest first (for the UI), each with its ordinal in OUR frame.
function WorldBoss.Active(partyLens)
    local rt = RT(partyLens)
    local now, out = time(), {}
    for npcID, s in pairs(rt.sightings) do
        if (now - (s.t or 0)) <= WorldBoss.SIGHTING_TTL then
            out[#out + 1] = {
                npcID = npcID, name = s.name, kind = s.kind, mapID = s.mapID,
                zoneUID = s.zoneUID, hp = s.hp, t = s.t, spotter = s.spotter,
                ordinal = Ordinal(partyLens, s.mapID, s.zoneUID),
            }
        else
            rt.sightings[npcID] = nil
        end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

-- Request a hop to the boss's layer (reuses the beacon / requester flow). The boss
-- is usually on a DIFFERENT map than where I'm standing, so pin its exact map +
-- zoneUID (RequestLayerFor) rather than a bare current-map ordinal.
function WorldBoss.HopTo(partyLens, sighting)
    local ln = LN()
    if not ln or not sighting then
        return
    end
    if ln.RequestLayerFor and sighting.mapID and sighting.zoneUID
        and sighting.mapID > 0 and sighting.zoneUID > 0 then
        ln.RequestLayerFor(partyLens, sighting.mapID, sighting.zoneUID)
    elseif ln.RequestLayer then
        local ord = sighting.ordinal or Ordinal(partyLens, sighting.mapID, sighting.zoneUID)
        if ord then
            ln.RequestLayer(partyLens, tostring(ord))
        end
    end
end

-- Public shout (call from a hardware event) — rally the server + brand the addon.
function WorldBoss.AnnouncePublic(partyLens, sighting)
    if not sighting then
        return
    end
    local ord = sighting.ordinal or Ordinal(partyLens, sighting.mapID, sighting.zoneUID)
    local num = GetChannelName and GetChannelName("LookingForGroup")
    if type(num) == "number" and num > 0 then
        Utils.SendChat(L("WB_ANNOUNCE_CHAT", sighting.name, ord or "?"), "CHANNEL", nil, num)
    end
end

_G[ADDON_NAME .. "_WorldBoss"] = WorldBoss
return WorldBoss
