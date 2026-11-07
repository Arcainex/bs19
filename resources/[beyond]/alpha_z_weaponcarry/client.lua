local objects={}
-- Separate local-only entities on bs_multichar's preview ped, never networked.
-- They are not player state and must not be touched by the normal carry updater.
local previewObjects={}
local previewRevision=0
local overrides={slots={},items={}}
local globalOverrides={slots={},items={}}
local editorGlobal=false
local function mergeLocalPositions()
 local result={slots={},items={}}
 local personal=LocalPlayer.state.alphaZCarryPersonal or {}
 for _,scope in ipairs({'slots','items'}) do
  for k,v in pairs(globalOverrides[scope] or {}) do result[scope][k]=v end
  for k,v in pairs(personal[scope] or {}) do result[scope][k]=v end
 end
 return result
end
local function personalForPed(ped)
 for _,player in ipairs(GetActivePlayers()) do
  if GetPlayerPed(player)==ped then
   local s=Player(GetPlayerServerId(player)).state.alphaZCarryPersonal
   if type(s)=='table' then return s end
   return nil
  end
 end
 return nil
end
local preview=nil
local editorOpen=false
local gizmoActive=false
local gizmoSelection=nil
-- V1.10: Orbit the currently selected, visible weapon prop (NOT the ped).
-- For accurate framing we use the center of the model's bounding box,
-- transformed into world coordinates. ALT and the gizmo share this target.
local editorCam=nil
local cameraAzimuth=0.0
local cameraElevation=10.0
local cameraDistance=1.65
local cameraFocusHeight=0.95 -- fallback only, when no selected weapon is visible
local cameraSelection={scope='slots',key='rifle'}
local cameraSmoothedTarget=nil
local cameraLastWeaponTarget=nil
local cameraLastWeaponTime=0
local function clampCamera(value,low,high)
 return math.max(low,math.min(high,value))
end
local function selectedCameraObject()
 local selected=cameraSelection
 if not selected then return nil end
 local prefix=tostring(GetPlayerServerId(PlayerId()))..':'
 if selected.scope=='items' then
  -- An item can occupy either belt slot regardless of its preferred default.
  -- Find the actual visible instance rather than assuming Carry.Items[item][2].
  for _,slot in ipairs({'left','right','melee','rifle'}) do
   local obj=objects[prefix..slot]
   if obj and obj.item==selected.key and obj.ped==PlayerPedId()
      and DoesEntityExist(obj.entity) then return obj end
  end
  return nil
 end
 local obj=objects[prefix..tostring(selected.key)]
 if not obj or obj.ped~=PlayerPedId() or not DoesEntityExist(obj.entity) then return nil end
 return obj
end
local function weaponVisualCenter(entity)
 local center=GetEntityCoords(entity)
 local min,max=GetModelDimensions(GetEntityModel(entity))
 if min and max then
  local x=(min.x+max.x)*0.5
  local y=(min.y+max.y)*0.5
  local z=(min.z+max.z)*0.5
  -- Reject corrupt dimensions rather than aiming the camera far away.
  if x==x and y==y and z==z and
   math.abs(x)<4.0 and math.abs(y)<4.0 and math.abs(z)<4.0 then
   center=GetOffsetFromEntityInWorldCoords(entity,x+0.0,y+0.0,z+0.0)
  end
 end
 return center
end
local function cameraTarget()
 local obj=selectedCameraObject()
 if obj then
  local center=weaponVisualCenter(obj.entity)
  cameraLastWeaponTarget=center
  cameraLastWeaponTime=GetGameTimer()
  return center,true
 end
 -- Brief grace period for inventory refreshes that recreate a prop.
 if cameraLastWeaponTarget and GetGameTimer()-cameraLastWeaponTime<800 then
  return cameraLastWeaponTarget,true
 end
 local ped=PlayerPedId()
 if ped==0 or not DoesEntityExist(ped) then return nil,false end
 local origin=GetEntityCoords(ped)
 return vector3(origin.x,origin.y,origin.z+cameraFocusHeight),false
end
local function recommendedWeaponDistance(obj)
 if not obj then return 1.65 end
 local min,max=GetModelDimensions(GetEntityModel(obj.entity))
 if not min or not max then return 1.65 end
 local size=math.max(max.x-min.x,max.y-min.y,max.z-min.z)
 if size~=size or size<0.0 or size>5.0 then return 1.65 end
 return clampCamera(0.95+size*1.15,0.90,2.8)
end
local function orientCameraToSlot(slot)
 local ped=PlayerPedId()
 if ped==0 or not DoesEntityExist(ped) then return end
 local forward=GetEntityForwardVector(ped)
 local facing=math.deg(math.atan(forward.y,forward.x))
 -- Show back-mounted weapons from behind; belt weapons from their side.
 local angle=slot=='left' and 90.0 or (slot=='right' and -90.0 or 180.0)
 cameraAzimuth=(facing+angle)%360.0
 cameraElevation=10.0
end
local function setCameraSelection(scope,key)
 local valid=(scope=='slots' and Carry.Slots[key]) or
  (scope=='items' and Carry.Items[key])
 if not valid then
  cameraSelection=nil
  cameraSmoothedTarget=nil
  cameraLastWeaponTarget=nil
  return
 end
 if cameraSelection and cameraSelection.scope==scope and cameraSelection.key==key then return end
 cameraSelection={scope=scope,key=key}
 cameraSmoothedTarget=nil
 cameraLastWeaponTarget=nil
 local slot=scope=='slots' and key or Carry.Items[key][2]
 orientCameraToSlot(slot)
 local obj=selectedCameraObject()
 cameraDistance=obj and recommendedWeaponDistance(obj) or 3.1
end
local function updateEditorCamera()
 if not editorCam or not DoesCamExist(editorCam) then return end
 local target,isWeapon=cameraTarget()
 if not target then return end
 if not cameraSmoothedTarget then
  cameraSmoothedTarget=target
 else
  -- Smooth the focus when moving the weapon with the gizmo.
  local a=isWeapon and 0.40 or 0.25
  local prev=cameraSmoothedTarget
  cameraSmoothedTarget=vector3(
   prev.x+(target.x-prev.x)*a,
   prev.y+(target.y-prev.y)*a,
   prev.z+(target.z-prev.z)*a)
 end
 local focus=cameraSmoothedTarget
 local angle=math.rad(cameraAzimuth)
 local elevation=math.rad(cameraElevation)
 local horizontal=cameraDistance*math.cos(elevation)
 SetCamCoord(editorCam,
  focus.x+horizontal*math.cos(angle),
  focus.y+horizontal*math.sin(angle),
  focus.z+cameraDistance*math.sin(elevation))
 PointCamAtCoord(editorCam,focus.x,focus.y,focus.z)
end
local function stopEditorCamera()
 if editorCam and DoesCamExist(editorCam) then
  RenderScriptCams(false,true,250,true,true)
  SetCamActive(editorCam,false)
  DestroyCam(editorCam,false)
 end
 editorCam=nil
 cameraSmoothedTarget=nil
 cameraLastWeaponTarget=nil
end
local function startEditorCamera()
 if editorCam and DoesCamExist(editorCam) then return end
 local ped=PlayerPedId()
 if ped==0 or not DoesEntityExist(ped) then return end
 local slot=cameraSelection and (cameraSelection.scope=='slots' and cameraSelection.key or
  (Carry.Items[cameraSelection.key] and Carry.Items[cameraSelection.key][2])) or 'rifle'
 orientCameraToSlot(slot)
 local obj=selectedCameraObject()
 cameraDistance=obj and recommendedWeaponDistance(obj) or 3.1
 cameraSmoothedTarget=nil
 editorCam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
 if not editorCam or not DoesCamExist(editorCam) then editorCam=nil;return end
 SetCamFov(editorCam,48.0)
 updateEditorCamera()
 SetCamActive(editorCam,true)
 RenderScriptCams(true,true,250,true,true)
end
local function orbitEditorCamera(dx,dy)
 if not editorCam or not DoesCamExist(editorCam) then return end
 dx=clampCamera(tonumber(dx) or 0.0,-120.0,120.0)
 dy=clampCamera(tonumber(dy) or 0.0,-120.0,120.0)
 cameraAzimuth=(cameraAzimuth-dx*0.26)%360.0
 cameraElevation=clampCamera(cameraElevation+dy*0.18,-80.0,80.0)
 updateEditorCamera()
end
local function zoomEditorCamera(delta)
 if not editorCam or not DoesCamExist(editorCam) then return end
 delta=clampCamera(tonumber(delta) or 0.0,-600.0,600.0)
 cameraDistance=clampCamera(cameraDistance+delta*0.0025,0.30,5.0)
 updateEditorCamera()
end
local refreshPreview -- defined after update(); NUI previews call it immediately.
local function getPlacement(slot,item,ped)
 local personal=ped and personalForPed(ped) or nil
 return (ped==PlayerPedId() and preview and preview.scope=='items' and preview.key==item and preview.data)
 or (ped==PlayerPedId() and preview and preview.scope=='slots' and preview.key==slot and preview.data)
 or (personal and personal.items and personal.items[item])
 or (personal and personal.slots and personal.slots[slot])
 or globalOverrides.items[item] or globalOverrides.slots[slot] or Carry.Slots[slot]
end
RegisterNetEvent('alpha_z_weaponcarry:positions',function(data)
 globalOverrides=type(data)=='table' and data or {slots={},items={}}
 overrides=mergeLocalPositions()
 if editorOpen then SendNUIMessage({action='positions',overrides=overrides}) end
 for key,obj in pairs(objects) do if DoesEntityExist(obj.entity) then DeleteEntity(obj.entity) end;objects[key]=nil end
end)
RegisterNetEvent('alpha_z_weaponcarry:notice',function(msg)
 TriggerEvent('chat:addMessage',{args={'Weapon Carry',msg}})
end)
RegisterNetEvent('alpha_z_weaponcarry:editorResult',function(result)
 if editorOpen and type(result)=='table' then
  result.action='editorResult'
  SendNUIMessage(result)
 end
end)
-- Show only bone IDs which actually exist on this player's ped skeleton.
local function availableBones(ped)
 local result={}
 if ped==0 or not DoesEntityExist(ped) then return result end
 for _,entry in ipairs(Carry.Bones or {}) do
  if GetPedBoneIndex(ped,entry.id)~=-1 then
   result[#result+1]={id=entry.id,label=entry.label}
  end
 end
 return result
end
RegisterNetEvent('alpha_z_weaponcarry:openEditor',function(data,canGlobal)
 editorGlobal=canGlobal==true
 overrides=type(data)=='table' and data or {slots={},items={}}
 local firstSlot='rifle'
 local serverId=GetPlayerServerId(PlayerId())
 local prefix=tostring(serverId)..':'
 local carried=Player(serverId).state.alphaZCarry
 local _,held=GetCurrentPedWeapon(PlayerPedId(),true)
 for _,slot in ipairs({'rifle','melee','left','right'}) do
  local obj=objects[prefix..slot]
  if obj and obj.ped==PlayerPedId() and DoesEntityExist(obj.entity) then
   firstSlot=slot
   break
  elseif type(carried)=='table' and carried[slot] and Carry.Items[carried[slot]] and
   GetHashKey(Carry.Items[carried[slot]][1])~=held then
   -- The prop may not have been spawned yet by the 250 ms refresh loop.
   firstSlot=slot
   break
  end
 end
 cameraSelection=nil
 setCameraSelection('slots',firstSlot)
 editorOpen=true;startEditorCamera();SetNuiFocus(true,true)
 SendNUIMessage({action='open',slots=Carry.Slots,items=Carry.Items,overrides=overrides,bones=availableBones(PlayerPedId()),initialSlot=firstSlot,canGlobal=editorGlobal})
end)
RegisterNUICallback('close',function(_,cb) editorOpen=false;gizmoActive=false;gizmoSelection=nil;preview=nil;stopEditorCamera();SetNuiFocus(false,false);cb({ok=true}) end)
-- Camera focus follows the weapon selected in the editor, including when
-- the user switches slots or selects a different item from the list.
RegisterNUICallback('cameraTarget',function(data,cb)
 if editorOpen and type(data)=='table' then
  setCameraSelection(data.scope,data.key)
  updateEditorCamera()
 end
 cb({ok=true,weapon=selectedCameraObject()~=nil})
end)
RegisterNUICallback('preview',function(data,cb)
 if editorOpen and type(data)=='table' and type(data.data)=='table' then
  local bone=tonumber(data.data.bone)
  local exists=false
  for _,entry in ipairs(Carry.Bones or {}) do
   if entry.id==bone and GetPedBoneIndex(PlayerPedId(),bone)~=-1 then exists=true;break end
  end
  if exists then
   preview=data
   if refreshPreview then refreshPreview() end
  end
 end
 cb({ok=true})
end)
RegisterNUICallback('save',function(data,cb)
 if data and data.scope and data.key and data.data then TriggerServerEvent('alpha_z_weaponcarry:savePosition',data.scope,data.key,data.data) end
 cb({ok=true})
end)
RegisterNUICallback('reset',function(data,cb)
 if data and data.scope and data.key then TriggerServerEvent('alpha_z_weaponcarry:resetPosition',data.scope,data.key) end
 preview=nil;cb({ok=true})
end)
CreateThread(function() Wait(1500);TriggerServerEvent('alpha_z_weaponcarry:getPositions') end)

local unarmed=GetHashKey('WEAPON_UNARMED')
local lastHash=unarmed
local hashItems={}
for item,def in pairs(Carry.Items) do
 local hash=GetHashKey(def[1]);hashItems[hash]=hashItems[hash] or {};table.insert(hashItems[hash],item)
end
local function removeObject(key)
 local o=objects[key]
 if o then
  if DoesEntityExist(o.entity) then DeleteEntity(o.entity) end
  objects[key]=nil
 end
end
local function clearAll()
 for key in pairs(objects) do removeObject(key) end
end
local function modelFor(item)
 local def=Carry.Items[item];if not def then return nil end
 local model=Carry.Models[item] or GetWeapontypeModel(GetHashKey(def[1]))
 -- Streamed model names are resolved to native hashes for IsModelInCdimage.
 if type(model)=='string' then return GetHashKey(model) end
 return model
end
local function boneIndexFor(ped,config,slot)
 local bone=config and tonumber(config.bone)
 if bone then
  local index=GetPedBoneIndex(ped,bone)
  if index and index~=-1 then return index end
 end
 local fallback=Carry.Slots[slot] and Carry.Slots[slot].bone
 if fallback then
  local index=GetPedBoneIndex(ped,fallback)
  if index and index~=-1 then return index end
 end
 return nil
end
-- FiveM's ATTACH_ENTITY_TO_ENTITY native takes float parameters for offsets
-- AND rotations. Lua 5.4 distinguishes integers from floats, and JSON/NUI may
-- decode whole-degree rotations (e.g. 90) as integers. Force native floats.
local function nativeFloat(value)
 return (tonumber(value) or 0.0) + 0.0
end
local function placeOnPed(entity,ped,slot,config)
 local index=boneIndexFor(ped,config,slot)
 if not index or not config or type(config.pos)~='table' or type(config.rot)~='table' then return false end
 -- Calling ATTACH_ENTITY_TO_ENTITY again updates its relative transform.
 -- Do NOT detach first: that introduces an unnecessary frame of free movement.
 AttachEntityToEntity(entity,ped,index,
  nativeFloat(config.pos[1]),nativeFloat(config.pos[2]),nativeFloat(config.pos[3]),
  nativeFloat(config.rot[1]),nativeFloat(config.rot[2]),nativeFloat(config.rot[3]),
  false,false,false,true,2,true)
 return true
end
local function attach(key,ped,item,slot,registry)
 registry=registry or objects
 local config=getPlacement(slot,item,ped);local model=modelFor(item)
 if not model or model==0 or not IsModelInCdimage(model) then return end
 RequestModel(model)
 local untilTime=GetGameTimer()+700
 while not HasModelLoaded(model) and GetGameTimer()<untilTime do Wait(0) end
 if not HasModelLoaded(model) then return end
 local obj=CreateObjectNoOffset(model,GetEntityCoords(ped),false,false,false)
 if obj==0 then SetModelAsNoLongerNeeded(model);return end
 SetEntityCollision(obj,false,false)
 SetEntityInvincible(obj,true)
 if not placeOnPed(obj,ped,slot,config) then
  DeleteEntity(obj)
  SetModelAsNoLongerNeeded(model)
  return
 end
 registry[key]={entity=obj,ped=ped,item=item,slot=slot,placement=json.encode(config)}
 SetModelAsNoLongerNeeded(model)
end
-- Always clean props before switching selected characters or leaving the screen.
local function clearPreviewCarry()
 previewRevision=previewRevision+1
 for key,obj in pairs(previewObjects) do
  if DoesEntityExist(obj.entity) then DeleteEntity(obj.entity) end
  previewObjects[key]=nil
 end
 previewObjects={}
end
exports('ClearPreviewPedWeapons',clearPreviewCarry)

-- Receives ONLY verified, saved hotbar item names from bs_multichar.
-- Spawns props directly on the preview ped, which is NOT a player ped.
exports('SetPreviewPedWeapons',function(ped,items)
 clearPreviewCarry()
 if type(ped)~='number' or ped==0 or not DoesEntityExist(ped) or type(items)~='table' then return false end
 local revision=previewRevision
 local registry=previewObjects
 -- Stable ordering: same slot assignment on every visit, independent of Lua pairs().
 local list={}
 for _,item in ipairs(items) do
  if type(item)=='string' and Carry.Items[item] then list[#list+1]=item end
 end
 table.sort(list)
 local chosen={}
 for _,item in ipairs(list) do
  local preferred=Carry.Items[item][2]
  local target=preferred
  if chosen[target] and (target=='left' or target=='right') then
   target=(target=='left') and 'right' or 'left'
  end
  if target and Carry.Slots[target] and not chosen[target] then chosen[target]=item end
 end
 CreateThread(function()
  for _,slot in ipairs({'rifle','melee','left','right'}) do
   if revision~=previewRevision or not DoesEntityExist(ped) then break end
   local item=chosen[slot]
   if item then
    attach('__preview:'..slot,ped,item,slot,registry)
    if revision~=previewRevision or not DoesEntityExist(ped) then break end
   end
  end
  -- An older model load may complete after the selected character changed.
  -- Delete only the old registry; never delete the newer preview's props.
  if revision~=previewRevision or not DoesEntityExist(ped) then
   for _,obj in pairs(registry) do
    if DoesEntityExist(obj.entity) then DeleteEntity(obj.entity) end
   end
  end
 end)
 return true
end)

local function update()
 local me=PlayerPedId();local myPos=GetEntityCoords(me)
 local wanted={}
 for _,player in ipairs(GetActivePlayers()) do
  local ped=GetPlayerPed(player)
  if ped~=0 and DoesEntityExist(ped) and not IsEntityDead(ped) and #(myPos-GetEntityCoords(ped))<Carry.Range then
   local state=Player(GetPlayerServerId(player)).state.alphaZCarry
   if type(state)=='table' then
    local _,held=GetCurrentPedWeapon(ped,true)
    -- Hide only ONE matching slot for the drawn weapon. A second knife
    -- with the same GTA hash remains on the other belt position.
    local heldSlot=nil
    if held and held~=GetHashKey('WEAPON_UNARMED') then
     for _,candidate in ipairs({'right','left','melee','rifle'}) do
      local item=state[candidate]
      local def=item and Carry.Items[item]
      if def and held==GetHashKey(def[1]) then heldSlot=candidate;break end
     end
    end
    for slot,item in pairs(state) do
     local def=Carry.Items[item]
     if def and Carry.Slots[slot] and slot~=heldSlot then
      local key=tostring(GetPlayerServerId(player))..':'..slot
      wanted[key]={ped=ped,item=item,slot=slot}
     end
    end
   end
  end
 end
 for key,obj in pairs(objects) do
  local w=wanted[key]
  if not w or obj.ped~=w.ped or obj.item~=w.item or not DoesEntityExist(obj.entity) then removeObject(key) end
 end
 for key,w in pairs(wanted) do if not objects[key] then attach(key,w.ped,w.item,w.slot) end end
 for key,obj in pairs(objects) do
  local config=getPlacement(obj.slot,obj.item,obj.ped)
  if config and DoesEntityExist(obj.entity) and DoesEntityExist(obj.ped) then
   -- Reapply the attachment only if its relative transform changed.
   -- Reattaching directly is supported; detaching first is not required.
   local signature=json.encode(config)
   if signature~=obj.placement then
    if placeOnPed(obj.entity,obj.ped,obj.slot,config) then
     obj.placement=signature
    else removeObject(key) end
   end
  end
 end
 -- Reposition preview props if the admin modifies saved carry positions.
 -- The selection ped is not in GetActivePlayers(), so it needs its own pass.
 for key,obj in pairs(previewObjects) do
  if not DoesEntityExist(obj.entity) or not DoesEntityExist(obj.ped) then
   if DoesEntityExist(obj.entity) then DeleteEntity(obj.entity) end
   previewObjects[key]=nil
  else
   local config=getPlacement(obj.slot,obj.item,obj.ped)
   if config then
    local signature=json.encode(config)
    if signature~=obj.placement then
     if placeOnPed(obj.entity,obj.ped,obj.slot,config) then
      obj.placement=signature
     end
    end
   end
  end
 end
end
CreateThread(function()
 while true do
  Wait(250)
  local ped=PlayerPedId()
  if ped~=0 and not IsEntityDead(ped) then
   local _,hash=GetCurrentPedWeapon(ped,true)
   if hash~=lastHash then
    lastHash=hash
    local candidates=hashItems[hash]
    if candidates then
     -- Verify via server inventory: server rejects items the player does not own.
     for _,item in ipairs(candidates) do TriggerServerEvent('alpha_z_weaponcarry:used',item) end
    end
   end
  end
 end
end)
refreshPreview=update

-- V1.6: mouse-operated, screen-projected 3D transform gizmo.
-- The position axes and rotation rings are anchored in the SAME ped-bone
-- coordinate system as AttachEntityToEntity. No external gizmo resource.
local axisVectors={
 x={1.0,0.0,0.0},
 y={0.0,1.0,0.0},
 z={0.0,0.0,1.0},
}
local function ownGizmoObject()
 if not gizmoSelection then return nil end
 local slot=gizmoSelection.scope=='slots' and gizmoSelection.key or
  (Carry.Items[gizmoSelection.key] and Carry.Items[gizmoSelection.key][2])
 if not slot then return nil end
 local key=tostring(GetPlayerServerId(PlayerId()))..':'..slot
 local obj=objects[key]
 if obj and obj.ped==PlayerPedId() and DoesEntityExist(obj.entity) and
  (gizmoSelection.scope=='slots' or obj.item==gizmoSelection.key) then return obj end
 return nil
end
local function isAllowedGizmoBone(bone)
 local ped=PlayerPedId()
 if not bone or ped==0 or GetPedBoneIndex(ped,bone)==-1 then return false end
 for _,entry in ipairs(Carry.Bones or {}) do
  if entry.id==bone then return true end
 end
 return false
end
RegisterNUICallback('gizmoStart',function(data,cb)
 if not editorOpen or type(data)~='table' then cb({ok=false,message='Editor nicht geöffnet.'});return end
 local scope,key=data.scope,data.key
 if (scope~='slots' and scope~='items') or type(key)~='string' or
  (scope=='slots' and not Carry.Slots[key]) or (scope=='items' and not Carry.Items[key]) then
  cb({ok=false,message='Ungültige Auswahl.'});return
 end
 local config=data.data
 if type(config)~='table' or type(config.pos)~='table' or type(config.rot)~='table' then
  cb({ok=false,message='Ungültige Position oder Rotation.'});return
 end
 for i=1,3 do
  local p,r=tonumber(config.pos[i]),tonumber(config.rot[i])
  if not p or not r or p~=p or r~=r or math.abs(p)>2.0 or math.abs(r)>360.0 then
   cb({ok=false,message='Ungültige Position oder Rotation.'});return
  end
 end
 local bone=tonumber(config.bone)
 if not isAllowedGizmoBone(bone) then cb({ok=false,message='Knochen ist am Charakter nicht vorhanden.'});return end
 setCameraSelection(scope,key)
 gizmoSelection={scope=scope,key=key}
 -- Use the unsaved values from the editor as the initial gizmo transform.
 preview={scope=scope,key=key,data=data.data}
 if refreshPreview then refreshPreview() end
 if not ownGizmoObject() then
  gizmoSelection=nil
  cb({ok=false,message='Keine passende Waffe sichtbar. Waffe in die Hotbar legen und wegstecken.'})
  return
 end
 gizmoActive=true
 cb({ok=true})
end)
RegisterNUICallback('gizmoStop',function(_,cb)
 gizmoActive=false
 gizmoSelection=nil
 cb({ok=true})
end)
-- ALT camera controls are available in both the editor and gizmo.
RegisterNUICallback('cameraOrbit',function(data,cb)
 if editorOpen and type(data)=='table' then orbitEditorCamera(data.dx,data.dy) end
 cb({ok=true})
end)
RegisterNUICallback('cameraZoom',function(data,cb)
 if editorOpen and type(data)=='table' then zoomEditorCamera(data.delta) end
 cb({ok=true,distance=cameraDistance})
end)
-- Retain the V1.6 right-mouse camera gesture in gizmo mode.
RegisterNUICallback('gizmoOrbit',function(data,cb)
 if editorOpen and gizmoActive and type(data)=='table' then orbitEditorCamera(data.dx,data.dy) end
 cb({ok=true})
end)
local function bonePoint(ped,bone,pos)
 return GetPedBoneCoords(ped,bone,nativeFloat(pos[1]),nativeFloat(pos[2]),nativeFloat(pos[3]))
end
local function screenPoint(world)
 local visible,x,y=GetScreenCoordFromWorldCoord(world.x,world.y,world.z)
 if not visible then return false end
 return {x=x,y=y}
end
local function gizmoFrame(obj)
 local config=getPlacement(obj.slot,obj.item,obj.ped)
 if not config or not isAllowedGizmoBone(tonumber(config.bone)) or
  type(config.pos)~='table' or type(config.rot)~='table' then return nil end
 local ped=obj.ped
 local bone=tonumber(config.bone)
 local center=bonePoint(ped,bone,config.pos)
 local projectedCenter=screenPoint(center)
 if not projectedCenter then return nil end
 local cam=(editorCam and DoesCamExist(editorCam)) and GetCamCoord(editorCam) or GetGameplayCamCoord()
 local distance=#(cam-center)
 -- Scale handles with camera distance so the on-screen gizmo remains usable.
 local length=math.max(0.20,math.min(0.65,distance*0.13))
 local radius=length*0.80
 local axes={}
 local rings={}
 for name,v in pairs(axisVectors) do
  local endPos={config.pos[1]+v[1]*length,config.pos[2]+v[2]*length,config.pos[3]+v[3]*length}
  axes[name]=screenPoint(bonePoint(ped,bone,endPos))
  local points={}
  for i=0,36 do
   local t=i*math.pi*2.0/36.0
   local c,s=math.cos(t)*radius,math.sin(t)*radius
   local p
   if name=='x' then p={config.pos[1],config.pos[2]+c,config.pos[3]+s}
   elseif name=='y' then p={config.pos[1]+c,config.pos[2],config.pos[3]+s}
   else p={config.pos[1]+c,config.pos[2]+s,config.pos[3]} end
   points[#points+1]=screenPoint(bonePoint(ped,bone,p))
  end
  rings[name]=points
 end
 return {center=projectedCenter,axes=axes,rings=rings,length=length,
  slot=obj.slot,item=obj.item,position=config.pos,rotation=config.rot}
end
CreateThread(function()
 while true do
  if not gizmoActive then Wait(350)
  else
   Wait(33)
   if not editorOpen then gizmoActive=false;gizmoSelection=nil
   else
    local obj=ownGizmoObject()
    -- The 250 ms inventory update can replace the prop after a hotbar change.
    if not obj and refreshPreview then refreshPreview();obj=ownGizmoObject() end
    if not obj then
     gizmoActive=false;gizmoSelection=nil
     SendNUIMessage({action='gizmoLost',message='Die Waffe ist nicht mehr am Körper sichtbar.'})
    else
     local frame=gizmoFrame(obj)
     if frame then SendNUIMessage({action='gizmoFrame',frame=frame})
     else SendNUIMessage({action='gizmoFrame',frame=false}) end
    end
   end
  end
 end
end)
-- Track the selected weapon every frame while the editor is open (including gizmo movement).
CreateThread(function()
 while true do
  if editorOpen then
   Wait(50)
   updateEditorCamera()
  else Wait(350) end
 end
end)
-- Admin-only-on-open F8 diagnostics for a still-not-rotating prop.
local function rotationDiagnostics()
 local myId=tostring(GetPlayerServerId(PlayerId()))..':'
 local count=0
 for objectKey,obj in pairs(objects) do
  if objectKey:sub(1,#myId)==myId and DoesEntityExist(obj.entity) then
   count=count+1
   local config=getPlacement(obj.slot,obj.item,obj.ped)
   local world=GetEntityRotation(obj.entity,2)
   local attached=GetEntityAttachedTo(obj.entity)==obj.ped
   print(('[Alpha-Z WeaponCarry ROT DEBUG] slot=%s item=%s attached=%s bone=%s requested=(%.1f, %.1f, %.1f) world=(%.1f, %.1f, %.1f)'):format(
    obj.slot,obj.item,tostring(attached),tostring(config.bone),
    nativeFloat(config.rot[1]),nativeFloat(config.rot[2]),nativeFloat(config.rot[3]),
    world.x,world.y,world.z))
  end
 end
 if count==0 then print('[Alpha-Z WeaponCarry ROT DEBUG] Keine sichtbare Hotbar-Waffe am eigenen Charakter gefunden.') end
 return count
end
RegisterCommand('weaponcarryrotdebug',function()
 if editorOpen then rotationDiagnostics() end
end,false)
RegisterNUICallback('rotationDebug',function(_,cb)
 if not editorOpen then cb({ok=false});return end
 cb({ok=true,count=rotationDiagnostics()})
end)
CreateThread(function()
 while true do Wait(editorOpen and 100 or Carry.RefreshMs);update() end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then gizmoActive=false;stopEditorCamera();clearAll();clearPreviewCarry();SetNuiFocus(false,false) end end)
