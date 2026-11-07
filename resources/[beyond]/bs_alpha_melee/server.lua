-- Alpha-Z universal melee durability. Uses only the existing WearItem export.
local ALLOWED = {
    hunting_knife  = joaat('WEAPON_KNIFE'),
    reinforced_bat = joaat('WEAPON_BAT'),
    hammer         = joaat('WEAPON_HAMMER'),
    weapon_bottle  = joaat('WEAPON_BOTTLE'),
    weapon_poolcue       = joaat('WEAPON_POOLCUE'),
    weapon_golfclub      = joaat('WEAPON_GOLFCLUB'),
    weapon_stone_hatchet  = joaat('WEAPON_STONE_HATCHET'),
    weapon_dagger = joaat('WEAPON_DAGGER'),
    machete        = joaat('WEAPON_MACHETE'),
    crowbar        = joaat('WEAPON_CROWBAR'),
    flashlight     = joaat('WEAPON_FLASHLIGHT'),
    hatchet        = joaat('WEAPON_HATCHET'),
}

local lastWear = {}
RegisterNetEvent('bs:alphaMelee:successfulHit', function(itemName, weaponHash)
    local src = source
    local expected = ALLOWED[itemName]
    if not expected or tonumber(weaponHash) ~= expected then return end

    local now = GetGameTimer()
    if lastWear[src] and now - lastWear[src] < 150 then return end
    lastWear[src] = now

    local ok, worn, left, broke = pcall(function()
        return exports.bs_inventory:WearItem(src, itemName, 1)
    end)
    if not ok or not worn then return end

    if broke then
        TriggerClientEvent('bs:alphaMelee:broke', src, expected)
        TriggerClientEvent('bs:ui:notify', src, {
            type = 'warn', message = 'Deine Nahkampfwaffe / dein Werkzeug ist zerbrochen.', duration = 3500,
        })
    end
end)

AddEventHandler('playerDropped', function() lastWear[source] = nil end)
