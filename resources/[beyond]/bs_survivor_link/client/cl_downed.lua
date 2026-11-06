-- Keeps the companion body in step with the server life state.
-- Server status is the truth: downed means on the ground in the medical writhe loop, alive means up and free.
local companion,freedAt
-- Same base-game writhe loop bs_medical uses for downed players.
local DICT,CLIP='combat@damage@writhe','writhe_loop'
local posed={} -- net -> 'down' once the body is on the ground, 'grab' while a walker holds him
-- Cowering pose while pinned by a walker.
local GDICT,GCLIP='amb@code_human_cower@male@base','base'

local function entity(net)
    if not net then return end
    local p=NetworkGetEntityFromNetworkId(net)
    if p~=0 and DoesEntityExist(p)then return p end
end
local function control(ped,ms)
    local untilAt=GetGameTimer()+(ms or 1000)
    while DoesEntityExist(ped)and not NetworkHasControlOfEntity(ped)and GetGameTimer()<untilAt do
        NetworkRequestControlOfEntity(ped);Wait(25)
    end
    return DoesEntityExist(ped)and NetworkHasControlOfEntity(ped)
end
local function loadDict()
    if HasAnimDictLoaded(DICT)then return true end
    RequestAnimDict(DICT)
    local untilAt=GetGameTimer()+2000
    while not HasAnimDictLoaded(DICT)and GetGameTimer()<untilAt do Wait(20)end
    return HasAnimDictLoaded(DICT)
end

-- Knock the body over, let it land, then hold the writhe loop.
local function goDown(ped,net,knock)
    if not control(ped,1500)then return false end
    FreezeEntityPosition(ped,false)
    ClearPedTasksImmediately(ped)
    RemoveAllPedWeapons(ped,true)
    SetBlockingOfNonTemporaryEvents(ped,true)
    if knock and not IsPedInAnyVehicle(ped,false)then
        SetPedToRagdoll(ped,1200,1600,0,false,false,false)
        local untilAt=GetGameTimer()+2500
        Wait(400)
        while IsPedRagdoll(ped)and GetGameTimer()<untilAt do Wait(100)end
    end
    if not DoesEntityExist(ped)or not NetworkHasControlOfEntity(ped)then return false end
    if IsPedInAnyVehicle(ped,false)then TaskLeaveVehicle(ped,GetVehiclePedIsIn(ped,false),16);Wait(1200)end
    if not loadDict()then return false end
    TaskPlayAnim(ped,DICT,CLIP,8.0,-8.0,-1,1,0,false,false,false)
    posed[net]='down'
    return true
end
local function pinned(ped,net,grabNet)
    if not control(ped,1000)then return false end
    FreezeEntityPosition(ped,false)
    RemoveAllPedWeapons(ped,true)
    local z=entity(grabNet)
    if z then
        local a,b=GetEntityCoords(ped),GetEntityCoords(z)
        SetEntityHeading(ped,GetHeadingFromVector_2d(b.x-a.x,b.y-a.y))
    end
    if not HasAnimDictLoaded(GDICT)then
        RequestAnimDict(GDICT)
        local untilAt=GetGameTimer()+2000
        while not HasAnimDictLoaded(GDICT)and GetGameTimer()<untilAt do Wait(20)end
    end
    if HasAnimDictLoaded(GDICT)then TaskPlayAnim(ped,GDICT,GCLIP,8.0,-8.0,-1,1,0,false,false,false)end
    posed[net]='grab'
    return true
end
local function getUp(ped,net)
    posed[net]=nil
    if not control(ped,1500)then return false end
    FreezeEntityPosition(ped,false)
    if IsEntityPlayingAnim(ped,DICT,CLIP,3)then StopAnimTask(ped,DICT,CLIP,2.0)end
    if IsEntityPlayingAnim(ped,GDICT,GCLIP,3)then StopAnimTask(ped,GDICT,GCLIP,2.0)end
    ClearPedTasks(ped)
    return true
end

RegisterNetEvent('bs:link:state',function(data)
    if not data then posed={} end
    companion=data or nil
end)
local function mark(net,status)
    if companion and companion.net==net and companion.life then companion.life.status=status end
end
RegisterNetEvent('bs:link:fallen',function(net,life)
    mark(net,'downed')
    CreateThread(function()local ped=entity(net);if ped then goDown(ped,net,true)end end)
end)
RegisterNetEvent('bs:link:grabbed',function(net,grabNet)
    if companion and companion.net==net and companion.life then companion.life.status='grabbed';companion.life.grabNet=grabNet end
    CreateThread(function()local ped=entity(net);if ped then pinned(ped,net,grabNet)end end)
end)
RegisterNetEvent('bs:link:revived',function(net)
    mark(net,'alive')
    CreateThread(function()local ped=entity(net);if ped then getUp(ped,net)end end)
end)

-- Watchdog: anything that stands the body up (a walker hit, ownership change, streaming) gets corrected here.
CreateThread(function()
    while true do
        local delay=1000
        if companion and companion.net then
            local ped=entity(companion.net)
            local status=companion.life and companion.life.status or 'alive'
            if ped then
                if status=='downed'then
                    delay=500
                    if NetworkHasControlOfEntity(ped)then
                        if not IsPedRagdoll(ped)and not IsEntityPlayingAnim(ped,DICT,CLIP,3)then goDown(ped,companion.net,false)end
                    else NetworkRequestControlOfEntity(ped)end
                elseif status=='grabbed'then
                    delay=250
                    local grabNet=companion.life.grabNet
                    local z=entity(grabNet)
                    -- Shoved over, killed or pulled off him: tell the server he is free.
                    if not z or IsEntityDead(z)or IsPedRagdoll(z)or Entity(z).state.bsZombieDead
                        or #(GetEntityCoords(z)-GetEntityCoords(ped))>2.6 then
                        if GetGameTimer()-(freedAt or 0)>1500 then freedAt=GetGameTimer();TriggerServerEvent('bs:link:grabFree',grabNet)end
                    elseif NetworkHasControlOfEntity(ped)and not IsEntityPlayingAnim(ped,GDICT,GCLIP,3)and not IsPedRagdoll(ped)then
                        pinned(ped,companion.net,grabNet)
                    elseif not NetworkHasControlOfEntity(ped)then NetworkRequestControlOfEntity(ped)end
                elseif status=='alive'and (posed[companion.net]or IsEntityPlayingAnim(ped,DICT,CLIP,3))then
                    getUp(ped,companion.net)
                end
            end
        end
        Wait(delay)
    end
end)
