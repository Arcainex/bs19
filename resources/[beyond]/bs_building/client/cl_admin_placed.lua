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
        local anchor = {x=r.x,y=r.y,z=r.z,h=r.h}
        local modelHeading = GetEntityHeading(entity)
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
            -- Store coordinates are the bottom-centre build anchor. The gizmo
            -- moves the *GTA entity pivot*. Saving the pivot directly shifted
            -- the prop every time the F10 editor was used.
            local reply=BSB.Await('build:admin:placedAction',12000,'move',id,{
                x=anchor.x+(c.x-start.x),
                y=anchor.y+(c.y-start.y),
                z=anchor.z+(c.z-start.z),
                h=(anchor.h+(h-modelHeading))%360
            })
            if reply and reply.ok then note('Objektposition dauerhaft gespeichert','success') else note(reply and reply.error or 'Speichern fehlgeschlagen','error') end
        elseif not ok then note('Gizmo-Fehler: '..tostring(result),'error') end
        if DoesEntityExist(entity) then ResetEntityAlpha(entity) end
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        busy=false
    end)
end)
