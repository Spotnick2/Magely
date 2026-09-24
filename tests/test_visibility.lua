------------------------------------------------------------
-- test_visibility.lua - when the window opens itself, and when it must not.
--
-- Closing the window is a preference, and the addon also opens itself when you
-- join a group. Those two rules meet in a few places where the wrong one can
-- win: a deliberate close overwritten on the next login or roster update, and
-- a show asked for during combat dropped entirely. Magely decides these; the
-- library only carries them out.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_visibility.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(groupSize, class)
    WoW.reset()
    -- The addon's own module state survives between sections of this file,
    -- where a real login always starts with nothing on screen. Close first so
    -- each section is testing the open, not inheriting one.
    WoW.inCombat = false
    T.CloseUI(false)
    MagelyDB = nil
    Magely_EnsureDefaults()
    H.TeachSpells({ "INT_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = class or "MAGE" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = groupSize or 2
end

-- Logically open, which is what the addon's policy is about. In combat the
-- frame can still be on screen after a close, because the client refuses to
-- hide a frame that parents secure buttons.
local function shown()
    local main = T.mainFrame()
    return main ~= nil and main:IsShown() and T.ui:IsVisible()
end

local function settle()
    WoW.flushTimers()
    WoW.flushTimers()   -- a deferred rebuild can queue another
end

-- Past the few seconds after login in which a roster arriving is the client
-- catching up rather than the player joining.
local function afterLogin() WoW.time = WoW.time + 30 end

------------------------------------------------------------
-- Login opens the window for a mage in a group
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "a mage logging in inside a group gets the window")

setup(0)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a mage logging in alone does not")

setup(0)
MagelyDB.showSolo = true
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "unless solo display is on")

------------------------------------------------------------
-- ...and nothing at all for any other class
------------------------------------------------------------

setup(2, "DRUID")
local before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a druid in a group gets no window")
H.eq(#WoW.messages, before, "and no Magely chat line")
WoW.dispatch("GROUP_ROSTER_UPDATE")
WoW.dispatch("READY_CHECK")
settle()
H.check(not shown(), "nor does a roster change or a ready check open one")
H.check(not T.isMage(), "Magely knows it is on another class")
-- Nor does the config's zone rebuild: ForceRebuild does nothing off-class.
Magely_ForceRebuild()
settle()
H.check(not shown(), "and a forced rebuild (the config's, or a zone change's) opens nothing")

-- Typed commands too: one line, and no saved table, no frames.
MagelyDB = nil
local framesBefore = T.mainFrame()
for _, cmd in ipairs({ "", "show", "reset", "hide", "pos", "config" }) do
    before = #WoW.messages
    SlashCmdList["MAGELY"](cmd)
    H.eq(#WoW.messages, before + 1, "/magely " .. cmd .. " answers once on a druid")
end
H.check(WoW.messages[#WoW.messages]:find("Mage", 1, true) ~= nil,
    "saying what Magely is for: " .. WoW.messages[#WoW.messages])
settle()
H.eq(MagelyDB, nil, "and creates no saved table")
H.eq(T.mainFrame(), framesBefore, "and builds no window")
H.check(not shown(), "and shows nothing")
Magely_OnSoloToggle(true)
settle()
H.check(not shown(), "the solo hook does nothing on a druid either")

------------------------------------------------------------
-- A deliberate close survives a reload
------------------------------------------------------------

setup(2)
MagelyDB.visible = false
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a window closed on purpose stays closed across a reload")
H.eq(MagelyDB.visible, false, "and the preference is not overwritten")

------------------------------------------------------------
-- Roster churn does not reopen a closed window...
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open to start with")
T.CloseUI(true)                     -- /magely hide
H.check(not shown(), "closed by hand")
H.eq(MagelyDB.visible, false, "which is remembered")

afterLogin()
WoW.groupMembers = 3
WoW.SetUnit("party2", { name = "Sten Thornbeard", guid = "P2" })
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a third member joining does not reopen it")
H.eq(MagelyDB.visible, false, "and does not overwrite the preference")

WoW.dispatch("READY_CHECK")
settle()
H.check(not shown(), "nor does a ready check")

------------------------------------------------------------
-- ...but joining a group does, because that is the advertised behaviour
------------------------------------------------------------

WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "leaving the group leaves it closed")

WoW.groupMembers = 2
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "joining a group reopens it - that is what the addon promises")
H.eq(MagelyDB.visible, true, "and the preference follows")

WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "leaving the group closes it again, with solo display off")

------------------------------------------------------------
-- The roster arriving just after login is not a join
--
-- Inside a group GetNumGroupMembers() can still read 0 at PLAYER_LOGIN. The
-- first roster update then looks like 0 -> n, and treating that as a join
-- would undo a close on every login.
------------------------------------------------------------

setup(0)
MagelyDB.visible = false
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.groupMembers = 5
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a roster that arrives just after login does not undo a close")
H.eq(MagelyDB.visible, false, "and the preference stands")

afterLogin()
WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
WoW.groupMembers = 2
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "a real join later on still reopens it")

------------------------------------------------------------
-- A settings change never reopens a closed window
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
Magely_ForceRebuild()
settle()
H.check(not shown(), "a rebuild asked for by the options panel leaves a closed window closed")
H.eq(MagelyDB.visible, false, "and the close is still remembered")
SlashCmdList["MAGELY"]("show")
settle()
Magely_ForceRebuild()
settle()
H.check(shown(), "an open window is rebuilt and stays open")

------------------------------------------------------------
-- Spells the client reports only after login still open the window
------------------------------------------------------------

setup(2)
WoW.knownSpells = {}                  -- nothing known yet at login
WoW.spellbook = {}
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "with nothing to cast there is no window")
H.eq(MagelyDB.visible, true, "which is not a close: the preference is untouched")
WoW.Know(H.SPELL.INT_SINGLE, H.NAME.INT_SINGLE)
WoW.dispatch("SPELLS_CHANGED")
settle()
H.check(shown(), "the spellbook arriving opens the window it would have opened at login")

T.CloseUI(true)
WoW.dispatch("SPELLS_CHANGED")
settle()
H.check(not shown(), "but spells changing never overrides a close")

------------------------------------------------------------
-- A show asked for during combat happens when combat ends
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
WoW.inCombat = true
SlashCmdList["MAGELY"]("show")
settle()
H.check(not shown(), "the window cannot be built during combat lockdown")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "so the request is honoured the moment combat ends, not dropped")

------------------------------------------------------------
-- The solo checkbox
------------------------------------------------------------

setup(0)
WoW.dispatch("PLAYER_LOGIN")
settle()
-- In the checkbox's order: the setting is saved, then the hook is called.
Magely_SetConfig("showSolo", true)
Magely_OnSoloToggle(true)
settle()
H.check(shown(), "ticking solo opens the window alone")
Magely_SetConfig("showSolo", false)
Magely_OnSoloToggle(false)
settle()
H.check(not shown(), "and unticking it alone closes it")

-- Mid-fight, the tick is honoured when the fight ends rather than lost.
WoW.inCombat = true
Magely_SetConfig("showSolo", true)
Magely_OnSoloToggle(true)
settle()
H.check(not shown(), "nothing can be built during the fight")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "and the window appears when it ends")

------------------------------------------------------------
-- Toggling
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open")
SlashCmdList["MAGELY"]("")          -- bare /magely toggles
settle()
H.check(not shown(), "toggles closed")
SlashCmdList["MAGELY"]("")
settle()
H.check(shown(), "and back open")

------------------------------------------------------------
-- Zoning never undoes a close, but can bring back a window that closed
-- itself for want of rows
--
-- The config calls Magely_ForceRebuild on every zone change, because a row
-- can appear by instance. That must never reopen a window the player closed.
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
MagelyDB.amplifyMode = "instance"
H.TeachSpells({ "INT_SINGLE", "AMPLIFY" })
T.RefreshSpellData()
WoW.instanceName, WoW.instanceType = "The Deadmines", "party"
WoW.dispatch("ZONE_CHANGED_NEW_AREA")
settle()
H.check(not shown(), "zoning into an Amplify instance leaves a closed window closed")
H.eq(MagelyDB.visible, false, "and the close is still remembered")

-- Nothing to show outdoors: Intellect untracked, Amplify only by instance.
-- The window closes itself - which is not a close the player asked for - and
-- zoning in, where the Amplify row appears, brings it back.
setup(2)
MagelyDB.trackIntellect = false
MagelyDB.trackDampen = false
MagelyDB.amplifyMode = "instance"
H.TeachSpells({ "INT_SINGLE", "AMPLIFY" })
T.RefreshSpellData()
WoW.instanceName, WoW.instanceType = "", nil
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "with nothing to show outdoors there is no window")
H.eq(MagelyDB.visible, true, "which is not a close")
WoW.instanceName, WoW.instanceType = "The Deadmines", "party"
WoW.dispatch("ZONE_CHANGED_NEW_AREA")
settle()
H.check(shown(), "zoning into an Amplify instance brings the window back with its row")
local ampRow
for _, r in ipairs(T.rows()) do
    if r._active and r._def and r._def.id == "amplify" then ampRow = r end
end
H.check(ampRow ~= nil, "and the row is Amplify's")
WoW.instanceName, WoW.instanceType = "", nil
WoW.dispatch("ZONE_CHANGED_NEW_AREA")
settle()
H.check(not shown(), "leaving the instance takes it away again")
H.eq(MagelyDB.visible, true, "without that counting as a close either")
WoW.instanceName, WoW.instanceType = "", nil

H.done("test_visibility")
