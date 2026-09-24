------------------------------------------------------------
-- test_config.lua - saved variables: defaults, the Amplify and Dampen modes,
-- the instance list, the learned durations, and the accessors the engine and
-- window read.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

------------------------------------------------------------
-- Defaults on a fresh install
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()

H.check(MagelyDB ~= nil, "a missing MagelyDB is created")
H.eq(MagelyDB.trackIntellect, true, "Arcane Intellect tracked by default")
H.eq(MagelyDB.trackAmplify, true, "Amplify Magic tracked by default")
H.eq(MagelyDB.trackDampen, true, "Dampen Magic tracked by default")
H.eq(MagelyDB.amplifyMode, "detect", "Amplify shows when detected, by default")
H.eq(MagelyDB.dampenMode, "detect", "and so does Dampen")
H.eq(MagelyDB.showSolo, false, "solo display off by default")
H.eq(MagelyDB.trackPets, true, "pets tracked by default")
H.eq(MagelyDB.frameAlpha, 0.96, "near-opaque by default")
H.eq(MagelyDB.popoverSide, "auto", "the popover picks its side by default")
H.eq(MagelyDB.lockFrame, false, "unlocked by default")
H.eq(MagelyDB.showClickHints, true, "hints are on by default - they exist to be discovered")
H.eq(MagelyDB.visible, nil, "the window's own state is not a setting to default")
H.eq(MagelyDB.pos, nil, "nor is its position: nil means 'never placed'")
H.eq(TC.DEFAULTS.svLoadCheck, nil, "and the load check's marker is never a default")
for _, key in ipairs({ "cooldownPane", "trackInnervate", "innervateDebug", "trackPowerInfusion",
                       "cooldownSpamProtect" }) do
    H.eq(TC.DEFAULTS[key], nil, key .. " is gone with the cooldown pane, until it returns")
end

-- The user's own settings survive a second run.
MagelyDB.trackIntellect = false
MagelyDB.frameAlpha = 0.5
MagelyDB.amplifyMode = "always"
MagelyDB.dampenMode = "instance"
Magely_EnsureDefaults()
H.eq(MagelyDB.trackIntellect, false, "a changed setting is not reset")
H.eq(MagelyDB.frameAlpha, 0.5, "...including the slider")
H.eq(MagelyDB.amplifyMode, "always", "...and the Amplify mode")
H.eq(MagelyDB.dampenMode, "instance", "...and the Dampen mode")

------------------------------------------------------------
-- The two modes
------------------------------------------------------------

local count = 0
for _ in pairs(TC.BUFF_MODES) do count = count + 1 end
H.eq(count, 3, "three modes: always, detect, instance")
for mode in pairs(TC.BUFF_MODES) do
    MagelyDB.amplifyMode, MagelyDB.dampenMode = mode, mode
    H.eq(Magely_GetBuffMode("amplify"), mode, "the Amplify '" .. mode .. "' mode reads back")
    H.eq(Magely_GetBuffMode("dampen"), mode, "and the Dampen one")
end
H.eq(Magely_GetBuffMode("intellect"), nil, "Intellect has no mode: it always shows")

-- A value this build does not know (a TBC-era saved table, a typo) reads as
-- the default, and EnsureDefaults repairs it, so the panel always has a radio
-- to check. Each buff independently.
MagelyDB.amplifyMode = "boss"
MagelyDB.dampenMode = "always"
H.eq(Magely_GetBuffMode("amplify"), "detect", "an unknown mode reads as the default")
Magely_EnsureDefaults()
H.eq(MagelyDB.amplifyMode, "detect", "and EnsureDefaults repairs the saved value")
H.eq(MagelyDB.dampenMode, "always", "without touching the other buff's")
MagelyDB = nil
H.eq(Magely_GetBuffMode("dampen"), "detect", "with no saved table at all, too")

------------------------------------------------------------
-- Buff toggles
------------------------------------------------------------

MagelyDB = nil
Magely_EnsureDefaults()
for _, pair in ipairs({ { "intellect", "trackIntellect" }, { "amplify", "trackAmplify" },
                        { "dampen", "trackDampen" } }) do
    H.eq(Magely_IsBuffEnabled(pair[1]), true, pair[1] .. " enabled by default")
    MagelyDB[pair[2]] = false
    H.eq(Magely_IsBuffEnabled(pair[1]), false, "and disabled by its own checkbox")
end
H.eq(Magely_IsBuffEnabled("something else"), true, "an unknown buff is not hidden by accident")
MagelyDB = nil
H.eq(Magely_IsBuffEnabled("intellect"), true, "with no saved table, everything is enabled")

------------------------------------------------------------
-- The instance list
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()

H.check(#TC.INSTANCE_DB >= 30, "Forever's instance list is carried: " .. #TC.INSTANCE_DB)
local seen, amp, damp = {}, 0, 0
for _, entry in ipairs(TC.INSTANCE_DB) do
    local name = entry[1]
    H.check(not seen[name], name .. " is listed once")
    seen[name] = true
    H.check(entry[2] == "Raids" or entry[2] == "Dungeons", name .. " has a category")
    H.check(type(entry[3]) == "boolean" and type(entry[4]) == "boolean", name .. " has two defaults")
    H.check(type(entry[5]) == "string" and entry[5] ~= "", name .. " has advice to hover")
    H.check(not name:find("\226\128\153", 1, true), name .. " uses ASCII apostrophes, as the client does")
    H.eq(MagelyDB.amplifyInstances[name], entry[3], name .. " seeds its Amplify default")
    H.eq(MagelyDB.dampenInstances[name], entry[4], name .. " seeds its Dampen default")
    if entry[3] then amp = amp + 1 end
    if entry[4] then damp = damp + 1 end
end
H.check(amp > 0 and damp > 0, "some instances suit each buff")
-- TBC's instances are dead content here; carrying them would list places no
-- one can zone into.
for _, tbc in ipairs({ "Karazhan", "Black Temple", "The Shattered Halls", "Magisters' Terrace" }) do
    H.check(not seen[tbc], tbc .. " (TBC) is not listed")
end
-- Forever's own, from Priestly's measured list.
H.check(seen["Ruins of Lordaeron"], "Ruins of Lordaeron, measured in game by Priestly, is listed")
H.eq(MagelyDB.amplifyInstances["Ruins of Lordaeron"], false,
    "and Forever's uncatalogued instances start unchecked")

-- A player's choice survives the next EnsureDefaults; a missing entry is
-- backfilled; an entry the list no longer names is kept.
Magely_SetInstance("amplify", "Scholomance", true)
MagelyDB.dampenInstances["Stratholme"] = nil
MagelyDB.dampenInstances["An Instance From Some Other Build"] = true
Magely_EnsureDefaults()
H.eq(MagelyDB.amplifyInstances["Scholomance"], true, "a changed flag is not reset")
H.eq(MagelyDB.dampenInstances["Stratholme"], true, "a missing one is backfilled from its default")
H.eq(MagelyDB.dampenInstances["An Instance From Some Other Build"], true,
    "and one the list does not name is not pruned")

-- A saved map that is not a table is replaced rather than indexed.
MagelyDB.amplifyInstances = "broken"
Magely_EnsureDefaults()
H.eq(type(MagelyDB.amplifyInstances), "table", "a broken instance map is rebuilt")
H.eq(MagelyDB.amplifyInstances["Blackrock Depths"], true, "with its defaults")

------------------------------------------------------------
-- Where am I? The instance check
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()
MagelyDB.amplifyMode, MagelyDB.dampenMode = "instance", "instance"
TC.forgetReported()

WoW.instanceName, WoW.instanceType = "Scholomance", "party"
TC.CheckCurrentInstance()
H.eq(TC.inInstance("amplify"), false, "Scholomance is not an Amplify instance by default")
H.eq(TC.inInstance("dampen"), true, "but it is a Dampen one")
H.eq(Magely_ShouldShowBuff("amplify", nil, nil), false, "so by instance, Amplify stays hidden")
H.eq(Magely_ShouldShowBuff("dampen", nil, nil), true, "and Dampen shows")

WoW.instanceName, WoW.instanceType = "The Deadmines", "party"
TC.CheckCurrentInstance()
H.eq(Magely_ShouldShowBuff("amplify", nil, nil), true, "in the Deadmines Amplify shows")
H.eq(Magely_ShouldShowBuff("dampen", nil, nil), false, "and Dampen does not")

-- Outdoors the live client hands back the CONTINENT with instanceType
-- "none", not an empty name.
WoW.instanceName, WoW.instanceType = "Eastern Kingdoms", "none"
MagelyDB.amplifyInstances["Eastern Kingdoms"] = true
TC.CheckCurrentInstance()
H.eq(TC.inInstance("amplify"), false, "a continent with instanceType 'none' is not an instance")
MagelyDB.amplifyInstances["Eastern Kingdoms"] = nil
WoW.instanceName, WoW.instanceType = "", nil
TC.CheckCurrentInstance()
H.eq(TC.inInstance("dampen"), false, "and nor is nowhere at all")

-- An instance the list does not know is said once, only for a dungeon or
-- raid, and only to someone using "by instance".
local function said(fromIndex)
    return table.concat(WoW.messages, " | ", fromIndex + 1, math.max(fromIndex, #WoW.messages))
end
local before = #WoW.messages
WoW.instanceName, WoW.instanceType = "Some New Dungeon", "party"
TC.CheckCurrentInstance()
H.check(said(before):find("Some New Dungeon", 1, true), "an unknown dungeon is reported: " .. said(before))
before = #WoW.messages
TC.CheckCurrentInstance()
H.eq(said(before), "", "once per session")
WoW.instanceName, WoW.instanceType = "Warsong Gulch", "pvp"
TC.CheckCurrentInstance()
H.eq(said(before), "", "a battleground is not asked about")
MagelyDB.amplifyMode, MagelyDB.dampenMode = "detect", "always"
WoW.instanceName, WoW.instanceType = "Another New Raid", "raid"
TC.CheckCurrentInstance()
H.eq(said(before), "", "nor is anything, to a player using neither buff's 'by instance' mode")
MagelyDB.dampenMode = "instance"
TC.CheckCurrentInstance()
H.check(said(before):find("Another New Raid", 1, true),
    "and turning one on later still gets the report - it was not marked as told: " .. said(before))

-- Setting a flag goes through the setter, one instance and one buff at a time.
Magely_SetInstance("dampen", "Another New Raid", true)
TC.CheckCurrentInstance()
H.eq(TC.inInstance("dampen"), true, "a newly checked instance counts at the next check")
H.eq(TC.inInstance("amplify"), false, "for that buff only")
Magely_SetInstance("nonsense", "Another New Raid", true)
H.eq(MagelyDB.nonsenseInstances, nil, "an unknown buff name writes nothing")

------------------------------------------------------------
-- Detect mode
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
local groups = { [1] = { { unit = "player" }, { unit = "party1" } } }
local ord = { 1 }

-- The names come from Magely.lua, resolved from spell IDs; until then nothing
-- can be matched.
Magely.auraNames = nil
WoW.SetAura("party1", "Amplify Magic", 600, 400)
H.eq(Magely_ShouldShowBuff("amplify", groups, ord), false,
    "without resolved names nothing is detected")

Magely.auraNames = { amplify = { "Amplify Magic" }, dampen = { "Dampen Magic" } }
H.eq(Magely_ShouldShowBuff("amplify", groups, ord), true, "Amplify on a member shows its row")
H.eq(Magely_ShouldShowBuff("dampen", groups, ord), false, "and not Dampen's: each buff on its own")
H.eq(Magely_ShouldShowBuff("amplify", nil, nil), false, "with no roster there is nothing to detect")

-- Both at once: the TBC build could show both rows, and so can this one.
WoW.SetAura("player", "Dampen Magic", 600, 300)
H.eq(Magely_ShouldShowBuff("dampen", groups, ord), true, "Dampen on another member shows its row too")
H.eq(Magely_ShouldShowBuff("amplify", groups, ord), true, "alongside Amplify's")

-- Combat: a read the client refuses is not evidence nobody has it.
WoW.ClearAuras("party1")
WoW.ClearAuras("player")
H.eq(Magely_ShouldShowBuff("amplify", groups, ord), false, "nobody has it: no row")
H.secrecy(true)
H.eq(Magely_ShouldShowBuff("amplify", groups, ord), true,
    "an unreadable roster keeps the row rather than dropping it at the pull")
H.secrecy(false)

H.eq(Magely_ShouldShowBuff("intellect", groups, ord), true, "Intellect has no rule of its own")
MagelyDB.amplifyMode = "always"
H.eq(Magely_ShouldShowBuff("amplify", nil, nil), true, "'always' needs no roster at all")
MagelyDB = nil
H.eq(Magely_ShouldShowBuff("dampen", groups, ord), false, "no saved table: the optional rows stay off")
H.eq(Magely_ShouldShowBuff("intellect", groups, ord), true, "while Intellect still shows")
Magely.auraNames = nil

------------------------------------------------------------
-- Duration store is per client build, keyed by spell name
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()

H.check(Magely_GetLearnedDuration("Arcane Intellect") == nil, "nothing learned yet")
Magely_LearnDuration("Arcane Intellect", 1800)
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), 1800, "a learned duration is stored")
Magely_LearnDuration("Arcane Intellect", 900)
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), 900, "and replaced downward on a nerf")
Magely_LearnDuration("Arcane Intellect", 0)
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), 900, "a nonsense value is ignored")
Magely_LearnDuration("Arcane Brilliance", 3600)
H.eq(Magely_GetLearnedDuration("Arcane Brilliance"), 3600,
    "the group form of the same buff is stored separately")
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), 900, "...without overwriting the single form")
H.check(pcall(Magely_LearnDuration, nil, 600), "a nil spell name is ignored rather than erroring")
H.eq(Magely_GetLearnedDuration(nil), nil, "and reads as nothing")

WoW.build = "70000"
Magely_EnsureDefaults()       -- a build change means a restart means a login
H.check(Magely_GetLearnedDuration("Arcane Intellect") == nil, "a new build resets the table")
Magely_LearnDuration("Arcane Intellect", 1200)
H.eq(Magely_GetLearnedDuration("Arcane Intellect"), 1200, "and starts learning again")

------------------------------------------------------------
-- The window's settings
------------------------------------------------------------

MagelyDB = nil
Magely_EnsureDefaults()
H.eq(Magely_PopoverSide(), "auto", "the popover side reads back")
MagelyDB.popoverSide = "right"
H.eq(Magely_PopoverSide(), "right", "an explicit side is reported back")
MagelyDB.popoverSide = nil
H.eq(Magely_PopoverSide(), "auto", "a missing key falls back to auto")

H.eq(Magely_FrameLocked(), false, "unlocked")
MagelyDB.lockFrame = true
H.eq(Magely_FrameLocked(), true, "locking is reported")
MagelyDB.lockFrame = nil
H.eq(Magely_FrameLocked(), false, "a missing key is unlocked, not a window nobody can move")

H.eq(Magely_ShowClickHints(), true, "hints on")
MagelyDB.showClickHints = false
H.eq(Magely_ShowClickHints(), false, "turning them off is respected")
MagelyDB.showClickHints = nil
H.eq(Magely_ShowClickHints(), true, "only an explicit false turns them off")

H.eq(Magely_GetFrameAlpha(), 0.96, "the default opacity")
MagelyDB.frameAlpha = 0.4
H.eq(Magely_GetFrameAlpha(), 0.4, "a chosen opacity")

H.eq(Magely_ShowSolo(), false, "solo off")
MagelyDB.showSolo = true
H.eq(Magely_ShowSolo(), true, "solo on")
H.eq(Magely_TrackPets(), true, "pets on")
MagelyDB.trackPets = false
H.eq(Magely_TrackPets(), false, "pets off")

MagelyDB = nil
H.eq(Magely_GetFrameAlpha(), 0.96, "no saved table: default opacity")
H.check(not Magely_FrameLocked(), "no saved table: unlocked")
H.check(Magely_ShowClickHints(), "no saved table: hints on")
H.check(not Magely_ShowSolo(), "no saved table: not solo")

H.done("test_config")
