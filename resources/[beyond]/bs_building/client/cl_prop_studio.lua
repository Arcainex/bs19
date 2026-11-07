-- BS19 Bau-Editor: mouse axis handles, orbit camera, server-authoritative save.
-- NEVER changes GTA model scale, collision mesh or model bounds.
local active, editorCam, editorObject, hiddenPed = false, nil, nil, nil
local input = {x=.5,y=.5,dx=0,dy=0,left=false,right=false,pressed=false,keys={}}
RegisterNUICallback('studioInput', function(data, cb)
    input.x=tonumber(data.x) or input.x;input.y=tonumber(data.y) or input.y
    input.dx=(input.dx or 0)+(tonumber(data.dx) or 0);input.dy=(input.dy or 0)+(tonumber(data.dy) or 0)
    input.pressed=data.down == true;input.left=data.left == true;input.right=data.right == true
    if data.key then input.keys[data.key]=true end
    cb({ok=true})
end)
local function notify(s,kind) TriggerEvent('bs:ui:notify',{type=kind or 'info',message=s,duration=5000}) end
local function report(s)
    print('^1[BS19 BAUEN EDITOR] '..tostring(s)..'^7')
    notify('Bauen (Prop Editor): '..tostring(s),'error')
    TriggerEvent('bs:admin:propStudioError',tostring(s))
end
local function label(x,y,t,scale,r,g,b)
    SetTextFont(4); SetTextScale(scale or .31,scale or .31); SetTextColour(r or 219,g or 239,b or 225,255)
    SetTextOutline(); SetTextEntry('STRING'); AddTextComponentString(t); DrawText(x,y)
end
local function screen(v) local ok,x,y=GetScreenCoordFromWorldCoord(v.x,v.y,v.z); return ok,x,y end
local axis={{1,0,0,230,90,90},{0,1,0,80,225,128},{0,0,1,88,157,240}}
local function cleanup()
    active=false
    SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
    if editorCam then RenderScriptCams(false,true,250,true,true); DestroyCam(editorCam,false); editorCam=nil end
    if editorObject and DoesEntityExist(editorObject) then DeleteEntity(editorObject) end
    editorObject=nil
    if hiddenPed and DoesEntityExist(hiddenPed) then SetEntityVisible(hiddenPed,true,false); ResetEntityAlpha(hiddenPed) end
    hiddenPed=nil
end
-- World-space gizmo, screen-space hit testing. No entity scaling or bounds edits.
local function edit(def)
    if active then return end
    if GetResourceState('bs_gizmo') ~= 'started' then
        return report('bs_gizmo nicht gestartet. Original-Gizmo installieren und ensure bs_gizmo vor bs_building starten.')
    end
    if type(def) ~= 'table' or type(def.model) ~= 'string' or def.model == '' then
        return report('Kein gueltiges Modell gewaehlt')
    end
    local hash = GetHashKey(def.model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return report('Modell nicht vorhanden: '..def.model)
    end
    if not Building.LoadModel(hash) then return report('Modell konnte nicht geladen werden: '..def.model) end

    local ped = PlayerPedId()
    local p = GetOffsetFromEntityInWorldCoords(ped,0,4.0,0)
    local found,ground = GetGroundZFor_3dCoord(p.x,p.y,p.z+12.0,false)
    local base = vector3(p.x,p.y,found and ground or p.z)
    local off = def.offset or {0,0,0}
    local rr = def.rotation or {0,0,0}
    local pos = {tonumber(off[1]) or 0,tonumber(off[2]) or 0,tonumber(off[3]) or 0}
    local rot = {tonumber(rr[1]) or 0,tonumber(rr[2]) or 0,tonumber(rr[3]) or 0}
    local obj = CreateObjectNoOffset(hash,base.x,base.y,base.z,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(obj) then return report('Vorschauobjekt konnte nicht erstellt werden: '..def.model..' | Hash '..tostring(hash)..'. Modell-Stream/YDR/YTYP pruefen; bei Kenney-Drehtuer sicheren BVH-Export verwenden.') end
    editorObject = obj
    active = true
    hiddenPed = ped
    SetEntityVisible(ped,false,false)
    SetEntityCollision(obj,false,false)
    FreezeEntityPosition(obj,true)
    SetEntityAlpha(obj,230,false)
    -- Match the F2 placement origin exactly. Align accounts for the real model dimensions.
    -- F2 and world spawns use Building.Align with the definition ID.
    -- The old code called Align without the ID, then added the old offset a
    -- second time. This made "original" edits drift after saving.
    local currentDef = Building.Pieces[def.id] or {}
    local defaultPitch = tonumber(currentDef.pitch) or 0.0
    if not def.create then
        Building.Align(obj,base.x,base.y,base.z,0.0,defaultPitch,def.id)
    else
        Building.Align(obj,base.x,base.y,base.z,0.0,defaultPitch,def.id,
            {offset=pos,rotation=rot})
    end

    -- Third-party gizmo owns mouse, orbit camera and 3D handles. No BS19 fake arrows.
    local settings = type(def.settings)=='table' and def.settings or {}
    local colors = {lime={175,255,45},green={105,205,115},white={255,255,255}}
    local boundsColor = colors[settings.boundsColor] or colors.lime
    local gizmoSize = math.max(0.5,math.min(1.5,tonumber(settings.gizmoSize) or 0.85))
    local ok,result = pcall(function()
        return exports.bs_gizmo:useGizmo(obj, {
            camera = 'orbit', mode = 'translate', space = 'world', pivot = 'center',
            enableScale = false, enableTranslate = true, enableRotate = true,
            modeToggle = true, enableCopy = false, snapToGround = false,
            prompts = false, showCoords = false,
            outline = false, showModelBounds = settings.showBounds ~= false, bs19Hud = true,
            bs19BoundsColor = boundsColor, snap = settings.defaultGrid == true,
            gizmoSize = gizmoSize,
        })
    end)
    if not ok then cleanup(); return report('bs_gizmo: '..tostring(result)) end
    if not result or result.cancelled or result.confirmed == false then
        cleanup(); notify('Prop-Bearbeitung verworfen'); return
    end
    if not DoesEntityExist(obj) then cleanup(); return report('Gizmo-Vorschauobjekt nicht mehr vorhanden') end
    local finalCoords = GetEntityCoords(obj)
    local finalRotation = GetEntityRotation(obj,2)
    -- Use the same final rotation as F2. The studio rotation is an offset
    -- relative to the definition's pitch, not an absolute GTA transform.
    local finalRot = {finalRotation.x-defaultPitch,finalRotation.y,finalRotation.z}
    Building.Align(obj,base.x,base.y,base.z,0.0,defaultPitch,def.id,
        {offset={0,0,0},rotation=finalRot})
    local aligned = GetEntityCoords(obj)
    local finalOffset = {finalCoords.x-aligned.x,finalCoords.y-aligned.y,finalCoords.z-aligned.z}
    cleanup()
    local payload = {id=def.id,label=def.label,model=def.model,cat=def.cat,
        size=def.size,offset=finalOffset,rotation=finalRot,create=def.create,cost=def.cost,tested=true}
    local response = BSB.Await('build:studio:save',15000,payload)
    if response and response.ok then
        if response.definition then Building.Pieces[def.id] = response.definition end
        notify('Prop gespeichert – F2-Katalog aktualisiert','success')
    else report(response and response.error or 'Speichern: Keine Serverantwort') end
end
RegisterNetEvent('bs:building:studio:edit',function(def)
    CreateThread(function()
        local ok,err=xpcall(function() edit(def) end,debug.traceback)
        if not ok then cleanup();report(err) end
        -- Return to the F10 editor after confirm, cancel, or a preview error.
        TriggerEvent('bs:admin:propStudioReturn')
    end)
end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then cleanup() end end)
