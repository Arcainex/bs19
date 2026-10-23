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

-- Two NPCs per safe zone, plus a black-market fence at Sandy Camp (fence_sandy), the one informal zone. Offsets are first guesses; correct them with /traderdebug.
Traders.Traders = {

    ---------------------------------------------------------------- Sandy Camp
    trader_sandy = {
        -- `clothing` is a service, not a role: this NPC sells tins and also offers 'Change Clothes' (see the flag in sv_registry.lua).
        label = 'Camp Trader', role = 'trader', clothing = true,
        zone = 'sandy_camp', offset = vector3(-6.0, 4.0, 0.0), heading = 30.0,
        model = 'a_m_m_farmer_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',

        buys = {
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
            { item = 'water_bottle', price = 12,  stock = 40 },
            { item = 'canned_food',  price = 18,  stock = 40 },
            { item = 'antibiotics',  price = 300, stock = 12 },
            { item = 'lockpick',     price = 200, stock = 10 },
            { item = 'shovel',       price = 210, stock = 5  },
            { item = 'pack_small',   price = 170, stock = 4  },
            { item = 'pack_medium',  price = 360, stock = 2  },
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
        zone = 'post_apocalyptic_airbase', offset = vector3(-4.0, 6.0, 0.0), heading = 110.0,
        model = 's_m_y_ranger_01', scenario = 'WORLD_HUMAN_GUARD_STAND',

        -- Ammo sells above catalogue value (ammo_pistol/shotgun/rifle are 4/7/8) at the usual ~1.4-1.5x markup; buy prices are raised to keep a sane spread.
        buys = {
            { item = 'ammo_pistol',  price = 2 },
            { item = 'ammo_shotgun', price = 3 },
            { item = 'ammo_rifle',   price = 4 },
        },
        -- The only vendor that sells firearms. Priced and stocked as the expensive, limited option next to finding or crafting one.
        sells = {
            { item = 'ammo_pistol',   price = 6,    stock = 200 },
            { item = 'ammo_shotgun',  price = 10,   stock = 120 },
            { item = 'ammo_rifle',    price = 11,   stock = 100 },
            { item = 'armour_plate',  price = 850,  stock = 2   },
            { item = 'pack_large',    price = 730,  stock = 2   },
            { item = 'vest_tactical', price = 530,  stock = 2   },
            { item = 'booster_focus',  price = 300,  stock = 3   },
            { item = 'booster_decoy',  price = 240,  stock = 3   },
            { item = 'combat_pistol', price = 1150, stock = 3   },
            { item = 'pump_shotgun',  price = 1650, stock = 2   },
        },

        missions = { 'kill_brutes_10' },
    },

    medic_airbase = {
        label = 'Base Medic', role = 'trader',
        zone = 'post_apocalyptic_airbase', offset = vector3(5.0, -3.0, 0.0), heading = 250.0,
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
        zone = 'post_apocalyptic_airbase', offset = vector3(-8.0, -6.0, 0.0), heading = 60.0,
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
