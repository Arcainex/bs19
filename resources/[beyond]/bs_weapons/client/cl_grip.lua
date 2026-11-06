-- Experimental: pull the left hand onto a fitted foregrip in third person.
-- GTA's third-person rifle clips keep the left hand on the handguard whether or not a grip component is fitted,
-- and our outer grip models are separate props, so nothing in the weapon data moves the hand. This adds a light
-- arm IK target on the weapon's grip bone every frame while the gun is simply held or aimed.
local G=Weapons.GripPose or {}
local gripComponents={}
CreateThread(function()
    Wait(1000)
    for _,part in pairs(Weapons.Attachments or {})do
        if part.slot=='grip'then
            for weapon,component in pairs(part.components or {})do
                local hash=GetHashKey(weapon)
                gripComponents[hash]=gripComponents[hash]or {}
                gripComponents[hash][GetHashKey(component)]=true
            end
        end
    end
end)
local function hasGrip(ped,hash)
    local list=gripComponents[hash];if not list then return false end
    for component in pairs(list)do if HasPedGotWeaponComponent(ped,hash,component)then return true end end
    return false
end
local function canPose(ped,isLocal)
    if IsPedReloading(ped)or IsPedRagdoll(ped)or IsPedInAnyVehicle(ped,true)or IsPedClimbing(ped)or IsPedFalling(ped)
        or IsPedSwimming(ped)or IsPedDeadOrDying(ped,true)or IsPedInCover(ped,false)then return false end
    if G.skipSprint~=false and IsPedSprinting(ped)then return false end
    -- First person already has its own grip clips.
    if isLocal and GetFollowPedCamViewMode()==4 and not (Weapons.PreviewActive and Weapons.PreviewActive())then return false end
    return true
end
local targets={}
CreateThread(function()
    while true do
        if not (Weapons.GripPose and Weapons.GripPose.enabled)then Wait(1500)
        else
            -- Every 400 ms: which streamed players hold a gun with a grip fitted.
            local list,me={},PlayerPedId()
            local origin=GetEntityCoords(me)
            for _,player in ipairs(GetActivePlayers())do
                local ped=GetPlayerPed(player)
                if ped~=0 and DoesEntityExist(ped)and #(GetEntityCoords(ped)-origin)<(G.distance or 40.0)then
                    local hash=GetSelectedPedWeapon(ped)
                    if hash and hasGrip(ped,hash)then list[#list+1]={ped=ped,local_=ped==me}end
                end
            end
            targets=list;Wait(400)
        end
    end
end)
CreateThread(function()
    while true do
        if #targets==0 or not (Weapons.GripPose and Weapons.GripPose.enabled)then Wait(250)
        else
            Wait(0)
            local o=G.offset or {}
            for _,t in ipairs(targets)do
                local ped=t.ped
                if DoesEntityExist(ped)and canPose(ped,t.local_)then
                    local weapon=GetCurrentPedWeaponEntityIndex(ped,0)
                    if weapon and weapon~=0 and DoesEntityExist(weapon)then
                        local bone=GetEntityBoneIndexByName(weapon,'WAPGrip')
                        if bone<0 then bone=GetEntityBoneIndexByName(weapon,'WAPGrip_2')end
                        if bone>=0 then
                            SetIkTarget(ped,G.ikPart or 3,weapon,bone,(o.x or 0.0)+0.0,(o.y or 0.0)+0.0,(o.z or -0.035)+0.0,0,G.blendIn or 180,G.blendOut or 180)
                        end
                    end
                end
            end
        end
    end
end)
