-- bs_traders - NPC trader and quest config.
-- Two roles, usable together on one NPC: trader (fixed item list and prices) and quest (missions from Traders.Missions).
-- Every NPC is anchored to a safe zone: it names a `zone` id from Zones.Safe (bs_zombies/config/config_zones.lua) and an `offset` from its centre. zoneCoords() at the bottom resolves the final coordinate, so NPCs follow their zone if it moves.
-- The /traderdebug editor writes a full absolute override to the database for that NPC, which then ignores `zone` + `offset` (see server/sv_registry.lua).

Traders = {}

Traders.Settings = {
    -- Percent off per faction rank step above the lowest rank; outsiders pay a surcharge at faction-only traders.
    rankDiscountPct = 5,
    outsiderSurchargePct = 25,

    spawnDistance   = 60.0,
    despawnDistance = 80.0,
    interactDistance = 2.5,

    -- Vendor stock refills to its max this often.
    restockInterval  = 3600,

    -- Default cooldown before the same giver's mission can be re-accepted, used when a mission sets no `cooldown`.
    defaultCooldown  = 1800,

    -- Player faction safezone flags get copies of these town NPCs (trader + mission giver), members only. (F1)
    factionSafezoneNpcs = true,
    factionSafezoneTemplates = {
        { id = 'trader_sandy',        offset = vector3(4.0, 3.0, 0.0),  heading = 200.0 },
        { id = 'quartermaster_sandy', offset = vector3(-4.0, 3.0, 0.0), heading = 160.0 },
    },

    -- Who may open /traderdebug. Admin aces only ('command' is not an admin ace); bs_admin's IsAdmin also counts. Every write is re-checked server-side, this only decides whether the menu opens.
    debugAces = { 'bs.admin', 'bs.superadmin' },

    -- Who may use teleport-to-NPC in /traderdebug. Deliberately narrower than `debugAces`, since moving a player is more than an edit. See isAdmin() in sv_npcs.lua.
    teleportAces = { 'bs.admin', 'bs.superadmin' },

    -- Diagnostic switch, off on purpose. Repeated access violations inside the game's ped/task code point at TaskStartScenarioInPlace (some scenarios probe surfaces or attach props). With this false no scenarios start; see client/cl_peds.lua.
    useScenarios = false,
}

-- Zone anchoring

-- Informal places that are not in bs_zombies Zones.Safe but anchor traders.
Traders.ExtraZones = {
    { id = 'sandy_camp',                label = 'Sandy Camp',      coords = vector3(1855.0, 3683.0, 34.3) },
    { id = 'post_apocalyptic_airbase',  label = 'Grand Senora Airbase', coords = vector3(1992.0, 3057.4, 46.3) },
}

-- Vanilla factions a trader can be locked to (ids of bs_factions).
Traders.Factions = { 'military', 'rebels', 'civilians', 'bikers' }

-- Item categories every trader starts with (labels come from the locales: ui.cat_<id>).
Traders.DefaultCategories = { 'weapons', 'ammo', 'medical', 'food', 'tools', 'materials', 'clothing', 'misc' }

-- All usable zones: Zones.Safe (also filled with faction_* entries) plus the extras above.
-- A bare faction id ('civilians') matches 'faction_civilians' too.
function Traders.ListZones()
    local out, seen = {}, {}
    for _, z in ipairs((Zones and Zones.Safe) or {}) do
        if z.id and z.coords and not seen[z.id] then
            seen[z.id] = true
            out[#out + 1] = { id = z.id, label = z.label or z.id, coords = z.coords }
        end
    end
    -- Faction zones may not be synced into this state yet: read the config list too.
    for _, f in ipairs((Zones and Zones.FactionSafe) or {}) do
        local id = 'faction_' .. f.id
        if f.kind == 'safezone' and not seen[id] and f.coords then
            seen[id] = true
            out[#out + 1] = { id = id, label = f.label or id, coords = f.coords }
        end
    end
    for _, z in ipairs(Traders.ExtraZones) do
        if not seen[z.id] then seen[z.id] = true; out[#out + 1] = z end
    end
    return out
end

local function findZone(zoneId)
    local list = Traders.ListZones()
    for _, z in ipairs(list) do if z.id == zoneId then return z end end
    for _, z in ipairs(list) do if z.id == 'faction_' .. tostring(zoneId) then return z end end
    return nil
end
Traders.FindZone = findZone

-- Absolute coordinate for a zone-relative NPC. An unknown zone falls back to an obviously wrong height instead of erroring, so one typo cannot take down every NPC. The warning prints once per id.
local warned = {}
local function zoneCoords(zoneId, offset)
    offset = offset or vector3(0.0, 0.0, 0.0)

    local zone = findZone(zoneId)
    if zone then return zone.coords + offset end

    if not warned[zoneId] then
        warned[zoneId] = true
        print(('^1[bs_traders]^7 unknown safe zone "%s" - is bs_zombies running, and does '
            .. 'Zones.Safe or Traders.ExtraZones define it? Placed at a visibly-wrong height.')
            :format(tostring(zoneId)))
    end
    return vector3(offset.x, offset.y, 500.0)
end

--------------------------------------------------------------------------------
-- NPCs
--------------------------------------------------------------------------------

-- Sandy Camp and Paleto offsets are first guesses; correct them with /traderdebug. The faction zones and the airbase were placed from the map props (see _notes/TRADER_PLACEMENT.md).
Traders.Traders = {

    ---------------------------------------------------------------- Sandy Camp
    trader_sandy = {
        -- `clothing` is a service, not a role: this NPC sells tins and also offers 'Change Clothes' (see the flag in sv_registry.lua).
        label = 'Camp Trader', role = 'trader', clothing = true,
        zone = 'sandy_camp', offset = vector3(-6.0, 4.0, 0.0), heading = 30.0,
        model = 'a_m_m_farmer_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'fish_bass', price = 16 },
            { item = 'fish_catfish', price = 28 },
            { item = 'fish_trout', price = 55 },
            { item = 'fish_salmon', price = 110 },
            { item = 'fish_mackerel', price = 18 },
            { item = 'raw_fish', price = 10 },
            { item = 'big_fish', price = 100 },

            -- zombie_teeth buy price is 80% of catalogue value (10), in line with the rest of the file (about Economy.Settings.sellRateMultiplier).
            { item = 'zombie_teeth',    price = 5 },
            { item = 'scrap_metal',     price = 3 },
            { item = 'cloth',           price = 2 },
            { item = 'wood_plank',      price = 2 },
            { item = 'copper',          price = 5 },
            { item = 'electrical_wire', price = 15 },
            -- hunting hides
            { item = 'deer_hide',       price = 18 },
            { item = 'boar_hide',       price = 15 },
            { item = 'rabbit_pelt',     price = 7  },
            { item = 'coyote_pelt',     price = 13 },
            { item = 'mtlion_pelt',     price = 42 },
        },
        -- Sell prices keep roughly a 1.4-1.5x markup over catalogue value (antiseptic: value 60).
        sells = {
            { item = 'radio', price = 220, stock = 8 },
            { item = 'radio_advanced', price = 800, stock = 3 },
            { item = 'portable_antenna', price = 1100, stock = 2 },
            { item = 'fishing_rod', price = 120, stock = 8 },
            { item = 'fish_bait', price = 3, stock = 200 },
            { item = 'water_bottle',  price = 12,  stock = 40 },
            { item = 'canned_food',   price = 18,  stock = 40 },
            { item = 'bandage',       price = 25,  stock = 25 },
            { item = 'antiseptic',    price = 90,  stock = 20 },
            { item = 'toolbox',       price = 220, stock = 4  },
            { item = 'hunting_knife', price = 135, stock = 6  },
            -- building supplies (bs_building)
            { item = 'wood_plank',    price = 8,   stock = 60 },
            { item = 'nails',         price = 3,   stock = 200 },
            { item = 'hammer',        price = 105, stock = 3  },
        },
    },

    quartermaster_sandy = {
        label = 'Quartermaster', role = 'quest',
        zone = 'sandy_camp', offset = vector3(2.0, 9.0, 0.0), heading = 200.0,
        model = 'ig_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_teeth_50', 'headshots_sandy' },
    },

    -------------------------------------------------------------- Paleto Refuge
    trader_paleto = {
        label = 'Refuge Trader', role = 'trader',
        zone = 'paleto', offset = vector3(-5.0, -5.0, 0.0), heading = 160.0,
        model = 'a_f_m_trampbeac_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'fish_bass', price = 16 },
            { item = 'fish_catfish', price = 28 },
            { item = 'fish_trout', price = 55 },
            { item = 'fish_salmon', price = 110 },
            { item = 'fish_mackerel', price = 18 },
            { item = 'raw_fish', price = 10 },
            { item = 'big_fish', price = 100 },

            { item = 'wood_plank',  price = 2 },
            { item = 'scrap_metal', price = 3 },
            { item = 'cloth',       price = 2 },
            { item = 'copper',      price = 6 },
            -- hunting hides
            { item = 'deer_hide',       price = 18 },
            { item = 'boar_hide',       price = 15 },
            { item = 'rabbit_pelt',     price = 7  },
            { item = 'coyote_pelt',     price = 13 },
            { item = 'mtlion_pelt',     price = 42 },
        },
        -- Same ~1.4x markup over catalogue value (antibiotics 220, lockpick 140).
        sells = {
            { item = 'fishing_rod', price = 120, stock = 8 },
            { item = 'fish_bait', price = 3, stock = 200 },
            { item = 'water_bottle', price = 12,  stock = 40 },
            { item = 'canned_food',  price = 18,  stock = 40 },
            { item = 'antibiotics',  price = 300, stock = 12 },
            { item = 'lockpick',     price = 200, stock = 10 },
            { item = 'shovel',       price = 210, stock = 5  },
            { item = 'pack_civilian',   price = 170, stock = 4  },
            { item = 'pack_hiking',  price = 360, stock = 2  },
        },
    },

    ranger_paleto = {
        label = 'Refuge Ranger', role = 'quest',
        zone = 'paleto', offset = vector3(6.0, 3.0, 0.0), heading = 80.0,
        model = 's_m_y_ranger_01', scenario = 'WORLD_HUMAN_GUARD_STAND',

        -- Gives Paleto its first kill mission (perimeter_sweep_paleto, below).
        missions = { 'gather_scrap_30', 'gather_wood_20', 'perimeter_sweep_paleto' },
    },

    -- Grand Senora Airbase: one ped with role 'both', the base quartermaster handles armoury and missions.
    armorer_airbase = {
        label = 'Armorer', role = 'both',
        -- Stands next to the armoury crate stacks north of the yard (ch_prop_ch_crate_01a / h4_prop_h4_crates_full_01a). Ymap-derived, absolute (1991.36, 3075.82, 46.99), check in game.
        zone = 'post_apocalyptic_airbase', offset = vector3(-0.64, 18.42, 0.69), heading = 185.9,
        model = 's_m_y_ranger_01', scenario = 'WORLD_HUMAN_GUARD_STAND',

        -- Ammo sells above catalogue value (ammo_pistol/shotgun/rifle are 4/7/8) at the usual ~1.4-1.5x markup; buy prices are raised to keep a sane spread.
        buys = {
            { item = 'advanced_rifle', price = 1440 },
            { item = 'ap_pistol', price = 607 },
            { item = 'assault_rifle', price = 1170 },
            { item = 'assault_rifle_mk2', price = 1935 },
            { item = 'assault_shotgun', price = 1620 },
            { item = 'assault_smg', price = 990 },
            { item = 'bullpup_rifle', price = 1305 },
            { item = 'bullpup_rifle_mk2', price = 1890 },
            { item = 'bullpup_shotgun', price = 1282 },
            { item = 'carbine', price = 1080 },
            { item = 'carbine_mk2', price = 2025 },
            { item = 'combat_mg', price = 2520 },
            { item = 'combat_mg_mk2', price = 3060 },
            { item = 'combat_pdw', price = 1125 },
            { item = 'combat_pistol', price = 382 },
            { item = 'compact_rifle', price = 1057 },
            { item = 'gusenberg', price = 1170 },
            { item = 'heavy_pistol', price = 540 },
            { item = 'heavy_shotgun', price = 1485 },
            { item = 'heavy_sniper', price = 2565 },
            { item = 'heavy_sniper_mk2', price = 3330 },
            { item = 'hunting_rifle', price = 945 },
            { item = 'machine_pistol', price = 517 },
            { item = 'marksman', price = 1305 },
            { item = 'marksman_mk2', price = 2160 },
            { item = 'mg', price = 2070 },
            { item = 'micro_smg', price = 607 },
            { item = 'military_rifle', price = 1845 },
            { item = 'musket', price = 495 },
            { item = 'pipe_pistol', price = 144 },
            { item = 'pipe_shotgun', price = 234 },
            { item = 'pistol', price = 292 },
            { item = 'pistol_50', price = 742 },
            { item = 'pistol_mk2', price = 810 },
            { item = 'pump_shotgun', price = 562 },
            { item = 'pump_shotgun_mk2', price = 1282 },
            { item = 'revolver', price = 405 },
            { item = 'revolver_mk2', price = 1035 },
            { item = 'sawn_off', price = 495 },
            { item = 'smg', price = 630 },
            { item = 'smg_mk2', price = 1395 },
            { item = 'sns_pistol_mk2', price = 562 },
            { item = 'special_carbine', price = 1530 },
            { item = 'special_carbine_mk2', price = 2115 },
            { item = 'vintage_pistol', price = 342 },
            { item = 'ammo_magnum', price = 5 },
            { item = 'gun_parts', price = 45 },
            { item = 'ammo_pistol',  price = 2 },
            { item = 'ammo_shotgun', price = 3 },
            { item = 'ammo_rifle',   price = 4 },
        },
        -- The only vendor that sells firearms. Priced and stocked as the expensive, limited option next to finding or crafting one.
        sells = {
            { item = 'advanced_rifle', price = 4800, stock = 2 },
            { item = 'ap_pistol', price = 2025, stock = 3 },
            { item = 'assault_rifle', price = 3900, stock = 2 },
            { item = 'assault_rifle_mk2', price = 6450, stock = 1 },
            { item = 'assault_shotgun', price = 5400, stock = 2 },
            { item = 'assault_smg', price = 3300, stock = 2 },
            { item = 'bullpup_rifle', price = 4350, stock = 2 },
            { item = 'bullpup_rifle_mk2', price = 6300, stock = 1 },
            { item = 'bullpup_shotgun', price = 4275, stock = 2 },
            { item = 'carbine_mk2', price = 6750, stock = 1 },
            { item = 'combat_mg', price = 8400, stock = 1 },
            { item = 'combat_mg_mk2', price = 10200, stock = 1 },
            { item = 'combat_pdw', price = 3750, stock = 2 },
            { item = 'compact_rifle', price = 3525, stock = 2 },
            { item = 'gusenberg', price = 3900, stock = 2 },
            { item = 'heavy_pistol', price = 1800, stock = 3 },
            { item = 'heavy_shotgun', price = 4950, stock = 2 },
            { item = 'heavy_sniper', price = 8550, stock = 1 },
            { item = 'heavy_sniper_mk2', price = 11100, stock = 1 },
            { item = 'hunting_rifle', price = 3150, stock = 2 },
            { item = 'machine_pistol', price = 1725, stock = 3 },
            { item = 'marksman', price = 4350, stock = 1 },
            { item = 'marksman_mk2', price = 7200, stock = 1 },
            { item = 'mg', price = 6900, stock = 1 },
            { item = 'micro_smg', price = 2025, stock = 2 },
            { item = 'military_rifle', price = 6150, stock = 1 },
            { item = 'musket', price = 1650, stock = 2 },
            { item = 'pipe_pistol', price = 480, stock = 3 },
            { item = 'pipe_shotgun', price = 780, stock = 2 },
            { item = 'pistol_50', price = 2475, stock = 3 },
            { item = 'pistol_mk2', price = 2700, stock = 1 },
            { item = 'pump_shotgun_mk2', price = 4275, stock = 1 },
            { item = 'revolver', price = 1350, stock = 3 },
            { item = 'revolver_mk2', price = 3450, stock = 1 },
            { item = 'sawn_off', price = 1650, stock = 2 },
            { item = 'smg_mk2', price = 4650, stock = 1 },
            { item = 'sns_pistol_mk2', price = 1875, stock = 1 },
            { item = 'special_carbine', price = 5100, stock = 2 },
            { item = 'special_carbine_mk2', price = 7050, stock = 1 },
            { item = 'vintage_pistol', price = 1140, stock = 3 },
            { item = 'ammo_magnum', price = 13, stock = 100 },
            { item = 'att_muzzle_brake', price = 480, stock = 3 },
            { item = 'att_reflex', price = 440, stock = 3 },
            { item = 'att_scope_long', price = 930, stock = 2 },
            { item = 'att_laser', price = 320, stock = 3 },
            { item = 'gun_parts', price = 180, stock = 15 },
            { item = 'ammo_pistol',   price = 6,    stock = 200 },
            { item = 'ammo_shotgun',  price = 10,   stock = 120 },
            { item = 'ammo_rifle',    price = 11,   stock = 100 },
            { item = 'armour_plate',  price = 850,  stock = 2   },
            { item = 'pack_survival',    price = 730,  stock = 2   },
            { item = 'vest_tactical', price = 530,  stock = 2   },
            { item = 'booster_focus',  price = 300,  stock = 3   },
            { item = 'booster_decoy',  price = 240,  stock = 3   },
            { item = 'combat_pistol', price = 1150, stock = 3   },
            { item = 'pistol', price = 950, stock = 3 },
            { item = 'smg', price = 2100, stock = 2 },
            { item = 'carbine', price = 3600, stock = 1 },
            { item = 'att_suppressor', price = 630, stock = 2 },
            { item = 'att_scope', price = 570, stock = 3 },
            { item = 'att_grip', price = 290, stock = 3 },
            { item = 'att_flashlight', price = 240, stock = 4 },
            { item = 'att_extmag', price = 360, stock = 4 },
            { item = 'pump_shotgun',  price = 1650, stock = 2   },
        },

        missions = { 'kill_brutes_10' },
    },

    medic_airbase = {
        label = 'Base Medic', role = 'trader',
        -- Stands next to the gazebo with clubhouse chairs and water cooler (prop_gazebo_02) by the yard. Ymap-derived, absolute (1997.55, 3060.33, 47.05).
        zone = 'post_apocalyptic_airbase', offset = vector3(5.55, 2.93, 0.75), heading = 94.1,
        model = 's_f_y_ranger_01', scenario = 'WORLD_HUMAN_CLIPBOARD',

        buys = {
            { item = 'scrap_metal', price = 3 },
            { item = 'copper',      price = 5 },
            { item = 'cloth',       price = 2 },
        },
        -- Same ~1.4x markup over catalogue value for medkit (120), antiseptic and antibiotics.
        sells = {
            { item = 'bandage',      price = 25,  stock = 30 },
            { item = 'medkit',       price = 170, stock = 12 },
            { item = 'antiseptic',   price = 90,  stock = 20 },
            { item = 'antibiotics',  price = 300, stock = 15 },
            { item = 'rag',          price = 10,  stock = 40 },
            { item = 'tourniquet',   price = 100, stock = 10 },
            { item = 'splint',       price = 65,  stock = 10 },
            { item = 'saline',       price = 130, stock = 8 },
            { item = 'painkillers',  price = 110, stock = 15 },
            { item = 'blood_bag',    price = 380, stock = 4 },
            { item = 'transfusion_kit', price = 450, stock = 2 },
            { item = 'surgical_kit', price = 650, stock = 2 },
            { item = 'antiviral',    price = 900, stock = 1 },
            { item = 'booster_regen',  price = 320, stock = 3 },
            { item = 'booster_medic',  price = 520, stock = 1 },
        },
    },

    -- The Tailor: role = 'clothing' is a wardrobe, not a shop. It sells nothing and gives no work; it changes the character's look for a fee and stores it in the outfit metadata bs_core keeps. See config_wardrobe.lua. `buys` and `sells` are absent on purpose.
    tailor_sandy = {
        label = 'The Tailor', role = 'clothing',
        zone = 'sandy_camp', offset = vector3(-11.0, 1.0, 0.0), heading = 75.0,
        model = 'a_f_m_trampbeac_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },
    -- add more tailors so every safe zone can dress you
    tailor_paleto = {
        label = 'The Tailor', role = 'clothing',
        zone = 'paleto', offset = vector3(-8.0, 6.0, 0.0), heading = 120.0,
        model = 'a_f_m_trampbeac_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },
    tailor_airbase = {
        label = 'The Tailor', role = 'clothing',
        -- Stands next to the bench and water vending machine (prop_bench_01a / prop_vend_water_01) south of the yard. Ymap-derived, absolute (1994.48, 3053.17, 47.21).
        zone = 'post_apocalyptic_airbase', offset = vector3(2.48, -4.23, 0.91), heading = 12.2,
        model = 'a_f_m_trampbeac_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },

    -- The Fence: black-market dealer at Sandy Camp (the informal zone). Buys vehicle/electrical salvage at the standard 0.45x trade-in rate. Sells attachments and fuel cans in low stock at prices well above catalogue value.
    fence_sandy = {
        label = 'The Fence', role = 'trader',
        zone = 'sandy_camp', offset = vector3(10.0, -6.0, 0.0), heading = 340.0,
        model = 'g_m_y_lost_01', scenario = 'WORLD_HUMAN_LEANING',

        buys = {
            { item = 'battery',         price = 145 },
            { item = 'engine_part',     price = 215 },
            { item = 'repair_kit',      price = 115 },
            { item = 'electrical_wire', price = 15  },
            { item = 'spark_plug',      price = 65  },
            { item = 'fuel_tank',       price = 160 },
            { item = 'mtlion_pelt',     price = 50  },
        },
        sells = {
            { item = 'spark_plug',     price = 340, stock = 4 },
            { item = 'battery',        price = 720, stock = 2 },
            { item = 'fuel_tank',      price = 820, stock = 2 },
            { item = 'lockpick',       price = 310, stock = 5 },
            { item = 'att_grip',       price = 280, stock = 4 },
            { item = 'att_flashlight', price = 230, stock = 4 },
            { item = 'att_extmag',     price = 340, stock = 3 },
            { item = 'att_scope',      price = 540, stock = 2 },
            { item = 'att_suppressor', price = 600, stock = 2 },
            { item = 'fuel_can',       price = 180, stock = 6 },
            -- bs_drugs: normal quality, black-market prices.
            { item = 'cigarette',      price = 35,  stock = 40 },
            { item = 'matches',        price = 20,  stock = 20 },
            { item = 'lighter',        price = 90,  stock = 6 },
            { item = 'weed',           price = 220, stock = 8 },
            { item = 'amphetamine',    price = 420, stock = 5 },
            { item = 'morphine',       price = 480, stock = 5 },
            { item = 'cocaine',        price = 520, stock = 4 },
        },
    },

    -- bs_drugs: the only source of rehab kits. Quest-only, one job at a time.
    rehab_doc_paleto = {
        label = 'Doc Harlan', role = 'quest',
        zone = 'paleto', offset = vector3(4.0, -9.0, 0.0), heading = 90.0,
        model = 's_m_m_doctor_01', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'rehab_fetch_meds', 'rehab_clear_nest' },
    },

    ------------------------------------------------ Vanilla faction safezones and outposts
    -- Three NPCs per zone (trading, missions, tailor), locked to that faction: outsiders can trade at the
    -- surcharge, only members get missions and the wardrobe. Spots come from the props of The Apocalypse
    -- Project map around each zone (see _notes/TRADER_PLACEMENT.md); offsets are from the zone centre in
    -- bs_zombies Zones.FactionSafe, so they move with it. Ped z is ground + 1 (cl_peds spawns at z - 1).
    -- The Bikers Outpost is the Grand Senora Airbase: armorer_airbase, medic_airbase and tailor_airbase serve it.

    -- Military
    military_trader = {
        -- Stands next to the stack of rifle crates (gr_prop_gr_crates_rifles_04a) by the north-east hangar. Ymap-derived, absolute (1753.55, 3273.25, 41.16).
        label = 'Military Trader', role = 'trader', faction = 'military',
        zone = 'military', offset = vector3(9.55, 8.25, -0.09), heading = 130.8,
        model = 's_m_y_marine_03', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'scrap_metal',     price = 3 },
            { item = 'copper',          price = 5 },
            { item = 'electrical_wire', price = 15 },
            { item = 'ammo_pistol',     price = 2 },
            { item = 'ammo_rifle',      price = 4 },
        },
        sells = {
            { item = 'water_bottle', price = 12,  stock = 40 },
            { item = 'canned_food',  price = 18,  stock = 40 },
            { item = 'bandage',      price = 25,  stock = 30 },
            { item = 'medkit',       price = 170, stock = 8  },
            { item = 'ammo_pistol',  price = 6,   stock = 150 },
            { item = 'ammo_rifle',   price = 11,  stock = 80 },
            { item = 'vest_tactical', price = 530, stock = 2 },
        },
    },
    military_missions = {
        -- Stands next to the supply rack with ammo boxes (imp_prop_impexp_rack_02a) inside the north gate. Ymap-derived, absolute (1744.70, 3298.14, 41.22).
        label = 'Military Quartermaster', role = 'quest', faction = 'military',
        zone = 'military', offset = vector3(0.70, 33.14, -0.03), heading = 178.8,
        model = 's_m_m_marine_01', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_scrap_30', 'gather_wood_20', 'gather_teeth_50' },
    },
    military_tailor = {
        -- Stands next to the ammo locker and gun case (bkr_prop_gunlocker_ammo_01a) on the west side. Ymap-derived, absolute (1719.54, 3286.03, 41.20), check in game.
        label = 'The Tailor', role = 'clothing', faction = 'military',
        zone = 'military', offset = vector3(-24.46, 21.03, -0.05), heading = 229.3,
        model = 's_f_y_ranger_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },

    -- Rebels
    rebels_trader = {
        -- Stands next to the fruit stall and table (prop_fruit_stand_01 / prop_table_08) in the middle of the camp market. Ymap-derived, absolute (1012.33, -320.18, 67.22).
        label = 'Rebels Trader', role = 'trader', faction = 'rebels',
        zone = 'rebels', offset = vector3(-2.67, -2.18, 0.22), heading = 309.2,
        model = 'g_m_y_salvagoon_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'scrap_metal', price = 3 },
            { item = 'cloth',       price = 2 },
            { item = 'wood_plank',  price = 2 },
            { item = 'copper',      price = 5 },
            { item = 'deer_hide',   price = 18 },
            { item = 'boar_hide',   price = 15 },
        },
        sells = {
            { item = 'water_bottle',  price = 12,  stock = 40 },
            { item = 'canned_food',   price = 18,  stock = 40 },
            { item = 'bandage',       price = 25,  stock = 25 },
            { item = 'lockpick',      price = 200, stock = 8 },
            { item = 'hunting_knife', price = 135, stock = 5 },
            { item = 'pack_civilian',    price = 170, stock = 4 },
        },
    },
    rebels_missions = {
        -- Stands next to the parasol table (prop_table_para_comb_05) by the couches. Ymap-derived, absolute (1016.11, -310.59, 67.72).
        label = 'Rebels Quartermaster', role = 'quest', faction = 'rebels',
        zone = 'rebels', offset = vector3(1.11, 7.41, 0.72), heading = 171.5,
        model = 'a_m_m_hillbilly_01', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_scrap_30', 'gather_wood_20', 'gather_teeth_50' },
    },
    rebels_tailor = {
        -- Stands next to the cloth market tents (prop_skid_tent_cloth). Ymap-derived, absolute (1026.91, -314.53, 67.77).
        label = 'The Tailor', role = 'clothing', faction = 'rebels',
        zone = 'rebels', offset = vector3(11.91, 3.47, 0.77), heading = 106.2,
        model = 'a_f_y_hippie_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },

    -- Rebels Outpost
    rebels_outpost_trader = {
        -- Stands next to the camp kitchen: fridge, fruit crates and BBQs (prop_trailr_fridge / prop_fruit_plas_crate_01). Ymap-derived, absolute (-1141.59, 4909.81, 220.97), check in game.
        label = 'Rebels Outpost Trader', role = 'trader', faction = 'rebels',
        zone = 'rebels_outpost', offset = vector3(-34.59, -10.19, 3.97), heading = 286.4,
        model = 'a_m_m_hillbilly_02', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'wood_plank',  price = 2 },
            { item = 'scrap_metal', price = 3 },
            { item = 'deer_hide',   price = 18 },
            { item = 'rabbit_pelt', price = 7 },
            { item = 'coyote_pelt', price = 13 },
        },
        sells = {
            { item = 'water_bottle', price = 12,  stock = 30 },
            { item = 'canned_food',  price = 18,  stock = 30 },
            { item = 'bandage',      price = 25,  stock = 20 },
            { item = 'antibiotics',  price = 300, stock = 6 },
            { item = 'shovel',       price = 210, stock = 3 },
        },
    },
    rebels_outpost_missions = {
        -- Stands next to the gunsmith workbench and tool chests (gr_prop_gr_gunsmithsupl_02a). Ymap-derived, absolute (-1099.11, 4946.36, 218.36).
        label = 'Rebels Outpost Quartermaster', role = 'quest', faction = 'rebels',
        zone = 'rebels_outpost', offset = vector3(7.89, 26.36, 1.36), heading = 163.3,
        model = 'g_m_y_salvagoon_02', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_scrap_30', 'gather_wood_20', 'gather_teeth_50' },
    },
    rebels_outpost_tailor = {
        -- Stands next to the camp bed (bkr_prop_biker_campbed_01) south of the clearing. Ymap-derived, absolute (-1116.83, 4909.10, 218.64), check in game.
        label = 'The Tailor', role = 'clothing', faction = 'rebels',
        zone = 'rebels_outpost', offset = vector3(-9.83, -10.90, 1.64), heading = 318.0,
        model = 'a_f_m_trampbeac_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },

    -- Civilians
    civilians_trader = {
        -- Stands next to the fruit stall and crates (prop_fruitstand_01 / prop_crate_10a) in the market corner. Ymap-derived, absolute (-252.76, -2067.61, 27.62).
        label = 'Civilians Trader', role = 'trader', faction = 'civilians',
        zone = 'civilians', offset = vector3(13.24, -18.61, 0.62), heading = 35.4,
        model = 'a_m_m_farmer_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'scrap_metal', price = 3 },
            { item = 'cloth',       price = 2 },
            { item = 'wood_plank',  price = 2 },
            { item = 'copper',      price = 5 },
        },
        sells = {
            { item = 'water_bottle', price = 12,  stock = 50 },
            { item = 'canned_food',  price = 18,  stock = 50 },
            { item = 'bandage',      price = 25,  stock = 25 },
            { item = 'antiseptic',   price = 90,  stock = 15 },
            { item = 'toolbox',      price = 220, stock = 3 },
            { item = 'wood_plank',   price = 8,   stock = 60 },
            { item = 'nails',        price = 3,   stock = 200 },
            { item = 'hammer',       price = 105, stock = 3 },
        },
    },
    civilians_missions = {
        -- Stands next to the desk with notebook and chair (prop_table_08) on the west side. Ymap-derived, absolute (-269.63, -2064.16, 27.62).
        label = 'Civilians Quartermaster', role = 'quest', faction = 'civilians',
        zone = 'civilians', offset = vector3(-3.63, -15.16, 0.62), heading = 346.5,
        model = 'a_m_y_hipster_01', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_scrap_30', 'gather_wood_20', 'gather_teeth_50' },
    },
    civilians_tailor = {
        -- Stands next to the canopy tents by the fire pits (prop_skid_tent_03). Ymap-derived, absolute (-228.17, -2067.08, 27.62), check in game.
        label = 'The Tailor', role = 'clothing', faction = 'civilians',
        zone = 'civilians', offset = vector3(37.83, -18.08, 0.62), heading = 64.5,
        model = 'a_f_y_hippie_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },

    -- Bikers
    bikers_trader = {
        -- Stands next to the wheel rack and tool boxes in the workshop (imp_prop_impexp_hub_rack_01a). Ymap-derived, absolute (961.12, -208.64, 73.03).
        label = 'Bikers Trader', role = 'trader', faction = 'bikers',
        zone = 'bikers', offset = vector3(3.88, -2.47, 0.98), heading = 57.5,
        model = 'g_m_y_lost_02', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
            { item = 'scrap_metal', price = 3 },
            { item = 'battery',     price = 145 },
            { item = 'engine_part', price = 215 },
            { item = 'spark_plug',  price = 65 },
        },
        sells = {
            { item = 'water_bottle', price = 12,  stock = 30 },
            { item = 'canned_food',  price = 18,  stock = 30 },
            { item = 'bandage',      price = 25,  stock = 20 },
            { item = 'lockpick',     price = 200, stock = 6 },
            { item = 'fuel_can',     price = 180, stock = 6 },
            { item = 'spark_plug',   price = 340, stock = 3 },
        },
    },
    bikers_missions = {
        -- Stands next to the sandbag post (prop_mb_sandblock_01) inside the main gate. Ymap-derived, absolute (965.11, -186.39, 72.64).
        label = 'Bikers Quartermaster', role = 'quest', faction = 'bikers',
        zone = 'bikers', offset = vector3(7.87, 19.78, 0.59), heading = 158.3,
        model = 'g_m_y_lost_03', scenario = 'WORLD_HUMAN_CLIPBOARD',

        missions = { 'kill_walkers_50', 'gather_scrap_30', 'gather_wood_20', 'gather_teeth_50' },
    },
    bikers_tailor = {
        -- Stands next to the camp beds in the bunk corner (gr_prop_gr_campbed_01). Ymap-derived, absolute (954.53, -197.92, 73.18), check in game.
        label = 'The Tailor', role = 'clothing', faction = 'bikers',
        zone = 'bikers', offset = vector3(-2.71, 8.25, 1.13), heading = 198.2,
        model = 'g_f_y_lost_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    },
}

--------------------------------------------------------------------------------
-- Missions
--------------------------------------------------------------------------------

-- Two mission kinds.
-- kind = 'kill': progress is a counter, credited by server/sv_npcs.lua on `bs:hook:player:action` (see bs_core/server/sv_rewards.lua).
-- kind = 'gather': no progress tracked; turn-in checks the player holds `target` of `item`, consumes it if consume is true, and pays out (see server/sv_npcs.lua).
Traders.Missions = {

    kill_walkers_50 = {
        label = 'Thin the Herd', giver = 'quartermaster_sandy',
        kind = 'kill', filter = { 'zombie_kill', 'zombie_kill_headshot' }, target = 50,
        desc = 'Fifty of the ordinary ones. The Quartermaster is not fussy about how.',
        reward = { xp = 400, money = 250 }, cooldown = 3600,
    },

    gather_teeth_50 = {
        label = 'Trophy Collector', giver = 'quartermaster_sandy',
        kind = 'gather', item = 'zombie_teeth', target = 50, consume = true,
        desc = 'Bring fifty zombie teeth as proof of the hunt.',
        reward = { xp = 250, money = 400 }, cooldown = 1800,
    },

    gather_scrap_30 = {
        label = 'Scrap Drive', giver = 'ranger_paleto',
        kind = 'gather', item = 'scrap_metal', target = 30, consume = true,
        desc = 'Thirty scrap metal for the refuge\'s repairs.',
        reward = { xp = 120, money = 150 }, cooldown = 900,
    },

    gather_wood_20 = {
        label = 'Timber Run', giver = 'ranger_paleto',
        kind = 'gather', item = 'wood_plank', target = 20, consume = true,
        desc = 'Twenty planks to shore up the refuge fence.',
        reward = { xp = 100, money = 110 }, cooldown = 900,
    },

    kill_brutes_10 = {
        label = 'Big Game', giver = 'armorer_airbase',
        kind = 'kill', filter = { 'zombie_kill_brute' }, target = 10,
        desc = 'Ten brutes. Bring a real gun.',
        reward = { xp = 600, money = 500 }, cooldown = 5400,
    },

    -- The `filter` lists only use the three action ids bs_core actually fires (see bs_core/server/sv_rewards.lua and config/config.lua). Do not invent others, nothing would trigger them.
    headshots_sandy = {
        label = 'Precision Work', giver = 'quartermaster_sandy',
        kind = 'kill', filter = { 'zombie_kill_headshot' }, target = 25,
        desc = 'Twenty-five clean headshots. No credit for anything that took two hits.',
        reward = { xp = 300, money = 300 }, cooldown = 2700,
    },

    -- The refuge's first kill mission.
    perimeter_sweep_paleto = {
        label = 'Perimeter Sweep', giver = 'ranger_paleto',
        kind = 'kill', filter = { 'zombie_kill', 'zombie_kill_headshot' }, target = 30,
        desc = 'Thirty walkers off the refuge\'s doorstep, however you put them down.',
        reward = { xp = 220, money = 260 }, cooldown = 2400,
    },

    -- bs_drugs rehab jobs: same group = one active at a time + shared cooldown.
    rehab_fetch_meds = {
        label = 'Clean Supplies', giver = 'rehab_doc_paleto', group = 'rehab',
        kind = 'gather', item = 'antibiotics', target = 4, consume = true,
        desc = 'Four courses of antibiotics for the sick ward. He\'ll get you clean in return.',
        reward = { xp = 300, money = 0, items = { { item = 'rehab_kit', amount = 1 } } }, cooldown = 7200,
    },
    rehab_clear_nest = {
        label = 'Clear the Road', giver = 'rehab_doc_paleto', group = 'rehab',
        kind = 'kill', filter = { 'zombie_kill', 'zombie_kill_headshot' }, target = 60,
        desc = 'Sixty walkers off the supply road. Then we talk about your habit.',
        reward = { xp = 350, money = 0, items = { { item = 'rehab_kit', amount = 1 } } }, cooldown = 7200,
    },
}

Traders.ZoneCoords = zoneCoords
