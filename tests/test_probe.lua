------------------------------------------------------------
-- test_probe.lua - Tools/MagelyProbe.
--
-- The probe is a throwaway dev tool and would normally not be worth testing.
-- It is tested because of what it is FOR: the cooldown pane's return rests on
-- its answers, and a probe that silently records nothing - or dies on the
-- first API this client lacks, or reports a pass for something that never
-- happened - produces a result that reads exactly like a measurement.
-- Priestly's probe taught that (its tests/test_probe.lua).
--
-- Everything the probe reads from the client goes through rawget, so each
-- case below installs or removes the API it needs with rawset: the strict
-- stub is not asked to vouch for anything here.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_probe.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.reset()
assert(loadfile("Tools/MagelyProbe/MagelyProbe.lua"))()

local slash = SlashCmdList["MAGELYPROBE"]
H.check(slash ~= nil and SLASH_MAGELYPROBE1 == "/mprobe", "the probe registers /mprobe")
local P = MagelyProbe

local function result(key) return MagelyProbeDB.results[key] end
local function said(from) return table.concat(WoW.messages, " | ", (from or 0) + 1, #WoW.messages) end

------------------------------------------------------------
-- Spells and items, by ID
------------------------------------------------------------

WoW.DefineSpell(1459, "Arcane Intellect")
WoW.Know(1459, "Arcane Intellect")
H.check(pcall(slash, "spells"), "the spell probe runs")
local ai = result("spell 1459 Arcane Intellect")
H.check(ai and ai:find("Arcane Intellect / known=true", 1, true), "a known spell reads as that: " .. tostring(ai))
local ab = result("spell 23028 Arcane Brilliance")
H.check(ab and ab:find("nil (does not resolve)", 1, true),
    "a spell the client does not know by ID says so, rather than looking like a name: " .. tostring(ab))
H.check(result("spell 10060 Power Infusion (Priest talent)") ~= nil, "every listed spell is recorded")
H.check((result("item 17020 Arcane Powder") or ""):find("icon=", 1, true), "and the reagent")

-- An API this client lacks is recorded as missing, and the rest still runs.
local realSpell = rawget(_G, "C_Spell")
rawset(_G, "C_Spell", nil)
H.check(pcall(slash, "spells"), "the spell probe survives C_Spell being absent")
H.check((result("spell 1459 Arcane Intellect") or ""):find("missing", 1, true),
    "and records it as missing: " .. tostring(result("spell 1459 Arcane Intellect")))
rawset(_G, "C_Spell", realSpell)

------------------------------------------------------------
-- UNIT_SPELLCAST_SUCCEEDED
------------------------------------------------------------

H.check(pcall(slash, "cast on"), "watching casts starts")
H.eq(result("UNIT_SPELLCAST_SUCCEEDED registers"), "true", "and records the registration")

WoW.inCombat = false
P.OnCast("party1", "cast-1", 1459)
P.OnCast("raid7", "cast-2", 1459)
P.OnCast("player", "cast-3", 1459)
H.eq(MagelyProbeDB.casts["party/nocombat/readable"], 1, "a party cast out of combat is counted as readable")
H.eq(MagelyProbeDB.casts["raid/nocombat/readable"], 1, "and a raid one")
H.eq(MagelyProbeDB.casts["player/nocombat/readable"], 1, "and your own")
H.check(MagelyProbeDB.samples[1]:find("Arcane Intellect", 1, true), "with the spell's name: " .. MagelyProbeDB.samples[1])

-- In combat the ID may be a secret value. With issecretvalue answering, it is
-- counted as that; a secret the test misses must throw inside the pcall and
-- be counted as THREW, never crash the handler or pass as readable. (A
-- coroutine stands in for a secret: arithmetic on it throws, and it is not a
-- table, so no type filter can skip it - PORTING doc, secret values.)
local secret = coroutine.create(function() end)
WoW.inCombat = true
rawset(_G, "issecretvalue", function(v) return v == secret end)
H.check(pcall(P.OnCast, "party1", "cast-4", secret), "a secret spell ID does not crash the handler")
H.eq(MagelyProbeDB.casts["party/combat/SECRET"], 1, "and is counted as SECRET, in combat")
rawset(_G, "issecretvalue", nil)
H.check(pcall(P.OnCast, "party2", "cast-5", secret), "without issecretvalue it still does not crash")
H.eq(MagelyProbeDB.casts["party/combat/THREW"], 1, "and is counted as THREW, not as readable")
H.check(pcall(P.OnCast, secret, "cast-6", 1459), "a secret unit token does not crash it either")
H.eq(MagelyProbeDB.casts["unreadable unit/combat/readable"], 1, "and is recorded as an unreadable unit")
WoW.inCombat = false

-- Wired to the real event, not just callable.
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "party3", "cast-7", 1459)
H.eq(MagelyProbeDB.casts["party/nocombat/readable"], 2, "the event reaches the counter")

-- A refused registration is recorded, not assumed.
H.check(pcall(slash, "cast off"), "watching stops")
WoW.refusedEvents.UNIT_SPELLCAST_SUCCEEDED = true
H.check(pcall(slash, "cast on"), "and restarts")
H.eq(result("UNIT_SPELLCAST_SUCCEEDED registers"), "false", "a false return is recorded as refused")
WoW.refusedEvents.UNIT_SPELLCAST_SUCCEEDED = nil
slash("cast off")

------------------------------------------------------------
-- The pane in combat
------------------------------------------------------------

WoW.inCombat = true
local before = #WoW.messages
H.check(pcall(slash, "pane build"), "building in combat is refused politely")
H.check(said(before):find("out of combat", 1, true), "and says why")
H.eq(P.pane, nil, "and builds nothing")
WoW.inCombat = false

before = #WoW.messages
H.check(pcall(slash, "pane test"), "testing before building says to build first")
H.check(said(before):find("build first", 1, true), "in so many words")

-- The watcher for restricted actions could not register: every "no blocked
-- event" would then be silence, not a clean pass, and must say so.
WoW.refusedEvents.ADDON_ACTION_BLOCKED = true
H.check(pcall(slash, "pane build"), "the pane builds out of combat")
H.eq(result("ADDON_ACTION_BLOCKED registers"), "false", "and records that the blocked-event watch was refused")
H.check(P.pane ~= nil and P.parent ~= nil, "both frames exist")
H.eq(P.parent:IsShown(), true, "the protected stand-in starts shown, so a refused Hide is visible")
WoW.refusedEvents.ADDON_ACTION_BLOCKED = nil

WoW.inCombat = true
local blockedBefore = #WoW.blockedCalls
H.check(pcall(slash, "pane test"), "the in-combat test runs")
H.eq(result("pane test in combat"), "true", "and knows it ran in combat")
H.check((result("pane Hide") or ""):find("took effect=true", 1, true),
    "a plain pane hides in combat (in the stub's model): " .. tostring(result("pane Hide")))
H.check((result("pane Show") or ""):find("took effect=true", 1, true), "and shows again from hidden")
local control = result("pane Hide the PROTECTED stand-in (control)") or ""
H.check(control:find("took effect=false", 1, true),
    "the control, a frame parenting a secure button, is refused: " .. control)
H.check(control:find("unavailable", 1, true),
    "and with no watcher, its blocked events are reported as unavailable - not as none: " .. control)
H.check(#WoW.blockedCalls > blockedBefore, "which is the refusal the stub saw")
for _, key in ipairs({ "pane SetHeight", "pane re-anchor" }) do
    H.check(result(key) ~= nil, key .. " was tried and recorded")
end
WoW.inCombat = false
H.check(pcall(slash, "pane remove"), "the frames are removed out of combat")
H.eq(P.pane, nil, "and forgotten")

-- Built again with a working watcher. Now model the finding the probe exists
-- to catch: the client refuses the PLAIN pane's Hide too, raising a blocked
-- event blamed on some other addon, the way this client attributes them.
-- Show must then be reported as untestable - a pane that never left the
-- screen is "shown after Show" without anything having happened.
H.check(pcall(slash, "pane build"), "the pane builds again")
H.eq(result("ADDON_ACTION_BLOCKED registers"), "false",
    "(the watcher is created once per session; its first answer stands)")
P.parent, P.pane = nil, nil
-- A fresh probe for the rest: a new load of the file starts a new session.
assert(loadfile("Tools/MagelyProbe/MagelyProbe.lua"))()
P = MagelyProbe
slash = SlashCmdList["MAGELYPROBE"]
H.check(pcall(slash, "pane build"), "a fresh session builds the pane")
H.eq(result("ADDON_ACTION_BLOCKED registers"), "true", "with the watcher registered")
local pane = P.pane
pane.Hide = function(self)
    WoW.dispatch("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Frame:Hide()")
    return self
end
WoW.inCombat = true
H.check(pcall(slash, "pane test"), "the test runs with the pane's Hide refused")
local hide = result("pane Hide") or ""
H.check(hide:find("took effect=false", 1, true), "the refused Hide reads as that: " .. hide)
H.check(hide:find("Frame:Hide() blamed on SomeOtherAddon", 1, true),
    "with the blocked event, its function and who it was blamed on: " .. hide)
H.check((result("pane Show") or ""):find("untestable", 1, true),
    "and Show is untestable, not a pass: " .. tostring(result("pane Show")))
WoW.inCombat = false
slash("pane remove")

------------------------------------------------------------
-- A whisper to a surnamed name
------------------------------------------------------------

local sent
local realChat = rawget(_G, "C_ChatInfo")
rawset(_G, "C_ChatInfo", { SendChatMessage = function(msg, kind, lang, target)
    sent = { msg = msg, kind = kind, target = target }
end })
H.check(pcall(slash, "whisper Zoruka Mortalis"), "the whisper probe runs")
H.eq(sent and sent.target, "Zoruka Mortalis", "the whole two-word name is the target, surname included")
H.eq(sent and sent.kind, "WHISPER", "as a whisper")
H.check((result("whisper via C_ChatInfo.SendChatMessage to \"Zoruka Mortalis\"") or ""):find("accepted", 1, true),
    "and the result says only that it was accepted - arrival is the recipient's to confirm")
rawset(_G, "C_ChatInfo", { SendChatMessage = function() error("not allowed") end })
H.check(pcall(slash, "whisper Zoruka Mortalis"), "a refusal does not crash it")
H.check((result("whisper via C_ChatInfo.SendChatMessage to \"Zoruka Mortalis\"") or ""):find("threw", 1, true),
    "and is recorded as refused")
rawset(_G, "C_ChatInfo", realChat)
before = #WoW.messages
H.check(pcall(slash, "whisper"), "a whisper with no name")
H.check(said(before):find("usage", 1, true), "explains itself")

------------------------------------------------------------
-- Talents of an inspected unit
------------------------------------------------------------

-- Nothing to inspect with: recorded as missing, no crash.
rawset(_G, "C_SpecializationInfo", nil)
H.check(pcall(slash, "inspect"), "the inspect probe survives a client with no C_SpecializationInfo")
H.check((result("GetTalentInfo") or ""):find("missing", 1, true), "and says so")

-- A client that answers only the specializationIndex/talentIndex shape, for
-- the first tree's first three talents.
local queries = {}
rawset(_G, "C_SpecializationInfo", {
    GetTalentInfo = function(q)
        queries[#queries + 1] = q
        if q.specializationIndex == 1 and q.talentIndex and q.talentIndex <= 3 then
            return { name = "Talent " .. q.talentIndex, rank = 1, maxRank = 5 }
        end
        return nil
    end,
    GetInspectSpecialization = function() return 0 end,
})
WoW.SetUnit("target", { name = "Zoruka Mortalis", guid = "T1", class = "PRIEST" })
-- CanInspect as the 69977 dump declares it: one argument. A probe that passes
-- more would be answered by a usage error, which reads like "cannot inspect".
local canInspect = true
rawset(_G, "CanInspect", function(...)
    if select("#", ...) ~= 1 then error("Usage: CanInspect(targetGUID)") end
    return canInspect
end)
local notified = 0
rawset(_G, "NotifyInspect", function(unit) notified = notified + 1 end)

-- The client says no: nothing is sent.
canInspect = false
H.check(pcall(slash, "inspect"), "the inspect probe runs when inspection is refused")
H.eq(result("CanInspect(target)"), "false", "the refusal is recorded - not a usage error")
H.eq(notified, 0, "and nothing is sent after it")

canInspect = true
H.check(pcall(slash, "inspect"), "the inspect probe runs with a target")
H.check((result("own talents by specializationIndex/talentIndex") or ""):find("3 hits", 1, true),
    "your own talents are read first, as the control: " .. tostring(result("own talents by specializationIndex/talentIndex")))
H.check((result("own talents by tier/column") or ""):find("0 hits", 1, true),
    "and the shape that answers nothing says 0, not nothing at all")
H.eq(result("CanInspect(target)"), "true", "the target can be inspected")
H.eq(notified, 1, "and is")

-- INSPECT_READY for somebody else - another addon's inspection - is not
-- this answer, and is not queried.
local queriesBefore = #queries
H.check(pcall(P.OnInspectReady, "SOMEONE-ELSE"), "an unrelated INSPECT_READY is handled")
H.eq(#queries, queriesBefore, "and nothing is queried for it")
H.eq(result("INSPECT_READY ignored (not the requested unit)"), 1, "it is counted as ignored")
H.eq(result("inspected talents by specializationIndex/talentIndex"), nil, "and no inspected result is published")

-- The requested unit's event, but the player has since targeted someone else.
WoW.SetUnit("target", { name = "Other Person", guid = "T2", class = "WARRIOR" })
H.check(pcall(P.OnInspectReady, "T1"), "the requested INSPECT_READY after a retarget")
H.check((result("INSPECT_READY") or ""):find("target changed", 1, true),
    "is recorded as that: " .. tostring(result("INSPECT_READY")))
H.eq(#queries, queriesBefore, "and the new target is not queried in the old one's name")

-- And the real answer, with the target unchanged.
WoW.SetUnit("target", { name = "Zoruka Mortalis", guid = "T1", class = "PRIEST" })
H.check(pcall(slash, "inspect"), "inspect again")
H.check(pcall(P.OnInspectReady, "T1"), "INSPECT_READY for the requested target")
H.eq(result("INSPECT_READY"), "for the requested target", "is recognised")
local hit = result("inspected talents by specializationIndex/talentIndex") or ""
H.check(hit:find("3 hits", 1, true) and hit:find("Talent 1", 1, true),
    "the inspected talents are counted, with examples: " .. hit)
local sawInspect = false
for _, q in ipairs(queries) do
    if q.isInspect == true and q.target == "target" then sawInspect = true end
end
H.check(sawInspect, "and asked for as an inspection of the target")
H.eq(result("GetInspectSpecialization(target)"), "0", "the inspect specialization is recorded too")

-- A GetTalentInfo that throws is counted, not fatal. So is a result that is
-- a secret value: truth-testing it throws, and it must do so inside the pcall.
rawset(_G, "C_SpecializationInfo", { GetTalentInfo = function() error("bad query") end })
H.check(pcall(slash, "inspect"), "a throwing GetTalentInfo does not crash the probe")
H.check((result("own talents by tier/column") or ""):find("bad query", 1, true),
    "and the error is recorded: " .. tostring(result("own talents by tier/column")))
local secretResult = setmetatable({}, { __index = function() error("attempt to compare a secret value") end })
rawset(_G, "C_SpecializationInfo", { GetTalentInfo = function() return secretResult end,
    GetInspectSpecialization = function() error("secret") end })
H.check(pcall(slash, "inspect"), "a secret talent result does not crash the probe")
H.check((result("own talents by specializationIndex/talentIndex") or ""):find("90 errors", 1, true),
    "it is counted as an error, never as a hit: " .. tostring(result("own talents by specializationIndex/talentIndex")))
H.check(pcall(P.OnInspectReady, "T1"), "nor does a secret result during INSPECT_READY")
H.check((result("GetInspectSpecialization(target)") or ""):find("threw", 1, true),
    "and a secret specialization is recorded as thrown")
rawset(_G, "C_SpecializationInfo", nil)
rawset(_G, "CanInspect", nil)
rawset(_G, "NotifyInspect", nil)

------------------------------------------------------------
-- Report and reset
------------------------------------------------------------

before = #WoW.messages
H.check(pcall(slash, "report"), "the report runs")
H.check(said(before):find("build 69913", 1, true), "names the build: " .. said(before))
H.check(pcall(slash, "reset"), "reset runs")
H.eq(next(MagelyProbeDB.results), nil, "and forgets")
before = #WoW.messages
H.check(pcall(slash, "report"), "a report with nothing recorded")
H.check(said(before):find("none seen", 1, true), "says so rather than printing nothing")
H.check(pcall(slash, ""), "a bare /mprobe prints its usage")

H.done("test_probe")
