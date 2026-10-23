-- bs_admin - staff free-camera movement

Noclip = { active = false }

local speed = Admin.Settings.noclipSpeed

function Noclip.Toggle(state)
    if state == nil then state = not Noclip.active end
    Noclip.active = state

    local ped = PlayerPedId()
    SetEntityInvincible(ped, state)
    SetEntityVisible(ped, not state, false)
    SetEntityCollision(ped, not state, not state)
    FreezeEntityPosition(ped, state)
    SetEntityAlpha(ped, state and 150 or 255, false)

    if not state then ResetEntityAlpha(ped) end
    return Noclip.active
end

CreateThread(function()
    while true do
        if Noclip.active then
            Wait(0)
            local ped = PlayerPedId()
            local cam = GetGameplayCamRot(2)
            local pos = GetEntityCoords(ped)

            -- Disable first, then read the disabled state (a disabled control always reads as not pressed).
            DisableControlAction(0, 32, true)   -- W
            DisableControlAction(0, 33, true)   -- S
            DisableControlAction(0, 34, true)   -- A
            DisableControlAction(0, 35, true)   -- D
            DisableControlAction(0, 22, true)   -- space
            DisableControlAction(0, 44, true)   -- Q
            DisableControlAction(0, 21, true)   -- shift
            DisableControlAction(0, 36, true)   -- ctrl
            DisableControlAction(0, 268, true)

            local mult = speed
            if IsDisabledControlPressed(0, 21) then mult = mult * Admin.Settings.noclipFastMult end
            if IsDisabledControlPressed(0, 36) then mult = mult * Admin.Settings.noclipSlowMult end

            local dx, dy, dz = 0.0, 0.0, 0.0
            if IsDisabledControlPressed(0, 32) then dy = mult end        -- W
            if IsDisabledControlPressed(0, 33) then dy = -mult end       -- S
            if IsDisabledControlPressed(0, 34) then dx = -mult end       -- A
            if IsDisabledControlPressed(0, 35) then dx = mult end        -- D
            if IsDisabledControlPressed(0, 22) then dz = mult end        -- space
            if IsDisabledControlPressed(0, 44) then dz = -mult end       -- Q

            if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then
                local yaw = math.rad(cam.z)
                local pitch = math.rad(cam.x)
                local fx = -math.sin(yaw) * math.cos(pitch)
                local fy =  math.cos(yaw) * math.cos(pitch)
                local fz =  math.sin(pitch)
                local rx =  math.cos(yaw)
                local ry =  math.sin(yaw)

                SetEntityCoordsNoOffset(ped,
                    pos.x + fx * dy + rx * dx,
                    pos.y + fy * dy + ry * dx,
                    pos.z + fz * dy + dz, true, true, true)
            end

            SetEntityHeading(ped, cam.z)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and Noclip.active then Noclip.Toggle(false) end
end)
