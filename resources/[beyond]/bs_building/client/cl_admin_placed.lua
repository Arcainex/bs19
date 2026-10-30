-- Edit an individual placed instance; definition is never modified.
local busy=false
local function note(msg,kind) TriggerEvent('bs:ui:notify',{type=kind or 'info',message=msg,duration=5500}) end
AddEventHandler('bs:building:admin:editPlaced',function(id)
    if busy then return end
    local r=World.pieces[id]
    if not r then return note('Objekt nicht geladen. Bitte naeher herangehen.','error') end
    if GetResourceState('bs_gizmo')~='started' then return note('bs_gizmo fehlt','error') end
    local entity=Building.EntityOf(id)
    if not entity or not DoesEntityExist(entity) then return note('Objekt noch nicht gespawnt','error') end
    busy=true
    CreateThread(function()
        local start=GetEntityCoords(entity)
        local oldH=r.h
        -- use a temporary copy: cancel never changes the live world object.
        local hash=GetEntityModel(entity)
        local obj=CreateObjectNoOffset(hash,start.x,start.y,start.z,false,false,false)
        if not obj or obj==0 then busy=false;return note('Vorschau fehlgeschlagen','error') end
        SetEntityRotation(obj,GetEntityRotation(entity,2),2,true)
        SetEntityAlpha(entity,70,false)
        local ok,result=pcall(function()
            return exports.bs_gizmo:useGizmo(obj,{camera='orbit',mode='translate',space='world',pivot='center',enableScale=false,enableTranslate=true,enableRotate=true,modeToggle=true,enableCopy=false,snapToGround=false,prompts=false,showCoords=true,outline=false,bs19Hud=true})
        end)
        if ok and result and not result.cancelled and result.confirmed~=false then
            local c=GetEntityCoords(obj)
            local h=GetEntityHeading(obj)
            local reply=BSB.Await('build:admin:placedAction',12000,'move',id,{x=c.x,y=c.y,z=c.z,h=h})
            if reply and reply.ok then note('Objektposition dauerhaft gespeichert','success') else note(reply and reply.error or 'Speichern fehlgeschlagen','error') end
        elseif not ok then note('Gizmo-Fehler: '..tostring(result),'error') end
        if DoesEntityExist(entity) then ResetEntityAlpha(entity) end
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        busy=false
    end)
end)
