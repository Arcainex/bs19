-- Bodycam view for the local player only. Other players keep seeing the normal ped.
-- Runs on GTA's first-person gameplay camera (view mode 4) so the arms, weapon and sights stay native;
-- the bodycam feel is layered on top with gameplay-cam shake, a colour grade and the NUI lens overlay.

local GROUP_MELEE, GROUP_UNARMED = GetHashKey('GROUP_MELEE'), GetHashKey('GROUP_UNARMED')
local FP = 4

local loaded = false
local blocked, soft = {}, {}
-- These menus leave the world view alone, so the effects stay up behind them.
local SOFT = { pause = true, radial = true, walkie = true, chat = true }
local stateOn, shown, tcIndex = false, false, nil
local downed, parkour = false, false
local grabbed, grabbedAt = false, 0
local active = false               -- first person is forced
local live = false                 -- effects are showing
local prevMode, prevVehMode = nil, nil
local pending, pendingType = 0.0, 'SMALL_EXPLOSION_SHAKE'
local shakeMode, handAmp = nil, 0.0
local airSince, lastHealth = nil, nil
local vOff = false                 -- V switches to third person until V is pressed again
local lastError = 0

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function BodycamIsActive() return live end

local function impulse(kind, amp)
    if not live or amp <= pending then return end
    pending, pendingType = amp, kind
end

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

-- Effects off; the view mode is left as it is (menus, death and cutscenes come back to it).
local function suspend()
    if shakeMode then StopGameplayCamShaking(true); shakeMode = nil end
    pending, airSince, lastHealth = 0.0, nil, nil
    live = false
    grade(false)
    overlay(false)
end

-- Full stop: effects off and the player's previous view modes back.
local function release()
    suspend()
    if active then
        active = false
        if prevMode and prevMode ~= FP and GetFollowPedCamViewMode() == FP then SetFollowPedCamViewMode(prevMode) end
        if prevVehMode and prevVehMode ~= FP and GetFollowVehicleCamViewMode() == FP then SetFollowVehicleCamViewMode(prevVehMode) end
        prevMode, prevVehMode = nil, nil
    end
end

local function enabled() return loaded and BodycamAllowed() and BodycamPrefs.bcEnabled end
local function wanted() return enabled() and not vOff end

local function setState(on)
    if stateOn ~= on then
        stateOn = on
        -- Field View and the comfort camera step aside while this is set.
        LocalPlayer.state:set('bsBodycam', on, false)
    end
end

-- Times when the bodycam effects pause without giving up first person.
local function pausedNow(ped)
    if next(blocked) then return true end
    if IsPedDeadOrDying(ped, true) or downed then return true end
    if IsCutsceneActive() or IsCutscenePlaying() or IsPlayerSwitchInProgress() then return true end
    if IsCinematicCamRendering() then return true end
    if not IsEntityVisible(ped) then return true end   -- staff noclip hides the ped
    if GetRenderingCam() ~= -1 then return true end     -- a menu, inspect or spectate camera owns the view
    return false
end

local function gait(ped)
    if IsPedSprinting(ped) then return Bodycam.moveShake.sprint end
    if IsPedRunning(ped) then return Bodycam.moveShake.run end
    if IsPedWalking(ped) then return Bodycam.moveShake.walk end
    return 0.0
end

local function shake(ped, aiming, inVeh)
    local k = BodycamPrefs.bcShake / 100
    if pending > 0 then
        if k > 0 then ShakeGameplayCam(pendingType, pending * k); shakeMode = 'hit' end
        pending = 0.0
        return
    end
    if shakeMode == 'hit' then
        if IsGameplayCamShaking() then return end
        shakeMode = nil
    end
    local hand = Bodycam.handShake * k * (grabbed and Bodycam.grabbedMult or 1.0) * (aiming and Bodycam.aimShakeMult or 1.0)
    if not inVeh then hand = hand + gait(ped) * (BodycamPrefs.bcMotion / 100) * (aiming and 0.5 or 1.0) end
    if hand <= 0.01 then
        if shakeMode == 'hand' then StopGameplayCamShaking(true); shakeMode = nil end
    elseif shakeMode ~= 'hand' or not IsGameplayCamShaking() then
        ShakeGameplayCam('HAND_SHAKE', hand); shakeMode, handAmp = 'hand', hand
    elseif math.abs(hand - handAmp) > 0.03 then
        -- ease toward the new amplitude so gait changes don't pop
        handAmp = handAmp + (hand - handAmp) * 0.25
        SetGameplayCamShakeAmplitude(handAmp)
    end
end

local function step()
    local ped = PlayerPedId()
    local inVeh = IsPedInAnyVehicle(ped, false)

    if not active then
        active = true
        prevMode, prevVehMode = GetFollowPedCamViewMode(), GetFollowVehicleCamViewMode()
    end

    if pausedNow(ped) then
        if live then suspend() end
        return
    end

    -- Hold first person; vehicles only when the player asked for it.
    if inVeh then
        if not BodycamPrefs.bcVehicle then
            if live then suspend() end
            return
        end
        if Bodycam.vehicleFirstPerson and GetFollowVehicleCamViewMode() ~= FP then SetFollowVehicleCamViewMode(FP) end
    elseif GetFollowPedCamViewMode() ~= FP then
        SetFollowPedCamViewMode(FP)
    end

    if not live then
        live = true
        overlay(true)
        grade(true)
    end

    local now = GetGameTimer()
    if grabbed and now - grabbedAt > 8000 then grabbed = false end

    -- Landing jolt
    local air = IsPedFalling(ped) or IsPedJumping(ped) or IsPedInParachuteFreeFall(ped)
    if air then
        airSince = airSince or now
    elseif airSince then
        local t = (now - airSince) / 1000.0
        airSince = nil
        if t > 0.25 then impulse('JOLT_SHAKE', Bodycam.landShake * math.min(1.0, t) * (0.5 + BodycamPrefs.bcMotion / 200)) end
    end

    -- Damage taken
    local hp = GetEntityHealth(ped) + GetPedArmour(ped)
    if lastHealth and hp < lastHealth then
        impulse('SMALL_EXPLOSION_SHAKE', Bodycam.damageShake * clamp((lastHealth - hp) / 40.0, 0.25, 1.0))
    end
    lastHealth = hp

    local aiming = IsPlayerFreeAiming(PlayerId())
    if BodycamPrefs.bcRealisticAim and not aiming then HideHudComponentThisFrame(14) end
    shake(ped, aiming, inVeh)
end

CreateThread(function()
    while true do
        local want = wanted()
        setState(want)
        if not want then
            release()
            Wait(250)
        else
            local ok, err = pcall(step)
            if ok then
                Wait(0)
            else
                suspend()
                if GetGameTimer() - lastError > 10000 then
                    lastError = GetGameTimer()
                    print(('^3[bs_bodycam] effects paused: %s^7'):format(tostring(err)))
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
        if live then grade(true) end
        Wait(250)
    end
end)

AddEventHandler('bs:ui:opened', function(name)
    name = name or 'menu'
    if SOFT[name] then soft[name] = true return end
    blocked[name] = true
    if live then suspend() end
end)
AddEventHandler('bs:ui:closed', function(name)
    name = name or 'menu'
    blocked[name] = nil
    soft[name] = nil
end)

local function unloaded()
    loaded = false
    blocked, soft = {}, {}
    release()
end
AddEventHandler('bs:hook:player:unloaded', unloaded)
AddEventHandler('bs:player:unloaded', unloaded)
local function selectionEnded() blocked.multichar = nil end
AddEventHandler('bs:multichar:spawnRelease', selectionEnded)
AddEventHandler('bs:hook:player:loaded', selectionEnded)

-- Your own melee hits
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not live then return end
    local ped = PlayerPedId()
    if args[2] ~= ped or args[1] == ped then return end
    local g = GetWeapontypeGroup(args[7] or 0)
    if g == GROUP_MELEE or g == GROUP_UNARMED then impulse('SMALL_EXPLOSION_SHAKE', Bodycam.hitShake) end
end)

-- A walker grabs you
RegisterNetEvent('bs:z:grabbed', function(_, victimSrc, holding)
    if victimSrc ~= GetPlayerServerId(PlayerId()) then return end
    grabbed = holding == true
    grabbedAt = GetGameTimer()
    if grabbed then impulse('MEDIUM_EXPLOSION_SHAKE', Bodycam.grabShake) end
end)

BodycamOnChange(function()
    if not BodycamPrefs.bcEnabled then release() return end
    if live then overlay(true); grade(true) end
end)

AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function()
    if not BodycamAllowed() and BodycamPrefs.bcEnabled and active then
        release()
        BodycamNotify('bc.disabled', 'error')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    release()
    LocalPlayer.state:set('bsBodycam', false, false)
end)

-- V: bodycam off (normal third person) / back on. GTA's own camera cycling is blocked meanwhile.
CreateThread(function()
    while true do
        if enabled() and not IsPedInAnyVehicle(PlayerPedId(), false) then
            DisableControlAction(0, 0, true)
            if IsDisabledControlJustPressed(0, 0) then
                vOff = not vOff
                if vOff then release(); SetFollowPedCamViewMode(1) end
            end
            Wait(0)
        elseif not enabled() then
            vOff = false
            Wait(500)
        else
            Wait(250)
        end
    end
end)
