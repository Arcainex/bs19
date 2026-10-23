-- bs_emotes - hold TAB to focus (Scoped focus Survival perk).
-- TAB is the weapon wheel, so it is blocked every frame while we own the key. There is no native to set the gameplay camera FOV, so a scripted camera mirrors the gameplay camera with a tighter FOV and a small shoulder offset; mouse look keeps working.

Focus = { active = false, t = 0.0 }

local cfg = Emotes.Focus
local heldSince = nil
local cam = nil
local baseFov = 50.0

-- Ease in-out cubic, so the zoom does not snap.
local function ease(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = (2 * t) - 2
    return 0.5 * f * f * f + 1
end

local function hasScopedFocus()
    if GetResourceState('bs_skills') ~= 'started' then return false end
    local ok, owned = pcall(function()
        return exports.bs_skills:HasPerk('scoped_focus')
    end)
    return ok and owned == true
end

local function canFocus()
    if LocalPlayer.state.bsDrone then return false end
    local ped = PlayerPedId()
    if not exports.bs_core:IsLoaded() then return false end
    if not hasScopedFocus() then return false end
    if IsEntityDead(ped) then return false end
    if IsPauseMenuActive() then return false end
    if GetResourceState('bs_inventory') == 'started' and exports.bs_inventory:IsOpen() then return false end
    return true
end

local function destroyCam()
    if not cam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, true)
    cam = nil
end

-- PERF: cross-resource exports are not free and this loop runs every frame, so the loaded flag is re-read from bs_core at most every 250ms.
local _perfLoadedAt, _perfLoaded = 0, false
local function loadedCached()
    local now = GetGameTimer()
    if now - _perfLoadedAt >= 250 then
        _perfLoadedAt = now
        local ok, v = pcall(function() return exports.bs_core:IsLoaded() end)
        _perfLoaded = ok and v == true
    end
    return _perfLoaded
end

CreateThread(function()
    while true do
        Wait(0)

        -- Own the key every frame, focusing or not. Partial blocking causes the wheel sound and blur.
        local ped = PlayerPedId()
        local loaded = loadedCached()

        if loaded then
            DisableControlAction(0, 37, true)      -- INPUT_SELECT_WEAPON (TAB)
            BlockWeaponWheelThisFrame()
            HudWeaponWheelIgnoreSelection()
        end

        local key = loaded and IsDisabledControlPressed(0, 37)
        local wants = key and canFocus()

        if wants and not heldSince then heldSince = GetGameTimer() end
        if not wants then heldSince = nil end

        local shouldFocus = heldSince and (GetGameTimer() - heldSince) >= (cfg.holdMs or 180)

        local step = GetFrameTime() / ((shouldFocus and cfg.easeIn or cfg.easeOut) or 0.5)
        Focus.t = math.max(0.0, math.min(1.0, Focus.t + (shouldFocus and step or -step)))

        if Focus.t > 0.001 then
            if not cam then
                baseFov = GetGameplayCamFov()
                cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
                SetCamActive(cam, true)
                RenderScriptCams(true, false, 0, true, true)
            end

            local blend = ease(Focus.t)
            local target = Focus.TargetFov()

            -- Aiming already tightens the game camera to around 40, so the lens works from the live camera FOV and goes a step past the aim zoom while aiming.
            local liveFov = GetGameplayCamFov()
            if IsPlayerFreeAiming(PlayerId()) then
                target = math.min(target, liveFov * (cfg.aimZoomFactor or 0.55))
            end
            baseFov = liveFov

            -- Mirror the gameplay camera so mouse look is untouched, then bias it over the shoulder and tighten the lens.
            local coords = GetGameplayCamCoord()
            local rot = GetGameplayCamRot(2)
            local off = cfg.offset or { x = 0.0, y = 0.0, z = 0.0 }

            local yaw = math.rad(rot.z)
            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)

            -- The shoulder offset is right in third person but moves the lens off the weapon optic in first person, so only the FOV changes there.
            local firstPerson = GetFollowPedCamViewMode() == 4
            local shoulder = firstPerson and 0.0 or (off.x or 0.0)
            local vertical = firstPerson and 0.0 or (off.z or 0.0)
            local shifted = coords + right * (shoulder * blend)

            SetCamCoord(cam, shifted.x, shifted.y, shifted.z + vertical * blend)
            SetCamRot(cam, rot.x, rot.y, rot.z, 2)
            SetCamFov(cam, baseFov + (target - baseFov) * blend)

            -- A scripted camera hides the normal aiming reticle. Restore it only for third-person weapon aiming.
            if not firstPerson and IsPlayerFreeAiming(PlayerId()) then
                ShowHudComponentThisFrame(14) -- HUD_RETICLE
            end

            if cfg.blockSprint then DisableControlAction(0, 21, true) end

            if not Focus.active and blend > 0.05 then
                Focus.active = true
                TriggerEvent('bs:emotes:focus', true)
            end
        elseif cam then
            destroyCam()
            Focus.active = false
            TriggerEvent('bs:emotes:focus', false)
        end
    end
end)

-- Focus tightens with each Survival level: base FOV at level 0, scope-like at the cap. Smaller FOV means more zoom, so the per-level value is subtracted.
function Focus.TargetFov()
    local base = cfg.fov or 32.0
    local level = 0

    if GetResourceState('bs_skills') == 'started' then
        local ok, value = pcall(function() return exports.bs_skills:GetSkillLevel('survival') end)
        if ok and type(value) == 'number' then level = value end
    end

    local perLevel = cfg.fovPerSkillLevel or 0.55
    local floor    = cfg.fovMin or 16.0

    return math.max(floor, base - (level * perLevel))
end

-- Is the player holding TAB to focus, and by how much?
-- Other resources cannot read Focus.t directly, so this is the way to ask. Thresholded at half because Focus.t eases continuously and a bare truthiness test flickers.
exports('Focusing', function()
    return Focus.t > 0.5
end)

-- Raw 0..1 focus amount, for anything that fades with the lens.
exports('FocusAmount', function() return Focus.t end)

-- What the UI shows: 1.0 at no skill, rising as the lens tightens.
exports('FocusZoom', function()
    local base = cfg.fov or 32.0
    return base / Focus.TargetFov()
end)

AddEventHandler('bs:hook:player:unloaded', destroyCam)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then destroyCam() end
end)

exports('IsFocused', function() return Focus.active end)
