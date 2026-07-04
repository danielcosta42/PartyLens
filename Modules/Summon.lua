local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]

-- Summon coordination. TBC reality: an addon cannot click the meeting stone, cast
-- a summon, or read exact world positions. What it CAN do (all unprotected) is
-- use UnitInRange (out of range ~= likely needs a summon), spot warlocks (Ritual
-- of Summoning), and post a clear, ordered announcement to the party/raid.
local Summon = {}

local function IterateUnits(callback)
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            callback("raid" .. i)
        end
    else
        callback("player")
        for i = 1, n - 1 do
            callback("party" .. i)
        end
    end
end

-- Snapshot of the group with each member's summon-relevant status. `marked` is a
-- set of lowercased names the player has ticked as already summoned.
function Summon.Snapshot(marked)
    marked = marked or {}
    local list = {}
    IterateUnits(function(unit)
        if not UnitExists(unit) then
            return
        end
        local name = UnitName(unit)
        local _, classFile = UnitClass(unit)
        local isPlayer = UnitIsUnit(unit, "player")
        -- UnitInRange ~ within 40yd; self is always "here". Out of range is our
        -- best (unprotected) proxy for "not with the group yet".
        local inRange = isPlayer or (UnitInRange and UnitInRange(unit)) or false
        list[#list + 1] = {
            name = name,
            classFile = classFile,
            isPlayer = isPlayer,
            inRange = inRange,
            isWarlock = (classFile == "WARLOCK"),
            summoned = marked[Utils.SafeLower(name or "")] or false,
        }
    end)
    return list
end

-- Names that likely still need summoning: out of range, not the player, not ticked.
function Summon.Needed(marked)
    local needs = {}
    for _, m in ipairs(Summon.Snapshot(marked)) do
        if not m.summoned and not m.inRange and not m.isPlayer then
            needs[#needs + 1] = m.name
        end
    end
    return needs
end

-- Warlocks present (and in range) who could open a Ritual of Summoning.
function Summon.Warlocks()
    local locks = {}
    for _, m in ipairs(Summon.Snapshot()) do
        if m.isWarlock and m.inRange then
            locks[#locks + 1] = Utils.PlayerShortName(m.name)
        end
    end
    return locks
end

local function Channel()
    return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end

-- Announce the whole "needs summon" list to the group.
function Summon.AnnounceNeeded(partyLens, marked)
    local needs = Summon.Needed(marked)
    if #needs == 0 then
        Utils.SendChat(Localization.L("SUMMON_ALL_HERE"), Channel())
        return
    end
    local names = {}
    for _, n in ipairs(needs) do
        names[#names + 1] = Utils.PlayerShortName(n)
    end
    Utils.SendChat(Localization.L("SUMMON_NEEDED_MSG", table.concat(names, ", ")), Channel())
end

-- Announce just the next person to summon (sequential summoning).
function Summon.AnnounceNext(partyLens, marked)
    local needs = Summon.Needed(marked)
    if needs[1] then
        Utils.SendChat(Localization.L("SUMMON_NEXT_MSG", Utils.PlayerShortName(needs[1])), Channel())
    else
        Utils.SendChat(Localization.L("SUMMON_ALL_HERE"), Channel())
    end
end

_G[ADDON_NAME .. "_Summon"] = Summon
return Summon
