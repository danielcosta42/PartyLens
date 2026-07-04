local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]
local Entry = _G[ADDON_NAME .. "_Entry"]
local Who = _G[ADDON_NAME .. "_Who"]

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

        -- Class + level filters. Class is almost always known (chat GUID / LFG
        -- leader / mesh), so an unknown class is EXCLUDED when a class filter is
        -- active. Level is only knowable off the mesh or a /who (the "Who"
        -- button), so an unknown level is KEPT — hiding it would empty the list —
        -- and only a CONFIRMED below-floor level is dropped. We fill from the
        -- /who cache inline (no lookup of our own: SendWho is a click-only,
        -- hardware-event-restricted call, so we never auto-scan).
        if include then
            local classFilter = partyLens.db.classFilter
            local hasClassFilter = classFilter and next(classFilter) ~= nil
            local minLevel = tonumber(partyLens.db.minLevel) or 0

            if Who and (hasClassFilter or minLevel > 0) then
                Who.Enrich(partyLens, entry) -- cache-fill only; no /who sent
            end

            if hasClassFilter then
                if entry.classFile and entry.classFile ~= "" then
                    if not classFilter[entry.classFile] then
                        include = false
                    end
                else
                    include = false -- unknown class: hide while filtering
                end
            end

            if include and minLevel > 0 and entry.level and entry.level > 0
                and entry.level < minLevel then
                include = false -- known to be below the floor
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
