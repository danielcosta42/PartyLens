local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Net = _G[ADDON_NAME .. "_Net"]
local Comm = _G[ADDON_NAME .. "_Comm"]
local Listing = _G[ADDON_NAME .. "_Listing"]

-- The PartyLens board: who runs PartyLens, and the listings passed between them directly. The mesh's directory
-- reaches three strangers a minute, most of them on other Chehul addons, so a listing would take tens of minutes
-- to reach a given player; the board makes PartyLens users the carriers instead.
--   * Peers: every PartyLens user heard (any "PartyLens" message, a HELLO tagged pl) and the ones peers name.
--   * Pull: every SYNC_INTERVAL the client asks the SYNC_FANOUT peers it asked longest ago for their board
--     ("2|q", whispered). The answer is the listings they hold, as ordinary listing messages one hop further on,
--     and the peers they know ("2|p|First Surname,..."). Someone who just logged in has the board in seconds.
--     With no peer known yet, a couple of directory members are asked instead: the PartyLens users among them
--     answer.
--   * Push: a change to my listing goes straight to PUSH_FANOUT peers, its "off" to the same ones.
-- A board answer carries only listings refreshed in the last GOSSIP_AGE (an active lister renews its seq every
-- Listing.REFRESH), so a listing that stopped leaves every board within minutes. Answers are rate-limited per
-- asker and per minute. Whispers to peers go through Net.WhisperQuiet: one that logged off costs no chat line.
local Board = {}

Board.SYNC_INTERVAL = 90
Board.SYNC_FIRST = 15
Board.SYNC_FANOUT = 2
Board.PUSH_FANOUT = 4
Board.PROBE = 2
Board.PEER_TTL = 30 * 60         -- a peer that sent me PartyLens traffic
Board.NAMED_TTL = 10 * 60        -- a peer only named by another one, not heard yet
Board.PEER_MAX = 200
-- The game throttles addon messages per prefix (a short burst, then about one a second; the backoffice saw
-- refusals on Forever): an answer is at most 7 whispers, and at most 4 answers go out a minute.
Board.REPLY_LISTINGS = 6
Board.REPLY_PEERS = 8
Board.REPLY_GAP = 60             -- one answer per asker per this
Board.REPLY_BUDGET = 4           -- answers per minute at most
Board.GOSSIP_AGE = Listing.REFRESH + 90

local function RT(partyLens)
    partyLens.board = partyLens.board or { peers = {}, asked = {}, replied = {}, pushed = {}, window = 0, answers = 0 }
    return partyLens.board
end

-- Someone runs PartyLens. "heard": they sent me PartyLens traffic; "named": a peer said so.
function Board.Learn(partyLens, name, how)
    if Utils.IsSecret(name) or type(name) ~= "string" then
        return
    end
    local full = Utils.FullName(name)
    if not full or #full > 48 or full:find("[,|]") or Utils.IsMe(full) then
        return
    end
    local rt, now, key = RT(partyLens), time(), Utils.NameKey(full)
    local p = rt.peers[key]
    if p then
        if how == "heard" then
            p.heard, p.at = true, now
        end
        return
    end
    local count, oldestKey, oldestAt = 0, nil, nil
    for k, peer in pairs(rt.peers) do
        count = count + 1
        if not oldestAt or peer.at < oldestAt then
            oldestKey, oldestAt = k, peer.at
        end
    end
    if count >= Board.PEER_MAX and oldestKey then
        rt.peers[oldestKey] = nil
    end
    rt.peers[key] = { name = full, at = now, heard = how == "heard" }
end

-- The PartyLens users worth a whisper now: heard lately, named lately, or tagged pl in a fresh HELLO.
function Board.Peers(partyLens)
    local rt, now, out, byKey = RT(partyLens), time(), {}, {}
    local function Add(name, key, sure)
        if not byKey[key] then
            byKey[key] = { name = name, key = key, sure = sure }
            out[#out + 1] = byKey[key]
        elseif sure then
            byKey[key].sure = true
        end
    end
    for key, p in pairs(rt.peers) do
        if now - p.at <= (p.heard and Board.PEER_TTL or Board.NAMED_TTL) then
            Add(p.name, key, p.heard)
        end
    end
    local CN = _G.ChehulNet
    for name, p in pairs((CN and CN.peers) or {}) do
        local key = Utils.NameKey(name)
        if key and p.addons and p.addons.pl and now - (p.ts or 0) <= ((CN and CN.PEER_TTL) or 600)
            and not Utils.IsMe(name) then
            Add(Utils.FullName(name) or name, key, true)
        end
    end
    return out
end

function Board.PeerCount(partyLens)
    return #Board.Peers(partyLens)
end

-- The ones asked (or pushed to) longest ago first; never asked before all others.
local function Rotation(partyLens, stamps)
    local list = Board.Peers(partyLens)
    for _, p in ipairs(list) do
        p.last, p.roll = stamps[p.key] or 0, math.random()
    end
    table.sort(list, function(a, b)
        if a.last ~= b.last then
            return a.last < b.last
        end
        return a.roll < b.roll
    end)
    return list
end

function Board.Sync(partyLens)
    if not Utils.CanSendAddon() then
        return
    end
    local rt, now = RT(partyLens), time()
    local asked = 0
    for _, p in ipairs(Rotation(partyLens, rt.asked)) do
        if asked >= Board.SYNC_FANOUT then
            break
        end
        if Net.WhisperQuiet(Comm.PREFIX, Comm.PROTO .. "|q", p.name) then
            rt.asked[p.key], asked = now, asked + 1
        end
    end
    if asked > 0 then
        return
    end
    -- Nobody known yet: a few Chehul clients, at random: the mesh's fresh peers outside the guild (LibChehulMesh v7)
    -- and directory members where the directory still works. The PartyLens users among them answer.
    local mesh = _G.ChehulMesh
    local names = {}
    for _, list in ipairs({ mesh and mesh.Peers and mesh:Peers() or {}, mesh and mesh.dir and mesh.dir.names or {} }) do
        for _, name in ipairs(list) do
            names[#names + 1] = name
        end
    end
    local tries = 0
    while asked < Board.PROBE and tries < Board.PROBE * 4 and #names > 0 do
        tries = tries + 1
        local name = names[math.random(1, #names)]
        local key = Utils.NameKey(name)
        if key and not Utils.IsMe(name) and rt.asked[key] ~= now then
            if Net.WhisperQuiet(Comm.PREFIX, Comm.PROTO .. "|q", name) then
                rt.asked[key], asked = now, asked + 1
            end
        end
    end
end

-- The listings I would hand on: mine, and the ones I hold that are fresh and may go one hop further.
local function Holdings(partyLens, except)
    local out, oldest = {}, GetServerTime() - Board.GOSSIP_AGE
    if Listing.IsActive(partyLens) then
        local state = Listing.State(partyLens)
        out[#out + 1] = { seq = state.seq or 0, payload = Comm.Build(state) }
    end
    for key, s in pairs(Comm.Seen(partyLens)) do
        if s.fields and s.kind ~= "off" and s.hops < Comm.MAX_HOPS and s.seq >= oldest and key ~= except then
            local f = {}
            for i, v in ipairs(s.fields) do
                f[i] = v
            end
            f[14] = tostring(s.hops + 1)
            out[#out + 1] = { seq = s.seq, payload = table.concat(f, "|") }
        end
    end
    table.sort(out, function(a, b) return a.seq > b.seq end)
    return out
end

local function Answer(partyLens, sender)
    local rt, now = RT(partyLens), time()
    local key = Utils.NameKey(sender)
    if now - (rt.replied[key] or 0) < Board.REPLY_GAP then
        return
    end
    if now - rt.window >= 60 then
        rt.window, rt.answers = now, 0
    end
    if rt.answers >= Board.REPLY_BUDGET then
        return
    end
    rt.replied[key], rt.answers = now, rt.answers + 1
    for i, item in ipairs(Holdings(partyLens, key)) do
        if i > Board.REPLY_LISTINGS then
            break
        end
        Net.Whisper(Comm.PREFIX, item.payload, sender)
    end
    local names, size = {}, 0
    for _, p in ipairs(Board.Peers(partyLens)) do
        if #names >= Board.REPLY_PEERS then
            break
        end
        if p.sure and p.key ~= key and size + #p.name < 220 then
            names[#names + 1], size = p.name, size + #p.name + 1
        end
    end
    if #names > 0 then
        Net.Whisper(Comm.PREFIX, Comm.PROTO .. "|p|" .. table.concat(names, ","), sender)
    end
end

-- "2|q" and "2|p|..." (Comm hands them over, already split): whispered only.
function Board.OnMessage(partyLens, f, sender, dist)
    if dist ~= "WHISPER" then
        return
    end
    Board.Learn(partyLens, sender, "heard")
    if f[2] == "q" then
        Answer(partyLens, sender)
    elseif f[2] == "p" and type(f[3]) == "string" then
        local n = 0
        for name in f[3]:gmatch("[^,]+") do
            n = n + 1
            if n > Board.REPLY_PEERS then
                break
            end
            Board.Learn(partyLens, Utils.Trim(name), "named")
        end
    end
end

-- A change to my listing (not a heartbeat): straight to a few peers. Its "off" goes to the same ones.
function Board.Push(partyLens, payload, off)
    if not Utils.CanSendAddon() then
        return
    end
    local rt, now = RT(partyLens), time()
    if off then
        for key, name in pairs(rt.pushed) do
            Net.WhisperQuiet(Comm.PREFIX, payload, name)
            rt.pushed[key] = nil
        end
        return
    end
    local sent = 0
    local stamps = {}
    for key in pairs(rt.pushed) do
        stamps[key] = now -- the ones that have it already go last
    end
    for _, p in ipairs(Rotation(partyLens, stamps)) do
        if sent >= Board.PUSH_FANOUT then
            break
        end
        if p.sure and Net.WhisperQuiet(Comm.PREFIX, payload, p.name) then
            rt.pushed[p.key], sent = p.name, sent + 1
        end
    end
end

function Board.Prune(partyLens)
    local rt, now = RT(partyLens), time()
    for key, p in pairs(rt.peers) do
        if now - p.at > Board.PEER_TTL then
            rt.peers[key] = nil
        end
    end
    for _, stamps in ipairs({ rt.asked, rt.replied }) do
        for key, at in pairs(stamps) do
            if now - at > Board.PEER_TTL then
                stamps[key] = nil
            end
        end
    end
end

_G[ADDON_NAME .. "_Board"] = Board
return Board
