local states = {}
local function notify(src,kind,message)
    TriggerClientEvent('bs:bodily:notify',src,{type=kind,title=Lp(src,'bd.notif_title'),message=message})
end
local function publish(src,state)
    Player(src).state:set('bsSoiled',state.soiledUntil>os.time(),true)
end
local function save(state)
    SetResourceKvp('bodily_'..state.charId,json.encode({pee=state.pee,poop=state.poop,queue=state.queue,soiledUntil=state.soiledUntil,peeRate=state.peeRate,poopRate=state.poopRate}))
end
local function ensure(src)
    if not Bodily.enabled then return end
    local player=exports.bs_core:GetPlayer(src)
    if not player or not player.charId then return end
    local state=states[src]
    if state and state.charId==player.charId then return state end
    if state then save(state) end
    state={charId=player.charId,pee=0,poop=0,queue={},soiledUntil=0,last=os.time(),peeRate=100/math.random(Bodily.pee.minSeconds,Bodily.pee.maxSeconds),poopRate=100/math.random(Bodily.poop.minSeconds,Bodily.poop.maxSeconds)}
    local raw=GetResourceKvpString('bodily_'..player.charId)
    if raw then
        local ok,p=pcall(json.decode,raw)
        if ok and type(p)=='table' then
            for _,kind in ipairs({'pee','poop'}) do if type(p[kind])=='number' then state[kind]=math.max(0,math.min(120,p[kind])) end end
            if type(p.queue)=='table' then state.queue=p.queue end
            if type(p.soiledUntil)=='number' then state.soiledUntil=p.soiledUntil end
            for _,kind in ipairs({'peeRate','poopRate'}) do if type(p[kind])=='number' and p[kind]>0 and p[kind]<1 then state[kind]=p[kind] end end
        end
    end
    states[src]=state;publish(src,state);return state
end
local function alive(src)
    local ped=GetPlayerPed(src)
    if ped==0 or GetEntityHealth(ped)<=0 then return false end
    if GetResourceState('bs_medical')=='started' then
        local ok,down=pcall(function() return exports.bs_medical:IsDowned(src) end)
        if ok and down then return false end
    end
    return true
end
local function validAction(src,action)
    return alive(src) and GetPlayerRoutingBucket(src)==action.bucket and #(GetEntityCoords(GetPlayerPed(src))-action.position)<=1.2 and GetVehiclePedIsIn(GetPlayerPed(src),false)==0
end
local function update(src,state)
    local now=os.time();local elapsed=math.max(0,math.min(60,now-state.last));state.last=now
    if not alive(src) then state.action=nil;return end
    state.pee=state.pee+elapsed*state.peeRate;state.poop=state.poop+elapsed*state.poopRate
    for i=#state.queue,1,-1 do
        local meal=state.queue[i]
        if type(meal)~='table' or type(meal.at)~='number' or (meal.kind~='pee' and meal.kind~='poop') or type(meal.amount)~='number' then table.remove(state.queue,i)
        elseif meal.at<=now then state[meal.kind]=state[meal.kind]+math.max(0,math.min(100,meal.amount));table.remove(state.queue,i) end
    end
    for _,kind in ipairs({'pee','poop'}) do
        if state[kind]>=75 and not state[kind..'Warned'] then
            state[kind..'Warned']=true;notify(src,'warn',Lp(src,kind=='pee' and 'bd.bladder_urgent' or 'bd.stomach_urgent'))
        end
        if state[kind]>=120 then
            state[kind]=0;state[kind..'Warned']=false;state.action=nil;state.soiledUntil=now+Bodily.soiledSeconds;publish(src,state)
            notify(src,'warn',Lp(src,kind=='pee' and 'bd.accident' or 'bd.soiled_self')..' '..Lp(src,'bd.smell_long'));save(state)
        end
    end
    if state.soiledUntil>0 and state.soiledUntil<=now then state.soiledUntil=0;publish(src,state);notify(src,'info',Lp(src,'bd.faded')) end
    if state.action and not validAction(src,state.action) then state.action=nil end
end
exports('RecordConsumption',function(src,item,hunger,thirst)
    if GetInvokingResource()~='bs_inventory' then return false end
    src=tonumber(src);local state=src and ensure(src)
    if not state or not alive(src) or type(item)~='string' then return false end
    update(src,state)
    local digest=Bodily.digestion
    for _,entry in ipairs({{kind='poop',value=hunger,factor=digest.foodFactor,delay=digest.foodDelay},{kind='pee',value=thirst,factor=digest.drinkFactor,delay=digest.drinkDelay}}) do
        local value=tonumber(entry.value)
        if value and value==value and value>0 then
            local amount=math.min(100,value)*entry.factor
            state.queue[#state.queue+1]={kind=entry.kind,amount=amount,at=os.time()+entry.delay}
        end
    end
    save(state);return true
end)
BSB.RegisterCallback('bodily:status',function(src)
    local state=ensure(src)
    if not state then return {ok=false,message=Lp(src,'bd.char')} end
    update(src,state)
    return {ok=true,pee=math.min(100,math.floor(state.pee)),poop=math.min(100,math.floor(state.poop)),soiled=state.soiledUntil>os.time(),soiledRemaining=math.max(0,state.soiledUntil-os.time())}
end)
BSB.RegisterCallback('bodily:begin',function(src,kind)
    local state=ensure(src)
    if not state or (kind~='pee' and kind~='poop') or not alive(src) then return {ok=false,message=Lp(src,'bd.unavail')} end
    update(src,state)
    if state.action or state[kind]<10 or GetVehiclePedIsIn(GetPlayerPed(src),false)~=0 then return {ok=false,message=Lp(src,'bd.not_yet')} end
    local duration=kind=='pee' and Bodily.relief.peeMs or Bodily.relief.poopMs
    local token=('%s:%s:%s'):format(src,GetGameTimer(),math.random(100000,999999))
    state.action={kind=kind,token=token,started=GetGameTimer(),duration=duration,position=GetEntityCoords(GetPlayerPed(src)),bucket=GetPlayerRoutingBucket(src)}
    return {ok=true,token=token,duration=duration}
end)
BSB.RegisterCallback('bodily:relieve',function(src,kind,token)
    local state=ensure(src);local action=state and state.action
    if not action or action.kind~=kind or action.token~=token or not validAction(src,action) or GetGameTimer()-action.started<action.duration or GetGameTimer()-action.started>action.duration+5000 then
        if state then state.action=nil end
        return {ok=false,message=Lp(src,'bd.unavail')}
    end
    state.action=nil;state[kind]=0;state[kind..'Warned']=false;save(state)
    return {ok=true,message=Lp(src,kind=='pee' and 'bd.peed' or 'bd.pooped')}
end)
RegisterNetEvent('bs:bodily:cancel',function() local state=states[source];if state then state.action=nil end end)
AddEventHandler('bs:hook:player:loaded',function(player) if player and player.source then ensure(player.source) end end)
AddEventHandler('bs:hook:player:unloaded',function(player) local src=player and player.source;if src and states[src] then save(states[src]);states[src]=nil end end)
AddEventHandler('playerDropped',function() if states[source] then save(states[source]);states[source]=nil end end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for _,state in pairs(states) do save(state) end end end)
CreateThread(function()
    while true do
        for _,id in ipairs(GetPlayers()) do local src=tonumber(id);local state=ensure(src);if state then update(src,state) end end
        Wait(500)
    end
end)
CreateThread(function() while true do Wait(60000);for _,state in pairs(states) do save(state) end end end)

local lastFart, activeFart = {}, {}

local function sendFart(src, event, ...)
    local bucket = GetPlayerRoutingBucket(src)
    for _, id in ipairs(GetPlayers()) do
        local recipient = tonumber(id)
        if GetPlayerRoutingBucket(recipient) == bucket then
            TriggerClientEvent(event, recipient, ...)
        end
    end
end

local function stopFart(src)
    if not activeFart[src] then return end
    activeFart[src] = nil
    sendFart(src, 'bs:bodily:fartStop', src)
end

RegisterNetEvent('bs:bodily:fartStart', function()
    local src = source
    local enabled = Bodily.funEnabled
    if GetResourceState('bs_config') == 'started' then
        local ok, value = pcall(function() return exports.bs_config:Get('Bodily.funEnabled', enabled) end)
        if ok then enabled = value end
    end
    if not Bodily.enabled or not enabled or not ensure(src) or not alive(src) then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return end
    local now = GetGameTimer()
    if activeFart[src] or now - (lastFart[src] or -100000) < Bodily.fartCooldown then return end
    lastFart[src] = now
    local variant = math.random(1, 20)
    local pos = GetEntityCoords(ped)
    activeFart[src] = now
    sendFart(src, 'bs:bodily:fartStart', {x=pos.x,y=pos.y,z=pos.z}, variant, src)
    SetTimeout(15000, function() if activeFart[src] == now then stopFart(src) end end)
end)

RegisterNetEvent('bs:bodily:fartStop', function()
    local src = source
    local started = activeFart[src]
    if not started then return end
    local remaining = 450 - (GetGameTimer() - started)
    if remaining > 0 then
        SetTimeout(remaining, function() if activeFart[src] == started then stopFart(src) end end)
    else
        stopFart(src)
    end
end)
AddEventHandler('playerDropped', function()
    stopFart(source)
    lastFart[source] = nil
end)

RegisterNetEvent('bs:bodily:reliefEffect', function(kind, duration)
    local src = source
    local state = states[src]
    local action = state and state.action
    if not action or action.kind ~= kind or not validAction(src, action) then return end
    local enabled = Bodily.funEnabled
    if GetResourceState('bs_config') == 'started' then
        local ok, value = pcall(function() return exports.bs_config:Get('Bodily.funEnabled', enabled) end)
        if ok then enabled = value end
    end
    if not enabled then return end
    if duration ~= action.duration then return end
    local pos = action.position
    for _, id in ipairs(GetPlayers()) do
        local recipient = tonumber(id)
        if GetPlayerRoutingBucket(recipient) == action.bucket then
            TriggerClientEvent('bs:bodily:reliefFx', recipient, action.bucket, {x=pos.x,y=pos.y,z=pos.z}, kind, duration, src)
        end
    end
end)
