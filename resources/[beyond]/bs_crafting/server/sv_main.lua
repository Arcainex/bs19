-- bs_crafting server. Owns every queue. The client only draws the panel and plays animations.

local S = Crafting.Settings
local RES = GetCurrentResourceName()
local INV = exports.bs_inventory

Craft = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function now() return os.time() end

local function started(res) return GetResourceState(res) == 'started' end

local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars) })
end
Craft.Notify = notify

local function player(src) return exports.bs_core:GetPlayer(src) end
local function charId(src) local p = player(src); return p and p.charId end

local function itemDef(name)
    local ok, d = pcall(function() return INV:GetItem(name) end)
    return ok and d or nil
end
Craft.ItemDef = itemDef
-- Item name in the player's language (server default without src).
local function labelOf(name, src)
    local ok, l = pcall(function() return INV:ItemLabel(name, src) end)
    if ok and l then return l end
    local d = itemDef(name); return d and d.label or name
end
Craft.Label = labelOf

local function pedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
Craft.PedPos = pedPos

-- Activity log into bs_guard_log (confidence 0 = normal activity, not a detection).
function Craft.Log(src, kind, details)
    local c = pedPos(src) or vector3(0, 0, 0)
    local lic = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license') or nil
    MySQL.insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,0,?,?,?,?)',
        { src, lic, charId(src), (GetPlayerName(src) or '?'):sub(1, 64), kind:sub(1, 32), tostring(details):sub(1, 512), c.x, c.y, c.z })
end

function Craft.SkillLevel(src)
    if not started('bs_skills') then return 0 end
    local ok, lv = pcall(function() return exports.bs_skills:GetSkillLevel(src, S.skill) end)
    return (ok and tonumber(lv)) or 0
end

function Craft.AddXP(src, xp)
    if xp > 0 and started('bs_skills') then
        pcall(function() exports.bs_skills:AddSkillXP(src, S.skill, math.floor(xp + 0.5)) end)
    end
end

-- Give to the bag, or queue for next spawn when the bag is full. Never deletes.
function Craft.GiveOrPend(src, item, amount)
    if amount <= 0 then return true end
    if INV:GiveAll(src, item, amount) then return true end
    local p = player(src)
    if not p then return false end
    local pending = (p.metadata and p.metadata.pendingLoadout) or {}
    pending[#pending + 1] = { item = item, amount = amount }
    exports.bs_core:SetPlayerMeta(src, 'pendingLoadout', pending)
    notify(src, 'warn', 'bag_full_later', { item = labelOf(item, src), amount = amount })
    return false
end

function Craft.Roll(list, mult)
    local out = {}
    for _, e in ipairs(list or {}) do
        if not e.chance or math.random() <= e.chance then
            local lo, hi = e.amount[1], e.amount[2] or e.amount[1]
            local n = math.floor(math.random(lo, hi) * (mult or 1) + 0.5)
            if n > 0 then out[e.item] = (out[e.item] or 0) + n end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Recipes (config + F1 overrides)
--------------------------------------------------------------------------------

local OVERRIDE_FILE = 'data/recipes.json'
local overrides = {}

local function loadOverrides()
    local raw = LoadResourceFile(RES, OVERRIDE_FILE)
    local ok, data = pcall(json.decode, raw or '')
    overrides = (ok and type(data) == 'table') and data or {}
end

function Craft.Recipes()
    local out = {}
    for id, r in pairs(Crafting.Recipes) do out[id] = r end
    for id, r in pairs(overrides) do
        if r == false then out[id] = nil
        elseif type(r) == 'table' then out[id] = r end
    end
    return out
end

function Craft.Recipe(id) return Craft.Recipes()[id] end
function Craft.Overrides() return overrides end

function Craft.SaveOverrides(tbl)
    overrides = tbl or {}
    SaveResourceFile(RES, OVERRIDE_FILE, json.encode(overrides, { indent = true }), -1)
    TriggerEvent('bs:crafting:recipesChanged')
end

function Craft.TimeFor(src, recipe)
    local cut = math.min(S.maxSpeedCut or 0.5, Craft.SkillLevel(src) * (S.speedPerLevel or 0))
    return math.max(1, math.floor((recipe.time or 5) * (1 - cut) + 0.5))
end

local function recipeAllowed(src, recipe)
    if recipe.explosive and not S.allowExplosives then return false, 'explosives_off' end
    if recipe.factionBase then
        local ok, home = pcall(function()
            local f = exports.bs_factions:GetFactionSummary(src)
            local flag = exports.bs_faction_bases:FlagAt(src)
            return f and f.factionId and flag and flag.factionId == f.factionId
        end)
        if not (ok and home) then return false, 'faction_base_only' end
    end
    if recipe.tool then
        local has = false
        for _, t in ipairs(recipe.tool) do if INV:CountItem(src, t) > 0 then has = true break end end
        if not has then return false, 'need_tool' end
    end
    return true
end

--------------------------------------------------------------------------------
-- Stations (bs_building pieces) and their storage
--------------------------------------------------------------------------------

local St = {}          -- [pieceId] = { type, queue = {}, burn = {} }
local dbReady = false

local function storageId(id) return ('craftst:%s'):format(id) end
Craft.StorageId = storageId

local function registerStorage(id, label)
    INV:RegisterContainer(storageId(id), { width = S.storageSize.w, height = S.storageSize.h,
        maxWeight = S.storageSize.maxWeight, label = label or 'Station' })
end

local function saveStation(id)
    local s = St[id]
    if not s or not dbReady then return end
    MySQL.update('INSERT INTO `bs_craft_stations` (`piece_id`,`type`,`data`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `type`=VALUES(`type`),`data`=VALUES(`data`)',
        { id, s.type, json.encode({ queue = s.queue, burn = s.burn, crop = s.crop }) })
end
Craft.SaveStation = saveStation

local function stationState(id, typ)
    local s = St[id]
    if not s then
        s = { type = typ, queue = {}, burn = {} }
        St[id] = s
        registerStorage(id, Crafting.Stations[typ] and Crafting.Stations[typ].label)
    end
    return s
end
Craft.StationState = stationState
Craft.Stations = St

-- Building pieces near a point that are our stations.
function Craft.PiecesNear(x, y, z, radius)
    if not started('bs_building') then return {} end
    local ok, list = pcall(function() return exports.bs_building:PiecesInRadius(x, y, z, radius) end)
    local out = {}
    for _, v in ipairs(ok and list or {}) do
        if Crafting.Stations[v.p] then out[#out + 1] = v end
    end
    return out
end

function Craft.CanUse(src, view)
    local cid = charId(src)
    if view.ow and cid and tonumber(view.ow) == tonumber(cid) then return true end
    if view.f and started('bs_factions') then
        local ok, f = pcall(function() return exports.bs_factions:GetFaction(src) end)
        if ok and f and tostring(f) == tostring(view.f) then return true end
    end
    if not view.ow and not view.f then return true end
    return false
end

-- The station this player is standing at, checked against the real ped position.
function Craft.StationAt(src, id)
    id = tonumber(id)
    local c = pedPos(src)
    if not id or not c then return nil, 'no_station' end
    for _, v in ipairs(Craft.PiecesNear(c.x, c.y, c.z, (S.stationRadius or 3.0) + 2.5)) do
        if tonumber(v.id) == id then
            if not v.b then return nil, 'not_built' end
            if not Craft.CanUse(src, v) then return nil, 'not_yours' end
            stationState(id, v.p)
            return v
        end
    end
    return nil, 'too_far'
end

-- Storages that feed a craft: every station this player may use within materialRadius.
local function sources(src)
    local c = pedPos(src)
    if not c then return {} end
    local out = {}
    for _, v in ipairs(Craft.PiecesNear(c.x, c.y, c.z, S.materialRadius or 10.0)) do
        if v.b and Craft.CanUse(src, v) then
            stationState(tonumber(v.id), v.p)
            out[#out + 1] = storageId(v.id)
        end
    end
    return out
end

local function haveCount(src, srcs, item)
    local n = INV:CountItem(src, item)
    for _, cid in ipairs(srcs) do n = n + INV:ContainerCount(cid, item) end
    return n
end

-- Takes a recipe's cost, bag first. Returns the list taken, or nil when short (nothing is taken then).
local function takeCost(src, srcs, cost, times)
    for _, c in ipairs(cost) do
        if haveCount(src, srcs, c.item) < c.amount * times then return nil, c.item end
    end
    local taken = {}
    for _, c in ipairs(cost) do
        local need = c.amount * times
        local inBag = math.min(need, INV:CountItem(src, c.item))
        if inBag > 0 and INV:RemoveItem(src, c.item, inBag) then need = need - inBag end
        for _, cid in ipairs(srcs) do
            if need <= 0 then break end
            local n = math.min(need, INV:ContainerCount(cid, c.item))
            if n > 0 and INV:ContainerRemove(cid, c.item, n) then need = need - n end
        end
        taken[#taken + 1] = { item = c.item, amount = c.amount * times - need }
        if need > 0 then
            -- Something moved under us: put back what we took.
            for _, t in ipairs(taken) do Craft.GiveOrPend(src, t.item, t.amount) end
            return nil, c.item
        end
    end
    return taken
end

--------------------------------------------------------------------------------
-- Queues
--------------------------------------------------------------------------------

local Hand = {}        -- [src] = { jobs }
local nextJob = 0
local function jobId() nextJob = nextJob + 1; return ('%d%04d'):format(now() % 100000, nextJob % 10000) end

local function payloadJob(j, t, src)
    local r = Craft.Recipe(j.recipe)
    return {
        id = j.id, recipe = j.recipe, item = j.item, amount = j.amount, label = labelOf(j.item, src),
        category = (itemDef(j.item) or {}).category, dur = j.dur,
        left = j.endsAt and math.max(0, j.endsAt - t) or j.dur, running = j.endsAt ~= nil,
        status = j.status, mine = true, station = r and r.station,
    }
end

local function refund(src, job, fallbackContainer)
    for _, t in ipairs(job.cost or {}) do
        local ok = src and INV:GiveAll(src, t.item, t.amount)
        if not ok and fallbackContainer then ok = INV:ContainerGiveAll(fallbackContainer, t.item, t.amount) end
        if not ok and src then Craft.GiveOrPend(src, t.item, t.amount) end
    end
end

local function finish(src, job)
    local r = Craft.Recipe(job.recipe) or {}
    Craft.AddXP(src, (r.time or job.dur) * (S.xpPerSecond or 0.4))
    pcall(function() exports.bs_core:AwardAction(src, 'item_crafted') end)
    -- faction jobs: cooks count food, everyone else counts crafts (bs_jobs)
    TriggerEvent('bs:jobs:event', src, r.cat == 'food' and 'craft_food' or 'craft', job.amount or 1, { item = job.item })
    local p = player(src)
    if p then
        MySQL.insert('INSERT INTO `bs_character_stats` (`character_id`, `items_crafted`) VALUES (?, 1) ON DUPLICATE KEY UPDATE `items_crafted` = `items_crafted` + 1', { p.charId })
    end
    Craft.Log(src, 'craft', ('%s x%d (%s)'):format(job.item, job.amount, job.recipe))
    notify(src, 'success', 'crafted', { item = labelOf(job.item, src), amount = job.amount })
end

local function srcByChar(cid)
    for _, pid in ipairs(GetPlayers()) do
        local p = player(tonumber(pid))
        if p and tonumber(p.charId) == tonumber(cid) then return tonumber(pid) end
    end
end

local function tick()
    local t = now()
    for src, q in pairs(Hand) do
        local j = q[1]
        if j then
            if not j.endsAt then j.endsAt = t + j.dur end
            if t >= j.endsAt then
                if INV:GiveAll(src, j.item, j.amount) then
                    table.remove(q, 1)
                    finish(src, j)
                    TriggerClientEvent('bs:crafting:changed', src)
                elseif j.status ~= 'full' then
                    j.status = 'full'
                    notify(src, 'warn', 'bag_full_wait')
                end
            end
        end
    end
    for id, s in pairs(St) do
        local j = s.queue and s.queue[1]
        if j then
            if not j.endsAt then j.endsAt = t + j.dur; saveStation(id) end
            if t >= j.endsAt then
                if INV:ContainerGiveAll(storageId(id), j.item, j.amount) then
                    table.remove(s.queue, 1)
                    local r = Craft.Recipe(j.recipe)
                    if r and r.burn then s.burn[#s.burn + 1] = { item = j.item, amount = j.amount, burnt = r.burn, at = t + (S.burnAfter or 180) } end
                    local owner = srcByChar(j.owner)
                    if owner then finish(owner, j) end
                    saveStation(id)
                elseif j.status ~= 'full' then
                    j.status = 'full'
                    saveStation(id)
                end
            end
        end
        -- Food left on the fire burns.
        for i = #(s.burn or {}), 1, -1 do
            local b = s.burn[i]
            if t >= b.at then
                table.remove(s.burn, i)
                local have = INV:ContainerCount(storageId(id), b.item)
                local n = math.min(have, b.amount)
                if n > 0 and INV:ContainerRemove(storageId(id), b.item, n) then
                    INV:ContainerGiveAll(storageId(id), b.burnt, n)
                end
                saveStation(id)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local ok, err = pcall(tick)
        if not ok then print('^1[bs_crafting] tick: ' .. tostring(err) .. '^7') end
    end
end)

--------------------------------------------------------------------------------
-- Callbacks used by the craft panel (bs_inventory/html/js/craft.js through our client)
--------------------------------------------------------------------------------

local function recipeList(src, stationType, srcs)
    local out, items = {}, {}
    for id, r in pairs(Craft.Recipes()) do
        if r.station == stationType and not (r.explosive and not S.allowExplosives) then
            local def = itemDef(r.result.item) or {}
            local costs, can = {}, true
            for _, c in ipairs(r.cost or {}) do
                local have = items[c.item] or haveCount(src, srcs, c.item)
                items[c.item] = have
                costs[#costs + 1] = { item = c.item, label = labelOf(c.item, src), need = c.amount, have = have,
                    category = (itemDef(c.item) or {}).category }
                if have < c.amount then can = false end
            end
            local ok, why = recipeAllowed(src, r)
            local tools = {}
            for _, t in ipairs(r.tool or {}) do tools[#tools + 1] = labelOf(t, src) end
            out[#out + 1] = {
                id = id, cat = r.cat or 'misc', label = r.label or labelOf(r.result.item, src),
                item = r.result.item, amount = r.result.amount or 1, category = def.category or 'misc',
                costs = costs, time = Craft.TimeFor(src, r), baseTime = r.time, tools = tools,
                can = can and ok, blocked = (not ok) and Lp(src, why) or nil, explosive = r.explosive or nil,
            }
        end
    end
    table.sort(out, function(a, b) if a.cat ~= b.cat then return a.cat < b.cat end return a.label < b.label end)
    return out
end

BSB.RegisterCallback('crafting:state', function(src, stationId)
    if not player(src) then return { ok = false } end
    local srcs = sources(src)
    local t = now()
    local res = { ok = true, enabled = S.enabled, level = Craft.SkillLevel(src), categories = Crafting.Categories,
        sourceCount = #srcs, handMax = S.handQueueMax, stationMax = S.stationQueueMax }

    local hq = {}
    for _, j in ipairs(Hand[src] or {}) do hq[#hq + 1] = payloadJob(j, t, src) end
    res.hand = hq

    if stationId then
        local v, why = Craft.StationAt(src, stationId)
        if not v then return { ok = false, error = Lp(src, why) } end
        local s = St[tonumber(v.id)]
        local def = Crafting.Stations[v.p]
        res.station = { id = v.id, type = v.p, label = def.label, farm = def.farm or nil }
        local cid = charId(src)
        local q = {}
        for _, j in ipairs(s.queue) do
            local pj = payloadJob(j, t, src)
            pj.mine = tonumber(j.owner) == tonumber(cid)
            pj.owner = j.ownerName
            q[#q + 1] = pj
        end
        res.queue = q
        local store = {}
        for _, e in ipairs(INV:ContainerContents(storageId(v.id))) do
            local d = itemDef(e.item) or {}
            store[#store + 1] = { item = e.item, amount = e.amount, label = labelOf(e.item, src), category = d.category }
        end
        res.storage = store
        if def.farm then
            res.farm = Craft.FarmView and Craft.FarmView(src, tonumber(v.id)) or nil
        else
            res.recipes = recipeList(src, v.p, srcs)
        end
    else
        res.recipes = recipeList(src, nil, srcs)
        res.dismantle = Craft.DismantleList and Craft.DismantleList(src) or {}
    end
    return res
end)

BSB.RegisterCallback('crafting:hand', function(src)
    local t, out = now(), {}
    for _, j in ipairs(Hand[src] or {}) do out[#out + 1] = payloadJob(j, t, src) end
    return { ok = true, jobs = out }
end)

local lastQueue = {}

BSB.RegisterCallback('crafting:queue', function(src, recipeId, count, stationId)
    if not S.enabled then return { ok = false, error = Lp(src, 'disabled') } end
    local p = player(src)
    if not p then return { ok = false } end
    local ms = GetGameTimer()
    if lastQueue[src] and ms - lastQueue[src] < 400 then return { ok = false, error = Lp(src, 'slow_down') } end
    lastQueue[src] = ms

    local r = Craft.Recipe(tostring(recipeId))
    if not r then return { ok = false, error = Lp(src, 'no_recipe') } end
    count = math.max(1, math.min(10, math.floor(tonumber(count) or 1)))

    local ok, why = recipeAllowed(src, r)
    if not ok then return { ok = false, error = Lp(src, why) } end

    local queue, view
    if r.station then
        if not stationId then return { ok = false, error = Lp(src, 'need_station', { station = Crafting.Stations[r.station].label }) } end
        local v, err = Craft.StationAt(src, stationId)
        if not v then return { ok = false, error = Lp(src, err) } end
        if v.p ~= r.station then return { ok = false, error = Lp(src, 'wrong_station') } end
        view = v
        queue = St[tonumber(v.id)].queue
        if #queue + count > (S.stationQueueMax or 8) then return { ok = false, error = Lp(src, 'queue_full') } end
    else
        Hand[src] = Hand[src] or {}
        queue = Hand[src]
        if #queue + count > (S.handQueueMax or 5) then return { ok = false, error = Lp(src, 'queue_full') } end
    end

    local srcs = sources(src)
    for _ = 1, count do
        local taken, short = takeCost(src, srcs, r.cost or {}, 1)
        if not taken then
            if _ == 1 then return { ok = false, error = Lp(src, 'missing', { item = labelOf(short, src) }) } end
            break
        end
        queue[#queue + 1] = {
            id = jobId(), recipe = recipeId, item = r.result.item, amount = r.result.amount or 1,
            dur = Craft.TimeFor(src, r), cost = taken, owner = p.charId, ownerName = p.name or GetPlayerName(src),
        }
    end
    if view then saveStation(tonumber(view.id)) end
    INV:Refresh(src)
    return { ok = true }
end)

BSB.RegisterCallback('crafting:cancel', function(src, jobIdArg, stationId)
    local p = player(src)
    if not p then return { ok = false } end
    jobIdArg = tostring(jobIdArg)
    if stationId then
        local v, err = Craft.StationAt(src, stationId)
        if not v then return { ok = false, error = Lp(src, err) } end
        local s = St[tonumber(v.id)]
        for i, j in ipairs(s.queue) do
            if j.id == jobIdArg then
                if tonumber(j.owner) ~= tonumber(p.charId) then return { ok = false, error = Lp(src, 'not_your_job') } end
                table.remove(s.queue, i)
                if i == 1 and s.queue[1] then s.queue[1].endsAt = nil end
                refund(src, j, storageId(v.id))
                saveStation(tonumber(v.id))
                return { ok = true }
            end
        end
    else
        for i, j in ipairs(Hand[src] or {}) do
            if j.id == jobIdArg then
                table.remove(Hand[src], i)
                if i == 1 and Hand[src][1] then Hand[src][1].endsAt = nil end
                refund(src, j)
                return { ok = true }
            end
        end
    end
    return { ok = false, error = Lp(src, 'no_job') }
end)

BSB.RegisterCallback('crafting:take', function(src, stationId, item, amount)
    local v, err = Craft.StationAt(src, stationId)
    if not v then return { ok = false, error = Lp(src, err) } end
    local cid = storageId(v.id)
    if item == '*' then
        for _, e in ipairs(INV:ContainerContents(cid)) do INV:MoveFromContainer(src, e.item, e.amount, cid) end
        return { ok = true }
    end
    amount = math.max(1, math.floor(tonumber(amount) or INV:ContainerCount(cid, item)))
    if INV:MoveFromContainer(src, tostring(item), amount, cid) then return { ok = true } end
    return { ok = false, error = Lp(src, 'no_room') }
end)

BSB.RegisterCallback('crafting:openStorage', function(src, stationId)
    local v, err = Craft.StationAt(src, stationId)
    if not v then return { ok = false, error = Lp(src, err) } end
    INV:OpenContainerFor(src, storageId(v.id))
    return { ok = true }
end)

-- Stations near the player, for the client's interaction zones.
BSB.RegisterCallback('crafting:nearStations', function(src)
    local c = pedPos(src)
    if not c then return { ok = false } end
    local out = {}
    for _, v in ipairs(Craft.PiecesNear(c.x, c.y, c.z, 60.0)) do
        if v.b then out[#out + 1] = { id = v.id, type = v.p, x = v.x, y = v.y, z = v.z, h = v.h,
            label = Crafting.Stations[v.p].label, mine = Craft.CanUse(src, v), busy = St[tonumber(v.id)] and #(St[tonumber(v.id)].queue) > 0 or false } end
    end
    return { ok = true, list = out }
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- A station that is torn down gives its queue back to whoever queued it.
AddEventHandler('bs:building:pieceRemoved', function(id, defId)
    id = tonumber(id)
    local s = St[id]
    if not s then return end
    for _, j in ipairs(s.queue or {}) do
        local owner = srcByChar(j.owner)
        if owner then refund(owner, j)
        else
            MySQL.insert('INSERT INTO `bs_craft_refunds` (`char_id`,`items`) VALUES (?,?)', { j.owner, json.encode(j.cost or {}) })
        end
    end
    St[id] = nil
    MySQL.update('DELETE FROM `bs_craft_stations` WHERE `piece_id` = ?', { id })
end)

-- Hand jobs are refunded on logout so nothing is lost mid-craft.
AddEventHandler('playerDropped', function()
    local src = source
    local q = Hand[src]
    Hand[src], lastQueue[src] = nil, nil
    if not q or #q == 0 then return end
    local cid
    local p = player(src)
    cid = p and p.charId
    local items = {}
    for _, j in ipairs(q) do for _, t in ipairs(j.cost or {}) do items[#items + 1] = t end end
    if cid then MySQL.insert('INSERT INTO `bs_craft_refunds` (`char_id`,`items`) VALUES (?,?)', { cid, json.encode(items) }) end
end)

-- Pending refunds are paid out on spawn.
AddEventHandler('bs:hook:player:spawned', function(p)
    if not p or not p.source or not p.charId then return end
    local rows = MySQL.query.await('SELECT `id`,`items` FROM `bs_craft_refunds` WHERE `char_id` = ?', { p.charId }) or {}
    for _, row in ipairs(rows) do
        MySQL.update.await('DELETE FROM `bs_craft_refunds` WHERE `id` = ?', { row.id })
        local ok, items = pcall(json.decode, row.items or '[]')
        for _, t in ipairs(ok and items or {}) do Craft.GiveOrPend(p.source, t.item, t.amount) end
    end
end)

CreateThread(function()
    loadOverrides()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    Wait(2500)
    local rows = MySQL.query.await('SELECT `piece_id`,`type`,`data` FROM `bs_craft_stations`') or {}
    for _, row in ipairs(rows) do
        local ok, d = pcall(json.decode, row.data or '{}')
        d = ok and d or {}
        local id = tonumber(row.piece_id)
        St[id] = { type = row.type, queue = d.queue or {}, burn = d.burn or {}, crop = d.crop }
        registerStorage(id, Crafting.Stations[row.type] and Crafting.Stations[row.type].label)
    end
    dbReady = true
    print(('^2[BeyondSurvival]^7 (crafting) %d station(s) loaded'):format(#rows))
end)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

-- Station defs for bs_building's RegisterPlaceable.
exports('StationDefs', function()
    local out = {}
    for id, d in pairs(Crafting.Stations) do
        out[id] = { id = id, cat = 'utility', label = d.label, station = id, models = d.models,
            cost = d.cost, health = d.health, size = d.size, support = 'any' }
    end
    return out
end)
exports('Recipes', function() return Craft.Recipes() end)
-- Recipe cost that makes an item, for the recycler (first recipe found, by hand preferred).
exports('RecipeFor', function(item)
    local best
    for _, r in pairs(Craft.Recipes()) do
        if r.result.item == item and (not best or not r.station) then best = r end
    end
    return best and { cost = best.cost, amount = best.result.amount or 1 } or nil
end)
exports('SkillLevel', function(src) return Craft.SkillLevel(src) end)

exports.bs_core:RegisterModule('crafting', { side = 'server', version = '1.0.0' })
