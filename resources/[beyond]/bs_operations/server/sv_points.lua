-- Control points: hostile spots held by a zombie garrison

local C = Ops.Points
Points = { defs = {}, order = {}, st = {}, overrides = {} }
local PT = Points

local function tagOf(id) return 'ops_cp_' .. id end

-- Config list + editor rows from bs_ops_defs.
function Points.Rebuild()
    local defs, order = {}, {}
    for _, d in ipairs(C.list) do
        local c = { id = d.id, label = d.label, x = d.x, y = d.y, z = d.z, radius = d.radius or 35.0,
            guards = d.guards, brutes = d.brutes, builtin = true }
        defs[d.id] = c; order[#order + 1] = d.id
    end
    for id, o in pairs(PT.overrides) do
        local c = defs[id]
        if not c then c = { id = id, builtin = false }; defs[id] = c; order[#order + 1] = id end
        for _, k in ipairs({ 'label', 'x', 'y', 'z', 'radius', 'guards', 'brutes', 'disabled' }) do
            if o[k] ~= nil then c[k] = o[k] end
        end
        c.edited = true
    end
    PT.defs, PT.order = defs, order
    for id in pairs(PT.st) do if not defs[id] then OpsU.clear(tagOf(id), false); PT.st[id] = nil end end
    for _, id in ipairs(order) do
        PT.st[id] = PT.st[id] or { owner = nil, capturedAt = 0, phase = 'idle', progress = 0, by = nil, spawned = false, lastNear = 0, cacheAt = 0 }
    end
end

local function stOf(id) return PT.st[id] end

function Points.View()
    local out = {}
    for _, id in ipairs(PT.order) do
        local d, s = PT.defs[id], PT.st[id]
        if d and not d.disabled then
            out[#out + 1] = { id = id, label = d.label, x = d.x, y = d.y, z = d.z, r = d.radius,
                owner = s.owner, ownerLabel = s.owner and OpsU.factionLabel(s.owner) or nil,
                phase = s.phase, progress = math.floor(s.progress), need = C.captureSeconds, by = s.by }
        end
    end
    return { enabled = C.enabled, list = out }
end

local function push() TriggerClientEvent('bs:ops:points', -1, Points.View()) end
Points.Push = push

local function saveOwner(id)
    local s = PT.st[id]
    exports.oxmysql:execute('INSERT INTO `bs_ops_points` (`id`,`faction`,`captured_at`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `faction` = VALUES(`faction`), `captured_at` = VALUES(`captured_at`)',
        { id, s.owner, s.capturedAt })
end

local function cacheId(id) return 'ops:cp:' .. id end

local function refillCache(id)
    local s = PT.st[id]
    local cid = cacheId(id)
    exports.bs_inventory:RegisterContainer(cid, { width = 6, height = 4, maxWeight = 120.0, label = PT.defs[id].label })
    local okh, has = pcall(function() return exports.bs_inventory:ContainerHasItems(cid) end)
    if okh and has then s.cacheAt = OpsU.now(); return end
    for _, row in ipairs(OpsU.rollLoot(C.cache)) do pcall(function() exports.bs_inventory:ContainerGive(cid, row.item, row.amount) end) end
    s.cacheAt = OpsU.now()
end

local function setOwner(id, fid, capturers)
    local s, d = PT.st[id], PT.defs[id]
    local old = s.owner
    s.owner, s.capturedAt, s.phase, s.progress, s.by = fid, OpsU.now(), 'idle', 0, nil
    s.spawned = false
    OpsU.clear(tagOf(id), true)
    saveOwner(id)
    if fid then
        pcall(function() exports.bs_inventory:ContainerTakeAll(cacheId(id)) end)
        refillCache(id)
        OpsU.factionXp(fid, C.rewardFactionXp, 'control_point')
        for _, p in ipairs(capturers or {}) do
            OpsU.pay(p, { xp = C.rewardXp, rep = C.rewardRep }, 'control_point')
        end
        OpsU.broadcast('ops.cp_taken', { faction = OpsU.factionLabel(fid), place = d.label }, 'warning')
        if old and old ~= fid then
            for _, m in ipairs(OpsU.factionMembers(old)) do OpsU.notify(m, 'error', 'ops.cp_lost', { place = d.label }) end
        end
    end
    push()
end

BSB.RegisterCallback('ops:cp:cache', function(src, id)
    local d, s = PT.defs[id], PT.st[id]
    if not d or not s or not s.owner then return { ok = false, msg = Lp(src, 'ops.gone') } end
    if OpsU.faction(src) ~= s.owner then return { ok = false, msg = Lp(src, 'ops.p_not_yours') } end
    local pos = OpsU.pos(src)
    if not pos or OpsU.dist2(pos, d.x, d.y) > d.radius then return { ok = false, msg = Lp(src, 'ops.far') } end
    if s.phase ~= 'idle' then return { ok = false, msg = Lp(src, 'ops.cp_fight') } end
    exports.bs_inventory:RegisterContainer(cacheId(id), { width = 6, height = 4, maxWeight = 120.0, label = d.label })
    exports.bs_inventory:OpenContainerFor(src, cacheId(id))
    return { ok = true }
end)

BSB.RegisterCallback('ops:cp:view', function() return Points.View() end)

local function spawnGarrison(id, n, brutes)
    local d = PT.defs[id]
    local r = math.max(10.0, d.radius * 0.8)
    for i = 1, n do
        local x, y = OpsU.ring(d.x, d.y, 4.0, r)
        OpsU.spawn(x, y, i <= brutes, tagOf(id))
    end
end

local function thinkPoint(id, near)
    local d, s = PT.defs[id], PT.st[id]
    local now = OpsU.now()
    local tag = tagOf(id)

    if s.owner and C.revertHours > 0 and now - s.capturedAt > C.revertHours * 3600 and s.phase == 'idle' then
        OpsU.broadcast('ops.cp_revert', { place = d.label }, 'info', function(p) return OpsU.faction(p) == s.owner end)
        setOwner(id, nil)
        return true
    end
    if s.owner and s.phase == 'idle' and now - s.cacheAt > C.cacheMinutes * 60 then refillCache(id) end

    -- who is around
    local inside, nearAny, rivals = {}, false, false
    for _, p in ipairs(near) do
        local pos = OpsU.pos(p)
        local dd = pos and OpsU.dist2(pos, d.x, d.y)
        if dd and dd <= C.activateRadius then
            nearAny = true
            local f = OpsU.faction(p)
            if f and f ~= s.owner then rivals = true end
            if dd <= d.radius and OpsU.alive(p) and f then
                inside[f] = inside[f] or {}
                table.insert(inside[f], p)
            end
        end
    end
    if nearAny then s.lastNear = now end

    local changed = false
    if s.phase == 'idle' and rivals then
        -- hostile point wakes its garrison; owned point gets defenders and calls the owners
        s.phase, s.progress, s.by = 'assault', 0, nil
        if s.owner then
            spawnGarrison(id, C.defenders, 1)
            for _, m in ipairs(OpsU.factionMembers(s.owner)) do
                OpsU.notify(m, 'warning', 'ops.cp_attack', { place = d.label })
                TriggerClientEvent('bs:ops:alert', m, { x = d.x, y = d.y, label = d.label })
            end
        else
            spawnGarrison(id, d.guards or C.guards, d.brutes or C.brutes)
        end
        changed = true
    end

    if s.phase ~= 'idle' then
        if not nearAny and now - s.lastNear > C.sleepSeconds then
            OpsU.clear(tag, false)
            s.phase, s.progress, s.by = 'idle', 0, nil
            push()
            return true
        end
        local alive = OpsU.alive_count(tag)
        if alive > 0 then
            if s.phase ~= 'assault' then s.phase = 'assault'; changed = true end
            if math.random() < 0.3 then OpsU.drive(tag, d.x, d.y, d.z) end
        else
            local list = {}
            for f in pairs(inside) do list[#list + 1] = f end
            local ownerHere = s.owner and inside[s.owner] ~= nil
            if s.phase == 'assault' then s.phase = 'capture'; changed = true end
            if #list == 1 and list[1] ~= s.owner then
                local f = list[1]
                if s.by ~= f then s.by, s.progress = f, 0 end
                s.progress = s.progress + Ops.Settings.tickMs / 1000
                changed = true
                if s.progress >= C.captureSeconds then setOwner(id, f, inside[f]); return true end
            elseif #list == 0 and not rivals then
                -- rivals left: owned point settles back
                if s.owner then s.phase, s.progress, s.by = 'idle', 0, nil; changed = true end
            elseif ownerHere and #list == 1 then
                s.phase, s.progress, s.by = 'idle', 0, nil; changed = true
            end
        end
    end
    return changed
end

local function tick()
    if not C.enabled then return end
    local players = OpsU.players()
    local any = false
    for _, id in ipairs(PT.order) do
        local d = PT.defs[id]
        if d and not d.disabled then
            local ok, ch = pcall(thinkPoint, id, players)
            if not ok then print('^1[bs_operations]^7 point ' .. id .. ': ' .. tostring(ch)) elseif ch then any = true end
        end
    end
    if any then push() end
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
    Wait(2500)
    local rows = exports.oxmysql:query_async('SELECT `id`,`data` FROM `bs_ops_defs` WHERE `kind` = ?', { 'point' }) or {}
    for _, r in ipairs(rows) do
        local ok, v = pcall(json.decode, r.data)
        if ok and type(v) == 'table' then PT.overrides[r.id] = v end
    end
    Points.Rebuild()
    local owners = exports.oxmysql:query_async('SELECT `id`,`faction`,`captured_at` FROM `bs_ops_points`') or {}
    for _, r in ipairs(owners) do
        local s = PT.st[r.id]
        if s and r.faction and r.faction ~= '' then
            s.owner, s.capturedAt = r.faction, tonumber(r.captured_at) or OpsU.now()
            s.cacheAt = 0
        end
    end
    push()
    while true do
        Wait(Ops.Settings.tickMs)
        tick()
    end
end)

-- Editor (sv_admin.lua)
local function saveDef(id)
    local o = PT.overrides[id]
    if o then
        exports.oxmysql:execute('INSERT INTO `bs_ops_defs` (`kind`,`id`,`data`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
            { 'point', id, json.encode(o) })
    else
        exports.oxmysql:execute('DELETE FROM `bs_ops_defs` WHERE `kind` = ? AND `id` = ?', { 'point', id })
    end
end

function Points.AdminList()
    local out = {}
    for _, id in ipairs(PT.order) do
        local d, s = PT.defs[id], PT.st[id]
        out[#out + 1] = { id = id, label = d.label, x = d.x, y = d.y, z = d.z, radius = d.radius, guards = d.guards or C.guards,
            brutes = d.brutes or C.brutes, disabled = d.disabled == true, builtin = d.builtin, edited = d.edited == true,
            owner = s.owner, phase = s.phase }
    end
    return out
end

function Points.AdminSave(id, p, pos)
    id = tostring(id or '')
    if not id:match('^[a-z0-9_]+$') or #id > 32 then return false, 'Bad id (a-z 0-9 _).' end
    local o = PT.overrides[id] or {}
    if type(p.label) == 'string' and #p.label > 0 then o.label = p.label:sub(1, 48) end
    local function num(k, lo, hi) local v = tonumber(p[k]); if v and v >= lo and v <= hi then o[k] = v end end
    num('radius', 10, 200); num('guards', 0, 40); num('brutes', 0, 10)
    if p.disabled ~= nil then o.disabled = p.disabled == true end
    if pos then o.x, o.y, o.z = pos.x, pos.y, pos.z end
    if not PT.defs[id] and not (o.x and o.label) then return false, 'New points need a label and a position.' end
    if not PT.defs[id] then o.radius = o.radius or 35.0 end
    PT.overrides[id] = o
    saveDef(id); Points.Rebuild(); push()
    return true
end

function Points.AdminReset(id)
    if not PT.overrides[id] then return false end
    PT.overrides[id] = nil
    saveDef(id); Points.Rebuild(); push()
    return true
end

function Points.AdminOwner(id, fid)
    if not PT.st[id] then return false end
    setOwner(id, fid ~= '' and fid or nil)
    return true
end
