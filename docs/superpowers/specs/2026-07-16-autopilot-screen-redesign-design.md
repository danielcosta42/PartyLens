# Autopilot screen redesign — design

**Date:** 2026-07-16
**Screen:** Autopilot mode panel (`CreateAutopilotPanel` / `UIMain.RefreshAutopilot` in `Modules/UIMain.lua`)
**Status:** Approved design, ready for implementation plan

## Problem

The current Autopilot screen stacks everything of every nature onto one panel:
Goal → Content → Recruit (comp + keyword + 2 toggles) → Automation (3 tiers +
description) → Advanced → text summary → ARM + status → live ops
(summon / roster / need) → activity log.

The user confirmed **all four** failure modes are present at once:

1. **Visual density** — too much shown simultaneously, no clear "look here first".
2. **Too many concepts** — Goal, Content, Recruit, Composition, Automation, and
   three tier names (Advisor/Assisted/Full) all demand a decision.
3. **Unclear flow** — not obvious what to do first, nor what ARM will actually do.
4. **Config + live mixed** — pre-arm configuration and live operation (roster,
   summon, log) share the same panel and blur together.

Because all four are present, this is a structural rework, not a cosmetic pass.

## What the user actually changes

Per session the user changes **Goal, Content/activity, and Composition**. The user
does **not** change the automation level session-to-session. This drives the whole
design: the three per-session choices stay front-and-center; everything else becomes
a default and moves out of the way.

## Design principles

- **Two faces, never both.** One panel renders either a calm **Setup** face or a
  live **Cockpit** face, chosen by the runtime `armed` flag. This directly resolves
  the config/live mixing.
- **Surface the per-session three; default and hide the rest.** Goal, Content, Group
  are always visible. Keyword, automation mode, whisper cooldown, min ilvl, announce
  toggle collapse behind a single **Adjust** disclosure.
- **A plain-language sentence before commitment.** A natural-language summary reads
  the config back ("Will build a Mechanar group and auto-invite anyone who whispers
  'inv'") so the user knows what ARM will do.
- **Follow the binding visual direction.** "Dark glass radar" brief governs: teal only
  for selection/focus/brand/live; muted section headers + dividers; full 4-side borders;
  role colors only for role pips. Build from `UIElements` factories. (See the
  `partylens-visual-direction` memory.)

## The two-state model

A single panel (`partyLens.autopilotPanel`) hosts two child containers:
`ap.setupFace` and `ap.cockpitFace`. `UIMain.RefreshAutopilot` shows exactly one based
on `partyLens.autopilot` being armed:

- **Not armed → Setup face** visible, Cockpit hidden.
- **Armed → Cockpit face** visible, Setup hidden.

`ARM` transitions Setup → Cockpit; `DISARM` (and the Cockpit's ✎ edit affordance)
transitions Cockpit → Setup. This reuses the existing `Autopilot.Toggle` / `rt.armed`
state — no new state machine.

## Setup face (not armed)

A short top-to-bottom form of only the per-session essentials.

```
 Autopilot                              PartyLens na rede: 3
 ─────────────────────────────────────────────────────────

  OBJETIVO
  ┌──────────────────────────┬──────────────────────────┐
  │  ● Montar grupo (LFM)    │    Entrar num grupo (LFG) │
  └──────────────────────────┴──────────────────────────┘

  CONTEÚDO
  [ Masmorra ][ Raid ][ Tudo ]   [ Tempest Keep — Mechanar ▾ ]

  GRUPO
  1T · 1H · 3D   ·  falta 1T 1H 3D          [ Editar composição ]

  ▸ Ajustar   (automático · convida no 'inv')
  ─────────────────────────────────────────────────────────
  Vai montar um grupo de Mechanar e convidar automaticamente
  quem sussurrar "inv".

  ┌────────────────────────┐
  │      ARMAR  ▶          │     Ocioso
  └────────────────────────┘
```

Elements:

- **Objetivo** — segmented pair (Montar grupo / Entrar num grupo). Selected = teal.
  Maps to `db.autopilot.role` (`build` / `find`), same as today.
- **Conteúdo** — `[Masmorra][Raid][Tudo]` segmented + the specific-activity dropdown.
  Maps to `activityType` + `activityID`/`activityFilter` (existing behavior, incl. the
  content→comfortable-comp auto-fill).
- **Grupo** (build) — compact comp readout (`1T · 1H · 3D`) plus what's still needed,
  and `[ Editar composição ]` opening the existing comp popup (`UIMain.OpenComp`).
  In **Find** mode this row becomes **SUA FUNÇÃO** with the existing spec chips
  (`BuildSpecChips`).
- **Adjust** — a single collapsible disclosure (`▸/▾ Ajustar`). Collapsed shows a
  one-line echo of its contents (`automático · convida no 'inv'`). Expanded:

  ```
    ▾ Ajustar
      Automação   [ Automático ][ Sugerir ]
      Convidar quem disser   [ inv ]
      Espera entre sussurros [ 20 ]s    ·    iLvl mínimo [ 0 ]
      [x] Anunciar LFM no canal
  ```

  (Find mode swaps in the strict-matching toggle in place of the keyword/announce.)
- **Natural-language summary** (gold/teal) directly above ARM — reads the config back.
  Reuses the existing `AP_SUMMARY_BUILD` / `AP_SUMMARY_FIND` locale strings.
- **ARMAR** — large teal primary button + status ("Ocioso") beside it.

No log, roster, or summon controls appear on this face.

## Cockpit face (armed)

The config controls collapse; the panel becomes a live monitor. Build mode:

```
 Autopilot                              PartyLens na rede: 3
 ─────────────────────────────────────────────────────────
  Build · Mechanar · Automático · 'inv'              ✎ editar

  ● Procurando membros…                       [ DESARMAR ]

  GRUPO   3/5
  ▮▮▮○○    Chehul, Xyz, Abc            ·   falta 1H 1D

  [ Anunciar pronto ]

  ATIVIDADE
  20:14  convidou Chehul
  20:13  ★ PartyLens: convidou Xyz
  20:12  anunciou LFM no canal
```

At 5/5 the status becomes **"● Grupo completo — pronto pra summon"** and the pips fill
(`▮▮▮▮▮`).

Structure, top to bottom:

- **Config summary line** (`Build · Mechanar · Automático · 'inv'`) — read-only, with
  a **✎ editar** affordance that disarms and returns to Setup (editing requires
  disarm — safer than mutating a live run).
- **Status block** — a status dot + large text driven by the existing state machine
  (`rt.state` → searching / assembling / ready / combat-paused). **DESARMAR** in coral
  to the right.
- **Progresso** — `GRUPO n/target` + **slot pips** `▮▮▮○○` (the one genuinely new
  widget: colored squares, filled = seated, hollow = open) + member names + the
  remaining-need readout (`falta 1H 1D`). Derived from `Roster.Needed` /
  `Roster.Snapshot` (already computed in the current refresh).
- **Live action** — `[ Anunciar pronto ]` (existing `announceBtn`). In **Sugerir**
  mode the gold **GO** button appears here only when `rt.pendingAction` is set.
- **ATIVIDADE** — the existing 5-line timestamped log.

### Find variation (cockpit)

```
  Find · Mechanar · Tank/Heal · Automático           ✎ editar
  ● Procurando grupos que precisam de Tank/Heal  [ DESARMAR ]
  CONTATOS   3 grupos sussurrados
  ATIVIDADE
  20:14  sussurrou Fulano (precisa de heal)
```

No roster pips (you are joining, not building). Instead a running count of groups
contacted this session. The rest (status, DISARM, log) is identical.

## Behavior changes (not just visual)

- **Automation 3 → 2 modes.** UI exposes only **Automático** and **Sugerir**.
  Mapping to today's `cfg.tier`:
  - `Automático` = today's `full` behavior (auto-fire invites/whispers/announce, never
    waits on a pending action).
  - `Sugerir` = today's `advisor` behavior (queue each action behind the GO button).
  - The now-hidden `assisted` tier folds into `Automático`.

  Persist `cfg.tier` as `"auto"` / `"suggest"`. Migrate in the Database backfill:
  `advisor → suggest`, `assisted|full → auto`. Update the tier checks in
  `Autopilot.lua` accordingly:
  - `EngageCandidate` (~L501, L518): queue `pendingAction` when `tier == "suggest"`,
    else auto-fire.
  - Auto-invite of matching PL mesh users (~L614): fire when `tier == "auto"`.
  - Tick's pending gate (~L732): treat `"auto"` as never-waiting (current `full`
    semantics), `"suggest"` as waiting on GO.
- **Toggles leave the main view.** `autoInvite` is implied by `Automático`. The
  channel-announce control (`autoAnnounce`) survives as a checkbox **inside Adjust**
  (default on). The strict-matching toggle (`findStrict`) moves into Adjust for Find
  mode.

## Out of scope

- The **Summon** screen (5th sidebar item) stays a separate mode. The cockpit keeps
  only the simple existing `Anunciar pronto` button; full summon coordination remains
  where it is. This redesign does not touch `Modules/Summon.lua` or `CreateSummonPanel`.
- No change to the mesh/Comm broadcast logic, the comp popup internals, the activity
  dropdown population (`RefreshAutopilotActivities`), or the sidebar navigation.
- No new colors or fonts — the "Dark glass radar" palette/type scale is unchanged.

## Implementation notes / touch points

- `Modules/UIMain.lua`: rebuild `CreateAutopilotPanel` into two child faces
  (`ap.setupFace`, `ap.cockpitFace`); split `UIMain.RefreshAutopilot` to toggle
  face visibility on `armed` and repaint whichever is shown. `LayoutAP` simplifies
  (Advanced-expand reflow now only affects the Setup face's Adjust section).
- `Modules/Autopilot.lua`: tier-check updates as above; the two-mode `Automático`
  path uses current `full` semantics.
- `Modules/Database.lua`: unconditional backfill migrates old tier values to
  `auto`/`suggest` (fills only when the value is one of the legacy strings).
- Slot-pip widget: a small helper (colored squares) — hollow for open slots, filled
  (role-tinted where known, else neutral) for seated members. Lives in `UIElements`
  or inline in UIMain, following the offset-based layout convention.
- Locale: reuse `AP_SUMMARY_*`, `AP_STATE_*`, `AP_ARM/DISARM`, `AP_GO`,
  `AP_ANNOUNCE_BTN`. New keys needed for the two mode names, the "editar" affordance,
  the pip/progress row, the Find "grupos contatados" counter, and the Adjust echo
  line — add to enUS + ptBR (other locales fall back to enUS).

## Testing considerations

- No in-repo Lua runtime — runtime behavior is verified in-game. Syntax-check with
  `luaparser` and run the repo `luacheck` (`.luacheckrc`) before shipping.
- Manual in-game checks: face flips on ARM/DISARM; ✎ editar disarms and returns to a
  correctly-populated Setup; tier migration leaves an existing DB armed-safe (armed
  state is runtime-only, so a reload never auto-resumes); pips track `n/target`;
  Find mode shows the spec-chip row and the contacts counter; Adjust collapse/expand
  reflows without overlapping the summary/ARM.
