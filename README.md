# PartyLens

**Your group radar — and a live player network — for the WoW TBC Anniversary client.**

PartyLens started as a better LookingForGroup: it watches the LFG chat channel **and**
the built-in Group Finder at once and puts every group in one clean, searchable panel.
It has since grown into a **realm-wide PartyLens network** — layer hopping, a world-boss
radar, community reputation, and a cross-layer group broker — all powered by other people
running the addon. The more players use it, the more it does for you.

Built for the **TBC Anniversary (Interface 2.5.x)** client, no dependencies, 10 languages.

---

## 🔎 Group finder (the core)

- **Two sources, one panel** — scans the LFG chat channel *and* the Group Finder together,
  deduplicated. Most addons do only one.
- **Role-need pips (Tank / Heal / DPS)** — color-coded, showing exactly what each group
  still needs; a healer can filter to "groups that need a healer" instantly.
- **Class + level filters** — icon toggles per class and a minimum-level field. Class is a
  hard filter (almost always known); the real level of PartyLens users comes free over the
  mesh, and a click **Who** resolves it for anyone else.
- **One-click whisper** — auto-fills a friendly message from your class, spec(s) and role:
  `Hi! {class} {spec} {role} here. {comment}` — fully editable.
- **Rich result cards** — LFG/LFM badge, a **PL** badge for fellow PartyLens users,
  class-colored leader name, group-fill bar (`3/5`, `24/25`), freshness dot, and the message.
- **Create a listing in two clicks** — pick the dungeon/raid from a live list with real
  names and correct IDs (with search, level range, and a max-level filter).
- **Modern "dark glass" interface** — translucent layered panels, no default WoW widgets,
  draggable, Escape-to-close, stays on screen.

## 🤖 Autopilot — hands-off recruiting & joining

- **Build a group**: define the composition you want on a **class + spec grid** (it derives
  how many Tank/Heal/DPS you need), and Autopilot auto-invites matching players and
  re-announces your LFM.
- **Find a group**: it reads what a group actually asks for and only answers the ones that
  need **your** role/class — with anti-spam caps and a per-name cooldown.
- **Multi-spec**: your roles are derived from the spec(s) you play (Resto + Balance → heal /
  dps), so you match anything you can fill.

## ✨ Summon coordination

A shared "summon stone" screen for the group: mark who needs a port, see who's ready, and
coordinate warlock summons without spamming chat.

---

## 🌐 The PartyLens Network

PartyLens users quietly form a network on your realm. Presence, sightings, vouches and
group needs sync between people running the addon; realm-wide calls to action go out as one
**signed** public line that every PartyLens beacon reads. (See *How the network reaches
people* below.)

### 🌀 Layer hopping + silent beacon

- **Standalone layer detection** — reads your layer from nearby NPC GUIDs (no NWB/AutoLayer
  needed) and **converges the numbering across the network**, so "my Layer 5" is your
  Layer 5 (and tends to match NWB).
- **Beacon** (right-click the minimap or the Beacon button): you become a silent node that
  **auto-invites anyone asking for your layer** in chat — no party spam, no whisper popups,
  party frame hidden — and sends one signed `/w`. Invites fire **the instant** a matching
  request appears, to win the client before other layer addons.
- **Get pulled**: a visual layer picker shows the layers the network actually knows about —
  a dot marks the ones with a **live beacon**, gold marks yours. Tap one (or "Any") and the
  network pulls you there. Match is by **exact zone identity + same map**, so it never sends
  you to the wrong layer.

### 🐉 World Boss Radar

- Recognises world bosses & rares by NPC id (Doom Lord Kazzak, Doomwalker, Fel Reaver —
  expandable) the moment you target / mouse-over / see one.
- **Alerts** you (chat + sound) and **shares the sighting across the network** with its layer.
- A dedicated **Radar** tab lists active sightings with **Hop** (pulls you to the boss's
  exact layer, even on another map) and **Shout** (a signed public rally that also spreads
  the addon's name).

### ⭐ Reputation (positive-only vouches)

- **Vouch** for players you grouped with; each vouch spreads over the network and everyone
  tallies "N players vouched for this person". No downvotes (no toxicity/defamation), and
  it's resistant to self-vouching.
- Groupmates become automatic vouch suggestions; a periodic digest keeps the web in sync.

### 🤝 Group broker

- A live list of **PartyLens users looking for group right now**, cross-layer, with one-click
  **Invite** and **whisper** — the network's own LFG, full of coordinated addon users.

### 📊 Network dashboard

- Live counters — **Nodes · Layers · Bosses · Hops · Requests · Your rep** — plus the broker
  and your vouch list, so the "living network" is always visible.

---

## How the network reaches people

Hidden addon messages over the **CHANNEL** distribution are blocked on this client, so
PartyLens does **not** rely on a silent realm-wide bus. Instead:

- The **hidden mesh** (presence, layer numbering, world-boss sightings, vouches, broker)
  syncs over **guild, party and nearby players** — transports that actually deliver here.
- **Realm-wide reach** for a call to action (a "get me to layer N" request, a boss shout)
  is one **signed, visible** line, sent from a real click, that every PartyLens beacon scans.
- Because those posts are signed, PartyLens users **recognise each other realm-wide** — the
  **PL** badge — with no extra traffic.
- Every send is instrumented, so the mesh can never fail silently again. Check it with
  `/partylens netdiag` (what each transport delivers) and `/partylens netstat` (mesh health).

---

## Commands

| Command | What it does |
| --- | --- |
| `/partylens` | Toggle the window |
| `/partylens show` · `hide` | Open / close |
| `/partylens join` | Join the LookingForGroup channel |
| `/partylens auto` | Open Autopilot; `arm` / `disarm` to start/stop |
| `/partylens summon` | Open the summon coordination screen |
| `/partylens layer` · `radar` · `network` | Open the Layer / Radar / Network tabs |
| `/partylens beacon` | Toggle the layer beacon |
| `/partylens reqlayer <n\|any>` | Request a hop to a layer |
| `/partylens vouch <name>` | Vouch for a player |
| `/partylens netdiag` · `netstat` | Network transport diagnostics / health |

## Install

Drop the `PartyLens` folder into `Interface/AddOns/` and restart the client (or `/reload`).
No dependencies. PartyLens auto-joins LookingForGroup on login so chat scanning works right
away. The game requires the Group Finder search to come from a real click, so PartyLens
never spams that API in the background.

## Languages

Auto-detected from your game client: English, Português, Deutsch, Français, Español,
Italiano, Русский, 简体中文, 繁體中文, 한국어.

---

## Created by Chehul

PartyLens is made by **Chehul (danielcosta42)**. If it saves you time, you can support
development:

**[Donate via PayPal](https://www.paypal.com/donate/?business=daniel.cfdutra13@gmail.com&currency_code=USD)**

Source, issues and full changelog on **[GitHub](https://github.com/danielcosta42/PartyLens)**.
