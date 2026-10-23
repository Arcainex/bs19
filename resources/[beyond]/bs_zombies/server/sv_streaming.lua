-- bs_zombies - streaming planner

ZStream = ZStream or {} -- preserve Registry-installed LiveCount

-- [source] = { fps, pedCount, ping, updatedAt } as last reported by the client.
ZStream.telemetry = {}

-- [coordinator source] = budget that cluster is allowed
ZStream.adaptive = {}

-- [source] = { anchorX, anchorY, arrivalUntil }. See arrivalOpen().
ZStream.observerState = {}

-- [source] = { [nodeId] = expiryMs }. Permit that lets a client place a candidate around a node instead of behind cover. Issued and expired here, checked on spawn.
ZStream.arrivalPermits = {}
ZStream.offers = {}
ZStream.selectionCursor = {}
ZStream.nextPlanId = 0

-- Diagnostic only. Everything /zstream prints comes from here.
ZStream.stats = {
    plans = 0,
    clusters = 0,
    lastPlanMs = 0,
    offered = 0,          -- candidates the planner asked clients to find
    accepted = 0,         -- candidates a client validated and reported back
    rejected = 0,         -- candidates a client refused, total
    -- Rejection breakdown, so a rule that refuses everything can be told apart from one that works
    reasons = { seen = 0, rayClear = 0, noSafeCoord = 0, safeZone = 0, tooFar = 0, noNode = 0,
                tooClose = 0, inView = 0, clumped = 0, nearPlayer = 0, queueDropped = 0 },
}

-- Last plan per cluster, for the readout.
ZStream.lastClusters = {}

-- [source] = { at, n } - per-interval spawn request gate. See bs:zs:spawn.
ZStream.spawnGate = {}

-- Small helpers
-- Declared before use: a local function referenced above its declaration compiles to a global

local function distance2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

local function count(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

-- Same safe-zone rule as sv_registry.lua inSafeZone(): the same Zones.Safe list and padding, so the two systems cannot disagree
local function inSafeZone(x, y)
    local padding = (Zombies and Zombies.Settings and Zombies.Settings.safeZonePadding)
        or Streaming.safeZonePaddingFallback
    for _, zone in ipairs((Zones and Zones.Safe) or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= ((zone.radius + padding) ^ 2) then return true end
    end
    return false
end

local function playerRecords()
    local result = {}
    for _, source in ipairs(GetPlayers()) do
        local src = tonumber(source)
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)
            result[#result + 1] = { source = src, x = at.x, y = at.y, z = at.z }
        end
    end
    return result
end

-- Clustering
local function makeClusters(records)
    local clusters = {}
    local radius2 = Streaming.clusterRadius * Streaming.clusterRadius

    for _, record in ipairs(records) do
        local selected
        for _, cluster in ipairs(clusters) do
            if distance2(record, cluster) <= radius2 then selected = cluster break end
        end

        if not selected then
            selected = { x = record.x, y = record.y, z = record.z, members = {}, coordinator = record.source }
            clusters[#clusters + 1] = selected
        end

        selected.members[#selected.members + 1] = record
        if record.source < selected.coordinator then selected.coordinator = record.source end

        local n = #selected.members
        selected.x = selected.x + (record.x - selected.x) / n
        selected.y = selected.y + (record.y - selected.y) / n
        selected.z = selected.z + (record.z - selected.z) / n
    end

    return clusters
end

-- Adaptive budget
local function budgetForCluster(cluster)
    -- The target comes from place density, and the telemetry ladder only lowers it
    local target = Streaming.clusterSoft
    if ZSpawnSrc and ZSpawnSrc.DensityFor then
        local ok, want = pcall(ZSpawnSrc.DensityFor, cluster)
        if ok and type(want) == 'number' and want > 0 then target = want end
    end
    local densityTarget = target
    local haveTelemetry = false

    for _, member in ipairs(cluster.members) do
        local t = ZStream.telemetry[member.source]
        if t and GetGameTimer() - t.updatedAt <= 10000 then
            haveTelemetry = true
            local matched = densityTarget
            for _, rung in ipairs(Streaming.ladder) do
                if t.fps < rung.fps or t.pedCount > rung.peds then
                    matched = rung.target
                    break
                end
            end
            -- The ladder is a ceiling under load, never a floor.
            if matched < target then target = matched end
        end
    end

    -- No telemetry means a new connection or a client thread that has not run yet
    if not haveTelemetry then target = math.min(densityTarget, Streaming.clusterColdStart) end

    local current = ZStream.adaptive[cluster.coordinator] or Streaming.clusterColdStart
    if target > current then
        current = math.min(target, current + Streaming.budgetStepUp)
    elseif target < current then
        current = math.max(target, current - Streaming.budgetStepDown)
    end

    ZStream.adaptive[cluster.coordinator] = current
    return current, target, haveTelemetry
end

-- Arrival window: true while the player counts as newly arrived
local function arrivalOpen(record, now)
    local state = ZStream.observerState[record.source]

    if not state then
        -- A player who just connected counts as an arrival.
        state = { anchorX = record.x, anchorY = record.y, arrivalUntil = now + Streaming.arrivalWindowMs }
        ZStream.observerState[record.source] = state
    else
        local dx, dy = record.x - state.anchorX, record.y - state.anchorY
        if (dx * dx + dy * dy) >= (Streaming.arrivalTravelDistance * Streaming.arrivalTravelDistance) then
            state.anchorX, state.anchorY = record.x, record.y
            state.arrivalUntil = now + Streaming.arrivalWindowMs
        end
    end

    return now < (state.arrivalUntil or 0)
end

-- Walkers already near this cluster, read from the sector registry (read-only) and subtracted from the budget
local function activeNear(cluster)
    local reg = rawget(_G, 'Registry')
    if type(reg) ~= 'table' or type(reg.zombies) ~= 'table' then return 0 end

    local n, radius2 = 0, Streaming.cleanupDistance * Streaming.cleanupDistance
    for _, record in pairs(reg.zombies) do
        if record.x and distance2(record, cluster) <= radius2 then n = n + 1 end
    end
    return n
end

-- The plan

-- One planning pass: cluster to budget to need to nearby herds to a per-node need sent to one
function ZStream.Plan()
    local now = GetGameTimer()
    ZStream.stats.plans = ZStream.stats.plans + 1
    ZStream.stats.lastPlanMs = now
    ZStream.lastClusters = {}
    if not Zombies.Settings.enabled or not Streaming.enabled or not ZSpawnSrc.Ready() then return end
    for id, offer in pairs(ZStream.offers) do
        if now >= offer.expires then ZStream.offers[id] = nil end
    end
    local records = playerRecords()
    -- Quiet-world population starts after a survivor stays in the same area for thirty seconds
    ZStream.areaPresence = ZStream.areaPresence or {}
    local present = {}
    for _, player in ipairs(records) do
        present[player.source] = true
        local stay = ZStream.areaPresence[player.source]
        local radius = Streaming.quietAreaRadius or 75.0
        if not stay or distance2(stay, player) > radius * radius then
            ZStream.areaPresence[player.source] = {x=player.x,y=player.y,since=now}
        end
    end
    for src in pairs(ZStream.areaPresence) do
        if not present[src] then ZStream.areaPresence[src] = nil end
    end
    local clusters = makeClusters(records)
    table.sort(clusters, function(a,b) return a.coordinator < b.coordinator end)
    ZStream.stats.clusters = #clusters
    ZStream.nextPlanId = ZStream.nextPlanId + 1
    local outstanding = count(ZStream.offers)
    local worldRoom = math.max(0, (Streaming.globalHard or 200) - ZStream.LiveCount() - outstanding)
    -- Rotate first service when the global pool is nearly full.
    for offset = 1, #clusters do
        local cluster = clusters[((offset + ZStream.nextPlanId - 2) % #clusters) + 1]
        local budget, target, haveTelemetry = budgetForCluster(cluster)
        local share = ZPolicy.Share(Streaming.globalHard or 200, #cluster.members, #records)
        budget = math.min(budget, share, (Zombies.Spawn and Zombies.Spawn.density and Zombies.Spawn.density.clusterCap) or 90)
        local active = activeNear(cluster)
        local pending = 0
        for _, offer in pairs(ZStream.offers) do
            if offer.src == cluster.coordinator then pending = pending + 1 end
        end
        local need = math.max(0, budget - active - pending)
        local remaining = math.min(need, Streaming.spawnPerPlan, worldRoom)
        local settled = false
        for _, member in ipairs(cluster.members) do
            local stay = ZStream.areaPresence[member.source]
            if stay and now - stay.since >= (Streaming.quietAreaMs or 30000) then
                settled = true
                break
            end
        end
        local recentNoise = ZPOI and ZPOI.LoudestNear
            and ZPOI.LoudestNear(cluster.x, cluster.y, 350.0)
        if not settled and not recentNoise then remaining = 0 end
        local nodes = {}
        local nearby = ZSpawnSrc.Nearby(cluster, Streaming.fullDistance + 100.0)
        local cursor = ZStream.selectionCursor[cluster.coordinator] or 0
        for i = 1, #nearby do
            if remaining <= 0 then break end
            local node = nearby[((cursor + i - 1) % #nearby) + 1]
            local closest = math.huge
            for _, player in ipairs(records) do closest = math.min(closest, distance2(node, player)) end
            if not ZStream.offers[node.id] and node.population > 0
               and closest >= (Streaming.spawnMin + 15.0)^2 and not inSafeZone(node.x,node.y) then
                local mode = node.synthetic and 'hidden' or 'simulation'
                ZStream.offers[node.id] = {
                    src = cluster.coordinator, expires = now + 6500, mode = mode,
                    x = node.x, y = node.y, budget = budget, cluster = cluster,
                }
                nodes[#nodes+1] = { id=node.id, x=node.x, y=node.y, z=node.z,
                    radius=node.radius, population=node.population, intent=node.intent,
                    need=1, mode=mode }
                remaining, worldRoom = remaining-1, worldRoom-1
            end
        end
        ZStream.selectionCursor[cluster.coordinator] = cursor + math.max(1, #nodes)
        ZStream.stats.offered = ZStream.stats.offered + #nodes
        ZStream.lastClusters[#ZStream.lastClusters+1] = {
            coordinator=cluster.coordinator, members=#cluster.members,
            x=cluster.x,y=cluster.y,budget=budget,target=target,telemetry=haveTelemetry,
            active=active,need=need,offered=#nodes,nodes=#nodes,arrival=false,pending=pending,
        }
        for _, member in ipairs(cluster.members) do
            TriggerClientEvent('bs:zs:plan', member.source, {
                nodes=nodes, canSpawn=member.source==cluster.coordinator,
                dryRun=Streaming.dryRun==true,budget=budget,active=active,
            })
        end
    end
end

RegisterNetEvent('bs:zs:tele', function(data)
    local src = source
    if not Streaming.enabled or type(data) ~= 'table' then return end

    local fps = tonumber(data.fps) or 60
    local peds = tonumber(data.pedCount) or 0
    if not ZPolicy.Finite(fps) or not ZPolicy.Finite(peds) then return end
    local live = tonumber(data.liveZombies)

    ZStream.telemetry[src] = {
        fps = math.max(5, math.min(240, fps)),
        pedCount = math.max(0, math.min(1024, math.floor(peds))),
        ping = GetPlayerPing(src) or 0,
        updatedAt = GetGameTimer(),
        liveZombies = ZPolicy.Finite(live) and math.max(0, math.min(1024, math.floor(live))) or nil,
    }
end)

-- Dry-run report
RegisterNetEvent('bs:zs:report', function(report)
    local src = source
    if not Streaming.enabled or type(report) ~= 'table' then return end

    local accepted = math.max(0, math.min(64, tonumber(report.accepted) or 0))
    ZStream.stats.accepted = ZStream.stats.accepted + accepted

    local reasons = type(report.reasons) == 'table' and report.reasons or {}
    for key, current in pairs(ZStream.stats.reasons) do
        local n = tonumber(reasons[key]) or 0
        if n > 0 then
            n = math.min(1024, n)
            ZStream.stats.reasons[key] = current + n
            ZStream.stats.rejected = ZStream.stats.rejected + n
        end
    end

end)

-- Placing one walker

-- Refusals by reason
ZStream.refused = {
    disabled = 0, dryRun = 0, noNode = 0, empty = 0, range = 0,
    permit = 0, cap = 0, safeZone = 0, tooClose = 0, blind = 0, other = 0,
    -- clumped: too close to a walker placed a few seconds ago
    clumped = 0, noiseCap = 0, poi = 0,
    -- rate is the per-client request gate, kept apart from cap (the global world ceiling) so one does not report as the other
    rate = 0,
}
ZStream.spawned = 0

-- Last few refusals in words (six entries), to show by how much a check failed.
ZStream.lastRefusals = {}

local function refuse(reason, detail)
    ZStream.refused[reason] = (ZStream.refused[reason] or 0) + 1

    table.insert(ZStream.lastRefusals, 1,
        ('%s%s'):format(reason, detail and (' - ' .. detail) or ''))
    while #ZStream.lastRefusals > 6 do table.remove(ZStream.lastRefusals) end

    return false
end

-- Counted when a request arrives, before any check, to tell "never asked" from "asked and refused"
ZStream.requests = 0

-- Archetype and model are decided here by the server once and sent with the record, so every client agrees
local function pickType(x, y)
    local best
    for _, zone in ipairs(Zones.Spawn or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
            if not best or (zone.difficulty or 1) > (best.difficulty or 1) then best = zone end
        end
    end

    local weights = (best and best.types) or { walker = 98, brute = 2 }
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    if total <= 0 then return 'walker' end

    local roll = math.random() * total
    local acc = 0
    for typeId, w in pairs(weights) do
        acc = acc + w
        if roll <= acc then return typeId end
    end
    return 'walker'
end

local function pickModel(x, y, typeId)
    return Zombies.PickModel(x, y, typeId)
end

-- Recent placements, kept on the server
ZStream.recentSpawns = {}

local function placementConfig()
    return Streaming.Placement or nil
end

-- Drop entries older than the separation memory, then check the point is far enough from recent placements
local function separatedEnough(x, y)
    local cfg = placementConfig()
    if not cfg then return true end

    local minSep = cfg.minSpawnSeparation or 0.0
    if minSep <= 0 then return true end

    local now = GetGameTimer()
    local memory = cfg.separationMemoryMs or 45000
    local kept, n = {}, 0
    local ok = true

    for i = 1, #ZStream.recentSpawns do
        local entry = ZStream.recentSpawns[i]
        if (now - entry.at) <= memory then
            n = n + 1
            kept[n] = entry
            local dx, dy = x - entry.x, y - entry.y
            if (dx * dx + dy * dy) < (minSep * minSep) then ok = false end
        end
    end

    ZStream.recentSpawns = kept
    return ok
end

-- Remembered only after a record is actually created, so a refused candidate does not reserve ground
local function rememberSpawn(x, y)
    ZStream.recentSpawns[#ZStream.recentSpawns + 1] = { x = x, y = y, at = GetGameTimer() }
end

-- One candidate, fully re-checked
function ZStream.Spawn(src, nodeId, coords, heading, mode)
    if not Zombies.Settings.enabled or not Streaming.enabled then return refuse('disabled') end
    if Streaming.dryRun then return refuse('dryRun') end
    if not ZSpawnSrc.Ready() then return refuse('noNode') end
    nodeId = tonumber(nodeId)
    if not ZPolicy.Finite(nodeId) or type(coords) ~= 'table' then return refuse('other') end
    local x,y,z = tonumber(coords.x),tonumber(coords.y),tonumber(coords.z)
    heading = tonumber(heading)
    if not ZPolicy.Point(x,y,z) or not ZPolicy.Finite(heading) then return refuse('other') end
    local offer = ZStream.offers[nodeId]
    if not offer or offer.src ~= src or GetGameTimer() >= offer.expires or mode ~= offer.mode then
        return refuse('permit')
    end
    -- Consume once, refusals included. A new plan can retry.
    ZStream.offers[nodeId] = nil
    local node = ZSpawnSrc.Get(nodeId)
    if not node then return refuse('noNode') end
    if node.population <= 0 then return refuse('empty') end
    if mode == 'simulation' and ((x-offer.x)^2+(y-offer.y)^2 > 60.0^2) then
        return refuse('range','placement left its simulation agent')
    end
    if activeNear(offer.cluster) >= offer.budget then return refuse('cap','cluster allocation full') end
    if ZStream.LiveCount() >= (Streaming.globalHard or 200) then return refuse('cap','global pool full') end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return refuse('blind') end
    local at = GetEntityCoords(ped)
    local maxRange = (Streaming.spawnMax or 200) + ((Sim and Sim.spawn and Sim.spawn.openPushMax) or 0) + 100
    if (x-at.x)^2+(y-at.y)^2 > maxRange^2 then return refuse('range') end
    if not separatedEnough(x,y) then return refuse('clumped') end
    local floor = math.max(Streaming.spawnMin or 110, (placementConfig() or {}).minPlayerDistance or 110)
    local typeId = pickType(x,y)
    local record,why = Registry.SpawnAtPoint(nodeId,x,y,z,heading,typeId,pickModel(x,y,typeId),floor)
    if not record then return refuse(why or 'other') end
    -- Simulation Bind already claimed the individual. Synthetic sources have no census.
    if node.synthetic then node.population = math.max(0,node.population-1) end
    rememberSpawn(x,y)
    ZStream.spawned = ZStream.spawned + 1
    return true
end

RegisterNetEvent('bs:zs:spawn', function(nodeId, coords, heading, mode)
    local src = source
    ZStream.requests = ZStream.requests + 1

    if not Streaming.enabled or Streaming.dryRun then return end
    if type(coords) ~= 'table' then return end

    -- Rate gate on its own counter, matching the client work interval (workMs 1000, up to 3 per pass), not the plan window
    local now = GetGameTimer()
    local gate = ZStream.spawnGate[src]
    if not gate or now - gate.at >= (Streaming.requestWindowMs or 1200) then
        gate = { at = now, n = 0 }
        ZStream.spawnGate[src] = gate
    end

    gate.n = gate.n + 1
    if gate.n > (Streaming.requestsPerWindow or 6) then
        ZStream.refused.rate = (ZStream.refused.rate or 0) + 1
        return
    end

    ZStream.Spawn(src, nodeId, coords, heading, mode)
end)

AddEventHandler('playerDropped', function()
    local src = source
    ZStream.telemetry[src] = nil
    ZStream.adaptive[src] = nil
    ZStream.observerState[src] = nil
    ZStream.arrivalPermits[src] = nil
    ZStream.spawnGate[src] = nil
    ZStream.selectionCursor[src] = nil
    for id, offer in pairs(ZStream.offers) do
        if offer.src == src then ZStream.offers[id] = nil end
    end
end)

-- The planner thread

CreateThread(function()
    -- The master switch is read once at start; change it with a resource restart.
    if not Streaming.enabled then
        print('^5[BS STREAM]^7 streaming planner is OFF (Streaming.enabled = false in '
            .. 'config/config_streaming.lua). Nothing is planned, no rays are cast, and '
            .. 'the sector system is untouched. /zstream will say the same.')
        return
    end

    print(('^5[BS STREAM]^7 streaming planner ON, dryRun=%s - %s')
        :format(tostring(Streaming.dryRun),
                Streaming.dryRun and 'candidates are validated and DISCARDED, nothing spawns'
                                  or '^1WALKERS WILL SPAWN FROM THIS PATH^7'))

    while true do
        Wait(Streaming.planMs)
        -- pcall so a fault in one pass cannot kill the loop (a dead thread looks like an idle server).
        local ok, err = pcall(ZStream.Plan)
        if not ok then
            print(('^1[BS STREAM]^7 plan pass failed: %s'):format(tostring(err)))
        end
    end
end)

-- Cutover watchdog
CreateThread(function()
    if not Streaming.enabled or Streaming.dryRun then return end

    local WINDOW = 300000
    local lastSeen, lastCount = GetGameTimer(), -1

    while true do
        Wait(60000)

        local players = #GetPlayers()
        local now = GetGameTimer()

        -- Written out step by step: and binds tighter than or in Lua.
        local spawned = ZStream.spawned or 0

        if players == 0 then
            -- An empty server spawning nothing is correct.
            lastSeen = now
        elseif spawned ~= lastCount then
            lastSeen = now
        end

        lastCount = spawned

        if players > 0 and (now - lastSeen) >= WINDOW then
            lastSeen = now
            print('^1' .. string.rep('=', 74) .. '^7')
            print(('^1[BS STREAM]^7 NOTHING HAS SPAWNED IN %d MINUTES with %d player(s) online.')
                :format(WINDOW / 60000, players))
            local s, client = ZStream.stats, ZStream.stats.reasons
            local server = ZStream.refused or {}
            print(('^1[BS STREAM]^7 plans=%d offered=%d client-accepted=%d requests=%d spawned=%d live=%d/%d')
                :format(s.plans, s.offered, s.accepted, ZStream.requests or 0,
                        spawned, ZStream.LiveCount(), Streaming.globalHard or 200))
            for i = 1, math.min(3, #ZStream.lastClusters) do
                local c = ZStream.lastClusters[i]
                print(('^1[BS STREAM]^7 cluster %d at %.0f %.0f: budget=%d active=%d pending=%d need=%d offered=%d')
                    :format(c.coordinator, c.x, c.y, c.budget, c.active, c.pending,
                            c.need, c.offered))
            end
            print(('^1[BS STREAM]^7 client refused: no-ground=%d in-view=%d seen=%d near-player=%d clumped=%d queue-expired=%d')
                :format(client.noSafeCoord or 0, client.inView or 0, client.seen or 0,
                        client.nearPlayer or 0, client.clumped or 0, client.queueDropped or 0))
            print(('^1[BS STREAM]^7 server refused: permit=%d range=%d cap=%d rate=%d no-source=%d other=%d')
                :format(server.permit or 0, server.range or 0, server.cap or 0,
                        server.rate or 0, (server.noNode or 0)+(server.empty or 0),
                        server.other or 0))
            print('^1[BS STREAM]^7 Run /zdiag at the stalled location for the local census and remaining gates.')
            print('^1' .. string.rep('=', 74) .. '^7')
        end
    end
end)

-- /zstream - planner diagnostic

-- What to watch: cluster count: players together must be one cluster

-- Diagnostic commands always answer and accept either staff authority (the bs.admin ace or bs_admin's IsAdmin)
local function staffAllowed(src)
    if src == 0 then return true end

    if IsPlayerAceAllowed(src, 'bs.admin') then return true end

    if GetResourceState('bs_admin') == 'started' then
        local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and admin == true then return true end
    end

    return false
end

--- Emit to whoever asked - chat for a player, console for the console.
local function emitTo(src, line)
    if src == 0 then
        print(line)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { line } })
    end
end

-- @return boolean allowed (it has already replied with a refusal if false)
local function staffGate(src, what)
    if staffAllowed(src) then return true end
    emitTo(src, ('^1[%s]^7 refused - this needs the `bs.admin` ace or staff in bs_admin.')
        :format(what))
    emitTo(src, '   (this message means the command EXISTS and the resource is running)')
    return false
end

RegisterCommand('zstream', function(src)
    if not staffGate(src, 'BS STREAM') then return end

    local function emit(line) emitTo(src, line) end

    if not Streaming.enabled then
        emit('^3[BS STREAM]^7 DISABLED - Streaming.enabled = false in config/config_streaming.lua')
        emit('   Stage 3/4 are shipped inert on purpose. The sector system is what you are')
        emit('   seeing in game. Set enabled = true and restart to watch the dry run.')
        return
    end

    local s = ZStream.stats
    emit(('^5[BS STREAM]^7 %s | %d plans | %d clusters now | %d telemetry, %d ramps')
        :format(Streaming.dryRun and '^3DRY RUN^7 (nothing spawns)' or '^1LIVE^7',
                s.plans, s.clusters, count(ZStream.telemetry), count(ZStream.adaptive)))

    if not ZSpawnSrc.Ready() then
        emit('   ^3ZNodes is not seeded yet^7 - the planner has no herds to plan around')
    end

    emit(('   candidates: %d offered, %d accepted, %d rejected (%.0f%% of what was tried)')
        :format(s.offered, s.accepted, s.rejected,
                (s.accepted + s.rejected) > 0 and (s.rejected / (s.accepted + s.rejected) * 100) or 0))

    emit(('   planner refusals: %d herd(s) inside the noise standoff | %d hunting herd(s) over the ambient share')
        :format(s.poiBlocked or 0, s.huntCapped or 0))

    local r = s.reasons
    emit(('   rejected by: seen-cell %d | ray-clear %d | no safe coord %d | safe zone %d | too far %d | no node %d')
        :format(r.seen, r.rayClear, r.noSafeCoord, r.safeZone, r.tooFar, r.noNode))

    -- Server-side refusals, after a client accepted
    local f = ZStream.refused or {}
    emit(('   spawned %d | server refused: range %d | permit %d | world-cap %d | rate-gate %d | too close %d | safe zone %d | no herd %d | other %d')
        :format(ZStream.spawned or 0, f.range or 0, f.permit or 0, f.cap or 0, f.rate or 0,
                f.tooClose or 0, f.safeZone or 0, (f.noNode or 0) + (f.empty or 0),
                (f.other or 0) + (f.blind or 0)))

    if #ZStream.lastClusters == 0 then
        emit('   last plan produced no clusters - nobody is connected, or no player ped exists yet')
        return
    end

    for _, c in ipairs(ZStream.lastClusters) do
        emit(('   cluster @%d (%d player%s) %.0f,%.0f | budget %d -> target %d%s | %d already near | need %d | offered %d over %d herd(s)%s')
            :format(c.coordinator, c.members, c.members == 1 and '' or 's', c.x, c.y,
                    c.budget, c.target, c.telemetry and '' or ' ^3(no telemetry)^7',
                    c.active, c.need, c.offered, c.nodes,
                    c.arrival and ' ^2[ARRIVAL]^7' or ''))
    end
end, false)

-- Planner view for the visualiser. Read-only, never yields (same contract as the node exports).

exports('StreamSnapshot', function()
    local clusters = {}
    for _, c in ipairs(ZStream.lastClusters) do
        clusters[#clusters + 1] = {
            coordinator = c.coordinator, members = c.members,
            x = c.x, y = c.y,
            budget = c.budget, target = c.target, telemetry = c.telemetry,
            active = c.active, need = c.need, offered = c.offered,
            nodes = c.nodes, arrival = c.arrival,
        }
    end

    local r = ZStream.stats.reasons
    return {
        -- Both flags, named as in the config, since "why is nothing spawning" usually comes down to one of them
        enabled = Streaming.enabled and true or false,
        dryRun = Streaming.dryRun and true or false,
        plans = ZStream.stats.plans,
        lastPlanMs = ZStream.stats.lastPlanMs,
        clusterCount = ZStream.stats.clusters,
        offered = ZStream.stats.offered,
        accepted = ZStream.stats.accepted,
        rejected = ZStream.stats.rejected,
        reasons = {
            seen = r.seen, rayClear = r.rayClear, noSafeCoord = r.noSafeCoord,
            safeZone = r.safeZone, tooFar = r.tooFar, noNode = r.noNode,
        },
        clusters = clusters,
    }
end)

-- Boot banner

CreateThread(function()
    Wait(3000)      -- after ZNodes.Init has had a chance to seed or load

    local line = string.rep('=', 74)
    print('^5' .. line .. '^7')
    print('^5[BS ZOMBIES]^7  SPAWN SYSTEM STATE')
    print('')

    local sectors = (Sectors and Sectors.Settings and Sectors.Settings.enabled) and true or false
    print(('   sector spawner   : %s'):format(
        sectors and '^2ON^7 (the old grid is filling the world)'
                 or '^3OFF^7 (cut over - the node simulation owns the world)'))

    print(('   node streaming   : %s'):format(
        not Streaming.enabled and '^1OFF^7 - Streaming.enabled = false, nothing will ever spawn from it'
        or (Streaming.dryRun and '^3ON, DRY RUN^7 - candidates are validated and DISCARDED'
                              or '^2ON, LIVE^7 - this path places walkers')))

    if ZNodes and ZNodes.ready and ZNodes.campaign then
        local count = 0
        for _ in pairs(ZNodes.nodes) do count = count + 1 end
        print(('   herds            : %d, world population %d, atlas v%s')
            :format(count, ZNodes.campaign.totalPopulation or 0, tostring(ZAtlas.version)))
    else
        print('   herds            : ^3not seeded yet^7 (or persistence is still loading)')
    end

    -- Both systems off is a valid configuration but gives an empty world, so it is called out on its own
    if not sectors and (not Streaming.enabled or Streaming.dryRun) then
        print('')
        print('^1   >>> NOTHING WILL SPAWN. The sector system is off and the node path is not^7')
        print('^1   >>> live. Set Sectors.Settings.enabled = true in config_sectors.lua to go^7')
        print('^1   >>> back, or Streaming.dryRun = false in config_streaming.lua to go on.^7')
    end

    print('')
    print('   commands: /zstream  /znodes  /nodemap  /safezones')
    print('   (they always reply now, even to refuse - silence means NOT LOADED)')
    print('^5' .. line .. '^7')
end)

-- /zdiag - walk the whole spawn chain and say where it stops

-- Walks the chain from a seeded herd to a walker in the street once

local function diagServer(src, emit)
    emit('^5' .. string.rep('-', 62) .. '^7')
    emit('^5[ZDIAG]^7 walking the spawn chain')

    ------------------------------------------------------------------ 1. flags
    local sectorsOn = (Sectors and Sectors.Settings and Sectors.Settings.enabled) and true or false
    emit(('1. config      : streaming=%s dryRun=%s sectors=%s')
        :format(tostring(Streaming.enabled), tostring(Streaming.dryRun), tostring(sectorsOn)))

    if not Streaming.enabled then
        emit('   ^1FAIL^7 - Streaming.enabled is false. Nothing downstream runs at all.')
        return
    end
    if Streaming.dryRun then
        emit('   ^3NOTE^7 - dryRun is on: the chain runs fully but the last step throws the')
        emit('          candidate away. Everything below should still report healthy.')
    end

    ------------------------------------------------------------- 2. simulation
    if not (ZNodes and ZNodes.ready) then
        emit('2. simulation  : ^1FAIL^7 - ZNodes.ready is false. No herds exist, so no plan can')
        emit('                 name one. Look for a [BS NODES] error at boot.')
        return
    end

    local herds, worldPop = 0, 0
    for _, n in pairs(ZNodes.nodes) do
        herds = herds + 1
        worldPop = worldPop + (n.population or 0)
    end
    emit(('2. simulation  : ready, %d cached individuals, %d available in cache')
        :format(herds, worldPop))
    if herds == 0 and ZSpawnSrc.Mode() ~= 'local' then
        emit('   ^3NOTE^7 - the diagnostic cache is empty; checking live sources below.')
    end

    -------------------------------------------------------------- 3. the asker
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        emit('3. your ped    : ^1FAIL^7 - the server cannot read your ped. Nothing can be planned')
        emit('                 around a player it cannot locate.')
        return
    end
    local at = GetEntityCoords(ped)
    emit(('3. your ped    : %.0f, %.0f, %.0f'):format(at.x, at.y, at.z))

    --------------------------------------------------------------- 4. clusters
    local records = playerRecords()
    local clusters = makeClusters(records)

    local mine
    for _, c in ipairs(clusters) do
        for _, m in ipairs(c.members) do
            if m.source == src then mine = c break end
        end
        if mine then break end
    end

    if not mine then
        emit(('4. clustering  : ^1FAIL^7 - %d player record(s), none of them you. playerRecords()')
            :format(#records))
        emit('                 skipped you, which means GetPlayerPed returned 0 for your id.')
        return
    end
    emit(('4. clustering  : %d cluster(s), yours has %d member(s), coordinator = %d%s')
        :format(#clusters, #mine.members, mine.coordinator,
                mine.coordinator == src and ' ^2(you)^7' or ' ^3(NOT you - only the coordinator casts rays)^7'))

    ----------------------------------------------------------------- 5. budget
    local budget, target, haveTele = budgetForCluster(mine)
    local active = activeNear(mine)
    local need = math.max(0, math.min(budget, Streaming.globalHard) - active)
    local held, materialised = 0, 0
    local registry = rawget(_G, 'Registry')
    if registry and registry.zombies then
        for _, record in pairs(registry.zombies) do
            if record.x and distance2(record, mine) <= Streaming.cleanupDistance^2 then
                if record.materialisedAt then materialised = materialised + 1
                else held = held + 1 end
            end
        end
    end

    emit(('5. budget      : budget=%d target=%d telemetry=%s | %d walker(s) already within %.0fm | need=%d')
        :format(budget, target, tostring(haveTele), active, Streaming.cleanupDistance, need))
    emit(('   records     : %d materialised, %d awaiting first client materialisation | world %d/%d')
        :format(materialised, held, ZStream.LiveCount(), Streaming.globalHard or 200))

    if need <= 0 then
        emit('   ^1FAIL^7 - need is zero, so no herd is asked for anything. Either the budget is')
        emit('          at the floor, or there are already enough walkers near you. If you have')
        emit('          been spawning them by hand, THAT is why - they count toward `active`.')
        return
    end

    ------------------------------------------------------------------ 6. herds
    local reach = Streaming.fullDistance + 100.0
    -- Goes through the dispatcher so it describes the active mode (reading ZNodes directly would be wrong in local mode)
    local nearby = ZSpawnSrc.Nearby(mine, reach)
    emit(('   spawn mode: ^5%s^7'):format(ZSpawnSrc.Mode()))

    local nearest, nearestDist = nil, math.huge
    local nearestSource = ZSpawnSrc.Mode() == 'simulation' and ZNodes and ZNodes.nodes
    if not nearestSource or not next(nearestSource) then nearestSource = nearby end
    for _, n in pairs(nearestSource) do
        local dx, dy = n.x - at.x, n.y - at.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < nearestDist then nearest, nearestDist = n, d end
    end

    emit(('6. herds near  : %d within %.0fm | nearest herd anywhere is #%s at %.0fm (%d zombies)')
        :format(#nearby, reach, nearest and tostring(nearest.id) or '-',
                nearestDist, nearest and nearest.population or 0))
    if ZSpawnSrc.Mode() == 'simulation' and ZSim and ZSim.CellAt then
        local farCount, individualCount, killedCount, graceCount = 0, 0, 0, 0
        local now = os.time()
        local grace = ((Sim and Sim.regrow and Sim.regrow.graceMinutes) or 0) * 60
        for dx = -250, 250, 50 do
            for dy = -250, 250, 50 do
                local cell = ZSim.CellAt(at.x + dx, at.y + dy)
                if cell then
                    farCount = farCount + (cell.n or 0)
                    individualCount = individualCount + (cell.ind or 0)
                    killedCount = killedCount + (cell.killed or 0)
                    if cell.clearedAt and cell.clearedAt > 0
                       and now - cell.clearedAt < grace then
                        graceCount = graceCount + 1
                    end
                end
            end
        end
        emit(('   local census: %d far-field, %d individuals, %d lifetime kills, %d cells in regrowth grace (550m square)')
            :format(farCount, individualCount, killedCount, graceCount))
    end

    if #nearby == 0 then
        emit('   ^1FAIL^7 - no herd is in planning range, so nothing is offered. This is the')
        emit('          COVERAGE case: the world is populated, just not here. Drive toward the')
        emit('          nearest herd above and run /zdiag again to confirm.')
        return
    end

    ------------------------------------------------------------- 7. offerable?
    local offered, skippedSafe, skippedEmpty, skippedNear = 0, 0, 0, 0
    for _, n in ipairs(nearby) do
        if inSafeZone(n.x, n.y) then skippedSafe = skippedSafe + 1
        elseif (n.population or 0) <= 0 then skippedEmpty = skippedEmpty + 1
        elseif (n.x-at.x)^2+(n.y-at.y)^2 < (Streaming.spawnMin + 15.0)^2 then
            skippedNear = skippedNear + 1
        else offered = offered + 1 end
    end

    emit(('7. offerable   : %d usable, %d too near, %d in a safe zone, %d empty')
        :format(offered, skippedNear, skippedSafe, skippedEmpty))

    if offered == 0 then
        emit('   ^1FAIL^7 - every source in range was skipped. Too-near sources are inside')
        emit('          the spawn floor; empty sources have already become live walkers.')
        return
    end

    emit('^2   SERVER PRECHECKS PASSED (not proof of a visible ped)^7 - a plan naming ' .. offered
        .. ' herd(s) should be reaching client ' .. mine.coordinator .. ' every '
        .. Streaming.planMs .. 'ms.')
    emit('   Asking that client what it did with it...')
end

RegisterCommand('zdiag', function(src)
    if not staffGate(src, 'ZDIAG') then return end

    if src == 0 then
        print('^3[ZDIAG]^7 run this in game - it walks the chain from a PLAYER position.')
        return
    end

    diagServer(src, function(line) emitTo(src, line) end)

    -- The client half is requested, not assumed: the two halves live in different Lua states.
    TriggerClientEvent('bs:zs:diag', src)
end, false)

-- The client's answer, printed in the same readout. Treated as a report only.
RegisterNetEvent('bs:zs:diagreply', function(report)
    local src = source
    if type(report) ~= 'table' then return end

    local function emit(line) emitTo(src, line) end

    emit(('8. your client : plan received=%s canSpawn=%s dryRun=%s herds in plan=%d')
        :format(tostring(report.hasPlan), tostring(report.canSpawn),
                tostring(report.dryRun), tonumber(report.nodes) or 0))

    if not report.hasPlan then
        emit('   ^1FAIL^7 - your client has never received a plan. The server thinks it is')
        emit('          sending them, so this is the event not arriving: check that')
        emit('          bs:zs:plan is not being blocked and that the client script loaded.')
    elseif not report.canSpawn then
        emit('   ^3NOTE^7 - you are not the coordinator of your cluster, so your client does')
        emit('          no ray work. That is correct behaviour, not a fault.')
    end

    emit(('9. ray work    : %d observed cells | %d work passes, %d attempts, %d ACCEPTED (totals, not a window)')
        :format(tonumber(report.observed) or 0, report.passes or 0,
                report.attempts or 0, report.accepted or 0))
    emit(('   refused by   : seen %d | ray-clear %d | no-coord %d | safe %d | far %d | no-node %d')
        :format(report.seen or 0, report.rayClear or 0, report.noSafeCoord or 0,
                report.safeZone or 0, report.tooFar or 0, report.noNode or 0))

    if (tonumber(report.observed) or 0) == 0 then
        emit('   ^1FAIL^7 - the observation thread has cast no rays. Streaming.enabled read false')
        emit('          on the CLIENT at start - the config did not reach it, or the client')
        emit('          script is not in the manifest.')
    elseif (report.passes or 0) == 0 then
        emit('   ^1FAIL^7 - the work thread has never run a pass. It exists (rays are being cast)')
        emit('          but canSpawn has never been true for this client.')
    elseif (report.attempts or 0) == 0 then
        emit(('   ^1FAIL^7 - %d passes and ZERO attempts. The plan carries need=%d, so the slot')
            :format(report.passes or 0, report.need or 0))
        emit('          loop never ran: every herd in the plan asked for nothing.')
    elseif (report.accepted or 0) == 0 then
        emit('   ^1FAIL^7 - every attempt was refused. The breakdown above names which rule; the')
        emit('          usual answer is seen-cell, meaning the hidden-spawn rule is starving.')
    end

    -- 10. the server's turn
    emit(('10. requests   : %d spawn request(s) reached the server, %d walker(s) created')
        :format(ZStream.requests or 0, ZStream.spawned or 0))

    if (report.accepted or 0) > 0 and (ZStream.requests or 0) == 0 then
        emit('   ^1FAIL^7 - your client accepted candidates but not one request arrived. The')
        emit('          bs:zs:spawn event is not reaching the server: check it is registered')
        emit('          and that the client is not still running an older cl_spawner.lua.')
    end

    local f = ZStream.refused or {}
    emit(('   refused by   : range %d | permit %d | world-cap %d | rate-gate %d | too close %d | safe %d | no herd %d | blind %d | other %d')
        :format(f.range or 0, f.permit or 0, f.cap or 0, f.rate or 0, f.tooClose or 0,
                f.safeZone or 0, (f.noNode or 0) + (f.empty or 0), f.blind or 0, f.other or 0))

    if #(ZStream.lastRefusals or {}) > 0 then
        emit('   last refusals: ' .. table.concat(ZStream.lastRefusals, ' | '))
    end

    if ZNet and ZNet.enabled and ZNet.DiagLines then
        for _, line in ipairs(ZNet.DiagLines(src)) do emit(line) end
    end

    emit('^5' .. string.rep('-', 62) .. '^7')
end)
