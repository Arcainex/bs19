local C=SurvivorLink
local links,busy,nextSummon={}, {}, {}
local reservations={}
local function recallAt(user)return nextSummon[user]or GetResourceKvpInt('recall:'..user)end
local function setRecall(user,untilAt)nextSummon[user]=untilAt;SetResourceKvpInt('recall:'..user,untilAt)end
local function err(message)return {ok=false,error=message}end
local function player(src)return exports.bs_core:GetPlayer(src)end
local function allowed(src)
    local p=player(src)
    local summary=C.access=='admins' and exports.bs_core:GetPlayerSummary(src)or nil
    return C.enabled and p and (C.access=='everyone' or (C.access=='ace' and IsPlayerAceAllowed(src,C.ace)) or (C.access=='admins' and (summary and (summary.role=='admin' or summary.role=='superadmin'))))
end
local function restrained(src)
    local st=Player(src).state
    return st.bsCuffed or st.bsCarriedBy or st.bsRestrained
end
local function closeEnough(src,rec,range)
    local me=GetPlayerPed(src)
    return rec and rec.ped and DoesEntityExist(rec.ped) and GetPlayerRoutingBucket(src)==GetEntityRoutingBucket(rec.ped) and #(GetEntityCoords(me)-GetEntityCoords(rec.ped))<=(range or C.commandRange)
end
local function pos(ped)local p=GetEntityCoords(ped);return {x=p.x,y=p.y,z=p.z,h=GetEntityHeading(ped)}end
local function activeLife(src)
    local life=exports.bs_medical:LinkMedical(src,'read') or {status='alive'}
    local ped=GetPlayerPed(src)
    life.health=math.max(0,GetEntityHealth(ped));life.armour=GetPedArmour(ped);life.lastNeedsAt=os.time()
    if life.health<=100 and life.status=='alive'then life.status='downed';life.endsAt=os.time()+300 end
    return life
end
local function persist(src,rec)
    if rec and rec.ped and DoesEntityExist(rec.ped)then
        rec.position=pos(rec.ped)
        if rec.ready and rec.life.status=='alive'then
            local hp=GetEntityHealth(rec.ped)
            if hp>0 then rec.life.health=hp end
            rec.life.armour=GetPedArmour(rec.ped)
        end
    end
    if rec and rec.position then
        local life=rec.life
        if life.status=='grabbed'then life={status='downed',health=105,armour=0,endsAt=os.time()+exports.bs_medical:LinkReviveRules().bleedout}end
        local saved=exports.bs_core:LinkSave(src,rec.char.id,life,rec.position)
        if saved~=true then return false end
        LinkGear.Save(rec)
    end
    return true
end
local function remove(src,save,keepSquad)
    local rec=links[src];if not rec then return end
    if save then
        local ok,saved=pcall(persist,src,rec)
        if not ok or saved~=true then print(('[bs_survivor_link] companion %s save failed during removal: %s'):format(rec.char.id,tostring(saved)))end
    end
    pcall(function()exports.bs_inventory:LinkClose(src,rec.char.id)end)
    if rec.ped and DoesEntityExist(rec.ped)then DeleteEntity(rec.ped)end
    if reservations[rec.char.id]==src then reservations[rec.char.id]=nil end
    links[src]=nil
    TriggerClientEvent('bs:link:state',src,false)
    -- Like a player leaving: a despawned companion drops out of the squad. A switch keeps him (he is now you).
    if GetResourceState('bs_factions')=='started'then
        pcall(function()
            if keepSquad then exports.bs_factions:LinkedSquadRefresh(rec.char.id)else exports.bs_factions:LinkedSquadLeave(rec.char.id)end
        end)
    end
end
local function public(rec)
    if not rec then return false end
    if rec.life.status=='grabbed'then rec.life.grabLeft=math.max(0,(rec.life.grabEndsAt or 0)-os.time())end
    return {id=rec.char.id,level=tonumber(rec.char.level)or 1,name=rec.char.first_name..' '..rec.char.last_name,net=NetworkGetNetworkIdFromEntity(rec.ped),life=rec.life,command=rec.command,stance=rec.stance,ammoMode=rec.ammoMode or 'normal',weapon=LinkGear.Payload(rec),god=rec.god or nil,zIgnore=rec.zIgnore or nil}
end
-- Stealth flag lives on the companion body only; a new body after a switch gets it again from its stance.
local function stealthBag(rec)
    if not rec or not rec.ped or not DoesEntityExist(rec.ped)then return end
    local factor=rec.stance=='defensive'and math.max(0.0,math.min(1.0,tonumber(C.defensiveStealth)or 0.1))or nil
    if factor and factor>=1.0 then factor=nil end
    Entity(rec.ped).state:set('bsLinkStealth',factor or false,true)
end
local function push(src)
    local rec=links[src]
    TriggerClientEvent('bs:link:state',src,public(rec))
    if rec and rec.ped and DoesEntityExist(rec.ped)and rec.sharedStatus~=rec.life.status then
        rec.sharedStatus=rec.life.status
        -- Squad frames and blips read this; squad mates get a fresh view on every change.
        Entity(rec.ped).state:set('bsLinkLife',rec.life.status,true)
        if GetResourceState('bs_factions')=='started'then pcall(function()exports.bs_factions:LinkedSquadRefresh(rec.char.id)end)end
    end
end
local function arm(src,rec)LinkGear.Arm(rec)end
local appearanceSequence=0
local function appearancePayload(rec)
    return {net=NetworkGetNetworkIdFromEntity(rec.ped),token=rec.appearanceToken,charId=rec.char.id,
        appearance=rec.char.appearance,outfit=rec.char.metadata.outfit,life=rec.life,weapon=LinkGear.Payload(rec),accuracy=C.accuracy}
end
RegisterNetEvent('bs:link:appearanceReady',function(net,token,ok,reason)
    local src=source
    local rec=links[src]
    if not rec or rec.appearanceToken~=token or NetworkGetNetworkIdFromEntity(rec.ped)~=tonumber(net)then return end
    if ok==true then rec.ready=true;rec.appearanceError=nil
    else rec.appearanceError=tostring(reason or 'Appearance could not be applied.'):sub(1,160)end
end)
local function spawn(src,char,at,life,orders)
    local model=char.gender=='female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    local ped=CreatePed(4,joaat(model),at.x,at.y,at.z,at.h or 0,true,true)
    local deadline=GetGameTimer()+2500
    while ped~=0 and not DoesEntityExist(ped) and GetGameTimer()<deadline do Wait(25)end
    if ped==0 or not DoesEntityExist(ped)then return nil end
    local rec
    local ok,result=pcall(function()
        SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src));SetEntityOrphanMode(ped,2)
        life=life or char.metadata.survivorLink or {status='alive',health=200,armour=0}
        appearanceSequence=appearanceSequence+1
        -- After a switch the new companion body takes over the old one's standing order and stance.
        local keep=orders and orders.command
        if keep=='target'or keep=='enter'or keep=='exit'then keep='follow'end
        rec={ped=ped,char=char,life=life,position=at,command=keep or 'follow',stance=orders and orders.stance or 'defensive',ammoMode=orders and orders.ammoMode or 'normal',revision=(orders and orders.revision or 0)+1,
            ready=false,appearanceToken=appearanceSequence}
        links[src]=rec;reservations[char.id]=src
        Entity(ped).state:set('bsSurvivorLink',{owner=src,charId=char.id,name=char.first_name..' '..char.last_name},true)
        Entity(ped).state:set('bsProtected',true,true)
        stealthBag(rec)
        -- Health and appearance setters run on the owning game client, not FXServer.
        arm(src,rec)
        for attempt=1,3 do
            if not player(src)or links[src]~=rec or not DoesEntityExist(ped)then return nil end
            TriggerClientEvent('bs:link:appearance',src,appearancePayload(rec))
            local untilAt=GetGameTimer()+2500
            while links[src]==rec and not rec.ready and GetGameTimer()<untilAt do Wait(50)end
            if rec.ready then break end
        end
        if not rec.ready then error(rec.appearanceError or 'Companion appearance timed out.')end
        if not persist(src,rec)then error('Could not save the companion state.')end
        push(src)
        return rec
    end)
    if ok and result then return result end
    if rec and links[src]==rec then links[src]=nil;TriggerClientEvent('bs:link:state',src,false)end
    if reservations[char.id]==src then reservations[char.id]=nil end
    if DoesEntityExist(ped)then DeleteEntity(ped)end
    print(('[bs_survivor_link] companion %s spawn rolled back: %s'):format(char.id,tostring(result)))
    return nil
end

local function guarded(src,fn,allowIncapacitated)
    if not allowed(src)then return err('Survivor Link is disabled or unavailable for this account.')end
    if Player(src).state.bsLinkSpawning then return err('Your survivor is still loading.')end
    if busy[src]then return err('Please wait for the current action.')end
    if not allowIncapacitated then
        local life=activeLife(src)
        if life.status~='alive' or life.health<=125 then return err('Only your living active survivor can perform this action.')end
    end
    if restrained(src)then return err('You cannot command or switch while restrained.')end
    busy[src]=true
    local ok,result=pcall(fn)
    busy[src]=nil
    for id,owner in pairs(reservations)do if owner==src and not (links[src]and links[src].char.id==id)then reservations[id]=nil end end
    if not ok then print('[bs_survivor_link] '..tostring(result));return err('Action failed. Your characters have been kept.')end
    return result
end
local function savedLife(src,char)
    local life=char.metadata.survivorLink
    if not life then return nil end
    local now=os.time()
    if life.status=='downed'and (tonumber(life.endsAt)or 0)<=now then
        life.status='dead'
        life.diedAt=tonumber(life.endsAt)or now
        if life.diedAt<=0 then life.diedAt=now end
        life.availableAt=life.diedAt+C.replacementCooldown
        life.recallVersion=2
        local at={x=char.pos_x or 0,y=char.pos_y or 0,z=char.pos_z or 0,h=char.heading or 0}
        if not exports.bs_core:LinkSave(src,char.id,life,at)then return nil,'Could not save survivor recovery.'end
        char.metadata.survivorLinkRecallAt=life.availableAt
    end
    return life
end
local function deathRecall(src,rec,when)
    rec.life.status='dead';rec.life.diedAt=when or os.time()
    rec.life.availableAt=rec.life.diedAt+C.replacementCooldown
    rec.life.recallVersion=2
    local p=player(src)
    if p then setRecall(p.userId,rec.life.availableAt)end
end
BSB.RegisterCallback('link:roster',function(src)
    if not allowed(src)then return err('Survivor Link is disabled or access is restricted.')end
    local p=player(src);local rows=exports.bs_core:LinkRoster(src)
    for _,entry in ipairs(rows)do
        if entry.id~=p.charId and not reservations[entry.id]and not exports.bs_core:GetPlayerByCharId(entry.id)then
            local char=exports.bs_core:LinkCharacter(src,entry.id)
            if char then
                local life=savedLife(src,char)
                local at=math.max(life and life.availableAt or 0,char.metadata.survivorLinkRecallAt or 0)
                if life and life.status=='downed'then at=math.max(at,(life.endsAt or os.time())+C.replacementCooldown)end
                entry.linkAvailableIn=math.max(0,at-os.time())
                entry.linkStatus=life and life.status or 'alive'
            end
        end
    end
    return {ok=true,active=p.charId,characters=rows,companion=public(links[src]),cooldown=math.max(0,recallAt(p.userId)-os.time())}
end)
BSB.RegisterCallback('link:summon',function(src,id)
    return guarded(src,function()
        local p=player(src);id=tonumber(id)
        if links[src]then return err('Dismiss your current companion first.')end
        if not id or id%1~=0 or reservations[id]or id==p.charId or exports.bs_core:GetPlayerByCharId(id)then return err('That survivor is already active.')end
        if os.time()<recallAt(p.userId)then return err('Companion recall is cooling down.')end
        reservations[id]=src
        local char=exports.bs_core:LinkCharacter(src,id)
        if not char then return err('Choose one of your saved survivors.')end
        local life,recoveryError=savedLife(src,char)
        if recoveryError then return err(recoveryError)end
        if math.max(life and life.availableAt or 0,char.metadata.survivorLinkRecallAt or 0)>os.time()then return err('This survivor is recovering. Check the recall timer.')end
        if life and life.status=='dead'then
            local rules=exports.bs_medical:LinkReviveRules()
            if not exports.bs_core:LinkRecover(src,id,rules)then return err('Could not complete this survivor recovery.')end
            exports.bs_inventory:LinkEvict(id)
            char=exports.bs_core:LinkCharacter(src,id);life=char.metadata.survivorLink
        end
        if life and life.status=='downed'then return err('This survivor is recovering. They will be available after the downed window and recall cooldown.')end
        local at=pos(GetPlayerPed(src));at.x=at.x+2.0
        if not spawn(src,char,at,life)then return err('Could not create the companion.')end
        setRecall(p.userId,os.time()+C.spawnCooldown)
        return {ok=true}
    end)
end)
BSB.RegisterCallback('link:dismiss',function(src)
    return guarded(src,function()
        local rec=links[src]
        if not rec or rec.life.status=='downed'or rec.life.status=='grabbed'then return err('An incapacitated survivor cannot be dismissed.')end
        if not closeEnough(src,rec,C.range)then return err('Get closer before dismissing your companion.')end
        remove(src,true);return {ok=true}
    end)
end)
local switches={}
BSB.RegisterCallback('link:switch',function(src)
    return guarded(src,function()
        local rec=links[src];local p=player(src)
        if not rec or rec.life.status~='alive'then return err('You need a living companion to switch.')end
        if not closeEnough(src,rec,C.range)then return err('Your companion is beyond switching range.')end
        if os.time()<(switches[src] or 0)then return err('Please wait before switching again.')end
        if exports.bs_inventory:LinkBusy(src)then return err('Finish your trade or inventory action first.')end
        local life=activeLife(src)
        local old=exports.bs_core:LinkCharacter(src,p.charId)
        old.appearance=p.appearance;old.metadata=p.metadata
        local oldPosition=pos(GetPlayerPed(src));local targetPosition=pos(rec.ped)
        rec.life.health=math.max(0,GetEntityHealth(rec.ped));rec.life.armour=GetPedArmour(rec.ped)
        persist(src,rec)
        if not player(src)or player(src).charId~=p.charId or exports.bs_inventory:LinkBusy(src)then return err('Character or inventory changed. Try again.')end
        if not closeEnough(src,rec,C.range)or not DoesEntityExist(rec.ped)or GetEntityHealth(rec.ped)<=125 or rec.life.status~='alive'then return err('Your companion was injured or moved during the switch.')end
        life=activeLife(src);oldPosition=pos(GetPlayerPed(src))
        reservations[p.charId]=src
        local suspended=exports.bs_medical:LinkMedical(src,'suspend')
        local result=exports.bs_core:LinkSwitch(src,rec.char.id,targetPosition,life)
        if not result.ok then exports.bs_medical:LinkRestore(src,suspended or life);return result end
        local orders={command=rec.command,stance=rec.stance,ammoMode=rec.ammoMode,revision=rec.revision}
        remove(src,false,true)
        switches[src]=os.time()+C.switchCooldown
        Player(src).state:set('bsLinkSpawning',true,true)
        if life.status=='dead'then
            setRecall(p.userId,os.time()+C.replacementCooldown)
            life.availableAt=recallAt(p.userId)
            exports.bs_core:LinkSave(src,old.id,life,oldPosition)
        else spawn(src,old,oldPosition,life,orders)end
        return {ok=true}
    end,true)
end)
local commands={follow=true,wait=true,guard=true,hide=true,sit=true,stand=true,regroup=true,enter=true,exit=true,target=true,cancel=true}
BSB.RegisterCallback('link:command',function(src,command,target,stance)
    return guarded(src,function()
        local rec=links[src]
        -- A downed companion still hears you: the order waits until he is back up.
        if not closeEnough(src,rec,C.commandRange)or rec.life.status=='dead'then return err('Your companion is unavailable or out of command range.')end
        if not commands[command]then return err('Unknown command.')end
        local queued=rec.life.status~='alive'
        local entity
        if command=='target'then
            if not C.allowTarget then return err('Target commands are disabled by the server.')end
            entity=NetworkGetEntityFromNetworkId(tonumber(target) or 0)
            if not entity or entity==0 or not DoesEntityExist(entity) or GetEntityType(entity)~=1 or entity==rec.ped or GetEntityHealth(entity)<=0 then return err('Aim at a living NPC first.')end
            for _,s in ipairs(GetPlayers())do if GetPlayerPed(s)==entity then return err('Direct target commands cannot attack players.')end end
            if Entity(entity).state.bsSurvivorLink or GetEntityRoutingBucket(entity)~=GetPlayerRoutingBucket(src) or #(GetEntityCoords(entity)-GetEntityCoords(rec.ped))>C.commandRange then return err('Target is unavailable or too far away.')end
        end
        if stance=='defensive'or stance=='aggressive'or stance=='hidden'then rec.stance=stance end
        stealthBag(rec)
        rec.command=command;rec.revision=rec.revision+1
        TriggerClientEvent('bs:link:command',src,NetworkGetNetworkIdFromEntity(rec.ped),command,target,rec.stance,rec.revision)
        push(src)
        if queued then return {ok=true,queued=true,label=Lp(src,'link.order_queued')}end
        return {ok=true}
    end)
end)
local revives={}
BSB.RegisterCallback('link:reviveStart',function(src)
    return guarded(src,function()
        local rec=links[src];local rules=exports.bs_medical:LinkReviveRules()
        if not rec or rec.life.status~='downed'or rec.life.flat or (rec.life.endsAt or 0)<=os.time()then return err('This survivor cannot be revived.')end
        if not closeEnough(src,rec,rules.distance+1.0)then return err('Move closer to your fallen survivor.')end
        if rules.item and exports.bs_inventory:CountItem(src,rules.item)<1 then return err('You need the configured medical item.')end
        revives[src]={id=rec.char.id,started=GetGameTimer(),duration=rules.duration}
        return {ok=true,duration=rules.duration}
    end)
end)
BSB.RegisterCallback('link:reviveFinish',function(src)
    return guarded(src,function()
        local rec=links[src];local action=revives[src];revives[src]=nil
        local rules=exports.bs_medical:LinkReviveRules()
        if not action or not rec or action.id~=rec.char.id or GetGameTimer()-action.started<action.duration-100 or rec.life.status~='downed'or rec.life.flat or (rec.life.endsAt or 0)<=os.time()or not closeEnough(src,rec,rules.distance+1.0)then return err('Revival interrupted.')end
        if exports.bs_inventory:LinkBusy(src)then return err('Inventory is busy.')end
        if rules.item and not exports.bs_inventory:RemoveItem(src,rules.item,1)then return err('The medical item is no longer available.')end
        rec.life={status='alive',health=100+rules.health,armour=0}
        TriggerClientEvent('bs:link:health',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,rec.life.health)
        TriggerClientEvent('bs:link:revived',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.life.health,'medical')
        persist(src,rec);push(src);return {ok=true}
    end)
end)
BSB.RegisterCallback('link:bags',function(src)
    if not allowed(src)or activeLife(src).status~='alive'or activeLife(src).health<=125 or not C.allowTrade or busy[src]or not closeEnough(src,links[src],3.0)or links[src].life.status~='alive'then return err('Move beside your living companion to trade.')end
    local p=player(src);local rec=links[src]
    return {ok=true,mine=exports.bs_inventory:LinkBag(p.charId),theirs=exports.bs_inventory:LinkBag(rec.char.id),companion=public(rec)}
end)
BSB.RegisterCallback('link:trade',function(src,direction,slot,id)
    return guarded(src,function()
        local rec=links[src]
        if not C.allowTrade or (direction~='give'and direction~='take')or not closeEnough(src,rec,3.0)or rec.life.status~='alive'then return err('Move beside your living companion to trade.')end
        return exports.bs_inventory:LinkTransfer(src,rec.char.id,40,direction,slot,id)
    end)
end)
exports('Targets',function()
    local out={}
    if C.enabled then for src,rec in pairs(links)do if (rec.life.status=='alive'or rec.life.status=='grabbed')and not rec.zIgnore and DoesEntityExist(rec.ped)then
        local p=GetEntityCoords(rec.ped);local link=tonumber(Entity(rec.ped).state.bsLinkStealth);out[#out+1]={src=-NetworkGetNetworkIdFromEntity(rec.ped),x=p.x,y=p.y,z=p.z,stealth=rec.stance=='hidden',mult=1.0,link=link}
    end end end
    return out
end)
exports('Reserved',function(id)return reservations[tonumber(id)]~=nil end)
AddEventHandler('bs:hook:player:unloaded',function(p,reason)
    if reason~='survivor_link'and p then remove(p.source,true)end
end)
AddEventHandler('playerDropped',function()local src=source;remove(src,true);busy[src]=nil;switches[src]=nil;revives[src]=nil end)
AddEventHandler('onResourceStop',function(res)if res==GetCurrentResourceName()then for src in pairs(links)do remove(src,true)end end end)
AddEventHandler('bs_config:changed:bs_survivor_link',function()for src in pairs(links)do if not allowed(src)then remove(src,true)end end end)
-- Going down (or dying) in the field; also the end of a failed rescue.
local function fall(src,rec,hp)
    local rules=exports.bs_medical:LinkReviveRules()
    rec.life.status=hp<=0 and 'dead'or 'downed';rec.life.endsAt=os.time()+rules.bleedout
    rec.life.grabEndsAt,rec.life.grabNet,rec.life.grabLeft=nil,nil,nil
    if hp<=0 then deathRecall(src,rec)end
    if hp>0 then TriggerClientEvent('bs:link:health',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,105)end
    TriggerClientEvent('bs:link:fallen',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.life)
    local saved=persist(src,rec);push(src)
    if saved and rec.life.status=='dead'then remove(src,false)end
end
LinkCore={fall=fall,push=push,persist=persist,links=links,closeEnough=closeEnough}
CreateThread(function()
    local tick=0
    while true do Wait(1000);tick=tick+1
        for src,rec in pairs(links)do
            if not busy[src]and rec.ready then
                if not allowed(src)then remove(src,true)
                elseif not DoesEntityExist(rec.ped)then remove(src,true)
                else
                    local hp=GetEntityHealth(rec.ped)
                    if hp==0 and not (rec.reportedHealth==0 and GetGameTimer()-(rec.reportedAt or 0)<4000)then hp=rec.life.health or 200 end
                    -- Admin god mode: never drops below the down line.
                    if rec.god and hp>0 and hp<=125 and rec.life.status=='alive'then
                        TriggerClientEvent('bs:link:health',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,200);hp=200
                    end
                    if rec.life.status=='grabbed'then LinkGrab.Tick(src,rec,hp)
                    elseif rec.life.status=='alive'and hp>0 and hp<=125 and LinkGrab.Start(src,rec)then
                        -- A walker has him: rescue window instead of going straight down.
                    elseif rec.life.status=='alive'and hp<=125 then fall(src,rec,hp)
                    elseif rec.life.status=='downed'and (hp<=0 or os.time()>=(rec.life.endsAt or 0))then
                        deathRecall(src,rec,hp<=0 and os.time()or rec.life.endsAt)
                        if persist(src,rec)then remove(src,false)else push(src)end
                    end
                    if tick%15==0 and links[src]==rec then
                        if persist(src,rec)and rec.life.status=='dead'then remove(src,false)else push(src)end
                    end
                end
            end
        end
    end
end)

AddEventHandler('bs:hook:player:spawned',function(p)
    if p then Player(p.source).state:set('bsLinkSpawning',false,true)end
    if p and p.metadata and p.metadata.survivorLink then exports.bs_medical:LinkRestore(p.source,p.metadata.survivorLink)end
end)

local shots,claws={},{}
RegisterNetEvent('bs:link:ammo',function(ammo,rev)
    local src=source;local rec=links[src]
    if rec and rec.life.status=='alive'and LinkGear.Spend(rec,ammo,rev)and LinkGear.Pool(rec.weapon)<=0 then
        TriggerClientEvent('bs:ui:notify',src,{type='warn',message=Lp(src,'link.no_ammo',{name=rec.char.first_name}),duration=4000})
    end
end)
RegisterNetEvent('bs:link:hit',function(zid,head)
    local src=source;local rec=links[src]
    if not C.enabled or busy[src]or not rec or rec.life.status~='alive'or not rec.weapon or GetResourceState('bs_zombies')~='started'then return end
    local now=GetGameTimer();if now-(shots[src]or 0)<80 then return end;shots[src]=now
    if rec.weapon.ammoItem and LinkGear.Pool(rec.weapon)<=0 and GetSelectedPedWeapon(rec.ped)~=joaat('WEAPON_UNARMED')then return end
    exports.bs_zombies:LinkDamage(src,tonumber(zid),rec.ped,joaat(rec.weapon.weapon),head==true)
end)
RegisterNetEvent('bs:link:claw',function(znet)
    local src=source;local rec=links[src]
    if not C.enabled or busy[src]or not rec or rec.life.status~='alive'or GetResourceState('bs_zombies')~='started'then return end
    local ok,damage=pcall(function()return exports.bs_zombies:LinkClaw(tonumber(znet),rec.ped)end)
    if ok and type(damage)=='number'and damage>0 and not rec.god then rec.lastClaw={net=tonumber(znet),at=os.time()};TriggerClientEvent('bs:link:damage',src,NetworkGetNetworkIdFromEntity(rec.ped),math.min(250,damage))end
end)

RegisterNetEvent('bs:link:vitals',function(net,hp)
    local rec=links[source];hp=tonumber(hp)
    if not rec or not hp or hp~=hp or net~=NetworkGetNetworkIdFromEntity(rec.ped)or hp<0 or hp>10000 then return end
    rec.reportedHealth=math.floor(hp);rec.reportedAt=GetGameTimer()
end)

exports('GetCompanion',function(src)
    src=tonumber(src);local rec=links[src]
    if not rec or not DoesEntityExist(rec.ped)then return false end
    local out=public(rec);out.owner=src;return out
end)
exports('GetCompanionByCharId',function(id)
    id=tonumber(id)
    for src,rec in pairs(links)do
        if rec.char.id==id and DoesEntityExist(rec.ped)then local out=public(rec);out.owner=src;return out end
    end
    return false
end)

-- Re-equip after his gear changed: open inventory drag, trade, ammo taken or given.
local function rearm(src,rec)
    if links[src]~=rec or not DoesEntityExist(rec.ped)then return end
    LinkGear.Arm(rec)
    TriggerClientEvent('bs:link:weapon',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,rec.life.status=='alive'and LinkGear.Payload(rec)or nil)
    push(src)
end
LinkRearm=rearm
AddEventHandler('bs:inventory:characterChanged',function(charId)
    for src,rec in pairs(links)do if rec.char.id==tonumber(charId)then CreateThread(function()rearm(src,rec)end)end end
end)
BSB.RegisterCallback('link:inventory',function(src)
    if not allowed(src)or busy[src]then return err(Lp(src,'link.e_inv_far'))end
    local rec=links[src]
    if not rec or rec.life.status=='dead'or not closeEnough(src,rec,3.0)then return err(Lp(src,'link.e_inv_far'))end
    if exports.bs_inventory:LinkBusy(src)then return err('Finish your trade or inventory action first.')end
    local name=rec.char.first_name..' '..rec.char.last_name
    local char=exports.bs_core:LinkCharacter(src,rec.char.id)
    if not char then return err('That survivor is unavailable.')end
    local result=exports.bs_inventory:LinkOpen(src,rec.char.id,GetEntityCoords(rec.ped),Lp(src,'link.inv_label',{name=name}),char.inventoryCarry)
    if result.ok then
        local sheet={}
        if GetResourceState('bs_skills')=='started'then
            local ok,data=pcall(function()return exports.bs_skills:LinkedCharacterSheet(rec.char.id)end)
            if ok and data then sheet=data end
        end
        local stats=char.inventoryStats or {name=name,level=char.level,classId=char.class}
        stats.health=math.max(0,GetEntityHealth(rec.ped)-100);stats.armour=GetPedArmour(rec.ped)
        stats.bodySex=char.gender=='female'and 'female'or 'male'
        local effects=sheet.effects or {};effects.points=char.skill_points or 0
        effects.carryWeight=(char.inventoryCarry or 40)-40+(effects.carryWeight or 0)
        result.subject={id=rec.char.id,net=NetworkGetNetworkIdFromEntity(rec.ped),stats=stats,levels=sheet.levels or{},trees=sheet.trees or{},effects=effects}
    end
    return result
end)
BSB.RegisterCallback('link:ammoMode',function(src,mode)
    if not allowed(src)then return err('Survivor Link is disabled or unavailable for this account.')end
    local rec=links[src]
    if not rec or not LinkGear.Modes[mode]then return err('Unknown command.')end
    if not closeEnough(src,rec,C.commandRange)then return err('Your companion is unavailable or out of command range.')end
    rec.ammoMode=mode
    if rec.weapon then rec.weapon.rev=rec.weapon.rev+1 end
    TriggerClientEvent('bs:link:weapon',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,rec.life.status=='alive'and LinkGear.Payload(rec)or nil)
    push(src)
    return {ok=true,mode=mode,label=Lp(src,'link.ammo_set',{mode=Lp(src,'link.ammo_'..mode)})}
end)
-- Trading goes through the normal player trade window; the companion side accepts on its own.
BSB.RegisterCallback('link:tradeStart',function(src)
    local rec=links[src]
    if not allowed(src)or not C.allowTrade or busy[src]or not rec or rec.life.status~='alive'or not closeEnough(src,rec,3.0)then return err('Move beside your living companion to trade.')end
    local life=activeLife(src)
    if life.status~='alive'or restrained(src)then return err('Only your living active survivor can perform this action.')end
    return exports.bs_inventory:LinkTradeStart(src,rec.char.id,rec.char.first_name..' '..rec.char.last_name)
end)

-- F10 > Survivor Link test tools. Only bs_admin may call this; it has already checked staff and logs to bs_guard_log.
local function nearestWalker(at,range)
    local best,bestD
    for _,ped in ipairs(GetAllPeds())do
        local st=Entity(ped).state
        if st.bsZombie and not st.bsZombieDead and GetEntityHealth(ped)>0 then
            local d=#(GetEntityCoords(ped)-at)
            if d<range and(not bestD or d<bestD)then best,bestD=ped,d end
        end
    end
    return best
end
local function standUp(src,rec)
    if rec.life.status=='grabbed'then pcall(function()exports.bs_zombies:LinkHold(rec.life.grabNet,NetworkGetNetworkIdFromEntity(rec.ped),false)end)end
    rec.life={status='alive',health=200,armour=0}
    local net=NetworkGetNetworkIdFromEntity(rec.ped)
    TriggerClientEvent('bs:link:health',src,net,rec.appearanceToken,200)
    TriggerClientEvent('bs:link:revived',src,net,200,'medical')
    persist(src,rec);push(src)
end
local function reissue(src,rec)
    rec.revision=rec.revision+1;stealthBag(rec)
    TriggerClientEvent('bs:link:command',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.command,nil,rec.stance,rec.revision)
    push(src)
end
local adminTools={
    god=function(src,rec)rec.god=not rec.god or nil;push(src);return 'god mode '..(rec.god and 'ON'or 'OFF')end,
    ignore=function(src,rec)rec.zIgnore=not rec.zIgnore or nil;push(src);return 'zombies ignore companion: '..(rec.zIgnore and 'ON'or 'OFF')end,
    down=function(src,rec)
        if rec.life.status~='alive'then return nil,'companion is not standing'end
        if rec.god then rec.god=nil end
        fall(src,rec,105);return 'companion forced down'
    end,
    revive=function(src,rec)
        if rec.life.status~='downed'and rec.life.status~='grabbed'then return nil,'companion is not down'end
        standUp(src,rec);return 'companion revived'
    end,
    grab=function(src,rec)
        if rec.life.status~='alive'then return nil,'companion is not standing'end
        local at=GetEntityCoords(rec.ped)
        local z=nearestWalker(at,40.0)
        if not z then return nil,'no walker within 40 m of the companion'end
        SetEntityCoords(z,at.x+0.8,at.y+0.2,at.z-0.9,false,false,false,false)
        rec.lastClaw={net=NetworkGetNetworkIdFromEntity(z),at=os.time()}
        if not LinkGrab.Start(src,rec,true)then return nil,'grab could not start'end
        return 'companion grabbed by the nearest walker'
    end,
    tp=function(src,rec)
        local p=GetEntityCoords(GetPlayerPed(src))
        SetEntityRoutingBucket(rec.ped,GetPlayerRoutingBucket(src))
        SetEntityCoords(rec.ped,p.x+1.2,p.y+0.6,p.z-0.9,false,false,false,false)
        return 'companion teleported to you'
    end,
    reset=function(src,rec)
        rec.command='follow';TriggerClientEvent('bs:link:adminReset',src,NetworkGetNetworkIdFromEntity(rec.ped))
        reissue(src,rec);return 'companion AI reset (follow)'
    end,
    dump=function(src,rec)
        local p=GetEntityCoords(rec.ped)
        local out={state=public(rec),serverHealth=GetEntityHealth(rec.ped),pos={x=p.x,y=p.y,z=p.z},bucket=GetEntityRoutingBucket(rec.ped),
            owner=NetworkGetEntityOwner(rec.ped),gear=rec.weapon,lastClaw=rec.lastClaw,ready=rec.ready,busy=busy[src]==true,char=rec.char.id}
        local text=json.encode(out)
        print(('[bs_survivor_link] dump for %s: %s'):format(GetPlayerName(src)or src,text))
        TriggerClientEvent('bs:link:adminDump',src,text)
        return 'state printed to F8 and the server console'
    end,
    overlay=function(src,rec)TriggerClientEvent('bs:link:adminOverlay',src);return 'debug overlay toggled'end,
    loadout=function(src,rec)
        for _,e in ipairs({{'carbine',1},{'ammo_rifle',6},{'machete',1},{'medkit',1}})do
            local ok,why=exports.bs_inventory:LinkGive(rec.char.id,e[1],e[2])
            if not ok then return nil,'loadout stopped at '..e[1]..': '..tostring(why)end
        end
        LinkRearm(src,rec);return 'test loadout given (carbine, 90 rifle rounds, machete, medkit)'
    end,
}
for _,stance in ipairs({'defensive','aggressive','hidden'})do
    adminTools['stance_'..stance]=function(src,rec)rec.stance=stance;reissue(src,rec);return 'stance '..stance end
end
for mode in pairs(LinkGear.Modes)do
    adminTools['ammo_'..mode]=function(src,rec)
        rec.ammoMode=mode
        if rec.weapon then rec.weapon.rev=rec.weapon.rev+1 end
        TriggerClientEvent('bs:link:weapon',src,NetworkGetNetworkIdFromEntity(rec.ped),rec.appearanceToken,rec.life.status=='alive'and LinkGear.Payload(rec)or nil)
        push(src);return 'ammo use '..mode
    end
end
exports('AdminTool',function(src,mode)
    if GetInvokingResource()~='bs_admin'then return {ok=false,error='not allowed'}end
    src=tonumber(src);local tool=adminTools[mode]
    if not tool then return {ok=false,error='unknown tool'}end
    local rec=links[src]
    if not rec or not rec.ped or not DoesEntityExist(rec.ped)then return {ok=false,error='call a companion first (F5 > Survivor Link)'}end
    local note,why=tool(src,rec)
    if not note then return {ok=false,error=why}end
    return {ok=true,note=note}
end)
