-- Alpha-Z Weather V24: seamless 9-minute acid build (5min cloud-only), dangerous hurricane-like finale.
-- bs_world holds ownership lock from warning through the complete fade-out.
-- A single seamless whole-frame tint is used; no layered bands or scanlines.
local active = 'none'
local creatorQuiet = false

-- Local-only exception: a player choosing a character sees a stable FOGGY sky.
-- The real Alpha-Z event keeps progressing normally on the server.
local function creatorWeatherActive()
    return creatorQuiet or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.azCharacterEditor == true)
end
local lastDamage = 0
local weatherParticles = {}
local particleAsset = 'core'
local transitionStart = 0
local DEFAULT_BUILDUP_MS = 180000
local ACID_BUILDUP_MS = 540000   -- 9 minutes
local ACID_RAIN_START_MS = 300000 -- 5 minutes: cloud-only before this point
local transitionDuration = DEFAULT_BUILDUP_MS
local transitioning = false
local activeRevision = nil
local weatherStage = 0
local lastWeatherHold = 0
local ending = false
local endingStart = 0
local endingDuration = 60000
local endingFromIntensity = 1.0
local endingBaseWeather = nil
local sirenToken = nil
local sirenDeadline = 0
local countdownAlert = nil
local acidParticlesStarted = false
local acidRainEnabled = false
local regenBlocked = false
-- Acid rain is different from the short legacy Alpha-Z stages. We never
-- release bs_world's original weather override at siren end. Instead the
-- cloud hat builds for minutes and the weather type is changed later, in
-- short engine-supported transitions.
local acidWeatherStage = 0
local acidOverrideReleased = false
local acidCloudStage = 0
local acidBaseWeather = 'OVERCAST'
local acidEndWeatherStarted = false
local acidEndNeedsWeatherRestore = false

local function clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function ease(value)
    local x = clamp01(value)
    return x * x * (3.0 - 2.0 * x)
end

-- GTA auto-healing normally stops at about 50%; set recharge to zero during
-- full-strength outdoor acid rain, so the player can die from continued exposure.
-- Re-enable the native default after shelter, the outro, death or resource stop.
local function blockNaturalRegen(shouldBlock)
    if shouldBlock then
        SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
        regenBlocked = true
    elseif regenBlocked then
        SetPlayerHealthRechargeMultiplier(PlayerId(), 1.0)
        regenBlocked = false
    end
end

-- Stage boundaries are *absolute* elapsed time after the siren ends.
-- Acid rain: cloud cover 0-180s, overcast 180-300s, RAIN from minute 5,
-- THUNDER through minute 9. No precipitation/acid particles before minute 5.
-- Other Alpha-Z events preserve their existing 180-second transitions.
local stages = {
    acidrain = {'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER'},
    toxicfog = {'RAIN', 'THUNDER'},
    ashstorm = {'CLOUDS', 'OVERCAST', 'SMOG', 'SMOG'},
}
local stageEnds = {
    acidrain = {180000, 300000, 345000, 540000},
    toxicfog = {35000, 180000},
    ashstorm = {45000, 90000, 135000, 180000},
}

local function stageAt(kind, elapsed)
    local ends = stageEnds[kind]
    if not ends then return 1, transitionDuration end
    for i, finishMs in ipairs(ends) do
        if elapsed < finishMs then
            return i, math.max(500, finishMs - elapsed)
        end
    end
    return #ends, 500
end

-- Deliberately no weather-type switch at 0 seconds after the siren.
-- Cloud hats are interpolated separately without touching bs_world's override.
-- The only weather native transitions for acid rain are SHORT (15 seconds),
-- well after the sky has already changed visually. Engine-native multi-minute
-- SetWeatherTypeOvertimePersist calls can jump instantly on some FiveM builds.
local ACID_STAGE_WEATHERS = { 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER' }
local ACID_STAGE_START_MS = { 210000, 275000, 300000, 465000 }
local ACID_NATIVE_BLEND_MS = 15000

local function acidStageAt(elapsed)
    local stage = 0
    for i, startMs in ipairs(ACID_STAGE_START_MS) do
        if elapsed >= startMs then stage = i else break end
    end
    return stage
end

local function acidCompletedStageAt(elapsed)
    local stage = 0
    for i, startMs in ipairs(ACID_STAGE_START_MS) do
        if elapsed >= startMs + ACID_NATIVE_BLEND_MS then stage = i else break end
    end
    return stage
end

local function acidCloudHatForWeather(weather)
    if weather == 'CLEAR' or weather == 'EXTRASUNNY' or weather == 'NEUTRAL' then
        return 'Clear 01'
    elseif weather == 'RAIN' or weather == 'THUNDER' or weather == 'CLEARING' then
        return 'RAIN'
    elseif weather == 'OVERCAST' or weather == 'FOGGY' then
        return 'Nimbus'
    end
    return 'Cloudy 01'
end

local function startAcidCloudCover(elapsed)
    if elapsed < 180000 then
        SetCloudHatTransition('Cloudy 01', math.max(1.0, (180000 - elapsed) / 1000.0))
        acidCloudStage = 1
    else
        SetCloudHatTransition('Stormy 01', math.max(1.0, (300000 - elapsed) / 1000.0))
        acidCloudStage = 2
    end
end

local function advanceAcidCloudCover(elapsed)
    if acidCloudStage == 1 and elapsed >= 180000 then
        acidCloudStage = 2
        SetCloudHatTransition('Stormy 01', math.max(1.0, (300000 - elapsed) / 1000.0))
    end
end

local function advanceAcidWeather(elapsed)
    local due = acidStageAt(elapsed)
    if due <= acidWeatherStage then return end
    -- Normal starting weather persists for the entire first part of buildup.
    -- ClearOverrideWeather is delayed until after 3m30s of gradual cloud hats.
    if not acidOverrideReleased then
        ClearOverrideWeather()
        acidOverrideReleased = true
    end
    -- Reconstruct at most one weather change per stage. Never use NowPersist
    -- for an on-time participant, and never start a 3-minute native transition.
    acidWeatherStage = acidWeatherStage + 1
    local startMs = ACID_STAGE_START_MS[acidWeatherStage]
    local remaining = math.max(1.0, (ACID_NATIVE_BLEND_MS - (elapsed - startMs)) / 1000.0)
    SetWeatherTypeOvertimePersist(ACID_STAGE_WEATHERS[acidWeatherStage], remaining)
end

local function finalWeather(kind)
    local sequence = stages[kind]
    return sequence and sequence[#sequence] or nil
end

local function applyStage(stage, seconds)
    local sequence = stages[active]
    if not sequence or weatherStage == stage then return end
    -- DO NOT use NowPersist here; it would snap the live weather instantly.
    SetWeatherTypeOvertimePersist(sequence[stage], math.max(0.5, seconds or 1.0))
    weatherStage = stage
end

local function finishTransition()
    if not transitioning then return end
    transitioning = false
    weatherStage = 5
    local target = finalWeather(active)
    if target then
        -- NowPersist is only used AFTER the entire 180-second blend is complete.
        SetWeatherTypeNowPersist(target)
        SetOverrideWeather(target)
        lastWeatherHold = GetGameTimer()
    end
end

local function stopParticles()
    for _, fx in ipairs(weatherParticles) do
        if fx and DoesParticleFxLoopedExist(fx) then
            StopParticleFxLooped(fx, false)
        end
    end
    weatherParticles = {}
    RemoveNamedPtfxAsset(particleAsset)
end

local function resetFx(previousKind)
    stopParticles()
    acidParticlesStarted = false
    acidRainEnabled = false
    blockNaturalRegen(false)
    ClearExtraTimecycleModifier()
    if previousKind == 'toxicfog' or previousKind == 'ashstorm' then
        ClearTimecycleModifier()
    end
    SetRainLevel(-1.0)
    SetWindSpeed(0.0)
    if acidCloudStage > 0 then
        ClearCloudHat()
        acidCloudStage = 0
    end
end

local function protected(ped)
    return GetInteriorFromEntity(ped) ~= 0 or IsPedInAnyVehicle(ped, false)
end

local function hurt(ped, amount)
    local now = GetGameTimer()
    if now-lastDamage < 5000 or protected(ped) or IsEntityDead(ped) then return end
    lastDamage=now
    SetEntityHealth(ped, math.max(0, GetEntityHealth(ped)-amount))
end

local function loadPtfx()
    if HasNamedPtfxAssetLoaded(particleAsset) then return true end
    RequestNamedPtfxAsset(particleAsset)
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(particleAsset) and GetGameTimer() < timeout do Wait(0) end
    return HasNamedPtfxAssetLoaded(particleAsset)
end

-- Green acid droplets/spray around the player. The emitters are moved with the player.
local function createAcidParticles()
    stopParticles()
    if not loadPtfx() then return end
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local offsets = {
        { 0.0,  0.0, 7.0, 2.2},
        { 4.0,  2.0, 6.0, 1.7},
        {-4.0, -2.0, 6.0, 1.7},
        { 2.0, -4.0, 6.5, 1.6},
        {-2.0,  4.0, 6.5, 1.6}
    }
    for _, o in ipairs(offsets) do
        UseParticleFxAssetNextCall(particleAsset)
        local fx = StartParticleFxLoopedAtCoord('ent_amb_sprinkler_city_sml', p.x+o[1], p.y+o[2], p.z+o[3], 90.0, 0.0, 0.0, o[4], false, false, false, false)
        if fx and fx ~= 0 then
            SetParticleFxLoopedColour(fx, 0.18, 1.0, 0.12, false)
            SetParticleFxLoopedAlpha(fx, 0.0)
            weatherParticles[#weatherParticles+1] = fx
        end
    end
end

-- Dense poisonous gas banks. Combined with THUNDER this keeps lightning visible.
local function createToxicFogParticles()
    stopParticles()
    if not loadPtfx() then return end
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local offsets = {
        { 0.0,  5.0, -0.8, 4.5}, { 0.0, -5.0, -0.8, 4.5},
        { 5.0,  0.0, -0.8, 4.5}, {-5.0,  0.0, -0.8, 4.5},
        { 4.0,  4.0, -0.5, 4.0}, {-4.0, -4.0, -0.5, 4.0}
    }
    for _, o in ipairs(offsets) do
        UseParticleFxAssetNextCall(particleAsset)
        local fx = StartParticleFxLoopedAtCoord('exp_grd_bzgas_smoke', p.x+o[1], p.y+o[2], p.z+o[3], 0.0, 0.0, 0.0, o[4], false, false, false, false)
        if fx and fx ~= 0 then
            SetParticleFxLoopedColour(fx, 0.24, 0.55, 0.18, false)
            SetParticleFxLoopedAlpha(fx, 0.0)
            weatherParticles[#weatherParticles+1] = fx
        end
    end
end

local function moveParticlesWithPlayer(kind, progress)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    if kind == 'acidrain' then
        local offsets = {{0,0,7},{4,2,6},{-4,-2,6},{2,-4,6.5},{-2,4,6.5}}
        for i,fx in ipairs(weatherParticles) do
            local o=offsets[i]
            if o and DoesParticleFxLoopedExist(fx) then
                SetParticleFxLoopedOffsets(fx, p.x+o[1],p.y+o[2],p.z+o[3],90.0,0.0,0.0)
                SetParticleFxLoopedAlpha(fx, 0.62 * progress)
            end
        end
    elseif kind == 'toxicfog' then
        local offsets = {{0,5,-0.8},{0,-5,-0.8},{5,0,-0.8},{-5,0,-0.8},{4,4,-0.5},{-4,-4,-0.5}}
        for i,fx in ipairs(weatherParticles) do
            local o=offsets[i]
            if o and DoesParticleFxLoopedExist(fx) then
                SetParticleFxLoopedOffsets(fx, p.x+o[1],p.y+o[2],p.z+o[3],0.0,0.0,0.0)
                SetParticleFxLoopedAlpha(fx, 0.72 * progress)
            end
        end
    end
end

-- Alpha-Z acid tint: engine colour correction only. Never draw screen rectangles.
-- V16 accidentally applied postfx_desaturation=0 and postfx_shift_col_*=0,
-- both of which can wipe out colour and crush the image into near black/white.
-- The new modifier overrides ONLY the RGB grading channels, whose baseline
-- is 1.0. Do not override exposure, saturation, tone mapping or screen shift.
local GREEN_TC = 'alpha_z_acid_green_v20'
local greenCreated = false
local greenEnabled = false
local lastGreenCheck = 0
local greenLastProgress = -1

local function ensureGreenModifier()
    if greenCreated then return true end
    local idx = CreateTimecycleModifier(GREEN_TC)
    if idx == nil or idx == -1 then
        print('^1[Alpha-Z Wetter]^7 Green timecycle modifier unavailable.')
        return false
    end
    greenCreated = true
    -- RGB=1 is the neutral starting point, matching the game-world colour grade.
    SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_r', 1.0, 0.0)
    SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_g', 1.0, 0.0)
    SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_b', 1.0, 0.0)
    return true
end

local function setGreen(intensity)
    local progress = clamp01(intensity)
    if not greenEnabled and progress <= 0.0001 then return end
    if not ensureGreenModifier() then return end
    if not greenEnabled then
        SetExtraTimecycleModifier(GREEN_TC)
        greenEnabled = true
        lastGreenCheck = GetGameTimer()
    elseif GetGameTimer() - lastGreenCheck >= 5000 then
        SetExtraTimecycleModifier(GREEN_TC)
        lastGreenCheck = GetGameTimer()
    end

    if math.abs(progress - greenLastProgress) >= 0.0003 then
        -- Balanced olive/toxic green: preserve ambient brightness and detail.
        -- Smoothly reach the full colour grade over this event's buildup.
        local x = ease(progress)
        SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_r', 1.0 - 0.42 * x, 0.0)
        SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_g', 1.0 + 0.10 * x, 0.0)
        SetTimecycleModifierVar(GREEN_TC, 'postfx_correct_col_b', 1.0 - 0.46 * x, 0.0)
        greenLastProgress = progress
    end
    if progress <= 0.0001 then
        ClearExtraTimecycleModifier()
        greenEnabled = false
        greenLastProgress = -1
    end
end

-- Reverse the real weather AND all local FX for a full 60 seconds.
-- For a buildup cancellation use the CURRENT stage, never force final THUNDER.
local function startEnding(elapsedMs, baseWeather, fadeFrom)
    if active == 'none' or ending then return end
    local now = GetGameTimer()
    local elapsed = math.max(0, tonumber(elapsedMs) or 0)
    ending = true
    transitioning = false
    endingStart = now - elapsed
    endingFromIntensity = clamp01(tonumber(fadeFrom) or
        ((now - transitionStart) / transitionDuration))
    -- Natural regeneration is restored the moment the outro begins.
    blockNaturalRegen(false)
    endingBaseWeather = (type(baseWeather) == 'string' and baseWeather ~= '')
        and baseWeather or 'OVERCAST'
    -- The server keeps bs_world locked throughout the entire 60-second outro.
    local remaining = endingDuration - elapsed
    if active == 'acidrain' then
        acidEndWeatherStarted = false
        acidEndNeedsWeatherRestore = acidOverrideReleased
        -- No weather-native call at all if only the cloud-only phase was reached:
        -- the original weather is still in charge under bs_world's override.
        -- Cloud hat fades back over the same 60 seconds as the colour and wind.
        if acidCloudStage > 0 then
            SetCloudHatTransition(acidCloudHatForWeather(endingBaseWeather),
                math.max(1.0, remaining / 1000.0))
        end
        if remaining <= 0 and acidEndNeedsWeatherRestore then
            ClearOverrideWeather()
            SetWeatherTypeNowPersist(endingBaseWeather)
            acidEndWeatherStarted = true
        end
    else
        ClearOverrideWeather()
        SetRainLevel(-1.0)
        if remaining > 0 then
            -- Legacy events keep their previous 60s return behaviour.
            if elapsed > 2000 and endingFromIntensity >= 0.98 then
                SetWeatherTypeNowPersist(finalWeather(active))
            end
            SetWeatherTypeOvertimePersist(endingBaseWeather, math.max(0.5, remaining / 1000.0))
        else
            SetWeatherTypeNowPersist(endingBaseWeather)
        end
    end
end

-- Revision IDs make duplicate syncs idempotent. Server clocks drive phase offsets.
RegisterNetEvent('bs:alphaweather:set', function(kind, revision, elapsedMs, baseWeather,
                                                isEnding, endingElapsedMs, fadeFrom)
    kind = tostring(kind or 'none')
    if not stages[kind] then kind = 'none' end
    revision = tonumber(revision) or 0

    -- Never apply storm/weather natives while the creator owns the view.
    -- After exiting, ask the server for a fresh, elapsed-time-correct state.
    if creatorWeatherActive() then
        active = kind
        activeRevision = nil
        blockNaturalRegen(false)
        return
    end

    if active == kind and activeRevision == revision then
        if isEnding and not ending then
            startEnding(endingElapsedMs, baseWeather, fadeFrom)
        end
        return
    end

    if active == 'none' and kind == 'none' then
        activeRevision = revision
        return
    end

    local hadEvent = active ~= 'none'
    local oldKind = active
    local wasEnding = ending
    local previousBase = endingBaseWeather
    active = kind
    activeRevision = revision
    transitionDuration = kind == 'acidrain' and ACID_BUILDUP_MS or DEFAULT_BUILDUP_MS
    transitioning = false
    ending = false
    weatherStage = 0
    transitionStart = 0
    endingStart = 0
    endingBaseWeather = nil
    resetFx(oldKind)
    greenEnabled = false
    greenLastProgress = -1
    acidWeatherStage = 0
    acidOverrideReleased = false
    acidCloudStage = 0
    acidEndWeatherStarted = false
    acidEndNeedsWeatherRestore = false

    if kind == 'none' then
        if hadEvent then
            if wasEnding and previousBase then
                -- The 60s fade has finished; the base weather is already restored
                -- by the outro. A last NowPersist here could cause a visible snap.
                if oldKind ~= 'acidrain' then SetWeatherTypeNowPersist(previousBase) end
                ClearOverrideWeather()
            else
                ClearOverrideWeather()
                ClearWeatherTypePersist()
            end
        end
        return
    end

    local elapsed = math.max(0, tonumber(elapsedMs) or 0)
    transitionStart = GetGameTimer() - elapsed
    transitioning = elapsed < transitionDuration

    -- Reset any leftover artificial rain to GTA native weather-controlled rain.
    SetRainLevel(-1.0)

    if kind == 'acidrain' then
        acidBaseWeather = (type(baseWeather) == 'string' and baseWeather ~= '')
            and baseWeather or 'OVERCAST'
        if transitioning then
            -- At siren end KEEP the already-visible bs_world weather override.
            -- Seed the hidden persisted weather (still behind that override),
            -- so the later first transition does not expose a random engine sky.
            if elapsed < 3000 then
                SetWeatherTypeNowPersist(acidBaseWeather)
            elseif elapsed >= ACID_STAGE_START_MS[1] then
                -- Late join only: reconstruct the last completely settled stage.
                -- On-time players never call NowPersist during the buildup.
                local completed = acidCompletedStageAt(elapsed)
                if completed > 0 then
                    ClearOverrideWeather()
                    SetWeatherTypeNowPersist(ACID_STAGE_WEATHERS[completed])
                    acidOverrideReleased = true
                    acidWeatherStage = completed
                end
            end
            startAcidCloudCover(elapsed)
            -- The first weather change is NOT due until 3m30 after siren ends.
        else
            SetWeatherTypeNowPersist('THUNDER')
            SetOverrideWeather('THUNDER')
            acidWeatherStage = #ACID_STAGE_WEATHERS
            acidOverrideReleased = true
            weatherStage = 5
            lastWeatherHold = GetGameTimer()
            startAcidCloudCover(elapsed)
        end
    elseif transitioning then
        local stage, remainingMs = stageAt(kind, elapsed)
        local remaining = remainingMs / 1000.0
        if not hadEvent and stage == 1 and elapsed < 3000
            and type(baseWeather) == 'string' and baseWeather ~= '' then
            SetWeatherTypeNowPersist(baseWeather)
        elseif stage > 1 then
            SetWeatherTypeNowPersist(stages[kind][stage - 1])
        end
        ClearOverrideWeather()
        applyStage(stage, remaining)
    else
        local target = finalWeather(kind)
        SetWeatherTypeNowPersist(target)
        SetOverrideWeather(target)
        weatherStage = 5
        lastWeatherHold = GetGameTimer()
    end

    if kind == 'acidrain' then
        -- PTFX are created lazily when the five cloud-only minutes have passed.
        -- Late joiners during an active rainy stage will spawn emitters in the loop.
    elseif kind == 'toxicfog' then
        createToxicFogParticles()
        SetTimecycleModifier('NG_filmic20')
        SetTimecycleModifierStrength(0.0)
    else
        SetTimecycleModifier('NG_filmic20')
        SetTimecycleModifierStrength(0.0)
    end

    if isEnding then
        startEnding(endingElapsedMs, baseWeather, fadeFrom)
    end
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('bs:alphaweather:request')
    while true do
        if active ~= 'none' and not creatorWeatherActive() then
            local now = GetGameTimer()
            local elapsed = math.max(0, now - transitionStart)
            local progress = clamp01(elapsed / transitionDuration)
            if ending then
                progress = endingFromIntensity * (1.0 - ease(
                    (now - endingStart) / endingDuration))
            elseif transitioning then
                if elapsed >= transitionDuration then
                    finishTransition()
                    progress = 1.0
                else
                    if active == 'acidrain' then
                        advanceAcidCloudCover(elapsed)
                        advanceAcidWeather(elapsed)
                    else
                        local stage, remainingMs = stageAt(active, elapsed)
                        if weatherStage ~= stage then
                            applyStage(stage, remainingMs / 1000.0)
                        end
                    end
                end
            elseif now - lastWeatherHold >= 5000 then
                SetOverrideWeather(finalWeather(active))
                lastWeatherHold = now
            end

            if active == 'acidrain' then
                -- No artificial rain before five minutes. If the *previous*
                -- world weather was already rainy, fade that rain out gently
                -- rather than switching it off hard at siren end.
                if ending then
                    local sourceElapsed = endingFromIntensity * ACID_BUILDUP_MS
                    local rainProgressAtStop = ease((sourceElapsed - ACID_RAIN_START_MS)
                        / (ACID_BUILDUP_MS - ACID_RAIN_START_MS))
                    local sourceRain = sourceElapsed >= ACID_RAIN_START_MS
                        and (0.16 + 0.69 * rainProgressAtStop) or 0.0
                    local endingProgress = ease((now - endingStart) / endingDuration)
                    SetRainLevel(sourceRain * (1.0 - endingProgress))
                    -- Delay the return-weather native to avoid a snap when
                    -- Beenden is clicked; colour/rain/wind fade through 60s.
                    if acidEndNeedsWeatherRestore and not acidEndWeatherStarted
                        and now - endingStart >= 25000 then
                        acidEndWeatherStarted = true
                        ClearOverrideWeather()
                        SetWeatherTypeOvertimePersist(endingBaseWeather, 15.0)
                    end
                elseif elapsed < ACID_RAIN_START_MS then
                    acidRainEnabled = false
                    if acidBaseWeather == 'RAIN' or acidBaseWeather == 'THUNDER' then
                        SetRainLevel(1.0 - ease(elapsed / 30000.0))
                    else
                        SetRainLevel(0.0)
                    end
                else
                    acidRainEnabled = true
                    -- Rain strength climbs smoothly from the first visible drops
                    -- at 5:00 to the hurricane finale at 9:00. No rain-level
                    -- jump when the event becomes fully active.
                    local rainProgress = ease((elapsed - ACID_RAIN_START_MS)
                        / (ACID_BUILDUP_MS - ACID_RAIN_START_MS))
                    SetRainLevel(0.16 + 0.69 * rainProgress)
                end

                -- Visual rain/acid droplet alpha begins ONLY after minute 5.
                -- On cancellation, reverse from the actual level already reached.
                local rainAmount = ease((elapsed - ACID_RAIN_START_MS) /
                    (ACID_BUILDUP_MS - ACID_RAIN_START_MS))
                if ending then
                    local fromElapsed = endingFromIntensity * ACID_BUILDUP_MS
                    local fromRain = ease((fromElapsed - ACID_RAIN_START_MS) /
                        (ACID_BUILDUP_MS - ACID_RAIN_START_MS))
                    rainAmount = fromRain * (1.0 - ease((now - endingStart) / endingDuration))
                end
                rainAmount = clamp01(rainAmount)
                if rainAmount > 0.002 and not acidParticlesStarted then
                    createAcidParticles()
                    acidParticlesStarted = true
                end
                if acidParticlesStarted then
                    moveParticlesWithPlayer('acidrain', rainAmount)
                end

                -- Maximum engine wind is 12m/s. Build continuously with small
                -- smooth gusts to give the final storm a hurricane-like feel.
                local wind = (11.58 + 0.34 * math.sin(now / 2400.0)) * ease(progress)
                SetWindSpeed(math.max(0.0, math.min(11.95, wind)))
                setGreen(progress)
                local fullyActive = not transitioning and not ending
                local ped = PlayerPedId()
                local exposed = fullyActive and not protected(ped) and not IsEntityDead(ped)
                blockNaturalRegen(exposed)
                if exposed then hurt(ped, 6) end
            elseif active == 'toxicfog' then
                if not transitioning and not ending then SetRainLevel(0.35) end
                SetWindSpeed(7.0 * progress)
                SetTimecycleModifierStrength(1.0 * progress)
                moveParticlesWithPlayer('toxicfog', progress)
                if not transitioning and not ending then hurt(PlayerPedId(), 9) end
            elseif active == 'ashstorm' then
                SetWindSpeed(12.0 * progress)
                SetTimecycleModifierStrength(0.58 * progress)
                if not transitioning and not ending then hurt(PlayerPedId(), 2) end
            end
            Wait(100)
        else
            Wait(1500)
        end
    end
end)

-- Extra lightning flashes make the toxic storm visible through the fog.
CreateThread(function()
    while true do
        if active == 'toxicfog' and not ending and not creatorWeatherActive() then
            Wait(math.random(2500, 6500))
            if active == 'toxicfog' and not ending and not creatorWeatherActive() then ForceLightningFlash() end
        else
            Wait(1500)
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() then
        resetFx(active)
        ClearOverrideWeather()
        ClearWeatherTypePersist()
    end
end)

-- Thin green/red 3D lightning bolts (kept from V14).
-- These are world-space lines, unrelated to the old horizontal overlay.
local bolt = nil

local function buildBolt()
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local heading = math.rad(GetGameplayCamRot(2).z)
    local distance = math.random(90, 180)
    local side = math.random(-90, 90)
    local cx = p.x + (-math.sin(heading) * distance) + (math.cos(heading) * side)
    local cy = p.y + ( math.cos(heading) * distance) + (math.sin(heading) * side)
    local topZ = p.z + math.random(145, 220)
    local bottomZ = p.z + math.random(15, 45)
    local green = math.random(1,100) <= 65
    local r,g,b = green and 95 or 255, green and 255 or 82, green and 120 or 58
    local pts = {}
    local count = math.random(10,15)
    for i=0,count do
        local t=i/count
        local spread=(1.0-t)*8.0 + 1.2
        pts[#pts+1] = {
            x=cx + math.random(-100,100)/100*spread,
            y=cy + math.random(-100,100)/100*spread,
            z=topZ + (bottomZ-topZ)*t
        }
    end
    bolt={pts=pts,r=r,g=g,b=b,untilMs=GetGameTimer()+math.random(110,190),branches={}}
    for n=1,math.random(2,4) do
        local idx=math.random(3,#pts-3)
        local a=pts[idx]
        local branch={{x=a.x,y=a.y,z=a.z}}
        local bx,by,bz=a.x,a.y,a.z
        for j=1,math.random(2,4) do
            bx=bx+math.random(-55,55)/10
            by=by+math.random(-55,55)/10
            bz=bz-math.random(6,14)
            branch[#branch+1]={x=bx,y=by,z=bz}
        end
        bolt.branches[#bolt.branches+1]=branch
    end
    ForceLightningFlash()
end

-- Neon-green / hot-red world-space lightning. Actual GTA flashes stay native,
-- but the custom coloured branches emit their own light for visible glow.
local function drawBoltPath(points, r, g, b, a, glowIntensity)
    for i = 1, #points - 1 do
        local from = points[i]
        local to = points[i + 1]
        DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, r, g, b, a)
        DrawLightWithRange(
            (from.x + to.x) * 0.5, (from.y + to.y) * 0.5,
            (from.z + to.z) * 0.5, r, g, b, 18.0, glowIntensity
        )
    end
end

-- One continuous overlay, not strips; intensity tracks the per-event
-- buildup (540s acid rain) and 60-second outro. V17 timecycle adds
-- subtle green correction behind this to preserve game details.
CreateThread(function()
    while true do
        if (active == 'acidrain' or active == 'toxicfog') and not creatorWeatherActive() then
            local now = GetGameTimer()
            local intensity = clamp01((now - transitionStart) / transitionDuration)
            if ending then
                intensity = endingFromIntensity * (1.0 - ease((now - endingStart) / endingDuration))
            end
            intensity = ease(clamp01(intensity))
            if intensity > 0.0001 then
                local opacity = math.floor((active == 'acidrain' and 54 or 40) * intensity + 0.5)
                if active == 'acidrain' then
                    DrawRect(0.5, 0.5, 1.0, 1.0, 34, 118, 36, opacity)
                else
                    DrawRect(0.5, 0.5, 1.0, 1.0, 30, 96, 28, opacity)
                end
            end

            if not ending and bolt and bolt.untilMs > now then
                drawBoltPath(bolt.pts, bolt.r, bolt.g, bolt.b, 255, 7.5)
                for _, branch in ipairs(bolt.branches) do
                    drawBoltPath(branch, bolt.r, bolt.g, bolt.b, 225, 5.2)
                end
            end
            Wait(0)
        else
            bolt = nil
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if active == 'acidrain' and not transitioning and not ending and not creatorWeatherActive() then
            Wait(math.random(1100,3000))
            if active == 'acidrain' and not transitioning and not ending and not creatorWeatherActive() then
                buildBolt()
                if math.random(1,100)<=28 then
                    Wait(math.random(130,260))
                    if not creatorWeatherActive() then buildBolt() end
                end
            end
        elseif active == 'toxicfog' and not transitioning and not ending and not creatorWeatherActive() then
            Wait(math.random(1700,4300))
            if active == 'toxicfog' and not transitioning and not ending and not creatorWeatherActive() then buildBolt() end
        else
            Wait(750)
        end
    end
end)

-- bs_world is locked through warning, buildup, event and full 60s outro.

-- Character editor must stay clear of alarm/countdown popups.
-- Suppression is local; weather state, server timers, and transitions stay intact.
local function hideWarningsForCreator()
    return creatorQuiet or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.azCharacterEditor == true)
end

AddEventHandler('bs:alphaweather:creatorQuiet', function(on)
    creatorQuiet = (on == true)
    if creatorQuiet then
        -- Remove existing storm effects ONLY for this client's preview scene.
        -- Server-side timers, weather locks and other players are untouched.
        resetFx(active)
        ClearTimecycleModifier()
        ClearExtraTimecycleModifier()
        blockNaturalRegen(false)
        greenEnabled = false
        greenLastProgress = -1
        SendNUIMessage({ action = 'alphaWeatherCountdownStop', token = countdownAlert and countdownAlert.token })
        SendNUIMessage({ action = 'alphaWeatherSirenStop', token = sirenToken })
    else
        -- Rebuild the actual running event at the current server phase, never
        -- resume an old local transition from before opening multichar.
        activeRevision = nil
        TriggerServerEvent('bs:alphaweather:request')
        local now = GetGameTimer()
        if sirenToken and now < sirenDeadline then
            SendNUIMessage({ action='alphaWeatherSirenStart', token=sirenToken,
                duration=math.max(0,sirenDeadline-now), volume=0.20 })
        end
        local alert = countdownAlert
        if alert and now < alert.showUntil and now < alert.deadline then
            SendNUIMessage({ action='alphaWeatherCountdown', token=alert.token,
                step=alert.step, remainingMs=math.max(0,alert.deadline-now),
                duration=math.max(0,alert.showUntil-now) })
        end
    end
end)

-- NUI-ready handshake: first siren works even when the browser loads late.
RegisterNUICallback('alphaWeatherReady', function(_, cb)
    cb({ ok = true })
    if not hideWarningsForCreator() and sirenToken and GetGameTimer() < sirenDeadline then
        SendNUIMessage({
            action = 'alphaWeatherSirenStart',
            token = sirenToken,
            duration = math.max(0, sirenDeadline - GetGameTimer()),
            volume = 0.20
        })
    end
    local alert = countdownAlert
    if alert and not hideWarningsForCreator() then
        local now = GetGameTimer()
        if now < alert.showUntil and now < alert.deadline then
            SendNUIMessage({
                action = 'alphaWeatherCountdown', token = alert.token,
                step = alert.step,
                remainingMs = math.max(0, alert.deadline - now),
                duration = math.max(0, alert.showUntil - now)
            })
        end
    end
end)

-- Tokenized NUI siren: a stale stop or duplicated sync cannot cut off a new siren.
RegisterNetEvent('bs:alphaweather:warning', function(kind, durationMs, ticket)
    local token = tonumber(ticket) or 0
    local remaining = math.max(0, tonumber(durationMs) or 56000)
    if token == sirenToken and GetGameTimer() < sirenDeadline then return end
    sirenToken = token
    sirenDeadline = GetGameTimer() + remaining
    if hideWarningsForCreator() then return end
    SendNUIMessage({
        action = 'alphaWeatherSirenStart',
        weather = tostring(kind or ''),
        duration = remaining,
        token = token,
        volume = 0.20
    })
end)

RegisterNetEvent('bs:alphaweather:warningStop', function(ticket)
    local token = tonumber(ticket) or 0
    if token ~= sirenToken then return end
    sirenToken = nil
    sirenDeadline = 0
    SendNUIMessage({ action = 'alphaWeatherSirenStop', token = token })
end)

-- V23: repeated shelter warnings are separate from siren playback.
RegisterNetEvent('bs:alphaweather:countdown', function(ticket, step, remainingMs, displayMs)
    local token = tonumber(ticket)
    local countStep = tonumber(step)
    if not token or not countStep then return end
    local now = GetGameTimer()
    local duration = math.max(0, math.min(10000, tonumber(displayMs) or 10000))
    local remaining = math.max(0, tonumber(remainingMs) or 0)
    if duration <= 0 or remaining <= 0 then return end

    -- Do not extend a window when a reconnect duplicates the same reminder.
    if countdownAlert and countdownAlert.token == token and countdownAlert.step == countStep
        and now < countdownAlert.showUntil then return end

    countdownAlert = {
        token = token, step = countStep,
        deadline = now + remaining,
        showUntil = now + duration
    }
    if hideWarningsForCreator() then return end
    SendNUIMessage({
        action = 'alphaWeatherCountdown', token = token, step = countStep,
        remainingMs = remaining, duration = duration
    })
end)

RegisterNetEvent('bs:alphaweather:countdownCancel', function(ticket)
    local token = tonumber(ticket)
    if not countdownAlert or countdownAlert.token ~= token then return end
    countdownAlert = nil
    SendNUIMessage({ action = 'alphaWeatherCountdownStop', token = token })
end)
