local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Activity = _G[ADDON_NAME .. "_Activity"]
local Localization = _G[ADDON_NAME .. "_Localization"]

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

local function ActivityEntry(activityID)
    local fullName, maxPlayers, orderIndex, categoryID
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
        end
    elseif C_LFGList.GetActivityInfo then
        fullName, _, categoryID, _, _, _, _, maxPlayers, _, orderIndex = C_LFGList.GetActivityInfo(activityID)
    end
    if not fullName or fullName == "" then
        return nil
    end
    return {
        value = activityID,
        label = fullName,
        order = orderIndex or 0,
        maxPlayers = maxPlayers or 0,
        categoryID = categoryID,
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

    local wantRaid = (listingCategory == "raids")
    local seen = {}

    -- Classify by group size (only raids exceed 5 players); this is robust even
    -- when the conventional category ids are wrong for this client build.
    local function consider(activityID)
        if seen[activityID] then
            return
        end
        seen[activityID] = true
        local entry = ActivityEntry(activityID)
        if not entry then
            return
        end
        local isRaid = entry.maxPlayers > 5
        if isRaid == wantRaid and (wantRaid or entry.maxPlayers >= 5) then
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

-- Asks the server for the activity catalog. On the Classic client this catalog
-- is owned by the Blizzard group-finder (a load-on-demand addon), so we load it
-- first; otherwise GetAvailableActivities() stays nil.
function LFGTool.RequestActivities()
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
        SendChatMessage(message, "CHANNEL", nil, channelNumber)
        Utils.Print(Localization.L("LISTING_ANNOUNCED"))
    else
        Utils.Print(Localization.L("LFG_JOIN_ATTEMPT"))
    end
end

_G[ADDON_NAME .. "_LFGTool"] = LFGTool
return LFGTool
