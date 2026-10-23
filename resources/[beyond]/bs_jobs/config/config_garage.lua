-- bs_jobs mechanic garage: an apocalyptic LS Customs at the faction yard.
-- Mechanics work on cars, the Bikers' Bike Mechanic on motorbikes (nobody else can touch a bike).
-- Mod slots are real GTA slots (saved on owned cars in bs_vehicles). Paint and props are saved here.
-- Paint numbers are GTA colour indices (worn / matte / util). Close enough to rust, primer and camo.

Jobs.Garage = {
    radius  = 14.0,   -- how close to your yard station the car must be
    maxBill = 5000,   -- (F1) highest bill a mechanic can send

    repair = { cost = { { item = 'scrap_metal', amount = 3 }, { item = 'screws', amount = 4 } } },

    paintCost = { { item = 'glue', amount = 1 }, { item = 'rags', amount = 2 } },
    paints = {
        { id = 'rust_red',     p1 = 48,  p2 = 106 },  -- worn dark red / worn brown
        { id = 'rust_orange',  p1 = 115, p2 = 107 },  -- worn orange / worn dark brown
        { id = 'primer_grey',  p1 = 13,  p2 = 14 },   -- matte grey / matte light grey
        { id = 'primer_black', p1 = 12,  p2 = 13 },   -- matte black / matte grey
        { id = 'bone',         p1 = 113, p2 = 105 },  -- worn off-white / worn honey beige
        { id = 'camo_wood',    p1 = 151, p2 = 152 },  -- matte forest green / matte olive drab
        { id = 'camo_desert',  p1 = 154, p2 = 153 },  -- matte desert tan / matte dark earth
        { id = 'camo_urban',   p1 = 22,  p2 = 12 },   -- worn graphite / matte black
    },

    -- cost is per level. max = highest level offered (clamped to what the car has).
    mods = {
        { id = 'armor',      slot = 16, max = 5, cost = { { item = 'scrap_metal', amount = 6 }, { item = 'screws', amount = 4 } } },
        { id = 'ram',        slot = 1,  max = 4, cost = { { item = 'scrap_metal', amount = 5 }, { item = 'metal_pipe', amount = 1 } } },
        { id = 'rear',       slot = 2,  max = 4, cost = { { item = 'scrap_metal', amount = 4 } } },
        { id = 'cage',       slot = 5,  max = 4, cost = { { item = 'metal_pipe', amount = 2 }, { item = 'screws', amount = 4 } } },
        { id = 'roof',       slot = 10, max = 4, cost = { { item = 'scrap_metal', amount = 4 }, { item = 'nails', amount = 6 } } },
        { id = 'hood',       slot = 7,  max = 4, cost = { { item = 'scrap_metal', amount = 4 } } },
        { id = 'grille',     slot = 6,  max = 4, cost = { { item = 'scrap_metal', amount = 2 }, { item = 'wires', amount = 1 } } },
        { id = 'skirts',     slot = 3,  max = 4, cost = { { item = 'scrap_metal', amount = 3 } } },
        { id = 'exhaust',    slot = 4,  max = 4, cost = { { item = 'metal_pipe', amount = 1 } } },
        { id = 'engine',     slot = 11, max = 4, cost = { { item = 'engine_part', amount = 1 }, { item = 'scrap_metal', amount = 4 } } },
        { id = 'brakes',     slot = 12, max = 3, cost = { { item = 'brake_pads', amount = 1 } } },
        { id = 'suspension', slot = 15, max = 4, cost = { { item = 'scrap_metal', amount = 3 }, { item = 'rubber', amount = 2 } } },
    },

    -- Bolted-on props (cars only). Each part tries its models in order; the first that exists is used.
    -- at: roof, front, left, right. off = extra offset, rot = rotation.
    props = {
        { id = 'roofrack', cost = { { item = 'scrap_metal', amount = 4 }, { item = 'wires', amount = 2 } }, parts = {
            { models = { 'prop_jerrycan_01a' }, at = 'roof', off = { -0.3, 0.1, 0.0 }, rot = { 0, 0, 90 } },
            { models = { 'prop_jerrycan_01a' }, at = 'roof', off = { 0.3, 0.1, 0.0 }, rot = { 0, 0, 90 } },
            { models = { 'prop_tool_box_02', 'prop_tool_box_04' }, at = 'roof', off = { 0.0, -0.55, 0.0 }, rot = { 0, 0, 0 } },
        } },
        { id = 'spikes', cost = { { item = 'nails', amount = 20 }, { item = 'scrap_metal', amount = 3 } }, parts = {
            { models = { 'p_ld_stinger_s', 'prop_mp_spike_01' }, at = 'front', off = { 0.0, 0.05, 0.0 }, rot = { 0, 0, 90 } },
        } },
        { id = 'cages', cost = { { item = 'metal_pipe', amount = 2 }, { item = 'wires', amount = 2 } }, parts = {
            { models = { 'prop_fnclink_03e', 'prop_barrier_work05' }, at = 'left', off = { 0.0, 0.0, 0.0 }, rot = { 0, 0, 90 } },
            { models = { 'prop_fnclink_03e', 'prop_barrier_work05' }, at = 'right', off = { 0.0, 0.0, 0.0 }, rot = { 0, 0, -90 } },
        } },
        { id = 'plates', cost = { { item = 'scrap_metal', amount = 8 }, { item = 'screws', amount = 6 } }, parts = {
            { models = { 'prop_metal_plates01', 'prop_barrier_work05' }, at = 'left', off = { 0.0, 0.0, -0.2 }, rot = { 0, 0, 90 } },
            { models = { 'prop_metal_plates01', 'prop_barrier_work05' }, at = 'right', off = { 0.0, 0.0, -0.2 }, rot = { 0, 0, -90 } },
        } },
        { id = 'bullbar', cost = { { item = 'metal_pipe', amount = 2 }, { item = 'scrap_metal', amount = 4 } }, parts = {
            { models = { 'prop_mp_barrier_02b', 'prop_barrier_work06a', 'prop_barrier_work05' }, at = 'front', off = { 0.0, 0.1, 0.1 }, rot = { 0, 0, 0 } },
        } },
    },
}
