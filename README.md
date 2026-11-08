# PartyLens

**A group radar for WoW: Forever.**

PartyLens listens to the LookingForGroup channel and to other PartyLens users, and shows every group
that is forming in one panel: what it runs, which roles it still needs, how fresh it is, and who leads
it. Whisper or invite with one click.

Built for **WoW: Forever** (interface 16001). No dependencies.
The TBC Anniversary edition stays on the 0.33 line.

---

## Groups

- **The radar.** Every group lights up as a blip; new ones pop in as they appear.
- **What each group still needs.** Tank, healer and dps pips, how full the group is, and the activity
  (vanilla dungeons and raids plus the Forever additions: City of Dalaran, Ruins of Lordaeron,
  Excavation Site: Wetlands, The Hall of Thanes, Manor Mistmantle).
- **Filters.** The roles you play, LFM or LFG, activity, text search, open groups only, spam hidden.
- **One-click actions.** Whisper (a message built from your roles), Invite (for players looking for a
  group), Who (fills in level and class for people without the addon), Block.

## Announce

Build your post from the activity, the roles you are missing and a comment. One click sends it to
LookingForGroup and publishes it to the PartyLens network, where other users see it on their radar.

**Autopilot** suggests players from the radar who fill the roles you are missing. You confirm each
invite and whisper; it never sends anything on its own.

## Layer

PartyLens reads your layer from nearby creatures and lists every layer it hears, zone by zone: how many
players are there, how many beacons are on duty, groups forming, and what changed lately (a beacon went
on duty, someone was brought over, the layer filled up). It shows layers, never names.

**Go here** asks a beacon on that layer to invite you; if it can't, the next one is asked by itself.
Accept the invite, then click the game's prompt to switch layers (or wait about five minutes and the game
moves you). Leave the group with a click when you are done. Layers on Forever belong to each zone, so a
beacon brings you over inside the zone you are both in.

**Be a beacon.** It is on by default and works while you are in the open world, out of combat, not away
and not in someone else's group. When a player asks for your layer, a prompt drops from the top of the
screen (window open or not) with Invite and Decline, and a key binding invites the next one. The game
needs a click for every invite. Each player who arrives on your layer is one hop; hops earn ranks, from
Spark to Legend. Turn it off in Settings.

## Summon

See who in your group still needs a summon and announce it to the group with one click.

---

## How the network works

WoW: Forever refuses addon messages on SAY and YELL, and custom channels deliver nothing. PartyLens rides
on **ChehulNet**, the mesh it shares with GuildOS and Lodestar: guild, group, and a hidden member list
that lets users whisper a few others of the faction, who pass a listing on at most twice. Nothing is
sent from inside an instance.

The game requires a real click for invites, visible chat and /who, so every one of those comes from a
button you press.

## Commands

| Command | What it does |
| --- | --- |
| `/pl` or `/partylens` | Open or close the window |
| `/pl announce` | Open Announce |
| `/pl layer` | Open Layer |
| `/pl help` | List the commands |

## Install

Put the `PartyLens` folder in `Interface/AddOns/` and restart the game (or `/reload`).

## Languages

The interface is in English and Portuguese; other languages translate part of it and fall back to
English. LFG posts are understood in English, Portuguese, German, French and Spanish.

---

## Created by Chehul

PartyLens is made by **Chehul (danielcosta42)**. If it saves you time, you can support
development:

**[Donate via PayPal](https://www.paypal.com/donate/?business=daniel.cfdutra13@gmail.com&currency_code=USD)**

Source, issues and full changelog on **[GitHub](https://github.com/danielcosta42/PartyLens)**.
