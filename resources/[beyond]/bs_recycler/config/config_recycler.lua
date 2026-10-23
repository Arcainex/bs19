-- bs_recycler config. Fuel-driven machines at fixed world spots. Anyone can load, start or empty one.
-- Points are kept in the database (bs_recycler_points); Recycler.Points only seeds an empty table.
-- Settings marked (F1) are live in the F1 console; points and the blacklist have their own F1 pages.

Recycler = {}

Recycler.Settings = {
    enabled          = true,   -- (F1)
    radius           = 2.5,
    itemSeconds      = 5,      -- (F1) seconds per item
    itemsPerLitre    = 10,     -- (F1) items one litre of fuel runs
    fuelMax          = 20,     -- litres a machine holds
    fuelItems        = { 'fuel_can', 'empty_bottle' },
    yieldRate        = 0.5,    -- (F1) share of the crafting cost that comes back
    dismantleRate    = 0.25,   -- (F1) hand dismantle share
    dismantleSeconds = 10,     -- (F1)
    skill            = 'crafting',
    bonusPerLevel    = 0.01,   -- (F1) +1% yield per crafting level
    bonusMax         = 0.15,   -- (F1)
    noiseRadius      = 150.0,  -- (F1) zombies hear a running machine this far
    noiseEvery       = 10,     -- seconds between noise pulses
    xpPerItem        = 1,
    inSize           = { w = 4, h = 3, maxWeight = 300.0 },
    outSize          = { w = 6, h = 4, maxWeight = 400.0 },
    models           = { 'prop_ind_mech_02a', 'prop_ind_mech_03a', 'prop_compressor_03', 'prop_generator_03b' },
    drawDistance     = 150.0,
}

-- Per-item scrap table for junk and things with no recipe. Amounts are what the machine gives at yieldRate 0.5;
-- they scale with the rate. `tool` is what hand dismantling needs (screwdriver for electronics, wrench for metal).
Recycler.Yields = {
    junk_radio     = { tool = 'screwdriver', { item = 'electronics', amount = { 1, 2 } }, { item = 'wires', amount = { 1, 2 } }, { item = 'plastic', amount = { 1, 2 } } },
    junk_battery   = { tool = 'wrench',      { item = 'lead', amount = { 3, 6 } }, { item = 'plastic', amount = { 1, 2 } } },
    junk_pipe      = { tool = 'wrench',      { item = 'metal_pipe', amount = { 1, 1 } }, { item = 'scrap_metal', amount = { 0, 1 } } },
    junk_tape      = { tool = 'screwdriver', { item = 'duct_tape', amount = { 0, 1 } }, { item = 'glue', amount = { 0, 1 } } },
    junk_phone     = { tool = 'screwdriver', { item = 'electronics', amount = { 1, 1 } }, { item = 'plastic', amount = { 1, 1 } } },
    junk_laptop    = { tool = 'screwdriver', { item = 'electronics', amount = { 2, 3 } }, { item = 'plastic', amount = { 1, 3 } }, { item = 'screws', amount = { 2, 4 } } },
    junk_toaster   = { tool = 'screwdriver', { item = 'scrap_metal', amount = { 1, 2 } }, { item = 'wires', amount = { 1, 1 } }, { item = 'screws', amount = { 1, 3 } } },
    junk_kettle    = { tool = 'screwdriver', { item = 'plastic', amount = { 1, 2 } }, { item = 'wires', amount = { 0, 1 } } },
    junk_fan       = { tool = 'screwdriver', { item = 'electronics', amount = { 0, 1 } }, { item = 'plastic', amount = { 1, 2 } }, { item = 'copper', amount = { 1, 2 } } },
    junk_cables    = { tool = 'screwdriver', { item = 'wires', amount = { 2, 3 } }, { item = 'copper', amount = { 1, 2 } }, { item = 'rubber', amount = { 0, 1 } } },
    junk_clock     = { tool = 'screwdriver', { item = 'electronics', amount = { 0, 1 } }, { item = 'screws', amount = { 1, 2 } } },
    junk_camera    = { tool = 'screwdriver', { item = 'electronics', amount = { 1, 2 } }, { item = 'glue', amount = { 0, 1 } } },
    junk_hairdryer = { tool = 'screwdriver', { item = 'wires', amount = { 1, 2 } }, { item = 'plastic', amount = { 1, 1 } } },
    junk_remote    = { tool = 'screwdriver', { item = 'electronics', amount = { 0, 1 } }, { item = 'plastic', amount = { 0, 1 } } },
    junk_lamp      = { tool = 'screwdriver', { item = 'wires', amount = { 1, 1 } }, { item = 'scrap_metal', amount = { 0, 1 } } },
    junk_cans      = { tool = 'wrench',      { item = 'scrap_metal', amount = { 0, 1 } } },
    junk_chain     = { tool = 'wrench',      { item = 'scrap_metal', amount = { 1, 1 } } },
    junk_shoes     = { tool = 'screwdriver', { item = 'rubber', amount = { 1, 2 } }, { item = 'leather', amount = { 0, 1 } } },
    junk_gears     = { tool = 'wrench',      { item = 'scrap_metal', amount = { 1, 2 } }, { item = 'screws', amount = { 0, 2 } } },
    junk_spraycan  = { tool = 'wrench',      { item = 'scrap_metal', amount = { 0, 1 } } },
    junk_glue      = { tool = 'screwdriver', { item = 'glue', amount = { 0, 1 } } },
    tyre           = { tool = 'wrench',      { item = 'rubber', amount = { 3, 5 } }, { item = 'scrap_metal', amount = { 0, 1 } } },
    engine_part    = { tool = 'wrench',      { item = 'scrap_metal', amount = { 5, 8 } }, { item = 'screws', amount = { 2, 4 } } },
    brake_pads     = { tool = 'wrench',      { item = 'scrap_metal', amount = { 1, 2 } } },
    spark_plug     = { tool = 'wrench',      { item = 'scrap_metal', amount = { 0, 1 } }, { item = 'electronics', amount = { 0, 1 } } },
    repair_kit     = { tool = 'wrench',      { item = 'scrap_metal', amount = { 2, 4 } }, { item = 'duct_tape', amount = { 0, 1 } } },
    armour_plate   = { tool = 'wrench',      { item = 'scrap_metal', amount = { 2, 4 } }, { item = 'cloth', amount = { 1, 3 } } },
    att_scope      = { tool = 'screwdriver', { item = 'electronics', amount = { 0, 1 } }, { item = 'scrap_metal', amount = { 1, 2 } } },
}

-- Firearms with no recipe come apart into gun parts and scrap. Fitted attachments come back first, whole.
Recycler.Firearm = { { item = 'gun_parts', amount = { 1, 2 } }, { item = 'scrap_metal', amount = { 2, 4 } }, { item = 'screws', amount = { 1, 3 } } }

-- Never accepted (F1 blacklist adds to this).
Recycler.Never = {
    scrap_metal = true, cloth = true, wood_plank = true, vip_coin = true, fuel_can = true, empty_bottle = true,
    faction_flag = true, safezone_flag = true, faction_xp_token = true, nails = true, screws = true, electronics = true, wires = true,
    plastic = true, rubber = true, glue = true, duct_tape = true, leather = true, gunpowder = true, gun_parts = true, lead = true,
}

-- Seed spots (scrapyards and industrial areas). Used only while the points table is empty.
Recycler.Points = {
    { id = 'rogers_salvage',  label = 'Recycler', coords = vector4(-468.5, -1718.0, 18.7, 90.0) },
    { id = 'sandy_scrapyard', label = 'Recycler', coords = vector4(2351.2, 3122.4, 48.2, 0.0) },
    { id = 'paleto_works',    label = 'Recycler', coords = vector4(-104.0, 6205.0, 31.0, 45.0) },
    { id = 'cypress_foundry', label = 'Recycler', coords = vector4(1078.0, -1975.0, 31.0, 0.0) },
    { id = 'elysian_docks',   label = 'Recycler', coords = vector4(480.0, -3050.0, 6.0, 0.0) },
    { id = 'davis_quarry',    label = 'Recycler', coords = vector4(2950.0, 2790.0, 41.0, 0.0) },
}
