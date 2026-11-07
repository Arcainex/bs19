local function nearStorage(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - PersonalStorage.Position) <= PersonalStorage.ServerDistance
end

RegisterNetEvent('bs:personalStorage:open', function()
    local src = source
    if not nearStorage(src) then return end

    local okPlayer, player = pcall(function()
        return exports.bs_core:GetPlayer(src)
    end)
    if not okPlayer or not player or not player.charId then return end

    -- The character id is part of the server-created container id. This means
    -- every character gets a different persistent inventory at the same world point.
    local containerId = ('personal:%s'):format(tostring(player.charId))
    local ok = exports.bs_inventory:RegisterContainer(containerId, {
        label = PersonalStorage.Label,
        width = PersonalStorage.Width,
        height = PersonalStorage.Height,
        maxWeight = PersonalStorage.MaxWeight,
        compact = false,
    }, src)

    if ok then
        exports.bs_inventory:OpenContainerFor(src, containerId)
    end
end)
