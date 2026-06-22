local ADDON_NAME = ...

local Entry = {}

Entry.MAX_RESULTS = 160
Entry.CHAT_TTL_SECONDS = 45 * 60
-- C_LFGList results are only meaningful for a short while after a search, so age
-- them out instead of pinning stale "open" groups at the top of the list.
Entry.TOOL_TTL_SECONDS = 10 * 60
-- PartyLens-mesh broadcasts are a live heartbeat (~30s); if one goes silent the
-- user has stopped/left, so expire their presence quickly.
Entry.ADDON_TTL_SECONDS = 3 * 60

Entry.DEDUP_WINDOW_SECONDS = 10 * 60

-- Optional audible ping when a NEW open group in the selected category shows up
-- while the window is closed (you're not already watching). Opt-in + debounced.
function Entry.MaybeAlert(partyLens, entry)
    local db = partyLens.db
    if not db or not db.alertOnMatch or not entry.open then
        return
    end
    if partyLens.frame and partyLens.frame:IsShown() then
        return
    end
    local cf = db.contentFilter or "all"
    if cf ~= "all" then
        local at = entry.activityType or (entry.isRaid and "raid" or "dungeon")
        if at ~= cf then
            return
        end
    end
    local now = time()
    if partyLens._lastAlert and (now - partyLens._lastAlert) < 8 then
        return
    end
    partyLens._lastAlert = now
    if PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
    end
end

local function NormalizedLeader(entry)
    return string.lower(entry.leaderDisplay or entry.leader or "")
end

-- Finds an existing entry that almost certainly represents the same group
-- (same leader + same content type within a short window). This collapses a
-- leader who both spams chat and has a live listing into one row, and also
-- folds repeated chat spam from the same leader together. Source is NOT part of
-- the match: once a chat row is upgraded to a tool row, later tool updates must
-- still find it (otherwise they would double-insert).
local function FindDuplicate(partyLens, entry)
    local leaderKey = NormalizedLeader(entry)
    if leaderKey == "" then
        return nil
    end

    local now = entry.timestamp or time()
    for _, candidate in ipairs(partyLens.entries) do
        if candidate.id ~= entry.id
            and NormalizedLeader(candidate) == leaderKey
            and (candidate.activityType or "") == (entry.activityType or "")
            and math.abs(now - (candidate.timestamp or now)) <= Entry.DEDUP_WINDOW_SECONDS then
            return candidate
        end
    end

    return nil
end

local function MergeEntry(canonical, incoming)
    -- The LFG tool is authoritative for group composition and naming; keep a
    -- human-readable chat message when the tool has none.
    local fromTool = incoming.source == "tool"
    if fromTool then
        canonical.source = "tool"
        canonical.resultID = incoming.resultID or canonical.resultID
        canonical.numMembers = incoming.numMembers or canonical.numMembers
        canonical.maxMembers = incoming.maxMembers or canonical.maxMembers
        canonical.open = incoming.open
        canonical.isDelisted = incoming.isDelisted
    end
    if incoming.message and incoming.message ~= "" then
        canonical.message = incoming.message
    end
    canonical.classFile = canonical.classFile or incoming.classFile
    -- Only let a tool update (or a first value) overwrite the descriptive fields,
    -- so chat guesses do not clobber the tool's authoritative activity name.
    if fromTool or not canonical.activity or canonical.activity == "" then
        canonical.activity = incoming.activity or canonical.activity
        canonical.activityKey = incoming.activityKey or canonical.activityKey
        canonical.intent = incoming.intent or canonical.intent
    end
    if incoming.needs and incoming.needs ~= "" then
        canonical.needs = incoming.needs
    end
    -- PartyLens-mesh data is trusted: once a leader is known to run the addon,
    -- keep the flag and their broadcast role even if a chat line merges in later.
    canonical.isAddonUser = canonical.isAddonUser or incoming.isAddonUser
    if incoming.role and incoming.role ~= "" then
        canonical.role = incoming.role
    end
    canonical.timestamp = math.max(canonical.timestamp or 0, incoming.timestamp or 0)
end

function Entry.AddOrUpdateEntry(partyLens, entry)
    if not entry or not entry.id then
        return
    end

    if not partyLens.entriesById then
        partyLens.entriesById = {}
        partyLens.entries = {}
    end

    local existing = partyLens.entriesById[entry.id]
    if existing then
        for key, value in pairs(entry) do
            existing[key] = value
        end
    else
        local duplicate = FindDuplicate(partyLens, entry)
        if duplicate then
            -- Merge into the existing row; the incoming id is intentionally not
            -- registered, so a later update re-merges instead of double-inserting.
            MergeEntry(duplicate, entry)
        else
            table.insert(partyLens.entries, entry)
            partyLens.entriesById[entry.id] = entry
            Entry.MaybeAlert(partyLens, entry)
        end
    end

    if #partyLens.entries > Entry.MAX_RESULTS then
        table.sort(partyLens.entries, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
        for index = Entry.MAX_RESULTS + 1, #partyLens.entries do
            partyLens.entriesById[partyLens.entries[index].id] = nil
            partyLens.entries[index] = nil
        end
    end

    if partyLens.Refresh then
        partyLens:Refresh()
    end
end

function Entry.PruneOldEntries(partyLens)
    if not partyLens.entries then
        return
    end

    local now = time()
    local kept = {}
    partyLens.entriesById = {}

    for _, entry in ipairs(partyLens.entries) do
        local ttl = Entry.CHAT_TTL_SECONDS
        if entry.source == "tool" then
            ttl = Entry.TOOL_TTL_SECONDS
        elseif entry.source == "addon" then
            ttl = Entry.ADDON_TTL_SECONDS
        end
        if (now - (entry.timestamp or now)) <= ttl then
            table.insert(kept, entry)
            partyLens.entriesById[entry.id] = entry
        end
    end

    partyLens.entries = kept
end

-- Backwards-compatible alias (chat-only pruning used to be the only path).
Entry.PruneOldChat = Entry.PruneOldEntries

function Entry.RemoveBySource(partyLens, source)
    if not partyLens.entries then
        return
    end

    local kept = {}
    partyLens.entriesById = {}

    for _, entry in ipairs(partyLens.entries) do
        if entry.source ~= source then
            table.insert(kept, entry)
            partyLens.entriesById[entry.id] = entry
        end
    end

    partyLens.entries = kept
end

_G[ADDON_NAME .. "_Entry"] = Entry
return Entry
