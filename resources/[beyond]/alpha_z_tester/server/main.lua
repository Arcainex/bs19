local vehiclesByModel, itemsByName = {}, {}
local freebuild = {}
for _, group in ipairs(AZTester.Vehicles) do
 for _, v in ipairs(group.entries) do vehiclesByModel[v.model] = v end
end
for _, group in ipairs(AZTester.Items) do
 for _, item in ipairs(group.entries) do itemsByName[item.name] = item end
end
local spawned = {}
local cooldown = {}
local function permitted(src)
 return type(src)=='number' and src>0 and IsPlayerAceAllowed(src, AZTester.Ace)
end
local function ping(src,msg,ok)
 TriggerClientEvent('alpha_z_tester:notify',src,msg,ok==true)
end
local function ready(src,kind,delay)
 local now=GetGameTimer()
 cooldown[src]=cooldown[src] or {}
 local last=cooldown[src][kind] or -100000
 if now-last<delay then ping(src,'Bitte kurz warten.',false); return false end
 cooldown[src][kind]=now
 return true
end
local function validPlayer(src)
 if not permitted(src) then return false end
 if GetResourceState('bs_inventory')~='started' or GetResourceState('bs_core')~='started' then
  ping(src,'Testsystem ist noch nicht bereit.',false); return false
 end
 local ped=GetPlayerPed(src)
 if ped==0 or GetEntityHealth(ped)<=0 then ping(src,'Nur mit einem lebenden Charakter möglich.',false);return false end
 return true
end
local function serializeList(src)
 local v,i={},{}
 for _,group in ipairs(AZTester.Vehicles) do
  local entries={}
  for _,e in ipairs(group.entries) do entries[#entries+1]={id=e.model,label=e.label} end
  v[#v+1]={label=group.label,entries=entries}
 end
 for _,group in ipairs(AZTester.Items) do
  local entries={}
  for _,e in ipairs(group.entries) do entries[#entries+1]={id=e.name,label=e.label} end
  i[#i+1]={label=group.label,entries=entries}
 end
 return {vehicles=v,items=i,features={heal=AZTester.EnableSelfHeal,repair=AZTester.EnableRepair,coords=AZTester.EnableCoords,weaponcarry=GetResourceState('alpha_z_weaponcarry')=='started',freebuild=AZTester.EnableFreeBuild,freebuildEnabled=freebuild[src]==true}}
end
RegisterNetEvent('alpha_z_tester:openRequest',function()
 local src=source
 if not permitted(src) then return end
 TriggerClientEvent('alpha_z_tester:open',src,serializeList(src))
end)
RegisterNetEvent('alpha_z_tester:giveItem',function(item,amount)
 local src=source
 if not validPlayer(src) then return end
 if type(item)~='string' or not itemsByName[item] then return end
 amount=tonumber(amount)
 if not amount or amount%1~=0 or amount<1 or amount>AZTester.MaxItemAmount then
  ping(src,'Ungültige Menge (max. '..AZTester.MaxItemAmount..').',false);return
 end
 if not ready(src,'item',AZTester.ItemCooldownMs) then return end
 local ok,result=pcall(function() return exports.bs_inventory:GiveItem(src,item,amount) end)
 if ok and result then
  ping(src,('Erhalten: %sx %s'):format(amount,itemsByName[item].label),true)
  print(('[AZ TESTER] %s (%s) gab sich %sx %s'):format(GetPlayerName(src) or '?',src,amount,item))
 else ping(src,'Inventar voll oder Item nicht verfügbar.',false) end
end)
local function trimVehicles(src)
 local list=spawned[src] or {}
 for i=#list,1,-1 do if not DoesEntityExist(list[i]) then table.remove(list,i) end end
 spawned[src]=list
 return list
end
RegisterNetEvent('alpha_z_tester:spawnVehicle',function(model)
 local src=source
 if not validPlayer(src) then return end
 if type(model)~='string' or not vehiclesByModel[model] then return end
 if not ready(src,'vehicle',AZTester.VehicleCooldownMs) then return end
 local list=trimVehicles(src)
 if #list>=AZTester.MaxVehiclesPerTester then
  ping(src,'Maximal '..AZTester.MaxVehiclesPerTester..' Testfahrzeuge. Entferne zuerst deine alten.',false);return
 end
 local ped=GetPlayerPed(src)
 local pos=GetEntityCoords(ped)
 local heading=GetEntityHeading(ped)
 local r=math.rad(heading)
 local x=pos.x-math.sin(r)*5.0
 local y=pos.y+math.cos(r)*5.0
 local hash=GetHashKey(model)
 -- Server-created, networked vehicle; model must be on the whitelist above.
 local veh=CreateVehicle(hash,x,y,pos.z+0.5,heading,true,true)
 if not veh or veh==0 or not DoesEntityExist(veh) then
  ping(src,'Fahrzeug konnte nicht erstellt werden.',false); return
 end
 SetEntityOrphanMode(veh,2)
 local netId=NetworkGetNetworkIdFromEntity(veh)
 list[#list+1]=veh
 TriggerClientEvent('alpha_z_tester:vehicleCreated',src,netId)
 ping(src,'Testfahrzeug gespawnt: '..vehiclesByModel[model].label,true)
 print(('[AZ TESTER] %s (%s) spawned %s'):format(GetPlayerName(src) or '?',src,model))
end)
RegisterNetEvent('alpha_z_tester:deleteVehicles',function()
 local src=source
 if not permitted(src) then return end
 if not ready(src,'cleanup',AZTester.UtilityCooldownMs) then return end
 local list=spawned[src] or {}
 for _,entity in ipairs(list) do if DoesEntityExist(entity) then DeleteEntity(entity) end end
 spawned[src]={}
 ping(src,'Eigene Testfahrzeuge entfernt.',true)
end)
RegisterNetEvent('alpha_z_tester:utility',function(action,netId)
 local src=source
 if not validPlayer(src) then return end
 if not ready(src,'utility',AZTester.UtilityCooldownMs) then return end
 if action=='heal' and AZTester.EnableSelfHeal then
  -- Medical conditions are persistent and server-authoritative.
  -- Ped health alone does not stop bleeding / remove fractures or wounds.
  if GetResourceState('bs_medical')~='started' then
   ping(src,'bs_medical ist nicht gestartet: Vollheilung nicht möglich.',false);return
  end
  local ok,cleared=pcall(function() return exports.bs_medical:ClearConditions(src) end)
  if not ok or cleared~=true then
   ping(src,'Verletzungen und Blutungen konnten nicht geheilt werden.',false);return
  end
  TriggerClientEvent('bs:medical:heal',src,1000)
  TriggerClientEvent('alpha_z_tester:healSelf',src)
  print(('[AZ TESTER] %s (%s) full medical heal'):format(GetPlayerName(src) or '?',src))
 elseif action=='repair' and AZTester.EnableRepair then
  netId=tonumber(netId)
  if not netId or netId%1~=0 or netId<1 then return end
  local veh=NetworkGetEntityFromNetworkId(netId)
  local ped=GetPlayerPed(src)
  if veh==0 or not DoesEntityExist(veh) or GetEntityType(veh)~=2 then return end
  if #(GetEntityCoords(ped)-GetEntityCoords(veh))>8.0 then ping(src,'Fahrzeug zu weit entfernt.',false);return end
  TriggerClientEvent('alpha_z_tester:repairVehicle',src,netId)
  print(('[AZ TESTER] %s (%s) repair %s'):format(GetPlayerName(src) or '?',src,netId))
 end
end)
AddEventHandler('playerDropped',function()
 local src=source
 for _,veh in ipairs(spawned[src] or {}) do if DoesEntityExist(veh) then DeleteEntity(veh) end end
 spawned[src]=nil;cooldown[src]=nil;freebuild[src]=nil
end)

-- Building integration: the building resource must call this from the server
-- when checking material cost. Never trust a client-side boolean.
exports('IsFreeBuildForTester', function(src)
 src=tonumber(src)
 return src and src>0 and AZTester.EnableFreeBuild == true
     and IsPlayerAceAllowed(src,AZTester.Ace) and freebuild[src]==true or false
end)
RegisterNetEvent('alpha_z_tester:freebuildToggle', function()
 local src=source
 if not permitted(src) or not AZTester.EnableFreeBuild then return end
 if not ready(src,'freebuild',800) then return end
 freebuild[src]=not freebuild[src]
 local enabled=freebuild[src]==true
 ping(src,enabled and 'Kostenloses Bauen: AN (Bausystem-Anbindung erforderlich)' or 'Kostenloses Bauen: AUS',enabled)
 TriggerClientEvent('alpha_z_tester:freebuildState',src,enabled)
 print(('[AZ TESTER] %s (%d) personal freebuild %s'):format(GetPlayerName(src) or '?',src,enabled and 'ON' or 'OFF'))
end)
