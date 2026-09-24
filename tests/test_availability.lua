------------------------------------------------------------
-- test_availability.lua - which buffs get a row, and what a click casts.
--
-- Arcane Brilliance is learned at 56, far above the beta's current cap, so for
-- now a mage knows Arcane Intellect and maybe Dampen Magic (12) and Amplify
-- Magic (18). Wiring a row to a spell the mage does not have is a dead click.
-- The TBC code decided this with per-def flags (always / needsKnown /
-- optional / leftUsesSingle); the library's availability and click mapping
-- replace all four, and the config's modes decide the rest.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_availability.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function defById(id)
    for _, d in ipairs(T.DEFS) do
        if d.id == id then return d end
    end
end

local function ids(defs)
    local out = {}
    for _, d in ipairs(defs) do out[#out + 1] = d.id end
    return table.concat(out, ",")
end

-- Amplify and Dampen default to "when detected", which with nobody buffed
-- hides them; "always" isolates availability from that rule.
local function setup(known, modes)
    WoW.reset()
    MagelyDB = nil
    Magely_EnsureDefaults()
    MagelyDB.amplifyMode = modes or "always"
    MagelyDB.dampenMode = modes or "always"
    H.TeachSpells(known)
    T.RefreshSpellData()
end

------------------------------------------------------------
-- The definitions are the library's shape
------------------------------------------------------------

H.eq(#T.DEFS, 3, "three buffs: Arcane Intellect, Amplify Magic, Dampen Magic")
local int, amp, damp = defById("intellect"), defById("amplify"), defById("dampen")
H.eq(int.snglID, H.SPELL.INT_SINGLE, "Arcane Intellect by its spell ID")
H.eq(int.grpID, H.SPELL.INT_GROUP, "with Arcane Brilliance as its group form")
H.eq(amp.snglID, H.SPELL.AMPLIFY, "Amplify Magic by its spell ID")
H.eq(amp.grpID, nil, "and no group form")
H.eq(damp.snglID, H.SPELL.DAMPEN, "Dampen Magic by its spell ID")
H.eq(damp.grpID, nil, "and no group form either")
for _, d in ipairs(T.DEFS) do
    for _, old in ipairs({ "always", "needsKnown", "optional", "leftUsesSingle" }) do
        H.eq(d[old], nil, d.id .. " carries no TBC flag '" .. old .. "'")
    end
    H.check(type(d.duration) == "number" and d.duration > 0, d.id .. " has a duration seed")
end

------------------------------------------------------------
-- Arcane Intellect only
------------------------------------------------------------

setup({ "INT_SINGLE" })
int = defById("intellect")
H.check(int.hasSingle == true, "Arcane Intellect is known")
H.check(int.hasGroup == false, "Arcane Brilliance is not")
H.eq(ids(T.ActiveDefs({}, {})), "intellect", "only the buff we can actually cast gets a row")

local primary, secondary = T.ClickSpells(int)
H.eq(primary, "Arcane Intellect",
    "left-click falls back to the single-target spell - never a dead primary click")
H.eq(secondary, "Arcane Intellect", "right-click is the same spell here")

------------------------------------------------------------
-- Brilliance learned: left-click becomes the group spell
------------------------------------------------------------

setup({ "INT_SINGLE", "INT_GROUP" })
primary, secondary = T.ClickSpells(defById("intellect"))
H.eq(primary, "Arcane Brilliance", "left-click prefers Arcane Brilliance")
H.eq(secondary, "Arcane Intellect", "right-click stays single-target")

------------------------------------------------------------
-- Amplify and Dampen: single-target on both clicks, which is what
-- leftUsesSingle did
------------------------------------------------------------

setup({ "INT_SINGLE", "INT_GROUP", "AMPLIFY", "DAMPEN" })
H.eq(ids(T.ActiveDefs({}, {})), "intellect,amplify,dampen",
    "both optional buffs get a row once known - at the same time")
for _, id in ipairs({ "amplify", "dampen" }) do
    primary, secondary = T.ClickSpells(defById(id))
    H.eq(primary, defById(id).sngl, id .. ": left-click casts the single spell")
    H.eq(secondary, defById(id).sngl, id .. ": and so does right-click - there is no group form")
end

setup({ "DAMPEN" })
H.eq(ids(T.ActiveDefs({}, {})), "dampen", "Dampen alone is enough for a Dampen row")

------------------------------------------------------------
-- Knowing nothing means no row at all
------------------------------------------------------------

setup({})
H.eq(ids(T.ActiveDefs({}, {})), "", "a mage who knows none of them gets no rows")

------------------------------------------------------------
-- The config layers on top of availability, not instead of it
------------------------------------------------------------

setup({ "INT_SINGLE", "AMPLIFY", "DAMPEN" })
MagelyDB.trackIntellect = false
H.eq(ids(T.ActiveDefs({}, {})), "amplify,dampen", "untracking Intellect removes its row")
MagelyDB.trackIntellect = true
MagelyDB.trackAmplify = false
H.eq(ids(T.ActiveDefs({}, {})), "intellect,dampen", "untracking Amplify removes only its row")
MagelyDB.trackAmplify = true
MagelyDB.trackDampen = false
H.eq(ids(T.ActiveDefs({}, {})), "intellect,amplify", "and Dampen likewise")

setup({ "INT_SINGLE" })
H.eq(ids(T.ActiveDefs({}, {})), "intellect",
    "no mode can conjure a row for a spell the mage does not have")

------------------------------------------------------------
-- The modes decide Amplify and Dampen, each on its own
--
-- Intellect has no mode: it always shows. The rest is the config's
-- Magely_ShouldShowBuff, tested fully in test_config; here it is wired in.
------------------------------------------------------------

WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
local groups = { [1] = { { unit = "player" }, { unit = "party1" } } }
local ord = { 1 }

setup({ "INT_SINGLE", "AMPLIFY", "DAMPEN" }, "detect")
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
H.eq(ids(T.ActiveDefs(groups, ord)), "intellect", "detect with nobody buffed: Intellect only")
WoW.SetAura("party1", "Dampen Magic", 600, 300)
H.eq(ids(T.ActiveDefs(groups, ord)), "intellect,dampen", "Dampen on a member brings its row")
WoW.SetAura("player", "Amplify Magic", 600, 300)
H.eq(ids(T.ActiveDefs(groups, ord)), "intellect,amplify,dampen", "and Amplify on another brings both")

MagelyDB.amplifyMode = "always"
MagelyDB.dampenMode = "instance"
WoW.instanceName, WoW.instanceType = "", nil
Magely._testConfig.CheckCurrentInstance()
H.eq(ids(T.ActiveDefs(groups, ord)), "intellect,amplify",
    "Amplify 'always' and Dampen 'by instance' outdoors: each follows its own mode")

-- detect reads the names resolved from spell IDs, which RefreshSpellData
-- publishes for the config.
H.eq(Magely.auraNames.amplify, defById("amplify").names, "the Amplify names are published")
H.eq(Magely.auraNames.dampen, defById("dampen").names, "and Dampen's")
H.eq(Magely.auraNames.intellect, nil, "Intellect has no mode, so no names are needed")

------------------------------------------------------------
-- Localized names come from the client, not from our literals
------------------------------------------------------------

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()
WoW.DefineSpell(1459, "Arkane Intelligenz")
WoW.Know(1459, "Arkane Intelligenz")
WoW.DefineSpell(604, "Magie dämpfen")
WoW.Know(604, "Magie dämpfen")
T.RefreshSpellData()
H.eq(defById("intellect").sngl, "Arkane Intelligenz", "the name is whatever the client says")
H.eq(defById("intellect").names[1], "Arkane Intelligenz", "and the aura lookup uses that name")
H.eq(Magely.auraNames.dampen[1], "Magie dämpfen", "and so does detect mode")

H.done("test_availability")
