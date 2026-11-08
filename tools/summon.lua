-- Warlock summon help, against the real modules (tools/wowstub.lua): who is far (UnitInRange answers only secrets
-- on 12.x, so the squared distance decides), the warlocks near, the marks, and the announce, from a click only.
--
--   luajit tools/summon.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local PL = W.boot({})
check(not PL:GetSummon().inGroup and select(2, W.click(PL.AnnounceSummon, PL, "all")) == "not_in_group",
  "alone there is nobody to summon and nothing to announce")

local changes = 0
PL:On("SUMMON_CHANGED", function() changes = changes + 1 end)
W.setGroup({
  { name = "Ana", surname = "Lima", class = "DRUID", dist = 10 },
  { name = "Bia", surname = "Rocha", class = "MAGE", dist = 300 },
  { name = "Caio", surname = "Nunes", class = "PRIEST", visible = false },
  { name = "Davi", surname = "Melo", class = "WARLOCK", dist = 5 },
})
check(changes == 1, "a roster change is a SUMMON_CHANGED")
local s = PL:GetSummon()
check(s.inGroup and #s.members == 5, "me and four groupmates")
check(#s.needed == 2 and s.needed[1] == "Bia Rocha" and s.needed[2] == "Caio Nunes",
  "the far one and the one the client cannot see need a summon, by full name")
check(#s.warlocks == 1 and s.warlocks[1] == "Davi Melo", "the warlock nearby can open the ritual")

PL:AnnounceSummon("all")
check(#W.chat == 0 and W.violations[1].fn == "SendChatMessage", "announcing outside a click is blocked")
W.violations = {}
W.click(PL.AnnounceSummon, PL, "all")
check(W.chat[1].chatType == "PARTY" and W.chat[1].msg == "[PartyLens]: summon needed — Bia Rocha, Caio Nunes",
  "from a click, the list goes to party chat")
PL:MarkSummoned("Bia Rocha", true)
check(changes == 2 and #PL:GetSummon().needed == 1, "marking one summoned takes it off")
W.click(PL.AnnounceSummon, PL, "next")
check(W.chat[2].msg == "[PartyLens]: summoning Caio Nunes next — to the stone!", "'next' names the next one")
PL:MarkSummoned("Caio Nunes", true)
W.click(PL.AnnounceSummon, PL, "next")
check(W.chat[3].msg == "[PartyLens]: everyone is here, no summons needed.", "and then everyone is here")

W.setGroup({ { name = "Ana", surname = "Lima", class = "DRUID", dist = 10 },
  { name = "Elza", surname = "Dias", class = "MAGE", dist = 500 } }, true)
check(#PL:GetSummon().members == 3 and PL:GetSummon().needed[1] == "Elza Dias", "a raid's units are read too")
W.click(PL.AnnounceSummon, PL, "all")
check(W.chat[4].chatType == "RAID", "and the list goes to raid chat")
W.setGroup({})
check(PL.summonMarked == nil, "leaving the group forgets the marks")
check(#W.violations == 0 and #W.errors == 0, "nothing else protected ran and nothing raised")

W.done("summon")
