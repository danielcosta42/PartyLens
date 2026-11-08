--=============================================================================
-- Layer: your layer, the nodes the network hears on other layers, your request and the ones for your layer.
-- Asking whispers the node; the node's player invites you with a click; a ring fills while you wait.
-- Serving, asking and undoing run straight from their buttons' OnClick (the game needs the click for the
-- invite, the uninvite and leaving; the core counts on it for the rest).
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, M, Kit = UI.T, UI.Motion, UI.Kit
local L = UI.L

local function MapName(mapID)
	local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if type(info) == "table" and info.name then return info.name end
	return mapID and string.format(L["map %d"], mapID) or ""
end

local function Pending(req)
	return req ~= nil and (req.state == "sent" or req.state == "accepted")
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------
local function CreateNode(row)
	local D = UI.data
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.edge = UI.Fill(row, T.amber, 1, "ARTWORK")
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetWidth(3)
	row.name = UI.Text(row, "data", 13)
	row.name:SetPoint("LEFT", 14, 0)
	row.layer = UI.Text(row, "display", 13, T.text)
	row.layer:SetPoint("LEFT", 210, 0)
	row.heard = UI.Text(row, "data", 12, T.muted)
	row.heard:SetPoint("LEFT", 330, 0)
	row.ask = Kit.Button(row, L["Ask for this layer"], "secondary", function(b)
		local ok, why = D.RequestLayer(row.item)
		if ok then b:Done(L["Asked"]) else b:Fail(D.Reason(why)) end
	end, { h = 24, minWidth = 132 })
	row.ask:SetPoint("RIGHT", -10, 0)
	Kit.Tip(row.ask, function(b)
		local n = b.node
		if not n then return end
		if n.canRequest then return L["Ask for this layer"], L["Whispers them the request. They invite you with a click."] end
		if n.sameLayer then return L["Ask for this layer"], L["You are on this layer already."] end
		if not n.sameMap then return L["Ask for this layer"], L["They are in another zone."] end
		return L["Ask for this layer"], L["Only players with PartyLens can answer a request."]
	end)
end

local function BindNode(row, n, _, list)
	local page = list.page
	row.name:SetText(UI.Esc(n.name))
	if n.sameLayer then
		row.layer:SetText(L["your layer"])
	elseif n.sameMap and n.ordinal then
		row.layer:SetText(string.format(L["layer %d"], n.ordinal))
	elseif n.sameMap then
		row.layer:SetText(L["another layer"]) -- one I have not seen myself: no number yet
	else
		row.layer:SetText(L["another zone"])
	end
	UI.TextColor(row.layer, n.sameMap and T.text or T.muted)
	row.heard:SetText(string.format(L["heard %s ago"], UI.Ago(n.ago or 0)))
	local ctx = page.context
	row.edge:SetShown(ctx ~= nil and ctx.zoneUID ~= nil and ctx.zoneUID == n.zoneUID and ctx.mapID == n.mapID)
	if row.boundId ~= n.key then
		row.boundId = n.key
		row.ask:Unmorph()
	end
	row.ask.node = n
	row.ask:SetEnabled(n.canRequest == true and not Pending(UI.data.MyRequest()))
end

local REQUEST_STATE = { invited = L["Invite sent"], served = L["In your group"], declined = L["Declined"] }

local function CreateRequest(row)
	local D = UI.data
	row.bg = UI.Fill(row, T.panel)
	row.bg:SetAllPoints()
	row.edge = UI.Fill(row, T.amber, 1, "ARTWORK")
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetWidth(3)
	row.text = UI.Text(row, "data", 13)
	row.text:SetPoint("LEFT", 14, 0)
	row.state = UI.Text(row, "data", 12, T.muted, "RIGHT")
	row.state:SetPoint("RIGHT", -14, 0)
	row.decline = Kit.Button(row, L["Decline"], "ghost", function() D.Decline(row.item) end, { h = 24 })
	row.decline:SetPoint("RIGHT", -10, 0)
	row.invite = Kit.Button(row, L["Invite"], "primary", function(b)
		local ok, why = D.Serve(row.item)
		if ok then b:Done(L["Invited"]) else b:Fail(D.Reason(why)) end
	end, { w = 76, h = 24 })
	row.invite:SetPoint("RIGHT", row.decline, "LEFT", -6, 0)
	row.undo = Kit.Button(row, L["Remove from group"], "secondary", function() D.Undo() end, { h = 24 })
	row.undo:SetPoint("RIGHT", -10, 0)
end

local function BindRequest(row, r)
	local open = r.state == "open"
	row.text:SetText(string.format(L["%s wants your layer"], UI.Esc(r.name)))
	row.edge:SetShown(open)
	if row.boundId ~= r.key then
		row.boundId = r.key
		row.invite:Unmorph()
	end
	row.invite:SetShown(open or row.invite.rest ~= nil)
	row.decline:SetShown(open)
	local undo = r.state == "served" and UI.data.CanUndo()
	row.undo:SetShown(undo)
	row.state:SetText((not open and not undo and REQUEST_STATE[r.state]) or "")
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
local function Build(page)
	local D = UI.data
	Kit.PageHead(page, L["Layer"], L["See your layer and ask the network for another one."])

	local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
	UI.Backdrop(card, T.panel, T.line)
	card:SetPoint("TOPLEFT", 0, -54)
	card:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	card:SetHeight(92)
	page.card = card
	card.label = UI.Text(card, "data", 12, T.muted)
	card.label:SetPoint("TOPLEFT", 18, -14)
	card.label:SetText(L["Your layer"])
	card.number = UI.Text(card, "display", 30, T.text)
	card.number:SetPoint("TOPLEFT", 18, -32)
	card.zone = UI.Text(card, "data", 12, T.muted)
	card.zone:SetPoint("BOTTOMLEFT", card.number, "BOTTOMRIGHT", 12, 4)
	card.zone:SetWidth(160)

	card.ring = Kit.ProgressRing(card, 44)
	card.ring:SetPoint("LEFT", card, "LEFT", 240, 0)
	card.halo = UI.Tex(card.ring, "ring", 44, T.amber, 1, "OVERLAY")
	card.halo:SetPoint("CENTER")
	card.halo:Hide()
	card.action = Kit.Button(card, L["Cancel"], "ghost", function()
		local req = D.MyRequest()
		if Pending(req) then D.CancelRequest() elseif D.CanUndo() then D.Undo() end
	end, { h = 24 })
	card.action:SetPoint("RIGHT", -14, 0)
	card.wait = UI.Text(card, "display", 13, T.text)
	card.wait:SetPoint("TOPLEFT", card.ring, "TOPRIGHT", 14, -4)
	card.wait:SetPoint("RIGHT", card.action, "LEFT", -12, 0)
	card.waitSub = UI.Text(card, "data", 12, T.muted)
	card.waitSub:SetPoint("TOPLEFT", card.wait, "BOTTOMLEFT", 0, -4)
	card.waitSub:SetPoint("RIGHT", card.action, "LEFT", -12, 0)

	local s1 = Kit.Section(page, L["Other layers in this zone"])
	s1:SetPoint("TOPLEFT", 0, -164)
	s1:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.nodes = Kit.List(page, { rowHeight = 40, gap = 4, create = CreateNode, bind = BindNode, width = UI.PAGE_W - 12,
		viewHeight = 170, emptyTop = 24 })
	page.nodes.page = page
	page.nodes:SetPoint("TOPLEFT", 0, -190)
	page.nodes:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.nodes:SetHeight(176)

	local s2 = Kit.Section(page, L["Requests for your layer"])
	s2:SetPoint("TOPLEFT", 0, -378)
	s2:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.requests = Kit.List(page, { rowHeight = 40, gap = 4, create = CreateRequest, bind = BindRequest,
		width = UI.PAGE_W - 12, viewHeight = 84, emptyTop = 6 })
	page.requests:SetPoint("TOPLEFT", 0, -404)
	page.requests:SetPoint("BOTTOMRIGHT", 0, 0)
	page.lastState = nil
end

local STATE_TEXT = {
	sent = { L["Waiting for %s"], L["Asked for their layer. Accept the invite when it comes."] },
	accepted = { L["%s is inviting you"], L["Accept the invite to join their layer."] },
	served = { L["In %s's group"], L["Your layer changes once you see a creature there."] },
	hopped = { L["On %s's layer now"], L["Leave the group when you are done."] },
	expired = { L["No answer from %s"], L["Ask someone else below."] },
}

local function Refresh(page)
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
		card.wait:SetText(string.format(text[1], UI.Esc(req.name)))
		card.waitSub:SetText(text[2])
		card.ring:Show()
		if req.state == "sent" then
			-- req.t is time(); the ring runs on GetTime().
			card.ring:Start(D.REQUEST_TTL, GetTime() - math.max(0, time() - (req.t or time())))
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
		card.wait:SetText(D.CanUndo() and L["You moved through a layer group"] or "")
		card.waitSub:SetText(D.CanUndo() and L["Leave the group when you are done."] or "")
	end
	page.lastState = req and req.state
	if Pending(req) then
		card.action:SetLabel(L["Cancel"])
		card.action:SetKind("ghost")
		card.action:Show()
	elseif D.CanUndo() then
		card.action:SetLabel(L["Leave group"])
		card.action:SetKind("secondary")
		card.action:Show()
	else
		card.action:Hide()
	end

	page.nodes:SetEmpty(L["Nobody else here right now"],
		L["Players with PartyLens or another ChehulNet addon in another layer of this zone show up here."])
	page.nodes:SetItems(D.LayerNodes())
	page.requests:SetEmpty(L["No requests"], L["When someone asks for your layer, you invite them from here."])
	page.requests:SetItems(D.ActiveRequests())
end

-- Someone asks for my layer: a toast with Invite and Decline (Invite serves it from its own OnClick).
UI:Listen("layerRequest", function(req)
	if not (req and UI:IsOpen()) then return end
	UI:Toast(string.format(L["%s wants your layer"], UI.Esc(req.name)),
		L["Invite them to your group to bring them over."], {
		hold = 20,
		actions = {
			{ label = L["Invite"], fn = function() UI.data.Serve(req) end },
			{ label = L["Decline"], kind = "ghost", fn = function() UI.data.Decline(req) end },
		},
	})
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
