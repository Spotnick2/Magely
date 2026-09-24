# Magely Changelog

## v1.0.0 - 2026-09-24

**Magely now runs on World of Warcraft: Forever.** This is the first release for the Forever client
(1.60.1). Playing TBC Classic Anniversary? Stay on **v0.1**, the last release for that client; it
remains available on CurseForge.

### Known issues
- **Your settings reset every time you reload.** This is a client bug that affects every addon:
  Forever saves addon settings and never reads them back. It has been reported to Blizzard, and
  Magely says so in chat once a game update fixes it.
- **Not yet played on a mage by its author.** Everything is covered by automated tests, and the
  same engine and window run Priestly in game today, but this build has not been through a
  hands-on pass. If something looks wrong, please report it, and type `/console scriptErrors 1` to
  see errors the client otherwise hides.
- **The cooldown request pane is gone for now.** The TBC version could track Innervate and Power
  Infusion and whisper a request. Forever does not let addons read the combat log, which the pane
  relied on, and neither spell exists at the current level cap. It is planned to come back once it
  can be built on something that works here.

### Changed
- **Built on the same engine and window as Priestly and Wildly** (the LibGroupBuffs library), so
  fixes found in any of them reach all three. The window keeps Magely's look: the cyan border, and
  a header, title and icon that follow your talents.
- **Left-click works before you know Arcane Brilliance.** It buffs whoever needs Arcane Intellect,
  and switches to Brilliance on its own once you learn it. Nothing is ever wired to a spell you do
  not have.
- **Amplify Magic and Dampen Magic each keep their own setting** - always, when someone in the
  group has it, or by instance - and both rows can show at once.
- **The instance lists are Forever's.** The TBC dungeons and raids are gone; the list now has
  Forever's instances, including its new ones, which start unchecked until someone knows what they
  need. Entering a dungeon or raid the list does not know says so once, if you use "by instance".
- **Your spec is read from your talents' spells** (Arcane Power, Combustion, Ice Barrier). At the
  current level cap nobody has them yet, so everyone gets the plain Mage look for now.
- **Arcane Powder appears in the footer once you know Arcane Brilliance**, not before.

### Added
- **During a fight, hovering a row lists who still needs the buff,** and says how current that is,
  because the game hides buffs in combat.
- **Buff state that cannot be read shows as `?`** instead of a false "missing".
- **Options:** lock the window's position, turn the click hints off, and choose which side the
  per-member popover opens on.
- **`/magely pos`** explains where the window is and why.

### Fixed
- **Clicks work whether your client acts on key down or key up.**
- **Closing the window in a fight** now says it closes when combat ends, and does, instead of
  failing silently.
- **Magely stays out of the way on other classes:** no window, no options page, no chat messages.

## v0.1 - 2026-05-16

The TBC Anniversary release.

### Added
- Initial **Magely** addon implementation for TBC Anniversary.
- Mage-only addon/class gating.
- Core buff tracking for **Arcane Intellect / Arcane Brilliance**.
- Optional **Amplify Magic** and **Dampen Magic** tracking with encounter-mode options.
- Optional cooldown request pane for **Innervate** and **Power Infusion**.
- Whisper request prefix: `[Magely]:`.
- Configurable cooldown whisper spam protection.

### Changed
- Cooldown pane anchored below main frame and aligned to main frame width.
- Cooldown request action moved to cooldown spell icon click.
- Deployment convention uses `## Version: dev` in deployed TOC.
