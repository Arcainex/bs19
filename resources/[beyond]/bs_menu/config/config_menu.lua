-- bs_menu - the hub opened with U, laid out like a pause screen.

Menu = {}

Menu.Settings = {
    openKey     = '',
    openCommand = 'survivorwheel_disabled',
    -- Dedicated key straight to the Craft panel (reuses the hub, see the RegisterCommand note in cl_main.lua).
    factionKey   = 'F5',
    factionCommand = 'factionmenu_unbound_v2',
    craftKey     = '',
    craftCommand = 'craftmenu',
    buildKey     = 'U',
    buildCommand = 'buildmenu_u',
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
        id     = 'keyboard',
        label  = 'Tastaturbelegung',
        blurb  = 'Wichtige Tasten und Funktionen.',
        icon   = 'key',
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


