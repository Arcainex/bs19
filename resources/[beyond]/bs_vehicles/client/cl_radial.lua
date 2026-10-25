-- bs_vehicles - vehicle wheel (U key). Everything you do to a car you are not driving.

local busy = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 3000 })
end

-- Doing things

local function toggleLock(plate)
    local result = BSB.Await('vehicles:lock', 6000, plate)

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.wont_budge'))
    end

    -- Locking needs visible feedback, otherwise it looks like nothing happened.
    local vehicle = Veh.Nearby(Vehicles.Settings.lockRange or 8.0)
    if vehicle and DoesEntityExist(vehicle) then
        SetVehicleLights(vehicle, 2)
        Wait(140)
        SetVehicleLights(vehicle, 0)
        PlayVehicleDoorCloseSound(vehicle, 0)
    end

    notify(result.locked and 'info' or 'success',
        result.locked and L('radial.locked_msg') or L('common.unlocked'), 1800)
end

local function claim(vehicle)
    local plate = Veh.Plate(vehicle)
    local result = BSB.Await('vehicles:claim', 8000, plate, Veh.ModelName(vehicle))

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.cant_take'))
    end

    Veh.current = result.vehicle
    notify('success', L('veh.claimed', { plate = plate }), 4000)
end

local function repairPart(vehicle, plate, partId, label)
    local ped = PlayerPedId()
    local dict = 'mini@repair'
    local opened = DoesEntityExist(vehicle)
    if opened then SetVehicleDoorOpen(vehicle, 4, false, false) end -- bonnet

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'fixing_a_ped', 4.0, -4.0,
            Vehicles.Settings.repairTime or 12000, 1, 0.0, false, false, false)
    end

    Wait(Vehicles.Settings.repairTime or 12000)
    ClearPedTasks(ped)
    if opened and DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, 4, false) end

    local result = BSB.Await('vehicles:repair', 8000, plate, partId)

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.wont_go_back'))
    end

    -- The car beside us may be the car we are in
    if Veh.current and Veh.current.plate == plate then
        Veh.current.parts = result.parts
    end
    if Wear and Wear.Apply then Wear.Apply(result.parts) end

    notify('success', L('veh.maxed', { name = label }), 3200)
end

-- Repair does every broken part in one visit
local function repairAll(vehicle, plate, count)
    local ped = PlayerPedId()
    local dict = 'mini@repair'
    local opened = DoesEntityExist(vehicle)
    if opened then SetVehicleDoorOpen(vehicle, 4, false, false) end

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    -- A whole car takes longer over the bonnet than one part does.
    local time = (Vehicles.Settings.repairTime or 12000) * math.min(3, math.max(1, count))
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'fixing_a_ped', 4.0, -4.0, time, 1, 0.0, false, false, false)
    end

    Wait(time)
    ClearPedTasks(ped)
    if opened and DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, 4, false) end

    local result = BSB.Await('vehicles:repairAll', 10000, plate)

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.wont_go_back'))
    end

    if Veh.current and Veh.current.plate == plate then
        Veh.current.parts = result.parts
    end
    if Wear and Wear.Apply then Wear.Apply(result.parts) end

    notify('success', L('radial.fixed', { n = result.fixed or 0 }), 3200)
end

local function scrap(vehicle)
    Scrap.Run(vehicle)
end

-- Rougher, faster patch for an already failed part (see Vehicles.Settings.tempFixTime)
local function tempFixPart(vehicle, plate, partId, label)
    local ped = PlayerPedId()
    local dict = 'mini@repair'
    local opened = DoesEntityExist(vehicle)
    if opened then SetVehicleDoorOpen(vehicle, 4, false, false) end -- bonnet

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'fixing_a_ped', 4.0, -4.0,
            Vehicles.Settings.tempFixTime or 7000, 1, 0.0, false, false, false)
    end

    Wait(Vehicles.Settings.tempFixTime or 7000)
    ClearPedTasks(ped)
    if opened and DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, 4, false) end

    local result = BSB.Await('vehicles:tempfix', 8000, plate, partId)

    if not result or not result.ok then
        return notify('warn', (result and result.error) or L('radial.cant_patch'))
    end

    if Veh.current and Veh.current.plate == plate then
        Veh.current.parts = result.parts
    end
    if Wear and Wear.Apply then Wear.Apply(result.parts) end

    if result.success then
        notify('success', L('veh.patched', { name = label }), 3800)
    else
        notify('warn', L('veh.patch_failed', { name = label }), 3800)
    end
end

local function diagnose(vehicle)
    local parts = Wear.Diagnose(vehicle)
    if not parts then return notify('warn', L('radial.cant_look')) end

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
end

-- Doors, windows, engine, seats: the mechanical half of the wheel

-- Door index to label. 4 is the bonnet, 5 is the boot.
local DOORS = {
    { id = 0, label = 'door.driver_door',     icon = 'car_door' },
    { id = 1, label = 'door.passenger_door',  icon = 'car_door' },
    { id = 2, label = 'door.rear_left',       icon = 'car_door' },
    { id = 3, label = 'door.rear_right',      icon = 'car_door' },
    { id = 4, label = 'door.bonnet',          icon = 'bonnet' },
    { id = 5, label = 'door.boot_lid',        icon = 'boot_lid' },
}

local function toggleDoor(vehicle, door)
    if not DoesEntityExist(vehicle) then return end

    -- Door open state is unreliable across vehicles, but the angle ratio works: anything above a crack counts as open
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.1 then
        SetVehicleDoorShut(vehicle, door, false)
    else
        SetVehicleDoorOpen(vehicle, door, false, false)
    end
end

local function toggleWindows(vehicle)
    if not DoesEntityExist(vehicle) then return end

    -- The engine does not report rolled-down windows, so it is tracked on the entity (state bags survive streaming)
    local state = Entity(vehicle).state
    local down = state and state.bsWindowsDown

    for window = 0, 3 do
        if down then
            SetVehicleWindowTint(vehicle, GetVehicleWindowTint(vehicle))
            RollUpWindow(vehicle, window)
        else
            RollDownWindow(vehicle, window)
        end
    end

    if state then state:set('bsWindowsDown', not down, false) end
    return not down
end

local function toggleEngine(vehicle)
    local running = GetIsVehicleEngineRunning(vehicle)
    SetVehicleEngineOn(vehicle, not running, false, true)
    return not running
end

-- Move across without getting out; only into an empty seat.
local function swapSeat(vehicle)
    local ped = PlayerPedId()

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(ped, vehicle, seat)
            return true
        end
    end

    return false
end

-- Building the wheel

local function openWheel()
    if busy then return end

    if GetResourceState('bs_radial') ~= 'started' then
        return notify('warn', L('veh.no_radial'))
    end

    local vehicle = Veh.Nearby(Vehicles.Settings.lockRange or 8.0)
    if not vehicle then
        return notify('info', L('radial.no_vehicle'), 2400)
    end

    local state = Veh.State(vehicle)
    if not state then
        return notify('warn', L('radial.unknown'), 3000)
    end

    local plate = state.plate
    local inside = GetVehiclePedIsIn(PlayerPedId(), false) == vehicle
    local items = {}

    -- Lock / unlock.
    items[#items + 1] = {
        id       = 'lock',
        label    = state.locked and L('target.unlock') or L('target.lock'),
        icon     = state.locked and 'unlock' or 'lock',
        disabled = not state.key,
        note     = state.key and plate or L('radial.no_key'),
    }

    -- The boot.
    items[#items + 1] = {
        id       = 'trunk',
        label    = L('radial.boot'),
        icon     = 'trunk',
        disabled = state.locked and not state.key,
        note     = (state.locked and not state.key) and L('radial.locked') or L('radial.boot_note'),
    }

    -- Fuel.
    items[#items + 1] = {
        id       = 'refuel',
        label    = L('radial.refuel'),
        icon     = 'refuel',
        disabled = inside or (state.fuel or 0) >= 99.5,
        note     = inside and L('radial.not_inside')
            or L('radial.in_tank', { pct = math.floor(state.fuel or 0) }),
    }

    -- Siphoning: only on an unowned car worth draining. No item or cash needed (see Fuel.Siphon).
    do
        local canSiphon = (not state.owned) and (state.fuel or 0) > 5.0
        if canSiphon then
            items[#items + 1] = {
                id    = 'siphon',
                label = L('radial.siphon'),
                icon  = 'siphon',
                note  = L('radial.unowned_tank', { pct = math.floor(state.fuel or 0) }),
            }
        end
    end

    -- Diagnosing, and what it leads to.
    items[#items + 1] = {
        id       = 'diagnose',
        label    = L('target.look'),
        icon     = 'inspect_car',
        disabled = inside,
        note     = inside and L('radial.get_out') or L('radial.diag_note'),
    }

    -- Parts that are not there at all (world spawns start without battery, spark plug and fuel tank).
    if World and not state.wrecked then
        local fits = {}
        for _, def in ipairs(World.MissingLabels(state)) do
            fits[#fits + 1] = {
                id = 'fit:' .. def.id, label = Veh.PartLabel(def),
                icon = def.id == 'battery' and 'battery' or (def.id == 'fueltank' and 'refuel' or 'wrench'),
                note = L('radial.missing'),
                danger = true,
            }
        end
        if #fits > 0 then
            items[#items + 1] = {
                id = 'fit', label = L('radial.fit_parts'), icon = 'wrench', title = L('radial.fit_title'),
                note = L('radial.n_missing', { n = #fits }),
                disabled = inside,
                submenu = fits,
            }
        end
    end

    -- Repairs: one slice per part that is not fine, so the wheel shrinks as the car improves.
    local repairs = {}
    for _, part in ipairs(Vehicles.Parts) do
        local value = math.floor((state.parts and state.parts[part.id]) or 100)
        if value < 99 then
            repairs[#repairs + 1] = {
                id    = 'fix:' .. part.id,
                label = Veh.PartLabel(part),
                icon  = part.id == 'tyres' and 'tyre'
                    or part.id == 'battery' and 'battery'
                    or part.id == 'engine' and 'engine' or 'wrench',
                note  = ('%d%%'):format(value),
                danger = value <= (part.fail or 0),
            }
        end
    end

    -- If more than one part is broken, offer a fix-all first.
    if #repairs > 1 then
        table.insert(repairs, 1, {
            id    = 'fixall',
            label = L('radial.repair_all'),
            icon  = 'repair_all',
            note  = L('radial.fixall_note', { n = #repairs }),
        })
    end

    if #repairs > 0 then
        items[#items + 1] = {
            id      = 'repair',
            label   = L('radial.repair'),
            icon    = 'repair_all',
            title   = L('radial.repair_title'),
            note    = L('radial.to_fix', { n = #repairs }),
            disabled = inside,
            submenu = repairs,
        }
    end

    -- Temporary fixes: one slice per part that has failed (not merely worn)
    local tempfixes = {}
    for _, part in ipairs(Vehicles.Parts) do
        local value = math.floor((state.parts and state.parts[part.id]) or 100)
        if value <= (part.fail or 0) then
            tempfixes[#tempfixes + 1] = {
                id    = 'tempfix:' .. part.id,
                label = Veh.PartLabel(part),
                icon  = part.id == 'tyres' and 'tyre'
                    or part.id == 'battery' and 'battery'
                    or part.id == 'engine' and 'engine' or 'wrench',
                note  = L('radial.rough'),
            }
        end
    end

    if #tempfixes > 0 then
        items[#items + 1] = {
            id      = 'tempfix',
            label   = L('radial.tempfix'),
            icon    = 'duct_tape',
            title   = L('radial.tempfix_title'),
            note    = L('radial.failed_n', { n = #tempfixes }),
            disabled = inside,
            submenu = tempfixes,
        }
    end

    -- Doors are a submenu to keep the wheel short
    local doorSlices = {}
    for _, door in ipairs(DOORS) do
        doorSlices[#doorSlices + 1] = {
            id    = 'door:' .. door.id,
            label = L(door.label),
            icon  = door.icon,
            note  = L('radial.open_shut'),
        }
    end

    items[#items + 1] = {
        id       = 'doors',
        label    = L('radial.doors'),
        icon     = 'car_door',
        title    = L('radial.doors_title'),
        note     = L('radial.door_note'),
        disabled = state.locked and not state.key,
        submenu  = doorSlices,
    }

    items[#items + 1] = {
        id    = 'windows',
        label = L('radial.windows'),
        icon  = 'window',
        note  = L('radial.up_down'),
        disabled = state.locked and not state.key,
    }

    if inside then
        items[#items + 1] = {
            id    = 'engine',
            label = GetIsVehicleEngineRunning(vehicle) and L('radial.kill_engine') or L('radial.start_it'),
            icon  = 'ignition',
            note  = GetIsVehicleEngineRunning(vehicle) and L('radial.quiet') or L('radial.noise'),
        }

        items[#items + 1] = {
            id    = 'seat',
            label = L('radial.move'),
            icon  = 'seat_swap',
            note  = L('radial.no_exit'),
        }
    end

    -- Ownership.
    if not state.owned then
        items[#items + 1] = {
            id    = 'claim',
            label = L('radial.claim'),
            icon  = 'claim',
            note  = L('radial.claim_note'),
        }
    elseif state.mine then
        items[#items + 1] = {
            id    = 'keys',
            label = L('radial.give_key'),
            icon  = 'key_give',
            note  = L('radial.give_note'),
        }
    end

    -- Strip: last and marked destructive
    items[#items + 1] = {
        id       = 'scrap',
        label    = L('radial.strip'),
        icon     = 'strip',
        danger   = true,
        disabled = inside or state.scrapped or (state.owned and not state.mine),
        note     = inside and L('radial.get_out')
            or state.scrapped and L('radial.stripped')
            or (state.owned and not state.mine) and L('radial.others')
            or L('radial.strip_note'),
    }

    local picked = BSB.Radial({
        title = plate,
        items = items,
    })

    if not picked then return end

    busy = true
    CreateThread(function()
        if picked == 'lock' then
            toggleLock(plate)

        elseif picked == 'trunk' then
            local result = BSB.Await('vehicles:trunk', 6000, plate)
            if not (result and result.ok) then
                notify('warn', (result and result.error) or L('radial.wont_open'))
            else
                -- Open the boot lid while the container is open and close it when the inventory panel closes.
                local veh = vehicle
                if DoesEntityExist(veh) then SetVehicleDoorOpen(veh, 5, false, false) end
                CreateThread(function()
                    local handler
                    handler = AddEventHandler('bs:ui:closed', function(panel)
                        if panel ~= 'inventory' then return end
                        if DoesEntityExist(veh) then SetVehicleDoorShut(veh, 5, false) end
                        RemoveEventHandler(handler)
                    end)
                end)
            end

        elseif picked == 'refuel' then
            Fuel.Pour(vehicle)

        elseif picked == 'siphon' then
            Fuel.Siphon(vehicle)

        elseif picked == 'diagnose' then
            diagnose(vehicle)

        elseif picked == 'claim' then
            claim(vehicle)

        elseif picked == 'keys' then
            Keys.GiveNearest(plate)

        elseif picked == 'scrap' then
            scrap(vehicle)

        elseif picked == 'windows' then
            local down = toggleWindows(vehicle)
            notify('info', down and L('radial.win_down') or L('radial.win_up'), 1800)

        elseif picked == 'engine' then
            local running = toggleEngine(vehicle)
            notify(running and 'success' or 'info',
                running and L('radial.running') or L('radial.engine_off'), 1800)

        elseif picked == 'seat' then
            if not swapSeat(vehicle) then
                notify('warn', L('radial.nowhere'), 2200)
            end

        else
            local doorId = picked:match('^door:(%d+)$')
            if doorId then
                toggleDoor(vehicle, tonumber(doorId))
                busy = false
                return
            end

            if picked == 'fixall' then
                local count = 0
                for _, part in ipairs(Vehicles.Parts) do
                    local value = math.floor((state.parts and state.parts[part.id]) or 100)
                    if value < 99 then count = count + 1 end
                end
                repairAll(vehicle, plate, count)
            end

            local fitId = picked:match('^fit:(.+)$')
            if fitId and World then World.Fit(vehicle, fitId) end

            local partId = picked:match('^fix:(.+)$')
            if partId then
                local def
                for _, part in ipairs(Vehicles.Parts) do
                    if part.id == partId then def = part break end
                end
                if def then repairPart(vehicle, plate, partId, def.label) end
            end

            local tempId = picked:match('^tempfix:(.+)$')
            if tempId then
                local def
                for _, part in ipairs(Vehicles.Parts) do
                    if part.id == tempId then def = part break end
                end
                if def then tempFixPart(vehicle, plate, tempId, def.label) end
            end
        end

        busy = false
    end)
end

RegisterCommand(Vehicles.Radial.command, function()
    -- Text typed into another NUI must never open vehicle actions.
    if IsNuiFocused() then return end
    CreateThread(openWheel)
end, false)

RegisterKeyMapping(Vehicles.Radial.command, L('radial.keymap'),
    'keyboard', Vehicles.Radial.key)

exports('OpenWheel', function() CreateThread(openWheel) end)
