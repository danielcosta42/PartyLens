local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Listing = _G[ADDON_NAME .. "_Listing"]

-- Suggestions only. With a listing active it ranks the radar: for an lfm, players looking for a group who fill a
-- missing role; for an lfg, groups that need one of my roles. The player clicks each invite and whisper; nothing
-- here sends, invites or searches, the tick included.
local Autopilot = {}

Autopilot.TICK = 5
Autopilot.FRESH = 15 * 60

local function RT(partyLens)
    partyLens.autopilot = partyLens.autopilot or { dismissed = {} }
    return partyLens.autopilot
end

local function SameActivity(state, e)
    if state.activity ~= "" then
        return e.activityKey == state.activity
    end
    if state.label ~= "" then
        return Utils.SafeLower(e.message):find(Utils.SafeLower(state.label), 1, true) ~= nil
    end
    return false
end

function Autopilot.Suggestions(partyLens)
    local out = {}
    if not Listing.IsActive(partyLens) then
        return out
    end
    local state = Listing.State(partyLens)
    local rt, db, now = RT(partyLens), partyLens.db, time()
    local wanted = state.type == "lfm" and Needs.FromCounts(state.missing) or state.roles
    if state.type == "lfm" and Needs.IsEmpty(wanted) then
        return out
    end
    -- Read once: this runs on every tick, entry and keystroke, and a raid is 40 units of API calls.
    local members = Roster.Members()
    for key, e in pairs(partyLens.entries or {}) do
        local usable = not rt.dismissed[key] and not db.blacklist[key] and not e.isSpam and e.name
            and (now - (e.timestamp or 0)) <= Autopilot.FRESH
            and e.type == (state.type == "lfm" and "lfg" or "lfm")
        if usable and state.type == "lfm" and Roster.Contains(members, e.name) then
            usable = false
        end
        if usable and e.type == "lfm" and e.open == false then
            usable = false
        end
        if usable then
            local roles = e.roles or {}
            local role
            for _, r in ipairs(Needs.ROLES) do
                if wanted[r] and roles[r] then
                    role = role or r
                end
            end
            local open = Needs.IsEmpty(roles)
            if role or open then
                local score = math.max(0, Autopilot.FRESH - (now - e.timestamp)) + (role and 3000 or 0)
                    + (SameActivity(state, e) and 2000 or 0) + (e.isAddonUser and 1000 or 0)
                    - (e.contacted and 5000 or 0)
                out[#out + 1] = {
                    entry = e, role = role, reason = role and "role" or "open", score = score,
                    action = state.type == "lfm" and "invite" or "whisper",
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

function Autopilot.Dismiss(partyLens, entry)
    if entry and entry.key then
        RT(partyLens).dismissed[entry.key] = true
        Autopilot.Check(partyLens, true)
    end
end

-- Fires SUGGESTIONS_CHANGED when the ranked list differs from the last one seen.
function Autopilot.Check(partyLens, force)
    local rt = RT(partyLens)
    local list = Autopilot.Suggestions(partyLens)
    local parts = {}
    for _, s in ipairs(list) do
        parts[#parts + 1] = s.entry.key .. ":" .. s.action .. ":" .. tostring(s.entry.contacted)
    end
    local signature = table.concat(parts, ",")
    if force or signature ~= rt.signature then
        rt.signature = signature
        partyLens:Fire("SUGGESTIONS_CHANGED", list)
    end
end

function Autopilot.OnListing(partyLens, state)
    local rt = RT(partyLens)
    if state.active and not rt.ticker then
        rt.ticker = C_Timer.NewTicker(Autopilot.TICK, function() Autopilot.Check(partyLens) end)
    elseif not state.active and rt.ticker then
        rt.ticker:Cancel()
        rt.ticker, rt.dismissed = nil, {}
    end
    Autopilot.Check(partyLens)
end

_G[ADDON_NAME .. "_Autopilot"] = Autopilot
return Autopilot
