-- bs_esx_bridge - server side. Runs once per resource, not per include of shared/sh_esx.lua:
-- 1. Re-broadcasts bs_core hooks as ESX events (esx:playerLoaded, esx:onPlayerLogout).
-- 2. Provides the getSharedObject export for scripts that can't add a shared_script line.

--------------------------------------------------------------------------------
-- Standard event re-broadcast
--------------------------------------------------------------------------------

-- The hook payload is a serialised copy across resources (fields only, no methods). It only identifies who, then an xPlayer is built via ESX.GetPlayerFromId.
AddEventHandler('bs:hook:player:loaded', function(player)
    local src = tonumber(type(player) == 'table' and player.source)
    if not src then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    TriggerClientEvent('esx:playerLoaded', src, xPlayer, false)
    TriggerEvent('esx:playerLoaded', src, xPlayer)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    local src = tonumber(type(player) == 'table' and player.source)
    if not src then return end

    TriggerClientEvent('esx:onPlayerLogout', src)
    TriggerEvent('esx:playerDropped', src)
end)

AddEventHandler('bs:hook:player:money', function(player, account, amount, reason)
    local src = tonumber(type(player) == 'table' and player.source)
    if not src then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    TriggerClientEvent('esx:setAccountMoney', src,
        { name = (account == 'bank') and 'bank' or 'money', money = xPlayer.getAccount(account == 'bank' and 'bank' or 'money').money })
end)

--------------------------------------------------------------------------------
-- Fallback export path - see shared/sh_esx.lua's header comment
--------------------------------------------------------------------------------

exports('getSharedObject', function() return ESX end)


CreateThread(function()
    -- Waits one tick so bs_core has had the chance to finish its own
    -- resource-start registration first.
    Wait(0)
    local ok = pcall(function() return exports.bs_core:RegisterModule('esx_bridge', { side = 'server', version = '0.1.0', ready = true }) end)
    if not ok then
        print('^3[bs_esx_bridge]^7 bs_core not ready yet - module registration skipped, bridge still works')
    end
    print('^2[bs_esx_bridge]^7 ready - ESX-shaped scripts can point at this resource instead of es_extended')
end)
