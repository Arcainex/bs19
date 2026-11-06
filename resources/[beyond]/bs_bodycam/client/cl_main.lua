-- Chest-mounted bodycam view for the local player only. Other players keep seeing the normal ped.
-- The gameplay camera keeps running underneath: it takes the mouse, drives movement and aiming,
-- and this camera rides on the chest and looks at the point the gameplay camera is aimed at.

local UNARMED = GetHashKey('WEAPON_UNARMED')
local GROUP_MELEE, GROUP_UNARMED, GROUP_SNIPER = GetHashKey('GROUP_MELEE'), GetHashKey('GROUP_UNARMED'), GetHashKey('GROUP_SNIPER')
local HEAD = 31086

local cam = nil
local loaded = false
local blocked, soft = {}, {}
-- These menus leave the world view alone, so the bodycam stays up behind them.
local SOFT = { pause = true, radial = true, walkie = true, chat = true }
local stateOn, shown, tcIndex = false, false, nil
local downed, parkour = false, false
local grabbed, grabbedAt = false, 0
local pending = 0.0
local shakeMode, handAmp = nil, 0.0
local lastError = 0

-- Smoothed values
local lagPos, aimBlend, roll, phase, bobAmp, dip, dipVis = nil, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
local airSince, lastHealth = nil, nil
local hitDist, probe, probeAt = 300.0, nil, 0

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function wrap(a) return (a + 180.0) % 360.0 - 180.0 end
local function len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function dirOf(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    return vector3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
end

function BodycamIsActive() return cam ~= nil end

local function impulse(amp) if cam then pending = math.max(pending, amp) end end

local function overlayData()
    return {
        action = 'show',
        film = BodycamPrefs.bcFilm / 100,
        chroma = BodycamPrefs.bcChroma,
        stamp = BodycamPrefs.bcStamp,
        label = tostring(Bodycam.stampLabel or 'BS19 CAM'),
        unit = L('bc.unit', { n = ('%03d'):format(GetPlayerServerId(PlayerId()) % 1000) }),
    }
end

local function overlay(on)
    if on then
        SendNUIMessage(overlayData()); shown = true
    elseif shown then
        SendNUIMessage({ action = 'hide' }); shown = false
    end
end

-- Colour grade. Never replaces a filter another script set (drugs, weather, zones).
local function grade(on)
    local s = BodycamPrefs.bcGrade / 100
    if on and s > 0 then
        local cur = GetTimecycleModifierIndex()
        if tcIndex and cur == tcIndex then SetTimecycleModifierStrength(s) return end
        if cur ~= -1 then return end
        SetTimecycleModifier(Bodycam.timecycle)
        SetTimecycleModifierStrength(s)
        tcIndex = GetTimecycleModifierIndex()
    elseif tcIndex then
        if GetTimecycleModifierIndex() == tcIndex then ClearTimecycleModifier() end
        tcIndex = nil
    end
end

-- foreign: another script's camera is rendering, so leave RenderScriptCams alone.
local function release(foreign)
    if cam then
        if not foreign and GetRenderingCam() == cam then RenderScriptCams(false, false, 0, true, false) end
        SetCamActive(cam, false)
        DestroyCam(cam, false)
        cam = nil
    end
    lagPos, aimBlend, roll, bobAmp, dip, dipVis = nil, 0.0, 0.0, 0.0, 0.0, 0.0
    airSince, lastHealth, probe, pending, shakeMode = nil, nil, nil, 0.0, nil
    grade(false)
    overlay(false)
end

local vOff = false   -- V (next camera) switches to the normal third person until V is pressed again
local function enabled() return loaded and BodycamAllowed() and BodycamPrefs.bcEnabled end
local function wanted() return enabled() and not vOff end

local function setState(on)
    if stateOn ~= on then
        stateOn = on
        -- Field View and the comfort camera step aside while this is set.
        LocalPlayer.state:set('bsBodycam', on, false)
    end
end

local function blockedNow(ped)
    if next(blocked) then return true end
    if IsPedDeadOrDying(ped, true) or downed then return true end
    if (IsPedInAnyVehicle(ped, false) or IsPedGettingIntoAVehicle(ped)) and not BodycamPrefs.bcVehicle then return true end
    if IsCutsceneActive() or IsCutscenePlaying() or IsPlayerSwitchInProgress() then return true end
    if IsCinematicCamRendering() then return true end
    -- Staff noclip hides the ped
    if not IsEntityVisible(ped) then return true end
    if parkour and Bodycam.pauseOnParkour then return true end
    return false
end

local function shake(speed)
    local k = BodycamPrefs.bcShake / 100
    if pending > 0 then
        if k > 0 then ShakeCam(cam, 'SMALL_EXPLOSION_SHAKE', pending * k); shakeMode = 'hit' end
        pending = 0.0
        return
    end
    if shakeMode == 'hit' and not IsCamShaking(cam) then shakeMode = nil end
    if shakeMode == 'hit' then return end
    local hand = Bodycam.handShake * k * (grabbed and 4.0 or 1.0) * (1.0 - aimBlend * 0.5) * (0.6 + math.min(speed, 6.0) / 10.0)
    if hand <= 0.001 then
        if shakeMode == 'hand' then StopCamShaking(cam, true); shakeMode = nil end
    elseif shakeMode ~= 'hand' then
        ShakeCam(cam, 'HAND_SHAKE', hand); shakeMode, handAmp = 'hand', hand
    elseif math.abs(hand - handAmp) > 0.02 then
        SetCamShakeAmplitude(cam, hand); handAmp = hand
    end
end

local function step()
    local ped = PlayerPedId()
    if blockedNow(ped) then release(false) return end

    -- Another camera owns the view (menus, inspect, spectate, focus zoom): wait for it.
    local rc = GetRenderingCam()
    if rc ~= -1 and rc ~= cam then
        if cam then release(true) end
        return
    end

    local weapon = GetSelectedPedWeapon(ped)
    local group = GetWeapontypeGroup(weapon)
    local armed = weapon ~= UNARMED and group ~= GROUP_MELEE and group ~= GROUP_UNARMED
    local aimHeld = armed and (IsControlPressed(0, 25) or IsDisabledControlPressed(0, 25) or IsPlayerFreeAiming(PlayerId()))
    -- Magnified scopes only work through the native scope camera.
    if aimHeld and Bodycam.nativeScopes and group == GROUP_SNIPER then release(false) return end

    local dt = math.min(0.05, GetFrameTime())
    local now = GetGameTimer()
    local motion = BodycamPrefs.bcMotion / 100
    local realistic = BodycamPrefs.bcRealisticAim
    local inVeh = IsPedInAnyVehicle(ped, false)

    if grabbed and now - grabbedAt > 8000 then grabbed = false end

    local bone = GetPedBoneIndex(ped, Bodycam.bone)
    local real = GetWorldPositionOfEntityBone(ped, bone)
    local heading = GetEntityHeading(ped)
    local h = math.rad(heading)
    local fwd, right = vector3(-math.sin(h), math.cos(h), 0.0), vector3(math.cos(h), math.sin(h), 0.0)

    -- Mount trails the body a little
    if not lagPos then lagPos = real end
    lagPos = lagPos + (real - lagPos) * (1.0 - math.exp(-dt * Bodycam.lag))
    local lag = (lagPos - real) * motion
    local ll = len(lag)
    if ll > Bodycam.maxLag then lag = lag * (Bodycam.maxLag / ll) end

    -- Gait bob
    local speed = GetEntitySpeed(ped)
    local amp = 0.0
    if not inVeh then
        if IsPedSprinting(ped) then amp = Bodycam.bob.sprint
        elseif IsPedRunning(ped) then amp = Bodycam.bob.run
        elseif IsPedWalking(ped) then amp = Bodycam.bob.walk end
    end
    amp = amp * motion * (1.0 - aimBlend * 0.7)
    bobAmp = bobAmp + (amp - bobAmp) * math.min(1.0, dt * 6.0)
    phase = (phase + dt * (4.0 + math.min(speed, 8.0) * 1.5)) % (math.pi * 2.0)
    local bobZ = math.sin(phase * 2.0) * bobAmp
    local bobX = math.sin(phase) * bobAmp * 0.6

    -- Landing dip
    local air = IsPedFalling(ped) or IsPedJumping(ped) or IsPedInParachuteFreeFall(ped)
    if air then
        airSince = airSince or now
    elseif airSince then
        local t = (now - airSince) / 1000.0
        airSince = nil
        if t > 0.25 then
            local k = math.min(1.0, t)
            dip = math.max(dip, k)
            impulse(Bodycam.hitShake * 1.5 * k)
        end
    end
    dip = dip * math.exp(-dt * 5.0)
    dipVis = dipVis + (dip - dipVis) * math.min(1.0, dt * 18.0)

    -- Damage taken
    local hp = GetEntityHealth(ped) + GetPedArmour(ped)
    if lastHealth and hp < lastHealth then
        impulse(Bodycam.damageShake * clamp((lastHealth - hp) / 40.0, 0.25, 1.0))
    end
    lastHealth = hp
    if IsPedShooting(ped) then impulse(Bodycam.shotShake) end

    -- Aim blend toward the sights
    local aimTarget = (aimHeld and not realistic) and 1.0 or 0.0
    aimBlend = aimBlend + (aimTarget - aimBlend) * (1.0 - math.exp(-dt * Bodycam.aimSpeed))

    local grot = GetGameplayCamRot(2)
    local gpos = GetGameplayCamCoord()
    local gdir = dirOf(grot)

    -- Looking far past the chest turns the body (idle only; moving and aiming already face the view)
    if not inVeh and not aimHeld and speed < 0.4 and not parkour then
        local rel = wrap(grot.z - heading)
        local c = Bodycam.yawClamp
        if math.abs(rel) > c + 0.5 then
            SetEntityHeading(ped, (grot.z - (rel > 0 and c or -c)) % 360.0)
        end
    end

    local o = Bodycam.offset
    local chest = real + right * (o.x + bobX) + fwd * o.y + vector3(0.0, 0.0, o.z + bobZ - dipVis * Bodycam.landing * motion) + lag
    local target = chest
    if aimBlend > 0.001 then
        local head = GetWorldPositionOfEntityBone(ped, GetPedBoneIndex(ped, HEAD))
        local a = Bodycam.aimOffset
        local gz = math.rad(grot.z)
        local eye = head + vector3(math.cos(gz), math.sin(gz), 0.0) * a.side + gdir * a.forward + vector3(0.0, 0.0, a.up)
        target = chest + (eye - chest) * aimBlend
    end

    -- Look at what the gameplay camera is aimed at, so shots land under the centre of this view.
    local rot = grot
    if not realistic then
        if probe then
            local st, hit, endC = GetShapeTestResult(probe)
            if st ~= 1 then
                if st == 2 then hitDist = (hit == true or hit == 1) and len(endC - gpos) or 300.0 end
                probe = nil
            end
        end
        if not probe and now - probeAt >= 33 then
            -- Start level with the player so nothing behind them counts.
            local s = math.max(0.0, (real.x - gpos.x) * gdir.x + (real.y - gpos.y) * gdir.y + (real.z - gpos.z) * gdir.z)
            local from = gpos + gdir * s
            local to = gpos + gdir * 300.0
            probe = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 511, ped, 7)
            probeAt = now
        end
        local v = (gpos + gdir * hitDist) - target
        if len(v) > 2.0 then
            rot = vector3(math.deg(math.atan(v.z, math.sqrt(v.x * v.x + v.y * v.y))), 0.0, math.deg(math.atan(-v.x, v.y)))
        end
    else
        HideHudComponentThisFrame(14)
    end

    -- Strafe roll and bob tilt
    local vel = GetEntityVelocity(ped)
    local cz = math.rad(rot.z)
    local lateral = vel.x * math.cos(cz) + vel.y * math.sin(cz)
    local rollTarget = inVeh and 0.0 or -clamp(lateral / 5.0, -1.0, 1.0) * Bodycam.strafeRoll * motion
    roll = roll + (rollTarget - roll) * math.min(1.0, dt * 6.0)
    local tiltRoll = math.sin(phase) * bobAmp * 45.0
    local tiltPitch = math.sin(phase * 2.0) * bobAmp * 25.0 - dipVis * 4.0 * motion

    local fov = BodycamPrefs.bcFov + (Bodycam.aimFov - BodycamPrefs.bcFov) * aimBlend

    if not cam then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
        if not cam or cam == 0 then cam = nil; error('camera could not start') end
        SetCamNearClip(cam, Bodycam.nearClip)
        SetCamAffectsAiming(cam, false)
        SetCamCoord(cam, target.x, target.y, target.z)
        SetCamRot(cam, rot.x, 0.0, rot.z, 2)
        SetCamFov(cam, fov)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false)
        overlay(true)
        grade(true)
    end

    -- Offset in body space from the chest bone; the engine keeps it glued to the animated bone.
    local d = target - real
    AttachCamToPedBone(cam, ped, bone, d.x * right.x + d.y * right.y, d.x * fwd.x + d.y * fwd.y, d.z, true)
    SetCamRot(cam, rot.x + tiltPitch + (Bodycam.pitch or 0.0) * (1.0 - aimBlend), roll + tiltRoll, rot.z, 2)
    SetCamFov(cam, fov)
    shake(speed)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local want = wanted()
        setState(want and (BodycamPrefs.bcVehicle or not IsPedInAnyVehicle(ped, false)))
        if not want then
            release(false)
            Wait(250)
        else
            local ok, err = pcall(step)
            if ok then
                Wait(0)
            else
                release(false)
                if GetGameTimer() - lastError > 10000 then
                    lastError = GetGameTimer()
                    print(('^3[bs_bodycam] camera paused: %s^7'):format(tostring(err)))
                end
                Wait(1000)
            end
        end
    end
end)

-- Slow state: character loaded, downed, parkour, colour grade upkeep.
CreateThread(function()
    while true do
        local ok, v = pcall(function() return exports.bs_core:IsLoaded() end)
        loaded = ok and v == true
        local st = LocalPlayer.state
        downed = st.bsDowned == true
        local pk = st.bsParkour
        parkour = type(pk) == 'table' and pk.active == true
        if cam then grade(true) end
        Wait(250)
    end
end)

AddEventHandler('bs:ui:opened', function(name)
    name = name or 'menu'
    if SOFT[name] then soft[name] = true return end
    blocked[name] = true
    release(false)
end)
AddEventHandler('bs:ui:closed', function(name)
    name = name or 'menu'
    blocked[name] = nil
    soft[name] = nil
end)

local function unloaded()
    loaded = false
    blocked, soft = {}, {}
    release(false)
end
AddEventHandler('bs:hook:player:unloaded', unloaded)
AddEventHandler('bs:player:unloaded', unloaded)
local function selectionEnded() blocked.multichar = nil end
AddEventHandler('bs:multichar:spawnRelease', selectionEnded)
AddEventHandler('bs:hook:player:loaded', selectionEnded)

-- Your own melee hits
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not cam then return end
    local ped = PlayerPedId()
    if args[2] ~= ped or args[1] == ped then return end
    local g = GetWeapontypeGroup(args[7] or 0)
    if g == GROUP_MELEE or g == GROUP_UNARMED then impulse(Bodycam.hitShake) end
end)

-- A walker grabs you
RegisterNetEvent('bs:z:grabbed', function(_, victimSrc, holding)
    if victimSrc ~= GetPlayerServerId(PlayerId()) then return end
    grabbed = holding == true
    grabbedAt = GetGameTimer()
    if grabbed then impulse(Bodycam.grabShake) end
end)

BodycamOnChange(function()
    if not BodycamPrefs.bcEnabled then release(false) return end
    if cam then overlay(true); grade(true) end
end)

AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function()
    if not BodycamAllowed() and BodycamPrefs.bcEnabled and cam then
        release(false)
        BodycamNotify('bc.disabled', 'error')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    release(false)
    LocalPlayer.state:set('bsBodycam', false, false)
end)

-- V: bodycam off (normal third person) / back on. GTA's own camera cycling is blocked meanwhile.
CreateThread(function()
    while true do
        if enabled() then
            DisableControlAction(0, 0, true)
            if IsDisabledControlJustPressed(0, 0) then
                vOff = not vOff
                if vOff then release(false); SetFollowPedCamViewMode(1) end
            end
            Wait(0)
        else
            vOff = false
            Wait(500)
        end
    end
end)
