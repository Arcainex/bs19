-- bs_emotes - small survival emote set: surrender, point, whistle, get down. Upper-body animations where possible so you can keep walking.

Emotes = {}

Emotes.Keys = {
    handsUp = 'X',
    point   = 'B',
    whistle = 'H',
    prone   = 'Z',
    -- K, not G: G is taken in game and the two fought over the press. K was the retired clothing wheel's key.
    crouch  = 'K',
    -- Hold to focus. Also the key that zooms the camera in.
    focus   = 'TAB',
}

-- Crouch: two clipset names and two blend times (see cl_crouch.lua).
-- `strafeClipset` is needed because aiming switches the ped to a different animation tree; without it the crouch drops when you raise a weapon.
Emotes.Crouch = {
    clipset       = 'move_ped_crouched',
    strafeClipset = 'move_ped_crouched_strafing',
    blendIn       = 0.35,
    blendOut      = 0.35,
}

Emotes.HandsUp = {
    dict = 'random@mugging3',
    clip = 'handsup_standing_base',
    -- 49 = upper body only + looped, so you can keep walking.
    flag = 49,
    blendIn = 3.0,
    blendOut = 3.0,
}

Emotes.Whistle = {
    dict = 'rcmnigel1c',
    clip = 'hailing_whistle_waive_a',
    flag = 49,
    -- Sound carries; this is what a horde hears.
    noiseRadius = 55.0,
    cooldown = 1500,
}

Emotes.Prone = {
    -- Base-game crawl set. There is no true prone in GTA V: you get flat and can crawl forward and back.
    dict      = 'move_crawl',
    idle      = 'onfront_fwd',
    forward   = 'onfront_fwd',
    backward  = 'onfront_bwd',
    -- Base crawl speed. Slow on purpose.
    speed     = 0.22,
    -- Survival skill raises it: final speed = speed * (1 + skillLevel * speedPerSkillLevel), capped by maxSpeed.
    speedPerSkillLevel = 0.055,
    maxSpeed  = 0.6,
    -- Aiming from prone breaks the crawl pose. Set false to force standing up before shooting.
    allowAiming = true,
}

Emotes.Focus = {
    -- Seconds to hold the key before the camera moves, so a tap does nothing.
    holdMs      = 180,
    -- Field of view to ease into. Lower = tighter.
    fov         = 32.0,
    -- Each Survival level tightens the lens by this much, down to fovMin (level 20: 32 -> 21, about 1.5x magnification).
    fovPerSkillLevel = 0.55,
    fovMin      = 16.0,
    -- While aiming, focus goes to this fraction of the aim FOV (0.55 = about 1.8x past the aim zoom).
    aimZoomFactor = 0.55,
    -- Seconds the ease takes.
    easeIn      = 0.55,
    easeOut     = 0.35,
    -- Slight shoulder offset while focused.
    offset      = { x = 0.22, y = 0.0, z = 0.02 },
    -- Muffle the world slightly while listening.
    audioScene  = 'DEATH_SCENE',
    useAudio    = false,
    -- Stop the player sprinting while focused.
    blockSprint = true,
}

-- Sounds the world makes and how far they carry, in metres. bs_zombies reads this.
-- The whole stealth layer is balanced on these numbers. A sector is a square kilometre, so values far below that mean most walkers in the sector never hear a fight.
Emotes.Noise = {
    whistle  = 110.0,
    footstep = 6.0,
    sprint   = 22.0,
    -- Loud enough to be a decision: firing in the open alerts about a third of the sector.
    gunshot  = 340.0,
    -- Still audible (a suppressor is not a silencer) but about a twentieth of the area, which is what makes one worth an inventory slot.
    silenced = 75.0,
    melee    = 14.0,
    shout    = 90.0,

    -- Vehicles. Three engine kinds because a vehicle differs on two axes: the radius here is how far the sound pulls walkers from, the weight in config_sectors.lua is how much it raises the sector's population target. A horn is deliberate and carries almost as far as a gunshot.
    horn        = 260.0,
    engine      = 120.0,   -- an ordinary car at speed
    engine_loud = 210.0,   -- bikes, trucks, offroad, anything with no silencing
    heli        = 520.0,   -- the loudest thing a player can arrive in

    -- Work noise (gathering). Standing still making noise is the risk of gathering, so the radius matters: a pickaxe on rock carries further than a hatchet on wood. Well under a gunshot (340): mining draws the street, not the district.
    mining   = 95.0,
    chopping = 60.0,
    -- Digging is the quiet one; a loud noise would make hiding things impossible.
    digging  = 35.0,
}

-- The emote list: short and survival-flavoured.
-- `dict`/`clip` play an animation; `scenario` plays a base-game scenario (loops and handles props). `upper` = upper body only, so you can keep walking.

Emotes.List = {
    {
        id = 'signals', group = 'emotes', label = 'Signals',
        items = {
            { id = 'wave',     label = 'Wave',        dict = 'friends@frj@ig_1', clip = 'wave_a',              upper = true },
            { id = 'comehere', label = 'Come here',   dict = 'anim@mp_player_intupperwank', clip = 'idle_a',   upper = true },
            { id = 'stop',     label = 'Stop',        dict = 'random@arrests@busted', clip = 'idle_a',         upper = true },
            { id = 'salute',   label = 'Salute',      dict = 'anim@mp_player_intincarsalutestd@ps@', clip = 'idle_a', upper = true },
            { id = 'clap',     label = 'Clap',        dict = 'anim@mp_player_intcelebrationfemale@slow_clap', clip = 'slow_clap', upper = true },
        },
    },
    {
        id = 'rest', group = 'emotes', label = 'Rest',
        items = {
            { id = 'sit',      label = 'Sit down',    scenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER' },
            { id = 'lean',     label = 'Lean',        scenario = 'WORLD_HUMAN_LEANING' },
            { id = 'smoke',    label = 'Smoke',       scenario = 'WORLD_HUMAN_SMOKING' },
            { id = 'drink',    label = 'Drink',       scenario = 'WORLD_HUMAN_DRINKING' },
            { id = 'warm',     label = 'Warm hands',  scenario = 'WORLD_HUMAN_STAND_FIRE' },
            { id = 'sleep',    label = 'Lie down',    scenario = 'WORLD_HUMAN_SUNBATHE_BACK' },
        },
    },
    {
        id = 'work', group = 'emotes', label = 'Work',
        items = {
            { id = 'kneel',    label = 'Kneel',       scenario = 'CODE_HUMAN_MEDIC_KNEEL' },
            { id = 'search',   label = 'Search',      scenario = 'CODE_HUMAN_POLICE_INVESTIGATE' },
            { id = 'repair',   label = 'Repair',      scenario = 'WORLD_HUMAN_WELDING' },
            { id = 'notepad',  label = 'Take notes',  scenario = 'WORLD_HUMAN_CLIPBOARD' },
            { id = 'guard',    label = 'Stand guard', scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { id = 'binocs',   label = 'Watch',       scenario = 'WORLD_HUMAN_BINOCULARS' },
        },
    },
    {
        id = 'reactions', group = 'emotes', label = 'Reactions',
        items = {
            { id = 'facepalm', label = 'Facepalm',    dict = 'anim@mp_player_intupperface_palm', clip = 'idle_a', upper = true },
            { id = 'shrug',    label = 'Shrug',       dict = 'anim@mp_player_intupperno_way', clip = 'idle_a',    upper = true },
            { id = 'cry',      label = 'Break down',  dict = 'amb@code_human_cower_stand@male@base', clip = 'base' },
            { id = 'vomit',    label = 'Be sick',     scenario = 'WORLD_HUMAN_VOMIT' },
            { id = 'cough',    label = 'Cough',       dict = 'timetable@gardener@smoking_joint', clip = 'idle_cough', upper = true },
        },
    },
    -- dpEmotes-style menu entries. Every dict+clip was checked against the DurtyFree animDictsCompact dump. `group` is the menu tab.
    {
        id = 'dances', group = 'dances', label = 'Dances',
        items = {
            { id = 'dance',      label = 'Dance',        dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_a@', clip = 'high_center' },
            { id = 'dance2',     label = 'Dance (slow)', dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_a@', clip = 'med_center' },
            { id = 'dance3',     label = 'Club dance',   dict = 'anim@amb@nightclub@dancers@crowddance_facedj@', clip = 'hi_dance_facedj_09_v2_male^1' },
            { id = 'dance4',     label = 'Entourage',    dict = 'anim@amb@nightclub@dancers@solomun_entourage@', clip = 'mi_dance_facedj_17_v1_female^1' },
            { id = 'disco',      label = 'Uncle disco',  dict = 'anim@mp_player_intcelebrationfemale@uncle_disco', clip = 'uncle_disco' },
            { id = 'raiseroof',  label = 'Raise the roof', dict = 'anim@mp_player_intcelebrationmale@raise_the_roof', clip = 'raise_the_roof', upper = true },
            { id = 'taodance',   label = 'Tao dance',    dict = 'misschinese2_crystalmazemcs1_cs', clip = 'dance_loop_tao' },
            { id = 'buttwag',    label = 'Butt wag',     dict = 'special_ped@mountain_dancer@monologue_3@monologue_3a', clip = 'mnt_dnc_buttwag' },
        },
    },
    {
        id = 'gestures', group = 'emotes', label = 'Gestures',
        items = {
            { id = 'thumbsup',   label = 'Thumbs up',    dict = 'anim@mp_player_intupperthumbs_up', clip = 'idle_a', upper = true },
            { id = 'peace',      label = 'Peace',        dict = 'mp_player_int_upperpeace_sign', clip = 'mp_player_int_peace_sign', upper = true },
            { id = 'knuckles',   label = 'Crack knuckles', dict = 'anim@mp_player_intcelebrationmale@knuckle_crunch', clip = 'knuckle_crunch', upper = true },
            { id = 'crossarms',  label = 'Arms crossed', dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', upper = true },
            { id = 'impatient',  label = 'Impatient',    dict = 'amb@world_human_stand_impatient@male@no_sign@idle_a', clip = 'idle_a' },
            { id = 'boss',       label = 'Boss stance',  dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss' },
        },
    },
}

-- VIP emotes (bs_vip perk 'exclusiveEmotes'), cosmetic only. All dicts/clips/scenarios are already used elsewhere in this repo, so they exist on this build.
table.insert(Emotes.List, {
    id = 'vip', group = 'emotes', label = 'Supporter',
    items = {
        { id = 'v_teamidle', label = 'Team idle',      dict = 'anim@heists@heist_corona@team_idle_a', clip = 'idle_a_m2', vip = true },
        { id = 'v_pace',     label = 'Pace',           scenario = 'WORLD_HUMAN_STAND_IMPATIENT', vip = true },
        { id = 'v_loiter',   label = 'Loiter',         scenario = 'WORLD_HUMAN_BUM_STANDING', vip = true },
        { id = 'v_inspect',  label = 'Inspect ground', scenario = 'WORLD_HUMAN_CROUCH_INSPECT', vip = true },
    },
})

-- Walks and expressions (the other two dpEmotes tabs). A walk is a movement clipset that persists until reset; an expression is a facial idle override. `reset` entries restore the default.
Emotes.Walks = {
    { id = 'walk_reset',  label = 'Default',   reset = true },
    { id = 'walk_injured',label = 'Injured',   clipset = 'move_m@injured' },
    { id = 'walk_drunk',  label = 'Drunk',     clipset = 'move_m@drunk@verydrunk' },
    { id = 'walk_hurry',  label = 'Hurry',     clipset = 'move_m@hurry@a' },
    { id = 'walk_quick',  label = 'Quick',     clipset = 'move_m@quick' },
    { id = 'walk_sad',    label = 'Sad',       clipset = 'move_m@sad@a' },
    { id = 'walk_shady',  label = 'Shady',     clipset = 'move_m@shadyped@a' },
    { id = 'walk_tired',  label = 'Tired',     clipset = 'move_m@tired' },
    { id = 'walk_brave',  label = 'Brave',     clipset = 'move_m@brave' },
    { id = 'walk_casual', label = 'Casual',    clipset = 'move_m@casual@d' },
    -- VIP (exclusiveEmotes)
    { id = 'walk_stagger', label = 'Stagger',  clipset = 'move_m@drunk@moderatedrunk', vip = true },
}

Emotes.Expressions = {
    { id = 'face_reset',    label = 'Default',  reset = true },
    { id = 'face_angry',    label = 'Angry',    mood = 'mood_angry_1' },
    { id = 'face_happy',    label = 'Happy',    mood = 'mood_happy_1' },
    { id = 'face_stressed', label = 'Stressed', mood = 'mood_stressed_1' },
    { id = 'face_injured',  label = 'In pain',  mood = 'mood_injured_1' },
    { id = 'face_sleepy',   label = 'Sleepy',   mood = 'mood_sleeping_1' },
    { id = 'face_drunk',    label = 'Drunk',    mood = 'mood_drunk_1' },
    { id = 'face_focused',  label = 'Focused',  mood = 'mood_aiming_1' },
}

-- The menu. F6 and COMMA were checked against every RegisterKeyMapping in resources/ (F3, the dpEmotes default, is bs_cinecam; B is point here).
Emotes.Menu = {
    command    = 'emotemenu',
    key        = 'F6',
    favCommand = 'emotefavs',
    favKey     = 'COMMA',
}
-- Max favourites a player can star; also the size of the favourites wheel.
Emotes.FavLimit = 15
-- bs_vip perks read here: extra favourites (bonus from the bs_vip config) and the vip = true emotes/walks above.
Emotes.VipFavPerk   = 'emoteFavourites'
Emotes.VipEmotePerk = 'exclusiveEmotes'
Emotes.FavHardCap   = 40   -- never keep more than this in KVP

Emotes.Settings = {
    -- Emotes stop when you move, unless they are upper-body.
    cancelOnMove = true,
    -- Key that cancels whatever is playing.
    cancelKey    = 'X',
}

-- Clothing take-off/put-on was removed; appearance is bought at the tailor.

-- Which automatic noise sources are armed. cl_noise.lua watches the player and raises noises on its own; turn individual watchers off here.

Emotes.NoiseSources = {
    -- Gunfire. Stays on. When bs_weapons reports a silent weapon, the whole event is skipped (see cl_noise.lua).
    gunfire = true,

    -- Sprinting. Small; the quiet-movement logic depends on it.
    sprint = true,

    -- Melee. Off: the watcher fired Noise.Make('melee') every 250ms for the whole fight, adding up to more than a rifle shot and defeating melee as the stealth option. Set true only if swinging should be as loud as firing, and lower the 250ms cadence with it.
    melee = false,
}
