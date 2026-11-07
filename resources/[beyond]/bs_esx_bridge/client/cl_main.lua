-- bs_esx_bridge - fills ESX.PlayerData/ESX.PlayerLoaded from the esx:playerLoaded event re-broadcast by sv_main.lua.

RegisterNetEvent('esx:playerLoaded', function(xPlayerData)
    ESX.PlayerData = xPlayerData or ESX.PlayerData
    ESX.PlayerLoaded = true
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}
end)

RegisterNetEvent('esx:setAccountMoney', function(account)
    if not account or not account.name then return end
    ESX.PlayerData.accounts = ESX.PlayerData.accounts or {}
    for _, existing in ipairs(ESX.PlayerData.accounts) do
        if existing.name == account.name then
            existing.money = account.money
            return
        end
    end
    table.insert(ESX.PlayerData.accounts, account)
end)
