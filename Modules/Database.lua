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
        schemaVersion = 6,
        spec = "",
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
        -- Autopilot: persisted CONFIG only. The armed/running state is runtime
        -- (partyLens.autopilot) so a reload never resumes acting silently.
        autopilot = {
            role = "build", -- "build" (recruit, LFM) | "find" (apply, LFG)
            tier = "assisted", -- "advisor" | "assisted" | "full"
            activityType = "dungeon", -- "dungeon" | "raid" | "any"
            activityFilter = "", -- optional substring, e.g. "kara" / "heroic"
            -- Desired composition for build mode (totals, including yourself).
            needTank = 1,
            needHeal = 1,
            needDps = 3,
            inviteKeyword = "inv",
            autoInvite = true,
            -- Auto-spam an "LFM" line in the LookingForGroup channel. The native
            -- C_LFGList listing is fully protected (addons can't create it), so
            -- channel announce + whisper auto-invite is the TBC recruiting path.
            autoAnnounce = true,
            -- Find mode.
            myRole = "dps",
            autoWhisper = true,
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
