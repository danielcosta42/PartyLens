local ADDON_NAME = ...

local UIElements = {}

-- "Vidro escuro" (dark glass) palette: translucent layered panels, soft sheen,
-- hairline edges for depth. Role colors drive the informative pips/bars.
UIElements.PALETTE = {
    shell = { 0.035, 0.040, 0.050, 0.90 },
    panel = { 0.070, 0.082, 0.100, 0.55 },
    panel2 = { 0.100, 0.118, 0.150, 0.62 },
    panelHover = { 0.140, 0.165, 0.205, 0.72 },
    field = { 0.040, 0.048, 0.062, 0.82 },
    stroke = { 0.320, 0.380, 0.450, 0.34 },
    strokeHot = { 0.150, 0.860, 0.720, 0.95 },
    sheen = { 1.000, 1.000, 1.000, 0.045 },
    gloss = { 1.000, 1.000, 1.000, 0.075 },
    shadow = { 0.000, 0.000, 0.000, 0.45 },
    text = { 0.910, 0.940, 0.960, 1.00 },
    muted = { 0.560, 0.620, 0.680, 1.00 },
    faint = { 0.420, 0.470, 0.530, 1.00 },
    teal = { 0.150, 0.860, 0.720, 1.00 },
    gold = { 0.980, 0.741, 0.302, 1.00 },
    coral = { 1.000, 0.420, 0.380, 1.00 },
    blue = { 0.360, 0.660, 1.000, 1.00 },
    purple = { 0.702, 0.561, 1.000, 1.00 },
    -- Role accents
    roleTank = { 0.360, 0.620, 1.000, 1.00 },
    roleHeal = { 0.460, 0.870, 0.520, 1.00 },
    roleDps = { 1.000, 0.470, 0.430, 1.00 },
    -- Freshness dot
    freshNew = { 0.420, 0.950, 0.560, 1.00 },
    freshMid = { 0.980, 0.760, 0.320, 1.00 },
    freshOld = { 0.520, 0.560, 0.620, 1.00 },
}

local PALETTE = UIElements.PALETTE

local function TextureColor(texture, color)
    if texture.SetColorTexture then
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    else
        texture:SetTexture(color[1], color[2], color[3], color[4])
    end
end

function UIElements.SetTextureColor(texture, color)
    TextureColor(texture, color)
end

function UIElements.AddTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(parent)
    TextureColor(texture, color)
    return texture
end

local function Lighten(c, amt)
    return { math.min(1, c[1] + amt), math.min(1, c[2] + amt), math.min(1, c[3] + amt), c[4] }
end

-- Subtle vertical gradient (top lighter -> bottom base) for depth. Feature-
-- detects the modern and legacy gradient APIs and falls back to a flat fill, so
-- a panel can never render broken on any client.
function UIElements.SetGradient(tex, topColor, bottomColor)
    if tex.SetColorTexture then
        tex:SetColorTexture(1, 1, 1, 1)
    end
    local ok = false
    if tex.SetGradient and CreateColor then
        ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] or 1),
            CreateColor(topColor[1], topColor[2], topColor[3], topColor[4] or 1))
    end
    if not ok and tex.SetGradientAlpha then
        ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL",
            bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] or 1,
            topColor[1], topColor[2], topColor[3], topColor[4] or 1)
    end
    if not ok then
        TextureColor(tex, topColor)
    end
end

-- A translucent "glass" panel: base fill + faint top sheen + bright top gloss
-- line + hairline borders. Border textures are exposed (top/bottom/left/right)
-- so callers can recolor them for focus/accent states. Pass gradient=true on big
-- static surfaces (frame/sidebar/host/cards) for depth.
function UIElements.CreatePanel(parent, name, color, borderColor, gradient)
    local frame = CreateFrame("Frame", name, parent)
    color = color or PALETTE.panel
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    if gradient then
        UIElements.SetGradient(frame.bg, Lighten(color, 0.035), color)
    else
        TextureColor(frame.bg, color)
    end

    frame.sheen = frame:CreateTexture(nil, "BORDER")
    frame.sheen:SetPoint("TOPLEFT", 1, -1)
    frame.sheen:SetPoint("TOPRIGHT", -1, -1)
    frame.sheen:SetHeight(16)
    TextureColor(frame.sheen, PALETTE.sheen)

    frame.gloss = frame:CreateTexture(nil, "BORDER")
    frame.gloss:SetPoint("TOPLEFT", 1, -1)
    frame.gloss:SetPoint("TOPRIGHT", -1, -1)
    frame.gloss:SetHeight(1)
    TextureColor(frame.gloss, PALETTE.gloss)

    local edge = borderColor or PALETTE.stroke
    frame.top = frame:CreateTexture(nil, "BORDER")
    frame.top:SetPoint("TOPLEFT")
    frame.top:SetPoint("TOPRIGHT")
    frame.top:SetHeight(1)
    TextureColor(frame.top, edge)
    frame.bottom = frame:CreateTexture(nil, "BORDER")
    frame.bottom:SetPoint("BOTTOMLEFT")
    frame.bottom:SetPoint("BOTTOMRIGHT")
    frame.bottom:SetHeight(1)
    TextureColor(frame.bottom, edge)
    frame.left = frame:CreateTexture(nil, "BORDER")
    frame.left:SetPoint("TOPLEFT")
    frame.left:SetPoint("BOTTOMLEFT")
    frame.left:SetWidth(1)
    TextureColor(frame.left, edge)
    frame.right = frame:CreateTexture(nil, "BORDER")
    frame.right:SetPoint("TOPRIGHT")
    frame.right:SetPoint("BOTTOMRIGHT")
    frame.right:SetWidth(1)
    TextureColor(frame.right, edge)
    return frame
end

function UIElements.SetPanelBorder(frame, color)
    TextureColor(frame.top, color)
    TextureColor(frame.bottom, color)
    TextureColor(frame.left, color)
    TextureColor(frame.right, color)
end

function UIElements.CreateLabel(parent, text, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    color = color or PALETTE.text
    label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    return label
end

-- Glass button: translucent base with a COMPLETE hairline border (all four
-- sides, like a panel — no one-sided edges). The teal/accent only appears on
-- hover and on the persistent selected state ("calm by default, accent on
-- purpose"): a left accent bar + warmed border, shown only then.
function UIElements.CreateButton(parent, text, width, height, accent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 96, height or 28)
    button.accent = accent or PALETTE.teal
    button.normalColor = { 0.090, 0.105, 0.130, 0.62 }
    button.hoverColor = { button.accent[1] * 0.22, button.accent[2] * 0.22, button.accent[3] * 0.22, 0.85 }
    button.downColor = { button.accent[1] * 0.38, button.accent[2] * 0.38, button.accent[3] * 0.38, 0.95 }
    button.bg = UIElements.AddTexture(button, "BACKGROUND", button.normalColor)

    button.sheen = button:CreateTexture(nil, "BORDER")
    button.sheen:SetPoint("TOPLEFT", 1, -1)
    button.sheen:SetPoint("TOPRIGHT", -1, -1)
    button.sheen:SetHeight(math.max(6, (height or 28) * 0.45))
    TextureColor(button.sheen, PALETTE.sheen)

    button.gloss = button:CreateTexture(nil, "BORDER")
    button.gloss:SetPoint("TOPLEFT", 1, -1)
    button.gloss:SetPoint("TOPRIGHT", -1, -1)
    button.gloss:SetHeight(1)
    TextureColor(button.gloss, PALETTE.gloss)

    -- Full hairline border (recolored via SetPanelBorder for hover/selected).
    button.top = button:CreateTexture(nil, "BORDER"); button.top:SetPoint("TOPLEFT"); button.top:SetPoint("TOPRIGHT"); button.top:SetHeight(1); TextureColor(button.top, PALETTE.stroke)
    button.bottom = button:CreateTexture(nil, "BORDER"); button.bottom:SetPoint("BOTTOMLEFT"); button.bottom:SetPoint("BOTTOMRIGHT"); button.bottom:SetHeight(1); TextureColor(button.bottom, PALETTE.stroke)
    button.left = button:CreateTexture(nil, "BORDER"); button.left:SetPoint("TOPLEFT"); button.left:SetPoint("BOTTOMLEFT"); button.left:SetWidth(1); TextureColor(button.left, PALETTE.stroke)
    button.right = button:CreateTexture(nil, "BORDER"); button.right:SetPoint("TOPRIGHT"); button.right:SetPoint("BOTTOMRIGHT"); button.right:SetWidth(1); TextureColor(button.right, PALETTE.stroke)

    button.label = UIElements.CreateLabel(button, text, 11, PALETTE.text)
    button.label:SetPoint("CENTER")
    button.label:SetJustifyH("CENTER")

    button.isActive = false
    -- Hover/selection accent is ALWAYS teal (the brand) and SYMMETRIC (the whole
    -- hairline border warms) — never a one-sided bar nor a category-colored frame.
    button:SetScript("OnEnter", function(self)
        if not self.isActive then
            TextureColor(self.bg, self.hoverColor)
        end
        UIElements.SetPanelBorder(self, PALETTE.strokeHot)
    end)
    button:SetScript("OnLeave", function(self)
        if self.isActive then
            TextureColor(self.bg, PALETTE.panelHover)
            UIElements.SetPanelBorder(self, PALETTE.strokeHot)
        else
            TextureColor(self.bg, self.normalColor)
            UIElements.SetPanelBorder(self, PALETTE.stroke)
        end
    end)
    button:SetScript("OnMouseDown", function(self)
        TextureColor(self.bg, self.downColor)
    end)
    button:SetScript("OnMouseUp", function(self)
        TextureColor(self.bg, self.isActive and PALETTE.panelHover or self.hoverColor)
    end)
    button.SetText = function(self, value)
        self.label:SetText(value)
    end
    -- Persistent selected state: panelHover fill + soft teal border, full opacity
    -- (others in the group dim to 0.6). No colored frames, no one-sided bars.
    button.SetActive = function(self, value)
        self.isActive = value and true or false
        if self.isActive then
            TextureColor(self.bg, PALETTE.panelHover)
            UIElements.SetPanelBorder(self, PALETTE.strokeHot)
            self:SetAlpha(1)
        else
            TextureColor(self.bg, self.normalColor)
            UIElements.SetPanelBorder(self, PALETTE.stroke)
            self:SetAlpha(0.6)
        end
    end
    button.SetAccent = function(self, color)
        self.accent = color
        self.hoverColor = { color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 0.85 }
        self.downColor = { color[1] * 0.38, color[2] * 0.38, color[3] * 0.38, 0.95 }
    end
    return button
end

-- Small glass chip used for tags/badges (content type, intent, etc).
function UIElements.CreateChip(parent, width, height, accent)
    local chip = UIElements.CreatePanel(parent, nil, PALETTE.field, accent or PALETTE.stroke)
    chip:SetSize(width or 64, height or 20)
    chip.text = UIElements.CreateLabel(chip, "", math.max(9, math.floor((height or 20) * 0.5)), PALETTE.text)
    chip.text:SetPoint("CENTER")
    chip.text:SetJustifyH("CENTER")

    -- Outlined style: faint tinted fill, colored border + text.
    function chip:SetAccent(color)
        TextureColor(self.bg, { color[1] * 0.14, color[2] * 0.14, color[3] * 0.14, 0.92 })
        UIElements.SetPanelBorder(self, { color[1], color[2], color[3], 0.75 })
        if self.dot then TextureColor(self.dot, color) end
        self.text:SetTextColor(color[1], color[2], color[3], 1)
    end

    -- Filled style: solid accent fill, dark text. Used for the key badge.
    function chip:SetFilled(color)
        TextureColor(self.bg, { color[1] * 0.92, color[2] * 0.92, color[3] * 0.92, 0.95 })
        UIElements.SetPanelBorder(self, { color[1], color[2], color[3], 1 })
        if self.dot then TextureColor(self.dot, { 0.06, 0.07, 0.09, 1 }) end
        self.text:SetTextColor(0.05, 0.06, 0.08, 1)
    end

    function chip:SetLabel(value)
        self.text:SetText(value)
    end

    -- Optional leading status dot (call once after creation).
    function chip:EnableDot()
        if self.dot then return end
        self.dot = self:CreateTexture(nil, "OVERLAY")
        self.dot:SetSize(5, 5)
        self.dot:SetPoint("LEFT", 7, 0)
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", 16, 0)
        self.text:SetPoint("RIGHT", -6, 0)
        self.text:SetJustifyH("LEFT")
    end

    return chip
end

-- Role pip: a tinted glass square with a single role letter (T/H/D/?).
function UIElements.CreateRolePip(parent, size)
    size = size or 18
    local pip = UIElements.CreatePanel(parent, nil, { 0.06, 0.07, 0.09, 0.9 }, PALETTE.stroke)
    pip:SetSize(size, size)
    pip.letter = UIElements.CreateLabel(pip, "", math.max(9, math.floor(size * 0.62)), PALETTE.text)
    pip.letter:SetPoint("CENTER")
    pip.letter:SetJustifyH("CENTER")

    local ROLE_MAP = {
        tank = { PALETTE.roleTank, "T" },
        heal = { PALETTE.roleHeal, "H" },
        dps = { PALETTE.roleDps, "D" },
        any = { PALETTE.teal, "*" },
    }

    function pip:SetRole(role)
        local m = ROLE_MAP[role] or ROLE_MAP.any
        local c = m[1]
        TextureColor(self.bg, { c[1] * 0.20, c[2] * 0.20, c[3] * 0.20, 0.95 })
        UIElements.SetPanelBorder(self, { c[1], c[2], c[3], 0.8 })
        self.letter:SetText(m[2])
        self.letter:SetTextColor(c[1], c[2], c[3], 1)
    end

    return pip
end

-- Horizontal fill bar with centered "cur/max" text, tinted by an accent.
function UIElements.CreateFillBar(parent, width, height)
    local bar = UIElements.CreatePanel(parent, nil, PALETTE.field, PALETTE.stroke)
    bar:SetSize(width or 100, height or 16)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetWidth(1)
    TextureColor(bar.fill, { PALETTE.teal[1] * 0.5, PALETTE.teal[2] * 0.5, PALETTE.teal[3] * 0.5, 0.8 })
    bar.text = UIElements.CreateLabel(bar, "", 10, PALETTE.text)
    bar.text:SetPoint("CENTER")
    bar.text:SetJustifyH("CENTER")

    function bar:SetValue(cur, max, color)
        local inner = self:GetWidth() - 2
        local pct = 0
        if max and max > 0 and cur then
            pct = math.max(0, math.min(1, cur / max))
        end
        self.fill:SetWidth(math.max(1, inner * pct))
        color = color or PALETTE.teal
        TextureColor(self.fill, { color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 0.85 })
        if cur and max then
            self.text:SetText(cur .. "/" .. max)
        elseif cur then
            self.text:SetText(tostring(cur))
        else
            self.text:SetText("?")
        end
    end

    return bar
end

function UIElements.CreateEditBox(parent, name, width, height)
    local holder = UIElements.CreatePanel(parent, name .. "Shell", PALETTE.field, PALETTE.stroke)
    holder:SetSize(width, height or 30)

    local editBox = CreateFrame("EditBox", name, holder)
    editBox.shell = holder
    holder.editBox = editBox
    editBox:SetPoint("LEFT", 10, 0)
    editBox:SetPoint("RIGHT", -10, 0)
    editBox:SetHeight((height or 30) - 4)
    editBox:SetAutoFocus(false)
    editBox:SetFont(STANDARD_TEXT_FONT, 12, "")
    editBox:SetTextColor(PALETTE.text[1], PALETTE.text[2], PALETTE.text[3], PALETTE.text[4])
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        UIElements.SetPanelBorder(self.shell, PALETTE.strokeHot)
        if self.UpdatePlaceholder then self:UpdatePlaceholder() end
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        UIElements.SetPanelBorder(self.shell, PALETTE.stroke)
        if self.UpdatePlaceholder then self:UpdatePlaceholder() end
    end)

    -- Optional hint text shown when the box is empty and unfocused.
    editBox.placeholderFS = editBox:CreateFontString(nil, "OVERLAY")
    editBox.placeholderFS:SetFont(STANDARD_TEXT_FONT, 12, "")
    editBox.placeholderFS:SetTextColor(PALETTE.faint[1], PALETTE.faint[2], PALETTE.faint[3], 1)
    editBox.placeholderFS:SetPoint("LEFT", 2, 0)
    editBox.placeholderFS:SetPoint("RIGHT", -2, 0)
    editBox.placeholderFS:SetJustifyH("LEFT")
    editBox.placeholderFS:Hide()

    function editBox:UpdatePlaceholder()
        if self.placeholderText and self.placeholderText ~= ""
            and self:GetText() == "" and not self:HasFocus() then
            self.placeholderFS:Show()
        else
            self.placeholderFS:Hide()
        end
    end

    function editBox:SetPlaceholder(text)
        self.placeholderText = text
        self.placeholderFS:SetText(text or "")
        self:UpdatePlaceholder()
    end

    return editBox, holder
end

function UIElements.CreateToggle(parent, text, width)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(width or 118, 30)
    toggle.bg = UIElements.AddTexture(toggle, "BACKGROUND", PALETTE.field)
    toggle.rail = toggle:CreateTexture(nil, "BORDER")
    toggle.rail:SetPoint("LEFT", 8, 0)
    toggle.rail:SetSize(26, 14)
    TextureColor(toggle.rail, PALETTE.stroke)
    toggle.knob = toggle:CreateTexture(nil, "ARTWORK")
    toggle.knob:SetPoint("LEFT", toggle.rail, "LEFT", 2, 0)
    toggle.knob:SetSize(10, 10)
    TextureColor(toggle.knob, PALETTE.muted)
    toggle.text = UIElements.CreateLabel(toggle, text, 11, PALETTE.text)
    toggle.text:SetPoint("LEFT", 42, 0)
    toggle.checked = false

    function toggle:SetChecked(value)
        self.checked = value and true or false
        if self.checked then
            TextureColor(self.rail, { PALETTE.teal[1] * 0.40, PALETTE.teal[2] * 0.40, PALETTE.teal[3] * 0.40, 1 })
            TextureColor(self.knob, PALETTE.teal)
            self.knob:ClearAllPoints()
            self.knob:SetPoint("RIGHT", self.rail, "RIGHT", -2, 0)
        else
            TextureColor(self.rail, PALETTE.stroke)
            TextureColor(self.knob, PALETTE.muted)
            self.knob:ClearAllPoints()
            self.knob:SetPoint("LEFT", self.rail, "LEFT", 2, 0)
        end
    end

    function toggle:GetChecked()
        return self.checked
    end

    toggle:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
    end)

    return toggle
end

function UIElements.CreateDivider(parent)
    local divider = parent:CreateTexture(nil, "BORDER")
    divider:SetHeight(1)
    TextureColor(divider, PALETTE.stroke)
    return divider
end

function UIElements.SetButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
        button:SetAlpha(1)
    else
        button:Disable()
        button:SetAlpha(0.40)
    end
end

-- Small square glass button holding a centered icon texture (header actions).
function UIElements.CreateIconButton(parent, texturePath, size, accent)
    accent = accent or PALETTE.teal
    size = size or 26
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.accent = accent
    b.normalColor = { 0.090, 0.105, 0.130, 0.65 }
    b.hoverColor = { accent[1] * 0.30, accent[2] * 0.30, accent[3] * 0.30, 0.9 }
    b.bg = UIElements.AddTexture(b, "BACKGROUND", b.normalColor)

    b.top = b:CreateTexture(nil, "BORDER"); b.top:SetPoint("TOPLEFT"); b.top:SetPoint("TOPRIGHT"); b.top:SetHeight(1); TextureColor(b.top, PALETTE.stroke)
    b.bottom = b:CreateTexture(nil, "BORDER"); b.bottom:SetPoint("BOTTOMLEFT"); b.bottom:SetPoint("BOTTOMRIGHT"); b.bottom:SetHeight(1); TextureColor(b.bottom, PALETTE.stroke)
    b.left = b:CreateTexture(nil, "BORDER"); b.left:SetPoint("TOPLEFT"); b.left:SetPoint("BOTTOMLEFT"); b.left:SetWidth(1); TextureColor(b.left, PALETTE.stroke)
    b.right = b:CreateTexture(nil, "BORDER"); b.right:SetPoint("TOPRIGHT"); b.right:SetPoint("BOTTOMRIGHT"); b.right:SetWidth(1); TextureColor(b.right, PALETTE.stroke)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(math.floor(size * 0.6), math.floor(size * 0.6))
    if texturePath then
        b.icon:SetTexture(texturePath)
    end

    -- Text glyph alternative (reliable where a texture path is uncertain).
    b.glyph = UIElements.CreateLabel(b, "", math.floor(size * 0.66), accent)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetJustifyH("CENTER")
    b.SetGlyph = function(self, text) self.glyph:SetText(text or "") end

    b.isActive = false
    b:SetScript("OnEnter", function(self) TextureColor(self.bg, self.hoverColor) end)
    b:SetScript("OnLeave", function(self) TextureColor(self.bg, self.isActive and self.hoverColor or self.normalColor) end)
    b:SetScript("OnMouseDown", function(self) TextureColor(self.bg, { self.accent[1] * 0.45, self.accent[2] * 0.45, self.accent[3] * 0.45, 0.95 }) end)
    b:SetScript("OnMouseUp", function(self) TextureColor(self.bg, self.hoverColor) end)
    b.SetActive = function(self, value)
        self.isActive = value and true or false
        UIElements.SetPanelBorder(self, self.isActive and self.accent or PALETTE.stroke)
        TextureColor(self.bg, self.isActive and self.hoverColor or self.normalColor)
    end
    b.SetIcon = function(self, path) self.icon:SetTexture(path) end
    return b
end

-- A role pip that can be toggled on/off, used as a "needs this role" filter.
function UIElements.CreateRoleToggle(parent, role, size)
    local pip = UIElements.CreateRolePip(parent, size)
    pip:SetRole(role)
    pip.role = role
    pip.selected = false
    pip:EnableMouse(true)

    function pip:SetSelected(value)
        self.selected = value and true or false
        self:SetAlpha(self.selected and 1 or 0.35)
    end
    pip:SetSelected(false)

    pip:SetScript("OnMouseUp", function(self)
        self:SetSelected(not self.selected)
        if self.onToggle then
            self.onToggle(self.role, self.selected)
        end
    end)
    pip:SetScript("OnEnter", function(self)
        if not self.selected then self:SetAlpha(0.7) end
    end)
    pip:SetScript("OnLeave", function(self)
        self:SetSelected(self.selected)
    end)

    return pip
end

-- Joined "role counter": a single pill with a colored role cap (T/H/D) flush
-- against a numeric input — reads as one control instead of a loose pip + box.
-- Returns (editBox, shell); use editBox:GetText()/SetText() for the count.
function UIElements.CreateRoleCounter(parent, name, role, width, height)
    local ROLE = {
        tank = { PALETTE.roleTank, "T" },
        heal = { PALETTE.roleHeal, "H" },
        dps = { PALETTE.roleDps, "D" },
    }
    local m = ROLE[role] or ROLE.dps
    local color = m[1]
    width = width or 62
    height = height or 28
    local capW = 24

    local shell = UIElements.CreatePanel(parent, name and (name .. "Shell") or nil, PALETTE.field, PALETTE.stroke)
    shell:SetSize(width, height)

    local cap = shell:CreateTexture(nil, "ARTWORK")
    cap:SetPoint("TOPLEFT", 1, -1)
    cap:SetPoint("BOTTOMLEFT", 1, 1)
    cap:SetWidth(capW)
    TextureColor(cap, { color[1] * 0.30, color[2] * 0.30, color[3] * 0.30, 0.95 })

    local divider = shell:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", cap, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", cap, "BOTTOMRIGHT", 0, 0)
    divider:SetWidth(1)
    TextureColor(divider, { color[1], color[2], color[3], 0.55 })

    local letter = UIElements.CreateLabel(shell, m[2], math.max(11, math.floor(height * 0.5)), color)
    letter:SetPoint("LEFT", 1, 0)
    letter:SetWidth(capW)
    letter:SetJustifyH("CENTER")

    local editBox = CreateFrame("EditBox", name, shell)
    editBox.shell = shell
    editBox:SetPoint("LEFT", cap, "RIGHT", 2, 0)
    editBox:SetPoint("RIGHT", -4, 0)
    editBox:SetHeight(height - 4)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(2)
    editBox:SetFont(STANDARD_TEXT_FONT, 13, "")
    editBox:SetJustifyH("CENTER")
    editBox:SetTextColor(PALETTE.text[1], PALETTE.text[2], PALETTE.text[3], 1)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self) UIElements.SetPanelBorder(self.shell, PALETTE.strokeHot) end)
    editBox:SetScript("OnEditFocusLost", function(self) UIElements.SetPanelBorder(self.shell, PALETTE.stroke) end)

    return editBox, shell
end

-- Custom glass dropdown (no Blizzard widget). Use :SetOptions({{value=,label=}}, value)
-- and assign .onSelect(value). Opens a popup list; closes on pick or outside click.
function UIElements.CreateDropdown(parent, width, height, accent)
    accent = accent or PALETTE.teal
    height = height or 30
    local dd = UIElements.CreatePanel(parent, nil, PALETTE.field, PALETTE.stroke)
    dd:SetSize(width or 150, height)
    dd.accent = accent
    dd.options = {}
    dd.value = nil
    dd.onSelect = nil
    dd:EnableMouse(true)

    dd.label = UIElements.CreateLabel(dd, "", 11, PALETTE.text)
    dd.label:SetPoint("LEFT", 10, 0)
    dd.label:SetPoint("RIGHT", -20, 0)
    dd.label:SetJustifyH("LEFT")

    dd.caret = UIElements.CreateLabel(dd, "v", 9, PALETTE.muted)
    dd.caret:SetPoint("RIGHT", -8, 0)

    dd.rowH = 24
    dd.maxRows = 12

    local popup = UIElements.CreatePanel(dd, nil, PALETTE.panel2, accent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -3)
    popup:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -3)
    popup:Hide()
    dd.popup = popup

    -- Scrollable list inside the popup (activity lists can be long).
    local scroll = CreateFrame("ScrollFrame", nil, popup)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * dd.rowH * 2)))
    end)
    dd.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    dd.content = content
    dd.rows = {}

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:Hide()
    dd.catcher = catcher

    function dd:Close()
        self.popup:Hide()
        self.catcher:Hide()
    end

    function dd:IsOpen()
        return self.popup:IsShown()
    end

    function dd:SetValue(value, fire)
        self.value = value
        local shown = false
        for _, opt in ipairs(self.options) do
            if opt.value == value then
                self.label:SetText(opt.label)
                shown = true
                break
            end
        end
        if not shown then
            self.label:SetText(self.placeholder or "")
        end
        if fire and self.onSelect then
            self.onSelect(value)
        end
    end

    function dd:SetOptions(options, value)
        self.options = options or {}
        local rowH = self.rowH
        local innerWidth = self:GetWidth() - 4
        self.content:SetWidth(innerWidth)
        for i, opt in ipairs(self.options) do
            local row = self.rows[i]
            if not row then
                row = UIElements.CreateButton(self.content, "", 10, rowH, self.accent)
                -- List rows are borderless (a per-row frame would look like a
                -- grid); selection/hover is carried by the background fill.
                row.top:Hide(); row.bottom:Hide(); row.left:Hide(); row.right:Hide()
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * rowH)
            row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(i - 1) * rowH)
            row:SetHeight(rowH)
            row:SetText(opt.label)
            row.label:ClearAllPoints()
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            if opt.header then
                -- Non-interactive category heading: tinted, accent-colored title.
                row:EnableMouse(false)
                row:SetScript("OnClick", nil)
                TextureColor(row.bg, { 0.045, 0.055, 0.072, 0.92 })
                row.label:SetPoint("LEFT", 8, 0)
                row.label:SetTextColor(self.accent[1], self.accent[2], self.accent[3], 0.95)
            else
                row:EnableMouse(true)
                TextureColor(row.bg, row.normalColor)
                row.label:SetPoint("LEFT", opt.indent and 22 or 10, 0)
                row.label:SetTextColor(PALETTE.text[1], PALETTE.text[2], PALETTE.text[3], 1)
                local optValue = opt.value
                row:SetScript("OnClick", function()
                    dd:SetValue(optValue, true)
                    dd:Close()
                end)
            end
            row:Show()
        end
        for i = #self.options + 1, #self.rows do
            self.rows[i]:Hide()
        end
        local n = #self.options
        self.content:SetHeight(math.max(1, n * rowH))
        local visible = math.min(n, self.maxRows)
        self.popup:SetHeight(4 + math.max(1, visible) * rowH)
        self:SetValue(value, false)
    end

    function dd:Toggle()
        if self:IsOpen() then
            self:Close()
        else
            self.scroll:SetVerticalScroll(0)
            self.catcher:Show()
            self.popup:Show()
            self.popup:Raise()
        end
    end

    catcher:SetScript("OnClick", function() dd:Close() end)
    dd:SetScript("OnMouseUp", function(self) self:Toggle() end)
    dd:SetScript("OnEnter", function(self) UIElements.SetPanelBorder(self, self.accent) end)
    dd:SetScript("OnLeave", function(self)
        if not self:IsOpen() then
            UIElements.SetPanelBorder(self, PALETTE.stroke)
        end
    end)

    return dd
end

_G[ADDON_NAME .. "_UIElements"] = UIElements
return UIElements
