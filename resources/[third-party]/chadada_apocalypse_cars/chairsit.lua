-- chairsit.lua - sit-on-chair interaction from Chadada Apocalypse Cars.

local isSitting = false
local chairModel = "prop_chair_08"
local chairHash = GetHashKey(chairModel)

-- Declared as a local function above its first use so the call resolves.
local function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    local scale = 0.45
    SetTextScale(scale, scale)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry("STRING")
    SetTextDropShadow(0, 0, 0, 0, 255)
    AddTextComponentString(text)
    DrawText(_x, _y)
end

local function toggleSit(playerPed, chair)
    local chairCoords = GetEntityCoords(chair)

    if not IsEntityAttached(playerPed) then
        SetEntityCoords(playerPed, chairCoords.x, chairCoords.y, chairCoords.z)
        SetEntityRotation(playerPed, 0, 0, GetEntityHeading(chair) + 180, 2, true)
        TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_SEAT_CHAIR", 0, false)
        isSitting = true
        Citizen.Wait(500)
        -- Re-check the chair: it can be deleted during the 500ms wait (vehicle props are removed on exit).
        if DoesEntityExist(chair) then
            AttachEntityToEntity(playerPed, chair, 0, 0.0, 0.1, -0.01, 0.0, 0.0, 180.0, false, false, false, false, 0, true)
        else
            isSitting = false
            ClearPedTasks(playerPed)
        end
    else
        isSitting = false
        DetachEntity(playerPed, true, true)
        SetEntityCoords(playerPed, chairCoords.x, chairCoords.y, chairCoords.z + 0.5)
        Citizen.Wait(500)
    end
end

-- No time-of-day override here. Scan is a cheap 250ms check while no chair is near,
-- then a per-frame loop only while standing at a chair (DrawText3D needs every frame).
local SCAN_WAIT = 250

Citizen.CreateThread(function()
    while true do
        local wait = SCAN_WAIT
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearbyChair = GetClosestObjectOfType(playerCoords, 1.0, chairHash, false, false, false)

        if DoesEntityExist(nearbyChair) then
            -- Near a chair: run per-frame until the player walks away or sits/stands.
            while DoesEntityExist(nearbyChair) do
                playerPed = PlayerPedId()
                playerCoords = GetEntityCoords(playerPed)
                local chairCoords = GetEntityCoords(nearbyChair)
                local dist = #(playerCoords - chairCoords)

                if dist >= 1.0 and not isSitting then break end

                -- Prompt text: "Press E to sit" / "Press E to stand" (translated from French).
                local message = "[~g~E~w~] Sit"
                if isSitting then message = "[~g~E~w~] Stand" end

                if dist < 1.0 then
                    DrawText3D(chairCoords.x, chairCoords.y, chairCoords.z + 0.5, message)
                end

                if IsControlJustReleased(0, 38) and dist < 0.8 then
                    -- Vmag check dropped: it repeats the Vdist distance test.
                    toggleSit(playerPed, nearbyChair)
                end

                Citizen.Wait(0)
            end

            -- The chair can be deleted while the player is sitting on it.
            if isSitting and not IsEntityAttached(PlayerPedId()) then
                isSitting = false
                ClearPedTasks(PlayerPedId())
            end
        end

        Citizen.Wait(wait)
    end
end)

-- Release the player so they are not stuck to a deleted prop.
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isSitting then
        local ped = PlayerPedId()
        DetachEntity(ped, true, true)
        ClearPedTasks(ped)
        isSitting = false
    end
end)
