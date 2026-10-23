-- bs_vehicles - the vehicle you are standing next to

Veh = {
    current = nil,      -- record for the vehicle you are in or beside
    plate = nil,
    inside = false,
}

local locked = {}       -- [plate] = boolean, mirrored from the server

-- Finding a vehicle

function Veh.Plate(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return nil end
    plate = plate:gsub('%s+', ''):upper()
    return plate ~= '' and plate or nil
end

function Veh.ModelName(vehicle)
    local model = BS.Util.ModelOf(vehicle)
    if not model then return 'unknown' end
    local name = GetDisplayNameFromVehicleModel(model)
    return (name and name ~= '' and name ~= 'CARNOTFOUND') and name or 'unknown'
end

--- The vehicle you are in, or the nearest one you could reach.
--- @return number|nil vehicle
function Veh.Nearby(range)
    local ped = PlayerPedId()

    local inside = GetVehiclePedIsIn(ped, false)
    if inside and inside ~= 0 then return inside end

    local at = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(at.x, at.y, at.z, range or 6.0, 0, 71)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end

    return nil
end

-- Server state

-- Reads a vehicle's record from the server, registering it if new. Returns plain data only.
function Veh.State(vehicle)
    local plate = Veh.Plate(vehicle)
    if not plate then return nil end

    local result = BSB.Await('vehicles:state', 6000, plate, Veh.ModelName(vehicle))
    if not result or not result.ok then return nil end

    locked[plate] = result.vehicle.locked
    return result.vehicle
end

RegisterNetEvent('bs:vehicles:lockState', function(plate, isLocked)
    if type(plate) ~= 'string' then return end
    locked[plate] = isLocked and true or false
end)

function Veh.IsLocked(plate) return locked[plate] == true end

-- Locks are re-applied every frame on nearby vehicles

CreateThread(function()
    while true do
        Wait(900)

        if exports.bs_core:IsLoaded() then
            local ped = PlayerPedId()
            local at = GetEntityCoords(ped)

            local vehicle = GetClosestVehicle(at.x, at.y, at.z, 25.0, 0, 71)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                local plate = Veh.Plate(vehicle)
                if plate and locked[plate] ~= nil then
                    -- 2 = locked for everyone, 1 = unlocked. Other values behave unpredictably.
                    SetVehicleDoorsLocked(vehicle, locked[plate] and 2 or 1)
                end
            end
        end
    end
end)

-- Protect a vehicle from the world sweep bs_world empties the streets

local asked = {}    -- [plate] = last time we asked the server

local function protect(vehicle, plate)
    if not DoesEntityExist(vehicle) then return end

    local state = Entity(vehicle).state
    if not state then return end

    -- server-protected entities (event convoys) are never downgraded here
    if state.bsConvoy then return end

    state:set('bsVehicle', true, false)

    local last = asked[plate] or 0
    if GetGameTimer() - last < 30000 then return end
    asked[plate] = GetGameTimer()

    CreateThread(function()
        local answer = BSB.Await('vehicles:keep', 6000, plate)
        if not DoesEntityExist(vehicle) then return end

        local keep = answer and answer.ok and answer.keep

        local s = Entity(vehicle).state
        if s and not s.bsConvoy then
            s:set('bsProtected', keep and true or false, false)
            s:set('bsKeep', keep and true or false, false)
        end

        if keep then
            -- The engine's own population cleanup is separate from ours and does not read state bags.
            SetEntityAsMissionEntity(vehicle, true, true)
            SetVehicleIsStolen(vehicle, false)
        end
    end)
end

CreateThread(function()
    while true do
        Wait(4000)

        if exports.bs_core:IsLoaded() then
            local ped = PlayerPedId()
            local at = GetEntityCoords(ped)

            -- Only vehicles close enough to matter; sweeping the whole pool every four seconds is wasted work
            local vehicle = GetClosestVehicle(at.x, at.y, at.z, 40.0, 0, 71)
            if vehicle and vehicle ~= 0 then
                local plate = Veh.Plate(vehicle)
                if plate then protect(vehicle, plate) end
            end
        end
    end
end)

-- Which vehicle am I in?

CreateThread(function()
    while true do
        Wait(750)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle and vehicle ~= 0 then
            local plate = Veh.Plate(vehicle)

            if plate ~= Veh.plate then
                Veh.plate = plate
                Veh.inside = true
                Veh.current = Veh.State(vehicle)
                TriggerEvent('bs:vehicles:entered', Veh.current, vehicle)
            end
        elseif Veh.inside then
            Veh.inside = false
            local was = Veh.current
            TriggerEvent('bs:vehicles:left', was)

            -- No automatic locking: a car's lock state changes only on an explicit action

            Veh.plate = nil
            Veh.current = nil
        end
    end
end)

exports('Nearby', function(range) return Veh.Nearby(range) end)
exports('PlateOf', function(vehicle) return Veh.Plate(vehicle) end)
exports('Current', function() return Veh.current end)


-- Part and item names in the player's language, config label as fallback.
function Veh.PartLabel(def)
    if not def then return '' end
    local key = 'part.' .. tostring(def.id)
    local text = L(key)
    return text ~= key and text or (def.label or tostring(def.id))
end

function Veh.ItemLabel(item)
    local ok, label = pcall(function() return exports.bs_inventory:ItemLabel(item) end)
    if ok and type(label) == 'string' and label ~= '' then return label end
    return (tostring(item):gsub('_', ' '))
end
