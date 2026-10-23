-- bs_zombies - point-of-interest board: where a sound was, and who is walking to it

ZPOI = ZPOI or {}

--- [n] = { x, y, z, loud, kind, at (os.time), reach, id, drawn, announcedAt }
ZPOI.points = {}
ZPOI.nextId = 1

--- Rolling counters for /zpoi and /zwhy.
ZPOI.stats = {
    published = 0, merged = 0, rejected = 0, evicted = 0,
    drawnHosted = 0, drawnUnhosted = 0, hordes = 0,
}

-- Helpers

local function cfg()
    return (Noise and Noise.POI) or nil
end

local function enabled()
    return Noise and Noise.enabled and cfg() ~= nil
end

-- How far this point reaches, in metres
local function reachFor(loud)
    local c = cfg()
    local scale = (c and c.reachScale) or 1.0
    local cap = (c and c.maxReach) or 520.0
    return math.min(cap, math.max(1.0, (loud or 60.0) * scale))
end

-- Squared 2D distance. 2D everywhere in this resource that a record is involved
local function d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Evict the quietest point, not the oldest, so a quiet shot cannot push a helicopter off the board
local function evictQuietest()
    local worst, worstIdx = nil, nil
    for i = 1, #ZPOI.points do
        local p = ZPOI.points[i]
        if not worst or p.loud < worst.loud then worst, worstIdx = p, i end
    end
    if worstIdx then
        table.remove(ZPOI.points, worstIdx)
        ZPOI.stats.evicted = ZPOI.stats.evicted + 1
    end
end

-- Publishing

-- Publish a point of interest
-- @param x,y,z where the sound was
-- @param loud the noise's carry in metres
-- @param kind 'gunshot', 'horn', 'whistle', ... for the readout only
-- @param src server id of the player who made the sound, or nil (used by sv_sim_senses.lua for the visibility score, never to target someone)
-- @return the point, or nil and a reason
-- Quiet sounds return nil: they are handled locally in cl_ai.lua, the board is for sounds worth crossing a town for
function ZPOI.Publish(x, y, z, loud, kind, src)
    if not enabled() then return nil, 'disabled' end
    local c = cfg()

    x, y = tonumber(x), tonumber(y)
    loud = tonumber(loud) or 0.0
    if not x or not y then
        ZPOI.stats.rejected = ZPOI.stats.rejected + 1
        return nil, 'coords'
    end

    if loud < (c.minLoudness or 45.0) then
        ZPOI.stats.rejected = ZPOI.stats.rejected + 1
        return nil, 'quiet'
    end

    local now = os.time()

    -- Merge: a magazine fired from one spot is one point, not thirty
    local mergeR = c.mergeRadius or 35.0
    for i = 1, #ZPOI.points do
        local p = ZPOI.points[i]
        if d2(x, y, p.x, p.y) <= (mergeR * mergeR) then
            -- The louder loudness and the newer timestamp
            if loud > p.loud then
                p.loud = loud
                p.reach = reachFor(loud)
                p.kind = kind or p.kind
                -- The louder contributor owns the point's attribution too: a rifle shot inside a footstep's merge radius is the rifle
                p.src = tonumber(src) or p.src
            end
            if not p.src then p.src = tonumber(src) end
            p.at = now
            p.hits = (p.hits or 1) + 1
            ZPOI.stats.merged = ZPOI.stats.merged + 1
            return p
        end
    end

    if #ZPOI.points >= (c.maxPoints or 48) then evictQuietest() end

    local point = {
        id = ZPOI.nextId,
        x = x, y = y, z = tonumber(z) or 0.0,
        loud = loud, kind = kind or 'noise',
        src = tonumber(src),
        at = now, hits = 1,
        reach = reachFor(loud),
        drawn = 0,
        lastDrawAt = 0,
        announcedAt = 0,
    }
    ZPOI.nextId = ZPOI.nextId + 1

    ZPOI.points[#ZPOI.points + 1] = point
    ZPOI.stats.published = ZPOI.stats.published + 1
    return point
end

-- How long a point stays interesting, scaled by loudness above the publish threshold
local function lifetimeOf(p)
    local c = cfg()
    local base = (c and c.lifetimeSeconds) or 45
    local scale = (c and c.lifetimeLoudScale) or 2.5
    local floor_ = (c and c.minLoudness) or 45.0
    local over = math.max(0.0, (p.loud - floor_) / math.max(1.0, floor_))
    return base * (1.0 + math.min(scale, over))
end

-- The live board, newest first
function ZPOI.Active()
    local out = {}
    local now = os.time()
    for i = 1, #ZPOI.points do
        local p = ZPOI.points[i]
        if (now - p.at) <= lifetimeOf(p) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- Loudest live point this coordinate can hear (returns point and distance, or nil)
function ZPOI.LoudestNear(x, y, radius)
    if not enabled() then return nil end
    local best, bestD = nil, nil
    local r2 = radius and (radius * radius) or nil
    local now = os.time()

    for i = 1, #ZPOI.points do
        local p = ZPOI.points[i]
        if (now - p.at) <= lifetimeOf(p) then
            local dd = d2(x, y, p.x, p.y)
            if not r2 or dd <= r2 then
                if not best or p.loud > best.loud then best, bestD = p, dd end
            end
        end
    end

    if not best then return nil end
    return best, math.sqrt(bestD)
end

-- The driver

-- Re-point on a slow tick for as long as a point is alive
local DRIVE_TICK = 2500

-- Point one record at p unless it is already committed to something better
local function pointRecordAt(record, p, now)
    local inv = (Noise and Noise.Investigate) or {}

    if record.poiId == p.id then
        -- Already walking to this one
        record.poiUntil = now + math.floor((inv.maxCommitMs or 300000) / 1000)
        return nil
    end

    if inv.repointNeedsLouder ~= false
       and record.poiUntil and record.poiUntil > now
       and (record.poiLoud or 0.0) >= p.loud then
        -- Committed to something at least as loud. Leave it alone.
        return nil
    end

    record.poiId = p.id
    record.poiLoud = p.loud
    record.poiX, record.poiY, record.poiZ = p.x, p.y, p.z
    record.poiUntil = now + math.floor((inv.maxCommitMs or 300000) / 1000)

    -- Provenance: movedBy is read by the CLOSE ARRIVAL tripwire in sv_registry and by /zwhy
    record.movedBy = 'poi'
    record.state = 'drawn'

    if record.host then
        -- Hosted: the client gets a real navigation task through goDrawn in cl_ai.lua
        TriggerClientEvent('bs:z:draw', record.host, record.id,
            { x = p.x, y = p.y, z = p.z })
        return 'hosted'
    end

    -- Unhosted: nobody simulates it, so the server drifts it in a straight line
    record.lureX, record.lureY = p.x, p.y
    record.lureUntil = record.poiUntil
    return 'unhosted'
end

--- Every record that should be walking to p, pointed at it.
local function drivePoint(p, now)
    if not (Registry and Registry.NearbyZombies) then return 0, 0 end

    local hosted, unhosted = 0, 0
    local near = Registry.NearbyZombies(p.x, p.y, p.reach)
    local r2 = p.reach * p.reach

    for i = 1, #near do
        local record = near[i]
        -- NearbyZombies works in grid buckets and over-returns at the edges; the exact distance test is here
        if d2(record.x, record.y, p.x, p.y) <= r2 then
            local how = pointRecordAt(record, p, now)
            if how == 'hosted' then hosted = hosted + 1
            elseif how == 'unhosted' then unhosted = unhosted + 1 end
        end
    end

    return hosted, unhosted
end

-- Convergence: a horde is something we NOTICE

-- A horde is an observation, not a spawn: count records within radius of a live point that are stamped as heading for it
local function checkConvergence(p, now)
    local h = (Noise and Noise.Horde) or {}
    if not h.enabled then return 0 end

    local radius = h.radius or 90.0
    local r2 = radius * radius
    local n = 0

    for _, record in ipairs(Registry.NearbyZombies(p.x, p.y, radius)) do
        if record.poiId == p.id and d2(record.x, record.y, p.x, p.y) <= r2 then
            n = n + 1
        end
    end

    p.converged = n

    if n >= (h.count or 12)
       and (now - (p.announcedAt or 0)) >= (h.announceCooldownSeconds or 120) then
        p.announcedAt = now
        ZPOI.stats.hordes = ZPOI.stats.hordes + 1
        -- Remembered for the atlas hordes layer (sv_director DirectorState).
        ZHordes = ZHordes or {}
        ZHordes['poi:' .. p.id] = { source = 'converged', x = p.x, y = p.y, size = n,
                                    kind = p.kind, startedAt = os.time(), endsAt = os.time() + 120 }

        print(('^1[BS POI]^7 HORDE OBSERVED: %d walkers converged on point %d (%s, %.0fm carry) at %.1f %.1f - nothing was spawned to make this happen')
            :format(n, p.id, tostring(p.kind), p.loud, p.x, p.y))

        -- Warn whoever stands near enough to the gathered crowd.
        for _, id in ipairs(GetPlayers()) do
            id = tonumber(id)
            local ped = id and GetPlayerPed(id)
            if ped and ped ~= 0 then
                local at = GetEntityCoords(ped)
                if d2(at.x, at.y, p.x, p.y) <= (radius * 3.0) * (radius * 3.0) then
                    TriggerClientEvent('bs:z:horde', id, {
                        coords = { x = p.x, y = p.y, z = p.z },
                        -- No warning delay: this is not coming, it is here.
                        warning = 0,
                        duration = 120,
                    })
                end
            end
        end
    end

    return n
end

-- The tick

CreateThread(function()
    while true do
        Wait(DRIVE_TICK)

        if enabled() and Registry and Registry.NearbyZombies then
            local now = os.time()
            local keep, kn = {}, 0

            for i = 1, #ZPOI.points do
                local p = ZPOI.points[i]

                if (now - p.at) <= lifetimeOf(p) then
                    local hosted, unhosted = drivePoint(p, now)
                    p.drawn = hosted + unhosted
                    p.lastDrawAt = now
                    ZPOI.stats.drawnHosted = ZPOI.stats.drawnHosted + hosted
                    ZPOI.stats.drawnUnhosted = ZPOI.stats.drawnUnhosted + unhosted

                    checkConvergence(p, now)

                    kn = kn + 1
                    keep[kn] = p
                else
                    -- Expired: walkers heading for it are not recalled
                end
            end

            ZPOI.points = keep
        end
    end
end)

-- /zpoi - board readout

local function emit(src, line)
    if src == 0 then print(line) else TriggerClientEvent('chat:addMessage', src, { args = { line } }) end
end

RegisterCommand('zpoi', function(src)
    src = tonumber(src) or 0

    if not enabled() then
        emit(src, '^1[BS POI]^7 Noise.enabled is false in config_noise.lua - the migration model is OFF and noise still feeds population the old way.')
        return
    end

    local live = ZPOI.Active()
    emit(src, ('^5[BS POI]^7 %d live point(s). published=%d merged=%d rejected(quiet)=%d evicted=%d | drawn hosted=%d unhosted=%d | hordes observed=%d')
        :format(#live, ZPOI.stats.published, ZPOI.stats.merged, ZPOI.stats.rejected,
                ZPOI.stats.evicted, ZPOI.stats.drawnHosted, ZPOI.stats.drawnUnhosted,
                ZPOI.stats.hordes))

    if #live == 0 then
        emit(src, '   nothing on the board. Make a loud noise (a gunshot carries ~340m) and run this again within a minute.')
        return
    end

    local now = os.time()
    for i = 1, math.min(10, #live) do
        local p = live[i]
        emit(src, ('   #%d %-9s loud=%.0fm reach=%.0fm age=%ds hits=%d drawn=%d converged=%d at %.0f %.0f')
            :format(p.id, tostring(p.kind), p.loud, p.reach, now - p.at,
                    p.hits or 1, p.drawn or 0, p.converged or 0, p.x, p.y))
    end

    emit(src, '   drawn = walkers pointed at it this tick. converged = walkers standing on it. Neither number was spawned.')
end, false)

-- Cleanup

-- A restart must not leave records stamped with points from a board that no longer exists, or those walkers never wander again
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if not (Registry and Registry.zombies) then return end

    for _, record in pairs(Registry.zombies) do
        record.poiId, record.poiLoud, record.poiUntil = nil, nil, nil
        record.poiX, record.poiY, record.poiZ = nil, nil, nil
    end
end)
