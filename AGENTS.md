# Magely Agent Instructions

Trust these instructions. Search the codebase only when information here is incomplete, stale, or
appears incorrect.

## Review policy

Use `$wow-addon-review` as the shared source of truth for review routing, committed-diff scope,
client/API evidence handling, validation, finding format, and merge-readiness verdicts.

Repository-specific additions:

- Post every pull-request review and follow-up review on the PR, then link the posted review in the
  final response.
- Reviews run from `C:\Projects\Magely`. PR numbers overlap with Priestly, Wildly and
  LibGroupBuffs, so name the repository explicitly when reviewing from elsewhere
  (`gh pr diff 2 -R Spotnick2/Magely`).
- Match `MEASURED_ON_BUILD` in `MagelyConfig.lua` (once ported) to
  `C:/Projects/References/forever-api-<version>.<build>.md`. Runtime measurements for this client
  live in `C:\Projects\Priestly\docs\FOREVER-PROBE.md` (and Magely's own `docs/` once it has
  measured something Mage-specific); addon-agnostic Forever findings live in
  `C:/Projects/References/PORTING-TBC-TO-FOREVER.md`.

## What This Repository Is

Magely Forever is a World of Warcraft addon for **WoW: Forever 1.60.1** (Interface `16001`). It is
PallyPower-style Mage buff management for **Arcane Intellect / Arcane Brilliance**, **Amplify
Magic** and **Dampen Magic** across party and raid members.

**TBC Classic Anniversary is no longer supported.** The last TBC code is the history before the
Forever port (Interface 20505). Do not add flavor branching for it.

Forever is *Vanilla content running on Blizzard's Retail (Mainline) codebase*: content assumptions
are Vanilla, API assumptions are Retail. Read `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`
before touching an unfamiliar API.

Magely is one of three thin hosts on **[LibGroupBuffs-1.0](https://github.com/Spotnick2/LibGroupBuffs)**
(with Priestly and Wildly). **Wildly is the closest model** (`C:\Projects\Wildly`: `Wildly.lua`,
`WildlyConfig.lua`, `tests/`), and **Priestly the first**: its instance list and its
detect / instance visibility modes are what Amplify and Dampen follow. When in doubt about how a
host should do something, do what they do, and copy their instructions rather than reinventing them.

There is no build system, compiler or package manager. CurseForge's packager handles releases.

## Port status

The port lands in slices, one issue and PR each:

1. **Foundation** — TOC, `MagelyCompat.lua`, `.pkgmeta` externals, tests, deploy, CI, this file.
2. **Config** — `MagelyConfig.lua` on the library's Settings write path, Priestly's panel shape,
   one Forever instance list with Amplify and Dampen flags.
3. **Host** — `Magely.lua` becomes DEFS + engine + window + spec look + Arcane Powder footer +
   events; the hand-built TBC window, and the cooldown pane with it, is deleted, not ported.
4. **In-game pass and v1.0.0.**
5. **The cooldown pane**, after v1.0 (see below).

Slices 1 to 3 are done: the addon is deployable, and the TBC window is gone. **Do not tag before
slice 4.**

**Nobody working on this port has a Mage on Forever.** The in-game pass (slice 4) is handed to
players and testers, as Wildly's was, and the release notes say no Magely build has been verified
in game. What Magely shares with Priestly - the engine, the window, the settings path, the combat
rules - is taken as measured by Priestly. What is Mage-specific stays listed as **unmeasured**
until someone measures it: whether spell IDs 1459 / 23028 / 1008 / 604 and the spec spells
resolve, the Amplify and Dampen durations, and the instance names beyond the ones Priestly checked.

`H.NOT_YET_PORTED` in `tests/harness.lua` is empty. It stays, with the check in `test_bridge`, until
this section is deleted. Update this section as slices land, and delete it when the port is done.

### The cooldown pane is not in v1.0

The TBC addon had an optional second pane tracking Innervate and Power Infusion providers, with a
click to whisper a request. None of its data sources work as written on this client:

- **Registering `COMBAT_LOG_EVENT_UNFILTERED` is a forbidden action** (measured by Stakeout on
  69977; PORTING doc section 3). Observed cooldowns came from the combat log.
- **`GetTalentInfo(tab, idx, inspect, unit)` is gone.** The dump has
  `C_SpecializationInfo.GetTalentInfo(query)` and `GetTalentInfoByID`; whether either returns
  Vanilla talent data for an inspected unit is unmeasured.
- **Innervate is a baseline Druid spell (level 40), not a talent**, so inspecting for it never
  worked on TBC either - that is what the old `innervateDebug` option papered over. Power Infusion
  is a talent. Neither exists at the current level cap of 20, so nothing can be tested in game.

It comes back as its own slice, on the library rather than beside it: a LibGroupBuffs issue first
(a companion pane needs more than `onLayout` / `onVisibility` - there is no tick hook, `onLayout`
never fires in combat), a probe of `UNIT_SPELLCAST_SUCCEEDED` for group units and of inspection,
then `MagelyCooldowns.lua`, keyed by GUID and anchored to `ui:MainFrame()`. **Never fork the
window for it.**

## Repository Layout

- `Magely.toc` — addon manifest: interface version, saved variables, load order.
- `MagelyCompat.lua` — the bridge to the shared library. It asks the library whether the active
  copy is usable, **`lib.Status(NEEDS_MINOR)`**, rather than checking the library's completion
  markers itself: Magely is the first host that does, and Priestly and Wildly still carry the
  hand-written check. It exposes `Magely.API`, `Magely.Settings`, `Magely.Engine`, `Magely.UI`,
  and `Magely.RegisterEvents`, which reports rejected events in chat. No API code lives here.
- `MagelyConfig.lua` — options panel, defaults, the Forever instance list, the Amplify / Dampen
  modes, exported config helpers. See "Config" below.
- `Magely.lua` — `DEFS`, the visibility rule, the Arcane Powder footer item, the spec look,
  event handling, slash commands and the test seam. See "The host" below. Everything else is
  LibGroupBuffs:
  - `Engine.lua` is the buff logic (aura cache, roster, stats, targeting, click mapping,
    `UNIT_AURA` filtering).
  - `UI.lua` is the window (rows, popover, secure buttons, dragging, ticker, what combat defers).
  A change to how buffs are read, targeted or drawn belongs in the library, not here.
- `tests/` — Lua 5.1 unit tests, no game client. See `tests/README.md`.
- `Tools/deploy.ps1` — deploy to the local Forever AddOns folder, library included.
- `.github/workflows/package-check.yml` — tests against the pinned library, a dry-run package, and
  a check that the zip embeds the library. Publishes nothing.
- `.pkgmeta`, `README.md`, `CHANGELOG.md`, `LICENSE` — packaging and user-facing material.

**One dependency: LibGroupBuffs-1.0.** It is never committed here — `Libs/` is git-ignored:

- **Release:** `.pkgmeta` `externals` embeds it at `Libs/LibGroupBuffs-1.0`, **pinned to a tag**
  (`r<MINOR>`), so a release cannot change underneath its own source.
- **Development:** check it out **next to this repository**, as `../LibGroupBuffs`. `tests/run.ps1`
  and `Tools/deploy.ps1` read it from there (or from `-Library`), print the revision they used, and
  fail loudly if it is missing. There is no vendored fallback.
- **CI** checks out the pinned tag, not the library's `main`.

`NEEDS_MINOR` in `MagelyCompat.lua` must equal the pinned tag; `tests/test_manifest.lua` checks the
TOC path, the externals key, the tag, the floor and the ignore rule all agree.

### The bridge's answers

| `lib.Status` | Means | Magely says |
|---|---|---|
| no library | `LibStub` has no copy | missing from Magely's Libs folder |
| `"ok"` | every file finished, active MINOR ≥ `NEEDS_MINOR` | nothing; starts |
| `"incomplete"` | a file threw partway, or an older copy's record under a newer MINOR | failed to load completely |
| `"too-old"` | complete, just behind | the version in use and the one needed - **never that it crashed** |
| `Status` absent, MINOR < floor, its four named markers all equal its MINOR (or it is r2–r5, which predate them) | another addon's complete copy from before `Status` existed | too old, as above |
| `Status` absent, MINOR < floor, a marker missing or older | that older copy threw partway | failed to load completely |
| `Status` absent otherwise | the library's last file, which installs `Status`, threw | failed to load completely |

Write the branches out: `a and f() or b` keeps only `f`'s first return, and would lose the MINOR
the too-old message names. Reading the named markers is allowed **only** for copies older than
`Status`: those tags are released and frozen, so that list cannot drift. `test_bridge` checks it
against the library's real r11 fixtures, whole and without `UI.lua`.

### A gap in a library seam

The seams were designed from Priestly alone and widened for Wildly; Magely will find more (the
cooldown pane is the known one). **Never fork or patch the library from here.** Fix it in
`C:\Projects\LibGroupBuffs`, following that repository's `AGENTS.md`: issue, branch, PR, `MINOR`
raised in every runtime file, the previous tag's files added as test fixtures, Priestly's and
Wildly's suites run against the working copy, merge, tag `r<MINOR>`. Then bump the pin here:
`tag:` in `.pkgmeta` and `NEEDS_MINOR` in `MagelyCompat.lua`, together, in a Magely PR.

Before calling something a gap, read `UI.lua`: `appearance()` already accepts a `title` (a spec
coloured `|cffRRGGBBMagely|r`), though the library's `AGENTS.md` does not list it yet.

## The host

`Magely.lua` exposes, for the config: `Magely_ScheduleRefresh`, `Magely_ForceRebuild` (does nothing
in combat for an open window - the library rebuilds it at combat end - and **never reopens a
window the player closed**; it goes through `WantsOpen`), `Magely_OnSoloToggle`,
`Magely_ApplyAlpha`, and `Magely.auraNames` (the Amplify and Dampen names, for detect mode). It
decides when the window opens, exactly as Wildly does: at login for a Mage in a group (or solo
mode) unless `visible` is false, or later when the spells arrive; on joining a group, overriding a
close (but not the roster arriving just after login); never on other roster churn, a ready check,
a settings change or a zone change over a close; nothing at all on another class, slash commands
included (one line saying so). Its test seam is `Magely._test`.

One rule Wildly does not need: an Amplify or Dampen **landing** can give a closed window its row
(Intellect untracked, the rest "when detected"). A relevant `UNIT_AURA` refreshes an open window;
for a closed one it queues **one** check per burst (`ReopenForAura`: `ui:Open` is not coalesced,
LibGroupBuffs #22, and `UNIT_AURA` is the noisiest event there is), never in combat, and only
through `WantsOpen` and `ui:Open`, so a player's close still wins.

### Buff definitions

`DEFS` are ID-based, the library's format: `id`, `snglID`, optional `grpID`, enUS `sngl` / `grp`
fallbacks, `fallbackIcon`, a `duration` seed. Names are resolved from IDs at runtime by
`engine:RefreshSpells()`, never the reverse.

| id | snglID | grpID | Notes |
|---|---|---|---|
| `intellect` | 1459 Arcane Intellect | 23028 Arcane Brilliance | Left-click Brilliance when known, else Intellect. Always visible. |
| `amplify` | 1008 Amplify Magic | — | Both clicks cast Amplify. Visible by its own mode. |
| `dampen` | 604 Dampen Magic | — | Both clicks cast Dampen. Visible by its own mode. |

The TBC flags `always`, `needsKnown`, `optional` and `leftUsesSingle` are **gone**. Availability is
the engine's (a row exists only for a spell the Mage knows), a def with no `grpID` casts the single
spell on both clicks, which is what `leftUsesSingle` did, and the engine's `isVisible(def, groups,
ord)` asks `Magely_ShouldShowBuff` for Amplify and Dampen **one at a time**, so both rows can show
at once. One behaviour change from TBC: Intellect used to show even when unknown (`always`); now,
like every row, it needs the spell.

### Reagent

`footerItems()` shows **Arcane Powder** (17020) once Arcane Brilliance is known and the Intellect
row is tracked, with the TBC build's count colours (50 / 25). Brilliance has one rank in Vanilla
content, learned at 56, so there is one reagent.

### Appearance

`appearance()` returns the spec's icon, a **spec-coloured title** (`|cffRRGGBBMagely|r` - the
library applies `look.title` on every rebuild, `UI.lua` `ApplyAppearance`), the header strip
tinted towards the spec colour, and the header and footer lines; the border stays Magely's cyan
`#3fc7eb`, and the popover keeps the library's colours, as the TBC build's did. Never fork `UI.lua`
for a colour: if a colour has no key, that is a library gap.

The spec comes from known spells, by ID, cached when spells change (never per rebuild): Arcane
Power (12042) → Arcane, Combustion (11129) → Fire, Ice Barrier (11426) → Frost, else the plain Mage
look. Icons and colours are the TBC build's. The talent-tab scan is gone on this client, and Summon
Water Elemental is a TBC spell.

## Config

`MagelyConfig.lua` is `WildlyConfig.lua`'s shape with Priestly's instance machinery. There is **no
class gate at file scope**: on any class but Mage its event frame does nothing - no options page,
no `MagelyDB`, no chat, no instance check - and every accessor copes with `MagelyDB` being nil.

It exposes, for `Magely.lua`: `Magely_EnsureDefaults`, `Magely_ShowSolo`, `Magely_TrackPets`,
`Magely_IsBuffEnabled` (`intellect` / `amplify` / `dampen`), `Magely_GetBuffMode`,
`Magely_ShouldShowBuff(defId, groups, ord)` (the engine's `isVisible`), `Magely_GetFrameAlpha`,
`Magely_FrameLocked`, `Magely_ShowClickHints`, `Magely_PopoverSide`, `Magely_LearnDuration` /
`Magely_GetLearnedDuration`, `Magely_OpenConfig`, the write paths `Magely_SetConfig(key, value)`
and `Magely_SetInstance(which, name, tracked)`, their hook `Magely_OnConfigChanged(key)` (empty
today), and `Magely_HandleEnteringWorld` / `Magely_CheckClientBuild`. It calls, guarded, the hooks
`Magely.lua` defines: `Magely_ForceRebuild`, `Magely_OnSoloToggle`, `Magely_ApplyAlpha`.

### Amplify and Dampen

Each has its own mode, `always`, `detect` or `instance` (`amplifyMode`, `dampenMode`), and both
rows can show at once. An unknown saved mode is repaired to `detect`.

- **detect** reads every member through `API.ReadBuff` with the names `Magely.lua` publishes as
  `Magely.auraNames[defId]`, resolved from spell IDs, so it works in every locale. A read that
  combat blocks counts as detected: dropping the row at the pull would be worse. Before the names
  are published nothing is detected.
- **instance** looks up the instance the player stands in, in `amplifyInstances` /
  `dampenInstances`. The check gates on `instanceType ~= "none"` (outdoors the name is the
  continent), and reports an instance the list does not know once per session - only a dungeon or
  raid, and only while one of the modes is `instance`.

`INSTANCE_DB` is **Forever's** list, from Priestly's `INSTANCE_DB` (exact `GetInstanceInfo()`
names), with an Amplify default and a Dampen default per instance. The TBC list is gone. Defaults
are advice, not measurement: Amplify suits physical content, Dampen magic-heavy content; the TBC
build's Vanilla opinions are kept where it had one, and Forever's own instances start unchecked.
The saved maps are backfilled by `EnsureDefaults` and **never pruned**, and written one flag at a
time through `Magely_SetInstance` (the library's `settings:SetIn`).

Zoning (`PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`) re-checks the instance and calls
`Magely_ForceRebuild` - not a refresh, which does nothing for a window that closed for want of
rows. `Magely.lua`'s ForceRebuild must never reopen a window the player closed.

## SavedVariables

`MagelyDB` is **per character**; `MagelySVCheck` is account-wide and holds only the library's
`svLoadCheck` marker, so the addon can tell when account-wide storage is fixed. Same as Priestly
and Wildly. The TBC addon kept `MagelyDB` account-wide; there is no migration, because this is a
separate install and nothing loads back on this client anyway.

**NO SavedVariables load back on this client — per-character included** (measured on build
1.60.1.69913 and re-checked on 69977; see Priestly's `AGENTS.md`, `docs/FOREVER-PROBE.md` section
11, and the PORTING doc section 0). Every session starts from defaults. Write the addon so losing
every setting at login is survivable.

`MEASURED_ON_BUILD` and `SV_BROKEN_ON_BUILD` in `MagelyConfig.lua` are **69977**, the newest build
both facts were checked on; Priestly and Wildly still carry 69913. `test_config_seam` pins them
independently of the source, so bump the test with the constants after re-measuring - never to
make it pass.

- **Never verify persistence by reading the SV file or diffing it against `.bak`.** It always
  looks populated because `EnsureDefaults` rewrites every default each session. Count launches
  inside the addon, or check a key that defaults to nil (`pos`).
- **Never with `/reload` alone.** `/reload` keeps the client process alive and can only prove
  something is broken. Confirm with a **full exit and relaunch**.
- **Every write to `MagelyDB` or `MagelySVCheck` goes through the settings write path**
  (`Magely_SetConfig` / `Magely_SetInstance`, built on the library's `Settings.New`), except
  inside `-- config-owner: begin/end` regions in `MagelyConfig.lua` (three: the saved-table
  accessors, `EnsureDefaults`, the learned-duration cache). `tests/test_config_seam.lua` scans
  every ported file with the library's `tests/config_scan.lua` and pins the region count. Owner
  code that writes through a local alias reports it with `settings:Changed(key)`.

Current `MagelyDB` keys: `trackIntellect`, `trackAmplify`, `trackDampen`, `amplifyMode`,
`dampenMode`, `showSolo`, `trackPets`, `frameAlpha`, `popoverSide`, `lockFrame`, `showClickHints`
(all in `DEFAULTS`), `amplifyInstances` / `dampenInstances` (backfilled, never pruned),
`learnedDurations` (keyed by **spell name**, reset when the client build changes), `visible` and
`pos` (the window's own state, never defaulted), and `svLoadCheck` (never in `DEFAULTS`). **`svLoadCheck`
  must never be in `DEFAULTS`**: it detects Blizzard's fix by being written every session and never
  defaulted.

## WoW API And Lua Rules

- Target the **Retail/Mainline** API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` here.
- Keep `## Interface: 16001`. The format is `%d%02d%02d`, so 1.60.1 → 16001. `11601` is a
  transposed-digit bug you will see in the wild.
- **Never call a moved API directly.** Add it to LibGroupBuffs' `Compat.lua` and reach it through
  `Magely.API`.
- **Never copy a library function into a local** (`local F = API.F`). `API` is shared with every
  addon that embeds the library and a newer copy upgrades it in place; a copy keeps the old
  version. Call through `API`, or wrap: `local function F(...) return API.F(...) end`. Call engine
  and ui methods (`engine:GroupStat(...)`), never a copy of them.
- Register events only through **`Magely.RegisterEvents`**, never the library's
  `API.RegisterEvents*` or a bare `frame:RegisterEvent`. `RegisterEvent` throws on an unknown
  event name and may return `false`; the wrapper reports both in chat.
- **`COMBAT_LOG_EVENT_UNFILTERED` cannot be registered** — it is a forbidden action here. Deaths
  are `UNIT_DIED`; other casts are unmeasured.
- **`C_Spell.GetSpellInfo(name)` only resolves spells the player KNOWS.** By ID it always works.
- **`UnitName(unit)` is a trap**: first name only for anyone but the player, with the surname where
  the realm used to be. Display with `API.UnitDisplayName`; key caches on `API.UnitKey` (GUID).
- **`GetInstanceInfo()` returns the continent outdoors** — gate on `instanceType ~= "none"`.
- **Auras are unreadable in combat for every unit**, and a secret value throws when compared or
  truth-tested. Never read an aura outside the library (`API.ReadBuff`, the engine).
- `ReloadUI()` is protected — use `/reload`.
- Errors are off by default (`/console scriptErrors 1`) and stop being delivered after 100 in a
  session.
- Slash-command arguments can contain a two-word name: `^(%S+)%s+(.+)$`, never two `%S+`.
- Lua 5.1. `0` is truthy — `x or default` does not guard a numeric that can be 0.

## Content Rules (Vanilla, mid-beta)

- **Level cap is 60**, and the live beta is capped far lower (20). Never hardcode a cap.
- **Arcane Brilliance is level 56.** Every row must work single-target only; the engine's
  `ClickSpells` falls back so the primary click is never dead. Datamining says it buffs the whole
  raid here, like Priestly's Prayers (LibGroupBuffs issue #19); not measured.
- **The spec comes from known spells**, by ID: the talent-tab scan is gone
  (`GetNumTalentTabs` / `GetTalentTabInfo` do not exist). Summon Water Elemental is a TBC spell.
  At a cap of 20 no 31-point talent is learnable, so every Mage shows the plain Mage look.
- **Instances are Forever's**, not TBC's: the TBC list is dead content. Take the names from
  Priestly's `INSTANCE_DB`, which is keyed on exact `GetInstanceInfo()` names.
- **Durations are learned, not assumed.** `DEFS[].duration` is a seed; the engine learns the real
  value from live auras, keyed by spell name.

## Secure UI Rules

The window is LibGroupBuffs' `UI.lua`, which owns these rules; do not reimplement them here.

- **In combat the window touches nothing.** Both frames parent secure buttons, so the client
  silently refuses to hide, move, re-anchor or stop a drag on them. `ui:Close()` returns false and
  the host says the window closes when combat ends (`onCloseDeferred`); `ui:OnCombatEnd()` on
  `PLAYER_REGEN_ENABLED` does what was asked.
- Buttons register **both mouse edges** (`API.ClickEdges`), and **never set `typerelease`** — that
  would cast twice and burn two reagents.
- No `SecureHandler*`, `_onstate-*` or state drivers: `loadstring_untainted` is missing on this
  client.
- **Known limitation, do not try to fix it:** a roster change mid-combat can hand a wired `raid3`
  token to a different player until `PLAYER_REGEN_ENABLED`.

## Validation

Offline, on every change:

```powershell
pwsh tests\run.ps1        # luac -p + all unit tests; needs ../LibGroupBuffs and Lua 5.1's luac
```

The first line names the library checkout and revision the tests ran against, next to the tag a
release would ship. They differ while working on both; they must match before a release.

`tests/wow_stubs.lua` is an **allowlist**: reading any global it does not define fails the run. It
is a copy of LibGroupBuffs' stub, and every difference is marked `Magely:` so a library fix can be
carried over (sharing one stub is LibGroupBuffs issue #21); `tests/test_stub.lua` pins those
differences. Before stubbing a new global, confirm it exists in the newest
`C:/Projects/References/forever-api-<build>.md` and stub it with the client's exact signature;
never add one because a test failed. Strict globals do not cover **methods** — for anything built
on a widget method, execute it and assert what it produced.

In game — **nothing ships without this pass**, and not before slice 3:

```powershell
pwsh Tools\deploy.ps1
```
```
/console scriptErrors 1
/reload
```

- AddOn list: enabled **and not flagged out of date**.
- `/magely help | config | show | hide | reset | pos`; drag the frame.
- Rows appear for what the Mage actually knows; no Brilliance wiring when it is not known.
- Amplify Magic (level 18) and Dampen Magic (level 12) in each mode, alone and together.
- Instance mode inside a listed dungeon; a close survives zoning in.
- Left and right click cast, out of combat and in combat, on yourself and a party member.
- Enter combat: timers count from the cache; a member never seen shows `?`, not `MISS`.
- Roster churn: invite/leave, reshuffle subgroups, pets — state follows the player, not the slot.
- Footer: Arcane Powder only once Brilliance is known, and its count.
- Options panel: every control.

## Workflow

1. **Open an issue first**, with enough context to review against.
2. **Branch** off `main`. Never commit to `main` directly.
3. **Open a PR** referencing the issue (`Closes #N`). CI runs the syntax check, the unit tests and a
   dry-run package build.
4. **Review before merge** using `$wow-addon-review`; post the result on the PR.
5. Squash-merge, then delete the branch.

## Releasing

CurseForge (project **1545112**) builds from a repository webhook when it sees a tag, and
publishes `CHANGELOG.md` as the release notes. **Do not add a release workflow**; it would publish
a second time (see Priestly's `AGENTS.md`, Packaging, for the history).

1. **Every tag needs a `CHANGELOG.md` entry, committed before the tag is pushed**, written for
   players.
2. The release type comes from the **tag name**: `alpha` → Alpha, `beta` → Beta, else Release.
3. **Check the published zip carries LibGroupBuffs, and nothing else.** CI proves the BigWigs
   packager embeds it, but releases are built by CurseForge's own packager from the tag webhook,
   which CI cannot run, and **the two do not behave the same**. Download the published file, run
   `lua tests/libfiles.lua <unzipped>/Magely/Libs/LibGroupBuffs-1.0 ship`, then count the files in
   that folder: the ones that command lists plus `LICENSE`, and nothing else.

   **CurseForge does not apply an external's own `.pkgmeta`.** Measured on Priestly's v2.0.6
   download: the library's `tests/`, `AGENTS.md`, `CLAUDE.md` and `README.md` all shipped. The
   entries under `Libs/LibGroupBuffs-1.0/` in *this* `.pkgmeta` are the guarantee, and
   `tests/test_manifest.lua` mirrors them from the library's own list.
4. Keep `@project-version@` in the TOC; `Tools/deploy.ps1` rewrites it to `dev` in the deployed
   copy only.
