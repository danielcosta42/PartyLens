-- The radar's chat ear on WoW: Forever, against the real modules (tools/wowstub.lua): posts in the LookingForGroup
-- channel become entries with their type, roles and activity (the new Forever dungeons included, in several
-- languages); a secret line is dropped without an error; my own lines, by full name, never become entries; a
-- signed post marks another PartyLens user.
--
--   luajit tools/chat.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local PL = W.boot({})
local Chat = _G.PartyLens_Chat

local function parse(text)
  return Chat.Parse(text)
end

-- ── activities ─────────────────────────────────────────────────────────────
local cases = {
  { "LFM RoL need tank", "rol", "lfm" },
  { "LF healer for Ruins of Lordaeron, need 1 heal", "rol", "lfm" },
  { "LFG City of Dalaran, dps 38", "dalaran", "lfg" },
  { "LF2M Excavation Site heals", "excavation", "lfm" },
  { "LFM Hall of Thanes need dps", "thanes", "lfm" },
  { "LFM Manor Mistmantle tank", "mistmantle", "lfm" },
  { "LF1M Krol'dok Stronghold healer", "kroldok", "lfm" },
  { "LFM Shaper's Terrace", "shapers", "lfm" },
  { "LFM DM need heal", "dm", "lfm" },
  { "LFM dm east tank", "dme", "lfm" },
  { "lf1m sm cath heal", "smcath", "lfm" },
  { "LFG BRD, warrior tank", "brd", "lfg" },
  { "LFG ST dps", "st", "lfg" },
  { "LFM MC need heals", "mc", "lfm" },
  { "LFM Naxx need tanks", "naxx", "lfm" },
}
for _, c in ipairs(cases) do
  local d = parse(c[1])
  check(d and d.activityKey == c[2], "'" .. c[1] .. "' is " .. c[2] .. " (got " .. tostring(d and d.activityKey) .. ")")
  check(d.type == c[3], "'" .. c[1] .. "' is " .. c[3])
end
check(parse("LFM RoL need tank").activity == "Ruins of Lordaeron", "the activity carries its display name")
check(parse("LFM MC need heals").activityType == "raid" and parse("LFM RoL tank").activityType == "dungeon",
  "raids and dungeons are told apart")
check(parse("LFG first time, any dungeon") and parse("LFG first time, any dungeon").activityKey == nil,
  "'st' is a whole word: 'first' is no Sunken Temple")
check(parse("LFM smth else").activityKey == nil, "nor 'sm' inside a word")

-- ── types and roles ────────────────────────────────────────────────────────
local d = parse("LFG Ruins of Lordaeron, heal/dps")
check(d.type == "lfg" and d.roles.heal and d.roles.dps and not d.roles.tank, "LFG with the roles offered")
d = parse("LFM RoL need 1 heal and a tank")
check(d.type == "lfm" and d.roles.heal and d.roles.tank and not d.roles.dps, "LFM with the roles needed")
d = parse("need group for WC, tank here")
check(d.type == "lfg" and d.roles.tank, "'need group' is a player looking for one")
d = parse("<Ashen> recruiting for raids, apply on discord, LFM")
check(d.activityType == "guild" and not d.roles.heal, "guild recruiting is 'guild', and 'disc' in discord is no healer")
check(parse("selling gold cheap LFM boost 500g").isSpam, "spam is flagged")
check(parse("anyone around Orgrimmar?") == nil, "a line that is neither LFG nor LFM is nothing")

-- ── languages ──────────────────────────────────────────────────────────────
PL = W.boot({ locale = "ptBR" })
Chat = _G.PartyLens_Chat
d = Chat.Parse("Procuro grupo para Minas Mortas, sou curador")
check(d and d.type == "lfg" and d.activityKey == "dm" and d.roles.heal, "ptBR: procuro grupo, Minas Mortas, curador")
d = Chat.Parse("LFM Ruínas de Lordaeron precisa tanque")
check(d and d.type == "lfm" and d.activityKey == "rol" and d.roles.tank, "ptBR: Ruínas de Lordaeron, tanque")
d = Chat.Parse("LFM RoL need heal")
check(d and d.activityKey == "rol" and d.roles.heal, "ptBR client still reads an English post")
PL = W.boot({ locale = "deDE" })
d = _G.PartyLens_Chat.Parse("LFM Todesminen benötigt heiler")
check(d and d.type == "lfm" and d.activityKey == "dm" and d.roles.heal, "deDE: Todesminen, heiler")
PL = W.boot({ locale = "frFR" })
d = _G.PartyLens_Chat.Parse("LF1M Mortemines soigneur")
check(d and d.activityKey == "dm" and d.roles.heal, "frFR: Mortemines, soigneur")
PL = W.boot({ locale = "esES" })
d = _G.PartyLens_Chat.Parse("LFM Monasterio Escarlata necesitamos sanador")
check(d and d.activityKey == "sm" and d.roles.heal, "esES: Monasterio Escarlata, sanador")

-- ── the channel ────────────────────────────────────────────────────────────
PL = W.boot({})
W.guids = { ["Player-1-77"] = "DRUID" }
local added = {}
PL:On("ENTRY_ADDED", function(e, needsMe) added[#added + 1] = { e = e, needsMe = needsMe } end)
W.channelLine("LFM RoL need dps", "Ana Lima-ClassicBetaPvE2", "Player-1-77")
local list = PL:GetEntries()
check(#list == 1 and list[1].name == "Ana Lima" and list[1].key == "ana lima", "an entry under the full name, realm off")
check(list[1].classFile == "DRUID", "its class from the GUID")
check(#added == 1 and added[1].needsMe == true, "ENTRY_ADDED says it needs me (I play dps by default)")
W.channelLine("LFM RoL need dps, 1 more", "Ana Lima-ClassicBetaPvE2", "Player-1-77", { lineID = 2 })
check(#PL:GetEntries() == 1 and #added == 1, "a second line from her is the same row, not a new one")
check(PL:GetEntries()[1].message == "LFM RoL need dps, 1 more", "with the latest message")

W.channelLine("LFM RoL need tank", "Bia Rocha", "", { channelName = "2. Trade - City", baseName = "Trade" })
check(#PL:GetEntries() == 1, "a line in Trade is not the radar's")

W.channelLine("LFM Hall of Thanes, need tank", "Chehul Costa-ClassicBetaPvE2", "Player-1-0001")
W.channelLine("LFM Hall of Thanes, need tank", "Chehul Costa", "Player-1-0001")
check(#PL:GetEntries() == 1, "my own lines, by my full name, are not entries")
W.channelLine("LFG thanes heal", "Chehul Druida", "")
check(PL.entries["chehul druida"] ~= nil, "another character with my first name is somebody else")

W.channelLine("[PartyLens]: LFM City of Dalaran, need heal", "Caio Nunes", "")
local caio = PL.entries["caio nunes"]
check(caio and caio.isAddonUser and caio.message == "LFM City of Dalaran, need heal",
  "a signed post marks a PartyLens user, sign stripped")

-- ── secrets ────────────────────────────────────────────────────────────────
local before = 0
for _ in pairs(PL.entries) do before = before + 1 end
local ok = pcall(W.channelLine, W.secret("LFM RoL need tank"), "Davi Melo", "")
check(ok, "a secret line raises nothing")
ok = pcall(W.channelLine, "LFM RoL need tank", W.secret("Davi Melo"), "")
check(ok, "nor a secret sender")
ok = pcall(W.channelLine, "LFM RoL need tank", "Davi Melo", W.secret("Player-1-9"))
check(ok, "nor a secret GUID")
ok = pcall(W.fire, "CHAT_MSG_CHANNEL", "LFM RoL tank", "Davi Melo", "", W.secret("4. LookingForGroup"), "", "", 26, 4,
  "LookingForGroup", 0, 9, "")
check(ok, "nor a secret channel name")
local after = 0
for _ in pairs(PL.entries) do after = after + 1 end
check(after == before and PL.entries["davi melo"] == nil, "and each such line is dropped")
ok = pcall(W.channelLine, "LFM RoL need tank", "", "")
check(ok and PL.entries[""] == nil, "a line with no sender is dropped too")
check(#W.errors == 0, "no handler error reached the error handler")

-- ── filters ────────────────────────────────────────────────────────────────
W.channelLine("LFG RoL tank", "Elza Dias", "")
PL:Set("filters.type", "lfg")
for _, e in ipairs(PL:GetEntries()) do check(e.type == "lfg", "the lfg filter shows players only") end
PL:Set("filters.type", "all")
PL:Set("filters.activity", "dalaran")
check(#PL:GetEntries() == 1 and PL:GetEntries()[1].name == "Caio Nunes", "the activity filter")
PL:Set("filters.activity", "")
PL:Set("filters.query", "thanes")
check(#PL:GetEntries() == 1 and PL:GetEntries()[1].name == "Chehul Druida", "the text search")
PL:Set("filters.query", "")
check(PL:Set("filters.nonsense", true) == false and PL:Set("filters.type", 3) == false,
  "Set refuses an unknown key and a value of another type")
check(PL:Set("listing.comment", "x") == false and PL:Set("schemaVersion", 1) == false,
  "and a key that has its own call")
PL:Block(PL.entries["elza dias"])
check(PL.entries["elza dias"] and not (function()
  for _, e in ipairs(PL:GetEntries()) do if e.key == "elza dias" then return true end end
end)(), "a blocked player is hidden")
W.channelLine("WTS gold LFM cheap boost 500g", "Fabi Reis", "")
check(PL.entries["fabi reis"].isSpam, "spam is stored flagged")
for _, e in ipairs(PL:GetEntries()) do check(not e.isSpam, "and hidden by default") end

-- ── counts follow the list ─────────────────────────────────────────────────
PL = W.boot({})
W.channelLine("LFM RoL need dps", "Gus Mar", "")
W.channelLine("LFM RoL need dps", "Ivo Sol", "")
W.channelLine("LFM RoL need dps cheap boost 500g", "Jon Lua", "")
W.channelLine("LFM MC need dps", "Kai Rio", "")
PL:Block(PL.entries["ivo sol"])
local c = PL:GetCounts()
check(c.total == 4 and c.visible == 2 and c.needsMe == 2, "needsMe counts only what the list shows: blocked and spam out")
PL:Set("filters.activity", "rol")
check(PL:GetCounts().needsMe == 1, "and filtered rows out")
PL:Set("filters.activity", "")
PL:Set("roles.dps", false)
PL:Set("roles.tank", true)
check(PL:GetCounts().needsMe == 0, "and is recounted the moment my roles change")

-- ── the LFG channel, in any language ───────────────────────────────────────
local function boot(o)
  PL = W.boot(o)
  local seen = {}
  PL:On("LFG_CHANNEL_CHANGED", function(ch) seen[#seen + 1] = ch or false end)
  return seen
end
local seen = boot({})
check(PL:LFGChannel() and PL:LFGChannel().id == 4 and PL:LFGChannel().name == "LookingForGroup",
  "the English client listens on LookingForGroup")
W.channels.LookingForGroup = nil
W.fire("CHANNEL_UI_UPDATE")
check(PL:LFGChannel() == nil and seen[#seen] == false, "leaving it is seen at once (LFG_CHANNEL_CHANGED nil)")
W.channels.LookingForGroup = 7
W.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED")
check(PL:LFGChannel().id == 7 and seen[#seen].id == 7, "and joining it again, under its new number")

seen = boot({ locale = "ptBR", channels = { Geral = 1, ["Comércio"] = 2, ProcurandoGrupo = 5 } })
check(PL:LFGChannel() and PL:LFGChannel().id == 5 and PL:LFGChannel().name == "ProcurandoGrupo",
  "a ptBR client listens on ProcurandoGrupo")
W.channelLine("LFM RoL need tank", "Lia Paz", "", { channelName = "5. ProcurandoGrupo", baseName = "ProcurandoGrupo" })
check(PL.entries["lia paz"] ~= nil, "and the radar reads it")
PL:SetListing({ activity = "rol" })
W.click(PL.PostLFG, PL)
check(W.chat[1] and W.chat[1].chatType == "CHANNEL" and W.chat[1].target == 5, "the post goes to that channel's number")
W.advance(15)
check(#W.joined == 0 or W.joined[1] == "ChehulNetH", "no custom LookingForGroup is joined")

seen = boot({ locale = "ptBR", channels = { Geral = 1 }, serverChannels = { "Geral", "Comércio", "ProcurandoGrupo" },
  joinable = { ProcurandoGrupo = 6 } })
W.advance(13)
local joinedLFG
for _, n in ipairs(W.joined) do if n ~= "ChehulNetH" then joinedLFG = n end end
check(joinedLFG == "ProcurandoGrupo", "missing, it is joined by the server's own (localized) name")
check(PL:LFGChannel() and PL:LFGChannel().id == 6 and seen[#seen].id == 6, "and the radar then listens on it")

seen = boot({ locale = "deDE", channels = { Allgemein = 1 } })
W.advance(13)
for _, n in ipairs(W.joined) do check(n ~= "LookingForGroup", "a German client without the list joins no English name") end
check(select(2, W.click(PL.PostLFG, PL)) == "no_channel" and #W.chat == 0, "and posts nothing")

seen = boot({ channels = { General = 1 } })
W.advance(13)
local english = false
for _, n in ipairs(W.joined) do if n == "LookingForGroup" then english = true end end
check(english, "an English client without the list joins LookingForGroup by name")

-- ── expiry ─────────────────────────────────────────────────────────────────
W.advance(31 * 60)
check(next(PL.entries) == nil, "chat entries expire after 30 minutes")
check(#W.violations == 0 and #W.errors == 0, "nothing protected ran and nothing raised")

W.done("chat")
