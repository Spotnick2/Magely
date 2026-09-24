# Magely on WoW: Forever — what is measured, and what is not

Nobody working on the port has a Mage on Forever. This file keeps the line between what Magely
relies on that **has been measured in game** (by Priestly, on the same library) and what is
**Mage-specific and has not**, so the first tester knows what to look at and nobody mistakes an
assumption for a measurement.

Client: WoW: Forever 1.60.1, builds 69913 and 69977 (`MEASURED_ON_BUILD` is 69977).

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
| SavedVariables never load back, per-character included | Priestly probe §11; PORTING §1 |
| Registering `COMBAT_LOG_EVENT_UNFILTERED` is a forbidden action | PORTING §3 (Stakeout probe) |
| The options panel's templates exist | Priestly probe §3 |

## Mage-specific — NOT measured

Each of these is an assumption until someone checks it on a Mage. Record the answer here, with the
build and date, when it is measured.

| Assumption | Why it matters | How to check |
|---|---|---|
| Arcane Intellect is spell **1459**, Amplify Magic **1008**, Dampen Magic **604** (rank 1) and they resolve and are "known" through `C_SpellBook.IsSpellKnown` | A wrong ID is a row that never appears | Learn the spell; its row appears. `/dump C_Spell.GetSpellInfo(1459)` |
| Arcane Brilliance is **23028** and reaches the whole raid, as Forever's Prayers do | Left-click and the per-subgroup rows (LibGroupBuffs #19) | Level 56 |
| Arcane Powder is item **17020** and is Brilliance's reagent | The footer | Level 56 |
| Arcane Power **12042**, Combustion **11129**, Ice Barrier **11426** are the 31-point talents | The spec look | Level 40+ |
| Durations. The seeds are Intellect 30 min and Amplify / Dampen 10 min (the TBC build's values). Brilliance shares Intellect's row, so until its own duration is learned its timer is scaled against 30 min too; it is expected to last 60 min. The engine learns every real value per spell name from the first live aura | Timer colours before the first live read | Watch a bar go down; `/dump MagelyDB.learnedDurations` |
| A wired unit token handed to another player by a roster change mid-fight | A click can land on the wrong member until combat ends (known, unfixable - Priestly probe §14) | Reshuffle a raid in combat |
| The instance names beyond the ones Priestly has stood in | Instance mode silently never fires on a misspelt key | Enter the instance with a mode on "by instance"; Magely reports an unknown name |

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
