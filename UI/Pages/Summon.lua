--=============================================================================
-- Summon: who in the group is far (or out of sight), the warlocks close by, marks for who already came, and the
-- announce in group chat (a click: visible chat needs one).
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local function State(m)
	if m.isPlayer then return L["you"], T.muted end
	if m.summoned then return L["summoned"], T.ok end
	if m.inRange then return L["here"], T.ok end
	return L["needs a summon"], T.amber
end

local function CreateMember(row)
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.dot = UI.Tex(row, "dot", 8, T.amber)
	row.dot:SetPoint("LEFT", 14, 0)
	row.name = UI.Text(row, "data", 13)
	row.name:SetPoint("LEFT", 32, 0)
	row.role = UI.Text(row, "data", 12, T.muted)
	row.role:SetPoint("LEFT", 230, 0)
	row.mark = Kit.Button(row, L["Mark summoned"], "ghost", function()
		local m = row.item
		UI.data.MarkSummoned(m.name, not m.summoned)
	end, { h = 24, minWidth = 120 })
	row.mark:SetPoint("RIGHT", -10, 0)
	row.state = UI.Text(row, "data", 12, T.amber, "RIGHT")
	row.state:SetPoint("RIGHT", row.mark, "LEFT", -14, 0)
end

local function BindMember(row, m)
	local text, color = State(m)
	row.name:SetText(UI.ClassName(m.name, m.classFile))
	row.role:SetText(m.isWarlock and L["warlock"] or "")
	row.state:SetText(text)
	UI.TextColor(row.state, color)
	UI.Paint(row.dot, color)
	local far = not m.isPlayer and not m.inRange
	row.mark:SetShown(far or m.summoned == true)
	row.mark:SetLabel(m.summoned and L["Not yet"] or L["Mark summoned"])
end

local function Build(page)
	local D = UI.data
	Kit.PageHead(page, L["Summon"], L["Group members who still need to get here."])
	-- Straight from each button's OnClick.
	page.announce = Kit.Button(page, L["Ask for a summon"], "primary", function(b)
		local ok, why = D.AnnounceSummon("all")
		if ok then b:Done(L["Asked"]) else b:Fail(D.Reason(why)) end
	end, { h = 30, tip = L["Ask for a summon"], tipBody = L["Posts who still needs a summon in group chat."] })
	page.announce:SetPoint("TOPRIGHT", 0, 0)
	page.next = Kit.Button(page, L["Next one"], "secondary", function(b)
		local ok, why = D.AnnounceSummon("next")
		if ok then b:Done(L["Posted"]) else b:Fail(D.Reason(why)) end
	end, { h = 30, tip = L["Next one"], tipBody = L["Posts the next name to summon, or that everyone is here."] })
	page.next:SetPoint("RIGHT", page.announce, "LEFT", -8, 0)
	page.warlocks = UI.Text(page, "data", 12, T.muted)
	page.warlocks:SetPoint("TOPLEFT", 0, -46)
	page.warlocks:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.list = Kit.List(page, { rowHeight = 40, gap = 4, create = CreateMember, bind = BindMember, width = UI.PAGE_W - 12,
		viewHeight = 380 })
	page.list:SetPoint("TOPLEFT", 0, -70)
	page.list:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function Refresh(page)
	local s = UI.data.Summon()
	page.announce:SetEnabled(s.inGroup and #s.needed > 0)
	page.next:SetEnabled(s.inGroup)
	if not s.inGroup then
		page.warlocks:SetText("")
	elseif #s.warlocks > 0 then
		page.warlocks:SetText(string.format(L["Warlocks close by: %s."], UI.Esc(table.concat(s.warlocks, ", "))))
	else
		page.warlocks:SetText(L["No warlock close by yet."])
	end
	if s.inGroup then
		page.list:SetEmpty(L["Nobody in your group needs a summon"], L["Members far from you show up here."])
	else
		page.list:SetEmpty(L["You are not in a group"], L["Your group shows up here, with who still needs a summon."])
	end
	page.list:SetItems(s.inGroup and s.members or {})
end

UI:RegisterPage("summon", {
	label = L["Summon"],
	icon = "icon-summon",
	build = Build,
	refresh = Refresh,
	badge = function()
		local n = #UI.data.Summon().needed
		if n > 0 then return tostring(n), T.amber end
	end,
})
