-- bs_operations config: power station, control points, mission chains
-- Most numbers are F1 settings (bs_config, category Operations)

Ops = {}

Ops.Settings = {
    adminAces = { 'bs.admin', 'bs.superadmin' },
    tickMs    = 2000,          -- server think interval
    -- Faction rank permission (bs_factions) needed to start the power station.
    startPerm = 'raid',
}

-- Power station (capture and hold)
Ops.Power = {
    enabled         = true,
    label           = 'Downtown Power Station',
    x = 689.0, y = 134.0, z = 80.0,
    captureRadius   = 45.0,
    minPlayers      = 10,     -- players online to start
    cooldownMinutes = 360,
    repairMinutes   = 15,     -- time to fix every panel before the run fails
    repairSeconds   = 10,     -- minimum time on one panel
    holdMinutes     = 60,
    captureSeconds  = 45,     -- uncontested time a rival needs to take control
    minHoldSeconds  = 120,    -- a faction needs this much hold time to win
    contribSeconds  = 180,    -- time in the zone a player needs for the personal reward
    -- Paid by the faction member who starts it.
    cost = {
        { item = 'electrical_wire', amount = 6 },
        { item = 'electronics',     amount = 4 },
        { item = 'scrap_metal',     amount = 30 },
    },
    -- Repair panels, offsets from the station centre (move them in F1 > Operations).
    panels = {
        { x = 8.0,  y = 4.0,  z = 0.0 },
        { x = -9.0, y = 6.0,  z = 0.0 },
        { x = 2.0,  y = -11.0, z = 0.0 },
    },
    waves = {
        intervalSeconds = 120,
        base            = 8,
        perPlayer       = 2,      -- added per player inside the zone
        maxAlive        = 45,
        bruteChance     = 0.12,
        ringMin         = 80.0,
        ringMax         = 130.0,
    },
    rewards = {
        buffHours    = 4,         -- faction buff length
        buffXpPct    = 15,        -- extra XP on rewarded actions while the buff runs
        buffLight    = true,      -- faction safezone is lit while the buff runs
        factionXp    = 1500,
        playerXp     = 600,
        playerRep    = 40,
        playerMoney  = 400,
        crateMinutes = 20,
        crate = {
            { item = 'ammo_rifle',  min = 30, max = 60 },
            { item = 'medkit',      min = 2,  max = 4 },
            { item = 'electronics', min = 3,  max = 6 },
            { item = 'gun_parts',   min = 2,  max = 4 },
            { item = 'c4',          min = 1,  max = 1, chance = 0.4 },
            { item = 'assault_rifle', min = 1, max = 1, chance = 0.25 },
        },
    },
    -- bs_world power zone ids switched on while the station runs. Restored after.
    districts = {},
}

-- Control points
Ops.Points = {
    enabled         = true,
    activateRadius  = 160.0,   -- garrison spawns when a faction player gets this close
    sleepSeconds    = 180,     -- garrison is removed after nobody is near for this long
    captureSeconds  = 60,
    guards          = 12,      -- default garrison size
    brutes          = 2,
    defenders       = 10,      -- spawned when a rival attacks an owned point
    revertHours     = 24,      -- owned point turns hostile again after this (0 = never)
    cacheMinutes    = 30,      -- supply cache refill
    rewardXp        = 300,
    rewardRep       = 20,
    rewardFactionXp = 400,
    cache = {
        { item = 'canned_food',  min = 2, max = 4 },
        { item = 'water_bottle', min = 2, max = 4 },
        { item = 'bandage',      min = 2, max = 5 },
        { item = 'ammo_pistol',  min = 12, max = 24 },
        { item = 'ammo_rifle',   min = 10, max = 20, chance = 0.5 },
        { item = 'scrap_metal',  min = 5, max = 10 },
    },
    list = {
        { id = 'cp_grapeseed',  label = 'Grapeseed Silos',     x = 2434.0,  y = 4968.0,  z = 46.0, radius = 35.0 },
        { id = 'cp_paleto_mill',label = 'Paleto Sawmill',      x = -565.0,  y = 5325.0,  z = 70.0, radius = 40.0 },
        { id = 'cp_quarry',     label = 'Stone Quarry',        x = 2950.0,  y = 2790.0,  z = 41.0, radius = 45.0 },
        { id = 'cp_harmony',    label = 'Harmony Motel',       x = 1142.0,  y = 2664.0,  z = 38.0, radius = 30.0 },
        { id = 'cp_dam',        label = 'Land Act Dam',        x = 1660.0,  y = -14.0,   z = 173.0, radius = 40.0 },
        { id = 'cp_docks',      label = 'Elysian Docks',       x = 1000.0,  y = -3100.0, z = 5.9,  radius = 45.0 },
        { id = 'cp_chumash',    label = 'Chumash Plaza',       x = -3165.0, y = 1095.0,  z = 20.8, radius = 35.0 },
    },
}

-- Mission chains
-- Given by quest traders of the chain's faction (a trader tagged with that faction, or standing in its safezone)
-- Step types: goto, kill, collect, deliver, defend, escort
Ops.Missions = {
    enabled       = true,
    squadScale    = 0.5,     -- extra spawns and rewards per extra squad member
    squadRange    = 250.0,   -- squad members this close share rewards
    failCooldown  = 10,      -- minutes before a failed chain can be retried
    dailyHeroic   = 1,       -- heroic chains per character per day
    leaveSeconds  = 25,      -- time allowed outside a defend area
}

Ops.Chains = {
    mil_dead_signal = {
        faction = 'military', tier = 'story', minLevel = 1, cooldownHours = 12,
        steps = {
            { type = 'goto',    place = 'Sandy Shores Airfield', x = 1730.0, y = 3310.0, z = 41.0, radius = 30.0 },
            { type = 'kill',    place = 'Sandy Shores Airfield', x = 1730.0, y = 3310.0, z = 41.0, radius = 90.0, count = 12, spawn = 12 },
            { type = 'collect', item = 'electronics', count = 2 },
            { type = 'defend',  place = 'Sandy Shores Airfield', x = 1730.0, y = 3310.0, z = 41.0, radius = 30.0, seconds = 120, waves = 3, size = 7 },
        },
        reward = { xp = 900, money = 500, rep = 40, factionXp = 300 },
    },
    mil_zancudo_ghosts = {
        faction = 'military', tier = 'heroic', minLevel = 10, minRep = 100, requires = 'mil_dead_signal', cooldownHours = 24,
        steps = {
            { type = 'goto',    place = 'Zancudo Gate', x = -1590.0, y = 2795.0, z = 17.0, radius = 35.0 },
            { type = 'kill',    place = 'Zancudo Gate', x = -1590.0, y = 2795.0, z = 17.0, radius = 100.0, count = 20, spawn = 20, brutes = 3 },
            { type = 'escort',  place = 'Zancudo Gate', model = 's_m_y_marine_01', x = -1590.0, y = 2795.0, z = 17.0, to = { x = 1744.0, y = 3265.0, z = 41.2 }, radius = 20.0 },
            { type = 'kill',    place = 'Military Safezone outskirts', x = 1600.0, y = 3200.0, z = 40.0, radius = 80.0, count = 1, spawn = 0, elite = { hpScale = 6.0 } },
        },
        reward = { xp = 2500, money = 1500, rep = 120, factionXp = 900, items = { { item = 'att_scope', amount = 1 } } },
    },
    reb_cut_lines = {
        faction = 'rebels', tier = 'story', minLevel = 1, cooldownHours = 12,
        steps = {
            { type = 'collect', item = 'c4', count = 1 },
            { type = 'goto',    place = 'Palmer-Taylor Power Station', x = 2735.0, y = 1530.0, z = 24.5, radius = 30.0 },
            { type = 'deliver', item = 'c4', count = 1, place = 'Palmer-Taylor Power Station', x = 2735.0, y = 1530.0, z = 24.5, radius = 8.0 },
            { type = 'defend',  place = 'Palmer-Taylor Power Station', x = 2735.0, y = 1530.0, z = 24.5, radius = 30.0, seconds = 90, waves = 3, size = 8 },
        },
        reward = { xp = 900, money = 600, rep = 40, factionXp = 300 },
    },
    reb_bolingbroke = {
        faction = 'rebels', tier = 'hard', minLevel = 6, requires = 'reb_cut_lines', cooldownHours = 18,
        steps = {
            { type = 'goto',    place = 'Bolingbroke', x = 1850.0, y = 2600.0, z = 45.6, radius = 40.0 },
            { type = 'kill',    place = 'Bolingbroke', x = 1850.0, y = 2600.0, z = 45.6, radius = 100.0, count = 18, spawn = 18, brutes = 2 },
            { type = 'escort',  place = 'Bolingbroke', model = 's_m_y_prisoner_01', x = 1850.0, y = 2600.0, z = 45.6, to = { x = 1015.0, y = -318.0, z = 67.0 }, radius = 20.0 },
        },
        reward = { xp = 1600, money = 900, rep = 80, factionXp = 600, items = { { item = 'gun_parts', amount = 3 } } },
    },
    civ_medicine_run = {
        faction = 'civilians', tier = 'story', minLevel = 1, cooldownHours = 8,
        steps = {
            { type = 'goto',    place = 'Pillbox Hill Medical', x = 298.0, y = -584.0, z = 43.3, radius = 30.0 },
            { type = 'kill',    place = 'Pillbox Hill Medical', x = 298.0, y = -584.0, z = 43.3, radius = 80.0, count = 10, spawn = 10 },
            { type = 'collect', item = 'antibiotics', count = 2 },
            { type = 'deliver', item = 'antibiotics', count = 2, place = 'Civilians Safezone', x = -266.0, y = -2049.0, z = 27.0, radius = 25.0 },
        },
        reward = { xp = 800, money = 500, rep = 40, factionXp = 300, items = { { item = 'medkit', amount = 1 } } },
    },
    civ_doctor = {
        faction = 'civilians', tier = 'challenging', minLevel = 8, requires = 'civ_medicine_run', cooldownHours = 24,
        steps = {
            { type = 'goto',    place = 'Mount Zonah', x = -449.0, y = -340.0, z = 34.5, radius = 35.0 },
            { type = 'defend',  place = 'Mount Zonah', x = -449.0, y = -340.0, z = 34.5, radius = 30.0, seconds = 150, waves = 4, size = 8 },
            { type = 'escort',  place = 'Mount Zonah', model = 's_m_m_doctor_01', x = -449.0, y = -340.0, z = 34.5, to = { x = -266.0, y = -2049.0, z = 27.0 }, radius = 20.0 },
        },
        reward = { xp = 2000, money = 1200, rep = 100, factionXp = 700, items = { { item = 'surgical_kit', amount = 1 } } },
    },
    bik_fuel_road = {
        faction = 'bikers', tier = 'story', minLevel = 1, cooldownHours = 8,
        steps = {
            { type = 'goto',    place = 'Route 68 Gas Station', x = 1040.0, y = 2670.0, z = 39.5, radius = 30.0 },
            { type = 'kill',    place = 'Route 68 Gas Station', x = 1040.0, y = 2670.0, z = 39.5, radius = 80.0, count = 10, spawn = 10 },
            { type = 'collect', item = 'fuel_can', count = 2 },
            { type = 'deliver', item = 'fuel_can', count = 2, place = 'Bikers Safezone', x = 957.2, y = -206.2, z = 72.0, radius = 25.0 },
        },
        reward = { xp = 800, money = 550, rep = 40, factionXp = 300 },
    },
    bik_road_kings = {
        faction = 'bikers', tier = 'heroic', minLevel = 10, minRep = 100, requires = 'bik_fuel_road', cooldownHours = 24,
        steps = {
            { type = 'deliver', item = 'supply_crate', count = 1, give = true, place = 'Stab City', x = 70.0, y = 3700.0, z = 39.7, radius = 25.0 },
            { type = 'defend',  place = 'Stab City', x = 70.0, y = 3700.0, z = 39.7, radius = 35.0, seconds = 180, waves = 4, size = 9 },
            { type = 'kill',    place = 'Stab City', x = 70.0, y = 3700.0, z = 39.7, radius = 90.0, count = 1, spawn = 0, elite = { hpScale = 6.0 } },
        },
        reward = { xp = 2500, money = 1500, rep = 120, factionXp = 900, items = { { item = 'att_extmag', amount = 1 } } },
    },
}
