-- /magely help ends with the spell report: the names Magely matches auras
-- against, as this client gave them (#48, #59). The library supplies the data
-- (Engine:SpellReport); these tests hold Magely's wording of it.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function help()
    WoW.messages = {}
    SlashCmdList.MAGELY("help")
    return table.concat(WoW.messages, "\n")
end

local function has(text, needle) return text:find(needle, 1, true) ~= nil end

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()
H.TeachSpells({ "INT_SINGLE" })
T.RefreshSpellData()
WoW.SetUnit("player", { name = "Mage", guid = "P", class = "MAGE" })
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers(); WoW.flushTimers()

------------------------------------------------------------
-- A healthy client: every name resolved, nothing to report.
------------------------------------------------------------
local out = help()
H.check(has(out, "Spell names, as this client gave them:"), "help ends with the spell report")
H.check(has(out, "locale enUS"), "the report names the locale")
H.check(has(out, "game build " .. WoW.build), "and the game build")
H.check(has(out, "library r" .. tostring(Magely.GB.MINOR)), "and the live library's MINOR")
H.check(out:find("intellect%s+single%s+Arcane Intellect\n") ~= nil,
    "a learned, resolved form is listed with no note")
H.check(out:find("intellect%s+group%s+Arcane Brilliance %- not learned") ~= nil,
    "an unlearned form says so")
H.check(has(out, "Amplify Magic") and has(out, "Dampen Magic"), "every buff Magely tracks is listed")
H.check(not has(out, "UNRESOLVED"), "no resolved name is flagged")
H.check(not has(out, "could not be read"), "no unresolved count on a healthy client")
H.check(not has(out, "unknown origin"), "no unknown-origin count on a healthy client")

------------------------------------------------------------
-- The two counts r34 keeps apart: a name still on its English
-- fallback (the #48 signature) and one built by an older library.
------------------------------------------------------------
local def = T.DEFS[1]
local single, group = def.snglFrom, def.grpFrom
def.snglFrom = "fallback"
def.grpFrom = "unknown"
out = help()
H.check(has(out, "(UNRESOLVED - English name)"), "a fallback name is flagged on its line")
H.check(has(out, "(provenance unknown)"), "an unknown-origin name is noted on its line")
H.check(has(out, "1 name(s) could not be read from the client."), "the unresolved count is said")
H.check(has(out, "1 name(s) of unknown origin"), "and the unknown-origin count, apart from it")
def.snglFrom, def.grpFrom = single, group

------------------------------------------------------------
-- Help is a slash command, and slash commands run in combat:
-- nothing in it may write to the protected window (r33 audit).
------------------------------------------------------------
T.ui:Open()
WoW.flushTimers()
WoW.inCombat = true
WoW.combatTouches = {}
help()
H.eq(#WoW.combatTouches, 0, "help in combat touches no protected frame")
WoW.inCombat = false

H.done("test_spell_report")
