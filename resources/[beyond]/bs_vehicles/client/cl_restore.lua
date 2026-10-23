-- bs_vehicles - putting a saved car back

local restoring = false
local recent = {}       -- [plate] = when we last put this one back


-- Is a vehicle with this plate already in the world near us?
local function alreadyThere(plate)
    local handle, vehicle = FindFirstVehicle()
    local ok = true
    local found = false

    repeat
        if DoesEntityExist(vehicle) then
            if Veh.Plate(vehicle) == plate then found = true break end
        end
        ok, vehicle = FindNextVehicle(handle)
    until not ok

    EndFindVehicle(handle)
    return found
end

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 8000 do Wait(20); waited = waited + 20 end

    return HasModelLoaded(hash) and hash or nil
end

-- Rebuilds one vehicle exactly where it was.
local function restore(entry)
    local pos = entry.position
    if not pos then return false end

    if alreadyThere(entry.plate) then return true end

    local hash = loadModel(entry.model)
    if not hash then
        print(('^3[BeyondSurvival]^7 (vehicles) cannot restore %s - model "%s" is not on this build')
            :format(entry.plate, tostring(entry.model)))
        return false
    end

    -- Ground has to exist before the car does, or it falls through the void forever.
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local waited = 0
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and waited < 3000 do
        Wait(50); waited = waited + 50
    end

    -- A world spawn placed for the first time
    if entry.fresh and World and World.FindClear then
        local x, y, z, h = pos.x, pos.y, pos.z, pos.h or 0.0
        if not World.ClearAt(x, y, z - 0.3, h, hash) then
            local spot, heading = World.FindClear(x, y, z, hash, 8)
            if not spot then
                SetModelAsNoLongerNeeded(hash)
                return false
            end
            pos = { x = spot.x, y = spot.y, z = spot.z, h = heading }
        end
        TriggerServerEvent('bs:vehicles:placed', entry.plate, pos.x, pos.y, pos.z, pos.h or 0.0)
    end

    local vehicle = CreateVehicle(hash, pos.x, pos.y, pos.z, pos.h or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then return false end

    SetVehicleNumberPlateText(vehicle, entry.plate)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, false, true, false)
    SetVehicleDoorsLocked(vehicle, entry.locked and 2 or 1)
    SetVehicleFuelLevel(vehicle, (entry.fuel or 50.0) + 0.0)

    -- Crash damage is restored the same way fuel and wear are.
    SetVehicleBodyHealth(vehicle, (entry.body or 1000.0) + 0.0)
    SetVehicleEngineHealth(vehicle, (entry.engine or 1000.0) + 0.0)

    -- Wheels too: CreateVehicle always returns four perfect tyres, so shot or blown wheels must be re-applied
    if type(entry.tyres) == 'table' then
        for idx, state in pairs(entry.tyres) do
            local wheel = tonumber(idx)
            state = tonumber(state) or 0
            if wheel then
                if state >= 1 then
                    pcall(SetVehicleTyreBurst, vehicle, wheel, true, 1000.0)
                end
                if state >= 2 then
                    pcall(SetVehicleTyreFitted, vehicle, wheel, false)
                end
            end
        end
    end

    -- A saved tune goes on first: SetVehicleModKit must run before any SetVehicleMod call is honoured
    if type(entry.mods) == 'table' and next(entry.mods) then
        SetVehicleModKit(vehicle, 0)
        for modType, index in pairs(entry.mods) do
            pcall(SetVehicleMod, vehicle, tonumber(modType), tonumber(index), false)
        end
    end

    -- A stripped wreck comes back stripped (no wheels, no doors, dead). See cl_strip.lua.
    if entry.stripped and Strip then
        Strip.Apply(vehicle)
    end

    -- An exploded car comes back burnt out.
    if entry.wrecked and World then
        World.ApplyWreck(vehicle)
    end

    -- It is ours now; tell the sweep before it runs again.
    SetEntityAsMissionEntity(vehicle, true, true)
    local state = Entity(vehicle).state
    if state then
        state:set('bsVehicle', true, false)
        state:set('bsProtected', true, false)
        state:set('bsKeep', true, false)
    end

    return true
end

-- The sweep

-- Only wait between sweeps, never before the first one
CreateThread(function()
    while true do
        if restoring or not exports.bs_core:IsLoaded() then
            Wait(1000)
            goto continue
        end

        do
            local state = exports.bs_core:GetSessionState()
            if state ~= 'playing' then
                Wait(1000)
                goto continue
            end

            restoring = true

            local at = GetEntityCoords(PlayerPedId())
            local answer = BSB.Await('vehicles:around', 8000, at.x, at.y, at.z, 220.0)

            for _, entry in ipairs((answer and answer.ok and answer.vehicles) or {}) do
                -- Never twice in quick succession, whatever the server says.
                local last = recent[entry.plate] or 0
                if GetGameTimer() - last > 60000 then
                    recent[entry.plate] = GetGameTimer()

                    local ok = restore(entry)
                    TriggerServerEvent('bs:vehicles:spawned', entry.plate, ok)
                end
            end

            restoring = false
        end

        Wait(12000)
        ::continue::
    end
end)
