-- bs_crafting server: gathering (skinning, foraging, wreck salvage), hand dismantling, food effects, traps and farming.

local S = Crafting.Settings
local INV = exports.bs_inventory
local notify = Craft.Notify

local function hasAny(src, list)
    for _, t in ipairs(list or {}) do if INV:CountItem(src, t) > 0 then return t end end
    return nil
end

local function giveRolled(src, rolled)
    local out = {}
    for item, n in pairs(rolled) do
        Craft.GiveOrPend(src, item, n)
        out[#out + 1] = { item = item, amount = n, label = Craft.Label(item, src) }
    end
    return out
end

local function safeAt(x, y)
    if GetResourceState('bs_zombies') ~= 'started' then return false end
    local ok, inside = pcall(function() return exports.bs_zombies:InSafeZone(x, y, 0.0) end)
    return ok and inside
end

-- Timed actions: start hands out a token, finish checks the time really passed and the player did not wander off.
local tokens = {}   -- [src] = { kind, data, at, ms, pos }
local function begin(src, kind, ms, data)
    local c = Craft.PedPos(src)
    tokens[src] = { kind = kind, data = data, at = GetGameTimer(), ms = ms, pos = c }
    return { ok = true, ms = ms }
end
local function complete(src, kind)
    local t = tokens[src]
    tokens[src] = nil
    if not t or t.kind ~= kind then return nil end
    if GetGameTimer() - t.at < t.ms - 600 then return nil end
    local c = Craft.PedPos(src)
    if not c or not t.pos or #(c - t.pos) > 3.0 then return nil end
    return t.data
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

local skinned = {}       -- [key] = os.time
-- Animal yield: F1 multiplier plus up to +30% from the hunting skill tree.
local function huntMult(src)
    local lv = 0
    if GetResourceState('bs_skills') == 'started' then
        local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel(src, S.huntSkill or 'survival') end)
        lv = (ok and tonumber(v)) or 0
    end
    return (tonumber(S.animalYieldMult) or 1.0) * (1.0 + math.min(0.3, lv * 0.015))
end

BSB.RegisterCallback('crafting:skinStart', function(src, kind, key, model)
    if not hasAny(src, Crafting.SkinTool) then return { ok = false, error = Lp(src, 'need_knife') } end
    key = tostring(key or '')
    if kind == 'zombie' then
        if not S.skinZombies then return { ok = false, error = Lp(src, 'disabled') } end
    elseif kind == 'animal' then
        if not Crafting.Animals[tostring(model)] then return { ok = false, error = Lp(src, 'cannot_skin') } end
        -- Networked carcass: the server checks the model, that it is dead and that you are next to it.
        local net = tonumber(key:match('^n(%d+)$'))
        if net then
            local ent = NetworkGetEntityFromNetworkId(net)
            if not ent or ent == 0 or not DoesEntityExist(ent) then return { ok = false, error = Lp(src, 'cannot_skin') } end
            if GetEntityModel(ent) ~= joaat(tostring(model)) or GetEntityHealth(ent) > 0 then return { ok = false, error = Lp(src, 'cannot_skin') } end
            local c = Craft.PedPos(src)
            if not c or #(c - GetEntityCoords(ent)) > (S.skinRange or 4.0) then return { ok = false, error = Lp(src, 'too_far') } end
        end
    else return { ok = false } end
    if key == '' or skinned[kind .. key] then return { ok = false, error = Lp(src, 'already_skinned') } end
    return begin(src, 'skin', S.skinMs or 6000, { kind = kind, key = key, model = tostring(model) })
end)

BSB.RegisterCallback('crafting:skinFinish', function(src)
    local d = complete(src, 'skin')
    if not d then return { ok = false, error = Lp(src, 'interrupted') } end
    if skinned[d.kind .. d.key] then return { ok = false, error = Lp(src, 'already_skinned') } end
    skinned[d.kind .. d.key] = os.time()
    local list = d.kind == 'zombie' and Crafting.ZombieSkin or Crafting.Animals[d.model]
    local got = giveRolled(src, Craft.Roll(list, d.kind == 'animal' and huntMult(src) or 1.0))
    Craft.AddXP(src, 4)
    -- Hunting XP (character + survival skill), only for carcasses the server could check.
    if d.kind == 'animal' and d.key:match('^n%d+$') then
        local f = (Crafting.HuntReward or {})[d.model] or 1.0
        pcall(function() exports.bs_core:AwardAction(src, 'animal_skinned', f) end)
    end
    -- faction jobs count this (bs_jobs)
    TriggerEvent('bs:jobs:event', src, d.kind == 'zombie' and 'skin_zombie' or 'skin_animal', 1)
    return { ok = true, items = got }
end)

--------------------------------------------------------------------------------
-- Foraging
--------------------------------------------------------------------------------

local picked = {}   -- [cellKey] = os.time

BSB.RegisterCallback('crafting:forageStart', function(src, x, y)
    local c = Craft.PedPos(src)
    x, y = tonumber(x), tonumber(y)
    if not c or not x or #(vector2(c.x, c.y) - vector2(x, y)) > 4.0 then return { ok = false } end
    local key = ('%d:%d'):format(math.floor(x), math.floor(y))
    if picked[key] and os.time() - picked[key] < (S.forageCooldown or 900) then
        return { ok = false, error = Lp(src, 'picked_clean') }
    end
    return begin(src, 'forage', S.forageMs or 3500, { key = key })
end)

BSB.RegisterCallback('crafting:forageFinish', function(src)
    local d = complete(src, 'forage')
    if not d then return { ok = false, error = Lp(src, 'interrupted') } end
    if picked[d.key] and os.time() - picked[d.key] < (S.forageCooldown or 900) then return { ok = false, error = Lp(src, 'picked_clean') } end
    picked[d.key] = os.time()
    local got = giveRolled(src, Craft.Roll(Crafting.Forage))
    Craft.AddXP(src, 2)
    TriggerEvent('bs:jobs:event', src, 'forage', 1)
    return { ok = true, items = got }
end)

--------------------------------------------------------------------------------
-- Wreck salvage
--------------------------------------------------------------------------------

BSB.RegisterCallback('crafting:salvageStart', function(src, plate)
    if INV:CountItem(src, 'wrench') < 1 then return { ok = false, error = Lp(src, 'need_wrench') } end
    if GetResourceState('bs_vehicles') ~= 'started' then return { ok = false } end
    local ok, near = pcall(function() return exports.bs_vehicles:IsWreckNear(src, plate) end)
    if not (ok and near) then return { ok = false, error = Lp(src, 'not_a_wreck') } end
    return begin(src, 'salvage', S.salvageMs or 20000, { plate = tostring(plate) })
end)

BSB.RegisterCallback('crafting:salvageFinish', function(src)
    local d = complete(src, 'salvage')
    if not d then return { ok = false, error = Lp(src, 'interrupted') } end
    local ok, done = pcall(function() return exports.bs_vehicles:SalvageWreck(src, d.plate) end)
    if not (ok and done) then return { ok = false, error = Lp(src, 'not_a_wreck') } end
    local bonus = 1.0 + math.min(0.15, Craft.SkillLevel(src) * 0.01)
    local got = giveRolled(src, Craft.Roll(Crafting.Salvage, bonus))
    Craft.AddXP(src, 12)
    Craft.Log(src, 'salvage', 'wreck ' .. d.plate)
    TriggerEvent('bs:jobs:event', src, 'salvage', 1)
    if GetResourceState('bs_zombies') == 'started' then
        local c = Craft.PedPos(src)
        pcall(function() exports.bs_zombies:EventNoise(c.x, c.y, c.z, 90.0, 'salvage') end)
    end
    return { ok = true, items = got }
end)

--------------------------------------------------------------------------------
-- Hand dismantling (25% of the recycler, needs the right tool)
--------------------------------------------------------------------------------

local function recycler() return GetResourceState('bs_recycler') == 'started' end

function Craft.DismantleList(src)
    if not recycler() then return {} end
    local ok, list = pcall(function() return exports.bs_recycler:DismantleCandidates(src) end)
    return ok and list or {}
end

BSB.RegisterCallback('crafting:dismantleStart', function(src, item)
    if not recycler() then return { ok = false } end
    item = tostring(item)
    if INV:CountItem(src, item) < 1 then return { ok = false, error = Lp(src, 'missing', { item = Craft.Label(item, src) }) } end
    local ok, tool = pcall(function() return exports.bs_recycler:ToolFor(item) end)
    if not ok or not tool then return { ok = false, error = Lp(src, 'cannot_dismantle') } end
    if INV:CountItem(src, tool) < 1 then return { ok = false, error = Lp(src, 'need_item', { item = Craft.Label(tool, src) }) } end
    local okS, secs = pcall(function() return exports.bs_recycler:DismantleSeconds() end)
    return begin(src, 'dismantle', ((okS and secs) or 10) * 1000, { item = item })
end)

BSB.RegisterCallback('crafting:dismantleFinish', function(src)
    local d = complete(src, 'dismantle')
    if not d then return { ok = false, error = Lp(src, 'interrupted') } end
    if not INV:RemoveItem(src, d.item, 1) then return { ok = false } end
    local ok, out = pcall(function() return exports.bs_recycler:HandYield(src, d.item) end)
    local got = giveRolled(src, ok and out or {})
    Craft.AddXP(src, 2)
    Craft.Log(src, 'dismantle', d.item)
    return { ok = true, items = got }
end)

--------------------------------------------------------------------------------
-- Items used from the bag
--------------------------------------------------------------------------------

local sickChance = { raw_meat = 0.6, dirty_water = 0.5, raw_fish = 0.4 }

AddEventHandler('bs:crafting:useItem', function(src, item, slot)
    if sickChance[item] then
        if math.random() < sickChance[item] then
            -- bs_medical owns the illness; this only says it happened.
            TriggerEvent('bs:medical:sicken', src, item == 'dirty_water' and 'water' or 'food')
            notify(src, 'warn', 'feel_sick')
        end
    elseif item == 'meat_stew' or item == 'veggie_stew' then
        TriggerClientEvent('bs:crafting:stewBonus', src, Crafting.StewBonus)
    elseif Crafting.Traps[item] then
        local c = Craft.PedPos(src)
        if c and safeAt(c.x, c.y) then return notify(src, 'warn', 'no_traps_safezone') end
        TriggerClientEvent('bs:crafting:placeTrap', src, item)
    end
end)

--------------------------------------------------------------------------------
-- Traps
--------------------------------------------------------------------------------

local Traps = {}    -- [id] = { id, kind, owner, x, y, z, h, until }
local trapSeq = 0

local function trapView() local out = {} for _, t in pairs(Traps) do out[#out + 1] = t end return out end
local function pushTraps(target) TriggerClientEvent('bs:crafting:traps', target or -1, trapView()) end

local function ownerCount(cid, kind)
    local n = 0
    for _, t in pairs(Traps) do if t.owner == cid and t.kind == kind then n = n + 1 end end
    return n
end

BSB.RegisterCallback('crafting:placeTrap', function(src, kind, x, y, z, h)
    local def = Crafting.Traps[tostring(kind)]
    local p = exports.bs_core:GetPlayer(src)
    if not def or not p then return { ok = false } end
    local c = Craft.PedPos(src)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or #(c - vector3(x, y, z)) > 4.0 then return { ok = false, error = Lp(src, 'too_far') } end
    if safeAt(x, y) then return { ok = false, error = Lp(src, 'no_traps_safezone') } end
    if def.limit and ownerCount(p.charId, kind) >= def.limit then return { ok = false, error = Lp(src, 'trap_limit') } end
    if not INV:RemoveItem(src, kind, 1) then return { ok = false } end

    if kind == 'zombie_bait' then
        trapSeq = trapSeq + 1
        local id = 'bait' .. trapSeq
        Traps[id] = { id = id, kind = kind, owner = p.charId, x = x, y = y, z = z, h = tonumber(h) or 0.0, temp = true }
        pushTraps()
        CreateThread(function()
            local left = def.lifeSeconds or 180
            while left > 0 and Traps[id] do
                if GetResourceState('bs_zombies') == 'started' then
                    pcall(function() exports.bs_zombies:EventNoise(x, y, z, def.noise or 120.0, 'bait') end)
                end
                Wait((def.lureEvery or 15) * 1000)
                left = left - (def.lureEvery or 15)
            end
            Traps[id] = nil
            pushTraps()
        end)
    else
        local id = MySQL.insert.await('INSERT INTO `bs_craft_traps` (`kind`,`owner_char`,`x`,`y`,`z`,`h`) VALUES (?,?,?,?,?,?)',
            { kind, p.charId, x, y, z, tonumber(h) or 0.0 })
        if not id then return { ok = false } end
        Traps[tostring(id)] = { id = tostring(id), kind = kind, owner = p.charId, x = x, y = y, z = z, h = tonumber(h) or 0.0 }
        pushTraps()
    end
    Craft.Log(src, 'trap', ('%s at %.1f %.1f'):format(kind, x, y))
    return { ok = true }
end)

local lastAlarm = {}

-- A client saw something step on a trap. Victims report themselves; zombies are reported by whoever is near.
RegisterNetEvent('bs:crafting:trapHit', function(id, what, netId)
    local src = source
    local t = Traps[tostring(id)]
    if not t then return end
    local c = Craft.PedPos(src)
    if not c or #(c - vector3(t.x, t.y, t.z)) > 60.0 then return end
    local def = Crafting.Traps[t.kind]

    if t.kind == 'bear_trap' then
        Traps[t.id] = nil
        MySQL.update('DELETE FROM `bs_craft_traps` WHERE `id` = ?', { tonumber(t.id) })
        pushTraps()
        if what == 'self' then
            if #(c - vector3(t.x, t.y, t.z)) > 3.0 then return end
            TriggerClientEvent('bs:crafting:trapped', src, def.damage or 45, def.holdMs or 10000)
        else
            TriggerClientEvent('bs:crafting:trapSnap', -1, tonumber(netId), t.x, t.y, t.z, def.holdMs or 10000)
        end
    elseif t.kind == 'tripwire_alarm' then
        if lastAlarm[t.id] and os.time() - lastAlarm[t.id] < 20 then return end
        lastAlarm[t.id] = os.time()
        TriggerClientEvent('bs:crafting:alarm', -1, t.x, t.y, t.z)
        for _, pid in ipairs(GetPlayers()) do
            local p = exports.bs_core:GetPlayer(tonumber(pid))
            if p and p.charId == t.owner then notify(tonumber(pid), 'warn', 'tripwire_alert') end
        end
        if GetResourceState('bs_zombies') == 'started' then
            pcall(function() exports.bs_zombies:EventNoise(t.x, t.y, t.z, def.noise or 80.0, 'alarm') end)
        end
    end
end)

BSB.RegisterCallback('crafting:pickupTrap', function(src, id)
    local t = Traps[tostring(id)]
    local p = exports.bs_core:GetPlayer(src)
    if not t or not p or t.temp then return { ok = false } end
    if t.owner ~= p.charId then return { ok = false, error = Lp(src, 'not_yours') } end
    if #(Craft.PedPos(src) - vector3(t.x, t.y, t.z)) > 3.0 then return { ok = false, error = Lp(src, 'too_far') } end
    Traps[t.id] = nil
    MySQL.update('DELETE FROM `bs_craft_traps` WHERE `id` = ?', { tonumber(t.id) })
    pushTraps()
    Craft.GiveOrPend(src, t.kind, 1)
    return { ok = true }
end)

AddEventHandler('bs:hook:player:spawned', function(p) if p and p.source then pushTraps(p.source) end end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    Wait(3000)
    for _, row in ipairs(MySQL.query.await('SELECT * FROM `bs_craft_traps`') or {}) do
        Traps[tostring(row.id)] = { id = tostring(row.id), kind = row.kind, owner = tonumber(row.owner_char),
            x = row.x, y = row.y, z = row.z, h = row.h }
    end
    pushTraps()
end)

--------------------------------------------------------------------------------
-- Farming (a farm_plot station). Growth runs in real time once the plot is both watered and fertilized.
--------------------------------------------------------------------------------

local function growSeconds() return math.max(60, (S.farmGrowMinutes or 90) * 60) end

local function progress(crop)
    if not crop then return 0 end
    if not (crop.water and crop.fert) or not crop.growFrom then return 0 end
    return math.min(1.0, (os.time() - crop.growFrom) / growSeconds())
end

function Craft.FarmView(src, id)
    local s = Craft.Stations[id]
    local crop = s and s.crop
    local seeds = {}
    for seed, c in pairs(Crafting.Crops) do
        seeds[#seeds + 1] = { item = seed, label = Craft.Label(seed, src), crop = c.label, have = INV:CountItem(src, seed) }
    end
    return {
        crop = crop and { seed = crop.seed, label = Crafting.Crops[crop.seed] and Crafting.Crops[crop.seed].label or crop.seed,
            water = crop.water or false, fert = crop.fert or false, progress = progress(crop),
            left = (crop.water and crop.fert and crop.growFrom) and math.max(0, crop.growFrom + growSeconds() - os.time()) or nil } or nil,
        seeds = seeds,
        haveWater = INV:CountItem(src, 'water_bottle') + INV:CountItem(src, 'dirty_water'),
        haveFert = INV:CountItem(src, 'fertilizer') + INV:CountItem(src, 'rotten_flesh'),
    }
end

BSB.RegisterCallback('crafting:farm', function(src, stationId, action, arg)
    local v, err = Craft.StationAt(src, stationId)
    if not v then return { ok = false, error = Lp(src, err) } end
    if v.p ~= 'farm_plot' then return { ok = false } end
    local id = tonumber(v.id)
    local s = Craft.StationState(id, v.p)

    if action == 'plant' then
        if s.crop then return { ok = false, error = Lp(src, 'plot_busy') } end
        if not Crafting.Crops[tostring(arg)] then return { ok = false } end
        if not INV:RemoveItem(src, tostring(arg), 1) then return { ok = false, error = Lp(src, 'missing', { item = Craft.Label(arg, src) }) } end
        s.crop = { seed = tostring(arg), planted = os.time() }
    elseif action == 'water' or action == 'fert' then
        if not s.crop then return { ok = false, error = Lp(src, 'plot_empty') } end
        local list = action == 'water' and { 'water_bottle', 'dirty_water' } or { 'fertilizer', 'rotten_flesh' }
        if s.crop[action] then return { ok = false, error = Lp(src, 'already_done') } end
        local used
        for _, it in ipairs(list) do if INV:RemoveItem(src, it, 1) then used = it break end end
        if not used then return { ok = false, error = Lp(src, 'missing', { item = Craft.Label(list[1], src) }) } end
        s.crop[action] = true
        if s.crop.water and s.crop.fert then s.crop.growFrom = os.time() end
    elseif action == 'harvest' then
        if not s.crop or progress(s.crop) < 1.0 then return { ok = false, error = Lp(src, 'not_ripe') } end
        local got = giveRolled(src, Craft.Roll(Crafting.Crops[s.crop.seed].yield, 1.0 + math.min(0.3, Craft.SkillLevel(src) * 0.015)))
        s.crop = nil
        Craft.AddXP(src, 10)
        TriggerEvent('bs:jobs:event', src, 'harvest', 1)
        Craft.SaveStation(id)
        TriggerClientEvent('bs:crafting:farmChanged', -1, id, nil)
        return { ok = true, items = got }
    else
        return { ok = false }
    end
    Craft.SaveStation(id)
    TriggerClientEvent('bs:crafting:farmChanged', -1, id, { seed = s.crop.seed, stage = progress(s.crop) })
    return { ok = true }
end)

-- Crop stages for nearby plots, so clients can draw them.
BSB.RegisterCallback('crafting:crops', function(src)
    local c = Craft.PedPos(src)
    if not c then return { ok = false } end
    local out = {}
    for _, v in ipairs(Craft.PiecesNear(c.x, c.y, c.z, 80.0)) do
        local s = Craft.Stations[tonumber(v.id)]
        if v.p == 'farm_plot' and s and s.crop then
            out[#out + 1] = { id = v.id, x = v.x, y = v.y, z = v.z, stage = progress(s.crop) }
        end
    end
    return { ok = true, list = out }
end)

AddEventHandler('playerDropped', function() tokens[source] = nil end)
