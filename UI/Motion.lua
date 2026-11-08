--=============================================================================
-- Motion: every animation in the interface goes through here.
--
-- One AnimationGroup per (region, purpose), created on first use and reused. Each helper sets the end state on
-- the region itself and plays the group only when the `animations` setting is on; when it is off, the same end
-- state lands at once and nothing plays. Transforms never persist past a group (WoW drops them when it ends), so
-- anything that moves is anchored at its start offset and re-anchored at its final place when the group ends.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local M = {}
UI.Motion = M

-- Durations from plan.md §5.
M.PAGE, M.PRESS, M.ENTER, M.EDGE, M.TOAST, M.SWEEP, M.SLIDE = 0.15, 0.08, 0.25, 2.0, 0.25, 4.0, 0.18

local groups = setmetatable({}, { __mode = "k" }) -- every group made, to stop them all at once

function M.On()
	return UI:Setting("animations") ~= false
end

-- `pending` marks a group that started and has not finished: the game stops a group without OnFinished when
-- its region is hidden, so a hidden window settles those itself (M.SettleAll).
local function Done(g) g.pending = false end

function M.Group(region, key, build)
	region.motion = region.motion or {}
	local g = region.motion[key]
	if not g then
		g = region:CreateAnimationGroup()
		groups[g] = true
		build(g, region)
		g.region = region
		g:HookScript("OnFinished", Done)
		region.motion[key] = g
	end
	return g
end

function M.Anim(g, kind, duration, order, smoothing)
	local a = g:CreateAnimation(kind)
	a:SetDuration(duration)
	a:SetOrder(order or 1)
	if smoothing then a:SetSmoothing(smoothing) end
	return a
end

-- Plays `g` when motion is on. Off: stops it and runs `finish` (the group's end state) right away.
function M.Play(g, finish, reverse, offset)
	g:Stop()
	if M.On() then
		g.pending = true
		g:Play(reverse or false, offset or 0)
		return true
	end
	g.pending = false
	if finish then finish() end
	return false
end

-- Stops a motion the caller takes over (it sets the state itself).
function M.Stop(region, key)
	local g = region.motion and region.motion[key]
	if g then
		g:Stop()
		g.pending = false
	end
end

-- Stops a motion and lands its end state at once (a page that must be gone now).
function M.Settle(region, key)
	local g = region.motion and region.motion[key]
	if g and g.pending then
		g:Stop()
		g.pending = false
		if g.finish then g.finish() end
	end
end

local function Under(region, root)
	while region do
		if region == root then return true end
		region = region:GetParent()
	end
	return false
end

-- Every motion under `root` that started and did not finish lands on its end state (the window closed
-- mid-motion: a page fading out is hidden, a card that was sliding is in place).
function M.SettleAll(root)
	for g in pairs(groups) do
		if g.pending and g.finish and g.region and Under(g.region, root) then
			g:Stop()
			g.pending = false
			g.finish()
		end
	end
end

-- The setting went off: freeze everything where its end state is.
function M.StopAll()
	for g in pairs(groups) do
		if g:IsPlaying() or g.pending then
			g:Stop()
			g.pending = false
			local done = g.finish
			if done then done() end
		end
	end
end

--------------------------------------------------------------------------------
-- Fade a region to `to`; shows it first, and hides it at the end when `hide` is set.
--------------------------------------------------------------------------------
function M.Fade(region, to, duration, hide)
	local g = M.Group(region, "fade", function(group)
		group.alpha = M.Anim(group, "Alpha", duration or M.PAGE, 1, "IN_OUT")
		group:SetToFinalAlpha(true)
		group.finish = function()
			region:SetAlpha(group.to)
			if group.hide then region:Hide() end
		end
		group:SetScript("OnFinished", group.finish)
	end)
	local from = region:IsShown() and region:GetAlpha() or 0
	g.to, g.hide = to, hide
	g:Stop()
	g.pending = false
	region:Show()
	if from == to then
		g.finish()
		return
	end
	g.alpha:SetFromAlpha(from)
	g.alpha:SetToAlpha(to)
	g.alpha:SetDuration(duration or M.PAGE)
	region:SetAlpha(to)
	M.Play(g, g.finish)
end

--------------------------------------------------------------------------------
-- Move a region into place from (dx, dy) away. `place(region, ox, oy)` anchors it with an extra offset;
-- it is called with (dx, dy) to start and with (0, 0) at the end. `fade` also fades it in from 0.
--------------------------------------------------------------------------------
function M.Slide(region, place, dx, dy, duration, fade, smoothing)
	local g = M.Group(region, "slide", function(group)
		group.move = M.Anim(group, "Translation", M.ENTER, 1, smoothing or "OUT")
		group.alpha = M.Anim(group, "Alpha", M.ENTER, 1, "OUT")
		group.finish = function()
			if group.place then group.place(region, 0, 0) end
			region:SetAlpha(1)
		end
		group:SetScript("OnFinished", group.finish)
	end)
	g:Stop()
	g.pending = false
	g.place = place
	if (dx == 0 and dy == 0 and not fade) or not M.On() then
		g.finish()
		return
	end
	place(region, dx, dy)
	g.move:SetOffset(-dx, -dy)
	g.move:SetDuration(duration or M.ENTER)
	g.alpha:SetFromAlpha(fade and 0 or 1)
	g.alpha:SetToAlpha(1)
	g.alpha:SetDuration(duration or M.ENTER)
	region:SetAlpha(1)
	M.Play(g, g.finish)
end

--------------------------------------------------------------------------------
-- Press: 0.96 for 0.08 s and back. The second step scales by the reciprocal: scale steps in one group compose.
--------------------------------------------------------------------------------
function M.Press(region)
	local g = M.Group(region, "press", function(group)
		local down = M.Anim(group, "Scale", M.PRESS, 1, "OUT")
		down:SetScaleFrom(1, 1)
		down:SetScaleTo(0.96, 0.96)
		down:SetOrigin("CENTER", 0, 0)
		local up = M.Anim(group, "Scale", M.PRESS, 2, "IN")
		up:SetScaleFrom(1, 1)
		up:SetScaleTo(1 / 0.96, 1 / 0.96)
		up:SetOrigin("CENTER", 0, 0)
	end)
	M.Play(g)
end

-- Pulse once: grows by `amount` and settles back (a role pip that needs you, a blip that was served).
function M.Pulse(region, amount, duration)
	amount = amount or 1.4
	local g = M.Group(region, "pulse", function(group)
		group.grow = M.Anim(group, "Scale", (duration or 0.4) / 2, 1, "OUT")
		group.grow:SetScaleFrom(1, 1)
		group.grow:SetOrigin("CENTER", 0, 0)
		group.back = M.Anim(group, "Scale", (duration or 0.4) / 2, 2, "IN_OUT")
		group.back:SetScaleFrom(1, 1)
		group.back:SetOrigin("CENTER", 0, 0)
	end)
	g.grow:SetScaleTo(amount, amount)
	g.back:SetScaleTo(1 / amount, 1 / amount)
	M.Play(g)
end

-- Grow in from almost nothing (a blip appearing, a check mark landing).
function M.Pop(region, duration, from)
	local g = M.Group(region, "pop", function(group)
		group.scale = M.Anim(group, "Scale", duration or 0.3, 1, "OUT")
		group.scale:SetOrigin("CENTER", 0, 0)
		group.scale:SetScaleTo(1, 1)
	end)
	g.scale:SetScaleFrom(from or 0.05, from or 0.05)
	g.scale:SetDuration(duration or 0.3)
	M.Play(g)
end

-- A texture that flashes to `peak` and fades out over `duration` (the green "sent", the amber "new" edge).
-- It ends invisible either way: off, nothing shows.
function M.Flash(region, peak, duration)
	local g = M.Group(region, "flash", function(group)
		group.alpha = M.Anim(group, "Alpha", duration or 0.5, 1, "IN")
		group.alpha:SetToAlpha(0)
		group.finish = function() region:SetAlpha(0) end
		group:SetScript("OnFinished", group.finish)
	end)
	g.alpha:SetFromAlpha(peak or 0.7)
	g.alpha:SetDuration(duration or 0.5)
	region:SetAlpha(0)
	region:Show()
	M.Play(g, g.finish)
end

-- Expanding ring that fades (the halo of a blip popping in, a served layer).
function M.Ripple(region, grow, duration)
	local g = M.Group(region, "ripple", function(group)
		group.scale = M.Anim(group, "Scale", duration or 0.8, 1, "OUT")
		group.scale:SetScaleFrom(1, 1)
		group.scale:SetOrigin("CENTER", 0, 0)
		group.alpha = M.Anim(group, "Alpha", duration or 0.8, 1, "OUT")
		group.alpha:SetFromAlpha(0.9)
		group.alpha:SetToAlpha(0)
		group.finish = function() region:Hide() end
		group:SetScript("OnFinished", group.finish)
	end)
	g.scale:SetScaleTo(grow or 3, grow or 3)
	region:SetAlpha(1)
	region:Show()
	M.Play(g, g.finish)
end
