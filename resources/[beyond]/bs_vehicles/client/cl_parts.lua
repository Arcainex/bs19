-- bs_vehicles - vehicle wear and diagnosis

Wear = {}

local wear = nil            -- [partId] = 0..100 for the car we are in
local lastPos = nil
local overheated = 0.0
local lastAbuseAt = 0       -- GetGameTimer() of the last collision-wear hit
local lastBodyHp = nil      -- GetVehicleBodyHealth() a moment ago, for real-crash detection
local lastRoll = nil        -- pitch/roll a moment ago, for the anti-flip guard
local roadkillUntil = 0     -- GetGameTimer() window in which the anti-flip guard is armed
local settleUntil = 0       -- GetGameTimer() window right after entering where abuse never fires

-- Why a car flips running something over: a ragdoll is a solid mesh, and a wheel catching it can torque the car onto its side
AddEventHandler('bs:vehicles:roadkill', function()
    roadkillUntil = GetGameTimer() + 450
end)

-- Wheel state for the current car: [wheelIndex] = 0 fine / 1 burst / 2 detached
local WHEELS = { 0, 1, 4, 5 }
local tyreState = nil

-- Measured once on entry from a vehicle known to exist, never in the per-frame loop (see the transmission note below)
local topSpeed = nil


-- Wrapped so one missing native, or a wheel index a model does not have, cannot kill the thread that runs every other effect
local function safe(fn, ...)
    if type(fn) ~= 'function' then return end
    pcall(fn, ...)
end

local function partDef(id)
    for _, part in ipairs(Vehicles.Parts) do
        if part.id == id then return part end
    end
end

-- 0..1 for a part, where 1 is new.
local function health(id)
    if not wear then return 1.0 end
    return math.max(0.0, math.min(100.0, wear[id] or 100.0)) / 100.0
end

local function failed(id)
    local def = partDef(id)
    if not def or not wear then return false end
    return (wear[id] or 100.0) <= (def.fail or 0)
end

-- What the server should write down. Plain numbers only.
function Wear.Snapshot()
    if not wear then return nil end
    local out = {}
    for id, value in pairs(wear) do out[id] = value end
    return out
end

function Wear.Current() return wear end
function Wear.Failed(id) return failed(id) end

-- Replaces the wear table in place. wear is a local captured on entry
function Wear.Apply(newParts)
    if not wear or type(newParts) ~= 'table' then return false end
    for id, value in pairs(newParts) do wear[id] = value end
    return true
end

exports('Apply', Wear.Apply)

-- Wheels
-- Kept apart from wear: a burst or detached tyre is a discrete event, not a number that drifts down

-- Pushes tyreState onto the entity
local function applyTyre(vehicle, idx)
    if not tyreState or not vehicle or vehicle == 0 then return end
    local state = tyreState[tostring(idx)] or 0

    if state >= 1 then safe(SetVehicleTyreBurst, vehicle, idx, true, 1000.0) end
    if state >= 2 then safe(SetVehicleTyreFitted, vehicle, idx, false) end
end

-- What the server should write down. Plain numbers only, same as Wear.Snapshot.
function Wear.TyreSnapshot()
    if not tyreState then return nil end
    local out = {}
    for idx, value in pairs(tyreState) do out[idx] = value end
    return out
end

-- Accumulating

AddEventHandler('bs:vehicles:entered', function(record)
    wear = record and record.parts or nil
    lastPos = nil
    overheated = 0.0
    topSpeed = nil
    lastBodyHp = nil
    lastRoll = nil

    -- Grace window after entering: a freshly created vehicle often overlaps the ground and the
    settleUntil = GetGameTimer() + 2500

    tyreState = {}
    if record and type(record.tyres) == 'table' then
        for idx, value in pairs(record.tyres) do
            tyreState[tostring(idx)] = tonumber(value) or 0
        end
    end

    -- Measure the model's top speed now, once, while the vehicle exists.
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local model = BS.Util.ModelOf(vehicle)
        if model and model ~= 0 and IsModelInCdimage(model) then
            local ok, speed = pcall(GetVehicleModelMaxSpeed, model)
            if ok and type(speed) == 'number' and speed > 0 then topSpeed = speed end
        end

        -- Put the server's known wheel state back on before driving off, so shot-out wheels persist across restarts and streaming rebuilds
        for _, idx in ipairs(WHEELS) do applyTyre(vehicle, idx) end
    end
end)

AddEventHandler('bs:vehicles:left', function()
    wear = nil
    lastPos = nil
    topSpeed = nil
    tyreState = nil
end)

local function addWear(id, amount)
    if not wear or amount <= 0 then return end
    wear[id] = math.max(0.0, (wear[id] or 100.0) - amount)
end

CreateThread(function()
    while true do
        Wait(500)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if not (wear and vehicle and vehicle ~= 0
                and GetPedInVehicleSeat(vehicle, -1) == ped) then
            lastPos = nil
            goto continue
        end

        do
            -- Poll the entity's real burst state so wheels shot out by bullets are saved too, not only worn-out ones
            if tyreState then
                for _, idx in ipairs(WHEELS) do
                    local key = tostring(idx)
                    local ok, burst = pcall(IsVehicleTyreBurst, vehicle, idx, false)
                    if ok and burst and (tyreState[key] or 0) < 1 then
                        tyreState[key] = 1
                    end
                end
            end

            local at = GetEntityCoords(vehicle)

            if lastPos then
                -- Kilometres since the last tick. Absurd values (teleport, stream-in far away) are dropped.
                local metres = #(at - lastPos)
                if metres < 200.0 then
                    local km = metres / 1000.0

                    for _, part in ipairs(Vehicles.Parts) do
                        addWear(part.id, (part.wearPerKm or 0.3) * km)
                    end

                    -- Braking hard wears brakes and tyres beyond the distance.
                    if IsControlPressed(0, 72) and GetEntitySpeed(vehicle) > 12.0 then
                        addWear('brakes', 0.012)
                        addWear('tyres', 0.008)
                    end
                end
            end

            lastPos = at

            -- Abuse only counts on a real crash
            local bodyHp = GetVehicleBodyHealth(vehicle)
            local bodyDrop = lastBodyHp and (lastBodyHp - bodyHp) or 0.0
            lastBodyHp = bodyHp

            if bodyDrop > 20.0 and GetGameTimer() - lastAbuseAt > 3500
               and GetGameTimer() > settleUntil then
                local speed = GetEntitySpeed(vehicle)
                if speed > 6.0 then
                    lastAbuseAt = GetGameTimer()
                    local force = math.min(1.0, speed / 30.0)

                    -- A car in poor condition (below a fifth) takes more wear from the same crash
                    local condition = 0.0
                    for _, part in ipairs(Vehicles.Parts) do
                        condition = condition + health(part.id)
                    end
                    condition = condition / #Vehicles.Parts
                    local frailty = condition < 0.2 and 1.8 or 1.0

                    -- One part breaks per crash, hit harder, instead of every part at once.
                    local hit = Vehicles.Parts[math.random(#Vehicles.Parts)]
                    addWear(hit.id, 1.1 * force * frailty)
                end
            end

            -- Overheating: a failed radiator cooks the engine, so engine health falls while it runs.
            if failed('radiator') and GetIsVehicleEngineRunning(vehicle) then
                overheated = overheated + 0.5
                if overheated >= 1.0 then
                    overheated = 0.0
                    local current = GetVehicleEngineHealth(vehicle)
                    SetVehicleEngineHealth(vehicle,
                        math.max(100.0, current - (Vehicles.Effects.overheatDamagePerSec or 6.0)))
                    addWear('engine', 0.15)
                end
            end
        end

        ::continue::
    end
end)

-- Applying the effects
-- Runs every frame while driving

-- Put back everything we changed
local function restore(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    safe(SetVehicleEnginePowerMultiplier, vehicle, 0.0)
    safe(SetVehicleReduceGrip, vehicle, false)

    -- The measured speed, or a number high enough to mean no cap
    safe(SetEntityMaxSpeed, vehicle, topSpeed or 500.0)
end

local effected = nil

AddEventHandler('bs:vehicles:left', function() restore(effected); effected = nil end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then restore(effected) end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if wear and vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            Wait(0)
            effected = vehicle

            -- Anti-flip guard (see roadkillUntil above)
            if GetGameTimer() < roadkillUntil then
                local rot = GetEntityRotation(vehicle, 2)
                if lastRoll then
                    local growing = math.abs(rot.x) > math.abs(lastRoll)
                    if math.abs(rot.x) > 35.0 and growing then
                        local corrected = rot.x * 0.4
                        safe(SetEntityRotation, vehicle, corrected, rot.y * 0.6, rot.z, 2, true)
                        rot = GetEntityRotation(vehicle, 2)
                    end
                end
                lastRoll = rot.x
            else
                lastRoll = nil
            end

            local E = Vehicles.Effects

            -- Engine: power falls as it wears
            local engine = health('engine')
            local power = (E.enginePowerFloor or 0.45)
                + (1.0 - (E.enginePowerFloor or 0.45)) * engine
            if failed('engine') then power = power * 0.6 end
            safe(SetVehicleEnginePowerMultiplier, vehicle, (power - 1.0) * 100.0)

            -- A failed engine occasionally misses a beat: worn cars are unreliable, never faster.
            if failed('engine') and GetIsVehicleEngineRunning(vehicle)
               and math.random() < (E.engineIntermittentChance or 0.012) then
                safe(SetVehicleEngineOn, vehicle, false, true, true)
                CreateThread(function()
                    Wait(math.random(150, 500))
                    if DoesEntityExist(vehicle) then
                        safe(SetVehicleEngineOn, vehicle, true, true, false)
                    end
                end)
            end

            -- Crash note: the vehicle can stop existing between the check at the top of the loop and this
            if failed('transmission') and topSpeed then
                safe(SetEntityMaxSpeed, vehicle, topSpeed * (E.transmissionCap or 0.5))
            end

            -- Tyres: grip drops only once they are meaningfully worn (a 0.8 cutoff made every car feel loose from the first corner)
            local traction = (E.tractionFloor or 0.55)
                + (1.0 - (E.tractionFloor or 0.55)) * health('tyres')
            safe(SetVehicleReduceGrip, vehicle, traction < 0.62)

            -- Tyres: a failed set can pop a wheel, and a popped wheel can eventually come off
            if failed('tyres') and tyreState and GetEntitySpeed(vehicle) > (E.tyreFailureMinSpeed or 8.0) then
                for _, idx in ipairs(WHEELS) do
                    local state = tyreState[tostring(idx)] or 0

                    if state == 0 and math.random() < (E.tyreBurstChance or 0.006) then
                        tyreState[tostring(idx)] = 1
                        applyTyre(vehicle, idx)
                        TriggerEvent('bs:ui:notify', {
                            type = 'danger', message = L('parts.tyre_blew'), duration = 3200,
                        })
                        break

                    elseif state == 1 and math.random() < (E.tyreDetachChance or 0.0015) then
                        tyreState[tostring(idx)] = 2
                        applyTyre(vehicle, idx)
                        TriggerEvent('bs:ui:notify', {
                            type = 'danger', message = L('parts.wheel_off'), duration = 3800,
                        })
                        break
                    end
                end
            end

            -- Brakes: shown only as a status, not simulated
        else
            if effected then restore(effected); effected = nil end
            Wait(400)
        end
    end
end)

-- Starting
-- A failed battery sometimes fails to start the engine. It is a chance, not a certainty.

CreateThread(function()
    while true do
        Wait(300)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if wear and vehicle and vehicle ~= 0
           and GetPedInVehicleSeat(vehicle, -1) == ped
           and failed('battery')
           and GetIsVehicleEngineRunning(vehicle) then

            if math.random() < (Vehicles.Effects.deadBatteryChance or 0.75) * 0.12 then
                SetVehicleEngineOn(vehicle, false, true, true)
                TriggerEvent('bs:ui:notify', {
                    type = 'warn', message = L('parts.wont_turn'), duration = 2600,
                })
                Wait(1500)
            end
        end
    end
end)

-- Symptoms
-- What the driver notices without diagnosing: an occasional line about what the car is doing

CreateThread(function()
    while true do
        Wait(45000)

        if wear and Veh.inside then
            local complaints = {}
            for _, part in ipairs(Vehicles.Parts) do
                if (wear[part.id] or 100.0) <= (part.warn or 50) then
                    complaints[#complaints + 1] = part.symptom
                end
            end

            if #complaints > 0 then
                TriggerEvent('bs:ui:notify', {
                    type = 'info',
                    message = complaints[math.random(#complaints)],
                    duration = 5000,
                })
            end
        end
    end
end)

-- Diagnosing

local diagnosing = false

-- Takes a few seconds under the bonnet. Returns the numbers so the caller can show them.
function Wear.Diagnose(vehicle)
    if diagnosing then return nil end
    diagnosing = true

    local state = Veh.State(vehicle)
    if not state then
        diagnosing = false
        return nil
    end

    local ped = PlayerPedId()
    local dict = 'mini@repair'

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'fixing_a_ped', 4.0, -4.0,
            Vehicles.Settings.diagnoseTime or 6000, 1, 0.0, false, false, false)
    end

    SetVehicleDoorOpen(vehicle, 4, false, false)   -- bonnet
    Wait(Vehicles.Settings.diagnoseTime or 6000)
    ClearPedTasks(ped)
    SetVehicleDoorShut(vehicle, 4, false)

    diagnosing = false
    return state.parts
end

exports('Diagnose', function(vehicle) return Wear.Diagnose(vehicle) end)
exports('PartHealth', function(id) return wear and wear[id] or nil end)

-- Debug: force a breakdown

-- Breaks the vehicle the caller is currently driving, after a delay
function Wear.ScheduleFailure(seconds)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or not wear then return false end

    local targetVehicle = vehicle

    CreateThread(function()
        Wait(math.floor((tonumber(seconds) or 10) * 1000))

        -- Only act if it is still the same car and its wear is still tracked, to avoid corrupting unrelated state
        local current = GetVehiclePedIsIn(PlayerPedId(), false)
        if current ~= targetVehicle or not wear then return end

        local part = Vehicles.Parts[math.random(#Vehicles.Parts)]
        wear[part.id] = 0.0

        -- Make it visible: setting the number to 0 is enough for engine power
        if part.id == 'tyres' and tyreState and targetVehicle and DoesEntityExist(targetVehicle) then
            local idx = WHEELS[math.random(#WHEELS)]
            tyreState[tostring(idx)] = 1
            applyTyre(targetVehicle, idx)
        elseif part.id == 'engine' and targetVehicle and DoesEntityExist(targetVehicle)
               and GetIsVehicleEngineRunning(targetVehicle) then
            safe(SetVehicleEngineOn, targetVehicle, false, true, true)
            CreateThread(function()
                Wait(400)
                if DoesEntityExist(targetVehicle) then
                    safe(SetVehicleEngineOn, targetVehicle, true, true, false)
                end
            end)
        end

        TriggerEvent('bs:ui:notify', {
            type = 'danger',
            message = L('parts.debug_failed', { part = Veh.PartLabel(part) }),
            duration = 4000,
        })
    end)

    return true
end

exports('ScheduleFailure', Wear.ScheduleFailure)
