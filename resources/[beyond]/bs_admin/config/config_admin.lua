-- bs_admin - admin menu config

Admin = {}

Admin.Settings = {
    -- F10. Change to any control id from the FiveM control list.
    openKey        = 57,
    openCommand    = 'adminmenu',
    -- Aces that may open the menu at all. Individual actions can require more.
    openAces       = { 'bs.admin', 'bs.superadmin', 'command.zombiemenu' },
    -- Names must match the actions table in sv_main.lua (checked on resource start); mayUse() only special-cases literal names
    superAdminOnly = { 'kick', 'givemoney', 'wipeBuilds', 'grantvip', 'revokevip', 'wipeInventory', 'ban', 'unban', 'kill', 'takemoney' },
    noclipSpeed    = 1.0,
    noclipFastMult = 4.0,
    noclipSlowMult = 0.25,
}

-- Vehicles, grouped like Admin.Weapons: { label = ..., items = { ... } }.
-- Read it through Admin.VehicleByModel instead of walking the groups
Admin.Vehicles = {
    {
        label = 'Base game',
        items = {
            { label = 'Sandking',   model = 'sandking'  },
            { label = 'Kamacho',    model = 'kamacho'   },
            { label = 'Rebel',      model = 'rebel'     },
            { label = 'Bodhi',      model = 'bodhi'     },
            { label = 'Insurgent',  model = 'insurgent' },
            { label = 'Ambulance',  model = 'ambulance' },
        },
    },
    {
        label = 'Apocalyptic (third-party pack: Chadada)',
        items = {
            { label = 'Bodhi (apoc)',       model = 'bodhi2'      },
            { label = 'Flatbed (apoc)',     model = 'flatbed'     },
            { label = 'Wastelander (apoc)', model = 'wastelander' },
            { label = 'Dozer / Dloader (apoc)', model = 'dloader' },
        },
    },
}

-- Flat model to entry lookup, built once in the shared config for client and server
-- The server only asks 'is this model on the list'. A model in two groups resolves to the last one.
Admin.VehicleByModel = {}
for _, group in ipairs(Admin.Vehicles) do
    for _, v in ipairs(group.items) do
        Admin.VehicleByModel[v.model] = v
    end
end

Admin.Weather = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN',
    'THUNDER', 'SMOG', 'FOGGY', 'XMAS', 'HALLOWEEN',
}

-- Weapons, grouped for usability. All base game.
-- The server authorises the request, the client gives the weapon since it must exist on the firing ped
Admin.Weapons = {
    {
        label = 'Melee',
        items = {
            { label = 'Knife',        model = 'WEAPON_KNIFE' },
            { label = 'Bat',          model = 'WEAPON_BAT' },
            { label = 'Crowbar',      model = 'WEAPON_CROWBAR' },
            { label = 'Machete',      model = 'WEAPON_MACHETE' },
            { label = 'Hatchet',      model = 'WEAPON_HATCHET' },
            { label = 'Hammer',       model = 'WEAPON_HAMMER' },
        },
    },
    {
        label = 'Sidearms',
        items = {
            { label = 'Pistol',       model = 'WEAPON_PISTOL',      ammo = 120 },
            { label = 'Combat pistol',model = 'WEAPON_COMBATPISTOL',ammo = 120 },
            { label = 'Heavy revolver',model = 'WEAPON_REVOLVER',   ammo = 60 },
            { label = 'Flare gun',    model = 'WEAPON_FLAREGUN',    ammo = 20 },
        },
    },
    {
        label = 'Long guns',
        items = {
            { label = 'Pump shotgun', model = 'WEAPON_PUMPSHOTGUN', ammo = 80 },
            { label = 'Sawn-off',     model = 'WEAPON_SAWNOFFSHOTGUN', ammo = 60 },
            { label = 'Carbine',      model = 'WEAPON_CARBINERIFLE', ammo = 250 },
            { label = 'Assault rifle',model = 'WEAPON_ASSAULTRIFLE', ammo = 250 },
            { label = 'Sniper',       model = 'WEAPON_SNIPERRIFLE',  ammo = 40 },
            { label = 'Marksman',     model = 'WEAPON_MARKSMANRIFLE',ammo = 60 },
        },
    },
    {
        label = 'Thrown & tools',
        items = {
            { label = 'Molotov',      model = 'WEAPON_MOLOTOV',     ammo = 10 },
            { label = 'Grenade',      model = 'WEAPON_GRENADE',     ammo = 10 },
            { label = 'Flashlight',   model = 'WEAPON_FLASHLIGHT' },
            { label = 'Fire extinguisher', model = 'WEAPON_FIREEXTINGUISHER', ammo = 500 },
        },
    },
}

-- Skill trees the menu can modify. Must match bs_skills config ids.
Admin.Skills = { 'combat', 'survival', 'crafting', 'medical' }

-- Amounts offered as one-click buttons.
Admin.QuickAmounts = { 1, 5, 10, 20 }

-- Picking one holds the clock there (see bs:admin:setTime in cl_main.lua); a one-shot override slides back to server time
-- Real time hands the clock back to the server: hour = -1 (anything outside 0-23 is a release)
Admin.TimePresets = {
    { label = 'Dawn',  hour = 6  },
    { label = 'Noon',  hour = 12 },
    { label = 'Dusk',  hour = 19 },
    { label = 'Night', hour = 1  },
    { label = 'Real time', hour = -1 },
}
