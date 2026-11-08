local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local LocalizedKeywords = _G[ADDON_NAME .. "_LocalizedKeywords"]

local Needs = {}

Needs.ROLES = { "tank", "heal", "dps" }

-- The roles a line names, as a set ({} when it names none). Whole words: "disc" is no healer in "discord".
function Needs.Guess(message)
    local text = Utils.SafeLower(message)
    local set = {}
    for role, words in pairs(LocalizedKeywords.GetRoleKeywords()) do
        if Utils.ContainsAnyWord(text, words) then
            set[role] = true
        end
    end
    return set
end

function Needs.Intersects(a, b)
    for _, role in ipairs(Needs.ROLES) do
        if a[role] and b[role] then
            return true
        end
    end
    return false
end

function Needs.IsEmpty(set)
    return not (set.tank or set.heal or set.dps)
end

-- { tank = 1, heal = 0, dps = 2 } -> { tank = true, dps = true }
function Needs.FromCounts(counts)
    local set = {}
    for _, role in ipairs(Needs.ROLES) do
        if (tonumber(counts and counts[role]) or 0) > 0 then
            set[role] = true
        end
    end
    return set
end

-- "tank+heal" on the wire and back.
function Needs.Encode(set)
    local parts = {}
    for _, role in ipairs(Needs.ROLES) do
        if set[role] then
            parts[#parts + 1] = role
        end
    end
    return (#parts > 0) and table.concat(parts, "+") or "any"
end

function Needs.Decode(text)
    local set = {}
    for token in string.gmatch(text or "", "[^+]+") do
        if token == "tank" or token == "heal" or token == "dps" then
            set[token] = true
        end
    end
    return set
end

_G[ADDON_NAME .. "_Needs"] = Needs
return Needs
