local ADDON_NAME = ...
-- Wires PartyLens into the shared ChehulNet presence (Modules/ChehulNet.lua): the "pl" tag in every HELLO, the
-- operator's alerts in PartyLens's identity, its layer for every HELLO, and its health for the backoffice's DIAG.
-- Everything resolves at call time, so module and SavedVariables load order do not matter.
local CN = _G.ChehulNet
if not CN then
    return
end

local function PL()
    return _G.PartyLens
end

local function Mod(name)
    return _G[ADDON_NAME .. "_" .. name]
end

CN.layerProvider = function()
    local pl = PL()
    if pl and pl.db then
        local cur = Mod("Layer").Current(pl)
        return cur.mapID or 0, cur.zoneUID or 0
    end
    return 0, 0
end

CN:EnableAlerts({
    accent = { 1.0, 0.71, 0.28 },
    title = "PartyLens",
    priority = 3,
    store = function()
        local pl = PL()
        return pl and pl.db and pl.db.alertDismissed
    end,
})

-- Caps ride every HELLO: no '|' ever, and nothing personal.
CN:Register("pl", function()
    local pl = PL()
    local parts = { "plv=" .. tostring(pl and pl.VERSION or "?") }
    if pl and pl.db and Mod("Listing").IsActive(pl) then
        parts[#parts + 1] = "lst=" .. pl.db.listing.type
    end
    return table.concat(parts, ",")
end, function(_, peer)
    local pl = PL()
    if not (pl and pl.db) then
        return
    end
    if peer and (peer.zoneUID or 0) > 0 then
        pl:Fire("LAYER_NODES_CHANGED")
    end
    pl:NetworkChanged()
end)

CN:RegisterDiag("pl", function()
    local pl = PL()
    if not (pl and pl.db) then
        return "v=" .. tostring(pl and pl.VERSION or "?")
    end
    local entries = 0
    for _ in pairs(pl.entries or {}) do
        entries = entries + 1
    end
    local beacon = Mod("LayerNet").BeaconStatus(pl)
    local listing = Mod("Listing").IsActive(pl) and pl.db.listing.type or "0"
    return table.concat({ "v=" .. tostring(pl.VERSION), "entries=" .. entries, "listing=" .. listing,
        "heard=" .. Mod("Comm").HeardCount(pl), "nodes=" .. Mod("LayerNet").NodeCount(pl), "req=" .. beacon.queue,
        "beacon=" .. (beacon.available and "duty" or (beacon.why or "off")), "hops=" .. beacon.hops,
        "plpeers=" .. Mod("Board").PeerCount(pl) }, ";")
end)
