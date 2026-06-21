# PartyLens — Branding & CurseForge Kit

> Goal: a memorable brand **and** organic discoverability (CurseForge search + Google).
> This file holds everything you need to publish: name decision, taglines, the full
> store page (EN + PT), keyword/SEO list, and the icon concept.

---

## 1. Name decision — keep **PartyLens**

**Verdict: keep it.** "PartyLens" is free on CurseForge (verified — no addon by that name),
it's brandable, and "Party" is literally the WoW word for a group while "Lens" carries the
*radar / see-everything* idea. It reads well, it's one word, and it's easy to say in a
Discord or a YouTube video.

**The one catch — and the fix.** Every competitor has the search keyword in its name:
*ClassicLFG, LFG MatchMaker, LFG Filter, LFG Expanded, GrouperLFG, LFG Bulletin Board (GBB)*.
CurseForge search ranks by **popularity + name match**, and players type **"LFG"** or
**"group finder"** into the box. A pure-brand name like "PartyLens" can get buried for a new
project.

The standard solution (used by GBB and many top addons) is to **split brand from the store
title**: the addon folder/brand stays `PartyLens`, but the **CurseForge project Title packs
the keywords**. You keep the brand and still show up for the searches that matter.

```
Brand / folder name:   PartyLens
CurseForge Title:      PartyLens — LFG & Group Finder (TBC Anniversary)
```

### Alternatives considered (if you ever want to pivot)

| Name | Read | Why not over PartyLens |
|---|---|---|
| **PartyRadar** | group radar | Strong, but "radar" is less ownable; a few "radar" addons exist |
| **GroupLens** | group + see | Good SEO ("group"), but blander, less catchy |
| **LFG Lens** | keyword + brand | Best pure-SEO, but looks like a generic LFG clone |
| **PartyScope** | party + scope | Fine, but "scope" feels more PvP/weapon |

PartyLens wins on memorability; the Title field covers the SEO gap.

---

## 2. Taglines

**Primary (EN)**
> One panel for LFG chat **and** the in-game Group Finder — no spam, no missed groups.

**Short (EN, for the CurseForge summary field, ~ under 120 chars)**
> A modern group radar that merges LFG chat and the Group Finder into one clean, searchable panel.

**Primary (PT)**
> Um só painel pro chat de LFG **e** o Group Finder do jogo — sem spam, sem perder grupo.

**Short (PT)**
> Um radar de grupos moderno que junta o chat de LFG e o Group Finder num painel limpo e pesquisável.

The whole pitch in one idea: **everyone else watches *either* chat *or* the finder.
PartyLens watches both, in one place.**

---

## 3. CurseForge store page — ENGLISH (primary)

> Paste this into the CurseForge description editor. It supports Markdown.

---

### PartyLens — your group radar for TBC Anniversary

**Tired of staring at the `LookingForGroup` channel so you don't miss a tank? Tired of
re-clicking the clunky Group Finder?** PartyLens watches **both at once** and puts every
group into one clean, searchable panel — with one-click whispers and the roles each group
still needs, at a glance.

It's a lightweight **LFG / group finder** built specifically for the **TBC Anniversary
(2.5.x)** client, where the modern dungeon finder doesn't exist.

#### Why PartyLens

- **Two sources, one panel.** It scans the **LFG chat channel** *and* the built-in
  **Group Finder** together. Most addons do only one — PartyLens unifies them, deduped.
- **See what each group needs.** Color-coded **role pips (Tank / Heal / DPS)** show exactly
  what's still open, so a healer can filter to "groups that need a healer" instantly.
- **One-click whisper.** Auto-fills a friendly message from your class, spec and role —
  `Hi! {class} {spec} {role} here. {comment}` — fully editable.
- **Rich result cards.** LFG/LFM badge, class-colored leader name, group-fill bar (e.g.
  `3/5`, `24/25`), a freshness dot, and the raw message — no guessing.
- **Smart filtering.** Filter by category (All · Dungeons · Raids · Guild · Quests · Other)
  and by the role you play. Search is instant and debounced.
- **Create a listing in two clicks.** Pick the dungeon/raid from a live list (real names,
  correct IDs) — no typing numeric activity IDs.
- **Modern "dark glass" UI.** Translucent layered panels, no default WoW widgets,
  draggable, Escape-to-close, stays on screen.
- **10 languages, auto-detected.** English, Português, Deutsch, Français, Español,
  Italiano, Русский, 简体中文, 繁體中文, 한국어.

#### Commands

- `/partylens` — toggle the window
- `/partylens show` / `hide`
- `/partylens join` — join the `LookingForGroup` channel

#### How it works

PartyLens auto-joins `LookingForGroup` on login so chat scanning works immediately. Click
**Update Dungeons** / **Update Raids** to refresh the official finder (the game requires that
search to come from a real click, so PartyLens never spams that API in the background).

Lightweight, no dependencies. Install, type `/partylens`, and stop missing groups.

*Keywords: LFG, LFM, looking for group, group finder, dungeon finder, raid finder, party
finder, group radar, TBC, Burning Crusade, Classic, Anniversary 2.5.x.*

---

## 4. CurseForge store page — PORTUGUÊS (section, paste below the English block)

---

### 🇧🇷 PartyLens em Português

**Cansado de ficar olhando o canal `LookingForGroup` pra não perder um tank? Cansado de
reabrir o Group Finder toda hora?** O PartyLens vigia **os dois ao mesmo tempo** e coloca
cada grupo num painel único, limpo e pesquisável — com whisper em um clique e as roles que
cada grupo ainda precisa, num relance.

É um addon **LFG / localizador de grupos** leve, feito pro cliente **TBC Anniversary (2.5.x)**,
onde o dungeon finder moderno não existe.

#### Por que usar

- **Duas fontes, um painel.** Lê o **canal de LFG** *e* o **Group Finder** nativo juntos,
  sem duplicar. A maioria dos addons faz só um dos dois.
- **Veja o que cada grupo precisa.** **Pips de role (Tank / Heal / DPS)** coloridos mostram
  o que está aberto — um healer filtra "grupos que precisam de healer" na hora.
- **Whisper em um clique.** Preenche uma mensagem amigável com sua classe, spec e role —
  `Oi! {class} {spec} {role} aqui. {comment}` — totalmente editável.
- **Cards completos.** Selo LFG/LFM, nome do líder colorido por classe, barra de vagas
  (`3/5`, `24/25`), indicador de "quão recente" e a mensagem original.
- **Filtro inteligente.** Por categoria (Tudo · Masmorras · Raides · Guilda · Quests · Outros)
  e pela role que você joga. Busca instantânea.
- **Criar listagem em dois cliques.** Escolha a masmorra/raide numa lista real — sem decorar
  IDs numéricos.
- **Interface "vidro escuro" moderna.** Painéis translúcidos, nada de widgets padrão do WoW.
- **10 idiomas, detectados automaticamente.**

#### Comandos

- `/partylens` — abre/fecha a janela
- `/partylens show` / `hide`
- `/partylens join` — entra no canal `LookingForGroup`

Leve, sem dependências. Instale, digite `/partylens` e pare de perder grupo.

---

## 5. Keywords & SEO

### CurseForge — project setup

- **Category:** `Boss Encounters / Group / Roles`? No — use **"Map & Minimap"** only if
  minimap-relevant. The right primary category is **"PvE"** is not a category either.
  Use **"Group, Guild & Friends"** (the closest official CurseForge WoW category for LFG
  tools). Verify the exact category name in the upload dropdown and pick the one matching
  *group/social* tools.
- **Game versions:** tag the **Burning Crusade Classic / TBC Anniversary (2.5.x)** version
  so it appears in the TBC filter. This is the single biggest discoverability lever.
- **Title field:** `PartyLens — LFG & Group Finder (TBC Anniversary)`

### Keyword list (use across Title, summary, description, and the first paragraph)

Primary: `LFG`, `LFM`, `group finder`, `looking for group`, `TBC`, `Anniversary`, `Classic`
Secondary: `dungeon finder`, `raid finder`, `party finder`, `group radar`, `LFG chat`,
`role filter`, `tank healer dps`, `whisper`, `Burning Crusade`, `2.5.x`
Long-tail (great for Google): `tbc anniversary group finder addon`,
`classic tbc lfg addon`, `wow tbc looking for group addon`, `tbc dungeon group addon`

**Rule of thumb:** the words "LFG" and "group finder" should appear in the **Title, the
summary, and the first two sentences** of the description. They already do above.

### Off-CurseForge organic reach (cheap, high-leverage)

- Post a short "I made an LFG addon that watches chat **and** the Group Finder" thread in
  **r/classicwow** and **r/woweconomy**, plus the TBC Anniversary Discord(s).
- Add the repo to **WoWInterface** and **Wago.io** as well — they rank on Google for addon
  searches and cost nothing extra.
- Make a 20–30s GIF of the panel filtering by role; it's the most shareable asset you have.

---

## 6. Icon / logo concept

**Concept: a teal radar "lens" sweep inside a rounded dark-glass tile.**

The icon should read at 64×64 and 32×32 in the addon list, so: one bold shape, max two
accent colors, high contrast against WoW's busy UI.

- **Tile:** rounded square, near-black dark-glass (`#090A0D`) with a hairline teal edge —
  matches the in-game UI exactly.
- **Symbol:** a stylized **lens / radar ring** in the signature teal (`#26DBB8`) with a
  single sweeping highlight, suggesting *scanning for groups*.
- **Detail:** three tiny dots inside the ring in the **role colors** (tank blue `#5C9EFF`,
  heal green `#76DE85`, dps coral `#FF7870`) — the same role pips users see in the app, so
  the icon "rhymes" with the product.
- **Avoid:** text in the icon (unreadable at small sizes), gradients that mush together, and
  the generic magnifying-glass cliché — the radar-ring + role-dots is more distinctive.

A ready-to-edit vector mockup is in **`icon-concept.svg`** (open it in any browser or
Figma/Illustrator). Export at **64×64 PNG** for the addon icon and **512×512** for the
CurseForge logo.

### Brand palette (pulled from the live UI)

| Token | Hex | Use |
|---|---|---|
| Dark glass shell | `#090A0D` | backgrounds, icon tile |
| **Teal (signature)** | `#26DBB8` | logo, accents, links |
| Gold | `#FABB4D` | highlights |
| Coral | `#FF6B61` | DPS / alerts |
| Tank blue | `#5C9EFF` | role pip |
| Heal green | `#76DE85` | role pip |

---

## 7. Quick publish checklist

- [ ] Set CurseForge **Title** to `PartyLens — LFG & Group Finder (TBC Anniversary)`
- [ ] Paste EN description, then the PT section
- [ ] Tag the **TBC Anniversary (2.5.x)** game version
- [ ] Pick the **group/social** category
- [ ] Upload **64×64** icon (from `icon-concept.svg`)
- [ ] Add 2–3 screenshots + one role-filter GIF
- [ ] Cross-post: WoWInterface, Wago.io, r/classicwow, TBC Discord
