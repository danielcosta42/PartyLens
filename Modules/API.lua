local ADDON_NAME = ...

-- PartyLens public inter-addon API — the STABLE surface sibling addons (Lodestar,
-- ProfessionHelper, ...) call. Kept deliberately separate from module internals so
-- cross-addon calls never reach into guts. Every entry point is standalone-safe:
-- it resolves _G.PartyLens + its modules LAZILY at call time and no-ops (returning
-- false + a reason) when PartyLens isn't loaded or hasn't finished DB init. Nothing
-- here is called at file-load time, so load order versus the other modules is moot.
--
-- Published as _G.PartyLens_API (module convention). Core.lua also mirrors it onto
-- _G.PartyLens.API so a caller can write `_G.PartyLens.API.StartQuestGroup(ctx)`.

local API = {}

-- Contract version — bump when the shape of these calls changes.
API.VERSION = 1

local function PL() return _G.PartyLens end
local function Mod(name) return _G[ADDON_NAME .. "_" .. name] end

-- True once PartyLens is loaded and past DB init (safe to accept calls).
function API.IsReady()
    local pl = PL()
    return (pl and pl.db) and true or false
end

-- Translate a desired group size / explicit roles into the autopilot's role totals.
-- comp is cleared so the autopilot recruits by size/role, not by a class wishlist.
local function applyComposition(cfg, ctx)
    cfg.comp = {}
    local size = tonumber(ctx.size) or (ctx.needRaid and 10 or 5)
    if size < 2 then size = 2 end
    local r = ctx.roles
    if type(r) == "table" then
        cfg.needTank = tonumber(r.tank) or 0
        cfg.needHeal = tonumber(r.heal) or 0
        cfg.needDps  = tonumber(r.dps) or math.max(0, size - cfg.needTank - cfg.needHeal)
    elseif size >= 5 then
        cfg.needTank, cfg.needHeal, cfg.needDps = 1, 1, size - 2
    else
        cfg.needTank, cfg.needHeal, cfg.needDps = 0, 0, size - 1
    end
end

-- StartQuestGroup(ctx): configure the autopilot to recruit a group for a quest and
-- open it PRE-FILLED for the player to arm. It does NOT auto-announce/auto-invite
-- unless ctx.arm == true — recruiting stays a user gesture (they click Arm), matching
-- the autopilot's invite/whisper-only, opt-in model.
--   ctx = {
--     questName, stepText,      -- label shown in the LFM line (either; questName wins)
--     size,                     -- desired total group size (default 5, or 10 if needRaid)
--     needRaid,                 -- true => raid content + size 10 default
--     activityType,             -- override: "dungeon" | "raid" | "any"
--     roles = { tank, heal, dps }, -- optional explicit composition
--     mapID, zoneUID,           -- optional: also request a hop to the target's layer
--     arm,                      -- optional: true => arm immediately (else just pre-fill)
--   }
-- Returns true on success, or false, reason.
function API.StartQuestGroup(ctx)
    ctx = ctx or {}
    local pl = PL()
    if not (pl and pl.db) then return false, "notready" end
    local AP = Mod("Autopilot")
    if not AP then return false, "noautopilot" end

    local cfg = pl.db.autopilot
    if type(cfg) ~= "table" then return false, "nocfg" end
    cfg.role = "build"
    cfg.activityType = ctx.activityType or (ctx.needRaid and "raid" or "any")
    local label = ctx.questName or ctx.stepText or ""
    cfg.activityFilter = tostring(label):gsub("|", "/"):sub(1, 60)
    applyComposition(cfg, ctx)

    -- Optional layer hop toward the objective (best-effort; ignored if unavailable).
    if ctx.mapID and ctx.zoneUID then
        API.RequestLayer(ctx.mapID, ctx.zoneUID)
    end

    if ctx.arm then
        pcall(AP.Arm, pl)
    end
    -- Surface it: open the autopilot screen pre-filled so the user reviews & arms.
    local UIMain = Mod("UIMain")
    if UIMain and UIMain.CreateMainUI then
        pcall(UIMain.CreateMainUI, pl)
        if pl.frame then pl.frame:Show() end
        if UIMain.SetMode then pcall(UIMain.SetMode, pl, "autopilot") end
    end
    return true
end

-- RequestLayer(mapID, zoneUID): pin a hop to a specific map+layer (e.g. the layer a
-- quest target NPC is on). Returns true if the request was issued.
function API.RequestLayer(mapID, zoneUID)
    local pl = PL()
    local LayerNet = Mod("LayerNet")
    mapID, zoneUID = tonumber(mapID), tonumber(zoneUID)
    if not (pl and LayerNet and LayerNet.RequestLayerFor and mapID and zoneUID) then
        return false, "notready"
    end
    pcall(LayerNet.RequestLayerFor, pl, mapID, zoneUID)
    return true
end

-- HopToLayerOfUnit(unit): resolve the layer of a targeted creature (default "target")
-- and request a hop to it. Returns true if a layer was resolved and requested.
function API.HopToLayerOfUnit(unit)
    local pl = PL()
    local Layer = Mod("Layer")
    if not (pl and Layer and Layer.ZoneUIDFromUnit) then return false, "notready" end
    local zoneUID = Layer.ZoneUIDFromUnit(unit or "target")
    if not zoneUID then return false, "nolayer" end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return false, "nomap" end
    return API.RequestLayer(mapID, zoneUID)
end

-- WhichLayer(mapID, zoneUID) -> ordinal layer number (or nil) — lets a sibling label
-- a layer the way PartyLens numbers it.
function API.WhichLayer(mapID, zoneUID)
    local pl = PL()
    local Layer = Mod("Layer")
    if not (pl and Layer and Layer.OrdinalOf) then return nil end
    local ok, ord = pcall(Layer.OrdinalOf, pl, tonumber(mapID), tonumber(zoneUID))
    return ok and ord or nil
end

-- MyLayer() -> mapID, zoneUID, ordinal for the local player (or nils).
function API.MyLayer()
    local pl = PL()
    local Layer = Mod("Layer")
    if not (pl and Layer and Layer.Current) then return nil end
    local ok, cur = pcall(Layer.Current, pl)
    if ok and type(cur) == "table" then return cur.mapID, cur.zoneUID, cur.ordinal end
    return nil
end

_G[ADDON_NAME .. "_API"] = API
return API
