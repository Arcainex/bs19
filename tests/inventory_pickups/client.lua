local root=arg[1]or'.';local n=0
local function check(v,label)n=n+1;assert(v,label)end
local function world()
 local e=setmetatable({},{__index=_G});assert(loadfile(root..'/resources/[beyond]/bs_inventory/config/config_inventory.lua','t',e))()
 local events,callbacks,messages={}, {}, {};local progress={active=false,bottom='237.6px'}
 local data={charId=101};local session='playing';local states={}
 e.source=65535;e.GetCurrentResourceName=function()return'bs_inventory'end
 e.GetResourceState=function(res)return states[res]or'started'end
 e.exports={bs_core={GetData=function()return data end,GetSessionState=function()return session end},bs_interactions={GetProgressState=function()return progress end}}
 e.AddEventHandler=function(k,fn)events[k]=fn end;e.RegisterNUICallback=function(k,fn)callbacks[k]=fn end
 e.SendNUIMessage=function(v)messages[#messages+1]=v end
 assert(loadfile(root..'/resources/[beyond]/bs_inventory/client/cl_pickups.lua','t',e))()
 return{env=e,events=events,callbacks=callbacks,messages=messages,data=data,states=states,progress=progress,
  ready=function()callbacks.pickupReady({},function()end)end,
  receipt=function(epoch,seq,char)events['bs:inventory:state']({pickups={epoch=epoch or'run',sequence=seq or 1,character=char or 101,changes={{item='water',amount=1}}}})end,
  count=function(action)local a=0;for _,m in ipairs(messages)do if m.action==action then a=a+1 end end;return a end}
end
local w=world();w.receipt();check(w.count('pickups')==0,'buffer before page ready');w.ready();check(w.count('pickups')==1,'deliver startup buffer once')
w.receipt();check(w.count('pickups')==1,'same packet cannot display twice');w.receipt('run',2);check(w.count('pickups')==2,'next confirmed packet')
w.receipt('run',3,202);check(w.count('pickups')==2,'foreign character ignored')
w.env.source=1;w.receipt('run',4);check(w.count('pickups')==2,'non-server event ignored');w.env.source=65535
w.progress.active=true;w.events['bs:interactions:progress'](w.progress);check(w.messages[#w.messages].state.active,'live local progress priority')
w.events.onClientResourceStop('bs_interactions');check(not w.messages[#w.messages].state.active,'progress resource stop releases area')
w.events['bs:hook:player:unloaded']();check(w.messages[#w.messages].action=='pickupReset','logout clears NUI queue')
w=world();w.env.Inventory.PickupVisuals.enabled=false;w.ready();w.receipt();check(w.count('pickups')==0,'disabled mode')
w=world();w.env.exports.bs_interactions.GetProgressState=function()error('legacy resource')end;w.ready()
check(w.messages[#w.messages].state.active,'old progress owner fails closed instead of overlapping')
print(('PASS: %d pickup client lifecycle assertions'):format(n))
