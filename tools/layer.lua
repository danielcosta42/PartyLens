-- Layer swap through beacons, against the real modules and mesh (tools/wowstub.lua): my layer from an NPC's GUID,
-- the layers heard (PartyLens presence and ChehulNet HELLOs) with population, beacons and news but no names, a
-- request whispered to the best beacon of a layer and passed to the next one on a "no" or silence, the beacon's
-- player inviting from a click only, hops counted once per person per day with ranks, duty (away, combat, someone
-- else's group, the setting) and the group undone from a click.
--
--   luajit tools/layer.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local function hello(tags, layer)
  return "CHN1|H|" .. tags .. "|DRUID|30|v=1|" .. layer
end

local function row(PL, mapID, zoneUID)
  for _, r in ipairs(PL:GetLayers()) do
    if r.mapID == mapID and r.zoneUID == zoneUID then return r end
  end
end

-- ── the requester: Chehul Costa on Stormwind (1453), layer 101 ─────────────
local PL = W.boot({})
W.directory({ "Zed One", "Yan Two", "Xia Three" })
local changed = {}
PL:On("LAYER_CHANGED", function(cur) changed[#changed + 1] = cur end)
check(PL:GetLayer().zoneUID == nil, "no layer before any NPC was seen")
check(PL.db.beacon.on == true, "the beacon starts on: opt-out")
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
local cur = PL:GetLayer()
check(cur.mapID == 1453 and cur.zoneUID == 101 and cur.ordinal == 1, "my layer from the target's GUID")
check(#changed >= 1 and changed[#changed].zoneUID == 101, "LAYER_CHANGED says so")
W.advance(30)
local s = W.sentWhere({ prefix = "PLLnet", dist = "GUILD" })
check(#s >= 1 and s[#s].msg == "PLL2|S|1453|101|1|0", "presence goes out on GUILD: my layer, on duty, 0 hops")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER" }) >= 3, "and through the directory")
check(select(2, _G.ChehulNet:MyLayer()) == 101, "ChehulNet's HELLO carries it")
check(PL:GetBeacon().available and PL:GetBeacon().rank == 1, "alone in the open world I am on duty, first rank")

W.units.target = { name = "Ana", surname = "Lima", guid = "Player-1-9" }
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetLayer().zoneUID == 101, "a player's GUID says nothing about my layer")
W.npc("target", 555, 416, true)
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetLayer().zoneUID == 101, "nor a pet's: its creature GUID carries its owner's home layer")
W.units.target = { npc = true, guid = W.secret("Creature-0-5250-0-999-3296-0") }
local ok = pcall(W.fire, "PLAYER_TARGET_CHANGED")
check(ok and PL:GetLayer().zoneUID == 101, "a secret GUID is skipped without an error")
ok = pcall(W.fire, "NAME_PLATE_UNIT_ADDED", W.secret("nameplate1"))
check(ok, "and so is a secret unit token")

W.deliver("PLLnet", "PLL2|S|1453|202|1|5", "GUILD", "Ana Lima-ClassicBetaPvE2")
W.deliver("PLLnet", "PLL2|S|1453|202|1|12", "GUILD", "Elza Dias")
W.deliver("PLLnet", "PLL2|S|1453|202|0|50", "GUILD", "Fabi Reis")
W.deliver("ChehulNet", hello("gos", "1453:303"), "GUILD", "Bia Rocha-ClassicBetaPvE2")
W.deliver("ChehulNet", hello("ls+pl", "1453:303"), "GUILD", "Caio Nunes-ClassicBetaPvE2")
W.deliver("ChehulNet", hello("pl", "1454:404"), "GUILD", "Davi Melo-ClassicBetaPvE2")
W.deliver("PLLnet", "PLL2|S|1454|404|1|7", "GUILD", "Ivo Far")
W.deliver("PLLnet", "PLL2|S|1453|202|1|x", "GUILD", "Gil Bad")
W.deliver("PLLnet", "PLL2|S|1453|202|1|-4", "GUILD", "Hugo Bad")
local layers = PL:GetLayers()
local mine, l202, l303, l404 = row(PL, 1453, 101), row(PL, 1453, 202), row(PL, 1453, 303), row(PL, 1454, 404)
check(#layers == 4 and layers[1].zoneUID == 101 and layers[2].zoneUID == 202 and layers[3].zoneUID == 303
  and layers[4].zoneUID == 404, "my zone's layers first, then the other zones")
check(mine.mine and mine.population == 1 and mine.beacons == 1 and mine.meBeacon and mine.ordinal == 1
  and not mine.canRequest, "my layer: me, on duty")
check(l202.population == 5 and l202.beacons == 4 and l202.canRequest and l202.ordinal == nil,
  "layer 202: five heard, four beacons on duty, askable, no number (I never saw it)")
check(l303.population == 2 and l303.beacons == 0 and not l303.canRequest,
  "layer 303: a GuildOS user and a PartyLens one known only from a HELLO: population, no beacon")
check(l404.ordinal == 1 and not l404.sameMap and l404.beacons == 1 and not l404.canRequest and l404.zonePopulation == 2,
  "another zone's layer is numbered among that zone's layers and, beacon or not, is not askable from here")
local named = false
for _, r in ipairs(layers) do
  for _, v in pairs(r) do if type(v) == "string" then named = true end end
end
check(not named, "no row carries a name")
for i = 1, 30 do
  W.deliver("PLLnet", "PLL2|S|1453|" .. (1000 + i) .. "|0|0", "WHISPER", "Spoof " .. string.char(64 + i) .. "x")
end
check(PL:GetLayer().ordinal == 1 and PL:GetLayer().count == 1, "30 spoofed presences do not make me 'layer 31 of 31'")

check(select(2, PL:RequestLayer(l303)) == "no_beacon", "a layer without a beacon cannot be asked")
check(select(2, PL:RequestLayer(l404)) == "other_map", "nor a layer of another zone")
check(select(2, PL:RequestLayer(mine)) == "same_layer", "nor my own")
W.sent = {}
check(W.click(PL.RequestLayer, PL, l202), "asking for layer 202")
W.advance(2)
local r = W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Elza Dias" })
check(#r == 1 and r[1].msg == "PLL2|R|1453|101|202", "the beacon with the most hops is asked first: map, my layer, hers")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Ana Lima" }) == 0, "and only her")
check(PL:GetMyLayerRequest().state == "sent", "my request is sent")
check(select(2, PL:RequestLayer(l202)) == "pending", "one request at a time")

W.deliver("PLLnet", "PLL2|N|1453|202", "WHISPER", "Zed One")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Ana Lima" }) == 0, "a no from somebody else changes nothing")
W.deliver("PLLnet", "PLL2|N|1453|202", "GUILD", "Elza Dias")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Ana Lima" }) == 0, "nor hers heard on GUILD")
W.deliver("PLLnet", "PLL2|N|1453|202", "WHISPER", "Elza Dias")
W.advance(2)
r = W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Ana Lima" })
check(#r == 1 and PL:GetMyLayerRequest().state == "sent", "her whispered no: the next beacon (Ana) is asked by itself")
W.advance(41)
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Gil Bad" }) == 1,
  "Ana silent for 40 s: the next one (a bad hop count reads as 0) is asked")
W.advance(41)
W.advance(41)
check(PL:GetMyLayerRequest().state == "expired", "with every beacon tried the request is over")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Fabi Reis" }) == 0, "a node off duty is never asked")

W.sent = {}
W.click(PL.RequestLayer, PL, l202)
W.advance(2)
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Elza Dias" }) == 1, "a new request starts over")
W.deliver("PLLnet", "PLL2|A|1453|202", "GUILD", "Elza Dias")
check(PL:GetMyLayerRequest().state == "sent", "an accept heard on GUILD is not hers to me")
W.deliver("PLLnet", "PLL2|A|1453|202", "WHISPER", "Ana Lima")
check(PL:GetMyLayerRequest().state == "sent", "nor one whispered by a beacon I did not ask now")
W.deliver("PLLnet", "PLL2|A|1453|202", "WHISPER", "Elza Dias")
check(PL:GetMyLayerRequest().state == "accepted", "her whispered accept: the invite is on its way")
W.advance(60)
check(PL:GetMyLayerRequest().state == "accepted", "and no other beacon is asked meanwhile")
W.setGroup({ { name = "Ivo", surname = "Sol" } })
check(PL:GetMyLayerRequest().state == "accepted", "joining somebody else's group serves nothing")
check(not PL:GetBeacon().available and PL:GetBeacon().why == "grouped", "and in a group I did not form I am off duty")
W.setGroup({ { name = "Elza", surname = "Dias" } })
check(PL:GetMyLayerRequest().state == "served", "joining her group serves the request")
W.npc("target", 202)
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetMyLayerRequest().state == "hopped" and PL:GetLayer().zoneUID == 202, "my layer is hers now")
check(PL:CanUndoLayer(), "the hop can be undone while grouped")
PL:UndoLayerGroup()
check(#W.left == 0 and #W.violations == 1 and W.violations[1].fn == "LeaveParty",
  "leaving from outside a click is blocked")
W.violations = {}
W.click(PL.UndoLayerGroup, PL)
check(#W.left == 1, "from a click it leaves the group")
W.setGroup({})
check(not PL:CanUndoLayer() and PL:GetMyLayerRequest().state == "hopped", "out of the group, I stay on her layer")
check(#W.invites == 0, "the requester never invited anybody")

W.advance(200)
local l = row(PL, 1453, 202)
check(l and l.population >= 4 and l.beacons == (l.meBeacon and 1 or 0),
  "a beacon flag not refreshed in 150 s is not counted (the node still is)")

-- ── the beacon: Ana Lima on layer 202 ──────────────────────────────────────
PL = W.boot({ name = "Ana", surname = "Lima", class = "DRUID" })
W.npc("target", 202)
W.fire("PLAYER_TARGET_CHANGED")
local received, served = {}, {}
PL:On("LAYER_REQUEST_RECEIVED", function(req) received[#received + 1] = req end)
PL:On("BEACON_SERVED", function(st) served[#served + 1] = st end)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "GUILD", "Chehul Costa")
check(#PL:GetLayerRequests() == 0, "a request heard on GUILD is ignored: requests are whispered")
W.sent = {}
W.deliver("PLLnet", "PLL2|R|1453|101|999", "WHISPER", "Chehul Costa")
W.advance(3)
local no = W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Chehul Costa" })
check(#PL:GetLayerRequests() == 0 and #no == 1 and no[1].msg == "PLL2|N|1453|202",
  "one for a layer I am not on gets a no, so the asker moves on")
W.deliver("PLLnet", "PLL2|R|1453|101|999", "WHISPER", "Chehul Costa")
W.advance(3)
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Chehul Costa" }) == 1, "one no per 30 s per asker")
W.advance(30)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Chehul Costa-ClassicBetaPvE2")
local reqs = PL:GetLayerRequests()
check(#reqs == 1 and reqs[1].name == "Chehul Costa" and reqs[1].state == "open" and reqs[1].fromZone == 101,
  "a whispered request for my layer is listed")
check(#received == 1 and received[1].name == "Chehul Costa", "LAYER_REQUEST_RECEIVED fired for the UI's prompt")
check(PL:GetBeacon().queue == 1, "the beacon status counts it")
local notices = #W.printed
for _ = 1, 50 do W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Chehul Costa") end
check(#received == 1 and #W.printed == notices and #PL:GetLayerRequests() == 1,
  "50 repeats from him are one request: no new prompt, no new notice")
W.advance(60)
check(#W.invites == 0 and #W.violations == 0, "and nothing invited him by itself, a minute on")

PL:ServeLayerRequest(reqs[1])
check(#W.invites == 0 and #W.violations == 1 and W.violations[1].fn == "InviteUnit",
  "serving from outside a click is blocked by the game")
W.violations, W.sent = {}, {}
check(W.click(PL.ServeLayerRequest, PL, reqs[1]), "serving from a click")
check(W.invites[1] == "Chehul Costa", "invites him by full name")
W.advance(2)
local a = W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Chehul Costa" })
check(#a == 1 and a[1].msg == "PLL2|A|1453|202", "and tells him the invite is coming")
check(PL:GetLayerRequests()[1].state == "invited", "the request is invited")
check(#served == 0 and PL.db.beacon.hops == 0, "an invite alone is no hop")
W.setGroup({ { name = "Chehul", surname = "Costa" } })
check(PL:GetLayerRequests()[1].state == "served", "he joined: served")
check(#served == 1 and served[1].hops == 1 and served[1].today == 1 and served[1].name == "Chehul Costa"
  and PL.db.beacon.hops == 1, "his joining counts one hop (BEACON_SERVED)")
check(PL:GetBeacon().available, "with only my hopper in the group I stay on duty")
check(PL:CanUndoLayer(), "and I can undo the group")
PL:UndoLayerGroup()
check(#W.uninvites == 0 and W.violations[1].fn == "UninviteUnit", "uninviting from outside a click is blocked")
W.violations = {}
W.click(PL.UndoLayerGroup, PL)
check(W.uninvites[1] == "Chehul Costa", "undo uninvites him, from a click")
W.setGroup({})
check(#PL:GetLayerRequests() == 0 and not PL:CanUndoLayer(), "and once he is out the request is done")

W.advance(31)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Chehul Costa")
W.click(PL.ServeLayerRequest, PL, PL:GetLayerRequests()[1])
W.setGroup({ { name = "Chehul", surname = "Costa" } })
check(#served == 1 and PL.db.beacon.hops == 1, "the same person again the same day is no new hop")
W.click(PL.UndoLayerGroup, PL)
W.setGroup({})

-- Ranks
PL.db.beacon.hops = 9
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Rui Alto")
check(W.click(PL.ServeNextLayerRequest, PL), "the key binding serves the oldest open request, from a click")
check(W.invites[#W.invites] == "Rui Alto", "inviting him")
W.setGroup({ { name = "Rui", surname = "Alto" } })
local st = served[#served]
check(st.hops == 10 and st.rank == 3 and st.rankUp and st.rankAt == 10 and st.nextAt == 25,
  "the tenth hop is a new rank (Lighthouse), with the next one at 25")
check(not W.click(PL.ServeNextLayerRequest, PL), "with nothing open the binding does nothing")
W.click(PL.UndoLayerGroup, PL)
W.setGroup({})

-- Duty
W.advance(15)
W.sent = {}
W.afk = true
W.fire("PLAYER_FLAGS_CHANGED", "player")
check(not PL:GetBeacon().available and PL:GetBeacon().why == "afk", "away: off duty")
W.advance(12)
s = W.sentWhere({ prefix = "PLLnet", dist = "GUILD" })
check(#s >= 1 and s[#s].msg == "PLL2|S|1453|202|0|10", "and the network hears it: on duty 0, 10 hops")
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Sol Away")
W.advance(3)
check(#PL:GetLayerRequests() == 0 and #W.sentWhere({ prefix = "PLLnet", target = "Sol Away" }) == 1,
  "a request while away gets a no, no prompt")
W.afk = false
W.fire("PLAYER_FLAGS_CHANGED", "player")
W.combat = true
W.fire("PLAYER_REGEN_DISABLED")
check(PL:GetBeacon().why == "combat", "in combat: off duty")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(PL:GetBeacon().available, "out of combat: back on duty")
W.click(PL.SetBeacon, PL, false)
check(PL.db.beacon.on == false and PL:GetBeacon().why == "off", "the setting turns it off")
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Tom Off")
check(#PL:GetLayerRequests() == 0, "and then requests are not taken")
PL:SetBeacon(true)
check(PL:GetBeacon().available, "and back on")

W.advance(31)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
W.sent = {}
PL:DeclineLayerRequest(PL:GetLayerRequests()[1])
W.advance(3)
check(PL:GetLayerRequests()[1].state == "declined", "a request can be declined")
check(#W.sentWhere({ prefix = "PLLnet", target = "Fabi Reis" }) == 1, "and she hears no")
check(not W.click(PL.ServeLayerRequest, PL, PL:GetLayerRequests()[1]), "and is not served after that")
local toasts = #received
W.advance(45)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
check(PL:GetLayerRequests()[1].state == "declined" and #received == toasts,
  "asking again after a decline changes nothing: still declined, no prompt")
W.advance(125)
check(#PL:GetLayerRequests() == 1, "a decline is held for a while")
W.advance(10 * 60)
check(#PL:GetLayerRequests() == 0, "then the request leaves the list")
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
check(#received == toasts + 1, "and she may ask again")
W.click(PL.DeclineLayerRequest, PL, PL:GetLayerRequests()[1])

-- Invites nobody takes do not block the list.
local function namedReq(name)
  for _, req in ipairs(PL:GetLayerRequests()) do if req.name == name then return req end end
end
for i = 1, 10 do
  W.advance(3)
  W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Asker" .. string.char(64 + i) .. " Paz")
end
check(#PL:GetLayerRequests() == 10 and not namedReq("Fabi Reis") and namedReq("AskerJ Paz"),
  "a full list makes room for a new request: the oldest one (her decline) goes")
for _, req in ipairs(PL:GetLayerRequests()) do W.click(PL.ServeLayerRequest, PL, req) end
W.setGroup({ { name = "AskerA", surname = "Paz" } })
check(namedReq("AskerA Paz").state == "served", "the oldest one joined my group")
toasts = #received
W.advance(3)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fresh Person")
check(#received == toasts + 1 and #PL:GetLayerRequests() == 10 and namedReq("Fresh Person") and not namedReq("AskerB Paz"),
  "invites nobody took still make room: the oldest not in my group goes, the new one is prompted")
check(namedReq("AskerA Paz") and namedReq("AskerA Paz").state == "served", "a hopper in my group is never evicted")
W.advance(3 * 60)
local left = {}
for _, req in ipairs(PL:GetLayerRequests()) do left[#left + 1] = req.name .. ":" .. req.state end
check(#left == 1 and left[1] == "AskerA Paz:served",
  "invites not taken within 150 s and open requests go; the one who joined stays (" .. table.concat(left, ",") .. ")")
W.setGroup({})

W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Gil Paz")
W.npc("target", 303)
W.fire("PLAYER_TARGET_CHANGED")
check(select(2, W.click(PL.ServeLayerRequest, PL, PL:GetLayerRequests()[1])) == "not_on_layer",
  "a request for a layer I left is not served")

ok = pcall(_G.ChehulMesh.handlers.PLLnet, W.secret("PLL2|R|1453|101|303"), "Hugo Luz", "WHISPER")
check(ok, "a secret request payload raises nothing")

-- ── news of each layer ─────────────────────────────────────────────────────
PL = W.boot({})
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
W.deliver("PLLnet", "PLL2|S|1453|202|0|3", "GUILD", "Ana Lima")
W.advance(30)
local function news(mapID, zoneUID)
  local rw = row(PL, mapID, zoneUID)
  return rw and rw.news or {}
end
check(#news(1453, 202) == 0, "the first look after login only takes the picture")
W.deliver("PLLnet", "PLL2|S|1453|202|1|3", "GUILD", "Ana Lima")
W.deliver("ChehulNet", hello("gos", "1454:404"), "GUILD", "Bia Rocha")
W.advance(30)
check(news(1453, 202)[1] and news(1453, 202)[1].kind == "beacon_on" and news(1453, 202)[1].n == 1,
  "a beacon going on duty is news")
check(news(1454, 404)[1] and news(1454, 404)[1].kind == "new", "a layer heard for the first time is news")
W.deliver("PLLnet", "PLL2|S|1453|202|1|5", "GUILD", "Ana Lima")
W.advance(30)
check(news(1453, 202)[1].kind == "hop" and news(1453, 202)[1].n == 2, "a beacon whose hops went up brought people over")
W.deliver("PartyLens", table.concat({ "2", "lfm", "heal", "dungeon", "thanes", "0", "DRUID", "34", "202", "1453",
  "1.0.2", "1.1.3", tostring(time()), "0", "Ana Lima", "need heal" }, "|"), "GUILD", "Ana Lima")
W.advance(30)
check(news(1453, 202)[1].kind == "group" and row(PL, 1453, 202).groups == 1, "a group forming there is news")
for i = 1, 3 do W.deliver("ChehulNet", hello("gos", "1453:202"), "GUILD", "Crowd" .. string.char(64 + i) .. " Paz") end
for _ = 1, 10 do
  W.deliver("PLLnet", "PLL2|S|1453|202|1|5", "GUILD", "Ana Lima")
  for i = 1, 3 do W.deliver("ChehulNet", hello("gos", "1453:202"), "GUILD", "Crowd" .. string.char(64 + i) .. " Paz") end
  W.advance(30)
end
local grew = false
for _, n in ipairs(news(1453, 202)) do if n.kind == "grow" and n.n == 3 then grew = true end end
check(grew, "three more people over a few minutes is news")
check(#news(1453, 202) <= 4, "a layer keeps its last four news")
W.advance(25 * 60)
check(#news(1453, 202) <= 1, "news older than 30 minutes go")

-- ── a reading that flips ───────────────────────────────────────────────────
PL = W.boot({})
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
W.advance(30)
local before = #W.sentWhere({ prefix = "PLLnet", dist = "GUILD" })
for _, z in ipairs({ 111, 101, 111, 101 }) do
  W.npc("target", z)
  W.fire("PLAYER_TARGET_CHANGED")
  W.advance(1)
end
check(#W.sentWhere({ prefix = "PLLnet", dist = "GUILD" }) == before + 1, "a flapping layer reading is held back")
W.advance(10)
s = W.sentWhere({ prefix = "PLLnet", dist = "GUILD" })
check(#s == before + 2 and s[#s].msg == "PLL2|S|1453|101|1|0",
  "to one presence per 10 s, the last reading following once the gap is over")

-- ── instances ──────────────────────────────────────────────────────────────
PL = W.boot({})
W.directory({ "Zed One" })
W.instance = true
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetLayer().zoneUID == nil and PL:GetLayer().inInstance, "inside an instance there is no layer")
check(PL:GetBeacon().why == "instance", "and no duty")
W.instance = false
check(PL:GetLayer().zoneUID == nil, "and an NPC seen inside it is not taken for my layer once out")
W.instance = true
W.advance(130)
check(#W.sentWhere({ prefix = "PLLnet" }) == 0, "and no presence")
check(#W.violations == 0 and #W.errors == 0, "nothing protected ran and nothing raised")

W.done("layer")
