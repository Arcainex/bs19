-- bs_weapons - live weapon preview

local P = Weapons.Preview or {}

local State = {
    orbit = 0, elevation = 0, zoom = 1,
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

    local angle = math.rad(State.orbit)
    local dx, dy = pos.x - target.x, pos.y - target.y
    pos = vector3(target.x + (dx * math.cos(angle) - dy * math.sin(angle)) * State.zoom,
        target.y + (dx * math.sin(angle) + dy * math.cos(angle)) * State.zoom,
        target.z + ((P.offsetUp or 0.10) + State.elevation) * State.zoom)
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

-- Close framing for the O menu: the camera stands in front of the player, a little to the weapon side,
-- and looks at the held weapon (a front three-quarter view). Distance comes from the weapon's own bounds so the whole gun stays in frame.
local function weaponBounds(ped)
    local ok, obj = pcall(GetCurrentPedWeaponEntityIndex, ped, 0)
    if ok and obj and obj ~= 0 and DoesEntityExist(obj) then
        local model = GetEntityModel(obj)
        if State.boundsModel ~= model then
            local low, high = GetModelDimensions(model)
            State.boundsModel = model
            State.boundsCenter = vector3((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5)
            State.boundsRadius = math.max(0.12, #(high - low) * 0.5)
        end
        local c = State.boundsCenter
        return GetOffsetFromEntityInWorldCoords(obj, c.x, c.y, c.z), State.boundsRadius
    end
    return weaponPoint(ped), 0.35
end

local function frameShoulder(cam, ped)
    local S = P.shoulder or {}
    local center, radius = weaponBounds(ped)

    -- Idle sway moves the gun a little every frame; ease the aim point so the view does not shake.
    if State.smooth then
        local k = S.follow or 0.22
        center = State.smooth + (center - State.smooth) * k
    end
    State.smooth = center

    local fwd = GetEntityForwardVector(ped)
    local rx, ry = fwd.y, -fwd.x
    local yaw = math.rad((S.yaw or 38.0) + State.orbit)
    local pitch = math.rad(math.max(S.minPitch or -8.0, math.min(S.maxPitch or 70.0, (S.pitch or 12.0) + State.elevation)))

    -- Horizontal direction from the gun to the camera: in front of the player, swung toward the weapon side,
    -- so the gun is seen against the body instead of being hidden behind the shoulder.
    local hx = fwd.x * math.cos(yaw) + rx * math.sin(yaw)
    local hy = fwd.y * math.cos(yaw) + ry * math.sin(yaw)
    local dir = vector3(hx * math.cos(pitch), hy * math.cos(pitch), math.sin(pitch))

    -- Fit the bounding sphere into the space between the side panels (centre ~55% of the width) and the height.
    local fov = math.rad(S.fov or P.fov or 38.0)
    local aspect = GetAspectRatio(false)
    local half = math.min(math.tan(fov * 0.5), math.tan(fov * 0.5) * aspect * (S.usableWidth or 0.55))
    local fit = (radius * (S.margin or 1.08)) / half
    local distance = math.max(S.minDistance or 0.55, fit * State.zoom)

    local pos = center + dir * distance
    local pitchDeg, yawDeg = lookAt(pos, center)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, pitchDeg, 0.0, yawDeg, 2)
    if P.dof then
        SetCamNearDof(cam, math.max(0.05, distance - radius * 1.5))
        SetCamFarDof(cam, distance + radius * 3.0)
    end
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
    State.orbit, State.elevation, State.zoom = 0, 0, 1
    State.mode, State.smooth, State.boundsModel, State.maxHold = nil, nil, nil, nil

    RenderScriptCams(false, true, P.easeOut or 320, true, true)

    if State.cam and DoesCamExist(State.cam) then
        DestroyCam(State.cam, false)
    end
    State.cam = nil
end

--- @return boolean started
--- opts.shoulder = true uses the close shoulder framing; opts.maxHold overrides the camera time cap.
function Weapons.StartPreview(opts)
    if not P.enabled then return false end
    if State.active then return true end
    opts = type(opts) == 'table' and opts or {}

    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) then return false end

    -- No camera in a vehicle: the framing assumes a standing ped.
    if IsPedInAnyVehicle(ped, false) then return false end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not cam or cam == 0 or not DoesCamExist(cam) then return false end

    State.mode = opts.shoulder and 'shoulder' or 'side'
    State.maxHold = tonumber(opts.maxHold)
    State.orbit, State.elevation, State.zoom = 0, 0, 1
    SetCamFov(cam, State.mode == 'shoulder' and ((P.shoulder and P.shoulder.fov) or 38.0) or (P.fov or 36.0))

    if P.dof then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, P.dofNear or 0.25)
        SetCamFarDof(cam, P.dofFar or 2.20)
        SetCamDofStrength(cam, 1.0)
    end

    State.cam = cam
    State.active = true
    State.startAt = GetGameTimer()

    local framer = State.mode == 'shoulder' and frameShoulder or frame
    framer(cam, ped)                      -- aimed before it is ever rendered
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
               or (GetGameTimer() - State.startAt) > (State.maxHold or P.maxHold or 90000) then
                return Weapons.StopPreview()
            end

            framer(State.cam, p)
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
    if what ~= 'radial' and what ~= 'weaponAttachments' then Weapons.StopPreview() end
end)

function Weapons.AdjustPreview(dx, dy, zoom, reset)
    if not State.active then return false end
    if reset then State.orbit, State.elevation, State.zoom = 0, 0, 1; return true end
    for _, value in ipairs({dx,dy,zoom}) do
        if type(value) ~= 'number' or value ~= value or math.abs(value) > 1000 then return false end
    end
    if State.mode == 'shoulder' then
        local S = P.shoulder or {}
        local yawLimit = S.orbitLimit or 80.0
        State.orbit = math.max(-yawLimit, math.min(yawLimit, State.orbit + math.max(-60,math.min(60,dx)) * 0.35))
        local base = S.pitch or 12.0
        State.elevation = math.max((S.minPitch or -8.0) - base, math.min((S.maxPitch or 70.0) - base, State.elevation + math.max(-60,math.min(60,dy)) * 0.3))
        -- Zoom never goes below 1: at 1 the whole weapon just fits between the panels.
        State.zoom = math.max(1.0, math.min(S.maxZoom or 1.9, State.zoom + math.max(-1,math.min(1,zoom)) * 0.08))
        return true
    end
    State.orbit = (State.orbit + math.max(-60,math.min(60,dx)) * 0.5) % 360
    State.elevation = math.max(-0.35,math.min(0.65,State.elevation - math.max(-60,math.min(60,dy)) * 0.003))
    State.zoom = math.max(0.55,math.min(1.7,State.zoom + math.max(-1,math.min(1,zoom)) * 0.08))
    return true
end
