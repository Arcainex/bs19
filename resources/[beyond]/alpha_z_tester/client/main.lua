local shown=false
local function notify(message,success)
 TriggerEvent('bs:ui:notify',{type=success and 'success' or 'warn',message=message,duration=3000})
end
RegisterNetEvent('alpha_z_tester:notify',notify)
local function close()
 if not shown then return end
 shown=false
 SetNuiFocus(false,false)
 SendNUIMessage({action='close'})
 TriggerEvent('bs:ui:closed','alpha_z_tester')
end
RegisterNetEvent('alpha_z_tester:open',function(data)
 if shown then return end
 shown=true
 SendNUIMessage({action='open',data=data})
 SetNuiFocus(true,true)
 TriggerEvent('bs:ui:opened','alpha_z_tester')
end)
RegisterCommand(AZTester.Command,function()
 if shown then close() else TriggerServerEvent('alpha_z_tester:openRequest') end
end,false)
RegisterKeyMapping(AZTester.Command,'Alpha-Z Testermenü öffnen','keyboard','F4')
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('item',function(d,cb)
 if shown and type(d)=='table' then TriggerServerEvent('alpha_z_tester:giveItem',d.id,d.amount) end
 cb({ok=true})
end)
RegisterNUICallback('vehicle',function(d,cb)
 if shown and type(d)=='table' then TriggerServerEvent('alpha_z_tester:spawnVehicle',d.id) end
 cb({ok=true})
end)
RegisterNUICallback('removeVehicles',function(_,cb)
 if shown then TriggerServerEvent('alpha_z_tester:deleteVehicles') end
 cb({ok=true})
end)
-- Opening the separate WeaponCarry UI requires its own server-side ACE check.
-- Never invoke the editor's client open event directly.
RegisterNUICallback('weaponcarry',function(_,cb)
 if not shown then cb({ok=false});return end
 if GetResourceState('alpha_z_weaponcarry')~='started' then
  notify('WeaponCarry ist nicht gestartet.',false);cb({ok=false});return
 end
 close()
 TriggerServerEvent('alpha_z_weaponcarry:requestEditor')
 cb({ok=true})
end)
RegisterNUICallback('heal',function(_,cb)
 if shown then TriggerServerEvent('alpha_z_tester:utility','heal') end
 cb({ok=true})
end)
RegisterNUICallback('repair',function(_,cb)
 if shown then
  local ped=PlayerPedId()
  local veh=GetVehiclePedIsIn(ped,false)
  if veh==0 then veh=GetClosestVehicle(GetEntityCoords(ped),6.0,0,70) end
  if veh~=0 then TriggerServerEvent('alpha_z_tester:utility','repair',NetworkGetNetworkIdFromEntity(veh))
  else notify('Kein Fahrzeug in Reichweite.',false) end
 end
 cb({ok=true})
end)
RegisterNUICallback('coords',function(_,cb)
 if not shown then cb({ok=false});return end
 local pos=GetEntityCoords(PlayerPedId())
 local heading=GetEntityHeading(PlayerPedId())
 cb({ok=true,coords=('vector4(%.2f, %.2f, %.2f, %.2f)'):format(pos.x,pos.y,pos.z,heading)})
end)
RegisterNetEvent('alpha_z_tester:healSelf',function()
 local ped=PlayerPedId()
 if not IsEntityDead(ped) then
  SetEntityHealth(ped,GetEntityMaxHealth(ped))
  ClearPedBloodDamage(ped)
  notify('Lebenspunkte, Verletzungen und Blutungen geheilt (kein Revive).',true)
 end
end)
RegisterNetEvent('alpha_z_tester:repairVehicle',function(netId)
 local veh=NetworkGetEntityFromNetworkId(netId)
 if veh==0 or not DoesEntityExist(veh) then return end
 local ped=PlayerPedId()
 if #(GetEntityCoords(veh)-GetEntityCoords(ped))>8.0 then return end
 SetVehicleFixed(veh);SetVehicleDeformationFixed(veh);SetVehicleEngineHealth(veh,1000.0)
 notify('Fahrzeug repariert.',true)
end)
RegisterNetEvent('alpha_z_tester:vehicleCreated',function(netId)
 local deadline=GetGameTimer()+2500
 while not NetworkDoesNetworkIdExist(netId) and GetGameTimer()<deadline do Wait(50) end
 local veh=NetworkGetEntityFromNetworkId(netId)
 if veh and veh~=0 then SetVehicleOnGroundProperly(veh) end
end)
AddEventHandler('onResourceStop',function(res)
 if res==GetCurrentResourceName() and shown then SetNuiFocus(false,false) end
end)

RegisterNUICallback('freebuildToggle',function(_,cb)
 if shown then TriggerServerEvent('alpha_z_tester:freebuildToggle') end
 cb({ok=shown})
end)
RegisterNetEvent('alpha_z_tester:freebuildState',function(enabled)
 SendNUIMessage({action='freebuildState',enabled=enabled==true})
end)
