-- BeyondSurvival - bs_mining config. Gathering turns time and risk into materials; every swing makes noise via bs_emotes.

Mining = {}

Mining.Settings = {
    enabled = true,

    -- Duration of one swing.
    swingMs = 2600,

    -- Max distance to the node. Checked server-side against the player's real position; the client's node name is only a claim.
    proximity = 4.0,

    -- Nodes deplete globally, not per player, so busy servers strip the easy nodes near town first. Intentional.
    respawnSeconds = 600,

    -- Skill level raises the chance of an extra unit per swing (capped).
    skill = 'survival',
    xpPerSwing = 3,
    bonusPerLevel = 0.02,
    maxBonus = 0.40,
}

-- Node types. `models` are matched against what the interaction dot points at, so every rock of those models is a node. Wrong matches go in Mining.ExcludeModels.
Mining.Types = {
    rock = {
        label     = 'Mine the rock',
        icon      = 'pickaxe',
        tool      = 'pickaxe',
        toolLabel = 'a pickaxe',
        wear      = 1,
        noise     = 'mining',
        swings    = { 5, 9 },
        yield     = { { item = 'stone', amount = { 1, 3 } }, { item = 'iron_ore', amount = { 0, 1 } },
                      { item = 'sulfur', amount = { 1, 1 }, chance = 0.25 } },

        -- Candidate clips, checked with GetAnimDuration at runtime. A dict can load without containing the clip, and TaskPlayAnim then silently does nothing.
        anim = {
            { dict = 'melee@hatchet@streamed_core',        clip = 'plyr_front_takedown' },
            { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
            { dict = 'anim@heists@fleeca_bank@drilling',    clip = 'drill_straight_idle' },
            { dict = 'missheistdockssetup1clipboard@base',  clip = 'base' },
        },

        models = {
            'prop_rock_1_a', 'prop_rock_1_b', 'prop_rock_1_c', 'prop_rock_1_d',
            'prop_rock_1_e', 'prop_rock_1_f', 'prop_rock_1_g', 'prop_rock_1_h',
            'prop_rock_1_i', 'prop_rock_2_a', 'prop_rock_2_b', 'prop_rock_2_c',
            'prop_rock_2_d', 'prop_rock_2_e', 'prop_rock_3_a', 'prop_rock_3_b',
            'prop_rock_3_c', 'prop_rock_3_d', 'prop_rock_4_a', 'prop_rock_4_b',
            'prop_rock_4_c', 'prop_rock_4_d', 'prop_rock_5_a', 'prop_rock_5_b',
            'prop_rock_5_c', 'prop_rock_5_d',
        },
    },

    timber = {
        label     = 'Fell the tree',
        icon      = 'axe',
        tool      = 'hatchet',
        tools     = { 'hatchet', 'axe' },
        toolLabel = 'a hatchet or axe',
        wear      = 1,
        noise     = 'chopping',
        swings    = { 4, 7 },
        yield     = { { item = 'log', amount = { 1, 2 } } },

        anim = {
            { dict = 'melee@hatchet@streamed_core',        clip = 'plyr_front_takedown' },
            { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
            { dict = 'missheistdockssetup1clipboard@base',  clip = 'base' },
        },

        models = {
            'prop_tree_birch_01', 'prop_tree_birch_02', 'prop_tree_birch_03',
            'prop_tree_birch_04', 'prop_tree_cedar_02', 'prop_tree_cedar_03',
            'prop_tree_cedar_04', 'prop_tree_cedar_s_01', 'prop_tree_cedar_s_04',
            'prop_tree_cypress_01', 'prop_tree_eng_oak_01', 'prop_tree_eucalip_01',
            'prop_tree_fallen_pine_01', 'prop_tree_jacada_01', 'prop_tree_jacada_02',
            'prop_tree_maple_02', 'prop_tree_maple_03', 'prop_tree_oak_01',
            'prop_tree_olive_01', 'prop_tree_pine_01', 'prop_tree_pine_02',
            'prop_s_pine_dead_01', 'prop_tree_log_01', 'prop_tree_log_02',
        },
    },
}

-- Models that match a type above but must never be a node. Empty by default; add props that turn out to be scenery.
Mining.ExcludeModels = {}
