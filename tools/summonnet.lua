-- Summons across the realm, against the real modules and mesh (tools/wowstub.lua): an ask goes to the network
-- (GUILD, group, realm) and again while open; a warlock of level 20 and up who offers summons gets one prompt per
-- ask and offers with a click (a whisper to the asker); the asker sees each offer once and invites from a click.
-- Anything out of shape, stale, ahead of the clock, past a sender's budget or past a warlock's prompt budget is
-- dropped; an offer counts only whispered and only for my open ask.
--
--   luajit tools/summonnet.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local function ask(id, level, class, seen, dest)
  return table.concat({ "PLS1", "Q", id, level, class, seen, dest }, "|")
end

-- ── the asker: Chehul Costa, a level 30 paladin ───────────────────────────
local PL = W.boot({})
W.directory({ "Zed One", "Yan Two", "Xia Three" })
W.advance(6)
local offers = {}
PL:On("SUMMON_OFFER", function(o) offers[#offers + 1] = o end)
check(not PL:IsSummoner(), "a paladin offers no summons")
check(select(2, PL:AskSummon("  ")) == "empty", "an ask needs a place")
W.instance = true
check(select(2, PL:AskSummon("Blackrock Depths")) == "cannot_send", "nothing from inside an instance")
W.instance = false
W.sent = {}
check(PL:AskSummon("Blackrock Depths"), "asking for a summon to Blackrock Depths")
W.advance(3)
local g = W.sentWhere({ prefix = "PLSum", dist = "GUILD" })
local f = g[1] and W.fields(g[1].msg)
check(#g == 1 and f[1] == "PLS1" and f[2] == "Q" and f[3]:match("^%x+$") and f[4] == "30" and f[5] == "PALADIN"
  and f[7] == "Blackrock Depths", "the ask goes on GUILD: id, my level and class, server time, the place")
local id = f[3]
check(select(2, PL:AskSummon("Molten Core")) == "pending", "one ask at a time")
local my = PL:GetSummonAsk()
check(my.state == "open" and my.dest == "Blackrock Depths" and #my.offers == 0, "my ask is open, no offer yet")
W.advance(30)
check(#W.sentWhere({ prefix = "PLSum", dist = "WHISPER" }) >= 1, "the realm copy goes by whisper to the directory")

W.sent = {}
W.advance(120)
check(#W.sentWhere({ prefix = "PLSum", dist = "GUILD" }) == 1, "while open, the ask goes again every RESEND")

W.deliver("PLSum", "PLS1|O|" .. id .. "|Searing Gorge", "WHISPER", "Wally Lock")
check(#offers == 1 and offers[1].name == "Wally Lock" and offers[1].zone == "Searing Gorge",
  "a warlock's whispered offer: a prompt with who and where")
W.deliver("PLSum", "PLS1|O|" .. id .. "|Searing Gorge", "WHISPER", "Wally Lock")
check(#offers == 1 and #PL:GetSummonAsk().offers == 1, "the same warlock again: no second prompt")
W.deliver("PLSum", "PLS1|O|" .. id .. "|Burning Steppes", "GUILD", "Gus Lock")
W.deliver("PLSum", "PLS1|O|ffff|Burning Steppes", "WHISPER", "Gus Lock")
W.deliver("PLSum", "PLS1|O|" .. id .. "|Bad\7Zone", "WHISPER", "Gus Lock")
W.deliver("PLSum", "PLS1|O|" .. id .. "|" .. string.rep("z", 41), "WHISPER", "Gus Lock")
W.deliver("PLSum", "PLS1|O|" .. id .. "|Zone|Extra", "WHISPER", "Gus Lock")
check(#offers == 1, "an offer not whispered, for another ask, or out of shape counts for nothing")

W.sent = {}
check(W.click(PL.AcceptSummonOffer, PL, offers[1]) and W.invites[1] == "Wally Lock" and #W.violations == 0,
  "Invite: the warlock is invited from the click")
check(PL:GetSummonAsk().offers[1].state == "invited", "and the offer says so")
W.setGroup({ { name = "Bia", surname = "Rocha" } })
W.group.leader = false
check(select(2, PL:AcceptSummonOffer(offers[1])) == "cannot_invite", "not the leader: no invite")
W.group.leader = true
W.setGroup({})

W.sent = {}
PL:CancelSummonAsk()
W.advance(3)
g = W.sentWhere({ prefix = "PLSum", dist = "GUILD" })
check(#g == 1 and g[1].msg:match("^PLS1|X|" .. id .. "|%d+$") and PL:GetSummonAsk().state == "cancelled",
  "taking the ask back tells the network")
W.deliver("PLSum", "PLS1|O|" .. id .. "|Searing Gorge", "WHISPER", "Late Lock")
check(#offers == 1, "an offer after that counts for nothing")

check(PL:AskSummon("Molten Core"), "a new ask")
W.advance(10 * 60 + 30)
check(PL:GetSummonAsk().state == "expired", "an ask nobody took ends after ASK_TTL")

-- ── the warlock: a level 40 warlock offering summons ──────────────────────
PL = W.boot({ class = "WARLOCK", level = 40 })
W.directory({ "Zed One" })
W.advance(6)
local asks = {}
PL:On("SUMMON_REQUEST", function(r) asks[#asks + 1] = r end)
check(PL:IsSummoner(), "a level 40 warlock offers summons (the default)")
local now = time()
W.deliver("PLSum", ask("a1b2", 28, "MAGE", now, "Blackrock Depths"), "GUILD", "Ana Lima-ClassicBetaPvE2")
check(#asks == 1 and asks[1].name == "Ana Lima" and asks[1].dest == "Blackrock Depths" and asks[1].level == 28
  and asks[1].classFile == "MAGE", "an ask heard: a prompt with who, where to and their level")
W.deliver("PLSum", ask("a1b2", 28, "MAGE", now + 120, "Blackrock Depths"), "GUILD", "Ana Lima")
check(#asks == 1 and #PL:GetSummonRequests() == 1, "the same ask repeated: no second prompt")

W.sent = {}
check(W.click(PL.OfferSummon, PL, asks[1]), "Offer, from a click")
W.advance(3)
local o = W.sentWhere({ prefix = "PLSum", dist = "WHISPER", target = "Ana Lima" })
check(#o == 1 and o[1].msg == "PLS1|O|a1b2|Searing Gorge", "the offer is whispered to the asker with where I am")
check(select(2, PL:OfferSummon(asks[1])) == "gone", "one offer per ask")
W.deliver("PLSum", "PLS1|X|a1b2|" .. now, "GUILD", "Ana Lima")
check(#PL:GetSummonRequests() == 0, "the asker took it back: off my list")

W.deliver("PLSum", ask("c3", 30, "ROGUE", now, "Zul'Farrak"), "GUILD", "Bia Rocha")
check(#asks == 2, "another ask, another prompt")
PL:IgnoreSummonRequest(asks[2])
check(#PL:GetSummonRequests() == 0, "Ignore takes it off the list")

local before = #PL:GetSummonRequests()
local bad = {
  ask("d4", 0, "ROGUE", now, "Too Low"),
  ask("d4", 30, "ROGUE", now + 600, "Ahead"),
  ask("d4", 30, "ROGUE", now - 11 * 60, "Too Old"),
  ask("zz", 30, "ROGUE", now, "Bad Id"),
  ask("d4", 30, "rogue", now, "Bad Class"),
  ask("d4", 30, "ROGUE", now, string.rep("y", 41)),
  ask("d4", 30, "ROGUE", now, "Bell\7Place"),
  ask("d4", 30, "ROGUE", now, "Place") .. "|extra",
  "PLS1|Q|d4|30|ROGUE|" .. now,
}
for _, m in ipairs(bad) do W.deliver("PLSum", m, "GUILD", "Odd Sender") end
check(#PL:GetSummonRequests() == before and #asks == 2, "anything out of shape is dropped")
W.deliver("PLSum", ask("e5", 30, "ROGUE", now, "Mine"), "GUILD", "Chehul Costa")
check(#PL:GetSummonRequests() == before, "my own echo is no ask")
local handler = _G.ChehulMesh.handlers.PLSum
local ok = pcall(handler, W.secret(ask("e6", 30, "ROGUE", now, "Secret")), "Bia Rocha", "GUILD")
ok = ok and pcall(handler, ask("e6", 30, "ROGUE", now, "Secret"), W.secret("Bia Rocha"), "GUILD")
check(ok and #PL:GetSummonRequests() == before, "a secret payload or sender raises nothing")

for i = 1, 6 do
  W.deliver("PLSum", ask("f" .. i, 30, "ROGUE", now, "Spam " .. i), "GUILD", "Spam Mer")
end
local spam = 0
for _, r in ipairs(PL:GetSummonRequests()) do if r.name == "Spam Mer" then spam = spam + 1 end end
check(spam == 4, "one sender gets SENDER_BUDGET asks a minute")
check(#asks == 3, "and a warlock PROMPT_BUDGET prompts a minute (two shown already this minute)")

-- Relayed through the mesh: the claimed asker is who the offer goes to.
W.advance(61)
W.deliver("ChehulRelay", "RL1|abc|2|Far Asker|PLSum|" .. ask("1a", 33, "PRIEST", time(), "Maraudon"), "WHISPER",
  "Ivo Near")
check(#asks == 4 and asks[4].name == "Far Asker" and asks[4].dest == "Maraudon", "a relayed ask prompts too")

W.instance = true
W.deliver("PLSum", ask("2b", 33, "PRIEST", time(), "Inside"), "GUILD", "Inner Asker")
W.instance = false
check(#asks == 4, "no prompt inside an instance")
PL.db.summonNet.offer = false
W.deliver("PLSum", ask("3c", 33, "PRIEST", time(), "Off"), "GUILD", "Off Asker")
check(#asks == 4 and #PL:GetSummonRequests() == 0 and not PL:IsSummoner(),
  "with offering off: no prompt, no list")
PL.db.summonNet.offer = true

PL = W.boot({ class = "WARLOCK", level = 19 })
asks = {}
PL:On("SUMMON_REQUEST", function(r) asks[#asks + 1] = r end)
W.deliver("PLSum", ask("4d", 30, "ROGUE", time(), "Low Lock"), "GUILD", "Bia Rocha")
check(#asks == 0 and not PL:IsSummoner(), "a warlock below 20 (no ritual yet) gets no prompt")

-- Budgets: the peer that whispers relayed copies, and everyone together.
PL = W.boot({ class = "WARLOCK", level = 40 })
W.advance(61)
local relayedFrom = 0
for i = 1, 8 do
  W.deliver("ChehulRelay", "RL1|c" .. i .. "|2|Fake" .. string.char(64 + i) .. " Asker|PLSum|"
    .. ask("5" .. i, 33, "PRIEST", time(), "Relay " .. i), "WHISPER", "Ivo Near")
end
for _, r in ipairs(PL:GetSummonRequests()) do if r.dest:find("^Relay ") then relayedFrom = relayedFrom + 1 end end
check(relayedFrom == 4, "relayed asks are budgeted on the peer that whispered them, whatever origin they claim")
W.advance(61)
local taken = {}
PL:On("SUMMON_CHANGED", function() end)
for i = 1, 16 do
  W.deliver("PLSum", ask("6" .. string.format("%x", i), 33, "PRIEST", time(), "All " .. i), "GUILD",
    "Many" .. string.char(64 + i) .. " Askers")
end
for _, r in pairs(PL.summonNet.inbound) do if r.dest:find("^All ") then taken[#taken + 1] = r end end
check(#taken == 12, "and everyone together gets GLOBAL_BUDGET asks a minute")

-- Repeats are free; a relayed take-back counts for nothing; one prompt per asker; relayed asks prompt rarely;
-- blocked players are skipped; a newer ask reopens a take-back.
PL = W.boot({ class = "WARLOCK", level = 40 })
asks = {}
PL:On("SUMMON_REQUEST", function(r) asks[#asks + 1] = r end)
W.advance(61)
for i = 1, 6 do
  W.deliver("PLSum", ask("7" .. i, 30, "ROGUE", time(), "Rep " .. i), "GUILD", "Rep" .. string.char(64 + i) .. " Asker")
  W.deliver("PLSum", ask("7" .. i, 30, "ROGUE", time(), "Rep " .. i), "GUILD", "Rep" .. string.char(64 + i) .. " Asker")
end
W.deliver("PLSum", ask("78", 30, "ROGUE", time(), "Seventh"), "GUILD", "Seventh Asker")
local seventh = false
for _, r in pairs(PL.summonNet.inbound) do seventh = seventh or r.dest == "Seventh" end
check(seventh, "a repeated ask costs no budget: a new one still gets through")
W.deliver("ChehulRelay", "RL1|d1|2|RepA Asker|PLSum|PLS1|X|71|" .. time(), "WHISPER", "Griefer Guy")
local still = false
for _, r in ipairs(PL:GetSummonRequests()) do still = still or r.id == "71" end
check(still, "a take-back that came relayed (its asker only a claim) counts for nothing")
W.deliver("PLSum", "PLS1|X|72|" .. time(), "GUILD", "RepB Asker")
W.advance(5)
W.deliver("PLSum", ask("72", 30, "ROGUE", time(), "Rep 2"), "GUILD", "RepB Asker")
local reopened = false
for _, r in ipairs(PL:GetSummonRequests()) do reopened = reopened or r.id == "72" end
check(reopened, "a newer copy of an ask taken back reopens it")
W.deliver("PLSum", "PLS1|X|73|" .. time(), "GUILD", "RepC Asker")
W.advance(5)
W.deliver("ChehulRelay", "RL1|f1|2|RepC Asker|PLSum|" .. ask("73", 30, "ROGUE", time(), "Rep 3"), "WHISPER",
  "Griefer Guy")
local undone = false
for _, r in ipairs(PL:GetSummonRequests()) do undone = undone or r.id == "73" end
check(not undone, "a relayed copy (asker only a claim) never undoes a take-back")
local r74
for _, r in pairs(PL.summonNet.inbound) do if r.id == "74" then r74 = r end end
local seen74 = r74.seen
W.deliver("ChehulRelay", "RL1|f2|2|RepD Asker|PLSum|" .. ask("74", 30, "ROGUE", time() + 60, "Rep 4"), "WHISPER",
  "Griefer Guy")
check(r74.seen == seen74, "nor keeps anyone's ask fresh")
W.advance(61) -- a fresh prompt budget: only the per-asker rule can hold it back
local n0 = #asks
W.deliver("PLSum", ask("79", 30, "ROGUE", time(), "Again"), "GUILD", "RepA Asker")
check(#asks == n0, "one prompt per asker per ASK_TTL, whatever new ids they send")
W.advance(61)
n0 = #asks
W.deliver("ChehulRelay", "RL1|e1|2|RelayOne Asker|PLSum|" .. ask("81", 30, "ROGUE", time(), "R1"), "WHISPER", "Ivo Near")
W.deliver("ChehulRelay", "RL1|e2|2|RelayTwo Asker|PLSum|" .. ask("82", 30, "ROGUE", time(), "R2"), "WHISPER", "Uma Near")
check(#asks == n0 + 1, "relayed asks prompt once per RELAY_PROMPT_GAP")
PL.db.blacklist["blocked asker"] = "Blocked Asker"
W.deliver("PLSum", ask("83", 30, "ROGUE", time(), "Blocked"), "GUILD", "Blocked Asker")
local blocked = false
for _, r in pairs(PL.summonNet.inbound) do blocked = blocked or r.dest == "Blocked" end
check(not blocked, "a blocked player's ask is dropped")
W.deliver("PLSum", ask("84", 30, "ROGUE", time() + 100, "Ahead"), "GUILD", "Clock Asker")
local ahead
for _, r in pairs(PL.summonNet.inbound) do if r.dest == "Ahead" then ahead = r end end
check(ahead and ahead.seen <= time(), "an ask dated ahead counts as now")

W.done("summonnet")
