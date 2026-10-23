-- bs_building config. Server owns the piece list; clients only draw it.
-- Defaults: no raiding, no decay, zombies never touch bases

Building = {}

Building.Settings = {
    enabled             = true,   -- (F1)
    -- anywhere = build outside blocked zones, limit per player. claim = only inside your faction flag, limit per faction.
    buildMode           = 'anywhere', -- (F1)
    playerPieceCap      = 150,    -- (F1) pieces per player, frames included
    raidsEnabled        = false,  -- (F1) off = no raiding at all: tools
    decayEnabled        = false,  -- (F1) off = bases never decay
    blockSafezones      = true,   -- (F1) no building in safezones and outposts (plus safeZonePadding)
    allowedOnly         = false,  -- (F1) only build inside allowed areas (/buildzone add allow)
    vendingEnabled      = true,   -- (F1) vending crates
    vendingMaxPrice     = 100000, -- (F1) highest price per unit
    vendingTaxPct       = 0,      -- (F1) percent of each sale that is burned
    flagRadius          = 50.0,   -- (F1) build rights radius around your faction flag
    pieceCap            = 300,    -- (F1) pieces per faction (claim mode)
    raidStartHour       = 18,     -- (F1) server clock, raids allowed from this hour
    raidEndHour         = 23,     -- (F1) ...until this hour
    raidAlways          = false,  -- (F1) ignore the window (testing)
    decayDays           = 7,      -- (F1) no member visit for this long = decay starts
    decayTickMinutes    = 30,     -- (F1) how often decaying pieces lose HP
    decayDamagePct      = 5,      -- (F1) percent of max HP lost per tick
    fullRefundMinutes   = 10,     -- (F1) demolish within this = full refund
    lateRefund          = 0.5,    -- (F1) refund after that
    respawnCooldownMin  = 5,      -- (F1) minutes between bed respawns
    streamDistance      = 150.0,  -- (F1) props drawn within this
    placeDistance       = 7.0,    -- how far from you a piece can go
    hammerMs            = 7000,   -- (F1) hammer time to finish a frame
    repairMs            = 5000,
    repairCostPct       = 20,     -- percent of the build cost to fully repair
    sledgeMs            = 6000,   -- (F1)
    sledgeDamage        = 60,     -- (F1)
    grinderMs           = 30000,  -- (F1) cutting a code lock off
    ramDamage           = 120,    -- (F1) per vehicle hit on fences, gates, barricades
    ramMinSpeed         = 8.0,    -- m/s
    raidAlertCooldown   = 60,     -- seconds between alerts per base
    generatorFuelHour   = 10,     -- fuel units burned per hour
    lightRange          = 18.0,   -- lights within this of a running generator glow
    rainPerMinute       = 2,      -- water units collected per minute of rain
    waterPerBottle      = 25,
    spikeDamage         = 8,
    safeZonePadding     = 60.0,   -- (F1) metres around safezones and outposts
    lootPadding         = 3.0,    -- client: keep clear of lootable props
    hammerItem          = 'hammer',
    grinderItem         = 'angle_grinder',
    sledgeItem          = 'sledgehammer',
    flagItem            = 'faction_flag',  -- outpost flag kit
    safezoneFlagItem    = 'safezone_flag', -- safezone flag (main base, one per player faction)
    maxOutposts         = 2,      -- (F1) outposts per player faction (vanilla factions get 1)
    raidDeclareMinutes  = 180,    -- (F1) how long a declared raid lasts
    raidCooldownMinutes = 720,    -- (F1) wait before the same faction can declare again
    -- Materials: frames and repairs also pull from your faction's storage boxes and crafting stations nearby.
    pullFromStorage     = true,   -- (F1)
    storageRadius       = 10.0,   -- (F1) metres
    costScale           = 1.0,    -- (F1) multiplies every piece cost (0.5 = half price)
    freeBuildAdmins     = false,  -- (F1) every admin builds for free, no F10 toggle needed
}

-- Fixed build areas on top of the ones staff add in game with /buildzone. kind = 'block' (no building) or
-- Circles: x, y, radius
Building.Zones = {
    -- { kind = 'block', label = 'Airport', x = -1336.0, y = -3044.0, radius = 400.0 },
}

-- Damage by GTA explosion type (server explosionEvent). Unlisted types do nothing.
Building.Explosions = {
    [0]  = 250,   -- grenade
    [2]  = 900,   -- sticky bomb (c4)
    [25] = 300,   -- grenade launcher
    [36] = 150,   -- rocket minor
    [43] = 450,   -- pipe bomb
    [44] = 450,
    [47] = 450,
}
Building.ExplosionRadius = 4.0

Building.Categories = {
    { id = 'structure', icon = 'house' },
    { id = 'openings',  icon = 'door' },
    { id = 'defense',   icon = 'shield' },
    { id = 'utility',   icon = 'box' },
    { id = 'claim',     icon = 'flag' },
}

-- size = width (x), depth (y), height (z) in metres, origin = bottom centre. support: no longer checked.
-- Every piece can go anywhere, foundations are optional
Building.Pieces = {
    -- Flat plank deck. First model the game has wins; the pallet pile is the last resort.
    foundation   = { cat='structure', size={3,3,0.3}, health=1500, support='ground', models={'prop_dock_float_1b','prop_dock_float_1','prop_skate_flatramp','prop_pallet_pile_01'},
                     cost={ {item='log',amount=4}, {item='scrap_metal',amount=3} } },
    wall         = { cat='structure', size={3,0.25,3}, health=1000, support={'foundation','floor','wall','floor_frame'}, models={'prop_fnccorgm_02a','prop_fncwood_14a','prop_const_fence01a'},
                     cost={ {item='wood_plank',amount=4}, {item='scrap_metal',amount=3}, {item='nails',amount=4} } },
    wall_doorway = { cat='structure', size={3,0.25,3}, health=900, support={'foundation','floor','wall','floor_frame'}, models={'prop_fnccorgm_05a','prop_fncwood_13c'},
                     cost={ {item='wood_plank',amount=4}, {item='scrap_metal',amount=2}, {item='nails',amount=4} } },
    wall_window  = { cat='structure', size={3,0.25,3}, health=900, support={'foundation','floor','wall','floor_frame'}, models={'prop_fnccorgm_03a','prop_fncwood_11a'},
                     cost={ {item='wood_plank',amount=4}, {item='scrap_metal',amount=2}, {item='nails',amount=4} } },
    floor        = { cat='structure', size={3,3,0.2}, health=900, support={'wall','wall_doorway','wall_window','foundation','walkway','watchtower'}, pitch=90.0, models={'prop_fncwood_14a','prop_pallet_pile_01'},
                     cost={ {item='wood_plank',amount=5}, {item='nails',amount=6} } },
    floor_frame  = { cat='structure', size={3,3,0.2}, health=800, support={'wall','wall_doorway','wall_window','foundation'}, pitch=90.0, models={'prop_fncwood_13c','prop_pallet_pile_01'},
                     cost={ {item='wood_plank',amount=4}, {item='nails',amount=6} } },
    roof         = { cat='structure', size={3,3,0.3}, health=900, support={'wall','wall_doorway','wall_window'}, pitch=70.0, models={'prop_fnccorgm_01a','prop_fnccorgm_02a'},
                     cost={ {item='scrap_metal',amount=6}, {item='nails',amount=4} } },
    stairs       = { cat='structure', size={3,3,3}, health=800, support={'foundation','floor'}, models={'prop_byard_ladder01','prop_ladder_01'},
                     cost={ {item='wood_plank',amount=6}, {item='nails',amount=6} } },
    walkway      = { cat='structure', size={3,1.5,0.2}, health=600, support={'wall','floor','foundation','walkway','watchtower'}, pitch=90.0, models={'prop_fncwood_14b','prop_fncwood_14a'},
                     cost={ {item='wood_plank',amount=3}, {item='nails',amount=3} } },

    door         = { cat='openings', size={1.2,0.15,2.2}, health=800, attach='wall_doorway', door=true, lock=true, models={'prop_com_ls_door_01','v_ilev_rc_door2'},
                     cost={ {item='wood_plank',amount=3}, {item='scrap_metal',amount=4}, {item='nails',amount=2} } },
    gate         = { cat='openings', size={6,0.3,3}, health=1600, support='ground', door=true, lock=true, ram=true, models={'prop_facgate_01','prop_fnclink_02gate1'},
                     cost={ {item='scrap_metal',amount=14}, {item='wood_plank',amount=4}, {item='nails',amount=6} } },
    window       = { cat='openings', size={1.4,0.1,1.2}, health=500, attach='wall_window', models={'prop_fncwood_08d','prop_fnclink_03gate5'},
                     cost={ {item='scrap_metal',amount=3} } },
    hatch        = { cat='openings', size={1.4,1.4,0.15}, health=600, attach='floor_frame', door=true, lock=true, models={'prop_pallet_02a','prop_pallet_01a'},
                     cost={ {item='wood_plank',amount=2}, {item='scrap_metal',amount=3} } },

    fence        = { cat='defense', size={3,0.3,2}, health=600, support='ground', ram=true, models={'prop_fncwood_14a','prop_fnccorgm_02a'},
                     cost={ {item='wood_plank',amount=3}, {item='nails',amount=3} } },
    barricade    = { cat='defense', size={2.5,0.8,1.2}, health=900, support='ground', ram=true, models={'prop_barier_conc_05b','prop_mp_barrier_02b','prop_woodpile_04a'},
                     cost={ {item='wood_plank',amount=4}, {item='scrap_metal',amount=2} } },
    spikes       = { cat='defense', size={2,1,0.6}, health=400, support='ground', ram=true, spikes=true, models={'p_ld_stinger_s','prop_tyre_spike_01'},
                     cost={ {item='wood_plank',amount=2}, {item='nails',amount=8} } },
    watchtower   = { cat='defense', size={3,3,6}, health=1800, support='ground', models={'prop_watchtower_01','prop_hunterhide','prop_scafold_01a'},
                     cost={ {item='log',amount=6}, {item='wood_plank',amount=8}, {item='nails',amount=10} } },

    storage_small = { cat='utility', size={1,0.6,0.6}, health=300, support='any', storage={w=6,h=4,weight=60}, lock=true, models={'prop_box_wood04a','prop_box_wood02a'},
                     cost={ {item='wood_plank',amount=4}, {item='nails',amount=2} } },
    storage_large = { cat='utility', size={1.6,0.8,1}, health=500, support='any', storage={w=10,h=6,weight=200}, lock=true, models={'prop_mil_crate_01','prop_box_wood05a'},
                     cost={ {item='wood_plank',amount=8}, {item='scrap_metal',amount=4}, {item='nails',amount=4} } },
    generator    = { cat='utility', size={1.2,0.8,1}, health=500, support='any', generator=true, models={'prop_generator_03b','prop_generator_01a'},
                     cost={ {item='scrap_metal',amount=12}, {item='engine_part',amount=1} } },
    light        = { cat='utility', size={0.5,0.5,2}, health=150, support='any', light=true, models={'prop_worklight_03b','prop_worklight_04c'},
                     cost={ {item='scrap_metal',amount=2}, {item='electrical_wire',amount=1} } },
    rain_collector = { cat='utility', size={1,1,1.2}, health=300, support='any', rain=true, models={'prop_water_barrel','prop_barrel_02a'},
                     cost={ {item='scrap_metal',amount=4}, {item='cloth',amount=2} } },
    vending_crate = { cat='utility', size={1.2,0.8,0.9}, health=500, support='any', storage={w=8,h=5,weight=150}, vending=true, limit=3,
                     models={'prop_mil_crate_02','prop_box_wood05a','prop_box_wood04a'},
                     cost={ {item='wood_plank',amount=8}, {item='scrap_metal',amount=6}, {item='nails',amount=6} } },
    sleeping_bag = { cat='utility', size={1,2,0.2}, health=100, support='any', respawn=true, models={'prop_skid_sleepbag_1','prop_rub_matress_01'},
                     cost={ {item='cloth',amount=6} } },
    bed          = { cat='utility', size={1.2,2.1,0.6}, health=300, support='any', respawn=true, models={'prop_rub_bed_01','v_res_msonbed'},
                     cost={ {item='wood_plank',amount=4}, {item='cloth',amount=8}, {item='nails',amount=2} } },

    -- Not pieces: they place the faction claim through bs_faction_bases
    -- Outpost: raidable in the raid window during a declared raid
    flag         = { cat='claim', size={0.5,0.5,4}, support='ground', flag='outpost', models={'prop_flag_us'},
                     cost={ {item='faction_flag',amount=1} } },
    -- Safezone: player factions only, one each. No PvP, no walkers, never raidable, hidden from outsiders.
    flag_safezone = { cat='claim', size={0.5,0.5,4}, support='ground', flag='safezone', models={'prop_flag_us'},
                     cost={ {item='safezone_flag',amount=1} } },
}

-- Converted from the old per-character builder (migration 031).
Building.Legacy = { barricade_wood='barricade', barricade_metal='barricade', bedroll='sleeping_bag', crate='storage_small' }

Building.Keys = {
    place  = 24,   -- left mouse
    cancel = 25,   -- right mouse
    rotL   = 14,   -- scroll
    rotR   = 15,
    snap   = 21,   -- shift toggles snapping
}
