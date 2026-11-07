-- bs_emotes - relays noise to everyone who could hear it, server-side so one player's gunshot reaches other players' zombie sims.

local RELAY_PADDING = 40.0   -- relay a bit past the radius; zombies drift

-- Server-side throttle: the client throttle alone can be bypassed with a direct TriggerServerEvent, forcing GetPlayers() scans and broadcasts.
local NOISE_COOLDOWN_MS = 200
local lastNoise = {} -- [src] = GetGameTimer() of the last accepted report

RegisterNetEvent('bs:world:noise', function(kind, coords, radius)
    local src = source
    if type(coords) ~= 'table' then return end

    local now = GetGameTimer()
    if lastNoise[src] and (now - lastNoise[src]) < NOISE_COOLDOWN_MS then return end
    lastNoise[src] = now

    radius = math.min(400.0, math.max(1.0, tonumber(radius) or 20.0))
    local origin = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    -- Sanity check: the noise must come from roughly where the player is.
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        if #(GetEntityCoords(ped) - origin) > 25.0 then return end
    end

    local payload = {
        kind = kind, radius = radius,
        coords = { x = origin.x, y = origin.y, z = origin.z },
        source = src,
    }

    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src then
            local other = GetPlayerPed(id)
            if other and other ~= 0 and #(GetEntityCoords(other) - origin) <= (radius + RELAY_PADDING) then
                TriggerClientEvent('bs:world:noiseRelay', id, payload)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastNoise[source] = nil
end)

exports.bs_core:RegisterModule('emotes', { side = 'server', version = '0.1.0' })
