# PartyLens

PartyLens is a lightweight TBC Anniversary addon that watches the `LookingForGroup`
chat channel and the built-in group finder, then gives you one searchable panel
with quick whisper templates.

**Now with multi-language support!** 🌍 The addon automatically detects your game language
and displays in: English, Portuguese, German, French, Spanish, Italian, Russian, 
Simplified Chinese, Traditional Chinese, and Korean.

## Use

- `/partylens` toggles the window.
- `/partylens show` opens it.
- `/partylens hide` closes it.
- `/partylens join` joins `LookingForGroup`.

Click **Atualizar Masmorras** / **Update Dungeons** or **Atualizar Raides** / **Update Raids** 
to refresh the official group finder. The game requires those searches to happen from a hardware click,
so PartyLens does not auto-query that API in the background.

The quick whisper message uses a template:

`Oi! {class} {spec} {role} aqui. {comment}`

You can edit `spec`, `role`, and `comment` in the panel. The message adapts to your game language.

## Architecture

PartyLens uses a **modular component-based architecture** with:

- **Utils** - Common utility functions
- **Localization** - Multi-language support (10 languages)
- **LocalizedKeywords** - Language-aware keyword detection
- **Activity** - Dungeon/Raid recognition
- **Needs** - Role detection (tank, heal, dps)
- **Database** - Persistent data storage
- **Entry** - Group entry management
- **Chat** - LFG channel monitoring
- **LFGTool** - Built-in group finder integration
- **Messaging** - Message templates
- **UIElements** - Reusable UI components
- **UIMain** - Main interface
- **Search** - Filtering and scoring
- **Roster** - Party composition tracking
- **Comm** - PartyLens-to-PartyLens mesh (hidden addon messages)
- **Autopilot** - Auto-recruit / auto-join + summon coordination

## Version

**0.8.0** - Badge polish + activity picker:

- Result badges restyled: the **LFG/LFM** badge is now a solid filled pill (the key info),
  the content tag is an outlined chip with a small status dot — clearer visual hierarchy.
- **Create a listing by picking the dungeon/raid from a list**, not by typing a numeric
  activity ID. The list is built live from `C_LFGList` (real names, correct IDs for the
  client) and scrolls; it refreshes when the activity data loads.

**0.7.0** - Streamlined, smarter filtering (far fewer controls):

- **No more tab/chip rows.** Create & Settings became small header icons (✚ / ⚙),
  freeing the entire mode bar; Browse is the default view.
- **Category is now one compact dropdown** (All · Dungeons · Raids · Guild · Quests · Other)
  instead of six chips — custom glass dropdown, no Blizzard widgets.
- **Role-need filter**: clickable T/H/D pips (same visual language as the cards) — e.g. a
  healer clicks **H** to see only groups that still need a healer.
- **LFG/LFM** is a small inline toggle. The result list gained ~40% more height.

**0.6.0** - Navigation/structure overhaul (less clutter, clearer mental model):

- **3 modes** — *Browse · Create · Settings* — replace the old 4-tab bar that mixed
  content views (Dungeons/Raids) with actions (Create/Settings).
- **One unified Category filter** (All · Dungeons · Raids · Guild · Quests · Other)
  replaces both the Dungeons/Raids tabs and the separate content-type row, so there is
  now a single, obvious way to filter content.
- The toolbar drops the duplicate "Raids" search button for one **Refresh** button that
  queries the game finder for whatever category is selected (both, when "All").
- Filter rows are explicitly labeled **Category** and **Looking for**; redundant
  "Players/Groups" toggles were removed from Settings (the Browse filter covers them).

**0.5.0** - "Dark glass" interface redesign:

- Translucent, layered glass panels with a frosted header, soft sheen and hairline
  edges — no default WoW widgets.
- **Rich result cards** instead of flat rows: a content-type tag (Dungeon/Raid/HC/…),
  an LFG/LFM badge, a class-colored leader name with class, a group-fill bar (e.g. `24/25`),
  a freshness dot + time, and **role-need pips** (T/H/D, color-coded) showing exactly
  what each group is looking for, plus the raw message.
- Filters and tabs now show a clear filled "selected" state; the result count is a glass
  pill; cards lift on hover; and an empty-state message replaces the blank void.

**0.4.0** - Reliability pass for the TBC Anniversary (2.5.x) client:

- Auto-joins the `LookingForGroup` channel on login so chat scanning actually works.
- `Who` button now uses `C_FriendList.SendWho` (the bare `SendWho` global is gone on 2.5.x).
- Native listing creation uses the correct positional `C_LFGList.CreateListing`, no longer
  wipes the title field, and reports real success/failure. An activity **Pick** dropdown
  removes the need to know raw numeric activity IDs.
- Real raid sizes from the activity info (25-man raids are no longer mis-flagged as full),
  class-colored leader names, leader dedup across chat + group finder, and tool results that
  expire instead of lingering.
- Smarter classification: heroic 5-mans stay under Dungeons, and stray `q`/`h`/`more`
  substrings no longer hide legitimate listings.
- Escape closes the window, it stays clamped on-screen, the search box has a placeholder and
  is debounced, and all 10 locales are fully translated.

**0.3.0** - Multi-language support with 10 locales ✨

