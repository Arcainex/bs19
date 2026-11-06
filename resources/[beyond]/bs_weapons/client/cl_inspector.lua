local inspecting,applying=false,false
local inspectingWeapon,studioWeapon,serial
local cachedCosmetics,cachedStickers
local previousHudHidden=false
local generation=0

local function request(route,...)
    local ok,result=pcall(BSB.Await,route,12000,...)
    return ok and result or {ok=false,error='The server did not respond. Your draft has been kept.'}
end
local function close()
    if not inspecting then return end
    inspecting=false;generation=generation+1;applying=false
    Weapons.PreviewCosmetic(nil);Weapons.PreviewStickers(nil)
    if Weapons.PreviewPaint then Weapons.PreviewPaint(nil)end
    Weapons.CloseStudio()
    inspectingWeapon=nil;studioWeapon=nil;serial=nil
    cachedCosmetics=nil;cachedStickers=nil
    SetNuiFocus(false,false);SendNUIMessage({action='close'})
    TriggerEvent('bs:ui:closed','weaponWorkshop')
    if GetResourceState('bs_ui')=='started'then
        pcall(function()exports.bs_ui:Send({action='bsHideAll',hidden=previousHudHidden})end)
    end
end
local function refresh()
    if Weapons.Settings and Weapons.Settings.editorEnabled==false then close();return end
    local token=generation
    local weapon,hash=Weapons.HeldWeapon()
    if weapon~=inspectingWeapon then close();return end
    local state=request('weapons:state',weapon)
    local profile=request('weapons:profile',weapon)
    local cosmetics=request('weapons:cosmeticState',weapon)
    local stickers=request('weapons:stickerState',weapon)
    local paintState=Weapons.Paint and Weapons.Paint.enabled and request('weapons:paintState',weapon)or {ok=false}
    local paintParts=paintState.ok and paintState.enabled and Weapons.PaintParts and Weapons.PaintParts(weapon)or {}
    if not inspecting or token~=generation then return end
    if not state.ok or not profile.ok then
        TriggerEvent('bs:ui:notify',{type='warn',message=state.error or profile.error or 'Weapon data unavailable.'})
        close();return
    end
    if Weapons.StickerAtlas and stickers.designs then Weapons.StickerAtlas.Update(stickers.designs)end
    local tintOptions=Weapons.StudioTintOptions and Weapons.StudioTintOptions(weapon)or nil
    if tintOptions and (type(profile.tint)~='number'or profile.tint<0 or profile.tint>=#tintOptions)then profile.tint=0 end
    serial=profile.serial;cachedCosmetics=cosmetics;cachedStickers=stickers
    for _,option in ipairs(cosmetics.options or {})do
        local part=Weapons.Cosmetics.parts[option.id]
        if part then
            local model=part.model and GetHashKey(part.model)or GetWeapontypeModel(GetHashKey(part.weaponModel))
            option.available=model and model~=0 and IsModelInCdimage(model)and IsModelValid(model)or false
        end
    end
    if studioWeapon~=weapon or not Weapons.InspectionObject()then
        if not Weapons.OpenStudio(weapon,state.fitted,profile.tint)then
            TriggerEvent('bs:ui:notify',{type='warn',message='The weapon preview could not load. Please try again.'})
            close();return
        end
        if not inspecting or token~=generation then Weapons.CloseStudio();return end
        studioWeapon=weapon
    else Weapons.SetStudioTint(profile.tint,true)end
    SendNUIMessage({action='show',weapon=state.label or (Weapons.PrettyWeapon and Weapons.PrettyWeapon(weapon))or weapon,profile=profile,
        cosmetics=cosmetics,stickers=stickers,tintOptions=tintOptions,options={},ammo=GetAmmoInPedWeapon(PlayerPedId(),hash),
        magazine=GetWeaponClipSize(hash),damage=math.floor(GetWeaponDamage(hash,0)+.5),
        backdrops={list=Weapons.StudioBackdrops and Weapons.StudioBackdrops()or {},current=Weapons.StudioBackdropId and Weapons.StudioBackdropId()or nil},
        paint={enabled=paintState.ok==true and paintState.enabled==true,parts=paintParts,data=paintState.paint,
            maxStrokes=Weapons.Paint and Weapons.Paint.maxStrokes or 40,maxParts=Weapons.Paint and Weapons.Paint.maxParts or 4}})
    if Weapons.PreviewPaint and paintState.ok then Weapons.PreviewPaint(weapon,paintState.paint or false)end
end
local function open()
    if Weapons.Settings and Weapons.Settings.editorEnabled==false then
        TriggerEvent('bs:ui:notify',{type='warn',message='The weapon cosmetic editor is disabled.'})
        return
    end
    if inspecting or not Weapons.HeldWeapon()or IsPedInAnyVehicle(PlayerPedId(),false)then return end
    inspecting=true;generation=generation+1;inspectingWeapon=Weapons.HeldWeapon()
    previousHudHidden=false
    if GetResourceState('bs_ui')=='started'then
        pcall(function()previousHudHidden=exports.bs_ui:IsHudHidden()==true end)
    end
    TriggerEvent('bs:ui:opened','weaponWorkshop')
    if GetResourceState('bs_ui')=='started'then pcall(function()exports.bs_ui:Send({action='bsHideAll',hidden=true})end)end
    SetNuiFocus(true,true);refresh()
end
AddEventHandler('bs_config:changed:bs_weapons',function()
    if Weapons.Settings and Weapons.Settings.editorEnabled==false then close()end
end)
exports('OpenInspect',function()CreateThread(open)end)
RegisterNetEvent('bs:weapons:inspect',function()CreateThread(open)end)
RegisterCommand('inspectweapon',function()CreateThread(open)end,false)
local function callback(name,fn)
    RegisterNUICallback(name,function(data,cb)
        if Weapons.Settings and Weapons.Settings.editorEnabled==false then close();return cb({ok=false,error='The weapon cosmetic editor is disabled.'})end
        if not inspecting or type(data)~='table'then return cb({ok=false,error='Workshop is closed.'})end
        local ok,result=pcall(fn,data)
        cb(ok and result or {ok=false,error='Could not update the preview. Your draft has been kept.'})
    end)
end
local function owns(data,state)
    return state and state.ok and state.enabled and not state.removeOnly and data.serial==serial and data.serial==state.serial
end
local function finite(value)
    return type(value)=='number'and value==value and math.abs(value)<math.huge
end
callback('close',function()close();return {ok=true}end)
callback('previewCamera',function(data)
    local x,y,z=tonumber(data.dx)or 0,tonumber(data.dy)or 0,tonumber(data.zoom)or 0
    if not finite(x)or not finite(y)or not finite(z)then return {ok=false}end
    local ok=Weapons.AdjustStudio(math.max(-200,math.min(200,x)),math.max(-200,math.min(200,y)),math.max(-10,math.min(10,z)),data.reset==true)
    local gizmo=owns(data,cachedCosmetics)and Weapons.ValidCosmeticTransform(data.transform)and Weapons.StudioGizmo(data.transform,data.mode)or nil
    return {ok=ok,gizmo=gizmo}
end)
callback('previewFinish',function(data)
    local tint=tonumber(data.tint)
    if not tint or tint%1~=0 or tint<0 or tint>31 then return {ok=false}end
    local ok,reason=Weapons.SetStudioTint(tint,false)
    return {ok=ok,error=reason}
end)
callback('cosmeticPreview',function(data)
    if data.undo then Weapons.PreviewCosmetic(nil);return {ok=true}end
    if not owns(data,cachedCosmetics)then return {ok=false,error='Cosmetic editing is unavailable.'}end
    data.weapon=inspectingWeapon
    return {ok=Weapons.PreviewCosmetic(data)}
end)
callback('stickerPreview',function(data)
    if data.undo then Weapons.PreviewStickers(nil);return {ok=true}end
    if not owns(data,cachedStickers)then return {ok=false,error='Stickers are unavailable for this weapon.'}end
    return {ok=Weapons.PreviewStickers(data.entries,inspectingWeapon,serial)}
end)
callback('gizmoState',function(data)
    if not owns(data,cachedCosmetics)or not Weapons.ValidCosmeticTransform(data.transform)then return {ok=false}end
    local result=Weapons.StudioGizmo(data.transform,data.mode)
    if result then result.ok=true;return result end
    return {ok=false}
end)
callback('gizmoDrag',function(data)
    if not owns(data,cachedCosmetics)or not Weapons.ValidCosmeticTransform(data.transform)then return {ok=false}end
    if data.axis~='x'and data.axis~='y'and data.axis~='z'and data.axis~='xy'and data.axis~='xz'and data.axis~='yz'then return {ok=false}end
    if data.mode~='move'and data.mode~='rotate'and data.mode~='scale'then return {ok=false}end
    local dx,dy=tonumber(data.dx),tonumber(data.dy)
    if not finite(dx)or not finite(dy)then return {ok=false}end
    local transform=Weapons.GizmoDrag(data.transform,data.mode,data.axis,
        math.max(-8192,math.min(8192,dx)),math.max(-8192,math.min(8192,dy)),
        {height=math.max(320,math.min(4320,tonumber(data.height)or 1080)),snap=data.snap==true,fine=data.fine==true,x=finite(data.x)and data.x or nil,y=finite(data.y)and data.y or nil})
    if not transform then return {ok=false}end
    for _,part in ipairs(cachedCosmetics.options or {})do if part.id==data.transform.id then
        transform.scale=math.max(part.minScale or part.scaleMin or .5,math.min(part.maxScale or part.scaleMax or 1.5,transform.scale or 1))
    end end
    local valid=Weapons.ValidCosmeticTransform(transform)~=nil
    local previewed=false
    if valid and type(data.mounts)=='table'then
        for i,mount in ipairs(data.mounts)do
            if mount.key==data.transform.key and mount.id==data.transform.id then
                transform.key,transform.id=mount.key,mount.id;data.mounts[i]=transform
                previewed=Weapons.PreviewCosmetic({weapon=inspectingWeapon,serial=serial,mounts=data.mounts});break
            end
        end
    end
    return {ok=valid,transform=transform,previewed=previewed,gizmo=valid and Weapons.StudioGizmo(transform,data.mode)or nil}
end)
callback('cosmeticMuzzle',function(data)
    if not owns(data,cachedCosmetics)then return {ok=false}end
    local transform=Weapons.StudioMuzzle()
    return {ok=transform~=nil,transform=transform,error=not transform and 'No muzzle anchor is available.'or nil}
end)
callback('stickerPlace',function(data)
    if not owns(data,cachedStickers)then return {ok=false}end
    local entries=Weapons.ValidStickers(inspectingWeapon,data.entries)
    local index=tonumber(data.index);local entry=index and entries and entries[index]
    local x,y=tonumber(data.x),tonumber(data.y)
    if not entry or not finite(x)or not finite(y)or x<0 or x>1 or y<0 or y>1 then return {ok=false}end
    local plane,point,best
    for id,candidate in pairs(Weapons.Stickers.surfaces[inspectingWeapon])do
        candidate=Weapons.ResolveStickerPlane and Weapons.ResolveStickerPlane(candidate)or candidate
        if not Weapons.StudioSurfaceFacing or Weapons.StudioSurfaceFacing(candidate)then
            local hit=Weapons.StudioPlanePoint(x,y,candidate)
            if hit then
                -- Whole-weapon faces: the real extent of the model; hand planes: their own -1..1.
                local eu=candidate.extentU and candidate.extentU/candidate.halfWidth or 1
                local ev=candidate.extentV and candidate.extentV/candidate.halfHeight or 1
                local miss=(math.max(0,math.abs(hit.u)-eu)/eu)^2+(math.max(0,math.abs(hit.v)-ev)/ev)^2
                -- Inside two faces at once (an edge): the one facing the camera most wins.
                local facing=Weapons.StudioSurfaceFacingAmount and Weapons.StudioSurfaceFacingAmount(candidate)or 0
                local score=miss*10-facing
                if not best or score<best then best=score;plane=candidate;point=hit;point.miss=miss;point.eu=eu;point.ev=ev;entry.surface=id end
            end
        end
    end
    if not point or point.miss>1 then return {ok=false,error='Point at the weapon, or use Face surface for a closer view.'}end
    local angle=math.rad(entry.rotation)
    local extent=entry.size*.5*(math.abs(math.cos(angle))+math.abs(math.sin(angle)))
    local umax=math.max(0,point.eu-extent/plane.halfWidth)
    local vmax=math.max(0,point.ev-extent/plane.halfHeight)
    entry.u=math.max(-umax,math.min(umax,point.u));entry.v=math.max(-vmax,math.min(vmax,point.v))
    return {ok=Weapons.PreviewStickers(entries,inspectingWeapon,serial),entries=entries}
end)
callback('stickerFocus',function(data)
    if not owns(data,cachedStickers)then return {ok=false}end
    local plane=Weapons.Stickers.surfaces[inspectingWeapon]and Weapons.Stickers.surfaces[inspectingWeapon][data.surface]
    plane=Weapons.ResolveStickerPlane and Weapons.ResolveStickerPlane(plane)or plane
    return {ok=plane and Weapons.FaceStickerSurface(plane)or false}
end)
callback('applyWorkshop',function(data)
    if applying or data.serial~=serial then return {ok=false,error='The selected weapon has changed.'}end
    applying=true
    local token=generation
    local paintChanged,paint=data.paintChanged==true,data.paint
    data.paintChanged,data.paint=nil,nil
    local result=request('weapons:workshopSave',inspectingWeapon,serial,data)
    -- Paint is saved before the menu reloads, otherwise the reload brings back the previous paint job.
    if result.ok and paintChanged then
        local saved=request('weapons:paintSave',inspectingWeapon,serial,paint)
        if not saved.ok then result={ok=false,error=saved.error or 'The paint could not be saved.'}end
    end
    applying=false
    if result.ok and inspecting and generation==token then
        local tint=result.metadata and result.metadata.tint or data.tint
        if type(SetPedWeaponTintIndex)=='function'and type(tint)=='number'then SetPedWeaponTintIndex(PlayerPedId(),GetHashKey(inspectingWeapon),tint)end
        Weapons.PreviewCosmetic(nil);Weapons.PreviewStickers(nil);refresh()
    end
    return result
end)
callback('studioBackdrop',function(data)
    if type(data.id)~='string'or not Weapons.SetStudioBackdrop then return {ok=false}end
    return {ok=Weapons.SetStudioBackdrop(data.id),current=Weapons.StudioBackdropId()}
end)
callback('paintPreview',function(data)
    if data.serial~=serial or not Weapons.PreviewPaint then return {ok=false}end
    return {ok=Weapons.PreviewPaint(inspectingWeapon,data.paint or false)}
end)
callback('paintSave',function(data)
    if applying or data.serial~=serial then return {ok=false,error='The selected weapon has changed.'}end
    applying=true
    local result=request('weapons:paintSave',inspectingWeapon,serial,data.paint)
    applying=false
    return result
end)
callback('part',function()return {ok=false,error='Functional attachments belong to the O menu.'}end)
AddEventHandler('bs:ui:opened',function(name)if inspecting and name~='weaponWorkshop'then close()end end)
AddEventHandler('bs:weapons:studioClosed',close)
AddEventHandler('bs:hook:player:unloaded',close)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then close()end end)
CreateThread(function()
    while true do
        Wait(inspecting and 250 or 1000)
        if inspecting and (IsEntityDead(PlayerPedId())or IsPedInAnyVehicle(PlayerPedId(),false)
            or Weapons.HeldWeapon()~=inspectingWeapon)then close()end
    end
end)
