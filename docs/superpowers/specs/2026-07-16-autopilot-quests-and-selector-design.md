# Autopilot: quest support + activity selector reorg — design

**Date:** 2026-07-16
**Branch:** `autopilot-redesign` (extends the Autopilot screen redesign)
**Status:** Approved, implementing

## Problem

Two issues with the Autopilot activity selector:

1. **Everything mixed together.** `LFGTool.GetActivityList` classifies activities
   purely by group size (≤5 = dungeon, >5 = raid), so Arenas (5v5) and
   Battlegrounds (Alterac Valley, 40) get swept into the PvE lists, and the "All"
   view is one flat list with Normal/Heroic interleaved.
2. **No quest support.** The client offers a "Find Group" action on group quests,
   but PartyLens can't target quests at all.

## Decisions (from brainstorming)

- Selector = **PvE only, sub-grouped**. Exclude Arenas/Battlegrounds. Dungeons →
  Normal/Heroic headers; Raids → by size; "All" → sections Dungeons(Normal),
  Dungeons(Heroic), Raids, Quests.
- Content buttons = **4**: Dungeon / Raid / Quest / All.
- Quests = **both** a selectable content type (sourced from the player's quest log)
  **and** a quest-log hook that opens PartyLens pre-configured for a clicked quest.

## Part A — Activity classification + selector reorg

**Classify by real _kind_, not size.** Add `LFGTool.CategoryKind(categoryID)` →
`"dungeon"|"raid"|"quest"|"pvp"|nil`, backed by a lazily-built cache mapping each
`categoryID` (from `C_LFGList.GetAvailableCategories`) to a kind by matching its
`C_LFGList.GetCategoryInfo(categoryID)` name against **localized globals**
(`_G.ARENA`, `_G.BATTLEGROUNDS`, `_G.QUESTS`, `_G.DUNGEONS`, `_G.RAIDS`; plus raw
English tokens as fallback). Locale-robust.

- `ActivityEntry` gains a `kind` field: `CategoryKind(categoryID)` or, when unknown,
  size-based (`>5` → raid, else dungeon). PvP is excluded here as a safety net when
  the activity/category name matches an arena/battleground token.
- `LFGTool.GetActivityList(kind)` now takes `"dungeons"|"raids"` and returns only
  matching-kind entries, **never PvP**. (Quests come from `GetQuestActivities`, below.)
- `ActivityCategory(item, content)` (UIMain) extended:
  - `dungeon` → `Normal`/`Heroic` (unchanged).
  - `raid` → by size (unchanged).
  - `quest` → single "Quests" section.
  - `any` → Dungeons·Normal (1), Dungeons·Heroic (2), Raids (3), Quests (4) — using
    `item.kind` + `ActivityIsHeroic(item.label)`.
- `RefreshAutopilotActivities` builds `lists` per content, adding
  `GetQuestActivities()` for `quest` and `any`.

**Content buttons:** add a 4th `quest` button; shrink widths so all four + the
activity dropdown fit one row (dropdown keeps its `RIGHT -PAD` stretch). Content-button
click for `quest` applies a small comfortable comp when none is set.

## Part B — Quests

**Source = the player's quest log.** `LFGTool.GetQuestActivities()` enumerates the
log via `C_QuestLog.GetNumQuestLogEntries` + `C_QuestLog.GetInfo(i)` (legacy
`GetNumQuestLogEntries`/`GetQuestLogTitle` fallback), keeping non-header quests with
`suggestedGroup > 1`. Each becomes an entry `{ value = "q:"..questID, label = title,
maxPlayers = suggestedGroup, kind = "quest" }`.

**Dropdown select** (`activityDropdown.onSelect`) branches on the `"q:"` prefix:
- Quest: `cfg.questID = <id>`, `cfg.activityFilter = <title>`, `cfg.activityID = nil`.
- Real activity: `cfg.activityID = <id>`, `cfg.questID = nil`, `cfg.activityFilter = <label>`
  (existing behavior).

`cfg.questID` clears whenever a non-quest content button or a non-quest activity is
chosen. Recruiting stays on the existing unprotected path (channel announce of the
quest title + whisper auto-invite) — quests do NOT touch protected LFG writes.

**Quest-log hook.** Self-contained in `LFGTool.lua` (mirrors `LayerNet`'s
`hooksecurefunc` pattern; no Core.lua/.toc edits): a private event frame listens for
`ADDON_LOADED`/`PLAYER_LOGIN` and, once `LFGListUtil_FindQuestGroup` exists, installs
`hooksecurefunc("LFGListUtil_FindQuestGroup", handler)` a single time. The handler uses
`_G.PartyLens`:
1. `db.autopilot.activityType = "quest"`, `questID`, `activityFilter = <title>`,
   `role = "build"`.
2. Open the window to the Autopilot mode and refresh the activity list + panel.
3. Do **not** auto-arm (arming stays deliberate).

Because `hooksecurefunc` is additive, Blizzard's own finder still opens alongside;
acceptable. If the symbol is absent on this build, the hook is skipped and the manual
Quest content type still works. **The exact hook symbol is the one piece unverifiable
without the client — feature-detected, confirmed in-game.**

## Persistence

`cfg.activityType` gains the value `"quest"` (no migration — existing string values stay
valid). `cfg.questID` is a new optional field (nil until set; no backfill needed).

## Out of scope / unchanged

- No native `C_LFGList` listing/apply (still fully protected).
- No Core.lua / PartyLens.toc changes (avoids entangling unrelated in-flight work).
- Summon screen, mesh/Comm, comp popup untouched.

## Files

- `Modules/LFGTool.lua`: `CategoryKind`, PvP exclusion, `ActivityEntry.kind`,
  `GetActivityList` kind filter, `GetQuestActivities`, quest-log hook.
- `Modules/UIMain.lua`: 4th content button + row fit, `ActivityCategory` sections,
  `RefreshAutopilotActivities` quest list, `onSelect` quest branch, questID clearing.
- `Modules/Localization.lua`: `FILTER_QUESTS`, `AP_QUEST_EMPTY` (enUS + ptBR).

## Verification

No Lua runtime — `luaparser` syntax + `luacheck`, then in-game: PvP gone from lists;
"All" shows the four sections; Quest button lists your group quests; picking one sets
the title; clicking a quest's Find Group opens PartyLens on Autopilot pre-filled.
