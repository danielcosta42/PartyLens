local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Messaging = _G[ADDON_NAME .. "_Messaging"]
local Comm = _G[ADDON_NAME .. "_Comm"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- My announce: the draft lives in db.listing, the active state only for the session (after a reload nothing
-- is broadcast until the player starts it again). Active, it goes on the network at once, on every change and
-- every HEARTBEAT seconds; the visible LFG post is a separate click.
local Listing = {}

Listing.HEARTBEAT = 60
-- An unchanged listing gets a new version this often: receivers drop a seq older than Comm.SEEN_TTL.
Listing.REFRESH = 5 * 60
Listing.POST_COOLDOWN = 15

local function RT(partyLens)
    partyLens.listingState = partyLens.listingState or { active = false, seq = 0 }
    return partyLens.listingState
end

local function Copy(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[k] = v
    end
    return out
end

function Listing.State(partyLens)
    local db = partyLens.db.listing
    local rt = RT(partyLens)
    local act = Activity.Get(db.activity)
    local want = {}
    for _, role in ipairs(Needs.ROLES) do
        want[role] = math.max(0, math.floor(tonumber(db.want[role]) or 0))
    end
    local have = Roster.Have(partyLens.db)
    local missing = {}
    for _, role in ipairs(Needs.ROLES) do
        missing[role] = math.max(0, want[role] - have[role])
    end
    local layer = Layer.Current(partyLens)
    local label = Utils.Trim(db.label)
    return {
        active = rt.active,
        type = db.type,
        activity = act and act.key or "",
        label = label,
        name = act and act.name or (label ~= "" and label) or L("ACTIVITY_ANY"),
        activityType = act and act.type or (label ~= "" and "quest" or "other"),
        want = want, have = have, missing = missing,
        size = want.tank + want.heal + want.dps,
        roles = Copy(partyLens.db.roles),
        comment = db.comment,
        startedAt = rt.startedAt, lastSent = rt.lastSent, lastPost = rt.lastPost, seq = rt.seq,
        mapID = layer.mapID, zoneUID = layer.zoneUID,
    }
end

local function Changed(partyLens)
    partyLens:Fire("LISTING_CHANGED", Listing.State(partyLens))
end

local function Publish(partyLens, kind)
    local rt = RT(partyLens)
    local payload = Comm.Build(Listing.State(partyLens), kind)
    if Comm.Send(payload) then
        rt.lastSent = time()
    end
    return payload
end

-- A change (not a heartbeat) also goes straight to a few PartyLens peers (Board).
local function Push(partyLens, payload, off)
    local Board = _G[ADDON_NAME .. "_Board"]
    if Board then
        Board.Push(partyLens, payload, off)
    end
end

local function Signature(state)
    return Needs.Encode(Needs.FromCounts(state.missing)) .. state.have.tank .. state.have.heal .. state.have.dps
end

-- The server clock at the change: it survives a reload (a receiver ignores anything below the last it saw from
-- me) and every receiver can tell a stale or made-up one from it.
local function Bump(rt)
    rt.seq = math.max(rt.seq + 1, GetServerTime())
end

function Listing.Set(partyLens, fields)
    local db = partyLens.db.listing
    fields = fields or {}
    if fields.type == "lfm" or fields.type == "lfg" then
        db.type = fields.type
    end
    if fields.activity ~= nil then
        db.activity = Activity.Get(fields.activity) and fields.activity or ""
    end
    if fields.label ~= nil then
        db.label = Comm.Clean(fields.label, 60)
    end
    if type(fields.want) == "table" then
        for _, role in ipairs(Needs.ROLES) do
            local n = tonumber(fields.want[role])
            if n then
                db.want[role] = math.max(0, math.min(40, math.floor(n)))
            end
        end
    end
    if fields.comment ~= nil then
        db.comment = Comm.Clean(fields.comment, Comm.COMMENT_MAX)
    end
    local rt = RT(partyLens)
    if rt.active then
        Bump(rt)
        Push(partyLens, Publish(partyLens))
    end
    Changed(partyLens)
end

function Listing.Start(partyLens, fields)
    local rt = RT(partyLens)
    rt.active = true
    rt.startedAt = rt.startedAt or time()
    Listing.Set(partyLens, fields)
    rt.signature = Signature(Listing.State(partyLens))
    if rt.ticker then
        rt.ticker:Cancel()
    end
    rt.ticker = C_Timer.NewTicker(Listing.HEARTBEAT, function()
        if GetServerTime() - rt.seq >= Listing.REFRESH then
            Bump(rt)
        end
        Publish(partyLens)
    end)
end

function Listing.Stop(partyLens)
    local rt = RT(partyLens)
    if not rt.active then
        return
    end
    rt.active, rt.startedAt = false, nil
    if rt.ticker then
        rt.ticker:Cancel()
        rt.ticker = nil
    end
    Bump(rt)
    Push(partyLens, Publish(partyLens, "off"), true)
    Changed(partyLens)
end

-- The group changed: what an lfm still needs changed with it.
function Listing.OnRoster(partyLens)
    local rt = RT(partyLens)
    if not rt.active then
        return
    end
    local state = Listing.State(partyLens)
    local signature = Signature(state)
    if signature ~= rt.signature then
        rt.signature = signature
        if state.type == "lfm" then
            Bump(rt)
            Publish(partyLens)
        end
        Changed(partyLens)
    end
end

function Listing.PostText(partyLens)
    local s = Listing.State(partyLens)
    local roles = (s.type == "lfm") and Needs.FromCounts(s.missing) or s.roles
    local level = UnitLevel("player")
    return Messaging.PostText(s.type, s.name, roles, Utils.IsSecret(level) and 0 or level, s.comment)
end

-- Click only: a visible line in the LookingForGroup channel, plus the network listing.
function Listing.Post(partyLens)
    local rt = RT(partyLens)
    if rt.lastPost and (time() - rt.lastPost) < Listing.POST_COOLDOWN then
        partyLens:Notice(L("NOTICE_POST_COOLDOWN"))
        return false, "cooldown"
    end
    local text = Listing.PostText(partyLens)
    if text == "" then
        return false, "empty"
    end
    local channel = Messaging.LFGChannel(partyLens, true)
    if not channel then
        partyLens:Notice(L("LFG_JOIN_ATTEMPT"))
        return false, "no_channel"
    end
    Utils.SendChat(text, "CHANNEL", channel)
    rt.lastPost = time()
    if rt.active then
        Publish(partyLens)
        Changed(partyLens)
    else
        Listing.Start(partyLens)
    end
    return true
end

function Listing.IsActive(partyLens)
    return RT(partyLens).active
end

_G[ADDON_NAME .. "_Listing"] = Listing
return Listing
