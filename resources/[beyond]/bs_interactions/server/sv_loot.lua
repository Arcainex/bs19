local function copy(value)
    if type(value)~='table'then return value end
    local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
local rules=copy(Scavenge)
local function admin(src) return IsPlayerAceAllowed(src,'bs.admin') or IsPlayerAceAllowed(src,'bs.superadmin') end
local function validNumber(n,lo,hi) return type(n)=='number' and n==n and n>=lo and n<=hi end
local function ident(s) return type(s)=='string' and #s>0 and #s<=64 and s:match('^[%w_%-]+$') end
local function tableExists(id)if not ident(id)then return false end;local ok,value=pcall(function()return exports.bs_economy:GetLootTable(id)end);return ok and value~=nil end
local function validate(value)
    if type(value)~='table' or type(value.categories)~='table' or type(value.modelRules)~='table' or type(value.locations)~='table' or type(value.ground)~='table' then return false,'Missing rule sections' end
    local n=0
    for category,id in pairs(value.categories) do n=n+1;if n>32 or not ident(category) or not tableExists(id) then return false,'Unknown category loot table' end end
    n=0
    for model,category in pairs(value.modelRules) do n=n+1;if n>512 or not ident(model) or not value.categories[category] then return false,'Invalid model rule' end end
    if #value.locations>512 then return false,'Too many furniture zones' end
    for _,p in ipairs(value.locations) do
        if type(p)~='table' or not ident(p.id) or not validNumber(p.x,-20000,20000) or not validNumber(p.y,-20000,20000) or not validNumber(p.z,-500,2500) or not validNumber(p.radius,0.25,100) or not value.categories[p.category] then return false,'Invalid furniture zone' end
    end
    local g=value.ground
    if g.density~=nil and not validNumber(g.density,.25,2)then return false,'Invalid density'end
    if g.coverage~=nil and g.coverage~='curated'and g.coverage~='expanded'then return false,'Invalid coverage'end
    if type(g.enabled)~='boolean' or not validNumber(g.maxVisible,1,48) or g.maxVisible%1~=0 or not validNumber(g.streamDistance,15,100) or not validNumber(g.respawn,60,86400) or type(g.points)~='table' or type(g.zones)~='table' or #g.points>512 or #g.zones>32 then return false,'Invalid ground loot limits' end
    local ids={}
    for _,p in ipairs(g.points) do
        if type(p)~='table' or not ident(p.id) or ids[p.id] or not validNumber(p.x,-20000,20000) or not validNumber(p.y,-20000,20000) or not validNumber(p.z,-500,2500) or not value.categories[p.category] then return false,'Invalid ground loot point' end
        ids[p.id]=true
    end
    for _,p in ipairs(g.zones) do
        if type(p)~='table' or not ident(p.id) or ids[p.id] or not validNumber(p.x,-20000,20000) or not validNumber(p.y,-20000,20000) or not validNumber(p.z,-500,2500) or not validNumber(p.radius,2,100) or not validNumber(p.count,1,16) or p.count%1~=0 or not value.categories[p.category] or p.coverage~=nil and p.coverage~='curated'and p.coverage~='expanded'or p.enabled~=nil and type(p.enabled)~='boolean' then return false,'Invalid procedural zone' end
        ids[p.id]=true
    end
    return true
end
local raw=LoadResourceFile(GetCurrentResourceName(),'data/loot_rules.json')
if raw then local ok,v=pcall(json.decode,raw);if ok then local good=validate(v);if good then rules=v end end end
local function publish() TriggerClientEvent('bs:scavenge:rules',-1,rules) end
function Containers.ResolveLoot(def,key,model)
    local tableId=rules.categories[rules.modelRules[tostring(model or '')]]
    local x,y,z=key:match('^(%-?[%d%.]+):(%-?[%d%.]+):(%-?[%d%.]+)$');x,y,z=tonumber(x),tonumber(y),tonumber(z)
    local best
    if x then for _,p in ipairs(rules.locations) do local dx,dy,dz=x-p.x,y-p.y,z-p.z;if dx*dx+dy*dy+dz*dz<=p.radius*p.radius and (not best or p.radius<best.radius) then best=p end end end
    if best and def==Containers.Types.furniture then tableId=rules.categories[best.category] end
    if def==Containers.Types.furniture then
        if not best or (x-best.x)^2+(y-best.y)^2+(z-best.z)^2>0.12 then return nil end
    end
    if not tableId then return def end
    local copy={};for k,v in pairs(def) do copy[k]=v end;copy.lootTable=tableId;return copy
end
local depleted,busy,groundTickets,lastPoll={},{},{},{}
local saved=LoadResourceFile(GetCurrentResourceName(),'data/ground_depleted.json')
if saved then local ok,v=pcall(json.decode,saved);if ok and type(v)=='table' then for id,until_ in pairs(v) do if type(id)=='string' and validNumber(until_,os.time(),os.time()+86400) then depleted[id]=until_ end end end end
local function points()
    local out={}
    for _,p in ipairs(rules.ground.points) do if p.enabled~=false then out[#out+1]=p end end
    for _,zone in ipairs(rules.ground.zones) do
        if zone.enabled~=false and (zone.coverage~='expanded'or rules.ground.coverage=='expanded')then
        local density=math.max(.25,math.min(2,tonumber(rules.ground.density)or 1))
        local count=math.max(1,math.min(16,math.floor(zone.count*density+.5)))
        for i=1,count do
            local angle=i*2.3999632297287
            local radius=zone.radius*math.sqrt(i/(count+1))
            out[#out+1]={id=zone.id..'_'..i,x=zone.x+math.cos(angle)*radius,y=zone.y+math.sin(angle)*radius,z=zone.z,category=zone.category,procedural=true}
        end
        end
    end
    return out
end
BSB.RegisterCallback('scavenge:rules',function() return {ok=true,rules=rules} end)
BSB.RegisterCallback('scavenge:ground',function(src)
    local now=GetGameTimer()
    if now-(lastPoll[src] or -5000)<2000 then return {ok=true,unchanged=true} end
    lastPoll[src]=now
    if not rules.ground.enabled or GetPlayerRoutingBucket(src)~=0 then return {ok=true,points={}} end
    local ped=GetPlayerPed(src);if ped==0 then return {ok=false} end
    local at=GetEntityCoords(ped);local out={}
    for _,p in ipairs(points()) do
        if not depleted[p.id] or depleted[p.id]<=os.time() then
            local dx,dy,dz=at.x-p.x,at.y-p.y,at.z-p.z
            if dx*dx+dy*dy+dz*dz<rules.ground.streamDistance^2 then out[#out+1]=p end
        end
    end
    table.sort(out,function(a,b) return (a.x-at.x)^2+(a.y-at.y)^2 < (b.x-at.x)^2+(b.y-at.y)^2 end)
    while #out>rules.ground.maxVisible do out[#out]=nil end
    local visible={}
    for _,point in ipairs(out)do local packed=GroundStock.Present(point,rules.categories[point.category]);if packed then visible[#visible+1]=packed end end
    return {ok=true,points=visible}
end)
BSB.RegisterCallback('scavenge:vicinity',function(src)
    if not rules.ground.enabled or GetPlayerRoutingBucket(src)~=0 or not exports.bs_core:GetPlayer(src) then return {ok=true,items={}} end
    local ped=GetPlayerPed(src);if ped==0 then return {ok=false,items={}} end
    local at=GetEntityCoords(ped);local out={}
    for _,point in ipairs(points()) do
        local distance=math.sqrt((at.x-point.x)^2+(at.y-point.y)^2+(at.z-point.z)^2)
        if distance<=10 and (depleted[point.id] or 0)<=os.time() then
            local stock=GroundStock.Get(point,rules.categories[point.category])
            if stock then
                local def=exports.bs_inventory:GetItem(stock.item) or {}
                out[#out+1]={id=point.id,kind='ground',item=stock.item,label=stock.label,amount=stock.amount,category=def.category,distance=distance}
            end
        end
    end
    table.sort(out,function(a,b)return a.distance<b.distance end)
    while #out>48 do out[#out]=nil end
    return {ok=true,items=out}
end)
BSB.RegisterCallback('scavenge:begin',function(src,id,vicinity)
    local reach=vicinity==true and 10 or 3
    if not rules.ground.enabled or GetPlayerRoutingBucket(src)~=0 or type(id)~='string' then return {ok=false} end
    local ped=GetPlayerPed(src);if ped==0 or GetEntityHealth(ped)<=0 then return {ok=false} end
    local at=GetEntityCoords(ped)
    for _,p in ipairs(points()) do
        if p.id==id and (depleted[id] or 0)<=os.time() and (at.x-p.x)^2+(at.y-p.y)^2+(at.z-p.z)^2<=reach*reach then
            local value=GroundStock.Get(p,rules.categories[p.category]);if not value then return {ok=false}end
            groundTickets[src]={id=id,reach=reach,token=value.token,ready=GetGameTimer()+1100,expires=GetGameTimer()+10000}
            return {ok=true}
        end
    end
    return {ok=false}
end)
BSB.RegisterCallback('scavenge:take',function(src,id)
    local ticket=groundTickets[src];groundTickets[src]=nil
    if not ticket or ticket.id~=id or GetGameTimer()<ticket.ready or GetGameTimer()>ticket.expires then return {ok=false,error='Search interrupted'} end
    if not rules.ground.enabled or GetPlayerRoutingBucket(src)~=0 or busy[id] then return {ok=false} end
    local ped=GetPlayerPed(src);if ped==0 or GetEntityHealth(ped)<=0 or not exports.bs_core:GetPlayer(src) then return {ok=false} end
    local point
    for _,p in ipairs(points()) do if p.id==id then point=p;break end end
    if not point or (depleted[id] or 0)>os.time() then return {ok=false,error='Already scavenged'} end
    local at=GetEntityCoords(ped)
    if (at.x-point.x)^2+(at.y-point.y)^2+(at.z-point.z)^2>(ticket.reach or 3)^2 then return {ok=false,error='Too far away'} end
    local value=GroundStock.Get(point,rules.categories[point.category])
    if not value or value.token~=ticket.token then return {ok=false,error='Search again'}end
    busy[id]=true
    local items={{item=value.item,amount=value.amount}}
    depleted[id]=os.time()+rules.ground.respawn
    if not SaveResourceFile(GetCurrentResourceName(),'data/ground_depleted.json',json.encode(depleted),-1) then
        depleted[id]=nil;busy[id]=nil;return {ok=false,error='Supplies unavailable; try again later'}
    end
    local given={}
    for _,item in ipairs(items) do local ok=exports.bs_inventory:GiveAll(src,item.item,item.amount);if ok then given[#given+1]=item end end
    if #items>0 and #given==0 then depleted[id]=nil;SaveResourceFile(GetCurrentResourceName(),'data/ground_depleted.json',json.encode(depleted),-1);busy[id]=nil;return {ok=false,error='No room in your inventory'} end
    depleted[id]=os.time()+rules.ground.respawn
    SaveResourceFile(GetCurrentResourceName(),'data/ground_depleted.json',json.encode(depleted),-1)
    busy[id]=nil;GroundStock.Remove(id);TriggerClientEvent('bs:scavenge:removed',-1,id)
    if #given>0 then exports.bs_core:AwardAction(src,'resource_gathered') end
    return {ok=true,items=given}
end)
AddEventHandler('playerDropped',function() groundTickets[source]=nil;lastPoll[source]=nil end)
exports('ConfigExt',function(src,action,payload)
    if not admin(src) then return {ok=false,error='Not allowed'} end
    if action=='get' then return {ok=true,rules=rules,tables=exports.bs_economy:LootCatalogue()} end
    if action=='save' then
        local ok,why=validate(payload);if not ok then return {ok=false,error=why} end
        if not SaveResourceFile(GetCurrentResourceName(),'data/loot_rules.json',json.encode(payload),-1) then return {ok=false,error='Unable to save loot rules'} end
        rules=copy(payload);GroundStock.Clear();groundTickets={};publish();return {ok=true,rules=rules}
    end
    return {ok=false,error='Unknown action'}
end)

AddEventHandler('bs_config:changed:'..GetCurrentResourceName(),function()
    local candidate=copy(rules)
    for _,key in ipairs({'enabled','coverage','density','maxVisible','streamDistance','respawn','points','zones'})do
        local value=BSConfigGet('Scavenge.ground.'..key,nil)
        if value~=nil then candidate.ground[key]=copy(value)end
    end
    local ok,why=validate(candidate)
    if ok then rules=candidate;GroundStock.Clear();groundTickets={};publish()
    else print('[bs_interactions] Ignoring invalid live loot rules: '..tostring(why))end
end)
