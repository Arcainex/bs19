-- bs_zombies - walker config. Slow walkers, dangerous in numbers.
-- Each client spawns local peds at deterministic grid positions (see cl_spawner.lua); the server only tracks which are dead

Zombies = {}

Zombies.Settings = {
    enabled             = true,

    -- Hard ceiling on every move rate a type can ask for (shamble, drawn, chase), applied in setChase()
    -- Set to nil to lift it, e.g. for a special infected.
    maxMoveRate         = 1.0,  -- 1.0 = drunk clip at real speed; below that it plays in slow motion

    -- Play the base-game ped pain voice for cues with no audio file
    -- Off, because walkers built on civilian models would shout like a person (see growl() in cl_ai.lua)
    enginePainFallback  = false,

    -- Per-client ped budget, enforced server-side
    -- Protects frame rate and the game's ped pool ("Pool Full, Size == 256")
    maxPerClient        = 28,

    -- Walkers built per pass on the client
    -- Model loading and CreatePed are main-thread work, so keep this low (about 2 per ~90 ms)
    spawnPerPass        = 2,
    -- The lure: the server walks unhosted records toward noise in a straight line (no navmesh), so far-away walkers still set off
    -- Once a client hosts them, normal pathing takes over
    lure = {
        enabled = true,

        -- Multiplier on the noise radius for how far a lure reaches. Above 1: a 150 m gunshot pulls from 300 m.
        reachScale = 2.0,
        maxReach   = 450.0,

        -- Lure speed in metres per second (flat, not the type's drawnRate). 1.15 is a purposeful walk; 200 m takes just under 3 minutes.
        speed = 1.15,

        -- Seconds they keep walking toward the last noise. Refreshed by every new sound.
        seconds = 180,

        -- Distance in metres at which they count as arrived, so they do not pile on the exact spot.
        arriveAt = 12.0,
    },

    -- Radius in metres around the player in which cells are considered for spawning.
    spawnRadius         = 175.0,
    -- Minimum spawn distance from any player, in metres
    -- High so walkers arrive by walking into view instead of popping in
    spawnDistanceMin    = 50.0,  -- never spawn closer than this to any player

    -- Distance in metres beyond which a walker's record is removed, only when no player at all is within it
    -- Must stay above Streaming.cleanupDistance (400) and spawnMax + openPushMax (370)
    despawnDistance     = 420.0,

    -- Grid size in metres. One cell holds at most one walker seed.
    cellSize            = 22.0,
    -- Fraction of cells that contain a walker before zone density is applied.
    baseOccupancy       = 0.26,

    -- Director tick on the client, ms.
    tick                = 900,
    -- Staggered so they never all think on one frame
    aiTick              = 260,

    -- Safe zones push walkers away entirely.
    safeZonePadding     = 55.0,

    -- How long a body stays (seconds) and how many may exist
    -- Bodies are peds, so too many for too long fills the ped pool. Over the cap the oldest goes first.
    corpseLifetime      = 300,
    maxCorpses          = 12,

    -- Global knobs.
    damageScale         = 1.0,
    headshotMultiplier  = 4.0,
    -- Non-headshot damage multiplier. Low so aiming for the head is the sane strategy.
    bodyDamageScale     = 0.35,
    -- Vehicle damage multiplier. Large enough that any real-speed hit is lethal.
    vehicleDamageScale  = 6.0,

    -- Melee damage multiplier
    -- Large enough that a bat or machete drops an ordinary walker (220 hp) in one swing; a brute (850 hp) still needs two or three
    meleeDamageScale    = 12.0,
    -- Bare fists are scaled far lower, so punching a walker to death takes several hits.
    unarmedDamageScale  = 2.0,

    -- Damage sv_registry.lua assumes when the reported weapon is not in Zombies.WeaponBaseDamage. Conservative.
    unknownWeaponRawDamage = 27,
    -- Headroom multiplier over the computed max damage per weapon, to absorb falloff and RNG without rejecting legitimate hits
    weaponDamageHeadroom   = 1.6,
    -- Max distance in metres between attacker and zombie for a server-accepted E-execute.
    executeMaxRange        = 3.0,

    -- Staff-only diagnostic overlay, shown while holding Alt
    -- Does not conflict with the normal Alt interaction menu
    debugOverlay = {
        enabled = true,
        control = 19,             -- INPUT_CHARACTER_WHEEL / Left Alt
        visibleDistance = 160.0,  -- real (A) walker labels
        simulatedRadius = 260.0,  -- nearby unmaterialised (D) agents
        simulatedLimit = 40,
        refreshMs = 500,
    },
}

-- Mobility: what a walker may do with terrain
-- Climbing is blocked through the ped's path capabilities (SET_PED_PATH_*), not config flags, with a high climb cost as backup
Zombies.Mobility = {
    -- Mantle/vault over walls, fences, crates. Off stops walkers vaulting fences.
    pathClimbovers     = false,
    -- Ladders. Uses the pathfinding side; SetPedCanClimbLadders does not exist on b3095.
    pathLadders        = false,
    -- Dropping off a height as a route choice. A walker can still fall, but will not choose to.
    pathDropFromHeight = false,
    -- Cost multiplier on any climb link the pathfinder still considers (engine clamps to about 0..10)
    -- At 10 a route around the obstacle always wins
    climbCostModifier  = 10.0,

    -- Extra ped config flags set at spawn, as { index, value } pairs
    -- Check each index against the CPED_CONFIG_FLAG enum for your build and put the name next to it: bad indices fail silently
    configFlags = {
        { 146, true  },  -- CPED_CONFIG_FLAG_DisableLadderClimbing
        { 97,  false },  -- CPED_CONFIG_FLAG_VaultFromCover
    },
    -- Re-applied on each think tick since task changes can reset path caps.
    reassertOnThink = true,
}

-- Vaulting over small fences only (client/cl_vault.lua)
-- Used when a walker is stuck against something lower than maxHeight (railings, low walls, benches)
Zombies.Vault = {
    enabled    = true,
    maxHeight  = 1.25,  -- obstacles taller than this (m above the feet) are walls: no
    kneeHeight = 0.45,  -- the low ray; something must be in the way here
    reach      = 1.1,   -- how far ahead to look (m)
    maxDrop    = 0.6,   -- landing must be within this height of where it stands
    stuckMs    = 1500,  -- moved less than stuckMove in this long = stuck
    stuckMove  = 0.4,
    checkMs    = 700,
    cooldownMs = 4000,  -- per walker, between attempts
}

-- Engine-side hit detector
-- The real walker health is on the server
Zombies.Detector = {
    engineHealthPool = 20000,
    maxEngineRevives = 3,
    sampleInterval   = 80,

    -- Self-heal for unkillable walkers
    -- Causes: an outside resource set invincibility or proofs on the ped, the server has no record for the id, or the hit latch drifted

    -- Reported hits with no acknowledged health change before a walker counts as stuck.
    stuckHits        = 4,

    -- Window in ms those hits must land in; outside it the count resets.
    stuckWindowMs    = 4000,

    -- Rung one: re-assert flags (not invincible, not proofed, max health)
    -- Cheap, and fixes the walker instead of removing it
    reassertFlags    = true,

    -- Rung two: ask the server whether the id still exists. If so health re-syncs, otherwise the walker is removed.
    -- Rate-limited per walker by stuckWindowMs
    verifyWithServer = true,

    -- Rung three: after this many stuck cycles the walker is despawned locally with no kill, loot or XP. 0 = never drop.
    dropAfterCycles  = 3,

    -- An invincible ped never takes damage, so the ladder above cannot trigger for it
    -- A few peds per sweep get the flags re-asserted (3 natives each), cursor-based so cost does not grow with the horde
    auditFlags       = true,

    -- ms between sweep steps. 250 is four steps a second.
    auditIntervalMs  = 250,

    -- Walkers re-asserted per step. 2 x 4/s = 8 per second, so a 200-walker horde is covered every 25 s.
    auditPerPass     = 2,

    -- Milliseconds a ped may be a walker with no live entry before it is deleted as an orphan
    -- Must exceed the birth window (spawn can wait up to 4 s for the clipset)
    reviveDecayMs    = 30000,

    -- Unused, kept so old configs still load.
    orphanAfterMs    = 15000,
}

-- Per-weapon upper bound for the damage a single reported hit can do, used by the bs:z:hit clamp in sv_registry.lua
-- Values only need to be a believable maximum so lied-about numbers get caught. melee = true routes through meleeDamageScale.
Zombies.WeaponBaseDamage = {
    -- Pistols / sidearms
    WEAPON_PISTOL         = { raw = 27  },
    WEAPON_COMBATPISTOL   = { raw = 26  },
    WEAPON_APPISTOL       = { raw = 24  },
    WEAPON_PISTOL50       = { raw = 38  },
    WEAPON_SNSPISTOL      = { raw = 24  },
    WEAPON_HEAVYPISTOL    = { raw = 30  },
    WEAPON_VINTAGEPISTOL  = { raw = 24  },
    WEAPON_REVOLVER       = { raw = 50  },
    -- SMGs
    WEAPON_MICROSMG       = { raw = 21  },
    WEAPON_SMG            = { raw = 24  },
    WEAPON_ASSAULTSMG     = { raw = 22  },
    WEAPON_MACHINEPISTOL  = { raw = 20  },
    -- Rifles
    WEAPON_ASSAULTRIFLE   = { raw = 30  },
    WEAPON_CARBINERIFLE   = { raw = 30  },
    WEAPON_ADVANCEDRIFLE  = { raw = 28  },
    WEAPON_SPECIALCARBINE = { raw = 32  },
    WEAPON_BULLPUPRIFLE   = { raw = 29  },
    WEAPON_COMPACTRIFLE   = { raw = 28  },
    -- Shotguns: a close hit lands several pellets, so the damage delta can be far above a rifle round. Generous.
    WEAPON_PUMPSHOTGUN    = { raw = 180 },
    WEAPON_SAWNOFFSHOTGUN = { raw = 200 },
    WEAPON_ASSAULTSHOTGUN = { raw = 130 },
    WEAPON_BULLPUPSHOTGUN = { raw = 130 },
    WEAPON_MUSKET         = { raw = 110 },
    WEAPON_DBSHOTGUN      = { raw = 200 },
    -- Sniper / marksman
    WEAPON_SNIPERRIFLE    = { raw = 100 },
    WEAPON_HEAVYSNIPER    = { raw = 130 },
    WEAPON_MARKSMANRIFLE  = { raw = 60  },
    -- Melee - routed through meleeDamageScale.
    WEAPON_BAT            = { raw = 45, melee = true },
    WEAPON_CROWBAR        = { raw = 45, melee = true },
    WEAPON_HAMMER         = { raw = 45, melee = true },
    WEAPON_GOLFCLUB       = { raw = 40, melee = true },
    WEAPON_KNIFE          = { raw = 35, melee = true },
    WEAPON_MACHETE        = { raw = 45, melee = true },
    WEAPON_HATCHET        = { raw = 45, melee = true },
    WEAPON_BATTLEAXE      = { raw = 55, melee = true },
    WEAPON_WRENCH         = { raw = 40, melee = true },
    WEAPON_POOLCUE        = { raw = 35, melee = true },
    WEAPON_SWITCHBLADE    = { raw = 35, melee = true },
    WEAPON_DAGGER         = { raw = 35, melee = true },
    WEAPON_FLASHLIGHT     = { raw = 25, melee = true },
    WEAPON_NIGHTSTICK     = { raw = 35, melee = true },
    WEAPON_STONE_HATCHET  = { raw = 45, melee = true },
    -- Melee-group weapons must be listed here
    -- Unarmed is listed for the same reason
    WEAPON_KNUCKLE        = { raw = 35, melee = true },
    WEAPON_BOTTLE         = { raw = 30, melee = true },
    WEAPON_UNARMED        = { raw = 14, melee = true },
    -- Thrown / tools: not GROUP_MELEE, so they use the ranged branch. Grenade/molotov are generous.
    WEAPON_MOLOTOV          = { raw = 60  },
    WEAPON_GRENADE          = { raw = 400 },
    WEAPON_PETROLCAN        = { raw = 20  },
    WEAPON_FIREEXTINGUISHER = { raw = 10  },
}

-- Ped models
-- Zombies.ModelPools picks a pool by area
Zombies.ModelPools = {
    urban    = { { 'u_m_y_zombie_01', 3 }, { 'bsz_walker_a', 2 }, { 'bsz_walker_b', 2 }, { 'bsz_walker_c', 2 }, { 'bsz_walker_d', 2 }, { 'bsz_female_a', 2 }, { 'bsz_cop_a', 1 } },
    rural    = { { 'u_m_y_zombie_01', 2 }, { 'bsz_walker_a', 2 }, { 'bsz_walker_b', 2 }, { 'bsz_walker_c', 2 }, { 'bsz_walker_d', 2 }, { 'bsz_female_a', 1 } },
    military = { { 'bsz_marine_a', 6 }, { 'u_m_y_zombie_01', 1 }, { 'bsz_walker_d', 1 } },
    police   = { { 'bsz_cop_a', 5 }, { 'u_m_y_zombie_01', 1 }, { 'bsz_walker_a', 1 } },
    medical  = { { 'bsz_medic_a', 5 }, { 'bsz_female_a', 1 }, { 'u_m_y_zombie_01', 1 } },
    -- Used for the brute type everywhere
    -- No fat model streams yet (the Fat Zombie pack is texture-only), so the bulkiest add-ons stand in
    brute    = { { 'bsz_marine_a', 2 }, { 'bsz_walker_d', 2 }, { 'bsz_cop_a', 1 } },
}

-- Areas that force a pool. Circles: x, y, r (metres).
Zombies.PoolAreas = {
    { pool = 'military', x = -2200.0, y = 3150.0, r = 650.0 },  -- Fort Zancudo
    { pool = 'military', x = 1700.0,  y = 2600.0, r = 250.0 },  -- Bolingbroke
    { pool = 'military', x = 3570.0,  y = 3750.0, r = 200.0 },  -- Humane Labs
    { pool = 'police',   x = 440.0,   y = -985.0, r = 150.0 },  -- Mission Row PD
    { pool = 'police',   x = 1855.0,  y = 3685.0, r = 120.0 },  -- Sandy Shores sheriff
    { pool = 'police',   x = -445.0,  y = 6015.0, r = 120.0 },  -- Paleto sheriff
    { pool = 'police',   x = -1095.0, y = -835.0, r = 120.0 },  -- Vespucci PD
    { pool = 'medical',  x = 300.0,   y = -585.0, r = 150.0 },  -- Pillbox Hill
    { pool = 'medical',  x = 1150.0,  y = -1530.0, r = 120.0 }, -- St Fiacre
    { pool = 'medical',  x = -450.0,  y = -340.0, r = 120.0 },  -- Mount Zonah
    { pool = 'medical',  x = 1840.0,  y = 3670.0, r = 60.0 },   -- Sandy medical
    { pool = 'medical',  x = -250.0,  y = 6320.0, r = 80.0 },   -- Paleto medical
}

-- Used when a pool is missing or empty, or an add-on ped fails to load.
Zombies.FallbackModels = { 'u_m_y_zombie_01' }   -- the custom replacement from bs_zombiepeds

-- roll is 0..1 (a cell hash or math.random). Returns a model name or nil.
function Zombies.PickModel(x, y, typeId, roll)
    local pools, name = Zombies.ModelPools or {}, nil
    if typeId == 'brute' and pools.brute then name = 'brute' end
    if not name and x and y then
        for _, a in ipairs(Zombies.PoolAreas or {}) do
            if (x - a.x) ^ 2 + (y - a.y) ^ 2 <= a.r * a.r then name = a.pool break end
        end
        name = name or ((y > 1000.0) and 'rural' or 'urban')
    end
    local pool = pools[name or 'urban'] or pools.urban
    if not pool or #pool == 0 then
        local fb = Zombies.FallbackModels
        return fb[math.floor((roll or math.random()) * #fb) + 1] or fb[1]
    end
    -- animals (a_c_*) never become walkers
    local list = {}
    for _, e in ipairs(pool) do
        if tostring(e[1]):sub(1, 4) ~= 'a_c_' then list[#list + 1] = e end
    end
    if #list == 0 then return Zombies.FallbackModels[1] end
    pool = list
    local total = 0
    for _, e in ipairs(pool) do total = total + (e[2] or 1) end
    local pick, acc = (roll or math.random()) * total, 0
    for _, e in ipairs(pool) do
        acc = acc + (e[2] or 1)
        if pick <= acc then return e[1] end
    end
    return pool[#pool][1]
end

-- Flat roster of every model in the pools (first = fallback). Built from ModelPools, do not edit by hand.
Zombies.Models = { 'u_m_y_zombie_01' }
do
    local seen = { u_m_y_zombie_01 = true }
    for _, pool in pairs(Zombies.ModelPools) do
        for _, e in ipairs(pool) do
            if not seen[e[1]] then seen[e[1]] = true; Zombies.Models[#Zombies.Models + 1] = e[1] end
        end
    end
end

-- Per-walker look. Listed drawables per component are never picked.
-- Empty now: the old replacement's invisible upper/lower drawable 0 is gone, and single-outfit add-ons only have drawable 0
Zombies.Appearance = {
    exclude = {},
    tries   = 4,
}

-- VIP health bars: cosmetic only. They annotate a walker you can already see and need line of sight.
-- Toggle with /bs_zombiehp or the admin menu's WORLD tab
Zombies.HealthBars = {
    -- The bar only shows on the one walker you are aiming at, and fades after linger seconds when you look away
    -- Range 300 m still requires clear line of sight. linger is per-player in the F7 menu; this is the fallback.
    range        = 300.0,
    linger       = 5.0,

    -- The last second of the linger is a fade.
    fadeFor      = 1.0,

    -- Full size below this distance (m); beyond it the bar shrinks.
    fullSizeUpTo = 25.0,

    width        = 0.055,
    height       = 0.0075,

    -- Segmented bar: ten notches filled from the left, matching the HUD style.
    segments     = 10,
    segmentGap   = 0.0009,

    -- How far above the head bone the bar floats, in metres.
    lift         = 0.45,

    -- Name and numbers, close range only (unreadable beyond that).
    showName     = true,
    showNumbers  = true,
    -- Name and numbers fade out and stop at this distance (m); the bar itself carries to the full range.
    textUpTo     = 70.0,

    -- Bar colours (RGB): bone when healthy, amber mid, blood low. Same palette as the HUD.
    colours = {
        high = { 216, 210, 194 },   -- bone
        mid  = { 200, 118,  58 },   -- amber
        low  = { 150,  52,  40 },   -- blood
    },
    backing = { 10, 10, 9 },

    -- VIP bar colours (RGB): the server accent palette (copper to ember). The low state matches the standard bar.
    -- Remove this table to fall back to the standard palette
    vipColours = {
        high = { 200, 118,  58 },   -- copper: the project accent, full health
        mid  = { 176,  84,  36 },   -- ember: deeper, hotter as it drops
        low  = { 150,  52,  40 },   -- blood: identical to standard
    },
    -- Slightly warmer than the standard backing so the readout stays in one colour family.
    vipBacking = { 16, 11, 8 },
}

-- Hit marker sounds: a tick on hit, a brighter one for headshots, a thud on kill
-- Toggled per player in the F7 VIP menu
Zombies.HitMarker = {
    file       = 'hitmarker.wav',
    headFile   = 'hitmarker_head.wav',
    killFile   = 'hitmarker_kill.wav',

    -- Headshot is the loudest
    volume     = 0.70,
    headVolume = 0.85,
    killVolume = 0.80,
}

-- Draw distance. lodDistance (SetEntityLodDist) is how far the entity draws at all
-- A low multiplier makes clothes flicker at range and eventually despawn visually
Zombies.Render = {
    -- Do not max these out: 65535 and 12.0 made walkers invisible (present and solid but not drawn). 1000 / 4.0 are safe.
    -- If clothes flicker through a scope, raise lodMultiplier in small steps and check walkers are still visible up close
    lodDistance   = 1000,
    lodMultiplier = 4.0,
}

-- Sounds. Each model has its own voice.
-- Base-game peds have no zombie growl
Zombies.Voices = {
    -- Shambling, alerted, chasing voices.
    lurk = {
        'z_lurk_1.ogg', 'z_lurk_2.ogg', 'z_lurk_3.ogg',
        'z_lurk_4.ogg', 'z_lurk_5.ogg', 'z_lurk_6.ogg',
    },

    -- Feeding voices. Quieter and shorter-ranged than the lurk voice.
    eat = {
        'z_eat_1.ogg', 'z_eat_2.ogg', 'z_eat_3.ogg', 'z_eat_4.ogg',
    },

    -- How far each walker's own pitch may stray from 1.0 (fixed per walker from its id). 0.18 is about three semitones.
    -- Higher = rougher crowd, 0.0 = off
    voicePitchRange = 0.18,

    -- How the lurk voice behaves
    -- Interval window in ms (roughly every 15 s per walker); keep it wide so groups do not fall into unison
    lurkInterval    = { 12000, 18000 },
    lurkPitch       = { 0.78, 1.0 },
    lurkVolume      = 0.55,
    lurkMaxDistance = 30.0,
    -- Hard cap in metres: no zombie voice is heard past this.
    hearDistance = 30.0,

    -- Feeding audio repeats more often than the lurk voice so it reads as continuous
    -- Clips are 6-20 s, so roughly the next one starts when the last ends (ms)
    eatInterval     = { 6000, 11000 },
    eatPitch        = { 0.9, 1.08 },
    eatVolume       = 0.70,

    -- Max distance in metres at which the eating sound is audible
    -- Keep it above Feeding.debugDistance (22), or the staff-spawned feeder is silent
    eatMaxDistance  = 30.0,

    -- Cue pools (attack, death, alerted). Empty pools fall back to the walker's own lurk voice.
    -- To add sounds: drop files in bs_ui/html/sound/, list them below, restart bs_ui and bs_zombies, test with /soundtest <file.ogg> 12
    attack  = { 'z_attack_1.ogg', 'z_attack_2.ogg', 'z_attack_3.ogg' },
    death   = { 'z_death_1.ogg', 'z_death_2.ogg', 'z_death_3.ogg' },
    alerted = { 'zombie_breathing1.ogg', 'zombie_breathing2.ogg' },

    -- Death fade in ms, so the voice sags away instead of cutting off. 600 works well; under 300 sounds like a cut, over 900 lingers.
    -- Horde bed: one looping emitter ('zed:horde') at the centroid of nearby walkers, never one per walker
    horde = {
        enabled   = true,
        file      = 'large_zombie_horde.ogg',

        -- Walkers within the radius needed to start the horde bed
        -- Below this the individual voices are the right texture
        count     = 20,
        radius    = 45.0,

        -- Hysteresis: the bed stops only when the count drops below count - dropoff, so it does not toggle.
        dropoff   = 5,

        volume      = 0.5,
        maxDistance = 70.0,
        fadeIn      = 2500,
        fadeOut     = 3500,

        -- How often the count is taken, ms.
        checkMs   = 1500,
    },

    deathFade       = 600,

    -- Fade in ms when a walker stops feeding without dying
    -- Short, since a walker coming for you must not keep chewing
    stopFade        = 150,

    -- How often (ms) a playing voice is told where its walker is, so the sound follows it
    -- About 200 is smooth; past ~500 it sounds like skating. Cost is bounded by UI.Audio.maxVoices.
    moveInterval    = 200,

    -- Safety timeout in ms for the position updater. Must be longer than the longest clip (~20 s for eat files).
    voiceTrackTimeout = 30000,
}

-- Model-specific pain ids only. Used only if Settings.enginePainFallback is on.
Zombies.Sounds = {
    ['s_m_y_zombie_01'] = { pain = { 6, 7, 8 } },
    ['u_m_y_zombie_01'] = { pain = { 9, 10, 11 } },
    default             = { pain = { 6, 8, 10 } },
}

-- Cues: moments, not voices
-- A cue holds how the walker's own voice is played at that moment (louder for an attack, lower for a death)
Zombies.Cues = {
    -- When one first notices you. A rising groan.
    alerted = { pitch = { 0.74, 0.92 }, volume = 0.58, maxDistance = 30.0,
                pain = { 6, 9, 10 } },

    -- Mid-attack. Closer and more insistent.
    attack  = { pitch = { 0.92, 1.10 }, volume = 0.70, maxDistance = 22.0,
                pain = { 7, 8, 9 } },

    -- On death. Low, slow and short.
    death   = { pitch = { 0.52, 0.66 }, volume = 0.62, maxDistance = 26.0,
                pain = { 2, 3 } },

    -- Feeding. The only cue that uses the walker's second (eat) voice. See Zombies.Voices.
    eating  = { pitch = { 0.90, 1.08 }, volume = 0.70, maxDistance = 30.0,
                voice = 'eat' },
}

-- Feeding: some walkers crouch over a kill instead of lurking
-- A feeder always prefers something alive
Zombies.Feeding = {
    -- Share of walkers (0-1) that spawn already feeding. Only walkers and brutes feed.
    share = 0.10,
    types = { walker = true, brute = true },

    -- Sense multipliers while feeding. Sight at 0.2 means a 28 m walker needs you within about 6 m.
    -- Hearing at 0.33 lets gunshots through but not footsteps
    senseScale = 0.20,
    hearScale  = 0.33,

    -- What it eats
    -- Animals are the common case (about two thirds of meals)
    meals = {
        { model = 'a_c_rat',           weight = 42, animal = true },
        { model = 'a_c_rabbit_01',     weight = 24, animal = true },
        { model = 'a_c_deer',          weight = 6,  animal = true },
        { model = 'a_c_pigeon',        weight = 6,  animal = true },
        { model = 'a_c_crow',          weight = 4,  animal = true },

        { model = 'a_m_y_hipster_01',  weight = 8,  civilian = true },
        { model = 'a_f_y_tourist_01',  weight = 7,  civilian = true },
        { model = 'a_m_m_farmer_01',   weight = 7,  civilian = true },
        { model = 'a_m_y_business_01', weight = 6,  civilian = true },
    },

    -- Max distance in metres between feeder and meal (sanity check).
    maxMealDistance = 2.0,

    -- Seconds a meal lingers after its eater dies or stops eating. It is decoration only (local ped, not lootable).
    mealLingerSeconds = 600,

    -- Player bodies (bs_medical) pull idle walkers within radius to feed, at most maxFeeders per body
    -- The body itself is never deleted here
    playerCorpses = { enabled = true, radius = 35.0, maxFeeders = 3 },

    -- Small animals are held in the walker's hands
    handHeld = {
        a_c_rat         = { bone = 57005, pos = { 0.12, 0.02, -0.02 }, rot = { 0.0, -90.0, 0.0 } },
        a_c_rabbit_01   = { bone = 57005, pos = { 0.14, 0.05, -0.05 }, rot = { 10.0, -90.0, 0.0 } },
        a_c_pigeon      = { bone = 57005, pos = { 0.12, 0.03, -0.02 }, rot = { 0.0, -90.0, 0.0 } },
        a_c_crow        = { bone = 57005, pos = { 0.12, 0.03, -0.02 }, rot = { 0.0, -90.0, 0.0 } },
        a_c_chickenhawk = { bone = 57005, pos = { 0.14, 0.04, -0.03 }, rot = { 0.0, -90.0, 0.0 } },
        a_c_cat_01      = { bone = 57005, pos = { 0.16, 0.06, -0.08 }, rot = { 10.0, -90.0, 0.0 } },
    },

    -- Spawn distance in metres for the staff debug button
    -- Outside the ~6 m a feeder can see, close enough to watch and hear it
    debugDistance = 22.0,
}

-- Archetypes

Zombies.Types = {
    walker = {
        label       = 'Walker',
        -- Spawn weight.
        weight      = 93,
        health      = 220,
        armour      = 0,

        -- Movement rates. 1.0 is a normal human walk.
        -- Keep these low: you should be able to walk away from one walker, the danger is the others behind it
        shambleRate = 1.0,
        -- Investigating a noise. Purposeful without being a chase (see setChase in cl_ai.lua).
        drawnRate   = 1.0,
        -- A walker that has seen you gets urgent, not fast. Still slower than a player's jog.
        chaseRate   = 1.0,

        damage      = 14,
        -- Sight radius in metres, needs clear line of sight and is reduced by stealth perks
        -- Too low and walkers stay in idle (wandering) almost always. Hearing is the main sense.
        senseRadius = 28.0,
        -- Hearing. This is the sense that matters.
        hearRadius  = 44.0,
        loseRadius  = 48.0,
        -- How long they keep coming after losing you (ms).
        persistence = 9000,
        -- Delay before committing (ms), so they lurch rather than snap.
        aggroDelay  = 900,

        reward      = 'zombie_kill',
        loot        = 'walker',
    },

-- There is no runner class
-- If a fast infected is ever wanted, add it back with Settings.maxMoveRate lifted for that type

    brute = {
        label       = 'Brute',
        weight      = 5,
        health      = 850,
        armour      = 60,
        shambleRate = 1.0,
        drawnRate   = 1.0,
        chaseRate   = 1.0,
        chaseAnim   = nil,   -- a brute lumbers, it does not jog
        damage      = 42,
        senseRadius = 30.0,
        hearRadius  = 48.0,
        loseRadius  = 60.0,
        persistence = 14000,
        aggroDelay  = 1300,
        -- Shrugs off body shots almost entirely.
        bodyResist  = 0.18,
        reward      = 'zombie_kill_brute',
        loot        = 'brute',
    },

    -- The screamer archetype was removed. Its zone share went to walker in config_zones.lua.
    -- Re-add by pasting a new block here


    -- The crawler: no working legs, comes at you on its belly. Slowest type, low and quiet.
    -- It does not spawn naturally: composition comes from the per-zone types weights in config_zones.lua
    crawler = {
        label       = 'Crawler',
        weight      = 0,

        -- Low health: a crawler is hard to see and hit, so it must be easy to kill
        health      = 90,
        armour      = 0,

        -- Move-rate overrides (animation playback speed), slower than a walker in every gear
        -- Settings.maxMoveRate still clamps them in setChase()
        shambleRate = 1.0,
        drawnRate   = 1.0,
        chaseRate   = 1.0,

        -- noClipset makes it crawl: a movement clipset would override the crawl animation
        -- It is checked in cl_sync.lua applyGait() and spawn(), and cl_ai.lua setChase(). Do not remove it.
        noClipset   = true,

        -- Marks this type as a crawler. Clips are named in Zombies.Crawl.
        crawls      = true,

        -- SetPedMaxMoveBlendRatio ceiling (0 still, 1 walk, 2 run, 3 sprint), re-applied every think tick since the engine resets it on task changes
        -- Keep 1.0 for the crawler too: lower values make the nav task stutter. Speed comes from the rates above.
        maxBlend    = 1.0,

        damage      = 12,

        -- Short sight, ordinary hearing. Crawlers notice you late; sound is the main sense.
        senseRadius = 16.0,
        hearRadius  = 40.0,
        loseRadius  = 30.0,

        -- Long persistence vs short sight: once it has you it keeps coming, slowly.
        persistence = 16000,
        aggroDelay  = 1100,

        -- Body damage is multiplied by (1 - bodyResist) in cl_combat.lua. 0.35 = a body shot lands about 65% of its damage.
        -- Only toughness stat for crawlers
        bodyResist  = 0.35,

        reward      = 'zombie_kill',
        -- Uses the walker loot table. bs_economy resolves loot by name, so a 'crawler' table must exist there before you change this.
        loot        = 'walker',
    },
}

-- Animation

Zombies.Anims = {
    -- DLC zombie clipsets (mp2024_01) are tried first
    -- Older builds fall back to the sets below via HasAnimSetLoaded
    zombieCore   = 'clipset@anim@ingame@move_m@zombie@core',
    zombieStrafe = 'clipset@anim@ingame@move_m@zombie@strafe',

    -- Share of walkers that keep a drunk walk instead of the DLC zombie one (0.0-1.0)
    -- Picked from each walker's id, so it is stable
    drunkShare   = 1.0,

    -- Movement clipsets.
    shamble = 'move_m@drunk@verydrunk',
    chase   = 'move_m@drunk@verydrunk',

    -- Each walker picks one of these for life, chosen from its own id (see cl_sync.lua), so a crowd does not move in lockstep
    -- All base game clipsets
    shambleSet = {
        'move_m@drunk@verydrunk',
    },
    -- Female ped models (IsPedMale false). move_f@drunk@a is the only female drunk clipset in the base game.
    -- Empty this list to make female models use shambleSet
    femaleShambleSet = {
        'move_f@drunk@a',
    },
    -- Idle behaviours when nothing is happening.
    idle    = { 'WORLD_HUMAN_STAND_IMPATIENT', 'WORLD_HUMAN_BUM_STANDING' },
    -- Feeding on a corpse.
    feed    = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
}
-- The crawl anim is a donated asset: see nutria_crawl_anims

-- Crawler locomotion settings. crawl_steps.ycd is made by Nutria and streamed by nutria_crawl_anims.
-- The dictionary name is the file name, so do not rename it. Start that resource before bs_zombies.
Zombies.Crawl = {
    -- Dictionary and clip used while moving. crawl_loop is the only looping clip; the dictionary also has crawl_step_01.._22 and crawl_turn_01.._22.
    dict = 'crawl_steps',
    loop = 'crawl_loop',

    -- Other clips in the dictionary, unused. Try one by editing loop or turnClip. Untested, so results may vary.
    steps = (function()
        local t = {}
        for i = 1, 22 do t[i] = ('crawl_step_%02d'):format(i) end
        return t
    end)(),
    turns = (function()
        local t = {}
        for i = 1, 22 do t[i] = ('crawl_turn_%02d'):format(i) end
        return t
    end)(),

    -- Anim flag 1 (repeat)
    -- The crawl is a primary task because the engine drops secondary tasks whenever the primary one changes
    flag     = 1,
    blendIn  = 8.0,
    blendOut = -8.0,

    -- Locked root motion: the clip only supplies the pose and cl_crawl.lua handles all movement
    -- Baked root motion speed ignores SetPedMoveRateOverride
    lockRootMotion = true,

    -- Playback rate while moving. Raise it if the crawler skates, lower it if it moonwalks.
    -- The pose is frozen (rate 0) when not moving
    speed = 1.0,

    -- Crawler speed. shambleRate/drawnRate/chaseRate are move-rate multipliers
    metresPerSecond = 1.45,
    maxSpeed        = 0.9,

    -- Turning. turnRate is degrees per second. faceAngle is how far off the goal bearing it can be and still move.
    turnRate      = 110.0,
    faceAngle     = 40.0,
    turnClip      = nil,
    turnClipAngle = 25.0,

    -- Arcing
    -- Speed scales with how far off the goal bearing it is, so it carves turns. stopAngle is the only hard stop (it turns on the spot).
    stopAngle     = 120.0,
    minMoveFactor = 0.08,

    -- Arrival distance in metres
    -- Keep it inside Zombies.Attack.range (1.55) or the crawler stops out of its own reach
    arrive = 1.0,

    -- Ground following. stepUp is the tallest rise accepted; anything taller counts as a wall, so crawlers cannot climb stairs.
    -- Limits are in metres
    stepUp   = 0.45,
    stepDown = 1.2,

    -- maxDescentPerSec caps how fast it can drop (m/s)
    maxDescentPerSec = 3.0,
    fallRescue       = 1.8,
    -- Entity z above the ground while crawling (ped root = pelvis). Lower if it floats.
    crawlZOffset     = 1.0,

    -- Obstacle probing, not pathfinding
    -- A capsule probe every probeEvery ms; on a hit it steers off by avoidAngle for avoidFor ms
    probeEvery    = 220,
    probeDistance = 1.1,
    probeRadius   = 0.35,
    probeHeight   = 0.35,
    probeFlags    = 17,
    avoidAngle    = 55.0,
    avoidFor      = 900,

    -- Three whiskers (left, centre, right) give a gradient so it curves along walls instead of snapping off at a fixed angle
    whiskerAngle  = 42.0,
    whiskerMemory = 1200,

    -- Idle drift is handled by cl_crawl.lua, not a task
    -- Anchor follows the crawler, leash limits wandering, with pauses between legs
    legMin     = 3.0,
    legMax     = 9.0,
    legTimeout = 20000,
    pauseMin   = 2400,
    pauseMax   = 7000,
    leash      = 12.0,
    anchorLerp = 0.02,

    -- Resume the clip where it was instead of restarting at frame 0
    -- Only matters after an outside task clear (revive, ragdoll recovery)
    preservePhase = true,

    -- Dictionary stream timeout and retry delay, in ms
    -- If nutria_crawl_anims is missing the crawler stays upright and the console names the resource once
    dictTimeout = 5000,
    dictRetry   = 15000,
}


-- Attacks: a walker takes hold and bites. Mash the jump key to break free early.
Zombies.Attack = {
    -- Dodging (cl_attack.lua, evaded())
    -- The claw only lands on someone slower than evadeSpeed m/s
    evadeSpeed  = 1.8,
    cornerProbe = 1.2,
    cornerCrowd = 3,
    -- Minimum bite damage after armour reduction.
    minBite = 2,

    -- Close enough to swing at you (m).
    range        = 1.55,

    -- Per walker, ms between swings.
    cooldown     = 1400,

    -- windup: ms from animation start until the claw connects
    windup       = 420,
    reach        = 1.9,
    -- How long the swing animation runs before the walker settles (ms).
    swingTime    = 1100,

    -- Damage when a claw lands, before armour.
    biteDamage   = 12,

    -- The walker swings and the player is not put into an animation
    -- The list below is the grab clips; keep punch or kick style paired clips out
    grabAnims = {
        -- Alien lunges and seizes with both hands. Base game, human skeleton.
        { dict = 'rcmbarry', clip = 'bar_1_attack_intro_aln', flag = 48 },
        -- Rockstar's zombie two-hand shove (only on builds that ship it).
        { dict = 'anim@ingame@melee@unarmed@streamed_core_zombie', clip = 'shove', flag = 48 },
        -- Same alien, struggling/biting loop, played as a one-shot.
        { dict = 'rcmbarry', clip = 'bar_1_attack_idle_aln', flag = 48 },
        -- One-armed snatch, last resort.
        { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', flag = 48 },
    },

    -- Old name, same table as grabAnims (not a copy).

    -- Guard list: clips whose name contains one of these fragments are skipped (case-insensitive plain find), with a console message
    forbiddenClipFragments = { 'punch', 'kick', 'stomp', 'ground_attack', 'boxing', 'jab' },

    -- Extra ms allowed on top of a grab's own length before it counts as stranded and is cleaned up.
    strandedGraceMs = 2500,
}

-- Old name for grabAnims, same table.
Zombies.Attack.swingAnims = Zombies.Attack.grabAnims

-- Reachers: some walkers walk with arms out front (upper-body anim over the shamble)
-- Chosen by the same cell hash as other per-walker traits, so it is stable
Zombies.Reach = {
    -- Off by default: the looped arms-out layer freezes the upper body and kills the drunk walk.
    enabled = false,

    -- Share of walkers that reach (0.0-1.0).
    chance  = 0.42,

    -- Both arms forward at chest height, upper body only (flag 49) so the legs keep the shamble walk. Base game.
    dict    = 'anim@heists@box_carry@',
    clip    = 'idle',
    flag    = 49,

    -- Only reach while hunting, stop when they lose you.
    whileHunting = true,
}

-- Executions: press E next to a walker for a one-hit kill. Animation depends on the weapon in hand.
-- Works best from behind; refused once the walker has committed to you
Zombies.Execute = {
    enabled   = true,
    key       = 38,        -- E (INPUT_PICKUP)
    range     = 1.8,
    -- Rear arc counted as behind it. 1.0 = directly behind.
    behindDot = -0.1,
    -- Refuse once it is actively hunting you.
    onlyUnaware = true,
    cooldown  = 1200,

    anims = {
        knife = { dict = 'melee@knife@streamed_core', clip = 'ground_attack_on_spot', time = 1100 },
        fists = { dict = 'melee@unarmed@streamed_core', clip = 'ground_attack_on_spot', time = 1500 },
    },

    -- Weapons that count as a blade for the animation choice.
    blades = { 'WEAPON_KNIFE', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_SWITCHBLADE',
               'WEAPON_DAGGER', 'WEAPON_BOTTLE', 'WEAPON_STONE_HATCHET' },
}

-- Aimed melee finisher: hold aim (RMB) with a melee weapon and attack a walker in front for a head strike kill.
Zombies.Finisher = {
    enabled   = true,
    range     = 1.6,
    frontDot  = 0.5,     -- how much it must be in front of you (1.0 = dead ahead)
    cooldown  = 1500,
    unarmed   = true,    -- bare hands count too
    stamina   = 0.0,     -- stamina cost (0 = off)
    killAt    = 0.55,    -- fraction of the anim where the kill is reported
    -- Clip pairs (from DurtyFree animDictsCompact). plyr = player, victim = zombie.
    anims = {
        hatchet = { dict = 'melee@hatchet@streamed_core', plyr = 'plyr_front_takedown', victim = 'victim_front_takedown', time = 1600 },
        knife   = { dict = 'melee@knife@streamed_core', plyr = 'plyr_knife_front_takedown', victim = 'victim_knife_front_takedown', time = 1500 },
        large   = { dict = 'melee@large_wpn@streamed_core', plyr = 'plyr_front_takedown_bat_headhit', victim = 'victim_front_takedown_bat_headhit', time = 1600 },
        small   = { dict = 'melee@small_wpn@streamed_core', plyr = 'plyr_front_takedown', victim = 'victim_front_takedown', time = 1500 },
        fists   = { dict = 'melee@unarmed@streamed_core', plyr = 'plyr_takedown_front_uppercut', victim = 'victim_takedown_front_uppercut', time = 1500 },
    },
    weapons = {
        hatchet = { 'WEAPON_HATCHET', 'WEAPON_STONE_HATCHET', 'WEAPON_MACHETE', 'WEAPON_BATTLEAXE' },
        knife   = { 'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE', 'WEAPON_DAGGER', 'WEAPON_BOTTLE' },
        small   = { 'WEAPON_HAMMER', 'WEAPON_WRENCH', 'WEAPON_NIGHTSTICK', 'WEAPON_FLASHLIGHT', 'WEAPON_KNUCKLE' },
        -- Anything else in GROUP_MELEE uses large (bat, crowbar, golf club, pool cue...).
    },
}

Zombies.Horde = {
    enabled        = true,
    -- Chance per director pass, per zone, before heat scaling.
    baseChance     = 0.018,
    cooldown       = 900,
    size           = { min = 10, max = 24 },
    -- A horde walks toward the noise that summoned it.
    followNoise    = true,
    -- Warning before it arrives, in seconds.
    warning        = 12,
}

-- Noises bs_zombies raises on its own. bs_emotes owns the noise API.

Zombies.NoiseSources = {
    -- Corpse noise: off
    -- It was a local-only event (never reached the server), so it gave no spawns and only made nearby zombies react
    corpse = false,

    -- Radius (m) used when corpse is true.
    corpseRadius = 14.0,
}

-- Damage model
-- Hits are detected from the shooter by raycast, never from the victim's health, because HasEntityBeenDamagedByEntity fails too often to trust

Zombies.Damage = {
    -- Max distance (m) a bullet is traced. Shots past this are ignored.
    maxRange = 250.0,

    -- Death is by headshot only
    -- Body damage lowers health but stops at bodyFloor, so a wrecked walker keeps coming until it is shot in the head
    bodyFloor = 10,

    -- Guns kill by headshot only (body shots stop at bodyFloor). false: body shots can kill.
    -- Melee always kills anywhere. F1 setting, per-difficulty presets.
    headshotOnly = true,

    -- Body and melee damage scale with player level (bs_core) and combat skill (bs_skills). mult = min +
    -- Headshot kills are unaffected
    progression = {
        enabled = true,
        min = 0.6,          -- level 1 / skill 0
        max = 1.2,          -- max level / max skill
        maxLevel = 60,      -- bs_core Config.Progression.maxLevel
        skillTree = 'combat',
        skillMax = 20,      -- combat tree maxLevel
        levelWeight = 0.5,
        curve = 1.0,
    },

    -- Strict headshot: the nearest bone to the impact must be the head bone and within headRadius of it.
    strictHeadshot = true,
    headRadius     = 0.22,

    -- Damage multipliers by body region. Head is absent: a headshot is a kill, not a number.
    regionScale = {
        torso = 1.00,
        arm   = 0.40,
        leg   = 0.40,
    },

    -- Legs: this many hits and the walker goes down permanently and becomes a crawler (cl_crawl.lua).
    legHitsToCrawl = 2,

    -- A hit arm drops what it is carrying. Cosmetic while walkers are unarmed.
    armDisarms = true,

    -- Melee uses a sphere in front of the player instead of a ray
    -- Nearest walker in the cone takes the hit, one walker per swing
    meleeRange     = 2.4,
    meleeHalfAngle = 60.0,

    -- Server anti-cheat headroom: a reported hit is clamped to the weapon's raw damage times this, anything above is refused and counted
    serverHeadroom = 1.6,

    -- Max distance (m) the server accepts for a reported hit, checked against the shooter's real position.
    serverMaxRange = 300.0,

    -- Shots per second one client may report before the rest are refused. A rifle is about 12/s.
    maxShotsPerSecond = 30,
}

-- Difficulty scaling (F1, per preset). 1.0 = the numbers above as written.
-- Each stat can also follow progression
Zombies.Difficulty = {
    healthMult  = 1.0,   -- walker health, set by the server at spawn
    speedMult   = 1.0,   -- move rate (non-drunk gaits, crawlers, the server lure)
    damageMult  = 1.0,   -- claw damage to players
    hordeMult   = 1.0,   -- horde and event wave sizes
    densityMult = 1.0,   -- networked walker caps
    speedCeiling = 1.35, -- absolute top move rate after scaling
    -- Also push the scaled rate onto drunk walkers
    -- Off: the drunk clip keeps its own speed (a rate override can break it)
    speedOnDrunkGait = false,
    Progression = {
        enabled  = false,
        radius   = 250.0,  -- players within this (m) count
        maxLevel = 60,     -- bs_core Config.Progression.maxLevel
        health   = { enabled = true,  min = 0.9, max = 1.4 },
        speed    = { enabled = false, min = 1.0, max = 1.1 },
        damage   = { enabled = true,  min = 0.8, max = 1.3 },
        horde    = { enabled = true,  min = 0.8, max = 1.4 },
        density  = { enabled = false, min = 0.9, max = 1.2 },
    },
}

-- Spawn mode and density.

Zombies.Spawn = {
    -- Which system decides where walkers come from
    -- 'simulation' is the node model: invisible zombies live in 50m density cells and get promoted to real records near players
    mode = 'simulation',

    density = {
        -- The main number to tune
        -- Zone multipliers from config_zones.lua apply on top (wilds 0.6, ordinary 1.0, urban 1.4): base 25 gives 35 in urban, 25 in town, 15 in the wilds
        base = 25,

        -- Target is per player, so a solo server feels as full as a busy one. The pool is split by clusterCap.
        perPlayer = true,

        -- Hard ceiling on walkers
        -- GTA's ped pool is 256 entries for everything, and cl_pools.lua already culls at 215 to avoid the 'Pool Full' crash
        clusterCap = 90,

        -- Players standing together share the pool instead of each getting a full allowance
        -- The per-player target applies until the cap is hit, then it is divided
        minPerPlayer = 8,
    },
}

-- Players in vehicles vs walkers (cl_vehicle.lua + bs:z:vehhit on the server).
Zombies.Vehicle = {
    -- Classes that never protect (8 motorcycles, 13 cycles, 14 boats).
    openClasses    = { [8] = true, [13] = true, [14] = true },
    -- Models that never protect regardless of class (quads etc).
    openModels     = { 'blazer', 'blazer2', 'blazer3', 'blazer4', 'blazer5', 'verus', 'outlaw' },
    doorOpenRatio  = 0.1,    -- door counts as open above this angle ratio

    -- Ramming, in km/h at impact.
    crippleKmh     = 30.0,   -- at or above: legs gone, becomes a crawler
    killKmh        = 90.0,   -- at or above: dead (roadkill)
    accumKillKmh   = 260.0,  -- summed impact speed across hits that also kills
    accumHardKmh   = 45.0,   -- ...but only after this many hard hits at/above this speed
    accumHardHits  = 2,
    hitCooldownMs  = 600,    -- one impact per walker per this window

    -- Running over a downed walker's head.
    crushMinKmh    = 3.0,
    crushRadius    = 0.5,    -- head to wheel centre, metres

    -- Server checks.
    serverMaxDist  = 14.0,   -- 2D, driver to walker record
    serverMinKmh   = 1.0,
    serverKillFrac = 0.6,    -- a ram kill needs car speed >= this * killKmh (crush exempt)
    proofRadius    = 15.0,   -- walkers this close to a moving car ignore engine crash damage
}
