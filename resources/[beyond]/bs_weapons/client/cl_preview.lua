-- bs_weapons - live weapon preview

local P = Weapons.Preview or {}

local State = {
    active  = false,
    cam     = nil,
    startAt = 0,
}

-- Geometry

-- Rotation that looks from one point at another
local function lookAt(from, to)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local flat = math.sqrt(dx * dx + dy * dy)

    -- Straight up or down: yaw is undefined, keep the last one.
    if flat < 0.0001 then return (dz > 0 and 89.0 or -89.0), 0.0 end

    local pitch = math.deg(math.atan(dz, flat))
    local yaw   = math.deg(math.atan(-dx, dy))
    return pitch, yaw
end

-- Where the gun is
local function weaponPoint(ped)
    local ok, obj = pcall(GetCurrentPedWeaponEntityIndex, ped, 0)
    if not ok then ok, obj = pcall(GetCurrentPedWeaponEntityIndex, ped) end

    if ok and obj and obj ~= 0 and DoesEntityExist(obj) then
        return GetEntityCoords(obj)
    end

    local bone = GetPedBoneIndex(ped, 57005)          -- SKEL_R_Hand
    local hand = GetWorldPositionOfEntityBone(ped, bone)
    local fwd  = GetEntityForwardVector(ped)

    return vector3(hand.x + fwd.x * 0.18, hand.y + fwd.y * 0.18, hand.z + 0.04)
end

-- Aim the camera at the weapon, from just off to one side.
local function frame(cam, ped)
    local target = weaponPoint(ped)
    local fwd    = GetEntityForwardVector(ped)

    -- The ped's right on the flat: forward = (-sin h, cos h), right = (cos h, sin h).
    local rx, ry = fwd.y, -fwd.x

    local pos = vector3(
        target.x + rx * (P.offsetRight or 0.42) + fwd.x * (P.offsetForward or 0.58),
        target.y + ry * (P.offsetRight or 0.42) + fwd.y * (P.offsetForward or 0.58),
        target.z + (P.offsetUp or 0.10)
    )

    local pitch, yaw = lookAt(pos, target)

    -- Puts the gun on one side of the screen: the camera aims slightly past the weapon
    local swing = P.swing or 15.0
    if (P.weaponSide or 'left') == 'left' then
        yaw = yaw - swing
    else
        yaw = yaw + swing
    end

    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, pitch, 0.0, yaw, 2)
end

-- Start / stop

-- Which side of the screen the wheel should take, given where the gun is.
function Weapons.PreviewWheelSide()
    if not P.enabled then return nil end
    return (P.weaponSide or 'left') == 'left' and 'right' or 'left'
end

function Weapons.PreviewActive() return State.active end

function Weapons.StopPreview()
    if not State.active then return end
    State.active = false

    RenderScriptCams(false, true, P.easeOut or 320, true, true)

    if State.cam and DoesCamExist(State.cam) then
        DestroyCam(State.cam, false)
    end
    State.cam = nil
end

--- @return boolean started
function Weapons.StartPreview()
    if not P.enabled then return false end
    if State.active then return true end

    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) then return false end

    -- No camera in a vehicle: the framing assumes a standing ped.
    if IsPedInAnyVehicle(ped, false) then return false end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not cam or cam == 0 or not DoesCamExist(cam) then return false end

    SetCamFov(cam, P.fov or 36.0)

    if P.dof then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, P.dofNear or 0.25)
        SetCamFarDof(cam, P.dofFar or 2.20)
        SetCamDofStrength(cam, 1.0)
    end

    State.cam = cam
    State.active = true
    State.startAt = GetGameTimer()

    frame(cam, ped)                       -- aimed before it is ever rendered
    SetCamActive(cam, true)
    RenderScriptCams(true, true, P.easeIn or 420, true, true)

    -- Follow loop: the gun moves (sway, animation, turning), so the framing is recomputed every frame
    CreateThread(function()
        while State.active do
            Wait(0)

            local p = PlayerPedId()

            -- Anything that makes the framing meaningless takes it down
            if not DoesCamExist(State.cam)
               or IsPedDeadOrDying(p, true)
               or IsPedInAnyVehicle(p, false)
               or (GetGameTimer() - State.startAt) > (P.maxHold or 90000) then
                return Weapons.StopPreview()
            end

            frame(State.cam, p)
            if P.dof then SetUseHiDof() end
        end
    end)

    return true
end

-- Safety: whatever happens to the caller (error, death, restart) the camera comes down

AddEventHandler('bs:hook:player:unloaded', function() Weapons.StopPreview() end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Weapons.StopPreview()
    RenderScriptCams(false, false, 0, true, true)
end)

-- If any other menu takes the screen, this camera comes down.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'radial' then Weapons.StopPreview() end
end)
