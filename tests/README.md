# Magely tests

Unit tests that run under **Lua 5.1** (the interpreter WoW uses) with no game client. Plain
scripts, no external dependencies. Same shape as Priestly's.

## Running

All tests:

```powershell
pwsh tests/run.ps1
```

A single test, from the repo root so the relative paths resolve:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
```

Use the Lua **5.1** interpreter, not a newer Lua that may be first on `PATH`. `run.ps1` defaults to
`C:\Program Files (x86)\Lua\5.1\lua.exe` (override with `-Lua <path>`) and runs `luac -p` over the
files `Magely.toc` loads and the library first. That check is required: `run.ps1` fails if it cannot
find `luac.exe` next to `lua.exe` (override with `-Luac <path>`).

**The tests need LibGroupBuffs-1.0 checked out next to this repository** (`../LibGroupBuffs`).
`run.ps1` takes `-Library <path>` instead and prints which checkout and revision it used next to
the tag a release pins. A single test run by hand reads the `LIBGROUPBUFFS` environment variable,
or the sibling checkout. There is no vendored copy to fall back to, on purpose.

## How it works

- **`wow_stubs.lua`** — a minimal WoW: Forever API mock, copied from LibGroupBuffs' own stub (every
  difference marked `Magely:`):
  frames that record secure attributes and refuse protected calls in combat, a `C_Timer` that
  collects callbacks, `C_UnitAuras` with a secrecy switch, known spells, and units with GUIDs and
  surnames. Drive it through the global `WoW` table. `dofile("tests/wow_stubs.lua")` **first** in
  every test.
- **`harness.lua`** — `check` / `eq`, `readFile`, `tocFiles()`, `loadLibrary()` (the library
  through its own XML) and `loadAddon()` (the library, then Magely's files in TOC order, skipping
  `H.NOT_YET_PORTED` - the files still on TBC code).
- **`libfiles.lua`** — the one reader of the library's XML, shared by the harness, `run.ps1`,
  `Tools/deploy.ps1` and CI.

## Test files

| File | What it pins down |
|---|---|
| `test_manifest.lua` | The TOC: interface 16001, per-character `MagelyDB` plus the account-wide `MagelySVCheck`, load order, and that the TOC path, `.pkgmeta` externals, pinned tag, `NEEDS_MINOR` and `.gitignore` agree. |
| `test_bridge.lua` | `Magely.API` / `.Settings` / `.Engine` / `.UI` are the library's own tables; rejected events are printed in chat. The library's own `lib.Status` decides whether a copy is usable, and every answer reaches the player as the right message: missing, failed to load (including the real library with one file unfinished), and too old (naming both versions, never claiming a crash) - also for an older copy from before `Status` existed. Also scans every ported file: each `API.*` it uses exists, no library function is copied into a local, and events go only through `Magely.RegisterEvents`. |
| `test_availability.lua` | Magely's DEFS on the engine: ID-based with no TBC flags, which buffs get a row for what the mage knows, what each click casts (Brilliance when known, Amplify and Dampen single on both buttons), both optional rows at once, the toggles and each buff's own mode layered over availability, the aura names published for detect mode, localized names. |
| `test_clicks.lua` | The secure attributes after a rebuild: Intellect vs Brilliance, Amplify and Dampen each on both buttons and aiming at whoever lacks its own buff, targets following who is missing it (a Brilliance counts), clearing rather than casting on a corpse, PreClick re-aiming, popover rows, both mouse edges, no `typerelease`, and hints that say what a click does. |
| `test_frames.lua` | Executes every handler, event and slash command the host installs, and checks what they produce where it matters: login, hover poll, drag and lock, closing in combat (and being told), an Amplify landing counting as relevant, `/magely help` describing the live mapping, `reset` while locked, `pos`, and the Arcane Powder tooltip. |
| `test_host.lua` | What is Magely's own: Arcane Powder once Brilliance is known and its count colours, the spec from Arcane Power / Combustion / Ice Barrier (read when spells change, not per rebuild), and the spec's title, header and lines reaching the drawn window - including after a respec. |
| `test_visibility.lua` | When the window opens itself: at login in a group or solo mode, never on another class, a deliberate close surviving reloads, roster churn, ready checks and zoning, joining a group reopening it, a combat-time show honoured at combat end, the solo checkbox, the toggle, and a window that closed for want of rows coming back when zoning in gives it an Amplify row. |
| `test_config.lua` | `MagelyDB` defaults (the cooldown-pane keys gone), the Amplify and Dampen modes each read back and repaired independently, the buff toggles, the Forever instance list (seeded, backfilled, never pruned, no TBC instances), the instance check (continent outdoors is not an instance; an unknown dungeon reported once, only to someone using "by instance"), detect mode through `API.ReadBuff` with a blocked read keeping the row, both rows at once, learned durations per spell name and client build, and the window's settings accessors. |
| `test_config_seam.lua` | The one write path: `Magely_SetConfig` and `Magely_SetInstance` report through the hook, the library's `config_scan.lua` finds no direct `MagelyDB` write in any ported file, the owner regions are pinned, another class gets nothing (not even on zoning), and the SavedVariables-fix and new-build checks fire (or stay quiet) on the right logins. |
| `test_options.lua` | Builds the options panel and clicks everything in it, with spies in place of the hooks `Magely.lua` defines: each checkbox, both mode radio groups independently, the popover side, the slider, both tabs, every instance's Amp and Damp box, Reset Defaults and the row tooltips; zoning re-checks the instance and asks for a rebuild; nothing needs the host loaded. |
| `test_libfiles.lua` | The library's file list, read from its XML, and that `libfiles.lua` does not mistake a test for its own script mode. |
| `test_stub.lua` | The stub entries Magely changed from the library's copy (`strsplit` keeping empty fields) keep the client's shape. |

## The stub is an allowlist, and it must model absences

`wow_stubs.lua` fails the run on the read of any global it does not define, so it is the list of
APIs verified present on this client. Never add a global because a test failed: confirm it in the
build-matched API dump (`C:/Projects/References/forever-api-<build>.md`) and stub it with the
client's exact signature, or list it as known-absent and make the addon cope.
