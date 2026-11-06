
local setPeds,setProps={},{}
local setGeneration=0
local chosenPreset
local arrivalCam,arrivalToken
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<12000 end
local function discard(list)
    for _,entity in ipairs(list)do if DoesEntityExist(entity)then DeleteEntity(entity)end end
end
function Scene.ClearSet()
    setGeneration=setGeneration+1
    discard(setPeds);discard(setProps);setPeds={};setProps={}
end
function Scene.SelectSet(faction)
    local cfg=Multichar.Selection
    local name=type(cfg.factions)=='table'and cfg.factions[tostring(faction or '')]or nil;name=name or cfg.preset
    local presets=type(cfg.presets)=='table'and cfg.presets or {}
    local preset=presets[name]or presets.motel
    if type(preset)~='table'or type(preset.ped)~='table'or not finite(preset.ped.x)or not finite(preset.ped.y)or not finite(preset.ped.z)then
        preset={ped={x=402.88,y=-996.45,z=-99,h=180},outdoor=false};name='lineup'
    end
    if chosenPreset==name then return false end
    chosenPreset=name
    Multichar.Scene.ped={x=preset.ped.x,y=preset.ped.y,z=preset.ped.z,h=finite(preset.ped.h)and preset.ped.h or 180}
    Multichar.Scene.precache={x=preset.ped.x,y=preset.ped.y,z=preset.ped.z+2}
    Multichar.Scene.weather=cfg.weather;Multichar.Scene.hour=cfg.hour;Multichar.Scene.minute=cfg.minute
    Multichar.Scene.maxCamDistance=preset.outdoor and 8.0 or 3.4
    Scene.cameraHeading=finite(preset.cameraHeading)and preset.cameraHeading or 0
    Scene.outdoor=preset.outdoor==true
    return true
end
-- Resolve a clear standing spot and view after the motel's collision has streamed.
function Scene.ResolveOutdoorSet()
    if not Scene.outdoor then return true end
    local at=Multichar.Scene.ped
    local generation=Scene.gen
    local deadline=GetGameTimer()+2000
    local function current()return Scene.gen==generation and Multichar.Scene.ped==at and GetGameTimer()<deadline end
    local heading=Scene.cameraHeading or 0
    local shot=Multichar.Settings.focus.full
    local distance=shot.offset.y or 2.75
    local aspect=GetAspectRatio(false)
    local lateral=(shot.offset.x or 0)*distance*math.tan(math.rad((shot.fov or 50)*.5))*aspect
    local function clear(a,b,radius)
        local ray=StartShapeTestCapsule(a.x,a.y,a.z,b.x,b.y,b.z,radius,17,PlayerPedId(),7)
        local deadline=GetGameTimer()+100
        local status,hit
        repeat status,hit=GetShapeTestResult(ray);if status==1 then Wait(0)end until status~=1 or GetGameTimer()>=deadline or not current()
        return current()and status==2 and (hit==0 or hit==false)
    end
    local offsets={{0,0},{-2,0},{2,0},{0,-2},{0,2},{-3,-3},{3,-3},{-3,3},{3,3},{0,-5},{-5,0},{5,0},{0,5}}
    for _,offset in ipairs(offsets)do
        if not current()then return false end
        local x,y=at.x+offset[1],at.y+offset[2]
        local found,ground=GetGroundZFor_3dCoord(x,y,at.z+2,false)
        if found and math.abs(ground-at.z)<4 then
            local feet={x=x,y=y,z=ground+.4};local head={x=x,y=y,z=ground+1.85}
            if clear(feet,head,.3)then
                for _,turn in ipairs({0,-30,30,-60,60,-90,90,180})do
                    local angle=heading+turn;local rad=math.rad(angle)
                    local camera={x=x+lateral*math.cos(rad)+distance*math.sin(rad),y=y+lateral*math.sin(rad)-distance*math.cos(rad),z=ground+.95}
                    if clear(camera,head,.15)and clear(camera,feet,.15)then
                        at.x,at.y,at.z=x,y,ground+1.0;at.h=(180+angle)%360
                        Scene.cameraHeading=angle%360
                        return true
                    end
                end
            end
        end
    end
    print('^3[BeyondSurvival]^7 selection scene: no clear full-body view found; adjust the scene position in F1.')
    return false
end

function Scene.BuildSet(characters,selected)
    Scene.ClearSet()
    local token=setGeneration
    if not Scene.active then return end
    local cfg=Multichar.Selection
    local preset=type(cfg.presets)=='table'and cfg.presets[chosenPreset]or{};preset=type(preset)=='table'and preset or{}
    local at=Multichar.Scene.ped
    local function current()return Scene.active and token==setGeneration end
    CreateThread(function()
        if cfg.lineup then
            local n=0
            for i,char in ipairs(characters or{})do
                if i~=selected and n<3 then
                    local actor=Scene.MakePortraitPed(char,current)
                    if actor then
                        if not current()then DeleteEntity(actor);return end
                        n=n+1
                        local rad=math.rad(Scene.cameraHeading or 0)
                        local x=(n%2==1 and -1 or 1)*(1.1+math.floor(n/2)*.5)
                        local y=1.4+math.floor(n/2)*.55
                        SetEntityCoordsNoOffset(actor,at.x+x*math.cos(rad)-y*math.sin(rad),at.y+x*math.sin(rad)+y*math.cos(rad),at.z,false,false,false)
                        SetEntityHeading(actor,at.h or 180)
                        setPeds[#setPeds+1]=actor
                        local idle=Multichar.Settings.idleAnim
                        RequestAnimDict(idle.dict)
                        local deadline=GetGameTimer()+1500
                        while current()and not HasAnimDictLoaded(idle.dict)and GetGameTimer()<deadline do Wait(0)end
                        if not current()then return end
                        if HasAnimDictLoaded(idle.dict)then TaskPlayAnim(actor,idle.dict,idle.clip,2.0,2.0,-1,1,0,false,false,false)end
                    end
                end
            end
        end
        local props={}
        for _,p in ipairs(type(cfg.props)=='table'and cfg.props or{})do props[#props+1]=p end
        for _,p in ipairs(type(preset.props)=='table'and preset.props or{})do props[#props+1]=p end
        for i,p in ipairs(props)do
            if i>32 or not current()then return end
            if type(p)=='table'and type(p.model)=='string'and finite(p.x)and finite(p.y)and finite(p.z)then
                local hash=GetHashKey(p.model)
                if IsModelInCdimage(hash)and IsModelValid(hash)then
                    RequestModel(hash);local deadline=GetGameTimer()+2000
                    while current()and not HasModelLoaded(hash)and GetGameTimer()<deadline do Wait(0)end
                    if not current()then SetModelAsNoLongerNeeded(hash);return end
                    if HasModelLoaded(hash)then
                        local object=CreateObjectNoOffset(hash,p.x,p.y,p.z,false,false,false)
                        if object and object~=0 then
                            SetEntityAsMissionEntity(object,true,true);Entity(object).state:set('bsProtected',true,false)
                            SetEntityHeading(object,finite(p.h)and p.h or 0);SetEntityCollision(object,false,false);FreezeEntityPosition(object,true)
                            setProps[#setProps+1]=object
                        end
                    end
                    SetModelAsNoLongerNeeded(hash)
                end
            end
        end
    end)
end
function Scene.EndArrival()
    arrivalToken=nil
    if arrivalCam then
        if GetRenderingCam()==arrivalCam then RenderScriptCams(false,false,0,true,true)end
        DestroyCam(arrivalCam,false);arrivalCam=nil
    end
end
AddEventHandler('bs:multichar:spawnArrival',function(data)
    local cfg=Multichar.Selection
    if not cfg.arrival or cfg.reducedMotion or GetResourceKvpInt('selectorMotionOff')==1 or data.survivorLinkSwitch then return end
    if IsPedDeadOrDying(PlayerPedId(),true)or GetRenderingCam()~=-1 then return end
    Scene.EndArrival()
    local ped=PlayerPedId();local at=GetEntityCoords(ped);local forward=GetEntityForwardVector(ped)
    local token={};arrivalToken=token
    arrivalCam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    local cam=arrivalCam
    SetCamCoord(cam,at.x-forward.x*5,at.y-forward.y*5,at.z+3)
    PointCamAtCoord(cam,at.x,at.y,at.z+.5);SetCamFov(cam,50)
    RenderScriptCams(true,false,0,true,true)
    CreateThread(function()
        local start=GetGameTimer();local duration=math.max(600,math.min(2500,cfg.arrivalMs or 1400))
        while arrivalToken==token and GetGameTimer()-start<duration do
            if PlayerPedId()~=ped or IsPedDeadOrDying(ped,true)or GetRenderingCam()~=cam then break end
            local t=(GetGameTimer()-start)/duration;t=t*t*(3-2*t)
            local finish=GetGameplayCamCoord()
            SetCamCoord(cam,at.x-forward.x*5+(finish.x-at.x+forward.x*5)*t,at.y-forward.y*5+(finish.y-at.y+forward.y*5)*t,at.z+3+(finish.z-at.z-3)*t)
            PointCamAtCoord(cam,at.x,at.y,at.z+.5);Wait(0)
        end
        if arrivalToken==token then Scene.EndArrival()end
    end)
end)
AddEventHandler('onResourceStop',function(resource)if resource==GetCurrentResourceName()then Scene.ClearSet();Scene.EndArrival()end end)
AddEventHandler('bs_config:changed:bs_multichar',function()if not Scene.active then chosenPreset=nil end end)
