local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local Roster = _G[ADDON_NAME .. "_Roster"]

local L = Localization.L

-- Warlock summon help. An addon cannot cast or click the stone; it can tell who is far (the best proxy for "not
-- here yet") and post the list to the group, from a click.
local Summon = {}

Summon.RANGE_SQ = 40 * 40

-- UnitInRange answers only secrets on 12.x; the squared distance does not, outside instances. Where the client
-- cannot measure it, whether the unit is drawn at all.
local function Near(unit)
    local d, checked = UnitDistanceSquared(unit)
    if not Utils.IsSecret(d, checked) and checked then
        return d <= Summon.RANGE_SQ
    end
    local visible = UnitIsVisible(unit)
    return not Utils.IsSecret(visible) and visible == true
end

local function Marked(partyLens)
    partyLens.summonMarked = partyLens.summonMarked or {}
    return partyLens.summonMarked
end

function Summon.Snapshot(partyLens)
    local marked = Marked(partyLens)
    local members = {}
    for _, m in ipairs(Roster.Members(partyLens.db)) do
        local inRange = m.isPlayer or Near(m.unit)
        members[#members + 1] = {
            name = m.name,
            classFile = m.classFile,
            isPlayer = m.isPlayer,
            inRange = inRange,
            isWarlock = m.classFile == "WARLOCK",
            summoned = marked[Utils.NameKey(m.name)] == true,
        }
    end
    local needed, warlocks = {}, {}
    for _, m in ipairs(members) do
        if not m.isPlayer and not m.inRange and not m.summoned then
            needed[#needed + 1] = m.name
        end
        if m.isWarlock and m.inRange then
            warlocks[#warlocks + 1] = m.name
        end
    end
    return { inGroup = IsInGroup(), members = members, needed = needed, warlocks = warlocks }
end

function Summon.Mark(partyLens, name, summoned)
    local key = Utils.NameKey(name)
    if key then
        Marked(partyLens)[key] = summoned and true or nil
        partyLens:Fire("SUMMON_CHANGED")
    end
end

-- Click only: visible party/raid chat.
function Summon.Announce(partyLens, mode)
    if not IsInGroup() then
        return false, "not_in_group"
    end
    local needed = Summon.Snapshot(partyLens).needed
    local chatType = IsInRaid() and "RAID" or "PARTY"
    if #needed == 0 then
        return Utils.SendChat(L("SUMMON_ALL_HERE"), chatType)
    end
    if mode == "next" then
        return Utils.SendChat(L("SUMMON_NEXT_MSG", needed[1]), chatType)
    end
    return Utils.SendChat(L("SUMMON_NEEDED_MSG", table.concat(needed, ", ")), chatType)
end

_G[ADDON_NAME .. "_Summon"] = Summon
return Summon
