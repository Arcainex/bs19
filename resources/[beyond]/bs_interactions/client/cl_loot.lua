local rules,objects,zoneIds=nil,{},{}
local generation=0
local function clear(id)
    local obj=objects[id]
    if obj then Registry.RemoveEntity(obj);if DoesEntityExist(obj) then DeleteEntity(obj) end;objects[id]=nil end
end
local function apply(value)
    generation=generation+1;rules=value
    for id in pairs(zoneIds) do Registry.RemoveZone(id) end;zoneIds={}
    for id in pairs(objects) do clear(id) end
    for _,p in ipairs(rules.locations or {}) do
        local id='furniture_'..p.id
        zoneIds[id]=true
        Registry.AddZone(id,vector3(p.x,p.y,p.z),math.min(2.4,p.radius),{{label='Search furniture',icon='search',distance=2.4,action=function()
            TriggerEvent('bs:scavenge:furniture',p)
        end}})
    end
end
RegisterNetEvent('bs:scavenge:rules',apply)
RegisterNetEvent('bs:scavenge:removed',function(id) clear(id) end)
CreateThread(function()
    Wait(2500)
    local result=BSB.Await('scavenge:rules',6000)
    if result and result.ok then apply(result.rules) end
    while true do
        Wait(3000)
        if rules and rules.ground.enabled then
            local run=generation
            local reply=BSB.Await('scavenge:ground',6000)
            if run==generation and reply and reply.ok and not reply.unchanged then
            local want={}
            for _,p in ipairs(reply and reply.points or {}) do
                want[p.id]=true
                if not objects[p.id] then
                    local obj,label=GroundModels.Create(p,function()return run==generation end)
                        if obj and obj~=0 then
                            objects[p.id]=obj;SetEntityCollision(obj,true,true);FreezeEntityPosition(obj,true)
                            Registry.AddEntity(obj,{{label=label,icon='search',distance=2.2,action=function()
                                local begin=BSB.Await('scavenge:begin',6000,p.id)
                                if not begin or not begin.ok then return end
                                if not exports.bs_interactions:RunSearch('Collecting supplies',1200,{pose='kneel',entity=obj}) then return end
                                local result=BSB.Await('scavenge:take',8000,p.id)
                                TriggerEvent('bs:ui:notify',{type=result and result.ok and 'success' or 'warn',message=result and result.ok and 'Supplies collected' or result and result.error or 'Nothing here'})
                            end}})
                        end
                end
            end
            if run==generation then for id in pairs(objects) do if not want[id] then clear(id) end end end
            end
        else for id in pairs(objects) do clear(id) end end
    end
end)
AddEventHandler('onResourceStop',function(resource) if resource==GetCurrentResourceName() then generation=generation+1;for id in pairs(objects) do clear(id) end end end)
