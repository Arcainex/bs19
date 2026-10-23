-- bs_jobs client rebels: rob and zip-tie options on players, and what it feels like to be held.

local notify = JC.Notify

local function serverIdOf(ped)
    if not ped or not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return nil end
    local pid = NetworkGetPlayerIndexFromPed(ped)
    if not pid or pid == -1 then return nil end
    return GetPlayerServerId(pid)
end

local function call(name, payload, okKey)
    local target = serverIdOf(payload and payload.entity)
    if not target then return end
    CreateThread(function()
        local r = BSB.Await(name, 8000, target)
        if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
        if okKey then notify('success', L(okKey, { n = r.n or 0 })) end
    end)
end

AddEventHandler('bs:jobs:rob', function(payload)
    if not IsPedArmed(PlayerPedId(), 4) then return notify('warn', L('err.need_gun')) end
    call('jobs:rob', payload, 'n.rob_done')
end)

AddEventHandler('bs:jobs:tie', function(payload)
    local target = serverIdOf(payload and payload.entity)
    if not target then return end
    CreateThread(function()
        if not JC.Timed(L('prog.tie'), 2500, { { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 } }) then return end
        local r = BSB.Await('jobs:kid:tie', 8000, target)
        if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
        notify('success', L('n.tied'))
    end)
end)

AddEventHandler('bs:jobs:hood', function(payload) call('jobs:kid:hood', payload) end)
AddEventHandler('bs:jobs:release', function(payload) call('jobs:kid:release', payload) end)
AddEventHandler('bs:jobs:carry', function(payload)
    local target = serverIdOf(payload and payload.entity)
    if not target then return end
    CreateThread(function()
        local r = BSB.Await('jobs:kid:carry', 8000, target)
        if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
    end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    Wait(1500)
    exports.bs_interactions:AddType('ped', {
        { labelKey = 'opt.rob', label = 'Rob', icon = 'hand', distance = 3.0, event = 'bs:jobs:rob',
          filters = { playerPed = true, onFoot = true, playerStateTrue = 'bsJ_rob', ownerStateTrue = 'bsHandsUp' } },
        { labelKey = 'opt.tie', label = 'Zip-tie', icon = 'hand', distance = 2.0, event = 'bs:jobs:tie',
          filters = { playerPed = true, onFoot = true, playerStateTrue = 'bsJ_kidnap', ownerStateFalse = 'bsCuffed' } },
        { labelKey = 'opt.hood', label = 'Hood on / off', icon = 'hand', distance = 2.0, event = 'bs:jobs:hood',
          filters = { playerPed = true, onFoot = true, playerStateTrue = 'bsJ_kidnap', ownerStateTrue = 'bsCuffed' } },
        { labelKey = 'opt.carry', label = 'Carry / put down', icon = 'hand', distance = 2.0, event = 'bs:jobs:carry',
          filters = { playerPed = true, onFoot = true, playerStateTrue = 'bsJ_kidnap', ownerStateTrue = 'bsCuffed' } },
        { labelKey = 'opt.release', label = 'Cut the ties', icon = 'hand', distance = 2.0, event = 'bs:jobs:release',
          filters = { playerPed = true, onFoot = true, playerStateTrue = 'bsJ_kidnap', ownerStateTrue = 'bsCuffed' } },
    })
end)

-- Captor side: carry pose while someone is on the shoulder.
CreateThread(function()
    local dict, clip = 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman'
    local was = false
    while true do
        local me = GetPlayerServerId(PlayerId())
        local carrying = false
        for _, p in ipairs(GetActivePlayers()) do
            local st = Player(GetPlayerServerId(p)).state
            if st and tonumber(st.bsCarriedBy) == me then carrying = true break end
        end
        if was and not carrying then ClearPedTasks(PlayerPedId()) end
        was = carrying
        if carrying then
            local ped = PlayerPedId()
            if DoesAnimDictExist(dict) then
                RequestAnimDict(dict)
                if HasAnimDictLoaded(dict) and not IsEntityPlayingAnim(ped, dict, clip, 3) then
                    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, 49, 0, false, false, false)
                end
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

--------------------------------------------------------------------------------
-- Victim side
--------------------------------------------------------------------------------

local BLOCK = { 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }
local attachedTo = nil

local function playLoop(dict, clip, flag)
    local ped = PlayerPedId()
    if not DoesAnimDictExist(dict) then return end
    RequestAnimDict(dict)
    if HasAnimDictLoaded(dict) and not IsEntityPlayingAnim(ped, dict, clip, 3) then
        TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, flag, 0, false, false, false)
    end
end

CreateThread(function()
    while true do
        local st = LocalPlayer.state
        if st.bsCuffed then
            for _, c in ipairs(BLOCK) do DisableControlAction(0, c, true) end
            local carrier = tonumber(st.bsCarriedBy)
            local ped = PlayerPedId()
            if carrier then
                local cp = GetPlayerFromServerId(carrier)
                local cped = cp ~= -1 and GetPlayerPed(cp) or 0
                if cped ~= 0 and attachedTo ~= cped then
                    AttachEntityToEntity(ped, cped, 0, 0.27, 0.15, 0.63, 0.5, 0.5, 180.0, false, false, false, false, 2, false)
                    attachedTo = cped
                end
                playLoop('nm', 'firemans_carry', 33)
            else
                if attachedTo then DetachEntity(ped, true, false); attachedTo = nil end
                playLoop('mp_arresting', 'idle', 49)
            end
            if st.bsHooded then
                DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 252)
                SetTextFont(4); SetTextScale(0.4, 0.4); SetTextColour(200, 190, 170, 200); SetTextCentre(true)
                BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(L('n.hooded')); EndTextCommandDisplayText(0.5, 0.48)
            end
            Wait(0)
        else
            if attachedTo then
                DetachEntity(PlayerPedId(), true, false)
                attachedTo = nil
                ClearPedTasks(PlayerPedId())
            end
            Wait(500)
        end
    end
end)

-- After a restart a stale cuff flag may be left on us; the server clears it if nobody holds us.
CreateThread(function()
    Wait(5000)
    if LocalPlayer.state.bsCuffed then TriggerServerEvent('bs:jobs:checkCuffs') end
end)

AddStateBagChangeHandler('bsCuffed', nil, function(bag, _, value)
    if bag ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
    if not value then SetTimeout(100, function() ClearPedTasks(PlayerPedId()) end) end
end)
