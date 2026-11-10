--=============================================================================
-- Layer: the copies of the zone I am in, as a stack of plates. Each plate is a layer: dots on its surface are the
-- players heard there, lights on its front edge the beacons on duty; mine glows amber with a "you" ping. A click
-- picks a plate; the panel beside it shows its numbers, its news and the button that asks one of its beacons to
-- bring me over. My beacon (a light that brightens with each rank) runs along the bottom.
-- Layers belong to one zone on Forever, so other zones are not shown: nothing there can be reached from here.
-- Asking, serving and undoing run straight from their buttons' OnClick (the game needs the click for the
-- invite, the uninvite and leaving; the core counts on it for the rest). No name shows except in the beacon's
-- prompt, for the person asking it.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, M, Kit = UI.T, UI.Motion, UI.Kit
local L = UI.L

local function rgb(hex)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

local function mix(a, b, k)
	return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
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

-- Plates: an empty one is a dark slate, a busy one a lighter blue; mine is amber.
local PLATE_LOW, PLATE_HIGH = T.line, rgb("4C6496")
local PLATE_MINE = mix(T.line, T.amber, 0.55)

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

local function KeyOf(item)
	return item.mapID .. ":" .. item.zoneUID
end

-- A layer goes by the game's own number for that copy of the zone (the zoneUID in every creature's GUID): the
-- same for every player, seen or not, so "layer 6" in chat means the same layer to everyone.
local function LayerName(item)
	return string.format(L["Layer %d"], item.zoneUID)
end

-- One piece of news, in words.
local function NewsText(n)
	local count = n.n or 1
	if n.kind == "new" then return L["Heard for the first time"] end
	if n.kind == "beacon_on" then return L["A beacon went on duty"] end
	if n.kind == "beacon_off" then return L["The last beacon went off duty"] end
	if n.kind == "hop" then
		return count == 1 and L["A beacon brought someone over"] or string.format(L["Beacons brought %d people over"], count)
	end
	if n.kind == "group" then
		return count == 1 and L["A group started forming"] or string.format(L["%d groups started forming"], count)
	end
	if n.kind == "grow" then return string.format(L["Up by %d people"], count) end
	if n.kind == "shrink" then return string.format(L["Down by %d people"], count) end
	return ""
end

--------------------------------------------------------------------------------
-- Plate geometry. slab.tga is 256 x 128: top face T, R, B, L (gen-media.py), shown at PW x PH.
--------------------------------------------------------------------------------
local PW, PH = 196, 98
local SC = PW / 256
local PT, PR, PB, PL = { 128 * SC, 8 * SC }, { 248 * SC, 56 * SC }, { 128 * SC, 104 * SC }, { 8 * SC, 56 * SC }
local STACK_W, STACK_H, STACK_PAD = 330, 340, 16
local MAX_PLATES, MAX_DOTS, MAX_LIGHTS = 8, 14, 4

-- A point on the top face: u runs T to R, v runs T to L (both 0..1).
local function OnFace(u, v)
	return PT[1] + u * (PR[1] - PT[1]) + v * (PL[1] - PT[1]), PT[2] + u * (PR[2] - PT[2]) + v * (PL[2] - PT[2])
end

-- Where the people dots sit: a fixed scatter (golden-ratio steps), the whole face on the top plate and only the
-- front half (u + v > 1, the part no plate above covers) on the others.
local SCATTER = { full = {}, front = {} }
do
	local i = 1
	while #SCATTER.full < MAX_DOTS or #SCATTER.front < MAX_DOTS do
		local u, v = 0.12 + ((i * 0.618034) % 1) * 0.76, 0.12 + ((i * 0.754878) % 1) * 0.76
		local x, y = OnFace(u, v)
		if #SCATTER.full < MAX_DOTS then SCATTER.full[#SCATTER.full + 1] = { x, y } end
		if u + v > 1.15 and #SCATTER.front < MAX_DOTS then SCATTER.front[#SCATTER.front + 1] = { x, y } end
		i = i + 1
	end
end

--------------------------------------------------------------------------------
-- Motion helpers
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

-- A ring that keeps growing out and fading, every two seconds (the "you are here" ping). Off: a still ring.
local function Ping(region)
	local g = M.Group(region, "ping", function(group)
		local grow = M.Anim(group, "Scale", 1.6, 1, "OUT")
		grow:SetScaleFrom(0.6, 0.6)
		grow:SetScaleTo(1.6, 1.6)
		grow:SetOrigin("CENTER", 0, 0)
		local fade = M.Anim(group, "Alpha", 1.6, 1, "IN")
		fade:SetFromAlpha(0.9)
		fade:SetToAlpha(0)
		group:SetLooping("REPEAT")
		group.finish = function() region:SetAlpha(0.6) end
	end)
	if M.On() then
		if not g:IsPlaying() then M.Play(g) end
	else
		g:Stop()
		g.finish()
	end
end

--------------------------------------------------------------------------------
-- The stack
--------------------------------------------------------------------------------
local function PlacePlate(plate, ox, oy)
	plate:ClearAllPoints()
	plate:SetPoint("TOPLEFT", plate:GetParent(), "TOPLEFT", 12 + ox, -(plate.y or 0) + oy + (plate.lift or 0))
end

local function PaintEdge(page, plate)
	local item = plate.item
	if not item then return end
	local req = UI.data.MyRequest()
	local target = Pending(req) and req.mapID == item.mapID and req.targetZone == item.zoneUID
	if item.mine or target then
		UI.Paint(plate.edge, T.amber, 0.95)
	elseif page.selected == KeyOf(item) then
		UI.Paint(plate.edge, T.text, 0.9)
	elseif plate.hover then
		UI.Paint(plate.edge, T.text, 0.4)
	else
		UI.Paint(plate.edge, T.text, 0)
	end
end

local function CreatePlate(page, i)
	local stack = page.stack
	local plate = CreateFrame("Button", nil, stack)
	plate:SetSize(PW, PH)
	plate:SetFrameLevel(stack:GetFrameLevel() + 2 + i * 3)
	plate:SetHitRectInsets(18, 18, 14, 28)
	plate.slab = UI.Tex(plate, "slab", nil, PLATE_LOW, 1, "BACKGROUND")
	plate.slab:SetAllPoints()
	plate.edge = UI.Tex(plate, "slab-edge", nil, T.text, 0, "BORDER")
	plate.edge:SetAllPoints()
	plate.dots = {}
	for d = 1, MAX_DOTS do
		local dot = UI.Tex(plate, "dot", 5, T.text, 0.85, "ARTWORK")
		dot:Hide()
		plate.dots[d] = dot
	end
	plate.lights = {}
	for l = 1, MAX_LIGHTS do
		local t = 0.28 + (l - 1) * 0.17 -- along the front-left side, L to B
		local light = UI.Tex(plate, "blip", 20, T.amber, 1, "OVERLAY")
		light:SetPoint("CENTER", plate, "TOPLEFT", PL[1] + t * (PB[1] - PL[1]), -(PL[2] + t * (PB[2] - PL[2])) - 3)
		light:Hide()
		plate.lights[l] = light
	end
	-- The label column right of the plates: what is left of the stack's width, truncated past it.
	local labelW = STACK_W - 12 - PR[1] - 10 - 8
	plate.label = UI.Text(stack, "display", 13, T.text)
	plate.label:SetPoint("BOTTOMLEFT", plate, "TOPLEFT", PR[1] + 10, -PR[2] - 1)
	plate.label:SetWidth(labelW)
	plate.count = UI.Text(stack, "data", 11, T.muted)
	plate.count:SetPoint("TOPLEFT", plate, "TOPLEFT", PR[1] + 10, -PR[2] - 3)
	plate.count:SetWidth(labelW)
	plate:SetScript("OnEnter", function(self)
		self.hover = true
		PaintEdge(page, self)
		if not self.lift or self.lift == 0 then
			self.lift = 3
			M.Slide(self, PlacePlate, 0, -3, 0.12)
		end
	end)
	plate:SetScript("OnLeave", function(self)
		self.hover = false
		PaintEdge(page, self)
		if self.lift and self.lift ~= 0 then
			self.lift = 0
			M.Slide(self, PlacePlate, 0, 3, 0.12)
		end
	end)
	plate:SetScript("OnClick", function(self)
		if not self.item then return end
		local key = KeyOf(self.item)
		if page.selected ~= key then
			page.selected = key
			M.Press(self)
			UI:Refresh(true)
			page.detail.body:SetAlpha(0)
			M.Fade(page.detail.body, 1, 0.15)
		end
	end)
	page.plates[i] = plate
	return plate
end

-- The plates to draw, bottom to top by layer number. Past MAX_PLATES the
-- busiest stay, with mine and the selected one always among them.
local function StackItems(page, items)
	local keep = {}
	for _, item in ipairs(items) do keep[#keep + 1] = item end
	local more = 0
	if #keep > MAX_PLATES then
		table.sort(keep, function(a, b)
			local wa = (a.mine or KeyOf(a) == page.selected) and 1 or 0
			local wb = (b.mine or KeyOf(b) == page.selected) and 1 or 0
			if wa ~= wb then return wa > wb end
			return a.population > b.population
		end)
		more = #keep - MAX_PLATES
		for i = #keep, MAX_PLATES + 1, -1 do keep[i] = nil end
	end
	table.sort(keep, function(a, b) return a.zoneUID < b.zoneUID end)
	return keep, more
end

local function DrawStack(page, items)
	local list, more = StackItems(page, items)
	local n = #list
	local room = STACK_H - 2 * STACK_PAD - PH
	local step = n > 1 and math.min(56, room / (n - 1)) or 0
	local bottomY = n > 1 and (STACK_H - STACK_PAD - PH) or (STACK_H - PH) / 2
	local most = 1
	for _, item in ipairs(list) do most = math.max(most, item.population) end
	local seen, youAt = page.seenPlates or {}, nil
	page.seenPlates = {}
	for i, item in ipairs(list) do
		local plate = page.plates[i] or CreatePlate(page, i)
		local key = KeyOf(item)
		local wasHere = seen[key]
		plate.item = item
		plate.y = bottomY - (i - 1) * step
		page.seenPlates[key] = true
		if plate.boundKey ~= key or not plate:IsShown() then
			plate.boundKey = key
			plate.lift = 0
			plate:Show()
			if wasHere then
				PlacePlate(plate, 0, 0)
			else
				-- A layer heard for the first time drops into the stack; the higher, the later it lands.
				M.Slide(plate, PlacePlate, 0, 14, 0.22 + i * 0.04, true)
			end
		elseif not plate.hover then
			PlacePlate(plate, 0, 0)
		end
		UI.Paint(plate.slab, item.mine and PLATE_MINE or mix(PLATE_LOW, PLATE_HIGH, item.population / most))
		local spots = i == n and SCATTER.full or SCATTER.front
		for d, dot in ipairs(plate.dots) do
			local spot = spots[d]
			if d <= math.min(item.population, MAX_DOTS) and spot then
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", plate, "TOPLEFT", spot[1], -spot[2])
				dot:Show()
			else
				dot:Hide()
			end
		end
		for l, light in ipairs(plate.lights) do light:SetShown(l <= item.beacons) end
		plate.label:SetText(LayerName(item))
		UI.TextColor(plate.label, item.mine and T.amber or T.text)
		plate.label:Show()
		local req = UI.data.MyRequest()
		local target = Pending(req) and req.mapID == item.mapID and req.targetZone == item.zoneUID
		plate.count:SetText(target and L["Asking a beacon"] or Plural(item.population, L["1 player"], L["%d players"]))
		UI.TextColor(plate.count, target and T.amber or T.muted)
		plate.count:Show()
		PaintEdge(page, plate)
		-- New news on a plate: its lights (or its surface, with no beacon) pulse once.
		local newest = item.news and item.news[1] and item.news[1].t or 0
		if wasHere and newest > (plate.newsAt or newest) then M.Pulse(plate.slab, 1.04, 0.5) end
		plate.newsAt = newest
		if item.mine then youAt = plate end
	end
	for i = n + 1, #page.plates do
		local plate = page.plates[i]
		plate.item, plate.boundKey = nil, nil
		plate:Hide()
		plate.label:Hide()
		plate.count:Hide()
	end
	page.more:SetText(more > 0 and Plural(more, L["1 more layer not shown"], L["%d more layers not shown"]) or "")

	-- "You are here": a ping on my plate; when my layer changes, the ping travels to the new plate.
	local you = page.you
	if youAt then
		local x, y = PB[1], -(PT[2] + (PB[2] - PT[2]) * 0.68)
		you:SetFrameLevel(youAt:GetFrameLevel() + 1)
		local from = page.youKey and page.youY
		you.place = function(self, ox, oy)
			self:ClearAllPoints()
			self:SetPoint("CENTER", youAt, "TOPLEFT", x + ox, y + oy)
		end
		if from and page.youKey ~= KeyOf(youAt.item) and youAt.y ~= from then
			M.Slide(you, you.place, 0, youAt.y - from, 0.5, false, "IN_OUT")
		else
			you.place(you, 0, 0)
			-- The stack re-laid itself under me (my old layer emptied): the ping lands on its new plate.
			if from and page.youKey ~= KeyOf(youAt.item) then M.Pop(you, 0.35, 0.3) end
		end
		page.youKey, page.youY = KeyOf(youAt.item), youAt.y
		you:Show()
		Ping(you.ring)
	else
		you:Hide()
		page.youKey = nil
	end
end

--------------------------------------------------------------------------------
-- The detail panel: status of my request (or where I am), the selected layer, its news, the way there.
--------------------------------------------------------------------------------
local function Stat(parent, x, y, label)
	local s = {}
	s.value = UI.Text(parent, "display", 22, T.text)
	s.value:SetPoint("TOPLEFT", x, y)
	s.label = UI.Text(parent, "data", 11, T.muted)
	s.label:SetPoint("TOPLEFT", s.value, "BOTTOMLEFT", 0, -3)
	s.label:SetText(label)
	return s
end

local function BuildDetail(page)
	local D = UI.data
	local d = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(d, T.panel, T.line)
	d:SetPoint("TOPLEFT", STACK_W + 12, -52)
	d:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	d:SetHeight(STACK_H)
	page.detail = d

	-- Status: my request while there is one, otherwise where I am.
	d.ring = Kit.ProgressRing(d, 26)
	d.ring:SetPoint("TOPLEFT", 16, -18)
	d.halo = UI.Tex(d.ring, "ring", 26, T.amber, 1, "OVERLAY")
	d.halo:SetPoint("CENTER")
	d.halo:Hide()
	d.action = Kit.Button(d, L["Cancel"], "ghost", function()
		local req = D.MyRequest()
		if Pending(req) then D.CancelRequest() elseif D.CanUndo() then D.Undo() end
	end, { h = 24 })
	d.action:SetPoint("TOPRIGHT", -12, -16)
	d.status = UI.Text(d, "display", 14, T.text)
	d.status:SetPoint("TOPLEFT", 16, -18)
	d.status:SetPoint("RIGHT", d.action, "LEFT", -10, 0)
	d.statusSub = UI.Text(d, "data", 11, T.muted)
	d.statusSub:SetPoint("TOPLEFT", d.status, "BOTTOMLEFT", 0, -4)
	d.statusSub:SetPoint("RIGHT", d, "RIGHT", -14, 0)
	local rule = UI.Rule(d, T.line)
	rule:SetPoint("TOPLEFT", 1, -70)
	rule:SetPoint("TOPRIGHT", -1, -70)

	-- The selected layer; the body fades in when another plate is picked.
	local b = CreateFrame("Frame", nil, d)
	b:SetPoint("TOPLEFT", 0, -72)
	b:SetPoint("BOTTOMRIGHT", 0, 0)
	d.body = b
	b.title = UI.Text(b, "display", 22, T.text)
	b.title:SetPoint("TOPLEFT", 16, -16)
	b.tag = UI.Text(b, "data", 12, T.amber)
	b.tag:SetPoint("BOTTOMLEFT", b.title, "BOTTOMRIGHT", 10, 3)
	b.players = Stat(b, 16, -56, L["players heard"])
	b.beacons = Stat(b, 124, -56, L["beacons on duty"])
	b.groups = Stat(b, 232, -56, L["groups forming"])
	local s = Kit.Section(b, L["What's new"])
	s:SetPoint("TOPLEFT", 16, -118)
	s:SetPoint("RIGHT", b, "RIGHT", -16, 0)
	b.news = {}
	for i = 1, 3 do
		local line = {}
		line.dot = UI.Tex(b, "dot", 6, T.amber)
		line.dot:SetPoint("TOPLEFT", 18, -146 - (i - 1) * 21)
		line.ago = UI.Text(b, "data", 11, T.muted, "RIGHT")
		line.ago:SetPoint("TOPRIGHT", -16, -143 - (i - 1) * 21)
		line.text = UI.Text(b, "data", 12, T.text)
		line.text:SetPoint("TOPLEFT", 32, -143 - (i - 1) * 21)
		line.text:SetPoint("RIGHT", line.ago, "LEFT", -8, 0)
		b.news[i] = line
	end
	b.quiet = UI.Text(b, "data", 12, T.muted)
	b.quiet:SetPoint("TOPLEFT", 18, -143)
	b.quiet:SetText(L["Nothing new here yet."])
	b.why = UI.Text(b, "data", 11, T.muted, "CENTER")
	b.why:SetPoint("BOTTOMLEFT", 16, 54)
	b.why:SetPoint("BOTTOMRIGHT", -16, 54)
	b.why:SetWordWrap(true)
	b.why:SetJustifyV("BOTTOM")
	b.why:SetHeight(28)
	b.go = Kit.Button(b, L["Go here"], "primary", function(btn)
		local ok, why = D.RequestLayer(btn.item)
		if ok then btn:Done(L["Asking"]) else btn:Fail(D.Reason(why)) end
	end, { h = 32 })
	b.go:SetPoint("BOTTOMLEFT", 16, 16)
	b.go:SetPoint("BOTTOMRIGHT", -16, 16)
end

local STATE_TEXT = {
	sent = { L["Asking a beacon"], L["Each beacon gets 40 s, then the next one."] },
	accepted = { L["A beacon is inviting you"], L["Accept the invite to come over."] },
	served = { L["In the beacon's group"], L["Click the game's switch prompt, or wait about 5 minutes."] },
	hopped = { L["On the new layer"], L["Leave the group when you are done."] },
	expired = { L["No beacon could take you"], L["Try again in a moment."] },
}

local function RefreshStatus(page, me, count)
	local D, d = UI.data, page.detail
	local req = D.MyRequest()
	local text = req and STATE_TEXT[req.state]
	if text then
		d.status:SetPoint("TOPLEFT", 52, -18)
		d.status:SetText(text[1])
		d.statusSub:SetText(text[2])
		d.ring:Show()
		if req.state == "sent" then
			-- askedAt is time(); the ring runs on GetTime().
			d.ring:Start(D.ASK_TTL, GetTime() - math.max(0, time() - (req.askedAt or req.t or time())))
		elseif req.state == "served" then
			-- The game moves me by itself after about five minutes (its prompt does it at once).
			d.ring:Start(D.SWITCH_WAIT, GetTime() - math.max(0, time() - (req.stateAt or time())))
		else
			d.ring:Stop()
			d.ring:SetFraction(req.state == "expired" and 0 or 1)
		end
		local waiting = req.state == "sent" or req.state == "served"
		d.ring:SetColor(req.state == "expired" and T.muted or (waiting and T.amber or T.ok))
		-- The ring flashes once when the invite is on its way.
		if req.state == "accepted" and page.lastState ~= "accepted" then M.Ripple(d.halo, 1.6, 0.7) end
	else
		d.ring:Stop()
		d.ring:Hide()
		d.status:SetPoint("TOPLEFT", 16, -18)
		d.status:SetText(UI.Esc(MapName(me.mapID)))
		if me.inInstance then
			d.statusSub:SetText(L["No layers inside an instance."])
		elseif me.zoneUID then
			d.statusSub:SetText(string.format(L["You are on layer %d; %d layers heard here"], me.zoneUID, count))
		else
			d.statusSub:SetText(L["Target any creature to find your layer."])
		end
	end
	page.lastState = req and req.state
	local undoMine = req and (req.state == "served" or req.state == "hopped") and D.CanUndo()
	if Pending(req) then
		d.action:SetLabel(L["Cancel"])
		d.action:SetKind("ghost")
		d.action:Show()
	elseif undoMine then
		d.action:SetLabel(L["Leave group"])
		d.action:SetKind("secondary")
		d.action:Show()
	else
		d.action:Hide()
	end
end

local function RefreshDetail(page, item)
	local b = page.detail.body
	b:SetShown(item ~= nil)
	if not item then return end
	b.title:SetText(LayerName(item))
	b.tag:SetText(item.mine and L["You are here"] or "")
	b.players.value:SetText(tostring(item.population))
	b.beacons.value:SetText(tostring(item.beacons))
	UI.TextColor(b.beacons.value, item.beacons > 0 and T.amber or T.text)
	b.groups.value:SetText(tostring(item.groups))
	-- Rares alive on this layer come first, then the layer's own news.
	local now, any, lines = time(), false, {}
	for _, r in ipairs(item.rares or {}) do
		lines[#lines + 1] = { text = string.format(L["Rare: %s"], UI.Esc(r.name)), ago = r.ago, rare = true }
	end
	for _, n in ipairs(item.news or {}) do
		lines[#lines + 1] = { text = NewsText(n), ago = now - n.t }
	end
	for i, line in ipairs(b.news) do
		local n = lines[i]
		line.dot:SetShown(n ~= nil)
		UI.Paint(line.dot, n and n.rare and T.bad or T.amber)
		line.text:SetText(n and n.text or "")
		line.ago:SetText(n and UI.Ago(n.ago) or "")
		any = any or n ~= nil
	end
	b.quiet:SetShown(not any)

	local req = UI.data.MyRequest()
	b.go.item = item
	if b.go.boundKey ~= KeyOf(item) then
		b.go.boundKey = KeyOf(item)
		b.go:Unmorph()
	end
	b.go:Settle(string.format(L["Go to layer %d"], item.zoneUID))
	b.go:SetShown(not item.mine)
	b.go:SetEnabled(item.canRequest == true and not Pending(req))
	if item.mine then
		b.why:SetText(L["You are on this layer. Beacons on other layers can bring you to theirs."])
	elseif Pending(req) then
		b.why:SetText(L["One request at a time: wait for this one or cancel it."])
	elseif not item.canRequest then
		b.why:SetText(L["No beacon on duty here right now."])
	else
		b.why:SetText(L["A beacon here invites you; accept, then switch layers."])
	end
end

--------------------------------------------------------------------------------
-- The beacon strip
--------------------------------------------------------------------------------
local function BuildBeacon(page)
	local D = UI.data
	local b = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(b, T.panel, T.line)
	b:SetPoint("TOPLEFT", 0, -52 - STACK_H - 12)
	b:SetPoint("BOTTOMRIGHT", 0, 0)
	page.beacon = b

	b.ring = Kit.Ring(b, 64, T.amber)
	b.ring:SetPoint("LEFT", 16, 0)
	b.ring:SetFraction(0)
	b.glow = UI.Tex(b.ring, "blip", 38, T.amber, 1, "ARTWORK")
	b.glow:SetPoint("CENTER")
	b.halo = UI.Tex(b.ring, "ring", 64, T.amber, 1, "OVERLAY")
	b.halo:SetPoint("CENTER")
	b.halo:Hide()
	b.plus = UI.Text(b, "display", 16, T.amber, "CENTER")
	b.plus:SetPoint("BOTTOM", b.ring, "TOP", 0, -12)
	b.plus:SetText("+1")
	b.plus:SetAlpha(0)

	b.toggle = Kit.Check(b, L["Beacon"], true, function(on) D.SetBeacon(on) end)
	b.toggle:SetPoint("BOTTOMRIGHT", -14, 12)
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

	b.rank = UI.Text(b, "display", 16, T.text)
	b.rank:SetPoint("TOPLEFT", 96, -16)
	b.hops = UI.Text(b, "data", 12, T.muted)
	b.hops:SetPoint("TOPLEFT", 96, -40)
	b.next = UI.Text(b, "data", 12, T.muted)
	b.next:SetPoint("TOPLEFT", 96, -57)
	b.duty = UI.Text(b, "data", 12, T.text)
	b.duty:SetPoint("TOPLEFT", 330, -40)
	b.duty:SetPoint("RIGHT", b.toggle, "LEFT", -12, 0)
	b.duty:SetWordWrap(true)
	b.duty:SetJustifyV("TOP")
	b.duty:SetHeight(44)
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
	if queue > 0 then b.serve:Settle(string.format(L["Invite next (%d)"], queue)) end
	local hoppers = false
	for _, r in ipairs(D.LayerRequests()) do hoppers = hoppers or r.state == "served" or r.state == "arrived" end
	b.undo:SetShown(queue == 0 and b.serve.rest == nil and hoppers)
	-- Going on duty sends one ripple from the light.
	if st.available and not page.breathing then
		page.breathing = true
		M.Ripple(b.halo, 1.5, 1.6)
	elseif not st.available then
		page.breathing = nil
	end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
local function Build(page)
	Kit.PageHead(page, L["Layer"],
		L["The copies of the zone you are in. Beacons bring you to theirs with an invite."])
	local stack = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(stack, T.well, T.line)
	stack:SetPoint("TOPLEFT", 0, -52)
	stack:SetSize(STACK_W, STACK_H)
	page.stack = stack
	page.plates = {}
	page.more = UI.Text(stack, "data", 11, T.muted)
	page.more:SetPoint("TOPLEFT", 12, -10)
	page.empty = Kit.Empty(stack)
	page.empty:SetPoint("CENTER", 0, 10)
	page.empty:SetWidth(290)
	page.empty.title:SetWidth(290)
	page.empty.body:SetWidth(290)
	page.empty:Hide()

	local you = CreateFrame("Frame", nil, stack)
	you:SetSize(30, 30)
	you.ring = UI.Tex(you, "ring", 30, T.amber, 0.6, "ARTWORK")
	you.ring:SetPoint("CENTER")
	you.dot = UI.Tex(you, "blip", 22, T.amber, 1, "OVERLAY")
	you.dot:SetPoint("CENTER")
	you.label = UI.Text(you, "display", 11, T.amber, "CENTER")
	you.label:SetPoint("BOTTOM", you, "TOP", 0, -4)
	you.label:SetText(L["You"])
	you:Hide()
	page.you = you

	BuildDetail(page)
	BuildBeacon(page)
end

local function Refresh(page)
	local D = UI.data
	local me = D.Layer()
	local items = {}
	for _, item in ipairs(D.Layers()) do
		if item.sameMap then items[#items + 1] = item end
	end
	-- The selected plate stays while it is heard; otherwise one with a beacon to ask, else mine.
	local selected
	for _, item in ipairs(items) do
		if KeyOf(item) == page.selected then selected = item end
	end
	if not selected then
		for _, item in ipairs(items) do
			if item.canRequest and (not selected or item.beacons > selected.beacons) then selected = item end
		end
		for _, item in ipairs(items) do
			if not selected and item.mine then selected = item end
		end
		selected = selected or items[1]
		page.selected = selected and KeyOf(selected) or nil
	end

	if me.inInstance then
		page.empty:Set(L["No layers inside an instance"], L["Back outside, your zone's layers show here."])
	elseif #items == 0 then
		page.empty:Set(L["No layer heard here yet"],
			L["Target any creature to find yours. Others show up as Chehul addon users announce theirs."])
	end
	page.empty:SetShown(me.inInstance or #items == 0)
	DrawStack(page, me.inInstance and {} or items)
	RefreshStatus(page, me, #items)
	RefreshDetail(page, not me.inInstance and selected or nil)
	RefreshBeacon(page)
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
	UI:ClearPrompts(prompt)
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
-- The shown request answered, expired or dropped (the core deletes it without a state change): the next one.
local function StillOpen(req)
	for _, r in ipairs(UI.data.LayerRequests()) do
		if r == req then return r.state == "open" end
	end
	return false
end
UI:Listen("layer", function()
	if prompt and prompt.req and not StillOpen(prompt.req) then
		prompt.req = nil
		ShowNext()
	end
end)

--------------------------------------------------------------------------------
-- A rare alive in my zone, told by the network: a prompt from the top of the screen, window open or not. Go
-- (a beacon of that layer brings me over) or Mark (the game's map pin at the reporter's spot), each from its own
-- click; otherwise it leaves by itself.
--------------------------------------------------------------------------------
local rarePrompt

local function RareBody(r)
	local where = r.here and L["On your layer"] or string.format(L["On layer %d of this zone"], r.zoneUID)
	local pos = r.x and string.format(L["near %.1f, %.1f"], r.x / 10, r.y / 10) or nil
	local parts = { where, r.ago < 10 and L["Just now"] or string.format(L["%s ago"], UI.Ago(r.ago)) }
	if pos then parts[#parts + 1] = pos end
	return table.concat(parts, ". ")
end

local function ShowRare(r)
	if not rarePrompt then
		rarePrompt = Kit.Toast(UIParent)
		rarePrompt:SetFrameStrata("DIALOG")
		UI.rarePrompt = rarePrompt
	end
	local actions = {}
	if r.canGo then
		actions[#actions + 1] = { label = L["Go to that layer"], fn = function()
			local ok, why = UI.data.GoToRare(r)
			if not ok then UI:Notify("notice", UI.data.Reason(why)) end
		end }
	end
	if r.canMark then
		actions[#actions + 1] = { label = L["Mark on map"], kind = #actions == 0 and "primary" or "ghost", fn = function()
			local ok, why = UI.data.MarkRare(r)
			if not ok then UI:Notify("notice", UI.data.Reason(why)) end
		end }
	end
	rarePrompt:Pop(string.format(L["Rare: %s"], UI.Esc(r.name)), RareBody(r),
		{ hold = 20, color = T.bad, actions = actions })
end

UI:Listen("rare", function(r)
	if type(r) ~= "table" or not r.alive then return end
	UI:WhenPromptFree(function() ShowRare(r) end)
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
