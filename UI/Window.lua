--=============================================================================
-- The window: header (mark, title, live status, network badge, close), sidebar with a sliding indicator, and a
-- content area where pages cross-fade. Pages register themselves:
--
--   UI:RegisterPage(key, { label, icon, order, build(page), refresh(page), onShow(page), badge(page) })
--     build runs once, the first time the page is shown; refresh on every show, every data change and every
--     few seconds while visible; badge returns (text, colour) for the sidebar.
--   UI:Open(key, context)  UI:Toggle()  UI:Close()  UI:Refresh()  UI:Toast(title, body, opts)
-- The core reaches the UI only through PartyLens.UI:Toggle() and PartyLens.UI:Open(key, context).
--=============================================================================
local ADDON, ns = ...
local UI = ns.UI
local T, M, Kit = UI.T, UI.Motion, UI.Kit
local L = UI.L

local W, H, HEAD, SIDE, NAV_H = 920, 600, 48, 184, 40
local PAD_X, PAD_TOP, PAD_BOTTOM = 24, 20, 18
UI.PAGE_W = W - SIDE - 2 - 2 * PAD_X
UI.PAGE_H = H - HEAD - 2 - PAD_TOP - PAD_BOTTOM
UI.ORDER = { "groups", "announce", "layer", "summon", "network", "settings" }
UI.pages, UI.pageFrames = {}, {}

function UI:RegisterPage(key, def)
	def.key = key
	self.pages[key] = def
	if self.frame then self:BuildNav() end
end

local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
end

-- Runs a page callback; an error goes to the error frame instead of breaking the window.
local function Call(fn, page)
	if not fn then return true end
	local ok, err = pcall(fn, page)
	if not ok then Report(err) end
	return ok
end

--------------------------------------------------------------------------------
-- Internal bus: data adapters notify, pages listen. Every notice also refreshes the visible page.
--------------------------------------------------------------------------------
local subs = {}
function UI:Listen(what, fn)
	subs[what] = subs[what] or {}
	table.insert(subs[what], fn)
end

function UI:Notify(what, ...)
	for _, fn in ipairs(subs[what] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then Report(err) end
	end
	self:Refresh()
end

-- The core's feedback (already localized): a toast while the window is open, a chat line while it is closed
-- (the core stays quiet in chat when a UI exists).
UI:Listen("notice", function(text)
	if type(text) ~= "string" or text == "" then return end
	if UI:IsOpen() then
		UI:Toast(UI.Esc(text), nil, { hold = 3 })
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(UI.Hex(T.amber) .. "PartyLens|r: " .. UI.Esc(text))
	end
end)

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
function UI:SavePosition()
	local p, _, rp, x, y = self.frame:GetPoint(1)
	if p then self:SetSetting("pos", { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }) end
end

function UI:RestorePosition()
	local f, pos = self.frame, self:Setting("pos")
	f:ClearAllPoints()
	if type(pos) == "table" and pos[1] then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3] or 0, pos[4] or 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

local function Version()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	if not v or v:find("^@") then return "dev" end
	return v
end

function UI:BuildHeader(f)
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", -1, -1)
	head:SetHeight(HEAD - 1)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() f:StartMoving() end)
	head:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		UI:SavePosition()
	end)
	self.head = head
	local rule = UI.Rule(head, T.line)
	rule:SetPoint("BOTTOMLEFT", 0, -1)
	rule:SetPoint("BOTTOMRIGHT", 0, -1)

	head.mark = UI.Tex(head, "mark", 24, T.amber)
	head.mark:SetPoint("LEFT", 18, 0)
	head.title = UI.Text(head, "display", 16)
	head.title:SetPoint("LEFT", head.mark, "RIGHT", 10, 0)
	head.title:SetText("PartyLens")
	head.status = UI.Text(head, "data", 13, T.muted)
	head.status:SetPoint("LEFT", head.title, "RIGHT", 16, -1)

	head.close = Kit.IconButton(head, "close", 28, function() UI:Close() end, L["Close"], L["Esc closes it too."])
	head.close:SetPoint("RIGHT", -10, 0)

	-- The network badge: how many nodes this client hears; a click opens the Network page.
	local net = CreateFrame("Button", nil, head)
	net:SetSize(110, 28)
	net:SetPoint("RIGHT", head.close, "LEFT", -12, 0)
	net.dot = UI.Tex(net, "dot", 8, T.muted)
	net.dot:SetPoint("LEFT", 6, 0)
	net.label = UI.Text(net, "data", 13, T.muted)
	net.label:SetPoint("LEFT", net.dot, "RIGHT", 7, 0)
	net:SetScript("OnEnter", function(btn) UI.TextColor(btn.label, T.text) end)
	net:SetScript("OnLeave", function(btn) UI.TextColor(btn.label, T.muted) end)
	net:SetScript("OnClick", function() UI:Open("network") end)
	Kit.Tip(net, L["Network"],
		L["Players with PartyLens or another ChehulNet addon heard in the last minutes. Click for the list."])
	head.net = net
	head.status:SetPoint("RIGHT", net, "LEFT", -12, 0)
end

function UI:BuildSidebar(f)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 1, -HEAD)
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(SIDE)
	UI.Fill(side, T.panel):SetAllPoints()
	local edge = UI.Rule(side, T.line, true)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	self.side = side

	local ind = CreateFrame("Frame", nil, side)
	ind:SetSize(SIDE - 1, NAV_H)
	ind.bg = UI.Fill(ind, T.raised)
	ind.bg:SetAllPoints()
	ind.bar = UI.Fill(ind, T.amber, 1, "ARTWORK")
	ind.bar:SetPoint("TOPLEFT")
	ind.bar:SetPoint("BOTTOMLEFT")
	ind.bar:SetWidth(3)
	ind:Hide()
	self.indicator = ind

	local version = UI.Text(side, "data", 11, T.faint)
	version:SetPoint("BOTTOMLEFT", 20, 14)
	version:SetText("PartyLens " .. Version() .. ",  /pl")
	self.nav = {}
	self:BuildNav()
end

local function NavY(index) return -14 - (index - 1) * NAV_H end

function UI:SortedPages()
	local list = {}
	for _, def in pairs(self.pages) do list[#list + 1] = def end
	local rank = {}
	for i, key in ipairs(self.ORDER) do rank[key] = i end
	table.sort(list, function(a, b)
		local ra, rb = a.order or rank[a.key] or 99, b.order or rank[b.key] or 99
		if ra ~= rb then return ra < rb end
		return a.key < b.key
	end)
	return list
end

function UI:BuildNav()
	if not self.side then return end
	for i, def in ipairs(self:SortedPages()) do
		local b = self.nav[def.key]
		if not b then
			b = CreateFrame("Button", nil, self.side)
			b:SetSize(SIDE - 1, NAV_H)
			b.icon = UI.Tex(b, def.icon or "mark", 18, T.muted)
			b.icon:SetPoint("LEFT", 20, 0)
			b.label = UI.Text(b, "display", 13, T.muted)
			b.label:SetPoint("LEFT", 48, 0)
			b.badge = UI.Text(b, "data", 12, T.muted, "RIGHT")
			b.badge:SetPoint("RIGHT", -16, 0)
			b.key = def.key
			b:SetScript("OnEnter", function(btn) if UI.current ~= btn.key then UI.TextColor(btn.label, T.text) end end)
			b:SetScript("OnLeave", function(btn) if UI.current ~= btn.key then UI.TextColor(btn.label, T.muted) end end)
			b:SetScript("OnClick", function(btn) UI:Open(btn.key) end)
			self.nav[def.key] = b
		end
		b.label:SetText(def.label)
		b.index = i
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.side, "TOPLEFT", 0, NavY(i))
	end
end

function UI:Build()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "PartyLensWindow", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	if f.SetDontSavePosition then f:SetDontSavePosition(true) end
	UI.Backdrop(f, T.bg, T.line)
	tinsert(UISpecialFrames, "PartyLensWindow")
	self.frame = f
	self:RestorePosition()
	self:BuildHeader(f)
	self:BuildSidebar(f)

	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", SIDE + 1, -HEAD)
	content:SetPoint("BOTTOMRIGHT", -1, 1)
	self.content = content
	self.toast = Kit.Toast(content)

	-- Closing mid-motion: the game stops the groups without OnFinished, so their end states land here (a page
	-- caught fading out would otherwise stay shown at alpha 0 and take clicks).
	f:SetScript("OnHide", function(frame)
		Kit.CloseMenu()
		M.SettleAll(frame)
		if UI.toast then UI.toast:Hide() end
	end)
	-- While open, the visible page refreshes every 5 s (ages, freshness rings).
	f.acc = 0
	f:SetScript("OnUpdate", function(frame, elapsed)
		frame.acc = frame.acc + elapsed
		if frame.acc >= 5 then
			frame.acc = 0
			UI:Refresh(true)
		end
	end)
	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
function UI:PageFrame(key)
	local page = self.pageFrames[key]
	if page then return page end
	local def = self.pages[key]
	page = CreateFrame("Frame", nil, self.content)
	page:SetPoint("TOPLEFT", PAD_X, -PAD_TOP)
	page:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_BOTTOM)
	page:Hide()
	page.key, page.def = key, def
	self.pageFrames[key] = page
	page.built = Call(def.build, page)
	if not page.built then
		local msg = UI.Text(page, "display", 14, T.text)
		msg:SetPoint("TOPLEFT")
		msg:SetText(L["This page could not load."])
		local sub = UI.Text(page, "data", 12, T.muted)
		sub:SetPoint("TOPLEFT", msg, "BOTTOMLEFT", 0, -6)
		sub:SetText(L["The error went to your error frame. Reloading the interface usually fixes it."])
	end
	return page
end

function UI:MoveIndicator(key, from)
	local ind, b = self.indicator, self.nav[key]
	if not b then return end
	local fromB = from and self.nav[from]
	local function place(region, ox, oy)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", UI.side, "TOPLEFT", ox, NavY(UI.nav[UI.current].index) + oy)
	end
	ind:Show()
	if fromB and fromB ~= b then
		M.Slide(ind, place, 0, NavY(fromB.index) - NavY(b.index), M.SLIDE, false, "IN_OUT")
	else
		place(ind, 0, 0)
	end
	for k, nb in pairs(self.nav) do
		local on = k == key
		UI.TextColor(nb.label, on and T.text or T.muted)
		UI.Paint(nb.icon, on and T.amber or T.muted)
	end
end

function UI:ShowPage(key, context)
	if not self.pages[key] then key = self:SortedPages()[1].key end
	local page = self:PageFrame(key)
	local from = self.current
	local old = from and self.pageFrames[from]
	self.current = key
	self:SetSetting("page", key)
	-- Only the target and the page it replaces may be on screen; anything else (a fade cut short) goes now.
	for k, other in pairs(self.pageFrames) do
		if k ~= key and other ~= old then
			M.Settle(other, "fade")
			other:Hide()
		end
	end
	if old and old ~= page then M.Fade(old, 0, M.PAGE, true) end
	page.context = context
	if old ~= page then
		if not page:IsShown() then page:SetAlpha(0) end
		M.Fade(page, 1, M.PAGE)
		self:MoveIndicator(key, from)
	end
	if page.built and (old ~= page or context) then Call(page.def.onShow, page) end
	self:RefreshNow()
	return page
end

--------------------------------------------------------------------------------
-- Open, close, refresh
--------------------------------------------------------------------------------
function UI:IsOpen()
	return self.frame and self.frame:IsShown() or false
end

-- `context` (from the core, e.g. the inter-addon API) reaches the page as page.context in onShow.
function UI:Open(key, context)
	local f = self:Build()
	if not f:IsShown() then
		M.Fade(f, 1, 0.12)
	end
	return self:ShowPage(key or self.current or self:Setting("page"), context)
end

function UI:Close()
	if self.frame then self.frame:Hide() end
end

function UI:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end

function UI:RefreshHeader()
	local head, D = self.head, self.data
	local st = D and D.Status and D.Status() or {}
	local radar = string.format(L["%d on the radar"], st.total or 0)
	if st.listening then
		head.status:SetText(string.format(L["Listening to %s, %s"], UI.Esc(st.channel), radar))
	else
		head.status:SetText(radar)
	end
	UI.Paint(head.mark, (st.listening or (st.total or 0) > 0) and T.amber or T.muted)
	local nodes = st.nodes or 0
	head.net.label:SetText(string.format(L["Network %d"], nodes))
	UI.Paint(head.net.dot, nodes > 0 and T.ok or T.muted)
	head.net:SetWidth(math.ceil(head.net.label:GetStringWidth()) + 28)
	for key, b in pairs(self.nav) do
		local def = self.pages[key]
		local text, color
		if def and def.badge then
			local page = self.pageFrames[key]
			local ok, t, c = pcall(def.badge, page and page.built and page or nil)
			if ok then text, color = t, c else Report(t) end
		end
		b.badge:SetText(text or "")
		UI.TextColor(b.badge, color or T.muted)
	end
end

function UI:RefreshNow()
	self.pending = false
	if not self:IsOpen() then return end
	self:RefreshHeader()
	local page = self.current and self.pageFrames[self.current]
	if page and page.built then Call(page.def.refresh, page) end
end

-- Coalesces bursts of updates into one redraw a moment later.
function UI:Refresh(now)
	if now then return self:RefreshNow() end
	if self.pending or not self:IsOpen() then return end
	self.pending = true
	C_Timer.After(0.1, function() UI:RefreshNow() end)
end

function UI:Toast(title, body, opts)
	if not self.toast then return end
	self.toast:Pop(title, body, opts)
end

--------------------------------------------------------------------------------
-- Boot: after the saved variables are in, set up the minimap button (UI/Data.lua subscribes to the core).
--------------------------------------------------------------------------------
-- The core finds the UI here (the UI files load after Core.lua; Init repeats it for any other order).
local function Register()
	local core = rawget(_G, "PartyLens")
	if type(core) == "table" then core.UI = UI end
end
Register()

function UI:Init()
	if self.ready then return end
	self.ready = true
	Register()
	UI:OnSetting("animations", function(on) if not on then M.StopAll() end end)
	if self.minimap then self.minimap:Init() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() UI:Init() end)
