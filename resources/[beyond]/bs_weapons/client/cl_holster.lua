-- bs_weapons - holster

Holster = { stowed = nil, stowedAt = nil, busy = false }

local ANIM = {
    -- Reaching across the body. Upper-body only, so it can be done walking.
    dict = 'reaction@intimidation@cop@unarmed',
    clip = 'intro',
    time = 700,
    flag = 49,
}

local UNARMED = GetHashKey('WEAPON_UNARMED')


local function playStow()
    local ped = PlayerPedId()
    if not DoesAnimDictExist(ANIM.dict) then return end

    if not HasAnimDictLoaded(ANIM.dict) then RequestAnimDict(ANIM.dict) end
    local waited = 0
    while not HasAnimDictLoaded(ANIM.dict) and waited < 900 do Wait(10); waited = waited + 10 end
    if not HasAnimDictLoaded(ANIM.dict) then return end

    TaskPlayAnim(ped, ANIM.dict, ANIM.clip, 4.0, -4.0, ANIM.time, ANIM.flag,
        0.0, false, false, false)
end

--- @return boolean drawn  true if the weapon came OUT
function Holster.Toggle()
    if Holster.busy then return false end

    local ped = PlayerPedId()

    if IsPedDeadOrDying(ped, true) then return false end
    if IsPedInAnyVehicle(ped, false) then
        TriggerEvent('bs:ui:notify', {
            type = 'info', message = L('wp.not_here'), duration = 1800,
        })
        return false
    end

    Holster.busy = true

    local _, current = GetCurrentPedWeapon(ped, true)

    if current and current ~= UNARMED then
        -- Putting it away.
        Holster.stowed = current
        -- Timestamp of the stow
        Holster.stowedAt = GetGameTimer()
        playStow()
        Wait(math.floor(ANIM.time * 0.45))
        SetCurrentPedWeapon(ped, UNARMED, true)
        Wait(160)
        Holster.busy = false
        return false
    end

    -- Taking it out again. Nothing stowed means nothing to draw.
    if not Holster.stowed or not HasPedGotWeapon(ped, Holster.stowed, false) then
        Holster.busy = false
        TriggerEvent('bs:ui:notify', {
            type = 'info', message = L('wp.nothing_draw'), duration = 1800,
        })
        return false
    end

    playStow()
    Wait(math.floor(ANIM.time * 0.45))
    SetCurrentPedWeapon(ped, Holster.stowed, true)
    Wait(160)

    -- Clear stowed on draw so it only means "currently stowed". cl_dryfire.lua relies on that.
    Holster.stowed = nil
    Holster.stowedAt = nil

    Holster.busy = false
    return true
end

-- Called by anything that hands you a weapon (hotbar, item use, admin menu)
function Holster.Clear()
    Holster.stowed = nil
    Holster.stowedAt = nil
end

-- Keys and events

RegisterCommand('bs_holster', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    CreateThread(function() Holster.Toggle() end)
end, false)

RegisterKeyMapping('bs_holster', L('wpn.key_holster'), 'keyboard', 'J')

-- Pressing the slot of the weapon already in hand puts it away instead of re-drawing it.
AddEventHandler('bs:weapons:hotbarWeapon', function(weaponName)
    local ped = PlayerPedId()
    local _, current = GetCurrentPedWeapon(ped, true)

    if current and weaponName and current == GetHashKey(weaponName) then
        CreateThread(function() Holster.Toggle() end)
    else
        Holster.Clear()
    end
end)

AddEventHandler('bs:hook:player:unloaded', function()
    Holster.stowed, Holster.stowedAt = nil, nil
end)

exports('Holster', function() CreateThread(function() Holster.Toggle() end) end)
exports('IsHolstered', function()
    local _, current = GetCurrentPedWeapon(PlayerPedId(), true)
    return current == UNARMED and Holster.stowed ~= nil
end)
