------------------------------------------------------------
-- test_config_seam.lua - one write path for MagelyDB, and the two checks
-- that watch for the client being fixed or updated.
--
-- Nothing an addon writes survives a real restart on this build. Until
-- Blizzard fixes it, every settings change goes through Magely_SetConfig so
-- the fix - or the migration it needs - lands in one place.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config_seam.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

local BROKEN = TC.SV_BROKEN_ON_BUILD
local MEASURED = TC.MEASURED_ON_BUILD
local FIXED = "70123"   -- any build other than the two above

-- Pinned independently of the source: the checks below take their builds
-- from it, so a stale constant would pass them all. 69977 is the build of the
-- newest API dump, re-checked against 69913 in the porting notes - the same
-- API surface, and SavedVariables still broken. Bump this with the constants
-- after re-measuring, never to make a test pass.
H.eq(MEASURED, "69977", "MEASURED_ON_BUILD is the build the notes were last checked on")
H.eq(BROKEN, "69977", "SV_BROKEN_ON_BUILD is the newest build SavedVariables are measured broken on")

------------------------------------------------------------
-- The setters
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()

local changed = {}
local realHook = Magely_OnConfigChanged
Magely_OnConfigChanged = function(key) changed[#changed + 1] = key end

Magely_SetConfig("frameAlpha", 0.5)
H.eq(MagelyDB.frameAlpha, 0.5, "SetConfig assigns")
H.eq(changed[#changed], "frameAlpha", "and reports the key")

-- Set first, so clearing it is an actual change the test can see fail.
Magely_SetConfig("pos", { point = "RIGHT", x = 1, y = 2 })
H.check(MagelyDB.pos ~= nil, "a position is stored")
Magely_SetConfig("pos", nil)
H.eq(MagelyDB.pos, nil, "SetConfig can clear a key that was set")
H.eq(changed[#changed], "pos", "and reports the clear")

-- An unchanged value is not a change. The window sets `visible` on every
-- refresh; without this the hook runs on the aura hot path.
local count = #changed
Magely_SetConfig("frameAlpha", 0.5)
H.eq(#changed, count, "setting the same value again does not report")

-- The learned-duration cache. Reading never writes - the engine asks on the
-- aura hot path - so a table left by another build answers nothing and stays
-- as it is until something is learned on this one. Then it is replaced once,
-- and that one write is reported once.
local stale = { build = "old", ["Arcane Intellect"] = 1800 }
MagelyDB.learnedDurations = stale
count = #changed
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), nil, "another build's duration is not used")
H.eq(#changed, count, "and reading it reports nothing")
H.check(MagelyDB.learnedDurations == stale, "and writes nothing")
Magely_LearnDuration("Arcane Intellect", 1200)
H.check(MagelyDB.learnedDurations ~= stale, "learning on this build replaces the table")
H.eq(#changed, count + 1, "reported exactly once for the replacement and the value together")
H.eq(changed[#changed], "learnedDurations", "under the table's key")
count = #changed
Magely_LearnDuration("Arcane Intellect", 1200)
H.eq(#changed, count, "re-learning the same value is not a change")
Magely_LearnDuration("Arcane Intellect", 900)
H.eq(#changed, count + 1, "a new value is")

-- EnsureDefaults' own writes reach the hook too: it is where the SavedVariables
-- fix or a migration lands, and a value it never heard about would never reach
-- a new store.
MagelyDB = {}
count = #changed
Magely_EnsureDefaults()
local seeded = {}
for i = count + 1, #changed do seeded[changed[i]] = true end
for key in pairs(TC.DEFAULTS) do
    H.check(seeded[key], "seeding " .. key .. " is reported")
end
count = #changed
Magely_EnsureDefaults()
H.eq(#changed, count, "a second run seeds nothing and reports nothing")
MagelyDB.amplifyMode = "boss"
Magely_EnsureDefaults()
H.eq(changed[#changed], "amplifyMode", "repairing an unknown Amplify mode is reported")
H.eq(#changed, count + 1, "and only that")
count = #changed
MagelyDB.dampenInstances["Scholomance"] = nil
Magely_EnsureDefaults()
H.eq(changed[#changed], "dampenInstances", "backfilling an instance is reported under its map")
H.eq(#changed, count + 1, "once, for the map")

-- One instance flag is written through the setter's nested form, and
-- reported under the map's own key, which is what is saved.
count = #changed
Magely_SetInstance("amplify", "Scholomance", true)
H.eq(MagelyDB.amplifyInstances["Scholomance"], true, "Magely_SetInstance writes the flag")
H.eq(changed[#changed], "amplifyInstances", "and reports the map")
Magely_SetInstance("amplify", "Scholomance", true)
H.eq(#changed, count + 1, "setting the same flag again does not report")

MagelyDB = nil
Magely_SetConfig("lockFrame", true)
H.eq(MagelyDB and MagelyDB.lockFrame, true, "SetConfig survives a missing table")

Magely_OnConfigChanged = realHook

------------------------------------------------------------
-- The source scan
--
-- A behavioural test cannot catch a new direct write: it works perfectly well.
-- So every file the TOC loads is read, and any assignment into Magely's
-- saved tables outside a `config-owner` region fails the run.
--
-- The scanner is LibGroupBuffs' tests/config_scan.lua, loaded from the same
-- library checkout the rest of the suite runs against (CI clones the pinned
-- tag). Its own tests cover the shapes it must catch; the cases here only
-- prove it is wired to Magely's names.
--
-- Files the port has not reached (H.NOT_YET_PORTED) are skipped: the TBC
-- Magely.lua writes MagelyDB directly throughout, and slice 3 replaces it.
-- Until then only the bridge and the config are scanned.
------------------------------------------------------------

local SAVED = { "MagelyDB", "MagelySVCheck" }
local CS = dofile(H.libraryRoot() .. "/tests/config_scan.lua")

H.eq(#CS.Scan("synthetic", "MagelyDB.lockFrame = true", SAVED), 1,
    "the scanner catches a direct MagelyDB write")
H.eq(#CS.Scan("synthetic", "MagelySVCheck.svLoadCheck = {}", SAVED), 1,
    "and a direct MagelySVCheck write")
H.eq(#CS.Scan("synthetic", "local p = MagelyDB.pos", SAVED), 0, "but not a read")

-- Every file the TOC loads, read from the TOC so a new one cannot be missed.
local files = {}
for _, path in ipairs(H.tocFiles()) do
    if not H.NOT_YET_PORTED[path] then files[#files + 1] = path end
end
H.check(#files >= (H.NOT_YET_PORTED["Magely.lua"] and 2 or 3), "the ported files are scanned: " .. table.concat(files, ", "))

-- Owner regions must stay few, or the scan stops meaning anything. Each file's
-- count is pinned, so adding one has to be done here on purpose.
local expectedRegions = { ["MagelyConfig.lua"] = 3 }
for _, path in ipairs(files) do
    local src = H.readFile(path)
    H.check(src ~= nil, path .. " is readable")
    local bad, regions = CS.Scan(path, src or "", SAVED)
    H.check(#bad == 0, path .. " writes its saved tables only through the setters: " ..
        table.concat(bad, " | "))
    H.eq(regions, expectedRegions[path] or 0, path .. " has the expected owner regions "
        .. "(MagelyConfig: the saved-table accessors, EnsureDefaults, the duration cache)")
end

------------------------------------------------------------
-- Magely is class-specific
--
-- On any other class it registers no options page, creates no saved table and
-- says nothing in chat: a build notice from an addon that does nothing on this
-- character is noise.
------------------------------------------------------------

WoW.reset()
WoW.build = "70123"                 -- not the measured build: a Mage would be warned
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "DRUID" })
MagelyDB, MagelySVCheck = nil, nil
local panelFrame = _G["MagelyOptionsPanel"]
panelFrame._category = nil
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.eq(#WoW.messages, 0, "a Druid hears nothing from Magely: " .. table.concat(WoW.messages, " | "))
H.eq(MagelyDB, nil, "gets no saved table")
H.eq(MagelySVCheck, nil, "in either scope")
H.eq(panelFrame._category, nil, "and no options page")
H.eq(Magely_IsBuffEnabled("intellect"), true, "while the accessors still answer without a table")
-- Nor does zoning do anything for it: no instance check, no rebuild asked.
WoW.instanceName, WoW.instanceType = "Some New Dungeon", "party"
WoW.dispatch("ZONE_CHANGED_NEW_AREA")
H.eq(#WoW.messages, 0, "and zoning into a dungeon says nothing either")
WoW.instanceName, WoW.instanceType = "", nil

WoW.SetUnit("player", { name = "Karuzo Elegia", class = "MAGE" })
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(MagelyDB ~= nil, "a Mage gets the saved table")
H.check(panelFrame._category ~= nil, "and the options page")
H.check(table.concat(WoW.messages, " "):find("tested on", 1, true) ~= nil,
    "and the build notice on a build Magely was not measured on")

------------------------------------------------------------
-- svLoadCheck: has Blizzard fixed it?
------------------------------------------------------------

H.eq(TC.DEFAULTS.svLoadCheck, nil,
    "svLoadCheck is NOT in DEFAULTS - if it were, EnsureDefaults would recreate it " ..
    "every session and the check could never tell a real load from a fresh start")

local function said(fromIndex)
    if #WoW.messages <= fromIndex then return "" end
    return table.concat(WoW.messages, " | ", fromIndex + 1, #WoW.messages)
end

local function freshSession(build)
    WoW.reset()
    WoW.build = build
    MagelyDB, MagelySVCheck = nil, nil
    Magely_EnsureDefaults()
end

-- Today, broken build, nothing loaded: nothing announced, markers written.
freshSession(BROKEN)
local before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
H.eq(said(before), "", "no marker at login, nothing announced - today's state")
H.check(type(MagelyDB.svLoadCheck) == "table", "the per-character marker is written")
H.check(type(MagelySVCheck.svLoadCheck) == "table", "and the account-wide one")
H.eq(MagelyDB.svLoadCheck.build, BROKEN, "with the build it was written on")

-- The broken build, marker still in memory: that is a relog or a /reload
-- being served from the client's cache. Neither may announce.
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
H.eq(said(before), "",
    "on the broken build a returning marker is the client's cache, not a fix")
Magely_HandleEnteringWorld(false, true)
H.eq(said(before), "", "and a /reload never announces")

-- A zone change is neither, and must not touch the marker.
local marker = MagelyDB.svLoadCheck
Magely_HandleEnteringWorld(false, false)
H.check(MagelyDB.svLoadCheck == marker, "a zone change leaves the marker alone")

-- The fix: a new build, and the marker came back on a real login.
WoW.build = FIXED
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
local msg = said(before)
H.check(msg:find("came back", 1, true), "a real login on a new build announces it: " .. msg)
H.check(msg:find("fully exited", 1, true), "conditional on a full exit: " .. msg)
H.check(msg:find("proves nothing", 1, true), "and says a relog or /reload proves nothing: " .. msg)
H.check(msg:find("per-character", 1, true) and msg:find("account-wide", 1, true),
    "naming the scopes that came back: " .. msg)
H.check(msg:find(FIXED, 1, true), "and the build: " .. msg)

-- Once only: the latch persists by then, because the store works.
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
H.check(not said(before):find("came back", 1, true), "it does not repeat at the next login")

-- Account-wide fixed on its own is worth knowing: it is where settings would
-- move back to.
freshSession(FIXED)
MagelySVCheck = { svLoadCheck = { stamp = "then", build = FIXED } }
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find("account-wide", 1, true) and not msg:find("per-character", 1, true),
    "a fix to account-wide storage alone is reported as that: " .. msg)

-- Wired to the real event, not just callable.
freshSession(BROKEN)
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(type(MagelyDB.svLoadCheck) == "table", "PLAYER_ENTERING_WORLD drives the check")

------------------------------------------------------------
-- MEASURED_ON_BUILD: did the client update?
------------------------------------------------------------

freshSession(MEASURED)
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
H.eq(said(before), "", "the measured build is silent")

freshSession(FIXED)
before = #WoW.messages
Magely_HandleEnteringWorld(false, true)
H.check(not said(before):find("tested on", 1, true), "a /reload never shows the build warning")
before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
H.check(not said(before):find("tested on", 1, true),
    "nor does PLAYER_LOGIN, which fires on /reload too")

before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find(FIXED, 1, true) and msg:find(MEASURED, 1, true),
    "a real login on a new build warns, naming both: " .. msg)
H.check(msg:find("report", 1, true), "worded for players: " .. msg)
H.check(not msg:find("MEASURED_ON_BUILD", 1, true),
    "with no developer instructions a player cannot act on: " .. msg)

-- Not latched: it repeats at every real login until MEASURED_ON_BUILD is
-- bumped. A notice shown once and missed would leave the addon running on
-- stale findings with nothing left to say so.
before = #WoW.messages
Magely_HandleEnteringWorld(true, false)
H.check(said(before):find("tested on", 1, true),
    "it warns again at the next real login, until someone re-measures")
H.eq(MagelyDB.warnedBuild, nil, "and records nothing that could silence it")

H.done("test_config_seam")
