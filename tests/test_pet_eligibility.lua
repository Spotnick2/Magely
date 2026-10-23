-- Arcane Intellect must not ask for casts on Forever's ineligible stat-buff pets.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, raid in ipairs({ false, true }) do
    for _, track in ipairs({ false, true }) do
        WoW.reset()
        MagelyDB = nil
        Magely_EnsureDefaults()
        Magely_SetConfig("trackPets", track)
        Magely_SetConfig("amplifyMode", "always")
        Magely_SetConfig("dampenMode", "always")
        H.TeachSpells({ "INT_SINGLE", "INT_GROUP", "AMPLIFY", "DAMPEN" })
        T.RefreshSpellData()
        WoW.inRaid = raid
        WoW.groupMembers = 4
        WoW.SetUnit("player", { name = "Priest", guid = "P", class = "MAGE" })
        local excluded = {}
        for i, class in ipairs({ "HUNTER", "WARLOCK", "MAGE" }) do
            local unit = (raid and "raid" or "party") .. i
            local pet = (raid and "raidpet" or "partypet") .. i
            WoW.SetUnit(unit, { name = class, guid = unit, class = class })
            WoW.SetUnit(pet, { name = "Pet " .. i, guid = pet })
            if raid then WoW.raidRoster[i] = { name = class, subgroup = 1 } end
            if class ~= "MAGE" then excluded[pet] = true end
        end
        if raid then
            WoW.SetUnit("raid4", { name = "Priest", guid = "P", class = "MAGE" })
            WoW.raidRoster[4] = { name = "Priest", subgroup = 1 }
        end
        T.UpdateUI()
        local totals = { intellect = 0, amplify = 0, dampen = 0 }
        for _, row in ipairs(T.rows()) do
            if row._active then
                local id = row._def.id
                local stats = T.engine:GroupStat(row._members, row._def)
                totals[id] = totals[id] + stats.nTotal
                H.eq(stats.nMiss, #row._members, "missing count uses eligible members")
                if id == "intellect" then
                    for _, m in ipairs(row._members) do
                        H.check(not excluded[m.unit], "Arcane Intellect members exclude hunter/warlock pets")
                    end
                    H.check(not excluded[row:GetAttribute("unit1")], "primary target is eligible")
                    H.check(not excluded[row:GetAttribute("unit2")], "secondary target is eligible")
                    T.UpdatePopover(row, row._members, row._def)
                    for _, pr in ipairs(T.popRows()) do
                        if pr._active then
                            H.check(not excluded[pr:GetAttribute("unit1")], "popover target is eligible")
                        end
                    end
                end
            end
        end
        H.eq(totals.intellect, track and 5 or 4, "Arcane Intellect keeps players and unverified pet types")
        H.eq(totals.amplify, track and 7 or 4, "Amplify eligibility unchanged")
        H.eq(totals.dampen, track and 7 or 4, "Dampen eligibility unchanged")
    end
end

-- A single-target-only mage never draws a stat-buff row for an ineligible pet,
-- while eligible auxiliary buff rows follow pet summon/despawn normally.
for _, raid in ipairs({ false, true }) do
    WoW.reset()
    MagelyDB = nil
    Magely_EnsureDefaults()
    Magely_SetConfig("amplifyMode", "always")
    Magely_SetConfig("dampenMode", "always")
    H.TeachSpells({ "INT_SINGLE", "AMPLIFY", "DAMPEN" })
    T.RefreshSpellData()
    WoW.inRaid, WoW.groupMembers = raid, 2
    local owner, pet = raid and "raid2" or "party1", raid and "raidpet2" or "partypet1"
    WoW.SetUnit(owner, { name = "Hunter", class = "HUNTER" })
    if raid then
        WoW.SetUnit("raid1", { name = "Mage", guid = WoW.units.player.guid, class = "MAGE" })
        WoW.raidRoster = { { name = "Mage", subgroup = 1 }, { name = "Hunter", subgroup = 1 } }
    end
    for _, summoned in ipairs({ true, false, true }) do
        if summoned then WoW.SetUnit(pet, { name = "Pet" }) else WoW.RemoveUnit(pet) end
        T.UpdateUI()
        local seen = {}
        for _, row in ipairs(T.rows()) do
            if row._active then
                for _, member in ipairs(row._members) do
                    if member.unit == pet then seen[row._def.id] = true end
                end
            end
        end
        H.check(not seen.intellect, "no pet Intellect row even without Brilliance")
        H.eq(seen.amplify == true, summoned, "Amplify follows pet presence")
        H.eq(seen.dampen == true, summoned, "Dampen follows pet presence")
    end
end
H.done("test_pet_eligibility")
