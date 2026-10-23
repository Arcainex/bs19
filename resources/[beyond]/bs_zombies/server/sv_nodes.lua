-- bs_zombies - zombie node (herd) population simulation

local S = ZAtlas.Simulation
local T = ZAtlas.Traits
local P = ZAtlas.Persistence
local D = ZAtlas.Decay

-- Deterministic maths, ported from mrpz shared/util.lua

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- Squared planar distance (avoids a sqrt per node per tick).
local function distance2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

local function copyTable(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copyTable(entry) end
    return result
end

-- Lehmer / Park-Miller: state = state * 48271 mod (2^31 - 1)
local function nextRandom(state)
    state = ((state or 1) * 48271) % 2147483647
    if state <= 0 then state = 1 end
    return state, state / 2147483647
end

--- @return integer newState, number value in [minimum, maximum]
local function randomRange(state, minimum, maximum)
    local nextState, value = nextRandom(state)
    return nextState, minimum + (maximum - minimum) * value
end

--- @return integer newState, number value rolled from a { lo, hi } config pair
local function randomTrait(state, range)
    return randomRange(state, range[1], range[2])
end

--- Cell key for the spatial memory and the merge buckets.
local function spatialKey(x, y, size)
    return ('%d:%d'):format(math.floor(x / size), math.floor(y / size))
end

local function tableCount(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

-- State

ZNodes = {}

-- The campaign world state. simTimeMs is the only clock the simulation reads.
ZNodes.campaign = nil

--- All live herds, keyed by id.
ZNodes.nodes = {}

-- 250m memory cells: { x, y, lastObserved, visitHeat, killPressure }
ZNodes.spatialMemory = {}

ZNodes.nextNodeId = 1
ZNodes.ready = false
ZNodes.lastMeanSpeed = 0.0

-- Counters since resource start (not persisted), shown by /znodes.
ZNodes.stats = { births = 0, deaths = 0, splits = 0, merges = 0 }

-- Ids of removed herds waiting to be deleted from the table. deletedSet dedupes.
ZNodes.deletedIds = {}
ZNodes.deletedSet = {}

-- Persistence bookkeeping for /znodes. saving stops the periodic save and a manual /znodesave
ZNodes.persistence = {
    enabled = false,
    loadedFromDb = false,
    saving = false,
    lastSaveSimMs = -1,
    lastSaveRealMs = 0,
    lastCounts = { nodes = 0, memory = 0, deleted = 0 },
    saves = 0,
    failures = 0,
}

-- The only legal way to remove a node
local function forgetNode(id)
    if ZNodes.nodes[id] == nil then return end
    ZNodes.nodes[id] = nil
    if not ZNodes.deletedSet[id] then
        ZNodes.deletedSet[id] = true
        ZNodes.deletedIds[#ZNodes.deletedIds + 1] = id
    end
end

-- Atlas helpers

-- Never returns nil
local function point(index)
    return ZAtlas.points[index] or ZAtlas.points[1]
end

-- Roulette selection over density weights, so dense areas (downtown) get proportionally more herds
local function chooseWeightedPoint(state)
    local total = 0
    for i = 1, #ZAtlas.points do total = total + ZAtlas.points[i].d end

    local value
    state, value = randomRange(state, 0, total)

    local cursor = 0
    for index = 1, #ZAtlas.points do
        cursor = cursor + ZAtlas.points[index].d
        if value <= cursor then return state, index end
    end
    return state, 1
end

-- Safe zones come from Zones.Safe in config_zones.lua, the same list the spawner uses
local function safePosition(x, y)
    for _, zone in ipairs(Zones and Zones.Safe or {}) do
        local c = zone.coords
        if c then
            local dx, dy = x - c.x, y - c.y
            local r = (zone.radius or 0.0)
            if dx * dx + dy * dy <= r * r then return false end
        end
    end
    return true
end

-- Node construction

-- Traits are rolled once per herd and only change through inheritance with mutation on a split
local function makeTraits(state, atlasIndex)
    local cohesion, territoriality, migration, noise, split, speed, spread

    state, cohesion       = randomTrait(state, T.cohesion)
    state, territoriality = randomTrait(state, T.territoriality)
    state, migration      = randomTrait(state, T.migration)
    state, noise          = randomTrait(state, T.noiseResponse)
    state, split          = randomTrait(state, T.splitImpulse)
    state, speed          = randomTrait(state, T.speed)
    state, spread         = randomTrait(state, T.spread)

    local behaviors = ZAtlas.Behaviors
    local behavior = behaviors[(state % #behaviors) + 1]

    local atlasType = point(atlasIndex).t
    if atlasType == 'mountain' and migration > 0.45 then behavior = 'mountain_roamer' end
    if atlasType == 'city' and territoriality > 0.45 then behavior = 'city_roamer' end

    return state, {
        cohesion = cohesion,
        territoriality = territoriality,
        migration = migration,
        noiseResponse = noise,
        splitImpulse = split,
        speed = speed,
        spread = spread,
        behavior = behavior,
    }
end

-- Radius = sqrt(population) * 1.8 * spread (a crowd covers an area). Recomputed wherever population changes so the Stage 3 planner never sees a stale size.
local function radiusFor(population, spread)
    return math.max(8.0, math.sqrt(population) * 1.8 * spread)
end

-- A split child copies its parent's traits and mutates cohesion (+/-0.08) and migration (+/-0.10)
local function newNode(id, population, atlasIndex, state, parent, spreadAlongEdge)
    local home = point(atlasIndex)

    -- Seeded herds start somewhere along an edge
    local originX, originY, originZ = home.x, home.y, home.z

    if spreadAlongEdge and home.n and #home.n > 0 then
        local pick, along
        state, pick = randomRange(state, 1.0, #home.n + 0.999)
        local neighbour = point(home.n[math.floor(pick)] or atlasIndex)

        state, along = randomRange(state, 0.0, 1.0)
        originX = home.x + (neighbour.x - home.x) * along
        originY = home.y + (neighbour.y - home.y) * along
        -- z is interpolated; only a hint to the client, which finds real ground with GetSafeCoordForPed.
        originZ = home.z + ((neighbour.z or home.z) - home.z) * along
    end

    local jitterX, jitterY
    state, jitterX = randomRange(state, -180.0, 180.0)
    state, jitterY = randomRange(state, -180.0, 180.0)

    local traits
    state, traits = makeTraits(state, atlasIndex)

    if parent then
        traits = copyTable(parent.traits)
        local mutation
        state, mutation = randomRange(state, -0.08, 0.08)
        traits.cohesion = clamp(traits.cohesion + mutation, 0.05, 0.99)
        state, mutation = randomRange(state, -0.10, 0.10)
        traits.migration = clamp(traits.migration + mutation, 0.01, 0.99)
    end

    local target = (home.n and #home.n > 0) and home.n[(state % #home.n) + 1] or atlasIndex

    return {
        id = id,
        population = population,
        x = originX + jitterX,
        y = originY + jitterY,
        z = originZ,
        radius = radiusFor(population, traits.spread),
        rngState = state,
        homeAtlas = atlasIndex,
        targetAtlas = target,
        intent = traits.behavior,
        traits = traits,
        alert = nil,
        updatedSimMs = 0,
        -- Set on every mutation so persistence can sweep dirty flags instead of diffing every node.
        dirty = true,
    }
end

-- Players and observation

-- no entity iterators here
local function playerList()
    local result = {}
    for _, source in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(source)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            result[#result + 1] = { source = tonumber(source), x = coords.x, y = coords.y, z = coords.z }
        end
    end
    return result
end

local function nearestPlayerDistance2(node, list)
    local nearest = math.huge
    for i = 1, #list do
        local d = distance2(node, list[i])
        if d < nearest then nearest = d end
    end
    return nearest
end

--- @return table memory entry for the cell containing (x, y), created if new
local function memoryAt(x, y)
    local key = spatialKey(x, y, S.memoryCellSize)
    local memory = ZNodes.spatialMemory[key]
    if not memory then
        memory = {
            x = x, y = y, visitHeat = 0.0, killPressure = 0.0, lastObserved = nil,
            -- Sim time at which killPressure was last updated
            pressureAtMs = ZNodes.campaign and ZNodes.campaign.simTimeMs or 0,
        }
        ZNodes.spatialMemory[key] = memory
    end
    return memory, key
end

-- Kill pressure decays exponentially with a half-life of one sim week
-- @return number the cell's kill pressure, decayed to now
local function killPressureOf(memory)
    if not memory then return 0.0 end

    local pressure = memory.killPressure or 0.0
    if pressure <= 0 then return 0.0 end

    local halfLife = (D and D.killPressureHalfLifeHours) or 0
    -- A half-life of zero or less means no decay.
    if halfLife <= 0 then return pressure end

    local elapsedHours = (ZNodes.campaign.simTimeMs - (memory.pressureAtMs or 0)) / 3600000
    if elapsedHours <= 0 then return pressure end

    pressure = pressure * (0.5 ^ (elapsedHours / halfLife))
    -- Snap a tiny remainder to zero so the cell can finish forgetting and stop being dirty.
    if pressure < 0.001 then pressure = 0.0 end

    memory.killPressure = pressure
    memory.pressureAtMs = ZNodes.campaign.simTimeMs
    memory.dirty = true
    return pressure
end

-- Records player presence. lastObserved (timestamp) drives isolation
local function observePlayers(list)
    for i = 1, #list do
        local memory = memoryAt(list[i].x, list[i].y)
        memory.lastObserved = ZNodes.campaign.simTimeMs
        memory.visitHeat = clamp(memory.visitHeat + 0.04, 0, 10)
        memory.dirty = true
    end
end

-- Pass: movement

-- Pick a destination: territoriality is rolled against a random number
local function chooseNextTarget(node)
    local current = point(node.targetAtlas)
    local choices = current.n

    if not choices or #choices == 0 then
        node.targetAtlas = node.homeAtlas
        return
    end

    local state, chance = randomRange(node.rngState, 0, 1)
    node.rngState = state

    if node.traits.territoriality > chance then
        node.targetAtlas = choices[(state % #choices) + 1]
    else
        node.rngState, node.targetAtlas = chooseWeightedPoint(node.rngState)
    end

    node.intent = node.traits.behavior
end

-- An alert overrides the destination
-- @return number metres per simulated second travelled (summed for the mean-speed diagnostic)
local function moveNode(node, dt)
    local target

    if node.alert and node.alert.expires > ZNodes.campaign.simTimeMs then
        target = node.alert
        node.intent = 'stimulus'
    else
        -- Expired alerts are cleared here, when the herd is already in hand.
        node.alert = nil
        target = point(node.targetAtlas)
    end

    local dx, dy = target.x - node.x, target.y - node.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < S.arriveDistance then
        -- Arrived
        if not node.alert then chooseNextTarget(node) end
        return 0
    end

    local step = math.min(distance, S.maxMoveStep, node.traits.speed * dt)
    local nx, ny = node.x + dx / distance * step, node.y + dy / distance * step

    if safePosition(nx, ny) then
        node.x, node.y = nx, ny
        -- z is interpolated toward the target, so a herd halfway up a mountain is halfway up
        if target.z then node.z = node.z + (target.z - node.z) * math.min(1.0, step / distance) end
        node.dirty = true
    else
        chooseNextTarget(node)
    end

    return step / math.max(dt, 0.001)
end

-- Pass: split

-- Split chance = splitImpulse * dt * pressure * (0.35 + (1 - cohesion))
local function maybeSplit(node, nodeCount, dt)
    if node.population < 12 then return end

    local pressure = nodeCount > S.nodeSoftTarget and (S.nodeSoftTarget / nodeCount) or 1.0
    local chance = node.traits.splitImpulse * dt * pressure * (0.35 + (1.0 - node.traits.cohesion))

    local state, roll = randomRange(node.rngState, 0, 1)
    node.rngState = state
    if roll >= chance then return end

    local fraction
    node.rngState, fraction = randomRange(node.rngState, 0.04, 0.30)

    local amount = math.max(1, math.floor(node.population * fraction))
    if amount >= node.population then return end

    node.population = node.population - amount
    node.radius = radiusFor(node.population, node.traits.spread)
    node.dirty = true

    -- The child's home is the parent's current destination, so a long march seeds the places it passes through
    local child = newNode(ZNodes.nextNodeId, amount, node.targetAtlas, node.rngState, node)
    child.x, child.y, child.z = node.x, node.y, node.z
    child.updatedSimMs = ZNodes.campaign.simTimeMs

    ZNodes.nextNodeId = ZNodes.nextNodeId + 1
    ZNodes.nodes[child.id] = child
    ZNodes.stats.splits = ZNodes.stats.splits + 1
end

-- Pass: merge

-- Merge pressure keeps the node count (the tick cost) bounded
local function mergePass()
    local buckets = {}
    local nodeCount = tableCount(ZNodes.nodes)
    local mergePressure = nodeCount > S.nodeSoftTarget and 0.16 or 0.01

    for _, node in pairs(ZNodes.nodes) do
        local key = spatialKey(node.x, node.y, S.mergeBucketSize)
        local bucket = buckets[key]
        if not bucket then
            bucket = {}
            buckets[key] = bucket
        end
        bucket[#bucket + 1] = node
    end

    for _, bucket in pairs(buckets) do
        if #bucket > 1 then
            table.sort(bucket, function(a, b) return a.id < b.id end)
            local primary = bucket[1]

            for index = 2, #bucket do
                local other = bucket[index]
                -- Check liveness twice: a node earlier in this bucket may already have been absorbed this pass.
                if ZNodes.nodes[primary.id] and ZNodes.nodes[other.id] then
                    local compatible = primary.intent == other.intent or distance2(primary, other) < 2500.0
                    local chance = (primary.traits.cohesion + other.traits.cohesion) * mergePressure

                    local state, roll = randomRange(primary.rngState, 0, 1)
                    primary.rngState = state

                    if compatible and roll < chance then
                        primary.population = primary.population + other.population
                        primary.radius = radiusFor(primary.population, primary.traits.spread)
                        primary.dirty = true
                        -- forgetNode, not = nil, so the absorbed herd's row is deleted too.
                        forgetNode(other.id)
                        ZNodes.stats.merges = ZNodes.stats.merges + 1
                    end
                end
            end
        end
    end
end

-- Pass: growth

-- Logistic growth, suppressed by isolation and kill pressure
local function growthPass(list)
    if ZNodes.campaign.status ~= 'running' or ZNodes.campaign.victory then return end

    local headroom = 1.0 - ZNodes.campaign.totalPopulation / ZNodes.campaign.globalCap
    if headroom <= 0 then return end

    local ratePerSecond = math.log(2) / (S.weeksToDouble * 7 * 24 * 3600)
    local multiplier = ZNodes.campaign.settings.growthMultiplier or 1.0
    local seconds = S.growthMs / 1000
    local totalBirths = 0

    for _, node in pairs(ZNodes.nodes) do
        local room = ZNodes.campaign.globalCap - ZNodes.campaign.totalPopulation - totalBirths
        if room <= 0 then break end

        local distanceFactor = 1.0
        if #list > 0 then
            distanceFactor = clamp(math.sqrt(nearestPlayerDistance2(node, list)) / 1500.0, 0, 1)
        end

        local key = spatialKey(node.x, node.y, S.memoryCellSize)
        local memory = ZNodes.spatialMemory[key]

        local elapsedHours = 72.0
        if memory and memory.lastObserved then
            elapsedHours = math.max(0, ZNodes.campaign.simTimeMs - memory.lastObserved) / 3600000
        end

        local isolation = clamp(elapsedHours / 24.0, 0, 1) * distanceFactor
        local density = point(node.homeAtlas).d / 12.0
        -- Use killPressureOf, not memory.killPressure, so the lazy decay is applied.
        local clearing = memory and (1.0 / (1.0 + killPressureOf(memory))) or 1.0

        local exact = node.population * ratePerSecond * seconds
            * multiplier * headroom * isolation * (0.35 + density) * clearing

        local births = math.floor(exact)
        local remainder = exact - births

        local state, roll = randomRange(node.rngState, 0, 1)
        node.rngState = state
        if roll < remainder then births = births + 1 end

        births = math.min(births, room)
        if births > 0 then
            node.population = node.population + births
            node.radius = radiusFor(node.population, node.traits.spread)
            node.dirty = true
            totalBirths = totalBirths + births
        end
    end

    ZNodes.campaign.totalPopulation = ZNodes.campaign.totalPopulation + totalBirths
    ZNodes.stats.births = ZNodes.stats.births + totalBirths
end

-- Persistence
-- Declared above ZNodes.Init because Init calls SaveNow for a new campaign

-- Snapshot the dirty set. Synchronous, so it captures one consistent instant.
-- @return table payload, table savedNodes, table savedMemory (the latter two let a failed write restore the flags)
local function buildSavePayload()
    local payload = {
        campaign = ZNodesDB.CampaignValues(ZNodes.campaign, ZNodes.nextNodeId),
        nodes = {},
        memory = {},
        deleted = ZNodes.deletedIds,
    }

    -- The deletion list is taken, not copied: the payload owns it and the simulation starts a fresh one
    ZNodes.deletedIds = {}
    ZNodes.deletedSet = {}

    local savedNodes, savedMemory = {}, {}

    for _, node in pairs(ZNodes.nodes) do
        if node.dirty then
            payload.nodes[#payload.nodes + 1] = ZNodesDB.NodeValues(node)
            node.dirty = false
            savedNodes[#savedNodes + 1] = node
        end
    end

    for key, memory in pairs(ZNodes.spatialMemory) do
        if memory.dirty then
            payload.memory[#payload.memory + 1] = ZNodesDB.MemoryValues(key, memory)
            memory.dirty = false
            savedMemory[#savedMemory + 1] = memory
        end
    end

    return payload, savedNodes, savedMemory
end

-- Write the world
-- @param reason string for the console line and /znodes
-- @return boolean ok, table counts
function ZNodes.SaveNow(reason)
    if not ZNodes.ready or not ZNodes.persistence.enabled then return false, nil end

    -- Re-entrancy guard: a second save during a running one would find the dirty set already cleared and write nothing
    if ZNodes.persistence.saving then return false, nil end
    ZNodes.persistence.saving = true

    local payload, savedNodes, savedMemory = buildSavePayload()
    local ok, counts = ZNodesDB.Save(payload)

    if ok then
        ZNodes.persistence.saves = ZNodes.persistence.saves + 1
        ZNodes.persistence.lastSaveSimMs = ZNodes.campaign.simTimeMs
        ZNodes.persistence.lastSaveRealMs = GetGameTimer()
        ZNodes.persistence.lastCounts = counts
    else
        -- Put the dirty flags back so a failed write is retried on the next save.
        ZNodes.persistence.failures = ZNodes.persistence.failures + 1
        for index = 1, #savedNodes do savedNodes[index].dirty = true end
        for index = 1, #savedMemory do savedMemory[index].dirty = true end
        for index = 1, #payload.deleted do
            local id = payload.deleted[index]
            if not ZNodes.deletedSet[id] then
                ZNodes.deletedSet[id] = true
                ZNodes.deletedIds[#ZNodes.deletedIds + 1] = id
            end
        end
        print(('^1[BS NODES]^7 save failed (%s): %s')
            :format(tostring(reason), tostring(ZNodesDB.lastError)))
    end

    ZNodes.persistence.saving = false
    return ok, counts
end

-- Campaign seeding

-- Population is dealt out so it always sums exactly to initialPopulation
local function seedCampaign(seedPopulation, seed)
    ZNodes.nodes = {}
    ZNodes.nextNodeId = 1

    local remaining = seedPopulation
    local state = seed

    for index = 1, S.initialNodeCount do
        local atlasIndex
        state, atlasIndex = chooseWeightedPoint(state)

        local base = math.floor(remaining / (S.initialNodeCount - index + 1))
        local variance
        state, variance = randomRange(state, 0.40, 1.60)

        local population
        if index == S.initialNodeCount then
            population = remaining
        else
            population = math.max(1, math.min(remaining, math.floor(base * variance)))
        end
        remaining = remaining - population

        -- true = spread along an edge. Only the seeder passes it (see newNode).
        local node = newNode(ZNodes.nextNodeId, population, atlasIndex, state, nil, true)
        state = node.rngState
        ZNodes.nodes[node.id] = node
        ZNodes.nextNodeId = ZNodes.nextNodeId + 1
    end
end

-- Creates a brand new world
-- @param keepMemory table|nil spatial memory carried over from a campaign that could not be loaded. It is keyed by world coordinates, so it stays valid after an atlas re-survey.
local function newCampaign(keepMemory)
    local seed = (os.time() % 2147483646) + 1

    ZNodes.campaign = {
        id = 1,
        seed = seed,
        simTimeMs = 0,
        status = 'running',
        victory = false,
        totalPopulation = S.initialPopulation,
        globalCap = S.globalPopulationCap,
        atlasVersion = ZAtlas.version,
        settings = {
            emptyServerSpeed = S.emptyServerSpeed,
            growthMultiplier = 1.0,
        },
    }

    seedCampaign(S.initialPopulation, seed)

    ZNodes.spatialMemory = keepMemory or {}
    -- Carried-over cells are marked dirty: their pressureAtMs was measured against the old campaign clock, which is now zero
    for _, memory in pairs(ZNodes.spatialMemory) do
        memory.pressureAtMs = 0
        memory.dirty = true
    end
end

-- Boot
function ZNodes.Init()
    -- The graph is checked at boot. Unreachable waypoints drain herds silently.
    ZNodes.atlasProblems = (ZAtlas.Validate and ZAtlas.Validate()) or {}
    if #ZNodes.atlasProblems > 0 then
        print(('^1[BS NODES]^7 THE ATLAS GRAPH HAS %d PROBLEM(S) - herds will migrate badly:')
            :format(#ZNodes.atlasProblems))
        for _, line in ipairs(ZNodes.atlasProblems) do
            print('^1[BS NODES]^7   ' .. line)
        end
        print('^1[BS NODES]^7 fix config/config_atlas.lua; every edge must be listed on BOTH points.')
    end

    ZNodes.persistence.enabled = P.enabled and true or false

    if not ZNodes.persistence.enabled then
        newCampaign(nil)
        ZNodes.ready = true
        print('^3[BS NODES]^7 persistence DISABLED in config - this world dies with the resource')
        return
    end

    -- Schema probe: bs_core's migration runner uses a hardcoded list
    if not ZNodesDB.SchemaReady() then
        ZNodes.persistence.enabled = false
        newCampaign(nil)
        ZNodes.ready = true
        print('^1[BS NODES]^7 bs_zombie_campaign is missing - running IN MEMORY ONLY.')
        print('^1[BS NODES]^7 check that 018_zombie_nodes.sql is listed in bs_core/server/sv_migrations.lua M.files')
        return
    end

    local loaded = ZNodesDB.Load()

    if loaded and loaded.atlasMismatch then
        print(('^1[BS NODES]^7 saved campaign is atlas v%d, config is v%d - RESEEDING the world.')
            :format(loaded.campaign.atlasVersion, ZAtlas.version))
        print('^1[BS NODES]^7 stored waypoint indices mean different places now; spatial memory is kept.')
        ZNodesDB.WipeNodes()
        newCampaign(loaded.memory)
        loaded = nil
    end

    if loaded then
        ZNodes.campaign = loaded.campaign
        ZNodes.nodes = loaded.nodes
        ZNodes.spatialMemory = loaded.memory
        ZNodes.nextNodeId = loaded.nextNodeId
        ZNodes.persistence.loadedFromDb = true
        ZNodes.ready = true
        return
    end

    if not ZNodes.persistence.loadedFromDb and not ZNodes.campaign then
        newCampaign(nil)
    end
    ZNodes.ready = true

    -- A new world is written immediately
    ZNodes.SaveNow('first save (new campaign)')
end

-- Tick

--- @param realDt number real seconds since the last tick
function ZNodes.Tick(realDt)
    if not ZNodes.ready then return end
    if ZNodes.campaign.status ~= 'running' or ZNodes.campaign.victory then return end

    local list = playerList()

    -- Empty-server slowdown scales sim time, not the loop rate, so herds still move a little for an admin watching
    local speed = (#list == 0) and (ZNodes.campaign.settings.emptyServerSpeed or 0.1) or 1.0
    local dt = realDt * speed

    ZNodes.campaign.simTimeMs = ZNodes.campaign.simTimeMs + math.floor(dt * 1000)

    observePlayers(list)

    local count = tableCount(ZNodes.nodes)
    local speedSum = 0

    for _, node in pairs(ZNodes.nodes) do
        node.updatedSimMs = ZNodes.campaign.simTimeMs
        speedSum = speedSum + moveNode(node, dt)
        maybeSplit(node, count, dt)
    end

    ZNodes.lastMeanSpeed = count > 0 and (speedSum / count) or 0.0
end

-- Queries and mutators
-- The surface later stages will call. Nothing calls them yet.

-- Herds within radius of a point, nearest first.
function ZNodes.Nearby(coords, radius)
    local result, radius2 = {}, radius * radius
    for _, node in pairs(ZNodes.nodes) do
        if distance2(node, coords) <= radius2 then result[#result + 1] = node end
    end
    table.sort(result, function(a, b) return distance2(a, coords) < distance2(b, coords) end)
    return result
end

function ZNodes.Get(id) return ZNodes.nodes[tonumber(id) or -1] end

-- Will take bs:world:noise (kind, radius and position already validated server-side). noiseResponse scales how long each herd cares.
function ZNodes.ApplyNoise(coords, radius, kind)
    if not ZNodes.ready then return 0 end
    local affected = ZNodes.Nearby(coords, radius)
    for i = 1, #affected do
        local node = affected[i]
        node.alert = {
            x = coords.x, y = coords.y, z = coords.z, kind = kind,
            expires = ZNodes.campaign.simTimeMs + math.floor(S.alertMs * node.traits.noiseResponse),
        }
        node.intent = 'stimulus'
        node.dirty = true
    end
    return #affected
end

-- One zombie died
function ZNodes.RecordDeath(nodeId, coords)
    local node = ZNodes.nodes[tonumber(nodeId) or -1]
    if not node or node.population <= 0 then return false end

    node.population = node.population - 1
    ZNodes.campaign.totalPopulation = math.max(0, ZNodes.campaign.totalPopulation - 1)
    ZNodes.stats.deaths = ZNodes.stats.deaths + 1
    node.dirty = true

    local memory = memoryAt(coords.x, coords.y)
    -- Decay first, then add, so pressure that was already forgotten is not credited.
    memory.killPressure = math.min(100, killPressureOf(memory) + 0.05)
    memory.pressureAtMs = ZNodes.campaign.simTimeMs
    memory.lastObserved = ZNodes.campaign.simTimeMs
    memory.dirty = true

    if node.population <= 0 then
        -- The herd is gone, so its row goes too.
        forgetNode(node.id)
    else
        node.radius = radiusFor(node.population, node.traits.spread)
    end

    return true
end

function ZNodes.Snapshot()
    return {
        ready = ZNodes.ready,
        status = ZNodes.campaign and ZNodes.campaign.status or 'loading',
        campaignId = ZNodes.campaign and ZNodes.campaign.id or 0,
        totalPopulation = ZNodes.campaign and ZNodes.campaign.totalPopulation or 0,
        globalCap = ZNodes.campaign and ZNodes.campaign.globalCap or 0,
        simTimeMs = ZNodes.campaign and ZNodes.campaign.simTimeMs or 0,
        nodeCount = tableCount(ZNodes.nodes),
        -- Included in the snapshot so the Node Atlas panel can show a broken graph.
        atlasVersion = ZAtlas.version,
        atlasProblems = ZNodes.atlasProblems or {},
        memoryCells = tableCount(ZNodes.spatialMemory),
        meanSpeed = ZNodes.lastMeanSpeed,
        stats = ZNodes.stats,
        -- Persistence status rides in the same snapshot as the world.
        persistence = {
            enabled = ZNodes.persistence.enabled,
            loadedFromDb = ZNodes.persistence.loadedFromDb,
            saves = ZNodes.persistence.saves,
            failures = ZNodes.persistence.failures,
            lastSaveSimMs = ZNodes.persistence.lastSaveSimMs,
            lastSaveRealMs = ZNodes.persistence.lastSaveRealMs,
            lastCounts = ZNodes.persistence.lastCounts,
            pendingNodes = ZNodes.PendingNodeCount(),
            pendingDeletes = #ZNodes.deletedIds,
            lastError = ZNodesDB and ZNodesDB.lastError or nil,
        },
    }
end

-- Dirty nodes waiting for the next sweep. O(nodes), only used by the readout.
function ZNodes.PendingNodeCount()
    local count = 0
    for _, node in pairs(ZNodes.nodes) do
        if node.dirty then count = count + 1 end
    end
    return count
end

-- Loops
-- Three timers because the passes have different costs and rates

CreateThread(function()
    ZNodes.Init()

    -- Separate wording for "resumed" and "seeded" so they are easy to tell apart in the console.
    if ZNodes.persistence.loadedFromDb then
        print(('^5[BS NODES]^7 campaign RESUMED from database: %d nodes, %s zombies, sim clock at %.1f h')
            :format(tableCount(ZNodes.nodes), tostring(ZNodes.campaign.totalPopulation),
                    ZNodes.campaign.simTimeMs / 3600000))
        print('^5[BS NODES]^7 sim time was restored as saved - downtime advanced nothing. /znodes to look.')
    else
        print(('^5[BS NODES]^7 NEW campaign seeded: %d nodes, %s zombies (Stage 2 - nothing consumes this yet, /znodes to look)')
            :format(tableCount(ZNodes.nodes), tostring(ZNodes.campaign.totalPopulation)))
    end

    local last = GetGameTimer()
    while true do
        Wait(S.tickMs)
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now
        ZNodes.Tick(dt)
    end
end)

CreateThread(function()
    while true do
        Wait(S.mergeMs)
        if ZNodes.ready then mergePass() end
    end
end)

CreateThread(function()
    while true do
        Wait(S.growthMs)
        if ZNodes.ready then growthPass(playerList()) end
    end
end)

-- Save loop on its own thread: SaveNow yields on every database call
CreateThread(function()
    while true do
        Wait(P.saveMs)
        if ZNodes.ready and ZNodes.persistence.enabled then
            ZNodes.SaveNow('periodic')
        end
    end
end)

-- Best-effort save on shutdown
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if not ZNodes.ready or not ZNodes.persistence.enabled then return end
    ZNodes.SaveNow('resource stopping')
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    if not ZNodes.ready or not ZNodes.persistence.enabled then return end
    ZNodes.SaveNow('server shutting down')
end)

-- Diagnostics

-- Nearest atlas waypoint to a herd, for the readout. O(points).
local function nearestPointName(node)
    local best, bestDistance = nil, math.huge
    for index = 1, #ZAtlas.points do
        local d = distance2(node, ZAtlas.points[index])
        if d < bestDistance then best, bestDistance = index, d end
    end
    return best and ZAtlas.points[best].id or '?', math.sqrt(bestDistance)
end

-- /znodes - population readout

local function nodesEmitTo(src, line)
    if src == 0 then print(line) else
        TriggerClientEvent('chat:addMessage', src, { args = { line } })
    end
end

local function nodesStaffGate(src, what)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'bs.admin') then return true end
    if GetResourceState('bs_admin') == 'started' then
        local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and admin == true then return true end
    end
    nodesEmitTo(src, ('^1[%s]^7 refused - this needs the `bs.admin` ace or staff in bs_admin.'):format(what))
    nodesEmitTo(src, '   (this message means the command EXISTS and the resource is running)')
    return false
end

RegisterCommand('znodes', function(src)
    if not nodesStaffGate(src, 'BS NODES') then return end

    local function emit(line) nodesEmitTo(src, line) end

    if not ZNodes.ready then
        emit('^5[BS NODES]^7 not seeded yet')
        return
    end

    local snap = ZNodes.Snapshot()

    emit(('^5[BS NODES]^7 %d nodes | pop %d / %d | sim %.1f h | %s')
        :format(snap.nodeCount, snap.totalPopulation, snap.globalCap,
                snap.simTimeMs / 3600000, snap.status))

    emit(('   births %d  deaths %d  splits %d  merges %d  | mean speed %.3f m/s-sim | %d memory cells')
        :format(snap.stats.births, snap.stats.deaths, snap.stats.splits,
                snap.stats.merges, snap.meanSpeed, snap.memoryCells))

    -- Atlas line: one line when healthy, loud when the graph is broken
    local problems = snap.atlasProblems or {}
    if #problems == 0 then
        emit(('   atlas v%d: %d waypoints, graph symmetric and fully connected')
            :format(snap.atlasVersion or 0, #(ZAtlas.points or {})))
    else
        emit(('   ^1atlas v%d: %d PROBLEM(S) - herds will migrate badly^7')
            :format(snap.atlasVersion or 0, #problems))
        for i = 1, math.min(#problems, 6) do
            emit('     ^1' .. problems[i] .. '^7')
        end
        if #problems > 6 then
            emit(('     ...and %d more (full list is in the server console at boot)')
                :format(#problems - 6))
        end
    end

    -- Persistence line: answers whether the world is being written
    local pers = snap.persistence
    if not pers.enabled then
        emit('   ^3persistence OFF^7 - this world dies with the resource')
    else
        emit(('   persistence: %s | %d saves, %d failed | last wrote %d nodes / %d cells / %d deletes')
            :format(pers.loadedFromDb and 'resumed from db' or 'new campaign',
                    pers.saves, pers.failures,
                    pers.lastCounts.nodes or 0, pers.lastCounts.memory or 0,
                    pers.lastCounts.deleted or 0))
        emit(('   pending: %d dirty nodes, %d queued deletes | last save at sim %.2f h (%s)')
            :format(pers.pendingNodes, pers.pendingDeletes,
                    (pers.lastSaveSimMs >= 0) and (pers.lastSaveSimMs / 3600000) or 0,
                    (pers.lastSaveRealMs > 0)
                        and (('%.0fs ago'):format((GetGameTimer() - pers.lastSaveRealMs) / 1000))
                        or 'never'))
        if pers.lastError then
            emit(('   ^1last database error:^7 %s'):format(tostring(pers.lastError)))
        end
    end

    -- Top herds by population (sorts a copy).
    local list = {}
    for _, node in pairs(ZNodes.nodes) do list[#list + 1] = node end
    table.sort(list, function(a, b) return a.population > b.population end)

    local shown = math.min(5, #list)
    for i = 1, shown do
        local node = list[i]
        local name, distance = nearestPointName(node)
        emit(('   #%-5d %7d  %-15s -> %-15s  near %s (%.0fm)%s')
            :format(node.id, node.population, node.intent,
                    point(node.targetAtlas).id, name, distance,
                    node.alert and '  [ALERT]' or ''))
    end
end, false)

-- /znodesave - force a save and print the row counts written
RegisterCommand('znodesave', function(src)
    if not nodesStaffGate(src, 'BS NODES') then return end

    local function emit(line)
        if src == 0 then
            print(line)
        else
            TriggerClientEvent('chat:addMessage', src, { args = { line } })
        end
    end

    if not ZNodes.ready then
        emit('^5[BS NODES]^7 not seeded yet')
        return
    end

    if not ZNodes.persistence.enabled then
        emit('^3[BS NODES]^7 persistence is OFF (schema missing, or disabled in config_atlas.lua)')
        return
    end

    local pending = ZNodes.PendingNodeCount()
    local queued = #ZNodes.deletedIds

    -- SaveNow yields, so it gets its own thread like the save loop.
    CreateThread(function()
        local ok, counts = ZNodes.SaveNow('manual /znodesave')

        if not ok then
            if ZNodes.persistence.saving then
                emit('^3[BS NODES]^7 a save was already running - nothing written, try again in a moment')
            else
                emit(('^1[BS NODES]^7 save FAILED: %s'):format(tostring(ZNodesDB.lastError)))
            end
            return
        end

        emit(('^5[BS NODES]^7 saved: %d node rows, %d memory cells, %d deletions (%d nodes and %d deletes were pending)')
            :format(counts.nodes, counts.memory, counts.deleted, pending, queued))
        emit(('   campaign row now holds sim %.2f h, population %d, %d nodes in memory')
            :format(ZNodes.campaign.simTimeMs / 3600000, ZNodes.campaign.totalPopulation,
                    tableCount(ZNodes.nodes)))
        emit('   verify from the other side: SELECT COUNT(*) FROM bs_zombie_nodes;')
    end)
end, false)

-- Exports for the visualiser

exports('NodeSnapshot', function() return ZNodes.Snapshot() end)

-- Every herd, flattened for drawing: position, size, behaviour and traits. rngState and dirty are left out.
exports('NodeList', function()
    local out = {}
    for _, node in pairs(ZNodes.nodes) do
        local t = node.traits or {}
        out[#out + 1] = {
            id = node.id,
            x = math.floor(node.x * 10) / 10,
            y = math.floor(node.y * 10) / 10,
            z = math.floor((node.z or 0) * 10) / 10,
            population = node.population,
            radius = math.floor(node.radius or 0),
            intent = node.intent,
            homeAtlas = node.homeAtlas,
            targetAtlas = node.targetAtlas,
            -- The alert is carried whole so the panel can draw a line from herd to noise.
            alert = node.alert and {
                x = node.alert.x, y = node.alert.y,
                kind = node.alert.kind, expires = node.alert.expires,
            } or nil,
            traits = {
                cohesion = t.cohesion, migration = t.migration,
                aggression = t.aggression, noiseResponse = t.noiseResponse,
                spread = t.spread, splitImpulse = t.splitImpulse,
                behavior = t.behavior,
            },
        }
    end
    return out
end)

-- The atlas graph, so the panel can draw roads
exports('NodeAtlas', function()
    local points, edges, seen = {}, {}, {}

    for index, p in ipairs(ZAtlas.points) do
        points[#points + 1] = {
            index = index, id = p.id, x = p.x, y = p.y, z = p.z,
            density = p.d, kind = p.t,
        }

        for _, other in ipairs(p.n or {}) do
            local a, b = math.min(index, other), math.max(index, other)
            local key = a .. ':' .. b
            if not seen[key] and ZAtlas.points[b] then
                seen[key] = true
                edges[#edges + 1] = { a = a, b = b }
            end
        end
    end

    return { version = ZAtlas.version, bounds = ZAtlas.bounds,
             points = points, edges = edges }
end)

-- Spatial memory as cells worth colouring (visits and kills). Empty cells are skipped.
exports('NodeMemory', function()
    local out = {}
    local size = (ZAtlas.Simulation and ZAtlas.Simulation.memoryCellSize) or 250.0

    for _, cell in pairs(ZNodes.spatialMemory) do
        local pressure = killPressureOf(cell)
        local heat = cell.visitHeat or 0
        if pressure > 0.01 or heat > 0.01 then
            out[#out + 1] = {
                x = cell.x, y = cell.y, size = size,
                killPressure = math.floor(pressure * 100) / 100,
                visitHeat = math.floor(heat * 100) / 100,
            }
        end
    end
    return out
end)
