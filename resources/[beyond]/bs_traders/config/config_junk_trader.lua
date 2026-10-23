-- Junk traders: buy scrap, junk and crafting materials for cash. Prices are per unit; edit freely.
Traders.JunkPrices = {
    scrap_metal = 3, nails = 1, screws = 1, electronics = 9, wires = 3, plastic = 1, rubber = 2, glue = 4,
    duct_tape = 5, leather = 4, gunpowder = 3, gun_parts = 20, lead = 2, copper = 5, metal_pipe = 6,
    infected_blood = 120, bone = 1, rotten_flesh = 1,
    deer_hide = 16, boar_hide = 13, rabbit_pelt = 6, coyote_pelt = 11, mtlion_pelt = 38,
    junk_radio = 12, junk_battery = 15, junk_pipe = 5, junk_tape = 2, junk_phone = 10, junk_laptop = 25,
    junk_toaster = 7, junk_kettle = 5, junk_fan = 8, junk_cables = 6, junk_clock = 4, junk_camera = 11,
    junk_hairdryer = 6, junk_remote = 3, junk_lamp = 5, junk_cans = 1, junk_chain = 4, junk_shoes = 3,
    junk_gears = 5, junk_spraycan = 2, junk_glue = 2,
}

-- Building supplies sold by junk dealers (bs_building). About 1.5x catalogue value, so scavenging stays cheaper.
Traders.BuildSupplies = {
    { item = 'wood_plank',  price = 8,   stock = 80,  restockAmount = 20 },
    { item = 'log',         price = 9,   stock = 40,  restockAmount = 10 },
    { item = 'nails',       price = 3,   stock = 300, restockAmount = 60 },
    { item = 'scrap_metal', price = 9,   stock = 80,  restockAmount = 20 },
    { item = 'hammer',      price = 105, stock = 4 },
}

local function buys()
    local out = {}
    for item, price in pairs(Traders.JunkPrices) do out[#out + 1] = { item = item, price = price } end
    table.sort(out, function(a, b) return a.item < b.item end)
    return out
end

Traders.Traders.junk_civilians = {
    label = 'Junk Dealer', role = 'trader',
    zone = 'civilians', offset = vector3(8.0, -6.0, 0.0), heading = 200.0,
    model = 's_m_y_garbage', scenario = 'WORLD_HUMAN_CLIPBOARD',
    buys = buys(), sells = Traders.BuildSupplies,
}
Traders.Traders.junk_paleto = {
    label = 'Junk Dealer', role = 'trader',
    zone = 'paleto', offset = vector3(9.0, 2.0, 0.0), heading = 270.0,
    model = 's_m_y_garbage', scenario = 'WORLD_HUMAN_CLIPBOARD',
    buys = buys(), sells = Traders.BuildSupplies,
}
