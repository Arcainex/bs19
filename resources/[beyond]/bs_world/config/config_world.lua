-- bs_world - keeps the world empty of traffic, peds and ambient noise.

World = {}

World.Population = {
    -- Master switch. Turn off to get vanilla GTA back for testing.
    enabled          = true,

    -- Ambient traffic and pedestrians. 0.0 = none.
    vehicleDensity   = 0.0,
    pedDensity       = 0.0,
    scenarioDensity  = 0.0,

    -- Parked cars are atmosphere, not traffic, so they are kept by default. They make a dead city look abandoned.
    keepParkedCars   = true,
    -- Parked cars are capped and thinned
    -- Each one uses a VehicleStreamRequest/Render slot and both pools are fixed at 256
    parkedDensity    = 0.4,
    parkedLimit      = 30,

    -- The sweep is a backstop
    -- The density multipliers stop spawns at the source; the sweep only deletes leftovers and backs off its interval when it finds nothing
    sweepEnabled     = true,
    sweepInterval    = 3000,
    sweepIdleAfter   = 3,
    sweepIdleInterval = 60000,
    -- Never delete a vehicle a player is in, or one within this radius of one.
    sweepSafeRadius  = 3.0,

    -- Emergency services, cops responding, random events - all off.
    disableDispatch  = true,
    disableWanted    = true,
    -- Random "ambient" events (drug deals, muggers, etc).
    disableAmbient   = true,

    -- Scenario peds/vehicles spawn outside the density multipliers, so each type must be disabled by name
    -- Emergency services first, since they are the most visible
    scenarioTypes = {
        'WORLD_VEHICLE_AMBULANCE',
        'WORLD_VEHICLE_FIRE_TRUCK',
        'WORLD_VEHICLE_POLICE',
        'WORLD_VEHICLE_POLICE_CAR',
        'WORLD_VEHICLE_POLICE_BIKE',
        'WORLD_VEHICLE_POLICE_NEXT_TO_CAR',
        'WORLD_VEHICLE_SECURITY_CAR',
        'WORLD_VEHICLE_HELI_LIFEGUARD',
        'WORLD_VEHICLE_MILITARY_PLANES_BIG',
        'WORLD_VEHICLE_MILITARY_PLANES_SMALL',
        'WORLD_VEHICLE_TRUCK_LOGS',
        'WORLD_VEHICLE_TRACTOR',
        'WORLD_VEHICLE_TRACTOR_BEACH',
    },

    -- Scenario groups cover whole sets at once
    -- Use strings, not hashes: the native takes a name and a backtick literal silently does nothing
    scenarioGroups = {
        'LSA_Planes',
        'SANDY_PLANES',
        'GRAPESEED_PLANES',
        'ng_planes',
        'POLICE_POUND01',
        'POLICE_POUND02',
        'POLICE_POUND03',
    },
}

World.Environment = {
    -- Wind and dust make an empty map feel less sterile.
    windSpeed        = 1.2,
    -- Distant sirens / city hum are wrong now that nobody is left.
    muteAmbientRadio = true,

    -- Interior audio emitters (bars, clubs, shops, arcades) keep playing in an empty world
    -- One native call per name; add more to the list as you find them
    silenceEmitters = {
        'SE_DLC_Casino_Nightclub_Ambience',
        'SE_Nightclub_Music_Emitter',
        'SE_Bahama_Mamas_Nightclub',
        'SE_Tequilala_Nightclub',
        'SE_Vanilla_Unicorn_Music_Emitter',
        'SE_Strip_Club_Music_Emitter',
        'SE_Ammunation_Music_Emitter',
        'SE_LOST_CLUBHOUSE_Music_Emitter',
        'SE_Comedy_Club_Music_Emitter',
        'SE_Cinema_Music_Emitter',
        'SE_247supermarket_01_Music_Emitter',
        'SE_Barbers_Music_Emitter',
        'SE_ClothesStore_Music_Emitter',
        'SE_TattooParlour_Music_Emitter',
        'SE_Carwash_Music_Emitter',
    },
}
