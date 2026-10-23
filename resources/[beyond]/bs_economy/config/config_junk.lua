-- Junk and crafting materials added to the loot tables (recycler fodder, see bs_recycler).
-- Appended after config_economy.lua so the main tables stay readable.

local add = {
    trash      = { { 'junk_cans', 1, 3, 14 }, { 'junk_tape', 1, 1, 5 }, { 'junk_shoes', 1, 1, 4 }, { 'junk_spraycan', 1, 2, 5 }, { 'rags', 1, 3, 12 }, { 'plastic', 1, 2, 8 }, { 'dirty_water', 1, 1, 4 }, { 'junk_remote', 1, 1, 3 } },
    kitchen    = { { 'junk_toaster', 1, 1, 6 }, { 'junk_kettle', 1, 1, 6 }, { 'junk_cans', 1, 2, 8 }, { 'dirty_water', 1, 1, 8 }, { 'purification_tablet', 1, 2, 2 } },
    vending    = { { 'plastic', 1, 2, 6 }, { 'junk_cans', 1, 2, 6 } },
    workshop   = { { 'junk_pipe', 1, 2, 10 }, { 'junk_gears', 1, 2, 8 }, { 'junk_chain', 1, 1, 5 }, { 'nails', 4, 12, 10 }, { 'screws', 4, 10, 8 }, { 'duct_tape', 1, 1, 5 }, { 'glue', 1, 1, 4 }, { 'junk_battery', 1, 1, 3 }, { 'screwdriver', 1, 1, 3 }, { 'wrench', 1, 1, 3 }, { 'metal_pipe', 1, 1, 4 } },
    electrical = { { 'junk_cables', 1, 2, 14 }, { 'junk_radio', 1, 1, 6 }, { 'electronics', 1, 1, 6 }, { 'wires', 1, 3, 10 }, { 'junk_lamp', 1, 1, 4 } },
    barrel     = { { 'junk_pipe', 1, 1, 6 }, { 'rubber', 1, 2, 6 }, { 'dirty_water', 1, 1, 6 } },
    vehicle    = { { 'junk_phone', 1, 1, 6 }, { 'junk_camera', 1, 1, 3 }, { 'junk_laptop', 1, 1, 2 }, { 'rubber', 1, 1, 4 }, { 'junk_hairdryer', 1, 1, 2 }, { 'junk_clock', 1, 1, 3 } },
    urban      = { { 'junk_phone', 1, 1, 6 }, { 'junk_radio', 1, 1, 4 }, { 'junk_fan', 1, 1, 3 }, { 'junk_laptop', 1, 1, 2 }, { 'junk_glue', 1, 1, 4 }, { 'rags', 1, 2, 6 } },
    rural      = { { 'junk_pipe', 1, 1, 4 }, { 'junk_chain', 1, 1, 3 }, { 'potato_seeds', 1, 2, 3 }, { 'herb_seeds', 1, 1, 2 }, { 'ammo_casing', 3, 8, 3 } },
    military   = { { 'ammo_casing', 5, 15, 12 }, { 'gunpowder', 2, 6, 6 }, { 'gun_parts', 1, 1, 4 }, { 'electronics', 1, 2, 4 }, { 'duct_tape', 1, 1, 4 } },
    walker     = { { 'rags', 1, 2, 6 }, { 'junk_phone', 1, 1, 2 }, { 'ammo_casing', 1, 4, 2 } },
}

for id, entries in pairs(add) do
    local tbl = Economy.LootTables[id]
    if tbl then
        tbl.entries = tbl.entries or {}
        for _, e in ipairs(entries) do
            tbl.entries[#tbl.entries + 1] = { item = e[1], amount = { e[2], e[3] }, weight = e[4] }
        end
    end
end
