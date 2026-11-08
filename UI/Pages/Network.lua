--=============================================================================
-- Network: how much of the ChehulNet mesh this client hears, which ways out work right now, and who.
-- The directory size has no event, so the page re-reads it on the window's 5 s refresh while it is open.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local ADDONS = { pl = "PartyLens", gos = "GuildOS", ls = "Lodestar", bo = "CehulNet" }

local function AddonList(set)
	local names = {}
	for tag in pairs(set or {}) do names[#names + 1] = ADDONS[tag] or tag end
	table.sort(names)
	return table.concat(names, ", ")
end

local function CreatePeer(row)
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.dot = UI.Tex(row, "dot", 8, T.amber)
	row.dot:SetPoint("LEFT", 14, 0)
	row.name = UI.Text(row, "data", 13)
	row.name:SetPoint("LEFT", 32, 0)
	row.addons = UI.Text(row, "data", 12, T.muted)
	row.addons:SetPoint("LEFT", 220, 0)
	row.where = UI.Text(row, "data", 12, T.muted)
	row.where:SetPoint("LEFT", 420, 0)
	row.heard = UI.Text(row, "data", 12, T.muted, "RIGHT")
	row.heard:SetPoint("RIGHT", -14, 0)
end

local function BindPeer(row, p, _, list)
	local me = list.layer or {}
	UI.Paint(row.dot, p.addons and p.addons.pl and T.amber or T.faint)
	row.name:SetText(UI.ClassName(p.name, p.classFile))
	row.addons:SetText(UI.Esc(AddonList(p.addons)))
	local where = ""
	if p.mapID and me.mapID and p.mapID == me.mapID then
		where = (p.zoneUID and p.zoneUID == me.zoneUID) and L["same layer"] or L["same zone"]
	elseif p.mapID then
		where = L["elsewhere"]
	end
	row.where:SetText(where)
	row.heard:SetText(UI.Ago(p.ago or 0))
end

local function Build(page)
	Kit.PageHead(page, L["Network"],
		L["PartyLens shares listings and layers with other players through the ChehulNet mesh."])
	page.stats = {}
	for i = 1, 4 do
		local s = Kit.Stat(page)
		s:SetPoint("TOPLEFT", (i - 1) * 168, -58)
		page.stats[i] = s
	end
	page.buses = UI.Text(page, "data", 12, T.muted)
	page.buses:SetPoint("TOPLEFT", 0, -118)
	page.buses:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local s1 = Kit.Section(page, L["Heard recently"])
	s1:SetPoint("TOPLEFT", 0, -144)
	s1:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	local legend = UI.Text(page, "data", 12, T.muted)
	legend:SetPoint("TOPLEFT", 0, -166)
	legend:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	legend:SetText(L["Amber: runs PartyLens. Grey: another ChehulNet addon."])
	page.list = Kit.List(page, { rowHeight = 36, gap = 4, create = CreatePeer, bind = BindPeer, width = UI.PAGE_W - 12,
		viewHeight = 300 })
	page.list:SetPoint("TOPLEFT", 0, -190)
	page.list:SetPoint("BOTTOMRIGHT", 0, 0)
	page.list:SetEmpty(L["Nobody heard yet"],
		L["Each player announces themselves every few minutes. Joining a guild with PartyLens users helps."])
end

local function Refresh(page)
	local D = UI.data
	local st = D.Network()
	page.stats[1]:Set(tostring(st.nodes or 0), L["nodes heard"])
	page.stats[2]:Set(tostring(st.plNodes or 0), L["running PartyLens"])
	page.stats[3]:Set(tostring(st.directory or 0), L["in the realm directory"])
	page.stats[4]:Set(tostring(st.listingsHeard or 0), L["listings heard"])
	local b = st.buses or {}
	local ways = {}
	if b.guild then ways[#ways + 1] = L["your guild"] end
	if b.group then ways[#ways + 1] = L["your group"] end
	if b.realm then ways[#ways + 1] = L["the realm directory"] end
	if st.inInstance then
		page.buses:SetText(L["Inside an instance nothing is sent; it resumes outside."])
	elseif st.lockdown then
		page.buses:SetText(L["The game has paused addon messages for now."])
	elseif #ways > 0 then
		page.buses:SetText(string.format(L["Reaching the network through %s."], table.concat(ways, ", ")))
	else
		page.buses:SetText(L["No way out yet: join a guild or a group, or wait for the realm directory."])
	end
	page.list.layer = D.Layer()
	page.list:SetItems(D.Peers())
end

UI:RegisterPage("network", {
	label = L["Network"],
	icon = "icon-network",
	build = Build,
	refresh = Refresh,
	badge = function() return tostring(UI.data.Network().nodes or 0) end,
})
