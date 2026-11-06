-- Local navigation around visible walkers. The survivor remains a normal, vulnerable ped.
BSLinkStealth = {}
local Stealth = BSLinkStealth
local records = {}
local SCAN_MS, REPLAN_MS = 1200, 1600
local SENSE_RADIUS, HOLD_RADIUS = 38.0, 8.0
local WALK_SPEED = 1.0

local function distance(a, b)
    local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
    return math.sqrt(x*x+y*y+z*z)
end
local function point(p)
    return { x=p.x, y=p.y, z=p.z }
end
local function pathDistance(a, b, p)
    local dx, dy = b.x-a.x, b.y-a.y
    local length = dx*dx+dy*dy
    local t = length>0.001 and ((p.x-a.x)*dx+(p.y-a.y)*dy)/length or 0
    t = math.max(0, math.min(1,t))
    local x, y = a.x+t*dx-p.x, a.y+t*dy-p.y
    return math.sqrt(x*x+y*y)
end

-- Pure scoring step kept separate from native navigation for regression checks.
function Stealth.Plan(current, goal, anchor, threats, candidates, covered)
    local nearest = math.huge
    for _,z in ipairs(threats) do nearest=math.min(nearest,distance(current,z)) end
    local best, bestScore
    for _,candidate in ipairs(candidates) do
        local valid = not anchor or distance(candidate,anchor)<=HOLD_RADIUS
        local clearance, route = math.huge, math.huge
        for _,z in ipairs(threats) do
            clearance=math.min(clearance,distance(candidate,z))
            route=math.min(route,pathDistance(current,candidate,z))
        end
        -- Do not walk through a walker to reach an otherwise attractive destination.
        if route<3.5 and route<nearest-0.35 then valid=false end
        -- When already in contact range, only choose a route that improves separation.
        if nearest<5.0 and clearance<nearest+0.5 then valid=false end
        if valid then
            local safety=math.min(clearance,18.0)*2.4+math.min(route,9.0)*1.2
            local score=safety-distance(candidate,goal)*0.9-distance(current,candidate)*0.2
            if covered and threats[1] and covered(candidate,threats[1])then score=score+8.0 end
            if not bestScore or score>bestScore then best,bestScore=candidate,score end
        end
    end
    return best
end

local function scan(ped,at)
    local out={}
    for _,other in ipairs(GetGamePool('CPed')) do
        if other~=ped and DoesEntityExist(other)and not IsEntityDead(other)then
            local state=Entity(other).state
            if state.bsZombie and not state.bsZombieDead then
                local position=GetEntityCoords(other)
                local d=distance(at,position)
                if d<SENSE_RADIUS and math.abs(position.z-at.z)<5.0 then
                    out[#out+1]={ped=other,x=position.x,y=position.y,z=position.z,distance=d}
                end
            end
        end
    end
    table.sort(out,function(a,b)return a.distance<b.distance end)
    while #out>12 do table.remove(out)end
    return out
end
local function coverAt(ped,candidate,zombie)
    local ray=StartExpensiveSynchronousShapeTestLosProbe(zombie.x,zombie.y,zombie.z+1.0,
        candidate.x,candidate.y,candidate.z+0.8,1,ped,7)
    local status,hit=GetShapeTestResult(ray)
    return status==2 and (hit==true or hit==1)
end
local function samples(current,goal)
    local out={}
    local function add(x,y,z)
        local found,safe=GetSafeCoordForPed(x,y,z,true,16)
        if found and safe and math.abs(safe.z-current.z)<2.5 then out[#out+1]=point(safe)end
    end
    add(goal.x,goal.y,goal.z)
    -- Short arcs let the navmesh route around nearby furniture instead of fleeing the area.
    for i=0,7 do
        local angle=i*math.pi/4
        add(current.x+math.cos(angle)*4.5,current.y+math.sin(angle)*4.5,current.z)
    end
    return out
end
local function stop(ped,rec)
    if rec.moving then ClearPedTasks(ped)end
    TaskStandStill(ped,REPLAN_MS+300)
    rec.moving=false;rec.destination=nil
end

function Stealth.Reset(ped)
    if ped then records[ped]=nil else records={}end
end

-- True means this helper owns the task for this tick; callers must skip normal follow/combat tasks.
function Stealth.Update(ped,order,owner)
    if not ped or not DoesEntityExist(ped)then return false end
    local command=order and order.command
    local hidden=order and (order.stance=='hidden' or command=='hide')
    -- Hold orders keep him on his spot: no walking away from walkers either.
    local excluded=command=='enter'or command=='exit'or command=='sit'or command=='wait'or command=='guard'
    if command=='target'then
        local target=order.target and NetworkGetEntityFromNetworkId(order.target)or 0
        excluded=target==0 or not DoesEntityExist(target)or not Entity(target).state.bsZombie
    end
    -- Aggressive companions fight instead of walking away.
    if order and order.stance=='aggressive'and not hidden then excluded=true end
    if excluded then
        local released=records[ped]~=nil
        Stealth.Reset(ped)
        return false,released
    end
    if not NetworkHasControlOfEntity(ped)or IsPedInAnyVehicle(ped,false)then return true end
    local now=GetGameTimer()
    local at=point(GetEntityCoords(ped))
    local key=tostring(command)..':'..tostring(order.revision or '')..':'..tostring(hidden)
    local rec=records[ped]
    if not rec or rec.key~=key then
        rec={key=key,anchor=point(at),scanAt=0,planAt=0,threats={},moving=false}
        records[ped]=rec
        if hidden then ClearPedTasks(ped)end
    end
    SetPedStealthMovement(ped,hidden==true,0)
    local stay=command=='hide'or command=='wait'or command=='guard'
    local goal=rec.anchor
    if not stay then
        if not owner or not DoesEntityExist(owner)then stop(ped,rec);return true end
        local d=(SurvivorLink and SurvivorLink.followDistance)or 2.5
        goal=point(GetOffsetFromEntityInWorldCoords(owner,-d,-d,0.0))
    end
    if rec.scanAt==0 or now-rec.scanAt>=(hidden and SCAN_MS or 650)then
        rec.threats=scan(ped,at);rec.scanAt=now
    end
    local nearest=rec.threats[1]
    if not hidden then
        -- Defensive: keep away from walkers inside avoidRange, with a little slack before letting go.
        local avoid=(SurvivorLink and SurvivorLink.avoidRange)or 25.0
        if not nearest or nearest.distance>(rec.moving and avoid+3.0 or avoid)then
            local released=rec.moving==true
            rec.moving=false;rec.destination=nil
            return false,released
        end
    end
    if now-rec.planAt<(hidden and REPLAN_MS or 850)then return true end
    rec.planAt=now
    -- A hold order stays put until a real walker approaches; safe followers walk toward their owner.
    if hidden and stay and (not nearest or nearest.distance>12.0)then stop(ped,rec);return true end
    if hidden and not stay and not nearest and distance(at,goal)<2.0 then stop(ped,rec);return true end
    local candidate
    if nearest then
        candidate=Stealth.Plan(at,goal,stay and rec.anchor or nil,rec.threats,samples(at,goal),
            function(position,zombie)return coverAt(ped,position,zombie)end)
    else
        local found,safe=GetSafeCoordForPed(goal.x,goal.y,goal.z,true,16)
        if found then candidate=point(safe)end
    end
    if not candidate or distance(at,candidate)<0.9 then
        -- Nowhere better to go with a walker at arm's length: the caller fights back.
        if nearest and nearest.distance<3.0 then
            local released=rec.moving==true
            rec.moving=false;rec.destination=nil
            return false,released,nearest.ped
        end
        stop(ped,rec);return true
    end
    if rec.destination and distance(rec.destination,candidate)<1.0 and rec.moving then return true end
    TaskFollowNavMeshToCoord(ped,candidate.x,candidate.y,candidate.z,hidden and WALK_SPEED or 2.2,-1,0.7,true,0.0)
    rec.destination=point(candidate);rec.moving=true
    return true
end

RegisterNetEvent('bs:link:state',function(data)if not data then Stealth.Reset()end end)
AddEventHandler('bs:hook:player:unloaded',function()Stealth.Reset()end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName()then Stealth.Reset()end
end)
