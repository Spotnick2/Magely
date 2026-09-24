-- ============================================================================
-- MagelyProbe  -  throwaway API probe for Magely's cooldown pane on WoW:
-- Forever 1.60.1.
--
-- The TBC Magely had a second pane: Innervate and Power Infusion providers,
-- their cooldowns, and a click to whisper a request. Every data source it used
-- is gone or forbidden here, so before the pane comes back (slice 5,
-- Spotnick2/LibGroupBuffs#24) this measures what it could stand on instead.
-- Most of it needs no Mage and no level 40: any character in a group can run
-- it.
--
--   /mprobe spells              do the Mage / Druid / Priest spell IDs resolve?
--   /mprobe cast on|off         watch UNIT_SPELLCAST_SUCCEEDED for group units
--   /mprobe pane build          (out of combat) a protected frame + a plain pane
--   /mprobe pane test           (IN combat) try to hide/resize/move the pane
--   /mprobe pane remove         (out of combat) take them away again
--   /mprobe whisper <name>      whisper a (surnamed) name through C_ChatInfo
--   /mprobe inspect             inspect your target and read its talents
--   /mprobe report              everything recorded so far
--   /mprobe reset               forget it
--
-- Results are printed and kept in MagelyProbeDB. SavedVariables never load
-- back on this client, but they ARE written: after /reload (or logout) the
-- file is at _classic_beta_\WTF\Account\<id>\SavedVariables\MagelyProbe.lua.
-- Copy the answers into docs/FOREVER-NOTES.md.
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

local C = "|cffff8800[MagelyProbe]|r "

local function G(name) return rawget(_G, name) end

local function Say(text)
    local chat = G("DEFAULT_CHAT_FRAME")
    if chat then chat:AddMessage(C .. text) end
end

-- Fresh every session on purpose: nothing loads back on this build anyway.
MagelyProbeDB = { build = nil, results = {}, casts = {}, samples = {}, blocked = {} }
local DB = MagelyProbeDB

local function Record(key, value)
    DB.results[key] = value
    Say(key .. ": |cffffffff" .. tostring(value) .. "|r")
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

function MagelyProbe_OnCast(unit, castGUID, spellID)
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
        local CF = G("CreateFrame")
        castFrame = CF("Frame")
        local ok, registered = pcall(castFrame.RegisterEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED")
        Record("UNIT_SPELLCAST_SUCCEEDED registers",
            ok and tostring(registered ~= false) or ("threw: " .. tostring(registered)))
        castFrame:SetScript("OnEvent", function(_, _, ...) MagelyProbe_OnCast(...) end)
        Say("watching casts. Have party members cast anything, in and out of combat, then "
            .. "/mprobe report.")
    else
        if castFrame then castFrame:UnregisterAllEvents() castFrame = nil end
        Say("stopped watching casts")
    end
end

------------------------------------------------------------
-- A plain pane anchored to a protected frame, in combat
--
-- Magely's window parents secure buttons, so the client refuses to hide or
-- move it in combat (Priestly probe section 13). The pane would be a plain
-- frame anchored under it. The assumption is that the pane stays free - the
-- dependency runs from the pane to the window, not back - but that is exactly
-- what nobody has measured.
------------------------------------------------------------

local paneParent, pane

local function OnBlocked(event, who, fn)
    local ok, text = pcall(function() return tostring(who) .. " " .. tostring(fn) end)
    DB.blocked[#DB.blocked + 1] = event .. ": " .. (ok and text or "unreadable")
end

local blockFrame

local function PaneBuild()
    if InCombat() then Say("build it out of combat") return end
    if paneParent then Say("already built") return end
    local CF, UIP = G("CreateFrame"), G("UIParent")
    paneParent = CF("Frame", nil, UIP)
    paneParent:SetSize(120, 60)
    paneParent:SetPoint("CENTER", UIP, "CENTER", 0, 150)
    local secure = CF("Button", nil, paneParent, "SecureActionButtonTemplate")
    secure:SetAllPoints(paneParent)
    local bg = paneParent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.4, 0.8)
    -- Explicitly shown: the control below reads "did Hide take effect" from
    -- IsShown, which would be true of a frame that was never shown at all.
    paneParent:Show()

    pane = CF("Frame", nil, UIP)
    pane:SetSize(120, 40)
    pane:SetPoint("TOPLEFT", paneParent, "BOTTOMLEFT", 0, -4)
    local pbg = pane:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.4, 0.1, 0.1, 0.8)
    pane:Show()

    if not blockFrame then
        blockFrame = CF("Frame")
        for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
            pcall(blockFrame.RegisterEvent, blockFrame, ev)
        end
        blockFrame:SetScript("OnEvent", function(_, ev, ...) OnBlocked(ev, ...) end)
    end
    Record("pane built; parent protected", tostring(paneParent.IsProtected and paneParent:IsProtected()))
    Say("blue = the protected stand-in, red = the plain pane under it. Start a fight, then "
        .. "/mprobe pane test.")
end

-- One attempted change: whether it threw, whether it took effect, and how
-- many ADDON_ACTION_BLOCKED/FORBIDDEN it raised.
local function Try(label, act, check)
    local before = #DB.blocked
    local ok, err = pcall(act)
    local okCheck, result = pcall(check)
    local took = okCheck and result and true or false
    Record("pane " .. label, string.format("%s, took effect=%s, blocked events=%d",
        ok and "no error" or ("threw: " .. tostring(err)), tostring(took), #DB.blocked - before))
end

local function PaneTest()
    if not pane then Say("run /mprobe pane build first, out of combat") return end
    Record("pane test in combat", tostring(InCombat()))
    -- Read defensively: a number the client does not hand back must not end
    -- the probe before the calls that matter have been tried.
    local okH, h = pcall(pane.GetHeight, pane)
    h = okH and tonumber(h) or 40
    Try("SetHeight", function() pane:SetHeight(h + 20) end,
        function() return math.abs(pane:GetHeight() - (h + 20)) < 0.5 end)
    Try("re-anchor", function()
        pane:ClearAllPoints()
        pane:SetPoint("BOTTOMLEFT", paneParent, "TOPLEFT", 0, 4)
    end, function()
        local point = pane:GetPoint()
        return point == "BOTTOMLEFT"
    end)
    Try("Hide", function() pane:Hide() end, function() return not pane:IsShown() end)
    Try("Show", function() pane:Show() end, function() return pane:IsShown() end)
    -- The control: this one SHOULD be refused in combat.
    Try("Hide the PROTECTED stand-in (control)", function() paneParent:Hide() end,
        function() return not paneParent:IsShown() end)
end

local function PaneRemove()
    if InCombat() then Say("remove it out of combat") return end
    if pane then pane:Hide() pane = nil end
    if paneParent then paneParent:Hide() paneParent = nil end
    Say("pane removed")
end

------------------------------------------------------------
-- A whisper to a surnamed name
--
-- Addon messages to "First Surname" are measured to route (PORTING doc,
-- surnames). A chat WHISPER through C_ChatInfo is not. Whether it arrived can
-- only be seen by the recipient, so this records only whether the call was
-- accepted.
------------------------------------------------------------

local function Whisper(target)
    if not target or target == "" then Say("usage: /mprobe whisper First Surname") return end
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
------------------------------------------------------------

local inspectFrame

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
    }
    for _, shape in ipairs(shapes) do
        local hits, errors, firstErr, examples = 0, 0, nil, {}
        for a = 1, shape.outer do
            for b = 1, shape.inner do
                local ok, res = pcall(CSI.GetTalentInfo, shape.make(a, b))
                if not ok then
                    errors = errors + 1
                    firstErr = firstErr or tostring(res)
                elseif res then
                    hits = hits + 1
                    if #examples < 4 then
                        local okName, text = pcall(function()
                            return string.format("%d,%d=%s r%s/%s", a, b, tostring(res.name),
                                tostring(res.rank), tostring(res.maxRank))
                        end)
                        examples[#examples + 1] = okName and text or "unreadable"
                    end
                end
            end
        end
        Record(who .. " talents by " .. shape.label, string.format("%d hits, %d errors%s%s",
            hits, errors, firstErr and (" (first: " .. firstErr .. ")") or "",
            #examples > 0 and (" e.g. " .. table.concat(examples, "; ")) or ""))
    end
end

function MagelyProbe_OnInspectReady(guid)
    local UG = G("UnitGUID")
    local ok, same = pcall(function() return UG and UG("target") == guid end)
    Record("INSPECT_READY for the target", ok and tostring(same) or "unreadable")
    QueryTalents(true, "target")
    local CSI = G("C_SpecializationInfo")
    if CSI and CSI.GetInspectSpecialization then
        local okS, spec = pcall(CSI.GetInspectSpecialization, "target")
        Record("GetInspectSpecialization(target)", okS and tostring(spec) or ("threw: " .. tostring(spec)))
    end
    local clear = G("ClearInspectPlayer")
    if clear then pcall(clear) end
end

local function Inspect()
    local UE, CanI, Notify = G("UnitExists"), G("CanInspect"), G("NotifyInspect")
    -- Your own talents first, as the control: if these read nothing, neither
    -- shape addresses a Vanilla tree at all.
    QueryTalents(false, nil)
    if not (UE and UE("target")) then Say("target someone with talents and run it again") return end
    if not (CanI and Notify) then
        Record("inspect", string.format("CanInspect %s, NotifyInspect %s",
            CanI and "present" or "MISSING", Notify and "present" or "MISSING"))
        return
    end
    local okC, can = pcall(CanI, "target", false)
    Record("CanInspect(target)", okC and tostring(can) or ("threw: " .. tostring(can)))
    if not inspectFrame then
        inspectFrame = G("CreateFrame")("Frame")
        local ok, registered = pcall(inspectFrame.RegisterEvent, inspectFrame, "INSPECT_READY")
        Record("INSPECT_READY registers", ok and tostring(registered ~= false) or ("threw: " .. tostring(registered)))
        inspectFrame:SetScript("OnEvent", function(_, _, guid) MagelyProbe_OnInspectReady(guid) end)
    end
    local okN, err = pcall(Notify, "target")
    Record("NotifyInspect(target)", okN and "sent - waiting for INSPECT_READY" or ("threw: " .. tostring(err)))
end

------------------------------------------------------------
-- Report
------------------------------------------------------------

local function Report()
    -- select, not `gb and gb()`: an and/or keeps only the first return, and
    -- the build is the second.
    local gb = G("GetBuildInfo")
    local build = gb and select(2, gb()) or nil
    DB.build = build
    Say("build " .. tostring(build) .. " - results:")
    local keys = {}
    for k in pairs(DB.results) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do Say("  " .. k .. ": " .. tostring(DB.results[k])) end
    local castKeys = {}
    for k in pairs(DB.casts) do castKeys[#castKeys + 1] = k end
    table.sort(castKeys)
    if #castKeys == 0 then
        Say("  casts: none seen" .. (castFrame and " yet" or " (not watching: /mprobe cast on)"))
    end
    for _, k in ipairs(castKeys) do Say("  cast " .. k .. " x" .. DB.casts[k]) end
    for _, b in ipairs(DB.blocked) do Say("  " .. b) end
end

------------------------------------------------------------
-- Slash command
------------------------------------------------------------

SLASH_MAGELYPROBE1 = "/mprobe"
SlashCmdList["MAGELYPROBE"] = function(msg)
    msg = msg or ""
    -- The rest of the line, not one token: whisper targets have surnames.
    local cmd, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "spells" then
        ProbeSpells()
    elseif cmd == "cast" then
        WatchCasts(rest:lower() ~= "off")
    elseif cmd == "pane" then
        local sub = rest:lower()
        if sub == "build" then PaneBuild()
        elseif sub == "test" then PaneTest()
        elseif sub == "remove" then PaneRemove()
        else Say("usage: /mprobe pane build | test | remove") end
    elseif cmd == "whisper" then
        Whisper(rest)
    elseif cmd == "inspect" then
        Inspect()
    elseif cmd == "report" then
        Report()
    elseif cmd == "reset" then
        MagelyProbeDB = { build = nil, results = {}, casts = {}, samples = {}, blocked = {} }
        DB = MagelyProbeDB
        Say("forgotten")
    else
        Say("/mprobe spells | cast on|off | pane build|test|remove | whisper <name> | "
            .. "inspect | report | reset")
    end
end
