------------------------------------------------------------
-- test_options.lua - build the options panel and click everything in it.
--
-- The panel is built lazily on OnShow, so without this none of it would run
-- under test: not the construction, not a single checkbox, radio or slider.
-- That would put the whole options UI outside the strict-global net in
-- wow_stubs.lua, which is the one thing protecting against an API that
-- quietly went away.
--
-- The hooks Magely.lua defines for the config - Magely_ForceRebuild and
-- friends - are replaced here by spies, and put back at the end. That tests
-- what the panel asks for, which is the panel's whole job; what the host then
-- does with it is test_frames' and test_visibility's.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_options.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, TC = H.loadAddon()

WoW.reset()
MagelyDB = nil
Magely_EnsureDefaults()

local calls = {}
local HOOKS = { "Magely_ForceRebuild", "Magely_OnSoloToggle", "Magely_ApplyAlpha" }
local realHooks = {}
for _, name in ipairs(HOOKS) do realHooks[name] = rawget(_G, name) end
local function spy(name)
    _G[name] = function(...) calls[#calls + 1] = { name = name, args = { ... } } end
end
for _, name in ipairs({ "Magely_ForceRebuild", "Magely_OnSoloToggle", "Magely_ApplyAlpha" }) do
    spy(name)
end
local function called(name, since)
    for i = (since or 0) + 1, #calls do
        if calls[i].name == name then return calls[i] end
    end
end

local function click(name, ...)
    local f = _G[name]
    if not f then H.check(false, "no widget named " .. name) return end
    local fn = f._scripts and f._scripts.OnClick
    if not fn then H.check(false, name .. " has no OnClick") return end
    local ok, err = pcall(fn, f, ...)
    H.check(ok, name .. " OnClick ran: " .. tostring(err))
    return f
end

-- Every change goes through the one write path.
local changed = {}
local realHook = Magely_OnConfigChanged
Magely_OnConfigChanged = function(key) changed[#changed + 1] = key end
local function reported(key, since)
    for i = (since or 0) + 1, #changed do
        if changed[i] == key then return true end
    end
    return false
end

------------------------------------------------------------
-- The panel builds at all
------------------------------------------------------------

local panel = _G["MagelyOptionsPanel"]
H.check(panel ~= nil, "the options panel frame exists")
local built, err = pcall(panel._scripts.OnShow, panel)
H.check(built, "it builds on first show: " .. tostring(err))
H.check(pcall(panel._scripts.OnShow, panel), "showing it again is a no-op")

------------------------------------------------------------
-- Checkboxes
--
-- The client toggles a checkbox before OnClick fires, so the test does too:
-- firing the handler alone just re-reads whatever state it was in.
------------------------------------------------------------

for _, key in ipairs({ "trackIntellect", "trackAmplify", "trackDampen", "trackPets", "showSolo",
                       "lockFrame", "showClickHints" }) do
    local box = _G["MagelyCB_" .. key]
    H.check(box ~= nil, key .. " has a checkbox")
    if box then
        -- Flip from whatever it is now, then back: setting the value it already
        -- has is (correctly) not a change, and would not be reported.
        local now = MagelyDB[key] ~= false
        for _, state in ipairs({ not now, now }) do
            local mark, rebuilds = #changed, #calls
            box:SetChecked(state)
            click("MagelyCB_" .. key)
            H.eq(MagelyDB[key], state, key .. " follows its checkbox to " .. tostring(state))
            H.check(reported(key, mark), key .. " is written through Magely_SetConfig")
            H.check(called("Magely_ForceRebuild", rebuilds) ~= nil, key .. " asks the window to rebuild")
        end
    end
end

-- Solo also asks for the dedicated show/hide handler, with the new state.
local mark = #calls
_G["MagelyCB_showSolo"]:SetChecked(true)
click("MagelyCB_showSolo")
local solo = called("Magely_OnSoloToggle", mark)
H.check(solo ~= nil and solo.args[1] == true, "ticking solo tells the window to show")

------------------------------------------------------------
-- Amplify and Dampen radios
--
-- Two groups with the same three keys: their global names carry the group,
-- so they cannot collide, and choosing one never moves the other.
------------------------------------------------------------

local MODES = { "always", "detect", "instance" }
for _, which in ipairs({ "amplify", "dampen" }) do
    local other = which == "amplify" and "dampen" or "amplify"
    local otherBefore = MagelyDB[other .. "Mode"]
    for _, mode in ipairs(MODES) do
        local before, rebuilds = #changed, #calls
        click("MagelyRB_" .. which .. "_" .. mode)
        H.eq(MagelyDB[which .. "Mode"], mode, "the " .. which .. " " .. mode .. " radio selects that mode")
        H.check(reported(which .. "Mode", before) or mode == "detect",
            "through the setter (re-selecting the default detect is no change)")
        H.check(called("Magely_ForceRebuild", rebuilds) ~= nil, "and rebuilds the window")
    end
    for _, mode in ipairs(MODES) do
        H.eq(_G["MagelyRB_" .. which .. "_" .. mode]:GetChecked(), mode == "instance",
            "only the selected " .. which .. " radio is checked (" .. mode .. ")")
    end
    H.eq(MagelyDB[other .. "Mode"], otherBefore, "and " .. other .. "'s mode is left alone")
end

-- Built with the saved modes checked, not always the first radio.
MagelyDB.amplifyMode, MagelyDB.dampenMode = "always", "detect"
panel._built = nil
H.check(pcall(panel._scripts.OnShow, panel), "the panel rebuilds")
H.eq(_G["MagelyRB_amplify_always"]:GetChecked(), true, "with the saved Amplify mode checked")
H.eq(_G["MagelyRB_amplify_instance"]:GetChecked(), false, "and no other")
H.eq(_G["MagelyRB_dampen_detect"]:GetChecked(), true, "and the saved Dampen mode checked")

------------------------------------------------------------
-- The Instances tab
------------------------------------------------------------

local TC2 = TC
H.eq(_G["MagelyInstanceContainer"]:IsShown(), false, "the Instances tab starts hidden")
click("MagelyTab2")
H.eq(_G["MagelyInstanceContainer"]:IsShown(), true, "its tab shows it")
H.eq(_G["MagelySettingsScroll"]:IsShown(), false, "and hides Settings")
click("MagelyTab1")
H.eq(_G["MagelySettingsScroll"]:IsShown(), true, "and back")

-- Every instance has both boxes, checked from the saved maps.
for _, entry in ipairs(TC2.INSTANCE_DB) do
    local slug = entry[1]:gsub("%W", "")
    for which, map in pairs(TC2.INSTANCE_MAPS) do
        local box = _G["MagelyInst_" .. which .. "_" .. slug]
        H.check(box ~= nil, entry[1] .. " has a " .. which .. " box")
        if box then
            H.eq(box:GetChecked(), MagelyDB[map.key][entry[1]] == true,
                entry[1] .. "'s " .. which .. " box shows its saved flag")
        end
    end
end

-- Ticking one writes that buff's map, re-checks where the player stands, and
-- rebuilds: standing in it, the row can appear at once.
MagelyDB.amplifyMode = "instance"
WoW.instanceName, WoW.instanceType = "Scholomance", "party"
TC2.CheckCurrentInstance()
H.eq(TC2.inInstance("amplify"), false, "Scholomance starts without Amplify")
local ampBox = _G["MagelyInst_amplify_Scholomance"]
local markC, markR = #changed, #calls
ampBox:SetChecked(true)
click("MagelyInst_amplify_Scholomance")
H.eq(MagelyDB.amplifyInstances["Scholomance"], true, "the Amp box writes the Amplify map")
H.eq(MagelyDB.dampenInstances["Scholomance"], true, "and leaves the Dampen one as it was")
H.check(reported("amplifyInstances", markC), "through the setter")
H.eq(TC2.inInstance("amplify"), true, "the instance check follows at once")
H.check(called("Magely_ForceRebuild", markR) ~= nil, "and the window is asked to rebuild")

-- Reset Defaults puts every flag, and every box, back.
MagelyDB.dampenInstances["Scholomance"] = false
markR = #calls
click("MagelyInstanceContainerDefaults")
H.eq(MagelyDB.amplifyInstances["Scholomance"], false, "Reset Defaults restores the Amplify default")
H.eq(MagelyDB.dampenInstances["Scholomance"], true, "and the Dampen one")
H.eq(ampBox:GetChecked(), false, "and the box shows it")
H.eq(TC2.inInstance("amplify"), false, "and the instance check follows")
H.check(called("Magely_ForceRebuild", markR) ~= nil, "and rebuilds")

-- Hovering an instance explains it.
for _, entry in ipairs(TC2.INSTANCE_DB) do
    local row = _G["MagelyInstRow_" .. entry[1]:gsub("%W", "")]
    H.check(row ~= nil and row._scripts.OnEnter ~= nil, entry[1] .. " has a row to hover")
end
local row = _G["MagelyInstRow_Scholomance"]
H.eq(row._mouseEnabled, true, "a row takes the mouse, or it could never be hovered")
H.check(pcall(row._scripts.OnEnter, row), "an instance row's tooltip opens")
local tip = WoW.tooltipText()
H.check(tip:find("Scholomance", 1, true) and tip:find("Caster-heavy", 1, true),
    "naming the instance, with its advice: " .. tip)
H.check(pcall(row._scripts.OnLeave, row), "and closes")
WoW.instanceName, WoW.instanceType = "", nil

------------------------------------------------------------
-- Zoning asks for a rebuild
--
-- A row can appear by instance, so a zone change re-checks and asks the
-- window to rebuild. Through ForceRebuild, never a plain refresh: a refresh
-- does nothing for a window that closed for want of rows. (That ForceRebuild
-- respects a player's close is Magely.lua's, tested in test_visibility.)
------------------------------------------------------------

MagelyDB.dampenMode = "instance"
WoW.instanceName, WoW.instanceType = "Stratholme", "party"
markR = #calls
WoW.dispatch("ZONE_CHANGED_NEW_AREA")
H.eq(TC2.inInstance("dampen"), true, "zoning into Stratholme is noticed")
H.check(called("Magely_ForceRebuild", markR) ~= nil, "and the window is asked to rebuild")
markR = #calls
WoW.instanceName, WoW.instanceType = "", nil
WoW.dispatch("PLAYER_ENTERING_WORLD", false, false)
H.eq(TC2.inInstance("dampen"), false, "leaving it is noticed too")
H.check(called("Magely_ForceRebuild", markR) ~= nil, "and rebuilds again")

------------------------------------------------------------
-- Popover side radios
--
-- A separate group from the buff modes: their names carry the group, so two
-- groups with a matching key could not collide in _G.
------------------------------------------------------------

for _, side in ipairs({ "left", "right", "auto" }) do
    click("MagelyRB_side_" .. side)
    H.eq(MagelyDB.popoverSide, side, "the " .. side .. " radio selects that side")
end
H.eq(_G["MagelyRB_side_auto"]:GetChecked(), true, "auto is the one left checked")
H.eq(_G["MagelyRB_side_left"]:GetChecked(), false, "with the others cleared")
H.eq(MagelyDB.amplifyMode, "instance", "and choosing a side leaves the buff modes alone")

------------------------------------------------------------
-- Opacity slider
------------------------------------------------------------

local slider = _G["MagelyAlphaSlider"]
H.check(slider ~= nil, "the opacity slider was created")
-- Template-free, so nothing else turns the mouse on: without this the thumb
-- cannot be dragged, and a test that calls OnValueChanged directly would never
-- notice.
H.eq(slider and slider._mouseEnabled, true, "and it takes the mouse")
local onValue = slider and slider._scripts.OnValueChanged
H.check(onValue ~= nil, "with a value handler")
mark = #calls
local changedMark = #changed
H.check(pcall(onValue, slider, 0.5), "which runs")
H.eq(MagelyDB.frameAlpha, 0.5, "and stores the opacity")
H.check(reported("frameAlpha", changedMark), "through Magely_SetConfig")
H.check(called("Magely_ApplyAlpha", mark) ~= nil, "and applies it to the window")
H.check(pcall(onValue, slider, 0.73), "an in-between value")
H.eq(MagelyDB.frameAlpha, 0.75, "is snapped to the 5% step")
H.check(pcall(onValue, slider, 1.0), "at the top of its range too")
H.eq(MagelyDB.frameAlpha, 1.0, "which is full opacity")

-- Installed with HookScript, so it has to be run on purpose.
H.check(pcall(slider._scripts.OnShow, slider), "the slider's OnShow hook runs")
WoW.flushTimers()

------------------------------------------------------------
-- Without Magely.lua's hooks at all
--
-- The config must not depend on the host having loaded: if Magely.lua failed,
-- each hook is looked up guarded, so a missing one is skipped, not an error.
------------------------------------------------------------

for _, name in ipairs({ "Magely_ForceRebuild", "Magely_OnSoloToggle", "Magely_ApplyAlpha" }) do
    _G[name] = nil
end
click("MagelyCB_trackIntellect")
click("MagelyRB_dampen_always")
H.check(pcall(onValue, slider, 0.6), "the slider runs with no host loaded")
H.eq(MagelyDB.dampenMode, "always", "and settings still save")
H.check(pcall(WoW.dispatch, "ZONE_CHANGED_NEW_AREA"), "and zoning does not need the host either")
for name, fn in pairs(realHooks) do _G[name] = fn end

------------------------------------------------------------
-- Layout measurement before the text has been laid out
------------------------------------------------------------

local flat = WoW.makeFrame()
flat.GetStringHeight = function() return 0 end
H.eq(TC.TextHeight(flat), 16, "a zero height falls back to a readable default")
H.eq(TC.TextHeight(flat, 32), 32, "callers can pick their own fallback")
local tall = WoW.makeFrame()
tall.GetStringHeight = function() return 24 end
H.eq(TC.TextHeight(tall), 24, "a real height is used as-is")
H.eq(TC.TextHeight(nil), 16, "and a missing FontString does not error")

WoW.zeroHeights = true
panel._built = nil
H.check(pcall(panel._scripts.OnShow, panel), "the panel builds even when no text has been measured yet")
WoW.zeroHeights = false

------------------------------------------------------------
-- Opening the panel
------------------------------------------------------------

local before = #WoW.messages
H.check(pcall(Magely_OpenConfig), "Magely_OpenConfig runs before the panel is registered")
H.check(#WoW.messages > before and WoW.messages[#WoW.messages]:find("AddOns", 1, true) ~= nil,
    "and says where to find the options rather than doing nothing")

-- The panel registers itself with the Settings framework on login, which is
-- what OpenToCategory needs.
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
H.check(pcall(Magely_OpenConfig), "Magely_OpenConfig runs")
H.eq(WoW.settingsOpenedTo, 42, "and opens the registered category")

Magely_OnConfigChanged = realHook

H.done("test_options")
