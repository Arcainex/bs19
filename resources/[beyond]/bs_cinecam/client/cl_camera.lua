-- bs_cinecam - scripted camera, not a moved ped.
-- The gameplay camera has its own spring and collision push-out that cannot be turned off, so everything here drives a scripted camera directly.

CineCam = {
    active  = false,
    handle  = nil,

    -- Live state. Position and angles are plain numbers because each is smoothed independently.
    x = 0.0, y = 0.0, z = 0.0,
    pitch = 0.0, yaw = 0.0, roll = 0.0,
    fov = 50.0,

    -- Smoothed velocity, in metres/second, world space.
    vx = 0.0, vy = 0.0, vz = 0.0,

    -- What the input is asking for. The camera eases toward these.
    tPitch = 0.0, tYaw = 0.0, tRoll = 0.0, tFov = 50.0,

    -- Set by the path player while a path runs. Manual flight is skipped in that state so two writers do not fight over the position.
    scripted = false,
}

local function S() return CineState.s end


-- Frame-rate independent smoothing: alpha = 1 - exp(-dt / tau).
-- tau is a time constant in seconds (~63% of the remaining distance after tau). A plain per-frame lerp converges faster at higher fps, so footage would differ per machine.
local function alphaFor(tau, dt)
    if not tau or tau <= 0.0 then return 1.0 end
    return 1.0 - math.exp(-dt / tau)
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Shortest-arc difference between two angles in degrees, in (-180, 180]. Avoids a 359 degree snap when panning across north.
local function angleDelta(from, to)
    local d = (to - from) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return d
end

local function lerpAngle(a, b, t) return a + angleDelta(a, b) * t end

CineCam.AngleDelta = angleDelta
CineCam.LerpAngle  = lerpAngle
CineCam.Lerp       = lerp

-- Unit forward and right vectors for a pitch/yaw pair, in GTA world axes (+Y north, +Z up, yaw counter-clockwise from north).
local function basis(pitch, yaw)
    local p = math.rad(pitch)
    local w = math.rad(yaw)
    local cp = math.cos(p)

    return  -math.sin(w) * cp, math.cos(w) * cp, math.sin(p),   -- forward
             math.cos(w),      math.sin(w),      0.0            -- right
end

CineCam.Basis = basis


local function pushToEngine()
    local cam = CineCam.handle
    if not cam or not DoesCamExist(cam) then return end

    SetCamCoord(cam, CineCam.x, CineCam.y, CineCam.z)

    -- Rotation order 2 takes (pitch, roll, yaw). Passing yaw in the second slot spins the camera around its view axis.
    SetCamRot(cam, CineCam.pitch, CineCam.roll, CineCam.yaw, 2)
    SetCamFov(cam, CineCam.fov)

    local s = S()
    if s.dofEnabled then
        -- Depth of field only exists while the frame is drawn, so these are per-frame calls.
        SetCamNearDof(cam, s.dofNear)
        SetCamFarDof(cam, s.dofFar)
        SetCamDofStrength(cam, s.dofStrength)
        SetCamUseShallowDofMode(cam, true)
        SetUseHiDof()
    else
        SetCamUseShallowDofMode(cam, false)
    end

    -- Streaming: without this the world only loads around the player, so a distant camera sees missing map. SetFocusPosAndVel moves the streaming centre. Must be cleared on exit.
    SetFocusPosAndVel(CineCam.x, CineCam.y, CineCam.z, 0.0, 0.0, 0.0)
end

CineCam.Push = pushToEngine


local savedPed = nil

local function prepPed(entering)
    local ped = PlayerPedId()

    if entering then
        savedPed = {
            coords = GetEntityCoords(ped),
            heading = GetEntityHeading(ped),
        }
    end

    SetEntityInvincible(ped, entering)
    FreezeEntityPosition(ped, entering)
    SetEntityVisible(ped, not entering, false)
    SetEntityCollision(ped, not entering, not entering)
    SetPlayerInvincible(PlayerId(), entering)

    -- The ped stays where it was instead of being teleported to the camera, so leaving puts you back where you started.
    if not entering then
        SetEntityAlpha(ped, 255, false)
        ResetEntityAlpha(ped)
    end
end

function CineCam.Enter()
    if CineCam.active then return true end

    local s = S()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local rot = GetGameplayCamRot(2)

    -- Start where the gameplay camera was looking so entering is a cut, not a jump.
    CineCam.x, CineCam.y, CineCam.z = pos.x, pos.y, pos.z + 0.7
    CineCam.pitch, CineCam.yaw, CineCam.roll = rot.x, rot.z, 0.0
    CineCam.tPitch, CineCam.tYaw, CineCam.tRoll = rot.x, rot.z, 0.0
    CineCam.fov, CineCam.tFov = s.fov, s.fov
    CineCam.vx, CineCam.vy, CineCam.vz = 0.0, 0.0, 0.0
    CineCam.scripted = false

    CineCam.handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    pushToEngine()
    RenderScriptCams(true, false, 0, true, true)

    prepPed(true)
    CineLock.SetLocked(not s.allowMenuHotkeys)
    if s.hideHud then CineLock.SetHud(true) end
    SetTimecycleModifier('default')

    -- Applied after the 'default' modifier above, which strips the world's grade. See cl_grade.lua for the hand-off with the player's own filter.
    if CineGrade then CineGrade.Set(s) end

    if s.timescale ~= 1.0 then SetTimeScale(s.timescale) end

    CineCam.active = true
    return true
end

function CineCam.Leave()
    if not CineCam.active then return false end

    CineCam.active = false
    CineCam.scripted = false

    -- cl_path.lua loads after this file, so CinePath is nil at load time. Guarded so leaving the camera works even if it fails to load.
    if CinePath then CinePath.Stop() end

    RenderScriptCams(false, false, 0, true, true)
    if CineCam.handle and DoesCamExist(CineCam.handle) then
        DestroyCam(CineCam.handle, false)
    end
    CineCam.handle = nil

    ClearFocus()
    SetTimeScale(1.0)
    ClearTimecycleModifier()

    -- Applied after ClearTimecycleModifier, which would otherwise strip the player's own grade restored by cl_grade.lua.
    if CineGrade then CineGrade.Release() end

    prepPed(false)
    CineLock.SetLocked(false)
    CineLock.SetHud(false)

    return true
end

function CineCam.Toggle()
    if CineCam.active then CineCam.Leave() else CineCam.Enter() end
    return CineCam.active
end


-- Collision, when enabled. Uses the synchronous LOS probe because the capsule test is asynchronous and would report a wall a couple of frames late.
local function collideStep(fromX, fromY, fromZ, toX, toY, toZ)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        fromX, fromY, fromZ, toX, toY, toZ,
        1 + 16,                 -- world geometry + objects
        PlayerPedId(), 4)

    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 then
        -- Stop a little short of the surface so the near plane does not end up inside the wall.
        return endCoords.x, endCoords.y, endCoords.z, true
    end

    return toX, toY, toZ, false
end

CreateThread(function()
    while true do
        if not CineCam.active then
            Wait(120)
            goto continue
        end

        Wait(0)

        local s  = S()
        local dt = GetFrameTime()
        if dt <= 0.0 then dt = 0.016 end

        if not CineCam.scripted then
            -- Look: read with the DISABLED accessor, since under lockout IsControlPressed / GetControlNormal report disabled controls as neutral.
            -- Look and the wheel (FOV) are suspended while the menu is open. The menu uses SetNuiFocusKeepInput so you can keep flying with the keyboard, but that also passes the mouse through, so reaching for a slider would pan the shot. The camera keeps its target angles and resumes when the panel closes.
            local menu = CineMenu and CineMenu.open

            local mx = menu and 0.0 or GetDisabledControlNormal(0, 1)
            local my = menu and 0.0 or GetDisabledControlNormal(0, 2)

            local look = s.sensitivity * 8.0
            if s.scaleLookByFov then
                -- Scaled by the lens, so a long-lens pan stays steady (12 degrees sweeps a quarter of what 50 does).
                look = look * (CineCam.fov / 50.0)
            end

            CineCam.tYaw   = CineCam.tYaw - mx * look * 24.0
            CineCam.tPitch = CineCam.tPitch + (s.invertY and my or -my) * look * 24.0
            CineCam.tPitch = math.max(-89.0, math.min(89.0, CineCam.tPitch))

            -- FOV: suspended with the look while the menu is open, since the wheel is the lens control.
            if not menu then
                if IsDisabledControlJustPressed(0, 15) then           -- wheel up
                    CineCam.tFov = math.max(Cine.Defaults.fovMin, CineCam.tFov - 2.0)
                elseif IsDisabledControlJustPressed(0, 14) then       -- wheel down
                    CineCam.tFov = math.min(Cine.Defaults.fovMax, CineCam.tFov + 2.0)
                end
            end

            ------------------------------------------------------------ roll
            if IsDisabledControlPressed(0, 44) then               -- Q
                CineCam.tRoll = math.max(-45.0, CineCam.tRoll - 30.0 * dt)
            elseif IsDisabledControlPressed(0, 38) then           -- E
                CineCam.tRoll = math.min(45.0, CineCam.tRoll + 30.0 * dt)
            end

            -------------------------------------------------------- movement
            local fx, fy, fz, rx, ry = basis(CineCam.pitch, CineCam.yaw)

            local dx, dy, dz = 0.0, 0.0, 0.0
            if IsDisabledControlPressed(0, 32) then dx, dy, dz = dx + fx, dy + fy, dz + fz end
            if IsDisabledControlPressed(0, 33) then dx, dy, dz = dx - fx, dy - fy, dz - fz end
            if IsDisabledControlPressed(0, 34) then dx, dy = dx - rx, dy - ry end
            if IsDisabledControlPressed(0, 35) then dx, dy = dx + rx, dy + ry end
            if IsDisabledControlPressed(0, 22) then dz = dz + 1.0 end
            if IsDisabledControlPressed(0, 36) and not IsDisabledControlPressed(0, 21) then
                dz = dz - 1.0
            end

            -- Normalise so diagonals are not 1.41x faster.
            local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
            if mag > 0.0001 then dx, dy, dz = dx / mag, dy / mag, dz / mag end

            local speed = s.speed
            if IsDisabledControlPressed(0, 21) then speed = speed * s.fastMult end
            if IsDisabledControlPressed(0, 36) and IsDisabledControlPressed(0, 21) then
                speed = speed * s.slowMult
            end

            ------------------------------------------------------- smoothing
            local aMove = alphaFor(s.moveSmooth, dt)
            local aLook = alphaFor(s.lookSmooth, dt)
            local aFov  = alphaFor(s.fovSmooth,  dt)
            local aRoll = alphaFor(s.rollSmooth, dt)

            -- Velocity is smoothed, not position. Smoothing position alone lags and stops dead on release; smoothing velocity gives momentum and a coast to a stop.
            CineCam.vx = lerp(CineCam.vx, dx * speed, aMove)
            CineCam.vy = lerp(CineCam.vy, dy * speed, aMove)
            CineCam.vz = lerp(CineCam.vz, dz * speed, aMove)

            local nx = CineCam.x + CineCam.vx * dt
            local ny = CineCam.y + CineCam.vy * dt
            local nz = CineCam.z + CineCam.vz * dt

            if s.collide then
                local hitX, hitY, hitZ, hit = collideStep(CineCam.x, CineCam.y, CineCam.z, nx, ny, nz)
                nx, ny, nz = hitX, hitY, hitZ
                if hit then CineCam.vx, CineCam.vy, CineCam.vz = 0.0, 0.0, 0.0 end
            end

            CineCam.x = nx
            CineCam.y = ny
            CineCam.z = math.max(Cine.Defaults.minZ, math.min(Cine.Defaults.maxZ, nz))

            CineCam.pitch = lerp(CineCam.pitch, CineCam.tPitch, aLook)
            CineCam.yaw   = lerpAngle(CineCam.yaw, CineCam.tYaw, aLook)
            CineCam.roll  = lerp(CineCam.roll, CineCam.tRoll, aRoll)
            CineCam.fov   = lerp(CineCam.fov, CineCam.tFov, aFov)
        end

        pushToEngine()

        ::continue::
    end
end)

--------------------------------------------------------------------------------
-- Safety
--------------------------------------------------------------------------------

-- A camera that outlives its resource leaves the player stuck looking at the sky, so this cleanup is required.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if CineCam.active then CineCam.Leave() end
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    SetTimeScale(1.0)
end)

AddEventHandler('bs:hook:player:unloaded', function()
    if CineCam.active then CineCam.Leave() end
end)
