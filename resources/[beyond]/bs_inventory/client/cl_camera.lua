-- Optional camera comfort settings. Everything is off by default and saved per player (KVP).
-- Smooth look: mouse look is read raw, low-passed, then applied to the gameplay camera.

local KVP = 'bs_camera_v1'

local cfg = {
    smooth = false,      -- smooth mouse look
    amount = 40,         -- 0..100 smoothing strength
    aim = 'reduced',     -- 'reduced' | 'off' (smoothing while aiming)
    sway = false,        -- subtle walking sway
    fov = false,         -- slightly lower field of view
    chase = false,       -- softer vehicle chase camera
}

local function load()
    local ok, saved = pcall(function() return json.decode(GetResourceKvpString(KVP) or '') end)
    if ok and type(saved) == 'table' then
        if type(saved.smooth) == 'boolean' then cfg.smooth = saved.smooth end
        if tonumber(saved.amount) then cfg.amount = math.max(0, math.min(100, tonumber(saved.amount))) end
        if saved.aim == 'reduced' or saved.aim == 'off' then cfg.aim = saved.aim end
        if type(saved.sway) == 'boolean' then cfg.sway = saved.sway end
        if type(saved.fov) == 'boolean' then cfg.fov = saved.fov end
        if type(saved.chase) == 'boolean' then cfg.chase = saved.chase end
    end
end
load()

local function save() SetResourceKvp(KVP, json.encode(cfg)) end

-- Tuning: degrees of turn per unit of mouse input, and limits.
local YAW_GAIN, PITCH_GAIN = 7.0, 5.0
local PITCH_MIN, PITCH_MAX = -70.0, 45.0
local FOV_SCALE = 0.92
local TAU_MAX = 0.20     -- seconds at amount 100
local AIM_KEEP = 0.2     -- share of smoothing kept while aiming (reduced mode)

local vx, vy = 0.0, 0.0
local HoldH, HoldP = nil, nil
local cam, camRot, camPos = nil, nil, nil
local swayOn = false
local VehCamHandle = function() return nil end  -- set by the vehicle cam block

local function lerpAngle(a, b, t)
    local d = ((b - a + 180.0) % 360.0) - 180.0
    return a + d * t
end

local function alphaFor(tau, dt)
    if tau <= 0.001 then return 1.0 end
    return 1.0 - math.exp(-dt / tau)
end

local function firstPerson(ped)
    if IsPedInAnyVehicle(ped, false) then return GetFollowVehicleCamViewMode() == 4 end
    return GetFollowPedCamViewMode() == 4
end

local function releaseCam()
    if cam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
        cam, camRot, camPos = nil, nil, nil
    end
end

local function scoped(ped)
    local w = GetSelectedPedWeapon(ped)
    return w and GetWeapontypeGroup(w) == 3082541095 and IsPlayerFreeAiming(PlayerId())
end

-- Smooth look: runs every frame only while enabled.
local function lookStep(ped, dt)
    local aiming = IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, 25)
    -- Raw input while aiming, in vehicles or looking back (C): the game owns the camera there.
    -- Ragdoll/falling: the game snaps the camera itself, writing heading then flickers.
    -- Vehicles: the game camera is left fully native (smoothing and holding both fought driving).
    if IsPedInAnyVehicle(ped, false) then vx, vy = 0.0, 0.0; HoldH, HoldP = nil, nil; return end
    if aiming or IsControlPressed(0, 26) or IsDisabledControlPressed(0, 26) or IsControlPressed(0, 79)
        or IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedGettingUp(ped) then
        vx, vy = 0.0, 0.0 return
    end
    -- Controller input is already analogue; leave it alone.
    if not IsInputDisabled(2) then vx, vy = 0.0, 0.0 return end

    -- Yaw only. Writing the gameplay pitch back fights the game's own pitch recentering
    -- (running, slopes, cars), which is what pulled the camera down. Pitch stays native.
    DisableControlAction(0, 1, true)
    local ix = GetDisabledControlNormal(0, 1)
    local iy = 0.0

    local tau = (cfg.amount / 100.0) * TAU_MAX
    if aiming then tau = tau * AIM_KEEP end
    local a = alphaFor(tau, dt)
    vx = vx + (ix - vx) * a
    vy = vy + (iy - vy) * a

    if math.abs(vx) < 0.0005 and ix == 0.0 then vx = 0.0 end
    if math.abs(vy) < 0.0005 and iy == 0.0 then vy = 0.0 end

    -- In vehicles the game recentres the camera behind the car; hold the player's last angles instead.
    if IsPedInAnyVehicle(ped, false) then
        if ix ~= 0.0 or IsControlPressed(0, 2) or not HoldH then
            HoldH, HoldP = GetGameplayCamRelativeHeading(), GetGameplayCamRelativePitch()
        else
            SetGameplayCamRelativeHeading(HoldH); SetGameplayCamRelativePitch(HoldP, 1.0)
        end
    else HoldH, HoldP = nil, nil end
    -- Only write when there is motion, so the game's own recentering (running) is not fought.
    if vx ~= 0.0 then SetGameplayCamRelativeHeading(GetGameplayCamRelativeHeading() - vx * YAW_GAIN) end

end

-- Mirror camera: follows the gameplay camera with a lower FOV and, in vehicles, a little lag.
local function mirrorStep(ped, dt, wantFov, wantChase)
    if not cam then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        camRot, camPos = nil, nil
    end
    local pos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()
    if wantFov then fov = fov * FOV_SCALE end

    if wantChase and camRot then
        local a = alphaFor(0.09, dt)
        rot = vector3(lerpAngle(camRot.x, rot.x, a), lerpAngle(camRot.y, rot.y, a), lerpAngle(camRot.z, rot.z, a))
    end
    camRot, camPos = rot, pos

    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
end

local function swayStep(ped)
    local moving = not IsPedInAnyVehicle(ped, false) and GetEntitySpeed(ped) > 0.8
        and not IsPedInCover(ped, false) and not IsPlayerFreeAiming(PlayerId())
    if moving and not swayOn then
        ShakeGameplayCam('HAND_SHAKE', 0.05)
        swayOn = true
    elseif not moving and swayOn then
        StopGameplayCamShaking(true)
        swayOn = false
    end
    if swayOn then
        SetGameplayCamShakeAmplitude(GetEntitySpeed(ped) > 4.0 and 0.09 or 0.05)
    end
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        local active = cfg.smooth or cfg.sway or cfg.fov or cfg.chase
        if not active then
            if cam then releaseCam() end
            if swayOn then StopGameplayCamShaking(true); swayOn = false end
            vx, vy = 0.0, 0.0
            Wait(500)
        else
            Wait(0)
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - last) / 1000.0)
            last = now

            local ped = PlayerPedId()
            -- NUI focus (inventory, chat) only pauses look smoothing; the FOV camera stays, so no zoom jump.
            local uiOpen = IsNuiFocused()
            local busy = IsPauseMenuActive() or IsPedDeadOrDying(ped, true)
                or IsCinematicCamRendering() or firstPerson(ped)
            -- Another script owns the view (cutscene, inspect cam): step aside.
            local rc = GetRenderingCam()
            local foreign = rc ~= -1 and rc ~= cam and rc ~= VehCamHandle()

            if foreign and cam then
                -- Another camera (inventory ped view) took over: drop ours without RenderScriptCams(false),
                -- which would switch that camera off too.
                SetCamActive(cam, false); DestroyCam(cam, false); cam, camRot, camPos = nil, nil, nil
            end
            if busy or foreign then
                if cam then releaseCam() end
                if swayOn then StopGameplayCamShaking(true); swayOn = false end
                vx, vy = 0.0, 0.0
            else
                local inVeh = IsPedInAnyVehicle(ped, false)
                if (cfg.smooth or (cfg.chase and inVeh)) and not uiOpen then lookStep(ped, dt) else vx, vy = 0.0, 0.0 end
                if cfg.sway then swayStep(ped) elseif swayOn then StopGameplayCamShaking(true); swayOn = false end
                -- Vehicle smoothing now goes through lookStep (yaw); the scripted chase cam is retired.
                local wantChase = false
                local lookBack = IsControlPressed(0, 26) or IsDisabledControlPressed(0, 26) or IsControlPressed(0, 79)
                if lookBack then wantChase = false end
                -- No scripted FOV cam in vehicles: it copies the gameplay cam a frame late, which jitters at speed.
                local wantFov = cfg.fov and not inVeh and not scoped(ped) and not lookBack and not IsPlayerFreeAiming(PlayerId())
                if wantChase or wantFov then mirrorStep(ped, dt, wantFov, wantChase)
                elseif cam then releaseCam() end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    releaseCam()
    if swayOn then StopGameplayCamShaking(true) end
end)

exports('GetCameraSettings', function()
    return { camSmooth = cfg.smooth, camSmoothAmount = cfg.amount, camSmoothAim = cfg.aim,
             camSway = cfg.sway, camFov = cfg.fov, camChase = cfg.chase }
end)

exports('SetCameraSetting', function(key, v)
    if key == 'camSmooth' then cfg.smooth = v == true
    elseif key == 'camSmoothAmount' then cfg.amount = math.max(0, math.min(100, tonumber(v) or cfg.amount))
    elseif key == 'camSmoothAim' then cfg.aim = (v == 'off') and 'off' or 'reduced'
    elseif key == 'camSway' then cfg.sway = v == true
    elseif key == 'camFov' then cfg.fov = v == true
    elseif key == 'camChase' then cfg.chase = v == true
    else return false end
    save()
    return true
end)

-- Vehicle chase camera (controller feel). The cam is attached to the vehicle with a
-- world-axis offset, so the engine places it at render time (no position jitter).
-- Yaw = damped vehicle heading + player orbit. Orbit eases back after 1.5 s idle.
do
    local vcam, vveh = nil, 0
    local follow, orbit, tOrbit, pitch, tPitch = 0.0, 0.0, 0.0, -8.0, -8.0
    local dist, idle, last = 0.0, 0.0, 0
    local size, topZ = 4.0, 1.5
    local PITCH_REST = -8.0

    local function wrap(a) return ((a + 180.0) % 360.0) - 180.0 end
    local function damp(cur, tgt, tau, dt) return cur + (tgt - cur) * (1.0 - math.exp(-dt / tau)) end
    local function dampAngle(cur, tgt, tau, dt) return wrap(cur + wrap(tgt - cur) * (1.0 - math.exp(-dt / tau))) end

    -- handOff: keep the gameplay cam facing where ours was, so leaving does not snap.
    local function vrelease(foreign)
        if not vcam then return end
        if foreign then
            -- Another script's cam is rendering: never call RenderScriptCams(false) over it.
            SetCamActive(vcam, false)
        else
            if vveh ~= 0 and DoesEntityExist(vveh) then
                SetGameplayCamRelativeHeading(wrap(follow + orbit - GetEntityHeading(vveh)))
            end
            RenderScriptCams(false, false, 0, true, false)
        end
        DestroyCam(vcam, false)
        vcam, vveh = nil, 0
    end
    VehCamHandle = function() return vcam end  -- upvalue from top of file

    local function start(veh)
        local mn, mx = GetModelDimensions(GetEntityModel(veh))
        size = math.max(mx.y - mn.y, mx.x - mn.x)
        topZ = mx.z
        follow = GetEntityHeading(veh)
        orbit = wrap(GetGameplayCamRelativeHeading()); tOrbit = orbit
        pitch, tPitch, idle = PITCH_REST, PITCH_REST, 0.0
        dist = 3.2 + size * 0.9
        vcam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(vcam, GetGameplayCamFov())
        vveh = veh
        SetCamActive(vcam, true)
        RenderScriptCams(true, false, 0, true, false)
        last = GetGameTimer()
    end

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local lookBack = IsControlPressed(0, 79) or IsControlPressed(0, 26) or IsDisabledControlPressed(0, 26)
            local want = (cfg.smooth or cfg.chase) and veh ~= 0 and not IsNuiFocused() and not IsPauseMenuActive()
                and GetFollowVehicleCamViewMode() ~= 4 and not IsPlayerFreeAiming(PlayerId())
                and not lookBack and not IsPedDeadOrDying(ped, true) and not IsCinematicCamRendering()
            local rc = GetRenderingCam()
            local foreign = rc ~= -1 and rc ~= vcam
            if foreign then want = false end
            if want and vcam and veh ~= vveh then vrelease(false) end

            if not want then
                vrelease(foreign)
                Wait(veh ~= 0 and 0 or 300)
            else
                if not vcam then start(veh) end
                Wait(0)
                local now = GetGameTimer(); local dt = math.min(0.1, (now - last) / 1000.0); last = now
                if dt <= 0.0 then dt = 0.001 end

                -- Look input only drives our cam; steering controls are never touched.
                -- Mouse-steer override held (106): leave the mouse to steering.
                DisableControlAction(0, 1, true); DisableControlAction(0, 2, true)
                local ix, iy = 0.0, 0.0
                if not IsControlPressed(0, 106) then
                    ix, iy = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
                end
                local mouse = IsInputDisabled(2)
                local gy, gp = 9.0, 6.0
                if not mouse then gy, gp = 160.0 * dt, 100.0 * dt end   -- stick is a rate, not a delta
                if math.abs(ix) > 0.001 or math.abs(iy) > 0.001 then idle = 0.0 else idle = idle + dt end
                tOrbit = wrap(tOrbit - ix * gy)
                tPitch = math.max(-40.0, math.min(25.0, tPitch - iy * gp))

                local speed = GetEntitySpeed(veh)
                if idle > 1.5 and speed > 5.0 then
                    tOrbit = dampAngle(tOrbit, 0.0, 0.45, dt)
                    tPitch = damp(tPitch, PITCH_REST, 0.45, dt)
                end

                -- Input smoothing (cfg.amount), then follow the car's heading with a soft lag.
                local tau = 0.03 + (cfg.amount / 100.0) * 0.22
                orbit = dampAngle(orbit, tOrbit, tau, dt)
                pitch = damp(pitch, tPitch, tau, dt)
                follow = dampAngle(follow, GetEntityHeading(veh), cfg.chase and 0.22 or 0.12, dt)

                local h, pr = math.rad(follow + orbit), math.rad(pitch)
                local pivotZ = topZ * 0.6
                local want_d = 3.2 + size * 0.9
                local ox = math.sin(h) * math.cos(pr)
                local oy = -math.cos(h) * math.cos(pr)
                local oz = -math.sin(pr)

                -- Collision: pull in at once, ease back out.
                local p = GetEntityCoords(veh)
                local px, py, pz = p.x, p.y, p.z + pivotZ
                local ray = StartExpensiveSynchronousShapeTestLosProbe(px, py, pz,
                    px + ox * want_d, py + oy * want_d, pz + oz * want_d + 0.6, 17, veh, 7)
                local _, hit, endC = GetShapeTestResult(ray)
                local d = want_d
                if hit == 1 then
                    d = math.max(1.0, #(vector3(endC.x, endC.y, endC.z) - vector3(px, py, pz)) - 0.35)
                end
                if d < dist then dist = d else dist = damp(dist, d, 0.35, dt) end

                AttachCamToEntity(vcam, veh, ox * dist, oy * dist, pivotZ + oz * dist + 0.6, false)
                PointCamAtEntity(vcam, veh, 0.0, 0.0, pivotZ, true)
            end
        end
    end)
    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        local rc = GetRenderingCam()
        vrelease(rc ~= -1 and rc ~= vcam)
    end)
end
