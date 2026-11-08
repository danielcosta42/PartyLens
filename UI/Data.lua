--=============================================================================
-- UI.data: the only door between the pages and the core, built on specs/forever/ui-contract.md.
--
-- Pages read and act through these functions; nothing here reaches into a core module, only the PartyLens
-- methods and fields the contract names. Core settings are written with PartyLens:Set; listing fields with
-- SetListing. Every core event is forwarded to the UI's own bus (UI:Notify), which redraws the open page.
--
-- CLICK ONLY: D.Whisper, D.OpenWhisper, D.Invite, D.Who, D.StartListing, D.StopListing, D.PostLFG,
-- D.RequestLayer, D.Serve, D.ServeNext, D.Undo and D.AnnounceSummon forward straight to the core and must be
-- called directly from a button's OnClick (a hardware event), never from a timer, an event or an animation
-- callback. Nothing in this file defers one.
--=============================================================================
local _, ns = ...
local UI = ns.UI
local D = {}
UI.data = D
local L = UI.L

-- How long an entry lives without news (contract section 3): the scale of the freshness rings and the radar.
D.CHAT_TTL, D.NET_TTL = 30 * 60, 3 * 60
-- Each beacon asked for a layer gets 40 s before the next one is asked (section 6).
D.ASK_TTL = 40
-- In the beacon's group the game switches me by itself after about this long (its prompt does it at once).
D.SWITCH_WAIT = 300

local FILTER_DEFAULTS = {
	["roles.tank"] = false, ["roles.heal"] = false, ["roles.dps"] = false, type = "all", activityType = "all",
	activity = "", query = "", onlyOpen = true, hideSpam = true,
}
local EMPTY_FILTERS = {
	roles = {}, type = "all", activityType = "all", activity = "", query = "", onlyOpen = true, hideSpam = true,
}

local function Core()
	local pl = rawget(_G, "PartyLens")
	if type(pl) == "table" and pl.db then return pl end
end

function D.Ready() return Core() ~= nil end

-- A setting by dotted path ("filters.query", "roles.heal", "alertOnMatch").
function D.Get(path)
	local pl = Core()
	local t = pl and pl.db
	for part in tostring(path):gmatch("[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[part]
	end
	return t
end

function D.Set(path, value)
	local pl = Core()
	return pl and pl:Set(path, value) or false
end

--------------------------------------------------------------------------------
-- Radar (section 3)
--------------------------------------------------------------------------------
function D.Entries() local pl = Core() return pl and pl:GetEntries() or {} end
function D.Counts() local pl = Core() return pl and pl:GetCounts() or { total = 0, visible = 0, needsMe = 0 } end
function D.Age(e) return math.max(0, time() - (e.timestamp or time())) end
function D.MaxAge(e) return e.source == "net" and D.NET_TTL or D.CHAT_TTL end

-- Missing (lfm) or offered (lfg) roles as counts: the network's per-role comp when it has one, else 1 per role.
function D.RoleCounts(e)
	local out, c = {}, e.comp
	for _, role in ipairs({ "tank", "heal", "dps" }) do
		if c and e.type == "lfm" then
			local k = role:sub(1, 1)
			out[role] = math.max(0, (c[k .. "Max"] or 0) - (c[k] or 0))
		else
			out[role] = (e.roles and e.roles[role]) and 1 or 0
		end
	end
	return out
end

function D.Filters()
	local f = D.Get("filters")
	return type(f) == "table" and f or EMPTY_FILTERS
end
function D.SetFilter(key, value) return D.Set("filters." .. key, value) end
function D.ClearFilters()
	for key, value in pairs(FILTER_DEFAULTS) do D.SetFilter(key, value) end
end

function D.MyRoles()
	local r = D.Get("roles")
	return type(r) == "table" and r or {}
end
function D.SetRole(role, on) return D.Set("roles." .. role, on and true or false) end

function D.Blocked() local pl = Core() return pl and pl:GetBlocked() or {} end
function D.Block(e) local pl = Core() if pl then pl:Block(e) end end
function D.Unblock(key) local pl = Core() if pl then pl:Unblock(key) end end
function D.ClearBlocked() local pl = Core() if pl then pl:ClearBlocked() end end
function D.WhisperText(e) local pl = Core() return pl and pl:WhisperText(e) or "" end

-- Click only.
function D.Whisper(e) return Core():Whisper(e) end
function D.OpenWhisper(e) return Core():OpenWhisper(e) end
function D.Invite(e) return Core():Invite(e) end
function D.Who(e) return Core():Who(e) end

--------------------------------------------------------------------------------
-- Activities (section 4)
--------------------------------------------------------------------------------
function D.Activities() local pl = Core() return pl and pl:GetActivities() or {} end

-- "Wailing Caverns  17-24", "Ruins of Lordaeron (new)".
function D.ActivityLabel(a)
	if a.minLevel and a.maxLevel and a.minLevel ~= a.maxLevel then
		return string.format("%s  %d-%d", a.name, a.minLevel, a.maxLevel)
	end
	if a.minLevel then return string.format("%s  %d", a.name, a.minLevel) end
	if a.isNew then return string.format(L["%s (new)"], a.name) end
	return a.name
end

--------------------------------------------------------------------------------
-- Announce and Autopilot (section 5)
--------------------------------------------------------------------------------
function D.Listing() local pl = Core() return pl and pl:GetListing() end
function D.SetListing(fields) local pl = Core() if pl then pl:SetListing(fields) end end
function D.DefaultWant(key) local pl = Core() return pl and pl:DefaultWant(key) or { tank = 1, heal = 1, dps = 3 } end
function D.BuildPost() local pl = Core() return pl and pl:BuildPost() or "" end
function D.Suggestions() local pl = Core() return pl and pl:GetSuggestions() or {} end
function D.Dismiss(entry) local pl = Core() if pl then pl:DismissSuggestion(entry) end end

-- Click only.
function D.StartListing(fields) return Core():StartListing(fields) end
function D.StopListing() return Core():StopListing() end
function D.PostLFG() return Core():PostLFG() end

--------------------------------------------------------------------------------
-- Layer (section 6)
--------------------------------------------------------------------------------
function D.Layer() local pl = Core() return pl and pl:GetLayer() or { count = 0 } end
function D.Layers() local pl = Core() return pl and pl:GetLayers() or {} end
function D.MyRequest() local pl = Core() return pl and pl:GetMyLayerRequest() end
function D.CancelRequest() local pl = Core() if pl then pl:CancelLayerRequest() end end
function D.LayerRequests() local pl = Core() return pl and pl:GetLayerRequests() or {} end
function D.Decline(req) local pl = Core() if pl then pl:DeclineLayerRequest(req) end end
function D.CanUndo() local pl = Core() return pl and pl:CanUndoLayer() or false end
function D.Beacon()
	local pl = Core()
	return pl and pl:GetBeacon() or { on = false, available = false, hops = 0, today = 0, rank = 1, rankAt = 0, queue = 0 }
end
function D.SetBeacon(on) local pl = Core() if pl then pl:SetBeacon(on) end end

function D.OpenRequests()
	local n = 0
	for _, r in ipairs(D.LayerRequests()) do if r.state == "open" then n = n + 1 end end
	return n
end

-- Click only.
function D.RequestLayer(layer) return Core():RequestLayer(layer) end
function D.Serve(req) return Core():ServeLayerRequest(req) end
function D.ServeNext() return Core():ServeNextLayerRequest() end
function D.Undo() return Core():UndoLayerGroup() end

--------------------------------------------------------------------------------
-- Summon and network (sections 7 and 8)
--------------------------------------------------------------------------------
function D.Summon()
	local pl = Core()
	return pl and pl:GetSummon() or { inGroup = false, members = {}, needed = {}, warlocks = {} }
end
function D.MarkSummoned(name, on) local pl = Core() if pl then pl:MarkSummoned(name, on) end end
function D.Network() local pl = Core() return pl and pl:GetNetworkStatus() or { nodes = 0, buses = {} } end
function D.Peers() local pl = Core() return pl and pl:GetPeers() or {} end

-- Click only.
function D.AnnounceSummon(mode) return Core():AnnounceSummon(mode) end

--------------------------------------------------------------------------------
-- The header line and the reasons an action can fail, in words.
--------------------------------------------------------------------------------
-- The LFG channel the radar listens on, by its name in the client's language (nil when none is joined).
function D.LFGChannel() local pl = Core() return pl and pl:LFGChannel() end

function D.Status()
	local counts, channel = D.Counts(), D.LFGChannel()
	return { listening = channel ~= nil, channel = channel and channel.name, total = counts.total,
		needsMe = counts.needsMe, nodes = D.Network().nodes or 0 }
end

local REASONS = {
	empty = L["Nothing to send"], cannot_invite = L["Not the leader"], in_group = L["Already grouped"],
	throttled = L["Wait a moment"], cooldown = L["Wait a moment"], no_channel = L["Joining the channel"],
	same_layer = L["Same layer"], pending = L["One at a time"], no_beacon = L["No beacon now"],
	other_map = L["Other zone"], cannot_send = L["Can't send now"], group_full = L["Group full"],
	not_on_layer = L["You moved"], gone = L["Gone"], not_in_group = L["Not in a group"],
}
function D.Reason(code)
	return REASONS[code] or L["Didn't work"]
end

--------------------------------------------------------------------------------
-- Core events onto the UI's bus. The UI files load after Core.lua, so PartyLens exists here (contract
-- section 0); handlers only read and redraw, never act.
--------------------------------------------------------------------------------
local FORWARD = {
	READY = "ready", ENTRIES_CHANGED = "entries", ENTRY_ADDED = "entry", LISTING_CHANGED = "listing",
	SUGGESTIONS_CHANGED = "suggestions", LAYER_CHANGED = "layer", LAYER_NODES_CHANGED = "layer",
	LAYER_REQUEST_RECEIVED = "layerRequest", LAYER_REQUESTS_CHANGED = "layer", SUMMON_CHANGED = "summon",
	ROSTER_CHANGED = "roster", NETWORK_CHANGED = "network", SETTINGS_CHANGED = "settings", NOTICE = "notice",
	LFG_CHANNEL_CHANGED = "channel", BEACON_CHANGED = "layer", BEACON_SERVED = "beaconServed",
}

local core = rawget(_G, "PartyLens")
if type(core) == "table" and type(core.On) == "function" then
	for event, what in pairs(FORWARD) do
		core:On(event, function(...) UI:Notify(what, ...) end)
	end
end
