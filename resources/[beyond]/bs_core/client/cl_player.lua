-- Client-side mirror of the server Player object. Read-only; replicated from the server.

BS.Player = {
    loaded = false,
    data   = {},
}

local P = BS.Player

function BS.IsLoaded()   return P.loaded end
function BS.GetData(key) if key == nil then return P.data end return P.data[key] end

RegisterNetEvent(BS.Events.PlayerLoaded, function(payload)
    P.data   = payload or {}
    P.loaded = true
    BS.Emit('player:loaded', P.data)
    BS.Log.info('player', ('loaded %s (level %d, %s)')
        :format(P.data.name or '?', P.data.level or 0, P.data.classId or '?'))
end)

RegisterNetEvent(BS.Events.PlayerUnloaded, function(reason)
    P.loaded = false
    BS.Emit('player:unloaded', reason)
    P.data = {}
end)

RegisterNetEvent(BS.Events.PlayerDataSet, function(key, value)
    P.data[key] = value
    BS.Emit('player:dataSet', key, value)
end)

-- A class change re-applies body stats live; health keeps its fraction of the old max.
BS.On('player:dataSet', function(key, value)
    if key ~= 'class' or type(value) ~= 'table' then return end
    local stats = value.stats or {}
    local ped = PlayerPedId()
    local oldMax = GetEntityMaxHealth(ped)
    local frac = oldMax > 100 and (GetEntityHealth(ped) - 100) / (oldMax - 100) or 1.0
    local newMax = stats.maxHealth or 200
    SetEntityMaxHealth(ped, newMax)
    SetEntityHealth(ped, math.floor(100 + math.max(0.0, math.min(1.0, frac)) * (newMax - 100)))
    SetPlayerMaxArmour(PlayerId(), stats.armorCap or 100)
end)

RegisterNetEvent(BS.Events.PlayerMoney, function(account, balance, delta)
    P.data.accounts = P.data.accounts or {}
    P.data.accounts[account] = balance
    BS.Emit('player:money', account, balance, delta)
end)

RegisterNetEvent(BS.Events.PlayerNeeds, function(needs)
    P.data.needs = needs
    BS.Emit('player:needs', needs)
end)

RegisterNetEvent(BS.Events.PlayerXP, function(xp, xpToNext, level, gained)
    P.data.xp, P.data.xpToNext, P.data.level = xp, xpToNext, level
    BS.Emit('player:xp', xp, xpToNext, level, gained)
end)

RegisterNetEvent(BS.Events.PlayerLevelUp, function(level, skillPoints)
    P.data.level, P.data.skillPoints = level, skillPoints
    BS.Emit('player:levelUp', level, skillPoints)
end)

exports('IsLoaded', BS.IsLoaded)
exports('GetData', BS.GetData)
