local function sourceFor(identifier)
    local src = tonumber(identifier)
    if src then return src end
    if type(identifier) ~= 'string' then return nil end
    local charId = identifier:match('^bs:(%d+)$')
    if not charId then return nil end
    for _, player in pairs(exports.bs_core:GetPlayers()) do
        if tostring(player.charId) == charId then return player.source end
    end
end

local function playerData(src)
    local data = exports.bs_core:GetPlayerSummary(src)
    if not data then return nil end
    return {
        source = src,
        citizenid = ('bs:%s'):format(data.charId),
        charinfo = { firstname = data.firstName, lastname = data.lastName, gender = data.gender },
        name = data.name,
        money = { cash = data.accounts.cash or 0, bank = data.accounts.bank or 0 },
        metadata = data.needs or {},
        job = { name = 'unemployed', label = 'Unemployed', grade = { name = 'Unemployed', level = 0 }, onduty = false },
        gang = { name = 'none', label = 'None', grade = { name = 'None', level = 0 } },
    }
end

local function getPlayer(identifier)
    local src = sourceFor(identifier)
    local data = src and playerData(src)
    if not data then return nil end
    local functions = {}
    function functions.GetMoney(kind) return exports.qbx_core:GetMoney(src, kind) end
    function functions.AddMoney(kind, amount, reason) return exports.qbx_core:AddMoney(src, kind, amount, reason) end
    function functions.RemoveMoney(kind, amount, reason) return exports.qbx_core:RemoveMoney(src, kind, amount, reason) end
    function functions.SetMoney(kind, amount, reason) return exports.qbx_core:SetMoney(src, kind, amount, reason) end
    function functions.GetMetaData(key) return exports.qbx_core:GetMetadata(src, key) end
    function functions.SetMetaData(key, value) return exports.qbx_core:SetMetadata(src, key, value) end
    function functions.AddItem(item, amount, slot, metadata)
        return exports.bs_inventory:GiveItem(src, item, amount or 1, metadata)
    end
    function functions.RemoveItem(item, amount)
        return exports.bs_inventory:RemoveItem(src, item, amount or 1)
    end
    function functions.GetItemByName(item)
        local count = exports.bs_inventory:CountItem(src, item)
        return count > 0 and { name = item, amount = count } or nil
    end
    return { PlayerData = data, Functions = functions }
end

exports('GetPlayer', getPlayer)
exports('GetPlayerByCitizenId', getPlayer)
exports('GetSource', function(identifier)
    return sourceFor(identifier) or 0
end)
exports('GetCoreVersion', function()
    return GetResourceMetadata('qbx_core', 'version', 0) or '0.1.0'
end)
exports('GetMoney', function(identifier, kind)
    local data = playerData(sourceFor(identifier) or -1)
    return data and data.money[kind] or false
end)
exports('AddMoney', function(identifier, kind, amount, reason)
    local src = sourceFor(identifier)
    if not src or (kind ~= 'cash' and kind ~= 'bank') then return false end
    return exports.bs_core:AddMoney(src, kind, amount, reason or 'qbx_bridge')
end)
exports('RemoveMoney', function(identifier, kind, amount, reason)
    local src = sourceFor(identifier)
    if not src or (kind ~= 'cash' and kind ~= 'bank') then return false end
    return exports.bs_core:RemoveMoney(src, kind, amount, reason or 'qbx_bridge')
end)
exports('SetMoney', function(identifier, kind, amount, reason)
    local src = sourceFor(identifier)
    amount = tonumber(amount)
    if not src or (kind ~= 'cash' and kind ~= 'bank') or not amount or amount < 0 or amount == math.huge or amount ~= amount then return false end
    amount = math.floor(amount)
    local current = exports.qbx_core:GetMoney(src, kind)
    if current == false then return false end
    if amount > current then
        return exports.bs_core:AddMoney(src, kind, amount - current, reason or 'qbx_bridge')
    end
    if amount < current then
        return exports.bs_core:RemoveMoney(src, kind, current - amount, reason or 'qbx_bridge')
    end
    return true
end)
exports('GetMetadata', function(identifier, key)
    local src = sourceFor(identifier)
    return src and exports.bs_core:GetPlayerMeta(src, key) or nil
end)
exports('SetMetadata', function(identifier, key, value)
    local src = sourceFor(identifier)
    return src and exports.bs_core:SetPlayerMeta(src, key, value) or false
end)
exports('GetQBPlayers', function()
    local result = {}
    for src in pairs(exports.bs_core:GetPlayers()) do result[src] = getPlayer(src) end
    return result
end)
exports('GetPlayersData', function()
    local result = {}
    for src in pairs(exports.bs_core:GetPlayers()) do result[#result + 1] = playerData(src) end
    return result
end)
exports('Notify', function(src, message, kind)
    local text = type(message) == 'table' and message.text or message
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = tostring(text or '') })
end)

AddEventHandler('bs:hook:player:loaded', function(player)
    local src = type(player) == 'table' and tonumber(player.source)
    if not src or not playerData(src) then return end
    TriggerEvent('QBCore:Server:OnPlayerLoaded', src)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    local src = type(player) == 'table' and tonumber(player.source)
    if not src then return end
    TriggerEvent('QBCore:Server:OnPlayerUnload', src)
end)
