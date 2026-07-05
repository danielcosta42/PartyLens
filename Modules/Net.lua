local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- ===========================================================================
-- Net — the PartyLens mesh transport, hardened.
--
-- WHY THIS EXISTS: the old mesh sent hidden addon messages over the CHANNEL
-- distribution (LookingForGroup), which is DISABLED on this client
-- (SendAddonMessage returns 4 = InvalidChatType) — every broadcast was dropped
-- silently because nothing checked the result. Verified with /partylens netdiag.
--
-- Transport reality on this client (measured, not assumed):
--   * Hidden addon messages WORK on GUILD / PARTY / RAID / SAY / YELL / WHISPER
--     (all return Success), and can be sent AUTOMATICALLY (from timers).
--   * Hidden addon messages over CHANNEL are BLOCKED (4).
--   * A visible SendChatMessage to a CHANNEL is realm-wide but HARDWARE-GATED:
--     it can only be sent from a real key/click, never a timer.
--
-- So there is NO automatic realm-wide hidden bus. This module gives every
-- caller an INSTRUMENTED send that records success/failure (Net.Stats) so the
-- mesh can never fail silently again, and routes each message over a transport
-- that actually delivers.
-- ===========================================================================

local Net = {}

-- Enum.SendAddonMessageResult value -> name (the client returns the numeric code).
local RESULT_NAMES = {
    [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage",
    [3] = "AddonMessageThrottle", [4] = "InvalidChatType", [5] = "NotInGroup",
    [6] = "TargetRequired", [7] = "InvalidChannel", [8] = "ChannelThrottle",
    [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown",
    [12] = "TargetOffline",
}

-- Session health counters — surfaced in the network dashboard so a dead mesh is
-- immediately visible instead of silent.
Net.stats = {
    sent = 0, ok = 0, throttled = 0, blocked = 0, failed = 0,
    chanQueued = 0, chanSent = 0, chanDropped = 0,
    lastError = nil, lastErrorAt = 0,
}

local function RecordError(what)
    Net.stats.lastError = what
    Net.stats.lastErrorAt = time()
end

-- Register a prefix once so CHAT_MSG_ADDON fires for it. Idempotent.
local registered = {}
function Net.RegisterPrefix(prefix)
    if registered[prefix] then
        return
    end
    registered[prefix] = true
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then
        pcall(reg, prefix)
    end
end

-- Instrumented hidden addon-message send. Returns true only on Success(0).
-- Never throws, never silent: every non-success updates Net.stats.
function Net.SendAddon(prefix, payload, dist, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then
        Net.stats.failed = Net.stats.failed + 1
        RecordError("no SendAddonMessage API")
        return false
    end
    Net.RegisterPrefix(prefix)
    Net.stats.sent = Net.stats.sent + 1

    local ok, r = pcall(fn, prefix, payload, dist, target)
    if not ok then
        Net.stats.failed = Net.stats.failed + 1
        RecordError("Lua error: " .. tostring(r))
        return false
    end

    -- Numeric Enum result (this client returns it).
    if type(r) == "number" then
        if r == 0 then
            Net.stats.ok = Net.stats.ok + 1
            return true
        elseif r == 3 or r == 8 then
            Net.stats.throttled = Net.stats.throttled + 1
            RecordError((RESULT_NAMES[r] or "throttle") .. " on " .. tostring(dist))
        elseif r == 11 then
            Net.stats.blocked = Net.stats.blocked + 1
            RecordError("lockdown on " .. tostring(dist))
        else
            Net.stats.failed = Net.stats.failed + 1
            RecordError((RESULT_NAMES[r] or ("code " .. r)) .. " on " .. tostring(dist))
        end
        return false
    end

    -- Older signature returns boolean/nil: treat truthy as success.
    if r ~= false and r ~= nil then
        Net.stats.ok = Net.stats.ok + 1
        return true
    end
    Net.stats.failed = Net.stats.failed + 1
    RecordError("falsy return on " .. tostring(dist))
    return false
end

-- Convenience wrappers over the distributions that actually deliver here.

-- Whole guild (the only automatic "many players" hidden bus). No-op off-guild.
function Net.Guild(prefix, payload)
    if IsInGuild and not IsInGuild() then
        return false
    end
    return Net.SendAddon(prefix, payload, "GUILD")
end

-- Current party/raid. No-op when solo.
function Net.Group(prefix, payload)
    if IsInGroup and not IsInGroup() then
        return false
    end
    local dist = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    return Net.SendAddon(prefix, payload, dist)
end

-- ~40 yd proximity (great at capital-city / auction-house hubs). Always allowed.
function Net.Proximity(prefix, payload)
    return Net.SendAddon(prefix, payload, "SAY")
end

-- Direct, targeted, same-realm handshake.
function Net.Whisper(prefix, payload, target)
    if not target or target == "" then
        return false
    end
    return Net.SendAddon(prefix, payload, "WHISPER", target)
end

-- ---------------------------------------------------------------------------
-- Realm-wide channel posting (hardware-gated).
--
-- SendChatMessage to a CHANNEL is realm-wide but can ONLY run from a real
-- key/click — a timer send raises ADDON_ACTION_BLOCKED (verified via
-- /partylens netdiag). So we QUEUE posts and flush one on the user's next
-- WorldFrame click, the same hardware-blessed trick the layer beacon uses for
-- UninviteUnit. netdiag part 3 confirmed this path DELIVERS on this client.
--
-- Posts are coalesced by key (only the latest per key survives) so a stale
-- announce can't pile up, and flushing is time-gated so a click-storm can't
-- trip the chat flood limiter.
-- ---------------------------------------------------------------------------
Net.channelQueue = {}      -- [key] = { text, channel }
local FLUSH_MIN_GAP = 1.5  -- seconds between channel sends
local lastFlush = 0

-- Queue (or replace) a realm-wide visible post; sent on the user's next click.
-- Signed at flush time (Utils.SendChat) so receivers recognise the PartyLens user.
function Net.QueueChannelPost(key, text, channelName)
    if not key or not text or text == "" then
        return
    end
    Net.channelQueue[key] = { text = text, channel = channelName or "LookingForGroup" }
    Net.stats.chanQueued = Net.stats.chanQueued + 1
end

-- Drop a still-queued post (e.g. the recruiter disarmed before the next click).
function Net.ClearChannelPost(key)
    if key then
        Net.channelQueue[key] = nil
    end
end

-- Flush at most one queued post. MUST run from a hardware event (WorldFrame click).
local function FlushChannel()
    local key, entry = next(Net.channelQueue)
    if not key then
        return
    end
    if (GetTime() - lastFlush) < FLUSH_MIN_GAP then
        return
    end
    local num = GetChannelName and GetChannelName(entry.channel)
    if type(num) ~= "number" or num == 0 then
        return -- channel not joined yet; leave it queued and retry on the next click
    end
    Net.channelQueue[key] = nil
    lastFlush = GetTime()
    local ok = pcall(Utils.SendChat, entry.text, "CHANNEL", nil, num)
    if ok then
        Net.stats.chanSent = Net.stats.chanSent + 1
    else
        Net.stats.chanDropped = Net.stats.chanDropped + 1
        RecordError("channel send error")
    end
end

-- Install the hardware-event flush hook once (call at startup).
function Net.InstallHooks()
    if Net._hooked then
        return
    end
    Net._hooked = true
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", FlushChannel)
    end
end

-- Snapshot for the network dashboard / diagnostics.
function Net.Stats()
    return Net.stats
end

-- Human one-liner for the health panel.
function Net.HealthLine()
    local s = Net.stats
    local line = string.format("addon %d/%d ok", s.ok, s.sent)
    if s.failed > 0 then line = line .. " · fail " .. s.failed end
    if s.throttled > 0 then line = line .. " · throttled " .. s.throttled end
    if s.chanQueued > 0 then line = line .. " · chan " .. s.chanSent .. "/" .. s.chanQueued end
    return line
end

_G[ADDON_NAME .. "_Net"] = Net
return Net
