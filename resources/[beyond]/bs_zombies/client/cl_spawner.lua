-- bs_zombies - validated client spawner

ZSpawner = {
    -- The plan last received from sv_streaming.lua.
    plan = { nodes = {}, canSpawn = false, dryRun = true },

    --- [cellKey] = GetGameTimer() when a ray last reached that cell.
    observed = {},

    -- Reset and sent to the server every work pass
    reasons = { seen = 0, rayClear = 0, tooClose = 0, noSafeCoord = 0, safeZone = 0, tooFar = 0, noNode = 0,
                inView = 0, clumped = 0, nearPlayer = 0, queueDropped = 0, roof = 0, notReady = 0 },
    accepted = 0,

    -- The same counters, never reset. reasons and accepted are a per-pass window zeroed every workMs
    totals = { accepted = 0, attempts = 0, passes = 0,
               seen = 0, rayClear = 0, tooClose = 0, noSafeCoord = 0, safeZone = 0, tooFar = 0, noNode = 0,
               inView = 0, clumped = 0, nearPlayer = 0, queueDropped = 0, roof = 0 },

    -- Where this client placed walkers recently: { x, y, at } per accepted candidate, swept by age
    recent = {},
    queuedSources = {},
    -- Offers already used this plan; the server takes each offer once
    usedSources = {},

    -- Stagger queue
    queue = {},
}

-- Helpers
-- Each is declared above its first use

local function cellKey(x, y)
    local size = Streaming.observationCellSize
    return ('%d:%d'):format(math.floor(x / size), math.floor(y / size))
end

-- True when nothing solid stands between from and to
local function rayClear(fromX, fromY, fromZ, toX, toY, toZ, ignore)
    local handle = StartShapeTestLosProbe(fromX, fromY, fromZ, toX, toY, toZ, 17, ignore or 0, 7)
    for _ = 1, Streaming.rayPollFrames do
        local status, hit = GetShapeTestResult(handle)
        if status == 2 then return hit == false or hit == 0 end
        Wait(0)
    end
    return nil
end

-- Nearest road node within 70 m (path nodes stay loaded far beyond collision and navmesh)
local function roadNear(x, y, z)
    local ok, pos = GetClosestVehicleNode(x, y, z, 1, 3.0, 0)
    if ok and pos and pos.x and ((pos.x - x) ^ 2 + (pos.y - y) ^ 2) <= 70.0 * 70.0 then return pos end
    return nil
end

-- A point well above the nearest road is a roof (slopes allowed for)
local function aboveRoad(c, road)
    if not road then return false end
    local d = math.sqrt((c.x - road.x) ^ 2 + (c.y - road.y) ^ 2)
    return c.z > road.z + 4.0 + d * 0.15
end

local function aboveLowerSurface(c)
    local found, lower = GetGroundZFor_3dCoord(c.x, c.y, c.z - 3.0, false)
    return found and lower and c.z - lower > 3.0
end

-- Water at a standing point (sea, lakes, canals)
local function inWater(x, y, z)
    local okW, has, wz = pcall(GetWaterHeight, x, y, z + 2.0)
    if okW and has and tonumber(wz) and wz > z - 0.4 then return true end
    local okP, hit, hz = pcall(TestVerticalProbeAgainstAllWater, x, y, z + 2.0, 0)
    if okP and (hit == true or hit == 1) and tonumber(hz) and hz > z - 0.4 then return true end
    return false
end

-- The walkable level must match the road level next to the candidate (slopes allowed for).
-- That is what tells a bridge deck from the street below it, a tunnel floor from the road on top, and a roof from both.
local function onRoadLevel(c, road)
    local d = math.sqrt((c.x - road.x) ^ 2 + (c.y - road.y) ^ 2)
    return math.abs(c.z - road.z) <= 2.5 + d * 0.12
end

-- Somewhere a ped can stand near x,y on a real walkable level: navmesh, then ground probed from just above
-- the road level, then the road node itself. Never the player's height, a roof, mid-air or water.
-- Returns coords, or nil plus the reason
local function safeCoord(x, y, z)
    local road = roadNear(x, y, z)
    if not road then return nil, 'noRoad' end
    local baseZ = road.z
    RequestCollisionAtCoord(x, y, baseZ)
    local roofHit = false
    for _, flags in ipairs({ 16, 0 }) do
        local found, c = GetSafeCoordForPed(x, y, baseZ, true, flags)
        if found and c and ((c.x - x) ^ 2 + (c.y - y) ^ 2) <= 30.0 * 30.0 then
            if onRoadLevel(c, road) and not inWater(c.x, c.y, c.z) then return c end
            roofHit = true
        end
    end
    local found, gz = GetGroundZFor_3dCoord(x, y, baseZ + 3.0, false)
    if found and gz and gz > -100.0 then
        local c = vector3(x, y, gz + 0.15)
        if onRoadLevel(c, road) and not inWater(c.x, c.y, c.z) then return c end
        roofHit = true
    end
    -- The road node is a driveable surface; the owner still confirms the ground before the walker can move
    if not inWater(road.x, road.y, road.z) then return vector3(road.x, road.y, road.z + 0.15) end
    return nil, roofHit and 'roof' or 'water'
end

-- Same safe-zone rule as the server, reading Zones.Safe from config_zones.lua (a shared_script, so it exists on both sides)
local function inSafeZone(x, y)
    local padding = (Zombies and Zombies.Settings and Zombies.Settings.safeZonePadding)
        or Streaming.safeZonePaddingFallback
    for _, zone in ipairs((Zones and Zones.Safe) or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= ((zone.radius + padding) ^ 2) then return true end
    end
    return false
end

-- The placement gate
-- Candidates must pass three rules, kept as separate functions so the counters show which one refused

-- Every player this client can see, as { ped, coords, isLocal }
local function visiblePlayers()
    local out, n = {}, 0
    local me = PlayerId()

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            n = n + 1
            out[n] = {
                ped = ped,
                coords = GetEntityCoords(ped),
                isLocal = (player == me),
            }
        end
    end

    return out, n
end

-- Rule one: far enough from every player this client can see
local function farEnoughFromPlayers(x, y, players, count)
    local cfg = Streaming.Placement
    local minD = (cfg and cfg.minPlayerDistance) or 0.0
    if minD <= 0 then return true end
    local min2 = minD * minD

    for i = 1, count do
        local dx, dy = x - players[i].coords.x, y - players[i].coords.y
        if (dx * dx + dy * dy) < min2 then return false end
    end
    return true
end

-- Rule two: not on top of something just spawned
local function farEnoughFromRecent(x, y)
    local cfg = Streaming.Placement
    local minSep = (cfg and cfg.minSpawnSeparation) or 0.0
    if minSep <= 0 then return true end

    local now = GetGameTimer()
    local memory = (cfg and cfg.separationMemoryMs) or 45000
    local kept, n, ok = {}, 0, true

    for i = 1, #ZSpawner.recent do
        local entry = ZSpawner.recent[i]
        if (now - entry.at) <= memory then
            n = n + 1
            kept[n] = entry
            local dx, dy = x - entry.x, y - entry.y
            if (dx * dx + dy * dy) < (minSep * minSep) then ok = false end
        end
    end

    ZSpawner.recent = kept
    return ok
end

-- Rule three: not inside anybody's view
local function hiddenFromEveryone(x, y, z, players, count)
    local cfg = Streaming.Placement
    if not cfg then return true end

    local sphere = cfg.viewSphereRadius or 2.0

    -- The frustum can report an occluded point as hidden, so also keep new walkers out of the direction the player is facing
    local cam = GetGameplayCamCoord()
    local dx, dy = x - cam.x, y - cam.y
    local distance2 = dx * dx + dy * dy
    local forwardRange = cfg.localViewRange or 300.0
    if distance2 > 0.01 and distance2 <= forwardRange * forwardRange then
        local yaw = math.rad(GetGameplayCamRot(2).z)
        local dot = (-dx * math.sin(yaw) + dy * math.cos(yaw)) / math.sqrt(distance2)
        if dot >= math.cos(math.rad(cfg.localViewHalfAngle or 65.0))
           and rayClear(cam.x,cam.y,cam.z,x,y,z+(Streaming.targetHeight or 0.8),PlayerPedId()) ~= false then
            return false
        end
    end

    -- Test 1: exact and cheapest, so first.
    if IsSphereVisible(x, y, z + (Streaming.targetHeight or 0.8), sphere)
       and rayClear(cam.x,cam.y,cam.z,x,y,z+(Streaming.targetHeight or 0.8),PlayerPedId()) ~= false then
        return false
    end

    -- Test 2: approximate, for players whose peds we have.
    local halfAngle = cfg.remoteViewHalfAngle or 75.0
    local range = cfg.remoteViewRange or 180.0
    local range2 = range * range
    -- cos of the half angle: the dot-product threshold a candidate must stay below to be outside the cone
    local cosLimit = math.cos(math.rad(halfAngle))

    for i = 1, count do
        local p = players[i]
        if not p.isLocal then
            local dx, dy = x - p.coords.x, y - p.coords.y
            local d2 = dx * dx + dy * dy

            if d2 <= range2 and d2 > 0.01 then
                local forward = GetEntityForwardVector(p.ped)
                local flen = math.sqrt(forward.x * forward.x + forward.y * forward.y)

                if flen < 0.01 then
                    -- Unknown facing: fail on the safe side (see the note above).
                    if cfg.refuseOnUnknownRemote then return false end
                else
                    local d = math.sqrt(d2)
                    -- Both vectors flattened and normalised, then a dot product (cos of the angle between his view and the walker)
                    local dot = ((dx / d) * (forward.x / flen)) + ((dy / d) * (forward.y / flen))
                    if dot >= cosLimit
                       and rayClear(p.coords.x,p.coords.y,p.coords.z+(Streaming.eyeHeight or 0.75),
                           x,y,z+(Streaming.targetHeight or 0.8),p.ped) ~= false then return false end
                end
            end
        end
    end

    return true
end

-- The whole gate, cheapest first. Returns true, or false and the reason key.
local function placementAllows(x, y, z, players, count, reserved)
    if not farEnoughFromPlayers(x, y, players, count) then return false, 'nearPlayer' end
    if not reserved and not farEnoughFromRecent(x, y) then return false, 'clumped' end
    if not hiddenFromEveryone(x, y, z, players, count) then return false, 'inView' end
    return true
end

-- One candidate, or nil and the refusal reason
local function candidateFor(node, attempt)
    local origin = GetEntityCoords(PlayerPedId())
    local seed = (node.id * 73856093 + attempt * 19349663 + GetGameTimer()) % 2147483647
    local angle = (seed % 1000) / 1000 * math.pi * 2
    local x,y
    local offset = math.min(12.0, tonumber(node.radius) or 12.0) * ((seed % 977) / 977)
    x,y = node.x + math.cos(angle)*offset, node.y + math.sin(angle)*offset
    -- The node's own level when it has one; otherwise the player's height only picks which road level is nearest
    local coords, bad = safeCoord(x,y,(tonumber(node.z) and node.z > 1.0) and node.z or origin.z)
    if not coords then return nil, bad or 'noSafeCoord' end
    if node.mode == 'simulation' and (coords.x-node.x)^2+(coords.y-node.y)^2 > 60^2 then
        return nil,'tooFar'
    end
    if inSafeZone(coords.x,coords.y) then return nil,'safeZone' end
    local players,count = visiblePlayers()
    local allowed,why = placementAllows(coords.x,coords.y,coords.z,players,count)
    if not allowed then return nil,why end
    -- Out of camera view is already hidden
    return coords, (math.deg(angle)+90)%360
end

function ZSpawner.Observe()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    local origin = GetEntityCoords(ped)
    local eyeZ = origin.z + Streaming.eyeHeight
    local now = GetGameTimer()

    -- Cache only the current camera cone
    local camera = GetGameplayCamRot(2)
    local rays = Streaming.observationFovRays or 5
    local halfFov = Streaming.observationHalfFov or 55.0
    for index = 0, rays - 1 do
        local fraction = rays == 1 and 0.5 or (index / (rays - 1))
        local angle = math.rad(camera.z + (-halfFov + (fraction * halfFov * 2.0)))
        for _, distance in ipairs(Streaming.observeDistances) do
            local tx = origin.x - math.sin(angle) * distance
            local ty = origin.y + math.cos(angle) * distance
            if rayClear(origin.x, origin.y, eyeZ, tx, ty, origin.z + Streaming.targetHeight, ped) then
                ZSpawner.observed[cellKey(tx, ty)] = now
            end
        end
    end

    for key, stamp in pairs(ZSpawner.observed) do
        if now - stamp > Streaming.observationMemoryMs then ZSpawner.observed[key] = nil end
    end
end

local spawnAllowedNow

-- Work: turn the current plan into validated candidates. spawnPerPlan caps how many one pass may
function ZSpawner.Work()
    local plan = ZSpawner.plan
    if not plan.canSpawn then return end

    -- Counted before any early return, so 'ran and found nothing' can be told from 'never ran'.
    ZSpawner.totals.passes = ZSpawner.totals.passes + 1

    local sent = 0
    -- Not ready or the pool is full: candidates would only age out in the queue
    if not plan.dryRun and not spawnAllowedNow() then
        ZSpawner.reasons.notReady = (ZSpawner.reasons.notReady or 0) + 1
        return
    end
    local room = ((Streaming.Stagger or {}).maxQueued or 8) - #ZSpawner.queue

    for _, node in ipairs(plan.nodes or {}) do
        if room <= 0 then return end
        if ZSpawner.queuedSources[node.id] or ZSpawner.usedSources[node.id] then
            -- One local candidate per outstanding server offer.
        elseif not node.id then
            ZSpawner.reasons.noNode = ZSpawner.reasons.noNode + 1
        else
            for slot = 1, (node.need or 0) do
                if sent >= Streaming.spawnPerPlan then return end

                -- candidateFor returns (coords, heading) on success and (nil, reasonKey) on refusal
                local coords, second
                for attempt = 1, Streaming.candidateAttempts do
                    coords, second = candidateFor(node, attempt + slot * 11)
                    if coords then break end
                    -- Count every refused attempt, not just the last of a slot: /zstream reports what the world is refusing
                    ZSpawner.totals.attempts = ZSpawner.totals.attempts + 1
                    if second and ZSpawner.reasons[second] then
                        ZSpawner.reasons[second] = ZSpawner.reasons[second] + 1
                        ZSpawner.totals[second] = (ZSpawner.totals[second] or 0) + 1
                    end
                end

                if coords then
                    local heading = second
                    ZSpawner.accepted = ZSpawner.accepted + 1
                    ZSpawner.totals.accepted = ZSpawner.totals.accepted + 1
                    sent = sent + 1

                    if heading == nil then heading = 0.0 end

                    -- The line that sends the candidate
                    if not plan.dryRun then
                        local st = Streaming.Stagger or {}
                        if #ZSpawner.queue >= (st.maxQueued or 8) then
                            ZSpawner.reasons.queueDropped = ZSpawner.reasons.queueDropped + 1
                            ZSpawner.totals.queueDropped = (ZSpawner.totals.queueDropped or 0) + 1
                        else
                            ZSpawner.queuedSources[node.id] = true
                            ZSpawner.usedSources[node.id] = true
                            room = room - 1
                            ZSpawner.queue[#ZSpawner.queue + 1] = {
                                nodeId = node.id,
                                x = coords.x, y = coords.y, z = coords.z,
                                heading = heading,
                                mode = node.mode or 'hidden',
                                at = GetGameTimer(),
                            }

                            -- Reserved when queued, not when sent
                            ZSpawner.recent[#ZSpawner.recent + 1] =
                                { x = coords.x, y = coords.y, at = GetGameTimer() }
                        end
                    end
                end
            end
        end
    end
end

-- Wiring

RegisterNetEvent('bs:zs:plan', function(plan)
    if not Streaming.enabled then return end
    ZSpawner.plan = (type(plan) == 'table') and plan or { nodes = {}, canSpawn = false, dryRun = true }
    ZSpawner.usedSources = {}
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Nothing to clean up: this file owns no entity.
    ZSpawner.observed = {}
    ZSpawner.queue = {}
    ZSpawner.recent = {}
end)

CreateThread(function()
    -- Read once at start, like the server thread
    if not Streaming.enabled then return end

    -- The observation loop runs even when this client is not its cluster's coordinator
    while true do
        Wait(Streaming.observeMs)
        local ok, err = pcall(ZSpawner.Observe)
        if not ok then
            print(('^1[BS STREAM]^7 observe pass failed: %s'):format(tostring(err)))
            Wait(5000)
        end
    end
end)

-- Stagger thread: one walker at a time with jitter
function spawnAllowedNow()
    local PG = Streaming.PoolGuard or {}
    if not (Zed and Zed.ready and Zed.readyAt) then return false end
    if GetGameTimer() - Zed.readyAt < (PG.joinSyncMs or 6000) then return false end
    if (Zed.count or 0) >= (PG.clientMaxLocal or 40) then return false end
    local ok, list = pcall(GetGamePool, 'CPed')
    if ok and type(list) == 'table' and #list >= (PG.clientPedLimit or 180) - 10 then return false end
    return true
end

CreateThread(function()
    if not Streaming.enabled then return end

    while true do
        local st = Streaming.Stagger or {}
        local minGap = st.minGapMs or 700
        local maxGap = st.maxGapMs or 2200
        if maxGap < minGap then maxGap = minGap end

        Wait(math.random(minGap, maxGap))

        local entry = table.remove(ZSpawner.queue, 1)
            if entry then ZSpawner.queuedSources[entry.nodeId] = nil end
        if entry then
            local age = GetGameTimer() - entry.at
            if age > (st.maxAgeMs or 4000) then
                -- Stale: the player has had time to turn around, so a point that was out of view is now a guess
                ZSpawner.reasons.queueDropped = ZSpawner.reasons.queueDropped + 1
                ZSpawner.totals.queueDropped = (ZSpawner.totals.queueDropped or 0) + 1
            elseif not spawnAllowedNow() then
                -- not synced yet, or ped pool / local cap too full
                ZSpawner.totals.poolRefused = (ZSpawner.totals.poolRefused or 0) + 1
            else
                local players, count = visiblePlayers()
                local allowed, why = placementAllows(entry.x,entry.y,entry.z,players,count,true)
                if allowed then
                    TriggerServerEvent('bs:zs:spawn', entry.nodeId,
                    { x = entry.x, y = entry.y, z = entry.z },
                    entry.heading, entry.mode)
                else
                    ZSpawner.reasons[why] = (ZSpawner.reasons[why] or 0) + 1
                end
            end
        end
    end
end)

CreateThread(function()
    if not Streaming.enabled then return end

    while true do
        Wait(Streaming.workMs)

        local ok, err = pcall(ZSpawner.Work)
        if not ok then
            print(('^1[BS STREAM]^7 work pass failed: %s'):format(tostring(err)))
            Wait(5000)
        end

        -- Report and reset
        TriggerServerEvent('bs:zs:report', {
            accepted = ZSpawner.accepted,
            reasons = ZSpawner.reasons,
        })

        ZSpawner.accepted = 0
        for key in pairs(ZSpawner.reasons) do ZSpawner.reasons[key] = 0 end
    end
end)

CreateThread(function()
    if not Streaming.enabled then return end

    while true do
        Wait(Streaming.telemetryMs)

        -- Counts the whole ped pool, not just walkers: a client near 190 peds is in trouble whoever spawned them
        local ok, list = pcall(GetGamePool, 'CPed')
        local peds = (ok and type(list) == 'table') and #list or 0
        -- Filler walkers (cl_filler.lua) give way to networked ones on their own, so they do not lower this budget
        if Zed and Zed.FillerCount then peds = math.max(0, peds - Zed.FillerCount()) end

        TriggerServerEvent('bs:zs:tele', {
            fps = 1.0 / math.max(GetFrameTime(), 0.001),
            pedCount = peds,
            liveZombies = Zed and Zed.count or 0,
        })
    end
end)

-- Client half of /zdiag
RegisterNetEvent('bs:zs:diag', function()
    local observed = 0
    for _ in pairs(ZSpawner.observed) do observed = observed + 1 end

    local plan = ZSpawner.plan or {}
    local t = ZSpawner.totals or {}

    -- Totals, not the per-pass window (see ZSpawner.totals), which is zeroed every second.
    local need = 0
    for _, node in ipairs(plan.nodes or {}) do need = need + (node.need or 0) end

    TriggerServerEvent('bs:zs:diagreply', {
        hasPlan  = plan.nodes ~= nil,
        canSpawn = plan.canSpawn and true or false,
        dryRun   = plan.dryRun and true or false,
        nodes    = plan.nodes and #plan.nodes or 0,
        need     = need,
        observed = observed,
        passes   = t.passes or 0,
        attempts = t.attempts or 0,
        accepted = t.accepted or 0,

        -- How many accepted candidates only passed via the open-ground fallback (Sim.spawn.openGroundFallback)
        openGround  = t.openGround or 0,

        seen        = t.seen or 0,
        rayClear    = t.rayClear or 0,
        noSafeCoord = t.noSafeCoord or 0,
        safeZone    = t.safeZone or 0,
        tooFar      = t.tooFar or 0,
        noNode      = t.noNode or 0,

        -- The placement gate's own refusals. inView dominating is the gate working
        inView       = t.inView or 0,
        clumped      = t.clumped or 0,
        nearPlayer   = t.nearPlayer or 0,
        queueDropped = t.queueDropped or 0,
        queued       = #ZSpawner.queue,
    })
end)
