------------------------------------------------------------
-- test_methods.lua - every widget method the addon calls exists on the
-- client, for that widget type (WowTestKit's Kit.checkMethods, against the
-- build tests/kit.pin names).
--
-- The stub answers any method the build has on any widget, so the other
-- tests cannot tell a FontString:SetTexCoord from a Texture's. This one
-- exercises the addon as widely as is cheap - load, login, the window with
-- every row kind, the popover and its hover, combat in and out, every slash
-- command, the options panel and every control in it - and then checks each
-- recorded Type:Method against the build's widget lists. The calls include
-- the libraries' (LibGroupBuffs draws the window, LibGlass its material):
-- they run in the addon's frames, so they are checked too.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_methods.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function run(frame, script, ...)
    local fn = frame and frame._scripts and frame._scripts[script]
    if fn then
        local ok, err = pcall(fn, frame, ...)
        H.check(ok, script .. " ran: " .. tostring(err))
    end
end

-- A mage who knows every buff, in a party, at login.
WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()
MagelyDB.amplifyMode, MagelyDB.dampenMode = "always", "always"
H.TeachSpells({ "INT_SINGLE", "INT_GROUP", "AMPLIFY", "DAMPEN" })
T.RefreshSpellData()
WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "MAGE" })
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.SetUnit("party2", { name = "Offline Person", guid = "P2", class = "PRIEST", connected = false })
WoW.groupMembers = 3
WoW.itemCounts[17020] = 40
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
WoW.flushTimers()
T.UpdateUI()

-- The window: every row, its hover and the popover's rows.
for _, r in ipairs(T.rows()) do
    if r._active then
        run(r, "OnEnter")
        for _, pr in ipairs(T.popRows()) do run(pr, "OnEnter") run(pr, "OnLeave") end
        run(r, "OnLeave")
    end
end
WoW.flushTimers(1)

-- Combat in and out, with a roster change in between.
WoW.inCombat = true
WoW.dispatch("PLAYER_REGEN_DISABLED")
WoW.flushTimers(1)
WoW.SetUnit("party3", { name = "New Person", guid = "P3", class = "ROGUE" })
WoW.groupMembers = 4
WoW.dispatch("GROUP_ROSTER_UPDATE")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers(1)

-- Every slash command.
for _, cmd in ipairs({ "help", "show", "hide", "show", "pos", "reset", "config", "bogus" }) do
    local ok, err = pcall(SlashCmdList.MAGELY, cmd)
    H.check(ok, "/magely " .. cmd .. ": " .. tostring(err))
end
WoW.flushTimers(1)

-- The options panel, built on its OnShow, and every control in it.
local panel = _G["MagelyOptionsPanel"]
H.check(panel ~= nil, "the options panel exists")
run(panel, "OnShow")
for name, w in pairs(_G) do
    if type(name) == "string" and name:find("^Magely") and type(w) == "table" and rawget(w, "_scripts") then
        run(w, "OnEnter")
        run(w, "OnClick", "LeftButton")
        run(w, "OnLeave")
    end
end
WoW.flushTimers(1)

-- The window's close button, last.
local main = T.mainFrame and T.mainFrame()
if main and main.closeBtn then run(main.closeBtn, "OnClick") end
WoW.flushTimers(1)

local recorded = Kit.checkMethods()
H.check(recorded >= 110, "the exercise reached the window and the panel (" .. recorded .. " recorded)")

H.done("test_methods")
