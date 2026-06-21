local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local LocalizedKeywords = _G[ADDON_NAME .. "_LocalizedKeywords"]

local Needs = {}

function Needs.GuessNeeds(message)
    local text = Utils.SafeLower(message)
    local needs = {}
    local roleKeywords = LocalizedKeywords.GetRoleKeywords()

    for role, words in pairs(roleKeywords) do
        if Utils.ContainsAny(text, words) then
            table.insert(needs, role)
        end
    end

    if #needs == 0 and Utils.ContainsAny(text, LocalizedKeywords.GetPositiveKeywords()) then
        table.insert(needs, "any")
    end

    return needs
end

_G[ADDON_NAME .. "_Needs"] = Needs
return Needs
