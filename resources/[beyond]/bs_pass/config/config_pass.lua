-- Wasteland Pass. Free for everyone, no paid track. Tokens only come from playing, never from money.
Pass = Pass or {}

Pass.Settings = {
    enabled      = true,
    menuEnabled  = true,     -- false = no F11 key, no /pass, no pause tab (F1 toggle)
    seasonDays   = 30,       -- length of a season
    tiers        = 100,
    xpPerTier    = 1000,
    dailyXpCap   = 8000,     -- XP from gameplay per day; challenge XP is not capped
    tokenEvery   = 5,        -- a token every N tiers
    key          = 'F11',    -- not registered when vMenu runs (it owns F11), use /pass then
    command      = 'pass',
    mailboxSlots = 120,
    mailboxWeight = 500.0,
    leaderboardSize = 25,
}

-- XP per gameplay source. Each goes through the daily cap.
Pass.XP = {
    zombie_kill   = 10,
    headshot      = 15,
    craft         = 15,
    gather        = 5,
    contract      = 250,
    event         = 200,     -- airdrop / convoy / stash crate opened, horde cleared
    heal          = 25,
    vehicle       = 20,
    playtime      = 6,       -- per active minute
}

-- Playtime only counts while the player actually moves.
Pass.Afk = {
    minutes = 5,             -- no movement for this long = AFK
    moveMeters = 1.5,
}

Pass.Challenges = {
    daily = 3, weekly = 5, rerollsPerDay = 1,
    weeklyTokens = 1,        -- bonus tokens per finished weekly
    -- kind: what counts. min/max/step: random target. xp: reward.
    Daily = {
        { id = 'd_kill',     kind = 'zombie_kill', min = 25, max = 60,  step = 5,  xp = 600 },
        { id = 'd_head',     kind = 'headshot',    min = 10, max = 25,  step = 5,  xp = 650 },
        { id = 'd_craft',    kind = 'craft',       min = 3,  max = 8,   step = 1,  xp = 500 },
        { id = 'd_gather',   kind = 'gather',      min = 10, max = 30,  step = 5,  xp = 500 },
        { id = 'd_play',     kind = 'playtime',    min = 30, max = 60,  step = 10, xp = 550 },
        { id = 'd_contract', kind = 'contract',    min = 1,  max = 2,   step = 1,  xp = 700 },
        { id = 'd_heal',     kind = 'heal',        min = 2,  max = 5,   step = 1,  xp = 500 },
        { id = 'd_vehicle',  kind = 'vehicle',     min = 1,  max = 3,   step = 1,  xp = 500 },
    },
    Weekly = {
        { id = 'w_kill',     kind = 'zombie_kill', min = 300, max = 500, step = 50, xp = 2500 },
        { id = 'w_head',     kind = 'headshot',    min = 100, max = 200, step = 25, xp = 2500 },
        { id = 'w_craft',    kind = 'craft',       min = 25,  max = 50,  step = 5,  xp = 2000 },
        { id = 'w_gather',   kind = 'gather',      min = 100, max = 200, step = 25, xp = 2000 },
        { id = 'w_play',     kind = 'playtime',    min = 300, max = 600, step = 60, xp = 2200 },
        { id = 'w_contract', kind = 'contract',    min = 5,   max = 10,  step = 1,  xp = 3000 },
        { id = 'w_event',    kind = 'event',       min = 2,   max = 4,   step = 1,  xp = 3000 },
        { id = 'w_heal',     kind = 'heal',        min = 10,  max = 20,  step = 5,  xp = 2000 },
        { id = 'w_spin',     kind = 'spin',        min = 3,   max = 5,   step = 1,  xp = 1500 },
    },
}

-- Reward shapes: { type='item', item=, amount= } { type='cash', amount= } { type='xp', amount= } { type='token', amount= } { type='car', model= }
-- Tier rewards are built from these rotations; the F1 tier editor saves single tiers on top (data/tiers.json).
Pass.Rotation = {
    supplies = {
        { { type = 'item', item = 'canned_food', amount = 3 }, { type = 'item', item = 'water_bottle', amount = 3 } },
        { { type = 'item', item = 'bandage', amount = 4 }, { type = 'item', item = 'antiseptic', amount = 2 } },
        { { type = 'item', item = 'ammo_pistol', amount = 40 } },
        { { type = 'item', item = 'scrap_metal', amount = 10 }, { type = 'item', item = 'cloth', amount = 8 } },
        { { type = 'item', item = 'medkit', amount = 1 }, { type = 'item', item = 'painkillers', amount = 2 } },
        { { type = 'item', item = 'ammo_rifle', amount = 30 } },
        { { type = 'item', item = 'nails', amount = 20 }, { type = 'item', item = 'wood_plank', amount = 10 } },
        { { type = 'item', item = 'ammo_shotgun', amount = 16 } },
    },
    cash = {
        { { type = 'cash', amount = 500 }, { type = 'xp', amount = 300 } },
        { { type = 'cash', amount = 900 }, { type = 'xp', amount = 500 } },
    },
    -- every 10th tier, in order (tier 10 = first, tier 100 = last)
    gear = {
        { { type = 'item', item = 'pistol', amount = 1 }, { type = 'item', item = 'ammo_pistol', amount = 60 } },
        { { type = 'item', item = 'att_flashlight', amount = 1 }, { type = 'item', item = 'att_grip', amount = 1 } },
        { { type = 'item', item = 'pump_shotgun', amount = 1 }, { type = 'item', item = 'ammo_shotgun', amount = 24 } },
        { { type = 'item', item = 'att_scope', amount = 1 }, { type = 'item', item = 'armour_plate', amount = 1 } },
        { { type = 'item', item = 'smg', amount = 1 }, { type = 'item', item = 'ammo_pistol', amount = 90 } },
        { { type = 'item', item = 'att_extmag', amount = 1 }, { type = 'item', item = 'att_laser', amount = 1 } },
        { { type = 'item', item = 'carbine', amount = 1 }, { type = 'item', item = 'ammo_rifle', amount = 60 } },
        { { type = 'item', item = 'att_suppressor', amount = 1 }, { type = 'item', item = 'vest_plate', amount = 1 } },
        { { type = 'item', item = 'marksman', amount = 1 }, { type = 'item', item = 'ammo_rifle', amount = 60 } },
        { { type = 'item', item = 'assault_rifle', amount = 1 }, { type = 'item', item = 'pack_field_military', amount = 1 }, { type = 'cash', amount = 5000 } },
    },
}

-- Slot machine. Each reel rolls a symbol by weight. Three of a kind pays that symbol's pool,
-- two of a kind pays 'pair', anything else pays 'consolation'. Never empty.
Pass.Slot = {
    Symbols = {
        { id = 'can',    w = 30, pool = 'supplies' },
        { id = 'med',    w = 25, pool = 'medical' },
        { id = 'bullet', w = 20, pool = 'ammo' },
        { id = 'gear',   w = 14, pool = 'rare' },
        { id = 'skull',  w = 8,  pool = 'epic' },
        { id = 'crown',  w = 3,  pool = 'jackpot' },
    },
    -- Each pool picks one bundle by weight.
    Pools = {
        consolation = {
            { w = 1, r = { { type = 'item', item = 'canned_food', amount = 1 }, { type = 'item', item = 'bandage', amount = 1 } } },
            { w = 1, r = { { type = 'item', item = 'water_bottle', amount = 1 }, { type = 'item', item = 'scrap_metal', amount = 3 } } },
            { w = 1, r = { { type = 'item', item = 'ammo_pistol', amount = 12 } } },
        },
        pair = {
            { w = 1, r = { { type = 'item', item = 'medkit', amount = 1 }, { type = 'item', item = 'canned_food', amount = 2 } } },
            { w = 1, r = { { type = 'item', item = 'ammo_rifle', amount = 20 } } },
            { w = 1, r = { { type = 'cash', amount = 400 } } },
        },
        supplies = {
            { w = 1, r = { { type = 'item', item = 'canned_food', amount = 5 }, { type = 'item', item = 'water_bottle', amount = 5 }, { type = 'item', item = 'gun_parts', amount = 2 } } },
        },
        medical = {
            { w = 1, r = { { type = 'item', item = 'medkit', amount = 2 }, { type = 'item', item = 'antibiotics', amount = 2 }, { type = 'item', item = 'antiviral', amount = 1 } } },
        },
        ammo = {
            { w = 1, r = { { type = 'item', item = 'ammo_rifle', amount = 60 }, { type = 'item', item = 'ammo_pistol', amount = 60 } } },
        },
        rare = {
            { w = 2, r = { { type = 'item', item = 'att_scope', amount = 1 }, { type = 'item', item = 'att_suppressor', amount = 1 } } },
            { w = 1, r = { { type = 'item', item = 'combat_pistol', amount = 1 }, { type = 'item', item = 'att_flashlight', amount = 1 } } },
        },
        epic = {
            { w = 1, r = { { type = 'item', item = 'carbine', amount = 1 }, { type = 'item', item = 'att_grip', amount = 1 }, { type = 'item', item = 'ammo_rifle', amount = 60 } } },
            { w = 1, r = { { type = 'cash', amount = 7500 } } },
        },
        jackpot = {
            { w = 3, r = { { type = 'cash', amount = 25000 } } },
            { w = 2, r = { { type = 'item', item = 'assault_rifle', amount = 1 }, { type = 'item', item = 'att_scope', amount = 1 }, { type = 'item', item = 'att_suppressor', amount = 1 }, { type = 'item', item = 'att_extmag', amount = 1 } } },
            { w = 2, r = { { type = 'item', item = 'pack_field_military', amount = 1 }, { type = 'item', item = 'vest_plate', amount = 1 } } },
            { w = 1, r = { { type = 'car', model = 'mesa3' } } },
            { w = 1, r = { { type = 'car', model = 'sandking' } } },
        },
    },
}
