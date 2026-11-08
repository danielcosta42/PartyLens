--=============================================================================
-- Announce: the listing draft (kind, activity or free label, group size, comment), the visible post it makes
-- and the network listing. Posting in LookingForGroup is a click (the game requires one) and also starts the
-- listing. On the right, the autopilot in suggestion mode: who fits, each with its own Invite or Whisper.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, Kit = UI.T, UI.Kit
local L = UI.L

local LEFT_W = 330
local ROLE_NAME = { tank = L["ROLE_TANK"], heal = L["ROLE_HEAL"], dps = L["ROLE_DPS"] }

local function Stepper(parent, role, onChange)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(100, 28)
	s.icon = UI.Tex(s, "role-" .. role, 16, T.role[role])
	s.icon:SetPoint("LEFT", 0, 0)
	s.minus = Kit.IconButton(s, "minus", 22, function() s:Set(s.n - 1, true) end, L["One less"])
	s.minus:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
	s.value = UI.Text(s, "display", 16, T.text, "CENTER")
	s.value:SetPoint("LEFT", s.minus, "RIGHT", 2, 0)
	s.value:SetWidth(22)
	s.plus = Kit.IconButton(s, "plus", 22, function() s:Set(s.n + 1, true) end, L["One more"])
	s.plus:SetPoint("LEFT", s.value, "RIGHT", 2, 0)
	function s:Set(n, user)
		self.n = math.max(0, math.min(40, n))
		self.value:SetText(tostring(self.n))
		UI.TextColor(self.value, self.n > 0 and T.role[role] or T.faint)
		self.minus:SetEnabled(self.n > 0)
		if user then onChange(self.n) end
	end
	return s
end

local function ActivityOptions()
	local list = { { value = "", label = L["Quest or something else"] } }
	for _, a in ipairs(UI.data.Activities()) do list[#list + 1] = { value = a.key, label = UI.data.ActivityLabel(a) } end
	return list
end

-- "1 Tank, 2 DPS", or nothing.
-- Typing in the label or the comment. A draft that is not on the air is saved as typed (nothing goes out, and
-- the preview, built by the core, follows each key). On the air, every save republishes the listing, so the
-- typing is saved once it pauses (DRAFT_PAUSE), on Enter or blur, and right before Post or List in their own
-- OnClick (page:CommitDrafts): never once per key.
local DRAFT_PAUSE = 0.8
local function Draft(page, field, text)
	local s = UI.data.Listing()
	if s and not s.active then
		UI.data.SetListing({ [field] = text })
		return
	end
	page.typing = (page.typing or 0) + 1
	local token = page.typing
	C_Timer.After(DRAFT_PAUSE, function()
		if page.typing == token then page:CommitDrafts() end
	end)
end

local function RoleList(counts)
	local parts = {}
	for _, role in ipairs(Kit.ROLES) do
		local n = counts[role] or 0
		if n > 0 then parts[#parts + 1] = n .. " " .. ROLE_NAME[role] end
	end
	return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- A suggestion row
--------------------------------------------------------------------------------
local function CreateSuggestion(row)
	local D = UI.data
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.pips = Kit.RolePips(row, 13)
	row.pips:SetPoint("TOPLEFT", 12, -9)
	row.name = UI.Text(row, "data", 13)
	row.name:SetPoint("LEFT", row.pips, "RIGHT", 8, 0)
	row.msg = UI.Text(row, "data", 12, T.muted)
	row.msg:SetPoint("TOPLEFT", 12, -28)
	row.dismiss = Kit.IconButton(row, "close", 20, function() D.Dismiss(row.item.entry) end, L["Not this one"],
		L["Hides this suggestion until the listing stops."])
	row.dismiss:SetPoint("RIGHT", -6, 0)
	-- Straight from each button's OnClick.
	row.main = Kit.Button(row, L["Invite"], "primary", function(b)
		local s = row.item
		local ok, why
		if s.action == "invite" then ok, why = D.Invite(s.entry) else ok, why = D.Whisper(s.entry) end
		if ok then b:Done(s.action == "invite" and L["Invited"] or L["Sent"]) else b:Fail(D.Reason(why)) end
	end, { w = 76, h = 24 })
	row.main:SetPoint("RIGHT", row.dismiss, "LEFT", -6, 0)
	row.whisper = Kit.Button(row, L["Whisper"], "secondary", function(b)
		local ok, why = D.Whisper(row.item.entry)
		if ok then b:Done(L["Sent"]) else b:Fail(D.Reason(why)) end
	end, { w = 76, h = 24 })
	row.whisper:SetPoint("RIGHT", row.main, "LEFT", -6, 0)
	row.msg:SetPoint("RIGHT", row.whisper, "LEFT", -10, 0)
end

local function BindSuggestion(row, s)
	local e = s.entry
	row.pips:Set(UI.data.RoleCounts(e))
	local level = e.level and ("  " .. UI.Hex(T.muted) .. L["LEVEL_SHORT"] .. " " .. e.level .. "|r") or ""
	row.name:SetText(UI.ClassName(e.name, e.classFile) .. level)
	row.msg:SetText(UI.Esc(e.message))
	if row.boundId ~= e.key then
		row.boundId = e.key
		row.main:Unmorph()
		row.whisper:Unmorph()
	end
	local invite = s.action == "invite"
	row.whisper:SetShown(invite)
	if e.contacted then
		row.main:Settle(e.contacted == "invite" and L["Invited"] or L["Whispered"], "secondary")
	else
		row.main:Settle(invite and L["Invite"] or L["Whisper"], "primary")
	end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
local function Build(page)
	local D = UI.data
	Kit.PageHead(page, L["Announce"], L["Post your group in LookingForGroup and share it with the network."])

	local y = -56
	local s1 = Kit.Section(page, L["Your group"])
	s1:SetPoint("TOPLEFT", 0, y)
	s1:SetWidth(LEFT_W)
	page.kind = Kit.Segmented(page, {
		{ value = "lfm", label = L["TYPE_LFM"], tip = L["You lead and need people."] },
		{ value = "lfg", label = L["TYPE_LFG"], tip = L["You look for a group."] },
	}, "lfm", function(v) D.SetListing({ type = v }) end, { segW = 60 })
	page.kind:SetPoint("TOPLEFT", 0, y - 26)
	page.kindHint = UI.Text(page, "data", 12, T.muted)
	page.kindHint:SetPoint("LEFT", page.kind, "RIGHT", 10, 0)

	page.activity = Kit.Dropdown(page, { w = LEFT_W, options = ActivityOptions, value = "",
		onChange = function(key)
			local fields = { activity = key }
			if key ~= "" then fields.want = D.DefaultWant(key) end
			D.SetListing(fields)
		end })
	page.activity:SetPoint("TOPLEFT", 0, y - 60)
	page.label = Kit.Edit(page, { w = LEFT_W, placeholder = L["Quest or activity name"], maxLetters = 60,
		onChange = function(text) Draft(page, "label", text) end, onCommit = function() page:CommitDrafts() end })
	page.label:SetPoint("TOPLEFT", 0, y - 92)

	page.roleLabel = UI.Text(page, "data", 12, T.muted)
	page.roleLabel:SetPoint("TOPLEFT", 0, y - 126)
	page.steppers, page.myRoles = {}, {}
	for i, role in ipairs(Kit.ROLES) do
		local st = Stepper(page, role, function(n) D.SetListing({ want = { [role] = n } }) end)
		st:SetPoint("TOPLEFT", (i - 1) * 112, y - 142)
		page.steppers[role] = st
		local chip = Kit.Chip(page, { icon = "role-" .. role, label = ROLE_NAME[role], color = T.role[role],
			onToggle = function(on) D.SetRole(role, on) end })
		chip:SetPoint("TOPLEFT", (i - 1) * 104, y - 144)
		page.myRoles[role] = chip
	end
	page.missing = UI.Text(page, "data", 12, T.muted)
	page.missing:SetPoint("TOPLEFT", 0, y - 176)
	page.missing:SetWidth(LEFT_W)

	page.comment = Kit.Edit(page, { w = LEFT_W, placeholder = L["Comment, for example: quest run, summons ready"],
		maxLetters = 80,
		onChange = function(text) Draft(page, "comment", text) end, onCommit = function() page:CommitDrafts() end })
	page.comment:SetPoint("TOPLEFT", 0, y - 198)

	local s2 = Kit.Section(page, L["Preview"])
	s2:SetPoint("TOPLEFT", 0, y - 232)
	s2:SetWidth(LEFT_W)
	page.quote = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(page.quote, T.well, T.line)
	page.quote:SetPoint("TOPLEFT", 0, y - 256)
	page.quote:SetSize(LEFT_W, 58)
	page.quote.text = UI.Text(page.quote, "data", 13, T.text)
	page.quote.text:SetPoint("TOPLEFT", 10, -9)
	page.quote.text:SetPoint("RIGHT", -10, 0)
	page.quote.text:SetWordWrap(true)
	page.quote.count = UI.Text(page.quote, "data", 11, T.faint, "RIGHT")
	page.quote.count:SetPoint("BOTTOMRIGHT", -8, 6)

	-- Straight from each button's OnClick.
	page.post = Kit.Button(page, L["Post in LookingForGroup"], "primary", function(b)
		page:CommitDrafts() -- a click on a button may leave the focus in the box: post what it shows
		local ok, why = D.PostLFG()
		if ok then b:Done(L["Posted"]) else b:Fail(D.Reason(why)) end
	end, { h = 30, tip = L["Post in LookingForGroup"],
		tipBody = L["Sends the preview to the channel and lists the group on the network. Every post needs a click."] })
	page.post:SetPoint("TOPLEFT", 0, y - 326)
	page.listing = Kit.Button(page, L["List on the network"], "secondary", function()
		page:CommitDrafts()
		local listing = D.Listing()
		if listing and listing.active then D.StopListing() else D.StartListing() end
	end, { h = 30, tip = L["The network listing"],
		tipBody = L["On PartyLens radars, refreshed every minute. After a stop, copies passed along fade within 3 min."] })
	page.listing:SetPoint("LEFT", page.post, "RIGHT", 8, 0)
	-- What the boxes show goes into the draft now, in one SetListing (and so one network update at most).
	function page:CommitDrafts()
		self.typing = (self.typing or 0) + 1 -- a pending pause save is no longer needed
		local s = D.Listing()
		if not s then return end
		local fields = {}
		local label, comment = self.label:GetText() or "", self.comment:GetText() or ""
		if self.label:IsShown() and label ~= s.label then fields.label = label end
		if comment ~= s.comment then fields.comment = comment end
		self.label.committed, self.comment.committed = label, comment
		if next(fields) then D.SetListing(fields) end
	end

	page.state = UI.Text(page, "data", 12, T.muted)
	page.state:SetPoint("TOPLEFT", 0, y - 366)
	page.state:SetWidth(LEFT_W)
	page.state:SetWordWrap(true)

	-- Suggestions
	local rx = LEFT_W + 32
	local s3 = Kit.Section(page, L["Suggestions"])
	s3:SetPoint("TOPLEFT", rx, y)
	s3:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.why = UI.Text(page, "data", 12, T.muted)
	page.why:SetPoint("TOPLEFT", rx, y - 24)
	page.why:SetWidth(UI.PAGE_W - rx)
	page.why:SetWordWrap(true)
	page.suggest = Kit.List(page, { rowHeight = 50, gap = 6, create = CreateSuggestion, bind = BindSuggestion,
		width = UI.PAGE_W - rx - 12, viewHeight = 300 })
	page.suggest:SetPoint("TOPLEFT", rx, y - 60)
	page.suggest:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function Refresh(page)
	local D = UI.data
	local s = D.Listing()
	if not s then return end
	local lfm = s.type == "lfm"
	page.kind:SetValue(s.type, true)
	page.kindHint:SetText(lfm and L["You lead and need people."] or L["You look for a group."])
	page.activity:SetValue(s.activity, true)
	page.label:SetShown(s.activity == "")
	page.label:SetValue(s.label)
	page.comment:SetValue(s.comment)

	page.roleLabel:SetText(lfm and L["Group size, you included"] or L["Roles you play"])
	local mine = D.MyRoles()
	for _, role in ipairs(Kit.ROLES) do
		page.steppers[role]:SetShown(lfm)
		page.steppers[role]:Set(s.want[role] or 0)
		page.myRoles[role]:SetShown(not lfm)
		page.myRoles[role]:SetSelected(mine[role], true)
	end
	if lfm then
		local missing = RoleList(s.missing)
		page.missing:SetText(missing ~= "" and string.format(L["Still missing: %s"], missing) or L["The group is full."])
	else
		page.missing:SetText("")
	end

	local text = D.BuildPost()
	page.quote.text:SetText(UI.Esc(text))
	page.quote.count:SetText(string.format("%d/255", #text))
	page.post:SetEnabled(text ~= "")
	page.listing:Settle(s.active and L["Stop listing"] or L["List on the network"])

	if s.active then
		local since = UI.Ago(time() - (s.startedAt or time()))
		local post = s.lastPost and string.format(L["last post %s ago"],
			UI.Ago(time() - s.lastPost)) or L["not posted in the channel yet"]
		page.state:SetText(string.format(L["On the network for %s, %s."], since, post))
	else
		page.state:SetText(L["Not listed yet. Posting also lists the group on the network."])
	end

	page.why:SetText(lfm and L["Players on the radar who fill your missing roles. Nothing goes out until you click."]
		or L["Groups on the radar that need one of your roles. Nothing goes out until you click."])
	if s.active then
		page.suggest:SetEmpty(L["Nobody fits yet"],
			L["Suggestions show up as players who fill your roles post in the channel."])
	else
		page.suggest:SetEmpty(L["Post your group to see who fits"],
			L["The radar keeps listening; matching players land here."])
	end
	page.suggest:SetItems(D.Suggestions())
end

UI:RegisterPage("announce", {
	label = L["Announce"],
	icon = "icon-announce",
	build = Build,
	refresh = Refresh,
	badge = function()
		local s = UI.data.Listing()
		if s and s.active then return L["live"], T.amber end
	end,
})
