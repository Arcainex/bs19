-- BeyondSurvival - bs_emotes movement consequences. Double-tapping jump ragdolls you instead of hopping. The Survival skill perk will later turn the stumble into a roll; the hook does nothing until the perk exists.

Movement = { lastJump = 0, recovering = false }

local DOUBLE_TAP_MS = 420

-- Can this character turn a bad landing into a roll? The perk lives in bs_skills; always false until it exists.
local function hasRollPerk()
    if GetResourceState('bs_skills') ~= 'started' then return false end
    local ok, value = pcall(function() return exports.bs_skills:HasPerk('survival', 'break_fall') end)
    return ok and value == true
end

local function stumble()
    local ped = PlayerPedId()
    if Movement.recovering then return end
    Movement.recovering = true

    if hasRollPerk() then
        -- The roll clip. Earlier guesses ('dive_start_run', 'jump_land_roll') do not exist in the dict, and TaskPlayAnim silently does nothing for a missing clip.
        RequestAnimDict('move_fall')
        local waited = 0
        while not HasAnimDictLoaded('move_fall') and waited < 1500 do Wait(10); waited = waited + 10 end
        if HasAnimDictLoaded('move_fall') then
            TaskPlayAnim(ped, 'move_fall', 'land_roll', 8.0, -8.0, 700, 0, 0, false, false, false)
        end

        -- A controlled roll costs an instant hit rather than a drain.
        if GetResourceState('bs_core') == 'started' then
            pcall(function() exports.bs_core:AdjustStamina(-15) end)
        end

        Wait(700)
    else
        -- No perk: you go down.
        SetPedToRagdoll(ped, math.random(900, 1500), math.random(900, 1500), 0, true, true, false)
        Wait(1400)
        -- A hard landing costs a little health.
        local health = GetEntityHealth(ped)
        if health > 101 then SetEntityHealth(ped, math.max(101, health - 4)) end
    end

    Wait(400)
    Movement.recovering = false
end

-- PERF: export calls are not free and this loop runs every frame, so the loaded flag is re-read from bs_core at most every 250ms.
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

        if loadedCached() then
            local ped = PlayerPedId()

            if IsControlJustPressed(0, 22) and not IsPedInAnyVehicle(ped, false) then
                local now = GetGameTimer()

                -- Second tap, only while already airborne; two taps on flat ground are just two jumps.
                if (now - Movement.lastJump) < DOUBLE_TAP_MS
                   -- IsEntityInAir is the real native (IsPedInAir does not exist and errors the thread).
                   and (IsPedJumping(ped) or IsPedFalling(ped)
                        or not IsPedOnFoot(ped) or IsEntityInAir(ped)) then
                    CreateThread(stumble)
                end

                Movement.lastJump = now
            end
        else
            Wait(200)
        end
    end
end)

exports('IsRecovering', function() return Movement.recovering end)
