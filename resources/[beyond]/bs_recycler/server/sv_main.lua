-- bs_recycler server. Machines live at fixed spots, run on fuel, take one item every few seconds and put the
-- materials in their output box. Shared: anyone nearby can load, start, stop or empty one.

local S = Recycler.Settings
local INV = exports.bs_inventory
local RES = GetCurrentResourceName()

local points = {}     -- [id] = { id, label, x, y, z, h, fuel }
local M = {}          -- [id] = { running, status, next, starter, noiseAt }
local blacklist = {}  -- F1 extras, [item] = true

local function inId(id) return ('recycler:%s:in'):format(id) end
local function outId(id) return ('recycler:%s:out'):format(id) end

local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars) })
end

local function itemDef(name)
    local ok, d = pcall(function() return INV:GetItem(name) end)
    return ok and d or nil
end
-- Item name in the player's language (server default without src).
local function labelOf(n, src)
    local ok, l = pcall(function() return INV:ItemLabel(n, src) end)
    if ok and l then return l end
    local d = itemDef(n); return d and d.label or n end

local function log(src, kind, details)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local p = exports.bs_core:GetPlayer(src)
    MySQL.insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,0,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), p and p.charId, (GetPlayerName(src) or '?'):sub(1, 64), kind, tostring(details):sub(1, 512), c.x, c.y, c.z })
end

--------------------------------------------------------------------------------
-- What an item gives back
--------------------------------------------------------------------------------

local function refused(item) return Recycler.Never[item] or blacklist[item] end

local function bonusFor(src)
    if not src or GetResourceState('bs_skills') ~= 'started' then return 0 end
    local ok, lv = pcall(function() return exports.bs_skills:GetSkillLevel(src, S.skill) end)
    return math.min(S.bonusMax or 0.15, ((ok and tonumber(lv)) or 0) * (S.bonusPerLevel or 0.01))
end

-- Expected amounts (floats) for one unit at a given share of the crafting cost.
local function expected(item, rate)
    local out = {}
    local tbl = Recycler.Yields[item]
    if tbl then
        local scale = rate / 0.5
        for _, e in ipairs(tbl) do out[e.item] = (out[e.item] or 0) + ((e.amount[1] + e.amount[2]) / 2) * scale end
        return out
    end
    if GetResourceState('bs_crafting') == 'started' then
        local ok, r = pcall(function() return exports.bs_crafting:RecipeFor(item) end)
        if ok and r then
            for _, c in ipairs(r.cost) do out[c.item] = (out[c.item] or 0) + c.amount * rate / (r.amount or 1) end
            return out
        end
    end
    local def = itemDef(item)
    if def and def.category == 'weapon' and def.data and def.data.spawnRounds then
        local scale = rate / 0.5
        for _, e in ipairs(Recycler.Firearm) do out[e.item] = (out[e.item] or 0) + ((e.amount[1] + e.amount[2]) / 2) * scale end
        return out
    end
    local value = def and tonumber(def.value) or 0
    local unit = (itemDef('scrap_metal') or {}).value or 6
    if value > 0 then out.scrap_metal = value * rate / unit end
    return out
end

local function canRecycle(item)
    if refused(item) then return false end
    return next(expected(item, 0.5)) ~= nil
end

-- Rolled amounts for one unit. Random rounding keeps the long-run average right.
local function rollYield(item, metadata, rate, bonus)
    local out = {}
    local tbl = Recycler.Yields[item]
    if tbl then
        local scale = rate / 0.5 * (1 + bonus)
        for _, e in ipairs(tbl) do
            local v = math.random(e.amount[1], e.amount[2]) * scale
            local n = math.floor(v) + ((math.random() < v % 1) and 1 or 0)
            if n > 0 then out[e.item] = (out[e.item] or 0) + n end
        end
    else
        for name, v in pairs(expected(item, rate)) do
            v = v * (1 + bonus)
            local n = math.floor(v) + ((math.random() < v % 1) and 1 or 0)
            if n > 0 then out[name] = (out[name] or 0) + n end
        end
    end
    -- Attachments fitted to a gun come back whole.
    if type(metadata) == 'table' and type(metadata.attachments) == 'table' then
        for k, v in pairs(metadata.attachments) do
            local name = (type(v) == 'string' and itemDef(v) and v) or ('att_' .. tostring(k))
            if itemDef(name) then out[name] = (out[name] or 0) + 1 end
        end
    end
    return out
end

local function preview(item, rate, bonus, count, src)
    local list = {}
    for name, v in pairs(expected(item, rate)) do
        local n = v * (1 + bonus) * (count or 1)
        list[#list + 1] = ('%s %s'):format(n >= 10 and math.floor(n + 0.5) or (math.floor(n * 10 + 0.5) / 10), labelOf(name, src))
    end
    table.sort(list)
    return table.concat(list, ', ')
end

local function toolFor(item)
    local tbl = Recycler.Yields[item]
    if tbl and tbl.tool then return tbl.tool end
    local e = expected(item, 0.5)
    if e.electronics or e.wires then return 'screwdriver' end
    return 'wrench'
end

--------------------------------------------------------------------------------
-- Points
--------------------------------------------------------------------------------

local function pointList()
    local out = {}
    for _, p in pairs(points) do
        out[#out + 1] = { id = p.id, label = p.label, x = p.x, y = p.y, z = p.z, h = p.h, running = M[p.id] and M[p.id].running or false }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function announce(target) TriggerClientEvent('bs:recycler:points', target or -1, pointList()) end

local function register(p)
    INV:RegisterContainer(inId(p.id), { width = S.inSize.w, height = S.inSize.h, maxWeight = S.inSize.maxWeight, label = L('rec.input') })
    INV:RegisterContainer(outId(p.id), { width = S.outSize.w, height = S.outSize.h, maxWeight = S.outSize.maxWeight, label = L('rec.output') })
    M[p.id] = M[p.id] or { running = false, status = 'idle' }
end

local function savePoint(p)
    MySQL.update('INSERT INTO `bs_recycler_points` (`id`,`label`,`x`,`y`,`z`,`h`,`fuel`) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE `label`=VALUES(`label`),`x`=VALUES(`x`),`y`=VALUES(`y`),`z`=VALUES(`z`),`h`=VALUES(`h`),`fuel`=VALUES(`fuel`)',
        { p.id, p.label, p.x, p.y, p.z, p.h or 0.0, p.fuel or 0.0 })
end

local function at(src, id)
    if not S.enabled then return nil, 'off' end
    local p = points[tostring(id)]
    if not p then return nil, 'no_machine' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'no_machine' end
    if #(GetEntityCoords(ped) - vector3(p.x, p.y, p.z)) > (S.radius + 2.5) then return nil, 'too_far' end
    return p
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function setRunning(id, on, status)
    local m = M[id]
    if not m then return end
    local was = m.running
    m.running, m.status = on, status or (on and 'running' or 'idle')
    if on and not m.next then m.next = os.time() + (S.itemSeconds or 5) end
    if not on then m.next = nil end
    if was ~= on then TriggerClientEvent('bs:recycler:running', -1, id, on) end
end

local function giveAll(cid, out)
    local added = {}
    for name, n in pairs(out) do
        if INV:ContainerGiveAll(cid, name, n) then added[#added + 1] = { name, n }
        else
            for _, a in ipairs(added) do INV:ContainerRemove(cid, a[1], a[2]) end
            return false
        end
    end
    return true
end

local function starterSrc(m)
    if m.starter and GetPlayerName(m.starter) then return m.starter end
end

local function step(id, p, m, t)
    if not m.running then return end
    if (p.fuel or 0) < (1 / (S.itemsPerLitre or 10)) - 1e-6 then return setRunning(id, false, 'no_fuel') end

    if (m.noiseAt or 0) <= t and GetResourceState('bs_zombies') == 'started' then
        m.noiseAt = t + (S.noiseEvery or 10)
        pcall(function() exports.bs_zombies:EventNoise(p.x, p.y, p.z, S.noiseRadius or 150.0, 'recycler') end)
    end
    if t < (m.next or 0) then return end

    local unit = INV:ContainerTakeOne(inId(id))
    if not unit then return setRunning(id, false, 'empty') end
    if refused(unit.item) then
        -- Should not get in, but never eat it: send it to the output untouched.
        INV:ContainerGiveAll(outId(id), unit.item, 1, unit.metadata)
        m.next = t + 1
        return
    end
    local src = starterSrc(m)
    local out = rollYield(unit.item, unit.metadata, S.yieldRate or 0.5, bonusFor(src))
    if not giveAll(outId(id), out) then
        INV:ContainerGiveAll(inId(id), unit.item, 1, unit.metadata)
        m.status = 'output_full'
        m.next = t + 3
        return
    end
    m.status = 'running'
    p.fuel = math.max(0, (p.fuel or 0) - 1 / (S.itemsPerLitre or 10))
    p.dirty = true
    m.next = t + (S.itemSeconds or 5)
    m.done = (m.done or 0) + 1
    if src and GetResourceState('bs_skills') == 'started' then
        pcall(function() exports.bs_skills:AddSkillXP(src, S.skill, S.xpPerItem or 1) end)
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local t = os.time()
        for id, m in pairs(M) do
            local p = points[id]
            if p then
                local ok, err = pcall(step, id, p, m, t)
                if not ok then print('^1[bs_recycler] ' .. tostring(err) .. '^7') end
            end
        end
    end
end)

-- Fuel is saved now and then, not every item.
CreateThread(function()
    while true do
        Wait(30000)
        for _, p in pairs(points) do if p.dirty then p.dirty = nil; savePoint(p) end end
    end
end)

--------------------------------------------------------------------------------
-- Panel callbacks (the CRAFT tab in the inventory, machine view)
--------------------------------------------------------------------------------

local function view(src, p)
    local m = M[p.id]
    local bonus = bonusFor(src)
    local function list(cid)
        local out, idx = {}, {}
        for _, e in ipairs(INV:ContainerContents(cid)) do
            if idx[e.item] then out[idx[e.item]].amount = out[idx[e.item]].amount + e.amount
            else
                local d = itemDef(e.item) or {}
                out[#out + 1] = { item = e.item, amount = e.amount, label = labelOf(e.item, src), category = d.category }
                idx[e.item] = #out
            end
        end
        return out
    end
    local input = list(inId(p.id))
    local totals = {}
    for _, e in ipairs(input) do
        for name, v in pairs(expected(e.item, S.yieldRate or 0.5)) do totals[name] = (totals[name] or 0) + v * (1 + bonus) * e.amount end
    end
    local prev = {}
    for name, v in pairs(totals) do prev[#prev + 1] = { item = name, label = labelOf(name, src), amount = math.floor(v + 0.5) } end
    table.sort(prev, function(a, b) return a.amount > b.amount end)

    local bag = {}
    for item, n in pairs(INV:ItemCounts(src)) do
        if canRecycle(item) then
            local d = itemDef(item) or {}
            bag[#bag + 1] = { item = item, amount = n, label = labelOf(item, src), category = d.category, preview = preview(item, S.yieldRate or 0.5, bonus, 1, src) }
        end
    end
    table.sort(bag, function(a, b) return a.label < b.label end)

    local fuelHave = INV:MeasuredInfo(src, S.fuelItems)
    return {
        ok = true, id = p.id, label = p.label, fuel = p.fuel or 0, fuelMax = S.fuelMax, running = m.running,
        status = m.status, bonus = math.floor(bonus * 100 + 0.5), itemSeconds = S.itemSeconds, itemsPerLitre = S.itemsPerLitre,
        input = input, output = list(outId(p.id)), bag = bag, preview = prev,
        progress = (m.running and m.next) and math.max(0, math.min(1, 1 - (m.next - os.time()) / (S.itemSeconds or 5))) or nil,
        canFuel = (fuelHave and fuelHave.held or 0) > 0 and (p.fuel or 0) < S.fuelMax,
    }
end

BSB.RegisterCallback('recycler:state', function(src, id)
    local p, why = at(src, id)
    if not p then return { ok = false, error = Lp(src, why) } end
    return view(src, p)
end)

BSB.RegisterCallback('recycler:act', function(src, id, action, item, all)
    local p, why = at(src, id)
    if not p then return { ok = false, error = Lp(src, why) } end
    local m = M[p.id]
    item = item and tostring(item)

    if action == 'load' then
        if refused(item) or not canRecycle(item) then return { ok = false, error = Lp(src, 'refused') } end
        local n = all and INV:CountItem(src, item) or 1
        if n < 1 or not INV:MoveToContainer(src, item, n, inId(p.id)) then return { ok = false, error = Lp(src, 'input_full') } end
    elseif action == 'unload' then
        local n = all and INV:ContainerCount(inId(p.id), item) or 1
        if not INV:MoveFromContainer(src, item, n, inId(p.id)) then return { ok = false, error = Lp(src, 'bag_full') } end
    elseif action == 'takeOutput' then
        local taken = {}
        for _, e in ipairs(INV:ContainerContents(outId(p.id))) do
            if item == '*' or e.item == item then
                if INV:MoveFromContainer(src, e.item, e.amount, outId(p.id)) then taken[#taken + 1] = e.amount .. 'x ' .. e.item end
            end
        end
        if #taken > 0 then log(src, 'recycle_take', p.id .. ': ' .. table.concat(taken, ', ')) end
        -- A machine paused on a full output starts again by itself once there is room.
    elseif action == 'start' then
        if (p.fuel or 0) <= 0 then return { ok = false, error = Lp(src, 'no_fuel') } end
        if #INV:ContainerContents(inId(p.id)) == 0 then return { ok = false, error = Lp(src, 'empty') } end
        m.starter = src
        setRunning(p.id, true)
        log(src, 'recycle_start', p.id)
    elseif action == 'stop' then
        setRunning(p.id, false, 'idle')
    elseif action == 'fuel' then
        local room = S.fuelMax - (p.fuel or 0)
        if room <= 0.05 then return { ok = false, error = Lp(src, 'tank_full') } end
        local drawn = INV:PourOut(src, S.fuelItems, room)
        if drawn <= 0 then return { ok = false, error = Lp(src, 'no_fuel_carried') } end
        p.fuel = (p.fuel or 0) + drawn
        savePoint(p)
    else
        return { ok = false }
    end
    return view(src, p)
end)

--------------------------------------------------------------------------------
-- Exports for bs_crafting (hand dismantle) and admin
--------------------------------------------------------------------------------

exports('CanRecycle', canRecycle)
exports('ToolFor', function(item) if not canRecycle(item) then return nil end return toolFor(item) end)
exports('DismantleSeconds', function() return S.dismantleSeconds or 10 end)
exports('HandYield', function(src, item) return rollYield(item, nil, S.dismantleRate or 0.25, bonusFor(src)) end)
exports('DismantleCandidates', function(src)
    local out = {}
    local bonus = bonusFor(src)
    for item, n in pairs(INV:ItemCounts(src)) do
        local d = itemDef(item) or {}
        -- Hand dismantling is for junk and parts, not for breaking down the crafted gear you are carrying.
        if canRecycle(item) and (d.category == 'junk' or Recycler.Yields[item]) then
            local tool = toolFor(item)
            out[#out + 1] = { item = item, count = n, label = labelOf(item, src), category = d.category,
                tool = tool, toolLabel = labelOf(tool, src), hasTool = INV:CountItem(src, tool) > 0,
                preview = preview(item, S.dismantleRate or 0.25, bonus, 1, src) }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

-- F1 pages (bs_config checks admin rights before calling).
local function adminState()
    local bl = {}
    for k in pairs(blacklist) do bl[#bl + 1] = k end
    table.sort(bl)
    local fixed = {}
    for k in pairs(Recycler.Never) do fixed[#fixed + 1] = k end
    table.sort(fixed)
    return { ok = true, points = pointList(), blacklist = bl, fixed = fixed }
end

local function saveBlacklist()
    local list = {}
    for k in pairs(blacklist) do list[#list + 1] = k end
    SaveResourceFile(RES, 'data/blacklist.json', json.encode(list), -1)
end

exports('ConfigExt', function(src, action, a)
    if action == 'points' then return adminState() end
    if action == 'addHere' then
        if src <= 0 then return { ok = false, error = 'Run it in game.' } end
        local c = GetEntityCoords(GetPlayerPed(src))
        local id = ('r%d'):format(os.time())
        local p = { id = id, label = (type(a) == 'string' and a ~= '' and a:sub(1, 32)) or 'Recycler', x = c.x, y = c.y, z = c.z - 1.0, h = GetEntityHeading(GetPlayerPed(src)), fuel = 0.0 }
        points[id] = p
        register(p); savePoint(p); announce()
        log(src, 'recycle_admin', 'added ' .. id)
        return adminState()
    elseif action == 'edit' and type(a) == 'table' then
        local p = points[tostring(a.id)]
        if not p then return { ok = false, error = 'No such machine.' } end
        p.label = type(a.label) == 'string' and a.label:sub(1, 32) or p.label
        p.x, p.y, p.z = tonumber(a.x) or p.x, tonumber(a.y) or p.y, tonumber(a.z) or p.z
        p.h = tonumber(a.h) or p.h
        if a.here and src > 0 then
            local c = GetEntityCoords(GetPlayerPed(src))
            p.x, p.y, p.z, p.h = c.x, c.y, c.z - 1.0, GetEntityHeading(GetPlayerPed(src))
        end
        savePoint(p); announce()
        log(src, 'recycle_admin', 'edited ' .. p.id)
        return adminState()
    elseif action == 'remove' then
        local p = points[tostring(a)]
        if not p then return { ok = false, error = 'No such machine.' } end
        setRunning(p.id, false)
        points[p.id], M[p.id] = nil, nil
        MySQL.update('DELETE FROM `bs_recycler_points` WHERE `id` = ?', { p.id })
        announce()
        log(src, 'recycle_admin', 'removed ' .. p.id)
        return adminState()
    elseif action == 'goto' then
        local p = points[tostring(a)]
        if p and src > 0 then
            if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 20000) end) end
            TriggerClientEvent('bs:core:safeTp', src, p.x + 0.0, p.y + 0.0, p.z + 0.0)
        end
        return adminState()
    elseif action == 'blacklist' and type(a) == 'table' then
        blacklist = {}
        for _, name in ipairs(a) do if type(name) == 'string' and itemDef(name) then blacklist[name] = true end end
        saveBlacklist()
        return adminState()
    end
    return { ok = false, error = 'Unknown action.' }
end)

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

AddEventHandler('bs:hook:player:spawned', function(p) if p and p.source then announce(p.source) end end)
BSB.RegisterCallback('recycler:points', function() return { ok = true, points = pointList() } end)
AddEventHandler('playerDropped', function()
    for _, m in pairs(M) do if m.starter == source then m.starter = nil end end
end)

CreateThread(function()
    local raw = LoadResourceFile(RES, 'data/blacklist.json')
    local ok, list = pcall(json.decode, raw or '[]')
    for _, n in ipairs(ok and list or {}) do blacklist[n] = true end

    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    Wait(2000)
    local rows = MySQL.query.await('SELECT * FROM `bs_recycler_points`') or {}
    if #rows == 0 then
        for _, s in ipairs(Recycler.Points) do
            local p = { id = s.id, label = s.label, x = s.coords.x, y = s.coords.y, z = s.coords.z, h = s.coords.w or 0.0, fuel = 0.0 }
            savePoint(p)
            rows[#rows + 1] = p
        end
        -- Machines placed with the old /recycler add carry over once.
        local oldRaw = LoadResourceFile(RES, 'recyclers.json')
        local okOld, old = pcall(json.decode, oldRaw or '')
        for _, a in ipairs(okOld and type(old) == 'table' and old.added or {}) do
            if a.id and a.coords then
                local p = { id = tostring(a.id):sub(1, 48), label = 'Recycler', x = a.coords.x, y = a.coords.y, z = a.coords.z, h = 0.0, fuel = 0.0 }
                if not points[p.id] then savePoint(p); rows[#rows + 1] = p end
            end
        end
    end
    for _, r in ipairs(rows) do
        local p = { id = tostring(r.id), label = r.label or 'Recycler', x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, h = (r.h or 0.0) + 0.0, fuel = (r.fuel or 0.0) + 0.0 }
        points[p.id] = p
        register(p)
    end
    announce()
    print(('^2[BeyondSurvival]^7 (recycler) %d machine(s) online'):format(#pointList()))
end)

exports.bs_core:RegisterModule('recycler', { side = 'server', version = '1.0.0' })
