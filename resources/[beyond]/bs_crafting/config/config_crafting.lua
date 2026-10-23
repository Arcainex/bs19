-- bs_crafting config. Settings marked (F1) are live in the F1 console (category Crafting & Recycling).

Crafting = {}

Crafting.Settings = {
    enabled          = true,   -- (F1)
    allowExplosives  = true,   -- (F1) off hides and blocks C4 / pipe bomb recipes
    materialRadius   = 10.0,   -- (F1) station storages this close also feed a craft
    stationRadius    = 3.0,    -- how close you must be to use a station
    handQueueMax     = 5,      -- (F1)
    stationQueueMax  = 8,      -- (F1)
    setupMs          = 2500,   -- station work you stand still for before the job runs on its own
    skill            = 'crafting',
    speedPerLevel    = 0.025,  -- (F1) craft time cut per crafting level
    maxSpeedCut      = 0.5,    -- (F1)
    xpPerSecond      = 0.4,    -- crafting XP per second of base craft time
    storageSize      = { w = 6, h = 4, maxWeight = 250.0 },
    burnAfter        = 180,    -- (F1) seconds cooked food can sit on the fire before it burns
    skinZombies      = true,   -- (F1)
    skinMs           = 6000,
    animalYieldMult  = 1.0,    -- (F1) multiplies everything rolled from a skinned animal
    huntSkill        = 'survival', -- skill tree whose level adds up to +30% animal yield
    skinRange        = 4.0,    -- server check: max metres between you and the carcass
    forageMs         = 3500,
    forageCooldown   = 900,    -- seconds a bush stays picked
    farmGrowMinutes  = 90,     -- (F1) real minutes from seed to harvest (watered + fertilized halves nothing, it is required)
    salvageMs        = 20000,  -- (F1) wrench time on a vehicle wreck
}

-- Stations. Placed through bs_building (RegisterPlaceable reads StationDefs). `id` is the building piece id.
-- anim: tried in order, the first dict that loads is used. prop: attached to the right hand while working.
Crafting.Stations = {
    workbench = {
        label = 'Workbench', models = { 'prop_tool_bench02', 'prop_tool_bench02_ld' }, health = 600, size = { 2.0, 1.0, 1.0 },
        cost = { { item = 'wood_plank', amount = 6 }, { item = 'scrap_metal', amount = 6 }, { item = 'nails', amount = 10 } },
        anim = { { dict = 'amb@world_human_hammering@male@base', clip = 'base' }, { dict = 'mini@repair', clip = 'fixing_a_player' } },
        prop = 'prop_tool_hammer',
    },
    campfire = {
        label = 'Campfire', models = { 'prop_beach_fire' }, health = 200, size = { 1.2, 1.2, 0.6 },
        cost = { { item = 'log', amount = 3 }, { item = 'stone', amount = 6 } },
        anim = { { dict = 'amb@prop_human_bbq@male@base', clip = 'base' }, { dict = 'amb@medic@standing@kneel@base', clip = 'base' } },
        prop = 'prop_fish_slice_01',
    },
    chem_table = {
        label = 'Chemistry table', models = { 'v_ret_ml_tablea', 'prop_table_03', 'prop_tool_bench02' }, health = 500, size = { 1.6, 0.9, 1.0 },
        cost = { { item = 'wood_plank', amount = 4 }, { item = 'scrap_metal', amount = 6 }, { item = 'glue', amount = 2 }, { item = 'electronics', amount = 2 } },
        anim = { { dict = 'anim@amb@business@meth@meth_monitoring_cooking@cooking@', clip = 'chemical_pour_short_cooker' }, { dict = 'mini@repair', clip = 'fixing_a_player' } },
        prop = 'prop_cs_beer_bot_01',
    },
    weapon_bench = {
        label = 'Weapon bench', models = { 'gr_prop_gr_bench_04a', 'gr_prop_gr_bench_02a', 'prop_tool_bench02' }, health = 700, size = { 2.0, 1.0, 1.0 },
        cost = { { item = 'wood_plank', amount = 4 }, { item = 'scrap_metal', amount = 10 }, { item = 'screws', amount = 12 }, { item = 'gun_parts', amount = 1 } },
        anim = { { dict = 'anim@amb@machinery@weapon_machinery@', clip = 'operate_02_hi_amy_skater_01' }, { dict = 'mini@repair', clip = 'fixing_a_player' } },
        prop = 'prop_tool_screwdvr01',
    },
    farm_plot = {
        label = 'Farm plot', models = { 'prop_veg_crop_03_cab', 'prop_haybale_03', 'prop_plant_flower_01' }, health = 150, size = { 1.5, 1.5, 0.3 },
        cost = { { item = 'wood_plank', amount = 3 }, { item = 'fertilizer', amount = 1 } },
        farm = true,
    },
}

-- Hand crafting (in the inventory) has no station. Its animation plays while the bar runs, you can walk.
Crafting.HandAnim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 }

-- Category order in the panel.
Crafting.Categories = { 'tools', 'building', 'weapons', 'ammo', 'attachments', 'medical', 'food', 'water', 'traps', 'explosives', 'materials', 'misc' }

-- Farming. One crop per plot. Stages are drawn as props.
Crafting.Crops = {
    potato_seeds = { label = 'Potatoes', yield = { { item = 'potato', amount = { 3, 6 } }, { item = 'potato_seeds', amount = { 1, 2 } } } },
    herb_seeds   = { label = 'Herbs',    yield = { { item = 'herbs',  amount = { 2, 4 } }, { item = 'herb_seeds',   amount = { 1, 2 } } } },
}
Crafting.CropProps = { 'prop_veg_crop_04_leaf', 'prop_veg_crop_03_pump', 'prop_veg_crop_02' }

-- Skinning. Animals need a knife; zombies need a knife too.
Crafting.SkinTool = { 'hunting_knife', 'machete', 'hatchet', 'axe' }
Crafting.Animals = {
    a_c_deer   = { { item = 'raw_meat', amount = { 3, 5 } }, { item = 'deer_hide', amount = { 1, 1 } }, { item = 'leather', amount = { 0, 1 } }, { item = 'bone', amount = { 1, 2 } } },
    a_c_boar   = { { item = 'raw_meat', amount = { 3, 4 } }, { item = 'boar_hide', amount = { 1, 1 } }, { item = 'leather', amount = { 0, 1 } }, { item = 'bone', amount = { 1, 2 } } },
    a_c_cow    = { { item = 'raw_meat', amount = { 5, 8 } }, { item = 'leather', amount = { 3, 4 } }, { item = 'bone', amount = { 2, 3 } } },
    a_c_pig    = { { item = 'raw_meat', amount = { 3, 5 } }, { item = 'leather', amount = { 1, 2 } }, { item = 'bone', amount = { 1, 2 } } },
    a_c_coyote = { { item = 'raw_meat', amount = { 1, 3 } }, { item = 'coyote_pelt', amount = { 1, 1 } }, { item = 'bone', amount = { 1, 1 } } },
    a_c_mtlion = { { item = 'raw_meat', amount = { 2, 4 } }, { item = 'mtlion_pelt', amount = { 1, 1 } }, { item = 'leather', amount = { 0, 1 } }, { item = 'bone', amount = { 1, 2 } } },
    a_c_rabbit_01 = { { item = 'raw_meat', amount = { 1, 1 } }, { item = 'rabbit_pelt', amount = { 1, 1 } } },
    a_c_hen    = { { item = 'raw_meat', amount = { 1, 1 } } },
}
-- Hunting reward per animal: scales bs_core Config.Rewards.animal_skinned (XP + survival skill XP).
Crafting.HuntReward = {
    a_c_deer = 1.0, a_c_boar = 1.3, a_c_coyote = 1.0, a_c_mtlion = 2.5, a_c_rabbit_01 = 0.4,
    a_c_cow = 0.5, a_c_pig = 0.5, a_c_hen = 0.2,
}
Crafting.ZombieSkin = {
    { item = 'rotten_flesh',   amount = { 1, 3 } },
    { item = 'bone',           amount = { 0, 2 } },
    { item = 'rags',           amount = { 1, 2 } },
    { item = 'infected_blood', amount = { 1, 1 }, chance = 0.04 },
}

-- Foraging bushes. Any of these models gets a Forage option.
Crafting.ForageModels = {
    'prop_bush_lrg_01', 'prop_bush_lrg_01b', 'prop_bush_lrg_01c', 'prop_bush_lrg_02', 'prop_bush_lrg_04b',
    'prop_bush_med_01', 'prop_bush_med_02', 'prop_bush_med_03', 'prop_bush_neat_01', 'prop_bush_ornament_01',
}
Crafting.Forage = {
    { item = 'berries',      amount = { 1, 4 }, chance = 0.8 },
    { item = 'herbs',        amount = { 1, 2 }, chance = 0.4 },
    { item = 'potato_seeds', amount = { 1, 1 }, chance = 0.08 },
    { item = 'herb_seeds',   amount = { 1, 1 }, chance = 0.08 },
}

-- Wreck salvage (wrench). Rolled once per wreck; the wreck is removed afterwards.
Crafting.Salvage = {
    { item = 'scrap_metal', amount = { 6, 12 } },
    { item = 'rubber',      amount = { 1, 3 } },
    { item = 'wires',       amount = { 1, 3 } },
    { item = 'screws',      amount = { 2, 6 } },
    { item = 'plastic',     amount = { 1, 3 } },
    { item = 'spark_plug',  amount = { 1, 1 }, chance = 0.15 },
    { item = 'tyre',        amount = { 1, 1 }, chance = 0.10 },
    { item = 'battery',     amount = { 1, 1 }, chance = 0.05 },
}

-- Traps.
Crafting.Traps = {
    bear_trap      = { model = { 'p_ld_stinger_s', 'prop_tool_box_02' }, radius = 1.1, damage = 45, holdMs = 10000, limit = 6 },
    tripwire_alarm = { model = { 'prop_ld_can_01', 'prop_cs_tin_can' },   radius = 2.0, alarmRange = 250.0, limit = 6, noise = 80.0 },
    zombie_bait    = { model = { 'prop_cs_steak', 'prop_ld_rub_binbag_01' }, lureEvery = 15, lifeSeconds = 180, noise = 120.0 },
}

-- Stews give a short bonus on top of the food.
Crafting.StewBonus = { health = 15, stamina = 30 }
