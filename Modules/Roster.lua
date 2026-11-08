local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- The group I am in. Unit identity can be secret, so every read goes through a guard and a secret unit is
-- simply skipped.
local Roster = {}

-- Vanilla has no role assignment worth trusting (UnitGroupRolesAssigned is "NONE" for most), so a member
-- without one counts as their class's usual role: only a hint.
Roster.DEFAULT_ROLE = {
    WARRIOR = "tank", PALADIN = "heal", HUNTER = "dps", ROGUE = "dps", PRIEST = "heal",
    SHAMAN = "heal", MAGE = "dps", WARLOCK = "dps", DRUID = "heal",
}

local ASSIGNED = { TANK = "tank", HEALER = "heal", DAMAGER = "dps" }

function Roster.Units()
    local units = {}
    local n = GetNumGroupMembers() or 0
    if IsInRaid() then
        for i = 1, n do
            units[#units + 1] = "raid" .. i
        end
    else
        units[1] = "player"
        for i = 1, math.max(0, n - 1) do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

-- My primary role, from the role template: tank over heal over dps.
function Roster.MyRole(db)
    local roles = db and db.roles or {}
    return (roles.tank and "tank") or (roles.heal and "heal") or "dps"
end

-- { name, classFile, role, isPlayer } per member that is not secret.
function Roster.Members(db)
    local out = {}
    for _, unit in ipairs(Roster.Units()) do
        if UnitExists(unit) then
            local name = Utils.UnitFullName(unit)
            local _, classFile = UnitClass(unit)
            local assigned = UnitGroupRolesAssigned(unit)
            if name and not Utils.IsSecret(classFile, assigned) then
                local isPlayer = Utils.IsPlayerUnit(unit)
                out[#out + 1] = {
                    unit = unit,
                    name = name,
                    classFile = classFile,
                    isPlayer = isPlayer,
                    role = (isPlayer and Roster.MyRole(db)) or ASSIGNED[assigned or ""]
                        or Roster.DEFAULT_ROLE[classFile or ""] or "dps",
                }
            end
        end
    end
    return out
end

-- Role counts in the group, me included (solo = a group of one being formed).
function Roster.Have(db)
    local have = { tank = 0, heal = 0, dps = 0 }
    for _, m in ipairs(Roster.Members(db)) do
        have[m.role] = have[m.role] + 1
    end
    return have
end

-- Whether `name` is among `members` (one Roster.Members() read, for a caller that checks many names).
function Roster.Contains(members, name)
    if not name then
        return false
    end
    for _, m in ipairs(members) do
        if not m.isPlayer and Utils.SameName(m.name, name) then
            return true
        end
    end
    return false
end

function Roster.IsInGroup(name)
    return Roster.Contains(Roster.Members(), name)
end

-- Leader, a raid assistant, or alone.
function Roster.CanInvite()
    if (GetNumGroupMembers() or 0) == 0 then
        return true
    end
    local leader = UnitIsGroupLeader("player")
    if not Utils.IsSecret(leader) and leader then
        return true
    end
    local assistant = IsInRaid() and UnitIsGroupAssistant("player")
    return (not Utils.IsSecret(assistant)) and assistant == true
end

function Roster.IsFull()
    local n = GetNumGroupMembers() or 0
    return (IsInRaid() and n >= 40) or (not IsInRaid() and n >= 5)
end

_G[ADDON_NAME .. "_Roster"] = Roster
return Roster
