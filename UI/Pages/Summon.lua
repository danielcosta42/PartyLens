--=============================================================================
-- Summon: who in the group is far (or out of sight), the warlocks close by, marks for who already came, and the
-- announce in group chat (a click: visible chat needs one). Above the group, a summon from the realm: a place,
-- the network's warlocks offer, and the offer is invited with a click.
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
	-- A summon from the realm's warlocks: a place, then each offer is a prompt with Invite.
	page.dest = Kit.Edit(page, { w = 260, placeholder = L["Where to? For example: Blackrock Depths"], maxLetters = 40,
		onSubmit = function() page.ask:Click() end })
	page.dest:SetPoint("TOPLEFT", 0, -50)
	page.ask = Kit.Button(page, L["Ask the realm's warlocks"], "secondary", function(b)
		if D.SummonAsk() and D.SummonAsk().state == "open" then
			D.CancelSummonAsk()
			return
		end
		local ok, why = D.AskSummon(page.dest:GetText() or "")
		if ok then b:Done(L["Asked"]) else b:Fail(D.Reason(why)) end
	end, { h = 26, tip = L["Ask the realm's warlocks"],
		tipBody = L["Warlocks with PartyLens anywhere on the realm see it and can offer; you invite the one you want."] })
	page.ask:SetPoint("LEFT", page.dest, "RIGHT", 8, 0)
	page.askState = UI.Text(page, "data", 12, T.muted)
	page.askState:SetPoint("LEFT", page.ask, "RIGHT", 12, 0)
	page.askState:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.warlocks = UI.Text(page, "data", 12, T.muted)
	page.warlocks:SetPoint("TOPLEFT", 0, -88)
	page.warlocks:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.list = Kit.List(page, { rowHeight = 40, gap = 4, create = CreateMember, bind = BindMember, width = UI.PAGE_W - 12,
		viewHeight = 340 })
	page.list:SetPoint("TOPLEFT", 0, -112)
	page.list:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function RefreshAsk(page)
	local ask = UI.data.SummonAsk()
	local open = ask ~= nil and ask.state == "open"
	page.ask:Settle(open and L["Cancel the ask"] or L["Ask the realm's warlocks"])
	if not ask then
		page.askState:SetText("")
	elseif open then
		local n = #ask.offers
		page.askState:SetText(n == 0 and string.format(L["Asking for %s"], UI.Esc(ask.dest))
			or string.format(n == 1 and L["%s: 1 warlock offered"] or L["%s: %d warlocks offered"], UI.Esc(ask.dest), n))
	elseif ask.state == "expired" then
		page.askState:SetText(L["No warlock answered in time"])
	else
		page.askState:SetText("")
	end
end

local function Refresh(page)
	RefreshAsk(page)
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

--------------------------------------------------------------------------------
-- Prompts from the top of the screen, window open or not, one at a time each: a warlock sees an ask (Offer),
-- the asker sees an offer (Invite). Every action is its own click.
--------------------------------------------------------------------------------
local askPrompt, offerPrompt

local function ShowAsk(r)
	if not askPrompt then
		askPrompt = Kit.Toast(UIParent)
		askPrompt:SetFrameStrata("DIALOG")
		UI.summonAskPrompt = askPrompt
	end
	local who = UI.ClassName(r.name, r.classFile)
	askPrompt:Pop(string.format(L["%s needs a summon"], who),
		string.format(L["To %s, level %d"], UI.Esc(r.dest), r.level or 0), {
			hold = 30,
			actions = {
				{ label = L["Offer"], fn = function()
					local ok, why = UI.data.OfferSummon(r)
					UI:Notify("notice", ok and string.format(L["Offered to %s"], UI.Esc(r.name)) or UI.data.Reason(why))
				end },
				{ label = L["Ignore"], kind = "ghost", fn = function() UI.data.IgnoreSummonRequest(r) end },
			},
		})
end

UI:Listen("summonRequest", function(r)
	if type(r) ~= "table" then return end
	UI:WhenPromptFree(function() ShowAsk(r) end)
end)

local function ShowOffer(o)
	if not offerPrompt then
		offerPrompt = Kit.Toast(UIParent)
		offerPrompt:SetFrameStrata("DIALOG")
		UI.summonOfferPrompt = offerPrompt
	end
	offerPrompt:Pop(string.format(L["%s can summon you"], UI.Esc(o.name)), string.format(L["Now in %s"], UI.Esc(o.zone)), {
		hold = 60,
		color = T.ok,
		actions = {
			{ label = L["Invite"], fn = function()
				local ok, why = UI.data.AcceptSummonOffer(o)
				if not ok then UI:Notify("notice", UI.data.Reason(why)) end
			end },
		},
	})
end

UI:Listen("summonOffer", function(o)
	if type(o) ~= "table" then return end
	UI:WhenPromptFree(function() ShowOffer(o) end)
end)

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
