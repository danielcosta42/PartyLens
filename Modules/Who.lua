local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- Passive /who enrichment (level + class).
--
-- Neither chat nor the LFG API exposes a stranger's LEVEL on this client, and
-- SendWho is a HARDWARE-EVENT-restricted function here (Blizzard's anti
-- gold-spam rule): it can only be issued from a real user action, never from a
-- timer or event handler — an automated send is silently dropped or throws an
-- ADDON_ACTION_BLOCKED error. So PartyLens never auto-scans. Instead:
--   * fellow PartyLens users broadcast their class + level over the mesh (free), and
--   * whenever the player runs /who (the row's "Who" button — a genuine click —
--     a manual /who, or the LFG panel) we HARVEST those results into a cache and
--     backfill matching entries.
-- The class/level filters then use real data as it becomes available, with zero
-- protected calls of our own.
local Who = {}

Who.CACHE_TTL = 15 * 60   -- trust a harvested level/class for this long
Who.MIN_INTERVAL = 3      -- politeness gap for the manual button (client throttles /who)

Who.cache = {}            -- [key] = { t, level, classFile }
Who.lastSend = 0

local function Key(name)
    return Utils.SafeLower(Utils.PlayerShortName(name or ""))
end

-- Fresh cache entry for a name, or nil.
function Who.Get(name)
    local key = Key(name)
    local c = Who.cache[key]
    if not c then
        return nil
    end
    if (time() - (c.t or 0)) > Who.CACHE_TTL then
        Who.cache[key] = nil
        return nil
    end
    return c
end

-- Reverse map (localized class name -> uppercase token), built lazily.
local classNameToToken
local function TokenFromLocalized(str)
    if not str or str == "" then
        return nil
    end
    if not classNameToToken then
        classNameToToken = {}
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
            classNameToToken[localized] = token
        end
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
            classNameToToken[localized] = token
        end
    end
    return classNameToToken[str]
end

local function ParseWhoInfo(info)
    if type(info) ~= "table" then
        return nil
    end
    local classFile = info.filename or TokenFromLocalized(info.classStr)
    return info.fullName or info.name, tonumber(info.level), classFile
end

-- Copies any known level/class onto every entry for that leader. Only fills
-- blanks so a mesh-supplied (trusted) value is never overwritten.
function Who.ApplyToEntries(partyLens)
    for _, e in ipairs(partyLens.entries or {}) do
        local c = e.leader and Who.Get(e.leader)
        if c then
            if c.level and not e.level then e.level = c.level end
            if c.classFile and not e.classFile then e.classFile = c.classFile end
        end
    end
end

-- Fill an entry's unknown level/class from cache (inline, no side effects).
function Who.Enrich(partyLens, entry)
    if not entry or not entry.leader then
        return
    end
    local c = Who.Get(entry.leader)
    if c then
        if c.level and not entry.level then entry.level = c.level end
        if c.classFile and not entry.classFile then entry.classFile = c.classFile end
    end
end

-- Manual /who for one name. MUST be called from a hardware event (a button
-- OnClick), the only context where SendWho is permitted on this client. Results
-- arrive asynchronously via WHO_LIST_UPDATE -> Who.OnWhoList, which harvests and
-- refreshes. Lightly throttled so rapid clicks don't trip the client's
-- "once every few seconds" limiter. Returns true if a query was issued.
function Who.Lookup(partyLens, name)
    if not name or name == "" then
        return false
    end
    if Who.Get(name) then
        return true -- already known; the row already shows it
    end
    if (time() - Who.lastSend) < Who.MIN_INTERVAL then
        return false
    end
    local display = Utils.PlayerShortName(name)
    local filter = 'n-"' .. display .. '"'
    local sent = false
    if C_FriendList and C_FriendList.SendWho then
        sent = pcall(C_FriendList.SendWho, filter)
    elseif SendWho then
        sent = pcall(SendWho, filter)
    end
    if sent then
        Who.lastSend = time()
    end
    return sent and true or false
end

-- WHO_LIST_UPDATE: harvest whatever results are present (from OUR button or any
-- other /who the player ran) into the cache, then backfill entries and refresh.
function Who.OnWhoList(partyLens)
    if not (C_FriendList and C_FriendList.GetNumWhoResults) then
        return
    end
    local n = C_FriendList.GetNumWhoResults() or 0
    local any = false
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo and C_FriendList.GetWhoInfo(i)
        local name, level, classFile = ParseWhoInfo(info)
        if name and name ~= "" then
            Who.cache[Key(name)] = { t = time(), level = level, classFile = classFile }
            any = true
        end
    end
    if any then
        Who.ApplyToEntries(partyLens)
        if partyLens.Refresh then
            partyLens:Refresh()
        end
    end
end

_G[ADDON_NAME .. "_Who"] = Who
return Who
