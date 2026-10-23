-- bs_drugs config. Items are defined in bs_inventory/config/config_items.lua (data.drug = true).

Drugs = {}

Drugs.MetaKey = 'drug_addiction'   -- character metadata: { [drug] = { pts = n, last = os.time } }
Drugs.UseLockMs = 1500             -- server anti-spam between two uses

-- Quality tiers. effect = strength/duration scale, addict = addiction gain scale.
Drugs.Quality = {
    bad    = { effect = 0.6, addict = 1.6, label = 'cut' },
    normal = { effect = 1.0, addict = 1.0, label = 'normal' },
    good   = { effect = 1.3, addict = 0.7, label = 'pure' },
}

-- item -> drug + quality
Drugs.Items = {
    cocaine_bad = { drug = 'cocaine', q = 'bad' },  cocaine = { drug = 'cocaine', q = 'normal' },  cocaine_good = { drug = 'cocaine', q = 'good' },
    morphine_bad = { drug = 'morphine', q = 'bad' }, morphine = { drug = 'morphine', q = 'normal' }, morphine_good = { drug = 'morphine', q = 'good' },
    amphetamine_bad = { drug = 'amphetamine', q = 'bad' }, amphetamine = { drug = 'amphetamine', q = 'normal' }, amphetamine_good = { drug = 'amphetamine', q = 'good' },
    weed_bad = { drug = 'weed', q = 'bad' }, weed = { drug = 'weed', q = 'normal' }, weed_good = { drug = 'weed', q = 'good' },
    cigarette = { drug = 'cigarette', q = 'normal' },
}

Drugs.RehabItem = 'rehab_kit'

-- Per drug. duration in seconds (x quality.effect). addict = points per use (x quality.addict).
Drugs.Types = {
    cocaine = {
        label = 'Cocaine', anim = 'snort', duration = 180, addict = 14,
        sprint = 1.30,          -- sprint multiplier (engine cap 1.49)
        staminaDrain = 0.30,    -- 70% less stamina drain
    },
    morphine = {
        label = 'Morphine', anim = 'inject', duration = 240, addict = 16,
        damageTaken = 0.70,     -- share of any health loss that sticks (rest is refunded)
        bleedoutBonus = 90,     -- extra seconds before bleeding out while downed
    },
    amphetamine = {
        label = 'Amphetamine', anim = 'pill', duration = 200, addict = 12,
        sway = 0.35,            -- aim sway multiplier (bs_skills)
        staminaRegen = 1.2,
    },
    weed = {
        label = 'Weed', anim = 'joint', duration = 300, addict = 6,
        infection = 0.5,        -- infection gain multiplier
    },
    cigarette = {
        label = 'Cigarette', anim = 'smoke', duration = 90, addict = 4,
        staminaCap = 30.0,      -- stamina bar clamped to this while smoking
        healPerTick = 1, healTickMs = 4000,  -- slow health regen
        needsFire = { 'lighter', 'matches' }, -- lighter is kept, a match is used up
        consumeFire = { matches = true },
    },
}

-- Addiction: 0..100 points per drug.
Drugs.Addiction = {
    max = 100,
    decayPerMinute = 0.5,       -- points lost per minute while clean
    cleanAfter = 600,           -- seconds after last use before decay starts
    withdrawalAfter = 900,      -- seconds after last use before withdrawal can start
    tickSeconds = 60,           -- server check interval
    levels = { 25, 55, 85 },    -- points -> withdrawal level 1/2/3
}

-- Withdrawal debuffs by level (the worst drug wins).
Drugs.Withdrawal = {
    -- healthRegen = GTA health recharge multiplier, shake = camera shake amplitude, fxEvery = seconds between screen effects
    [1] = { sway = 1.3, staminaRegen = 0.85, healthRegen = 0.7, shake = 0.0,  fxEvery = 240 },
    [2] = { sway = 1.7, staminaRegen = 0.65, healthRegen = 0.4, shake = 0.08, fxEvery = 150 },
    [3] = { sway = 2.3, staminaRegen = 0.45, healthRegen = 0.1, shake = 0.18, fxEvery = 90 },
    fx = 'DrugsDrivingIn', fxMs = 6000,   -- periodic screen effect (AnimpostFX)
    shakeType = 'DRUNK_SHAKE',
}

-- Animations (names checked against DurtyFree gta-v-data-dumps).
Drugs.Anims = {
    snort  = { dict = 'move_p_m_two_idles@generic', clip = 'fidget_sniff_fingers', time = 3000, flag = 49 },
    inject = { dict = 'rcmpaparazzo1ig_4', clip = 'miranda_shooting_up', time = 4000, flag = 49,
               prop = 'prop_syringe_01', bone = 28422, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
    pill   = { dict = 'mp_player_inteat@pnq', clip = 'loop', time = 2500, flag = 49,
               prop = 'prop_cs_pills', bone = 28422, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
    joint  = { dict = 'amb@world_human_smoking_pot@male@base', clip = 'base', time = 6000, flag = 49,
               prop = 'p_cs_joint_01', bone = 64097, pos = vector3(0.02, 0.02, -0.008), rot = vector3(100.0, 0.0, 100.0) },
    -- Cigarette is a loop: enter, base (looped until done or cancelled), exit.
    smoke  = {
        enter = { dict = 'amb@world_human_smoking@male@male_a@enter', clip = 'enter', time = 3000 },
        base  = { dict = 'amb@world_human_smoking@male@male_a@base',  clip = 'base' },
        exit  = { dict = 'amb@world_human_smoking@male@male_a@exit',  clip = 'exit', time = 2000 },
        prop = 'prop_cs_ciggy_01', bone = 64097, pos = vector3(0.02, 0.02, -0.008), rot = vector3(100.0, 0.0, 100.0),
        flag = 49,  -- upper body + loop, so you can walk while smoking
    },
}

-- Screen/camera effects while a drug is active (see client/cl_fx.lua). Names checked against DurtyFree gta-v-data-dumps.
-- tc = main timecycle (strongest active drug wins), extra = subtle second layer when another drug owns tc.
-- str = strength at normal quality (x quality.effect, max 1.0). shake = ShakeGameplayCam amplitude.
-- pulse = short AnimpostFX replayed every `every` seconds.
Drugs.Fx = {
    fadeMs = 3000,          -- fade in / out time
    tickMs = 50,            -- ramp step while something is on screen
    cocaine = {
        tc = 'hud_def_desatcrunch', str = 0.45, extra = 'rply_contrast', extraStr = 0.35,
        shakeType = 'HAND_SHAKE', shake = 0.12,
        pulse = { fx = 'FocusIn', ms = 700, every = 18 },
    },
    weed = {
        tc = 'stoned', str = 0.25, extra = 'drug_flying_base', extraStr = 0.15,
        shakeType = 'DRUNK_SHAKE', shake = 0.3,
    },
    amphetamine = {
        tc = 'hud_def_desat_cold', str = 0.4, extra = 'rply_contrast', extraStr = 0.25,
        shakeType = 'HAND_SHAKE', shake = 0.06,
        pulse = { fx = 'Dont_tazeme_bro', ms = 400, every = 40 },  -- brief chromatic flicker
    },
    morphine = {
        tc = 'drug_drive_blend01', str = 0.35, extra = 'rply_vignette', extraStr = 0.4,
        shakeType = 'DRUNK_SHAKE', shake = 0.15,
    },
    cigarette = {
        extra = 'rply_vignette', extraStr = 0.12,   -- barely there
    },
    -- Cut (bad) drugs glitch now and then.
    badGlitch = { fx = 'DrugsDrivingOut', ms = 1200, every = 35 },
}

-- HUD widget (html/). Icons are inline SVG keys in html/app.js.
Drugs.Hud = { enabled = true }
