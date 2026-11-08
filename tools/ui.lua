-- The PartyLens interface against the real core, under the core's simulated Forever client (tools/wowstub.lua)
-- with a widget layer for the UI (tools/uistub.lua).
--
--   luajit tools/ui.lua            (from the repository root)
--
-- W.boot loads the whole TOC: the core modules, Core.lua, then the UI files, with uistub's widgets laid over
-- wowstub just before the first UI file. Then chat lines and network listings arrive, a listing is drafted,
-- posted and stopped, suggestions are acted on, a layer is asked for, accepted, served and undone, a request
-- for my layer arrives and is served from its toast, the group needs summons, and every page is drawn and every
-- control clicked; then animations go off and it all runs again expecting no animation to play.
-- Clicks go through W.click (a hardware event); a protected core action reached any other way is a failure.
-- Also checks the textures in Media/, every Media path the code paints, every widget method against the
-- Forever API lists, the ptBR table and the copy rules. Prints every failure and exits 1 if there was any.
local W = dofile("tools/wowstub.lua")
local Stub = dofile("tools/uistub.lua")

-- The order the TOC loads them in, after Core.lua.
local FILES = {
	"UI/Theme.lua", "UI/Locale.lua", "UI/Motion.lua", "UI/Widgets.lua", "UI/Radar.lua", "UI/Window.lua", "UI/Data.lua",
	"UI/Pages/Groups.lua", "UI/Pages/Announce.lua", "UI/Pages/Layer.lua", "UI/Pages/Summon.lua",
	"UI/Pages/Network.lua", "UI/Pages/Settings.lua", "UI/Minimap.lua",
}
local PAGES = { "groups", "announce", "layer", "summon", "network", "settings" }
local MEDIA_PREFIX = "Interface\\AddOns\\PartyLens\\Media\\"
local FONTS = { ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true }
-- Core keys the contract (section 9) lets the UI reuse.
local CORE_KEYS = { ROLE_TANK = true, ROLE_HEAL = true, ROLE_DPS = true, TYPE_LFG = true, TYPE_LFM = true,
	ACTIVITY_DUNGEON = true, ACTIVITY_RAID = true, ACTIVITY_QUEST = true, ACTIVITY_GUILD = true, ACTIVITY_OTHER = true,
	ACTIVITY_ANY = true, LEVEL_SHORT = true, BINDING_TOGGLE = true, HELP = true }
-- The contract's click-only calls (section 3 to 7, "Click? yes"). The game itself blocks the bold ones; the
-- harness wraps all of them so a call outside W.click is recorded the same way.
local CLICK_ONLY = { "Whisper", "OpenWhisper", "Invite", "Who", "StartListing", "StopListing", "PostLFG",
	"RequestLayer", "ServeLayerRequest", "ServeNextLayerRequest", "UndoLayerGroup", "AnnounceSummon" }

local checks, failures = 0, 0
local function check(cond, what)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.stderr:write("FAIL: " .. what .. "\n")
	end
	return cond
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- ── textures ──────────────────────────────────────────────────────────────
local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
local function pow2(n) return n > 0 and n % 1 == 0 and math.floor(2 ^ math.floor(math.log(n) / math.log(2) + 0.5)) == n end

local function validTGA(name)
	local s = read("Media/" .. name .. ".tga")
	if not s then return false, "missing" end
	if #s < 18 then return false, "short header" end
	local idLen, cmap, kind = s:byte(1), s:byte(2), s:byte(3)
	local w, h, bpp, desc = u16(s, 13), u16(s, 15), s:byte(17), s:byte(18)
	if idLen ~= 0 or cmap ~= 0 or kind ~= 2 then return false, "not an uncompressed true-colour TGA" end
	if bpp ~= 32 or desc % 16 ~= 8 then return false, "not 32-bit with 8 alpha bits" end
	if not (pow2(w) and pow2(h)) then return false, string.format("%dx%d is not a power of two", w, h) end
	if #s ~= 18 + w * h * 4 and #s ~= 18 + w * h * 4 + 26 then return false, "size does not match the header" end
	return true
end

local generated = {}
for name in (read("tools/gen-media.py") or ""):gmatch('%("([%w%-]+)", [%w_%(]+') do generated[#generated + 1] = name end
check(#generated >= 20, "tools/gen-media.py lists its textures (" .. #generated .. " found)")
local isGenerated = {}
for _, name in ipairs(generated) do
	isGenerated[name] = true
	local ok, why = validTGA(name)
	check(ok, "Media/" .. name .. ".tga: " .. tostring(why))
end

-- ── the TOC ───────────────────────────────────────────────────────────────
local toc = W.toc()
local coreAt, ui = nil, {}
for i, path in ipairs(toc) do
	if path == "Core.lua" then coreAt = i end
	if path:find("^UI/") then ui[#ui + 1] = { path = path, at = i } end
end
check(#ui == #FILES, "the TOC lists the " .. #FILES .. " UI files (" .. #ui .. " found)")
for i, f in ipairs(FILES) do
	check(ui[i] and ui[i].path == f and coreAt and ui[i].at > coreAt, "the TOC loads " .. f .. " after Core.lua, in order")
end

-- ── sources ───────────────────────────────────────────────────────────────
-- Sources without their comments, so prose about what the code avoids is not mistaken for code.
local sources = {}
for _, f in ipairs(FILES) do
	local src = read(f)
	check(src, "exists: " .. f)
	sources[f] = (src or ""):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
end
local function media(f, name, how)
	if name:sub(-1) == "-" then -- a prefix completed at run time ("role-" .. role)
		for _, role in ipairs({ "tank", "heal", "dps" }) do media(f, name .. role, how) end
		return
	end
	check(isGenerated[name], f .. " " .. how .. " Media/" .. name .. " which gen-media.py does not make")
end
for f, src in pairs(sources) do
	for name in src:gmatch('UI%.Tex%([^,]+,%s*"([%w%-]+)"') do media(f, name, "paints") end
	for name in src:gmatch('icon%s*=%s*"([%w%-]+)"') do media(f, name, "uses the icon") end
	for name in src:gmatch('Kit%.IconButton%([^,]+,%s*"([%w%-]+)"') do media(f, name, "uses") end
	check(not src:find("UIDropDownMenu", 1, true) and not src:find("hooksecurefunc", 1, true), f .. " stays off UIDropDownMenu and hooks")
	check(not src:find("SendChatMessage", 1, true), f .. " never sends chat itself")
	for global in src:gmatch("PartyLens_[%w_]+") do
		check(global == "PartyLens_UI", f .. " reads only the contract, not the core module " .. global)
	end
end

-- Every UI key has a Portuguese line and follows the copy rules; core keys are ones the contract names.
local keys, coreKeys = {}, {}
for f, src in pairs(sources) do
	for key in src:gmatch('L%["(.-)"%]') do
		if key:find("^[A-Z][A-Z_]+$") then coreKeys[key] = f else keys[key] = f end
	end
end
check(next(keys) ~= nil, "the code uses L[...] strings")
for key, f in pairs(coreKeys) do check(CORE_KEYS[key], f .. " reuses core key " .. key .. ", which the contract does not offer") end
local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local ACRONYMS = { LFM = true, LFG = true, DPS = true, ID = true }
local function copyOK(s)
	if s:find("\194\183", 1, true) then return false, "middle dot separator" end
	for word in plain(s):gmatch("[%a]+") do
		if #word >= 3 and word == word:upper() and not ACRONYMS[word] then return false, "all-caps word " .. word end
	end
	return true
end

-- ── one client: the core and the UI ───────────────────────────────────────
local S, PL, UI

-- Wraps the click-only calls so one made outside W.click lands in W.violations like the game's own.
local function guardClicks(pl)
	for _, name in ipairs(CLICK_ONLY) do
		local fn = pl[name]
		pl[name] = function(...)
			if not W.hw then
				table.insert(W.violations, { fn = "PartyLens:" .. name })
				return false, "not_a_click"
			end
			return fn(...)
		end
	end
end

local function boot(opts)
	opts = opts or {}
	local real, overlay = loadfile, nil
	_G.loadfile = function(path, ...)
		if not overlay and type(path) == "string" and path:find("^UI/") then
			overlay = Stub.overlay(W, opts)
			_G.L = opts.globalL
		end
		return real(path, ...)
	end
	local ok, pl = pcall(W.boot, opts)
	_G.loadfile = real
	check(ok, "the core and the UI boot: " .. tostring(pl))
	S, PL = overlay, ok and pl or nil
	UI = PL and PL.UI
	if PL then guardClicks(PL) end
	return S, PL, UI
end

local function noErrors(what)
	local err = S.errors[1] or W.errors[1]
	check(err == nil, what .. " without a Lua error" .. (err and (": " .. tostring(err)) or ""))
	S.errors, W.errors = {}, {}
end

local function noViolations(what)
	local v = W.violations[1]
	check(v == nil, what .. ": no protected core action outside a click" .. (v and (" (" .. v.fn .. ")") or ""))
	W.violations = {}
end

local function plays(g) return g and g.__plays or 0 end
local function click(o, button) return W.click(S.fire, o, "OnClick", button or "LeftButton", false) end

-- Every visible clickable thing on screen gets entered, pressed, clicked and left; fields get typed into.
-- The animations checkbox and the minimap button are left alone (they are tested on their own).
local function fuzz(key)
	local clicked = 0
	local skip = { [_G.PartyLensMinimapButton or 0] = true }
	local settings = UI.pageFrames.settings
	if settings and settings.animations then skip[settings.animations] = true end
	for _, o in ipairs(S.descendants(UIParent)) do
		local sc = o.__scripts
		if (sc.OnClick or sc.OnMouseDown) and S.visible(o) and not skip[o] then
			S.fire(o, "OnEnter")
			S.fire(o, "OnMouseDown", "LeftButton")
			S.fire(o, "OnMouseUp", "LeftButton")
			if o.__enabled ~= false then click(o) end
			S.fire(o, "OnLeave")
			clicked = clicked + 1
			S.advance(0.05)
			if not UI:IsOpen() or UI.current ~= key then UI:Open(key) end
		end
	end
	for _, o in ipairs(S.descendants(UIParent)) do
		if o.__kind == "EditBox" and S.visible(o) then
			o:SetFocus()
			o.__text = "ru"
			S.fire(o, "OnTextChanged", true)
			S.fire(o, "OnEnterPressed")
			o:SetFocus()
			o.__text = ""
			S.fire(o, "OnTextChanged", true)
			S.fire(o, "OnEscapePressed")
		elseif o.__kind == "ScrollFrame" and S.visible(o) then
			S.fire(o, "OnMouseWheel", -1)
			S.fire(o, "OnMouseWheel", 1)
		end
	end
	S.advance(0.5)
	return clicked
end

local function rowOf(list, match)
	for _, row in ipairs(list.rows) do
		if row.item and row.__shown and match(row.item) then return row end
	end
end

-- Picks a menu row by its text, wheeling down a long list like a player would.
local function menuPick(text)
	local menu = _G.PartyLensMenu
	for _ = 1, 60 do
		for _, r in ipairs(menu and menu.rows or {}) do
			if r.__shown and r.item and r.item.text == text then return click(r) end
		end
		S.fire(menu, "OnMouseWheel", -1)
	end
	check(false, "the menu offers \"" .. text .. "\"")
end

local function typeInto(edit, text)
	edit:SetFocus()
	edit.__text = text
	S.fire(edit, "OnTextChanged", true)
	S.fire(edit, "OnEnterPressed")
end

-- A PartyLens network listing (Comm's wire format). seq is the lister's server time at the change: the core
-- drops one far from its own clock.
local function listing(origin, kind, roles, activity, filled, want)
	return table.concat({ "2", kind or "lfm", roles or "tank+heal", "dungeon", activity or "thanes", "0", "WARRIOR", "34",
		"202", "1453", filled or "1.0.2", want or "1.1.3", tostring(time()), "0", origin, "fast run" }, "|")
end

local function entryNamed(name)
	for _, e in ipairs(PL:GetEntries()) do if e.name == name then return e end end
end

--------------------------------------------------------------------------------
-- 1. English client, animations on, the core alive
--------------------------------------------------------------------------------
boot({})
noErrors("booting the core and the UI")
check(UI and UI == _G.PartyLens_UI and type(UI.Toggle) == "function" and type(UI.Open) == "function",
	"the UI registers itself as PartyLens.UI with Toggle and Open")
check(UI.Motion.On() and PL.db.animations == true, "animations start on (db.animations)")
PL:Set("roles.heal", true)
PL:Set("roles.dps", true)
W.directory({ "Zed One", "Yan Two" })
W.guids = { ["Player-1-0101"] = "DRUID", ["Player-1-0102"] = "PRIEST", ["Player-1-0103"] = "MAGE" }
W.npc("target", 101)
W.fire("PLAYER_TARGET_CHANGED")
W.channelLine("LFM Ruins of Lordaeron need heal", "Davi Melo", "Player-1-0101")
W.channelLine("LFG RoL tank, warrior 36", "Bia Rocha", "")
W.channelLine("LFG any dungeon dps mage", "Caio Nunes", "Player-1-0103")
W.channelLine("LFM Wailing Caverns need tank", "Fabi Reis", "")
W.deliver("PartyLens", listing("Ana Lima"), "WHISPER", "Ana Lima-ClassicBetaPvE2")
W.deliver("PLLnet", "PLL2|S|1453|202|1|4", "GUILD", "Ana Lima-ClassicBetaPvE2")
W.deliver("ChehulNet", "CHN1|H|pl|DRUID|30|v=1|1453:303", "GUILD", "Gil Paz-ClassicBetaPvE2")
W.deliver("ChehulNet", "CHN1|H|gos|MAGE|44|v=1|1454:404", "GUILD", "Hugo Luz-ClassicBetaPvE2")
check(#PL:GetEntries() >= 5, "the core has entries from chat and the network (" .. #PL:GetEntries() .. ")")

for i, key in ipairs(PAGES) do
	local def = UI.pages[key]
	check(def, "page '" .. key .. "' is registered")
	if def then
		check(type(def.label) == "string" and def.label ~= "", "page '" .. key .. "' has a label")
		check(isGenerated[def.icon or ""], "page '" .. key .. "' has an icon from Media")
		check(type(def.build) == "function" and type(def.refresh) == "function", "page '" .. key .. "' has build and refresh")
	end
	check(UI.ORDER[i] == key, "sidebar order puts '" .. key .. "' at " .. i)
end

-- Minimap and compartment
local mm = _G.PartyLensMinimapButton
check(mm and mm.__shown and mm.__parent == Minimap, "the minimap button sits on the minimap")
check(#S.compartment == 1 and S.compartment[1].text == "PartyLens" and type(S.compartment[1].func) == "function",
	"PartyLens is registered once in the addon compartment")
check(S.compartment[1] and S.compartment[1].icon == MEDIA_PREFIX .. "logo", "the compartment icon is the coloured logo")

-- Open on the Groups page
PL:Toggle()
local page = UI.pageFrames.groups
noErrors("opening the window with PartyLens:Toggle()")
local win = _G.PartyLensWindow
check(win and win == UI.frame and UI:IsOpen() and UI.current == "groups", "PartyLens:Toggle() opens PartyLensWindow on Groups")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "PartyLensWindow" then esc = true end end
check(esc, "Esc closes the window (UISpecialFrames)")
check(win.__backdrop and win.__template == "BackdropTemplate", "the window paints its backdrop through BackdropTemplate")
check(plays(win.motion and win.motion.fade) == 1 and near(win.motion.fade.alpha.__duration, 0.12), "the window fades in when it opens")
check(PL:LFGChannel() and UI.head.status.__text:find("Listening to " .. PL:LFGChannel().name, 1, true)
	and UI.head.status.__text:find("on the radar", 1, true), "the header names the core's LFG channel and counts the radar")
-- The channel goes and comes back (LFG_CHANNEL_CHANGED): the header follows.
W.channels.LookingForGroup = nil
W.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT")
S.advance(0.3)
check(PL:LFGChannel() == nil and not UI.head.status.__text:find("Listening", 1, true), "without the channel the header stops claiming it")
W.channels.LookingForGroup = 4
W.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED")
S.advance(0.3)
check(UI.head.status.__text:find("Listening to LookingForGroup", 1, true), "and says it again when the channel is back")
check(UI.head.net.label.__text == "Network " .. PL:GetNetworkStatus().nodes, "the network badge counts the nodes heard")

-- The radar from real entries
local radar = page.radar
local spin = radar.spin
local turn = spin.__anims[1]
check(spin.__playing and spin.__looping == "REPEAT", "the sweep turns, looping")
check(turn.__kind == "Rotation" and turn.__degrees == -360 and near(turn.__duration, 4) and turn.__origin[1] == "CENTER",
	"one clockwise turn every 4 s around the centre")
check(radar.sweep.__texture == MEDIA_PREFIX .. "radar-sweep", "the sweep is the conic texture")
local entries = PL:GetEntries()
check(#radar.list == #entries, "a blip per visible entry (" .. #radar.list .. "/" .. #entries .. ")")
local anaBlip, davi = radar.byId["ana lima"], radar.byId["davi melo"]
check(anaBlip and davi and near(anaBlip.dot.__color[1], UI.T.lfm[1]), "blips are keyed by entry and coloured by kind")
local caio = radar.byId["caio nunes"]
check(caio and near(caio.dot.__color[3], UI.T.lfg[3]), "a player looking for a group is a blue blip")
local function angleOf(b) return b.angle end
check(angleOf(anaBlip) < 0.25, "a dungeon sits in the dungeon quarter")
S.advance(4.2)
local lit = 0
for _, b in ipairs(radar.list) do if plays(b.glow) > 0 then lit = lit + 1 end end
check(lit == #radar.list, "every blip lights up as the sweep passes it (" .. lit .. "/" .. #radar.list .. ")")
check(page.groups.value.__text == tostring(PL:GetCounts().total) and page.needYou.value.__text == tostring(PL:GetCounts().needsMe),
	"the numbers are the core's counts")

-- Cards from real entries
local anaRow = rowOf(page.list, function(e) return e.key == "ana lima" end)
if check(anaRow, "Ana's network listing has a card") then
	local b = anaRow.body
	check(b.activity.__text == "The Hall of Thanes" and b.kind.__text == "LFM", "the card names the activity and the kind")
	check(b.user.__shown, "and marks a fellow PartyLens user")
	check(b.pips.pips.heal.__shown and b.pips.pips.dps.__shown and not b.pips.pips.tank.__shown,
		"the pips are the roles still missing from the network's group (1 heal, 1 dps)")
	check(b.fill.__text == "3/5", "and the group size from the listing")
end
local daviRow = rowOf(page.list, function(e) return e.key == "davi melo" end)
check(daviRow and daviRow.body.line.__text:find("Davi Melo", 1, true) and daviRow.body.action.label.__text == "Whisper",
	"a chat post: the leader by full name and Whisper")
local caioRow = rowOf(page.list, function(e) return e.key == "caio nunes" end)
check(caioRow and caioRow.body.action.label.__text == "Invite", "a player looking for a group: Invite")
noErrors("drawing the radar and the cards")

-- A new person arrives
S.advance(11)
W.channelLine("LFM Ruins of Lordaeron need a healer", "Elza Dias", "Player-1-0102")
S.advance(0.3)
local blip = radar.byId["elza dias"]
check(blip and plays(blip.motion and blip.motion.pop) == 1, "the new entry's blip pops in")
check(blip and plays(blip.halo.motion and blip.halo.motion.ripple) == 1, "with a halo")
local card = rowOf(page.list, function(e) return e.key == "elza dias" end)
if check(card, "the new entry has a card") then
	local slide = card.body.motion and card.body.motion.slide
	check(slide and plays(slide) == 1 and slide.move.__offset[1] == -12 and near(slide.move.__duration, 0.25),
		"the card slides 12 px in over 0.25 s")
	check(slide and slide.alpha.__from == 0, "with a fade")
	local wash = card.body.wash.motion and card.body.wash.motion.flash
	check(wash and plays(wash) == 1 and near(wash.alpha.__duration, 2), "and an amber edge that fades over 2 s")
	local pip = card.body.pips.pips.heal
	check(pip.__shown and plays(pip.motion and pip.motion.pulse) == 1, "the healer pip pulses once: the core says it needs my role")
end
local toast = UI.toast
check(toast.__shown and toast.title.__text:find("needs you", 1, true), "a toast says the group needs me")
check(plays(toast.motion and toast.motion.slide) == 1 and toast.motion.slide.move.__offset[2] == -18, "the toast drops from the top")
S.advance(5)
check(not toast.__shown, "and leaves by itself")
noErrors("a new entry arriving")
noViolations("entries arriving")

-- Whisper from the card: a click, Sent with a green flash, then the core's contacted mark
card = rowOf(page.list, function(e) return e.key == "elza dias" end)
if check(card, "Elza's card is still listed") then
	local act = card.body.action
	click(act)
	check(W.chat[#W.chat] and W.chat[#W.chat].chatType == "WHISPER" and W.chat[#W.chat].target == "Elza Dias",
		"Whisper sends the core's whisper to her full name")
	check(act.label.__text == "Sent" and plays(act.flash.motion and act.flash.motion.flash) == 1, "Whisper turns into Sent with a flash")
	check(act.flash.__layer ~= "OVERLAY", "the flash sits under the label, not over it")
	UI:Refresh(true)
	check(act.label.__text == "Sent", "a refresh in the meantime keeps Sent")
	S.advance(3)
	card = rowOf(page.list, function(e) return e.key == "elza dias" end)
	check(card and card.body.action.label.__text == "Whispered", "then the card says she was whispered")
end
check(toast.__shown and toast.title.__text:find("Elza Dias", 1, true), "the core's notice shows as a toast")
-- Invite a player looking for a group
caioRow = rowOf(page.list, function(e) return e.key == "caio nunes" end)
if caioRow then
	click(caioRow.body.action)
	check(W.invites[#W.invites] == "Caio Nunes", "Invite invites the player by full name")
end
-- The more menu: who, block
local fabi = rowOf(page.list, function(e) return e.key == "fabi reis" end)
if check(fabi, "Fabi's card is listed") then
	click(fabi.body.more)
	menuPick("Who is this?")
	check(W.whos[#W.whos] and W.whos[#W.whos]:find("Fabi", 1, true), "Who looks the player up, from the menu's click")
	click(fabi.body.more)
	menuPick("Block this player")
	S.advance(0.3)
	check(PL.db.blacklist["fabi reis"] and not rowOf(page.list, function(e) return e.key == "fabi reis" end),
		"Block takes the player off the radar")
end
noViolations("acting on cards")

-- Links in a post stay links; a stray pipe shows as a pipe and starts nothing.
local LINK = "|cffffff00|Hquest:123:20|h[Elite Ogres]|h|r"
check(UI.Esc("LFM " .. LINK .. " go") == "LFM " .. LINK .. " go|r", "a quest link and its colour pass through intact")
check(UI.Esc("a|b ||c |Hx |cnope") == "a||b ||c ||Hx ||cnope", "stray and malformed pipes are escaped, an escaped one kept")
check(UI.Esc("|cff00ff00green") == "|cff00ff00green|r", "a colour left open is closed at the end of the line")
W.channelLine("LFM " .. LINK .. " need heal", "Olga Rui", "")
W.channelLine("LFM RoL tank|dps need heal", "Pia Nox", "")
S.advance(0.3)
local olga = rowOf(page.list, function(e) return e.key == "olga rui" end)
check(olga and olga.body.line.__text:find(LINK, 1, true), "a card shows the quest link from the chat line as a link")
local pia = rowOf(page.list, function(e) return e.key == "pia nox" end)
check(pia and pia.body.line.__text:find("tank||dps", 1, true), "and a lone pipe as a pipe")

-- Filters persist through PartyLens:Set
local F = PL.db.filters
click(page.roleChips.tank)
check(F.roles.tank == true, "the tank chip sets db.filters.roles.tank")
check(#page.list.items == #PL:GetEntries(), "and the list is the core's filtered entries")
click(page.roleChips.tank)
click(page.kind.segments[3])
check(F.type == "lfg" and #page.list.items == #PL:GetEntries(), "LFG sets db.filters.type")
click(page.kind.segments[1])
click(page.activity)
menuPick("Wailing Caverns  17-24")
check(F.activity == "wc" or (F.activity ~= "" and F.activityType == "all"), "an activity sets db.filters.activity (" .. tostring(F.activity) .. ")")
click(page.activity)
menuPick("Raids")
check(F.activity == "" and F.activityType == "raid", "a kind of content sets db.filters.activityType")
click(page.activity)
menuPick("Any activity")
typeInto(page.search, "lordaeron")
check(F.query == "lordaeron" and #page.list.items == #PL:GetEntries(), "typing sets db.filters.query")
click(page.open)
check(F.onlyOpen == false, "Open only sets db.filters.onlyOpen")
F.query, F.type = "zzz-none", "all"
UI:Refresh(true)
check(page.list.empty.__shown and page.list.empty.title.__text == "No group matches these filters", "no match: the filter empty state")
click(page.list.empty.action)
check(F.query == "" and F.onlyOpen == true and F.type == "all" and F.activityType == "all", "Clear filters puts the defaults back")
noErrors("the filters")

-- Every page, with the crossfade
for _, key in ipairs(PAGES) do
	local prev = UI.pageFrames[UI.current]
	local p = UI:Open(key)
	check(UI.current == key and p.__shown and p.built, "page '" .. key .. "' builds and shows")
	if prev and prev ~= p then
		check(plays(p.motion.fade) > 0 and near(p.motion.fade.alpha.__duration, 0.15), "page '" .. key .. "' fades in over 0.15 s")
		S.advance(0.2)
		check(not prev.__shown, "the page before '" .. key .. "' is hidden after the crossfade")
	end
	noErrors("drawing page '" .. key .. "'")
end

-- A crossfade cut short. Closing the window stops its fades without OnFinished: the page that was fading out
-- must not stay on screen at alpha 0 (its buttons would take clicks).
UI:Open("groups")
S.advance(0.3)
local gpage, npage = UI.pageFrames.groups, UI.pageFrames.network
UI:Open("network")
UI:Close()
check(not gpage.__shown, "closing mid-crossfade: the page fading out is hidden at once")
UI:Open()
check(not gpage.__shown and npage.__shown and npage.__alpha == 1, "and reopening shows only the new page, fully")
-- A fade stopped any other way: the next page switch clears whatever is left over.
UI:Open("summon")
S.advance(0.3)
UI:Open("layer")
local spage = UI.pageFrames.summon
S.interrupt(spage)
check(spage.__shown and spage.__alpha == 0, "a fade stopped half way leaves its page shown at alpha 0")
UI:Open("settings")
check(not spage.__shown, "the next page switch hides it")
S.advance(0.3)
local stray = 0
for k, p in pairs(UI.pageFrames) do if k ~= "settings" and p.__shown then stray = stray + 1 end end
check(stray == 0 and UI.pageFrames.settings.__alpha == 1, "only the current page is on screen")

-- Sidebar indicator slides
UI:Open("groups")
S.advance(0.3)
UI:Open("settings")
check(plays(UI.indicator.motion and UI.indicator.motion.slide) > 0, "the sidebar indicator slides to the page")
S.advance(0.3)
local _, _, _, _, iy = UI.indicator:GetPoint(1)
check(iy == UI.nav.settings.__points[1][5], "and lands on the active item")

--------------------------------------------------------------------------------
-- Announce: the draft, the post, the network listing, the suggestions
--------------------------------------------------------------------------------
local ap = UI:Open("announce")
S.advance(0.3)
click(ap.activity)
menuPick("Ruins of Lordaeron (new)")
local s = PL:GetListing()
check(s.activity ~= "" and s.name == "Ruins of Lordaeron", "picking an activity sets the draft (" .. tostring(s.activity) .. ")")
local want = PL:DefaultWant(s.activity)
check(s.want.tank == want.tank and s.want.dps == want.dps, "sized by the core's default for it")
click(ap.steppers.dps.plus)
check(PL:GetListing().want.dps == want.dps + 1, "a stepper sets want")
click(ap.steppers.dps.minus)
-- Off the air, the draft follows the typing (no Enter, the focus still in the box) and so does the preview.
local function typeKeys(edit, text)
	edit:SetFocus()
	for i = 1, #text do
		edit.__text = text:sub(1, i)
		S.fire(edit, "OnTextChanged", true)
	end
end
typeKeys(ap.comment, "summons ready")
S.advance(0.2)
check(PL:GetListing().comment == "summons ready", "off the air, the comment is saved as it is typed")
check(ap.quote.text.__text == PL:BuildPost() and ap.quote.text.__text:find("summons ready", 1, true),
	"and the preview, the core's post, follows each key")
check(ap.missing.__text:find("missing", 1, true), "and what is still missing")
S.fire(ap.comment, "OnEscapePressed")
local chatBefore = #W.chat
click(ap.post)
check(#W.chat == chatBefore + 1 and W.chat[#W.chat].chatType == "CHANNEL" and W.chat[#W.chat].msg:find("Ruins of Lordaeron", 1, true),
	"Post sends the line to the LookingForGroup channel, from the click")
check(PL:GetListing().active and ap.post.label.__text == "Posted", "and starts the listing")
S.advance(0.3)
check(UI.nav.announce.badge.__text == "live", "the sidebar says the listing is live")
check(ap.listing.label.__text == "Stop listing", "the listing button offers to stop it")
click(ap.post)
check(ap.post.label.__text == "Wait a moment", "posting again right away: the core's cooldown, in words")
-- On the air, typing never republishes per key: it is saved once it pauses.
S.advance(16)
local sentBefore = #W.sentWhere({ prefix = "PartyLens" })
typeKeys(ap.comment, "fast run")
S.advance(0.3)
check(#W.sentWhere({ prefix = "PartyLens" }) == sentBefore and PL:GetListing().comment == "summons ready",
	"on the air, typing sends nothing per key")
S.advance(1)
check(PL:GetListing().comment == "fast run" and #W.sentWhere({ prefix = "PartyLens" }) > sentBefore,
	"a pause saves it once: one network update")
UI:Refresh(true)
check(ap.quote.text.__text:find("fast run", 1, true), "and the preview follows")
-- A click on Post may leave the focus in the box: Post takes what the box shows, before any pause or Enter.
typeKeys(ap.comment, "last call")
click(ap.post)
check(W.chat[#W.chat].chatType == "CHANNEL" and W.chat[#W.chat].msg:find("last call", 1, true),
	"Post sends the text in the box, even typed a moment ago")
check(PL:GetListing().comment == "last call", "and saves it in the same click")
S.fire(ap.comment, "OnEscapePressed")
S.advance(16)
-- Suggestions: players who fill the missing roles, with Invite and Whisper
W.channelLine("LFG RoL tank warrior", "Ivo Sol", "")
S.advance(6)
local sug = rowOf(ap.suggest, function(x) return x.entry.name == "Ivo Sol" end)
if check(sug, "the autopilot suggests the tank looking for a group") then
	check(sug.main.label.__text == "Invite" and sug.whisper.__shown, "with Invite and Whisper")
	click(sug.main)
	check(W.invites[#W.invites] == "Ivo Sol", "Invite invites him, from the click")
	click(sug.dismiss)
	S.advance(0.3)
	check(not rowOf(ap.suggest, function(x) return x.entry.name == "Ivo Sol" end), "dismissing takes him off the list")
end
click(ap.listing)
check(not PL:GetListing().active, "Stop listing stops it")
S.advance(0.3)
click(ap.listing)
check(PL:GetListing().active and #W.sentWhere({ prefix = "PartyLens" }) > sentBefore, "List on the network starts it, from the click")
S.advance(0.3)
click(ap.listing)
check(not PL:GetListing().active, "and stops it again")
click(ap.kind.segments[2])
check(PL:GetListing().type == "lfg", "the kind switch sets the draft to LFG")
UI:Refresh(true)
check(ap.myRoles.heal.__shown and not ap.steppers.tank.__shown, "an LFG draft shows my roles, not the group size")
click(ap.kind.segments[1])
-- The inter-addon API opens Announce with its context
PL.API.StartQuestGroup({ stepText = "Elite ogres" })
check(UI.current == "announce" and ap.context and ap.context.label == "Elite ogres", "the API opens Announce with its context")
S.advance(0.3)
check(ap.label.__shown and ap.label.__text == "Elite ogres", "a quest draft shows its label")
noErrors("the announce page")
noViolations("the announce page")

--------------------------------------------------------------------------------
-- Layer: layers, not people. Go to a layer through its beacon; my beacon, its rank and its prompt.
--------------------------------------------------------------------------------
local function textsUnder(root)
	local out = {}
	for _, o in ipairs(S.descendants(root)) do
		if o.__text and o.__shown ~= false then out[#out + 1] = o.__text end
	end
	return table.concat(out, " | ")
end
local lp = UI:Open("layer")
S.advance(0.3)
local function layerRow(zoneUID) return rowOf(lp.layers, function(it) return it.zoneUID == zoneUID end) end
check(lp.card.number.__text == "1", "my layer: the first of the layers known here")
local mineRow, anaRow, gilRow = layerRow(101), layerRow(202), layerRow(303)
check(mineRow and mineRow.here.__shown and not mineRow.go.__shown and mineRow.zone.__text == "You are here",
	"my layer's row says I am here, with no button")
check(anaRow and anaRow.title.__text == "Another layer" and anaRow.pop.__text == "1 player heard"
	and anaRow.beacons.__text:find("1 beacon", 1, true) and anaRow.beacons.__text:find("1 group forming", 1, true),
	"layer 202: unnumbered (never seen), one player, one beacon, her group forming")
check(gilRow and gilRow.beacons.__text == "No beacon" and gilRow.go.__enabled == false, "layer 303: no beacon, no asking")
check(layerRow(404) and layerRow(404).title.__text == "Layer 1" and layerRow(404).go.__enabled == false,
	"another zone's layer is listed, numbered there, not askable from here")
local seen = textsUnder(lp)
check(not seen:find("Ana Lima", 1, true) and not seen:find("Gil Paz", 1, true) and not seen:find("Hugo Luz", 1, true),
	"no name anywhere on the page")
local b = lp.beacon
check(b.rank.__text == "Spark" and b.hops.__text == "0 brought over, 0 today" and b.next.__text == "3 more to Lantern",
	"my beacon: first rank, nothing yet, 3 to the next")
check(b.duty.__text:find("On duty", 1, true) and b.toggle.checked, "on duty by default")
if check(anaRow, "Ana's layer has a row") then
	click(anaRow.go)
	check(PL:GetMyLayerRequest() and PL:GetMyLayerRequest().state == "sent", "Go here asks its beacon, from the click")
	S.advance(0.3)
	check(lp.card.ring.__shown and lp.card.ring.__scripts.OnUpdate and lp.card.wait.__text == "Asking a beacon",
		"the ring runs while a beacon is asked")
	S.advance(10)
	local frac = lp.card.ring.fill.__radial or 0
	check(frac > 0.2 and frac < 0.32, "after 10 s of 40 the ring is a quarter full (" .. frac .. ")")
	W.deliver("PLLnet", "PLL2|A|1453|202", "WHISPER", "Ana Lima-ClassicBetaPvE2")
	S.advance(0.3)
	check(lp.card.wait.__text == "A beacon is inviting you" and plays(lp.card.halo.motion and lp.card.halo.motion.ripple) == 1,
		"its accept: the ring flashes once")
	W.setGroup({ { name = "Ana", surname = "Lima" } })
	S.advance(0.3)
	check(lp.card.wait.__text == "In the beacon's group" and lp.card.waitSub.__text:find("switch prompt", 1, true)
		and lp.card.ring.__scripts.OnUpdate, "in the beacon's group: click the game's switch prompt or wait, the ring runs")
	W.npc("target", 202)
	W.fire("PLAYER_TARGET_CHANGED")
	S.advance(0.3)
	check(PL:GetMyLayerRequest().state == "hopped" and lp.card.wait.__text == "On the new layer", "on the new layer")
	check(lp.card.action.__shown and lp.card.action.label.__text == "Leave group", "with a button to leave the group")
	click(lp.card.action)
	check(#W.left == 1, "leaving the group, from the click")
	W.setGroup({})
end
-- Someone asks for my layer: the prompt drops from the top of the screen, window open or not.
UI:Close()
W.deliver("PLLnet", "PLL2|R|1453|303|202", "WHISPER", "Jon Mar-ClassicBetaPvE2")
S.advance(0.3)
local prompt = UI.prompt
check(prompt and prompt.__shown and prompt:GetParent() == UIParent and prompt.title.__text == "Jon Mar wants your layer"
	and prompt.actions[1].__shown, "a request with the window closed: a prompt on the screen with Invite")
W.deliver("PLLnet", "PLL2|R|1453|303|202", "WHISPER", "Kai Rio-ClassicBetaPvE2")
S.advance(0.3)
check(prompt.title.__text == "Jon Mar wants your layer" and prompt.body.__text:find("1 more waiting", 1, true),
	"a second one waits behind the first")
click(prompt.actions[1])
local function reqOf(name)
	for _, r in ipairs(PL:GetLayerRequests()) do if r.name == name then return r end end
end
check(W.invites[#W.invites] == "Jon Mar" and reqOf("Jon Mar").state == "invited", "Invite serves it, from its click")
S.advance(0.6)
check(prompt.__shown and prompt.title.__text == "Kai Rio wants your layer", "then the next one shows")
click(prompt.actions[2])
check(reqOf("Kai Rio").state == "declined", "Decline declines it")
S.advance(0.6)
check(not prompt.__shown or prompt.__alpha == 0, "and with none left the prompt goes")
lp = UI:Open("layer")
S.advance(0.3)
W.setGroup({ { name = "Jon", surname = "Mar" } })
S.advance(0.3)
check(plays(lp.beacon.plus.motion and lp.beacon.plus.motion.float) == 0, "his joining alone is no hop yet")
check(lp.beacon.undo.__shown, "but he is my hopper: the card can remove him")
W.deliver("PLLnet", "PLL2|T|1453|202", "WHISPER", "Jon Mar-ClassicBetaPvE2")
S.advance(0.3)
check(plays(lp.beacon.plus.motion and lp.beacon.plus.motion.float) == 1, "his arrival throws a +1 off the light")
check(lp.beacon.hops.__text == "1 brought over, 1 today" and lp.beacon.next.__text == "2 more to Lantern", "and counts")
check(lp.beacon.undo.__shown, "the beacon card offers to remove him")
click(lp.beacon.undo)
check(W.uninvites[#W.uninvites] == "Jon Mar", "remove uninvites him, from the click")
W.setGroup({})
-- A new rank ripples
PL.db.beacon.hops = 2
W.deliver("PLLnet", "PLL2|R|1453|303|202", "WHISPER", "Lia Sol-ClassicBetaPvE2")
S.advance(0.3)
check(lp.beacon.serve.__shown and lp.beacon.serve.label.__text == "Invite next (1)", "Invite next shows the queue")
click(lp.beacon.serve)
check(W.invites[#W.invites] == "Lia Sol", "and serves it, from the click")
W.setGroup({ { name = "Lia", surname = "Sol" } })
W.deliver("PLLnet", "PLL2|T|1453|202", "WHISPER", "Lia Sol-ClassicBetaPvE2")
S.advance(0.3)
check(lp.beacon.rank.__text == "Lantern" and plays(lp.beacon.halo.motion and lp.beacon.halo.motion.ripple) >= 1,
	"the third hop is Lantern, with a ripple")
W.setGroup({})
-- Off
click(lp.beacon.toggle)
S.advance(0.3)
check(PL.db.beacon.on == false and lp.beacon.duty.__text:find("Off", 1, true), "the toggle turns the beacon off")
click(lp.beacon.toggle)
check(PL.db.beacon.on == true, "and on again")
-- The API opens the Layer page on a layer
PL.API.RequestLayer(1453, 202)
S.advance(0.3)
check(UI.current == "layer" and lp.context and lp.context.zoneUID == 202, "the API opens Layer with its context")
noErrors("the layer page")
noViolations("the layer page")

--------------------------------------------------------------------------------
-- Summon, network, settings
--------------------------------------------------------------------------------
W.setGroup({
	{ name = "Ana", surname = "Lima", class = "DRUID", dist = 10 },
	{ name = "Bia", surname = "Rocha", class = "MAGE", dist = 300 },
	{ name = "Davi", surname = "Melo", class = "WARLOCK", dist = 5 },
})
local sp = UI:Open("summon")
S.advance(0.3)
local bia = rowOf(sp.list, function(m) return m.name == "Bia Rocha" end)
check(bia and bia.state.__text == "needs a summon" and bia.mark.__shown, "the far member needs a summon, with a mark button")
check(sp.warlocks.__text:find("Davi Melo", 1, true), "the warlock close by is named")
check(UI.nav.summon.badge.__text == "1", "the sidebar counts who needs a summon")
click(sp.announce)
check(W.chat[#W.chat].chatType == "PARTY" and W.chat[#W.chat].msg:find("Bia Rocha", 1, true), "Ask for a summon posts in party chat, from the click")
click(bia.mark)
S.advance(0.3)
bia = rowOf(sp.list, function(m) return m.name == "Bia Rocha" end)
check(bia and bia.state.__text == "summoned" and #PL:GetSummon().needed == 0, "marking her summoned")
click(sp.next)
check(W.chat[#W.chat].msg:find("everyone is here", 1, true), "Next one says everyone is here")
W.setGroup({})
S.advance(0.3)
check(sp.list.empty.__shown and sp.list.empty.title.__text == "You are not in a group", "alone: the empty state says so")

local np = UI:Open("network")
S.advance(0.3)
local st = PL:GetNetworkStatus()
check(np.stats[1].value.__text == tostring(st.nodes) and np.stats[3].value.__text == tostring(st.directory),
	"the numbers are the core's network status")
check(np.buses.__text:find("realm directory", 1, true), "and which ways out work")
check(np.addons.__text:find("PartyLens %d"), "counts per addon")
check(not np.list and not np.addons.__text:find("Gil Paz", 1, true), "and no names of who was heard")

local setp = UI:Open("settings")
S.advance(0.3)
click(setp.roles.tank)
check(PL.db.roles.tank == true, "a role chip sets db.roles")
click(setp.spam)
check(PL.db.filters.hideSpam == false, "Hide spam sets db.filters.hideSpam")
click(setp.join)
check(PL.db.joinLFGChannel == false, "joining LookingForGroup is db.joinLFGChannel")
click(setp.alert)
check(PL.db.alertOnMatch == true, "the sound is db.alertOnMatch")
typeInto(setp.comment, "have summons")
check(PL.db.comment == "have summons", "the whisper note is db.comment")
typeInto(setp.template, "Hi {name}, {role} here")
check(PL.db.whisperTemplate == "Hi {name}, {role} here", "the whisper is db.whisperTemplate")
S.advance(0.3)
local blocked = rowOf(setp.blocked, function(b) return b.key == "fabi reis" end)
if check(blocked, "the blocked player is listed") then
	click(blocked.unblock)
	check(PL.db.blacklist["fabi reis"] == nil, "Unblock unblocks")
end
PL:Block(entryNamed("Bia Rocha"))
S.advance(0.3)
click(setp.clear)
check(setp.clear.label.__text == "Click again to unblock" and next(PL.db.blacklist) ~= nil, "the first click asks to confirm")
click(setp.clear)
check(next(PL.db.blacklist) == nil, "the second click unblocks everyone")
noErrors("summon, network and settings")
noViolations("summon, network and settings")

-- Notices with the window closed go to chat; a group that needs me plays the sound
UI:Close()
local printed = #W.printed
PL:Notice("hello there")
check(#W.printed == printed + 1 and W.printed[#W.printed]:find("hello there", 1, true), "a notice with the window closed is a chat line")
W.channelLine("LFM Wailing Caverns need heal", "Lia Vale", "")
check(S.sounds[#S.sounds] == 8960, "a group that needs me plays the sound while the window is closed (alertOnMatch)")
PL:Toggle()

-- Fuzz every page, with the core behind it
local total = 0
for _, key in ipairs(PAGES) do
	UI:Open(key)
	S.advance(0.3)
	total = total + fuzz(key)
	noErrors("clicking everything on '" .. key .. "'")
	noViolations("clicking everything on '" .. key .. "'")
end
check(total > 60, "the fuzz reached the controls (" .. total .. " clicks)")
S.advance(130)
noViolations("two minutes after the clicks")
check(UI.Motion.On(), "the fuzz left animations on for the next part")

-- Buttons press at 0.96 for 0.08 s
ap = UI:Open("announce")
S.fire(ap.post, "OnMouseDown", "LeftButton")
local press = ap.post.motion and ap.post.motion.press
check(press and plays(press) >= 1, "a button press plays the scale")
if press then
	local down, up = press.__anims[1], press.__anims[2]
	check(down.__kind == "Scale" and near(down.__to[1], 0.96) and near(down.__duration, 0.08), "down to 0.96 in 0.08 s")
	check(up.__order == 2 and near(up.__to[1] * 0.96, 1), "and back to 1")
end
S.fire(ap.post, "OnMouseUp", "LeftButton")

-- Dragging the window saves its place in db.ui
win:ClearAllPoints()
win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 120, 700)
S.fire(UI.head, "OnDragStart")
S.fire(UI.head, "OnDragStop")
local pos = PL.db.ui.pos
check(pos and pos[1] == "TOPLEFT" and pos[2] == "BOTTOMLEFT" and pos[3] == 120 and pos[4] == 700, "the window position is saved (db.ui.pos)")
win:ClearAllPoints()
UI:RestorePosition()
local p1, rel, p2, wx, wy = win:GetPoint(1)
check(p1 == "TOPLEFT" and rel == UIParent and p2 == "BOTTOMLEFT" and wx == 120 and wy == 700, "and restored")
win:Hide()
check(not UI:IsOpen(), "hiding the window (what Esc does) closes it")

-- Minimap button
S.cursor = { x = 1800, y = 1000 }
S.fire(mm, "OnDragStart")
S.advance(0.1)
S.fire(mm, "OnDragStop")
check(math.abs(PL.db.minimap.angle - 90) < 0.01, "dragging the minimap button saves its angle (db.minimap.angle)")
local _, _, _, mx, my = mm:GetPoint(1)
check(math.abs(mx) < 0.01 and my > 70, "and puts it on the minimap edge at that angle")
click(mm)
check(UI:IsOpen(), "a click on it opens the window (through PartyLens:Toggle)")
click(mm)
check(not UI:IsOpen(), "another closes it")
click(mm, "RightButton")
setp = UI.pageFrames.settings
check(UI:IsOpen() and UI.current == "settings", "a right click opens Settings")
UI:SetSetting("minimapHidden", false)
UI:Refresh(true)
click(setp.minimap)
check(not mm.__shown and PL.db.minimap.hide == true, "Settings hides the minimap button (db.minimap.hide)")
click(setp.minimap)
check(mm.__shown, "and shows it again")
noErrors("minimap button and settings")

-- A burst: only the newest few animate. With the window closed nothing piles up for when it opens.
local function popsAndSlides()
	local pops, slides = 0, 0
	for _, b in ipairs(radar.pool) do pops = pops + plays(b.motion and b.motion.pop) end
	for _, r in ipairs(page.list.rows) do slides = slides + plays(r.body and r.body.motion and r.body.motion.slide) end
	return pops, slides
end
UI:Open("groups")
UI.data.ClearFilters()
S.advance(0.3)
local p0 = popsAndSlides()
for i = 1, 12 do W.channelLine("LFM Wailing Caverns need dps " .. i, "Burst N" .. i, "") end
S.advance(0.3)
local p1 = popsAndSlides()
check(p1 - p0 <= 5 and p1 - p0 >= 1, "a burst of 12 arrivals pops only the newest few (" .. (p1 - p0) .. ")")
check(#page.pops == 0 and next(page.fresh) == nil, "and nothing is left queued after the redraw")
UI:Close()
for i = 1, 30 do W.channelLine("LFM Ragefire Chasm need dps " .. i, "Closed N" .. i, "") end
check(#page.pops == 0 and next(page.fresh) == nil, "arrivals while the window is closed queue no animation")
local q0, s0 = popsAndSlides()
UI:Open("groups")
S.advance(0.3)
local q1, s1 = popsAndSlides()
check(q1 == q0 and s1 == s0, "and opening it plays none of them")

--------------------------------------------------------------------------------
-- 2. Animations off from Settings: every state lands at once, nothing plays
--------------------------------------------------------------------------------
UI:Open("settings")
UI:Toast("Test", "a toast mid-motion")
check(UI.toast.motion.slide.__playing and UI.pageFrames.settings.motion.fade.__playing, "motion is under way")
click(setp.animations)
check(PL.db.animations == false and not UI.Motion.On(), "the Settings checkbox turns animations off (db.animations)")
check(not spin.__playing and radar.sweep.__rotation == 0, "the sweep stops, standing at twelve o'clock")
local playing = 0
for _, grp in ipairs(S.groups) do if grp.__playing then playing = playing + 1 end end
check(playing == 0, "no animation group is left playing (" .. playing .. ")")
S.plays, S.playLog = 0, {}

for _, key in ipairs(PAGES) do
	local prev = UI.pageFrames[UI.current]
	local p = UI:Open(key)
	check(p.__shown and p.__alpha == 1, "off: page '" .. key .. "' is there at once")
	if prev and prev ~= p then check(not prev.__shown, "off: the page before '" .. key .. "' is gone at once") end
	fuzz(key)
end
UI:Open("groups")
UI.data.ClearFilters()
W.channelLine("LFM Scarlet Monastery need heal", "Mia Lua", "")
S.advance(0.3)
local row = rowOf(page.list, function(e) return e.key == "mia lua" end)
if check(row, "off: the new entry has a card") then
	local _, _, _, bx = row.body:GetPoint(1)
	check(bx == 0 and row.body.__alpha == 1 and row.body.wash.__alpha == 0, "off: the card is in place, no edge glow")
	click(row.body.action)
	check(row.body.action.label.__text == "Sent", "off: Whisper still says Sent")
end
check(toast.__shown and toast.__alpha == 1, "off: the toast is there at once")
S.advance(5)
check(not toast.__shown, "off: and still leaves by itself")
for _, b in ipairs(radar.list) do
	if not near(b.dot.__alpha, 0.9) then check(false, "off: every blip simply lit") break end
end
local offenders = {}
for i = 1, math.min(5, #S.playLog) do
	local grp = S.playLog[i]
	offenders[#offenders + 1] = (grp.__anims and grp.__anims[1] and grp.__anims[1].__kind or grp.__kind)
end
check(S.plays == 0, "with animations off nothing plays (" .. S.plays .. " plays: " .. table.concat(offenders, ", ") .. ")")
noErrors("a full round with animations off")
noViolations("a full round with animations off")

UI:Open("settings")
click(setp.animations)
UI:Open("groups")
check(spin.__playing, "turning animations back on starts the sweep again")

-- Method names against the Forever API
local bad = {}
for key, used in pairs(S.used) do
	local kind, template = key:match("^([^<]+)<?([^>]*)>?$")
	local allowed, extra = Stub.ALLOWED[kind], Stub.TEMPLATES[template]
	for name in pairs(used) do
		if not (allowed and allowed[name]) and not (extra and extra[name]) then bad[#bad + 1] = key .. ":" .. name end
	end
end
table.sort(bad)
check(#bad == 0, "every widget method exists on Forever: " .. table.concat(bad, ", "))

-- Media the code actually painted
for path in pairs(S.textures) do
	if path:sub(1, #MEDIA_PREFIX) == MEDIA_PREFIX then
		local name = path:sub(#MEDIA_PREFIX + 1)
		check(isGenerated[name] and validTGA(name), "painted texture exists: Media/" .. name .. ".tga")
	else
		check(path == "Interface\\Buttons\\WHITE8x8", "only own media or WHITE8x8 are painted: " .. path)
	end
end
for path in pairs(S.fonts) do check(FONTS[path], "fonts are Friz Quadrata or Arial Narrow: " .. tostring(path)) end

-- Long text is bounded (a width, or anchored on both sides) so it wraps or truncates instead of running over
-- its neighbours. Measured at the stub's 0.5 em per character.
for _, key in ipairs(PAGES) do
	UI:Open(key)
	S.advance(0.3)
	for _, o in ipairs(S.descendants(UI.frame)) do
		if o.__kind == "FontString" and S.visible(o) and o.__text then
			if o:GetStringWidth() > 360 and not (o.__w > 0 or #o.__points >= 2) then
				check(false, "page '" .. key .. "': unbounded long text: " .. o.__text:sub(1, 60))
			end
		end
	end
end

-- Copy on screen
for _, t in ipairs(S.texts) do
	if t:find("%%[sd]") or t:find("nil", 1, true) then check(false, "no unformatted or nil text on screen: " .. t) break end
end

--------------------------------------------------------------------------------
-- 3. Saved with animations off: nothing ever plays from login on
--------------------------------------------------------------------------------
boot({ savedDB = { schemaVersion = 100, animations = false } })
S.plays = 0
PL:Toggle()
for _, key in ipairs(PAGES) do UI:Open(key); fuzz(key) end
W.channelLine("LFM Ruins of Lordaeron need dps", "Noa Paz", "")
S.advance(6)
check(S.plays == 0, "saved off: nothing plays from login on (" .. S.plays .. ")")
-- Distance from the centre is age: a post 15 minutes old sits half way out, a new one near the centre.
S.advance(900)
W.channelLine("LFM Ruins of Lordaeron need tank", "Rui Paz", "")
UI:Open("groups")
UI.data.ClearFilters() -- the fuzz left its own
UI:Refresh(true)
local r = UI.pageFrames.groups.radar
local function dist(id)
	local b = r.byId[id]
	if not b then return -1 end
	local _, _, _, x, y = b:GetPoint(1)
	return math.sqrt(x * x + y * y) / r.reach
end
local old, new = dist("noa paz"), dist("rui paz")
check(new >= 0 and new < 0.15 and math.abs(old - (0.12 + 0.88 * 0.5)) < 0.03,
	"blips move out with age: new near the centre, 15 min half way (" .. old .. ", " .. new .. ")")
check(not UI.pageFrames.groups.radar.spin.__playing, "saved off: the sweep never starts")
noErrors("a session with animations saved off")
noViolations("a session with animations saved off")

--------------------------------------------------------------------------------
-- 4. Portuguese client
--------------------------------------------------------------------------------
for key, file in pairs(keys) do
	local pt = UI.TRANSLATIONS.ptBR[key]
	check(pt, "ptBR has \"" .. key .. "\" (" .. file .. ")")
	local ok, why = copyOK(key)
	check(ok, "copy rule on \"" .. key .. "\": " .. tostring(why))
	if pt then
		ok, why = copyOK(pt)
		check(ok, "copy rule on ptBR \"" .. pt .. "\": " .. tostring(why))
		check(select(2, key:gsub("%%", "")) == select(2, pt:gsub("%%", "")), "ptBR keeps the format codes of \"" .. key .. "\"")
	end
	check(_G.PartyLens_Localization.Strings.enUS[key] == nil, "the UI key \"" .. key .. "\" never shadows a core key")
end
for key in pairs(UI.TRANSLATIONS.ptBR) do check(keys[key], "ptBR line still used: \"" .. key .. "\"") end

boot({ locale = "ptBR", channels = { Geral = 1, ["Comércio"] = 2, ProcurandoGrupo = 5 } })
PL:Toggle()
check(UI.head.status.__text:find("Ouvindo ProcurandoGrupo", 1, true), "a ptBR header names the channel as the client does")
check(UI.nav.groups.label.__text == "Grupos" and UI.nav.settings.label.__text == "Ajustes", "a Portuguese client reads Grupos and Ajustes")
check(UI.pageFrames.groups.radar.sectors[1].__text == "Masmorras", "and the core's own words where the UI reuses them")
for _, key in ipairs(PAGES) do UI:Open(key); fuzz(key) end
noErrors("every page in Portuguese")
noViolations("every page in Portuguese")

--------------------------------------------------------------------------------
-- 5. Another addon's leaked global L (an AceLocale table raises on a missing key) is never read
--------------------------------------------------------------------------------
local reads = 0
local leaked = setmetatable({}, { __index = function(_, k)
	reads = reads + 1
	error("AceLocale-3.0: missing entry for '" .. tostring(k) .. "'")
end })
boot({ locale = "ptBR", globalL = leaked })
check(rawget(_G, "L") == leaked, "the leaked L is in place while the UI loads")
PL:Toggle()
for _, key in ipairs(PAGES) do UI:Open(key) end
check(reads == 0 and UI.nav.groups.label.__text == "Grupos", "the UI never reads it: its own strings, through the core")
noErrors("a leaked global L")

print(string.format("partylens ui: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
