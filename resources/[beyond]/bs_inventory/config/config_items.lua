-- bs_inventory - item definitions, synced into `bs_item_definitions` on start.

Items = {}


-- `spawnRounds`: how many rounds an admin-spawned weapon arrives with.
Items.Definitions = {
    vehicle_inverter = { label = 'Vehicle power inverter', category = 'vehicle', weight = 1.5, w = 2, h = 1, stack = 1, usable = true, value = 450, data = { handled = true, useEvent = 'bs:radio:installInverter' } },
    radio = { label = 'Field radio', category = 'tool', weight = 0.5, w = 1, h = 2, stack = 1, usable = true, value = 180, data = { handled = true, radio = true, useEvent = 'bs:walkie:open' } },
    radio_advanced = { label = 'Expedition radio', category = 'tool', weight = 0.65, w = 1, h = 2, stack = 1, usable = true, value = 650, data = { handled = true, radio = true, useEvent = 'bs:walkie:open' } },
    radio_military = { label = 'Military radio', category = 'tool', weight = 0.9, w = 1, h = 2, stack = 1, usable = true, value = 1800, data = { handled = true, radio = true, useEvent = 'bs:walkie:open' } },
    portable_antenna = { label = 'Portable relay kit', category = 'tool', weight = 3.5, w = 2, h = 3, stack = 1, usable = true, value = 900, data = { handled = true, useEvent = 'bs:walkie:deploy', defaultMeta = { batterySeconds = 3600 } } },
    bandage       = { label = 'Bandage',        category = 'medical', weight = 0.1, w = 1, h = 1, stack = 10, usable = true,  value = 15,  data = { heal = 20 } },
    medkit        = { label = 'Medkit',         category = 'medical', weight = 1.2, w = 2, h = 2, stack = 3,  usable = true,  value = 120, data = { heal = 75, revive = true } },
    water_bottle  = { label = 'Water bottle',   category = 'drink',   weight = 0.5, w = 1, h = 2, stack = 5,  usable = true,  value = 8,   data = { thirst = 35 } },
    canned_food   = { label = 'Canned food',    category = 'food',    weight = 0.4, w = 1, h = 1, stack = 8,  usable = true,  value = 12,  data = { hunger = 30 } },
    hunting_knife = { label = 'Hunting knife',  category = 'weapon',  weight = 0.8, w = 1, h = 2, stack = 1,  usable = true,  value = 90,  data = { weapon = 'WEAPON_KNIFE' } },
    toolbox       = { label = 'Toolbox',        category = 'tool',    weight = 3.0, w = 3, h = 2, stack = 1,  usable = true,  value = 150, data = { craftingStation = true } },
    scrap_metal   = { label = 'Scrap metal',    category = 'material',weight = 0.25, w = 1, h = 1, stack = 50, usable = false, value = 6 },
    cloth         = { label = 'Cloth',          category = 'material',weight = 0.1, w = 1, h = 1, stack = 50, usable = false, value = 4 },
    wood_plank    = { label = 'Wooden plank',   category = 'material',weight = 0.4, w = 2, h = 1, stack = 50, usable = false, value = 5 },
    faction_flag = { label = 'Outpost flag kit', category = 'construction', weight = 5.0, w = 2, h = 3, stack = 1, usable = false, value = 350 },
    safezone_flag = { label = 'Safezone flag', category = 'construction', weight = 8.0, w = 2, h = 3, stack = 1, usable = false, value = 1500 },
    -- Electrical salvage: copper is pulled from electrical boxes, wire is crafted from it.
    copper        = { label = 'Copper',          category = 'material',weight = 0.3, w = 1, h = 1, stack = 40, usable = false, value = 14 },
    duct_tape       = { label = 'Duct tape', category = 'material', weight = 0.1, w = 1, h = 1, stack = 20, usable = false, value = 12 },
    electrical_wire = { label = 'Electrical wire', category = 'material',weight = 0.15, w = 1, h = 1, stack = 40, usable = false, value = 34 },

    zombie_teeth  = { label = 'Zombie teeth',   category = 'trophy',  weight = 0.1, w = 1, h = 1, stack = 30, usable = false, value = 10 },

    -- VIP currency from the daily VIP crate (bs_vip). Not `usable`, since there is nothing to spend it on yet. Weightless.
    vip_coin      = { label = 'VIP coin',       category = 'currency',weight = 0.0, w = 1, h = 1, stack = 500, usable = false, value = 0 },

    -- Craftable and lootable medicine for infection.
    antiseptic    = { label = 'Antiseptic',     category = 'medical', weight = 0.3, w = 1, h = 1, stack = 5,  usable = true,  value = 60,  data = { cure = 20 } },
    antibiotics   = { label = 'Antibiotics',    category = 'medical', weight = 0.2, w = 1, h = 1, stack = 5,  usable = true,  value = 220, data = { cure = 55, heal = 10 } },

    -- Medical system (bs_medical). With it on, using one opens the Medical tab; with it off they do the plain thing below or nothing.
    rag             = { label = 'Rag',              category = 'medical', weight = 0.1, w = 1, h = 1, stack = 10, usable = true, value = 6,    data = { heal = 5 } },
    tourniquet      = { label = 'Tourniquet',       category = 'medical', weight = 0.2, w = 1, h = 1, stack = 3,  usable = true, value = 70,   data = { heal = 5 } },
    splint          = { label = 'Splint',           category = 'medical', weight = 0.4, w = 1, h = 2, stack = 3,  usable = true, value = 45,   data = { handled = true } },
    antiviral       = { label = 'Antiviral',        category = 'medical', weight = 0.2, w = 1, h = 1, stack = 5,  usable = true, value = 380,  data = { handled = true } },
    painkillers     = { label = 'Painkillers',      category = 'medical', weight = 0.1, w = 1, h = 1, stack = 10, usable = true, value = 80,   data = { heal = 5 } },
    saline          = { label = 'Saline bag',       category = 'medical', weight = 0.6, w = 1, h = 2, stack = 3,  usable = true, value = 90,   data = { heal = 15 } },
    blood_bag       = { label = 'Blood bag',        category = 'medical', weight = 0.6, w = 1, h = 2, stack = 3,  usable = true, value = 260,  data = { handled = true } },
    transfusion_kit = { label = 'Transfusion kit',  category = 'medical', weight = 0.8, w = 2, h = 1, stack = 1,  usable = true, value = 320,  data = { handled = true } },
    surgical_kit    = { label = 'Surgical kit',     category = 'medical', weight = 1.0, w = 2, h = 1, stack = 2,  usable = true, value = 450,  data = { handled = true } },
    defibrillator   = { label = 'Defibrillator',    category = 'medical', weight = 2.5, w = 2, h = 2, stack = 1,  usable = true, value = 1800, data = { handled = true } },

    -- Crafted only, not found.
    armour_plate  = { label = 'Bulletproof vest', category = 'gear',  weight = 4.5, w = 2, h = 2, stack = 1, usable = false, value = 300, equipSlot = 'armour', data = { stats = { armour = 50 }, durability = 100 } },
    reinforced_bat= { label = 'Reinforced bat', category = 'weapon',  weight = 2.4, w = 1, h = 3, stack = 1,  usable = true,  value = 180, data = { weapon = 'WEAPON_BAT' } },
    molotov       = { label = 'Molotov',        category = 'weapon',  weight = 0.8, w = 1, h = 2, stack = 4,  usable = true,  value = 140, data = { weapon = 'WEAPON_MOLOTOV', ammo = 1, throwable = true } },

    -- Firearms are items: using one draws it; it is never consumed and comes with no rounds. `ammoFor` on a box of
    pistol        = { label = '9mm pistol',     category = 'weapon', weight = 1.1, w = 2, h = 1, stack = 1, usable = true, value = 650,  data = { weapon = 'WEAPON_PISTOL', spawnRounds = 12 } },
    revolver      = { label = 'Revolver',       category = 'weapon', weight = 1.4, w = 2, h = 2, stack = 1, usable = true, value = 900,  data = { weapon = 'WEAPON_REVOLVER', spawnRounds = 6 } },
    smg           = { label = 'Submachine gun', category = 'weapon', weight = 2.8, w = 3, h = 2, stack = 1, usable = true, value = 1400, data = { weapon = 'WEAPON_SMG', spawnRounds = 30 } },
    pump_shotgun  = { label = 'Pump shotgun',   category = 'weapon', weight = 3.6, w = 4, h = 2, stack = 1, usable = true, value = 1250, data = { weapon = 'WEAPON_PUMPSHOTGUN', spawnRounds = 8 } },

    -- Weapons from the admin menu that have inventory items so kits and attachments work.
    combat_pistol = { label = 'Combat pistol',  category = 'weapon', weight = 1.2, w = 2, h = 1, stack = 1, usable = true, value = 850,  data = { weapon = 'WEAPON_COMBATPISTOL', spawnRounds = 12 } },
    sawn_off      = { label = 'Sawn-off',       category = 'weapon', weight = 2.8, w = 3, h = 2, stack = 1, usable = true, value = 1100, data = { weapon = 'WEAPON_SAWNOFFSHOTGUN', spawnRounds = 2 } },
    assault_rifle = { label = 'Assault rifle',  category = 'weapon', weight = 4.1, w = 4, h = 2, stack = 1, usable = true, value = 2600, data = { weapon = 'WEAPON_ASSAULTRIFLE', spawnRounds = 30 } },
    marksman      = { label = 'Marksman rifle', category = 'weapon', weight = 4.4, w = 4, h = 2, stack = 1, usable = true, value = 2900, data = { weapon = 'WEAPON_MARKSMANRIFLE', spawnRounds = 8 } },
    hammer        = { label = 'Hammer',         category = 'weapon', weight = 1.0, w = 1, h = 2, stack = 1, usable = true, value = 70,   data = { weapon = 'WEAPON_HAMMER' } },
    carbine       = { label = 'Carbine rifle',  category = 'weapon', weight = 3.9, w = 4, h = 2, stack = 1, usable = true, value = 2400, data = { weapon = 'WEAPON_CARBINERIFLE', spawnRounds = 30 } },
    hunting_rifle = { label = 'Hunting rifle',  category = 'weapon', weight = 4.2, w = 4, h = 2, stack = 1, usable = true, value = 2100, data = { weapon = 'WEAPON_SNIPERRIFLE', spawnRounds = 10 } },
    machete       = { label = 'Machete',        category = 'weapon', weight = 1.2, w = 1, h = 3, stack = 1, usable = true, value = 140,  data = { weapon = 'WEAPON_MACHETE' } },
    crowbar       = { label = 'Crowbar',        category = 'weapon', weight = 1.8, w = 1, h = 3, stack = 1, usable = true, value = 110,  data = { weapon = 'WEAPON_CROWBAR' } },
    -- Handheld flashlight: use it to draw WEAPON_FLASHLIGHT (never consumed).
    flashlight    = { label = 'Flashlight',     category = 'tool',   weight = 0.4, w = 1, h = 2, stack = 1, usable = true, value = 60,   data = { weapon = 'WEAPON_FLASHLIGHT' } },
    hatchet       = { label = 'Hatchet',        category = 'weapon', weight = 1.3, w = 1, h = 2, stack = 1, usable = true, value = 160,  data = { weapon = 'WEAPON_HATCHET', tool = 'logging', durability = 90 } },

    -- ammoFor must agree with bs_weapons Weapons.Magazines[..].ammo
    ammo_pistol   = { label = '9mm rounds',     category = 'ammo', weight = 0.02, w = 1, h = 1, stack = 60, usable = true, value = 4, data = { rounds = 12, ammoFor = { 'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_MACHINEPISTOL', 'WEAPON_SMG', 'WEAPON_MICROSMG', 'WEAPON_ASSAULTSMG' } } },
    ammo_magnum   = { label = '.44 rounds',     category = 'ammo', weight = 0.04, w = 1, h = 1, stack = 40, usable = true, value = 9, data = { rounds = 6,  ammoFor = { 'WEAPON_REVOLVER', 'WEAPON_PISTOL50' } } },
    ammo_shotgun  = { label = 'Buckshot',       category = 'ammo', weight = 0.06, w = 1, h = 1, stack = 40, usable = true, value = 7, data = { rounds = 8,  ammoFor = { 'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET' } } },
    ammo_rifle    = { label = 'Rifle rounds',   category = 'ammo', weight = 0.05, w = 1, h = 1, stack = 50, usable = true, value = 8, data = { rounds = 15, ammoFor = { 'WEAPON_CARBINERIFLE', 'WEAPON_ASSAULTRIFLE', 'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE', 'WEAPON_MG', 'WEAPON_COMBATMG' } } },

    -- Vehicle parts: all drop from wrecks as well as going into running cars.
    fuel_can      = { label = 'Jerry can',      category = 'vehicle', weight = 6.0, w = 2, h = 2, stack = 1, usable = false, value = 120, data = { capacity = 100, holds = 'diesel' } },

    -- Improvised jerrycan: a fifth of the capacity and a twentieth of the weight, so nobody is locked out of fuel.
    empty_bottle  = { label = 'Empty bottle',   category = 'vehicle', weight = 0.3, w = 1, h = 2, stack = 1, usable = false, value = 10,  data = { capacity = 20, holds = 'diesel' } },
    engine_part   = { label = 'Engine part',    category = 'vehicle', weight = 5.5, w = 2, h = 2, stack = 2, usable = false, value = 480 },
    battery       = { label = 'Car battery',    category = 'vehicle', weight = 8.0, w = 2, h = 2, stack = 1, usable = false, value = 320, data = { battery = true } },
    jumper_cables = { label = 'Jumper cables',  category = 'vehicle', weight = 1.5, w = 2, h = 1, stack = 1, usable = false, value = 90 },
    spark_plug    = { label = 'Spark plug',     category = 'vehicle', weight = 0.1, w = 1, h = 1, stack = 4, usable = false, value = 150 },
    fuel_tank     = { label = 'Fuel tank',      category = 'vehicle', weight = 9.0, w = 3, h = 2, stack = 1, usable = false, value = 360 },
    brake_pads    = { label = 'Brake pads',     category = 'vehicle', weight = 1.4, w = 1, h = 2, stack = 4, usable = false, value = 180 },
    tyre          = { label = 'Tyre',           category = 'vehicle', weight = 7.0, w = 2, h = 2, stack = 2, usable = false, value = 200 },
    repair_kit    = { label = 'Repair kit',     category = 'vehicle', weight = 3.2, w = 2, h = 2, stack = 2, usable = false, value = 260 },
    -- Tools that wear out: `durability` in item data is the number of uses.
    shovel        = { label = 'Shovel',         category = 'tool',    weight = 2.8, w = 1, h = 3, stack = 1, usable = false, value = 140, data = { tool = 'digging', durability = 60 } },

    pickaxe       = { label = 'Pickaxe',        category = 'tool',    weight = 3.4, w = 2, h = 3, stack = 1, usable = false, value = 180, data = { tool = 'mining', durability = 120 } },

    lockpick      = { label = 'Lockpick',       category = 'tool',    weight = 0.2, w = 1, h = 1, stack = 3, usable = false, value = 140 },

    -- Attachments are not usable: they are fitted from the weapon wheel (O), so a USE button would do nothing.
    att_suppressor= { label = 'Suppressor',     category = 'attachment', weight = 0.6, w = 1, h = 2, stack = 3, usable = false, value = 420, data = { attachment = 'suppressor' } },
    att_scope     = { label = 'Optic',          category = 'attachment', weight = 0.5, w = 2, h = 1, stack = 3, usable = false, value = 380, data = { attachment = 'scope' } },
    att_grip      = { label = 'Foregrip',       category = 'attachment', weight = 0.3, w = 1, h = 1, stack = 4, usable = false, value = 190, data = { attachment = 'grip' } },
    att_flashlight= { label = 'Weapon light',   category = 'attachment', weight = 0.3, w = 1, h = 1, stack = 4, usable = false, value = 160, data = { attachment = 'flashlight' } },
    att_extmag    = { label = 'Extended mag',   category = 'attachment', weight = 0.7, w = 1, h = 1, stack = 5, usable = false, value = 240, data = { attachment = 'extmag' } },
    -- Sixth attachment slot, see Weapons.Attachments.laser in bs_weapons/config/config_weapons.lua.
    att_laser     = { label = 'Laser sight',    category = 'attachment', weight = 0.2, w = 1, h = 1, stack = 4, usable = false, value = 210, data = { attachment = 'laser' } },

    -- Gadgets: deployables, slotted into the 2 gadget slots (bs_gadgets). Ids kept for old saves.
    booster_drone      = { label = 'Scout drone',   category = 'gadget', weight = 0.8, w = 2, h = 1, stack = 1, usable = false, value = 260, data = { gadget = true, battery = true, defaultMeta = { battery = 100, capacity = 'small' } } },
    booster_turret     = { label = 'Mini turret',   category = 'gadget', weight = 2.5, w = 2, h = 2, stack = 2, usable = false, value = 420, data = { gadget = true } },
    booster_medic      = { label = 'Medic beacon',  category = 'gadget', weight = 0.7, w = 1, h = 2, stack = 3, usable = false, value = 280, data = { gadget = true } },
    booster_decoy      = { label = 'Decoy',         category = 'gadget', weight = 0.4, w = 1, h = 1, stack = 5, usable = false, value = 120, data = { gadget = true } },
    -- Riot shield: a gadget now (bs_gadgets). Id kept for old saves.
    booster_shield     = { label = 'Riot Shield', category = 'gadget', weight = 0.5, w = 1, h = 1, stack = 3, usable = false, value = 240, data = { gadget = true } },
    -- Boosters: single-use buffs, slotted into the 3 booster slots (bs_boosters).
    booster_focus      = { label = 'Focus',         category = 'booster', weight = 0.1, w = 1, h = 1, stack = 5, usable = false, value = 180, data = { booster = true } },
    booster_regen      = { label = 'Painkiller drip', category = 'booster', weight = 0.2, w = 1, h = 1, stack = 5, usable = false, value = 200, data = { booster = true } },
    booster_fortify    = { label = 'Fortify',       category = 'booster', weight = 0.2, w = 1, h = 1, stack = 5, usable = false, value = 220, data = { booster = true } },
    booster_adrenaline = { label = 'Adrenaline',    category = 'booster', weight = 0.1, w = 1, h = 1, stack = 5, usable = false, value = 160, data = { booster = true } },
    -- Drugs (bs_drugs). _bad = zombie loot, plain = traders, _good = faction-base craft.
    cocaine_bad      = { label = 'Cocaine (cut)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 104, data = { drug = true } },
    cocaine          = { label = 'Cocaine', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 260, data = { drug = true } },
    cocaine_good     = { label = 'Cocaine (pure)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 468, data = { drug = true } },
    morphine_bad     = { label = 'Morphine (cut)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 96, data = { drug = true } },
    morphine         = { label = 'Morphine', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 240, data = { drug = true } },
    morphine_good    = { label = 'Morphine (pure)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 432, data = { drug = true } },
    amphetamine_bad  = { label = 'Amphetamine (cut)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 80, data = { drug = true } },
    amphetamine      = { label = 'Amphetamine', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 200, data = { drug = true } },
    amphetamine_good = { label = 'Amphetamine (pure)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 360, data = { drug = true } },
    weed_bad         = { label = 'Weed (cut)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 44, data = { drug = true } },
    weed             = { label = 'Weed', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 110, data = { drug = true } },
    weed_good        = { label = 'Weed (pure)', category = 'drug', weight = 0.05, w = 1, h = 1, stack = 10, usable = true, value = 198, data = { drug = true } },
    cigarette        = { label = 'Cigarette', category = 'drug', weight = 0.01, w = 1, h = 1, stack = 20, usable = true, value = 20, data = { drug = true } },
    lighter          = { label = 'Lighter', category = 'tool', weight = 0.05, w = 1, h = 1, stack = 1, usable = false, value = 60 },
    matches          = { label = 'Matches', category = 'tool', weight = 0.02, w = 1, h = 1, stack = 5, usable = false, value = 10 },
    -- World-event loot. Use it inside your own faction flag radius for faction XP (bs_events).
    faction_xp_token = { label = 'Faction XP token', category = 'currency', weight = 0.1, w = 1, h = 1, stack = 10, usable = true, value = 500, data = { handled = true } },
    rehab_kit        = { label = 'Rehab kit', category = 'medical', weight = 0.6, w = 1, h = 2, stack = 1, usable = true, value = 900, data = { drug = true } },
}

-- Standard firearms use the same per-item weapon records as the existing catalogue.
do
    local add = {
        ap_pistol = { label = 'AP pistol', category = 'weapon', weight = 1.1, w = 2, h = 2, stack = 1, usable = true, value = 1350, data = { weapon = 'WEAPON_APPISTOL', spawnRounds = 18 } },
        heavy_pistol = { label = 'Heavy pistol', category = 'weapon', weight = 1.2, w = 2, h = 2, stack = 1, usable = true, value = 1200, data = { weapon = 'WEAPON_HEAVYPISTOL', spawnRounds = 18 } },
        vintage_pistol = { label = 'Vintage pistol', category = 'weapon', weight = 0.9, w = 2, h = 2, stack = 1, usable = true, value = 760, data = { weapon = 'WEAPON_VINTAGEPISTOL', spawnRounds = 7 } },
        pistol_50 = { label = 'Heavy .50 pistol', category = 'weapon', weight = 1.5, w = 2, h = 2, stack = 1, usable = true, value = 1650, data = { weapon = 'WEAPON_PISTOL50', spawnRounds = 9 } },
        micro_smg = { label = 'Micro SMG', category = 'weapon', weight = 2.5, w = 3, h = 2, stack = 1, usable = true, value = 1350, data = { weapon = 'WEAPON_MICROSMG', spawnRounds = 16 } },
        assault_smg = { label = 'Assault SMG', category = 'weapon', weight = 3.0, w = 3, h = 2, stack = 1, usable = true, value = 2200, data = { weapon = 'WEAPON_ASSAULTSMG', spawnRounds = 30 } },
        machine_pistol = { label = 'Machine pistol', category = 'weapon', weight = 1.5, w = 2, h = 2, stack = 1, usable = true, value = 1150, data = { weapon = 'WEAPON_MACHINEPISTOL', spawnRounds = 12 } },
        advanced_rifle = { label = 'Advanced rifle', category = 'weapon', weight = 3.6, w = 4, h = 2, stack = 1, usable = true, value = 3200, data = { weapon = 'WEAPON_ADVANCEDRIFLE', spawnRounds = 30 } },
        special_carbine = { label = 'Special carbine', category = 'weapon', weight = 3.9, w = 4, h = 2, stack = 1, usable = true, value = 3400, data = { weapon = 'WEAPON_SPECIALCARBINE', spawnRounds = 30 } },
        bullpup_rifle = { label = 'Bullpup rifle', category = 'weapon', weight = 3.4, w = 4, h = 2, stack = 1, usable = true, value = 2900, data = { weapon = 'WEAPON_BULLPUPRIFLE', spawnRounds = 30 } },
        compact_rifle = { label = 'Compact rifle', category = 'weapon', weight = 2.9, w = 3, h = 2, stack = 1, usable = true, value = 2350, data = { weapon = 'WEAPON_COMPACTRIFLE', spawnRounds = 30 } },
        assault_shotgun = { label = 'Assault shotgun', category = 'weapon', weight = 4.3, w = 4, h = 2, stack = 1, usable = true, value = 3600, data = { weapon = 'WEAPON_ASSAULTSHOTGUN', spawnRounds = 8 } },
        bullpup_shotgun = { label = 'Bullpup shotgun', category = 'weapon', weight = 3.8, w = 4, h = 2, stack = 1, usable = true, value = 2850, data = { weapon = 'WEAPON_BULLPUPSHOTGUN', spawnRounds = 14 } },
        musket = { label = 'Musket', category = 'weapon', weight = 4.6, w = 5, h = 2, stack = 1, usable = true, value = 1100, data = { weapon = 'WEAPON_MUSKET', spawnRounds = 1 } },
        heavy_sniper = { label = 'Heavy sniper rifle', category = 'weapon', weight = 6.5, w = 5, h = 2, stack = 1, usable = true, value = 5700, data = { weapon = 'WEAPON_HEAVYSNIPER', spawnRounds = 6 } },
        mg = { label = 'Light machine gun', category = 'weapon', weight = 6.2, w = 5, h = 2, stack = 1, usable = true, value = 4600, data = { weapon = 'WEAPON_MG', spawnRounds = 54 } },
        combat_mg = { label = 'Combat machine gun', category = 'weapon', weight = 7.2, w = 5, h = 2, stack = 1, usable = true, value = 5600, data = { weapon = 'WEAPON_COMBATMG', spawnRounds = 100 } },
        gusenberg = { label = 'Gusenberg sweeper', category = 'weapon', weight = 4.8, w = 4, h = 2, stack = 1, usable = true, value = 2600, data = { weapon = 'WEAPON_GUSENBERG', spawnRounds = 30 } },
        combat_pdw = { label = 'Combat PDW', category = 'weapon', weight = 3.0, w = 3, h = 2, stack = 1, usable = true, value = 2500, data = { weapon = 'WEAPON_COMBATPDW', spawnRounds = 30 } },
        military_rifle = { label = 'Military rifle', category = 'weapon', weight = 3.6, w = 4, h = 2, stack = 1, usable = true, value = 4100, data = { weapon = 'WEAPON_MILITARYRIFLE', spawnRounds = 30 } },
        heavy_shotgun = { label = 'Heavy shotgun', category = 'weapon', weight = 4.1, w = 4, h = 2, stack = 1, usable = true, value = 3300, data = { weapon = 'WEAPON_HEAVYSHOTGUN', spawnRounds = 6 } },
        pistol_mk2 = { label = 'Pistol Mk II', category = 'weapon', weight = 1.0, w = 2, h = 2, stack = 1, usable = true, value = 1800, data = { weapon = 'WEAPON_PISTOL_MK2', spawnRounds = 12 } },
        sns_pistol_mk2 = { label = 'SNS pistol Mk II', category = 'weapon', weight = 0.8, w = 2, h = 2, stack = 1, usable = true, value = 1250, data = { weapon = 'WEAPON_SNSPISTOL_MK2', spawnRounds = 6 } },
        revolver_mk2 = { label = 'Heavy revolver Mk II', category = 'weapon', weight = 1.5, w = 2, h = 2, stack = 1, usable = true, value = 2300, data = { weapon = 'WEAPON_REVOLVER_MK2', spawnRounds = 6 } },
        smg_mk2 = { label = 'SMG Mk II', category = 'weapon', weight = 2.9, w = 3, h = 2, stack = 1, usable = true, value = 3100, data = { weapon = 'WEAPON_SMG_MK2', spawnRounds = 30 } },
        assault_rifle_mk2 = { label = 'Assault rifle Mk II', category = 'weapon', weight = 4.0, w = 4, h = 2, stack = 1, usable = true, value = 4300, data = { weapon = 'WEAPON_ASSAULTRIFLE_MK2', spawnRounds = 30 } },
        carbine_mk2 = { label = 'Carbine rifle Mk II', category = 'weapon', weight = 3.8, w = 4, h = 2, stack = 1, usable = true, value = 4500, data = { weapon = 'WEAPON_CARBINERIFLE_MK2', spawnRounds = 30 } },
        special_carbine_mk2 = { label = 'Special carbine Mk II', category = 'weapon', weight = 3.8, w = 4, h = 2, stack = 1, usable = true, value = 4700, data = { weapon = 'WEAPON_SPECIALCARBINE_MK2', spawnRounds = 30 } },
        bullpup_rifle_mk2 = { label = 'Bullpup rifle Mk II', category = 'weapon', weight = 3.5, w = 4, h = 2, stack = 1, usable = true, value = 4200, data = { weapon = 'WEAPON_BULLPUPRIFLE_MK2', spawnRounds = 30 } },
        combat_mg_mk2 = { label = 'Combat machine gun Mk II', category = 'weapon', weight = 7.0, w = 5, h = 2, stack = 1, usable = true, value = 6800, data = { weapon = 'WEAPON_COMBATMG_MK2', spawnRounds = 100 } },
        pump_shotgun_mk2 = { label = 'Pump shotgun Mk II', category = 'weapon', weight = 3.6, w = 4, h = 2, stack = 1, usable = true, value = 2850, data = { weapon = 'WEAPON_PUMPSHOTGUN_MK2', spawnRounds = 8 } },
        heavy_sniper_mk2 = { label = 'Heavy sniper Mk II', category = 'weapon', weight = 6.4, w = 5, h = 2, stack = 1, usable = true, value = 7400, data = { weapon = 'WEAPON_HEAVYSNIPER_MK2', spawnRounds = 6 } },
        marksman_mk2 = { label = 'Marksman rifle Mk II', category = 'weapon', weight = 4.4, w = 4, h = 2, stack = 1, usable = true, value = 4800, data = { weapon = 'WEAPON_MARKSMANRIFLE_MK2', spawnRounds = 8 } },
        att_muzzle_brake = { label = 'Muzzle brake', category = 'attachment', weight = 0.25, w = 1, h = 1, stack = 3, usable = false, value = 320, data = { attachment = 'muzzle_brake' } },
        att_reflex = { label = 'Reflex sight', category = 'attachment', weight = 0.3, w = 1, h = 1, stack = 3, usable = false, value = 290, data = { attachment = 'reflex' } },
        att_scope_long = { label = 'Long-range scope', category = 'attachment', weight = 0.8, w = 2, h = 1, stack = 3, usable = false, value = 620, data = { attachment = 'scope_long' } },
    }
    for id,definition in pairs(add)do Items.Definitions[id]=definition end
    local ammunition = {
        ammo_pistol = {'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_MICROSMG', 'WEAPON_ASSAULTSMG', 'WEAPON_MACHINEPISTOL', 'WEAPON_GUSENBERG', 'WEAPON_COMBATPDW', 'WEAPON_PISTOL_MK2', 'WEAPON_SNSPISTOL_MK2', 'WEAPON_SMG_MK2'},
        ammo_magnum = {'WEAPON_PISTOL50', 'WEAPON_REVOLVER_MK2'},
        ammo_shotgun = {'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2'},
        ammo_rifle = {'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_MILITARYRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE_MK2', 'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_BULLPUPRIFLE_MK2', 'WEAPON_COMBATMG_MK2', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE_MK2'},
    }
    for item,names in pairs(ammunition)do
        local pool=Items.Definitions[item].data.ammoFor
        local known={};for _,name in ipairs(pool)do known[name]=true end
        for _,name in ipairs(names)do if not known[name]then pool[#pool+1]=name;known[name]=true end end
    end
end

-- Crafting recipes live in bs_crafting/config/config_recipes.lua.
