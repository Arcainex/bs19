-- bs_skills - perk trees. A perk not marked `pending` has a working effect.
-- `effect` keys: weaponDamage, meleeDamage (damage multiplier, client);
-- hungerRate, thirstRate (fraction drain is reduced by, client);
-- stealth (fraction walker sight is cut by, client); lootRolls (extra draws, server);
-- xpBonus (fraction added to XP, server); flag (named capability, both).

Skills = {}

-- Training: a skill point can be spent directly on XP in a tree of your
-- choice, so new characters always have somewhere to put points.
Skills.Training = {
    enabled = true,
    -- Points per training purchase.
    cost    = 1,
    -- What one point buys: a fraction of the XP needed for the next level.
    -- 1.0 = exactly one level.
    levels  = 1.0,
}

Skills.Settings = {
    -- Perks cost points, points come from character levels.
    -- Respec costs a level's worth of XP.
    allowRespec   = true,
    respecXpCost  = 500,
    -- Skill XP is capped per action.
    maxXpPerGrant = 400,
}

Skills.Trees = {
    combat = {
        label = 'Combat', icon = 'combat', maxLevel = 20,
        blurb = 'What you learn by surviving fights instead of avoiding them.',
        xpPerLevel = function(level) return 80 * (level + 1) end,
        perks = {
            steady_hands = {
                label = 'Steady hands', requires = 3, cost = 1, order = 1,
                description = '+8% firearm damage. Fear stops costing you rounds.',
                effect = { weaponDamage = 0.08 },
            },
            heavy_swing = {
                label = 'Heavy swing', requires = 6, cost = 1, order = 2,
                description = '+12% melee damage. A crowbar becomes an answer.',
                effect = { meleeDamage = 0.12 },
            },
            executioner = {
                label = 'Executioner', requires = 12, cost = 2, order = 3,
                description = 'Any headshot on a walker is lethal, whatever it is wearing.',
                effect = { flag = 'executioner' },
            },
            butcher = {
                label = 'Butcher', requires = 16, cost = 2, order = 4,
                description = '+15% XP from everything you kill.',
                effect = { xpBonus = 0.15 },
            },
        },
    },

    survival = {
        label = 'Survival', icon = 'survival', maxLevel = 20,
        blurb = 'Moving quietly, eating rarely, and knowing where to look.',
        xpPerLevel = function(level) return 70 * (level + 1) end,
        perks = {
            iron_stomach = {
                label = 'Iron stomach', requires = 3, cost = 1, order = 1,
                description = 'Hunger and thirst drain 15% slower.',
                effect = { hungerRate = 0.15, thirstRate = 0.15 },
            },
            scoped_focus = {
                label = 'Scoped focus', requires = 4, cost = 1, order = 2,
                description = 'Hold TAB to focus your view. In first person, it tightens directly through your weapon optic.',
                effect = { flag = 'scoped_focus' },
            },
            -- Dodge roll unlock. cl_dodge.lua refuses the roll without this perk.
            dodge_roll = {
                label = 'Dodge roll', requires = 5, cost = 1, order = 2,
                description = 'Hold Shift and double-tap a direction to roll out of a walker\'s reach. Can be turned off in Settings.',
                effect = { flag = 'dodge_roll' },
            },
            scavenger = {
                label = 'Scavenger', requires = 6, cost = 1, order = 2,
                description = 'One extra draw from every container and every body.',
                effect = { lootRolls = 1 },
            },
            break_fall = {
                label = 'Break fall', requires = 8, cost = 1, order = 3,
                description = 'Double-tap jump becomes a roll instead of a fall.',
                effect = { flag = 'break_fall' },
            },
            ghost = {
                label = 'Ghost', requires = 12, cost = 2, order = 4,
                description = 'Walkers see you 25% later. Prone, they barely see you at all.',
                effect = { stealth = 0.25 },
            },
            -- Fireman carry, three levels bought in order (needsPerk).
            -- Read by bs_medical/client/cl_carry.lua: L1 shuffle, L2 walk, L3 jog.
            fireman_carry = {
                label = 'Fireman carry I', requires = 2, cost = 1, order = 5,
                description = 'Carry a downed survivor over your shoulder. Slow and exhausting.',
                effect = { flag = 'fireman_carry' },
            },
            fireman_carry_2 = {
                label = 'Fireman carry II', requires = 7, cost = 1, order = 6, needsPerk = 'fireman_carry',
                description = 'Carry a downed survivor at a normal walk.',
                effect = { flag = 'fireman_carry_2' },
            },
            fireman_carry_3 = {
                label = 'Fireman carry III', requires = 13, cost = 2, order = 7, needsPerk = 'fireman_carry_2',
                description = 'Jog while carrying a downed survivor.',
                effect = { flag = 'fireman_carry_3' },
            },
            -- The level-15 capstone `survivor_sense` was removed (it crashed the client).
            -- Characters that bought it keep a `survivor_sense` row in bs_character_perks
            -- that does nothing; delete the rows and refund the 3 points if you want.
        },
    },

    crafting = {
        label = 'Crafting', icon = 'crafting', maxLevel = 20,
        blurb = 'Turning what the city left behind into something that works.',
        xpPerLevel = function(level) return 90 * (level + 1) end,
        perks = {
            efficient = {
                label = 'Efficient', requires = 4, cost = 1, order = 1,
                description = '10% chance per material to keep it when crafting.',
                effect = { flag = 'efficient' },
            },
            fortifier = {
                label = 'Fortifier', requires = 8, cost = 2, order = 2,
                description = 'Everything you build stands 25% longer.',
                effect = { flag = 'fortifier' },
            },
        },
    },

    medical = {
        label = 'Medical', icon = 'medical', maxLevel = 20,
        blurb = 'Keeping other people breathing, which is how groups last.',
        xpPerLevel = function(level) return 85 * (level + 1) end,
        perks = {
            field_medic = {
                label = 'Field medic', requires = 4, cost = 1, order = 1,
                description = 'Treating a downed survivor takes 30% less time.',
                effect = { flag = 'field_medic' },
            },
            triage = {
                label = 'Triage', requires = 9, cost = 2, order = 2,
                description = 'Bandages and medkits heal 25% more.',
                effect = { flag = 'triage' },
            },
        },
    },

    -- Trained by forcing vehicle locks. Each level widens the sweet spot and slows the pick (Vehicles.Lockpick in bs_vehicles).
    lockpicking = {
        label = 'Lockpicking', icon = 'crafting', maxLevel = 20,
        blurb = 'Getting into things that were locked for a reason.',
        xpPerLevel = function(level) return 70 * (level + 1) end,
        perks = {},
    },
}

-- Each level in a skill adds a bit of XP to that skill's actions, up to a cap.
Skills.LevelBonus = {
    perLevel = 0.008,   -- +0.8% per level
    max      = 0.20,    -- max +20%
}

-- Which skill an action trains. Config.Rewards in bs_core has the real numbers.
Skills.ActionSkill = {
    zombie_kill          = 'combat',
    zombie_kill_headshot = 'combat',
    zombie_kill_brute    = 'combat',
    item_crafted         = 'crafting',
    player_revived       = 'medical',
    resource_gathered    = 'survival',
    animal_skinned       = 'survival',
    vehicle_hotwired     = 'lockpicking',
}
