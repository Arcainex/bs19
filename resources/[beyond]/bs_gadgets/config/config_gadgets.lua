-- Gadgets: deployable utility + riot shield, 2 slots (default 9 / 0), PvE only.
-- Item ids keep their booster_ names so existing saves work. Item defs: bs_inventory/config/config_items.lua (category 'gadget').

Gadgets = {}

Gadgets.Slots = 2
-- 9/0: hotbar is 1-5, boosters 6/7/8. G is the downed bandage key, H is whistle.
Gadgets.DefaultKeys = { '9', '0' }
Gadgets.Command = 'bs_gadget%d'    -- renamed so the new defaults reach players who had gadget1/2 saved
Gadgets.MetaKey = 'gadgets'        -- character metadata { ['1']=item, ['2']=item }
Gadgets.CdKey = 'gadget_cd'        -- character metadata { [item] = readyAt (os.time) }
Gadgets.UseDelayMs = 800
Gadgets.PickupKey = 38             -- E, to pick your turret back up
Gadgets.PickupDist = 2.0
Gadgets.ShieldKey = 'shield_hp'    -- character metadata: durability left on a stowed shield

Gadgets.Types = {
    -- Riot shield. Model/idea from "Shield Mod" by winject (gta5-mods.com/scripts/shield-mod); that mod is a SHVDN script, this is a Lua rewrite.
    booster_shield = {
        kind = 'shield', label = 'Riot Shield', cooldown = 5,
        enabled = false,       -- shield parked: prop does not show on the arm yet; set true to re-enable
        model = 'prop_ballistic_shield', fallback = 'prop_riot_shield',
        durability = 120,      -- bites + bullets it can take
        arc = 120,             -- frontal arc it covers, degrees
        bulletHp = 4,          -- durability lost per bullet that hits it
        -- left forearm (bone 61163)
        bone = 61163, offset = vector3(0.1, -0.05, 0.0), rot = vector3(-80.0, 180.0, 10.0),
        -- Optional upper-body loop while unarmed/melee. Off by default (the original mod only uses weapons@pistol_1h@gang/aim_med_loop for aiming).
        pose = nil,            -- e.g. { dict = 'weapons@pistol_1h@gang', name = 'aim_med_loop' }
    },
    booster_drone = {
        kind = 'drone', label = 'Scout drone', cooldown = 0,   -- battery limits it instead
        model = 'ch_prop_casino_drone_02a',
        tablet = 'prop_cs_tablet',
        animDict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', animName = 'base',
        battery = 300,         -- fallback seconds of flight (small battery)
        idleDrain = 0.4,       -- hovering still drains this share of normal
        boostDrain = 1.6,      -- boosting drains this much more
        camForward = 0.35, camDown = 0.35,  -- camera sits under/in front of the props
        hidePilotDrone = true, -- pilot never sees their own drone model
        keepOnEmpty = true,    -- flat battery: drone crashes but you keep it at 0%
        maxRange = 250.0,      -- signal lost past this
        staticFrom = 0.8,      -- static starts at 80% of range
        speed = 7.0, boost = 2.2, climb = 4.0,
        smooth = true,         -- cinecam-style eased flight
        accel = 0.35,          -- seconds to ramp/coast speed (higher = more inertia)
        lookSmooth = 0.08,     -- seconds of camera rotation lag (0 = raw mouse)
        fov = 70.0,            -- drone camera field of view
        zoomFov = 25.0,        -- hold ALT: camera narrows to this FOV (x2.8 at 70/25)
        zoomSpeed = 0.18,      -- seconds of zoom easing (0 = instant)
        maxHeight = 120.0,     -- above the pilot
        health = 60,           -- a couple of hits
        markRadius = 120.0, markSecs = 60, markEveryMs = 1500, markLoot = true,
        pingSecs = 30,
        exitOnHit = true,      -- pilot gets hurt -> back to your own eyes
        fallMs = 4000,         -- battery out: drops, then despawns
    },
    booster_turret = {
        kind = 'turret', label = 'Mini turret', cooldown = 240,
        -- Static ammo crate as the base, a combat MG on top. Only the gun turns.
        model = 'prop_box_ammo04a', headModel = 'w_mg_combatmg',
        headZ = 0.08,          -- gun height above the top of the crate
        gunYaw = 90.0,         -- make it 270 if the gun faces backwards
        pitchSign = 1.0,       -- make it -1 if the barrel tilts the wrong way
        maxPitch = 20.0,       -- up/down aim limit
        turnSpeed = 180.0,     -- deg/s while tracking
        fireArc = 12.0,        -- only fires once it points within this many degrees
        sweep = 40.0,          -- idle: sweeps this far either side of the placed direction
        placeRange = 4.0, maxSlope = 0.85,  -- ground normal z at least this
        duration = 120, ammo = 80, range = 25.0, fireMs = 450, damage = 34,
        health = 300,
        scanSpeed = 20.0,      -- deg/s while idle
        pickupAnim = { dict = 'pickup_object', name = 'pickup_low' },
    },
    booster_medic = {
        kind = 'medic', label = 'Medic beacon', cooldown = 200,
        model = 'prop_med_bag_01', health = 60,
        duration = 40, radius = 10.0, tickMs = 2000, healPerTick = 4,
        placeRange = 3.0,
    },
    booster_decoy = {
        kind = 'decoy', label = 'Decoy', cooldown = 120,
        model = 'prop_boombox_01',
        duration = 25, loud = 90.0, pulseMs = 2500, placeRange = 12.0, health = 80,
        sound = 'Beep_Red', soundSet = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
    },
}

-- Drone batteries: metadata { battery = 0-100, capacity = 'small'|'medium'|'large' }.
-- Seconds of flight from full; drain %/s = 100 / secs * drainMul.
-- Defaults: about 5 / 10 / 20 minutes of normal flight.
Gadgets.Batteries = { small = 300, medium = 600, large = 1200 }
Gadgets.DrainMul = 1.0

Gadgets.Charge = {
    vehiclePerSec = 1.5,     -- % per second from a running vehicle
    generatorPerSec = 3.0,   -- % per second at a generator
    tickMs = 2000,           -- client reports this often while charging
    vehicleRange = 4.0,      -- standing next to a running vehicle
    generatorRange = 3.0,
    key = 38,                -- E / interaction to start/stop charging on foot
    generatorModels = {
        'prop_generator_01a', 'prop_generator_02a', 'prop_generator_03a', 'prop_generator_03b',
        'prop_generator_04', 'prop_rub_generator', 'prop_set_generator_01', 'ch_prop_ch_generator_01a',
    },
}

function Gadgets.BatterySecs(meta)
    local cap = type(meta) == 'table' and meta.capacity or 'small'
    return Gadgets.Batteries[cap] or Gadgets.Batteries.small
end

function Gadgets.BatteryPct(meta)
    local b = type(meta) == 'table' and tonumber(meta.battery) or nil
    if not b then return 100 end
    return math.max(0, math.min(100, b))
end

-- Visual/sound bits.
Gadgets.Fx = {
    muzzleAsset = 'core', muzzleName = 'muz_assault_rifle',
    breakAsset = 'core', breakName = 'ent_dst_electrical',
    -- destroyed by someone: sparks + smoke puff, drones also get a bang
    sparkName = 'ent_dst_elec_fire_sp', smokeName = 'exp_grd_grenade_smoke',
    boomSound = 'Explosion_External', boomSet = 'DLC_SECURITY_TAIL_AND_DESTROY_Sounds',
    deploySound = nil, deploySet = nil,   -- no activation sound
    shotWeapon = 'WEAPON_COMBATMG',       -- turret shots are harmless real bullets of this gun (sound/tracer/impact)
    pingSound = 'WAYPOINT_SET', pingSet = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
    lowSound = '5_SEC_WARNING', lowSet = 'HUD_MINI_GAME_SOUNDSET',
    droneLoop = 'Flight_Loop', droneSet = 'DLC_BTL_Drone_Sounds',
    camMod = 'scanline_cam', staticMod = 'CAMERA_secuirity_FUZZ',
}

-- Other players can shoot, hit or blow up placed gadgets and flying drones.
-- The server applies it (weaponDamageEvent / explosionEvent); never inside safe zones.
Gadgets.PvP = {
    enabled = true,
    maxDist = 250.0,       -- attacker must be this close to the gadget
    meleeDist = 4.0,
    minDamage = 5,         -- per hit
    explosionRadius = 6.0, explosionDamage = 250,
    safeZonePad = 0.0,     -- extra metres around bs_zombies safe zones
}

function Gadgets.IsGadget(item) return Gadgets.Types[item] ~= nil end
