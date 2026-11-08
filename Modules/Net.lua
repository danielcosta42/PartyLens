local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

-- PartyLens's transport: the shared LibChehulMesh. On Forever SAY and YELL addon messages are refused and a
-- custom channel delivers nothing, so the buses are GUILD, the group, WHISPER and the mesh's directory
-- (Realm: whispers to a few members of a hidden channel's roster). Nothing goes from an instance or a chat
-- lockdown.
local Net = {}

local function Mesh()
    return _G.ChehulMesh
end

function Net.Register(prefix, handler)
    local mesh = Mesh()
    if mesh and mesh.Register then
        mesh:Register(prefix, handler)
    end
end

function Net.Broadcast(prefix, payload, realmKey)
    local mesh = Mesh()
    if not mesh or not Utils.CanSendAddon() then
        return false
    end
    mesh:Guild(prefix, payload)
    mesh:Group(prefix, payload)
    if realmKey then
        mesh:Realm(prefix, payload, realmKey)
    end
    return true
end

function Net.Realm(prefix, payload, realmKey)
    local mesh = Mesh()
    if mesh and Utils.CanSendAddon() then
        mesh:Realm(prefix, payload, realmKey)
        return true
    end
    return false
end

function Net.Whisper(prefix, payload, target)
    local mesh = Mesh()
    if not mesh or not Utils.CanSendAddon() then
        return false
    end
    return mesh:Whisper(prefix, payload, target) and true or false
end

-- A whisper to someone who may have logged off since: the mesh hides the game's "No player named X" line for a
-- name it was told about (its directory does the same for its own whispers).
function Net.WhisperQuiet(prefix, payload, target)
    local mesh = Mesh()
    if mesh and type(mesh.dir) == "table" and type(mesh.dir.tried) == "table" and GetTime then
        mesh.dir.tried[target] = GetTime() + (mesh.TRIED_SECONDS or 30)
    end
    return Net.Whisper(prefix, payload, target)
end

function Net.Status()
    local mesh = Mesh() or {}
    local dir = mesh.dir or {}
    local stats = mesh.stats or {}
    local dead = {}
    for dist in pairs(mesh.dead or {}) do
        dead[#dead + 1] = dist
    end
    table.sort(dead)
    local canSend = Utils.CanSendAddon()
    return {
        directory = dir.count or 0,
        dead = dead,
        canSend = canSend,
        inInstance = Utils.InInstance(),
        lockdown = Utils.InLockdown(),
        buses = {
            guild = canSend and IsInGuild() == true,
            group = canSend and IsInGroup() == true,
            realm = canSend and (dir.count or 0) > 0,
        },
        stats = {
            ok = stats.ok or 0, fail = stats.fail or 0, recv = stats.recv or 0, refused = stats.refused or 0,
            dirSent = stats.dirSent or 0, realmQueued = stats.realmQueued or 0, realmSent = stats.realmSent or 0,
            realmDropped = stats.realmDropped or 0,
        },
        meshVersion = mesh.version or 0,
    }
end

_G[ADDON_NAME .. "_Net"] = Net
return Net
