local objects,preview={},nil
local nextToken=0
local function discardPart(part)
    part.cancelled=true
    if part.object and DoesEntityExist(part.object)then DeleteEntity(part.object)end
end
local function remove(player)
    local record=objects[player]
    if record then for _,part in pairs(record.parts)do discardPart(part)end end
    objects[player]=nil
end
local function parentFor(ped,weapon)
    if ped==PlayerPedId()and Weapons.InspectionObject then
        local studio=Weapons.InspectionObject()
        if studio then return studio,true end
    end
    if not DoesEntityExist(ped)or IsEntityDead(ped)or GetSelectedPedWeapon(ped)~=GetHashKey(weapon)then return nil end
    local parent=GetCurrentPedWeaponEntityIndex(ped,0)
    if parent and parent~=0 and DoesEntityExist(parent)then return parent,false end
end
local function normalise(data)
    if type(data)~='table'or type(data.weapon)~='string'or not Weapons.Cosmetics.weapons[data.weapon]then return nil end
    local manual,functional={},{}
    for _,mount in ipairs(data.mounts or (data.id and {data})or {})do
        if mount.functional then
            if not Weapons.Attachments[mount.id]then return nil end
            functional[#functional+1]=mount
        elseif Weapons.Cosmetics.enabled then manual[#manual+1]=mount end
    end
    local clean=Weapons.ValidCosmeticMounts(manual,12)
    local derived=Weapons.ValidCosmeticMounts(functional,6)
    if not clean or not derived then return nil end
    for _,mount in ipairs(clean)do mount.key='cosmetic:'..(mount.key or tostring(_))end
    for _,mount in ipairs(derived)do clean[#clean+1]=mount end
    return clean
end
local function attach(part,parent)
    if not part.object or not DoesEntityExist(part.object)then return end
    local p,r=part.transform.position,part.transform.rotation
    local scale=part.transform.scale or 1
    local previous=part.applied
    local changed=not previous or previous.parent~=parent or previous.x~=p.x or previous.y~=p.y or previous.z~=p.z
        or previous.rx~=r.x or previous.ry~=r.y or previous.rz~=r.z or previous.scale~=scale
    if changed then
        local bone=-1
        if part.transform.key and part.transform.key:sub(1,7)=='native:'and part.definition.mountBone then bone=GetEntityBoneIndexByName(parent,part.definition.mountBone)end
        AttachEntityToEntity(part.object,parent,bone,p.x,p.y,p.z,r.x,r.y,r.z,false,false,false,true,2,true)
        part.applied={parent=parent,x=p.x,y=p.y,z=p.z,rx=r.x,ry=r.y,rz=r.z,scale=scale}
    end
    if Weapons.ApplyCosmeticScale and (changed or math.abs(scale*(part.definition.baseScale or 1)-1)>.00001)then
        Weapons.ApplyCosmeticScale(part.object,scale,part.definition.baseScale or 1)
    end
end
local function spawnPart(record,key,transform,definition)
    nextToken=nextToken+1
    local part={token=nextToken,definition=definition,transform=transform,loading=true}
    record.parts[key]=part
    CreateThread(function()
        local model=definition.model and GetHashKey(definition.model)or GetWeapontypeModel(GetHashKey(definition.weaponModel))
        local deadline=GetGameTimer()+1800
        if model and model~=0 and IsModelInCdimage(model)and IsModelValid(model)then
            RequestModel(model)
            while not part.cancelled and not HasModelLoaded(model)and GetGameTimer()<deadline do Wait(25)end
            if not part.cancelled and HasModelLoaded(model)and DoesEntityExist(record.parent)and record.parts[key]==part then
                local at=GetEntityCoords(record.parent)
                local object=CreateObject(model,at.x,at.y,at.z,false,false,false)
                if object and object~=0 then
                    part.object=object
                    SetEntityAsMissionEntity(object,true,true)
                    Entity(object).state:set('bsProtected',true,false)
                    SetEntityCollision(object,false,false)
                    attach(part,record.parent)
                end
            end
            SetModelAsNoLongerNeeded(model)
        end
        part.loading=false;part.retryAt=GetGameTimer()+2000
    end)
end
local function previewWithFitted(player,data)
    if player~=PlayerId()or data~=preview then return data end
    local saved=Player(GetPlayerServerId(player)).state.bsWeaponCosmetic
    if not saved or saved.weapon~=data.weapon or saved.serial~=data.serial then return data end
    local merged={weapon=data.weapon,serial=data.serial,mounts={}}
    for _,mount in ipairs(data.mounts or (data.id and {data})or {})do merged.mounts[#merged.mounts+1]=mount end
    for _,mount in ipairs(saved.mounts or {})do if mount.functional then merged.mounts[#merged.mounts+1]=mount end end
    return merged
end
local function apply(player,ped,data)
    data=previewWithFitted(player,data)
    local mounts=normalise(data)
    local parent=mounts and parentFor(ped,data.weapon)
    if not parent then remove(player);return end
    local record=objects[player]
    if record and (record.parent~=parent or record.serial~=data.serial or record.weapon~=data.weapon)then remove(player);record=nil end
    if not record then record={ped=ped,parent=parent,serial=data.serial,weapon=data.weapon,parts={}};objects[player]=record end
    local present={}
    for index,transform in ipairs(mounts)do
        local key=transform.key or ('draft:'..index)
        local definition=Weapons.Cosmetics.parts[transform.id]
        present[key]=true
        local part=record.parts[key]
        if part and part.transform.id~=transform.id then discardPart(part);record.parts[key]=nil;part=nil end
        if part then
            part.transform=transform
            if part.object then attach(part,parent)end
            if not part.object and not part.loading and GetGameTimer()>=(part.retryAt or 0)then record.parts[key]=nil;part=nil end
        end
        if not part then spawnPart(record,key,transform,definition)end
    end
    for key,part in pairs(record.parts)do if not present[key]then discardPart(part);record.parts[key]=nil end end
end
function Weapons.PreviewCosmetic(data)
    if data==nil then preview=nil;remove(PlayerId());return true end
    if not Weapons.Cosmetics.enabled or not normalise(data)then return false end
    if not (Weapons.InspectionObject and Weapons.InspectionObject())and Weapons.HeldWeapon()~=data.weapon then return false end
    preview=data
    apply(PlayerId(),PlayerPedId(),preview)
    return true
end
CreateThread(function()
    while true do
        Wait(250)
        local candidates={}
        if Weapons.Cosmetics.enabled or Weapons.CustomAttachments then
            local origin=GetEntityCoords(PlayerPedId())
            for _,player in ipairs(GetActivePlayers())do
                local ped=GetPlayerPed(player)
                local data=player==PlayerId()and preview or Player(GetPlayerServerId(player)).state.bsWeaponCosmetic
                if data and ped~=0 and DoesEntityExist(ped)then
                    local p=GetEntityCoords(ped);local dx,dy,dz=p.x-origin.x,p.y-origin.y,p.z-origin.z
                    local distance=dx*dx+dy*dy+dz*dz
                    if player==PlayerId()or distance<=math.min(30,Weapons.Cosmetics.drawDistance or 18)^2 then
                        candidates[#candidates+1]={player=player,ped=ped,data=data,distance=player==PlayerId()and -1 or distance}
                    end
                end
            end
        end
        table.sort(candidates,function(a,b)return a.distance<b.distance end)
        local selected={}
        for index,candidate in ipairs(candidates)do
            if index>math.max(1,math.min(12,Weapons.Cosmetics.maxVisiblePlayers or 6))then break end
            selected[candidate.player]=true;apply(candidate.player,candidate.ped,candidate.data)
        end
        for player in pairs(objects)do if not selected[player]then remove(player)end end
    end
end)
CreateThread(function()
    while true do
        local count=0
        for player,record in pairs(objects)do
            local parent=parentFor(record.ped,record.weapon)
            if parent~=record.parent then remove(player)
            else
                for _,part in pairs(record.parts)do
                    if part.object then attach(part,parent);count=count+1 end
                end
            end
        end
        Wait(count>0 and 0 or 150)
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName()then preview=nil;for player in pairs(objects)do remove(player)end end
end)
