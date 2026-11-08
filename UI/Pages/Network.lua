--=============================================================================
-- Network: how much of the ChehulNet mesh this client hears and which ways out work right now. Counts only:
-- the page never lists who was heard.
-- The directory size has no event, so the page re-reads it on the window's 5 s refresh while it is open.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local ADDONS = { pl = "PartyLens", gos = "GuildOS", ls = "Lodestar", bo = "CehulNet" }

-- How many heard nodes run each addon ("GuildOS 12, Lodestar 3"); counts only, names stay private.
local function ByAddon(peers)
	local n = {}
	for _, p in ipairs(peers) do
		for tag in pairs(p.addons or {}) do
			local name = ADDONS[tag] or tag
			n[name] = (n[name] or 0) + 1
		end
	end
	local out = {}
	for name, c in pairs(n) do out[#out + 1] = name .. " " .. c end
	table.sort(out)
	return table.concat(out, ", ")
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
	page.addons = UI.Text(page, "data", 12, T.muted)
	page.addons:SetPoint("TOPLEFT", 0, -140)
	page.addons:SetPoint("RIGHT", page, "RIGHT", 0, 0)
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
	local by = ByAddon(D.Peers())
	page.addons:SetText(by ~= "" and string.format(L["By addon: %s."], by) or "")
end

UI:RegisterPage("network", {
	label = L["Network"],
	icon = "icon-network",
	build = Build,
	refresh = Refresh,
	badge = function() return tostring(UI.data.Network().nodes or 0) end,
})
