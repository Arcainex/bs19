-- Alpha-Z: remote crossbow sound, distance checked using server-side ped position.
local last = {}
RegisterNetEvent('alpha_z_crossbow:shot', function()
    local src = source
    local now = GetGameTimer()
    if last[src] and now - last[src] < 220 then return end
    last[src] = now
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local p = GetEntityCoords(ped)
    for _, target in ipairs(GetPlayers()) do
        local dst = tonumber(target)
        if dst and dst ~= src then
            local other = GetPlayerPed(dst)
            if other and other ~= 0 and #(GetEntityCoords(other) - p) <= 55.0 then
                TriggerClientEvent('alpha_z_crossbow:remoteShot', dst, {x=p.x, y=p.y, z=p.z})
            end
        end
    end
end)
AddEventHandler('playerDropped', function() last[source] = nil end)
