local ADDON_NAME = ...

-- The stable surface sibling addons (Lodestar) call, as _G.PartyLens_API and _G.PartyLens.API. Every call
-- resolves PartyLens when it runs and answers false, reason when it is not ready. Nothing here sends anything:
-- it fills a draft and opens a page, and the player takes it from there.
local API = {}

API.VERSION = 2

local function PL()
    local pl = _G.PartyLens
    return (pl and pl.db) and pl or nil
end

function API.IsReady()
    return PL() ~= nil
end

-- ctx = { questID, questName | stepText, needRaid, size }: an lfm draft for the quest, then the Announce page. A
-- listing already on the air is the player's and stays as it is.
function API.StartQuestGroup(ctx)
    local pl = PL()
    if not pl then
        return false, "notready"
    end
    ctx = type(ctx) == "table" and ctx or {}
    local qid = tonumber(ctx.questID)
    local title = qid and C_QuestLog.GetTitleForQuestID(qid)
    if type(title) ~= "string" or title == "" then
        title = (type(ctx.questName) == "string" and ctx.questName ~= "" and ctx.questName)
            or (type(ctx.stepText) == "string" and ctx.stepText ~= "" and ctx.stepText)
            or (qid and ("Quest " .. qid)) or nil
    end
    if not title then
        return false, "notitle"
    end
    local size = math.max(2, tonumber(ctx.size) or (ctx.needRaid and 10 or 5))
    local heal = size >= 10 and 2 or 1
    local tank = size >= 3 and 1 or 0
    if not pl:GetListing().active then
        pl:SetListing({ type = "lfm", activity = "", label = title,
            want = { tank = tank, heal = heal, dps = math.max(0, size - tank - heal) } })
    end
    pl:Open("announce", { source = "api", label = title })
    return true
end

-- Opens the Layer page on a map and layer (say, a quest NPC's): that layer's row is marked; the player goes from there.
function API.RequestLayer(mapID, zoneUID)
    local pl = PL()
    mapID, zoneUID = tonumber(mapID), tonumber(zoneUID)
    if not (pl and mapID and zoneUID) then
        return false, "notready"
    end
    pl:Open("layer", { source = "api", mapID = mapID, zoneUID = zoneUID })
    return true
end

-- mapID, zoneUID, ordinal of my layer (nils until one is detected).
function API.MyLayer()
    local pl = PL()
    if not pl then
        return nil
    end
    local cur = pl:GetLayer()
    return cur.mapID, cur.zoneUID, cur.ordinal
end

_G[ADDON_NAME .. "_API"] = API
return API
