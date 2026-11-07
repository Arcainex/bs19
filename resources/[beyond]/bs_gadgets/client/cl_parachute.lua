-- Alpha-Z: a parachute is usable ONLY while its real inventory item is equipped
-- in either server-authoritative bs_gadgets slot. No wardrobe component grants it.
local PARACHUTE = joaat('GADGET_PARACHUTE')
local permitted = false
local function equipped(loadout)
    if type(loadout) ~= 'table' then return false end
    for i = 1, 2 do
        local e = loadout[tostring(i)] or loadout[i]
        if type(e) == 'table' and e.item == 'parachute' and (tonumber(e.count) or 0) > 0 then
            return true
        end
    end
    return false
end

AddEventHandler('bs:gadgets:loadoutChanged', function(loadout)
    permitted = equipped(loadout)
end)

-- The engine consumes its parachute gadget on use. Re-grant it while the
-- actual item remains equipped, including after respawn or changing ped model.
-- Never remove a deployed chute mid-flight if the slot is emptied in the air.
CreateThread(function()
    local lastPed = 0
    local onGroundSince = nil
    while true do
        Wait(700)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            if ped ~= lastPed then
                lastPed = ped
                onGroundSince = nil
            end
            local alive = not IsEntityDead(ped) and not LocalPlayer.state.bsDowned
            local wanted = permitted and alive
            local has = HasPedGotWeapon(ped, PARACHUTE, false)
            local flying = IsPedInParachuteFreeFall(ped) or GetPedParachuteState(ped) > 0
            -- GTA can consume GADGET_PARACHUTE on deployment. Re-granting
            -- while gliding interrupts the animation and may collapse the canopy
            -- as soon as movement keys are pressed. Never touch it in midair.
            local airborne = flying or IsPedFalling(ped) or IsEntityInAir(ped)
            -- Avoid weapon modifications during a landing transition, too.
            -- Only restore/remove the gadget after 1.4 seconds on the ground.
            if airborne or IsPedInAnyVehicle(ped, false) then
                onGroundSince = nil
            else
                onGroundSince = onGroundSince or GetGameTimer()
            end
            if onGroundSince and GetGameTimer() - onGroundSince >= 1400 then
                if wanted and not has then
                    GiveWeaponToPed(ped, PARACHUTE, 1, false, false)
                elseif not wanted and has then
                    RemoveWeaponFromPed(ped, PARACHUTE)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped)
           and not (IsPedInParachuteFreeFall(ped) or GetPedParachuteState(ped) >= 0 or IsEntityInAir(ped)) then
            RemoveWeaponFromPed(ped, PARACHUTE)
        end
    end
end)
