-- bs_zombies - sv_sim.lua: the simulation

ZSim = ZSim or {}

-- [key] = cell. The grid is fixed at boot and never grows, so lookups never allocate.
ZSim.cells = {}

-- A flat array of every key, built once at boot. The cell sweep walks a cursor through it.
ZSim.keys = {}
ZSim.cellCursor = 1

-- [id] = agent. Near-field individuals.
ZSim.agents = {}
ZSim.agentCount = 0
ZSim.nextAgentId = 1

-- Flat array of agent ids, rebuilt lazily, for the sliced agent sweep.
ZSim.agentKeys = {}
ZSim.agentCursor = 1

-- Observed clusters, recomputed by the herd sweep. Never a spawn source.
ZSim.herds = {}

--- [n] = { x, y, radius, until_, by } - atlas observers.
ZSim.observers = {}

ZSim.ready = false

ZSim.stats = {
    total = 0, individuals = 0, cells = 0, herds = 0,
    promoted = 0, demoted = 0, killed = 0, regrown = 0, migrated = 0,
    truncated = false,
    tickMs = 0.0, cellTickMs = 0.0, lastSweepAt = 0,
}

-- Helpers. Declared above every use.

local floor, sqrt, cos, sin, atan, pi = math.floor, math.sqrt, math.cos, math.sin, math.atan, math.pi
local random = math.random          -- used only for behaviour jitter, never promotion

local function cfg() return Sim end
local function on() return Sim and Sim.enabled end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Cell size and bounds, resolved once
local CELL = (Sim and Sim.grid and Sim.grid.cell) or 50.0
local BOUNDS = {
    minX = (ZAtlas and ZAtlas.bounds and ZAtlas.bounds.minX) or Sim.grid.minX,
    minY = (ZAtlas and ZAtlas.bounds and ZAtlas.bounds.minY) or Sim.grid.minY,
    maxX = (ZAtlas and ZAtlas.bounds and ZAtlas.bounds.maxX) or Sim.grid.maxX,
    maxY = (ZAtlas and ZAtlas.bounds and ZAtlas.bounds.maxY) or Sim.grid.maxY,
}
ZSim.cellSize = CELL
ZSim.bounds = BOUNDS

local CX0, CY0 = floor(BOUNDS.minX / CELL), floor(BOUNDS.minY / CELL)
local CX1, CY1 = floor(BOUNDS.maxX / CELL), floor(BOUNDS.maxY / CELL)

local function cellIndex(x, y)
    return floor(x / CELL), floor(y / CELL)
end

-- String keys rather than packed integers: the atlas speaks in (cx, cy) and keys are readable in a console dump
local function keyOf(cx, cy) return cx .. ':' .. cy end
ZSim.KeyOf = keyOf

local function inGrid(cx, cy)
    return cx >= CX0 and cx <= CX1 and cy >= CY0 and cy <= CY1
end

-- Centre of a cell, in world coordinates.
local function cellCentre(cx, cy)
    return (cx + 0.5) * CELL, (cy + 0.5) * CELL
end
ZSim.CellCentre = cellCentre

local function getCell(cx, cy)
    if not inGrid(cx, cy) then return nil end
    return ZSim.cells[keyOf(cx, cy)]
end
ZSim.Cell = getCell

function ZSim.CellAt(x, y)
    local cx, cy = cellIndex(x, y)
    return getCell(cx, cy), cx, cy
end

-- Deterministic hashing

local function hash32(a, b, c, d)
    local h = (a * 73856093) ~ (b * 19349663) ~ (c * 83492791) ~ (d * 2654435761)
    h = h & 0xFFFFFFFF
    h = (h ~ (h >> 16)) * 0x45D9F3B & 0xFFFFFFFF
    h = (h ~ (h >> 16)) * 0x45D9F3B & 0xFFFFFFFF
    h = h ~ (h >> 16)
    return h & 0xFFFFFFFF
end

-- A deterministic float in [0,1).
local function hashUnit(a, b, c, d)
    return hash32(a, b, c, d) / 4294967296.0
end

-- The slow clock seeds promotion, so a cell's individuals are stable for epochSeconds and then change
local EPOCH_SECONDS = 300
local function epochNow() return floor(os.time() / EPOCH_SECONDS) end

-- Boot: build the grid and lay down the density map

-- Weights are stamped outward from atlas points instead of gathered per cell: ~3,300 visits instead of 1.6M distance tests at boot
local function stampWeights()
    local P = cfg().population
    local points = (ZAtlas and ZAtlas.points) or {}

    for i = 1, #points do
        local p = points[i]
        -- A point's density figure scales both its weight and its reach: downtown (d=12) is denser and bigger than Grapeseed (d~1.5)
        local reach = P.urbanRadius * clamp((p.d or 1.0) / 6.0, 0.35, 2.2)
        local r2 = reach * reach
        local cx0, cy0 = cellIndex(p.x - reach, p.y - reach)
        local cx1, cy1 = cellIndex(p.x + reach, p.y + reach)

        for cx = cx0, cx1 do
            for cy = cy0, cy1 do
                if inGrid(cx, cy) then
                    local wx, wy = cellCentre(cx, cy)
                    local dd = d2(wx, wy, p.x, p.y)
                    if dd <= r2 then
                        -- Linear falloff; anything smoother is invisible at 50m resolution and costs a sqrt per cell.
                        local t = 1.0 - sqrt(dd) / reach
                        local k = keyOf(cx, cy)
                        local c = ZSim.cells[k]
                        if c then
                            c.w = c.w + P.urbanWeight * (p.d or 1.0) * t
                        end
                    end
                end
            end
        end
    end
end

-- Build every cell, then normalise weights into baselines that sum to Sim.population.target
local function buildGrid()
    local P = cfg().population
    local n = 0

    for cx = CX0, CX1 do
        for cy = CY0, CY1 do
            local k = keyOf(cx, cy)
            ZSim.cells[k] = {
                cx = cx, cy = cy,
                n = 0,              -- far-field count (individuals NOT included)
                w = P.fallbackWeight,
                base = 0,           -- what regrowth climbs back toward
                promoted = false,   -- are this cell's zombies currently records?
                ind = 0,            -- how many of this cell's zombies are records
                lock = false,       -- staff lock: regrowth and migration skip it
                killed = 0,         -- lifetime kills recorded here
                clearedAt = 0,      -- os.time of the last kill
                inFlow = 0, outFlow = 0,
                lastNoiseAt = 0,
            }
            n = n + 1
            ZSim.keys[n] = k
            if (n % 4000) == 0 then Wait(0) end
        end
    end

    stampWeights()
    Wait(0)

    local total = 0.0
    for i = 1, n do total = total + ZSim.cells[ZSim.keys[i]].w end
    if total <= 0 then total = 1.0 end

    local target = P.target or 100000
    local assigned = 0
    for i = 1, n do
        local c = ZSim.cells[ZSim.keys[i]]
        local base = floor((c.w / total) * target + 0.5)
        if base > P.maxCellBaseline then base = P.maxCellBaseline end
        c.base = base
        c.n = base
        assigned = assigned + base
        if (i % 6000) == 0 then Wait(0) end
    end

    ZSim.stats.cells = n
    ZSim.stats.total = assigned
    print(('^2[BS SIM]^7 grid built: %d cells of %.0fm, %d zombies seeded (target %d)')
        :format(n, CELL, assigned, target))
end

-- Anchors: who is causing promotion

local function anchors()
    local out, n = {}, 0

    for _, src in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)
            if at then
                n = n + 1
                out[n] = { x = at.x, y = at.y, r = cfg().near.promoteRadius,
                           dr = cfg().near.demoteRadius, src = tonumber(src), kind = 'player' }
            end
        end
    end

    local now = os.time()
    local kept, m = {}, 0
    for i = 1, #ZSim.observers do
        local o = ZSim.observers[i]
        if o.until_ > now then
            m = m + 1
            kept[m] = o
            n = n + 1
            out[n] = { x = o.x, y = o.y, r = o.radius, dr = o.radius + 120.0,
                       src = o.by, kind = 'observer' }
        end
    end
    ZSim.observers = kept

    return out, n
end
ZSim.Anchors = anchors

-- Promotion: counts become individuals

local function newAgentFromCell(c, slot, epoch)
    local id = ZSim.nextAgentId
    ZSim.nextAgentId = id + 1

    local wx, wy = cellCentre(c.cx, c.cy)
    -- Deterministic position inside the cell
    local ox = (hashUnit(c.cx, c.cy, slot, epoch) - 0.5) * CELL
    local oy = (hashUnit(c.cy, c.cx, slot + 7919, epoch) - 0.5) * CELL
    local head = hashUnit(c.cx + 31, c.cy + 17, slot, epoch) * 360.0

    -- Grouping is emergent: individuals from one cell start within 50m of each other and the wander

    local a = {
        id = id,
        x = wx + ox, y = wy + oy, z = 0.0,
        h = head,
        state = (hashUnit(c.cx, c.cy, slot + 104729, epoch) < cfg().move.lurkShare)
                and 'lurk' or 'wander',
        target = nil,          -- { kind='point'|'player', x, y, src, until_ }
        originX = wx + ox, originY = wy + oy,   -- the 300m leash anchor
        cellKey = keyOf(c.cx, c.cy),
        nextLegAt = 0,
        legX = nil, legY = nil,
        bornAt = os.time(),
        pedId = nil,           -- Registry record id once it is a real ped
    }

    ZSim.agents[id] = a
    ZSim.agentCount = ZSim.agentCount + 1
    ZSim.stats.promoted = ZSim.stats.promoted + 1
    return a
end

local function promoteCell(c, epoch, budget)
    if c.n <= 0 or budget <= 0 then return 0 end
    local want = c.n
    local cap = math.max(0, cfg().near.maxPerCell - c.ind)
    if want > cap then want = cap end
    if want > budget then want = budget end

    for slot = 1, want do
        newAgentFromCell(c, c.ind + slot, epoch)
    end

    c.ind = c.ind + want
    c.n = c.n - want
    c.promoted = true
    return want
end

-- Demotion
local function demoteAgent(a)
    local cx, cy = cellIndex(a.x, a.y)
    local c = getCell(cx, cy)
    if c then
        c.n = c.n + 1
    else
        -- Off the edge of the world: put it back in the cell it came from (in-grid by construction) instead of losing it
        local home = ZSim.cells[a.cellKey]
        if home then home.n = home.n + 1 end
    end

    local from = ZSim.cells[a.cellKey]
    if from and from.ind > 0 then from.ind = from.ind - 1 end
    if from and from.ind == 0 then from.promoted = false end

    ZSim.agents[a.id] = nil
    ZSim.agentCount = ZSim.agentCount - 1
    ZSim.stats.demoted = ZSim.stats.demoted + 1
end

-- Closest cells first, round-robin across anchors. Demote before assigning room.
local promotionTurn = 0
local function promotePass()
    if not on() or not ZSim.ready then return end
    local list, count = anchors()
    -- Nearby players share a promotion bubble
    local clustered = {}
    for _, anchor in ipairs(list) do
        local merged = false
        for _, group in ipairs(clustered) do
            if d2(anchor.x,anchor.y,group.x,group.y) <= 100.0^2 then
                group.r,group.dr=math.max(group.r,anchor.r),math.max(group.dr,anchor.dr)
                merged=true; break
            end
        end
        if not merged then clustered[#clustered+1]=anchor end
    end
    list,count=clustered,#clustered
    local epoch = epochNow()
    for _, ag in pairs(ZSim.agents) do
        if not ag.pedId then
            local keep = false
            for _, anchor in ipairs(list) do
                if d2(ag.x, ag.y, anchor.x, anchor.y) <= anchor.dr * anchor.dr then keep = true break end
            end
            if not keep then demoteAgent(ag) end
        end
    end
    -- Rebalance when another player arrives after the agent pool filled
    if count > 1 then
        local groups = {}
        for i = 1, count do groups[i] = {} end
        for _, ag in pairs(ZSim.agents) do
            if not ag.pedId then
                local owner, best = 1, math.huge
                for i, anchor in ipairs(list) do
                    local distance = d2(ag.x,ag.y,anchor.x,anchor.y)
                    if distance < best then owner,best = i,distance end
                end
                groups[owner][#groups[owner]+1] = {agent=ag,distance=best}
            end
        end
        local quota = math.ceil(cfg().near.maxAgents/count)
        for _, group in ipairs(groups) do
            table.sort(group,function(a,b) return a.distance < b.distance end)
            for i = quota+1, #group do demoteAgent(group[i].agent) end
        end
    end
    local owned = {}
    for i=1,count do owned[i]=0 end
    for _, agent in pairs(ZSim.agents) do
        local owner,best=nil,math.huge
        for i,anchor in ipairs(list) do
            local distance=d2(agent.x,agent.y,anchor.x,anchor.y)
            if distance<best then owner,best=i,distance end
        end
        if owner then owned[owner]=owned[owner]+1 end
    end
    local queues = {}
    for index, anchor in ipairs(list) do
        local cells = {}
        local cx0, cy0 = cellIndex(anchor.x - anchor.r, anchor.y - anchor.r)
        local cx1, cy1 = cellIndex(anchor.x + anchor.r, anchor.y + anchor.r)
        for cx = cx0, cx1 do for cy = cy0, cy1 do
            local c = getCell(cx, cy)
            if c and c.n > 0 and c.ind < cfg().near.maxPerCell then
                local x, y = cellCentre(cx, cy)
                local distance = d2(x, y, anchor.x, anchor.y)
                if distance <= anchor.r * anchor.r then cells[#cells + 1] = { cell = c, distance = distance } end
            end
        end end
        table.sort(cells, function(a, b)
            if a.distance == b.distance then
                return keyOf(a.cell.cx, a.cell.cy) < keyOf(b.cell.cx, b.cell.cy)
            end
            return a.distance < b.distance
        end)
        queues[#queues + 1] = { cells = cells, cursor = 1,
            room=math.max(0,math.ceil(cfg().near.maxAgents/math.max(1,count))-owned[index]) }
    end
    local budget = cfg().near.maxAgents - ZSim.agentCount
    local progress = true
    promotionTurn = promotionTurn + 1
    while budget > 0 and progress do
        progress = false
        for offset = 1, count do
            local q = queues[((offset + promotionTurn - 1) % count) + 1]
            while q.room > 0 and q.cells[q.cursor] do
                local c = q.cells[q.cursor].cell
                if c.n <= 0 or c.ind >= cfg().near.maxPerCell then q.cursor = q.cursor + 1
                else
                    local added = promoteCell(c, epoch, 1)
                    budget = budget - added
                    q.room = q.room - added
                    progress = added > 0 or progress
                    break
                end
            end
            if budget <= 0 then break end
        end
    end
    ZSim.stats.truncated = budget <= 0
    ZSim.stats.individuals = ZSim.agentCount
end


local function leash(a, nx, ny)
    local M = cfg().move.maxDriftFromOrigin
    if d2(nx, ny, a.originX, a.originY) <= M * M then return nx, ny end
    local ang = atan(a.originY - ny, a.originX - nx)
    return nx + cos(ang) * 2.0, ny + sin(ang) * 2.0
end

local function pickLeg(a, now)
    local mv = cfg().move
    a.nextLegAt = now + random(mv.legMinMs, mv.legMaxMs)

    -- A lurking leg is a few metres, a wandering leg is tens
    if random() < mv.lurkShare then
        a.state = 'lurk'
        local ang = random() * pi * 2.0
        local d = 1.0 + random() * 4.0
        a.legX, a.legY = a.x + cos(ang) * d, a.y + sin(ang) * d
    else
        a.state = 'wander'
        -- Biased to keep roughly the same facing; a fresh uniform bearing each leg makes a zombie pace back and forth
        local ang = math.rad(a.h) + (random() - 0.5) * pi * 0.9
        local d = 8.0 + random() * 30.0
        a.legX, a.legY = a.x + cos(ang) * d, a.y + sin(ang) * d
    end

    a.legX, a.legY = leash(a, a.legX, a.legY)
end

local function speedFor(a)
    local mv = cfg().move
    if a.state == 'hunt' then return mv.huntSpeed end
    if a.state == 'drawn' or a.state == 'investigate' then return mv.drawnSpeed end
    if a.state == 'lurk' then return mv.lurkSpeed end
    if a.state == 'feed' then return 0.0 end
    return mv.wanderSpeed
end

-- Move a toward (tx, ty) at its state's speed. Returns true on arrival.
local function stepToward(a, tx, ty, dt)
    local dx, dy = tx - a.x, ty - a.y
    local dist = sqrt(dx * dx + dy * dy)
    if dist < 0.6 then return true end
    local step = math.min(dist, speedFor(a) * dt)
    local nx, ny = a.x + dx / dist * step, a.y + dy / dist * step
    local fraction = ZPolicy.ApproachFraction(a.x, a.y, nx, ny,
        ZSim.materialisePlayers or {}, ((Streaming and Streaming.spawnMin) or 140) + 35)
    a.waitingForPed = fraction < 1
    a.x, a.y = a.x + (nx - a.x) * fraction, a.y + (ny - a.y) * fraction
    if step >= dist and fraction == 1 then return true end
    a.h = (math.deg(atan(dy, dx)) + 360.0) % 360.0
    return false
end

-- One agent, one tick. The order here is the sense ladder's precedence.
local function tickAgent(a, now, dt)
    local stim = nil
    if ZSimSense and ZSimSense.Evaluate then
        stim = ZSimSense.Evaluate(a, now)
    end

    if stim then
        a.stim = stim.kind
        a.stimAt = now

        if stim.kind == 'damage' or stim.kind == 'scent' or stim.kind == 'sight' then
            -- Only these three may name a person; that is the rule the ladder exists to enforce.
            a.state = 'hunt'
            a.target = { kind = 'player', src = stim.src, x = stim.x, y = stim.y,
                         until_ = now + cfg().sense.huntMemorySeconds * 1000 }
        elseif stim.kind == 'noise' or stim.kind == 'vehicle' then
            -- Zombies go to where they heard the sound: the point, never the player, even if the point is on a player
            a.state = 'drawn'
            a.target = { kind = 'point', x = stim.x, y = stim.y, until_ = stim.until_ }
            a.originX, a.originY = a.x, a.y      -- re-anchor the leash; see leash()
        end
    end

    -- A record that owns a ped is steered by its host client
    if a.pedId then return end

    local t = a.target
    if t and t.until_ and now > t.until_ then
        -- The target expired
        if t.kind == 'player' then
            a.target = { kind = 'point', x = t.x, y = t.y, until_ = now + 20000 }
            a.state = 'investigate'
        else
            a.target = nil
            a.state = 'wander'
            a.nextLegAt = 0
        end
        t = a.target
    end

    if t then
        if stepToward(a, t.x, t.y, dt) then
            if t.kind == 'point' then
                -- Arrived at the point. Mill around instead of idling; a crowd that stops dead looks scripted.
                a.target = nil
                a.state = 'lurk'
                a.nextLegAt = 0
            end
        end
        return
    end

    if now >= (a.nextLegAt or 0) then pickLeg(a, now) end
    if a.legX then
        if stepToward(a, a.legX, a.legY, dt) then a.nextLegAt = 0 end
    end
end

-- Herd observation. A herd is 20+ zombies gathered in one area.

-- Sliced like every other sweep here
local herdCursor = 1
local herdPending, herdPendingN = {}, 0
local herdSeen = {}

local function herdSweep()
    if not ZSim.ready then return end
    local H = cfg().herd
    local threshold = H.minCount
    local floorCount = floor(threshold / 4)

    local total = #ZSim.keys
    if total == 0 then return end
    local slice = (cfg().tick.herdCellsPerSlice) or 6000
    local stop = math.min(herdCursor + slice - 1, total)

    for i = herdCursor, stop do
        local k = ZSim.keys[i]
        local c = ZSim.cells[k]
        if c and (c.n + c.ind) >= floorCount and not herdSeen[k] then
            local sum, sx, sy = 0, 0.0, 0.0
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local nb = getCell(c.cx + dx, c.cy + dy)
                    if nb then
                        local q = nb.n + nb.ind
                        if q > 0 then
                            local wx, wy = cellCentre(nb.cx, nb.cy)
                            sum = sum + q
                            sx = sx + wx * q
                            sy = sy + wy * q
                        end
                    end
                end
            end
            if sum >= threshold then
                -- Claim the 3x3 so one crowd is not reported nine times with nine centres.
                for dx = -1, 1 do for dy = -1, 1 do
                    herdSeen[keyOf(c.cx + dx, c.cy + dy)] = true
                end end
                herdPendingN = herdPendingN + 1
                herdPending[herdPendingN] = { x = sx / sum, y = sy / sum, n = sum, r = H.radius }
            end
        end
    end

    herdCursor = stop + 1
    if herdCursor > total then
        -- Wrapped: publish the pass and start a clean one.
        ZSim.herds = herdPending
        ZSim.stats.herds = herdPendingN
        herdPending, herdPendingN = {}, 0
        herdSeen = {}
        herdCursor = 1
    end
end

-- Far field sweep: migration and regrowth

local function regrowCell(c, now, hours)
    local R = cfg().regrow
    if not R.enabled or c.lock then return 0 end

    local cap = floor(c.base * R.capFraction)
    local have = c.n + c.ind
    if have >= cap then return 0 end

    -- The grace period: a hole should feel like a hole.
    if c.clearedAt > 0 and (now - c.clearedAt) < (R.graceMinutes * 60) then return 0 end

    -- Fractional accumulation: a cell regrowing 1.5/hour visited every 29s is owed 0.012 of a zombie
    c.acc = (c.acc or 0.0) + R.perCellPerHour * hours
    local whole = floor(c.acc)
    if whole < 1 then return 0 end
    c.acc = c.acc - whole
    if have + whole > cap then whole = cap - have end
    if whole < 1 then return 0 end

    c.n = c.n + whole
    ZSim.stats.regrown = ZSim.stats.regrown + whole
    ZSim.stats.total = ZSim.stats.total + whole
    return whole
end

-- Migration
local function migrateCell(c, now)
    local M = cfg().migrate
    if not M.enabled or c.lock or c.n <= 0 then return 0 end

    local move = floor(c.n * M.rate)
    if move < 1 then
        -- Below one zombie per sweep, migrate probabilistically; otherwise cells under 50 zombies would be frozen, which is most of the map
        if random() > (c.n * M.rate) then return 0 end
        move = 1
    end

    local bx, by = nil, nil
    if ZSimSense and ZSimSense.BestPointNear then
        local wx, wy = cellCentre(c.cx, c.cy)
        local p = ZSimSense.BestPointNear(wx, wy, cfg().sense.hearMaxRange)
        if p and random() < M.noiseBias then bx, by = p.x, p.y end
    end

    local best, bestScore = nil, -1e9
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                local nb = getCell(c.cx + dx, c.cy + dy)
                if nb and not nb.lock then
                    local score
                    if bx then
                        local wx, wy = cellCentre(nb.cx, nb.cy)
                        score = -d2(wx, wy, bx, by)
                    else
                        score = (nb.base - (nb.n + nb.ind)) + random() * 2.0
                    end
                    if score > bestScore then best, bestScore = nb, score end
                end
            end
        end
    end

    if not best then return 0 end
    if move > c.n then move = c.n end
    c.n = c.n - move
    best.n = best.n + move
    c.outFlow = c.outFlow + move
    best.inFlow = best.inFlow + move
    ZSim.stats.migrated = ZSim.stats.migrated + move
    return move
end

-- Kills

-- Called by the registry when a walker dies, and by the compat shim so the existing death path needs no edit
function ZSim.RecordDeath(agentId, x, y)
    local a = agentId and ZSim.agents[agentId] or nil
    -- Replayed deaths and local-mode kills cannot debit unrelated density.
    if not a then return false end
    if a then
        x = x or a.x; y = y or a.y
        local from = ZSim.cells[a.cellKey]
        if from and from.ind > 0 then
            from.ind = from.ind - 1
            if from.ind == 0 then from.promoted = false end
        end
        ZSim.agents[agentId] = nil
        ZSim.agentCount = ZSim.agentCount - 1
    end

    if not x or not y then return false end
    local cx, cy = cellIndex(x, y)
    local c = getCell(cx, cy)
    if not c then c = ZSim.cells[a.cellKey] end
    if not c then return false end
    c.killed = c.killed + 1
    c.clearedAt = os.time()
    c.acc = 0.0
    ZSim.stats.killed = ZSim.stats.killed + 1
    ZSim.stats.total = math.max(0, ZSim.stats.total - 1)
    return true
end

-- Queries used by the rest of the resource and by the atlas

-- Individuals inside a rectangle, capped. Bounded by the agent ceiling.
function ZSim.AgentsInRect(x1, y1, x2, y2, cap)
    local out, n = {}, 0
    cap = cap or 1500
    local truncated = false
    for _, a in pairs(ZSim.agents) do
        if a.x >= x1 and a.x <= x2 and a.y >= y1 and a.y <= y2 then
            if n >= cap then truncated = true break end
            n = n + 1
            out[n] = a
        end
    end
    return out, n, truncated
end

-- Individuals within radius of a point, nearest first
function ZSim.AgentsNear(x, y, radius)
    local out, n = {}, 0
    local r2 = radius * radius
    for _, a in pairs(ZSim.agents) do
        local dd = d2(a.x, a.y, x, y)
        if dd <= r2 then
            n = n + 1
            out[n] = { agent = a, d2 = dd }
        end
    end
    table.sort(out, function(p, q) return p.d2 < q.d2 end)
    local flat = {}
    for i = 1, n do flat[i] = out[i].agent end
    return flat, n
end

-- Total population: far-field counts plus live individuals.
function ZSim.Total()
    return ZSim.stats.total
end

-- Threads

CreateThread(function()
    if not on() then
        print('^3[BS SIM]^7 Sim.enabled is false - the simulation layer is inert.')
        return
    end
    buildGrid()
    ZSim.ready = true
end)

-- Agents. Sliced: agentsPerSlice records per agentMs.
CreateThread(function()
    while true do
        Wait((cfg().tick and cfg().tick.agentMs) or 250)
        if on() and ZSim.ready then
            local t0 = os.clock()
            local now = GetGameTimer()
            do
                ZSim.materialisePlayers = {}
                for _, anchor in ipairs(anchors()) do
                    if anchor.kind == 'player' then ZSim.materialisePlayers[#ZSim.materialisePlayers + 1] = anchor end
                end
                -- Rebuild the key array when the cursor wraps, not every tick: pairs() over 2500 agents every 250ms adds up with many players
                if ZSim.agentCursor > #ZSim.agentKeys then
                    local keys, n = {}, 0
                    for id in pairs(ZSim.agents) do n = n + 1 keys[n] = id end
                    ZSim.agentKeys = keys
                    ZSim.agentCursor = 1
                end

                local slice = (cfg().tick.agentsPerSlice) or 400
                local stop = math.min(ZSim.agentCursor + slice - 1, #ZSim.agentKeys)
                -- dt is the time since the last tick

                for i = ZSim.agentCursor, stop do
                    local a = ZSim.agents[ZSim.agentKeys[i]]
                    if a then
                        local dt = math.min(2.0, math.max(0, now - (a.lastTickAt or now)) / 1000.0)
                        a.lastTickAt = now
                        tickAgent(a, now, dt)
                    end
                end
                ZSim.agentCursor = stop + 1
                ZSim.stats.tickMs = (os.clock() - t0) * 1000.0
            end
        end
    end
end)

-- Far field. Sliced: cellsPerSlice cells per cellMs. Never the whole grid.
CreateThread(function()
    local lastVisit = os.time()
    while true do
        Wait((cfg().tick and cfg().tick.cellMs) or 1000)
        if on() and ZSim.ready then
            local t0 = os.clock()
            local now = os.time()
            local slice = (cfg().tick.cellsPerSlice) or 1500
            local total = #ZSim.keys
            if total > 0 then
                -- Hours since this cell was last visited = one full pass.
                local passSeconds = (total / slice) * ((cfg().tick.cellMs or 1000) / 1000.0)
                local hours = passSeconds / 3600.0

                local stop = math.min(ZSim.cellCursor + slice - 1, total)
                for i = ZSim.cellCursor, stop do
                    local c = ZSim.cells[ZSim.keys[i]]
                    if c then
                        regrowCell(c, now, hours)
                        migrateCell(c, now)
                    end
                end
                ZSim.cellCursor = stop + 1
                if ZSim.cellCursor > total then
                    ZSim.cellCursor = 1
                    ZSim.stats.lastSweepAt = now
                    lastVisit = now
                end
            end
            ZSim.stats.cellTickMs = (os.clock() - t0) * 1000.0
        end
    end
end)

-- Promotion / demotion.
CreateThread(function()
    while true do
        Wait((cfg().tick and cfg().tick.promoteMs) or 2000)
        if on() and ZSim.ready then promotePass() end
    end
end)

-- Herd observation.
CreateThread(function()
    while true do
        Wait((cfg().tick and cfg().tick.herdMs) or 5000)
        if on() and ZSim.ready then herdSweep() end
    end
end)
