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
-- Where the left hand goes, in world space: the weapon's grip bone, else the attached grip model, else a point
-- under the front of the weapon from its bounds. Offset is in the weapon's own axes.
local fractions={.64,.25}
local function gripPoint(ped,weapon)
    local source,local_
    local bone=GetEntityBoneIndexByName(weapon,'WAPGrip')
    if bone<0 then bone=GetEntityBoneIndexByName(weapon,'WAPGrip_2')end
    if bone>=0 then
        local w=GetWorldPositionOfEntityBone(weapon,bone)
        local_=GetOffsetFromEntityGivenWorldCoords(weapon,w.x,w.y,w.z);source='bone'
    else
        local prop=Weapons.GripPropFor and Weapons.GripPropFor(ped)
        if prop then
            local w=GetEntityCoords(prop)
            local_=GetOffsetFromEntityGivenWorldCoords(weapon,w.x,w.y,w.z);source='prop'
        else
            local low,high=GetModelDimensions(GetEntityModel(weapon))
            local longX=(high.x-low.x)>=(high.y-low.y)
            local along=longX and low.x+(high.x-low.x)*fractions[1]or low.y+(high.y-low.y)*fractions[1]
            local z=low.z+(high.z-low.z)*fractions[2]
            local_=longX and vector3(along,(low.y+high.y)*.5,z)or vector3((low.x+high.x)*.5,along,z);source='bounds'
        end
    end
    local o=G.offset or {}
    return GetOffsetFromEntityInWorldCoords(weapon,local_.x+(o.x or 0.0),local_.y+(o.y or 0.0),local_.z+(o.z or -0.035)),source
end
local debugGrip=false
RegisterCommand('gripdebug',function()debugGrip=not debugGrip;print('[bs_weapons] grip pose debug '..(debugGrip and 'on'or 'off'))end,false)
CreateThread(function()
    local lastPrint=0
    while true do
        G=Weapons.GripPose or G
        if #targets==0 or not (G and G.enabled)then Wait(250)
        else
            Wait(0)
            for _,t in ipairs(targets)do
                local ped=t.ped
                if DoesEntityExist(ped)and canPose(ped,t.local_)then
                    local weapon=GetCurrentPedWeaponEntityIndex(ped,0)
                    if weapon and weapon~=0 and DoesEntityExist(weapon)then
                        local at,source=gripPoint(ped,weapon)
                        -- No entity: the offset is the world position. Called every frame; IK_PART_ARM_LEFT = 3.
                        SetIkTarget(ped,G.ikPart or 3,0,-1,at.x+0.0,at.y+0.0,at.z+0.0,0,G.blendIn or 0,G.blendOut or 150)
                        if debugGrip and t.local_ then
                            DrawMarker(28,at.x,at.y,at.z,0.0,0.0,0.0,0.0,0.0,0.0,.02,.02,.02,80,220,90,200,false,false,2,false,nil,nil,false)
                            if GetGameTimer()>lastPrint then lastPrint=GetGameTimer()+2000;print(('[bs_weapons] grip target from %s at %.2f %.2f %.2f'):format(source,at.x,at.y,at.z))end
                        end
                    end
                end
            end
        end
    end
end)
