-- Alpha-Z universal melee durability. Isolated from bs_inventory internals.
-- Every successful melee hit consumes exactly 1 durability point.
local WEAPONS = {
    [GetHashKey('WEAPON_KNIFE')]         = 'hunting_knife',
    [GetHashKey('WEAPON_BAT')]           = 'reinforced_bat',
    [GetHashKey('WEAPON_HAMMER')]        = 'hammer',
    [GetHashKey('WEAPON_BOTTLE')]        = 'weapon_bottle',
    [GetHashKey('WEAPON_POOLCUE')]       = 'weapon_poolcue',
    [GetHashKey('WEAPON_GOLFCLUB')]      = 'weapon_golfclub',
    [GetHashKey('WEAPON_STONE_HATCHET')] = 'weapon_stone_hatchet',
    [GetHashKey('WEAPON_DAGGER')]        = 'weapon_dagger',
    [GetHashKey('WEAPON_MACHETE')]       = 'machete',
    [GetHashKey('WEAPON_CROWBAR')]       = 'crowbar',
    [GetHashKey('WEAPON_FLASHLIGHT')]    = 'flashlight',
    [GetHashKey('WEAPON_HATCHET')]       = 'hatchet',
}

local lastHitAt = 0

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker = args[1], args[2]
    local ped = PlayerPedId()
    if attacker ~= ped or not victim or victim == 0 or victim == ped then return end
    if not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end

    local weaponHash = GetSelectedPedWeapon(ped)
    local itemName = WEAPONS[weaponHash]
    if not itemName then return end

    local now = GetGameTimer()
    if now - lastHitAt < 180 then return end
    lastHitAt = now
    TriggerServerEvent('bs:alphaMelee:successfulHit', itemName, weaponHash)
end)

RegisterNetEvent('bs:alphaMelee:broke', function(weaponHash)
    local ped = PlayerPedId()
    weaponHash = tonumber(weaponHash)
    if not weaponHash then return end
    if GetSelectedPedWeapon(ped) == weaponHash then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    end
    RemoveWeaponFromPed(ped, weaponHash)
    TriggerEvent('bs:weapons:forget', weaponHash)
end)
