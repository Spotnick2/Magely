# Magely on WoW: Forever — what is measured, and what is not

This file keeps the line between what Magely relies on that **has been measured in game** - by
Priestly on the same library, by the probe, or on a Mage - and what is **Mage-specific and has not**,
so a tester knows what to look at and nobody mistakes an assumption for a measurement. v1.0.0
shipped before anyone on the port had a Mage; the first pass on one is recorded below.

Client: WoW: Forever 1.60.1, builds 69913, 69977, 70009 (from 2026-09-25), 70205, 70338 and
**70959**, built Nov 13 (`MEASURED_ON_BUILD` is 70959; see "Build 70959" below).

## Shared with Priestly — taken as measured

Magely is a thin host on LibGroupBuffs-1.0, and everything below runs the same code Priestly runs
in game. The measurements are in `C:\Projects\WoW\Priestly\docs\FOREVER-PROBE.md` and
`C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`; do not re-derive them here.

| Behaviour | Where it was measured |
|---|---|
| Secure buttons cast on self and a party member, both buttons, registering both mouse edges | Priestly probe §1 |
| ...and still cast during a fight, on the wiring made before it | Priestly probe §14 (measured 2026-09-22; §1's "still to confirm" predates it) |
| Auras are unreadable in combat for every unit; the engine's cache and `?` state | Priestly probe §9 |
| A frame parenting secure buttons cannot be hidden or moved in combat; the window defers | Priestly probe §13 |
| `GetUnitName(unit, false)` for surnames; GUID-keyed identity | Priestly probe §4 |
| `GetInstanceInfo()` returns the continent outdoors; `instanceType` gates | Priestly probe §5, §12 |
| `C_Spell.GetSpellInfo(id)` resolves unlearned spells by ID, not by name | Priestly probe §8 |
| SavedVariables never loaded back, per-character included, on 69913 and 69977. **70009 fixed it** | Priestly probe §11 |
| **Re-measured on 70009** (2026-09-25): aura secrecy unchanged (`combat=true secret=true` in a fight); secure buttons build, fire on both edges, and one cast per click on all three bench buttons; `loadstring_untainted` still absent. `UnitName("player")` now splits like every unit; `GetInstanceInfo` returns eleven values | Spotnick2/priestly#60 |
| Registering `COMBAT_LOG_EVENT_UNFILTERED` is a forbidden action | PORTING §3 (Stakeout probe) |
| The options panel's templates exist | Priestly probe §3 |

## Measured on a Mage

First in-game pass, 2026-09-27, build **70009**, a low-level Mage in a party of two:

| Question | Answer |
|---|---|
| Is Arcane Intellect **1459** reported known once learned? | **Yes**: its row appears. |
| What are the clicks wired to without Arcane Brilliance? | **Arcane Intellect on both buttons**, as the click hint shows, naming the member it is aimed at: "Left Arcane Intellect on Karuzo Memphisto / Right Arcane Intellect on Karuzo Memphisto". That is the wiring; a click being performed and landing is still on the checklist. |
| How long does Arcane Intellect last? | **At least 59:56** - the remaining times read 59:48 and 59:56, so it is longer than Vanilla's 30 minutes, but the total is not measured (it could be more than 60). The row's seed is now 3600, provisionally. `/dump MagelyDB.learnedDurations` after a live read shows the duration the aura itself reports. |
| Names in the popover | **Full names with surnames** (Karuzo Memphisto, Karuzo Macphisto), class-coloured, with the range marker green in range. |
| The window | Visible in a party, headed "Magely dev" (a deployed build), with the plain Mage look (no 31-point talent yet) and the Intellect row green with its timer. Whether grouping opened it by itself is not shown by a still. |

## Mage-specific — NOT measured

Each of these is an assumption until someone checks it on a Mage. Record the answer here, with the
build and date, when it is measured.

| Assumption | Why it matters | How to check |
|---|---|---|
| Amplify Magic **1008** and Dampen Magic **604** are reported "known" once learned (Arcane Intellect's is measured - above; that the IDs **resolve** is measured - below) | A known spell reported unknown is a row that never appears | Learn the spell (levels 18 and 12); its row appears in "always" mode |
| Arcane Brilliance **23028** reaches the whole raid, as Forever's Prayers do | Left-click and the per-subgroup rows (LibGroupBuffs #19) | Level 56 |
| Arcane Powder **17020** is Brilliance's reagent (the item exists - below) | The footer | Level 56 |
| Arcane Power **12042**, Combustion **11129**, Ice Barrier **11426** are learned as the 31-point talents (the IDs resolve - below) | The spec look | Level 40+ |
| Durations: Amplify and Dampen seeded 10 min (the TBC build's); Arcane Intellect seeded 60 min, provisionally - at least 59:56 is measured, above; Brilliance shares that seed until its own is learned. The engine learns every real value per spell name from the first live aura | Timer colours before the first live read | Watch a bar go down; `/dump MagelyDB.learnedDurations` |
| A wired unit token handed to another player by a roster change mid-fight | A click can land on the wrong member until combat ends (known, unfixable - Priestly probe §14) | Reshuffle a raid in combat |
| The instance names beyond the ones Priestly has stood in | Instance mode silently never fires on a misspelt key | Enter the instance with a mode on "by instance"; Magely reports an unknown name |

## Measured by `Tools/MagelyProbe`

The probe is retired (#75): the cooldown pane it measured for is being built in Buffy, not here.
These tables stay as client facts, and as Buffy's starting point. The probe's code and its command
reference are in git history (`Tools/MagelyProbe` and this file's "The cooldown pane's questions"
at `825abae`).

### Build 70959, 2026-11-18: the controlled repeat

On a Mage, with the owner's second account (a Priest) in the party, through the procedures
`/fp steps mp casts` and `/fp steps mp talents` (all checks PASS; `ForeverProbe.lua`
`steps.records`, `MagelyProbe.lua` log, runs #427-#428). Bugsy recorded no Lua error.

| Question | Answer |
|---|---|
| Do other players' casts arrive? | **Yes.** `UNIT_SPELLCAST_SUCCEEDED` fires for a party member, out of combat and in a fight: 3 party casts seen (2 out of combat, 1 in combat), within 41 s of being asked. The 70009 "none seen" was the unconfirmed party, as suspected. |
| Can the pane tell **which** spell? | **Not from that event.** A party member's `spellID` is a **secret value** on all 3 casts, out of combat as well as in it (`party/nocombat/SECRET` x2, `party/combat/SECRET` x1). Your **own** casts are readable out of combat (`player/nocombat/readable` x4); your own casts **in combat** were not seen in this run. So the event can say *that* a party member cast, never *what*: identifying Innervate / Power Infusion has to come from the caster, by addon message - if a player's own cast is readable in combat too. |
| Where do talents live? | **In Retail's traits system.** `C_ClassTalents.GetActiveConfigID()` = 650752, and `C_Traits.GetConfigInfo` names it `Mage`, type 4, **1 tree**. `C_SpecializationInfo.GetTalentInfo` still answers nothing in any shape, for yourself or an inspected player: `{ specializationIndex, talentIndex }` throws "query.tier must be specified" on every query, the other two shapes find 0. |
| Inspection | **Works**, as on 70009: `CanInspect`, `NotifyInspect`, then `INSPECT_READY` for the requested target within a second. `GetInspectSpecialization` answered **1487**, which `GetSpecializationInfoForSpecID` names **Priest (role DAMAGER)**: a class-level ID, as 1486 was on 70009. |

### Build 70009, 2026-09-25

Build **70009**, 2026-09-25, on a non-Mage (so every spell reads `known=false`, as it should).

| Question | Answer |
|---|---|
| Do the IDs resolve by ID? | **Yes, all of them, with the right names**: 1459 Arcane Intellect, 23028 Arcane Brilliance, 1008 Amplify Magic, 604 Dampen Magic, 12042 Arcane Power, 11129 Combustion, 11426 Ice Barrier, 29166 Innervate, 10060 Power Infusion. Item 17020 (Arcane Powder) has icon **133848**. |
| Can a plain frame anchored under a protected one be changed **in combat**? | **Yes, all of it.** SetHeight, re-anchor, Hide and Show all took effect with no blocked event. The control - Hide on the frame parenting a secure button - was refused: `ADDON_ACTION_BLOCKED: Frame:Hide() blamed on MagelyProbe`. So a cooldown pane under the window can live its own life in combat (LibGroupBuffs #24). |
| `C_SpecializationInfo.GetTalentInfo` | **Answers nothing in any shape**, for your own talents and an inspected target alike: `{ specializationIndex, talentIndex }` **throws** *"query.tier must be specified"*; `{ tier, column }` (tiers 1-10 x columns 1-4) and `{ specializationIndex, tier, column }` (3 trees x 10 x 4) give **0 hits, 0 errors**. So Power Infusion cannot be found through it. The probe now asks whether Retail's traits system holds the talents instead (`C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo`). Second run, 2026-09-25. |
| Other players' casts: `UNIT_SPELLCAST_SUCCEEDED` | **Registers. One inconclusive negative:** the watcher ran from 00:45:05 to the report at 00:45:13 - about eight seconds - while, the owner reports, their second account was casting; the report said *"casts: none seen yet"*, i.e. no event reached the handler for any unit (it counts every unit, `player` included). Not established: that the second account was in the party, how many casts landed in that window. (This run was first misread here as "nobody cast"; the owner corrected it.) Needs a controlled repeat before anything is ruled out. |
| Inspection | **Works.** `CanInspect(target)` true, `NotifyInspect` sent, and `INSPECT_READY` arrived for the requested target a second later. `GetInspectSpecialization(target)` answered **1486** - no Retail spec ID; the probe now names it with `GetSpecializationInfoForSpecID`, the documented form. |
| A WHISPER to a surnamed name | **Accepted and echoed.** `C_ChatInfo.SendChatMessage(..., "WHISPER", nil, "Karuzo Elegia")` was accepted, chat showed the outgoing `[W To] [Karuzo Elegia]` line, and there was no "No player named" error (which a wrong name did produce on the first run). **Delivery was not confirmed** by the recipient. |

Left open when the probe was retired (for whoever builds the pane):
- **Your own casts in combat**: not seen. A pane fed by each provider's addon messages needs the
  provider's own `spellID` readable in a fight.
- **Raid members' casts**: not tried.
- **Talents**: whether the traits tree's nodes say which talents are taken, for yourself and for an
  inspected player; the probe never walked the tree.

## Build 70959

`MEASURED_ON_BUILD` moved to **70959** on 2026-11-18 (#67). What that rests on:

- **API dump**: 70959's declarations against 70338's (`Compare-Dumps.ps1`): functions +28 -9,
  events +9 -3, tables +9 -6, widget methods unchanged (7530). Nothing Magely, LibGroupBuffs r34
  or LibGlass r11 names was removed or changed; the changes are mail and secure transfer, title
  icons, transmog, game-rules presets, `PARTY_INVITE_REQUEST` and `PLAYER_LEVEL_UP` gaining a
  field, and `GroupBuffItem` gaining `displaySpellID` (only `C_CooldownViewer` returns it).
- **In game**: Magely v1.1.0 ran for a Mage on 70959 - its load-check marker in that character's
  `MagelyDB` recorded build 70959 on 2026-11-17, and the marker is written only on the Mage path
  (`IsMage()` gates the config's event handler). No buff was learned in that session
  (`learnedDurations` is empty), so no cast was seen, and no checklist pass on this build is
  recorded.
- **Owner's confirmation**: the owner confirmed 70959 as Magely's measured build on 2026-11-18
  (#69), on the evidence above.
- `GetBuildInfo()` on 70959 reports `Nov 13 2026` (ForeverProbe's log). The shared test stub at
  LibGroupBuffs r34 still models 70338, which `tests/test_stub.lua` pins; that moves with the
  library, not with this constant.
- `/pprobe` in a fight and the full-exit SavedVariables check were last run in full on 70009.

## Build 70338

`MEASURED_ON_BUILD` moved to **70338** on 2026-10-11. What that rests on:

- **API dump**: 70338's declarations against 70205's (Priestly's `docs/FOREVER-PROBE.md`, "70338
  against 70205"). Nothing Magely, LibGroupBuffs or LibGlass calls was removed or changed
  signature; the changes are voice chat, Discord, LFG structures and the `ComboFrame_*` globals.
- **In game**: tested by the owner on 70338 (2026-10-11).
- `/pprobe` in a fight and the full-exit SavedVariables check were last run in full on 70009.

## Build 70205

`MEASURED_ON_BUILD` moved to **70205** on 2026-10-04 (#35). What that rests on:

- **API dump**: 70205's declarations against 70009's (Spotnick2/priestly#78). Nothing Magely,
  the library or the probe calls was removed or changed signature; `C_PlayerInfo.GetName` lost
  `optional` on its return, and only the probe calls it, inside `try`.
- **In game**: v1.0.4 (LibGroupBuffs r27, LibGlass r1) on 70205 - works, no errors (owner,
  2026-10-04).
- **Not re-run on 70205**, still as measured on 70009: aura secrecy in a fight (`/pprobe`), and
  SavedVariables loading back after a **full exit**. Run them and record the result here.

## Build 70009

The client moved to **70009** and SavedVariables load back. Priestly re-measured it
(Spotnick2/priestly#60), and Magely followed:

- `MEASURED_ON_BUILD` is **70009**, so the "tested on another build" notice is silent there.
- The settings check needs no build constant since LibGroupBuffs r14: it announces when a marker
  saved on a **different** build comes back - which can only have been read after a restart - and
  says nothing to one from the running build (a relog). On the first 70009 login after 69977 it
  announces the fix once; a latch keeps later patches quiet, including r12's (r15, LibGroupBuffs
  #31).

## The release check on 70959 (2026-11-18)

The owner ran `/fp steps mp check` on a Mage (Magely v1.1.0 deployed with LibGroupBuffs r36 and
LibGlass r13), to the end, run #438 (`ForeverProbe.lua` `steps.records["MagelyProbe/check"]`, the
`MagelyProbe.lua` log). Bugsy recorded no Lua error that session, and none ever from Magely, its
libraries or the probe. It was the procedure's **rev 1**, before #78's review: its row waits forced
a rebuild themselves, and its click waits took any spell. So:

| Item | Result |
|---|---|
| Versions, the spell report | PASS: r36, LibGlass r13; nothing unresolved, nothing of unknown origin |
| "always" | Intellect, Amplify and Dampen rows |
| "detected" | The rows came and went with Amplify and Dampen on a member. Read after the probe's own rebuild, so not on its own proof that Magely's aura refresh does it; **the owner saw the same in normal play** after the check, with both modes back on "detected" (Amplify and Dampen rows beside Buffy's, for the same member) |
| "by instance", outdoors | no Amplify or Dampen row, as it should |
| "by instance" inside a dungeon, a hand-closed window staying closed on zoning in | **not run** (skipped) |
| Left-click on yourself, right-click on a party member, a click in combat | each cast Arcane Intellect (1461) and landed where meant (owner); timers counted in combat and nobody showed MISS for a never-seen member (owner) |
| Footer | no Arcane Powder, correctly: Brilliance is not known at this level |
| Options panel | every control works (owner) |
| Settings put back | PASS (only the six keys rev 1 saved; rev 3 saves them all) |

Still unmeasured on a Mage: instance mode inside a dungeon, the close surviving a zone-in,
Brilliance and its reagent (level 56), raids. Rev 3 of the procedure only observes Magely's
window and only counts a buff cast as a click; a re-run of it is the clean record.

## In-game checklist for testers

The guided form of this list is `/fp steps mp check` (`pwsh Tools\deploy.ps1 -Probe`, then
`/reload`): it reads the versions and the spell report, sets each Amplify / Dampen mode and checks
the rows, waits for your clicks in and out of combat, checks the footer, and puts your settings
back. What it can't see (the options panel, a window closed by hand staying closed) it asks.

```
/console scriptErrors 1
/reload
```

- AddOn list: Magely enabled **and not flagged out of date**.
- On any other class: no window, no options page, and `/magely` answers with one line.
- On a Mage: `/magely help | config | show | hide | reset | pos`; drag the frame; lock it.
- Rows appear for what the Mage actually knows; no Brilliance wiring before it is known.
- Amplify Magic (level 18) and Dampen Magic (level 12): each mode - always, detected, by instance -
  alone and with both rows at once.
- Instance mode inside a listed dungeon (Ragefire Chasm, Ruins of Lordaeron); a window closed by
  hand stays closed when zoning in.
- Left and right click cast, out of combat and in combat, on yourself and a party member.
- Enter combat: timers count down from the cache; a member never seen shows `?`, not `MISS`.
- Roster churn: invite and leave, reshuffle subgroups, pets.
- The options panel: every checkbox, both mode groups, the slider, the Instances tab.
