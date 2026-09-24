------------------------------------------------------------
-- test_stub.lua - the stub's own shapes, where Magely depends on them.
--
-- The stub is the list of APIs the tests trust, so a stub that answers
-- differently from the client lets broken code pass. These pin the entries
-- Magely added to the library's copy (marked "Magely:" in wow_stubs.lua) to
-- the client's declared or observed shape.
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

H.done("test_stub")
