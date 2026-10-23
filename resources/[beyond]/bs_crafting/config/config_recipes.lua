-- bs_crafting recipes. Every recipe is known from the start.
-- station: nil = by hand in the inventory, or workbench / campfire / chem_table / weapon_bench.
-- time: seconds at crafting level 0. tool: any one of these must be carried, it is not used up.
-- burn: cooked results left in the station storage turn into this after Crafting.Settings.burnAfter.
-- The F1 recipe editor saves changes on top of this file (data/recipes.json).

local function r(cat, station, item, amount, time, cost, extra)
    local t = { cat = cat, station = station, result = { item = item, amount = amount }, time = time, cost = cost }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local HAND, WB, FIRE, CHEM, GUN = nil, 'workbench', 'campfire', 'chem_table', 'weapon_bench'

Crafting.Recipes = {
    -- by hand
    bandage_rags     = r('medical', HAND, 'bandage', 1, 5, { { item = 'rags', amount = 2 } }),
    bandage_cloth    = r('medical', HAND, 'bandage', 2, 5, { { item = 'cloth', amount = 2 } }),
    splint           = r('medical', HAND, 'splint', 1, 8, { { item = 'wood_plank', amount = 1 }, { item = 'rags', amount = 2 } }),
    antiseptic       = r('medical', HAND, 'antiseptic', 1, 8, { { item = 'cloth', amount = 2 }, { item = 'water_bottle', amount = 1 } }),
    purify_water     = r('water', HAND, 'water_bottle', 1, 6, { { item = 'dirty_water', amount = 1 }, { item = 'purification_tablet', amount = 1 } }),
    rags_to_cloth    = r('materials', HAND, 'cloth', 1, 4, { { item = 'rags', amount = 3 } }),
    -- tanning hides into leather (knife needed)
    tan_deer_hide    = r('materials', HAND, 'leather', 3, 12, { { item = 'deer_hide', amount = 1 } }, { tool = { 'hunting_knife', 'machete' } }),
    tan_boar_hide    = r('materials', HAND, 'leather', 2, 12, { { item = 'boar_hide', amount = 1 } }, { tool = { 'hunting_knife', 'machete' } }),
    tan_coyote_pelt  = r('materials', HAND, 'leather', 2, 10, { { item = 'coyote_pelt', amount = 1 } }, { tool = { 'hunting_knife', 'machete' } }),
    tan_rabbit_pelt  = r('materials', HAND, 'leather', 1, 6, { { item = 'rabbit_pelt', amount = 2 } }, { tool = { 'hunting_knife', 'machete' } }),
    tan_mtlion_pelt  = r('materials', HAND, 'leather', 4, 15, { { item = 'mtlion_pelt', amount = 1 } }, { tool = { 'hunting_knife', 'machete' } }),
    electrical_wire  = r('materials', HAND, 'electrical_wire', 1, 5, { { item = 'copper', amount = 3 } }),
    wires            = r('materials', HAND, 'wires', 2, 4, { { item = 'electrical_wire', amount = 1 } }),
    fertilizer       = r('materials', HAND, 'fertilizer', 1, 6, { { item = 'rotten_flesh', amount = 2 }, { item = 'bone', amount = 1 } }),
    planks_by_hand   = r('materials', HAND, 'wood_plank', 1, 10, { { item = 'log', amount = 1 } }, { tool = { 'hatchet', 'axe' } }),
    -- faction jobs gear (bs_jobs)
    fishing_rod      = r('tools', HAND, 'fishing_rod', 1, 15, { { item = 'wood_plank', amount = 1 }, { item = 'wires', amount = 2 }, { item = 'nails', amount = 1 } }),
    fish_bait        = r('food', HAND, 'fish_bait', 3, 4, { { item = 'rotten_flesh', amount = 1 } }),
    zip_ties         = r('tools', HAND, 'zip_ties', 2, 6, { { item = 'plastic', amount = 2 } }),
    head_sack        = r('tools', HAND, 'head_sack', 1, 6, { { item = 'cloth', amount = 2 } }),
    siphon_hose      = r('tools', HAND, 'siphon_hose', 1, 10, { { item = 'rubber', amount = 2 }, { item = 'metal_pipe', amount = 1 } }),
    molotov          = r('weapons', HAND, 'molotov', 1, 6, { { item = 'water_bottle', amount = 1 }, { item = 'rags', amount = 2 } }),
    zombie_bait      = r('traps', HAND, 'zombie_bait', 1, 6, { { item = 'rotten_flesh', amount = 3 }, { item = 'rags', amount = 1 } }),
    tripwire_alarm   = r('traps', HAND, 'tripwire_alarm', 1, 10, { { item = 'wires', amount = 3 }, { item = 'junk_cans', amount = 2 } }),
    -- backpacks and vests (bs_inventory gear): small by hand, the rest at a workbench
    pack_small       = r('misc', HAND, 'pack_small', 1, 20, { { item = 'cloth', amount = 6 }, { item = 'rags', amount = 2 } }),
    booster_decoy    = r('misc', HAND, 'booster_decoy', 1, 8, { { item = 'scrap_metal', amount = 2 }, { item = 'electrical_wire', amount = 1 } }),

    -- workbench
    pack_medium      = r('misc', WB, 'pack_medium', 1, 40, { { item = 'cloth', amount = 8 }, { item = 'leather', amount = 4 } }),
    pack_large       = r('misc', WB, 'pack_large', 1, 60, { { item = 'leather', amount = 8 }, { item = 'cloth', amount = 6 }, { item = 'duct_tape', amount = 2 } }),
    vest_tactical    = r('misc', WB, 'vest_tactical', 1, 45, { { item = 'cloth', amount = 6 }, { item = 'leather', amount = 3 }, { item = 'duct_tape', amount = 1 } }),
    planks           = r('materials', WB, 'wood_plank', 3, 8, { { item = 'log', amount = 1 } }),
    nails            = r('materials', WB, 'nails', 10, 8, { { item = 'scrap_metal', amount = 1 } }),
    screws           = r('materials', WB, 'screws', 10, 8, { { item = 'scrap_metal', amount = 1 } }),
    metal_pipe       = r('materials', WB, 'metal_pipe', 1, 10, { { item = 'scrap_metal', amount = 2 } }),
    glue             = r('materials', CHEM, 'glue', 2, 15, { { item = 'bone', amount = 3 }, { item = 'water_bottle', amount = 1 } }),
    hammer           = r('tools', WB, 'hammer', 1, 15, { { item = 'scrap_metal', amount = 3 }, { item = 'wood_plank', amount = 1 } }),
    axe              = r('tools', WB, 'axe', 1, 25, { { item = 'scrap_metal', amount = 5 }, { item = 'wood_plank', amount = 2 }, { item = 'duct_tape', amount = 1 } }),
    pickaxe          = r('tools', WB, 'pickaxe', 1, 25, { { item = 'scrap_metal', amount = 5 }, { item = 'wood_plank', amount = 2 } }),
    shovel           = r('tools', WB, 'shovel', 1, 20, { { item = 'scrap_metal', amount = 4 }, { item = 'wood_plank', amount = 1 } }),
    sledgehammer     = r('tools', WB, 'sledgehammer', 1, 40, { { item = 'scrap_metal', amount = 12 }, { item = 'metal_pipe', amount = 1 }, { item = 'duct_tape', amount = 2 } }),
    angle_grinder    = r('tools', WB, 'angle_grinder', 1, 60, { { item = 'electronics', amount = 4 }, { item = 'scrap_metal', amount = 8 }, { item = 'wires', amount = 4 }, { item = 'battery', amount = 1 } }),
    screwdriver      = r('tools', WB, 'screwdriver', 1, 12, { { item = 'scrap_metal', amount = 1 }, { item = 'plastic', amount = 2 } }),
    wrench           = r('tools', WB, 'wrench', 1, 15, { { item = 'scrap_metal', amount = 4 } }),
    hunting_knife    = r('tools', WB, 'hunting_knife', 1, 15, { { item = 'scrap_metal', amount = 3 }, { item = 'leather', amount = 1 } }),
    lockpick         = r('tools', WB, 'lockpick', 2, 15, { { item = 'scrap_metal', amount = 1 }, { item = 'screws', amount = 2 } }),
    toolbox          = r('tools', WB, 'toolbox', 1, 30, { { item = 'scrap_metal', amount = 8 }, { item = 'screws', amount = 6 } }),
    -- Outpost flag (cheap) and safezone flag (main base, expensive).
    faction_flag     = r('building', WB, 'faction_flag', 1, 60, { { item = 'wood_plank', amount = 8 }, { item = 'cloth', amount = 6 }, { item = 'scrap_metal', amount = 4 } }),
    safezone_flag    = r('building', WB, 'safezone_flag', 1, 180, { { item = 'log', amount = 10 }, { item = 'wood_plank', amount = 20 }, { item = 'cloth', amount = 15 }, { item = 'scrap_metal', amount = 20 }, { item = 'electronics', amount = 6 }, { item = 'wires', amount = 10 } }),
    spiked_bat       = r('weapons', WB, 'spiked_bat', 1, 20, { { item = 'wood_plank', amount = 2 }, { item = 'nails', amount = 15 } }),
    reinforced_bat   = r('weapons', WB, 'reinforced_bat', 1, 25, { { item = 'wood_plank', amount = 1 }, { item = 'scrap_metal', amount = 2 }, { item = 'duct_tape', amount = 1 } }),
    machete          = r('weapons', WB, 'machete', 1, 30, { { item = 'scrap_metal', amount = 5 }, { item = 'leather', amount = 1 } }),
    crowbar          = r('weapons', WB, 'crowbar', 1, 25, { { item = 'metal_pipe', amount = 1 }, { item = 'scrap_metal', amount = 2 } }),
    bear_trap        = r('traps', WB, 'bear_trap', 1, 30, { { item = 'scrap_metal', amount = 8 }, { item = 'nails', amount = 6 } }),
    jumper_cables    = r('misc', WB, 'jumper_cables', 1, 30, { { item = 'electrical_wire', amount = 3 }, { item = 'scrap_metal', amount = 2 }, { item = 'rubber', amount = 2 } }),
    battery          = r('misc', WB, 'battery', 1, 40, { { item = 'lead', amount = 8 }, { item = 'scrap_metal', amount = 4 }, { item = 'electrical_wire', amount = 2 } }),
    booster_drone    = r('misc', WB, 'booster_drone', 1, 45, { { item = 'battery', amount = 1 }, { item = 'electronics', amount = 3 }, { item = 'scrap_metal', amount = 3 } }),
    booster_medic    = r('misc', WB, 'booster_medic', 1, 40, { { item = 'bandage', amount = 4 }, { item = 'battery', amount = 1 }, { item = 'electronics', amount = 1 } }),
    booster_turret   = r('misc', WB, 'booster_turret', 1, 60, { { item = 'scrap_metal', amount = 8 }, { item = 'battery', amount = 2 }, { item = 'electronics', amount = 4 } }),

    -- campfire
    cook_meat        = r('food', FIRE, 'cooked_meat', 1, 20, { { item = 'raw_meat', amount = 1 } }, { burn = 'burnt_meat' }),
    cook_fish        = r('food', FIRE, 'cooked_fish', 1, 18, { { item = 'raw_fish', amount = 1 } }, { burn = 'burnt_meat' }),
    cook_big_fish    = r('food', FIRE, 'cooked_fish', 3, 30, { { item = 'big_fish', amount = 1 } }, { burn = 'burnt_meat' }),
    meat_stew        = r('food', FIRE, 'meat_stew', 1, 45, { { item = 'cooked_meat', amount = 2 }, { item = 'potato', amount = 1 }, { item = 'water_bottle', amount = 1 } }),
    veggie_stew      = r('food', FIRE, 'veggie_stew', 1, 40, { { item = 'potato', amount = 2 }, { item = 'herbs', amount = 1 }, { item = 'water_bottle', amount = 1 } }),
    boil_water       = r('water', FIRE, 'water_bottle', 1, 30, { { item = 'dirty_water', amount = 1 } }),
    charcoal         = r('materials', FIRE, 'charcoal', 3, 25, { { item = 'log', amount = 1 } }),
    lead             = r('materials', FIRE, 'lead', 4, 30, { { item = 'junk_battery', amount = 1 } }),

    -- chemistry table
    antibiotics      = r('medical', CHEM, 'antibiotics', 1, 60, { { item = 'herbs', amount = 3 }, { item = 'antiseptic', amount = 1 }, { item = 'water_bottle', amount = 1 } }),
    painkillers      = r('medical', CHEM, 'painkillers', 2, 45, { { item = 'herbs', amount = 2 }, { item = 'antiseptic', amount = 1 } }),
    antiviral        = r('medical', CHEM, 'antiviral', 1, 120, { { item = 'infected_blood', amount = 1 }, { item = 'antibiotics', amount = 1 }, { item = 'herbs', amount = 2 } }),
    purification_tablet = r('water', CHEM, 'purification_tablet', 4, 30, { { item = 'charcoal', amount = 2 }, { item = 'sulfur', amount = 1 } }),
    gunpowder        = r('materials', CHEM, 'gunpowder', 5, 30, { { item = 'charcoal', amount = 2 }, { item = 'sulfur', amount = 1 } }),
    pipe_bomb        = r('explosives', CHEM, 'pipe_bomb', 1, 90, { { item = 'metal_pipe', amount = 1 }, { item = 'gunpowder', amount = 15 }, { item = 'duct_tape', amount = 2 }, { item = 'rags', amount = 1 } }, { explosive = true }),
    c4               = r('explosives', CHEM, 'c4', 1, 180, { { item = 'gunpowder', amount = 40 }, { item = 'electronics', amount = 4 }, { item = 'duct_tape', amount = 3 }, { item = 'plastic', amount = 6 }, { item = 'wires', amount = 4 } }, { explosive = true }),
    booster_adrenaline = r('medical', CHEM, 'booster_adrenaline', 1, 30, { { item = 'antiseptic', amount = 1 }, { item = 'herbs', amount = 2 } }),
    booster_focus    = r('medical', CHEM, 'booster_focus', 1, 30, { { item = 'antiseptic', amount = 1 }, { item = 'berries', amount = 4 } }),
    booster_fortify  = r('medical', CHEM, 'booster_fortify', 1, 40, { { item = 'antibiotics', amount = 1 }, { item = 'cloth', amount = 2 } }),
    cocaine_good     = r('misc', CHEM, 'cocaine_good', 1, 45, { { item = 'cocaine_bad', amount = 2 }, { item = 'antiseptic', amount = 1 } }, { factionBase = true }),
    morphine_good    = r('misc', CHEM, 'morphine_good', 1, 45, { { item = 'morphine_bad', amount = 2 }, { item = 'antiseptic', amount = 1 } }, { factionBase = true }),
    amphetamine_good = r('misc', CHEM, 'amphetamine_good', 1, 45, { { item = 'amphetamine_bad', amount = 2 }, { item = 'antiseptic', amount = 1 } }, { factionBase = true }),
    weed_good        = r('misc', CHEM, 'weed_good', 1, 45, { { item = 'weed_bad', amount = 3 }, { item = 'cloth', amount = 1 } }, { factionBase = true }),

    -- weapon bench
    ammo_pistol      = r('ammo', GUN, 'ammo_pistol', 12, 20, { { item = 'ammo_casing', amount = 12 }, { item = 'gunpowder', amount = 2 }, { item = 'lead', amount = 2 } }),
    ammo_magnum      = r('ammo', GUN, 'ammo_magnum', 6, 20, { { item = 'ammo_casing', amount = 6 }, { item = 'gunpowder', amount = 2 }, { item = 'lead', amount = 2 } }),
    ammo_shotgun     = r('ammo', GUN, 'ammo_shotgun', 8, 20, { { item = 'ammo_casing', amount = 8 }, { item = 'gunpowder', amount = 3 }, { item = 'lead', amount = 3 } }),
    ammo_rifle       = r('ammo', GUN, 'ammo_rifle', 15, 25, { { item = 'ammo_casing', amount = 15 }, { item = 'gunpowder', amount = 4 }, { item = 'lead', amount = 3 } }),
    pipe_pistol      = r('weapons', GUN, 'pipe_pistol', 1, 60, { { item = 'metal_pipe', amount = 2 }, { item = 'gun_parts', amount = 1 }, { item = 'wood_plank', amount = 1 }, { item = 'duct_tape', amount = 1 }, { item = 'screws', amount = 4 } }),
    pipe_shotgun     = r('weapons', GUN, 'pipe_shotgun', 1, 90, { { item = 'metal_pipe', amount = 3 }, { item = 'gun_parts', amount = 2 }, { item = 'wood_plank', amount = 2 }, { item = 'duct_tape', amount = 2 }, { item = 'screws', amount = 6 } }),
    att_suppressor   = r('attachments', GUN, 'att_suppressor', 1, 45, { { item = 'metal_pipe', amount = 1 }, { item = 'rags', amount = 3 }, { item = 'screws', amount = 2 } }),
    att_grip         = r('attachments', GUN, 'att_grip', 1, 25, { { item = 'scrap_metal', amount = 2 }, { item = 'rubber', amount = 1 } }),
    att_flashlight   = r('attachments', GUN, 'att_flashlight', 1, 30, { { item = 'scrap_metal', amount = 2 }, { item = 'electronics', amount = 1 }, { item = 'wires', amount = 1 } }),
    att_laser        = r('attachments', GUN, 'att_laser', 1, 35, { { item = 'scrap_metal', amount = 2 }, { item = 'electronics', amount = 2 }, { item = 'battery', amount = 1 } }),
    att_extmag       = r('attachments', GUN, 'att_extmag', 1, 35, { { item = 'scrap_metal', amount = 3 }, { item = 'screws', amount = 2 } }),
}
