-- A simulated WoW: Forever client for the harnesses (a library, not a harness: CI skips files named *stub.lua).
-- It loads the real TOC files (the real AceComm, ChatThrottleLib, LibChehulMesh and ChehulNet included) under
-- stubbed engine globals that behave the way the game was measured to behave on Forever:
--   * SAY and YELL addon messages answer Enum.SendAddonMessageResult.InvalidChatType, CHANNEL InvalidChannel;
--   * visible chat, invites, uninvites, leaving and /who are protected: called outside W.click(...) they are
--     recorded in W.violations instead of happening (ADDON_ACTION_BLOCKED);
--   * a value made with W.secret(v) is a secret: issecretvalue says so and comparing, concatenating,
--     indexing or tostring-ing it raises, as the game does;
--   * names are "First Surname": UnitName gives the first name, UnitFullName the two parts.
-- Timers and OnUpdate run only when the test advances the clock (W.advance).
--
--   local W = dofile("tools/wowstub.lua")
--   local PL = W.boot({ ... })     -- a fresh client, PartyLens loaded and ADDON_LOADED fired
local W = {}

local baseline = {}
for k in pairs(_G) do baseline[k] = true end

W.checks = 0
function W.check(cond, what)
  W.checks = W.checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

function W.done(name)
  print(string.format("%s: %d checks passed", name, W.checks))
end

-- ── secrets ────────────────────────────────────────────────────────────────
local rawtype = type
local SecretMT = {}
local function refuse() error("attempt to use a secret value", 2) end
for _, m in ipairs({ "__index", "__newindex", "__concat", "__eq", "__lt", "__le", "__len", "__call", "__tostring",
  "__add", "__sub", "__unm" }) do
  SecretMT[m] = refuse
end
function W.secret(v) return setmetatable({ value = v }, SecretMT) end
local function isSecret(v) return rawtype(v) == "table" and getmetatable(v) == SecretMT end
-- The game's type() of a secret is its value's type: a guard that only checks type() lets one through.
local function secretType(v)
  if isSecret(v) then return rawtype(rawget(v, "value")) end
  return rawtype(v)
end

-- ── generic frames ─────────────────────────────────────────────────────────
local function noop() end
local Object = {}
Object.__index = function(t, k)
  local m = rawget(Object, k)
  if m then return m end
  return noop
end
function Object:RegisterEvent(ev)
  W.listeners[ev] = W.listeners[ev] or {}
  for _, f in ipairs(W.listeners[ev]) do if f == self then return end end
  table.insert(W.listeners[ev], self)
end
function Object:UnregisterEvent(ev)
  for i, f in ipairs(W.listeners[ev] or {}) do if f == self then table.remove(W.listeners[ev], i) return end end
end
function Object:UnregisterAllEvents()
  for ev in pairs(W.listeners) do self:UnregisterEvent(ev) end
end
function Object:SetScript(name, fn) rawset(self, "_scripts", rawget(self, "_scripts") or {}); self._scripts[name] = fn end
function Object:GetScript(name) return (rawget(self, "_scripts") or {})[name] end
function Object:HookScript(name, fn)
  local old = self:GetScript(name)
  self:SetScript(name, function(...) if old then old(...) end return fn(...) end)
end
function Object:Show() rawset(self, "_shown", true) end
function Object:Hide() rawset(self, "_shown", false) end
function Object:IsShown() return rawget(self, "_shown") ~= false end
function Object:IsVisible() return false end
local function NewObject() return setmetatable({}, Object) end
function Object:CreateTexture() return NewObject() end
function Object:CreateFontString() return NewObject() end
function Object:CreateAnimationGroup() return NewObject() end

-- ── the clock ──────────────────────────────────────────────────────────────
local function schedule(at, fn, ticker)
  table.insert(W.timers, { at = at, fn = fn, ticker = ticker })
end

function W.advance(seconds)
  local stop = W.now + seconds
  while true do
    local nextAt, idx
    for i, t in ipairs(W.timers) do
      if not nextAt or t.at < nextAt then nextAt, idx = t.at, i end
    end
    local step = math.min(W.now + 0.1, stop)
    if nextAt and nextAt <= step then
      local t = table.remove(W.timers, idx)
      W.epoch = W.epoch + (t.at - W.now)
      W.now = t.at
      if not (t.ticker and t.ticker.cancelled) then
        t.fn(t.ticker)
        if t.ticker and not t.ticker.cancelled then schedule(W.now + t.ticker.interval, t.fn, t.ticker) end
      end
    else
      local elapsed = step - W.now
      W.epoch, W.now = W.epoch + elapsed, step
      for _, f in ipairs(W.frames) do
        local s = f:GetScript("OnUpdate")
        if s and f:IsShown() then s(f, elapsed) end
      end
      if W.now >= stop then break end
    end
  end
end

-- ── events and messages ────────────────────────────────────────────────────
function W.fire(event, ...)
  for _, f in ipairs({ unpack(W.listeners[event] or {}) }) do
    local s = f:GetScript("OnEvent")
    if s then s(f, event, ...) end
  end
end

-- An addon message arriving, as the game delivers it (AceComm reads CHAT_MSG_ADDON).
function W.deliver(prefix, message, dist, sender)
  W.fire("CHAT_MSG_ADDON", prefix, message, dist, sender)
end

-- A line in the LookingForGroup channel.
function W.channelLine(text, sender, guid, opts)
  opts = opts or {}
  W.fire("CHAT_MSG_CHANNEL", text, sender, "", opts.channelName or "4. LookingForGroup", sender, "", 26, 4,
    opts.baseName or "LookingForGroup", 0, opts.lineID or 1, guid or "")
end

-- Runs fn as if from a button's OnClick: the only place a protected call may happen.
function W.click(fn, ...)
  W.hw = true
  local r = { pcall(fn, ...) }
  W.hw = false
  if not r[1] then error(r[2], 2) end
  return unpack(r, 2)
end

local function protected(name, fn)
  return function(...)
    if not W.hw then
      table.insert(W.violations, { fn = name, args = { ... } })
      return
    end
    return fn(...)
  end
end

-- Addon messages this client sent, optionally filtered: { prefix=, dist=, target= }.
function W.sentWhere(filter)
  local out = {}
  for _, m in ipairs(W.sent) do
    local ok = true
    for k, v in pairs(filter or {}) do if m[k] ~= v then ok = false end end
    if ok then out[#out + 1] = m end
  end
  return out
end

function W.fields(msg)
  local out = {}
  for piece in (msg .. "|"):gmatch("(.-)|") do out[#out + 1] = piece end
  return out
end

-- ── the client ─────────────────────────────────────────────────────────────
local function split(sep, s)
  local out, pos = {}, 1
  if s == nil then return nil end
  while true do
    local a, b = string.find(s, sep, pos, true)
    if not a then out[#out + 1] = s:sub(pos) break end
    out[#out + 1] = s:sub(pos, a - 1)
    pos = b + 1
  end
  return unpack(out)
end

local function install(o)
  W.now, W.epoch = 1000, 1790000000
  W.timers, W.frames, W.listeners = {}, {}, {}
  W.sent, W.chat, W.violations, W.invites, W.uninvites, W.left, W.whos, W.errors, W.printed = {}, {}, {}, {}, {}, {}, {}, {}, {}
  W.tells, W.joined = {}, {}
  W.pos, W.waypoints, W.superTracked = { x = 0.523, y = 0.301 }, {}, false
  W.hw, W.lockdown, W.instance = false, false, false
  W.realm = o.realm or "ClassicBetaPvE2"
  W.mapID = o.mapID or 1453
  W.guild = o.guild ~= false
  W.who = {}
  W.channels = o.channels or { General = 1, Trade = 2, LookingForGroup = 4 }
  W.joinable = o.joinable or {} -- [name] = the number a join gets
  W.quests = o.quests or {}
  W.units = {
    player = { name = o.name or "Chehul", surname = o.surname == nil and "Costa" or o.surname, class = o.class or "PALADIN",
      level = o.level or 30, guid = "Player-1-0001" },
  }
  W.group = { members = {}, raid = false, leader = true }
  W.afk, W.combat = false, false

  issecretvalue = isSecret
  type = secretType
  strsplit = split
  wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  table.wipe = wipe
  time = function() return math.floor(W.epoch) end
  GetTime = function() return W.now end
  GetServerTime = time
  date = function(fmt, t) return os.date(fmt, t or math.floor(W.epoch)) end
  GetFramerate = function() return 60 end
  GetLocale = function() return o.locale or "enUS" end
  GetBuildInfo = function() return "1.60.1", "70862", "Nov 1 2026", 16001 end
  geterrorhandler = function() return function(err) table.insert(W.errors, err) end end
  securecallfunction = function(fn, ...) return fn(...) end
  hooksecurefunc = function(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = _G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
  end
  CreateFrame = function() local f = NewObject() table.insert(W.frames, f) return f end
  UIParent, WorldFrame = NewObject(), NewObject()
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(W.printed, text) end }
  SlashCmdList = {}
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  WHO_TAG_EXACT = "x-"
  RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" }, PALADIN = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
    PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" }, DRUID = { r = 1, g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
    MAGE = { r = 0.41, g = 0.8, b = 0.94, colorStr = "ff69ccf0" }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
  }
  Enum = { SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
    InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
    NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 } }

  Ambiguate = function(name, mode)
    if mode == "short" then return (name:gsub("%-.*$", "")) end
    return (name:gsub("%-" .. W.realm:gsub("%p", "%%%0") .. "$", ""))
  end
  local function unit(u)
    if isSecret(u) then error("secret unit token") end
    return W.units[u]
  end
  UnitExists = function(u) return unit(u) ~= nil end
  UnitName = function(u) local d = unit(u) if d then return d.name, nil end end
  UnitFullName = function(u) local d = unit(u) if d then return d.name, d.surname end end
  UnitClass = function(u) local d = unit(u) if d then return (d.class or ""):sub(1, 1) .. (d.class or ""):sub(2):lower(), d.class end end
  UnitLevel = function(u) local d = unit(u) return d and d.level or 0 end
  UnitGUID = function(u) local d = unit(u) return d and d.guid end
  UnitIsPlayer = function(u) local d = unit(u) return d ~= nil and not d.npc and not d.pet end
  UnitPlayerControlled = function(u) local d = unit(u) return d ~= nil and (not d.npc or d.pet == true) end
  UnitIsUnit = function(a, b) return unit(a) ~= nil and unit(a) == unit(b) end
  UnitGroupRolesAssigned = function(u) local d = unit(u) return d and d.role or "NONE" end
  UnitIsGroupLeader = function(u) return u == "player" and W.group.leader end
  UnitIsGroupAssistant = function() return false end
  UnitIsAFK = function(u) return u == "player" and W.afk == true end
  UnitAffectingCombat = function(u) return u == "player" and W.combat == true end
  UnitInRange = function() return W.secret(true), W.secret(true) end -- always secret on 12.x
  UnitDistanceSquared = function(u)
    local d = unit(u)
    if not d or d.dist == nil then return 0, false end
    return d.dist * d.dist, true
  end
  UnitIsVisible = function(u) local d = unit(u) return d ~= nil and d.visible ~= false end
  UnitClassification = function(u) local d = unit(u) return d and d.classification or "normal" end
  UnitIsDead = function(u)
    local d = unit(u)
    if d and isSecret(d.dead) then return d.dead end
    return d ~= nil and d.dead == true
  end
  UnitFactionGroup = function() return "Horde", "Horde" end
  UnitIsGhost = function() return false end
  GetPlayerInfoByGUID = function(guid)
    local class = (W.guids or {})[guid]
    if class then return class:lower(), class end
  end
  GetNumGroupMembers = function() return #W.group.members > 0 and (#W.group.members + 1) or 0 end
  IsInGroup = function() return #W.group.members > 0 end
  IsInRaid = function() return W.group.raid end
  IsInGuild = function() return W.guild end
  IsInInstance = function() return W.instance, W.instance and "party" or "none" end
  InCombatLockdown = function() return false end
  GetChannelName = function(what)
    if rawtype(what) == "number" then
      for name, id in pairs(W.channels) do
        if id == what then return id, name end
      end
      return 0
    end
    local id = W.channels[what]
    if id then return id, what end
    return 0
  end
  -- The server channels a client may join, in its own language; nil = the client has no such call.
  EnumerateServerChannels = o.serverChannels and function() return unpack(o.serverChannels) end or nil
  JoinPermanentChannel = function(name)
    table.insert(W.joined, name)
    if W.joinable[name] then W.channels[name] = W.joinable[name] end
  end
  JoinTemporaryChannel = function(name) table.insert(W.joined, name) end
  GetNumDisplayChannels = function() return 0 end
  GetChannelDisplayInfo = noop
  SetSelectedDisplayChannel = noop

  C_Timer = {
    After = function(sec, fn) schedule(W.now + sec, fn) end,
    NewTicker = function(sec, fn)
      local t = { interval = sec }
      function t:Cancel() self.cancelled = true end
      function t:IsCancelled() return self.cancelled == true end
      schedule(W.now + sec, fn, t)
      return t
    end,
  }
  C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "test" or nil end }
  C_PlayerInfo = { ShouldDisplaySurname = function() return W.units.player.surname ~= nil end }
  C_NameUtil = { ReplaceSurnameSeparatorWithLinkSeparator = function(n) return (n:gsub(" ", "-")) end }
  C_Map = {
    GetBestMapForUnit = function() return W.mapID end, GetMapInfo = noop,
    GetPlayerMapPosition = function()
      if not W.pos then return nil end
      return { GetXY = function() return W.pos.x, W.pos.y end }
    end,
    SetUserWaypoint = function(point) table.insert(W.waypoints, point) return true end,
  }
  UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, x = x, y = y } end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) W.superTracked = on end }
  C_QuestLog = { GetTitleForQuestID = function(id) return W.quests[id] end }
  local R = Enum.SendAddonMessageResult
  local function addon(prefix, message, dist, target)
    if isSecret(prefix) or isSecret(message) then error("secret argument to SendAddonMessage") end
    table.insert(W.sent, { prefix = prefix, msg = message, dist = dist, target = target, at = W.now, hw = W.hw })
    if dist == "SAY" or dist == "YELL" then return R.InvalidChatType end
    if dist == "CHANNEL" then return R.InvalidChannel end
    if W.lockdown then return R.AddOnMessageLockdown end
    return R.Success
  end
  C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    IsAddonMessagePrefixRegistered = function() return true end,
    SendAddonMessage = addon,
    SendAddonMessageLogged = addon,
    InChatMessagingLockdown = function() return W.lockdown end,
    GetChannelRosterInfo = noop,
    SendChatMessage = protected("SendChatMessage", function(msg, chatType, _, target)
      table.insert(W.chat, { msg = msg, chatType = chatType, target = target })
    end),
  }
  C_PartyInfo = {
    InviteUnit = protected("InviteUnit", function(name) table.insert(W.invites, name) end),
    UninviteUnit = protected("UninviteUnit", function(name) table.insert(W.uninvites, name) end),
    LeaveParty = protected("LeaveParty", function() table.insert(W.left, true) end),
  }
  C_FriendList = {
    SendWho = protected("SendWho", function(filter) table.insert(W.whos, filter) end),
    SetWhoToUi = noop,
    GetNumWhoResults = function() return #W.who end,
    GetWhoInfo = function(i) return W.who[i] end,
  }
  local box = { Insert = function(_, text) W.inserted = text end }
  ChatFrameUtil = {
    AddMessageEventFilter = noop,
    SendTell = function(name) table.insert(W.tells, name) end,
    GetActiveWindow = function() return box end,
  }
end

-- Clears everything a previous client left in _G.
local function reset()
  for k in pairs(_G) do
    if not baseline[k] then _G[k] = nil end
  end
end

function W.toc()
  local files = {}
  for line in io.lines("PartyLens.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:find("^##") and line:find("%.lua$") then files[#files + 1] = line end
  end
  return files
end

--- A fresh client with PartyLens loaded. opts: name, surname (false = none), class, level, mapID, guild,
--- channels ([name] = number joined), joinable ([name] = number a join gets), serverChannels (names),
--- savedDB (a PartyLensDB to start from), locale, realm, quests.
function W.boot(opts)
  opts = opts or {}
  reset()
  install(opts)
  PartyLensDB = opts.savedDB
  local ns = {} -- the game hands every file of an addon the same namespace table
  for _, path in ipairs(W.toc()) do
    local chunk = assert(loadfile(path))
    chunk("PartyLens", ns)
  end
  W.fire("ADDON_LOADED", "PartyLens")
  W.fire("PLAYER_LOGIN")
  W.fire("PLAYER_ENTERING_WORLD", true, false)
  local mesh = _G.ChehulMesh
  -- What the first probes find on Forever: SAY and YELL dead, and the directory in use.
  mesh.dead.SAY, mesh.dead.YELL = "InvalidChatType", "InvalidChatType"
  mesh.dir.on = true
  mesh.YELL_PERCENT = 100
  return _G.PartyLens
end

--- Fills the mesh's directory (the realm bus's whisper targets), as a list just read: LibChehulMesh v9 whispers only
--- members of a list read within DIR_FRESH.
function W.directory(names)
  local mesh = _G.ChehulMesh
  mesh.dir.names, mesh.dir.count, mesh.dir.at = names, #names, time()
end

--- Puts people in my group: { { name, surname, class, role, dist (yards; nil = unmeasured), visible } }.
function W.setGroup(members, raid)
  W.group.members, W.group.raid = {}, raid == true
  for i = 1, 40 do W.units["party" .. i], W.units["raid" .. i] = nil, nil end
  for i, m in ipairs(members) do
    W.group.members[i] = m
    local u = { name = m.name, surname = m.surname, class = m.class or "WARRIOR", level = m.level or 30,
      role = m.role, dist = m.dist, visible = m.visible, guid = "Player-1-" .. i }
    W.units[(raid and "raid" or "party") .. (raid and i + 1 or i)] = u
  end
  if raid then W.units.raid1 = W.units.player end
  W.fire("GROUP_ROSTER_UPDATE")
end

--- A creature on the given layer under the unit token (pet = a player's pet or guardian, a creature GUID that
--- carries its owner's home layer).
function W.npc(unitToken, zoneUID, npcID, pet)
  W.units[unitToken] = { npc = true, pet = pet, guid = string.format("Creature-0-5250-0-%d-%d-0000ABCDEF", zoneUID,
    npcID or 3296) }
end

--- A rare (classification "rare", "rareelite" or "worldboss") on the given layer under the unit token.
function W.rare(unitToken, zoneUID, npcID, name, classification, dead)
  W.npc(unitToken, zoneUID, npcID)
  local u = W.units[unitToken]
  u.name, u.classification, u.dead = name, classification or "rare", dead == true
end

return W
