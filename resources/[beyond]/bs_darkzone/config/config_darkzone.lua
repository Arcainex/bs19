-- bs_darkzone config: the rotating Dark Zone.
-- Most numbers are F1 settings (bs_config, category Dark Zone). Zones can also be edited in F1 > Dark Zone editor.

DZ = {}

DZ.Settings = {
    enabled          = false,  -- master switch, off by default
    adminAces        = { 'bs.admin', 'bs.superadmin' },

    -- rotation
    rotationHours    = 4.0,    -- how long one zone stays active
    warningMinutes   = 10,     -- broadcast this long before it moves
    radiusOverride   = 0.0,    -- 0 = each zone uses its own radius
    safePad          = 150.0,  -- extra gap kept to safezones and outposts

    -- loot
    lootTier         = 3,      -- 1 to 3, picks the crate loot table
    crateCount       = 8,      -- crates spread over the zone
    crateMinutes     = 20,     -- an emptied crate refills after this
    bagWidth         = 6,
    bagHeight        = 4,
    bagMaxWeight     = 40.0,
    dropMinutes      = 30,     -- a dropped bag stays this long

    -- zombies
    zHealth          = 1.6,
    zDamage          = 1.3,
    zSpeed           = 1.1,
    zHorde           = 1.5,
    spawnSeconds     = 40,     -- one group per player inside, this often
    spawnGroup       = 5,
    spawnMaxAlive    = 40,
    bruteChance      = 0.15,
    eliteChance      = 0.08,
    eliteHp          = 4.0,

    -- helicopter extraction
    heliSeconds      = 90,
    heliCooldown     = 300,    -- seconds before the same zone can call another one
    heliRadius       = 15.0,   -- stand this close to the flare when the heli lands
    heliWaveSeconds  = 20,
    heliWaveSize     = 6,
    requireFlare     = false,  -- true = calling the heli uses a dz_flare
    heliVisual       = true,   -- a helicopter flies in on each client (cosmetic only)

    -- walk-out extraction
    walkSeconds      = 120,
    walkRadius       = 6.0,
    walkMaxWeight    = 8.0,
    walkMaxStacks    = 4,

    -- progression
    xpMult           = 1.0,
    xpExtract        = 100,    -- per successful extraction with loot
    xpPerStack       = 15,
    xpHeliBonus      = 50,
    xpPlayerKill     = 120,
    xpZombieKill     = 4,
    xpEliteKill      = 40,
    charXpExtract    = 100,    -- normal character XP on extraction

    -- visuals
    showBoundary     = true,
    boundaryDistance = 120.0,  -- the red wall shows when you are this close to the edge
}

-- Candidate zones. One is active at a time. F1 edits are saved in the database and win over these.
-- heli / walks are optional: without them the points are put on the nearest road at the centre and the edge.
DZ.Zones = {
    { id = 'port',       label = 'Port of Los Santos', x = 900.0,   y = -3050.0, z = 6.0,   radius = 300.0 },
    { id = 'airport',    label = 'LSIA Airfield',      x = -1300.0, y = -2900.0, z = 14.0,  radius = 350.0 },
    { id = 'zancudo',    label = 'Fort Zancudo',       x = -2150.0, y = 3100.0,  z = 33.0,  radius = 400.0 },
    { id = 'humane',     label = 'Humane Labs',        x = 3560.0,  y = 3720.0,  z = 35.0,  radius = 250.0 },
    { id = 'grapeseed',  label = 'Grapeseed Farms',    x = 2450.0,  y = 4950.0,  z = 45.0,  radius = 300.0 },
    { id = 'quarry',     label = 'Davis Quarry',       x = 2950.0,  y = 2780.0,  z = 43.0,  radius = 250.0 },
    { id = 'lumber',     label = 'Paleto Lumber Mill', x = -560.0,  y = 5350.0,  z = 70.0,  radius = 220.0 },
    { id = 'powerplant', label = 'Palmer-Taylor Power',x = 2750.0,  y = 1550.0,  z = 25.0,  radius = 300.0 },
}

-- Crate loot, one table per tier. chance per row, then min..max.
DZ.Loot = {
    [1] = {
        { item = 'ammo_pistol', chance = 0.7, min = 12, max = 30 },
        { item = 'ammo_rifle', chance = 0.4, min = 10, max = 25 },
        { item = 'bandage', chance = 0.6, min = 1, max = 3 },
        { item = 'antibiotics', chance = 0.25, min = 1, max = 1 },
        { item = 'electronics', chance = 0.35, min = 1, max = 2 },
        { item = 'dz_intel', chance = 0.4, min = 1, max = 1 },
        { item = 'dz_flare', chance = 0.2, min = 1, max = 1 },
    },
    [2] = {
        { item = 'ammo_rifle', chance = 0.7, min = 20, max = 45 },
        { item = 'ammo_shotgun', chance = 0.4, min = 8, max = 20 },
        { item = 'medkit', chance = 0.35, min = 1, max = 1 },
        { item = 'antiviral', chance = 0.2, min = 1, max = 1 },
        { item = 'gun_parts', chance = 0.4, min = 1, max = 3 },
        { item = 'att_scope', chance = 0.12, min = 1, max = 1 },
        { item = 'att_grip', chance = 0.12, min = 1, max = 1 },
        { item = 'dz_intel', chance = 0.5, min = 1, max = 2 },
        { item = 'dz_sample', chance = 0.3, min = 1, max = 1 },
        { item = 'dz_flare', chance = 0.3, min = 1, max = 1 },
        { item = 'booster_dz_overdrive', chance = 0.08, min = 1, max = 1 },
    },
    [3] = {
        { item = 'ammo_rifle', chance = 0.8, min = 30, max = 60 },
        { item = 'ammo_shotgun', chance = 0.4, min = 10, max = 24 },
        { item = 'medkit', chance = 0.45, min = 1, max = 2 },
        { item = 'surgical_kit', chance = 0.15, min = 1, max = 1 },
        { item = 'antiviral', chance = 0.3, min = 1, max = 1 },
        { item = 'armour_plate', chance = 0.12, min = 1, max = 1 },
        { item = 'att_suppressor', chance = 0.12, min = 1, max = 1 },
        { item = 'att_extmag', chance = 0.15, min = 1, max = 1 },
        { item = 'assault_rifle', chance = 0.06, min = 1, max = 1 },
        { item = 'marksman', chance = 0.04, min = 1, max = 1 },
        { item = 'dz_intel', chance = 0.6, min = 1, max = 3 },
        { item = 'dz_sample', chance = 0.45, min = 1, max = 2 },
        { item = 'dz_flare', chance = 0.35, min = 1, max = 2 },
        { item = 'booster_dz_overdrive', chance = 0.12, min = 1, max = 1 },
        { item = 'booster_dz_ironhide', chance = 0.1, min = 1, max = 1 },
        { item = 'booster_dz_sentry', chance = 0.04, min = 1, max = 1 },
        { item = 'dz_pdw_warden', chance = 0.02, min = 1, max = 1 },
    },
}

-- DZ ranks. Reaching one gives its title and reward (sent to the normal inventory).
DZ.Ranks = {
    { xp = 0,     key = 'rookie' },
    { xp = 600,   key = 'scavenger', reward = { { item = 'dz_flare', amount = 2 }, { item = 'booster_dz_overdrive', amount = 1 } } },
    { xp = 1800,  key = 'stalker',   reward = { { item = 'booster_dz_ironhide', amount = 2 } } },
    { xp = 4000,  key = 'hunter',    reward = { { item = 'dz_pdw_warden', amount = 1 } } },
    { xp = 8000,  key = 'warden',    reward = { { item = 'booster_dz_sentry', amount = 1 } } },
    { xp = 14000, key = 'revenant',  reward = { { item = 'dz_rifle_revenant', amount = 1 } } },
    { xp = 22000, key = 'phantom',   reward = { { item = 'dz_shotgun_breacher', amount = 1 } } },
}

-- Named weapons: tint and damage are applied on the client while the gun is held.
DZ.Variants = {
    WEAPON_COMBATPDW    = { tint = 2, damage = 1.15 },
    WEAPON_MILITARYRIFLE = { tint = 6, damage = 1.12 },
    WEAPON_HEAVYSHOTGUN = { tint = 3, damage = 1.10 },
}

DZ.Models = {
    crate = 'prop_mil_crate_01',
    drop  = 'prop_cs_heist_bag_02',
    heli  = 'frogger',
    pilot = 's_m_y_pilot_01',
}

function DZ.RankFor(xp)
    xp = tonumber(xp) or 0
    local idx = 1
    for i, r in ipairs(DZ.Ranks) do if xp >= r.xp then idx = i end end
    return idx, DZ.Ranks[idx], DZ.Ranks[idx + 1]
end
