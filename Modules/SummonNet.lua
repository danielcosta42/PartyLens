local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Net = _G[ADDON_NAME .. "_Net"]
local L = _G[ADDON_NAME .. "_Localization"].L

-- Summons across the realm. Someone who needs to get somewhere asks the network ("summon to Blackrock Depths");
-- warlocks with PartyLens (level 20 and up, offering on) get a prompt and offer with a click; the asker sees the
-- offer and invites that warlock with a click. The warlock does the rest in the game (the ritual takes two more
-- people where they stand). Prefix "PLSum":
--   PLS1|Q|id|level|class|seen|dest     an ask: GUILD, group and realm (relayed by LibChehulMesh v8+), again every
--                                       RESEND while it is open, at most ASK_TTL
--   PLS1|X|id|seen                      the asker took it back (same buses)
--   PLS1|O|id|zone                      a warlock's offer, whispered to the asker (from the warlock's click)
-- id: hex of the asker's server time and a random part. An offer counts only whispered and only for my open ask;
-- an ask relayed through the mesh names its asker only as a claim, so a warlock's offer to it is that warlock's own
-- click and costs one whisper. Every field is checked; seen (server time) must be recent; one sender gets
-- SENDER_BUDGET asks a minute (a relayed ask counts against the peer that whispered it, its origin being only a
-- claim), everyone together GLOBAL_BUDGET, and a warlock PROMPT_BUDGET prompts a minute.
local SummonNet = {}

SummonNet.PREFIX = "PLSum"
SummonNet.PROTO = "PLS1"
SummonNet.ASK_TTL = 10 * 60
SummonNet.RESEND = 2 * 60
SummonNet.OFFER_TTL = 5 * 60
SummonNet.INBOUND_TTL = 5 * 60   -- a warlock forgets an ask not heard again within this
SummonNet.FUTURE = 120
SummonNet.MIN_LEVEL = 20         -- Ritual of Summoning
SummonNet.SENDER_BUDGET = 4
SummonNet.GLOBAL_BUDGET = 12
SummonNet.RELAY_PROMPT_GAP = 120 -- a relayed ask (its asker only a claim) prompts at most once per this
SummonNet.PROMPT_BUDGET = 3
SummonNet.INBOUND_MAX = 20
SummonNet.OFFERS_MAX = 10
SummonNet.TEXT_MAX = 40

local function RT(partyLens)
    partyLens.summonNet = partyLens.summonNet or { inbound = {}, senders = {}, prompts = { window = 0, n = 0 },
        all = { window = 0, n = 0 }, prompted = {}, relayPromptAt = -math.huge }
    return partyLens.summonNet
end

local function Changed(partyLens)
    partyLens:Fire("SUMMON_CHANGED")
end

-- Free text as it may travel: trimmed, no separator, no control character, not too long.
local function Clean(text)
    if Utils.IsSecret(text) or type(text) ~= "string" then
        return nil
    end
    text = Utils.Trim(text)
    if text == "" or #text > SummonNet.TEXT_MAX or text:find("[|%c]") then
        return nil
    end
    return text
end

local function Whole(text, min, max)
    local n = tonumber(text)
    if n and n == math.floor(n) and n >= min and n <= max then
        return n
    end
end

local function NewID()
    return string.format("%x%04x", GetServerTime(), math.random(0, 0xffff))
end

-- Warlocks of level 20 and up who offer summons.
function SummonNet.IsSummoner(partyLens)
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player")
    if Utils.IsSecret(classFile, level) then
        return false
    end
    return classFile == "WARLOCK" and (tonumber(level) or 0) >= SummonNet.MIN_LEVEL
        and partyLens.db.summonNet.offer == true
end

local function Budget(b, limit)
    local now = time()
    if now - b.window >= 60 then
        b.window, b.n = now, 0
    end
    if b.n >= limit then
        return false
    end
    b.n = b.n + 1
    return true
end

-- ---------------------------------------------------------------------------
-- The asker
-- ---------------------------------------------------------------------------
local function SendAsk(my)
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player")
    if Utils.IsSecret(classFile, level) then
        return false
    end
    local payload = table.concat({ SummonNet.PROTO, "Q", my.id, tonumber(level) or 0, classFile or "", GetServerTime(),
        my.dest }, "|")
    if Net.Broadcast(SummonNet.PREFIX, payload, SummonNet.PREFIX, true) then
        my.sentAt = time()
        return true
    end
    return false
end

local function Open(my)
    return my ~= nil and my.state == "open"
end

-- From a click: ask the realm's warlocks for a summon to `dest` (a place, in the player's words).
function SummonNet.Ask(partyLens, dest)
    dest = Clean(dest)
    if not dest then
        return false, "empty"
    end
    local rt = RT(partyLens)
    if Open(rt.my) then
        return false, "pending"
    end
    if not Utils.CanSendAddon() then
        return false, "cannot_send"
    end
    rt.my = { id = NewID(), dest = dest, t = time(), state = "open", offers = {} }
    if not SendAsk(rt.my) then
        rt.my = nil
        return false, "cannot_send"
    end
    partyLens:Notice(L("NOTICE_SUMMON_ASKED", dest))
    Changed(partyLens)
    return true
end

function SummonNet.CancelAsk(partyLens)
    local my = RT(partyLens).my
    if not Open(my) then
        return
    end
    my.state = "cancelled"
    Net.Broadcast(SummonNet.PREFIX, table.concat({ SummonNet.PROTO, "X", my.id, GetServerTime() }, "|"),
        SummonNet.PREFIX, true)
    Changed(partyLens)
end

-- nil, or { id, dest, t, state = "open"|"cancelled"|"expired", offers = { { name, key, zone, t, state } } } with
-- the offers newest first.
function SummonNet.MyAsk(partyLens)
    local my = RT(partyLens).my
    if not my then
        return nil
    end
    local offers = {}
    for _, o in pairs(my.offers) do
        offers[#offers + 1] = o
    end
    table.sort(offers, function(a, b) return a.t > b.t end)
    return { id = my.id, dest = my.dest, t = my.t, state = my.state, offers = offers }
end

-- From a click: invite the warlock who offered.
function SummonNet.AcceptOffer(partyLens, offer)
    local my = RT(partyLens).my
    local o = my and type(offer) == "table" and my.offers[offer.key]
    if not o then
        return false, "gone"
    end
    if not Roster.CanInvite() then
        return false, "cannot_invite"
    end
    if Roster.IsFull() then
        return false, "group_full"
    end
    if Roster.IsInGroup(o.name) then
        return false, "in_group"
    end
    C_PartyInfo.InviteUnit(o.name)
    o.state = "invited"
    partyLens:Notice(L("NOTICE_INVITED", o.name))
    Changed(partyLens)
    return true
end

local function OnOffer(partyLens, f, sender, dist)
    local my = RT(partyLens).my
    if dist ~= "WHISPER" or #f ~= 4 or not Open(my) or f[3] ~= my.id then
        return
    end
    local zone, name = Clean(f[4]), Utils.FullName(sender)
    local key = name and Utils.NameKey(name)
    if not zone or not key then
        return
    end
    local count = 0
    for _ in pairs(my.offers) do
        count = count + 1
    end
    if not my.offers[key] and count >= SummonNet.OFFERS_MAX then
        return
    end
    local fresh = my.offers[key] == nil
    my.offers[key] = { name = name, key = key, zone = zone, t = time(), state = "offered" }
    Changed(partyLens)
    if fresh then
        partyLens:Fire("SUMMON_OFFER", my.offers[key])
    end
end

-- ---------------------------------------------------------------------------
-- The warlock
-- ---------------------------------------------------------------------------
local function OnAsk(partyLens, f, sender, dist, via)
    if #f ~= 7 then
        return
    end
    local now = GetServerTime()
    local id = f[3]
    local level, seen = Whole(f[4], 1, 255), Whole(f[6], now - SummonNet.ASK_TTL, now + SummonNet.FUTURE)
    seen = seen and math.min(seen, now)
    local classFile, dest = f[5], Clean(f[7])
    local name = Utils.FullName(sender)
    local key = name and Utils.NameKey(name)
    if not (id:match("^%x+$") and #id <= 16 and level and seen and dest and key) or not classFile:match("^%u*$") then
        return
    end
    local rt = RT(partyLens)
    if partyLens.db.blacklist[key] then
        return
    end
    -- A repeat of an ask I know costs nothing: it refreshes it, and a newer one reopens it after a cancel.
    local known = rt.inbound[key .. ":" .. id]
    if known then
        if seen > known.seen then
            known.seen = seen
            if known.state == "cancelled" then
                known.state = "open"
                Changed(partyLens)
            end
        end
        return
    end
    local from = key
    if dist == "RELAY" and type(via) == "string" and not Utils.IsSecret(via) then
        from = Utils.NameKey(via) or via
    end
    local b = rt.senders[from]
    if not b then
        b = { window = 0, n = 0 }
        rt.senders[from] = b
    end
    local all = rt.all
    if time() - all.window >= 60 then
        all.window, all.n = time(), 0
    end
    if all.n >= SummonNet.GLOBAL_BUDGET or not Budget(b, SummonNet.SENDER_BUDGET) then
        return
    end
    all.n = all.n + 1
    local rkey = key .. ":" .. id
    local count, oldestKey, oldestT = 0, nil, nil
    for k, x in pairs(rt.inbound) do
        count = count + 1
        if not oldestT or x.t < oldestT then
            oldestKey, oldestT = k, x.t
        end
    end
    if count >= SummonNet.INBOUND_MAX and oldestKey then
        rt.inbound[oldestKey] = nil
    end
    local r = { rkey = rkey, id = id, name = name, key = key, level = level,
        classFile = classFile ~= "" and classFile or nil,
        dest = dest, seen = seen, t = time(), state = "open" }
    rt.inbound[rkey] = r
    Changed(partyLens)
    -- A prompt: once per asker per ASK_TTL; a relayed ask (asker only claimed) once per RELAY_PROMPT_GAP at most.
    local wall = time()
    if not SummonNet.IsSummoner(partyLens) or Utils.InInstance() then
        return
    end
    if wall - (rt.prompted[key] or -math.huge) < SummonNet.ASK_TTL then
        return
    end
    if dist == "RELAY" and wall - rt.relayPromptAt < SummonNet.RELAY_PROMPT_GAP then
        return
    end
    if Budget(rt.prompts, SummonNet.PROMPT_BUDGET) then
        rt.prompted[key] = wall
        if dist == "RELAY" then
            rt.relayPromptAt = wall
        end
        partyLens:Fire("SUMMON_REQUEST", r)
    end
end

-- A take-back counts only straight from the asker (GUILD, group, whisper): a relayed one names its asker only as a
-- claim, and anyone could end anyone's ask with it. A relayed ask simply ages out.
local function OnCancel(partyLens, f, sender, dist)
    if dist == "RELAY" then
        return
    end
    local key = Utils.NameKey(sender)
    local r = key and #f == 4 and RT(partyLens).inbound[key .. ":" .. f[3]]
    if r then
        r.state = "cancelled"
        Changed(partyLens)
    end
end

-- Asks heard, newest first, while open or offered (a warlock's list; empty for anyone else).
function SummonNet.Inbound(partyLens)
    local out = {}
    if not SummonNet.IsSummoner(partyLens) then
        return out
    end
    for _, r in pairs(RT(partyLens).inbound) do
        if r.state == "open" or r.state == "offered" then
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- From a click: tell the asker I can summon them (where I am, in the game's own zone name).
function SummonNet.Offer(partyLens, req)
    local r = type(req) == "table" and RT(partyLens).inbound[req.rkey]
    if not r or r.state ~= "open" then
        return false, "gone"
    end
    if not SummonNet.IsSummoner(partyLens) then
        return false, "not_summoner"
    end
    local zone = Clean(GetRealZoneText and GetRealZoneText() or "") or "?"
    if not Net.WhisperQuiet(SummonNet.PREFIX, table.concat({ SummonNet.PROTO, "O", r.id, zone }, "|"), r.name) then
        return false, "cannot_send"
    end
    r.state = "offered"
    Changed(partyLens)
    return true
end

function SummonNet.Ignore(partyLens, req)
    local r = type(req) == "table" and RT(partyLens).inbound[req.rkey]
    if r and r.state == "open" then
        r.state = "ignored"
        Changed(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Wire and clock
-- ---------------------------------------------------------------------------
function SummonNet.OnMessage(partyLens, payload, sender, dist, via)
    if Utils.IsSecret(payload, sender, dist) or type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    if Utils.IsMe(sender) then
        return
    end
    local f = { strsplit("|", payload) }
    if f[1] ~= SummonNet.PROTO then
        return
    end
    if f[2] == "Q" then
        OnAsk(partyLens, f, sender, dist, via)
    elseif f[2] == "X" then
        OnCancel(partyLens, f, sender, dist)
    elseif f[2] == "O" then
        OnOffer(partyLens, f, sender, dist)
    end
end

-- Every 30 s: repeat my open ask, end it after ASK_TTL, forget stale asks and offers.
function SummonNet.Tick(partyLens)
    local rt, now = RT(partyLens), time()
    local my = rt.my
    if Open(my) then
        if now - my.t >= SummonNet.ASK_TTL then
            my.state = "expired"
            Changed(partyLens)
        elseif now - (my.sentAt or 0) >= SummonNet.RESEND then
            SendAsk(my)
        end
    end
    if my then
        for key, o in pairs(my.offers) do
            if now - o.t > SummonNet.OFFER_TTL then
                my.offers[key] = nil
            end
        end
    end
    for rkey, r in pairs(rt.inbound) do
        if now - r.t > SummonNet.INBOUND_TTL and GetServerTime() - r.seen > SummonNet.INBOUND_TTL then
            rt.inbound[rkey] = nil
        end
    end
    for key, b in pairs(rt.senders) do
        if now - b.window > 120 then
            rt.senders[key] = nil
        end
    end
    for key, at in pairs(rt.prompted) do
        if now - at > SummonNet.ASK_TTL then
            rt.prompted[key] = nil
        end
    end
end

_G[ADDON_NAME .. "_SummonNet"] = SummonNet
return SummonNet
