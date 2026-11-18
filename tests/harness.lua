------------------------------------------------------------
-- harness.lua - tiny assertion harness + addon loader.
--
--     local H = dofile("tests/harness.lua")
--     H.loadLibrary()
--     H.eq(actual, expected, "what this proves")
--     H.done("test_thing")
--
-- Run from the repo root so the relative paths resolve.
--
-- The assertions are WowTestKit's (check / eq / done, globals the kit
-- defines; tests/kit.pin pins it), loaded by the shared stub's
-- dofile("tests/kit.lua"). H.check / H.eq / H.done stay as their names here,
-- so no test changes. The kit's print goes to WoW.chat, not the terminal,
-- which is why nothing here prints: done() writes the result line itself.
------------------------------------------------------------

local H = {}

function H.check(cond, msg) check(cond, msg or "assertion failed") end

function H.eq(a, b, msg) eq(a, b, msg or "values differ") end

-- A whole file as text with CRLF normalised, or nil if it does not exist.
function H.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- The addon's own Lua files, in the order Magely.toc loads them. Read from
-- the TOC so a new file cannot be missed by the tests that scan every file.
function H.tocFiles()
    local files = {}
    local toc = assert(H.readFile("Magely.toc"), "Magely.toc not found - run from the repo root")
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then files[#files + 1] = file end
    end
    return files
end

-- Where LibGroupBuffs-1.0 is checked out. tests/run.ps1 sets LIBGROUPBUFFS to
-- the path it resolved (and prints it); running a test file by hand falls back
-- to the sibling checkout. There is deliberately no vendored copy to fall back
-- to: a stale one would make the suite pass against code that no longer ships.
function H.libraryRoot()
    return ((os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"):gsub("\\", "/"):gsub("/$", ""))
end

-- Where LibGlass-1.0 is checked out: LIBGLASS (run.ps1 and CI set it), else
-- the sibling checkout. Fails loudly when it is not there - a missing
-- material is not something to skip.
function H.libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass next to this repository or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- Load a file or stop the run, naming it. A test that silently skipped a
-- missing file is how a load error in the client can pass a green suite.
-- The arguments are what the client passes an addon's file: its name and
-- the addon's private table.
local function run(path, ...)
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 3) end
    chunk(...)
end

-- ForeverProbe, the host MagelyProbe is a module of. Private and local
-- (..\ForeverProbe or $FOREVERPROBE), so CI sets FOREVERPROBE_OPTIONAL=1 and
-- the probe's tests skip there; locally a missing checkout is an error, never
-- a silent skip. Loaded into THIS stub environment the way the client loads a
-- dependency: its files, then its ADDON_LOADED. (Priestly's tests/harness.lua.)
function H.loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    -- The widget methods the host's console calls that the shared stub does not
    -- model. They are the host's, not Magely's: ForeverProbe runs in game
    -- with them, and its own tests carry the same list.
    WoW.allowMethod("SetMultiLine", "SetAutoFocus", "SetMaxLetters", "EnableMouseWheel",
        "GetVerticalScrollRange", "SetVerticalScroll")
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.dispatch("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

-- The files the TOC's library lines load, in order: LibGlass's, then
-- LibGroupBuffs', as full paths - read with tests/libfiles.lua, the same
-- reader run.ps1, deploy.ps1 and CI use. LibGroupBuffs is checked against the
-- LibGlass it draws from: a texture it names that LibGlass lacks fails here.
function H.libraryScripts()
    local L = dofile("tests/libfiles.lua")
    local glassRoot, root = H.libGlassRoot(), H.libraryRoot()
    local files = {}
    local ok, load = pcall(L.glass, glassRoot)
    if not ok then error(tostring(load), 2) end
    for _, file in ipairs(load) do files[#files + 1] = glassRoot .. "/" .. file end
    ok, load = pcall(L.resolve, root, nil, glassRoot)
    if not ok then
        -- Only a MISSING checkout gets the "check your checkout" advice.
        -- resolve also fails when a texture is undeclared, and telling someone
        -- with a perfectly good clone to re-clone it sends them away from the
        -- one line that says what is actually wrong.
        local why = tostring(load)
        if why:find("not found in", 1, true) then
            why = why .. ". Check LibGroupBuffs out next to this repository "
                .. "(../LibGroupBuffs) or set LIBGROUPBUFFS to its path."
        end
        error(why, 2)
    end
    for _, file in ipairs(load) do files[#files + 1] = root .. "/" .. file end
    return files
end

-- Load the two libraries alone, as the TOC's library lines do. Returns the
-- addon's private table, for loadAddon to hand on to Magely's files.
function H.loadLibrary()
    local ns = {}
    for _, path in ipairs(H.libraryScripts()) do run(path, "Magely", ns) end
    return ns
end

-- The TOC's files the port has not reached yet. They are the TBC code, which
-- neither loads under this stub nor keeps the rules test_bridge scans for, so
-- loadAddon skips them and so do the scans. The slice that ports a file
-- removes it here; test_bridge fails while a listed file already uses
-- Magely.API, so the list cannot outlive the port.
H.NOT_YET_PORTED = {}

-- Load everything the TOC loads that has been ported, in its order: LibGlass,
-- then LibGroupBuffs, then Magely's files. Each gets ("Magely", ns), as in the
-- client.
function H.loadAddon()
    local ns = H.loadLibrary()
    for _, file in ipairs(H.tocFiles()) do
        if not H.NOT_YET_PORTED[file] then run(file, "Magely", ns) end
    end
    return Magely._test, Magely._testConfig, Magely.API
end

-- The buffs, by the IDs Magely.lua uses.
H.SPELL = {
    INT_SINGLE = 1459, INT_GROUP = 23028,
    AMPLIFY    = 1008,
    DAMPEN     = 604,
}
H.NAME = {
    INT_SINGLE = "Arcane Intellect",
    INT_GROUP  = "Arcane Brilliance",
    AMPLIFY    = "Amplify Magic",
    DAMPEN     = "Dampen Magic",
}

-- Teach the stub client every spell name, and make `known` (a list of keys
-- into H.SPELL) the ones the player actually has. `ranks` optionally gives a
-- key's spellbook subtext ("Rank 2"), which is where the reagent comes from.
function H.TeachSpells(known, ranks)
    for key, id in pairs(H.SPELL) do
        WoW.DefineSpell(id, H.NAME[key])
    end
    for _, key in ipairs(known or {}) do
        WoW.Know(H.SPELL[key], H.NAME[key], ranks and ranks[key])
    end
end

-- Combat aura secrecy as measured on the live client: the flag is set AND
-- every index read throws, while the by-name lookup quietly returns nil.
function H.secrecy(on)
    WoW.secret = on and true or false
    WoW.auraReadsThrow = on and true or false
    WoW.inCombat = on and true or false
end

-- "<name>: N passed, M failed", after the kit's own two checks: no stray
-- "|" in any printed line, and no blocked operation on a secret swallowed by
-- a pcall. Exits with the result.
function H.done(name) done(name) end

return H
