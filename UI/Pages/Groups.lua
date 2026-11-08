--=============================================================================
-- Groups: the radar on top, what it hears in numbers next to it, the filters, and the list.
--
-- Radar encoding: angle by kind of content (one quarter each: dungeons, raids, quests, other and guild),
-- distance from the centre by age against the entry's lifetime (new near the centre, drifting out as it ages),
-- colour by kind (LFM amber, LFG blue). Filters are the core's db.filters, written with PartyLens:Set.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local RADAR, ROW, GAP = 164, 58, 6
local SECTOR = { dungeon = 0, raid = 0.25, quest = 0.5, other = 0.75, guild = 0.75 }

local function Hash(s)
	local h = 7
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
	return h
end

local function Blips(entries)
	local D, list = UI.data, {}
	for _, e in ipairs(entries) do
		local base = SECTOR[e.activityType] or SECTOR.other
		list[#list + 1] = {
			id = e.key,
			angle = base + 0.03 + 0.19 * ((Hash(e.activityKey or e.activity or "") % 97) / 96),
			radius = 0.12 + 0.88 * math.min(1, D.Age(e) / D.MaxAge(e)),
			color = e.type == "lfg" and T.lfg or T.lfm,
		}
	end
	return list
end

-- The first of my roles this group still needs (its pip pulses once when it arrives).
local function MyFirstRole(e)
	local mine = UI.data.MyRoles()
	for _, role in ipairs(Kit.ROLES) do
		if mine[role] and e.roles and e.roles[role] then return role end
	end
end

-- The activity filter: one dropdown over db.filters.activityType and db.filters.activity.
local function ActivityOptions()
	local list = {
		{ value = "all", label = L["Any activity"] },
		{ value = "type:dungeon", label = L["ACTIVITY_DUNGEON"] }, { value = "type:raid", label = L["ACTIVITY_RAID"] },
		{ value = "type:quest", label = L["ACTIVITY_QUEST"] }, { value = "type:guild", label = L["ACTIVITY_GUILD"] },
		{ value = "type:other", label = L["ACTIVITY_OTHER"] },
	}
	for _, a in ipairs(UI.data.Activities()) do
		list[#list + 1] = { value = "key:" .. a.key, label = UI.data.ActivityLabel(a) }
	end
	return list
end

local function ActivityValue(f)
	if f.activity ~= "" then return "key:" .. f.activity end
	if f.activityType ~= "all" then return "type:" .. f.activityType end
	return "all"
end

local function SetActivity(value)
	local D = UI.data
	local kind, rest = value:match("^(%a+):(.+)$")
	D.SetFilter("activity", kind == "key" and rest or "")
	D.SetFilter("activityType", kind == "type" and rest or "all")
end

--------------------------------------------------------------------------------
-- A card in the list
--------------------------------------------------------------------------------
local function CreateCard(row)
	Kit.Card(row)
	local b = row.body
	b.activity = UI.Text(b, "display", 14)
	b.activity:SetPoint("TOPLEFT", 16, -10)
	b.kind = UI.Text(b, "data", 12, T.lfm)
	b.kind:SetPoint("LEFT", b.activity, "RIGHT", 9, 0)
	b.ring = Kit.FreshRing(b, 12)
	b.ring:SetPoint("LEFT", b.kind, "RIGHT", 11, 0)
	b.age = UI.Text(b, "data", 12, T.muted)
	b.age:SetPoint("LEFT", b.ring, "RIGHT", 5, 0)
	Kit.Tip(b.ring, L["Freshness"], L["The ring empties as the post gets older."])
	b.ring:EnableMouse(true)
	-- The mark of a fellow PartyLens user (their own network listing or a signed post).
	b.user = UI.Tex(b, "mark", 13, T.amber)
	b.user:SetPoint("LEFT", b.age, "RIGHT", 10, 0)
	b.userHit = CreateFrame("Frame", nil, b)
	b.userHit:SetAllPoints(b.user)
	b.userHit:EnableMouse(true)
	Kit.Tip(b.userHit, L["Uses PartyLens"],
		L["Their listing comes straight from the addon: roles and group size are exact."])

	b.more = Kit.IconButton(b, "icon-more", 26, function(btn) UI.groupsPage:OpenMore(btn, row.item) end, L["More"])
	b.more:SetPoint("RIGHT", -10, 0)
	b.action = Kit.Button(b, L["Whisper"], "primary", function(btn) UI.groupsPage:Act(btn, row.item) end, { w = 92,
		h = 26 })
	b.action:SetPoint("RIGHT", b.more, "LEFT", -6, 0)
	Kit.Tip(b.action, function(btn)
		local e = btn.item
		if not e then return end
		if e.type == "lfm" then return L["Whisper"], UI.Esc(UI.data.WhisperText(e)) end
		return L["Invite"], string.format(L["Invites %s to your group."], UI.Esc(e.name))
	end)
	b.fill = UI.Text(b, "display", 13, T.text, "RIGHT")
	b.fill:SetPoint("RIGHT", b.action, "LEFT", -14, 0)
	b.pips = Kit.RolePips(b, 14)
	b.pips:SetPoint("RIGHT", b.fill, "LEFT", -10, 0)

	b.line = UI.Text(b, "data", 13, T.muted)
	b.line:SetPoint("TOPLEFT", 16, -33)
	b.line:SetPoint("RIGHT", b.pips, "LEFT", -16, 0)
end

local function BindCard(row, e, _, list)
	local page, b, D = list.page, row.body, UI.data
	if row.boundId ~= e.key then
		row:ResetMotion()
		row.boundId = e.key
	end
	local lfm = e.type == "lfm"
	row:SetEdge(lfm and T.lfm or T.lfg)
	b.activity:SetText(UI.Esc(e.activity))
	b.kind:SetText(lfm and L["TYPE_LFM"] or L["TYPE_LFG"])
	UI.TextColor(b.kind, lfm and T.lfm or T.lfg)
	local age = D.Age(e)
	b.ring:SetAge(age, D.MaxAge(e))
	b.age:SetText(UI.Ago(age))
	b.user:SetShown(e.isAddonUser == true)
	b.userHit:SetShown(e.isAddonUser == true)
	b.line:SetText(UI.ClassName(e.name, e.classFile) .. "  " .. UI.Esc(e.message))
	b.pips:Set(D.RoleCounts(e))
	if lfm then
		b.fill:SetText((e.filled and e.max) and string.format("%d/%d", e.filled, e.max) or "")
	else
		b.fill:SetText(e.level and (L["LEVEL_SHORT"] .. " " .. e.level) or "")
	end
	if b.action.item ~= e then
		b.action:Unmorph()
		b.action.item = e
	end
	-- Settle keeps a "Sent" showing and lands on the core's contacted mark when it ends.
	if e.contacted then
		b.action:Settle(e.contacted == "invite" and L["Invited"] or L["Whispered"], "secondary")
	else
		b.action:Settle(lfm and L["Whisper"] or L["Invite"], "primary")
	end
	if page.fresh[e.key] then
		page.fresh[e.key] = nil
		row:MarkNew()
		local role = e.needsMe and MyFirstRole(e)
		if role then b.pips:Pulse(role) end
	end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
local function Build(page)
	UI.groupsPage = page
	local D = UI.data
	page.fresh, page.pops = {}, {}

	page.radar = Kit.Radar(page, RADAR)
	page.radar:SetPoint("TOPLEFT", 0, 0)
	page.radar:SetSectors({
		{ corner = "TOPRIGHT", label = L["ACTIVITY_DUNGEON"] }, { corner = "BOTTOMRIGHT", label = L["ACTIVITY_RAID"] },
		{ corner = "BOTTOMLEFT", label = L["ACTIVITY_QUEST"] }, { corner = "TOPLEFT", label = L["ACTIVITY_OTHER"] },
	})

	local x = RADAR + 32
	page.groups = Kit.Stat(page)
	page.groups:SetPoint("TOPLEFT", x, -8)
	page.needYou = Kit.Stat(page, T.amber)
	page.needYou:SetPoint("TOPLEFT", x + 160, -8)
	page.nodes = Kit.Stat(page)
	page.nodes:SetPoint("TOPLEFT", x + 320, -8)
	page.legend = UI.Text(page, "data", 12, T.muted)
	page.legend:SetPoint("TOPLEFT", x, -78)
	page.legend:SetWidth(UI.PAGE_W - x)
	page.legend:SetWordWrap(true)
	page.legend:SetText(L["A blip per group: amber looks for members, blue for a group. New ones start near the centre."])

	-- Filters
	local F = D.Filters()
	local y = -RADAR - 14
	page.roleChips = {}
	local roleTip = { tank = L["Groups that need a tank"], heal = L["Groups that need a healer"],
		dps = L["Groups that need damage"] }
	local cx = 0
	for _, role in ipairs(Kit.ROLES) do
		local chip = Kit.Chip(page, {
			icon = "role-" .. role, color = T.role[role], selected = F.roles[role], w = 30, tip = roleTip[role],
			tipBody = L["Posts that name no role stay. Players looking for a group show up when they can play it."],
			onToggle = function(on) D.SetFilter("roles." .. role, on); page:Changed() end,
		})
		chip:SetPoint("TOPLEFT", cx, y)
		page.roleChips[role] = chip
		cx = cx + 34
	end
	page.kind = Kit.Segmented(page, {
		{ value = "all", label = L["All"] },
		{ value = "lfm", label = L["TYPE_LFM"], tip = L["Groups looking for members"] },
		{ value = "lfg", label = L["TYPE_LFG"], tip = L["Players looking for a group"] },
	}, F.type, function(v) D.SetFilter("type", v); page:Changed() end)
	page.kind:SetPoint("TOPLEFT", cx + 8, y)
	page.activity = Kit.Dropdown(page, { w = 168, options = ActivityOptions, value = ActivityValue(F),
		onChange = function(v) SetActivity(v); page:Changed() end })
	page.activity:SetPoint("LEFT", page.kind, "RIGHT", 10, 0)
	page.search = Kit.Edit(page, { w = 150, icon = "search", placeholder = L["Search"], text = F.query,
		onChange = function(text) D.SetFilter("query", text); page:Changed() end })
	page.search:SetPoint("LEFT", page.activity, "RIGHT", 10, 0)
	page.open = Kit.Check(page, L["Open only"], F.onlyOpen, function(on) D.SetFilter("onlyOpen", on); page:Changed() end)
	page.open:SetPoint("LEFT", page.search, "RIGHT", 14, -1)
	Kit.Tip(page.open, L["Open only"], L["Hide groups that are already full."])

	page.list = Kit.List(page, { rowHeight = ROW, gap = GAP, create = CreateCard, bind = BindCard, width = UI.PAGE_W - 12,
		viewHeight = UI.PAGE_H - RADAR - 52 })
	page.list.page = page
	page.list:SetPoint("TOPLEFT", 0, y - 38)
	page.list:SetPoint("BOTTOMRIGHT", 0, 0)

	function page:Changed()
		self.list:ScrollToTop()
		UI:Refresh(true)
	end

	-- Straight from the button's OnClick: whisper a group, invite a player.
	function page:Act(btn, e)
		if not e then return end
		local ok, why
		if e.type == "lfm" then ok, why = D.Whisper(e) else ok, why = D.Invite(e) end
		if ok then btn:Done(e.type == "lfm" and L["Sent"] or L["Invited"]) else btn:Fail(D.Reason(why)) end
	end

	function page:OpenMore(anchor, e)
		if not e then return end
		local items = {}
		if e.type == "lfg" then items[#items + 1] = { text = L["Whisper"], value = "whisper" } end
		items[#items + 1] = { text = L["Write the whisper myself"], value = "edit" }
		items[#items + 1] = { text = L["Who is this?"], value = "who" }
		items[#items + 1] = { text = L["Block this player"], value = "block", color = T.dps }
		-- Runs inside the menu row's OnClick: the protected calls stay on the click.
		Kit.OpenMenu(anchor, items, function(v)
			if v == "whisper" then D.Whisper(e)
			elseif v == "edit" then D.OpenWhisper(e)
			elseif v == "who" then D.Who(e)
			elseif v == "block" then D.Block(e)
			end
		end)
	end
end

-- A new person on the radar: the blip pops, the card slides in, and when the group needs my role its pip pulses
-- and a toast says so (at most one every 10 s, so a busy channel does not bury the window).
-- Animations are recorded only while the window is open, and only the newest few: arrivals while it is closed
-- must not pile up into a burst of pops and slides when it opens.
local lastToast, KEEP = -100, 5
UI:Listen("entry", function(e, needsMe)
	local page = UI.groupsPage
	if not (page and e and e.key) then return end
	if UI:IsOpen() then
		page.fresh[e.key] = true
		page.pops[#page.pops + 1] = e.key
		while #page.pops > KEEP do page.fresh[table.remove(page.pops, 1)] = nil end
	end
	if not needsMe then return end
	if UI:IsOpen() and GetTime() - lastToast >= 10 then
		lastToast = GetTime()
		UI:Toast(string.format(L["%s needs you"], UI.Esc(e.activity)), UI.Esc(e.name) .. ": " .. UI.Esc(e.message),
			{ onClick = function() UI:Open("groups") end })
	end
end)

-- With the window closed, a sound when a group needs my role (db.alertOnMatch, off by default).
UI:Listen("entry", function(_, needsMe)
	if not needsMe or UI:IsOpen() or not UI.data.Get("alertOnMatch") then return end
	if C_Sound and C_Sound.PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then C_Sound.PlaySound(SOUNDKIT.READY_CHECK) end
end)

local function Refresh(page)
	local D = UI.data
	local entries, counts = D.Entries(), D.Counts()
	page.radar:SetBlips(Blips(entries))
	for _, key in ipairs(page.pops) do page.radar:Pop(key) end
	wipe(page.pops)
	page.groups:Set(tostring(counts.total), L["on the radar"])
	page.needYou:Set(tostring(counts.needsMe), L["need your role"])
	page.nodes:Set(tostring(D.Network().nodes or 0), L["nodes on the network"])

	local F = D.Filters()
	for role, chip in pairs(page.roleChips) do chip:SetSelected(F.roles[role], true) end
	page.kind:SetValue(F.type, true)
	page.activity:SetValue(ActivityValue(F), true)
	page.search:SetValue(F.query)
	page.open:SetChecked(F.onlyOpen)

	if counts.total == 0 then
		page.list:SetEmpty(L["Listening to the channel…"],
			L["Groups show up here as soon as someone posts in LookingForGroup or the network shares a listing."])
	else
		page.list:SetEmpty(L["No group matches these filters"], L["Try another role or activity, or clear the search."],
			L["Clear filters"], function()
				D.ClearFilters()
				page:Changed()
			end)
	end
	page.list:SetItems(entries)
	wipe(page.fresh) -- the cards in view took theirs; a new entry out of view is not new later
end

UI:RegisterPage("groups", {
	label = L["Groups"],
	icon = "icon-groups",
	build = Build,
	refresh = Refresh,
	badge = function()
		local n = UI.data.Counts().needsMe or 0
		if n > 0 then return tostring(n), T.amber end
	end,
})
