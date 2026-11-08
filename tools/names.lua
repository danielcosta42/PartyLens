-- Names on WoW: Forever ("First Surname"), against the real modules (tools/wowstub.lua): how the client knows
-- itself, the key and the target every whisper, invite and /who uses, a group unit that gives the first name
-- alone; and the fresh Forever save (an older schema is wiped).
--
--   luajit tools/names.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local PL = W.boot({})
local U = _G.PartyLens_Utils

-- ── who I am ───────────────────────────────────────────────────────────────
check(U.MyName() == "Chehul Costa", "MyName is first name and surname, as every sender arrives")
check(U.IsMe("Chehul Costa") and U.IsMe("Chehul Costa-ClassicBetaPvE2") and U.IsMe("chehul costa"),
  "I know myself with or without the realm, in any case")
check(not U.IsMe("Chehul") and not U.IsMe("Chehul Druida"), "the first name alone, or a namesake, is not me")
W.units.player.name = W.secret("Chehul")
local ok, me = pcall(U.MyName)
check(ok and me == "", "a secret own name gives an empty name, not an error")
W.units.player.name = "Chehul"

PL = W.boot({ surname = false })
U = _G.PartyLens_Utils
check(U.MyName() == "Chehul", "with no surname to show, UnitName")

PL = W.boot({})
U = _G.PartyLens_Utils

-- ── spelling and keys ──────────────────────────────────────────────────────
check(U.FullName("Ana Lima-ClassicBetaPvE2") == "Ana Lima", "First Surname-Realm is whispered as First Surname")
check(U.FullName("Ana Lima-OtherHome") == "Ana Lima", "from another home server too: the Name-Realm form never arrives")
check(U.FullName("Bob-ClassicBetaPvE2") == "Bob", "a surnameless name on my realm loses the realm")
check(U.FullName("Bob-OtherRealm") == "Bob-OtherRealm", "and keeps a foreign one, which reaching it needs")
check(U.NameKey("Ana Lima-ClassicBetaPvE2") == "ana lima", "the key is the lowercase full name")
check(U.FullName(W.secret("Ana Lima")) == nil and U.NameKey(W.secret("x")) == nil, "a secret name is no name")
check(U.SameName("Ana", "Ana Lima") and U.SameName("Ana Lima", "ana lima-ClassicBetaPvE2"),
  "a first name alone matches the full name (a group unit may give just that)")
check(not U.SameName("Ana Lima", "Ana Rocha"), "two surnames that differ are two people")

-- ── targets ────────────────────────────────────────────────────────────────
W.channelLine("LFM RoL need dps", "Ana Lima-ClassicBetaPvE2", "")
local ana = PL.entries["ana lima"]
W.click(PL.Whisper, PL, ana)
check(#W.chat == 1 and W.chat[1].chatType == "WHISPER" and W.chat[1].target == "Ana Lima",
  "a whisper goes to First Surname")
check(W.chat[1].msg:find("^%[PartyLens%]: Hi Ana! ") ~= nil, "signed, and greets her by first name")
check(ana.contacted == "whisper", "the entry remembers the whisper")
W.click(PL.Invite, PL, ana)
check(W.invites[1] == "Ana Lima" and ana.contacted == "invite", "an invite goes to First Surname")
W.click(PL.Who, PL, ana)
check(W.whos[1] == "x-Ana-Lima", "/who is exact, built as Forever's own UI builds it")
check(select(2, W.click(PL.Who, PL, ana)) == "throttled", "a second /who within 3 s is held back")
W.click(PL.OpenWhisper, PL, ana)
check(W.tells[1] == "Ana Lima" and W.inserted and W.inserted:find("Hi Ana!", 1, true),
  "the edit box opens on the full name, never '/w First Surname'")
W.who = { { fullName = "Ana Lima", level = 34, filename = "DRUID" } }
W.fire("WHO_LIST_UPDATE")
check(ana.level == 34 and ana.classFile == "DRUID", "the /who answer fills level and class")
W.who = { { fullName = "Zoe Far", level = 50, filename = "MAGE" } }
W.fire("WHO_LIST_UPDATE")
check(PL.whoCache["zoe far"] ~= nil, "every /who answer is cached")
W.advance(16 * 60)
check(next(PL.whoCache) == nil, "and the cache is pruned after 15 minutes")
check(#W.violations == 0, "all of it ran from clicks")

-- Outside a click the game blocks them: the stub records what the game would refuse.
PL:Whisper(ana)
PL:Invite(ana)
check(#W.violations == 2, "the stub catches a protected call outside a click")
W.violations = {}

-- ── group units ────────────────────────────────────────────────────────────
W.setGroup({ { name = "Ivo", surname = "Sol" } })
W.group.leader = false
W.invites = {}
check(select(2, W.click(PL.Invite, PL, ana)) == "cannot_invite" and #W.invites == 0, "not the leader: no invite")
W.group.leader = true
W.setGroup({ { name = "Ana", surname = nil, class = "DRUID" } })
check(_G.PartyLens_Roster.IsInGroup("Ana Lima"), "a groupmate whose unit gives the first name alone is found")
check(select(2, W.click(PL.Invite, PL, ana)) == "in_group", "and not invited again")
W.setGroup({ { name = "Bia", surname = "Rocha" } })
check(_G.PartyLens_Roster.IsInGroup("Bia Rocha") and not _G.PartyLens_Roster.IsInGroup("Bia Lima"),
  "a unit with a surname matches it exactly")
W.units.party1.name = W.secret("Bia")
ok = pcall(_G.PartyLens_Roster.Members)
check(ok and #_G.PartyLens_Roster.Members() == 1, "a secret groupmate is skipped, not an error")

-- ── the save ───────────────────────────────────────────────────────────────
PL = W.boot({ savedDB = { schemaVersion = 8, spec = "Holy", specAuto = true, rep = { given = {} },
  autopilot = { tier = "auto" }, layer = { beacon = true }, roles = { tank = true } } })
check(PL.db.schemaVersion == 100, "an Anniversary save starts over as schema 100")
check(PL.db.spec == nil and PL.db.rep == nil and PL.db.autopilot == nil and PL.db.layer == nil,
  "none of its keys survive")
check(PL.db.roles.tank == false and PL.db.roles.dps == true, "not even a key the new schema also has")
check(PL.db.filters.onlyOpen == true and PL.db.listing.want.dps == 3, "the defaults are there")
PL.db.roles.tank, PL.db.comment = true, "geared"
local saved = PartyLensDB
saved.filters.type = nil
PL = W.boot({ savedDB = saved })
check(PL.db.roles.tank == true and PL.db.comment == "geared", "a schema 100 save keeps the player's choices")
check(PL.db.filters.type == "all", "and gets a missing key back at any depth")
PL = W.boot({ savedDB = { schemaVersion = 101, comment = "from the future" } })
check(PL.db.comment == "from the future", "a newer schema is not wiped")
check(#W.errors == 0, "nothing raised")

W.done("names")
