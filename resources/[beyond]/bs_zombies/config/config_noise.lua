-- bs_zombies - noise migration model
-- Noise moves existing walkers toward the last heard sound; it never spawns new ones

Noise = Noise or {}

-- 1. Cuts: each of these severs one route from noise to population.

-- Master switch for the migration model. false restores the old behaviour (sector multiplier, herd relocation, noise-driven spawn budget).
-- Other settings here are ignored while false
Noise.enabled = true

-- May noise move a herd?
-- If true, herds with an alert walk to the alert point, which skews the spawner that draws from the nearest herd. false: herds ignore noise.
Noise.herdMigration = false

-- While a POI is live, the planner refuses to draw spawn candidates from herds within plannerStandoff of it
-- If walkers still appear near noise, raise plannerStandoff and check /zwhy
Noise.plannerRefusesAlertedHerds = true
Noise.plannerStandoff = 45.0

-- May noise raise a sector's target population? Number, 1.0 = off
-- Something like 1.3 gives a slightly denser loud region over time
Noise.sectorTargetMultiplierCap = 1.0

-- 2. Point of interest board

Noise.POI = {
    -- How long a point stays interesting, in seconds, at the quietest publishable loudness
    -- Scaled up with loudness (see lifetimeLoudScale)
    lifetimeSeconds = 45,
    lifetimeLoudScale = 2.5,

    -- Max points on the board, world-wide. When full, the quietest point is evicted, not the oldest.
    maxPoints = 48,

    -- Merge radius in metres. Nearby noises merge into one point with the louder loudness and the newer timestamp.
    mergeRadius = 35.0,

    -- Quietest noise worth publishing to the world board
    -- Loudness is the noise's carry in metres (as computed by bs_emotes)
    minLoudness = 45.0,

    -- How far a point reaches, as a multiple of the noise's own carry (1.0 = as far as it travelled)
    -- Capped by maxReach so one loud noise cannot drain the whole map
    reachScale = 1.0,
    maxReach = 520.0,
}

-- 3. Investigate, mill, decay

Noise.Investigate = {
    -- Distance in metres that counts as arrived. Kept generous so walkers blocked by a fence or kerb still finish.
    arriveDistance = 6.0,

    -- Investigation ring: walkers are sent to a random spot between spreadMin and spreadMax metres from the point
    spreadMin = 8.0,
    spreadMax = 22.0,

    -- Milling: on arrival the walker takes short random legs around the point
    -- A leg is at most legDistance metres, the mill lasts millSeconds, and each walker rolls its own jitter
    millSeconds = 70,
    millJitter = 0.45,
    legDistance = 9.0,
    legPauseMs = { 1200, 4200 },

    maxCommitMs = 300000,

    -- May a walker be re-pointed while investigating? Only by a louder point, or by any point once it is milling
    -- Prevents steady fire from restarting every path
    repointNeedsLouder = true,
}

-- 4. Detection - the only way a player gets targeted

Noise.Detection = {
    -- Vision cone half-angle in degrees from the walker's forward vector. Line of sight is still required on top.
    visionHalfAngle = 80.0,

    -- Contact range in metres. Inside this a walker notices you regardless of facing or cone.
    contactRadius = 3.5,

    -- Sight range in metres by stance
    -- Absolute values, not multipliers (crouched 10, standing 50), so they are easy to tune
    sight = {
        standing = 50.0,
        crouched = 10.0,

        -- Prone is below crouched but not zero; it works at range, not as invisibility.
        prone    = 6.0,

        -- The senseRadius a type needs to get exactly the ranges above. Types with more see proportionally further.
        -- Changing this rescales every type, so tune the stance ranges instead
        referenceSenseRadius = 28.0,

        -- Contact radius for a crouched player standing behind a walker, in metres
        -- Small so sneaking past from behind works unless you are almost touching it
        crouchedContactRadius = 1.2,
    },

    -- Being hurt always acquires the player
    -- One of the few exceptions to 'noise never targets a player'; handled in cl_combat.lua
    damageAlwaysAcquires = true,
}

-- 5. Emergent hordes

Noise.Horde = {
    -- A horde is counted, not created. sv_poi.lua counts live records within radius of a POI that are heading for it
    enabled = true,
    radius = 90.0,
    count = 12,

    -- Cooldown in seconds before the same gathering is announced again.
    announceCooldownSeconds = 120,
}

-- 6. Materialisation gate (client) - see cl_sync.lua

-- Client gate: decides when this client calls CreatePed for a record entering its streaming radius, whoever created it
-- Separate from the spawner gate in cl_spawner.lua, which decides where the server creates a record
Noise.Materialise = {
    enabled = true,

    -- Inside this radius (metres) a walker is not created while the local player can see the spot
    -- Outside it, create freely
    holdRadius = 180.0,

    -- Hard floor in metres: nothing is ever created inside this radius, whatever the view test says.
    hardFloor = 80.0,  -- matches spawnFloor

    -- Keep at 0
    -- Any value above zero lets walkers appear right on top of the player. cl_sync only reads it to warn at boot.
    showAnywayRadius = 0.0,

    -- Sphere radius and centre height for the frustum test. Matches the spawner so both gates agree on 'visible'.
    viewSphereRadius = 1.6,
    viewHeight = 0.9,

    -- Max ms a record may be held before it is shown anyway
    -- Records outside hardFloor appear (counted as forced in /zwhy); inside hardFloor they are escalated instead (see escalateAfterMs)
    maxHoldMs = 9000,

    -- A record stuck inside hardFloor this long (ms) is reported to the server (bs:z:gated)
    escalateAfterMs = 12000,

    -- Ask the server to remove gated records. false just holds them on this client; use it if sv_registry has no bs:z:gated handler.
    escalate = true,

    -- How often held records are retried, in ms.
    retryMs = 250,

    -- Sort each drain by descending distance, so the horizon fills in before nearby walkers.
    farFirst = true,
}

-- 7. Appearance ledger - /zwhy

-- Ledger of the last N materialisations on this client (door, distance, in view). /zwhy prints it.
-- See cl_sync.lua
Noise.Ledger = {
    enabled = true,
    keep = 40,
}
