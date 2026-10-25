-- bs_zombies - atlas API for the Node Atlas panel

-- Staff gate, copied from sv_sectors.lua

local function isStaff(src)
    if src == 0 then return true end        -- server console
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return ok and admin == true
end

local Atlas = {
    maxCells = 4000,
    maxAgents = 1500,
    maxNoise = 64,
    maxHerds = 256,
}

local function fail(why) return { ok = false, error = why } end

-- Ops: the six operations, without the staff gate
local OPS = {}

local function ready()
    if not (Sim and Sim.enabled) then return false, 'sim disabled' end
    if not (ZSim and ZSim.ready) then return false, 'sim not ready' end
    return true
end

local function num(v, d)
    v = tonumber(v)
    if v ~= v then return d end             -- NaN in, NaN everywhere after
    return v or d
end

-- Order a rectangle and clamp it to the world. Everything below depends on this.
local function rect(a)
    local x1 = math.min(num(a and a.x1, 0.0), num(a and a.x2, 0.0))
    local x2 = math.max(num(a and a.x1, 0.0), num(a and a.x2, 0.0))
    local y1 = math.min(num(a and a.y1, 0.0), num(a and a.y2, 0.0))
    local y2 = math.max(num(a and a.y1, 0.0), num(a and a.y2, 0.0))
    local B = ZSim.bounds
    return math.max(x1, B.minX), math.max(y1, B.minY),
           math.min(x2, B.maxX), math.min(y2, B.maxY)
end

-- A cell's state as one word (the atlas wants a colour)
local function cellState(c, now)
    if c.lock then return 'locked' end
    local have = c.n + c.ind
    if have == 0 and c.base == 0 then return 'empty' end
    if c.clearedAt > 0 and (now - c.clearedAt) < ((Sim.regrow.graceMinutes or 20) * 60) then
        return 'cleared'
    end
    if c.ind > 0 then return 'promoted' end
    if c.base > 0 and have < c.base * 0.5 then return 'thin' end
    if have >= c.base and c.base > 0 then return 'full' end
    return 'normal'
end

-- 1. Snapshot

-- The stats block, also printed by /zsim. One function so the console and the panel agree.
local function statsBlock()
    local s = ZSim.stats
    local spawned, confirmed = 0, 0
    if Registry and Registry.zombies then
        for _, record in pairs(Registry.zombies) do
            spawned = spawned + 1
            if record.materialisedAt then confirmed = confirmed + 1 end
        end
    end
    local rendered, reporting = 0, 0
    for _, t in pairs((ZStream and ZStream.telemetry) or {}) do
        if GetGameTimer() - t.updatedAt <= 10000 and t.liveZombies ~= nil then
            rendered, reporting = rendered + t.liveZombies, reporting + 1
        end
    end
    return {
        total = s.total,
        individuals = ZSim.agentCount,
        cells = s.cells,
        herds = s.herds,
        spawnedPeds = spawned,
        confirmedRecords = confirmed,
        unconfirmedRecords = spawned - confirmed,
        clientRenderedSum = rendered,
        reportingClients = reporting,

        -- Which system is placing walkers (staff can switch with /zmode)
        spawnMode = (ZSpawnSrc and ZSpawnSrc.Mode and ZSpawnSrc.Mode()) or 'unknown',

        -- Why candidates are refused
        refusedBlind    = (Registry and Registry.refusedBlind) or 0,
        refusedTooClose = (Registry and Registry.refusedTooClose) or 0,

        -- Walkers the streaming planner actually placed. spawnedPeds counts Registry.zombies
        streamSpawned = (ZStream and ZStream.spawned) or 0,
        streamRefused = (ZStream and ZStream.stats and ZStream.stats.rejected) or 0,
        regrowthPerHour = (Sim.regrow.enabled and Sim.regrow.perCellPerHour) or 0,
        tickMs = s.tickMs,
        cellTickMs = s.cellTickMs,
        promoted = s.promoted, demoted = s.demoted,
        killed = s.killed, regrown = s.regrown, migrated = s.migrated,
        truncated = s.truncated,
        population = Sim.population.target,
        cellSize = ZSim.cellSize,
        observers = #ZSim.observers,
    }
end

-- The in-world Alt overlay only identifies a real local walker (A) next to its unmaterialised simulation neighbours (D)
BSB.RegisterCallback('zombies:debug:nearby', function(src, args)
    if not isStaff(src) then return fail('not staff') end
    local ok, why = ready()
    if not ok then return fail(why) end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return fail('player position unavailable') end
    local pos = GetEntityCoords(ped)
    if not pos then return fail('player position unavailable') end

    local cfg = (Zombies.Settings and Zombies.Settings.debugOverlay) or {}
    local radius = math.min(math.max(num(args and args.radius, cfg.simulatedRadius or 260.0), 30.0), 350.0)
    local limit = math.min(math.max(math.floor(num(args and args.limit, cfg.simulatedLimit or 40)), 1), 80)
    local nearby, count = ZSim.AgentsNear(pos.x, pos.y, radius)
    local agents = {}
    for i = 1, count do
        local a = nearby[i]
        -- pedId means it is already a real registry walker with an A label on the client
        if a and not a.pedId then
            agents[#agents + 1] = { id = a.id, x = a.x, y = a.y, z = a.z or pos.z, state = a.state }
            if #agents >= limit then break end
        end
    end
    return { ok = true, agents = agents, total = count }
end)
OPS.snapshot = function(actor, args)
    local ok, why = ready()
    if not ok then return fail(why) end

    local x1, y1, x2, y2 = rect(args)
    local zoom = num(args and args.zoom, 1.0)
    local CELL = ZSim.cellSize

    -- Decimation: a whole-map rectangle is 44,000 cells. step samples every Nth cell in both axes
    local cx0, cy0 = math.floor(x1 / CELL), math.floor(y1 / CELL)
    local cx1, cy1 = math.floor(x2 / CELL), math.floor(y2 / CELL)
    local wide, high = (cx1 - cx0 + 1), (cy1 - cy0 + 1)
    local step = 1
    while (math.ceil(wide / step) * math.ceil(high / step)) > Atlas.maxCells do
        step = step + 1
    end

    local now = os.time()
    local cells, n = {}, 0
    for cx = cx0, cx1, step do
        for cy = cy0, cy1, step do
            local c = ZSim.Cell(cx, cy)
            if c and (c.n + c.ind) > 0 then
                n = n + 1
                cells[n] = { cx = c.cx, cy = c.cy, n = c.n + c.ind, state = cellState(c, now) }
            end
        end
    end

    -- Individuals, capped at 1500. truncated is set when the cap hits.
    local agents, an, truncated = ZSim.AgentsInRect(x1, y1, x2, y2, Atlas.maxAgents)
    local aout, represented = {}, {}
    for i = 1, an do
        local a = agents[i]
        local record = a.pedId and Registry and Registry.zombies[a.pedId]
        if not record then
        aout[i] = {
            id = a.id,
            x = a.x, y = a.y,
            state = a.state,
            -- target shows why the zombie is moving: 'point' = it heard something, 'player' = something higher up the sense ladder fired
            target = a.target and {
                kind = a.target.kind, x = a.target.x, y = a.target.y,
                src = a.target.src,
            } or nil,
            stim = a.stim,
            ped = a.pedId or nil,
            h = a.h,
        }
        else
            represented[a.pedId] = true
            aout[i] = { id = 'ped:' .. record.id, x = record.x, y = record.y,
                state = record.state, ped = record.ent and DoesEntityExist(record.ent) and record.id or nil,
                h = record.h }
        end
    end

    -- Fallback-ring and staff walkers have no simulation agent. Include their real positions too.
    for id, record in pairs((Registry and Registry.zombies) or {}) do
        if not represented[id] and not record.dead and (record.hp or 1) > 0 then
            local at = record.ent and DoesEntityExist(record.ent) and GetEntityCoords(record.ent) or record
            if at.x >= x1 and at.x <= x2 and at.y >= y1 and at.y <= y2 then
                aout[#aout + 1] = { id = 'ped:' .. id, x = at.x, y = at.y, h = record.h,
                    state = record.state, ped = record.ent and DoesEntityExist(record.ent) and id or nil,
                    target = record.poiX and { kind = 'point', x = record.poiX, y = record.poiY } or nil }
            end
        end
    end

    -- Observed herds inside the rectangle. Recomputed elsewhere; read here.
    local herds, hn = {}, 0
    for i = 1, #ZSim.herds do
        local h = ZSim.herds[i]
        if h.x >= x1 and h.x <= x2 and h.y >= y1 and h.y <= y2 and hn < Atlas.maxHerds then
            hn = hn + 1
            herds[hn] = { x = h.x, y = h.y, n = h.n, r = h.r }
        end
    end

    -- Live points of interest, straight off the sense layer's cached board.
    local noise, nn = {}, 0
    local board = (ZSimSense and ZSimSense.board) or {}
    for i = 1, #board do
        local b = board[i]
        if nn < Atlas.maxNoise and b.x >= x1 - b.reach and b.x <= x2 + b.reach
           and b.y >= y1 - b.reach and b.y <= y2 + b.reach then
            nn = nn + 1
            noise[nn] = { x = b.x, y = b.y, loud = b.loud, age = now - (b.at or now),
                          kind = b.kind, reach = b.reach }
        end
    end

    -- Players: positions and stance.
    local players, pn = {}, 0
    for id, p in pairs((ZSimSense and ZSimSense.players) or {}) do
        if p.x then
            pn = pn + 1
            -- zone / near / target fields for the players layer; older fields unchanged.
            local zone
            for _, z in ipairs((Zones and Zones.Spawn) or {}) do
                local zx, zy = z.coords.x - p.x, z.coords.y - p.y
                if zx * zx + zy * zy <= z.radius * z.radius then zone = z.id; break end
            end
            local near, chasing = 0, 0
            if Registry and Registry.NearbyZombies then
                for _, r in ipairs(Registry.NearbyZombies(p.x, p.y, 120.0)) do
                    near = near + 1
                    if r.tgtSrc == id then chasing = chasing + 1 end
                end
            end
            players[pn] = { id = id, name = p.name or ('#' .. id), x = p.x, y = p.y,
                            heading = p.h or 0.0, crouched = (p.crouched or p.prone) and true or false,
                            prone = p.prone and true or false,
                            vehicle = p.veh and true or false,
                            zone = zone, near = near, chasing = chasing,
                            stealth = p.mult or 1.0 }
        end
    end

    return {
        ok = true,
        rect = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 },
        stride = step, zoom = zoom, cellSize = CELL,
        cells = cells,
        agents = aout, truncated = truncated,
        herds = herds,
        noise = noise,
        players = players,
        stats = statsBlock(),
        -- Director heat zones and active hordes, for the HEAT and HORDES layers.
        director = (DirectorState and DirectorState()) or nil,
        -- Live atlas points including the survey, so labels follow the survey instead of the client's config copy
        points = (ZAtlasPoints and ZAtlasPoints.List and ZAtlasPoints.List()) or nil,
    }
end

-- THE SURVEY
local TERRAINS = { city = true, town = true, rural = true, industrial = true, military = true,
                   coast = true, forest = true, mountain = true, desert = true, road = true }
OPS.survey = function(actor, args)
    if not ZAtlasPoints then return fail('survey store missing (sv_atlas_points.lua)') end
    local action = tostring(args.action or 'list')
    if action == 'list' then return { ok = true, points = ZAtlasPoints.List(), dirty = ZAtlasPoints.dirty } end
    if action == 'save' then
        local ok = ZAtlasPoints.Save(actor.label)
        print(('^2[BS ATLAS]^7 survey saved by %s'):format(actor.label))
        return { ok = ok, persisted = ok, points = ZAtlasPoints.List(), note = 'density applies after a bs_zombies restart' }
    end
    if actor.key == 'web' then return fail('survey points are placed in game, where you stand') end
    local id = tostring(args.id or '')
    local cur = ZAtlasPoints.overrides[id] or {}
    for _, p in ipairs(ZAtlas.points or {}) do
        if p.id == id then cur = { x = p.x, y = p.y, z = p.z, d = p.d, t = p.t, n = p.n }; break end
    end
    local o = { x = cur.x, y = cur.y, z = cur.z, d = cur.d, t = cur.t, n = cur.n }
    if action == 'add' or action == 'move' then
        local ped = GetPlayerPed(actor.key)
        if not ped or ped == 0 then return fail('no ped') end
        local at = GetEntityCoords(ped)
        o.x, o.y, o.z = math.floor(at.x * 10 + 0.5) / 10, math.floor(at.y * 10 + 0.5) / 10, math.floor(at.z * 10 + 0.5) / 10
        if action == 'add' and not cur.x then o.d, o.t = 3.0, 'town' end
    elseif action == 'remove' then
        o = { removed = true }
    elseif action ~= 'set' then
        return fail('unknown survey action')
    end
    if action ~= 'remove' then
        if args.d ~= nil then o.d = tonumber(args.d) or o.d end
        if args.t ~= nil then
            if not TERRAINS[tostring(args.t)] then return fail('unknown terrain') end
            o.t = tostring(args.t)
        end
        if type(args.n) == 'table' then o.n = args.n end
        if not o.x then return fail('no such point - use add') end
    end
    local ok, err = ZAtlasPoints.Set(id, o)
    if not ok then return fail(err) end
    print(('^3[BS ATLAS]^7 survey %s "%s" by %s (unsaved)'):format(action, id, actor.label))
    return { ok = true, points = ZAtlasPoints.List(), dirty = true }
end

-- 2. INSPECT

OPS.inspect = function(actor, args)
    local ok, why = ready()
    if not ok then return fail(why) end

    local cx, cy = math.floor(num(args and args.cx, 0)), math.floor(num(args and args.cy, 0))
    local c = ZSim.Cell(cx, cy)
    if not c then return fail('no such cell') end

    local now = os.time()
    local wx, wy = ZSim.CellCentre(cx, cy)

    -- Its individuals, if promoted. Bounded by Sim.near.maxPerCell.
    local inds, n = {}, 0
    for _, a in pairs(ZSim.agents) do
        if a.cellKey == ZSim.KeyOf(cx, cy) then
            n = n + 1
            inds[n] = { id = a.id, x = a.x, y = a.y, h = a.h, state = a.state,
                        stim = a.stim, ped = a.pedId or nil,
                        target = a.target and { kind = a.target.kind, x = a.target.x,
                                                y = a.target.y, src = a.target.src } or nil,
                        driftFromOrigin = math.sqrt((a.x - a.originX) ^ 2 + (a.y - a.originY) ^ 2) }
        end
    end

    local sinceCleared = (c.clearedAt > 0) and (now - c.clearedAt) or nil
    local grace = (Sim.regrow.graceMinutes or 20) * 60

    return {
        ok = true,
        cell = {
            cx = cx, cy = cy, x = wx, y = wy, size = ZSim.cellSize,
            n = c.n, individuals = c.ind, total = c.n + c.ind,
            baseline = c.base, weight = c.w,
            state = cellState(c, now), locked = c.lock and true or false,
        },
        history = {
            killed = c.killed,
            clearedAt = c.clearedAt,
            secondsSinceKill = sinceCleared,
            migratedIn = c.inFlow, migratedOut = c.outFlow,
        },
        regrowth = {
            enabled = Sim.regrow.enabled and not c.lock,
            perHour = Sim.regrow.perCellPerHour,
            cap = math.floor(c.base * (Sim.regrow.capFraction or 1.0)),
            banked = c.acc or 0.0,
            -- nil when regrowth is running; seconds left while the grace period holds the hole open.
            graceRemaining = (sinceCleared and sinceCleared < grace) and (grace - sinceCleared) or nil,
        },
        individuals = inds,
    }
end

-- 3

OPS.edit = function(actor, args)
    local ok, why = ready()
    if not ok then return fail(why) end

    local cx, cy = math.floor(num(args and args.cx, 0)), math.floor(num(args and args.cy, 0))
    local c = ZSim.Cell(cx, cy)
    if not c then return fail('no such cell') end
    local patch = (type(args) == 'table' and type(args.patch) == 'table') and args.patch or {}

    local before = c.n + c.ind

    if patch.clear then
        -- Clears the COUNT, not the individuals: a promoted zombie may already be rendered by a client
        ZSim.stats.total = math.max(0, ZSim.stats.total - c.n)
        c.n = 0
        c.clearedAt = os.time()
        c.acc = 0.0
    end

    if patch.n ~= nil then
        local want = math.max(0, math.floor(num(patch.n, 0)))
        -- Hard ceiling per cell, same as the density map
        local ceiling = math.max(Sim.population.maxCellBaseline * 4, 100)
        if want > ceiling then want = ceiling end
        ZSim.stats.total = math.max(0, ZSim.stats.total - c.n + want)
        c.n = want
    end

    if patch.lock ~= nil then c.lock = patch.lock and true or false end
    if patch.baseline ~= nil then
        c.base = math.max(0, math.floor(num(patch.baseline, c.base)))
    end

    print(('^5[BS SIM]^7 atlas edit by %s: cell %d,%d %d -> %d%s')
        :format(actor.label, cx, cy,
                before, c.n + c.ind, c.lock and ' [locked]' or ''))

    local now = os.time()
    return { ok = true, cell = { cx = cx, cy = cy, n = c.n, individuals = c.ind,
                                 total = c.n + c.ind, baseline = c.base,
                                 locked = c.lock and true or false,
                                 state = cellState(c, now) } }
end

-- 4. REPOPULATE Admin button to refill ground from the atlas.

OPS.repopulate = function(actor, args)
    local ok, why = ready()
    if not ok then return fail(why) end

    local x1, y1, x2, y2 = rect(args)
    local amount = math.floor(num(args and args.amount, 0))
    if amount <= 0 then return fail('amount must be positive') end
    if amount > 20000 then amount = 20000 end   -- a typo is not a world event

    local CELL = ZSim.cellSize
    local cx0, cy0 = math.floor(x1 / CELL), math.floor(y1 / CELL)
    local cx1, cy1 = math.floor(x2 / CELL), math.floor(y2 / CELL)

    -- Spread by weight, not evenly: the density map says
    local pool, n, totalW = {}, 0, 0.0
    for cx = cx0, cx1 do
        for cy = cy0, cy1 do
            local c = ZSim.Cell(cx, cy)
            if c and not c.lock then
                n = n + 1
                pool[n] = c
                totalW = totalW + math.max(0.001, c.w)
            end
        end
    end
    if n == 0 then return fail('no editable cells in that rectangle') end

    local added = 0
    for i = 1, n do
        local c = pool[i]
        local share = math.floor(amount * (math.max(0.001, c.w) / totalW) + 0.5)
        if share > 0 then
            c.n = c.n + share
            added = added + share
            -- Repopulating ends the grace period, otherwise natural regrowth would stay frozen on top of the manual refill
            c.clearedAt = 0
        end
    end

    ZSim.stats.total = ZSim.stats.total + added
    print(('^5[BS SIM]^7 atlas repopulate by %s: +%d across %d cells')
        :format(actor.label, added, n))

    return { ok = true, added = added, cells = n,
             rect = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, stats = statsBlock() }
end

-- 5. OBSERVE Register/clear an atlas observer at a point.

OPS.observe = function(actor, args)
    local ok, why = ready()
    if not ok then return fail(why) end

    local x, y = num(args and args.x, nil), num(args and args.y, nil)
    local radius = math.min(num(args and args.radius, 300.0), Sim.observer.maxRadius)
    local turnOn = (args == nil) or (args.on ~= false)

    if not x or not y then return fail('x and y required') end

    -- Replace this staff member's observer instead of stacking them, so panning the map does not leave a trail of live regions behind
    local kept, n = {}, 0
    for i = 1, #ZSim.observers do
        local o = ZSim.observers[i]
        if o.by ~= actor.key then n = n + 1 kept[n] = o end
    end
    ZSim.observers = kept

    if not turnOn then
        return { ok = true, cleared = true, observers = #ZSim.observers }
    end

    if #ZSim.observers >= (Sim.observer.max or 8) then
        return fail('too many observers')
    end

    ZSim.observers[#ZSim.observers + 1] = {
        x = x, y = y, radius = radius, by = actor.key,
        until_ = os.time() + (Sim.observer.ttlSeconds or 300),
    }

    return { ok = true, x = x, y = y, radius = radius,
             expiresIn = Sim.observer.ttlSeconds or 300,
             observers = #ZSim.observers }
end

-- 6. CONFIG Read with no args; write with { patch = { ['sense.sightRange'] = 60.0 } }.

-- Whitelist of tunable keys (noise radii, regrowth, population target, crouch multiplier, sense r
local WRITABLE = {
    ['population.target']           = { 1000, 400000 },
    ['sense.sightRange']            = { 5.0, 200.0 },
    ['sense.sightHalfAngle']        = { 10.0, 180.0 },
    ['sense.scentRange']            = { 0.0, 50.0 },
    ['sense.crouchSightMultiplier'] = { 0.01, 1.0 },
    ['sense.proneSightMultiplier']  = { 0.01, 1.0 },
    ['sense.crouchScentMultiplier'] = { 0.01, 1.0 },
    ['sense.stillMultiplier']       = { 0.05, 1.0 },
    ['sense.hearMaxRange']          = { 20.0, 900.0 },
    ['sense.huntMemorySeconds']     = { 1, 120 },
    ['sense.damageTargetSeconds']   = { 1, 300 },
    ['score.loudPower']             = { 0.5, 4.0 },
    ['score.halfLifeSeconds']       = { 2.0, 300.0 },
    ['score.visibleMultiplier']     = { 1.0, 10.0 },
    ['regrow.perCellPerHour']       = { 0.0, 60.0 },
    ['regrow.capFraction']          = { 0.0, 3.0 },
    ['regrow.graceMinutes']         = { 0, 1440 },
    ['migrate.rate']                = { 0.0, 0.5 },
    ['migrate.noiseBias']           = { 0.0, 1.0 },
    ['move.maxDriftFromOrigin']     = { 25.0, 2000.0 },
    ['move.lurkShare']              = { 0.0, 1.0 },
    ['vehicle.followRange']         = { 20.0, 1000.0 },
    ['vehicle.driftSeconds']        = { 5, 900 },
    ['near.promoteRadius']          = { 100.0, 1500.0 },
    ['near.maxAgents']              = { 100, 12000 },
}

local BOOLEAN = {
    ['enabled'] = true, ['regrow.enabled'] = true,
    ['migrate.enabled'] = true, ['vehicle.enabled'] = true,
}

local function readConfig()
    return {
        enabled = Sim.enabled,
        population = Sim.population, grid = Sim.grid, near = Sim.near,
        move = Sim.move, sense = Sim.sense, score = Sim.score,
        vehicle = Sim.vehicle, herd = Sim.herd, regrow = Sim.regrow,
        migrate = Sim.migrate, tick = Sim.tick, observer = Sim.observer,
        spawn = Sim.spawn,
        writable = WRITABLE,
        persisted = false,
    }
end

OPS.config = function(actor, args)

    local patch = (type(args) == 'table' and type(args.patch) == 'table') and args.patch or nil
    if not patch then
        return { ok = true, config = readConfig(), persisted = false }
    end

    local applied, rejected = {}, {}

    for key, value in pairs(patch) do
        local range = WRITABLE[key]
        local isBool = BOOLEAN[key]
        local section, leaf = key:match('^([%w_]+)%.([%w_]+)$')

        if isBool then
            local v = value and true or false
            if section then
                if Sim[section] then Sim[section][leaf] = v applied[key] = v
                else rejected[key] = 'no such section' end
            else
                Sim[key] = v applied[key] = v
            end
        elseif range and section and Sim[section] then
            local v = tonumber(value)
            if not v or v ~= v then
                rejected[key] = 'not a number'
            elseif v < range[1] or v > range[2] then
                -- Values are clamped and reported as clamped, so a slider at the end of its travel does not look broken
                v = math.max(range[1], math.min(range[2], v))
                Sim[section][leaf] = v
                applied[key] = v
                rejected[key] = ('clamped to %s'):format(tostring(v))
            else
                Sim[section][leaf] = v
                applied[key] = v
            end
        else
            rejected[key] = 'not writable'
        end
    end

    if next(applied) then
        local parts = {}
        for k, v in pairs(applied) do parts[#parts + 1] = ('%s=%s'):format(k, tostring(v)) end
        print(('^5[BS SIM]^7 config write by %s: %s')
            :format(actor.label, table.concat(parts, ' ')))
    end

    return { ok = true, applied = applied, rejected = rejected,
             config = readConfig(), persisted = false }
end


-- The two entry points into OPS.

-- In-game identity for the log lines.
local function playerActor(src)
    return { key = src, label = (src == 0) and 'console' or (GetPlayerName(src) or tostring(src)) }
end

-- Entry 1: the six BSB callbacks, gated by bs_admin. bs_atlas's cl_atlas.lua whitelists these six names.
for _, op in ipairs({ 'snapshot', 'inspect', 'edit', 'repopulate', 'observe', 'config', 'survey' }) do
    local fn = OPS[op]
    BSB.RegisterCallback('zombies:atlas:' .. op, function(src, args)
        if not isStaff(src) then return fail('not staff') end
        return fn(playerActor(src), args)
    end)
end

-- Entry 2: exports.bs_zombies:AtlasCall(op, args, via), for the nodes web panel (nodes/server/sv_http.lua), which has no player
exports('AtlasCall', function(op, args, via)
    local fn = type(op) == 'string' and OPS[op] or nil
    if not fn then return fail('unknown atlas op') end
    local label = ('web panel (key holder, not a named person%s)')
        :format(via and via ~= '' and (' - ' .. tostring(via)) or '')
    local ok, res = pcall(fn, { key = 'web', label = label }, type(args) == 'table' and args or {})
    if not ok then
        print(('^1[BS SIM]^7 AtlasCall(%s) threw: %s'):format(op, tostring(res)))
        return fail('server error in atlas ' .. op)
    end
    return res
end)

-- /zsim - same stats block as the snapshot, in the console. /zwhy (cl_sync.lua) and /zpoi (sv_poi.lua) still work.

local function emit(src, line)
    if src == 0 then print(line) else TriggerClientEvent('chat:addMessage', src, { args = { line } }) end
end

RegisterCommand('zsim', function(src)
    if not isStaff(src) then
        emit(src, '^1[BS SIM]^7 refused - staff only.')
        return
    end

    if not (Sim and Sim.enabled) then
        emit(src, '^3[BS SIM]^7 Sim.enabled is false. The simulation layer is inert.')
        return
    end
    if not (ZSim and ZSim.ready) then
        emit(src, '^3[BS SIM]^7 still building the grid.')
        return
    end

    local s = statsBlock()
    emit(src, ('^5[BS SIM]^7 %d zombies | %d individuals | %d cells | %d herds | %d server records')
        :format(s.total, s.individuals, s.cells, s.herds, s.spawnedPeds))
    emit(src, ('^5[BS SIM]^7 %d confirmed records | %d never confirmed | %d client ped copies (%d recent clients)')
        :format(s.confirmedRecords,s.unconfirmedRecords,s.clientRenderedSum,s.reportingClients))
    emit(src, ('^5[BS SIM]^7 target %d | regrowth %.2f/h/cell | agent tick %.2fms | cell tick %.2fms%s')
        :format(s.population, s.regrowthPerHour, s.tickMs, s.cellTickMs,
                s.truncated and ' | ^3TRUNCATED^7' or ''))
    emit(src, ('^5[BS SIM]^7 lifetime: %d promoted, %d demoted, %d killed, %d regrown, %d migrated')
        :format(s.promoted, s.demoted, s.killed, s.regrown, s.migrated))

    -- ~500 individuals is not a cap
    local bubbleCells = math.floor(math.pi * (Sim.near.promoteRadius ^ 2) / (ZSim.cellSize ^ 2) + 0.5)
    emit(src, ('^5[BS SIM]^7 near field: %d individuals of max %d (%s) | %.0fm bubble covers ~%d cells | %.2f zombies/cell here')
        :format(s.individuals, Sim.near.maxAgents,
                s.truncated and '^3CAP BINDING^7' or 'cap not binding',
                Sim.near.promoteRadius, bubbleCells,
                bubbleCells > 0 and (s.individuals / bubbleCells) or 0.0))

    local sense = (ZSimSense and ZSimSense.stats) or {}
    emit(src, ('^5[BS SIM]^7 senses: %d evals | noise %d | sight %d | scent %d | damage %d | vehicle %d')
        :format(sense.evals or 0, sense.noise or 0, sense.sight or 0,
                sense.scent or 0, sense.damage or 0, sense.vehicle or 0))
    emit(src, ('^5[BS SIM]^7 board: %d live points (%d expired, not counted) | %d observers')
        :format(sense.boardPoints or #((ZSimSense and ZSimSense.board) or {}),
                sense.boardStale or 0, s.observers))

    -- Readout of muted players. /zsim names every player the zombies ignore (staff zombie godmode)
    local muted, mutedN = {}, 0
    if ZSimSense and ZSimSense.MutedNames then muted, mutedN = ZSimSense.MutedNames() end

    emit(src, ('^5[BS SIM]^7 players in ladder: %d | muted by ZOMBIE GODMODE: %d%s')
        :format(sense.players or 0, mutedN,
                mutedN > 0 and (' -> ^3' .. table.concat(muted, ', ') .. '^7') or ''))

    if mutedN > 0 then
        emit(src, '^3[BS SIM]^7 A MUTED PLAYER CANNOT BE SEEN OR SMELLED. sight/scent will read 0 for them no matter what the ladder does. Turn ZOMBIE GODMODE off before judging the sense model. (Noise and damage are NOT muted.)')
    end

    if (sense.evals or 0) > 0 and (sense.players or 0) == 0 then
        emit(src, '^1[BS SIM]^7 the ladder is running with ZERO players in its snapshot. That is a real fault, not a toggle - sv_sim_senses.snapshotPlayers is failing. Check the server console for a Lua error in that file.')
    end

    if (sense.boardPoints or 0) == 0 then
        emit(src, '^3[BS SIM]^7 board is empty, so `noise 0` is expected: no sound has been published inside its lifetime. Fire an UNSUPPRESSED weapon (a suppressed one is silent by design, and melee makes no noise) and run /zpoi. If /zpoi shows a point and this still says 0, the fault is between ZPOI and the sim, not in the producer.')
    end

    -- The hit / kill path is where 'damage 0' and '0 killed' are decided
    local h = (Registry and Registry.hitStats) or nil
    if h then
        emit(src, ('^5[BS SIM]^7 hits: %d received | %d no-record | %d out-of-range | %d applied | %d with nodeId | %d WITHOUT')
            :format(h.received or 0, h.noRecord or 0, h.outOfRange or 0,
                    h.applied or 0, h.withNode or 0, h.withoutNode or 0))
        emit(src, ('^5[BS SIM]^7 deaths: %d | RecordDeath called %d | no nodeId %d | ZNodes not ready %d | reward errors %d | gated removals %d')
            :format(h.deaths or 0, h.recordDeath or 0, h.deathNoNode or 0,
                    h.deathNotReady or 0, h.rewardErrors or 0, h.gated or 0))

        if (h.received or 0) == 0 then
            emit(src, '^1[BS SIM]^7 NO HITS HAVE REACHED THE SERVER AT ALL. `0 killed` and `damage 0` follow from that, and so does "the walkers are invincible": the client is not reporting. Look at cl_combat.lua, not at the simulation.')
        elseif (h.withoutNode or 0) > 0 and (h.withNode or 0) == 0 then
            emit(src, '^1[BS SIM]^7 every hit landed on a record with NO nodeId. Those walkers do not belong to the simulation, so nothing can debit a cell and `0 killed` is correct-but-useless. Find out what is creating them: it is not ZStream.Spawn.')
        elseif (h.rewardErrors or 0) > 0 then
            emit(src, '^3[BS SIM]^7 the reward half of the kill path has thrown. Deaths still complete (they are ordered first now) but payouts are being lost - check bs_core:AwardAction.')
        end
    end
end, false)
