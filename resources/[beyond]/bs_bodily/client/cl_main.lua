local function notify(payload)
    if GetResourceState('bs_ui') == 'started' then
        exports.bs_ui:Notify(payload)
    end
end

RegisterNetEvent('bs:bodily:notify', function(payload)
    notify(payload)
end)

local function urgencyNote(value)
    if value >= 80 then return L('bd.critical') end
    if value >= 45 then return L('bd.urgent') end
    if value > 0 then return L('bd.building') end
    return L('bd.comfortable')
end

local doing=false
local function openNeeds()
    if doing then return end
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if not Bodily.enabled or GetResourceState('bs_radial') ~= 'started' then return end
    CreateThread(function()
        local status = BSB.Await('bodily:status', 5000) or {}
        if not status.ok then
            return notify({ type = 'warn', title = L('bd.title'), message = status.message or L('bd.not_ready') })
        end

        local coreNeeds = exports.bs_core:GetNeeds() or {}
        local items = {
            { id = 'status', label = L('bd.status', { food = math.floor(coreNeeds.hunger or 0), water = math.floor(coreNeeds.thirst or 0) }), icon = 'needs', disabled = true, note = L('bd.keep_eating') },
            { id = 'pee', label = L('bd.pee'), icon = 'pee', note = L('bd.bladder', { s = urgencyNote(status.pee) }), disabled = status.pee < 10 },
            { id = 'poop', label = L('bd.poop'), icon = 'poop', note = L('bd.bowel', { s = urgencyNote(status.poop) }), disabled = status.poop < 10 },
        }
        if status.soiled then
            items[#items + 1] = { id = 'soiled', label = L('bd.soiled'), icon = 'warn', danger = true, disabled = true, note = L('bd.smell') }
        end

        local choice = exports.bs_radial:Open({ title = L('bd.title'):upper(), items = items, blur = false })
        if choice ~= 'pee' and choice ~= 'poop' then return end
        local begin = BSB.Await('bodily:begin', 5000, choice) or {}
        if not begin.ok then return notify({type='warn',title=L('bd.title'),message=begin.message or L('bd.unavail')}) end
        doing=true
        local ped=PlayerPedId();local origin=GetEntityCoords(ped)
        local dict=choice=='pee' and 'misscarsteal2peeing' or 'missfbi3ig_0'
        local anim=choice=='pee' and 'peeing_loop' or 'shit_loop_trev'
        RequestAnimDict(dict);local loadUntil=GetGameTimer()+2000
        while not HasAnimDictLoaded(dict) and GetGameTimer()<loadUntil do Wait(10) end
        if not HasAnimDictLoaded(dict) then doing=false;TriggerServerEvent('bs:bodily:cancel');return end
        TaskPlayAnim(ped,dict,anim,4.0,-4.0,begin.duration,1,0.0,false,false,false)
        TriggerServerEvent('bs:bodily:reliefEffect', choice, begin.duration)
        local started=GetGameTimer();local cancelled=false
        local minigame = Bodily.reliefMinigame and { windows = choice == 'pee' and {1400, 3500} or {2200, 5400}, hits = 0, checked = {} }
        while GetGameTimer()-started<begin.duration do
            Wait(0)
            DisableControlAction(0,24,true);DisableControlAction(0,25,true)
            if minigame then
                local elapsed = GetGameTimer() - started
                for index, cue in ipairs(minigame.windows) do
                    if not minigame.checked[index] and elapsed >= cue and elapsed < cue + 950 then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('Hold steady - press ~INPUT_CONTEXT~')
                        EndTextCommandDisplayHelp(0, false, false, -1)
                        if IsControlJustPressed(0, 38) then
                            minigame.checked[index] = true
                            minigame.hits = minigame.hits + 1
                        end
                    elseif elapsed >= cue + 950 then
                        minigame.checked[index] = true
                    end
                end
            end
            if IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped,false) or #(GetEntityCoords(ped)-origin)>1.0 or IsControlJustPressed(0,177) or IsPauseMenuActive() then cancelled=true;break end
        end
        ClearPedTasks(ped);RemoveAnimDict(dict);doing=false
        if cancelled then TriggerServerEvent('bs:bodily:cancel');return end
        if minigame and minigame.hits < #minigame.windows then
            notify({type='warn',title=L('bd.title'),message='That took a little longer.'})
            Wait(1500)
        end
        local result = BSB.Await('bodily:relieve', 5000, choice, begin.token) or {}
        notify({ type = result.ok and 'success' or 'warn', title = L('bd.title'), message = result.message or L('bd.nothing') })
    end)
end

RegisterCommand('bodilyneeds',openNeeds,false)
RegisterNetEvent('bs:bodily:open',openNeeds)
exports('OpenNeeds',openNeeds)

local holdingFart = false
local fartSounds = {}

local function fartPoint(speakerId, fallback)
    local player = GetPlayerFromServerId(speakerId)
    if player ~= -1 then
        local ped = GetPlayerPed(player)
        if ped ~= 0 and DoesEntityExist(ped) then
            local point = GetPedBoneCoords(ped, 11816, 0.0, -0.18, -0.12)
            return { x = point.x, y = point.y, z = point.z }
        end
    end
    return fallback
end

RegisterCommand('+bsfart_pt', function()
    if holdingFart then return end
    holdingFart = true
    TriggerServerEvent('bs:bodily:fartStart')
end, false)
RegisterCommand('-bsfart_pt', function()
    if not holdingFart then return end
    holdingFart = false
    TriggerServerEvent('bs:bodily:fartStop')
end, false)
RegisterKeyMapping('+bsfart_pt', 'Hold to fart', 'keyboard', 'OEM_1') -- Ç on PT-PT keyboards

RegisterCommand('fart', function()
    TriggerServerEvent('bs:bodily:fartStart')
    SetTimeout(850, function() TriggerServerEvent('bs:bodily:fartStop') end)
end, false)

RegisterNetEvent('bs:bodily:fartStart', function(coords, variant, speakerId)
    if GetResourceState('bs_ui') ~= 'started' then return end
    speakerId = tonumber(speakerId) or -1
    local point = fartPoint(speakerId, coords)
    local me = GetEntityCoords(PlayerPedId())
    if #(me - vector3(point.x, point.y, point.z)) > 22.0 then return end
    local tag = 'bodily:fart:' .. speakerId
    if fartSounds[speakerId] then exports.bs_ui:StopSoundTag(tag, 60) end
    fartSounds[speakerId] = true
    if speakerId == GetPlayerServerId(PlayerId()) and GetResourceState('bs_emotes') == 'started' then
        exports.bs_emotes:MakeNoise('fart', point, 12.0)
    end
    exports.bs_ui:PlaySoundAt(('fart_%d.mp3'):format(math.max(1, math.min(20, tonumber(variant) or 1))), point,
        {id = tag, volume = 0.7, maxDistance = 16.0, loop = true})
end)

RegisterNetEvent('bs:bodily:fartStop', function(speakerId)
    speakerId = tonumber(speakerId) or -1
    if not fartSounds[speakerId] then return end
    fartSounds[speakerId] = nil
    if GetResourceState('bs_ui') == 'started' then
        exports.bs_ui:StopSoundTag('bodily:fart:' .. speakerId, 120)
    end
end)

CreateThread(function()
    while true do
        if next(fartSounds) then
            for speakerId in pairs(fartSounds) do
                local point = fartPoint(speakerId)
                if point then exports.bs_ui:MoveSoundAt('bodily:fart:' .. speakerId, point) end
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('bs:bodily:reliefFx', function(bucket, coords, kind, duration, speakerId)
    local player = GetPlayerFromServerId(tonumber(speakerId) or -1)
    local ped = player ~= -1 and GetPlayerPed(player) or 0
    local at = vector3(coords.x, coords.y, coords.z)
    if #(GetEntityCoords(PlayerPedId()) - at) > 35.0 then return end
    if kind == 'pee' then
        if ped == 0 or not DoesEntityExist(ped) then return end
        RequestNamedPtfxAsset('core')
        local deadline = GetGameTimer() + 1500
        while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < deadline do Wait(0) end
        if not HasNamedPtfxAssetLoaded('core') then return end
        UseParticleFxAssetNextCall('core')
        local fx = StartParticleFxLoopedOnEntity('ent_sht_water', ped,
            0.0, 0.27, -0.55, -25.0, 0.0, 0.0, 0.16, false, false, false)
        Wait(math.min(duration, 10000))
        if fx and fx ~= 0 then StopParticleFxLooped(fx, false) end
        RemoveNamedPtfxAsset('core')
    elseif kind == 'poop' then
        local model = joaat('prop_big_shit_01')
        if not IsModelInCdimage(model) then return end
        RequestModel(model)
        local deadline = GetGameTimer() + 1500
        while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
        if not HasModelLoaded(model) then return end
        if ped == 0 or not DoesEntityExist(ped) then SetModelAsNoLongerNeeded(model); return end
        local rear = GetOffsetFromEntityInWorldCoords(ped, 0.0, -0.18, 0.0)
        local ground = rear.z - 0.95
        if GetResourceState('bs_ui') == 'started' then
            exports.bs_ui:PlaySoundAt('fart_3.mp3', {x=rear.x,y=rear.y,z=ground}, {volume=0.45,maxDistance=10.0})
        end
        local obj = CreateObjectNoOffset(model, rear.x, rear.y, ground + 0.55, false, false, false)
        if obj ~= 0 then
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, false, false)
            SetEntityVisible(obj, true, false)
            local started = GetGameTimer()
            while DoesEntityExist(obj) and GetGameTimer() - started < math.min(duration, 4500) do
                local progress = (GetGameTimer() - started) / math.min(duration, 4500)
                local point = GetOffsetFromEntityInWorldCoords(ped, 0.0, -0.18, 0.0)
                SetEntityCoordsNoOffset(obj, point.x, point.y, ground + 0.55 * (1.0 - progress), false, false, false)
                Wait(0)
            end
            PlaceObjectOnGroundProperly(obj)
        end
        SetModelAsNoLongerNeeded(model)
        Wait(90000)
        if obj ~= 0 and DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end)
