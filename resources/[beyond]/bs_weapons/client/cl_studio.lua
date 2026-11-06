-- Local workbench scene. The player's real weapon and position are never changed.
local Scene={active=false,object=nil,cam=nil,asset=nil,model=nil,revision=0,orbit=0,elevation=.08,zoom=1}
local backdrop
local backdropSequence=0
local backdropTxd
local FOV=36.0
local AXES={x={x=1,y=0,z=0},y={x=0,y=1,z=0},z={x=0,y=0,z=1}}
local COLORS={x='#cf7565',y='#9bb579',z='#82a8cb'}
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vec(x,y,z)return{x=x,y=y,z=z}end
local function add(a,b)return vec(a.x+b.x,a.y+b.y,a.z+b.z)end
local function sub(a,b)return vec(a.x-b.x,a.y-b.y,a.z-b.z)end
local function mul(a,s)return vec(a.x*s,a.y*s,a.z*s)end
local function dot(a,b)return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b)return vec(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)end
local function length(a)return math.sqrt(dot(a,a))end
local function unit(a)local n=length(a);return n>.000001 and mul(a,1/n)or vec(0,0,0)end
local function copyTransform(t)
    local out={};for k,v in pairs(t)do out[k]=v end
    out.position=vec(t.position.x,t.position.y,t.position.z)
    out.rotation=vec(t.rotation.x,t.rotation.y,t.rotation.z)
    out.scale=finite(t.scale)and t.scale or 1
    return out
end
local function world(localPoint)
    local p=GetOffsetFromEntityInWorldCoords(Scene.object,localPoint.x,localPoint.y,localPoint.z)
    return vec(p.x,p.y,p.z)
end
local function localPoint(p)
    local v=GetOffsetFromEntityGivenWorldCoords(Scene.object,p.x,p.y,p.z)
    return vec(v.x,v.y,v.z)
end
function Weapons.InspectionObject()
    return Scene.active and Scene.object and DoesEntityExist(Scene.object)and Scene.object or nil
end
local function cameraBasis()
    if not Scene.active or not Scene.cam or not DoesCamExist(Scene.cam)then return end
    local c,r=GetCamCoord(Scene.cam),GetCamRot(Scene.cam,2)
    local yaw,pitch=math.rad(r.z),math.rad(r.x)
    return vec(c.x,c.y,c.z),vec(math.cos(yaw),math.sin(yaw),0),
        vec(math.sin(yaw)*math.sin(pitch),-math.cos(yaw)*math.sin(pitch),math.cos(pitch)),
        vec(-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch))
end
-- Backdrops: a real place behind the gun, streamed in, thrown out of focus and darkened by a veil behind the weapon.
local BD_KEY='bs_workbench_backdrop'
local function backdropList()return (Weapons.Workbench and Weapons.Workbench.backdrops)or {{id='black',label='Black',solid=true}}end
local function findBackdrop(id)for _,b in ipairs(backdropList())do if b.id==id then return b end end end
function Weapons.StudioBackdropId()
    local id=GetResourceKvpString(BD_KEY)
    if not id or not findBackdrop(id)then id=(Weapons.Workbench and Weapons.Workbench.backdrop)or 'black'end
    if not findBackdrop(id)then id=backdropList()[1].id end
    return id
end
function Weapons.StudioBackdrops()
    local out={};for _,b in ipairs(backdropList())do out[#out+1]={id=b.id,label=b.label or b.id}end
    return out
end
local function isPlace(bd)return bd and bd.camera and bd.lookAt and not bd.solid and not bd.capture end
local function releasePlace()
    if Scene.focused then ClearFocus();Scene.focused=false end
    if IsNewLoadSceneActive()then NewLoadSceneStop()end
    if Scene.interior then UnpinInterior(Scene.interior);Scene.interior=nil end
end
local function holdPlayer(on)
    local ped=PlayerPedId()
    if on and not Scene.frozePed then
        -- The world streams around the place, not the player: keep the player from dropping through unloaded ground.
        if not IsEntityPositionFrozen(ped)then FreezeEntityPosition(ped,true);Scene.frozePed=ped end
    elseif not on and Scene.frozePed then
        if DoesEntityExist(Scene.frozePed)then FreezeEntityPosition(Scene.frozePed,false)end
        Scene.frozePed=nil
    end
end
-- Streams the place and puts the gun just in front of the backdrop camera. Orbit and object heading are set so the
-- home view is the same broadside view as before, now looking into the place.
local function placeAtBackdrop(bd,seq)
    local cam=vec(bd.camera.x,bd.camera.y,bd.camera.z)
    local look=vec(bd.lookAt.x,bd.lookAt.y,bd.lookAt.z)
    local dir=unit(sub(look,cam))
    SetFocusPosAndVel(cam.x,cam.y,cam.z,0.0,0.0,0.0);Scene.focused=true
    RequestCollisionAtCoord(cam.x,cam.y,cam.z)
    if not IsNewLoadSceneActive()then NewLoadSceneStart(cam.x,cam.y,cam.z,dir.x,dir.y,dir.z,45.0,0)end
    local deadline=GetGameTimer()+3500
    while Scene.backdropSeq==seq and GetGameTimer()<deadline and IsNewLoadSceneActive()and not IsNewLoadSceneLoaded()do Wait(50)end
    if IsNewLoadSceneActive()then NewLoadSceneStop()end
    if Scene.backdropSeq~=seq then return false end
    if bd.interior then
        local id=GetInteriorAtCoords(look.x,look.y,look.z)
        if id and id~=0 then
            PinInteriorInMemory(id);Scene.interior=id
            local untilAt=GetGameTimer()+2000
            while Scene.backdropSeq==seq and not IsInteriorReady(id)and GetGameTimer()<untilAt do Wait(50)end
        end
    end
    if Scene.backdropSeq~=seq or not Weapons.InspectionObject()then return false end
    local flat=unit(vec(dir.x,dir.y,0))
    local home=math.deg(math.atan(-flat.y,flat.x))
    Scene.heading=((Scene.baseOrbit or 0)-home)%360
    Scene.homeOrbit=home
    local d=Scene.distance
    local target=add(cam,mul(vec(flat.x,flat.y,dir.z),d))
    target=vec(target.x,target.y,target.z-Scene.elevation*d)
    SetEntityHeading(Scene.object,Scene.heading)
    local at=GetEntityCoords(Scene.object);local c=world(Scene.fullCenter)
    SetEntityCoordsNoOffset(Scene.object,at.x+target.x-c.x,at.y+target.y-c.y,at.z+target.z-c.z,false,false,false)
    Scene.center=Scene.fullCenter;Scene.orbit,Scene.zoom=home,1
    return true
end
local function frame()
    if not Weapons.InspectionObject()or not Scene.cam then return end
    local target=world(Scene.center)
    local a,d=math.rad(Scene.orbit),Scene.distance*Scene.zoom
    local from=vec(target.x-math.cos(a)*d,target.y+math.sin(a)*d,target.z+Scene.elevation*d)
    local right=unit(vec(target.y-from.y,from.x-target.x,0))
    local aim=add(add(target,mul(right,d*.09)),vec(0,0,-d*.025))
    local direction=sub(aim,from)
    local flat=math.sqrt(direction.x^2+direction.y^2)
    local pitch=math.deg(math.atan(direction.z,flat))
    local yaw=math.deg(math.atan(-direction.x,direction.y))
    SetCamCoord(Scene.cam,from.x,from.y,from.z)
    SetCamRot(Scene.cam,pitch,0.0,yaw,2)
    if isPlace(Scene.bd)then
        -- Focus band hugs the weapon; everything behind it falls out of focus.
        local r=Scene.radius or .3
        SetCamUseShallowDofMode(Scene.cam,true)
        SetCamNearDof(Scene.cam,math.max(.02,d-r-.15))
        SetCamFarDof(Scene.cam,d+r+.05)
        SetCamDofStrength(Scene.cam,clamp(Scene.bd.blur or 1.0,0,1))
    end
end
function Weapons.CloseStudio()
    Scene.revision=Scene.revision+1
    Scene.active=false
    if backdrop and backdrop.dui then DestroyDui(backdrop.dui)end
    backdrop=nil
    if Scene.cam then
        RenderScriptCams(false,false,0,true,true)
        if DoesCamExist(Scene.cam)then DestroyCam(Scene.cam,false)end
    end
    Scene.backdropSeq=(Scene.backdropSeq or 0)+1
    releasePlace();holdPlayer(false)
    Scene.bd,Scene.heading,Scene.homeOrbit=nil,nil,nil
    if Scene.object and DoesEntityExist(Scene.object)then DeleteEntity(Scene.object)end
    if Scene.asset then RemoveWeaponAsset(Scene.asset)end
    if Scene.model then SetModelAsNoLongerNeeded(Scene.model)end
    Scene.object,Scene.cam,Scene.asset,Scene.model=nil,nil,nil,nil
end
local function stagingPoint(ped)
    local at=GetEntityCoords(ped)
    local z=at.z+4.0
    -- A short local roof probe keeps indoor workbenches above their ceiling.
    if StartExpensiveSynchronousShapeTestLosProbe and GetShapeTestResult then
        local ray=StartExpensiveSynchronousShapeTestLosProbe(at.x,at.y,at.z+80.0,at.x,at.y,at.z,1,ped,7)
        local status,hit,point=GetShapeTestResult(ray)
        if status==2 and hit and point and finite(point.z)then z=math.max(z,point.z+4.0)end
    end
    return vec(at.x,at.y,z)
end
function Weapons.StudioTintOptions(weapon)
    local hash=GetHashKey(weapon)
    local count=type(GetWeaponTintCount)=='function'and GetWeaponTintCount(hash)or 8
    count=math.max(1,math.min(32,tonumber(count)or 1))
    local names={'Factory','Green','Gold','Pink','Army','Police','Orange','Platinum'}
    local out={}
    for i=0,count-1 do out[#out+1]={id=i,label=count<=8 and names[i+1]or ('Finish %02d'):format(i+1)}end
    return out
end
function Weapons.SetStudioTint(tint,_)
    local object=Weapons.InspectionObject()
    if not object or not finite(tint)or tint%1~=0 or tint<0 or tint>=#Weapons.StudioTintOptions(Scene.weapon)then return false,'This weapon does not support that finish.'end
    SetWeaponObjectTintIndex(object,tint)
    if type(GetWeaponObjectTintIndex)=='function'and GetWeaponObjectTintIndex(object)~=tint then return false,'The model rejected this finish.'end
    return true
end
local pendingBackdrop
RegisterNUICallback('studioBackdropCaptured',function(data,cb)
    if pendingBackdrop and data.token==pendingBackdrop.token then
        if type(data.image)=='string'and #data.image<12000000 and data.image:sub(1,16)=='data:image/jpeg;'then pendingBackdrop.image=data.image end
        pendingBackdrop.finished=true
    end
    cb({ok=true})
end)
local function captureBackdrop(revision)
    backdropSequence=backdropSequence+1
    local request={token=backdropSequence};pendingBackdrop=request
    SendNUIMessage({action='studio:grabBackdrop',token=request.token})
    local deadline=GetGameTimer()+1800
    while not request.finished and Scene.revision==revision and GetGameTimer()<deadline do Wait(0)end
    if pendingBackdrop==request then pendingBackdrop=nil end
    if Scene.revision~=revision then return end
    local record={token=request.token,image=request.image};backdrop=record
    record.dui=CreateDui(('https://cfx-nui-%s/html/studio-backdrop.html?resource=%s&token=%d'):format(GetCurrentResourceName(),GetCurrentResourceName(),record.token),1280,720)
end
RegisterNUICallback('studioBackdropPage',function(data,cb)
    if backdrop and data.token==backdrop.token then
        SendDuiMessage(backdrop.dui,json.encode({image=backdrop.image,token=backdrop.token}))
    end
    cb({ok=true})
end)
RegisterNUICallback('studioBackdropReady',function(data,cb)
    if backdrop and data.token==backdrop.token then
        -- Dictionary once, a new texture name per capture: a reused name keeps showing the old, destroyed page.
        backdropTxd=backdropTxd or CreateRuntimeTxd('bs_weapon_backdrop')
        backdrop.txn='scene'..backdrop.token
        backdrop.texture=CreateRuntimeTextureFromDuiHandle(backdropTxd,backdrop.txn,GetDuiHandle(backdrop.dui))
        backdrop.ready=backdrop.texture and backdrop.texture~=0
        backdrop.image=nil
    end
    cb({ok=true})
end)
function Weapons.OpenStudio(weapon,fitted,tint)
    Weapons.CloseStudio()
    local revision=Scene.revision
    local hash=GetHashKey(weapon)
    if not IsWeaponValid(hash)then return false end
    local model=GetWeapontypeModel(hash)
    if not model or model==0 or not IsModelInCdimage(model)then return false end
    RequestWeaponAsset(hash,31,0);RequestModel(model)
    local deadline=GetGameTimer()+3000
    while revision==Scene.revision and GetGameTimer()<deadline and (not HasWeaponAssetLoaded(hash)or not HasModelLoaded(model))do Wait(20)end
    if revision~=Scene.revision or not HasWeaponAssetLoaded(hash)or not HasModelLoaded(model)then
        RemoveWeaponAsset(hash);SetModelAsNoLongerNeeded(model);return false
    end
    Scene.bd=findBackdrop(Weapons.StudioBackdropId())
    if Scene.bd and Scene.bd.capture then captureBackdrop(revision)end
    if revision~=Scene.revision then RemoveWeaponAsset(hash);SetModelAsNoLongerNeeded(model);return false end
    local at=stagingPoint(PlayerPedId())
    -- The two final flags keep the model entirely local to this player's inspection scene.
    local object=CreateWeaponObject(hash,0,at.x,at.y,at.z,true,1.0,0,false,false)
    if not object or object==0 or not DoesEntityExist(object)then
        RemoveWeaponAsset(hash);SetModelAsNoLongerNeeded(model);return false
    end
    Scene.object,Scene.asset,Scene.model,Scene.weapon=object,hash,model,weapon
    SetEntityAsMissionEntity(object,true,true)
    Entity(object).state:set('bsProtected',true,false)
    SetEntityCoordsNoOffset(object,at.x,at.y,at.z,false,false,false)
    SetEntityHeading(object,0.0);SetEntityCollision(object,false,false)
    SetEntityVisible(object,true,false);SetEntityAlpha(object,255,false)
    SetEntityLodDist(object,250);FreezeEntityPosition(object,true)
    for _,id in pairs(fitted or {})do
        local part=Weapons.Attachments and Weapons.Attachments[id]
        local component=part and part.components and part.components[weapon]
        if component then GiveWeaponComponentToWeaponObject(object,GetHashKey(component))end
    end
    local low,high=GetModelDimensions(GetEntityModel(object))
    Scene.center=vec((low.x+high.x)*.5,(low.y+high.y)*.5,(low.z+high.z)*.5)
    Scene.fullCenter=vec(Scene.center.x,Scene.center.y,Scene.center.z)
    Scene.radius=math.max(.20,length(sub(high,low))*.5)
    Scene.distance=math.max(.85,(Scene.radius+.08)/math.sin(math.rad(FOV)*.5)*1.1)
    Scene.baseOrbit=(high.x-low.x)>(high.y-low.y)and 90 or 0
    Scene.orbit,Scene.elevation,Scene.zoom=Scene.baseOrbit,.08,1
    Scene.cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    if not Scene.cam or Scene.cam==0 or not DoesCamExist(Scene.cam)then Weapons.CloseStudio();return false end
    Scene.active=true
    SetCamFov(Scene.cam,FOV);SetCamNearClip(Scene.cam,.01)
    Scene.heading,Scene.homeOrbit=0,nil
    if isPlace(Scene.bd)then
        Scene.backdropSeq=(Scene.backdropSeq or 0)+1
        holdPlayer(true)
        if not placeAtBackdrop(Scene.bd,Scene.backdropSeq)then
            if revision~=Scene.revision then return false end
            Scene.bd=findBackdrop('black')
        end
    end
    frame();SetCamActive(Scene.cam,true);RenderScriptCams(true,false,0,true,true)
    Weapons.SetStudioTint(tint or 0,true)
    CreateThread(function()Wait(250);if Scene.active and Scene.revision==revision then pcall(Weapons.ProbeStudioStickerDepth)end end)
    return true
end
-- Picker in the workbench. Remembered per player in client KVP.
function Weapons.SetStudioBackdrop(id)
    local bd=findBackdrop(id);if not bd then return false end
    SetResourceKvp(BD_KEY,bd.id)
    if not Weapons.InspectionObject()then return true end
    Scene.backdropSeq=(Scene.backdropSeq or 0)+1
    local seq,revision=Scene.backdropSeq,Scene.revision
    releasePlace()
    if backdrop and backdrop.dui then DestroyDui(backdrop.dui)end;backdrop=nil
    Scene.bd=bd
    if isPlace(bd)then
        holdPlayer(true)
        CreateThread(function()
            if not placeAtBackdrop(bd,seq)and Scene.revision==revision and Scene.backdropSeq==seq then Scene.bd=findBackdrop('black')end
            frame()
        end)
        return true
    end
    holdPlayer(false)
    -- Back above the player, as the original studio did.
    local at=stagingPoint(PlayerPedId())
    SetEntityHeading(Scene.object,0.0);SetEntityCoordsNoOffset(Scene.object,at.x,at.y,at.z,false,false,false)
    Scene.heading,Scene.homeOrbit=0,nil
    Scene.center=Scene.fullCenter;Scene.orbit,Scene.zoom=Scene.baseOrbit or 0,1
    SetCamUseShallowDofMode(Scene.cam,false)
    if bd.capture then
        -- The captured frame has to show the world, so the scripted camera steps aside for one grab.
        CreateThread(function()RenderScriptCams(false,false,0,true,true);Wait(0);captureBackdrop(revision)
            if Scene.revision==revision and Scene.cam then RenderScriptCams(true,false,0,true,true)end end)
    end
    frame();return true
end
function Weapons.AdjustStudio(dx,dy,zoom,reset)
    if not Weapons.InspectionObject()then return false end
    if not finite(dx)or not finite(dy)or not finite(zoom)then return false end
    if reset then Scene.center=Scene.fullCenter;Scene.orbit,Scene.elevation,Scene.zoom=Scene.homeOrbit or Scene.baseOrbit or 0,.08,1
    else
        Scene.orbit=(Scene.orbit+clamp(dx,-150,150)*.4)%360
        Scene.elevation=clamp(Scene.elevation-dy*.003,-1.0,1.0)
        Scene.zoom=clamp(Scene.zoom*math.exp(zoom*.10),.35,4.5)
    end
    frame();return true
end
local function projectWorld(p)
    local origin,right,up,forward=cameraBasis();if not origin then return end
    local rel=sub(p,origin);local depth=dot(rel,forward)
    if depth<=.005 then return end
    local tan=math.tan(math.rad(GetCamFov(Scene.cam))*.5)
    local x=.5+dot(rel,right)/(2*depth*tan*GetAspectRatio(false))
    local y=.5-dot(rel,up)/(2*depth*tan)
    return {x=x,y=y,visible=x>=0 and x<=1 and y>=0 and y<=1}
end
function Weapons.ProjectStudioPoint(position)
    if not Weapons.InspectionObject()or type(position)~='table'then return nil end
    return projectWorld(world(position))
end
local function rayFromScreen(x,y)
    local origin,right,up,forward=cameraBasis()
    if not origin or not finite(x)or not finite(y)then return end
    local tan=math.tan(math.rad(GetCamFov(Scene.cam))*.5)
    local direction=unit(add(add(forward,mul(right,(2*x-1)*tan*GetAspectRatio(false))),mul(up,(1-2*y)*tan)))
    local a=localPoint(origin);local b=localPoint(add(origin,direction))
    return a,unit(sub(b,a))
end
local function planePoint(x,y,origin,normal)
    local from,direction=rayFromScreen(x,y);if not from then return end
    local denominator=dot(direction,normal)
    if math.abs(denominator)<.00001 then return end
    local distance=dot(sub(origin,from),normal)/denominator
    if distance<=0 then return end
    return add(from,mul(direction,distance))
end
local stickerAxes={}
-- Receiver thickness differs per model. Weapons.Stickers.depth[WEAPON_X] (metres, + = further out) moves both
-- side planes along their own normal so a sticker sits flush; /stickerdepth calibrates it live in the workbench.
-- Priority: /stickerdepth, then a measured value (shape test on the weapon's own collision), then config.
local liveDepth,measuredDepth,probed={}, {}, {}
-- Whole-weapon faces (defined further down, used by the probes here).
local autoCache,grids,gridBusy={}, {}, {}
local buildGrid,storeGrid,gridFor
local function depthFor(weapon)
    if not weapon then return 0 end
    if liveDepth[weapon]then return liveDepth[weapon]end
    if measuredDepth[weapon]==nil then
        local ok,v=pcall(GetResourceKvpFloat,'stickerDepth:'..weapon)
        local exists=ok and GetResourceKvpString('stickerDepthSet:'..weapon)=='1'
        measuredDepth[weapon]=exists and finite(v)and v or false
    end
    if measuredDepth[weapon]then return measuredDepth[weapon]end
    local d=Weapons.Stickers.depth and Weapons.Stickers.depth[weapon]
    return finite(d)and clamp(d,-.03,.03)or 0
end
local function basePlane(plane,object)
    local model=GetEntityModel(object)
    if stickerAxes[model]==nil then local low,high=GetModelDimensions(model);stickerAxes[model]=(high.x-low.x)>(high.y-low.y)*1.25 end
    if not stickerAxes[model]then return plane end
    local out={};for k,v in pairs(plane)do out[k]=v end
    for _,key in ipairs({'origin','axisU','axisV'})do local v=plane[key];out[key]={x=v.y,y=-v.x,z=v.z}end
    return out
end
-- Fires short rays at each receiver plane along its normal and keeps the median hit on the gun itself.
-- The sticker then sits on the measured surface instead of the hand-typed plane.
local function probeDepth(object,weapon)
    local planes=Weapons.Stickers.surfaces and Weapons.Stickers.surfaces[weapon]
    if not planes or not object or not DoesEntityExist(object)then return nil end
    SetEntityCollision(object,true,true);Wait(0);Wait(0)
    local values={}
    for _,raw in pairs(planes)do
        local plane=basePlane(raw,object)
        local n=unit(cross(plane.axisU,plane.axisV))
        for _,u in ipairs({-.6,-.2,.2,.6})do for _,v in ipairs({-.4,.4})do
            local p=add(plane.origin,add(mul(plane.axisU,u*plane.halfWidth),mul(plane.axisV,v*plane.halfHeight)))
            local a=GetOffsetFromEntityInWorldCoords(object,p.x+n.x*.06,p.y+n.y*.06,p.z+n.z*.06)
            local b=GetOffsetFromEntityInWorldCoords(object,p.x-n.x*.04,p.y-n.y*.04,p.z-n.z*.04)
            local ray=StartExpensiveSynchronousShapeTestLosProbe(a.x,a.y,a.z,b.x,b.y,b.z,16,0,7)
            local _,hit,coords,_,entity=GetShapeTestResult(ray)
            if (hit==true or hit==1)and entity==object then
                local l=GetOffsetFromEntityGivenWorldCoords(object,coords.x,coords.y,coords.z)
                values[#values+1]=dot(sub(vec(l.x,l.y,l.z),p),n)
            end
        end end
    end
    if DoesEntityExist(object)then SetEntityCollision(object,false,false)end
    if #values<4 then return nil end
    table.sort(values)
    local median=values[math.floor(#values/2)+1]
    -- Outside this window the collision box is not the visible receiver; keep the configured plane.
    if median<-.025 or median>.012 then return nil end
    return median+.0004
end
local function storeDepth(weapon,value,source)
    measuredDepth[weapon]=value
    SetResourceKvpFloat('stickerDepth:'..weapon,value);SetResourceKvp('stickerDepthSet:'..weapon,'1')
    print(('[bs_weapons] sticker surface for %s measured %s: %.1f mm from the configured plane'):format(weapon,source,value*1000))
end
function Weapons.ProbeStudioStickerDepth(force)
    local object,weapon=Weapons.InspectionObject(),Scene.weapon
    if not object or not weapon or (probed[weapon]and not force)then return end
    probed[weapon]=true
    if Weapons.StickerSurfacesAuto and Weapons.StickerSurfacesAuto(weapon)then
        local grid=buildGrid(object,weapon);if grid then storeGrid(weapon,grid,'in the workbench')end
        return
    end
    local value=probeDepth(object,weapon)
    if value then storeDepth(weapon,value,'in the workbench')end
end
-- Same measurement for weapons seen in other players' hands, on a short-lived local copy far above the player.
function Weapons.EnsureStickerDepth(weapon)
    if not weapon or probed[weapon]then return end
    local auto=Weapons.StickerSurfacesAuto and Weapons.StickerSurfacesAuto(weapon)
    if auto and gridFor(weapon)then probed[weapon]=true;return end
    if not auto and (liveDepth[weapon]or depthFor(weapon)~=(Weapons.Stickers.depth and Weapons.Stickers.depth[weapon]or 0))then return end
    probed[weapon]=true
    CreateThread(function()
        local hash=GetHashKey(weapon)
        if not HasWeaponAssetLoaded(hash)then return end
        local at=GetEntityCoords(PlayerPedId())
        local object=CreateWeaponObject(hash,0,at.x,at.y,at.z+60.0,false,1.0,0,false,false)
        if not object or object==0 then return end
        SetEntityVisible(object,false,false);FreezeEntityPosition(object,true)
        if auto then
            gridBusy[weapon]=true
            local ok,grid=pcall(buildGrid,object,weapon)
            gridBusy[weapon]=nil
            if DoesEntityExist(object)then DeleteEntity(object)end
            if ok and grid then storeGrid(weapon,grid,'on a held weapon')end
            return
        end
        local ok,value=pcall(probeDepth,object,weapon)
        if DoesEntityExist(object)then DeleteEntity(object)end
        if ok and value then storeDepth(weapon,value,'on a held weapon')end
    end)
end
local function weaponOfPlane(plane)
    for weapon,list in pairs(Weapons.Stickers.surfaces or {})do for _,p in pairs(list)do if p==plane then return weapon end end end
end
-- Whole-weapon sticker faces. Planes marked auto ('left', 'right', 'top', 'bottom') are built from the model's
-- bounding box, then a grid of short rays against the gun's own collision measures where the real surface is,
-- so a sticker sits on the mesh (0.2 mm proud) instead of on the box.
local GRID_U,GRID_V=16,6
local function axis(name,sign)local v=vec(0,0,0);v[name]=sign;return v end
local function autoPlane(plane,model)
    local key=model..':'..plane.auto
    local cached=autoCache[key]
    if cached then return cached end
    local low,high=GetModelDimensions(model)
    local longX=(high.x-low.x)>=(high.y-low.y)
    local L,T=longX and 'x'or 'y',longX and 'y'or 'x'
    local c=vec((low.x+high.x)*.5,(low.y+high.y)*.5,(low.z+high.z)*.5)
    local n,u,v,origin,eu,ev
    local halfL=(high[L]-low[L])*.5
    if plane.auto=='left'or plane.auto=='right'then
        local sign=plane.auto=='right'and 1 or -1
        n=axis(T,sign);v=axis('z',1);u=cross(v,n)
        origin=vec(c.x,c.y,c.z);origin[T]=sign>0 and high[T]or low[T]
        eu,ev=halfL,(high.z-low.z)*.5
    else
        local sign=plane.auto=='top'and 1 or -1
        n=axis('z',sign);u=axis(L,1);v=cross(n,u)
        origin=vec(c.x,c.y,sign>0 and high.z or low.z)
        eu,ev=halfL,(high[T]-low[T])*.5
    end
    local out={};for k,val in pairs(plane)do out[k]=val end
    out.origin,out.axisU,out.axisV,out.extentU,out.extentV=origin,u,v,eu,ev
    out.thickness=dot(sub(high,low),vec(math.abs(n.x),math.abs(n.y),math.abs(n.z)))
    out.depthOffset=0;out.modelAxes=true
    autoCache[key]=out
    return out
end
buildGrid=function(object,weapon)
    local planes=Weapons.Stickers.surfaces and Weapons.Stickers.surfaces[weapon]
    if not planes or not object or not DoesEntityExist(object)then return nil end
    local model=GetEntityModel(object)
    SetEntityCollision(object,true,true);Wait(0);Wait(0)
    local out,hits={faces={}},0
    for id,raw in pairs(planes)do if raw.auto then
        local plane=autoPlane(raw,model)
        local n=unit(cross(plane.axisU,plane.axisV))
        local face={}
        for i=0,GRID_U-1 do face[i]={}
            for j=0,GRID_V-1 do
                local su=((i+.5)/GRID_U*2-1)*plane.extentU*.98
                local sv=((j+.5)/GRID_V*2-1)*plane.extentV*.98
                local p=add(plane.origin,add(mul(plane.axisU,su),mul(plane.axisV,sv)))
                local a=GetOffsetFromEntityInWorldCoords(object,p.x+n.x*.05,p.y+n.y*.05,p.z+n.z*.05)
                local depth=plane.thickness+.01
                local b=GetOffsetFromEntityInWorldCoords(object,p.x-n.x*depth,p.y-n.y*depth,p.z-n.z*depth)
                local _,hit,coords,_,entity=GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(a.x,a.y,a.z,b.x,b.y,b.z,16,0,7))
                if (hit==true or hit==1)and entity==object then
                    local l=GetOffsetFromEntityGivenWorldCoords(object,coords.x,coords.y,coords.z)
                    face[i][j]=dot(sub(vec(l.x,l.y,l.z),p),n);hits=hits+1
                else face[i][j]=false end
            end
        end
        out.faces[id]=face
    end end
    if DoesEntityExist(object)then SetEntityCollision(object,false,false)end
    out.hits=hits
    return out
end
storeGrid=function(weapon,grid,source)
    grids[weapon]=grid
    pcall(SetResourceKvp,'stickerGrid1:'..weapon,json.encode(grid))
    print(('[bs_weapons] sticker surface for %s measured %s: %d of %d points hit the gun'):format(weapon,source,grid.hits or 0,GRID_U*GRID_V*4))
end
gridFor=function(weapon)
    if grids[weapon]==nil then
        local raw=GetResourceKvpString('stickerGrid1:'..weapon)
        local ok,data=pcall(function()return raw and json.decode(raw)end)
        grids[weapon]=ok and type(data)=='table'and data.faces and data or false
    end
    return grids[weapon]or nil
end
-- Depth of the real surface under a sticker footprint (outermost hit), relative to the face. nil = unmeasured.
local function surfaceDepth(weapon,surface,plane,cu,cv,extent)
    local grid=gridFor(weapon);local face=grid and grid.faces and grid.faces[surface]
    if not face then return nil end
    local function cell(value,size,count)return math.floor(((value/size)+1)*.5*count)end
    local best
    for r=0,2 do
        local i0,i1=cell(cu-extent,plane.extentU,GRID_U)-r,cell(cu+extent,plane.extentU,GRID_U)+r
        local j0,j1=cell(cv-extent,plane.extentV,GRID_V)-r,cell(cv+extent,plane.extentV,GRID_V)+r
        for i=math.max(0,i0),math.min(GRID_U-1,i1)do
            local col=face[i]or face[tostring(i)]
            if col then for j=math.max(0,j0),math.min(GRID_V-1,j1)do
                local d=col[j]or col[tostring(j)]
                if type(d)=='number'and (not best or d>best)then best=d end
            end end
        end
        if best then return best end
    end
    return nil
end
-- Corners of a sticker in the weapon's local space, clamped to the face and pushed onto the measured surface.
function Weapons.StickerQuadCorners(plane,entry,weapon)
    if not plane or not plane.extentU then return Weapons.StickerCorners(plane,entry)end
    local angle=math.rad(entry.rotation or 0)
    local half=(entry.size or .03)*.5
    local extent=half*(math.abs(math.cos(angle))+math.abs(math.sin(angle)))
    local cu=clamp((entry.u or 0)*plane.halfWidth,-math.max(0,plane.extentU-extent),math.max(0,plane.extentU-extent))
    local cv=clamp((entry.v or 0)*plane.halfHeight,-math.max(0,plane.extentV-extent),math.max(0,plane.extentV-extent))
    local n=unit(cross(plane.axisU,plane.axisV))
    local depth=(surfaceDepth(weapon,entry.surface,plane,cu,cv,extent)or 0)+.0002+(liveDepth[weapon]or 0)
    local cos,sin=math.cos(angle),math.sin(angle)
    local corners={}
    for i,p in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}})do
        local u=cu+half*(p[1]*cos-p[2]*sin)
        local v=cv+half*(p[1]*sin+p[2]*cos)
        corners[i]=add(add(plane.origin,add(mul(plane.axisU,u),mul(plane.axisV,v))),mul(n,depth))
    end
    return corners
end
function Weapons.StickerGridBusy(weapon)return gridBusy[weapon]==true end
function Weapons.ResolveStickerPlane(plane,object)
    if not plane or plane.modelAxes then return plane end
    object=object or Weapons.InspectionObject()
    if not object or not DoesEntityExist(object)then return plane end
    local model=GetEntityModel(object)
    if plane.auto then return autoPlane(plane,model)end
    if stickerAxes[model]==nil then
        local low,high=GetModelDimensions(model)
        stickerAxes[model]=(high.x-low.x)>(high.y-low.y)*1.25
    end
    local out={};for key,value in pairs(plane)do out[key]=value end
    if stickerAxes[model]then
        for _,key in ipairs({'origin','axisU','axisV'})do local v=plane[key];out[key]={x=v.y,y=-v.x,z=v.z}end
    end
    local depth=depthFor(plane.weapon or weaponOfPlane(plane))
    if depth~=0 then
        local normal=unit(cross(out.axisU,out.axisV))
        out.origin=add(out.origin,mul(normal,depth))
    end
    return out
end
RegisterCommand('stickerdepth',function(_,args)
    local weapon=Scene.active and Scene.weapon
    if not weapon then print('[bs_weapons] open the weapon workbench first');return end
    local mm=tonumber(args[1])
    if args[1]=='auto'then liveDepth[weapon]=nil;probed[weapon]=nil;measuredDepth[weapon]=nil;grids[weapon]=nil;DeleteResourceKvp('stickerDepthSet:'..weapon);DeleteResourceKvp('stickerGrid1:'..weapon);CreateThread(function()pcall(Weapons.ProbeStudioStickerDepth,true)end)
    elseif mm then liveDepth[weapon]=clamp(mm/1000,-.03,.03)end
    print(('[bs_weapons] sticker depth for %s: %.1f mm. Config line: Weapons.Stickers.depth.%s = %.4f')
        :format(weapon,depthFor(weapon)*1000,weapon,depthFor(weapon)))
end,false)
-- How squarely a face looks at the camera (1 = straight on, 0 = edge on, < 0 = facing away).
function Weapons.StudioSurfaceFacingAmount(plane)
    local origin=cameraBasis()
    if not origin or not plane then return -1 end
    local normal=unit(cross(plane.axisU,plane.axisV))
    return dot(unit(sub(localPoint(origin),plane.origin)),normal)
end
function Weapons.StudioSurfaceFacing(plane)
    local origin=cameraBasis()
    if not origin or not plane then return false end
    local normal=unit(cross(plane.axisU,plane.axisV))
    return dot(sub(localPoint(origin),plane.origin),normal)>.0001
end
function Weapons.FaceStickerSurface(plane)
    if not Weapons.InspectionObject()or not plane then return false end
    local normal=unit(cross(plane.axisU,plane.axisV))
    if math.abs(normal.z)>.7 then
        -- Top or bottom face: look down (or up) at it from the current side.
        Scene.elevation=normal.z>0 and .95 or -.95
    else
        Scene.orbit=(math.deg(math.atan(normal.y,-normal.x))-(Scene.heading or 0))%360
        Scene.elevation=.04
    end
    Scene.zoom=.60
    local o=plane.origin;if plane.extentU then o=add(o,mul(unit(cross(plane.axisU,plane.axisV)),-(plane.thickness or 0)*.5))end
    Scene.center=vec(o.x,o.y,o.z)
    frame();return true
end
function Weapons.StudioPlanePoint(x,y,plane)
    if not Weapons.InspectionObject()or type(plane)~='table'then return nil end
    local normal=unit(cross(plane.axisU,plane.axisV))
    local hit=planePoint(x,y,plane.origin,normal)
    if not hit then return nil end
    local delta=sub(hit,plane.origin)
    return {u=dot(delta,plane.axisU)/plane.halfWidth,v=dot(delta,plane.axisV)/plane.halfHeight}
end
function Weapons.MoveStudioMount(position,dx,dy,viewportHeight,depth)
    local object=Weapons.InspectionObject();local origin,right,up,forward=cameraBasis()
    if not object or not origin then return nil end
    local at=world(position);local distance=length(sub(at,origin))
    local units=2*distance*math.tan(math.rad(GetCamFov(Scene.cam))*.5)/math.max(300,viewportHeight)
    local delta=depth and mul(forward,dy*units)or add(mul(right,dx*units),mul(up,-dy*units))
    local p=localPoint(add(at,delta))
    local limit=Weapons.Cosmetics and Weapons.Cosmetics.maxOffset or .75
    return vec(clamp(p.x,-limit,limit),clamp(p.y,-limit,limit),clamp(p.z,-limit,limit))
end
-- Native attachment order 2: ZXY Euler angles are stored, quaternions are used while dragging.
local function quaternion(rotation)
    local x,y,z=math.rad(rotation.x)*.5,math.rad(rotation.y)*.5,math.rad(rotation.z)*.5
    local cx,cy,cz,sx,sy,sz=math.cos(x),math.cos(y),math.cos(z),math.sin(x),math.sin(y),math.sin(z)
    return {x=sx*cy*cz-cx*sy*sz,y=cx*sy*cz+sx*cy*sz,z=cx*cy*sz+sx*sy*cz,w=cx*cy*cz-sx*sy*sz}
end
local function multiply(a,b)
    return {x=a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,y=a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        z=a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,w=a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z}
end
local function axisAngle(axis,degrees)
    local n=length(axis);if n<.00001 then return{x=0,y=0,z=0,w=1}end
    local half=math.rad(degrees)*.5;local scale=math.sin(half)/n
    return{x=axis.x*scale,y=axis.y*scale,z=axis.z*scale,w=math.cos(half)}
end
local function euler(q)
    local n=math.sqrt(q.x^2+q.y^2+q.z^2+q.w^2)
    local x,y,z,w=q.x/n,q.y/n,q.z/n,q.w/n
    local m11,m12,m21,m22=1-2*(y*y+z*z),2*(x*y-z*w),2*(x*y+z*w),1-2*(x*x+z*z)
    local m31,m32,m33=2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)
    local rx=math.asin(clamp(m32,-1,1));local ry,rz
    if math.abs(m32)<.9999999 then ry,rz=math.atan(-m31,m33),math.atan(-m12,m22)
    else ry,rz=0,math.atan(m21,m11)end
    return vec(math.deg(rx),math.deg(ry),math.deg(rz))
end
local function rotate(q,v)
    local t=mul(cross(vec(q.x,q.y,q.z),v),2)
    return add(v,add(mul(t,q.w),cross(vec(q.x,q.y,q.z),t)))
end
local function localDirection(v)
    local origin=GetEntityCoords(Scene.object)
    return localPoint(add(vec(origin.x,origin.y,origin.z),v))
end
function Weapons.RotateStudioMount(rotation,dx,dy,roll)
    local _,right,up,forward=cameraBasis()
    if not Weapons.InspectionObject()or not right then return nil end
    local delta=roll and axisAngle(localDirection(forward),dx*.35)or multiply(axisAngle(localDirection(up),dx*.35),axisAngle(localDirection(right),dy*.35))
    return euler(multiply(delta,quaternion(rotation)))
end
local function dimensions(opts)
    local height=math.max(300,tonumber(opts and opts.height)or select(2,GetActiveScreenResolution()))
    return height*GetAspectRatio(false),height
end
local function gizmoLength(position,opts)
    local origin=cameraBasis();if not origin then return .15 end
    local _,height=dimensions(opts)
    return 64*2*length(sub(world(position),origin))*math.tan(math.rad(GetCamFov(Scene.cam))*.5)/height
end
function Weapons.StudioGizmo(transform,mode)
    if not Weapons.InspectionObject()or type(transform)~='table'or not transform.position or not transform.rotation then return nil end
    mode=mode=='rotate'and 'rotate'or mode=='scale'and 'scale'or 'move'
    local center=Weapons.ProjectStudioPoint(transform.position)
    if not center or not center.visible then return {center=center,handles={}}end
    local size=gizmoLength(transform.position)
    local handles={};local q=quaternion(transform.rotation)
    for _,name in ipairs({'x','y','z'})do
        local axis=mode=='rotate'and rotate(q,AXES[name])or AXES[name]
        local finish=Weapons.ProjectStudioPoint(add(transform.position,mul(axis,size)))
        local width,height=dimensions()
        local screenLength=finish and ((finish.x-center.x)*width)^2+((finish.y-center.y)*height)^2 or 0
        if finish and finish.visible and (mode=='rotate'or screenLength>36)then
            local handle={axis=name,x=finish.x,y=finish.y,type=mode,color=COLORS[name],visible=true}
            if mode=='rotate'then
                local u=rotate(q,AXES[name=='x'and 'y'or 'x'])
                local v=unit(cross(axis,u));handle.points={}
                for step=0,48 do
                    local a=step/48*math.pi*2
                    local point=Weapons.ProjectStudioPoint(add(transform.position,mul(add(mul(u,math.cos(a)),mul(v,math.sin(a))),size)))
                    if not point or not point.visible then handle.points=nil;break end
                    handle.points[#handle.points+1]={x=point.x,y=point.y}
                end
            end
            handles[#handles+1]=handle
        end
    end
    if mode=='move'then
        for _,names in ipairs({'xy','xz','yz'})do
            local points={};local valid=true
            for _,offset in ipairs({{.24,.24},{.48,.24},{.48,.48},{.24,.48}})do
                local p=Weapons.ProjectStudioPoint(add(transform.position,add(mul(AXES[names:sub(1,1)],size*offset[1]),mul(AXES[names:sub(2,2)],size*offset[2]))))
                if not p or not p.visible then valid=false;break end
                points[#points+1]={x=p.x,y=p.y}
            end
            if valid then
                local area=0;for i=1,4 do local a,b=points[i],points[i%4+1];area=area+a.x*b.y-b.x*a.y end
                local width,height=dimensions()
                if math.abs(area)*width*height>24 then handles[#handles+1]={axis=names,type='plane',x=points[3].x,y=points[3].y,points=points}end
            end
        end
    end
    return {center={x=center.x,y=center.y},handles=handles}
end
local function snapped(value,step)return math.floor(value/step+.5)*step end
function Weapons.GizmoDrag(transform,mode,axis,dx,dy,opts)
    if not Weapons.InspectionObject()or type(transform)~='table'or not transform.position or not transform.rotation
        or not finite(dx)or not finite(dy)or (not AXES[axis]and not (mode=='move'and (axis=='xy'or axis=='xz'or axis=='yz')))then return nil end
    opts=opts or {};local out=copyTransform(transform);local fine=opts.fine and .15 or 1
    dx,dy=clamp(dx,-8192,8192),clamp(dy,-8192,8192)
    if mode=='move'and #axis==2 then
        if not finite(opts.x)or not finite(opts.y)then return nil end
        local first,second=axis:sub(1,1),axis:sub(2,2)
        local normal=cross(AXES[first],AXES[second]);local width,height=dimensions(opts)
        local before=planePoint(opts.x-dx/width,opts.y-dy/height,out.position,normal)
        local after=planePoint(opts.x,opts.y,out.position,normal)
        if not before or not after then return nil end
        local delta=sub(after,before);local limit=Weapons.Cosmetics and Weapons.Cosmetics.maxOffset or .75
        for _,name in ipairs({first,second})do
            local value=out.position[name]+delta[name]*fine
            if opts.snap then value=snapped(value,.01)end
            out.position[name]=clamp(value,-limit,limit)
        end
        return out
    end
    if mode=='scale'then
        out.scale=clamp(out.scale*math.exp((dx-dy)*.007*fine),.5,1.5)
        if opts.snap then out.scale=clamp(snapped(out.scale,.05),.5,1.5)end
    elseif mode=='rotate'then
        local q=quaternion(out.rotation);local normal=rotate(q,AXES[axis]);local degrees
        if finite(opts.x)and finite(opts.y)then
            local width,height=dimensions(opts)
            local before=planePoint(opts.x-dx/width,opts.y-dy/height,out.position,normal)
            local after=planePoint(opts.x,opts.y,out.position,normal)
            if before and after then
                local a,b=unit(sub(before,out.position)),unit(sub(after,out.position))
                degrees=math.deg(math.atan(dot(normal,cross(a,b)),clamp(dot(a,b),-1,1)))*fine
            end
        end
        degrees=degrees or (dx-dy)*.35*fine
        if opts.snap then degrees=snapped(degrees,15)end
        out.rotation=euler(multiply(q,axisAngle(AXES[axis],degrees)))
    else
        local size=gizmoLength(out.position,opts)
        local start=Weapons.ProjectStudioPoint(out.position)
        local finish=Weapons.ProjectStudioPoint(add(out.position,mul(AXES[axis],size)))
        if not start or not finish then return nil end
        local width,height=dimensions(opts)
        local sx,sy=(finish.x-start.x)*width,(finish.y-start.y)*height
        local pixels=sx*sx+sy*sy
        local amount
        if finite(opts.x)and finite(opts.y)then
            local origin=cameraBasis()
            local view=unit(sub(localPoint(origin),out.position))
            local direction=AXES[axis]
            local normal=unit(sub(view,mul(direction,dot(view,direction))))
            if length(normal)>.0001 then
                local before=planePoint(opts.x-dx/width,opts.y-dy/height,out.position,normal)
                local after=planePoint(opts.x,opts.y,out.position,normal)
                if before and after then amount=dot(sub(after,before),direction)*fine end
            end
        end
        amount=amount or (pixels>16 and (dx*sx+dy*sy)/pixels*size*fine or -dy*size/64*fine)
        local limit=Weapons.Cosmetics and Weapons.Cosmetics.maxOffset or .75
        out.position[axis]=clamp(out.position[axis]+amount,-limit,limit)
        if opts.snap then out.position[axis]=clamp(snapped(out.position[axis],.01),-limit,limit)end
    end
    return out
end
function Weapons.StudioMuzzle()
    local object=Weapons.InspectionObject();if not object then return nil end
    local bone=GetEntityBoneIndexByName(object,'gun_muzzle');if bone<0 then return nil end
    local p=GetWorldPositionOfEntityBone(object,bone);local at=localPoint(vec(p.x,p.y,p.z))
    return {position=vec(clamp(at.x,-.75,.75),clamp(at.y,-.75,.75),clamp(at.z-.025,-.75,.75)),rotation=vec(90,0,0),scale=1}
end
function Weapons.ApplyCosmeticScale(object,scale,baseScale)
    if not object or not DoesEntityExist(object)or not finite(scale)then return false end
    baseScale=finite(baseScale)and clamp(baseScale,.02,2.0)or 1.0
    scale=clamp(scale,.5,1.5)*baseScale
    local forward,right,up,position=GetEntityMatrix(object)
    forward,right,up=mul(unit(forward),scale),mul(unit(right),scale),mul(unit(up),scale)
    SetEntityMatrix(object,forward.x,forward.y,forward.z,right.x,right.y,right.z,up.x,up.y,up.z,position.x,position.y,position.z)
    return true
end
local function veil(origin,right,up,forward)
    -- A dark see-through sheet just behind the gun: darkens the place, never the weapon in front of it.
    local target=world(Scene.fullCenter or Scene.center)
    local depth=length(sub(target,origin))+(Scene.radius or .3)+.25
    local mid=add(origin,mul(forward,depth))
    local h=depth*math.tan(math.rad(GetCamFov(Scene.cam))*.5)*1.4
    local w=h*GetAspectRatio(false)*1.2
    local a=add(sub(mid,mul(right,w)),mul(up,-h));local b=add(add(mid,mul(right,w)),mul(up,-h))
    local c=add(add(mid,mul(right,w)),mul(up,h));local d=add(sub(mid,mul(right,w)),mul(up,h))
    local tint=Scene.bd.tint or {8,9,8}
    local alpha=math.floor(clamp(Scene.bd.darkness or .75,0,1)*255+.5)
    local function tri(x,y,z)DrawPoly(x.x,x.y,x.z,y.x,y.y,y.z,z.x,z.y,z.z,tint[1],tint[2],tint[3],alpha)end
    tri(a,b,c);tri(a,c,d);tri(c,b,a);tri(d,c,a)
    SetUseHiDof()
end
local function background()
    local origin,right,up,forward=cameraBasis();if not origin then return end
    local target=world(Scene.center);local distance=length(sub(target,origin))
    if isPlace(Scene.bd)then
        veil(origin,right,up,forward)
        DrawLightWithRange(target.x-.8,target.y-.4,target.z+.7,235,231,213,6.0,2.5)
        DrawLightWithRange(target.x+.5,target.y+.5,target.z+.2,157,178,191,4.0,1.0)
        return
    end
    local center=add(target,mul(forward,3))
    local width,height=math.max(8,distance*GetAspectRatio(false)),math.max(6,distance)
    local a=add(sub(center,mul(right,width)),mul(up,-height))
    local b=add(add(center,mul(right,width)),mul(up,-height))
    local c=add(add(center,mul(right,width)),mul(up,height))
    local d=add(sub(center,mul(right,width)),mul(up,height))
    if backdrop and backdrop.ready then
        local function textured(x,y,z,ua,va,ub,vb,uc,vc)
            Citizen.InvokeNative(0x29280002282F1928,x.x+0.0,x.y+0.0,x.z+0.0,y.x+0.0,y.y+0.0,y.z+0.0,z.x+0.0,z.y+0.0,z.z+0.0,
                255,255,255,255,'bs_weapon_backdrop',backdrop.txn,ua+0.0,va+0.0,1.0,ub+0.0,vb+0.0,1.0,uc+0.0,vc+0.0,1.0)
        end
        textured(a,b,c,0,1,1,1,1,0);textured(a,c,d,0,1,1,0,0,0)
        textured(c,b,a,1,0,1,1,0,1);textured(d,c,a,0,0,1,0,0,1)
    else
        local function triangle(x,y,z)DrawPoly(x.x,x.y,x.z,y.x,y.y,y.z,z.x,z.y,z.z,17,21,18,255)end
        triangle(a,b,c);triangle(a,c,d);triangle(c,b,a);triangle(d,c,a)
    end
    DrawLightWithRange(target.x-.8,target.y-.4,target.z+.7,235,231,213,6.0,2.5)
    DrawLightWithRange(target.x+.5,target.y+.5,target.z+.2,157,178,191,4.0,1.0)
end
CreateThread(function()
    while true do
        Wait(Scene.active and 0 or 250)
        if Scene.active then
            local ped=PlayerPedId()
            if not Weapons.InspectionObject()or IsEntityDead(ped)then
                Weapons.CloseStudio();TriggerEvent('bs:weapons:studioClosed')
            else
                frame();background();HideHudAndRadarThisFrame()
                SetEntityLocallyInvisible(ped)
                local held=GetCurrentPedWeaponEntityIndex(ped,0)
                if held and held~=0 and held~=Scene.object then SetEntityLocallyInvisible(held)end
            end
        end
    end
end)
AddEventHandler('bs:hook:player:unloaded',function()Weapons.CloseStudio();TriggerEvent('bs:weapons:studioClosed')end)
AddEventHandler('onResourceStop',function(res)if res==GetCurrentResourceName()then Weapons.CloseStudio()end end)
