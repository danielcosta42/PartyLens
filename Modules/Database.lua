local ADDON_NAME = ...
local Utils = _G[ADDON_NAME .. "_Utils"]

local Database = {}

function Database.EnsureDB(partyLens)
    if type(PartyLensDB) ~= "table" then
        PartyLensDB = {}
    end

    local className = select(1, UnitClass("player")) or ""
    local previousSchemaVersion = PartyLensDB.schemaVersion or 0
    local defaults = {
        className = className,
        schemaVersion = 8,
        spec = "",
        -- Spec picker: specAuto detects the active spec from talents; otherwise
        -- specKeys is the set of specs the player pinned. Roles are DERIVED from
        -- the chosen specs into myRoles (find matching + mesh + whisper {role}).
        specAuto = true,
        specKeys = {},
        myRoles = { dps = true },
        role = "dps",
        comment = "",
        template = "Oi! {class} {spec} {role} aqui. {comment}",
        query = "",
        -- mode: "browse" | "create" | "settings"
        mode = "browse",
        intentFilter = "all",
        -- contentFilter: "all" | "dungeon" | "raid" | "guild" | "quest" | "other"
        contentFilter = "all",
        -- roleFilter: when any are true, only show groups needing that role.
        roleFilter = { tank = false, heal = false, dps = false },
        -- classFilter: [classFile] = true for each allowed class. Empty = all
        -- classes. Applies to the Browse list AND who Autopilot invites.
        classFilter = {},
        -- minLevel: 0 = off; otherwise hide/skip players known to be below it.
        -- Level is only knowable via the mesh or a /who lookup on this client.
        minLevel = 0,
        -- Layer network: beacon = am I a node that auto-invites layer requesters.
        -- channels = which public chats to scan for requests. seen/hops filled at
        -- runtime. Detection lives in Layer.lua; the engine in LayerNet.lua.
        layer = {
            beacon = false,
            channels = { trade = true, general = true, lookingforgroup = true, world = true },
            -- Instruction whisper to the invited player: ON (it doubles as
            -- marketing — every hopper receives the addon's name). The beacon
            -- itself stays silent: the outgoing echo is filtered and the whisper
            -- tab it would open is auto-closed (FCF_OpenTemporaryWindow hook).
            whisper = true,
            -- Hide the party unit frames while beaconing (SetAlpha, not :Hide).
            hideParty = true,
            hops = 0,
            seen = {},
        },
        -- Community reputation (positive-only "vouches", shared over the mesh).
        -- given[lname]=epoch (people I vouched — one each), tally[lname]={[voter]=epoch}
        -- (vouches I've HEARD, distinct voters = the score), groupmates[lname]=epoch
        -- (people I recently grouped with — the suggestions to vouch).
        rep = {
            given = {},
            tally = {},
            groupmates = {},
        },
        listingCategory = "dungeons",
        listingActivityID = "",
        listingTitle = "",
        listingComment = "",
        listingMinItemLevel = "0",
        listingAutoAccept = false,
        listingPrivate = false,
        includeChat = true,
        includeTool = true,
        onlyOpen = true,
        minimap = true,
        minimapAngle = 225,
        -- Audible ping when a new open group in the selected category appears
        -- while the window is closed (opt-in).
        alertOnMatch = false,
        -- Hide gold/boost/RMT spam from the LFG channel scan.
        hideSpam = true,
        -- Per-player blacklist: [lowerShortName] = true.
        blacklist = {},
        -- Autopilot: persisted CONFIG only. The armed/running state is runtime
        -- (partyLens.autopilot) so a reload never resumes acting silently.
        autopilot = {
            role = "build", -- "build" (recruit, LFM) | "find" (apply, LFG)
            tier = "auto", -- "auto" (fire immediately) | "suggest" (queue for GO)
            activityType = "dungeon", -- "dungeon" | "raid" | "any"
            activityFilter = "", -- optional substring, e.g. "kara" / "heroic"
            -- Desired composition for build mode (totals, including yourself).
            -- These are DERIVED from `comp` when it has picks; otherwise they act
            -- as a plain size/role target.
            needTank = 1,
            needHeal = 1,
            needDps = 3,
            -- Class/spec composition: comp[classFile][specKey] = wanted count.
            -- Drives the role totals above, the class gate for auto-invite, and
            -- is the player's recruiting wishlist. Empty = recruit by size only.
            comp = {},
            inviteKeyword = "inv",
            autoInvite = true,
            -- Auto-spam an "LFM" line in the LookingForGroup channel. The native
            -- C_LFGList listing is fully protected (addons can't create it), so
            -- channel announce + whisper auto-invite is the TBC recruiting path.
            autoAnnounce = true,
            -- Find mode.
            myRole = "dps",
            autoWhisper = true,
            -- Only whisper groups whose description explicitly asks for our role
            -- or class; skip vague/unspecified listings. Far fewer, on-target
            -- contacts. Turn off to also answer open ("LFM more") groups.
            findStrict = true,
            -- Shared.
            minIlvl = 0,
            -- Safety.
            whisperCooldown = 20,
        },
    }

    for key, value in pairs(defaults) do
        if PartyLensDB[key] == nil then
            PartyLensDB[key] = value
        end
    end

    if previousSchemaVersion < 4 then
        PartyLensDB.minimap = true
        PartyLensDB.schemaVersion = 4
    end

    -- v5: replace the Dungeons/Raids/Create/Settings tab model with a 3-mode
    -- nav (browse/create/settings) and a single unified content category.
    if previousSchemaVersion < 5 then
        local oldTab = PartyLensDB.activeTab
        if oldTab == "create" then
            PartyLensDB.mode = "create"
        elseif oldTab == "settings" then
            PartyLensDB.mode = "settings"
        else
            PartyLensDB.mode = "browse"
        end
        if oldTab == "raids" then
            PartyLensDB.contentFilter = "raid"
        elseif oldTab == "dungeons" then
            PartyLensDB.contentFilter = "dungeon"
        elseif PartyLensDB.contentFilter == "groups" or PartyLensDB.contentFilter == nil then
            PartyLensDB.contentFilter = "all"
        end
        PartyLensDB.activeTab = nil
        PartyLensDB.schemaVersion = 5
    end

    -- v6: autopilot first introduced. Default the queued role to the player's
    -- likely role (one-time, so we don't override later choices).
    if previousSchemaVersion < 6 then
        if type(PartyLensDB.autopilot) ~= "table" then
            PartyLensDB.autopilot = {}
        end
        local _, classFile = UnitClass("player")
        local classRole = ({ PRIEST = "heal", PALADIN = "heal", DRUID = "heal" })[classFile or ""]
        if classRole and (PartyLensDB.autopilot.myRole == nil or PartyLensDB.autopilot.myRole == "dps") then
            PartyLensDB.autopilot.myRole = classRole
        end
        PartyLensDB.schemaVersion = 6
    end

    -- v7: the free-text spec/role boxes became a spec picker that DERIVES roles.
    -- Preserve any custom text the player typed (move it into the still-editable
    -- comment) instead of overwriting it, and start the picker in Auto mode so the
    -- first detection fills the canonical spec.
    if previousSchemaVersion < 7 then
        if PartyLensDB.spec and PartyLensDB.spec ~= "" then
            if not PartyLensDB.comment or PartyLensDB.comment == "" then
                PartyLensDB.comment = PartyLensDB.spec
            end
        end
        PartyLensDB.spec = ""
        PartyLensDB.specKey = nil -- from the short-lived single-spec build
        PartyLensDB.specAuto = true
        PartyLensDB.specKeys = {}
        PartyLensDB.schemaVersion = 7
    end

    -- v8: automation tiers collapsed 3 -> 2. advisor -> suggest; assisted|full -> auto.
    if previousSchemaVersion < 8 then
        if type(PartyLensDB.autopilot) == "table" then
            local t = PartyLensDB.autopilot.tier
            if t == "advisor" then
                PartyLensDB.autopilot.tier = "suggest"
            elseif t == "assisted" or t == "full" then
                PartyLensDB.autopilot.tier = "auto"
            end
        end
        PartyLensDB.schemaVersion = 8
    end

    -- Always backfill autopilot sub-keys so new options (added across versions)
    -- pick up their default WITHOUT needing a schema bump each time. Only fills
    -- nils, so it never clobbers the player's saved choices.
    if type(PartyLensDB.autopilot) ~= "table" then
        PartyLensDB.autopilot = {}
    end
    for key, value in pairs(defaults.autopilot) do
        if PartyLensDB.autopilot[key] == nil then
            PartyLensDB.autopilot[key] = value
        end
    end

    partyLens.db = PartyLensDB
    return PartyLensDB
end

function Database.SaveField(editBox, key, partyLens)
    partyLens.db[key] = Utils.Trim(editBox:GetText())
    if partyLens.Refresh then
        partyLens:Refresh()
    end
end

_G[ADDON_NAME .. "_Database"] = Database
return Database
