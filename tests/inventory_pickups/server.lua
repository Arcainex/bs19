-- Run with Lua 5.4: lua tests/inventory_pickups/server.lua <repository root>
-- Executes the real grid, inventory mutations and receipt module; SQL is an in-memory fake.
local root=arg[1] or '.'
local base=root..'/resources/[beyond]/bs_inventory/'
local assertions=0
local function check(v,label)assertions=assertions+1;assert(v,label)end
local function world(enabled)
    local e=setmetatable({},{__index=_G})
    local function load(p)assert(loadfile(base..p,'t',e))()end
    load('config/config_inventory.lua')
    e.Inventory.PickupVisuals.enabled=enabled~=false
    local players={ [1]={source=1,charId=101,class={stats={carryWeight=10000}},metadata={}},[2]={source=2,charId=202,class={stats={carryWeight=10000}},metadata={}} }
    local callbacks,events,api,messages,sql={},{},{},{},{}
    local id=0
    e.Items={Get=function(item)return ({water={label='Water',weight=1,stack=10,w=1,h=1,category='drink'},
        scrap={label='Scrap',weight=1,stack=100,w=1,h=1,category='material'},
        single={label='Single',weight=1,stack=1,w=1,h=1,category='misc'}})[item]end}
    e.ItemLabel=function(item)return (e.Items.Get(item)or{}).label or item end
    local function db(method,query,args)
        sql[#sql+1]={method=method,query=query}
        if method=='single_async' then return nil end
        if method=='query_async' then return{}end
        if method=='insert_async' then id=id+1;return id end
        return 1
    end
    e.exports=setmetatable({bs_core={GetPlayer=function(_,src)return players[tonumber(src)]end,RegisterModule=function()end},
        oxmysql=setmetatable({},{__index=function(_,method)return function(_,query,args)return db(method,query,args)end end})},
        {__call=function(_,name,fn)api[name]=fn end})
    e.BSB={RegisterCallback=function(name,fn)callbacks[name]=fn end}
    e.Hotbar={};e.json={encode=function()return'{}'end,decode=function()return{}end}
    e.GetGameTimer=function()return 10000 end;e.GetCurrentResourceName=function()return'bs_inventory'end
    e.GetResourceState=function()return'missing'end
    e.GetPlayerPed=function(src)return src end;e.GetPlayerName=function(src)return tostring(src)end
    e.GetHashKey=function()return 1 end;e.GetConvarInt=function(_,default)return default end
    local vector={__sub=function(a,b)return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},getmetatable(a))end,__len=function(v)return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)end}
    e.vector3=function(x,y,z)return setmetatable({x=x,y=y,z=z},vector)end
    e.GetEntityCoords=function()return e.vector3(0,0,0)end
    e.AddEventHandler=function(name,fn)events[name]=events[name]or{};table.insert(events[name],fn)end
    e.RegisterNetEvent=e.AddEventHandler;e.CreateThread=function()end;e.Wait=function()error('unexpected wait')end
    e.TriggerClientEvent=function(name,src,payload)messages[#messages+1]={name=name,source=src,payload=payload}end
    e.TriggerEvent=function()end;e.Lp=function(_,key)return key end;e.L=function(key)return key end
    e.print=function()end
    load('server/sv_grid.lua');load('server/sv_main.lua');load('server/sv_pickups.lua')
    local function last(src)
        for i=#messages,1,-1 do if messages[i].name=='bs:inventory:state' and messages[i].source==src then return messages[i].payload end end
    end
    return{env=e,players=players,callbacks=callbacks,api=api,sql=sql,last=last,messages=messages,events=events,
        give=function(src,item,n,quiet)return e.Inv.Give(src,item,n,nil,quiet)end}
end
local w=world();check(w.give(1,'water',1),'give succeeds')
local packet=w.last(1).pickups
check(packet.character==101 and packet.changes[1].item=='water' and packet.changes[1].amount==1,'confirmed x1 receipt')
check(w.last(2)==nil,'correct player only')
w.give(1,'water',4);check(w.last(1).pickups.changes[1].amount==4,'receipt is amount received, not new total')
check(w.env.Inv.Count(1,'water')==5,'inventory result unchanged')
w.give(2,'scrap',7);check(w.last(2).pickups.character==202,'second character')
check(not w.give(1,'unknown',2) and not w.last(1).pickups,'unknown item has no success visual')
w.give(1,'water',1,true);check(w.last(1).pickups==nil,'internal refund/starter grant is silent')
w.api.GiveItem(1,'water',1,nil,{pickup=false});check(w.last(1).pickups==nil,'optional backward-compatible silent grant')
w.env.Inv.Push(1);check(w.last(1).pickups==nil,'refresh is not a receipt')
w.env.Inv.Remove(1,'water',1);check(w.last(1).pickups==nil,'removed visuals disabled by default')
w.env.Inventory.PickupVisuals.showRemoved=true;w.env.Inv.Remove(1,'water',1)
check(w.last(1).pickups.changes[1].kind=='removed','opt-in removal')
w=world(false);w.give(1,'water',3);check(w.last(1).pickups==nil and w.env.Inv.Count(1,'water')==3,'disabled preserves mechanics')
local writesDisabled=#w.sql
w=world(true);w.give(1,'water',3);check(#w.sql==writesDisabled,'presentation adds no database queries')

-- A full grid, including legacy Give's partial failure, must never announce a requested success.
w=world();for _=1,70 do check(w.give(1,'single',1),'fill actual grid')end
check(not w.give(1,'water',1) and w.last(1).pickups==nil,'full grid has no false receipt')
w=world();w.give(1,'water',9);for _=1,69 do w.give(1,'single',1)end
check(not w.give(1,'water',2),'legacy partial Give still reports failure')
check(w.last(1).pickups==nil,'failed partial Give does not claim x2 success')
check(w.env.Inv.Count(1,'water')==10,'legacy partial inventory behavior not changed')
check(not w.api.GiveAll(1,'water',2) and not w.last(1).pickups,'atomic GiveAll rollback has no success receipt')
check(w.env.Inv.Count(1,'water')==10,'GiveAll rollback preserves baseline count')
w=world();w.give(1,'water',3)
check(w.callbacks['inventory:give'](1,1,1,2).ok,'player transfer succeeds')
check(not w.last(2).pickups and not w.last(1).pickups,'player handover is not loot for either player')

-- Server-validated container path, not client snapshot arithmetic.
w=world();w.api.RegisterContainer('loot',{width=4,height=4,maxWeight=100},1)
w.api.ContainerGive('loot','water',8)
check(w.callbacks['inventory:openContainer'](1,'loot').ok,'granted container opens')
local moved=w.callbacks['inventory:move'](1,{inv='container',slot=1},{inv='player',slot=1,x=1,y=1},3)
check(moved.ok,'container move accepted')
check(w.last(1).pickups.changes[1].amount==3,'loot receipt only for committed quantity')
local split=w.callbacks['inventory:move'](1,{inv='player',slot=1},{inv='player',slot=2,x=2,y=1},1)
check(split.ok and not w.last(1).pickups,'internal split is silent')
local refused=w.callbacks['inventory:move'](1,{inv='container',slot=99},{inv='player',slot=3,x=3,y=1},1)
check(not refused.ok,'invalid move still rejected')
w=world();w.give(1,'water',9)
local barSlot=w.last(1).player.gridSlots+1
local bar=w.callbacks['inventory:move'](1,{inv='player',slot=1},{inv='player',slot=barSlot},9)
check(bar.ok,'prepare existing bar stack: '..tostring(bar.error))
w.api.RegisterContainer('loot',{width=4,height=4,maxWeight=100},1);w.api.ContainerGive('loot','scrap',1);w.api.ContainerGive('loot','water',8)
check(w.callbacks['inventory:openContainer'](1,'loot').ok,'merge container opens')
local merged=w.callbacks['inventory:move'](1,{inv='container',slot=2},{inv='player',slot=barSlot},8)
check(merged.ok,'bounded stack merge: '..tostring(merged.error))
check(w.last(1).pickups.changes[1].amount==1,'merge reports real moved amount, not requested eight')

-- Character switch during a yielding operation cannot attach a receipt to the replacement character.
w=world();w.env.Inv.Pickups.Record(1,'water',2,'received',101)
w.players[1].charId=303;local p={};w.env.Inv.Pickups.Flush(1,p)
check(p.pickups==nil,'pending old character discarded')
w.env.Inv.Pickups.Record(1,'water',2,'received',101);p={};w.env.Inv.Pickups.Flush(1,p)
check(p.pickups==nil,'old operation owner rejected before recording')
print(('PASS: %d authoritative inventory/receipt assertions'):format(assertions))
