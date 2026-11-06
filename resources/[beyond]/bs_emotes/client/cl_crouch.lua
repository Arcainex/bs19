-- bs_emotes - crouch: gTA has no on-foot crouch state

Crouch = { active = false }

local cfg = Emotes.Crouch or {}

-- Load the clipset like any animation asset.
local function loadSet(name)
    if HasAnimSetLoaded(name) then return true end

    RequestAnimSet(name)
    local waited = 0
    while not HasAnimSetLoaded(name) and waited < 2000 do
        Wait(10)
        waited = waited + 10
    end

    return HasAnimSetLoaded(name)
end

local function canCrouch()
    local ped = PlayerPedId()

    if not exports.bs_core:IsLoaded() then return false end
    if IsEntityDead(ped) then return false end
    if IsPedInAnyVehicle(ped, false) then return false end
    if IsPedFalling(ped) or IsPedRagdoll(ped) then return false end
    if IsPedSwimming(ped) then return false end

    -- Not mid-stumble: a clipset set during cl_movement's double-tap ragdoll recovery can leave the ped stuck half-standing.
    if GetResourceState('bs_emotes') == 'started' and Movement and Movement.recovering then
        return false
    end

    return true
end

function Crouch.Set(state)
    local ped = PlayerPedId()

    if not state then
        Crouch.active = false
        ResetPedMovementClipset(ped, cfg.blendOut or 0.35)
        ResetPedStrafeClipset(ped)
        TriggerEvent('bs:emotes:crouch', false)
        return true
    end

    if not canCrouch() then return false end

    -- Already prone? Come up to a crouch instead of doing nothing.
    if Prone and Prone.active then Prone.Set(false) end

    local set = cfg.clipset or 'move_ped_crouched'
    if not loadSet(set) then return false end

    Crouch.active = true
    SetPedMovementClipset(ped, set, cfg.blendIn or 0.35)

    -- The strafe set is a separate clipset.
    local strafe = cfg.strafeClipset or 'move_ped_crouched_strafing'
    if loadSet(strafe) then SetPedStrafeClipset(ped, strafe) end

    TriggerEvent('bs:emotes:crouch', true)
    return true
end

-- The command name matters: the key in RegisterKeyMapping is only a default
RegisterCommand('bs_stance_crouch', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if Crouch.active then
        Crouch.Set(false)
    elseif not Crouch.Set(true) then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = L('emote.not_here'), duration = 1500 })
    end
end, false)

-- Escape hatch. cl_prone.lua also registers `/standup`, and RegisterCommand replaces an existing handler.
RegisterCommand('standup', function()
    Crouch.Set(false)
    if Prone then Prone.Set(false) end
end, false)

RegisterKeyMapping('bs_stance_crouch', L('emote.key_crouch'), 'keyboard',
    Emotes.Keys.crouch or 'K')

-- Drop the stance when the body stops being yours.
CreateThread(function()
    while true do
        Wait(250)

        if Crouch.active then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then
                Crouch.Set(false)
            end
        end
    end
end)

AddEventHandler('bs:hook:player:spawned', function() Crouch.Set(false) end)

-- Prone and crouch are the same axis, so each clears the other.
AddEventHandler('bs:emotes:prone', function(state)
    if state and Crouch.active then Crouch.Set(false) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and Crouch.active then
        ResetPedMovementClipset(PlayerPedId(), 0.0)
        ResetPedStrafeClipset(PlayerPedId())
    end
end)

exports('IsCrouched', function() return Crouch.active end)
exports('SetCrouched', function(state) return Crouch.Set(state and true or false) end)
