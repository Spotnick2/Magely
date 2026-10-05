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
4. **v1.0.0**, handed to testers for the in-game pass (below).
5. **The cooldown pane**, after v1.0 (see below).

Slices 1 to 4 are done and **v1.0.0 is the first Forever release**. It shipped before anyone on
the port had a Mage - a deliberate exception to the rule under Validation, made by the owner and
stated in the release notes.

**There is a Mage now.** The first in-game pass on one (2026-09-27, build 70009) is recorded in
`docs/FOREVER-NOTES.md`: Arcane Intellect known and its clicks wired, at least 59:56 remaining
after a cast (the total unmeasured), surnames in the popover. What Magely shares with Priestly - the engine, the window, the settings path, the combat
rules - is taken as measured by Priestly. What is Mage-specific and not yet seen in play stays
listed there as **unmeasured**: Amplify and Dampen (levels 18 and 12), their modes, instance mode
in a dungeon, combat, raids. Record each as it is measured, and delete this section once the
checklist there has been run.

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

It comes back as its own slice, on the library rather than beside it: LibGroupBuffs #24 (a
companion pane needs more than `onLayout` / `onVisibility` - there is no tick hook, `onLayout`
never fires in combat), then `MagelyCooldowns.lua`, keyed by GUID and anchored to
`ui:MainFrame()`. **Never fork the window for it.**

What `Tools/MagelyProbe` has measured so far (build 70009; `docs/FOREVER-NOTES.md`):

- **The pane itself is possible**: a plain frame anchored under the protected window can be
  resized, moved, hidden and shown in combat.
- **Other players' casts: not established.** `UNIT_SPELLCAST_SUCCEEDED` registers; one ~8-second
  run while the owner's second account cast saw no event for any unit, but that account being in
  the party was not confirmed. A controlled repeat decides it. If others' casts are not delivered,
  the only source left is each provider announcing its **own** casts by addon message.
- **Talents cannot be read** through `C_SpecializationInfo.GetTalentInfo` in any query shape, for
  yourself or an inspected target; inspection itself works. Whether Retail's traits system holds
  them is the probe's next question.

## Repository Layout

- `Magely.toc` — addon manifest: interface version, saved variables, load order.
- `MagelyCompat.lua` — the bridge to the shared library: asks it for Magely's instance
  (`lib:New`, exposed as `Magely.GB`) and its compat layer as `Magely.API`, and holds Magely's one
  reporter, which prints everything the library has to say — the settings checks and rejected
  events. `Magely.RegisterEvents` is the one way to register an event. No API code lives here.
- `MagelyConfig.lua` — options panel, defaults, the Forever instance list, the Amplify / Dampen
  modes, exported config helpers. See "Config" below.
- `Magely.lua` — `DEFS`, the visibility rule, the Arcane Powder footer item, the spec look,
  event handling, slash commands and the test seam. See "The host" below. Everything else is
  LibGroupBuffs (one file, `LibGroupBuffs.lua`, since r26; the names below are its sections, each
  built through `Magely.GB`):
  - `Engine` is the buff logic (aura cache, roster, stats, targeting, click mapping,
    `UNIT_AURA` filtering).
  - `UI` is the window (rows, popover, secure buttons, dragging, ticker, what combat defers),
    drawn in LibGlass-1.0's material.
  A change to how buffs are read, targeted or drawn belongs in the library, not here.
- `docs/FOREVER-NOTES.md` — what is measured and what is not, and the in-game checklist.
- `tests/` — Lua 5.1 unit tests, no game client. See `tests/README.md`.
- `Tools/deploy.ps1` — deploy to the local Forever AddOns folder, both libraries included (it runs
  LibGlass's own deploy first). `-Probe` /
  `-ProbeOnly` deploy `Tools/MagelyProbe` too / alone.
- `Tools/MagelyProbe/` — the throwaway probe for the cooldown pane's questions (`/mprobe`); see
  `docs/FOREVER-NOTES.md`. Never shipped (`.pkgmeta` ignores `Tools`). It reads every client global
  with `rawget`, so a missing API is recorded rather than fatal, and `tests/test_probe.lua` holds it
  to that.
- `.github/workflows/package-check.yml` — tests against the pinned libraries, a dry-run package,
  and a check that the zip is exactly the addon plus both libraries at their pins. Publishes
  nothing.
- `.pkgmeta`, `README.md`, `CHANGELOG.md`, `LICENSE` — packaging and user-facing material.

**Two dependencies, embedded side by side:**

- **[LibGroupBuffs-1.0](https://github.com/Spotnick2/LibGroupBuffs)**: compat layer, engine,
  window, window policy, settings.
- **[LibGlass-1.0](https://github.com/Spotnick2/LibGlass)**, the glass material LibGroupBuffs'
  window draws with. LibGroupBuffs does not embed it itself (the packager does not fetch an
  external's own externals), so Magely declares both. See "The glass material" below.

Neither is ever committed here — `Libs/` is git-ignored:

- **Release:** `.pkgmeta` `externals` embeds them at `Libs/LibGroupBuffs-1.0` and
  `Libs/LibGlass-1.0`, each **pinned** — to a tag (`r<MINOR>`), or to a full commit while piloting
  a library release before it is tagged — so a release cannot change underneath its own source.
  Never `tag: latest`, and **no comment on a value line**: the packager's YAML reader keeps it as
  part of the ref.
- **Development:** check both out **next to this repository**, as `../LibGroupBuffs` and
  `../LibGlass`. `tests/run.ps1` and `Tools/deploy.ps1` read them from there (or from `-Library` /
  `-LibGlass`, and `$env:LIBGLASS`), print the revision they used, warn when a checkout is not at
  its pin (`tests/pins.ps1`), and fail loudly if one is missing. There is no vendored fallback.
- **CI** fetches each pinned ref (`tests/fetch_external.sh`), not the libraries' `main`.

`.pkgmeta`'s externals are read **by path**, through `tests/pkgmeta.lua` — run.ps1, deploy.ps1, CI
and the manifest test all use it. With two externals, "the first `tag:` in the file" is LibGlass's.
`NEEDS_MINOR` in `MagelyCompat.lua` must equal the pinned LibGroupBuffs MINOR;
`tests/test_manifest.lua` checks the TOC paths, the externals, the pins, the floor and the ignore
rules all agree.

### The bridge

`MagelyCompat.lua` calls `lib:New({ owner = "Magely", report = Report, needs = NEEDS_MINOR })`
**under pcall**. `New` refuses a copy that did not finish loading, a missing or half-loaded
LibGlass, and one older than the floor. On a refusal the bridge prints one line in chat and
stops, and `MagelyConfig.lua` and `Magely.lua` stop when `Magely.API` is nil.

**`New`'s error is never printed to players.** Its wording is for developers, it cannot tell
whose copy failed, and a crash inside `New` has no position under pcall, so its text cannot tell
a crash from a refusal. `WhyRefused` reads the same facts `New` checks, in `New`'s order, from the
libraries' markers:

| Fact | Magely says |
|---|---|
| no library at all | missing from Magely's Libs folder; reinstall |
| a copy without `New`, below the floor | Magely's own copy did not load; reinstall |
| a copy without `New`, at or above the floor | failed to load completely; reinstall |
| `lib.ready ~= active` | that copy did not finish loading - **`/console scriptErrors 1` shows whose**, not "reinstall": LibStub runs the newest copy, which may not be Magely's |
| LibGlass not registered | missing from Magely's Libs folder; reinstall |
| LibGlass registered, `ready ~= minor` | another addon's copy failed; `scriptErrors`, as above |
| below the floor | names both versions; reinstall - **never that it crashed** |
| anything else | failed to load completely |

`New`'s own text goes into the developers' `error()` as `lib:New said: …`. LibGroupBuffs#54 asks
`New` to raise a structured reason; when it lands, switch on its `code` instead.

Constructors are **dot calls on the instance**: `GB.Engine(host)`, `GB.UI(host)`,
`GB.Settings(spec)`, `GB.Visibility(spec)` (each fills in `owner` and `report`); shared data is
`GB.STATES`, `GB.PET_GROUP`, `GB.LOAD_CHECK_KEY`, `GB.MINOR`.

**One reporter.** The library never prints; everything it says arrives at the bridge's
`report(text, kind)`, which the settings object inherits. A kind's rewording lives with the file
that owns it, in `Magely.reportFilters[kind]` (`MagelyConfig.lua`: `newBuild`, `settingsLoaded`);
a filter returns the text to print, or nil to say nothing. Rejected events arrive as kind
`"events"` and are recorded in `Magely.eventFailures` **before** the chat-frame check; the label is
coloured by the line's shape (`^([^:]*:)(.*)$`), not the library's words.

### A gap in a library seam

The seams were designed from Priestly alone and widened for Wildly; Magely will find more (the
cooldown pane is the known one). **Never fork or patch the library from here.** Fix it in
`C:\Projects\LibGroupBuffs`, following that repository's `AGENTS.md`: issue, branch, PR, `MINOR`
raised in every runtime file, the previous tag's files added as test fixtures, Priestly's and
Wildly's suites run against the working copy, merge, tag `r<MINOR>`. Then bump the pin here:
`tag:` in `.pkgmeta` and `NEEDS_MINOR` in `MagelyCompat.lua`, together, in a Magely PR - **in a
release made anyway**: players get library fixes earlier through whichever addon ships the newest
copy, since LibStub runs that one.

Before calling something a gap, read the UI section of `LibGroupBuffs.lua`: `appearance()` already
accepts a `title` (a spec coloured `|cffRRGGBBMagely|r`), though the library's `AGENTS.md` does not
list it yet.

## The host

`Magely.lua` exposes, for the config: `Magely_ScheduleRefresh`, `Magely_ForceRebuild` (does nothing
in combat for an open window - the library rebuilds it at combat end - and **never reopens a
window the player closed**; it goes through `WantsOpen`), `Magely_OnSoloToggle`,
`Magely_ApplyAlpha`, and `Magely.auraNames` (the Amplify and Dampen names, for detect mode).

It no longer decides **when** the window opens. That is `lib.Visibility` (LibGroupBuffs r24):
Magely builds one `vis` with its class, solo setting and saved `visible`, and its events report what
happened — `vis:Login()`, `ReadyCheck()`, `GroupJoined()`, `RosterChanged()`, `SoloToggled(on)`,
`ContentChanged()`. **Do not add a window-policy branch to `Magely.lua`.** This used to live here, in
Priestly and in the third addon as three copies, and every defect they produced was one found in a
single addon and left standing in the other two (LibGroupBuffs#22 lists them). `ContentChanged` is
one method for every source — a setting, a spell learned, a tank appearing, zoning — because
splitting it is what grew the copies.

What stays Magely's is whether a notification is worth making at all: the class it is for, and whether it has
anything to report: an Amplify landing **in combat** is not reported at all, because auras cannot
be read then and only Magely knows that about its own rows. Its test seam is `Magely._test`.

One rule Wildly does not need: an Amplify or Dampen **landing** can give a closed window its row
(Intellect untracked, the rest "when detected"). A relevant `UNIT_AURA` refreshes an open window;
for a closed one `ReopenForAura` asks `ui:Open(0.35)` - never in combat, and only when
`WantsOpen` - and the library coalesces a burst into one rebuild (since r14, LibGroupBuffs #22),
with a player's close still winning through its generation check.

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
library applies `look.title` on every rebuild, `ApplyAppearance` in `LibGroupBuffs.lua`), the header strip
tinted towards the spec colour, and the header and footer lines; the border stays Magely's cyan
`#3fc7eb`, and the popover keeps the library's colours, as the TBC build's did. Never fork the library's UI
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
`svLoadCheck` marker, so the addon can tell when account-wide storage works. Same as Priestly and
Wildly. The TBC addon kept `MagelyDB` account-wide; there is no migration, because this is a
separate install.

**SavedVariables load back on 70009.** Through 69977 nothing did, per-character included
(Priestly's `docs/FOREVER-PROBE.md` section 11): every session started from defaults. The addon is
still written so losing every setting at login is survivable - the beta has broken this once, and
Magely v1.0.0 shipped before the fix.

`MEASURED_ON_BUILD` in `MagelyConfig.lua` is **70009**, the build Priestly last re-measured
(Spotnick2/priestly#60: API dump, `/pprobe` in and out of combat, the click bench).
`test_config_seam` pins it independently of the source, so bump the test with the constant after
re-measuring - never to make it pass.

**There is no second, settings-check constant** (`SV_BROKEN_ON_BUILD` is gone, and
`test_config_seam` fails if it or `svBrokenOnBuild` comes back). Since LibGroupBuffs r14 the load
check decides from the marker's own recorded build: a marker returning under a different build was
read after a restart, which is the fix; one from the running build is a relog or `/reload` and is
silent. A `loads` latch keeps later patches quiet, and r15 also reads the `announced` latch r12
wrote, so nobody is told twice (LibGroupBuffs #31). Do not reintroduce a host build number for it:
that is what announced a fix on every relog (LibGroupBuffs #27).

- **Never verify persistence by reading the SV file or diffing it against `.bak`.** It always
  looks populated because `EnsureDefaults` rewrites every default each session. Count launches
  inside the addon, or check a key that defaults to nil (`pos`).
- **Never with `/reload` alone.** `/reload` keeps the client process alive and can only prove
  something is broken. Confirm with a **full exit and relaunch**.
- **Every write to `MagelyDB` or `MagelySVCheck` goes through the settings write path**
  (`Magely_SetConfig` / `Magely_SetInstance`, built with `Magely.GB.Settings`), except
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

## The glass material

The window's look is **LibGlass-1.0** (`..\LibGlass`, github.com/Spotnick2/LibGlass, MIT), the
material every glass addon embeds. LibGroupBuffs draws with it; Magely never calls LibGlass itself
and has no `Glass.lua` or textures of its own.

- **Material changes are LibGlass PRs**, never edits here; how the window uses it is a
  LibGroupBuffs PR. Never edit either checkout from this repository's session: a need found here
  goes on that library's issue tracker.
- **How it's embedded:** `.pkgmeta` externals put it in `Libs\LibGlass-1.0\` — the only supported
  path, since its `MEDIA` is derived from it; anywhere else draws blank textures with no error — and
  the TOC loads its XML **before** LibGroupBuffs'. A dev copy comes from the LibGlass checkout's own
  `Tools\deploy.ps1`, which `Tools\deploy.ps1` here calls first.
- **The pin:** a tag, never `tag: latest`. Bump it only in a release made anyway.
- `tests/libfiles.lua` checks every texture LibGroupBuffs names is in LibGlass's `Media/`.
- **Colours passed to a glass bar's `SetStatusBarColor` must be plain** (the library's hook
  compares them): never a secret value.

## WoW API And Lua Rules

- Target the **Retail/Mainline** API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` here.
- Keep `## Interface: 16001`. The format is `%d%02d%02d`, so 1.60.1 → 16001. `11601` is a
  transposed-digit bug you will see in the wild.
- **Never call a moved API directly.** Add it to LibGroupBuffs' compat section and reach it
  through `Magely.API`.
- **Never copy a library function into a local** (`local F = API.F`). `API` is shared with every
  addon that embeds the library and a newer copy upgrades it in place; a copy keeps the old
  version. Call through `API`, or wrap: `local function F(...) return API.F(...) end`. Call engine
  and ui methods (`engine:GroupStat(...)`), never a copy of them.
- Register events only through **`Magely.RegisterEvents`**, never the library's
  `API.RegisterEvents*`, `GB.RegisterEvents` or a bare `frame:RegisterEvent`. `RegisterEvent`
  throws on an unknown event name and may return `false`; the wrapper calls `GB.RegisterEvents`,
  whose rejections reach Magely's reporter as kind `"events"`, printed and recorded.
- **`COMBAT_LOG_EVENT_UNFILTERED` cannot be registered** — it is a forbidden action here. Deaths
  are `UNIT_DIED`; other casts are unmeasured.
- **`C_Spell.GetSpellInfo(name)` only resolves spells the player KNOWS.** By ID it always works.
- **`UnitName(unit)` is a trap.** On 70009 it returns only the **first name** for *every* unit,
  player included, with the surname where the realm normally sits - so `local name, realm =
  UnitName(unit)` hands you a surname and calls it a realm. On 69913 the player alone came back
  joined, with a real realm; which reading is right is unresolved (Priestly's
  `docs/FOREVER-PROBE.md` section 4), so depend on neither. Display with `API.UnitDisplayName`
  (`GetUnitName(unit, false)`, which joins under both); key caches on `API.UnitKey` (GUID). The
  test stub models 70009 by default and 69913's shape for a unit given a `realm`.
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

The window is LibGroupBuffs' UI section, which owns these rules; do not reimplement them here.

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
pwsh tests\run.ps1        # luac -p + all unit tests; needs ../LibGroupBuffs, ../LibGlass and Lua 5.1's luac
bash tests/fetch_external.sh Libs/LibGlass-1.0 <dir>   # clone a library at its .pkgmeta pin (what CI does)
```

The first lines name each library checkout and revision the tests ran against, and warn when one
is not at its `.pkgmeta` pin. They differ while working on a library; they must match before a
release. **Test against clones of the pins**, not `../LibGroupBuffs` as another session left it:
a branch there can carry a shared stub for a different client build.

**The stub is shared.** The client surface lives in `../LibGroupBuffs/tests/wow_stubs.lua`, one
copy for Priestly, Wildly and Magely (LibGroupBuffs#21) — it was a copy here until the glass
material needed mask, slice and status-bar methods in all three at once, which is the drift a copy
was always going to cause. `tests/wow_stubs.lua` is now a thin layer holding only what is Magely's:
its default class and its own globals. A new *API* stub goes in the library, where all three get
it; a new *global* goes in the layer. Anything the source reads guarded (`if Magely_OpenConfig
then`) must be allowed as nil, or the guard throws inside the stub instead of exercising the
branch it protects — `tests/test_bridge.lua` checks the guards against the list.

The stub is an **allowlist**: reading any global it does not define fails the run. Before stubbing a new global, confirm it exists in the newest
`C:/Projects/References/forever-api-<build>.md` and stub it with the client's exact signature;
never add one because a test failed. Strict globals do not cover **methods** — for anything built
on a widget method, execute it and assert what it produced.

In game — **nothing ships without this pass**. The one exception so far is v1.0.0, released
before anyone on the port had a Mage (see Port status). There is one now, so the next release needs
the pass. The checklist is in `docs/FOREVER-NOTES.md`:

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
3. **Check the published zip carries both libraries, and nothing else.** CI proves the BigWigs
   packager embeds them, but releases are built by CurseForge's own packager from the tag webhook,
   which CI cannot run, and **the two do not behave the same**. Download the published file and,
   with `<p>` = `<unzipped>/Magely/Libs`, check each folder:
   - `lua tests/libfiles.lua <p>/LibGroupBuffs-1.0 ship <p>/LibGlass-1.0`, then count the files in
     `LibGroupBuffs-1.0/`: **four** (the XML, `LibStub/LibStub.lua`, `LibGroupBuffs.lua`,
     `LICENSE`). There is no `Media/` any more.
   - `lua tests/libfiles.lua --glass <p>/LibGlass-1.0 ship`, then count the files in
     `LibGlass-1.0/`: **nineteen** (the XML, the two files it loads, `LICENSE`, 15 textures).
   - Both libraries equal to their pins, and the released `MagelyConfig.lua` must still say
     `"@" .. "project-version@"` (#32).

   **CurseForge does not apply an external's own `.pkgmeta`.** Measured on Priestly's v2.0.6
   download: the library's `tests/`, `AGENTS.md`, `CLAUDE.md` and `README.md` all shipped. The
   entries under `Libs/LibGroupBuffs-1.0/` and `Libs/LibGlass-1.0/` in *this* `.pkgmeta` are the
   guarantee, and `tests/test_manifest.lua` mirrors them from each library's own list.
4. Keep `@project-version@` in the TOC; `Tools/deploy.ps1` rewrites it to `dev` in the deployed
   copy only.
