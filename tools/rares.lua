-- Rare sightings by layer, against the real modules and mesh (tools/wowstub.lua): a rare, rare elite or world boss
-- targeted, moused over or seen on a nameplate is told to the network (GUILD, group, realm) at most once per
-- SEND_GAP per rare, layer and state, and only when nobody told it during the wait; a sighting heard from the network
-- for my zone prompts me once, with a way to the rare's layer (the beacons) and a map pin, one prompt per
-- PROMPT_GAP; anything out of shape, stale, past a sender's (or a relaying peer's, or everyone's) budget is dropped,
-- and a clock ahead never outranks what I see.
--
--   luajit tools/rares.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local function wire(mapID, zoneUID, npcID, x, y, alive, kind, seen, name)
  return table.concat({ "PLR1", "S", mapID, zoneUID, npcID, x, y, alive, kind, seen, name }, "|")
end

-- ── seeing a rare ──────────────────────────────────────────────────────────
local PL = W.boot({})
W.directory({ "Zed One", "Yan Two", "Xia Three" })
local prompts = {}
PL:On("RARE_SPOTTED", function(v) prompts[#prompts + 1] = v end)
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
check(PL:GetLayer().zoneUID == 101, "my layer from an NPC")

W.sent = {}
W.rare("target", 101, 61, "Mor'Ladim", "rare")
W.fire("PLAYER_TARGET_CHANGED")
local now = time()
W.advance(16) -- the wait for someone else's word (SEND_DELAY + SEND_JITTER), then ChatThrottleLib
local g = W.sentWhere({ prefix = "PLRare", dist = "GUILD" })
check(#g == 1 and g[1].msg == wire(1453, 101, 61, 523, 301, 1, "r", now, "Mor'Ladim"),
  "a rare targeted goes on GUILD: map, layer, npc, my position in thousandths, alive, kind, server time, name")
check(#prompts == 0, "a rare I see myself prompts nothing")
local list = PL:GetRares(1453)
check(#list == 1 and list[1].mine and list[1].here and list[1].alive and list[1].name == "Mor'Ladim",
  "and it is on my list, on my layer")
W.advance(30)
check(#W.sentWhere({ prefix = "PLRare", dist = "WHISPER" }) >= 1, "the realm copy goes by whisper to the directory")

W.sent = {}
W.fire("UPDATE_MOUSEOVER_UNIT")
W.units.mouseover = W.units.target
W.fire("UPDATE_MOUSEOVER_UNIT")
W.advance(16)
check(#W.sentWhere({ prefix = "PLRare" }) == 0, "the same rare again within SEND_GAP goes out no more")
W.units.target.dead = true
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
g = W.sentWhere({ prefix = "PLRare", dist = "GUILD" })
check(#g == 1 and W.fields(g[1].msg)[8] == "0", "its death goes out after the same wait")
W.units.target.dead = false

W.sent = {}
W.rare("target", 101, 62, "Gnoll Boss", "normal")
W.fire("PLAYER_TARGET_CHANGED")
W.units.target = { name = "Ana", surname = "Lima", guid = "Player-1-9", classification = "rare" }
W.fire("PLAYER_TARGET_CHANGED")
W.rare("target", 101, 63, "Pet Rare", "rare")
W.units.target.pet = true
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
check(#W.sentWhere({ prefix = "PLRare" }) == 0, "a normal creature, a player or a pet is no sighting")
W.rare("target", 101, 64, "Secret Rare", "rare")
W.units.target.classification = W.secret("rare")
local ok = pcall(W.fire, "PLAYER_TARGET_CHANGED")
W.rare("nameplate1", 101, 65, "Secret Death", "rare")
W.units.nameplate1.dead = W.secret(false)
ok = ok and pcall(W.fire, "NAME_PLATE_UNIT_ADDED", "nameplate1")
W.advance(16)
check(ok and #W.sentWhere({ prefix = "PLRare" }) == 0, "a secret classification or death is skipped without an error")
W.rare("nameplate2", 101, 66, "Elite One", "rareelite")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
W.advance(16)
g = W.sentWhere({ prefix = "PLRare", dist = "GUILD" })
check(#g == 1 and W.fields(g[1].msg)[9] == "e", "a rare elite seen on a nameplate counts, kind e")
W.sent = {}
W.instance = true
W.rare("target", 101, 67, "Inside", "worldboss")
W.fire("PLAYER_TARGET_CHANGED")
W.instance = false
PL.db.rares.share = false
W.rare("target", 101, 68, "Not Shared", "worldboss")
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
local inside = false
for _, r in ipairs(PL:GetRares()) do inside = inside or r.name == "Inside" end
check(#W.sentWhere({ prefix = "PLRare", dist = "GUILD" }) == 0 and not inside,
  "nothing seen inside an instance, nothing sent with sharing off")
local kept = false
for _, r in ipairs(PL:GetRares(1453)) do kept = kept or r.name == "Not Shared" end
check(kept, "with sharing off I still keep what I saw")
PL.db.rares.share = true
W.pos = nil
W.sent = {}
W.rare("target", 101, 69, "Nowhere", "rare")
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
g = W.sentWhere({ prefix = "PLRare", dist = "GUILD" })
check(#g == 1 and W.fields(g[1].msg)[6] == "" and W.fields(g[1].msg)[7] == "", "no position from the game: empty x, y")
W.pos = { x = 0.523, y = 0.301 }

-- ── hearing a rare ─────────────────────────────────────────────────────────
W.deliver("PLLnet", "PLL2|S|1453|202|1|5", "GUILD", "Elza Dias")
now = time()
W.deliver("PLRare", wire(1453, 202, 71, 400, 650, 1, "r", now - 30, "Fenros"), "GUILD", "Ana Lima-ClassicBetaPvE2")
check(#prompts == 1 and prompts[1].name == "Fenros" and prompts[1].zoneUID == 202 and prompts[1].onMyMap
  and not prompts[1].here and prompts[1].canGo and prompts[1].canMark and prompts[1].ago == 30,
  "a rare alive on another layer of my zone prompts me: go there (a beacon is on duty) or mark it")
local row
for _, r in ipairs(PL:GetLayers()) do if r.zoneUID == 202 then row = r end end
check(row and #row.rares == 1 and row.rares[1].name == "Fenros", "the layer page lists it among the layer's news")

W.sent = {}
check(W.click(PL.GoToRare, PL, prompts[1]), "Go: asks a beacon of that layer")
W.advance(2)
check(#W.sentWhere({ prefix = "PLLnet", dist = "WHISPER", target = "Elza Dias" }) == 1, "the beacon gets the request")
check(W.click(PL.MarkRare, PL, prompts[1]) and #W.waypoints == 1 and W.waypoints[1].uiMapID == 1453
  and math.abs(W.waypoints[1].x - 0.4) < 1e-9 and math.abs(W.waypoints[1].y - 0.65) < 1e-9 and W.superTracked,
  "Mark: the game's pin at the reporter's spot, tracked")

W.deliver("PLRare", wire(1453, 202, 71, 410, 650, 1, "r", now - 10, "Fenros"), "GUILD", "Bia Rocha")
check(#prompts == 1, "the same rare on the same layer again: no second prompt")
W.deliver("PLRare", wire(1453, 202, 71, 410, 650, 1, "r", now - 60, "Fenros"), "GUILD", "Caio Nunes")
local f71
for _, r in ipairs(PL:GetRares(1453)) do if r.npcID == 71 then f71 = r end end
check(f71.x == 410 and f71.seen == now - 10, "an older word about it changes nothing")
W.deliver("PLRare", wire(1453, 202, 71, "", "", 0, "r", now - 5, "Fenros"), "GUILD", "Bia Rocha")
for _, r in ipairs(PL:GetRares(1453)) do if r.npcID == 71 then f71 = r end end
check(not f71.alive and f71.x == 410 and #prompts == 1, "its death: no prompt, the last position kept")
W.deliver("PLRare", wire(1453, 202, 71, 410, 650, 1, "r", now - 2, "Fenros"), "GUILD", "Caio Nunes")
check(#prompts == 1, "alive again within NOTIFY_GAP: still no second prompt for it")
W.advance(31) -- PROMPT_GAP
now = time()
W.deliver("PLRare", wire(1453, 303, 72, 100, 100, 1, "w", now, "Azuregos"), "GUILD", "Bia Rocha")
check(#prompts == 2 and not prompts[2].canGo and prompts[2].canMark, "another rare: a prompt; no beacon there, no Go")
PL:CancelLayerRequest()
check(select(2, PL:GoToRare(prompts[2])) == "no_beacon", "and Go says why")
W.deliver("PLRare", wire(1454, 404, 73, 100, 100, 1, "r", now, "Far Away"), "GUILD", "Bia Rocha")
check(#prompts == 2 and #PL:GetRares(1454) == 1, "a rare of another zone is kept, no prompt")
PL.db.rares.notify = false
W.deliver("PLRare", wire(1453, 202, 74, 100, 100, 1, "r", now, "Quiet One"), "GUILD", "Bia Rocha")
check(#prompts == 2, "with the prompt off nothing pops")
PL.db.rares.notify = true
W.advance(31)
now = time()
W.deliver("PLRare", wire(1453, 101, 75, 100, 100, 1, "r", now, "On Mine"), "GUILD", "Bia Rocha")
check(#prompts == 3 and prompts[3].here and not prompts[3].canGo, "a rare on my own layer: a prompt, nothing to go to")

local before = #PL:GetRares()
local bad = {
  "PLR1|S|1453|202|80|1|1|1|r|" .. now, -- a field short
  wire(1453, 202, 80, 1, 1, 1, "r", now, "A") .. "|extra",
  wire(0, 202, 80, 1, 1, 1, "r", now, "Zero Map"),
  wire(1453, 202, 80, 1001, 1, 1, "r", now, "Off Map"),
  wire(1453, 202, 80, 5, "", 1, "r", now, "Half Pos"),
  wire(1453, 202, 80, 1, 1, 2, "r", now, "Alive Two"),
  wire(1453, 202, 80, 1, 1, 1, "z", now, "Odd Kind"),
  wire(1453, 202, 80, 1, 1, 1, "r", now - 16 * 60, "Too Old"),
  wire(1453, 202, 80, 1, 1, 1, "r", now + 600, "Too New"),
  wire(1453, 202, 80, 1, 1, 1, "r", now, "Bell\7Char"),
  wire(1453, 202, 80, 1, 1, 1, "r", now, string.rep("x", 49)),
  wire(1453, 202, "1.5", 1, 1, 1, "r", now, "Half Npc"),
  wire(1453, 202, "inf", 1, 1, 1, "r", now, "Inf Npc"),
  "PLR2|S|1453|202|80|1|1|1|r|" .. now .. "|Wrong Proto",
}
for _, msg in ipairs(bad) do W.deliver("PLRare", msg, "GUILD", "Odd Sender") end
check(#PL:GetRares() == before and #prompts == 3, "anything out of shape is dropped")
local handler = _G.ChehulMesh.handlers.PLRare
ok = pcall(handler, W.secret(wire(1453, 202, 83, 1, 1, 1, "r", now, "Secret")), "Bia Rocha", "GUILD")
ok = ok and pcall(handler, wire(1453, 202, 83, 1, 1, 1, "r", now, "Secret"), W.secret("Bia Rocha"), "GUILD")
check(ok and #PL:GetRares() == before, "a secret payload or sender raises nothing and is dropped")
W.deliver("PLRare", wire(1453, 202, 81, 1, 1, 1, "r", now, "Echo"), "GUILD", "Chehul Costa")
check(#PL:GetRares() == before, "my own echo is not a sighting")

for i = 1, 8 do
  W.deliver("PLRare", wire(1454, 404, 90 + i, 1, 1, 0, "r", now, "Spam " .. i), "GUILD", "Spam Mer")
end
check(#PL:GetRares() == before + 6, "one sender gets SENDER_BUDGET sightings a minute, no more")

-- A relayed copy (LibChehulMesh v8+) reaches the handler.
W.advance(61)
now = time()
local relayed = wire(1453, 202, 82, 200, 200, 1, "e", now, "Relayed Rare")
W.deliver("ChehulRelay", "RL1|abc123|2|Far Lister|PLRare|" .. relayed, "WHISPER", "Ivo Near")
local got
for _, r in ipairs(PL:GetRares(1453)) do if r.npcID == 82 then got = r end end
check(got and got.kind == "rareelite" and #prompts == 4, "a sighting relayed through the mesh is taken and prompts")

-- Quiet when the network has it: a hundred players at a world boss send a handful of words.
local function sentFor(npcID)
  local out = {}
  for _, m in ipairs(W.sentWhere({ prefix = "PLRare", dist = "GUILD" })) do
    if W.fields(m.msg)[5] == tostring(npcID) then out[#out + 1] = m end
  end
  return out
end
W.advance(61)
W.sent = {}
W.deliver("PLRare", wire(1453, 101, 91, 500, 500, 1, "r", time(), "Already Told"), "GUILD", "Ana Lima")
W.advance(2)
W.rare("target", 101, 91, "Already Told", "rare")
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
check(#sentFor(91) == 0, "a rare the network told within SEND_GAP: I stay quiet")
W.rare("target", 101, 92, "Told Meanwhile", "rare")
W.fire("PLAYER_TARGET_CHANGED")
W.advance(1)
W.deliver("PLRare", wire(1453, 101, 92, 500, 500, 1, "r", time(), "Told Meanwhile"), "GUILD", "Bia Rocha")
W.advance(16)
check(#sentFor(92) == 0, "someone told it during my wait: I stay quiet")
W.deliver("PLRare", wire(1453, 101, 93, 500, 500, 1, "r", time(), "Now Dead"), "GUILD", "Caio Nunes")
W.rare("target", 101, 93, "Now Dead", "rare", true)
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
local d93 = sentFor(93)
check(#d93 == 1 and W.fields(d93[1].msg)[8] == "0", "a state the network does not have yet (its death) goes out")

-- A clock ahead never outranks what I see.
W.advance(61)
W.deliver("PLRare", wire(1453, 101, 94, 500, 500, 0, "r", time() + 119, "Forged Dead"), "GUILD", "Odd Clock")
W.rare("target", 101, 94, "Forged Dead", "rare")
W.fire("PLAYER_TARGET_CHANGED")
W.advance(16)
local f94 = sentFor(94)
local r94
for _, r in ipairs(PL:GetRares(1453)) do if r.npcID == 94 then r94 = r end end
check(#f94 == 1 and W.fields(f94[1].msg)[8] == "1" and r94.alive and r94.mine,
  "a word dated ahead of the clock: what I see replaces it and goes out")

W.deliver("PLRare", wire(1453, 202, 95, 500, 500, 0, "r", time() + 119, "Honest Later"), "GUILD", "Odd Clock")
W.advance(5)
W.deliver("PLRare", wire(1453, 202, 95, 500, 500, 1, "r", time(), "Honest Later"), "GUILD", "Ana Lima")
local r95
for _, r in ipairs(PL:GetRares(1453)) do if r.npcID == 95 then r95 = r end end
check(r95 and r95.alive, "a word dated ahead counts as now: an honest word a moment later replaces it")

-- Budgets: the peer that whispers a relayed copy, and everyone together.
W.advance(61)
local beforeVia = #PL:GetRares()
for i = 1, 10 do
  local env = wire(1454, 404, 200 + i, 1, 1, 0, "r", time(), "Via " .. i)
  W.deliver("ChehulRelay", "RL1|b" .. i .. "|2|Fake" .. string.char(64 + i) .. " Origin|PLRare|" .. env, "WHISPER",
    "Ivo Near")
end
check(#PL:GetRares() == beforeVia + 6, "relayed copies are budgeted on the peer that whispered them, whatever origin")
W.advance(61)
local beforeAll = #PL:GetRares()
for i = 1, 25 do
  W.deliver("PLRare", wire(1454, 404, 300 + i, 1, 1, 0, "r", time(), "All " .. i), "GUILD",
    "Many" .. string.char(64 + i) .. " Senders")
end
check(#PL:GetRares() == beforeAll + 20, "and everyone together gets GLOBAL_BUDGET a minute")

-- One prompt per PROMPT_GAP; a made-up layer is no layer.
W.advance(61)
local p0 = #prompts
W.deliver("PLRare", wire(1453, 202, 401, 1, 1, 1, "r", time(), "First Pop"), "GUILD", "Pop One")
W.deliver("PLRare", wire(1453, 202, 402, 1, 1, 1, "r", time(), "Second Pop"), "GUILD", "Pop Two")
check(#prompts == p0 + 1 and prompts[#prompts].name == "First Pop", "two rares at once: one prompt (PROMPT_GAP)")
W.deliver("PLRare", wire(1453, 909, 403, 1, 1, 1, "r", time(), "Made Up Layer"), "GUILD", "Pop Three")
local fake = false
for _, r in ipairs(PL:GetLayers()) do fake = fake or r.zoneUID == 909 end
check(not fake, "a rare on a layer I never saw (and nobody announced) adds no layer")
local changes = 0
PL:On("RARES_CHANGED", function() changes = changes + 1 end)
W.rare("target", 101, 61, "Mor'Ladim", "rare")
W.fire("PLAYER_TARGET_CHANGED")
W.fire("PLAYER_TARGET_CHANGED")
local c1 = changes
W.fire("PLAYER_TARGET_CHANGED")
check(changes == c1, "looking at the same rare again changes nothing (no redraw)")

W.advance(16 * 60)
check(#PL:GetRares() == 0, "sightings go after FRESH")

W.done("rares")
