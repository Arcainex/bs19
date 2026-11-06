local sessions, channels, nodes, limits = {}, {}, {}, {}
local function save() SetResourceKvp('walkie_network',json.encode({channels=channels,nodes=nodes})) end
local stored=GetResourceKvpString('walkie_network')
if stored then local ok,data=pcall(json.decode,stored);if ok and type(data)=='table' then channels=data.channels or {};nodes=data.nodes or {} end end
if #nodes==0 then nodes=Walkie.antennas end
local function admin(src) return src==0 or IsPlayerAceAllowed(src,'bs.admin') end
local function faction(src)
    local ok,id=pcall(function() return exports.bs_factions:GetFaction(src) end)
    return ok and id or nil
end
local function tier(src)
    local ok,ownership=pcall(function() return exports.bs_inventory:RadioOwnership(src) end)
    if not ok or not ownership then return nil end
    if ownership.equipped then
        for i,entry in ipairs(Walkie.tiers) do if entry.item==ownership.equipped then return i end end
    end

end

local function allowed(src,channel)
    local lock=channels[tostring(channel)]
    return not lock or faction(src)==lock.faction
end
local function notify(src,message) TriggerClientEvent('bs:walkie:notice',src,message) end
local function state(src)
    local s=sessions[src]or {}
    local battery=WalkieBattery.snapshot(src)
    TriggerClientEvent('bs:walkie:state',src,{channel=s.channel,tier=tier(src),transmitting=s.tx or false,battery=battery.battery,charging=battery.charging,source=battery.source})
end
local function join(src,channel)
    channel=tonumber(channel)
    if channel==0 then sessions[src]=nil;state(src);return true end
    if not channel or channel%1~=0 or channel<1 or channel>9999 then return false end
    local owned=tier(src)
    if not owned then notify(src,'Equip a radio in its equipment slot first.');return false end
    if not WalkieBattery.powered(src)then notify(src,'The radio battery is empty.');return false end
    if not allowed(src,channel) then notify(src,'That frequency belongs to another faction.');return false end
    sessions[src]={channel=channel,tx=false,tier=owned};state(src);return true
end
RegisterNetEvent('bs:walkie:join',function(channel)
    local src=source
    if limits[src] and GetGameTimer()-limits[src]<400 then return end
    limits[src]=GetGameTimer();join(src,channel)
end)
RegisterNetEvent('bs:walkie:transmit',function(on)
    local src=source;local s=sessions[src]
    if not s then return end
    s.tx=on==true and GetEntityHealth(GetPlayerPed(src))>100 and tier(src)~=nil and WalkieBattery.powered(src)and not Player(src).state.bsDowned and not Player(src).state.bsDead and allowed(src,s.channel)
    s.pulse=GetGameTimer();state(src)
end)
RegisterNetEvent('bs:walkie:factionChannel',function(channel)
    local src=source;local fid=faction(src)
    if not fid then return end
    local ok,permitted=pcall(function() return exports.bs_factions:RankAllowed(src,'squad_manage') end)
    if not ok or permitted~=true then notify(src,'Faction management permission required.');return end
    channel=tonumber(channel)
    if not channel or channel%1~=0 or channel<1 or channel>9999 then return end
    if channels[tostring(channel)] and channels[tostring(channel)].faction~=fid then return end
    for key,lock in pairs(channels) do if lock.faction==fid then channels[key]=nil end end
    channels[tostring(channel)]={faction=fid};save();notify(src,'Faction frequency secured.')
end)
local function nearby(src,node,distance)
    local ped=GetPlayerPed(src)
    if ped==0 or (node.bucket and node.bucket~=GetPlayerRoutingBucket(src)) then return false end
    return WalkieGraph.distance(GetEntityCoords(ped),node)<=distance
end
local function character(src)
    local ok,p=pcall(function() return exports.bs_core:GetPlayer(src) end)
    return ok and p and p.charId or nil
end
local function deploy(src,slot)
    if GetPlayerPed(src)==0 or not character(src) then return false end
    local owned=0
    for _,n in ipairs(nodes) do if n.owner==character(src) then owned=owned+1 end end
    if owned>=2 then return false end
    local selected
    for _,entry in ipairs(exports.bs_inventory:ItemMetaList(src,'portable_antenna')) do if not slot or tonumber(slot)==entry.slot then selected=entry;break end end
    if not selected then return false end
    local remaining=math.min(Walkie.portableLife,math.max(0,tonumber(selected.metadata.batterySeconds) or Walkie.portableLife))
    if remaining<1 then notify(src,'The relay battery is empty.');return false end
    local ok,removed=pcall(function() return exports.bs_inventory:RemoveSlot(src,selected.slot,'portable_antenna') end)
    if not ok or not removed then return false end
    local p=GetEntityCoords(GetPlayerPed(src))
    nodes[#nodes+1]={id='portable_'..src..'_'..os.time(),label='Portable relay',x=p.x,y=p.y,z=p.z,range=Walkie.portableRange,linkRange=Walkie.portableRange,enabled=true,owner=character(src),bucket=GetPlayerRoutingBucket(src),expires=os.time()+remaining}
    save();return true
end
AddEventHandler('bs:walkie:deploy',function(src,_,slot) deploy(tonumber(src),slot) end)
RegisterNetEvent('bs:walkie:recover',function(id)
    local src=source
    for i,n in ipairs(nodes) do
        if n.id==id and n.owner==character(src) and nearby(src,n,3.0) then
            local ok,given=pcall(function() return exports.bs_inventory:GiveItem(src,'portable_antenna',1,{batterySeconds=math.max(0,(n.expires or os.time())-os.time())}) end)
            if ok and given then table.remove(nodes,i);save() end
            return
        end
    end
end)
local function settings() return {voiceRanges=GetResourceState('bs_voice')=='started' and exports.bs_voice:GetRanges() or {3,15,35},directRange=Walkie.directRange,portableLife=Walkie.portableLife,portableRange=Walkie.portableRange,tiers=Walkie.tiers,antennas=nodes,channels=channels} end
exports('GetRadioSettings',settings)
exports('UpdateAntenna',function(src,id,patch)
    if not admin(src) or type(patch)~='table' then return false end
    for _,n in ipairs(nodes) do if n.id==id then
        for _,key in ipairs({'x','y','z','range','linkRange'}) do
            if patch[key]~=nil then local v=tonumber(patch[key]);if not v or v~=v or math.abs(v)>20000 or ((key=='range' or key=='linkRange') and v<1) then return false end end
        end
        for _,key in ipairs({'x','y','z','range','linkRange'}) do if patch[key]~=nil then n[key]=tonumber(patch[key]) end end
        if type(patch.enabled)=='boolean' then n.enabled=patch.enabled end
        if type(patch.label)=='string' then n.label=patch.label:sub(1,60) end
        save();return true
    end end
    return false
end)
exports('UpdateRadioSettings',function(src,patch)
    if not admin(src) or type(patch)~='table' then return false end
    if patch.tiers~=nil then
        if type(patch.tiers)~='table' or #patch.tiers~=3 then return false end
        for i,t in ipairs(patch.tiers) do if type(t)~='table' or type(t.hops)~='number' or t.hops%1~=0 or t.hops<0 or t.hops>999 then return false end end
        for i,t in ipairs(patch.tiers) do Walkie.tiers[i].hops=t.hops end
        SetResourceKvp('walkie_tiers',json.encode(patch.tiers))
    end
    for _,key in ipairs({'directRange','portableLife','portableRange'}) do
        local value=patch[key]
        if value~=nil and (type(value)~='number' or value<1 or value>86400) then return false end
    end
    for _,key in ipairs({'directRange','portableLife','portableRange'}) do if patch[key] then Walkie[key]=patch[key] end end
    SetResourceKvp('walkie_settings',json.encode({directRange=Walkie.directRange,portableLife=Walkie.portableLife,portableRange=Walkie.portableRange}))
    return true
end)
local savedSettings=GetResourceKvpString('walkie_settings')
if savedSettings then local ok,p=pcall(json.decode,savedSettings);if ok and type(p)=='table' then for _,key in ipairs({'directRange','portableLife','portableRange'}) do if type(p[key])=='number' and p[key]>=1 and p[key]<=86400 then Walkie[key]=p[key] end end end end
exports('SetAntennaDisruption',function(id,seconds)
    if GetInvokingResource()~='bs_missions' then return false end
    for _,n in ipairs(nodes) do if n.id==id then n.disrupted=seconds and os.time()+math.min(3600,math.max(1,tonumber(seconds) or 1)) or nil;save();return true end end
    return false
end)
exports('OfferRadioMission',function(src,offer)
    if not tier(src) or type(offer)~='table' then return false end
    TriggerClientEvent('bs:walkie:offer',src,{id=offer.id,title=tostring(offer.title or 'Radio contract'):sub(1,100)})
    return true
end)
RegisterNetEvent('bs:walkie:debug',function()
    if admin(source) then TriggerClientEvent('bs:walkie:debugNodes',source,nodes) end
end)
AddEventHandler('playerDropped',function() sessions[source],limits[source]=nil,nil end)
CreateThread(function()
    while true do
        for i=#nodes,1,-1 do
            local n=nodes[i]
            if n.expires and n.expires<=os.time() then table.remove(nodes,i)
            elseif n.disrupted and n.disrupted<=os.time() then n.disrupted=nil end
        end
        for src,s in pairs(sessions) do
            s.tier=tier(src)
            if not s.tier or not WalkieBattery.powered(src)or not allowed(src,s.channel) then sessions[src]=nil;state(src) end
        end
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id);local s=sessions[src];local recipients={}
            if s and s.tx and s.pulse and GetGameTimer()-s.pulse<1500 and GetPlayerPed(src)~=0 then
                local bucket=GetPlayerRoutingBucket(src)
                for other,r in pairs(sessions) do
                    if other~=src and r.channel==s.channel and GetPlayerRoutingBucket(other)==bucket and GetPlayerPed(other)~=0 and WalkieGraph.connected(GetEntityCoords(GetPlayerPed(src)),GetEntityCoords(GetPlayerPed(other)),nodes,math.min(Walkie.tiers[s.tier].hops,Walkie.tiers[r.tier].hops),bucket) then recipients[other]=math.min(s.tier,r.tier) end
                end
            end
            if GetResourceState('bs_voice')=='started' then exports.bs_voice:SetRadioRecipients(src,recipients) end
        end
        Wait(250)
    end
end)

AddEventHandler('bs:walkie:open',function(src)
    if tier(tonumber(src)) then TriggerClientEvent('bs:walkie:open',tonumber(src)) end
end)
exports('CreateAntenna',function(src,node)
    if not admin(src) or type(node)~='table' or type(node.id)~='string' or not node.id:match('^[%w_-]+$') or #node.id>48 then return false end
    for _,n in ipairs(nodes) do if n.id==node.id then return false end end
    for _,key in ipairs({'x','y','z','range','linkRange'}) do if type(node[key])~='number' or node[key]~=node[key] or math.abs(node[key])>20000 then return false end end
    if node.range<1 or node.linkRange<1 then return false end
    nodes[#nodes+1]={id=node.id,label=tostring(node.label or node.id):sub(1,60),x=node.x,y=node.y,z=node.z,range=node.range,linkRange=node.linkRange,enabled=node.enabled~=false}
    save();return true
end)
exports('DeleteAntenna',function(src,id)
    if not admin(src) then return false end
    for i,n in ipairs(nodes) do if n.id==id and not n.owner then table.remove(nodes,i);save();return true end end
    return false
end)
exports('SetFactionChannel',function(src,fid,channel)
    if not admin(src) or type(fid)~='string' then return false end
    channel=tonumber(channel)
    if not channel or channel%1~=0 or channel<1 or channel>9999 then return false end
    if channels[tostring(channel)] and channels[tostring(channel)].faction~=fid then return false end
    for key,lock in pairs(channels) do if lock.faction==fid then channels[key]=nil end end
    channels[tostring(channel)]={faction=fid};save();return true
end)
CreateThread(function()
    while true do
        local portable={}
        for _,n in ipairs(nodes) do if n.owner then portable[#portable+1]={id=n.id,x=n.x,y=n.y,z=n.z,bucket=n.bucket,expires=n.expires} end end
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id);local visible={}
            for _,n in ipairs(portable) do if n.bucket==GetPlayerRoutingBucket(src) then visible[#visible+1]=n end end
            TriggerClientEvent('bs:walkie:portable',src,visible)
        end
        Wait(2000)
    end
end)

local savedTiers=GetResourceKvpString('walkie_tiers')
if savedTiers then local ok,t=pcall(json.decode,savedTiers);if ok and type(t)=='table' then for i=1,3 do if t[i] and type(t[i].hops)=='number' and t[i].hops%1==0 and t[i].hops>=0 and t[i].hops<=999 then Walkie.tiers[i].hops=t[i].hops end end end end

exports('GetChannel',function(src) local s=sessions[tonumber(src)];return s and s.channel end)

exports('ConfigExt',function(src,action,payload)
    src=tonumber(src)
    if not src or not admin(src) then return {ok=false,error='Administrator access required.'} end
    payload=type(payload)=='table' and payload or {}
    if action=='get' then return {ok=true,data=settings()} end
    local ok=false
    if action=='settings' then ok=exports.bs_radio:UpdateRadioSettings(src,payload)
    elseif action=='antenna.update' then ok=exports.bs_radio:UpdateAntenna(src,payload.id,payload)
    elseif action=='antenna.create' then ok=exports.bs_radio:CreateAntenna(src,payload)
    elseif action=='antenna.delete' then ok=exports.bs_radio:DeleteAntenna(src,payload.id)
    elseif action=='faction.channel' then ok=exports.bs_radio:SetFactionChannel(src,payload.faction,payload.channel)
    elseif action=='debug' then TriggerClientEvent('bs:walkie:debugNodes',src,nodes);ok=true
    elseif action=='voice.ranges' then
        if GetResourceState('bs_voice')=='started' and type(payload.ranges)=='table' then ok=exports.bs_voice:SetRanges(payload.ranges) end
    end
    return {ok=ok==true,data=ok and settings() or nil,error=not ok and 'Invalid radio configuration.' or nil}
end)

local openRequests={}
RegisterNetEvent('bs:walkie:requestOpen',function()
    local src=source;local now=GetGameTimer()
    if openRequests[src] and now-openRequests[src]<400 then return end
    openRequests[src]=now
    if not tier(src)then notify(src,'Equip a radio in its equipment slot first.');return end
    state(src)
    TriggerClientEvent('bs:walkie:openGranted',src)
end)
AddEventHandler('playerDropped',function() openRequests[source]=nil end)

AddEventHandler('bs:radio:equipmentChanged',function(src)
    src=tonumber(src)
    if not tier(src)or not WalkieBattery.powered(src)then sessions[src]=nil;exports.bs_voice:SetRadioRecipients(src,{})end
    state(src)
end)

AddEventHandler('bs:hook:player:unloaded',function(p)
    if p then sessions[p.source]=nil;TriggerClientEvent('bs:walkie:state',p.source,{battery=0,charging=false,transmitting=false});exports.bs_voice:SetRadioRecipients(p.source,{})end
end)
CreateThread(function()
    while true do
        Wait(30000)
        for _,id in ipairs(GetPlayers())do
            local src=tonumber(id);local session=sessions[src]
            WalkieBattery.tick(src,30,session~=nil,session and session.tx==true)
        end
    end
end)
