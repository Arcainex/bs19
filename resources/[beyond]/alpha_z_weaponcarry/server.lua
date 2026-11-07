local lastSeen={}
local saved={slots={},items={}}
-- The UI is not a security boundary; only these known ped bones can be saved.
local allowedBones={}
for _,entry in ipairs(Carry.Bones or {}) do allowedBones[entry.id]=true end
local function validVec(t)
 if type(t)~='table' or #t~=3 then return false end
 for i=1,3 do if type(t[i])~='number' or t[i]~=t[i] or math.abs(t[i])>360 then return false end end
 return true
end
local function clean(t)
 if type(t)~='table' or not validVec(t.pos) or not validVec(t.rot) then return nil end
 local bone=tonumber(t.bone)
 if not bone or bone%1~=0 or not allowedBones[bone] then return nil end
 for i=1,3 do if math.abs(t.pos[i])>2.0 then return nil end end
 return {bone=bone,pos=t.pos,rot=t.rot}
end
local raw=LoadResourceFile(GetCurrentResourceName(),'positions.json')
if raw and raw~='' then local ok,v=pcall(json.decode,raw);if ok and type(v)=='table' then
 for k,t in pairs(v.slots or {}) do if Carry.Slots[k] then saved.slots[k]=clean(t) end end
 for k,t in pairs(v.items or {}) do if Carry.Items[k] then saved.items[k]=clean(t) end end
end end
-- Distinct permissions: testers may edit their own character; only admins may change defaults.
local function canGlobal(src)
 if src==0 then return true end
 for _,ace in ipairs(Carry.GlobalEditorAces or {'bs.admin','bs.superadmin','command.zombiemenu'}) do
  if IsPlayerAceAllowed(src,ace) then return true end
 end
 return false
end
local function canPersonal(src)
 if canGlobal(src) then return true end
 for _,ace in ipairs(Carry.PersonalEditorAces or {'alpha_z.weaponcarry.edit','alpha_z.tester'}) do
  if IsPlayerAceAllowed(src,ace) then return true end
 end
 return false
end
local function charId(src)
 if GetResourceState('bs_core')~='started' then return nil end
 local ok,p=pcall(function() return exports.bs_core:GetPlayer(src) end)
 if not ok or type(p)~='table' then return nil end
 local id=tonumber(p.charId)
 if not id or id<=0 or id%1~=0 then return nil end
 return tostring(id)
end
local personalFile='character_positions.json'
local personal={}
do
 local raw=LoadResourceFile(GetCurrentResourceName(),personalFile)
 if raw and raw~='' then
  local ok,v=pcall(json.decode,raw)
  if ok and type(v)=='table' then
   for id,d in pairs(v) do
    if tostring(id):match('^%d+$') and type(d)=='table' then
     local entry={slots={},items={}}
     for scope,defs in pairs({slots=Carry.Slots,items=Carry.Items}) do
      for k,t in pairs(d[scope] or {}) do if defs[k] then entry[scope][k]=clean(t) end end
     end
     personal[tostring(id)]=entry
    end
   end
  end
 end
end
local function ownPositions(src)
 local id=charId(src)
 return id and personal[id] or nil
end
local function merged(src)
 local result={slots={},items={}}
 for _,scope in ipairs({'slots','items'}) do
  for k,v in pairs(saved[scope]) do result[scope][k]=v end
  local own=ownPositions(src)
  for k,v in pairs(own and own[scope] or {}) do result[scope][k]=v end
 end
 return result
end
local function replicatePersonal(src)
 local id=charId(src)
 local player=Player(src)
 if player then
  player.state:set('alphaZCarryPersonal',id and personal[id] or {slots={},items={}},true)
 end
 return id
end
local function publishGlobal()
 TriggerClientEvent('alpha_z_weaponcarry:positions',-1,saved)
end
RegisterNetEvent('alpha_z_weaponcarry:getPositions',function()
 local src=source
 replicatePersonal(src)
 TriggerClientEvent('alpha_z_weaponcarry:positions',src,saved)
end)
local function openEditor(src)
 if not canPersonal(src) then
  TriggerClientEvent('alpha_z_weaponcarry:notice',src,'Keine Berechtigung für den Waffen-Editor.')
  return
 end
 if not replicatePersonal(src) then
  TriggerClientEvent('alpha_z_weaponcarry:notice',src,'Bitte zuerst einen Charakter laden.')
  return
 end
 TriggerClientEvent('alpha_z_weaponcarry:openEditor',src,merged(src),canGlobal(src))
end
RegisterNetEvent('alpha_z_weaponcarry:requestEditor',function() openEditor(source) end)
local function editorResult(src,operation,ok,message,scope,key)
 if src<=0 then return end
 TriggerClientEvent('alpha_z_weaponcarry:editorResult',src,{
  operation=operation,ok=ok,message=message,scope=scope,key=key,
  overrides=ok and merged(src) or nil
 })
end
local function validSelection(scope,key)
 return (scope=='slots' and Carry.Slots[key]) or (scope=='items' and Carry.Items[key])
end
local function clonePositions(current)
 local result={slots={},items={}}
 for _,scope in ipairs({'slots','items'}) do
  for k,v in pairs(current and current[scope] or {}) do result[scope][k]=v end
 end
 return result
end
local function store(src,operation,scope,key,data)
 if not canPersonal(src) then return end
 if type(key)~='string' or #key>96 or not validSelection(scope,key) then return end
 local global=canGlobal(src)
 local id=global and nil or charId(src)
 if not global and not id then
  editorResult(src,operation,false,'Kein Charakter geladen.',scope,key)
  return
 end
 local v=operation=='save' and clean(data) or nil
 if operation=='save' and not v then
  editorResult(src,operation,false,'Ungültige Werte oder nicht erlaubter Knochen.',scope,key)
  return
 end
 if global then
  local nextSaved=clonePositions(saved)
  nextSaved[scope][key]=v
  if not SaveResourceFile(GetCurrentResourceName(),'positions.json',json.encode(nextSaved),-1) then
   editorResult(src,operation,false,'Speichern fehlgeschlagen. Dateirechte prüfen.',scope,key)
   return
  end
  saved=nextSaved
  publishGlobal()
  editorResult(src,operation,true,operation=='save' and 'Serverweite Waffenposition gespeichert.' or 'Globale Standardposition zurückgesetzt.',scope,key)
 else
  local nextAll={}
  for who,entry in pairs(personal) do nextAll[who]=entry end
  local nextOwn=clonePositions(personal[id])
  nextOwn[scope][key]=v
  nextAll[id]=nextOwn
  if not SaveResourceFile(GetCurrentResourceName(),personalFile,json.encode(nextAll),-1) then
   editorResult(src,operation,false,'Persönliche Position konnte nicht gespeichert werden.',scope,key)
   return
  end
  personal=nextAll
  replicatePersonal(src)
  editorResult(src,operation,true,operation=='save' and 'Nur für deinen Charakter gespeichert.' or 'Persönliche Position zurückgesetzt.',scope,key)
 end
end
RegisterNetEvent('alpha_z_weaponcarry:savePosition',function(scope,key,data)
 store(source,'save',scope,key,data)
end)
RegisterNetEvent('alpha_z_weaponcarry:resetPosition',function(scope,key)
 store(source,'reset',scope,key,nil)
end)
RegisterCommand('weaponcarry',function(src)
 if src>0 then openEditor(src) end
end,false)
-- Character switching can occur without reconnecting. Clear inherited personal layouts
-- and republish the current character's layout whenever the core's charId changes.
local lastCharacter={}
CreateThread(function()
 while true do
  Wait(1500)
  for _,id in ipairs(GetPlayers()) do
   local src=tonumber(id)
   local cid=charId(src) or ''
   if lastCharacter[src]~=cid then
    lastCharacter[src]=cid
    replicatePersonal(src)
   end
  end
 end
end)
AddEventHandler('playerDropped',function() lastCharacter[source]=nil end)
-- Alpha-Z physical weapon slots are the only source of carried props.
-- Inventory server validates placements and provides unambiguous item IDs.
local physical = { ['1']='melee', ['2']='rifle', ['3']='left', ['4']='right' }
local function publish(src)
 local slots={}
 if GetResourceState('bs_inventory')=='started' then
  local ok,items=pcall(function() return exports.bs_inventory:WeaponCarryHotbarSlotItems(src) end)
  if ok and type(items)=='table' then
   for number,slot in pairs(physical) do
    local item=items[number]
    if type(item)=='string' and Carry.Items[item] then slots[slot]=item end
   end
  end
 end
 local signature=json.encode(slots)
 if signature~=lastSeen[src] then
  lastSeen[src]=signature
  Player(src).state:set('alphaZCarry',slots,true)
 end
end
-- Existing event is retained for compatibility, but cannot change physical slots.
RegisterNetEvent('alpha_z_weaponcarry:used',function() publish(source) end)
CreateThread(function()
 while true do
  Wait(750)
  for _,id in ipairs(GetPlayers()) do publish(tonumber(id)) end
 end
end)
AddEventHandler('playerDropped',function() lastSeen[source]=nil end)
