-- bs_interactions - searchable containers.
-- Each entry maps prop models to a bs_economy loot table, plus search time and refill time. Search state is per container, kept on the server by world position.

Containers = {}

Containers.Settings = {
    -- Seconds before a searched container refills.
    defaultRespawn   = 1800,
    -- Movement cancels the search.
    cancelOnMove     = true,
    -- Search animations: `search` is a standing rummage (bins, lockers, boots, fridges). `kneel` is for things on the ground, like bodies, and layers two full-body clips (a kneel base plus the hand motion). See the movement cancel note in cl_search.lua.
    anim             = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' },

    kneelAnim        = {
        base = { dict = 'amb@medic@standing@kneel@base',        clip = 'base'   },
        work = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
    },
    -- Play a sound cue when something is found.
    sound            = true,
}

Containers.Types = {
    -- Existing bush loot from your Git branch (numeric model hash).
    bush = {
        label     = 'Busch durchsuchen',
        icon      = 'search',
        time      = 4000,
        lootTable = 'rural',
        respawn   = 1800,
        models    = { 1165271193 },
    },
    trash = {
        label     = 'Search the bin',
        icon      = 'search',
        time      = 4000,
        lootTable = 'trash',
        respawn   = 1200,
        models = {
            'prop_bin_01a', 'prop_bin_02a', 'prop_bin_03a', 'prop_bin_04a',
            'prop_bin_05a', 'prop_bin_06a', 'prop_bin_07a', 'prop_bin_07b',
            'prop_bin_07c', 'prop_bin_07d', 'prop_bin_08a', 'prop_bin_08open',
            'prop_bin_09a', 'prop_bin_10a', 'prop_bin_10b', 'prop_bin_11a',
            'prop_bin_11b', 'prop_bin_12a', 'prop_bin_13a', 'prop_bin_14a',
            'prop_bin_14b', 'prop_dumpster_01a', 'prop_dumpster_02a',
            'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a',
            'prop_dumpster_4b', 'prop_skip_01a', 'prop_skip_03',
            'prop_skip_04a', 'prop_skip_05a', 'prop_skip_06a', 'prop_skip_08a',

            -- More bin models: the blue street, beach, recycling and wheelie bins are separate models from prop_bin_01a-14b.
            'prop_bin_15a',
            'prop_bin_beach_01a', 'prop_bin_beach_01b',
            'prop_bin_beach_01c', 'prop_bin_beach_01d',
            'prop_bin_delpiero', 'prop_bin_delpiero_b', 'prop_bin_delpiero_t',
            'prop_cs_bin_01', 'prop_cs_bin_02', 'prop_cs_bin_03',
            'prop_cs_bin_beach', 'prop_cs_dumpster_01a',
            'prop_wheelie_bin_01a',
            'prop_recyclebin_01a', 'prop_recyclebin_02_a', 'prop_recyclebin_02_b',
            'prop_recyclebin_02_c', 'prop_recyclebin_02_d',
            'prop_recyclebin_03_a', 'prop_recyclebin_04_a', 'prop_recyclebin_05_a',
            'prop_rub_binbag_01', 'prop_rub_binbag_03', 'prop_rub_binbag_08',
            'prop_rub_binbag_sd_01', 'prop_rub_bin_01a',
            'prop_binbag_01', 'prop_binbag_02', 'prop_binbag_03',
            'prop_binbag_04', 'prop_binbag_05', 'prop_binbag_06', 'prop_binbag_07',
            'prop_binbag_beach_01', 'prop_bin_beach_01a_ld',
            'prop_ld_binbag_01',
            'prop_dumpster_01b', 'prop_dumpster_02c',
            'prop_cardbordbox_01a', 'prop_cardbordbox_02a',
            'prop_cardbordbox_03a', 'prop_cardbordbox_04a',
        },
    },

    medical = {
        label     = 'Search for supplies',
        icon      = 'medical',
        time      = 5000,
        lootTable = 'medical',
        respawn   = 2400,
        models = {
            'v_med_bed2', 'prop_medstation_01', 'prop_medstation_02',
            'prop_medstation_03', 'prop_medstation_04', 'v_med_cabinet1',
            'v_med_cabinet2', 'v_med_cabinet3', 'prop_med_jar_01',
        },
    },

    toolbox = {
        label     = 'Look through the tools',
        icon      = 'tool',
        time      = 5000,
        lootTable = 'workshop',
        respawn   = 2400,
        models = {
            'prop_toolchest_01', 'prop_toolchest_02', 'prop_toolchest_03',
            'prop_toolchest_04', 'prop_toolchest_05', 'prop_tool_box_01',
            'prop_tool_box_02', 'prop_tool_box_03', 'prop_tool_box_04',
            -- prop_toolchest_05 must only be listed once, duplicates show the option twice.
            'prop_tool_bench02',
        },
    },

    -- Electrical boxes: slower to strip and slow to refill, since copper is valuable.
    electrical = {
        label     = 'Strip the wiring',
        icon      = 'wire',
        time      = 7000,
        lootTable = 'electrical',
        respawn   = 3600,
        models = {
            'prop_elecbox_01a', 'prop_elecbox_02', 'prop_elecbox_03',
            'prop_elecbox_04', 'prop_elecbox_05', 'prop_elecbox_06',
            'prop_elecbox_07', 'prop_elecbox_08', 'prop_elecbox_09',
            'prop_elecbox_10a', 'prop_elecbox_11a', 'prop_elecbox_12',
            'prop_elecbox_13', 'prop_elecbox_14', 'prop_elecbox_15',
            'prop_elecbox_16a', 'prop_elecbox_16b', 'prop_elecbox_16c',
            'prop_elecbox_16d', 'prop_elecbox_16e',
            'prop_fusebox_01', 'prop_fusebox_02', 'prop_fusebox_03',
            'prop_fusebox_04', 'prop_fusebox_05',
            'prop_elecbox_18a', 'prop_elecbox_20', 'prop_elecbox_22',
            'prop_elecbox_23', 'prop_elecbox_24',
            'prop_electricbox_15a', 'prop_elec_junc_01',
        },
    },

    -- Barrels and drums: small chance of a small amount of diesel, kept low on purpose (hundreds of props). Read by the bs_interactions loot path, not the loot table. See Containers.Diesel below.
    barrel = {
        label     = 'Scrap the barrel',
        icon      = 'barrel',
        time      = 6000,
        lootTable = 'barrel',
        respawn   = 2700,
        diesel    = true,
        models = {
            'prop_barrel_01a', 'prop_barrel_02a', 'prop_barrel_03a',
            'prop_barrel_04a', 'prop_barrel_05a', 'prop_barrel_06a',
            'prop_barrel_07a', 'prop_barrel_08a', 'prop_barrel_09a',
            'prop_barrel_exp_01a', 'prop_barrel_pile_01', 'prop_barrel_pile_02',
            'prop_barrel_pile_03', 'prop_barrel_pile_04',
            'prop_oil_drum_01', 'prop_oil_drum_02', 'prop_oil_drum_03',
            'prop_oil_drum_04', 'prop_oil_drum_05',
            'prop_oilcan_01a', 'prop_oilcan_02a',
            'prop_gas_tank_01a', 'prop_metal_barrel_01',
            'prop_rub_barrel_01', 'prop_rub_barrel_02', 'prop_rub_barrel_03',
            'prop_water_barrel_01', 'prop_water_barrel_dy',
            'prop_water_barrel_pile',
        },
    },

    locker = {
        label     = 'Force the locker',
        icon      = 'crowbar',
        time      = 7000,
        lootTable = 'military',
        respawn   = 3600,
        models = {
            'v_ilev_ph_gunlocker', 'prop_ld_ferris_wheel', 'v_ilev_shelf_02',
            'prop_lockerdoor_01', 'v_ilev_locker01', 'v_ilev_locker02',
        },
    },

    fridge = {
        label     = 'Check the fridge',
        icon      = 'fridge',
        time      = 3500,
        lootTable = 'kitchen',
        respawn   = 1800,
        models = {
            'prop_fridge_01', 'prop_fridge_02', 'prop_fridge_03', 'prop_fridge_04',
            'v_res_fridgemodern', 'v_res_mfridge', 'prop_vend_fridge01',
        },
    },

    vending = {
        label     = 'Pry open the machine',
        icon      = 'drop',
        time      = 6000,
        lootTable = 'vending',
        respawn   = 2400,
        models = {
            'prop_vend_soda_01', 'prop_vend_soda_02', 'prop_vend_water_01',
            'prop_vend_snack_01', 'prop_vend_coffe_01', 'prop_vend_fags_01',
        },
    },

    -- Ambulances carry medical loot (bs_medical items).
    ambulance = {
        label     = 'Search the medical bag',
        icon      = 'medical',
        time      = 5000,
        lootTable = 'medical',
        respawn   = 3600,
        models = { 'ambulance' },
    },

    car_boot = {
        label     = 'Search the boot',
        icon      = 'bag',
        time      = 5000,
        lootTable = 'vehicle',
        respawn   = 3600,
        -- Vehicles are matched by entity type rather than model.
        entityType = 'vehicle',
        -- Only from behind, so you cannot loot a car through its bonnet.
        rearOnly   = true,
    },

    -- Wreck props: car_boot only matches real vehicle entities, so decorative wrecks (scrapyards, crash scenes) are static objects matched by model, like the bins.
    car_wreck = {
        label     = 'Pick through the wreck',
        icon      = 'bag',
        time      = 6000,
        lootTable = 'vehicle',
        respawn   = 3600,
        models = {
            'prop_wreckedcar_01', 'prop_wreckedcar_02', 'prop_wreckedcar_03',
            'prop_wreckedcar_04', 'prop_wreckedcar_05',
            'bkr_prop_wreckedcar_01a', 'bkr_prop_wreckedcar_01b',
            'bkr_prop_wreckedcar_01c', 'bkr_prop_wreckedcar_01d',
            'bkr_prop_wreckedcar_02a', 'bkr_prop_wreckedcar_02b',
            'ex_prop_ex_wreck_car01',
        },

        -- Size-based wreck match for models not in the list above (map mods ship their own names; a hash cannot be turned back into a name). Uses GetModelDimensions: roughly 3-6.5m long, 1.5-2.5m wide, under 2m tall. enabled = false -> explicit list only. The staff PROP ID overlay shows model names to add.
        matchBySize = {
            enabled   = true,
            minLength = 3.0,
            maxLength = 6.6,
            minWidth  = 1.4,
            maxWidth  = 2.7,
            maxHeight = 2.3,
        },
    },

    -- BS19 additional searchable props (19 models)
    plastic_bag = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'plastic_bag', respawn = 1800,
        models = { 'prop_rub_binbag_03b' },
    },
    cement_pipes = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'cement_pipes', respawn = 1800,
        models = { 'prop_pipes_01a' },
    },
    plywood = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'plywood', respawn = 1800,
        models = { 'prop_cons_ply01' },
    },
    portable_toilet = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'portable_toilet', respawn = 1800,
        models = { 'prop_portaloo_01a' },
    },
    construction_skip = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'construction_skip', respawn = 1800,
        models = { 'prop_skip_02a' },
    },
    wood_pallet = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'wood_pallet', respawn = 1800,
        models = { 'prop_pallet_pile_02' },
    },
    fruit_boxes = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'fruit_boxes', respawn = 1800,
        models = { 'prop_rub_boxpile_04b' },
    },
    meat_crate = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'meat_crate', respawn = 1800,
        models = { 'prop_crate_11b' },
    },
    general_boxes = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 'prop_rub_boxpile_09' },
    },
    wood_pallet_mix = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'wood_pallet_mix', respawn = 1800,
        models = { 'prop_pallet_pile_04' },
    },
    drink_boxes = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'drink_boxes', respawn = 1800,
        models = { 'prop_rub_boxpile_04' },
    },
    tyre_stack = {
        label = 'Reifenstapel durchsuchen', icon = 'search', time = 5000,
        lootTable = 'tyre_stack', respawn = 1800,
        models = { -1919073083, 2069078066 },
    },
    old_couch = {
        label = 'Couch durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 2021659595, -1841495633, -2021659595 },
    },
    bicycle = {
        label = 'Fahrrad durchsuchen', icon = 'search', time = 5000,
        lootTable = 'bicycle', respawn = 1800,
        models = { 902408500 },
    },
    mailbox = {
        label = 'Briefkasten durchsuchen', icon = 'search', time = 5000,
        lootTable = 'mailbox', respawn = 1800,
        cash = { chance = 0.08, min = 1, max = 10 },
        models = { -861422469, 354284193 },
    },
    crate_extra = {
        label = 'Kiste durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { -1415300092 },
    },
    trash_bag_extra = {
        label = 'Müllsack durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { -1681329307 },
    },
    phone_booth = {
        label = 'Telefonzelle durchsuchen', icon = 'search', time = 5000,
        lootTable = 'phone_booth', respawn = 1800,
        cash = { chance = 0.08, min = 1, max = 5 },
        models = { 1281992692 },
    },


    -- Additional world props collected in Sandy Shores (2026-10-29).
    trash_bag_sandy = {
        label = 'Müllsack durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 600967813, 1098827230, 1388308576 },
    },
    shopping_cart = {
        label = 'Einkaufswagen durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 1918323043 },
    },
    old_furniture = {
        label = 'Alte Möbel durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 306579620, 603696143 },
    },
    sandy_crates = {
        label = 'Kiste durchsuchen', icon = 'search', time = 5000,
        lootTable = 'trash', respawn = 1800,
        models = { 1138027619, -2073573168, -1322592273, -52732303 },
    },
    motorcycle_salvage = {
        label = 'Motorrad durchsuchen', icon = 'search', time = 5000,
        lootTable = 'motorcycle', respawn = 1800,
        models = { 1347944675 },
    },
    locked_crate = {
        label = 'Verschlossene Kiste öffnen', icon = 'crowbar', time = 6000,
        lootTable = 'locked_crate', respawn = 2400,
        requiredWeapon = 'WEAPON_CROWBAR',
        requiredWeaponError = 'Du musst eine Brechstange in der Hand halten.',
        cash = { chance = 0.10, min = 1, max = 20 },
        models = { -1322183878 },
    },
    old_wood_barrel = {
        label = 'Altes Holzfass öffnen', icon = 'crowbar', time = 6000,
        lootTable = 'old_wood_barrel', respawn = 2400,
        requiredWeapon = 'WEAPON_CROWBAR',
        requiredWeaponError = 'Du musst eine Brechstange in der Hand halten.',
        models = { 650320113 },
    },

    electrical_salvage = {
        label = 'Search', icon = 'search', time = 5000,
        lootTable = 'electrical_salvage', respawn = 1800,
        models = { 'prop_aircon_m_04', 'prop_roofvent_06a', 'prop_aircon_m_07', 'prop_aircon_m_03', 'prop_roofvent_03a', 'prop_sub_trans_01a', 'prop_sub_trans_04a', 'prop_elecbox_25' },
    },
}

-- Diesel: one rule shared by the barrel, siphon and pump - fuel goes into containers, never pockets. `chance` is per search, not per barrel.
Containers.Diesel = {
    chance     = 0.22,
    amount     = { 5, 18 },     -- units, out of a jerrycan's 100
    -- Keep in step with Vehicles.Fuel.containers (bs_vehicles). bs_interactions cannot see that config, so this is a local copy.
    containers = { 'fuel_can', 'empty_bottle' },
}

--- Flattened model -> type lookup, built once at load.
Containers.ByModel = {}
for typeId, def in pairs(Containers.Types) do
    for _, model in ipairs(def.models or {}) do
        Containers.ByModel[type(model) == 'number' and model or GetHashKey(model)] = typeId
    end
end
