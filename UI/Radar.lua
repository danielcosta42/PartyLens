--=============================================================================
-- The radar: the one bold element (plan.md §5). Concentric rings, an amber sweep turning once every 4 s and a
-- blip per group. A blip lights up when the sweep passes over it and dims behind it, the way a radar screen
-- keeps an afterglow; a new group pops in with a halo. With animations off the sweep stands still at twelve
-- o'clock and every blip is simply lit.
--
--   local radar = UI.Kit.Radar(parent, 160)
--   radar:SetBlips({ { id = "g1", angle = 0.1, radius = 0.4, color = UI.T.amber }, ... })
--     angle: 0..1 clockwise from twelve o'clock; radius: 0 (centre) .. 1 (outer ring)
--   radar:Pop("g1")                      -- the blip for g1 grows in with a halo
--   radar:SetSectors({ { corner = "TOPRIGHT", label = "Dungeons" }, ... })
--=============================================================================
local _, ns = ...
local UI = ns.UI
local T, M, Kit = UI.T, UI.Motion, UI.Kit

local TAU = 2 * math.pi
local DIM, LIT, STILL = 0.45, 1, 0.9
local BLIP = 13

local function crossed(prev, cur, a)
	if prev <= cur then return a > prev and a <= cur end
	return a > prev or a <= cur -- the sweep wrapped past twelve o'clock
end

local function NewBlip(r)
	local b = CreateFrame("Frame", nil, r.field)
	b:SetSize(BLIP, BLIP)
	b.dot = UI.Tex(b, "blip", BLIP, T.amber, 1, "ARTWORK")
	b.dot:SetPoint("CENTER")
	b.halo = UI.Tex(b, "ring", 12, T.amber, 1, "OVERLAY")
	b.halo:SetPoint("CENTER")
	b.halo:Hide()
	-- The afterglow: lit as the sweep passes, then dimming until the next turn.
	b.glow = M.Group(b.dot, "glow", function(g)
		local a = M.Anim(g, "Alpha", M.SWEEP * 0.65, 1, "OUT")
		a:SetFromAlpha(LIT)
		a:SetToAlpha(DIM)
	end)
	return b
end

function Kit.Radar(parent, size)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(size, size)
	r.size, r.reach = size, size / 2 - BLIP / 2 - 2
	r.disc = UI.Tex(r, "dot", size - 4, T.well, 1, "BACKGROUND")
	r.disc:SetPoint("CENTER")
	r.grid = UI.Tex(r, "radar-grid", size, T.lineHi, 1, "BORDER")
	r.grid:SetPoint("CENTER")
	r.sweep = UI.Tex(r, "radar-sweep", size, T.amber, 0.9, "ARTWORK")
	r.sweep:SetPoint("CENTER")
	r.field = CreateFrame("Frame", nil, r)
	r.field:SetAllPoints()
	r.hub = UI.Tex(r.field, "dot", 5, T.amber, 1, "OVERLAY")
	r.hub:SetPoint("CENTER")
	r.pool, r.byId, r.list, r.sectors = {}, {}, {}, {}

	r.spin = M.Group(r.sweep, "sweep", function(g)
		local turn = M.Anim(g, "Rotation", M.SWEEP, 1)
		turn:SetDegrees(-360) -- negative: clockwise
		turn:SetOrigin("CENTER", 0, 0)
		g:SetLooping("REPEAT")
	end)

	-- Where the sweep's leading edge is now, 0..1 clockwise from twelve o'clock.
	function r:SweepAt()
		return self.spin:GetProgress() % 1
	end

	local function follow(self)
		local cur = self:SweepAt()
		local prev = self.prevAt or cur
		self.prevAt = cur
		for _, b in ipairs(self.list) do
			if b:IsShown() and crossed(prev, cur, b.angle) then b.glow:Play() end
		end
	end

	-- Motion on: the sweep turns and blips follow it. Off: everything still, every blip lit.
	function r:Apply()
		if M.On() then
			if not self.spin:IsPlaying() then
				self.spin:Play()
				self.prevAt = nil
			end
			self:SetScript("OnUpdate", follow)
			for _, b in ipairs(self.list) do b.dot:SetAlpha(DIM) end
		else
			self.spin:Stop()
			self.sweep:SetRotation(0)
			self:SetScript("OnUpdate", nil)
			for _, b in ipairs(self.list) do
				b.glow:Stop()
				b.dot:SetAlpha(STILL)
			end
		end
	end

	function r:SetBlips(blips)
		wipe(self.byId)
		wipe(self.list)
		for i, data in ipairs(blips or {}) do
			local b = self.pool[i] or NewBlip(self)
			self.pool[i] = b
			b.id, b.angle = data.id, (data.angle or 0) % 1
			local radius = math.max(0, math.min(1, data.radius or 0.5)) * self.reach
			b:ClearAllPoints()
			b:SetPoint("CENTER", self, "CENTER", math.sin(b.angle * TAU) * radius, math.cos(b.angle * TAU) * radius)
			local c = data.color or T.amber
			UI.Paint(b.dot, c)
			UI.Paint(b.halo, c)
			b.dot:SetAlpha(M.On() and DIM or STILL)
			b:Show()
			self.byId[b.id] = b
			self.list[#self.list + 1] = b
		end
		for i = #self.list + 1, #self.pool do
			self.pool[i].glow:Stop()
			self.pool[i]:Hide()
		end
	end

	function r:Pop(id)
		local b = self.byId[id]
		if not b then return end
		M.Pop(b, 0.35, 0.05)
		M.Ripple(b.halo, 3.2, 0.8)
		if M.On() then b.glow:Play() end
	end

	function r:SetSectors(list)
		for _, fs in ipairs(self.sectors) do fs:Hide() end
		for i, s in ipairs(list or {}) do
			local fs = self.sectors[i] or UI.Text(self, "data", 11, T.faint)
			self.sectors[i] = fs
			fs:ClearAllPoints()
			fs:SetPoint(s.corner, self, s.corner, 0, 0)
			fs:SetJustifyH(s.corner:find("RIGHT") and "RIGHT" or "LEFT")
			fs:SetText(s.label)
			fs:Show()
		end
	end

	r:SetScript("OnShow", function(self) self:Apply() end)
	r:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	UI:OnSetting("animations", function() r:Apply() end)
	r:Apply()
	return r
end
