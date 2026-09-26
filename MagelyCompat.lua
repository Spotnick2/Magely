-- ============================================================================
-- MagelyCompat.lua  -  the bridge to LibGroupBuffs-1.0.
--
-- Every removed or moved API on WoW: Forever 1.60.1, the buff engine and the
-- buff window live in the shared library (Libs\LibGroupBuffs-1.0, loaded
-- first by the TOC), which Priestly and Wildly embed too. This file checks
-- the library loaded completely and exposes it under Magely's names:
--
--     local API = Magely.API
--
-- No fallback copy lives here on purpose. If the library is missing or broken,
-- Magely says so in chat and does not start, instead of running on a stale
-- duplicate.
-- ============================================================================

Magely = Magely or {}

-- The oldest library this build of Magely works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r12 is the
-- first with lib.Status. Keep this equal to the tag .pkgmeta pins;
-- tests/test_manifest.lua checks that.
local NEEDS_MINOR = 14

local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end

-- Is the ACTIVE copy usable? That is the library's own question to answer
-- (lib.Status): which files it consists of, and whether each one reached its
-- last line under the active MINOR, are its internals. Priestly and Wildly
-- each carried a hand-written copy of that check, and both got it wrong the
-- same way (Spotnick2/priestly#52).
--
-- Status is installed by the library's LAST file, so its absence has two
-- meanings. A copy at least as new as the floor without it means its last
-- file threw: "incomplete". An older copy that predates it (r11 or earlier,
-- brought by another addon while Magely's own is missing) is too old - but
-- it can ALSO be half-loaded, and incomplete wins, as it does in Status.
--
-- For those older copies only, the answer comes from the named markers they
-- set on each file's last line. That is not the internals-copying Status
-- replaced: the tags are released and never change, so this list cannot
-- drift. r6 to r11 set all four; r2 to r5 predate them, cannot say whether
-- they finished, and are too old whatever the answer.
local LEGACY_MARKERS_FROM = 6

local function LegacyComplete(l, m)
    if m < LEGACY_MARKERS_FROM then return true end
    return l.compatMinor == m and l.settingsMinor == m
        and l.engineMinor == m and l.uiMinor == m
end

-- Written out branch by branch on purpose: `a and f() or b` keeps only the
-- first value f returns, which would lose the active MINOR.
local status, active
if not lib then
    status = "missing"
elseif type(lib.Status) == "function" then
    status, active = lib.Status(NEEDS_MINOR)
elseif type(minor) == "number" and minor < NEEDS_MINOR then
    active = minor
    status = LegacyComplete(lib, minor) and "too-old" or "incomplete"
else
    status = "incomplete"
end

local problem
if status == "missing" then
    problem = "the LibGroupBuffs-1.0 library is missing from Magely's Libs folder"
elseif status == "too-old" then
    -- Complete, just old. Said separately, because it is a different fault:
    -- nothing crashed. LibStub runs the newest copy any addon brought, so an
    -- older one being active means Magely's own copy is missing or stale.
    problem = "the LibGroupBuffs-1.0 library in use is r" .. tostring(active)
        .. ", older than the r" .. NEEDS_MINOR .. " this Magely needs"
elseif status ~= "ok" then
    -- "incomplete", or an answer this build does not know - which a newer
    -- library could only give for a copy that is not usable either.
    problem = "the LibGroupBuffs-1.0 library failed to load completely"
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- Once they are ported (AGENTS.md, Port status), MagelyConfig.lua and
    -- Magely.lua check Magely.API and stop before building anything, so this
    -- is the only message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r |cffff6666Magely cannot start:|r "
            .. problem .. ". Reinstalling Magely should fix it.")
    end
    error("Magely: " .. problem .. " (Libs\\LibGroupBuffs-1.0). Developers: check out "
        .. "LibGroupBuffs next to the repository and run Tools/deploy.ps1.")
end

Magely.API = lib.API
-- The settings write path and the client-fix watches; MagelyConfig.lua builds
-- Magely's settings object from it.
Magely.Settings = lib.Settings
-- The buff engine; Magely.lua builds Magely's engine from it.
Magely.Engine = lib.Engine
-- The buff window; Magely.lua builds Magely's from it.
Magely.UI = lib.UI

-- Magely's own record of the events this client rejected, for
-- `/dump Magely.eventFailures`. The library also keeps it, as
-- API.eventFailuresByOwner.Magely; this copy is the short name to type.
Magely.eventFailures = Magely.eventFailures or {}

-- How Magely tells the player. The library never prints - it has no business
-- writing to another addon's chat frame - so it calls this with the names the
-- client rejected, whether it threw or returned false.
local function ReportRejected(failed)
    local mine = lib.API.eventFailuresByOwner and lib.API.eventFailuresByOwner.Magely or {}
    for _, ev in ipairs(failed) do
        Magely.eventFailures[ev] = mine[ev] or true
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r |cffff6666unsupported events skipped:|r "
            .. table.concat(failed, ", "))
    end
end

-- Event registration, with the failures reported. Magely code must use this,
-- never the library's registration directly (tests/test_bridge.lua enforces
-- it), so the reporter is never left out.
function Magely.RegisterEvents(frame, ...)
    return lib.API.RegisterEventsReported(frame, "Magely", ReportRejected, ...)
end
