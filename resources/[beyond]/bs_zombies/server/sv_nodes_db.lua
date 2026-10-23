-- bs_zombies - node persistence. Adapted with permission from mrpz_zombies by Norway174 (server/persistence.lua); credited in docs/CREDITS.md. Not a licence to redistribute the original.
-- This is the only file in bs_zombies that knows column names (sv_nodes.lua decides what/when to save; the value builders NodeValues / MemoryValues live here). Schema lives in bs_core/sql/.
-- It talks to oxmysql directly (*_async only), not BS.DB, which is in another Lua state. Every call yields, so none may run from ZNodes.Tick or the merge/growth passes; sv_nodes.lua calls Save() from its own thread.
-- declare a local function before its first use, or it is a nil global at runtime.

local P = ZAtlas.Persistence

ZNodesDB = {}

-- Set true once a query has failed hard, so the readout can show it.
ZNodesDB.lastError = nil

-- Driver wrappers: thin and pcall'd

local function dbQuery(sql, params)
    local ok, result = pcall(function()
        return exports.oxmysql:query_async(sql, params or {})
    end)
    if not ok then
        ZNodesDB.lastError = tostring(result)
        print(('^1[BS NODES DB]^7 query failed: %s'):format(tostring(result)))
        return nil, result
    end
    return result
end

-- One statement, many parameter sets: oxmysql prepares once and executes per set, so a 1200-row sweep is one round trip
local function dbPrepare(sql, sets)
    if not sets or #sets == 0 then return true end
    local ok, result = pcall(function()
        return exports.oxmysql:prepare_async(sql, sets)
    end)
    if not ok then
        ZNodesDB.lastError = tostring(result)
        print(('^1[BS NODES DB]^7 write failed: %s'):format(tostring(result)))
        return false, result
    end
    return true, result
end

-- Statements
-- Upserts throughout: a node created since the last save has no row yet, and the dirty flag cannot tell new from existing

local CAMPAIGN_UPSERT = [[
    INSERT INTO `bs_zombie_campaign`
        (`id`, `seed`, `sim_time_ms`, `status`, `victory`, `total_population`,
         `global_cap`, `settings`, `atlas_version`)
    VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        `seed` = VALUES(`seed`),
        `sim_time_ms` = VALUES(`sim_time_ms`),
        `status` = VALUES(`status`),
        `victory` = VALUES(`victory`),
        `total_population` = VALUES(`total_population`),
        `global_cap` = VALUES(`global_cap`),
        `settings` = VALUES(`settings`),
        `atlas_version` = VALUES(`atlas_version`)
]]

local NODE_UPSERT = [[
    INSERT INTO `bs_zombie_nodes`
        (`id`, `population`, `x`, `y`, `z`, `radius`, `rng_state`,
         `home_atlas`, `target_atlas`, `intent`, `traits`, `alert`, `updated_sim_ms`)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        `population` = VALUES(`population`),
        `x` = VALUES(`x`), `y` = VALUES(`y`), `z` = VALUES(`z`),
        `radius` = VALUES(`radius`),
        `rng_state` = VALUES(`rng_state`),
        `home_atlas` = VALUES(`home_atlas`),
        `target_atlas` = VALUES(`target_atlas`),
        `intent` = VALUES(`intent`),
        `traits` = VALUES(`traits`),
        `alert` = VALUES(`alert`),
        `updated_sim_ms` = VALUES(`updated_sim_ms`)
]]

local MEMORY_UPSERT = [[
    INSERT INTO `bs_zombie_spatial_memory`
        (`spatial_key`, `x`, `y`, `last_observed_sim_ms`, `visit_heat`,
         `kill_pressure`, `pressure_at_sim_ms`)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        `x` = VALUES(`x`), `y` = VALUES(`y`),
        `last_observed_sim_ms` = VALUES(`last_observed_sim_ms`),
        `visit_heat` = VALUES(`visit_heat`),
        `kill_pressure` = VALUES(`kill_pressure`),
        `pressure_at_sim_ms` = VALUES(`pressure_at_sim_ms`)
]]

local NODE_DELETE = 'DELETE FROM `bs_zombie_nodes` WHERE `id` = ?'

-- Row builders
-- Called synchronously by sv_nodes.lua before the save thread starts

--- @return table parameter set for NODE_UPSERT
function ZNodesDB.NodeValues(node)
    return {
        node.id,
        math.floor(node.population),
        node.x, node.y, node.z,
        node.radius,
        -- The Lehmer state is the herd's future
        math.floor(node.rngState),
        node.homeAtlas,
        node.targetAtlas,
        node.intent or 'wanderer',
        json.encode(node.traits),
        -- '' instead of nil (see the no-NULLs note in 018_zombie_nodes.sql); nil would shorten this array and shift later columns
        node.alert and json.encode(node.alert) or '',
        math.floor(node.updatedSimMs or 0),
    }
end

--- @return table parameter set for MEMORY_UPSERT
function ZNodesDB.MemoryValues(key, memory)
    return {
        key,
        memory.x, memory.y,
        -- -1 is "never observed". Not 0, which is a real sim time.
        memory.lastObserved or -1,
        memory.visitHeat or 0.0,
        memory.killPressure or 0.0,
        memory.pressureAtMs or 0,
    }
end

function ZNodesDB.CampaignValues(campaign, nextNodeId)
    -- nextNodeId is stored inside settings to avoid another column
    local settings = {}
    for key, value in pairs(campaign.settings or {}) do settings[key] = value end
    settings.nextNodeId = nextNodeId

    return {
        math.floor(campaign.seed),
        math.floor(campaign.simTimeMs),
        campaign.status or 'running',
        campaign.victory and 1 or 0,
        math.floor(campaign.totalPopulation),
        math.floor(campaign.globalCap),
        json.encode(settings),
        campaign.atlasVersion or 1,
    }
end

-- Decode helpers

-- The driver returns LONGTEXT as a string, but JSON columns on some builds come back already decoded
local function decodeJson(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if not ok or type(decoded) ~= 'table' then return fallback end
    return decoded
end

-- Load. Yields: call from a thread, once, before the simulation ticks.
-- @return nil  no campaign row - caller seeds a new world
-- @return table  { campaign, nodes, memory, nextNodeId, atlasMismatch }

function ZNodesDB.Load()
    if not P.enabled then return nil end

    local rows = dbQuery('SELECT * FROM `bs_zombie_campaign` WHERE `id` = 1 LIMIT 1')
    if not rows or #rows == 0 then return nil end
    local row = rows[1]

    local settings = decodeJson(row.settings, {})
    local nextNodeId = tonumber(settings.nextNodeId) or 1
    settings.nextNodeId = nil

    local campaign = {
        id = 1,
        seed = tonumber(row.seed) or 1,
        -- sim_time_ms is taken verbatim from the row, not offset by downtime
        simTimeMs = tonumber(row.sim_time_ms) or 0,
        status = row.status or 'running',
        victory = row.victory == true or (tonumber(row.victory) or 0) ~= 0,
        totalPopulation = tonumber(row.total_population) or 0,
        globalCap = tonumber(row.global_cap) or 0,
        atlasVersion = tonumber(row.atlas_version) or 1,
        settings = settings,
    }

    -- Atlas version guard: home_atlas and target_atlas index into ZAtlas.points
    local mismatch = campaign.atlasVersion ~= ZAtlas.version

    local nodes, memory = {}, {}
    local maxId = 0

    for _, r in ipairs(dbQuery('SELECT * FROM `bs_zombie_nodes`') or {}) do
        local id = tonumber(r.id) or 0
        if id > 0 then
            local traits = decodeJson(r.traits, nil)
            -- A node whose traits failed to decode has no safe default
            if traits then
                nodes[id] = {
                    id = id,
                    population = tonumber(r.population) or 0,
                    x = tonumber(r.x) or 0.0,
                    y = tonumber(r.y) or 0.0,
                    z = tonumber(r.z) or 0.0,
                    radius = tonumber(r.radius) or 20.0,
                    rngState = tonumber(r.rng_state) or 1,
                    homeAtlas = tonumber(r.home_atlas) or 1,
                    targetAtlas = tonumber(r.target_atlas) or 1,
                    intent = r.intent or 'wanderer',
                    traits = traits,
                    alert = decodeJson(r.alert, nil),
                    updatedSimMs = tonumber(r.updated_sim_ms) or 0,
                    -- Loaded rows are already in the database
                    dirty = false,
                }
                if id > maxId then maxId = id end
            else
                print(('^3[BS NODES DB]^7 node %d dropped: traits did not decode'):format(id))
            end
        end
    end

    for _, r in ipairs(dbQuery('SELECT * FROM `bs_zombie_spatial_memory`') or {}) do
        local key = r.spatial_key
        if type(key) == 'string' and key ~= '' then
            local observed = tonumber(r.last_observed_sim_ms) or -1
            memory[key] = {
                x = tonumber(r.x) or 0.0,
                y = tonumber(r.y) or 0.0,
                -- -1 back to nil: the growth pass treats nil lastObserved as 'never visited' (72 hours idle). 0
                lastObserved = (observed >= 0) and observed or nil,
                visitHeat = tonumber(r.visit_heat) or 0.0,
                killPressure = tonumber(r.kill_pressure) or 0.0,
                pressureAtMs = tonumber(r.pressure_at_sim_ms) or 0,
                dirty = false,
            }
        end
    end

    return {
        campaign = campaign,
        nodes = nodes,
        memory = memory,
        nextNodeId = math.max(nextNodeId, maxId + 1),
        atlasMismatch = mismatch,
    }
end

-- Save. Yields: call from the save thread only.
-- @param payload { campaign, nextNodeId, nodes = {values...},
--                  memory = {values...}, deleted = {ids...} }
-- @return boolean ok, table counts

-- Split a set list into chunks so one save is not a single huge batch (worst case: a 1200-node first save after a reseed)
local function chunked(sets, size, run)
    local total = #sets
    local first = 1
    while first <= total do
        local batch = {}
        local last = math.min(first + size - 1, total)
        for index = first, last do batch[#batch + 1] = sets[index] end
        if not run(batch) then return false end
        first = last + 1
    end
    return true
end

function ZNodesDB.Save(payload)
    if not P.enabled then return false, { skipped = true } end

    local counts = { nodes = #payload.nodes, memory = #payload.memory, deleted = #payload.deleted }

    -- Deletes go first and are required
    local ok = chunked(payload.deleted, P.batchSize, function(batch)
        local sets = {}
        for index = 1, #batch do sets[index] = { batch[index] } end
        return (dbPrepare(NODE_DELETE, sets))
    end)
    if not ok then return false, counts end

    ok = chunked(payload.nodes, P.batchSize, function(batch)
        return (dbPrepare(NODE_UPSERT, batch))
    end)
    if not ok then return false, counts end

    ok = chunked(payload.memory, P.batchSize, function(batch)
        return (dbPrepare(MEMORY_UPSERT, batch))
    end)
    if not ok then return false, counts end

    -- The campaign row is written last
    if not dbPrepare(CAMPAIGN_UPSERT, { payload.campaign }) then
        return false, counts
    end

    ZNodesDB.lastError = nil
    return true, counts
end

-- True once the schema is present, so boot can report un-run migrations clearly instead of failing in the first SELECT
function ZNodesDB.SchemaReady()
    local rows = dbQuery("SHOW TABLES LIKE 'bs_zombie_campaign'")
    return rows ~= nil and #rows > 0
end

-- Removes every node row
function ZNodesDB.WipeNodes()
    return dbQuery('DELETE FROM `bs_zombie_nodes`') ~= nil
end
