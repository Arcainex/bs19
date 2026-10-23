-- bs_world - removes ambient traffic and pedestrians

local sweeping = false

-- Wrapped in pcall: one mistyped or removed native would otherwise kill this thread and silently restore full traffic
local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print(('^3[BeyondSurvival]^7 (world) skipping unavailable native: %s'):format(tostring(err)))
    end
    return ok
end

CreateThread(function()
    if not World.Population.enabled then return end

    local p = World.Population

    while true do
        Wait(0)

        SetVehicleDensityMultiplierThisFrame(p.vehicleDensity)
        SetRandomVehicleDensityMultiplierThisFrame(p.vehicleDensity)
        SetParkedVehicleDensityMultiplierThisFrame(p.keepParkedCars and (p.parkedDensity or 1.0) or 0.0)
        SetPedDensityMultiplierThisFrame(p.pedDensity)
        SetScenarioPedDensityMultiplierThisFrame(p.scenarioDensity, p.scenarioDensity)

        -- Density multipliers only stop new spawns
        safe(SetPedPopulationBudget, 0)
        safe(SetVehiclePopulationBudget, 0)

        -- Garbage trucks, planes and boats have their own spawn paths.
        SetGarbageTrucks(false)
        SetRandomBoats(false)
        SetCreateRandomCops(false)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)

        if p.disableAmbient then
            SetAmbientVehicleRangeMultiplierThisFrame(0.0)
        end
    end
end)

-- One-off switches: set once, no need to loop
CreateThread(function()
    if not World.Population.enabled then return end

    local p = World.Population

    Wait(2000)

    safe(SetAllLowPriorityVehicleGeneratorsActive, false)
    safe(SetDistantCarsEnabled, false)
    safe(DistantCopCarSirens, false)

    -- Scenario peds/vehicles use their own spawn path that density does not cover
    safe(SetAudioFlag, 'PoliceScannerDisabled', true)
    safe(SetFarDrawVehicles, false)

    for _, name in ipairs(World.Population.scenarioTypes or {}) do
        safe(SetScenarioTypeEnabled, name, false)
    end

    for _, name in ipairs(World.Population.scenarioGroups or {}) do
        safe(SetScenarioGroupEnabled, name, false)
    end

    -- Interior audio emitters (bars, clubs, shops) run forever on an empty map, so they are switched off, one native per emitter
    for _, name in ipairs(World.Environment.silenceEmitters or {}) do
        safe(SetStaticEmitterEnabled, name, false)
    end

    -- -1 means the engine decides
    if p.keepParkedCars then
        safe(SetNumberOfParkedVehicles, p.parkedLimit or 30)
    else
        safe(SetNumberOfParkedVehicles, 0)
    end
end)

--- Emergency dispatch and the wanted system.
CreateThread(function()
    if not World.Population.enabled then return end

    if World.Population.disableDispatch then
        for service = 1, 15 do
            safe(EnableDispatchService, service, false)
        end
    end

    while true do
        Wait(500)

        if World.Population.disableWanted then
            local player = PlayerId()
            ClearPlayerWantedLevel(player)
            SetPlayerWantedLevel(player, 0, false)
            SetPlayerWantedLevelNow(player, false)
            SetMaxWantedLevel(0)
        end
    end
end)

-- Sweep: density multipliers stop most spawning, but the streamer still places peds and cars

local function isPlayerVehicle(vehicle)
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle then return true end
        if IsPedInAnyVehicle(ped, true) and GetVehiclePedIsIn(ped, true) == vehicle then return true end
    end
    return false
end

local function nearAnyPlayer(coords, radius)
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 and #(GetEntityCoords(ped) - coords) < radius then return true end
    end
    return false
end

-- Pool full (size 256) fix
local PURGE_BUDGET = 40

--- @return boolean gone  true when the entity is actually no longer there
local function purge(entity, isVehicle)
    if not DoesEntityExist(entity) then return true end

    -- Rule 1. A networked entity we do not own cannot be deleted, and tagging it would waste a slot.
    if NetworkGetEntityIsNetworked(entity) then
        if not NetworkHasControlOfEntity(entity) then
            NetworkRequestControlOfEntity(entity)
            if not NetworkHasControlOfEntity(entity) then return false end
        end
    end

    SetEntityAsMissionEntity(entity, true, true)

    if isVehicle then
        DeleteVehicle(entity)
    else
        DeleteEntity(entity)
    end

    -- Rule 2. Still there means the registration is still held, so hand it back.
    if DoesEntityExist(entity) then
        safe(SetEntityAsNoLongerNeeded, entity)
        return false
    end

    return true
end

-- The sweep is a backstop, not a heartbeat
local sweepIdleStreak = 0

CreateThread(function()
    if not (World.Population.enabled and World.Population.sweepEnabled) then return end

    local p = World.Population

    while true do
        -- Three empty passes in a row before standing down, because the streamer arrives in bursts.
        local idle = sweepIdleStreak >= (p.sweepIdleAfter or 3)
        Wait(idle and (p.sweepIdleInterval or 60000) or p.sweepInterval)

        if sweeping then goto continue end

        -- Skip while the character screen is up; the player is not in the world yet.
        if GetResourceState('bs_core') == 'started' then
            local ok, state = pcall(function() return exports.bs_core:GetSessionState() end)
            if ok and state ~= 'playing' then goto continue end
        end

        sweeping = true

        -- Vehicles are emptied, stopped and made harmless before deletion

        -- Rule 3: one budget shared by both loops.
        local budget = PURGE_BUDGET

        -- Vehicles first, with their occupants.
        for vehicle in EnumerateVehicles() do
            if budget <= 0 then break end
            -- Owned vehicles are not litter. bs_vehicles marks registered vehicles bsProtected
            local vstate = DoesEntityExist(vehicle) and Entity(vehicle).state or nil
            local owned = vstate and (vstate.bsConvoy or vstate.bsProtected or vstate.bsKeep or vstate.bsVehicle)

            if DoesEntityExist(vehicle) and not owned and not isPlayerVehicle(vehicle) then
                local coords = GetEntityCoords(vehicle)
                local occupied = not IsVehicleSeatFree(vehicle, -1)
                local parked = World.Population.keepParkedCars
                    and GetEntitySpeed(vehicle) < 0.1 and not occupied

                if not parked and not nearAnyPlayer(coords, World.Population.sweepSafeRadius) then
                    -- Stop it and make it harmless.
                    safe(SetVehicleEngineOn, vehicle, false, true, false)
                    safe(SetEntityVelocity, vehicle, 0.0, 0.0, 0.0)
                    safe(SetVehicleEngineHealth, vehicle, 1000.0)
                    safe(SetVehiclePetrolTankHealth, vehicle, 1000.0)
                    safe(SetEntityInvincible, vehicle, true)
                    safe(SetVehicleOutOfControl, vehicle, false, false)

                    -- Empty it; a ped left behind at speed is a hazard.
                    for seat = -1, 6 do
                        local rider = GetPedInVehicleSeat(vehicle, seat)
                        if rider and rider ~= 0 and DoesEntityExist(rider)
                           and not IsPedAPlayer(rider) then
                            purge(rider, false)
                        end
                    end

                    purge(vehicle, true)
                    budget = budget - 1
                end
            end
        end

        -- Removes every non-player ped, except those tagged bsProtected or bsZombie (owning resources set the tag)
        local spared = 0

        for ped in EnumeratePeds() do
            if budget <= 0 then break end

            if not IsPedAPlayer(ped) and DoesEntityExist(ped) then
                local state = Entity(ped).state
                local ours = state and (state.bsZombie or state.bsProtected or state.bsConvoy)

                -- The state bag tag is only a hint
                if not ours and GetResourceState('bs_zombies') == 'started' then
                    local ok, mine = pcall(function()
                        return exports.bs_zombies:IsWalkerPed(ped)
                    end)

                    -- Fail safe: if the export throws or is not ready, assume the ped belongs to someone and keep it
                    if not ok then
                        ours = true
                        spared = spared + 1
                    elseif mine then
                        ours = true
                    end
                end

                if not ours and not IsPedInAnyVehicle(ped, true) then
                    purge(ped, false)
                    budget = budget - 1
                end
            end
        end

        -- Reported once per pass, and only when it happened: a sweep that cannot ask bs_zombies deletes nothing
        if spared > 0 then
            print(('^3[BeyondSurvival]^7 (world) sweep spared %d ped(s) - bs_zombies could not be asked whether they were walkers. If this repeats, the ambient sweep is effectively OFF and the "zombies" you are shooting may be ordinary pedestrians.')
                :format(spared))
        end

        -- Anything less than the full budget means the world was dirty.
        if budget < PURGE_BUDGET then
            sweepIdleStreak = 0
        else
            sweepIdleStreak = sweepIdleStreak + 1
        end

        sweeping = false
        ::continue::
    end
end)

-- Called when the population rules change (density raised in a safe zone, or lowered again)
exports('Resweep', function()
    sweepIdleStreak = 0
end)

-- Entity enumerators (pool snapshots, not iterators)

-- Uses GetGamePool snapshots instead of FindFirstPed/FindNextPed

local function poolIterator(poolName)
    return coroutine.wrap(function()
        local ok, pool = pcall(GetGamePool, poolName)
        if not ok or type(pool) ~= 'table' then return end

        for i = 1, #pool do
            local entity = pool[i]
            -- Existence is re-checked when yielded, since the caller deletes as it goes.
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                coroutine.yield(entity)
            end
        end
    end)
end

function EnumeratePeds()     return poolIterator('CPed') end
function EnumerateVehicles() return poolIterator('CVehicle') end

-- Atmosphere

CreateThread(function()
    SetWindSpeed(World.Environment.windSpeed or 1.0)

    if World.Environment.muteAmbientRadio then
        -- City hum and distant sirens belong to a world with people in it.
        StartAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE')
    end
end)
