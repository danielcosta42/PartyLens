local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- ===========================================================================
-- NetDiag — empirical transport prober for the PartyLens mesh.
--
-- The mesh silently died because SendAddonMessage over CHANNEL is blocked on
-- this client (returns 4 = InvalidChatType) and NOTHING checked the result.
-- The first rule of hardening is: measure what actually delivers. This probe
-- reports, for THIS client, exactly which transports work — so the mesh can be
-- built on measured truth instead of documentation.
--
-- Run with:  /partylens netdiag
--
-- What it measures:
--   1. C_ChatInfo.SendAddonMessage return code for every distribution
--      (GUILD / PARTY / RAID / SAY / YELL / WHISPER-self / CHANNEL).
--   2. Whether SendChatMessage to a CHANNEL works from a TIMER (non-hardware).
--      Expected: NO — it is hardware-gated.
--   3. Whether SendChatMessage to a CHANNEL works from a real CLICK, flushed via
--      a WorldFrame OnMouseDown hook (the same hardware-blessed trick the layer
--      beacon already uses for UninviteUnit). If yes, an automatic realm-wide
--      mesh heartbeat is viable (fire queued posts on the user's natural clicks).
--
-- Delivery is checked by SELF-ECHO on a PRIVATE temp channel, so nothing ever
-- spams LookingForGroup.
-- ===========================================================================

local NetDiag = {}

local DIAG_PREFIX = "PLNetDiag"

-- Enum.SendAddonMessageResult value -> name (client returns the numeric code).
local RESULT_NAMES = {
    [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage",
    [3] = "AddonMessageThrottle", [4] = "InvalidChatType", [5] = "NotInGroup",
    [6] = "TargetRequired", [7] = "InvalidChannel", [8] = "ChannelThrottle",
    [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown",
    [12] = "TargetOffline",
}

local function ResultText(r)
    if type(r) == "number" then
        return (RESULT_NAMES[r] or "Unknown") .. " (" .. r .. ")"
    end
    return tostring(r)
end

local function SendAddon(dist, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then
        return "no SendAddonMessage API"
    end
    local ok, r = pcall(fn, DIAG_PREFIX, "ping", dist, target)
    if not ok then
        return "Lua error: " .. tostring(r)
    end
    return ResultText(r)
end

local function LFGChannelNumber()
    local n = GetChannelName and GetChannelName("LookingForGroup")
    return (type(n) == "number" and n > 0) and n or nil
end

-- Guard so a WorldFrame hook armed by one run never lingers into the next.
local run = 0

function NetDiag.Run(partyLens)
    run = run + 1
    local myRun = run

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, DIAG_PREFIX)
    end

    Utils.Print("|cff35f0c5== NetDiag ==|r probing transports on this client...")

    -- ---- Part 1: hidden addon-message distributions -----------------------
    Utils.Print("1) SendAddonMessage return codes (hidden bus):")
    local me = UnitName("player")
    local probes = {
        { "GUILD", nil }, { "PARTY", nil }, { "RAID", nil },
        { "SAY", nil }, { "YELL", nil }, { "WHISPER", me },
    }
    for _, p in ipairs(probes) do
        Utils.Print("   " .. p[1] .. string.rep(" ", 8 - #p[1]) .. " -> " .. SendAddon(p[1], p[2]))
    end
    local lfg = LFGChannelNumber()
    if lfg then
        Utils.Print("   CHANNEL(LFG) -> " .. SendAddon("CHANNEL", lfg)
            .. "   |cff808080(4 = blocked, expected)|r")
    else
        Utils.Print("   CHANNEL(LFG) -> not joined; run /partylens join first")
    end

    -- ---- Parts 2 & 3: SendChatMessage to a CHANNEL (private temp channel) --
    local diagName = "pld" .. tostring(math.random(10000, 99999))
    local token2 = "PLND2" .. tostring(math.random(10000, 99999))
    local token3 = "PLND3" .. tostring(math.random(10000, 99999))
    local state = { got2 = false, got3 = false, blocked = false, blockedInfo = "",
                    err2 = nil, err3 = nil, num = nil, fired = false, finished = false }

    if JoinTemporaryChannel then
        JoinTemporaryChannel(diagName)
    end

    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_CHANNEL")
    pcall(listener.RegisterEvent, listener, "ADDON_ACTION_BLOCKED")
    listener:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_CHANNEL" then
            local text = ...
            if type(text) == "string" then
                if string.find(text, token2, 1, true) then state.got2 = true end
                if string.find(text, token3, 1, true) then state.got3 = true end
            end
        elseif event == "ADDON_ACTION_BLOCKED" then
            local a, b = ...
            state.blocked = true
            state.blockedInfo = tostring(a or "") .. " " .. tostring(b or "")
        end
    end)

    local function Finish()
        if state.finished then return end
        state.finished = true
        -- Part 3 verdict.
        if state.num then
            if state.err3 then
                Utils.Print("   click send: |cffff5555FAILED|r (" .. state.err3 .. ")")
            elseif state.got3 then
                Utils.Print("   click send: |cff55ff55DELIVERED|r from a real click (hook path)")
            elseif state.fired then
                Utils.Print("   click send: |cffff5555not delivered|r (fired but no self-echo)")
            else
                Utils.Print("   click send: |cff808080no click detected (skipped)|r")
            end
            Utils.Print("|cff35f0c5-- Realm-wide verdict --|r")
            if state.got3 and not state.err3 then
                Utils.Print("   |cff55ff55Auto realm-wide mesh IS viable|r: queue posts, flush on the user's clicks.")
            else
                Utils.Print("   |cffffcc00Realm-wide only on explicit user posts|r (arm/broadcast buttons).")
            end
        end
        if listener then
            listener:UnregisterAllEvents()
            listener:SetScript("OnEvent", nil)
        end
        if LeaveChannelByName then
            pcall(LeaveChannelByName, diagName)
        end
    end

    -- Part 2: timer (non-hardware) channel send.
    C_Timer.After(1.0, function()
        state.num = GetChannelName and GetChannelName(diagName)
        if type(state.num) ~= "number" or state.num == 0 then
            state.num = nil
            state.err2 = "could not create/resolve private diag channel"
            return
        end
        local ok, err = pcall(SendChatMessage, "PLNETDIAG " .. token2, "CHANNEL", nil, state.num)
        if not ok then state.err2 = tostring(err) end
    end)

    -- Part 2 report + arm Part 3 (hardware-hook click test).
    C_Timer.After(3.0, function()
        Utils.Print("|cff35f0c5-- NetDiag results --|r")
        Utils.Print("2) Auto (timer) channel send:")
        if state.err2 then
            Utils.Print("   |cffff5555FAILED|r (" .. state.err2 .. ")")
        elseif state.got2 then
            Utils.Print("   |cff55ff55DELIVERED|r (unexpected — timer sends usually gated)")
        else
            Utils.Print("   |cffffcc00NOT delivered|r (gated, as expected)")
        end
        if state.blocked then
            Utils.Print("   ADDON_ACTION_BLOCKED: " .. state.blockedInfo .. " |cff808080(may be another addon)|r")
        end

        if not state.num then
            Finish()
            return
        end

        -- Part 3: send from a real click via a WorldFrame OnMouseDown hook.
        Utils.Print("3) |cffffff00CLICK anywhere in the game world|r to test a click-driven channel send...")
        if WorldFrame and WorldFrame.HookScript then
            WorldFrame:HookScript("OnMouseDown", function()
                if state.fired or state.finished or myRun ~= run then return end
                state.fired = true
                local ok, err = pcall(SendChatMessage, "PLNETDIAG " .. token3, "CHANNEL", nil, state.num)
                if not ok then state.err3 = tostring(err) end
                C_Timer.After(1.0, Finish)
            end)
        end
        -- Safety: finish even if the user never clicks.
        C_Timer.After(20.0, Finish)
    end)
end

_G[ADDON_NAME .. "_NetDiag"] = NetDiag
return NetDiag
