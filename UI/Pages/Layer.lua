--=============================================================================
-- Layer: layers, not people. My layer and my request on the left, my beacon on the right (a light that gets
-- brighter with each rank, its ring filling toward the next one), then every layer heard, zone by zone, with its
-- population, beacons on duty, groups forming and its latest news. "Go here" asks a beacon of that layer; the
-- addon picks which one. Names show only to a beacon, in the prompt of the person asking it.
-- Asking, serving and undoing run straight from their buttons' OnClick (the game needs the click for the
-- invite, the uninvite and leaving; the core counts on it for the rest).
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, M, Kit = UI.T, UI.Motion, UI.Kit
local L = UI.L

local function rgb(hex)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- The beacon brightens with rank: dim amber to white.
local RANKS = {
	{ name = L["Spark"], color = rgb("B08A55") },
	{ name = L["Lantern"], color = rgb("FFB547") },
	{ name = L["Lighthouse"], color = rgb("FFC66B") },
	{ name = L["Guiding light"], color = rgb("FFD893") },
	{ name = L["North star"], color = rgb("FFE9BE") },
	{ name = L["Legend"], color = rgb("FFFFFF") },
}

local DUTY = {
	off = L["Off. Turn it on to help players reach your layer."],
	instance = L["Paused inside an instance."],
	no_layer = L["Paused until your layer is known: target any creature."],
	combat = L["Paused in combat."],
	afk = L["Paused while you are away."],
	grouped = L["Paused while you are in a group."],
	group_full = L["Paused: your group is full."],
}

local function MapName(mapID)
	local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if type(info) == "table" and info.name then return info.name end
	return mapID and string.format(L["map %d"], mapID) or ""
end

local function Pending(req)
	return req ~= nil and (req.state == "sent" or req.state == "accepted")
end

local function Plural(n, one, many)
	return n == 1 and one or string.format(many, n)
end

-- The newest news of a layer, in words.
local function News(item)
	local n = item.news and item.news[1]
	if not n then return "" end
	local ago, count = UI.Ago(time() - n.t), n.n or 1
	if n.kind == "new" then return string.format(L["Heard for the first time, %s ago"], ago) end
	if n.kind == "beacon_on" then return string.format(L["A beacon went on duty, %s ago"], ago) end
	if n.kind == "beacon_off" then return string.format(L["The last beacon went off duty, %s ago"], ago) end
	if n.kind == "hop" then
		if count == 1 then return string.format(L["A beacon brought someone over, %s ago"], ago) end
		return string.format(L["Beacons brought %d people over, %s ago"], count, ago)
	end
	if n.kind == "group" then
		if count == 1 then return string.format(L["A group started forming, %s ago"], ago) end
		return string.format(L["%d groups started forming, %s ago"], count, ago)
	end
	if n.kind == "grow" then return string.format(L["Up by %d people, %s ago"], count, ago) end
	if n.kind == "shrink" then return string.format(L["Down by %d people, %s ago"], count, ago) end
	return ""
end

local function LayerName(item)
	if item.ordinal then return string.format(L["Layer %d"], item.ordinal) end
	return L["Another layer"] -- on my map, one I have not seen myself: no number yet
end

--------------------------------------------------------------------------------
-- Rows: one per layer
--------------------------------------------------------------------------------
local BAR_W = 116

local function CreateRow(row)
	local D = UI.data
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.edge = UI.Fill(row, T.amber, 1, "ARTWORK")
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetWidth(3)
	row.title = UI.Text(row, "display", 14)
	row.title:SetPoint("TOPLEFT", 16, -11)
	row.zone = UI.Text(row, "data", 12, T.muted)
	row.zone:SetPoint("TOPLEFT", 16, -32)
	row.zone:SetWidth(150)

	row.track = UI.Fill(row, T.line, 1, "ARTWORK")
	row.track:SetPoint("TOPLEFT", 182, -15)
	row.track:SetSize(BAR_W, 6)
	row.bar = UI.Fill(row, T.text, 1, "OVERLAY")
	row.bar:SetPoint("TOPLEFT", row.track, "TOPLEFT")
	row.bar:SetHeight(6)
	row.pop = UI.Text(row, "data", 12, T.muted)
	row.pop:SetPoint("TOPLEFT", 182, -32)

	row.light = UI.Tex(row, "blip", 14, T.amber)
	row.light:SetPoint("TOPLEFT", 320, -11)
	row.beacons = UI.Text(row, "data", 13)
	row.beacons:SetPoint("LEFT", row.light, "RIGHT", 6, 0)
	row.news = UI.Text(row, "data", 12, T.muted)
	row.news:SetPoint("TOPLEFT", 320, -32)

	row.here = UI.Text(row, "data", 12, T.amber, "RIGHT")
	row.here:SetPoint("RIGHT", -16, 0)
	row.go = Kit.Button(row, L["Go here"], "primary", function(b)
		local ok, why = D.RequestLayer(row.item)
		if ok then b:Done(L["Asking"]) else b:Fail(D.Reason(why)) end
	end, { h = 26, minWidth = 92 })
	row.go:SetPoint("RIGHT", -10, 0)
	row.news:SetPoint("RIGHT", row.go, "LEFT", -12, 0)
	Kit.Tip(row.go, function(b)
		local item = b.item
		if not item then return end
		if item.canRequest then
			return L["Go here"], L["Asks a beacon of this layer to invite you. Accept the invite to come over."]
		end
		if not item.sameMap then return L["Go here"], L["Go to that zone first: beacons bring you over inside one zone."] end
		return L["Go here"], L["No beacon on duty here right now."]
	end)
end

local function BindRow(row, item, _, list)
	local page = list.page
	row.title:SetText(LayerName(item))
	UI.TextColor(row.title, item.sameMap and T.text or T.muted)
	row.zone:SetText(item.mine and L["You are here"] or UI.Esc(MapName(item.mapID)))
	UI.TextColor(row.zone, item.mine and T.amber or T.muted)
	local ctx = page.context
	local pinned = ctx ~= nil and ctx.zoneUID == item.zoneUID and ctx.mapID == item.mapID
	row.edge:SetShown(item.mine or pinned)
	UI.Paint(row.edge, item.mine and T.amber or T.text)

	local share = item.population / math.max(1, list.maxPopulation or 1)
	row.bar:SetWidth(math.max(2, BAR_W * share))
	UI.Paint(row.bar, item.mine and T.amber or T.text, item.sameMap and 1 or 0.6)
	row.pop:SetText(Plural(item.population, L["1 player heard"], L["%d players heard"]))

	local lit = item.beacons > 0
	UI.Paint(row.light, lit and T.amber or T.faint, lit and 1 or 0.6)
	local beacons = lit and Plural(item.beacons, L["1 beacon"], L["%d beacons"]) or L["No beacon"]
	if item.groups > 0 then
		beacons = string.format(L["%s, %s"], beacons, Plural(item.groups, L["1 group forming"], L["%d groups forming"]))
	end
	row.beacons:SetText(beacons)
	UI.TextColor(row.beacons, lit and T.text or T.muted)
	row.news:SetText(News(item))

	-- A new piece of news lights the row's light once.
	local newest = item.news and item.news[1] and item.news[1].t or 0
	local key = item.mapID .. ":" .. item.zoneUID
	if row.boundId == key and newest > (row.newsAt or 0) and page.seenNews then M.Pulse(row.light, 1.8, 0.5) end
	if row.boundId ~= key then
		row.boundId = key
		row.go:Unmorph()
	end
	row.newsAt = newest

	row.here:SetShown(item.mine)
	row.here:SetText(item.mine and L["Your layer"] or "")
	row.go:SetShown(not item.mine)
	row.go.item = item
	row.go:SetEnabled(item.canRequest == true and not Pending(UI.data.MyRequest()))
end

--------------------------------------------------------------------------------
-- The beacon card's motion: the rank ring easing to its new fill and a "+1" floating off the light.
--------------------------------------------------------------------------------
local function EaseRing(ring, to)
	local from = ring.fraction or 0
	if not M.On() or math.abs(to - from) < 0.001 then
		ring:SetScript("OnUpdate", nil)
		ring:SetFraction(to)
		return
	end
	local t0 = GetTime()
	ring:SetScript("OnUpdate", function(self)
		local k = math.min(1, (GetTime() - t0) / 0.6)
		self:SetFraction(from + (to - from) * (1 - (1 - k) * (1 - k)))
		if k >= 1 then self:SetScript("OnUpdate", nil) end
	end)
end

local function FloatUp(fs)
	local g = M.Group(fs, "float", function(group)
		group.move = M.Anim(group, "Translation", 1.1, 1, "OUT")
		group.move:SetOffset(0, 26)
		group.alpha = M.Anim(group, "Alpha", 1.1, 1, "IN")
		group.alpha:SetFromAlpha(1)
		group.alpha:SetToAlpha(0)
		group.finish = function() fs:SetAlpha(0) end
		group:SetScript("OnFinished", group.finish)
	end)
	fs:SetAlpha(1)
	M.Play(g, g.finish)
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
local CARD_Y, CARD_H, LEFT_W = -54, 112, 322

local function BuildMine(page)
	local D = UI.data
	local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(card, T.panel, T.line)
	card:SetPoint("TOPLEFT", 0, CARD_Y)
	card:SetSize(LEFT_W, CARD_H)
	page.card = card
	card.label = UI.Text(card, "data", 12, T.muted)
	card.label:SetPoint("TOPLEFT", 18, -14)
	card.label:SetText(L["Your layer"])
	card.number = UI.Text(card, "display", 30, T.text)
	card.number:SetPoint("TOPLEFT", 18, -32)
	card.zone = UI.Text(card, "data", 12, T.muted)
	card.zone:SetPoint("BOTTOMLEFT", card.number, "BOTTOMRIGHT", 12, 4)
	card.zone:SetPoint("RIGHT", card, "RIGHT", -14, 0)

	card.ring = Kit.ProgressRing(card, 26)
	card.ring:SetPoint("TOPLEFT", 16, -74)
	card.halo = UI.Tex(card.ring, "ring", 26, T.amber, 1, "OVERLAY")
	card.halo:SetPoint("CENTER")
	card.halo:Hide()
	card.action = Kit.Button(card, L["Cancel"], "ghost", function()
		local req = D.MyRequest()
		if Pending(req) then D.CancelRequest() elseif D.CanUndo() then D.Undo() end
	end, { h = 24 })
	card.action:SetPoint("TOPRIGHT", -12, -12)
	card.wait = UI.Text(card, "display", 13, T.text)
	card.wait:SetPoint("TOPLEFT", 52, -74)
	card.wait:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.waitSub = UI.Text(card, "data", 11, T.muted)
	card.waitSub:SetPoint("TOPLEFT", card.wait, "BOTTOMLEFT", 0, -4)
	card.waitSub:SetPoint("RIGHT", card, "RIGHT", -14, 0)
end

local function BuildBeacon(page)
	local D = UI.data
	local b = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(b, T.panel, T.line)
	b:SetPoint("TOPLEFT", LEFT_W + 12, CARD_Y)
	b:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	b:SetHeight(CARD_H)
	page.beacon = b

	b.ring = Kit.Ring(b, 72, T.amber)
	b.ring:SetPoint("LEFT", 16, 0)
	b.ring:SetFraction(0)
	b.glow = UI.Tex(b.ring, "blip", 40, T.amber, 1, "ARTWORK")
	b.glow:SetPoint("CENTER")
	b.halo = UI.Tex(b.ring, "ring", 72, T.amber, 1, "OVERLAY")
	b.halo:SetPoint("CENTER")
	b.halo:Hide()
	b.plus = UI.Text(b, "display", 16, T.amber, "CENTER")
	b.plus:SetPoint("BOTTOM", b.ring, "TOP", 0, -14)
	b.plus:SetText("+1")
	b.plus:SetAlpha(0)

	-- Top right: the queue's button; bottom right: the toggle. The text column runs between them.
	b.toggle = Kit.Check(b, L["Beacon"], true, function(on) D.SetBeacon(on) end)
	b.toggle:SetPoint("BOTTOMRIGHT", -14, 12)
	b.rank = UI.Text(b, "display", 16, T.text)
	b.rank:SetPoint("TOPLEFT", 104, -16)
	b.hops = UI.Text(b, "data", 12, T.muted)
	b.hops:SetPoint("TOPLEFT", 104, -40)
	b.next = UI.Text(b, "data", 12, T.muted)
	b.next:SetPoint("TOPLEFT", 104, -57)
	b.duty = UI.Text(b, "data", 12, T.text)
	b.duty:SetPoint("TOPLEFT", 104, -76)
	b.duty:SetPoint("RIGHT", b.toggle, "LEFT", -12, 0)
	b.duty:SetWordWrap(true)
	b.duty:SetJustifyV("TOP")
	b.duty:SetHeight(30)

	Kit.Tip(b.toggle, L["Beacon"],
		L["Others in your zone ask to come to your layer; you invite with a click. Each one raises your rank."])
	b.serve = Kit.Button(b, L["Invite next"], "primary", function(btn)
		local ok, why = D.ServeNext()
		if ok then btn:Done(L["Invited"]) else btn:Fail(D.Reason(why)) end
	end, { h = 26 })
	b.serve:SetPoint("TOPRIGHT", -12, -12)
	b.serve:Hide()
	b.undo = Kit.Button(b, L["Remove from group"], "secondary", function() D.Undo() end, { h = 26 })
	b.undo:SetPoint("TOPRIGHT", -12, -12)
	b.undo:Hide()
end

local function Build(page)
	Kit.PageHead(page, L["Layer"],
		L["Every layer heard, with its people and news. Beacons bring you over with an invite."])
	BuildMine(page)
	BuildBeacon(page)
	local s1 = Kit.Section(page, L["Layers heard"])
	s1:SetPoint("TOPLEFT", 0, CARD_Y - CARD_H - 16)
	s1:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.layers = Kit.List(page, { rowHeight = 56, gap = 4, create = CreateRow, bind = BindRow, width = UI.PAGE_W - 12,
		viewHeight = 300, emptyTop = 28 })
	page.layers.page = page
	page.layers:SetPoint("TOPLEFT", 0, CARD_Y - CARD_H - 42)
	page.layers:SetPoint("BOTTOMRIGHT", 0, 0)
	page.layers:SetEmpty(L["No layer heard yet"],
		L["Layers show up as players with PartyLens, GuildOS or Lodestar announce where they are."])
	page.lastState = nil
end

local STATE_TEXT = {
	sent = { L["Asking a beacon"], L["Each beacon gets 40 s, then the next one."] },
	accepted = { L["A beacon is inviting you"], L["Accept the invite to come over."] },
	served = { L["In the beacon's group"], L["Target a creature there to confirm."] },
	hopped = { L["On the new layer"], L["Leave the group when you are done."] },
	expired = { L["No beacon could take you"], L["Try again in a moment."] },
}

local function RefreshMine(page)
	local D, card = UI.data, page.card
	local me = D.Layer()
	if me.inInstance then
		card.number:SetText("-")
		card.zone:SetText(L["No layers inside an instance."])
	elseif me.zoneUID then
		card.number:SetText(tostring(me.ordinal or "?"))
		card.zone:SetText(string.format(L["%s, %d layers known"], UI.Esc(MapName(me.mapID)), me.count or 1))
	else
		card.number:SetText("?")
		card.zone:SetText(L["Target any creature to find out."])
	end

	local req = D.MyRequest()
	local text = req and STATE_TEXT[req.state]
	if text then
		card.wait:SetText(text[1])
		card.waitSub:SetText(text[2])
		card.ring:Show()
		if req.state == "sent" then
			-- askedAt is time(); the ring runs on GetTime().
			card.ring:Start(D.ASK_TTL, GetTime() - math.max(0, time() - (req.askedAt or req.t or time())))
		else
			card.ring:Stop()
			card.ring:SetFraction(req.state == "expired" and 0 or 1)
		end
		card.ring:SetColor(req.state == "expired" and T.muted or (req.state == "sent" and T.amber or T.ok))
		-- The ring flashes once when the invite is on its way.
		if req.state == "accepted" and page.lastState ~= "accepted" then M.Ripple(card.halo, 1.6, 0.7) end
	else
		card.ring:Stop()
		card.ring:Hide()
		card.wait:SetText(L["Pick a layer below"])
		card.waitSub:SetText(L["A beacon there invites you over."])
	end
	page.lastState = req and req.state
	local undoMine = req and (req.state == "served" or req.state == "hopped") and D.CanUndo()
	if Pending(req) then
		card.action:SetLabel(L["Cancel"])
		card.action:SetKind("ghost")
		card.action:Show()
	elseif undoMine then
		card.action:SetLabel(L["Leave group"])
		card.action:SetKind("secondary")
		card.action:Show()
	else
		card.action:Hide()
	end
end

local function RefreshBeacon(page)
	local D, b = UI.data, page.beacon
	local st = D.Beacon()
	local rank = RANKS[st.rank] or RANKS[1]
	b.rank:SetText(rank.name)
	UI.TextColor(b.rank, st.on and rank.color or T.muted)
	b.hops:SetText(string.format(L["%d brought over, %d today"], st.hops or 0, st.today or 0))
	if st.nextAt then
		b.next:SetText(string.format(L["%d more to %s"], st.nextAt - (st.hops or 0), RANKS[st.rank + 1].name))
		EaseRing(b.ring, ((st.hops or 0) - st.rankAt) / math.max(1, st.nextAt - st.rankAt))
	else
		b.next:SetText(L["The brightest beacon there is"])
		EaseRing(b.ring, 1)
	end
	b.ring:SetColor(st.on and rank.color or T.faint)
	UI.Paint(b.glow, st.available and rank.color or T.faint, st.available and 1 or 0.5)
	b.duty:SetText(st.available and L["On duty: players on other layers can ask you."] or (DUTY[st.why] or ""))
	UI.TextColor(b.duty, st.available and T.ok or T.muted)
	b.toggle:SetChecked(st.on)
	local queue = st.queue or 0
	b.serve:SetShown(queue > 0 or b.serve.rest ~= nil)
	if queue > 0 then b.serve:SetLabel(string.format(L["Invite next (%d)"], queue)) end
	local hoppers = false
	for _, r in ipairs(D.LayerRequests()) do hoppers = hoppers or r.state == "served" end
	b.undo:SetShown(queue == 0 and b.serve.rest == nil and hoppers)
	-- Going on duty sends one ripple from the light.
	if st.available and not page.breathing then
		page.breathing = true
		M.Ripple(b.halo, 1.5, 1.6)
	elseif not st.available then
		page.breathing = nil
	end
end

local function Refresh(page)
	local D = UI.data
	RefreshMine(page)
	RefreshBeacon(page)
	local items = D.Layers()
	local most = 1
	for _, item in ipairs(items) do most = math.max(most, item.population) end
	page.layers.maxPopulation = most
	page.layers:SetItems(items)
	page.seenNews = true
end

-- A hop served: the light throws a "+1", the ring eases forward, and a new rank ripples.
UI:Listen("beaconServed", function(st)
	if type(st) ~= "table" then return end
	UI:Notify("notice", string.format(L["%s came over to your layer: one more hop"], UI.Esc(st.name or "")))
	if st.rankUp then
		local rank = RANKS[st.rank]
		UI:Notify("notice", string.format(L["New beacon rank: %s"], rank and rank.name or ""))
	end
	local page = UI.pageFrames and UI.pageFrames.layer
	if not (page and page.beacon) then return end
	RefreshBeacon(page)
	FloatUp(page.beacon.plus)
	M.Pulse(page.beacon.glow, 1.5, 0.5)
	if st.rankUp then M.Ripple(page.beacon.halo, 2.2, 1.2) end
end)

--------------------------------------------------------------------------------
-- The beacon's prompt: someone asks for my layer. It drops from the top of the screen, window open or not,
-- and stays while the request is open; Invite serves it from its own OnClick, then the next one shows.
--------------------------------------------------------------------------------
local prompt

local function OldestOpen()
	local oldest
	for _, r in ipairs(UI.data.LayerRequests()) do
		if r.state == "open" and (not oldest or r.seq < oldest.seq) then oldest = r end
	end
	return oldest
end

local function ShowNext()
	local req = OldestOpen()
	if not req then
		if prompt and prompt:IsShown() then prompt:Leave() end
		if prompt then prompt.req = nil end
		return
	end
	if not prompt then
		prompt = Kit.Toast(UIParent)
		prompt:SetFrameStrata("DIALOG")
		UI.prompt = prompt
	end
	local more = UI.data.OpenRequests() - 1
	local body = more > 0 and string.format(L["Invite to bring them over. %d more waiting."], more)
		or L["Invite to bring them over."]
	if prompt.req == req and prompt:IsShown() then
		prompt.body:SetText(body) -- the same request: only the queue under it changed
		return
	end
	prompt.req = req
	prompt:Pop(string.format(L["%s wants your layer"], UI.Esc(req.name)), body, {
		hold = 90,
		actions = {
			{ label = L["Invite"], fn = function()
				prompt.req = nil
				local ok, why = UI.data.Serve(req)
				if not ok then UI:Notify("notice", UI.data.Reason(why)) end
				C_Timer.After(0.4, ShowNext)
			end },
			{ label = L["Decline"], kind = "ghost", fn = function()
				prompt.req = nil
				UI.data.Decline(req)
				C_Timer.After(0.4, ShowNext)
			end },
		},
	})
end

UI:Listen("layerRequest", function() ShowNext() end)
UI:Listen("layer", function()
	if prompt and prompt.req and prompt.req.state ~= "open" then
		prompt.req = nil
		ShowNext()
	end
end)

UI:RegisterPage("layer", {
	label = L["Layer"],
	icon = "icon-layer",
	build = Build,
	refresh = Refresh,
	badge = function()
		local n = UI.data.OpenRequests()
		if n > 0 then return tostring(n), T.amber end
	end,
})
