-- bs_scoreboard - three boards: most walker kills, longest survived (XP), and most survivor kills.

Scoreboard = {}

Scoreboard.Settings = {
    key         = 'F9',
    command     = 'scoreboard',
    -- Held, not toggled: a glance, not a screen.
    hold        = true,
    -- How many rows per board.
    top         = 10,
    -- Lists are rebuilt at most this often (seconds-equivalent rate limit, however hard F9 is pressed).
    cacheMs     = 5000,
    -- Server name shown at the top. Cosmetic.
    title       = 'BEYOND SURVIVAL',
    subtitle    = 'RPG ZOMBIE SURVIVAL',
}

--- The three boards, in the order they appear.
Scoreboard.Boards = {
    { id = 'zombies', label = 'WALKERS PUT DOWN', column = 'zombie_kills', suffix = '' },
    { id = 'xp',      label = 'MOST EXPERIENCED', column = 'xp',           suffix = ' XP' },
    { id = 'kills',   label = 'SURVIVORS KILLED', column = 'player_kills', suffix = '' },
}
