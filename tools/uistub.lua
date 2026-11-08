-- A generic WoW: Forever widget layer for the interface harness (tools/ui.lua), laid over the core's simulated
-- client (tools/wowstub.lua): wowstub keeps the clock, the events, the protected calls and the error handler;
-- this file gives the UI real-enough widgets.
--
-- Frames, textures, font strings and animation groups are plain tables. Methods the UI needs to behave
-- (points, sizes, visibility with OnShow/OnHide, scripts, text, scroll, slider, edit box focus, buttons
-- enabling, animation groups that play, loop and finish on wowstub's clock) are implemented; any other method
-- name that starts with a capital letter returns a no-op. Every method name the UI touches is recorded per
-- widget type, so the harness can check it against API, the method lists of the Forever client's own
-- Blizzard_APIDocumentationGenerated (build 1.60.1.70862, retail 12.x), plus the few Lua-side methods the
-- client adds (BackdropTemplate, GameTooltip). APIs gone from the client and Blizzard dropdowns error here.
--
--   local W = dofile("tools/wowstub.lua")
--   local Stub = dofile("tools/uistub.lua")
--   local S = Stub.overlay(W, opts)   -- after wowstub installed its client, before the UI files load
local Stub = {}

-- ── Forever API (generated from the client's API documentation) ──────────────
local API = {
	SimpleObjectAPI = [[ClearParentKey GetDebugName GetParent GetParentKey SetParentKey]],
	SimpleFrameScriptObjectAPI = [[AddAccessRestrictions AddForbiddenAspects AddSecretAspect CanBeAccessedInContext GetAccessRestrictions
		GetForbiddenAspects GetInheritableForbiddenAspects GetName GetObjectTable GetObjectType HasAccessConstraints
		HasAnyAccessRestrictions HasAnyForbiddenAspects HasAnySecretAspect HasSecretAspect HasSecretValues
		IsForbidden IsObjectType IsPreventingSecretValues SetForbidden SetToDefaults]],
	SimpleScriptRegionAPI = [[CanChangeProtectedState CanPropagateMouseClicks CanPropagateMouseMotion ClearScripts CollapsesLayout
		EnableMouse EnableMouseMotion EnableMouseWheel FocusEnter FocusExit GetBottom GetCenter GetHeight GetLeft
		GetRect GetRight GetRoundLayoutToNearestPixel GetScaledRect GetScript GetSize GetSourceLocation GetTop
		GetWidth HasScript Hide HookScript Intersects IsAnchoringRestricted IsAnchoringSecret IsCollapsed IsDragging
		IsMouseClickEnabled IsMouseEnabled IsMouseMotionEnabled IsMouseMotionFocus IsMouseOver IsMouseWheelEnabled
		IsProtected IsRectValid IsShown IsVisible MouseDown MouseUp SetCollapsesLayout SetMouseClickEnabled
		SetMouseMotionEnabled SetParent SetPassThroughButtons SetPropagateMouseClicks SetPropagateMouseMotion
		SetRoundLayoutToNearestPixel SetScript SetShown ShouldButtonPassThrough Show]],
	SimpleScriptRegionResizingAPI = [[AdjustPointsOffset ClearAllPoints ClearPoint ClearPointsOffset GetNumPoints GetPoint GetPointByName
		SetAllPoints SetHeight SetPoint SetPointsOffset SetSize SetWidth]],
	SimpleAnimatableObjectAPI = [[CreateAnimationGroup GetAnimationGroups StopAnimating]],
	SimpleRegionAPI = [[GetAlpha GetDrawLayer GetEffectiveScale GetScale GetVertexColor IsIgnoringParentAlpha IsIgnoringParentScale
		IsObjectLoaded SetAlpha SetAlphaFromBoolean SetDrawLayer SetIgnoreParentAlpha SetIgnoreParentScale SetScale
		SetVertexColor SetVertexColorFromBoolean]],
	SimpleTextureBaseAPI = [[ClearRadialProgressBar ClearSVG ClearTextureSlice ClearVertexOffsets GetAtlas GetBlendMode GetDesaturation
		GetHorizTile GetRadialProgressBarEndOffset GetRadialProgressBarFeather GetRadialProgressBarPercent
		GetRadialProgressBarReverse GetRadialProgressBarStartOffset GetRotation GetTexCoord GetTexelSnappingBias
		GetTexture GetTextureFileID GetTextureFilePath GetTextureSliceMargins GetTextureSliceMode GetVertTile
		GetVertexOffset IsBlockingLoadRequested IsDesaturated IsSnappingToPixelGrid ResetTexCoord SetAtlas
		SetBlendMode SetBlockingLoadsRequested SetColorTexture SetDesaturated SetDesaturation SetGradient
		SetHorizTile SetMask SetRadialProgressBarEndOffset SetRadialProgressBarFeather SetRadialProgressBarPercent
		SetRadialProgressBarReverse SetRadialProgressBarStartOffset SetRotation SetSVG SetSnapToPixelGrid
		SetSpriteSheetCell SetTexCoord SetTexelSnappingBias SetTexture SetTextureSliceMargins SetTextureSliceMode
		SetVertTile SetVertexOffset]],
	SimpleTextureAPI = [[AddMaskTexture GetMaskTexture GetNumMaskTextures RemoveMaskTexture]],
	SimpleFontStringAPI = [[CalculateScreenAreaFromCharacterSpan CanNonSpaceWrap CanWordWrap ClearAlphaGradient ClearText
		FindCharacterIndexAtCoordinate GetAlphaGradient GetFieldSize GetFont GetFontHeight GetFontObject
		GetIndentedWordWrap GetJustifyH GetJustifyV GetLineHeight GetMaxLines GetNumLines GetRotation
		GetScaleAnimationMode GetShadowColor GetShadowOffset GetSmoothScaling GetSpacing GetStringHeight
		GetStringWidth GetText GetTextColor GetTextScale GetUnboundedStringWidth GetUnboundedStringWidthForText
		GetWrappedWidth IsTruncated OnColorsUpdated SetAlphaGradient SetDesaturateEmbeddedTextures SetFixedColor
		SetFont SetFontHeight SetFontObject SetFormattedText SetIndentedWordWrap SetJustifyH SetJustifyV SetMaxLines
		SetNonSpaceWrap SetRotation SetScaleAnimationMode SetShadowColor SetShadowOffset SetSmoothScaling SetSpacing
		SetText SetTextColor SetTextHeight SetTextScale SetTextToFit SetWordWrap]],
	SimpleFrameAPI = [[AbortDrag AddRoleset CanChangeAttribute ClearAlphaGradient ClearAttribute ClearAttributes CreateFontString
		CreateLine CreateMaskTexture CreateTexture CreateVectorGraphics DesaturateHierarchy DisableDrawLayer
		DoesClipChildren DoesHyperlinkPropagateToParent EnableDrawLayer EnableGamePadButton EnableGamePadStick
		EnableKeyboard ExecuteAttribute GetAlpha GetAttribute GetBoundsRect GetChildren GetClampRectInsets
		GetDontSavePosition GetEffectiveAlpha GetEffectiveScale GetEffectivelyFlattensRenderLayers
		GetFlattensRenderLayers GetFrameLevel GetFrameStrata GetHighestFrameLevel GetHitRectInsets
		GetHyperlinksEnabled GetID GetNumChildren GetNumRegions GetOnUpdateMode GetPropagateKeyboardInput
		GetRaisedFrameLevel GetRegions GetResizeBounds GetRolesetNames GetScale GetWindow HasAlphaGradient
		HasFixedFrameLevel HasFixedFrameStrata Hide InterceptStartDrag IsClampedToScreen IsDrawLayerEnabled
		IsEventRegistered IsFrameBuffer IsGamePadButtonEnabled IsGamePadStickEnabled IsHighlightLocked
		IsIgnoringChildrenForBounds IsIgnoringParentAlpha IsIgnoringParentScale IsKeyboardEnabled IsMovable
		IsObjectLoaded IsResizable IsRolesetFiltered IsShown IsToplevel IsUserPlaced IsUsingParentLevel IsVisible
		LockHighlight Lower Raise RegisterAllEvents RegisterEvent RegisterEventCallback RegisterForDrag
		RegisterUnitEvent RegisterUnitEventCallback RemoveRoleset ResizeToBoundsRect RotateTextures SetAlpha
		SetAlphaFromBoolean SetAlphaGradient SetAttribute SetAttributeNoHandler SetClampRectInsets
		SetClampedToScreen SetClipsChildren SetDontSavePosition SetDrawLayerEnabled SetFixedFrameLevel
		SetFixedFrameStrata SetFlattensRenderLayers SetFrameLevel SetFrameStrata SetHighlightLocked SetHitRectInsets
		SetHyperlinkPropagateToParent SetHyperlinksEnabled SetID SetIgnoreParentAlpha SetIgnoreParentScale
		SetIgnoringChildrenForBounds SetIsFrameBuffer SetMovable SetOnUpdateMode SetPropagateKeyboardInput
		SetResizable SetResizeBounds SetRolesets SetScale SetShown SetToplevel SetUserPlaced SetUsingParentLevel
		SetWindow Show StartMoving StartSizing StopMovingOrSizing UnlockHighlight UnregisterAllEvents
		UnregisterEvent]],
	SimpleButtonAPI = [[ClearDisabledTexture ClearHighlightTexture ClearNormalTexture ClearPushedTexture Click Disable Enable
		GetButtonState GetDisabledFontObject GetDisabledTexture GetFontString GetHighlightFontObject
		GetHighlightTexture GetMotionScriptsWhileDisabled GetNormalFontObject GetNormalTexture GetPushedTextOffset
		GetPushedTexture GetText GetTextHeight GetTextWidth IsEnabled RegisterForClicks RegisterForMouse
		SetButtonState SetDisabledAtlas SetDisabledFontObject SetDisabledTexture SetEnabled SetFontString
		SetFormattedText SetHighlightAtlas SetHighlightFontObject SetHighlightTexture SetMotionScriptsWhileDisabled
		SetNormalAtlas SetNormalFontObject SetNormalTexture SetPushedAtlas SetPushedTextOffset SetPushedTexture
		SetText]],
	SimpleCheckboxAPI = [[GetChecked GetCheckedTexture GetDisabledCheckedTexture SetChecked SetCheckedTexture
		SetDisabledCheckedTexture]],
	SimpleEditBoxAPI = [[AddHistoryLine ClearFocus ClearHighlightText ClearHistory Disable Enable GetAltArrowKeyMode GetBlinkSpeed
		GetCursorPosition GetDisplayText GetFont GetFontObject GetHighlightColor GetHistoryLines GetIndentedWordWrap
		GetInputLanguage GetJustifyH GetJustifyV GetMaxBytes GetMaxLetters GetNumLetters GetNumLines GetNumber
		GetShadowColor GetShadowOffset GetSpacing GetText GetTextColor GetTextInsets GetUTF8CursorPosition
		GetVisibleTextByteLimit HasFocus HasText HighlightText Insert IsAlphabeticOnly IsAutoFocus
		IsCountInvisibleLetters IsEnabled IsInIMECompositionMode IsMultiLine IsNumeric IsNumericFullRange IsPassword
		IsSecureText ResetInputMode SetAlphabeticOnly SetAltArrowKeyMode SetAutoFocus SetBlinkSpeed
		SetCountInvisibleLetters SetCursorPosition SetEnabled SetFocus SetFont SetFontObject SetHighlightColor
		SetHistoryLines SetIndentedWordWrap SetJustifyH SetJustifyV SetMaxBytes SetMaxLetters SetMultiLine SetNumber
		SetNumeric SetNumericFullRange SetPassword SetSecureText SetSecurityDisablePaste SetSecurityDisableSetText
		SetShadowColor SetShadowOffset SetSpacing SetText SetTextColor SetTextInsets SetVisibleTextByteLimit
		ToggleInputLanguage]],
	SimpleScrollFrameAPI = [[GetHorizontalScroll GetHorizontalScrollRange GetScrollChild GetVerticalScroll GetVerticalScrollRange
		SetHorizontalScroll SetScrollChild SetVerticalScroll UpdateScrollChildRect]],
	SimpleSliderAPI = [[Disable Enable GetMinMaxValues GetObeyStepOnDrag GetOrientation GetStepsPerPage GetThumbTexture GetValue
		GetValueStep IsDraggingThumb IsEnabled SetEnabled SetMinMaxValues SetObeyStepOnDrag SetOrientation
		SetStepsPerPage SetThumbTexture SetValue SetValueStep]],
	FrameAPICooldown = [[Clear GetCooldownDisplayDuration GetCooldownDuration GetCooldownTimes GetCountdownAbbrevThreshold
		GetCountdownFontString GetCountdownFormatter GetCountdownMillisecondsThreshold GetDrawBling GetDrawEdge
		GetDrawSwipe GetEdgeScale GetHideCountdownNumbers GetMinimumCountdownDuration GetReverse GetRotation
		GetUseAuraDisplayTime IsPaused Pause Resume SetBlingTexture SetCooldown SetCooldownDuration
		SetCooldownFromDurationObject SetCooldownFromExpirationTime SetCooldownUNIX SetCountdownAbbrevThreshold
		SetCountdownFont SetCountdownFormatter SetCountdownMillisecondsThreshold SetDrawBling SetDrawEdge
		SetDrawSwipe SetEdgeColor SetEdgeScale SetEdgeTexture SetHideCountdownNumbers SetMinimumCountdownDuration
		SetPaused SetReverse SetRotation SetSwipeColor SetSwipeTexture SetTexCoordRange SetUseAuraDisplayTime
		SetUseCircularEdge]],
	SimpleStatusBarAPI = [[GetFillStyle GetInterpolatedValue GetMinMaxValues GetOrientation GetRenderMode GetReverseFill
		GetRotatesTexture GetStatusBarColor GetStatusBarDesaturation GetStatusBarTexture GetTimerDuration GetValue
		IsInterpolating IsStatusBarDesaturated SetColorFill SetFillStyle SetMinMaxValues SetOrientation
		SetRenderMode SetReverseFill SetRotatesTexture SetStatusBarColor SetStatusBarDesaturated
		SetStatusBarDesaturation SetStatusBarTexture SetTimerDuration SetToTargetValue SetValue]],
	FrameAPITooltip = [[AddFontStrings ClearPadding GetLeftLine GetMinimumWidth GetPadding GetRightLine SetMinimumWidth SetPadding
		SetText]],
	SimpleAnimGroupAPI = [[CreateAnimation Finish GetAnimationSpeedMultiplier GetAnimations GetDuration GetElapsed GetLoopState
		GetLooping GetProgress GetScript HasScript HookScript IsDone IsPaused IsPendingFinish IsPlaying IsReverse
		IsSetToFinalAlpha Pause Play RemoveAnimations Restart SetAnimationSpeedMultiplier SetLooping SetPlaying
		SetScript SetToFinalAlpha Stop]],
	SimpleAnimAPI = [[GetDuration GetElapsed GetEndDelay GetOrder GetProgress GetRegionParent GetScript GetSmoothProgress
		GetSmoothing GetStartDelay GetTarget HasScript HookScript IsDelaying IsDone IsPaused IsPlaying IsStopped
		Pause Play Restart SetChildKey SetDuration SetEndDelay SetOrder SetParent SetPlaying SetScript
		SetSmoothProgress SetSmoothing SetStartDelay SetTarget SetTargetKey SetTargetName SetTargetParent Stop]],
	SimpleAnimAlphaAPI = [[GetFromAlpha GetToAlpha SetFromAlpha SetToAlpha]],
	SimpleAnimScaleAPI = [[GetOrigin GetScale GetScaleFrom GetScaleTo SetOrigin SetScale SetScaleFrom SetScaleTo]],
	SimpleAnimTranslationAPI = [[GetOffset SetOffset]],
	SimpleAnimRotationAPI = [[GetDegrees GetOrigin GetRadians SetDegrees SetOrigin SetRadians]],
	MinimapFrameAPI = [[GetPingPosition GetZoom GetZoomLevels PingLocation SetArchBlobInsideAlpha SetArchBlobInsideTexture
		SetArchBlobOutsideAlpha SetArchBlobOutsideTexture SetArchBlobRingAlpha SetArchBlobRingScalar
		SetArchBlobRingTexture SetIconScale SetMaskTexture SetQuestBlobInsideAlpha SetQuestBlobInsideTexture
		SetQuestBlobOutsideAlpha SetQuestBlobOutsideTexture SetQuestBlobRingAlpha SetQuestBlobRingScalar
		SetQuestBlobRingTexture SetTaskBlobInsideAlpha SetTaskBlobInsideTexture SetTaskBlobOutsideAlpha
		SetTaskBlobOutsideTexture SetTaskBlobRingAlpha SetTaskBlobRingScalar SetTaskBlobRingTexture
		SetUsingSoftCursor SetZoom UpdateBlips UpdateMouseoverAtPoint]],
	SimpleLineAPI = [[ClearAllPoints GetEndPoint GetHitRectThickness GetStartPoint GetThickness SetEndPoint SetHitRectThickness
		SetStartPoint SetThickness]],
}

local function set(...)
	local t = {}
	for _, list in ipairs({ ... }) do
		for name in list:gmatch("%S+") do t[name] = true end
	end
	return t
end

local BASE = API.SimpleObjectAPI .. " " .. API.SimpleFrameScriptObjectAPI
local SCRIPT_REGION = BASE .. " " .. API.SimpleScriptRegionAPI .. " " .. API.SimpleScriptRegionResizingAPI .. " " .. API.SimpleAnimatableObjectAPI
local FRAME = SCRIPT_REGION .. " " .. API.SimpleFrameAPI
local REGION = SCRIPT_REGION .. " " .. API.SimpleRegionAPI
-- Lua-side methods that are not in the C API documentation.
local TOOLTIP_LUA = "SetOwner AddLine AddDoubleLine ClearLines NumLines IsOwned GetOwner"
local BACKDROP_LUA = "SetBackdrop SetBackdropColor SetBackdropBorderColor GetBackdrop GetBackdropColor GetBackdropBorderColor ApplyBackdrop ClearBackdrop"

Stub.ALLOWED = {
	Frame = set(FRAME),
	Button = set(FRAME, API.SimpleButtonAPI),
	CheckButton = set(FRAME, API.SimpleButtonAPI, API.SimpleCheckboxAPI),
	EditBox = set(FRAME, API.SimpleEditBoxAPI),
	ScrollFrame = set(FRAME, API.SimpleScrollFrameAPI),
	Slider = set(FRAME, API.SimpleSliderAPI),
	Cooldown = set(FRAME, API.FrameAPICooldown),
	StatusBar = set(FRAME, API.SimpleStatusBarAPI),
	GameTooltip = set(FRAME, API.FrameAPITooltip, TOOLTIP_LUA),
	Minimap = set(FRAME, API.MinimapFrameAPI),
	Texture = set(REGION, API.SimpleTextureBaseAPI, API.SimpleTextureAPI),
	FontString = set(REGION, API.SimpleFontStringAPI),
	Line = set(REGION, API.SimpleTextureBaseAPI, API.SimpleLineAPI),
	AnimationGroup = set(BASE, API.SimpleAnimGroupAPI),
	Alpha = set(BASE, API.SimpleAnimAPI, API.SimpleAnimAlphaAPI),
	Scale = set(BASE, API.SimpleAnimAPI, API.SimpleAnimScaleAPI),
	Translation = set(BASE, API.SimpleAnimAPI, API.SimpleAnimTranslationAPI),
	Rotation = set(BASE, API.SimpleAnimAPI, API.SimpleAnimRotationAPI),
}
Stub.TEMPLATES = { BackdropTemplate = set(BACKDROP_LUA) }
local FRAME_TYPES = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true, Cooldown = true, StatusBar = true }
local ANIM_TYPES = { Alpha = true, Scale = true, Translation = true, Rotation = true }

function Stub.overlay(W, opts)
	opts = opts or {}
	local S = {
		objects = {}, groups = {}, used = {}, texts = {}, textures = {}, fonts = {}, sounds = {},
		errors = {}, plays = 0, playLog = {}, compartment = {}, cursor = { x = 0, y = 0 },
	}

	local function fail(err) S.errors[#S.errors + 1] = tostring(err) end

	local function fire(obj, name, ...)
		local fn = obj.__scripts and obj.__scripts[name]
		if not fn then return false end
		local ok, err = pcall(fn, obj, ...)
		if not ok then fail(name .. ": " .. tostring(err)) end
		return true
	end
	S.fire = fire

	-- ── objects ──────────────────────────────────────────────────────────
	local IMPL = {}
	local NOOP = function() end
	local MT = {
		__index = function(self, k)
			if type(k) ~= "string" or not k:match("^%u") then return nil end
			local key = rawget(self, "__kind") .. (rawget(self, "__template") and ("<" .. self.__template .. ">") or "")
			local u = S.used[key]
			if not u then u = {}; S.used[key] = u end
			u[k] = (u[k] or 0) + 1
			return IMPL[k] or NOOP
		end,
	}

	local function new(kind, parent, name, template)
		local o = setmetatable({
			__kind = kind, __parent = parent, __children = {}, __scripts = {}, __points = {}, __shown = true,
			__alpha = 1, __w = 0, __h = 0, __enabled = true, __name = name, __template = template, __id = #S.objects + 1,
		}, MT)
		S.objects[#S.objects + 1] = o
		if parent and parent.__children then table.insert(parent.__children, o) end
		if name then _G[name] = o end
		return o
	end
	S.new = new

	local function visible(o)
		while o do
			if not o.__shown then return false end
			o = o.__parent
		end
		return true
	end
	S.visible = visible

	-- Stops the playing groups of a region without OnFinished (OnStop fires), as the game does when the region
	-- is hidden mid-animation.
	local function interrupt(o)
		for _, g in ipairs(S.groups) do
			if g.__target == o and g.__playing then
				g.__playing = false
				fire(g, "OnStop")
			end
		end
	end
	S.interrupt = interrupt

	local function cascade(o, on)
		if not on then interrupt(o) end
		fire(o, on and "OnShow" or "OnHide")
		for _, c in ipairs(o.__children) do
			if c.__shown then cascade(c, on) end
		end
	end

	local function setShown(o, v)
		v = v and true or false
		local before = visible(o)
		o.__shown = v
		local after = visible(o)
		if before ~= after then cascade(o, after) end
	end

	-- regions
	function IMPL:Show() setShown(self, true) end
	function IMPL:Hide() setShown(self, false) end
	function IMPL:SetShown(v) setShown(self, v) end
	function IMPL:IsShown() return self.__shown end
	function IMPL:IsVisible() return visible(self) end
	function IMPL:SetAlpha(a) self.__alpha = a end
	function IMPL:GetAlpha() return self.__alpha end
	function IMPL:GetEffectiveScale() return 1 end
	function IMPL:GetScale() return 1 end
	function IMPL:GetParent() return self.__parent end
	function IMPL:GetName() return self.__name end
	function IMPL:GetObjectType() return self.__kind end
	function IMPL:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
		if rel == nil and relPoint == nil then relPoint = point end
		if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
		self.__points[#self.__points + 1] = { point, rel or self.__parent, relPoint or point, x or 0, y or 0 }
	end
	function IMPL:ClearAllPoints() self.__points = {} end
	function IMPL:SetAllPoints(rel) self.__points = { { "TOPLEFT", rel or self.__parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or self.__parent, "BOTTOMRIGHT", 0, 0 } } end
	function IMPL:GetNumPoints() return #self.__points end
	function IMPL:GetPoint(i)
		local p = self.__points[i or 1]
		if p then return p[1], p[2], p[3], p[4], p[5] end
	end
	local function resized(o, w, h)
		local changed = o.__w ~= w or o.__h ~= h
		o.__w, o.__h = w, h
		if changed then fire(o, "OnSizeChanged", w, h) end
	end
	function IMPL:SetSize(w, h) resized(self, w, h) end
	function IMPL:SetWidth(w) resized(self, w, self.__h) end
	function IMPL:SetHeight(h) resized(self, self.__w, h) end
	function IMPL:GetWidth() return self.__w end
	function IMPL:GetHeight() return self.__h end
	function IMPL:GetSize() return self.__w, self.__h end
	function IMPL:GetCenter() return self.__cx or 500, self.__cy or 400 end
	function IMPL:IsMouseOver() return self.__mouseOver or false end
	function IMPL:SetVertexColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end
	function IMPL:GetVertexColor() local c = self.__color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end

	-- scripts
	function IMPL:SetScript(name, fn) self.__scripts[name] = fn end
	function IMPL:GetScript(name) return self.__scripts[name] end
	function IMPL:HasScript() return true end
	function IMPL:HookScript(name, fn)
		local prev = self.__scripts[name]
		self.__scripts[name] = prev and function(...) prev(...); fn(...) end or fn
		return true
	end

	-- frames
	function IMPL:CreateTexture(name, layer, template, sublevel)
		local t = new("Texture", self, name)
		t.__layer, t.__sublevel = layer, sublevel
		return t
	end
	function IMPL:CreateFontString(name, layer)
		local t = new("FontString", self, name)
		t.__layer = layer
		return t
	end
	function IMPL:CreateLine(name, layer) return new("Line", self, name) end
	function IMPL:GetChildren() return unpack(self.__children) end
	function IMPL:GetNumChildren() return #self.__children end
	function IMPL:SetFrameLevel(l) self.__level = l end
	function IMPL:GetFrameLevel() return self.__level or 1 end
	function IMPL:SetFrameStrata(s) self.__strata = s end
	function IMPL:GetFrameStrata() return self.__strata or "MEDIUM" end
	-- Events come from wowstub: W.fire reaches these frames like the core's own.
	function IMPL:RegisterEvent(event)
		W.listeners[event] = W.listeners[event] or {}
		for _, f in ipairs(W.listeners[event]) do if f == self then return end end
		table.insert(W.listeners[event], self)
	end
	function IMPL:UnregisterEvent(event)
		for i, f in ipairs(W.listeners[event] or {}) do
			if f == self then table.remove(W.listeners[event], i) return end
		end
	end
	function IMPL:SetBackdrop(b) self.__backdrop = b end
	function IMPL:SetBackdropColor(r, g, b, a) self.__bg = { r, g, b, a or 1 } end
	function IMPL:SetBackdropBorderColor(r, g, b, a) self.__border = { r, g, b, a or 1 } end

	-- buttons
	local function enable(o, on)
		on = on and true or false
		if o.__enabled == on then return end
		o.__enabled = on
		fire(o, on and "OnEnable" or "OnDisable")
	end
	function IMPL:Enable() enable(self, true) end
	function IMPL:Disable() enable(self, false) end
	function IMPL:SetEnabled(on) enable(self, on) end
	function IMPL:IsEnabled() return self.__enabled end
	function IMPL:Click(button) fire(self, "OnClick", button or "LeftButton", false) end
	function IMPL:SetChecked(v) self.__checked = v and true or false end
	function IMPL:GetChecked() return self.__checked end

	-- text
	local function textOf(o, t)
		if t ~= nil then t = tostring(t) end
		o.__text = t
		if t and t ~= "" then S.texts[#S.texts + 1] = t end
	end
	function IMPL:SetText(t)
		textOf(self, t)
		if self.__kind == "EditBox" then fire(self, "OnTextChanged", false) end
	end
	function IMPL:SetFormattedText(fmt, ...) textOf(self, string.format(fmt, ...)) end
	function IMPL:GetText() return self.__text end
	function IMPL:SetFont(path, size, flags)
		self.__font = { path, size, flags }
		S.fonts[path] = true
		return true
	end
	function IMPL:GetFont() local f = self.__font or {}; return f[1], f[2], f[3] end
	function IMPL:GetStringWidth()
		local t = (self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local size = self.__font and self.__font[2] or 12
		local n = 0
		for _ in t:gmatch("[^\128-\191]") do n = n + 1 end
		return n * size * 0.5
	end
	function IMPL:GetStringHeight() return self.__font and self.__font[2] or 12 end
	function IMPL:SetTextColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end

	-- edit boxes
	function IMPL:SetFocus()
		if S.focus and S.focus ~= self then IMPL.ClearFocus(S.focus) end
		S.focus = self
		fire(self, "OnEditFocusGained")
	end
	function IMPL:ClearFocus()
		if S.focus == self then
			S.focus = nil
			fire(self, "OnEditFocusLost")
		end
	end
	function IMPL:HasFocus() return S.focus == self end

	-- textures
	function IMPL:SetTexture(path)
		self.__texture = path
		if type(path) == "string" then S.textures[path] = true end
		return true
	end
	function IMPL:GetTexture() return self.__texture end
	function IMPL:SetColorTexture(r, g, b, a) self.__texture = "color"; self.__fill = { r, g, b, a or 1 } end
	function IMPL:SetRotation(radians) self.__rotation = radians end
	function IMPL:GetRotation() return self.__rotation or 0 end
	function IMPL:SetRadialProgressBarPercent(p) self.__radial = p end
	function IMPL:GetRadialProgressBarPercent() return self.__radial end

	-- scroll frames and sliders
	function IMPL:SetScrollChild(child) self.__child = child end
	function IMPL:GetScrollChild() return self.__child end
	function IMPL:SetVerticalScroll(v)
		self.__scroll = v
		fire(self, "OnVerticalScroll", v)
	end
	function IMPL:GetVerticalScroll() return self.__scroll or 0 end
	function IMPL:GetVerticalScrollRange()
		return math.max(0, (self.__child and self.__child.__h or 0) - self.__h)
	end
	function IMPL:SetMinMaxValues(lo, hi) self.__min, self.__max = lo, hi end
	function IMPL:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
	function IMPL:SetValue(v)
		v = math.max(self.__min or 0, math.min(self.__max or 0, v))
		local changed = self.__value ~= v
		self.__value = v
		if changed then fire(self, "OnValueChanged", v, false) end
	end
	function IMPL:GetValue() return self.__value or 0 end

	-- animation groups
	function IMPL:CreateAnimationGroup(name)
		local g = new("AnimationGroup", nil, name)
		g.__target, g.__anims, g.__plays = self, {}, 0
		S.groups[#S.groups + 1] = g
		return g
	end
	function IMPL:CreateAnimation(kind, name)
		assert(ANIM_TYPES[kind], "unknown animation type " .. tostring(kind))
		local a = new(kind, nil, name)
		a.__group, a.__duration, a.__order = self, 0, 1
		table.insert(self.__anims, a)
		return a
	end
	function IMPL:SetDuration(d) self.__duration = d end
	function IMPL:GetDuration()
		if self.__kind ~= "AnimationGroup" then return self.__duration end
		local byOrder = {}
		for _, a in ipairs(self.__anims) do
			local o = a.__order or 1
			byOrder[o] = math.max(byOrder[o] or 0, (a.__delay or 0) + (a.__duration or 0))
		end
		local total = 0
		for _, d in pairs(byOrder) do total = total + d end
		return total
	end
	function IMPL:SetOrder(o) self.__order = o end
	function IMPL:SetStartDelay(d) self.__delay = d end
	function IMPL:SetSmoothing(s) self.__smoothing = s end
	function IMPL:SetFromAlpha(a) self.__from = a end
	function IMPL:SetToAlpha(a) self.__to = a end
	function IMPL:SetScaleFrom(x, y) self.__from = { x, y } end
	function IMPL:SetScaleTo(x, y) self.__to = { x, y } end
	function IMPL:SetOffset(x, y) self.__offset = { x, y } end
	function IMPL:SetDegrees(d) self.__degrees = d end
	function IMPL:SetOrigin(p, x, y) self.__origin = { p, x, y } end
	function IMPL:SetLooping(l) self.__looping = l end
	function IMPL:GetLooping() return self.__looping or "NONE" end
	function IMPL:Play(reverse, offset)
		S.plays = S.plays + 1
		S.playLog[#S.playLog + 1] = self
		self.__plays = (self.__plays or 0) + 1
		if self.__kind == "AnimationGroup" then
			self.__playing, self.__elapsed = true, offset or 0
		end
	end
	function IMPL:Stop()
		if self.__playing then
			self.__playing = false
			fire(self, "OnStop")
		end
	end
	function IMPL:Finish()
		if self.__playing then
			self.__playing = false
			fire(self, "OnFinished")
		end
	end
	function IMPL:Pause() self.__playing = false end
	function IMPL:IsPlaying() return self.__playing or false end
	function IMPL:GetElapsed() return self.__elapsed or 0 end
	function IMPL:GetProgress()
		local d = IMPL.GetDuration(self)
		return d > 0 and math.min(1, (self.__elapsed or 0) / d) or 0
	end

	-- tooltip
	function IMPL:SetOwner(owner) self.__owner, self.__lines = owner, {} end
	function IMPL:IsOwned(owner) return self.__owner == owner end
	function IMPL:GetOwner() return self.__owner end
	function IMPL:AddLine(text)
		self.__lines = self.__lines or {}
		table.insert(self.__lines, text)
		textOf(self, text)
	end
	function IMPL:NumLines() return #(self.__lines or {}) end

	-- ── clock ────────────────────────────────────────────────────────────
	-- Moves wowstub's clock in `step` slices (its timers and its frames' OnUpdate), then this layer's animation
	-- groups and the OnUpdate of visible widgets.
	function S.advance(seconds, step)
		step = step or 0.05
		local left = seconds
		while left > 1e-9 do
			local dt = math.min(step, left)
			left = left - dt
			W.advance(dt)
			for _, g in ipairs(S.groups) do
				if g.__playing then
					g.__elapsed = g.__elapsed + dt
					local d = IMPL.GetDuration(g)
					if g.__elapsed >= d then
						if g.__looping == "REPEAT" or g.__looping == "BOUNCE" then
							g.__elapsed = d > 0 and (g.__elapsed % d) or 0
							fire(g, "OnLoop")
						else
							g.__playing = false
							fire(g, "OnFinished")
						end
					end
				end
			end
			for _, o in ipairs(S.objects) do
				if o.__scripts.OnUpdate and visible(o) then fire(o, "OnUpdate", dt) end
			end
		end
	end

	S.fireEvent = W.fire

	-- Every object under `root` (children first-level order, depth first).
	function S.descendants(root, out)
		out = out or {}
		for _, c in ipairs(root.__children) do
			out[#out + 1] = c
			S.descendants(c, out)
		end
		return out
	end

	-- ── globals: the widget side only; the client itself is wowstub's ─────
	local function gone(name)
		return function() error("the interface must not call " .. name, 2) end
	end
	_G.CreateFrame = function(kind, name, parent, template)
		assert(FRAME_TYPES[kind], "CreateFrame: unexpected frame type " .. tostring(kind))
		if template ~= nil and not Stub.TEMPLATES[template] then
			error("CreateFrame: only BackdropTemplate is allowed in the interface, got " .. tostring(template), 2)
		end
		return new(kind, parent, name, template)
	end
	_G.UIParent = new("Frame", nil, "UIParent")
	UIParent.__w, UIParent.__h = 1920, 1080
	_G.Minimap = new("Minimap", UIParent, "Minimap")
	Minimap.__w, Minimap.__h, Minimap.__cx, Minimap.__cy = 140, 140, 1800, 900
	_G.GameTooltip = new("GameTooltip", UIParent, "GameTooltip")
	GameTooltip.__shown = false
	_G.UISpecialFrames = {}
	_G.AddonCompartmentFrame = {
		RegisterAddon = function(_, info) S.compartment[#S.compartment + 1] = info end,
	}
	_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	_G.GetCursorPosition = function() return S.cursor.x, S.cursor.y end
	_G.tinsert, _G.tremove = table.insert, table.remove
	_G.GetMouseFocus = nil -- gone from the retail client
	_G.SOUNDKIT = { READY_CHECK = 8960 }
	_G.C_Sound = { PlaySound = function(id) S.sounds[#S.sounds + 1] = id return true end }
	_G.SendChatMessage = gone("SendChatMessage (gone on 12.x; chat is the core's, from a click)")
	_G.UIDropDownMenu_Initialize = gone("UIDropDownMenu_Initialize")
	_G.UIDropDownMenu_CreateInfo = gone("UIDropDownMenu_CreateInfo")
	_G.EasyMenu = gone("EasyMenu")
	return S
end

return Stub
