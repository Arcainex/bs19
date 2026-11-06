exports('Notify', function(message, kind)
    local text = type(message) == 'table' and message.text or message
    local caption = type(message) == 'table' and message.caption or nil
    if caption and caption ~= '' then text = ('%s\n%s'):format(tostring(text or ''), caption) end
    local tone = ({ inform = 'info', warning = 'warning', success = 'success', error = 'error' })[kind] or 'info'
    TriggerEvent('bs:ui:notify', { type = tone, message = tostring(text or '') })
end)

local function playerData()
    if not exports.bs_core:IsLoaded() then return nil end
    local data = exports.bs_core:GetData()
    if not data or not data.charId then return nil end
    local meta = data.metadata or {}
    local needs = data.needs or {}
    local metadata = {}
    for key, value in pairs(meta) do metadata[key] = value end
    for key, value in pairs(needs) do metadata[key] = value end
    return {
        source = GetPlayerServerId(PlayerId()),
        citizenid = ('bs:%s'):format(data.charId),
        name = data.name,
        charinfo = { firstname = data.firstName, lastname = data.lastName, gender = data.gender },
        money = { cash = (data.accounts or {}).cash or 0, bank = (data.accounts or {}).bank or 0 },
        metadata = metadata,
        job = { name = 'unemployed', label = 'Unemployed', grade = { name = 'Unemployed', level = 0 }, onduty = false },
        gang = { name = 'none', label = 'None', grade = { name = 'None', level = 0 } },
    }
end

exports('GetPlayerData', playerData)

local function updatePlayerData()
    local data = playerData()
    if data then TriggerEvent('QBCore:Player:SetPlayerData', data) end
end

AddEventHandler('bs:hook:player:loaded', updatePlayerData)
AddEventHandler('bs:hook:player:dataSet', updatePlayerData)
AddEventHandler('bs:hook:player:money', updatePlayerData)
AddEventHandler('bs:hook:player:needs', updatePlayerData)

AddEventHandler('bs:hook:player:spawned', function()
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end)

AddEventHandler('bs:hook:player:unloaded', function()
    TriggerEvent('qbx_core:client:playerLoggedOut')
end)
