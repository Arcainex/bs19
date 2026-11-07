-- Faction progression: levels, missions, skill tree, unlocks. Read by server/sv_progression.lua. See docs/FACTION_PROGRESSION.md.

Factions.Progression = {
    maxLevel = 30,
    -- XP needed to go from level n to n+1 = floor(base * n ^ exponent)
    curve = { base = 400, exponent = 1.55 },

    -- Treasury donations: poor rate on purpose, capped per member per day.
    donation = { dollarsPerXp = 25, dailyXpCap = 400, min = 100, max = 50000 },

    -- Board sizes and how many of each a faction rolls.
    board = { daily = 3, weekly = 2 },

    -- Who may spend skill points besides the Leader (rank permission).
    skillPerm = 'skills',
}

-- Mission pool.
-- kind = 'action': counts bs:hook:player:action ids in `actions`
-- kind = 'extract': counts successful extractions (bs:extraction:completed)
-- kind = 'deliver': members hand in `item` at one of the faction's flags
-- `n` is { min, max }; the rolled target scales rewards linearly.
Factions.Progression.Missions = {
    daily = {
        { id='d_kill',      kind='action',  label='Thin the herd',       actions={'zombie_kill','zombie_kill_headshot','zombie_kill_brute'}, n={60,120},  xpPer=2,  moneyPer=4 },
        { id='d_headshot',  kind='action',  label='Clean shots',         actions={'zombie_kill_headshot'}, n={20,40}, xpPer=5, moneyPer=8 },
        { id='d_extract',   kind='extract', label='Get home alive',      n={3,6},    xpPer=30, moneyPer=60 },
        { id='d_scrap',     kind='deliver', label='Scrap drive',         item='scrap_metal', n={30,60}, xpPer=3, moneyPer=5 },
        { id='d_cloth',     kind='deliver', label='Bandage supply',      item='cloth',       n={20,40}, xpPer=3, moneyPer=4 },
        { id='d_food',      kind='deliver', label='Stock the pantry',    item='canned_food', n={10,20}, xpPer=6, moneyPer=8 },
        { id='d_craft',     kind='action',  label='Workshop shift',      actions={'item_crafted'}, n={10,20}, xpPer=6, moneyPer=6 },
        { id='d_gather',    kind='action',  label='Foraging run',        actions={'resource_gathered'}, n={15,30}, xpPer=4, moneyPer=5 },
    },
    weekly = {
        { id='w_kill',      kind='action',  label='Purge',               actions={'zombie_kill','zombie_kill_headshot','zombie_kill_brute'}, n={600,1000}, xpPer=2, moneyPer=4 },
        { id='w_brute',     kind='action',  label='Big game',            actions={'zombie_kill_brute'}, n={15,30}, xpPer=40, moneyPer=80 },
        { id='w_horde',     kind='action',  label='Break the hordes',    actions={'horde_cleared'}, n={4,8}, xpPer=120, moneyPer=250 },
        { id='w_extract',   kind='extract', label='Supply lines',        n={25,40},  xpPer=30, moneyPer=60 },
        { id='w_planks',    kind='deliver', label='Build the wall',      item='wood_plank', n={80,140}, xpPer=4, moneyPer=6 },
        { id='w_metal',     kind='deliver', label='Armoury stockpile',   item='scrap_metal', n={200,300}, xpPer=3, moneyPer=5 },
        { id='w_revive',    kind='action',  label='No one left behind',  actions={'player_revived'}, n={10,20}, xpPer=30, moneyPer=40 },
    },
}

-- Skill tree. One point per level above 1 (level 30 = 29 points).
-- ranks = times it can be bought, `value` per rank (summed by GetSkillValue). requires = { skillId = minRank, ... }. `level` = minimum faction level. Other resources read these via exports; bs_factions only stores them.
Factions.Progression.Skills = {
    { id='stash_slots',   label='Deep shelves',      desc='+10 base stash slots per rank.',             ranks=3, value=10, level=2 },
    { id='trader_disc',   label='Trade contacts',    desc='-2% trader prices per rank.',                ranks=3, value=2,  level=4 },
    { id='build_speed',   label='Work crews',        desc='-5% base build time per rank.',              ranks=3, value=5,  level=3 },
    { id='booster_cd',    label='Field chemistry',   desc='-5% booster cooldown per rank.',             ranks=3, value=5,  level=6,  requires={ build_speed=1 } },
    { id='stash_slots2',  label='Warehouse',         desc='+20 base stash slots per rank.',             ranks=2, value=20, level=12, requires={ stash_slots=3 } },
    { id='trader_disc2',  label='Black market',      desc='-3% trader prices per rank.',                ranks=2, value=3,  level=15, requires={ trader_disc=3 } },
    { id='build_speed2',  label='Engineers',         desc='-10% base build time per rank.',             ranks=2, value=10, level=14, requires={ build_speed=3 } },
    { id='booster_cd2',   label='Stimulant lab',     desc='-10% booster cooldown per rank.',            ranks=2, value=10, level=18, requires={ booster_cd=3 } },
    { id='donation_rate', label='Patrons',           desc='+10% XP from treasury donations per rank.',  ranks=2, value=10, level=8 },
    { id='mission_pay',   label='Contracts',         desc='+10% mission treasury pay per rank.',        ranks=3, value=10, level=10, requires={ donation_rate=1 } },
    { id='quartermaster', label='Quartermaster',     desc='-15% trader prices at the top of the tree.', ranks=1, value=15, level=25, requires={ trader_disc2=2, stash_slots2=2 } },
}

-- Level unlocks.
-- base: faction-base gates read by bs_faction_bases (level needed). flag_main / flag_outpost = placing that flag kind at all. extraFlags = { [level] = +N flag cap }.
-- styles: cosmetic tag colours/styles, set with factions:cosmetics:set.
Factions.Progression.Unlocks = {
    base = {
        flag_main    = 1,
        flag_outpost = 3,
        extraFlags   = { [10] = 1, [20] = 1, [30] = 1 },
    },
    colours = {
        { id='amber',   hex='#e08c46', level=1  },
        { id='bone',    hex='#f0ebdd', level=1  },
        { id='moss',    hex='#7f9a5a', level=5  },
        { id='rust',    hex='#b0553a', level=8  },
        { id='steel',   hex='#8aa2c0', level=12 },
        { id='toxic',   hex='#a6e04a', level=16 },
        { id='blood',   hex='#c0303a', level=20 },
        { id='gold',    hex='#e6c35a', level=25 },
        { id='ghost',   hex='#cfe8ff', level=30 },
    },
    styles = {
        { id='plain',   label='Plain',    level=1  },
        { id='bracket', label='[Bracket]',level=4  },
        { id='stencil', label='Stencil',  level=10 },
        { id='glow',    label='Glow',     level=18 },
        { id='chevron', label='Chevron',  level=24 },
        { id='elite',   label='Elite',    level=30 },
    },
}
