-- bs_jobs - faction jobs. No salary: every finished contract pays character XP, skill XP and faction rep.
-- Settings marked (F1) are live in the F1 console (category Faction Jobs).
-- Every position below is approximate. Fix them in F1 if a station lands in a wall.

Jobs = {}

Jobs.Settings = {
    enabled            = true,  -- (F1)
    leaveCooldownHours = 24,    -- (F1) wait after leaving a job before taking another
    boardRefreshMin    = 45,    -- (F1) open contracts older than this are swapped for new ones
    takenMinutes       = 90,    -- (F1) time to finish a contract once taken
    vanillaBoardPerJob = 3,     -- (F1) open contracts per job on a vanilla board
    playerBoardPerJob  = 2,     -- (F1) open contracts per job on a player faction board
    vanillaRewardMult  = 1.5,   -- (F1) vanilla factions are always stronger
    playerRewardMult   = 1.0,   -- (F1)
    playerMaxPicks     = 2,     -- (F1) jobs a player faction may pick from the pool
    stationRadius      = 3.0,   -- how close you must be to use a station
    turnInRadius       = 10.0,  -- turn-ins work this close to one of your faction's job stations
    victimCooldownMin  = 120,   -- (F1) the same player can be robbed or kidnapped once per this
    robPercent         = 20,    -- (F1) share of the victim's bag a Raider takes
    ransomCap          = 2500,  -- (F1) highest ransom a Kidnapper may ask
    kidnapMaxMinutes   = 20,    -- (F1) a captive is released automatically after this
    smugglePingSeconds = 120,   -- (F1) how often a smuggler's position leaks to other factions
    huntingEnabled     = true,  -- (F1) animal spawner in the wild
    huntPerPlayer      = 3,     -- (F1) animals kept around each player in a hunting area
    huntMax            = 24,    -- (F1) animals in the whole world
    huntLifeMinutes    = 20,    -- animals despawn after this
    huntSpawnMin       = 70,    -- (F1) closest an animal appears to a player (m)
    huntSpawnMax       = 130,   -- (F1) farthest an animal appears (m)
    huntAvoidTowns     = true,  -- (F1) no animals inside Jobs.Hunting.towns
    huntPredators      = true,  -- (F1) mountain lions and boars attack players; off = they flee like the rest
    huntAggroRadius    = 25.0,  -- (F1) predators charge players this close (m)
    huntLeash          = 70.0,  -- predators give up past this (m)
    huntFleeRadius     = 30.0,  -- (F1) other animals run from players this close (m)
}

-- Members per job. Everything starts at 2 (F1 per job).
Jobs.Caps = {
    gunsmith = 2, combat_medic = 2, patrol = 2, logistics = 2, mechanic = 2,
    bike_mechanic = 2, road_captain = 2, fuel_runner = 2, scrapper = 2,
    hunter_fisher = 2, farmer = 2, cook = 2, medic = 2, water_engineer = 2,
    kidnapper = 2, car_thief = 2, raider = 2, smuggler = 2,
    scavenger = 2, hunter = 2, fisher = 2,
}

-- skill = bs_skills tree that gets skill XP. special = vanilla only, never in the player pool.
-- garage = 'car' or 'bike' for the mechanic garage.
Jobs.Defs = {
    gunsmith       = { label = 'Gunsmith',        skill = 'crafting',    special = true },
    combat_medic   = { label = 'Combat Medic',    skill = 'medical' },
    patrol         = { label = 'Patrol Officer',  skill = 'combat' },
    logistics      = { label = 'Logistics',       skill = 'survival' },
    mechanic       = { label = 'Mechanic',        skill = 'crafting',    garage = 'car' },
    bike_mechanic  = { label = 'Bike Mechanic',   skill = 'crafting',    garage = 'bike', special = true },
    road_captain   = { label = 'Road Captain',    skill = 'survival' },
    fuel_runner    = { label = 'Fuel Runner',     skill = 'survival' },
    scrapper       = { label = 'Scrapper',        skill = 'crafting' },
    hunter_fisher  = { label = 'Hunter & Fisher', skill = 'survival' },
    farmer         = { label = 'Farmer',          skill = 'survival' },
    cook           = { label = 'Cook',            skill = 'survival' },
    medic          = { label = 'Medic',           skill = 'medical' },
    water_engineer = { label = 'Water Engineer',  skill = 'crafting' },
    kidnapper      = { label = 'Kidnapper',       skill = 'combat',      special = true },
    car_thief      = { label = 'Car Thief',       skill = 'lockpicking' },
    raider         = { label = 'Raider',          skill = 'combat' },
    smuggler       = { label = 'Smuggler',        skill = 'survival' },
    scavenger      = { label = 'Scavenger',       skill = 'survival' },
    hunter         = { label = 'Hunter',          skill = 'survival' },
    fisher         = { label = 'Fisher',          skill = 'survival' },
}

-- Jobs per vanilla faction, 2-5 each. A vanilla faction not listed gets Jobs.VanillaFallback.
Jobs.Vanilla = {
    military  = { 'gunsmith', 'combat_medic', 'patrol', 'logistics', 'mechanic' },
    bikers    = { 'bike_mechanic', 'road_captain', 'fuel_runner', 'scrapper' },
    civilians = { 'hunter_fisher', 'farmer', 'cook', 'medic', 'water_engineer' },
    rebels    = { 'kidnapper', 'car_thief', 'raider', 'smuggler' },
}
Jobs.VanillaFallback = { 'mechanic', 'scavenger', 'medic' }

-- Player-made factions pick up to playerMaxPicks of these. Never special jobs.
Jobs.PlayerPool = { 'mechanic', 'scavenger', 'hunter', 'fisher', 'farmer' }

-- What a job counts as for shared tasks (fishing spots, hunting): a Hunter & Fisher does both.
Jobs.Does = {
    hunter_fisher = { hunt = true, fish = true },
    hunter = { hunt = true }, fisher = { fish = true },
    water_engineer = { water = true }, car_thief = { chop = true }, fuel_runner = { siphon = true },
    kidnapper = { kidnap = true }, raider = { rob = true }, smuggler = { smuggle = true },
    gunsmith = { gunsmith = true },
}

-- Job stations inside each vanilla safezone (approximate, F1 editable).
-- kind: yard = turn-ins and the mechanic garage, gunsmith = the gunsmith bench, chop = chop shop, water = purifier.
Jobs.Stations = {
    military_yard     = { faction = 'military',  kind = 'yard',     x = 1730.0, y = 3290.0, z = 41.1,  h = 105.0 },
    military_gunsmith = { faction = 'military',  kind = 'gunsmith', x = 1752.0, y = 3255.0, z = 41.2,  h = 15.0 },
    bikers_yard       = { faction = 'bikers',    kind = 'yard',     x = 965.0,  y = -198.0, z = 72.6,  h = 60.0 },
    civilians_yard    = { faction = 'civilians', kind = 'yard',     x = -255.0, y = -2040.0, z = 27.7, h = 230.0 },
    civilians_water   = { faction = 'civilians', kind = 'water',    x = -280.0, y = -2060.0, z = 27.7, h = 50.0 },
    rebels_yard       = { faction = 'rebels',    kind = 'yard',     x = 1010.0, y = -322.0, z = 66.8,  h = 150.0 },
    rebels_chop       = { faction = 'rebels',    kind = 'chop',     x = 1030.0, y = -335.0, z = 66.5,  h = 150.0 },
}

-- Contract templates per job. kind:
--   count   = do event amount times (counted from gameplay, e.g. skinning, repairs, zombie kills)
--   nest    = kill amount walkers near a nest point
--   deliver = bring items to one of your faction's job stations
--   route   = drive through points (convoy needs escort faction mates close by)
--   supply  = recover a crate at a drop point and bring it home
--   service = refuel a generator at a power zone (uses a fuel can)
--   smuggle = carry contraband to a drop point, your position leaks every few minutes
-- rep = faction reputation, xp = character XP, sxp = skill XP, fxp = faction level XP.
Jobs.Contracts = {
    gunsmith = {
        { id = 'gs_attach', kind = 'count', event = 'gunsmith_attach', amount = { 3, 5 }, rep = 40, xp = 120, sxp = 60, fxp = 30 },
        { id = 'gs_gadget', kind = 'count', event = 'gunsmith_gadget', amount = { 1, 2 }, rep = 45, xp = 140, sxp = 70, fxp = 35 },
        { id = 'gs_parts',  kind = 'deliver', items = { { item = 'gun_parts', amount = { 2, 3 } }, { item = 'screws', amount = { 10, 20 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    combat_medic = {
        { id = 'cm_treat',  kind = 'count', event = 'wound_treated', amount = { 3, 5 }, rep = 35, xp = 110, sxp = 60, fxp = 25 },
        { id = 'cm_revive', kind = 'count', event = 'player_revived', amount = { 1, 2 }, rep = 45, xp = 140, sxp = 80, fxp = 30 },
        { id = 'cm_kits',   kind = 'deliver', items = { { item = 'bandage', amount = { 4, 8 } }, { item = 'antiseptic', amount = { 1, 3 } } }, rep = 25, xp = 80, sxp = 30, fxp = 15 },
    },
    patrol = {
        { id = 'pt_nest',  kind = 'nest', amount = { 10, 16 }, radius = 80.0, rep = 50, xp = 160, sxp = 80, fxp = 35 },
        { id = 'pt_sweep', kind = 'count', event = 'zombie_kill', amount = { 25, 40 }, rep = 35, xp = 110, sxp = 60, fxp = 25 },
        { id = 'pt_horde', kind = 'count', event = 'horde_cleared', amount = { 1, 1 }, rep = 55, xp = 180, sxp = 90, fxp = 40 },
    },
    logistics = {
        { id = 'lg_drop', kind = 'supply', rep = 45, xp = 140, sxp = 50, fxp = 35 },
        { id = 'lg_ammo', kind = 'deliver', items = { { item = 'ammo_rifle', amount = { 20, 40 } }, { item = 'ammo_pistol', amount = { 20, 40 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    mechanic = {
        { id = 'mc_repair', kind = 'count', event = 'vehicle_repaired', amount = { 2, 4 }, rep = 30, xp = 100, sxp = 50, fxp = 20 },
        { id = 'mc_garage', kind = 'count', event = 'garage_car', amount = { 2, 3 }, rep = 40, xp = 120, sxp = 60, fxp = 30 },
        { id = 'mc_parts',  kind = 'deliver', items = { { item = 'spark_plug', amount = { 1, 2 } }, { item = 'tyre', amount = { 1, 2 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    bike_mechanic = {
        { id = 'bm_garage', kind = 'count', event = 'garage_bike', amount = { 2, 3 }, rep = 45, xp = 130, sxp = 60, fxp = 30 },
        { id = 'bm_repair', kind = 'count', event = 'vehicle_repaired', amount = { 2, 3 }, rep = 30, xp = 100, sxp = 50, fxp = 20 },
        { id = 'bm_parts',  kind = 'deliver', items = { { item = 'engine_part', amount = { 1, 1 } }, { item = 'rubber', amount = { 4, 8 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    road_captain = {
        { id = 'rc_convoy', kind = 'route', points = 3, escort = 1, vehicle = true, rep = 55, xp = 170, sxp = 60, fxp = 40 },
        { id = 'rc_scout',  kind = 'route', points = 4, escort = 0, vehicle = true, rep = 35, xp = 110, sxp = 40, fxp = 25 },
    },
    fuel_runner = {
        { id = 'fr_siphon',  kind = 'count', event = 'fuel_siphoned', amount = { 2, 4 }, rep = 35, xp = 110, sxp = 40, fxp = 25 },
        { id = 'fr_deliver', kind = 'deliver', items = { { item = 'fuel_can', amount = { 2, 3 } } }, rep = 35, xp = 100, sxp = 30, fxp = 25 },
    },
    scrapper = {
        { id = 'sc_salvage', kind = 'count', event = 'salvage', amount = { 2, 3 }, rep = 35, xp = 110, sxp = 50, fxp = 25 },
        { id = 'sc_scrap',   kind = 'deliver', items = { { item = 'scrap_metal', amount = { 20, 35 } }, { item = 'rubber', amount = { 3, 6 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    hunter_fisher = {
        { id = 'hf_skin', kind = 'count', event = 'skin_animal', amount = { 2, 4 }, rep = 35, xp = 110, sxp = 50, fxp = 25 },
        { id = 'hf_fish', kind = 'count', event = 'fish_catch', amount = { 4, 7 }, rep = 35, xp = 110, sxp = 50, fxp = 25 },
        { id = 'hf_meat', kind = 'deliver', items = { { item = 'raw_meat', amount = { 4, 8 } }, { item = 'leather', amount = { 2, 4 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    farmer = {
        { id = 'fa_harvest', kind = 'count', event = 'harvest', amount = { 2, 3 }, rep = 35, xp = 110, sxp = 50, fxp = 25 },
        { id = 'fa_potato',  kind = 'deliver', items = { { item = 'potato', amount = { 8, 14 } } }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    cook = {
        { id = 'ck_cook', kind = 'count', event = 'craft_food', amount = { 4, 6 }, rep = 30, xp = 100, sxp = 40, fxp = 20 },
        { id = 'ck_stew', kind = 'deliver', items = { { item = 'meat_stew', amount = { 1, 3 } }, { item = 'cooked_fish', amount = { 2, 4 } } }, rep = 35, xp = 110, sxp = 40, fxp = 25 },
    },
    medic = {
        { id = 'md_treat',  kind = 'count', event = 'wound_treated', amount = { 3, 4 }, rep = 30, xp = 100, sxp = 60, fxp = 20 },
        { id = 'md_revive', kind = 'count', event = 'player_revived', amount = { 1, 1 }, rep = 40, xp = 130, sxp = 80, fxp = 25 },
        { id = 'md_kits',   kind = 'deliver', items = { { item = 'bandage', amount = { 6, 10 } } }, rep = 25, xp = 80, sxp = 30, fxp = 15 },
    },
    water_engineer = {
        { id = 'we_service', kind = 'service', rep = 45, xp = 140, sxp = 60, fxp = 35 },
        { id = 'we_purify',  kind = 'count', event = 'water_purified', amount = { 4, 6 }, rep = 30, xp = 100, sxp = 40, fxp = 20 },
        { id = 'we_bottles', kind = 'deliver', items = { { item = 'water_bottle', amount = { 4, 8 } } }, rep = 25, xp = 80, sxp = 30, fxp = 15 },
    },
    kidnapper = {
        { id = 'kd_ransom', kind = 'count', event = 'ransom_paid', amount = { 1, 1 }, rep = 70, xp = 200, sxp = 80, fxp = 45 },
        { id = 'kd_grab',   kind = 'count', event = 'kidnap', amount = { 1, 1 }, rep = 40, xp = 120, sxp = 50, fxp = 25 },
    },
    car_thief = {
        { id = 'ct_chop',    kind = 'count', event = 'car_chopped', amount = { 1, 2 }, rep = 55, xp = 170, sxp = 80, fxp = 35 },
        { id = 'ct_hotwire', kind = 'count', event = 'vehicle_hotwired', amount = { 2, 3 }, rep = 35, xp = 110, sxp = 60, fxp = 25 },
    },
    raider = {
        { id = 'rd_rob',    kind = 'count', event = 'player_robbed', amount = { 1, 1 }, rep = 55, xp = 160, sxp = 60, fxp = 35 },
        { id = 'rd_loot',   kind = 'count', event = 'resource_gathered', amount = { 10, 15 }, rep = 30, xp = 90, sxp = 30, fxp = 20 },
    },
    smuggler = {
        { id = 'sm_run', kind = 'smuggle', rep = 60, xp = 180, sxp = 60, fxp = 40 },
    },
    scavenger = {
        { id = 'sv_search', kind = 'count', event = 'resource_gathered', amount = { 10, 15 }, rep = 25, xp = 90, sxp = 40, fxp = 15 },
        { id = 'sv_forage', kind = 'count', event = 'forage', amount = { 4, 6 }, rep = 20, xp = 70, sxp = 30, fxp = 15 },
        { id = 'sv_junk',   kind = 'deliver', items = { { item = 'electronics', amount = { 2, 4 } }, { item = 'scrap_metal', amount = { 10, 20 } } }, rep = 25, xp = 80, sxp = 30, fxp = 15 },
    },
    hunter = {
        { id = 'hu_skin',    kind = 'count', event = 'skin_animal', amount = { 2, 3 }, rep = 25, xp = 90, sxp = 40, fxp = 15 },
        { id = 'hu_leather', kind = 'deliver', items = { { item = 'leather', amount = { 3, 5 } } }, rep = 20, xp = 70, sxp = 30, fxp = 15 },
    },
    fisher = {
        { id = 'fi_fish',    kind = 'count', event = 'fish_catch', amount = { 4, 6 }, rep = 25, xp = 90, sxp = 40, fxp = 15 },
        { id = 'fi_deliver', kind = 'deliver', items = { { item = 'raw_fish', amount = { 3, 6 } } }, rep = 20, xp = 70, sxp = 30, fxp = 15 },
    },
}

-- Places contracts send people to. All approximate, away from safezones.
Jobs.Nests = {
    { x = 1695.0, y = 4790.0, z = 41.9 },   -- Grapeseed
    { x = 590.0,  y = 2730.0, z = 42.0 },   -- Harmony
    { x = -125.0, y = 6290.0, z = 31.4 },   -- Paleto Bay
    { x = 240.0,  y = 200.0,  z = 105.0 },  -- Vinewood
    { x = -3150.0, y = 1095.0, z = 20.7 },  -- Chumash
    { x = 1210.0, y = -1430.0, z = 35.0 },  -- El Burro
}
Jobs.SupplyDrops = {
    { x = 2580.0, y = 3160.0, z = 51.0 },
    { x = -1110.0, y = 2690.0, z = 18.6 },
    { x = 230.0,  y = 3080.0, z = 42.5 },
    { x = 2950.0, y = 4630.0, z = 48.5 },
    { x = -540.0, y = 5300.0, z = 74.2 },
}
Jobs.RoutePoints = {
    { x = 1200.0, y = 2690.0, z = 37.9 },   -- Route 68
    { x = 2410.0, y = 3110.0, z = 48.2 },
    { x = 2700.0, y = 4410.0, z = 46.8 },   -- Great Ocean north
    { x = 1700.0, y = 6400.0, z = 31.5 },
    { x = -2200.0, y = 4300.0, z = 52.0 },
    { x = -1550.0, y = 1900.0, z = 82.0 },
    { x = 870.0,  y = 2100.0, z = 52.0 },
    { x = 2550.0, y = 1700.0, z = 29.0 },
}
Jobs.SmuggleDrops = {
    { x = 1530.0, y = 6330.0, z = 24.1 },
    { x = -1120.0, y = 4920.0, z = 218.0 },
    { x = 2340.0, y = 4850.0, z = 41.8 },
    { x = -3030.0, y = 120.0, z = 11.6 },
    { x = 3600.0, y = 3700.0, z = 29.0 },
}
-- Generators (same places as bs_world Power.Zones).
Jobs.Generators = {
    { id = 'sandy_camp',     x = 1855.0, y = 3683.0, z = 34.3 },
    { id = 'paleto_refuge',  x = -448.0, y = 6013.0, z = 31.7 },
    { id = 'hospital_block', x = 297.5,  y = -584.6, z = 43.3 },
}

-- Fishing: stand in one of these with a fishing rod. Bait gives better fish.
Jobs.Fishing = {
    ms = 14000,
    spots = {
        { x = -1850.0, y = -1250.0, z = 8.6,  r = 30.0 },   -- Del Perro pier
        { x = -3428.0, y = 967.0,   z = 8.3,  r = 25.0 },   -- Chumash pier
        { x = -275.0,  y = 6635.0,  z = 7.4,  r = 25.0 },   -- Paleto pier
        { x = 1300.0,  y = 4217.0,  z = 33.9, r = 30.0 },   -- Alamo Sea dock
        { x = 713.0,   y = 4093.0,  z = 34.7, r = 30.0 },   -- Alamo Sea west
        { x = -1611.0, y = 5260.0,  z = 3.9,  r = 25.0 },   -- Paleto cove
    },
    catch = { { item = 'raw_fish', chance = 0.70 }, { item = 'big_fish', chance = 0.12, baitChance = 0.30 } },
}

-- Hunting areas: the spawner keeps animals around players inside these circles (never in safezones).
Jobs.Hunting = {
    models = { 'a_c_deer', 'a_c_boar', 'a_c_coyote', 'a_c_rabbit_01', 'a_c_mtlion' },
    weights = { 40, 25, 15, 18, 2 },
    areas = {
        { x = -600.0,  y = 5500.0, r = 900.0 },   -- Paleto forest
        { x = 500.0,   y = 5500.0, r = 700.0 },   -- Mount Chiliad
        { x = -1500.0, y = 4300.0, r = 700.0 },   -- Raton Canyon
        { x = -1700.0, y = 2200.0, r = 700.0 },   -- Tongva / Zancudo hills
        { x = 2900.0,  y = 3800.0, r = 700.0 },   -- Grand Senora east
        { x = 1500.0,  y = 1600.0, r = 800.0 },   -- Tataviam mountains
        { x = 2900.0,  y = 5300.0, r = 600.0 },   -- Mount Gordon
        { x = -300.0,  y = 2300.0, r = 550.0 },   -- Great Chaparral
        { x = 2700.0,  y = -200.0, r = 600.0 },   -- Palomino Highlands
    },
    -- Attack players (relationship group BS_PREDATOR). Everything else flees.
    predators = { a_c_mtlion = true, a_c_boar = true },
    -- Towns: no animals spawn inside these circles (huntAvoidTowns).
    towns = {
        { x = -250.0,  y = -1000.0, r = 1900.0 }, -- Los Santos
        { x = 1700.0,  y = 3700.0,  r = 450.0 },  -- Sandy Shores
        { x = -200.0,  y = 6400.0,  r = 450.0 },  -- Paleto Bay
        { x = 1900.0,  y = 4900.0,  r = 350.0 },  -- Grapeseed
        { x = 550.0,   y = 2700.0,  r = 250.0 },  -- Harmony
        { x = -3150.0, y = 1000.0,  r = 350.0 },  -- Chumash
        { x = -2250.0, y = 3100.0,  r = 500.0 },  -- Fort Zancudo
    },
}

-- Gunsmith bench (military only). Cheaper than the weapon bench and the only place for some gadgets.
-- event: gunsmith_attach or gunsmith_gadget (what contracts count).
Jobs.Gunsmith = {
    { id = 'att_suppressor', item = 'att_suppressor', amount = 1, ms = 20000, event = 'gunsmith_attach', cost = { { item = 'metal_pipe', amount = 1 }, { item = 'scrap_metal', amount = 2 } } },
    { id = 'att_scope',      item = 'att_scope',      amount = 1, ms = 20000, event = 'gunsmith_attach', cost = { { item = 'electronics', amount = 1 }, { item = 'scrap_metal', amount = 2 }, { item = 'glue', amount = 1 } } },
    { id = 'att_grip',       item = 'att_grip',       amount = 2, ms = 15000, event = 'gunsmith_attach', cost = { { item = 'scrap_metal', amount = 2 }, { item = 'rubber', amount = 1 } } },
    { id = 'att_flashlight', item = 'att_flashlight', amount = 1, ms = 15000, event = 'gunsmith_attach', cost = { { item = 'electronics', amount = 1 }, { item = 'scrap_metal', amount = 1 } } },
    { id = 'att_extmag',     item = 'att_extmag',     amount = 1, ms = 20000, event = 'gunsmith_attach', cost = { { item = 'scrap_metal', amount = 3 }, { item = 'screws', amount = 4 } } },
    { id = 'att_laser',      item = 'att_laser',      amount = 1, ms = 18000, event = 'gunsmith_attach', cost = { { item = 'electronics', amount = 2 }, { item = 'wires', amount = 1 } } },
    { id = 'booster_turret', item = 'booster_turret', amount = 1, ms = 45000, event = 'gunsmith_gadget', cost = { { item = 'gun_parts', amount = 1 }, { item = 'electronics', amount = 3 }, { item = 'scrap_metal', amount = 6 } } },
    { id = 'booster_drone',  item = 'booster_drone',  amount = 1, ms = 40000, event = 'gunsmith_gadget', cost = { { item = 'battery', amount = 1 }, { item = 'electronics', amount = 2 }, { item = 'scrap_metal', amount = 2 } } },
    { id = 'booster_decoy',  item = 'booster_decoy',  amount = 2, ms = 15000, event = 'gunsmith_gadget', cost = { { item = 'scrap_metal', amount = 2 }, { item = 'electrical_wire', amount = 1 } } },
    { id = 'booster_medic',  item = 'booster_medic',  amount = 1, ms = 35000, event = 'gunsmith_gadget', cost = { { item = 'electronics', amount = 2 }, { item = 'bandage', amount = 3 }, { item = 'battery', amount = 1 } } },
}

-- Water purifier (Water Engineer): dirty water in, clean bottles out.
Jobs.Water = { ms = 10000, input = 'dirty_water', inputAmount = 2, output = 'water_bottle', outputAmount = 3 }

-- Siphon (Fuel Runner): from parked cars nobody owns. Fills one fuel can.
Jobs.Siphon = { ms = 12000, tool = 'siphon_hose', can = 'fuel_can', empty = 'empty_bottle', take = 25.0 }

-- Chop shop (Car Thief): a car you picked in the last windowMin minutes. The owner keeps the car,
-- the parts come off it and go to you.
Jobs.Chop = { windowMin = 120, parts = { 'battery', 'sparkplug' }, items = { battery = 'battery', sparkplug = 'spark_plug' }, bonus = { { item = 'scrap_metal', amount = 8 }, { item = 'rubber', amount = 2 } } }
