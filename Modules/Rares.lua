local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local LayerNet = _G[ADDON_NAME .. "_LayerNet"]
local Net = _G[ADDON_NAME .. "_Net"]

-- Rare sightings by layer. On Forever every zone runs several copies (layers) and a rare lives in one of them;
-- whoever targets, mouses over or sees the nameplate of a rare, rare elite or world boss tells the zone through
-- the network, and the players there get a discreet prompt to go to that layer (the beacons of LayerNet) or to
-- mark the spot on their map. Prefix "PLRare":
--   PLR1|S|mapID|zoneUID|npcID|x|y|alive|kind|seen|name
-- x, y: the reporter's own position on that map, in thousandths (empty when the game gives none); alive 1|0;
-- kind r (rare), e (rare elite), w (world boss); seen: the reporter's GetServerTime() (every client shares that
-- clock). It goes on GUILD, to the group and to the realm (relayed by LibChehulMesh v8+), at most once per
-- SEND_GAP per rare and layer unless the rare died meanwhile, and only when nobody told it already: a client that
-- sees a rare waits SEND_DELAY (plus up to SEND_JITTER) and stays quiet when the same rare and state arrives from
-- the network meanwhile, or arrived within SEND_GAP. A hundred players at a world boss send a handful of words,
-- not a hundred. Nothing in a message is trusted beyond its shape: a field out of range, a sighting older than
-- FRESH or ahead of the clock, or a sender past its budget is dropped; a relayed sighting is budgeted on the peer
-- that whispered it (its origin is only a claim), and all senders together on GLOBAL_BUDGET. A sighting is data,
-- never a reason to whisper or invite: going there is the player's click.
local Rares = {}

Rares.PREFIX = "PLRare"
Rares.PROTO = "PLR1"
Rares.KINDS = { rare = "r", rareelite = "e", worldboss = "w" }
Rares.FROM_WIRE = { r = "rare", e = "rareelite", w = "worldboss" }
Rares.SEND_GAP = 5 * 60      -- the same rare, layer and state goes out once per this
Rares.FRESH = 15 * 60        -- a sighting older than this is gone (a rare moves on, dies, despawns)
Rares.FUTURE = 120
Rares.NOTIFY_GAP = 10 * 60   -- one prompt per rare and layer per this
Rares.LIST_MAX = 60
Rares.SENDER_BUDGET = 6      -- sightings taken from one sender per minute
Rares.NAME_MAX = 48
Rares.RELAY_SLOTS = 3        -- realm queue keys shared by all sightings (the mesh queue holds 40 for the family)
Rares.SEND_DELAY = 2         -- a sighting of mine waits this long, plus up to SEND_JITTER, for someone else's word
Rares.SEND_JITTER = 13
Rares.GLOBAL_BUDGET = 20     -- sightings taken from everyone together per minute
Rares.PROMPT_GAP = 30        -- one prompt at most per this, whatever the rare

local function RT(partyLens)
    partyLens.rares = partyLens.rares or { list = {}, sent = {}, notified = {}, senders = {}, heard = {},
        pending = {}, all = { window = 0, n = 0 }, lastPrompt = -math.huge }
    return partyLens.rares
end

local function Settings(partyLens)
    return partyLens.db.rares
end

local function Key(mapID, zoneUID, npcID)
    return mapID .. ":" .. zoneUID .. ":" .. npcID
end

local function Whole(text, min, max)
    local n = tonumber(text)
    if n and n == math.floor(n) and n >= min and n <= max then
        return n
    end
end

-- A creature name as it may travel: trimmed, no field separator, no control character, not too long.
local function CleanName(name)
    if Utils.IsSecret(name) or type(name) ~= "string" then
        return nil
    end
    name = Utils.Trim(name)
    if name == "" or #name > Rares.NAME_MAX or name:find("[|%c]") then
        return nil
    end
    return name
end

-- My position on `mapID`, in thousandths; nil when the game gives none (restricted, an instance, a secret).
local function MyPosition(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then
        return nil
    end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or pos == nil or Utils.IsSecret(pos) or type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
        return nil
    end
    local done, x, y = pcall(pos.GetXY, pos)
    if not done or Utils.IsSecret(x, y) or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    if x <= 0 or x > 1 or y <= 0 or y > 1 then
        return nil
    end
    return math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

local function Prune(partyLens)
    local rt, now = RT(partyLens), GetServerTime()
    for key, s in pairs(rt.list) do
        if now - s.seen > Rares.FRESH then
            rt.list[key] = nil
        end
    end
    local wall = time()
    for key, b in pairs(rt.senders) do
        if wall - b.window > 120 then
            rt.senders[key] = nil
        end
    end
    for _, stamps in ipairs({ rt.sent, rt.notified, rt.heard }) do
        for key, v in pairs(stamps) do
            local at = type(v) == "table" and v.at or v
            if wall - at > Rares.FRESH * 2 then
                stamps[key] = nil
            end
        end
    end
end
Rares.Prune = Prune

-- Takes a sighting in. Returns the record and whether it is news (a rare not known on that layer, or one whose
-- state changed). An older word from the network about a known rare changes nothing; what I see myself always
-- replaces it. The list keeps LIST_MAX, the least recently heard going first.
local function Upsert(partyLens, s)
    local rt = RT(partyLens)
    local key = Key(s.mapID, s.zoneUID, s.npcID)
    local old = rt.list[key]
    if old and not s.mine and old.seen > s.seen then
        return old, false
    end
    local news = old == nil or old.alive ~= s.alive
    s.key, s.at = key, time()
    if old and not s.x then
        s.x, s.y = old.x, old.y -- a later word without a position keeps the last one heard
    end
    local moved = old ~= nil and (old.x ~= s.x or old.y ~= s.y)
    rt.list[key] = s
    local count, oldestKey, oldestAt = 0, nil, nil
    for k, r in pairs(rt.list) do
        count = count + 1
        if not oldestAt or r.at < oldestAt then
            oldestKey, oldestAt = k, r.at
        end
    end
    if count > Rares.LIST_MAX and oldestKey then
        rt.list[oldestKey] = nil
    end
    if news or moved then
        partyLens:Fire("RARES_CHANGED")
    end
    return s, news
end

local function RelayKey(key)
    local h = 0
    for i = 1, #key do
        h = (h * 31 + key:byte(i)) % 65521
    end
    return Rares.PREFIX .. ":" .. (h % Rares.RELAY_SLOTS)
end

local function Send(partyLens, s)
    if not Settings(partyLens).share or not Utils.CanSendAddon() then
        return false
    end
    local rt, now = RT(partyLens), time()
    local last = rt.sent[s.key]
    if last and last.alive == s.alive and now - last.at < Rares.SEND_GAP then
        return false
    end
    local payload = table.concat({ Rares.PROTO, "S", s.mapID, s.zoneUID, s.npcID, s.x or "", s.y or "",
        s.alive and 1 or 0, Rares.KINDS[s.kind], s.seen, s.name }, "|")
    if Net.Broadcast(Rares.PREFIX, payload, RelayKey(s.key), true) then
        rt.sent[s.key] = { at = now, alive = s.alive }
        return true
    end
    return false
end

-- What the UI shows of a sighting: its fields plus where it is from where I stand.
function Rares.View(partyLens, s)
    local cur = Layer.Current(partyLens)
    local onMyMap = cur.mapID ~= nil and cur.mapID == s.mapID
    local here = onMyMap and cur.zoneUID == s.zoneUID
    return {
        key = s.key, mapID = s.mapID, zoneUID = s.zoneUID, npcID = s.npcID, name = s.name, kind = s.kind,
        alive = s.alive, x = s.x, y = s.y, seen = s.seen, mine = s.mine == true,
        ago = math.max(0, GetServerTime() - s.seen),
        onMyMap = onMyMap, here = here,
        ordinal = onMyMap and Layer.OrdinalOf(partyLens, s.mapID, s.zoneUID) or nil,
        canGo = onMyMap and not here and cur.zoneUID ~= nil
            and #LayerNet.Beacons(partyLens, s.mapID, s.zoneUID) > 0,
        canMark = s.x ~= nil and C_Map ~= nil and C_Map.SetUserWaypoint ~= nil,
    }
end

-- A prompt for a rare alive in my zone, once per rare and layer per NOTIFY_GAP and one at most per PROMPT_GAP;
-- never one I am looking at.
local function Notify(partyLens, s)
    if not Settings(partyLens).notify or not s.alive or s.mine or Utils.InInstance() then
        return
    end
    if Layer.CurrentMap() ~= s.mapID then
        return
    end
    local rt, now = RT(partyLens), time()
    if now - (rt.notified[s.key] or -math.huge) < Rares.NOTIFY_GAP or now - rt.lastPrompt < Rares.PROMPT_GAP then
        return
    end
    rt.notified[s.key], rt.lastPrompt = now, now
    partyLens:Fire("RARE_SPOTTED", Rares.View(partyLens, s))
end

-- A creature under `unit` (target, mouseover, a nameplate): a rare, rare elite or world boss is a sighting.
function Rares.Observe(partyLens, unit)
    if Utils.InInstance() or Utils.IsSecret(unit) or not UnitExists(unit) then
        return
    end
    local isPlayer, controlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
    if Utils.IsSecret(isPlayer, controlled) or isPlayer or controlled then
        return
    end
    local kind = UnitClassification and UnitClassification(unit)
    if Utils.IsSecret(kind) or not Rares.KINDS[kind] then
        return
    end
    local guid = UnitGUID(unit)
    if Utils.IsSecret(guid) or type(guid) ~= "string" then
        return
    end
    local gkind, _, _, _, zoneUID, npcID = strsplit("-", guid)
    zoneUID, npcID = tonumber(zoneUID), tonumber(npcID)
    if (gkind ~= "Creature" and gkind ~= "Vehicle") or not zoneUID or zoneUID <= 0 or not npcID or npcID <= 0 then
        return
    end
    local mapID = Layer.CurrentMap()
    local name = CleanName((UnitName(unit)))
    local dead = UnitIsDead(unit)
    if not mapID or not name or Utils.IsSecret(dead) then
        return
    end
    local x, y = MyPosition(mapID)
    local alive, rt = dead ~= true, RT(partyLens)
    local key = Key(mapID, zoneUID, npcID)
    local prior = rt.list[key]
    local told = prior ~= nil and not prior.mine and prior.alive == alive
        and GetServerTime() - prior.seen < Rares.SEND_GAP
    Upsert(partyLens, { mapID = mapID, zoneUID = zoneUID, npcID = npcID, name = name, kind = kind,
        alive = alive, x = x, y = y, seen = GetServerTime(), mine = true })
    if told or not Settings(partyLens).share then
        return -- the network has it already
    end
    local p = rt.pending[key]
    if p and p.alive == alive then
        return
    end
    p = { alive = alive, at = time() }
    rt.pending[key] = p
    C_Timer.After(Rares.SEND_DELAY + math.random() * Rares.SEND_JITTER, function()
        if rt.pending[key] ~= p then
            return
        end
        rt.pending[key] = nil
        local h, s = rt.heard[key], rt.list[key]
        if (h and h.alive == alive and h.at >= p.at) or not s or s.alive ~= alive then
            return -- someone told it meanwhile, or it changed again (that change has its own wait)
        end
        Send(partyLens, s)
    end)
end

-- Mesh handler for the prefix: (payload, sender, dist, via). A relayed sighting (dist "RELAY") names its reporter
-- only as a claim; it is budgeted on `via`, the peer that whispered it.
function Rares.OnMessage(partyLens, payload, sender, dist, via)
    if Utils.IsSecret(payload, sender, dist) or type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    if Utils.IsMe(sender) then
        return
    end
    local f = { strsplit("|", payload) }
    if #f ~= 11 or f[1] ~= Rares.PROTO or f[2] ~= "S" then
        return
    end
    local now = GetServerTime()
    local mapID, zoneUID = Whole(f[3], 1, 1e7), Whole(f[4], 1, 1e12)
    local npcID = Whole(f[5], 1, 1e7)
    local x, y = Whole(f[6], 1, 1000), Whole(f[7], 1, 1000)
    local kind, name = Rares.FROM_WIRE[f[9]], CleanName(f[11])
    local seen = Whole(f[10], now - Rares.FRESH, now + Rares.FUTURE)
    seen = seen and math.min(seen, now) -- a clock ahead never outranks a later word
    if not (mapID and zoneUID and npcID and kind and seen and name) or (f[8] ~= "0" and f[8] ~= "1") then
        return
    end
    if (f[6] ~= "" and not x) or (f[7] ~= "" and not y) or ((x == nil) ~= (y == nil)) then
        return
    end
    local rt, wall = RT(partyLens), time()
    local from = dist == "RELAY" and type(via) == "string" and not Utils.IsSecret(via) and via or sender
    local who = Utils.NameKey(from) or from
    local b = rt.senders[who]
    if not b or wall - b.window >= 60 then
        b = { window = wall, n = 0 }
        rt.senders[who] = b
    end
    if wall - rt.all.window >= 60 then
        rt.all.window, rt.all.n = wall, 0
    end
    if b.n >= Rares.SENDER_BUDGET or rt.all.n >= Rares.GLOBAL_BUDGET then
        return
    end
    b.n, rt.all.n = b.n + 1, rt.all.n + 1
    local alive = f[8] == "1"
    rt.heard[Key(mapID, zoneUID, npcID)] = { alive = alive, at = wall }
    local s, news = Upsert(partyLens, { mapID = mapID, zoneUID = zoneUID, npcID = npcID, name = name, kind = kind,
        alive = alive, x = x, y = y, seen = seen })
    if news then
        Notify(partyLens, s)
    end
end

-- The sightings still fresh, alive first then the newest; only `mapID`'s when given.
function Rares.List(partyLens, mapID)
    Prune(partyLens)
    local out = {}
    for _, s in pairs(RT(partyLens).list) do
        if not mapID or s.mapID == mapID then
            out[#out + 1] = Rares.View(partyLens, s)
        end
    end
    table.sort(out, function(a, b)
        if a.alive ~= b.alive then
            return a.alive
        end
        return a.seen > b.seen
    end)
    return out
end

local function Find(partyLens, sighting)
    local key = type(sighting) == "table" and sighting.key
    return key and RT(partyLens).list[key] or nil
end

-- From a click: ask a beacon of the rare's layer to bring me there (LayerNet's own request).
function Rares.GoTo(partyLens, sighting)
    local s = Find(partyLens, sighting)
    if not s then
        return false, "gone"
    end
    return LayerNet.RequestLayer(partyLens, { mapID = s.mapID, zoneUID = s.zoneUID })
end

-- From a click: the game's own map pin at the reporter's position (approximate: where they stood).
function Rares.Mark(partyLens, sighting)
    local s = Find(partyLens, sighting)
    if not s then
        return false, "gone"
    end
    if not s.x or not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false, "no_position"
    end
    local ok, set = pcall(function()
        local point = UiMapPoint.CreateFromCoordinates(s.mapID, s.x / 1000, s.y / 1000)
        local done = C_Map.SetUserWaypoint(point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        return done
    end)
    if not ok or set == false then
        return false, "cannot_mark"
    end
    return true
end

_G[ADDON_NAME .. "_Rares"] = Rares
return Rares
