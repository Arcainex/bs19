-- bs_zombies - tunables for the streaming planner (server/sv_streaming.lua) and the client spawner (client/cl_spawner.lua)
-- Adapted from Norway174's mrpz_zombies Config.Streaming

Streaming = {}

-- Master switch. false = nothing runs (no planner, rays, telemetry or events). true = planner and client
-- See dryRun. To revert, set false and restart.
Streaming.enabled = true

-- Second switch. true = accepted candidates are only counted and discarded. false = they become walkers
-- Together with Sectors.Settings.enabled = false in config_sectors.lua this is the whole cutover
Streaming.dryRun = false

-- Cadence

-- Server plan interval (ms). One plan every 2.5s is cheap, and an arrival window (15s) still gets about 6 plans.
Streaming.planMs = 2500

-- Client work interval (ms): how often the spawner turns a plan into candidates
-- Slightly faster than planMs so each plan is acted on
Streaming.workMs = 1000

-- Client observation interval (ms). The expensive one: observe() casts 48 shape tests per pass.
-- Separate so the ray budget can be tuned alone
Streaming.observeMs = 500

-- Distances

-- Hidden-spawn ring around the player (m): candidates are drawn between spawnMin and spawnMax
-- Keep spawnMin above spawnFloor and Noise.Materialise.hardFloor, or every spawn is refused
Streaming.spawnMin = 70.0
Streaming.spawnMax = 140.0
Streaming.quietAreaMs = 15000
Streaming.quietAreaRadius = 75.0

-- Distance floor for this path (m)
-- Lower than the sector system's spawnDistanceMin (180) because candidates here are ray-tested as unseen
Streaming.spawnFloor = 70.0
Streaming.arrivalFloor = 140.0

-- A node closer than this (m) to a cluster is a candidate for real peds.
Streaming.fullDistance = 310.0

-- Cleanup distance (m): a walker further than this from every player is culled
-- It must exceed the furthest a walker can be born (spawnMax + Sim.spawn.openPushMax, plus slack), or walkers get deleted as they arrive
Streaming.cleanupDistance = 400.0

-- Hidden-spawn rule (see cl_spawner.lua for the mechanism)

-- How long (ms) a 22m cell stays "recently seen" after a ray reached it
-- Too short and walkers fade in behind you
Streaming.observationMemoryMs = 15000

-- Cell size (m) of the observation memory
-- Matches the sector cell size in sv_registry.lua by coincidence; do not couple them
Streaming.observationCellSize = 22.0

-- Rays per observation pass: bearings x distances across the live spawn ring
-- Three rings and 48 probes keep the memory dense and aligned with where candidates are created
Streaming.observeBearings = 16
Streaming.observeDistances = { 85.0, 125.0, 155.0 }

-- Shape-test polling: frames a probe may take before the candidate is discarded as "could not prove it is hidden"
-- Discarding on timeout is deliberate
Streaming.rayPollFrames = 8

-- Eye height and target height (m) for visibility probes.
Streaming.eyeHeight = 0.75
Streaming.targetHeight = 0.8

-- Attempts per requested walker before giving up on the slot for this pass.
Streaming.candidateAttempts = 16

-- The stale-observation cache follows the camera cone; current-frame visibility stays exact.
Streaming.observationFovRays = 5
Streaming.observationHalfFov = 55.0

-- Candidates one client may offer per plan
-- Ours is 3 because our cluster budgets are about a third of the reference values
Streaming.spawnPerPlan = 4

-- Max candidates from one herd per plan
-- A herd is a point, so several from one herd stack up in one small circle
Streaming.perNodePerPlan = 2

-- Ambient share: how many of a plan's slots may go to hunters
-- The nearest herds are the ones already hunting the player, so without a cap every slot goes to hunters and nobody is seen at a distance
Streaming.huntSharePerPlan = 1

-- Request gate: max spawn requests (requestsPerWindow) one client may send per window (requestWindowMs)
-- Derived from workMs and spawnPerPlan so it sits above what an honest client sends but still stops a broken one
Streaming.requestWindowMs = 1200
Streaming.requestsPerWindow = 8

-- Arrival window

-- When a player travels more than arrivalTravelDistance (m) from where they last anchored
-- Without it, a newly entered town fills too slowly
Streaming.arrivalWindowMs = 15000
Streaming.arrivalTravelDistance = 220.0
Streaming.arrivalSpawnMaxDistance = 280.0

-- Clustering

-- Players within this radius (m) share one budget and one coordinator
-- Without it a squad in one street gets one budget per player and the street ends up over-populated
Streaming.clusterRadius = 300.0

-- Adaptive budgets

-- Down fast, up slow: -24 / +8 per tick
-- A budget that rises as fast as it falls oscillates and the population visibly pulses
Streaming.budgetStepDown = 24
Streaming.budgetStepUp = 8

-- Client telemetry interval (ms).
Streaming.telemetryMs = 2000

-- Per-cluster budgets (walkers): coldStart is used before telemetry arrives
-- Starting low is the safe direction; a healthy client climbs at +8 per tick
Streaming.clusterColdStart = 14
Streaming.clusterSoft = 26
Streaming.clusterHard = 40

-- Server-wide ceilings on walkers this path is responsible for: soft 120, hard 200
-- A busy server narrows every cluster instead of starving the last one to ask
Streaming.globalSoft = 120
Streaming.globalHard = 200

-- Anti-despawn / pool safety.
Streaming.PoolGuard = {
    maxNetworked      = 128,    -- hard world cap on registry walkers (also clamps globalHard)
    maxPerPlayer      = 28,    -- walkers already near a player count against this
    minSpawnDistance  = 50.0,
    clientPedLimit    = 180,   -- refuse CreatePed / spawn requests at this CPed pool size
    clientMaxLocal    = 40,    -- walkers one client will hold as peds
    joinSyncMs        = 6000,  -- after first sync, wait this long before asking for new spawns
    hostDriftAccept   = 60.0,  -- host drift under this is followed (clamped), never snapped
    hostSnapDistance  = 120.0, -- only past this, and only if not in combat, is a host snapped back
}

-- Telemetry ladder: measured client health to budget its cluster may aim at
-- A cluster takes the worst of its members. Ped-count thresholds use the whole ped pool, not just walkers.
Streaming.ladder = {
    { fps = 30, peds = 200, target = 6 },
    { fps = 40, peds = 180, target = 12 },
    { fps = 50, peds = 160, target = 18 },
    { fps = 58, peds = 140, target = 24 },
}

-- Safe zones

-- Safe zones come from Zones.Safe in config_zones.lua (checked by inSafeZone() in sv_registry.lua and again client-side in cl_sync.lua)
-- Same list and padding on both sides of this stage
Streaming.safeZonePaddingFallback = 55.0

-- Placement gate: spawn far from each other and away from any player's view
-- Enforced in client/cl_spawner.lua (the only side with collision and a camera) and re-checked server-side in

Streaming.Placement = {
    -- Minimum distance (m) from every player, not just the one spawning
    -- Separate from spawnMin, which is the ring around the spawning player
    minPlayerDistance = 70.0,
    -- Refuse candidates in the local camera's forward arc even if the engine's frustum test reports them occluded at this instant
    localViewHalfAngle = 65.0,
    localViewRange = 300.0,

    -- Minimum separation (m) between two spawns of the same response; closer candidates are discarded. 25m is about "not in the same doorway".
    -- Do not raise it far above spawnMax - spawnMin or the ring fills up and every later candidate is refused
    minSpawnSeparation = 10.0,

    -- How long (ms) a used point keeps reserving its separation radius
    -- Long enough to cover a noise response, short enough that walking a street twice does not leave it sterile
    separationMemoryMs = 8000,

    -- View test: IsSphereVisible asks the engine if a sphere at the candidate intersects the local camera frustum
    viewSphereRadius = 2.0,

    -- Remote players: a client cannot know another player's camera
    -- Peds not streamed to this client cannot be tested; minPlayerDistance (server-side) covers them
    remoteViewHalfAngle = 75.0,
    remoteViewRange     = 180.0,

    -- If a remote ped cannot be read (zero forward vector, ped 0), treat it as unknown and refuse the candidate
    -- Keep true; false ignores unknown players
    refuseOnUnknownRemote = true,
}

-- Stagger: accepted candidates go into a queue and one thread dispatches them with a random gap

Streaming.Stagger = {
    -- Milliseconds between two dispatches, drawn uniformly from this range. The jitter avoids a fixed rhythm.
    minGapMs = 250,
    maxGapMs = 700,

    -- Max accepted candidates held in the queue
    -- Extras are dropped, not banked, since the view check would be stale
    maxQueued = 12,

    -- Max age in ms of a queued candidate. Older ones are discarded because the view check no longer holds.
    maxAgeMs = 6000,
}
