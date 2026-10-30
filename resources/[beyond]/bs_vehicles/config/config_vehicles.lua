-- bs_vehicles - vehicle config. Fuel runs out and parts wear; a worn part misbehaves in a way you can feel.
-- Thresholds are generous: driving should feel precarious, not tedious

Vehicles = {}

Vehicles.Settings = {
    -- Keys, doors and ownership.
    lockRange       = 8.0,      -- how far away lock/unlock works
    -- No auto-lock on exit: locking is always explicit. See the exit handler in cl_core.lua.
    hotwireTime     = 12000,    -- ms to hotwire a car you have no key for
    hotwireSkill    = 'lockpicking',
    hotwireMinLevel = 0,

    -- How often the server saves a vehicle's state to the database.
    persistInterval = 30000,
    -- How often the driver reports fuel and wear.
    reportInterval  = 5000,

    -- Boot.
    trunkRange      = 3.0,
    trunkSize       = 60,       -- 10 x 6
    trunkWeight     = 200.0,

    -- Diagnosing. Long enough that you would not do it in the open.
    diagnoseTime    = 6000,
    -- Repairing one part.
    repairTime      = 12000,

    -- Temporary fix, for a failed part when you have no time or spares
    -- Free and fast but a gamble: it only brings a part back to just above its own fail line
    tempFixTime          = 7000,
    tempFixSuccessChance = 0.40,
    -- How far above the part's own fail line a successful patch lands
    tempFixMargin        = 14,
    -- Free. Add costs here if you want them.
    tempFixCost          = {},
    -- Seconds before the same part on the same car can be temp-fixed again.
    tempFixCooldown       = 300,

    -- Stripping a car for parts. It leaves a hulk behind, see cl_strip.lua.
    scrapTime       = 25000,
    scrapRange      = 4.0,
}

-- Dash HUD: speed, RPM, fuel, engine and body condition, shown while driving
-- Per-player (on/off, unit, size), not saved server-side or synced
Vehicles.Hud = {
    enabled       = true,
    -- 'kmh' or 'mph'. Cycle with the unit command below.
    unit          = 'kmh',
    -- Starting HUD size. /bs_carhud_scale adjusts it live (per-player, not saved).
    scale         = 1.4,
    toggleCommand = 'bs_carhud',
    unitCommand   = 'bs_carhud_units',
    -- Dash styles shown in inventory Settings. vip = true needs VIP (bs_vip), or is free when VIP is switched off.
    style         = 'field',
    styles = {
        { id = 'classic',  vip = false },
        { id = 'field',    vip = false },
        { id = 'tactical', vip = false },
        { id = 'scrap',    vip = true },
        { id = 'nightops', vip = true },
        { id = 'gauge',    vip = false },
        { id = 'slate',    vip = false },
        { id = 'cipher',   vip = true },
        { id = 'hologram', vip = true },
    },
}

-- Fuel. Consumption is per real-world minute at full throttle, scaled by engine load.
-- A tank is 100 units, so drain is roughly percent of a tank per minute flat out (2.2 is a bit over 45 min of hard driving)
Vehicles.Fuel = {
    drain        = 2.2,
    -- Idling still burns, just much less.
    idleDrain    = 0.35,
    -- A holed tank leaks. Multiplied by how damaged the tank is.
    leakDrain    = 3.0,
    -- Below this the engine starts to stutter as a warning.
    spluttersAt  = 8.0,
    -- The item that refuels, and how much one gives.
    canItem      = 'fuel_can',

    -- Everything that can hold diesel. One list shared by refuelling, siphoning and the barrels in bs_interactions.
    -- Order does not matter; the inventory tops up the fullest container first
    containers   = { 'fuel_can', 'empty_bottle' },
    canAmount    = 35.0,
    refuelTime   = 8000,
    -- Siphoning an abandoned car's tank into a can. Same amount as a can gives when poured.
    siphonAmount = 35.0,
    siphonTime   = 9000,
    -- Optional tool needed to siphon from the radial (e.g. 'siphon_hose'). false = only a container.
    siphonTool   = false,
}

-- Fuel stations
-- The power is off, so nothing is bought
Vehicles.Stations = {
    { label = 'Route 68',        x = 49.4,     y = 2778.7,   z = 58.0 },
    { label = 'Harmony',         x = 263.9,    y = 2606.6,   z = 44.9 },
    { label = 'Paleto Bay',      x = -94.6,    y = 6419.6,   z = 31.5 },
    { label = 'Sandy Shores',    x = 1181.4,   y = 2640.7,   z = 37.8 },
    { label = 'Grapeseed',       x = 2679.9,   y = 3263.9,   z = 55.2 },
    { label = 'Grand Senora',    x = 1745.6,   y = 4636.4,   z = 42.0 },
    { label = 'Popular Street',  x = -724.6,   y = -935.0,   z = 19.2 },
    { label = 'Strawberry',      x = 265.0,    y = -1261.4,  z = 29.3 },
    { label = 'Vespucci',        x = -527.9,   y = -1211.4,  z = 18.2 },
    { label = 'Chumash',         x = -70.9,    y = -1761.9,  z = 29.5 },
    { label = 'Pacific Bluffs',  x = -2096.2,  y = -320.5,   z = 13.2 },
    { label = 'Davis',           x = 178.9,    y = -1562.4,  z = 29.3 },
}

-- The pumps
-- A pump works when its station sits in a lit bs_world generator zone, or while somebody keeps a battery clamped to it
Vehicles.Pumps = {
    enabled = true,

    models = {
        'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c',
        'prop_gas_pump_1d', 'prop_gas_pump_old2', 'prop_gas_pump_old3',
        'prop_vintage_pump', 'prop_gas_pump_1a_frag_', 'prop_gas_pump_1c_frag_',
    },

    distance = 2.6,          -- how close you must be to use one
    stationCapacity = 1000,  -- litres under each forecourt
    startPct = 30,           -- reserve on server start, %
    stationRadius = 60.0,    -- pumps this close to a listed station share its reserve
    tickMs = 500,            -- one pump tick while holding the trigger
    litersPerTick = 1.0,
    hoseLength = 6.0,        -- nozzle hose reach from the pump

    -- Jump-starting a dead pump off a battery (a car with the bonnet open, or a loose battery item).
    jump = {
        enabled = true,
        cableItem = 'jumper_cables',
        batteryItem = 'battery',
        junkItem = 'junk_battery',
        cableLength = 6.0,       -- car moves more than this and the cables snap
        clampMs = 1400,          -- per clamp
        crankWindowMs = 18000,   -- time to finish the needle game
        holdMs = 3500,           -- time the needle has to spend in the green
        difficulty = 1.0,        -- global multiplier (F1)
        skillTree = 'crafting',  -- bs_skills tree used as the mechanic/electric skill
        classes = { engineer = true, mechanic = true },
        minCharge = 5,           -- a battery under this will not crank
        wearMin = 5,  wearMax = 10,          -- capacity lost on success, %
        failWearMin = 15, failWearMax = 25,  -- capacity lost on a failed crank, %
        drainPerLiter = 1.0,     -- battery % per litre pumped
        shock = true,            -- failed cranks can shock you
        shockChance = 0.6,
        noise = true,            -- failed cranks spark and draw nearby walkers (never spawns any)
        noiseRadius = 60.0,
        xp = 40,                 -- skill XP for a good crank
    },

    recharge = {
        drivingPerMinute = 3.0,  -- battery % per minute of engine running
        generatorAmount = 40,    -- % per charge at a running base generator
        generatorFuel = 3,       -- generator fuel per charge
        generatorMs = 8000,
        generatorModels = { 'prop_generator_03b', 'prop_generator_01a' },
    },
}

Vehicles.StationSettings = {
    -- How close you must be, on foot, to search a listed station. Generous.
    radius       = 15.0,
    -- How long searching takes.
    searchTime   = 6500,
    -- Chance a search turns up a can.
    findChance   = 0.55,
    -- Minutes before the same station is worth searching again, win or lose.
    cooldown     = 600,
}

-- The parts. wear is 0 (broken) to 100 (new), symptom is what the driver notices, repair is what fixing it costs.
Vehicles.Parts = {
    {
        id = 'engine', label = 'Engine',
        symptom = 'It hesitates and loses power on hills.',
        -- Below warn the symptom appears; below fail the part stops working
        warn = 55, fail = 18,
        repair = { { item = 'engine_part', amount = 1 }, { item = 'scrap_metal', amount = 4 } },
        wearPerKm = 0.55,
    },
    {
        id = 'battery', label = 'Battery',
        symptom = 'It turns over slowly, and sometimes not at all.',
        warn = 45, fail = 12,
        repair = { { item = 'battery', amount = 1 } },
        wearPerKm = 0.0,   -- battery is charge now, owned by the server (sv_pumps)
    },
    {
        id = 'radiator', label = 'Radiator',
        symptom = 'It runs hot. Steam under the bonnet in traffic.',
        warn = 50, fail = 15,
        repair = { { item = 'scrap_metal', amount = 6 }, { item = 'cloth', amount = 2 } },
        wearPerKm = 0.40,
    },
    {
        id = 'brakes', label = 'Brakes',
        symptom = 'It pulls to one side and takes far too long to stop.',
        warn = 50, fail = 20,
        repair = { { item = 'brake_pads', amount = 1 }, { item = 'scrap_metal', amount = 2 } },
        wearPerKm = 0.60,
    },
    {
        id = 'tyres', label = 'Tyres',
        symptom = 'It wanders on the straight and the ride is harsh.',
        warn = 45, fail = 14,
        repair = { { item = 'tyre', amount = 1 } },
        wearPerKm = 0.70,
    },
    {
        id = 'transmission', label = 'Transmission',
        symptom = 'It hunts between gears and clunks going in.',
        warn = 40, fail = 12,
        repair = { { item = 'engine_part', amount = 2 }, { item = 'scrap_metal', amount = 3 } },
        wearPerKm = 0.30,
    },
}

-- What a worn part does. Applied client-side to the vehicle you drive; felt rather than read.
Vehicles.Effects = {
    -- Engine: top speed and acceleration fall away.
    enginePowerFloor      = 0.45,
    -- Brakes: stopping distance grows.
    brakeFloor            = 0.35,
    -- Tyres: grip goes.
    tractionFloor         = 0.55,
    -- Transmission: a failed one will not let you past this fraction of speed.
    transmissionCap       = 0.5,
    -- Radiator: a failed one cooks the engine over time.
    overheatDamagePerSec  = 6.0,
    -- Battery: chance per start that a failed battery simply does not.
    deadBatteryChance     = 0.75,

    -- Failure, not speed
    -- A failed part makes the car slower and harder to control
    engineIntermittentChance = 0.012,
    -- Tyres: once failed and moving at speed, chance per tick that one pops.
    tyreBurstChance          = 0.006,
    -- An already-burst tyre on a still-failed set can come off entirely.
    tyreDetachChance         = 0.0015,
    -- Below this speed nothing pops or detaches.
    tyreFailureMinSpeed      = 8.0,
}

--- Stripping a wreck: one skill check per part. The server rolls everything and validates the timings.
-- mode 'timing': a marker sweeps the bar
-- Amounts also scale with the wreck's condition
Vehicles.ScrapGame = {
    totalTime   = 120000,   -- ms for the whole job, from the first check
    maxLaps     = 2,        -- sweeps before a timing check counts as a miss
    graceMs     = 700,      -- network slack allowed on reported times
    minReactMs  = 180,      -- faster than this is not human
    perfectFrac = 0.25,     -- inner part of the zone that counts as perfect
    mult        = { perfect = 1.25, good = 1.0, miss = 0.35 },
    missChance  = 0.5,      -- multiplier on the part chance after a miss
    minChance   = 0.05,
    maxChance   = 0.97,
    xpTree      = 'crafting',
    xpPerPart   = 3,
    -- Best tool carried is used. chance/zone are added to every part.
    tools = {
        { item = 'toolbox', chance = 0.15, zone = 0.05, mult = 1.15 },
        { item = 'crowbar', chance = 0.08, zone = 0.03, mult = 1.05 },
    },
    -- Skill tree level (bs_skills, if running) adds per level.
    skill = { chancePerLevel = 0.01, zonePerLevel = 0.004 },
    parts = {
        { id = 'doors',   mode = 'timing', period = 1500, zone = 0.20, chance = 0.90,
          yield = { { item = 'scrap_metal', min = 3, max = 6 } } },
        { id = 'hood',    mode = 'timing', period = 1400, zone = 0.20, chance = 0.90,
          yield = { { item = 'scrap_metal', min = 2, max = 4 } } },
        { id = 'trunk',   mode = 'timing', period = 1400, zone = 0.20, chance = 0.90,
          yield = { { item = 'scrap_metal', min = 2, max = 4 }, { item = 'fuel_can', min = 1, max = 1, chance = 0.2 } } },
        { id = 'wheels',  mode = 'hold',   period = 1800, zone = 0.18, chance = 0.80,
          yield = { { item = 'tyre', min = 1, max = 2, chance = 0.7 } } },
        { id = 'engine',  mode = 'hold',   period = 2200, zone = 0.12, chance = 0.55,
          yield = { { item = 'engine_part', min = 1, max = 1 }, { item = 'spark_plug', min = 1, max = 1, chance = 0.5 } } },
        { id = 'battery', mode = 'timing', period = 1100, zone = 0.12, chance = 0.65, missing = 'battery',
          yield = { { item = 'battery', min = 1, max = 1 }, { item = 'electrical_wire', min = 1, max = 2, chance = 0.6 } } },
        { id = 'seats',   mode = 'timing', period = 1600, zone = 0.22, chance = 0.85,
          yield = { { item = 'cloth', min = 2, max = 4 } } },
        { id = 'exhaust', mode = 'hold',   period = 1600, zone = 0.16, chance = 0.75,
          yield = { { item = 'scrap_metal', min = 2, max = 5 } } },
        { id = 'tank',    mode = 'timing', period = 1200, zone = 0.14, chance = 0.60, missing = 'fueltank',
          yield = { { item = 'fuel_tank', min = 1, max = 1 } } },
    },
}

-- Wheel key is G, not U (U opens the survivor menu in bs_menu and the two fought over NUI focus and blur)
-- The command name changed too: FiveM stores key bindings per command name in the player's settings
Vehicles.Radial = {
    key     = 'G',
    command = 'bs_vehiclewheel',
}

--- Plates. Generated for a vehicle that has never been seen before.
Vehicles.Plate = {
    prefix = 'BS',
    length = 6,
}

-- World vehicles (DayZ/SCUM style). Spawned at random road spots, refilled only when the server restarts.
-- Every one starts with no battery, spark plug or fuel tank (see Vehicles.Missing)
Vehicles.World = {
    enabled = true,

    -- Most of each category that may exist at once. Claimed ones still count.
    max = { car = 20, pickup = 8, van = 5, bike = 4, offroad = 3 },

    -- Models per category as "model:weight,model:weight". Higher weight = more common.
    -- Editable in F1, so more models can be added without touching this file
    pool = {
        car     = 'emperor2:4,tornado3:3,tornado4:2,voodoo2:3',
        pickup  = 'ratloader:3,rebel:3',
        van     = 'surfer2:3,journey:2,flatbed:1',
        bike    = 'ratbike:3,deathbike:1,bmx:3',
        offroad = 'bodhi2:3,dloader:3,wastelander:1',
    },

    -- Starting fuel, percent. Only usable once a fuel tank is fitted.
    fuelMin = 0, fuelMax = 50,

    -- How far from the player a client looks for a road spot
    -- Restore radius is 220 m, so spots appear as you travel
    ringMin = 260.0, ringMax = 650.0,
    -- No spawn this close to any player.
    playerClear = 180.0,
    -- No spawn inside a safezone, outpost or faction flag, plus this padding.
    safePad = 40.0,
    -- No spawn this close to another saved vehicle.
    vehicleClear = 25.0,
    -- How often the server asks a client for a spot while some are still owed (ms).
    askEvery = 20000,

    -- Spread: each spawn is aimed at a random anchor (x, y, rough z) plus up to anchorJitter metres
    -- Any online player's client finds the road spot there
    spread = true,
    anchorJitter = 700.0,
    -- A found road spot must be this close to the aimed point.
    anchorSnap = 250.0,
    -- Ask interval while spreading (ms); owed cars are placed over the first minutes of an uptime.
    spreadEvery = 4000,
    anchors = {
        { -1037.0, -2737.0, 14.0 }, { -1220.0, -1320.0, 5.0 },  { 120.0, -910.0, 30.0 },   { -1450.0, -400.0, 35.0 },
        { 300.0, 200.0, 105.0 },    { 100.0, -1700.0, 30.0 },   { 1000.0, -600.0, 60.0 },  { 1200.0, -1500.0, 35.0 },
        { -1800.0, -300.0, 20.0 },  { -3030.0, 500.0, 7.0 },    { -2000.0, 3100.0, 32.0 }, { -1500.0, 2200.0, 60.0 },
        { 600.0, 2700.0, 42.0 },    { 1200.0, 2700.0, 38.0 },   { 1850.0, 3700.0, 34.0 },  { 1400.0, 3600.0, 35.0 },
        { 2400.0, 3300.0, 48.0 },   { 1700.0, 4800.0, 41.0 },   { 2500.0, 5000.0, 44.0 },  { 2900.0, 4400.0, 48.0 },
        { 400.0, 3000.0, 40.0 },    { -150.0, 6250.0, 31.0 },   { -700.0, 5500.0, 40.0 },  { -400.0, 4500.0, 100.0 },
        { 200.0, 4600.0, 120.0 },   { 1000.0, 5600.0, 200.0 },  { -2400.0, 2600.0, 40.0 }, { 2600.0, 2000.0, 70.0 },
        { 1500.0, 1200.0, 100.0 },  { -2900.0, 1700.0, 150.0 }, { -1100.0, 4600.0, 140.0 }, { 3300.0, 5200.0, 40.0 },
    },

    -- Exploded vehicles become wrecks. Wrecks and stripped hulks are deleted after this many minutes.
    wreckMinutes = 120,
}

-- Parts that can be missing entirely. A missing part is fitted from the item, nothing else.
Vehicles.Missing = {
    { id = 'battery',   label = 'Battery',    item = 'battery',    stops = 'start' },
    { id = 'sparkplug', label = 'Spark plug', item = 'spark_plug', stops = 'start' },
    { id = 'fueltank',  label = 'Fuel tank',  item = 'fuel_tank',  stops = 'fuel'  },
}
Vehicles.FitTime = 8000

-- Lockpicking a claimed vehicle. Not allowed inside safezones, so a car parked there is safe after logout.
-- A pick wipes the claim: the next player to get in can claim it
Vehicles.Lockpick = {
    -- Pins to set. Each one is a bar with a sweet spot; press E when the marker is on it.
    pins = 3,
    -- Width of the sweet spot (fraction of the bar) at skill 0 and at max skill.
    zoneMin = 0.08, zoneMax = 0.22,
    -- Marker speed (bar widths per second) at skill 0 and at max skill.
    speedMin = 1.35, speedMax = 0.75,
    -- Misses allowed before the attempt fails.
    misses = 2,
    -- Chance the pick snaps on a failed attempt.
    breakChance = 0.5,
    -- Skill level treated as max for the curves above.
    maxLevel = 20,
}
