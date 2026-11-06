-- Reviving the companion: kneel beside him, inject, and a short wake-up effect when he comes round.
BSLinkRevive={}
-- First set that loads wins, so a missing dictionary never leaves you standing still.
local SETS={
    {dict='amb@medic@standing@tendtodead@idle_a',clip='idle_a'},
    {dict='amb@medic@standing@kneel@base',clip='base'},
}
local SYRINGE=joaat('prop_syringe_01')
local R_HAND=57005
local prop

local function loadDict(dict)
    if HasAnimDictLoaded(dict)then return true end
    RequestAnimDict(dict)
    local untilAt=GetGameTimer()+2500
    while not HasAnimDictLoaded(dict)and GetGameTimer()<untilAt do Wait(20)end
    return HasAnimDictLoaded(dict)
end
local function loadModel(model)
    if not IsModelInCdimage(model)then return false end
    RequestModel(model)
    local untilAt=GetGameTimer()+2500
    while not HasModelLoaded(model)and GetGameTimer()<untilAt do Wait(20)end
    return HasModelLoaded(model)
end
local function dropProp()
    if prop and DoesEntityExist(prop)then DeleteObject(prop)end
    prop=nil
end

-- Returns the anim set that is playing, or nil when none loaded.
function BSLinkRevive.Start(target,duration)
    local me=PlayerPedId()
    if target and DoesEntityExist(target)then
        TaskTurnPedToFaceEntity(me,target,700);Wait(700)
    end
    local used
    for _,set in ipairs(SETS)do
        if loadDict(set.dict)then used=set;break end
    end
    if used then TaskPlayAnim(me,used.dict,used.clip,3.0,-3.0,duration or -1,1,0,false,false,false)end
    if loadModel(SYRINGE)then
        dropProp()
        local at=GetEntityCoords(me)
        prop=CreateObject(SYRINGE,at.x,at.y,at.z+0.2,false,false,false)
        SetEntityCollision(prop,false,false)
        AttachEntityToEntity(prop,me,GetPedBoneIndex(me,R_HAND),0.11,0.02,-0.02,-80.0,0.0,0.0,true,true,false,false,1,true)
        SetModelAsNoLongerNeeded(SYRINGE)
    end
    return used
end
function BSLinkRevive.Stop(used)
    local me=PlayerPedId()
    if used then StopAnimTask(me,used.dict,used.clip,2.0);RemoveAnimDict(used.dict)end
    ClearPedTasks(me)
    dropProp()
end

-- Groggy for a while after he wakes: short flash for you, limp walk for him.
local GROGGY='move_m@injured'
function BSLinkRevive.Wake(ped)
    AnimpostfxPlay('FocusIn',0,false)
    SetTimeout(1400,function()AnimpostfxStop('FocusIn');AnimpostfxPlay('FocusOut',0,false)end)
    SetTimeout(2600,function()AnimpostfxStop('FocusOut')end)
    if not ped or not DoesEntityExist(ped)then return end
    RequestAnimSet(GROGGY)
    local untilAt=GetGameTimer()+2000
    while not HasAnimSetLoaded(GROGGY)and GetGameTimer()<untilAt do Wait(20)end
    if HasAnimSetLoaded(GROGGY)and NetworkHasControlOfEntity(ped)then
        SetPedMovementClipset(ped,GROGGY,0.5)
        SetTimeout(20000,function()if DoesEntityExist(ped)then ResetPedMovementClipset(ped,0.5)end end)
    end
end
AddEventHandler('onResourceStop',function(res)if res==GetCurrentResourceName()then dropProp()end end)
