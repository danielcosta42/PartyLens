local ADDON_NAME = ...

-- Create a simple require-like function for module loading
local function LoadModule(moduleName)
    local globalName = ADDON_NAME .. "_" .. moduleName
    if _G[globalName] then
        return _G[globalName]
    end
    error("Module not loaded: " .. moduleName)
end

-- Load modules
local Utils = LoadModule("Utils")
local Activity = LoadModule("Activity")
local Needs = LoadModule("Needs")
local Database = LoadModule("Database")
local Entry = LoadModule("Entry")
local Chat = LoadModule("Chat")
local LFGTool = LoadModule("LFGTool")
local Messaging = LoadModule("Messaging")
local UIElements = LoadModule("UIElements")
local MinimapButton = LoadModule("Minimap")
local Roster = LoadModule("Roster")
local Net = LoadModule("Net")
local Comm = LoadModule("Comm")
local Who = LoadModule("Who")
local Layer = LoadModule("Layer")
local LayerNet = LoadModule("LayerNet")
local WorldBoss = LoadModule("WorldBoss")
local Reputation = LoadModule("Reputation")
local Autopilot = LoadModule("Autopilot")
local UIMain = LoadModule("UIMain")
local NetDiag = LoadModule("NetDiag")
local Search = LoadModule("Search")
local Localization = LoadModule("Localization")
local LocalizedKeywords = LoadModule("LocalizedKeywords")

local PartyLens = CreateFrame("Frame", "PartyLens_EventFrame")
_G.PartyLens = PartyLens

-- Key Bindings UI labels (the binding action itself lives in Bindings.xml).
_G.BINDING_HEADER_PARTYLENS = "PartyLens"
_G.BINDING_NAME_PARTYLENS_TOGGLE = Localization.L("BINDING_TOGGLE")


function PartyLens:Refresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end

    local P = UIElements.PALETTE
    local entries = Search.GetFilteredEntries(self)
    self.visibleEntries = entries
    self.content:SetHeight(math.max(1, #entries * UIMain.ROW_HEIGHT))
    self.countLabel:SetText(Localization.L("RESULT_COUNT", #entries))

    if self.emptyState then
        if #entries == 0 then
            self.emptyState:Show()
        else
            self.emptyState:Hide()
        end
    end

    for index = 1, #entries do
        if not self.rows[index] then
            UIMain.CreateResultRow(self, index)
        end
    end

    -- My current layer, resolved once, so each row can flag mesh users who are on
    -- my exact layer (same map + zoneUID) as "reachable now".
    local myLayer = Layer.Current(self)

    for index, row in ipairs(self.rows) do
        local entry = entries[index]
        if entry then
            row.entry = entry
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -((index - 1) * UIMain.ROW_HEIGHT))

            local intent = entry.intent or "group"
            local intentColor = intent == "player" and P.gold or P.teal
            local hasLeader = entry.leader ~= nil and entry.leader ~= ""

            -- Content tag + intent badge.
            local tagLabel, tagColor = UIMain.ContentTagInfo(entry)
            row.tag:SetLabel(tagLabel)
            row.tag:SetAccent(tagColor)
            row.intent:SetLabel(intent == "player" and Localization.L("INTENT_PLAYER") or Localization.L("INTENT_GROUP"))
            row.intent:SetFilled(intentColor)

            if row.plBadge then
                if entry.isAddonUser then
                    row.plBadge:SetFilled(P.teal)
                    row.plBadge:Show()
                else
                    row.plBadge:Hide()
                end
            end

            -- Community trust: positive corroborated vouch count for this leader,
            -- brighter when one of the voters is someone I've grouped with. Positive-
            -- only, so a leader with no vouches simply shows no chip.
            if row.trustChip then
                local vouches, byContacts = Reputation.VouchInfo(self, entry.leader)
                if vouches > 0 then
                    row.trustChip:SetLabel(tostring(vouches))
                    row.trustChip:SetAccent(byContacts > 0 and P.teal or P.gold)
                    row.trustChip:Show()
                else
                    row.trustChip:Hide()
                end
            end

            -- Group fill + age/freshness.
            row.fill:SetValue(entry.numMembers, entry.maxMembers, intentColor)
            local age = math.max(0, time() - (entry.timestamp or time()))
            row.time:SetText(Utils.SecondsAgo(entry.timestamp))
            UIElements.SetTextureColor(row.freshDot, UIMain.FreshnessColor(age))

            -- Title (activity).
            row.title:SetText(entry.activity or Localization.L("CONTENT_OTHER"))

            -- Leader (class colored) + class + source/open.
            local leaderStr = Utils.ClassColoredName(entry.leader or "", entry.classFile)
            if entry.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.classFile] then
                leaderStr = leaderStr .. " · " .. LOCALIZED_CLASS_NAMES_MALE[entry.classFile]
            end
            if entry.level and entry.level > 0 then
                leaderStr = leaderStr .. " · " .. Localization.L("LEVEL_SHORT") .. " " .. entry.level
            end
            local sourceLabel = entry.source == "tool" and Localization.L("SOURCE_LFG") or Localization.L("SOURCE_CHAT")
            local openText = entry.open and Localization.L("OPEN_STATUS") or Localization.L("CLOSED_STATUS")
            -- Reachable now: this mesh user is on my exact layer (same map + zoneUID),
            -- so a plain invite lands them with me — no hop needed.
            local reachSuffix = ""
            if entry.senderZoneUID and entry.senderMapID and myLayer.zoneUID
                and entry.senderMapID == myLayer.mapID and entry.senderZoneUID == myLayer.zoneUID then
                reachSuffix = "   ·   |cff35f0c5" .. Localization.L("REACH_BADGE") .. "|r"
            end
            row.leader:SetText(leaderStr .. "   ·   " .. sourceLabel .. "  ·  " .. openText .. reachSuffix)

            -- Role-need pips.
            local needSet = {}
            for token in string.gmatch(entry.needs or "", "[^,%s]+") do
                needSet[token] = true
            end
            local needed = {}
            for _, role in ipairs({ "tank", "heal", "dps" }) do
                if needSet[role] then
                    needed[#needed + 1] = role
                end
            end
            if #needed == 0 and needSet.any then
                needed = { "any" }
            end
            for i = 1, 3 do
                local role = needed[i]
                if role then
                    row.pips[i]:SetRole(role)
                    row.pips[i]:Show()
                else
                    row.pips[i]:Hide()
                end
            end
            if #needed > 0 then
                row.needsLabel:SetText(Localization.L("NEEDS_LABEL"))
                row.needsLabel:Show()
            else
                row.needsLabel:Hide()
            end

            -- Live group composition (from a PartyLens leader's mesh broadcast):
            -- append "T1/1 H0/1 D2/3" so you see who's already in and what's still open.
            local msgText = entry.message or ""
            -- Gate on intent too: if a mesh sender flips LFM->LFG, the existing-row
            -- copy can't clear the now-nil comp (pairs skips nil keys), but intent
            -- does update — so a stale "T1/1..." never renders on a player entry.
            if entry.comp and entry.intent == "group" then
                local c = entry.comp
                msgText = msgText .. "   |cff8a94a4"
                    .. Localization.L("COMP_INLINE", c.t, c.tMax, c.h, c.hMax, c.d, c.dMax) .. "|r"
            end
            row.message:SetText(msgText)

            UIElements.SetButtonEnabled(row.whisper, hasLeader)
            UIElements.SetButtonEnabled(row.open, hasLeader)
            UIElements.SetButtonEnabled(row.who, hasLeader)
            UIElements.SetButtonEnabled(row.block, hasLeader)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

function PartyLens:SearchDungeons()
    LFGTool.SearchTool(self, (LFGListCategoryEnum and LFGListCategoryEnum.Dungeons) or 2)
end

function PartyLens:SearchRaids()
    LFGTool.SearchTool(self, (LFGListCategoryEnum and LFGListCategoryEnum.Raids) or 3)
end

-- Refreshes game-finder results for whatever content category is selected.
function PartyLens:RefreshGroups()
    LFGTool.RefreshGameFinder(self, self.db and self.db.contentFilter)
end

function PartyLens:Toggle()
    UIMain.CreateMainUI(self)
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end

function PartyLens:EnsureLFGChannel()
    -- CHAT_MSG_CHANNEL only fires for channels we have actually joined, and
    -- LookingForGroup is opt-in (not auto-joined like Trade/General). Without this
    -- the entire chat-scanning half of the addon silently produces nothing.
    if self._lfgJoinChecked then
        return
    end
    self._lfgJoinChecked = true

    local id = GetChannelName and GetChannelName("LookingForGroup")
    if type(id) ~= "number" or id == 0 then
        if JoinPermanentChannel then
            JoinPermanentChannel("LookingForGroup")
        end
    end
end

function PartyLens:OnAddonLoaded(name)
    if name ~= ADDON_NAME then
        return
    end

    Database.EnsureDB(self)
    self.entries = {}
    self.entriesById = {}
    Comm.Init()
    Net.InstallHooks() -- WorldFrame click hook that flushes queued realm-wide posts
    UIMain.CreateMainUI(self)
    MinimapButton.SetShown(self, self.db.minimap)
    -- Layer network: install the (beacon-gated) chat-silencing filters and start
    -- the presence/cleanup ticker. Detection rides target/mouseover events above.
    LayerNet.InstallFilters(self)
    LayerNet.Start(self)
    Reputation.Start(self) -- periodic vouch-digest sync

    -- Receive: route both the hidden addon buses AND the realm-wide channel posts of
    -- our prefixes through the shared mesh's dispatcher. (We therefore no longer
    -- handle CHAT_MSG_ADDON directly for these prefixes — that would double-process.)
    local Mesh = _G.ChehulMesh
    if Mesh and Mesh.Register then
        Mesh:Register(LayerNet.PREFIX, function(payload, sender, dist)
            LayerNet.OnAddonMessage(self, LayerNet.PREFIX, payload, dist, sender)
        end)
        Mesh:Register(Comm.PREFIX, function(payload, sender, dist)
            Comm.OnMessage(self, Comm.PREFIX, payload, dist, sender)
        end)
    end

    SLASH_PARTYLENS1 = "/partylens"
    SlashCmdList.PARTYLENS = function(msg)
        msg = Utils.SafeLower(Utils.Trim(msg))
        if msg == Localization.L("SLASH_SHOW") or msg == "show" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            self:Refresh()
        elseif msg == Localization.L("SLASH_HIDE") or msg == "hide" then
            if self.frame then
                self.frame:Hide()
            end
        elseif msg == Localization.L("SLASH_JOIN") or msg == "join" then
            Messaging.JoinLookingForGroup()
        elseif msg == Localization.L("SLASH_AUTO") or msg == "auto" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "autopilot")
        elseif msg == Localization.L("SLASH_SUMMON") or msg == "summon" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "summon")
        elseif msg == "arm" then
            Autopilot.Arm(self)
        elseif msg == "disarm" then
            Autopilot.Disarm(self)
        elseif msg == "beacon" then
            LayerNet.ToggleBeacon(self)
        elseif msg == "autobeacon" then
            LayerNet.ToggleAutoBeacon(self)
        elseif msg:sub(1, 8) == "reqlayer" then
            -- "/partylens reqlayer 5" (or "reqlayer any" / just "reqlayer").
            -- Triggered by the Enter key, so the visible chat post is allowed.
            LayerNet.RequestLayer(self, Utils.Trim(msg:sub(9)))
        elseif msg == "boss" then
            local list = WorldBoss.Active(self)
            if #list == 0 then
                Utils.Print(Localization.L("WB_NONE"))
            else
                for _, s in ipairs(list) do
                    Utils.Print(Localization.L("WB_ALERT", s.name, s.ordinal or "?"))
                end
            end
        elseif msg == "bosstest" then
            -- Dev/QA: inject a fake sighting on our current layer to see the banner.
            local cur = Layer.Current(self)
            WorldBoss.OnMeshSighting(self, cur.mapID, cur.zoneUID or 1, 18728, 73, "Tester")
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "layer")
        elseif msg == "layerframe" then
            -- Diagnostic: which party-frame candidates exist, and (after 3s) the
            -- frame under the mouse — hover the party frame to identify it.
            for _, n in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer",
                "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }) do
                local f = _G[n]
                Utils.Print(n .. ": " .. (f and ("shown=" .. tostring(f:IsShown()) ..
                    " a=" .. tostring(f:GetAlpha())) or "NIL"))
            end
            Utils.Print("hover the party frame now... reading in 3s")
            if C_Timer and C_Timer.After then
                C_Timer.After(3, function()
                    local foci = GetMouseFoci and GetMouseFoci()
                    local f = (foci and foci[1]) or (GetMouseFocus and GetMouseFocus())
                    if f and f.GetName then
                        Utils.Print("UNDER MOUSE: " .. (f:GetName() or "(anonymous)"))
                        local p, d = f:GetParent(), 0
                        while p and p.GetName and d < 8 do
                            Utils.Print("  ^ " .. (p:GetName() or "(anonymous)"))
                            p, d = p:GetParent(), d + 1
                        end
                    else
                        Utils.Print("nothing under mouse (hover the frame during the 3s)")
                    end
                end)
            end
        elseif msg == "quiet" then
            -- "/partylens quiet" — rank known layers by mesh crowding and hop to the
            -- least-crowded one (farming/questing helper).
            local layers = (LayerNet.KnownLayers and LayerNet.KnownLayers(self)) or {}
            local quiet = LayerNet.QuietestLayer and LayerNet.QuietestLayer(self, layers)
            if #layers > 0 then
                Utils.Print("|cff88ccff" .. Localization.L("LAYER_QUIET_HEADER") .. "|r")
                for _, ly in ipairs(layers) do
                    local tag = ly.isCurrent and " |cffffd200(you)|r"
                        or (quiet and ly.ordinal == quiet.ordinal and " |cff58d6b0<= quietest|r")
                        or ""
                    Utils.Print(Localization.L("LAYER_QUIET_LINE", ly.ordinal, ly.nodes or 0, tag))
                end
            end
            if quiet then
                Utils.Print("|cff58d6b0" .. Localization.L("LAYER_QUIET_HOP", quiet.ordinal, quiet.nodes or 0) .. "|r")
                if quiet.beaconZoneUID and quiet.beaconMapID and LayerNet.RequestLayerFor then
                    LayerNet.RequestLayerFor(self, quiet.beaconMapID, quiet.beaconZoneUID)
                else
                    LayerNet.RequestLayer(self, tostring(quiet.ordinal))
                end
            else
                Utils.Print(Localization.L("LAYER_QUIET_NONE"))
            end
        elseif msg == "layer" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "layer")
        elseif msg == "radar" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "radar")
        elseif msg == "flag" then
            -- "/partylens flag" — crowd-source: put my current target (any rare/boss/event
            -- mob) on the realm live feed with its name + layer.
            if WorldBoss and WorldBoss.FlagTarget then WorldBoss.FlagTarget(self) end
        elseif msg == "network" or msg == "net" then
            UIMain.CreateMainUI(self)
            self.frame:Show()
            UIMain.SetMode(self, "network")
        elseif msg:sub(1, 5) == "vouch" then
            -- "/partylens vouch Name" — quick vouch from chat.
            local name = Utils.Trim(msg:sub(6))
            if name ~= "" then Reputation.Vouch(self, name) end
        elseif msg == "diag" then
            LFGTool.Diagnose()
        elseif msg == "netdiag" then
            NetDiag.Run(self)
        elseif msg == "netstat" then
            Utils.Print("mesh: " .. Net.HealthLine())
        elseif msg == "hopdebug" then
            -- Toggle layer-hop tracing: the beacon logs why it does/doesn't invite
            -- (no-match with both zoneUIDs, party full, cooldown, no rights) into its
            -- Layer-net activity log, so a silent non-invite is diagnosable.
            self.db.layer = self.db.layer or {}
            self.db.layer.hopdebug = not self.db.layer.hopdebug
            Utils.Print("PartyLens hop debug: " .. (self.db.layer.hopdebug and "|cff66ff66ON|r" or "|cffff5555OFF|r")
                .. " (watch the Layer Net activity log)")
        elseif msg == "layerdebug" then
            -- One-shot dump of what PartyLens vs NWB think the current layer is — so a
            -- "PL shows L1, NWB shows L5" divergence is diagnosable (NWB found? current
            -- num? does NWB know our zoneUID?).
            local cur = Layer.Current(self)
            local nwbNum, nwbZone = Layer.NWBCurrent()
            local nwbKnows = cur.zoneUID and Layer.NWBNumber(cur.zoneUID) or nil
            Utils.Print("|cff88ccffPartyLens layer debug|r")
            Utils.Print(("  our: |cffffd100L%s|r  zoneUID=%s  map=%s  of %s")
                :format(tostring(cur.ordinal), tostring(cur.zoneUID), tostring(cur.mapID), tostring(cur.count)))
            Utils.Print(("  NWB installed: %s   NWB current: |cffffd100L%s|r  zone=%s")
                :format(Layer.HasNWB() and "|cff66ff66yes|r" or "|cffff5555NO (standalone numbering)|r",
                    tostring(nwbNum), tostring(nwbZone)))
            Utils.Print(("  NWB.GetLayerNum(ourZoneUID) = %s  %s")
                :format(tostring(nwbKnows),
                    nwbKnows and "" or "|cffff5555(our zoneUID not in NWB's validated set)|r"))
        else
            self:Toggle()
        end
    end

    Utils.Print(Localization.L("LOADED"))
end

PartyLens:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        self:OnAddonLoaded(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:EnsureLFGChannel()
        -- Pre-load the group-finder activity catalog so the Create picker is
        -- populated by the time the player opens it.
        LFGTool.RequestActivities()
        if UIMain.DetectAndApplySpec then
            UIMain.DetectAndApplySpec(self)
        end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Respec / point spent / dual-spec swap: refresh the detected spec.
        if UIMain.DetectAndApplySpec then
            UIMain.DetectAndApplySpec(self)
        end
    elseif event == "CHAT_MSG_CHANNEL" then
        -- Layer net FIRST: a layer request must reach the invite as fast as possible
        -- (before the Browse chat parsing) so we beat other addons to the client.
        -- args: text(1), sender(2), ..., channelBaseName(9)
        LayerNet.OnChannelChat(self, (select(1, ...)), (select(2, ...)), (select(9, ...)))
        Chat.HandleChatMessage(self, ...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        LayerNet.Observe(self, "target")
        WorldBoss.Observe(self, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        LayerNet.Observe(self, "mouseover")
        WorldBoss.Observe(self, "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- Passive layer + world-boss detection: any nearby NPC's GUID reveals the
        -- layer AND whether it's a tracked boss/rare (map lookup is cached).
        LayerNet.Observe(self, ...)
        WorldBoss.Observe(self, ...)
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        LFGTool.CaptureToolResults(self)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        Utils.Print(Localization.L("LFG_SEARCH_FAILED"))
    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if UIMain.RefreshActivityList then
            UIMain.RefreshActivityList(self)
        end
        if UIMain.RefreshAutopilotActivities then
            UIMain.RefreshAutopilotActivities(self)
        end
    elseif event == "CHAT_MSG_WHISPER" then
        -- args: message, sender, ...
        Autopilot.HandleWhisper(self, ...)
        LayerNet.OnRequest(self, (select(1, ...)), (select(2, ...)), "whisper")
    elseif event == "GROUP_ROSTER_UPDATE" then
        Autopilot.OnRosterUpdate(self)
        LayerNet.OnRosterUpdate(self)
        Reputation.OnRoster(self) -- remember who I grouped with (vouch suggestions)
        if UIMain.RefreshSummon then
            UIMain.RefreshSummon(self)
        end
    -- CHAT_MSG_ADDON is now handled by the shared mesh's dispatcher (see the
    -- Mesh:Register calls in OnAddonLoaded), which routes both hidden addon messages
    -- and realm-wide channel posts of our prefixes to Comm/LayerNet.
    elseif event == "WHO_LIST_UPDATE" then
        Who.OnWhoList(self)
    end
end)

PartyLens:RegisterEvent("ADDON_LOADED")
PartyLens:RegisterEvent("PLAYER_ENTERING_WORLD")
PartyLens:RegisterEvent("CHAT_MSG_CHANNEL")
PartyLens:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
PartyLens:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
PartyLens:RegisterEvent("LFG_LIST_SEARCH_FAILED")
PartyLens:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
PartyLens:RegisterEvent("CHAT_MSG_WHISPER")
PartyLens:RegisterEvent("GROUP_ROSTER_UPDATE")
PartyLens:RegisterEvent("PLAYER_TARGET_CHANGED")
PartyLens:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
pcall(PartyLens.RegisterEvent, PartyLens, "NAME_PLATE_UNIT_ADDED")
-- CHAT_MSG_ADDON is handled by the shared mesh (Mesh:Register), not here.
PartyLens:RegisterEvent("WHO_LIST_UPDATE")
-- Talent/spec events aren't guaranteed to exist on every client build, and an
-- unknown event name raises an error — register them defensively.
for _, ev in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    pcall(PartyLens.RegisterEvent, PartyLens, ev)
end
