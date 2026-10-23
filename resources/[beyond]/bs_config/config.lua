BSConfig = BSConfig or {}

BSConfig.Settings = {
    key         = 'F1',                                 -- default key (players can rebind in GTA settings)
    adminAces   = { 'bs.admin', 'bs.superadmin' },      -- fallback when bs_admin is not running
    ownerAces   = { 'bs.owner' },                       -- only these may delete profiles
    auditLimit  = 200,                                  -- rows shown in the audit tab
    nameMax     = 32,
}

-- Categories shown in the left rail, in order.
BSConfig.Categories = {
    { id = 'zombies',   label = 'Zombies' },
    { id = 'economy',   label = 'Economy & Loot' },
    { id = 'survival',  label = 'Survival & Medical' },
    { id = 'drugs',     label = 'Drugs & Addiction' },
    { id = 'gadgets',   label = 'Gadgets' },
    { id = 'factions',  label = 'Factions / Squads / VIP' },
    { id = 'building',  label = 'Building & Raids' },
    { id = 'weather',   label = 'Weather & Time' },
    { id = 'weapons',   label = 'Weapons & Recoil' },
    { id = 'safezones', label = 'Safe Zones & PvP' },
    { id = 'factionsafe', label = 'Vanilla Faction Safezones' },
    { id = 'vehicles',  label = 'Vehicles' },
    { id = 'ui',        label = 'Keybinds & UI' },
    { id = 'events',    label = 'World Events' },
    { id = 'anticheat', label = 'Anti-cheat' },
    { id = 'crafting',  label = 'Crafting & Recycling' },
    { id = 'jobs',      label = 'Faction Jobs' },
    { id = 'hunting',   label = 'Hunting' },
    { id = 'gates',     label = 'Map Gates' },
    { id = 'tutorial',  label = 'Tutorial & Pause Menu' },
    { id = 'pass',      label = 'Wasteland Pass' },
    { id = 'operations', label = 'Operations' },
    { id = 'testserver', label = 'Test server' },
}

-- Read-only built-in profiles. 'Default' = the config files as shipped.
BSConfig.Builtin = { 'Default', 'Easy', 'Hardcore', 'PvP' }

-- Resources with their own F1 page (html/ext_*.js draws it, the resource's ConfigExt export answers).
BSConfig.Extensions = { bs_crafting = true, bs_recycler = true, bs_pass = true, bs_tutorial = true, bs_operations = true }
