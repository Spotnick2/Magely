-- ============================================================================
-- MagelyCompat.lua  -  the bridge to LibGroupBuffs-1.0.
--
-- Every removed or moved API on WoW: Forever 1.60.1, the buff engine, the
-- window, its open/close policy and the settings write path live in the shared
-- library (Libs\LibGroupBuffs-1.0, loaded by the TOC after LibGlass-1.0, the
-- glass material its window draws with). This file asks the library for
-- Magely's own instance and exposes it:
--
--     Magely.GB         the instance: GB.Engine(host), GB.UI(host),
--                         GB.Settings(spec), GB.Visibility(spec), GB.STATES, ...
--     Magely.API        the compat layer, GB.API, under the name the rest of
--                         Magely already uses
--
-- lib:New does the version check this file used to carry by hand: it refuses
-- a copy that did not finish loading, a missing or half-loaded LibGlass, and
-- one older than NEEDS_MINOR. No fallback copy lives here on purpose. If the
-- library is missing or refuses, Magely says so in chat and does not start,
-- instead of running on a stale duplicate.
-- ============================================================================

Magely = Magely or {}

-- The oldest library this build of Magely works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r26 is where
-- lib:New arrived, so it is also the floor this file can be written against.
-- Keep this equal to the MINOR .pkgmeta pins; tests/test_manifest.lua checks
-- that.
local NEEDS_MINOR = 26

-- Magely's own record of the events this client rejected, for
-- `/dump Magely.eventFailures`. The library also keeps it, as
-- API.eventFailuresByOwner.Magely; this copy is the short name to type.
Magely.eventFailures = Magely.eventFailures or {}

-- Per-kind rewording for the one reporter below, filled in by the files that
-- own each kind (MagelyConfig.lua: newBuild, settingsLoaded). Looked up when
-- a report arrives, so a filter installed after this file loads is the one
-- that runs. A filter returns the text to print, or nil to say nothing.
Magely.reportFilters = Magely.reportFilters or {}

local GB

-- How Magely tells the player. The library never prints - it has no
-- business writing to another addon's chat frame - so everything it has to
-- say arrives here: the settings checks, and with kind "events" the names
-- the client rejected, whether it threw or returned false.
local function Report(text, kind)
    if kind == "events" then
        text = tostring(text)
        -- Recorded whether or not anything can be printed: the record is what
        -- `/dump Magely.eventFailures` reads when the line was never seen.
        local mine = GB and GB.EventFailures() or {}
        for ev, why in pairs(mine) do Magely.eventFailures[ev] = why or true end
        -- The label in red, the names plain - whatever the library calls it.
        -- Its wording is the library's to change, so this matches the shape
        -- ("label: names"), not the words, and a line without a colon is red
        -- throughout rather than plain.
        local label, names = text:match("^([^:]*:)(.*)$")
        text = label and ("|cffff6666" .. label .. "|r" .. names) or ("|cffff6666" .. text .. "|r")
    end
    -- Before any filter: a filter may record that it spoke (newBuild does),
    -- and with no chat frame nothing was said.
    if not DEFAULT_CHAT_FRAME then return end
    local filter = Magely.reportFilters[kind]
    if filter then text = filter(text, kind) end
    if text then DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r " .. text) end
end

local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end

-- What a player can do about a copy that did not finish loading. The copy
-- LibStub runs is the newest any addon shipped, so it may well not be
-- Magely's - and errors are hidden by default, so say how to see them.
local SEE_WHICH = " - one addon's copy of it failed. With /console scriptErrors 1 and /reload,"
    .. " the first error names that addon; updating or disabling it should fix this"

-- Why lib:New refused, in the words a player needs. New checks, in order:
-- the active copy finished loading (lib.ready, the library's marker), LibGlass
-- is there and finished loading (its own `ready` marker), and the active copy
-- is at least the floor. The same three facts are read here, in the same
-- order, from the libraries' documented markers - never from the error's
-- words, which are the library's to change. Anything else New throws is not
-- one of its refusals (a bug, or a host mistake such as a second New for the
-- same owner) and reads as a failed load; its text goes to developers only.
-- LibGroupBuffs#54 asks for New to raise this as a structured reason.
local function WhyRefused()
    local _, active = LibStub:GetLibrary("LibGroupBuffs-1.0", true)
    if lib.ready ~= active then
        return "the LibGroupBuffs-1.0 library (r" .. tostring(active) .. ") did not finish loading"
            .. SEE_WHICH
    end
    local glass, glassMinor = LibStub:GetLibrary("LibGlass-1.0", true)
    if type(glass) ~= "table" then
        -- Not registered at all: no addon's copy loaded, and Magely ships
        -- one in its own Libs folder, so it is Magely's install.
        return "the LibGlass-1.0 library is missing from Magely's Libs folder."
            .. " Reinstalling Magely should fix it"
    end
    if glass.ready ~= glassMinor then
        -- Registered but never ready: the newest copy threw partway. Magely's
        -- own copy loaded, or the name would not be registered at all, so
        -- reinstalling Magely would change nothing.
        return "the LibGlass-1.0 library (r" .. tostring(glassMinor) .. ") did not finish loading"
            .. SEE_WHICH
    end
    if type(active) == "number" and active < NEEDS_MINOR then
        return "this version of Magely needs the LibGroupBuffs-1.0 library r" .. NEEDS_MINOR
            .. " or newer, and the newest copy loaded is r" .. tostring(active)
            .. ". Reinstalling Magely should fix it"
    end
    return "the LibGroupBuffs-1.0 library failed to load completely. Reinstalling Magely should fix it"
end

local problem, detail
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Magely's Libs folder."
        .. " Reinstalling Magely should fix it"
elseif type(lib.New) ~= "function" then
    -- The TOC loads Magely's own copy of the library before this file, and
    -- LibStub UPGRADES an older copy another addon loaded first - so a copy
    -- without New cannot be another addon's doing. Below the floor, Magely's
    -- own copy never registered; at or above it, the copy threw before New
    -- was installed. Neither is a reason to send the player off to update
    -- other addons.
    if type(minor) == "number" and minor < NEEDS_MINOR then
        problem = "the LibGroupBuffs-1.0 library in Magely's Libs folder is r" .. tostring(minor)
            .. ", and this version of Magely needs r" .. NEEDS_MINOR
            .. " - its own copy did not load. Reinstalling Magely should fix it"
    else
        problem = "the LibGroupBuffs-1.0 library failed to load completely."
            .. " Reinstalling Magely should fix it"
    end
else
    -- Under pcall: New is library code on a shared table, and its refusals are
    -- errors. A throw escaping here would skip the chat message below and
    -- leave Magely silently dead, since this client hides Lua errors by
    -- default.
    local ok, made = pcall(lib.New, lib, { owner = "Magely", report = Report, needs = NEEDS_MINOR })
    if ok then
        GB = made
    else
        detail = tostring(made)
        -- Under pcall too: it reads shared tables another copy may have left
        -- half-built, and a throw here must still end in the chat line.
        local asked, why = pcall(WhyRefused)
        problem = asked and why
            or "the LibGroupBuffs-1.0 library failed to load completely. Reinstalling Magely should fix it"
    end
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- MagelyConfig.lua and Magely.lua both check Magely.API and stop
    -- before building anything, so there is exactly one message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r |cffff6666Magely cannot start:|r "
            .. problem .. ".")
    end
    error("Magely: " .. problem .. " (Libs\\LibGroupBuffs-1.0, Libs\\LibGlass-1.0"
        .. (detail and detail ~= problem and ("; lib:New said: " .. detail) or "")
        .. "). Developers: check out LibGroupBuffs and LibGlass next to the repository and run "
        .. "Tools/deploy.ps1.")
end

Magely.GB = GB
Magely.API = GB.API

-- Event registration, with the failures reported. Magely code must use this,
-- never the library's registration directly (tests/test_bridge.lua enforces
-- it), so the reporter is never left out.
function Magely.RegisterEvents(frame, ...)
    return GB.RegisterEvents(frame, ...)
end
