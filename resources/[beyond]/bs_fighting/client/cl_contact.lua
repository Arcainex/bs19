FightContact={}
local bounds={}
local previous={}
function FightContact.Begin() previous={} end
local function distanceToSegment(p,a,b)
    local x,y,z=b.x-a.x,b.y-a.y,b.z-a.z
    local length=x*x+y*y+z*z
    local t=length>.00001 and math.max(0,math.min(1,((p.x-a.x)*x+(p.y-a.y)*y+(p.z-a.z)*z)/length))or 0
    local dx,dy,dz=p.x-a.x-x*t,p.y-a.y-y*t,p.z-a.z-z*t
    return math.sqrt(dx*dx+dy*dy+dz*dz)
end
FightContact.DistanceToSegment=distanceToSegment
function FightContact.Test(attacker,target,class,kind)
    if not DoesEntityExist(attacker)or not DoesEntityExist(target)or IsEntityDead(target)then return false end
    if not HasEntityClearLosToEntity(attacker,target,17)then return false end
    local segments={}
    local function bone(id)
        local p=GetPedBoneCoords(attacker,id,0.0,0.0,0.0)
        segments[#segments+1]={p,p}
    end
    if kind=='kick'then bone(14201);bone(52301)
    elseif class=='fists'then bone(18905);bone(57005)
    else
        local object=GetCurrentPedWeaponEntityIndex(attacker,0)
        if object and object~=0 and DoesEntityExist(object)then
            local model=GetEntityModel(object);local box=bounds[model]
            if not box then local low,high=GetModelDimensions(model);box={low=low,high=high};bounds[model]=box end
            local low,high=box.low,box.high
            local x,y,z=(low.x+high.x)*.5,(low.y+high.y)*.5,(low.z+high.z)*.5
            local a,b
            if high.x-low.x>=math.max(high.y-low.y,high.z-low.z)then
                a=GetOffsetFromEntityInWorldCoords(object,low.x,y,z);b=GetOffsetFromEntityInWorldCoords(object,high.x,y,z)
            elseif high.y-low.y>=high.z-low.z then
                a=GetOffsetFromEntityInWorldCoords(object,x,low.y,z);b=GetOffsetFromEntityInWorldCoords(object,x,high.y,z)
            else a=GetOffsetFromEntityInWorldCoords(object,x,y,low.z);b=GetOffsetFromEntityInWorldCoords(object,x,y,high.z)end
            segments[#segments+1]={a,b}
        else bone(57005)end
    end
    local radius=math.max(.2,math.min(.8,Fighting.Settings.contactRadius or .5))
    local swept={}
    for i,segment in ipairs(segments) do
        local last=previous[i]
        if last then
            swept[#swept+1]={last[1],segment[1]}
            swept[#swept+1]={last[2],segment[2]}
        end
        previous[i]={segment[1],segment[2]}
    end
    for _,id in ipairs({11816,24818,31086,58271,51826,63931,36864})do
        local point=GetPedBoneCoords(target,id,0.0,0.0,0.0)
        for _,segment in ipairs(segments)do if distanceToSegment(point,segment[1],segment[2])<=radius then return true end end
        for _,segment in ipairs(swept)do if distanceToSegment(point,segment[1],segment[2])<=radius then return true end end
    end
    return false
end
