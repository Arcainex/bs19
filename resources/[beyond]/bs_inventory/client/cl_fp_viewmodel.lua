-- Local rifle presentation. The equipped weapon remains the gameplay authority.
BSFieldViewModel={}
local V=BSFieldViewModel
local object,asset,hiddenWeapon,loading,token=nil,nil,nil,false,0
local objectWeapon=nil
local yaw,pitch,eyeHeight,phase,kick=nil,nil,nil,0,0
local smoothLook,lookAmount=false,40
local lookX,lookY=0,0
function V.SetLookSmoothing(enabled,amount)
    smoothLook=enabled==true;lookAmount=math.max(0,math.min(100,tonumber(amount)or 40))
    lookX,lookY=0,0
end
local hiddenPed
local failedWeapon,retryAt=nil,0
local groups={}
for _,name in ipairs({'pistol','smg','rifle','mg','shotgun','sniper','heavy','melee'}) do
    groups[GetHashKey('GROUP_'..name:upper())]=name
end
local function tuning(weapon)
    local cfg=FirstPerson and FirstPerson.viewmodel
    if not cfg or not cfg.enabled or weapon==GetHashKey('WEAPON_UNARMED') then return end
    local state=LocalPlayer and LocalPlayer.state
    local cosmetic=state and state.bsWeaponCosmetic
    local stickers=state and state.bsWeaponStickers
    if cosmetic and cosmetic.mounts and #cosmetic.mounts>0 then return end
    if stickers and stickers.entries and #stickers.entries>0 then return end
    local kind=groups[GetWeapontypeGroup(weapon)]
    local profile=kind and cfg.classes and cfg.classes[kind]
    if not profile or profile.enabled==false then return end
    if weapon==GetHashKey(cfg.weapon or '') then return cfg end
    local custom=FirstPerson.weapons or {}
    for name,overrides in pairs(custom) do
        if GetHashKey(name)==weapon and overrides.enabled==false then return end
        if GetHashKey(name)==weapon then profile=overrides end
    end
    return profile
end
function V.Clear()
    token=token+1;loading=false
    if hiddenWeapon and DoesEntityExist(hiddenWeapon)then SetEntityLocallyVisible(hiddenWeapon)end
    hiddenWeapon=nil
    if hiddenPed and DoesEntityExist(hiddenPed)then SetEntityLocallyVisible(hiddenPed)end
    hiddenPed=nil
    if object and DoesEntityExist(object)then DeleteEntity(object)end
    object=nil;objectWeapon=nil
    if asset then RemoveWeaponAsset(asset);asset=nil end
    yaw,pitch,eyeHeight,phase,kick=nil,nil,nil,0,0
    lookX,lookY=0,0
end
function V.Supports(weapon)return tuning(weapon)~=nil end
function V.Status(weapon)
    local cfg=FirstPerson and FirstPerson.viewmodel
    if not cfg or not cfg.enabled then return 'Independent rifle presentation disabled in config.'end
    if not tuning(weapon)then return 'Native fallback: this weapon or its cosmetic parts need a separate viewmodel.'end
    if object and DoesEntityExist(object)then return 'Field View active.'end
    if failedWeapon==weapon and GetGameTimer()<retryAt then return 'Native fallback: weapon model failed to load; retrying shortly.'end
    return 'Preparing weapon viewmodel.'
end
function V.Ready(ped,weapon)
    if not tuning(weapon)then V.Clear();return false end
    if objectWeapon and objectWeapon~=weapon then V.Clear() end
    if object and DoesEntityExist(object)then
        local source=GetCurrentPedWeaponEntityIndex(ped,0)
        if source and source~=0 and DoesEntityExist(source)then return true end
        V.Clear()
        failedWeapon=weapon;retryAt=GetGameTimer()+1500
        return false
    end
    if loading or (failedWeapon==weapon and GetGameTimer()<retryAt)then return false end
    loading=true;token=token+1;local run=token
    CreateThread(function()
        if run~=token then return end
        local ok=pcall(function()
            RequestWeaponAsset(weapon,31,0);asset=weapon
            local untilAt=GetGameTimer()+1500
            while run==token and not HasWeaponAssetLoaded(weapon)and GetGameTimer()<untilAt do Wait(0)end
            if run~=token then return end
            if not HasWeaponAssetLoaded(weapon)or GetSelectedPedWeapon(ped)~=weapon then error('Rifle asset unavailable')end
            local at=GetEntityCoords(ped)
            object=CreateWeaponObject(weapon,0,at.x,at.y,at.z,true,1.0,0,false,false)
            if not object or object==0 or not DoesEntityExist(object)then object=nil;error('Weapon viewmodel unavailable')end
            objectWeapon=weapon
            SetEntityCollision(object,false,false);FreezeEntityPosition(object,true)
            SetEntityVisible(object,false,false)
            local cfg=tuning(weapon)
            for _,name in ipairs(cfg and cfg.components or {})do
                local component=GetHashKey(name)
                if HasPedGotWeaponComponent(ped,weapon,component)then GiveWeaponComponentToWeaponObject(object,component)end
            end
            SetWeaponObjectTintIndex(object,GetPedWeaponTintIndex(ped,weapon))
        end)
        if run~=token then return end
        loading=false
        if not ok then V.Clear();failedWeapon=weapon;retryAt=GetGameTimer()+5000 end
    end)
    return false
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
AddEventHandler('bs:camera:recoil',function(vertical,horizontal)
    if not yaw then return end
    if finite(vertical)then pitch=math.max(-70,math.min(70,pitch+math.max(-5,math.min(5,vertical))))end
    if finite(horizontal)then yaw=(yaw+math.max(-3,math.min(3,horizontal)))%360 end
end)
function V.Camera(ped,dt)
    if not yaw then
        local rot=GetGameplayCamRot(2);yaw,pitch=rot.z,rot.x
    end
    DisableControlAction(0,1,true);DisableControlAction(0,2,true)
    local gain=IsInputDisabled(2)and 8.0 or 135.0*dt
    local ix,iy=GetDisabledControlNormal(0,1),GetDisabledControlNormal(0,2)
    if smoothLook and IsInputDisabled(2) then
        local tau=lookAmount*.002
        local alpha=tau<.001 and 1 or 1-math.exp(-dt/tau)
        lookX=lookX+(ix-lookX)*alpha;lookY=lookY+(iy-lookY)*alpha
        ix,iy=lookX,lookY
    else lookX,lookY=0,0 end
    yaw=(yaw-ix*gain)%360
    pitch=math.max(-70,math.min(70,pitch-iy*gain))
    -- Keep the native fallback aligned for a clean handoff when aiming or opening a menu.
    SetGameplayCamRelativePitch(pitch,1.0)
    SetGameplayCamRelativeHeading(((yaw-GetEntityHeading(ped)+180)%360)-180)
    local base=GetEntityCoords(ped)
    local crouched=IsPedDucking(ped)
    local height=crouched and .98 or 1.60
    eyeHeight=eyeHeight or height
    eyeHeight=eyeHeight+(height-eyeHeight)*math.min(1,dt*10)
    local y=math.rad(yaw)
    local forward=(FirstPerson.viewmodel and FirstPerson.viewmodel.eyeForward) or .20
    forward=math.max(.12,math.min(.26,tonumber(forward) or .20))
    if FirstPerson.viewmodel and FirstPerson.viewmodel.showBody==false then
        hiddenPed=ped;SetEntityLocallyInvisible(ped)
    end
    return vector3(base.x-math.sin(y)*forward,base.y+math.cos(y)*forward,base.z+eyeHeight),{x=pitch,y=0,z=yaw}
end
function V.Draw(ped,weapon,pos,rot,dt,prefs,lean)
    local cfg=tuning(weapon)
    if not cfg or not object or not DoesEntityExist(object)then return end
    local source=GetCurrentPedWeaponEntityIndex(ped,0)
    if not source or source==0 or not DoesEntityExist(source)then SetEntityVisible(object,false,false);return end
    hiddenWeapon=source;SetEntityLocallyInvisible(source)
    local y,p=math.rad(rot.z),math.rad(rot.x)
    local right={x=math.cos(y),y=math.sin(y)}
    local f={x=-math.sin(y)*math.cos(p),y=math.cos(y)*math.cos(p),z=math.sin(p)}
    local up={x=math.sin(y)*math.sin(p),y=-math.cos(y)*math.sin(p),z=math.cos(p)}
    phase=phase+dt*math.min(GetEntitySpeed(ped),5)*5
    if IsPedShooting(ped)then kick=math.min(.025,kick+.009)end
    kick=kick*math.exp(-dt*18)
    local sprint=IsPedSprinting(ped)
    local sway=math.sin(phase)*.008*prefs.fpsBob/100
    local side=(cfg.side or .19)+prefs.fpsSide/100+sway
    local forward=(cfg.forward or .46)+prefs.fpsForward/100-kick
    local height=(cfg.height or -.22)+prefs.fpsHeight/100+(sprint and -.08 or 0)+math.cos(phase*2)*.004*prefs.fpsBob/100
    SetEntityCoordsNoOffset(object,pos.x+right.x*side+f.x*forward+up.x*height,pos.y+right.y*side+f.y*forward+up.y*height,pos.z+f.z*forward+up.z*height,false,false,false)
    SetEntityRotation(object,(sprint and 18 or 0)+(lean or 0)*3,-rot.x+(sprint and 15 or 0)-kick*100,rot.z+90+(sprint and -12 or 0),2,true)
    SetEntityVisible(object,true,false)
end
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then V.Clear()end end)
