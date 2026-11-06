-- bs_parkour config. Most numbers are F1 settings (bs_config, category Parkour).

Parkour = {}

Parkour.Settings = {
    enabled          = true,
    adminAces        = { 'bs.admin', 'bs.superadmin' },
    -- Space near an obstacle picks the move. The dedicated key (wall run / slide) is remappable in GTA settings.
    contextJump      = true,
    -- Mouse 4 by default (C is GTA's look-back). Players rebind it under Settings > Key Bindings > FiveM.
    moveKeyDevice    = 'MOUSE_BUTTON',
    moveKey          = 'MOUSE_EXTRABTN1',
    -- The move key also vaults / climbs when an obstacle is ahead (off = it only slides and wall-bounces)
    moveKeyObstacles = true,
    debug            = false,    -- print why an obstacle move fell back (F8)
    probeMs          = 90,       -- how often the obstacle probe runs while on foot
    -- Shooting
    noFireDuringMove = true,
    aimPenaltyMs     = 900,      -- camera shake after a move, shortened by perks
    aimPenaltyShake  = 0.35,
    -- Carry weight only slows moves (never blocks them). At full load moves take this much longer.
    weightSlowAtFull = 0.35,
    -- Passive fall damage reduction, per parkour level, capped
    fallReducePerLevel = 0.025,
    fallReduceMax      = 0.55,
    fallSafeHeight     = 3.5,    -- metres before a fall hurts at all
    fallHpPerMetre     = 9.0,    -- damage per metre past the safe height, before reduction
    rollMinHeight      = 2.5,
    rollMaxHeight      = 9.0,
    rollWindowMs       = 450,    -- press Space or the move key this close to landing to roll
    -- XP
    xpMult           = 1.0,
    xpPerMinuteCap   = 160,
    -- Escapes: a walker within chaseRange for chaseMinSeconds is a chase, none within lostRange for lostSeconds breaks it
    escapeEnabled    = true,
    escapeXp         = 40,
    chaseRange       = 14.0,
    chaseMinSeconds  = 4,
    lostRange        = 35.0,
    lostSeconds      = 6,
    escapeMinDistance = 35.0,
    escapeCooldown   = 60,
    -- Trainers
    basicCost        = 150,      -- cash
    advancedCost     = 600,
    advancedLevel    = 5,        -- parkour level the advanced trainers ask for
    advancedNeedsTrial = true,   -- the basic trainers' rooftop trial must be done first
}

-- Per move: enabled, stamina cost (0 = free), skill XP, cooldown (ms)
Parkour.Moves = {
    vault     = { enabled = true, stamina = 0,  xp = 4,  cooldown = 900 },
    climb     = { enabled = true, stamina = 8,  xp = 6,  cooldown = 1200 },
    climbHigh = { enabled = true, stamina = 16, xp = 10, cooldown = 1800 },
    slide     = { enabled = true, stamina = 0,  xp = 4,  cooldown = 1400 },
    bonnet    = { enabled = true, stamina = 0,  xp = 4,  cooldown = 900 },   -- slide across a car hood
    step      = { enabled = true, stamina = 0,  xp = 0,  cooldown = 350 },   -- auto step up, no XP
    roll      = { enabled = true, stamina = 0,  xp = 6,  cooldown = 900 },
    wallrun   = { enabled = true, stamina = 18, xp = 10, cooldown = 2200 },
    walljump  = { enabled = true, stamina = 12, xp = 12, cooldown = 700 },
    ledge     = { enabled = true, stamina = 10, xp = 8,  cooldown = 1200 },
    shimmy    = { enabled = true, stamina = 0,  xp = 1,  cooldown = 350 },
}

-- Which trainer tier unlocks a move
Parkour.MoveTier = {
    vault = 'basic', climb = 'basic', climbHigh = 'basic', slide = 'basic', roll = 'basic', bonnet = 'basic',
    wallrun = 'advanced', walljump = 'advanced', ledge = 'advanced', shimmy = 'advanced',
}
Parkour.TierPerk = { basic = 'pk_basics', advanced = 'pk_advanced' }

Parkour.Tuning = {
    ledgeDrainPerSec = 3.0,      -- stamina while hanging
    ledgeClimbCost   = 8,
    vaultMax         = 1.35,     -- metres: below this a thin obstacle is vaulted
    climbMax         = 2.4,      -- native climb height
    climbHighMax     = 3.2,      -- our own climb, raised by High reach
    hangMax          = 4.2,      -- a ledge up to this height can be grabbed (advanced)
    wallRunSeconds   = 0.9,
    wallRunSpeed     = 7.5,
    wallJumpPush     = 6.5,
    wallJumpLift     = 6.0,
    slideSeconds     = 0.75,
    slideSpeed       = 9.0,
    shimmyStep       = 0.45,
}

-- Animations. GTA clips by default; the first entry whose dict and clip exist is used.
-- A custom pack goes in Parkour.CustomAnims: if the dict is streamed on the server, its clips are tried first.
Parkour.Anims = {
    climbHigh = { { dict = 'move_climb', clip = 'standclimbup_295_low' }, { dict = 'move_climb', clip = 'standclimbup_220_high' }, { dict = 'move_climb', clip = 'standclimbup_180_high' } },
    slide     = { { dict = 'missheistfbi3b_ig6_v2', clip = 'rubble_slide_gunman' }, { dict = 'move_jump', clip = 'dive_start_run' }, { dict = 'move_strafe@roll', clip = 'combatroll_fwd_p1_00' } },
    roll      = { { dict = 'move_fall', clip = 'land_roll' }, { dict = 'move_strafe@roll', clip = 'combatroll_fwd_p1_00' } },
    wallrun   = { { dict = 'move_m@brave', clip = 'run' }, { dict = 'move_jump', clip = 'jump_launch_r' } },
    wallup    = { { dict = 'laddersbase', clip = 'climb_up' }, { dict = 'move_climb', clip = 'standclimbup_180_low' }, { dict = 'move_m@brave', clip = 'run' } },
    walljump  = { { dict = 'anim@arena@celeb@flat@solo@no_props@', clip = 'flip_a_player_a' }, { dict = 'move_jump', clip = 'jump_launch_l_to_skydive' }, { dict = 'move_strafe@roll', clip = 'combatroll_fwd_p1_00' } },
    ledge     = { { dict = 'missfam1_yachtbattleonyacht02_', clip = 'onboom_twohand_hang_idle' }, { dict = 'missfbi1', clip = 'ledge_loop' } },
}
-- "Parkour animations" pack by BoringNeptune (Mixamo-based, second pack by QwertNikol), gta5-mods.com/misc/parkour-animations.
-- Drop its .ycd files in bs_parkour/stream/; clips are used only when the dict streams in.
Parkour.CustomAnims = {
    { dict = 'parkour_part_2@anim', clips = { climbHigh = 'ledge_jump_up', wallup = 'ledge_jump_up_power', wallrun = 'wallrun_right_side', ledge = 'ledge_idle', roll = 'diveroll_r' } },
    { dict = 'parkour@anims', clips = { slide = 'slide', walljump = 'wall_flip', climbHigh = 'big_jump_01' } },
}

-- Parkour v3: vault, climb, high climb, car hood slide and auto step. Everyone can do the basic moves;
-- AdvancedMoves need parkour level >= advancedLevel or the advanced perk (pk_advanced). Server checks the same.
Parkour.Pk3 = {
    probeMs        = 50,     -- obstacle probe interval while on foot
    coyoteMs       = 150,    -- Space still triggers a move this long after the obstacle was last seen / the ground was left
    bufferMs       = 120,    -- Space pressed this early still triggers once the obstacle is seen
    jumpWindowMs   = 300,    -- a move can still take over this long into a normal jump (for the buffer)
    reachBase      = 1.0,    -- probe reach in metres, plus reachPerSpeed per m/s of speed, capped at reachMax
    reachPerSpeed  = 0.12,
    reachMax       = 1.9,
    autoStep       = true,   -- step up small obstacles without input
    stepMin        = 0.30,   -- below this GTA steps on its own
    stepMax        = 0.50,
    stepMs         = 220,
    vaultDepth     = 1.0,    -- deepest obstacle vaulted over; deeper ones are climbed onto
    vaultMaxDrop   = 2.5,    -- deepest drop allowed on the far side of a vault
    vaultApex      = 0.35,   -- how high the body passes over the top
    bonnetMin      = 0.6,    -- car hood height band for the hood slide
    bonnetMax      = 1.25,
    bonnetDepth    = 3.2,
    bonnetApex     = 0.3,
    bonnetSide     = 'auto', -- 'auto', 'l' or 'r'
    confirmMs      = 250,    -- how long to wait for the clip to start before giving up (nothing moves before that)
    timeoutPadMs   = 600,    -- hard stop = clip length + this
    retries        = 1,      -- a clip dropped mid-move is restarted this many times, then the move finishes quickly
    firstPerson    = 'clip', -- 'clip' or 'native' (first person uses GTA's own climb)
    firstPersonAlign = false, -- turn the body to face the obstacle in first person (turns the camera too)
    useNative      = false,  -- safe mode: every obstacle move uses GTA's own climb
    -- Vault and climb use GTA's own climb task (TaskClimb): its clips are layered by the task with IK and
    -- play as a bare T-pose when started on their own. true = try our own clips first (only verified ones).
    ownVaultClimb  = false,
    poseCheckMs    = 160,    -- after a clip starts, wait this long and check the body is not in a T-pose
    -- Clips verified to animate the whole body when played on their own, 'dict/clip' = flag
    -- (a TaskPlayAnim flag number, or 'adv' for TaskPlayAnimAdvanced). Only these are used by the high climb
    -- and the hood slide; without any, those moves use GTA's own climb. Fill from /pkcliptest <dict> <clip>.
    Standalone     = {
    },
    advancedLevel  = 3,
    AdvancedMoves  = { climbHigh = true, walljump = true, wallrun = true, ledge = true, shimmy = true },
    -- Base game clips (move_climb). The first one that exists is used.
    VaultClips = {
        run   = { { dict = 'move_climb', clip = 'standvault_80' }, { dict = 'move_climb', clip = 'standvault_20' } },
        stand = { { dict = 'move_climb', clip = 'standvault_80' }, { dict = 'move_climb', clip = 'standvaultclose_20' } },
    },
    -- Climbs by height label; the band closest to the obstacle height is used. run = arriving above 3 m/s.
    ClimbBands = {
        { label = 0.8,  run = { 'runclimbup_80', 'runclimbup_80_low' },             stand = { 'standclimbup_80', 'standclimbup_80_low' } },
        { label = 1.4,  run = { 'runclimbup_140_high', 'runclimbup_140_low' },      stand = { 'standclimbup_140_high', 'standclimbup_140_low' } },
        { label = 1.8,  run = { 'runclimbup_180_high', 'runclimbup_180_low' },      stand = { 'standclimbup_180_high', 'standclimbup_180_low' } },
        { label = 2.2,  run = { 'runclimbup_220', 'runclimbup_220_high' },          stand = { 'standclimbup_220', 'standclimbup_220_high' } },
        { label = 2.95, run = { 'runclimbup_295_low' },                             stand = { 'standclimbup_295_low' } },
    },
    -- Car hood slide: in, slide, out, played in order
    BonnetClips = {
        l = { 'bonnet_slide_l_in', 'bonnet_slide_l_slide', 'bonnet_slide_l_out' },
        r = { 'bonnet_slide_r_in', 'bonnet_slide_r_slide', 'bonnet_slide_r_out' },
    },
}

-- Measured clip offsets, keyed 'dict/clip'. Fill with /pkmeasure <dict> <clip> (prints a ready line to F8).
-- fwd / up / right = metres the clip moves the body, dur = seconds, upEnd = phase where the rise is done,
-- curve = { {fwd, up}, ... } at every 10% of the clip. Without an entry the move uses a default path.
Parkour.ClipOffsets = {
}

-- Trainers. Basic ones stand in each faction safezone; advanced ones are hidden, no blip.
-- z is a hint: the ped is snapped to the ground when the area streams in.
Parkour.Trainers = {
    { id = 'mil_basic', tier = 'basic', label = 'Sergeant Okafor', model = 's_m_y_marine_03', x = 1752.0, y = 3268.0, z = 41.2, h = 105.0, chains = { 'pk_first_steps', 'pk_rooftops' }, blip = true },
    { id = 'reb_basic', tier = 'basic', label = 'Dash',            model = 'a_m_y_runner_01', x = 1024.0, y = -311.0, z = 66.9, h = 180.0, chains = { 'pk_first_steps', 'pk_rooftops' }, blip = true },
    { id = 'civ_basic', tier = 'basic', label = 'Coach Marlow',    model = 'a_f_y_runner_01', x = -257.0, y = -2041.0, z = 27.0, h = 230.0, chains = { 'pk_first_steps', 'pk_rooftops' }, blip = true },
    { id = 'bik_basic', tier = 'basic', label = 'Skids',           model = 'a_m_y_motox_01',  x = 966.0,  y = -198.0, z = 72.1, h = 150.0, chains = { 'pk_first_steps', 'pk_rooftops' }, blip = true },
    { id = 'adv_vinewood', tier = 'advanced', label = 'The Sign Keeper', model = 'a_m_y_hippy_01',   x = 726.0,  y = 1196.0,  z = 326.0, h = 170.0, chains = { 'pk_ghost_line' } },
    { id = 'adv_docks',    tier = 'advanced', label = 'Crane',           model = 'a_m_m_hillbilly_02', x = 1090.0, y = -3020.0, z = 5.9,   h = 90.0,  chains = { 'pk_ghost_line' } },
    { id = 'adv_chiliad',  tier = 'advanced', label = 'Old Wren',        model = 'a_f_m_tramp_01',   x = 452.0,  y = 5566.0,  z = 781.2, h = 90.0,  chains = { 'pk_ghost_line' } },
}
Parkour.TrainerRange = 6.0

-- Trials, in the same shape as bs_operations chains: ordered steps and a reward paid on claim (Mission Log).
-- Step types: move (kind, count), escape (count), goto (x, y, z, radius, minZ)
Parkour.Chains = {
    pk_first_steps = {
        tier = 'basic', needsPerk = 'pk_basics', cooldownHours = 0, once = true,
        steps = {
            { type = 'move', kind = 'vault', count = 3 },
            { type = 'move', kind = 'climb', count = 2 },
            { type = 'move', kind = 'slide', count = 2 },
        },
        reward = { skillXp = 250, xp = 150, money = 100 },
    },
    pk_rooftops = {
        tier = 'basic', needsPerk = 'pk_basics', requires = 'pk_first_steps', cooldownHours = 0, once = true,
        steps = {
            { type = 'move', kind = 'climbHigh', count = 2 },
            { type = 'move', kind = 'roll', count = 2 },
            { type = 'escape', count = 1 },
        },
        reward = { skillXp = 500, xp = 300, money = 250 },
    },
    pk_ghost_line = {
        tier = 'advanced', needsPerk = 'pk_advanced', requires = 'pk_rooftops', cooldownHours = 24,
        steps = {
            { type = 'move', kind = 'wallrun', count = 3 },
            { type = 'move', kind = 'walljump', count = 2 },
            { type = 'move', kind = 'ledge', count = 2 },
            { type = 'escape', count = 2 },
        },
        reward = { skillXp = 900, xp = 600, money = 500, items = { { item = 'water_bottle', amount = 2 }, { item = 'bandage', amount = 2 } } },
    },
}
