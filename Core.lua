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
local Comm = LoadModule("Comm")
local Autopilot = LoadModule("Autopilot")
local UIMain = LoadModule("UIMain")
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
            local sourceLabel = entry.source == "tool" and Localization.L("SOURCE_LFG") or Localization.L("SOURCE_CHAT")
            local openText = entry.open and Localization.L("OPEN_STATUS") or Localization.L("CLOSED_STATUS")
            row.leader:SetText(leaderStr .. "   ·   " .. sourceLabel .. "  ·  " .. openText)

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

            row.message:SetText(entry.message or "")

            UIElements.SetButtonEnabled(row.whisper, hasLeader)
            UIElements.SetButtonEnabled(row.open, hasLeader)
            UIElements.SetButtonEnabled(row.who, hasLeader)
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
    UIMain.CreateMainUI(self)
    MinimapButton.SetShown(self, self.db.minimap)

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
        elseif msg == "arm" then
            Autopilot.Arm(self)
        elseif msg == "disarm" then
            Autopilot.Disarm(self)
        elseif msg == "diag" then
            LFGTool.Diagnose()
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
    elseif event == "CHAT_MSG_CHANNEL" then
        Chat.HandleChatMessage(self, ...)
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
    elseif event == "GROUP_ROSTER_UPDATE" then
        Autopilot.OnRosterUpdate(self)
    elseif event == "CHAT_MSG_ADDON" then
        -- args: prefix, text, channel, sender
        Comm.OnMessage(self, ...)
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
PartyLens:RegisterEvent("CHAT_MSG_ADDON")
