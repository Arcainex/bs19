-- O: functional attachments on the weapon in your hands, seen over a close shoulder camera.
-- Fit and remove go through the serial-bound server path in cl_main (weapons:fit / weapons:remove).
local view={open=false,run=0,busy=false}
local A=Weapons.AttachmentActions
-- Clip components change the loaded rounds, so the magazine mount never previews.
local NO_GHOST={mag=true}
local ghost

-- Fallback label from the id: WEAPON_ASSAULTRIFLE -> Assault Rifle (word breaks from the config's own known names).
function Weapons.PrettyWeapon(weapon)
    local out=tostring(weapon or ''):gsub('^WEAPON_',''):lower():gsub('_',' ')
    -- Longest first; placeholders stop "mg" matching again inside "smg".
    local words={{'shotgun','Shotgun'},{'carbine','Carbine'},{'pistol','Pistol'},{'sniper','Sniper'},{'rifle','Rifle'},
        {'mk2','Mk II'},{'smg','SMG'},{'pdw','PDW'},{'mg','MG'}}
    for i,w in ipairs(words)do out=out:gsub(w[1],' \1'..i..'\1 ')end
    out=out:gsub('(%a)(%a*)',function(a,b)return a:upper()..b end)
    out=out:gsub('\1(%d+)\1',function(i)return words[tonumber(i)][2]end)
    return (out:gsub('%s+',' '):gsub('^ ',''):gsub(' $',''))
end
local function send(action,data)SendNUIMessage({action='attachments:'..action,data=data})end
-- Sounds by event. 'gear' uses the game's own weapon-mod clicks (the gun shop attachment sounds); 'off' is silent.
-- Menu beeps (open, hover, error) are left out on purpose: they read as a phone UI, not a gun on a bench.
local SOUNDS={
    gear={fit={'WEAPON_ATTACHMENT_EQUIP','HUD_AMMO_SHOP_SOUNDSET'},remove={'WEAPON_ATTACHMENT_UNEQUIP','HUD_AMMO_SHOP_SOUNDSET'}},
    off={},
}
local function sound(event)
    local set=SOUNDS[Weapons.AttachmentSounds or 'gear']or SOUNDS.off
    local s=set[event]
    if s then PlaySoundFrontend(-1,s[1],s[2],true)end
end
local function componentOf(id,weapon)
    local part=id and Weapons.Attachments[id]
    return part and part.components and part.components[weapon]
end
local function findSlot(id)
    for _,slot in ipairs(view.slots or{})do if slot.id==id then return slot end end
end

-- Hover preview: the real component goes on the gun until the pointer leaves, then the fitted one comes back.
local function clearGhost()
    local g=ghost;ghost=nil
    if not g then return end
    local ped=PlayerPedId()
    -- Undo it even if the gun was just put away, so the preview part never stays on the loadout.
    if not HasPedGotWeapon(ped,g.hash,false)then return end
    if g.component~=g.restore and HasPedGotWeaponComponent(ped,g.hash,GetHashKey(g.component))then
        RemoveWeaponComponentFromPed(ped,g.hash,GetHashKey(g.component))
    end
    if g.restore and not HasPedGotWeaponComponent(ped,g.hash,GetHashKey(g.restore))then
        GiveWeaponComponentToPed(ped,g.hash,GetHashKey(g.restore))
    end
end
local function setGhost(slotId,id)
    clearGhost()
    if not slotId or not id or NO_GHOST[slotId]or view.busy or A.isBusy()then return false end
    local slot=findSlot(slotId);if not slot then return false end
    local option
    for _,o in ipairs(slot.options)do if o.id==id then option=o end end
    if not option or option.installed then return false end
    local component=componentOf(id,view.weapon);if not component then return false end
    local restore=componentOf(slot.current,view.weapon)
    local ped=PlayerPedId()
    if restore and restore~=component then RemoveWeaponComponentFromPed(ped,view.hash,GetHashKey(restore))end
    GiveWeaponComponentToPed(ped,view.hash,GetHashKey(component))
    ghost={hash=view.hash,slot=slotId,component=component,restore=restore}
    return true
end

-- The same numbers the game's weapon wheel shows (0-100). Structs come back as 8-byte padded ints.
local HUD_KEYS={'damage','speed','capacity','accuracy','range'}
local function hudStats(native,hash)
    local ok,result=pcall(function()
        local buffer=string.rep('\0',96)
        if not Citizen.InvokeNative(native,hash,buffer,Citizen.ReturnResultAnyway())then return nil end
        local out={}
        for i,key in ipairs(HUD_KEYS)do
            local value=string.unpack('<i4',buffer,(i-1)*8+1)
            if value<-200 or value>200 then return nil end
            out[key]=value
        end
        return out
    end)
    return ok and result or nil
end
local function weaponStats(hash)return hudStats(0xD92C739EE34C9EBA,hash)end
local function componentStats(component)return component and hudStats(0xB3CAF387AE12E9F8,GetHashKey(component))or nil end
local function noiseOf(id)
    local effect=id and Weapons.Effects and Weapons.Effects[id]
    return effect and effect.noiseScale or nil
end

local function close()
    if not view.open then return end
    view.open=false;view.run=view.run+1
    clearGhost()
    Weapons.StopPreview();SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
    if view.asset then RemoveWeaponAsset(view.asset)end;view.asset=nil
    send('close');TriggerEvent('bs:ui:closed','weaponAttachments')
    if GetResourceState('bs_ui')=='started'then pcall(function()exports.bs_ui:Send({action='bsHideAll',hidden=view.hudHidden==true})end)end
end
local function valid()
    return view.open and A.current()==view.weapon and not IsPedDeadOrDying(PlayerPedId(),true)
        and not IsPedInAnyVehicle(PlayerPedId(),true)
end
local function refresh()
    local run=view.run
    local ok,state=pcall(BSB.Await,'weapons:state',6000,view.weapon)
    if not ok then state=nil end
    if not valid()or run~=view.run then return false end
    if not state or not state.ok or (view.serial and view.serial~=state.serial)then close();return false end
    view.serial=state.serial
    local slots,unsupported={},0
    for _,slot in ipairs(Weapons.Slots)do
        local row={id=slot.id,label=slot.label,icon=slot.icon,current=state.fitted[slot.id],options={}}
        local installed=row.current and Weapons.Attachments[row.current]
        row.currentLabel=installed and installed.label
        row.currentItem=installed and installed.item
        row.currentStats=componentStats(componentOf(row.current,view.weapon))
        row.currentNoise=noiseOf(row.current)
        for id,part in pairs(Weapons.Attachments)do
            local component=part.components and part.components[view.weapon]
            if part.slot==slot.id and A.accepts(view.hash,component)then
                row.options[#row.options+1]={id=id,item=part.item,label=part.label,blurb=part.blurb,
                    count=tonumber(state.counts[part.item])or 0,installed=row.current==id,
                    stats=componentStats(component),noise=noiseOf(id),ghost=not NO_GHOST[slot.id]}
            end
        end
        table.sort(row.options,function(a,b)if (a.count>0)~=(b.count>0)then return a.count>0 end;return a.label<b.label end)
        if #row.options==0 and not row.current then unsupported=unsupported+1 end
        slots[#slots+1]=row
    end
    view.slots=slots
    local ped=PlayerPedId()
    local mags=Weapons.Magazines and Weapons.Magazines[view.weapon]
    local okClip,clip=pcall(GetMaxAmmoInClip,ped,view.hash,true)
    local noise=Weapons.Noise or {}
    send('state',{weapon=state.name and state.name~=''and state.name or state.label or Weapons.PrettyWeapon(view.weapon),
        serial=view.serial,slots=slots,unsupported=unsupported,rounds=GetAmmoInPedWeapon(ped,view.hash),
        base=weaponStats(view.hash),
        magazine={current=okClip and tonumber(clip)or nil,base=mags and mags.base or nil,ext=mags and mags.ext or nil},
        noise={silent=noise.suppressorIsSilent~=false,silentAt=noise.silentAtOrBelow or .30}})
    return true
end
local function open()
    if view.open then close();return end
    if A.isBusy()then return end
    local weapon,hash=A.current();local ped=PlayerPedId()
    if not weapon or IsNuiFocused()or IsPedDeadOrDying(ped,true)or IsPedInAnyVehicle(ped,true)then return end
    if Weapons.Settings.requireStill and (IsPedRunning(ped)or IsPedSprinting(ped))then return end
    view.open=true;view.run=view.run+1;view.weapon,view.hash,view.serial=weapon,hash,nil;view.busy=false
    local run=view.run
    view.hudHidden=false
    if GetResourceState('bs_ui')=='started'then pcall(function()view.hudHidden=exports.bs_ui:IsHudHidden()==true end)end
    -- Other menus close on this event; faction tags pause until the matching closed event.
    TriggerEvent('bs:ui:opened','weaponAttachments')
    if not HasWeaponAssetLoaded(hash)then
        RequestWeaponAsset(hash,31,0);view.asset=hash
        local deadline=GetGameTimer()+1500
        while view.run==run and not HasWeaponAssetLoaded(hash)and GetGameTimer()<deadline do Wait(10)end
    end
    if not valid()or run~=view.run then return end
    if not Weapons.StartPreview({shoulder=true,maxHold=30*60000})then close();return end
    if not refresh()then return end
    if GetResourceState('bs_ui')=='started'then pcall(function()exports.bs_ui:Send({action='bsHideAll',hidden=true})end)end
    view.ready=false
    send('open');SetNuiFocus(true,true);SetNuiFocusKeepInput(false)
    sound('open')
    CreateThread(function()Wait(4000);if view.open and view.run==run and not view.ready then close()end end)
end
function Weapons.OpenAttachments()
    local ok,err=xpcall(open,debug.traceback)
    if not ok then close();print('[bs_weapons] attachment view: '..tostring(err))end
end
RegisterNUICallback('attachmentReady',function(_,cb)view.ready=view.open;cb({ok=view.open})end)
RegisterNUICallback('attachmentClose',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('attachmentGhost',function(data,cb)
    if not valid()or type(data)~='table'or data.serial~=view.serial then return cb({ok=false})end
    if data.id==nil then clearGhost();return cb({ok=true})end
    cb({ok=setGhost(data.slot,data.id)})
end)
local CUES={pick='pick',match='match',cancel='cancel'}
RegisterNUICallback('attachmentCue',function(data,cb)
    local cue=type(data)=='table'and CUES[data.cue]
    if cue and view.open then sound(cue)end
    cb({ok=true})
end)
RegisterNUICallback('attachmentPart',function(data,cb)
    if not valid()or view.busy or type(data)~='table'or data.serial~=view.serial then return cb({ok=false,error='The weapon changed or is busy.'})end
    local selected=findSlot(data.slot)
    if not selected then return cb({ok=false})end
    if data.remove then
        if not selected.current then return cb({ok=false,error='Nothing fitted here.'})end
    else
        local found=false
        for _,option in ipairs(selected.options)do if option.id==data.id and option.count>0 and not option.installed then found=true end end
        if not found then sound('error');return cb({ok=false,error='You need a compatible part in your inventory.'})end
    end
    clearGhost()
    view.busy=true;local run=view.run
    local weapon,hash,serial=view.weapon,view.hash,view.serial
    local work=Weapons.Settings.viewWorkTime
    CreateThread(function()
        if view.run~=run or not valid()then return cb({ok=false,error='Attachment view closed.'})end
        local ok,result=pcall(function()
            if data.remove then return A.remove(weapon,hash,data.slot,serial,work)end
            return A.fit(weapon,hash,data.id,serial,work)
        end)
        if not ok then A.reset()end
        local success=ok and result and result.ok
        if view.run==run then
            view.busy=false
            if success then
                sound(data.remove and 'remove' or 'fit')
            else sound('error')end
            if valid()then refresh()else close()end
        end
        cb(ok and result or {ok=false,error='Attachment action failed.'})
    end)
end)
RegisterNUICallback('attachmentOrbit',function(data,cb)
    if valid()and not view.busy and type(data)=='table'then Weapons.AdjustPreview(tonumber(data.x)or 0,tonumber(data.y)or 0,tonumber(data.zoom)or 0,data.reset==true)end
    cb({ok=view.open})
end)

-- Hotspots: weapon mount bones projected to the screen every frame, with a bounds fallback.
local bones={muzzle='WAPSupp',scope='WAPScop',grip='WAPGrip',light='WAPFlsh',laser='WAPLasr',mag='WAPClip'}
local fallbackBones={muzzle='Gun_Muzzle',scope='WAPScop_2',grip='WAPGrip_2',light='WAPFlshLasr',laser='WAPFlshLasr',mag='WAPClip_2'}
local fractions={muzzle={.95,.55},scope={.53,.9},grip={.64,.25},light={.78,.55},laser={.78,.75},mag={.42,.12}}
local function samePoints(a,b)
    if not a or #a~=#b then return false end
    for i,p in ipairs(b)do
        local old=a[i]
        if old.id~=p.id or old.visible~=p.visible then return false end
        if p.visible and (math.abs(old.x-p.x)>.0001 or math.abs(old.y-p.y)>.0001)then return false end
    end
    return true
end
local function boneIndex(object,slot)
    local bone=GetEntityBoneIndexByName(object,bones[slot]or '')
    if (not bone or bone<0)and fallbackBones[slot]then bone=GetEntityBoneIndexByName(object,fallbackBones[slot])end
    return bone or -1
end
CreateThread(function()
    local cached,lastPoints={},nil
    while true do
        Wait(view.open and 0 or 500)
        if view.open then
            HideHudAndRadarThisFrame()
            if not valid()or not Weapons.PreviewActive()then close()
            else
                local object=GetCurrentPedWeaponEntityIndex(PlayerPedId(),0)
                if object and object~=0 and DoesEntityExist(object)then
                    local model=GetEntityModel(object)
                    if cached.object~=object or cached.model~=model or cached.run~=view.run then
                        local low,high=GetModelDimensions(model)
                        -- The long axis decides where the fallback fractions run along the gun.
                        cached={object=object,model=model,run=view.run,low=low,high=high,bones={},longX=(high.x-low.x)>=(high.y-low.y)}
                        lastPoints=nil
                    end
                    local low,high=cached.low,cached.high;local points={}
                    for _,slot in ipairs(view.slots or{})do
                        if #slot.options>0 or slot.current then
                            local bone=cached.bones[slot.id]
                            if bone==nil then bone=boneIndex(object,slot.id);cached.bones[slot.id]=bone end
                            local point,source
                            if bone>=0 then point=GetWorldPositionOfEntityBone(object,bone);source='bone'
                            else
                                local f=fractions[slot.id]or{.5,.5}
                                if cached.longX then point=GetOffsetFromEntityInWorldCoords(object,low.x+(high.x-low.x)*f[1],(low.y+high.y)*.5,low.z+(high.z-low.z)*f[2])
                                else point=GetOffsetFromEntityInWorldCoords(object,(low.x+high.x)*.5,low.y+(high.y-low.y)*f[1],low.z+(high.z-low.z)*f[2])end
                                source='bounds'
                            end
                            local on,x,y=GetScreenCoordFromWorldCoord(point.x,point.y,point.z)
                            points[#points+1]={id=slot.id,x=x,y=y,source=source,visible=on and x>.01 and x<.99 and y>.02 and y<.98}
                        end
                    end
                    if not samePoints(lastPoints,points)then send('points',points);lastPoints=points end
                elseif lastPoints and #lastPoints>0 then
                    send('points',{});lastPoints=nil
                end
            end
        end
    end
end)
AddEventHandler('bs:ui:opened',function(name)if name~='weaponAttachments'then close()end end)
AddEventHandler('bs:hook:player:unloaded',close)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then close()end end)
