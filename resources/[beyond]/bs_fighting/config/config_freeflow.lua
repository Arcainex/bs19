-- bs_fighting v3 - freeflow combat. Every number for the freeflow client and server lives here.
-- Clips are vanilla melee@* dicts. A pair whose clip does not load on a client is skipped there.

Freeflow = {}

Freeflow.Settings = {
    enabled          = true,
    -- Turns GTA's own melee off while fists or a melee weapon is out, so it never fights ours
    disableNative    = true,
    combatMs         = 5000,    -- "in combat" this long after your last swing or a walker swing at you

    -- stamina per action (bs_core needs); below minStamina you can't swing
    stamina          = { light = 6.0, heavy = 12.0, counter = 4.0, dodge = 8.0 },
    minStamina       = 8.0,

    -- heavy key: tap = heavy, hold this long = finisher when one is open
    heavyHoldMs      = 350,

    -- lock-on (right mouse)
    lockMode         = 'toggle',  -- 'toggle' (tap on / tap off) or 'hold'
    lockBreakRange   = 10.0,
    lockLosMs        = 1000,      -- lost line of sight this long breaks it
    lockTurnRate     = 10.0,      -- how fast you turn to face it (per second)
    lockCamera       = true,      -- camera stays on it, so sideways input circles it
    lockCamRate      = 6.0,
    lockColor        = { 240, 163, 92, 220 },

    -- target picker
    pickRange        = 7.0,
    pickDot          = 0.5,     -- input direction vs direction to the enemy
    idleRange        = 3.0,     -- no input: nearest in front of the camera within this
    idleDot          = 0.3,
    maxHeightGap     = 2.0,
    marker           = true,
    markerColor      = { 224, 140, 70, 170 },   -- bs_ui dossier accent

    -- distance bands (m)
    -- close-range clips only: past the clip gap we close in ourselves (short lunge), then strike
    lungeBand        = 3.6,     -- targets further than this get a swing in place, facing them

    -- lunge (own ped only)
    lungeMs          = 200,
    lungeBase        = 2.0,     -- max lunge distance at fighting level 0
    lungePerLevel    = 0.05,
    lungeMax         = 2.5,
    lungeFirstPerson = 1.2,     -- shorter in first person
    lungeStopGap     = 0.95,    -- default gap to the target when a clip has no pair offset
    lungeTimeoutMs   = 450,

    -- paired clips
    pairs            = true,    -- hold the walker and play its reaction clip on it
    pairScene        = false,   -- also lock both into one synced scene (off: its rotation twisted the player)
    -- Clips are checked by bones every frame for poseCheckMs. Clips matching Freeflow.SafePatterns start full
    -- body; any other clip starts as an upper-body layer, is checked 2 frames, then goes full body.
    -- A T-pose drops to the layer at once; a layer T-pose bans the clip (kept in KVP, shared by the server).
    poseCheckMs      = 300,
    controlWaitMs    = 250,     -- how long to wait for control before playing unpaired
    sceneCheckMs     = 120,     -- the scene must be playing on you by then, or we fall back
    maxAttackerShift = 0.5,     -- the scene is anchored on the walker; we may be shifted this much to fit it
    trackSpeed       = 3.0,     -- m/s we close in on a walker we couldn't hold, until impact
    blendOut         = 3.0,     -- every clip ends with this blend (never an instant clear)
    fallbackSnap     = 0.45,    -- unpaired: nudge the held walker to the clip gap if it is this close

    -- timing (fraction of the clip)
    lightPortion     = 0.72,    -- control comes back here so chains feel quick
    heavyPortion     = 0.85,
    lightSpeed       = 1.2,
    heavySpeed       = 1.0,
    impactAt         = 0.42,    -- default impact moment; clips can override with hitAt

    -- feel
    hitStopLight     = 60,
    hitStopHeavy     = 110,
    hitStopScale     = 0.2,
    shakeLight       = 0.04,
    shakeHeavy       = 0.10,
    shakeFirstPerson = 1.5,     -- shake multiplier in first person (the camera is never moved)
    comboResetMs     = 2500,

    -- stagger on walkers (bs_zombies SetStaggered)
    staggerLight     = 700,
    staggerHeavy     = 1400,
    staggerCounter   = 1800,

    -- counter: window before the walker's hit lands
    counterBase      = 0.45,
    counterPerLevel  = 0.03,
    counterMax       = 0.75,
    counterDamage    = true,    -- the counter blow also reports a hit

    -- dodge
    dodgeIframesMs   = 350,     -- bs_skills GrantEvade: walker claws miss while it runs
    dodgeCooldownMs  = 600,

    -- finishers: hold attack (heavyHoldMs) at the combo or on a staggered/downed walker
    finisherCombo    = 5,
    finisherLevel    = 2,       -- fighting level needed...
    finisherPerk     = 'fs_soldier',  -- ...or this perk ('' = level only)

    -- server side XP (rate limited there)
    xpLight          = 1,
    xpHeavy          = 2,
    xpCounter        = 3,
    xpFinisher       = 6,
    xpGapMs          = 900,

    debug            = false,
}

-- Default keys, rebindable in Settings > Key Bindings > FiveM
Freeflow.Keys = {
    light   = { mapper = 'MOUSE_BUTTON', key = 'MOUSE_LEFT' },
    heavy   = { mapper = 'keyboard',     key = 'R' },             -- tap heavy, hold for a finisher
    counter = { mapper = 'keyboard',     key = 'Q' },
    lock    = { mapper = 'MOUSE_BUTTON', key = 'MOUSE_RIGHT' },   -- lock on target
    dodge   = { mapper = 'keyboard',     key = 'SPACE' },
}

Freeflow.PvP = {
    enabled         = true,
    damage          = { light = 7, heavy = 14, counter = 10 },
    maxRange        = 3.4,
}

local UC = 'melee@unarmed@streamed_core'
local UV = 'melee@unarmed@streamed_variations'
local LW = 'melee@large_wpn@streamed_core'
local SW = 'melee@small_wpn@streamed_core'
local KN = 'melee@knife@streamed_core'

-- Each entry: { dict, plyr = attacker clip, victim = reaction clip or nil, hitAt = impact fraction }.
-- No victim clip: the walker gets a short stagger instead.
-- ground = solo clips on a downed target. dodge = solo clips on you.
Freeflow.Clips = {
    unarmed = {
        light = {
            { dict = UC, plyr = 'heavy_punch_a', victim = 'hit_heavy_punch_a', hitAt = 0.40 },
            { dict = UC, plyr = 'heavy_punch_b', victim = 'hit_heavy_punch_b', hitAt = 0.40 },
            { dict = UC, plyr = 'heavy_punch_c', victim = 'hit_heavy_punch_c', hitAt = 0.40 },
        },
        heavy = {
            { dict = UC, plyr = 'heavy_finishing_punch', victim = 'hit_heavy_finishing_move', hitAt = 0.45 },
            { dict = UC, plyr = 'kick_close_a', hitAt = 0.45 },
            { dict = UC, plyr = 'kick_close_b', hitAt = 0.45 },
        },
        counter = {
            l = { dict = UC, plyr = 'counter_attack_l', victim = 'hit_counter_attack_l', hitAt = 0.45 },
            r = { dict = UC, plyr = 'counter_attack_r', victim = 'hit_counter_attack_r', hitAt = 0.45 },
        },
        front = {
            { dict = UC, plyr = 'plyr_takedown_front_elbow',    victim = 'victim_takedown_front_elbow',    hitAt = 0.55 },
            { dict = UC, plyr = 'plyr_takedown_front_uppercut', victim = 'victim_takedown_front_uppercut', hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_front_headbutt', victim = 'victim_takedown_front_headbutt', hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_front_backslap', victim = 'victim_takedown_front_backslap', hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_front_cross_r',  victim = 'victim_takedown_front_cross_r',  hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_front_low_punch', victim = 'victim_takedown_front_low_punch', hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_front_slap',     victim = 'victim_takedown_front_slap',     hitAt = 0.55 },
        },
        rear = {
            { dict = UC, plyr = 'plyr_takedown_rear_lefthook', victim = 'victim_takedown_rear_lefthook', hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_rear_backhit',  victim = 'victim_takedown_rear_backhit',  hitAt = 0.55 },
            { dict = UV, plyr = 'plyr_takedown_rear_righthook', victim = 'victim_takedown_rear_righthook', hitAt = 0.55 },
        },
        ground = { dict = UC, front = 'ground_attack_0', left = 'ground_attack_90', back = 'ground_attack_180',
                   right = 'ground_attack_-90', spot = 'ground_attack_on_spot', hitAt = 0.55 },
        dodge = { dict = UC, l = 'dodge_generic_l', r = 'dodge_generic_r', c = 'dodge_generic_centre' },
    },
    large_wpn = {
        light = { { dict = LW, plyr = 'plyr_walking_attack', hitAt = 0.45 } },
        heavy = { { dict = LW, plyr = 'long_0_attack', hitAt = 0.50 }, { dict = LW, plyr = 'kick_close_a', hitAt = 0.45 } },
        counter = {
            l = { dict = LW, plyr = 'counter_attack_l', victim = 'hit_counter_attack_l', hitAt = 0.45 },
            r = { dict = LW, plyr = 'counter_attack_r', victim = 'hit_counter_attack_r', hitAt = 0.45 },
        },
        front = { { dict = LW, plyr = 'plyr_front_takedown_bat_headhit', victim = 'victim_front_takedown_bat_headhit', hitAt = 0.55 } },
        rear  = { { dict = LW, plyr = 'plyr_rear_takedown_bat_r_facehit', victim = 'victim_rear_takedown_bat_r_facehit', hitAt = 0.55 } },
        ground = { dict = LW, front = 'ground_attack_0', left = 'ground_attack_90', back = 'ground_attack_180',
                   right = 'ground_attack_-90', spot = 'ground_attack_on_spot', hitAt = 0.55 },
    },
    small_wpn = {
        light = { { dict = SW, plyr = 'plyr_walking_attack_a', hitAt = 0.45 } },
        heavy = { { dict = SW, plyr = 'small_melee_wpn_long_range_0', hitAt = 0.50 }, { dict = SW, plyr = 'kick_close_a', hitAt = 0.45 } },
        counter = {
            l = { dict = SW, plyr = 'counter_attack_l', hitAt = 0.45 },
            r = { dict = SW, plyr = 'counter_attack_r', hitAt = 0.45 },
        },
        front = { { dict = SW, plyr = 'plyr_front_takedown', victim = 'victim_front_takedown', hitAt = 0.55 } },
        rear  = { { dict = SW, plyr = 'plyr_rear_takedown',  victim = 'victim_rear_takedown',  hitAt = 0.55 } },
        ground = { dict = SW, front = 'ground_attack_0', left = 'ground_attack_90', back = 'ground_attack_180',
                   right = 'ground_attack_-90', spot = 'ground_attack_on_spot', hitAt = 0.55 },
    },
    knife = {
        light = { { dict = KN, plyr = 'plyr_walking_attack_a', hitAt = 0.45 }, { dict = KN, plyr = 'plyr_walking_attack_b', hitAt = 0.45 } },
        heavy = { { dict = KN, plyr = 'knife_long_range_0', hitAt = 0.50 }, { dict = KN, plyr = 'kick_close_a', hitAt = 0.45 } },
        counter = {
            l = { dict = KN, plyr = 'counter_attack_l', victim = 'hit_counter_attack_l', hitAt = 0.45 },
            r = { dict = KN, plyr = 'counter_attack_r', victim = 'hit_counter_attack_r', hitAt = 0.45 },
        },
        front = { { dict = KN, plyr = 'plyr_knife_front_takedown', victim = 'victim_knife_front_takedown', hitAt = 0.55 } },
        rear  = { { dict = KN, plyr = 'plyr_knife_rear_takedown',  victim = 'victim_knife_rear_takedown',  hitAt = 0.55 } },
        ground = { dict = KN, front = 'ground_attack_0', left = 'ground_attack_90', back = 'ground_attack_180',
                   right = 'ground_attack_-90', spot = 'ground_attack_on_spot', hitAt = 0.55 },
    },
}

-- Reaction a player plays on their own client when hit (PvP), by attack kind
Freeflow.PlayerReact = {
    light   = { dict = UC, clip = 'hit_heavy_punch_a', ms = 700 },
    heavy   = { dict = UC, clip = 'hit_heavy_finishing_move', ms = 1100 },
    counter = { dict = UC, clip = 'hit_counter_attack_r', ms = 1000 },
}

-- v1 weapon class names -> v3 clip tables. Classes without a dodge entry use the unarmed one.
Freeflow.ClassMap = { fists = 'unarmed', one = 'small_wpn', two = 'large_wpn', knife = 'knife' }

-- Clips checked with /ffcliptest: 'dict/clip' = flag that plays them full body without a T-pose
-- (0, 2, 48 = upper body over movement, or 'adv'), or false to never use them. /ffcliptest prints these lines.
Freeflow.SafeClips = {
}

-- Clip names believed full-body safe; everything else is "test first" (see poseCheckMs)
Freeflow.SafePatterns = {
    '^heavy_punch_', '^counter_attack_', '^dodge_generic_', '^ground_attack_',
    '^plyr_takedown_', '^plyr_front_takedown', '^plyr_rear_takedown', '^plyr_knife_front_takedown', '^plyr_knife_rear_takedown',
}
