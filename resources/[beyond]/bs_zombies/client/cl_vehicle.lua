-- Players in vehicles vs walkers. 1.

local V = Zombies.Vehicle or {}

local openModel = {}
for _, name in ipairs(V.openModels or {}) do openModel[GetHashKey(name)] = true end

-- Seat index to the door beside it (-1 driver = door 0, etc)
local function seatOf(veh, ped)
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if GetPedInVehicleSeat(veh, seat) == ped then return seat end
    end
    return nil
end

local function vehicleIsOpen(veh, ped)
    if (V.openClasses or {})[GetVehicleClass(veh)] then return true end
    if openModel[GetEntityModel(veh)] then return true end
    if GetNumberOfVehicleDoors(veh) <= 0 then return true end

    local seat = seatOf(veh, ped)
    if not seat then return true end
    local door = seat + 1
    if door > 3 then return false end   -- rear-most seats: no side door to check

    if not DoesVehicleHaveDoor(veh, door) then return true end
    if IsVehicleDoorDamaged(veh, door) then return true end
    if GetVehicleDoorAngleRatio(veh, door) > (V.doorOpenRatio or 0.1) then return true end
    return false
end

local function playerProtectedInVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return false end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    return not vehicleIsOpen(veh, ped)
end

Zombies.PlayerProtectedInVehicle = playerProtectedInVehicle
exports('PlayerProtectedInVehicle', playerProtectedInVehicle)

-- Nobody drags you out of a sealed car.
CreateThread(function()
    local last
    while true do
        Wait(250)
        local prot = playerProtectedInVehicle()
        if prot ~= last then
            SetPedCanBeDraggedOut(PlayerPedId(), not prot)
            last = prot
        end
    end
end)

-- Ramming and head crush (driver side)

local WHEELS = { 'wheel_lf', 'wheel_rf', 'wheel_lm1', 'wheel_rm1', 'wheel_lr', 'wheel_rr' }
local HEAD = 31086   -- SKEL_Head

local function isDown(entry)
    if entry.crippled then return true end
    local crawler = Zombies.Types and Zombies.Types.crawler
    if crawler and entry.def == crawler then return true end
    return IsPedRagdoll(entry.ped) or IsPedProne(entry.ped)
end

local function report(entry, id, kind)
    if kind == 'kill' then
        if entry.vehKilled then return end
        entry.vehKilled = true
        entry.vehKillOk = true   -- cl_combat: this death was ours
        TriggerEvent('bs:vehicles:roadkill')
    else
        if entry.crippled or entry.vehCrippled then return end
        entry.vehCrippled = true
    end
    TriggerServerEvent('bs:z:vehhit', id, kind)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped or not Zed or not Zed.live then
            Wait(500)
        else
            Wait(50)
            local kmh = GetEntitySpeed(veh) * 3.6
            local vAt = GetEntityCoords(veh)
            local now = GetGameTimer()

            local wheels
            for id, entry in pairs(Zed.live) do
                local zp = entry.ped
                if zp and not entry.dying and not entry.vehKilled and DoesEntityExist(zp)
                   and not IsEntityDead(zp) and #(GetEntityCoords(zp) - vAt) < 8.0 then

                    -- Impact: count once per cooldown window.
                    local hit = HasEntityBeenDamagedByEntity(zp, veh, true)
                        or IsEntityTouchingEntity(veh, zp)
                    if hit and kmh >= (V.crippleKmh or 30.0)
                       and now >= (entry.vehHitAt or 0) then
                        entry.vehHitAt = now + (V.hitCooldownMs or 600)
                        entry.ramAccum = (entry.ramAccum or 0) + kmh
                        if kmh >= (V.accumHardKmh or 45.0) then
                            entry.ramHard = (entry.ramHard or 0) + 1
                        end
                        ClearEntityLastDamageEntity(zp)

                        if kmh >= (V.killKmh or 90.0)
                           or (entry.ramAccum >= (V.accumKillKmh or 260.0)
                               and (entry.ramHard or 0) >= (V.accumHardHits or 2)) then
                            report(entry, id, 'kill')
                        else
                            report(entry, id, 'cripple')
                        end
                    end

                    -- Head under a wheel.
                    if not entry.vehKilled and kmh >= (V.crushMinKmh or 3.0) and isDown(entry) then
                        if not wheels then
                            wheels = {}
                            for _, b in ipairs(WHEELS) do
                                local bi = GetEntityBoneIndexByName(veh, b)
                                if bi ~= -1 then wheels[#wheels + 1] = GetWorldPositionOfEntityBone(veh, bi) end
                            end
                        end
                        local head = GetPedBoneCoords(zp, HEAD, 0.0, 0.0, 0.0)
                        local r = V.crushRadius or 0.5
                        for i = 1, #wheels do
                            local w = wheels[i]
                            -- Horizontal distance; head sits below the hub so allow some height.
                            if #(vector2(head.x, head.y) - vector2(w.x, w.y)) <= r
                               and math.abs(head.z - w.z) <= 0.8 then
                                report(entry, id, 'kill')
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Crash proofing: the engine kills peds from almost any bump

local function movingCarNear(pos, r)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if GetEntitySpeed(veh) > 1.0 and #(GetEntityCoords(veh) - pos) < r then return true end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(200)
        if Zed and Zed.live then
            local r = V.proofRadius or 15.0
            for _, entry in pairs(Zed.live) do
                local zp = entry.ped
                if zp and DoesEntityExist(zp) and not entry.dying then
                    local want = movingCarNear(GetEntityCoords(zp), r)
                    if want ~= (entry.crashProof or false) then
                        entry.crashProof = want
                        -- bullet, fire, explosion, collision, melee, steam, p7, drown
                        SetEntityProofs(zp, false, false, false, want, false, false, false, false)
                    end
                end
            end
        end
    end
end)
