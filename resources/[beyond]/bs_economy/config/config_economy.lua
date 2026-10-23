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
            -- No clothes in loot: clothing is appearance, bought at the wardrobe NPC. Backpacks and body armour are still items and drop where listed.
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
        -- Cash: see the loot callback in bs_zombies/server/sv_director.lua. cashChance gates whether a body has money; the amount is cubed so large finds are rare.
        cashChance = 0.35,
        cashMax    = 800,
        entries = {
            { item = 'pack_small',    amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
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
            { item = 'pack_small',    amount = { 1, 1 }, weight = 2 },  -- backpack tier by area danger
            { item = 'pack_medium',   amount = { 1, 1 }, weight = 1 },
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
            { item = 'pack_small',    amount = { 1, 1 }, weight = 2 },  -- backpack tier by area danger
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
            { item = 'pack_small',    amount = { 1, 1 }, weight = 1 },
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
            { item = 'pack_small',    amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
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
            { item = 'pack_medium',   amount = { 1, 1 }, weight = 1 },  -- rare zombie drop
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
            { item = 'pack_large',    amount = { 1, 1 }, weight = 3  },
            { item = 'pack_military', amount = { 1, 1 }, weight = 1  },
            { item = 'vest_tactical', amount = { 1, 1 }, weight = 3  },
            { item = 'vest_plate',    amount = { 1, 1 }, weight = 1  },
        },
    },
}

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
