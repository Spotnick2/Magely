------------------------------------------------------------
-- test_libfiles.lua - the one reader of the libraries' XML.
--
-- Its name is part of the test: libfiles.lua has a script mode, and it once
-- decided it was being run as a script whenever the running file's name
-- ENDED in "libfiles.lua" - which this file's does. It then printed its usage
-- and exited before any test ran. Reaching H.done at all is the first check.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_libfiles.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local L = dofile("tests/libfiles.lua")
local ok, err

H.check(type(L.resolve) == "function", "loaded as a module, not run as a script")

-- Since r26 the library is one runtime file, and draws LibGlass's textures:
-- resolving it against the LibGlass checkout requires every one it names.
local glassRoot = H.libGlassRoot()
local load, ship = L.resolve(H.libraryRoot(), nil, glassRoot)
H.eq(load[1], "LibStub/LibStub.lua", "LibStub loads first")
H.eq(load[2], "LibGroupBuffs.lua", "then the library's one runtime file")
H.eq(#load, 2, "and nothing else")

local shipped = {}
for _, file in ipairs(ship) do shipped[file] = true end
H.check(shipped["LibGroupBuffs-1.0.xml"], "the entry XML itself ships")
for _, file in ipairs(load) do
    H.check(shipped[file], file .. " is loaded, so it ships")
end
for file in pairs(shipped) do
    H.check(not file:find("^Media/"), "LibGroupBuffs ships no textures of its own: " .. file)
end

-- LibGlass ships its XML, what that loads, LICENSE and every texture it draws.
local gload, gship = L.glass(glassRoot)
H.eq(gload[#gload], "LibGlass.lua", "LibGlass loads its one runtime file")
local gshipped, textures = {}, 0
for _, file in ipairs(gship) do
    gshipped[file] = true
    if file:find("^Media/") then textures = textures + 1 end
end
H.check(gshipped["LibGlass-1.0.xml"] and gshipped["LICENSE"], "with its XML and LICENSE")
H.check(textures >= 10, "and its textures: " .. textures)

-- A texture LibGroupBuffs draws that LibGlass lacks is an error naming it.
ok, err = pcall(L.resolve, H.libraryRoot(), nil, "tests/no-such-glass")
H.check(not ok and tostring(err):find("does not have", 1, true),
    "a LibGlass without the textures LibGroupBuffs draws is an error: " .. tostring(err))

-- A missing file is an error naming it, never a shorter list.
ok, err = pcall(L.resolve, "tests/no-such-library")
H.check(not ok and tostring(err):find("not found", 1, true), "a missing library is an error: " .. tostring(err))

-- Both libraries load through the harness from here, too.
H.loadLibrary()
H.check(LibStub("LibGlass-1.0", true) ~= nil, "the harness loads LibGlass from this file")
H.check(LibStub("LibGroupBuffs-1.0", true) ~= nil, "and the library")

H.done("test_libfiles")
