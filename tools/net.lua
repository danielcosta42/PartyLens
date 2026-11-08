-- PartyLens listings on the network, against the real modules, AceComm, ChatThrottleLib and LibChehulMesh
-- (tools/wowstub.lua): a listing goes out on GUILD, the group and the mesh's directory, never SAY or YELL (Forever
-- refuses both); it repeats every 60 s; a listing heard is relayed once, with a hop limit and a seen-cache;
-- nothing leaves from an instance or a chat lockdown; a stopped listing tells the network.
--
--   luajit tools/net.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local OURS = { PartyLens = true, PLLnet = true }

-- Every call to the mesh's SAY/YELL buses, whatever the mesh does with it.
local function spy()
  local calls = {}
  local mesh = _G.ChehulMesh
  for _, bus in ipairs({ "Proximity", "Yell" }) do
    local orig = mesh[bus]
    mesh[bus] = function(self, prefix, ...)
      calls[#calls + 1] = { bus = bus, prefix = prefix }
      return orig(self, prefix, ...)
    end
  end
  return calls
end

local function ours(filter)
  local out = {}
  for _, m in ipairs(W.sentWhere(filter)) do
    if OURS[m.prefix] then out[#out + 1] = m end
  end
  return out
end

local function noSayYell(calls, what)
  for _, c in ipairs(calls) do
    check(not OURS[c.prefix], what .. ": PartyLens asked the mesh for " .. c.bus)
  end
  check(#ours({ dist = "SAY" }) == 0 and #ours({ dist = "YELL" }) == 0, what .. ": nothing of ours on SAY or YELL")
end

local DIR = { "Zed One", "Yan Two", "Xia Three", "Wil Four", "Val Five" }

-- ── sending ────────────────────────────────────────────────────────────────
local PL = W.boot({})
local calls = spy()
W.directory(DIR)
W.setGroup({ { name = "Gil", surname = "Paz", class = "PRIEST" } })
W.click(PL.StartListing, PL, { type = "lfm", activity = "rol", comment = "chill run | no rush" })
W.advance(30)
local guild = ours({ prefix = "PartyLens", dist = "GUILD" })
local party = ours({ prefix = "PartyLens", dist = "PARTY" })
local wide = ours({ prefix = "PartyLens", dist = "WHISPER" })
check(#guild == 1 and #party == 1, "the listing went out on GUILD and the group")
check(#wide == 3, "and through the directory, to three of its members (got " .. #wide .. ")")
local f = W.fields(guild[1].msg)
check(f[1] == "2" and f[2] == "lfm" and f[5] == "rol" and f[14] == "0" and f[15] == "Chehul Costa",
  "protocol 2, lfm, the activity key, hop 0, me as origin by full name")
check(f[11] == "0.1.1" and f[12] == "1.1.3", "filled and wanted per role (me dps, the priest a healer)")
check(f[3] == "tank+dps", "the roles still missing")
check(f[16] == "chill run / no rush", "the comment, with the field separator out")
local seq = tonumber(f[13])
check(math.abs(seq - GetServerTime()) <= 31, "its version is the server time of the change")
noSayYell(calls, "start")

W.advance(61)
local again = ours({ prefix = "PartyLens", dist = "GUILD" })
check(#again == 2 and W.fields(again[2].msg)[13] == tostring(seq), "a heartbeat a minute later, same version")

PL:SetListing({ comment = "need a real tank" })
W.advance(2)
again = ours({ prefix = "PartyLens", dist = "GUILD" })
check(tonumber(W.fields(again[#again].msg)[13]) > seq, "a change goes out at once with a higher version")
seq = tonumber(W.fields(again[#again].msg)[13])

W.setGroup({ { name = "Gil", surname = "Paz", class = "PRIEST" }, { name = "Hugo", surname = "Luz", class = "WARRIOR" } })
W.advance(2)
again = ours({ prefix = "PartyLens", dist = "GUILD" })
local last = W.fields(again[#again].msg)
check(tonumber(last[13]) > seq and last[3] == "dps" and last[11] == "1.1.1",
  "a tank joining changes what is missing, and the network hears it")

W.click(PL.StopListing, PL)
W.advance(2)
again = ours({ prefix = "PartyLens", dist = "GUILD" })
check(W.fields(again[#again].msg)[2] == "off", "stopping tells the network to drop it")
local count = #ours({ prefix = "PartyLens", dist = "GUILD" })
W.advance(200)
check(#ours({ prefix = "PartyLens", dist = "GUILD" }) == count, "and the heartbeat stops")
noSayYell(calls, "heartbeats and stop")

-- ── the visible LFG post ───────────────────────────────────────────────────
PL = W.boot({})
PL:SetListing({ type = "lfm", activity = "rol", comment = "fast" })
check(PL:BuildPost() == "LFM Ruins of Lordaeron, need Tank/Healer/DPS - fast", "the post is built from the draft")
check(W.click(PL.PostLFG, PL), "posting from a click")
check(#W.chat == 1 and W.chat[1].chatType == "CHANNEL" and W.chat[1].target == 4
  and W.chat[1].msg == "[PartyLens]: LFM Ruins of Lordaeron, need Tank/Healer/DPS - fast",
  "a signed line in the LookingForGroup channel, by its number")
check(PL:GetListing().active, "and the listing starts on the network with it")
check(select(2, W.click(PL.PostLFG, PL)) == "cooldown" and #W.chat == 1, "a second post within 15 s is held back")
W.advance(16)
check(W.click(PL.PostLFG, PL) and #W.chat == 2, "and goes once the gap is over")
W.click(PL.StopListing, PL)
PL:SetListing({ type = "lfg", activity = "dalaran", comment = "" })
W.advance(16)
W.click(PL.PostLFG, PL)
check(W.chat[3].msg == "[PartyLens]: LFG City of Dalaran, DPS level 30", "an lfg post says my roles and level")
W.channels.LookingForGroup = nil
W.advance(16)
check(select(2, W.click(PL.PostLFG, PL)) == "no_channel" and W.joined[#W.joined] == "LookingForGroup" and #W.chat == 3,
  "without the channel nothing is posted and the channel is joined")
W.channels.LookingForGroup = 4
PL:PostLFG()
check(W.violations[1] and W.violations[1].fn == "SendChatMessage", "posting outside a click is blocked")
W.violations = {}

-- ── an unchanged listing keeps a fresh version ─────────────────────────────
PL = W.boot({})
W.click(PL.StartListing, PL, { activity = "rol" })
W.advance(2)
local first = tonumber(W.fields(ours({ prefix = "PartyLens", dist = "GUILD" })[1].msg)[13])
W.advance(4 * 60)
local list = ours({ prefix = "PartyLens", dist = "GUILD" })
check(tonumber(W.fields(list[#list].msg)[13]) == first, "heartbeats repeat the version for a while")
W.advance(2 * 60)
list = ours({ prefix = "PartyLens", dist = "GUILD" })
local refreshed = tonumber(W.fields(list[#list].msg)[13])
check(refreshed > first and GetServerTime() - refreshed < 61,
  "and renew it every 5 minutes, so receivers never take it for a stale one")

-- ── instance and lockdown ──────────────────────────────────────────────────
PL = W.boot({})
calls = spy()
W.directory(DIR)
W.instance = true
W.click(PL.StartListing, PL, { activity = "dalaran" })
W.advance(130)
check(#ours({}) == 0, "inside an instance nothing of ours leaves, start or heartbeat")
W.instance = false
W.lockdown = true
W.advance(61)
check(#ours({}) == 0, "nor during a chat lockdown")
W.lockdown = false
W.advance(61)
check(#ours({ prefix = "PartyLens", dist = "GUILD" }) == 1, "and out of both it resumes")

-- ── receiving and relaying ─────────────────────────────────────────────────
PL = W.boot({})
calls = spy()
W.directory(DIR)
-- seq is the lister's server time at the change; S(n) is a version n seconds after T0 - 1000.
local T0 = GetServerTime()
local function S(n) return T0 - 1000 + n end
local function listing(origin, seq, hops, kind, extra, filled)
  local fields = { "2", kind or "lfm", "tank+heal", "dungeon", "thanes", "0", "WARRIOR", "34", "202", "1453",
    filled or "1.0.2", "1.1.3", tostring(seq), tostring(hops), origin, extra or "fast run" }
  return table.concat(fields, "|")
end
local function relays()
  local n = {}
  for _, m in ipairs(ours({ prefix = "PartyLens", dist = "WHISPER" })) do n[#n + 1] = W.fields(m.msg) end
  return n
end

W.deliver("PartyLens", listing("Ana Lima", S(500), 0), "WHISPER", "Ana Lima-ClassicBetaPvE2")
local ana = PL.entries["ana lima"]
check(ana and ana.source == "net" and ana.isAddonUser and ana.type == "lfm", "a listing is a PartyLens entry")
check(ana.activity == "The Hall of Thanes" and ana.roles.tank and ana.roles.heal and not ana.roles.dps,
  "with its activity by key and the roles it needs")
check(ana.filled == 3 and ana.max == 5 and ana.comp.t == 1 and ana.comp.dMax == 3 and ana.open,
  "its fill and composition")
check(ana.classFile == "WARRIOR" and ana.level == 34 and ana.mapID == 1453 and ana.zoneUID == 202,
  "its class, level and layer")
check(ana.message:find("fast run", 1, true) ~= nil, "and its comment")
W.advance(30)
local r = relays()
check(#r == 3 and r[1][14] == "1" and r[1][15] == "Ana Lima", "relayed through the directory once, hop 1, origin kept")

W.deliver("PartyLens", listing("Ana Lima", S(500), 0), "WHISPER", "Ana Lima")
W.deliver("PartyLens", listing("Ana Lima", S(500), 1), "WHISPER", "Yan Two")
W.advance(30)
check(#relays() == 3, "the same version again, from her or relayed, is not relayed again")

W.deliver("PartyLens", listing("Ana Lima", S(400), 0, nil, nil, "0.0.1"), "WHISPER", "Ana Lima")
check(PL.entries["ana lima"].filled == 3, "an older version is ignored")

W.channelLine("LFG anything, heal", "Ana Lima", "")
ana = PL.entries["ana lima"]
check(ana.type == "lfm" and ana.activityKey == "thanes" and ana.roles.tank and ana.message == "LFG anything, heal",
  "her chat line updates the message, not what her live listing says")

W.deliver("PartyLens", listing("Bia Rocha", S(600), 2), "WHISPER", "Zed One")
W.advance(30)
check(PL.entries["bia rocha"] ~= nil and #relays() == 3, "a listing at the hop limit is shown, not relayed")

W.deliver("PartyLens", listing("Ana Lima", S(501), 1), "WHISPER", "Zed One")
W.advance(30)
r = relays()
check(#r == 6 and r[6][14] == "2" and r[6][13] == tostring(S(501)), "a new version is relayed once more, hop 2")

-- Nothing in a message is trusted beyond its shape.
for _, bad in ipairs({ "-1000", "-1", "3", "1.5", "inf", "nan", "x", "" }) do
  local name = "Hops " .. (bad:gsub("%W", "")) .. "z"
  W.deliver("PartyLens", listing(name, S(650), bad), "WHISPER", "Zed One")
  check(PL.entries[name:lower()] == nil, "a hops of '" .. bad .. "' drops the message")
end
W.advance(30)
check(#relays() == 6, "and nothing of them was relayed")
local now = GetServerTime()
for _, bad in ipairs({ "inf", "1e300", "nan", "-inf", "12.5", tostring(now + 121), tostring(now - 15 * 60 - 1),
  "" }) do
  W.deliver("PartyLens", listing("Gil Paz", bad, 2), "WHISPER", "Evil Guy")
  check(PL.entries["gil paz"] == nil, "a seq of '" .. bad .. "' drops the message")
end
W.deliver("PartyLens", listing("Gil Paz", now, 0), "WHISPER", "Gil Paz")
check(PL.entries["gil paz"] ~= nil, "so a made-up seq cannot lock the real lister out")
W.deliver("PartyLens", listing("Gil Paz", now + 1, 1, "off"), "WHISPER", "Evil Guy")
W.deliver("PartyLens", listing("Gil Paz", now + 1, 0, "off"), "GUILD", "Evil Guy")
check(PL.entries["gil paz"] ~= nil and PL.entries["gil paz"].netAt ~= nil,
  "a stop from anybody but the lister, relayed or not, is ignored")

local Comm = _G.PartyLens_Comm
Comm.GUILD_RELAY_CHANCE = 0
W.deliver("PartyLens", listing("Caio Nunes", S(700), 0), "GUILD", "Caio Nunes")
W.advance(30)
local base = #relays()
check(PL.entries["caio nunes"] ~= nil and base == 9, "a guildmate's listing, heard on GUILD, is not always relayed")
Comm.GUILD_RELAY_CHANCE = 1
W.deliver("PartyLens", listing("Davi Melo", S(700), 0), "GUILD", "Davi Melo")
W.advance(30)
check(#relays() == base + 3, "but sometimes is")

W.deliver("PartyLens", listing("Chehul Costa", S(900), 0), "GUILD", "Chehul Costa")
check(PL.entries["chehul costa"] == nil, "my own listing echoed on GUILD is not an entry")

W.deliver("PartyLens", listing("Ana Lima", S(502), 0, "off"), "WHISPER", "Ana Lima-ClassicBetaPvE2")
ana = PL.entries["ana lima"]
check(ana and ana.source == "chat" and ana.netAt == nil, "her own stop drops the listing; her chat line keeps a chat row")
W.advance(30)
check(#relays() == base + 3, "and a stop is never relayed: copies that missed it age out")
Comm.GUILD_RELAY_CHANCE = 0
W.deliver("PartyLens", listing("Caio Nunes", S(701), 0, "off"), "GUILD", "Caio Nunes")
check(PL.entries["caio nunes"] == nil, "with nothing else of his, a stopped listing leaves the radar at once")

W.instance = true
W.deliver("PartyLens", listing("Elza Dias", S(800), 0), "WHISPER", "Elza Dias")
W.advance(30)
check(PL.entries["elza dias"] ~= nil and #relays() == base + 3, "inside an instance a listing is still shown, not relayed")
W.instance = false
W.advance(30)
check(#relays() == base + 3, "nor later: it was never queued")

-- Straight to the mesh's handler: AceComm itself reads the payload before anything of ours does.
local handler = _G.ChehulMesh.handlers.PartyLens
local ok = pcall(handler, W.secret(listing("Fabi Reis", S(990), 0)), "Fabi Reis", "WHISPER")
check(ok and PL.entries["fabi reis"] == nil, "a secret payload is dropped without an error")
ok = pcall(handler, listing("Fabi Reis", S(990), 0), W.secret("Fabi Reis"), "WHISPER")
check(ok and PL.entries["fabi reis"] == nil, "and so is a secret sender")
W.deliver("PartyLens", "1|lfm|tank|dungeon|kara|0|", "GUILD", "Old Client")
check(PL.entries["old client"] == nil, "an Anniversary (protocol 1) message is not ours")

W.advance(4 * 60)
check(PL.entries["bia rocha"] == nil, "a listing not heard for 3 minutes expires")

-- A burst of new listings takes a bounded share of the mesh's shared realm queue.
for i = 1, 20 do
  W.deliver("PartyLens", listing("Burst " .. string.char(64 + i) .. "x", GetServerTime() - i, 0), "WHISPER", "Zed One")
end
local slots = 0
for key in pairs(_G.ChehulMesh._realmQueue) do
  if key:find("^PartyLens	") then slots = slots + 1 end
end
check(slots >= 1 and slots <= Comm.RELAY_SLOTS, "20 relays wait in at most " .. Comm.RELAY_SLOTS .. " queue slots (" .. slots .. ")")

noSayYell(calls, "receiving")
check(#W.violations == 0 and #W.errors == 0, "nothing protected ran and nothing raised")

W.done("net")
