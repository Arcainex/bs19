-- bs_skills - weapon sway, stronger at low combat skill.
-- Skills.Sway.mode: 'aim' offsets the aim point, 'crosshair' only wobbles the reticle, 'both' does both.
-- Sway is the per-frame delta of two slow sines (0.31 and 0.79 Hz) added to camera pitch/heading, so mouse input is kept and the offset stays bounded. No camera shake (nausea).
-- Exactly 0 at max skill and when no firearm is aimed.
-- NOTE: the heading part is unreliable in third person free-aim (the engine rewrites it from the mouse); vertical carries most of the effect and the reticle shows the error. /skilltest prints the resolved amplitude.

-- Declarations first: in Lua a `local` used above its declaration is a nil global.

local cfg                       -- Skills.Sway
local prevX, prevY = 0.0, 0.0   -- last frame's offset, for the delta
local seed         = 0.0        -- per-session phase, so two players differ
local lastDebugAt  = 0
local lastStepAt   = 0
local loopAlive    = false      -- for /skilltest
local bootState    = 'not started'
local lastActive   = false      -- for /skilltest
local lastFactor   = 0.0        -- for /skilltest
local lastReason   = 'never evaluated'

--- Shared with cl_dodge.lua and cl_skilldebug.lua. One Lua state per resource,
--- so a global is the whole mechanism. See the note in cl_dodge.lua.
BS_SkillsDebug = BS_SkillsDebug or {}

local UNARMED = GetHashKey('WEAPON_UNARMED')

--------------------------------------------------------------------------------
-- How much sway, right now
--------------------------------------------------------------------------------

local function combatLevel()
    local tree = (cfg and cfg.tree) or 'combat'
    local ok, level = pcall(function() return exports.bs_skills:GetSkillLevel(tree) end)
    if ok and type(level) == 'number' then return level end
    return 0
end

local function hasSteadyHands()
    local ok, value = pcall(function()
        return exports.bs_skills:HasPerk((cfg and cfg.tree) or 'combat', 'steady_hands')
    end)
    return ok and value == true
end

-- 1.0 at zero skill, exactly 0.0 at `zeroAtLevel` (hard early return, before the situational multipliers).
local function skillFactor()
    local zeroAt = cfg.zeroAtLevel or 20
    local level  = combatLevel()

    if level >= zeroAt then return 0.0 end

    local remaining = 1.0 - (level / math.max(1, zeroAt))
    local factor    = remaining ^ (cfg.curve or 1.0)

    if hasSteadyHands() then
        factor = factor * (1.0 - (cfg.perkBonus or 0.0))
    end

    return math.max(0.0, factor)
end

--- Stance, movement and being out of breath, on top of the skill.
local function situationalMultiplier(ped)
    local m = 1.0

    if IsPedRunning(ped) or IsPedSprinting(ped) or IsPedWalking(ped) then
        m = m * (cfg.movingMultiplier or 1.0)
    end

    -- Crouch/prone state belongs to bs_emotes, so ask it through its exports. `Crouch.active` would be nil here (each resource has its own Lua state).
    -- Guarded on the resource being started.
    if GetResourceState('bs_emotes') == 'started' then
        local okStance, low = pcall(function()
            return exports.bs_emotes:IsCrouched() or exports.bs_emotes:IsProne()
        end)
        if okStance and low == true then
            m = m * (cfg.crouchMultiplier or 1.0)
        end
    end

    -- bs_drugs: amphetamine steadies, withdrawal shakes.
    local dm = LocalPlayer.state.bsDrugMods
    if type(dm) == 'table' and tonumber(dm.sway) then m = m * dm.sway end

    local okNeeds, needs = pcall(function() return exports.bs_core:GetNeeds() end)
    if okNeeds and type(needs) == 'table' and type(needs.stamina) == 'number' then
        local from = cfg.windedFrom or 25.0
        if needs.stamina < from then
            -- Scales in from 1.0 at `windedFrom` to the full penalty at zero instead of snapping on at a threshold.
            local t = 1.0 - math.max(0.0, math.min(1.0, needs.stamina / math.max(0.001, from)))
            m = m * (1.0 + ((cfg.windedMultiplier or 1.0) - 1.0) * t)
        end
    end

    -- Focus booster (bs_boosters)
    local st = tonumber(LocalPlayer.state.bsSteady)
    if st then m = m * math.max(0.3, math.min(1.0, st)) end

    return m
end

--------------------------------------------------------------------------------
-- The curve
--------------------------------------------------------------------------------

-- Offset in roughly -1..+1 per axis. Driven by GetGameTimer (wall clock), so it looks the same at any frame rate. The 0.6/0.4 layer weighting keeps the peak under 1.0; `seed` is per session so players do not sway in lockstep.
local function swayOffset()
    local t     = GetGameTimer() / 1000.0 + seed
    local slow  = (cfg.slowHz or 0.31) * 2.0 * math.pi
    local fast  = (cfg.fastHz or 0.79) * 2.0 * math.pi

    local x = 0.6 * math.sin(t * slow) + 0.4 * math.sin(t * fast * 1.13 + 1.7)
    local y = 0.6 * math.sin(t * slow * 0.87 + 0.6) + 0.4 * math.sin(t * fast + 2.9)

    return x, y * (cfg.verticalRatio or 1.0)
end

--------------------------------------------------------------------------------
-- Is this a firearm, and is it being aimed
--------------------------------------------------------------------------------

-- Asked of the engine: GetWeaponDamageType is 3 for bullet weapons (melee 2, unarmed 0). Fallback is GetMaxAmmoInClip, as in bs_weapons/cl_reload.lua. Throwables are excluded.
-- Returns true/false plus the reason, so /skilltest can show why a weapon did or did not qualify.
local function isFirearm(ped, hash)
    if not hash or hash == 0 or hash == -1 or hash == UNARMED then return false end
    if not IsWeaponValid(hash) then return false end

    local ok, dmgType = pcall(GetWeaponDamageType, hash)
    if ok and type(dmgType) == 'number' and dmgType ~= 0 then
        return dmgType == 3
    end

    return (GetMaxAmmoInClip(ped, hash, 0) or 0) > 1
end

--------------------------------------------------------------------------------
-- Am I aiming a gun, and if not, which half of that failed
--------------------------------------------------------------------------------

-- Shared with /skilltest so the diagnostic runs the same check as the loop.
-- Three aim reads are ORed on purpose: IsPlayerFreeAiming, IsControlPressed(0, 25) for the first frame of aiming, and IsDisabledControlPressed(0, 25) for when another resource disabled the aim control.
local function evaluate(ped)
    local aiming = IsPlayerFreeAiming(PlayerId())
        or IsControlPressed(0, 25) or IsDisabledControlPressed(0, 25)

    if not aiming                        then return false, 'not aiming' end
    if IsNuiFocused()                    then return false, 'nui focus' end
    if IsPedDeadOrDying(ped, true)       then return false, 'dead' end
    if IsPedRagdoll(ped)                 then return false, 'ragdoll' end
    if IsPedInAnyVehicle(ped, true)      then return false, 'in a vehicle' end

    local _, hash = GetCurrentPedWeapon(ped, true)
    if not isFirearm(ped, hash) then
        return false, 'not a firearm (hash ' .. tostring(hash) .. ')'
    end

    return true, 'aiming a firearm'
end

--------------------------------------------------------------------------------
-- The crosshair, when the config asks for one
--------------------------------------------------------------------------------

-- Drawn natively with DrawRect instead of NUI: a per-frame SendNUIMessage is costly and lags behind the movement.
-- The centre dot stays fixed on purpose (where you pointed); the ticks move (where your hands are).
local function drawCrosshair(ox, oy)
    local c    = cfg.crosshair or {}
    local col  = c.colour or { 235, 235, 235, 170 }
    local gap  = c.gapBase or 0.006
    local len  = c.length or 0.010
    local th   = c.thickness or 0.0016

    -- Natives use square screen space, so the horizontal size is divided by the aspect ratio to keep the crosshair from stretching on wide monitors.
    local aspect = GetAspectRatio(false)
    if not aspect or aspect <= 0.0 then aspect = 16.0 / 9.0 end

    local cx = 0.5 + (ox / aspect)
    local cy = 0.5 + oy

    -- left, right, top, bottom
    DrawRect(cx - gap - len / 2.0, cy, len / aspect, th * aspect, col[1], col[2], col[3], col[4])
    DrawRect(cx + gap + len / 2.0, cy, len / aspect, th * aspect, col[1], col[2], col[3], col[4])
    DrawRect(cx, cy - gap - len / 2.0, th / aspect, len * aspect, col[1], col[2], col[3], col[4])
    DrawRect(cx, cy + gap + len / 2.0, th / aspect, len * aspect, col[1], col[2], col[3], col[4])

    if c.dot ~= false then
        DrawRect(0.5, 0.5, th / aspect, th * aspect, col[1], col[2], col[3], 220)
    end
end

--------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------

CreateThread(function()
    cfg = Skills.Sway or {}

    -- Boot line, always printed, so you can tell the file is running without editing the config. Also prints the amplitude at level 0.
    if not Skills or not Skills.Sway then
        bootState = 'CONFIG MISSING'
        print('^1[BeyondSurvival]^7 (skills) cl_sway.lua LOADED but Skills.Sway is nil - config/config_abilities.lua did not load, or it loaded BEFORE config_skills.lua and its table was overwritten. Check shared_scripts order in fxmanifest.lua. Sway is OFF.')
        return
    end

    print(('^2[BeyondSurvival]^7 (skills) cl_sway.lua loaded - enabled=%s mode=%s maxDegrees=%s zeroAt=%s tree=%s. Type /skilltest in game for the full picture.')
        :format(tostring(cfg.enabled), tostring(cfg.mode), tostring(cfg.maxDegrees),
                tostring(cfg.zeroAtLevel), tostring(cfg.tree)))

    if not cfg.enabled then
        bootState = 'disabled in config'
        print('^3[BeyondSurvival]^7 (skills) sway is disabled by config (Skills.Sway.enabled = false).')
        return
    end

    seed       = math.random() * 1000.0
    bootState  = 'running'
    loopAlive  = true

    while true do
        local ped = PlayerPedId()

        -- Gate, cheapest check first. Only aiming counts, not just holding a rifle.
        local active, reason = evaluate(ped)
        lastActive, lastReason = active, reason

        if not active then
            -- Offset memory is reset when the state ends, so the next aim does not apply a delta against a stale curve position (one big camera jerk).
            prevX, prevY = 0.0, 0.0
            lastFactor   = 0.0
            Wait(250)
            goto continue
        end

        do
            local factor = skillFactor()

            if factor <= 0.0 then
                -- Capped shooter. Nothing is touched at all - see skillFactor.
                prevX, prevY = 0.0, 0.0
                lastFactor   = 0.0
                Wait(0)
                goto continue
            end

            factor     = factor * situationalMultiplier(ped)
            lastFactor = factor

            -- Per-shot recoil and shake live in cl_recoil.lua (Skills.Recoil).

            local ox, oy = swayOffset()
            local mode   = cfg.mode or 'both'

            -- Crosshair first, outside the `stepMs` throttle: DrawRect only lasts one frame, so skipped frames make the reticle flicker.
            if mode == 'crosshair' or mode == 'both' then
                local amp = ((cfg.crosshair or {}).maxOffset or 0.011) * factor
                drawCrosshair(ox * amp, oy * amp)
            end

            if mode == 'aim' or mode == 'both' then
                local step = cfg.stepMs or 0
                local now  = GetGameTimer()
                if step <= 0 or (now - lastStepAt) >= step then
                    lastStepAt = now

                    local degrees = (cfg.maxDegrees or 1.8) * factor
                    local x, y    = ox * degrees, oy * degrees

                    -- Apply the change (delta) so the player's own aim is kept and the offset sums back to zero over a cycle.
                    -- Pitch is the axis that survives third person free-aim; heading is applied anyway.
                    -- Both are pcall'd: a camera native can throw when a cutscene takes over, which would kill this thread.
                    pcall(function()
                        SetGameplayCamRelativeHeading(GetGameplayCamRelativeHeading() - (x - prevX))
                        SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() + (y - prevY), 1.0)
                    end)

                    prevX, prevY = x, y
                end
            end

            if cfg.debug then
                local now = GetGameTimer()
                if now - lastDebugAt > 1000 then
                    lastDebugAt = now
                    print(('^2[BeyondSurvival]^7 (skills) sway factor %.3f at %s level %d')
                        :format(factor, cfg.tree or 'combat', combatLevel()))
                end
            end

            Wait(0)
        end

        ::continue::
    end
end)

--------------------------------------------------------------------------------
-- The debug surface, for /skilltest
--------------------------------------------------------------------------------

BS_SkillsDebug.sway = function()
    local ped = PlayerPedId()
    local active, reason = false, 'evaluate errored'
    pcall(function() active, reason = evaluate(ped) end)

    local base = 0.0
    pcall(function() base = skillFactor() end)

    local situational = 1.0
    pcall(function() situational = situationalMultiplier(ped) end)

    local _, hash = GetCurrentPedWeapon(ped, true)

    return {
        loaded      = true,
        configFound = (Skills and Skills.Sway) and true or false,
        enabled     = cfg and cfg.enabled or false,
        bootState   = bootState,
        loopAlive   = loopAlive,
        mode        = cfg and cfg.mode or '?',
        tree        = cfg and cfg.tree or 'combat',
        level       = combatLevel(),
        zeroAt      = cfg and cfg.zeroAtLevel or 20,
        steadyHands = hasSteadyHands(),
        active      = active,
        reason      = reason,
        weaponHash  = hash,
        isFirearm   = isFirearm(ped, hash),
        freeAiming  = IsPlayerFreeAiming(PlayerId()),
        firstPerson = (GetFollowPedCamViewMode() == 4),
        baseFactor  = base,
        situational = situational,
        factor      = base * situational,
        degrees     = (cfg and cfg.maxDegrees or 1.8) * base * situational,
        screenFrac  = ((cfg and cfg.crosshair or {}).maxOffset or 0.011) * base * situational,
        lastFactor  = lastFactor,
        -- What the loop last decided, vs what `evaluate` says now. They only differ when the loop is not running, which is what /skilltest is meant to catch.
        loopActive  = lastActive,
        loopReason  = lastReason,
    }
end

-- Never stuck: this file holds no engine state, so a stop has nothing to unwind. Only the offset memory is cleared, so a stale `prev` cannot cause a one-frame jerk after a respawn.

local function release() prevX, prevY = 0.0, 0.0 end

AddEventHandler('bs:hook:player:spawned', release)
AddEventHandler('bs:ui:panic', release)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    release()
end)
