-- bs_zombies - where candidate spawn points come from

ZSpawnSrc = {}

local function cfg()
    return (Zombies and Zombies.Spawn) or {}
end

function ZSpawnSrc.Ready()
    return ZSpawnSrc.Mode() == 'local' or (ZSim and ZSim.ready) == true
end

function ZSpawnSrc.Mode()
    local m = cfg().mode
    return (m == 'local') and 'local' or 'simulation'
end

-- DENSITY

-- The map is graded by config_zones.lua (per-zone density multiplier, also read by sv_registry), so there is no second grading here
local function zoneDensityAt(x, y)
    local best
    for _, zone in ipairs((Zones and Zones.Spawn) or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
            if not best or (zone.density or 1.0) > (best.density or 1.0) then
                best = zone
            end
        end
    end
    return best and (best.density or 1.0) or 0.6
end

-- Target walker count for a cluster
function ZSpawnSrc.DensityFor(cluster)
    local d = cfg().density or {}
    local base = d.base or 25
    local mult = zoneDensityAt(cluster.x or 0.0, cluster.y or 0.0)

    local members = math.max(1, #(cluster.members or { 1 }))
    local perPlayer = math.floor(base * mult + 0.5)

    local want = (d.perPlayer ~= false) and (perPlayer * members) or perPlayer

    local cap = d.clusterCap or 90
    if want > cap then want = cap end

    local floor_ = (d.minPerPlayer or 8) * members
    if want < floor_ then want = math.min(floor_, cap) end

    return want, mult, perPlayer
end

-- LOCAL MODE: SYNTHETIC NODES

-- Ephemeral points on a ring around the cluster, regenerated every plan
local synthetic = {}      -- [id] = node
local nextId = -1         -- negative so a synthetic id can never collide with
                          -- a simulation agent id, which is what record.nodeId carries and what ZNodes.RecordDeath is given

local SYNTH_TTL_MS = 15000

local function sweepSynthetic(now)
    for id, node in pairs(synthetic) do
        if now - (node.bornAt or 0) > SYNTH_TTL_MS then synthetic[id] = nil end
    end
end

local function makeSyntheticRing(cluster, radius, count)
    local now = GetGameTimer()
    sweepSynthetic(now)

    local out, n = {}, 0
    local cx, cy = cluster.x or 0.0, cluster.y or 0.0

    -- The bearing is offset per plan
    local jitter = (now % 3600) / 10.0

    for i = 0, count - 1 do
        local a = math.rad(jitter + (360.0 / count) * i)
        local r = radius * (0.85 + ((i * 37) % 30) / 100.0)

        nextId = nextId - 1
        local node = {
            id = nextId,
            x = cx + math.cos(a) * r,
            y = cy + math.sin(a) * r,
            z = cluster.z or 0.0,
            radius = 20.0,
            -- Enough that one plan does not exhaust a point, low enough that a single point cannot become a crowd
            population = 3,
            intent = 'wander',
            synthetic = true,
            bornAt = now,
        }

        synthetic[node.id] = node
        n = n + 1
        out[n] = node
    end

    return out
end

-- THE TWO CALLS THE PLANNER MAKES

-- Candidate sources near a cluster
function ZSpawnSrc.Nearby(cluster, radius)
    if ZSpawnSrc.Mode() == 'local' then
        -- Drawn on the spawn ring, not at radius, so offered points are already in the band the client may use
        local lo = (Streaming and Streaming.spawnMin) or 110.0
        local hi = (Streaming and Streaming.spawnMax) or 200.0
        return makeSyntheticRing(cluster, (lo + hi) / 2.0, 12)
    end

    local list = (ZNodes and ZNodes.Nearby) and ZNodes.Nearby(cluster, radius) or {}

    -- The countryside is thin, not empty
    local live = 0
    for _, node in ipairs(list) do
        if (node.population or 0) > 0 then live = live + 1 end
    end
    local want = cfg().wildsMinSources or 6
    if cfg().wildsFallback ~= false and live < want then
        local lo = (Streaming and Streaming.spawnMin) or 110.0
        local hi = (Streaming and Streaming.spawnMax) or 200.0
        for _, node in ipairs(makeSyntheticRing(cluster, (lo + hi) / 2.0, want - live)) do
            list[#list + 1] = node
        end
    end
    return list
end

-- Resolve a node the client has just reported against.
function ZSpawnSrc.Get(id)
    id = tonumber(id)
    if not id then return nil end

    -- Negative ids are synthetic by construction - see nextId.
    if id < 0 then
        local node = synthetic[id]
        if not node
           or GetGameTimer() - node.bornAt > SYNTH_TTL_MS then return nil end
        return node
    end
    if ZSpawnSrc.Mode() ~= 'simulation' then return nil end

    if ZNodes and ZNodes.Get then return ZNodes.Get(id) end
    return nil
end

-- /zmode - SWITCH LIVE, AND SHOW THE WORKING

RegisterCommand('zmode', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local function emit(line)
        if src == 0 then print(line)
        else TriggerClientEvent('chat:addMessage', src, { args = { 'BS', line } }) end
    end

    local wanted = tostring(args and args[1] or ''):lower()

    if wanted == 'local' or wanted == 'simulation' then
        Zombies.Spawn = Zombies.Spawn or {}
        Zombies.Spawn.mode = wanted
        emit(('^2[BS MODE]^7 spawn mode is now %s. Existing walkers are left alone; the change applies to the next plan.'):format(wanted))
        print(('^2[BS MODE]^7 spawn mode switched to %s by %s')
            :format(wanted, src == 0 and 'console' or (GetPlayerName(src) or src)))
        return
    end

    emit(('^5[BS MODE]^7 spawn mode: %s'):format(ZSpawnSrc.Mode()))
    emit('   /zmode simulation   the node model - memory, depletion, migration')
    emit('   /zmode local        a plain ring spawner, no simulation at all')

    local d = cfg().density or {}
    emit(('   density base %d, cluster cap %d, per player %s')
        :format(d.base or 25, d.clusterCap or 90,
                (d.perPlayer ~= false) and 'yes' or 'no'))

    local n = 0
    for _ in pairs(synthetic) do n = n + 1 end
    emit(('   %d synthetic node(s) alive'):format(n))
end, false)

exports('SpawnMode', function() return ZSpawnSrc.Mode() end)
exports('SetSpawnMode', function(mode)
    if mode ~= 'local' and mode ~= 'simulation' then return false end
    Zombies.Spawn = Zombies.Spawn or {}
    Zombies.Spawn.mode = mode
    return true
end)
