------------------------------------------------------------
-- test_stub.lua - the stub's own shapes, where Magely depends on them.
--
-- The stub is the list of APIs the tests trust, so a stub that answers
-- differently from the client lets broken code pass. The stub itself is the
-- library's now (../LibGroupBuffs/tests/wow_stubs.lua), which makes these a
-- contract rather than a self-check: the shapes Magely depends on, pinned to the
-- client's declared or observed behaviour, so a change over there that would
-- break this addon fails here rather than in game.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_stub.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

------------------------------------------------------------
-- strsplit keeps empty fields, as the client does
------------------------------------------------------------

local a, b, c = strsplit(",", "a,,b")
H.eq(select("#", strsplit(",", "a,,b")), 3, "an empty field is still a field")
H.eq(a, "a", "first") H.eq(b, "", "the empty one") H.eq(c, "b", "last")
H.eq(select("#", strsplit(",", "")), 1, "an empty string is one empty field")
local x, y, z = strsplit(",;", "1;2,3")
H.eq(x .. y .. z, "123", "every character of the separator splits")

------------------------------------------------------------
-- The client the stub models: 70205 (LibGroupBuffs#50, from r27). Magely's
-- MEASURED_ON_BUILD stays 70009 until someone re-measures; that is a
-- separate decision, made in game, not by the stub.
------------------------------------------------------------

WoW.reset()
H.eq(WoW.build, "70205", "the stub is the installed client's build")
local _, build, date = GetBuildInfo()
H.eq(build, "70205", "GetBuildInfo's second return is that build")
-- Two spaces: C's __DATE__ pads a single-digit day, and the client repeats it.
H.eq(date, "Oct  2 2026", "and its third the date 70205 was built")
WoW.build = "70123"
H.eq(select(2, GetBuildInfo()), "70123", "a test can still move it")
WoW.reset()

H.eq(select("#", GetInstanceInfo()), 11, "GetInstanceInfo returns eleven values on 70009")

-- UnitName: 70009 splits every unit, player included; a unit with a realm
-- reads the 69913 way, joined name then realm.
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "MAGE" })
local n1, n2 = UnitName("player")
H.eq(n1, "Karuzo", "on 70009 the player's UnitName is the first name")
H.eq(n2, "Elegia", "with the surname in the realm slot")
H.eq(GetUnitName("player", false), "Karuzo Elegia", "while GetUnitName still joins it")
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "MAGE", realm = "ClassicBetaPvE" })
n1, n2 = UnitName("player")
H.eq(n1, "Karuzo Elegia", "a unit given a realm reads the 69913 way: the joined name")
H.eq(n2, "ClassicBetaPvE", "and a real realm")
WoW.reset()

H.done("test_stub")
