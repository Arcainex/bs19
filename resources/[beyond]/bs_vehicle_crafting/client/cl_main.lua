local open=false
local function notify(k,m) TriggerEvent('bs:ui:notify',{type=k,message=m,duration=5000}) end
local function show(mode,data) open=true; SetNuiFocus(true,true); SendNUIMessage({action='open',mode=mode,data=data}) end
local function close() open=false; SetNuiFocus(false,false); SendNUIMessage({action='close'}) end
local function openStorage() CreateThread(function() local r=BSB.Await('vehiclecraft:storage',8000); if r and r.ok then show('storage',r.data) else notify('error',(r and r.error) or 'Fehler') end end) end
local function openBuild() CreateThread(function() local r=BSB.Await('vehiclecraft:buildList',8000); if r and r.ok then show('build',r.data) else notify('error',(r and r.error) or 'Fehler') end end) end
CreateThread(function()
 Wait(1500)
 exports.bs_interactions:AddZone('bs_mech_parts',vector3(VehicleCraft.Storage.x,VehicleCraft.Storage.y,VehicleCraft.Storage.z+0.8),VehicleCraft.Storage.radius,{{label='Teilelager öffnen',icon='bag',event='bs:vehiclecraft:storage'}})
 exports.bs_interactions:AddZone('bs_mech_build',vector3(VehicleCraft.Build.x,VehicleCraft.Build.y,VehicleCraft.Build.z+0.5),VehicleCraft.Build.radius,{{label='Fahrzeug zusammenbauen',icon='wrench',event='bs:vehiclecraft:build'}})
end)
AddEventHandler('bs:vehiclecraft:storage',openStorage); AddEventHandler('bs:vehiclecraft:build',openBuild)
RegisterNUICallback('close',function(_,cb) close(); cb({ok=true}) end)
RegisterNUICallback('deposit',function(d,cb) CreateThread(function() cb(BSB.Await('vehiclecraft:deposit',8000,d) or {ok=false}) end) end)
RegisterNUICallback('withdraw',function(d,cb) CreateThread(function() cb(BSB.Await('vehiclecraft:withdraw',8000,d) or {ok=false}) end) end)
RegisterNUICallback('build',function(d,cb)
 CreateThread(function()
  local r=BSB.Await('vehiclecraft:start',8000,d); if not r or not r.ok then return cb(r or {ok=false}) end
  close(); cb({ok=true})
  local done=JC and JC.Timed and JC.Timed('Fahrzeug wird zusammengebaut...',r.ms,JC.Anim and JC.Anim.repair,'kneel') or exports.bs_interactions:RunSearch('Fahrzeug wird zusammengebaut...',r.ms,{pose='search'})
  if not done then BSB.Await('vehiclecraft:cancel',8000); return notify('warn','Fahrzeugbau abgebrochen. Teile wurden zurückgelegt.') end
  local f=BSB.Await('vehiclecraft:finish',8000); if not f or not f.ok then return notify('error',(f and f.error) or 'Bau fehlgeschlagen') end
  local hash=joaat(f.model); RequestModel(hash); local t=GetGameTimer(); while not HasModelLoaded(hash) and GetGameTimer()-t<10000 do Wait(50) end
  if not HasModelLoaded(hash) then return notify('error','Fahrzeugmodell konnte nicht geladen werden.') end
  local veh=CreateVehicle(hash,f.x,f.y,f.z,f.h,true,true); SetVehicleNumberPlateText(veh,f.plate); SetEntityAsMissionEntity(veh,true,true); SetVehicleOnGroundProperly(veh); SetVehicleFuelLevel(veh,20.0); SetModelAsNoLongerNeeded(hash)
  TriggerServerEvent('bs:vehicles:spawned',f.plate,true); TriggerServerEvent('bs:vehicles:placed',f.plate,f.x,f.y,f.z,f.h)
  notify('success',(f.label or f.model)..' wurde gebaut. Kennzeichen: '..f.plate)
 end)
end)
AddEventHandler('onResourceStop',function(r) if r==GetCurrentResourceName() then pcall(function() exports.bs_interactions:RemoveZone('bs_mech_parts'); exports.bs_interactions:RemoveZone('bs_mech_build') end); if open then SetNuiFocus(false,false) end end end)
