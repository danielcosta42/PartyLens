local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Mesh = _G.ChehulMesh

-- ===========================================================================
-- Net — PartyLens's transport. The hidden addon-message buses now delegate to
-- the shared LibChehulMesh (_G.ChehulMesh), so PartyLens, ProfessionHelper and
-- GuildOS all speak over one instrumented mesh (ChehulMesh:Stats).
--
-- The VISIBLE LookingForGroup posting below (the autopilot's human-readable
-- "LFM ..." line) stays here on purpose: it targets real players reading the LFG
-- channel, not the hidden structured mesh. It is hardware-gated (flushed on a
-- click), just like the shared mesh's realm-wide bus.
-- ===========================================================================

local Net = {}

-- Hidden buses -> shared mesh.
function Net.SendAddon(prefix, payload, dist, target)
    return (Mesh and Mesh.SendAddon(prefix, payload, dist, target)) or false
end

function Net.Guild(prefix, payload)
    return (Mesh and Mesh:Guild(prefix, payload)) or false
end

function Net.Group(prefix, payload)
    return (Mesh and Mesh:Group(prefix, payload)) or false
end

function Net.Proximity(prefix, payload)
    return (Mesh and Mesh:Proximity(prefix, payload)) or false
end

function Net.Whisper(prefix, payload, target)
    return (Mesh and Mesh:Whisper(prefix, payload, target)) or false
end

-- Realm-wide bus (dedicated addon-only channel, click-flushed, coalesced by key).
-- Use a STABLE per-message-type/per-source key so the queue holds only the latest
-- of each, instead of piling up.
function Net.Realm(prefix, payload, coalesceKey)
    if Mesh and Mesh.Realm then
        Mesh:Realm(prefix, payload, coalesceKey)
    end
end

-- ---------------------------------------------------------------------------
-- Visible LookingForGroup posting (autopilot LFM). Hardware-gated: queue + flush
-- one on the user's next WorldFrame click. Coalesced by key, time-gated.
-- ---------------------------------------------------------------------------
Net.channelQueue = {}
Net.chan = { queued = 0, sent = 0, dropped = 0 }
local FLUSH_MIN_GAP = 1.5
local lastFlush = 0

function Net.QueueChannelPost(key, text, channelName)
    if not key or not text or text == "" then
        return
    end
    Net.channelQueue[key] = { text = text, channel = channelName or "LookingForGroup" }
    Net.chan.queued = Net.chan.queued + 1
end

function Net.ClearChannelPost(key)
    if key then
        Net.channelQueue[key] = nil
    end
end

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
        return -- channel not joined yet; retry on the next click
    end
    Net.channelQueue[key] = nil
    lastFlush = GetTime()
    local ok = pcall(Utils.SendChat, entry.text, "CHANNEL", nil, num)
    if ok then
        Net.chan.sent = Net.chan.sent + 1
    else
        Net.chan.dropped = Net.chan.dropped + 1
    end
end

function Net.InstallHooks()
    if Net._hooked then
        return
    end
    Net._hooked = true
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", FlushChannel)
    end
end

-- ---------------------------------------------------------------------------
-- Diagnostics (delegate to the shared mesh; add the LFG-post counters).
-- ---------------------------------------------------------------------------
function Net.Stats()
    return (Mesh and Mesh:Stats()) or {}
end

function Net.HealthLine()
    local line = (Mesh and Mesh:HealthLine()) or "no mesh"
    if Net.chan.queued > 0 then
        line = line .. " \194\183 lfg " .. Net.chan.sent .. "/" .. Net.chan.queued
    end
    return line
end

_G[ADDON_NAME .. "_Net"] = Net
return Net
