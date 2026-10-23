-- bs_medical - injuries, bleeding, infection, sickness and blood.
-- Medical.System.enabled is the master switch (F1). Off = only going down and
-- being revived by friends, exactly as before. Nothing below runs.

Medical.System = {
    enabled          = true,

    -- Zombie hits
    infectChance     = 0.05,   -- per hit that lands
    bleedInfectMult  = 2.0,    -- chance multiplier while you are bleeding
    scratchChance    = 0.35,   -- a hit opens a light bleed
    bruteFractureChance = 0.15,

    -- Infection (0-100). Stage 1 fever, 2 blurred vision, 3 dying, 100 = dead.
    infectionPerMinute = 1.2,
    stage2At         = 35.0,
    stage3At         = 70.0,
    antiviralMaxStage = 2,     -- antiviral works up to this stage

    -- Blood (percent). Loss per minute per open wound.
    bleedLight       = 2.0,
    bleedHeavy       = 7.0,
    bloodRegen       = 0.8,    -- per minute when fed, watered and not bleeding
    bloodLowAt       = 60.0,   -- blur and stamina loss below this
    bloodCriticalAt  = 30.0,   -- health loss below this
    bulletRebleedMin = 4,      -- minutes before a lodged bullet opens again

    -- Fractures
    splintHealMinutes = 20,
    fallFractureHeight = 4.5,  -- metres
    crashFractureKmh = 55.0,   -- sudden speed loss counted as a crash

    -- Sickness
    foodPoisonMinutes = 12,
    coldMinutes      = 20,
    coldChance       = 0.08,   -- per minute while wet at night
    coughNoise       = 30.0,
    vomitLoss        = 12.0,   -- hunger and thirst lost per vomit

    -- Pain (0-100) from wounds, breaks, bullets and heavy hits. Shakes the
    -- screen and the aim. Painkillers mask it for a while.
    painMult         = 1.0,
    painkillerMinutes = 10,
    hitPainDecay     = 6.0,    -- per minute, pain from hits fading

    -- Health regen when fed and not bleeding: hp every 10 s.
    regenHp          = 1,
    regenNeedsAt     = 50.0,

    -- Defibrillator window after a bleedout (seconds). The body stays.
    defibWindow      = 60,

    -- NPC doctor full heal price (cash).
    doctorPrice      = 2500,

    -- Treating someone else is quicker.
    otherSpeed       = 0.7,
    -- Medical skill: each level shaves this off the time (capped at 50%).
    skillSpeedPerLevel = 0.04,
}

-- Body parts, in diagram order.
Medical.Parts = { 'head', 'torso', 'larm', 'rarm', 'lleg', 'rleg' }

-- What each item does. self = can be used on yourself, time in ms (before
-- speed bonuses). keep = not used up.
Medical.Items = {
    rag            = { self = true,  time = 3500,  anim = 'bandage', does = 'bleed_light' },
    bandage        = { self = true,  time = 4500,  anim = 'bandage', does = 'bleed' },
    tourniquet     = { self = true,  time = 4000,  anim = 'bandage', does = 'tourniquet', limbs = true },
    splint         = { self = true,  time = 7000,  anim = 'kneel',   does = 'splint', limbs = true },
    medkit         = { self = true,  time = 6000,  anim = 'kneel',   does = 'medkit' },
    antibiotics    = { self = true,  time = 2500,  anim = 'pill',    does = 'antibiotics', whole = true },
    antiviral      = { self = true,  time = 3000,  anim = 'inject',  does = 'antiviral', whole = true },
    antiseptic     = { self = true,  time = 3000,  anim = 'bandage', does = 'antiseptic' },
    painkillers    = { self = true,  time = 2500,  anim = 'pill',    does = 'painkillers', whole = true },
    saline         = { self = true,  time = 6000,  anim = 'inject',  does = 'saline', whole = true },
    blood_bag      = { self = false, time = 10000, anim = 'kneel',   does = 'transfusion', whole = true, needs = 'transfusion_kit' },
    surgical_kit   = { self = false, time = 12000, anim = 'kneel',   does = 'surgery' },
    defibrillator  = { self = false, time = 8000,  anim = 'kneel',   does = 'defib', whole = true, keep = true },
}

-- Treatment animations (base game).
Medical.TreatAnims = {
    bandage = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
    kneel   = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
    pill    = { dict = 'mp_suicide', clip = 'pill', flag = 49 },
    inject  = { dict = 'rcmpaparazzo_1ig_4', clip = 'miranda_shooting_up', flag = 49 },
    vomit   = { dict = 'oddjobs@taxi@tie', clip = 'vomit_outside', flag = 0 },
    cough   = { dict = 'timetable@gardener@smoking_joint', clip = 'idle_cough', flag = 48 },
}

-- Paid doctors, anchored to safe zones (ids from bs_zombies Zones.Safe).
Medical.Doctors = {
    { zone = 'paleto',             offset = vector3(-3.0, -10.0, 0.0), heading = 20.0 },
    { zone = 'faction_military',   offset = vector3(6.0, 4.0, 0.0),   heading = 180.0 },
    { zone = 'faction_rebels',     offset = vector3(6.0, 4.0, 0.0),   heading = 180.0 },
    { zone = 'faction_civilians',  offset = vector3(6.0, 4.0, 0.0),   heading = 180.0 },
    { zone = 'faction_bikers',     offset = vector3(6.0, 4.0, 0.0),   heading = 180.0 },
}
Medical.DoctorModel = 's_m_m_doctor_01'
