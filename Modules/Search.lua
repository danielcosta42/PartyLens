local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]

local Search = {}

function Search.ScoreEntry(partyLens, entry, query)
    local score = entry.timestamp or 0
    local text = Utils.SafeLower((entry.message or "") .. " " .. (entry.activity or "") .. " " .. (entry.activityKey or "") .. " " .. (entry.leader or ""))

    if entry.open then
        score = score + 100000
    end

    if entry.source == "tool" then
        score = score + 20000
    end

    -- Fellow PartyLens users carry trusted, structured data — surface them first.
    if entry.isAddonUser then
        score = score + 60000
    end

    if query and query ~= "" then
        local matched = true
        for token in string.gmatch(Utils.SafeLower(query), "%S+") do
            if string.find(text, token, 1, true) then
                score = score + 30000
            else
                matched = false
            end
        end
        if not matched then
            return nil
        end
    end

    local role = Utils.SafeLower(partyLens.db.role or "")
    if role ~= "" and string.find(text, role, 1, true) then
        score = score + 10000
    end

    return score
end

function Search.GetFilteredEntries(partyLens)
    Entry.PruneOldEntries(partyLens)

    local results = {}
    local query = partyLens.db.query or ""

    for _, entry in ipairs(partyLens.entries or {}) do
        local include = true
        local activityType = entry.activityType or (entry.isRaid and "raid" or "dungeon")
        local contentFilter = partyLens.db.contentFilter or "all"

        -- Source toggles.
        if entry.source == "chat" and not partyLens.db.includeChat then
            include = false
        end
        if entry.source == "tool" and not partyLens.db.includeTool then
            include = false
        end

        -- Spam + per-player blacklist.
        if entry.isSpam and partyLens.db.hideSpam then
            include = false
        end
        if include and partyLens.db.blacklist and entry.leader
            and partyLens.db.blacklist[Utils.SafeLower(Utils.PlayerShortName(entry.leader))] then
            include = false
        end

        -- Open-only.
        if partyLens.db.onlyOpen and not entry.open then
            include = false
        end

        -- "Looking for" (intent): players (LFG) vs groups (LFM).
        if partyLens.db.intentFilter == "players" and entry.intent ~= "player" then
            include = false
        end
        if partyLens.db.intentFilter == "groups" and entry.intent ~= "group" then
            include = false
        end

        -- Unified content category.
        if contentFilter ~= "all" and activityType ~= contentFilter then
            include = false
        end

        -- Role-need filter: when any role is selected, keep only groups that
        -- need one of those roles (or a generic "any" need).
        local rf = partyLens.db.roleFilter
        if rf and (rf.tank or rf.heal or rf.dps) then
            local needs = entry.needs or ""
            local matchesRole = string.find(needs, "any", 1, true)
                or (rf.tank and string.find(needs, "tank", 1, true))
                or (rf.heal and string.find(needs, "heal", 1, true))
                or (rf.dps and string.find(needs, "dps", 1, true))
            if not matchesRole then
                include = false
            end
        end

        if include then
            local score = Search.ScoreEntry(partyLens, entry, query)
            if score then
                entry.score = score
                table.insert(results, entry)
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    return results
end

_G[ADDON_NAME .. "_Search"] = Search
return Search
