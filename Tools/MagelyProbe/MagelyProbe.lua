-- ============================================================================
-- MagelyProbe  -  throwaway API probe for Magely's cooldown pane on WoW:
-- Forever 1.60.1. A ForeverProbe module: /fp mp.
--
-- The TBC Magely had a second pane: Innervate and Power Infusion providers,
-- their cooldowns, and a click to whisper a request. Every data source it used
-- is gone or forbidden here, so before the pane comes back (slice 5,
-- Spotnick2/LibGroupBuffs#24) this measures what it could stand on instead.
-- Most of it needs no Mage and no level 40: any character in a group can run
-- it.
--
--   /fp mp spells               do the Mage / Druid / Priest spell IDs resolve?
--   /fp mp cast on|off          watch UNIT_SPELLCAST_SUCCEEDED for group units
--   /fp mp pane build           (out of combat) a protected frame + a plain pane
--   /fp mp pane test            (IN combat) try to hide/resize/move the pane
--   /fp mp pane remove          (out of combat) take them away again
--   /fp mp whisper <name>       whisper a (surnamed) name through C_ChatInfo
--   /fp mp inspect              inspect your target and read its talents
--   /fp mp report               everything recorded this session
--   /fp mp reset                forget this session's results (the log stays)
--   /fp mp clear                empty the saved log
--
-- The experiments that need the owner's hands are procedures (/fp steps mp
-- <name>): `casts` (do other players' casts arrive?), `talents` (do talents
-- live in the traits system?) and `pane` (a plain pane under the protected
-- window, in combat).
--
-- Lines go to the /fp console and MagelyProbeDB.log; this session's answers
-- are in MagelyProbeDB.results, .casts, .samples and .blocked. /reload writes
-- them to _forever_\WTF\Account\<id>\SavedVariables\MagelyProbe.lua. Copy the
-- answers into docs/FOREVER-NOTES.md.
--
-- Every client global is read with rawget, so an API this client lacks is
-- recorded as missing rather than throwing - a probe that dies on the first
-- absent function measures nothing after it. Every touch of event data happens
-- inside pcall: in combat it can be a SECRET value, which throws when compared
-- or truth-tested, not only when read.
--
-- Nothing here ships (.pkgmeta ignores Tools). Delete it once the pane is
-- built or abandoned.
-- ============================================================================

local ADDON, NS = ...
local MAX_LOG = 3000

local FP = ForeverProbe
local Probe = FP:Module("MagelyProbe", { api = 1, cmd = "mp" })

local function G(name) return rawget(_G, name) end
local function Say(text) Probe:Say(text) end

-- The probe's own state, for the event handlers and the test seam
-- (NS._test, never a global): the pane's frames live here.
local P = {}

-- MagelyProbeDB, bound at the probe's own ADDON_LOADED: the client loads
-- SavedVariables AFTER the addon's files, so a table made at file scope would
-- be replaced and its writes lost (the guide's section 1; this probe's old bug).
local DB

-- A measurement belongs to the session - and the build - it was taken in, so
-- each load starts the results afresh. The log is kept across sessions: each
-- line carries its run number.
local function NewSession()
    local gb = G("GetBuildInfo")
    DB.build = gb and select(2, gb()) or nil
    DB.results, DB.casts, DB.samples, DB.blocked = {}, {}, {}, {}
end

local function Record(key, value)
    if not DB then Say("not loaded yet: " .. key) return end
    DB.results[key] = value
    Say(key .. ": " .. tostring(value))
end

local function InCombat()
    local f = G("InCombatLockdown")
    return f and f() and true or false
end

-- Is v a secret value? Answered without touching v in a way that could throw.
local function Secret(v)
    local test = G("issecretvalue")
    if not test then return nil end
    local ok, is = pcall(test, v)
    if not ok then return "issecretvalue threw" end
    return is and true or false
end

------------------------------------------------------------
-- Spells and items, by ID
------------------------------------------------------------

local SPELLS = {
    { id = 1459,  label = "Arcane Intellect" },
    { id = 23028, label = "Arcane Brilliance" },
    { id = 1008,  label = "Amplify Magic" },
    { id = 604,   label = "Dampen Magic" },
    { id = 12042, label = "Arcane Power (Arcane 31)" },
    { id = 11129, label = "Combustion (Fire 31)" },
    { id = 11426, label = "Ice Barrier (Frost 31)" },
    { id = 29166, label = "Innervate (Druid, baseline 40)" },
    { id = 10060, label = "Power Infusion (Priest talent)" },
}
local ITEMS = { { id = 17020, label = "Arcane Powder" } }

local function ProbeSpells()
    local CS, SB, CI = G("C_Spell"), G("C_SpellBook"), G("C_Item")
    for _, s in ipairs(SPELLS) do
        local name, known = "C_Spell.GetSpellInfo missing", "C_SpellBook.IsSpellKnown missing"
        if CS and CS.GetSpellInfo then
            local ok, info = pcall(CS.GetSpellInfo, s.id)
            name = (not ok and ("threw: " .. tostring(info)))
                or (info and tostring(info.name)) or "nil (does not resolve)"
        end
        if SB and SB.IsSpellKnown then
            local ok, k = pcall(SB.IsSpellKnown, s.id)
            known = ok and tostring(k) or ("threw: " .. tostring(k))
        end
        Record("spell " .. s.id .. " " .. s.label, name .. " / known=" .. known)
    end
    for _, it in ipairs(ITEMS) do
        local icon = "C_Item.GetItemIconByID missing"
        if CI and CI.GetItemIconByID then
            local ok, v = pcall(CI.GetItemIconByID, it.id)
            icon = ok and tostring(v) or ("threw: " .. tostring(v))
        end
        Record("item " .. it.id .. " " .. it.label, "icon=" .. icon)
    end
end

------------------------------------------------------------
-- UNIT_SPELLCAST_SUCCEEDED for group units
--
-- The TBC pane learned about Innervate and Power Infusion casts from the combat
-- log. Registering COMBAT_LOG_EVENT_UNFILTERED is a forbidden action here
-- (PORTING doc section 3), so the candidate is UNIT_SPELLCAST_SUCCEEDED
-- (unitTarget, castGUID, spellID) - if it fires for other group members, and
-- if spellID can be read in combat. Counted per kind of unit, per combat
-- state, per whether the ID was readable.
------------------------------------------------------------

local castFrame

local function UnitKind(unit)
    local ok, kind = pcall(function()
        if unit == "player" then return "player" end
        if unit == "pet" then return "pet" end
        if unit:find("^partypet") or unit:find("^raidpet") then return "grouppet" end
        if unit:find("^party") then return "party" end
        if unit:find("^raid") then return "raid" end
        return "other"
    end)
    return ok and kind or "unreadable unit"
end

function P.OnCast(unit, castGUID, spellID)
    if not DB then return end
    local combat = InCombat() and "combat" or "nocombat"
    local secret = Secret(spellID)
    local readable, name = "readable", nil
    local ok = pcall(function()
        if secret == true then readable = "SECRET" return end
        local id = spellID + 0            -- throws on a secret the test missed
        local CS = G("C_Spell")
        local info = CS and CS.GetSpellInfo and CS.GetSpellInfo(id)
        name = info and info.name
    end)
    if not ok then readable = "THREW" end
    local key = UnitKind(unit) .. "/" .. combat .. "/" .. readable
    DB.casts[key] = (DB.casts[key] or 0) + 1
    if #DB.samples < 40 then
        DB.samples[#DB.samples + 1] = key .. " " .. tostring(name)
    end
end

local function WatchCasts(on)
    if on then
        if castFrame then Say("already watching") return end
        castFrame = G("CreateFrame")("Frame")
        -- The module's helper logs a throw (unknown event) or a refusal itself.
        local registered = Probe:RegisterEvents(castFrame, { "UNIT_SPELLCAST_SUCCEEDED" })
        Record("UNIT_SPELLCAST_SUCCEEDED registers", tostring(registered))
        castFrame:SetScript("OnEvent", function(_, _, ...) P.OnCast(...) end)
        Say("watching casts. Have party members cast anything, in and out of combat, then /fp mp report.")
    else
        if castFrame then castFrame:UnregisterAllEvents() castFrame = nil end
        Say("stopped watching casts")
    end
end

-- How many casts of one kind of unit were seen this session, any state.
local function CastsBy(kind, state)
    local n = 0
    for key, count in pairs(DB and DB.casts or {}) do
        local k, s = key:match("^([^/]+)/([^/]+)/")
        if k == kind and (state == nil or s == state) then n = n + count end
    end
    return n
end

------------------------------------------------------------
-- A plain pane anchored to a protected frame, in combat
--
-- Magely's window parents secure buttons, so the client refuses to hide or
-- move it in combat (Priestly probe section 13). The pane would be a plain
-- frame anchored under it. Measured on 70009 (docs/FOREVER-NOTES.md): the pane
-- stays free. The procedure `pane` repeats it on a new build.
--
-- A refusal is silent: the call does nothing and ADDON_ACTION_BLOCKED fires,
-- blamed on whichever addon's taint the call path carries (Priestly probe
-- section 13), not necessarily this one. So each attempt is judged by whether
-- it TOOK EFFECT, and the blocked events it raised are reported with the
-- function and the addon they were blamed on - never as a bare count, and not
-- at all if the watcher could not register.
--
-- ForeverProbe's baseline is the one ADDON_ACTION_BLOCKED / FORBIDDEN watcher
-- (a module never registers its own). It offers no way to ask which blocked
-- actions one call raised, or whether its watcher registered, so until it
-- does (Spotnick2/ForeverProbe#19) the probe reads them from the host: the
-- watcher frame's IsEventRegistered, and the host's lines in ForeverProbe.lines.
------------------------------------------------------------

-- true / false, or nil when it cannot be told.
local function BlockWatch()
    local B = FP.Baseline
    local frame = B and B.taintFrame
    if not frame then return false end
    local ok, all = pcall(function()
        return frame:IsEventRegistered("ADDON_ACTION_BLOCKED")
            and frame:IsEventRegistered("ADDON_ACTION_FORBIDDEN") and true or false
    end)
    if not ok then return nil end
    return all
end

local function LastLine()
    local lines = FP.lines
    return lines[#lines]
end

-- The host's blocked-action lines written after `mark`, oldest first, as
-- "EVENT: function blamed on addon".
local function BlockedSince(mark)
    local out, lines = {}, FP.lines
    for i = #lines, 1, -1 do
        local line = lines[i]
        if line == mark then break end
        if line.m == FP.host.name then
            local event, who, fn = FP.Plain(line.text):match("(ADDON_ACTION_%u+) (%S+) (.*)$")
            if event then table.insert(out, 1, event .. ": " .. fn .. " blamed on " .. who) end
        end
    end
    return out
end

local function PaneBuild()
    if InCombat() then Say("build it out of combat") return end
    if P.pane then Say("already built") return end
    local CF, UIP = G("CreateFrame"), G("UIParent")
    local parent = CF("Frame", nil, UIP)
    parent:SetSize(120, 60)
    parent:SetPoint("CENTER", UIP, "CENTER", 0, 150)
    local secure = CF("Button", nil, parent, "SecureActionButtonTemplate")
    secure:SetAllPoints(parent)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.4, 0.8)
    -- Explicitly shown: the control below reads "did Hide take effect" from
    -- IsShown, which would be true of a frame that was never shown at all.
    parent:Show()

    local pane = CF("Frame", nil, UIP)
    pane:SetSize(120, 40)
    pane:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
    local pbg = pane:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.4, 0.1, 0.1, 0.8)
    pane:Show()

    P.parent, P.pane = parent, pane
    local watch = BlockWatch()
    Record("blocked-action watcher registered", watch == nil and "unknown" or tostring(watch))
    local okP, prot = pcall(function() return tostring(parent:IsProtected()) end)
    Record("pane built; stand-in IsProtected", okP and prot or "unreadable")
    Say("blue = the protected stand-in, red = the plain pane under it. Start a fight, then /fp mp pane test.")
end

-- One attempted change: whether it threw, whether it took effect, and which
-- blocked actions it raised. Returns whether it took effect.
local function Attempt(label, act, check)
    local mark = LastLine()
    local ok, err = pcall(act)
    local okCheck, result = pcall(check)
    local took = okCheck and result and true or false
    local blocked
    if BlockWatch() ~= true then
        blocked = "blocked events unavailable (the host's watcher is not registered, or can't be told)"
    else
        local seen = BlockedSince(mark)
        for _, b in ipairs(seen) do DB.blocked[#DB.blocked + 1] = b end
        blocked = #seen == 0 and "no blocked event" or ("raised " .. table.concat(seen, "; "))
    end
    Record("pane " .. label, string.format("%s, took effect=%s, %s",
        ok and "no error" or ("threw: " .. tostring(err)), tostring(took), blocked))
    return took
end

local function PaneTest()
    local pane, parent = P.pane, P.parent
    if not pane then Say("run /fp mp pane build first, out of combat") return end
    Record("pane test in combat", tostring(InCombat()))
    -- Read defensively: a number the client does not hand back must not end
    -- the probe before the calls that matter have been tried.
    local okH, h = pcall(pane.GetHeight, pane)
    h = okH and tonumber(h) or 40
    Attempt("SetHeight", function() pane:SetHeight(h + 20) end,
        function() return math.abs(pane:GetHeight() - (h + 20)) < 0.5 end)
    Attempt("re-anchor", function()
        pane:ClearAllPoints()
        pane:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 4)
    end, function()
        local point = pane:GetPoint()
        return point == "BOTTOMLEFT"
    end)
    -- Show only means something from hidden: after a refused Hide the pane is
    -- still shown, and "shown after Show" would pass without anything having
    -- happened.
    if Attempt("Hide", function() pane:Hide() end, function() return not pane:IsShown() end) then
        Attempt("Show", function() pane:Show() end, function() return pane:IsShown() end)
    else
        Record("pane Show", "untestable: Hide was refused, so the pane never left the screen")
    end
    -- The control: this one SHOULD be refused in combat.
    Attempt("Hide the PROTECTED stand-in (control)", function() parent:Hide() end,
        function() return not parent:IsShown() end)
end

local function PaneRemove()
    if InCombat() then Say("remove it out of combat") return end
    if P.pane then P.pane:Hide() P.pane = nil end
    if P.parent then P.parent:Hide() P.parent = nil end
    Say("pane removed")
end

------------------------------------------------------------
-- A whisper to a surnamed name
--
-- Addon messages to "First Surname" are measured to route (PORTING doc,
-- surnames). A chat WHISPER through C_ChatInfo is not. Whether it arrived can
-- only be seen by the recipient, so this records only whether the call was
-- accepted. The whisper itself is a deliberate chat stimulus.
------------------------------------------------------------

local function Whisper(target)
    if not target or target == "" then Say("usage: /fp mp whisper First Surname") return end
    local CI = G("C_ChatInfo")
    local send = (CI and CI.SendChatMessage) or G("SendChatMessage")
    local via = (CI and CI.SendChatMessage) and "C_ChatInfo.SendChatMessage" or "SendChatMessage"
    if not send then Record("whisper", "no SendChatMessage at all") return end
    local ok, err = pcall(send, "[MagelyProbe] whisper test - please tell the sender if this arrived",
        "WHISPER", nil, target)
    Record("whisper via " .. via .. " to \"" .. target .. "\"",
        ok and "accepted (ask the recipient whether it arrived)" or ("threw: " .. tostring(err)))
end

------------------------------------------------------------
-- Talents of an inspected unit
--
-- GetTalentInfo(tab, idx, inspect, unit) is gone. The dump has
-- C_SpecializationInfo.GetTalentInfo(query) with TalentInfoQuery
-- { groupIndex, isInspect, tier, column, target, specializationIndex,
--   talentIndex, isPet }. Which fields address a Vanilla talent tree is the
-- question, so both shapes are tried and every hit is recorded.
--
-- A result may be a secret value, and a secret throws when truth-tested, not
-- only when read - so the call, the nil test and every field read happen in
-- one pcall, which hands back plain strings.
------------------------------------------------------------

local inspectFrame
-- The GUID /fp mp inspect asked about. INSPECT_READY for anybody else -
-- another addon's inspection, or a target changed since - is not this answer.
local inspectGUID

local function QueryTalents(isInspect, unit)
    local CSI = G("C_SpecializationInfo")
    if not (CSI and CSI.GetTalentInfo) then
        Record("GetTalentInfo", "C_SpecializationInfo.GetTalentInfo missing")
        return
    end
    local who = isInspect and "inspected" or "own"
    local shapes = {
        { label = "specializationIndex/talentIndex", make = function(a, b)
            return { isInspect = isInspect, target = unit, specializationIndex = a, talentIndex = b } end,
          outer = 3, inner = 30 },
        { label = "tier/column", make = function(a, b)
            return { isInspect = isInspect, target = unit, tier = a, column = b } end,
          outer = 10, inner = 4 },
        -- Measured on 70009: the index shape throws "query.tier must be
        -- specified", and tier/column alone finds nothing - so the tree may
        -- be what is missing. `a` is the tree; `b` walks tiers 1-10 by
        -- columns 1-4.
        { label = "specializationIndex/tier/column", make = function(a, b)
            return { isInspect = isInspect, target = unit, specializationIndex = a,
                     tier = math.floor((b - 1) / 4) + 1, column = (b - 1) % 4 + 1 } end,
          outer = 3, inner = 40 },
    }
    for _, shape in ipairs(shapes) do
        local hits, errors, firstErr, examples = 0, 0, nil, {}
        for a = 1, shape.outer do
            for b = 1, shape.inner do
                local ok, kind, text = pcall(function()
                    local res = CSI.GetTalentInfo(shape.make(a, b))
                    if res == nil then return "none" end
                    return "hit", string.format("%d,%d=%s r%s/%s", a, b, tostring(res.name),
                        tostring(res.rank), tostring(res.maxRank))
                end)
                if not ok then
                    errors = errors + 1
                    firstErr = firstErr or tostring(kind)
                elseif kind == "hit" then
                    hits = hits + 1
                    if #examples < 4 then examples[#examples + 1] = text end
                end
            end
        end
        Record(who .. " talents by " .. shape.label, string.format("%d hits, %d errors%s%s",
            hits, errors, firstErr and (" (first: " .. firstErr .. ")") or "",
            #examples > 0 and (" e.g. " .. table.concat(examples, "; ")) or ""))
    end
end

-- A specialization ID, by name. Measured on 70009: GetInspectSpecialization
-- answers 1486 for a target, which is no Retail spec ID - so ask the client
-- what it is rather than guess. Through GetSpecializationInfoForSpecID, the
-- one the 70009 dump documents with its return order (id, name, description,
-- icon, role, ...); GetSpecializationInfoByID is only in its names-only list.
local function RecordSpecName(who, spec)
    local byID = G("GetSpecializationInfoForSpecID")
    if not byID then Record(who .. " spec by ID", "GetSpecializationInfoForSpecID missing") return end
    local ok, text = pcall(function()
        local id, name, _, _, role = byID(spec)
        return string.format("%s = %s (role %s)", tostring(id), tostring(name), tostring(role))
    end)
    Record(who .. " spec by ID", ok and text or ("threw: " .. tostring(text)))
end

-- Measured on 70009: C_SpecializationInfo.GetTalentInfo answers nothing in
-- any shape, even for your own talents. Forever may keep talents in Retail's
-- traits system instead; the first question is whether there is a config.
local function RecordTraitConfig()
    local CT, TR = G("C_ClassTalents"), G("C_Traits")
    if not (CT and CT.GetActiveConfigID) then
        Record("C_ClassTalents.GetActiveConfigID", "missing") return
    end
    -- A missing function, a nil answer and a config with empty fields are
    -- three different findings, and must not read alike.
    local ok, text = pcall(function()
        local id = CT.GetActiveConfigID()
        if id == nil then return "nil (no active talent config)" end
        local head = tostring(id) .. "; "
        if not (TR and TR.GetConfigInfo) then return head .. "C_Traits.GetConfigInfo missing" end
        local info = TR.GetConfigInfo(id)
        if info == nil then return head .. "GetConfigInfo answered nil" end
        return head .. string.format("GetConfigInfo: name=%s type=%s trees=%s",
            tostring(info.name), tostring(info.type),
            tostring(type(info.treeIDs) == "table" and #info.treeIDs or info.treeIDs))
    end)
    Record("C_ClassTalents.GetActiveConfigID", ok and text or ("threw: " .. tostring(text)))
end

local IGNORED = "INSPECT_READY ignored (not the requested unit)"

function P.OnInspectReady(guid)
    if not DB then return end
    local UG = G("UnitGUID")
    local okMatch, isOurs = pcall(function() return inspectGUID ~= nil and guid == inspectGUID end)
    if not (okMatch and isOurs) then
        -- Somebody else's inspection (another addon's, or an older request of
        -- ours): not this measurement, and not ours to clear.
        DB.results[IGNORED] = (DB.results[IGNORED] or 0) + 1
        return
    end
    inspectGUID = nil
    local okT, stillTarget = pcall(function() return UG and UG("target") == guid end)
    if not (okT and stillTarget) then
        Record("INSPECT_READY", "arrived after the target changed - not queried, run it again")
    else
        Record("INSPECT_READY", "for the requested target")
        QueryTalents(true, "target")
        local CSI = G("C_SpecializationInfo")
        if CSI and CSI.GetInspectSpecialization then
            local okS, spec = pcall(CSI.GetInspectSpecialization, "target")
            local okText, text = pcall(tostring, spec)
            Record("GetInspectSpecialization(target)",
                (okS and okText) and text or ("threw: " .. tostring(okS and text or spec)))
            if okS then RecordSpecName("inspected", spec) end
        end
    end
    local clear = G("ClearInspectPlayer")
    if clear then pcall(clear) end
end

local function OwnTalents()
    -- Your own talents first, as the control: if these read nothing, neither
    -- shape addresses a Vanilla tree at all.
    QueryTalents(false, nil)
    RecordTraitConfig()
end

-- Sends the inspection; true when a request went out.
local function SendInspect()
    local UE, UG, CanI, Notify = G("UnitExists"), G("UnitGUID"), G("CanInspect"), G("NotifyInspect")
    if not (UE and UE("target")) then Say("target someone with talents and run it again") return false end
    if not (CanI and Notify) then
        Record("inspect", string.format("CanInspect %s, NotifyInspect %s",
            CanI and "present" or "MISSING", Notify and "present" or "MISSING"))
        return false
    end
    -- One argument, as the 69977 dump declares it: CanInspect(targetGUID:UnitToken).
    local okC, can = pcall(function() return CanI("target") and true or false end)
    Record("CanInspect(target)", okC and tostring(can) or ("threw: " .. tostring(can)))
    if not (okC and can) then
        Say("the client says this target cannot be inspected - get closer, or try another")
        return false
    end
    if not inspectFrame then
        inspectFrame = G("CreateFrame")("Frame")
        local registered = Probe:RegisterEvents(inspectFrame, { "INSPECT_READY" })
        Record("INSPECT_READY registers", tostring(registered))
        inspectFrame:SetScript("OnEvent", function(_, _, guid) P.OnInspectReady(guid) end)
    end
    local okG, guid = pcall(function() return UG and UG("target") end)
    inspectGUID = okG and guid or nil
    local okN, err = pcall(Notify, "target")
    -- No request went out, so no INSPECT_READY is ours: somebody else's
    -- inspection of the same unit must not be published under this one.
    if not okN then inspectGUID = nil end
    Record("NotifyInspect(target)", okN and "sent - waiting for INSPECT_READY" or ("threw: " .. tostring(err)))
    return okN
end

local function Inspect()
    OwnTalents()
    SendInspect()
end

------------------------------------------------------------
-- Report
------------------------------------------------------------

local function Report()
    if not DB then Say("not loaded yet") return end
    Say("build " .. tostring(DB.build) .. " - results:")
    local keys = {}
    for k in pairs(DB.results) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do Say("  " .. k .. ": " .. tostring(DB.results[k])) end
    local castKeys = {}
    for k in pairs(DB.casts) do castKeys[#castKeys + 1] = k end
    table.sort(castKeys)
    if #castKeys == 0 then
        Say("  casts: none seen" .. (castFrame and " yet" or " (not watching: /fp mp cast on)"))
    end
    for _, k in ipairs(castKeys) do Say("  cast " .. k .. " x" .. DB.casts[k]) end
    for _, b in ipairs(DB.blocked) do Say("  " .. b) end
end

------------------------------------------------------------
-- Commands: /fp mp <command> [args]
------------------------------------------------------------

Probe:Command("spells", function() ProbeSpells() end, "do the Mage / Druid / Priest spell IDs resolve?")
Probe:Command("cast", function(args) WatchCasts((args or ""):lower() ~= "off") end,
    "on|off - watch UNIT_SPELLCAST_SUCCEEDED for group units")
Probe:Command("pane", function(args)
    local sub = (args or ""):lower()
    if sub == "build" then PaneBuild()
    elseif sub == "test" then PaneTest()
    elseif sub == "remove" then PaneRemove()
    else Say("usage: /fp mp pane build | test | remove") end
end, "build|test|remove - a plain pane under a protected frame, tested in combat")
-- The rest of the line, not one token: whisper targets have surnames.
Probe:Command("whisper", function(args) Whisper(args) end, "<First Surname> - whisper through C_ChatInfo")
Probe:Command("inspect", function() Inspect() end, "your own talents, then inspect your target's")
Probe:Command("report", function() Report() end, "everything recorded this session")
Probe:Command("reset", function()
    if not DB then Say("not loaded yet") return end
    NewSession()
    Say("this session's results forgotten (the log stays: /fp mp clear)")
end, "forget this session's results")
Probe:Command("clear", function() Probe:ClearLog(); Say("log cleared") end, "empty the saved log")

------------------------------------------------------------
-- Procedures: /fp steps mp <name>
------------------------------------------------------------

-- Do other players' casts arrive? One ~8-second run on 70009 saw nothing for
-- any unit, but whether the second account was in the party was not
-- confirmed. This is the controlled repeat: the party is confirmed first,
-- your own cast is the control, and a timeout is the "no" answer.
Probe:Steps("casts", {
    title = "Do other players' casts arrive?",
    { text = "Get a second player (your other account will do) into your party, both in the same zone.",
      wait = function()
          local n = G("GetNumGroupMembers")
          local members = n and n() or 0
          return members > 1, "party members: " .. tostring(members)
      end, timeout = 300 },
    { text = "Is the other player online and close to you?", ask = true },
    { text = "Watching casts now.", auto = true, run = function()
          WatchCasts(true)
          return DB.results["UNIT_SPELLCAST_SUCCEEDED registers"]
      end,
      check = function() return DB.results["UNIT_SPELLCAST_SUCCEEDED registers"] == "true", "registered" end },
    { text = "The control: cast any spell yourself, out of combat.",
      wait = function() return CastsBy("player") > 0, "your casts seen: " .. CastsBy("player") end,
      timeout = 120 },
    { text = "Now the other player casts any spell, out of combat (a buff on themselves is fine). "
          .. "Waits up to 2 minutes: running out means their casts don't arrive.",
      wait = function() return CastsBy("party") > 0, "party casts seen: " .. CastsBy("party") end,
      timeout = 120, screenshot = "party cast" },
    { text = "In a fight (pull a mob together), the other player casts again. Skip if you can't.",
      wait = function() return CastsBy("party", "combat") > 0,
          "party casts in combat: " .. CastsBy("party", "combat") end,
      timeout = 180 },
    { text = "The counts.", auto = true, run = function()
          Report()
          WatchCasts(false)
          return CastsBy("player"), CastsBy("party"), CastsBy("party", "combat")
      end,
      check = function() return CastsBy("party") > 0, "party casts: " .. CastsBy("party") end },
    { text = "Type /reload to save the results (or press Reload now).", reload = true },
})

-- Do talents live in Retail's traits system? GetTalentInfo answered nothing
-- in any shape on 70009, for yourself or an inspected target.
Probe:Steps("talents", {
    title = "Where do talents live?",
    { text = "Your own talents and talent config.", auto = true, run = function()
          OwnTalents()
          return DB.results["C_ClassTalents.GetActiveConfigID"]
      end },
    { text = "Target another player who has spent talent points, and stand close to them.",
      wait = function()
          local UE, UIP = G("UnitExists"), G("UnitIsPlayer")
          local ok, ready = pcall(function()
              return UE and UE("target") and UIP and UIP("target") and true or false
          end)
          return ok and ready, "no player targeted"
      end, timeout = 300 },
    { text = "Inspect them.", button = "Inspect", run = function()
          return SendInspect()
      end,
      check = function() return DB.results["NotifyInspect(target)"] ~= nil
          and DB.results["NotifyInspect(target)"]:find("^sent") ~= nil, DB.results["NotifyInspect(target)"] end },
    { text = "Waiting for the inspection to arrive (INSPECT_READY).", event = "INSPECT_READY", shapeOnly = true },
    { text = "What came back.", auto = true, run = function()
          return DB.results["INSPECT_READY"], DB.results["inspected talents by specializationIndex/tier/column"],
              DB.results["inspected spec by ID"]
      end,
      check = function() return DB.results["INSPECT_READY"] == "for the requested target", DB.results["INSPECT_READY"] end },
    { text = "Type /reload to save the results (or press Reload now).", reload = true },
})

-- A plain pane under the protected window, in combat. Measured on 70009 (it
-- stays free); this repeats it on a new build.
Probe:Steps("pane", {
    title = "A plain pane under a protected frame, in combat",
    { text = "Out of combat: build the stand-in (blue) and the pane (red).", button = "Build", run = function()
          PaneBuild()
          return P.pane ~= nil, DB.results["blocked-action watcher registered"]
      end,
      check = function() return P.pane ~= nil, "built" end, screenshot = "built" },
    { text = "Start a fight (a training dummy or any mob). The step completes when combat starts.",
      event = "PLAYER_REGEN_DISABLED" },
    { text = "Try to resize, move, hide and show the pane, and hide the stand-in.", auto = true, run = function()
          PaneTest()
          return DB.results["pane Hide"], DB.results["pane Hide the PROTECTED stand-in (control)"]
      end,
      check = function()
          local hide = DB.results["pane Hide"] or ""
          local control = DB.results["pane Hide the PROTECTED stand-in (control)"] or ""
          return hide:find("took effect=true", 1, true) ~= nil and control:find("took effect=false", 1, true) ~= nil,
              hide, control
      end, screenshot = "in combat" },
    { text = "Finish the fight. The step completes when combat ends.", event = "PLAYER_REGEN_ENABLED" },
    { text = "Take the frames away.", auto = true, run = function()
          PaneRemove()
          return P.pane == nil
      end },
    { text = "Type /reload to save the results (or press Reload now).", reload = true },
})

------------------------------------------------------------
-- Load
------------------------------------------------------------

local boot = G("CreateFrame")("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(MagelyProbeDB) ~= "table" then MagelyProbeDB = {} end
    DB = MagelyProbeDB
    if type(DB.log) ~= "table" then DB.log = {} end
    Probe:UseLog(DB.log, MAX_LOG)
    DB.loads = (tonumber(DB.loads) or 0) + 1
    NewSession()
    Say("loaded (" .. DB.loads .. " loads), build " .. tostring(DB.build) .. ". /fp mp for the commands, "
        .. "/fp steps for the procedures")
end)

NS._test = { Probe = Probe, P = P }
