-- Layer swap as a click tool, against the real modules and mesh (tools/wowstub.lua): my layer from an NPC's GUID,
-- the nodes on other layers (PartyLens presence and ChehulNet HELLOs), a request whispered to a node, the node's
-- player inviting from a click only, the requester served when they join and hopped when their layer changes, and
-- the group undone from a click.
--
--   luajit tools/layer.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local function hello(tags, layer)
  return "CHN1|H|" .. tags .. "|DRUID|30|v=1|" .. layer
end

-- ── the requester: Chehul Costa on Stormwind (1453), layer 101 ─────────────
local PL = W.boot({})
W.directory({ "Zed One", "Yan Two", "Xia Three" })
local changed = {}
PL:On("LAYER_CHANGED", function(cur) changed[#changed + 1] = cur end)
check(PL:GetLayer().zoneUID == nil, "no layer before any NPC was seen")
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
local cur = PL:GetLayer()
check(cur.mapID == 1453 and cur.zoneUID == 101 and cur.ordinal == 1, "my layer from the target's GUID")
check(#changed >= 1 and changed[#changed].zoneUID == 101, "LAYER_CHANGED says so")
W.advance(30)
local s = W.sentWhere({ prefix = "PLLnet", dist = "GUILD" })
check(#s >= 1 and s[1].msg == "PLL2|S|1453|101", "presence goes out on GUILD when the layer is found")
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER" }) >= 3, "and through the directory")
check(select(2, _G.ChehulNet:MyLayer()) == 101, "ChehulNet's HELLO carries it")


W.units.player2 = nil
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

W.deliver("PLLnet", "PLL2|S|1453|202", "GUILD", "Ana Lima-ClassicBetaPvE2")
W.deliver("ChehulNet", hello("gos", "1453:303"), "GUILD", "Bia Rocha-ClassicBetaPvE2")
W.deliver("ChehulNet", hello("ls+pl", "1453:303"), "GUILD", "Caio Nunes-ClassicBetaPvE2")
W.deliver("ChehulNet", hello("pl", "1454:404"), "GUILD", "Davi Melo-ClassicBetaPvE2")
local nodes = {}
for _, n in ipairs(PL:GetLayerNodes()) do nodes[n.name] = n end
check(nodes["Ana Lima"] and nodes["Ana Lima"].canRequest and nodes["Ana Lima"].zoneUID == 202,
  "a PartyLens node on another layer of my map can be asked")
check(nodes["Ana Lima"].ordinal == nil and PL:GetLayer().count == 1 and PL:GetLayer().ordinal == 1,
  "a layer only the network reports gets no number: I number what I saw myself")
check(nodes["Bia Rocha"] and not nodes["Bia Rocha"].canRequest and nodes["Bia Rocha"].zoneUID == 303,
  "a GuildOS user shows on its layer from the HELLO, but cannot be asked")
check(nodes["Caio Nunes"] and nodes["Caio Nunes"].canRequest and nodes["Caio Nunes"].source == "cn",
  "a PartyLens user known only from its HELLO can be asked")
check(nodes["Davi Melo"] and not nodes["Davi Melo"].sameMap and not nodes["Davi Melo"].canRequest,
  "a node on another map is listed, not askable")
local summary = PL:GetLayerSummary()
check(#summary == 3 and summary[1].mine and summary[1].ordinal == 1 and summary[2].zoneUID == 202
  and summary[2].ordinal == nil and summary[3].nodes == 2 and summary[3].requestable == 1,
  "the summary: my numbered layers, then the network's unnumbered ones, with their nodes")
for i = 1, 30 do
  W.deliver("PLLnet", "PLL2|S|1453|" .. (1 + i), "WHISPER", "Spoof " .. string.char(64 + i) .. "x")
end
check(PL:GetLayer().ordinal == 1 and PL:GetLayer().count == 1, "30 spoofed presences do not make me 'layer 31 of 31'")

check(select(2, PL:RequestLayer(nodes["Bia Rocha"])) == "cannot_request", "asking a non-PartyLens node is refused")
W.sent = {}
check(W.click(PL.RequestLayer, PL, nodes["Ana Lima"]), "asking Ana")
W.advance(2)
local r = W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Ana Lima" })
check(#r == 1 and r[1].msg == "PLL2|R|1453|101|202", "the request is whispered to her: map, my layer, hers")
check(PL:GetMyLayerRequest().state == "sent", "my request is sent")
check(select(2, PL:RequestLayer(nodes["Caio Nunes"])) == "pending", "one request at a time")

W.deliver("PLLnet", "PLL2|A|1453|202", "GUILD", "Ana Lima")
check(PL:GetMyLayerRequest().state == "sent", "an accept heard on GUILD is not hers to me")
W.deliver("PLLnet", "PLL2|A|1453|202", "WHISPER", "Zed One")
check(PL:GetMyLayerRequest().state == "sent", "nor one whispered by somebody else")
W.deliver("PLLnet", "PLL2|A|1453|202", "WHISPER", "Ana Lima-ClassicBetaPvE2")
check(PL:GetMyLayerRequest().state == "accepted", "her whispered accept: the invite is on its way")
W.setGroup({ { name = "Ivo", surname = "Sol" } })
check(PL:GetMyLayerRequest().state == "accepted", "joining somebody else's group serves nothing")
W.setGroup({ { name = "Ana", surname = "Lima" } })
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

-- An unanswered request expires.
W.setGroup({})
W.deliver("PLLnet", "PLL2|S|1453|101", "GUILD", "Elza Dias")
for _, n in ipairs(PL:GetLayerNodes()) do if n.name == "Elza Dias" then nodes.elza = n end end
W.click(PL.RequestLayer, PL, nodes.elza)
W.advance(151)
check(PL:GetMyLayerRequest().state == "expired", "a request nobody answers expires after two minutes")

-- ── the node: Ana Lima on layer 202 ────────────────────────────────────────
PL = W.boot({ name = "Ana", surname = "Lima", class = "DRUID" })
W.npc("target", 202)
W.fire("PLAYER_TARGET_CHANGED")
local received = {}
PL:On("LAYER_REQUEST_RECEIVED", function(req) received[#received + 1] = req end)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "GUILD", "Chehul Costa")
check(#PL:GetLayerRequests() == 0, "a request heard on GUILD is ignored: requests are whispered")
W.deliver("PLLnet", "PLL2|R|1453|101|999", "WHISPER", "Chehul Costa")
check(#PL:GetLayerRequests() == 0, "and one for a layer I am not on")
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Chehul Costa-ClassicBetaPvE2")
local reqs = PL:GetLayerRequests()
check(#reqs == 1 and reqs[1].name == "Chehul Costa" and reqs[1].state == "open" and reqs[1].fromZone == 101,
  "a whispered request for my layer is listed")
check(#received == 1 and received[1].name == "Chehul Costa", "LAYER_REQUEST_RECEIVED fired for the UI's toast")
local notices = #W.printed
for _ = 1, 50 do W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Chehul Costa") end
check(#received == 1 and #W.printed == notices and #PL:GetLayerRequests() == 1,
  "50 repeats from him are one request: no new toast, no new notice")
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
W.setGroup({ { name = "Chehul", surname = "Costa" } })
check(PL:GetLayerRequests()[1].state == "served", "he joined: served")
check(PL:CanUndoLayer(), "and I can undo the group")
PL:UndoLayerGroup()
check(#W.uninvites == 0 and W.violations[1].fn == "UninviteUnit", "uninviting from outside a click is blocked")
W.violations = {}
W.click(PL.UndoLayerGroup, PL)
check(W.uninvites[1] == "Chehul Costa", "undo uninvites him, from a click")
W.setGroup({})
check(#PL:GetLayerRequests() == 0 and not PL:CanUndoLayer(), "and once he is out the request is done")

W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
PL:DeclineLayerRequest(PL:GetLayerRequests()[1])
check(PL:GetLayerRequests()[1].state == "declined", "a request can be declined")
check(not W.click(PL.ServeLayerRequest, PL, PL:GetLayerRequests()[1]), "and is not served after that")
local toasts = #received
W.advance(45)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
check(PL:GetLayerRequests()[1].state == "declined" and #received == toasts,
  "asking again after a decline changes nothing: still declined, no toast")
W.advance(125)
check(#PL:GetLayerRequests() == 1, "a decline is held for a while")
W.advance(10 * 60)
check(#PL:GetLayerRequests() == 0, "then the request leaves the list")
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fabi Reis")
check(#received == toasts + 1, "and she may ask again")
W.click(PL.DeclineLayerRequest, PL, PL:GetLayerRequests()[1])

-- Invites nobody takes do not block the list.
local function named(name)
  for _, req in ipairs(PL:GetLayerRequests()) do if req.name == name then return req end end
end
for i = 1, 10 do
  W.advance(1)
  W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Asker" .. string.char(64 + i) .. " Paz")
end
check(#PL:GetLayerRequests() == 10 and not named("Fabi Reis") and named("AskerJ Paz"),
  "a full list makes room for a new request: the oldest one (her decline) goes")
for _, req in ipairs(PL:GetLayerRequests()) do W.click(PL.ServeLayerRequest, PL, req) end
W.setGroup({ { name = "AskerA", surname = "Paz" } })
check(named("AskerA Paz").state == "served", "the oldest one joined my group")
toasts = #received
W.advance(1)
W.deliver("PLLnet", "PLL2|R|1453|101|202", "WHISPER", "Fresh Person")
check(#received == toasts + 1 and #PL:GetLayerRequests() == 10 and named("Fresh Person") and not named("AskerB Paz"),
  "invites nobody took still make room: the oldest not in my group goes, the new one is toasted")
check(named("AskerA Paz") and named("AskerA Paz").state == "served", "a hopper in my group is never evicted")
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
check(#s == before + 2 and s[#s].msg == "PLL2|S|1453|101",
  "to one presence per 10 s, the last reading following once the gap is over")

-- ── instances ──────────────────────────────────────────────────────────────
PL = W.boot({})
W.directory({ "Zed One" })
W.instance = true
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetLayer().zoneUID == nil and PL:GetLayer().inInstance, "inside an instance there is no layer")
W.instance = false
check(PL:GetLayer().zoneUID == nil, "and an NPC seen inside it is not taken for my layer once out")
W.instance = true
W.advance(130)
check(#W.sentWhere({ prefix = "PLLnet" }) == 0, "and no presence")
check(#W.violations == 0 and #W.errors == 0, "nothing protected ran and nothing raised")

W.done("layer")
