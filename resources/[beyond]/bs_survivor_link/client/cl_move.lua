-- Companion movement: hold orders keep him on his spot, follow keeps him beside you at your pace.
BSLinkMove={}
local M=BSLinkMove
local anchor,returning,anchorRev
local function running(ped,name)return GetScriptTaskStatus(ped,joaat(name))~=7 end
local follow={at=0,speed=0,side=1.0}
local BACK=1.4          -- metres behind you
local SIDE=0.9          -- metres to the side
local REPATH=3.0        -- only re-path past this distance
local CATCHUP=8.0       -- sprint to catch up past this

M.Stay={wait=true,guard=true,sit=true,hide=true}
M.Following={follow=true,regroup=true,cancel=true,stand=true}

-- Walk / run / sprint like the player.
local function paceOf(me)
    local s=GetEntitySpeed(me)
    if s<0.4 then return 0 end
    if s<2.4 then return 1.0 end
    if s<5.2 then return 2.0 end
    return 3.0
end

function M.Reset()anchor,returning,anchorRev=nil,nil,nil;follow.at,follow.speed=0,0 end

-- Hold: remember where he stands and stand still there; never steer toward the player.
function M.StartHold(ped,command,rev)
    -- Same order again (after a fight): keep the original spot and walk back to it.
    if not anchor or rev==nil or rev~=anchorRev then anchor=GetEntityCoords(ped)end
    anchorRev=rev;returning=false
    SetPedCombatMovement(ped,0)
    ClearPedTasks(ped)
    if command=='sit'then TaskStartScenarioInPlace(ped,'WORLD_HUMAN_PICNIC',0,true)
    else TaskStandStill(ped,-1)end
    SetPedKeepTask(ped,true)
end
function M.Hold(ped,command)
    if not anchor then M.StartHold(ped,command);return end
    local d=#(GetEntityCoords(ped)-anchor)
    -- Pushed or knocked off his spot: walk back, then stand again.
    if d>1.5 and not returning then
        returning=true
        TaskGoStraightToCoord(ped,anchor.x,anchor.y,anchor.z,1.0,8000,GetEntityHeading(ped),0.4)
    elseif returning and d<0.7 then
        returning=false
        if command=='sit'then TaskStartScenarioInPlace(ped,'WORLD_HUMAN_PICNIC',0,true)else TaskStandStill(ped,-1)end
    elseif not returning and command~='sit'and not running(ped,'SCRIPT_TASK_STAND_STILL')and not IsPedInCombat(ped,0)then
        -- Anything else that slipped in gets replaced.
        TaskStandStill(ped,-1)
    end
end

-- Follow: beside and behind on his current side, re-pathed only when he falls behind, his pace matches yours.
function M.StartFollow(ped,me)
    anchor,returning,anchorRev=nil,nil,nil
    local rel=GetOffsetFromEntityGivenWorldCoords(me,GetEntityCoords(ped))
    follow.side=rel.x>=0 and SIDE or -SIDE
    follow.at,follow.speed=0,-1
    SetPedCombatMovement(ped,1)
    M.FollowTick(ped,me,true)
end
function M.FollowTick(ped,me,force)
    local now=GetGameTimer()
    local at,mine=GetEntityCoords(ped),GetEntityCoords(me)
    local d=#(at-mine)
    local pace=paceOf(me)
    local speed=d>CATCHUP and 3.0 or math.max(pace,d>REPATH and 2.0 or 1.0)
    -- In front of you while you move: swing round behind so he never blocks your path.
    local rel=GetOffsetFromEntityGivenWorldCoords(me,at)
    local blocking=pace>0 and rel.y>0.2 and math.abs(rel.x)<1.2 and d<3.0
    local changed=pace>0 and speed~=follow.speed
    if not force and now-follow.at<900 then return end
    if force or blocking or (d>REPATH and(changed or not running(ped,'SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY')))or(changed and d>2.0)then
        if blocking then follow.side=rel.x>=0 and SIDE or -SIDE end
        TaskFollowToOffsetOfEntity(ped,me,follow.side,-BACK,0.0,speed,-1,1.0,true)
        follow.at,follow.speed=now,speed
    end
end
