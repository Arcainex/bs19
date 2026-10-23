-- Per-shot recoil (camera climb) and camera shake. Read by client/cl_recoil.lua.
-- Degrees are camera pitch. Keep kicks small.
Skills.Recoil = {
    enabled = true,
    tree    = 'combat',

    -- Skill scaling: level 0 -> lowSkillMult, maxLevel -> highSkillMult (linear).
    lowSkillMult  = 1.35,
    highSkillMult = 0.70,
    steadyHandsMult = 0.90,     -- extra if the Steady Hands perk is owned
    -- bs_drugs sway modifier is applied too, clamped to this range
    drugMin = 0.80, drugMax = 1.50,

    -- Recovery once you stop firing: return this fraction of the burst climb.
    recoverDelayMs  = 90,       -- wait this long after the last shot
    recoverMs       = 250,
    recoverFraction = 0.60,
    shotGapMs       = 60,       -- min ms between detected shots (IsPedShooting can stay true 2 frames)
    firstPersonMult = 0.85,     -- FP view is closer to the sights, so a bit less

    -- Per weapon group. kick = pitch deg per shot, drift = max random yaw deg,
    -- maxClimb = cap of total climb in one burst, shake = amplitude.
    groups = {
        pistol  = { kick = 0.35, drift = 0.10, maxClimb = 2.5, shake = 0.05 },
        smg     = { kick = 0.22, drift = 0.12, maxClimb = 3.0, shake = 0.07 },
        rifle   = { kick = 0.30, drift = 0.12, maxClimb = 3.5, shake = 0.10 },
        mg      = { kick = 0.32, drift = 0.18, maxClimb = 4.0, shake = 0.16 },
        shotgun = { kick = 1.10, drift = 0.25, maxClimb = 3.0, shake = 0.22 },
        sniper  = { kick = 1.40, drift = 0.20, maxClimb = 3.0, shake = 0.20 },
        heavy   = { kick = 1.20, drift = 0.25, maxClimb = 3.0, shake = 0.25 },
    },

    -- Caliber overrides by weapon name (fields replace the group ones).
    weapons = {
        WEAPON_PISTOL50        = { kick = 0.65, shake = 0.10 },   -- .50 AE
        WEAPON_REVOLVER        = { kick = 0.80, shake = 0.12 },
        WEAPON_REVOLVER_MK2    = { kick = 0.80, shake = 0.12 },
        WEAPON_HEAVYPISTOL     = { kick = 0.45, shake = 0.07 },
        WEAPON_MARKSMANRIFLE   = { kick = 0.80, shake = 0.16, maxClimb = 3.0 },
        WEAPON_MARKSMANRIFLE_MK2 = { kick = 0.80, shake = 0.16, maxClimb = 3.0 },
        WEAPON_HEAVYSNIPER     = { kick = 1.80, shake = 0.28 },
        WEAPON_HEAVYSNIPER_MK2 = { kick = 1.80, shake = 0.28 },
        WEAPON_MUSKET          = { kick = 1.60, shake = 0.25 },
        WEAPON_MINIGUN         = { kick = 0.10, drift = 0.20, shake = 0.18 },
    },

    -- One-shot shake per shot. SMALL_EXPLOSION_SHAKE is a short, valid jolt.
    -- Big calibers (shake >= bigShakeFrom) use bigShakeName.
    shakeName    = 'SMALL_EXPLOSION_SHAKE',
    bigShakeName = 'JOLT_SHAKE',
    bigShakeFrom = 0.20,
    shakeMax     = 0.35,

    -- Attachments (vanilla component names). Reductions are fractions.
    suppressor = { climb = 0.10, shake = 0.30 },
    grip       = { climb = 0.20, shake = 0.10 },
    suppressorComponents = {
        'COMPONENT_AT_PI_SUPP', 'COMPONENT_AT_PI_SUPP_02', 'COMPONENT_AT_AR_SUPP',
        'COMPONENT_AT_AR_SUPP_02', 'COMPONENT_AT_SR_SUPP', 'COMPONENT_AT_SR_SUPP_03',
        'COMPONENT_AT_MUZZLE_01', 'COMPONENT_AT_MUZZLE_02', 'COMPONENT_AT_MUZZLE_03',
        'COMPONENT_AT_MUZZLE_04', 'COMPONENT_AT_MUZZLE_05', 'COMPONENT_AT_MUZZLE_06',
        'COMPONENT_AT_MUZZLE_07', 'COMPONENT_AT_MUZZLE_08', 'COMPONENT_AT_MUZZLE_09',
    },
    gripComponents = { 'COMPONENT_AT_AR_AFGRIP', 'COMPONENT_AT_AR_AFGRIP_02' },

    debug = false,
}
