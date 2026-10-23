-- bs_vehicles - fuel pumps

local function Pc() return Vehicles.Pumps or {} end
local function J() return Pc().jump or {} end

local function num(v, fb) return tonumber(v) or fb end

-- Logging

local function guardLog(src, detail)
    local ped = src and src > 0 and GetPlayerPed(src) or 0
    local c = (ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local player = src and src > 0 and exports.bs_core:GetPlayer(src) or nil
    pcall(function()
        exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
            { src or 0, src and src > 0 and GetPlayerIdentifierByType(src, 'license') or nil, player and player.charId or nil,
              (src and src > 0 and GetPlayerName(src) or 'server'):sub(1, 64), 'pump', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
    end)
end

-- Stations and their fuel

local stations = {}   -- [id] = { id, label, x, y, z, fuel }
local condition = {}  -- [pumpKey] = 0.35..1.0, rolled once per restart

local function capacity() return num(Pc().stationCapacity, 1000) end

local function pumpKey(x, y, z) return ('%.1f:%.1f:%.1f'):format(x, y, z) end

local function stationRec(id, label, x, y, z)
    local st = stations[id]
    if not st then
        st = { id = id, label = label, x = x, y = y, z = z, fuel = capacity() * num(Pc().startPct, 30) / 100 }
        stations[id] = st
    end
    return st
end

for i, s in ipairs(Vehicles.Stations or {}) do stationRec('s' .. i, s.label, s.x, s.y, s.z) end

local function stationFor(x, y, z)
    local best, bd
    for i, s in ipairs(Vehicles.Stations or {}) do
        local dx, dy = s.x - x, s.y - y
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = i, d end
    end
    local r = num(Pc().stationRadius, 60.0)
    if best and bd <= r * r then
        local s = Vehicles.Stations[best]
        return stationRec('s' .. best, s.label, s.x, s.y, s.z)
    end
    -- A roadside pump with no listed station keeps its own reserve.
    return stationRec('p' .. pumpKey(x, y, z), 'Roadside pump', x, y, z)
end

local function conditionOf(key)
    if not condition[key] then condition[key] = math.random(35, 100) / 100 end
    return condition[key]
end

-- Position and power checks

local function pedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function distTo(src, x, y, z)
    local at = pedPos(src)
    if not at then return 9999.0 end
    return #(at - vector3(x, y, z))
end

-- The pump position is a claim from the client; the player position is checked here.
local function standingAt(src, x, y, z, reach)
    return distTo(src, x, y, z) <= (reach or num(Pc().distance, 2.6)) + 2.5
end

-- Districts lit by the power station event (GlobalState.bsPowerDistricts = { { id, x, y, radius } })
local function districtAt(x, y)
    local list = GlobalState.bsPowerDistricts
    if type(list) ~= 'table' then return nil end
    for _, d in ipairs(list) do
        local dx, dy = num(d.x, 0) - x, num(d.y, 0) - y
        local r = num(d.radius, 0)
        if dx * dx + dy * dy <= r * r then return 'district:' .. tostring(d.id) end
    end
end

local function gridAt(x, y, z)
    local district = districtAt(x, y)
    if district then return district end
    if GetResourceState('bs_world') ~= 'started' then return nil end
    local ok, zone = pcall(function() return exports.bs_world:PoweredAt(x, y, z) end)
    return ok and zone or nil
end
exports('PumpPoweredAt', function(x, y, z) return gridAt(num(x, 0), num(y, 0), num(z, 0)) end)

local function vehicleNear(plate, x, y, z, reach)
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) then
            local c = GetEntityCoords(veh)
            if #(c - vector3(x, y, z)) <= reach then
                local read = GetVehicleNumberPlateText(veh)
                if type(read) == 'string' and read:gsub('%s+$', '') == plate then return veh end
            end
        end
    end
end

-- Battery items: metadata { charge, cap }. No metadata means a fresh one.

local function itemMeta(m)
    m = type(m) == 'table' and m or {}
    local cap = math.max(0.0, math.min(100.0, num(m.cap, 100.0)))
    return { charge = math.max(0.0, math.min(cap, num(m.charge, cap))), cap = cap }
end

local function batteryItem() return J().batteryItem or 'battery' end

-- Best battery a player carries (most charge). Also used by sv_world when fitting one.
function VehBatteryBestSlot(src)
    local best, bm
    for _, e in ipairs(exports.bs_inventory:ItemMetaList(src, batteryItem()) or {}) do
        local m = itemMeta(e.metadata)
        if not bm or m.charge > bm.charge then best, bm = e.slot, m end
    end
    return best, bm
end

local function itemAtSlot(src, slot)
    for _, e in ipairs(exports.bs_inventory:ItemMetaList(src, batteryItem()) or {}) do
        if e.slot == slot then return itemMeta(e.metadata) end
    end
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Writes a battery item back; capacity 0 turns it into junk (recyclable).
local function writeItem(src, slot, charge, cap, push)
    if cap <= 0 then
        exports.bs_inventory:RemoveSlot(src, slot, batteryItem())
        exports.bs_inventory:GiveItem(src, J().junkItem or 'junk_battery', 1)
        return false
    end
    exports.bs_inventory:SetItemMeta(src, slot, batteryItem(), { charge = round1(charge), cap = round1(cap), battery = math.floor(charge), capacity = ('max %d%%'):format(math.floor(cap)) }, not push)
    return true
end

-- Jump sessions, one per pump

local sessions = {}  -- [pumpKey] = session
local owned = {}     -- [src] = pumpKey
local nextId = 0

local function sessionById(id)
    for _, s in pairs(sessions) do if s.id == id then return s end end
end

local function publicList()
    local out = {}
    for _, s in pairs(sessions) do
        out[#out + 1] = { id = s.id, x = s.x, y = s.y, z = s.z, kind = s.kind, netId = s.netId, stage = s.stage }
    end
    return out
end

local function broadcast() TriggerClientEvent('bs:vehicles:jump:sessions', -1, publicList()) end

-- Writes the cached charge back to the car or the item.
local function flush(s, push)
    if s.junked then return end
    if s.kind == 'car' then
        if VehPumpSetBattery then VehPumpSetBattery(s.plate, s.charge, s.cap) end
        if s.cap <= 0 then
            exports.bs_inventory:GiveItem(s.src, J().junkItem or 'junk_battery', 1)
        end
    else
        writeItem(s.src, s.slot, s.charge, s.cap, push)
    end
    s.junked = s.cap <= 0
    s.dirty = false
    s.flushedAt = GetGameTimer()
end

local function endSession(s, reasonKey)
    if not sessions[s.key] then return end
    flush(s, true)
    sessions[s.key] = nil
    if owned[s.src] == s.key then owned[s.src] = nil end
    if reasonKey and GetPlayerName(s.src) then
        TriggerClientEvent('bs:ui:notify', s.src, { type = 'warn', message = Lp(s.src, reasonKey), duration = 4000 })
    end
    TriggerClientEvent('bs:vehicles:jump:ended', -1, s.id, s.x, s.y, s.z)
    broadcast()
end

local function rainy()
    if GetResourceState('bs_world') ~= 'started' then return false end
    local ok, w = pcall(function() return exports.bs_world:WorldState() end)
    local name = ok and type(w) == 'table' and tostring(w.weather or ''):upper() or ''
    return name:find('RAIN') ~= nil or name:find('THUNDER') ~= nil
end

-- 0..1: skill tree level plus a nudge for Engineers and Mechanics.
local function skillOf(src)
    local lvl = 0
    if GetResourceState('bs_skills') == 'started' then
        local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel(src, J().skillTree or 'crafting') end)
        lvl = ok and num(v, 0) or 0
    end
    local player = exports.bs_core:GetPlayer(src)
    local bonus = (player and (J().classes or {})[player.classId or '']) and 0.25 or 0.0
    return math.min(1.0, lvl / 20.0 + bonus)
end

-- The needle game for this crank. Harder with low skill, a weak battery, a worn pump and rain.
local function difficulty(s)
    local skill = skillOf(s.src)
    local cond = conditionOf(s.key)
    local wet = rainy()
    local d = num(J().difficulty, 1.0)
        * (1.35 - 0.6 * skill)
        * (1.3 - 0.5 * (s.charge / 100.0))
        * (1.3 - 0.45 * cond)
        * (wet and 1.25 or 1.0)
    d = math.max(0.35, math.min(3.0, d))
    return {
        level = d,
        zone = math.max(0.06, math.min(0.3, 0.2 / d)),
        drift = 0.25 * d,
        holdMs = num(J().holdMs, 3500),
        windowMs = num(J().crankWindowMs, 18000),
        rain = wet, pump = math.floor(cond * 100), skill = math.floor(skill * 100),
    }
end

local function poweredBy(key, x, y, z)
    local grid = gridAt(x, y, z)
    if grid then return 'grid' end
    local s = sessions[key]
    if s and s.stage == 'powered' then return 'battery', s end
end

local function hasCables(src)
    return exports.bs_inventory:CountItem(src, J().cableItem or 'jumper_cables') > 0
end

-- Callbacks

local function stationView(st)
    return { label = st.label, fuel = math.floor(st.fuel), cap = math.floor(capacity()) }
end

-- What the panel needs when somebody walks up to a pump.
BSB.RegisterCallback('vehicles:pumpState', function(src, x, y, z)
    if not Pc().enabled or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return { ok = false } end
    if not standingAt(src, x, y, z) then return { ok = false, error = Lp(src, 'srv.too_far_pump') } end
    local key = pumpKey(x, y, z)
    local by, s = poweredBy(key, x, y, z)
    local out = { ok = true, powered = by, station = stationView(stationFor(x, y, z)), jump = J().enabled == true }
    s = s or sessions[key]
    if s then
        out.session = { id = s.id, stage = s.stage, mine = s.src == src, charge = s.charge, cap = s.cap, kind = s.kind, clamps = s.clamps }
    end
    return out
end)

BSB.RegisterCallback('vehicles:jumpConnect', function(src, x, y, z, plate)
    local j = J()
    if not Pc().enabled or not j.enabled then return { ok = false } end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return { ok = false } end
    if not standingAt(src, x, y, z) then return { ok = false, error = Lp(src, 'srv.too_far_pump') } end

    local key = pumpKey(x, y, z)
    if gridAt(x, y, z) then return { ok = false, error = Lp(src, 'srv.has_power') } end
    if sessions[key] then return { ok = false, error = Lp(src, 'pj.busy') } end
    if owned[src] then return { ok = false, error = Lp(src, 'pj.already') } end
    if not hasCables(src) then return { ok = false, error = Lp(src, 'pj.need_cables') } end

    nextId = nextId + 1
    local s = { id = nextId, key = key, x = x, y = y, z = z, src = src, stage = 'clamps', clamps = 0,
                at = GetGameTimer(), clampAt = GetGameTimer(), flushedAt = GetGameTimer() }

    if type(plate) == 'string' and plate ~= '' then
        local veh = vehicleNear(plate, x, y, z, num(j.cableLength, 6.0) + 1.5)
        if not veh then return { ok = false, error = Lp(src, 'pj.car_reach') } end
        if VehPumpMissing and VehPumpMissing(plate, 'battery') then return { ok = false, error = Lp(src, 'srv.no_batt') } end
        local charge, cap = VehPumpBatteryOf(plate)
        if not charge then return { ok = false, error = Lp(src, 'srv.unknown') } end
        s.kind, s.plate, s.charge, s.cap = 'car', plate, charge, cap
        s.netId = NetworkGetNetworkIdFromEntity(veh)
        s.anchor = GetEntityCoords(veh)
    else
        local slot, meta = VehBatteryBestSlot(src)
        if not slot then return { ok = false, error = Lp(src, 'pj.need_battery') } end
        s.kind, s.slot, s.charge, s.cap = 'item', slot, meta.charge, meta.cap
    end

    if s.charge < num(j.minCharge, 5) then return { ok = false, error = Lp(src, 'pj.flat'), charge = s.charge, cap = s.cap } end

    sessions[key] = s
    owned[src] = key
    broadcast()
    return { ok = true, id = s.id, kind = s.kind, charge = s.charge, cap = s.cap, clampMs = num(j.clampMs, 1400) }
end)

BSB.RegisterCallback('vehicles:jumpClamp', function(src, id)
    local s = sessionById(id)
    if not s or s.src ~= src or s.stage ~= 'clamps' then return { ok = false } end
    local now = GetGameTimer()
    if now - s.clampAt < num(J().clampMs, 1400) - 250 then return { ok = false, error = Lp(src, 'pj.too_quick') } end
    s.clampAt = now
    s.clamps = s.clamps + 1
    if s.clamps >= 2 then
        s.stage = 'crank'
        s.crankAt = now
        s.diff = difficulty(s)
        broadcast()
    end
    return { ok = true, clamps = s.clamps, stage = s.stage, diff = s.diff }
end)

local function shock(s)
    local j = J()
    if j.shock == false or math.random() > num(j.shockChance, 0.6) then return nil end
    -- Either a sharp jolt (10-25 HP and a stagger) or a hard throw (ragdoll, 30 HP).
    if math.random() < 0.5 then
        TriggerClientEvent('bs:vehicles:pump:shock', s.src, 'stagger', math.random(10, 25))
        return 'stagger'
    end
    TriggerClientEvent('bs:vehicles:pump:shock', s.src, 'ragdoll', 30)
    return 'ragdoll'
end

BSB.RegisterCallback('vehicles:jumpCrank', function(src, id, success)
    local s = sessionById(id)
    if not s or s.src ~= src or s.stage ~= 'crank' then return { ok = false } end
    local j = J()
    local now = GetGameTimer()
    local took = now - (s.crankAt or now)

    -- Nobody holds a needle in the green for holdMs in less than holdMs.
    if success and took < (s.diff and s.diff.holdMs or 3500) - 400 then
        guardLog(src, ('pump crank too fast: %dms at %s'):format(took, s.key))
        success = false
    end

    local out = { ok = true, success = success == true }
    if success then
        s.cap = math.max(0.0, s.cap - math.random(num(j.wearMin, 5), num(j.wearMax, 10)))
        s.charge = math.min(s.charge, s.cap)
        s.stage = 'powered'
        if GetResourceState('bs_skills') == 'started' then
            pcall(function() exports.bs_skills:AddSkillXP(src, j.skillTree or 'crafting', num(j.xp, 40)) end)
        end
        guardLog(src, ('pump jump ok %s (%s, cap %.0f)'):format(s.key, s.kind, s.cap))
    else
        s.cap = math.max(0.0, s.cap - math.random(num(j.failWearMin, 15), num(j.failWearMax, 25)))
        s.charge = math.min(s.charge, s.cap)
        out.shock = shock(s)
        if j.noise ~= false and GetResourceState('bs_zombies') == 'started' then
            -- Lures walkers already nearby. EventNoise never spawns any.
            pcall(function() exports.bs_zombies:EventNoise(s.x, s.y, s.z, num(j.noiseRadius, 60.0), 'pump') end)
        end
        guardLog(src, ('pump jump failed %s (%s, cap %.0f, shock %s)'):format(s.key, s.kind, s.cap, tostring(out.shock)))
        s.stage = 'crank'
        s.crankAt = now
        s.diff = difficulty(s)
        out.diff = s.diff
    end

    out.charge, out.cap = s.charge, s.cap
    flush(s, true)
    if s.cap <= 0 then
        out.junk = true
        endSession(s, 'pj.junk')
    elseif s.charge < num(j.minCharge, 5) and s.stage ~= 'powered' then
        endSession(s, 'pj.flat')
        out.ended = true
    else
        broadcast()
    end
    return out
end)

BSB.RegisterCallback('vehicles:jumpDisconnect', function(src)
    local key = owned[src]
    local s = key and sessions[key]
    if not s then return { ok = false } end
    endSession(s, 'pj.unclamped')
    return { ok = true }
end)

-- One pump tick while somebody holds the trigger. Anyone can use a powered pump.
local lastTick = {}

BSB.RegisterCallback('vehicles:pumpTick', function(src, x, y, z, target, plate)
    if not Pc().enabled or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return { ok = false } end
    local hose = num(Pc().hoseLength, 6.0)
    if not standingAt(src, x, y, z, hose) then return { ok = false, error = Lp(src, 'pj.hose_reach') } end

    local now = GetGameTimer()
    if now - (lastTick[src] or 0) < num(Pc().tickMs, 500) - 100 then return { ok = true, skipped = true } end
    lastTick[src] = now

    local key = pumpKey(x, y, z)
    local by, s = poweredBy(key, x, y, z)
    if not by then return { ok = false, error = Lp(src, 'srv.no_power') } end

    local st = stationFor(x, y, z)
    if st.fuel < 0.1 then return { ok = false, error = Lp(src, 'srv.dry') } end

    local want = math.min(num(Pc().litersPerTick, 1.0), st.fuel)
    local moved, tank = 0.0, nil

    if target == 'can' then
        local containers = Vehicles.Fuel.containers or { 'fuel_can' }
        local info = exports.bs_inventory:MeasuredInfo(src, containers)
        if not info or (info.containers or 0) < 1 then return { ok = false, error = Lp(src, 'srv.need_can') } end
        if (info.room or 0) <= 0 then return { ok = false, error = Lp(src, 'srv.cans_full'), full = true } end
        moved = exports.bs_inventory:PourInto(src, containers, math.min(want, info.room)) or 0
    else
        if type(plate) ~= 'string' then return { ok = false } end
        if not vehicleNear(plate, x, y, z, hose + 3.0) then return { ok = false, error = Lp(src, 'pj.hose_reach') } end
        if VehPumpMissing(plate, 'fueltank') then return { ok = false, error = Lp(src, 'srv.no_tank') } end
        local fuel = VehPumpFuelOf(plate)
        if not fuel then return { ok = false, error = Lp(src, 'srv.unknown') } end
        if fuel >= 99.5 then return { ok = false, error = Lp(src, 'srv.tank_full'), full = true } end
        moved = math.min(want, 100.0 - fuel)
        tank = VehPumpApplyFuel(plate, moved)
    end

    if moved <= 0 then return { ok = false, error = Lp(src, 'srv.nothing_moved'), full = true } end
    st.fuel = math.max(0.0, st.fuel - moved)

    local out = { ok = true, moved = moved, fuel = tank, station = stationView(st), powered = by }
    if by == 'battery' and s then
        s.charge = math.max(0.0, s.charge - moved * num(J().drainPerLiter, 1.0))
        s.dirty = true
        out.charge, out.cap = s.charge, s.cap
        if s.charge <= 0 then
            endSession(s, 'pj.flat')
            out.dead = true
        end
    end
    return out
end)

-- Charging battery items at a running base generator (bs_building).
local charging = {}

BSB.RegisterCallback('vehicles:chargeStart', function(src)
    if GetResourceState('bs_building') ~= 'started' then return { ok = false } end
    local gen = exports.bs_building:RunningGeneratorNear(src, 4.0)
    if not gen then return { ok = false, error = Lp(src, 'pj.no_generator') } end
    local any = false
    for _, e in ipairs(exports.bs_inventory:ItemMetaList(src, batteryItem()) or {}) do
        local m = itemMeta(e.metadata)
        if m.charge < m.cap then any = true break end
    end
    if not any then return { ok = false, error = Lp(src, 'pj.nothing_charge') } end
    charging[src] = { gen = gen, at = GetGameTimer() }
    return { ok = true, ms = num((Pc().recharge or {}).generatorMs, 8000) }
end)

BSB.RegisterCallback('vehicles:chargeFinish', function(src)
    local c = charging[src]
    charging[src] = nil
    local R = Pc().recharge or {}
    if not c or GetGameTimer() - c.at < num(R.generatorMs, 8000) - 500 then return { ok = false } end
    if exports.bs_building:RunningGeneratorNear(src, 4.0) ~= c.gen then return { ok = false, error = Lp(src, 'pj.no_generator') } end
    local n = 0
    for _, e in ipairs(exports.bs_inventory:ItemMetaList(src, batteryItem()) or {}) do
        local m = itemMeta(e.metadata)
        if m.charge < m.cap then
            writeItem(src, e.slot, math.min(m.cap, m.charge + num(R.generatorAmount, 40)), m.cap, false)
            n = n + 1
        end
    end
    exports.bs_inventory:Refresh(src)
    exports.bs_building:UseGeneratorFuel(c.gen, num(R.generatorFuel, 3))
    return { ok = true, n = n }
end)

-- Watching the cables

CreateThread(function()
    while true do
        Wait(1000)
        local reach = num(J().cableLength, 6.0)
        for _, s in pairs(sessions) do
            if not GetPlayerName(s.src) then
                endSession(s, nil)
            elseif s.kind == 'car' then
                local veh = s.netId and NetworkGetEntityFromNetworkId(s.netId) or 0
                if veh == 0 or not DoesEntityExist(veh) or #(GetEntityCoords(veh) - s.anchor) > reach then
                    endSession(s, 'pj.snapped')
                end
            else
                -- A loose battery sits at the pump; walking off with it pulls the clamps.
                if distTo(s.src, s.x, s.y, s.z) > reach + 1.5 or not itemAtSlot(s.src, s.slot) then
                    endSession(s, 'pj.snapped')
                end
            end
            if sessions[s.key] then
                if s.stage ~= 'powered' and GetGameTimer() - s.at > num(J().crankWindowMs, 18000) * 4 + 60000 then
                    endSession(s, 'pj.unclamped')
                elseif s.dirty and GetGameTimer() - s.flushedAt > 5000 then
                    flush(s, true)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastTick[src], charging[src] = nil, nil
    local key = owned[src]
    if key and sessions[key] then endSession(sessions[key], nil) end
end)

RegisterNetEvent('bs:vehicles:jump:ask', function()
    TriggerClientEvent('bs:vehicles:jump:sessions', source, publicList())
end)

-- Fuel Runner deliveries and staff

-- Delivered fuel goes to the emptiest listed station.
exports('PumpDeliver', function(src, liters)
    liters = num(liters, 0)
    if liters <= 0 then return 0 end
    local best
    for i in ipairs(Vehicles.Stations or {}) do
        local st = stations['s' .. i]
        if st and (not best or st.fuel < best.fuel) then best = st end
    end
    if not best then return 0 end
    local added = math.min(liters, capacity() - best.fuel)
    best.fuel = best.fuel + added
    if src and GetPlayerName(src) then
        TriggerClientEvent('bs:ui:notify', src, { type = 'success', duration = 4500,
            message = Lp(src, 'pj.delivered', { n = math.floor(added), station = best.label }) })
    end
    return added
end)

exports('PumpStations', function()
    local out = {}
    for _, st in pairs(stations) do
        local jumped = false
        for _, s in pairs(sessions) do
            if s.stage == 'powered' and stationFor(s.x, s.y, s.z) == st then jumped = true end
        end
        out[#out + 1] = { id = st.id, label = st.label, fuel = math.floor(st.fuel), cap = math.floor(capacity()),
                          grid = gridAt(st.x, st.y, st.z) ~= nil, jumped = jumped }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

exports('PumpSetFuel', function(id, liters)
    local st = stations[tostring(id)]
    if not st then return false end
    st.fuel = math.max(0.0, math.min(capacity(), num(liters, 0)))
    return true
end)

BSB.RegisterCommand('pumps', 'bs.admin', 'Fuel left at every station', {}, function(src)
    for _, st in pairs(stations) do
        local line = ('%s - %d / %d L'):format(st.label, math.floor(st.fuel), math.floor(capacity()))
        if src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'PUMPS', line } }) else print(line) end
    end
end)
