# Magely Changelog

## Unreleased

### Changed
- **The buff window's glass now comes from LibGlass**, a small library shared by the Glass addons
  and included in the download - nothing extra to install. The window's rim is a little softer;
  nothing else changes on screen.
- **The window explains itself when it can't close yet.** If it has nothing left to show during
  a fight (your group emptied, or you untick "show when solo"), it now says it will close once
  combat ends, instead of staying up without a word.
- Needs LibGroupBuffs r27 and LibGlass r1, both included in the download.

## v1.0.3 - 2026-10-04

### Fixed
- **No more "this version was tested on game build …" message at login.** It appeared every time
  the game client updated, even though Magely kept working fine. It was a reminder meant for the
  addon's developer, not for players, and now only shows in development copies. If something
  does misbehave after a game update, please still report it.

## v1.0.2 - 2026-09-29

### Fixed
- **The window comes back when it has something to show again.** If it had closed itself because
  there was nothing to display — every buff untracked, or the spells not learned yet — then
  learning one, or respeccing, left it shut until something else woke it. An Amplify or Dampen
  landing still reopens it the way it did, and still does not try to while you are in combat,
  where those auras cannot be read at all.
- **Being invited reopens a window you had closed** — but a roster arriving in the moments after
  you log in no longer counts as an invitation. That was decided on a five-second timer from
  login, which could be wrong in both directions: a roster update can arrive before the timer is
  even set, and a slow world load can push a perfectly ordinary catch-up past five seconds. It
  asks whether it has seen the roster yet instead.

### Under the hood
- **Magely now shares one copy of the rules for when the window opens** with Priestly and Wildly,
  instead of each addon carrying its own. Both fixes above are cases where those copies had
  drifted apart: found in one addon, fixed there, and left standing in the other two.
- **Much less work per refresh in a raid.** Checking whether somebody is missing a buff means
  reading their auras, and that was happening once per buff per person. Each person is now read
  once and every buff answered from that, and "show when detected" shares the same read instead of
  scanning the group all over again. Nothing looks different; there is simply less of it happening
  forty times a minute.
- Needs LibGroupBuffs r25, included in the download.

## v1.0.1 - 2026-09-27

### Changed
- **A new look.** The window is drawn in glass: a translucent, softly lit panel with rounded
  corners instead of the flat Blizzard dialog box, and every buff bar filled the same way.
- **It is easier to read at a glance.** The rows are taller and the spell icons bigger, each one
  in a rounded tile of its own, and the text is a cleaner typeface with a shadow behind it so it
  stays legible wherever the window sits. Group separators are centred across the window rather
  than tucked against one edge, and the close button matches the rest of it instead of being
  Blizzard's gold disc.
- **The window is a little wider and taller** because of that. If you keep it tucked against
  something, you may want to nudge it once; where you put it is remembered as always.
- **Tooltips no longer land on top of the window** they are describing, and are drawn slightly
  smaller so they suit it.

  Nothing about how it *works* has changed: same rows, same clicks, same colours telling you who
  is missing what.

## v1.0.0 - 2026-09-24

**Magely now runs on World of Warcraft: Forever.** This is the first release for the Forever client
(1.60.1). Playing TBC Classic Anniversary? Stay on **v0.1**, the last release for that client; it
remains available on CurseForge.

### Known issues
- **Your settings reset every time you reload.** This is a client bug that affects every addon:
  Forever saves addon settings and never reads them back. It has been reported to Blizzard, and
  Magely says so in chat once a game update fixes it.
- **Not yet played on a mage by its author.** The code has an offline test suite, and the same
  engine and window run Priestly in game today, but this build has not been through a hands-on
  pass: whether the Mage spells are recognised, how long they last on Forever, and the instance
  names are still to be confirmed in game. If something looks wrong, please report it, and type
  `/console scriptErrors 1` to see errors the client otherwise hides.
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
- **Magely stays out of the way on other classes:** no window, no options page and no chat
  messages - `/magely` answers with one line saying what Magely is for.

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
