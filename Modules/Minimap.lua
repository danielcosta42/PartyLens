local ADDON_NAME = ...
local Localization = _G[ADDON_NAME .. "_Localization"]

local MinimapButton = {}

local BUTTON_RADIUS = 80
local DEG_TO_RAD = math.pi / 180

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function UpdatePosition(partyLens)
    if not partyLens.minimapButton or not Minimap then
        return
    end

    local angle = (partyLens.db and partyLens.db.minimapAngle) or 225
    local radians = angle * DEG_TO_RAD
    local x = math.cos(radians) * BUTTON_RADIUS
    local y = math.sin(radians) * BUTTON_RADIUS

    partyLens.minimapButton:ClearAllPoints()
    partyLens.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SavePosition(partyLens)
    if not partyLens.minimapButton or not Minimap then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local angle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
    if angle < 0 then
        angle = angle + 360
    end

    partyLens.db.minimapAngle = angle
    UpdatePosition(partyLens)
end

function MinimapButton.Create(partyLens)
    if partyLens.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "PartyLensMinimapButton", Minimap)
    partyLens.minimapButton = button
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Addon logo (Icon.tga, round badge). No SetMask+SetTexCoord combo — mixing
    -- the two rendered blank on this client.
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetTexture("Interface\\AddOns\\PartyLens\\Icon")

    -- Tracking-border ring positioned the LibDBIcon way: TOPLEFT-anchored on a
    -- 31px button with a 53px ring, so the art's hole lands over the centered
    -- icon. The old CENTER-ish -11,11 offset is what made it look misaligned.
    button.ring = button:CreateTexture(nil, "OVERLAY")
    button.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.ring:SetSize(53, 53)
    button.ring:SetPoint("TOPLEFT", 0, 0)

    -- Left-click opens the window; RIGHT-click toggles the layer beacon.
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            local LayerNet = _G[ADDON_NAME .. "_LayerNet"]
            if LayerNet then
                LayerNet.ToggleBeacon(partyLens)
            end
        else
            partyLens:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            SavePosition(partyLens)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        SavePosition(partyLens)
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("PartyLens", 0.12, 0.85, 0.72)
            GameTooltip:AddLine(Localization.L("MINIMAP_TOOLTIP"), 0.9, 0.93, 0.93, true)
            local on = partyLens.db and partyLens.db.layer and partyLens.db.layer.beacon
            GameTooltip:AddLine(Localization.L("MINIMAP_BEACON",
                on and Localization.L("LAYER_ON") or Localization.L("LAYER_OFF")), 0.6, 0.62, 0.68, true)
            GameTooltip:AddLine(Localization.L("CREDIT_BY"), 0.4, 0.42, 0.46)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    UpdatePosition(partyLens)
end

function MinimapButton.SetShown(partyLens, shown)
    if not partyLens.minimapButton then
        MinimapButton.Create(partyLens)
    end

    if partyLens.minimapButton then
        if shown then
            partyLens.minimapButton:Show()
        else
            partyLens.minimapButton:Hide()
        end
    end
end

_G[ADDON_NAME .. "_Minimap"] = MinimapButton
return MinimapButton
