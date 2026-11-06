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
    placeDistance       = 8.0,    -- how far from you a piece can go
    hammerMs            = 7000,   -- (F1) hammer time to finish a frame
    repairMs            = 5000,
    repairCostPct       = 20,     -- percent of the build cost to fully repair
    sledgeMs            = 6000,   -- (F1)
    sledgeDamage        = 60,     -- (F1)
    grinderMs           = 30000,  -- (F1) cutting a code lock off
    ramDamage           = 120,    -- (F1) per vehicle hit on fences, gates, barricades
    ramMinSpeed         = 8.0,    -- m/s
    raidAlertCooldown   = 60,     -- seconds between alerts per base
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

    -- Placing
    constructionMode    = 'mixed', -- direct for small pieces, material plans for structural work
    costOverrides       = {}, -- piece -> tier (or base) -> item quantities; managed in F1
    instantBuild        = true,   -- (F1) placing pays the cost and the piece is done after a short hammer swing. Off = frame, deposit, hammer.
    placeHammerMs       = 1500,   -- hammer swing after an instant place
    needSupport         = true,   -- (F1) walls, floors, roofs, stairs and doors need a piece to stand on (foundation, floor or wall)
    upgradeMs           = 5000,   -- (F1) hammer time for a tier upgrade

    -- Power
    powerRadius         = 20.0,   -- (F1) lights and small devices within this of a running generator get power
    poleRadius          = 12.0,   -- (F1) same around a powered pole or junction box
    wiresEnabled        = true,   -- (F1) power poles and junction boxes can be wired together
    wireMaxLength       = 40.0,   -- (F1) longest single wire, metres
    wirePerMetres       = 10.0,   -- one wire item per this many metres of cable
    wireItem            = 'electrical_wire',
    maxWiresPerNode     = 4,
    batteryItem         = 'battery',
    fuelItems           = { 'fuel_can', 'empty_bottle' },
    reserveCap          = 100,    -- fuel the jerrycan slot of a generator holds
    autoRefuelAt        = 10,     -- below this the generator tops up from its jerrycan slot
    batteryOutput       = 2,      -- power units each charged battery gives while the generator is off
    batteryDrainMin     = 1.0,    -- charge a battery loses per minute while it powers things
    batteryChargeMin    = 2.0,    -- charge a battery gains per minute from a running generator
    generatorSound      = true,   -- (F1) running generators hum (3D, fades with distance)
    generatorSoundRange = 45.0,   -- metres

    -- Faction flag removal
    flagRemoveRefundPct = 50,     -- (F1) share of the materials returned to the faction salvage crate when a flag goes
    abandonDecayHours   = 24,     -- (F1) "let it decay": pieces fall apart over this many hours

    menuDefault         = 'bar', -- build menu for players who never picked one: wheel, bar or catalogue
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
    { id = 'storage',   icon = 'box' },
    { id = 'power',     icon = 'power' },
    { id = 'furniture', icon = 'bed' },
    { id = 'utility',   icon = 'wrench' },
    { id = 'claim',     icon = 'flag' },
}

-- Upgrade order. A piece with tiers starts at its first one and is upgraded in place with a hammer.
Building.TierOrder = { 'wood', 'metal', 'concrete' }

-- Pieces
-- size = width (x), depth (y), height (z) in metres, origin = bottom centre. The client measures the real model for snapping.
-- snap = socket kind for structure pieces (they snap Rust style). Pieces without snap are placed freely.
-- support = snap kinds that hold this piece up (needSupport). 'ground' = sits on the ground.
-- tiers = { wood = { models, health, cost }, metal = {...}, concrete = {...} }. Pieces without tiers use models/health/cost.
-- parts = extra copies of the model at local offsets (door frame posts).
-- Every model below is in the base game object list. See _notes/BUILDING_PROPS.md before changing one.
Building.Pieces = {
    -- Structure
    foundation   = { cat='structure', snap='foundation', support='ground', size={6,3,0.6},
                     tiers = {
                         wood  = { models={'prop_dock_float_1'}, health=1500, cost={ {item='log',amount=4}, {item='wood_plank',amount=4}, {item='nails',amount=6} } },
                         metal = { models={'prop_metal_plates01'}, health=3000, cost={ {item='scrap_metal',amount=14}, {item='screws',amount=6} } },
                     } },
    wall         = { cat='structure', snap='wall', support={'foundation','floor','wall','doorway'}, size={3,0.25,2.5},
                     tiers = {
                         wood     = { models={'prop_fncply_01a'}, health=700, cost={ {item='wood_plank',amount=6}, {item='nails',amount=6} } },
                         metal    = { models={'prop_fnccorgm_02a'}, health=1500, cost={ {item='scrap_metal',amount=10}, {item='screws',amount=6} } },
                         concrete = { models={'prop_barier_conc_05c'}, health=3000, cost={ {item='stone',amount=14}, {item='scrap_metal',amount=4} } },
                     } },
    -- Two posts with room for a door between them
    wall_doorway = { cat='structure', snap='doorway', support={'foundation','floor','wall','doorway'}, size={3,0.25,2.5},
                     tiers = {
                         wood  = { models={'prop_fncply_01post'}, parts={ {x=-0.75}, {x=0.75} }, health=600, cost={ {item='wood_plank',amount=4}, {item='nails',amount=4} } },
                         metal = { models={'prop_fnccorgm_02pole'}, parts={ {x=-0.75}, {x=0.75} }, health=1200, cost={ {item='scrap_metal',amount=6}, {item='screws',amount=4} } },
                     } },
    floor        = { cat='structure', snap='floor', support={'wall','doorway','foundation','floor'}, size={6,3,0.5},
                     tiers = {
                         wood  = { models={'prop_dock_float_1b'}, health=700, cost={ {item='wood_plank',amount=6}, {item='nails',amount=6} } },
                         metal = { models={'prop_metal_plates02'}, health=1400, cost={ {item='scrap_metal',amount=10}, {item='screws',amount=6} } },
                     } },
    -- Fence sheets laid flat across the walls
    roof         = { cat='structure', snap='roof', support={'wall','doorway'}, size={3,3,0.2}, pitch=90.0,
                     tiers = {
                         wood  = { models={'prop_fncply_01b'}, health=600, cost={ {item='wood_plank',amount=5}, {item='nails',amount=5} } },
                         metal = { models={'prop_fnccorgm_01a'}, health=1200, cost={ {item='scrap_metal',amount=8}, {item='screws',amount=4} } },
                     } },
    stairs       = { cat='structure', snap='stairs', support={'foundation','floor'}, size={1.5,3,2.5},
                     tiers = {
                         wood  = { models={'prop_air_woodsteps'}, health=700, cost={ {item='wood_plank',amount=8}, {item='nails',amount=8} } },
                         metal = { models={'prop_portasteps_01'}, health=1400, cost={ {item='scrap_metal',amount=12}, {item='screws',amount=6} } },
                     } },
    walkway      = { cat='structure', snap='walkway', support={'wall','doorway','floor','walkway','watchtower'}, size={3,1.5,0.2},
                     models={'prop_byard_planks01'}, health=500, cost={ {item='wood_plank',amount=4}, {item='nails',amount=4} } },
    ladder       = { cat='structure', size={0.6,0.3,3.5}, health=300, support='any',
                     models={'prop_byard_ladder01'}, cost={ {item='wood_plank',amount=3}, {item='nails',amount=4} } },

    -- Doors and gates
    door         = { cat='openings', snap='door', support={'doorway'}, size={1.2,0.15,2.2}, door=true, lock=true,
                     tiers = {
                         wood  = { models={'prop_door_01'}, health=800, cost={ {item='wood_plank',amount=4}, {item='nails',amount=4}, {item='scrap_metal',amount=1} } },
                         metal = { models={'prop_ld_jail_door'}, health=1800, cost={ {item='scrap_metal',amount=10}, {item='screws',amount=6} } },
                     } },
    gate         = { cat='openings', snap='gate', support='any', size={4,0.3,2}, door=true, lock=true, ram=true,
                     tiers = {
                         wood  = { models={'prop_gate_farm_03'}, health=1200, cost={ {item='wood_plank',amount=8}, {item='nails',amount=8} } },
                         metal = { models={'prop_fnclink_02gate1'}, health=2200, cost={ {item='scrap_metal',amount=14}, {item='screws',amount=8} } },
                     } },
    gate_large   = { cat='openings', snap='gate', support='any', size={8,0.4,3}, door=true, lock=true, ram=true, slide=true,
                     models={'prop_facgate_01'}, health=4000, cost={ {item='scrap_metal',amount=30}, {item='screws',amount=12}, {item='metal_pipe',amount=4} } },

    -- Defense (placed freely)
    fence        = { cat='defense', size={3,0.3,2}, support='ground', ram=true,
                     tiers = {
                         wood  = { models={'prop_fncwood_14a'}, health=400, cost={ {item='wood_plank',amount=3}, {item='nails',amount=3} } },
                         metal = { models={'prop_fnccorgm_03a'}, health=800, cost={ {item='scrap_metal',amount=5}, {item='screws',amount=2} } },
                     } },
    mesh_panel   = { cat='defense', size={3,0.2,2}, support='ground', ram=true,
                     models={'prop_fnclink_03e'}, health=600, cost={ {item='scrap_metal',amount=4}, {item='electrical_wire',amount=1} } },
    barricade    = { cat='defense', size={2.5,0.8,1.2}, support='ground', ram=true,
                     tiers = {
                         wood     = { models={'prop_woodpile_04a'}, health=900, cost={ {item='log',amount=4} } },
                         concrete = { models={'prop_barier_conc_01a'}, health=2200, cost={ {item='stone',amount=10}, {item='scrap_metal',amount=2} } },
                     } },
    tyre_wall    = { cat='defense', size={2.5,1,1.2}, support='ground', ram=true,
                     models={'prop_tyre_wall_01'}, health=1000, cost={ {item='rubber',amount=6}, {item='scrap_metal',amount=2} } },
    spikes       = { cat='defense', size={2,1,0.3}, health=400, support='ground', ram=true, spikes=true,
                     models={'p_ld_stinger_s','prop_tyre_spike_01'}, cost={ {item='scrap_metal',amount=4}, {item='nails',amount=10} } },
    watchtower   = { construction='blueprint', cat='defense', size={3,3,4}, health=1800, support='ground',
                     models={'prop_hunterhide'}, cost={ {item='log',amount=6}, {item='wood_plank',amount=8}, {item='nails',amount=10} } },
    scaffold     = { construction='blueprint', cat='defense', size={3,1.5,3}, health=1200, support='any',
                     models={'prop_scafold_01a'}, cost={ {item='metal_pipe',amount=6}, {item='wood_plank',amount=4}, {item='screws',amount=6} } },

    -- Storage
    storage_small = { cat='storage', size={1,0.6,0.6}, health=300, support='any', storage={w=6,h=4,weight=60}, lock=true,
                      models={'prop_box_wood04a'}, cost={ {item='wood_plank',amount=4}, {item='nails',amount=2} } },
    storage_large = { cat='storage', size={1.6,0.8,1}, health=500, support='any', storage={w=10,h=6,weight=200}, lock=true,
                      models={'prop_mil_crate_01'}, cost={ {item='wood_plank',amount=8}, {item='scrap_metal',amount=4}, {item='nails',amount=4} } },
    shelf         = { cat='storage', size={2.5,1,2.5}, health=600, support='any', storage={w=8,h=6,weight=150}, lock=true,
                      models={'prop_warehseshelf01'}, cost={ {item='scrap_metal',amount=8}, {item='screws',amount=6}, {item='wood_plank',amount=2} } },
    vending_crate = { cat='storage', size={1.2,0.8,0.9}, health=500, support='any', storage={w=8,h=5,weight=150}, vending=true, limit=3,
                      models={'prop_mil_crate_02'}, cost={ {item='wood_plank',amount=8}, {item='scrap_metal',amount=6}, {item='nails',amount=6} } },
    -- Made by the server when a flag is removed. Holds the refunded materials.
    salvage_crate = { cat='storage', size={1.2,0.8,0.9}, health=500, support='any', storage={w=12,h=10,weight=500}, lock=true,
                      hidden=true, noCap=true, salvage=true, models={'prop_box_wood05a'}, cost={} },

    -- Power
    generator_small  = { cat='power', size={0.8,0.6,0.7}, health=400, support='any', generator={ output=4, fuelHour=4, tank=40, bats=1 },
                         models={'prop_generator_01a'}, cost={ {item='scrap_metal',amount=8}, {item='electronics',amount=2}, {item='electrical_wire',amount=2} } },
    generator_medium = { cat='power', size={1.2,0.8,1}, health=500, support='any', generator={ output=8, fuelHour=7, tank=80, bats=2 },
                         models={'prop_generator_02a'}, cost={ {item='scrap_metal',amount=12}, {item='engine_part',amount=1}, {item='electrical_wire',amount=3} } },
    -- id kept from v1 so old generators stay large ones
    generator        = { cat='power', size={2,1.2,2}, health=800, support='any', generator={ output=16, fuelHour=12, tank=160, bats=2, topLights=true },
                         models={'prop_generator_03b'}, cost={ {item='scrap_metal',amount=20}, {item='engine_part',amount=2}, {item='electrical_wire',amount=4} } },
    light            = { cat='power', size={0.5,0.5,2}, health=150, support='any', power=1, light={ range=16.0, intensity=6.0, spot=true },
                         models={'prop_worklight_03b'}, cost={ {item='scrap_metal',amount=2}, {item='electrical_wire',amount=1} } },
    floodlight       = { cat='power', size={1,1,4}, health=250, support='any', power=2, light={ range=30.0, intensity=10.0, spot=true },
                         models={'prop_worklight_04c'}, cost={ {item='scrap_metal',amount=6}, {item='electrical_wire',amount=2}, {item='electronics',amount=1} } },
    lamp             = { cat='power', size={0.4,0.4,0.5}, health=80, support='any', power=1, light={ range=9.0, intensity=4.0 },
                         models={'prop_construcionlamp_01'}, cost={ {item='scrap_metal',amount=1}, {item='electrical_wire',amount=1} } },
    pylon            = { cat='power', size={0.6,0.6,8}, health=600, support='ground', node=true, wireZ=-0.6,
                         models={'prop_telegraph_01a'}, cost={ {item='log',amount=3}, {item='electrical_wire',amount=2}, {item='scrap_metal',amount=2} } },
    junction         = { cat='power', size={0.6,0.4,1}, health=300, support='any', node=true,
                         models={'prop_elecbox_01a'}, cost={ {item='scrap_metal',amount=4}, {item='electrical_wire',amount=2}, {item='electronics',amount=1} } },

    -- Furniture
    sleeping_bag = { cat='furniture', size={1,2,0.2}, health=100, support='any', respawn=true,
                     models={'prop_skid_sleepbag_1'}, cost={ {item='cloth',amount=6} } },
    mattress     = { cat='furniture', size={1,2,0.3}, health=120, support='any', respawn=true,
                     models={'prop_rub_matress_01'}, cost={ {item='cloth',amount=8} } },
    bed          = { cat='furniture', size={1.4,2.1,0.6}, health=300, support='any', respawn=true,
                     models={'v_res_msonbed'}, cost={ {item='wood_plank',amount=4}, {item='cloth',amount=8}, {item='nails',amount=2} } },
    tent         = { cat='furniture', size={2.5,2.5,2}, health=250, support='ground', respawn=true,
                     models={'prop_skid_tent_01'}, cost={ {item='cloth',amount=12}, {item='metal_pipe',amount=2} } },
    chair        = { cat='furniture', size={0.6,0.6,1}, health=100, support='any',
                     models={'prop_old_wood_chair'}, cost={ {item='wood_plank',amount=2}, {item='nails',amount=2} } },
    table        = { cat='furniture', size={2,1,0.8}, health=200, support='any',
                     models={'prop_ld_farm_table01'}, cost={ {item='wood_plank',amount=4}, {item='nails',amount=4} } },
    couch        = { cat='furniture', size={2,1,0.9}, health=200, support='any',
                     models={'prop_rub_couch01'}, cost={ {item='cloth',amount=6}, {item='wood_plank',amount=2} } },
    campfire     = { cat='furniture', size={1,1,0.4}, health=100, support='ground', fire=true,
                     models={'prop_beach_fire'}, cost={ {item='log',amount=2}, {item='stone',amount=4} } },

    -- Utility
    rain_collector = { cat='utility', size={0.8,0.8,1.2}, health=300, support='any', rain=true,
                       models={'prop_wooden_barrel'}, cost={ {item='wood_plank',amount=4}, {item='cloth',amount=2} } },

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

-- Placing keys (GTA control ids). Arrows and numpad nudge, the bar menu takes the arrows while it is open.
Building.Keys = {
    place   = 24,   -- left mouse
    cancel  = 25,   -- right mouse
    back    = 177,  -- backspace
    rotL    = 14,   -- scroll
    rotR    = 15,
    fine    = 19,   -- hold left alt: 1 degree / 1 cm steps
    snap    = 21,   -- shift toggles snapping (structure) or surface snap (furniture)
    raise   = 10,   -- page up
    lower   = 11,   -- page down
    reset   = 45,   -- R: reset height and nudge
    left    = 174, right = 175, up = 172, down = 173,
    npLeft  = 108, npRight = 109, npUp = 111, npDown = 112,
}

-- Shared helpers (client and server)

function Building.TierList(d)
    local out = {}
    if not d or not d.tiers then return out end
    for _, t in ipairs(Building.TierOrder) do if d.tiers[t] then out[#out + 1] = t end end
    return out
end

-- First tier a piece has, nil for pieces without tiers.
function Building.BaseTier(d)
    return Building.TierList(d)[1]
end

-- Tier a placed piece is at. r.data.tier on the server, r.t in client views.
function Building.TierOfData(d, tier)
    if not d or not d.tiers then return nil end
    if tier and d.tiers[tier] then return tier end
    return Building.BaseTier(d)
end

-- models, health, cost and parts for one tier (or the piece itself when it has no tiers)
function Building.Spec(d, tier)
    if not d then return nil end
    if d.tiers then
        local t = Building.TierOfData(d, tier)
        return t and d.tiers[t] or nil
    end
    return d
end

function Building.NextTier(d, tier)
    local list = Building.TierList(d)
    local cur = Building.TierOfData(d, tier)
    for i, t in ipairs(list) do if t == cur then return list[i + 1] end end
    return nil
end
