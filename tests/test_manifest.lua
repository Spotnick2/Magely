------------------------------------------------------------
-- test_manifest.lua - assertions about Magely.toc itself.
--
-- The TOC is not Lua and nothing else in the suite can see it, but two of its
-- lines are load-bearing in ways that are invisible until a player notices
-- something missing: which files load and in what order, and where settings
-- are stored.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_manifest.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- One reader for every file this test looks at (H.readFile normalises CRLF),
-- split into lines once.
local function lines(path)
    local text = assert(H.readFile(path), path .. " is missing")
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = (line:gsub("%s+$", "")) end
    return out
end

local toc = lines("Magely.toc")

local function directive(name)
    -- Escape the name: "X-Curse-Project-ID" contains "-", which is a Lua
    -- pattern quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for _, line in ipairs(toc) do
        local value = line:match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

------------------------------------------------------------
-- Interface version
------------------------------------------------------------

H.eq(directive("Interface"), "16001",
    "WoW: Forever 1.60.1 is interface 16001 - the %d%02d%02d form, not the transposed 11601 "
    .. "that circulates in the wild")

------------------------------------------------------------
-- Settings storage
--
-- Measured on builds 69913 and 69977: the client wrote SavedVariables and never
-- read them back - account-wide AND per-character - so every session started
-- from defaults. (An earlier note in Priestly said per-character storage
-- loaded. It did not; that was concluded from reading the saved file, which
-- always looks populated because EnsureDefaults rewrites every default each
-- session.) Build 70009 fixed it, and settings persist.
--
-- Per character is where Magely's settings belong: one Mage's choices are not
-- another's. Magely follows Priestly here; Priestly's issues #9 and #35 have
-- the history. Read them before changing storage.
------------------------------------------------------------

H.eq(directive("SavedVariablesPerCharacter"), "MagelyDB",
    "MagelyDB is declared per character - one Mage's settings are not another's")
-- The only account-wide variable is the load check's marker, so the addon can
-- tell when account-wide storage is fixed.
H.eq(directive("SavedVariables"), "MagelySVCheck",
    "the only account-wide variable is the load-check marker")
H.check(not tostring(directive("SavedVariables")):find("MagelyDB", 1, true),
    "and MagelyDB is not ALSO declared account-wide - one variable cannot live in both")

------------------------------------------------------------
-- Load order
--
-- LibGroupBuffs-1.0 provides the compat layer, engine and window, and
-- MagelyCompat exposes them as Magely.API / .Settings / .Engine / .UI; both
-- other files read those at load time. Anything out of order and they get nil.
------------------------------------------------------------

local entries = {}
for _, line in ipairs(toc) do
    -- Any line starting with "#" is a directive or a comment to the client,
    -- never a file to load.
    if line:match("%.[lx][um][al]$") and not line:match("^%s*#") then entries[#entries + 1] = line end
end

local LIB_XML = "Libs\\LibGroupBuffs-1.0\\LibGroupBuffs-1.0.xml"
H.eq(entries[1], LIB_XML, "the shared library loads first, through its own XML")
H.eq(entries[2], "MagelyCompat.lua", "then the bridge that exposes it as Magely.API")
H.eq(entries[3], "MagelyConfig.lua", "then the config, which reads Magely.API at file scope")
H.eq(entries[4], "Magely.lua", "then the addon proper")
H.eq(#entries, 4, "and nothing else loads")

------------------------------------------------------------
-- The library is embedded, pinned, and never committed
--
-- The TOC path, the .pkgmeta externals key and .gitignore have to agree, or
-- the release zip is missing the library while every local check passes.
------------------------------------------------------------

local pkg = lines(".pkgmeta")
local pkgmeta = table.concat(pkg, "\n")
local external = pkgmeta:match("externals:%s*\n%s+([^\n:]+):")
H.eq(external, "Libs/LibGroupBuffs-1.0", ".pkgmeta embeds the library at Libs/LibGroupBuffs-1.0")
H.eq(external and (external:gsub("/", "\\") .. "\\LibGroupBuffs-1.0.xml"), LIB_XML,
    "which is exactly where the TOC loads it from")
H.check(pkgmeta:find("url: https://github.com/Spotnick2/LibGroupBuffs", 1, true) ~= nil,
    "from the LibGroupBuffs repository")
local tag = pkgmeta:match("\n%s+tag:%s*(%S+)")
H.check(tag ~= nil and tag:match("^r%d+$") ~= nil,
    "pinned to a library tag, so a release cannot change under its own source: " .. tostring(tag))

-- The bridge refuses a library older than the behaviour this build needs, and
-- that floor has to be the tag actually shipped: pinning a newer tag while the
-- floor stays behind means a player with the older library installed gets an
-- addon that starts and quietly misbehaves, which is what the floor exists to
-- prevent. (The opposite, a floor ahead of the pin, refuses to start at all.)
local needs = tonumber((H.readFile("MagelyCompat.lua") or "")
    :match("local NEEDS_MINOR = (%d+)"))
H.check(needs ~= nil, "MagelyCompat declares the oldest library it works against")
H.eq(needs, tonumber(tostring(tag):match("^r(%d+)$")),
    "and it is the tag .pkgmeta pins: " .. tostring(tag) .. " vs NEEDS_MINOR " .. tostring(needs))

local libIgnored = false
for line in ((H.readFile(".gitignore") or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line == "Libs/" then libIgnored = true end
end
H.check(libIgnored, "and Libs/ is git-ignored, so no vendored copy can creep back in")

------------------------------------------------------------
-- Packaging
------------------------------------------------------------

H.eq(directive("Version"), "@project-version@",
    "the packager substitutes the version; deploy.ps1 rewrites it only in the deployed copy")
H.check(directive("X-Curse-Project-ID") ~= nil, "the CurseForge project is declared")
H.check(tostring(directive("Title")):find("Magely", 1, true) ~= nil,
    "the Title directive names the addon: " .. tostring(directive("Title")))
H.eq(directive("X-Curse-Project-ID"), "1545112", "and it is Magely's CurseForge project")

------------------------------------------------------------
-- The packaged zip must not carry internal documents
------------------------------------------------------------


-- Every Lua pattern character escaped, not just the dot: a path like
-- Libs/LibGroupBuffs-1.0/tests carries a `-`, which is a quantifier in a
-- pattern, so a dot-only escape silently matches nothing and the check
-- passes for the wrong reason.
local function ignored(name)
    local literal = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
    for _, line in ipairs(pkg) do
        if line:match("^%s*%-%s*" .. literal .. "%s*$") then return true end
    end
    return false
end

for _, name in ipairs({ "AGENTS.md", "CLAUDE.md", "tests", "Tools", "docs", ".github" }) do
    H.check(ignored(name), name .. " stays out of the release zip")
end

------------------------------------------------------------
-- The library's dev files are ignored from HERE
--
-- CurseForge's packager, which builds the release from the tag webhook, does
-- not apply an external's own ignore list: Priestly v2.0.6 shipped the
-- library's tests and notes, 46 files instead of 7. Read from the library's
-- own .pkgmeta rather than copied, so a dev file added and ignored there - and
-- so invisible to CI's packager, which does honour it - fails here instead of
-- shipping in the next release. Dot-paths are skipped: both packagers prune
-- those.
------------------------------------------------------------

local libPkgmeta = H.readFile(H.libraryRoot() .. "/.pkgmeta")
H.check(libPkgmeta ~= nil, "the library checkout has a .pkgmeta to mirror")

local mirrored, inIgnore = 0, false
for line in (libPkgmeta or ""):gmatch("[^\n]+") do
    if line:match("^ignore:%s*$") then
        inIgnore = true
    -- A top-level comment does not end a YAML list; a later entry can follow.
    elseif line:match("^%S") and not line:match("^#") then
        inIgnore = false
    elseif inIgnore then
        local entry = line:match("^%s+%-%s+(%S+)")
        -- `external` is the embed path this .pkgmeta declares, so a move to a
        -- 2.0 library leaves these checks pointing at the right place.
        if entry and entry:sub(1, 1) ~= "." then
            mirrored = mirrored + 1
            H.check(ignored(external .. "/" .. entry),
                entry .. " is ignored from here too, not left to the library's own list")
        end
    end
end
H.check(mirrored >= 4, "the library's ignore list was read: " .. mirrored .. " entries")

H.done("test_manifest")
