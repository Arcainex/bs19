-- bs_emotes - the noise a vehicle makes.
-- Sends 'horn' and 'engine' noise (weights in bs_zombies config_sectors.lua).
-- Gunfire and whistling are in cl_noise.lua and cl_actions.lua.
-- An engine is continuous, so driving is turned into a pulse every PULSE_MS;
-- that single number sets what driving costs. Speed and RPM scale what each pulse is
-- worth, not the rate.
-- Louder vehicles are a different kind (motorbike = `engine_loud`, hatchback =
-- `engine`) so both radius and weight can be priced in config.

local Vehicle = { lastPulse = 0, lastHorn = 0 }

-- How often a moving vehicle makes a noise event. Main tuning knob for driving.
local PULSE_MS  = 2600

-- A horn is deliberate; this only stops one press becoming thirty events.
local HORN_MS   = 1200

-- A slow engine can still be loud when the driver revs it.
local MOVING    = 5.0
local REV_RPM   = 0.45

-- Loud vehicles are picked by GetVehicleClass, not model, so add-ons are covered.
--   8 motorcycles, 9 off-road, 14 boats, 15 helicopters (own kind), 16 planes,
--   17 service, 18 emergency, 19 military, 20 commercial
-- Everything else is `engine`. Class 13 (bicycles) makes no engine noise.
local LOUD_CLASSES = {
    [8] = true, [9] = true, [14] = true, [17] = true,
    [18] = true, [19] = true, [20] = true,
}
local AIR_CLASSES  = { [15] = true, [16] = true }
local SILENT_CLASSES = { [13] = true }   -- bicycles

-- The noise kind for a vehicle, or nil for none.
local function kindFor(vehicle)
    local class = GetVehicleClass(vehicle)

    if SILENT_CLASSES[class] then return nil end
    if AIR_CLASSES[class]    then return 'heli' end
    if LOUD_CLASSES[class]   then return 'engine_loud' end
    return 'engine'
end

-- A dead engine makes no noise (coasting, towed, wrecked).
local function isRunning(vehicle)
    if not GetIsVehicleEngineRunning(vehicle) then return false end
    if IsEntityDead(vehicle) then return false end
    return true
end

-- The engine

CreateThread(function()
    while true do
        Wait(500)

        if not exports.bs_core:IsLoaded() then
            Wait(1500)
            goto continue
        end

        do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle == 0 or not DoesEntityExist(vehicle) then goto continue end

            -- Only the driver reports, so a full car is one engine, not four.
            if GetPedInVehicleSeat(vehicle, -1) ~= ped then goto continue end

            if not isRunning(vehicle) then goto continue end

            local kind = kindFor(vehicle)
            if not kind then goto continue end

            local speed = GetEntitySpeed(vehicle)
            local rpm = math.max(0.0, math.min(1.0, GetVehicleCurrentRpm(vehicle)))

            if kind ~= 'heli' and speed < MOVING and rpm < REV_RPM then goto continue end

            local now = GetGameTimer()
            if now - Vehicle.lastPulse < PULSE_MS then goto continue end
            Vehicle.lastPulse = now

            -- RPM also carries stationary revving; idle stays quiet.
            local base = Emotes.Noise[kind] or 120.0
            local rev = math.max(0.0, (rpm - 0.2) / 0.8)
            local scale = math.min(1.0, math.max(speed >= MOVING and (0.45 + speed / 40.0) or 0.0, rev))
            if kind == 'heli' then scale = 1.0 end

            Noise.Make(kind, GetEntityCoords(vehicle), base * scale)
        end

        ::continue::
    end
end)

-- The horn

-- 86 is INPUT_VEH_HORN. IsControlPressed on purpose: holding the horn keeps
-- drawing walkers. The cooldown limits the event rate.
CreateThread(function()
    while true do
        Wait(150)

        if exports.bs_core:IsLoaded() then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and DoesEntityExist(vehicle)
               and GetPedInVehicleSeat(vehicle, -1) == ped
               and IsControlPressed(0, 86)
               and not SILENT_CLASSES[GetVehicleClass(vehicle)] then

                local now = GetGameTimer()
                if now - Vehicle.lastHorn >= HORN_MS then
                    Vehicle.lastHorn = now
                    Noise.Make('horn', GetEntityCoords(vehicle))
                end
            end
        else
            Wait(1500)
        end
    end
end)

-- For the diagnostics command.
exports('VehicleNoiseKind', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return kindFor(vehicle)
end)
