# Magely on WoW: Forever — what is measured, and what is not

Nobody working on the port has a Mage on Forever. This file keeps the line between what Magely
relies on that **has been measured in game** (by Priestly, on the same library) and what is
**Mage-specific and has not**, so the first tester knows what to look at and nobody mistakes an
assumption for a measurement.

Client: WoW: Forever 1.60.1, builds 69913, 69977 and - from 2026-09-25 - **70009**
(`MEASURED_ON_BUILD` is still 69977; see "Build 70009" below).

## Shared with Priestly — taken as measured

Magely is a thin host on LibGroupBuffs-1.0, and everything below runs the same code Priestly runs
in game. The measurements are in `C:\Projects\Priestly\docs\FOREVER-PROBE.md` and
`C:\Projects\References\PORTING-TBC-TO-FOREVER.md`; do not re-derive them here.

| Behaviour | Where it was measured |
|---|---|
| Secure buttons cast on self and a party member, both buttons, registering both mouse edges | Priestly probe §1 |
| ...and still cast during a fight, on the wiring made before it | Priestly probe §14 (measured 2026-09-22; §1's "still to confirm" predates it) |
| Auras are unreadable in combat for every unit; the engine's cache and `?` state | Priestly probe §9 |
| A frame parenting secure buttons cannot be hidden or moved in combat; the window defers | Priestly probe §13 |
| `GetUnitName(unit, false)` for surnames; GUID-keyed identity | Priestly probe §4 |
| `GetInstanceInfo()` returns the continent outdoors; `instanceType` gates | Priestly probe §5, §12 |
| `C_Spell.GetSpellInfo(id)` resolves unlearned spells by ID, not by name | Priestly probe §8 |
| SavedVariables never load back, per-character included - **on 69913 and 69977. On 70009 the owner reports they now load**; being re-measured in Priestly | Priestly probe §11; PORTING §1 |
| Registering `COMBAT_LOG_EVENT_UNFILTERED` is a forbidden action | PORTING §3 (Stakeout probe) |
| The options panel's templates exist | Priestly probe §3 |

## Mage-specific — NOT measured

Each of these is an assumption until someone checks it on a Mage. Record the answer here, with the
build and date, when it is measured.

| Assumption | Why it matters | How to check |
|---|---|---|
| Arcane Intellect **1459**, Amplify Magic **1008** and Dampen Magic **604** are reported "known" by `C_SpellBook.IsSpellKnown` once learned. (That the IDs **resolve**, with the right names, is measured - below.) | A known spell reported unknown is a row that never appears | Learn the spell; its row appears |
| Arcane Brilliance **23028** reaches the whole raid, as Forever's Prayers do | Left-click and the per-subgroup rows (LibGroupBuffs #19) | Level 56 |
| Arcane Powder **17020** is Brilliance's reagent (the item exists - below) | The footer | Level 56 |
| Arcane Power **12042**, Combustion **11129**, Ice Barrier **11426** are learned as the 31-point talents (the IDs resolve - below) | The spec look | Level 40+ |
| Durations. The seeds are Intellect 30 min and Amplify / Dampen 10 min (the TBC build's values). Brilliance shares Intellect's row, so until its own duration is learned its timer is scaled against 30 min too; it is expected to last 60 min. The engine learns every real value per spell name from the first live aura | Timer colours before the first live read | Watch a bar go down; `/dump MagelyDB.learnedDurations` |
| A wired unit token handed to another player by a roster change mid-fight | A click can land on the wrong member until combat ends (known, unfixable - Priestly probe §14) | Reshuffle a raid in combat |
| The instance names beyond the ones Priestly has stood in | Instance mode silently never fires on a misspelt key | Enter the instance with a mode on "by instance"; Magely reports an unknown name |

## Measured by `Tools/MagelyProbe`

Build **70009**, 2026-09-25, on a non-Mage (so every spell reads `known=false`, as it should).

| Question | Answer |
|---|---|
| Do the IDs resolve by ID? | **Yes, all of them, with the right names**: 1459 Arcane Intellect, 23028 Arcane Brilliance, 1008 Amplify Magic, 604 Dampen Magic, 12042 Arcane Power, 11129 Combustion, 11426 Ice Barrier, 29166 Innervate, 10060 Power Infusion. Item 17020 (Arcane Powder) has icon **133848**. |
| Can a plain frame anchored under a protected one be changed **in combat**? | **Yes, all of it.** SetHeight, re-anchor, Hide and Show all took effect with no blocked event. The control - Hide on the frame parenting a secure button - was refused: `ADDON_ACTION_BLOCKED: Frame:Hide() blamed on MagelyProbe`. So a cooldown pane under the window can live its own life in combat (LibGroupBuffs #24). |
| `C_SpecializationInfo.GetTalentInfo` | **Answers nothing in any shape**, for your own talents and an inspected target alike: `{ specializationIndex, talentIndex }` **throws** *"query.tier must be specified"*; `{ tier, column }` (tiers 1-10 x columns 1-4) and `{ specializationIndex, tier, column }` (3 trees x 10 x 4) give **0 hits, 0 errors**. So Power Infusion cannot be found through it. The probe now asks whether Retail's traits system holds the talents instead (`C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo`). Second run, 2026-09-25. |
| Other players' casts: `UNIT_SPELLCAST_SUCCEEDED` | **Registers. One inconclusive negative:** the watcher ran from 00:45:05 to the report at 00:45:13 - about eight seconds - while, the owner reports, their second account was casting; the report said *"casts: none seen yet"*, i.e. no event reached the handler for any unit (it counts every unit, `player` included). Not established: that the second account was in the party, how many casts landed in that window. (This run was first misread here as "nobody cast"; the owner corrected it.) Needs a controlled repeat before anything is ruled out. |
| Inspection | **Works.** `CanInspect(target)` true, `NotifyInspect` sent, and `INSPECT_READY` arrived for the requested target a second later. `GetInspectSpecialization(target)` answered **1486** - no Retail spec ID; the probe now names it with `GetSpecializationInfoForSpecID`, the documented form. |
| A WHISPER to a surnamed name | **Accepted and echoed.** `C_ChatInfo.SendChatMessage(..., "WHISPER", nil, "Karuzo Elegia")` was accepted, chat showed the outgoing `[W To] [Karuzo Elegia]` line, and there was no "No player named" error (which a wrong name did produce on the first run). **Delivery was not confirmed** by the recipient. |

Not answered yet, and why:
- **Group casts, controlled**: with the second account **confirmed in your party**, `/mprobe cast on`,
  have it cast several spells over a minute - out of combat and in a fight - then `/mprobe report`.
  Cast yourself during the same run, as the control: `player` casts are counted too.
- **If others' casts turn out not to be delivered**, the pane's remaining source is each provider
  announcing its own Innervate / Power Infusion by addon message (the TBC pane's `MAGELYCD` sync,
  minus the combat log) - which needs a player's own casts to be observable, the control above.
- **Raid members' casts**: not tried.
- **Whisper to a surname** and **inspection**: answered on the second run, above.
- **Talents**: `GetTalentInfo` answers nothing; whether the traits system does is the next run.

## Build 70009

The client moved to **70009**, and the owner reports SavedVariables now load back. Two constants in
`MagelyConfig.lua` are about exactly that, and follow Priestly's fix rather than being guessed here:

- `MEASURED_ON_BUILD` is 69977, so every real login on 70009 shows the "tested on another build"
  notice until it is bumped - which needs the notes re-checked on 70009 (a new API dump).
- `SV_BROKEN_ON_BUILD` is 69977, so on 70009 the load check is free to announce that settings
  came back - which is now the right answer.

## The cooldown pane's questions - `Tools/MagelyProbe`

The pane (slice 5, LibGroupBuffs #24) waits on these. **Most need no Mage and no level 40**: any
character in a group can answer them. Deploy with `pwsh Tools/deploy.ps1 -ProbeOnly`, then:

| Command | Answers | Needs |
|---|---|---|
| `/mprobe spells` | Do the Mage / Druid / Priest IDs above resolve, and which does this character know? Arcane Powder's icon | Any character |
| `/mprobe cast on`, then `/mprobe report` | Does `UNIT_SPELLCAST_SUCCEEDED` fire for party and raid members, and is `spellID` readable, **secret** or throwing, in and out of combat? | A group; people casting anything |
| `/mprobe pane build`, fight, `/mprobe pane test`, `/mprobe pane remove` | Can a **plain** frame anchored under a protected one be resized, re-anchored, hidden and shown in combat? (The protected stand-in's own hide is the control, and should be refused.) | Any character, a fight |
| `/mprobe whisper First Surname` | Is a WHISPER to a surnamed name accepted through `C_ChatInfo.SendChatMessage`? Ask the recipient whether it arrived | A second character |
| `/mprobe inspect` (with a target) | What `C_SpecializationInfo.GetTalentInfo` returns, for yourself and an inspected unit, by specialization/talent index, by tier/column, and by specialization with tier/column | A target with talents |

Results print in chat and land in `MagelyProbeDB` on disk after `/reload`. Record the answers here,
with the build and the date.

## In-game checklist for testers

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
