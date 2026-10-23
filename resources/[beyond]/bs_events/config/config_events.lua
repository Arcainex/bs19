-- bs_events - scheduled world events. Times use the server's local clock (os.date).
-- Scalars are also editable live from the F1 console (category "World Events")

Events = {}

Events.Settings = {
    enabled       = true,    -- master switch for the scheduler (admin commands still work)
    chat          = true,    -- also post announcements in chat
    radioSeconds  = 16,      -- how long the radio popup stays up
    maxConcurrent = 3,       -- scheduled starts are skipped above this
    minPlayers    = 1,       -- scheduled starts need at least this many players online
}

-- When each event fires. times: comma list of HH:MM (24h). days: 'daily' or a comma list of mon,tue,wed,thu,fri,sat,sun.
-- Set enabled = false to turn one off
Events.Schedule = {
    airdrop = { enabled = true, times = '15:00,21:00',       days = 'daily' },
    stash   = { enabled = true, times = '13:30,17:30,23:00', days = 'daily' },
    convoy  = { enabled = true, times = '19:00',             days = 'fri,sat,sun' },
    horde   = { enabled = true, times = '22:00',             days = 'wed,sat' },
}

-- Loot rows: item, min, max, chance (0-1). Items must exist in bs_inventory config_items.
Events.Loot = {
    airdrop = {
        rolls = 6,
        { item = 'assault_rifle',    min = 1, max = 1, chance = 0.35 },
        { item = 'carbine',          min = 1, max = 1, chance = 0.35 },
        { item = 'marksman',         min = 1, max = 1, chance = 0.15 },
        { item = 'ammo_rifle',       min = 2, max = 5, chance = 0.9 },
        { item = 'att_suppressor',   min = 1, max = 1, chance = 0.3 },
        { item = 'att_scope',        min = 1, max = 1, chance = 0.35 },
        { item = 'att_grip',         min = 1, max = 1, chance = 0.35 },
        { item = 'att_extmag',       min = 1, max = 1, chance = 0.3 },
        { item = 'booster_adrenaline', min = 1, max = 2, chance = 0.4 },
        { item = 'booster_medic',    min = 1, max = 1, chance = 0.2 },
        { item = 'booster_fortify',  min = 1, max = 1, chance = 0.2 },
        { item = 'antibiotics',      min = 1, max = 3, chance = 0.6 },
        { item = 'rehab_kit',        min = 1, max = 1, chance = 0.2 },
        { item = 'medkit',           min = 1, max = 2, chance = 0.5 },
        { item = 'antiviral',        min = 1, max = 1, chance = 0.15 },
        { item = 'blood_bag',        min = 1, max = 2, chance = 0.3 },
        { item = 'surgical_kit',     min = 1, max = 1, chance = 0.25 },
        { item = 'defibrillator',    min = 1, max = 1, chance = 0.05 },
        { item = 'faction_xp_token', min = 1, max = 2, chance = 0.7 },
    },
    stash = {
        rolls = 4,
        { item = 'canned_food',  min = 2, max = 4, chance = 0.7 },
        { item = 'water_bottle', min = 2, max = 4, chance = 0.7 },
        { item = 'bandage',      min = 2, max = 5, chance = 0.6 },
        { item = 'rag',          min = 2, max = 4, chance = 0.5 },
        { item = 'splint',       min = 1, max = 2, chance = 0.3 },
        { item = 'saline',       min = 1, max = 1, chance = 0.25 },
        { item = 'painkillers',  min = 1, max = 3, chance = 0.4 },
        { item = 'antibiotics',  min = 1, max = 2, chance = 0.35 },
        { item = 'ammo_pistol',  min = 2, max = 4, chance = 0.5 },
        { item = 'ammo_rifle',   min = 1, max = 3, chance = 0.3 },
        { item = 'combat_pistol', min = 1, max = 1, chance = 0.15 },
        { item = 'lockpick',     min = 1, max = 2, chance = 0.3 },
    },
    -- military tier: truck cargo. Item names must exist in the bs_inventory registry.
    convoy = {
        rolls = 6,                               -- rolls per cargo truck
        { item = 'assault_rifle',   min = 1, max = 1, chance = 0.35 },
        { item = 'carbine',         min = 1, max = 1, chance = 0.30 },
        { item = 'marksman',        min = 1, max = 1, chance = 0.18 },
        { item = 'smg',             min = 1, max = 1, chance = 0.20 },
        { item = 'ammo_rifle',      min = 3, max = 8, chance = 0.90 },
        { item = 'ammo_pistol',     min = 2, max = 5, chance = 0.40 },
        { item = 'armour_plate',    min = 1, max = 1, chance = 0.45 },
        { item = 'att_suppressor',  min = 1, max = 1, chance = 0.25 },
        { item = 'att_scope',       min = 1, max = 1, chance = 0.35 },
        { item = 'att_grip',        min = 1, max = 1, chance = 0.30 },
        { item = 'att_extmag',      min = 1, max = 1, chance = 0.30 },
        { item = 'att_laser',       min = 1, max = 1, chance = 0.20 },
        { item = 'att_flashlight',  min = 1, max = 1, chance = 0.20 },
        { item = 'medkit',          min = 1, max = 2, chance = 0.50 },
        { item = 'tourniquet',      min = 1, max = 3, chance = 0.50 },
        { item = 'transfusion_kit', min = 1, max = 1, chance = 0.25 },
        { item = 'surgical_kit',    min = 1, max = 1, chance = 0.25 },
        { item = 'blood_bag',       min = 1, max = 2, chance = 0.30 },
        { item = 'morphine',        min = 1, max = 1, chance = 0.20 },
        { item = 'antibiotics',     min = 1, max = 2, chance = 0.40 },
        { item = 'antiviral',       min = 1, max = 1, chance = 0.12 },
        { item = 'defibrillator',   min = 1, max = 1, chance = 0.05 },
        { item = 'booster_fortify', min = 1, max = 1, chance = 0.15 },
        { item = 'booster_shield',  min = 1, max = 1, chance = 0.15 },
        { item = 'gun_parts',       min = 1, max = 3, chance = 0.30 },
        { item = 'faction_xp_token', min = 1, max = 2, chance = 0.50 },
    },
    -- loot on each dead convoy escort body, military items too. cash = small chance of pocket money
    convoy_npc = {
        rolls = 4,
        cash = { chance = 0.5, min = 15, max = 120 },
        { item = 'ammo_rifle',     min = 2, max = 5, chance = 0.80 },
        { item = 'ammo_pistol',    min = 1, max = 3, chance = 0.40 },
        { item = 'bandage',        min = 1, max = 2, chance = 0.50 },
        { item = 'tourniquet',     min = 1, max = 1, chance = 0.40 },
        { item = 'medkit',         min = 1, max = 1, chance = 0.25 },
        { item = 'morphine',       min = 1, max = 1, chance = 0.10 },
        { item = 'armour_plate',   min = 1, max = 1, chance = 0.08 },
        { item = 'att_suppressor', min = 1, max = 1, chance = 0.06 },
        { item = 'att_scope',      min = 1, max = 1, chance = 0.06 },
        { item = 'att_extmag',     min = 1, max = 1, chance = 0.06 },
        { item = 'carbine',        min = 1, max = 1, chance = 0.04 },
    },
}

Events.Airdrop = {
    enabled       = true,
    planeModel    = 'titan',                   -- or 'cargoplane'
    crateModel    = 'prop_drop_armscrate_01',
    chuteModel    = 'p_cargo_chute_s',
    flightHeight  = 320.0,                     -- metres above the drop point
    planeSpeed    = 70.0,                      -- m/s
    fallSpeed     = 7.0,                       -- m/s under canopy
    openSeconds   = 10,                        -- interaction timer
    timeoutMinutes = 25,                       -- crate removed after this even if not looted
    noiseLoudness = 260.0,                     -- how far zombies hear the flare
    blipFuzz      = 150.0,                     -- announced area is offset up to this much
    areas = {
        { label = 'Sandy Shores Airfield', points = { vector3(1695.0, 3281.0, 41.1), vector3(1747.0, 3262.0, 41.1), vector3(1612.0, 3228.0, 40.4) } },
        { label = 'Grapeseed Farmland',    points = { vector3(2140.0, 4790.0, 41.0), vector3(2450.0, 4960.0, 46.0), vector3(1905.0, 4905.0, 44.0) } },
        { label = 'Paleto Forest',         points = { vector3(-600.0, 5300.0, 70.0), vector3(-760.0, 5420.0, 35.0) } },
        { label = 'Route 68',              points = { vector3(590.0, 2740.0, 42.0), vector3(1180.0, 2650.0, 38.0) } },
        { label = 'Elysian Island Docks',  points = { vector3(1015.0, -3100.0, 5.9), vector3(1140.0, -3020.0, 5.9) } },
    },
}

Events.Stash = {
    enabled        = true,
    model          = 'prop_box_ammo03a',
    openSeconds    = 4,
    timeoutMinutes = 20,
    spots = {
        { label = 'Stab City',           coords = vector3(70.0, 3700.0, 39.7) },
        { label = 'Paleto Sawmill',      coords = vector3(-570.0, 5270.0, 70.3) },
        { label = 'Alamo Sea Pier',      coords = vector3(1300.0, 4220.0, 33.9) },
        { label = 'Senora Desert Trailer', coords = vector3(2380.0, 3040.0, 48.2) },
        { label = 'Grapeseed Barn',      coords = vector3(2450.0, 4960.0, 46.0) },
    },
}

Events.Convoy = {
    enabled          = false,                   -- off by default (F1 setting)
    announce         = true,                    -- radio + chat announcement when a convoy starts
    intervalMinutes  = 120,
    jitterMinutes    = 10,                      -- each start is moved by up to +/- this many minutes
    minPlayers       = 1,                       -- scheduled convoys need this many players online
    waypointRadius   = 25.0,                    -- the leader this close to a waypoint = go for the next one
    trucks           = { 'barracks', 'barracks3' },  -- cargo trucks; the loot (Events.Loot.convoy) is inside each
    truckCount       = 2,
    requireTool      = true,                    -- opening the cargo still needs a lockpick / crowbar
    -- cargo trucks are tough so they are not lost by accident: stop them by killing the driver or shooting the tyres
    -- A truck that dies (engine/body gone, explosion) loses its loot
    cargo = {
        reach          = 7.0,                   -- metres from the truck centre to open the cargo
        engineHealth   = 3000.0,                -- default is 1000
        bodyHealth     = 3000.0,
        tankHealth     = 3000.0,
        damageScale    = 0.25,                  -- SetVehicleDamageModifier, lower = tougher
        strong         = true,                  -- SetVehicleStrong
        tyresCanBurst  = true,                  -- shoot the tyres to stop it
    },
    leadKill = {                                -- bonus to whoever kills the lead truck driver
        enabled = true,
        rep     = 10,                           -- faction reputation
        xp      = 60,                           -- faction XP
    },
    escort = {
        vehicles        = { 'crusader', 'mesa3' },
        vehicleMin      = 2,
        vehicleMax      = 3,
        gunnersPerTruck = 2,                    -- seats filled besides the driver
        gunnersPerVehicle = 3,
        weapons         = { 'WEAPON_CARBINERIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_COMBATMG', 'WEAPON_PUMPSHOTGUN' },
        ammo            = 400,
        healthMin       = 400,
        healthMax       = 400,
        armour          = 100,
        accuracyMin     = 55,
        accuracyMax     = 65,
        ability         = 2,                    -- 0 poor, 1 average, 2 professional
        rangeMin        = 1,                    -- 1 medium, 2 far
        rangeMax        = 2,
        movement        = 1,                    -- 1 defensive (uses cover), 2 offensive
        hateRadius      = 120.0,                -- target search radius when fighting
        guardRadius     = 40.0,                 -- cargo stays locked while an escort lives this close to the truck
        group           = 'BS_CONVOY',          -- own relationship group
    },
    lockMin          = 20,                      -- forcing the cargo: seconds
    lockMax          = 40,
    tools            = { 'lockpick', 'crowbar' }, -- any one of these is needed
    lockpickBreak    = 0.35,                    -- chance a lockpick is used up
    noiseLoudness    = 220.0,                   -- forcing a crate is loud
    guards           = 8,                       -- armoured zombies around the wreck
    guardType        = 'brute',
    guardHpScale     = 1.3,
    timeoutMinutes   = 30,
    driverModel      = 's_m_y_marine_01',
    driverModels     = { 's_m_y_marine_01', 's_m_m_marine_01' },
    driverWeapon     = 'WEAPON_CARBINERIFLE',
    speed            = 14.0,                    -- m/s cruise (about 58 km/h)
    driveStyle       = 786475,                  -- careful: stops for traffic, avoids peds and vehicles
    gap              = 9.0,                     -- escort distance between vehicles
    arriveRadius     = 25.0,                    -- leader this close to the last point = arrived
    -- Fixed routes
    -- The convoy picks a random enabled one
    routes = {
        { name = 'Route 68 (Zancudo to Harmony)', points = {
            vector3(-1130.0, 2690.0, 17.5), vector3(-330.0, 2830.0, 55.0),
            vector3(590.0, 2740.0, 42.0), vector3(1180.0, 2650.0, 38.0) } },
        { name = 'Senora Freeway (Sandy to Grapeseed)', points = {
            vector3(1720.0, 3290.0, 41.0), vector3(2450.0, 3900.0, 38.0),
            vector3(2680.0, 4300.0, 44.0), vector3(2140.0, 4790.0, 41.0) } },
        { name = 'Great Ocean Highway (Paleto)', points = {
            vector3(-1520.0, 4970.0, 62.0), vector3(-1100.0, 4650.0, 60.0),
            vector3(-400.0, 6010.0, 31.0) } },
    },
    -- Used only when there are no routes at all (config empty and none in the DB)
    -- No route: it drives routeFallback metres straight ahead
    routeFallback    = 600.0,
    sites = {
        { label = 'Route 68 near Harmony',   coords = vector4(730.0, 2700.0, 39.0, 95.0),
          route = { vector3(1180.0, 2650.0, 38.0) } },
        { label = 'Great Ocean Highway',     coords = vector4(-1520.0, 4970.0, 62.0, 220.0),
          route = { vector3(-1100.0, 4650.0, 60.0) } },
        { label = 'Grapeseed Main Street',   coords = vector4(1680.0, 4800.0, 41.9, 0.0),
          route = { vector3(2140.0, 4790.0, 41.0) } },
        { label = 'Senora Freeway',          coords = vector4(2450.0, 3900.0, 38.0, 30.0),
          route = { vector3(2680.0, 4300.0, 44.0) } },
    },
}

Events.Horde = {
    enabled        = true,
    waves          = 3,
    waveSize       = 18,                        -- capped by the zombie pool (Streaming.PoolGuard.maxNetworked)
    waveInterval   = 90,                        -- seconds between waves
    bruteChance    = 0.12,
    spread         = 45.0,                      -- spawn scatter around the start point
    outskirts      = 30.0,                      -- stop this far past the safe zone's padded edge
    durationMinutes = 20,                       -- then the walkers become normal walkers
    regions = {
        { label = 'Grand Senora Desert', from = vector3(2400.0, 3400.0, 50.0),  target = 'sandy_camp' },
        { label = 'Harmony Flats',       from = vector3(1200.0, 2900.0, 40.0),  target = 'post_apocalyptic_airbase' },
        { label = 'Paleto Forest',       from = vector3(-700.0, 5500.0, 40.0),  target = 'paleto' },
    },
}

Events.FactionToken = {
    item = 'faction_xp_token',
    xp   = 250,                                 -- faction XP per token
}

-- Blip sprites (FiveM blip list): 306 crate drop, 440 dead drop, 750 military truck, 305 horde.
Events.Blips = {
    airdrop = { sprite = 306, colour = 1 },
    stash   = { sprite = 440, colour = 5 },
    convoy  = { sprite = 750, colour = 52 },
    horde   = { sprite = 305, colour = 1 },
}
