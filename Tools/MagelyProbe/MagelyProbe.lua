-- ============================================================================
-- MagelyProbe - Magely's in-game release check, as a ForeverProbe module.
--
--   /fp mp state          client, Magely, the running LibGroupBuffs and
--                         LibGlass copies, and which Mage buffs you know
--   /fp mp spells         Magely's spell report and its counts
--   /fp mp rows           which rows the window shows now
--   /fp mp restore        put back the settings the check changed
--   /fp mp clear          empty the saved log
--   /fp steps mp check    the guided check (AGENTS.md, Validation): what is
--                         Mage-specific and not yet seen in play
--
-- The check changes a few of Magely's settings so each mode can be seen
-- (amplifyMode, dampenMode, trackAmplify, trackDampen, showSolo), through
-- Magely's own write path, the way the options panel does. It saves them
-- first and puts them back at the end; /fp mp restore does it by hand if the
-- check is stopped half-way. Nothing else of Magely's is written.
--
-- This is not the cooldown pane's old probe (retired in #75; the pane is
-- Buffy's): the name came back with a different job. Nothing here ships
-- (.pkgmeta ignores Tools).
-- ============================================================================

local ADDON, NS = ...
local MAX_LOG = 3000

-- What this deploy is meant to run. A newer copy loaded by another addon wins
-- through LibStub, so the checks are "at least".
local EXPECT = { gb = 36, glass = 13 }
local SPELL = { intellect = 1459, brilliance = 23028, amplify = 1008, dampen = 604 }
local SAVED_KEYS = { "trackIntellect", "trackAmplify", "trackDampen", "amplifyMode", "dampenMode", "showSolo" }

local Probe = ForeverProbe:Module("MagelyProbe", { api = 1, cmd = "mp" })
local function say(msg) Probe:Say(msg) end
local show = Probe.Show
local function G(name) return rawget(_G, name) end

local DB  -- MagelyProbeDB, bound at the probe's own ADDON_LOADED

local function magely() return G("Magely") end
local function T() local M = magely(); return M and M._test end
local function TC() local M = magely(); return M and M._testConfig end

local function lib(major)
    local LS = G("LibStub")
    if type(LS) ~= "table" then return nil end
    return LS(major, true)
end

local function inCombat()
    local f = G("InCombatLockdown")
    return type(f) == "function" and f() and true or false
end

local function knows(id)
    local f = G("IsPlayerSpell")
    local ok, k = Probe:Try("IsPlayerSpell " .. id, f, id)
    return ok and k and true or false
end

-- Never `db and db[key] or nil`: that turns a saved false into nil.
local function setting(key)
    local db = G("MagelyDB")
    if type(db) ~= "table" then return nil end
    return db[key]
end

-- The value in effect: the saved one, else Magely's default. What the check
-- saves, so a setting the owner never touched comes back as what it meant.
local function effective(key)
    local v = setting(key)
    if v ~= nil then return v end
    local tc = TC()
    return tc and tc.DEFAULTS and tc.DEFAULTS[key]
end

-- ─── measurements ───────────────────────────────────────────────────────────

local function state()
    local _, build = G("GetBuildInfo")()
    local C = G("C_AddOns")
    local okV, version = Probe:Try("Magely version", C and C.GetAddOnMetadata, "Magely", "Version")
    local gb, gbMinor = lib("LibGroupBuffs-1.0")
    local _, glassMinor = lib("LibGlass-1.0")
    local t = T()
    local s = {
        build = build, magely = okV and version or nil, mage = t and t.isMage() or false,
        gb = gbMinor, gbReady = gb and gb.ready, glass = glassMinor,
        intellect = knows(SPELL.intellect), brilliance = knows(SPELL.brilliance),
        amplify = knows(SPELL.amplify), dampen = knows(SPELL.dampen),
    }
    say("client " .. show(build, true) .. ", Magely " .. show(s.magely) .. ", Mage " .. show(s.mage))
    say("LibGroupBuffs r" .. show(gbMinor) .. " (ready " .. show(s.gbReady) .. "), LibGlass r" .. show(glassMinor)
        .. "; expected at least r" .. EXPECT.gb .. " and r" .. EXPECT.glass)
    say("known: Arcane Intellect " .. show(s.intellect) .. ", Arcane Brilliance " .. show(s.brilliance)
        .. ", Amplify Magic " .. show(s.amplify) .. ", Dampen Magic " .. show(s.dampen))
    return s
end

local function stateOK(s)
    s = s or state()
    local missing = {}
    if not s.mage then missing[#missing + 1] = "not a Mage" end
    if not (type(s.gb) == "number" and s.gb >= EXPECT.gb and s.gbReady == s.gb) then
        missing[#missing + 1] = "LibGroupBuffs r" .. show(s.gb)
    end
    if not (type(s.glass) == "number" and s.glass >= EXPECT.glass) then
        missing[#missing + 1] = "LibGlass r" .. show(s.glass)
    end
    if not s.amplify then missing[#missing + 1] = "Amplify Magic unknown (level 18)" end
    if not s.dampen then missing[#missing + 1] = "Dampen Magic unknown (level 12)" end
    return #missing == 0, #missing == 0 and "ready" or table.concat(missing, "; ")
end

local function spells()
    local t = T()
    local engine = t and t.engine
    if not engine then say("spells: Magely has no engine (not a Mage, or not logged in)") return nil end
    local ok, report = Probe:Try("SpellReport", engine.SpellReport, engine)
    if not ok or type(report) ~= "table" then return nil end
    local r = { locale = report.locale, buffs = #report, unresolved = report.unresolved or 0,
                unknown = report.unknown or 0 }
    say("spells (" .. show(r.locale, true) .. "): " .. r.buffs .. " buffs; unresolved " .. r.unresolved
        .. ", unknown " .. r.unknown)
    return r
end

local function spellsOK(r)
    if not r then return false, "no report" end
    return r.unresolved == 0 and r.unknown == 0, "unresolved " .. r.unresolved .. ", unknown " .. r.unknown
end

-- The rows the window shows, by buff id ("intellect", "amplify", "dampen").
local function rows()
    local t = T()
    local out, list = {}, {}
    for _, r in ipairs(t and t.rows() or {}) do
        local id = r._active and r._def and r._def.id
        if id then out[id] = true; list[#list + 1] = id end
    end
    table.sort(list)
    local visible = t and t.ui and t.ui:IsVisible()
    say("window " .. (visible and "open" or "closed") .. "; rows: " .. (#list > 0 and table.concat(list, ", ") or "none"))
    return out, visible
end

-- Waits for Magely's coalesced rebuild, then reads the rows.
local function rowsAfterRebuild()
    local t = T()
    if t then t.UpdateUI() end
    return rows()
end

-- ─── settings: changed through Magely's write path, saved first ────────────

local function saveSettings()
    if DB.saved then say("settings already saved from an earlier start: keeping those") return end
    local saved = {}
    for _, key in ipairs(SAVED_KEYS) do saved[key] = effective(key) end
    DB.saved = saved
    say("saved your settings: amplifyMode " .. show(saved.amplifyMode) .. ", dampenMode " .. show(saved.dampenMode)
        .. ", showSolo " .. show(saved.showSolo))
end

local function apply(changes)
    local set = G("Magely_SetConfig")
    if type(set) ~= "function" then error("Magely_SetConfig is missing (Magely not loaded?)", 0) end
    local solo
    for key, value in pairs(changes) do
        set(key, value)
        if key == "showSolo" then solo = value end
    end
    if solo ~= nil and G("Magely_OnSoloToggle") then Magely_OnSoloToggle(solo) end
    if G("Magely_ForceRebuild") then Magely_ForceRebuild() end
end

local function setModes(mode)
    apply({ trackAmplify = true, trackDampen = true, amplifyMode = mode, dampenMode = mode, showSolo = true })
    say("Amplify and Dampen set to " .. mode)
end

local function restore()
    if not DB or not DB.saved then say("nothing to restore") return true end
    local saved = DB.saved
    apply(saved)
    local ok = true
    for _, key in ipairs(SAVED_KEYS) do
        if setting(key) ~= saved[key] then ok = false end
    end
    say("settings restored" .. (ok and "" or " - but some still differ, check /magely config"))
    if ok then DB.saved = nil end
    return ok
end

-- ─── casts (the clicks) ─────────────────────────────────────────────────────

-- Your own successful casts, counted from the moment a step arms them.
local casts, lastCast, armedAt = 0, nil, nil
local castWatch = G("CreateFrame")("Frame")
Probe:RegisterEvents(castWatch, { "UNIT_SPELLCAST_SUCCEEDED" })
castWatch:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" then return end
    casts = casts + 1
    local secret = G("issecretvalue") and G("issecretvalue")(spellID) and true or false
    lastCast = { id = not secret and spellID or nil, secret = secret, combat = inCombat() }
    say("cast #" .. casts .. ": spellID " .. (secret and "<secret>" or show(spellID)) .. ", combat "
        .. show(lastCast.combat))
end)

local function castSince(wantCombat)
    if not armedAt then armedAt = casts end
    if casts > armedAt and lastCast and (wantCombat == nil or lastCast.combat == wantCombat) then
        return true, lastCast.id, lastCast.combat
    end
    return false, wantCombat and "no cast in combat yet" or "no cast yet"
end
local function arm() armedAt = casts; return casts end

-- ─── commands ───────────────────────────────────────────────────────────────

Probe:Command("state", function() say("check: " .. select(2, stateOK(state()))) end,
    "client, Magely, library copies and known Mage buffs")
Probe:Command("spells", function() spellsOK(spells()) end, "Magely's spell report and its counts")
Probe:Command("rows", function() rows() end, "which rows the window shows now")
Probe:Command("restore", function() restore() end, "put back the settings the check changed")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

-- ─── the procedure ──────────────────────────────────────────────────────────

-- Whether the window shows (or not) the Amplify and Dampen rows, now.
local function rowsMatch(wantAmplify, wantDampen)
    local r = rowsAfterRebuild()
    local ok = (r.amplify == true) == wantAmplify and (r.dampen == true) == wantDampen
    return ok, "amplify " .. show(r.amplify == true) .. ", dampen " .. show(r.dampen == true)
end

-- A wait step's function: done once the rows match.
local function rowWait(wantAmplify, wantDampen)
    return function() return rowsMatch(wantAmplify, wantDampen) end
end

-- /magely show, as typed: the modes are seen in an open window.
local function showWindow()
    local slash = G("SlashCmdList") and SlashCmdList.MAGELY
    if type(slash) ~= "function" then error("SlashCmdList.MAGELY is missing", 0) end
    slash("show")
end

Probe:Steps("check", {
    rev = 2,                                   -- 2: Read refuses outdoors; restore hint
    title = "Magely's in-game check (Mage-specific)",
    { text = "On a Mage of level 18 or higher (Amplify Magic), out of combat, alone or in a party. "
          .. "Type /console scriptErrors 1 once, then press Next. This check changes your Amplify and "
          .. "Dampen modes and puts them back at the end: if you Stop part-way, type /fp mp restore." },
    { text = "Reading the versions and the buffs you know, and saving the settings this check changes.",
      auto = true,
      run = function()
          local s = state()
          saveSettings()
          return s.build, s.magely, s.gb, s.glass, s.amplify, s.dampen
      end,
      check = function() return stateOK() end },
    { text = "Run /magely help. It prints in chat and ends with the spell report.", button = "Run /magely help",
      run = function()
          local slash = G("SlashCmdList") and SlashCmdList.MAGELY
          if type(slash) ~= "function" then error("SlashCmdList.MAGELY is missing", 0) end
          slash("help")
          local r = spells()
          return r and r.unresolved, r and r.unknown
      end,
      check = function() return spellsOK(spells()) end },

    -- always. Each mode is set by a button, then checked by a short wait: the
    -- window rebuilds on a timer, so its rows are read once it has.
    { text = "Set Amplify and Dampen to \"always\". This opens the window.", button = "Set always",
      run = function() setModes("always"); showWindow(); return true end },
    { text = "Both rows should show, with the Intellect row.", timeout = 10, screenshot = "always",
      wait = rowWait(true, true) },

    -- detect
    { text = "Set both to \"detected\". If you or a party member already has Amplify or Dampen, "
          .. "right-click it off (or wait for it to expire) first.", button = "Set detected",
      run = function() setModes("detect"); showWindow(); return true end },
    { text = "Nobody has Amplify or Dampen, so neither row should show.", timeout = 30,
      screenshot = "detected, none", wait = rowWait(false, false) },
    { text = "Cast Amplify Magic on yourself (or a party member). The Amplify row should appear.",
      timeout = 120, screenshot = "detected, amplify",
      wait = function()
          local r = rowsAfterRebuild()
          return r.amplify == true, r.amplify and "amplify row shown" or "amplify row not shown yet"
      end },
    { text = "Now cast Dampen Magic on yourself (it replaces Amplify on that target). The Dampen row should appear.",
      timeout = 120, screenshot = "detected, dampen",
      wait = function()
          local r = rowsAfterRebuild()
          return r.dampen == true, r.dampen and "dampen row shown" or "dampen row not shown yet"
      end },
    { text = "Did each row appear within a second or two of the buff landing, with nothing odd?", ask = true },

    -- instance
    { text = "Outdoors, set both to \"by instance\".", button = "Set by instance",
      run = function()
          local _, instanceType = G("GetInstanceInfo")()
          setModes("instance"); showWindow()
          return instanceType
      end,
      check = function()
          local _, instanceType = G("GetInstanceInfo")()
          return instanceType == "none", "instance type " .. show(instanceType) .. " (this step is for outdoors)"
      end },
    { text = "Outdoors, neither row should show.", timeout = 10, screenshot = "instance, outdoors",
      wait = rowWait(false, false) },
    { text = "Optional - if you can't go to a dungeon today, Skip this step and the next two. "
          .. "Close the window with its X, then enter a dungeon from Magely's list, e.g. Ragefire Chasm "
          .. "(Amplify on by default) or Ruins of Lordaeron.", timeout = 1800,
      wait = function()
          local _, instanceType = G("GetInstanceInfo")()
          return instanceType == "party" or instanceType == "raid", "not in a dungeon yet"
      end },
    { text = "Inside: the window you closed by hand stayed closed?", ask = true, screenshot = "instance, inside" },
    -- Outdoors this refuses to run (the step stays, for Skip) rather than
    -- completing with a FAIL that means only "you skipped the dungeon".
    { text = "Inside the dungeon: reopen the window and read which rows the instance list turns on here. "
          .. "(Skipped the dungeon? Press Skip.)", button = "Read",
      screenshot = "instance rows",
      run = function()
          local _, here = G("GetInstanceInfo")()
          if here == "none" then error("not in an instance: press Skip if you skipped the dungeon", 0) end
          showWindow()
          local name = G("GetInstanceInfo")()
          local tc = TC()
          return name, tc and tc.inInstance("amplify"), tc and tc.inInstance("dampen")
      end,
      check = function()
          local _, instanceType = G("GetInstanceInfo")()
          if instanceType == "none" then return false, "not in an instance (Skip this step if you skipped the dungeon)" end
          local tc = TC()
          if not tc then return false, "no config seam" end
          return rowsMatch(tc.inInstance("amplify") == true, tc.inInstance("dampen") == true)
      end },

    -- clicks
    { text = "Out of combat: press Arm, then left-click Arcane Intellect in Magely's window on yourself.",
      button = "Arm", run = function() return arm() end },
    { text = "Left-click the Intellect row now.", timeout = 180,
      wait = function() return castSince(false) end },
    { text = "Optional, in a party (alone: Skip this step and the next): press Arm, then right-click a row "
          .. "to cast on a party member.",
      button = "Arm", run = function() return arm() end },
    { text = "Right-click a row for a party member now.", timeout = 180,
      wait = function() return castSince(false) end },
    { text = "Did each click land on the one you meant?", ask = true },
    { text = "With the window open, enter combat (a training dummy or a mob).", timeout = 600,
      wait = function() if inCombat() then arm(); return true end; return false, "not in combat yet" end },
    { text = "In combat: click a buff row (any). It should still cast.", timeout = 300,
      wait = function() return castSince(true) end },
    { text = "In combat, do the timers keep counting down, and does a member never seen show ? rather than MISS?",
      ask = true, screenshot = "in combat" },
    { text = "Leave combat.", timeout = 600,
      wait = function() if not inCombat() then return true end; return false, "still in combat" end },

    -- footer and panel
    { text = "The footer: Arcane Powder shows only once Arcane Brilliance is known.", auto = true,
      run = function()
          local t = T()
          local items = t and t.FooterItems() or {}
          return knows(SPELL.brilliance), #items
      end,
      check = function()
          local t = T()
          local n = t and #t.FooterItems() or 0
          local brilliance = knows(SPELL.brilliance)
          return (n > 0) == brilliance, "Brilliance known " .. show(brilliance) .. ", footer items " .. n
      end },
    { text = "Open /magely config. Click through every checkbox, both mode groups, the slider and the "
          .. "Instances tab. All work, nothing odd?", ask = true, screenshot = "options" },

    -- put it back
    { text = "Putting your settings back.", auto = true,
      run = function() return restore() end,
      check = function() return DB.saved == nil, DB.saved and "not restored: /fp mp restore" or "restored" end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

-- ─── boot ───────────────────────────────────────────────────────────────────

local boot = G("CreateFrame")("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    -- rawget: before the first /reload there is no saved table.
    DB = G("MagelyProbeDB")
    if type(DB) ~= "table" then DB = {} rawset(_G, "MagelyProbeDB", DB) end
    if type(DB.log) ~= "table" then DB.log = {} end
    Probe:UseLog(DB.log, MAX_LOG)
    DB.loads = (tonumber(DB.loads) or 0) + 1
    say("loaded (" .. DB.loads .. " loads). /fp mp for the commands; /fp steps mp check"
        .. (DB.saved and " - settings from an unfinished check are saved: /fp mp restore" or ""))
end)

NS._test = { Probe = Probe, state = state, stateOK = stateOK, spells = spells, spellsOK = spellsOK,
             rows = rows, restore = restore, saveSettings = saveSettings, setModes = setModes,
             db = function() return DB end }
