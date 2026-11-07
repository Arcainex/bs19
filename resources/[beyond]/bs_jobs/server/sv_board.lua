-- bs_jobs job board: contracts per job, progress from gameplay, turn-ins, routes and the scoreboard.

local S = Jobs.Settings
local q, x = J.q, J.x
local C = {}          -- [id] = contract
J.Contracts = C

local function tplOf(job, id)
    for _, t in ipairs(Jobs.Contracts[job] or {}) do if t.id == id then return t end end
end
local function rnd(r) if type(r) ~= 'table' then return tonumber(r) or 1 end; return math.random(r[1], r[2] or r[1]) end
local function pickN(list, n)
    local idx, out = {}, {}
    for i = 1, #list do idx[i] = i end
    for i = #idx, 2, -1 do local j = math.random(i); idx[i], idx[j] = idx[j], idx[i] end
    for i = 1, math.min(n, #idx) do local p = list[idx[i]]; out[#out + 1] = { x = p.x, y = p.y, z = p.z, id = p.id } end
    return out
end

local function save(c)
    if c.id then
        x('UPDATE bs_job_contracts SET status = ?, taken_by = ?, taken_at = ?, progress = ?, data = ? WHERE id = ?',
            { c.status, c.takenBy, c.takenAt or 0, c.progress or 0, json.encode(c.data or {}), c.id })
    end
end
local function remove(c)
    C[c.id] = nil
    x('DELETE FROM bs_job_contracts WHERE id = ?', { c.id })
end

-- Rolls a new contract from a template.
local function create(fid, job, tpl)
    local d = { target = 1 }
    if tpl.kind == 'count' or tpl.kind == 'nest' then d.target = rnd(tpl.amount) end
    if tpl.kind == 'deliver' then
        d.items = {}
        for _, it in ipairs(tpl.items or {}) do d.items[#d.items + 1] = { item = it.item, amount = rnd(it.amount) } end
    elseif tpl.kind == 'nest' then d.points = pickN(Jobs.Nests, 1)
    elseif tpl.kind == 'route' then d.points = pickN(Jobs.RoutePoints, tpl.points or 3); d.target = #d.points
    elseif tpl.kind == 'supply' then d.points = pickN(Jobs.SupplyDrops, 1); d.target = 2
    elseif tpl.kind == 'service' then d.points = pickN(Jobs.Generators, 1)
    elseif tpl.kind == 'smuggle' then d.points = pickN(Jobs.SmuggleDrops, 1)
    end
    local now = J.Now()
    local id = MySQL.insert.await('INSERT INTO bs_job_contracts (faction_id, job_id, template, data, status, created_at, expires_at) VALUES (?,?,?,?,?,?,?)',
        { fid, job, tpl.id, json.encode(d), 'open', now, now + math.floor((tonumber(S.boardRefreshMin) or 45) * 60) })
    if not id then return nil end
    C[id] = { id = id, fid = fid, job = job, tpl = tpl.id, data = d, status = 'open', progress = 0, created = now }
    return C[id]
end

-- Keeps each job's board topped up for a faction.
function J.FillBoard(fid)
    local per = J.IsVanilla(fid) and (tonumber(S.vanillaBoardPerJob) or 3) or (tonumber(S.playerBoardPerJob) or 2)
    for _, job in ipairs(J.JobsOf(fid)) do
        local list = Jobs.Contracts[job] or {}
        if #list > 0 then
            local open, used = 0, {}
            for _, c in pairs(C) do
                if c.fid == fid and c.job == job and c.status == 'open' then open = open + 1; used[c.tpl] = true end
            end
            local guard = 0
            while open < per and guard < 10 do
                guard = guard + 1
                local fresh = {}
                for _, t in ipairs(list) do if not used[t.id] then fresh[#fresh + 1] = t end end
                local t = (#fresh > 0 and fresh or list)[math.random(#(#fresh > 0 and fresh or list))]
                if create(fid, job, t) then open = open + 1; used[t.id] = true end
            end
        end
    end
end

function J.ActiveOf(cid)
    for _, c in pairs(C) do if c.status == 'taken' and c.takenBy == cid then return c end end
end

local function title(src, c)
    local tpl = tplOf(c.job, c.tpl) or {}
    local vars = { n = c.data.target }
    if c.data.items then
        local parts = {}
        for _, it in ipairs(c.data.items) do
            local label = it.item
            pcall(function() label = exports.bs_inventory:ItemLabel(it.item, src) or it.item end)
            parts[#parts + 1] = ('%dx %s'):format(it.amount, label)
        end
        vars.items = table.concat(parts, ', ')
    end
    return Lp(src, 'ct.' .. tostring(tpl.id or c.tpl), vars)
end

local function view(src, c, cid)
    local tpl = tplOf(c.job, c.tpl) or {}
    local mult = J.IsVanilla(c.fid) and (tonumber(S.vanillaRewardMult) or 1.5) or (tonumber(S.playerRewardMult) or 1.0)
    local left = c.status == 'taken' and ((c.takenAt or 0) + math.floor((tonumber(S.takenMinutes) or 90) * 60) - J.Now()) or nil
    return {
        id = c.id, job = c.job, jobLabel = J.JobLabel(src, c.job), kind = tpl.kind, label = title(src, c),
        target = c.data.target, progress = c.progress or 0, status = c.status, mine = c.takenBy == cid,
        rep = math.floor((tpl.rep or 0) * mult), xp = math.floor((tpl.xp or 0) * mult), left = left,
        points = c.status == 'taken' and c.takenBy == cid and c.data.points or nil,
        turnIn = tpl.kind == 'deliver' or (tpl.kind == 'supply' and (c.progress or 0) >= 1),
    }
end

-- Sends the active contract to its taker (blips and route points on the client).
function J.PushActive(src, cid)
    cid = cid or J.CharId(src)
    local c = cid and J.ActiveOf(cid)
    TriggerClientEvent('bs:jobs:active', src, c and view(src, c, cid) or false)
end

local function complete(c, src)
    local tpl = tplOf(c.job, c.tpl) or {}
    local cid = c.takenBy
    remove(c)
    local got = J.Reward(src, cid, c.fid, tpl, c.job)
    if src then
        J.Notify(src, 'success', 'n.contract_done', { rep = got.rep, xp = got.xp })
        J.PushActive(src, cid)
    end
    J.Log(src, 'contract', ('%s %s/%s rep %d'):format(tostring(cid), c.fid, c.tpl, got.rep))
    TriggerEvent('bs:jobs:completed', src, c.job, c.tpl)
end

-- Progress from gameplay. Only the contract the player has taken counts, and only for their current job.
function J.Progress(src, kind, n, pos)
    local cid = J.CharId(src)
    local c = cid and J.ActiveOf(cid)
    if not c then return end
    local job, m = J.JobOf(src)
    if job ~= c.job or m.fid ~= c.fid then return end
    local tpl = tplOf(c.job, c.tpl)
    if not tpl then return end
    if tpl.kind == 'count' and tpl.event == kind then
        -- fine
    elseif tpl.kind == 'nest' and kind == 'zombie_kill' then
        local p, at = c.data.points and c.data.points[1], pos or J.PedPos(src)
        if not p or not at or #(vector2(at.x, at.y) - vector2(p.x, p.y)) > (tpl.radius or 80.0) then return end
    else
        return
    end
    c.progress = math.min(c.data.target, (c.progress or 0) + math.max(1, math.floor(tonumber(n) or 1)))
    if c.progress >= c.data.target then complete(c, src) else save(c); J.PushActive(src, cid) end
end

-- Server-only event other resources fire (never a net event).
AddEventHandler('bs:jobs:event', function(src, kind, n)
    src = tonumber(src)
    if src and J.Ready then J.Progress(src, tostring(kind), n) end
end)

local ACTION = {
    zombie_kill = 'zombie_kill', zombie_kill_headshot = 'zombie_kill', zombie_kill_brute = 'zombie_kill',
    horde_cleared = 'horde_cleared', wound_treated = 'wound_treated', player_revived = 'player_revived',
    -- vehicle_repaired is sent directly (bs:jobs:event) by bs_vehicles and the garage, so it is not counted here twice
    vehicle_scrapped = 'vehicle_scrapped', vehicle_hotwired = 'vehicle_hotwired',
    resource_gathered = 'resource_gathered',
}
AddEventHandler('bs:hook:player:action', function(player, actionId)
    local src = type(player) == 'table' and tonumber(player.source)
    if src and ACTION[actionId] and J.Ready then J.Progress(src, ACTION[actionId], 1) end
end)

--------------------------------------------------------------------------------
-- Board callbacks
--------------------------------------------------------------------------------

local function board(src)
    local cid, fid = J.CharId(src), J.Faction(src)
    if not cid or not fid then return { ok = false, error = Lp(src, 'err.no_faction') } end
    J.FillBoard(fid)
    local list = {}
    for _, c in pairs(C) do
        if c.fid == fid and (c.status == 'open' or c.takenBy == cid) then list[#list + 1] = view(src, c, cid) end
    end
    table.sort(list, function(a, b) if a.mine ~= b.mine then return a.mine end; if a.job ~= b.job then return a.job < b.job end; return a.id < b.id end)
    local job = J.JobOf(src)
    return { ok = true, contracts = list, job = job, jobLabel = job and J.JobLabel(src, job) or nil,
             refreshMin = S.boardRefreshMin, takenMinutes = S.takenMinutes }
end

local function take(src, a)
    a = type(a) == 'table' and a or {}
    local cid = J.CharId(src)
    local c = C[tonumber(a.id) or -1]
    local job, m = J.JobOf(src)
    if not c or c.status ~= 'open' then return { ok = false, error = Lp(src, 'err.gone') } end
    if not job or job ~= c.job or m.fid ~= c.fid then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    if J.ActiveOf(cid) then return { ok = false, error = Lp(src, 'err.one_active') } end
    local tpl = tplOf(c.job, c.tpl)
    if tpl and tpl.kind == 'smuggle' then
        if not exports.bs_inventory:GiveItem(src, 'contraband', 1) then return { ok = false, error = Lp(src, 'err.bag_full') } end
    end
    c.status, c.takenBy, c.takenAt, c.progress = 'taken', cid, J.Now(), 0
    save(c)
    J.PushActive(src, cid)
    J.Log(src, 'take', ('%s/%s #%d'):format(c.fid, c.tpl, c.id))
    return board(src)
end

local function release(c, src)
    local tpl = tplOf(c.job, c.tpl)
    if tpl and tpl.kind == 'smuggle' and src then pcall(function() exports.bs_inventory:RemoveItem(src, 'contraband', 1) end) end
    if tpl and tpl.kind == 'supply' and src and (c.progress or 0) >= 1 then pcall(function() exports.bs_inventory:RemoveItem(src, 'supply_crate', 1) end) end
    remove(c)
end

local function abandon(src, a)
    a = type(a) == 'table' and a or {}
    local cid = J.CharId(src)
    local c = C[tonumber(a.id) or -1]
    if not c or c.takenBy ~= cid or c.status ~= 'taken' then return { ok = false, error = Lp(src, 'err.gone') } end
    release(c, src)
    J.PushActive(src, cid)
    return board(src)
end

-- Deliveries and the supply crate are handed in at one of the faction's job stations.
local function turnIn(src, a)
    a = type(a) == 'table' and a or {}
    local cid = J.CharId(src)
    local c = C[tonumber(a.id) or -1]
    if not c or c.takenBy ~= cid or c.status ~= 'taken' then return { ok = false, error = Lp(src, 'err.gone') } end
    if not J.NearStation(src, c.fid, tonumber(S.turnInRadius) or 10.0) then return { ok = false, error = Lp(src, 'err.not_at_station') } end
    local tpl = tplOf(c.job, c.tpl) or {}
    local INV = exports.bs_inventory
    if tpl.kind == 'deliver' then
        for _, it in ipairs(c.data.items or {}) do
            if INV:CountItem(src, it.item) < it.amount then
                return { ok = false, error = Lp(src, 'err.missing_items', { item = INV:ItemLabel(it.item, src) or it.item, n = it.amount }) }
            end
        end
        for _, it in ipairs(c.data.items or {}) do
            if not INV:RemoveItem(src, it.item, it.amount) then J.Flag(src, 'turnin', 'remove failed ' .. it.item); return { ok = false } end
        end
        -- Fuel Runner cans go into the emptiest gas station (bs_vehicles).
        if c.job == 'fuel_runner' and GetResourceState('bs_vehicles') == 'started' then
            local cans = 0
            for _, it in ipairs(c.data.items or {}) do if it.item == 'fuel_can' then cans = cans + it.amount end end
            if cans > 0 then pcall(function() exports.bs_vehicles:PumpDeliver(src, cans * 35) end) end
        end
    elseif tpl.kind == 'supply' then
        if (c.progress or 0) < 1 then return { ok = false, error = Lp(src, 'err.not_yet') } end
        if not INV:RemoveItem(src, 'supply_crate', 1) then return { ok = false, error = Lp(src, 'err.missing_items', { item = INV:ItemLabel('supply_crate', src), n = 1 }) } end
    else
        return { ok = false }
    end
    complete(c, src)
    return board(src)
end

-- Timed point actions (supply pickup, generator service, smuggle drop). start hands out a token, reach checks it.
local tokens = {}
local REACH_MS = { supply = 8000, service = 12000, smuggle = 5000, route = 0, nest = 0 }

local function atPoint(src, c, idx, radius)
    local p = c.data.points and c.data.points[idx]
    local at = J.PedPos(src)
    return p and at and #(vector2(at.x, at.y) - vector2(p.x, p.y)) <= (radius or 15.0)
end

BSB.RegisterCallback('jobs:reachStart', function(src, id, idx)
    local cid = J.CharId(src)
    local c = C[tonumber(id) or -1]
    if not c or c.takenBy ~= cid or c.status ~= 'taken' then return { ok = false } end
    local tpl = tplOf(c.job, c.tpl) or {}
    idx = tonumber(idx) or 1
    if not atPoint(src, c, idx, 15.0) then return { ok = false, error = Lp(src, 'err.not_there') } end
    if tpl.kind == 'service' and exports.bs_inventory:CountItem(src, 'fuel_can') < 1 then
        return { ok = false, error = Lp(src, 'err.need_item', { item = exports.bs_inventory:ItemLabel('fuel_can', src) }) }
    end
    tokens[src] = { id = c.id, idx = idx, at = GetGameTimer() }
    return { ok = true, ms = REACH_MS[tpl.kind] or 0 }
end)

BSB.RegisterCallback('jobs:reach', function(src, id, idx)
    local cid = J.CharId(src)
    local c = C[tonumber(id) or -1]
    local t = tokens[src]
    tokens[src] = nil
    if not c or c.takenBy ~= cid or c.status ~= 'taken' or not t or t.id ~= c.id then return { ok = false } end
    local tpl = tplOf(c.job, c.tpl) or {}
    idx = tonumber(idx) or 1
    if t.idx ~= idx or GetGameTimer() - t.at < (REACH_MS[tpl.kind] or 0) - 700 then J.Flag(src, 'reach_fast', c.tpl); return { ok = false } end
    if not atPoint(src, c, idx, 15.0) then return { ok = false, error = Lp(src, 'err.not_there') } end
    local INV = exports.bs_inventory
    if tpl.kind == 'route' then
        if idx ~= (c.progress or 0) + 1 then return { ok = false } end
        local ped = GetPlayerPed(src)
        if tpl.vehicle and GetVehiclePedIsIn(ped, false) == 0 then return { ok = false, error = Lp(src, 'err.need_vehicle') } end
        if (tpl.escort or 0) > 0 then
            local near, at = 0, GetEntityCoords(ped)
            for _, v in ipairs(GetPlayers()) do
                local o = tonumber(v)
                if o ~= src and J.Faction(o) == c.fid then
                    local op = J.PedPos(o)
                    if op and #(op - at) <= 60.0 then near = near + 1 end
                end
            end
            if near < tpl.escort then return { ok = false, error = Lp(src, 'err.need_escort', { n = tpl.escort }) } end
        end
        c.progress = idx
        if c.progress >= #c.data.points then complete(c, src) else save(c); J.PushActive(src, cid) end
    elseif tpl.kind == 'supply' then
        if (c.progress or 0) >= 1 then return { ok = false } end
        if not INV:GiveItem(src, 'supply_crate', 1) then return { ok = false, error = Lp(src, 'err.bag_full') } end
        c.progress = 1
        save(c)
        J.PushActive(src, cid)
        J.Notify(src, 'info', 'n.crate_home')
    elseif tpl.kind == 'service' then
        if not INV:RemoveItem(src, 'fuel_can', 1) then return { ok = false, error = Lp(src, 'err.need_item', { item = INV:ItemLabel('fuel_can', src) }) } end
        -- the serviced generator actually gets the fuel (bs_world)
        local pt = c.data and c.data.points and c.data.points[1]
        if pt and pt.id and GetResourceState('bs_world') == 'started' then
            pcall(function() exports.bs_world:ServiceZone(pt.id) end)
        end
        complete(c, src)
    elseif tpl.kind == 'smuggle' then
        if not INV:RemoveItem(src, 'contraband', 1) then return { ok = false, error = Lp(src, 'err.lost_cargo') } end
        complete(c, src)
    else
        return { ok = false }
    end
    return { ok = true }
end)

-- Scoreboard: rep earned and contracts completed, this week or all time.
local function scores(src, a)
    a = type(a) == 'table' and a or {}
    local fid, cid = J.Faction(src), J.CharId(src)
    if not fid then return { ok = false, error = Lp(src, 'err.no_faction') } end
    local rows
    if a.period == 'all' then
        rows = q('SELECT character_id, SUM(rep) AS rep, SUM(contracts) AS contracts FROM bs_job_stats WHERE faction_id = ? GROUP BY character_id', { fid })
    else
        rows = q('SELECT character_id, rep, contracts FROM bs_job_stats WHERE faction_id = ? AND week = ?', { fid, J.Week() })
    end
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = tonumber(r.character_id) end
    local names = J.Names(ids)
    local list = {}
    for _, r in ipairs(rows) do
        local c = tonumber(r.character_id)
        local m = J.Members[c]
        list[#list + 1] = { cid = c, name = names[c] or ('#' .. c), rep = tonumber(r.rep) or 0, contracts = tonumber(r.contracts) or 0,
                            job = m and m.fid == fid and m.status == 'active' and J.JobLabel(src, m.job) or nil, you = c == cid }
    end
    return { ok = true, period = a.period == 'all' and 'all' or 'week', rows = list }
end

BSB.RegisterCallback('jobs:board', board)
BSB.RegisterCallback('jobs:take', take)
BSB.RegisterCallback('jobs:abandon', abandon)
BSB.RegisterCallback('jobs:turnin', turnIn)
BSB.RegisterCallback('jobs:scores', scores)
BSB.RegisterCallback('jobs:active', function(src) J.PushActive(src); return { ok = true } end)

-- Losing the job drops a taken contract too.
J.OnDropped = function(cid)
    local c = J.ActiveOf(cid)
    if c then release(c, J.SrcOf(cid)) end
end
J.OnUnpicked = function(fid, job)
    for _, c in pairs(C) do if c.fid == fid and c.job == job then remove(c) end end
end

-- Expire old offers and overdue contracts, then refill boards of factions with someone online.
CreateThread(function()
    while not J.Ready do Wait(500) end
    for _, r in ipairs(q("SELECT * FROM bs_job_contracts WHERE status IN ('open','taken')")) do
        local ok, d = pcall(json.decode, r.data or '{}')
        C[tonumber(r.id)] = { id = tonumber(r.id), fid = r.faction_id, job = r.job_id, tpl = r.template, data = ok and d or {},
                              status = r.status, takenBy = tonumber(r.taken_by), takenAt = tonumber(r.taken_at) or 0,
                              progress = tonumber(r.progress) or 0, created = tonumber(r.created_at) or 0 }
    end
    x("DELETE FROM bs_job_contracts WHERE status NOT IN ('open','taken')")
    while true do
        local now = J.Now()
        local life = math.floor((tonumber(S.boardRefreshMin) or 45) * 60)
        local taken = math.floor((tonumber(S.takenMinutes) or 90) * 60)
        for _, c in pairs(C) do
            if c.status == 'open' and now - (c.created or 0) > life then
                remove(c)
            elseif c.status == 'taken' and now - (c.takenAt or 0) > taken then
                local src = J.SrcOf(c.takenBy)
                release(c, src)
                if src then J.Notify(src, 'warn', 'n.contract_expired'); J.PushActive(src) end
            elseif not tplOf(c.job, c.tpl) then
                remove(c)
            end
        end
        local seen = {}
        for _, v in ipairs(GetPlayers()) do
            local fid = J.Faction(tonumber(v))
            if fid and not seen[fid] then seen[fid] = true; J.FillBoard(fid) end
        end
        Wait(60000)
    end
end)

AddEventHandler('playerDropped', function() tokens[source] = nil end)

-- Mission Log (bs_inventory): the contract this player has taken. Turn-ins happen at a job station.
exports('MissionLogList', function(src)
    src = tonumber(src)
    local cid = src and J.CharId(src)
    local c = cid and J.ActiveOf(cid)
    if not c then return {} end
    local v = view(src, c, cid)
    local tpl = tplOf(c.job, c.tpl) or {}
    local done = (tpl.kind == 'supply' and (c.progress or 0) >= 1) or false
    local vars = { rep = v.rep, xp = v.xp, min = math.max(0, math.floor((v.left or 0) / 60)) }
    local label = v.label
    if v.target and v.target > 1 and tpl.kind ~= 'deliver' then
        label = Lp(src, 'mlog.job_progress', { label = v.label, p = v.progress, n = v.target })
    end
    return { {
        id = 'job:' .. tostring(c.id), title = v.jobLabel, group = Lp(src, 'mlog.job_group'),
        steps = { { label = label, done = done } },
        complete = done, claimed = false, noClaim = true,
        hint = Lp(src, v.turnIn and 'mlog.job_station' or 'mlog.job_auto', vars),
    } }
end)
exports('MissionLogClaim', function() return { ok = false } end)

local function registerLog()
    if GetResourceState('bs_inventory') == 'started' then
        pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end)
    end
end
CreateThread(function() Wait(1500); registerLog() end)
AddEventHandler('onResourceStart', function(res) if res == 'bs_inventory' then SetTimeout(1000, registerLog) end end)
