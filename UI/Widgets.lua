--=============================================================================
-- Widget kit. Own frames only: no Blizzard templates besides BackdropTemplate, no UIDropDownMenu.
--
-- Every factory returns a frame with its parts as fields and its behaviour as methods; colours come from
-- UI.T and every movement from UI.Motion, so the `animations` setting reaches all of them.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, M = UI.T, UI.Motion
local Kit = {}
UI.Kit = Kit

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function shade(c, k) return { clamp(c[1] * k, 0, 1), clamp(c[2] * k, 0, 1), clamp(c[3] * k, 0, 1) } end

--------------------------------------------------------------------------------
-- Tooltip: `title` and `body` may be strings or a function(owner) returning both.
--------------------------------------------------------------------------------
local function ShowTip(owner)
	local title, body = owner.tipTitle, owner.tipBody
	if type(title) == "function" then title, body = title(owner) end
	if not title then return end
	GameTooltip:SetOwner(owner, owner.tipAnchor or "ANCHOR_TOP")
	GameTooltip:AddLine(title, T.text[1], T.text[2], T.text[3])
	if body and body ~= "" then GameTooltip:AddLine(body, T.muted[1], T.muted[2], T.muted[3], true) end
	GameTooltip:Show()
end

local function HideTip(owner)
	if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

function Kit.Tip(frame, title, body, anchor)
	frame.tipTitle, frame.tipBody, frame.tipAnchor = title, body, anchor
	if not frame.tipHooked then
		frame.tipHooked = true
		frame:HookScript("OnEnter", ShowTip)
		frame:HookScript("OnLeave", HideTip)
	end
end

--------------------------------------------------------------------------------
-- Buttons: primary (amber, the page's main action), secondary, ghost, danger.
--------------------------------------------------------------------------------
local function PaintButton(b)
	local on, hover, down = b:IsEnabled(), b.hover and b:IsEnabled(), b.down
	local bg, bgA, edge, edgeA, label, labelA
	if b.kind == "primary" then
		bg = shade(T.amber, down and 0.86 or (hover and 1.1 or 1))
		bgA, edge, edgeA, label, labelA = on and 1 or 0.3, bg, on and 1 or 0.3, T.onAmber, on and 1 or 0.7
	elseif b.kind == "danger" then
		bg, bgA, edge, edgeA = T.dps, (hover and 0.14 or 0) + (down and 0.1 or 0), T.dps, on and 0.9 or 0.3
		label, labelA = on and T.dps or T.faint, 1
	elseif b.kind == "ghost" then
		bg, bgA, edge, edgeA = T.raised, (hover and 0.9 or 0) + (down and 0.1 or 0), T.line, 0
		label, labelA = on and (hover and T.text or T.muted) or T.faint, 1
	else
		bg, bgA = down and T.panel or T.raised, 1
		edge, edgeA = hover and T.lineHi or T.line, 1
		label, labelA = on and T.text or T.faint, 1
	end
	b:SetBackdropColor(bg[1], bg[2], bg[3], bgA)
	b:SetBackdropBorderColor(edge[1], edge[2], edge[3], edgeA)
	label = (on and b.tone) or label
	UI.TextColor(b.label, label, labelA)
	if b.icon then UI.Paint(b.icon, label, labelA) end
end

local ButtonMethods = {}

function ButtonMethods:SetLabel(text)
	self.text = text
	self.label:SetText(text)
	if not self.fixedWidth then
		local w = math.ceil(self.label:GetStringWidth()) + (self.icon and 46 or 28)
		self:SetWidth(math.max(self.minWidth or 0, w))
	end
end

function ButtonMethods:SetKind(kind)
	self.kind = kind
	PaintButton(self)
end

-- Turn into another label (and kind) for `seconds`, then back. `flash`: a colour that flashes once over it;
-- `tone`: a label colour while morphed.
function ButtonMethods:Morph(text, kind, seconds, flash, tone)
	self.morphs = (self.morphs or 0) + 1
	local token = self.morphs
	if not self.rest then self.rest = { text = self.text, kind = self.kind, width = self:GetWidth() } end
	self.tone = tone
	self:SetLabel(text)
	-- Wide enough for the morphed text, a fixed-width button included, until it settles back.
	self:SetWidth(math.max(self:GetWidth(), self.rest.width, math.ceil(self.label:GetStringWidth()) + 20))
	self.kind = kind or self.kind
	PaintButton(self)
	if flash then
		self.flash:SetColorTexture(flash[1], flash[2], flash[3], 1)
		M.Flash(self.flash, 0.6, 0.6)
	end
	if seconds then
		C_Timer.After(seconds, function()
			if self.morphs == token then self:Unmorph() end
		end)
	end
end

function ButtonMethods:Unmorph()
	local rest = self.rest
	if not rest then return end
	self.rest, self.confirming, self.tone = nil, nil, nil
	self:SetLabel(rest.text)
	self:SetWidth(self.fixedWidth or rest.width)
	self.kind = rest.kind
	PaintButton(self)
end

-- Two-step action: the first click turns the button into `ask` (danger) for 3 s; a second click runs `fn`.
function ButtonMethods:Confirm(ask, fn)
	if self.confirming then
		self:Unmorph()
		fn(self)
		return true
	end
	self:Morph(ask, "danger", 3)
	self.confirming = true
	return false
end

-- Feedback after an action went out: the label says so in green for a moment.
function ButtonMethods:Done(text, seconds)
	self:Morph(text, "secondary", seconds or 2.5, T.ok, T.ok)
end

-- The label (and kind) the button rests on: applied now, or after a morph that is showing ends.
function ButtonMethods:Settle(text, kind)
	if self.rest then
		self.rest.text, self.rest.kind = text, kind or self.rest.kind
		return
	end
	if self.text ~= text then self:SetLabel(text) end
	if kind and self.kind ~= kind then self:SetKind(kind) end
end

-- The action was refused: the label says why, in red, for a moment.
function ButtonMethods:Fail(text, seconds)
	self:Morph(text, "danger", seconds or 2.5)
end

local function OnButtonDown(b)
	if not b:IsEnabled() then return end
	b.down = true
	PaintButton(b)
	M.Press(b)
end

local function OnButtonUp(b)
	b.down = false
	PaintButton(b)
end

function Kit.Button(parent, label, kind, onClick, opts)
	opts = opts or {}
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	UI.Backdrop(b, T.raised, T.line)
	b:SetHeight(opts.h or 26)
	b.kind, b.onClick, b.fixedWidth, b.minWidth = kind or "secondary", onClick, opts.w, opts.minWidth
	if opts.w then b:SetWidth(opts.w) end
	b.label = UI.Text(b, "display", opts.size or 12, T.text, "CENTER")
	if opts.icon then
		b.icon = UI.Tex(b, opts.icon, 13)
		b.icon:SetPoint("LEFT", 12, 0)
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
	else
		b.label:SetPoint("CENTER", 0, 0)
	end
	b.flash = UI.Fill(b, T.ok, 1, "ARTWORK")
	b.flash:SetPoint("TOPLEFT", 1, -1)
	b.flash:SetPoint("BOTTOMRIGHT", -1, 1)
	b.flash:SetAlpha(0)
	for k, fn in pairs(ButtonMethods) do b[k] = fn end
	b:SetScript("OnEnter", function(self) self.hover = true; PaintButton(self) end)
	b:SetScript("OnLeave", function(self) self.hover, self.down = false, false; PaintButton(self) end)
	b:SetScript("OnMouseDown", OnButtonDown)
	b:SetScript("OnMouseUp", OnButtonUp)
	b:SetScript("OnEnable", PaintButton)
	b:SetScript("OnDisable", PaintButton)
	b:SetScript("OnClick", function(self, button)
		if self.onClick then self.onClick(self, button) end
	end)
	b:SetLabel(label or "")
	PaintButton(b)
	if opts.tip then Kit.Tip(b, opts.tip, opts.tipBody) end
	return b
end

-- Square button with a glyph from Media (more, close, search...).
function Kit.IconButton(parent, icon, size, onClick, tip, tipBody)
	size = size or 24
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.bg = UI.Fill(b, T.raised, 0)
	b.bg:SetAllPoints()
	b.icon = UI.Tex(b, icon, math.floor(size * 0.6), T.muted)
	b.icon:SetPoint("CENTER")
	b.onClick = onClick
	local function paint(self)
		local on = self:IsEnabled()
		self.bg:SetAlpha((self.hover and on) and 1 or 0)
		UI.Paint(self.icon, on and ((self.hover or self.active) and T.text or T.muted) or T.faint)
	end
	b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
	b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then M.Press(self) end end)
	b:SetScript("OnEnable", paint)
	b:SetScript("OnDisable", paint)
	b:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
	paint(b)
	if tip then Kit.Tip(b, tip, tipBody) end
	return b
end

--------------------------------------------------------------------------------
-- Chip: a toggle with an optional glyph, tinted by its own colour when on (role filters).
--------------------------------------------------------------------------------
function Kit.Chip(parent, opts)
	local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
	UI.Backdrop(c, T.panel, T.line)
	c:SetHeight(opts.h or 24)
	c.color, c.onToggle = opts.color or T.amber, opts.onToggle
	local x = 8
	if opts.icon then
		c.icon = UI.Tex(c, opts.icon, 14)
		c.icon:SetPoint("LEFT", 6, 0)
		x = 25
	end
	c.label = UI.Text(c, "data", 12)
	c.label:SetPoint("LEFT", x, 0)
	c.label:SetText(opts.label or "")
	local w = opts.label and (x + math.ceil(c.label:GetStringWidth()) + 9) or 26
	c:SetWidth(opts.w or w)
	local function paint(self)
		local col = self.selected and self.color or (self.hover and T.text or T.muted)
		self:SetBackdropColor(self.color[1], self.color[2], self.color[3], self.selected and 0.16 or 0)
		local edge = self.selected and self.color or (self.hover and T.lineHi or T.line)
		self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
		UI.TextColor(self.label, col)
		if self.icon then UI.Paint(self.icon, self.selected and self.color or T.muted) end
	end
	function c:SetSelected(on, silent)
		self.selected = on and true or false
		paint(self)
		if not silent and self.onToggle then self.onToggle(self.selected, self) end
	end
	c:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
	c:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
	c:SetScript("OnMouseDown", function(self) M.Press(self) end)
	c:SetScript("OnClick", function(self) self:SetSelected(not self.selected) end)
	c:SetSelected(opts.selected, true)
	if opts.tip then Kit.Tip(c, opts.tip, opts.tipBody) end
	return c
end

--------------------------------------------------------------------------------
-- Segmented control: equal segments, an indicator that slides to the chosen one.
-- options = { { value = v, label = "text" }, ... }
--------------------------------------------------------------------------------
function Kit.Segmented(parent, options, value, onChange, opts)
	opts = opts or {}
	local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(s, T.well, T.line)
	local h = opts.h or 24
	s:SetHeight(h)
	s.onChange, s.segments = onChange, {}
	local segW = opts.segW or 0
	if segW == 0 then
		local probe = UI.Text(s, "data", 12)
		for _, o in ipairs(options) do
			probe:SetText(o.label)
			segW = math.max(segW, math.ceil(probe:GetStringWidth()) + 22)
		end
		probe:Hide()
	end
	s:SetWidth(segW * #options + 2)
	s.ind = CreateFrame("Frame", nil, s)
	s.ind:SetSize(segW, h - 2)
	s.ind.bg = UI.Fill(s.ind, T.amber, 0.14, "BACKGROUND", 1)
	s.ind.bg:SetAllPoints()
	s.ind.mark = UI.Fill(s.ind, T.amber, 1, "ARTWORK")
	s.ind.mark:SetPoint("BOTTOMLEFT")
	s.ind.mark:SetPoint("BOTTOMRIGHT")
	s.ind.mark:SetHeight(2)
	for i, o in ipairs(options) do
		local b = CreateFrame("Button", nil, s)
		b:SetSize(segW, h - 2)
		b:SetPoint("TOPLEFT", 1 + (i - 1) * segW, -1)
		b.value, b.index = o.value, i
		b.label = UI.Text(b, "data", 12, T.muted, "CENTER")
		b.label:SetPoint("CENTER")
		b.label:SetText(o.label)
		b:SetScript("OnEnter", function(self) if s.value ~= self.value then UI.TextColor(self.label, T.text) end end)
		b:SetScript("OnLeave", function(self) if s.value ~= self.value then UI.TextColor(self.label, T.muted) end end)
		b:SetScript("OnClick", function(self) s:SetValue(self.value) end)
		if o.tip then Kit.Tip(b, o.label, o.tip) end
		s.segments[i] = b
	end
	local function place(ind, ox) ind:ClearAllPoints(); ind:SetPoint("TOPLEFT", s, "TOPLEFT", 1 + (s.at - 1) * segW + ox,
		-1) end
	function s:SetValue(v, silent)
		local from = self.at
		for _, b in ipairs(self.segments) do
			if b.value == v then self.at = b.index end
			UI.TextColor(b.label, b.value == v and T.text or T.muted)
		end
		self.value = v
		if not self.at then return end
		if from and from ~= self.at then
			M.Slide(self.ind, place, (from - self.at) * segW, 0, M.SLIDE)
		else
			place(self.ind, 0)
		end
		if not silent and self.onChange then self.onChange(v) end
	end
	s:SetValue(value, true)
	return s
end

--------------------------------------------------------------------------------
-- Checkbox with a label and an optional line under it; `width` wraps that line.
--------------------------------------------------------------------------------
function Kit.Check(parent, label, checked, onChange, sub, width)
	local c = CreateFrame("Button", nil, parent)
	c.box = CreateFrame("Frame", nil, c, "BackdropTemplate")
	c.box:SetSize(16, 16)
	c.box:SetPoint("TOPLEFT", 0, -1)
	UI.Backdrop(c.box, T.well, T.line)
	c.mark = UI.Tex(c.box, "check", 13, T.onAmber, 1, "OVERLAY")
	c.mark:SetPoint("CENTER")
	c.label = UI.Text(c, "data", 13)
	c.label:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 9, 0)
	c.label:SetText(label)
	local w = math.ceil(c.label:GetStringWidth())
	local h = 18
	if sub then
		c.sub = UI.Text(c, "data", 12, T.muted)
		c.sub:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -3)
		c.sub:SetText(sub)
		if width then
			c.sub:SetWidth(width - 26)
			c.sub:SetWordWrap(true)
			w = width - 26
		else
			w = math.max(w, math.ceil(c.sub:GetStringWidth()))
		end
		h = 22 + math.max(14, math.ceil(c.sub:GetStringHeight()))
	end
	c:SetSize(w + 26, h)
	c.onChange = onChange
	local function paint(self)
		local on = self.checked
		local edge = on and T.amber or (self.hover and T.lineHi or T.line)
		local bg = on and T.amber or T.well
		self.box:SetBackdropColor(bg[1], bg[2], bg[3], 1)
		self.box:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
		self.mark:SetShown(on)
	end
	function c:SetChecked(v)
		self.checked = v and true or false
		paint(self)
	end
	function c:GetChecked() return self.checked end
	c:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
	c:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
	c:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.checked then M.Pop(self.mark, 0.12, 0.5) end
		if self.onChange then self.onChange(self.checked, self) end
	end)
	c:SetChecked(checked)
	return c
end

--------------------------------------------------------------------------------
-- Edit box with a placeholder. onChange fires on typing only, never on SetValue; onCommit on Enter or when the
-- box loses focus with a changed text (for values that go to the network, not on every keystroke).
--------------------------------------------------------------------------------
function Kit.Edit(parent, opts)
	opts = opts or {}
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	UI.Backdrop(e, T.well, T.line)
	e:SetSize(opts.w or 160, opts.h or 24)
	e:SetFont(UI.FONT.data, 13, "")
	e:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
	e:SetAutoFocus(false)
	e:SetMaxLetters(opts.maxLetters or 120)
	local inset = 8
	if opts.icon then
		e.icon = UI.Tex(e, opts.icon, 12, T.muted)
		e.icon:SetPoint("LEFT", 8, 0)
		inset = 25
	end
	e:SetTextInsets(inset, 8, 0, 0)
	e.placeholder = UI.Text(e, "data", 13, T.faint)
	e.placeholder:SetPoint("LEFT", inset, 0)
	e.placeholder:SetText(opts.placeholder or "")
	e.onChange, e.onSubmit, e.onCommit = opts.onChange, opts.onSubmit, opts.onCommit
	local function edge(self, c) self:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
	local function commit(self)
		local text = self:GetText() or ""
		if self.onCommit and text ~= self.committed then
			self.committed = text
			self.onCommit(text, self)
		end
	end
	e:SetScript("OnEditFocusGained", function(self) edge(self, T.amber) end)
	e:SetScript("OnEditFocusLost", function(self)
		edge(self, T.line)
		commit(self)
	end)
	e:SetScript("OnTextChanged", function(self, userInput)
		local text = self:GetText() or ""
		self.placeholder:SetShown(text == "")
		if userInput and self.onChange then self.onChange(text, self) end
	end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		commit(self)
		self:ClearFocus()
		if self.onSubmit then self.onSubmit(self:GetText() or "", self) end
	end)
	-- Sets the text unless the player is typing in it.
	function e:SetValue(text)
		if self:HasFocus() then return end
		self.committed = text or ""
		self:SetText(text or "")
		self.placeholder:SetShown((text or "") == "")
	end
	e:SetValue(opts.text)
	return e
end

--------------------------------------------------------------------------------
-- Menu: one popup for the whole UI (dropdowns and the "more" buttons on cards).
-- items = { { text, value, checked, disabled, color, tip }, ... }
--------------------------------------------------------------------------------
local MENU_ROW, MENU_MAX = 22, 10
local menu

local function MenuRow(m, i)
	local r = m.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, m)
	r:SetHeight(MENU_ROW)
	r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
	r:SetPoint("RIGHT", -4, 0)
	r.hl = UI.Fill(r, T.raised, 1)
	r.hl:SetAllPoints()
	r.hl:Hide()
	r.dot = UI.Tex(r, "dot", 6, T.amber)
	r.dot:SetPoint("LEFT", 8, 0)
	r.label = UI.Text(r, "data", 13)
	r.label:SetPoint("LEFT", 22, 0)
	r.label:SetPoint("RIGHT", -8, 0)
	r:SetScript("OnEnter", function(self) if self:IsEnabled() then self.hl:Show() end end)
	r:SetScript("OnLeave", function(self) self.hl:Hide() end)
	r:SetScript("OnClick", function(self)
		local item, pick = self.item, m.onPick
		Kit.CloseMenu()
		if item and pick then pick(item.value, item) end
	end)
	m.rows[i] = r
	return r
end

local function RenderMenu(m)
	local n = math.min(#m.items, MENU_MAX)
	for i = 1, n do
		local item, r = m.items[i + m.offset], MenuRow(m, i)
		r.item = item
		r.label:SetText(item.text)
		UI.TextColor(r.label, item.disabled and T.faint or (item.color or T.text))
		r.dot:SetShown(item.checked and true or false)
		r:SetEnabled(not item.disabled)
		r.hl:Hide()
		r:Show()
	end
	for i = n + 1, #m.rows do m.rows[i]:Hide() end
	-- A long list scrolls with the wheel; a thin bar on the right says where in it the view is.
	local extra = #m.items - MENU_MAX
	m.thumb:SetShown(extra > 0)
	if extra > 0 then
		local track = MENU_MAX * MENU_ROW
		local h = math.max(12, track * MENU_MAX / #m.items)
		m.thumb:SetHeight(h)
		m.thumb:ClearAllPoints()
		m.thumb:SetPoint("TOPRIGHT", m, "TOPRIGHT", -2, -4 - (track - h) * m.offset / extra)
	end
end

local function Menu()
	if menu then return menu end
	menu = CreateFrame("Frame", "PartyLensMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetFrameLevel(20)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	UI.Backdrop(menu, T.panel, T.lineHi)
	menu.rows = {}
	menu.thumb = UI.Fill(menu, T.lineHi, 1, "OVERLAY")
	menu.thumb:SetWidth(2)
	menu.thumb:Hide()
	menu:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, #self.items - MENU_MAX)
		self.offset = clamp(self.offset - delta, 0, max)
		RenderMenu(self)
	end)
	-- A click anywhere else closes it.
	menu.catcher = CreateFrame("Button", nil, UIParent)
	menu.catcher:SetFrameStrata("DIALOG")
	menu.catcher:SetFrameLevel(1)
	menu.catcher:SetAllPoints(UIParent)
	menu.catcher:RegisterForClicks("AnyUp")
	menu.catcher:SetScript("OnClick", function() Kit.CloseMenu() end)
	menu.catcher:Hide()
	menu:Hide()
	return menu
end

function Kit.OpenMenu(anchor, items, onPick)
	local m = Menu()
	m.items, m.onPick, m.offset, m.owner = items, onPick, 0, anchor
	local probe, w = MenuRow(m, 1).label, anchor:GetWidth()
	for _, item in ipairs(items) do
		probe:SetText(item.text)
		w = math.max(w, math.ceil(probe:GetStringWidth()) + 40)
	end
	m:SetSize(w, math.min(#items, MENU_MAX) * MENU_ROW + 8)
	RenderMenu(m)
	m.catcher:Show()
	local function place(self, ox, oy)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox, -3 + oy)
	end
	M.Slide(m, place, 0, 6, 0.12, true)
	m:Show()
end

function Kit.CloseMenu()
	if not menu then return end
	menu:Hide()
	menu.catcher:Hide()
	menu.owner = nil
end

function Kit.MenuOwner()
	return menu and menu:IsShown() and menu.owner or nil
end

--------------------------------------------------------------------------------
-- Dropdown: options = { { value, label } } or a function returning them.
--------------------------------------------------------------------------------
function Kit.Dropdown(parent, opts)
	local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
	UI.Backdrop(d, T.well, T.line)
	d:SetSize(opts.w or 160, opts.h or 24)
	d.label = UI.Text(d, "data", 13)
	d.label:SetPoint("LEFT", 8, 0)
	d.label:SetPoint("RIGHT", -24, 0)
	d.chevron = UI.Tex(d, "chevron", 12, T.muted)
	d.chevron:SetPoint("RIGHT", -8, 0)
	d.options, d.onChange, d.placeholder = opts.options or {}, opts.onChange, opts.placeholder
	function d:GetOptions()
		return type(self.options) == "function" and self.options() or self.options
	end
	function d:SetOptions(list)
		self.options = list
		self:SetValue(self.value, true)
	end
	function d:SetValue(v, silent)
		self.value = v
		local text
		for _, o in ipairs(self:GetOptions()) do
			if o.value == v then text = o.label end
		end
		self.label:SetText(text or self.placeholder or "")
		UI.TextColor(self.label, text and T.text or T.faint)
		if not silent and self.onChange then self.onChange(v) end
	end
	function d:GetValue() return self.value end
	local function edge(self, c) self:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
	d:SetScript("OnEnter", function(self) edge(self, T.lineHi) end)
	d:SetScript("OnLeave", function(self) edge(self, T.line) end)
	d:SetScript("OnClick", function(self)
		if Kit.MenuOwner() == self then Kit.CloseMenu() return end
		local items = {}
		for _, o in ipairs(self:GetOptions()) do
			items[#items + 1] = { text = o.label, value = o.value, checked = o.value == self.value }
		end
		Kit.OpenMenu(self, items, function(v) self:SetValue(v) end)
	end)
	d:SetValue(opts.value, true)
	return d
end

--------------------------------------------------------------------------------
-- Scroll list with recycled rows: only the rows in view exist, re-bound as it scrolls.
-- opts = { rowHeight, gap, create(row, list), bind(row, item, index, list), width, viewHeight, emptyTop }
--------------------------------------------------------------------------------
function Kit.List(parent, opts)
	local l = CreateFrame("Frame", nil, parent)
	l.rowHeight, l.gap, l.create, l.bind = opts.rowHeight or 40, opts.gap or 0, opts.create, opts.bind
	l.step = l.rowHeight + l.gap
	l.items, l.rows = {}, {}
	l.scroll = CreateFrame("ScrollFrame", nil, l)
	l.scroll:SetPoint("TOPLEFT")
	l.scroll:SetPoint("BOTTOMRIGHT", -12, 0)
	l.child = CreateFrame("Frame", nil, l.scroll)
	l.child:SetSize(opts.width or 400, 1)
	l.scroll:SetScrollChild(l.child)

	l.bar = CreateFrame("Slider", nil, l)
	l.bar:SetOrientation("VERTICAL")
	l.bar:SetPoint("TOPRIGHT", 0, 0)
	l.bar:SetPoint("BOTTOMRIGHT", 0, 0)
	l.bar:SetWidth(5)
	l.bar:EnableMouse(true)
	l.bar:SetObeyStepOnDrag(true)
	l.bar.track = UI.Fill(l.bar, T.panel)
	l.bar.track:SetAllPoints()
	l.bar.thumb = l.bar:CreateTexture(nil, "ARTWORK")
	l.bar.thumb:SetColorTexture(T.lineHi[1], T.lineHi[2], T.lineHi[3], 1)
	l.bar.thumb:SetSize(5, 36)
	l.bar:SetThumbTexture(l.bar.thumb)
	l.bar:SetMinMaxValues(0, 0)
	l.bar:SetValueStep(1)
	l.bar:SetValue(0)
	l.bar:SetScript("OnValueChanged", function(_, v) l.scroll:SetVerticalScroll(v) end)

	l.scroll:EnableMouseWheel(true)
	l.scroll:SetScript("OnMouseWheel", function(_, delta)
		local lo, hi = l.bar:GetMinMaxValues()
		l.bar:SetValue(clamp(l.bar:GetValue() - delta * l.step * 2, lo, hi))
	end)
	l.scroll:SetScript("OnVerticalScroll", function() l:Layout() end)
	l.scroll:SetScript("OnSizeChanged", function(_, w)
		if w and w > 0 then l.child:SetWidth(w) end
		l:Update()
	end)

	l.empty = Kit.Empty(l)
	l.empty:SetPoint("TOP", 0, -(opts.emptyTop or 48))
	l.empty:Hide()

	function l:ViewHeight()
		local h = self.scroll:GetHeight()
		return (h and h > 1) and h or (opts.viewHeight or 320)
	end

	function l:Update()
		local total = #self.items * self.step
		self.child:SetHeight(math.max(1, total))
		local range = math.max(0, total - self:ViewHeight())
		self.bar:SetMinMaxValues(0, range)
		self.bar:SetShown(range > 0)
		if self.bar:GetValue() > range then self.bar:SetValue(range) end
		self:Layout()
	end

	function l:Layout()
		local offset = self.scroll:GetVerticalScroll() or 0
		local first = math.floor(offset / self.step) + 1
		local count = math.ceil(self:ViewHeight() / self.step) + 1
		for i = 1, count do
			local index = first + i - 1
			local item = self.items[index]
			local row = self.rows[i]
			if item and not row then
				row = CreateFrame("Frame", nil, self.child)
				row:SetHeight(self.rowHeight)
				if self.create then self.create(row, self) end
				self.rows[i] = row
			end
			if row then
				if item then
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -(index - 1) * self.step)
					row:SetPoint("RIGHT", self.child, "RIGHT", 0, 0)
					row.item, row.index = item, index
					if self.bind then self.bind(row, item, index, self) end
					row:Show()
				else
					row.item = nil
					row:Hide()
				end
			end
		end
		for i = count + 1, #self.rows do
			self.rows[i].item = nil
			self.rows[i]:Hide()
		end
	end

	function l:SetItems(items)
		self.items = items or {}
		self.empty:SetShown(#self.items == 0 and (self.empty.title:GetText() or "") ~= "")
		self:Update()
	end

	function l:SetEmpty(title, body, action, onAction)
		self.empty:Set(title, body, action, onAction)
		self.empty:SetShown(#self.items == 0)
	end

	function l:RowFor(match)
		for _, row in ipairs(self.rows) do
			if row.item and row:IsShown() and match(row.item) then return row end
		end
	end

	function l:ScrollToTop()
		self.bar:SetValue(0)
		self.scroll:SetVerticalScroll(0)
	end

	return l
end

--------------------------------------------------------------------------------
-- Card: a row surface with a colour edge on the left. The body is a child so it can slide in while the
-- list keeps the row anchored. MarkNew: slides 12 px in with a fade and an amber edge glow that fades in 2 s.
--------------------------------------------------------------------------------
function Kit.Card(row)
	row.body = CreateFrame("Frame", nil, row)
	local function place(body, ox, oy)
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", row, "TOPLEFT", ox, oy)
		body:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", ox, oy)
	end
	place(row.body, 0, 0)
	local body = row.body
	body.bg = UI.Fill(body, T.panel)
	body.bg:SetAllPoints()
	body.edge = UI.Fill(body, T.amber, 1, "ARTWORK")
	body.edge:SetPoint("TOPLEFT")
	body.edge:SetPoint("BOTTOMLEFT")
	body.edge:SetWidth(3)
	body.wash = UI.Tex(body, "gradient", nil, T.amber, 1, "BORDER")
	body.wash:SetPoint("TOPLEFT", 3, 0)
	body.wash:SetPoint("BOTTOMLEFT", 3, 0)
	body.wash:SetWidth(180)
	body.wash:SetAlpha(0)
	function row:SetEdge(c) UI.Paint(self.body.edge, c) end
	function row:MarkNew()
		M.Slide(self.body, place, 12, 0, M.ENTER, true)
		M.Flash(self.body.wash, 0.45, M.EDGE)
	end
	function row:ResetMotion()
		M.Stop(self.body, "slide")
		M.Stop(self.body.wash, "flash")
		place(self.body, 0, 0)
		self.body:SetAlpha(1)
		self.body.wash:SetAlpha(0)
	end
	return row
end

--------------------------------------------------------------------------------
-- Role pips: one glyph per role still missing (shape and colour, so it reads without colour too), a count
-- when more than one is missing, and a single pulse when a group needs your role.
--------------------------------------------------------------------------------
Kit.ROLES = { "tank", "heal", "dps" }

function Kit.RolePips(parent, size)
	size = size or 14
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(size, size)
	p.pips = {}
	local names = { tank = UI.L["ROLE_TANK"], heal = UI.L["ROLE_HEAL"], dps = UI.L["ROLE_DPS"] }
	for _, role in ipairs(Kit.ROLES) do
		local f = CreateFrame("Frame", nil, p)
		f:SetSize(size, size)
		f.glow = UI.Tex(f, "blip", math.floor(size * 2.4), T.role[role], 1, "BACKGROUND")
		f.glow:SetPoint("CENTER")
		f.glow:SetAlpha(0)
		f.icon = UI.Tex(f, "role-" .. role, size, T.role[role])
		f.icon:SetPoint("CENTER")
		f.count = UI.Text(f, "display", 10, T.role[role])
		f.count:SetPoint("LEFT", f, "RIGHT", 1, -3)
		f:EnableMouse(true)
		Kit.Tip(f, function(self) return names[role] .. ((self.n or 0) > 1 and (" x" .. self.n) or "") end)
		p.pips[role] = f
	end
	-- need = { tank = n, heal = n, dps = n }: how many of each are still missing. Returns the width used.
	function p:Set(need)
		local x = 0
		for _, role in ipairs(Kit.ROLES) do
			local f, n = self.pips[role], need and need[role] or 0
			f.n = n
			if n > 0 then
				f:ClearAllPoints()
				f:SetPoint("LEFT", self, "LEFT", x, 0)
				f.count:SetText(n > 1 and tostring(n) or "")
				f:Show()
				x = x + size + (n > 1 and 13 or 6)
			else
				f:Hide()
			end
		end
		self:SetWidth(math.max(1, x))
		return x
	end
	function p:Pulse(role)
		local f = self.pips[role]
		if not (f and f:IsShown()) then return end
		M.Pulse(f, 1.45, 0.45)
		M.Flash(f.glow, 0.8, 0.9)
	end
	return p
end

--------------------------------------------------------------------------------
-- Rings: a track and an arc (radial progress of the ring texture), 0 to 1 from twelve o'clock clockwise.
--------------------------------------------------------------------------------
function Kit.Ring(parent, size, color)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(size, size)
	r.track = UI.Tex(r, "ring-thick", size, T.line, 1, "BACKGROUND")
	r.track:SetPoint("CENTER")
	r.fill = UI.Tex(r, "ring-thick", size, color or T.amber, 1, "ARTWORK")
	r.fill:SetPoint("CENTER")
	-- Fallback for a client without radial progress: the whole ring, dimmer as it empties.
	r.radial = r.fill.SetRadialProgressBarPercent ~= nil
	if r.radial then r.fill:SetRadialProgressBarStartOffset(0.5) end
	function r:SetFraction(f)
		f = clamp(f or 0, 0, 1)
		self.fraction = f
		if self.radial then self.fill:SetRadialProgressBarPercent(f) else self.fill:SetAlpha(0.2 + 0.8 * f) end
	end
	function r:SetColor(c) UI.Paint(self.fill, c) end
	r:SetFraction(1)
	return r
end

-- Freshness: full when just posted, empty at maxAge. Amber while new, then text, muted past half.
Kit.NEW_FOR = 120
function Kit.FreshRing(parent, size)
	local r = Kit.Ring(parent, size or 14)
	function r:SetAge(age, maxAge)
		local f = 1 - age / math.max(1, maxAge)
		self:SetFraction(f)
		self:SetColor(age < Kit.NEW_FOR and T.amber or (f > 0.5 and T.text or T.muted))
	end
	return r
end

-- Progress while waiting for something with a deadline (a layer invite). Fills smoothly when motion is on,
-- once a second when it is off.
function Kit.ProgressRing(parent, size)
	local r = Kit.Ring(parent, size or 40, T.amber)
	r:SetFraction(0)
	local function tick(self, elapsed)
		self.acc = self.acc + elapsed
		if self.acc < (M.On() and 0.03 or 1) then return end
		self.acc = 0
		local f = (GetTime() - self.startedAt) / self.duration
		self:SetFraction(f)
		if f >= 1 then
			self:Stop()
			if self.onDone then self.onDone() end
		end
	end
	function r:Start(duration, startedAt, onDone)
		self.duration, self.startedAt, self.onDone, self.acc = math.max(0.1, duration), startedAt or GetTime(), onDone, 0
		self:SetFraction((GetTime() - self.startedAt) / self.duration)
		self:SetScript("OnUpdate", tick)
	end
	function r:Stop()
		self:SetScript("OnUpdate", nil)
	end
	return r
end

--------------------------------------------------------------------------------
-- Toast: drops from the top of `host`, stays `hold` seconds and leaves by itself. Click: opts.onClick.
--------------------------------------------------------------------------------
function Kit.Toast(host)
	local t = CreateFrame("Button", nil, host, "BackdropTemplate")
	UI.Backdrop(t, T.raised, T.lineHi)
	t:SetSize(400, 50)
	t:SetFrameLevel(host:GetFrameLevel() + 40)
	t.edge = UI.Fill(t, T.amber, 1, "ARTWORK")
	t.edge:SetPoint("TOPLEFT", 1, -1)
	t.edge:SetPoint("BOTTOMLEFT", 1, 1)
	t.edge:SetWidth(3)
	t.title = UI.Text(t, "display", 13)
	t.title:SetPoint("TOPLEFT", 16, -9)
	t.title:SetPoint("RIGHT", -12, 0)
	t.body = UI.Text(t, "data", 12, T.muted)
	t.body:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
	t.body:SetPoint("RIGHT", -12, 0)
	-- Up to two actions on the right (a layer request: Invite, Decline). Each runs inside its own OnClick.
	t.actions = {}
	for i = 1, 2 do
		local b = Kit.Button(t, "", i == 1 and "primary" or "ghost", function(btn)
			local fn = btn.fn
			t.serial = t.serial + 1
			t:Leave()
			if fn then fn(btn) end
		end, { h = 24 })
		b:Hide()
		t.actions[i] = b
	end
	t:Hide()
	local function place(self, ox, oy)
		self:ClearAllPoints()
		self:SetPoint("TOP", host, "TOP", ox, -12 + oy)
	end
	place(t, 0, 0)
	t.serial = 0
	function t:Pop(title, body, opts)
		opts = opts or {}
		self.serial = self.serial + 1
		local token = self.serial
		self.onClickFn = opts.onClick
		self.title:SetText(title)
		self.body:SetText(body or "")
		local right = self
		for i, b in ipairs(self.actions) do
			local a = opts.actions and opts.actions[i]
			if a then
				b:Unmorph()
				b:SetLabel(a.label)
				b:SetKind(a.kind or (i == 1 and "primary" or "ghost"))
				b.fn = a.fn
				b:ClearAllPoints()
				if right == self then b:SetPoint("RIGHT", -10, 0) else b:SetPoint("RIGHT", right, "LEFT", -6, 0) end
				right = b
				b:Show()
			else
				b.fn = nil
				b:Hide()
			end
		end
		local edge = right == self and "RIGHT" or "LEFT"
		self.title:SetPoint("RIGHT", right, edge, -12, 0)
		self.body:SetPoint("RIGHT", right, edge, -12, 0)
		self:SetWidth(right == self and 400 or 480)
		UI.Paint(self.edge, opts.color or T.amber)
		M.Stop(self, "fade")
		self:SetAlpha(1)
		self:Show()
		M.Slide(self, place, 0, 18, M.TOAST, true)
		C_Timer.After(opts.hold or 4, function()
			if self.serial == token then self:Leave() end
		end)
	end
	function t:Leave()
		if self:IsShown() then M.Fade(self, 0, 0.3, true) end
	end
	t:SetScript("OnClick", function(self)
		local fn = self.onClickFn
		self.serial = self.serial + 1
		self:Leave()
		if fn then fn() end
	end)
	return t
end

--------------------------------------------------------------------------------
-- Text blocks
--------------------------------------------------------------------------------
-- A number with what it counts under it.
function Kit.Stat(parent, color)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(150, 48)
	s.value = UI.Text(s, "display", 26, color or T.text)
	s.value:SetPoint("TOPLEFT")
	s.label = UI.Text(s, "data", 12, T.muted)
	s.label:SetPoint("TOPLEFT", s.value, "BOTTOMLEFT", 0, -3)
	function s:Set(value, label, c)
		self.value:SetText(value)
		self.label:SetText(label)
		if c then UI.TextColor(self.value, c) end
	end
	return s
end

-- Title and one line saying what the page is for.
function Kit.PageHead(page, title, sub)
	page.title = UI.Text(page, "display", 18)
	page.title:SetPoint("TOPLEFT", 0, 0)
	page.title:SetText(title)
	page.sub = UI.Text(page, "data", 12, T.muted)
	page.sub:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -5)
	page.sub:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	page.sub:SetText(sub or "")
	return page.title, page.sub
end

-- A quiet section label with a rule to the right edge of `parent`.
function Kit.Section(parent, text)
	local s = CreateFrame("Frame", nil, parent)
	s:SetHeight(18)
	s.label = UI.Text(s, "display", 12, T.muted)
	s.label:SetPoint("LEFT")
	s.label:SetText(text)
	s.rule = UI.Rule(s, T.line)
	s.rule:SetPoint("LEFT", s.label, "RIGHT", 10, 0)
	s.rule:SetPoint("RIGHT")
	return s
end

-- Empty state: what is going on and what to do.
function Kit.Empty(parent)
	local e = CreateFrame("Frame", nil, parent)
	e:SetSize(380, 90)
	e.title = UI.Text(e, "display", 14, T.text, "CENTER")
	e.title:SetPoint("TOP")
	e.title:SetWidth(380)
	e.body = UI.Text(e, "data", 12, T.muted, "CENTER")
	e.body:SetPoint("TOP", e.title, "BOTTOM", 0, -6)
	e.body:SetWidth(380)
	e.body:SetWordWrap(true)
	e.action = Kit.Button(e, "", "secondary")
	e.action:SetPoint("TOP", e.body, "BOTTOM", 0, -12)
	e.action:Hide()
	function e:Set(title, body, action, onAction)
		self.title:SetText(title or "")
		self.body:SetText(body or "")
		if action then
			self.action:SetLabel(action)
			self.action.onClick = onAction
			self.action:Show()
		else
			self.action:Hide()
		end
	end
	return e
end
