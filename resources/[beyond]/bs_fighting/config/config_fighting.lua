-- bs_fighting - Dying Light style melee. Keys, styles, moves, weapon classes and limits. F1 > Fighting has the main numbers.
-- Every clip below is from the vanilla game files (melee@* and the casino brawl sets). /fightanims re-checks them in game.

Fighting = {}

Fighting.Settings = {
    enabled             = true,
    -- While unarmed or holding a melee weapon our moves replace the vanilla melee and the aim lock-on.
    replaceVanillaMelee = true,
    defaultStyle        = 'untrained',
    switchCooldownMs    = 1200,

    holdHeavyMs         = 240,     -- hold attack this long and it becomes a heavy
    chargeFullMs        = 900,     -- fully charged heavy
    comboWindowMs       = 650,

    staminaLight        = 5.0,
    staminaHeavy        = 14.0,    -- at full charge
    staminaKick         = 10.0,
    staminaStomp        = 6.0,
    staminaBlockHit     = 7.0,
    tiredAt             = 20.0,    -- below this: slow, weak swings
    tiredSpeed          = 0.72,
    tiredDamage         = 0.55,

    hitHalfAngle        = 55.0,
    contactRadius       = 0.5,     -- tolerance around the visible hand/foot/weapon and victim bones
    contactWindowMs     = 180,     -- sample a short window around the animation impact

    blockReduce         = 0.30,
    parryWindowMs       = 180,
    parryPerLevelMs     = 5,
    parryMaxMs          = 360,
    counterWindowMs     = 800,
    counterBonus        = 1.6,

    takedownRange       = 1.6,
    takedownBehindDot   = -0.3,
    takedownCooldownMs  = 1500,

    stompRange          = 2.2,
    stompMs             = 1800,    -- a knocked down target can be stomped this long

    -- feel
    hitStopLight        = 45,      -- ms the swing freezes on contact
    hitStopHeavy        = 95,
    hitStopKick         = 80,
    timeScaleOnHeavy    = true,    -- short slow-down on heavies and kicks that connect
    timeScale           = 0.35,
    timeScaleMs         = 70,
    shakeLight          = 0.025,
    shakeHeavy          = 0.09,
    sound               = true,
    soundVolume         = 0.6,

    damagePerLevel      = 0.015,
    staminaPerLevel     = 0.01,

    xpZombieStrike      = 2,
    xpZombieKill        = 10,
    xpPlayerHit         = 1,
    xpSpar              = 150,
    xpTrial             = 400,

    debug               = false,
}

-- Default keys, rebindable in Settings > Key Bindings > FiveM. Checked against every RegisterKeyMapping in resources/:
-- R is only the vanilla melee/reload key, and reload means nothing while unarmed or holding a melee weapon.
Fighting.Keys = {
    attack = { mapper = 'MOUSE_BUTTON', key = 'MOUSE_LEFT' },    -- tap light, hold heavy
    kick   = { mapper = 'keyboard',     key = 'R' },
    block  = { mapper = 'MOUSE_BUTTON', key = 'MOUSE_RIGHT' },   -- hold to guard, tap just before a hit to parry
    style  = { mapper = 'keyboard',     key = '' },              -- unbound by default, /fightstyle works too
}

Fighting.PvP = {
    enabled          = true,
    blockInSafezones = true,
    maxDamagePerHit  = 30,
    maxHitsPerSecond = 4,
    maxDamagePer10s  = 150,
    maxRange         = 3.4,
    takedownDamage   = 40,
    stompDamage      = 25,
    chokeTicks       = 4,
    chokeDamage      = 6,
    chokeMs          = 4200,
}

Fighting.Zombies = {
    enabled        = true,
    heavyHits      = 2,       -- a full charge heavy reports this many hits
    stompKills     = true,    -- stomping a downed walker is a kill (head hit, same rule as a headshot)
    takedowns      = true,    -- Soldier: attack from behind kills an unaware walker (bs_zombies execution check)
    knockdowns     = true,
    grabEscape     = true,
}

Fighting.Grab = {
    baseWindowMs  = 160,
    perLevelMs    = 10,
    maxWindowMs   = 420,
    guardChance   = 0.20,
    guardPerLevel = 0.025,
    guardMax      = 0.70,
    evadeMs       = 650,
    staminaCost   = 8.0,
}

-- Optional custom animation pack: move id -> { dict = '', clip = '' }. Missing entries use the built-in clips.
Fighting.CustomAnims = { enabled = false, map = {} }

local UC = 'melee@unarmed@streamed_core'
local UV = 'melee@unarmed@streamed_variations'
local UB = 'melee@unarmed@streamed_background'
local LW = 'melee@large_wpn@streamed_core'
local SW = 'melee@small_wpn@streamed_core'
local KN = 'melee@knife@streamed_core'
local BT = 'anim@amb@casino@brawl@fights@bar_throw@'
local HL = 'anim@amb@casino@brawl@fights@headlock@'

-- Moves. clip = { dict, name }. portion = how much of the clip plays before control returns.
-- hitAt = fraction of the played part where the hit lands. react = what the target does:
-- 'stumble' (short flinch), 'stagger' (longer, breaks their swing), 'down' (ragdoll), 'throw' (ragdoll + big push).
-- dmg is the PvP base (players have 100 health), zHits = hits reported on a walker.
Fighting.Moves = {
    -- unarmed
    jab         = { clip = { UC, 'short_0_punch' },              portion = 0.75, hitAt = 0.40, dmg = 5,  zHits = 1, react = 'stumble' },
    cross       = { clip = { UC, 'long_0_punch' },               portion = 0.75, hitAt = 0.45, dmg = 6,  zHits = 1, react = 'stumble' },
    jab_finish  = { clip = { UC, 'light_finishing_punch' },      portion = 0.85, hitAt = 0.45, dmg = 8,  zHits = 1, react = 'stagger' },
    elbow       = { clip = { UC, 'plyr_takedown_front_elbow' },  portion = 0.60, hitAt = 0.45, dmg = 7,  zHits = 1, react = 'stagger' },
    headbutt    = { clip = { UV, 'plyr_takedown_front_headbutt' }, portion = 0.60, hitAt = 0.50, dmg = 9, zHits = 1, react = 'stagger' },
    shove       = { clip = { UC, 'shove' },                      portion = 0.90, hitAt = 0.40, dmg = 2,  zHits = 0, react = 'down', push = 6.0 },
    heavy_a     = { clip = { UC, 'heavy_punch_a' },              portion = 0.80, hitAt = 0.50, dmg = 12, zHits = 2, react = 'stagger' },
    haymaker    = { clip = { UV, 'heavy_punch_b_var_1' },        portion = 0.85, hitAt = 0.50, dmg = 16, zHits = 2, react = 'down', push = 4.0 },
    uppercut    = { clip = { UC, 'plyr_takedown_front_uppercut' }, portion = 0.65, hitAt = 0.45, dmg = 14, zHits = 2, react = 'down', push = 2.0 },
    finisher    = { clip = { UC, 'heavy_finishing_punch' },      portion = 0.85, hitAt = 0.50, dmg = 16, zHits = 2, react = 'down', push = 3.0 },
    counter     = { clip = { UC, 'counter_attack_r' },           portion = 0.80, hitAt = 0.45, dmg = 12, zHits = 2, react = 'stagger' },
    kick_push   = { clip = { UC, 'kick_close_b' },               portion = 0.85, hitAt = 0.45, dmg = 6,  zHits = 1, react = 'stagger', push = 2.5 },
    kick_low    = { clip = { UC, 'kick_close_a' },               portion = 0.85, hitAt = 0.45, dmg = 7,  zHits = 1, react = 'stagger', region = 'leg' },
    dropkick    = { clip = { UC, 'kick_far_a' },                 portion = 0.85, hitAt = 0.45, dmg = 10, zHits = 1, react = 'down', push = 7.0, reach = 2.4 },
    throw       = { clip = { BT, 'miscreant_bar_fight_throw' },  portion = 0.55, hitAt = 0.55, dmg = 6,  zHits = 0, react = 'throw', push = 11.0 },
    choke       = { clip = { HL, 'headlock_loop_mp_m_brawler' }, portion = 1.00, hitAt = 0.20, dmg = 0,  zHits = 0, react = 'choke', loop = true },
    stomp       = { clip = { UC, 'ground_attack_0' },            portion = 0.80, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
    takedown    = { clip = { UC, 'plyr_stealth_kill_unarmed_a' }, portion = 0.85, hitAt = 0.55, dmg = 0, zHits = 0, react = 'none' },
    -- melee weapons, by class
    w1_light    = { clip = { SW, 'small_melee_wpn_short_range_0' }, portion = 0.80, hitAt = 0.45, dmg = 8,  zHits = 1, react = 'stumble' },
    w1_heavy    = { clip = { SW, 'small_melee_wpn_long_range_0' },  portion = 0.80, hitAt = 0.50, dmg = 15, zHits = 2, react = 'stagger' },
    w1_kick     = { clip = { SW, 'kick_close_a' },               portion = 0.85, hitAt = 0.45, dmg = 6,  zHits = 1, react = 'down', push = 4.0 },
    w1_stomp    = { clip = { SW, 'ground_attack_on_spot' },      portion = 0.80, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
    w1_takedown = { clip = { SW, 'plyr_rear_takedown' },         portion = 0.85, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
    w2_light    = { clip = { LW, 'short_0_attack' },             portion = 0.80, hitAt = 0.50, dmg = 11, zHits = 1, react = 'stagger', reach = 2.3 },
    w2_heavy    = { clip = { LW, 'long_0_attack' },              portion = 0.85, hitAt = 0.55, dmg = 20, zHits = 2, react = 'down', push = 4.0, reach = 2.5 },
    w2_kick     = { clip = { LW, 'kick_close_a' },               portion = 0.85, hitAt = 0.45, dmg = 6,  zHits = 1, react = 'down', push = 4.0 },
    w2_stomp    = { clip = { LW, 'ground_attack_on_spot' },      portion = 0.80, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
    w2_takedown = { clip = { LW, 'plyr_rear_takedown_bat_r_facehit' }, portion = 0.85, hitAt = 0.55, dmg = 0, zHits = 0, react = 'none' },
    kn_light    = { clip = { KN, 'knife_short_range_0' },        portion = 0.75, hitAt = 0.40, dmg = 9,  zHits = 1, react = 'stumble', reach = 1.6 },
    kn_heavy    = { clip = { KN, 'knife_long_range_0' },         portion = 0.80, hitAt = 0.50, dmg = 16, zHits = 2, react = 'stagger', reach = 1.7 },
    kn_kick     = { clip = { KN, 'kick_close_a' },               portion = 0.85, hitAt = 0.45, dmg = 6,  zHits = 1, react = 'down', push = 4.0 },
    kn_stomp    = { clip = { KN, 'ground_attack_on_spot' },      portion = 0.80, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
    kn_takedown = { clip = { KN, 'plyr_knife_rear_takedown' },   portion = 0.85, hitAt = 0.55, dmg = 0,  zHits = 0, react = 'none' },
}

-- Poses and reactions (not attacks)
Fighting.Poses = {
    guard     = { UB, 'idle' },                         -- fists up, played on the upper body while blocking
    recoil    = { UC, 'recoil_heavy_left' },            -- your swing got parried
    hit_front = { LW, 'melee_damage_front' },
    hit_back  = { UC, 'melee_damage_back' },
    hit_left  = { UC, 'melee_damage_left' },
    hit_right = { UC, 'melee_damage_right' },
    hit_heavy = { UC, 'hit_heavy_punch_a' },
    choked    = { HL, 'headlock_loop_mp_m_pedestrian' },
}

-- Weapon classes: reach and speed differ, each has its own light/heavy/kick/stomp/takedown.
Fighting.WeaponClasses = {
    fists = { reach = 1.8, speed = 1.0 },
    one   = { reach = 2.0, speed = 1.0,  light = 'w1_light', heavy = 'w1_heavy', kick = 'w1_kick', stomp = 'w1_stomp', takedown = 'w1_takedown' },
    two   = { reach = 2.4, speed = 0.82, light = 'w2_light', heavy = 'w2_heavy', kick = 'w2_kick', stomp = 'w2_stomp', takedown = 'w2_takedown' },
    knife = { reach = 1.6, speed = 1.2,  light = 'kn_light', heavy = 'kn_heavy', kick = 'kn_kick', stomp = 'kn_stomp', takedown = 'kn_takedown' },
}
Fighting.WeaponClassOf = {
    WEAPON_KNIFE = 'knife', WEAPON_DAGGER = 'knife', WEAPON_SWITCHBLADE = 'knife', WEAPON_BOTTLE = 'knife',
    WEAPON_HAMMER = 'one', WEAPON_WRENCH = 'one', WEAPON_NIGHTSTICK = 'one', WEAPON_FLASHLIGHT = 'one',
    WEAPON_HATCHET = 'one', WEAPON_MACHETE = 'one', WEAPON_STONE_HATCHET = 'one',
    WEAPON_BAT = 'two', WEAPON_CROWBAR = 'two', WEAPON_GOLFCLUB = 'two', WEAPON_POOLCUE = 'two', WEAPON_BATTLEAXE = 'two',
    -- knuckle dusters fight like fists
    WEAPON_KNUCKLE = 'fists',
}

-- Styles. Each one changes the moves and the feel, not only numbers.
--   chain   = light attacks in order (unarmed), heavy = held attack, kick = kick key
--   feel    = anim speed, extra hit-stop and shake multipliers
--   guard   = share of damage a block lets through, parry = parry window multiplier
--   parryDo = what a parry does: 'counter' (next attack is a counter punch), 'disarm', 'shove'
Fighting.Styles = {
    untrained = { order = 0, free = true, icon = 'fist',
        chain = { 'jab', 'cross' }, heavy = 'heavy_a', kick = 'kick_push',
        speed = 0.95, dmg = 0.85, stamina = 1.15, hitStop = 1.0, shake = 1.0, guard = 0.40, parry = 0.8, parryDo = 'none' },
    brawler = { order = 1, basic = true, minLevel = 0, icon = 'bottle',
        chain = { 'cross', 'elbow', 'headbutt' }, heavy = 'haymaker', kick = 'dropkick',
        speed = 0.88, dmg = 1.20, stamina = 1.10, hitStop = 1.5, shake = 1.6, guard = 0.20, parry = 0.6, parryDo = 'shove',
        weaponDown = true },          -- weapon heavies always knock down
    boxer = { order = 2, basic = true, minLevel = 0, icon = 'glove',
        chain = { 'jab', 'cross', 'jab', 'jab_finish' }, heavy = 'uppercut', kick = 'kick_push',
        speed = 1.25, dmg = 0.95, stamina = 0.85, hitStop = 0.7, shake = 0.8, guard = 0.35, parry = 1.6, parryDo = 'counter' },
    soldier = { order = 3, minLevel = 4, icon = 'knife',
        chain = { 'jab', 'elbow' }, heavy = 'heavy_a', kick = 'kick_low',
        speed = 1.05, dmg = 1.0, stamina = 0.95, hitStop = 1.0, shake = 1.0, guard = 0.30, parry = 1.1, parryDo = 'disarm',
        takedowns = true, knife = 1.25 },
    grappler = { order = 4, minLevel = 6, icon = 'grip',
        chain = { 'jab', 'shove' }, heavy = 'throw', kick = 'shove',
        speed = 0.95, dmg = 0.9, stamina = 0.95, hitStop = 1.2, shake = 1.3, guard = 0.30, parry = 1.0, parryDo = 'shove',
        choke = true, grab = 1.35 },
}

-- Trainers. Brawler and Boxer in every faction safezone, Soldier and Grappler hidden (no blip).
Fighting.Trainers = {
    { id = 'mil_coach', zone = 'military',  offset = { 9.0, -6.0 }, model = 's_m_y_marine_01',    heading = 90.0,  teaches = { 'brawler', 'boxer' }, blip = true },
    { id = 'reb_coach', at = { 1000.0, -318.0, 67.0 },              model = 'g_m_y_salvagoon_01', heading = 200.0, teaches = { 'brawler', 'boxer' }, blip = true },
    { id = 'civ_coach', zone = 'civilians', offset = { -8.0, 7.0 }, model = 'a_m_y_musclbeac_01', heading = 0.0,   teaches = { 'brawler', 'boxer' }, blip = true },
    { id = 'bik_coach', zone = 'bikers',    offset = { 6.0, 8.0 },  model = 'g_m_y_lost_01',      heading = 270.0, teaches = { 'brawler', 'boxer' }, blip = true },
    { id = 'cqc_vet',   at = { 3537.0, 3668.0, 28.1 },              model = 's_m_y_blackops_01',  heading = 170.0, teaches = { 'soldier' } },   -- Humane Labs yard
    { id = 'grappler',  at = { 1859.0, 3746.0, 33.0 },              model = 'a_m_m_salton_01',    heading = 210.0, teaches = { 'grappler' } },  -- Sandy Shores
}

Fighting.Spar = {
    hits         = 8,
    hitsAdvanced = 12,
    seconds      = 90,
    loseAt       = 35,
    minGapMs     = 250,
    defenseMod   = 4.0,
    range        = 30.0,
}

Fighting.Trials = {
    basicKills    = 10,
    advancedKills = 15,
    creditMs      = 2500,
    money         = 250,
}
