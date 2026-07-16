# Autopilot Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Autopilot mode panel into a two-face screen — a calm **Setup** face while disarmed and a live **Cockpit** face while armed — and collapse the three automation tiers into two named modes.

**Architecture:** One panel (`partyLens.autopilotPanel`) holds two sibling child frames, `ap.setupFace` and `ap.cockpitFace`; `UIMain.RefreshAutopilot` shows exactly one based on the runtime `armed` flag and repaints it. The automation backend collapses `advisor/assisted/full` to `suggest/auto` with a schema migration. No new state machine — reuses `Autopilot.Toggle` / `rt.armed` / `rt.state`.

**Tech Stack:** Lua 5.1 (WoW TBC 2.5.x addon API, Interface 20506), offset-based frame layout built from `Modules/UIElements.lua` factories. No bundler, no in-repo Lua runtime.

## Global Constraints

- **Visual direction is binding** — "Dark glass radar" brief: teal (`P.teal`) only for selection/focus/brand/live; section headers `muted` size 12 + divider; complete 4-side borders on interactive surfaces; role colors only for role pips; class names in Blizzard class colors. Build from `UIElements` factories; introduce no new hues or font sizes.
- **Window is 820×600, sidebar 150px** — the mode panel fills `host`; usable content width ≈ 620px inside `PAD=16` insets. Layout is offset-based; positions are hand-tuned constants — starting offsets in this plan are computed from the design and **tuned in-game**.
- **Armed/running state is runtime-only** (`partyLens.autopilot`, created lazily by `RT()`) — never persisted, so a reload never auto-resumes. Do not change this.
- **Native LFG writes stay untouched** — `C_LFGList.CreateListing`/`ApplyToGroup` are fully protected on this client; the autopilot uses only unprotected invite/whisper/channel-announce. Do not add calls to protected APIs.
- **Locale**: add new keys to **enUS + ptBR** only (`Modules/Localization.lua`); the other 8 locales fall back to enUS via `Localization.Get`.
- **No test runner / no Lua runtime** — the per-task "verify" step is: (a) syntax-check changed files with `luaparser`, (b) run `luacheck` if available locally, (c) an in-game verification checklist. Treat the checklist as the acceptance gate.
- **Out of scope**: the Summon screen (`Modules/Summon.lua`, `CreateSummonPanel`), the mesh/Comm broadcast, the comp popup internals (`CreateCompPopup`), activity-dropdown population (`RefreshAutopilotActivities`), sidebar nav.

**Verify helper (used by every task's verify step):**

```bash
# From the addon root. Syntax-only check of the files a task changed:
python -c "from luaparser import ast; import sys; [ast.parse(open(f,encoding='utf-8').read()) for f in sys.argv[1:]]; print('syntax OK')" \
  Modules/UIMain.lua Modules/Autopilot.lua Modules/Database.lua Modules/Localization.lua
# Optional (CI also runs it); ignore if luacheck isn't installed locally:
luacheck Modules/UIMain.lua Modules/Autopilot.lua Modules/Database.lua Modules/Localization.lua
```

---

### Task 1: Collapse automation tiers to `auto`/`suggest` (backend + migration)

Pure backend + persistence. No UI. Deliverable: the state machine understands only `auto` and `suggest`; existing saved configs migrate; a fresh DB defaults to `auto`.

**Files:**
- Modify: `Modules/Autopilot.lua` (`Autopilot.Engage` ~L492-526, `Autopilot.OnReady` ~L614, `Autopilot.Tick` gate ~L732)
- Modify: `Modules/Database.lua` (defaults ~L88, `schemaVersion` L15, add v8 migration after L183)

**Interfaces:**
- Produces: `db.autopilot.tier` now holds `"auto"` (default) or `"suggest"`. `"auto"` = fire invites/whispers/announce immediately, never wait on a pending action (former `full` semantics). `"suggest"` = queue each action in `rt.pendingAction` for the GO button (former `advisor` semantics). Consumed by Task 2's Adjust mode toggle and Task 3's GO button.

- [ ] **Step 1: Update the tier default + comment in Database.lua**

In `Modules/Database.lua`, change the default (L88):

```lua
            tier = "auto", -- "auto" (fire immediately) | "suggest" (queue for GO)
```

- [ ] **Step 2: Bump the schema version**

In `Modules/Database.lua` L15:

```lua
        schemaVersion = 8,
```

- [ ] **Step 3: Add the v8 migration block**

In `Modules/Database.lua`, insert immediately AFTER the v7 block (after its `PartyLensDB.schemaVersion = 7` / closing `end`, currently ~L183) and BEFORE the "Always backfill autopilot sub-keys" comment (~L185):

```lua
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
```

(The unconditional backfill only fills `tier` when nil, so it never clobbers a migrated value; a fresh install already has `"auto"` from defaults before this block runs, so the block is a no-op there.)

- [ ] **Step 4: Update `Autopilot.Engage` tier checks**

In `Modules/Autopilot.lua`, `Autopilot.Engage`:
- L494: `local tier = cfg.tier or "assisted"` → `local tier = cfg.tier or "auto"`
- L501: `if tier == "advisor" then` → `if tier == "suggest" then`
- L518: `if tier == "advisor" then` → `if tier == "suggest" then`

- [ ] **Step 5: Update `Autopilot.OnReady` announce gate**

In `Modules/Autopilot.lua` L614:

```lua
    if cfg.role == "build" and cfg.tier ~= "suggest" and Roster.CanInvite() and snap.size > 1 then
```

- [ ] **Step 6: Update the `Autopilot.Tick` pending gate**

In `Modules/Autopilot.lua` L730-732, replace the comment + condition:

```lua
    -- Suggest mode waits for the player's GO before queuing anything new, so a
    -- pending suggestion doesn't get re-logged every tick. Auto never waits.
    if cfg.tier == "suggest" and Autopilot.HasPending(partyLens) then
        Autopilot.RefreshPanel(partyLens)
        return
    end
```

- [ ] **Step 7: Verify**

Run the verify helper (Task-1 files). Expected: `syntax OK`. Grep to confirm no stale tier strings remain in logic:

```bash
grep -nE '"(advisor|assisted|full)"' Modules/Autopilot.lua
```
Expected: no matches in Autopilot.lua (Database.lua legacy strings appear ONLY inside the v8 migration block).

In-game checklist: `/reload` with an existing v7 config whose tier was `assisted` → open `/partylens auto`; no Lua error on load; DB migrates (verify later once the UI reads it in Task 2).

- [ ] **Step 8: Commit**

```bash
git add Modules/Autopilot.lua Modules/Database.lua
git commit -m "Autopilot: collapse automation tiers to auto/suggest (schema v8)"
```

---

### Task 2: Two faces + Setup face (build mode)

Rebuild `CreateAutopilotPanel` so the panel holds two child frames, and construct the **Setup** face fully for build mode. Wire `RefreshAutopilot` to switch faces on `armed`. The Cockpit face is created empty here (a placeholder container) and filled in Task 3.

**Files:**
- Modify: `Modules/UIMain.lua` (`CreateAutopilotPanel` L1059-1374; `UpdateAutopilotRole` L824-840; `UpdateAutopilotTier` L848-858; `LayoutAP` L863-887; `AP_STATE_LABEL`/`AP_TIER_DESC` L817-846; `UIMain.RefreshAutopilot` L1628-1731)
- Modify: `Modules/Localization.lua` (add new keys, enUS + ptBR)

**Interfaces:**
- Consumes: `db.autopilot.tier` from Task 1; existing helpers `ApplyComp`, `ComfortableComp`, `CompActive`, `UIMain.OpenComp`, `UIMain.RefreshComp`, `BuildSpecChips`, `Section`, `ShowFrame`/`HideFrame`, `UIElements.CreateButton/CreateToggle/CreateEditBox/CreateLabel/CreateDropdown/CreateDivider`, button methods `:SetActive(bool)`/`:SetAccent(color)`/`:SetText`.
- Produces: `ap.setupFace` and `ap.cockpitFace` (Frames, siblings of `panel`, each `:SetAllPoints(panel)`); `ap.modeAutoBtn`/`ap.modeSuggestBtn` (the 2-mode toggle writing `db.autopilot.tier`); `ap.adjustOpen` disclosure state; `UIMain.RefreshAutopilot` shows one face by `armed`. Task 3 fills `ap.cockpitFace`; Task 4 adds find-mode widgets.

- [ ] **Step 1: Add the new locale keys**

In `Modules/Localization.lua`, add to BOTH the enUS and ptBR tables (find the existing `AP_*` block). enUS:

```lua
    AP_ADJUST = "Adjust",
    AP_MODE_LABEL = "Automation",
    AP_MODE_AUTO = "Automatic",
    AP_MODE_SUGGEST = "Suggest",
    AP_ADJUST_ECHO_AUTO = "automatic",
    AP_ADJUST_ECHO_SUGGEST = "suggest",
    AP_EDIT = "edit",
    AP_GROUP_PROGRESS = "GROUP  %d/%d",
    AP_CONTACTED = "%d groups whispered",
```

ptBR:

```lua
    AP_ADJUST = "Ajustar",
    AP_MODE_LABEL = "Automação",
    AP_MODE_AUTO = "Automático",
    AP_MODE_SUGGEST = "Sugerir",
    AP_ADJUST_ECHO_AUTO = "automático",
    AP_ADJUST_ECHO_SUGGEST = "sugerir",
    AP_EDIT = "editar",
    AP_GROUP_PROGRESS = "GRUPO  %d/%d",
    AP_CONTACTED = "%d grupos sussurrados",
```

- [ ] **Step 2: Replace the tier state tables**

In `Modules/UIMain.lua`, delete `AP_TIER_DESC` (L842-846) and rewrite `UpdateAutopilotTier` (L848-858) for the 2-button toggle:

```lua
local function UpdateAutopilotTier(partyLens)
    local ap = partyLens.ap
    if not ap or not ap.modeAutoBtn then return end
    local tier = partyLens.db.autopilot.tier or "auto"
    ap.modeAutoBtn:SetActive(tier == "auto")
    ap.modeSuggestBtn:SetActive(tier == "suggest")
    if UIMain.RefreshAutopilot then UIMain.RefreshAutopilot(partyLens) end
end
```

- [ ] **Step 3: Rewrite `CreateAutopilotPanel` — panel + two faces + Setup (build)**

Replace `CreateAutopilotPanel` (L1059-1374). Create the panel, then two faces. Build ALL setup controls as children of `ap.setupFace` (not `panel`). Keep the existing wiring for Goal/Content/comp/keyword; move automation into an Adjust disclosure with the 2-mode toggle; keep the natural-language summary and ARM. Concrete structure (offsets are starting values, tune in-game):

```lua
local function CreateAutopilotPanel(partyLens, host)
    local P = UIElements.PALETTE
    local panel = CreateFrame("Frame", "PartyLensAutopilotPanel", host)
    partyLens.autopilotPanel = panel
    panel:SetAllPoints(host)

    local ap = {}
    partyLens.ap = ap

    -- Two faces; RefreshAutopilot shows exactly one based on armed state.
    local setupFace = CreateFrame("Frame", nil, panel)
    setupFace:SetAllPoints(panel)
    ap.setupFace = setupFace
    local cockpitFace = CreateFrame("Frame", nil, panel)
    cockpitFace:SetAllPoints(panel)
    cockpitFace:Hide()
    ap.cockpitFace = cockpitFace

    -- Shared header: live mesh count (top-right) shown on both faces, so it lives
    -- on `panel`, not a face.
    ap.meshLabel = UIElements.CreateLabel(panel, "", 11, P.teal)
    ap.meshLabel:SetPoint("TOPRIGHT", -PAD, -PAD)
    ap.meshLabel:SetJustifyH("RIGHT")

    -- ===================== SETUP FACE =====================
    local LX, CX = PAD, PAD + 88
    local function StepLabel(text, y)
        local l = UIElements.CreateLabel(setupFace, text, 10, P.muted)
        l:SetPoint("TOPLEFT", LX, y)
        return l
    end

    -- 1) OBJETIVO (build/find) — unchanged wiring, parented to setupFace.
    StepLabel(L("AP_GOAL_LABEL"), -46)
    ap.roleBuildBtn = UIElements.CreateButton(setupFace, L("AP_ROLE_BUILD"), 260, 26, P.teal)
    ap.roleBuildBtn:SetPoint("TOPLEFT", CX, -42)
    ap.roleBuildBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "build"
        UpdateAutopilotRole(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)
    ap.roleFindBtn = UIElements.CreateButton(setupFace, L("AP_ROLE_FIND"), 176, 26, P.gold)
    ap.roleFindBtn:SetPoint("LEFT", ap.roleBuildBtn, "RIGHT", 6, 0)
    ap.roleFindBtn:SetPoint("RIGHT", -PAD, 0)
    ap.roleFindBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.role = "find"
        UpdateAutopilotRole(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)

    -- 2) CONTEÚDO — content buttons + activity dropdown. PORT the existing loop
    -- (L1107-1177) verbatim EXCEPT parent = setupFace and anchors below.
    --   StepLabel(L("AP_CONTENT_LABEL"), -84); content buttons at TOPLEFT CX,-80;
    --   activityDropdown parented to setupFace, LEFT of last content btn, RIGHT -PAD.
    -- (Keep the comfortable-comp auto-fill on content click and on dropdown select.)

    -- 3) GRUPO (build) / SUA FUNÇÃO (find). Port buildBox (L1182-1206: compBtn +
    -- compNeed + keyword) and findBox (L1226-1235: BuildSpecChips) into setupFace,
    -- but MOVE the automation toggles (autoInvite/autoAnnounce/autoWhisper/strict)
    -- OUT of these boxes into the Adjust section below. buildBox now holds only the
    -- comp editor + derived need + (keyword MOVES to Adjust too). See Step 4.
    ap.roleSection = StepLabel("", -126)
    -- buildBox: comp editor + need readout only.
    -- findBox: spec chips only.  (Both anchored TOPLEFT CX,-122; RIGHT -PAD; height ~30.)

    -- 4) ADJUST disclosure (see Step 4) at TOPLEFT PAD, -170.
    -- 5) Divider + natural-language summary + ARM (see Step 5).

    CreateCompPopup(partyLens)
    UpdateAutopilotRole(partyLens)
    UpdateAutopilotTier(partyLens)
    UpdateAutopilotContent(partyLens)
    UIMain.RefreshAutopilotActivities(partyLens, true)
    UIMain.RefreshComp(partyLens)
    UIMain.CommitSpec(partyLens)
    LayoutAP(partyLens)
end
```

Port the Content block (current L1107-1177) and the comp editor / spec-chip boxes (current L1182-1206 build, L1226-1235 find) verbatim, changing only the parent to `setupFace`/`ap.buildBox`/`ap.findBox` and the anchors noted above. Keep `ap.contentBtns`, `ap.activityDropdown`, `ap.compBtn`, `ap.compNeed`, `ap.buildBox`, `ap.findBox` field names so `UpdateAutopilotContent`, `UIMain.RefreshComp`, and `UpdateAutopilotRole` keep working unchanged.

- [ ] **Step 4: Build the Adjust disclosure**

Inside `CreateAutopilotPanel`, after the GRUPO row, add the collapsible Adjust section (parented to `setupFace`). Header button toggles `db.autopilot.adjustOpen`; body holds the 2-mode toggle, keyword, cooldown, ilvl, and the announce checkbox:

```lua
    ap.adjustToggle = UIElements.CreateButton(setupFace, "", 140, 22, P.blue)
    ap.adjustToggle:SetPoint("TOPLEFT", PAD, -170)
    ap.adjustToggle:SetScript("OnClick", function()
        partyLens.db.autopilot.adjustOpen = not partyLens.db.autopilot.adjustOpen
        LayoutAP(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)

    local adj = CreateFrame("Frame", nil, setupFace)
    ap.adjBox = adj
    adj:SetPoint("TOPLEFT", PAD, -196)
    adj:SetPoint("RIGHT", -PAD, 0)
    adj:SetHeight(96)

    -- Automation mode (2 buttons).
    local modeLabel = UIElements.CreateLabel(adj, L("AP_MODE_LABEL"), 10, P.muted)
    modeLabel:SetPoint("TOPLEFT", 0, -2)
    ap.modeAutoBtn = UIElements.CreateButton(adj, L("AP_MODE_AUTO"), 120, 24, P.teal)
    ap.modeAutoBtn:SetPoint("TOPLEFT", 96, 0)
    ap.modeAutoBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.tier = "auto"; UpdateAutopilotTier(partyLens)
    end)
    ap.modeSuggestBtn = UIElements.CreateButton(adj, L("AP_MODE_SUGGEST"), 120, 24, P.blue)
    ap.modeSuggestBtn:SetPoint("LEFT", ap.modeAutoBtn, "RIGHT", 6, 0)
    ap.modeSuggestBtn:SetScript("OnClick", function()
        partyLens.db.autopilot.tier = "suggest"; UpdateAutopilotTier(partyLens)
    end)

    -- Keyword (MOVED from buildBox).
    local kwLabel = UIElements.CreateLabel(adj, L("AP_KEYWORD_SHORT"), 10, P.muted)
    kwLabel:SetPoint("TOPLEFT", 0, -34)
    local kwBox, kwShell = UIElements.CreateEditBox(adj, "PartyLensAPKeyword", 86, 26)
    kwShell:SetPoint("LEFT", kwLabel, "RIGHT", 8, 0)
    kwBox:SetText(partyLens.db.autopilot.inviteKeyword or "inv")
    kwBox:SetScript("OnTextChanged", function(e)
        partyLens.db.autopilot.inviteKeyword = Utils.Trim(e:GetText())
    end)

    -- Cooldown + ilvl (MOVED from the old advBox).
    local cdLabel = UIElements.CreateLabel(adj, L("AP_COOLDOWN_LABEL"), 9, P.muted)
    cdLabel:SetPoint("LEFT", kwShell, "RIGHT", 22, 0)
    local cdBox, cdShell = UIElements.CreateEditBox(adj, "PartyLensAPCooldown", 46, 26)
    cdShell:SetPoint("LEFT", cdLabel, "RIGHT", 8, 0)
    cdBox:SetText(tostring(partyLens.db.autopilot.whisperCooldown or 20))
    cdBox:SetScript("OnTextChanged", function(e) SaveAutopilotNumber(e, "whisperCooldown", partyLens, 5) end)
    local ilvlLabel = UIElements.CreateLabel(adj, L("LISTING_ILVL_LABEL"), 9, P.muted)
    ilvlLabel:SetPoint("LEFT", cdShell, "RIGHT", 18, 0)
    local ilvlBox, ilvlShell = UIElements.CreateEditBox(adj, "PartyLensAPIlvl", 46, 26)
    ilvlShell:SetPoint("LEFT", ilvlLabel, "RIGHT", 8, 0)
    ilvlBox:SetText(tostring(partyLens.db.autopilot.minIlvl or 0))
    ilvlBox:SetScript("OnTextChanged", function(e) SaveAutopilotNumber(e, "minIlvl", partyLens, 0) end)

    -- Announce-to-channel toggle (MOVED from buildBox); find-mode strict toggle
    -- is added in Task 4 and shown/hidden by role.
    ap.autoAnnounceToggle = UIElements.CreateToggle(adj, L("AP_AUTO_ANNOUNCE"), 220)
    ap.autoAnnounceToggle:SetPoint("TOPLEFT", 0, -66)
    ap.autoAnnounceToggle:SetChecked(partyLens.db.autopilot.autoAnnounce)
    ap.autoAnnounceToggle:SetScript("OnClick", function(c)
        c:SetChecked(not c:GetChecked())
        partyLens.db.autopilot.autoAnnounce = c:GetChecked()
    end)
```

`db.autopilot.autoInvite` is no longer a visible toggle; leave its default `true` in the DB (auto-invite is implied by mode `auto`). Keep `ap.autoInviteToggle`/`ap.findStrictToggle`/`ap.autoWhisperToggle` references only where Task 4 recreates them; remove the old buildBox/findBox toggle creation.

- [ ] **Step 5: Summary + ARM on the Setup face**

Add below Adjust (parented to `setupFace`):

```lua
    ap.summaryDivider = UIElements.CreateDivider(setupFace)
    ap.summaryDivider:SetPoint("TOPLEFT", PAD, -300)
    ap.summaryDivider:SetPoint("RIGHT", -PAD, 0)

    ap.summary = UIElements.CreateLabel(setupFace, "", 11, P.gold)
    ap.summary:SetPoint("TOPLEFT", PAD, -314)
    ap.summary:SetPoint("RIGHT", -PAD, 0)
    ap.summary:SetJustifyH("LEFT")

    ap.armBtn = UIElements.CreateButton(setupFace, L("AP_ARM"), 210, 36, P.teal)
    ap.armBtn:SetPoint("TOPLEFT", PAD, -352)
    ap.armBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)
    ap.setupStatus = UIElements.CreateLabel(setupFace, "", 12, P.muted)
    ap.setupStatus:SetPoint("LEFT", ap.armBtn, "RIGHT", 12, 0)
    ap.setupStatus:SetText(L("AP_STATUS_IDLE"))
```

- [ ] **Step 6: Simplify `LayoutAP`**

`LayoutAP` now only reflows the Setup face's summary/divider/ARM when Adjust collapses. Replace L863-887:

```lua
local AP_ADJ_HEIGHT = 96
local function LayoutAP(partyLens)
    local ap = partyLens.ap
    if not ap or not ap.summary then return end
    local open = partyLens.db.autopilot.adjustOpen and true or false
    if ap.adjustToggle then
        ap.adjustToggle:SetText((open and "▾  " or "▸  ") .. L("AP_ADJUST"))
    end
    if ap.adjBox then ap.adjBox:SetShown(open) end
    local s = open and AP_ADJ_HEIGHT or 0
    ap.summaryDivider:ClearAllPoints()
    ap.summaryDivider:SetPoint("TOPLEFT", PAD, -300 - s); ap.summaryDivider:SetPoint("RIGHT", -PAD, 0)
    ap.summary:ClearAllPoints()
    ap.summary:SetPoint("TOPLEFT", PAD, -314 - s); ap.summary:SetPoint("RIGHT", -PAD, 0)
    ap.armBtn:ClearAllPoints(); ap.armBtn:SetPoint("TOPLEFT", PAD, -352 - s)
end
```

- [ ] **Step 7: Split `UIMain.RefreshAutopilot` — face switch + Setup repaint**

Rewrite `UIMain.RefreshAutopilot` (L1628-1731). Compute `armed`, `plCount` (keep the existing mesh-count logic L1647-1663 verbatim), then show one face and repaint it. The cockpit repaint is a call to a helper filled in Task 3 (`RefreshCockpit`); stub it to a no-op here so this task runs standalone:

```lua
function UIMain.RefreshAutopilot(partyLens)
    local ap = partyLens.ap
    if not ap then return end
    local P = UIElements.PALETTE
    local cfg = partyLens.db.autopilot
    local rt = partyLens.autopilot
    local armed = rt and rt.armed

    -- (keep existing mesh-count block here → sets ap.meshLabel)

    if armed then
        ap.setupFace:Hide(); ap.cockpitFace:Show()
        if UIMain.RefreshCockpit then UIMain.RefreshCockpit(partyLens) end
        return
    end
    ap.cockpitFace:Hide(); ap.setupFace:Show()

    -- Adjust echo on the collapsed toggle.
    local modeEcho = cfg.tier == "suggest" and L("AP_ADJUST_ECHO_SUGGEST") or L("AP_ADJUST_ECHO_AUTO")

    -- Natural-language summary (keep existing AP_SUMMARY_BUILD/FIND logic L1669-1682).
    -- compNeed readout for build (port L1690-1709 need computation, but only the
    -- setup-relevant part: compNeed text). Roster/log/announce move to the cockpit.
end
```

Port the summary composition (L1669-1682) and the build-mode `compNeed`/need text into the setup branch. Delete the roster/need/announce/log/GO repaint from this function — those belong to the cockpit (Task 3).

- [ ] **Step 8: Verify**

Run the verify helper. Expected `syntax OK`. In-game checklist:
- `/partylens auto` while disarmed shows the Setup face: Objetivo, Conteúdo, Grupo, ▸ Ajustar (collapsed), summary sentence, ARMAR.
- Clicking ▸ Ajustar expands to show Automação (Automático/Sugerir), keyword, cooldown, ilvl, announce toggle; summary + ARM shift down without overlap; collapsing restores.
- Selecting Automático/Sugerir highlights the right button and persists across `/reload`.
- Pressing ARMAR hides the Setup face (cockpit is a blank frame for now — expected).

- [ ] **Step 9: Commit**

```bash
git add Modules/UIMain.lua Modules/Localization.lua
git commit -m "Autopilot: two-face panel + rebuilt Setup face with Adjust disclosure"
```

---

### Task 3: Cockpit face (build mode) — status, pips, roster, live action, log

Fill `ap.cockpitFace` and add `UIMain.RefreshCockpit`. Build mode only; find-mode differences come in Task 4.

**Files:**
- Modify: `Modules/UIMain.lua` (`CreateAutopilotPanel` — add cockpit widgets; add `UIMain.RefreshCockpit`; `AP_STATE_LABEL` L817-822)

**Interfaces:**
- Consumes: `ap.cockpitFace` (Task 2), `Roster.Needed`/`Roster.Snapshot`, `rt.state`/`rt.pendingAction`/`rt.log`, `Autopilot.PressGo`/`Autopilot.AnnounceReady`/`Autopilot.Toggle`, `Utils.ClassColoredName`.
- Produces: `UIMain.RefreshCockpit(partyLens)` (called from `RefreshAutopilot` when armed); a `SetPips(frame, filled, total)` local helper. Task 4 reuses the status/log/DISARM widgets and hides the pips for find mode.

- [ ] **Step 1: Add a slot-pip helper**

In `Modules/UIMain.lua`, near the other Autopilot locals (before `CreateAutopilotPanel`), add a colored-square pip strip. Filled = seated, hollow = open; role-tinted only where a member's role is known, else neutral `P.text`:

```lua
-- A row of small squares showing group fill. `parent` gets up to MAX pip textures
-- created lazily on `parent.pips`; SetPips paints the first `total`, filling `filled`.
local AP_PIP_MAX = 40
local function SetPips(parent, filled, total)
    local P = UIElements.PALETTE
    parent.pips = parent.pips or {}
    total = math.min(total or 0, AP_PIP_MAX)
    for i = 1, AP_PIP_MAX do
        local pip = parent.pips[i]
        if i <= total then
            if not pip then
                pip = parent:CreateTexture(nil, "ARTWORK")
                pip:SetSize(12, 12)
                pip:SetPoint("LEFT", (i - 1) * 16, 0)
                parent.pips[i] = pip
            end
            local on = i <= (filled or 0)
            pip:SetColorTexture(
                on and P.teal[1] or P.stroke[1],
                on and P.teal[2] or P.stroke[2],
                on and P.teal[3] or P.stroke[3],
                on and 1 or 0.5)
            pip:Show()
        elseif pip then
            pip:Hide()
        end
    end
end
```

- [ ] **Step 2: Build the cockpit widgets**

Inside `CreateAutopilotPanel`, after the Setup face block, add the cockpit children (parented to `ap.cockpitFace`; offsets are starting values):

```lua
    -- ===================== COCKPIT FACE =====================
    ap.cfgLine = UIElements.CreateLabel(cockpitFace, "", 11, P.muted)
    ap.cfgLine:SetPoint("TOPLEFT", PAD, -PAD)
    ap.cfgLine:SetJustifyH("LEFT")
    ap.editBtn = UIElements.CreateButton(cockpitFace, L("AP_EDIT"), 64, 20, P.blue)
    ap.editBtn:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    ap.editBtn:SetScript("OnClick", function()
        Autopilot.Disarm(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)

    ap.statusDot = cockpitFace:CreateTexture(nil, "ARTWORK")
    ap.statusDot:SetSize(10, 10)
    ap.statusDot:SetPoint("TOPLEFT", PAD, -48)
    ap.statusLabel = UIElements.CreateLabel(cockpitFace, "", 14, P.text)
    ap.statusLabel:SetPoint("LEFT", ap.statusDot, "RIGHT", 8, 0)
    ap.disarmBtn = UIElements.CreateButton(cockpitFace, L("AP_DISARM"), 120, 26, P.coral)
    ap.disarmBtn:SetPoint("TOPRIGHT", -PAD, -42)
    ap.disarmBtn:SetScript("OnClick", function()
        Autopilot.Toggle(partyLens); UIMain.RefreshAutopilot(partyLens)
    end)

    ap.progressLabel = UIElements.CreateLabel(cockpitFace, "", 11, P.muted)
    ap.progressLabel:SetPoint("TOPLEFT", PAD, -86)
    ap.pipRow = CreateFrame("Frame", nil, cockpitFace)
    ap.pipRow:SetPoint("TOPLEFT", PAD, -106); ap.pipRow:SetSize(600, 14)
    ap.rosterLabel = UIElements.CreateLabel(cockpitFace, "", 11, P.text)
    ap.rosterLabel:SetPoint("TOPLEFT", PAD, -128); ap.rosterLabel:SetPoint("RIGHT", -PAD, 0)
    ap.rosterLabel:SetJustifyH("LEFT")
    ap.needLabel = UIElements.CreateLabel(cockpitFace, "", 11, P.gold)
    ap.needLabel:SetPoint("TOPLEFT", PAD, -148); ap.needLabel:SetPoint("RIGHT", -PAD, 0)
    ap.needLabel:SetJustifyH("LEFT")

    ap.announceBtn = UIElements.CreateButton(cockpitFace, L("AP_ANNOUNCE_BTN"), 150, 28, P.gold)
    ap.announceBtn:SetPoint("TOPLEFT", PAD, -178)
    ap.announceBtn:SetScript("OnClick", function() Autopilot.AnnounceReady(partyLens) end)
    ap.goBtn = UIElements.CreateButton(cockpitFace, L("AP_GO"), 80, 28, P.gold)
    ap.goBtn:SetPoint("LEFT", ap.announceBtn, "RIGHT", 8, 0)
    ap.goBtn:SetScript("OnClick", function() Autopilot.PressGo(partyLens) end)
    ap.goBtn:Hide()

    ap.logHeader = UIElements.CreateLabel(cockpitFace, L("AP_LOG_TITLE"), 10, P.muted)
    ap.logHeader:SetPoint("TOPLEFT", PAD, -220)
    ap.logLines = {}
    for i = 1, 6 do
        local line = UIElements.CreateLabel(cockpitFace, "", 10, P.faint)
        line:SetPoint("TOPLEFT", PAD, -240 - (i - 1) * 16); line:SetPoint("RIGHT", -PAD, 0)
        line:SetJustifyH("LEFT"); line:Hide()
        ap.logLines[i] = line
    end
```

- [ ] **Step 3: Add `UIMain.RefreshCockpit`**

Add after `UIMain.RefreshAutopilot`. Reuses the need/roster/log logic ported out of the old refresh:

```lua
function UIMain.RefreshCockpit(partyLens)
    local ap = partyLens.ap
    local P = UIElements.PALETTE
    local cfg = partyLens.db.autopilot
    local rt = partyLens.autopilot
    local state = (rt and rt.state) or "searching"

    local modeLabel = cfg.tier == "suggest" and L("AP_MODE_SUGGEST") or L("AP_MODE_AUTO")
    local contentLabel = (cfg.activityFilter ~= "" and cfg.activityFilter)
        or L(cfg.activityType == "raid" and "TAB_RAIDS" or cfg.activityType == "any" and "FILTER_ALL" or "TAB_DUNGEONS")
    local roleWord = cfg.role == "build" and L("AP_ROLE_BUILD") or L("AP_ROLE_FIND")
    ap.cfgLine:SetText(roleWord .. " · " .. contentLabel .. " · " .. modeLabel)

    ap.statusLabel:SetText(L(AP_STATE_LABEL[state] or "AP_STATUS_SEARCHING"))
    local live = (state == "ready") and P.freshNew or P.teal
    ap.statusDot:SetColorTexture(live[1], live[2], live[3], 1)

    local need, snap = Roster.Needed(partyLens)
    ap.progressLabel:SetText(L("AP_GROUP_PROGRESS", snap.size, snap.max or (snap.size + need.total)))
    SetPips(ap.pipRow, snap.size, snap.max or (snap.size + need.total))
    local names = {}
    for _, m in ipairs(snap.members) do names[#names + 1] = Utils.ClassColoredName(m.name or "", m.classFile) end
    ap.rosterLabel:SetText(table.concat(names, ", "))

    if need.total <= 0 then
        ap.needLabel:SetText(L("AP_NEED_NONE")); ap.needLabel:SetTextColor(P.freshNew[1], P.freshNew[2], P.freshNew[3], 1)
    else
        local parts = {}
        if need.tank > 0 then parts[#parts+1] = need.tank .. "T" end
        if need.heal > 0 then parts[#parts+1] = need.heal .. "H" end
        if need.dps  > 0 then parts[#parts+1] = need.dps  .. "D" end
        ap.needLabel:SetText(L("AP_NEED_REMAINING", (#parts > 0) and table.concat(parts, " ") or (need.remaining .. "x")))
        ap.needLabel:SetTextColor(P.gold[1], P.gold[2], P.gold[3], 1)
    end

    ap.goBtn:SetShown(rt and rt.pendingAction ~= nil)
    UIElements.SetButtonEnabled(ap.announceBtn, snap.size > 1)
    ap.announceBtn:Show()

    local log = (rt and rt.log) or {}
    for i = 1, #ap.logLines do
        local entry = log[i]
        if entry then
            local stamp = date and date("%H:%M", entry.t) or ""
            ap.logLines[i]:SetText("|cff5a6470" .. stamp .. "|r  " .. entry.text); ap.logLines[i]:Show()
        else
            ap.logLines[i]:Hide()
        end
    end
end
```

- [ ] **Step 4: Verify**

Run the verify helper. In-game checklist (build mode, solo is fine):
- ARMAR → Setup hides, Cockpit shows: config line (`Build · <content> · Automático`), status dot + text, DESARMAR, `GRUPO 1/5` + one filled pip + hollow pips, need `falta …`, Anunciar pronto (disabled solo), log lines appear as the ticker acts.
- ✎ editar and DESARMAR both return to the Setup face with controls intact.
- Switch mode to Sugerir, re-arm, trigger a candidate → GO appears; pressing GO fires and hides it.

- [ ] **Step 5: Commit**

```bash
git add Modules/UIMain.lua
git commit -m "Autopilot: build-mode cockpit face (status, slot pips, roster, log)"
```

---

### Task 4: Find-mode variations + final polish

Make both faces correct in find mode, and finish role-driven show/hide.

**Files:**
- Modify: `Modules/UIMain.lua` (`CreateAutopilotPanel` — find widgets; `UpdateAutopilotRole` L824-840; `UIMain.RefreshCockpit`; find-mode Adjust)

**Interfaces:**
- Consumes: `ap.findBox`, `ap.autoAnnounceToggle`, `UIMain.RolesText`, `rt.contactCount` (a table `[lowerShortName] = attempts`, maintained by `Autopilot.RecordContact`; the contacts counter shows the count of distinct keys, not the value).
- Produces: role-correct Setup (SUA FUNÇÃO chips + auto-whisper/strict in Adjust) and Cockpit (no pips, contacts counter).

- [ ] **Step 1: Add find-mode Adjust toggles**

In the Adjust box (Task 2 Step 4), add the two find-only toggles, hidden by default (shown by role in Step 3):

```lua
    ap.autoWhisperToggle = UIElements.CreateToggle(adj, L("AP_AUTO_WHISPER"), 200)
    ap.autoWhisperToggle:SetPoint("TOPLEFT", 0, -66)
    ap.autoWhisperToggle:SetChecked(partyLens.db.autopilot.autoWhisper)
    ap.autoWhisperToggle:SetScript("OnClick", function(c)
        c:SetChecked(not c:GetChecked()); partyLens.db.autopilot.autoWhisper = c:GetChecked()
    end)
    ap.findStrictToggle = UIElements.CreateToggle(adj, L("AP_FIND_STRICT"), 240)
    ap.findStrictToggle:SetPoint("TOPLEFT", 260, -66)
    ap.findStrictToggle:SetChecked(partyLens.db.autopilot.findStrict ~= false)
    ap.findStrictToggle:SetScript("OnClick", function(c)
        c:SetChecked(not c:GetChecked()); partyLens.db.autopilot.findStrict = c:GetChecked()
    end)
```

- [ ] **Step 2: Add the cockpit contacts counter**

In `CreateAutopilotPanel`'s cockpit block, add (shown by role in Step 3):

```lua
    ap.contactsLabel = UIElements.CreateLabel(cockpitFace, "", 11, P.muted)
    ap.contactsLabel:SetPoint("TOPLEFT", PAD, -86)
    ap.contactsLabel:Hide()
```

- [ ] **Step 3: Role-driven show/hide in `UpdateAutopilotRole`**

Extend `UpdateAutopilotRole` (L824-840) so the Adjust body swaps build vs find controls, and set the roleSection label (already there). Append before its final `end`:

```lua
    if ap.autoAnnounceToggle then ap.autoAnnounceToggle:SetShown(role == "build") end
    if ap.autoWhisperToggle then ap.autoWhisperToggle:SetShown(role == "find") end
    if ap.findStrictToggle then ap.findStrictToggle:SetShown(role == "find") end
```

- [ ] **Step 4: Find branch in `UIMain.RefreshCockpit`**

In `RefreshCockpit`, branch build vs find for the progress/pips/need area:

```lua
    if cfg.role == "find" then
        ap.progressLabel:Hide(); ap.pipRow:Hide(); ap.rosterLabel:Hide()
        ap.contactsLabel:Show()
        -- rt.contactCount is a TABLE ([lowerShortName] = attempts); count distinct names.
        local contacted = 0
        for _ in pairs((rt and rt.contactCount) or {}) do contacted = contacted + 1 end
        ap.contactsLabel:SetText(L("AP_CONTACTED", contacted))
        local rolesText = (UIMain.RolesText and UIMain.RolesText(partyLens)) or "dps"
        if rolesText == "" then rolesText = "dps" end
        ap.needLabel:SetText(L("AP_MYROLE_LABEL") .. ": " .. rolesText)
        ap.needLabel:SetTextColor(P.muted[1], P.muted[2], P.muted[3], 1)
        ap.announceBtn:Hide()
        -- status/dot/cfgLine/log handled above, unchanged.
        ap.cfgLine:SetText(L("AP_ROLE_FIND") .. " · " .. contentLabel .. " · " .. rolesText .. " · " .. modeLabel)
    else
        ap.progressLabel:Show(); ap.pipRow:Show(); ap.rosterLabel:Show(); ap.contactsLabel:Hide()
        -- (existing build-mode progress/pips/roster/need/announce block)
    end
```

Move the `contentLabel`/`modeLabel` locals above this branch so both branches use them.

- [ ] **Step 5: Verify**

Run the verify helper. In-game checklist:
- Setup + find role: GRUPO row becomes SUA FUNÇÃO with spec chips; Adjust shows auto-whisper + strict (not announce); summary reads the find sentence.
- ARM in find mode → cockpit shows `Find · <content> · <roles> · <mode>`, no pips/roster, `N grupos sussurrados`, whisper log lines; no Anunciar button.
- Toggle back to build → all build widgets return; no leftover find widgets visible.
- `/reload` in each mode: no Lua errors; disarmed always lands on Setup.

- [ ] **Step 6: Release bump**

Per the project's release workflow (feature → minor bump), update `PartyLens.toc` `## Version` and prepend a `CHANGELOG.md` entry (e.g. `0.33.1 → 0.34.0`, "Autopilot screen redesigned: calm Setup / live Cockpit; automation simplified to Automatic/Suggest").

- [ ] **Step 7: Commit**

```bash
git add Modules/UIMain.lua PartyLens.toc CHANGELOG.md
git commit -m "Autopilot: find-mode Setup/Cockpit variations; release 0.34.0"
```

---

## Self-Review notes

- **Spec coverage:** two-face model (Task 2 Step 3/7), Setup layout incl. Adjust (Task 2), Cockpit incl. pips/status/log (Task 3), find variations (Task 4), automation 3→2 + migration (Task 1), toggles-into-Adjust (Task 2/4), out-of-scope Summon untouched (no task touches it). Natural-language summary reused (Task 2 Step 7). Mesh count preserved (shared header, Task 2 Step 3).
- **Deferred-to-in-game:** all pixel offsets are starting values, tuned during each task's in-game checklist — consistent with the codebase's hand-tuned offset convention.
- **Field-name continuity:** `ap.contentBtns`, `ap.activityDropdown`, `ap.buildBox`, `ap.findBox`, `ap.compBtn`, `ap.compNeed`, `ap.roleBuildBtn`, `ap.roleFindBtn`, `ap.rosterLabel`, `ap.needLabel`, `ap.announceBtn`, `ap.goBtn`, `ap.logLines`, `ap.meshLabel`, `ap.summary` kept so existing helpers (`UpdateAutopilotContent`, `UIMain.RefreshComp`, `RefreshAutopilotActivities`, `UpdateAutopilotRole`) keep working. New: `ap.setupFace`, `ap.cockpitFace`, `ap.modeAutoBtn`, `ap.modeSuggestBtn`, `ap.adjBox`, `ap.adjustToggle`, `ap.cfgLine`, `ap.editBtn`, `ap.statusDot`, `ap.statusLabel`, `ap.disarmBtn`, `ap.progressLabel`, `ap.pipRow`, `ap.contactsLabel`, `ap.setupStatus`, `ap.summaryDivider`.
```
