-- bs_vehicles - fuel. GTA has no fuel;

Fuel = {}

local tank = nil            -- local copy while driving
local lastTick = 0
local lastReport = 0
local spluttering = false


local function partOf(record, id)
    return (record and record.parts and tonumber(record.parts[id])) or 100.0
end

-- Fuel cost per second of this driving.
local function drainPerSecond(vehicle, record)
    local F = Vehicles.Fuel

    local rpm = GetVehicleCurrentRpm(vehicle) or 0.0
    local throttle = math.max(0.0, math.min(1.0, rpm))

    -- Idling burns very little; flat out burns the configured rate.
    local rate = ((F.idleDrain or 0.35) + ((F.drain or 2.2) - (F.idleDrain or 0.35)) * throttle) / 60.0

    -- A holed tank leaks whether moving or not.
    local tankHealth = GetVehiclePetrolTankHealth(vehicle) or 1000.0
    if tankHealth < 900.0 then
        local hole = 1.0 - math.max(0.0, tankHealth) / 1000.0
        rate = rate + ((F.leakDrain or 3.0) / 60.0) * hole
    end

    -- A worn engine burns more.
    local engine = partOf(record, 'engine') / 100.0
    rate = rate * (1.0 + (1.0 - engine) * 0.5)

    return rate
end

-- The loop

AddEventHandler('bs:vehicles:entered', function(record)
    tank = record and record.fuel or nil
    lastTick = GetGameTimer()
    lastReport = GetGameTimer()
    spluttering = false
end)

AddEventHandler('bs:vehicles:left', function()
    tank = nil
    spluttering = false
end)

CreateThread(function()
    while true do
        Wait(200)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        -- Only the driver simulates the tank; a passenger would fight the driver's numbers.
        if not (vehicle and vehicle ~= 0
                and GetPedInVehicleSeat(vehicle, -1) == ped
                and tank and Veh.current) then
            goto continue
        end

        do
            local nowMs = GetGameTimer()
            local dt = (nowMs - lastTick) / 1000.0
            lastTick = nowMs

            if GetIsVehicleEngineRunning(vehicle) then
                tank = math.max(0.0, tank - drainPerSecond(vehicle, Veh.current) * dt)
            end

            -- Keep the engine's own tank in step so the gauge, warning light and smoke agree.
            SetVehicleFuelLevel(vehicle, tank + 0.0)

            -- Running out: below the splutter threshold the engine cuts for a fraction of a second at random
            local F = Vehicles.Fuel

            if tank <= 0.05 then
                if GetIsVehicleEngineRunning(vehicle) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
                if not spluttering then
                    spluttering = true
                    TriggerEvent('bs:ui:notify', {
                        type = 'danger', message = L('fuel.out'), duration = 4000,
                    })
                end

            elseif tank <= (F.spluttersAt or 8.0) then
                if not spluttering then
                    spluttering = true
                    TriggerEvent('bs:ui:notify', {
                        type = 'warn',
                        message = L('fuel.fumes'),
                        duration = 4000,
                    })
                end

                if math.random() < 0.06 then
                    SetVehicleEngineOn(vehicle, false, true, true)
                    Wait(math.random(120, 420))
                    if DoesEntityExist(vehicle) and tank > 0.05 then
                        SetVehicleEngineOn(vehicle, true, true, false)
                    end
                end
            else
                spluttering = false
            end

            -- Report on a timer, not every tick.
            if nowMs - lastReport >= (Vehicles.Settings.reportInterval or 5000) then
                lastReport = nowMs
                -- Body/engine health ride along with fuel so crash damage persists.
                TriggerServerEvent('bs:vehicles:report', Veh.plate, tank,
                    Wear and Wear.Snapshot() or nil,
                    GetVehicleBodyHealth(vehicle), GetVehicleEngineHealth(vehicle),
                    Wear and Wear.TyreSnapshot() or nil)

                local at = GetEntityCoords(vehicle)
                TriggerServerEvent('bs:vehicles:position', Veh.plate,
                    at.x, at.y, at.z, GetEntityHeading(vehicle))
            end
        end

        ::continue::
    end
end)

-- Refuelling

local refuelling = false

function Fuel.Pour(vehicle)
    if refuelling then return end

    local plate = Veh.Plate(vehicle)
    if not plate then return end

    refuelling = true

    -- Items and tank checked by the server first, so nobody kneels for nothing.
    local pre = BSB.Await('vehicles:siphonCheck', 8000, plate)
    if not pre or not pre.ok then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = (pre and pre.error) or L('fuel.nothing_drain'), duration = 3200 })
        refuelling = false
        return
    end

    local ped = PlayerPedId()
    local dict = 'timetable@gardener@filling_can'

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'gar_ig_5_filling_can', 4.0, -4.0,
            Vehicles.Fuel.refuelTime or 8000, 49, 0.0, false, false, false)
    end

    Wait(Vehicles.Fuel.refuelTime or 8000)
    ClearPedTasks(ped)

    local result = BSB.Await('vehicles:refuel', 8000, plate)

    if result and result.ok then
        if Veh.current and Veh.current.plate == plate then
            Veh.current.fuel = result.fuel
            if tank then tank = result.fuel end
        end
        TriggerEvent('bs:ui:notify', {
            type = 'success',
            message = L('fuel.level', { pct = math.floor(result.fuel) }),
            duration = 2600,
        })
    else
        TriggerEvent('bs:ui:notify', {
            type = 'warn',
            message = (result and result.error) or L('fuel.nothing_pour'),
            duration = 2600,
        })
    end

    refuelling = false
end

-- Siphoning (jerry can source)
-- No pump works and nothing costs money (see config_vehicles.lua)

function Fuel.Siphon(vehicle)
    if refuelling then return end
    if not DoesEntityExist(vehicle) then return end

    local plate = Veh.Plate(vehicle)
    if not plate then return end

    refuelling = true

    local ped = PlayerPedId()
    local dict = 'timetable@gardener@filling_can'

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'gar_ig_5_filling_can', 4.0, -4.0,
            Vehicles.Fuel.siphonTime or 9000, 49, 0.0, false, false, false)
    end

    Wait(Vehicles.Fuel.siphonTime or 9000)
    ClearPedTasks(ped)

    local result = BSB.Await('vehicles:siphon', 8000, plate)

    if result and result.ok then
        TriggerEvent('bs:ui:notify', {
            type = 'success',
            -- What went into your can; the can is a container with a level.
            message = L('fuel.siphoned', { n = math.floor(result.taken or 0) }),
            duration = 2800,
        })
    else
        TriggerEvent('bs:ui:notify', {
            type = 'warn',
            message = (result and result.error) or L('fuel.nothing_drain'),
            duration = 2600,
        })
    end

    refuelling = false
end

exports('TankLevel', function() return tank end)
