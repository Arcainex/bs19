-- Unstick watchdog. If the player is asking to move, is allowed to move, and is not moving for long enough, it clears the ped's tasks and logs it to the console.
-- It ignores every legitimate reason to be still (downed, prone, grabbed, in a menu, ragdolled, in a vehicle, dead, frozen by spawn code).

local STUCK_AFTER = 1500     -- ms of "asking and not moving" before we act
local COOLDOWN    = 4000     -- do not fight the same state twice a second

local askingSince, lastFix = nil, 0

-- Legitimate reasons to stand still.
local function allowedToBeStill(ped)
    if IsEntityDead(ped) then return true end
    if IsPedRagdoll(ped) then return true end
    if IsPedFalling(ped) then return true end
    if IsPedGettingUp(ped) then return true end
    if IsPedInAnyVehicle(ped, true) then return true end
    if IsEntityPositionFrozen(ped) then return true end
    if IsPedJumping(ped) or IsPedClimbing(ped) or IsPedVaulting(ped) then return true end

    -- Our own systems that stop you on purpose.
    if GetResourceState('bs_medical') == 'started' then
        local ok, downed = pcall(function() return exports.bs_medical:IsDowned() end)
        if ok and downed then return true end
    end
    if GetResourceState('bs_emotes') == 'started' then
        local ok, prone = pcall(function() return exports.bs_emotes:IsProne() end)
        if ok and prone then return true end
    end
    if GetResourceState('bs_zombies') == 'started' then
        local ok, grabbed = pcall(function() return exports.bs_zombies:IsGrabbed() end)
        if ok and grabbed then return true end
    end

    -- Menus with NUI focus take the input instead of the game.
    if IsNuiFocused() then return true end

    return false
end

CreateThread(function()
    while true do
        Wait(150)

        if not exports.bs_core:IsLoaded() then askingSince = nil goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then askingSince = nil goto continue end

        -- Is the player trying to move? Checks normal and disabled input, since movement left disabled is one of the causes.
        local asking =
            IsControlPressed(0, 32) or IsControlPressed(0, 33) or
            IsControlPressed(0, 34) or IsControlPressed(0, 35) or
            IsDisabledControlPressed(0, 32) or IsDisabledControlPressed(0, 33) or
            IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 35)

        if not asking or allowedToBeStill(ped) then
            askingSince = nil
            goto continue
        end

        if GetEntitySpeed(ped) > 0.12 then
            askingSince = nil
            goto continue
        end

        askingSince = askingSince or GetGameTimer()

        local now = GetGameTimer()
        if (now - askingSince) >= STUCK_AFTER and (now - lastFix) >= COOLDOWN then
            lastFix = now
            askingSince = nil

            -- Log what it was stuck in, so the cause can be fixed.
            print(('^3[BeyondSurvival]^7 (unstick) movement blocked - clearing tasks (weapon=%s, anim=%s, config36=%s)')
                :format(tostring(GetSelectedPedWeapon(ped)),
                        tostring(IsEntityPlayingAnim(ped, 'anim@mp_point', 'idle', 3)),
                        tostring(GetPedConfigFlag(ped, 36, true))))

            ClearPedTasks(ped)
            ClearPedSecondaryTask(ped)

            -- Clear the known stuck states:
            SetPedConfigFlag(ped, 36, false)     -- weapon switching blocked (pointing)
            ResetPedMovementClipset(ped, 0.2)    -- a clipset that outlived its owner
            SetPedMoveRateOverride(ped, 1.0)     -- a move rate nobody restored
            SetPlayerControl(PlayerId(), true, 0)
            FreezeEntityPosition(ped, false)
            SetPedCanPlayAmbientAnims(ped, true)
        end

        ::continue::
    end
end)

-- Dry firing: the click is played here and the weapon task cleared, so an empty trigger pull cannot leave the ped stuck.

local lastClick = 0
local UNARMED = GetHashKey('WEAPON_UNARMED')   -- PERF: hashed once, not every frame

CreateThread(function()
    while true do
        Wait(0)

        -- PERF: same-resource call instead of an export round-trip each frame.
        if BS.IsLoaded() then
            local ped = PlayerPedId()
            local _, weapon = GetCurrentPedWeapon(ped, true)

            if weapon and weapon ~= UNARMED
               and IsPedArmed(ped, 4) then

                local ammo = GetAmmoInPedWeapon(ped, weapon)

                if ammo <= 0 and (IsControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 24)) then
                    local now = GetGameTimer()
                    if now - lastClick > 350 then
                        lastClick = now

                        PlaySoundFrontend(-1, 'Faux_Click', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
                        TriggerEvent('bs:ui:notify', {
                            type = 'warn', message = L('common.empty'), duration = 1400,
                        })

                        -- Stop the engine starting a dry-fire reaction it may not finish.
                        ClearPedSecondaryTask(ped)
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

exports('Unstick', function()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    SetPedConfigFlag(ped, 36, false)
    ResetPedMovementClipset(ped, 0.2)
    SetPedMoveRateOverride(ped, 1.0)
    SetPlayerControl(PlayerId(), true, 0)
    FreezeEntityPosition(ped, false)
    SetPedCanPlayAmbientAnims(ped, true)
    return true
end)

-- Command so a stuck player does not have to wait for the watchdog.
RegisterCommand('unstick', function()
    exports.bs_core:Unstick()
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('core.unstuck'), duration = 2000 })
end, false)
