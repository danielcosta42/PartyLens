-- Autopilot in suggestion mode, against the real modules (tools/wowstub.lua): with a listing active it ranks the
-- radar (players who fill a missing role for an lfm, groups that need my role for an lfg), and no tick, however
-- long it runs, invites, whispers, posts or searches. Only a click acts.
--
--   luajit tools/autopilot.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local function nothingActed(what)
  check(#W.invites == 0 and #W.chat == 0 and #W.whos == 0 and #W.uninvites == 0 and #W.left == 0,
    what .. ": nothing was invited, said, whispered or searched")
  check(#W.violations == 0, what .. ": no protected call was even attempted")
end

local PL = W.boot({})
PL.db.roles = { tank = false, heal = true, dps = false }
local fired = {}
PL:On("SUGGESTIONS_CHANGED", function(list) fired[#fired + 1] = list end)

W.channelLine("LFG RoL tank, warrior 36", "Ana Lima", "")
W.channelLine("LFG RoL heal", "Bia Rocha", "")
W.channelLine("LFG any dungeon dps", "Caio Nunes", "")
W.channelLine("LFM RoL need heal", "Davi Melo", "")
W.channelLine("LFG anything", "Elza Dias", "")

check(#PL:GetSuggestions() == 0, "no listing, no suggestions")
W.advance(60)
nothingActed("idle")

W.click(PL.StartListing, PL, { type = "lfm", activity = "rol", want = { tank = 1, heal = 1, dps = 3 } })
local list = PL:GetSuggestions()
local byName = {}
for i, s in ipairs(list) do byName[s.entry.name] = { s = s, rank = i } end
check(byName["Ana Lima"] and byName["Ana Lima"].s.action == "invite" and byName["Ana Lima"].s.role == "tank",
  "an lfm suggests the player who fills the missing tank, to invite")
check(byName["Caio Nunes"] and byName["Caio Nunes"].s.role == "dps", "and the dps")
check(byName["Bia Rocha"] == nil, "not a healer: I am the healer, that slot is filled")
check(byName["Davi Melo"] == nil, "not a group: an lfm recruits players")
check(byName["Elza Dias"] and byName["Elza Dias"].s.reason == "open", "a player who names no role is an open match")
check(byName["Ana Lima"].rank < byName["Elza Dias"].rank, "a role match ranks above an open one")
check(byName["Ana Lima"].rank < byName["Caio Nunes"].rank, "the same activity ranks above another")
check(#fired >= 1, "SUGGESTIONS_CHANGED fired")

W.advance(10 * 60)
nothingActed("ten minutes of ticks with an lfm listing")
check(#W.sentWhere({ prefix = "PartyLens" }) > 0, "the listing itself did go on the network (addon messages only)")

W.click(PL.Invite, PL, byName["Ana Lima"].s.entry)
check(W.invites[1] == "Ana Lima", "a click on a suggestion invites her")
list = PL:GetSuggestions()
check(list[1].entry.name ~= "Ana Lima" and PL.entries["ana lima"].contacted == "invite",
  "and she drops down the list, marked contacted")

PL:DismissSuggestion(PL.entries["caio nunes"])
for _, s in ipairs(PL:GetSuggestions()) do check(s.entry.name ~= "Caio Nunes", "a dismissed suggestion is gone") end

W.setGroup({ { name = "Ana", surname = "Lima", class = "WARRIOR" } })
for _, s in ipairs(PL:GetSuggestions()) do check(s.entry.name ~= "Ana Lima", "a groupmate is never suggested") end

-- In a raid every roster read is 40 units of API calls: one suggestion pass reads the roster a fixed number of
-- times, however many entries the radar holds.
local raid = {}
for i = 1, 39 do raid[i] = { name = "Raider" .. string.char(64 + (i % 26) + 1), surname = "N" .. i } end
W.setGroup(raid, true)
for i = 1, 60 do W.channelLine("LFG RoL dps", "Lfg" .. i .. " Pug", "") end
local reads, real = 0, UnitFullName
UnitFullName = function(...) reads = reads + 1 return real(...) end
PL:GetSuggestions()
UnitFullName = real
check(reads <= 2 * 40, "a suggestion pass over 60 entries reads a 40-unit roster at most twice (" .. reads .. " reads)")
W.setGroup({ { name = "Ana", surname = "Lima", class = "WARRIOR" } })

W.click(PL.StopListing, PL)
check(#PL:GetSuggestions() == 0, "stopping the listing ends the suggestions")
local n = #fired
W.advance(60)
check(#fired == n, "and its ticker")

-- An lfg listing: groups that need one of my roles, to whisper.
W.invites = {}
W.setGroup({})
W.click(PL.StartListing, PL, { type = "lfg", activity = "rol" })
list = PL:GetSuggestions()
check(#list == 1 and list[1].entry.name == "Davi Melo" and list[1].action == "whisper" and list[1].role == "heal",
  "an lfg suggests the group that needs a healer, to whisper")
W.channelLine("LFM RoL need tank", "Fabi Reis", "")
W.advance(6)
for _, s in ipairs(PL:GetSuggestions()) do check(s.entry.name ~= "Fabi Reis", "not a group that needs only a tank") end
W.advance(10 * 60)
nothingActed("ten minutes of ticks with an lfg listing")
W.click(PL.Whisper, PL, list[1].entry)
check(#W.chat == 1 and W.chat[1].target == "Davi Melo" and W.chat[1].chatType == "WHISPER", "a click whispers him")

-- ── the inter-addon API and the slash command open pages, and send nothing ─
PL = W.boot({ quests = { [4321] = "Elite Ogres" } })
local opened = {}
PL.UI = { Open = function(_, page, ctx) opened[#opened + 1] = { page = page, ctx = ctx } end,
  Toggle = function() opened[#opened + 1] = { page = "toggle" } end }
local API = _G.PartyLens.API
check(API == _G.PartyLens_API and API.IsReady(), "the API is reachable both ways and ready")
check(API.StartQuestGroup({ questID = 4321, stepText = "kill ogres" }), "StartQuestGroup")
local draft = PL:GetListing()
check(not draft.active and draft.type == "lfm" and draft.label == "Elite Ogres" and draft.activityType == "quest",
  "a quest draft, titled from the quest log, not started")
check(draft.want.tank == 1 and draft.want.heal == 1 and draft.want.dps == 3, "sized for five")
check(opened[1].page == "announce" and opened[1].ctx.label == "Elite Ogres", "and the Announce page opens on it")
check(API.StartQuestGroup({ stepText = "Onyxia attunement", needRaid = true }) and PL:GetListing().want.heal == 2,
  "a raid quest is sized for ten")
W.click(PL.StartListing, PL, { label = "my own" })
API.StartQuestGroup({ stepText = "another quest" })
check(PL:GetListing().label == "my own", "a listing on the air is left alone")
W.click(PL.StopListing, PL)
check(API.RequestLayer(1453, 202) and opened[#opened].page == "layer" and opened[#opened].ctx.zoneUID == 202,
  "RequestLayer opens the Layer page on that layer")
local mapID = API.MyLayer()
check(mapID == 1453, "MyLayer")
SlashCmdList.PARTYLENS("announce")
check(opened[#opened].page == "announce", "/pl announce")
SlashCmdList.PARTYLENS("layer")
check(opened[#opened].page == "layer", "/pl layer")
SlashCmdList.PARTYLENS("")
check(opened[#opened].page == "toggle", "/pl toggles")
check(SLASH_PARTYLENS1 == "/partylens" and SLASH_PARTYLENS2 == "/pl", "both slash words")
nothingActed("the API and the slash command")
check(#W.errors == 0, "nothing raised")

W.done("autopilot")
