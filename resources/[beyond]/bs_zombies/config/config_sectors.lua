-- bs_zombies - sector grid defaults. Per-sector overrides are saved by the panel into sector_overrides.json.

Sectors = {}

Sectors.Settings = {
    -- Master switch for the sector spawner
    -- Off: the node simulation places every walker and the director loop in sv_registry.lua skips its spawn pass
    enabled = false,

    -- Metres per side (250 = a couple of city blocks)
    -- Changing this renumbers every sector, so delete sector_overrides.json afterwards
    size = 250.0,

    -- How close a player must be for a sector to wake, in metres, measured to the sector's nearest edge (not its centre)
    activateWithin = 800.0,

    -- Where grid references count from
    -- A-1 is the south-west corner of the playable area; letters run east, numbers run north
    origin = { x = -4000.0, y = -4000.0 },

    -- How long a dead walker stays dead, per sector (30 minutes by default)
    -- A kill adds a debt that suppresses one slot until it expires; the sector still wants its full target
    respawnSeconds = 1800,

    -- Noise
    -- Accumulates per sector and decays. noiseFull is the amount that counts as as-loud-as-it-gets (sector at maxMultiplier), linear in between.
    noiseFull       = 30.0,
    maxMultiplier   = 3.0,
    -- Points bled off per minute. A sector goes from full to quiet in about five minutes of silence.
    noiseDecayPerMinute = 6.0,

    -- What each kind of noise is worth. Suppressed fire is worth a fraction of unsuppressed.
    noiseWeights = {
        gunshot   = 3.0,
        silenced  = 0.6,
        horn      = 2.0,
        engine    = 0.35,
        -- Motorbikes, muscle cars, off-roaders
        -- Sent by bs_emotes' cl_vehiclenoise; a kind with no price here is ignored
        engine_loud = 0.6,
        explosion = 12.0,
        scream    = 1.5,

        -- Work noise
        -- Worth less per event than a gunshot, but it repeats every couple of seconds, so a long dig adds up
        mining    = 0.8,
        chopping  = 0.5,
        digging   = 0.3,

        -- Noise kinds sent by bs_emotes
        -- The director rejects any kind that is not priced here, so every kind needs a weight
        whistle   = 2.2,
        shout     = 1.6,
        sprint    = 0.15,
        melee     = 0.25,

        -- Vehicles
        -- See the matching radii in bs_emotes' config_emotes.lua: radius is how far it pulls, this is how much it breeds
        heli        = 12.0,
        engine_loud = 1.1,
    },

    -- Baseline population of a sector, per sector (so it scales with sector size)
    -- Multiplied by zone density
    baseTarget = 3,

    -- Hard cap per sector however loud it gets. Keeps one street corner from costing client frames.
    maxTarget  = 14,

    -- How often the sector sweep runs, in ms. Sectors are cheap to walk, so this can be slow.
    tick = 1500,
}

-- Named sectors. Cosmetic only; the admin menu falls back to the grid reference (e.g. M-14) for the rest.
-- Keys are grid coordinates 'cx:cy' where cx = floor(x / size)
Sectors.Names = {
    -- ['1:3'] = 'Sandy Shores',
}

-- Per-sector overrides set in code. The panel writes sector_overrides.json, which wins over this table.
-- Use this for sectors you want fixed, e.g. a spawn-free starter area.
Sectors.Overrides = {
    -- ['1:3'] = { enabled = false },
}

-- Bounded noise response. A noise opens a response: a located, expiring permission for the world to react.
-- While open, more noise only refreshes a small alert allowance

Sectors.NoiseResponse = {
    -- Off brings back unbounded noise spawning. This switch changes pacing, so it is left to the server owner.
    enabled = true,

    -- Size of one response, in metres
    -- Noises within this radius of each other count as the same event. 220 is just under Streaming.fullDistance
    radius = 220.0,

    -- Hard cap: how many walkers one noise event may spawn
    -- Once spent, the response closes and the area goes on cooldown. 6 is a group, not a tide.
    spawnBudget = 24,

    -- Seconds a response stays open if its budget is never spent (90 lets herds walk in from the edge of earshot).
    openSeconds = 90,

    -- Cooldown in seconds after a response ends
    -- Noise in this area still feeds sector noise
    cooldownSeconds = 120,

    -- How many times one open response may re-alert the herds
    -- Alerting on every shot would pin herds to the player, so keep this low
    alertsPerResponse = 3,

    -- Seconds between two of those alerts, so a magazine does not spend the whole allowance at once.
    alertMinGapSeconds = 8,

    -- How many times one open response may lure unhosted records (Registry.Lure)
    -- Keep low, same reason as the alerts
    luresPerResponse = 2,
    lureMinGapSeconds = 10,
}
