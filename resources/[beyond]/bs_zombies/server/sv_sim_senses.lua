-- bs_zombies - sense ladder (server side)

ZSimSense = ZSimSense or {}

-- Choosing between noises: pick by score
ZSimSense.players = {}

--- [agentId] = { src, until_ } - damage memory, the top rung.
ZSimSense.hurtBy = {}

-- Cached, scored copy of the POI board
ZSimSense.board = {}

ZSimSense.stats = { evals = 0, noise = 0, sight = 0, scent = 0, damage = 0, vehicle = 0,
                    -- Cached, scored copy of the POI board, refreshed on its own slow thread so evaluations do not each walk the raw board
                    players = 0,
                    muted = 0,        -- ...of which are muted by ZOMBIE GODMODE
                    boardPoints = 0,  -- live noise points at the last board refresh
                    boardStale = 0,   -- points dropped as expired on that refresh
                    mutedSkips = 0,   -- sight/scent rungs skipped for a muted player
}

-- Staff "zombie godmode" toggle
local function isZombieMuted(src)
    local ok, bag = pcall(function() return Player(src).state end)
    if not ok or not bag then return false end
    local ok2, v = pcall(function() return bag.bsZombieGodmode end)
    return ok2 and v == true
end

-- Helpers, declared above first use (a local used before its declaration is a nil global in Lua 5.4)

local sqrt, cos, sin, atan, abs, deg, rad = math.sqrt, math.cos, math.sin, math.atan, math.abs, math.deg, math.rad

local function cfg() return Sim end

local function d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Smallest absolute angle between two bearings, 0..180 degrees.
local function angleDelta(a, b)
    local d = (a - b) % 360.0
    if d > 180.0 then d = 360.0 - d end
    return d
end

-- Player snapshot: one pass over connected players every 250ms, using server-safe natives only

local function vehicleOf(ped)
    -- Wrapped in pcall: a missing native should only cost the vehicle feature, not the resource.
    local ok, veh = pcall(GetVehiclePedIsIn, ped, false)
    if ok and veh and veh ~= 0 then return veh end
    return nil
end

local function snapshotPlayers()
    local now = GetGameTimer()
    local seen = {}

    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)
            if at then
                local prev = ZSimSense.players[src]
                local speed = 0.0
                if prev and prev.at and now > prev.at then
                    local dt = (now - prev.at) / 1000.0
                    if dt > 0.05 then
                        speed = sqrt(d2(at.x, at.y, prev.x, prev.y)) / dt
                        -- Teleports (respawn, admin tp) would read as huge speed and make the player the loudest thing on the map
                        if speed > 90.0 then speed = 0.0 end
                    else
                        speed = prev.speed or 0.0
                    end
                end

                local hOk, h = pcall(GetEntityHeading, ped)
                local veh = vehicleOf(ped)

                local st = prev and prev.stance or nil
                seen[src] = {
                    -- Sampled once per snapshot so evaluations do not each read a statebag.
                    muted = isZombieMuted(src),
                    x = at.x, y = at.y, z = at.z,
                    h = (hOk and h) or (prev and prev.h) or 0.0,
                    speed = speed,
                    veh = veh,
                    at = now,
                    -- Stance comes from the client report; absent = standing.
                    stance = st,
                    crouched = st and st.crouched or false,
                    prone = st and st.prone or false,
                    stealth = st and st.stealth or false,
                    mult = st and st.mult or 1.0,
                    name = GetPlayerName(src) or ('#' .. src),
                }
            end
        end
    end

    ZSimSense.players = seen

    local n, m = 0, 0
    for _, p in pairs(seen) do
        n = n + 1
        if p.muted then m = m + 1 end
    end
    ZSimSense.stats.players, ZSimSense.stats.muted = n, m
end

-- Names of players currently invisible to the sense ladder (used by /zsim).
function ZSimSense.MutedNames()
    local out, n = {}, 0
    for src, p in pairs(ZSimSense.players) do
        if p.muted then
            n = n + 1
            out[n] = ('%s (#%s)'):format(tostring(p.name or '?'), tostring(src))
        end
    end
    return out, n
end

-- Stance report from cl_sim_stance.lua
RegisterNetEvent('bs:sim:stance', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local p = ZSimSense.players[src]
    local st = {
        crouched = payload.crouched and true or false,
        prone = payload.prone and true or false,
        stealth = payload.stealth and true or false,
        -- Client stealth multiplier, clamped to 0.2..1.0 so it can only reduce visibility.
        mult = math.max(0.2, math.min(1.0, tonumber(payload.mult) or 1.0)),
        at = GetGameTimer(),
    }
    if p then
        p.stance = st
        p.crouched, p.prone, p.stealth, p.mult = st.crouched, st.prone, st.stealth, st.mult
    else
        ZSimSense.players[src] = { stance = st, crouched = st.crouched,
                                   prone = st.prone, stealth = st.stealth, mult = st.mult }
    end
end)

AddEventHandler('playerDropped', function()
    ZSimSense.players[source] = nil
end)

-- Noise board, read from ZPOI (sv_poi.lua)

local function refreshBoard()
    local out, n = {}, 0
    local now = os.time()

    -- Use ZPOI.Active() rather than the raw points array
    local points = (ZPOI and ZPOI.Active and ZPOI.Active()) or {}
    local raw = (ZPOI and ZPOI.points) or {}
    ZSimSense.stats.boardStale = math.max(0, #raw - #points)

    for i = 1, #points do
        local p = points[i]
        if p and p.x then
            n = n + 1
            out[n] = {
                x = p.x, y = p.y, z = p.z or 0.0,
                loud = p.loud or 60.0,
                reach = math.min(cfg().sense.hearMaxRange, p.reach or 200.0),
                at = p.at or now,
                kind = p.kind or 'noise',
                src = p.src,            -- may be nil; POIs are places, not people
                id = p.id,
            }
        end
    end

    -- Vehicles: one point per moving vehicle a player drives
    local V = cfg().vehicle
    if V.enabled then
        for src, p in pairs(ZSimSense.players) do
            if p.veh and p.x and (p.speed or 0) > 2.0 then
                local t = math.min(1.0, (p.speed or 0) / V.fullSpeed)
                n = n + 1
                out[n] = {
                    x = p.x, y = p.y, z = p.z or 0.0,
                    loud = 60.0 + 120.0 * t,
                    reach = V.baseRange + V.speedRange * t,
                    at = now, kind = 'vehicle', src = src, veh = true,
                }
            end
        end
    end

    ZSimSense.board = out
    ZSimSense.stats.boardPoints = n
end

-- Most interesting point within radius, ignoring line of sight. Used by far-field migration.
function ZSimSense.BestPointNear(x, y, radius)
    local best, bestScore = nil, 0.0
    local r2 = (radius or 300.0) ^ 2
    local S = cfg().score
    local now = os.time()

    for i = 1, #ZSimSense.board do
        local p = ZSimSense.board[i]
        local dd = d2(x, y, p.x, p.y)
        if dd <= r2 and dd <= (p.reach * p.reach) then
            local age = math.max(0, now - p.at)
            local recency = 0.5 ^ (age / S.halfLifeSeconds)
            local prox = 1.0 - (sqrt(dd) / math.max(1.0, p.reach)) * S.proximityWeight
            if prox < 0.05 then prox = 0.05 end
            local score = (p.loud ^ S.loudPower) * recency * prox
            if score > bestScore then best, bestScore = p, score end
        end
    end

    return best, bestScore
end

-- Sense rungs

-- Rung 2: sight
local function sightRange(agent, p, isNoisy)
    local S = cfg().sense
    local r = S.sightRange

    if p.prone then r = r * S.proneSightMultiplier
    elseif p.crouched or p.stealth then r = r * S.crouchSightMultiplier end

    if isNoisy then
        -- Making noise cancels the motion discount but not the stance one, so a crouched shooter is still hard to spot
        return r
    end

    if (p.speed or 0) < 0.6 then r = r * S.stillMultiplier end
    return r
end

local function canSee(agent, p, isNoisy)
    local S = cfg().sense
    local r = sightRange(agent, p, isNoisy)
    local dd = d2(agent.x, agent.y, p.x, p.y)
    if dd > r * r then return false end
    if dd < 1.0 then return true end

    local bearing = (deg(atan(p.y - agent.y, p.x - agent.x)) + 360.0) % 360.0
    return angleDelta(bearing, agent.h or 0.0) <= S.sightHalfAngle
end

-- Rung 3: scent. Defeated by sneaking, crouching, or being behind the zombie.
local function canSmell(agent, p)
    local S = cfg().sense
    local r = S.scentRange
    if p.crouched or p.prone or p.stealth then r = r * S.crouchScentMultiplier end

    local dd = d2(agent.x, agent.y, p.x, p.y)
    if dd > r * r then return false end
    if dd < 0.36 then return true end

    -- Behind the zombie = outside the scent arc = no scent.
    local bearing = (deg(atan(p.y - agent.y, p.x - agent.x)) + 360.0) % 360.0
    return angleDelta(bearing, agent.h or 0.0) <= S.scentHalfAngle
end

-- Damage, the top rung

-- Called only after the registry validates a hit (both damage paths).
function ZSimSense.ReportDamage(src, id)
    id = tonumber(id)
    if not id then return end

    local record = Registry and Registry.zombies and Registry.zombies[id]
    local agentId = record and record.nodeId
    if not agentId then return end

    ZSimSense.hurtBy[agentId] = {
        src = src,
        until_ = GetGameTimer() + (cfg().sense.damageTargetSeconds * 1000),
    }
    ZSimSense.stats.damage = ZSimSense.stats.damage + 1
end

-- Evaluate one zombie

function ZSimSense.Evaluate(agent, now)
    ZSimSense.stats.evals = ZSimSense.stats.evals + 1
    local S = cfg().sense

    -- Rung 4: damaged.
    local hurt = ZSimSense.hurtBy[agent.id]
    if hurt then
        if now < hurt.until_ then
            local p = ZSimSense.players[hurt.src]
            if p and p.x then
                return { kind = 'damage', src = hurt.src, x = p.x, y = p.y,
                         until_ = hurt.until_ }
            end
        else
            ZSimSense.hurtBy[agent.id] = nil
        end
    end

    -- Players currently making noise (any board entry names them)
    local noisy = nil
    for i = 1, #ZSimSense.board do
        local b = ZSimSense.board[i]
        if b.src then
            noisy = noisy or {}
            noisy[b.src] = true
        end
    end

    -- Rung 3: scent, above sight (see canSmell). p.muted is the staff zombie godmode flag (see isZombieMuted).
    for src, p in pairs(ZSimSense.players) do
        if p.muted then
            ZSimSense.stats.mutedSkips = ZSimSense.stats.mutedSkips + 1
        elseif p.x and canSmell(agent, p) then
            ZSimSense.stats.scent = ZSimSense.stats.scent + 1
            return { kind = 'scent', src = src, x = p.x, y = p.y,
                     until_ = now + S.huntMemorySeconds * 1000 }
        end
    end

    -- Rung 2: seen. Muted players are not seen.
    for src, p in pairs(ZSimSense.players) do
        if (not p.muted) and p.x and canSee(agent, p, noisy and noisy[src]) then
            ZSimSense.stats.sight = ZSimSense.stats.sight + 1
            return { kind = 'sight', src = src, x = p.x, y = p.y,
                     until_ = now + S.huntMemorySeconds * 1000 }
        end
    end

    -- Rung 1: heard. Gives a point, never a person.
    local best, bestScore, bestVisible = nil, 0.0, false
    local SC = cfg().score
    local wall = os.time()

    for i = 1, #ZSimSense.board do
        local b = ZSimSense.board[i]
        local dd = d2(agent.x, agent.y, b.x, b.y)
        local reach = math.max(S.hearMinRange, math.min(S.hearMaxRange, b.reach))
        if dd <= reach * reach then
            local age = math.max(0, wall - b.at)
            local recency = 0.5 ^ (age / SC.halfLifeSeconds)
            local prox = 1.0 - (sqrt(dd) / reach) * SC.proximityWeight
            if prox < 0.05 then prox = 0.05 end

            -- A point whose source this zombie can see outranks one it only heard
            local visible = false
            if b.src then
                local p = ZSimSense.players[b.src]
                if p and p.x then
                    local bearing = (deg(atan(p.y - agent.y, p.x - agent.x)) + 360.0) % 360.0
                    visible = angleDelta(bearing, agent.h or 0.0) <= S.sightHalfAngle
                end
            end

            local score = (b.loud ^ SC.loudPower) * recency * prox
            if visible then score = score * SC.visibleMultiplier end

            if score > bestScore then best, bestScore, bestVisible = b, score, visible end
        end
    end

    if not best then return nil end

    -- Vehicle leash: past followRange the point stops tracking the car and becomes a fixed
    if best.veh then
        local V = cfg().vehicle
        local dist = sqrt(d2(agent.x, agent.y, best.x, best.y))
        ZSimSense.stats.vehicle = ZSimSense.stats.vehicle + 1
        if dist > V.followRange then
            local ang = atan(best.y - agent.y, best.x - agent.x)
            return {
                kind = 'vehicle',
                x = agent.x + cos(ang) * V.driftDistance,
                y = agent.y + sin(ang) * V.driftDistance,
                until_ = now + V.driftSeconds * 1000,
                score = bestScore,
            }
        end
        return { kind = 'vehicle', x = best.x, y = best.y,
                 until_ = now + 15000, score = bestScore }
    end

    ZSimSense.stats.noise = ZSimSense.stats.noise + 1
    return {
        kind = 'noise', x = best.x, y = best.y,
        -- Held until the point is stale, not for a fixed time: a zombie 300m away needs about four minutes to arrive
        until_ = now + 240000,
        score = bestScore, visible = bestVisible, kind_src = best.kind,
    }
end

-- Threads: two fixed-cost passes (players, POI board); neither scales with zombie count.

CreateThread(function()
    while true do
        Wait(250)
        if Sim and Sim.enabled then pcall(snapshotPlayers) end
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        if Sim and Sim.enabled then pcall(refreshBoard) end
    end
end)

-- Sweep the damage memory (one entry per shot zombie) so it does not grow over a long uptime.
CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for id, h in pairs(ZSimSense.hurtBy) do
            if now > h.until_ then ZSimSense.hurtBy[id] = nil end
        end
    end
end)
