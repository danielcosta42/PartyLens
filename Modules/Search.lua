local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Who = _G[ADDON_NAME .. "_Who"]
local Layer = _G[ADDON_NAME .. "_Layer"]

-- The radar as the player filtered it (db.filters), PartyLens users first, then what needs me, then freshest.
local Search = {}

local function Matches(f, e)
    if f.hideSpam and e.isSpam then
        return false
    end
    if f.onlyOpen and not e.open then
        return false
    end
    if f.type ~= "all" and e.type ~= f.type then
        return false
    end
    if f.activityType ~= "all" and e.activityType ~= f.activityType then
        return false
    end
    if f.activity ~= "" and e.activityKey ~= f.activity then
        return false
    end
    if (f.roles.tank or f.roles.heal or f.roles.dps) and not Needs.IsEmpty(e.roles or {})
        and not Needs.Intersects(f.roles, e.roles) then
        return false
    end
    local query = Utils.Trim(f.query)
    if query ~= "" then
        local hay = Utils.SafeLower((e.message or "") .. " " .. (e.activity or "") .. " " .. (e.name or ""))
        for word in Utils.SafeLower(query):gmatch("%S+") do
            if not hay:find(word, 1, true) then
                return false
            end
        end
    end
    return true
end

function Search.Entries(partyLens)
    local db = partyLens.db
    local layer = Layer.Current(partyLens)
    local out = {}
    for key, e in pairs(partyLens.entries or {}) do
        Who.Enrich(partyLens, e)
        Entry.Decorate(partyLens, e, layer)
        if not db.blacklist[key] and Matches(db.filters, e) then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if a.isAddonUser ~= b.isAddonUser then
            return a.isAddonUser == true
        end
        if a.needsMe ~= b.needsMe then
            return a.needsMe == true
        end
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    return out
end

-- needsMe counts what the list shows (blocked, spam and filtered rows out), decorated just now.
function Search.Counts(partyLens)
    local list = Search.Entries(partyLens)
    local total, needsMe, listed = 0, 0, 0
    for _ in pairs(partyLens.entries or {}) do
        total = total + 1
    end
    for _, e in ipairs(list) do
        if e.needsMe then
            needsMe = needsMe + 1
        end
        if e.isAddonUser then
            listed = listed + 1
        end
    end
    return { total = total, visible = #list, needsMe = needsMe, listed = listed }
end

_G[ADDON_NAME .. "_Search"] = Search
return Search
