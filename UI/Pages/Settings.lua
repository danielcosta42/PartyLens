--=============================================================================
-- Settings: the interface (animations, minimap button: UI-owned keys), the radar, my roles, the whisper and
-- the block list. Core keys go through PartyLens:Set (contract section 2); text fields commit on Enter or blur.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local COL = 330
local ROLE_NAME = { tank = L["ROLE_TANK"], heal = L["ROLE_HEAL"], dps = L["ROLE_DPS"] }

local function CreateBlocked(row)
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.name = UI.Text(row, "data", 13)
	row.name:SetPoint("LEFT", 12, 0)
	row.unblock = Kit.Button(row, L["Unblock"], "ghost", function() UI.data.Unblock(row.item.key) end, { h = 22 })
	row.unblock:SetPoint("RIGHT", -6, 0)
end

local function BindBlocked(row, b)
	row.name:SetText(UI.Esc(b.name or b.key))
end

local function Build(page)
	local D = UI.data
	Kit.PageHead(page, L["Settings"], L["Changes apply right away."])

	-- The left column stacks: each control goes under the last one.
	local y = -56
	local function stack(widget, gap)
		widget:SetPoint("TOPLEFT", 0, y)
		y = y - widget:GetHeight() - (gap or 12)
		return widget
	end
	local function section(text)
		local s = Kit.Section(page, text)
		s:SetWidth(COL)
		return stack(s, 10)
	end
	local function check(label, sub, get, set, gap)
		return stack(Kit.Check(page, label, get(), function(on) set(on) end, sub, COL), gap)
	end

	section(L["Interface"])
	page.animations = check(L["Animations"], L["Turn off to make every change instant. The radar stands still."],
		function() return UI:Setting("animations") end, function(on) UI:SetSetting("animations", on) end)
	page.minimap = check(L["Minimap button"],
		L["Drag it around the minimap. The addon menu next to it always lists PartyLens."],
		function() return not UI:Setting("minimapHidden") end, function(on) UI:SetSetting("minimapHidden", not on) end, 22)

	section(L["Radar"])
	page.spam = check(L["Hide spam"], L["Leaves out gold sellers, boosts and similar posts."],
		function() return D.Get("filters.hideSpam") end, function(on) D.Set("filters.hideSpam", on) end)
	page.join = check(L["Join LookingForGroup at login"],
		L["The radar reads that channel; without it only the network fills it."],
		function() return D.Get("joinLFGChannel") end, function(on) D.Set("joinLFGChannel", on) end)
	page.alert = check(L["Sound when a group needs my role"], L["Only while this window is closed."],
		function() return D.Get("alertOnMatch") end, function(on) D.Set("alertOnMatch", on) end, 22)

	section(L["Layer"])
	page.beacon = check(L["Be a beacon"],
		L["Players on other layers of your zone can ask to come to yours; you invite each one with a click."],
		function() return D.Beacon().on end, function(on) D.SetBeacon(on) end)

	-- Right column
	local rx = COL + 40
	y = -56
	local function rsection(text, at)
		local s = Kit.Section(page, text)
		s:SetPoint("TOPLEFT", rx, at)
		s:SetPoint("RIGHT", page, "RIGHT", 0, 0)
		return s
	end
	rsection(L["Roles I play"], y)
	page.roles = {}
	local x = rx
	for _, role in ipairs(Kit.ROLES) do
		local chip = Kit.Chip(page, { icon = "role-" .. role, label = ROLE_NAME[role], color = T.role[role],
			onToggle = function(on) D.SetRole(role, on) end })
		chip:SetPoint("TOPLEFT", x, y - 28)
		x = x + chip:GetWidth() + 8
		page.roles[role] = chip
	end
	local rolesWhy = UI.Text(page, "data", 12, T.muted)
	rolesWhy:SetPoint("TOPLEFT", rx, y - 60)
	rolesWhy:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	rolesWhy:SetText(L["Used to find groups that need you and to write your whispers."])

	rsection(L["Whisper"], y - 88)
	local w = UI.PAGE_W - rx
	page.comment = Kit.Edit(page, { w = w, placeholder = L["A note for every whisper, for example: have summons"],
		maxLetters = 80,
		onCommit = function(text) D.Set("comment", text) end })
	page.comment:SetPoint("TOPLEFT", rx, y - 114)
	page.template = Kit.Edit(page, { w = w, placeholder = L["Your own whisper (empty: the standard one)"],
		maxLetters = 200,
		onCommit = function(text) D.Set("whisperTemplate", text) end })
	page.template:SetPoint("TOPLEFT", rx, y - 144)
	local tokens = UI.Text(page, "data", 12, T.muted)
	tokens:SetPoint("TOPLEFT", rx, y - 174)
	tokens:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	tokens:SetText(L["Filled in: {name} {class} {level} {role} {activity} {comment}"])

	rsection(L["Blocked players"], y - 204)
	page.blocked = Kit.List(page, { rowHeight = 30, gap = 3, create = CreateBlocked, bind = BindBlocked, width = w - 12,
		viewHeight = 72, emptyTop = 4 })
	page.blocked:SetPoint("TOPLEFT", rx, y - 230)
	page.blocked:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.blocked:SetHeight(72)
	page.blocked:SetEmpty(L["Nobody blocked"], L["Block a player from the menu on their card."])
	page.clear = Kit.Button(page, L["Unblock everyone"], "danger", function(b)
		b:Confirm(L["Click again to unblock"], function() D.ClearBlocked() end)
	end, { h = 26 })
	page.clear:SetPoint("TOPLEFT", rx, y - 312)

	-- What the network does for me: rares in my zone, and summons for warlocks. Short labels, no sub-line: the
	-- column has room for three rows.
	rsection(L["Network"], y - 352)
	local function rcheck(label, at, get, set)
		local c = Kit.Check(page, label, get(), function(on) set(on) end, nil, w)
		c:SetPoint("TOPLEFT", rx, at)
		return c
	end
	page.rareNotify = rcheck(L["Tell me about rares in my zone"], y - 380,
		function() return D.Get("rares.notify") end, function(on) D.Set("rares.notify", on) end)
	page.rareShare = rcheck(L["Share the rares I see"], y - 406,
		function() return D.Get("rares.share") end, function(on) D.Set("rares.share", on) end)
	page.summonOffer = rcheck(L["Offer summons (warlocks)"], y - 432,
		function() return D.Get("summonNet.offer") end, function(on) D.Set("summonNet.offer", on) end)

	UI:OnSetting("animations", function(on) page.animations:SetChecked(on) end)
end

local function Refresh(page)
	local D = UI.data
	page.animations:SetChecked(UI:Setting("animations"))
	page.minimap:SetChecked(not UI:Setting("minimapHidden"))
	page.spam:SetChecked(D.Get("filters.hideSpam"))
	page.join:SetChecked(D.Get("joinLFGChannel"))
	page.alert:SetChecked(D.Get("alertOnMatch"))
	page.beacon:SetChecked(D.Beacon().on)
	page.rareNotify:SetChecked(D.Get("rares.notify"))
	page.rareShare:SetChecked(D.Get("rares.share"))
	page.summonOffer:SetChecked(D.Get("summonNet.offer"))
	local mine = D.MyRoles()
	for role, chip in pairs(page.roles) do chip:SetSelected(mine[role], true) end
	page.comment:SetValue(D.Get("comment") or "")
	page.template:SetValue(D.Get("whisperTemplate") or "")
	local blocked = D.Blocked()
	page.blocked:SetItems(blocked)
	page.clear:SetEnabled(#blocked > 0 or page.clear.rest ~= nil)
end

UI:RegisterPage("settings", {
	label = L["Settings"],
	icon = "icon-settings",
	build = Build,
	refresh = Refresh,
})
