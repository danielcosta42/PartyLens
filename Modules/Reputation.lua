local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Localization = _G[ADDON_NAME .. "_Localization"]

local L = Localization.L
local Reputation = {}

-- ===========================================================================
-- Community reputation — a positive-only "vouch" web shared over the mesh. You
-- vouch for people you grouped with; each vouch is broadcast and everyone tallies
-- distinct voters per player. No downvotes (avoids toxicity / defamation), so the
-- score is purely "N players vouched for this person". A digest re-broadcast keeps
-- the web converging for users who log in later. Flywheel: every user adds trust
-- data, so the reputation is only useful if you're on the network -> more installs.
-- ===========================================================================

Reputation.DIGEST_INTERVAL = 300 -- re-broadcast my given-vouches digest this often
Reputation.GROUPMATE_TTL = 172800 -- keep a groupmate suggestion ~2 days
Reputation.MAX_GROUPMATES = 40
Reputation.TALLY_TTL = 60 * 60 * 24 * 30 -- age out heard vouches for strangers after 30d
Reputation.MAX_TALLY = 2000            -- hard cap on tracked names (SavedVariables bound)

local function DB(partyLens)
    partyLens.db.rep = partyLens.db.rep or {}
    local r = partyLens.db.rep
    r.given = r.given or {}
    r.tally = r.tally or {}
    r.groupmates = r.groupmates or {}
    return r
end

local function Key(name)
    return Utils.SafeLower(Utils.PlayerShortName(name or ""))
end

local function MyKey()
    return Key(UnitName("player") or "")
end

-- Display form of a lowercased key (WoW names are First-letter-capitalised).
local function Disp(key)
    if not key or key == "" then
        return key or ""
    end
    return key:sub(1, 1):upper() .. key:sub(2)
end

local function LN()
    return _G[ADDON_NAME .. "_LayerNet"]
end

function Reputation.Refresh(partyLens)
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.RefreshNetwork then
        UIMain.RefreshNetwork(partyLens)
    end
end

-- Distinct-voter count for a name (the score). Includes my own vouch if I gave one.
function Reputation.Count(partyLens, name)
    local voters = DB(partyLens).tally[Key(name)]
    if not voters then
        return 0
    end
    local n = 0
    for _ in pairs(voters) do
        n = n + 1
    end
    return n
end

function Reputation.HasVouched(partyLens, name)
    return DB(partyLens).given[Key(name)] ~= nil
end

-- Trust snapshot at a decision moment: total distinct corroborated voters (the
-- realm-wide "N vouched" score) and how many of those voters are people I have
-- actually grouped with (a stronger, personal signal). Positive-only — a 0 here
-- means "nobody we heard from vouched", never a negative mark. Returns count, byContacts.
function Reputation.VouchInfo(partyLens, name)
    local db = DB(partyLens)
    local voters = db.tally[Key(name)]
    if not voters then
        return 0, 0
    end
    local count, byContacts = 0, 0
    for voter in pairs(voters) do
        count = count + 1
        if db.groupmates[voter] then
            byContacts = byContacts + 1
        end
    end
    return count, byContacts
end

-- Vouch for a player (once). Records locally + broadcasts to the mesh.
function Reputation.Vouch(partyLens, name)
    local key = Key(name)
    if key == "" or key == MyKey() then
        return -- no self-vouch
    end
    local db = DB(partyLens)
    if db.given[key] then
        return -- already vouched this person
    end
    db.given[key] = time()
    db.tally[key] = db.tally[key] or {}
    db.tally[key][MyKey()] = time() -- count my own vote immediately
    local ln = LN()
    if ln and ln.Broadcast then
        ln.Broadcast(table.concat({ ln.NET_PROTO, "V", Utils.PlayerShortName(name) }, "|"))
    end
    Utils.Print(L("REP_VOUCHED", Utils.PlayerShortName(name)))
    Reputation.Refresh(partyLens)
end

-- Inbound vouch (V = one target) or digest (VD = CSV of a voter's vouches).
function Reputation.OnMesh(partyLens, kind, text, sender)
    local voter = Key(sender)
    if voter == "" or voter == MyKey() then
        return
    end
    local db = DB(partyLens)
    local function tally(name)
        local key = Key(name)
        -- key ~= voter: a sender can't vouch for THEMSELVES (spoof resistance),
        -- so "distinct voters" only ever counts third parties.
        if key ~= "" and key ~= voter then
            db.tally[key] = db.tally[key] or {}
            db.tally[key][voter] = time()
        end
    end
    if kind == "V" then
        local _, _, target = strsplit("|", text)
        if target and target ~= "" then
            tally(target)
        end
    elseif kind == "VD" then
        local _, _, csv = strsplit("|", text)
        if csv then
            for nm in string.gmatch(csv, "[^,]+") do
                tally(nm)
            end
        end
    end
    Reputation.Refresh(partyLens)
end

-- Note that I'm currently grouped with someone (a vouch suggestion). Called from
-- GROUP_ROSTER_UPDATE.
function Reputation.NoteGroupmate(partyLens, name)
    local key = Key(name)
    if key == "" or key == MyKey() then
        return
    end
    DB(partyLens).groupmates[key] = time()
end

function Reputation.OnRoster(partyLens)
    if (GetNumGroupMembers and GetNumGroupMembers() or 0) <= 1 then
        return
    end
    local isRaid = IsInRaid and IsInRaid()
    local total = isRaid and 40 or 4
    local changed = false
    for i = 1, total do
        local unit = (isRaid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local nm = UnitName(unit)
            if nm and nm ~= "" then
                DB(partyLens).groupmates[Key(nm)] = time()
                changed = true
            end
        end
    end
    if changed then
        Reputation.Refresh(partyLens)
    end
end

-- Recent groupmates I can vouch for, newest first (display list). Skips ones I've
-- already vouched. Also prunes stale entries.
function Reputation.Groupmates(partyLens)
    local db = DB(partyLens)
    local now, list, stale = time(), {}, {}
    for key, t in pairs(db.groupmates) do
        if type(t) ~= "number" or (now - t) > Reputation.GROUPMATE_TTL then
            stale[#stale + 1] = key
        else
            list[#list + 1] = {
                key = key,
                name = Disp(key),
                t = t,
                vouched = db.given[key] ~= nil,
                count = Reputation.Count(partyLens, key),
            }
        end
    end
    for _, key in ipairs(stale) do
        db.groupmates[key] = nil
    end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    while #list > Reputation.MAX_GROUPMATES do
        list[#list] = nil
    end
    return list
end

-- The SOCIAL CIRCLE: everyone I've built a connection with — grouped/hopped with
-- (groupmates, which GROUP_ROSTER_UPDATE records, so hop partners are included), vouched,
-- or who vouched me — each annotated with LIVE mesh presence (online / their layer / on my
-- layer). A pure VIEW over data we already keep (db.rep) + LayerNet presence, no new
-- persistence. Sorted online-first, then by vouch count, then name.
function Reputation.Circle(partyLens)
    local db = DB(partyLens)
    local ln = LN()
    local me = MyKey()
    local seen = {}
    local function add(key, reason)
        if not key or key == "" or key == me then
            return
        end
        local e = seen[key]
        if not e then
            e = { key = key, name = Disp(key), grouped = false, vouchedByMe = false, vouchedMe = false }
            seen[key] = e
        end
        e[reason] = true
    end
    for key in pairs(db.groupmates) do add(key, "grouped") end
    for key in pairs(db.given) do add(key, "vouchedByMe") end
    local myVoters = db.tally[me]
    if myVoters then
        for voter in pairs(myVoters) do add(voter, "vouchedMe") end
    end
    local list = {}
    for key, e in pairs(seen) do
        e.count = Reputation.Count(partyLens, key)
        e.node = (ln and ln.NodeInfo) and ln.NodeInfo(partyLens, key) or nil
        e.online = (e.node and e.node.online) and true or false
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end -- online first
        if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
        return a.key < b.key
    end)
    return list
end

-- Count of contacts in the circle currently online (a header stat).
function Reputation.CircleOnline(partyLens)
    local n = 0
    for _, e in ipairs(Reputation.Circle(partyLens)) do
        if e.online then n = n + 1 end
    end
    return n
end

-- Vouches I've received.
function Reputation.MyScore(partyLens)
    return Reputation.Count(partyLens, UnitName("player") or "")
end

-- How many distinct players I've vouched for.
function Reputation.GivenCount(partyLens)
    local n = 0
    for _ in pairs(DB(partyLens).given) do
        n = n + 1
    end
    return n
end

-- Re-broadcast a byte-capped digest of the people I've vouched so late joiners
-- learn my votes. No-op if I've vouched nobody.
function Reputation.BroadcastDigest(partyLens)
    local db = DB(partyLens)
    local ln = LN()
    if not ln or not ln.Broadcast then
        return
    end
    local out, used = {}, 0
    for key in pairs(db.given) do
        local add = #key + (used > 0 and 1 or 0)
        if used + add > 180 then
            break
        end
        out[#out + 1] = key
        used = used + add
    end
    if #out > 0 then
        -- Realm-wide too, coalesced to my single latest digest (VD subsumes the
        -- individual V vouches, so only the digest needs the realm-wide bus).
        ln.Broadcast(table.concat({ ln.NET_PROTO, "VD", table.concat(out, ",") }, "|"), "VD")
    end
end

-- Age out heard vouches for strangers (keeping anyone I vouched or grouped with)
-- and hard-cap the tracked-name count so the SavedVariable can't grow unbounded
-- from realm-wide channel traffic.
function Reputation.PruneTally(partyLens)
    local db = DB(partyLens)
    local now = time()
    local remove, keepable = {}, {}
    for key, voters in pairs(db.tally) do
        local newest = 0
        for v, t in pairs(voters) do
            if (now - (t or 0)) > Reputation.TALLY_TTL then
                voters[v] = nil -- removing the CURRENT key is allowed during pairs
            elseif (t or 0) > newest then
                newest = t
            end
        end
        local interesting = db.given[key] or db.groupmates[key]
        if not next(voters) then
            remove[#remove + 1] = key
        elseif not interesting and (now - newest) > Reputation.TALLY_TTL then
            remove[#remove + 1] = key
        elseif not interesting then
            keepable[#keepable + 1] = { key = key, ts = newest }
        end
    end
    for _, key in ipairs(remove) do
        db.tally[key] = nil
    end
    -- Hard cap: drop the oldest non-interesting entries.
    local count = 0
    for _ in pairs(db.tally) do count = count + 1 end
    if count > Reputation.MAX_TALLY then
        table.sort(keepable, function(a, b) return a.ts < b.ts end)
        local excess = count - Reputation.MAX_TALLY
        for i = 1, math.min(excess, #keepable) do
            db.tally[keepable[i].key] = nil
        end
    end
end

-- Start the periodic digest (called once from Core after load).
function Reputation.Start(partyLens)
    if Reputation._ticker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    Reputation._ticker = C_Timer.NewTicker(Reputation.DIGEST_INTERVAL, function()
        Reputation.BroadcastDigest(partyLens)
        Reputation.PruneTally(partyLens)
    end)
    if C_Timer.After then
        C_Timer.After(20, function() Reputation.BroadcastDigest(partyLens) end) -- bootstrap on login
    end
end

_G[ADDON_NAME .. "_Reputation"] = Reputation
return Reputation
