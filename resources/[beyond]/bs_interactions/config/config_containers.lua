-- bs_interactions - searchable containers.

Containers = {}

Containers.Settings = {
    -- Seconds before a searched container refills.
    defaultRespawn   = 1800,
    -- Movement cancels the search.
    cancelOnMove     = true,
    -- Search animations: `search` is a standing rummage (bins, lockers, boots, fridges). `kneel` is for things on
    anim             = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' },

    kneelAnim        = {
        base = { dict = 'amb@medic@standing@kneel@base',        clip = 'base'   },
        work = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
    },
    -- Play a sound cue when something is found.
    sound            = true,
}

Containers.Types = {
    furniture = {label='Search furniture',icon='search',time=4500,lootTable='urban',respawn=1800},
    drawers = {label='Search drawers',icon='search',time=4000,lootTable='kitchen',respawn=1800,
        models={'prop_ld_int_safe_01','v_res_tre_storagebox','v_res_mconsolemod','v_res_mconsolemove','v_res_tre_bedside','v_res_tre_draws','v_res_tre_wardrobe','v_res_mcupboard'}},
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
            'prop_dumpster_4b', 'prop_skip_01a', 'prop_skip_02a', 'prop_skip_03',
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

    -- Barrels and drums: small chance of a small amount of diesel, kept low (hundreds of props).
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

    -- Wreck props: car_boot only matches real vehicle entities
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

        -- Size-based wreck match for models not in the list above (map mods ship their own names; a hash cannot be turned back into a name). Uses GetModelDimensions: roughly 3-6.5m long, 1.5-2.5m wide, under 2m tall. enabled = false to explicit list only. The staff PROP ID overlay shows model names to add.
        matchBySize = {
            enabled   = true,
            minLength = 3.0,
            maxLength = 6.6,
            minWidth  = 1.4,
            maxWidth  = 2.7,
            maxHeight = 2.3,
        },
    },
}

-- Diesel: one rule shared by the barrel, siphon and pump - fuel goes into containers
Containers.Diesel = {
    chance     = 0.22,
    amount     = { 5, 18 },     -- units, out of a jerrycan's 100
    -- Keep in step with Vehicles.Fuel.containers (bs_vehicles). bs_interactions cannot see that config, so this is a local copy.
    containers = { 'fuel_can', 'empty_bottle' },
}

-- Storage families. Only real loaded models are registered by cl_search.
-- Unavailable DLC/custom model names are skipped rather than turned into proximity targets.
Containers.Types.backpack={label="Search backpack",icon='search',time=3200,lootTable='travel',respawn=2400,models={"prop_michael_backpack","p_michael_backpack_s","prop_cs_backpack_01"}}
Containers.Types.duffel={label="Search duffel bag",icon='search',time=3500,lootTable='travel',respawn=2400,models={"prop_cs_heist_bag_01","prop_cs_heist_bag_02","prop_cs_duffel_01","prop_cs_duffel_01b","p_ld_heist_bag_s","p_ld_heist_bag_s_1"}}
Containers.Types.suitcase={label="Search suitcase",icon='search',time=3500,lootTable='travel',respawn=2400,models={"prop_ld_suitcase_01","prop_ld_suitcase_02","prop_luggage_01a","prop_luggage_02a","prop_luggage_03a","prop_luggage_04a","prop_luggage_05a","prop_luggage_06a","prop_luggage_07a","prop_luggage_08a","prop_luggage_09a"}}
Containers.Types.briefcase={label="Search briefcase",icon='search',time=4000,lootTable='office',respawn=2400,models={"prop_ld_case_01","prop_ld_case_02","prop_security_case_01"}}
Containers.Types.cardboard_box={label="Search parcel",icon='search',time=3500,lootTable='parcel',respawn=2400,models={"prop_cs_cardbox_01","prop_cardbordbox_01a","prop_cardbordbox_02a","prop_cardbordbox_03a","prop_cardbordbox_04a","prop_box_01a","prop_box_02a","prop_box_03a","prop_box_04a","prop_box_05a","prop_box_06a","prop_box_07a","prop_box_08a"}}
Containers.Types.wooden_crate={label="Search wooden crate",icon='search',time=4500,lootTable='warehouse',respawn=2400,models={"prop_box_wood01a","prop_box_wood02a","prop_box_wood03a","prop_box_wood04a","prop_box_wood05a","prop_box_wood02a_pu","prop_box_wood05b","prop_box_wood06a"}}
Containers.Types.plastic_crate={label="Search storage crate",icon='search',time=4000,lootTable='warehouse',respawn=2400,models={"prop_crate_01a","prop_crate_02a","prop_crate_03a","prop_crate_04a","prop_crate_05a","prop_crate_06a","prop_crate_07a","prop_crate_08a","prop_crate_09a","prop_crate_10a","prop_crate_11a"}}
Containers.Types.military_crate={label="Search military supplies",icon='search',time=6500,lootTable='military',respawn=2400,models={"prop_mil_crate_01","prop_mil_crate_02","prop_box_ammo01a","prop_box_ammo02a","prop_box_ammo03a","prop_box_ammo04a","prop_box_ammo05a","prop_box_ammo06a","prop_box_ammo07a"}}
Containers.Types.police_armory={label="Search police weapon storage",icon='search',time=6500,lootTable='police',respawn=2400,models={"v_ilev_ph_gunlocker","prop_gun_case_01","prop_box_guncase_01a","prop_ld_guncase_01"}}
Containers.Types.weapon_rack={label="Search weapon rack",icon='search',time=6000,lootTable='military',respawn=2400,models={"prop_gunrack","prop_gunrack_01","prop_gunrack_02","prop_gunrack_03","gr_prop_gr_gunsmithsupl_02a"}}
Containers.Types.gun_case={label="Search gun case",icon='search',time=6000,lootTable='weapon_storage',respawn=2400,models={"gr_prop_gr_guncase_01a","gr_prop_gr_guncase_02a","gr_prop_gr_guncase_03a"}}
Containers.Types.office_storage={label="Search office storage",icon='search',time=4000,lootTable='office',respawn=2400,models={"prop_cabinet_01","prop_cabinet_01b","prop_cabinet_02b","v_corp_cabinet","v_corp_filecablow","v_corp_filecabtall","v_corp_offshelf","v_corp_offshelf_01"}}
Containers.Types.safe={label="Search safe",icon='search',time=7000,lootTable='safe',respawn=2400,models={"prop_ld_int_safe_01","prop_ld_int_safe_01b","prop_safe_01","prop_safe_02","prop_safe_03","prop_ld_int_safe_door"}}
Containers.Types.wardrobe={label="Search wardrobe",icon='search',time=4500,lootTable='travel',respawn=2400,models={"v_res_tre_wardrobe","v_res_mcupboard","v_res_tre_wdunits","v_res_tre_wdunitsc","v_res_j_wardrobe","v_res_m_wardrobe"}}
Containers.Types.bedside_storage={label="Search bedside storage",icon='search',time=3500,lootTable='home',respawn=2400,models={"v_res_tre_bedside","v_res_mbbedtable","v_res_mdbedtable","v_res_tre_draws","v_res_d_dressingtable","v_res_mconsolemod","v_res_mconsolemove"}}
Containers.Types.kitchen_cupboard={label="Search kitchen cupboard",icon='search',time=4000,lootTable='kitchen',respawn=2400,models={"v_res_mcabinet","v_res_mcounter","v_res_tre_cupboard","v_res_fa_cabinet","v_res_mchest"}}
Containers.Types.shelf_storage={label="Search shelf supplies",icon='search',time=4500,lootTable='warehouse',respawn=2400,models={"v_ilev_shelf_02","prop_shelves_01","prop_shelves_02","prop_shelves_03","prop_shelf_01","prop_shelf_02","prop_shelf_03","prop_rub_cabinet01","prop_rub_cabinet02"}}
Containers.Types.shop_till={label="Search shop till",icon='search',time=5000,lootTable='shop',respawn=2400,models={"prop_till_01","prop_till_02","prop_till_03","prop_cash_register_01"}}
Containers.Types.shop_basket={label="Search basket",icon='search',time=3000,lootTable='shop',respawn=2400,models={"prop_shopping_bags01","prop_shopping_bags02","prop_shop_basket_01","prop_shop_basket_02","prop_fruit_basket"}}
Containers.Types.food_crate={label="Search food crate",icon='search',time=3500,lootTable='kitchen',respawn=2400,models={"prop_fruitstand_01","prop_fruitstand_02","prop_crate_11e","prop_crate_11d","prop_crate_11c","prop_crate_11b"}}
Containers.Types.cooler={label="Search cooler",icon='search',time=3500,lootTable='kitchen',respawn=2400,models={"prop_coolbox_01","prop_coolbox_02","prop_coolbox_03","prop_coolbox_04","prop_coolbox_05","prop_coolbox_06"}}
Containers.Types.medical_bag={label="Search medical supplies",icon='search',time=4500,lootTable='medical',respawn=2400,models={"prop_ld_health_pack","prop_ld_health_pack_01","prop_med_bag_01","xm_prop_x17_bag_med_01a"}}
Containers.Types.medicine_cabinet={label="Search medicine cabinet",icon='search',time=4500,lootTable='medical',respawn=2400,models={"v_med_cabinet1","v_med_cabinet2","v_med_cabinet3","v_res_mmedcab","v_res_tre_medicinecabinet","prop_medstation_01","prop_medstation_02","prop_medstation_03","prop_medstation_04"}}
Containers.Types.first_aid_box={label="Search first-aid box",icon='search',time=4000,lootTable='medical',respawn=2400,models={"prop_medstation_01a","prop_firstaid_01","prop_firstaid_02"}}
Containers.Types.industrial_case={label="Search equipment case",icon='search',time=5000,lootTable='industrial',respawn=2400,models={"prop_box_elec01a","prop_box_elec01b","prop_box_elec02a","prop_box_elec02b","prop_box_elec03a","prop_box_elec04a","prop_box_elec05a","prop_box_elec06a","prop_box_elec07a"}}
Containers.Types.parts_storage={label="Search spare parts",icon='search',time=5000,lootTable='vehicle',respawn=2400,models={"prop_toolchest_01","prop_toolchest_02","prop_toolchest_03"}}
Containers.Types.tool_case={label="Search tool case",icon='search',time=4500,lootTable='workshop',respawn=2400,models={"prop_tool_box_01","prop_tool_box_02","prop_tool_box_03","prop_tool_box_04","prop_tool_box_05","prop_toolchest_04","prop_toolchest_05"}}
Containers.Types.fishing_storage={label="Search fishing supplies",icon='search',time=4000,lootTable='fishing',respawn=2400,models={"prop_fishing_bait_01"}}
Containers.Types.camp_storage={label="Search camping supplies",icon='search',time=4000,lootTable='travel',respawn=2400,models={"prop_cs_sack_01","prop_cs_sack_02"}}
-- Generic lockers do not become military containers merely because of their location.
Containers.Types.locker.lootTable='urban'
local excluded={prop_ld_ferris_wheel=true,v_med_bed2=true}
local owner={}
local order={}
for id in pairs(Containers.Types)do order[#order+1]=id end
table.sort(order)
-- Later explicit families own aliases that appeared in older generic lists.
local preferred={"backpack","duffel","suitcase","briefcase","cardboard_box","wooden_crate","plastic_crate","military_crate","police_armory","weapon_rack","gun_case","office_storage","safe","wardrobe","bedside_storage","kitchen_cupboard","shelf_storage","shop_till","shop_basket","food_crate","cooler","medical_bag","medicine_cabinet","first_aid_box","industrial_case","parts_storage","tool_case","fishing_storage","camp_storage"}
for _,id in ipairs(preferred)do for _,model in ipairs(Containers.Types[id].models or {})do owner[model]=id end end
for _,id in ipairs(order)do
    local def=Containers.Types[id];local clean={}
    for _,model in ipairs(def.models or {})do
        if not excluded[model]and (not owner[model]or owner[model]==id)then
            if not owner[model]then owner[model]=id end
            local duplicate=false;for _,known in ipairs(clean)do if known==model then duplicate=true;break end end
            if not duplicate then clean[#clean+1]=model end
        end
    end
    if def.models then def.models=clean end
end

--- Flattened model to type lookup, built once at load.
Containers.ByModel = {}
for typeId, def in pairs(Containers.Types) do
    for _, model in ipairs(def.models or {}) do
        Containers.ByModel[GetHashKey(model)] = typeId
    end
end

-- Optional installed-model discovery. Explicit names remain the first choice.
Containers.Discovery={enabled=false,overrides={}}
function Containers.DiscoverType(name)
    if type(name)~='string'or #name>128 then return end
    name=name:lower()
    local cfg=Containers.Discovery
    local override=cfg.overrides and cfg.overrides[name]
    if override==false then return end
    if type(override)=='string'then return Containers.Types[override]and override or nil end
    local known=Containers.ByModel[GetHashKey(name)];if known then return known end
    if not cfg.enabled then return end
    for _,excluded in ipairs({'door','strap','handle','debris','fragment','_lod','_glass','_wheel'})do if name:find(excluded,1,true)then return end end
    local families={
        {'gunlocker','police_armory'},{'gunrack','weapon_rack'},{'guncase','gun_case'},{'gun_case','gun_case'},
        {'mil_crate','military_crate'},{'ammo_box','military_crate'},{'box_ammo','military_crate'},
        {'backpack','backpack'},{'suitcase','suitcase'},{'luggage','suitcase'},{'duffel','duffel'},
        {'briefcase','briefcase'},{'tool_box','tool_case'},{'toolbox','tool_case'},{'toolchest','tool_case'},
        {'med_cabinet','medicine_cabinet'},{'medical_cabinet','medicine_cabinet'},{'med_bag','medical_bag'},
        {'firstaid','first_aid_box'},{'coolbox','cooler'},{'cooler_box','cooler'},{'filingcab','office_storage'},
        {'wardrobe','wardrobe'},{'bedside','bedside_storage'},{'locker','locker'},{'cabinet','office_storage'},
        {'wood_crate','wooden_crate'},{'box_wood','wooden_crate'},{'cardboard','cardboard_box'},{'cardbord','cardboard_box'},
        {'storagebox','plastic_crate'},{'storage_box','plastic_crate'},{'storagebin','plastic_crate'},
    }
    for _,pair in ipairs(families)do if name:find(pair[1],1,true)then return pair[2]end end
end
