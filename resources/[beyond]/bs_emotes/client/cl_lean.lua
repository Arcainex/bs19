-- bs_emotes - camera lean (Q left, E right) while aiming.
-- It moves the camera, not the ped: GTA has no real lean for a player on foot, and an animation-only lean would show you exposed while the collision capsule stays behind cover. Other players do not see the lean.
-- Only active while aiming a weapon, which keeps E free for interacting; cover (Q) is suppressed only while aiming too.
-- The offset is probe-tested every frame so the camera never leans into a wall.

-- Master switch for leaning, off by default. When off the loop returns immediately and touches no controls or cameras. Set to true (or use /lean) to enable.
local ENABLED_BY_DEFAULT = false

local Lean = {
    enabled = ENABLED_BY_DEFAULT,
    -- -1 left, 1 right, 0 upright. What the keys are asking for.
    want = 0,

    -- Camera sideways offset in metres. Chases `want` instead of snapping.
    at = 0.0,

    cam = nil,
    active = false,
}

--------------------------------------------------------------------------------
-- Tuning
--------------------------------------------------------------------------------

local L = {
    -- Eye sideways distance at full lean, metres. Past about 0.7 it stops reading as a lean.
    distance = 0.55,

    -- Degrees of roll at full lean. Keep small (under ~10) to avoid motion sickness.
    roll = 7.0,

    -- Metres per second the offset chases the target at. About half a second feels like a body moving.
    speed = 2.6,

    -- Radius of the clearance probe, slightly wider than the camera.
    probeRadius = 0.28,

    -- Height above the ped's root the eye sits at when probing.
    eyeHeight = 0.65,
}


-- True when leaning is allowed. Aiming a firearm is the gate.
local function allowed()
    if not Lean.enabled then return false end

    local ped = PlayerPedId()
    if not ped or ped == 0 then return false end
    if IsPedDeadOrDying(ped, true) then return false end
    if IsPedInAnyVehicle(ped, false) then return false end

    -- Aiming specifically, not merely holding a gun. IsPlayerFreeAiming covers third-person aim and scoped/ironsight.
    if not IsPlayerFreeAiming(PlayerId()) then return false end

    -- Stances that already own the body (prone) are left alone so this does not fight cl_prone. Crouching is fine.
    local prone = rawget(_G, 'Prone')
    if type(prone) == 'table' and prone.active then return false end

    return true
end

-- How far we may lean this frame: a probe from the eye to the requested offset, backing off to just short of any hit.
-- Synchronous on purpose, an async result would arrive a frame late and clip into walls. There is no synchronous capsule native, so this is a ray; `probeRadius` is subtracted to make up for the missing width. One short probe per frame, only while a key is held and aiming.
local function clearance(ped, sign)
    local at = GetEntityCoords(ped)
    local eye = vector3(at.x, at.y, at.z + L.eyeHeight)

    -- The ped's own right vector, so left is always the player's left.
    local heading = math.rad(GetEntityHeading(ped))
    local right = vector3(math.cos(heading), math.sin(heading), 0.0)

    local target = eye + (right * (L.distance * sign))

    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        eye.x, eye.y, eye.z,
        target.x, target.y, target.z,
        -- 1 (world) + 16 (objects). Not peds or vehicles, so you can lean past a parked car or a team mate.
        17, ped, 4)

    local _, hit, endCoords = GetShapeTestResult(handle)

    if hit == 1 and endCoords then
        local reached = #(vector3(endCoords.x, endCoords.y, endCoords.z) - eye)
        -- Stop a probe-radius short of what we touched.
        return math.max(0.0, reached - L.probeRadius)
    end

    return L.distance
end

--------------------------------------------------------------------------------
-- The camera
--------------------------------------------------------------------------------

-- A camera that copies the gameplay camera and steps sideways. Created when a lean begins and destroyed when it ends, so a script camera is never left rendering and stuck.
local function ensureCam()
    if Lean.cam and DoesCamExist(Lean.cam) then return Lean.cam end

    Lean.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(Lean.cam, true)

    -- 0 blend: the camera starts exactly where the gameplay camera is, so a blend would only show as a swim. The smoothing is on the offset.
    RenderScriptCams(true, false, 0, true, true)
    return Lean.cam
end

local function dropCam()
    if Lean.cam then
        RenderScriptCams(false, false, 0, true, true)
        if DoesCamExist(Lean.cam) then DestroyCam(Lean.cam, true) end
        Lean.cam = nil
    end
    Lean.active = false
end

--------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local canLean = allowed()

        -- Read both forms of the control: a control disabled by another resource reads as not pressed through IsControlPressed. Q is INPUT_COVER and E is interact (bs_interactions disables it while its menu is up).
        local left = canLean and (IsControlPressed(0, 44) or IsDisabledControlPressed(0, 44))
        local right = canLean and (IsControlPressed(0, 38) or IsDisabledControlPressed(0, 38))

        -- Both at once is upright.
        Lean.want = (left and right) and 0 or (left and -1) or (right and 1) or 0

        if canLean and Lean.want ~= 0 then
            -- Suppress what the keys normally do (Q cover, E interact), only in frames where a lean is using them.
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 38, true)
        end

        if Lean.want ~= 0 or Lean.at ~= 0.0 then
            local target = 0.0

            if canLean and Lean.want ~= 0 then
                target = clearance(ped, Lean.want) * Lean.want
            end

            -- Chase, do not snap. Frame-rate independent: metres per second times real frame time.
            local step = L.speed * GetFrameTime()
            if math.abs(target - Lean.at) <= step then
                Lean.at = target
            else
                Lean.at = Lean.at + (target > Lean.at and step or -step)
            end

            if math.abs(Lean.at) < 0.01 and Lean.want == 0 then
                -- Home again. Give the view back to the engine.
                Lean.at = 0.0
                dropCam()
            else
                local cam = ensureCam()

                -- Mirror the gameplay camera every frame and add an offset, so aiming, mouse look and shoulder swap keep working.
                local base = GetGameplayCamCoord()
                local rot = GetGameplayCamRot(2)
                local fov = GetGameplayCamFov()

                -- Sideways in camera space, so the offset stays perpendicular to the view when looking up or down.
                local yaw = math.rad(rot.z)
                local rightVec = vector3(math.cos(-yaw), math.sin(-yaw), 0.0)

                local pos = base + (rightVec * Lean.at)

                SetCamCoord(cam, pos.x, pos.y, pos.z)
                -- Roll is the y component of the rotation vector, scaled by how far into the lean we are.
                SetCamRot(cam, rot.x, (Lean.at / L.distance) * L.roll, rot.z, 2)
                SetCamFov(cam, fov)

                Lean.active = true
            end

            Wait(0)
        else
            -- Nothing to do. Idle at 200ms rather than every frame.
            if Lean.cam then dropCam() end
            Wait(200)
        end
    end
end)

--------------------------------------------------------------------------------
-- Never stuck
--------------------------------------------------------------------------------

-- The way out of a state is never conditional (same rule as cl_crouch and cl_prone). A stuck camera offset cannot be walked off.
local function reset()
    Lean.want, Lean.at = 0, 0.0
    dropCam()
end

AddEventHandler('bs:hook:player:spawned', reset)
AddEventHandler('bs:hook:player:unloaded', reset)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then reset() end
end)

-- /lean - toggle the feature for this session. Not persisted.
RegisterCommand('lean', function()
    Lean.enabled = not Lean.enabled
    if not Lean.enabled then reset() end

    TriggerEvent('bs:ui:notify', { type = 'info', duration = 3000,
        message = Lean.enabled
            and 'Leaning ON - hold Q or E while aiming.'
            or 'Leaning OFF.' })
end, false)

-- Manual escape hatch, same idea as /unblur.
RegisterCommand('unlean', function()
    reset()
    TriggerEvent('bs:ui:notify', { type = 'info', duration = 2000,
        message = BSLocale.T(BSLocale.Lang(), 'emo.lean_reset') })
end, false)

exports('IsLeaning', function() return Lean.active end)

BSLean = Lean
