# Magely Forever

**Magely** is a lightweight buff manager for mages, inspired by **PallyPower**. It tracks
*Arcane Intellect* (and *Arcane Brilliance*), *Amplify Magic* and *Dampen Magic* across your party
or raid and lets you rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

![Magely buff window in a group](https://raw.githubusercontent.com/Spotnick2/Magely/main/docs/screenshots/magely-01.png)

*Earlier-build screenshot. The cooldown-request pane shown here is not in the current Forever
version; the buff window has since gained additional controls.*

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
* **Window controls.** Minimize without closing, lock its position, adjust opacity and choose
  which side the member popover opens on.

---

## Usage

Use the header **-** to minimize to the title bar and **+** to restore. Requests in
combat wait until combat ends. Minimized state lasts for this session; `/reload`
or logging in expands the window again. **X** closes the window.

In the popover, **? beside the class icon** means spell range is unknown.
**? instead of a timer** means the buff cannot be read and there is no cached reading.

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
Settings and window position persist between sessions.

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat, so
Magely keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### GitHub and Wago

Download from [GitHub Releases](https://github.com/Spotnick2/Magely/releases/latest)
or [Wago Addons](https://addons.wago.io/addons/magely). Both include the required libraries.
The GitHub release includes `release.json` for compatible addon managers.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Magely/
```

---

## Good to know

**Pet eligibility:** hunter and warlock pets are excluded from Arcane Intellect
tracking and targeting. Amplify and Dampen keep their existing pet eligibility.

Magely uses single-target Arcane Intellect until you learn Arcane Brilliance. It learns buff
durations from live auras and relearns them when the client build changes. The cooldown-request
pane in the screenshot is from the older Anniversary edition and is not available in Forever.
If a Forever instance is missing from the Amplify/Dampen list, please report its in-game name.

Forever can hide aura data during combat. Magely uses its last observation and shows `?` if no
reliable reading is available. Window movement, closing and minimize/restore requests made during
combat take effect after combat ends.

---

## Feedback

Open an [issue on GitHub](https://github.com/Spotnick2/Magely/issues) or leave a comment on
CurseForge. Include the addon version,
client build, locale, and whether the problem happened in combat. Typing
`/console scriptErrors 1` in game shows Lua errors that the client otherwise hides.

## Author

**Spotnick**

## License

MIT - see [LICENSE](LICENSE).
