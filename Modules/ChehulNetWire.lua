-- Wires PartyLens into the shared ChehulNet presence mesh (see ChehulNet.lua).
-- PartyLens works fully standalone; this only adds cross-addon recognition.
local CN = _G.ChehulNet
if not CN then
    return
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
end, nil)
