-- BeyondSurvival - bs_guard thresholds
-- Detection only: it logs to bs_guard_log and toasts online staff, never kicks or bans

Guard = {}

Guard.Settings = {
    enabled        = true,     -- (F1) master switch for every check
    staffExempt    = true,     -- (F1) staff (aces below) are never checked
    staffAces      = { 'bs.admin', 'bs.superadmin', 'bs.guard.bypass' },
    -- extra exempt identifiers ('license:xxxx', 'discord:xxxx') - testers etc.
    whitelist      = {},
    joinGraceMs    = 20000,    -- (F1) no movement checks this long after join / character spawn
    debug          = false,    -- print every Flag() to the server console
}

Guard.Alerts = {
    minConfidence  = 50,       -- (F1) detections below this are logged but not toasted
    cooldownMs     = 30000,    -- (F1) same player + same check: at most one log/toast per window
    toastMs        = 9000,
    keepDays       = 30,       -- (F1) rows older than this are pruned at start (0 = keep)
    listLimit      = 200,      -- rows the GUARD tab loads
}

Guard.Movement = {
    enabled         = true,    -- (F1)
    tickMs          = 1000,    -- sample rate
    teleportDist    = 150.0,   -- (F1) metres in one tick with no Allow() = teleport
    onFootMax       = 13.0,    -- (F1) m/s horizontal on foot (sprint ~7-9, boosters ~11)
    vehicleMax      = 85.0,    -- (F1) m/s land vehicles (~306 km/h)
    airMax          = 150.0,   -- (F1) m/s helis/planes
    speedStrikes    = 3,       -- (F1) consecutive over-limit ticks before flagging
    jumpRise        = 5.0,     -- (F1) metres of rise in one tick on foot = super jump
    noclipRise      = 1.6,     -- (F1) per-tick rise on foot that counts toward noclip
    noclipStrikes   = 4,       -- (F1) consecutive rising ticks (no vehicle) = noclip
}

Guard.God = {
    enabled         = true,    -- (F1)
    checkDelayMs    = 1200,    -- wait after a weaponDamageEvent before reading health
    minDamage       = 10,      -- ignore hits smaller than this
    strikes         = 4,       -- (F1) no-damage hits (in the window) before flagging
    windowMs        = 60000,
    maxHealth       = 200,     -- (F1) health above this is flagged (player max is 200)
    maxArmour       = 100,     -- (F1)
}

Guard.Weapons = {
    enabled         = true,    -- (F1)
    checkMs         = 5000,
    strikes         = 2,       -- (F1) consecutive checks holding an unowned weapon
    -- weapons that never map to an inventory item (tools, gadgets, fists)
    ignore = {
        'WEAPON_UNARMED', 'WEAPON_FLASHLIGHT', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN',
        'GADGET_PARACHUTE', 'WEAPON_BALL', 'WEAPON_SNOWBALL', 'WEAPON_FLARE', 'OBJECT',
    },
}

Guard.Explosions = {
    enabled         = true,    -- (F1)
    windowMs        = 10000,
    maxPerWindow    = 6,       -- (F1) explosions by one client per window
    -- explosion types that no legit item on this server produces (orbital, railgun, ...)
    suspiciousTypes = { 36, 37, 38, 59, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82 },
    ptfxPerWindow   = 25,      -- (F1) networked ptFx events per window
}

Guard.Entities = {
    enabled         = true,    -- (F1)
    windowMs        = 10000,
    maxVehicles     = 4,       -- (F1) script-created vehicles per client per window
    maxPeds         = 45,      -- (F1) peds (clients build zombies, so keep this high)
    maxObjects      = 60,      -- (F1) objects/props
    -- When true, any client-created vehicle/ped whose model is NOT listed in modelWhitelist is flagged
    -- Off by default: zombies and props are client-built
    whitelistOnly   = false,
    modelWhitelist  = {},
    -- always flagged (classic cheat-menu spawns)
    modelBlacklist  = {
        'hydra', 'lazer', 'rhino', 'khanjali', 'oppressor', 'oppressor2', 'deluxo', 'jet', 'cargoplane',
        'blimp', 'titan', 'avenger', 'strikeforce', 'prop_windmill_01', 'p_spinning_anus_s',
        'stt_prop_stunt_track_start', 'prop_beach_fire', 'prop_gas_tank_01a', 'prop_fnclink_05crnr1',
    },
}

Guard.Events = {
    enabled         = true,    -- (F1)
    windowMs        = 10000,
    defaultLimit    = 40,      -- (F1) per-event calls per window if not listed below
    -- net events counted per client. name = max calls per window.
    watch = {
        ['bs:callback:request']        = 120,
        ['bs:player:updatePosition']   = 30,
        ['bs:player:updateNeeds']      = 30,
        ['bs:chat:say']                = 15,
        ['bs:inventory:ammoRefund']    = 30,
        ['bs:inventory:wearWorn']      = 30,
        ['bs:weapons:reportAmmo']      = 60,
        ['bs:building:hit']            = 60,
        ['bs:building:ram']            = 20,
        ['bs:building:spike']          = 30,
        ['bs:gadgets:use']             = 20,
        ['bs:gadgets:deploy']          = 10,
        ['bs:boosters:use']            = 15,
        ['bs:drugs:request']           = 20,
        ['bs:world:noise']             = 80,
        ['bs:z:dmg']                   = 200,
        ['bs:z:hit']                   = 200,
        ['bs:zombies:bitten']          = 40,
        ['bs:extraction:playerKilled'] = 10,
        ['bs_config:rpc']              = 40,
    },
}

Guard.Economy = {
    enabled         = true,    -- (F1)
    pollMs          = 60000,
    moneyPerMinute  = 25000,   -- (F1) cash+bank gain in one minute that gets flagged
    itemsPerMinute  = 250,     -- (F1) items reported gained per minute (see ReportItem)
}
