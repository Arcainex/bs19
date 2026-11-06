local progress, notices, cooldown, loaded, sourceCharacters, syncRate = {}, {}, {}, {}, {}, {}
local function persist(cid)
    local entries={}
    for id,m in pairs(progress[cid] or {}) do
        entries[id]={kind=m.kind,target=m.target,expires=m.expires,title=m.title,complete=m.complete==true,claimed=m.claimed==true,claimState=m.claimState,effectState=m.effectState,rewardItem=m.rewardItem,rewardAmount=m.rewardAmount,repairItem=m.repairItem,repairAmount=m.repairAmount,bucket=m.bucket or 0,cooldown=cooldown[cid..':'..id]}
    end
    local ok,raw=pcall(json.encode,{version=1,missions=entries})
    if not ok then return false end
    local key='relay_missions_v1_'..cid
    local written=pcall(SetResourceKvp,key,raw)
    return written and GetResourceKvpString(key)==raw
end
local function restore(cid)
    if loaded[cid] then return end
    loaded[cid]=true;progress[cid]={}
    local raw=GetResourceKvpString('relay_missions_v1_'..cid)
    if not raw or #raw>131072 then return end
    local ok,data=pcall(json.decode,raw)
    if not ok or type(data)~='table' or data.version~=1 or type(data.missions)~='table' then return end
    local count=0
    for id,m in pairs(data.missions) do
        if count>=64 then break end
        if type(id)=='string' and #id<=120 and type(m)=='table' and (m.kind=='repair' or m.kind=='sabotage') and type(m.target)=='string' and m.target:match('^[%w_-]+$') and id==m.kind..':'..m.target and type(m.expires)=='number' then
            if m.complete==true or m.effectState=='pending' or m.expires>os.time() then
                if not m.claimed or (tonumber(m.cooldown) or 0)>os.time() then
                    progress[cid][id]={kind=m.kind,target=m.target,expires=m.expires,title=tostring(m.title or 'Relay contract'):sub(1,140),complete=m.complete==true,claimed=m.claimed==true,claimState=m.claimState=='pending' and 'pending' or nil,effectState=m.effectState=='pending' and 'pending' or nil,rewardItem=type(m.rewardItem)=='string' and m.rewardItem or RelayMissions.rewardItem,rewardAmount=math.max(1,math.min(1000,tonumber(m.rewardAmount) or RelayMissions.rewardAmount)),repairItem=type(m.repairItem)=='string' and m.repairItem or RelayMissions.repairItem,repairAmount=math.max(1,math.min(1000,tonumber(m.repairAmount) or RelayMissions.repairAmount)),bucket=tonumber(m.bucket) or 0}
                    if type(m.cooldown)=='number' then cooldown[cid..':'..id]=m.cooldown end
                    count=count+1
                end
            end
        end
    end
end
local function character(src)
    local ok,p=pcall(function() return exports.bs_core:GetPlayer(src) end)
    local value=ok and p and tonumber(p.charId) or nil
    local cid=value and value>0 and value%1==0 and ('%.0f'):format(value) or nil
    if cid then
        cid=tostring(cid)
        local previous=sourceCharacters[src]
        if previous and previous~=cid then
            for _,m in pairs(progress[previous] or {}) do m.started=nil;m.lastSeen=nil end
            persist(previous)
            progress[previous]=nil;loaded[previous]=nil
            local prefix=previous..':'
            for key in pairs(cooldown) do if key:sub(1,#prefix)==prefix then cooldown[key]=nil end end
            TriggerClientEvent('bs:relay:reset',src)
        end
        sourceCharacters[src]=cid;restore(cid)
    end
    return cid
end
local function nodes() return exports.bs_radio:GetRadioSettings().antennas or {} end
local function node(id) for _,n in ipairs(nodes()) do if n.id==id then return n end end end
local function parse(id)
    local kind,target=tostring(id or ''):match('^(%a+):([%w_-]+)$')
    if kind~='sabotage' and kind~='repair' then return end
    return kind,target
end
local function get(src,id)
    local cid=character(src)
    return cid and progress[cid] and progress[cid][id],cid
end
local function applicable(kind,n) return n and n.enabled and not n.owner and ((kind=='repair' and n.disrupted) or (kind=='sabotage' and not n.disrupted)) end
local function nearby(src,n)
    local ped=GetPlayerPed(src)
    if ped==0 or GetEntityHealth(ped)<=0 then return false end
    if GetResourceState('bs_medical')=='started' then local ok,down=pcall(function() return exports.bs_medical:IsDowned(src) end);if not ok or down then return false end end
    return n and GetPlayerRoutingBucket(src)==0 and ped~=0 and #(GetEntityCoords(GetPlayerPed(src))-vector3(n.x,n.y,n.z))<=5.0
end
exports('MissionLogList',function(src)
    local cid=character(src);if not cid then return {} end
    local out={};local changed=false
    for id,m in pairs(progress[cid] or {}) do
        if not m.claimState and not m.effectState and ((not m.complete and m.expires<=os.time()) or (m.claimed and (cooldown[cid..':'..id] or 0)<=os.time())) then progress[cid][id]=nil;cooldown[cid..':'..id]=nil;changed=true end
    end
    if changed then persist(cid) end
    for _,n in ipairs(nodes()) do
        if n.enabled and not n.owner then
            local kind=n.disrupted and 'repair' or 'sabotage'
            local id=kind..':'..n.id
            local m=progress[cid] and progress[cid][id]
            if m and m.expires<os.time() and not m.complete and not m.effectState then progress[cid][id]=nil;persist(cid);m=nil end
            if not cooldown[cid..':'..id] or cooldown[cid..':'..id]<=os.time() or m then
                out[#out+1]={id=id,title=(kind=='repair' and 'Restore ' or 'Disrupt ')..n.label,group='Relay contracts',offer=not m,complete=m and m.complete or false,claimed=m and m.claimed or false,noClaim=m and (m.claimState=='pending' or m.effectState=='pending') or false,steps={{label='Reach the relay and hold the interaction',done=m and m.complete or false}},reward={{item=m and m.rewardItem or RelayMissions.rewardItem,amount=m and m.rewardAmount or RelayMissions.rewardAmount}},hint=m and (m.claimState or m.effectState) and 'Mission delivery requires administrator review.' or kind=='repair' and ('Requires '..RelayMissions.repairAmount..' '..RelayMissions.repairItem) or 'Disruption is temporary. Other survivors can restore the relay.'}
            end
        end
    end
    -- A completed contract remains claimable even after its relay changes state.
    for id,m in pairs(progress[cid] or {}) do
        if m.complete or m.effectState or m.expires>os.time() then
            local found=false;for _,entry in ipairs(out) do if entry.id==id then found=true end end
            if not found then out[#out+1]={id=id,title=m.title,group='Relay contracts',offer=false,complete=m.complete or false,claimed=m.claimed or false,noClaim=m.claimState=='pending' or m.effectState=='pending',hint=(m.claimState=='pending' or m.effectState=='pending') and 'Mission delivery requires administrator review.' or nil,steps={{label='Relay objective',done=m.complete or false}},reward={{item=m and m.rewardItem or RelayMissions.rewardItem,amount=m and m.rewardAmount or RelayMissions.rewardAmount}}} end
        end
    end
    return out
end)
exports('MissionLogAccept',function(src,id)
    local kind,target=parse(id);local n=target and node(target);local cid=character(src)
    if not cid or GetPlayerRoutingBucket(src)~=0 or not applicable(kind,n) then return {ok=false,error='This relay contract is unavailable.'} end
    local existing=get(src,id)
    if existing and existing.claimed and (cooldown[cid..':'..id] or 0)<=os.time() then progress[cid][id]=nil;existing=nil end
    local count=0;for _ in pairs(progress[cid] or {}) do count=count+1 end
    if count>=64 then return {ok=false,error='Finish or claim existing relay contracts first.'} end
    if existing then return {ok=false,error='Contract already accepted.'} end
    if cooldown[cid..':'..id] and cooldown[cid..':'..id]>os.time() then return {ok=false,error='This contract is cooling down.'} end
    progress[cid]=progress[cid] or {}
    progress[cid][id]={kind=kind,target=target,expires=os.time()+RelayMissions.offerLifetime,title=(kind=='repair' and 'Restore ' or 'Disrupt ')..n.label,bucket=GetPlayerRoutingBucket(src),rewardItem=RelayMissions.rewardItem,rewardAmount=RelayMissions.rewardAmount,repairItem=RelayMissions.repairItem,repairAmount=RelayMissions.repairAmount}
    if not persist(cid) then progress[cid][id]=nil;return {ok=false,error='Mission state could not be saved. Try again later.'} end
    TriggerClientEvent('bs:relay:objective',src,{id=id,label=n.label,x=n.x,y=n.y,z=n.z,expires=os.time()+RelayMissions.offerLifetime,seconds=RelayMissions.actionSeconds})
    return {ok=true}
end)
RegisterNetEvent('bs:relay:begin',function(id)
    local src=source;local m=get(src,id)
    if not m or m.complete or m.effectState or m.bucket~=GetPlayerRoutingBucket(src) or m.expires<os.time() or not applicable(m.kind,node(m.target)) or not nearby(src,node(m.target)) then return end
    if m.started then m.lastSeen=GetGameTimer();return end
    m.started=GetGameTimer();m.lastSeen=GetGameTimer()
end)
RegisterNetEvent('bs:relay:cancel',function(id) local m=get(source,id);if m then m.started=nil;m.lastSeen=nil end end)
exports('MissionLogClaim',function(src,id)
    local m,cid=get(src,id)
    if not m or not m.complete or m.claimed or m.claimState=='pending' then return {ok=false,error='No reward available.'} end
    m.claimState='pending'
    if not persist(cid) then return {ok=false,error='Reward reservation could not be saved. No reward was granted.'} end
    local ok,given=pcall(function() return exports.bs_inventory:GiveItem(src,m.rewardItem or RelayMissions.rewardItem,m.rewardAmount or RelayMissions.rewardAmount) end)
    if not ok then return {ok=false,error='Reward delivery is uncertain. Ask an administrator to review this claim.'} end
    if not given then m.claimState=nil;persist(cid);return {ok=false,error='Make room for the reward.'} end
    m.claimState=nil;m.claimed=true
    cooldown[cid..':'..id]=os.time()+RelayMissions.offerLifetime
    persist(cid)
    return {ok=true}
end)
local function register() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end
AddEventHandler('onResourceStart',function(name) if name==GetCurrentResourceName() or name=='bs_inventory' then register() end end)
CreateThread(function()
    while true do
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id);local cid=character(src)
            for mission,m in pairs(cid and progress[cid] or {}) do
                if m.started then
                    local n=node(m.target)
                    if m.bucket~=GetPlayerRoutingBucket(src) or not nearby(src,n) or not applicable(m.kind,n) or m.expires<os.time() or GetGameTimer()-(m.lastSeen or 0)>1500 then m.started=nil;TriggerClientEvent('bs:relay:stopped',src,mission,false)
                    elseif GetGameTimer()-m.started>=RelayMissions.actionSeconds*1000 then
                        m.effectState='pending'
                        if persist(cid) then
                            local paid=m.kind~='repair' or exports.bs_inventory:RemoveItem(src,m.repairItem or RelayMissions.repairItem,m.repairAmount or RelayMissions.repairAmount)
                            if not paid then m.effectState=nil;persist(cid)
                            else
                                local ok,applied=pcall(function() return exports.bs_radio:SetAntennaDisruption(m.target,m.kind=='sabotage' and RelayMissions.disruptionSeconds or false) end)
                                if ok and applied then m.complete=true;m.effectState=nil;persist(cid) end
                            end
                        end
                        m.started=nil;TriggerClientEvent('bs:relay:stopped',src,mission,m.complete==true)
                    end
                end
            end
        end
        Wait(250)
    end
end)

CreateThread(function()
    while true do
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id)
            if exports.bs_radio:GetChannel(src) and not notices[src] then
                for _,n in ipairs(nodes()) do
                    if n.enabled and not n.owner then
                        local kind=n.disrupted and 'repair' or 'sabotage'
                        exports.bs_radio:OfferRadioMission(src,{id=kind..':'..n.id,title='Relay contracts available in the Mission Log'})
                        notices[src]=true;break
                    end
                end
            end
        end
        Wait(10000)
    end
end)
local function detach(src)
    notices[src]=nil;syncRate[src]=nil
    local cid=sourceCharacters[src]
    if cid then
        for _,m in pairs(progress[cid] or {}) do m.started=nil;m.lastSeen=nil end
        persist(cid);sourceCharacters[src]=nil;progress[cid]=nil;loaded[cid]=nil
        local prefix=cid..':'
        for key in pairs(cooldown) do if key:sub(1,#prefix)==prefix then cooldown[key]=nil end end
    end
end
AddEventHandler('playerDropped',function() detach(source) end)
AddEventHandler('bs:hook:player:unloaded',function(player) if player and player.source then detach(player.source) end end)
local function sync(src)
    local cid=character(src);if not cid then return end
    TriggerClientEvent('bs:relay:reset',src)
    for id,m in pairs(progress[cid] or {}) do
        m.started=nil;m.lastSeen=nil
        local n=node(m.target)
        if not m.complete and not m.effectState and m.expires>os.time() and n and m.bucket==GetPlayerRoutingBucket(src) then
            TriggerClientEvent('bs:relay:objective',src,{id=id,label=n.label,x=n.x,y=n.y,z=n.z,expires=m.expires,seconds=RelayMissions.actionSeconds})
        end
    end
end
AddEventHandler('bs:hook:player:loaded',function(player) if player and player.source then sync(player.source) end end)
RegisterNetEvent('bs:relay:sync',function()
    local src=source
    if syncRate[src] and GetGameTimer()-syncRate[src]<3000 then return end
    syncRate[src]=GetGameTimer();sync(src)
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for cid in pairs(progress) do persist(cid) end end end)
CreateThread(function() Wait(1000);for _,id in ipairs(GetPlayers()) do sync(tonumber(id)) end end)


local function configExt(src,action,payload)
    if tonumber(src)~=0 and not IsPlayerAceAllowed(tonumber(src) or -1,'bs.admin') then return {ok=false,error='Administrator access required.'} end
    payload=type(payload)=='table' and payload or {}
    local number=tonumber(payload.charId)
    local cid=number and number>0 and number%1==0 and ('%.0f'):format(number) or ''
    if not cid:match('^%d+$') or #cid>20 then return {ok=false,error='A character ID is required.'} end
    restore(cid)
    if action=='review' then
        local entries={}
        for id,m in pairs(progress[cid]) do if m.claimState=='pending' or m.effectState=='pending' then entries[#entries+1]={id=id,title=m.title,reward=m.claimState,effect=m.effectState,complete=m.complete} end end
        return {ok=true,charId=cid,entries=entries}
    end
    local m=progress[cid][tostring(payload.id or '')]
    if not m then return {ok=false,error='Mission not found.'} end
    local before={claimed=m.claimed,claimState=m.claimState,effectState=m.effectState,complete=m.complete}
    if action=='confirmReward' and m.claimState=='pending' then m.claimState=nil;m.claimed=true;cooldown[cid..':'..payload.id]=os.time()+RelayMissions.offerLifetime
    elseif action=='retryReward' and m.claimState=='pending' then m.claimState=nil
    elseif action=='confirmObjective' and m.effectState=='pending' then m.effectState=nil;m.complete=true
    elseif action=='retryObjective' and m.effectState=='pending' then m.effectState=nil
    else return {ok=false,error='No matching pending operation.'} end
    if not persist(cid) then
        m.claimed=before.claimed;m.claimState=before.claimState;m.effectState=before.effectState;m.complete=before.complete
        return {ok=false,error='Resolution could not be saved.'}
    end
    print(('[bs_missions] administrator %s resolved %s for character %s using %s'):format(src,tostring(payload.id),cid,action))
    return {ok=true}
end

exports('ConfigExt',function(src,action,payload)
    local result=configExt(src,action,payload)
    local number=type(payload)=='table' and tonumber(payload.charId) or nil
    local cid=number and number>0 and number%1==0 and ('%.0f'):format(number) or ''
    local online=false
    for _,active in pairs(sourceCharacters) do if active==cid then online=true end end
    if not online and loaded[cid] then
        progress[cid]=nil;loaded[cid]=nil
        local prefix=cid..':'
        for key in pairs(cooldown) do if key:sub(1,#prefix)==prefix then cooldown[key]=nil end end
    end
    return result
end)
