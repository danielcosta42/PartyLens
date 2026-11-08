local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Needs = _G[ADDON_NAME .. "_Needs"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Messaging = _G[ADDON_NAME .. "_Messaging"]
local Net = _G[ADDON_NAME .. "_Net"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- Listings between PartyLens users, prefix "PartyLens":
--   2|kind|roles|activityType|activity|minIlvl|class|level|zoneUID|mapID|filled|target|seq|hops|origin|comment
-- kind lfg|lfm|off; roles "tank+heal" (lfm: still needed, lfg: offered); activity a key of Activity.LIST or a
-- free label; filled/target "t.h.d"; seq grows on every change of the listing (a heartbeat repeats it); hops
-- counts relays; origin is the lister, since a relayed copy arrives from someone else.
-- GUILD and the group carry it to people near the lister; the mesh's directory (Realm) to a few strangers of
-- the faction, and each of them passes a version it had not seen on once more, up to MAX_HOPS.
-- Nothing in a message is trusted beyond its shape: seq is the lister's GetServerTime() at the change (every
-- client shares that clock), so one more than FUTURE seconds ahead or older than SEEN_TTL is dropped, and so is
-- a hops outside 0..MAX_HOPS. An "off" counts only straight from its lister and is never relayed: a copy that
-- missed it ages out with the entry (Entry.NET_TTL).
local Comm = {}

Comm.PREFIX = "PartyLens"
Comm.PROTO = "2"
Comm.MAX_HOPS = 2
-- A guild hears its members' listings on GUILD already; the lister's own Realm send covers the rest, so a
-- guildmate passes one on only now and then.
Comm.GUILD_RELAY_CHANCE = 0.25
Comm.SEEN_TTL = 15 * 60
Comm.FUTURE = 120
-- The mesh's realm queue holds 40 keys for every Chehul addon and drains a few items a minute: relays share
-- RELAY_SLOTS keys, the newest relay in a slot replacing the one waiting there.
Comm.RELAY_SLOTS = 4
Comm.COMMENT_MAX = 80

local TYPES = { dungeon = true, raid = true, quest = true, guild = true, other = true }

-- [listerKey] = { seq, at, kind, hops, fields }: the last version heard from each lister (fields kept for the
-- board, which hands fresh ones on).
local function Seen(partyLens)
    partyLens.netSeen = partyLens.netSeen or {}
    return partyLens.netSeen
end
Comm.Seen = Seen

local function Board()
    return _G[ADDON_NAME .. "_Board"]
end

-- Cut on a UTF-8 boundary, with the field separator out.
function Comm.Clean(text, max)
    text = Utils.Trim(tostring(text or ""):gsub("|", "/"))
    if #text <= max then
        return text
    end
    local cut = max
    while cut > 0 do
        local b = text:byte(cut + 1)
        if b and b >= 0x80 and b < 0xC0 then
            cut = cut - 1
        else
            break
        end
    end
    return text:sub(1, cut)
end

local function RelayKey(key)
    local h = 0
    for i = 1, #key do
        h = (h * 31 + key:byte(i)) % 65521
    end
    return Comm.PREFIX .. ":relay" .. (h % Comm.RELAY_SLOTS)
end

local function Triple(t)
    return (t.tank or 0) .. "." .. (t.heal or 0) .. "." .. (t.dps or 0)
end

-- My listing on the wire. `listing` is Listing.State's shape.
function Comm.Build(listing, kind)
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player")
    local roles, filled, target = Needs.Encode(listing.roles or {}), "", ""
    if listing.type == "lfm" then
        roles = Needs.Encode(Needs.FromCounts(listing.missing))
        filled, target = Triple(listing.have), Triple(listing.want)
    end
    local activity = listing.activity ~= "" and listing.activity or Comm.Clean(listing.label, 40)
    return table.concat({
        Comm.PROTO, kind or listing.type, roles, listing.activityType or "other", activity, "0",
        Utils.IsSecret(classFile) and "" or (classFile or ""), Utils.IsSecret(level) and "0" or tostring(level or 0),
        tostring(listing.zoneUID or 0), tostring(listing.mapID or 0), filled, target,
        tostring(listing.seq or 0), "0", Utils.MyName(), Comm.Clean(listing.comment, Comm.COMMENT_MAX),
    }, "|")
end

function Comm.Send(payload)
    return Net.Broadcast(Comm.PREFIX, payload, Comm.PREFIX .. ":" .. (Utils.NameKey(Utils.MyName()) or ""))
end

local function ParseTriple(text)
    local t, h, d = (text or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if t then
        return tonumber(t), tonumber(h), tonumber(d)
    end
end

-- A finite whole number (tonumber also reads "inf" and "nan").
local function Integer(text)
    local n = tonumber(text)
    if n and n == math.floor(n) and n > -math.huge and n < math.huge then
        return n
    end
end

local function WholeLevel(text)
    local n = tonumber(text)
    if n and n >= 1 and n <= 255 and n == math.floor(n) then
        return n
    end
end

local function EntryFrom(f, origin)
    local kind = f[2]
    local act = Activity.Get(f[5])
    local label = (f[5] ~= "" and f[5] ~= "any") and f[5] or nil
    local data = {
        key = Utils.NameKey(origin), name = origin, source = "net", isAddonUser = true,
        type = kind, roles = Needs.Decode(f[3]),
        activityKey = act and act.key or nil,
        activity = act and act.name or label or L("ACTIVITY_ANY"),
        activityType = act and act.type or (TYPES[f[4]] and f[4]) or "other",
        classFile = (f[7] or ""):match("^%u+$"),
        level = WholeLevel(f[8]),
        zoneUID = tonumber(f[9]), mapID = tonumber(f[10]),
    }
    if data.zoneUID == 0 then data.zoneUID = nil end
    if data.mapID == 0 then data.mapID = nil end
    local ft, fh, fd = ParseTriple(f[11])
    local tt, th, td = ParseTriple(f[12])
    if kind == "lfm" and ft and tt then
        data.comp = { t = ft, h = fh, d = fd, tMax = tt, hMax = th, dMax = td }
        data.filled, data.max = ft + fh + fd, tt + th + td
    end
    data.message = Messaging.PostText(kind, data.activity, data.roles, data.level, f[16])
    return data
end

-- Mesh handler for the prefix: (payload, sender, dist).
function Comm.OnMessage(partyLens, payload, sender, dist)
    if Utils.IsSecret(payload, sender, dist) or type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    local f = { strsplit("|", payload) }
    if f[1] == Comm.PROTO and (f[2] == "q" or f[2] == "p") and not Utils.IsMe(sender) then
        Board().OnMessage(partyLens, f, sender, dist) -- the board's ask and its list of peers
        return
    end
    if f[1] ~= Comm.PROTO or not (f[2] == "lfg" or f[2] == "lfm" or f[2] == "off") or #f < 15 then
        return
    end
    local origin = Utils.FullName(f[15])
    if not origin or Utils.IsMe(origin) or Utils.IsMe(sender) then
        return
    end
    local key = Utils.NameKey(origin)
    local seq, hops, now = Integer(f[13]), Integer(f[14]), GetServerTime()
    if not seq or not hops or hops < 0 or hops > Comm.MAX_HOPS or seq > now + Comm.FUTURE
        or seq < now - Comm.SEEN_TTL then
        return
    end
    if f[2] == "off" and Utils.NameKey(sender) ~= key then
        return
    end
    local seen = Seen(partyLens)
    local last = seen[key]
    if last and seq < last.seq then
        return
    end
    local fresh = not last or seq > last.seq
    seen[key] = { seq = seq, at = time(), kind = f[2], hops = hops, fields = f }
    Board().Learn(partyLens, sender, "heard")
    Board().Learn(partyLens, origin, "named")
    if f[2] == "off" then
        Entry.DropNet(partyLens, key)
        return
    end
    Entry.Upsert(partyLens, EntryFrom(f, origin))
    if fresh and hops < Comm.MAX_HOPS and (dist ~= "GUILD" or math.random() < Comm.GUILD_RELAY_CHANCE) then
        local copy = {}
        for i, v in ipairs(f) do
            copy[i] = v
        end
        copy[14] = tostring(hops + 1)
        Net.Realm(Comm.PREFIX, table.concat(copy, "|"), RelayKey(key))
    end
end

function Comm.Prune(partyLens)
    local seen, now = Seen(partyLens), time()
    for key, s in pairs(seen) do
        if now - s.at > Comm.SEEN_TTL then
            seen[key] = nil
        end
    end
end

function Comm.HeardCount(partyLens)
    local n = 0
    for _ in pairs(Seen(partyLens)) do
        n = n + 1
    end
    return n
end

_G[ADDON_NAME .. "_Comm"] = Comm
return Comm
