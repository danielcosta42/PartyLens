--=============================================================================
-- Minimap button (no LibDBIcon): the mark on a slate disc, dragged around the minimap edge, angle saved in
-- PartyLensDB.minimap.angle. Left click opens the window, right click opens Settings. The addon compartment
-- (the addon menu by the minimap) lists PartyLens too, when the client has one.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T = UI.T
local L = UI.L

local MM = {}
UI.minimap = MM

-- The contract's way in (section 0): PartyLens:Toggle(), which forwards to PartyLens.UI.
function MM.Toggle()
	local core = rawget(_G, "PartyLens")
	if type(core) == "table" and core.Toggle then core:Toggle() else UI:Toggle() end
end

local function Radius()
	return (Minimap:GetWidth() or 140) / 2 + 8
end

function MM:Place()
	local b = self.button
	if not b then return end
	local a = math.rad(UI:Setting("minimapAngle") or 200)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * Radius(), math.sin(a) * Radius())
end

-- The angle (degrees, 0 = east, counterclockwise) of the cursor around the minimap centre.
function MM:CursorAngle()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local mx, my = Minimap:GetCenter()
	return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("PartyLens", T.amber[1], T.amber[2], T.amber[3])
	GameTooltip:AddLine(L["Click: open or close"], T.text[1], T.text[2], T.text[3])
	GameTooltip:AddLine(L["Right-click: settings"], T.text[1], T.text[2], T.text[3])
	GameTooltip:AddLine(L["Drag: move around the minimap"], T.muted[1], T.muted[2], T.muted[3])
	GameTooltip:Show()
end

function MM:Create()
	if self.button or not Minimap then return end
	local b = CreateFrame("Button", "PartyLensMinimapButton", Minimap)
	b:SetSize(32, 32)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b.disc = UI.Tex(b, "dot", 28, T.bg, 1, "BACKGROUND")
	b.disc:SetPoint("CENTER")
	b.mark = UI.Tex(b, "mark", 20, T.amber)
	b.mark:SetPoint("CENTER")
	b.border = UI.Tex(b, "ring", 32, T.lineHi, 1, "OVERLAY")
	b.border:SetPoint("CENTER")
	b:SetScript("OnEnter", function(btn)
		UI.Paint(btn.border, T.amber)
		Tooltip(btn)
	end)
	b:SetScript("OnLeave", function(btn)
		UI.Paint(btn.border, T.lineHi)
		GameTooltip:Hide()
	end)
	b:SetScript("OnMouseDown", function(btn) UI.Motion.Press(btn) end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then UI:Open("settings") else MM.Toggle() end
	end)
	b:SetScript("OnDragStart", function(btn)
		btn:SetScript("OnUpdate", function()
			UI:SetSetting("minimapAngle", MM:CursorAngle(), true)
			MM:Place()
		end)
	end)
	b:SetScript("OnDragStop", function(btn)
		btn:SetScript("OnUpdate", nil)
		UI:SetSetting("minimapAngle", MM:CursorAngle())
		MM:Place()
	end)
	self.button = b
	self:Place()
	self:Apply()
end

function MM:Apply()
	if self.button then self.button:SetShown(not UI:Setting("minimapHidden")) end
end

function MM:RegisterCompartment()
	if self.compartment then return end
	local frame = _G.AddonCompartmentFrame
	if not (frame and frame.RegisterAddon) then return end
	self.compartment = true
	frame:RegisterAddon({
		text = "PartyLens",
		icon = UI.MEDIA .. "logo",
		notCheckable = true,
		func = function() MM.Toggle() end,
		funcOnEnter = function(button) Tooltip(button) end,
		funcOnLeave = function() GameTooltip:Hide() end,
	})
end

function MM:Init()
	self:Create()
	self:RegisterCompartment()
	UI:OnSetting("minimapHidden", function() MM:Apply() end)
end
