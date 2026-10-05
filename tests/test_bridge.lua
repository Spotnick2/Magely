------------------------------------------------------------
-- test_bridge.lua - Magely on top of LibGroupBuffs-1.0.
--
-- The compat layer, the engine and the window live in the shared library,
-- with their own tests there. What is checked here is the join: that Magely
-- really uses the instance lib:New made for it, refuses to start - and says
-- why - when the library or LibGlass is missing, broken or too old, and
-- reports what the library says through its one reporter.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC, API = H.loadAddon()

------------------------------------------------------------
-- Magely.API IS the library's API - not a copy of it
------------------------------------------------------------

local lib = LibStub("LibGroupBuffs-1.0")
H.check(lib ~= nil, "LibGroupBuffs-1.0 is loaded")
H.check(API == lib.API, "Magely.API is the library's API table itself")
H.check(Magely.GB ~= nil and Magely.GB == lib.instances.Magely,
    "and Magely.GB the instance lib:New made for Magely")
-- The r25 bridge copied each piece onto Magely; the instance replaces them,
-- and a copy left behind would be a second way in that skips it.
for _, name in ipairs({ "Settings", "Engine", "UI", "Visibility" }) do
    H.eq(Magely[name], nil, "Magely." .. name .. " is gone: constructors go through Magely.GB")
end

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
                                           or code:find("%f[%w_]GB%.RegisterEvents%s*%(")
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
-- The label in red, the names plain - matched by the line's shape, not by the
-- library's words, which are the library's to change.
H.check(said:find("|cffff6666[^|]*:|r", 1) and not said:find("|cffff6666[^|]*REFUSED_EVENT"),
    "the label in red, the names plain: " .. said)
do
    -- A later library that words it differently keeps the same shape.
    local n = #WoW.messages
    Magely.GB.report("rejected events: SOME_EVENT", "events")
    local reworded = table.concat(WoW.messages, " ", n + 1, #WoW.messages)
    H.check(reworded:find("|cffff6666rejected events:|r SOME_EVENT", 1, true),
        "however the library words it: " .. reworded)
end

-- With no chat frame nothing can be printed, but the record is what
-- `/dump Magely.eventFailures` reads afterwards, and it must still be made.
do
    local chat = DEFAULT_CHAT_FRAME
    -- false, not nil: the strict stub refuses a read of a global it holds no
    -- value for, and the bridge only tests it for truth.
    DEFAULT_CHAT_FRAME = false
    WoW.badEvents.UNHEARD_EVENT = true
    local registered, why = pcall(Magely.RegisterEvents, f, "UNHEARD_EVENT")
    DEFAULT_CHAT_FRAME = chat
    H.check(registered, "a rejection with no chat frame does not throw: " .. tostring(why))
    H.check(Magely.eventFailures.UNHEARD_EVENT ~= nil,
        "and it is recorded in Magely's table all the same")
    -- Left as found, so nothing below depends on this section having run.
    WoW.badEvents.UNHEARD_EVENT = nil
    Magely.eventFailures.UNHEARD_EVENT = nil
    API.eventFailuresByOwner.Magely.UNHEARD_EVENT = nil
end

------------------------------------------------------------
-- One reporter for everything the library says
--
-- The instance carries Magely's reporter, and the settings object built from
-- it inherits the same one. Each kind's rewording lives with the file that
-- owns it (Magely.reportFilters); a kind nobody rewords is printed as is.
------------------------------------------------------------

local function reported(text, kind)
    local n = #WoW.messages
    Magely.GB.report(text, kind)
    return table.concat(WoW.messages, " ", n + 1, #WoW.messages)
end
said = reported("Settings are saved again.", "settingsLoaded")
H.check(said:find("[Magely]", 1, true) and said:find("|cff55ff55Settings are saved again.|r", 1, true),
    "a settingsLoaded message is printed in green, with Magely's prefix: " .. said)
said = reported("something new to say", "aKindFromALaterLibrary")
H.check(said:find("something new to say", 1, true),
    "and a kind this build has no filter for is still said, not dropped: " .. said)
said = reported(nil, "aKindFromALaterLibrary")
H.eq(said, "", "and a report with no text says nothing, rather than 'nil'")

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

local FLOOR = tonumber((H.readFile("MagelyCompat.lua") or ""):match("NEEDS_MINOR = (%d+)"))
H.check(FLOOR ~= nil, "the bridge declares the oldest library it works against")

-- A copy with no New at all. The TOC loads Magely's own copy first, so this
-- is Magely's copy not having registered (below the floor) or having
-- thrown before New was installed (at or above it). Either way the player is
-- pointed at Magely, not at other addons.
local function withoutNew(minor)
    local l = { API = {} }
    return setmetatable({}, { __call = function() return l, minor end })
end

loaded, err, chat = loadWithout(withoutNew(FLOOR - 1))
H.check(not loaded, "a copy without New, below the floor, is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "as too old, naming the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "without claiming a failed load: " .. chat)
H.check(chat:find("Reinstalling", 1, true),
    "and pointing at Magely's own copy, the only thing that can be behind: " .. chat)

loaded, err, chat = loadWithout(withoutNew(FLOOR))
H.check(not loaded, "a copy without New at the floor is refused too")
H.check(chat:find("completely", 1, true), "as a failed load: " .. chat)

------------------------------------------------------------
-- What the bridge does with each answer from lib:New
--
-- Which copies are usable is the library's question: lib:New refuses a copy
-- that did not finish loading, a missing or half-loaded LibGlass, and one
-- older than the floor, and its own tests cover how it decides
-- (LibGroupBuffs tests/test_new.lua). Magely's job is to ask with its
-- floor, refuse to start, and tell the player - so these run against the real
-- library, put into each state, rather than a fake that could agree with a
-- bridge asking the wrong question.
------------------------------------------------------------

LibStub, Magely = savedLibStub, savedMagely
local GB_MAJOR, GLASS_MAJOR = "LibGroupBuffs-1.0", "LibGlass-1.0"

-- Load the bridge again on the real library. New is once per owner, so the
-- instance the first load made is set aside for the duration and put back.
local function reload()
    local held = lib.instances.Magely
    lib.instances.Magely = nil
    Magely = nil
    local before = #WoW.messages
    local ok, why = pcall(dofile, "MagelyCompat.lua")
    local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
    local made = Magely and Magely.GB
    lib.instances.Magely = held
    Magely = savedMagely
    return ok, tostring(why), said, made
end

do
    local ok, why, said, made = reload()
    H.check(ok, "the real library, as loaded, is accepted: " .. why)
    H.eq(said, "", "and nothing is said to the player")
    H.eq(made and made.needs, FLOOR, "and the floor is what the bridge asked New for")
    H.eq(made and made.owner, "Magely", "under Magely's own name")
end

-- Whatever New said goes to developers, after Magely's own sentence. Checked
-- by shape - not by the library's words, which are its to change.
local function handsOverReason(why, label)
    local said = why:match("; lib:New said: (.-)%)%. Developers:")
    H.check(said ~= nil and said ~= "", label .. ": developers get New's own reason: " .. why)
end

-- A copy that threw partway: registered, never ready. LibStub runs the newest
-- copy any addon shipped, so it need not be Magely's - the player is told
-- how to find out whose, not sent to reinstall Magely.
do
    local ready = lib.ready
    lib.ready = -1
    local ok, why, said = reload()
    lib.ready = ready
    H.check(not ok, "a library that did not finish loading is refused")
    H.check(said:find("cannot start", 1, true) and said:find("did not finish loading", 1, true)
            and said:find(GB_MAJOR, 1, true),
        "and the player is told so: " .. said)
    H.check(said:find("scriptErrors", 1, true) and not said:find("Reinstalling", 1, true),
        "with how to see which addon's copy failed, not a reinstall that would change nothing: " .. said)
    handsOverReason(why, "an unfinished library")
end

-- LibGlass missing outright: no addon's copy registered, and Magely ships
-- one, so it is Magely's install.
do
    local glass, glassMinor = LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR]
    LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR] = nil, nil
    local ok, why, said = reload()
    LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR] = glass, glassMinor
    H.check(not ok, "a missing LibGlass is refused")
    H.check(said:find("cannot start", 1, true) and said:find(GLASS_MAJOR, 1, true),
        "naming LibGlass to the player: " .. said)
    H.check(said:find("Reinstalling Magely", 1, true),
        "pointing them at reinstalling Magely: " .. said)
    handsOverReason(why, "a missing LibGlass")

    -- Registered but never ready: the newest LibGlass threw partway. Magely's
    -- own copy loaded (or the name would not be registered), so it is some
    -- other addon's copy, and reinstalling Magely would change nothing.
    local ready = glass.ready
    glass.ready = nil
    ok, why, said = reload()
    glass.ready = ready
    H.check(not ok, "a LibGlass that did not finish loading is refused too")
    H.check(said:find(GLASS_MAJOR, 1, true) and said:find("did not finish loading", 1, true)
            and said:find("scriptErrors", 1, true) and not said:find("Reinstalling", 1, true),
        "as another addon's copy failing, not as Magely's install: " .. said)
    handsOverReason(why, "a half-loaded LibGlass")
end

-- Both at once: the library's own copy unfinished is what New refuses first,
-- so it is what the player hears about first.
do
    local ready, glass = lib.ready, LibStub.libs[GLASS_MAJOR]
    local glassReady = glass.ready
    lib.ready, glass.ready = -1, nil
    local _, _, said = reload()
    lib.ready, glass.ready = ready, glassReady
    H.check(said:find(GB_MAJOR .. " library", 1, true) and not said:find(GLASS_MAJOR, 1, true),
        "with both unfinished, the library's own copy is named, as New checks it first: " .. said)
end

-- Anything else New throws is not one of its refusals, and reads as a failed
-- load: a Lua error, whose file and line mean nothing to a player, and a host
-- mistake such as a second New for the same owner, which pcall leaves with no
-- position at all - so a position cannot be what tells them apart.
do
    local realNew = lib.New
    for _, case in ipairs({
        { label = "a New that crashes", thrown = "attempt to index field 'instances' (a nil value)", level = 1 },
        { label = "a host mistake", thrown = "LibGroupBuffs-1.0: Magely already has an instance", level = 0 },
    }) do
        lib.New = function() error(case.thrown, case.level) end
        local ok, why, said = reload()
        lib.New = realNew
        H.check(not ok, case.label .. " is refused")
        H.check(said:find("failed to load completely", 1, true) and said:find("Reinstalling", 1, true),
            case.label .. " reads as a failed load: " .. said)
        H.check(not said:find(case.thrown, 1, true) and not said:find(":%d+:"),
            case.label .. ": its text and position stay out of chat: " .. said)
        H.check(why:find(case.thrown, 1, true), case.label .. " goes to developers instead: " .. why)
    end
end

-- A complete copy that is simply behind the floor.
do
    local minor, ready = LibStub.minors[GB_MAJOR], lib.ready
    LibStub.minors[GB_MAJOR], lib.ready = FLOOR - 1, FLOOR - 1
    local ok, _, said = reload()
    LibStub.minors[GB_MAJOR], lib.ready = minor, ready
    H.check(not ok, "a complete library below the floor is refused")
    H.check(said:find("r" .. (FLOOR - 1), 1, true) and said:find("r" .. FLOOR, 1, true),
        "naming the version in use and the one needed: " .. said)
    H.check(not said:find("did not finish", 1, true), "without claiming a failed load: " .. said)
end

-- After all of that, the real instance is the one Magely is running on.
H.check(lib.instances.Magely == Magely.GB, "the refusals left Magely's own instance alone")

------------------------------------------------------------
-- The real load order: an older copy loaded first is UPGRADED, not refused
--
-- The reloads above call the bridge directly, which is not how the game gets
-- here. Magely's TOC loads its own copy of the library BEFORE this file, so
-- another addon's older copy has already been upgraded by LibStub when the
-- bridge runs. r25 is the copy every other consumer ships until it moves on,
-- so that is the one loaded first.
------------------------------------------------------------

do
    local root = H.libraryRoot()
    local older = {}
    for _, name in ipairs({ "Compat", "Glass", "Settings", "Engine", "UI", "Visibility" }) do
        older[#older + 1] = root .. "/tests/fixtures/" .. name .. "-r25.lua"
    end
    local haveFixtures = true
    for _, path in ipairs(older) do
        local f = io.open(path, "r")
        if f then f:close() else haveFixtures = false end
    end
    H.check(haveFixtures, "the library checkout carries its r25 fixtures to load first")

    if haveFixtures then
        Magely = nil
        -- A LibStub with nothing registered, the way a session starts.
        local stub = loadfile(root .. "/LibStub/LibStub.lua")
        LibStub = nil
        stub()

        for _, path in ipairs(older) do loadfile(path)("SomeOtherAddon", {}) end
        local _, before = LibStub:GetLibrary(GB_MAJOR)
        H.eq(before, 25, "another addon's r25 copy registered first")

        -- Now Magely's own, as its TOC does: LibGlass, then LibGroupBuffs.
        local resolved, files = pcall(H.libraryScripts)
        H.check(resolved, "the libraries resolve: " .. tostring(files))
        for _, path in ipairs(resolved and files or {}) do loadfile(path)("Magely", {}) end
        local _, after = LibStub:GetLibrary(GB_MAJOR)
        H.check(after > before, "and Magely's copy upgrades it to r" .. tostring(after))

        local before2 = #WoW.messages
        local ok, why = pcall(dofile, "MagelyCompat.lua")
        H.check(ok, "so the bridge accepts it, despite the older copy having loaded first: "
            .. tostring(why))
        H.eq(#WoW.messages, before2, "and says nothing to the player")
        H.check(Magely.API ~= nil and Magely.GB ~= nil, "with the upgraded library in place")
    end

    LibStub, Magely = savedLibStub, savedMagely
end

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

------------------------------------------------------------
-- Every hook the source reads GUARDED is a global the stub allows
--
-- `if Magely_ForceRebuild then` exists because MagelyConfig.lua can fail to
-- load while Magely.lua carries on. Under the strict-global stub a name not on
-- the allow-list does not read as nil - it throws - so a guard whose name is
-- missing can never be exercised, and the branch it protects is untested
-- while looking covered. The list and the guards are checked against each
-- other here rather than kept in step by hand.
------------------------------------------------------------

-- The source JOINED, not line by line, and every boolean position - not
-- just `if X` and `X and`. The first version of this scan matched only those
-- two forms on single lines, and missed both
-- `not Magely_ShowClickHints or Magely_ShowClickHints()` and a guard whose
-- `and` sits on the next line. A check that half-covers the thing it claims
-- to make impossible is worse than none, because AGENTS.md and the README
-- now both say the drift cannot happen.
local guarded = {}
for file, lines in pairs(SOURCES) do
    local joined = table.concat(lines, " ")
    local function find(pattern)
        for name in joined:gmatch(pattern) do guarded[name] = file end
    end
    find("[^%w_](Magely_[%a_][%w_]*)%s+and[%s(]")
    find("[^%w_](Magely_[%a_][%w_]*)%s+or[%s(]")
    find("[^%w_](Magely_[%a_][%w_]*)%s+then[%s(]")
    find("%f[%w_]not%s+(Magely_[%a_][%w_]*)")
    find("%f[%w_]if%s+(Magely_[%a_][%w_]*)")
    find("%f[%w_]elseif%s+(Magely_[%a_][%w_]*)")
end
local nGuarded = 0
for name, file in pairs(guarded) do
    nGuarded = nGuarded + 1
    H.check(WoW.hostGlobals[name],
        file .. " reads " .. name .. " guarded, so tests/wow_stubs.lua must allow it as nil")
end
H.check(nGuarded >= 2,
    "and the scan found the guards rather than nothing: " .. nGuarded)

H.done("test_bridge")
