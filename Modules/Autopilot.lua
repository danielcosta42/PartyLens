local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Roster = _G[ADDON_NAME .. "_Roster"]
local Messaging = _G[ADDON_NAME .. "_Messaging"]
local LFGTool = _G[ADDON_NAME .. "_LFGTool"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local LocalizedKeywords = _G[ADDON_NAME .. "_LocalizedKeywords"]
local Comm = _G[ADDON_NAME .. "_Comm"]

local L = Localization.L

local Autopilot = {}

-- Tick cadence (seconds). One engagement (whisper/invite/apply) happens at most
-- per tick, which is the coarse global rate limit; per-target cooldowns prevent
-- re-contacting the same person.
Autopilot.TICK = 3
-- Don't re-run the native group-finder search more often than this (the client
-- rate-limits C_LFGList.Search and will start failing).
Autopilot.SEARCH_INTERVAL = 15
-- How often build mode re-spams its "LFM" line in the LookingForGroup channel.
Autopilot.ANNOUNCE_INTERVAL = 60
Autopilot.LOG_MAX = 24
-- Anti-spam: never send more than this many whispers/invites per rolling minute.
Autopilot.MAX_PER_MINUTE = 8
-- Per-name attempt cap before a session blacklist (don't pester the same person).
Autopilot.MAX_CONTACTS = 2
-- Safety: auto-disarm if it has been armed this long without finishing (no
-- runaway that spams all day if the player walks away).
Autopilot.MAX_RUNTIME = 45 * 60

-- ---------------------------------------------------------------------------
-- Runtime state (NOT persisted): the autopilot always boots disarmed after a
-- reload so it never silently acts on login. Config lives in db.autopilot.
-- ---------------------------------------------------------------------------
local function RT(partyLens)
    if not partyLens.autopilot then
        partyLens.autopilot = {
            armed = false,
            state = "idle", -- idle | searching | assembling | ready
            contacts = {}, -- [lowerShortName] = lastContactTime
            contactCount = {}, -- [lowerShortName] = attempts (session blacklist)
            actionTimes = {}, -- timestamps of recent whispers/invites (rate cap)
            armedAt = 0,
            log = {},
            lastSearch = 0,
            lastAnnounce = 0,
            readyAnnounced = false,
            pendingAction = nil, -- { kind, name, message } for the advisor GO button
        }
    end
    return partyLens.autopilot
end

local function CFG(partyLens)
    return partyLens.db.autopilot
end

local function Short(name)
    return Utils.PlayerShortName(name or "")
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
function Autopilot.Log(partyLens, message)
    local rt = RT(partyLens)
    table.insert(rt.log, 1, { t = time(), text = message })
    for i = Autopilot.LOG_MAX + 1, #rt.log do
        rt.log[i] = nil
    end
    Autopilot.RefreshPanel(partyLens)
end

function Autopilot.RefreshPanel(partyLens)
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.RefreshAutopilot then
        UIMain.RefreshAutopilot(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- Contact rate limiting
-- ---------------------------------------------------------------------------
local function Cooldown(partyLens)
    local cfg = CFG(partyLens)
    local cd = tonumber(cfg.whisperCooldown) or 20
    return math.max(5, cd)
end

-- True only if we may contact this name: under the per-name attempt cap (a
-- session blacklist after MAX_CONTACTS so we don't pester anyone) and past its
-- cooldown.
function Autopilot.CanContact(partyLens, name)
    local rt = RT(partyLens)
    local key = Utils.SafeLower(Short(name))
    if (rt.contactCount[key] or 0) >= Autopilot.MAX_CONTACTS then
        return false
    end
    local last = rt.contacts[key]
    return not last or (time() - last) >= Cooldown(partyLens)
end

function Autopilot.RecordContact(partyLens, name)
    local rt = RT(partyLens)
    local key = Utils.SafeLower(Short(name))
    rt.contacts[key] = time()
    rt.contactCount[key] = (rt.contactCount[key] or 0) + 1
    rt.actionTimes[#rt.actionTimes + 1] = time()
end

-- Global throttle: cap whispers/invites per rolling minute so we never trip the
-- client's chat spam filter. Prunes the window as a side effect.
function Autopilot.WithinRate(partyLens)
    local rt = RT(partyLens)
    local now = time()
    local kept = {}
    for _, t in ipairs(rt.actionTimes or {}) do
        if now - t < 60 then
            kept[#kept + 1] = t
        end
    end
    rt.actionTimes = kept
    return #kept < Autopilot.MAX_PER_MINUTE
end

-- ---------------------------------------------------------------------------
-- Role inference for a candidate entry. Prefers an explicit role keyword in the
-- player's own message, then the class default. Returns a role token or nil.
-- ---------------------------------------------------------------------------
local function RoleFromKeywords(text)
    local matched
    local count = 0
    for role, words in pairs(LocalizedKeywords.GetRoleKeywords()) do
        if Utils.ContainsAny(text, words) then
            matched = role
            count = count + 1
        end
    end
    -- Only trust an unambiguous single-role mention.
    if count == 1 then
        return matched
    end
    return nil
end

function Autopilot.GuessPlayerRole(entry)
    -- A PartyLens-mesh broadcast carries the player's actual role — trust it.
    if entry.role and entry.role ~= "" and entry.role ~= "any" then
        return entry.role
    end
    local text = Utils.SafeLower((entry.message or "") .. " " .. (entry.activity or ""))
    local fromMsg = RoleFromKeywords(text)
    if fromMsg then
        return fromMsg
    end
    if entry.classFile and Roster.DEFAULT_ROLE[entry.classFile] then
        return Roster.DEFAULT_ROLE[entry.classFile]
    end
    return "dps"
end

-- ---------------------------------------------------------------------------
-- Candidate matching / ranking
-- ---------------------------------------------------------------------------
local function MatchesContent(partyLens, entry)
    local cfg = CFG(partyLens)
    local want = cfg.activityType or "dungeon"
    if want ~= "any" then
        local t = entry.activityType or (entry.isRaid and "raid" or "dungeon")
        if t ~= want then
            return false
        end
    end

    local filter = Utils.Trim(Utils.SafeLower(cfg.activityFilter or ""))
    if filter ~= "" then
        local hay = Utils.SafeLower((entry.activity or "") .. " " .. (entry.activityKey or "") .. " " .. (entry.message or ""))
        if not string.find(hay, filter, 1, true) then
            return false
        end
    end

    return true
end

local function FreshnessScore(entry)
    local age = math.max(0, time() - (entry.timestamp or time()))
    -- Newer is better; ~0 after 15 min.
    return math.max(0, 900 - age)
end

-- Returns a ranked list of engageable candidates for the current role.
function Autopilot.RankCandidates(partyLens)
    local cfg = CFG(partyLens)
    local results = {}
    local meShort = Utils.SafeLower(Short(UnitName("player")))

    local need
    if cfg.role == "build" then
        need = Roster.Needed(partyLens)
        if need.total <= 0 then
            return results
        end
    end

    for _, entry in ipairs(partyLens.entries or {}) do
        local ok = entry.open and entry.leader and entry.leader ~= ""
        if ok and Utils.SafeLower(Short(entry.leader)) == meShort then
            ok = false
        end
        -- Never engage spam or blacklisted leaders.
        if ok and entry.isSpam then
            ok = false
        end
        if ok and partyLens.db.blacklist and partyLens.db.blacklist[Utils.SafeLower(Short(entry.leader))] then
            ok = false
        end
        if ok and not MatchesContent(partyLens, entry) then
            ok = false
        end
        if ok and not Autopilot.CanContact(partyLens, entry.leader) then
            ok = false
        end

        if ok and cfg.role == "build" then
            -- We recruit solo players who are looking for a group. Role is a
            -- preference (scored below), not a hard filter: with fuzzy TBC role
            -- detection, rejecting on a mis-guess could stall the last slots.
            if entry.intent ~= "player" then
                ok = false
            elseif Roster.IsInGroup(entry.leader) then
                ok = false
            else
                entry._apRole = Autopilot.GuessPlayerRole(entry)
            end
        elseif ok and cfg.role == "find" then
            -- We answer groups recruiting our role.
            if entry.intent ~= "group" then
                ok = false
            else
                local needs = entry.needs or ""
                local myRole = cfg.myRole or "dps"
                local matches = needs == ""
                    or string.find(needs, "any", 1, true)
                    or string.find(needs, myRole, 1, true)
                if not matches then
                    ok = false
                end
            end
        end

        if ok then
            local score = FreshnessScore(entry)
            if entry.source == "tool" then
                score = score + 200
            end
            if entry.activityKey and entry.activityKey ~= "other" then
                score = score + 150
            end
            -- Build mode: prefer candidates whose (guessed) role still has an
            -- open slot, but don't exclude others.
            if cfg.role == "build" and need and entry._apRole and (need[entry._apRole] or 0) > 0 then
                score = score + 300
            end
            -- Strongly prefer fellow PartyLens users: their data is trusted and
            -- they'll respond instantly. This is the mesh advantage.
            if entry.isAddonUser then
                score = score + 5000
            end
            entry._apScore = score
            results[#results + 1] = entry
        end
    end

    table.sort(results, function(a, b)
        return (a._apScore or 0) > (b._apScore or 0)
    end)
    return results
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
function Autopilot.DoInvite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        pcall(InviteUnit, name)
    end
end

-- Engages a single candidate according to the configured automation tier. Uses
-- ONLY unprotected actions: party invites and whispers. Native LFG writes
-- (CreateListing/ApplyToGroup) are fully protected on this client — they taint
-- and get blocked even from a button click — so the autopilot never calls them.
function Autopilot.Engage(partyLens, entry)
    local cfg = CFG(partyLens)
    local tier = cfg.tier or "assisted"
    local rt = RT(partyLens)

    if cfg.role == "build" then
        if not Roster.CanInvite() then
            return
        end
        if tier == "advisor" then
            rt.pendingAction = { kind = "invite", name = entry.leader }
            Autopilot.Log(partyLens, L("AP_LOG_SUGGEST_INVITE", Short(entry.leader)))
        elseif Autopilot.WithinRate(partyLens) then
            Autopilot.DoInvite(entry.leader)
            Autopilot.RecordContact(partyLens, entry.leader)
            Autopilot.Log(partyLens, L(entry.isAddonUser and "AP_LOG_PL_INVITED" or "AP_LOG_INVITED", Short(entry.leader)))
        end
        return
    end

    -- find role: whisper the recruiting leader. Applying to a listing is a
    -- protected action we can't automate, so the whisper IS the contact.
    local message = Messaging.BuildAutopilotFind(partyLens.db, entry.activity)
    if message == "" then
        return
    end
    if tier == "advisor" then
        rt.pendingAction = { kind = "whisper", name = entry.leader, message = message }
        Autopilot.Log(partyLens, L("AP_LOG_SUGGEST_WHISPER", Short(entry.leader)))
    elseif Autopilot.WithinRate(partyLens) then
        SendChatMessage(message, "WHISPER", nil, entry.leader)
        Autopilot.RecordContact(partyLens, entry.leader)
        Autopilot.Log(partyLens, L(entry.isAddonUser and "AP_LOG_PL_WHISPERED" or "AP_LOG_WHISPERED", Short(entry.leader)))
    end
end

-- Fires the queued suggestion behind the GO button (advisor tier, a real click).
-- Both actions here (invite / whisper) are unprotected.
function Autopilot.PressGo(partyLens)
    local rt = RT(partyLens)
    local a = rt.pendingAction
    if a then
        if a.kind == "invite" then
            Autopilot.DoInvite(a.name)
            Autopilot.Log(partyLens, L("AP_LOG_INVITED", Short(a.name)))
        elseif a.kind == "whisper" then
            SendChatMessage(a.message, "WHISPER", nil, a.name)
            Autopilot.Log(partyLens, L("AP_LOG_WHISPERED", Short(a.name)))
        end
        Autopilot.RecordContact(partyLens, a.name)
        rt.pendingAction = nil
    end
    Autopilot.RefreshPanel(partyLens)
end

function Autopilot.HasPending(partyLens)
    return RT(partyLens).pendingAction ~= nil
end

-- ---------------------------------------------------------------------------
-- Inbound whisper -> auto-invite (build role only)
-- ---------------------------------------------------------------------------
function Autopilot.HandleWhisper(partyLens, message, sender)
    local rt = RT(partyLens)
    local cfg = CFG(partyLens)
    if not rt.armed or cfg.role ~= "build" or not cfg.autoInvite then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if not Roster.CanInvite() then
        return
    end
    local keyword = Utils.SafeLower(Utils.Trim(cfg.inviteKeyword or "inv"))
    if keyword == "" then
        keyword = "inv"
    end
    if not string.find(Utils.SafeLower(message or ""), keyword, 1, true) then
        return
    end
    local need = Roster.Needed(partyLens)
    if need.total <= 0 then
        return
    end
    if Roster.IsInGroup(sender) then
        return
    end
    -- Respect the per-name blacklist and the per-minute cap even for replies.
    if not Autopilot.CanContact(partyLens, sender) or not Autopilot.WithinRate(partyLens) then
        return
    end
    Autopilot.DoInvite(sender)
    Autopilot.RecordContact(partyLens, sender)
    Autopilot.Log(partyLens, L("AP_LOG_INVITED", Short(sender)))
end

-- ---------------------------------------------------------------------------
-- "Ready to summon" handling
-- ---------------------------------------------------------------------------
function Autopilot.OnReady(partyLens, snap)
    local rt = RT(partyLens)
    rt.state = "ready"
    if rt.readyAnnounced then
        return
    end
    rt.readyAnnounced = true
    Autopilot.Log(partyLens, L("AP_LOG_READY", snap.size, snap.max))

    local cfg = CFG(partyLens)
    -- Only the recruiter announces, and only when not in advisor mode.
    if cfg.role == "build" and cfg.tier ~= "advisor" and Roster.CanInvite() and snap.size > 1 then
        Autopilot.AnnounceReady(partyLens)
    end
end

function Autopilot.AnnounceReady(partyLens)
    local cfg = CFG(partyLens)
    local activity = cfg.activityFilter
    if not activity or activity == "" then
        activity = (cfg.activityType == "raid") and L("TAB_RAIDS") or L("TAB_DUNGEONS")
    end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    local msg = L("AP_ANNOUNCE_READY", activity)
    SendChatMessage(msg, channel)
    Autopilot.Log(partyLens, L("AP_LOG_ANNOUNCED"))
end

-- ---------------------------------------------------------------------------
-- Native group-finder warmup (find role)
-- ---------------------------------------------------------------------------
function Autopilot.MaybeSearch(partyLens, force)
    local rt = RT(partyLens)
    if not force and (time() - (rt.lastSearch or 0)) < Autopilot.SEARCH_INTERVAL then
        return
    end
    rt.lastSearch = time()
    local cfg = CFG(partyLens)
    local content = cfg.activityType
    if content == "any" then
        content = nil
    end
    if LFGTool and LFGTool.RefreshGameFinder then
        LFGTool.RefreshGameFinder(partyLens, content)
    end
end

-- Human-readable "still need" text for chat announcements, e.g. "1 Tank, 3 DPS".
local function NeedRolesText(need)
    local parts = {}
    if need.tank > 0 then parts[#parts + 1] = need.tank .. " " .. L("ROLE_TANK") end
    if need.heal > 0 then parts[#parts + 1] = need.heal .. " " .. L("ROLE_HEAL") end
    if need.dps > 0 then parts[#parts + 1] = need.dps .. " " .. L("ROLE_DPS") end
    if #parts == 0 then
        return tostring(need.remaining)
    end
    return table.concat(parts, ", ")
end

-- Build mode's recruiting engine on TBC: spam an "LFM" line in the
-- LookingForGroup channel (UNPROTECTED, unlike the native listing) and let
-- chat auto-invite pick up whoever whispers the keyword. Joins the channel if
-- needed. Returns true if it actually sent.
function Autopilot.AnnounceLFM(partyLens)
    local cfg = CFG(partyLens)
    local rt = RT(partyLens)
    local need = Roster.Needed(partyLens)
    if need.total <= 0 then
        return false
    end

    local activity = Utils.Trim(cfg.activityFilter or "")
    if activity == "" then
        activity = (cfg.activityType == "raid") and L("TAB_RAIDS") or L("TAB_DUNGEONS")
    end
    local keyword = Utils.Trim(cfg.inviteKeyword or "inv")
    if keyword == "" then
        keyword = "inv"
    end
    local message = L("AP_LFM_ANNOUNCE", activity, NeedRolesText(need), keyword)

    local channelNumber = GetChannelName and GetChannelName("LookingForGroup")
    if type(channelNumber) ~= "number" or channelNumber == 0 then
        if JoinPermanentChannel then
            JoinPermanentChannel("LookingForGroup")
        end
        channelNumber = GetChannelName and GetChannelName("LookingForGroup")
    end
    if type(channelNumber) ~= "number" or channelNumber == 0 then
        return false
    end

    SendChatMessage(message, "CHANNEL", nil, channelNumber)
    rt.lastAnnounce = time()
    Autopilot.Log(partyLens, L("AP_LOG_ANNOUNCED_LFM"))
    return true
end

-- Seeds build mode on ARM: fire the first LFM announcement right away.
function Autopilot.SeedBuild(partyLens)
    local cfg = CFG(partyLens)
    if cfg.autoAnnounce then
        Autopilot.AnnounceLFM(partyLens)
    end
end

-- ---------------------------------------------------------------------------
-- The tick loop
-- ---------------------------------------------------------------------------
function Autopilot.Tick(partyLens)
    local rt = RT(partyLens)
    local cfg = CFG(partyLens)
    if not rt.armed then
        return
    end
    -- Safety net: stop after a long run so it never spams unattended all day.
    if rt.armedAt and rt.armedAt > 0 and (time() - rt.armedAt) >= Autopilot.MAX_RUNTIME then
        Autopilot.Log(partyLens, L("AP_LOG_TIMEOUT"))
        Autopilot.Disarm(partyLens)
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    -- Broadcast our intent to the PartyLens mesh (throttled inside Heartbeat).
    if Comm and Comm.Heartbeat then
        Comm.Heartbeat(partyLens)
    end
    -- Advisor/assisted tiers wait for the player's GO before queuing anything
    -- new, so a pending suggestion or apply doesn't get re-logged every tick.
    if cfg.tier ~= "full" and Autopilot.HasPending(partyLens) then
        Autopilot.RefreshPanel(partyLens)
        return
    end

    if cfg.role == "build" then
        local need, snap = Roster.Needed(partyLens)
        if need.total <= 0 then
            Autopilot.OnReady(partyLens, snap)
            Autopilot.RefreshPanel(partyLens)
            return
        end
        rt.readyAnnounced = false
        rt.state = (snap.size > 1) and "assembling" or "searching"
        -- Periodically re-spam the LFM line in the LFG channel.
        if cfg.autoAnnounce and (time() - (rt.lastAnnounce or 0)) >= Autopilot.ANNOUNCE_INTERVAL then
            Autopilot.AnnounceLFM(partyLens)
        end
        local candidates = Autopilot.RankCandidates(partyLens)
        if candidates[1] then
            Autopilot.Engage(partyLens, candidates[1])
        end
    else
        Autopilot.MaybeSearch(partyLens)
        local snap = Roster.Snapshot()
        if snap.size > 1 then
            Autopilot.OnReady(partyLens, snap)
            Autopilot.RefreshPanel(partyLens)
            return
        end
        rt.readyAnnounced = false
        rt.state = "searching"
        local candidates = Autopilot.RankCandidates(partyLens)
        if candidates[1] then
            Autopilot.Engage(partyLens, candidates[1])
        end
    end

    Autopilot.RefreshPanel(partyLens)
end

-- React to roster changes immediately (someone accepted/left) instead of waiting
-- for the next tick.
function Autopilot.OnRosterUpdate(partyLens)
    local rt = RT(partyLens)
    if not rt.armed then
        return
    end
    local cfg = CFG(partyLens)
    if cfg.role == "build" then
        local need, snap = Roster.Needed(partyLens)
        if need.total <= 0 then
            Autopilot.OnReady(partyLens, snap)
        else
            rt.readyAnnounced = false
            rt.state = (snap.size > 1) and "assembling" or "searching"
        end
    else
        local snap = Roster.Snapshot()
        if snap.size > 1 then
            Autopilot.OnReady(partyLens, snap)
        end
    end
    Autopilot.RefreshPanel(partyLens)
end

-- ---------------------------------------------------------------------------
-- Arm / disarm
-- ---------------------------------------------------------------------------
function Autopilot.Arm(partyLens)
    local rt = RT(partyLens)
    local cfg = CFG(partyLens)
    rt.armed = true
    rt.readyAnnounced = false
    rt.lastAnnounce = 0
    rt.pendingAction = nil
    rt.state = "searching"
    -- Fresh session: reset the blacklist + rate window + runtime clock.
    rt.armedAt = time()
    rt.contactCount = {}
    rt.actionTimes = {}

    local roleLabel = (cfg.role == "build") and L("AP_ROLE_BUILD") or L("AP_ROLE_FIND")
    Autopilot.Log(partyLens, L("AP_LOG_ARMED", roleLabel))

    if cfg.role == "build" then
        Autopilot.SeedBuild(partyLens)
    else
        Autopilot.MaybeSearch(partyLens, true)
    end

    if rt.ticker then
        rt.ticker:Cancel()
    end
    if C_Timer and C_Timer.NewTicker then
        rt.ticker = C_Timer.NewTicker(Autopilot.TICK, function()
            Autopilot.Tick(partyLens)
        end)
    end

    Autopilot.Tick(partyLens)
    Autopilot.RefreshPanel(partyLens)
end

function Autopilot.Disarm(partyLens)
    local rt = RT(partyLens)
    rt.armed = false
    rt.state = "idle"
    rt.pendingAction = nil
    if rt.ticker then
        rt.ticker:Cancel()
        rt.ticker = nil
    end
    Autopilot.Log(partyLens, L("AP_LOG_DISARMED"))
    Autopilot.RefreshPanel(partyLens)
end

function Autopilot.IsArmed(partyLens)
    return RT(partyLens).armed
end

function Autopilot.Toggle(partyLens)
    if Autopilot.IsArmed(partyLens) then
        Autopilot.Disarm(partyLens)
    else
        Autopilot.Arm(partyLens)
    end
end

_G[ADDON_NAME .. "_Autopilot"] = Autopilot
return Autopilot
