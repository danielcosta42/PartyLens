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
local Summon = _G[ADDON_NAME .. "_Summon"]
local Who = _G[ADDON_NAME .. "_Who"]
local Layer = _G[ADDON_NAME .. "_Layer"]
local LayerNet = _G[ADDON_NAME .. "_LayerNet"]
local WorldBoss = _G[ADDON_NAME .. "_WorldBoss"]
local LayerBuffs = _G[ADDON_NAME .. "_LayerBuffs"]
local Reputation = _G[ADDON_NAME .. "_Reputation"]

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
local MODES = { browse = true, create = true, settings = true, autopilot = true, summon = true, layer = true, radar = true, network = true, circle = true }

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
    summon = "SUMMON_TITLE",
    layer = "LAYER_TITLE",
    radar = "WB_TITLE",
    network = "NET_TITLE",
    circle = "CIRCLE_TITLE",
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

    -- A live refresh timer runs only while the Summon screen is up.
    if partyLens._summonTicker then
        partyLens._summonTicker:Cancel()
        partyLens._summonTicker = nil
    end

    HideFrame(partyLens.resultsPanel)
    HideFrame(partyLens.createPanel)
    HideFrame(partyLens.settingsPanel)
    HideFrame(partyLens.autopilotPanel)
    HideFrame(partyLens.summonPanel)
    HideFrame(partyLens.layerPanel)
    HideFrame(partyLens.radarPanel)
    HideFrame(partyLens.networkPanel)
    HideFrame(partyLens.circlePanel)
    HideFrame(partyLens.countPill)
    HideFrame(partyLens.compPopup)

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
    elseif mode == "summon" then
        ShowFrame(partyLens.summonPanel)
        UIMain.RefreshSummon(partyLens)
        if C_Timer and C_Timer.NewTicker then
            partyLens._summonTicker = C_Timer.NewTicker(1.5, function()
                UIMain.RefreshSummon(partyLens)
            end)
        end
    elseif mode == "layer" then
        ShowFrame(partyLens.layerPanel)
        UIMain.RefreshLayer(partyLens)
        if C_Timer and C_Timer.NewTicker then
            partyLens._summonTicker = C_Timer.NewTicker(1.5, function()
                UIMain.RefreshLayer(partyLens)
            end)
        end
    elseif mode == "radar" then
        ShowFrame(partyLens.radarPanel)
        UIMain.RefreshRadar(partyLens)
        if C_Timer and C_Timer.NewTicker then
            partyLens._summonTicker = C_Timer.NewTicker(2, function()
                UIMain.RefreshRadar(partyLens)
            end)
        end
    elseif mode == "network" then
        ShowFrame(partyLens.networkPanel)
        UIMain.RefreshNetwork(partyLens)
        if C_Timer and C_Timer.NewTicker then
            partyLens._summonTicker = C_Timer.NewTicker(2, function()
                UIMain.RefreshNetwork(partyLens)
            end)
        end
    elseif mode == "circle" then
        ShowFrame(partyLens.circlePanel)
        UIMain.RefreshCircle(partyLens)
        if C_Timer and C_Timer.NewTicker then
            partyLens._summonTicker = C_Timer.NewTicker(2, function()
                UIMain.RefreshCircle(partyLens)
            end)
        end
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

    -- Positive-vouch count (community trust) — a dot + count, teal when someone I've
    -- grouped with is among the voters, gold otherwise. Hidden when nobody vouched.
    row.trustChip = UIElements.CreateChip(row, 44, 20)
    row.trustChip:EnableDot()
    row.trustChip:SetPoint("LEFT", row.plBadge, "RIGHT", 7, 0)
    row.trustChip:Hide()

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
    -- A real click is the only context where SendWho is permitted on this
    -- client, so the /who level+class lookup is driven from here. Route it
    -- through the Who module so the result is harvested into the row (level
    -- appears + the level filter can use it), throttled and de-duped.
    row.who:SetScript("OnClick", function(button)
        local entry = button:GetParent().entry
        if entry and entry.leader and Who then
            local name = (entry.leaderDisplay and entry.leaderDisplay ~= "" and entry.leaderDisplay)
                or Utils.PlayerShortName(entry.leader)
            Who.Lookup(partyLens, name)
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

-- TBC class roster (no Death Knight). Order groups tanks/healers loosely first.
local CLASS_FILTER_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function SetClassFilter(partyLens, classFile, value)
    partyLens.db.classFilter = partyLens.db.classFilter or {}
    -- Store as a sparse set (nil to clear) so `next()` cheaply tells us whether
    -- any class filter is active.
    partyLens.db.classFilter[classFile] = value and true or nil
    partyLens:Refresh()
end

local function SetMinLevel(partyLens, text)
    local n = tonumber(Utils.Trim(text or "")) or 0
    n = math.max(0, math.min(70, n)) -- TBC level cap is 70
    partyLens.db.minLevel = n
    partyLens:Refresh()
end

-- TBC specializations per class, each mapped to a role so picking specs derives
-- the tank/heal/dps totals. Spec is a recruiting WISHLIST (it can't be verified
-- for strangers on this client), so it shapes your plan + role math; the CLASS
-- is the hard gate for who Autopilot invites. Druid Feral defaults to dps (its
-- bear/cat split isn't distinguishable here); adjust counts to taste.
local CLASS_SPECS = {
    WARRIOR = { { key = "arms", role = "dps", en = "Arms", pt = "Armas" }, { key = "fury", role = "dps", en = "Fury", pt = "Fúria" }, { key = "prot", role = "tank", en = "Protection", pt = "Proteção" } },
    PALADIN = { { key = "holy", role = "heal", en = "Holy", pt = "Sagrado" }, { key = "prot", role = "tank", en = "Protection", pt = "Proteção" }, { key = "ret", role = "dps", en = "Retribution", pt = "Retribuição" } },
    HUNTER  = { { key = "bm", role = "dps", en = "Beast Mastery", pt = "Domínio" }, { key = "mm", role = "dps", en = "Marksmanship", pt = "Precisão" }, { key = "surv", role = "dps", en = "Survival", pt = "Sobrevivência" } },
    ROGUE   = { { key = "assa", role = "dps", en = "Assassination", pt = "Assassínio" }, { key = "combat", role = "dps", en = "Combat", pt = "Combate" }, { key = "sub", role = "dps", en = "Subtlety", pt = "Sutileza" } },
    PRIEST  = { { key = "disc", role = "heal", en = "Discipline", pt = "Disciplina" }, { key = "holy", role = "heal", en = "Holy", pt = "Sagrado" }, { key = "shadow", role = "dps", en = "Shadow", pt = "Sombra" } },
    SHAMAN  = { { key = "ele", role = "dps", en = "Elemental", pt = "Elemental" }, { key = "enh", role = "dps", en = "Enhancement", pt = "Aperfeiç." }, { key = "resto", role = "heal", en = "Restoration", pt = "Restaur." } },
    MAGE    = { { key = "arcane", role = "dps", en = "Arcane", pt = "Arcano" }, { key = "fire", role = "dps", en = "Fire", pt = "Fogo" }, { key = "frost", role = "dps", en = "Frost", pt = "Gelo" } },
    WARLOCK = { { key = "affli", role = "dps", en = "Affliction", pt = "Aflição" }, { key = "demo", role = "dps", en = "Demonology", pt = "Demonol." }, { key = "destro", role = "dps", en = "Destruction", pt = "Destruição" } },
    DRUID   = { { key = "balance", role = "dps", en = "Balance", pt = "Equilíbrio" }, { key = "feral", role = "dps", en = "Feral", pt = "Feral" }, { key = "resto", role = "heal", en = "Restoration", pt = "Restaur." } },
}

local function SpecName(spec)
    if Localization.CurrentLocale == "ptBR" and spec.pt then
        return spec.pt
    end
    return spec.en
end

-- Sums the composition into tank/heal/dps totals (+ overall count).
local function CompTotals(partyLens)
    local comp = (partyLens.db.autopilot and partyLens.db.autopilot.comp) or {}
    local t, h, d = 0, 0, 0
    for classFile, specList in pairs(CLASS_SPECS) do
        local picks = comp[classFile]
        if picks then
            for _, spec in ipairs(specList) do
                local n = tonumber(picks[spec.key]) or 0
                if n > 0 then
                    if spec.role == "tank" then t = t + n
                    elseif spec.role == "heal" then h = h + n
                    else d = d + n end
                end
            end
        end
    end
    return t, h, d, (t + h + d)
end

local function CompActive(partyLens)
    return select(4, CompTotals(partyLens)) > 0
end

-- The player's own class specs (from CLASS_SPECS) + the class token.
local function PlayerSpecList()
    local _, classToken = UnitClass("player")
    return CLASS_SPECS[classToken or ""], classToken
end

-- Index (1-3) of the talent tree with the most points — the player's active
-- spec. Returns nil if the talent API is unavailable or no points are spent yet.
-- Tree order matches CLASS_SPECS order for every TBC class, so the index maps
-- straight onto the spec list. Defensive: a bad/absent API just yields nil and
-- the manual picker still works.
local function DetectSpecIndex()
    if not (GetNumTalentTabs and GetTalentTabInfo) then
        return nil
    end
    local tabs = GetNumTalentTabs() or 0
    local best, bestPts = nil, 0
    for i = 1, tabs do
        -- Modern-engine Anniversary client (post-4.4.0) signature:
        --   id, name, description, icon, pointsSpent, background, ...
        -- (pointsSpent is the 5th return, NOT the 3rd as on legacy Classic).
        -- Fall back to the legacy 3rd-slot value if the 5th isn't numeric.
        local ok, r1, r2, r3, r4, r5 = pcall(GetTalentTabInfo, i)
        local pts = (ok and (tonumber(r5) or tonumber(r3))) or 0
        if pts > bestPts then
            bestPts = pts
            best = i
        end
    end
    return best
end

-- Derived role set from a set of spec keys (using each spec's role).
local function SpecRolesFromKeys(specKeys, specs)
    local roleSet = { tank = false, heal = false, dps = false }
    if specs and specKeys then
        for _, s in ipairs(specs) do
            if specKeys[s.key] then
                roleSet[s.role] = true
            end
        end
    end
    return roleSet
end

-- Builds a shared spec picker into `parent`: an "Auto" chip (detect the active
-- spec from talents) + one toggle chip per class spec. Selecting specs is
-- multi-select and pins manual mode; the roles the player matches for are derived
-- from the chosen specs. Every instance is registered so RefreshSpecPickers keeps
-- them all in sync (the same picker appears in Settings and Autopilot "find").
-- point = { "TOPLEFT", x, y } for the Auto chip; withRoleHint adds a "→ roles" tag.
local function BuildSpecChips(partyLens, parent, point, withRoleHint)
    local P = UIElements.PALETTE
    local specs = PlayerSpecList()
    partyLens.specPickers = partyLens.specPickers or {}
    local group = { specChips = {} }

    local auto = UIElements.CreateButton(parent, L("SPEC_AUTO"), 50, 24, P.teal)
    auto:SetPoint(point[1], point[2], point[3])
    auto:SetScript("OnClick", function()
        partyLens.db.specAuto = true
        UIMain.CommitSpec(partyLens)
    end)
    group.autoChip = auto

    local prev = auto
    if specs then
        for _, s in ipairs(specs) do
            local chip = UIElements.CreateButton(parent, SpecName(s), 90, 24, P.blue)
            chip:SetPoint("LEFT", prev, "RIGHT", 5, 0)
            local key = s.key
            chip:SetScript("OnClick", function()
                local db = partyLens.db
                db.specAuto = false
                db.specKeys = db.specKeys or {}
                db.specKeys[key] = (not db.specKeys[key]) or nil
                UIMain.CommitSpec(partyLens)
            end)
            group.specChips[key] = chip
            prev = chip
        end
    end

    if withRoleHint then
        group.roleHint = UIElements.CreateLabel(parent, "", 10, P.gold)
        group.roleHint:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    end

    partyLens.specPickers[#partyLens.specPickers + 1] = group
    return group
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

    -- Toolbar row 3: class + minimum-level filters (also govern who Autopilot
    -- invites, hence the hint).
    local classLabel = UIElements.CreateLabel(panel, L("CLASS_FILTER_LABEL"), 10, P.muted)
    classLabel:SetPoint("TOPLEFT", PAD, -104)

    partyLens.db.classFilter = partyLens.db.classFilter or {}
    partyLens.classToggles = {}
    local prevClass
    for _, cf in ipairs(CLASS_FILTER_ORDER) do
        local toggle = UIElements.CreateClassToggle(panel, cf, 22)
        toggle.className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf
        if prevClass then
            toggle:SetPoint("LEFT", prevClass, "RIGHT", 4, 0)
        else
            toggle:SetPoint("TOPLEFT", PAD, -120)
        end
        toggle:SetSelected(partyLens.db.classFilter[cf] and true or false)
        toggle.onToggle = function(classFile, selected) SetClassFilter(partyLens, classFile, selected) end
        partyLens.classToggles[cf] = toggle
        prevClass = toggle
    end

    local levelLabel = UIElements.CreateLabel(panel, L("MIN_LEVEL_LABEL"), 10, P.muted)
    levelLabel:SetPoint("TOPLEFT", PAD + 264, -104)
    local minLevel, minLevelShell = UIElements.CreateEditBox(panel, "PartyLensMinLevelEditBox", 56, 26)
    partyLens.minLevelBox = minLevel
    minLevelShell:SetPoint("TOPLEFT", PAD + 264, -120)
    minLevel:SetNumeric(true)
    minLevel:SetMaxLetters(2)
    minLevel:SetText(tostring(partyLens.db.minLevel or 0))
    minLevel:SetPlaceholder("0")
    minLevel:SetScript("OnTextChanged", function(editBox)
        SetMinLevel(partyLens, editBox:GetText())
        editBox:UpdatePlaceholder()
    end)

    local filterHint = UIElements.CreateLabel(panel, L("FILTER_INVITE_HINT"), 9, P.faint)
    filterHint:SetPoint("TOPLEFT", PAD + 264 + 74, -110)
    filterHint:SetPoint("RIGHT", -PAD, 0)
    filterHint:SetJustifyH("LEFT")

    -- Results scroll area.
    local scrollFrame = CreateFrame("ScrollFrame", "PartyLensScrollFrame", panel)
    partyLens.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", PAD, -152)
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
    activityDropdown.searchPlaceholder = L("SEARCH_ACTIVITY")
    activityDropdown.levelShort = L("LEVEL_SHORT")
    activityDropdown:EnableSearch(true)
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
        ap.roleSection:SetText(role == "build" and L("AP_WHO_BUILD") or L("AP_WHO_FIND"))
    end
    if role == "build" then
        ShowFrame(ap.buildBox)
        HideFrame(ap.findBox)
    else
        HideFrame(ap.buildBox)
        ShowFrame(ap.findBox)
    end
    -- Adjust rows that only apply to one goal (guards are nil-safe until the
    -- find-only toggles exist).
    if ap.autoAnnounceToggle then ap.autoAnnounceToggle:SetShown(role == "build") end
    if ap.kwLabel then ap.kwLabel:SetShown(role == "build") end
    if ap.kwShell then ap.kwShell:SetShown(role == "build") end
    if ap.autoWhisperToggle then ap.autoWhisperToggle:SetShown(role == "find") end
    if ap.findStrictToggle then ap.findStrictToggle:SetShown(role == "find") end
end

local function UpdateAutopilotTier(partyLens)
    local ap = partyLens.ap
    if not ap or not ap.modeAutoBtn then return end
    local tier = partyLens.db.autopilot.tier or "auto"
    ap.modeAutoBtn:SetActive(tier == "auto")
    ap.modeSuggestBtn:SetActive(tier == "suggest")
    if UIMain.RefreshAutopilot then UIMain.RefreshAutopilot(partyLens) end
end

-- Collapse/expand the Adjust disclosure on the Setup face (progressive disclosure).
-- The summary + divider + Arm shift down by the Adjust box height when it's open so
-- nothing overlaps. Only the Setup face reflows; the Cockpit face is fixed.
local AP_ADJ_HEIGHT = 96
local function LayoutAP(partyLens)
    local ap = partyLens.ap
    if not ap or not ap.summary then return end
    local open = partyLens.db.autopilot.adjustOpen and true or false
    if ap.adjustToggle then
        -- Plain ASCII carets: the WoW default font has no small-triangle glyphs
        -- (they render as tofu). Mirrors the dropdown's "v" caret.
        ap.adjustToggle:SetText((open and "v  " or ">  ") .. L("AP_ADJUST"))
    end
    if ap.adjBox then ap.adjBox:SetShown(open) end
    local s = open and AP_ADJ_HEIGHT or 0
    ap.summaryDivider:ClearAllPoints()
    ap.summaryDivider:SetPoint("TOPLEFT", PAD, -204 - s)
    ap.summaryDivider:SetPoint("RIGHT", -PAD, 0)
    ap.summary:ClearAllPoints()
    ap.summary:SetPoint("TOPLEFT", PAD, -218 - s)
    ap.summary:SetPoint("RIGHT", -PAD, 0)
    ap.armBtn:ClearAllPoints()
    ap.armBtn:SetPoint("TOPLEFT", PAD, -256 - s)
end

local function UpdateAutopilotContent(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    for key, btn in pairs(ap.contentBtns) do
        btn:SetActive(key == partyLens.db.autopilot.activityType)
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

-- A spec chip inside the composition popup: shows the spec name and, once you
-- want one or more, a "×N" count. Click cycles the count 0→1→2→3→0.
local function MakeSpecChip(parent, classFile, spec, rgb, partyLens)
    local chip = UIElements.CreateButton(parent, SpecName(spec), 104, 24, { rgb[1], rgb[2], rgb[3], 1 })
    chip.specKey = spec.key
    chip.specName = SpecName(spec)
    function chip:SetCount(n)
        n = tonumber(n) or 0
        if n > 0 then
            self:SetText(self.specName .. "  x" .. n)
            self:SetActive(true)
        else
            self:SetText(self.specName)
            self:SetActive(false)
        end
    end
    chip:SetScript("OnClick", function()
        local comp = partyLens.db.autopilot.comp or {}
        partyLens.db.autopilot.comp = comp
        comp[classFile] = comp[classFile] or {}
        local n = (tonumber(comp[classFile][spec.key]) or 0) + 1
        if n > 3 then n = 0 end
        comp[classFile][spec.key] = (n > 0) and n or nil
        if not next(comp[classFile]) then
            comp[classFile] = nil
        end
        UIMain.CommitComp(partyLens)
    end)
    return chip
end

-- The composition editor: a class-per-row grid of spec chips. Lives as a modal
-- over the main window (opened from the Autopilot build card) so it has room to
-- breathe. Repainted by UIMain.RefreshComp.
local function CreateCompPopup(partyLens)
    local P = UIElements.PALETTE
    local pop = UIElements.CreatePanel(partyLens.frame, "PartyLensCompPopup", P.shell, P.strokeHot, true)
    partyLens.compPopup = pop
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetSize(540, 60 + #CLASS_FILTER_ORDER * 32 + 50)
    pop:SetPoint("CENTER", partyLens.frame, "CENTER", 0, 0)
    pop:EnableMouse(true)
    pop:Hide()
    pop.rows = {}

    local title = UIElements.CreateLabel(pop, L("COMP_TITLE"), 15, P.text)
    title:SetPoint("TOPLEFT", 16, -14)

    local close = UIElements.CreateButton(pop, L("CLOSE"), 28, 24, P.coral)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() pop:Hide() end)

    local sub = UIElements.CreateLabel(pop, L("COMP_HINT"), 10, P.muted)
    sub:SetPoint("TOPLEFT", 16, -34)
    sub:SetPoint("RIGHT", -16, 0)
    sub:SetJustifyH("LEFT")

    local y = -58
    for _, classFile in ipairs(CLASS_FILTER_ORDER) do
        local row = CreateFrame("Frame", nil, pop)
        row:SetPoint("TOPLEFT", 16, y)
        row:SetPoint("RIGHT", pop, "RIGHT", -16, 0)
        row:SetHeight(28)
        row.chips = {}

        local iconFrame = UIElements.CreatePanel(row, nil, { 0.06, 0.07, 0.09, 0.9 }, P.stroke)
        iconFrame:SetSize(24, 24)
        iconFrame:SetPoint("LEFT", 0, 0)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
            icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            local co = CLASS_ICON_TCOORDS[classFile]
            icon:SetTexCoord(co[1], co[2], co[3], co[4])
        end

        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        local rgb = cc and { cc.r, cc.g, cc.b, 1 } or P.text
        local nameLabel = UIElements.CreateLabel(row,
            (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile, 11, rgb)
        nameLabel:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
        nameLabel:SetWidth(94)
        nameLabel:SetJustifyH("LEFT")

        local prevChip
        for _, spec in ipairs(CLASS_SPECS[classFile]) do
            local chip = MakeSpecChip(row, classFile, spec, rgb, partyLens)
            if prevChip then
                chip:SetPoint("LEFT", prevChip, "RIGHT", 6, 0)
            else
                chip:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0)
            end
            row.chips[#row.chips + 1] = chip
            prevChip = chip
        end
        pop.rows[classFile] = row
        y = y - 32
    end

    pop.needLabel = UIElements.CreateLabel(pop, "", 12, P.gold)
    pop.needLabel:SetPoint("BOTTOMLEFT", 16, 18)

    local clear = UIElements.CreateButton(pop, L("COMP_CLEAR"), 90, 26, P.coral)
    clear:SetPoint("BOTTOMRIGHT", -122, 12)
    clear:SetScript("OnClick", function()
        partyLens.db.autopilot.comp = {}
        UIMain.CommitComp(partyLens)
    end)

    local done = UIElements.CreateButton(pop, L("COMP_DONE"), 96, 26, P.teal)
    done:SetPoint("BOTTOMRIGHT", -16, 12)
    done:SetScript("OnClick", function() pop:Hide() end)

    -- Modal click-catcher: without it, controls in the main window's margin
    -- (sidebar, header close) stay clickable under the "modal". A full-window
    -- button one level below the popup swallows outside clicks and dismisses,
    -- mirroring the dropdown catcher in UIElements.
    local catcher = CreateFrame("Button", nil, partyLens.frame)
    catcher:SetAllPoints(partyLens.frame)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnClick", function() pop:Hide() end)
    pop.catcher = catcher
    pop:SetScript("OnShow", function(self)
        catcher:Show()
        catcher:SetFrameLevel(math.max(0, self:GetFrameLevel() - 1))
    end)
    pop:SetScript("OnHide", function() catcher:Hide() end)
end

-- A row of small squares showing group fill. Filled = seated, hollow = open.
-- Textures are created lazily on parent.pips and reused across repaints.
local AP_PIP_MAX = 40
local function SetPips(parent, filled, total)
    local P = UIElements.PALETTE
    parent.pips = parent.pips or {}
    total = math.min(total or 0, AP_PIP_MAX)
    filled = filled or 0
    for i = 1, AP_PIP_MAX do
        local pip = parent.pips[i]
        if i <= total then
            if not pip then
                pip = parent:CreateTexture(nil, "ARTWORK")
                pip:SetSize(12, 12)
                pip:SetPoint("LEFT", (i - 1) * 16, 0)
                parent.pips[i] = pip
            end
            local on = i <= filled
            pip:SetColorTexture(
                on and P.teal[1] or P.stroke[1],
                on and P.teal[2] or P.stroke[2],
                on and P.teal[3] or P.stroke[3],
                on and 1 or 0.5)
            pip:Show()
        elseif pip then
            pip:Hide()
        end
    end
end

-- Builds the live COCKPIT face (status, slot pips, roster, live action, log).
-- Declared here so CreateAutopilotPanel can call it; repainted by RefreshCockpit.
local function CreateAutopilotCockpit(partyLens, face)
    local P = UIElements.PALETTE
    local ap = partyLens.ap

    -- Config summary line + an edit affordance (disarms and returns to Setup).
    ap.cfgLine = UIElements.CreateLabel(face, "", 11, P.muted)
    ap.cfgLine:SetPoint("TOPLEFT", PAD, -PAD)
    ap.cfgLine:SetJustifyH("LEFT")
    ap.editBtn = UIElements.CreateButton(face, L("AP_EDIT"), 64, 20, P.blue)
    ap.editBtn:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    ap.editBtn:SetScript("OnClick", function()
        Autopilot.Disarm(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    -- Big status: a live dot + state text, with DISARM on the right.
    ap.statusDot = face:CreateTexture(nil, "ARTWORK")
    ap.statusDot:SetSize(10, 10)
    ap.statusDot:SetPoint("TOPLEFT", PAD, -48)
    ap.statusLabel = UIElements.CreateLabel(face, "", 14, P.text)
    ap.statusLabel:SetPoint("LEFT", ap.statusDot, "RIGHT", 8, 0)
    ap.disarmBtn = UIElements.CreateButton(face, L("AP_DISARM"), 120, 26, P.coral)
    ap.disarmBtn:SetPoint("TOPRIGHT", -PAD, -42)
    ap.disarmBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    -- Progress: n/target + slot pips + roster names + remaining need. Find mode
    -- swaps the progress/pips/roster for a running contacts count (RefreshCockpit).
    ap.progressLabel = UIElements.CreateLabel(face, "", 11, P.muted)
    ap.progressLabel:SetPoint("TOPLEFT", PAD, -86)
    ap.contactsLabel = UIElements.CreateLabel(face, "", 11, P.muted)
    ap.contactsLabel:SetPoint("TOPLEFT", PAD, -86)
    ap.contactsLabel:Hide()
    ap.pipRow = CreateFrame("Frame", nil, face)
    ap.pipRow:SetPoint("TOPLEFT", PAD, -106)
    ap.pipRow:SetSize(600, 14)
    ap.rosterLabel = UIElements.CreateLabel(face, "", 11, P.text)
    ap.rosterLabel:SetPoint("TOPLEFT", PAD, -128)
    ap.rosterLabel:SetPoint("RIGHT", -PAD, 0)
    ap.rosterLabel:SetJustifyH("LEFT")
    ap.needLabel = UIElements.CreateLabel(face, "", 11, P.gold)
    ap.needLabel:SetPoint("TOPLEFT", PAD, -148)
    ap.needLabel:SetPoint("RIGHT", -PAD, 0)
    ap.needLabel:SetJustifyH("LEFT")

    -- Live action: Announce ready (build) + GO (suggest mode, when pending).
    ap.announceBtn = UIElements.CreateButton(face, L("AP_ANNOUNCE_BTN"), 150, 28, P.gold)
    ap.announceBtn:SetPoint("TOPLEFT", PAD, -178)
    ap.announceBtn:SetScript("OnClick", function() Autopilot.AnnounceReady(partyLens) end)
    ap.goBtn = UIElements.CreateButton(face, L("AP_GO"), 80, 28, P.gold)
    ap.goBtn:SetPoint("LEFT", ap.announceBtn, "RIGHT", 8, 0)
    ap.goBtn:SetScript("OnClick", function() Autopilot.PressGo(partyLens) end)
    ap.goBtn:Hide()

    -- Activity log.
    ap.logHeader = UIElements.CreateLabel(face, L("AP_LOG_TITLE"), 10, P.muted)
    ap.logHeader:SetPoint("TOPLEFT", PAD, -220)
    ap.logLines = {}
    for i = 1, 6 do
        local line = UIElements.CreateLabel(face, "", 10, P.faint)
        line:SetPoint("TOPLEFT", PAD, -240 - (i - 1) * 16)
        line:SetPoint("RIGHT", -PAD, 0)
        line:SetJustifyH("LEFT")
        line:Hide()
        ap.logLines[i] = line
    end
end

local function CreateAutopilotPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensAutopilotPanel", host)
    partyLens.autopilotPanel = panel
    panel:SetAllPoints(host)

    local ap = {}
    partyLens.ap = ap

    -- Two faces on one panel: a calm SETUP face while disarmed and a live COCKPIT
    -- face while armed. RefreshAutopilot shows exactly one, keyed on rt.armed, so
    -- configuration and live operation never share the screen.
    local setupFace = CreateFrame("Frame", nil, panel)
    setupFace:SetAllPoints(panel)
    ap.setupFace = setupFace
    local cockpitFace = CreateFrame("Frame", nil, panel)
    cockpitFace:SetAllPoints(panel)
    cockpitFace:Hide()
    ap.cockpitFace = cockpitFace

    -- Live mesh count sits on the shared panel (shown on both faces), top-right.
    ap.meshLabel = UIElements.CreateLabel(panel, "", 11, P.teal)
    ap.meshLabel:SetPoint("TOPRIGHT", -PAD, -PAD)
    ap.meshLabel:SetJustifyH("RIGHT")

    -- ================= SETUP FACE =================
    -- A small-caps step-label on the left, controls on the right — a clean
    -- top-to-bottom form (Goal -> Content -> Group), extras behind Adjust, a
    -- plain-language summary, then a prominent Arm.
    local LX, CX = PAD, PAD + 88
    local function StepLabel(text, y)
        local l = UIElements.CreateLabel(setupFace, text, 10, P.muted)
        l:SetPoint("TOPLEFT", LX, y)
        return l
    end

    -- 1) GOAL — build a group (LFM) vs find one (LFG).
    StepLabel(L("AP_GOAL_LABEL"), -46)
    ap.roleBuildBtn = UIElements.CreateButton(setupFace, L("AP_ROLE_BUILD"), 260, 26, P.teal)
    ap.roleBuildBtn:SetPoint("TOPLEFT", CX, -42)
    ap.roleBuildBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "build"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)
    ap.roleFindBtn = UIElements.CreateButton(setupFace, L("AP_ROLE_FIND"), 176, 26, P.gold)
    ap.roleFindBtn:SetPoint("LEFT", ap.roleBuildBtn, "RIGHT", 6, 0)
    ap.roleFindBtn:SetPoint("RIGHT", -PAD, 0) -- stretch to fill the row (equal halves)
    ap.roleFindBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "find"
        UpdateAutopilotRole(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    -- 2) CONTENT — dungeon / raid / any + a specific activity.
    StepLabel(L("AP_CONTENT_LABEL"), -84)
    ap.contentBtns = {}
    local contentOrder = {
        { key = "dungeon", labelKey = "TAB_DUNGEONS", color = P.teal, width = 82 },
        { key = "raid", labelKey = "TAB_RAIDS", color = P.blue, width = 50 },
        { key = "quest", labelKey = "FILTER_QUESTS", color = P.gold, width = 58 },
        { key = "any", labelKey = "FILTER_ALL", color = P.purple, width = 44 },
    }
    local prevContent
    for _, c in ipairs(contentOrder) do
        local btn = UIElements.CreateButton(setupFace, L(c.labelKey), c.width, 26, c.color)
        if prevContent then
            btn:SetPoint("LEFT", prevContent, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", CX, -80)
        end
        local key = c.key
        btn:SetScript("OnClick", function()
            partyLens.db.autopilot.activityType = key
            -- A quest selection only makes sense under the Quest content type.
            if key ~= "quest" then
                partyLens.db.autopilot.questID = nil
            end
            UpdateAutopilotContent(partyLens)
            UIMain.RefreshAutopilotActivities(partyLens, true)
            -- Auto-fill a comfortable size for the content type (build only, and
            -- only when the player hasn't defined an explicit class/spec comp).
            if partyLens.db.autopilot.role == "build" and not CompActive(partyLens) then
                if key == "dungeon" or key == "quest" then
                    ApplyComp(partyLens, ComfortableComp(5))
                elseif key == "raid" then
                    ApplyComp(partyLens, ComfortableComp(25))
                end
            end
            UIMain.RefreshAutopilot(partyLens)
        end)
        ap.contentBtns[c.key] = btn
        prevContent = btn
    end

    local activityDropdown = UIElements.CreateDropdown(setupFace, 200, 26, P.purple)
    ap.activityDropdown = activityDropdown
    activityDropdown.placeholder = L("AP_ANY_ACTIVITY")
    activityDropdown.searchPlaceholder = L("SEARCH_ACTIVITY")
    activityDropdown.levelShort = L("LEVEL_SHORT")
    activityDropdown:EnableSearch(true)
    activityDropdown:SetPoint("LEFT", prevContent, "RIGHT", 10, 0)
    activityDropdown:SetPoint("RIGHT", -PAD, 0)
    activityDropdown.onSelect = function(value)
        local cfg = partyLens.db.autopilot
        if value == "__retry__" then
            LFGTool.RequestActivities()
            UIMain.RefreshAutopilotActivities(partyLens, true)
            return
        elseif value == "__any__" then
            cfg.activityFilter = ""
            cfg.activityID = nil
            cfg.questID = nil
            UIMain.RefreshAutopilot(partyLens)
            return
        end
        local label, maxp
        for _, opt in ipairs(activityDropdown.allOptions or activityDropdown.options) do
            if opt.value == value then
                label = opt.label
                maxp = opt.maxPlayers
                break
            end
        end
        -- Quests carry a "q:"..questID value; real activities carry a numeric id.
        local qid = tostring(value):match("^q:(%d+)$")
        if qid then
            cfg.questID = tonumber(qid)
            cfg.activityID = nil
        else
            cfg.activityID = tonumber(value)
            cfg.questID = nil
        end
        cfg.activityFilter = label or ""
        -- Match the size to the picked activity/quest (build only, and only when no
        -- explicit class/spec comp is set).
        if maxp and cfg.role == "build" and not CompActive(partyLens) then
            ApplyComp(partyLens, ComfortableComp(maxp))
        end
        UIMain.RefreshAutopilot(partyLens)
    end

    -- 3) GROUP (build) / YOUR ROLE (find) — the label swaps in UpdateAutopilotRole.
    -- Only one of buildBox/findBox is shown at a time; the other is hidden by role.
    ap.roleSection = StepLabel("", -126)
    local buildBox = CreateFrame("Frame", nil, setupFace)
    ap.buildBox = buildBox
    buildBox:SetPoint("TOPLEFT", CX, -122)
    buildBox:SetPoint("RIGHT", -PAD, 0)
    buildBox:SetHeight(30)

    -- Composition editor (opens the class/spec popup) + derived need readout.
    -- The invite keyword and automation toggles moved to the Adjust section.
    ap.compBtn = UIElements.CreateButton(buildBox, L("COMP_EDIT"), 150, 28, P.teal)
    ap.compBtn:SetPoint("TOPLEFT", 0, -2)
    ap.compBtn:SetScript("OnClick", function() UIMain.OpenComp(partyLens) end)

    ap.compNeed = UIElements.CreateLabel(buildBox, "", 11, P.gold)
    ap.compNeed:SetPoint("LEFT", ap.compBtn, "RIGHT", 12, 0)
    ap.compNeed:SetPoint("RIGHT", 0, 0)
    ap.compNeed:SetJustifyH("LEFT")

    -- Find box occupies the same WHO slot: spec picker only (keyword/toggles live
    -- in Adjust). Only one of buildBox/findBox is shown at a time.
    local findBox = CreateFrame("Frame", nil, setupFace)
    ap.findBox = findBox
    findBox:SetPoint("TOPLEFT", CX, -122)
    findBox:SetPoint("RIGHT", -PAD, 0)
    findBox:SetHeight(30)

    -- The roles the player answers for come from their spec(s) — the same picker
    -- as Settings (multi-select, unified). Pick 2+ specs to match groups needing
    -- any of those roles.
    BuildSpecChips(partyLens, findBox, { "TOPLEFT", 0, -2 }, true)

    -- 4) ADJUST — extras that are set once and forgotten (progressive disclosure):
    -- automation mode, invite keyword, safety knobs, channel announce.
    ap.adjustToggle = UIElements.CreateButton(setupFace, "", 140, 22, P.blue)
    ap.adjustToggle:SetPoint("TOPLEFT", PAD, -170)
    ap.adjustToggle:SetScript("OnClick", function()
        partyLens.db.autopilot.adjustOpen = not partyLens.db.autopilot.adjustOpen
        LayoutAP(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)

    local adj = CreateFrame("Frame", nil, setupFace)
    ap.adjBox = adj
    adj:SetPoint("TOPLEFT", PAD, -196)
    adj:SetPoint("RIGHT", -PAD, 0)
    adj:SetHeight(96)

    -- Automation: 2 named modes (auto fires immediately; suggest queues for GO).
    local modeLabel = UIElements.CreateLabel(adj, L("AP_MODE_LABEL"), 10, P.muted)
    modeLabel:SetPoint("TOPLEFT", 0, -4)
    ap.modeAutoBtn = UIElements.CreateButton(adj, L("AP_MODE_AUTO"), 120, 24, P.teal)
    ap.modeAutoBtn:SetPoint("TOPLEFT", 96, 0)
    ap.modeAutoBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.tier = "auto"
        UpdateAutopilotTier(partyLens)
    end)
    ap.modeSuggestBtn = UIElements.CreateButton(adj, L("AP_MODE_SUGGEST"), 120, 24, P.blue)
    ap.modeSuggestBtn:SetPoint("LEFT", ap.modeAutoBtn, "RIGHT", 6, 0)
    ap.modeSuggestBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.tier = "suggest"
        UpdateAutopilotTier(partyLens)
    end)

    -- Invite keyword (build): the word a recruit whispers to get an auto-invite.
    ap.kwLabel = UIElements.CreateLabel(adj, L("AP_KEYWORD_SHORT"), 10, P.muted)
    ap.kwLabel:SetPoint("TOPLEFT", 0, -36)
    local kwBox, kwShell = UIElements.CreateEditBox(adj, "PartyLensAPKeyword", 86, 26)
    kwShell:SetPoint("LEFT", ap.kwLabel, "RIGHT", 8, 0)
    ap.kwShell = kwShell
    kwBox:SetText(partyLens.db.autopilot.inviteKeyword or "inv")
    kwBox:SetScript("OnTextChanged", function(editBox)
        partyLens.db.autopilot.inviteKeyword = Utils.Trim(editBox:GetText())
    end)

    -- Safety knobs: whisper cooldown + minimum item level.
    local cdLabel = UIElements.CreateLabel(adj, L("AP_COOLDOWN_LABEL"), 9, P.muted)
    cdLabel:SetPoint("LEFT", kwShell, "RIGHT", 22, 0)
    local cdBox, cdShell = UIElements.CreateEditBox(adj, "PartyLensAPCooldown", 46, 26)
    cdShell:SetPoint("LEFT", cdLabel, "RIGHT", 8, 0)
    cdBox:SetText(tostring(partyLens.db.autopilot.whisperCooldown or 20))
    cdBox:SetScript("OnTextChanged", function(editBox) SaveAutopilotNumber(editBox, "whisperCooldown", partyLens, 5) end)
    local ilvlLabel = UIElements.CreateLabel(adj, L("LISTING_ILVL_LABEL"), 9, P.muted)
    ilvlLabel:SetPoint("LEFT", cdShell, "RIGHT", 18, 0)
    local ilvlBox, ilvlShell = UIElements.CreateEditBox(adj, "PartyLensAPIlvl", 46, 26)
    ilvlShell:SetPoint("LEFT", ilvlLabel, "RIGHT", 8, 0)
    ilvlBox:SetText(tostring(partyLens.db.autopilot.minIlvl or 0))
    ilvlBox:SetScript("OnTextChanged", function(editBox) SaveAutopilotNumber(editBox, "minIlvl", partyLens, 0) end)

    -- Channel announce (build): auto-spam an LFM line in the LFG channel.
    ap.autoAnnounceToggle = UIElements.CreateToggle(adj, L("AP_AUTO_ANNOUNCE"), 240)
    ap.autoAnnounceToggle:SetPoint("TOPLEFT", 0, -68)
    ap.autoAnnounceToggle:SetChecked(partyLens.db.autopilot.autoAnnounce)
    ap.autoAnnounceToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoAnnounce = check:GetChecked()
    end)

    -- Find-only toggles share the same row (shown by role in UpdateAutopilotRole):
    -- auto-whisper recruiting leaders + strict role/class matching.
    ap.autoWhisperToggle = UIElements.CreateToggle(adj, L("AP_AUTO_WHISPER"), 200)
    ap.autoWhisperToggle:SetPoint("TOPLEFT", 0, -68)
    ap.autoWhisperToggle:SetChecked(partyLens.db.autopilot.autoWhisper)
    ap.autoWhisperToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.autoWhisper = check:GetChecked()
    end)
    ap.findStrictToggle = UIElements.CreateToggle(adj, L("AP_FIND_STRICT"), 240)
    ap.findStrictToggle:SetPoint("TOPLEFT", 260, -68)
    ap.findStrictToggle:SetChecked(partyLens.db.autopilot.findStrict ~= false)
    ap.findStrictToggle:SetScript("OnClick", function(check)
        check:SetChecked(not check:GetChecked())
        partyLens.db.autopilot.findStrict = check:GetChecked()
    end)

    -- 5) Summary sentence + ARM. Final positions are set by LayoutAP (they shift
    -- down when Adjust is open).
    ap.summaryDivider = UIElements.CreateDivider(setupFace)
    ap.summaryDivider:SetPoint("TOPLEFT", PAD, -204)
    ap.summaryDivider:SetPoint("RIGHT", -PAD, 0)

    ap.summary = UIElements.CreateLabel(setupFace, "", 11, P.gold)
    ap.summary:SetPoint("TOPLEFT", PAD, -218)
    ap.summary:SetPoint("RIGHT", -PAD, 0)
    ap.summary:SetJustifyH("LEFT")

    ap.armBtn = UIElements.CreateButton(setupFace, L("AP_ARM"), 210, 36, P.teal)
    ap.armBtn:SetPoint("TOPLEFT", PAD, -256)
    ap.armBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens)
        UIMain.RefreshAutopilot(partyLens)
    end)
    ap.setupStatus = UIElements.CreateLabel(setupFace, "", 12, P.muted)
    ap.setupStatus:SetPoint("LEFT", ap.armBtn, "RIGHT", 12, 0)
    ap.setupStatus:SetText(L("AP_STATUS_IDLE"))

    -- ================= COCKPIT FACE =================
    -- Live widgets (status, slot pips, roster, log) are added in a later step.
    CreateAutopilotCockpit(partyLens, cockpitFace)

    CreateCompPopup(partyLens)

    UpdateAutopilotRole(partyLens)
    UpdateAutopilotTier(partyLens)
    UpdateAutopilotContent(partyLens)
    LayoutAP(partyLens)
    UIMain.RefreshAutopilotActivities(partyLens, true)
    UIMain.RefreshComp(partyLens)
    -- Re-sync the spec pickers now that the find-box picker exists too.
    UIMain.CommitSpec(partyLens)
end

-- Applies a composition change: derives the tank/heal/dps totals (which feed the
-- size gate, the mesh, and the LFM announce) and repaints the readouts. When the
-- comp is emptied the last totals are left in place so recruiting-by-size still
-- works. The class GATE is read live from the comp by Autopilot.RecruitFilter, so
-- nothing else needs writing here.
function UIMain.CommitComp(partyLens)
    local t, h, d, total = CompTotals(partyLens)
    local cfg = partyLens.db.autopilot
    if total > 0 then
        cfg.needTank, cfg.needHeal, cfg.needDps = t, h, d
    else
        -- Comp emptied (Clear, or the last spec cycled to 0): revert the size
        -- gate to the selected content's default instead of stranding the just-
        -- cleared comp's per-role totals (which would make Autopilot recruit the
        -- wrong headcount). Mirrors the content-button auto-fill.
        cfg.needTank, cfg.needHeal, cfg.needDps =
            ComfortableComp(cfg.activityType == "raid" and 25 or 5)
    end
    UIMain.RefreshComp(partyLens)
    if UIMain.RefreshAutopilot then
        UIMain.RefreshAutopilot(partyLens)
    end
end

-- Repaints the build-card readout/button and, if open, the popup's spec chips
-- and derived-need footer.
function UIMain.RefreshComp(partyLens)
    local ap = partyLens.ap
    local comp = (partyLens.db.autopilot and partyLens.db.autopilot.comp) or {}
    local t, h, d, total = CompTotals(partyLens)

    if ap and ap.compNeed then
        if total > 0 then
            local parts = {}
            if t > 0 then parts[#parts + 1] = t .. "T" end
            if h > 0 then parts[#parts + 1] = h .. "H" end
            if d > 0 then parts[#parts + 1] = d .. "D" end
            ap.compNeed:SetText(table.concat(parts, " ") .. "  ·  " .. total)
        else
            ap.compNeed:SetText(L("COMP_NONE"))
        end
    end

    local pop = partyLens.compPopup
    if pop then
        for classFile, row in pairs(pop.rows) do
            local picks = comp[classFile]
            for _, chip in ipairs(row.chips) do
                chip:SetCount(picks and picks[chip.specKey] or 0)
            end
        end
        if pop.needLabel then
            pop.needLabel:SetText(L("COMP_NEED", t, h, d, total))
        end
    end
end

function UIMain.OpenComp(partyLens)
    if not partyLens.compPopup then
        return
    end
    UIMain.RefreshComp(partyLens)
    partyLens.compPopup:Show()
    partyLens.compPopup:Raise()
end

-- Readable derived roles, e.g. "Heal / DPS", from db.myRoles.
function UIMain.RolesText(partyLens)
    local mr = partyLens.db.myRoles or {}
    local parts = {}
    if mr.tank then parts[#parts + 1] = L("ROLE_TANK") end
    if mr.heal then parts[#parts + 1] = L("ROLE_HEAL") end
    if mr.dps then parts[#parts + 1] = L("ROLE_DPS") end
    return table.concat(parts, " / ")
end

-- Central spec commit: (re)derives db.spec / db.role / db.myRoles from the chosen
-- specs (db.specKeys). In Auto mode it first sets specKeys to the single detected
-- talent spec (updates on respec). db.myRoles then drives find matching, the mesh,
-- and the whisper {role}; db.spec fills {spec}. Called from the pickers, on login,
-- and on respec.
function UIMain.CommitSpec(partyLens)
    local db = partyLens.db
    if not db then
        return
    end
    local specs = PlayerSpecList()
    db.specKeys = db.specKeys or {}

    -- Drop any pinned key that isn't valid for the player's class (defensive).
    if specs then
        local valid = {}
        for _, s in ipairs(specs) do valid[s.key] = true end
        for key in pairs(db.specKeys) do
            if not valid[key] then db.specKeys[key] = nil end
        end
    end

    if db.specAuto then
        -- Only replace the detected spec when detection actually resolves one.
        -- On login the talent API may not be populated yet (DetectSpecIndex
        -- returns nil); wiping first would collapse the roles to the dps
        -- fallback until the next talent event, silently mis-broadcasting a
        -- healer/tank as dps. Keep the prior specKeys through a transient nil.
        local idx = DetectSpecIndex()
        if idx and specs and specs[idx] then
            if wipe then wipe(db.specKeys) else db.specKeys = {} end
            db.specKeys[specs[idx].key] = true
        end
    end

    local names = {}
    if specs then
        for _, s in ipairs(specs) do
            if db.specKeys[s.key] then
                names[#names + 1] = SpecName(s)
            end
        end
    end
    local roleSet = SpecRolesFromKeys(db.specKeys, specs)
    if not (roleSet.tank or roleSet.heal or roleSet.dps) then
        roleSet.dps = true -- never leave find matching with zero roles
    end
    db.spec = table.concat(names, " / ")
    db.myRoles = roleSet
    -- Primary role token for Search scoring + legacy consumers.
    db.role = (roleSet.tank and "tank") or (roleSet.heal and "heal") or "dps"

    UIMain.RefreshSpecPickers(partyLens)
    if UIMain.RefreshAutopilot then
        UIMain.RefreshAutopilot(partyLens)
    end
end

-- Back-compat name used by Core's login / talent-change events.
function UIMain.DetectAndApplySpec(partyLens)
    UIMain.CommitSpec(partyLens)
end

-- Syncs every spec picker instance (Settings + Autopilot "find") to db state.
function UIMain.RefreshSpecPickers(partyLens)
    local roleHint = "\194\183  " .. UIMain.RolesText(partyLens) -- "· Heal / DPS" (middledot renders; → does not)
    for _, g in ipairs(partyLens.specPickers or {}) do
        if g.autoChip then
            g.autoChip:SetActive(partyLens.db.specAuto and true or false)
        end
        for key, chip in pairs(g.specChips) do
            chip:SetActive(partyLens.db.specKeys and partyLens.db.specKeys[key] and true or false)
        end
        if g.roleHint then
            g.roleHint:SetText(roleHint)
        end
    end
end

local function ActivityIsHeroic(label)
    local l = string.lower(label or "")
    return string.find(l, "heroic", 1, true)
        or string.find(l, "heroica", 1, true)
        or string.find(l, "%f[%a]hc%f[%A]") ~= nil
end

local function ActivityCategory(item, content)
    if content == "quest" then
        return "quest", L("FILTER_QUESTS"), 1
    elseif content == "dungeon" then
        if ActivityIsHeroic(item.label) then
            return "heroic", L("AP_CAT_HEROIC"), 2
        end
        return "normal", L("AP_CAT_NORMAL"), 1
    elseif content == "raid" then
        local size = item.maxPlayers or 0
        return "r" .. size, L("AP_CAT_RAID_SIZE", size), size
    else
        -- "All": split into Dungeons(Normal), Dungeons(Heroic), Raids, Quests
        -- instead of one flat list.
        if item.kind == "quest" then
            return "quest", L("FILTER_QUESTS"), 4
        end
        if (item.maxPlayers or 0) > 5 or item.kind == "raid" then
            return "raids", L("TAB_RAIDS"), 3
        end
        if ActivityIsHeroic(item.label) then
            return "dh", L("TAB_DUNGEONS") .. " \194\183 " .. L("AP_CAT_HEROIC"), 2
        end
        return "dn", L("TAB_DUNGEONS") .. " \194\183 " .. L("AP_CAT_NORMAL"), 1
    end
end

function UIMain.RefreshAutopilotActivities(partyLens, allowRequest)
    local ap = partyLens.ap
    if not ap or not ap.activityDropdown then
        return
    end

    local content = partyLens.db.autopilot.activityType
    local current = (partyLens.db.autopilot.questID and ("q:" .. partyLens.db.autopilot.questID))
        or partyLens.db.autopilot.activityID or "__any__"
    local lists
    if content == "raid" then
        lists = { LFGTool.GetActivityList("raids") }
    elseif content == "dungeon" then
        lists = { LFGTool.GetActivityList("dungeons") }
    elseif content == "quest" then
        lists = { LFGTool.GetQuestActivities() }
    else
        lists = { LFGTool.GetActivityList("dungeons"), LFGTool.GetActivityList("raids"), LFGTool.GetQuestActivities() }
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
        if content == "quest" then
            -- Quests come from your log, not the finder catalog — nothing to retry.
            options[#options + 1] = { value = "__questempty__", label = L("AP_QUEST_EMPTY"), header = true }
        else
            if allowRequest then
                LFGTool.RequestActivities()
            end
            options[#options + 1] = { value = "__retry__", label = L("LISTING_PICK_EMPTY") }
        end
        ap.activityDropdown:SetOptions(options, current)
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
            options[#options + 1] = { value = item.value, label = item.label, indent = true,
                maxPlayers = item.maxPlayers, minLevel = item.minLevel, levelText = item.levelText }
        end
    end

    ap.activityDropdown:SetOptions(options, current)
end

-- Full resync of the autopilot panel from db (content buttons, role boxes, the
-- activity list, the panel). Used when config changes programmatically rather than
-- via a click on the panel — e.g. the quest-log "Find Group" hook.
function UIMain.SyncAutopilot(partyLens)
    if not partyLens.ap then
        return
    end
    UpdateAutopilotContent(partyLens)
    UpdateAutopilotRole(partyLens)
    UIMain.RefreshAutopilotActivities(partyLens, true)
    UIMain.RefreshAutopilot(partyLens)
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

    -- "PartyLens on the mesh": count the living network, not just users who
    -- happen to be advertising an LFG intent right now. Every PL user announces
    -- presence via ChehulNet (the "pl" tag), automatically and realm-wide, so
    -- that is the canonical source (same living-mesh feel as "Nodes online").
    -- Union in any advertising entries too, in case a signed chat/Comm line
    -- arrived before that peer's presence HELLO propagated. Deduped by name.
    local seen = {}
    local CN = _G.ChehulNet
    if CN and CN.peers then
        for name, p in pairs(CN.peers) do
            if p.addons and p.addons["pl"] then
                seen[Utils.SafeLower((Ambiguate and Ambiguate(name, "short")) or name)] = true
            end
        end
    end
    for _, e in ipairs(partyLens.entries or {}) do
        if e.isAddonUser and e.leader and e.leader ~= "" then
            seen[Utils.SafeLower((Ambiguate and Ambiguate(e.leader, "short")) or e.leader)] = true
        end
    end
    local plCount = 0
    for _ in pairs(seen) do plCount = plCount + 1 end
    ap.meshLabel:SetText(L("AP_MESH_COUNT", plCount))

    -- Show exactly one face: live cockpit while armed, calm setup otherwise.
    if armed then
        ap.setupFace:Hide()
        ap.cockpitFace:Show()
        if UIMain.RefreshCockpit then UIMain.RefreshCockpit(partyLens) end
        return
    end
    ap.cockpitFace:Hide()
    ap.setupFace:Show()

    ap.armBtn:SetText(L("AP_ARM"))
    ap.armBtn:SetAccent(P.teal)
    ap.setupStatus:SetText(L("AP_STATUS_IDLE"))

    -- Plain-language preview of what arming will do (so the config reads as a sentence).
    if ap.summary then
        local modeLabel = cfg.tier == "suggest" and L("AP_MODE_SUGGEST") or L("AP_MODE_AUTO")
        local contentLabel = (cfg.activityFilter and cfg.activityFilter ~= "" and cfg.activityFilter)
            or L(cfg.activityType == "raid" and "TAB_RAIDS"
                or cfg.activityType == "any" and "FILTER_ALL" or "TAB_DUNGEONS")
        if cfg.role == "build" then
            ap.summary:SetText(L("AP_SUMMARY_BUILD", contentLabel, modeLabel, cfg.inviteKeyword or "inv"))
        else
            local rolesText = (UIMain.RolesText and UIMain.RolesText(partyLens)) or ""
            if rolesText == "" then rolesText = "dps" end
            ap.summary:SetText(L("AP_SUMMARY_FIND", contentLabel, rolesText, modeLabel))
        end
    end
end

-- Repaints the live COCKPIT face (only while armed). Build mode shows the group
-- filling up (progress + slot pips + roster + remaining need); find mode swaps in
-- a contacts count (added in the find-mode step).
function UIMain.RefreshCockpit(partyLens)
    local ap = partyLens.ap
    if not ap or not ap.statusLabel then
        return
    end
    local P = UIElements.PALETTE
    local cfg = partyLens.db.autopilot
    local rt = partyLens.autopilot
    local state = (rt and rt.state) or "searching"

    local modeLabel = cfg.tier == "suggest" and L("AP_MODE_SUGGEST") or L("AP_MODE_AUTO")
    local contentLabel = (cfg.activityFilter and cfg.activityFilter ~= "" and cfg.activityFilter)
        or L(cfg.activityType == "raid" and "TAB_RAIDS"
            or cfg.activityType == "any" and "FILTER_ALL" or "TAB_DUNGEONS")
    local roleWord = cfg.role == "build" and L("AP_ROLE_BUILD") or L("AP_ROLE_FIND")
    ap.cfgLine:SetText(roleWord .. "  \194\183  " .. contentLabel .. "  \194\183  " .. modeLabel)

    ap.statusLabel:SetText(L(AP_STATE_LABEL[state] or "AP_STATUS_SEARCHING"))
    local live = (state == "ready") and P.freshNew or P.teal
    ap.statusDot:SetColorTexture(live[1], live[2], live[3], 1)

    ap.goBtn:SetShown(rt and rt.pendingAction ~= nil)

    if cfg.role == "find" then
        -- Joining, not building: no roster/pips — show how many groups we contacted.
        ap.progressLabel:Hide()
        ap.pipRow:Hide()
        ap.rosterLabel:Hide()
        ap.announceBtn:Hide()
        ap.contactsLabel:Show()
        -- rt.contactCount is a TABLE ([lowerShortName] = attempts); count distinct names.
        local contacted = 0
        for _ in pairs((rt and rt.contactCount) or {}) do contacted = contacted + 1 end
        ap.contactsLabel:SetText(L("AP_CONTACTED", contacted))
        local rolesText = (UIMain.RolesText and UIMain.RolesText(partyLens)) or ""
        if rolesText == "" then rolesText = "dps" end
        ap.cfgLine:SetText(roleWord .. "  \194\183  " .. contentLabel
            .. "  \194\183  " .. rolesText .. "  \194\183  " .. modeLabel)
        ap.needLabel:SetText(L("AP_MYROLE_LABEL") .. ": " .. rolesText)
        ap.needLabel:SetTextColor(P.muted[1], P.muted[2], P.muted[3], 1)
    else
        local need, snap = Roster.Needed(partyLens)
        local target = snap.size + math.max(0, need.total or 0)

        ap.contactsLabel:Hide()
        ap.progressLabel:Show()
        ap.pipRow:Show()
        ap.rosterLabel:Show()
        ap.progressLabel:SetText(L("AP_GROUP_PROGRESS", snap.size, target))
        SetPips(ap.pipRow, snap.size, target)
        local names = {}
        for _, m in ipairs(snap.members) do
            names[#names + 1] = Utils.ClassColoredName(m.name or "", m.classFile)
        end
        ap.rosterLabel:SetText(table.concat(names, ", "))

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
        UIElements.SetButtonEnabled(ap.announceBtn, snap.size > 1)
        ap.announceBtn:Show()
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

    -- Spec picker: Auto (detected from talents) or pick the spec(s) you play.
    -- The roles you match for are DERIVED from the specs (shown to the right), so
    -- a Resto/Balance druid matches groups needing heal OR dps.
    local specLabel = UIElements.CreateLabel(panel, L("SPEC_LABEL"), 10, P.muted)
    specLabel:SetPoint("TOPLEFT", PAD, -140)
    BuildSpecChips(partyLens, panel, { "TOPLEFT", PAD, -158 }, true)

    local commentLabel = UIElements.CreateLabel(panel, L("COMMENT_LABEL"), 10, P.muted)
    commentLabel:SetPoint("TOPLEFT", PAD, -192)
    local comment, commentShell = UIElements.CreateEditBox(panel, "PartyLensCommentEditBox", 100, 30)
    partyLens.commentBox = comment
    commentShell:SetPoint("TOPLEFT", PAD, -208)
    commentShell:SetPoint("RIGHT", -PAD, 0)
    comment:SetText(partyLens.db.comment or "")
    comment:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "comment", partyLens) end)

    local templateLabel = UIElements.CreateLabel(panel, L("TEMPLATE_LABEL"), 10, P.muted)
    templateLabel:SetPoint("TOPLEFT", PAD, -244)
    local template, templateShell = UIElements.CreateEditBox(panel, "PartyLensTemplateEditBox", 100, 32)
    partyLens.templateBox = template
    templateShell:SetPoint("TOPLEFT", PAD, -260)
    templateShell:SetPoint("RIGHT", -PAD, 0)
    template:SetText(partyLens.db.template or "")
    template:SetScript("OnTextChanged", function(editBox) SaveEditBox(editBox, "template", partyLens) end)

    local hint = UIElements.CreateLabel(panel, L("TEMPLATE_HINT"), 10, P.faint)
    hint:SetPoint("TOPLEFT", PAD, -300)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")

    -- Credit footer (bottom-right): the author signature, matching the sibling addons.
    local credit = UIElements.CreateLabel(panel, L("CREDIT"), 10, P.muted)
    credit:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    credit:SetJustifyH("RIGHT")
    local link = UIElements.CreateLabel(panel, "|cff5a6470github.com/danielcosta42/PartyLens|r", 9, P.faint)
    link:SetPoint("BOTTOMRIGHT", credit, "TOPRIGHT", 0, 2)
    link:SetJustifyH("RIGHT")

    UIMain.CommitSpec(partyLens)
end

-- ===========================================================================
-- Sidebar nav button
-- ===========================================================================
-- ===========================================================================
-- Summon coordination panel
-- ===========================================================================
local function CreateSummonRow(parent)
    local P = UIElements.PALETTE
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(24)
    row.bg = UIElements.AddTexture(row, "BACKGROUND", { 0, 0, 0, 0 })
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(9, 9)
    row.dot:SetPoint("LEFT", 6, 0)
    row.name = UIElements.CreateLabel(row, "", 12, P.text)
    row.name:SetPoint("LEFT", 22, 0)
    row.status = UIElements.CreateLabel(row, "", 11, P.muted)
    row.status:SetPoint("RIGHT", -10, 0)
    row.status:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self) UIElements.SetTextureColor(self.bg, P.panelHover) end)
    row:SetScript("OnLeave", function(self) UIElements.SetTextureColor(self.bg, { 0, 0, 0, 0 }) end)
    row:Hide()
    return row
end

local function CreateSummonPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensSummonPanel", host)
    partyLens.summonPanel = panel
    panel:SetAllPoints(host)

    local s = {}
    partyLens.summon = s
    partyLens.summonMarked = partyLens.summonMarked or {}

    local hint = UIElements.CreateLabel(panel, L("SUMMON_HINT"), 10, P.muted)
    hint:SetPoint("TOPLEFT", PAD, -PAD)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")

    s.warlock = UIElements.CreateLabel(panel, "", 11, P.purple)
    s.warlock:SetPoint("TOPLEFT", PAD, -48)
    s.warlock:SetPoint("RIGHT", -PAD, 0)
    s.warlock:SetJustifyH("LEFT")

    Section(panel, L("SUMMON_PARTY"), PAD, -76)

    s.rows = {}
    for i = 1, 14 do
        local row = CreateSummonRow(panel)
        row:SetPoint("TOPLEFT", PAD, -96 - (i - 1) * 26)
        row:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        row:SetScript("OnClick", function(self)
            if self.memberName then
                local key = Utils.SafeLower(self.memberName)
                partyLens.summonMarked[key] = (not partyLens.summonMarked[key]) or nil
                UIMain.RefreshSummon(partyLens)
            end
        end)
        s.rows[i] = row
    end

    s.empty = UIElements.CreateLabel(panel, L("SUMMON_EMPTY"), 12, P.faint)
    s.empty:SetPoint("TOP", panel, "TOP", 0, -160)
    s.empty:SetJustifyH("CENTER")
    s.empty:Hide()

    s.announceBtn = UIElements.CreateButton(panel, L("SUMMON_NEEDED_BTN"), 160, 30, P.gold)
    s.announceBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    s.announceBtn:SetScript("OnClick", function()
        Summon.AnnounceNeeded(partyLens, partyLens.summonMarked)
    end)

    s.nextBtn = UIElements.CreateButton(panel, L("SUMMON_NEXT_BTN"), 140, 30, P.teal)
    s.nextBtn:SetPoint("LEFT", s.announceBtn, "RIGHT", 8, 0)
    s.nextBtn:SetScript("OnClick", function()
        Summon.AnnounceNext(partyLens, partyLens.summonMarked)
    end)

    s.resetBtn = UIElements.CreateButton(panel, L("SUMMON_RESET_BTN"), 90, 30, P.coral)
    s.resetBtn:SetPoint("LEFT", s.nextBtn, "RIGHT", 8, 0)
    s.resetBtn:SetScript("OnClick", function()
        partyLens.summonMarked = {}
        UIMain.RefreshSummon(partyLens)
    end)
end

-- Repaints the summon roster (live: in-range status changes as people arrive).
function UIMain.RefreshSummon(partyLens)
    local s = partyLens.summon
    if not s then
        return
    end
    local P = UIElements.PALETTE
    local marked = partyLens.summonMarked or {}
    local list = Summon.Snapshot(marked)

    local locks = Summon.Warlocks()
    if #locks > 0 then
        s.warlock:SetText(L("SUMMON_WARLOCK", table.concat(locks, ", ")))
        s.warlock:Show()
    else
        s.warlock:Hide()
    end

    if #list <= 1 then
        s.empty:Show()
        for _, row in ipairs(s.rows) do row:Hide() end
        UIElements.SetButtonEnabled(s.announceBtn, false)
        UIElements.SetButtonEnabled(s.nextBtn, false)
        UIElements.SetButtonEnabled(s.resetBtn, false)
        return
    end
    s.empty:Hide()
    UIElements.SetButtonEnabled(s.announceBtn, true)
    UIElements.SetButtonEnabled(s.nextBtn, true)
    UIElements.SetButtonEnabled(s.resetBtn, true)

    -- Needs-summon first, then here, then already summoned.
    local function rank(m)
        if m.summoned then return 3 end
        if not m.inRange and not m.isPlayer then return 1 end
        return 2
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end)

    for i, row in ipairs(s.rows) do
        local m = list[i]
        if m then
            row.memberName = m.name
            row.name:SetText(Utils.ClassColoredName(m.name or "", m.classFile))
            local statusKey, color
            if m.summoned then
                statusKey, color = "SUMMON_STATUS_DONE", P.teal
            elseif not m.inRange and not m.isPlayer then
                statusKey, color = "SUMMON_STATUS_NEEDS", P.gold
            else
                statusKey, color = "SUMMON_STATUS_HERE", P.freshNew
            end
            row.status:SetText(L(statusKey))
            row.status:SetTextColor(color[1], color[2], color[3], 1)
            UIElements.SetTextureColor(row.dot, color)
            row:SetAlpha(m.summoned and 0.55 or 1)
            row:Show()
        else
            row.memberName = nil
            row:Hide()
        end
    end
end

-- ===========================================================================
-- Layer network panel
-- ===========================================================================
local function CreateLayerPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensLayerPanel", host)
    partyLens.layerPanel = panel
    panel:SetAllPoints(host)

    local ln = { stats = {}, logLines = {} }
    partyLens.layerUI = ln

    ln.hint = UIElements.CreateLabel(panel, L("LAYER_HINT"), 10, P.muted)
    ln.hint:SetPoint("TOPLEFT", PAD, -PAD)
    ln.hint:SetPoint("RIGHT", -PAD, 0)
    ln.hint:SetJustifyH("LEFT")

    -- World-boss radar banner: hidden until a boss is spotted (by us or the mesh),
    -- then it takes the top strip with a Hop (pull me there) + Shout (public rally)
    -- button. Rare, so it borrows the hint's space rather than a permanent slot.
    ln.bossBanner = UIElements.CreatePanel(panel, nil, { 0.22, 0.09, 0.07, 0.9 }, P.coral, true)
    ln.bossBanner:SetHeight(28)
    ln.bossBanner:SetPoint("TOPLEFT", PAD, -PAD + 2)
    ln.bossBanner:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    ln.bossText = UIElements.CreateLabel(ln.bossBanner, "", 12, P.gold)
    ln.bossText:SetPoint("LEFT", 10, 0)
    ln.bossShout = UIElements.CreateButton(ln.bossBanner, L("WB_SHOUT"), 60, 20, P.gold)
    ln.bossShout:SetPoint("RIGHT", -6, 0)
    ln.bossShout:SetScript("OnClick", function()
        if WorldBoss and ln.bossCurrent then WorldBoss.AnnouncePublic(partyLens, ln.bossCurrent) end
    end)
    ln.bossHop = UIElements.CreateButton(ln.bossBanner, L("WB_HOP"), 50, 20, P.freshNew)
    ln.bossHop:SetPoint("RIGHT", ln.bossShout, "LEFT", -6, 0)
    ln.bossHop:SetScript("OnClick", function()
        if WorldBoss and ln.bossCurrent then WorldBoss.HopTo(partyLens, ln.bossCurrent) end
    end)
    ln.bossBanner:Hide()

    -- Current layer (big) on the left; beacon toggle on the right.
    Section(panel, L("LAYER_CURRENT"), PAD, -46, 260)
    ln.layerBig = UIElements.CreateLabel(panel, "", 30, P.freshNew)
    ln.layerBig:SetPoint("TOPLEFT", PAD, -68)
    ln.layerSub = UIElements.CreateLabel(panel, "", 11, P.muted)
    ln.layerSub:SetPoint("TOPLEFT", PAD, -106)

    ln.beaconBtn = UIElements.CreateButton(panel, "", 210, 40, P.freshNew)
    ln.beaconBtn:SetPoint("TOPRIGHT", -PAD, -62)
    ln.beaconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ln.beaconBtn:SetScript("OnClick", function()
        if LayerNet then LayerNet.ToggleBeacon(partyLens) end
    end)
    -- Auto-beacon toggle ("park and help") sits directly UNDER the beacon button, then
    -- the hint below it — stacked so nothing overlaps in the tight space above "Network".
    ln.autoBeaconBtn = UIElements.CreateButton(panel, "", 210, 16, P.teal)
    ln.autoBeaconBtn:SetPoint("TOPRIGHT", ln.beaconBtn, "BOTTOMRIGHT", 0, -4)
    ln.autoBeaconBtn:SetScript("OnClick", function()
        if LayerNet then LayerNet.ToggleAutoBeacon(partyLens) end
    end)

    local bhint = UIElements.CreateLabel(panel, L("LAYER_BEACON_HINT"), 9, P.faint)
    bhint:SetPoint("TOPRIGHT", ln.autoBeaconBtn, "BOTTOMRIGHT", 0, -3)
    bhint:SetWidth(210)
    bhint:SetJustifyH("RIGHT")

    -- Your beacon-service rank (from lifetime hops served) — the status reward. On the
    -- LEFT column (under the current-layer readout), clear of the right-side buttons.
    ln.rankLabel = UIElements.CreateLabel(panel, "", 11, P.gold)
    ln.rankLabel:SetPoint("TOPLEFT", PAD, -128)
    ln.rankLabel:SetJustifyH("LEFT")
    ln.rankLabel:Hide()

    -- Live network stats (marketing: the "living network" feel).
    Section(panel, L("LAYER_NETWORK"), PAD, -146)
    local statDefs = {
        { key = "nodes", labelKey = "LAYER_NODES", color = P.teal },
        { key = "covered", labelKey = "LAYER_COVERED", color = P.blue },
        { key = "hops", labelKey = "LAYER_HOPS", color = P.gold },
        { key = "requests", labelKey = "LAYER_REQUESTS", color = P.purple },
    }
    local cardW, gap = 138, 10
    for i, d in ipairs(statDefs) do
        local card = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.55 }, P.stroke, true)
        card:SetSize(cardW, 58)
        card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + gap), -170)
        local num = UIElements.CreateLabel(card, "0", 22, d.color)
        num:SetPoint("TOPLEFT", 12, -8)
        local lbl = UIElements.CreateLabel(card, L(d.labelKey), 9, P.muted)
        lbl:SetPoint("BOTTOMLEFT", 12, 8)
        ln.stats[d.key] = num
    end

    -- Requester side — "I want to hop." Tap a KNOWN layer (the picker is built from
    -- the converged mesh set) or "Qualquer"; a dot marks layers with a LIVE beacon,
    -- gold marks the one you're on. No typing. Tapping broadcasts an invisible mesh
    -- request (every beacon on that layer auto-invites me) + one signed public line.
    Section(panel, L("LAYER_HOP"), PAD, -244)
    -- Quietest-layer hint (farming/questing): the least-crowded known layer by mesh
    -- presence. Sits at the right of the "Hop" header; tapping requests a hop there.
    ln.quietRec = UIElements.CreateButton(panel, "", 116, 18, P.teal)
    ln.quietRec:SetPoint("TOPRIGHT", -PAD, -242)
    ln.quietRec:SetScript("OnClick", function()
        local best = LayerNet.QuietestLayer and LayerNet.QuietestLayer(partyLens)
        if not best then return end
        if best.beaconZoneUID and best.beaconMapID and LayerNet.RequestLayerFor then
            LayerNet.RequestLayerFor(partyLens, best.beaconMapID, best.beaconZoneUID)
        else
            LayerNet.RequestLayer(partyLens, tostring(best.ordinal))
        end
    end)
    ln.quietRec:Hide()
    ln.hopHint = UIElements.CreateLabel(panel, L("LAYER_HOP_HINT"), 9, P.faint)
    ln.hopHint:SetPoint("TOPLEFT", PAD, -262)
    ln.hopHint:SetPoint("RIGHT", -PAD, 0)
    ln.hopHint:SetJustifyH("LEFT")

    ln.hopNone = UIElements.CreateLabel(panel, L("LAYER_HOP_NONE"), 11, P.faint)
    ln.hopNone:SetPoint("TOPLEFT", PAD, -282)
    ln.hopNone:SetPoint("RIGHT", -PAD, 0)
    ln.hopNone:SetJustifyH("LEFT")
    ln.hopNone:Hide()

    -- Layer chips are pooled and (re)laid out in RefreshLayer as the set converges.
    ln.chipPool = {}
    ln.chipY = -280

    -- Active-request line + Stop button (shown only while a request is active).
    ln.reqActive = UIElements.CreateLabel(panel, "", 11, P.gold)
    ln.reqActive:SetPoint("TOPLEFT", PAD, -348)
    ln.reqActive:SetWidth(420)
    ln.reqActive:SetJustifyH("LEFT")
    ln.reqCancel = UIElements.CreateButton(panel, L("LAYER_REQ_CANCEL"), 84, 22, P.coral)
    ln.reqCancel:SetPoint("TOPRIGHT", -PAD, -344)
    ln.reqCancel:SetScript("OnClick", function()
        if LayerNet then LayerNet.CancelRequest(partyLens) end
    end)
    ln.reqCancel:Hide()

    -- Beacon status line — tells you WHY it is / isn't inviting (beacon off, layer
    -- unknown, party full, or listening). Prominent because the beacon is silent.
    ln.status = UIElements.CreateLabel(panel, "", 12, P.gold)
    ln.status:SetPoint("TOPLEFT", PAD, -374)
    ln.status:SetPoint("RIGHT", -PAD, 0)
    ln.status:SetJustifyH("LEFT")

    -- Activity log — the beacon acts silently (no chat/party/whisper), so this is
    -- how you actually SEE it working ("invited X -> L5").
    Section(panel, L("LAYER_ACTIVITY"), PAD, -398)
    for i = 1, 5 do
        local line = UIElements.CreateLabel(panel, "", 10, P.faint)
        line:SetPoint("TOPLEFT", PAD, -420 - (i - 1) * 15)
        line:SetPoint("RIGHT", -PAD, 0)
        line:SetJustifyH("LEFT")
        line:Hide()
        ln.logLines[i] = line
    end
    ln.empty = UIElements.CreateLabel(panel, L("LAYER_NO_ACTIVITY"), 11, P.faint)
    ln.empty:SetPoint("TOPLEFT", PAD, -422)
    ln.empty:Hide()
end

-- Lazily create / fetch pooled layer-picker chip #i (a button with a "beacon live"
-- corner dot).
local function HopChip(ln, panel, i)
    local P = UIElements.PALETTE
    local chip = ln.chipPool[i]
    if not chip then
        chip = UIElements.CreateButton(panel, "", 44, 26, P.teal)
        chip.dot = chip:CreateTexture(nil, "OVERLAY")
        chip.dot:SetSize(7, 7)
        chip.dot:SetPoint("TOPRIGHT", -3, -3)
        UIElements.SetTextureColor(chip.dot, P.teal)
        chip.dot:Hide()
        -- Subtle player-count badge: a tiny, faint number in the bottom-right corner
        -- (instead of inline "L1 2"), so the layer number stays the focus. What it means
        -- is spelled out on hover.
        chip.count = UIElements.CreateLabel(chip, "", 8, P.faint)
        chip.count:ClearAllPoints()
        chip.count:SetPoint("BOTTOMRIGHT", -3, 3)
        chip.count:Hide()
        -- World-buff indicator (top-LEFT corner, mirroring the beacon dot at top-right):
        -- coral = a drop buff is landing NOW here (go!), gold = a stable buff (songflower
        -- / zone control) is up. What's up is spelled out on hover.
        chip.buff = chip:CreateTexture(nil, "OVERLAY")
        chip.buff:SetSize(7, 7)
        chip.buff:SetPoint("TOPLEFT", 3, -3)
        chip.buff:Hide()
        -- Tooltip (hooked so the button's own hover effect still runs): the little number
        -- is how many mesh players are on that layer; then the world buffs up there.
        chip:HookScript("OnEnter", function(self)
            if self.tipPeers == nil then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tipTitle or "")
            if self.tipPeers > 0 then
                GameTooltip:AddLine(L("LAYER_CHIP_TIP_COUNT", self.tipPeers), 0.55, 0.60, 0.66, true)
            else
                GameTooltip:AddLine(L("LAYER_CHIP_TIP_EMPTY"), 0.45, 0.49, 0.54, true)
            end
            if self.tipBuffs and #self.tipBuffs > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("LB_TIP_HEADER"), 0.98, 0.74, 0.30)
                for _, b in ipairs(self.tipBuffs) do
                    local when
                    if b.status == "pending" then
                        when = L("LB_DROPPING")
                    elseif b.remaining then
                        when = L("LB_REMAINING", LayerBuffs.FmtTime(b.remaining))
                    else
                        when = ""
                    end
                    if b.urgent then
                        GameTooltip:AddLine("  " .. b.name .. "  -  " .. when, 1.0, 0.42, 0.38)
                    else
                        GameTooltip:AddLine("  " .. b.name .. "  -  " .. when, 0.15, 0.86, 0.72)
                    end
                end
            end
            GameTooltip:Show()
        end)
        chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
        ln.chipPool[i] = chip
    end
    return chip
end

-- Rebuild the layer-picker chips from the converged mesh set. Flow-lays them out
-- (wrapping to a 2nd row if needed) and colours them: gold = your current layer,
-- teal dot = a beacon is live there, dim = known but no beacon yet, highlighted =
-- your active request.
local function RefreshHopChips(partyLens)
    local ln = partyLens.layerUI
    local panel = partyLens.layerPanel
    if not ln or not ln.chipPool or not panel then
        return
    end
    local P = UIElements.PALETTE
    local mr = LayerNet.MyRequest and LayerNet.MyRequest(partyLens)
    local layers = (LayerNet.KnownLayers and LayerNet.KnownLayers(partyLens)) or {}
    -- World-buff picture across all layers, built once (NWB read + native/mesh detections)
    -- so each chip below annotates its layer without recomputing per chip.
    local buffSnap = (LayerBuffs and LayerBuffs.Snapshot and LayerBuffs.Snapshot(partyLens)) or nil
    -- Quietest known layer (fewest mesh peers) — highlight its chip + drive the header
    -- recommendation. Reuse the `layers` list we already built (no second KnownLayers).
    local quiet = LayerNet.QuietestLayer and LayerNet.QuietestLayer(partyLens, layers)
    local curCrowd = LayerNet.CurrentCrowding and LayerNet.CurrentCrowding(partyLens, layers)
    if ln.quietRec then
        -- Only worth showing when there's a real choice (>=2 known layers) and the
        -- quietest is actually less crowded than where I am (else no reason to move).
        if quiet and #layers >= 2 and (curCrowd == nil or (quiet.nodes or 0) < curCrowd) then
            ln.quietRec:SetText(L("LAYER_QUIET_REC", quiet.ordinal, quiet.nodes or 0))
            ln.quietRec:Show()
        else
            ln.quietRec:Hide()
        end
    end

    local right = panel:GetWidth() or 0
    if right < 100 then right = 600 end -- pre-layout fallback
    local x, y = PAD, ln.chipY
    local rowH, idx = 30, 0
    local function place(chip, w)
        chip:SetWidth(w)
        if x + w > right - PAD then
            x, y = PAD, y - rowH -- wrap
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", x, y)
        chip:Show()
        x = x + w + 6
    end

    -- "Qualquer" first.
    idx = idx + 1
    local anyChip = HopChip(ln, panel, idx)
    anyChip.dot:Hide()
    anyChip.count:Hide()
    anyChip.buff:Hide()
    anyChip.tipBuffs = nil
    anyChip.tipPeers = nil -- no count tooltip on "Any"
    anyChip:SetText(L("LAYER_REQ_ANY"))
    anyChip.label:SetTextColor(P.text[1], P.text[2], P.text[3], 1)
    anyChip:SetScript("OnClick", function()
        if LayerNet then LayerNet.RequestLayer(partyLens, "any") end
    end)
    local anySel = (mr and mr.req.any) and true or false
    anyChip:SetActive(anySel)
    if not anySel then anyChip:SetAlpha(1) end
    place(anyChip, 74)

    -- One chip per known layer.
    for _, ly in ipairs(layers) do
        idx = idx + 1
        local ord = ly.ordinal
        local peers = ly.nodes or 0
        local bZone, bMap = ly.beaconZoneUID, ly.beaconMapID
        local chip = HopChip(ln, panel, idx)
        -- Live occupancy: how many PartyLens peers we've heard on this layer, so the picker
        -- doubles as a "which layer is busy / quiet" map. Shown as a tiny faint corner badge
        -- (subtle — the layer number stays the focus); its meaning is on hover.
        chip:SetText("L" .. ord)
        if peers > 0 then
            chip.count:SetText(peers)
            chip.count:Show()
        else
            chip.count:Hide()
        end
        chip.tipPeers = peers
        chip.tipTitle = L("LAYER_N", ord)
        -- World buffs on this layer: a corner indicator (coral = a drop buff landing
        -- NOW, gold = a stable buff up) + the full list on the tooltip.
        local buffs = (LayerBuffs and LayerBuffs.ForOrdinal and buffSnap)
            and LayerBuffs.ForOrdinal(partyLens, ord, buffSnap) or nil
        chip.tipBuffs = buffs and buffs.list or nil
        if buffs and buffs.hasUrgent then
            UIElements.SetTextureColor(chip.buff, P.coral)
            chip.buff:Show()
        elseif buffs and buffs.hasStable then
            UIElements.SetTextureColor(chip.buff, P.gold)
            chip.buff:Show()
        else
            chip.buff:Hide()
        end
        chip:SetScript("OnClick", function()
            if not LayerNet then return end
            -- If a beacon is live on this layer, request its EXACT zoneUID (pin it) so
            -- the match can't miss on a number disagreement between the two clients;
            -- otherwise fall back to the ordinal (broadcast + hope a beacon appears).
            if bZone and bMap and LayerNet.RequestLayerFor then
                LayerNet.RequestLayerFor(partyLens, bMap, bZone)
            else
                LayerNet.RequestLayer(partyLens, tostring(ord))
            end
        end)
        if ly.hasBeacon then chip.dot:Show() else chip.dot:Hide() end
        local isQuietest = quiet and not ly.isCurrent and ly.ordinal == quiet.ordinal
        if ly.isCurrent then
            chip.label:SetTextColor(P.gold[1], P.gold[2], P.gold[3], 1)
        elseif isQuietest then
            chip.label:SetTextColor(P.teal[1], P.teal[2], P.teal[3], 1) -- quietest: teal
        else
            chip.label:SetTextColor(P.text[1], P.text[2], P.text[3], 1)
        end
        local sel = (mr and not mr.req.any and mr.req.layers and mr.req.layers[ord]) and true or false
        chip:SetActive(sel)
        if not sel then
            -- Keep layers with a beacon, my current layer, the quietest, OR live peers at
            -- full opacity; only dim empty known-but-quiet layers.
            chip:SetAlpha((ly.hasBeacon or ly.isCurrent or isQuietest or peers > 0) and 1 or 0.5)
        end
        place(chip, 44) -- uniform width now that the count is a corner badge, not inline
    end

    -- Park any leftover pooled chips.
    for i = idx + 1, #ln.chipPool do
        ln.chipPool[i]:Hide()
    end
    if ln.hopNone then
        if #layers == 0 then ln.hopNone:Show() else ln.hopNone:Hide() end
    end
end

-- Repaints the Layer panel: current layer, beacon state, live stats, request list.
function UIMain.RefreshLayer(partyLens)
    local ln = partyLens.layerUI
    if not ln or not Layer or not LayerNet then
        return
    end
    local cur = Layer.Current(partyLens)
    local stats = LayerNet.Stats(partyLens)

    if cur.ordinal then
        ln.layerBig:SetText(L("LAYER_N", cur.ordinal))
        ln.layerSub:SetText(L("LAYER_OF", cur.count or 1))
    else
        ln.layerBig:SetText("?")
        ln.layerSub:SetText(L("LAYER_UNKNOWN"))
    end

    local on = partyLens.db.layer and partyLens.db.layer.beacon
    ln.beaconBtn:SetText(L("LAYER_BEACON") .. ":  " .. (on and L("LAYER_ON") or L("LAYER_OFF")))
    ln.beaconBtn:SetActive(on and true or false)

    if ln.autoBeaconBtn then
        local auto = partyLens.db.layer and partyLens.db.layer.autoBeacon
        ln.autoBeaconBtn:SetText(L("LAYER_AUTOBEACON") .. ":  " .. (auto and L("LAYER_ON") or L("LAYER_OFF")))
        ln.autoBeaconBtn:SetActive(auto and true or false)
    end
    if ln.rankLabel then
        local hops = (partyLens.db.layer and partyLens.db.layer.hops) or 0
        local title = LayerNet.Rank and LayerNet.Rank(hops)
        if title then
            ln.rankLabel:SetText("|cffffd200" .. title .. "|r  ·  " .. L("LAYER_HOPS_SERVED", hops))
            ln.rankLabel:Show()
        else
            ln.rankLabel:Hide()
        end
    end

    ln.stats.nodes:SetText(stats.nodes)
    ln.stats.covered:SetText(stats.layersCovered)
    ln.stats.hops:SetText(stats.hops)
    ln.stats.requests:SetText(stats.openRequests)

    if ln.status then
        local P = UIElements.PALETTE
        local st, warn = LayerNet.Status(partyLens)
        ln.status:SetText(st)
        local c = warn and P.coral or P.gold
        ln.status:SetTextColor(c[1], c[2], c[3], 1)
    end

    -- World-boss radar: show the banner (over the hint) when something's up.
    if ln.bossBanner then
        local bosses = (WorldBoss and WorldBoss.Active and WorldBoss.Active(partyLens)) or {}
        local top = bosses[1]
        ln.bossCurrent = top
        if top then
            local ord = top.ordinal or "?"
            local txt = (top.hp and top.hp > 0)
                and L("WB_LINE", top.name, ord, top.hp)
                or L("WB_LINE_NOHP", top.name, ord)
            ln.bossText:SetText(txt)
            ln.bossBanner:Show()
            if ln.hint then ln.hint:Hide() end
        else
            ln.bossBanner:Hide()
            if ln.hint then ln.hint:Show() end
        end
    end

    -- Requester side: the layer picker + my own active request line.
    RefreshHopChips(partyLens)
    if ln.reqActive then
        local mr = LayerNet.MyRequest and LayerNet.MyRequest(partyLens)
        if mr then
            ln.reqActive:SetText(L("LAYER_REQ_ACTIVE", LayerNet.RequestText(mr.req)))
            if ln.reqCancel then ln.reqCancel:Show() end
        else
            ln.reqActive:SetText("")
            if ln.reqCancel then ln.reqCancel:Hide() end
        end
    end

    local log = LayerNet.RecentLog(partyLens)
    for i, line in ipairs(ln.logLines) do
        local entry = log[i]
        if entry then
            local stamp = (date and date("%H:%M", entry.t)) or ""
            line:SetText("|cff5a6470" .. stamp .. "|r  " .. (entry.text or ""))
            line:Show()
        else
            line:Hide()
        end
    end
    if ln.empty then
        if #log == 0 then ln.empty:Show() else ln.empty:Hide() end
    end
end

-- ===========================================================================
-- Radar panel — world bosses / rares the network has spotted.
-- ===========================================================================
local function AgoText(t)
    local s = time() - (t or time())
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
end

local function CreateRadarPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensRadarPanel", host)
    partyLens.radarPanel = panel
    panel:SetAllPoints(host)

    local rd = { rows = {} }
    partyLens.radarUI = rd

    local hint = UIElements.CreateLabel(panel, L("WB_HINT"), 10, P.muted)
    hint:SetPoint("TOPLEFT", PAD, -PAD)
    hint:SetPoint("RIGHT", -110, 0)
    hint:SetJustifyH("LEFT")

    -- Crowd-source: flag whatever I'm targeting (rare, boss, invasion) to the realm feed.
    rd.flagBtn = UIElements.CreateButton(panel, L("WB_FLAG"), 96, 22, P.teal)
    rd.flagBtn:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    rd.flagBtn:SetScript("OnClick", function()
        if WorldBoss and WorldBoss.FlagTarget then WorldBoss.FlagTarget(partyLens) end
    end)

    Section(panel, L("WB_ACTIVE"), PAD, -46)

    for i = 1, 6 do
        local card = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.6 }, P.stroke, true)
        card:SetHeight(44)
        card:SetPoint("TOPLEFT", PAD, -70 - (i - 1) * 50)
        card:SetPoint("RIGHT", -PAD, 0)

        card.name = UIElements.CreateLabel(card, "", 13, P.gold)
        card.name:SetPoint("TOPLEFT", 12, -7)
        card.sub = UIElements.CreateLabel(card, "", 10, P.muted)
        card.sub:SetPoint("BOTTOMLEFT", 12, 7)

        card.shout = UIElements.CreateButton(card, L("WB_SHOUT"), 62, 22, P.gold)
        card.shout:SetPoint("RIGHT", -8, 0)
        card.hop = UIElements.CreateButton(card, L("WB_HOP"), 50, 22, P.freshNew)
        card.hop:SetPoint("RIGHT", card.shout, "LEFT", -6, 0)
        card.hop:SetScript("OnClick", function()
            if WorldBoss and card.sighting then WorldBoss.HopTo(partyLens, card.sighting) end
        end)
        card.shout:SetScript("OnClick", function()
            if WorldBoss and card.sighting then WorldBoss.AnnouncePublic(partyLens, card.sighting) end
        end)
        card:Hide()
        rd.rows[i] = card
    end

    rd.empty = UIElements.CreateLabel(panel, L("WB_NONE"), 12, P.faint)
    rd.empty:SetPoint("TOPLEFT", PAD, -74)
    rd.empty:SetPoint("RIGHT", -PAD, 0)
    rd.empty:Hide()
end

function UIMain.RefreshRadar(partyLens)
    local rd = partyLens.radarUI
    if not rd or not WorldBoss then
        return
    end
    local P = UIElements.PALETTE
    local list = WorldBoss.Active(partyLens)
    for i, card in ipairs(rd.rows) do
        local s = list[i]
        if s then
            card.sighting = s
            local c = (s.kind == "boss") and P.gold
                or (s.kind == "flag") and P.teal -- crowd-sourced flag
                or P.coral                        -- elite / rare
            card.name:SetTextColor(c[1], c[2], c[3], 1)
            card.name:SetText(s.name)
            local hp = (s.hp and s.hp > 0) and (s.hp .. "%") or "?"
            card.sub:SetText(L("WB_SUB", s.ordinal or "?", hp, s.spotter or "?", AgoText(s.t)))
            card:Show()
        else
            card.sighting = nil
            card:Hide()
        end
    end
    if rd.empty then
        if #list == 0 then rd.empty:Show() else rd.empty:Hide() end
    end
end

-- ===========================================================================
-- Network panel — live dashboard, the group broker (PartyLens LFG), and the
-- reputation vouch list, all reading data the mesh already gives us.
-- ===========================================================================
local function NetStatCard(panel, i, labelKey, color)
    local P = UIElements.PALETTE
    local cardW, gap = 94, 8
    local card = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.55 }, P.stroke, true)
    card:SetSize(cardW, 52)
    card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + gap), -44)
    card.num = UIElements.CreateLabel(card, "0", 20, color)
    card.num:SetPoint("TOPLEFT", 10, -7)
    card.lbl = UIElements.CreateLabel(card, L(labelKey), 8, P.muted)
    card.lbl:SetPoint("BOTTOMLEFT", 10, 7)
    return card
end

local function InviteName(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        pcall(InviteUnit, name)
    end
end

local function CreateNetworkPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensNetworkPanel", host)
    partyLens.networkPanel = panel
    panel:SetAllPoints(host)

    local nu = { stats = {}, brokerRows = {}, repRows = {} }
    partyLens.networkUI = nu

    local hint = UIElements.CreateLabel(panel, L("NET_HINT"), 10, P.muted)
    hint:SetPoint("TOPLEFT", PAD, -PAD)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")

    -- Live counters.
    local statDefs = {
        { key = "nodes", labelKey = "NET_NODES", color = P.teal },
        { key = "layers", labelKey = "NET_LAYERS", color = P.freshNew },
        { key = "bosses", labelKey = "NET_BOSSES", color = P.coral },
        { key = "hops", labelKey = "NET_HOPS", color = P.gold },
        { key = "reqs", labelKey = "NET_REQS", color = P.purple },
        { key = "rep", labelKey = "NET_REP", color = P.blue },
    }
    for i, d in ipairs(statDefs) do
        nu.stats[d.key] = NetStatCard(panel, i, d.labelKey, d.color)
    end

    -- Broker: PartyLens users looking for group / more.
    Section(panel, L("NET_BROKER"), PAD, -110)
    for i = 1, 4 do
        local row = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.5 }, P.stroke, true)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", PAD, -134 - (i - 1) * 36)
        row:SetPoint("RIGHT", -PAD, 0)
        row.text = UIElements.CreateLabel(row, "", 11, P.text)
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetWidth(360)
        row.text:SetJustifyH("LEFT")
        row.inv = UIElements.CreateButton(row, L("NET_INVITE"), 48, 22, P.teal)
        row.inv:SetPoint("RIGHT", -8, 0)
        row.wsp = UIElements.CreateButton(row, L("NET_WHISPER"), 40, 22, P.blue)
        row.wsp:SetPoint("RIGHT", row.inv, "LEFT", -6, 0)
        row.inv:SetScript("OnClick", function()
            if row.pname then InviteName(row.pname) end
        end)
        row.wsp:SetScript("OnClick", function()
            if row.pname and ChatFrame_SendTell then ChatFrame_SendTell(row.pname) end
        end)
        row:Hide()
        nu.brokerRows[i] = row
    end
    nu.brokerEmpty = UIElements.CreateLabel(panel, L("NET_BROKER_NONE"), 11, P.faint)
    nu.brokerEmpty:SetPoint("TOPLEFT", PAD, -138)
    nu.brokerEmpty:Hide()

    -- Reputation: vouch the people you've grouped with.
    Section(panel, L("NET_REP_SECTION"), PAD, -290)
    for i = 1, 4 do
        local row = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.5 }, P.stroke, true)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", PAD, -314 - (i - 1) * 36)
        row:SetPoint("RIGHT", -PAD, 0)
        row.text = UIElements.CreateLabel(row, "", 11, P.text)
        row.text:SetPoint("LEFT", 10, 0)
        row.vouch = UIElements.CreateButton(row, L("REP_VOUCH_BTN"), 78, 22, P.gold)
        row.vouch:SetPoint("RIGHT", -8, 0)
        row.vouch:SetScript("OnClick", function()
            if Reputation and row.pname then Reputation.Vouch(partyLens, row.pname) end
        end)
        row:Hide()
        nu.repRows[i] = row
    end
    nu.repEmpty = UIElements.CreateLabel(panel, L("NET_REP_NONE"), 11, P.faint)
    nu.repEmpty:SetPoint("TOPLEFT", PAD, -318)
    nu.repEmpty:Hide()
end

function UIMain.RefreshNetwork(partyLens)
    local nu = partyLens.networkUI
    if not nu then
        return
    end
    local stats = (LayerNet and LayerNet.Stats and LayerNet.Stats(partyLens)) or {}
    local bosses = (WorldBoss and WorldBoss.Active and WorldBoss.Active(partyLens)) or {}
    nu.stats.nodes.num:SetText(stats.nodes or 0)
    nu.stats.layers.num:SetText((Layer and Layer.CountOnMap and Layer.CountOnMap(partyLens, Layer.CurrentMap())) or stats.layersCovered or 0)
    nu.stats.bosses.num:SetText(#bosses)
    nu.stats.hops.num:SetText(stats.hops or 0)
    nu.stats.reqs.num:SetText(stats.openRequests or 0)
    nu.stats.rep.num:SetText((Reputation and Reputation.MyScore and Reputation.MyScore(partyLens)) or 0)

    -- Broker: fresh PartyLens LFG/LFM entries.
    local now, matches = time(), {}
    for _, e in ipairs(partyLens.entries or {}) do
        if e.isAddonUser and e.open ~= false and (now - (e.timestamp or 0)) < 300
            and e.leaderDisplay and e.leaderDisplay ~= "" then
            matches[#matches + 1] = e
        end
    end
    table.sort(matches, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    for i, row in ipairs(nu.brokerRows) do
        local e = matches[i]
        if e then
            row.pname = e.leaderDisplay
            row.text:SetText("|cff8fd6c8" .. e.leaderDisplay .. "|r  " .. (e.message or ""))
            row:Show()
        else
            row.pname = nil
            row:Hide()
        end
    end
    if nu.brokerEmpty then
        if #matches == 0 then nu.brokerEmpty:Show() else nu.brokerEmpty:Hide() end
    end

    -- Reputation: groupmates to vouch.
    local mates = (Reputation and Reputation.Groupmates and Reputation.Groupmates(partyLens)) or {}
    for i, row in ipairs(nu.repRows) do
        local m = mates[i]
        if m then
            row.pname = m.name
            local score = (m.count and m.count > 0) and ("  |cff5a6470" .. L("REP_COUNT", m.count) .. "|r") or ""
            row.text:SetText(m.name .. score)
            row.vouch:SetText(m.vouched and L("REP_VOUCHED_BTN") or L("REP_VOUCH_BTN"))
            UIElements.SetButtonEnabled(row.vouch, not m.vouched)
            row:Show()
        else
            row.pname = nil
            row:Hide()
        end
    end
    if nu.repEmpty then
        if #mates == 0 then nu.repEmpty:Show() else nu.repEmpty:Hide() end
    end
end

-- ===========================================================================
-- Circle panel — my mesh social graph: people I've grouped/hopped with, vouched,
-- or who vouched me, each with live "online / reachable now" status + a one-tap
-- hop-to-them / whisper. A pure view over Reputation's data + LayerNet presence.
-- ===========================================================================
local function CreateCirclePanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensCirclePanel", host)
    partyLens.circlePanel = panel
    panel:SetAllPoints(host)

    local cu = { rows = {} }
    partyLens.circleUI = cu

    local hint = UIElements.CreateLabel(panel, L("CIRCLE_HINT"), 10, P.muted)
    hint:SetPoint("TOPLEFT", PAD, -PAD)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetJustifyH("LEFT")

    cu.header = UIElements.CreateLabel(panel, "", 12, P.freshNew)
    cu.header:SetPoint("TOPLEFT", PAD, -34)

    Section(panel, L("CIRCLE_SECTION"), PAD, -54)

    for i = 1, 8 do
        local row = UIElements.CreatePanel(panel, nil, { 0.082, 0.096, 0.120, 0.5 }, P.stroke, true)
        row:SetHeight(38)
        row:SetPoint("TOPLEFT", PAD, -78 - (i - 1) * 44)
        row:SetPoint("RIGHT", -PAD, 0)
        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("LEFT", 10, 0)
        row.name = UIElements.CreateLabel(row, "", 12, P.text)
        row.name:SetPoint("TOPLEFT", 24, -6)
        row.sub = UIElements.CreateLabel(row, "", 9, P.muted)
        row.sub:SetPoint("BOTTOMLEFT", 24, 6)
        row.hop = UIElements.CreateButton(row, L("WB_HOP"), 46, 22, P.freshNew)
        row.hop:SetPoint("RIGHT", -8, 0)
        row.wsp = UIElements.CreateButton(row, L("NET_WHISPER"), 40, 22, P.blue)
        row.wsp:SetPoint("RIGHT", row.hop, "LEFT", -6, 0)
        row.hop:SetScript("OnClick", function()
            if row.node and row.node.mapID and row.node.zoneUID and LayerNet and LayerNet.RequestLayerFor then
                LayerNet.RequestLayerFor(partyLens, row.node.mapID, row.node.zoneUID)
            end
        end)
        row.wsp:SetScript("OnClick", function()
            if row.pname and ChatFrame_SendTell then ChatFrame_SendTell(row.pname) end
        end)
        row:Hide()
        cu.rows[i] = row
    end

    cu.empty = UIElements.CreateLabel(panel, L("CIRCLE_NONE"), 12, P.faint)
    cu.empty:SetPoint("TOPLEFT", PAD, -82)
    cu.empty:SetPoint("RIGHT", -PAD, 0)
    cu.empty:Hide()
end

function UIMain.RefreshCircle(partyLens)
    local cu = partyLens.circleUI
    if not cu or not Reputation or not Reputation.Circle then
        return
    end
    local P = UIElements.PALETTE
    local list = Reputation.Circle(partyLens)
    local online = 0
    for _, e in ipairs(list) do
        if e.online then online = online + 1 end
    end
    if cu.header then
        cu.header:SetText(L("CIRCLE_HEADER", #list, online))
    end
    for i, row in ipairs(cu.rows) do
        local e = list[i]
        if e then
            row.pname = e.name
            row.node = e.node
            local nc = e.online and P.freshNew or P.faint
            row.name:SetTextColor(nc[1], nc[2], nc[3], 1)
            local score = (e.count and e.count > 0) and ("  |cff5a6470" .. L("REP_COUNT", e.count) .. "|r") or ""
            row.name:SetText(e.name .. score)
            -- presence dot: beacon = teal, online = green, offline = grey.
            local dc = (e.node and e.node.beacon and P.teal)
                or (e.online and P.freshNew) or { 0.4, 0.45, 0.5, 1 }
            UIElements.SetTextureColor(row.dot, dc)
            -- relationship reasons.
            local rel = {}
            if e.grouped then rel[#rel + 1] = L("CIRCLE_R_GROUPED") end
            if e.vouchedByMe then rel[#rel + 1] = L("CIRCLE_R_VOUCHED") end
            if e.vouchedMe then rel[#rel + 1] = L("CIRCLE_R_VOUCHEDME") end
            -- presence text.
            local presence
            if e.online then
                if e.node and e.node.sameLayer then
                    presence = L("CIRCLE_P_SAMELAYER")
                elseif e.node and e.node.ordinal then
                    presence = L("CIRCLE_P_LAYER", e.node.ordinal)
                else
                    presence = L("CIRCLE_P_ONLINE")
                end
            else
                presence = L("CIRCLE_P_OFFLINE")
            end
            local relText = table.concat(rel, ", ")
            row.sub:SetText(presence .. (relText ~= "" and ("  \194\183  " .. relText) or ""))
            -- Hop only when online, on a DIFFERENT layer, and we know their zone.
            if e.online and e.node and not e.node.sameLayer and e.node.zoneUID and e.node.mapID then
                row.hop:Show()
            else
                row.hop:Hide()
            end
            row:Show()
        else
            row.pname, row.node = nil, nil
            row:Hide()
        end
    end
    if cu.empty then
        if #list == 0 then cu.empty:Show() else cu.empty:Hide() end
    end
end

local function NavButton(parent, text, y, accent, onClick)
    local b = UIElements.CreateButton(parent, text, SIDEBAR_W - 20, 32, accent)
    b:SetPoint("TOPLEFT", 10, y)
    -- A small accent dot gives the sidebar colour identity without clutter.
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(6, 6)
    b.dot:SetPoint("LEFT", 11, 0)
    UIElements.SetTextureColor(b.dot, accent)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 24, 0)
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

    local frame = UIElements.CreatePanel(UIParent, "PartyLensFrame", P.shell, P.strokeHot, true)
    partyLens.frame = frame
    frame:SetSize(UIMain.UI_WIDTH, UIMain.UI_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        if partyLens._summonTicker then
            partyLens._summonTicker:Cancel()
            partyLens._summonTicker = nil
        end
    end)
    -- Re-show paths (Toggle / minimap / keybind / "/partylens show") call a bare
    -- frame:Show() without SetMode, so make sure the comp popup never re-appears
    -- stranded over whatever screen the window opens into.
    frame:SetScript("OnShow", function()
        HideFrame(partyLens.compPopup)
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "PartyLensFrame")

    -- Sidebar (brand + nav).
    local sidebar = UIElements.CreatePanel(frame, "PartyLensSidebar", { 0.055, 0.065, 0.082, 0.72 }, P.stroke, true)
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
        { key = "summon", labelKey = "SUMMON_TITLE", accent = P.purple },
        { key = "layer", labelKey = "LAYER_TITLE", accent = P.freshNew },
        { key = "radar", labelKey = "WB_TITLE", accent = P.coral },
        { key = "network", labelKey = "NET_TITLE", accent = P.blue },
        { key = "circle", labelKey = "CIRCLE_TITLE", accent = P.freshNew },
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

    -- Brand accent line under the header.
    local headAccent = chead:CreateTexture(nil, "OVERLAY")
    headAccent:SetHeight(2)
    headAccent:SetPoint("BOTTOMLEFT", chead, "BOTTOMLEFT", 2, -3)
    headAccent:SetPoint("BOTTOMRIGHT", chead, "BOTTOMRIGHT", -2, -3)
    UIElements.SetTextureColor(headAccent, { P.teal[1], P.teal[2], P.teal[3], 0.45 })

    -- Content host (the four panels fill this).
    local hostPanel = UIElements.CreatePanel(frame, "PartyLensHost", { 0.040, 0.050, 0.065, 0.45 }, P.stroke, true)
    hostPanel:SetPoint("TOPLEFT", chead, "BOTTOMLEFT", 0, -6)
    hostPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    partyLens.host = hostPanel

    -- Faint radar-logo watermark for brand presence behind the content.
    local watermark = hostPanel:CreateTexture(nil, "ARTWORK")
    watermark:SetTexture("Interface\\AddOns\\PartyLens\\Icon")
    watermark:SetSize(170, 170)
    watermark:SetPoint("BOTTOMRIGHT", -6, 8)
    watermark:SetAlpha(0.05)

    CreateResultsPanel(partyLens, hostPanel)
    CreateCreatePanel(partyLens, hostPanel)
    CreateSettingsPanel(partyLens, hostPanel)
    CreateAutopilotPanel(partyLens, hostPanel)
    CreateSummonPanel(partyLens, hostPanel)
    CreateLayerPanel(partyLens, hostPanel)
    CreateRadarPanel(partyLens, hostPanel)
    CreateNetworkPanel(partyLens, hostPanel)
    CreateCirclePanel(partyLens, hostPanel)

    UIMain.SetMode(partyLens, partyLens.mode)
end

_G[ADDON_NAME .. "_UIMain"] = UIMain
return UIMain
