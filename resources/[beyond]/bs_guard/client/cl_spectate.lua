-- bs_guard - staff spectate for the F10 GUARD tab

local active, back = nil, nil

local function stop()
    if not active then return end
    -- cleared first so a failure below can never leave the follow thread calling stop() forever
    active = nil
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    if back then
        RequestCollisionAtCoord(back.x, back.y, back.z)
        SetEntityCoordsNoOffset(ped, back.x, back.y, back.z, false, false, false)
    end
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    active, back = nil, nil
    TriggerEvent('bs:ui:notify', { type = 'info', title = 'GUARD', message = L('guard.spec_stopped') })
end

RegisterNetEvent('bs_guard:spectateStop', stop)

RegisterNetEvent('bs_guard:spectate', function(target, x, y, z)
    if active == target then stop() return end
    if active then stop() end
    local ped = PlayerPedId()
    back = GetEntityCoords(ped)
    active = target
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z - 15.0, false, false, false)

    local deadline = GetGameTimer() + 8000
    local tp
    while GetGameTimer() < deadline do
        local pl = GetPlayerFromServerId(target)
        if pl ~= -1 then tp = GetPlayerPed(pl) if tp ~= 0 and DoesEntityExist(tp) then break end end
        Wait(100)
    end
    if not tp or tp == 0 or active ~= target then
        stop()
        TriggerEvent('bs:ui:notify', { type = 'error', title = 'GUARD', message = L('guard.spec_nostream') })
        return
    end
    NetworkSetInSpectatorMode(true, tp)
    TriggerEvent('bs:ui:notify', { type = 'info', title = 'GUARD', message = L('guard.spec_on', { id = target }) })

    -- keep the hidden admin ped under the target so it stays in scope
    CreateThread(function()
        while active == target do
            local pl = GetPlayerFromServerId(target)
            local p = pl ~= -1 and GetPlayerPed(pl) or 0
            if p == 0 or not DoesEntityExist(p) then stop() break end
            local c = GetEntityCoords(p)
            SetEntityCoordsNoOffset(PlayerPedId(), c.x, c.y, c.z - 15.0, false, false, false)
            Wait(1000)
        end
    end)
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then stop() end end)
