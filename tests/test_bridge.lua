------------------------------------------------------------
-- test_bridge.lua - Magely on top of LibGroupBuffs-1.0.
--
-- The compat layer, the engine and the window live in the shared library,
-- with their own tests there. What is checked here is the join: that Magely
-- really uses the library, refuses one that is missing, broken or too old,
-- and reports rejected events in chat, which is the one behaviour it owns.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadLibrary()
dofile("MagelyCompat.lua")
local API = Magely.API

------------------------------------------------------------
-- Magely.API IS the library's API - not a copy of it
------------------------------------------------------------

local lib = LibStub("LibGroupBuffs-1.0")
H.check(lib ~= nil, "LibGroupBuffs-1.0 is loaded")
H.check(API == lib.API, "Magely.API is the library's API table itself")
H.check(Magely.Settings == lib.Settings, "and Magely.Settings its Settings")
H.check(Magely.Engine == lib.Engine, "and Magely.Engine its Engine")
H.check(Magely.UI == lib.UI, "and Magely.UI its UI")

------------------------------------------------------------
-- The rules every ported file keeps, read from the source
--
-- Files the port has not reached yet are the TBC code and break these rules
-- by construction, so they are skipped: H.NOT_YET_PORTED, shared with
-- loadAddon. Each slice that ports a file removes it from that list; the
-- check below fails while an entry names a file that no longer carries TBC
-- code, so the list cannot quietly outlive the port.
------------------------------------------------------------

local NOT_YET_PORTED = H.NOT_YET_PORTED

local SOURCES = {}
for _, file in ipairs(H.tocFiles()) do
    local text = H.readFile(file)
    H.check(text ~= nil, "the TOC lists " .. file .. ", which exists")
    if NOT_YET_PORTED[file] then
        -- Still the TBC code if it has not started using the library: a
        -- ported file reads Magely.API, even just to stop without it.
        H.check(text and not text:find("Magely.API", 1, true),
            file .. " is listed as not yet ported (" .. NOT_YET_PORTED[file]
            .. ") and is still the TBC code - drop it from NOT_YET_PORTED once it is ported")
    else
        local code = {}
        for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
            code[#code + 1] = (line:gsub("%-%-.*$", ""))
        end
        SOURCES[file] = code
    end
end
H.check(SOURCES["MagelyCompat.lua"] ~= nil, "the bridge itself is scanned")

-- Every API function a ported file calls exists in the library: the point of
-- the library is one copy, and a missing one only fails in game.
for file, lines in pairs(SOURCES) do
    for _, code in ipairs(lines) do
        for name in code:gmatch("%f[%w_]API%.([%a_][%w_]*)") do
            local want = (name == "eventFailures" or name == "eventFailuresByOwner") and "table" or "function"
            H.check(type(API[name]) == want, file .. " uses API." .. name .. ", so the library must provide it")
        end
    end
end

-- No library function copied into a local. API is shared by every addon that
-- embeds the library, and a newer copy upgrades it in place: `local F = API.F`
-- taken at load time keeps running the old version. Call through API, or
-- wrap: `local function F(...) return API.F(...) end`.
local captures = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- Qualified too: `lib.API.F` and `Magely.API.F` are the same copy.
        if code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*$")
            or code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*;") then
            captures[#captures + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#captures, 0, "no file copies a library function into a local: " .. table.concat(captures, " | "))

-- Events only through Magely.RegisterEvents. A bare frame:RegisterEvent
-- throws on an unknown name or returns false, and the library's own
-- registration prints nothing, so either can leave a handler silently dead.
local direct = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- MagelyCompat.lua holds the wrapper itself, the one allowed caller.
        if file ~= "MagelyCompat.lua" and (code:find("%f[%w_]API%.RegisterEvents%w*%s*%(")
                                           or code:find(":RegisterEvent%s*%(")) then
            direct[#direct + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#direct, 0, "nothing registers events except through Magely.RegisterEvents: " .. table.concat(direct, " | "))

------------------------------------------------------------
-- Rejected events are reported in chat
--
-- The library returns them instead of printing, because it must not write to
-- another addon's chat frame. A silently missing handler is worse than a
-- noisy one, so Magely prints them.
------------------------------------------------------------

WoW.reset()
local f = CreateFrame("Frame")
local before = #WoW.messages
local ok, failed = Magely.RegisterEvents(f, "PLAYER_LOGIN", "UNIT_AURA")
H.eq(ok, true, "known events register cleanly")
H.eq(#WoW.messages, before, "and print nothing")

WoW.badEvents.NOT_A_REAL_EVENT = true
before = #WoW.messages
ok, failed = Magely.RegisterEvents(f, "UNIT_PET", "NOT_A_REAL_EVENT")
H.eq(ok, false, "a rejected event name is reported")
H.check(WoW.events[f].UNIT_PET == true, "the good event still registered")
H.eq(failed and failed[1], "NOT_A_REAL_EVENT", "the caller gets the rejected name")
local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("NOT_A_REAL_EVENT", 1, true), "and it is printed, not silent: " .. said)
H.check(Magely.eventFailures.NOT_A_REAL_EVENT ~= nil,
    "and recorded in Magely's own table - the library's is shared by every addon")
H.check(API.eventFailuresByOwner.Magely.NOT_A_REAL_EVENT ~= nil,
    "and in the library under Magely's name")

-- The client can also refuse by returning false; that must be just as loud.
WoW.refusedEvents.REFUSED_EVENT = true
before = #WoW.messages
ok, failed = Magely.RegisterEvents(f, "REFUSED_EVENT")
H.eq(ok, false, "a false return is a rejection too")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("REFUSED_EVENT", 1, true), "and it is printed: " .. said)

------------------------------------------------------------
-- A missing library stops loading, with a message that says why
--
-- No fallback copy: running on a stale duplicate is the drift this removes.
------------------------------------------------------------

local savedLibStub, savedMagely = LibStub, Magely

local function loadWithout(libStubValue)
    LibStub = libStubValue
    Magely = nil
    local before = #WoW.messages
    local loaded, err = pcall(dofile, "MagelyCompat.lua")
    local chat = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
    return loaded, tostring(err), chat
end

local loaded, err, chat = loadWithout(nil)
H.check(not loaded, "MagelyCompat refuses to load without the library")
H.check(err:find("Libs\\LibGroupBuffs-1.0", 1, true),
    "the error names the real folder, backslash intact: " .. err)
-- Lua errors are hidden by default on this client, so the error alone would
-- leave a player looking at an addon that silently does nothing.
H.check(chat:find("cannot start", 1, true) and chat:find("missing", 1, true),
    "and a player is told in chat, where they will see it: " .. chat)

-- Whether a copy is usable is the library's answer (lib.Status), not
-- something Magely re-derives from its markers. These fakes stand in for the
-- library with a Status that answers whatever the case needs, and record the
-- floor Magely asked it about.
local FLOOR = tonumber(H.readFile("MagelyCompat.lua"):match("local NEEDS_MINOR = (%d+)"))
local asked
local function shaped(minor, status, active)
    local l = { API = { RegisterEventsReported = function() return true end } }
    if status then
        l.Status = function(needs) asked = needs return status, active end
    end
    return setmetatable({}, { __call = function() return l, minor end })
end

asked = nil
loaded = loadWithout(shaped(FLOOR, "ok", FLOOR))
H.check(loaded, "a library whose Status says ok is accepted - the baseline for the cases below")
H.eq(asked, FLOOR, "and Status was asked about Magely's own floor, NEEDS_MINOR")

loaded, err, chat = loadWithout(shaped(FLOOR, "incomplete", FLOOR))
H.check(not loaded, "a library whose Status says incomplete is refused")
H.check(chat:find("completely", 1, true), "as one that failed to load completely: " .. chat)

-- Complete and self-consistent, just behind: nothing crashed, so the message
-- must not say it did, and it names both versions so a report is actionable.
loaded, err, chat = loadWithout(shaped(FLOOR, "too-old", FLOOR - 1))
H.check(not loaded, "a library whose Status says too-old is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "the message names the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "and does not claim a failed load: " .. chat)

-- An answer this build does not know is not "ok", so it is not usable.
loaded, err, chat = loadWithout(shaped(FLOOR, "something-new", FLOOR))
H.check(not loaded, "a Status answer Magely does not know is refused, not trusted")
H.check(chat:find("completely", 1, true), "and reported as a failed load: " .. chat)

-- No Status at all has two meanings. Another addon's older copy - r11 or
-- earlier, from before Status existed - is complete, just old: the player
-- must not be sent after a crash that did not happen.
loaded, err, chat = loadWithout(shaped(FLOOR - 1, nil))
H.check(not loaded, "an older copy without Status is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "as too old, naming both versions: " .. chat)
H.check(not chat:find("completely", 1, true), "not as a failed load: " .. chat)

-- A copy at least as new as the floor without Status: its last file, which
-- installs Status, threw.
loaded, err, chat = loadWithout(shaped(FLOOR, nil))
H.check(not loaded, "a copy new enough to have Status, without it, is refused")
H.check(chat:find("completely", 1, true), "as one that failed to load completely: " .. chat)
loaded, err, chat = loadWithout(shaped(nil, nil))
H.check(not loaded and chat:find("completely", 1, true),
    "and so is a copy that does not even report its MINOR: " .. chat)

-- The real library's own answer, not a fake's: take away one file's record of
-- finishing, as a file that threw partway would leave it, and the real
-- Status must refuse it through Magely.
LibStub = savedLibStub
local realLib = LibStub("LibGroupBuffs-1.0")
local uiRecord = realLib.fileMinors.UI
realLib.fileMinors.UI = nil
loaded, err, chat = loadWithout(savedLibStub)
realLib.fileMinors.UI = uiRecord
H.check(not loaded, "the real library with UI.lua unfinished is refused")
H.check(chat:find("completely", 1, true), "as one that failed to load completely: " .. chat)
loaded = loadWithout(savedLibStub)
H.check(loaded, "and accepted again once every file has finished")

-- The ported files stop before building anything when the bridge refused the
-- library, so a missing library is one message rather than a cascade of
-- errors and half-made frames.
Magely = {}
local frames = 0
local realCreateFrame = CreateFrame
CreateFrame = function(...) frames = frames + 1 return realCreateFrame(...) end
local stopped = 0
for _, file in ipairs(H.tocFiles()) do
    if file ~= "MagelyCompat.lua" and not NOT_YET_PORTED[file] then
        local ok, why = pcall(dofile, file)
        H.check(ok, file .. " returns quietly when Magely.API is missing: " .. tostring(why))
        stopped = stopped + 1
    end
end
-- Until the config is ported (slice 2) every file after the bridge is TBC
-- code, and there is nothing to run here yet.
H.check(stopped >= 1 or next(NOT_YET_PORTED) ~= nil, "at least one ported file was checked")
H.eq(frames, 0, "and creates no frames")
CreateFrame = realCreateFrame

LibStub, Magely = savedLibStub, savedMagely

H.done("test_bridge")
