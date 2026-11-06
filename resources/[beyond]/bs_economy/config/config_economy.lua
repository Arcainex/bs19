-- bs_economy - economy and loot config.

Economy = {}

Economy.Settings = {
    sellRateMultiplier  = 0.45,   -- vendors buy at this fraction of base value
    restockInterval     = 3600,   -- seconds
    -- Loot point respawn window.
    lootRespawn         = { min = 900, max = 2400 },
}

-- Vendors moved to bs_traders/config/config_traders.lua. Kept empty as a pointer to where Economy.Vendors went.
Economy.Vendors = {}

-- Loot tables. `rolls` is the number of draws, each draw picks one weighted entry. Rolled on the server only.
Economy.LootTables = {
    trash = {
        rolls = { min = 0, max = 2 },
        entries = {
            { item = 'cloth',       amount = { 1, 2 }, weight = 34 },
            { item = 'scrap_metal', amount = { 1, 2 }, weight = 26 },
            { item = 'canned_food', amount = { 1, 1 }, weight = 14 },
            { item = 'water_bottle',amount = { 1, 1 }, weight = 12 },
            { item = 'bandage',     amount = { 1, 1 }, weight = 8  },
            { item = 'wood_plank',  amount = { 1, 2 }, weight = 6  },
            -- No clothes in loot: clothing is appearance, bought at the wardrobe NPC.
        },
    },
    kitchen = {
        rolls = { min = 1, max = 2 },
        entries = {
            { item = 'canned_food', amount = { 1, 3 }, weight = 45 },
            { item = 'water_bottle',amount = { 1, 2 }, weight = 35 },
            { item = 'cloth',       amount = { 1, 2 }, weight = 20 },
        },
    },
    vending = {
        rolls = { min = 1, max = 3 },
        entries = {
            { item = 'water_bottle',amount = { 1, 2 }, weight = 55 },
            { item = 'canned_food', amount = { 1, 1 }, weight = 35 },
            { item = 'scrap_metal', amount = { 1, 1 }, weight = 10 },
        },
    },
    workshop = {
        rolls = { min = 1, max = 3 },
        entries = {  -- boosters / gadgets (rare)
            { item = 'booster_decoy', amount = { 1, 1 }, weight = 3 },
            { item = 'booster_fortify', amount = { 1, 1 }, weight = 2 },
            { item = 'att_grip',    amount = { 1, 1 }, weight = 6  },
            { item = 'att_flashlight', amount = { 1, 1 }, weight = 5 },
            { item = 'scrap_metal', amount = { 2, 4 }, weight = 40 },
            { item = 'wood_plank',  amount = { 1, 3 }, weight = 28 },
            { item = 'nails',       amount = { 4, 12 }, weight = 22 },  -- building
            { item = 'hammer',      amount = { 1, 1 }, weight = 3  },
            { item = 'toolbox',     amount = { 1, 1 }, weight = 8  },
            { item = 'spark_plug',  amount = { 1, 2 }, weight = 7  },
            { item = 'battery',     amount = { 1, 1 }, weight = 4  },
            { item = 'fuel_tank',   amount = { 1, 1 }, weight = 3  },
            { item = 'lockpick',    amount = { 1, 1 }, weight = 5  },
            { item = 'cloth',       amount = { 1, 2 }, weight = 24 },
            -- What is hanging on the back of a workshop door.
        },
    },
    -- Street cabinets and fuse boxes: narrow table (copper, wire, the odd component), no food or medicine.
    electrical = {
        rolls = { min = 1, max = 2 },
        entries = {  -- boosters (rare)
            { item = 'radio', amount = {1,1}, weight = 6 },
            { item = 'radio_advanced', amount = {1,1}, weight = 3 },
            { item = 'radio_military', amount = {1,1}, weight = 1 },
            { item = 'portable_antenna', amount = {1,1}, weight = 1 },
            { item = 'booster_drone', amount = { 1, 1 }, weight = 2 },
            { item = 'copper',          amount = { 1, 3 }, weight = 46 },
            { item = 'electrical_wire', amount = { 1, 2 }, weight = 24 },
            { item = 'scrap_metal',     amount = { 1, 2 }, weight = 20 },
            { item = 'battery',         amount = { 1, 1 }, weight = 6  },
            { item = 'att_flashlight',  amount = { 1, 1 }, weight = 4  },
        },
    },

    -- Barrels: thin table (metal, rags, some wire) so barrels stay a fuel errand. Diesel is not an item, see Containers.Diesel.
    barrel = {
        rolls = { min = 0, max = 2 },
        entries = {
            { item = 'scrap_metal',     amount = { 1, 3 }, weight = 44 },
            { item = 'cloth',           amount = { 1, 2 }, weight = 28 },
            { item = 'copper',          amount = { 1, 1 }, weight = 12 },
            { item = 'electrical_wire', amount = { 1, 1 }, weight = 6  },
            { item = 'empty_bottle',    amount = { 1, 1 }, weight = 10 },
        },
    },

    vehicle = {
        rolls = { min = 0, max = 3 },
        entries = {
            { item = 'scrap_metal', amount = { 1, 3 }, weight = 38 },
            { item = 'cloth',       amount = { 1, 2 }, weight = 26 },
            { item = 'bandage',     amount = { 1, 2 }, weight = 16 },
            { item = 'canned_food', amount = { 1, 1 }, weight = 12 },
            { item = 'hunting_knife', amount = { 1, 1 }, weight = 8 },
            { item = 'spark_plug',  amount = { 1, 1 }, weight = 6 },
            -- Left on the back seat, which is where coats live.
        },
    },
    walker = {
        rolls = { min = 0, max = 2 },
        -- Cash: see the loot callback in bs_zombies/server/sv_director.lua. cashChance gates whether a body has money
        cashChance = 0.35,
        cashMax    = 800,
        entries = {
            { item = 'pack_civilian',    amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
            { item = 'zombie_teeth', amount = { 1, 2 }, weight = 34 },
            { item = 'cloth',        amount = { 1, 3 }, weight = 28 },
            { item = 'canned_food',  amount = { 1, 1 }, weight = 13 },
            { item = 'bandage',      amount = { 1, 1 }, weight = 10 },
            { item = 'lockpick',     amount = { 1, 1 }, weight = 6 },
            { item = 'water_bottle', amount = { 1, 1 }, weight = 6 },
            { item = 'scrap_metal',  amount = { 1, 2 }, weight = 3 },
            -- bs_drugs: cut drugs and smokes in the pockets.
            { item = 'cigarette',       amount = { 1, 4 }, weight = 7 },
            { item = 'matches',         amount = { 1, 1 }, weight = 3 },
            { item = 'weed_bad',        amount = { 1, 2 }, weight = 3 },
            { item = 'amphetamine_bad', amount = { 1, 1 }, weight = 2 },
            { item = 'cocaine_bad',     amount = { 1, 1 }, weight = 1 },
            { item = 'morphine_bad',    amount = { 1, 1 }, weight = 1 },
            -- Off the body: cheap clothes only. Bodies are the most common container, so weights here are the smallest in the file.
        },
    },
    urban = {
        rolls = { min = 1, max = 3 },
        entries = {
            { item = 'pack_civilian',    amount = { 1, 1 }, weight = 2 },  -- backpack tier by area danger
            { item = 'pack_hiking',   amount = { 1, 1 }, weight = 1 },
            { item = 'cloth',       amount = { 1, 4 }, weight = 30 },
            { item = 'scrap_metal', amount = { 1, 3 }, weight = 30 },
            { item = 'nails',       amount = { 2, 6 }, weight = 8  },  -- building
            { item = 'canned_food', amount = { 1, 2 }, weight = 20 },
            { item = 'bandage',     amount = { 1, 2 }, weight = 15 },
            { item = 'medkit',      amount = { 1, 1 }, weight = 5 },
        },
    },
    -- Zone tables referenced by bs_zombies/config/config_zones.lua. Missing tables make zones fall back silently.
    rural = {
        rolls = { min = 1, max = 2 },
        entries = {
            { item = 'pack_civilian',    amount = { 1, 1 }, weight = 2 },  -- backpack tier by area danger
            { item = 'wood_plank',  amount = { 1, 3 }, weight = 30 },
            { item = 'log',         amount = { 1, 2 }, weight = 14 },  -- building
            { item = 'nails',       amount = { 2, 8 }, weight = 10 },
            { item = 'cloth',       amount = { 1, 3 }, weight = 24 },
            { item = 'canned_food', amount = { 1, 2 }, weight = 22 },
            { item = 'scrap_metal', amount = { 1, 2 }, weight = 18 },
            { item = 'hunting_knife', amount = { 1, 1 }, weight = 6 },
        },
    },
    medical = {
        rolls = { min = 1, max = 3 },
        entries = {  -- boosters (rare)
            { item = 'pack_civilian',    amount = { 1, 1 }, weight = 1 },
            { item = 'booster_medic', amount = { 1, 1 }, weight = 2 },
            { item = 'booster_adrenaline', amount = { 1, 1 }, weight = 3 },
            { item = 'booster_regen', amount = { 1, 1 }, weight = 3 },
            { item = 'bandage',     amount = { 1, 3 }, weight = 34 },
            { item = 'antiseptic',  amount = { 1, 2 }, weight = 24 },
            { item = 'medkit',      amount = { 1, 1 }, weight = 18 },
            { item = 'cloth',       amount = { 1, 3 }, weight = 16 },
            { item = 'antibiotics', amount = { 1, 1 }, weight = 8  },
            -- medical system
            { item = 'rag',          amount = { 1, 3 }, weight = 20 },
            { item = 'splint',       amount = { 1, 1 }, weight = 12 },
            { item = 'tourniquet',   amount = { 1, 1 }, weight = 10 },
            { item = 'saline',       amount = { 1, 1 }, weight = 9  },
            { item = 'painkillers',  amount = { 1, 2 }, weight = 14 },
            { item = 'blood_bag',    amount = { 1, 1 }, weight = 4  },
            { item = 'transfusion_kit', amount = { 1, 1 }, weight = 2 },
            { item = 'surgical_kit', amount = { 1, 1 }, weight = 3  },
            { item = 'antiviral',    amount = { 1, 1 }, weight = 1  },
            { item = 'defibrillator',amount = { 1, 1 }, weight = 1  },
        },
    },

    -- Bodies: walkers carry rags, tougher types carry more.
    runner = {
        rolls = { min = 0, max = 2 },
        cashChance = 0.45,
        cashMax    = 800,
        entries = {  -- boosters (rare)
            { item = 'pack_civilian',    amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
            { item = 'booster_adrenaline', amount = { 1, 1 }, weight = 2 },
            { item = 'zombie_teeth', amount = { 1, 3 }, weight = 42 },
            { item = 'cloth',        amount = { 1, 2 }, weight = 30 },
            { item = 'rag',          amount = { 1, 2 }, weight = 14 },
            { item = 'bandage',      amount = { 1, 1 }, weight = 18 },
            { item = 'water_bottle', amount = { 1, 1 }, weight = 10 },
            { item = 'amphetamine_bad', amount = { 1, 1 }, weight = 4 },
            { item = 'cocaine_bad',     amount = { 1, 1 }, weight = 3 },
            { item = 'cigarette',       amount = { 1, 3 }, weight = 5 },
        },
    },
    brute = {
        rolls = { min = 1, max = 3 },
        -- Harder to kill, better pockets.
        cashChance = 0.65,
        cashMax    = 800,
        entries = {
            { item = 'pack_hiking',   amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
            { item = 'vest_tactical', amount = { 1, 1 }, weight = 1 },
            { item = 'zombie_teeth', amount = { 2, 5 }, weight = 38 },
            { item = 'scrap_metal',  amount = { 1, 3 }, weight = 26 },
            { item = 'medkit',       amount = { 1, 1 }, weight = 14 },
            { item = 'armour_plate', amount = { 1, 1 }, weight = 6  },
            { item = 'cloth',        amount = { 1, 3 }, weight = 16 },
            { item = 'morphine_bad', amount = { 1, 1 }, weight = 5 },
            { item = 'cocaine_bad',  amount = { 1, 1 }, weight = 3 },
        },
    },
    screamer = {
        rolls = { min = 1, max = 2 },
        entries = {  -- boosters (rare)
            { item = 'booster_adrenaline', amount = { 1, 1 }, weight = 3 },
            { item = 'zombie_teeth', amount = { 1, 4 }, weight = 40 },
            { item = 'antiseptic',   amount = { 1, 1 }, weight = 24 },
            { item = 'antibiotics',  amount = { 1, 1 }, weight = 12 },
            { item = 'cloth',        amount = { 1, 2 }, weight = 24 },
        },
    },

    military = {
        rolls = { min = 1, max = 4 },
        entries = {  -- boosters (rare)
            { item = 'booster_turret', amount = { 1, 1 }, weight = 2 },
            -- shield parked: { item = 'booster_shield', amount = { 1, 1 }, weight = 3 },
            { item = 'booster_focus', amount = { 1, 1 }, weight = 3 },
            { item = 'scrap_metal',   amount = { 2, 5 }, weight = 40 },
            { item = 'medkit',        amount = { 1, 1 }, weight = 20 },
            { item = 'hunting_knife', amount = { 1, 1 }, weight = 15 },
            { item = 'toolbox',       amount = { 1, 1 }, weight = 10 },
            { item = 'antibiotics',   amount = { 1, 2 }, weight = 8  },
            { item = 'tourniquet',    amount = { 1, 1 }, weight = 8  },
            { item = 'surgical_kit',  amount = { 1, 1 }, weight = 2  },
            { item = 'armour_plate',  amount = { 1, 1 }, weight = 7  },
            { item = 'att_suppressor',amount = { 1, 1 }, weight = 6  },
            { item = 'att_scope',     amount = { 1, 1 }, weight = 6  },
            { item = 'att_extmag',    amount = { 1, 2 }, weight = 9  },
            { item = 'att_flashlight',amount = { 1, 1 }, weight = 8  },

            -- Packs and vests by area danger: military areas hold the big ones, all rare.
            { item = 'pack_survival',    amount = { 1, 1 }, weight = 3  },
            { item = 'pack_field_military', amount = { 1, 1 }, weight = 1  },
            { item = 'vest_tactical', amount = { 1, 1 }, weight = 3  },
            { item = 'vest_plate',    amount = { 1, 1 }, weight = 1  },
        },
    },
}


-- Storage-specific pools: their container type is the source, not the surrounding map zone.
Economy.LootTables.travel={rolls={min=1,max=3},entries={
    {item='cloth',weight=30,amount={1,3}},
    {item='water_bottle',weight=24,amount={1,2}},
    {item='canned_food',weight=20,amount={1,2}},
    {item='bandage',weight=12,amount={1,2}},
    {item='pack_civilian',weight=3,amount={1,1}},
    {item='pack_hiking',weight=1,amount={1,1}},
    {item='pistol',weight=1,amount={1,1}},
    {item='ammo_pistol',weight=5,amount={1,2}},
}}
Economy.LootTables.office={rolls={min=1,max=3},entries={
    {item='cloth',weight=25,amount={1,2}},
    {item='scrap_metal',weight=30,amount={1,2}},
    {item='electrical_wire',weight=16,amount={1,2}},
    {item='battery',weight=2,amount={1,1}},
    {item='lockpick',weight=2,amount={1,1}},
    {item='water_bottle',weight=15,amount={1,1}},
}}
Economy.LootTables.parcel={rolls={min=1,max=3},entries={
    {item='canned_food',weight=22,amount={1,2}},
    {item='water_bottle',weight=22,amount={1,2}},
    {item='cloth',weight=22,amount={1,3}},
    {item='scrap_metal',weight=18,amount={1,3}},
    {item='duct_tape',weight=10,amount={1,2}},
    {item='bandage',weight=6,amount={1,2}},
}}
Economy.LootTables.warehouse={rolls={min=1,max=3},entries={
    {item='scrap_metal',weight=30,amount={2,5}},
    {item='wood_plank',weight=25,amount={1,3}},
    {item='nails',weight=18,amount={3,10}},
    {item='duct_tape',weight=15,amount={1,3}},
    {item='toolbox',weight=5,amount={1,1}},
    {item='gun_parts',weight=3,amount={1,2}},
    {item='att_grip',weight=2,amount={1,1}},
}}
Economy.LootTables.industrial={rolls={min=1,max=3},entries={
    {item='scrap_metal',weight=35,amount={2,5}},
    {item='copper',weight=20,amount={1,3}},
    {item='electrical_wire',weight=22,amount={1,3}},
    {item='duct_tape',weight=10,amount={1,3}},
    {item='toolbox',weight=8,amount={1,1}},
    {item='gun_parts',weight=3,amount={1,2}},
}}
Economy.LootTables.fishing={rolls={min=1,max=3},entries={
    {item='fish_bait',weight=50,amount={2,6}},
    {item='fishing_rod',weight=6,amount={1,1}},
    {item='water_bottle',weight=20,amount={1,1}},
    {item='cloth',weight=20,amount={1,2}},
}}
Economy.LootTables.safe={rolls={min=1,max=3},entries={
    {item='gun_parts',weight=28,amount={1,3}},
    {item='ammo_pistol',weight=22,amount={1,3}},
    {item='pistol',weight=3,amount={1,1}},
    {item='revolver',weight=2,amount={1,1}},
    {item='att_suppressor',weight=3,amount={1,1}},
    {item='lockpick',weight=12,amount={1,1}},
    {item='scrap_metal',weight=30,amount={1,3}},
}}
Economy.LootTables.police={rolls={min=1,max=3},entries={
    {item='ammo_pistol',weight=35,amount={1,3}},
    {item='ammo_shotgun',weight=22,amount={1,3}},
    {item='ammo_rifle',weight=15,amount={1,2}},
    {item='gun_parts',weight=25,amount={1,3}},
    {item='att_flashlight',weight=10,amount={1,1}},
    {item='att_extmag',weight=8,amount={1,1}},
    {item='att_scope',weight=5,amount={1,1}},
    {item='combat_pistol',weight=4,amount={1,1}},
    {item='pump_shotgun',weight=3,amount={1,1}},
    {item='smg',weight=2,amount={1,1}},
    {item='carbine',weight=1,amount={1,1}},
    {item='heavy_pistol',weight=2,amount={1,1}},
    {item='combat_pdw',weight=1,amount={1,1}},
    {item='pistol_mk2',weight=0.5,amount={1,1}},
    {item='carbine_mk2',weight=0.25,amount={1,1}},
}}
Economy.LootTables.weapon_storage={rolls={min=1,max=3},entries={
    {item='gun_parts',weight=35,amount={2,4}},
    {item='ammo_pistol',weight=20,amount={1,3}},
    {item='ammo_rifle',weight=20,amount={1,3}},
    {item='ammo_shotgun',weight=12,amount={1,3}},
    {item='att_scope',weight=8,amount={1,1}},
    {item='att_suppressor',weight=8,amount={1,1}},
    {item='att_grip',weight=8,amount={1,1}},
    {item='att_extmag',weight=10,amount={1,1}},
    {item='pistol',weight=3,amount={1,1}},
    {item='smg',weight=2,amount={1,1}},
    {item='assault_rifle',weight=2,amount={1,1}},
    {item='pump_shotgun',weight=3,amount={1,1}},
    {item='special_carbine',weight=1,amount={1,1}},
}}
Economy.LootTables.shop=Economy.LootTables.urban
Economy.LootTables.home=Economy.LootTables.urban
for _,entry in ipairs({
    {item='ammo_rifle',weight=30,amount={1,4}},
    {item='ammo_pistol',weight=18,amount={1,3}},
    {item='ammo_shotgun',weight=15,amount={1,3}},
    {item='ammo_magnum',weight=8,amount={1,2}},
    {item='gun_parts',weight=28,amount={1,4}},
    {item='assault_rifle',weight=3,amount={1,1}},
    {item='advanced_rifle',weight=2,amount={1,1}},
    {item='special_carbine',weight=2,amount={1,1}},
    {item='bullpup_rifle',weight=2,amount={1,1}},
    {item='compact_rifle',weight=2,amount={1,1}},
    {item='assault_shotgun',weight=1,amount={1,1}},
    {item='bullpup_shotgun',weight=1,amount={1,1}},
    {item='mg',weight=0.6,amount={1,1}},
    {item='combat_mg',weight=0.4,amount={1,1}},
    {item='heavy_sniper',weight=0.25,amount={1,1}},
    {item='military_rifle',weight=0.6,amount={1,1}},
    {item='heavy_shotgun',weight=0.5,amount={1,1}},
    {item='assault_rifle_mk2',weight=0.3,amount={1,1}},
    {item='combat_mg_mk2',weight=0.2,amount={1,1}},
    {item='heavy_sniper_mk2',weight=0.1,amount={1,1}},
    {item='att_muzzle_brake',weight=4,amount={1,1}},
    {item='att_reflex',weight=3,amount={1,1}},
    {item='att_scope_long',weight=2,amount={1,1}},
})do Economy.LootTables.military.entries[#Economy.LootTables.military.entries+1]=entry end

--- Gatherable world resources.
Economy.Gathering = {
    scrap = { item = 'scrap_metal', time = 5000, skill = 'survival', models = { 'prop_rub_scrap_03', 'prop_rub_scrap_04' } },
    wood  = { item = 'wood_plank',  time = 6000, skill = 'survival', models = { 'prop_logpile_01', 'prop_logpile_06' } },
}


-- Lookup used by bs_interactions when it rolls a container.

function Economy.GetLootTable(id)
    return Economy.LootTables[id]
end

-- Cash machines: opened by a real explosion, no interact option. Cash is good but slow to come back.
Economy.ATM = {
    enabled = true,

    models = {
        'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm',
    },

    -- How close the blast has to be to the machine.
    blastRadius = 4.0,
    -- How close the person who set it off must be to claim it.
    claimRadius = 30.0,

    cash  = { 600, 3200 },
    scrap = { 2, 6 },

    -- Seconds before the same machine can be blown again (45 minutes).
    cooldown = 2700,
}
