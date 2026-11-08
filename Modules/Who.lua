local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- /who for one name, from a click only (the game requires a hardware event). Its answer, and any /who the
-- player runs, fills the level and class of radar rows that lack them.
local Who = {}

Who.MIN_INTERVAL = 3
Who.CACHE_TTL = 15 * 60

local function Cache(partyLens)
    partyLens.whoCache = partyLens.whoCache or {}
    return partyLens.whoCache
end

function Who.Get(partyLens, name)
    local key = Utils.NameKey(name)
    local c = key and Cache(partyLens)[key]
    if c and (time() - c.t) <= Who.CACHE_TTL then
        return c
    end
end

-- Forever's own UI builds an exact /who as WHO_TAG_EXACT plus the name with its surname separator swapped for
-- the link one (GuildOS issue #71); n-"First Surname" finds nobody.
function Who.Filter(name)
    if WHO_TAG_EXACT and C_NameUtil and C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator then
        return WHO_TAG_EXACT .. C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(name)
    end
    return 'n-"' .. name .. '"'
end

-- Results to the API rather than the Social window, for this query only.
local function ToApi(on)
    if not on and WhoFrame and WhoFrame:IsVisible() then
        return
    end
    C_FriendList.SetWhoToUi(on)
end

function Who.Lookup(partyLens, name)
    if not name then
        return false, "no_name"
    end
    local now = GetTime()
    if partyLens.whoAt and (now - partyLens.whoAt) < Who.MIN_INTERVAL then
        return false, "throttled"
    end
    partyLens.whoAt = now
    ToApi(true)
    C_FriendList.SendWho(Who.Filter(name))
    return true
end

local function Fill(e, c)
    if c.level and not e.level then
        e.level = c.level
    end
    if c.classFile and not e.classFile then
        e.classFile = c.classFile
    end
end

-- Only fills blanks: a listing's own word wins.
function Who.Enrich(partyLens, e)
    local c = Who.Get(partyLens, e.name)
    if c then
        Fill(e, c)
    end
end

function Who.Prune(partyLens)
    local cache, now = Cache(partyLens), time()
    for key, c in pairs(cache) do
        if now - c.t > Who.CACHE_TTL then
            cache[key] = nil
        end
    end
end

function Who.OnWhoList(partyLens)
    local n = C_FriendList.GetNumWhoResults() or 0
    local cache, any = Cache(partyLens), false
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo(i)
        if type(info) == "table" and not Utils.IsSecret(info.fullName, info.level, info.filename) then
            local key = Utils.NameKey(info.fullName)
            if key then
                cache[key] = { t = time(), level = tonumber(info.level), classFile = info.filename }
                local e = partyLens.entries and partyLens.entries[key]
                if e then
                    Fill(e, cache[key])
                end
                any = true
            end
        end
    end
    ToApi(false)
    if any then
        partyLens:Fire("ENTRIES_CHANGED")
    end
end

_G[ADDON_NAME .. "_Who"] = Who
return Who
