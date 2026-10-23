-- bs_vehicles - world vehicles on the client

World = {}

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 2800 })
end

-- Clear space check

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 5000 do Wait(20); waited = waited + 20 end
    return HasModelLoaded(hash) and hash or nil
end

function World.ClearAt(x, y, z, heading, hash)
    local mn, mx = GetModelDimensions(hash)
    local sx = (mx.x - mn.x) + 0.8
    local sy = (mx.y - mn.y) + 0.8
    local sz = math.max(1.2, (mx.z - mn.z))
    local handle = StartShapeTestBox(x, y, z + 0.6 + sz / 2.0, sx, sy, sz, 0.0, 0.0, heading or 0.0, 2, 1 | 2 | 16, 0, 7)
    local status, hit
    local waited = 0
    repeat
        Wait(0)
        status, hit = GetShapeTestResult(handle)
        waited = waited + 1
    until status ~= 1 or waited > 200
    if status ~= 2 then return false end
    return not (hit == true or hit == 1)
end

-- Ground under a point, after asking for its collision.
local function groundAt(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    for _ = 1, 10 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
        if ok then return gz end
        Wait(60)
    end
    return nil
end

-- A road-side point near (x, y): the nearest car node, pushed to the kerb.
local function roadSpot(x, y, z, nth)
    local ok, node, heading
    if nth and nth > 1 then
        ok, node, heading = GetNthClosestVehicleNodeWithHeading(x, y, z, nth, 1, 3.0, 0)
    else
        ok, node, heading = GetClosestVehicleNodeWithHeading(x, y, z, 1, 3.0, 0)
    end
    if not ok or not node then return nil end

    local sideOk, side = GetPointOnRoadSide(node.x, node.y, node.z, -1)
    local pos = (sideOk and side and side.x ~= 0.0) and side or node
    return pos, heading or 0.0
end

-- Finds a clear spot on a road near (x, y) for this model. Tries the nearest nodes in turn.
function World.FindClear(x, y, z, hash, tries)
    for nth = 1, tries or 6 do
        local pos, heading = roadSpot(x, y, z, nth)
        if pos then
            local gz = groundAt(pos.x, pos.y, pos.z)
            if gz and World.ClearAt(pos.x, pos.y, gz, heading, hash) then
                return vector3(pos.x, pos.y, gz + 0.3), heading
            end
        end
    end
    return nil
end

-- The server wants a spot for a new world vehicle somewhere in a ring around us
local function findAimed(reqId, hash, tx, ty, tz, snap)
    local r = snap + 100.0
    local loaded = false
    for _ = 1, 60 do
        RequestPathNodesInAreaThisFrame(tx - r, ty - r, tx + r, ty + r)
        if ArePathNodesLoadedInArea(tx - r, ty - r, tx + r, ty + r) then loaded = true break end
        Wait(0)
    end
    if not loaded then return false end
    for nth = 1, 4 do
        local pos, heading = roadSpot(tx, ty, tz, nth)
        if pos and #(vector2(pos.x, pos.y) - vector2(tx, ty)) < snap then
            TriggerServerEvent('bs:vehicles:spot', reqId, pos.x, pos.y, pos.z + 0.3, heading)
            return true
        end
    end
    return false
end

RegisterNetEvent('bs:vehicles:findSpot', function(reqId, model, ringMin, ringMax, tx, ty, tz)
    CreateThread(function()
        local hash = loadModel(model)
        if not hash then return end

        if tx and ty then
            findAimed(reqId, hash, tx + 0.0, ty + 0.0, (tz or 40.0) + 0.0, 250.0)
            SetModelAsNoLongerNeeded(hash)
            return
        end

        local at = GetEntityCoords(PlayerPedId())
        for _ = 1, 10 do
            local angle = math.random() * math.pi * 2.0
            local dist = ringMin + math.random() * (ringMax - ringMin)
            local tx, ty = at.x + math.cos(angle) * dist, at.y + math.sin(angle) * dist

            local pos, heading = roadSpot(tx, ty, at.z, 1)
            -- Path nodes far away may not be loaded, in which case the nearest one is somewhere else.
            if pos and #(vector2(pos.x, pos.y) - vector2(tx, ty)) < 80.0
               and #(vector2(pos.x, pos.y) - vector2(at.x, at.y)) >= ringMin * 0.8 then
                local gz = groundAt(pos.x, pos.y, pos.z)
                if gz and World.ClearAt(pos.x, pos.y, gz, heading, hash) then
                    SetModelAsNoLongerNeeded(hash)
                    return TriggerServerEvent('bs:vehicles:spot', reqId, pos.x, pos.y, gz + 0.3, heading)
                end
            end
            Wait(100)
        end
        SetModelAsNoLongerNeeded(hash)
    end)
end)

-- Missing parts: no battery or spark plug, no start; no fuel tank, no fuel.

local function missingSet(record)
    local out = {}
    for _, id in ipairs((record and record.missing) or {}) do out[id] = true end
    return out
end

function World.MissingLabels(record)
    local set, out = missingSet(record), {}
    for _, m in ipairs(Vehicles.Missing or {}) do
        if set[m.id] then out[#out + 1] = m end
    end
    return out
end

local warnedFor
local held = {}     -- [vehicle] = true while we keep it from running

AddEventHandler('bs:vehicles:entered', function(record)
    warnedFor = nil
end)

CreateThread(function()
    while true do
        Wait(250)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local record = Veh.current

        if vehicle ~= 0 and record and GetPedInVehicleSeat(vehicle, -1) == ped then
            local missing = missingSet(record)
            local reason
            if missing.battery then reason = L('world.no_batt')
            elseif missing.sparkplug then reason = L('world.no_plug')
            elseif missing.fueltank then reason = L('world.no_tank') end

            if reason or record.wrecked then
                if GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
                SetVehicleUndriveable(vehicle, true)
                held[vehicle] = true
                if warnedFor ~= record.plate then
                    warnedFor = record.plate
                    notify('warn', record.wrecked and L('world.burnt') or reason, 4000)
                end
            elseif held[vehicle] then
                -- Everything is back in (often fitted from outside): let it run again.
                held[vehicle] = nil
                warnedFor = nil
                SetVehicleUndriveable(vehicle, false)
            end
        end
    end
end)

-- Fitting

local fitting = false

function World.Fit(vehicle, partId)
    if fitting then return end
    local plate = Veh.Plate(vehicle)
    if not plate then return end

    local def
    for _, m in ipairs(Vehicles.Missing or {}) do if m.id == partId then def = m end end
    if not def then return end

    if GetResourceState('bs_inventory') == 'started' then
        local ok, count = pcall(function() return exports.bs_inventory:CountLocal(def.item) end)
        if ok and type(count) == 'number' and count == 0 then
            return notify('warn', L('world.need_part', { part = Veh.PartLabel(def) }))
        end
    end

    fitting = true
    local ped = PlayerPedId()
    local dict = 'mini@repair'
    local door = def.id == 'fueltank' and 5 or 4
    SetVehicleDoorOpen(vehicle, door, false, false)

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'fixing_a_ped', 4.0, -4.0, Vehicles.FitTime or 8000, 1, 0.0, false, false, false)
    end

    local started, cancelled = GetGameTimer(), false
    while GetGameTimer() - started < (Vehicles.FitTime or 8000) do
        Wait(100)
        if not DoesEntityExist(vehicle) or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 4.5
           or IsPedRagdoll(ped) or IsEntityDead(ped) then
            cancelled = true
            break
        end
    end

    ClearPedTasks(ped)
    if DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, door, false) end
    fitting = false
    if cancelled then return notify('warn', L('common.stopped')) end

    local result = BSB.Await('vehicles:fit', 8000, plate, partId)
    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('world.wont_go_in'))
    end

    if Veh.current and Veh.current.plate == plate and result.vehicle then
        Veh.current.missing = result.vehicle.missing
        Veh.current.parts = result.vehicle.parts
    end
    if Wear and Wear.Apply and result.vehicle then Wear.Apply(result.vehicle.parts) end
    notify('success', L('world.fitted', { part = Veh.PartLabel(def) }), 3000)
end

-- Fits the first missing part you are carrying.
function World.FitAny(vehicle)
    local state = Veh.State(vehicle)
    local list = World.MissingLabels(state)
    if #list == 0 then return notify('info', L('world.nothing_missing')) end
    for _, def in ipairs(list) do
        local ok, count = pcall(function() return exports.bs_inventory:CountLocal(def.item) end)
        if not ok or count == nil or count > 0 then return World.Fit(vehicle, def.id) end
    end
    local names = {}
    for _, def in ipairs(list) do names[#names + 1] = Veh.PartLabel(def) end
    notify('warn', L('world.missing_list', { list = table.concat(names, ', ') }), 4000)
end

-- Wrecks

function World.ApplyWreck(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    pcall(SetEntityRenderScorched, vehicle, true)
    pcall(SetVehicleEngineHealth, vehicle, -4000.0)
    pcall(SetVehicleBodyHealth, vehicle, 0.0)
    pcall(SetVehiclePetrolTankHealth, vehicle, 0.0)
    pcall(SetVehicleEngineOn, vehicle, false, true, true)
    pcall(SetVehicleUndriveable, vehicle, true)
    pcall(SetVehicleDoorsLocked, vehicle, 1)
end

local function byPlate(plate)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if Veh.Plate(vehicle) == plate then return vehicle end
    end
end

local reported = {}

-- Report vehicles near us that have just been destroyed.
CreateThread(function()
    while true do
        Wait(1500)
        local at = GetEntityCoords(PlayerPedId())
        local anyReported = next(reported) ~= nil
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if IsEntityDead(vehicle) then
                if #(GetEntityCoords(vehicle) - at) < 150.0 then
                    local plate = Veh.Plate(vehicle)
                    if plate and not reported[plate] then
                        reported[plate] = true
                        TriggerServerEvent('bs:vehicles:destroyed', plate)
                    end
                end
            elseif anyReported then
                local plate = Veh.Plate(vehicle)
                if plate and reported[plate] and not World.wrecks[plate] then reported[plate] = nil end
            end
        end
        for vehicle in pairs(held) do
            if not DoesEntityExist(vehicle) then held[vehicle] = nil end
        end
    end
end)

World.wrecks = {}   -- [plate] = true, wrecked as far as the server said

RegisterNetEvent('bs:vehicles:wrecked', function(plate)
    reported[plate] = true
    World.wrecks[plate] = true
    if Veh.current and Veh.current.plate == plate then Veh.current.wrecked = true end
    local vehicle = byPlate(plate)
    if vehicle then World.ApplyWreck(vehicle) end
end)

RegisterNetEvent('bs:vehicles:unwrecked', function(plate)
    World.wrecks[plate] = nil
    reported[plate] = nil
    if Veh.current and Veh.current.plate == plate then Veh.current.wrecked = false end
end)

-- Wrecks past their timer are gone from the database; take the entity too.
RegisterNetEvent('bs:vehicles:removed', function(plates)
    for _, plate in ipairs(plates or {}) do
        World.wrecks[plate] = nil
        reported[plate] = nil
        local vehicle = byPlate(plate)
        if vehicle then
            CreateThread(function()
                NetworkRequestControlOfEntity(vehicle)
                local tries = 0
                while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and tries < 20 do
                    Wait(100); tries = tries + 1
                    NetworkRequestControlOfEntity(vehicle)
                end
                if DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle) then
                    SetEntityAsMissionEntity(vehicle, true, true)
                    DeleteVehicle(vehicle)
                end
            end)
        end
    end
end)

RegisterCommand('fitpart', function()
    CreateThread(function()
        local vehicle = Veh.Nearby(4.0)
        if not vehicle then return notify('info', L('common.nothing_reach'), 2400) end
        World.FitAny(vehicle)
    end)
end, false)
