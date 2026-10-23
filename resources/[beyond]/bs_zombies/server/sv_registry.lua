-- bs_zombies - server registry of all walkers

Registry = {
    zombies   = {},    -- [id] = record
    byCell    = {},
    cellDead  = {},    -- [cellKey] = os.time when it may repopulate
    liveGrid  = {},    -- [liveKey] = { [id] = true }, current position
    nextId    = 1,
    seed      = 0,
    hostOf    = {},    -- [src] = { [id] = true }
    -- Short recycled label for staff debug, separate from the permanent record id used on the wire.
    debugIds  = { next = 1, free = {} },
    hordeBonus = {},   -- [src] = { startsAt, until_, extra } - set by sv_director
}

local S = Zombies.Settings
local CELL = S.cellSize

-- Record ids are permanent and never reused
local function acquireDebugId()
    local pool = Registry.debugIds
    local id = table.remove(pool.free)
    if id then return id end
    id = pool.next
    pool.next = id + 1
    return id
end

local function releaseDebugId(id)
    if type(id) == 'number' and id > 0 then
        Registry.debugIds.free[#Registry.debugIds.free + 1] = id
    end
end

-- Server-only tuning.
local HOST_RADIUS     = math.max(180.0, Streaming.fullDistance or 280.0, (Streaming.spawnMax or 200.0) + ((Sim and Sim.spawn and Sim.spawn.openPushMax) or 0.0) + 30.0)    -- a host has to be near enough to simulate it
local STREAM_RADIUS   = HOST_RADIUS + 30.0    -- who receives updates about it
local TICK            = 400      -- ms between broadcast passes
local DIRECTOR_TICK   = 1200     -- ms between spawn passes
-- World-wide ceiling. Only a backstop; the per-player ceiling is what protects a client.
local MAX_TOTAL       = math.min(Streaming.globalHard or 200, (Streaming.PoolGuard or {}).maxNetworked or 96) -- same policy for staff/legacy paths
-- states where a walker is engaging a player; never snap these
local COMBAT_STATES = { hunting = true, grab = true, drawn = true, disturbed = true, attacking = true }
local MAX_PER_PLAYER  = 34       -- how many may exist around one player
local CELL_RESPAWN    = 1800     -- seconds before a cleared cell repopulates
local MAX_SPEED       = 12.0     -- m/s a walker can plausibly move (runners included)

-- Live grid: broadcast, countNear and the horde wake pass used to scan every zombie on the map once per player every tick
local LIVE_GRID = 60.0

-- Player positions. The spawn floor is only as good as this list.

local lastKnownAt = {}          -- [src] = { x =, y =, z =, at = os.clock() }
local LASTKNOWN_TTL = 120.0     -- seconds a remembered position stays usable

local pointCache, pointCacheAt, pointCacheBlind = nil, -1, 0

--- @return table list of { src, x, y, z, stale }, number players we have no
---         position for at all
local function playerPoints()
    local now = GetGameTimer()
    if pointCache and (now - pointCacheAt) < 200 then
        return pointCache, pointCacheBlind
    end

    local out, blind = {}, 0
    local clock = os.clock()

    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local ped = src and GetPlayerPed(src) or 0
        local ok = false

        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)
            -- 0,0,0 is not a position, it means 'not yet'.
            if at.x ~= 0.0 or at.y ~= 0.0 then
                lastKnownAt[src] = { x = at.x, y = at.y, z = at.z, at = clock }
                out[#out + 1] = { src = src, x = at.x, y = at.y, z = at.z, stale = false }
                ok = true
            end
        end

        if not ok then
            local last = lastKnownAt[src]
            if last and (clock - last.at) <= LASTKNOWN_TTL then
                out[#out + 1] = { src = src, x = last.x, y = last.y, z = last.z, stale = true }
            else
                blind = blind + 1
            end
        end
    end

    pointCache, pointCacheAt, pointCacheBlind = out, now, blind
    return out, blind
end

Registry.PlayerPoints = playerPoints

-- 2D distance from a point to the nearest player, nil if nobody is on. 2D because records carry z = 0.0 until a host reports ground.
-- @return number|nil distance, number|nil src
local function nearestPlayer2D(x, y)
    local best, bestSrc
    for _, p in ipairs(playerPoints()) do
        local dx, dy = x - p.x, y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if not best or d < best then best, bestSrc = d, p.src end
    end
    return best, bestSrc
end

-- Attribution: every record is stamped at birth with the code path that created it

-- Single spawn floor for every non-staff path: max of the two config values, never below 100 m.
-- @param record table
-- @param path string  how this record came to exist ('sector', 'staff', ...)
local function spawnFloor()
    return math.max(S.spawnDistanceMin or 50.0, (Streaming.PoolGuard or {}).minSpawnDistance or 50.0, 50.0)
end
Registry.SpawnFloor = spawnFloor

local function noteBirth(record, path)
    record.bornBy = path
    local d, src = nearestPlayer2D(record.x, record.y)
    record.bornDist = d
    record.bornNear = src

    local floor = spawnFloor()

    -- 'staff' is exempt from the floor (see zombies:force), so it is only stamped
    if path ~= 'staff' and path ~= 'event' and d and d < floor then
        print(('^1[BS ZOMBIES]^7 FLOOR BREACH AT BIRTH: walker %d created by "%s" %.0fm from src %s (floor %.0fm) at %.1f %.1f')
            :format(record.id, path, d, tostring(src), floor, record.x, record.y))
    end
end

local function liveGridKey(x, y)
    return math.floor(x / LIVE_GRID) .. '|' .. math.floor(y / LIVE_GRID)
end

-- Places (or re-places, if it moved cells) a record in the live grid
local function liveGridPut(record)
    local key = liveGridKey(record.x, record.y)
    if key == record.liveKey then return end

    if record.liveKey then
        local old = Registry.liveGrid[record.liveKey]
        if old then
            old[record.id] = nil
            if next(old) == nil then Registry.liveGrid[record.liveKey] = nil end
        end
    end

    Registry.liveGrid[key] = Registry.liveGrid[key] or {}
    Registry.liveGrid[key][record.id] = true
    record.liveKey = key
end

local function liveGridDrop(record)
    if not record.liveKey then return end
    local bucket = Registry.liveGrid[record.liveKey]
    if bucket then
        bucket[record.id] = nil
        if next(bucket) == nil then Registry.liveGrid[record.liveKey] = nil end
    end
    record.liveKey = nil
end

-- Every zombie record within radius (2D) of (x, y)
local function liveGridSize()
    local buckets, ids = 0, 0
    for _, bucket in pairs(Registry.liveGrid) do
        buckets = buckets + 1
        for _ in pairs(bucket) do ids = ids + 1 end
    end

    -- Counted here instead of calling total(), which is declared further down
    local records = 0
    for _ in pairs(Registry.zombies) do records = records + 1 end

    return buckets, ids, records
end

-- Fallback: the live grid is only an index and can drift
local gridWarned = 0

local function scanZombies(x, y, radius)
    local out = {}
    local r2 = radius * radius
    for _, record in pairs(Registry.zombies) do
        local dx, dy = record.x - x, record.y - y
        if (dx * dx + dy * dy) <= r2 then out[#out + 1] = record end
    end
    return out
end

local function nearbyZombies(x, y, radius)
    local out = {}
    local span = math.ceil(radius / LIVE_GRID)
    local ocx = math.floor(x / LIVE_GRID)
    local ocy = math.floor(y / LIVE_GRID)
    local r2 = radius * radius

    for dx = -span, span do
        for dy = -span, span do
            local bucket = Registry.liveGrid[(ocx + dx) .. '|' .. (ocy + dy)]
            if bucket then
                for id in pairs(bucket) do
                    local record = Registry.zombies[id]
                    if record then
                        local ddx, ddy = record.x - x, record.y - y
                        if (ddx * ddx + ddy * ddy) <= r2 then
                            out[#out + 1] = record
                        end
                    end
                end
            end
        end
    end

    -- Index said nothing, check the table before believing it.
    if #out == 0 and next(Registry.zombies) ~= nil then
        local real = scanZombies(x, y, radius)

        if #real > 0 then
            local now = GetGameTimer()
            if now - gridWarned > 10000 then
                gridWarned = now
                local buckets, ids, records = liveGridSize()
                print(('^1[BS ZOMBIES]^7 LIVE GRID MISS: index returned 0 near %.0f %.0f but a scan found %d. Grid holds %d id(s) in %d bucket(s); registry holds %d. Falling back to the scan.')
                    :format(x, y, #real, ids, buckets, records))
            end
            return real
        end
    end

    return out
end

Registry.NearbyZombies = nearbyZombies

-- Deterministic layout (decides WHERE, not WHETHER)

local function hash3(x, y, seed)
    local h = seed
    h = (h * 73856093) ~ (x * 19349663)
    h = (h * 83492791) ~ (y * 39916801)
    h = h & 0x7FFFFFFF
    h = h ~ (h >> 13)
    h = (h * 1274126177) & 0x7FFFFFFF
    return h ~ (h >> 16)
end

local function hashFloat(x, y, salt)
    return (hash3(x, y, Registry.seed + salt) % 100000) / 100000.0
end

local function cellKey(cx, cy) return cx .. ':' .. cy end

local function makeSeed()
    math.randomseed(os.time() % 2147483647)
    for _ = 1, 5 do math.random() end
    return math.random(100000, 2147483000)
end

Registry.seed = makeSeed()

-- Zones

local function zoneAt(x, y)
    local best
    for _, zone in ipairs(Zones.Spawn or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
            if not best or (zone.difficulty or 1) > (best.difficulty or 1) then best = zone end
        end
    end
    return best
end

local function inSafeZone(x, y)
    for _, zone in ipairs(Zones.Safe or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= ((zone.radius + S.safeZonePadding) ^ 2) then return true end
    end
    return false
end

local function typeForCell(cx, cy, zone)
    local weights = (zone and zone.types) or { walker = 98, brute = 2 }

    local total = 0
    for _, w in pairs(weights) do total = total + w end
    if total <= 0 then return 'walker' end

    local roll = hashFloat(cx, cy, 7717) * total
    local acc = 0
    for typeId, w in pairs(weights) do
        acc = acc + w
        if roll <= acc then return typeId end
    end
    return 'walker'
end

-- Cell coords to world centre are only needed for the pool area check
local function modelForCell(cx, cy, typeId, n)
    return Zombies.PickModel((cx + 0.5) * CELL, (cy + 0.5) * CELL, typeId, hashFloat(cx + (n or 0) * 7919, cy, 4231))
end

-- Records

local function wire(record)
    -- Minimal shape a client needs to build and place a ped
    return {
        id    = record.id,
        -- d is the transient A label shown only by the staff Alt overlay.
        d     = record.debugId,
        -- Simulation-agent id: lets a real A label identify its D origin.
        n     = record.nodeId,
        t     = record.typeId,
        m     = record.model,
        x     = record.x, y = record.y, z = record.z, h = record.h,
        hp    = record.hp,
        mhp   = record.maxHp,
        s     = record.state,
        r     = record.reacher and 1 or 0,
        -- Spawned feeding, see where it is rolled.
        e     = record.feeding and 1 or 0,

        -- Which system made the walker (node or sector)
        p     = record.nodeId and 'n' or 's',

        -- Provenance sent to the client, read by /zwhy
        b     = record.bornBy or '?',
        a     = math.floor((GetGameTimer() - (record.born or GetGameTimer())) / 100),
        w     = record.movedBy or nil,
    }
end

-- Through playerPoints, like every other question about where people are
local function playersNear(x, y, z, radius)
    local out = {}
    for _, p in ipairs(playerPoints()) do
        local dx, dy, dz = p.x - x, p.y - y, p.z - z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist <= radius then out[#out + 1] = { src = p.src, dist = dist } end
    end
    return out
end

local function assignHost(record, candidates)
    -- Networked walker (sv_net.lua): the engine owner is the host, always.
    if record.ent and ZNet and ZNet.enabled and ZNet.HostCandidates then
        candidates = ZNet.HostCandidates(record) or candidates
    end
    candidates = candidates or playersNear(record.x, record.y, record.z, HOST_RADIUS)

    local best
    for _, c in ipairs(candidates) do
        if not best or c.dist < best.dist then best = c end
    end

    local newHost = best and best.src or nil
    if newHost == record.host then return false end

    if record.host and Registry.hostOf[record.host] then
        Registry.hostOf[record.host][record.id] = nil
    end

    record.host = newHost

    if newHost then
        Registry.hostOf[newHost] = Registry.hostOf[newHost] or {}
        Registry.hostOf[newHost][record.id] = true
        if record.poiX and (record.poiUntil or 0) > os.time() then
            TriggerClientEvent('bs:z:draw',newHost,record.id,
                {x=record.poiX,y=record.poiY,z=record.poiZ or record.z})
        end
    end

    return true
end

local function removeZombie(id, reason)
    local record = Registry.zombies[id]
    if not record then return end

    -- Networked walker: corpse it or delete its entity (sv_net.lua).
    if record.ent and ZNet and ZNet.OnRemove then
        local okNet, errNet = pcall(ZNet.OnRemove, record, reason)
        if not okNet then print('^1[BS ZNET]^7 OnRemove error: ' .. tostring(errNet)) end
    end

    if record.host and Registry.hostOf[record.host] then
        Registry.hostOf[record.host][id] = nil
    end

    -- Guarded: a node walker has no cell, and t[nil] = nil raises "table index is nil" in Lua
    if record.cell then Registry.byCell[record.cell] = nil end
    if record.nodeId and record.nodeId > 0 and ZNodes and ZNodes.Release then
        ZNodes.Release(record)
    end
    liveGridDrop(record)
    releaseDebugId(record.debugId)
    Registry.zombies[id] = nil

    -- Removals are counted by reason and reported by the director tick.
    Registry.removedBy = Registry.removedBy or {}
    Registry.removedBy[reason or '?'] = (Registry.removedBy[reason or '?'] or 0) + 1

    -- Forced staff spawns are rare and interesting, so each one is named.
    if record.cell and tostring(record.cell):sub(1, 6) == 'force:' then
        print(('^3[BS ZOMBIES]^7 forced walker %d removed after %.1fs - reason "%s"')
            :format(id, (GetGameTimer() - (record.born or GetGameTimer())) / 1000.0,
                    tostring(reason)))
    end

    -- Always send a reason. cl_net treats a bs:z:rm without a reason as a per-player stream drop, not a deletion.
    TriggerClientEvent('bs:z:rm', -1, id, reason or 'removed')
end

Registry.Remove = removeZombie
Registry.GridPut = liveGridPut
Registry.AssignHost = assignHost

-- The director: what exists

local function spawnAt(cx, cy, zone)
    local key = cellKey(cx, cy)
    if Registry.byCell[key] then return nil end

    local cooldown = Registry.cellDead[key]
    if cooldown and os.time() < cooldown then return nil end
    if cooldown then Registry.cellDead[key] = nil end

    local px = (cx * CELL) + hashFloat(cx, cy, 313) * CELL
    local py = (cy * CELL) + hashFloat(cx, cy, 727) * CELL
    if inSafeZone(px, py) then return nil end

    -- Distance floor is enforced here, the only place it can be
    local floor = spawnFloor()
    local floor2 = floor * floor

    local points, blind = playerPoints()

    -- A connected player with no readable position: refuse and retry in 1.2s, since we cannot know the point is not on top of them
    if blind > 0 then
        Registry.refusedBlind = (Registry.refusedBlind or 0) + 1

        local now = GetGameTimer()
        Registry.blindSince = Registry.blindSince or now

        if (now - Registry.blindSince) < 30000 then
            return nil
        end

        if now - (Registry.blindWarned or 0) > 30000 then
            Registry.blindWarned = now
            print(('^3[BS ZOMBIES]^7 %d player(s) have had no readable position for %.0fs - spawning anyway. If a walker turns up on top of somebody, this line is why.')
                :format(blind, (now - Registry.blindSince) / 1000.0))
        end
    else
        Registry.blindSince = nil
    end

    for _, p in ipairs(points) do
        local dx, dy = px - p.x, py - p.y
        if (dx * dx + dy * dy) < floor2 then
            Registry.refusedTooClose = (Registry.refusedTooClose or 0) + 1
            return nil
        end
    end

    local typeId = typeForCell(cx, cy, zone)
    local def = Zombies.Types[typeId] or Zombies.Types.walker
    local model = modelForCell(cx, cy, typeId, Registry.nextId)
    if not model then return nil end

    local id = Registry.nextId
    Registry.nextId = id + 1

    local zhp = ZDiff.Health(def.health, px, py)
    local record = {
        id = id, cell = key, typeId = typeId, model = model,
        x = px, y = py, z = 0.0, h = hashFloat(cx, cy, 991) * 360.0,
        -- Z is unknown server-side (no collision)
        needsGround = true,
        hp = zhp, maxHp = zhp,

        -- State comes from feeding, not hardcoded to 'idle'
        reacher = Zombies.Reach.enabled and hashFloat(cx, cy, 5519) < (Zombies.Reach.chance or 0.4),

        -- Feeding is rolled once on the server so every client sees the same walker
        feeding = (Zombies.Feeding.types or {})[typeId] == true
                  and hashFloat(cx, cy, 7717) < (Zombies.Feeding.share or 0.0),

        born = GetGameTimer(),
    }

    -- See the note above: the server reports 'feeding' from the first broadcast, so nothing stands the client's ped back up
    record.state = record.feeding and 'feeding' or 'idle'

    Registry.zombies[id] = record
    Registry.byCell[key] = id
    liveGridPut(record)

    -- Stamped with the spawn path and the distance to the nearest player, so spawn complaints can be traced in the log
    noteBirth(record, 'sector')

    return record
end

-- Spawning at a point, not in a cell (node path)

-- Separate from spawnAt() because the node path needs an exact position
local function spawnAtPoint(nodeId, x, y, z, heading, typeId, model, floorOverride)
    if not ZPolicy.Point(x, y, z) or not ZPolicy.Finite(heading) then return nil, 'noCoord' end
    if nodeId and nodeId > 0 then
        local agent = ZSim and ZSim.agents[nodeId]
        if not agent or agent.pedId then return nil, 'empty' end
    end
    local PG = Streaming.PoolGuard or {}
    local cap = math.min(Streaming.globalHard or 200, PG.maxNetworked or 96)
    local count = 0
    for _ in pairs(Registry.zombies) do count = count + 1 end
    if count >= cap then return nil, 'cap' end

    -- Inside the world: a coordinate outside the map bounds is a broken plan or a bad client
    local bounds = ZAtlas and ZAtlas.bounds
    if bounds and (x < bounds.minX - 500 or x > bounds.maxX + 500
                or y < bounds.minY - 500 or y > bounds.maxY + 500) then
        return nil, 'outOfBounds'
    end

    if inSafeZone(x, y) then return nil, 'safeZone' end

    -- The distance floor is chosen by the caller
    local floor = math.max(tonumber(floorOverride) or 0.0, spawnFloor())
    local floor2 = floor * floor

    local points, blind = playerPoints()

    -- A player with an unreadable position is not treated as far away
    if blind > 0 then
        Registry.refusedBlind = (Registry.refusedBlind or 0) + 1
        return nil, 'blind'
    end

    for _, p in ipairs(points) do
        local dx, dy = x - p.x, y - p.y
        if (dx * dx + dy * dy) < floor2 then
            Registry.refusedTooClose = (Registry.refusedTooClose or 0) + 1
            return nil, 'tooClose'
        end
    end

    -- Per-player budget: walkers around any player who would stream this one count, so a player joining next to a horde gets none
    local perCap = PG.maxPerPlayer or S.maxPerClient or MAX_PER_PLAYER
    local r2 = STREAM_RADIUS * STREAM_RADIUS
    for _, p in ipairs(points) do
        local dx, dy = x - p.x, y - p.y
        if (dx * dx + dy * dy) <= r2 and #nearbyZombies(p.x, p.y, STREAM_RADIUS) >= perCap then
            Registry.refusedPlayerCap = (Registry.refusedPlayerCap or 0) + 1
            return nil, 'cap'
        end
    end

    local def = Zombies.Types[typeId] or Zombies.Types.walker
    if not def then return nil, 'noType' end
    if not model then return nil, 'noModel' end

    local id = Registry.nextId
    Registry.nextId = id + 1

    local zhp = ZDiff.Health(def.health, x, y)
    local record = {
        id = id,
        debugId = acquireDebugId(),
        -- No cell: a node walker must not claim a sector cell, or it would block the sector path from using it
        cell = nil,
        nodeId = nodeId,
        typeId = typeId, model = model,
        x = x, y = y, z = tonumber(z) or 0.0,
        h = tonumber(heading) or 0.0,

        -- The client's Z is trusted
        needsGround = false,

        hp = zhp, maxHp = zhp,
        reacher = Zombies.Reach.enabled and math.random() < (Zombies.Reach.chance or 0.4),
        feeding = (Zombies.Feeding.types or {})[typeId] == true
                  and math.random() < (Zombies.Feeding.share or 0.0),
        born = GetGameTimer(),
    }

    record.state = record.feeding and 'feeding' or 'idle'

    Registry.zombies[id] = record
    liveGridPut(record)

    -- Stamped 'node' rather than 'sector' so the log shows which system spawned a walker
    if nodeId and nodeId > 0 and not (ZNodes and ZNodes.Bind(record)) then
        Registry.zombies[id] = nil
        liveGridDrop(record)
        releaseDebugId(record.debugId)
        return nil, 'empty'
    end
    noteBirth(record, 'node')

    return record
end

-- Lets the streaming planner (same Lua state) reach the function above
Registry.SpawnAtPoint = spawnAtPoint


local function countNear(x, y, z)
    return #nearbyZombies(x, y, S.spawnRadius)
end

local function total()
    local n = 0
    for _ in pairs(Registry.zombies) do n = n + 1 end
    return n
end

-- Player positions are sampled once per director tick and reused for every zombie decision
local function samplePlayers()
    return (playerPoints())
end

-- Like playersNear, but against an already-sampled list (no native calls).
local function nearAmong(players, x, y, z, radius)
    local out = {}
    local r2 = radius * radius
    for _, p in ipairs(players) do
        local dx, dy, dz = p.x - x, p.y - y, p.z - z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 <= r2 then out[#out + 1] = { src = p.src, dist = math.sqrt(d2) } end
    end
    return out
end

-- The sector director

-- Sector population is counted from the records each tick, so it cannot drift like a maintained counter
local function countBySector()
    local counts = {}
    for _, record in pairs(Registry.zombies) do
        local key = ZSectors.KeyFor(record.x, record.y)
        counts[key] = (counts[key] or 0) + 1
    end
    return counts
end

local lastReport = 0

CreateThread(function()
    while true do
        Wait(Sectors.Settings.tick or DIRECTOR_TICK)
        -- This gate only covers the sector spawn pass
        if not S.enabled then goto continue end

        local worldTotal = total()
        local players = samplePlayers()
        -- why is declared out here because the 30s report prints it even when the sector pass did not run (it then reports zeroes)
        local why = { sectors = 0, disabled = 0, satisfied = 0, debt = 0, attempts = 0 }

        -- Sector spawn pass, currently disabled (node simulation decides what the world holds)
        if Sectors.Settings.enabled and not Streaming.enabled then
            local counts = countBySector()

            -- Which sectors are awake: a sector wakes when any player is within activateWithin of its nearest edge
            local awake = {}
            local reach = Sectors.Settings.activateWithin or 800.0

            for _, p in ipairs(players) do
                -- Every sector whose edge is within reach of this player
                local size = Sectors.Settings.size or 1000.0
                local pcx, pcy = math.floor(p.x / size), math.floor(p.y / size)
                local span = math.ceil(reach / size) + 1

                for dx = -span, span do
                    for dy = -span, span do
                        local key = ('%d:%d'):format(pcx + dx, pcy + dy)
                        if not awake[key] and ZSectors.DistanceTo(key, p.x, p.y) <= reach then
                            awake[key] = true
                        end
                    end
                end
            end

            -- Anything not awake this tick is marked asleep, so the upkeep sweep in sv_sectors can drop cold ones
            for key, sector in pairs(ZSectors.All()) do
                sector.awake = awake[key] or false
                sector.count = counts[key] or 0
            end

            -- Walkers each player already carries, checked against MAX_PER_PLAYER
            local load = {}
            for _, p in ipairs(players) do
                load[p.src] = #nearbyZombies(p.x, p.y, STREAM_RADIUS)
            end

            local perPlayerCap = (Streaming.PoolGuard or {}).maxPerPlayer or S.maxPerClient or MAX_PER_PLAYER

            local hour = tonumber(os.date('%H'))
            local night = Zones.Scaling.nightHours or { from = 20, to = 6 }
            local isNight = (hour >= night.from or hour < night.to)

            -- Every reason the loop refuses to spawn is counted and printed every 30 seconds to the server

            for key in pairs(awake) do
                if worldTotal >= MAX_TOTAL then break end
                why.sectors = why.sectors + 1

                local sector = ZSectors.Get(key)
                sector.awake = true
                sector.count = counts[key] or 0

                -- Zone density decides that a city block is worse than open scrub
                local mx, my = ZSectors.RandomPointIn(key)
                local zone = zoneAt(mx, my)
                local density = (zone and zone.density) or 0.6

                local want = ZSectors.TargetFor(sector, density, isNight)
                local short = want - sector.count

                if not sector.enabled then
                    why.disabled = why.disabled + 1
                elseif want == 0 then
                    -- Target is zero although the sector is on: respawn debt.
                    why.debt = why.debt + 1
                elseif short <= 0 then
                    why.satisfied = why.satisfied + 1
                end

                if short > 0 then
                    why.attempts = why.attempts + 1
                    -- Spawn attempts, not spawns
                    local attempts = math.min(short, 6)

                    for _ = 1, attempts do
                        if worldTotal >= MAX_TOTAL then break end

                        -- Pulled toward whatever has been making noise here (see SpawnPointIn).
                        local px, py = ZSectors.SpawnPointIn(key, sector)

                        -- Never in someone's face: the point must be checked against every player, since sectors pick points anywhere inside themselves
                        local tooClose = false

                        -- Never past what a client can carry: if any player watching this walker is at their ceiling, refuse the spawn
                        local watching = {}
                        local blocked = false

                        -- Never so far that the next tick culls it
                        local keepRadius = (S.despawnDistance or 800.0) * 0.9
                        local tooFar = true

                        for _, p in ipairs(players) do
                            local dx, dy = px - p.x, py - p.y
                            local d2 = dx * dx + dy * dy

                            local minD = spawnFloor()
                            if d2 < (minD * minD) then
                                tooClose = true
                                break
                            end

                            if d2 <= (keepRadius * keepRadius) then tooFar = false end

                            if d2 <= (STREAM_RADIUS * STREAM_RADIUS) then
                                if (load[p.src] or 0) >= perPlayerCap then
                                    blocked = true
                                    break
                                end
                                watching[#watching + 1] = p.src
                            end
                        end

                        if not tooClose and not blocked and not tooFar then
                            local cx = math.floor(px / CELL)
                            local cy = math.floor(py / CELL)
                            local record = spawnAt(cx, cy, zone)
                            if record then
                                worldTotal = worldTotal + 1
                                sector.count = sector.count + 1
                                for _, src in ipairs(watching) do
                                    load[src] = (load[src] or 0) + 1
                                end
                            end
                        end
                    end
                end
            end

        end

        -- Cull anything nobody is near, and re-host the rest
        local scanRadius = math.max(S.despawnDistance, HOST_RADIUS)
        for id, record in pairs(Registry.zombies) do
            local near = nearAmong(players, record.x, record.y, record.z, scanRadius)

            local withinDespawn = {}
            local withinHost = {}
            for _, c in ipairs(near) do
                if c.dist <= S.despawnDistance then withinDespawn[#withinDespawn + 1] = c end
                if c.dist <= HOST_RADIUS then withinHost[#withinHost + 1] = c end
            end

            if #withinDespawn == 0 then
                -- Nobody can see it
                if not record.event then removeZombie(id, 'far') end
            else
                assignHost(record, withinHost)
            end
        end

        -- Every 30 seconds: enough to watch state changes while debugging, quiet enough to leave on.
        if GetGameTimer() - lastReport > 30000 then
            lastReport = GetGameTimer()
            local removed = {}
            for reason, n in pairs(Registry.removedBy or {}) do
                removed[#removed + 1] = ('%s=%d'):format(reason, n)
            end
            Registry.removedBy = {}

            -- refused-blind: non-zero means a spawn was refused because a player had no readable position
            print(('^5[BS ZOMBIES]^7 world=%d/%d  players=%d  awake=%d  spawning=%d  refused-too-close=%d  refused-blind=%d  rejected-host-moves=%d  (asleep: disabled=%d debt=%d satisfied=%d)  removed since last: %s')
                :format(worldTotal, MAX_TOTAL, #players, why.sectors,
                        why.attempts, Registry.refusedTooClose or 0,
                        Registry.refusedBlind or 0, Registry.rejectedMoves or 0,
                        why.disabled, why.debt, why.satisfied,
                        #removed > 0 and table.concat(removed, ' ') or 'none'))

            -- Per-report, not cumulative.
            Registry.refusedTooClose = 0
            Registry.refusedBlind = 0
        end

        ::continue::
    end
end)

-- Broadcast. Per player, only about walkers they are near.

local known = {}    -- [src] = { [id] = true }

local streamStat = { adds = 0, moves = 0, near = 0, known = 0 }
local lastStream = 0

CreateThread(function()
    while true do
        Wait(TICK)

        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then goto nextPlayer end

            local at = GetEntityCoords(ped)

            -- A player at the origin is one we do not know yet
            if at.x == 0.0 and at.y == 0.0 then goto nextPlayer end

            known[src] = known[src] or {}
            local seen = known[src]

            local adds, moves, drops = {}, {}, {}
            local hosted = {}

            -- Asks the live grid for zombies near this player (see nearbyZombies / LIVE_GRID) instead of
            local stillNear = {}
            local nearCount = 0

            for _, record in ipairs(nearbyZombies(at.x, at.y, STREAM_RADIUS)) do
                nearCount = nearCount + 1
                local id = record.id
                stillNear[id] = true

                if not seen[id] then
                    seen[id] = true
                    adds[#adds + 1] = wire(record)

                    -- Tripwire: an add is the moment a walker appears on someone's screen
                    local afx, afy = record.x - at.x, record.y - at.y
                    local appearedAt = math.sqrt(afx * afx + afy * afy)
                    local floor = spawnFloor()

                    if appearedAt < (floor * 0.5) then
                        print(('^1[BS ZOMBIES]^7 CLOSE ARRIVAL: walker %d appeared %.0fm from src %s (floor %.0fm). born=%s at %s from nearest player, moved-by=%s, age=%.1fs, host=%s, lured=%s')
                            :format(id, appearedAt, tostring(src), floor,
                                    tostring(record.bornBy or '?'),
                                    record.bornDist and ('%.0fm'):format(record.bornDist) or '?',
                                    tostring(record.movedBy or 'nothing'),
                                    (GetGameTimer() - (record.born or GetGameTimer())) / 1000.0,
                                    tostring(record.host),
                                    record.lureUntil and 'yes' or 'no'))
                    end
                else
                    -- Compact: id, position, heading, state, health.
                    moves[#moves + 1] = {
                        record.id, record.x, record.y, record.z, record.h,
                        record.state, record.hp,
                    }
                end
                if record.host == src then hosted[#hosted + 1] = id end
            end

            -- Anything this player knew about that is not in stillNear moved out of range or was removed, so it comes off their screen
            local dropRadius = STREAM_RADIUS * 1.25

            for id in pairs(seen) do
                if not stillNear[id] then
                    local rec = Registry.zombies[id]

                    if not rec then
                        seen[id] = nil
                        drops[#drops + 1] = id
                        print(('^1[BS STREAM]^7 dropping walker %d - no longer in the registry'):format(id))
                    else
                        local dx, dy = rec.x - at.x, rec.y - at.y
                        local d2 = dx * dx + dy * dy

                        if d2 > (dropRadius * dropRadius) then
                            seen[id] = nil
                            drops[#drops + 1] = id
                            print(('^1[BS STREAM]^7 dropping walker %d - record is %.0fm away (%.1f %.1f), you are at %.1f %.1f')
                                :format(id, math.sqrt(d2), rec.x, rec.y, at.x, at.y))
                        else
                            streamStat.rescued = (streamStat.rescued or 0) + 1
                        end
                    end
                end
            end

            -- Counters are written here for the report. Without these assignments the report prints zeros.
            streamStat.near  = nearCount
            streamStat.adds  = streamStat.adds + #adds
            streamStat.moves = streamStat.moves + #moves

            streamStat.known = 0
            for _ in pairs(seen) do streamStat.known = streamStat.known + 1 end

            if #adds > 0 then TriggerClientEvent('bs:z:add', src, adds) end
            if #moves > 0 then TriggerClientEvent('bs:z:upd', src, moves) end
            if #drops > 0 then TriggerClientEvent('bs:z:rm', src, drops) end
            TriggerClientEvent('bs:z:host', src, hosted)

            if GetGameTimer() - lastStream > 30000 then
                lastStream = GetGameTimer()
                print(('^5[BS STREAM]^7 src=%s at %.0f %.0f  within-%dm=%d  knows=%d  sent-adds=%d moves=%d  ^3index-misses-rescued=%d^7')
                    :format(tostring(src), at.x, at.y, STREAM_RADIUS,
                            streamStat.near, streamStat.known,
                            streamStat.adds, streamStat.moves,
                            streamStat.rescued or 0))
                streamStat.adds, streamStat.moves, streamStat.rescued = 0, 0, 0
            end

            ::nextPlayer::
        end
    end
end)

-- Host reports

RegisterNetEvent('bs:z:report', function(batch)
    local src = source
    if type(batch) ~= 'table' then return end

    local mine = Registry.hostOf[src]
    if not mine then return end

    local now = GetGameTimer()

    for _, entry in ipairs(batch) do
        local id = entry[1]
        local record = Registry.zombies[id]

        -- Only the host of THIS walker may move it.
        if record and mine[id] and record.ent and ZNet and ZNet.enabled then
            -- Networked walker: position is read from the entity by sv_net
            local state = entry[6]
            if type(state) == 'string' and #state <= 12 and (state ~= 'grab' or record.grabBy) then record.state = state end
            record.lastReport = now
        elseif record and mine[id] then
            local x, y, z, h, state = entry[2], entry[3], entry[4], entry[5], entry[6]

            if ZPolicy.Point(x, y, z) then
                -- Plausibility: no walker teleports
                local dt = math.max(0.05, (now - (record.lastReport or now)) / 1000.0)
                -- Horizontal and vertical movement are kept separate because they are policed by different rules below
                local dx, dy, dz = x - record.x, y - record.y, z - record.z

                -- The first report is never a teleport
                local firstReport = record.lastReport == nil
                local groundFix   = record.needsGround

                -- The first-report exemption is watched
                local horizontal = math.sqrt(dx * dx + dy * dy)
                local budget = (MAX_SPEED * dt) + 2.0
                if firstReport then budget = math.max(budget, 5.0) end

                local horizontalOK = horizontal <= budget

                if not horizontalOK then
                    -- Logged with numbers and rate-limited: a lying host and packet loss look the same from here, and only the first is worth chasing
                    Registry.rejectedMoves = (Registry.rejectedMoves or 0) + 1
                    if Registry.rejectedMoves == 1 or Registry.rejectedMoves % 50 == 0 then
                        print(('^3[BS ZOMBIES]^7 walker %d: host src %s reported a %.0fm horizontal jump in %.2fs (budget %.0fm, needsGround=%s, first=%s) - refused. %.1f %.1f -> %.1f %.1f')
                            :format(id, tostring(src), horizontal, dt, budget,
                                    tostring(groundFix), tostring(firstReport),
                                    record.x, record.y, x, y))
                    end
                    -- The host's local ped can drift hundreds of metres from the authoritative record
                    local PG = Streaming.PoolGuard or {}
                    local follow = PG.hostDriftAccept or 60.0
                    local snapAt = PG.hostSnapDistance or 120.0
                    local busy = COMBAT_STATES[record.state] or COMBAT_STATES[state]
                    if horizontal <= follow or busy then
                        local k = budget / horizontal
                        record.x = record.x + dx * k
                        record.y = record.y + dy * k
                        record.movedBy = 'host-clamped:' .. tostring(src)
                        record.movedAt = now
                        liveGridPut(record)
                    elseif not groundFix and horizontal > snapAt
                       and now - (record.lastCorrection or -10000) >= 3000 then
                        record.lastCorrection = now
                        TriggerClientEvent('bs:z:correctHost', src, id,
                            record.x, record.y, record.z)
                    end
                end

                if horizontalOK then
                    record.x, record.y = x, y
                    record.movedBy = 'host:' .. tostring(src)
                    record.movedAt = now
                end

                -- Height is accepted while we are still waiting for one, then policed like anything else
                if firstReport or groundFix or math.abs(dz) <= budget then
                    record.z = z
                    record.needsGround = false
                end

                if horizontalOK or firstReport or groundFix then
                    record.h = tonumber(h) or record.h
                    liveGridPut(record)
                end

                if type(state) == 'string' and #state <= 12 and (state ~= 'grab' or record.grabBy) then record.state = state end
                record.lastReport = now
            end
        end
    end
end)

-- Damage and death

local killRate = {}

-- Weapon name to hash, built once at start. cl_combat reports the weapon as
local weaponByHash = {}
for name, entry in pairs(Zombies.WeaponBaseDamage) do
    weaponByHash[tostring(GetHashKey(name))] = entry
end

-- Most damage a single reported hit can plausibly be worth, given the weapon and headshot
local function maxPlausibleDamage(weaponKey, headshot)
    local S = Zombies.Settings
    local entry = weaponByHash[weaponKey]
    local raw = entry and entry.raw or S.unknownWeaponRawDamage

    local scale
    if entry and entry.melee then
        scale = (S.meleeDamageScale or 12.0) * (headshot and 1.5 or 1.0)
    else
        scale = headshot and (S.headshotMultiplier or 4.0) or (S.bodyDamageScale or 0.35)
    end

    return raw * scale * (S.damageScale or 1.0) * (S.weaponDamageHeadroom or 1.6)
end

-- Rate limit on rewards, not on dying
local function underKillLimit(src)
    local now = os.time()
    local rec = killRate[src]

    if not rec or (now - rec.at) >= 60 then
        killRate[src] = { at = now, n = 1 }
        return true
    end

    if rec.n >= 45 then return false end

    rec.n = rec.n + 1
    return true
end

-- Any client may report damage to any walker it can see
local nosuchSent = {}

local function tellClientNoSuchWalker(src, id)
    local key = ('%s:%s'):format(src, id)
    local now = os.time()

    -- Once per player per walker every five seconds is enough
    if nosuchSent[key] and (now - nosuchSent[key]) < 5 then return end
    nosuchSent[key] = now

    TriggerClientEvent('bs:z:nosuch', src, id)
end

-- Is this walker real?
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for key, at in pairs(nosuchSent) do
            if (now - at) > 30 then nosuchSent[key] = nil end
        end
    end
end)

RegisterNetEvent('bs:z:verify', function(id)
    local src = source
    id = tonumber(id)
    if not id then return end

    local record = Registry.zombies[id]
    if not record then
        return tellClientNoSuchWalker(src, id)
    end

    local key = ('v%s:%s'):format(src, id)
    local now = os.time()
    if nosuchSent[key] and (now - nosuchSent[key]) < 5 then return end
    nosuchSent[key] = now

    TriggerClientEvent('bs:z:verified', src, id, record.hp)
end)

-- Kill/hit telemetry
Registry.hitStats = Registry.hitStats or {
    received      = 0,   -- bs:z:hit arrived at all
    noRecord      = 0,   -- ...for an id this table does not have
    outOfRange    = 0,   -- ...from further than 150m
    zeroDamage    = 0,   -- ...clamped to nothing
    applied       = 0,   -- ...health actually reduced
    withNode      = 0,   -- ...on a record that carries a nodeId
    withoutNode   = 0,   -- ...on a record without one (sector / staff / other)
    deaths        = 0,   -- health reached zero here
    recordDeath   = 0,   -- ZNodes.RecordDeath was called
    deathNoNode   = 0,   -- death that could not debit the simulation
    deathNotReady = 0,   -- ...because ZNodes.ready was false
    rewardErrors  = 0,   -- export threw after the walker died
    gated         = 0,   -- removed because a client could not show it
}

-- Server half of the spawn-on-top-of-player guard
RegisterNetEvent('bs:z:gated', function() end)

RegisterNetEvent('bs:z:materialised', function(id)
    local src = source
    local record = Registry.zombies[tonumber(id)]
    if not record then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local at = GetEntityCoords(ped)
    if (record.x-at.x)^2 + (record.y-at.y)^2 > (STREAM_RADIUS+50)^2 then return end
    record.materialisedAt = record.materialisedAt or GetGameTimer()
    if record.host == src and record.poiX and (record.poiUntil or 0)>os.time() then
        TriggerClientEvent('bs:z:draw',src,record.id,
            {x=record.poiX,y=record.poiY,z=record.poiZ or record.z})
    end
end)

-- A record nobody ever drew must not hold an active slot forever
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        local expired = {}
        for id, record in pairs(Registry.zombies) do
            if record.nodeId and not record.materialisedAt and now-(record.born or now) > 45000 then
                expired[#expired+1] = id
            end
        end
        for _, id in ipairs(expired) do removeZombie(id,'unmaterialised') end
    end
end)


-- Apply-and-die path, shared by bs:z:hit and bs:z:dmg
local releaseGrab   -- defined with the grab events below

local function applyHit(src, id, record, damage, headshot, weapon, noReward)
    if ZSimSense and ZSimSense.ReportDamage then ZSimSense.ReportDamage(src, id) end
    Registry.hitStats.applied = Registry.hitStats.applied + 1
    record.hp = record.hp - damage

    if record.hp > 0 then
        -- Everyone sees the hit, and everything nearby turns toward it.
        TriggerClientEvent('bs:z:hurt', -1, id, record.hp, src)
        return
    end

    Registry.hitStats.deaths = Registry.hitStats.deaths + 1
    if record.grabBy or record.state == 'grab' then releaseGrab(record) end   -- end the grab cleanly

    -- Death path order matters: ZNodes.RecordDeath

    local def = Zombies.Types[record.typeId] or Zombies.Types.walker
    local zone = zoneAt(record.x, record.y)

    -- 1. The body belongs to everyone: same walker, same corpse, same loot.
    TriggerClientEvent('bs:z:dead', -1, id, {
        x = record.x, y = record.y, z = record.z,
        killer = src, headshot = headshot and true or false,
        loot = def.loot or 'walker',
    })

    -- 2
    if ZSectors then pcall(ZSectors.RegisterKill, record.x, record.y) end

    -- 3
    if record.nodeId and record.nodeId > 0 then
        if ZNodes and ZNodes.Init() then
            local ok, debited = pcall(ZNodes.RecordDeath, record.nodeId,
                             { x = record.x, y = record.y, z = record.z or 0.0 })
            if ok and debited then
                Registry.hitStats.recordDeath = Registry.hitStats.recordDeath + 1
            end
        else
            Registry.hitStats.deathNotReady = Registry.hitStats.deathNotReady + 1
        end
    else
        Registry.hitStats.deathNoNode = Registry.hitStats.deathNoNode + 1
    end

    -- 4. Same nil-cell guard as removeZombie, see the note there.
    if record.cell then
        Registry.cellDead[record.cell] = os.time() + CELL_RESPAWN
    end

    -- 5. The record is gone. Above this is world state, below is bookkeeping for one player.
    removeZombie(id, 'dead')

    -- Staff kills (/zkill) pay nothing and add no kill stats.
    if noReward then return end

    -- Rewards and logging. Isolated: an error here costs a payout, not a death.

    local rewardOk = pcall(function()
        -- Dead either way; paid only if under the ceiling (see underKillLimit).
        local paid = underKillLimit(src)

        local action = def.reward or 'zombie_kill'
        if headshot and action == 'zombie_kill' then action = 'zombie_kill_headshot' end

        if zone and Director_AddHeat then Director_AddHeat(zone, 1.2) end

        local reward = paid
            and exports.bs_core:AwardAction(src, action, zone and zone.difficulty or 1.0)
            or nil

        local player = exports.bs_core:GetPlayer(src)
        if player then
            -- Running total read by the scoreboard
            TriggerEvent('bs:db:insert', [[
                INSERT INTO `bs_character_stats` (`character_id`, `zombie_kills`)
                VALUES (?, 1)
                ON DUPLICATE KEY UPDATE `zombie_kills` = `zombie_kills` + 1
            ]], { player.charId })

            TriggerEvent('bs:db:insert', [[
                INSERT INTO `bs_zombie_kills`
                    (`character_id`, `zombie_type`, `weapon`, `headshot`, `zone`, `xp_awarded`, `money_awarded`)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]], {
                player.charId,
                tostring(record.typeId):sub(1, 32),
                tostring(weapon or ''):sub(1, 48),
                headshot and 1 or 0,
                zone and zone.id or 'wilds',
                reward and reward.xp or 0,
                reward and reward.money or 0,
            })
        end
    end)

    if not rewardOk then
        Registry.hitStats.rewardErrors = Registry.hitStats.rewardErrors + 1
        print(('^1[BS ZOMBIES]^7 the reward/logging half of walker %d\'s death threw. The walker IS dead and the world has been told - that is the point of the re-order in this handler. Check bs_core:AwardAction. Total so far: %d')
            :format(id, Registry.hitStats.rewardErrors))
    end
end

local executionGate = {}
RegisterNetEvent('bs:z:hit', function(id, damage, headshot, weapon)
    local src = source
    id = tonumber(id)
    -- Only cl_execute still sends this. Guns/melee use bs:z:dmg.
    local finisher = weapon == 'finisher' and Zombies.Finisher and Zombies.Finisher.enabled
    if weapon ~= 'execution' and not finisher then return end
    if weapon == 'execution' and not Zombies.Execute.enabled then return end
    if not known[src] or not known[src][id] then return end
    if GetGameTimer() < (executionGate[src] or 0) then return end
    -- Dead or downed players cannot take a walker down.
    if Player(src).state.bsDowned then return end
    local sped = GetPlayerPed(src)
    if not sped or sped == 0 or GetEntityHealth(sped) <= 0 then return end

    Registry.hitStats.received = Registry.hitStats.received + 1

    local record = Registry.zombies[id]
    if not record then
        -- Reply so the client knows, see tellClientNoSuchWalker.
        Registry.hitStats.noRecord = Registry.hitStats.noRecord + 1
        if id then tellClientNoSuchWalker(src, id) end
        return
    end

    -- Counts hits on records with a nodeId
    if record.nodeId then
        Registry.hitStats.withNode = Registry.hitStats.withNode + 1
    else
        Registry.hitStats.withoutNode = Registry.hitStats.withoutNode + 1
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    local dx, dy = at.x - record.x, at.y - record.y
    local maxR = finisher and (Zombies.Finisher.range or 1.6) or (Zombies.Execute.range or 1.8)
    if (dx * dx + dy * dy) > (maxR + 1.0)^2 then
        Registry.hitStats.outOfRange = Registry.hitStats.outOfRange + 1
        return
    end

    -- Damage is clamped to what the named weapon can plausibly do
    if not finisher and Zombies.Execute.onlyUnaware and (record.state == 'hunting' or record.state == 'hunt' or record.state == 'grab') then return end
    executionGate[src] = GetGameTimer() + (finisher and (Zombies.Finisher.cooldown or 1500) or (Zombies.Execute.cooldown or 1200)) - 100
    -- See maxPlausibleDamage above. The absolute zombie-HP ceiling stays as a backstop.
    weapon = tostring(weapon or '')
    local reported = math.max(0, tonumber(damage) or 0)

    -- Executioner perk: a headshot is an instant kill
    local executioner = false
    if headshot and GetResourceState('bs_skills') == 'started' then
        local ok, has = pcall(function() return exports.bs_skills:HasPerk(src, 'executioner') end)
        executioner = ok and has == true
    end

    if executioner and weapon ~= 'vehicle' then
        damage = math.min(reported, record.maxHp * 10)
    elseif weapon == 'execution' or finisher then
        -- E-takedown needs the attacker next to the zombie, so the range check is stricter than the general 150 unit hit range
        if (dx * dx + dy * dy) > (Zombies.Settings.executeMaxRange or 3.0) ^ 2 then
            return
        end
        damage = math.min(reported, record.maxHp * 10)
    elseif weapon == 'vehicle' then
        damage = math.min(reported, record.maxHp * 3)
    else
        local cap = maxPlausibleDamage(weapon, headshot and true or false)

        -- Floor under the cap for unlisted weapons (addons, unmatched hashes)
        if not weaponByHash[weapon] then
            local floorCap = record.maxHp * (headshot and 0.25 or 0.085)
            if floorCap > cap then cap = floorCap end
        end

        damage = math.min(reported, cap, record.maxHp * 2)
    end

    if damage <= 0 then
        Registry.hitStats.zeroDamage = Registry.hitStats.zeroDamage + 1
        return
    end


    -- Legacy door. cl_execute takedowns come through here: they name their own damage and are gated on being behind a walker.
    applyHit(src, id, record, damage, headshot, weapon)
end)

-- bs:z:dmg: the client raycasts its own shot, reads the bone and reports WHERE it hit, not how much

local dmgGate = {}   -- [src] = { at = ms, n = shots this window }

-- Body/melee damage multiplier from player level (bs_core) and combat skill (bs_skills)
local function progressionMult(src)
    local P = (Zombies.Damage or {}).progression
    if not P or P.enabled == false then return 1.0 end
    local lf, sf = 1.0, 1.0
    local okP, pl = pcall(function() return exports.bs_core:GetPlayer(src) end)
    if okP and pl and pl.level then
        lf = math.max(0, math.min(1, (pl.level - 1) / math.max(1, (P.maxLevel or 60) - 1)))
    end
    if GetResourceState('bs_skills') == 'started' then
        local okS, lv = pcall(function() return exports.bs_skills:GetSkillLevel(src, P.skillTree or 'combat') end)
        if okS and tonumber(lv) then sf = math.max(0, math.min(1, lv / math.max(1, P.skillMax or 20))) end
    end
    local lw = P.levelWeight or 0.5
    local t = lw * lf + (1 - lw) * sf
    t = t ^ (P.curve or 1.0)
    return (P.min or 0.6) + ((P.max or 1.2) - (P.min or 0.6)) * t
end

RegisterNetEvent('bs:z:dmg', function(id, region, headshotFlag, weapon, dist)
    local src = source
    id = tonumber(id)
    if not id then return end

    local D = Zombies.Damage or {}

    -- Rate limit: an automatic rifle fires about 12 rounds/s, so the ceiling is well above real fire and far below a script
    local now = GetGameTimer()
    local gate = dmgGate[src]
    if not gate or (now - gate.at) >= 1000 then
        gate = { at = now, n = 0 }
        dmgGate[src] = gate
    end
    gate.n = gate.n + 1
    if gate.n > (D.maxShotsPerSecond or 30) then
        Registry.hitStats.rate = (Registry.hitStats.rate or 0) + 1
        return
    end

    Registry.hitStats.received = Registry.hitStats.received + 1

    local record = Registry.zombies[id]
    if not record then
        Registry.hitStats.noRecord = Registry.hitStats.noRecord + 1
        tellClientNoSuchWalker(src, id)
        return
    end

    if record.nodeId then
        Registry.hitStats.withNode = Registry.hitStats.withNode + 1
    else
        Registry.hitStats.withoutNode = Registry.hitStats.withoutNode + 1
    end

    -- Range check against the shooter's real server position
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local at = GetEntityCoords(ped)
    local dx, dy = record.x - at.x, record.y - at.y
    local maxR = D.serverMaxRange or 300.0
    if (dx * dx + dy * dy) > (maxR * maxR) then
        Registry.hitStats.outOfRange = (Registry.hitStats.outOfRange or 0) + 1
        if not record.warnedHitRange then
            record.warnedHitRange = true
            print(('[BS ZOMBIES] walker %d hit refused: server record %.0fm from shooter (limit %.0fm); host movement may be desynced')
                :format(id, math.sqrt(dx * dx + dy * dy), maxR))
        end
        return
    end

    region = tostring(region or 'torso')
    local headshot = (tonumber(headshotFlag) or 0) == 1
    if not known[src] or not known[src][id] then return end
    if region ~= 'head' and region ~= 'torso' and region ~= 'arm' and region ~= 'leg' then return end
    if headshot and region ~= 'head' then return end

    -- Weapon damage comes from this server's table; the client only says which weapon
    local entry = weaponByHash[tostring(weapon)]
    if entry and entry.melee and (dx*dx+dy*dy) > ((D.meleeRange or 2.4)+2.0)^2 then return end
    local base = entry and entry.raw or nil
    if not base or base <= 0 then base = (record.maxHp or 220) * 0.12 end
    if entry and entry.melee then
        base = base * ((Zombies.Settings and Zombies.Settings.meleeDamageScale) or 1.0)
    end

    -- Headshot rule: a headshot kills at any hp
    local damage
    if headshot then
        damage = record.hp   -- Exact, so the shared death path sees hp hit zero.
    else
        local scale = (D.regionScale and D.regionScale[region]) or 1.0
        damage = math.floor(base * scale * progressionMult(src) + 0.5)

        -- No body floor while it holds a player, so a grabber can always be put down
        local floor_ = ((entry and entry.melee) or D.headshotOnly == false) and 0 or (D.bodyFloor or 10)
        local allowed = math.max(0, (record.hp or 0) - floor_)
        if damage > allowed then damage = allowed end

        -- Limbs are recorded before the damage is capped, so a walker at the floor still loses its legs
        if region == 'leg' then
            record.legHits = (record.legHits or 0) + 1
            if not record.crawler and record.legHits >= (D.legHitsToCrawl or 2) then
                record.crawler = true
                -- Everyone sees it go down. cl_crawl.lua owns the pose and drag. Legs cripple but never kill.
                TriggerClientEvent('bs:z:crippled', -1, id)
            end
        elseif region == 'arm' and D.armDisarms ~= false then
            record.armHits = (record.armHits or 0) + 1
        end

        if damage <= 0 then
            -- At the floor and still shot in the body: the hit landed but cannot kill.
            Registry.hitStats.atFloor = (Registry.hitStats.atFloor or 0) + 1
            if not record.warnedBodyFloor then
                record.warnedBodyFloor = true
                print(('[BS ZOMBIES] walker %d at %d HP body floor; further body shots cannot kill it, headshot required')
                    :format(id, record.hp or 0))
            end
            TriggerClientEvent('bs:z:hurt', -1, id, record.hp, src)
            TriggerClientEvent('bs:z:dmgnum', src, id, 0, 'floored')
            return
        end
    end

    local hpBefore = record.hp or 0
    applyHit(src, id, record, damage, headshot, weapon)
    TriggerClientEvent('bs:z:dmgnum', src, id, headshot and hpBefore or damage, headshot and 'head' or 'body')
end)

AddEventHandler('playerDropped', function()
    dmgGate[source] = nil
end)

-- Environmental death (fall, fire, no shooter): removed with no credit, loot or kill count
local vehGate = {}
RegisterNetEvent('bs:z:vehhit', function(id, kind)
    local src = source
    id = tonumber(id)
    if not id or (kind ~= 'kill' and kind ~= 'cripple') then return end
    if not known[src] or not known[src][id] then return end
    local V = Zombies.Vehicle or {}

    local now = GetGameTimer()
    local g = vehGate[src]
    if not g or now - g.at >= 1000 then g = { at = now, n = 0 }; vehGate[src] = g end
    g.n = g.n + 1
    if g.n > 12 then return end

    local record = Registry.zombies[id]
    if not record then tellClientNoSuchWalker(src, id); return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end

    local at = GetEntityCoords(veh)
    local dx, dy = record.x - at.x, record.y - at.y
    local maxD = V.serverMaxDist or 14.0
    if dx * dx + dy * dy > maxD * maxD then
        Registry.hitStats.outOfRange = (Registry.hitStats.outOfRange or 0) + 1
        return
    end
    -- Speed may already have dropped after the hit, so only a loose floor.
    if GetEntitySpeed(veh) * 3.6 < (V.serverMinKmh or 1.0) then return end

    if kind == 'cripple' then
        if not record.crawler then
            record.crawler = true
            TriggerClientEvent('bs:z:crippled', -1, id)
        end
        return
    end

    if (record.hp or 0) <= 0 then return end
    -- A ram kill needs real speed; a downed/crawling walker can be crushed slowly.
    if not record.crawler and not record.downed
       and GetEntitySpeed(veh) * 3.6 < (V.killKmh or 90.0) * (V.serverKillFrac or 0.6) then
        if not record.crawler then
            record.crawler = true
            TriggerClientEvent('bs:z:crippled', -1, id)
        end
        return
    end
    applyHit(src, id, record, record.hp, false, 'vehicle')
end)
AddEventHandler('playerDropped', function() vehGate[source] = nil end)

RegisterNetEvent('bs:z:envdeath', function(id)
    id = tonumber(id)
    if not id then return end
    local record = Registry.zombies[id]
    if not record then return end
    if record.host ~= source then return end

    Registry.hitStats.envDeath = (Registry.hitStats.envDeath or 0) + 1
    TriggerClientEvent('bs:z:dead', -1, id, { env = true })
    removeZombie(id, 'environment')
end)


-- Being grabbed is shared: everyone near sees the same walker holding the same player, since state rides on the record
RegisterNetEvent('bs:z:grab', function(id, holding)
    local src = source
    local record = Registry.zombies[tonumber(id)]
    if not record then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    local dx, dy = at.x - record.x, at.y - record.y
    if (dx * dx + dy * dy) > 16.0 then return end

    -- A grab is a lunge, not a hold, and the server ends it
    local now = GetGameTimer()
    if holding then
        if record.grabBy == src and (now - (record.grabAt or 0)) < 300 then return end
        record.grabBy, record.grabAt = src, now
        record.grabUntil = now + ((Zombies.Net and Zombies.Net.grabMaxMs) or 1500)
    else
        if record.grabBy and record.grabBy ~= src then return end
        record.grabBy, record.grabAt, record.grabUntil = nil, nil, nil
    end
    record.state = holding and 'grab' or 'hunting'
    TriggerClientEvent('bs:z:grabbed', -1, record.id, src, holding and true or false)
end)

releaseGrab = function(record)
    local victim = record.grabBy
    record.grabBy, record.grabAt, record.grabUntil = nil, nil, nil
    if record.state == 'grab' then record.state = 'hunting' end
    if victim then TriggerClientEvent('bs:z:grabbed', -1, record.id, victim, false) end
end

-- Grab clock. Four times a second is plenty for a 1.5s lunge.
CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        for _, record in pairs(Registry.zombies) do
            if record.grabBy then
                local vped = GetPlayerPed(record.grabBy)
                local gone = not vped or vped == 0 or not DoesEntityExist(vped)
                local dead = not gone and GetEntityHealth(vped) <= 0
                if gone or dead or now >= (record.grabUntil or 0) then
                    releaseGrab(record)
                end
            elseif record.state == 'grab' then
                -- 'grab' with nobody holding it (lost event): clear it so it never sticks.
                record.state = 'hunting'
            end
        end
    end
end)

-- Housekeeping

AddEventHandler('playerDropped', function()
    local src = source

    -- Forget their last known position
    lastKnownAt[src] = nil

    -- Everything this player was hosting needs a new host now, or it stands still until the next director pass
    for id in pairs(Registry.hostOf[src] or {}) do
        local record = Registry.zombies[id]
        if record then
            record.host = nil
            -- netOwner of a networked walker is only refreshed by sv_net's 500ms pass and still names the
            if record.ent and record.netOwner == src then
                local ok, owner = pcall(NetworkGetEntityOwner, record.ent)
                record.netOwner = (ok and owner and owner > 0 and owner ~= src) and owner or nil
            end
            assignHost(record)
        end
    end
    -- Release anyone this player was holding or being held by.
    for _, record in pairs(Registry.zombies) do
        if record.grabBy == src then releaseGrab(record) end
    end

    Registry.hostOf[src] = nil
    known[src] = nil
    killRate[src] = nil
    executionGate[src] = nil
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for key, at in pairs(Registry.cellDead) do
            if now >= at then Registry.cellDead[key] = nil end
        end
    end
end)

-- Reads

-- Safe zones as plain numbers. bs_building asks this before letting anyone barricade a camp shut.
exports('SafeZones', function()
    local out = {}
    for _, zone in ipairs(Zones.Safe or {}) do
        -- flag = a faction safezone flag; placement checks skip those, PvP and spawning do not
        out[#out + 1] = { id = zone.id, label = zone.label, radius = zone.radius, flag = zone.flag == true,
                          faction = zone.faction, kind = zone.kind,
                          x = zone.coords.x, y = zone.coords.y, z = zone.coords.z }
    end
    return out
end)

-- Same list plus the padded radius, for the Node Atlas panel
exports('InSafeZone', function(x, y, pad)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end
    for _, zone in ipairs(Zones.Safe or {}) do
        if Zones.Contains(zone, x, y, tonumber(pad) or 0.0) then return true, zone.label end
    end
    return false
end)

exports('SafeZonesPadded', function()
    local out = {}
    local pad = S.safeZonePadding or 55.0
    for _, zone in ipairs(Zones.Safe or {}) do
        out[#out + 1] = {
            id = zone.id, label = zone.label,
            x = zone.coords.x, y = zone.coords.y,
            radius = zone.radius, padded = zone.radius + pad,
        }
    end
    return out
end)

exports('Total', total)

-- Same count handed to the streaming planner, which enforces the global ceiling with it
ZStream = ZStream or {}
ZStream.LiveCount = total
exports('WorldSeed', function() return Registry.seed end)

exports('Snapshot', function()
    local byType, hosted = {}, {}
    for _, record in pairs(Registry.zombies) do
        byType[record.typeId] = (byType[record.typeId] or 0) + 1
        if record.host then hosted[record.host] = (hosted[record.host] or 0) + 1 end
    end
    return { total = total(), byType = byType, hosted = hosted, seed = Registry.seed }
end)

-- Is any server-tracked walker within radius of (x, y, z)?. Plain boolean.
exports('AnyNear', function(x, y, z, radius)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return false end
    radius = tonumber(radius) or 10.0

    for _, record in pairs(Registry.zombies) do
        local dx, dy, dz = record.x - x, record.y - y, record.z - z
        if (dx * dx + dy * dy + dz * dz) <= (radius * radius) then return true end
    end
    return false
end)

-- Nearest walker, for the staff menu

local function isStaff(src)
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return ok and admin == true
end

-- Staff spawn through the real pipeline

BSB.RegisterCallback('zombies:force', function(src, x, y, h, typeId, feeding, gz)
    if not isStaff(src) then return { ok = false, error = 'not staff' } end

    x, y = tonumber(x), tonumber(y)
    if not x or not y then return { ok = false, error = 'bad coordinates' } end

    if total() >= MAX_TOTAL then
        return { ok = false, error = ('world is at its ceiling (%d)'):format(MAX_TOTAL) }
    end

    typeId = Zombies.Types[typeId] and typeId or 'walker'
    local def = Zombies.Types[typeId]

    local model = (Zombies.Models or {})[1]
    if not model then return { ok = false, error = 'no models configured' } end

    local id = Registry.nextId
    Registry.nextId = id + 1

    local zhp = ZDiff.Health(def.health, x, y)
    local record = {
        id = id, cell = 'force:' .. id, typeId = typeId, model = model,
        x = x, y = y, z = (tonumber(gz) and gz > 1.0) and gz or 0.0, h = tonumber(h) or 0.0,
        -- Ground z from the admin client when known; otherwise the host probes it.
        needsGround = not (tonumber(gz) and gz > 1.0),
        hp = zhp, maxHp = zhp,
        reacher = false,
        -- The staff button can ask for one that is already feeding.
        feeding = feeding == true,
        born = GetGameTimer(),
    }

    -- As above, the server must agree from the first broadcast or the walker kneels and stands back up
    record.state = record.feeding and 'feeding' or 'idle'

    Registry.zombies[id] = record
    Registry.byCell[record.cell] = id
    liveGridPut(record)

    -- Stamped 'staff' because this path skips the distance floor
    noteBirth(record, 'staff')

    print(('^5[BS ZOMBIES]^7 staff force-spawn: id %d (%s, model %s%s) at %.1f %.1f')
        :format(id, typeId, tostring(model), record.feeding and ', FEEDING' or '', x, y))

    return { ok = true, id = id, model = model, typeId = typeId, feeding = record.feeding }
end)

-- Client reports that something ate its ped, or that it deleted an orphaned walker ped
Registry.orphans = 0

RegisterNetEvent('bs:z:orphan', function(ageMs)
    local src = source
    Registry.orphans = Registry.orphans + 1
    print(('^1[BeyondSurvival]^7 (zombies) client %s deleted an ORPHANED walker ped (alive %.0fs with no live entry) - %d so far this session. Something is failing inside spawn(); check that client\'s console for the throw.')
        :format(tostring(src), (tonumber(ageMs) or 0) / 1000.0, Registry.orphans))
end)

RegisterNetEvent('bs:z:pedlost', function(id, total, age)
    print(('^1[BS ZOMBIES]^7 client %s lost the PED for walker %s after %sms - %s so far this session. Nothing on the server removed it.')
        :format(tostring(source), tostring(id), tostring(age), tostring(total)))
end)

-- A client could not apply one of the natives that makes a walker a walker
RegisterNetEvent('bs:z:enginedeath', function(id, revives, maxHealth, cause, deathSource)
    id = tonumber(id)
    local record = Registry.zombies[id]
    if not record then return end
    if record.host ~= source then return end

    -- The cause is sent with the report and lands in fxserver.log, so it can be read after the fact.
    print(('^1[BS ZOMBIES]^7 client %s could not keep walker %d standing (%s revives, ped max health %s). '
        .. 'CAUSE: weapon hash %s, source %s. Removing the record.')
        :format(tostring(source), id, tostring(revives), tostring(maxHealth),
                tostring(cause), tostring(deathSource)))

    Registry.Remove(id, 'engine')
end)

RegisterNetEvent('bs:z:badnative', function(name, count, err)
    print(('^1[BS ZOMBIES]^7 client %s could not apply %s (%s occurrence(s)): %s - walkers on that client are missing that behaviour.')
        :format(tostring(source), tostring(name), tostring(count), tostring(err)))
end)

-- Client side of /zanim, so the clipset info lands in a file.
RegisterNetEvent('bs:z:animreport', function(text)
    print(('^5[BS ANIM]^7 client %s: %s'):format(tostring(source), tostring(text)))
end)

-- The lure: walkers nobody is simulating still hear you

-- Lure (see Settings.lure): a record with no host is frozen

-- Point every unhosted record within earshot at a noise.
-- @param x number
-- @param y number
-- @param radius number the noise's own carry, before lure.reachScale
function Registry.Lure(x, y, radius)
    local cfg = S.lure
    if not cfg or not cfg.enabled then return 0 end

    local reach = math.min((radius or 60.0) * (cfg.reachScale or 2.0),
                           cfg.maxReach or 450.0)
    local until_ = os.time() + (cfg.seconds or 180)
    local r2 = reach * reach
    local n = 0

    -- Uses nearbyZombies instead of a full scan: a gunshot at the reach ceiling only visits the buckets it overlaps
    for _, record in ipairs(nearbyZombies(x, y, reach)) do
        local dx, dy = x - record.x, y - record.y
        if (dx * dx + dy * dy) <= r2 then
            record.lureX, record.lureY = x, y
            record.lureUntil = until_
            n = n + 1
        end
    end

    return n
end

CreateThread(function()
    local TICK = 1000
    local last = os.clock()

    while true do
        Wait(TICK)

        local cfg = S.lure
        if not cfg or not cfg.enabled then goto continue end

        do
            -- Uses measured elapsed time, not an assumed tick length, so drift speed does not change with server load
            local now = os.clock()
            local dt = now - last
            last = now
            if dt <= 0 or dt > 10 then goto continue end

            local step = (cfg.speed or 1.15) * ZDiff.Mult('speed') * dt

            -- The lure stops at the spawn floor
            local floor = spawnFloor()
            local arrive2 = math.max(cfg.arriveAt or 0.0, floor) ^ 2
            local stamp = os.time()

            -- Players are gathered once per tick
            local crowd, cn = {}, 0
            for _, p in ipairs(playerPoints()) do
                cn = cn + 1
                crowd[cn] = p
            end
            local floor2 = floor * floor

            for _, record in pairs(Registry.zombies) do
                if record.lureUntil and not record.host then
                    if stamp > record.lureUntil then
                        record.lureX, record.lureY, record.lureUntil = nil, nil, nil
                    else
                        local dx = record.lureX - record.x
                        local dy = record.lureY - record.y
                        local d2 = dx * dx + dy * dy

                        if d2 <= arrive2 then
                            -- Arrived. It stays put until another noise, or until a player is close enough to host it.
                            record.lureX, record.lureY, record.lureUntil = nil, nil, nil
                        else
                            local d = math.sqrt(d2)
                            local nx = record.x + (dx / d) * step
                            local ny = record.y + (dy / d) * step

                            -- Would this step enter someone's spawn floor?
                            local blockedByPlayer = false
                            for i = 1, cn do
                                local pdx, pdy = nx - crowd[i].x, ny - crowd[i].y
                                if (pdx * pdx + pdy * pdy) < floor2 then
                                    blockedByPlayer = true
                                    break
                                end
                            end

                            if blockedByPlayer then
                                record.lureX, record.lureY, record.lureUntil = nil, nil, nil
                                goto nextLured
                            end

                            record.x = nx
                            record.y = ny

                            -- Provenance: records where the walker was placed from (see the ATTRIBUTION note at the top of this file)
                            record.movedBy = 'lure'
                            record.movedAt = GetGameTimer()

                            -- Z is left alone: the server has no collision (see needsGround)
                            record.needsGround = true
                            liveGridPut(record)
                        end
                    end
                end
                ::nextLured::
            end
        end

        ::continue::
    end
end)

BSB.RegisterCallback('zombies:nearest', function(src)
    if not isStaff(src) then return { ok = false, error = 'not staff' } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'no ped' } end

    local at = GetEntityCoords(ped)
    local best, bestD2 = nil, math.huge
    -- Up to 8 nearest ids so the client can pick one that is really drawn.
    local ranked = {}

    -- The count within streaming range matters as much as the nearest one: "14 walkers within 100m but none drawn" is a diagnosis
    local near = 0

    for _, record in pairs(Registry.zombies) do
        local dx, dy = record.x - at.x, record.y - at.y
        local d2 = dx * dx + dy * dy
        if d2 < bestD2 then best, bestD2 = record, d2 end
        if d2 <= (100.0 * 100.0) then near = near + 1 end
        if d2 <= (400.0 * 400.0) then ranked[#ranked + 1] = { d2 = d2, id = record.id } end
    end
    table.sort(ranked, function(a, b) return a.d2 < b.d2 end)
    local ids = {}
    for k = 1, math.min(#ranked, 8) do ids[k] = ranked[k].id end

    if not best then
        return { ok = false, error = 'there are no walkers in the world right now' }
    end

    -- Z is sent as is
    return {
        ok       = true,
        id       = best.id,
        x        = best.x,
        y        = best.y,
        z        = best.z,
        grounded = (best.z or 0.0) > 1.0,
        typeId   = best.typeId,
        state    = best.state,
        hp       = best.hp,
        maxHp    = best.maxHp,
        distance = math.sqrt(bestD2),
        near     = near,
        ids      = ids,

        -- Provenance, so staff next to a walker that should not be there can see where it came from without the server log
        bornBy   = best.bornBy,
        bornDist = best.bornDist,
        movedBy  = best.movedBy,
    }
end)


-- bs_events hooks

local function eventSpawn(x, y, typeId, opts)
    opts = type(opts) == 'table' and opts or {}
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil, 'coords' end
    if total() >= MAX_TOTAL then return nil, 'cap' end

    typeId = Zombies.Types[typeId] and typeId or 'walker'
    local def = Zombies.Types[typeId]
    local model = Zombies.PickModel(x, y, typeId)
    if not model then return nil, 'noModel' end

    local hp = math.floor(ZDiff.Health(def.health or 200, x, y) * math.max(0.1, tonumber(opts.hpScale) or 1.0))
    local id = Registry.nextId
    Registry.nextId = id + 1

    local record = {
        id = id, cell = 'event:' .. id, typeId = typeId, model = model,
        x = x, y = y, z = 0.0, h = math.random() * 360.0,
        needsGround = true,
        hp = hp, maxHp = hp,
        reacher = false, feeding = false,
        born = GetGameTimer(),
        event = tostring(opts.tag or 'event'),
        state = 'idle',
    }
    Registry.zombies[id] = record
    Registry.byCell[record.cell] = id
    liveGridPut(record)
    noteBirth(record, 'event')
    return id
end

-- Point every walker of tag at a spot (hosted: real nav task, unhosted: drift).
local function eventDrive(tag, x, y, z, seconds)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return 0 end
    local n, untilT = 0, os.time() + (tonumber(seconds) or 300)
    for _, record in pairs(Registry.zombies) do
        if record.event == tag and (record.hp or 1) > 0 then
            record.state = 'drawn'
            record.movedBy = 'event'
            if record.host then
                TriggerClientEvent('bs:z:draw', record.host, record.id, { x = x, y = y, z = tonumber(z) or 0.0 })
            else
                record.lureX, record.lureY, record.lureUntil = x, y, untilT
            end
            n = n + 1
        end
    end
    return n
end

local function eventCount(tag)
    local n = 0
    for _, record in pairs(Registry.zombies) do
        if record.event == tag then n = n + 1 end
    end
    return n
end

local function eventClear(tag, keep)
    local ids = {}
    for id, record in pairs(Registry.zombies) do
        if record.event == tag then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do
        if keep then Registry.zombies[id].event = nil else removeZombie(id, 'event') end
    end
    return #ids
end

exports('EventSpawn', eventSpawn)
exports('EventDrive', eventDrive)
exports('EventCount', eventCount)
-- keep = true: untag only, so the walkers stay and fall back to normal culling.
exports('EventClear', eventClear)
exports('EventNoise', function(x, y, z, loud, kind)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end
    loud = tonumber(loud) or 200.0
    if ZPOI and ZPOI.Publish then pcall(ZPOI.Publish, x, y, tonumber(z) or 0.0, loud, kind or 'event') end
    pcall(Registry.Lure, x, y, loud)
    return true
end)

-- Gadget damage (bs_gadgets turret)
exports('GadgetHit', function(src, id, damage, ox, oy, range, weapon)
    src, id = tonumber(src), tonumber(id)
    local record = id and Registry.zombies[id]
    if not src or not record or (record.hp or 0) <= 0 then return false end
    ox, oy, range = tonumber(ox), tonumber(oy), tonumber(range) or 0
    if not ox or not oy then return false end
    local dx, dy = record.x - ox, record.y - oy
    if (dx * dx + dy * dy) > (range + 3.0) ^ 2 then return false end
    damage = math.min(math.max(0, tonumber(damage) or 0), record.maxHp * 0.5, 200)
    if damage <= 0 then return false end
    applyHit(src, id, record, damage, false, tostring(weapon or 'turret'))
    return true
end)

-- /zsync: per client, records the server streams vs local peds that exist.
local syncCaller = nil
RegisterCommand('zsync', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    syncCaller = src
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        local n = 0
        for _ in pairs(known[id] or {}) do n = n + 1 end
        local line = ('[BS ZSYNC] %s (%d): server streams %d record(s)'):format(GetPlayerName(id) or '?', id, n)
        if ZNet and ZNet.enabled then
            line = line .. (' | networked peds within 424m: %d'):format(ZNet.NearCount(id))
        end
        print(line)
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { line } }) end
        TriggerClientEvent('bs:z:syncq', id)
    end
end, false)

RegisterNetEvent('bs:z:synca', function(live, peds, h, q, netVisible)
    local src = source
    local n = 0
    for _ in pairs(known[src] or {}) do n = n + 1 end
    if ZNet and ZNet.enabled then
        -- Networked: compare what the server holds near this player with the bsZombie peds that exist in that client's pool
        local srv = ZNet.NearCount(src)
        local vis = tonumber(netVisible) or 0
        local nline = ('[BS ZSYNC] %s (%d): NETWORKED server=%d near | client sees %d networked ped(s), adopted %d%s')
            :format(GetPlayerName(src) or '?', src, srv, vis, tonumber(live) or 0,
                    vis < srv and '  ^3(fewer: out of scope or still streaming)^7' or '')
        print(nline)
        if syncCaller and syncCaller ~= 0 then TriggerClientEvent('chat:addMessage', syncCaller, { args = { nline } }) end
    end
    local line = ('[BS ZSYNC] %s (%d): server=%d | client live=%d peds=%d held=%d queued=%d%s')
        :format(GetPlayerName(src) or '?', src, n, tonumber(live) or 0, tonumber(peds) or 0,
                tonumber(h) or 0, tonumber(q) or 0, (tonumber(peds) or 0) < n and '  ^1MISMATCH^7' or '')
    print(line)
    if syncCaller and syncCaller ~= 0 then TriggerClientEvent('chat:addMessage', syncCaller, { args = { line } }) end
end)

-- Staff /zkill: kill the walker in the crosshair, or every walker within a radius

local function zkillStaff(src)
    if src == 0 then return false end
    if isStaff(src) then return true end
    return IsPlayerAceAllowed(src, 'bs.admin') == true
end

-- Staff action line in bs_guard_log (kind admin).
local function zkillLog(src, detail)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local player = exports.bs_core:GetPlayer(src)
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), player and player.charId or nil,
          (GetPlayerName(src) or '?'):sub(1, 64), 'admin', 0, detail:sub(1, 512), c.x, c.y, c.z })
end

local function zkillSay(src, text)
    TriggerClientEvent('chat:addMessage', src, { args = { 'ZKILL', text } })
end

-- Same death path as a headshot kill, minus rewards; then the ped (or its corpse) is deleted.
local function zkillOne(src, id)
    local record = Registry.zombies[id]
    if not record then return false end
    local ent = record.ent
    record.hp = record.hp or 1
    applyHit(src, id, record, math.max(record.hp, 1), true, 'zkill', true)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        if ZNet then
            if ZNet.corpses then ZNet.corpses[ent] = nil end
            if ZNet.ents then ZNet.ents[ent] = nil end
            if ZNet.expected then ZNet.expected[ent] = 'zkill' end
        end
        DeleteEntity(ent)
    end
    return true
end

RegisterCommand('zkill', function(src, args)
    if not zkillStaff(src) then return end
    if tostring(args[1] or ''):lower() == 'radius' then
        local r = tonumber(args[2])
        if not r or r <= 0 then zkillSay(src, Lp(src, 'zed.zkill_usage')) return end
        r = math.min(r, 50.0)
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return end
        local at = GetEntityCoords(ped)
        local ids = {}
        for id, rec in pairs(Registry.zombies) do
            local dx, dy = (rec.x or 0) - at.x, (rec.y or 0) - at.y
            if dx * dx + dy * dy <= r * r then ids[#ids + 1] = id end
        end
        local n = 0
        for _, id in ipairs(ids) do if zkillOne(src, id) then n = n + 1 end end
        zkillLog(src, ('zkill radius %.0f: %d walkers'):format(r, n))
        zkillSay(src, Lp(src, 'zed.zkill_radius', { n = n, r = math.floor(r) }))
        return
    end
    TriggerClientEvent('bs:z:zkillcast', src)
end, false)

RegisterNetEvent('bs:z:zkillhit', function(id)
    local src = source
    if not zkillStaff(src) then return end
    id = tonumber(id)
    local record = id and Registry.zombies[id]
    if not record then zkillSay(src, Lp(src, 'zed.zkill_none')) return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local at = GetEntityCoords(ped)
    local dx, dy = (record.x or 0) - at.x, (record.y or 0) - at.y
    if dx * dx + dy * dy > 120.0 * 120.0 then return end
    local x, y, z = record.x or 0.0, record.y or 0.0, record.z or 0.0
    if zkillOne(src, id) then
        zkillLog(src, ('zkill walker %d at %.1f, %.1f, %.1f'):format(id, x, y, z))
        zkillSay(src, Lp(src, 'zed.zkill_done', { id = id }))
    end
end)
