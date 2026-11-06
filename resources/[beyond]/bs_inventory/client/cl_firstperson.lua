local key='bs_firstperson_v1'
local prefs={fpsEnabled=false,fpsFov=70,fpsBob=15,fpsCrosshair='dot',fpsSide=0,fpsForward=0,fpsHeight=0,fpsAimZoom=110}
local ranges={fpsFov={55,100},fpsBob={0,100},fpsSide={-8,8},fpsForward={-8,8},fpsHeight={-6,6},fpsAimZoom={100,150}}
local crosses={off=true,dot=true,cross=true,t=true}
local cam,lean,phase=nil,0,0
local left,right=false,false
local blocked,loaded={},false
local probe,clearance,probeAt=nil,0,0
local failed=false
local zoomOwned=false
local hudOwned=false
local function hud(active)
    if hudOwned~=active then hudOwned=active;LocalPlayer.state:set('bsFieldView',active,false)end
end
local groupNames={}
for _,name in ipairs({'pistol','smg','rifle','mg','shotgun','sniper','heavy','melee'})do groupNames[GetHashKey('GROUP_'..name:upper())]=name end
local function clamp(v,a,z)return math.max(a,math.min(z,v))end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function set(k,v)
    if k=='fpsEnabled'then if type(v)~='boolean'then return end
    elseif k=='fpsCrosshair'then if not crosses[v]then return end
    elseif ranges[k]then v=tonumber(v);if not finite(v)then return end;v=clamp(v,table.unpack(ranges[k]))
    else return end
    prefs[k]=v
    SetResourceKvp(key,json.encode(prefs))
end
do
    local ok,saved=pcall(json.decode,GetResourceKvpString(key)or '')
    if ok and type(saved)=='table'then for k,v in pairs(saved)do set(k,v)end end
end
local function release(keepViewModel)
    if BSFieldViewModel and not keepViewModel then BSFieldViewModel.Clear()end
    hud(false)
    if zoomOwned then SetFirstPersonAimCamZoomFactor(1.0);zoomOwned=false end
    if cam then
        if GetRenderingCam()==cam then RenderScriptCams(false,false,0,true,false)end
        DestroyCam(cam,false);cam=nil
    end
    lean,probe,clearance=0,nil,0
end
local function available()return FirstPerson and FirstPerson.enabled==true and not failed end
local function selected()return available()and prefs.fpsEnabled end
local function group(weapon)return groupNames[GetWeapontypeGroup(weapon)]or 'other'end
local function calibration(weapon)
    local result=FirstPerson.groups[group(weapon)]or FirstPerson.groups.other
    for name,p in pairs(FirstPerson.weapons or {})do if GetHashKey(name)==weapon then return p end end
    return result
end
exports('GetFirstPersonSettings',function()
    local out={fpsAvailable=available()};for k,v in pairs(prefs)do out[k]=v end;return out
end)
exports('SetFirstPersonSetting',set)
exports('GetFirstPersonHandling',function()
    if not selected()or not loaded or next(blocked)or IsNuiFocused()or GetFollowPedCamViewMode()~=4 or IsPedInAnyVehicle(PlayerPedId(),false)then return nil end
    if not BSFieldViewModel or not BSFieldViewModel.Supports(GetSelectedPedWeapon(PlayerPedId()))then return nil end
    return {highSkillRecoil=clamp(tonumber(FirstPerson.highSkillRecoil)or .45,.2,1),shake=.45}
end)
RegisterCommand('+bs_fps_left',function()if selected()then left=true end end,false)
RegisterCommand('-bs_fps_left',function()left=false end,false)
RegisterCommand('+bs_fps_right',function()if selected()then right=true end end,false)
RegisterCommand('-bs_fps_right',function()right=false end,false)
RegisterKeyMapping('+bs_fps_left','First-person lean left','keyboard','LBRACKET')
RegisterKeyMapping('+bs_fps_right','First-person lean right','keyboard','RBRACKET')
RegisterCommand('fpsreset',function()failed=false;left=false;right=false;set('fpsEnabled',false);release()end,false)
AddEventHandler('bs:ui:opened',function(name)blocked[name or 'menu']=true;left=false;right=false;release()end)
AddEventHandler('bs:ui:closed',function(name)blocked[name or 'menu']=nil end)
local function unloaded()loaded=false;left=false;right=false;blocked={};release()end
AddEventHandler('bs:hook:player:unloaded',unloaded)
AddEventHandler('bs:player:unloaded',unloaded)
-- Recover a selector-open marker left by an older multichar version.
local function selectionEnded()blocked.multichar=nil end
AddEventHandler('bs:multichar:spawnRelease',selectionEnded)
AddEventHandler('bs:hook:player:loaded',selectionEnded)
RegisterCommand('fpsstatus',function()
    local menus={};for name in pairs(blocked)do menus[#menus+1]=tostring(name)end;table.sort(menus)
    local reason='Ready: select first-person view with the normal camera key.'
    if failed then reason='Paused after a camera error. /fpsreset returns to vanilla; enable Field View again to retry.'
    elseif not available()then reason='Unavailable: enable First-person prototype availability in F1.'
    elseif not prefs.fpsEnabled then reason='Vanilla selected: enable Field View in Settings.'
    elseif not loaded then reason='Waiting for character spawn.'
    elseif #menus>0 then reason='Paused by menu: '..table.concat(menus,', ')
    elseif IsNuiFocused()or IsPauseMenuActive()then reason='Paused while a menu has focus.'
    elseif IsPedInAnyVehicle(PlayerPedId(),false)then reason='Vehicle camera remains native.'
    elseif GetFollowPedCamViewMode()~=4 then reason='Third person selected: switch to first person.'
    elseif BSFieldViewModel then reason=BSFieldViewModel.Status(GetSelectedPedWeapon(PlayerPedId()))
    elseif IsPlayerFreeAiming(PlayerId())then reason='Native aiming/scopes: release aim to see Field View.'
    else reason='Waiting for camera ownership or a supported movement state.'end
    print('[Field View] '..reason)
end,false)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then release()end end)
CreateThread(function()
    while true do
        local ok,value=pcall(function()return exports.bs_core:IsLoaded()end)
        loaded=ok and value==true
        if not loaded then release()end
        Wait(500)
    end
end)
local function crosshair(ped,weapon)
    HideHudComponentThisFrame(14)
    if prefs.fpsCrosshair=='off'or not IsPedArmed(ped,4)or IsPedReloading(ped)or IsPedSprinting(ped)then return end
    HideHudComponentThisFrame(14)
    local w,h=GetActiveScreenResolution();local sx,sy=1/w,1/h
    local spread=4+math.min(10,GetEntitySpeed(ped)*1.5)+(IsPedShooting(ped)and 4 or 0)
    if prefs.fpsCrosshair=='dot'then DrawRect(.5,.5,2*sx,2*sy,235,230,215,210);return end
    DrawRect(.5-(spread+3)*sx,.5,6*sx,sy,235,230,215,210)
    DrawRect(.5+(spread+3)*sx,.5,6*sx,sy,235,230,215,210)
    DrawRect(.5,.5+(spread+3)*sy,sx,6*sy,235,230,215,210)
    if prefs.fpsCrosshair=='cross'then DrawRect(.5,.5-(spread+3)*sy,sx,6*sy,235,230,215,210)end
end
local function step()
    local ped=PlayerPedId()
    local parkour=LocalPlayer.state.bsParkour
    local foreign=GetRenderingCam()
    local busy=not loaded or not selected()or next(blocked)or IsNuiFocused()or IsPauseMenuActive()
        or IsPedDeadOrDying(ped,true)or IsPedInAnyVehicle(ped,false)or IsPedRagdoll(ped)or IsPedFalling(ped)
        or IsCinematicCamRendering()or GetFollowPedCamViewMode()~=4
        or (type(parkour)=='table'and parkour.active)
        or LocalPlayer.state.bsBodycam==true
        or (foreign~=-1 and foreign~=cam)
    if busy then release();return end
    if cam then
        DisableControlAction(0,0,true)
        if IsDisabledControlJustPressed(0,0)then SetFollowPedCamViewMode(0);release();return end
    end
    local weapon=GetSelectedPedWeapon(ped)
    local profile=calibration(weapon)
    if not profile or profile.enabled==false then release();return end
    local aiming=IsPlayerFreeAiming(PlayerId())or IsControlPressed(0,25)
    local dedicated=BSFieldViewModel and BSFieldViewModel.Supports(weapon)
    if aiming or (dedicated and IsPedReloading(ped))then
        release()
        -- Native sights and magnified scopes retain their model-specific alignment.
        if group(weapon)~='sniper'then SetFirstPersonAimCamZoomFactor(prefs.fpsAimZoom/100);zoomOwned=true end
        return
    end
    local dt=math.min(.05,GetFrameTime())
    local desired=(right and 1 or 0)-(left and 1 or 0)
    if IsPedSprinting(ped)then desired=0 end
    lean=lean+(desired-lean)*math.min(1,dt*12)
    -- Never mirror a scripted view back through the gameplay camera for unsupported weapons.
    if not dedicated then release();return end
    local dedicatedReady=BSFieldViewModel.Ready(ped,weapon)
    if not dedicatedReady then release(true);return end
    local pos,rot=BSFieldViewModel.Camera(ped,dt)
    local origin=GetEntityCoords(ped)
    if not finite(pos.x)or not finite(pos.y)or not finite(pos.z)
        or (pos.x-origin.x)^2+(pos.y-origin.y)^2+(pos.z-origin.z)^2>6.25 then error('Camera outside player bounds')end
    local yaw,pitch=math.rad(rot.z),math.rad(rot.x)
    local side={x=math.cos(yaw),y=math.sin(yaw)}
    local forward={x=-math.sin(yaw)*math.cos(pitch),y=math.cos(yaw)*math.cos(pitch),z=math.sin(pitch)}
    local lateral=prefs.fpsSide/100+lean*clamp(tonumber(FirstPerson.leanDistance)or .22,0,.3)
    local advance=(tonumber(profile.forward)or 0)+prefs.fpsForward/100
    local height=(tonumber(profile.height)or 0)+prefs.fpsHeight/100
    if dedicatedReady then lateral=lean*clamp(tonumber(FirstPerson.leanDistance)or .22,0,.3);advance=0;height=0 end
    phase=phase+dt*math.min(GetEntitySpeed(ped),5)*5
    local bob=math.sin(phase)*.008*prefs.fpsBob/100
    -- Pull the framing up slightly while sprinting: the weapon sits lower in view.
    local z=height+bob+(IsPedSprinting(ped)and .025 or 0)
    local target=vector3(pos.x+side.x*lateral+forward.x*advance,pos.y+side.y*lateral+forward.y*advance,pos.z+forward.z*advance+z)
    local now=GetGameTimer()
    if probe then
        local state,hit=GetShapeTestResult(probe)
        if state~=1 then clearance=state==2 and (hit==false or hit==0)and 1 or 0;probe=nil end
    end
    if not probe and now-probeAt>=40 then
        -- Check the entire requested lean before letting the camera move outward.
        local fullSide=prefs.fpsSide/100+desired*clamp(tonumber(FirstPerson.leanDistance)or .22,0,.3)
        probe=StartShapeTestCapsule(pos.x,pos.y,pos.z,pos.x+side.x*fullSide+forward.x*advance,pos.y+side.y*fullSide+forward.y*advance,pos.z+forward.z*advance+z,.09,511,ped,7)
        probeAt=now
    end
    if clearance==0 then target=pos;lean=0 end
    if not cam then
        cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',false)
        if not cam or cam==0 then cam=nil;error('Camera could not start')end
        SetCamNearClip(cam,.06);SetCamAffectsAiming(cam,true)
        SetCamCoord(cam,target.x,target.y,target.z)
        SetCamRot(cam,rot.x,lean*clamp(tonumber(FirstPerson.leanRoll)or 5,0,8),rot.z,2)
        SetCamFov(cam,prefs.fpsFov)
        SetCamActive(cam,true);RenderScriptCams(true,false,0,true,false)
    end
    SetCamCoord(cam,target.x,target.y,target.z)
    SetCamRot(cam,rot.x,lean*clamp(tonumber(FirstPerson.leanRoll)or 5,0,8),rot.z,2)
    SetCamFov(cam,prefs.fpsFov)
    if dedicatedReady then BSFieldViewModel.Draw(ped,weapon,target,rot,dt,prefs,lean)end
    hud(true)
    crosshair(ped,weapon)
end
CreateThread(function()
    while true do
        if not selected()or not loaded then release();Wait(250)
        else
            local ok,err=pcall(step)
            if not ok then release();failed=true;print('[bs_inventory] First-person camera paused: '..tostring(err)..' /fpsreset retries it.')end
            Wait(0)
        end
    end
end)
