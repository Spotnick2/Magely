------------------------------------------------------------
-- test_clicks.lua - what the secure buttons are actually wired to after a
-- rebuild.
--
-- This is the part that has to be right: a row whose spell1 attribute names
-- Arcane Brilliance when the mage does not have it is a click that does
-- nothing, and the frame gives no hint of it. Asserting the attributes is the
-- closest we can get to clicking without a game client. The mechanics are the
-- library's and tested there; this pins Magely's buffs onto them.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_clicks.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(known)
    WoW.reset()
    MagelyDB = nil
    Magely_EnsureDefaults()
    -- Amplify and Dampen shown regardless of who has them: this file is about
    -- how rows are wired, and when they appear is test_visibility's and
    -- test_config's.
    MagelyDB.amplifyMode, MagelyDB.dampenMode = "always", "always"
    H.TeachSpells(known)
    T.RefreshSpellData()

    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "MAGE" })
    WoW.SetUnit("party1", { name = "Sten Thornbeard", guid = "P1", class = "WARRIOR" })
    WoW.SetUnit("party2", { name = "Mirel Dawnsong", guid = "P2", class = "PRIEST" })
    WoW.groupMembers = 3
    T.UpdateUI()
    return T.rows()
end

local function activeRows(rows)
    local out = {}
    for _, r in ipairs(rows) do
        if r._active then out[#out + 1] = r end
    end
    return out
end

local function rowFor(defId)
    for _, r in ipairs(activeRows(T.rows())) do
        if r._def and r._def.id == defId then return r end
    end
end

------------------------------------------------------------
-- Arcane Intellect without Brilliance
------------------------------------------------------------

local rows = setup({ "INT_SINGLE" })
H.eq(#activeRows(rows), 1, "one row: the one buff this mage has")
local row = rowFor("intellect")
H.eq(row:GetAttribute("type1"), "spell", "left-click casts a spell")
H.eq(row:GetAttribute("spell1"), "Arcane Intellect",
    "left-click falls back to the single-target spell, never a Brilliance that does not exist")
H.eq(row:GetAttribute("spell2"), "Arcane Intellect", "right-click likewise")
local u1 = row:GetAttribute("unit1")
H.check(u1 == "player" or u1 == "party1" or u1 == "party2",
    "aimed at a group member, got " .. tostring(u1))
H.eq(row:GetAttribute("typerelease"), nil,
    "no typerelease: the press-and-hold path would cast a second time")

------------------------------------------------------------
-- The target follows who is actually missing the buff
------------------------------------------------------------

setup({ "INT_SINGLE" })
WoW.SetAura("player", "Arcane Intellect", 1800, 1500)
WoW.SetAura("party1", "Arcane Intellect", 1800, 1500)
T.UpdateUI()
row = rowFor("intellect")
H.eq(row:GetAttribute("unit2"), "party2", "right-click aims at the one missing it")
H.eq(row:GetAttribute("unit1"), "party2", "and so does left-click while there is no Brilliance")

-- Arcane Brilliance on someone counts as having the buff: one row, two auras.
setup({ "INT_SINGLE" })
WoW.SetAura("player", "Arcane Intellect", 1800, 1500)
WoW.SetAura("party1", "Arcane Brilliance", 3600, 3000)
T.UpdateUI()
row = rowFor("intellect")
H.eq(row:GetAttribute("unit2"), "party2", "a Brilliance from another mage is not re-buffed with Intellect")

------------------------------------------------------------
-- With Brilliance learned, left-click becomes the group cast
------------------------------------------------------------

setup({ "INT_SINGLE", "INT_GROUP" })
row = rowFor("intellect")
H.eq(row:GetAttribute("spell1"), "Arcane Brilliance", "left-click is Arcane Brilliance")
H.eq(row:GetAttribute("spell2"), "Arcane Intellect", "right-click stays single-target")

------------------------------------------------------------
-- Amplify and Dampen: the same spell on both buttons, both rows at once
------------------------------------------------------------

setup({ "INT_SINGLE", "INT_GROUP", "AMPLIFY", "DAMPEN" })
H.eq(#activeRows(T.rows()), 3, "a row per buff - Amplify and Dampen together")
for _, pair in ipairs({ { "amplify", "Amplify Magic" }, { "dampen", "Dampen Magic" } }) do
    row = rowFor(pair[1])
    H.check(row ~= nil, pair[2] .. " has its own row")
    H.eq(row:GetAttribute("spell1"), pair[2], pair[2] .. ": left-click - never Arcane Brilliance")
    H.eq(row:GetAttribute("spell2"), pair[2], pair[2] .. ": and right-click")
end

-- Each aims at whoever lacks its own buff, independently.
WoW.SetAura("player", "Amplify Magic", 600, 500)
WoW.SetAura("party1", "Amplify Magic", 600, 500)
WoW.SetAura("party2", "Dampen Magic", 600, 500)
WoW.SetAura("party1", "Dampen Magic", 600, 500)
T.UpdateUI()
H.eq(rowFor("amplify"):GetAttribute("unit2"), "party2", "Amplify aims at the one without Amplify")
H.eq(rowFor("dampen"):GetAttribute("unit2"), "player", "and Dampen at the one without Dampen")

------------------------------------------------------------
-- Nobody valid to cast on: clear the spell rather than cast on a corpse
------------------------------------------------------------

setup({ "INT_SINGLE" })
WoW.units.player.dead = true
WoW.units.party1.dead = true
WoW.units.party2.connected = false
T.UpdateUI()
row = rowFor("intellect")
H.check(row:GetAttribute("spell1") == nil, "no valid target -> no spell on left-click")
H.check(row:GetAttribute("spell2") == nil, "same for right-click")

------------------------------------------------------------
-- PreClick re-picks the target at click time; combat leaves it alone
------------------------------------------------------------

setup({ "INT_SINGLE" })
for _, u in ipairs({ "player", "party1", "party2" }) do WoW.SetAura(u, "Arcane Intellect", 1800, 1500) end
T.UpdateUI()
row = rowFor("intellect")
WoW.ClearAuras("party1")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "PreClick re-aims at whoever lost the buff")

WoW.inCombat = true
WoW.ClearAuras("party2")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "in combat the wiring is left alone")
WoW.inCombat = false

------------------------------------------------------------
-- Popover rows
------------------------------------------------------------

setup({ "INT_SINGLE", "INT_GROUP" })
row = rowFor("intellect")
T.UpdatePopover(row, {
    { unit = "player", name = "Karuzo Elegia",   class = "MAGE" },
    { unit = "party1", name = "Sten Thornbeard", class = "WARRIOR" },
}, row._def)
local prs = T.popRows()
H.eq(prs[1]:GetAttribute("unit1"), "player", "each popover row targets its own member")
H.eq(prs[2]:GetAttribute("unit1"), "party1", "...the second one too")
H.eq(prs[1]:GetAttribute("spell1"), "Arcane Brilliance", "left-click in the popover is Brilliance")
H.eq(prs[1]:GetAttribute("spell2"), "Arcane Intellect", "right-click is Intellect on that person")
H.check(prs[3]._active == false, "unused rows are released")

------------------------------------------------------------
-- Both mouse edges, on every button in both pools
--
-- The client's secure handler acts on exactly one edge, chosen by the
-- ActionButtonUseKeyDown CVar. One edge registered is a dead button for
-- anyone whose client acts on the other.
------------------------------------------------------------

setup({ "INT_SINGLE" })
local function assertBothEdges(button, what)
    local set = {}
    for _, e in ipairs(button._clicks or {}) do set[e] = true end
    H.eq(#(button._clicks or {}), 4, what .. " registers four click events")
    for _, e in ipairs({ "LeftButtonDown", "RightButtonDown", "LeftButtonUp", "RightButtonUp" }) do
        H.check(set[e], what .. " registers " .. e)
    end
end
assertBothEdges(T.rows()[1], "the first row")
assertBothEdges(T.rows()[#T.rows()], "the last row in the pool")
assertBothEdges(T.popRows()[1], "the first popover row")
assertBothEdges(T.popRows()[#T.popRows()], "the last popover row")
H.check(WoW.events[T.eventFrame()].CVAR_UPDATE == nil,
    "no CVAR_UPDATE handler - the registration is unconditional")

------------------------------------------------------------
-- Click hints describe what the click will actually do
------------------------------------------------------------

local function hintFor(r)
    WoW.clearTooltip()
    r._scripts.OnEnter(r)
    return WoW.tooltipText()
end

setup({ "INT_SINGLE", "DAMPEN" })
local hint = hintFor(rowFor("intellect"))
H.check(hint:find("Arcane Intellect"), "the hint names the spell: " .. hint)
H.check(not hint:find("Brilliance"), "and never a Brilliance this mage cannot cast: " .. hint)
hint = hintFor(rowFor("dampen"))
H.check(hint:find("Dampen Magic"), "the Dampen row's hint names Dampen Magic: " .. hint)
H.check(hint:find("Karuzo Elegia") or hint:find("Sten Thornbeard") or hint:find("Mirel Dawnsong"),
    "and who it lands on, since it is always single-target: " .. hint)
H.check(not hint:find("your party"), "never 'your party': Dampen has no group form: " .. hint)

setup({ "INT_SINGLE", "INT_GROUP" })
hint = hintFor(rowFor("intellect"))
H.check(hint:find("Arcane Brilliance") and hint:find("your party"),
    "with Brilliance known, left-click reads as the group cast: " .. hint)

MagelyDB.showClickHints = false
H.eq(hintFor(rowFor("intellect")), "", "turning hints off shows nothing")

H.done("test_clicks")
