------------------------------------------------------------
-- test_probe.lua - Tools/MagelyProbe, the in-game release check
-- (/fp steps mp check), a ForeverProbe module.
--
-- A check that passes a step it never saw, or leaves the owner's settings
-- changed, is worse than none. So the procedure is run end to end here: its
-- waits read Magely's real rows, its checks fail when a mode shows the wrong
-- rows, and the settings it changes come back exactly.
--
-- ForeverProbe is private and local (..\ForeverProbe, or $FOREVERPROBE): CI,
-- which cannot see it, sets FOREVERPROBE_OPTIONAL=1 and skips this file.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_probe.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.reset()
local FP = H.loadForeverProbe()
local T = H.loadAddon()

-- A Mage who knows every buff, alone (showSolo is what the check turns on).
MagelyDB = nil
Magely_EnsureDefaults()
MagelyDB.amplifyMode, MagelyDB.dampenMode, MagelyDB.showSolo = "detect", "instance", false
H.TeachSpells({ "INT_SINGLE", "INT_GROUP", "AMPLIFY", "DAMPEN" })
T.RefreshSpellData()
WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "MAGE" })
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()

local KNOWN = { [1459] = true, [23028] = true, [1008] = true, [604] = true }
rawset(_G, "IsPlayerSpell", function(id) return KNOWN[id] == true end)

local ns = {}
assert(loadfile("Tools/MagelyProbe/MagelyProbe.lua"))("MagelyProbe", ns)
WoW.dispatch("ADDON_LOADED", "MagelyProbe")
local P = ns._test

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local S = FP.Steps
-- A step's screenshot holds the procedure until the client has taken it,
-- which needs the wall clock to tick (ForeverProbe's Screenshots.lua). Here
-- it finishes at once, as a client that can't take one would.
FP.Screenshots.Take = function(_, _, done) if done then done(nil, "no screenshots under test") end end
local function record() return ForeverProbeDB.steps.records["MagelyProbe/check"] end
local function at() return record().at end
local function result(i) return record().results[i] end

------------------------------------------------------------
-- The module
------------------------------------------------------------

H.check(FP.byCmd.mp ~= nil and FP.byCmd.mp.name == "MagelyProbe", "it is /fp mp")
H.check(type(MagelyProbeDB) == "table" and type(MagelyProbeDB.log) == "table", "its log is bound at its ADDON_LOADED")
H.eq(rawget(_G, "MagelyProbe"), nil, "no global of its own")

local ok, detail = P.stateOK()
H.check(ok, "a Mage on r36+ and LibGlass r13+ who knows Amplify and Dampen is ready: " .. tostring(detail))
KNOWN[1008] = nil
ok, detail = P.stateOK()
H.check(not ok and detail:find("Amplify Magic unknown", 1, true), "without Amplify it says so: " .. tostring(detail))
KNOWN[1008] = true

-- The settings it changes come back exactly, through Magely's write path.
P.saveSettings()
P.setModes("always")
H.eq(MagelyDB.amplifyMode, "always", "setModes writes Magely's setting")
H.eq(MagelyDB.showSolo, true, "and shows the window solo")
H.check(P.restore(), "restore runs")
H.eq(MagelyDB.amplifyMode, "detect", "amplifyMode is back")
H.eq(MagelyDB.dampenMode, "instance", "dampenMode is back")
H.eq(MagelyDB.showSolo, false, "showSolo is back")
H.eq(P.db().saved, nil, "and nothing is left to restore")

------------------------------------------------------------
-- The procedure, end to end
------------------------------------------------------------

local function poll(times) for _ = 1, times or 1 do WoW.flushTimers(1); S.Poll() end end

H.check(pcall(fp, "steps mp check"), "the check starts")
S.Next()                                                       -- 1: the setup
H.eq(result(2).check, "PASS", "versions and known buffs pass")
H.check(P.db().saved ~= nil, "and the settings are saved before anything changes")
H.eq(at(), 3, "then /magely help")
S.Run()
H.eq(result(3).check, "PASS", "the spell report has nothing unresolved")

-- always
S.Run()                                                        -- 4: set always
poll()
H.eq(at(), 6, "always: both rows show, so the wait completes")
H.eq(MagelyDB.amplifyMode, "always", "(the mode was set)")

-- detect: nobody has them, then Amplify, then Dampen.
S.Run()                                                        -- 6: set detected
poll()
H.eq(at(), 8, "detected with nobody buffed: neither row, so the wait completes")
poll()
H.eq(at(), 8, "it waits for Amplify to land")
WoW.SetAura("player", "Amplify Magic", 600, 600, 1008)
WoW.dispatch("UNIT_AURA", "player")
poll(2)
H.eq(at(), 9, "the Amplify row appears and the wait completes")
WoW.SetAura("player", "Amplify Magic", nil)
WoW.SetAura("player", "Dampen Magic", 600, 600, 604)
WoW.dispatch("UNIT_AURA", "player")
poll(2)
H.eq(at(), 10, "then the Dampen row")
S.Answer(true)

-- instance, outdoors
S.Run()                                                        -- 11: set by instance
H.eq(result(11).check, "PASS", "the setting step runs outdoors")
poll()
H.eq(at(), 13, "outdoors neither row shows (Dampen is still on you, and doesn't count here)")
S.Skip() S.Skip() S.Skip()                                     -- no dungeon today
H.eq(at(), 16, "the dungeon steps can be skipped")

-- clicks
-- A cast from before the Arm must not count for the click.
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "g0", 1459)
S.Run()                                                        -- 16: arm
poll()
H.eq(at(), 17, "it waits for the click's cast")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "g1", 1459)
poll()
H.eq(at(), 18, "and goes on when it lands")
S.Skip() S.Skip()                                              -- alone: no party click
S.Answer(true)
poll()
H.eq(at(), 21, "it waits for combat")
WoW.inCombat = true
poll()
H.eq(at(), 22, "in combat it waits for a cast")
poll()
H.eq(at(), 22, "the out-of-combat click before it doesn't count")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "g2", 1459)
poll()
H.eq(at(), 23, "a cast in combat completes it")
S.Answer(true)
poll()
H.eq(at(), 24, "it waits for the end of combat")
WoW.inCombat = false
poll()
H.eq(result(25).check, "PASS", "Brilliance known and Arcane Powder in the footer")
S.Answer(true)
H.eq(result(27).check, "PASS", "the settings are put back")
H.eq(MagelyDB.amplifyMode, "detect", "amplifyMode is the owner's again")
H.eq(MagelyDB.showSolo, false, "and showSolo")
S.Stop()

------------------------------------------------------------
-- A mode showing the wrong rows fails
------------------------------------------------------------

WoW.SetAura("player", "Dampen Magic", nil)
fp("steps mp check")
S.Next()
S.Run()
S.Run()                                                        -- set always
-- A Magely that drops the Amplify row in "always" mode:
local realShould = Magely_ShouldShowBuff
Magely_ShouldShowBuff = function(defId, ...) if defId == "amplify" then return false end return realShould(defId, ...) end
for _ = 1, 12 do WoW.flushTimers(1); WoW.advance(1); S.Poll() end
H.eq(result(5).status, "timeout", "the always wait never completes, and times out")
Magely_ShouldShowBuff = realShould
S.Stop()
H.check(P.restore(), "restore by hand after a stopped check")
H.eq(MagelyDB.amplifyMode, "detect", "puts the owner's mode back")

H.eq(#WoW.messages > 0, true, "(the /magely commands it ran printed, as typed)")

H.done("test_probe")
