-- bs_zombies - zombie simulation config. Every tunable, with the direction that breaks it.
-- Model: the primitive is one zombie with its own position, heading and state

Sim = Sim or {}

-- Master switch. false keeps the resource loaded, answers every callback with { ok = false, error = 'sim disabled' } and spawns nothing.
-- The old sector path (sv_sectors.lua) still runs
Sim.enabled = true

-- 1. Population

Sim.population = {}

-- World-wide headcount
-- Higher (200k+): the empty quarters are never empty
Sim.population.target = 100000

-- Cell share of the target (its baseline, which regrowth climbs back to)
-- Derived from the atlas points (config_atlas.lua): more points nearby = more built up
Sim.population.urbanRadius   = 260.0   -- metres; an atlas point's influence
Sim.population.urbanWeight   = 6.0     -- weight added per point in range
Sim.population.fallbackWeight= 1.0     -- every cell gets at least this
Sim.population.maxCellBaseline = 80    -- hard ceiling per 50m cell

-- 2. Grid (far field)

Sim.grid = {}

-- Cell size in metres. About the distance at which two zombies read as together.
-- Bigger (100) halves sweep cost but promotion gets lumpy
Sim.grid.cell = 50.0

-- World bounds. Read from ZAtlas.bounds when loaded; these are the fallback.
Sim.grid.minX, Sim.grid.minY = -4200.0, -4200.0
Sim.grid.maxX, Sim.grid.maxY =  4800.0,  8200.0

-- 3. Near field (individuals)

Sim.near = {}

-- Metres. Zombies within this distance of any player are real records.
-- Covers the streaming ring (60-140m) and arrival ceiling (280m)
Sim.near.promoteRadius = 600.0

-- Metres
-- Demote at a larger radius than promote (hysteresis), or zombies flip between record and count and re-roll their positions
Sim.near.demoteRadius = 780.0

-- Global cap on individuals, the hard bound on memory and tick cost (2500 is single-digit ms per sweep)
-- At the cap, promotion stops nearest-cell-first, so truncation happens at the far edge; the atlas snapshot flags it as truncated
Sim.near.maxAgents = 2500

-- Per-cell promotion cap; the rest of an oversized cell stays as a count.
Sim.near.maxPerCell = 20

-- 4. Movement: wander, lurk, 300m leash

Sim.move = {}

-- Max distance in metres a zombie may be from where it was drawn (its origin), independent of sector boundaries
-- Raise it and the density map homogenises toward noise; lower it and zombies feel pinned
Sim.move.maxDriftFromOrigin = 300.0

Sim.move.wanderSpeed = 0.9    -- m/s while wandering. Shuffling pace.
Sim.move.lurkSpeed   = 0.35   -- m/s while lurking. Barely moving.
Sim.move.drawnSpeed  = 1.15   -- m/s walking to a noise. Matches Registry.Lure.
Sim.move.huntSpeed   = 2.6    -- m/s once it has a player. Faster than you walk.

-- ms. How long a zombie keeps one wander leg before picking a new bearing.
-- Short looks indecisive, long looks like patrols
Sim.move.legMinMs, Sim.move.legMaxMs = 6000, 20000

-- 0..1. Share of idle time spent lurking (barely moving) rather than walking. Higher also saves CPU.
Sim.move.lurkShare = 0.55

-- 5. Sense ladder. Precedence, lowest to highest: heard < seen < scent < damaged.
-- Hearing never sets a player as target, it sets a point. Only sight, scent or damage may name a person.

Sim.sense = {}

-- Metres. Max range of a noise from the POI board (sv_poi.lua), scaled by its loudness.
-- A suppressed shot or footstep is a fraction of this; loud noises like helicopters are capped here
Sim.sense.hearMaxRange = 320.0
Sim.sense.hearMinRange = 8.0

-- Metres. Base range at which a standing, moving player inside the cone is seen.
-- Read from config_noise.lua (Noise.Detection.sight) with a literal fallback; live walkers use the same value
Sim.sense.sightRange = (Noise and Noise.Detection and Noise.Detection.sight
                        and Noise.Detection.sight.standing) or 50.0

-- Degrees, half-angle of the vision cone (65 = 130 degree field)
-- Stealth comes from the crouch multiplier and the behind rule, not a narrow cone
Sim.sense.sightHalfAngle = 65.0

-- Multiplies sight range for a player standing still (no shooting, no vehicle).
Sim.sense.stillMultiplier = 0.45

-- Sight multiplier when crouched; prone is lower
-- Derived so crouched sight matches the live-walker value (10 / 50 = 0.2)
Sim.sense.crouchSightMultiplier = (function()
    local d = Noise and Noise.Detection and Noise.Detection.sight
    if d and d.standing and d.standing > 0 and d.crouched then
        return d.crouched / d.standing
    end
    return 0.2
end)()
Sim.sense.proneSightMultiplier  = 0.15

-- Metres. Scent range.
-- Defeated by: crouched or prone (range x crouchScentMultiplier), being behind the zombie (outside the scent arc), sneaking (treated as crouched)
Sim.sense.scentRange = 5.0
Sim.sense.crouchScentMultiplier = 0.35   -- 1.75m. You have to nearly touch it.
Sim.sense.scentHalfAngle = 120.0         -- 240 degree arc; "behind" is the rest.

-- Seconds a damaged zombie keeps targeting the shooter
-- Damage ignores every stealth term, so suppressors are not a win button
Sim.sense.damageTargetSeconds = 45

-- Seconds a zombie keeps chasing a player it can no longer sense before falling back to a point (the last place it saw them)
Sim.sense.huntMemorySeconds = 18

-- 6
-- Choosing between noises By score

Sim.score = {}

-- score = loudness^loudPower * recency * visibility * proximity loudPower > 1 makes loudness dominate (3x louder = 4.7x more interesting)
-- Raise it if zombies dither
Sim.score.loudPower = 1.4

-- Seconds for a noise to lose half its recency value. Only ranks; the POI board lifetime is the real cutoff.
Sim.score.halfLifeSeconds = 25.0

-- Multiplier when the noise source passes the sight test.
Sim.score.visibleMultiplier = 2.5

-- How much closer noises are favoured. 1.0 = score scales with (1 - d/reach).
Sim.score.proximityWeight = 1.0

-- 7
-- Vehicles Engine noise drags zombies, but past followRange they stop following and drift along that direction for driftSeconds

Sim.vehicle = {}

Sim.vehicle.enabled = true

-- Metres. How far a moving engine is heard, scaled by speed (see fullSpeed).
Sim.vehicle.baseRange = 140.0
Sim.vehicle.speedRange = 260.0        -- added at full speed
Sim.vehicle.fullSpeed = 30.0          -- m/s treated as "full speed" (~108 km/h)

-- Metres. Beyond this the zombie stops tracking the vehicle and keeps only the direction it was last going.
Sim.vehicle.followRange = 200.0

-- Seconds of walking/lurking along the remembered bearing before decaying back to wandering
-- Too high and one car drags the whole county; too low and vehicles stop mattering
Sim.vehicle.driftSeconds = 120
Sim.vehicle.driftDistance = 120.0

-- 8. Herds (an observation, not a primitive) 20+ zombies in the same area count as a herd.

Sim.herd = {}

Sim.herd.minCount = 20
Sim.herd.radius   = 45.0

-- Herds are recomputed on the observation sweep, not stored, and nothing spawns from a herd
-- Cost is O(interesting cells): only cells with count >= minCount/4 and their neighbours
Sim.herd.sweepSeconds = 5   -- informational; the real cadence is Sim.tick.herdMs

-- 9. Regrowth Killed zombies take a while to repopulate.

Sim.regrow = {}

Sim.regrow.enabled = true

-- Zombies per hour per 50m cell. At 1.5, a cleared block of 12 takes about 8 hours to refill.
-- Keep it low so a cleared town stays cleared
Sim.regrow.perCellPerHour = 1.5

-- Regrowth climbs to baseline * this, never past it
-- At 1.0 the world population stays self-limited at Sim.population.target
Sim.regrow.capFraction = 1.0

-- Minutes a freshly emptied cell waits before regrowth starts.
Sim.regrow.graceMinutes = 20

-- 10. Migration

Sim.migrate = {}

Sim.migrate.enabled = true

-- Fraction of a cell's count that may move to a neighbour per sweep. 0.02 is a slow shuffle
Sim.migrate.rate = 0.02

-- 0-1. How strongly far-field zombies drift toward live noise points.
Sim.migrate.noiseBias = 0.55

-- 11. Tick budget - read before changing any number above

Sim.tick = {}

-- ms
-- Agent sweep: each near-field individual is integrated once per this interval
Sim.tick.agentMs = 250
Sim.tick.agentsPerSlice = 400        -- 2500 agents / 400 = a full pass in 1.6s

-- ms. Far-field sweep (migration + regrowth), sliced; never the whole grid at once.
Sim.tick.cellMs = 1000
Sim.tick.cellsPerSlice = 1500        -- ~40k live cells => a full pass in ~27s

-- ms. Promotion/demotion check; only looks at players and observers.
Sim.tick.promoteMs = 2000

-- ms
-- Herd observation, also sliced and resumed from a cursor, so the list can be up to one pass stale (fine for display and horde triggers)
Sim.tick.herdMs = 5000
Sim.tick.herdCellsPerSlice = 6000

-- 12. Atlas observers Lets staff watch a town live with nobody there.

Sim.observer = {}

-- Seconds before an observer expires unless the atlas refreshes it
-- It must expire: an observer forces promotion and a forgotten one keeps ~2000 records alive
Sim.observer.ttlSeconds = 300
Sim.observer.maxRadius = 1200.0
Sim.observer.max = 8

-- 13. Spawning (the visible half)

Sim.spawn = {}

-- Metres
-- Zombies should spawn out of view. cl_spawner.lua already refuses candidates with a clear line from the eye
Sim.spawn.openPushStep = 12.0
-- Metres. Max total push on open ground (see openPushStep), added to Streaming.spawnMax.
-- In open desert nothing can hide a spawn, so the candidate is walked out until it is past view distance and walks in
Sim.spawn.openPushMax  = 120.0      -- + Streaming.spawnMax (300) = 420m furthest

-- Open-ground fallback. In open scrubland every attempt fails with rayClear and the field stays empty.
-- With this true, a candidate past openGroundMinDistance may be accepted with a clear ray
Sim.spawn.openGroundFallback    = true
Sim.spawn.openGroundMinDistance = 180.0
