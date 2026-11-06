local busy={}
local function catalogue()
    local out={}
    for id,part in pairs(Weapons.Cosmetics.parts)do out[id]={item=part.item}end
    return out
end
local function publicMounts(meta)
    local out={}
    for _,mount in ipairs(Weapons.CosmeticMounts(meta))do
        local transform=Weapons.ValidCosmeticTransform(mount)
        if transform and Weapons.Cosmetics.parts[mount.id]then
            transform.id,transform.key=mount.id,mount.key or mount.mountKey
            out[#out+1]=transform
        end
    end
    return out
end
function Weapons.PublishCosmetic(src,weapon,meta)
    local mounts=Weapons.Cosmetics.enabled and meta and publicMounts(meta)or {}
    for _,mount in ipairs(Weapons.CustomFunctionalMounts and Weapons.CustomFunctionalMounts(meta)or {})do mounts[#mounts+1]=mount end
    Player(src).state:set('bsWeaponCosmetic',#mounts>0 and {weapon=weapon,serial=meta.serial,mounts=mounts}or nil,true)
end
BSB.RegisterCallback('weapons:cosmeticState',function(src,weapon)
    if type(weapon)~='string'or #weapon>48 then return {ok=false}end
    if not Weapons.Cosmetics.weapons[weapon]then return {ok=true,enabled=false}end
    local slot,_,meta=Weapons.Instance(src,weapon)
    if not slot then return {ok=false,error='Weapon is no longer in your inventory.'}end
    local mounts=publicMounts(meta)
    if not Weapons.Cosmetics.enabled and #mounts==0 then return {ok=true,enabled=false}end
    local options={}
    for id,part in pairs(Weapons.Cosmetics.parts)do
        options[#options+1]={id=id,label=part.label,item=part.item,count=exports.bs_inventory:CountItem(src,part.item),
            position=part.position,rotation=part.rotation,scale=1}
    end
    table.sort(options,function(a,b)return a.label<b.label end)
    local limits=Weapons.CosmeticLimits()
    return {ok=true,enabled=true,removeOnly=not Weapons.Cosmetics.enabled,serial=meta.serial,mount=mounts[1],mounts=mounts,
        options=options,maxMounts=limits.maxMounts,minScale=limits.minScale,maxScale=limits.maxScale,maxOffset=limits.maxOffset}
end)
local function held(src,weapon,expectedSerial)
    if type(weapon)~='string'or #weapon>48 then return nil,'Invalid weapon.'end
    local slot,_,meta=Weapons.Instance(src,weapon)
    if not slot or meta.serial~=expectedSerial then return nil,'The selected weapon has changed.'end
    local ped=GetPlayerPed(src)
    if ped==0 or GetEntityHealth(ped)<=0 or GetSelectedPedWeapon(ped)~=GetHashKey(weapon)then return nil,'Hold the selected weapon before saving.'end
    return slot,meta
end
BSB.RegisterCallback('weapons:cosmeticSave',function(src,weapon,expectedSerial,id,mode,data)
    if not Weapons.Cosmetics.enabled and mode~='remove'then return {ok=false,error='Cosmetic mounts are disabled.'}end
    if busy[src]or type(id)~='string'or (mode~='fit'and mode~='update'and mode~='remove')then return {ok=false}end
    local part=Weapons.Cosmetics.parts[id]
    if not part or not Weapons.Cosmetics.weapons[weapon]then return {ok=false,error='Unknown cosmetic mount.'}end
    local transform=mode~='remove'and Weapons.ValidCosmeticTransform(data)or {}
    if not transform then return {ok=false,error='Mount transform is outside the configured limits.'}end
    if type(data)=='table'then transform.key=data.key or data.mountKey end
    local slot,meta=held(src,weapon,expectedSerial)
    if not slot then return {ok=false,error=meta}end
    local limits=Weapons.CosmeticLimits();limits.catalogue=catalogue()
    busy[src]=true
    local ok,result=pcall(function()return exports.bs_inventory:WeaponCosmetic(src,slot,expectedSerial,id,part.item,mode,transform,limits)end)
    busy[src]=nil
    if not ok then print('[bs_weapons] cosmetic save failed: '..tostring(result));return {ok=false,error='Could not save the cosmetic piece.'}end
    if result and result.ok then Weapons.PublishCosmetic(src,weapon,result.metadata)end
    return result or {ok=false}
end)
local function sameTransform(a,b)
    if a.id~=b.id or (a.scale or 1)~=(b.scale or 1)then return false end
    for _,kind in ipairs({'position','rotation'})do for _,axis in ipairs({'x','y','z'})do if not a[kind]or not b[kind]or a[kind][axis]~=b[kind][axis]then return false end end end
    return true
end
BSB.RegisterCallback('weapons:workshopSave',function(src,weapon,expectedSerial,data)
    if Weapons.Settings.editorEnabled==false then return {ok=false,error='The weapon cosmetic editor is disabled.'}end
    if Weapons.RefreshStickerCatalogue then Weapons.RefreshStickerCatalogue()end
    if busy[src]or type(data)~='table'then return {ok=false,error='Workshop is busy.'}end
    local slot,meta=held(src,weapon,expectedSerial)
    if not slot then return {ok=false,error=meta}end
    local current=publicMounts(meta)
    local proposed=data.mounts
    if proposed==nil then proposed=current end
    local limits=Weapons.CosmeticLimits()
    limits.stickerDesigns=Weapons.StickerDesignRules and Weapons.StickerDesignRules().designs or nil
    local mounts=Weapons.ValidCosmeticMounts(proposed,math.max(limits.maxMounts,#current))
    if not mounts then return {ok=false,error='A cosmetic piece is outside the configured limits.'}end
    if #mounts>0 and not Weapons.Cosmetics.weapons[weapon]then return {ok=false,error='Cosmetic mounts are not configured for this weapon.'}end
    if not Weapons.Cosmetics.enabled then
        local old={};for _,m in ipairs(current)do old[m.key]=m end
        for _,m in ipairs(mounts)do if not old[m.key]or not sameTransform(m,old[m.key])then return {ok=false,error='Cosmetic mounts are disabled; existing pieces can only be kept or removed.'}end end
    end
    local entries=data.entries
    if entries~=nil then
        entries=Weapons.ValidStickers(weapon,entries)
        if not entries then return {ok=false,error='A sticker is outside its supported surface.'}end
        if not Weapons.Stickers.enabled and #entries>0 then
            local old=Weapons.ValidStickers(weapon,meta.weaponStickers or {})or {}
            if json.encode(entries)~=json.encode(old)then return {ok=false,error='Stickers are disabled; existing stickers can only be kept or cleared.'}end
        end
    end
    local profile
    if data.name~=nil or data.tint~=nil then
        profile={name=data.name or meta.customName or '',tint=data.tint==nil and (meta.tint or 0)or data.tint}
    end
    busy[src]=true
    local ok,result=pcall(function()return exports.bs_inventory:WeaponWorkshop(src,slot,expectedSerial,profile,mounts,entries,limits,catalogue())end)
    busy[src]=nil
    if not ok then print('[bs_weapons] workshop save failed: '..tostring(result));return {ok=false,error='Could not save the workshop changes.'}end
    if result and result.ok then
        Weapons.PublishCosmetic(src,weapon,result.metadata)
        if Weapons.PublishStickers then Weapons.PublishStickers(src,weapon,result.metadata)end
    end
    return result or {ok=false}
end)
AddEventHandler('playerDropped',function()busy[source]=nil end)
AddEventHandler('bs:hook:player:unloaded',function(player)
    if player and player.source then busy[player.source]=nil;Player(player.source).state:set('bsWeaponCosmetic',nil,true)end
end)
