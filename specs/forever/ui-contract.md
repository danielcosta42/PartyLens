# PartyLens Forever: core ↔ UI contract

The UI is built from this file only. Everything here is implemented by the core (`Core.lua` and `Modules/*.lua`;
the UI lives in `UI/` and `Media/`). `tools/contract.lua` fails CI when a method, event or settings path named
here goes missing from the core. The UI never reads module
globals (`PartyLens_Utils`, `PartyLens_LayerNet`, ...) or `PartyLens.<module state>`: only the methods,
fields and events below. If something is missing, ask for it to be added here; do not reach into the core.

## 0. Loading

- The UI files load **after `Core.lua`** (the owner appends them to the TOC). At UI file load time
  `_G.PartyLens` exists with its methods and event bus, but `PartyLens.db` does **not** yet (SavedVariables
  arrive with `ADDON_LOADED`). Subscribe at file scope; read data in a `READY` handler or later.
- The UI registers itself as `PartyLens.UI = { Toggle = function(self) ... end, Open = function(self, pageKey, context) ... end }`.
  The core calls only these two, always with `:` (method) syntax and only if `PartyLens.UI` exists:
  - `PartyLens.UI:Toggle()` from `/pl`, `/partylens`, the key binding and `PartyLens:Toggle()`.
  - `PartyLens.UI:Open(pageKey, context)` with `pageKey` one of `"groups"`, `"announce"`, `"layer"`, `"summon"`,
    `"network"`, `"settings"`. `context` is `nil` except:
    - `"announce"` from the inter-addon API: `{ source = "api", label = "<quest title>" }` (the draft is already filled).
    - `"layer"` from the inter-addon API: `{ source = "api", mapID = n, zoneUID = n }` (highlight nodes on it).
- The minimap button and `AddonCompartment` are the UI's (call `PartyLens:Toggle()`).
- Tests: every `tools/*.lua` is a harness CI runs with `luajit tools/<x>.lua` from the repo root, **except
  files ending in `stub.lua`**, which are libraries (`tools/wowstub.lua` is the core's simulated client; a UI
  frame stub should be named e.g. `tools/uistub.lua`). A harness exits 1 on the first failure.

## 1. Event bus

```lua
PartyLens:On(event, fn)    -- fn(...) receives the event's arguments (no event name, no self)
PartyLens:Off(event, fn)
PartyLens:Fire(event, ...) -- core use; a handler error goes to geterrorhandler() and does not stop the others
```

| Event | Arguments | Fired when |
|---|---|---|
| `READY` | — | DB loaded, modules started (once per session, from `ADDON_LOADED`) |
| `ENTRIES_CHANGED` | — | any entry added/updated/removed/expired (expiry is checked every 30 s), a /who result filled level/class, block/unblock, a `roles.*` or `filters.*` setting changed |
| `ENTRY_ADDED` | `entry, needsMe` | a person appears on the radar for the first time this session (`needsMe` = `entry.needsMe`) |
| `LISTING_CHANGED` | `listing` (same shape as `GetListing()`) | draft edited, listing started/stopped/updated, roster changed while active, a post went out |
| `SUGGESTIONS_CHANGED` | `suggestions` (same as `GetSuggestions()`) | the ranked list changed (checked every 5 s while a listing is active, and on entry/roster changes) |
| `LAYER_CHANGED` | `layer` (same as `GetLayer()`) | my detected layer changed, after a loading screen, and on a zone change (then usually with `zoneUID = nil` until an NPC is seen) |
| `LAYER_NODES_CHANGED` | — | a node's presence/layer arrived or expired, or a layer has news |
| `LAYER_REQUEST_RECEIVED` | `req` (an inbound request, see §6) | someone asked to come to my layer (show the beacon prompt with Invite/Decline, window open or not) |
| `BEACON_CHANGED` | `status` (same as `GetBeacon()`) | the beacon setting or my duty changed (away, combat, group, layer, instance) |
| `BEACON_SERVED` | `status` + `rankUp` (bool), `name` (who arrived) | someone I invited arrived on my layer (their client says so): one more hop (once per person per day) |
| `LAYER_REQUESTS_CHANGED` | — | an inbound request or my own request changed state |
| `SUMMON_CHANGED` | — | roster changed, a member was marked summoned |
| `ROSTER_CHANGED` | — | `GROUP_ROSTER_UPDATE` (already secret-guarded) |
| `LFG_CHANNEL_CHANGED` | `channel` (same as `LFGChannel()`, or nil) | the LFG channel the radar listens on was found, joined, left or renumbered |
| `NETWORK_CHANGED` | — | a ChehulNet HELLO arrived (coalesced, at most once per second). The directory size has no event: poll `GetNetworkStatus()` while the Network page is open |
| `SETTINGS_CHANGED` | `path, value` | `PartyLens:Set(path, value)` |
| `NOTICE` | `text` | user-facing feedback from an action, already localized (e.g. `L.WHISPER_SENT`, `L.LFG_JOIN_ATTEMPT`, `L.NOTICE_POST_COOLDOWN`, `L.NOTICE_LAYER_INCOMING`). The core prints it to chat itself only when `PartyLens.UI` is absent. |

## 2. Settings (`PartyLens.db`, SavedVariable `PartyLensDB`, `schemaVersion = 100`)

Any older save (schemaVersion < 100) is wiped on load. Read freely; write core keys only with
`PartyLens:Set(path, value)` (dotted path, fires `SETTINGS_CHANGED`). `Set` returns `false` and changes nothing
for an unknown path, a value of another type than the default's, a table value, or the keys that have their own
calls (`listing.*` → `SetListing`, `blacklist` → `Block`/`Unblock`, `beacon.*` → `SetBeacon`, `alertDismissed`,
`schemaVersion`).
The UI may write `db.ui`, `db.minimap`, `db.animations` directly.

| Path | Default | Meaning |
|---|---|---|
| `roles.tank` / `roles.heal` / `roles.dps` | `false` / `false` / `true` | the roles I play (role template; there is no spec detection) |
| `comment` | `""` | free text, `{comment}` in the whisper template |
| `whisperTemplate` | `""` | the whisper to a group leader; `""` = `L.WHISPER_TEMPLATE`. Tokens: `{name}` (their first name) `{class} {level} {role}` (mine) `{activity} {comment}`. A player looking for a group gets `L.WHISPER_RECRUIT` instead (an offer to join my group) |
| `filters.roles.tank/heal/dps` | all `false` | any true: keep only entries whose `roles` include one of them (entries with empty `roles` stay) |
| `filters.type` | `"all"` | `"all"` \| `"lfg"` \| `"lfm"` |
| `filters.activityType` | `"all"` | `"all"` \| `"dungeon"` \| `"raid"` \| `"quest"` \| `"guild"` \| `"other"` |
| `filters.activity` | `""` | `""` or an activity key (§4) |
| `filters.query` | `""` | space-separated words, all must appear in message/activity/name |
| `filters.onlyOpen` | `true` | hide full groups (`entry.open == false`) |
| `filters.hideSpam` | `true` | hide `entry.isSpam` |
| `listing.type` | `"lfm"` | announce draft: `"lfm"` (I lead, need people) \| `"lfg"` (I look for a group) |
| `listing.activity` | `""` | activity key, or `""` to use `listing.label` |
| `listing.label` | `""` | free activity text (quests); used when `listing.activity == ""` |
| `listing.want.tank/heal/dps` | `1` / `1` / `3` | lfm: wanted totals **including me** |
| `listing.comment` | `""` | appended to the post and sent with the listing (max 80 chars, `|` removed) |
| `joinLFGChannel` | `true` | join `LookingForGroup` at login when missing (the radar needs it) |
| `alertOnMatch` | `false` | UI-owned behavior: play a sound on `ENTRY_ADDED` with `needsMe` while the window is closed |
| `animations` | `true` | UI-owned |
| `minimap.hide` / `minimap.angle` | `false` / `225` | UI-owned |
| `ui` | `{}` | free table for the UI (window position, last page, ...) |
| `beacon.on` / `beacon.hops` / `beacon.today` | `true` / `0` / `0` | read only (write with `SetBeacon`): beacon setting (opt-out), people brought over in all, today |
| `rares.notify` / `rares.share` | `true` / `true` | a prompt for rares alive in my zone; the rares I see told to the network |
| `summonNet.offer` | `true` | a warlock of level 20+ gets the realm's summon asks and can offer (section 7) |
| `blacklist` | `{}` | `[key] = name`; use `Block`/`Unblock`, not direct writes |

## 3. Radar entries

`PartyLens:GetEntries()` returns a fresh array, filtered by `db.filters` and blacklist, sorted (fellow
PartyLens users, then `needsMe`, then freshest). One row per person. Fields (read-only):

| Field | Type | Meaning |
|---|---|---|
| `id` | string | stable row id (= `key`) |
| `name` | string | "First Surname" as the game gave it: display it, it is also the whisper/invite target |
| `key` | string | lowercased name |
| `type` | `"lfg"`\|`"lfm"` | lfg = a player looking for a group; lfm = a group looking for members |
| `source` | `"chat"`\|`"net"` | last update came from the LFG channel or from a PartyLens network listing |
| `isAddonUser` | bool | runs PartyLens (network listing, or a signed `[PartyLens]:` chat post) |
| `classFile` | string\|nil | `"WARRIOR"`, ... (chat GUID, listing, or a /who) |
| `level` | number\|nil | from a listing or a /who |
| `activityKey` | string\|nil | key into `GetActivities()`, nil when not recognized |
| `activity` | string | display name: the activity, a quest label, or `L.ACTIVITY_OTHER` |
| `activityType` | string | `"dungeon"` \| `"raid"` \| `"quest"` \| `"guild"` \| `"other"` |
| `roles` | set | `{ tank = true, ... }`: lfm = roles still needed, lfg = roles offered. Empty = unspecified |
| `needsMe` | bool | lfm whose `roles` include one of `db.roles` |
| `message` | string | the chat line (sign stripped), or the listing summary + comment |
| `filled`, `max` | number\|nil | group size and target (network lfm only) |
| `comp` | table\|nil | `{ t, h, d, tMax, hMax, dMax }` filled/target per role (network lfm only) |
| `open` | bool | false when `filled >= max` |
| `isSpam` | bool | gold/boost/RMT heuristics |
| `timestamp` | number | `time()` of the last update; `firstSeen` = first time this session |
| `mapID`, `zoneUID` | number\|nil | the sender's layer (network only) |
| `sameLayer` | bool | that layer is exactly mine |
| `contacted` | `"whisper"`\|`"invite"`\|nil | what I already did to this person this session |

Entries expire: chat 30 min after the last line, network 3 min after the last heartbeat (a stopped listing
goes at once). Own lines and own listings are never entries.

| Call | Click? | Returns / does |
|---|---|---|
| `PartyLens:GetEntries()` | | array (above) |
| `PartyLens:GetCounts()` | | `{ total, visible, needsMe, listed }`: `total` = rows stored, `visible` = `#GetEntries()`, `needsMe` = visible rows with `needsMe`, `listed` = visible rows from PartyLens users (their listing or a signed post; they sort first, the channel's lines after them). Blocked, spam and filtered-out rows never count |
| `PartyLens:LFGChannel()` | | `{ id = n, name = "LookingForGroup" }` (the joined channel the radar listens on, in the client's language: e.g. `ProcurandoGrupo` on ptBR), or nil when none is joined. Changes come with `LFG_CHANNEL_CHANGED` |
| `PartyLens:WhisperText(entry)` | | the whisper that `Whisper` would send (preview) |
| `PartyLens:Whisper(entry)` | **yes** | sends it (`C_ChatInfo.SendChatMessage` WHISPER to `entry.name`). `true` or `false, reason` (`"empty"`) |
| `PartyLens:OpenWhisper(entry)` | yes | opens the chat edit box on `entry.name` with the text inserted, for editing |
| `PartyLens:Invite(entry)` | **yes** | `C_PartyInfo.InviteUnit(entry.name)`. `false, reason`: `"cannot_invite"` (not leader), `"in_group"` |
| `PartyLens:Who(entry)` | **yes** | /who for the exact name; the answer fills `level`/`classFile` later (`ENTRIES_CHANGED`). `false, "throttled"` within 3 s of the last one (also sends a `NOTICE`) |
| `PartyLens:Block(entry)` / `PartyLens:Unblock(key)` | | blacklist; fires `ENTRIES_CHANGED` |
| `PartyLens:GetBlocked()` | | array of `{ key, name }` |
| `PartyLens:ClearBlocked()` | | |
| `PartyLens:ClassColor(classFile)` | | `r, g, b, "ffRRGGBB"` (white for unknown) |

"Click? yes" means: call it only from a button's `OnClick` (a hardware event). Calling it from a timer, an
event or an animation callback is blocked by the game. **bold** = the game requires it; "yes" = no hardware
need, but it is a user action and must stay one.

## 4. Activities

`PartyLens:GetActivities()` → array sorted dungeons (by level) then raids:
`{ key, name, type = "dungeon"|"raid", minLevel, maxLevel, size, isNew, instanceID }`.
`minLevel`/`maxLevel` are nil for the new Forever dungeons (no reliable data yet); `isNew` marks them
(City of Dalaran, Ruins of Lordaeron, Excavation Site: Wetlands, The Hall of Thanes, Manor Mistmantle,
The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace).
`PartyLens:GetActivity(key)` → one record or nil.

## 5. Announce (listing), post and Autopilot

`PartyLens:GetListing()` →
```lua
{ active = bool, type = "lfm"|"lfg", activity = key|"", label = string, name = "display activity",
  activityType = "dungeon"|"raid"|"quest"|"other",
  want = {tank,heal,dps}, have = {tank,heal,dps}, missing = {tank,heal,dps}, size = n, -- lfm (have = current group)
  roles = {tank=bool,heal=bool,dps=bool},  -- lfg: = db.roles
  comment = string, startedAt = time|nil, lastSent = time|nil, lastPost = time|nil, seq = n }
```

| Call | Click? | Does |
|---|---|---|
| `PartyLens:SetListing(fields)` | | merges `fields` (`type`, `activity`, `label`, `want = {...}`, `comment`) into the draft; resends at once when active |
| `PartyLens:StartListing(fields?)` | yes | optional merge, then publishes on the network now and every 60 s (GUILD + group + ChehulNet directory). Nothing is sent from instances or chat lockdown |
| `PartyLens:StopListing()` | yes | stops and tells those who hear me directly (GUILD, group, the directory members I whisper) to drop it. A stop is never relayed: copies relayed further age out within 3 min |
| `PartyLens:DefaultWant(activityKey)` | | `{tank,heal,dps}` for the activity size (5: 1/1/3, 10: 2/3/5, 20: 2/4/14, 40: 4/8/28) |
| `PartyLens:BuildPost()` | | the visible LFG line the post would send (without the `[PartyLens]: ` sign) |
| `PartyLens:PostLFG()` | **yes** | sends the line to the LFG channel (`LFGChannel()`) and starts/refreshes the listing. `false, reason`: `"no_channel"` (none joined: it is joined when the client can name it, by the server's own channel list or, on an English client, as LookingForGroup; try again after `LFG_CHANNEL_CHANGED`), `"cooldown"` (< 15 s since the last post), `"empty"` |

Autopilot is **suggestion only**: nothing it computes is ever sent by itself.

`PartyLens:GetSuggestions()` → array (best first; empty without an active listing):
`{ entry = <entry>, action = "invite"|"whisper", role = "tank"|"heal"|"dps"|nil, reason = "role"|"open", score = n }`.
lfm listing: lfg players who fill a missing role (`action = "invite"`; `Whisper` also works).
lfg listing: lfm groups that need one of my roles (`action = "whisper"`).
Act with `PartyLens:Invite(s.entry)` / `PartyLens:Whisper(s.entry)` (clicks); `PartyLens:DismissSuggestion(entry)`
hides it until the listing stops. Contacted entries stay listed with `entry.contacted` set.

## 6. Layer

Rows are layers, never people: the page shows no names except to the beacon, for the people who ask it.

| Call | Click? | Returns / does |
|---|---|---|
| `PartyLens:GetLayer()` | | `{ mapID, zoneUID|nil, ordinal|nil, count, since|nil, inInstance }` (`count` = layers known on the map). `zoneUID` nil until a nearby NPC was targeted, moused over or shown with a nameplate on this map. `ordinal` is this client's own numbering of the layers it saw itself on the map (1 = lowest zoneUID); network presences never add to it, so `count` = layers I saw |
| `PartyLens:GetLayers()` | | one row per layer heard, my zone first, then zones by population, inside a zone by zoneUID: `{ mapID, zoneUID, ordinal|nil, mine, sameMap, population, zonePopulation, beacons, meBeacon, groups, canRequest, news }`. `population` = ChehulNet nodes heard there (me included on mine); `beacons` = PartyLens beacons on duty there (me included when on duty); `groups` = network lfm listings that carry that layer. `ordinal`: on my map my own numbering (nil for a layer only the network reports), elsewhere the order among the layers heard on that map. `canRequest` = my map, not mine, a beacon on duty. `news` = newest first, at most 4, 30 min: `{ t, kind, n }`, `kind` = `"new"` (layer heard for the first time) \| `"beacon_on"` (`n` beacons now) \| `"beacon_off"` \| `"hop"` (beacons there brought `n` people over) \| `"group"` (`n` groups started forming) \| `"grow"` / `"shrink"` (population up/down by `n` over 5 to 10 min) |
| `PartyLens:GetLayerNodes()` | | the raw nodes behind `GetLayers()` (network status only; the UI shows no names): `{ name, key, mapID, zoneUID, source = "pl"|"cn", pl, beacon, hops, sameMap, sameLayer, ago }` |
| `PartyLens:RequestLayer(layer)` | yes | `layer` = a row of `GetLayers()` (or `{ mapID, zoneUID }`): whispers the request to that layer's beacon with the most hops (one that let an ask run out in the last 30 min goes last); on its no (`N`) or 40 s of silence, to the next one, by itself. A late invite from any beacon already asked still serves it. `false, reason`: `"other_map"`, `"same_layer"`, `"no_beacon"`, `"pending"` (one at a time), `"cannot_send"` (instance or chat lockdown) |
| `PartyLens:GetMyLayerRequest()` | | nil or `{ name, mapID, targetZone, state, t, stateAt, askedAt, asked }` (`name` = the beacon asked now, internal: the UI says "a beacon"), `state` = `"sent"` (`askedAt` = when the current beacon was asked, 40 s each) → `"accepted"` (it clicked invite; 120 s to join) → `"served"` (I joined its group; the game moves me when I click its switch prompt, or by itself after about 5 min) → `"hopped"` (my layer is now that one; the beacon is told, which counts its hop) → `"done"` (I left its group); or `"expired"` (no beacon took it) / `"cancelled"` (cancelled, or I left its group before arriving) |
| `PartyLens:CancelLayerRequest()` | | |
| `PartyLens:GetBeacon()` | | `{ on, available, why|nil, hops, today, rank, rankAt, nextAt|nil, queue }`. `why` when not taking requests: `"off"`, `"instance"`, `"no_layer"`, `"combat"` (the network is not told: a fight is short), `"afk"`, `"grouped"` (in a group I did not form, or not leader), `"group_full"`. `rank` 1..6 by hops (thresholds 0, 3, 10, 25, 60, 150; `rankAt` this rank's, `nextAt` the next one's, nil at the top). `queue` = open requests |
| `PartyLens:SetBeacon(on)` | | the beacon setting (opt-out); fires `BEACON_CHANGED` and tells the network |
| `PartyLens:GetLayerRequests()` | | inbound, newest first: `{ name, key, mapID, fromZone, targetZone, t, seq, stateAt, state = "open"|"invited"|"served"|"arrived"|"declined" }` (`seq` = arrival order; `served` = in my group, `arrived` = on my layer, which counts the hop). Only while taking requests (otherwise the asker gets a no); open ones get a no and go when I stop taking them (combat, away, a group of my own). One per person: a repeat never prompts again and never reopens it. `open` goes after 90 s, `invited` after 150 s unless they joined (then `served`, `arrived` once on my layer, until they leave), `declined` is held 10 min (that person gets a no meanwhile). At most 10: a new one evicts the oldest not in my group |
| `PartyLens:ServeLayerRequest(req)` | **yes** | invites the requester and tells them. `false, reason`: `"cannot_invite"`, `"group_full"`, `"not_on_layer"` (I moved), `"off_duty"`, `"gone"` (declined or expired) |
| `PartyLens:ServeNextLayerRequest()` | **yes** | the same for the oldest open request (also the key binding "Beacon: invite the next layer request"); `false, "gone"` with none |
| `PartyLens:DeclineLayerRequest(req)` | | tells them no |
| `PartyLens:CanUndoLayer()` | | true after a served hop (either side) while still grouped |
| `PartyLens:UndoLayerGroup()` | **yes** | beacon side: uninvites the hopper (or leaves when not leader); requester side: leaves the group. States follow the roster: the served request goes (beacon) or stays `"hopped"` with `CanUndoLayer()` false (requester) on the next `LAYER_REQUESTS_CHANGED`/`ROSTER_CHANGED` |
| `PartyLens:GetRares(mapID?)` | | rare sightings still fresh (15 min), alive first then newest; `mapID`'s only when given: `{ key, mapID, zoneUID, npcID, name, kind = "rare"|"rareelite"|"worldboss", alive, x|nil, y|nil (the reporter's spot, thousandths), seen (server time), ago, mine (I saw it), onMyMap, here (my layer), ordinal|nil, canGo, canMark }`. `canGo` = my map, another layer, a beacon on duty there |
| `PartyLens:GoToRare(sighting)` | yes | `RequestLayer` for the rare's layer; its reasons, plus `"gone"` |
| `PartyLens:MarkRare(sighting)` | yes | the game's map pin (`C_Map.SetUserWaypoint`, tracked) at the reporter's spot. `false, reason`: `"gone"`, `"no_position"`, `"cannot_mark"` |

Rows of `GetLayers()` also carry `rares` = the rares alive on that layer (`GetRares` entries). A layer of my map known
only by a rare alive on it is a row too. Events: `RARES_CHANGED` (any sighting in or out), `RARE_SPOTTED(view)` (a
rare alive on my map heard from the network: once per rare and layer per 10 min, never one I saw myself, only with
`rares.notify`).

## 7. Summon (warlock)

`PartyLens:GetSummon()` → `{ inGroup = bool, members = { { name, classFile, isPlayer, inRange, isWarlock, summoned } },
needed = { names }, warlocks = { names } }` (`needed` = not in range, not me, not marked). `inRange` = within 40 yd
by squared distance, or, where the client cannot measure it (instances), whether the unit is visible at all
(`UnitInRange` only returns secrets on 12.x). Marks are forgotten when the group ends.
`PartyLens:MarkSummoned(name, bool)` (fires `SUMMON_CHANGED`).
`PartyLens:AnnounceSummon("all"|"next")` — **click**: posts the list (or the next name, or "everyone is here") to
party/raid chat; `false, "not_in_group"` alone.

Summons across the realm (`summonNet.offer`, default `true`, matters only to warlocks of level 20 and up):

| Call | Click? | Returns / does |
|---|---|---|
| `PartyLens:AskSummon(dest)` | yes | asks the realm's warlocks for a summon to `dest` (free text, 40 chars, no `|`), again every 2 min while open, 10 min at most. `false, reason`: `"empty"`, `"pending"` (one at a time), `"cannot_send"` |
| `PartyLens:CancelSummonAsk()` | | takes it back (tells the network) |
| `PartyLens:GetSummonAsk()` | | nil or `{ id, dest, t, state = "open"|"cancelled"|"expired", offers = { { name, key, zone, t, state = "offered"|"invited" } } }` (offers newest first, 5 min each) |
| `PartyLens:AcceptSummonOffer(offer)` | **yes** | invites that warlock. `false, reason`: `"gone"`, `"cannot_invite"`, `"group_full"`, `"in_group"` |
| `PartyLens:IsSummoner()` | | a warlock of level 20+ with `summonNet.offer` |
| `PartyLens:GetSummonRequests()` | | a summoner's asks heard, newest first, open or offered: `{ rkey, id, name, key, level, classFile|nil, dest, seen, t, state }`; empty for anyone else |
| `PartyLens:OfferSummon(req)` | yes | whispers the offer (with my zone) to the asker. `false, reason`: `"gone"` (one offer per ask), `"not_summoner"`, `"cannot_send"` |
| `PartyLens:IgnoreSummonRequest(req)` | | off my list |

Events: `SUMMON_REQUEST(req)` (a summoner, an ask heard: 3 prompts a minute at most, none inside an instance),
`SUMMON_OFFER(offer)` (the asker, a warlock's first offer for my open ask), and `SUMMON_CHANGED` on any change.
The UI's prompts from the top of the screen share one spot (`UI:WhenPromptFree`): a beacon's layer request goes
first, a rare or a summon waits until the spot is free.

## 8. Network

`PartyLens:GetNetworkStatus()` →
```lua
{ nodes = n,        -- ChehulNet peers heard (any Chehul addon) within 10 min
  plNodes = n,      -- PartyLens users known: tagged pl in a HELLO, or known to the board (heard or named lately)
  directory = n,    -- members in the ChehulNet directory channel (realm-wide reach)
  listingsHeard = n, layerNodes = n,
  buses = { guild = bool, group = bool, realm = bool }, -- usable now
  canSend = bool, inInstance = bool, lockdown = bool,
  dead = { "SAY", "YELL" },                              -- buses the game refused this session
  stats = { ok, fail, recv, refused, dirSent, realmQueued, realmSent, realmDropped },
  meshVersion = n, cnVersion = n }
```
`PartyLens:GetPeers()` → array `{ name, addons = { pl = true, gos = true, ... }, classFile, level, mapID, zoneUID, ago }`.

## 9. Misc

- `PartyLens.VERSION` (string), `PartyLens:IsReady()`.
- `PartyLens:Toggle()`, `PartyLens:Open(pageKey, context)`: forward to `PartyLens.UI` when present (without a UI,
  `Toggle` prints the slash help).
- Slash: `/pl`, `/partylens` (toggle), `/pl announce`, `/pl layer`, `/pl help`.
- Localization: `local L = PartyLens.L`; `L["KEY"]` (missing → enUS → the key itself) and `L("KEY", ...)`
  (`string.format`). The UI adds its own strings with `PartyLens:AddStrings(locale, { KEY = "..." })` from its
  own files, at least `enUS` and `ptBR` (other locales fall back to enUS); a key the core already has is never
  replaced, so prefix the UI's keys (e.g. `UI_`). Core keys the UI may reuse:
  `ROLE_TANK ROLE_HEAL ROLE_DPS TYPE_LFG TYPE_LFM ACTIVITY_DUNGEON ACTIVITY_RAID ACTIVITY_QUEST ACTIVITY_GUILD
  ACTIVITY_OTHER ACTIVITY_ANY LEVEL_SHORT BINDING_TOGGLE HELP` and the `NOTICE_*` texts.
