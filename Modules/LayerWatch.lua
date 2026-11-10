local ADDON_NAME = ...
local Layer = _G[ADDON_NAME .. "_Layer"]
local LayerNet = _G[ADDON_NAME .. "_LayerNet"]

-- The layers this client hears, zone by zone: population (ChehulNet nodes heard there, me included), beacons on
-- duty, groups forming (network listings that carry a layer) and what changed lately. The news come only from what
-- already arrives (presence, HELLO, listings), compared every 30 s by Watch. No names leave this module.
local LayerWatch = {}

LayerWatch.TREND_WINDOW = 10 * 60 -- population is compared with the oldest sample of this window
LayerWatch.TREND_SPAN = 5 * 60    -- ...once the window holds at least this much
LayerWatch.TREND_MIN = 2          -- a smaller change is no news
LayerWatch.TREND_GAP = 10 * 60    -- one population news per layer per this
LayerWatch.NEWS_TTL = 30 * 60
LayerWatch.NEWS_MAX = 4
LayerWatch.WARMUP = 4 * 60        -- after login the picture fills in (HELLOs every 3 min): no news meanwhile
LayerWatch.HOP_STEP_MAX = 3       -- a beacon brings a few people per look at most; a claim of more is not news

local function RT(partyLens)
    partyLens.layerWatch = partyLens.layerWatch or { layers = {} }
    return partyLens.layerWatch
end

-- Counts per layer right now: { [mapID:zoneUID] = { mapID, zoneUID, population, beacons, groups, hops, meBeacon } }.
local function Count(partyLens)
    local cur = Layer.Current(partyLens)
    local by = {}
    local function At(mapID, zoneUID)
        local key = mapID .. ":" .. zoneUID
        local c = by[key]
        if not c then
            c = { mapID = mapID, zoneUID = zoneUID, population = 0, beacons = 0, groups = 0, hops = {} }
            by[key] = c
        end
        return c
    end
    if cur.zoneUID then
        local c = At(cur.mapID, cur.zoneUID)
        c.population = 1
        if LayerNet.Available(partyLens) then
            c.beacons, c.meBeacon = 1, true
        end
    end
    for _, n in ipairs(LayerNet.Nodes(partyLens)) do
        local c = At(n.mapID, n.zoneUID)
        c.population = c.population + 1
        if n.beacon then
            c.beacons = c.beacons + 1
            c.hops[n.key] = n.hops
        end
    end
    for _, e in pairs(partyLens.entries or {}) do
        if e.type == "lfm" and e.mapID and e.zoneUID then
            local c = At(e.mapID, e.zoneUID)
            c.groups = c.groups + 1
        end
    end
    -- A layer of my zone known only by a rare alive on it is still a layer to show (and to go to), when I saw that
    -- layer myself: a sighting alone (anyone can make one up) never adds a layer.
    local Rares = _G[ADDON_NAME .. "_Rares"]
    if Rares and cur.mapID then
        for _, r in ipairs(Rares.List(partyLens, cur.mapID)) do
            if r.alive and Layer.OrdinalOf(partyLens, r.mapID, r.zoneUID) then
                At(r.mapID, r.zoneUID)
            end
        end
    end
    return by
end

-- Compares the counts with the last look and writes the news (kinds: new, beacon_on, beacon_off, hop, group, grow,
-- shrink; n = how many). For the first minutes after login it only takes the picture.
function LayerWatch.Watch(partyLens)
    local rt, now = RT(partyLens), time()
    rt.startedAt = rt.startedAt or now
    local warm = now - rt.startedAt >= LayerWatch.WARMUP
    local added = false
    local function Add(w, kind, n)
        if not warm then
            return
        end
        table.insert(w.news, 1, { t = now, kind = kind, n = n })
        while #w.news > LayerWatch.NEWS_MAX do
            table.remove(w.news)
        end
        added = true
    end
    local by = Count(partyLens)
    for key, c in pairs(by) do
        local w = rt.layers[key]
        if not w then
            w = { hist = {}, news = {}, beacons = 0, groups = 0, hops = {} }
            rt.layers[key] = w
            Add(w, "new")
        else
            if w.beacons == 0 and c.beacons > 0 then
                Add(w, "beacon_on", c.beacons)
            elseif w.beacons > 0 and c.beacons == 0 then
                Add(w, "beacon_off")
            end
            local hopped = 0
            for nodeKey, hops in pairs(c.hops) do
                local was = w.hops[nodeKey]
                if was and hops > was then
                    hopped = hopped + math.min(hops - was, LayerWatch.HOP_STEP_MAX)
                end
            end
            if hopped > 0 then
                Add(w, "hop", hopped)
            end
            if c.groups > w.groups then
                Add(w, "group", c.groups - w.groups)
            end
            local base = w.hist[1]
            if base and now - base.t >= LayerWatch.TREND_SPAN and now - (w.trendAt or 0) >= LayerWatch.TREND_GAP then
                local delta = c.population - base.pop
                if math.abs(delta) >= LayerWatch.TREND_MIN then
                    Add(w, delta > 0 and "grow" or "shrink", math.abs(delta))
                    w.trendAt = now
                end
            end
        end
        w.beacons, w.groups, w.hops, w.seen = c.beacons, c.groups, c.hops, now
        if not warm then
            w.hist = {} -- the trend starts from the filled-in picture, not from the first half-heard one
        end
        w.hist[#w.hist + 1] = { t = now, pop = c.population }
        while w.hist[1] and now - w.hist[1].t > LayerWatch.TREND_WINDOW do
            table.remove(w.hist, 1)
        end
    end
    for key, w in pairs(rt.layers) do
        for i = #w.news, 1, -1 do
            if now - w.news[i].t > LayerWatch.NEWS_TTL then
                table.remove(w.news, i)
            end
        end
        if not by[key] and now - (w.seen or 0) > LayerWatch.NEWS_TTL then
            rt.layers[key] = nil
        end
    end
    if added then
        partyLens:Fire("LAYER_NODES_CHANGED")
    end
end

-- One row per layer heard: my zone first, then the busiest zones; inside a zone by layer. My map is numbered from
-- what I saw myself (nil for a layer only the network reports); other maps by their order among the layers heard.
function LayerWatch.Layers(partyLens)
    local cur, rt = Layer.Current(partyLens), RT(partyLens)
    local zones, order = {}, {}
    -- the rares alive per layer, from one list (the layer page's news)
    local Rares, rares = _G[ADDON_NAME .. "_Rares"], {} -- loads after this file
    for _, r in ipairs(Rares and Rares.List(partyLens) or {}) do
        if r.alive then
            local k = r.mapID .. ":" .. r.zoneUID
            rares[k] = rares[k] or {}
            table.insert(rares[k], r)
        end
    end
    for key, c in pairs(Count(partyLens)) do
        local z = zones[c.mapID]
        if not z then
            z = { mine = c.mapID == cur.mapID, population = 0, layers = {} }
            zones[c.mapID] = z
            order[#order + 1] = c.mapID
        end
        local w = rt.layers[key]
        c.hops = nil
        c.mine = z.mine and c.zoneUID == cur.zoneUID
        c.news = w and w.news or {}
        c.rares = rares[key] or {}
        z.population = z.population + c.population
        z.layers[#z.layers + 1] = c
    end
    table.sort(order, function(a, b)
        local x, y = zones[a], zones[b]
        if x.mine ~= y.mine then
            return x.mine
        end
        if x.population ~= y.population then
            return x.population > y.population
        end
        return a < b
    end)
    local out = {}
    for _, mapID in ipairs(order) do
        local z = zones[mapID]
        table.sort(z.layers, function(a, b) return a.zoneUID < b.zoneUID end)
        for i, c in ipairs(z.layers) do
            c.sameMap = z.mine
            c.zonePopulation = z.population
            if z.mine then
                c.ordinal = Layer.OrdinalOf(partyLens, mapID, c.zoneUID)
            else
                c.ordinal = i
            end
            c.canRequest = z.mine and not c.mine and c.beacons > 0
            out[#out + 1] = c
        end
    end
    return out
end

_G[ADDON_NAME .. "_LayerWatch"] = LayerWatch
return LayerWatch
