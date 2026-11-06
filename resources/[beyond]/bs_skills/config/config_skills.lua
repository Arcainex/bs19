-- bs_skills - perk trees: a perk not marked `pending` has a working effect. `effect` keys: weaponDamage

Skills = {}

-- Training: a skill point can be spent directly on XP in a tree of your choice
Skills.Training = {
    enabled = true,
    -- Points per training purchase.
    cost    = 1,
    -- What one point buys: a fraction of the XP needed for the next level.
    -- 1.0 = exactly one level.
    levels  = 1.0,
}

Skills.Settings = {
    -- Perks cost points, points come from character levels. Respec costs a level's worth of XP.
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

Skills.Trees.fishing = {
    label='Fishing', icon='fishing', maxLevel=20,
    blurb='Read the water. Keep the line steady. Land the catch.',
    xpPerLevel=function(level) return 55*(level+1) end,
    perks={},
}
Skills.ActionSkill.fish_catch = 'fishing'

-- Parkour (bs_parkour). The first two perks are taught by trainers only (trainer = tier), the rest are bought with points.
-- Branches: agility, endurance, escape.
Skills.Trees.parkour = {
    label = 'Parkour', icon = 'parkour', maxLevel = 20,
    blurb = 'Over the fence, up the wall, gone before they turn around.',
    xpPerLevel = function(level) return 75 * (level + 1) end,
    perks = {
        pk_basics = { label = 'Parkour basics', requires = 0, cost = 0, order = 1, trainer = 'basic',
            description = 'Taught by safezone trainers. Vaults, high climbs, sprint slides and landing rolls.', effect = { flag = 'pk_basics' } },
        pk_advanced = { label = 'Advanced parkour', requires = 5, cost = 0, order = 2, trainer = 'advanced', needsPerk = 'pk_basics',
            description = 'Taught by hidden trainers. Wall runs, wall jumps, ledge hangs and shimmying.', effect = { flag = 'pk_advanced' } },
        -- agility
        pk_high_reach = { label = 'High reach', requires = 3, cost = 1, order = 10, branch = 'agility', needsPerk = 'pk_basics',
            description = 'Agility. Climb and grab ledges 60 cm higher.', effect = { flag = 'pk_high_reach' } },
        pk_long_slide = { label = 'Long slide', requires = 4, cost = 1, order = 11, branch = 'agility', needsPerk = 'pk_basics',
            description = 'Agility. Sprint slides last 35% longer.', effect = { flag = 'pk_long_slide' } },
        pk_wall_runner = { label = 'Wall runner', requires = 7, cost = 1, order = 12, branch = 'agility', needsPerk = 'pk_advanced',
            description = 'Agility. Wall runs last 40% longer.', effect = { flag = 'pk_wall_runner' } },
        pk_double_wall = { label = 'Double wall', requires = 10, cost = 2, order = 13, branch = 'agility', needsPerk = 'pk_wall_runner',
            description = 'Agility. A second wall run before you touch the ground.', effect = { flag = 'pk_double_wall' } },
        pk_cat_balance = { label = 'Cat balance', requires = 13, cost = 1, order = 14, branch = 'agility', needsPerk = 'pk_advanced',
            description = 'Agility. Shimmy along ledges twice as fast.', effect = { flag = 'pk_cat_balance' } },
        pk_spring_heels = { label = 'Spring heels', requires = 16, cost = 2, order = 15, branch = 'agility', needsPerk = 'pk_double_wall',
            description = 'Agility. Wall jumps go 25% further and higher.', effect = { flag = 'pk_spring_heels' } },
        -- endurance
        pk_steady_breath = { label = 'Steady breath', requires = 2, cost = 1, order = 20, branch = 'endurance', needsPerk = 'pk_basics',
            description = 'Endurance. Big moves cost 15% less stamina.', effect = { flag = 'pk_steady_breath' } },
        pk_iron_grip = { label = 'Iron grip', requires = 5, cost = 1, order = 21, branch = 'endurance', needsPerk = 'pk_advanced',
            description = 'Endurance. Hanging on a ledge drains 40% less stamina.', effect = { flag = 'pk_iron_grip' } },
        pk_soft_landing = { label = 'Soft landing', requires = 6, cost = 1, order = 22, branch = 'endurance', needsPerk = 'pk_basics',
            description = 'Endurance. Falls hurt 15% less, on top of your parkour level.', effect = { flag = 'pk_soft_landing' } },
        pk_pack_mule = { label = 'Pack mule', requires = 9, cost = 1, order = 23, branch = 'endurance', needsPerk = 'pk_steady_breath',
            description = 'Endurance. A heavy bag slows your moves half as much.', effect = { flag = 'pk_pack_mule' } },
        pk_second_wind = { label = 'Second wind', requires = 12, cost = 2, order = 24, branch = 'endurance', needsPerk = 'pk_steady_breath',
            description = 'Endurance. Every big move you land gives back 5 stamina.', effect = { flag = 'pk_second_wind' } },
        pk_marathon = { label = 'Marathon', requires = 15, cost = 2, order = 25, branch = 'endurance', needsPerk = 'pk_second_wind',
            description = 'Endurance. Big moves cost another 20% less stamina.', effect = { flag = 'pk_marathon' } },
        pk_cat_landing = { label = 'Cat landing', requires = 18, cost = 2, order = 26, branch = 'endurance', needsPerk = 'pk_soft_landing',
            description = 'Endurance. You roll out of any fall up to 12 m without pressing anything.', effect = { flag = 'pk_cat_landing' } },
        -- escape
        pk_quick_recovery = { label = 'Quick recovery', requires = 3, cost = 1, order = 30, branch = 'escape', needsPerk = 'pk_basics',
            description = 'Escape. The aim shake after a move is half as long.', effect = { flag = 'pk_quick_recovery' } },
        pk_breakaway = { label = 'Breakaway', requires = 4, cost = 1, order = 31, branch = 'escape', needsPerk = 'pk_basics',
            description = 'Escape. +30% XP for breaking a walker chase.', effect = { flag = 'pk_breakaway' } },
        pk_adrenaline = { label = 'Adrenaline', requires = 8, cost = 1, order = 32, branch = 'escape', needsPerk = 'pk_breakaway',
            description = 'Escape. While chased, big moves cost 30% less stamina.', effect = { flag = 'pk_adrenaline' } },
        pk_shake_off = { label = 'Shake off', requires = 11, cost = 2, order = 33, branch = 'escape', needsPerk = 'pk_adrenaline',
            description = 'Escape. While chased, moves recover 30% faster.', effect = { flag = 'pk_shake_off' } },
        pk_low_profile = { label = 'Low profile', requires = 14, cost = 2, order = 34, branch = 'escape', needsPerk = 'pk_breakaway',
            description = 'Escape. Walkers notice you 10% later.', effect = { stealth = 0.10 } },
        pk_ghost_runner = { label = 'Ghost runner', requires = 17, cost = 2, order = 35, branch = 'escape', needsPerk = 'pk_quick_recovery',
            description = 'Escape. No aim shake at all after a move.', effect = { flag = 'pk_ghost_runner' } },
        pk_escape_artist = { label = 'Escape artist', requires = 20, cost = 3, order = 36, branch = 'escape', needsPerk = 'pk_shake_off',
            description = 'Escape. Walkers lose you sooner: chases break 30% faster and at a shorter distance.', effect = { flag = 'pk_escape_artist' } },
    },
}

-- Fighting (bs_fighting). Style perks are taught by fight trainers (trainer = tier); the rest are bought with points
-- and only work while that style is active.
Skills.Trees.fighting = {
    label = 'Fighting', icon = 'fighting', maxLevel = 20,
    blurb = 'Fists, boots and whatever is in reach. Learn a style, then make it yours.',
    xpPerLevel = function(level) return 80 * (level + 1) end,
    perks = {
        fs_brawler = { label = 'Brawler', requires = 0, cost = 0, order = 1, trainer = 'basic',
            description = 'Taught by safezone fight trainers. Slow, heavy hands: haymakers, dropkicks and knockdowns.', effect = { flag = 'fs_brawler' } },
        fs_boxer = { label = 'Boxer', requires = 0, cost = 0, order = 2, trainer = 'basic',
            description = 'Taught by safezone fight trainers. Fast four-punch chains, wide parries and counter punches.', effect = { flag = 'fs_boxer' } },
        fs_soldier = { label = 'Soldier CQC', requires = 4, cost = 0, order = 3, trainer = 'advanced',
            description = 'Taught by a hidden trainer. Takedowns from behind, low kicks, disarming parries, better with a knife.', effect = { flag = 'fs_soldier' } },
        fs_grappler = { label = 'Grappler', requires = 6, cost = 0, order = 4, trainer = 'advanced',
            description = 'Taught by a hidden trainer. Shoves, throws into walls and crowds, chokes on players.', effect = { flag = 'fs_grappler' } },
        fight_footwork = { label = 'Footwork', requires = 2, cost = 1, order = 10,
            description = 'Dodge roll without the Survival perk, and every dodge opens a counter.', effect = { flag = 'fight_footwork' } },
        fight_stomp = { label = 'Boot', requires = 4, cost = 1, order = 11,
            description = 'You can stomp downed targets from a little further away.', effect = { flag = 'fight_stomp' } },
        fight_iron_guard = { label = 'Iron guard', requires = 5, cost = 1, order = 12,
            description = 'Blocking a hit costs half the stamina.', effect = { flag = 'fight_iron_guard' } },
        fight_grab_breaker = { label = 'Grab breaker', requires = 8, cost = 1, order = 13,
            description = 'Walker escape window +50%, and the counter-shove lands a hit.', effect = { flag = 'fight_grab_breaker' } },
        fight_second_wind = { label = 'Second wind', requires = 14, cost = 2, order = 14,
            description = 'Knockdowns and stomps give back 6 stamina.', effect = { flag = 'fight_second_wind' } },
        brw_heavy_hands = { label = 'Heavy hands', requires = 3, cost = 1, order = 20, needsPerk = 'fs_brawler',
            description = 'Brawler. Heavies charge 35% faster.', effect = { flag = 'brw_heavy_hands' } },
        brw_bulldozer = { label = 'Bulldozer', requires = 9, cost = 2, order = 21, needsPerk = 'brw_heavy_hands',
            description = 'Brawler. Haymaker and dropkick hit everything in front of you.', effect = { flag = 'brw_bulldozer' } },
        brw_thick_skin = { label = 'Thick skin', requires = 13, cost = 2, order = 22, needsPerk = 'brw_bulldozer',
            description = 'Brawler. Your guard lets only 10% through.', effect = { flag = 'brw_thick_skin' } },
        box_quick_hands = { label = 'Quick hands', requires = 3, cost = 1, order = 23, needsPerk = 'fs_boxer',
            description = 'Boxer. Light punches are 15% faster.', effect = { flag = 'box_quick_hands' } },
        box_counter = { label = 'Counter puncher', requires = 9, cost = 2, order = 24, needsPerk = 'box_quick_hands',
            description = 'Boxer. Counters hit 50% harder and the window is longer.', effect = { flag = 'box_counter' } },
        box_slip = { label = 'Slip', requires = 13, cost = 2, order = 25, needsPerk = 'box_counter',
            description = 'Boxer. A parry gives back 8 stamina.', effect = { flag = 'box_slip' } },
        sol_silent = { label = 'Silent hands', requires = 6, cost = 1, order = 26, needsPerk = 'fs_soldier',
            description = 'Soldier CQC. Takedowns recover twice as fast.', effect = { flag = 'sol_silent' } },
        sol_knife = { label = 'Knife work', requires = 9, cost = 2, order = 27, needsPerk = 'sol_silent',
            description = 'Soldier CQC. Knife lights hit walkers twice.', effect = { flag = 'sol_knife' } },
        sol_breaker = { label = 'Leg breaker', requires = 13, cost = 2, order = 28, needsPerk = 'sol_knife',
            description = 'Soldier CQC. One low kick cripples a walker.', effect = { flag = 'sol_breaker' } },
        grp_throw = { label = 'Heave', requires = 7, cost = 1, order = 29, needsPerk = 'fs_grappler',
            description = 'Grappler. Throws go 50% further.', effect = { flag = 'grp_throw' } },
        grp_choke = { label = 'Sleeper', requires = 10, cost = 2, order = 30, needsPerk = 'grp_throw',
            description = 'Grappler. Chokes on players last two ticks longer.', effect = { flag = 'grp_choke' } },
        grp_escape = { label = 'Slippery', requires = 12, cost = 2, order = 31, needsPerk = 'grp_choke',
            description = 'Grappler. Walker escape window +30%.', effect = { flag = 'grp_escape' } },
    },
}
