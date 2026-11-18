<#
    run.ps1 - Run all Magely unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies) that load the addon
    files against tests/wow_stubs.lua. WoW uses Lua 5.1, so the tests do too -
    not the newer Lua that may be first on PATH.

    The scaffolding is WowTestKit, at the commit and client build
    tests/kit.pin names. tests/kit.ps1 puts that commit in
    %LOCALAPPDATA%\WowTestKit\<sha> (or, with -KitDev, uses the ..\WowTestKit
    working copy), and this script hands off to the kit's runner, which
    syntax-checks the files (with the luac beside -Lua, which must exist) and
    runs every tests/test_*.lua.

    Magely embeds two libraries, loaded before its own files: LibGlass-1.0
    (the glass material) and LibGroupBuffs-1.0 (the compat layer, engine and
    window, which draws with LibGlass). The tests read each from a checkout
    next to this repository - ../LibGlass and ../LibGroupBuffs - or from
    -LibGlass / $env:LIBGLASS and -Library. There is no vendored copy to fall
    back to: a stale one would let the suite pass against code that no longer
    ships.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -Library "D:\src\LibGroupBuffs" -LibGlass "D:\src\LibGlass"
        pwsh tests/run.ps1 -KitDev       # against ..\WowTestKit, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Library = "",
    [string]$LibGlass = "",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

# The syntax check is required here, as it was before the kit: the kit's
# runner only warns ("luac -p SKIPPED") when there is no luac.exe beside
# lua.exe, and a skipped check that still ends green is how it once looked
# green while never running.
$luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
if (-not (Test-Path $luac)) {
    Write-Error "luac (Lua 5.1) not found at: $luac - the syntax check is required; install it beside $Lua"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Library) { $Library = Join-Path (Split-Path -Parent $RepoRoot) "LibGroupBuffs" }
if (-not (Test-Path (Join-Path $Library "LibGroupBuffs-1.0.xml"))) {
    Write-Error ("LibGroupBuffs-1.0 not found at $Library. Clone " +
        "https://github.com/Spotnick2/LibGroupBuffs next to this repository, or pass -Library.")
    exit 1
}
$Library = (Resolve-Path $Library).Path
$env:LIBGROUPBUFFS = $Library

if (-not $LibGlass) {
    $LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
}
if (-not (Test-Path (Join-Path $LibGlass "LibGlass-1.0.xml"))) {
    Write-Error ("LibGlass-1.0 not found at $LibGlass. Clone " +
        "https://github.com/Spotnick2/LibGlass next to this repository, or set LIBGLASS / pass -LibGlass.")
    exit 1
}
$LibGlass = (Resolve-Path $LibGlass).Path
$env:LIBGLASS = $LibGlass

# Say which checkout the tests actually ran against, and whether it is the one
# a release would ship. A mismatch is normal while working on a library, so it
# is a warning, never a failure: tests/test_manifest.lua is what checks the
# pins themselves, and CI tests exactly the pinned commits. The comparison is
# tests/pins.ps1, shared with Tools/deploy.ps1.
. (Join-Path $PSScriptRoot "pins.ps1")
function Show-Pin {
    param([string]$Name, [string]$Path, [string]$Root)
    $s = Get-PinState -Lua $Lua -RepoRoot $RepoRoot -Path $Path -Root $Root
    $pinText = if ($s.Pin) { $s.Pin } else { "NOTHING" }
    if ($s.AtPin) {
        Write-Host "${Name}: $Root @ $($s.Revision) (the .pkgmeta pin, $pinText)" -ForegroundColor DarkGray
    } else {
        Write-Host ("WARNING: ${Name} at $Root @ $($s.Revision) is not the .pkgmeta pin ($pinText)" +
            ", or has uncommitted changes; CI tests the pin") -ForegroundColor Yellow
    }
}
Show-Pin -Name "LibGlass" -Path "Libs/LibGlass-1.0" -Root $LibGlass
Show-Pin -Name "LibGroupBuffs" -Path "Libs/LibGroupBuffs-1.0" -Root $Library

# The kit's runner syntax-checks the TOC's Lua files; these go with them. A
# parse error in LibGroupBuffs would show up as a confusing load failure
# inside every test. Its files come from tests/libfiles.lua, the one reader of
# its XML that the harness, deploy.ps1 and CI use too, so a new file cannot be
# left unchecked. LibGlass is checked in its own repository, and loading it is
# the first thing every test does.
$libFiles = & $Lua (Join-Path $PSScriptRoot "libfiles.lua") $Library load $LibGlass
if ($LASTEXITCODE -ne 0) { Write-Host "LibGroupBuffs file list FAILED" -ForegroundColor Red; exit 1 }
$extra = @($libFiles | ForEach-Object { Join-Path $Library $_ })

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "Magely.toc" -Extra $extra -Lua $Lua
exit $LASTEXITCODE
