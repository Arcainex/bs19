-- bs_vehicles - the car on the alt dot

-- Lock state, published as a state bag (Entity(veh).state.bsLocked)

-- [plate] = true/false
local ownedByPlate = {}

CreateThread(function()
    while true do
        Wait(1200)

        if exports.bs_core:IsLoaded() then
            local ped = PlayerPedId()
            local at = GetEntityCoords(ped)

            local vehicle = GetClosestVehicle(at.x, at.y, at.z, 12.0, 0, 71)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                local plate = Veh.Plate(vehicle)
                local state = Entity(vehicle).state

                if plate and state then
                    local locked = Veh.IsLocked(plate)
                    if state.bsLocked ~= locked then
                        state:set('bsLocked', locked, false)
                    end

                    -- Ownership is published through a state bag the same way as the lock (bs_interactions knows nothing about plates)
                    if ownedByPlate[plate] == nil then
                        ownedByPlate[plate] = false     -- claim it, so a slow
                                                        -- answer is not asked for twice
                        local info = Veh.State(vehicle)
                        if info then
                            ownedByPlate[plate] = info.owned and true or false
                        else
                            ownedByPlate[plate] = nil   -- no answer: ask again
                        end
                    end

                    local owned = ownedByPlate[plate] == true
                    if state.bsOwned ~= owned then
                        state:set('bsOwned', owned, false)
                    end
                end
            end
        end
    end
end)

-- What each option does
-- One handler per event name. bs_interactions fires these with a payload carrying the entity that was under the dot.

local busy = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 2800 })
end

-- Wraps a handler so two of them can never overlap
local function handler(fn)
    return function(payload)
        if busy then return end
        if not payload or not payload.entity or not DoesEntityExist(payload.entity) then return end

        busy = true
        local ok, err = pcall(fn, payload.entity)
        busy = false

        if not ok then
            print(('^1[BeyondSurvival]^7 (vehicles) dot option failed: %s'):format(tostring(err)))
        end
    end
end

local function setLock(vehicle, wanted)
    local plate = Veh.Plate(vehicle)
    if not plate then return end

    local result = BSB.Await('vehicles:lock', 6000, plate, wanted)

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.wont_budge'))
    end

    -- A lock with no sign of it is indistinguishable from one that did nothing.
    if DoesEntityExist(vehicle) then
        SetVehicleLights(vehicle, 2)
        Wait(140)
        SetVehicleLights(vehicle, 0)

        local state = Entity(vehicle).state
        if state then state:set('bsLocked', result.locked and true or false, false) end
    end

    notify(result.locked and 'info' or 'success',
        result.locked and L('radial.locked_msg') or L('common.unlocked'), 1800)
end

AddEventHandler('bs:vehicles:dot:unlock', handler(function(vehicle)
    setLock(vehicle, false)
end))

AddEventHandler('bs:vehicles:dot:lock', handler(function(vehicle)
    setLock(vehicle, true)
end))

AddEventHandler('bs:vehicles:dot:trunk', handler(function(vehicle)
    local plate = Veh.Plate(vehicle)
    if not plate then return end

    local result = BSB.Await('vehicles:trunk', 6000, plate)
    if not (result and result.ok) then
        notify('warn', (result and result.error) or L('radial.wont_open'))
    else
        if DoesEntityExist(vehicle) then SetVehicleDoorOpen(vehicle, 5, false, false) end
        CreateThread(function()
            local eventHandler
            eventHandler = AddEventHandler('bs:ui:closed', function(panel)
                if panel ~= 'inventory' then return end
                if DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, 5, false) end
                RemoveEventHandler(eventHandler)
            end)
        end)
    end
end))

AddEventHandler('bs:vehicles:dot:refuel', handler(function(vehicle)
    Fuel.Pour(vehicle)
end))

AddEventHandler('bs:vehicles:dot:diagnose', handler(function(vehicle)
    local parts = Wear.Diagnose(vehicle)
    if not parts then
        return notify('warn', L('radial.cant_look'))
    end

    local lines, absent = {}, {}
    for _, id in ipairs(parts.missing or {}) do absent[id] = true end
    for _, part in ipairs(Vehicles.Parts) do
        local value = math.floor(parts[part.id] or 100)
        local state = value <= part.fail and L('cond.gone')
            or value <= part.warn and L('cond.poor')
            or value < 85 and L('cond.worn') or L('cond.good')
        lines[#lines + 1] = absent[part.id] and ('%s: %s'):format(Veh.PartLabel(part), L('radial.missing'))
            or ('%s %d%% (%s)'):format(Veh.PartLabel(part), value, state)
    end

    notify('info', table.concat(lines, '  |  '), 9000)
end))

AddEventHandler('bs:vehicles:dot:hotwire', handler(function(vehicle)
    Keys.Hotwire(vehicle)
end))

AddEventHandler('bs:vehicles:dot:fit', handler(function(vehicle)
    World.FitAny(vehicle)
end))

AddEventHandler('bs:vehicles:dot:wheel', function()
    -- Not wrapped: the wheel manages its own blocking, and it must be able to open even while something else is mid-animation
    exports.bs_vehicles:OpenWheel()
end)

-- Registering them

CreateThread(function()
    -- bs_interactions may start after us
    local waited = 0
    while GetResourceState('bs_interactions') ~= 'started' and waited < 20000 do
        Wait(500); waited = waited + 500
    end

    if GetResourceState('bs_interactions') ~= 'started' then
        return print('^3[BeyondSurvival]^7 (vehicles) bs_interactions never started - no dot options')
    end

    local ok, err = pcall(function()
        exports.bs_interactions:AddType('vehicle', {
            {
                label = L('target.unlock'), labelKey = 'target.unlock',
                icon  = 'unlock',
                event = 'bs:vehicles:dot:unlock',
                filters = { onFoot = true, maxDistance = 3.2, stateTrue = 'bsLocked' },
            },
            {
                label = L('target.lock'), labelKey = 'target.lock',
                icon  = 'lock',
                event = 'bs:vehicles:dot:lock',
                filters = { onFoot = true, maxDistance = 3.2, stateFalse = 'bsLocked' },
            },
            {
                label = L('target.open_boot'), labelKey = 'target.open_boot',
                icon  = 'trunk',
                event = 'bs:vehicles:dot:trunk',
                -- Behind the car only
                filters = { onFoot = true, behind = true, maxDistance = 3.2 },
            },
            {
                label = L('target.pour'), labelKey = 'target.pour',
                icon  = 'fuel',
                event = 'bs:vehicles:dot:refuel',
                filters = { onFoot = true, maxDistance = 3.2 },
            },
            {
                label = L('target.look'), labelKey = 'target.look',
                icon  = 'wrench',
                event = 'bs:vehicles:dot:diagnose',
                filters = { onFoot = true, maxDistance = 3.2 },
            },
            {
                label = L('target.fit'), labelKey = 'target.fit',
                icon  = 'wrench',
                event = 'bs:vehicles:dot:fit',
                filters = { onFoot = true, maxDistance = 3.2 },
            },
            {
                label = L('target.force'), labelKey = 'target.force',
                icon  = 'key',
                event = 'bs:vehicles:dot:hotwire',
                filters = { onFoot = true, maxDistance = 3.0, stateTrue = 'bsLocked' },
            },
            {
                label = L('target.all'), labelKey = 'target.all',
                icon  = 'gear',
                event = 'bs:vehicles:dot:wheel',
                filters = { onFoot = true, maxDistance = 3.2 },
            },
        })
    end)

    if ok then
        print('^2[BeyondSurvival]^7 (vehicles) dot options registered')
    else
        print(('^1[BeyondSurvival]^7 (vehicles) could not register dot options: %s'):format(tostring(err)))
    end
end)
