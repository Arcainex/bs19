-- ap_core.lua - owns prop lifetime for the vehicle files: creation, tracking per vehicle handle,
-- and deletion on exit, vehicle loss or resource stop.
-- Self-contained: no framework calls, no exports, no shared includes.

ApocalypseCars = {}

-- modelHash -> { bone = "motor", props = { spec, ... } }
local specs = {}

-- Props belong to the vehicle, not the driver: every registered vehicle near the player
-- stays dressed while it exists and is in range, and is undressed when destroyed, streamed out or left behind.
-- dressed[vehicleHandle] = { propEntity, ... }
local dressed = {}

-- Guarded model read: DoesEntityExist first, then pcall, returns nil instead of throwing.
-- GetEntityModel can fault on entities whose archetype is not resolved yet. Kept local so the resource has no framework dependency.
local function safeModelOf(entity)
    if not entity or entity == 0 then return nil end
    if not DoesEntityExist(entity) then return nil end
    local ok, model = pcall(GetEntityModel, entity)
    if ok then return model end
    return nil
end

-- Called from bodhi2.lua / dloader.lua / flatbed.lua / wastelander.lua at load time, before the driver thread starts.
function ApocalypseCars.Register(modelName, boneName, propList)
    specs[GetHashKey(modelName)] = { bone = boneName, props = propList }
end

-- Deletion. Detach first so the object does not inherit vehicle velocity, then take mission-entity ownership so DeleteObject takes effect.
local function undress(vehicle)
    local props = dressed[vehicle]
    if not props then return end

    for i = 1, #props do
        local obj = props[i]
        if obj and DoesEntityExist(obj) then
            DetachEntity(obj, true, false)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
            if DoesEntityExist(obj) then
                -- Could not take ownership: hand it back to the engine so it can be cleaned up.
                SetEntityAsNoLongerNeeded(obj)
            end
        end
    end

    dressed[vehicle] = nil
end

local function undressAll()
    for vehicle in pairs(dressed) do undress(vehicle) end
    dressed = {}
end

-- Creation. Request each prop model first (a unloaded model gives a null handle). The wait is bounded so a bad model name cannot hang the thread.
local function dress(vehicle, spec)
    local bone = GetEntityBoneIndexByName(vehicle, spec.bone)
    local props = {}
    dressed[vehicle] = props

    for i = 1, #spec.props do
        local p = spec.props[i]
        local hash = GetHashKey(p.model)

        if not HasModelLoaded(hash) and IsModelValid(hash) then
            RequestModel(hash)
            local tries = 0
            while not HasModelLoaded(hash) and tries < 100 do
                Citizen.Wait(10)
                tries = tries + 1
            end
        end

        -- The vehicle may be gone after the model streaming wait.
        if not DoesEntityExist(vehicle) then
            undress(vehicle)
            return false
        end

        -- Client-local objects (isNetwork = false): every client dresses each rigged vehicle it sees,
        -- so networked props would stack duplicates and exhaust the object budget.
        local obj = CreateObject(hash, 0.0, 0.0, 0.0, false, true, true)
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            AttachEntityToEntity(
                obj, vehicle, bone,
                p.off[1], p.off[2], p.off[3],
                p.rot[1], p.rot[2], p.rot[3],
                -- Trailing argument pattern from Chadada's original script.
                (p.p9 ~= false), (p.softPin ~= false), (p.collision == true),
                true, 1, true
            )
            props[#props + 1] = obj
        end

        SetModelAsNoLongerNeeded(hash)
    end

    return true
end

-- Driver loop. Scans the vehicle pool, not just the player's seat, since props belong to the vehicle.
-- Uses GetGamePool (a snapshot) instead of the Find iterators, which can crash on a changing pool.

-- Distance (m) to dress a rigged vehicle and a larger distance to undress it.
-- The gap is hysteresis, so a car on the line does not flicker.
local DRESS_RANGE   = 140.0
local UNDRESS_RANGE = 190.0

-- Max vehicles dressed at once (97 props on a wastelander adds up). Nearest first.
local MAX_DRESSED = 3

local SCAN_WAIT = 750

local function distanceTo(coords, entity)
    return #(coords - GetEntityCoords(entity))
end

Citizen.CreateThread(function()
    -- Wait so every vehicle file finishes registering before the first scan.
    Citizen.Wait(1000)

    while true do
        Citizen.Wait(SCAN_WAIT)

        local ped = PlayerPedId()
        if not ped or ped == 0 or not DoesEntityExist(ped) then goto continue end

        do
            local at = GetEntityCoords(ped)

            -- First release anything no longer in range, so its slot is free for a nearer vehicle in the same pass.
            for vehicle in pairs(dressed) do
                if not DoesEntityExist(vehicle)
                   or not specs[safeModelOf(vehicle) or 0]
                   or distanceTo(at, vehicle) > UNDRESS_RANGE then
                    undress(vehicle)
                end
            end

            -- Then the candidates, nearest first.
            local candidates = {}

            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) and not dressed[vehicle] then
                    local model = safeModelOf(vehicle)
                    local spec = model and specs[model]

                    if spec then
                        local d = distanceTo(at, vehicle)
                        if d <= DRESS_RANGE then
                            candidates[#candidates + 1] =
                                { vehicle = vehicle, spec = spec, dist = d }
                        end
                    end
                end
            end

            table.sort(candidates, function(a, b) return a.dist < b.dist end)

            local held = 0
            for _ in pairs(dressed) do held = held + 1 end

            for i = 1, #candidates do
                if held >= MAX_DRESSED then break end
                dress(candidates[i].vehicle, candidates[i].spec)
                held = held + 1
            end
        end

        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    undressAll()
end)
