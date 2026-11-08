local ADDON_NAME = ...
local Needs = _G[ADDON_NAME .. "_Needs"]

-- The radar: one row per person, keyed by their lowercased full name. A network listing is the person's own
-- structured word, so a chat line from them afterwards updates only the message and the clock.
local Entry = {}

Entry.MAX = 200
Entry.CHAT_TTL = 30 * 60
Entry.NET_TTL = 3 * 60

local NET_FIELDS = { "type", "roles", "activityKey", "activity", "activityType", "classFile", "level", "filled",
    "max", "comp", "mapID", "zoneUID" }

local function Store(partyLens)
    partyLens.entries = partyLens.entries or {}
    return partyLens.entries
end

local function NetAlive(e, now)
    return e.netAt ~= nil and (now - e.netAt) <= Entry.NET_TTL
end

-- Flags that depend on my own state (roles, layer), recomputed whenever entries are read.
function Entry.Decorate(partyLens, e, layer)
    local mine = partyLens.db and partyLens.db.roles or {}
    e.needsMe = e.type == "lfm" and Needs.Intersects(e.roles or {}, mine)
    e.open = not (e.filled and e.max and e.max > 0 and e.filled >= e.max)
    e.sameLayer = layer ~= nil and layer.zoneUID ~= nil and e.zoneUID == layer.zoneUID and e.mapID == layer.mapID
    return e
end

function Entry.Get(partyLens, key)
    return key and Store(partyLens)[key] or nil
end

local function Count(entries)
    local n = 0
    for _ in pairs(entries) do
        n = n + 1
    end
    return n
end

local function DropOldest(entries)
    local oldestKey, oldestAt
    for key, e in pairs(entries) do
        if not oldestAt or (e.timestamp or 0) < oldestAt then
            oldestKey, oldestAt = key, e.timestamp or 0
        end
    end
    if oldestKey then
        entries[oldestKey] = nil
    end
end

-- data: key, name, source ("chat"|"net") and the fields it knows. Returns the stored entry.
function Entry.Upsert(partyLens, data)
    local entries = Store(partyLens)
    local now = time()
    local e = entries[data.key]
    local isNew = e == nil
    if isNew then
        if Count(entries) >= Entry.MAX then
            DropOldest(entries)
        end
        e = { id = data.key, key = data.key, firstSeen = now, roles = {}, activityType = "other" }
        entries[data.key] = e
    end
    e.name = data.name or e.name
    e.isAddonUser = e.isAddonUser or data.isAddonUser == true
    if data.source == "net" then
        e.netAt = now
        for _, field in ipairs(NET_FIELDS) do
            e[field] = data[field]
        end
    else
        e.chatAt = now
        if not NetAlive(e, now) then
            for _, field in ipairs({ "type", "roles", "activityKey", "activity", "activityType" }) do
                e[field] = data[field]
            end
        end
        e.classFile = data.classFile or e.classFile
        e.isSpam = data.isSpam == true
        e.channel = data.channel
    end
    e.source = data.source
    e.message = data.message or e.message or ""
    e.timestamp = now
    Entry.Decorate(partyLens, e)
    if isNew then
        partyLens:Fire("ENTRY_ADDED", e, e.needsMe)
    end
    partyLens:Fire("ENTRIES_CHANGED")
    return e, isNew
end

function Entry.Remove(partyLens, key)
    local entries = Store(partyLens)
    if entries[key] then
        entries[key] = nil
        partyLens:Fire("ENTRIES_CHANGED")
    end
end

-- A stopped or expired listing leaves the row only when no recent chat line keeps it.
function Entry.DropNet(partyLens, key)
    local e = Store(partyLens)[key]
    if not e then
        return
    end
    if e.chatAt and (time() - e.chatAt) <= Entry.CHAT_TTL then
        e.netAt, e.source = nil, "chat"
        partyLens:Fire("ENTRIES_CHANGED")
    else
        Entry.Remove(partyLens, key)
    end
end

function Entry.Prune(partyLens)
    local entries = Store(partyLens)
    local now, changed = time(), false
    for key, e in pairs(entries) do
        local chatAlive = e.chatAt ~= nil and (now - e.chatAt) <= Entry.CHAT_TTL
        if not chatAlive and not NetAlive(e, now) then
            entries[key] = nil
            changed = true
        elseif e.netAt and not NetAlive(e, now) then
            e.netAt, e.source = nil, "chat"
            changed = true
        end
    end
    if changed then
        partyLens:Fire("ENTRIES_CHANGED")
    end
end

_G[ADDON_NAME .. "_Entry"] = Entry
return Entry
