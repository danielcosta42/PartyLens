-- Wires PartyLens into the shared ChehulNet presence mesh (see ChehulNet.lua).
-- PartyLens works fully standalone; this only adds cross-addon recognition.
local CN = _G.ChehulNet
if not CN then
    return
end

-- Feed PartyLens's real (NWB-aware, converged) layer into the shared presence, so our
-- CHN1 HELLO carries the SAME zoneUID our layer mesh uses — not the built-in detector's
-- naive parse. Resolved at call time (BuildHello), so module load order doesn't matter.
CN.layerProvider = function()
    local pl = _G.PartyLens
    local Layer = _G.PartyLens_Layer
    if pl and Layer and Layer.Current then
        local c = Layer.Current(pl)
        return c.mapID or 0, c.zoneUID or 0
    end
    return 0, 0
end

-- Show network alerts in PartyLens's identity (teal). Highest priority in the family, so
-- when PartyLens is installed it owns the alert popup. Forever-dismissed ids live in our
-- SavedVariables (db.alertDismissed), resolved at call time (after SV load).
if CN.EnableAlerts then
    CN:EnableAlerts({
        accent = { 0.150, 0.860, 0.720 },
        title = "PartyLens",
        priority = 3,
        store = function()
            local pl = _G.PartyLens
            if pl and pl.db then
                pl.db.alertDismissed = pl.db.alertDismissed or {}
                return pl.db.alertDismissed
            end
        end,
    })
end

CN:Register("pl", function()
    -- Advertise "looking for group" while the autopilot is armed, so crafter /
    -- guild peers know this PartyLens user is actively LFG.
    local pl = _G.PartyLens
    local ap = pl and pl.autopilot
    if ap and ap.armed then
        return "lfg"
    end
    return ""
end, function(shortName, peer)
    -- A cross-addon peer announced presence. If they are NOT a PartyLens user (PL users
    -- already ride our own layer mesh via S) but DID share a layer, fold them into the
    -- layer node table so GuildOS/ProfessionHelper users show up on the occupancy map,
    -- the node count, and the Circle — the whole mesh becomes visible, not just PL.
    if peer and not (peer.addons and peer.addons["pl"])
        and peer.zoneUID and peer.zoneUID > 0 and peer.mapID and peer.mapID > 0 then
        local pl = _G.PartyLens
        local LayerNet = _G.PartyLens_LayerNet
        if pl and LayerNet and LayerNet.RecordCrossAddonNode then
            LayerNet.RecordCrossAddonNode(pl, shortName, peer.mapID, peer.zoneUID)
        end
    end
end)
