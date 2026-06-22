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

local L = Localization.L
local UIMain = {}

UIMain.UI_WIDTH = 820
UIMain.UI_HEIGHT = 600
UIMain.ROW_HEIGHT = 116
UIMain.ROW_WIDTH = 600
UIMain.CARD_INSET = 16

-- Layout system: a left nav sidebar + a content area with a consistent padding
-- grid. PAD is the universal inner margin so every panel lines up.
local PAD = 16
local SIDEBAR_W = 150

-- Maps an entry's content type to a short tag label + accent color.
function UIMain.ContentTagInfo(entry)
    local P = UIElements.PALETTE
    local t = entry.activityType or (entry.isRaid and "raid" or "dungeon")
    if t == "raid" then
        return L("TAB_RAIDS"), P.blue
    elseif t == "guild" then
        return L("CONTENT_GUILD"), P.gold
    elseif t == "quest" then
        return L("CONTENT_QUEST"), P.purple
    elseif t == "dungeon" then
        if entry.activity and string.find(string.lower(entry.activity), "heroic", 1, true) then
            return "HC", P.gold
        end
        return L("TAB_DUNGEONS"), P.teal
    end
    return L("CONTENT_OTHER"), P.muted
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
function UIMain.RefreshActivityList(partyLens, allowRequest)
    local dd = partyLens.activityDropdown
    if not dd then
        return
    end
    local list = LFGTool.GetActivityList(partyLens.db.listingCategory)
    if #list == 0 then
        if allowRequest then
            LFGTool.RequestActivities()
        end
        dd:SetOptions({ { value = "__retry__", label = L("LISTING_PICK_EMPTY") } })
        return
    end
    dd:SetOptions(list, tonumber(partyLens.db.listingActivityID))
end

-- Top-level navigation modes.
local MODES = { browse = true, create = true, settings = true, autopilot = true }

local CONTENT_CATEGORIES = {
    { key = "all", labelKey = "FILTER_ALL" },
    { key = "dungeon", labelKey = "TAB_DUNGEONS" },
    { key = "raid", labelKey = "TAB_RAIDS" },
    { key = "guild", labelKey = "CONTENT_GUILD" },
    { key = "quest", labelKey = "CONTENT_QUEST" },
    { key = "other", labelKey = "CONTENT_OTHER" },
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

local function ShowFrame(frame) if frame then frame:Show() end end
local function HideFrame(frame) if frame then frame:Hide() end end

-- Section heading: a muted title + a hairline underline (teal is reserved for
-- brand/selection/focus). Returns the label so callers can relabel it later.
-- width nil => stretch to panel right edge.
local function Section(parent, text, x, y, width)
    local P = UIElements.PALETTE
    local label = UIElements.CreateLabel(parent, Utils.Upper(text), 12, P.muted)
    label:SetPoint("TOPLEFT", x, y)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 16)
    if width then
        line:SetWidth(width)
    else
        line:SetPoint("TOPRIGHT", -PAD, y - 16)
    end
    UIElements.SetTextureColor(line, { P.stroke[1], P.stroke[2], P.stroke[3], 0.45 })
    return label
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

local MODE_TITLE = {
    browse = "MODE_BROWSE",
    autopilot = "AP_TITLE",
    create = "LISTING_SECTION_TITLE",
    settings = "SETTINGS_TITLE",
}

function UIMain.SetMode(partyLens, mode)
    if not mode or not partyLens.frame then
        return
    end
    if not MODES[mode] then
        mode = "browse"
    end
    partyLens.mode = mode
    partyLens.db.mode = mode

    for key, button in pairs(partyLens.navButtons or {}) do
        button:SetActive(key == mode)
    end
    if partyLens.headerTitle then
        partyLens.headerTitle:SetText(L(MODE_TITLE[mode] or "MODE_BROWSE"))
    end

    HideFrame(partyLens.resultsPanel)
    HideFrame(partyLens.createPanel)
    HideFrame(partyLens.settingsPanel)
    HideFrame(partyLens.autopilotPanel)
    HideFrame(partyLens.countPill)

    if mode == "create" then
        ShowFrame(partyLens.createPanel)
        UIMain.RefreshActivityList(partyLens, true)
    elseif mode == "settings" then
        ShowFrame(partyLens.settingsPanel)
        if partyLens.UpdateClearBlock then
            partyLens.UpdateClearBlock()
        end
    elseif mode == "autopilot" then
        ShowFrame(partyLens.autopilotPanel)
        UIMain.RefreshAutopilotActivities(partyLens, true)
        UIMain.RefreshAutopilot(partyLens)
    else
        ShowFrame(partyLens.resultsPanel)
        ShowFrame(partyLens.countPill)
        partyLens:Refresh()
    end
end

function UIMain.CreateResultRow(partyLens, index)
    local P = UIElements.PALETTE
    local inset = UIMain.CARD_INSET
    local cardHeight = UIMain.ROW_HEIGHT - 8

    local row = UIElements.CreatePanel(partyLens.content, "PartyLensResultRow" .. index, P.panel2, P.stroke)
    row:SetSize(UIMain.ROW_WIDTH, cardHeight)
    row:EnableMouse(true)

    row.tag = UIElements.CreateChip(row, 86, 20)
    row.tag:EnableDot()
    row.tag:SetPoint("TOPLEFT", inset, -11)

    row.intent = UIElements.CreateChip(row, 52, 20)
    row.intent:SetPoint("LEFT", row.tag, "RIGHT", 7, 0)

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

    row.title = UIElements.CreateLabel(row, "", 14, P.text)
    row.title:SetPoint("TOPLEFT", inset, -35)
    row.title:SetPoint("RIGHT", row.fill, "LEFT", -12, 0)
    row.title:SetJustifyH("LEFT")

    row.leader = UIElements.CreateLabel(row, "", 12, P.muted)
    row.leader:SetPoint("TOPLEFT", inset, -57)
    row.leader:SetPoint("RIGHT", row.fill, "LEFT", -12, 0)
    row.leader:SetJustifyH("LEFT")

    row.needsLabel = UIElements.CreateLabel(row, "", 10, P.muted)
    row.needsLabel:SetPoint("TOPLEFT", inset, -80)

    row.pips = {}
    for i = 1, 3 do
        local pip = UIElements.CreateRolePip(row, 16)
        pip:SetPoint("TOPLEFT", 64 + (i - 1) * 22, -78)
        pip:Hide()
        row.pips[i] = pip
    end

    row.message = UIElements.CreateLabel(row, "", 11, P.faint)
    row.message:SetPoint("TOPLEFT", inset, -96)
    row.message:SetPoint("RIGHT", row, "RIGHT", -82, 0)
    row.message:SetHeight(14)
    row.message:SetJustifyH("LEFT")

    row.whisper = UIElements.CreateButton(row, L("SEND_WHISPER"), 60, 18, P.teal)
    row.whisper:SetPoint("TOPRIGHT", -14, -11)
    row.whisper:SetScript("OnClick", function(button)
        Messaging.SendWhisper(partyLens, button:GetParent().entry)
    end)

    row.open = UIElements.CreateButton(row, L("EDIT_WHISPER"), 60, 18, P.blue)
    row.open:SetPoint("TOP", row.whisper, "BOTTOM", 0, -5)
    row.open:SetScript("OnClick", function(button)
        Messaging.OpenWhisper(partyLens, button:GetParent().entry)
    end)

    row.who = UIElements.CreateButton(row, L("WHO_CHECK"), 60, 18, P.gold)
    row.who:SetPoint("TOP", row.open, "BOTTOM", 0, -5)
    row.who:SetScript("OnClick", function(button)
        local entry = button:GetParent().entry
        if entry and entry.leader then
            local name = (entry.leaderDisplay and entry.leaderDisplay ~= "" and entry.leaderDisplay)
                or Utils.PlayerShortName(entry.leader)
            if C_FriendList and C_FriendList.SendWho then
                C_FriendList.SendWho('n-"' .. name .. '"')
            elseif SendWho then
                SendWho('n-"' .. name .. '"')
            end
        end
    end)

    row.block = UIElements.CreateButton(row, L("BLOCK_LEADER"), 60, 18, P.coral)
    row.block:SetPoint("TOP", row.who, "BOTTOM", 0, -5)
    row.block:SetScript("OnClick", function(button)
        local entry = button:GetParent().entry
        if entry and entry.leader then
            local key = Utils.SafeLower(Utils.PlayerShortName(entry.leader))
            partyLens.db.blacklist = partyLens.db.blacklist or {}
            partyLens.db.blacklist[key] = true
            Utils.Print(Localization.L("BLOCKED_MSG", Utils.PlayerShortName(entry.leader)))
            if partyLens.UpdateClearBlock then partyLens.UpdateClearBlock() end
            partyLens:Refresh()
        end
    end)

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

local function SetRoleFilter(partyLens, role, value)
    partyLens.db.roleFilter = partyLens.db.roleFilter or {}
    partyLens.db.roleFilter[role] = value and true or false
    partyLens:Refresh()
end

-- ===========================================================================
-- Browse panel
-- ===========================================================================
local function CreateResultsPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensResultsPanel", host)
    partyLens.resultsPanel = panel
    panel:SetAllPoints(host)

    -- Toolbar row 1: search (left) + refresh + join (right).
    local join = UIElements.CreateButton(panel, L("JOIN_LFG"), 92, 30, P.gold)
    join:SetPoint("TOPRIGHT", -PAD, -PAD)
    join:SetScript("OnClick", function() Messaging.JoinLookingForGroup() end)

    local refresh = UIElements.CreateButton(panel, L("REFRESH"), 96, 30, P.teal)
    refresh:SetPoint("RIGHT", join, "LEFT", -8, 0)
    refresh:SetScript("OnClick", function() partyLens:RefreshGroups() end)

    local query, queryShell = UIElements.CreateEditBox(panel, "PartyLensQueryEditBox", 396, 30)
    partyLens.queryBox = query
    queryShell:SetPoint("TOPLEFT", PAD, -PAD)
    query:SetText(partyLens.db.query or "")
    query:SetPlaceholder(L("SEARCH_PLACEHOLDER"))
    query:SetScript("OnTextChanged", function(editBox)
        partyLens.db.query = editBox:GetText()
        editBox:UpdatePlaceholder()
        if partyLens._queryTimer and partyLens._queryTimer.Cancel then
            partyLens._queryTimer:Cancel()
        end
        if C_Timer and C_Timer.NewTimer then
            partyLens._queryTimer = C_Timer.NewTimer(0.25, function() partyLens:Refresh() end)
        else
            partyLens:Refresh()
        end
    end)

    -- Toolbar row 2: labels.
    local catLabel = UIElements.CreateLabel(panel, L("CATEGORY_HEADER"), 10, P.muted)
    catLabel:SetPoint("TOPLEFT", PAD, -56)
    local intentLabel = UIElements.CreateLabel(panel, L("INTENT_HEADER"), 10, P.muted)
    intentLabel:SetPoint("TOPLEFT", PAD + 176, -56)
    local needsLabel = UIElements.CreateLabel(panel, L("NEEDS_LABEL"), 10, P.muted)
    needsLabel:SetPoint("TOPLEFT", PAD + 392, -56)

    -- Toolbar row 2: controls.
    local category = UIElements.CreateDropdown(panel, 160, 28, P.teal)
    partyLens.categoryDropdown = category
    category:SetPoint("TOPLEFT", PAD, -72)
    local categoryOptions = {}
    for _, cat in ipairs(CONTENT_CATEGORIES) do
        categoryOptions[#categoryOptions + 1] = { value = cat.key, label = L(cat.labelKey) }
    end
    category:SetOptions(categoryOptions, partyLens.db.contentFilter or "all")
    category.onSelect = function(value) SetContentFilter(partyLens, value) end

    local intentOrder = {
        { key = "all", labelKey = "FILTER_ALL", color = P.teal },
        { key = "players", labelKey = "INTENT_PLAYER", color = P.gold },
        { key = "groups", labelKey = "INTENT_GROUP", color = P.blue },
    }
    partyLens.intentFilterButtons = {}
    local prevIntent
    for _, opt in ipairs(intentOrder) do
        local key = opt.key
        local button = UIElements.CreateButton(panel, L(opt.labelKey), 64, 28, opt.color)
        if prevIntent then
            button:SetPoint("LEFT", prevIntent, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", PAD + 176, -72)
        end
        button:SetScript("OnClick", function() SetIntentFilter(partyLens, key) end)
        partyLens.intentFilterButtons[key] = button
        prevIntent = button
    end
    UpdateIntentFilterButtons(partyLens)

    partyLens.roleToggles = {}
    local prevPip
    for _, role in ipairs({ "tank", "heal", "dps" }) do
        local pip = UIElements.CreateRoleToggle(panel, role, 22)
        if prevPip then
            pip:SetPoint("LEFT", prevPip, "RIGHT", 8, 0)
        else
            pip:SetPoint("TOPLEFT", PAD + 392, -74)
        end
        pip:SetSelected(partyLens.db.roleFilter and partyLens.db.roleFilter[role])
        pip.onToggle = function(r, v) SetRoleFilter(partyLens, r, v) end
        partyLens.roleToggles[role] = pip
        prevPip = pip
    end

    -- Results scroll area.
    local scrollFrame = CreateFrame("ScrollFrame", "PartyLensScrollFrame", panel)
    partyLens.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", PAD, -112)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(scroll, delta)
        local current = scroll:GetVerticalScroll()
        local maxScroll = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta * 38))))
    end)

    local content = CreateFrame("Frame", "PartyLensScrollContent", scrollFrame)
    partyLens.content = content
    content:SetSize(UIMain.ROW_WIDTH, 1)
    scrollFrame:SetScrollChild(content)

    local empty = UIElements.CreateLabel(panel, L("EMPTY_RESULTS"), 12, P.faint)
    empty:SetPoint("TOP", scrollFrame, "TOP", 0, -48)
    empty:SetPoint("LEFT", scrollFrame, "LEFT", 30, 0)
    empty:SetPoint("RIGHT", scrollFrame, "RIGHT", -30, 0)
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("TOP")
    empty:Hide()
    partyLens.emptyState = empty

    partyLens.rows = {}
end

-- ===========================================================================
-- Create panel
-- ===========================================================================
local function CreateCreatePanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensCreatePanel", host)
    partyLens.createPanel = panel
    panel:SetAllPoints(host)

    Section(panel, L("LISTING_CATEGORY_LABEL"), PAD, -PAD)

    local dungeonButton = UIElements.CreateButton(panel, L("TAB_DUNGEONS"), 110, 30, P.teal)
    partyLens.createDungeonButton = dungeonButton
    dungeonButton:SetPoint("TOPLEFT", PAD, -42)
    dungeonButton:SetScript("OnClick", function()
        partyLens.db.listingCategory = "dungeons"
        dungeonButton:SetActive(true)
        partyLens.createRaidButton:SetActive(false)
        UIMain.RefreshActivityList(partyLens, true)
    end)

    local raidButton = UIElements.CreateButton(panel, L("TAB_RAIDS"), 110, 30, P.blue)
    partyLens.createRaidButton = raidButton
    raidButton:SetPoint("LEFT", dungeonButton, "RIGHT", 8, 0)
    raidButton:SetScript("OnClick", function()
        partyLens.db.listingCategory = "raids"
        raidButton:SetActive(true)
        dungeonButton:SetActive(false)
        UIMain.RefreshActivityList(partyLens, true)
    end)

    local isRaid = partyLens.db.listingCategory == "raids"
    dungeonButton:SetActive(not isRaid)
    raidButton:SetActive(isRaid)

    Section(panel, L("LISTING_ACTIVITY_LABEL"), PAD, -90)

    local activityDropdown = UIElements.CreateDropdown(panel, 380, 30, P.blue)
    partyLens.activityDropdown = activityDropdown
    activityDropdown.placeholder = L("LISTING_PICK")
    activityDropdown:SetPoint("TOPLEFT", PAD, -114)
    activityDropdown.onSelect = function(value)
        if value == "__retry__" then
            LFGTool.RequestActivities()
            UIMain.RefreshActivityList(partyLens, true)
            return
        end
        partyLens.db.listingActivityID = tostring(value)
    end

    local ilvlLabel = UIElements.CreateLabel(panel, L("LISTING_ILVL_LABEL"), 10, P.muted)
    ilvlLabel:SetPoint("TOPLEFT", PAD + 396, -98)
    local ilvl, ilvlShell = UIElements.CreateEditBox(panel, "PartyLensListingIlvlEditBox", 80, 30)
    partyLens.listingIlvlBox = ilvl
    ilvlShell:SetPoint("TOPLEFT", PAD + 396, -114)
    ilvl:SetText(partyLens.db.listingMinItemLevel or "0")
    ilvl:SetScript("OnTextChanged", function(editBox)
        SaveEditBox(editBox, "listingMinItemLevel", partyLens)
    end)

    UIMain.RefreshActivityList(partyLens, true)

    local autoAccept = UIElements.CreateToggle(panel, L("AUTO_ACCEPT_TOGGLE"), 130)
    partyLens.listingAutoAcceptCheck = autoAccept
    autoAccept:SetPoint("TOPLEFT", PAD, -156)
    autoAccept:SetChecked(partyLens.db.listingAutoAccept)
    autoAccept:SetScript("OnClick", function(check) ToggleDB(check, "listingAutoAccept", partyLens, false) end)

    local privateGroup = UIElements.CreateToggle(panel, L("PRIVATE_GROUP_TOGGLE"), 110)
    partyLens.listingPrivateCheck = privateGroup
    privateGroup:SetPoint("LEFT", autoAccept, "RIGHT", 10, 0)
    privateGroup:SetChecked(partyLens.db.listingPrivate)
    privateGroup:SetScript("OnClick", function(check) ToggleDB(check, "listingPrivate", partyLens, false) end)

    Section(panel, L("LISTING_TITLE_LABEL"), PAD, -196)
    local listingTitle, listingTitleShell = UIElements.CreateEditBox(panel, "PartyLensListingTitleEditBox", 100, 32)
    partyLens.listingTitleBox = listingTitle
    listingTitleShell:SetPoint("TOPLEFT", PAD, -218)
    listingTitleShell:SetPoint("RIGHT", -PAD, 0)
    listingTitle:SetMaxLetters(60)
    listingTitle:SetText(partyLens.db.listingTitle or "")
    listingTitle:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "listingTitle", partyLens) end)

    Section(panel, L("LISTING_COMMENT_LABEL"), PAD, -262)
    local listingComment, listingCommentShell = UIElements.CreateEditBox(panel, "PartyLensListingCommentEditBox", 100, 32)
    partyLens.listingCommentBox = listingComment
    listingCommentShell:SetPoint("TOPLEFT", PAD, -284)
    listingCommentShell:SetPoint("RIGHT", -PAD, 0)
    listingComment:SetMaxLetters(180)
    listingComment:SetText(partyLens.db.listingComment or "")
    listingComment:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "listingComment", partyLens) end)

    local create = UIElements.CreateButton(panel, L("CREATE_LFG_LISTING"), 150, 32, P.gold)
    create:SetPoint("TOPLEFT", PAD, -332)
    create:SetScript("OnClick", function() LFGTool.CreateListing(partyLens) end)

    local announce = UIElements.CreateButton(panel, L("ANNOUNCE_CHAT_LISTING"), 150, 32, P.teal)
    announce:SetPoint("LEFT", create, "RIGHT", 10, 0)
    announce:SetScript("OnClick", function() LFGTool.AnnounceListing(partyLens) end)

    local hint = UIElements.CreateLabel(panel, L("LISTING_HINT"), 10, P.faint)
    hint:SetPoint("TOPLEFT", PAD, -380)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")
end

-- ===========================================================================
-- Autopilot panel
-- ===========================================================================
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
    if ap.roleSection then
        ap.roleSection:SetText(role == "build" and L("AP_NEEDS_LABEL") or L("AP_MYROLE_LABEL"))
    end
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

-- A comfortable role split for a given group size; the player can still tweak it.
local function ComfortableComp(maxPlayers)
    local m = tonumber(maxPlayers) or 5
    if m <= 5 then return 1, 1, 3 end
    if m <= 10 then return 2, 3, 5 end
    if m <= 25 then return 2, 6, 17 end
    if m <= 40 then return 4, 9, 27 end
    local tanks = math.max(1, math.floor(m / 12))
    local heals = math.max(1, math.floor(m / 5))
    return tanks, heals, math.max(0, m - tanks - heals)
end

-- Writes a composition into the config + the comp boxes (build mode).
local function ApplyComp(partyLens, t, h, d)
    local cfg = partyLens.db.autopilot
    cfg.needTank, cfg.needHeal, cfg.needDps = t, h, d
    local ap = partyLens.ap
    if ap then
        if ap.needT then ap.needT:SetText(tostring(t)) end
        if ap.needH then ap.needH:SetText(tostring(h)) end
        if ap.needD then ap.needD:SetText(tostring(d)) end
    end
    if UIMain.RefreshAutopilot then UIMain.RefreshAutopilot(partyLens) end
end

-- A grouping card: subtle filled panel with a small title at its top-left, so
-- related controls read as one block instead of floating loose.
local function Card(parent, titleText, y, h)
    local P = UIElements.PALETTE
    local card = UIElements.CreatePanel(parent, nil, { 0.082, 0.096, 0.120, 0.55 }, P.stroke)
    card:SetPoint("TOPLEFT", PAD, y)
    card:SetPoint("TOPRIGHT", -PAD, y)
    card:SetHeight(h)
    if titleText then
        card.title = UIElements.CreateLabel(card, titleText, 11, P.teal)
        card.title:SetPoint("TOPLEFT", 12, -9)
    end
    return card
end

local function CreateAutopilotPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensAutopilotPanel", host)
    partyLens.autopilotPanel = panel
    panel:SetAllPoints(host)

    local ap = {}
    partyLens.ap = ap

    -- Mesh count (top-right) + short hint (top-left).
    ap.meshLabel = UIElements.CreateLabel(panel, "", 11, P.teal)
    ap.meshLabel:SetPoint("TOPRIGHT", -PAD, -PAD)
    ap.meshLabel:SetJustifyH("RIGHT")

    local hint = UIElements.CreateLabel(panel, L("AP_HINT"), 10, P.muted)
    hint:SetPoint("TOPLEFT", PAD, -PAD)
    hint:SetPoint("RIGHT", ap.meshLabel, "LEFT", -10, 0)
    hint:SetJustifyH("LEFT")

    -- Goal: build vs find (big segmented).
    ap.roleBuildBtn = UIElements.CreateButton(panel, L("AP_ROLE_BUILD"), 290, 30, P.teal)
    ap.roleBuildBtn:SetPoint("TOPLEFT", PAD, -38)
    ap.roleBuildBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "build"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)
    ap.roleFindBtn = UIElements.CreateButton(panel, L("AP_ROLE_FIND"), 290, 30, P.gold)
    ap.roleFindBtn:SetPoint("LEFT", ap.roleBuildBtn, "RIGHT", 8, 0)
    ap.roleFindBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "find"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    -- ---- Content card -----------------------------------------------------
    local contentCard = Card(panel, L("AP_CONTENT_LABEL"), -78, 64)
    ap.contentBtns = {}
    local contentOrder = {
        { key = "dungeon", labelKey = "TAB_DUNGEONS", color = P.teal, width = 92 },
        { key = "raid", labelKey = "TAB_RAIDS", color = P.blue, width = 72 },
        { key = "any", labelKey = "FILTER_ALL", color = P.purple, width = 56 },
    }
    local prevContent
    for _, c in ipairs(contentOrder) do
        local btn = UIElements.CreateButton(contentCard, L(c.labelKey), c.width, 28, c.color)
        if prevContent then
            btn:SetPoint("LEFT", prevContent, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 12, -26)
        end
        local key = c.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.activityType = key
            UpdateAutopilotContent(partyLens)
            UIMain.RefreshAutopilotActivities(partyLens, true)
            -- Auto-fill a comfortable comp for the content type (build only).
            if partyLens.db.autopilot.role == "build" then
                if key == "dungeon" then
                    ApplyComp(partyLens, ComfortableComp(5))
                elseif key == "raid" then
                    ApplyComp(partyLens, ComfortableComp(25))
                end
            end
        end)
        ap.contentBtns[c.key] = btn
        prevContent = btn
    end

    local activityDropdown = UIElements.CreateDropdown(contentCard, 340, 28, P.purple)
    ap.activityDropdown = activityDropdown
    activityDropdown.placeholder = L("AP_ANY_ACTIVITY")
    activityDropdown:SetPoint("TOPLEFT", 260, -26)
    activityDropdown:SetPoint("RIGHT", -12, 0)
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
        local label, maxp
        for _, opt in ipairs(activityDropdown.options) do
            if opt.value == value then
                label = opt.label
                maxp = opt.maxPlayers
                break
            end
        end
        partyLens.db.autopilot.activityFilter = label or ""
        -- Match the comp to the picked activity's size (build only).
        if maxp and partyLens.db.autopilot.role == "build" then
            ApplyComp(partyLens, ComfortableComp(maxp))
        end
    end

    -- ---- Role card (composition for build / role for find) ----------------
    local roleCard = Card(panel, L("AP_NEEDS_LABEL"), -152, 92)
    ap.roleSection = roleCard.title

    -- Build box fills the role card below its title.
    local buildBox = CreateFrame("Frame", nil, roleCard)
    ap.buildBox = buildBox
    buildBox:SetPoint("TOPLEFT", 12, -26)
    buildBox:SetPoint("TOPRIGHT", -12, -26)
    buildBox:SetHeight(58)

    -- Row 1: unified role counters + invite keyword.
    local function MakeCounter(name, key, x, role)
        local box, shell = UIElements.CreateRoleCounter(buildBox, name, role, 62, 28)
        shell:SetPoint("TOPLEFT", x, -2)
        box:SetText(tostring(partyLens.db.autopilot[key] or 0))
        box:SetScript("OnTextChanged", function(editBox) SaveAutopilotNumber(editBox, key, partyLens, 0) end)
        return box
    end
    ap.needT = MakeCounter("PartyLensAPNeedTank", "needTank", 0, "tank")
    ap.needH = MakeCounter("PartyLensAPNeedHeal", "needHeal", 68, "heal")
    ap.needD = MakeCounter("PartyLensAPNeedDps", "needDps", 136, "dps")

    local kwLabel = UIElements.CreateLabel(buildBox, L("AP_KEYWORD_SHORT"), 10, P.muted)
    kwLabel:SetPoint("TOPLEFT", 236, -8)
    local kwBox, kwShell = UIElements.CreateEditBox(buildBox, "PartyLensAPKeyword", 86, 28)
    kwShell:SetPoint("TOPLEFT", 300, -2)
    kwBox:SetText(partyLens.db.autopilot.inviteKeyword or "inv")
    kwBox:SetScript("OnTextChanged", function(editBox)
        partyLens.db.autopilot.inviteKeyword = Utils.Trim(editBox:GetText())
    end)

    -- Row 2: automation toggles.
    ap.autoInviteToggle = UIElements.CreateToggle(buildBox, L("AP_AUTO_INVITE"), 150)
    ap.autoInviteToggle:SetPoint("TOPLEFT", 0, -34)
    ap.autoInviteToggle:SetChecked(partyLens.db.autopilot.autoInvite)
    ap.autoInviteToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoInvite = check:GetChecked()
    end)

    ap.autoAnnounceToggle = UIElements.CreateToggle(buildBox, L("AP_AUTO_ANNOUNCE"), 190)
    ap.autoAnnounceToggle:SetPoint("LEFT", ap.autoInviteToggle, "RIGHT", 16, 0)
    ap.autoAnnounceToggle:SetChecked(partyLens.db.autopilot.autoAnnounce)
    ap.autoAnnounceToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoAnnounce = check:GetChecked()
    end)

    -- Find box fills the role card below its title.
    local findBox = CreateFrame("Frame", nil, roleCard)
    ap.findBox = findBox
    findBox:SetPoint("TOPLEFT", 12, -26)
    findBox:SetPoint("TOPRIGHT", -12, -26)
    findBox:SetHeight(58)

    ap.myRoleBtns = {}
    local roleOrder = {
        { key = "tank", labelKey = "ROLE_TANK", color = P.roleTank },
        { key = "heal", labelKey = "ROLE_HEAL", color = P.roleHeal },
        { key = "dps", labelKey = "ROLE_DPS", color = P.roleDps },
    }
    local prevRole
    for _, r in ipairs(roleOrder) do
        local btn = UIElements.CreateButton(findBox, L(r.labelKey), 74, 28, r.color)
        if prevRole then
            btn:SetPoint("LEFT", prevRole, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 0, -2)
        end
        local key = r.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.myRole = key
            UpdateAutopilotMyRole(partyLens)
        end)
        ap.myRoleBtns[r.key] = btn
        prevRole = btn
    end

    ap.autoWhisperToggle = UIElements.CreateToggle(findBox, L("AP_AUTO_WHISPER"), 150)
    ap.autoWhisperToggle:SetPoint("TOPLEFT", 0, -34)
    ap.autoWhisperToggle:SetChecked(partyLens.db.autopilot.autoWhisper)
    ap.autoWhisperToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoWhisper = check:GetChecked()
    end)

    -- ---- Automation card (tier + safety) ----------------------------------
    local autoCard = Card(panel, L("AP_TIER_LABEL"), -254, 64)
    ap.tierBtns = {}
    local tierOrder = {
        { key = "advisor", labelKey = "AP_TIER_ADVISOR", color = P.blue },
        { key = "assisted", labelKey = "AP_TIER_ASSISTED", color = P.teal },
        { key = "full", labelKey = "AP_TIER_FULL", color = P.coral },
    }
    local prevTier
    for _, t in ipairs(tierOrder) do
        local btn = UIElements.CreateButton(autoCard, L(t.labelKey), 108, 28, t.color)
        if prevTier then
            btn:SetPoint("LEFT", prevTier, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", 12, -26)
        end
        local key = t.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.tier = key
            UpdateAutopilotTier(partyLens)
        end)
        ap.tierBtns[t.key] = btn
        prevTier = btn
    end

    -- Safety inputs share the card's top line (right side).
    local cdLabel = UIElements.CreateLabel(autoCard, L("AP_COOLDOWN_LABEL"), 9, P.muted)
    cdLabel:SetPoint("TOPLEFT", 372, -10)
    local cdBox, cdShell = UIElements.CreateEditBox(autoCard, "PartyLensAPCooldown", 46, 28)
    cdShell:SetPoint("TOPLEFT", 372, -26)
    cdBox:SetText(tostring(partyLens.db.autopilot.whisperCooldown or 20))
    cdBox:SetScript("OnTextChanged", function(editBox) SaveAutopilotNumber(editBox, "whisperCooldown", partyLens, 5) end)

    local ilvlLabel = UIElements.CreateLabel(autoCard, L("LISTING_ILVL_LABEL"), 9, P.muted)
    ilvlLabel:SetPoint("TOPLEFT", 470, -10)
    local ilvlBox, ilvlShell = UIElements.CreateEditBox(autoCard, "PartyLensAPIlvl", 46, 28)
    ilvlShell:SetPoint("TOPLEFT", 470, -26)
    ilvlBox:SetText(tostring(partyLens.db.autopilot.minIlvl or 0))
    ilvlBox:SetScript("OnTextChanged", function(editBox) SaveAutopilotNumber(editBox, "minIlvl", partyLens, 0) end)

    -- ---- Arm / GO / status ------------------------------------------------
    ap.armBtn = UIElements.CreateButton(panel, L("AP_ARM"), 220, 34, P.teal)
    ap.armBtn:SetPoint("TOPLEFT", PAD, -330)
    ap.armBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    ap.goBtn = UIElements.CreateButton(panel, L("AP_GO"), 70, 34, P.gold)
    ap.goBtn:SetPoint("LEFT", ap.armBtn, "RIGHT", 8, 0)
    ap.goBtn:SetScript("OnClick", function() Autopilot.PressGo(partyLens) end)
    ap.goBtn:Hide()

    ap.statusLabel = UIElements.CreateLabel(panel, "", 12, P.text)
    ap.statusLabel:SetPoint("LEFT", ap.goBtn, "RIGHT", 12, 0)
    ap.statusLabel:SetPoint("RIGHT", -PAD, 0)
    ap.statusLabel:SetJustifyH("LEFT")

    -- ---- Ready to summon --------------------------------------------------
    ap.announceBtn = UIElements.CreateButton(panel, L("AP_ANNOUNCE_BTN"), 104, 26, P.gold)
    ap.announceBtn:SetPoint("TOPRIGHT", -PAD, -374)
    ap.announceBtn:SetScript("OnClick", function() Autopilot.AnnounceReady(partyLens) end)

    Section(panel, L("AP_SUMMON_SECTION"), PAD, -380, 400)
    ap.rosterLabel = UIElements.CreateLabel(panel, "", 11, P.text)
    ap.rosterLabel:SetPoint("TOPLEFT", PAD, -400)
    ap.rosterLabel:SetPoint("RIGHT", -PAD, 0)
    ap.rosterLabel:SetJustifyH("LEFT")

    ap.needLabel = UIElements.CreateLabel(panel, "", 11, P.gold)
    ap.needLabel:SetPoint("TOPLEFT", PAD, -418)
    ap.needLabel:SetPoint("RIGHT", -PAD, 0)
    ap.needLabel:SetJustifyH("LEFT")

    -- ---- Activity log -----------------------------------------------------
    Section(panel, L("AP_LOG_TITLE"), PAD, -442)
    ap.logLines = {}
    for i = 1, 5 do
        local line = UIElements.CreateLabel(panel, "", 10, P.faint)
        line:SetPoint("TOPLEFT", PAD, -462 - (i - 1) * 14)
        line:SetPoint("RIGHT", -PAD, 0)
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

local function ActivityCategory(item, content)
    if content == "dungeon" then
        if ActivityIsHeroic(item.label) then
            return "heroic", L("AP_CAT_HEROIC"), 2
        end
        return "normal", L("AP_CAT_NORMAL"), 1
    elseif content == "raid" then
        local size = item.maxPlayers or 0
        return "r" .. size, L("AP_CAT_RAID_SIZE", size), size
    else
        if (item.maxPlayers or 0) > 5 then
            return "raids", L("TAB_RAIDS"), 2
        end
        return "dungeons", L("TAB_DUNGEONS"), 1
    end
end

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

    local items, seen = {}, {}
    for _, list in ipairs(lists) do
        for _, item in ipairs(list) do
            if not seen[item.value] then
                seen[item.value] = true
                items[#items + 1] = item
            end
        end
    end

    local options = { { value = "__any__", label = L("AP_ANY_ACTIVITY") } }

    if #items == 0 then
        if allowRequest then
            LFGTool.RequestActivities()
        end
        options[#options + 1] = { value = "__retry__", label = L("LISTING_PICK_EMPTY") }
        ap.activityDropdown:SetOptions(options, partyLens.db.autopilot.activityID or "__any__")
        return
    end

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

    if content == "dungeon" and groups.normal and not groups.heroic then
        groups.normal.label = L("TAB_DUNGEONS")
    end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)

    for _, g in ipairs(ordered) do
        table.sort(g.items, function(a, b)
            if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
            return (a.label or "") < (b.label or "")
        end)
        options[#options + 1] = { value = "__header__", label = g.label, header = true }
        for _, item in ipairs(g.items) do
            options[#options + 1] = { value = item.value, label = item.label, indent = true, maxPlayers = item.maxPlayers }
        end
    end

    ap.activityDropdown:SetOptions(options, partyLens.db.autopilot.activityID or "__any__")
end

function UIMain.RefreshAutopilot(partyLens)
    local ap = partyLens.ap
    if not ap then
        return
    end
    local P = UIElements.PALETTE
    local cfg = partyLens.db.autopilot
    local rt = partyLens.autopilot
    local armed = rt and rt.armed

    ap.armBtn:SetText(armed and L("AP_DISARM") or L("AP_ARM"))
    ap.armBtn:SetAccent(armed and P.coral or P.teal)

    local plCount = 0
    for _, e in ipairs(partyLens.entries or {}) do
        if e.isAddonUser then plCount = plCount + 1 end
    end
    ap.meshLabel:SetText(L("AP_MESH_COUNT", plCount))

    local state = armed and ((rt and rt.state) or "searching") or "idle"
    ap.statusLabel:SetText(L("AP_STATE_LABEL") .. ": " .. L(AP_STATE_LABEL[state] or "AP_STATUS_IDLE"))

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
    ap.rosterLabel:SetText(L("AP_ROSTER_LABEL", snap.size) .. "  " .. table.concat(names, ", "))

    if cfg.role == "build" then
        if need.total <= 0 then
            ap.needLabel:SetText(L("AP_NEED_NONE"))
            ap.needLabel:SetTextColor(P.freshNew[1], P.freshNew[2], P.freshNew[3], 1)
        else
            local parts = {}
            if need.tank > 0 then parts[#parts + 1] = need.tank .. "T" end
            if need.heal > 0 then parts[#parts + 1] = need.heal .. "H" end
            if need.dps > 0 then parts[#parts + 1] = need.dps .. "D" end
            local detail = (#parts > 0) and table.concat(parts, " ") or (need.remaining .. "x")
            ap.needLabel:SetText(L("AP_NEED_REMAINING", detail))
            ap.needLabel:SetTextColor(P.gold[1], P.gold[2], P.gold[3], 1)
        end
        UIElements.SetButtonEnabled(ap.announceBtn, armed and snap.size > 1)
        ap.announceBtn:Show()
    else
        ap.needLabel:SetText(L("AP_MYROLE_LABEL") .. ": " .. (cfg.myRole or "dps"))
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

-- ===========================================================================
-- Settings panel
-- ===========================================================================
local function CreateSettingsPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensSettingsPanel", host)
    partyLens.settingsPanel = panel
    panel:SetAllPoints(host)

    Section(panel, L("SEARCH_AND_FILTERS"), PAD, -PAD)

    local includeChat = UIElements.CreateToggle(panel, L("CHAT_TOGGLE"), 96)
    partyLens.includeChatCheck = includeChat
    includeChat:SetPoint("TOPLEFT", PAD, -40)
    includeChat:SetChecked(partyLens.db.includeChat)
    includeChat:SetScript("OnClick", function(check) ToggleDB(check, "includeChat", partyLens, true) end)

    local includeTool = UIElements.CreateToggle(panel, L("LFG_TOOL_TOGGLE"), 128)
    partyLens.includeToolCheck = includeTool
    includeTool:SetPoint("LEFT", includeChat, "RIGHT", 8, 0)
    includeTool:SetChecked(partyLens.db.includeTool)
    includeTool:SetScript("OnClick", function(check) ToggleDB(check, "includeTool", partyLens, true) end)

    local onlyOpen = UIElements.CreateToggle(panel, L("OPEN_ONLY_TOGGLE"), 116)
    partyLens.onlyOpenCheck = onlyOpen
    onlyOpen:SetPoint("LEFT", includeTool, "RIGHT", 8, 0)
    onlyOpen:SetChecked(partyLens.db.onlyOpen)
    onlyOpen:SetScript("OnClick", function(check) ToggleDB(check, "onlyOpen", partyLens, true) end)

    local minimap = UIElements.CreateToggle(panel, L("MINIMAP_TOGGLE"), 134)
    partyLens.minimapCheck = minimap
    minimap:SetPoint("LEFT", onlyOpen, "RIGHT", 8, 0)
    minimap:SetChecked(partyLens.db.minimap)
    minimap:SetScript("OnClick", function(check)
        ToggleDB(check, "minimap", partyLens, false)
        if MinimapButton then
            MinimapButton.SetShown(partyLens, partyLens.db.minimap)
        end
    end)

    -- Row 2: spam + alert + blacklist management.
    local hideSpam = UIElements.CreateToggle(panel, L("HIDE_SPAM_TOGGLE"), 116)
    partyLens.hideSpamCheck = hideSpam
    hideSpam:SetPoint("TOPLEFT", PAD, -72)
    hideSpam:SetChecked(partyLens.db.hideSpam)
    hideSpam:SetScript("OnClick", function(check) ToggleDB(check, "hideSpam", partyLens, true) end)

    local alert = UIElements.CreateToggle(panel, L("ALERT_TOGGLE"), 84)
    partyLens.alertCheck = alert
    alert:SetPoint("LEFT", hideSpam, "RIGHT", 8, 0)
    alert:SetChecked(partyLens.db.alertOnMatch)
    alert:SetScript("OnClick", function(check) ToggleDB(check, "alertOnMatch", partyLens, false) end)

    local clearBlock = UIElements.CreateButton(panel, "", 168, 26, P.coral)
    partyLens.clearBlockBtn = clearBlock
    clearBlock:SetPoint("LEFT", alert, "RIGHT", 14, 0)
    local function updateClearBlock()
        local n = 0
        for _ in pairs(partyLens.db.blacklist or {}) do n = n + 1 end
        clearBlock:SetText(L("BLACKLIST_CLEAR", n))
        UIElements.SetButtonEnabled(clearBlock, n > 0)
    end
    partyLens.UpdateClearBlock = updateClearBlock
    clearBlock:SetScript("OnClick", function()
        partyLens.db.blacklist = {}
        updateClearBlock()
        partyLens:Refresh()
    end)
    updateClearBlock()

    Section(panel, L("PROFILE_AND_WHISPER"), PAD, -116)

    local specLabel = UIElements.CreateLabel(panel, L("SPEC_LABEL"), 10, P.muted)
    specLabel:SetPoint("TOPLEFT", PAD, -140)
    local spec, specShell = UIElements.CreateEditBox(panel, "PartyLensSpecEditBox", 130, 30)
    partyLens.specBox = spec
    specShell:SetPoint("TOPLEFT", PAD, -156)
    spec:SetText(partyLens.db.spec or "")
    spec:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "spec", partyLens) end)

    local roleLabel = UIElements.CreateLabel(panel, L("ROLE_LABEL"), 10, P.muted)
    roleLabel:SetPoint("TOPLEFT", PAD + 146, -140)
    local role, roleShell = UIElements.CreateEditBox(panel, "PartyLensRoleEditBox", 100, 30)
    partyLens.roleBox = role
    roleShell:SetPoint("TOPLEFT", PAD + 146, -156)
    role:SetText(partyLens.db.role or "")
    role:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "role", partyLens) end)

    local commentLabel = UIElements.CreateLabel(panel, L("COMMENT_LABEL"), 10, P.muted)
    commentLabel:SetPoint("TOPLEFT", PAD + 262, -140)
    local comment, commentShell = UIElements.CreateEditBox(panel, "PartyLensCommentEditBox", 100, 30)
    partyLens.commentBox = comment
    commentShell:SetPoint("TOPLEFT", PAD + 262, -156)
    commentShell:SetPoint("RIGHT", -PAD, 0)
    comment:SetText(partyLens.db.comment or "")
    comment:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "comment", partyLens) end)

    local templateLabel = UIElements.CreateLabel(panel, L("TEMPLATE_LABEL"), 10, P.muted)
    templateLabel:SetPoint("TOPLEFT", PAD, -198)
    local template, templateShell = UIElements.CreateEditBox(panel, "PartyLensTemplateEditBox", 100, 32)
    partyLens.templateBox = template
    templateShell:SetPoint("TOPLEFT", PAD, -214)
    templateShell:SetPoint("RIGHT", -PAD, 0)
    template:SetText(partyLens.db.template or "")
    template:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "template", partyLens) end)

    local hint = UIElements.CreateLabel(panel, L("TEMPLATE_HINT"), 10, P.faint)
    hint:SetPoint("TOPLEFT", PAD, -258)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")
end

-- ===========================================================================
-- Sidebar nav button
-- ===========================================================================
local function NavButton(parent, text, y, accent, onClick)
    local b = UIElements.CreateButton(parent, text, SIDEBAR_W - 20, 32, accent)
    b:SetPoint("TOPLEFT", 10, y)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 12, 0)
    b.label:SetJustifyH("LEFT")
    b:SetScript("OnClick", onClick)
    return b
end

function UIMain.CreateMainUI(partyLens)
    if partyLens.frame then
        return
    end
    local P = UIElements.PALETTE

    partyLens.mode = partyLens.db.mode or "browse"
    if not MODES[partyLens.mode] then
        partyLens.mode = "browse"
    end

    local frame = UIElements.CreatePanel(UIParent, "PartyLensFrame", P.shell, P.strokeHot)
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
    tinsert(UISpecialFrames, "PartyLensFrame")

    -- Sidebar (brand + nav).
    local sidebar = UIElements.CreatePanel(frame, "PartyLensSidebar", { 0.055, 0.065, 0.082, 0.72 }, P.stroke)
    sidebar:SetPoint("TOPLEFT", 8, -8)
    sidebar:SetPoint("BOTTOMLEFT", 8, 8)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:EnableMouse(true)
    sidebar:RegisterForDrag("LeftButton")
    sidebar:SetScript("OnDragStart", function() frame:StartMoving() end)
    sidebar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local logo = sidebar:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 10, -10)
    logo:SetSize(32, 32)
    logo:SetTexture("Interface\\AddOns\\PartyLens\\Icon")

    local title = UIElements.CreateLabel(sidebar, L("TITLE"), 15, P.text)
    title:SetPoint("TOPLEFT", 48, -13)
    local subtitle = UIElements.CreateLabel(sidebar, L("SUBTITLE"), 9, P.muted)
    subtitle:SetPoint("TOPLEFT", 48, -31)
    subtitle:SetPoint("RIGHT", -8, 0)
    subtitle:SetJustifyH("LEFT")

    partyLens.navButtons = {}
    local navOrder = {
        { key = "browse", labelKey = "MODE_BROWSE", accent = P.teal },
        { key = "autopilot", labelKey = "AP_TITLE", accent = P.blue },
        { key = "create", labelKey = "TAB_CREATE", accent = P.gold },
        { key = "settings", labelKey = "TAB_SETTINGS", accent = P.coral },
    }
    local navY = -64
    for _, nav in ipairs(navOrder) do
        local key = nav.key
        partyLens.navButtons[key] = NavButton(sidebar, L(nav.labelKey), navY, nav.accent, function()
            UIMain.SetMode(partyLens, key)
        end)
        navY = navY - 38
    end

    -- Content header (panel title + count + close).
    local chead = CreateFrame("Frame", "PartyLensContentHeader", frame)
    chead:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    chead:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    chead:SetHeight(40)

    partyLens.headerTitle = UIElements.CreateLabel(chead, L("MODE_BROWSE"), 16, P.text)
    partyLens.headerTitle:SetPoint("LEFT", 4, 0)

    local close = UIElements.CreateButton(chead, L("CLOSE"), 28, 26, P.coral)
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    local countPill = UIElements.CreateChip(chead, 92, 24, P.teal)
    countPill:SetPoint("RIGHT", close, "LEFT", -10, 0)
    countPill:SetAccent(P.teal)
    countPill:SetLabel(L("RESULT_COUNT", 0))
    partyLens.countPill = countPill
    partyLens.countLabel = countPill.text

    -- Content host (the four panels fill this).
    local hostPanel = UIElements.CreatePanel(frame, "PartyLensHost", { 0.040, 0.050, 0.065, 0.45 }, P.stroke)
    hostPanel:SetPoint("TOPLEFT", chead, "BOTTOMLEFT", 0, -6)
    hostPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    partyLens.host = hostPanel

    CreateResultsPanel(partyLens, hostPanel)
    CreateCreatePanel(partyLens, hostPanel)
    CreateSettingsPanel(partyLens, hostPanel)
    CreateAutopilotPanel(partyLens, hostPanel)

    UIMain.SetMode(partyLens, partyLens.mode)
end

_G[ADDON_NAME .. "_UIMain"] = UIMain
return UIMain
