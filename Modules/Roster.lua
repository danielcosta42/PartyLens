local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

local Roster = {}

-- Best-effort default role per class for TBC pugs. Role assignment is NOT a
-- first-class TBC concept (UnitGroupRolesAssigned usually returns "NONE" for
-- TBC content), so this is only a hint used when nothing better is available.
-- The autopilot's "full / not full" gate relies on group SIZE, which is solid;
-- per-role counts are advisory.
Roster.DEFAULT_ROLE = {
    WARRIOR = "dps",
    PALADIN = "heal",
    HUNTER = "dps",
    ROGUE = "dps",
    PRIEST = "heal",
    SHAMAN = "dps",
    MAGE = "dps",
    WARLOCK = "dps",
    DRUID = "dps",
}

-- Resolves a unit's role: prefer an explicit assignment when the client exposes
-- one, otherwise fall back to the class default.
function Roster.RoleForUnit(unit)
    if UnitGroupRolesAssigned then
        local assigned = UnitGroupRolesAssigned(unit)
        if assigned == "TANK" then return "tank" end
        if assigned == "HEALER" then return "heal" end
        if assigned == "DAMAGER" then return "dps" end
    end
    local _, classFile = UnitClass(unit)
    return Roster.DEFAULT_ROLE[classFile or ""] or "dps"
end

-- Walks every unit in the current group (or just the player when solo).
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

-- Snapshot of the current party/raid composition. Solo counts the player as the
-- seed of a forming group (size = 1), so build-mode math works before anyone
-- has been invited. `playerRole` (optional) overrides the player's inferred role
-- with their self-declared one, which is more reliable than the class default.
function Roster.Snapshot(playerRole)
    local snap = { size = 0, max = 5, tank = 0, heal = 0, dps = 0, members = {} }

    if IsInRaid and IsInRaid() then
        snap.max = 40
    end

    IterateUnits(function(unit)
        if not UnitExists(unit) then
            return
        end
        local name = UnitName(unit)
        local _, classFile = UnitClass(unit)
        local isPlayer = UnitIsUnit(unit, "player")
        local role = (isPlayer and playerRole) or Roster.RoleForUnit(unit)
        snap.size = snap.size + 1
        snap[role] = (snap[role] or 0) + 1
        snap.members[#snap.members + 1] = {
            name = name,
            classFile = classFile,
            role = role,
            isPlayer = isPlayer,
        }
    end)

    return snap
end

-- Computes the recruiting target, plus the current snapshot. Returns
-- (need, snapshot). Per-role counts (need.tank/heal/dps) are ADVISORY guidance
-- for which role to seek next — they rely on fuzzy class→role guessing. The
-- authoritative stop condition is need.total, which is SIZE-based
-- (target headcount minus current size) so a mis-guessed role can never cause
-- the autopilot to recruit past the intended group size.
function Roster.Needed(partyLens)
    local cfg = (partyLens.db and partyLens.db.autopilot) or {}
    local snap = Roster.Snapshot(cfg.myRole)
    local targetSize = math.max(1, (cfg.needTank or 0) + (cfg.needHeal or 0) + (cfg.needDps or 0))
    local need = {
        tank = math.max(0, (cfg.needTank or 0) - snap.tank),
        heal = math.max(0, (cfg.needHeal or 0) - snap.heal),
        dps = math.max(0, (cfg.needDps or 0) - snap.dps),
    }
    need.size = targetSize
    need.remaining = math.max(0, targetSize - snap.size)
    need.total = need.remaining
    return need, snap
end

-- True when `name` (short or full) is already in the player's group.
function Roster.IsInGroup(name)
    if not name or name == "" then
        return false
    end
    local target = Utils.SafeLower(Utils.PlayerShortName(name))
    local found = false
    IterateUnits(function(unit)
        if UnitExists(unit) and Utils.SafeLower(Utils.PlayerShortName(UnitName(unit) or "")) == target then
            found = true
        end
    end)
    return found
end

-- True when the player can issue invites (leader, or assistant in a raid). Solo
-- counts as "leader of a group of one".
function Roster.CanInvite()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n == 0 then
        return true
    end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return true
    end
    if IsInRaid and IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player") then
        return true
    end
    return false
end

_G[ADDON_NAME .. "_Roster"] = Roster
return Roster
