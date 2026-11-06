GroundModels={}
local function modelFor(stock)
    if stock.weapon then
        local weapon=GetHashKey(stock.weapon)
        if IsWeaponValid(weapon)then local model=GetWeapontypeModel(weapon);if model~=0 and IsModelInCdimage(model)then return model,weapon end end
        return
    end
    if type(stock.model)=='string'then local model=GetHashKey(stock.model);if IsModelInCdimage(model)then return model end end
    local fallback=GetHashKey(Scavenge.fallbackGroundModel)
    if IsModelInCdimage(fallback)then return fallback,nil,true end
end
local function height(point)
    if not point.procedural then return point.z end
    RequestCollisionAtCoord(point.x,point.y,point.z)
    local hit,z=GetGroundZFor_3dCoord(point.x,point.y,point.z+4,false)
    if not hit or math.abs(z-point.z)>2 or GetInteriorAtCoords(point.x,point.y,z+.3)~=0 then return end
    local probe=StartShapeTestCapsule(point.x,point.y,z+.18,point.x,point.y,z+.32,.12,17,PlayerPedId(),7)
    local deadline=GetGameTimer()+100;local state,blocked
    repeat state,blocked=GetShapeTestResult(probe);if state==1 then Wait(0)end until state~=1 or GetGameTimer()>=deadline
    if state~=2 or blocked==true or blocked==1 then return end
    return z
end
function GroundModels.Create(point,current)
    local stock=point.stock
    if type(stock)~='table'or not stock.item or not stock.token then return end
    local z=height(point);if not z or not current()then return end
    local model,weapon,bagged=modelFor(stock);if not model then return end
    if weapon then RequestWeaponAsset(weapon,31,0)else RequestModel(model)end
    local deadline=GetGameTimer()+1500
    while current()and GetGameTimer()<deadline and not (weapon and HasWeaponAssetLoaded(weapon)or not weapon and HasModelLoaded(model))do Wait(25)end
    local ready=weapon and HasWeaponAssetLoaded(weapon)or not weapon and HasModelLoaded(model)
    if not current()or not ready then if weapon then RemoveWeaponAsset(weapon)else SetModelAsNoLongerNeeded(model)end;return end
    local obj
    if weapon then obj=CreateWeaponObject(weapon,0,point.x,point.y,z+.04,true,1.0,0,false,false)
    else obj=CreateObjectNoOffset(model,point.x,point.y,z+.03,false,false,false)end
    if weapon then RemoveWeaponAsset(weapon)else SetModelAsNoLongerNeeded(model)end
    if not obj or obj==0 or not DoesEntityExist(obj)then return end
    SetEntityCollision(obj,false,false);FreezeEntityPosition(obj,true)
    if weapon then SetEntityRotation(obj,90,0,((GetHashKey(point.id)%360)+360)%360,2,true)end
    return obj,('Collect %s ×%d%s'):format(stock.label or stock.item,stock.amount or 1,(bagged or stock.bagged)and ' (supplies bag)'or '')
end
