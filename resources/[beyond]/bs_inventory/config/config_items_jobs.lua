-- bs_inventory - items used by faction jobs (bs_jobs): fishing, kidnapping, smuggling, supply runs.

local add = {
    fishing_rod   = { label = 'Fishing rod',    category = 'tool',     weight = 1.2,  w = 1, h = 3, stack = 1,  usable = false, value = 90 },
    fish_bait     = { label = 'Fish bait',      category = 'material', weight = 0.05, w = 1, h = 1, stack = 30, usable = false, value = 3 },
    raw_fish      = { label = 'Raw fish',       category = 'food',     weight = 0.5,  w = 1, h = 1, stack = 10, usable = true,  value = 10, data = { hunger = 6, useEvent = 'bs:crafting:useItem' } },
    big_fish      = { label = 'Big fish',       category = 'food',     weight = 1.6,  w = 2, h = 1, stack = 4,  usable = false, value = 45 },
    cooked_fish   = { label = 'Cooked fish',    category = 'food',     weight = 0.4,  w = 1, h = 1, stack = 10, usable = true,  value = 24, data = { hunger = 32 } },
    zip_ties      = { label = 'Zip ties',       category = 'tool',     weight = 0.05, w = 1, h = 1, stack = 10, usable = false, value = 25 },
    head_sack     = { label = 'Head sack',      category = 'tool',     weight = 0.2,  w = 1, h = 1, stack = 3,  usable = false, value = 15 },
    contraband    = { label = 'Contraband',     category = 'junk',     weight = 4.0,  w = 2, h = 2, stack = 1,  usable = false, value = 0 },
    supply_crate  = { label = 'Supply crate',   category = 'junk',     weight = 6.0,  w = 2, h = 2, stack = 1,  usable = false, value = 0 },
    siphon_hose   = { label = 'Siphon hose',    category = 'tool',     weight = 0.4,  w = 1, h = 2, stack = 1,  usable = false, value = 40 },
}

for id, def in pairs(add) do
    if Items.Definitions[id] == nil then Items.Definitions[id] = def end
end

-- Rods are equipment. Casting uses bait, never the rod itself.
Items.Definitions.fishing_rod.usable = true
Items.Definitions.fishing_rod.data = { handled = true, useEvent = 'bs:jobs:useRod' }
local outdoors = {
    sticks = { label='Sticks', category='material', weight=.1, w=1, h=2, stack=40, usable=false, value=1 },
    leaves = { label='Leaves', category='material', weight=.02, w=1, h=1, stack=50, usable=false, value=1 },
    cranberries = { label='Wild berries', category='food', weight=.08, w=1, h=1, stack=20, usable=true, value=4, data={hunger=4} },
    fish_bass = { label='Bass', category='food', weight=.7, w=2, h=1, stack=8, usable=false, value=16 },
    fish_catfish = { label='Catfish', category='food', weight=1.2, w=2, h=1, stack=6, usable=false, value=28 },
    fish_trout = { label='Trout', category='food', weight=.8, w=2, h=1, stack=6, usable=false, value=55 },
    fish_salmon = { label='Salmon', category='food', weight=1.5, w=2, h=1, stack=4, usable=false, value=110 },
    fish_mackerel = { label='Mackerel', category='food', weight=.5, w=2, h=1, stack=8, usable=false, value=18 },
}
for id, def in pairs(outdoors) do
    if not Items.Definitions[id] then Items.Definitions[id]=def end
end
