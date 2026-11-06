local C=SurvivorLink
local companion,opened,acting=nil,false,false
local lastCommand,lastIssued,revision=nil,0,0
local aimedTarget
local openWheel, wheelBusy, startTrade
local function post(data)SendNUIMessage(data)end
local function notify(text)TriggerEvent('bs:ui:notify',{type='info',message=text,duration=4500})end
local function entity(net)
    if not net then return end
    local p=NetworkGetEntityFromNetworkId(net)
    if p~=0 and DoesEntityExist(p)then return p end
end
local function close()
    if not opened then return end
    opened=false;SetNuiFocus(false,false);post({action='close'})
    TriggerEvent('bs:ui:closed','survivorLink')
end
local function refresh()
    local result=BSB.Await('link:roster',7000)
    if opened then post({action='roster',data=result})end
    return result
end
local function open(wheel)
    if wheel then return openWheel()end
    if not exports.bs_core:IsLoaded()then return end
    if opened then close();return end
    local hit,aimed=GetEntityPlayerIsFreeAimingAt(PlayerId())
    aimedTarget=hit and aimed~=0 and IsEntityAPed(aimed)and not IsPedAPlayer(aimed)and NetworkGetNetworkIdFromEntity(aimed)or nil
    local result=BSB.Await('link:roster',7000)
    if not result or not result.ok then notify(result and result.error or 'Survivor Link unavailable.');return end
    TriggerEvent('bs:ui:opened','survivorLink')
    opened=true;SetNuiFocus(true,true);post({action='open',wheel=wheel==true,data=result})
end
RegisterNetEvent('bs:link:open',function()CreateThread(function()open(false)end)end)
RegisterCommand('survivorlink',function()CreateThread(function()open(false)end)end,false)
-- Retire the old F7 command so a saved mapping cannot conflict with VIP.
RegisterCommand('+survivorlink',function()end,false)
RegisterCommand('-survivorlink',function()end,false)
RegisterCommand('+bs_link_wheel',function()CreateThread(function()open(true)end)end,false)
RegisterCommand('-bs_link_wheel',function()end,false)
RegisterKeyMapping('+bs_link_wheel','Survivor Link command wheel','keyboard','L')
RegisterNUICallback('close',function(_,cb)close();cb({ok=true})end)
local function action(route,...)
    if acting then return {ok=false,error='Please wait.'}end
    acting=true
    local ok,result=pcall(BSB.Await,route,15000,...)
    acting=false
    if not ok then result=nil end
    if not result then result={ok=false,error='Server did not respond.'}end
    if not result.ok then notify(result.error)end
    return result
end
RegisterNUICallback('summon',function(data,cb)CreateThread(function()local result=action('link:summon',data.id);cb(result);refresh()end)end)
RegisterNUICallback('dismiss',function(_,cb)CreateThread(function()local result=action('link:dismiss');cb(result);refresh()end)end)
local function switchControl(cb)
    StopScreenEffect('SwitchHUDIn')
    if not companion or not companion.life or companion.life.status~='alive' then
        local result={ok=false,error='Call a living survivor before switching.'}
        notify(result.error)
        if cb then cb(result)end
        return
    end
    close()
    local result=action('link:switch')
    StopScreenEffect('SwitchHUDIn')
    if result.ok then PlaySoundFrontend(-1,'SELECT','HUD_FRONTEND_DEFAULT_SOUNDSET',true)end
    if cb then cb(result)end
end
RegisterNUICallback('switch',function(_,cb)CreateThread(function()switchControl(cb)end)end)
RegisterNUICallback('command',function(data,cb)CreateThread(function()
    local target
    if data.command=='target'then
        if not aimedTarget then cb({ok=false,error='Aim at an NPC before opening the wheel.'});notify('Aim at an NPC before opening the wheel.');return end
        target=aimedTarget
    end
    local result=action('link:command',data.command,target,data.stance);cb(result)
    if result.queued then notify(result.label)end
    if result.ok then PlaySoundFrontend(-1,'NAV_UP_DOWN','HUD_FRONTEND_DEFAULT_SOUNDSET',true);close()end
end)end)
-- His gear uses the normal inventory layout with his character as the subject.
local function openGear(cb)
    local result=action('link:inventory')
    if result.ok then close();TriggerEvent('bs:inventory:showContainer',result)end
    if cb then cb(result)end
end
local function setAmmo(mode,cb)
    local result=action('link:ammoMode',mode)
    if result.ok then notify(result.label)end
    if cb then cb(result)end
end
RegisterNUICallback('gear',function(_,cb)CreateThread(function()openGear(cb)end)end)
RegisterNUICallback('ammoMode',function(data,cb)CreateThread(function()setAmmo(data.mode,cb)end)end)
startTrade=function()
    close()
    action('link:tradeStart')
end
RegisterNUICallback('tradeStart',function(_,cb)CreateThread(function()cb({ok=true});startTrade()end)end)
RegisterNUICallback('bags',function(_,cb)CreateThread(function()cb(action('link:bags'))end)end)
RegisterNUICallback('trade',function(data,cb)CreateThread(function()cb(action('link:trade',data.direction,data.slot,data.id))end)end)
local function reviveCompanion(cb)
    local result=action('link:reviveStart')
    if not result.ok then if cb then cb(result)end;return end
    close()
    local ped=PlayerPedId()
    local body=companion and entity(companion.net)
    -- Kneel and inject; the progress bar is the same medical one players get.
    local used=BSLinkRevive.Start(body,result.duration)
    local ok,completed=pcall(function()
        return exports.bs_interactions:RunSearch('Reviving survivor',result.duration,{pose='none'})
    end)
    BSLinkRevive.Stop(used)
    if not ok or not completed or IsEntityDead(ped)then
        result={ok=false,error='Revival interrupted.'}
        if cb then cb(result)end
        return
    end
    result=action('link:reviveFinish');if cb then cb(result)end
end
openWheel=function()
    if wheelBusy or acting or not exports.bs_core:IsLoaded()then return end
    wheelBusy=true
    close()
    local hit,ped=GetEntityPlayerIsFreeAimingAt(PlayerId())
    aimedTarget=hit and ped~=0 and IsEntityAPed(ped)and not IsPedAPlayer(ped)and NetworkGetNetworkIdFromEntity(ped)or nil
    local result=refresh()
    if not result or not result.ok then wheelBusy=false;notify('Survivor Link unavailable.');return end
    local c=result.companion
    companion=c or nil
    local alive=c and c.life and c.life.status=='alive'
    -- Orders also go to a downed companion; he carries them out once he is up.
    local listening=c and c.life and c.life.status~='dead'
    local orders={}
    for _,entry in ipairs({{'follow','Follow','hand'},{'wait','Hold here','hand'},{'guard','Guard','vest'},
        {'hide','Stay hidden','mask'},{'sit','Sit tight','hand'},{'regroup','Regroup','hand'},
        {'enter','Get in','door'},{'exit','Get out','door'},{'target','Target NPC','scope'},{'cancel','Stand down','hand'}})do
        orders[#orders+1]={id=entry[1],label=entry[2],icon=entry[3],disabled=not listening or(entry[1]=='target'and not aimedTarget)}
    end
    local ok,choice=pcall(function()return BSB.Radial({title='SURVIVOR LINK',blur=false,hold=false,items={
        {id='switch',label='Switch survivor',icon='star',disabled=not alive,note=alive and c.name or 'Call a living survivor first'},
        {id='orders',label='Orders',icon='hand',disabled=not listening,note=listening and not alive and L('link.order_wait')or nil,submenu=orders},
        {id='trade',label='Trade',icon='bag',disabled=not alive},
        {id='gear',label=L('link.inv_open'),icon='bag',disabled=not c or c.life.status=='dead'},
        {id='ammo',label=L('link.ammo_title'),icon='scope',disabled=not c,note=c and L('link.ammo_'..(c.ammoMode or 'normal'))or nil,submenu={
            {id='ammo:conserve',label=L('link.ammo_conserve'),icon='scope',note=L('link.ammo_conserve_hint')},
            {id='ammo:normal',label=L('link.ammo_normal'),icon='scope',note=L('link.ammo_normal_hint')},
            {id='ammo:free',label=L('link.ammo_free'),icon='scope',note=L('link.ammo_free_hint')},
        }},
        {id='revive',label='Revive',icon='heart',disabled=not c or not c.life or c.life.status~='downed'},
        {id='manage',label='Survivors',icon='gear',note='Call or manage your saved survivors'},
    }})end)
    wheelBusy=false
    if not ok or not choice then return end
    if choice=='switch'then switchControl()
    elseif choice=='revive'then reviveCompanion()
    elseif choice=='gear'then openGear()
    elseif type(choice)=='string'and choice:sub(1,5)=='ammo:'then setAmmo(choice:sub(6))
    elseif choice=='trade'then startTrade()
    elseif choice=='manage'then open(false)
    else
        local result=action('link:command',choice,choice=='target'and aimedTarget or nil,choice=='hide'and 'hidden'or(c.stance or 'defensive'))
        if result.queued then notify(result.label)end
    end
end
RegisterNUICallback('revive',function(_,cb)CreateThread(function()reviveCompanion(cb)end)end)
AddEventHandler('bs:link:openTab',function(tab)
    if tab=='trade'then CreateThread(startTrade);return end
    if tab~='commands'then return end
    CreateThread(function()if not opened then open(false)end;if opened then post({action='tab',tab=tab})end end)
end)
AddEventHandler('bs:link:action',function(name)
    CreateThread(function()if name=='switch'then switchControl()elseif name=='revive'then reviveCompanion()elseif name=='gear'then openGear()
        elseif name=='squad'then local r=action('link:squadJoin');if r.ok then notify(L('link.squad_joined',{squad=r.label or ''}))end end end)
end)
RegisterNUICallback('factionJoin',function(_,cb)CreateThread(function()cb(action('link:factionJoin'));refresh()end)end)
RegisterNUICallback('squadJoin',function(_,cb)CreateThread(function()cb(action('link:squadJoin'));refresh()end)end)
RegisterNetEvent('bs:link:state',function(data)
    companion=data or nil;post({action='state',data=data,showHud=C.showHud})
    if not companion then lastCommand=nil end
end)
RegisterNetEvent('bs:link:dress',function(net,appearance,outfit,life,weapon)
    CreateThread(function()
        local untilAt=GetGameTimer()+7000;local ped=entity(net)
        while not ped and GetGameTimer()<untilAt do Wait(50);ped=entity(net)end
        if not ped then return end
        NetworkRequestControlOfEntity(ped)
        local controlDeadline=GetGameTimer()+2000
        while not NetworkHasControlOfEntity(ped)and GetGameTimer()<controlDeadline do NetworkRequestControlOfEntity(ped);Wait(25)end
        if not NetworkHasControlOfEntity(ped)then return end
        SetPedDefaultComponentVariation(ped)
        exports.bs_core:ApplyAppearanceTo(ped,appearance)
        if outfit then exports.bs_core:ApplyOutfit(ped,outfit)end
        SetEntityMaxHealth(ped,math.max(200,life.health or 200))
        SetEntityHealth(ped,life.status=='alive' and math.max(101,life.health or 200)or 105)
        SetPedArmour(ped,life.armour or 0)
        SetPedDropsWeaponsWhenDead(ped,false);SetPedCanRagdoll(ped,true)
        SetPedCombatAbility(ped,1);SetPedAccuracy(ped,C.accuracy)
        SetPedCombatAttributes(ped,5,true);SetPedCombatAttributes(ped,46,true);SetPedCombatAttributes(ped,58,true);SetPedFleeAttributes(ped,0,false)
        SetPedRelationshipGroupHash(ped,GetPedRelationshipGroupHash(PlayerPedId()))
        SetBlockingOfNonTemporaryEvents(ped,true)
        RemoveAllPedWeapons(ped,true)
        if weapon then GiveWeaponToPed(ped,joaat(weapon.weapon),weapon.ammo or 0,false,true)end
        lastCommand=nil
        if life.status~='alive'then TriggerEvent('bs:link:fallen',net,life)end
    end)
end)
RegisterNetEvent('bs:link:command',function(net,command,target,stance,rev)
    revision=rev or revision+1
    lastCommand={net=net,command=command,target=target,stance=stance,revision=revision};lastIssued=0
end)
-- Getting up is handled in cl_downed; here we only drop the stale order.
RegisterNetEvent('bs:link:revived',function(net,hp,how)
    lastIssued=0
    if how=='medical'then CreateThread(function()Wait(400);BSLinkRevive.Wake(entity(net))end)end
end)
local function issue(ped,order)
    local me=PlayerPedId();local command=order.command
    SetPedStealthMovement(ped,order.stance=='hidden',0)
    SetPedCombatMovement(ped,order.stance=='aggressive' and 2 or 1)
    if command=='target'then local target=entity(order.target);if target and not IsEntityDead(target)then TaskCombatPed(ped,target,0,16)else lastCommand=nil end
    elseif BSLinkMove.Following[command]then
        FreezeEntityPosition(ped,false);ClearPedTasks(ped);BSLinkMove.StartFollow(ped,me)
    elseif command=='enter'then
        local vehicle=GetVehiclePedIsIn(me,false)
        if vehicle~=0 then for seat=0,GetVehicleMaxNumberOfPassengers(vehicle)-1 do if IsVehicleSeatFree(vehicle,seat)then TaskEnterVehicle(ped,vehicle,10000,seat,2.0,1,0);break end end end
    elseif command=='exit'then local vehicle=GetVehiclePedIsIn(ped,false);if vehicle~=0 then TaskLeaveVehicle(ped,vehicle,0)end
    elseif command=='hide'then SetPedStealthMovement(ped,true,0);BSLinkMove.StartHold(ped,command,order.revision or 0)
    else BSLinkMove.StartHold(ped,command,order.revision or 0)end
end
-- Who last hurt the companion, the enemy we sent it after, and the body this logic drives.
local hurtBy,hurtAt,fighting,fightAt,trackedNet,pinnedNet=nil,0,nil,0,nil,nil
local function alive(p)return p and p~=0 and DoesEntityExist(p)and not IsEntityDead(p)end
local function threatFor(ped,order,me,cornered)
    if order.command=='target'then return nil end
    if alive(cornered)then return cornered end
    local at=GetEntityCoords(ped)
    -- Walkers that bite are evaded in defensive/hidden stance; anyone else who hurts it gets answered.
    if alive(hurtBy)and GetGameTimer()-hurtAt<6000 and #(GetEntityCoords(hurtBy)-at)<40.0 then
        if order.stance=='aggressive'or not Entity(hurtBy).state.bsZombie then return hurtBy end
    end
    if order.stance=='hidden'then return nil end
    local range=(order.stance=='aggressive'and 30.0 or 12.0)*(BSLinkGear and BSLinkGear.Reach()or 1.0)
    local best,bestD
    for _,enemy in ipairs(GetGamePool('CPed'))do
        if enemy~=ped and enemy~=me and alive(enemy)and not IsPedAPlayer(enemy)then
            local d=#(GetEntityCoords(enemy)-at)
            if d<range and(not bestD or d<bestD)then
                local st=Entity(enemy).state
                if not st.bsSurvivorLink then
                    local threat=st.bsZombie and not st.bsZombieDead and order.stance=='aggressive'
                    if not threat then
                        threat=HasEntityBeenDamagedByEntity(ped,enemy,true)or HasEntityBeenDamagedByEntity(me,enemy,true)
                            or IsPedInCombat(enemy,me)or IsPedInCombat(enemy,ped)
                    end
                    if threat then best,bestD=enemy,d end
                end
            end
        end
    end
    return best
end
CreateThread(function()
    while true do
        local delay=750
        if companion and C.enabled and companion.net~=trackedNet then
            -- New body (summon or switch): start its orders fresh, nothing carried from the old one.
            trackedNet=companion.net;lastIssued=0;fighting=nil;hurtBy=nil;pinnedNet=nil;BSLinkMove.Reset()
            if lastCommand and lastCommand.net~=companion.net then lastCommand=nil end
            BSLinkStealth.Reset();ClearEntityLastDamageEntity(PlayerPedId())
        end
        if companion and C.enabled then
            local ped=entity(companion.net)
            local me=PlayerPedId()
            if ped and ped~=me and companion.life.status=='alive'then
                if not NetworkHasControlOfEntity(ped)then NetworkRequestControlOfEntity(ped);delay=250
                else
                    -- Keep the body on this client so another player streaming it does not take it over.
                    if pinnedNet~=companion.net then SetNetworkIdCanMigrate(companion.net,false);pinnedNet=companion.net end
                    local order=lastCommand or {command=companion.command or 'follow',stance=companion.stance}
                    local avoiding,released,cornered=BSLinkStealth.Update(ped,order,me)
                    if released then lastIssued=0 end
                    local now=GetGameTimer()
                    if avoiding then fighting=nil;delay=250
                    else
                        local enemy=threatFor(ped,order,me,cornered)
                        if enemy then
                            if fighting~=enemy or(not IsPedInCombat(ped,enemy)and now-fightAt>1500)then
                                FreezeEntityPosition(ped,false);TaskCombatPed(ped,enemy,0,16)
                                fighting,fightAt=enemy,now
                            end
                            delay=250
                        else
                            -- Fight over: back to the standing order.
                            if fighting then fighting=nil;lastIssued=0 end
                            if lastIssued==0 then issue(ped,order);lastIssued=now
                            elseif BSLinkMove.Following[order.command]and not IsPedInAnyVehicle(ped,false)then BSLinkMove.FollowTick(ped,me);delay=250
                            elseif BSLinkMove.Stay[order.command]then BSLinkMove.Hold(ped,order.command);delay=400 end
                        end
                    end
                end
            end
        end
        Wait(delay)
    end
end)
AddEventHandler('bs:hook:player:spawned',function()
    StopScreenEffect('SwitchHUDIn');close();lastCommand=nil
    local data=exports.bs_core:GetData();local life=data.metadata and data.metadata.survivorLink
    if life and life.status=='alive'then
        SetEntityHealth(PlayerPedId(),math.max(101,math.min(GetEntityMaxHealth(PlayerPedId()),life.health or 200)))
        SetPedArmour(PlayerPedId(),life.armour or 0)
    end
end)
AddEventHandler('bs:hook:player:unloaded',function()close()end)
AddEventHandler('bs:ui:opened',function(who)if who~='survivorLink'then close()end end)
AddEventHandler('onResourceStop',function(res)if res==GetCurrentResourceName()then close();post({action='state',data=false})end end)

AddEventHandler('gameEventTriggered',function(name,args)
    if name~='CEventNetworkEntityDamage'or not companion or companion.life.status~='alive'then return end
    local ped=entity(companion.net);local victim=args[1]
    if ped and victim==ped and args[2]and args[2]~=0 and args[2]~=PlayerPedId()and DoesEntityExist(args[2])then hurtBy,hurtAt=args[2],GetGameTimer()end
    if ped and args[2]==ped and victim and DoesEntityExist(victim)then
        local zid=Entity(victim).state.bsZombie
        if zid then local hit,bone=GetPedLastDamageBone(victim);TriggerServerEvent('bs:link:hit',zid,hit and bone==31086)end
    end
end)
CreateThread(function()
    while true do
        Wait(1000)
        if companion and companion.life.status=='alive'then
            local ped=entity(companion.net)
            if ped then
                TriggerServerEvent('bs:link:vitals',companion.net,GetEntityHealth(ped))
                local at=GetEntityCoords(ped);local count=0
                for _,z in ipairs(GetGamePool('CPed'))do
                    if z~=ped and DoesEntityExist(z)and #(GetEntityCoords(z)-at)<2.0 then
                        local st=Entity(z).state
                        if st.bsZombie and st.zTarget==-companion.net then TriggerServerEvent('bs:link:claw',NetworkGetNetworkIdFromEntity(z));hurtBy,hurtAt=z,GetGameTimer();count=count+1;if count>=8 then break end end
                    end
                end
            end
        end
    end
end)

local function offerRescue(bag,key,value)
    if value~=true or bag~=('player:'..GetPlayerServerId(PlayerId()))or not companion or companion.life.status~='alive'then return end
    notify('Your other survivor can help. Open Survivor Link (L) to switch.')
end
AddStateBagChangeHandler('bsDowned',nil,offerRescue)
AddStateBagChangeHandler('bsDead',nil,offerRescue)

local hudPanel
AddEventHandler('bs:ui:opened',function(name)
    hudPanel=name
    post({action='hudVisibility',visible=false})
end)
AddEventHandler('bs:ui:closed',function(name)
    if name==nil or name==hudPanel then hudPanel=nil;post({action='hudVisibility',visible=true})end
end)
AddEventHandler('bs:link:membershipChanged',function()if opened then CreateThread(refresh)end end)
