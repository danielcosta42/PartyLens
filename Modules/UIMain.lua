local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local UIElements = _G[ADDON_NAME .. "_UIElements"]
local Messaging = _G[ADDON_NAME .. "_Messaging"]
local Database = _G[ADDON_NAME .. "_Database"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local LFGTool = _G[ADDON_NAME .. "_LFGTool"]
local MinimapButton = _G[ADDON_NAME .. "_Minimap"]
local Autopilot = _G[ADDON_NAME .. "_Autopilot"]
local Roster = _G[ADDON_NAME .. "_Roster"]

local UIMain = {}

UIMain.UI_WIDTH = 760
UIMain.UI_HEIGHT = 560
UIMain.ROW_HEIGHT = 120
UIMain.CARD_INSET = 16

-- Maps an entry's content type to a short tag label + accent color.
function UIMain.ContentTagInfo(entry)
    local P = UIElements.PALETTE
    local t = entry.activityType or (entry.isRaid and "raid" or "dungeon")
    if t == "raid" then
        return Localization.L("TAB_RAIDS"), P.blue
    elseif t == "guild" then
        return Localization.L("CONTENT_GUILD"), P.gold
    elseif t == "quest" then
        return Localization.L("CONTENT_QUEST"), P.purple
    elseif t == "dungeon" then
        if entry.activity and string.find(string.lower(entry.activity), "heroic", 1, true) then
            return "HC", P.gold
        end
        return Localization.L("TAB_DUNGEONS"), P.teal
    end
    return Localization.L("CONTENT_OTHER"), P.muted
end

-- Time-based "freshness" color for the age dot.
function UIMain.FreshnessColor(age)
    local P = UIElements.PALETTE
    if age < 120 then
        return P.freshNew
    elseif age < 600 then
        return P.freshMid
    end
    return P.freshOld
end

-- Repopulates the Create-panel activity dropdown from the live C_LFGList data.
-- allowRequest must be false when called from the availability event, otherwise
-- an always-empty list would re-request forever (event storm).
function UIMain.RefreshActivityList(partyLens, allowRequest)
    local dd = partyLens.activityDropdown
    if not dd then
        return
    end
    local list = LFGTool.GetActivityList(partyLens.db.listingCategory)
    if #list == 0 then
        if allowRequest then
            -- Data not ready yet; ask the server and repopulate on the event.
            LFGTool.RequestActivities()
        end
        -- Show a tappable hint instead of an empty popup.
        dd:SetOptions({ { value = "__retry__", label = Localization.L("LISTING_PICK_EMPTY") } })
        return
    end
    dd:SetOptions(list, tonumber(partyLens.db.listingActivityID))
end

-- Top-level navigation modes.
local MODES = {
    browse = true,
    create = true,
    settings = true,
    autopilot = true,
}

-- Content categories shown as the unified filter row (order matters).
local CONTENT_CATEGORIES = {
    { key = "all", labelKey = "FILTER_ALL", color = "teal", width = 56 },
    { key = "dungeon", labelKey = "TAB_DUNGEONS", color = "teal", width = 96 },
    { key = "raid", labelKey = "TAB_RAIDS", color = "blue", width = 72 },
    { key = "guild", labelKey = "CONTENT_GUILD", color = "gold", width = 66 },
    { key = "quest", labelKey = "CONTENT_QUEST", color = "purple", width = 72 },
    { key = "other", labelKey = "CONTENT_OTHER", color = "coral", width = 66 },
}

local function SaveEditBox(editBox, key, partyLens)
    Database.SaveField(editBox, key, partyLens)
end

local function ToggleDB(check, key, partyLens, refresh)
    check:SetChecked(not check:GetChecked())
    partyLens.db[key] = check:GetChecked() and true or false
    if refresh and partyLens.Refresh then
        partyLens:Refresh()
    end
end

local function ShowFrame(frame)
    if frame then
        frame:Show()
    end
end

local function HideFrame(frame)
    if frame then
        frame:Hide()
    end
end

local function UpdateIntentFilterButtons(partyLens)
    local active = partyLens.db.intentFilter or "all"
    for key, button in pairs(partyLens.intentFilterButtons or {}) do
        button:SetActive(key == active)
    end
end

local function UpdateContentFilterButtons(partyLens)
    if partyLens.categoryDropdown then
        partyLens.categoryDropdown:SetValue(partyLens.db.contentFilter or "all", false)
    end
end

local function SetIntentFilter(partyLens, filter)
    partyLens.db.intentFilter = filter
    UpdateIntentFilterButtons(partyLens)
    partyLens:Refresh()
end

local function SetContentFilter(partyLens, filter)
    partyLens.db.contentFilter = filter
    UpdateContentFilterButtons(partyLens)
    partyLens:Refresh()
end

function UIMain.SetMode(partyLens, mode)
    if not mode or not partyLens.frame then
        return
    end
    if not MODES[mode] then
        mode = "browse"
    end

    partyLens.mode = mode
    partyLens.db.mode = mode

    if partyLens.createIcon then
        partyLens.createIcon:SetActive(mode == "create")
    end
    if partyLens.settingsIcon then
        partyLens.settingsIcon:SetActive(mode == "settings")
    end
    if partyLens.autopilotIcon then
        partyLens.autopilotIcon:SetActive(mode == "autopilot")
    end

    if mode == "create" then
        HideFrame(partyLens.resultsPanel)
        ShowFrame(partyLens.createPanel)
        HideFrame(partyLens.settingsPanel)
        HideFrame(partyLens.autopilotPanel)
        HideFrame(partyLens.countPill)
        UIMain.RefreshActivityList(partyLens, true)
    elseif mode == "settings" then
        HideFrame(partyLens.resultsPanel)
        HideFrame(partyLens.createPanel)
        ShowFrame(partyLens.settingsPanel)
        HideFrame(partyLens.autopilotPanel)
        HideFrame(partyLens.countPill)
    elseif mode == "autopilot" then
        HideFrame(partyLens.resultsPanel)
        HideFrame(partyLens.createPanel)
        HideFrame(partyLens.settingsPanel)
        ShowFrame(partyLens.autopilotPanel)
        HideFrame(partyLens.countPill)
        UIMain.RefreshAutopilotActivities(partyLens, true)
        UIMain.RefreshAutopilot(partyLens)
    else
        ShowFrame(partyLens.resultsPanel)
        HideFrame(partyLens.createPanel)
        HideFrame(partyLens.settingsPanel)
        HideFrame(partyLens.autopilotPanel)
        ShowFrame(partyLens.countPill)
        partyLens:Refresh()
    end
end

function UIMain.CreateResultRow(partyLens, index)
    local P = UIElements.PALETTE
    local inset = UIMain.CARD_INSET
    local cardHeight = UIMain.ROW_HEIGHT - 8

    local row = UIElements.CreatePanel(partyLens.content, "PartyLensResultRow" .. index, P.panel2, P.stroke)
    row:SetSize(UIMain.UI_WIDTH - 66, cardHeight)
    row:EnableMouse(true)

    -- Left accent stripe (color reflects intent / open state).
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", 0, 0)
    row.accent:SetWidth(3)
    UIElements.SetTextureColor(row.accent, P.teal)

    -- Top row: content tag + intent badge (left); fill bar + age (right).
    row.tag = UIElements.CreateChip(row, 86, 20)
    row.tag:EnableDot()
    row.tag:SetPoint("TOPLEFT", inset, -11)

    row.intent = UIElements.CreateChip(row, 52, 20)
    row.intent:SetPoint("LEFT", row.tag, "RIGHT", 7, 0)

    -- "PL" badge: marks a fellow PartyLens user (mesh advantage made visible).
    row.plBadge = UIElements.CreateChip(row, 30, 20)
    row.plBadge:SetPoint("LEFT", row.intent, "RIGHT", 7, 0)
    row.plBadge:SetLabel("PL")
    row.plBadge:Hide()

    row.fill = UIElements.CreateFillBar(row, 104, 16)
    row.fill:SetPoint("TOPRIGHT", -90, -12)

    row.time = UIElements.CreateLabel(row, "", 10, P.muted)
    row.time:SetPoint("TOPRIGHT", row.fill, "BOTTOMRIGHT", 0, -7)
    row.time:SetJustifyH("RIGHT")

    row.freshDot = row:CreateTexture(nil, "ARTWORK")
    row.freshDot:SetSize(7, 7)
    row.freshDot:SetPoint("RIGHT", row.time, "LEFT", -5, 0)
    UIElements.SetTextureColor(row.freshDot, P.freshOld)

    -- Activity title.
    row.title = UIElements.CreateLabel(row, "", 15, P.text)
    row.title:SetPoint("TOPLEFT", inset, -35)
    row.title:SetPoint("RIGHT", row.fill, "LEFT", -12, 0)
    row.title:SetJustifyH("LEFT")

    -- Leader (class colored) + class + source/open.
    row.leader = UIElements.CreateLabel(row, "", 11, P.muted)
    row.leader:SetPoint("TOPLEFT", inset, -57)
    row.leader:SetPoint("RIGHT", row.fill, "LEFT", -12, 0)
    row.leader:SetJustifyH("LEFT")

    -- Needs row: label + up to three role pips.
    row.needsLabel = UIElements.CreateLabel(row, "", 10, P.muted)
    row.needsLabel:SetPoint("TOPLEFT", inset, -80)

    row.pips = {}
    for i = 1, 3 do
        local pip = UIElements.CreateRolePip(row, 16)
        pip:SetPoint("TOPLEFT", 64 + (i - 1) * 22, -78)
        pip:Hide()
        row.pips[i] = pip
    end

    -- Free-text message.
    row.message = UIElements.CreateLabel(row, "", 11, P.faint)
    row.message:SetPoint("TOPLEFT", inset, -96)
    row.message:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    row.message:SetHeight(14)
    row.message:SetJustifyH("LEFT")

    -- Action buttons (right column).
    row.whisper = UIElements.CreateButton(row, Localization.L("SEND_WHISPER"), 60, 20, P.teal)
    row.whisper:SetPoint("TOPRIGHT", -14, -12)
    row.whisper:SetScript("OnClick", function(button)
        Messaging.SendWhisper(partyLens, button:GetParent().entry)
    end)

    row.open = UIElements.CreateButton(row, Localization.L("EDIT_WHISPER"), 60, 20, P.blue)
    row.open:SetPoint("TOP", row.whisper, "BOTTOM", 0, -6)
    row.open:SetScript("OnClick", function(button)
        Messaging.OpenWhisper(partyLens, button:GetParent().entry)
    end)

    row.who = UIElements.CreateButton(row, Localization.L("WHO_CHECK"), 60, 20, P.gold)
    row.who:SetPoint("TOP", row.open, "BOTTOM", 0, -6)
    row.who:SetScript("OnClick", function(button)
        local entry = button:GetParent().entry
        if entry and entry.leader then
            -- The bare global SendWho does not exist on the 2.5.x client; the
            -- supported API is C_FriendList.SendWho. Use an exact-name filter and
            -- strip any "-Realm" suffix so the query matches the character.
            local name = (entry.leaderDisplay and entry.leaderDisplay ~= "" and entry.leaderDisplay)
                or Utils.PlayerShortName(entry.leader)
            if C_FriendList and C_FriendList.SendWho then
                C_FriendList.SendWho('n-"' .. name .. '"')
            elseif SendWho then
                SendWho('n-"' .. name .. '"')
            end
        end
    end)

    -- Hover lift.
    row:SetScript("OnEnter", function(self)
        UIElements.SetTextureColor(self.bg, P.panelHover)
    end)
    row:SetScript("OnLeave", function(self)
        UIElements.SetTextureColor(self.bg, P.panel2)
    end)

    row:Hide()
    partyLens.rows[index] = row
    return row
end

-- Toggles a header action mode (create/settings); clicking the active one
-- returns to browse.
local function ToggleMode(partyLens, mode)
    if partyLens.mode == mode then
        UIMain.SetMode(partyLens, "browse")
    else
        UIMain.SetMode(partyLens, mode)
    end
end

local function SetRoleFilter(partyLens, role, value)
    partyLens.db.roleFilter = partyLens.db.roleFilter or {}
    partyLens.db.roleFilter[role] = value and true or false
    partyLens:Refresh()
end

local function CreateResultsPanel(partyLens, frame)
    local panel = CreateFrame("Frame", "PartyLensResultsPanel", frame)
    partyLens.resultsPanel = panel
    panel:SetPoint("TOPLEFT", 18, -92)
    panel:SetPoint("BOTTOMRIGHT", -18, 18)

    -- Row 1: search + category dropdown (left) and refresh + join (right).
    local query, queryShell = UIElements.CreateEditBox(panel, "PartyLensQueryEditBox", 300, 32)
    partyLens.queryBox = query
    queryShell:SetPoint("TOPLEFT", 0, -10)
    query:SetText(partyLens.db.query or "")
    query:SetPlaceholder(Localization.L("SEARCH_PLACEHOLDER"))
    query:SetScript("OnTextChanged", function(editBox)
        partyLens.db.query = editBox:GetText()
        editBox:UpdatePlaceholder()
        -- Debounce so a full filter+sort+relayout does not run on every keystroke.
        if partyLens._queryTimer and partyLens._queryTimer.Cancel then
            partyLens._queryTimer:Cancel()
        end
        if C_Timer and C_Timer.NewTimer then
            partyLens._queryTimer = C_Timer.NewTimer(0.25, function()
                partyLens:Refresh()
            end)
        else
            partyLens:Refresh()
        end
    end)

    local category = UIElements.CreateDropdown(panel, 150, 32, UIElements.PALETTE.teal)
    partyLens.categoryDropdown = category
    category:SetPoint("LEFT", queryShell, "RIGHT", 10, 0)
    local categoryOptions = {}
    for _, cat in ipairs(CONTENT_CATEGORIES) do
        categoryOptions[#categoryOptions + 1] = { value = cat.key, label = Localization.L(cat.labelKey) }
    end
    category:SetOptions(categoryOptions, partyLens.db.contentFilter or "all")
    category.onSelect = function(value)
        SetContentFilter(partyLens, value)
    end

    local join = UIElements.CreateButton(panel, Localization.L("JOIN_LFG"), 96, 32, UIElements.PALETTE.gold)
    join:SetPoint("TOPRIGHT", 0, -10)
    join:SetScript("OnClick", function()
        Messaging.JoinLookingForGroup()
    end)

    local refresh = UIElements.CreateButton(panel, Localization.L("REFRESH"), 100, 32, UIElements.PALETTE.teal)
    refresh:SetPoint("RIGHT", join, "LEFT", -8, 0)
    refresh:SetScript("OnClick", function()
        partyLens:RefreshGroups()
    end)

    -- Row 2: role-need pips (filter by the role a group needs) + LFG/LFM toggle.
    local needsLabel = UIElements.CreateLabel(panel, Localization.L("NEEDS_LABEL"), 11, UIElements.PALETTE.muted)
    needsLabel:SetPoint("TOPLEFT", 0, -55)

    partyLens.roleToggles = {}
    local prevPip
    for _, role in ipairs({ "tank", "heal", "dps" }) do
        local pip = UIElements.CreateRoleToggle(panel, role, 20)
        if prevPip then
            pip:SetPoint("LEFT", prevPip, "RIGHT", 6, 0)
        else
            pip:SetPoint("TOPLEFT", 62, -53)
        end
        pip:SetSelected(partyLens.db.roleFilter and partyLens.db.roleFilter[role])
        pip.onToggle = function(r, v) SetRoleFilter(partyLens, r, v) end
        partyLens.roleToggles[role] = pip
        prevPip = pip
    end

    local intentLabel = UIElements.CreateLabel(panel, Localization.L("INTENT_HEADER"), 11, UIElements.PALETTE.muted)
    intentLabel:SetPoint("TOPLEFT", 176, -55)

    local intentOrder = {
        { key = "all", labelKey = "FILTER_ALL", color = "teal", width = 56 },
        { key = "players", labelKey = "INTENT_PLAYER", color = "gold", width = 50 },
        { key = "groups", labelKey = "INTENT_GROUP", color = "blue", width = 50 },
    }
    partyLens.intentFilterButtons = {}
    local prevIntent
    for _, intentOpt in ipairs(intentOrder) do
        local intentKey = intentOpt.key
        local button = UIElements.CreateButton(panel, Localization.L(intentOpt.labelKey), intentOpt.width, 24, UIElements.PALETTE[intentOpt.color])
        if prevIntent then
            button:SetPoint("LEFT", prevIntent, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", 250, -53)
        end
        button:SetScript("OnClick", function()
            SetIntentFilter(partyLens, intentKey)
        end)
        partyLens.intentFilterButtons[intentKey] = button
        prevIntent = button
    end
    UpdateIntentFilterButtons(partyLens)

    local scrollFrame = CreateFrame("ScrollFrame", "PartyLensScrollFrame", panel)
    partyLens.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", 0, -86)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(scroll, delta)
        local current = scroll:GetVerticalScroll()
        local maxScroll = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta * 38))))
    end)

    local content = CreateFrame("Frame", "PartyLensScrollContent", scrollFrame)
    partyLens.content = content
    content:SetSize(UIMain.UI_WIDTH - 66, 1)
    scrollFrame:SetScrollChild(content)

    -- Empty-state shown over the scroll area when there are no results.
    local empty = UIElements.CreateLabel(panel, Localization.L("EMPTY_RESULTS"), 12, UIElements.PALETTE.faint)
    empty:SetPoint("TOP", scrollFrame, "TOP", 0, -48)
    empty:SetPoint("LEFT", scrollFrame, "LEFT", 30, 0)
    empty:SetPoint("RIGHT", scrollFrame, "RIGHT", -30, 0)
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("TOP")
    empty:Hide()
    partyLens.emptyState = empty

    partyLens.rows = {}
end

local function CreateCreatePanel(partyLens, frame)
    local panel = UIElements.CreatePanel(frame, "PartyLensCreatePanel", UIElements.PALETTE.panel, UIElements.PALETTE.stroke)
    partyLens.createPanel = panel
    panel:SetPoint("TOPLEFT", 18, -92)
    panel:SetPoint("BOTTOMRIGHT", -18, 18)

    local title = UIElements.CreateLabel(panel, Localization.L("LISTING_SECTION_TITLE"), 16, UIElements.PALETTE.text)
    title:SetPoint("TOPLEFT", 14, -14)

    local categoryLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_CATEGORY_LABEL"), 10, UIElements.PALETTE.muted)
    categoryLabel:SetPoint("TOPLEFT", 14, -50)

    local dungeonButton = UIElements.CreateButton(panel, Localization.L("TAB_DUNGEONS"), 100, 30, UIElements.PALETTE.teal)
    partyLens.createDungeonButton = dungeonButton
    dungeonButton:SetPoint("TOPLEFT", 14, -67)
    dungeonButton:SetScript("OnClick", function()
        partyLens.db.listingCategory = "dungeons"
        dungeonButton:SetActive(true)
        partyLens.createRaidButton:SetActive(false)
        UIMain.RefreshActivityList(partyLens, true)
    end)

    local raidButton = UIElements.CreateButton(panel, Localization.L("TAB_RAIDS"), 88, 30, UIElements.PALETTE.blue)
    partyLens.createRaidButton = raidButton
    raidButton:SetPoint("LEFT", dungeonButton, "RIGHT", 8, 0)
    raidButton:SetScript("OnClick", function()
        partyLens.db.listingCategory = "raids"
        raidButton:SetActive(true)
        dungeonButton:SetActive(false)
        UIMain.RefreshActivityList(partyLens, true)
    end)

    if partyLens.db.listingCategory == "raids" then
        dungeonButton:SetActive(false)
        raidButton:SetActive(true)
    else
        dungeonButton:SetActive(true)
        raidButton:SetActive(false)
    end

    -- Activity picker: a live list from C_LFGList (no manual numeric ID typing).
    local activityLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_ACTIVITY_LABEL"), 10, UIElements.PALETTE.muted)
    activityLabel:SetPoint("TOPLEFT", 14, -112)
    local activityDropdown = UIElements.CreateDropdown(panel, 250, 30, UIElements.PALETTE.blue)
    partyLens.activityDropdown = activityDropdown
    activityDropdown.placeholder = Localization.L("LISTING_PICK")
    activityDropdown:SetPoint("TOPLEFT", 14, -129)
    activityDropdown.onSelect = function(value)
        if value == "__retry__" then
            LFGTool.RequestActivities()
            UIMain.RefreshActivityList(partyLens, true)
            return
        end
        partyLens.db.listingActivityID = tostring(value)
    end

    local ilvlLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_ILVL_LABEL"), 10, UIElements.PALETTE.muted)
    ilvlLabel:SetPoint("TOPLEFT", activityDropdown, "TOPRIGHT", 14, 17)
    local ilvl, ilvlShell = UIElements.CreateEditBox(panel, "PartyLensListingIlvlEditBox", 94, 30)
    partyLens.listingIlvlBox = ilvl
    ilvlShell:SetPoint("LEFT", activityDropdown, "RIGHT", 14, 0)
    ilvl:SetText(partyLens.db.listingMinItemLevel or "0")
    ilvl:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "listingMinItemLevel", partyLens)
    end)

    UIMain.RefreshActivityList(partyLens, true)

    local autoAccept = UIElements.CreateToggle(panel, Localization.L("AUTO_ACCEPT_TOGGLE"), 124)
    partyLens.listingAutoAcceptCheck = autoAccept
    autoAccept:SetPoint("LEFT", ilvlShell, "RIGHT", 14, 0)
    autoAccept:SetChecked(partyLens.db.listingAutoAccept)
    autoAccept:SetScript("OnClick", function(check)
        ToggleDB(check, "listingAutoAccept", partyLens, false)
    end)

    local privateGroup = UIElements.CreateToggle(panel, Localization.L("PRIVATE_GROUP_TOGGLE"), 96)
    partyLens.listingPrivateCheck = privateGroup
    privateGroup:SetPoint("LEFT", autoAccept, "RIGHT", 8, 0)
    privateGroup:SetChecked(partyLens.db.listingPrivate)
    privateGroup:SetScript("OnClick", function(check)
        ToggleDB(check, "listingPrivate", partyLens, false)
    end)

    local listingTitleLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_TITLE_LABEL"), 10, UIElements.PALETTE.muted)
    listingTitleLabel:SetPoint("TOPLEFT", 14, -177)
    local listingTitle, listingTitleShell = UIElements.CreateEditBox(panel, "PartyLensListingTitleEditBox", 684, 32)
    partyLens.listingTitleBox = listingTitle
    listingTitleShell:SetPoint("TOPLEFT", 14, -194)
    listingTitle:SetMaxLetters(60)
    listingTitle:SetText(partyLens.db.listingTitle or "")
    listingTitle:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "listingTitle", partyLens)
    end)

    local listingCommentLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_COMMENT_LABEL"), 10, UIElements.PALETTE.muted)
    listingCommentLabel:SetPoint("TOPLEFT", 14, -242)
    local listingComment, listingCommentShell = UIElements.CreateEditBox(panel, "PartyLensListingCommentEditBox", 684, 32)
    partyLens.listingCommentBox = listingComment
    listingCommentShell:SetPoint("TOPLEFT", 14, -259)
    listingComment:SetMaxLetters(180)
    listingComment:SetText(partyLens.db.listingComment or "")
    listingComment:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "listingComment", partyLens)
    end)

    local create = UIElements.CreateButton(panel, Localization.L("CREATE_LFG_LISTING"), 138, 32, UIElements.PALETTE.gold)
    create:SetPoint("TOPLEFT", 14, -316)
    create:SetScript("OnClick", function()
        LFGTool.CreateListing(partyLens)
    end)

    local announce = UIElements.CreateButton(panel, Localization.L("ANNOUNCE_CHAT_LISTING"), 138, 32, UIElements.PALETTE.teal)
    announce:SetPoint("LEFT", create, "RIGHT", 10, 0)
    announce:SetScript("OnClick", function()
        LFGTool.AnnounceListing(partyLens)
    end)

    local hint = UIElements.CreateLabel(panel, Localization.L("LISTING_HINT"), 10, UIElements.PALETTE.muted)
    hint:SetPoint("TOPLEFT", 14, -365)
    hint:SetPoint("RIGHT", -14, 0)
end

-- Maps the runtime autopilot state to a localized status label.
local AP_STATE_LABEL = {
    idle = "AP_STATUS_IDLE",
    searching = "AP_STATUS_SEARCHING",
    assembling = "AP_STATUS_ASSEMBLING",
    ready = "AP_STATUS_READY",
}

local function UpdateAutopilotRole(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    local role = partyLens.db.autopilot.role
    ap.roleBuildBtn:SetActive(role == "build")
    ap.roleFindBtn:SetActive(role == "find")
    if role == "build" then
        ShowFrame(ap.buildBox)
        HideFrame(ap.findBox)
    else
        HideFrame(ap.buildBox)
        ShowFrame(ap.findBox)
    end
end

local function UpdateAutopilotTier(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    for key, btn in pairs(ap.tierBtns) do
        btn:SetActive(key == partyLens.db.autopilot.tier)
    end
end

local function UpdateAutopilotContent(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    for key, btn in pairs(ap.contentBtns) do
        btn:SetActive(key == partyLens.db.autopilot.activityType)
    end
end

local function UpdateAutopilotMyRole(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    for key, btn in pairs(ap.myRoleBtns) do
        btn:SetActive(key == partyLens.db.autopilot.myRole)
    end
end

local function SaveAutopilotNumber(editBox, key, partyLens, minValue)
    local n = tonumber(Utils.Trim(editBox:GetText())) or 0
    partyLens.db.autopilot[key] = math.max(minValue or 0, n)
end

local function CreateAutopilotPanel(partyLens, frame)
    local P = UIElements.PALETTE
    local panel = UIElements.CreatePanel(frame, "PartyLensAutopilotPanel", P.panel, P.stroke)
    partyLens.autopilotPanel = panel
    panel:SetPoint("TOPLEFT", 18, -92)
    panel:SetPoint("BOTTOMRIGHT", -18, 18)

    local ap = {}
    partyLens.ap = ap

    local title = UIElements.CreateLabel(panel, Localization.L("AP_TITLE"), 16, P.text)
    title:SetPoint("TOPLEFT", 14, -12)

    -- Live count of fellow PartyLens users seen — the visible network reward.
    ap.meshLabel = UIElements.CreateLabel(panel, "", 11, P.teal)
    ap.meshLabel:SetPoint("TOPRIGHT", -14, -14)
    ap.meshLabel:SetJustifyH("RIGHT")

    local subtitle = UIElements.CreateLabel(panel, Localization.L("AP_HINT"), 10, P.muted)
    subtitle:SetPoint("TOPLEFT", 14, -32)
    subtitle:SetPoint("RIGHT", -14, 0)
    subtitle:SetJustifyH("LEFT")

    -- Role selector: build (recruit) vs find (apply).
    ap.roleBuildBtn = UIElements.CreateButton(panel, Localization.L("AP_ROLE_BUILD"), 168, 28, P.teal)
    ap.roleBuildBtn:SetPoint("TOPLEFT", 14, -52)
    ap.roleBuildBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "build"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)
    ap.roleFindBtn = UIElements.CreateButton(panel, Localization.L("AP_ROLE_FIND"), 168, 28, P.gold)
    ap.roleFindBtn:SetPoint("LEFT", ap.roleBuildBtn, "RIGHT", 8, 0)
    ap.roleFindBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "find"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    -- Automation tier.
    local tierLabel = UIElements.CreateLabel(panel, Localization.L("AP_TIER_LABEL"), 10, P.muted)
    tierLabel:SetPoint("TOPLEFT", 14, -88)
    ap.tierBtns = {}
    local tierOrder = {
        { key = "advisor", labelKey = "AP_TIER_ADVISOR", color = P.blue },
        { key = "assisted", labelKey = "AP_TIER_ASSISTED", color = P.teal },
        { key = "full", labelKey = "AP_TIER_FULL", color = P.coral },
    }
    local prevTier
    for _, t in ipairs(tierOrder) do
        local btn = UIElements.CreateButton(panel, Localization.L(t.labelKey), 96, 24, t.color)
        if prevTier then
            btn:SetPoint("LEFT", prevTier, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 90, -86)
        end
        local key = t.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.tier = key
            UpdateAutopilotTier(partyLens)
        end)
        ap.tierBtns[t.key] = btn
        prevTier = btn
    end

    -- Content type + free-text activity filter.
    local contentLabel = UIElements.CreateLabel(panel, Localization.L("AP_CONTENT_LABEL"), 10, P.muted)
    contentLabel:SetPoint("TOPLEFT", 14, -120)
    ap.contentBtns = {}
    local contentOrder = {
        { key = "dungeon", labelKey = "TAB_DUNGEONS", color = P.teal, width = 92 },
        { key = "raid", labelKey = "TAB_RAIDS", color = P.blue, width = 72 },
        { key = "any", labelKey = "FILTER_ALL", color = P.purple, width = 56 },
    }
    local prevContent
    for _, c in ipairs(contentOrder) do
        local btn = UIElements.CreateButton(panel, Localization.L(c.labelKey), c.width, 24, c.color)
        if prevContent then
            btn:SetPoint("LEFT", prevContent, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 90, -118)
        end
        local key = c.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.activityType = key
            UpdateAutopilotContent(partyLens)
            UIMain.RefreshAutopilotActivities(partyLens, true)
        end)
        ap.contentBtns[c.key] = btn
        prevContent = btn
    end

    -- Activity picker: a live list from C_LFGList (no free-text typing). Picking
    -- one stores its name as the match filter; "Any" clears it.
    local activityDropdown = UIElements.CreateDropdown(panel, 244, 26, P.purple)
    ap.activityDropdown = activityDropdown
    activityDropdown.placeholder = Localization.L("AP_ANY_ACTIVITY")
    activityDropdown:SetPoint("TOPLEFT", 348, -117)
    activityDropdown.onSelect = function(value)
        if value == "__retry__" then
            LFGTool.RequestActivities()
            UIMain.RefreshAutopilotActivities(partyLens, true)
            return
        elseif value == "__any__" then
            partyLens.db.autopilot.activityFilter = ""
            partyLens.db.autopilot.activityID = nil
            return
        end
        partyLens.db.autopilot.activityID = tonumber(value)
        local label
        for _, opt in ipairs(activityDropdown.options) do
            if opt.value == value then
                label = opt.label
                break
            end
        end
        partyLens.db.autopilot.activityFilter = label or ""
    end

    -- ---- Build-mode controls (recruit) ------------------------------------
    local buildBox = CreateFrame("Frame", nil, panel)
    ap.buildBox = buildBox
    buildBox:SetPoint("TOPLEFT", 14, -150)
    buildBox:SetPoint("TOPRIGHT", -14, -150)
    buildBox:SetHeight(64)

    local compLabel = UIElements.CreateLabel(buildBox, Localization.L("AP_NEEDS_LABEL"), 10, P.muted)
    compLabel:SetPoint("TOPLEFT", 0, 0)

    local function CompBox(name, key, x, role)
        local pip = UIElements.CreateRolePip(buildBox, 18)
        pip:SetRole(role)
        pip:SetPoint("TOPLEFT", x, -18)
        local box, shell = UIElements.CreateEditBox(buildBox, name, 36, 26)
        shell:SetPoint("LEFT", pip, "RIGHT", 4, 0)
        box:SetText(tostring(partyLens.db.autopilot[key] or 0))
        box:SetScript("OnTextChanged", function(editBox)
            SaveAutopilotNumber(editBox, key, partyLens, 0)
        end)
        return box
    end
    ap.needT = CompBox("PartyLensAPNeedTank", "needTank", 0, "tank")
    ap.needH = CompBox("PartyLensAPNeedHeal", "needHeal", 64, "heal")
    ap.needD = CompBox("PartyLensAPNeedDps", "needDps", 128, "dps")

    local kwLabel = UIElements.CreateLabel(buildBox, Localization.L("AP_INVITE_KEYWORD_LABEL"), 10, P.muted)
    kwLabel:SetPoint("TOPLEFT", 200, 0)
    local kwBox, kwShell = UIElements.CreateEditBox(buildBox, "PartyLensAPKeyword", 90, 26)
    kwShell:SetPoint("TOPLEFT", 200, -18)
    kwBox:SetText(partyLens.db.autopilot.inviteKeyword or "inv")
    kwBox:SetScript("OnTextChanged", function(editBox)
        partyLens.db.autopilot.inviteKeyword = Utils.Trim(editBox:GetText())
    end)

    ap.autoInviteToggle = UIElements.CreateToggle(buildBox, Localization.L("AP_AUTO_INVITE"), 118)
    ap.autoInviteToggle:SetPoint("TOPLEFT", 300, -18)
    ap.autoInviteToggle:SetChecked(partyLens.db.autopilot.autoInvite)
    ap.autoInviteToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoInvite = check:GetChecked()
    end)

    ap.autoAnnounceToggle = UIElements.CreateToggle(buildBox, Localization.L("AP_AUTO_ANNOUNCE"), 160)
    ap.autoAnnounceToggle:SetPoint("TOPLEFT", 426, -18)
    ap.autoAnnounceToggle:SetChecked(partyLens.db.autopilot.autoAnnounce)
    ap.autoAnnounceToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoAnnounce = check:GetChecked()
    end)

    -- ---- Find-mode controls (apply) ---------------------------------------
    local findBox = CreateFrame("Frame", nil, panel)
    ap.findBox = findBox
    findBox:SetPoint("TOPLEFT", 14, -150)
    findBox:SetPoint("TOPRIGHT", -14, -150)
    findBox:SetHeight(64)

    local myRoleLabel = UIElements.CreateLabel(findBox, Localization.L("AP_MYROLE_LABEL"), 10, P.muted)
    myRoleLabel:SetPoint("TOPLEFT", 0, 0)
    ap.myRoleBtns = {}
    local roleOrder = {
        { key = "tank", labelKey = "ROLE_TANK", color = P.roleTank },
        { key = "heal", labelKey = "ROLE_HEAL", color = P.roleHeal },
        { key = "dps", labelKey = "ROLE_DPS", color = P.roleDps },
    }
    local prevRole
    for _, r in ipairs(roleOrder) do
        local btn = UIElements.CreateButton(findBox, Localization.L(r.labelKey), 70, 24, r.color)
        if prevRole then
            btn:SetPoint("LEFT", prevRole, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 0, -18)
        end
        local key = r.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.myRole = key
            UpdateAutopilotMyRole(partyLens)
        end)
        ap.myRoleBtns[r.key] = btn
        prevRole = btn
    end

    ap.autoWhisperToggle = UIElements.CreateToggle(findBox, Localization.L("AP_AUTO_WHISPER"), 130)
    ap.autoWhisperToggle:SetPoint("TOPLEFT", 248, -18)
    ap.autoWhisperToggle:SetChecked(partyLens.db.autopilot.autoWhisper)
    ap.autoWhisperToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoWhisper = check:GetChecked()
    end)

    -- ---- Common safety row -------------------------------------------------
    local cdLabel = UIElements.CreateLabel(panel, Localization.L("AP_COOLDOWN_LABEL"), 10, P.muted)
    cdLabel:SetPoint("TOPLEFT", 14, -222)
    local cdBox, cdShell = UIElements.CreateEditBox(panel, "PartyLensAPCooldown", 50, 26)
    cdShell:SetPoint("TOPLEFT", 120, -219)
    cdBox:SetText(tostring(partyLens.db.autopilot.whisperCooldown or 20))
    cdBox:SetScript("OnTextChanged", function(editBox)
        SaveAutopilotNumber(editBox, "whisperCooldown", partyLens, 5)
    end)

    local ilvlLabel = UIElements.CreateLabel(panel, Localization.L("LISTING_ILVL_LABEL"), 10, P.muted)
    ilvlLabel:SetPoint("TOPLEFT", 200, -222)
    local ilvlBox, ilvlShell = UIElements.CreateEditBox(panel, "PartyLensAPIlvl", 50, 26)
    ilvlShell:SetPoint("TOPLEFT", 270, -219)
    ilvlBox:SetText(tostring(partyLens.db.autopilot.minIlvl or 0))
    ilvlBox:SetScript("OnTextChanged", function(editBox)
        SaveAutopilotNumber(editBox, "minIlvl", partyLens, 0)
    end)

    -- ---- Arm / GO / status -------------------------------------------------
    ap.armBtn = UIElements.CreateButton(panel, Localization.L("AP_ARM"), 200, 34, P.teal)
    ap.armBtn:SetPoint("TOPLEFT", 14, -252)
    ap.armBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    ap.goBtn = UIElements.CreateButton(panel, Localization.L("AP_GO"), 70, 34, P.gold)
    ap.goBtn:SetPoint("LEFT", ap.armBtn, "RIGHT", 8, 0)
    ap.goBtn:SetScript("OnClick", function()
        Autopilot.PressGo(partyLens)
    end)
    ap.goBtn:Hide()

    ap.statusLabel = UIElements.CreateLabel(panel, "", 12, P.text)
    ap.statusLabel:SetPoint("LEFT", ap.goBtn, "RIGHT", 12, 0)
    ap.statusLabel:SetPoint("RIGHT", -14, 0)
    ap.statusLabel:SetJustifyH("LEFT")

    -- ---- Roster / summon ---------------------------------------------------
    local divider = UIElements.CreateDivider(panel)
    divider:SetPoint("TOPLEFT", 14, -298)
    divider:SetPoint("TOPRIGHT", -14, -298)

    ap.rosterLabel = UIElements.CreateLabel(panel, "", 11, P.text)
    ap.rosterLabel:SetPoint("TOPLEFT", 14, -310)
    ap.rosterLabel:SetPoint("RIGHT", -120, 0)
    ap.rosterLabel:SetJustifyH("LEFT")

    ap.needLabel = UIElements.CreateLabel(panel, "", 11, P.gold)
    ap.needLabel:SetPoint("TOPLEFT", 14, -330)
    ap.needLabel:SetPoint("RIGHT", -120, 0)
    ap.needLabel:SetJustifyH("LEFT")

    ap.announceBtn = UIElements.CreateButton(panel, Localization.L("AP_ANNOUNCE_BTN"), 104, 26, P.gold)
    ap.announceBtn:SetPoint("TOPRIGHT", -14, -310)
    ap.announceBtn:SetScript("OnClick", function()
        Autopilot.AnnounceReady(partyLens)
    end)

    -- ---- Live log ----------------------------------------------------------
    local logTitle = UIElements.CreateLabel(panel, Localization.L("AP_LOG_TITLE"), 10, P.muted)
    logTitle:SetPoint("TOPLEFT", 14, -352)
    ap.logLines = {}
    for i = 1, 6 do
        local line = UIElements.CreateLabel(panel, "", 10, P.faint)
        line:SetPoint("TOPLEFT", 14, -366 - (i - 1) * 14)
        line:SetPoint("RIGHT", -14, 0)
        line:SetJustifyH("LEFT")
        line:Hide()
        ap.logLines[i] = line
    end

    UpdateAutopilotRole(partyLens)
    UpdateAutopilotTier(partyLens)
    UpdateAutopilotContent(partyLens)
    UpdateAutopilotMyRole(partyLens)
    UIMain.RefreshAutopilotActivities(partyLens, true)
end

local function ActivityIsHeroic(label)
    local l = string.lower(label or "")
    return string.find(l, "heroic", 1, true)
        or string.find(l, "heroica", 1, true)
        or string.find(l, "%f[%a]hc%f[%A]") ~= nil
end

-- Buckets one activity into a {key, label, order} category, adapting to the
-- selected content type. maxPlayers is reliable; heroic detection from the name
-- is best-effort (falls back to a single "Dungeons" group below).
local function ActivityCategory(item, content)
    if content == "dungeon" then
        if ActivityIsHeroic(item.label) then
            return "heroic", Localization.L("AP_CAT_HEROIC"), 2
        end
        return "normal", Localization.L("AP_CAT_NORMAL"), 1
    elseif content == "raid" then
        local size = item.maxPlayers or 0
        return "r" .. size, Localization.L("AP_CAT_RAID_SIZE", size), size
    else
        if (item.maxPlayers or 0) > 5 then
            return "raids", Localization.L("TAB_RAIDS"), 2
        end
        return "dungeons", Localization.L("TAB_DUNGEONS"), 1
    end
end

-- Repopulates the autopilot activity picker from the live C_LFGList catalog,
-- scoped to the selected content type and grouped under category headers.
-- Mirrors RefreshActivityList: allowRequest must be false when called from the
-- availability event to avoid a request storm.
function UIMain.RefreshAutopilotActivities(partyLens, allowRequest)
    local ap = partyLens.ap
    if not ap or not ap.activityDropdown then
        return
    end

    local content = partyLens.db.autopilot.activityType
    local lists
    if content == "raid" then
        lists = { LFGTool.GetActivityList("raids") }
    elseif content == "dungeon" then
        lists = { LFGTool.GetActivityList("dungeons") }
    else
        lists = { LFGTool.GetActivityList("dungeons"), LFGTool.GetActivityList("raids") }
    end

    -- Flatten + dedup.
    local items, seen = {}, {}
    for _, list in ipairs(lists) do
        for _, item in ipairs(list) do
            if not seen[item.value] then
                seen[item.value] = true
                items[#items + 1] = item
            end
        end
    end

    local options = { { value = "__any__", label = Localization.L("AP_ANY_ACTIVITY") } }

    if #items == 0 then
        if allowRequest then
            LFGTool.RequestActivities()
        end
        options[#options + 1] = { value = "__retry__", label = Localization.L("LISTING_PICK_EMPTY") }
        ap.activityDropdown:SetOptions(options, partyLens.db.autopilot.activityID or "__any__")
        return
    end

    -- Group by category.
    local groups, ordered = {}, {}
    for _, item in ipairs(items) do
        local key, label, order = ActivityCategory(item, content)
        local g = groups[key]
        if not g then
            g = { label = label, order = order, items = {} }
            groups[key] = g
            ordered[#ordered + 1] = g
        end
        g.items[#g.items + 1] = item
    end

    -- Dungeon mode with no heroics detected: a lone "Normal dungeons" heading
    -- reads oddly, so relabel it to plain "Dungeons".
    if content == "dungeon" and groups.normal and not groups.heroic then
        groups.normal.label = Localization.L("TAB_DUNGEONS")
    end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)

    -- Emit header + indented items per group (items already ordered by the API).
    for _, g in ipairs(ordered) do
        table.sort(g.items, function(a, b)
            if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
            return (a.label or "") < (b.label or "")
        end)
        options[#options + 1] = { value = "__header__", label = g.label, header = true }
        for _, item in ipairs(g.items) do
            options[#options + 1] = { value = item.value, label = item.label, indent = true }
        end
    end

    ap.activityDropdown:SetOptions(options, partyLens.db.autopilot.activityID or "__any__")
end

-- Refreshes the live state of the autopilot panel (status, roster, log, GO).
function UIMain.RefreshAutopilot(partyLens)
    local ap = partyLens.ap
    if not ap then
        return
    end
    local P = UIElements.PALETTE
    local cfg = partyLens.db.autopilot
    local rt = partyLens.autopilot
    local armed = rt and rt.armed

    ap.armBtn:SetText(armed and Localization.L("AP_DISARM") or Localization.L("AP_ARM"))
    ap.armBtn:SetAccent(armed and P.coral or P.teal)

    local plCount = 0
    for _, e in ipairs(partyLens.entries or {}) do
        if e.isAddonUser then
            plCount = plCount + 1
        end
    end
    ap.meshLabel:SetText(Localization.L("AP_MESH_COUNT", plCount))

    local state = armed and ((rt and rt.state) or "searching") or "idle"
    ap.statusLabel:SetText(Localization.L("AP_STATE_LABEL") .. ": " .. Localization.L(AP_STATE_LABEL[state] or "AP_STATUS_IDLE"))

    if rt and rt.pendingAction then
        ap.goBtn:Show()
    else
        ap.goBtn:Hide()
    end

    local need, snap = Roster.Needed(partyLens)
    local names = {}
    for _, m in ipairs(snap.members) do
        names[#names + 1] = Utils.ClassColoredName(m.name or "", m.classFile)
    end
    ap.rosterLabel:SetText(Localization.L("AP_ROSTER_LABEL", snap.size) .. "  " .. table.concat(names, ", "))

    if cfg.role == "build" then
        if need.total <= 0 then
            ap.needLabel:SetText(Localization.L("AP_NEED_NONE"))
            ap.needLabel:SetTextColor(P.freshNew[1], P.freshNew[2], P.freshNew[3], 1)
        else
            local parts = {}
            if need.tank > 0 then parts[#parts + 1] = need.tank .. "T" end
            if need.heal > 0 then parts[#parts + 1] = need.heal .. "H" end
            if need.dps > 0 then parts[#parts + 1] = need.dps .. "D" end
            -- Slots remain but the (fuzzy) per-role guidance is satisfied — show a
            -- generic headcount so the label never reads "need nothing" while open.
            local detail = (#parts > 0) and table.concat(parts, " ") or (need.remaining .. "x")
            ap.needLabel:SetText(Localization.L("AP_NEED_REMAINING", detail))
            ap.needLabel:SetTextColor(P.gold[1], P.gold[2], P.gold[3], 1)
        end
        UIElements.SetButtonEnabled(ap.announceBtn, armed and snap.size > 1)
        ap.announceBtn:Show()
    else
        ap.needLabel:SetText(Localization.L("AP_MYROLE_LABEL") .. ": " .. (cfg.myRole or "dps"))
        ap.needLabel:SetTextColor(P.muted[1], P.muted[2], P.muted[3], 1)
        ap.announceBtn:Hide()
    end

    local log = (rt and rt.log) or {}
    for i = 1, #ap.logLines do
        local entry = log[i]
        if entry then
            local stamp = date and date("%H:%M", entry.t) or ""
            ap.logLines[i]:SetText("|cff5a6470" .. stamp .. "|r  " .. entry.text)
            ap.logLines[i]:Show()
        else
            ap.logLines[i]:Hide()
        end
    end
end

local function CreateSettingsPanel(partyLens, frame)
    local panel = UIElements.CreatePanel(frame, "PartyLensSettingsPanel", UIElements.PALETTE.panel, UIElements.PALETTE.stroke)
    partyLens.settingsPanel = panel
    panel:SetPoint("TOPLEFT", 18, -92)
    panel:SetPoint("BOTTOMRIGHT", -18, 18)

    local title = UIElements.CreateLabel(panel, Localization.L("SETTINGS_TITLE"), 16, UIElements.PALETTE.text)
    title:SetPoint("TOPLEFT", 14, -14)

    local filtersTitle = UIElements.CreateLabel(panel, Localization.L("SEARCH_AND_FILTERS"), 12, UIElements.PALETTE.text)
    filtersTitle:SetPoint("TOPLEFT", 14, -52)

    local includeChat = UIElements.CreateToggle(panel, Localization.L("CHAT_TOGGLE"), 92)
    partyLens.includeChatCheck = includeChat
    includeChat:SetPoint("TOPLEFT", 14, -74)
    includeChat:SetChecked(partyLens.db.includeChat)
    includeChat:SetScript("OnClick", function(check)
        ToggleDB(check, "includeChat", partyLens, true)
    end)

    local includeTool = UIElements.CreateToggle(panel, Localization.L("LFG_TOOL_TOGGLE"), 126)
    partyLens.includeToolCheck = includeTool
    includeTool:SetPoint("LEFT", includeChat, "RIGHT", 8, 0)
    includeTool:SetChecked(partyLens.db.includeTool)
    includeTool:SetScript("OnClick", function(check)
        ToggleDB(check, "includeTool", partyLens, true)
    end)

    local onlyOpen = UIElements.CreateToggle(panel, Localization.L("OPEN_ONLY_TOGGLE"), 112)
    partyLens.onlyOpenCheck = onlyOpen
    onlyOpen:SetPoint("LEFT", includeTool, "RIGHT", 8, 0)
    onlyOpen:SetChecked(partyLens.db.onlyOpen)
    onlyOpen:SetScript("OnClick", function(check)
        ToggleDB(check, "onlyOpen", partyLens, true)
    end)

    -- (The old "Players LFG"/"Groups LFM" toggles were removed — they duplicated
    -- the "Looking for" filter in Browse.)
    local minimap = UIElements.CreateToggle(panel, Localization.L("MINIMAP_TOGGLE"), 132)
    partyLens.minimapCheck = minimap
    minimap:SetPoint("LEFT", onlyOpen, "RIGHT", 8, 0)
    minimap:SetChecked(partyLens.db.minimap)
    minimap:SetScript("OnClick", function(check)
        ToggleDB(check, "minimap", partyLens, false)
        if MinimapButton then
            MinimapButton.SetShown(partyLens, partyLens.db.minimap)
        end
    end)

    local divider = UIElements.CreateDivider(panel)
    divider:SetPoint("TOPLEFT", 14, -124)
    divider:SetPoint("TOPRIGHT", -14, -124)

    local profileTitle = UIElements.CreateLabel(panel, Localization.L("PROFILE_AND_WHISPER"), 12, UIElements.PALETTE.text)
    profileTitle:SetPoint("TOPLEFT", 14, -146)

    local specLabel = UIElements.CreateLabel(panel, Localization.L("SPEC_LABEL"), 10, UIElements.PALETTE.muted)
    specLabel:SetPoint("TOPLEFT", 14, -176)
    local spec, specShell = UIElements.CreateEditBox(panel, "PartyLensSpecEditBox", 124, 30)
    partyLens.specBox = spec
    specShell:SetPoint("TOPLEFT", 14, -193)
    spec:SetText(partyLens.db.spec or "")
    spec:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "spec", partyLens)
    end)

    local roleLabel = UIElements.CreateLabel(panel, Localization.L("ROLE_LABEL"), 10, UIElements.PALETTE.muted)
    roleLabel:SetPoint("TOPLEFT", specShell, "TOPRIGHT", 12, 17)
    local role, roleShell = UIElements.CreateEditBox(panel, "PartyLensRoleEditBox", 92, 30)
    partyLens.roleBox = role
    roleShell:SetPoint("LEFT", specShell, "RIGHT", 12, 0)
    role:SetText(partyLens.db.role or "")
    role:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "role", partyLens)
    end)

    local commentLabel = UIElements.CreateLabel(panel, Localization.L("COMMENT_LABEL"), 10, UIElements.PALETTE.muted)
    commentLabel:SetPoint("TOPLEFT", roleShell, "TOPRIGHT", 12, 17)
    local comment, commentShell = UIElements.CreateEditBox(panel, "PartyLensCommentEditBox", 438, 30)
    partyLens.commentBox = comment
    commentShell:SetPoint("LEFT", roleShell, "RIGHT", 12, 0)
    comment:SetText(partyLens.db.comment or "")
    comment:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "comment", partyLens)
    end)

    local templateLabel = UIElements.CreateLabel(panel, Localization.L("TEMPLATE_LABEL"), 10, UIElements.PALETTE.muted)
    templateLabel:SetPoint("TOPLEFT", 14, -247)
    local template, templateShell = UIElements.CreateEditBox(panel, "PartyLensTemplateEditBox", 684, 32)
    partyLens.templateBox = template
    templateShell:SetPoint("TOPLEFT", 14, -264)
    template:SetText(partyLens.db.template or "")
    template:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "template", partyLens)
    end)

    local hint = UIElements.CreateLabel(panel, Localization.L("TEMPLATE_HINT"), 10, UIElements.PALETTE.muted)
    hint:SetPoint("TOPLEFT", 14, -308)
end

function UIMain.CreateMainUI(partyLens)
    if partyLens.frame then
        return
    end

    partyLens.mode = partyLens.db.mode or "browse"
    if not MODES[partyLens.mode] then
        partyLens.mode = "browse"
    end

    local frame = UIElements.CreatePanel(UIParent, "PartyLensFrame", UIElements.PALETTE.shell, UIElements.PALETTE.strokeHot)
    partyLens.frame = frame
    frame:SetSize(UIMain.UI_WIDTH, UIMain.UI_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    -- Let Escape close the window like other addon panels (registered once;
    -- CreateMainUI early-returns if the frame already exists).
    tinsert(UISpecialFrames, "PartyLensFrame")

    local header = UIElements.CreatePanel(frame, "PartyLensHeader", { 0.060, 0.070, 0.088, 0.66 }, UIElements.PALETTE.stroke)
    header:SetPoint("TOPLEFT", 10, -10)
    header:SetPoint("TOPRIGHT", -10, -10)
    header:SetHeight(76)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local brandMark = UIElements.CreatePanel(header, "PartyLensBrandMark", UIElements.PALETTE.teal, UIElements.PALETTE.teal)
    brandMark:SetPoint("TOPLEFT", 14, -14)
    brandMark:SetSize(6, 48)

    local title = UIElements.CreateLabel(header, Localization.L("TITLE"), 24, UIElements.PALETTE.text)
    title:SetPoint("TOPLEFT", 32, -12)

    local subtitle = UIElements.CreateLabel(header, Localization.L("SUBTITLE"), 11, UIElements.PALETTE.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -2)

    local close = UIElements.CreateButton(header, Localization.L("CLOSE"), 26, 26, UIElements.PALETTE.coral)
    close:SetPoint("TOPRIGHT", -14, -15)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Create/Settings demoted to compact header icons — frees the whole mode row.
    local settingsIcon = UIElements.CreateIconButton(header, "Interface\\Buttons\\UI-OptionsButton", 26, UIElements.PALETTE.coral)
    settingsIcon:SetPoint("RIGHT", close, "LEFT", -6, 0)
    partyLens.settingsIcon = settingsIcon
    settingsIcon:SetScript("OnClick", function()
        ToggleMode(partyLens, "settings")
    end)

    local createIcon = UIElements.CreateIconButton(header, nil, 26, UIElements.PALETTE.gold)
    createIcon:SetGlyph("+")
    createIcon:SetPoint("RIGHT", settingsIcon, "LEFT", -6, 0)
    partyLens.createIcon = createIcon
    createIcon:SetScript("OnClick", function()
        ToggleMode(partyLens, "create")
    end)

    -- Autopilot toggle (the "group looking" eye reads as a matchmaker).
    local autopilotIcon = UIElements.CreateIconButton(header, "Interface\\Icons\\INV_Misc_GroupLooking", 26, UIElements.PALETTE.blue)
    autopilotIcon:SetPoint("RIGHT", createIcon, "LEFT", -6, 0)
    partyLens.autopilotIcon = autopilotIcon
    autopilotIcon:SetScript("OnClick", function()
        ToggleMode(partyLens, "autopilot")
    end)

    local countPill = UIElements.CreateChip(header, 96, 24, UIElements.PALETTE.teal)
    countPill:SetPoint("TOPRIGHT", autopilotIcon, "TOPLEFT", -12, 0)
    countPill:SetAccent(UIElements.PALETTE.teal)
    countPill:SetLabel(Localization.L("RESULT_COUNT", 0))
    partyLens.countPill = countPill
    partyLens.countLabel = countPill.text

    CreateResultsPanel(partyLens, frame)
    CreateCreatePanel(partyLens, frame)
    CreateSettingsPanel(partyLens, frame)
    CreateAutopilotPanel(partyLens, frame)

    UIMain.SetMode(partyLens, partyLens.mode)
end

_G[ADDON_NAME .. "_UIMain"] = UIMain
return UIMain
