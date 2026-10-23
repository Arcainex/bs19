-- Power station: a faction pays parts to start it

local P = Ops.Power
local TAG = 'ops_power'

Power = {
    phase = 'idle', starter = nil, endsAt = 0, cooldownUntil = 0,
    panels = {}, controller = nil, flip = 0, flipBy = nil, contested = false,
    hold = {}, contrib = {}, nextWave = 0, crate = nil, buff = nil, districts = nil,
}
local S = Power
local repairing = {}   -- [src] = { idx, t }

local function center() return vector3(P.x, P.y, P.z) end

local function panelPos(i)
    local o = P.panels[i]
    return o and vector3(P.x + o.x, P.y + o.y, P.z + o.z) or nil
end

-- What clients see. Plain data only.
function Power.View()
    local panels = {}
    for i = 1, #P.panels do
        local p = panelPos(i)
        panels[i] = { x = p.x, y = p.y, z = p.z, done = S.panels[i] == true }
    end
    local hold = {}
    for f, sec in pairs(S.hold) do hold[#hold + 1] = { f = f, label = OpsU.factionLabel(f), s = math.floor(sec) } end
    table.sort(hold, function(a, b) return a.s > b.s end)
    return {
        enabled = P.enabled, phase = S.phase, label = P.label, x = P.x, y = P.y, z = P.z, r = P.captureRadius,
        left = math.max(0, S.endsAt - OpsU.now()), cooldown = math.max(0, S.cooldownUntil - OpsU.now()),
        starter = S.starter, starterLabel = OpsU.factionLabel(S.starter),
        controller = S.controller, controllerLabel = S.controller and OpsU.factionLabel(S.controller) or nil,
        contested = S.contested, flip = math.floor(S.flip), flipBy = S.flipBy, flipNeed = P.captureSeconds,
        panels = panels, hold = hold, crate = S.crate and { faction = S.crate.faction, left = math.max(0, S.crate.untilT - OpsU.now()) } or nil,
        buff = S.buff and { faction = S.buff.faction, label = OpsU.factionLabel(S.buff.faction), left = math.max(0, S.buff.untilT - OpsU.now()) } or nil,
        cost = P.cost,
    }
end

local function push() TriggerClientEvent('bs:ops:power', -1, Power.View()) end

-- XP bonus in percent for src from the live buff. 0 when none.
function Power.XpPct(src)
    local b = S.buff
    if not b or (b.untilT or 0) <= OpsU.now() then return 0 end
    if OpsU.faction(src) ~= b.faction then return 0 end
    return tonumber(P.rewards.buffXpPct) or 0
end
exports('XpBuffPct', function(src) return Power.XpPct(tonumber(src)) end)
Power.Push = push

local function saveState()
    OpsU.stateSave('power', { cooldownUntil = S.cooldownUntil, buff = S.buff, panels = P.panels })
end

-- Buff: statebag on every online member, refreshed by the tick.
local function applyBuff()
    local b = S.buff
    local live = b and b.untilT > OpsU.now()
    if b and not live then S.buff = nil; saveState() end
    for _, p in ipairs(OpsU.players()) do
        local want = live and OpsU.faction(p) == b.faction and { faction = b.faction, untilT = b.untilT, xp = P.rewards.buffXpPct, light = P.rewards.buffLight } or nil
        local fid = OpsU.faction(p) or false
        if Player(p).state.bsOpsFaction ~= fid then Player(p).state:set('bsOpsFaction', fid, true) end
        local cur = Player(p).state.bsOpsBuff
        if (want == nil) ~= (cur == nil) or (want and cur and cur.untilT ~= want.untilT) then
            Player(p).state:set('bsOpsBuff', want, true)
        end
    end
end

local function setDistricts(on)
    if not OpsU.started('bs_world') then return end
    if on then
        S.districts = {}
        for _, id in ipairs(P.districts or {}) do
            local ok, z = pcall(function() return exports.bs_world:PowerZone(id) end)
            if ok and z then
                S.districts[id] = z.on
                pcall(function() exports.bs_world:SetZonePower(id, true) end)
            end
        end
    elseif S.districts then
        for id, was in pairs(S.districts) do pcall(function() exports.bs_world:SetZonePower(id, was) end) end
        S.districts = nil
    end
end

local function reset(cooldown)
    OpsU.clear(TAG, true)
    setDistricts(false)
    S.phase, S.starter, S.endsAt, S.panels = 'idle', nil, 0, {}
    S.controller, S.flip, S.flipBy, S.contested, S.hold, S.contrib = nil, 0, nil, false, {}, {}
    repairing = {}
    if cooldown then S.cooldownUntil = OpsU.now() + P.cooldownMinutes * 60 end
    saveState()
    push()
end

function Power.Start(src, fid, free)
    if S.phase ~= 'idle' then return false, 'ops.p_busy' end
    S.phase, S.starter = 'repair', fid
    S.endsAt = OpsU.now() + P.repairMinutes * 60
    S.panels, S.hold, S.contrib = {}, {}, {}
    S.controller, S.flip, S.contested = fid, 0, false
    S.nextWave = OpsU.now() + 30
    OpsU.noise(P.x, P.y, P.z, 300.0)
    OpsU.broadcast('ops.p_started', { faction = OpsU.factionLabel(fid), place = P.label }, 'warning')
    push()
    return true
end

function Power.Stop(reason)
    if S.phase == 'idle' then return false end
    OpsU.broadcast('ops.p_stopped', { place = P.label }, 'info')
    reset(reason ~= 'admin')
    return true
end

BSB.RegisterCallback('ops:power:start', function(src)
    if not P.enabled then return { ok = false, msg = Lp(src, 'ops.off') } end
    local pos = OpsU.pos(src)
    if not pos or OpsU.dist2(pos, P.x, P.y) > P.captureRadius then return { ok = false, msg = Lp(src, 'ops.far') } end
    if S.phase ~= 'idle' then return { ok = false, msg = Lp(src, 'ops.p_busy') } end
    local left = S.cooldownUntil - OpsU.now()
    if left > 0 then return { ok = false, msg = Lp(src, 'ops.p_cooldown', { min = math.ceil(left / 60) }) } end
    if #GetPlayers() < P.minPlayers then return { ok = false, msg = Lp(src, 'ops.p_players', { n = P.minPlayers }) } end
    local fid = OpsU.faction(src)
    if not fid then return { ok = false, msg = Lp(src, 'ops.no_faction') } end
    local okRank, allowed = pcall(function() return exports.bs_factions:RankAllowed(src, Ops.Settings.startPerm) end)
    if not okRank or allowed ~= true then return { ok = false, msg = Lp(src, 'ops.p_rank') } end
    for _, c in ipairs(P.cost) do
        local okc, n = pcall(function() return exports.bs_inventory:CountItem(src, c.item) end)
        if not okc or (n or 0) < c.amount then return { ok = false, msg = Lp(src, 'ops.p_cost') } end
    end
    for i, c in ipairs(P.cost) do
        if not exports.bs_inventory:RemoveItem(src, c.item, c.amount) then
            -- give back what was taken
            for j = 1, i - 1 do pcall(function() exports.bs_inventory:GiveItem(src, P.cost[j].item, P.cost[j].amount) end) end
            return { ok = false, msg = Lp(src, 'ops.p_cost') }
        end
    end
    Power.Start(src, fid)
    return { ok = true }
end)

-- Panel repair: begin stores the time, finish checks it. The wire puzzle runs on the client.
BSB.RegisterCallback('ops:power:repairBegin', function(src, idx)
    idx = tonumber(idx)
    local p = idx and panelPos(idx)
    if S.phase ~= 'repair' or not p or S.panels[idx] then return { ok = false } end
    if OpsU.faction(src) ~= S.starter then return { ok = false, msg = Lp(src, 'ops.p_not_yours') } end
    local pos = OpsU.pos(src)
    if not pos or #(pos - p) > 4.0 then return { ok = false, msg = Lp(src, 'ops.far') } end
    repairing[src] = { idx = idx, t = GetGameTimer() }
    return { ok = true, seconds = P.repairSeconds }
end)

BSB.RegisterCallback('ops:power:repairDone', function(src, idx)
    idx = tonumber(idx)
    local r = repairing[src]
    repairing[src] = nil
    local p = idx and panelPos(idx)
    if S.phase ~= 'repair' or not r or r.idx ~= idx or not p or S.panels[idx] then return { ok = false } end
    if GetGameTimer() - r.t < P.repairSeconds * 1000 then return { ok = false } end
    local pos = OpsU.pos(src)
    if not pos or #(pos - p) > 5.0 then return { ok = false, msg = Lp(src, 'ops.far') } end
    S.panels[idx] = true
    local done = 0
    for i = 1, #P.panels do if S.panels[i] then done = done + 1 end end
    if done >= #P.panels then
        S.phase = 'hold'
        S.endsAt = OpsU.now() + P.holdMinutes * 60
        setDistricts(true)
        OpsU.broadcast('ops.p_online', { place = P.label, min = P.holdMinutes }, 'warning')
    else
        for _, m in ipairs(OpsU.factionMembers(S.starter)) do OpsU.notify(m, 'success', 'ops.p_panel', { n = done, total = #P.panels }) end
    end
    push()
    return { ok = true }
end)

-- Loot crate for the winner.
BSB.RegisterCallback('ops:power:crate', function(src)
    local c = S.crate
    if not c or c.untilT < OpsU.now() then return { ok = false, msg = Lp(src, 'ops.gone') } end
    if OpsU.faction(src) ~= c.faction then return { ok = false, msg = Lp(src, 'ops.p_not_yours') } end
    local pos = OpsU.pos(src)
    if not pos or OpsU.dist2(pos, P.x, P.y) > 6.0 then return { ok = false, msg = Lp(src, 'ops.far') } end
    exports.bs_inventory:OpenContainerFor(src, c.id)
    return { ok = true }
end)

local function finish()
    local best, bestS = nil, 0
    for f, sec in pairs(S.hold) do if sec > bestS then best, bestS = f, sec end end
    if not best or bestS < P.minHoldSeconds then
        OpsU.broadcast('ops.p_nowinner', { place = P.label }, 'info')
        reset(true)
        return
    end
    local R = P.rewards
    S.buff = { faction = best, untilT = OpsU.now() + R.buffHours * 3600 }
    OpsU.factionXp(best, R.factionXp, 'power_station')
    for _, p in ipairs(OpsU.players()) do
        local cid = OpsU.charId(p)
        if cid and OpsU.faction(p) == best and (S.contrib[cid] or 0) >= P.contribSeconds then
            OpsU.pay(p, { xp = R.playerXp, rep = R.playerRep, money = R.playerMoney }, 'power_station')
            OpsU.notify(p, 'success', 'ops.p_reward', { xp = R.playerXp, rep = R.playerRep })
        end
    end
    local id = ('ops:power:%d'):format(OpsU.now())
    exports.bs_inventory:RegisterContainer(id, { width = 6, height = 4, maxWeight = 150.0, label = P.label })
    for _, row in ipairs(OpsU.rollLoot(R.crate)) do pcall(function() exports.bs_inventory:ContainerGive(id, row.item, row.amount) end) end
    S.crate = { id = id, faction = best, untilT = OpsU.now() + R.crateMinutes * 60 }
    OpsU.broadcast('ops.p_won', { faction = OpsU.factionLabel(best), place = P.label, h = R.buffHours }, 'success')
    reset(true)
end

local function presence()
    local by, n = {}, 0
    for _, p in ipairs(OpsU.players()) do
        local pos = OpsU.pos(p)
        if pos and OpsU.dist2(pos, P.x, P.y) <= P.captureRadius and OpsU.alive(p) then
            local f = OpsU.faction(p)
            if f then
                by[f] = by[f] or {}
                table.insert(by[f], p)
                n = n + 1
            end
        end
    end
    return by, n
end

local lastTick = os.clock()
local function tick()
    local dt = Ops.Settings.tickMs / 1000
    if S.crate and S.crate.untilT < OpsU.now() then
        pcall(function() exports.bs_inventory:ContainerTakeAll(S.crate.id) end)
        S.crate = nil
        push()
    end
    applyBuff()
    if S.phase == 'idle' then return end
    if not P.enabled then return Power.Stop('admin') end

    local by, inside = presence()
    local now = OpsU.now()

    if S.phase == 'repair' and now >= S.endsAt then
        OpsU.broadcast('ops.p_failed', { place = P.label }, 'error')
        return reset(true)
    end

    if S.phase == 'hold' then
        local list = {}
        for f in pairs(by) do list[#list + 1] = f end
        S.contested = #list > 1
        if #list == 1 then
            local f = list[1]
            if f == S.controller then
                S.hold[f] = (S.hold[f] or 0) + dt
                S.flip, S.flipBy = 0, nil
            else
                if S.flipBy ~= f then S.flip, S.flipBy = 0, f end
                S.flip = S.flip + dt
                if S.flip >= P.captureSeconds then
                    S.controller, S.flip, S.flipBy = f, 0, nil
                    OpsU.broadcast('ops.p_taken', { faction = OpsU.factionLabel(f), place = P.label }, 'warning')
                end
            end
        end
        for f, members in pairs(by) do
            for _, p in ipairs(members) do
                local cid = OpsU.charId(p)
                if cid then S.contrib[cid] = (S.contrib[cid] or 0) + dt end
            end
        end
        if now >= S.endsAt then return finish() end
    end

    -- waves draw on the noise of the station
    if now >= S.nextWave then
        S.nextWave = now + P.waves.intervalSeconds
        local W = P.waves
        local want = math.min(W.maxAlive - OpsU.alive_count(TAG), W.base + W.perPlayer * inside)
        for _ = 1, math.max(0, want) do
            local x, y = OpsU.ring(P.x, P.y, W.ringMin, W.ringMax)
            OpsU.spawn(x, y, math.random() < W.bruteChance, TAG)
        end
        OpsU.drive(TAG, P.x, P.y, P.z)
    end
    push()
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
    Wait(2000)
    local st = OpsU.stateLoad('power')
    if type(st) == 'table' then
        S.cooldownUntil = tonumber(st.cooldownUntil) or 0
        if type(st.buff) == 'table' and (tonumber(st.buff.untilT) or 0) > OpsU.now() then S.buff = st.buff end
        if type(st.panels) == 'table' and #st.panels > 0 then P.panels = st.panels end
    end
    push()
    while true do
        Wait(Ops.Settings.tickMs)
        local ok, err = pcall(tick)
        if not ok then print('^1[bs_operations]^7 power tick: ' .. tostring(err)) end
    end
end)

AddEventHandler('playerDropped', function() repairing[source] = nil end)

-- Admin helpers used by sv_admin.lua
function Power.AdminStart(src, fid)
    if not fid then return false, 'faction?' end
    return Power.Start(src, fid, true)
end

function Power.AdminPanelHere(src, idx)
    local pos = OpsU.pos(src)
    if not pos then return false end
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 or idx > #P.panels + 1 or idx > 8 then return false end
    P.panels[idx] = { x = pos.x - P.x, y = pos.y - P.y, z = pos.z - 1.0 - P.z }
    saveState(); push()
    return true
end

function Power.AdminPanelRemove(idx)
    idx = math.floor(tonumber(idx) or 0)
    if S.phase ~= 'idle' or not P.panels[idx] or #P.panels <= 1 then return false end
    table.remove(P.panels, idx)
    saveState(); push()
    return true
end

function Power.AdminClearCooldown() S.cooldownUntil = 0; saveState(); push(); return true end
function Power.AdminClearBuff() S.buff = nil; saveState(); applyBuff(); push(); return true end

BSB.RegisterCallback('ops:power:view', function() return Power.View() end)
