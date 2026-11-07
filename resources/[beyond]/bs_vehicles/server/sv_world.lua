-- bs_vehicles - world vehicles (random road spawns), missing parts, wrecks and lockpicking

local W = Vehicles.World or {}
local R = VehReg

local owed = {}          -- [category] = how many still to place this uptime
local pending = {}       -- [reqId] = { src, category, model, at }
local taken = {}         -- { {x, y}, ... } positions of saved vehicles, so spawns do not stack
local nextReq = 0
local deck = {}          -- shuffled anchor indexes; each anchor is used once per pass
local worldPaused, managingWorld = false, false

-- Next anchor from a shuffled deck, so N spawns cover N different anchors (no repeats until all are used)
local function nextAnchor()
    local list = W.anchors
    if #deck == 0 then
        for i = 1, #list do deck[i] = i end
        for i = #deck, 2, -1 do
            local j = math.random(i)
            deck[i], deck[j] = deck[j], deck[i]
        end
    end
    return list[table.remove(deck)] or list[1]
end

local function now() return os.time() end

-- "model:weight,model:weight" to { {model, weight}, ... }
local function parsePool(text)
    local out = {}
    for chunk in tostring(text or ''):gmatch('[^,]+') do
        local model, weight = chunk:match('^%s*([%w_]+)%s*:?%s*(%d*)%s*$')
        if model then out[#out + 1] = { model = model:lower(), weight = math.max(1, tonumber(weight) or 1) } end
    end
    return out
end

local function pickWeighted(list)
    local total = 0
    for _, e in ipairs(list) do total = total + e.weight end
    if total <= 0 then return nil end
    local roll = math.random() * total
    for _, e in ipairs(list) do
        roll = roll - e.weight
        if roll <= 0 then return e end
    end
    return list[#list]
end

local function safeAt(x, y, pad)
    if GetResourceState('bs_zombies') ~= 'started' then return false end
    local ok, inside = pcall(function() return exports.bs_zombies:InSafeZone(x, y, pad or 0.0) end)
    return ok and inside == true
end

-- Counting what is owed (boot only)

-- Counts live world cars per category and what is owed; also rebuilds the "taken" positions.
local function computeOwed()
    owed = {}
    taken = {}
    local rows = exports.oxmysql:query_async([[
        SELECT `category`, COUNT(*) AS `n` FROM `bs_vehicles`
        WHERE `world_spawn` = 1 AND `scrapped` = 0 AND `wrecked_at` IS NULL
        GROUP BY `category`
    ]]) or {}
    local have = {}
    for _, row in ipairs(rows) do have[row.category or ''] = tonumber(row.n) or 0 end

    local total = 0
    for category, max in pairs(W.max or {}) do
        local want = math.max(0, math.floor(tonumber(max) or 0) - (have[category] or 0))
        if #parsePool((W.pool or {})[category]) == 0 then want = 0 end
        owed[category] = want
        total = total + want
    end

    local positions = exports.oxmysql:query_async([[
        SELECT `position` FROM `bs_vehicles` WHERE `stored` = 0 AND `position` IS NOT NULL AND `scrapped` = 0
    ]]) or {}
    for _, row in ipairs(positions) do
        local ok, pos = pcall(json.decode, row.position)
        if ok and type(pos) == 'table' and pos.x then taken[#taken + 1] = { pos.x, pos.y } end
    end
    return total
end

CreateThread(function()
    -- Migrations run in bs_core on start; give them a moment.
    Wait(8000)
    if not W.enabled then return end
    local total = computeOwed()
    print(('^2[BeyondSurvival]^7 (vehicles) world spawns owed this restart: %d'):format(total))
end)

local function totalOwed()
    local n = 0
    for _, v in pairs(owed) do n = n + v end
    return n
end

-- Asking clients for spots

CreateThread(function()
    while true do
        local spreading = W.spread and type(W.anchors) == 'table' and #W.anchors > 0
        Wait(math.max(spreading and 1500 or 5000, tonumber(spreading and W.spreadEvery or W.askEvery) or 20000))

        if W.enabled and not worldPaused and not managingWorld and totalOwed() > 0 then
            -- Expire unanswered requests.
            local t = GetGameTimer()
            for id, req in pairs(pending) do
                if t - req.at > 20000 then pending[id] = nil end
            end

            local players = GetPlayers()
            -- Aim at an anchor spread over the map, not at the player (cars would pile up where players are).
            local aim
            if W.spread and type(W.anchors) == 'table' and #W.anchors > 0 then
                local a = nextAnchor()
                local jit = tonumber(W.anchorJitter) or 700.0
                aim = { x = a[1] + (math.random() * 2 - 1) * jit, y = a[2] + (math.random() * 2 - 1) * jit, z = a[3] or 40.0 }
            end
            if #players > 0 then
                local src = tonumber(players[math.random(#players)])

                -- Category weighted by how many it is still owed.
                local cats = {}
                for category, n in pairs(owed) do
                    if n > 0 then cats[#cats + 1] = { model = category, weight = n } end
                end
                local category = pickWeighted(cats)
                local entry = category and pickWeighted(parsePool((W.pool or {})[category.model]))

                if entry and src and GetPlayerPed(src) ~= 0 then
                    nextReq = nextReq + 1
                    pending[nextReq] = { src = src, category = category.model, model = entry.model, at = t, aim = aim }
                    TriggerClientEvent('bs:vehicles:findSpot', src, nextReq, entry.model,
                        W.ringMin or 260.0, W.ringMax or 650.0, aim and aim.x, aim and aim.y, aim and aim.z)
                end
            end
        end
    end
end)

RegisterNetEvent('bs:vehicles:spot', function(reqId, x, y, z, h)
    local src = source
    if worldPaused or managingWorld then return end
    reqId = tonumber(reqId) or -1
    local req = pending[reqId]
    if not req or req.src ~= src then return end
    pending[reqId] = nil

    x, y, z, h = tonumber(x), tonumber(y), tonumber(z), tonumber(h) or 0.0
    if not x or not y or not z then return end
    if (owed[req.category] or 0) <= 0 then return end

    if req.aim then
        -- Aimed request: the spot must be near the aimed point, not near the asker.
        if #(vector2(req.aim.x, req.aim.y) - vector2(x, y)) > (tonumber(W.anchorSnap) or 250.0) + 50.0 then return end
    else
        -- The asked client must actually be near the spot it found.
        local me = GetEntityCoords(GetPlayerPed(src))
        local ringMax = (W.ringMax or 650.0) + 150.0
        if #(vector2(me.x, me.y) - vector2(x, y)) > ringMax then return end
    end

    -- Not near anybody.
    local clear = W.playerClear or 180.0
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 then
            local at = GetEntityCoords(ped)
            if #(vector2(at.x, at.y) - vector2(x, y)) < clear then return end
        end
    end

    -- Not in a safezone, outpost or faction flag.
    if safeAt(x, y, W.safePad or 40.0) then return end

    -- Not on top of another saved vehicle.
    local gap = (W.vehicleClear or 25.0) ^ 2
    for _, p in ipairs(taken) do
        local dx, dy = p[1] - x, p[2] - y
        if dx * dx + dy * dy < gap then return end
    end

    -- Worn but not failing, same rule as a found car
    local parts = {}
    for _, part in ipairs(Vehicles.Parts) do
        parts[part.id] = math.random(math.floor((part.warn or 50) + 4), 96) + 0.0
    end
    local missing = {}
    for _, m in ipairs(Vehicles.Missing or {}) do missing[#missing + 1] = m.id end

    local plate = R.generatePlate()
    if not plate then return end
    local lo = math.max(0, math.floor(tonumber(W.fuelMin) or 0))
    local hi = math.max(lo, math.floor(tonumber(W.fuelMax) or 50))
    local fuel = math.random(lo, hi) + 0.0

    local id = exports.oxmysql:insert_async([[
        INSERT INTO `bs_vehicles` (`plate`, `model`, `fuel`, `parts`, `missing`, `position`, `locked`, `world_spawn`, `category`)
        VALUES (?, ?, ?, ?, ?, ?, 0, 1, ?)
    ]], { plate, req.model, fuel, json.encode(parts), json.encode(missing),
          json.encode({ x = x, y = y, z = z, h = h }), req.category })
    if not id then return end

    owed[req.category] = owed[req.category] - 1
    taken[#taken + 1] = { x, y }
end)

local WORLD_SCOPES = {
    unclaimed = 'v.`owner_character_id` IS NULL AND NOT EXISTS (SELECT 1 FROM `bs_vehicle_keys` k WHERE k.`vehicle_id` = v.`id`)',
    claimed = '(v.`owner_character_id` IS NOT NULL OR EXISTS (SELECT 1 FROM `bs_vehicle_keys` k WHERE k.`vehicle_id` = v.`id`))',
    all = '1 = 1',
}

local function worldRows(scope)
    local filter = WORLD_SCOPES[scope]
    if not filter then return nil end
    local rows = exports.oxmysql:query_async('SELECT v.`id`, v.`plate` FROM `bs_vehicles` v WHERE v.`stored` = 0 AND v.`scrapped` = 0 AND (' .. filter .. ')') or {}
    if scope ~= 'claimed' then
        local saved = {}
        for _, row in ipairs(exports.oxmysql:query_async('SELECT `plate` FROM `bs_vehicles`') or {}) do saved[row.plate] = true end
        for _, entity in ipairs(GetAllVehicles()) do
            local plate = GetVehicleNumberPlateText(entity):gsub('^%s+', ''):gsub('%s+$', '')
            if not saved[plate] and GetEntityRoutingBucket(entity) == 0 then
                rows[#rows + 1] = { plate = plate, entity = entity }
            end
        end
    end
    return rows
end

exports('PreviewWorldCars', function(scope)
    local rows = worldRows(scope)
    return rows and #rows or nil
end)

exports('ManageWorldCars', function(scope, operation)
    if not WORLD_SCOPES[scope] or (operation ~= 'wipe' and operation ~= 'repopulate') then return { ok = false, error = 'Invalid vehicle operation' } end
    if managingWorld then return { ok = false, error = 'Another vehicle operation is running' } end
    if operation == 'repopulate' and not W.enabled then return { ok = false, error = 'Enable world vehicle spawning first' } end
    managingWorld = true
    local ok, result = pcall(function()
        pending = {}
        local plates, selected = {}, {}
        for _, row in ipairs(worldRows(scope)) do
            -- Recheck ownership in the DELETE so a newly claimed car is not swept as unclaimed.
            local changed = row.entity and 1 or exports.oxmysql:update_async('DELETE v FROM `bs_vehicles` v WHERE v.`id` = ? AND v.`stored` = 0 AND v.`scrapped` = 0 AND (' .. WORLD_SCOPES[scope] .. ')', { row.id })
            if tonumber(changed) and changed > 0 then
                if row.entity then DeleteEntity(row.entity)
                elseif R.forget then R.forget(row.plate) else R.registry[row.plate], R.dirty[row.plate] = nil, nil end
                plates[#plates + 1], selected[row.plate] = row.plate, true
            end
        end
        for _, vehicle in ipairs(GetAllVehicles()) do
            local plate = GetVehicleNumberPlateText(vehicle):gsub('^%s+', ''):gsub('%s+$', '')
            if selected[plate] then DeleteEntity(vehicle) end
        end
        if #plates > 0 then TriggerClientEvent('bs:vehicles:removed', -1, plates) end
        deck = {}
        local missing = computeOwed()
        worldPaused = operation == 'wipe'
        return { ok = true, removed = #plates, queued = worldPaused and 0 or missing, paused = worldPaused }
    end)
    managingWorld = false
    if not ok then error(result) end
    return result
end)

-- Fitting a missing part

local function missingDef(id)
    for _, m in ipairs(Vehicles.Missing or {}) do
        if m.id == id then return m end
    end
end

BSB.RegisterCallback('vehicles:fit', function(src, plate, partId)
    if not R.nearPlate(src, plate, 4.0) then return { ok = false, error = Lp(src, 'srv.not_at') } end
    local record = R.get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end
    if record.scrapped or record.wreckedAt then return { ok = false, error = Lp(src, 'srv.nothing_fit') } end

    local def = missingDef(partId)
    if not def then return { ok = false, error = Lp(src, 'srv.unknown_part') } end
    if not record.missing[def.id] then return { ok = false, error = Lp(src, 'srv.has_part', { part = VehPartName(src, def) }) } end

    if exports.bs_inventory:CountItem(src, def.item) < 1 then
        local item = exports.bs_inventory:GetItem(def.item)
        return { ok = false, error = Lp(src, 'srv.need_part', { part = VehPartName(src, def) }) }
    end
    -- A battery keeps its own charge and capacity, so take the best one and carry its numbers over.
    local meta
    if def.id == 'battery' and VehBatteryBestSlot then
        local slot
        slot, meta = VehBatteryBestSlot(src)
        if not slot or not exports.bs_inventory:RemoveSlot(src, slot, def.item) then return { ok = false, error = Lp(src, 'srv.need_the_part') } end
    elseif not exports.bs_inventory:RemoveItem(src, def.item, 1) then
        return { ok = false, error = Lp(src, 'srv.need_the_part') }
    end

    record.missing[def.id] = nil
    if def.id == 'battery' then
        record.parts.batteryCap = meta and meta.cap or 100.0
        record.parts.battery = meta and meta.charge or 100.0
    end
    R.touch(record.plate)
    R.save(record)

    VehRepaired(src)
    return { ok = true, label = def.label, vehicle = R.payload(record, R.charIdOf(src)) }
end)

-- Wrecks: a vehicle that exploded stays as a burnt shell until Vehicles.World.wreckMinutes runs out

local function entityByPlate(plate)
    for _, veh in ipairs(GetAllVehicles()) do
        if R.clean(GetVehicleNumberPlateText(veh)) == plate then return veh end
    end
end

RegisterNetEvent('bs:vehicles:destroyed', function(plate)
    local src = source
    plate = R.clean(plate)
    if not plate then return end

    local record = R.get(plate)
    if not record or record.wreckedAt or record.scrapped then return end

    -- The reporter has to be near the burning car.
    local veh = entityByPlate(plate)
    if not veh then return end
    local at = GetEntityCoords(veh)
    if #(GetEntityCoords(GetPlayerPed(src)) - at) > 250.0 then return end

    record.wreckedAt = now()
    record.owner = nil
    record.locked = false
    record.fuel = 0.0
    record.position = { x = at.x, y = at.y, z = at.z, h = GetEntityHeading(veh) }
    R.touch(plate)
    R.save(record)

    exports.oxmysql:execute_async('DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    record.keys = {}

    TriggerClientEvent('bs:vehicles:lockState', -1, plate, false)
    TriggerClientEvent('bs:vehicles:wrecked', -1, plate)
end)

-- Lockpicking a claimed vehicle. Never inside a safezone. Success wipes the claim.

local tokens = {}   -- [src] = { plate, id, at }
local LP = Vehicles.Lockpick or {}

local function skillLevel(src)
    if GetResourceState('bs_skills') ~= 'started' then return 0 end
    local ok, level = pcall(function()
        return exports.bs_skills:GetSkillLevel(src, Vehicles.Settings.hotwireSkill or 'lockpicking')
    end)
    return (ok and tonumber(level)) or 0
end

BSB.RegisterCallback('vehicles:lockpickStart', function(src, plate)
    if not R.nearPlate(src, plate, 4.0) then return { ok = false, error = Lp(src, 'srv.not_at') } end
    local record = R.get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end
    if not record.locked then return { ok = false, error = Lp(src, 'srv.not_locked') } end

    if R.hasKey(record, R.charIdOf(src)) then
        record.locked = false
        R.touch(record.plate)
        TriggerClientEvent('bs:vehicles:lockState', -1, record.plate, false)
        return { ok = true, unlocked = true }
    end

    local at = GetEntityCoords(GetPlayerPed(src))
    if safeAt(at.x, at.y, 0.0) then
        return { ok = false, error = Lp(src, 'srv.safezone') }
    end

    if exports.bs_inventory:CountItem(src, 'lockpick') < 1 then
        return { ok = false, error = Lp(src, 'srv.need_pick') }
    end

    local level = skillLevel(src)
    if level < (Vehicles.Settings.hotwireMinLevel or 0) then
        return { ok = false, error = Lp(src, 'srv.dont_know') }
    end

    local id = math.random(100000, 999999)
    tokens[src] = { plate = record.plate, id = id, at = GetGameTimer() }
    return { ok = true, token = id, level = level }
end)

BSB.RegisterCallback('vehicles:hotwire', function(src, plate, token, success)
    local t = tokens[src]
    tokens[src] = nil
    local clean = R.clean(plate)
    if not t or t.plate ~= clean or t.id ~= tonumber(token) then return { ok = false, error = Lp(src, 'keys.lost') } end

    -- A real attempt takes time; an instant success is not one
    local elapsed = GetGameTimer() - t.at
    if elapsed > 120000 or (success and elapsed < 250 * (tonumber(LP.pins) or 3)) then
        return { ok = false, error = Lp(src, 'keys.lost') }
    end

    if not R.nearPlate(src, plate, 4.0) then return { ok = false, error = Lp(src, 'srv.not_at') } end
    local record = R.get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local at = GetEntityCoords(GetPlayerPed(src))
    if safeAt(at.x, at.y, 0.0) then return { ok = false, error = Lp(src, 'srv.not_safezone') } end
    if exports.bs_inventory:CountItem(src, 'lockpick') < 1 then return { ok = false, error = Lp(src, 'srv.need_pick') } end

    if not success then
        local broke = math.random() < (LP.breakChance or 0.5)
        if broke then exports.bs_inventory:RemoveItem(src, 'lockpick', 1) end
        return { ok = false, error = broke and Lp(src, 'srv.pick_snapped') or Lp(src, 'srv.pick_slipped'), broke = broke }
    end

    -- Even a clean pick wears out sometimes.
    if math.random() < 0.2 then exports.bs_inventory:RemoveItem(src, 'lockpick', 1) end

    -- faction jobs: a Car Thief can deliver a picked car to the chop shop (bs_jobs)
    TriggerEvent('bs:jobs:carPicked', src, record.plate, record.owner)
    -- The claim is wiped: whoever gets in next can claim it.
    record.owner = nil
    record.locked = false
    exports.oxmysql:execute_async('DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    record.keys = {}
    R.touch(record.plate)
    R.save(record)

    TriggerClientEvent('bs:vehicles:lockState', -1, record.plate, false)
    TriggerClientEvent('bs:vehicles:claimWiped', -1, record.plate)
    exports.bs_core:AwardAction(src, 'vehicle_hotwired')

    return { ok = true }
end)

AddEventHandler('playerDropped', function() tokens[source] = nil end)

-- Staff

RegisterCommand('bs_worldcars', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    local parts = {}
    for category, n in pairs(owed) do parts[#parts + 1] = ('%s %d'):format(category, n) end
    local line = 'world vehicles still owed: ' .. (#parts > 0 and table.concat(parts, ', ') or 'none')
    if src == 0 then print(line) else
        TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = line, duration = 6000 })
    end
end, false)

-- Read-only list for the staff atlas

exports('GetWorldCars', function()
    local rows = exports.oxmysql:query_async([[
        SELECT v.*, CONCAT_WS(' ', c.`first_name`, c.`last_name`) AS `owner_name`
        FROM `bs_vehicles` v LEFT JOIN `bs_characters` c ON c.`id` = v.`owner_character_id`
        WHERE v.`scrapped` = 0 AND v.`stored` = 0 AND v.`position` IS NOT NULL
        LIMIT 2000
    ]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, pos = pcall(json.decode, r.position)
        if ok and type(pos) == 'table' and pos.x and pos.y then
            local state = 'free'
            if r.wrecked_at then state = 'wrecked'
            elseif r.owner_character_id then state = 'claimed'
            elseif r.locked == true or tonumber(r.locked) == 1 then state = 'locked' end
            out[#out + 1] = { id = r.id, plate = r.plate, model = tostring(r.model or '?'),
                origin = (r.world_spawn == true or tonumber(r.world_spawn) == 1) and 'system' or 'admin',
                owner = r.owner_character_id, ownerName = r.owner_name,
                category = r.category, fuel = tonumber(r.fuel) or 0,
                x = pos.x, y = pos.y, z = pos.z, state = state }
        end
    end
    return out
end)

-- Staff: wipe unowned world cars and place them again over the anchors

-- Only system cars with no owner and no keys
exports('ResetWorldCars', function()
    local rows = exports.oxmysql:query_async([[
        SELECT v.`id`, v.`plate` FROM `bs_vehicles` v
        WHERE v.`world_spawn` = 1 AND v.`owner_character_id` IS NULL
          AND NOT EXISTS (SELECT 1 FROM `bs_vehicle_keys` k WHERE k.`vehicle_id` = v.`id`)
    ]]) or {}
    local plates = {}
    for _, row in ipairs(rows) do
        exports.oxmysql:execute_async('DELETE FROM `bs_vehicles` WHERE `id` = ? AND `owner_character_id` IS NULL', { row.id })
        R.registry[row.plate] = nil
        R.dirty[row.plate] = nil
        plates[#plates + 1] = row.plate
    end
    if #plates > 0 then TriggerClientEvent('bs:vehicles:removed', -1, plates) end
    pending = {}
    deck = {}
    local owedNow = W.enabled and computeOwed() or 0
    return #plates, owedNow
end)
