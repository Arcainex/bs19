-- bs_inventory - items added by crafting, recycling and gathering (bs_crafting, bs_recycler).
-- Merged into Items.Definitions after config_items.lua. An id that already exists is left alone, so other files win.

local add = {
    -- materials
    nails          = { label = 'Nails',            category = 'material', weight = 0.01, w = 1, h = 1, stack = 200, usable = false, value = 2 },
    screws         = { label = 'Screws',           category = 'material', weight = 0.01, w = 1, h = 1, stack = 200, usable = false, value = 2 },
    electronics    = { label = 'Electronics',      category = 'material', weight = 0.2,  w = 1, h = 1, stack = 20, usable = false, value = 18 },
    wires          = { label = 'Wires',            category = 'material', weight = 0.05,  w = 1, h = 1, stack = 60, usable = false, value = 6 },
    plastic        = { label = 'Plastic',          category = 'material', weight = 0.05,  w = 1, h = 1, stack = 50, usable = false, value = 3 },
    rubber         = { label = 'Rubber',           category = 'material', weight = 0.1,  w = 1, h = 1, stack = 50, usable = false, value = 4 },
    glue           = { label = 'Glue',             category = 'material', weight = 0.1,  w = 1, h = 1, stack = 20, usable = false, value = 8 },
    duct_tape      = { label = 'Duct tape',        category = 'material', weight = 0.1,  w = 1, h = 1, stack = 20, usable = false, value = 10 },
    leather        = { label = 'Leather',          category = 'material', weight = 0.3,  w = 1, h = 1, stack = 20, usable = false, value = 9 },
    -- hunting hides (skinned animals), sold at traders or tanned into leather
    deer_hide      = { label = 'Deer hide',        category = 'material', weight = 0.8,  w = 1, h = 1, stack = 10, usable = false, value = 30 },
    boar_hide      = { label = 'Boar hide',        category = 'material', weight = 0.9,  w = 1, h = 1, stack = 10, usable = false, value = 26 },
    rabbit_pelt    = { label = 'Rabbit pelt',      category = 'material', weight = 0.2,  w = 1, h = 1, stack = 20, usable = false, value = 12 },
    coyote_pelt    = { label = 'Coyote pelt',      category = 'material', weight = 0.5,  w = 1, h = 1, stack = 10, usable = false, value = 22 },
    mtlion_pelt    = { label = 'Mountain lion pelt', category = 'material', weight = 1.0, w = 1, h = 1, stack = 5, usable = false, value = 70 },
    gunpowder      = { label = 'Gunpowder',        category = 'material', weight = 0.05, w = 1, h = 1, stack = 50, usable = false, value = 6 },
    gun_parts      = { label = 'Gun parts',        category = 'material', weight = 0.4,  w = 1, h = 1, stack = 20, usable = false, value = 40 },
    log            = { label = 'Log',              category = 'material', weight = 1.5,  w = 1, h = 2, stack = 20,  usable = false, value = 6 },
    stone          = { label = 'Stone',            category = 'material', weight = 0.5,  w = 1, h = 1, stack = 40, usable = false, value = 2 },
    iron_ore       = { label = 'Iron ore',         category = 'material', weight = 0.6,  w = 1, h = 1, stack = 40, usable = false, value = 7 },
    sulfur         = { label = 'Sulfur',           category = 'material', weight = 0.2,  w = 1, h = 1, stack = 40, usable = false, value = 8 },
    charcoal       = { label = 'Charcoal',         category = 'material', weight = 0.1,  w = 1, h = 1, stack = 50, usable = false, value = 3 },
    metal_pipe     = { label = 'Metal pipe',       category = 'material', weight = 0.5,  w = 1, h = 2, stack = 20, usable = false, value = 12 },
    lead           = { label = 'Lead',             category = 'material', weight = 0.2,  w = 1, h = 1, stack = 50, usable = false, value = 4 },
    ammo_casing    = { label = 'Empty casings',    category = 'material', weight = 0.01, w = 1, h = 1, stack = 100, usable = false, value = 1 },
    rags           = { label = 'Rags',             category = 'material', weight = 0.1,  w = 1, h = 1, stack = 20, usable = false, value = 1 },
    bone           = { label = 'Bone',             category = 'material', weight = 0.3,  w = 1, h = 1, stack = 20, usable = false, value = 2 },
    rotten_flesh   = { label = 'Rotten flesh',     category = 'material', weight = 0.3,  w = 1, h = 1, stack = 20, usable = false, value = 1 },
    fertilizer     = { label = 'Fertilizer',       category = 'material', weight = 0.5,  w = 1, h = 1, stack = 10, usable = false, value = 6 },
    infected_blood = { label = 'Infected blood sample', category = 'trophy', weight = 0.1, w = 1, h = 1, stack = 10, usable = false, value = 150 },

    -- tools
    axe            = { label = 'Axe',              category = 'weapon', weight = 2.4, w = 1, h = 3, stack = 1, usable = true, value = 160, data = { weapon = 'WEAPON_BATTLEAXE', tool = 'logging', durability = 150 } },
    sledgehammer   = { label = 'Sledgehammer',     category = 'tool',   weight = 5.0, w = 1, h = 3, stack = 1, usable = false, value = 260, data = { tool = 'raiding' } },
    angle_grinder  = { label = 'Angle grinder',    category = 'tool',   weight = 2.6, w = 2, h = 1, stack = 1, usable = false, value = 340, data = { tool = 'cutting' } },
    screwdriver    = { label = 'Screwdriver',      category = 'tool',   weight = 0.2, w = 1, h = 1, stack = 1, usable = false, value = 40,  data = { tool = 'screwdriver' } },
    wrench         = { label = 'Wrench',           category = 'tool',   weight = 0.9, w = 1, h = 2, stack = 1, usable = true, value = 70,   data = { weapon = 'WEAPON_WRENCH', tool = 'wrench' } },


    -- traps
    bear_trap      = { label = 'Bear trap',        category = 'gadget', weight = 2.0, w = 2, h = 1, stack = 3, usable = true, value = 120, data = { handled = true, useEvent = 'bs:crafting:useItem' } },
    tripwire_alarm = { label = 'Tripwire alarm',   category = 'gadget', weight = 0.4, w = 1, h = 1, stack = 5, usable = true, value = 60,  data = { handled = true, useEvent = 'bs:crafting:useItem' } },
    zombie_bait    = { label = 'Zombie bait',      category = 'gadget', weight = 0.5, w = 1, h = 1, stack = 5, usable = true, value = 30,  data = { handled = true, useEvent = 'bs:crafting:useItem' } },

    -- explosives (raid damage lives in the building side)
    c4             = { label = 'C4',               category = 'weapon', weight = 1.0, w = 1, h = 1, stack = 5, usable = true, value = 1200, data = { weapon = 'WEAPON_STICKYBOMB', ammo = 1, throwable = true } },
    pipe_bomb      = { label = 'Pipe bomb',        category = 'weapon', weight = 0.8, w = 1, h = 2, stack = 5, usable = true, value = 600,  data = { weapon = 'WEAPON_PIPEBOMB', ammo = 1 } },

    -- improvised guns
    pipe_pistol    = { label = 'Pipe pistol',      category = 'weapon', weight = 1.3, w = 2, h = 1, stack = 1, usable = true, value = 320, data = { weapon = 'WEAPON_SNSPISTOL', spawnRounds = 6 } },
    pipe_shotgun   = { label = 'Pipe shotgun',     category = 'weapon', weight = 3.2, w = 4, h = 2, stack = 1, usable = true, value = 520, data = { weapon = 'WEAPON_DBSHOTGUN', spawnRounds = 2 } },
    spiked_bat     = { label = 'Spiked bat',       category = 'weapon', weight = 2.0, w = 1, h = 3, stack = 1, usable = true, value = 120, data = { weapon = 'WEAPON_BAT' } },

    -- medical (effects owned by bs_medical)
    splint         = { label = 'Splint',           category = 'medical', weight = 0.4, w = 1, h = 2, stack = 3, usable = true, value = 45,  data = { handled = true } },
    antiviral      = { label = 'Antiviral',        category = 'medical', weight = 0.2, w = 1, h = 1, stack = 5, usable = true, value = 380, data = { cure = 80 } },

    -- food and water
    raw_meat       = { label = 'Raw meat',         category = 'food', weight = 0.4, w = 1, h = 1, stack = 10, usable = true, value = 8,  data = { hunger = 8, useEvent = 'bs:crafting:useItem' } },
    cooked_meat    = { label = 'Cooked meat',      category = 'food', weight = 0.3, w = 1, h = 1, stack = 10, usable = true, value = 20, data = { hunger = 35 } },
    burnt_meat     = { label = 'Burnt meat',       category = 'food', weight = 0.3, w = 1, h = 1, stack = 10, usable = true, value = 3,  data = { hunger = 10 } },
    meat_stew      = { label = 'Meat stew',        category = 'food', weight = 0.6, w = 1, h = 1, stack = 5,  usable = true, value = 60, data = { hunger = 70, thirst = 20, useEvent = 'bs:crafting:useItem' } },
    veggie_stew    = { label = 'Vegetable stew',   category = 'food', weight = 0.6, w = 1, h = 1, stack = 5,  usable = true, value = 45, data = { hunger = 50, thirst = 30, useEvent = 'bs:crafting:useItem' } },
    berries        = { label = 'Wild berries',     category = 'food', weight = 0.1, w = 1, h = 1, stack = 20, usable = true, value = 4,  data = { hunger = 6, thirst = 4 } },
    herbs          = { label = 'Wild herbs',       category = 'material', weight = 0.05, w = 1, h = 1, stack = 20, usable = false, value = 6 },
    potato         = { label = 'Potato',           category = 'food', weight = 0.2, w = 1, h = 1, stack = 20, usable = true, value = 5,  data = { hunger = 8 } },
    potato_seeds   = { label = 'Potato seeds',     category = 'material', weight = 0.05, w = 1, h = 1, stack = 20, usable = false, value = 6 },
    herb_seeds     = { label = 'Herb seeds',       category = 'material', weight = 0.05, w = 1, h = 1, stack = 20, usable = false, value = 8 },
    dirty_water    = { label = 'Dirty water',      category = 'drink', weight = 0.5, w = 1, h = 2, stack = 5, usable = true, value = 2, data = { thirst = 20, useEvent = 'bs:crafting:useItem' } },
    purification_tablet = { label = 'Purification tablet', category = 'medical', weight = 0.01, w = 1, h = 1, stack = 20, usable = false, value = 12 },

    -- junk: found in loot, only good for the recycler or the junk trader
    junk_radio       = { label = 'Broken radio',      category = 'junk', weight = 1.2, w = 2, h = 1, stack = 2,  usable = false, value = 30 },
    junk_battery     = { label = 'Dead car battery',  category = 'junk', weight = 7.0, w = 2, h = 2, stack = 1,  usable = false, value = 40 },
    junk_pipe        = { label = 'Rusty pipe',        category = 'junk', weight = 1.0, w = 1, h = 2, stack = 5,  usable = false, value = 12 },
    junk_tape        = { label = 'Used tape roll',    category = 'junk', weight = 0.1, w = 1, h = 1, stack = 10, usable = false, value = 6 },
    junk_phone       = { label = 'Broken phone',      category = 'junk', weight = 0.2, w = 1, h = 1, stack = 5,  usable = false, value = 25 },
    junk_laptop      = { label = 'Smashed laptop',    category = 'junk', weight = 2.0, w = 2, h = 1, stack = 1,  usable = false, value = 60 },
    junk_toaster     = { label = 'Toaster',           category = 'junk', weight = 1.5, w = 2, h = 1, stack = 2,  usable = false, value = 18 },
    junk_kettle      = { label = 'Kettle',            category = 'junk', weight = 0.9, w = 1, h = 2, stack = 2,  usable = false, value = 14 },
    junk_fan         = { label = 'Desk fan',          category = 'junk', weight = 1.6, w = 2, h = 2, stack = 1,  usable = false, value = 22 },
    junk_cables      = { label = 'Tangle of cables',  category = 'junk', weight = 0.6, w = 1, h = 1, stack = 5,  usable = false, value = 16 },
    junk_clock       = { label = 'Alarm clock',       category = 'junk', weight = 0.4, w = 1, h = 1, stack = 5,  usable = false, value = 12 },
    junk_camera      = { label = 'Broken camera',     category = 'junk', weight = 0.5, w = 1, h = 1, stack = 3,  usable = false, value = 28 },
    junk_hairdryer   = { label = 'Hair dryer',        category = 'junk', weight = 0.7, w = 1, h = 2, stack = 2,  usable = false, value = 16 },
    junk_remote      = { label = 'TV remote',         category = 'junk', weight = 0.1, w = 1, h = 1, stack = 10, usable = false, value = 8 },
    junk_lamp        = { label = 'Desk lamp',         category = 'junk', weight = 1.1, w = 1, h = 2, stack = 2,  usable = false, value = 14 },
    junk_cans        = { label = 'Empty tin cans',    category = 'junk', weight = 0.2, w = 1, h = 1, stack = 20, usable = false, value = 3 },
    junk_chain       = { label = 'Bike chain',        category = 'junk', weight = 0.5, w = 1, h = 1, stack = 5,  usable = false, value = 10 },
    junk_shoes       = { label = 'Old boots',         category = 'junk', weight = 0.9, w = 2, h = 1, stack = 2,  usable = false, value = 8 },
    junk_gears       = { label = 'Rusty gears',       category = 'junk', weight = 0.6, w = 1, h = 1, stack = 10, usable = false, value = 12 },
    junk_spraycan    = { label = 'Empty spray can',   category = 'junk', weight = 0.2, w = 1, h = 1, stack = 10, usable = false, value = 5 },
    junk_glue        = { label = 'Half a glue tube',  category = 'junk', weight = 0.05, w = 1, h = 1, stack = 10, usable = false, value = 6 },
}

for id, def in pairs(add) do
    if Items.Definitions[id] == nil then Items.Definitions[id] = def end
end
