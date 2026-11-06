if IsDuplicityVersion() then return end

QBX = QBX or {}
QBX.PlayerData = exports.qbx_core:GetPlayerData() or {}

AddEventHandler('QBCore:Player:SetPlayerData', function(data)
    QBX.PlayerData = data or {}
end)

AddEventHandler('qbx_core:client:playerLoggedOut', function()
    QBX.PlayerData = {}
end)
