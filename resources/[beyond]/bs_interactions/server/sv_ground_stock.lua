GroundStock={}
local cache,sequence={},0
function GroundStock.Clear()cache={}end
function GroundStock.Remove(id)cache[id]=nil end
function GroundStock.Get(point,pool)
    if cache[point.id]then return cache[point.id]end
    local entries=Containers.RollLoot(pool,nil,true)
    local item=entries and entries[1]
    if not item then return end
    local def=exports.bs_inventory:GetItem(item.item)
    if not def then return end
    sequence=sequence+1
    local data=def.data or {}
    local value={item=item.item,amount=item.amount,label=def.label or item.item,token=sequence,weapon=data.weapon,
        model=Scavenge.groundModels[item.item]or data.worldModel or Scavenge.fallbackGroundModel,
        bagged=not data.weapon and not Scavenge.groundModels[item.item]and not data.worldModel}
    cache[point.id]=value;return value
end
function GroundStock.Present(point,pool)
    local value=GroundStock.Get(point,pool);if not value then return end
    local result={};for k,v in pairs(point)do result[k]=v end;result.stock=value;return result
end
