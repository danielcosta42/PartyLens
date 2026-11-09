local ADDON_NAME = ...

local function Mod(name)
    return _G[ADDON_NAME .. "_" .. name] or error("Module not loaded: " .. name)
end

local Utils = Mod("Utils")
local Localization = Mod("Localization")
local Activity = Mod("Activity")
local Database = Mod("Database")
local Entry = Mod("Entry")
local Chat = Mod("Chat")
local Messaging = Mod("Messaging")
local Summon = Mod("Summon")
local Net = Mod("Net")
local Comm = Mod("Comm")
local Who = Mod("Who")
local Layer = Mod("Layer")
local LayerNet = Mod("LayerNet")
local LayerWatch = Mod("LayerWatch")
local Listing = Mod("Listing")
local Board = Mod("Board")
local Autopilot = Mod("Autopilot")
local Search = Mod("Search")

local L = Localization.L

-- The addon object: an event bus and the facade the UI is built on (specs/forever/ui-contract.md). The core
-- never touches the UI's internals; it calls PartyLens.UI:Toggle() and :Open(page, context) when a UI exists.
local PartyLens = {}
_G.PartyLens = PartyLens
PartyLens.API = Mod("API")
PartyLens.L = Localization.T
PartyLens.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

_G.BINDING_HEADER_PARTYLENS = "PartyLens"
_G.BINDING_NAME_PARTYLENS_TOGGLE = L("BINDING_TOGGLE")
_G.BINDING_NAME_PARTYLENS_SERVE = L("BINDING_SERVE")

-- ---------------------------------------------------------------------------
-- Event bus
-- ---------------------------------------------------------------------------
local handlers = {}

function PartyLens:On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

function PartyLens:Off(event, fn)
    for i, h in ipairs(handlers[event] or {}) do
        if h == fn then
            table.remove(handlers[event], i)
            return
        end
    end
end

-- One handler's error never stops the others, nor the core path that fired.
function PartyLens:Fire(event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for _, fn in ipairs({ unpack(list) }) do
        local ok, err = pcall(fn, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

function PartyLens:Notice(text)
    self:Fire("NOTICE", text)
    if not self.UI then
        Utils.Print(text)
    end
end

-- HELLOs arrive in bursts: one NETWORK_CHANGED a second at most.
function PartyLens:NetworkChanged()
    if self.netPending then
        return
    end
    self.netPending = true
    C_Timer.After(1, function()
        self.netPending = false
        self:Fire("NETWORK_CHANGED")
    end)
end

function PartyLens:IsReady()
    return self.db ~= nil
end

function PartyLens:Toggle()
    if self.UI and self.UI.Toggle then
        self.UI:Toggle()
    else
        Utils.Print(L("HELP"))
    end
end

function PartyLens:Open(pageKey, context)
    if self.UI and self.UI.Open then
        self.UI:Open(pageKey, context)
    end
end

function PartyLens:AddStrings(locale, strings)
    Localization.Add(locale, strings)
end

-- Keys with their own calls (SetListing, Block, ...), never written through Set.
local OWN_API = { listing = true, blacklist = true, alertDismissed = true, schemaVersion = true, beacon = true,
    meshPeers = true }

-- A dotted path into db for a key that exists, with a value of the same type.
function PartyLens:Set(path, value)
    local t = self.db
    local parts = {}
    for part in tostring(path):gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end
    for i = 1, #parts - 1 do
        t = type(t) == "table" and t[parts[i]] or nil
    end
    local leaf = parts[#parts]
    if OWN_API[parts[1]] or type(t) ~= "table" or t[leaf] == nil or type(t[leaf]) ~= type(value)
        or type(value) == "table" then
        return false
    end
    t[leaf] = value
    self:Fire("SETTINGS_CHANGED", path, value)
    if parts[1] == "roles" or parts[1] == "filters" then
        self:Fire("ENTRIES_CHANGED")
        Autopilot.Check(self)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Radar
-- ---------------------------------------------------------------------------
function PartyLens:GetEntries()
    return Search.Entries(self)
end

function PartyLens:GetCounts()
    return Search.Counts(self)
end

local function Contacted(self, entry, kind)
    entry.contacted = kind
    self:Fire("ENTRIES_CHANGED")
    Autopilot.Check(self)
end

function PartyLens:WhisperText(entry)
    return Messaging.BuildWhisper(self, entry)
end

function PartyLens:Whisper(entry)
    local ok, why = Messaging.SendWhisper(self, entry)
    if ok then
        Contacted(self, entry, "whisper")
    end
    return ok, why
end

function PartyLens:OpenWhisper(entry)
    return Messaging.OpenWhisper(self, entry)
end

function PartyLens:Invite(entry)
    local ok, why = Messaging.Invite(self, entry.name)
    if ok then
        Contacted(self, entry, "invite")
    end
    return ok, why
end

function PartyLens:Who(entry)
    local ok, why = Who.Lookup(self, entry.name)
    if why == "throttled" then
        self:Notice(L("NOTICE_WHO_THROTTLED"))
    end
    return ok, why
end

function PartyLens:Block(entry)
    if entry and entry.key then
        self.db.blacklist[entry.key] = entry.name or entry.key
        self:Notice(L("NOTICE_BLOCKED", entry.name or entry.key))
        self:Fire("ENTRIES_CHANGED")
        Autopilot.Check(self)
    end
end

function PartyLens:Unblock(key)
    if self.db.blacklist[key] then
        self.db.blacklist[key] = nil
        self:Fire("ENTRIES_CHANGED")
    end
end

function PartyLens:GetBlocked()
    local out = {}
    for key, name in pairs(self.db.blacklist) do
        out[#out + 1] = { key = key, name = name }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function PartyLens:ClearBlocked()
    wipe(self.db.blacklist)
    self:Fire("ENTRIES_CHANGED")
end

function PartyLens:ClassColor(classFile)
    return Utils.ClassColor(classFile)
end

function PartyLens:LFGChannel()
    local c = self.lfgChannel
    return c and { id = c.id, name = c.name } or nil
end

-- ---------------------------------------------------------------------------
-- Activities, announce, autopilot
-- ---------------------------------------------------------------------------
function PartyLens:GetActivities()
    return Activity.Sorted()
end

function PartyLens:GetActivity(key)
    for _, a in ipairs(Activity.Sorted()) do
        if a.key == key then
            return a
        end
    end
end

function PartyLens:DefaultWant(key)
    return Activity.DefaultWant(key)
end

function PartyLens:GetListing()
    return Listing.State(self)
end

function PartyLens:SetListing(fields)
    Listing.Set(self, fields)
end

function PartyLens:StartListing(fields)
    Listing.Start(self, fields)
end

function PartyLens:StopListing()
    Listing.Stop(self)
end

function PartyLens:BuildPost()
    return Listing.PostText(self)
end

function PartyLens:PostLFG()
    return Listing.Post(self)
end

function PartyLens:GetSuggestions()
    return Autopilot.Suggestions(self)
end

function PartyLens:DismissSuggestion(entry)
    Autopilot.Dismiss(self, entry)
end

-- ---------------------------------------------------------------------------
-- Layer, summon, network
-- ---------------------------------------------------------------------------
function PartyLens:GetLayer()
    return Layer.Current(self)
end

function PartyLens:GetLayerNodes()
    return LayerNet.Nodes(self)
end

function PartyLens:GetLayers()
    return LayerWatch.Layers(self)
end

function PartyLens:RequestLayer(layer)
    return LayerNet.RequestLayer(self, layer)
end

function PartyLens:GetBeacon()
    return LayerNet.BeaconStatus(self)
end

function PartyLens:SetBeacon(on)
    LayerNet.SetBeacon(self, on)
end

function PartyLens:ServeNextLayerRequest()
    return LayerNet.ServeNext(self)
end

function PartyLens:GetMyLayerRequest()
    return LayerNet.MyRequest(self)
end

function PartyLens:CancelLayerRequest()
    LayerNet.Cancel(self)
end

function PartyLens:GetLayerRequests()
    return LayerNet.Inbound(self)
end

function PartyLens:ServeLayerRequest(req)
    return LayerNet.Serve(self, req)
end

function PartyLens:DeclineLayerRequest(req)
    LayerNet.Decline(self, req)
end

function PartyLens:CanUndoLayer()
    return LayerNet.CanUndo(self)
end

function PartyLens:UndoLayerGroup()
    return LayerNet.Undo(self)
end

function PartyLens:GetSummon()
    return Summon.Snapshot(self)
end

function PartyLens:MarkSummoned(name, summoned)
    Summon.Mark(self, name, summoned)
end

function PartyLens:AnnounceSummon(mode)
    return Summon.Announce(self, mode)
end

local function Peers()
    local CN = _G.ChehulNet
    local out, now = {}, time()
    for name, p in pairs((CN and CN.peers) or {}) do
        if now - (p.ts or 0) <= ((CN and CN.PEER_TTL) or 600) then
            out[#out + 1] = { name = name, addons = p.addons or {}, classFile = p.class, level = p.level,
                mapID = p.mapID, zoneUID = p.zoneUID, ago = now - (p.ts or now) }
        end
    end
    table.sort(out, function(a, b) return a.ago < b.ago end)
    return out
end

function PartyLens:GetPeers()
    return Peers()
end

function PartyLens:GetNetworkStatus()
    local status = Net.Status()
    local peers = Peers()
    local pl = 0
    for _, p in ipairs(peers) do
        if p.addons.pl then
            pl = pl + 1
        end
    end
    status.nodes, status.plNodes = #peers, math.max(pl, Board.PeerCount(self))
    status.listingsHeard = Comm.HeardCount(self)
    status.layerNodes = LayerNet.NodeCount(self)
    status.cnVersion = (_G.ChehulNet and _G.ChehulNet.version) or 0
    return status
end

-- ---------------------------------------------------------------------------
-- Game events. Each handler drops its event when an argument it reads is secret.
-- ---------------------------------------------------------------------------
local function JoinLFGLater(self)
    if self.db.joinLFGChannel and not self.lfgJoinTried then
        self.lfgJoinTried = true
        -- The game joins its own channels first after a load screen; a join before them is lost.
        C_Timer.After(10, function() Messaging.LFGChannel(self, true) end)
    end
end

function PartyLens:OnLoad()
    Database.EnsureDB(self)
    Net.Register(Comm.PREFIX, function(payload, sender, dist) Comm.OnMessage(self, payload, sender, dist) end)
    Net.Register(LayerNet.PREFIX, function(payload, sender, dist)
        LayerNet.OnMessage(self, payload, sender, dist)
    end)
    self:On("LISTING_CHANGED", function(state) Autopilot.OnListing(self, state) end)
    self:On("ENTRY_ADDED", function() Autopilot.Check(self) end)
    self:On("LAYER_CHANGED", function(cur) LayerNet.OnLayerChanged(self, cur) end)
    C_Timer.NewTicker(30, function()
        Entry.Prune(self)
        Comm.Prune(self)
        Who.Prune(self)
        Chat.RefreshLFGChannel(self)
        LayerNet.Prune(self)
        Layer.Prune(self)
        LayerWatch.Watch(self)
        Board.Prune(self)
    end)
    C_Timer.After(Board.SYNC_FIRST, function() Board.Sync(self) end)
    C_Timer.NewTicker(Board.SYNC_INTERVAL, function() Board.Sync(self) end)
    C_Timer.NewTicker(LayerNet.PRESENCE_INTERVAL, function() LayerNet.SendPresence(self) end)

    _G.SLASH_PARTYLENS1 = "/partylens"
    _G.SLASH_PARTYLENS2 = "/pl"
    SlashCmdList.PARTYLENS = function(msg)
        local cmd = Utils.IsSecret(msg) and "" or Utils.SafeLower(Utils.Trim(msg))
        if cmd == "announce" or cmd == "layer" then
            self:Open(cmd)
        elseif cmd == "help" then
            Utils.Print(L("HELP"))
        else
            self:Toggle()
        end
    end

    self:Fire("READY")
    Utils.Print(L("LOADED"))
end

local EVENTS = {
    ADDON_LOADED = function(self, name)
        if name == ADDON_NAME then
            self:OnLoad()
        end
    end,
    PLAYER_ENTERING_WORLD = function(self)
        Chat.RefreshLFGChannel(self)
        JoinLFGLater(self)
        self:Fire("LAYER_CHANGED", Layer.Current(self))
    end,
    ZONE_CHANGED_NEW_AREA = function(self)
        self:Fire("LAYER_CHANGED", Layer.Current(self))
    end,
    CHAT_MSG_CHANNEL = function(self, ...)
        Chat.HandleChatMessage(self, ...)
    end,
    -- Joined, left, renumbered: its payload is not read, so a secret one does no harm.
    CHANNEL_UI_UPDATE = function(self)
        Chat.RefreshLFGChannel(self)
    end,
    CHAT_MSG_CHANNEL_NOTICE = function(self)
        Chat.RefreshLFGChannel(self)
    end,
    PLAYER_TARGET_CHANGED = function(self)
        Layer.Observe(self, "target")
    end,
    UPDATE_MOUSEOVER_UNIT = function(self)
        Layer.Observe(self, "mouseover")
    end,
    NAME_PLATE_UNIT_ADDED = function(self, unit)
        Layer.Observe(self, unit)
    end,
    GROUP_ROSTER_UPDATE = function(self)
        if not IsInGroup() then
            self.summonMarked = nil
        end
        Listing.OnRoster(self)
        LayerNet.OnRoster(self)
        self:Fire("ROSTER_CHANGED")
        self:Fire("SUMMON_CHANGED")
    end,
    WHO_LIST_UPDATE = function(self)
        Who.OnWhoList(self)
    end,
    -- Beacon duty: away, combat. Their payloads are not read.
    PLAYER_FLAGS_CHANGED = function(self)
        LayerNet.CheckDuty(self)
    end,
    PLAYER_REGEN_DISABLED = function(self)
        LayerNet.CheckDuty(self)
    end,
    PLAYER_REGEN_ENABLED = function(self)
        LayerNet.CheckDuty(self)
    end,
}

local frame = CreateFrame("Frame")
PartyLens.eventFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and not PartyLens.db then
        return
    end
    EVENTS[event](PartyLens, ...)
end)
for event in pairs(EVENTS) do
    frame:RegisterEvent(event)
end
