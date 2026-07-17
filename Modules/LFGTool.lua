local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Localization = _G[ADDON_NAME .. "_Localization"]
local Spam = _G[ADDON_NAME .. "_Spam"]

local LFGTool = {}

local function Bool(value)
    return value and true or false
end

local function NumberOrZero(value)
    return tonumber(value) or 0
end

local function RaidCategoryID()
    return (LFGListCategoryEnum and LFGListCategoryEnum.Raids) or 3
end

local function DungeonCategoryID()
    return (LFGListCategoryEnum and LFGListCategoryEnum.Dungeons) or 2
end

function LFGTool.RaidCategoryID()
    return RaidCategoryID()
end

function LFGTool.DungeonCategoryID()
    return DungeonCategoryID()
end

-- ---------------------------------------------------------------------------
-- Activity KIND classification (dungeon / raid / quest / pvp).
-- The old size-only split (<=5 dungeon, >5 raid) swept Arenas and Battlegrounds
-- into the PvE lists. We classify by the activity's real category instead, mapping
-- each categoryID to a kind by matching its localized category name against the
-- client's own localized globals (locale-robust). Size remains the fallback for
-- categories we can't recognize; PvP is then excluded from the PvE lists.
-- ---------------------------------------------------------------------------
local function LowerContainsAny(hay, needles)
    hay = Utils.SafeLower(hay or "")
    if hay == "" then
        return false
    end
    for _, n in ipairs(needles) do
        if n ~= "" and hay:find(n, 1, true) then
            return true
        end
    end
    return false
end

local KIND_TOKENS
local function KindTokens()
    if KIND_TOKENS then
        return KIND_TOKENS
    end
    local function tok(...)
        local out = {}
        for _, v in ipairs({ ... }) do
            if type(v) == "string" and v ~= "" then
                out[#out + 1] = Utils.SafeLower(v)
            end
        end
        return out
    end
    -- Order matters: PvP first so a "PvP"/"Arena" category never falls through to
    -- the dungeon/raid buckets. Localized globals + English fallbacks. The PvP set
    -- also lists TBC's fixed battleground/arena names by hand, because some clients
    -- don't expose a PvP *category* name we can recognize (then the BGs would size-
    -- classify as raids); an activity-name net catches them regardless of category.
    KIND_TOKENS = {
        { kind = "pvp", needles = tok(
            _G.ARENA, _G.ARENAS, _G.BATTLEGROUND, _G.BATTLEGROUNDS, _G.PVP, _G.PLAYER_VS_PLAYER,
            "arena", "battleground", "player vs", "pvp", "2v2", "3v3", "5v5",
            "warsong gulch", "arathi basin", "alterac valley", "eye of the storm") },
        { kind = "quest", needles = tok(_G.QUESTS, _G.QUEST, "quest") },
        { kind = "raid", needles = tok(_G.RAIDS, _G.RAID, "raid") },
        { kind = "dungeon", needles = tok(_G.DUNGEONS, _G.DUNGEON, "dungeon") },
    }
    return KIND_TOKENS
end

local categoryKindCache
local function BuildCategoryKindCache()
    categoryKindCache = {}
    if not C_LFGList or not C_LFGList.GetAvailableCategories or not C_LFGList.GetCategoryInfo then
        return
    end
    local okc, cats = pcall(C_LFGList.GetAvailableCategories)
    if not okc or type(cats) ~= "table" then
        return
    end
    for _, catID in ipairs(cats) do
        local ok, info = pcall(C_LFGList.GetCategoryInfo, catID)
        local name
        if ok then
            if type(info) == "table" then
                name = info.name or info.categoryName
            elseif type(info) == "string" then
                name = info
            end
        end
        if name then
            for _, entry in ipairs(KindTokens()) do
                if LowerContainsAny(name, entry.needles) then
                    categoryKindCache[catID] = entry.kind
                    break
                end
            end
        end
    end
end

-- kind for a categoryID, or nil when the category isn't recognized.
function LFGTool.CategoryKind(categoryID)
    if not categoryID then
        return nil
    end
    if not categoryKindCache then
        BuildCategoryKindCache()
    end
    return categoryKindCache[categoryID]
end

-- Invalidate the category->kind cache (call when the catalog is re-requested).
function LFGTool.ResetCategoryKinds()
    categoryKindCache = nil
end

-- True when an activity NAME itself reads as PvP (safety net for arenas whose
-- category slipped classification). Battlegrounds are caught by category kind.
local function LooksPvP(name)
    return LowerContainsAny(name, KindTokens()[1].needles)
end

local function LooksLikeRecruiting(text)
    text = Utils.SafeLower(text)
    local needles = {
        "lfm",
        "lf1m",
        "lf2m",
        "lf3m",
        "lf4m",
        "need tank",
        "need heal",
        "need healer",
        "need dps",
        "needs tank",
        "needs heal",
        "forming",
        "montando",
        "precisa tank",
        "precisa heal",
        "precisa healer",
        "precisa dps",
        "vaga",
        "vagas",
    }
    return Utils.ContainsAny(text, needles)
end

local function GuessToolIntent(result, message, activity)
    local numMembers = result.numMembers or 1
    if numMembers > 1 then
        return "group"
    end

    if LooksLikeRecruiting((message or "") .. " " .. (activity or "")) then
        return "group"
    end

    return "player"
end

function LFGTool.CaptureToolResults(partyLens)
    if not C_LFGList or not C_LFGList.GetSearchResults or not C_LFGList.GetSearchResultInfo then
        return
    end

    local totalOrResults, results = C_LFGList.GetSearchResults()
    if type(totalOrResults) == "table" and results == nil then
        results = totalOrResults
    end
    if type(results) ~= "table" then
        return
    end

    for _, resultID in ipairs(results) do
        local result = C_LFGList.GetSearchResultInfo(resultID)
        local leaderInfo = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(resultID)
        local leaderName = leaderInfo and leaderInfo.name or result and (result.leaderName or result.leader)
        if result and leaderName then
            local activity = "Grupo"
            local isRaid = partyLens.lastSearchCategoryID == RaidCategoryID()
            local activityID = result.activityID or (result.activityIDs and result.activityIDs[1])
            local activityMax
            if activityID and C_LFGList.GetActivityInfoTable then
                local info = C_LFGList.GetActivityInfoTable(activityID)
                if info then
                    activity = info.fullName or info.shortName or info.name or activity
                    isRaid = isRaid or info.isRaid or info.categoryID == RaidCategoryID()
                    activityMax = info.maxNumPlayers
                end
            elseif activityID and C_LFGList.GetActivityInfo then
                -- Older 2.5.x clients expose the positional form; the 8th return
                -- is maxPlayers and the 1st is the full name.
                local fullName, _, categoryID, _, _, _, _, maxPlayers = C_LFGList.GetActivityInfo(activityID)
                if fullName and fullName ~= "" then
                    activity = fullName
                end
                isRaid = isRaid or categoryID == RaidCategoryID()
                activityMax = maxPlayers
            elseif result.name and result.name ~= "" then
                activity = result.name
            end
            if not isRaid and Activity and Activity.GuessActivity then
                local _, _, guessedRaid = Activity.GuessActivity(activity .. " " .. (result.comment or result.name or ""))
                isRaid = guessedRaid and true or false
            end
            local guessedActivityKey = tostring(activityID or activity)
            if Activity and Activity.GuessActivity then
                local guessedActivityName, guessedKey, guessedRaid = Activity.GuessActivity(activity .. " " .. (result.comment or result.name or ""))
                if guessedKey and guessedKey ~= "other" then
                    guessedActivityKey = guessedKey
                    activity = guessedActivityName or activity
                    isRaid = guessedRaid and true or isRaid
                end
            end

            local message = result.comment or result.name or ""
            -- GetSearchResultInfo has no max-size field in 2.5.x, so prefer the
            -- activity's real cap and only fall back to a sane heuristic.
            local maxMembers = activityMax
            if not maxMembers or maxMembers == 0 then
                maxMembers = isRaid and 25 or 5
            end
            local open = not result.isDelisted and (not result.numMembers or result.numMembers < maxMembers)
            local intent = GuessToolIntent(result, message, activity)

            Entry.AddOrUpdateEntry(partyLens, {
                id = "tool:" .. tostring(resultID),
                resultID = resultID,
                source = "tool",
                leader = leaderName,
                leaderDisplay = Utils.PlayerShortName(leaderName),
                classFile = leaderInfo and leaderInfo.classFilename or nil,
                activity = activity,
                activityKey = guessedActivityKey,
                activityType = isRaid and "raid" or "dungeon",
                intent = intent,
                message = message,
                timestamp = time(),
                open = open,
                numMembers = result.numMembers,
                maxMembers = maxMembers,
                isDelisted = result.isDelisted,
                isRaid = isRaid,
                isSpam = Spam and Spam.IsSpam((message or "") .. " " .. (activity or "")) or false,
            })
        end
    end
end

function LFGTool.SearchTool(partyLens, categoryID, keepExisting)
    if not C_LFGList or not C_LFGList.Search then
        Utils.Print(Localization.L("LFG_NOT_AVAILABLE"))
        return
    end

    local languages = {}
    if C_LFGList.GetLanguageSearchFilter then
        languages = C_LFGList.GetLanguageSearchFilter() or {}
    end

    -- Drop results from the previous search so stale listings from another
    -- category cannot linger. Skipped when chaining a multi-category refresh.
    if not keepExisting then
        Entry.RemoveBySource(partyLens, "tool")
    end

    local ok = pcall(function()
        partyLens.lastSearchCategoryID = categoryID
        C_LFGList.Search(categoryID, 0, nil, languages, false, nil, nil)
    end)

    if not ok then
        Utils.Print(Localization.L("LFG_SEARCH_FAILED"))
    end
end

-- Refreshes game-finder results for the active content category. "raid" and
-- "dungeon" query that one category; anything else queries both (staggered to
-- respect the LFG search rate limit).
function LFGTool.RefreshGameFinder(partyLens, contentFilter)
    Entry.RemoveBySource(partyLens, "tool")

    if contentFilter == "raid" then
        LFGTool.SearchTool(partyLens, RaidCategoryID(), true)
    elseif contentFilter == "dungeon" then
        LFGTool.SearchTool(partyLens, DungeonCategoryID(), true)
    else
        LFGTool.SearchTool(partyLens, DungeonCategoryID(), true)
        if C_Timer and C_Timer.After then
            C_Timer.After(1.0, function()
                LFGTool.SearchTool(partyLens, RaidCategoryID(), true)
            end)
        else
            LFGTool.SearchTool(partyLens, RaidCategoryID(), true)
        end
    end
end

-- Compact "60-62" / "70" level tag for an activity's recommended range.
local function LevelRangeText(minLevel, maxLevel)
    minLevel = tonumber(minLevel) or 0
    maxLevel = tonumber(maxLevel) or 0
    if minLevel > 0 and maxLevel > 0 then
        if maxLevel > minLevel then
            return minLevel .. "-" .. maxLevel
        end
        return tostring(minLevel)
    elseif minLevel > 0 then
        return tostring(minLevel)
    elseif maxLevel > 0 then
        return tostring(maxLevel)
    end
    return ""
end

local function ActivityEntry(activityID)
    local fullName, maxPlayers, orderIndex, categoryID, minLevel, maxLevel
    local isPvp, isRaidFlag, usesRoles
    -- The Anniversary client is a modern build: GetActivityInfo was replaced by
    -- the table-returning GetActivityInfoTable. Prefer it; fall back to the old
    -- positional form on older clients.
    if C_LFGList.GetActivityInfoTable then
        local info = C_LFGList.GetActivityInfoTable(activityID)
        if info then
            fullName = info.fullName or info.shortName or info.name
            maxPlayers = info.maxNumPlayers or info.maxPlayers
            orderIndex = info.orderIndex
            categoryID = info.categoryID
            -- Modern GroupFinderActivityInfo has no "maxLevel"; the real fields
            -- are minLevel + min/maxLevelSuggestion. Fall back through them so a
            -- range like "68-70" renders wherever the client exposes it.
            minLevel = info.minLevel
            if not minLevel or minLevel == 0 then
                minLevel = info.minLevelSuggestion
            end
            maxLevel = info.maxLevelSuggestion or info.maxLevel
            -- Reliable per-activity classification flags (this client exposes them
            -- even though the category API is missing).
            isPvp = info.isPvpActivity or info.isRatedPvpActivity
            isRaidFlag = info.isCurrentRaidActivity
            usesRoles = info.useDungeonRoleExpectations
        end
    elseif C_LFGList.GetActivityInfo then
        fullName, _, categoryID, _, _, _, _, maxPlayers, _, orderIndex = C_LFGList.GetActivityInfo(activityID)
    end
    if not fullName or fullName == "" then
        return nil
    end

    -- Classify. Prefer the category map (works on clients with GetCategoryInfo);
    -- otherwise use the activity's own flags. PvP (arenas/battlegrounds) is always
    -- excluded; world/quest zones report maxNumPlayers == 0 and no dungeon roles,
    -- so they fall to "quest" (kept out of the dungeon/raid lists too).
    local maxp = maxPlayers or 0
    local kind = LFGTool.CategoryKind(categoryID)
    if not kind then
        if isPvp or LooksPvP(fullName) then
            kind = "pvp"
        elseif isRaidFlag or maxp > 5 then
            kind = "raid"
        elseif maxp >= 2 and maxp <= 5 then
            kind = "dungeon"
        elseif usesRoles then
            kind = "dungeon" -- role-based instance whose size the client left at 0
        else
            kind = "quest" -- world/quest zone (e.g. "Hellfire Peninsula")
        end
    elseif kind ~= "pvp" and LooksPvP(fullName) then
        kind = "pvp"
    end

    return {
        value = activityID,
        label = fullName,
        order = orderIndex or 0,
        maxPlayers = maxp,
        categoryID = categoryID,
        kind = kind,
        minLevel = tonumber(minLevel) or 0,
        maxLevel = tonumber(maxLevel) or 0,
        levelText = LevelRangeText(minLevel, maxLevel),
    }
end

-- Returns a sorted list of {value = activityID, label = fullName} for the given
-- listing category ("dungeons"/"raids"), built live from C_LFGList. No hardcoded
-- IDs — they are not reliably documented for 2.5.x and are build-specific.
-- Strategy: try the conventional category id first (clean lists); if that yields
-- nothing, fall back to enumerating ALL activities and classifying by group size
-- (only raids exceed 5 players), which is robust against wrong category ids.
function LFGTool.GetActivityList(listingCategory)
    local list = {}
    if not C_LFGList or not C_LFGList.GetAvailableActivities
        or (not C_LFGList.GetActivityInfoTable and not C_LFGList.GetActivityInfo) then
        return list
    end

    local wantKind = (listingCategory == "raids") and "raid" or "dungeon"
    local seen = {}

    -- Keep only entries whose real kind matches; this drops Arenas/Battlegrounds
    -- (kind == "pvp") and quests from the dungeon/raid lists. ActivityEntry.kind
    -- falls back to size when the category can't be recognized, so unknown-build
    -- category ids still classify correctly.
    local function consider(activityID)
        if seen[activityID] then
            return
        end
        seen[activityID] = true
        local entry = ActivityEntry(activityID)
        if not entry then
            return
        end
        if entry.kind == wantKind then
            list[#list + 1] = entry
        end
    end

    local function consumeCategory(catID)
        local ok, acts = pcall(C_LFGList.GetAvailableActivities, catID)
        if ok and type(acts) == "table" then
            for _, id in ipairs(acts) do
                consider(id)
            end
        end
    end

    -- Preferred: enumerate the categories the client actually reports, so we
    -- never depend on guessed category ids.
    if C_LFGList.GetAvailableCategories then
        local okc, cats = pcall(C_LFGList.GetAvailableCategories)
        if okc and type(cats) == "table" then
            for _, catID in ipairs(cats) do
                consumeCategory(catID)
            end
        end
    end

    -- Fallbacks: conventional ids, then the no-argument "all activities" form.
    if #list == 0 then
        consumeCategory(DungeonCategoryID())
        consumeCategory(RaidCategoryID())
    end
    if #list == 0 then
        local okAll, allActs = pcall(C_LFGList.GetAvailableActivities)
        if okAll and type(allActs) == "table" then
            for _, id in ipairs(allActs) do
                consider(id)
            end
        end
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.label < b.label
    end)

    return list
end

-- The player's quest-log quests that suggest a group, as activity-shaped entries.
-- Sourced from the log (not the finder catalog) so it reflects what YOU are on.
-- Value is "q:"..questID so the dropdown can tell quests from real activities.
function LFGTool.GetQuestActivities()
    local list = {}
    local QL = _G.C_QuestLog

    -- Entry count + per-entry info come from whichever API this client exposes.
    -- Prefer the table-returning C_QuestLog.GetInfo (named fields, no positional
    -- ambiguity) even when the count function only exists as a global; only the
    -- oldest clients fall back to the positional GetQuestLogTitle. Everything is
    -- coerced with tonumber so a string field can never reach a numeric compare.
    local num = (QL and QL.GetNumQuestLogEntries and QL.GetNumQuestLogEntries())
        or (_G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries())
        or 0

    -- Group-ish quest tags (localized global + English literal). On this client
    -- GetQuestLogTitle returns the quest TAG as a string in slot 3 ("Group" for
    -- group quests) -- not a numeric suggestedGroup -- so we detect by tag.
    local groupTags = {}
    for _, g in ipairs({ _G.GROUP, "Group", _G.ELITE, "Elite", _G.DUNGEON, "Dungeon", _G.RAID, "Raid" }) do
        if type(g) == "string" and g ~= "" then
            groupTags[g] = true
        end
    end

    for i = 1, num do
        local questID, title, level, isHeader, isGroup

        if QL and QL.GetInfo then
            -- Modern named-field path (absent on many Classic builds).
            local info = QL.GetInfo(i)
            if info then
                title, questID, isHeader, level = info.title, info.questID, info.isHeader, info.level
                isGroup = (tonumber(info.suggestedGroup) or 0) > 1
            end
        elseif _G.GetQuestLogTitle then
            -- Global positional path. Layout on this client:
            --   1 title, 2 level, 3 questTag(string|nil), 4 isHeader, ... 8 questID
            local t = { _G.GetQuestLogTitle(i) }
            title = t[1]
            level = tonumber(t[2]) or 0
            isHeader = t[4] and true or false
            isGroup = (type(t[3]) == "string" and groupTags[t[3]]) and true or false
            if type(t[8]) == "number" and t[8] > 0 then
                questID = t[8]
            end
        end

        level = tonumber(level) or 0
        if title and not isHeader and isGroup then
            list[#list + 1] = {
                value = (questID and questID > 0) and ("q:" .. questID) or ("qi:" .. i),
                label = title,
                order = level,
                maxPlayers = 5, -- group quests are small; drives a comfortable comp
                kind = "quest",
                questID = (questID and questID > 0) and questID or nil,
                minLevel = level,
                maxLevel = level,
                levelText = level > 0 and tostring(level) or "",
            }
        end
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.label < b.label
    end)
    return list
end

-- Resolve a quest title from its id. This client has no C_QuestLog.GetTitleForQuestID,
-- so scan the log by the questID that GetQuestLogTitle exposes in slot 8.
function LFGTool.QuestTitleByID(questID)
    if not questID or not _G.GetQuestLogTitle then
        return nil
    end
    local n = (_G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local t = { _G.GetQuestLogTitle(i) }
        if t[8] == questID and t[1] and t[1] ~= "" then
            return t[1]
        end
    end
    return nil
end

-- Asks the server for the activity catalog. On the Classic client this catalog
-- is owned by the Blizzard group-finder (a load-on-demand addon), so we load it
-- first; otherwise GetAvailableActivities() stays nil.
function LFGTool.RequestActivities()
    LFGTool.ResetCategoryKinds()
    if not C_LFGList then
        return
    end

    if not LFGTool._finderLoaded then
        LFGTool._finderLoaded = true
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then
            pcall(load, "Blizzard_GroupFinder")
            pcall(load, "Blizzard_LookingForGroupUI")
        end
    end

    if C_LFGList.RequestAvailableActivities then
        pcall(C_LFGList.RequestAvailableActivities)
    end
end

-- Prints the state of the C_LFGList activity catalog to chat. Run via
-- "/partylens diag" to find out why the activity picker is empty.
function LFGTool.Diagnose()
    Utils.Print("--- diag ---")
    if not C_LFGList then
        Utils.Print("C_LFGList: NO (group finder API missing)")
        return
    end
    Utils.Print("Request=" .. (C_LFGList.RequestAvailableActivities and "y" or "N")
        .. " GetCategories=" .. (C_LFGList.GetAvailableCategories and "y" or "N")
        .. " GetActivities=" .. (C_LFGList.GetAvailableActivities and "y" or "N")
        .. " GetInfo=" .. (C_LFGList.GetActivityInfo and "y" or "N"))

    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then
        local okA = pcall(load, "Blizzard_GroupFinder")
        local okB = pcall(load, "Blizzard_LookingForGroupUI")
        Utils.Print("loadAddon GroupFinder=" .. tostring(okA) .. " LFGUI=" .. tostring(okB))
    end
    if C_LFGList.RequestAvailableActivities then
        pcall(C_LFGList.RequestAvailableActivities)
    end

    local function report()
        local cats = C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableCategories()
        if type(cats) ~= "table" then
            Utils.Print("categories = " .. tostring(cats) .. " (catalog not loaded)")
        else
            Utils.Print("categories: " .. #cats)
            for _, id in ipairs(cats) do
                local name = C_LFGList.GetCategoryInfo and C_LFGList.GetCategoryInfo(id)
                local acts = C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(id)
                local count = (type(acts) == "table") and #acts or tostring(acts)
                local sample = ""
                if type(acts) == "table" and acts[1] then
                    local entry = ActivityEntry(acts[1])
                    if entry then
                        sample = " e.g. " .. entry.label .. " (" .. tostring(entry.maxPlayers) .. "p)"
                    end
                end
                Utils.Print("  cat " .. tostring(id) .. " '" .. tostring(name) .. "' acts=" .. count .. sample)
            end
        end
        local all = C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities()
        Utils.Print("no-arg activities = " .. (type(all) == "table" and #all or tostring(all)))
    end

    if C_Timer and C_Timer.After then
        Utils.Print("(waiting 2s for server data...)")
        C_Timer.After(2, report)
    else
        report()
    end
end

-- Core native-listing creation from an explicit param table:
-- { activityID, itemLevel, autoAccept, privateGroup, title, comment }.
-- Returns true on apparent success. Shared by the Create panel (db values) and
-- the autopilot (its own activity selection), so the autopilot can list without
-- the player ever touching the Create tab.
function LFGTool.CreateListingWith(params)
    if not C_LFGList or not C_LFGList.CreateListing then
        Utils.Print(Localization.L("LFG_NOT_AVAILABLE"))
        return false
    end

    local activityID = tonumber(params.activityID)
    if not activityID then
        Utils.Print(Localization.L("LISTING_ACTIVITY_REQUIRED"))
        return false
    end

    local itemLevel = NumberOrZero(params.itemLevel)
    local autoAccept = Bool(params.autoAccept)
    local privateGroup = Bool(params.privateGroup)
    local title = Utils.Trim(params.title or "")
    local comment = Utils.Trim(params.comment or "")

    -- Best-effort: push our title/comment into the native creation fields (may be
    -- protected, so guard with pcall).
    if title ~= "" and C_LFGList.SetEntryTitle then
        pcall(C_LFGList.SetEntryTitle, title)
    end
    if C_LFGList.SetEntryComment then
        pcall(C_LFGList.SetEntryComment, comment)
    end

    -- The Anniversary client is modern, so CreateListing takes a single table;
    -- older clients use the positional form. Try the table form first, then fall
    -- back to positional, and accept any non-false result as success.
    local function succeeded(ok, result)
        return ok and result ~= false and result ~= nil
    end

    local ok, result = pcall(C_LFGList.CreateListing, {
        activityID = activityID,
        activityIDs = { activityID },
        itemLevel = itemLevel,
        honorLevel = 0,
        autoAccept = autoAccept,
        isAutoAccept = autoAccept,
        privateGroup = privateGroup,
        isPrivateGroup = privateGroup,
        name = title,
        comment = comment,
    })

    if not succeeded(ok, result) then
        ok, result = pcall(C_LFGList.CreateListing, activityID, itemLevel, 0, autoAccept, privateGroup)
    end

    if succeeded(ok, result) then
        Utils.Print(Localization.L("LISTING_CREATE_SENT"))
        return true
    end
    Utils.Print(Localization.L("LISTING_CREATE_FAILED"))
    return false
end

function LFGTool.CreateListing(partyLens)
    local db = partyLens.db or {}
    return LFGTool.CreateListingWith({
        activityID = db.listingActivityID,
        itemLevel = db.listingMinItemLevel,
        autoAccept = db.listingAutoAccept,
        privateGroup = db.listingPrivate,
        title = db.listingTitle,
        comment = db.listingComment,
    })
end

function LFGTool.AnnounceListing(partyLens)
    local db = partyLens.db or {}
    local title = Utils.Trim(db.listingTitle or "")
    local comment = Utils.Trim(db.listingComment or "")
    local message = Utils.Trim(title .. " " .. comment)

    if message == "" then
        Utils.Print(Localization.L("LISTING_MESSAGE_REQUIRED"))
        return
    end

    local channelNumber = GetChannelName and GetChannelName("LookingForGroup")
    if type(channelNumber) ~= "number" or channelNumber == 0 then
        JoinPermanentChannel("LookingForGroup")
        channelNumber = GetChannelName and GetChannelName("LookingForGroup")
    end

    if type(channelNumber) == "number" and channelNumber > 0 then
        Utils.SendChat(message, "CHANNEL", nil, channelNumber)
        Utils.Print(Localization.L("LISTING_ANNOUNCED"))
    else
        Utils.Print(Localization.L("LFG_JOIN_ATTEMPT"))
    end
end

-- ---------------------------------------------------------------------------
-- Quest -> Autopilot entry point. Targets a specific quest and opens PartyLens on
-- the Autopilot, pre-set to Build that quest (does NOT auto-arm -- arming stays
-- deliberate). Public so any addon can drive it:
--
--     PartyLens_FindQuestGroup(questID)            -- title resolved from the log
--     PartyLens_FindQuestGroup(questID, "Title")   -- caller supplies the title
--
-- Also hooked to the Blizzard quest-log "Find Group" action where that exists
-- (this client lacks it, but other builds have it).
-- ---------------------------------------------------------------------------
function LFGTool.FindQuestGroup(questID, title)
    -- TEMP diagnostic: confirms the call fires and shows the args passed in.
    print("|cff26dbb8PartyLens_FindQuestGroup|r qid=" .. tostring(questID) .. " title=" .. tostring(title))
    local qid = tonumber(questID)
    if not qid and not (type(title) == "string" and title ~= "") then
        return -- nothing usable to target
    end
    local pl = _G.PartyLens
    if not pl or not pl.db or not pl.db.autopilot then
        return
    end
    -- Prefer a caller-supplied title (e.g. Lodestar already knows it); otherwise
    -- resolve from the quest log by id.
    if type(title) ~= "string" or title == "" then
        title = (qid and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid))
            or (qid and LFGTool.QuestTitleByID(qid))
            or (qid and _G.QuestUtils_GetQuestName and _G.QuestUtils_GetQuestName(qid))
            or ("Quest " .. tostring(qid or "?"))
    end
    local cfg = pl.db.autopilot
    cfg.role = "build"
    cfg.activityType = "quest"
    cfg.questID = qid
    cfg.activityFilter = title
    cfg.activityID = nil
    local UIMain = _G[ADDON_NAME .. "_UIMain"]
    if UIMain and UIMain.CreateMainUI then
        UIMain.CreateMainUI(pl)
        if pl.frame then
            pl.frame:Show()
        end
        if UIMain.SetMode then
            UIMain.SetMode(pl, "autopilot")
        end
        if UIMain.SyncAutopilot then
            UIMain.SyncAutopilot(pl)
        end
    end
    return true
end

-- Global alias so other addons can integrate without reaching into the module.
_G.PartyLens_FindQuestGroup = LFGTool.FindQuestGroup

local questHookInstalled = false
local function TryInstallQuestHook()
    if questHookInstalled then
        return
    end
    if type(_G.LFGListUtil_FindQuestGroup) == "function" and hooksecurefunc then
        hooksecurefunc("LFGListUtil_FindQuestGroup", function(questID)
            LFGTool.FindQuestGroup(questID)
        end)
        questHookInstalled = true
    end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        TryInstallQuestHook()
    end)
    -- In case the symbol is already present when this module loads.
    TryInstallQuestHook()
end

_G[ADDON_NAME .. "_LFGTool"] = LFGTool
return LFGTool
