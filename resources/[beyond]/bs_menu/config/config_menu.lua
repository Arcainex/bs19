-- bs_menu - the hub opened with U, laid out like a pause screen.

Menu = {}

Menu.Settings = {
    openKey     = 'F5',
    openCommand = 'survivorwheel',
    -- Dedicated key straight to the Craft panel (reuses the hub, see the RegisterCommand note in cl_main.lua).
    factionKey   = 'U',
    factionCommand = 'factionmenu',
    craftKey     = 'Y',
    craftCommand = 'craftmenu_y',
    -- Slow the world slightly while the hub is open, like a pause screen.
    dimWorld      = false,
}

-- Entries, in order. `resource`/`export` is called when chosen; `panel` renders inside the hub.
Menu.Entries = {
    {
        id     = 'inventory',
        label  = 'Inventory',
        blurb  = 'What you are carrying.',
        icon   = 'bag',
        kind   = 'resource',
        resource = 'bs_inventory',
        action = 'Open',
    },
    {
        id     = 'stats',
        label  = 'Survivor',
        blurb  = 'Condition, progress and how long you have lasted.',
        icon   = 'heart',
        kind   = 'panel',
    },
    {
        id     = 'skills',
        label  = 'Skills',
        blurb  = 'What you have learned out here.',
        icon   = 'star',
        kind   = 'panel',
    },
    {
        id     = 'build',
        label  = 'Build',
        blurb  = 'Barricades, a fire, somewhere to wake up.',
        icon   = 'wall',
        kind   = 'panel',
    },
    {
        id     = 'craft',
        label  = 'Craft',
        blurb  = 'Turn what you found into something that works.',
        icon   = 'anvil',
        kind   = 'panel',
    },
    -- Factions: a panel rather than a resource, since it is read as often as acted on (members, your rank, who is near enough to recruit).
    {
        id     = 'faction',
        label  = 'Faction',
        blurb  = 'Who you run with, and who runs it.',
        icon   = 'star',
        kind   = 'panel',
    },
    {
        id     = 'settings',
        label  = 'Settings',
        blurb  = 'HUD layout, XP bar, transparency.',
        icon   = 'gear',
        kind   = 'resource',
        resource = 'bs_inventory',
        action = 'Open',
        -- Opens the inventory straight onto its Settings tab.
        args   = 'settings',
    },
}


