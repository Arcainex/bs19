-- bs_zombies - atlas config. Adapted with permission from mrpz_zombies by Norway174 (data/atlas.lua, config/shared.lua); not a licence to redistribute her resource.
-- The atlas is a navigation graph, not a spawn table: each point has a density weight d, terrain t and neighbours n. Herds walk between points; nothing is placed at a point.
-- Coordinates are a baseline - re-survey them for your own map. Safe zones (config_zones.lua) are checked at move time in sv_nodes.lua.

ZAtlas = {}

-- Simulation tunables

-- Per-tick cost scales with node count, not population (population is one integer add per node)
-- Move/split is O(nodes) every tickMs, merge is O(nodes) plus O(bucket^2), growth is O(nodes x players)

ZAtlas.Simulation = {
    -- Population. Norway174's values were 1,000,000 initial / 10,000,000 cap / 640 nodes; these start lower.
    -- Raising initialPopulation costs nothing at runtime, raising initialNodeCount does
    initialPopulation = 250000,     -- hers: 1000000
    globalPopulationCap = 2500000,  -- hers: 10000000

    -- Herds the map starts with. 400 with the edge-seeding in sv_nodes.lua leaves about 10% of road without a herd
    -- Costs one iteration per node per move pass
    initialNodeCount = 400,         -- hers: 640

    -- Soft ceiling on herd count
    -- Above it merging is 16x more likely and splitting is scaled down by softTarget/count, so the count settles instead of hard-clamping
    nodeSoftTarget = 1200,          -- hers: 3000

    -- Main simulation tick. Movement and splitting happen here.
    tickMs = 2000,

    -- Sim time runs slower with nobody online (0.10 = an empty night advances the world about 2.5 hours)
    -- Multiplies sim time, not the tick rate
    emptyServerSpeed = 0.10,

    -- Merge and growth are structural changes; they do not need to run at movement rate and both are more expensive per pass than movement is
    mergeMs = 30000,
    growthMs = 60000,

    -- Logistic growth rate as a doubling time: 1.5 weeks to double at full isolation and no headroom pressure.
    weeksToDouble = 1.5,

    -- Max metres a herd may move in one tick, whatever its speed trait says
    -- Stops a large dt (server hitch, restart with stale timestamp) teleporting a horde
    maxMoveStep = 30.0,

    -- Herds within this radius of a waypoint count as arrived and pick a new destination
    arriveDistance = 15.0,

    -- Bucket size for the merge pass. Two herds in the same 180m square are close enough to be considered one crowd.
    mergeBucketSize = 180.0,

    -- Spatial memory cell size. 250m matches the sector size so 'cleared area' means the same in both systems.
    memoryCellSize = 250.0,

    -- How long a noise alert holds a herd's attention, before the herd's noiseResponse trait scales it
    -- Test with /znodes alert
    alertMs = 45000,
}

-- Trait ranges. Each node rolls its traits once from its own rngState.
-- Values are from Norway174; changing them changes what a typical herd does map-wide, so change one at a time

ZAtlas.Traits = {
    -- How strongly a herd holds together. High cohesion resists splitting and makes merging more likely.
    cohesion       = { 0.25, 0.95 },
    -- Preference for staying on the local edge of the graph rather than picking a fresh weighted destination anywhere on the map
    territoriality = { 0.05, 0.98 },
    -- Willingness to wander
    -- Currently only shades the behaviour label and mutates on split; it becomes load-bearing when the atlas is re-surveyed
    migration      = { 0.05, 0.95 },
    -- Multiplier on how long a noise alert holds this herd.
    noiseResponse  = { 0.35, 1.25 },
    -- Per-second probability of shedding a sub-herd
    -- Tiny by construction: this is multiplied by dt in seconds
    splitImpulse   = { 0.00004, 0.0005 },
    -- Metres per simulated second.
    speed          = { 0.18, 0.92 },
    -- Multiplier on the radius a herd's population implies
    -- Purely visual/ spatial - it decides how spread out the crowd is, not how big it is
    spread         = { 0.7, 1.6 },
}

-- Behaviour labels. intent is what the herd is doing (useful in diagnostics)
ZAtlas.Behaviors = {
    'territorial', 'city_roamer', 'mountain_roamer', 'road_migrant', 'wanderer', 'stimulus',
}

-- Waypoint graph, re-surveyed for this map from Norway174's table
-- Edges must be symmetric (chooseNextTarget only walks to neighbours of the current point);

ZAtlas.version = 2
ZAtlas.bounds = { minX = -3800.0, maxX = 4500.0, minY = -4200.0, maxY = 8200.0 }

ZAtlas.points = {
    { id='ls_airport',       x=-1035.0, y=-2735.0, z=20.0,  d=4.0,  t='city',       n={2,3,5} },
    { id='vespucci',         x=-1220.0, y=-1320.0, z=5.0,   d=7.0,  t='city',       n={1,3,4} },
    { id='downtown',         x=120.0,   y=-910.0,  z=30.0,  d=12.0, t='city',       n={1,2,4,5,6,7,32,33} },
    { id='del_perro',        x=-1450.0, y=-400.0,  z=35.0,  d=9.0,  t='city',       n={2,3,7,32,35} },
    { id='south_ls',         x=240.0,   y=-1730.0, z=28.0,  d=10.0, t='city',       n={1,3,6,8,31} },
    { id='east_ls',          x=950.0,   y=-1200.0, z=30.0,  d=10.0, t='city',       n={3,5,8,9,10,34} },
    { id='vinewood',         x=-150.0,  y=450.0,   z=110.0, d=9.0,  t='city',       n={3,4,10,11,32,33} },
    { id='docks',            x=920.0,   y=-2850.0, z=8.0,   d=7.0,  t='industrial', n={5,6,9,31,36} },
    { id='la_mesa',          x=980.0,   y=-1850.0, z=30.0,  d=8.0,  t='industrial', n={6,8,10,31,34,36} },
    { id='mirror_park',      x=1150.0,  y=-520.0,  z=65.0,  d=7.0,  t='city',       n={6,7,9,12,33} },
    { id='vinewood_hills',   x=-450.0,  y=1100.0,  z=325.0, d=4.0,  t='mountain',   n={7,12,13} },
    { id='tataviam',         x=1800.0,  y=700.0,   z=160.0, d=2.5,  t='mountain',   n={10,11,14,15} },
    { id='tongva',           x=-1550.0, y=1550.0,  z=115.0, d=2.0,  t='mountain',   n={11,16,17,35} },
    { id='senora_south',     x=1700.0,  y=2100.0,  z=105.0, d=2.3,  t='desert',     n={12,15,18} },
    { id='wind_farm',        x=2350.0,  y=1850.0,  z=105.0, d=2.0,  t='desert',     n={12,14,19} },
    { id='zancudo_east',     x=-1150.0, y=2400.0,  z=55.0,  d=1.5,  t='rural',      n={13,17,18,20,37} },
    { id='chumash_north',    x=-2350.0, y=2200.0,  z=55.0,  d=2.2,  t='rural',      n={13,16,21,35,37} },
    { id='harmony',          x=550.0,   y=2650.0,  z=45.0,  d=4.0,  t='town',       n={14,16,19,20,22} },
    { id='sandy_shores',     x=2050.0,  y=3880.0,  z=35.0,  d=5.0,  t='town',       n={15,18,22,23} },
    { id='route_68',         x=-450.0,  y=2850.0,  z=35.0,  d=2.5,  t='road',       n={16,18,21,22,37} },
    { id='great_chaparral',  x=-1200.0, y=3300.0,  z=65.0,  d=1.5,  t='mountain',   n={17,20,24,37} },
    { id='senora',           x=500.0,   y=3600.0,  z=35.0,  d=2.0,  t='desert',     n={18,19,20,23,24} },
    { id='grapeseed',        x=2450.0,  y=4850.0,  z=45.0,  d=4.5,  t='town',       n={19,22,25,26} },
    { id='mount_josiah',     x=-1150.0, y=4200.0,  z=200.0, d=1.0,  t='mountain',   n={21,22,25,27} },
    { id='alamo_west',       x=750.0,   y=4650.0,  z=145.0, d=1.2,  t='mountain',   n={23,24,26,27} },
    { id='chiliad_east',     x=2350.0,  y=5700.0,  z=650.0, d=0.8,  t='mountain',   n={23,25,28,29} },
    { id='chiliad_west',     x=-350.0,  y=5450.0,  z=550.0, d=0.8,  t='mountain',   n={24,25,28} },
    { id='paleto_south',     x=-350.0,  y=6350.0,  z=35.0,  d=3.0,  t='rural',      n={26,27,29,30} },
    { id='paleto_bay',       x=-110.0,  y=6500.0,  z=32.0,  d=6.0,  t='town',       n={26,28,30} },
    { id='proccopio',        x=-1200.0, y=7000.0,  z=25.0,  d=2.0,  t='rural',      n={28,29} },
    { id='cypress',          x=800.0,   y=-2300.0, z=28.0,  d=7.0,  t='industrial', n={5,8,9,34} },
    { id='rockford',         x=-750.0,  y=-250.0,  z=38.0,  d=9.0,  t='city',       n={3,4,7} },
    { id='hawick',           x=380.0,   y=-150.0,  z=65.0,  d=10.0, t='city',       n={3,7,10} },
    { id='murrieta',         x=1250.0,  y=-1550.0, z=45.0,  d=7.5,  t='industrial', n={6,9,31,36} },
    { id='banham',           x=-2750.0, y=100.0,   z=15.0,  d=2.5,  t='rural',      n={4,13,17} },
    { id='el_burro',         x=1450.0,  y=-2500.0, z=55.0,  d=5.5,  t='industrial', n={8,9,34} },
    -- Fort Zancudo: position matches the military spawn zone in config_zones.lua
    -- Density 3.0 (big base, little walkable); neighbours are the four approaches so herds can migrate in and out
    { id='fort_zancudo',     x=-2100.0, y=3100.0,  z=32.0,  d=3.0,  t='industrial', n={16,17,20,21} },
}


-- Persistence settings (nothing else reads them).

ZAtlas.Persistence = {
    -- Turning persistence off is supported: the simulation runs in memory and reseeds at every restart
    -- Useful on dev servers or if the schema is missing
    enabled = true,

    -- How often the dirty sweep saves changed herds (30s)
    -- Longer loses more on a crash, shorter rewrites the same herds. Runs on its own thread.
    saveMs = 30000,

    -- Parameter sets per prepared-statement batch, so the first save after a reseed is several ordinary statements instead of one huge one
    batchSize = 200,
}

ZAtlas.Decay = {
    -- Kill pressure half-life in simulated hours: 168 (one sim week) to halve
    -- Long so a cleared town stays thin the next day, but no cell stays dead forever
    killPressureHalfLifeHours = 168.0,
}


-- Validating the graph
-- Runs at every boot because hand-edited neighbour lists easily end up one-way or unreachable, which silently drains parts of the map

--- @return table problems  list of human-readable strings, empty when healthy
function ZAtlas.Validate()
    local problems = {}
    local points = ZAtlas.points or {}
    local count = #points

    if count == 0 then
        return { 'ZAtlas.points is empty - the simulation has nowhere to put anything' }
    end

    for i = 1, count do
        local p = points[i]

        if type(p.x) ~= 'number' or type(p.y) ~= 'number' then
            problems[#problems + 1] = ('#%d (%s) has no usable position'):format(i, tostring(p.id))
        end
        if type(p.d) ~= 'number' or p.d <= 0 then
            problems[#problems + 1] = ('#%d (%s) has density %s - it can never be seeded')
                :format(i, tostring(p.id), tostring(p.d))
        end
        if type(p.n) ~= 'table' or #p.n == 0 then
            problems[#problems + 1] = ('#%d (%s) has NO neighbours - a herd that arrives can never leave')
                :format(i, tostring(p.id))
        end

        for _, j in ipairs(p.n or {}) do
            if type(j) ~= 'number' or j < 1 or j > count then
                problems[#problems + 1] = ('#%d (%s) lists neighbour %s, which is not a point')
                    :format(i, tostring(p.id), tostring(j))
            elseif j == i then
                problems[#problems + 1] = ('#%d (%s) lists itself as a neighbour')
                    :format(i, tostring(p.id))
            else
                -- One-way edge: herds can leave through it but never return, since chooseNextTarget only walks to neighbours of the current point
                local back = false
                for _, k in ipairs(points[j].n or {}) do
                    if k == i then back = true break end
                end
                if not back then
                    problems[#problems + 1] = ('ONE-WAY EDGE: %s -> %s, but %s does not list %s back')
                        :format(p.id, points[j].id, points[j].id, p.id)
                end
            end
        end
    end

    -- Reachability sweep: symmetric edges do not guarantee a connected graph
    -- Flood-fill from point 1; anything unreached is an island
    local seen, stack = { [1] = true }, { 1 }
    while #stack > 0 do
        local current = table.remove(stack)
        for _, j in ipairs(points[current].n or {}) do
            if points[j] and not seen[j] then
                seen[j] = true
                stack[#stack + 1] = j
            end
        end
    end

    for i = 1, count do
        if not seen[i] then
            problems[#problems + 1] = ('UNREACHABLE: %s cannot be walked to from the rest of the graph')
                :format(points[i].id)
        end
    end

    return problems
end
