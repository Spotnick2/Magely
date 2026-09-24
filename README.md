# Magely Forever

**Magely** is a lightweight buff manager for mages, inspired by **PallyPower**. It tracks
*Arcane Intellect* (and *Arcane Brilliance*), *Amplify Magic* and *Dampen Magic* across your party
or raid and lets you rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

> **Playing TBC Classic Anniversary?** Install **v0.1**, the last release for that client. It stays
> available on CurseForge for the Anniversary game version. The Anniversary line is no longer
> being developed.

Magely shares its engine and window with **Priestly** and **Wildly** through the
[LibGroupBuffs](https://github.com/Spotnick2/LibGroupBuffs) library, so a fix to one reaches all
three.

---

## Features

* **One row per group, per buff**, colour-coded by how many people are missing it, with the lowest
  remaining timer on the bar.
* **One-click buffing.** Left-click casts Arcane Brilliance, right-click buffs the first person
  missing Arcane Intellect. No targeting.
* **Works before you have Arcane Brilliance.** While you only know Arcane Intellect, left-click
  simply buffs whoever needs it. Nothing is wired to a spell you do not have.
* **Amplify and Dampen Magic when they matter.** Each has its own setting: always, when someone in
  the group already has it, or by instance - with a list of Forever's dungeons and raids to tick.
  Both rows can show at once.
* **Per-member popover.** Mouse over a row for the full list with range indicators and per-person
  click casting.
* **Group-aware.** It follows party and raid changes, subgroups, and pets.
* **Reagent tracking.** The Arcane Powder count, once you know Arcane Brilliance.
* **Your spec's look.** The header, title and icon follow Arcane, Fire or Frost.

---

## Usage

```
/magely          toggle the window
/magely show     force open
/magely hide     close
/magely config   open the options panel
/magely reset    reset the window position
/magely pos      why the window is where it is
/magely help     full command and click reference
```

The window opens on its own when you join a group. On other classes Magely shows nothing and
says nothing, unless you type `/magely`, which answers with one line.

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat, so
Magely keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Magely/
```

---

## Beta notes

Forever is in beta and the level cap is still low, so some of Magely is waiting for content to
catch up:

* **Arcane Brilliance is not learnable yet** (it comes at level 56). The Intellect row works
  single-target until it is, and switches over automatically once you learn it. Arcane Powder
  appears in the footer at the same time.
* **The spec look needs a 31-point talent**, which nobody can reach yet, so everyone gets the plain
  Mage look for now.
* **The cooldown request pane is not in this version.** Forever does not let addons read the
  combat log, which it relied on, and Innervate and Power Infusion are above the level cap. It is
  planned to return.
* **Forever's own instances are not catalogued yet**, so they start unchecked in the instance
  list. If you use "by instance" and enter one the list does not know at all, Magely says so -
  please report the name.
* **Mage buff durations have not been measured on Forever yet**, and Forever's durations have
  already turned out to differ from both TBC and Vanilla for other classes. Magely learns the real
  duration from live buffs rather than assuming one, and forgets what it learned whenever the
  client build changes.
* **Your settings reset every time you reload.** This is a client bug and it affects every addon:
  Forever writes addon settings to disk correctly and then never reads them back at login. So the
  window position, the lock and every option start fresh each session. No addon can work around
  it. It waits on Blizzard's fix, which has been reported, and Magely says so in chat once a game
  update fixes it.

---

## Feedback

Open an issue on GitHub or leave a comment on CurseForge. This first Forever release has not been
played by its author on a mage yet, so reports of anything odd are especially welcome. Typing
`/console scriptErrors 1` in game shows Lua errors that the client otherwise hides.

## Author

**Spotnick**

## License

MIT - see [LICENSE](LICENSE).
