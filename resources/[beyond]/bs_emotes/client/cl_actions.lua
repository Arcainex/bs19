-- BeyondSurvival - bs_emotes actions: hands up and whistling. Both are upper-body animations (flag 49) so you can still walk and look around.

Actions = { handsUp = false, whistling = false }

local lastWhistle = 0

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 3000 do
        Wait(10); waited = waited + 10
    end
    return HasAnimDictLoaded(dict)
end

--- True when the player is in a state where an emote makes no sense.
local function busy()
    local ped = PlayerPedId()
    if not exports.bs_core:IsLoaded() then return true end
    if IsEntityDead(ped) then return true end
    if IsPedInAnyVehicle(ped, false) then return true end
    if IsPauseMenuActive() then return true end
    if GetResourceState('bs_inventory') == 'started' and exports.bs_inventory:IsOpen() then return true end
    return false
end

--------------------------------------------------------------------------------
-- Hands up
--------------------------------------------------------------------------------

function Actions.SetHandsUp(state)
    local ped = PlayerPedId()
    local cfg = Emotes.HandsUp

    if state then
        if not loadDict(cfg.dict) then return false end
        TaskPlayAnim(ped, cfg.dict, cfg.clip, cfg.blendIn, cfg.blendOut, -1, cfg.flag, 0, false, false, false)
        Actions.handsUp = true
    else
        -- Stop only OUR animation, not everything the ped is doing.
        StopAnimTask(ped, cfg.dict, cfg.clip, cfg.blendOut)
        Actions.handsUp = false
    end

    TriggerEvent('bs:emotes:handsUp', Actions.handsUp)
    return true
end

RegisterCommand('bs_handsup', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if busy() then return end
    Actions.SetHandsUp(not Actions.handsUp)
end, false)
RegisterKeyMapping('bs_handsup', L('emote.key_handsup'), 'keyboard', Emotes.Keys.handsUp)

-- Keep the pose alive: any task change (bump, ragdoll) cancels the anim, so re-apply it while hands are up.
CreateThread(function()
    while true do
        Wait(400)
        if Actions.handsUp then
            local ped = PlayerPedId()
            if busy() then
                Actions.SetHandsUp(false)
            elseif not IsEntityPlayingAnim(ped, Emotes.HandsUp.dict, Emotes.HandsUp.clip, 3) then
                Actions.SetHandsUp(true)
            end
        end
    end
end)

--- You cannot shoot with your hands in the air.
CreateThread(function()
    while true do
        if Actions.handsUp then
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)    -- attack
            DisableControlAction(0, 25, true)    -- aim
            DisableControlAction(0, 47, true)    -- weapon
            DisableControlAction(0, 58, true)
        else
            Wait(250)
        end
    end
end)

--------------------------------------------------------------------------------
-- Whistle
--------------------------------------------------------------------------------

RegisterCommand('bs_whistle', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if busy() then return end
    if GetGameTimer() - lastWhistle < (Emotes.Whistle.cooldown or 1500) then return end
    lastWhistle = GetGameTimer()

    local ped = PlayerPedId()
    local cfg = Emotes.Whistle

    if loadDict(cfg.dict) then
        TaskPlayAnim(ped, cfg.dict, cfg.clip, 4.0, 4.0, 1200, cfg.flag, 0, false, false, false)
    end

    PlaySoundFrontend(-1, 'Whistle_Dog', 'DLC_BTL_Dog_Sounds', true)

    -- Whistling is noise, and noise is what the dead follow.
    Noise.Make('whistle', GetEntityCoords(ped))
end, false)
RegisterKeyMapping('bs_whistle', 'Whistle', 'keyboard', Emotes.Keys.whistle)

AddEventHandler('bs:hook:player:unloaded', function()
    if Actions.handsUp then Actions.SetHandsUp(false) end
end)

exports('IsHandsUp', function() return Actions.handsUp end)
