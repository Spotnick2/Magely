------------------------------------------------------------
-- test_probe.lua - Tools/MagelyProbe, a ForeverProbe module (/fp mp).
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
-- ForeverProbe is private and local (..\ForeverProbe, or $FOREVERPROBE): the
-- host is loaded into this stub environment, and CI, which cannot see it,
-- sets FOREVERPROBE_OPTIONAL=1 and skips this file.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_probe.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.reset()
local FP = H.loadForeverProbe()

local PROBE = "Tools/MagelyProbe/MagelyProbe.lua"

-- The client's order: the addon's files, then its ADDON_LOADED (which is when
-- its saved table is readable). Only ONE copy of the probe answers an event:
-- loading drops the previous copy's boot frame and keeps the host's
-- registrations (Priestly's loadProbe).
local function loadProbe()
    for frame in pairs(WoW.events) do
        if frame._probeBoot then WoW.events[frame] = nil end
    end
    local known = {}
    for frame in pairs(WoW.events) do known[frame] = true end
    local ns = {}
    assert(loadfile(PROBE))("MagelyProbe", ns)
    for frame in pairs(WoW.events) do
        if not known[frame] then frame._probeBoot = true end
    end
    WoW.dispatch("ADDON_LOADED", "MagelyProbe")
    return ns._test
end

local T = loadProbe()
local P = T.P

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local function mp(cmd) fp("mp " .. cmd) end
local function result(key) return MagelyProbeDB.results[key] end

-- Everything the probe has said since line n, from its saved log. With
-- nothing new, table.concat(t, sep, i) would quietly return the LAST OLD line.
local function logSince(n)
    local log = MagelyProbeDB.log
    if #log <= n then return "" end
    return table.concat(log, " | ", n + 1, #log)
end

------------------------------------------------------------
-- A module of the host, with its own saved log
------------------------------------------------------------

H.check(type(MagelyProbeDB) == "table" and type(MagelyProbeDB.log) == "table",
    "the saved log is bound at the probe's own ADDON_LOADED")
H.check(FP.modules.MagelyProbe ~= nil and FP.byCmd.mp == FP.modules.MagelyProbe, "it is /fp mp")
H.eq(rawget(SlashCmdList, "MAGELYPROBE"), nil, "the probe has no slash command of its own any more")
H.eq(rawget(_G, "SLASH_MAGELYPROBE1"), nil, "and no /mprobe")
H.eq(rawget(_G, "MagelyProbe"), nil, "and no global: the test seam is the addon's namespace")
H.eq(MagelyProbeDB.loads, 1, "a load is counted")
H.check(logSince(0):find("loaded", 1, true), "and said, in the saved log")

-- The saved table the client hands back at ADDON_LOADED is the one written
-- to: a table made at file scope would be replaced, and its writes lost.
local saved = { log = { "an older session's line" }, loads = 4, results = { stale = "from before" } }
MagelyProbeDB = saved
T = loadProbe()
P = T.P
H.check(MagelyProbeDB == saved, "the probe adopts the saved table rather than replacing it")
H.eq(MagelyProbeDB.loads, 5, "and counts on from it")
H.eq(MagelyProbeDB.log[1], "an older session's line", "the log is kept across sessions")
H.eq(result("stale"), nil, "but each session's results start afresh")
H.eq(MagelyProbeDB.build, WoW.build, "with the build they were taken on")
mp("clear")
H.check(MagelyProbeDB.log == saved.log, "clear empties the log in place, never replacing the table")
H.eq(#MagelyProbeDB.log, 1, "leaving only the line it says afterwards")
H.check(MagelyProbeDB.log[1]:find("log cleared", 1, true), "which is that")

------------------------------------------------------------
-- Spells and items, by ID
------------------------------------------------------------

WoW.DefineSpell(1459, "Arcane Intellect")
WoW.Know(1459, "Arcane Intellect")
H.check(pcall(mp, "spells"), "the spell probe runs")
local ai = result("spell 1459 Arcane Intellect")
H.check(ai and ai:find("Arcane Intellect / known=true", 1, true), "a known spell reads as that: " .. tostring(ai))
local ab = result("spell 23028 Arcane Brilliance")
H.check(ab and ab:find("nil (does not resolve)", 1, true),
    "a spell the client does not know by ID says so, rather than looking like a name: " .. tostring(ab))
H.check(result("spell 10060 Power Infusion (Priest talent)") ~= nil, "every listed spell is recorded")
H.check((result("item 17020 Arcane Powder") or ""):find("icon=", 1, true), "and the reagent")
H.check(logSince(0):find("spell 1459 Arcane Intellect: Arcane Intellect", 1, true), "and said in the log")

-- An API this client lacks is recorded as missing, and the rest still runs.
local realSpell = rawget(_G, "C_Spell")
rawset(_G, "C_Spell", nil)
H.check(pcall(mp, "spells"), "the spell probe survives C_Spell being absent")
H.check((result("spell 1459 Arcane Intellect") or ""):find("missing", 1, true),
    "and records it as missing: " .. tostring(result("spell 1459 Arcane Intellect")))
rawset(_G, "C_Spell", realSpell)

------------------------------------------------------------
-- UNIT_SPELLCAST_SUCCEEDED
------------------------------------------------------------

H.check(pcall(mp, "cast on"), "watching casts starts")
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
H.check(pcall(mp, "cast off"), "watching stops")
WoW.refusedEvents.UNIT_SPELLCAST_SUCCEEDED = true
local before = #MagelyProbeDB.log
H.check(pcall(mp, "cast on"), "and restarts")
H.eq(result("UNIT_SPELLCAST_SUCCEEDED registers"), "false", "a false return is recorded as refused")
H.check(logSince(before):find("RegisterEvent UNIT_SPELLCAST_SUCCEEDED: refused", 1, true),
    "and the module's helper says which event")
WoW.refusedEvents.UNIT_SPELLCAST_SUCCEEDED = nil
mp("cast off")
-- An unknown name throws in the client; that is a refusal too, not a crash.
WoW.badEvents.UNIT_SPELLCAST_SUCCEEDED = true
H.check(pcall(mp, "cast on"), "a throwing registration does not crash the probe")
H.eq(result("UNIT_SPELLCAST_SUCCEEDED registers"), "false", "and is recorded as not registered")
WoW.badEvents.UNIT_SPELLCAST_SUCCEEDED = nil
mp("cast off")

------------------------------------------------------------
-- The pane in combat
------------------------------------------------------------

WoW.inCombat = true
before = #MagelyProbeDB.log
H.check(pcall(mp, "pane build"), "building in combat is refused politely")
H.check(logSince(before):find("out of combat", 1, true), "and says why")
H.eq(P.pane, nil, "and builds nothing")
WoW.inCombat = false

before = #MagelyProbeDB.log
H.check(pcall(mp, "pane test"), "testing before building says to build first")
H.check(logSince(before):find("build first", 1, true), "in so many words")

-- The host's watcher is the one ADDON_ACTION_BLOCKED listener. When the probe
-- cannot tell that it registered - here IsEventRegistered throws - every
-- "no blocked event" would be silence, not a clean pass, and must say so.
local taint = FP.Baseline.taintFrame
H.check(taint ~= nil, "the host has its blocked-action watcher")
taint.IsEventRegistered = function() error("IsEventRegistered: not answered") end
H.check(pcall(mp, "pane build"), "the pane builds out of combat")
H.eq(result("blocked-action watcher registered"), "unknown", "and records that it can't tell the watcher's state")
H.check(P.pane ~= nil and P.parent ~= nil, "both frames exist")
H.eq(P.parent:IsShown(), true, "the protected stand-in starts shown, so a refused Hide is visible")

WoW.inCombat = true
local blockedBefore = #WoW.blockedCalls
H.check(pcall(mp, "pane test"), "the in-combat test runs")
H.eq(result("pane test in combat"), "true", "and knows it ran in combat")
H.check((result("pane Hide") or ""):find("took effect=true", 1, true),
    "a plain pane hides in combat (in the stub's model): " .. tostring(result("pane Hide")))
H.check((result("pane Show") or ""):find("took effect=true", 1, true), "and shows again from hidden")
local control = result("pane Hide the PROTECTED stand-in (control)") or ""
H.check(control:find("took effect=false", 1, true),
    "the control, a frame parenting a secure button, is refused: " .. control)
H.check(control:find("unavailable", 1, true),
    "and with the watcher's state unknown, its blocked events are reported as unavailable - not as none: " .. control)
H.check(#WoW.blockedCalls > blockedBefore, "which is the refusal the stub saw")
for _, key in ipairs({ "pane SetHeight", "pane re-anchor" }) do
    H.check(result(key) ~= nil, key .. " was tried and recorded")
end
WoW.inCombat = false
H.check(pcall(mp, "pane remove"), "the frames are removed out of combat")
H.eq(P.pane, nil, "and forgotten")

-- The host's watcher, modelled with the client's IsEventRegistered over the
-- stub's registrations, so a refusal can be set per event.
taint.IsEventRegistered = function(self, ev) return (WoW.events[self] or {})[ev] == true end
-- A watcher the client refused: unavailable again.
WoW.events[taint].ADDON_ACTION_FORBIDDEN = nil
H.check(pcall(mp, "pane build"), "the pane builds with a half-registered watcher")
H.eq(result("blocked-action watcher registered"), "false", "and says the watcher is not fully registered")
mp("pane remove")
WoW.events[taint].ADDON_ACTION_FORBIDDEN = true

-- Now model the finding the probe exists to catch: the client refuses the
-- PLAIN pane's Hide too, raising a blocked event blamed on some other addon,
-- the way this client attributes them. Show must then be reported as
-- untestable - a pane that never left the screen is "shown after Show"
-- without anything having happened.
H.check(pcall(mp, "pane build"), "the pane builds again")
H.eq(result("blocked-action watcher registered"), "true", "with the watcher registered")
local pane = P.pane
pane.Hide = function(self)
    WoW.dispatch("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Frame:Hide()")
    return self
end
WoW.inCombat = true
H.check(pcall(mp, "pane test"), "the test runs with the pane's Hide refused")
local hide = result("pane Hide") or ""
H.check(hide:find("took effect=false", 1, true), "the refused Hide reads as that: " .. hide)
H.check(hide:find("ADDON_ACTION_BLOCKED: Frame:Hide() blamed on SomeOtherAddon", 1, true),
    "with the blocked event, its function and who it was blamed on: " .. hide)
H.check((result("pane SetHeight") or ""):find("no blocked event", 1, true),
    "an attempt that raised nothing says so, now that the watcher is known: " .. tostring(result("pane SetHeight")))
H.check((result("pane Show") or ""):find("untestable", 1, true),
    "and Show is untestable, not a pass: " .. tostring(result("pane Show")))
H.eq(MagelyProbeDB.blocked[1], "ADDON_ACTION_BLOCKED: Frame:Hide() blamed on SomeOtherAddon",
    "the blocked action is kept for the report")
WoW.inCombat = false
mp("pane remove")

------------------------------------------------------------
-- A whisper to a surnamed name
------------------------------------------------------------

local sent
local realChat = rawget(_G, "C_ChatInfo")
rawset(_G, "C_ChatInfo", { SendChatMessage = function(msg, kind, lang, target)
    sent = { msg = msg, kind = kind, target = target }
end })
H.check(pcall(mp, "whisper Zoruka Mortalis"), "the whisper probe runs")
H.eq(sent and sent.target, "Zoruka Mortalis", "the whole two-word name is the target, surname included")
H.eq(sent and sent.kind, "WHISPER", "as a whisper")
H.check((result("whisper via C_ChatInfo.SendChatMessage to \"Zoruka Mortalis\"") or ""):find("accepted", 1, true),
    "and the result says only that it was accepted - arrival is the recipient's to confirm")
rawset(_G, "C_ChatInfo", { SendChatMessage = function() error("not allowed") end })
H.check(pcall(mp, "whisper Zoruka Mortalis"), "a refusal does not crash it")
H.check((result("whisper via C_ChatInfo.SendChatMessage to \"Zoruka Mortalis\"") or ""):find("threw", 1, true),
    "and is recorded as refused")
rawset(_G, "C_ChatInfo", realChat)
before = #MagelyProbeDB.log
H.check(pcall(mp, "whisper"), "a whisper with no name")
H.check(logSince(before):find("usage", 1, true), "explains itself")

------------------------------------------------------------
-- Talents of an inspected unit
------------------------------------------------------------

-- Nothing to inspect with: recorded as missing, no crash.
rawset(_G, "C_SpecializationInfo", nil)
H.check(pcall(mp, "inspect"), "the inspect probe survives a client with no C_SpecializationInfo")
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
H.check(pcall(mp, "inspect"), "the inspect probe runs when inspection is refused")
H.eq(result("CanInspect(target)"), "false", "the refusal is recorded - not a usage error")
H.eq(notified, 0, "and nothing is sent after it")

canInspect = true
H.check(pcall(mp, "inspect"), "the inspect probe runs with a target")
H.check((result("own talents by specializationIndex/talentIndex") or ""):find("3 hits", 1, true),
    "your own talents are read first, as the control: " .. tostring(result("own talents by specializationIndex/talentIndex")))
H.check((result("own talents by tier/column") or ""):find("0 hits", 1, true),
    "and the shape that answers nothing says 0, not nothing at all")
H.eq(result("CanInspect(target)"), "true", "the target can be inspected")
H.eq(result("INSPECT_READY registers"), "true", "INSPECT_READY is registered")
H.eq(notified, 1, "and the target is inspected")

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

-- A request that never went out: NotifyInspect refused. Another addon's
-- INSPECT_READY for the same unit must not be published as this answer.
rawset(_G, "NotifyInspect", function() error("refused") end)
H.check(pcall(mp, "inspect"), "a refused NotifyInspect does not crash the probe")
H.check((result("NotifyInspect(target)") or ""):find("threw", 1, true), "and is recorded as refused")
queriesBefore = #queries
-- For exactly the unit the refused request named - the current target - so
-- only the request having been forgotten can keep it out.
H.check(pcall(P.OnInspectReady, UnitGUID("target")), "a later INSPECT_READY for that unit")
H.eq(#queries, queriesBefore, "is not queried: no request of ours went out")
H.eq(result("INSPECT_READY ignored (not the requested unit)"), 2, "and is counted as ignored")
rawset(_G, "NotifyInspect", function(unit) notified = notified + 1 end)

-- And the real answer, with the target unchanged, through the real event.
WoW.SetUnit("target", { name = "Zoruka Mortalis", guid = "T1", class = "PRIEST" })
H.check(pcall(mp, "inspect"), "inspect again")
WoW.dispatch("INSPECT_READY", "T1")
H.eq(result("INSPECT_READY"), "for the requested target", "INSPECT_READY for the requested target is recognised")
local hit = result("inspected talents by specializationIndex/talentIndex") or ""
H.check(hit:find("3 hits", 1, true) and hit:find("Talent 1", 1, true),
    "the inspected talents are counted, with examples: " .. hit)
local sawInspect = false
for _, q in ipairs(queries) do
    if q.isInspect == true and q.target == "target" then sawInspect = true end
end
H.check(sawInspect, "and asked for as an inspection of the target")
H.eq(result("GetInspectSpecialization(target)"), "0", "the inspect specialization is recorded too")

-- The client as measured on 70009: a query without a tier throws, and a
-- tier without the tree finds nothing. If the tree is what was missing, the
-- third shape is the one that answers.
local treeQueries = {}
rawset(_G, "C_SpecializationInfo", {
    GetTalentInfo = function(q)
        if not q.tier then error("GetTalentInfo(): query.tier must be specified.") end
        if q.specializationIndex then treeQueries[#treeQueries + 1] = q end
        if q.specializationIndex and q.tier <= 2 then
            return { name = "Tree " .. q.specializationIndex .. " t" .. q.tier .. "c" .. q.column,
                     rank = 0, maxRank = 5 }
        end
        return nil
    end,
})
H.check(pcall(mp, "inspect"), "the probe runs against the 70009 shape")
H.check((result("own talents by specializationIndex/talentIndex") or ""):find("tier must be specified", 1, true),
    "the index shape records the client's refusal: " .. tostring(result("own talents by specializationIndex/talentIndex")))
H.check((result("own talents by tier/column") or ""):find("0 hits, 0 errors", 1, true),
    "tier/column alone finds nothing, as measured")
local three = result("own talents by specializationIndex/tier/column") or ""
H.check(three:find("24 hits", 1, true) and three:find("Tree 1 t1c1", 1, true),
    "and the tree plus tier and column answers, with examples: " .. three)
-- A count of hits cannot show the walk is complete: always asking tree 1, or
-- column 1, would hit just as often here. Every (tree, tier, column) must be
-- asked exactly once, as the player's own talents.
local seenCombo, dupes, wrongContext = {}, 0, 0
for _, q in ipairs(treeQueries) do
    local key = q.specializationIndex .. "/" .. q.tier .. "/" .. q.column
    if seenCombo[key] then dupes = dupes + 1 end
    seenCombo[key] = true
    if q.isInspect ~= false or q.target ~= nil then wrongContext = wrongContext + 1 end
end
local missing = {}
for tree = 1, 3 do for tier = 1, 10 do for col = 1, 4 do
    local key = tree .. "/" .. tier .. "/" .. col
    if not seenCombo[key] then missing[#missing + 1] = key end
end end end
H.eq(#treeQueries, 120, "3 trees x 10 tiers x 4 columns are asked")
H.eq(#missing, 0, "every combination, none skipped: " .. table.concat(missing, " "))
H.eq(dupes, 0, "and none twice")
H.eq(wrongContext, 0, "all as the player's own talents, not an inspection")

-- A GetTalentInfo that throws is counted, not fatal. So is a result that is
-- a secret value: truth-testing it throws, and it must do so inside the pcall.
rawset(_G, "C_SpecializationInfo", { GetTalentInfo = function() error("bad query") end })
H.check(pcall(mp, "inspect"), "a throwing GetTalentInfo does not crash the probe")
H.check((result("own talents by tier/column") or ""):find("bad query", 1, true),
    "and the error is recorded: " .. tostring(result("own talents by tier/column")))
local secretResult = setmetatable({}, { __index = function() error("attempt to compare a secret value") end })
rawset(_G, "C_SpecializationInfo", { GetTalentInfo = function() return secretResult end,
    GetInspectSpecialization = function() error("secret") end })
H.check(pcall(mp, "inspect"), "a secret talent result does not crash the probe")
H.check((result("own talents by specializationIndex/talentIndex") or ""):find("90 errors", 1, true),
    "it is counted as an error, never as a hit: " .. tostring(result("own talents by specializationIndex/talentIndex")))
H.check(pcall(P.OnInspectReady, "T1"), "nor does a secret result during INSPECT_READY")
H.check((result("GetInspectSpecialization(target)") or ""):find("threw", 1, true),
    "and a secret specialization is recorded as thrown")
rawset(_G, "C_SpecializationInfo", nil)
rawset(_G, "CanInspect", nil)
rawset(_G, "NotifyInspect", nil)

------------------------------------------------------------
-- The inspected spec by name, and whether talents live in traits
--
-- Measured on 70009: GetInspectSpecialization answered 1486, and
-- GetTalentInfo answered nothing in any shape. The probe names the spec and
-- asks whether an active trait config exists.
------------------------------------------------------------

rawset(_G, "C_SpecializationInfo", {
    GetTalentInfo = function() return nil end,
    GetInspectSpecialization = function() return 1486 end,
})
rawset(_G, "CanInspect", function(u) return true end)
rawset(_G, "NotifyInspect", function() end)
WoW.SetUnit("target", { name = "Zoruka Mortalis", guid = "T1", class = "PRIEST" })

-- Neither lookup present: recorded as missing, nothing crashes.
rawset(_G, "GetSpecializationInfoForSpecID", nil)
rawset(_G, "C_ClassTalents", nil)
H.check(pcall(mp, "inspect"), "inspect runs with no traits API")
H.eq(result("C_ClassTalents.GetActiveConfigID"), "missing", "the traits config lookup is recorded as missing")
H.check(pcall(P.OnInspectReady, "T1"), "and INSPECT_READY with no spec lookup")
H.eq(result("GetInspectSpecialization(target)"), "1486", "the spec ID is recorded")
H.eq(result("inspected spec by ID"), "GetSpecializationInfoForSpecID missing", "and the missing lookup too")

-- Both present.
-- The documented tuple, 70009 dump: id, name, description, icon, role, ...
rawset(_G, "GetSpecializationInfoForSpecID", function(id)
    if id == 1486 then return 1486, "Holy", "Heals.", 12345, "HEALER" end
end)
rawset(_G, "C_ClassTalents", { GetActiveConfigID = function() return 7 end })
local askedConfig
rawset(_G, "C_Traits", { GetConfigInfo = function(id)
    askedConfig = id
    return { name = "Loadout", type = 1, treeIDs = { 101, 102, 103 } }
end })
H.check(pcall(mp, "inspect"), "inspect runs with the traits API")
H.eq(result("C_ClassTalents.GetActiveConfigID"), "7; GetConfigInfo: name=Loadout type=1 trees=3",
    "an active config is recorded with what it holds")
H.eq(askedConfig, 7, "asking C_Traits about the active config's own ID")

-- The namespace there, the system not wired: each case reads differently.
rawset(_G, "C_Traits", { GetConfigInfo = function() return nil end })
H.check(pcall(mp, "inspect"), "inspect with GetConfigInfo answering nil")
H.eq(result("C_ClassTalents.GetActiveConfigID"), "7; GetConfigInfo answered nil",
    "a nil answer is not a config with empty fields")
rawset(_G, "C_Traits", nil)
H.check(pcall(mp, "inspect"), "inspect with no C_Traits")
H.eq(result("C_ClassTalents.GetActiveConfigID"), "7; C_Traits.GetConfigInfo missing",
    "and a missing function says so")
H.check(pcall(P.OnInspectReady, "T1"), "INSPECT_READY with the spec lookup")
H.eq(result("inspected spec by ID"), "1486 = Holy (role HEALER)", "the spec is named, with its role")

-- No config, a throwing lookup, and a secret spec ID: each recorded, none fatal.
rawset(_G, "C_ClassTalents", { GetActiveConfigID = function() return nil end })
H.check(pcall(mp, "inspect"), "inspect with no active config")
H.eq(result("C_ClassTalents.GetActiveConfigID"), "nil (no active talent config)", "says there is none")
rawset(_G, "C_ClassTalents", { GetActiveConfigID = function() error("not here") end })
H.check(pcall(mp, "inspect"), "inspect with a throwing config lookup")
H.check((result("C_ClassTalents.GetActiveConfigID") or ""):find("threw", 1, true), "records it as thrown")
local secretSpec = coroutine.create(function() end)
rawset(_G, "C_SpecializationInfo", { GetTalentInfo = function() return nil end,
    GetInspectSpecialization = function() return secretSpec end })
rawset(_G, "GetSpecializationInfoForSpecID", function(id) return id + 0 end)
H.check(pcall(P.OnInspectReady, "T1"), "a secret spec ID does not crash INSPECT_READY")
H.check((result("inspected spec by ID") or ""):find("threw", 1, true),
    "and its lookup is recorded as thrown: " .. tostring(result("inspected spec by ID")))
for _, name in ipairs({ "C_SpecializationInfo", "GetSpecializationInfoForSpecID", "C_ClassTalents", "C_Traits",
                        "CanInspect", "NotifyInspect" }) do
    rawset(_G, name, nil)
end

------------------------------------------------------------
-- Report and reset
------------------------------------------------------------

before = #MagelyProbeDB.log
H.check(pcall(mp, "report"), "the report runs")
-- Whatever build the stub models: the probe reports the client it runs on.
H.check(logSince(before):find("build " .. WoW.build, 1, true), "names the build: " .. logSince(before))
H.check(logSince(before):find("Frame:Hide() blamed on SomeOtherAddon", 1, true), "and the blocked actions")
local logBefore = #MagelyProbeDB.log
H.check(pcall(mp, "reset"), "reset runs")
H.eq(next(MagelyProbeDB.results), nil, "and forgets the session's results")
H.check(#MagelyProbeDB.log > logBefore, "but not the log")
before = #MagelyProbeDB.log
H.check(pcall(mp, "report"), "a report with nothing recorded")
H.check(logSince(before):find("none seen", 1, true), "says so rather than printing nothing")
before = #MagelyProbeDB.log
H.check(pcall(mp, ""), "a bare /fp mp lists its commands")
H.check(logSince(before):find("whisper", 1, true), "including the whisper")

------------------------------------------------------------
-- The procedures
--
-- `casts` answers the open question - do other players' casts arrive? - so
-- it is run end to end: its waits read the counters, your own cast is the
-- control, and its final check fails when no party cast was seen.
------------------------------------------------------------

local S = FP.Steps
local function record(name) return ForeverProbeDB.steps.records["MagelyProbe/" .. name] end
local function at(name) return record(name).at end

-- With no party member yet, the first step keeps waiting.
H.check(pcall(fp, "steps mp casts"), "the casts procedure starts")
H.eq(record("casts").status, "active", "and is running")
S.Poll()
H.eq(at("casts"), 1, "it waits for a party member")
WoW.groupMembers = 2
S.Poll()
H.eq(at("casts"), 2, "and goes on once there is one")
S.Answer(true)
H.eq(at("casts"), 4, "the watch starts on arrival and its check passes")
H.eq(record("casts").results[3].check, "PASS", "the registration check passed")
S.Poll()
H.eq(at("casts"), 4, "your own cast is awaited")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1459)
S.Poll()
H.eq(at("casts"), 5, "and seen")
S.Poll()
H.eq(at("casts"), 5, "a party cast is awaited")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "c2", 1459)
S.Poll()
H.eq(at("casts"), 6, "and seen")
S.Skip()                                    -- no fight
H.eq(record("casts").results[7].check, "PASS", "the counts pass with a party cast")
H.eq(at("casts"), 8, "and the procedure asks for a /reload")
S.Stop()

-- Again, with NO manual reset: the first run's casts are still in the
-- session's counters, and must not answer for this run. Its waits must wait,
-- and with no party cast the final check must FAIL, never inherit a pass.
fp("steps mp casts")
S.Poll()
S.Answer(true)
S.Poll()
H.eq(at("casts"), 4, "a repeat run waits for a new cast of yours, not the first run's")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 1459)
S.Poll()
H.eq(at("casts"), 5, "and goes on when one arrives")
S.Poll()
H.eq(at("casts"), 5, "the first run's party cast does not complete this run's wait")
S.Skip()                                    -- the party member never cast
S.Skip()
H.eq(record("casts").results[7].check, "FAIL", "no party cast this run fails the check")
H.eq(MagelyProbeDB.casts["party/nocombat/readable"] > 0, true, "though the session's counter still holds the old one")
S.Stop()

-- Casts seen by an earlier manual watch don't count either.
fp("mp cast on")
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "c4", 1459)
fp("steps mp casts")
S.Poll()
S.Answer(true)
WoW.dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "c5", 1459)
S.Poll()
S.Poll()
H.eq(at("casts"), 5, "a party cast from before the run started does not count")
S.Stop()
fp("mp cast off")
WoW.groupMembers = 0

------------------------------------------------------------
-- `talents`, through the inspection
--
-- Its wait completes on the answer to THIS request: never on another addon's
-- INSPECT_READY, never on an earlier run's answer, whichever handler the
-- event reaches first.
------------------------------------------------------------

rawset(_G, "C_SpecializationInfo", {
    GetTalentInfo = function() return nil end,
    GetInspectSpecialization = function() return 1486 end,
})
rawset(_G, "CanInspect", function() return true end)
local notifies = 0
rawset(_G, "NotifyInspect", function() notifies = notifies + 1 end)
rawset(_G, "UnitIsPlayer", function(unit) return unit == "target" end)
WoW.SetUnit("target", { name = "Zoruka Mortalis", guid = "T1", class = "PRIEST" })

H.check(pcall(fp, "steps mp talents"), "the talents procedure starts")
H.eq(at("talents"), 2, "its own talents are read on arrival, then it waits for a target")
S.Poll()
H.eq(at("talents"), 3, "a player target goes on to the inspection")
S.Run()
H.eq(notifies, 1, "the Inspect button sends the request")
H.eq(record("talents").results[3].check, "PASS", "and its check sees it sent")
H.eq(at("talents"), 4, "then it waits for the answer")
WoW.dispatch("INSPECT_READY", "SOMEONE-ELSE")
S.Poll()
H.eq(at("talents"), 4, "another addon's INSPECT_READY does not complete the wait")
WoW.dispatch("INSPECT_READY", "T1")
S.Poll()
H.eq(at("talents"), 6, "the answer to this request does, and what came back is read")
H.eq(record("talents").results[5].check, "PASS", "with the answer for the requested target")
S.Stop()

-- A second run, after a successful one: the old answer is not this one's.
fp("steps mp talents")
S.Poll()
S.Run()
H.eq(notifies, 2, "the second run sends its own request")
H.eq(result("INSPECT_READY"), nil, "and the first run's answer is gone")
S.Poll()
H.eq(at("talents"), 4, "so the wait waits for the new answer")
S.DoneByHand()                              -- the owner gives up waiting
H.eq(record("talents").results[5].check, "FAIL", "and with no answer, the check fails rather than pass on the old one")
S.Stop()

-- An attempt that stops early (it can't inspect) is never "answered" either.
fp("steps mp talents")
S.Poll()
rawset(_G, "CanInspect", function() return false end)
S.Run()
H.eq(notifies, 2, "nothing is sent when the target can't be inspected")
H.eq(record("talents").results[3].check, "FAIL", "the Inspect step's check fails")
S.Poll()
H.eq(at("talents"), 4, "and the wait does not complete from the earlier answer")
S.Stop()
for _, name in ipairs({ "C_SpecializationInfo", "CanInspect", "NotifyInspect", "UnitIsPlayer" }) do
    rawset(_G, name, nil)
end

H.check(pcall(fp, "steps mp pane"), "the pane procedure starts")
H.eq(record("pane").status, "active", "pane is running")
S.Stop()

H.eq(#WoW.messages, 0, "and none of the probe's diagnostics went to chat")

H.done("test_probe")
