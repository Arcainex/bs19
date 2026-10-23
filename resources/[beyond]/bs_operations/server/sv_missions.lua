-- Mission chains: ordered steps (goto, kill, collect, deliver, defend, escort) run by one player and shared with their squad

local M = Ops.Missions
Missions = { chains = {}, overrides = {}, runs = {}, logs = {}, restored = {} }
local MS = Missions
local Runs = MS.runs

local TYPES = { ['goto'] = true, kill = true, collect = true, deliver = true, defend = true, escort = true }
local TIERS = { story = true, hard = true, challenging = true, heroic = true }
local FACTIONS = { military = true, rebels = true, civilians = true, bikers = true }
Missions.TYPES, Missions.TIERS, Missions.FACTIONS = TYPES, TIERS, FACTIONS

local function copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

function Missions.Rebuild()
    local out = {}
    for id, c in pairs(Ops.Chains) do
        local d = copy(c); d.id = id; d.builtin = true
        out[id] = d
    end
    for id, o in pairs(MS.overrides) do
        local d = copy(o); d.id = id; d.builtin = Ops.Chains[id] ~= nil; d.edited = true
        out[id] = d
    end
    MS.chains = out
end

local function chainTitle(src, c)
    if type(c.title) == 'string' and c.title ~= '' then return c.title end
    return Lp(src, ('ch.%s.t'):format(c.id))
end
local function chainDesc(src, c)
    if type(c.desc) == 'string' and c.desc ~= '' then return c.desc end
    return Lp(src, ('ch.%s.d'):format(c.id))
end

local function itemLabel(item, src)
    local ok, l = pcall(function() return exports.bs_inventory:ItemLabel(item, src) end)
    return ok and l or item
end

-- Owner plus online squad members.
local function party(src)
    local out = { src }
    if OpsU.started('bs_factions') then
        local ok, list = pcall(function() return exports.bs_factions:GetSquadMembers(src) end)
        if ok and type(list) == 'table' then
            for _, m in ipairs(list) do
                if m.src and m.src ~= src and GetPlayerName(m.src) then out[#out + 1] = m.src end
            end
        end
    end
    return out
end

local function scale(run) return 1.0 + M.squadScale * math.max(0, (run.size or 1) - 1) end

local function stepText(p, run)
    local c = MS.chains[run.chainId]
    local s = c and c.steps[run.step]
    if not s then return '' end
    if type(s.text) == 'string' and s.text ~= '' then return s.text end
    local vars = { place = s.place or '', n = run.target or s.count or 0, item = s.item and itemLabel(s.item, p) or '' }
    return Lp(p, 'step.' .. s.type, vars)
end

local function view(p, run)
    local c = MS.chains[run.chainId]
    local s = c and c.steps[run.step]
    if not s then return nil end
    local pt = s.type == 'escort' and run.sd.picked and s.to or s
    return {
        title = chainTitle(p, c), tier = c.tier, step = run.step, steps = #c.steps,
        text = stepText(p, run), progress = math.floor(run.progress or 0), target = run.target or 0, kind = s.type,
        x = pt.x, y = pt.y, z = pt.z, r = s.radius or 25.0,
        left = run.sd.endsAt and math.max(0, run.sd.endsAt - OpsU.now()) or nil,
        escort = run.sd.net,
    }
end

local function track(run)
    for _, p in ipairs(run.party or { run.src }) do
        TriggerClientEvent('bs:ops:track', p, view(p, run))
    end
end

local function save(run)
    exports.oxmysql:execute('INSERT INTO `bs_ops_runs` (`character_id`,`chain_id`,`step`,`progress`) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE `chain_id` = VALUES(`chain_id`), `step` = VALUES(`step`), `progress` = VALUES(`progress`)',
        { run.charId, run.chainId, run.step, math.floor(run.progress or 0) })
end

local function tagOf(run) return 'ops_m_' .. run.charId end

local function cleanupStep(run, keep)
    OpsU.clear(tagOf(run), keep)
    if run.sd and run.sd.ped and DoesEntityExist(run.sd.ped) then DeleteEntity(run.sd.ped) end
end

local function endRun(run, why)
    cleanupStep(run, why == 'done')
    Runs[run.src] = nil
    exports.oxmysql:execute('DELETE FROM `bs_ops_runs` WHERE `character_id` = ?', { run.charId })
    for _, p in ipairs(run.party or { run.src }) do TriggerClientEvent('bs:ops:track', p, nil) end
end

local function beginStep(run)
    local c = MS.chains[run.chainId]
    local s = c.steps[run.step]
    run.sd, run.progress = {}, run.progress or 0
    run.target = 1
    if s.type == 'kill' then
        local n = (s.spawn or 0) > 0 and math.ceil(s.spawn * scale(run)) or 0
        run.sd.spawnN = n + (s.brutes or 0) + (s.elite and 1 or 0)
        run.target = run.sd.spawnN > 0 and run.sd.spawnN or math.max(1, math.ceil((s.count or 1) * scale(run)))
    elseif s.type == 'collect' or s.type == 'deliver' then
        run.target = s.count or 1
        if s.type == 'deliver' and s.give and not run.sd.given and not run.resumed then
            pcall(function() exports.bs_inventory:GiveItem(run.src, s.item, s.count or 1) end)
            run.sd.given = true
        end
    elseif s.type == 'defend' then
        run.target = s.seconds or 120
    end
    run.resumed = nil
    save(run)
    track(run)
end

local function fail(run, key)
    for _, p in ipairs(run.party or { run.src }) do OpsU.notify(p, 'error', key or 'ops.m_failed', { title = chainTitle(p, MS.chains[run.chainId] or { id = run.chainId }) }) end
    MS.logs[run.charId] = MS.logs[run.charId] or {}
    MS.logs[run.charId]['fail:' .. run.chainId] = OpsU.now()
    endRun(run, 'fail')
end

local function complete(run)
    local c = MS.chains[run.chainId]
    local r = c.reward or {}
    local owner = OpsU.pos(run.src)
    local n = #run.party
    local mult = 1.0 + M.squadScale * 0.5 * math.max(0, n - 1)
    for _, p in ipairs(run.party) do
        local pos = OpsU.pos(p)
        if p == run.src or (pos and owner and #(pos - owner) <= M.squadRange) then
            local share = { xp = math.floor((r.xp or 0) * mult), money = math.floor((r.money or 0) * mult), rep = r.rep }
            if p == run.src then share.items = r.items end
            OpsU.pay(p, share, 'chain_' .. run.chainId)
            OpsU.notify(p, 'success', 'ops.m_done', { title = chainTitle(p, c), xp = share.xp, money = share.money })
        end
    end
    OpsU.factionXp(OpsU.faction(run.src), r.factionXp, 'chain_' .. run.chainId)
    exports.oxmysql:insert('INSERT INTO `bs_ops_chain_log` (`character_id`,`chain_id`,`tier`) VALUES (?,?,?)', { run.charId, run.chainId, c.tier or 'story' })
    local L = MS.logs[run.charId]
    if L and L.loaded then
        L[run.chainId] = OpsU.now()
        L['n:' .. run.chainId] = (L['n:' .. run.chainId] or 0) + 1
        if c.tier == 'heroic' then table.insert(L.heroic, OpsU.now()) end
    end
    endRun(run, 'done')
end

local function nextStep(run)
    local c = MS.chains[run.chainId]
    cleanupStep(run, true)
    if run.step >= #c.steps then return complete(run) end
    run.step, run.progress = run.step + 1, 0
    for _, p in ipairs(run.party) do OpsU.notify(p, 'info', 'ops.m_step', { n = run.step, total = #c.steps }) end
    beginStep(run)
end

local function anyNear(run, x, y, r)
    for _, p in ipairs(run.party) do
        local pos = OpsU.pos(p)
        if pos and OpsU.dist2(pos, x, y) <= r and OpsU.alive(p) then return p end
    end
end

local function thinkStep(run)
    local c = MS.chains[run.chainId]
    if not c then return endRun(run, 'gone') end
    local s = c.steps[run.step]
    if not s then return endRun(run, 'gone') end
    local sd, now = run.sd, OpsU.now()
    if OpsU.dead(run.src) then return fail(run, 'ops.m_died') end

    if s.type == 'goto' then
        if anyNear(run, s.x, s.y, s.radius or 25.0) then return nextStep(run) end

    elseif s.type == 'kill' then
        if sd.spawnN and sd.spawnN > 0 then
            if not sd.spawned then
                if anyNear(run, s.x, s.y, 200.0) then
                    sd.spawned = true
                    local tag, r = tagOf(run), math.max(8.0, (s.radius or 60.0) * 0.5)
                    local walkers = sd.spawnN - (s.brutes or 0) - (s.elite and 1 or 0)
                    for _ = 1, walkers do local x, y = OpsU.ring(s.x, s.y, 3.0, r); OpsU.spawn(x, y, false, tag) end
                    for _ = 1, (s.brutes or 0) do local x, y = OpsU.ring(s.x, s.y, 3.0, r); OpsU.spawn(x, y, true, tag) end
                    if s.elite then OpsU.spawn(s.x, s.y, true, tag, s.elite.hpScale or 5.0) end
                    Wait(500)
                end
            else
                local alive = OpsU.alive_count(tagOf(run))
                local p = sd.spawnN - alive
                if p ~= run.progress then run.progress = p; track(run) end
                if alive <= 0 then return nextStep(run) end
                if math.random() < 0.2 then OpsU.drive(tagOf(run), s.x, s.y, s.z) end
            end
        elseif run.progress >= run.target then
            return nextStep(run)
        end

    elseif s.type == 'collect' then
        local best = 0
        for _, p in ipairs(run.party) do
            local ok, n = pcall(function() return exports.bs_inventory:CountItem(p, s.item) end)
            if ok and (n or 0) > best then best = n end
        end
        best = math.min(best, run.target)
        if best ~= run.progress then run.progress = best; track(run) end
        if best >= run.target then return nextStep(run) end

    elseif s.type == 'deliver' then
        local p = anyNear(run, s.x, s.y, s.radius or 10.0)
        if p then
            for _, q in ipairs(run.party) do
                local qp = OpsU.pos(q)
                local ok, n = pcall(function() return exports.bs_inventory:CountItem(q, s.item) end)
                if qp and OpsU.dist2(qp, s.x, s.y) <= (s.radius or 10.0) and ok and (n or 0) >= run.target then
                    if exports.bs_inventory:RemoveItem(q, s.item, run.target) then return nextStep(run) end
                end
            end
            if not sd.warned then sd.warned = true; OpsU.notify(p, 'info', 'ops.m_need', { n = run.target, item = itemLabel(s.item, p) }) end
        end

    elseif s.type == 'defend' then
        local r = s.radius or 30.0
        local inside = anyNear(run, s.x, s.y, r)
        if not sd.endsAt then
            if inside then
                sd.endsAt = now + (s.seconds or 120)
                sd.waves, sd.nextWave, sd.out = 0, now, 0
                track(run)
            end
        else
            if inside then sd.out = 0 else sd.out = (sd.out or 0) + Ops.Settings.tickMs / 1000 end
            if sd.out > M.leaveSeconds then return fail(run, 'ops.m_left') end
            run.progress = math.min(run.target, run.target - (sd.endsAt - now))
            local waves = s.waves or 3
            if sd.waves < waves and now >= sd.nextWave then
                sd.waves = sd.waves + 1
                sd.nextWave = now + math.floor((s.seconds or 120) / waves)
                local n = math.ceil((s.size or 6) * scale(run))
                for i = 1, n do
                    local x, y = OpsU.ring(s.x, s.y, 60.0, 95.0)
                    OpsU.spawn(x, y, i == 1 and sd.waves == waves, tagOf(run))
                end
                OpsU.drive(tagOf(run), s.x, s.y, s.z)
                OpsU.noise(s.x, s.y, s.z, 120.0)
            end
            track(run)
            if now >= sd.endsAt then return nextStep(run) end
        end

    elseif s.type == 'escort' then
        local to = s.to or {}
        if not sd.ped then
            if anyNear(run, s.x, s.y, 120.0) then
                local model = joaat(s.model or 's_m_m_doctor_01')
                local ped = CreatePed(4, model, s.x + 0.0, s.y + 0.0, (s.z or 0.0) + 0.0, 0.0, true, true)
                local t = GetGameTimer()
                while not DoesEntityExist(ped) and GetGameTimer() - t < 3000 do Wait(50) end
                if DoesEntityExist(ped) then
                    sd.ped, sd.net, sd.picked = ped, NetworkGetNetworkIdFromEntity(ped), true
                    Entity(ped).state:set('bsOpsEscort', run.src, true)
                    SetPedArmour(ped, 50)
                    track(run)
                end
            end
        else
            if not DoesEntityExist(sd.ped) or GetEntityHealth(sd.ped) <= 0 then return fail(run, 'ops.m_escort') end
            local pp = GetEntityCoords(sd.ped)
            if OpsU.dist2(pp, to.x or 0, to.y or 0) <= (s.radius or 20.0) then return nextStep(run) end
            local own = OpsU.pos(run.src)
            if own and #(own - pp) > 250.0 then
                sd.far = (sd.far or 0) + Ops.Settings.tickMs / 1000
                if sd.far > 60 then return fail(run, 'ops.m_escort') end
            else
                sd.far = 0
            end
            sd.ambush = (sd.ambush or 0) + Ops.Settings.tickMs / 1000
            if sd.ambush > 45 then
                sd.ambush = 0
                for _ = 1, math.ceil(3 * scale(run)) do
                    local x, y = OpsU.ring(pp.x, pp.y, 45.0, 70.0)
                    OpsU.spawn(x, y, false, tagOf(run))
                end
                OpsU.drive(tagOf(run), pp.x, pp.y, pp.z)
            end
        end
    end
end

-- Kills for kill steps without their own spawn.
AddEventHandler('bs:hook:player:action', function(player, actionId)
    if type(actionId) ~= 'string' or not actionId:find('^zombie_kill') or not player or not player.source then return end
    local src = player.source
    for _, run in pairs(Runs) do
        local c = MS.chains[run.chainId]
        local s = c and c.steps[run.step]
        if s and s.type == 'kill' and (run.sd.spawnN or 0) == 0 then
            for _, p in ipairs(run.party) do
                if p == src then
                    local pos = OpsU.pos(src)
                    if not s.x or (pos and OpsU.dist2(pos, s.x, s.y) <= (s.radius or 80.0)) then
                        run.progress = math.min(run.target, (run.progress or 0) + 1)
                        track(run)
                    end
                    break
                end
            end
        end
    end
end)

-- History for gating, loaded once per character.
local function logsOf(charId)
    local L = MS.logs[charId]
    if L and L.loaded then return L end
    L = L or {}
    L.heroic = {}
    local rows = exports.oxmysql:query_async('SELECT `chain_id`, `tier`, UNIX_TIMESTAMP(`completed_at`) AS t FROM `bs_ops_chain_log` WHERE `character_id` = ?', { charId }) or {}
    for _, r in ipairs(rows) do
        local t = tonumber(r.t) or 0
        if t > (L[r.chain_id] or 0) then L[r.chain_id] = t end
        L['n:' .. r.chain_id] = (L['n:' .. r.chain_id] or 0) + 1
        if r.tier == 'heroic' then table.insert(L.heroic, t) end
    end
    L.loaded = true
    MS.logs[charId] = L
    return L
end

local function heroicToday(L)
    local n, day = 0, os.date('%Y%m%d')
    for _, t in ipairs(L.heroic or {}) do if os.date('%Y%m%d', t) == day then n = n + 1 end end
    return n
end

-- nil when the player may take it, else a locale key and vars.
local function lockReason(src, c, fid)
    if c.disabled then return 'ops.m_l_off' end
    if c.faction and c.faction ~= fid then return 'ops.m_l_faction' end
    local p = OpsU.player(src)
    if (c.minLevel or 0) > 0 and (not p or (p.level or 1) < c.minLevel) then return 'ops.m_l_level', { n = c.minLevel } end
    if (c.minRep or 0) > 0 then
        local ok, s = pcall(function() return exports.bs_factions:GetFactionSummary(src) end)
        if not ok or not s or (s.reputation or 0) < c.minRep then return 'ops.m_l_rep', { n = c.minRep } end
    end
    if not p or not p.charId then return 'ops.m_l_off' end
    local L = logsOf(p.charId)
    if c.requires and c.requires ~= '' and not L[c.requires] then
        local req = MS.chains[c.requires]
        return 'ops.m_l_req', { title = req and chainTitle(src, req) or c.requires }
    end
    local last = L[c.id]
    if last and (c.cooldownHours or 0) > 0 and OpsU.now() - last < c.cooldownHours * 3600 then
        return 'ops.m_l_cd', { h = math.ceil((c.cooldownHours * 3600 - (OpsU.now() - last)) / 3600) }
    end
    local f = L['fail:' .. c.id]
    if f and OpsU.now() - f < M.failCooldown * 60 then return 'ops.m_l_cd', { h = 1 } end
    if c.tier == 'heroic' and heroicToday(L) >= M.dailyHeroic then return 'ops.m_l_daily' end
    return nil
end

-- Quest trader check through bs_traders
local function npcOk(src, npcId)
    if not OpsU.started('bs_traders') then return false end
    local ok, info = pcall(function() return exports.bs_traders:NpcInfo(npcId) end)
    if not ok or type(info) ~= 'table' or not info.quest then return false end
    local pos = OpsU.pos(src)
    if not pos or #(pos - vector3(info.x, info.y, info.z)) > 6.0 then return false end
    local fid = OpsU.faction(src)
    return fid ~= nil and info.faction == fid
end

BSB.RegisterCallback('ops:m:board', function(src, npcId)
    if not M.enabled then return { ok = false, msg = Lp(src, 'ops.off') } end
    if not npcOk(src, npcId) then return { ok = false, msg = Lp(src, 'ops.m_wrong_npc') } end
    local fid = OpsU.faction(src)
    local cid = OpsU.charId(src)
    if not cid then return { ok = false } end
    local L = logsOf(cid)
    local list = {}
    for id, c in pairs(MS.chains) do
        if (not c.faction or c.faction == fid) and not c.disabled then
            local key, vars = lockReason(src, c, fid)
            local steps = {}
            local rw = c.reward or {}
            local reward = { xp = rw.xp, money = rw.money, rep = rw.rep, items = {} }
            for _, it in ipairs(rw.items or {}) do reward.items[#reward.items + 1] = { item = itemLabel(it.item, src), amount = it.amount } end
            for i, s in ipairs(c.steps) do steps[i] = Lp(src, 'step.' .. s.type, { place = s.place or '', n = s.count or s.seconds or 1, item = s.item and itemLabel(s.item, src) or '' }) end
            list[#list + 1] = { id = id, title = chainTitle(src, c), desc = chainDesc(src, c), tier = c.tier or 'story',
                tierLabel = Lp(src, 'ops.tier_' .. (c.tier or 'story')), steps = steps, reward = reward,
                locked = key and Lp(src, key, vars) or nil, done = L['n:' .. id] or 0,
                active = Runs[src] and Runs[src].chainId == id or false }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return { ok = true, list = list, npc = npcId, busy = Runs[src] and Runs[src].chainId or nil }
end)

local function startRun(src, chainId, step, progress, resumed)
    local cid = OpsU.charId(src)
    local p = party(src)
    local run = { src = src, charId = cid, chainId = chainId, step = step or 1, progress = progress or 0, party = p, size = #p, resumed = resumed }
    Runs[src] = run
    beginStep(run)
    return run
end

BSB.RegisterCallback('ops:m:accept', function(src, npcId, chainId)
    if not M.enabled then return { ok = false, msg = Lp(src, 'ops.off') } end
    if not npcOk(src, npcId) then return { ok = false, msg = Lp(src, 'ops.m_wrong_npc') } end
    local c = MS.chains[tostring(chainId)]
    if not c then return { ok = false } end
    if Runs[src] then return { ok = false, msg = Lp(src, 'ops.m_busy') } end
    local key, vars = lockReason(src, c, OpsU.faction(src))
    if key then return { ok = false, msg = Lp(src, key, vars) } end
    startRun(src, c.id)
    return { ok = true }
end)

BSB.RegisterCallback('ops:m:abandon', function(src)
    local run = Runs[src]
    if not run then return { ok = false } end
    endRun(run, 'abandon')
    return { ok = true }
end)

-- Resume a saved run after a reconnect (spawns are made again).
local function restore(src, cid)
    MS.restored[cid] = true
    local row = exports.oxmysql:single_async('SELECT `chain_id`,`step`,`progress` FROM `bs_ops_runs` WHERE `character_id` = ?', { cid })
    if row and MS.chains[row.chain_id] and not Runs[src] then
        local c = MS.chains[row.chain_id]
        local step = math.max(1, math.min(#c.steps, tonumber(row.step) or 1))
        local s = c.steps[step]
        local prog = (s.type == 'collect' or s.type == 'deliver') and 0 or (tonumber(row.progress) or 0)
        if s.type == 'kill' and (s.spawn or 0) > 0 then prog = 0 end
        startRun(src, row.chain_id, step, prog, true)
    end
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
    Wait(3000)
    local rows = exports.oxmysql:query_async('SELECT `id`,`data` FROM `bs_ops_defs` WHERE `kind` = ?', { 'chain' }) or {}
    for _, r in ipairs(rows) do
        local ok, v = pcall(json.decode, r.data)
        if ok and type(v) == 'table' then MS.overrides[r.id] = v end
    end
    Missions.Rebuild()
    local tick = 0
    while true do
        Wait(Ops.Settings.tickMs)
        tick = tick + 1
        for src, run in pairs(Runs) do
            if not GetPlayerName(src) then
                cleanupStep(run, false); Runs[src] = nil
            else
                if tick % 5 == 0 then run.party = party(src) end
                local ok, err = pcall(thinkStep, run)
                if not ok then print('^1[bs_operations]^7 chain ' .. tostring(run.chainId) .. ': ' .. tostring(err)) end
            end
        end
        if tick % 5 == 0 and M.enabled then
            for _, p in ipairs(OpsU.players()) do
                local cid = OpsU.charId(p)
                if cid and not MS.restored[cid] and not Runs[p] then
                    local ok, err = pcall(restore, p, cid)
                    if not ok then print('^1[bs_operations]^7 restore: ' .. tostring(err)) end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local run = Runs[source]
    if run then
        MS.restored[run.charId] = nil
        cleanupStep(run, false)
        Runs[source] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, run in pairs(Runs) do cleanupStep(run, false) end
end)

-- Editor validation (sv_admin.lua). Returns clean chain or nil, error.
function Missions.Clean(id, c)
    if type(id) ~= 'string' or not id:match('^[a-z0-9_]+$') or #id > 40 then return nil, 'Bad id (a-z 0-9 _ , max 40).' end
    if type(c) ~= 'table' then return nil, 'Not an object.' end
    local o = {}
    if c.faction ~= nil and c.faction ~= '' then
        if not FACTIONS[c.faction] then return nil, 'faction must be military, rebels, civilians or bikers.' end
        o.faction = c.faction
    end
    o.tier = TIERS[c.tier] and c.tier or 'story'
    local function int(k, lo, hi)
        if c[k] == nil then return true end
        local v = tonumber(c[k]); if not v or v < lo or v > hi then return false end
        o[k] = math.floor(v); return true
    end
    if not int('minLevel', 0, 200) or not int('minRep', 0, 100000) or not int('cooldownHours', 0, 720) then return nil, 'minLevel / minRep / cooldownHours out of range.' end
    if c.requires ~= nil and c.requires ~= '' then
        if type(c.requires) ~= 'string' or not c.requires:match('^[a-z0-9_]+$') then return nil, 'requires must be a chain id.' end
        o.requires = c.requires
    end
    if type(c.title) == 'string' then o.title = c.title:sub(1, 64) end
    if type(c.desc) == 'string' then o.desc = c.desc:sub(1, 400) end
    o.disabled = c.disabled == true or nil
    if type(c.steps) ~= 'table' or #c.steps < 1 or #c.steps > 12 then return nil, 'steps: 1 to 12 entries.' end
    o.steps = {}
    for i, s in ipairs(c.steps) do
        if type(s) ~= 'table' or not TYPES[s.type] then return nil, ('step %d: type must be goto, kill, collect, deliver, defend or escort.'):format(i) end
        local t = { type = s.type }
        local function n(k, lo, hi, req)
            local v = tonumber(s[k])
            if v == nil then if req then error(('step %d: %s is required'):format(i, k), 0) end return end
            if v < lo or v > hi then error(('step %d: %s out of range'):format(i, k), 0) end
            t[k] = v
        end
        local ok, err = pcall(function()
            local needPos = s.type ~= 'collect' and not (s.type == 'kill' and s.x == nil)
            n('x', -5000, 9000, needPos); n('y', -5000, 9000, needPos); n('z', -200, 2000, needPos)
            n('radius', 2, 300)
            if s.type == 'kill' then n('count', 1, 200); n('spawn', 0, 60); n('brutes', 0, 10)
                if type(s.elite) == 'table' then t.elite = { hpScale = math.max(1, math.min(20, tonumber(s.elite.hpScale) or 5)) } end
                if (t.spawn or 0) > 0 and not t.x then error(('step %d: spawn needs x/y/z'):format(i), 0) end
                if not t.count and (t.spawn or 0) == 0 and not t.elite then t.count = 10 end
            elseif s.type == 'collect' or s.type == 'deliver' then
                if type(s.item) ~= 'string' or not s.item:match('^[%w_%-]+$') then error(('step %d: item is required'):format(i), 0) end
                local okI, def = pcall(function() return exports.bs_inventory:GetItem(s.item) end)
                if okI and def == nil then error(('step %d: unknown item %s'):format(i, s.item), 0) end
                t.item = s.item; n('count', 1, 100); t.count = t.count or 1
                if s.type == 'deliver' then t.give = s.give == true or nil end
            elseif s.type == 'defend' then n('seconds', 20, 1800, true); n('waves', 1, 12); n('size', 1, 30)
            elseif s.type == 'escort' then
                if type(s.to) ~= 'table' then error(('step %d: escort needs to = { x, y, z }'):format(i), 0) end
                local tx, ty, tz = tonumber(s.to.x), tonumber(s.to.y), tonumber(s.to.z)
                if not (tx and ty and tz) then error(('step %d: bad escort destination'):format(i), 0) end
                t.to = { x = tx, y = ty, z = tz }
                t.model = (type(s.model) == 'string' and s.model:match('^[%w_]+$')) and s.model or 's_m_m_doctor_01'
            end
        end)
        if not ok then return nil, tostring(err) end
        if type(s.place) == 'string' then t.place = s.place:sub(1, 48) end
        if type(s.text) == 'string' and s.text ~= '' then t.text = s.text:sub(1, 160) end
        o.steps[i] = t
    end
    local r = type(c.reward) == 'table' and c.reward or {}
    o.reward = {}
    for _, k in ipairs({ 'xp', 'money', 'rep', 'factionXp' }) do
        local v = tonumber(r[k]); if v then o.reward[k] = math.max(0, math.min(100000, math.floor(v))) end
    end
    if type(r.items) == 'table' then
        o.reward.items = {}
        for _, it in ipairs(r.items) do
            if type(it) == 'table' and type(it.item) == 'string' and it.item:match('^[%w_%-]+$') then
                table.insert(o.reward.items, { item = it.item, amount = math.max(1, math.min(100, math.floor(tonumber(it.amount) or 1))) })
            end
        end
    end
    return o
end

function Missions.AdminSave(id, clean)
    MS.overrides[id] = clean
    exports.oxmysql:execute('INSERT INTO `bs_ops_defs` (`kind`,`id`,`data`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
        { 'chain', id, json.encode(clean) })
    Missions.Rebuild()
end

function Missions.AdminReset(id)
    if not MS.overrides[id] then return false end
    MS.overrides[id] = nil
    exports.oxmysql:execute('DELETE FROM `bs_ops_defs` WHERE `kind` = ? AND `id` = ?', { 'chain', id })
    for src, run in pairs(Runs) do if run.chainId == id and not Ops.Chains[id] then endRun(run, 'gone') end end
    Missions.Rebuild()
    return true
end

function Missions.ActiveList()
    local out = {}
    for src, run in pairs(Runs) do
        out[#out + 1] = { src = src, name = GetPlayerName(src), chain = run.chainId, step = run.step, party = #run.party }
    end
    return out
end
