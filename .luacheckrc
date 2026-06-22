-- luacheck config for PartyLens (WoW TBC Anniversary addon, Lua 5.1).
--
-- The WoW client injects hundreds of engine globals (CreateFrame, C_LFGList, …)
-- that luacheck can't know about, so we DON'T fail on undefined globals/fields.
-- We keep the high-value checks that actually catch our mistakes: unused locals,
-- shadowing/redefinition, and dead control flow.

std = "lua51"
max_line_length = false
codes = true

-- Our own writable globals (saved variable + the global addon handles).
globals = {
    "PartyLensDB",
    "PartyLens",
    "L",
    "SlashCmdList",
    "SLASH_PARTYLENS1",
}

ignore = {
    "111", -- setting an undefined global (WoW handles / our _G assigns)
    "112", -- mutating an undefined global
    "113", -- accessing an undefined global (WoW API)
    "142", -- setting an undefined field of a global
    "143", -- accessing an undefined field of a global
    "212", -- unused argument (event/callback signatures often ignore some)
    "213", -- unused loop variable
    "542", -- empty if branch
}

exclude_files = {
    ".release/",
}
