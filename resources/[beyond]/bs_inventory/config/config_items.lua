-- bs_inventory - item definitions, synced into `bs_item_definitions` on start.

Items = {}


-- `spawnRounds`: how many rounds an admin-spawned weapon arrives with. Read only by bs_admin's giveweapon, which seeds the bs_weapons ammo store. Separate from `data.ammo` (used by throwables) so weapons found in the world stay empty.
Items.Definitions = {
    -- BS19 extra prop loot items
    plastic = { label = 'Plastic', category = 'material', weight = 0.12, w = 1, h = 1, stack = 30, usable = false, value = 4 },
	paper = { label = 'Papier', category = 'material', weight = 0.08, w = 1, h = 1, stack = 100, usable = false, value = 5 },
	tape = { label = 'Duct tape', category = 'material', weight = 0.15, w = 1, h = 1, stack = 30, usable = false, value = 10 },
    cement = { label = 'Cement', category = 'material', weight = 2.0, w = 1, h = 1, stack = 30, usable = false, value = 7 },
    toilet_paper = { label = 'Toilet paper', category = 'material', weight = 0.1, w = 1, h = 1, stack = 30, usable = false, value = 2 },
    poop = { label = 'Kacke', category = 'material', weight = 0.3, w = 1, h = 1, stack = 30, usable = false, value = 1 },
    apple = { label = 'Apple', category = 'food', weight = 0.2, w = 1, h = 1, stack = 30, usable = false, value = 5 },
    banana = { label = 'Banana', category = 'food', weight = 0.2, w = 1, h = 1, stack = 30, usable = false, value = 5 },
    expired_meat = { label = 'Abgelaufenes Fleisch', category = 'material', weight = 0.4, w = 1, h = 1, stack = 30, usable = false, value = 3 },
    bone = { label = 'Knochen', category = 'material', weight = 0.2, w = 1, h = 1, stack = 30, usable = false, value = 2 },
    fertilizer = { label = 'Duenger', category = 'material', weight = 0.5, w = 1, h = 1, stack = 30, usable = false, value = 8 },
    -- ================================================================
    -- GRUNDVERSORGUNG: Medizin, Nahrung und einfache Werkzeuge
    -- ================================================================
	book = { label = 'Book', category = 'item', weight = 0.3, w = 1, h = 1, stack = 1, usable = true, value = 50, data = { handled = true, useEvent = 'bs:books:use' } },
    pacific_blueprints = { label = 'Pacific Bank Blueprints', category = 'item', weight = 0.5, w = 1, h = 1, stack = 1, usable = true, value = 500, data = { handled = true, useEvent = 'bs:books:use' } },
    tourism_guide = { label = 'Tourism Guide', category = 'item', weight = 0.3, w = 1, h = 1, stack = 1, usable = true, value = 100, data = { handled = true, useEvent = 'bs:books:use' } },
    medkit        = { label = 'Medkit',         category = 'medical', weight = 1.2, w = 1, h = 1, stack = 5,  usable = true,  value = 120, data = { heal = 75, revive = true } },
    bandage       = { label = 'Verband',        category = 'medical', weight = 0.10, w = 1, h = 1, stack = 10, usable = true,  value = 20,  data = { heal = 15 } },
    water_bottle  = { label = 'Water bottle',   category = 'drink',   weight = 0.5, w = 1, h = 1, stack = 10,  usable = true,  value = 8,   data = { thirst = 35 } },
    canned_food   = { label = 'Canned food',    category = 'food',    weight = 0.4, w = 1, h = 1, stack = 10,  usable = true,  value = 12,  data = { hunger = 30 } },
    hunting_knife = { label = 'Hunting knife',  category = 'weapon',  weight = 0.8, w = 1, h = 1, stack = 1,  usable = true,  value = 90,  data = { weapon = 'WEAPON_KNIFE' } },
    toolbox       = { label = 'Toolbox',        category = 'tool',    weight = 3.0, w = 1, h = 1, stack = 3,  usable = true,  value = 150, data = { craftingStation = true } },
    -- ================================================================
    -- BAUMATERIALIEN UND NATURROHSTOFFE
    -- ================================================================
    stick         = { label = 'Stock', category = 'material', weight = 0.2, w = 1, h = 1, stack = 30, usable = false, value = 1 },
    scrap_metal   = { label = 'Scrap metal',    category = 'material',weight = 0.25, w = 1, h = 1, stack = 50, usable = false, value = 6 },
    cloth         = { label = 'Cloth',          category = 'material',weight = 0.1, w = 1, h = 1, stack = 50, usable = false, value = 4 },
    wood_plank    = { label = 'Wooden plank',   category = 'material',weight = 0.4, w = 1, h = 1, stack = 50, usable = false, value = 5 },
    faction_flag = { label = 'Outpost flag kit', category = 'construction', weight = 5.0, w = 1, h = 2, stack = 1, usable = false, value = 350 },
    safezone_flag = { label = 'Safezone flag', category = 'construction', weight = 8.0, w = 1, h = 2, stack = 1, usable = false, value = 1500 },
    -- Electrical salvage: copper is pulled from electrical boxes, wire is crafted from it. Copper is heavy on purpose so looting everything is a trade-off.
    copper        = { label = 'Copper',          category = 'material',weight = 0.3, w = 1, h = 1, stack = 40, usable = false, value = 14 },
    electrical_wire = { label = 'Electrical wire', category = 'material',weight = 0.15, w = 1, h = 1, stack = 40, usable = false, value = 34 },

    zombie_teeth  = { label = 'Zombie teeth',   category = 'trophy',  weight = 0.1, w = 1, h = 1, stack = 30, usable = false, value = 10 },

    -- VIP currency from the daily VIP crate (bs_vip). Not `usable`, since there is nothing to spend it on yet. Weightless.
    vip_coin      = { label = 'VIP coin',       category = 'currency',weight = 0.0, w = 1, h = 1, stack = 500, usable = false, value = 0 },

    -- Craftable and lootable medicine for infection.
    antiseptic    = { label = 'Antiseptic',     category = 'medical', weight = 0.3, w = 1, h = 1, stack = 5,  usable = true,  value = 60,  data = { cure = 20 } },
    antibiotics   = { label = 'Antibiotics',    category = 'medical', weight = 0.2, w = 1, h = 1, stack = 5,  usable = true,  value = 220, data = { cure = 55, heal = 10 } },

    -- ================================================================
    -- ERWEITERTE MEDIZIN
    -- ================================================================
    -- Medical system (bs_medical). With it on, using one opens the Medical tab; with it off they do the plain thing below or nothing.
    rag             = { label = 'Rag',              category = 'medical', weight = 0.1, w = 1, h = 1, stack = 10, usable = true, value = 6,    data = { heal = 5 } },
    tourniquet      = { label = 'Tourniquet',       category = 'medical', weight = 0.2, w = 1, h = 1, stack = 3,  usable = true, value = 70,   data = { heal = 5 } },
    splint          = { label = 'Splint',           category = 'medical', weight = 0.4, w = 1, h = 1, stack = 3,  usable = true, value = 45,   data = { handled = true } },
    antiviral       = { label = 'Antiviral',        category = 'medical', weight = 0.2, w = 1, h = 1, stack = 5,  usable = true, value = 380,  data = { handled = true } },
    painkillers     = { label = 'Painkillers',      category = 'medical', weight = 0.1, w = 1, h = 1, stack = 10, usable = true, value = 80,   data = { heal = 5 } },
    saline          = { label = 'Saline bag',       category = 'medical', weight = 0.6, w = 1, h = 1, stack = 3,  usable = true, value = 90,   data = { heal = 15 } },
    blood_bag       = { label = 'Blood bag',        category = 'medical', weight = 0.6, w = 1, h = 1, stack = 3,  usable = true, value = 260,  data = { handled = true } },
    transfusion_kit = { label = 'Transfusion kit',  category = 'medical', weight = 0.8, w = 1, h = 1, stack = 1,  usable = true, value = 320,  data = { handled = true } },
    surgical_kit    = { label = 'Surgical kit',     category = 'medical', weight = 1.0, w = 1, h = 1, stack = 2,  usable = true, value = 450,  data = { handled = true } },
    defibrillator   = { label = 'Defibrillator',    category = 'medical', weight = 2.5, w = 1, h = 1, stack = 1,  usable = true, value = 1800, data = { handled = true } },

    -- Crafted only, not found.
    armour_plate  = { label = 'Bulletproof vest', category = 'gear',  weight = 4.5, w = 1, h = 1, stack = 1, usable = false, value = 300, equipSlot = 'armour', data = { stats = { armour = 50 }, durability = 100 } },
    reinforced_bat= { label = 'Reinforced bat', category = 'weapon',  weight = 2.4, w = 1, h = 1, stack = 1,  usable = true,  value = 180, data = { weapon = 'WEAPON_BAT' } },
    molotov       = { label = 'Molotov',        category = 'weapon',  weight = 0.8, w = 1, h = 1, stack = 4,  usable = true,  value = 140, data = { weapon = 'WEAPON_MOLOTOV', ammo = 1, throwable = true } },

    -- ================================================================
    -- SCHUSSWAFFEN UND NAHKAMPF
    -- ================================================================
    -- Firearms are items. Using one draws it; it is never consumed and comes with no rounds. `ammoFor` on a box of rounds lists the weapons it loads and is checked against the weapon in hand.
    pistol        = { label = '9mm pistol',     category = 'weapon', weight = 1.1, w = 1, h = 1, stack = 1, usable = true, value = 650,  data = { weapon = 'WEAPON_PISTOL', spawnRounds = 12 } },
    revolver      = { label = 'Revolver',       category = 'weapon', weight = 1.4, w = 1, h = 1, stack = 1, usable = true, value = 900,  data = { weapon = 'WEAPON_REVOLVER', spawnRounds = 6 } },
    smg           = { label = 'Submachine gun', category = 'weapon', weight = 2.8, w = 1, h = 1, stack = 1, usable = true, value = 1400, data = { weapon = 'WEAPON_SMG', spawnRounds = 30 } },
    pump_shotgun  = { label = 'Pump shotgun',   category = 'weapon', weight = 3.6, w = 1, h = 1, stack = 1, usable = true, value = 1250, data = { weapon = 'WEAPON_PUMPSHOTGUN', spawnRounds = 8 } },

    -- Weapons from the admin menu that have inventory items so kits and attachments work. Without an item, weaponItemFor returns nil and the weapon falls back to the ped, where the bag cannot see, weigh or drop it.
    combat_pistol = { label = 'Combat pistol',  category = 'weapon', weight = 1.2, w = 1, h = 1, stack = 1, usable = true, value = 850,  data = { weapon = 'WEAPON_COMBATPISTOL', spawnRounds = 12 } },
    sawn_off      = { label = 'Sawn-off',       category = 'weapon', weight = 2.8, w = 1, h = 1, stack = 1, usable = true, value = 1100, data = { weapon = 'WEAPON_SAWNOFFSHOTGUN', spawnRounds = 2 } },
    assault_rifle = { label = 'Assault rifle',  category = 'weapon', weight = 4.1, w = 1, h = 1, stack = 1, usable = true, value = 2600, data = { weapon = 'WEAPON_ASSAULTRIFLE', spawnRounds = 30 } },
    marksman      = { label = 'Marksman rifle', category = 'weapon', weight = 4.4, w = 1, h = 1, stack = 1, usable = true, value = 2900, data = { weapon = 'WEAPON_MARKSMANRIFLE', spawnRounds = 8 } },
    hammer        = { label = 'Hammer',         category = 'weapon', weight = 1.0, w = 1, h = 1, stack = 1, usable = true, value = 70,   data = { weapon = 'WEAPON_HAMMER' } },
    carbine       = { label = 'Carbine rifle',  category = 'weapon', weight = 3.9, w = 1, h = 1, stack = 1, usable = true, value = 2400, data = { weapon = 'WEAPON_CARBINERIFLE', spawnRounds = 30 } },
    hunting_rifle = { label = 'Hunting rifle',  category = 'weapon', weight = 4.2, w = 1, h = 1, stack = 1, usable = true, value = 2100, data = { weapon = 'WEAPON_SNIPERRIFLE', spawnRounds = 10 } },
    machete       = { label = 'Machete',        category = 'weapon', weight = 1.2, w = 1, h = 1, stack = 1, usable = true, value = 140,  data = { weapon = 'WEAPON_MACHETE' } },
    crowbar       = { label = 'Crowbar',        category = 'weapon', weight = 1.8, w = 1, h = 1, stack = 1, usable = true, value = 110,  data = { weapon = 'WEAPON_CROWBAR' } },
    -- Handheld flashlight: use it to draw WEAPON_FLASHLIGHT (never consumed).
    flashlight    = { label = 'Flashlight',     category = 'tool',   weight = 0.4, w = 1, h = 1, stack = 1, usable = true, value = 60,   data = { weapon = 'WEAPON_FLASHLIGHT' } },
    hatchet       = { label = 'Hatchet',        category = 'weapon', weight = 1.3, w = 1, h = 1, stack = 1, usable = true, value = 160,  data = { weapon = 'WEAPON_HATCHET', tool = 'logging', durability = 90 } },

    -- ammoFor must agree with bs_weapons Weapons.Magazines[..].ammo
    ammo_pistol   = { label = '9mm rounds',     category = 'ammo', weight = 0.02, w = 1, h = 1, stack = 60, usable = true, value = 4, data = { rounds = 12, ammoFor = { 'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_MACHINEPISTOL', 'WEAPON_SMG', 'WEAPON_MICROSMG', 'WEAPON_ASSAULTSMG' } } },
    ammo_magnum   = { label = '.44 rounds',     category = 'ammo', weight = 0.04, w = 1, h = 1, stack = 40, usable = true, value = 9, data = { rounds = 6,  ammoFor = { 'WEAPON_REVOLVER', 'WEAPON_PISTOL50' } } },
    ammo_shotgun  = { label = 'Buckshot',       category = 'ammo', weight = 0.06, w = 1, h = 1, stack = 40, usable = true, value = 7, data = { rounds = 8,  ammoFor = { 'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET' } } },
    ammo_rifle    = { label = 'Rifle rounds',   category = 'ammo', weight = 0.05, w = 1, h = 1, stack = 50, usable = true, value = 8, data = { rounds = 15, ammoFor = { 'WEAPON_CARBINERIFLE', 'WEAPON_ASSAULTRIFLE', 'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE', 'WEAPON_MG', 'WEAPON_COMBATMG' } } },

    -- ================================================================
    -- FAHRZEUGE UND REPARATURTEILE
    -- ================================================================
    -- Vehicle parts: all drop from wrecks as well as going into running cars.
    -- Jerrycan is a container: `capacity` is up to 100 units, and the current level is stored on the slot like a tool's durability.
    fuel_can      = { label = 'Jerry can',      category = 'vehicle', weight = 6.0, w = 1, h = 1, stack = 1, usable = false, value = 120, data = { capacity = 100, holds = 'diesel' } },

    -- Improvised jerrycan: a fifth of the capacity and a twentieth of the weight, so nobody is locked out of fuel.
    empty_bottle  = { label = 'Empty bottle',   category = 'vehicle', weight = 0.3, w = 1, h = 1, stack = 1, usable = false, value = 10,  data = { capacity = 20, holds = 'diesel' } },
    engine_part   = { label = 'Motor',    category = 'vehicle', weight = 10.0, w = 2, h = 2, stack = 2, usable = false, value = 480 },
    gearbox       = { label = 'Gearbox',        category = 'vehicle', weight = 10.0, w = 2, h = 2, stack = 1, usable = false, value = 520 },
    bonnet        = { label = 'Bonnet',         category = 'vehicle', weight = 10.0, w = 2, h = 2, stack = 1, usable = false, value = 300 },
    rear_bumper   = { label = 'Rear bumper',    category = 'vehicle', weight = 8.0, w = 2, h = 2, stack = 1, usable = false, value = 260 },
    exhaust       = { label = 'Exhaust',        category = 'vehicle', weight = 5.0, w = 2, h = 2, stack = 1, usable = false, value = 240 },
    car_door      = { label = 'Car door',       category = 'vehicle', weight = 10.0, w = 2, h = 2, stack = 1, usable = false, value = 280 },
    battery       = { label = 'Car battery',    category = 'vehicle', weight = 8.0, w = 2, h = 1, stack = 1, usable = false, value = 320, data = { battery = true } },
    jumper_cables = { label = 'Jumper cables',  category = 'vehicle', weight = 1.5, w = 1, h = 1, stack = 1, usable = false, value = 90 },
    spark_plug    = { label = 'Spark plug',     category = 'vehicle', weight = 0.1, w = 1, h = 1, stack = 4, usable = false, value = 150 },
    fuel_tank     = { label = 'Fuel tank',      category = 'vehicle', weight = 8.0, w = 2, h = 2, stack = 1, usable = false, value = 360 },
    brake_pads    = { label = 'Brake pads',     category = 'vehicle', weight = 1.4, w = 2, h = 1, stack = 4, usable = false, value = 180 },
    tyre          = { label = 'Tyre',           category = 'vehicle', weight = 7.0, w = 2, h = 2, stack = 2, usable = false, value = 200 },
    repair_kit    = { label = 'Repair kit',     category = 'vehicle', weight = 3.2, w = 1, h = 1, stack = 3, usable = false, value = 260 },
    -- Tools that wear out: `durability` in item data is the number of uses. A pickaxe has no `weapon` field; it is consumed by working. The hatchet is both a weapon and a tool.
    shovel        = { label = 'Shovel',         category = 'tool',    weight = 2.8, w = 1, h = 1, stack = 1, usable = false, value = 140, data = { tool = 'digging', durability = 60 } },

    pickaxe       = { label = 'Pickaxe',        category = 'tool',    weight = 3.4, w = 1, h = 1, stack = 1, usable = false, value = 180, data = { tool = 'mining', durability = 120 } },

    lockpick      = { label = 'Lockpick',       category = 'tool',    weight = 0.2, w = 1, h = 1, stack = 10, usable = false, value = 140 },

    -- ================================================================
    -- WAFFENAUFSAETZE
    -- ================================================================
    -- Attachments are not usable: they are fitted from the weapon wheel (O), so a USE button would do nothing.
    att_suppressor= { label = 'Suppressor',     category = 'attachment', weight = 0.6, w = 1, h = 1, stack = 3, usable = false, value = 420, data = { attachment = 'suppressor' } },
    att_scope     = { label = 'Optic',          category = 'attachment', weight = 0.5, w = 1, h = 1, stack = 3, usable = false, value = 380, data = { attachment = 'scope' } },
    att_grip      = { label = 'Foregrip',       category = 'attachment', weight = 0.3, w = 1, h = 1, stack = 4, usable = false, value = 190, data = { attachment = 'grip' } },
    att_flashlight= { label = 'Weapon light',   category = 'attachment', weight = 0.3, w = 1, h = 1, stack = 4, usable = false, value = 160, data = { attachment = 'flashlight' } },
    att_extmag    = { label = 'Extended mag',   category = 'attachment', weight = 0.7, w = 1, h = 1, stack = 5, usable = false, value = 240, data = { attachment = 'extmag' } },
    -- Sixth attachment slot, see Weapons.Attachments.laser in bs_weapons/config/config_weapons.lua. Uses the shared 'attachment' icon fallback (icons.js).
    att_laser     = { label = 'Laser sight',    category = 'attachment', weight = 0.2, w = 1, h = 1, stack = 4, usable = false, value = 210, data = { attachment = 'laser' } },

    -- ================================================================
    -- GADGETS, BOOSTER UND SONSTIGES
    -- ================================================================
    -- Gadgets: deployables, slotted into the 2 gadget slots (bs_gadgets). Ids kept for old saves.
    booster_drone      = { label = 'Scout drone',   category = 'gadget', weight = 0.8, w = 1, h = 1, stack = 1, usable = false, value = 260, data = { gadget = true, battery = true, defaultMeta = { battery = 100, capacity = 'small' } } },
    booster_turret     = { label = 'Mini turret',   category = 'gadget', weight = 2.5, w = 1, h = 1, stack = 2, usable = false, value = 420, data = { gadget = true } },
    booster_medic      = { label = 'Medic beacon',  category = 'gadget', weight = 0.7, w = 1, h = 1, stack = 3, usable = false, value = 280, data = { gadget = true } },
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
    rehab_kit        = { label = 'Rehab kit', category = 'medical', weight = 0.6, w = 1, h = 1, stack = 4, usable = true, value = 900, data = { drug = true } },
}

-- Crafting recipes live in bs_crafting/config/config_recipes.lua.
