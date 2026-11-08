--=============================================================================
-- PartyLens interface: namespace, tokens, fonts, settings and small painters.
--
-- The UI is one table, shared by every file under UI/ through the addon namespace and exposed as
-- _G.PartyLens_UI (the same "<Addon>_<Module>" convention Core.lua uses to find modules).
-- Identity (specs/forever/plan.md §5): deep slate surfaces told apart by a 1px line, amber for the radar,
-- the main action and "new", role colours used only as data. Friz Quadrata for titles and numbers,
-- Arial Narrow for data.
--=============================================================================
local ADDON, ns = ...
ADDON = ADDON or "PartyLens"
ns = ns or {}
local UI = ns.UI or {}
ns.UI = UI
_G.PartyLens_UI = UI

UI.ADDON = ADDON
UI.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
UI.WHITE = "Interface\\Buttons\\WHITE8x8"

local function rgb(hex)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- Tokens. `raised` and `lineHi` are the hover steps of panel and line; `well` sits under inputs.
local T = {
	bg = rgb("0F1626"), panel = rgb("172036"), raised = rgb("1E2943"), well = rgb("0B111E"),
	line = rgb("26324D"), lineHi = rgb("3A4A6E"),
	amber = rgb("FFB547"), onAmber = rgb("1B1406"),
	tank = rgb("5AA9FF"), heal = rgb("5BE39A"), dps = rgb("FF6B6B"),
	text = rgb("E8EEF8"), muted = rgb("8A96B0"), faint = rgb("5A6684"),
}
T.lfm, T.lfg = T.amber, T.tank -- group kind as colour: LFM amber, LFG blue
T.ok, T.bad = T.heal, T.dps
T.role = { tank = T.tank, heal = T.heal, dps = T.dps }
UI.T = T

-- Friz and Arial Narrow carry Latin glyphs only; other alphabets use the client's own font.
local LATIN = { enUS = true, enGB = true, ptBR = true, ptPT = true, deDE = true, frFR = true, esES = true,
	esMX = true, itIT = true }
local locale = GetLocale and GetLocale() or "enUS"
local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.FONT = {
	display = LATIN[locale] and "Fonts\\FRIZQT__.TTF" or fallback,
	data = LATIN[locale] and "Fonts\\ARIALN.TTF" or fallback,
}

function UI.Hex(c)
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
		math.floor(c[3] * 255 + 0.5))
end

-- '|' starts an escape sequence in WoW text: anything that came from chat or the network goes through here.
-- What a chat line legitimately carries stays: colour codes (|cAARRGGBB ... |r), links (|H...|h[text]|h) and
-- an already escaped pipe (||). Any other pipe is escaped, so it shows as a pipe and starts nothing. A colour
-- the line opened is closed at its end, so it never bleeds into what the UI writes after it.
function UI.Esc(s)
	s = tostring(s == nil and "" or s):gsub("%c", " ")
	local out, i, n, colour = {}, 1, #s, false
	while i <= n do
		local at = s:find("|", i, true)
		if not at then
			out[#out + 1] = s:sub(i)
			break
		end
		out[#out + 1] = s:sub(i, at - 1)
		local rest = s:sub(at)
		local keep = rest:match("^||") or rest:match("^|r") or rest:match("^|H[^|]+|h[^|]*|h")
		local c = rest:match("^|c%x%x%x%x%x%x%x%x")
		if c then
			keep, colour = c, true
		end
		out[#out + 1] = keep or "||"
		i = at + (keep and #keep or 1)
	end
	if colour then out[#out + 1] = "|r" end
	return table.concat(out)
end

function UI.ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then return { c.r, c.g, c.b } end
	return T.text
end

function UI.ClassName(name, classFile)
	return UI.Hex(UI.ClassColor(classFile)) .. UI.Esc(name) .. "|r"
end

-- "now", "40 s", "3 min", "2 h": how long ago, in a word or two.
function UI.Ago(seconds)
	local L = UI.L
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds < 10 then return L["now"] end
	if seconds < 60 then return string.format(L["%d s"], seconds) end
	if seconds < 3600 then return string.format(L["%d min"], math.floor(seconds / 60)) end
	return string.format(L["%d h"], math.floor(seconds / 3600))
end

--------------------------------------------------------------------------------
-- Settings the UI owns, where specs/forever/ui-contract.md section 2 puts them in PartyLensDB, read through
-- defaults, with listeners. db.ui is the UI's free table (window position, last page).
--------------------------------------------------------------------------------
local PATHS = {
	animations = { "animations" },
	minimapHidden = { "minimap", "hide" },
	minimapAngle = { "minimap", "angle" },
	pos = { "ui", "pos" },
	page = { "ui", "page" },
}
UI.DEFAULTS = { animations = true, page = "groups", minimapAngle = 225, minimapHidden = false }
local listeners = {}

-- The core's db once it is loaded (it may replace PartyLensDB on a schema change); before that, a scratch
-- table, so nothing written early ever shadows the saved variables.
local scratch = {}
local function Root()
	local pl = rawget(_G, "PartyLens")
	if type(pl) == "table" and type(pl.db) == "table" then return pl.db end
	local db = rawget(_G, "PartyLensDB")
	return type(db) == "table" and db or scratch
end

function UI:DB()
	local db = Root()
	if type(db.ui) ~= "table" then db.ui = {} end
	return db.ui
end

function UI:Setting(key)
	local t, path = Root(), PATHS[key]
	for i = 1, #path - 1 do
		t = t[path[i]]
		if type(t) ~= "table" then return self.DEFAULTS[key] end
	end
	local v = t[path[#path]]
	if v == nil then return self.DEFAULTS[key] end
	return v
end

-- `quiet`: store without telling the listeners (a value that changes every frame, like a drag).
function UI:SetSetting(key, value, quiet)
	local t, path = Root(), PATHS[key]
	for i = 1, #path - 1 do
		if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
		t = t[path[i]]
	end
	t[path[#path]] = value
	if quiet then return end
	for _, fn in ipairs(listeners[key] or {}) do fn(value) end
end

function UI:OnSetting(key, fn)
	listeners[key] = listeners[key] or {}
	table.insert(listeners[key], fn)
end

--------------------------------------------------------------------------------
-- Painters. Every region is created on our own frames; nothing touches a Blizzard frame.
--------------------------------------------------------------------------------
function UI.Fill(parent, c, a, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
	t:SetColorTexture(c[1], c[2], c[3], a or 1)
	return t
end

function UI.Tex(parent, name, size, c, a, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(UI.MEDIA .. name)
	if size then t:SetSize(size, size) end
	if c then t:SetVertexColor(c[1], c[2], c[3], a or 1) end
	return t
end

function UI.Paint(region, c, a)
	region:SetVertexColor(c[1], c[2], c[3], a or 1)
end

function UI.Text(parent, kind, size, c, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(kind == "display" and UI.FONT.display or UI.FONT.data, size or 12, "")
	c = c or T.text
	fs:SetTextColor(c[1], c[2], c[3], 1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	fs:SetShadowOffset(0, 0)
	return fs
end

function UI.TextColor(fs, c, a)
	fs:SetTextColor(c[1], c[2], c[3], a or 1)
end

-- A 1px rule. `vertical` makes it 1px wide.
function UI.Rule(parent, c, vertical, layer)
	local t = UI.Fill(parent, c or T.line, 1, layer or "BORDER")
	if vertical then t:SetWidth(1) else t:SetHeight(1) end
	return t
end

-- Flat surface with a 1px border; the frame must come from CreateFrame(..., "BackdropTemplate").
local BACKDROP = { bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 }
function UI.Backdrop(frame, bg, border, bgAlpha, borderAlpha)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bgAlpha or 1)
	border = border or T.line
	frame:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha or 1)
end
