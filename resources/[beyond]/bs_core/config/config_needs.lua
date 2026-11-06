-- BeyondSurvival - hunger / thirst / stamina survival loop.

Config = Config or {}

Config.Needs = {
    enabled     = true,
    -- Seconds between need ticks on the client.
    tickRate    = 30,
    -- Percentage lost per tick at a 1.0 class multiplier.
    hungerPerTick = 0.55,
    thirstPerTick = 0.80,
    -- Extra drain multiplier while sprinting.
    sprintMultiplier = 1.75,
    -- Standing still drains slower.
    idleMultiplier = 0.35,
    afkMultiplier  = 0.10,
    afkAfter       = 120,
    -- Starving/dehydrated thresholds: below these values the player takes damage.
    starvingAt  = 20.0,
    dehydratedAt = 20.0,
    -- Health lost per tick while starving or dehydrated.
    damagePerTick = 6,
    -- Server persists needs at most this often (seconds).
    persistInterval = 120,
}

Config.Infection = {
    enabled       = true,
    -- Infection only ever goes up on its own; cures are server-side items.
    perTick       = 0.35,
    -- A zombie hit adds this much.
    perZombieHit  = 4.0,
    -- Above this, the screen starts to go wrong.
    symptomsAt    = 35.0,
    -- Above this, you lose health every tick.
    criticalAt    = 80.0,
    damagePerTick = 2,
    -- Fully infected. Death, and the character is flagged.
    fatalAt       = 100.0,
}

Config.Stamina = {
    enabled         = true,
    -- Native stamina is replaced by our own bar so classes can modify it.
    drainPerSecond  = 6.0,
    regenPerSecond  = 9.0,
    regenDelay      = 1.5,

    -- Being winded slows you down but never stops sprinting.
    windedAt        = 5.0,
    -- Speed at zero stamina as a fraction of a normal sprint. Slow, but a walker still cannot catch you on the flat.
    windedMoveRate  = 0.72,
}

Config.Death = {
    -- Seconds a downed player can be revived before bleeding out.
    bleedoutTime    = 300,
    respawnCost     = 0,
    -- Character keeps its inventory on death.
    keepInventory   = true,
    -- Nearest hospital-style respawn points.
    respawnPoints = {
        { x = 1839.5, y = 3672.9, z = 34.28, h = 210.0, label = 'Sandy Shores Medical' },
        { x = 297.5,  y = -584.6, z = 43.26, h = 70.0,  label = 'Pillbox Hill Medical' },
    },
}
