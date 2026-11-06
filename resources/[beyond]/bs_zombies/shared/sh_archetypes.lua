-- Optional population recipes for Networked+. Selection stays on the server.
Zombies = Zombies or {}
function Zombies.PickArchetype(record)
    local pool, total = {}, 0
    for _, a in ipairs(type(Zombies.Archetypes) == 'table' and Zombies.Archetypes or {}) do
        if type(a) == 'table' and type(a.id) == 'string' and #a.id <= 48
            and type(a.gait) == 'string' and #a.gait > 0 and #a.gait < 100
            and ({walk=true,jog=true,run=true,sprint=true})[a.speed] then
            local match = type(a.regions) ~= 'table' or #a.regions == 0
            for _, region in ipairs(type(a.regions) == 'table' and a.regions or {}) do
                local rx = type(region) == 'table' and tonumber(region.x)
                local ry = type(region) == 'table' and tonumber(region.y)
                local radius = type(region) == 'table' and tonumber(region.radius)
                if rx and ry and radius and radius > 0 and radius <= 10000 then
                    local dx,dy = record.x-rx,record.y-ry
                    if dx*dx+dy*dy <= radius*radius then match=true end
                end
            end
            local weight = tonumber(a.weight) or 0
            if match and weight == weight and weight >= 1 and weight <= 100 then
                -- A malformed model pool cannot wedge promotion or invoke native hashing on a table.
                local models = {}
                for _, model in ipairs(type(a.models) == 'table' and a.models or {}) do
                    if type(model) == 'string' and #model > 0 and #model < 100 and model:match('^[%w_]+$') then models[#models+1]=model end
                end
                local copy={id=a.id,gait=a.gait,speed=a.speed,models=models}
                total=total+weight; pool[#pool+1]={limit=total,value=copy}
            end
        end
    end
    if total == 0 then return nil end
    local roll=(math.floor(tonumber(record.id) or 0)*7919 % total)
    for _, choice in ipairs(pool) do if roll < choice.limit then return choice.value end end
end
