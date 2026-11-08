local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Net = _G[ADDON_NAME .. "_Net"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- Layer swap through beacons. Who is on which layer comes from PartyLens presence and from every ChehulNet HELLO
-- (any Chehul addon reports mapID:zoneUID). A beacon is a PartyLens player on duty: beacon setting on (the default),
-- open world, out of combat, not away, alone or only with the people it brought. The player picks a layer; the
-- addon whispers the request to that layer's best beacon, and on a "no" or 40 s of silence to the next one. The
-- beacon's player invites with a click (the game requires one). In the beacon's group, the game moves the requester
-- to the beacon's copy of the zone when they click its switch prompt, or by itself after about five minutes; the
-- requester's client then says "arrived" and the hop counts. Layers are per zone on Forever: each zone runs its own
-- copies, as many as its population needs (measured 2026-11-08: Thunder Bluff one copy for ten random players, The
-- Barrens eight copies for eight guildmates at the same time), so a beacon only helps inside its own zone.
-- Prefix "PLLnet":
--   PLL2|S|mapID|zoneUID|beacon|hops          presence (GUILD + group + directory), on a change and every 60 s;
--                                             beacon = 1 while on duty, hops = people it brought over
--   PLL2|R|mapID|myZoneUID|targetZoneUID      a request, whispered to the chosen beacon
--   PLL2|A|mapID|zoneUID                      "invite on its way", whispered back by the beacon that clicked
--   PLL2|N|mapID|zoneUID                      "not now", whispered back by a beacon that cannot take it
--   PLL2|T|mapID|zoneUID                      "arrived", whispered by the requester once its layer is the beacon's
-- No invite, whisper or uninvite ever leaves from a timer or an event. Layers are numbered only from what this
-- client saw itself (Layer.Observe): a presence names a node's layer, it never adds one to my numbering.
local LayerNet = {}

LayerNet.PREFIX = "PLLnet"
LayerNet.PROTO = "PLL2"
LayerNet.PRESENCE_INTERVAL = 60
LayerNet.PRESENCE_GAP = 10 -- a reading that flips between two zoneUIDs must not flood GUILD
LayerNet.NODE_TTL = 10 * 60
LayerNet.BEACON_FRESH = 150      -- a beacon flag older than this (presence every 60 s) is not counted on
LayerNet.ASK_TTL = 40            -- a beacon that neither invites nor says no within this: the next one is asked
LayerNet.REQUEST_TTL = 120       -- an invite on its way that I never join is over after this
LayerNet.INBOUND_TTL = 90        -- an open request nobody answered goes after this
LayerNet.INVITE_TTL = 150        -- an invite not taken within this is over (declined or timed out in the game)
LayerNet.DECLINE_HOLD = 10 * 60  -- a declined requester is not heard again for this long
LayerNet.REQUEST_COOLDOWN = 30   -- one request (or one "no") per sender per this; a repeat is never a new toast
LayerNet.INBOUND_MAX = 10        -- when full, the oldest request not yet in my group makes room
LayerNet.HOPS_MAX = 99999
LayerNet.SILENT_HOLD = 30 * 60   -- a beacon that let an ask run out is asked last for this long
-- Ranks by hops served. The names live in the UI; the core only knows the thresholds.
LayerNet.RANKS = { 0, 3, 10, 25, 60, 150 }

local function RT(partyLens)
    partyLens.layerNet = partyLens.layerNet or { nodes = {}, inbound = {}, said = {}, silent = {} }
    return partyLens.layerNet
end

local function Changed(partyLens)
    partyLens:Fire("LAYER_REQUESTS_CHANGED")
end

local function Pending(my)
    return my ~= nil and (my.state == "sent" or my.state == "accepted")
end

local function BeaconDB(partyLens)
    return partyLens.db.beacon
end

local function Integer(text, max)
    local n = tonumber(text)
    if n and n >= 0 and n == math.floor(n) and n <= (max or math.huge) then
        return n
    end
end

local function Positive(text)
    local n = Integer(text)
    if n and n > 0 then
        return n
    end
end

-- ---------------------------------------------------------------------------
-- Beacon: on duty or not, and the hops it served
-- ---------------------------------------------------------------------------
-- Joined my group (served) or already on my layer (arrived): my hoppers.
local function IsHopper(r)
    return r.state == "served" or r.state == "arrived"
end

-- A "no" to a request, at most once per sender per cooldown.
local function SayNo(partyLens, key, name, mapID)
    local rt, now = RT(partyLens), time()
    if (rt.said[key] or 0) + LayerNet.REQUEST_COOLDOWN > now then
        return
    end
    rt.said[key] = now
    local cur = Layer.Current(partyLens)
    Net.Whisper(LayerNet.PREFIX, table.concat({ LayerNet.PROTO, "N", mapID, cur.zoneUID or 0 }, "|"), name)
end

-- On duty, as the presence advertises it: false and why otherwise. Combat is not in it (a fight that comes and
-- goes every few seconds must not flood the network); CanTake adds it.
function LayerNet.Available(partyLens)
    if not BeaconDB(partyLens).on then
        return false, "off"
    end
    if Utils.InInstance() then
        return false, "instance"
    end
    if not Layer.Current(partyLens).zoneUID then
        return false, "no_layer"
    end
    local afk = UnitIsAFK("player")
    if Utils.IsSecret(afk) or afk then
        return false, "afk"
    end
    if IsInGroup() then
        if not Roster.CanInvite() then
            return false, "grouped"
        end
        if Roster.IsFull() then
            return false, "group_full"
        end
        -- Never someone else's group: only the people I brought over may be in it. A group unit can carry the
        -- first name alone, so the match is SameName's, as the roster's.
        local hoppers = {}
        for _, r in pairs(RT(partyLens).inbound) do
            if IsHopper(r) then
                hoppers[#hoppers + 1] = r.name
            end
        end
        for _, m in ipairs(Roster.Members()) do
            if not m.isPlayer then
                local mine = false
                for _, name in ipairs(hoppers) do
                    mine = mine or Utils.SameName(m.name, name)
                end
                if not mine then
                    return false, "grouped"
                end
            end
        end
    end
    return true
end

-- On duty and free to take a request this moment (not in combat).
function LayerNet.CanTake(partyLens)
    local available, why = LayerNet.Available(partyLens)
    if not available then
        return false, why
    end
    local combat = UnitAffectingCombat("player")
    if Utils.IsSecret(combat) or combat then
        return false, "combat"
    end
    return true
end

function LayerNet.Rank(hops)
    local rank = 1
    for i, at in ipairs(LayerNet.RANKS) do
        if (hops or 0) >= at then
            rank = i
        end
    end
    return rank
end

function LayerNet.BeaconStatus(partyLens)
    local b = BeaconDB(partyLens)
    local available, why = LayerNet.CanTake(partyLens)
    local rank = LayerNet.Rank(b.hops)
    local today = (b.day == date("%Y-%m-%d")) and b.today or 0
    return { on = b.on == true, available = available, why = why, hops = b.hops, today = today, rank = rank,
        rankAt = LayerNet.RANKS[rank], nextAt = LayerNet.RANKS[rank + 1], queue = LayerNet.OpenCount(partyLens) }
end

-- Re-reads duty after anything that can change it. The network hears a change of duty; the UI hears that and
-- combat. Requests still open when I can no longer take them get a no now, so the askers move on.
function LayerNet.CheckDuty(partyLens)
    local rt = RT(partyLens)
    local available = LayerNet.Available(partyLens) == true
    local canTake, why = LayerNet.CanTake(partyLens)
    if not canTake then
        local dropped = false
        for key, r in pairs(rt.inbound) do
            if r.state == "open" then
                rt.inbound[key] = nil
                SayNo(partyLens, key, r.name, r.mapID)
                dropped = true
            end
        end
        if dropped then
            Changed(partyLens)
        end
    end
    if rt.onDuty ~= available then
        rt.onDuty = available
        LayerNet.SendPresence(partyLens)
    end
    local state = canTake and "take" or why
    if rt.dutyState ~= state then
        rt.dutyState = state
        partyLens:Fire("BEACON_CHANGED", LayerNet.BeaconStatus(partyLens))
    end
end

function LayerNet.SetBeacon(partyLens, on)
    BeaconDB(partyLens).on = on == true
    partyLens:Fire("BEACON_CHANGED", LayerNet.BeaconStatus(partyLens))
    LayerNet.CheckDuty(partyLens)
end

-- One hop per person per day: two friends trading invites do not climb the ranks.
local function CountHop(partyLens, req)
    local b, day = BeaconDB(partyLens), date("%Y-%m-%d")
    if b.day ~= day then
        b.day, b.today, b.todayKeys = day, 0, {}
    end
    if b.todayKeys[req.key] then
        return
    end
    b.todayKeys[req.key] = true
    local before = LayerNet.Rank(b.hops)
    b.hops = math.min(LayerNet.HOPS_MAX, b.hops + 1)
    b.today = b.today + 1
    local status = LayerNet.BeaconStatus(partyLens)
    status.rankUp = status.rank > before
    status.name = req.name
    partyLens:Fire("BEACON_SERVED", status)
end

-- ---------------------------------------------------------------------------
-- Presence
-- ---------------------------------------------------------------------------
function LayerNet.SendPresence(partyLens)
    local rt = RT(partyLens)
    local wait = (rt.presenceAt or -LayerNet.PRESENCE_GAP) + LayerNet.PRESENCE_GAP - GetTime()
    if wait > 0 then
        if not rt.presencePending then
            rt.presencePending = true
            C_Timer.After(wait, function()
                rt.presencePending = false
                LayerNet.SendPresence(partyLens)
            end)
        end
        return false
    end
    local cur = Layer.Current(partyLens)
    if not cur.zoneUID then
        return false
    end
    local onDuty = LayerNet.Available(partyLens) == true
    rt.onDuty = onDuty
    local payload = table.concat({ LayerNet.PROTO, "S", cur.mapID, cur.zoneUID, onDuty and 1 or 0,
        BeaconDB(partyLens).hops }, "|")
    if Net.Broadcast(LayerNet.PREFIX, payload, LayerNet.PREFIX .. ":S") then
        rt.presenceAt = GetTime()
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

local function OnRequest(partyLens, name, key, mapID, fromZone, target)
    local rt = RT(partyLens)
    local now, old = time(), rt.inbound[key]
    if old then
        -- Declined, invited or served stay so; an open one asked again only stays open longer.
        if old.state == "open" and now - old.t >= LayerNet.REQUEST_COOLDOWN then
            old.t = now
        elseif old.state == "declined" then
            SayNo(partyLens, key, name, mapID)
        end
        return
    end
    local cur = Layer.Current(partyLens)
    if cur.mapID ~= mapID or not cur.zoneUID or (target and target ~= cur.zoneUID)
        or LayerNet.CanTake(partyLens) ~= true or not LayerNet.MakeRoom(rt) then
        SayNo(partyLens, key, name, mapID)
        return
    end
    rt.seq = (rt.seq or 0) + 1
    local req = { name = name, key = key, mapID = mapID, fromZone = fromZone, targetZone = cur.zoneUID,
        t = now, seq = rt.seq, state = "open" }
    rt.inbound[key] = req
    partyLens:Fire("LAYER_REQUEST_RECEIVED", req) -- the UI's prompt shows it; no notice on top
    Changed(partyLens)
end

function LayerNet.OnMessage(partyLens, payload, sender, dist)
    if Utils.IsSecret(payload, sender, dist) or type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    local proto, kind, a, b, c, d = strsplit("|", payload)
    local name = Utils.FullName(sender)
    if proto ~= LayerNet.PROTO or not name or Utils.IsMe(name) then
        return
    end
    local key = Utils.NameKey(name)
    local rt = RT(partyLens)
    local mapID, zoneUID = Positive(a), Positive(b)
    if kind == "S" and mapID and zoneUID then
        rt.nodes[key] = { name = name, mapID = mapID, zoneUID = zoneUID, t = time(), beacon = c == "1",
            hops = Integer(d, LayerNet.HOPS_MAX) or 0 }
        partyLens:Fire("LAYER_NODES_CHANGED")
    elseif kind == "R" and dist == "WHISPER" and mapID then
        OnRequest(partyLens, name, key, mapID, zoneUID, Positive(c))
    elseif kind == "A" and dist == "WHISPER" then
        -- Any beacon I asked may click late, after the next one was asked: its invite is as good.
        local my = rt.my
        if my and my.state == "sent" and my.tried[key] then
            my.name, my.key = my.tried[key], key
            my.state, my.stateAt = "accepted", time()
            partyLens:Notice(L("NOTICE_LAYER_ACCEPTED"))
            Changed(partyLens)
        end
    elseif kind == "N" and dist == "WHISPER" then
        local my = rt.my
        if my and my.state == "sent" and Utils.SameName(my.name, name) then
            LayerNet.AskNext(partyLens)
        end
    elseif kind == "T" and dist == "WHISPER" then
        -- Only someone I invited, in my group, arriving on the layer I served: that is a hop.
        local r = rt.inbound[key]
        if r and r.state == "served" and mapID == r.mapID and zoneUID == r.targetZone then
            r.state, r.stateAt = "arrived", time()
            CountHop(partyLens, r)
            Changed(partyLens)
        end
    end
end

-- Room for one more inbound request: the oldest one not in my group goes. False when every slot is a hopper.
function LayerNet.MakeRoom(rt)
    local count, oldestKey, oldestAt = 0, nil, nil
    for key, r in pairs(rt.inbound) do
        count = count + 1
        if not IsHopper(r) and (not oldestAt or r.t < oldestAt) then
            oldestKey, oldestAt = key, r.t
        end
    end
    if count < LayerNet.INBOUND_MAX then
        return true
    end
    if oldestKey then
        rt.inbound[oldestKey] = nil
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Nodes
-- ---------------------------------------------------------------------------
-- Every node I know of, from PartyLens presence and from ChehulNet's HELLO.
function LayerNet.Nodes(partyLens)
    local rt, now = RT(partyLens), time()
    local byKey = {}
    local CN = _G.ChehulNet
    for name, p in pairs((CN and CN.peers) or {}) do
        local key = Utils.NameKey(name)
        if key and (p.mapID or 0) > 0 and (p.zoneUID or 0) > 0 and now - (p.ts or 0) <= LayerNet.NODE_TTL
            and not Utils.IsMe(name) then
            byKey[key] = { name = name, key = key, mapID = p.mapID, zoneUID = p.zoneUID, t = p.ts or now,
                pl = (p.addons and p.addons.pl) == true, source = "cn" }
        end
    end
    for key, n in pairs(rt.nodes) do
        if now - n.t <= LayerNet.NODE_TTL then
            local have = byKey[key]
            local beacon = n.beacon and now - n.t <= LayerNet.BEACON_FRESH
            if not have or n.t >= have.t then
                byKey[key] = { name = n.name, key = key, mapID = n.mapID, zoneUID = n.zoneUID, t = n.t, pl = true,
                    source = "pl", beacon = beacon, hops = n.hops }
            else
                have.pl, have.hops = true, n.hops
                have.beacon = beacon and have.mapID == n.mapID and have.zoneUID == n.zoneUID
            end
        end
    end
    local cur = Layer.Current(partyLens)
    local list = {}
    for _, n in pairs(byKey) do
        local sameMap = cur.mapID ~= nil and n.mapID == cur.mapID
        list[#list + 1] = {
            name = n.name, key = n.key, mapID = n.mapID, zoneUID = n.zoneUID, source = n.source, pl = n.pl,
            beacon = n.beacon == true, hops = n.hops or 0,
            sameMap = sameMap, sameLayer = sameMap and cur.zoneUID == n.zoneUID, ago = now - n.t,
        }
    end
    table.sort(list, function(x, y) return x.name < y.name end)
    return list
end

function LayerNet.NodeCount(partyLens)
    return #LayerNet.Nodes(partyLens)
end

-- The beacons on duty on one layer, the one with the most hops first (then the freshest). One that let an ask
-- run out lately goes last, whatever hops it claims: a presence can claim any number.
function LayerNet.Beacons(partyLens, mapID, zoneUID)
    local out, silent, now = {}, RT(partyLens).silent, time()
    for _, n in ipairs(LayerNet.Nodes(partyLens)) do
        if n.beacon and n.mapID == mapID and n.zoneUID == zoneUID then
            n.silent = silent[n.key] ~= nil and now - silent[n.key] < LayerNet.SILENT_HOLD
            out[#out + 1] = n
        end
    end
    table.sort(out, function(x, y)
        if x.silent ~= y.silent then
            return y.silent
        end
        if x.hops ~= y.hops then
            return x.hops > y.hops
        end
        return x.ago < y.ago
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Asking for a layer (an addon whisper: no hardware event needed, but only ever a player's choice)
-- ---------------------------------------------------------------------------
-- Whispers the next beacon on the requested layer not asked yet; with none left the request is over.
function LayerNet.AskNext(partyLens)
    local rt = RT(partyLens)
    local my = rt.my
    if not my or my.state ~= "sent" then
        return false
    end
    local cur = Layer.Current(partyLens)
    for _, beacon in ipairs(LayerNet.Beacons(partyLens, my.mapID, my.targetZone)) do
        if not my.tried[beacon.key] then
            my.tried[beacon.key] = beacon.name
            local payload = table.concat({ LayerNet.PROTO, "R", my.mapID, cur.zoneUID or 0, my.targetZone }, "|")
            if Net.Whisper(LayerNet.PREFIX, payload, beacon.name) then
                my.name, my.key, my.askedAt = beacon.name, beacon.key, time()
                my.asked = my.asked + 1
                local attempt = my.asked
                C_Timer.After(LayerNet.ASK_TTL, function()
                    if rt.my == my and my.state == "sent" and my.asked == attempt then
                        rt.silent[beacon.key] = time() -- it let the ask run out: asked last for a while
                        LayerNet.AskNext(partyLens)
                    end
                end)
                Changed(partyLens)
                return true
            end
        end
    end
    my.state, my.stateAt = "expired", time()
    if my.asked > 0 then
        partyLens:Notice(L("NOTICE_LAYER_NOBODY"))
    end
    Changed(partyLens)
    return false
end

-- layer = { mapID, zoneUID }: a layer of the map I am on.
function LayerNet.RequestLayer(partyLens, layer)
    local rt = RT(partyLens)
    if Pending(rt.my) then
        return false, "pending"
    end
    local cur = Layer.Current(partyLens)
    if type(layer) ~= "table" or not layer.mapID or layer.mapID ~= cur.mapID then
        return false, "other_map"
    end
    if layer.zoneUID == cur.zoneUID then
        return false, "same_layer"
    end
    if #LayerNet.Beacons(partyLens, layer.mapID, layer.zoneUID) == 0 then
        return false, "no_beacon"
    end
    local now = time()
    local my = { mapID = layer.mapID, targetZone = layer.zoneUID, state = "sent", t = now, stateAt = now,
        tried = {}, asked = 0 }
    rt.my = my
    if not LayerNet.AskNext(partyLens) then
        rt.my = nil
        Changed(partyLens)
        return false, "cannot_send"
    end
    partyLens:Notice(L("NOTICE_LAYER_REQUESTED"))
    return true
end

function LayerNet.MyRequest(partyLens)
    return RT(partyLens).my
end

function LayerNet.Cancel(partyLens)
    local my = RT(partyLens).my
    if Pending(my) then
        my.state, my.stateAt = "cancelled", time()
        Changed(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Serving (the beacon's side)
-- ---------------------------------------------------------------------------
function LayerNet.Inbound(partyLens)
    local list = {}
    for _, r in pairs(RT(partyLens).inbound) do
        list[#list + 1] = r
    end
    table.sort(list, function(x, y) return x.seq > y.seq end)
    return list
end

function LayerNet.OpenCount(partyLens)
    local n = 0
    for _, r in pairs(RT(partyLens).inbound) do
        if r.state == "open" then
            n = n + 1
        end
    end
    return n
end

-- Click only: the invite needs a hardware event.
function LayerNet.Serve(partyLens, req)
    local r = req and RT(partyLens).inbound[req.key]
    if not r or r.state == "declined" then
        return false, "gone"
    end
    local cur = Layer.Current(partyLens)
    if cur.mapID ~= r.mapID or cur.zoneUID ~= r.targetZone then
        return false, "not_on_layer"
    end
    local canTake, why = LayerNet.CanTake(partyLens)
    if not canTake then
        return false, why == "group_full" and "group_full" or "off_duty"
    end
    if not Roster.CanInvite() then
        return false, "cannot_invite"
    end
    if Roster.IsFull() then
        return false, "group_full"
    end
    C_PartyInfo.InviteUnit(r.name)
    Net.Whisper(LayerNet.PREFIX, table.concat({ LayerNet.PROTO, "A", cur.mapID, cur.zoneUID }, "|"), r.name)
    r.state, r.stateAt = "invited", time()
    Changed(partyLens)
    return true
end

-- Click only (a key binding counts): the open request that arrived first.
function LayerNet.ServeNext(partyLens)
    local oldest
    for _, r in pairs(RT(partyLens).inbound) do
        if r.state == "open" and (not oldest or r.seq < oldest.seq) then
            oldest = r
        end
    end
    if not oldest then
        return false, "gone"
    end
    return LayerNet.Serve(partyLens, oldest)
end

function LayerNet.Decline(partyLens, req)
    local r = req and RT(partyLens).inbound[req.key]
    if r then
        r.state, r.stateAt = "declined", time()
        SayNo(partyLens, r.key, r.name, r.mapID)
        Changed(partyLens)
    end
end

function LayerNet.OnRoster(partyLens)
    local rt, changed = RT(partyLens), false
    local members = Roster.Members()
    local my = rt.my
    if Pending(my) then
        for key, name in pairs(my.tried) do
            if Roster.Contains(members, name) then
                my.name, my.key = name, key
                my.state, my.stateAt = "served", time()
                changed = true
            end
        end
    elseif my and (my.state == "served" or my.state == "hopped") and not Roster.Contains(members, my.name) then
        -- Out of the beacon's group: the hop is over (or never happened); the card stops offering to leave.
        my.state, my.stateAt = my.state == "hopped" and "done" or "cancelled", time()
        changed = true
    end
    for key, r in pairs(rt.inbound) do
        local grouped = Roster.Contains(members, r.name)
        if r.state == "invited" and grouped then
            r.state, r.stateAt = "served", time()
            changed = true
        elseif IsHopper(r) and not grouped then
            rt.inbound[key] = nil -- uninvited, or gone on their own: the hop is over
            changed = true
        end
    end
    if changed then
        Changed(partyLens)
    end
    LayerNet.CheckDuty(partyLens)
end

function LayerNet.OnLayerChanged(partyLens, cur)
    local my = RT(partyLens).my
    if my and my.state == "served" and cur.mapID == my.mapID and cur.zoneUID == my.targetZone then
        my.state, my.stateAt = "hopped", time()
        Net.Whisper(LayerNet.PREFIX, table.concat({ LayerNet.PROTO, "T", cur.mapID, cur.zoneUID }, "|"), my.name)
        partyLens:Notice(L("NOTICE_LAYER_HOPPED"))
        Changed(partyLens)
    end
    LayerNet.SendPresence(partyLens)
    LayerNet.CheckDuty(partyLens)
end

local function ServedHoppers(partyLens)
    local out, members = {}, Roster.Members()
    for key, r in pairs(RT(partyLens).inbound) do
        if IsHopper(r) and Roster.Contains(members, r.name) then
            out[#out + 1] = key
        end
    end
    return out
end

function LayerNet.CanUndo(partyLens)
    local my = RT(partyLens).my
    if my and (my.state == "served" or my.state == "hopped") and IsInGroup() then
        return true
    end
    return #ServedHoppers(partyLens) > 0
end

-- Click only: uninviting needs a hardware event, and leaving is the player's call. The state follows the roster
-- (OnRoster), not this call: a blocked call changes nothing.
function LayerNet.Undo(partyLens)
    local rt = RT(partyLens)
    local hoppers = ServedHoppers(partyLens)
    if #hoppers > 0 then
        for _, key in ipairs(hoppers) do
            if Roster.CanInvite() then
                C_PartyInfo.UninviteUnit(rt.inbound[key].name)
            else
                C_PartyInfo.LeaveParty()
            end
        end
        return true
    end
    local my = rt.my
    if my and (my.state == "served" or my.state == "hopped") and IsInGroup() then
        C_PartyInfo.LeaveParty()
        return true
    end
    return false
end

function LayerNet.Prune(partyLens)
    local rt, now = RT(partyLens), time()
    local changed, nodesChanged = false, false
    local members = Roster.Members()
    for key, n in pairs(rt.nodes) do
        if now - n.t > LayerNet.NODE_TTL then
            rt.nodes[key] = nil
            nodesChanged = true
        end
    end
    for key, at in pairs(rt.said) do
        if now - at > LayerNet.REQUEST_COOLDOWN then
            rt.said[key] = nil
        end
    end
    for key, at in pairs(rt.silent) do
        if now - at > LayerNet.SILENT_HOLD then
            rt.silent[key] = nil
        end
    end
    for key, r in pairs(rt.inbound) do
        local since = now - (r.stateAt or r.t)
        if (r.state == "open" and now - r.t > LayerNet.INBOUND_TTL)
            or (r.state == "invited" and since > LayerNet.INVITE_TTL and not Roster.Contains(members, r.name))
            or (r.state == "declined" and since > LayerNet.DECLINE_HOLD) then
            rt.inbound[key] = nil
            changed = true
        end
    end
    local my = rt.my
    if my and my.state == "accepted" and now - my.stateAt > LayerNet.REQUEST_TTL then
        my.state, my.stateAt = "expired", now
        changed = true
    elseif my and my.state == "sent" and now - (my.askedAt or my.t) > LayerNet.ASK_TTL * 2 then
        LayerNet.AskNext(partyLens) -- a lost timer must not leave the request waiting forever
    end
    if changed then
        Changed(partyLens)
    end
    if nodesChanged then
        partyLens:Fire("LAYER_NODES_CHANGED")
    end
end

_G[ADDON_NAME .. "_LayerNet"] = LayerNet
return LayerNet
