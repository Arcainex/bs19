-- bs_vehicles - a stripped car stays as a hulk (no wheels, doors, bonnet, dead battery) for

local WHEELS = { 0, 1, 4, 5 }
local DOORS  = { 0, 1, 2, 3, 4, 5 }   -- front/back doors, bonnet(4), boot(5)

-- Applies the stripped look
local function applyStripped(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    for _, idx in ipairs(WHEELS) do
        pcall(SetVehicleTyreFitted, vehicle, idx, false)
    end
    for _, idx in ipairs(DOORS) do
        pcall(SetVehicleDoorBroken, vehicle, idx, true)
    end

    pcall(SetVehicleEngineOn, vehicle, false, true, true)
    pcall(SetVehicleUndriveable, vehicle, true)
    pcall(SetVehicleDoorsLocked, vehicle, 1)
end

Strip = { Apply = applyStripped }

-- A plate was just stripped; if its entity is near us, update it now instead of waiting for the next restore pass
RegisterNetEvent('bs:vehicles:scrapped', function(plate)
    if type(plate) ~= 'string' then return end

    local handle, vehicle = FindFirstVehicle()
    local ok = true
    repeat
        if DoesEntityExist(vehicle) and Veh.Plate(vehicle) == plate then
            applyStripped(vehicle)
            break
        end
        ok, vehicle = FindNextVehicle(handle)
    until not ok
    EndFindVehicle(handle)
end)

exports('ApplyStripped', applyStripped)
