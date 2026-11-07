local INV = exports.bs_inventory
local busy = false
local partSet = {}
for _,p in ipairs(VehicleCraft.Parts) do partSet[p.item]=p end

local function mechanic(src)
 -- Workshop access is based on faction membership only.
 -- The active mechanic job is intentionally NOT required, because players
 -- remain Civilians as their base faction and mechanic_workshop is secondary.
 if GetResourceState('bs_factions') ~= 'started' then return false end
 local ok, member = pcall(function()
  return exports.bs_factions:HasFactionMembership(src, VehicleCraft.Faction)
 end)
 if ok and member == true then return true end
 -- Compatibility fallback for older bs_factions versions.
 local ok2, secondary = pcall(function()
  return exports.bs_factions:HasSecondaryFaction(src, VehicleCraft.Faction)
 end)
 return ok2 and secondary == true
end
local function near(src, p, max)
 local ped=GetPlayerPed(src); if not ped or ped==0 then return false end
 local c=GetEntityCoords(ped); local dx,dy,dz=c.x-p.x,c.y-p.y,c.z-p.z
 return dx*dx+dy*dy+dz*dz <= (max or p.radius or 3.0)^2
end
local function stock()
 local out={}; for item in pairs(partSet) do out[item]=0 end
 local rows=exports.oxmysql:query_async('SELECT item, amount FROM bs_mechanic_parts') or {}
 for _,v in ipairs(rows) do if partSet[v.item] then out[v.item]=tonumber(v.amount) or 0 end end
 return out
end
local function payload()
 local s=stock(); local parts={}
 for _,p in ipairs(VehicleCraft.Parts) do parts[#parts+1]={item=p.item,label=p.label,amount=s[p.item] or 0} end
 return {parts=parts,stock=s,recipes=VehicleCraft.Recipes,buildSeconds=VehicleCraft.BuildSeconds}
end
local function deny(src, at)
 if not mechanic(src) then return {ok=false,error='Nur Mechaniker der Mechaniker Werkstatt haben Zugriff.'} end
 if at and not near(src,at,(at.radius or 3.0)+1.0) then return {ok=false,error='Du bist zu weit entfernt.'} end
end

MySQL.ready(function()
 exports.oxmysql:execute_async([[CREATE TABLE IF NOT EXISTS bs_mechanic_parts (
  item VARCHAR(64) NOT NULL PRIMARY KEY, amount INT NOT NULL DEFAULT 0, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
 )]])
 exports.oxmysql:execute_async([[CREATE TABLE IF NOT EXISTS bs_mechanic_build_log (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, character_id INT NULL, player_name VARCHAR(96) NULL, model VARCHAR(64) NOT NULL, plate VARCHAR(16) NOT NULL,
  recipe LONGTEXT NULL, built_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
 )]])
end)

BSB.RegisterCallback('vehiclecraft:storage', function(src)
 local d=deny(src,VehicleCraft.Storage); if d then return d end
 return {ok=true,data=payload()}
end)
BSB.RegisterCallback('vehiclecraft:deposit', function(src,a)
 local d=deny(src,VehicleCraft.Storage); if d then return d end
 local item=tostring(a and a.item or ''); local n=math.floor(tonumber(a and a.amount) or 1)
 if not partSet[item] or n<1 or n>20 then return {ok=false,error='Ungültiges Fahrzeugteil.'} end
 if INV:CountItem(src,item)<n or not INV:RemoveItem(src,item,n) then return {ok=false,error='Nicht genug Teile im Inventar.'} end
 exports.oxmysql:execute_async('INSERT INTO bs_mechanic_parts (item,amount) VALUES (?,?) ON DUPLICATE KEY UPDATE amount=amount+VALUES(amount)',{item,n})
 return {ok=true,data=payload()}
end)
BSB.RegisterCallback('vehiclecraft:withdraw', function(src,a)
 local d=deny(src,VehicleCraft.Storage); if d then return d end
 local item=tostring(a and a.item or ''); local n=math.floor(tonumber(a and a.amount) or 1)
 if not partSet[item] or n<1 or n>20 then return {ok=false,error='Ungültiges Fahrzeugteil.'} end
 local changed=exports.oxmysql:update_async('UPDATE bs_mechanic_parts SET amount=amount-? WHERE item=? AND amount>=?',{n,item,n}) or 0
 if changed<1 then return {ok=false,error='Nicht genug Teile im Lager.'} end
 if not INV:GiveItem(src,item,n) then
  exports.oxmysql:execute_async('UPDATE bs_mechanic_parts SET amount=amount+? WHERE item=?',{n,item})
  return {ok=false,error='Kein Platz im Inventar.'}
 end
 return {ok=true,data=payload()}
end)
BSB.RegisterCallback('vehiclecraft:buildList', function(src)
 local d=deny(src,VehicleCraft.Build); if d then return d end
 return {ok=true,data=payload()}
end)
local pending={}
BSB.RegisterCallback('vehiclecraft:start', function(src,a)
 local d=deny(src,VehicleCraft.Build); if d then return d end
 if busy or pending[src] then return {ok=false,error='Die Hebebühne wird bereits benutzt.'} end
 local id=tostring(a and a.id or ''); local rec
 for _,v in ipairs(VehicleCraft.Recipes) do if v.id==id then rec=v break end end
 if not rec then return {ok=false,error='Unbekanntes Fahrzeug.'} end
 local s=stock(); for item,n in pairs(rec.recipe) do if (s[item] or 0)<n then return {ok=false,error='Es fehlen Fahrzeugteile.'} end end
 -- reserve all recipe parts; rollback if any concurrent update fails
 local taken={}
 for item,n in pairs(rec.recipe) do
  local changed=exports.oxmysql:update_async('UPDATE bs_mechanic_parts SET amount=amount-? WHERE item=? AND amount>=?',{n,item,n}) or 0
  if changed<1 then
   for ri,rn in pairs(taken) do exports.oxmysql:execute_async('UPDATE bs_mechanic_parts SET amount=amount+? WHERE item=?',{rn,ri}) end
   return {ok=false,error='Lagerbestand hat sich geändert.'}
  end
  taken[item]=n
 end
 busy=true; pending[src]={rec=rec,taken=taken,at=os.time()}
 return {ok=true,ms=(VehicleCraft.BuildSeconds or 60)*1000,label=rec.label}
end)
BSB.RegisterCallback('vehiclecraft:cancel', function(src)
 local p=pending[src]; if not p then return {ok=true} end
 for item,n in pairs(p.taken) do exports.oxmysql:execute_async('UPDATE bs_mechanic_parts SET amount=amount+? WHERE item=?',{n,item}) end
 pending[src]=nil; busy=false; return {ok=true}
end)
BSB.RegisterCallback('vehiclecraft:finish', function(src)
 local p=pending[src]; if not p then return {ok=false,error='Kein Fahrzeugbau aktiv.'} end
 local d=deny(src,VehicleCraft.Build); if d then
  for item,n in pairs(p.taken) do exports.oxmysql:execute_async('UPDATE bs_mechanic_parts SET amount=amount+? WHERE item=?',{n,item}) end
  pending[src]=nil; busy=false; return d
 end
 if os.time()-(p.at or 0) < math.max(1,(VehicleCraft.BuildSeconds or 60)-2) then return {ok=false,error='Der Bau ist noch nicht fertig.'} end
 local plate=exports.bs_vehicles:GeneratePlate(); local pl=exports.bs_core:GetPlayer(src); local cid=pl and pl.charId
 if not plate or not cid then return {ok=false,error='Fahrzeug konnte nicht registriert werden.'} end
 local registered=exports.bs_vehicles:TesterRegister(plate,p.rec.id,cid)
 if not registered then return {ok=false,error='Fahrzeug konnte nicht registriert werden.'} end
 exports.oxmysql:insert_async('INSERT INTO bs_mechanic_build_log (character_id,player_name,model,plate,recipe) VALUES (?,?,?,?,?)',{cid,GetPlayerName(src) or '',p.rec.id,plate,json.encode(p.rec.recipe)})
 pending[src]=nil; busy=false
 return {ok=true,model=p.rec.id,label=p.rec.label,plate=plate,x=VehicleCraft.Build.x,y=VehicleCraft.Build.y,z=VehicleCraft.Build.z,h=VehicleCraft.Build.h}
end)
AddEventHandler('playerDropped',function()
 local src=source; local p=pending[src]; if p then for item,n in pairs(p.taken) do exports.oxmysql:execute_async('UPDATE bs_mechanic_parts SET amount=amount+? WHERE item=?',{n,item}) end; pending[src]=nil; busy=false end
end)
