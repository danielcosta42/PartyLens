local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Net = _G[ADDON_NAME .. "_Net"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- Layer swap as a tool the player drives. Who is on which layer comes from PartyLens presence and from every
-- ChehulNet HELLO (any Chehul addon reports mapID:zoneUID). The player picks a PartyLens node on another layer
-- of the same map and asks it by whisper; that player sees the request and invites by click; joining their
-- group moves the requester to their layer. Prefix "PLLnet":
--   PLL2|S|mapID|zoneUID                      presence (GUILD + group + directory), on a change and every 60 s
--   PLL2|R|mapID|myZoneUID|targetZoneUID      a request, whispered to the chosen node
--   PLL2|A|mapID|zoneUID                      "invite on its way", whispered back by the node that clicked
-- No invite, whisper or uninvite ever leaves from a timer or an event. Layers are numbered only from what this
-- client saw itself (Layer.Observe): a presence names a node's layer, it never adds one to my numbering.
local LayerNet = {}

LayerNet.PREFIX = "PLLnet"
LayerNet.PROTO = "PLL2"
LayerNet.PRESENCE_INTERVAL = 60
LayerNet.PRESENCE_GAP = 10 -- a reading that flips between two zoneUIDs must not flood GUILD
LayerNet.NODE_TTL = 10 * 60
LayerNet.REQUEST_TTL = 120
LayerNet.INBOUND_TTL = 90        -- an open request nobody answered goes after this
LayerNet.INVITE_TTL = 150        -- an invite not taken within this is over (declined or timed out in the game)
LayerNet.DECLINE_HOLD = 10 * 60  -- a declined requester is not heard again for this long
LayerNet.REQUEST_COOLDOWN = 30   -- one request per sender per this; a repeat is never a new toast
LayerNet.INBOUND_MAX = 10        -- when full, the oldest request not yet in my group makes room

local function RT(partyLens)
    partyLens.layerNet = partyLens.layerNet or { nodes = {}, inbound = {} }
    return partyLens.layerNet
end

local function Changed(partyLens)
    partyLens:Fire("LAYER_REQUESTS_CHANGED")
end

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
    local payload = table.concat({ LayerNet.PROTO, "S", cur.mapID, cur.zoneUID }, "|")
    if Net.Broadcast(LayerNet.PREFIX, payload, LayerNet.PREFIX .. ":S") then
        rt.presenceAt = GetTime()
        return true
    end
    return false
end

local function Positive(text)
    local n = tonumber(text)
    if n and n > 0 and n == math.floor(n) then
        return n
    end
end

function LayerNet.OnMessage(partyLens, payload, sender, dist)
    if Utils.IsSecret(payload, sender, dist) or type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    local proto, kind, a, b, c = strsplit("|", payload)
    local name = Utils.FullName(sender)
    if proto ~= LayerNet.PROTO or not name or Utils.IsMe(name) then
        return
    end
    local key = Utils.NameKey(name)
    local rt = RT(partyLens)
    local mapID, zoneUID = Positive(a), Positive(b)
    if kind == "S" and mapID and zoneUID then
        rt.nodes[key] = { name = name, mapID = mapID, zoneUID = zoneUID, t = time() }
        partyLens:Fire("LAYER_NODES_CHANGED")
    elseif kind == "R" and dist == "WHISPER" and mapID then
        local target = Positive(c)
        local cur = Layer.Current(partyLens)
        if cur.mapID ~= mapID or not cur.zoneUID or (target and target ~= cur.zoneUID) then
            return
        end
        local now, old = time(), rt.inbound[key]
        if old then
            -- Declined, invited or served stay so; an open one asked again only stays open longer.
            if old.state == "open" and now - old.t >= LayerNet.REQUEST_COOLDOWN then
                old.t = now
            end
            return
        end
        if not LayerNet.MakeRoom(rt) then
            return
        end
        local req = { name = name, key = key, mapID = mapID, fromZone = zoneUID, targetZone = cur.zoneUID,
            t = now, state = "open" }
        rt.inbound[key] = req
        if zoneUID then
            rt.nodes[key] = { name = name, mapID = mapID, zoneUID = zoneUID, t = now }
        end
        partyLens:Notice(L("NOTICE_LAYER_INCOMING", name))
        partyLens:Fire("LAYER_REQUEST_RECEIVED", req)
        Changed(partyLens)
    elseif kind == "A" and dist == "WHISPER" then
        local my = rt.my
        if my and my.state == "sent" and Utils.SameName(my.name, name) then
            my.state, my.stateAt = "accepted", time()
            partyLens:Notice(L("NOTICE_LAYER_ACCEPTED", name))
            Changed(partyLens)
        end
    end
end

-- Room for one more inbound request: the oldest one not in my group goes. False when every slot is a hopper.
function LayerNet.MakeRoom(rt)
    local count, oldestKey, oldestAt = 0, nil, nil
    for key, r in pairs(rt.inbound) do
        count = count + 1
        if r.state ~= "served" and (not oldestAt or r.t < oldestAt) then
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
            if not have or n.t >= have.t then
                byKey[key] = { name = n.name, key = key, mapID = n.mapID, zoneUID = n.zoneUID, t = n.t, pl = true,
                    source = "pl" }
            else
                have.pl = true
            end
        end
    end
    local cur = Layer.Current(partyLens)
    local list = {}
    for _, n in pairs(byKey) do
        local sameMap = cur.mapID ~= nil and n.mapID == cur.mapID
        local sameLayer = sameMap and cur.zoneUID == n.zoneUID
        list[#list + 1] = {
            name = n.name, key = n.key, mapID = n.mapID, zoneUID = n.zoneUID, source = n.source,
            sameMap = sameMap, sameLayer = sameLayer, canRequest = n.pl and sameMap and not sameLayer,
            ago = now - n.t,
        }
    end
    for _, n in ipairs(list) do
        n.ordinal = n.sameMap and Layer.OrdinalOf(partyLens, n.mapID, n.zoneUID) or nil
    end
    table.sort(list, function(x, y)
        if x.sameMap ~= y.sameMap then
            return x.sameMap
        end
        if x.canRequest ~= y.canRequest then
            return x.canRequest
        end
        if (x.ordinal or 0) ~= (y.ordinal or 0) then
            return (x.ordinal or 0) < (y.ordinal or 0)
        end
        return x.name < y.name
    end)
    return list
end

-- Layers of my map: the ones I saw, numbered, then the ones only the network reports, unnumbered.
function LayerNet.Summary(partyLens)
    local cur = Layer.Current(partyLens)
    local out, byZone = {}, {}
    local function Row(zoneUID, ordinal)
        local row = { zoneUID = zoneUID, ordinal = ordinal, nodes = 0, requestable = 0, mine = zoneUID == cur.zoneUID }
        out[#out + 1], byZone[zoneUID] = row, row
        return row
    end
    for i, zoneUID in ipairs(cur.mapID and Layer.KnownZones(partyLens, cur.mapID) or {}) do
        Row(zoneUID, i)
    end
    local heard = {}
    for _, n in ipairs(LayerNet.Nodes(partyLens)) do
        if n.sameMap then
            local row = byZone[n.zoneUID]
            if not row then
                row = Row(n.zoneUID, nil)
                heard[#heard + 1] = row
            end
            row.nodes = row.nodes + 1
            if n.canRequest then
                row.requestable = row.requestable + 1
            end
        end
    end
    table.sort(heard, function(x, y) return x.zoneUID < y.zoneUID end)
    local numbered = #out - #heard
    for i, row in ipairs(heard) do
        out[numbered + i] = row
    end
    return out
end

-- An addon whisper (no hardware event needed), but only ever a player's choice.
function LayerNet.Request(partyLens, node)
    local rt = RT(partyLens)
    if rt.my and (rt.my.state == "sent" or rt.my.state == "accepted") then
        return false, "pending"
    end
    local found
    for _, n in ipairs(LayerNet.Nodes(partyLens)) do
        if node and n.key == (node.key or Utils.NameKey(node.name)) then
            found = n
        end
    end
    if not found then
        return false, "offline"
    end
    if not found.canRequest then
        return false, found.sameLayer and "same_layer" or "cannot_request"
    end
    local cur = Layer.Current(partyLens)
    local payload = table.concat({ LayerNet.PROTO, "R", found.mapID, cur.zoneUID or 0, found.zoneUID }, "|")
    if not Net.Whisper(LayerNet.PREFIX, payload, found.name) then
        return false, "cannot_send"
    end
    local now = time()
    rt.my = { name = found.name, key = found.key, mapID = found.mapID, targetZone = found.zoneUID, state = "sent",
        t = now, stateAt = now }
    partyLens:Notice(L("NOTICE_LAYER_REQUESTED", found.name))
    Changed(partyLens)
    return true
end

function LayerNet.MyRequest(partyLens)
    return RT(partyLens).my
end

function LayerNet.Cancel(partyLens)
    local my = RT(partyLens).my
    if my and (my.state == "sent" or my.state == "accepted") then
        my.state, my.stateAt = "cancelled", time()
        Changed(partyLens)
    end
end

function LayerNet.Inbound(partyLens)
    local list = {}
    for _, r in pairs(RT(partyLens).inbound) do
        list[#list + 1] = r
    end
    table.sort(list, function(x, y) return x.t > y.t end)
    return list
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

function LayerNet.Decline(partyLens, req)
    local r = req and RT(partyLens).inbound[req.key]
    if r then
        r.state, r.stateAt = "declined", time()
        Changed(partyLens)
    end
end

function LayerNet.OnRoster(partyLens)
    local rt, changed = RT(partyLens), false
    local members = Roster.Members()
    local my = rt.my
    if my and (my.state == "sent" or my.state == "accepted") and Roster.Contains(members, my.name) then
        my.state, my.stateAt = "served", time()
        changed = true
    end
    for key, r in pairs(rt.inbound) do
        local grouped = Roster.Contains(members, r.name)
        if r.state == "invited" and grouped then
            r.state, r.stateAt = "served", time()
            changed = true
        elseif r.state == "served" and not grouped then
            rt.inbound[key] = nil -- uninvited, or gone on their own: the hop is over
            changed = true
        end
    end
    if changed then
        Changed(partyLens)
    end
end

function LayerNet.OnLayerChanged(partyLens, cur)
    local my = RT(partyLens).my
    if my and my.state == "served" and cur.mapID == my.mapID and cur.zoneUID == my.targetZone then
        my.state, my.stateAt = "hopped", time()
        partyLens:Notice(L("NOTICE_LAYER_HOPPED", my.name))
        Changed(partyLens)
    end
    LayerNet.SendPresence(partyLens)
end

local function ServedHoppers(partyLens)
    local out, members = {}, Roster.Members()
    for key, r in pairs(RT(partyLens).inbound) do
        if r.state == "served" and Roster.Contains(members, r.name) then
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
    if my and (my.state == "sent" or my.state == "accepted") and now - my.t > LayerNet.REQUEST_TTL then
        my.state, my.stateAt = "expired", now
        changed = true
    end
    if changed then
        Changed(partyLens)
    end
    if nodesChanged then
        partyLens:Fire("LAYER_NODES_CHANGED")
    end
end

function LayerNet.NodeCount(partyLens)
    return #LayerNet.Nodes(partyLens)
end

_G[ADDON_NAME .. "_LayerNet"] = LayerNet
return LayerNet
