-- bs_zombies - horde warning

local Horde = { active = false, until_ = 0, coords = nil }

RegisterNetEvent('bs:z:horde', function(payload)
    if not payload or not payload.coords then return end

    local coords = vector3(payload.coords.x, payload.coords.y, payload.coords.z)

    TriggerEvent('bs:ui:notify', {
        type = 'error',
        title = L('zed.heard_title'),
        message = L('zed.move_now'),
        duration = 6000,
    })

    CreateThread(function()
        local warning = (payload.warning or 12) * 1000
        local elapsed = 0

        while elapsed < warning do
            Wait(2600)
            elapsed = elapsed + 2600
            -- A missing sound name on a build just doesn't play.
            PlaySoundFromCoord(-1, 'Beast_Howl', coords.x, coords.y, coords.z,
                'RESPAWN_ONLINE_SOUNDSET', false, 220, false)
        end

        Horde.active = true
        Horde.coords = coords
        Horde.until_ = GetGameTimer() + ((payload.duration or 180) * 1000)

        TriggerEvent('bs:ui:notify', {
            type = 'error', message = L('zed.they_here'), duration = 4000,
        })
    end)
end)

RegisterNetEvent('bs:z:hordeOver', function()
    Horde.active = false
    Horde.coords = nil
end)

--- The server tells a host to pull one of its walkers toward something.
RegisterNetEvent('bs:z:draw', function(id, coords)
    local entry = Zed and Zed.live[id]
    if not entry or not entry.hosted then return end
    if not Zombies.Draw then return end

    Zombies.Draw(entry, vector3(coords.x, coords.y, coords.z))
end)

CreateThread(function()
    while true do
        Wait(5000)
        if Horde.active and GetGameTimer() > Horde.until_ then
            Horde.active = false
            Horde.coords = nil
        end
    end
end)

exports('HordeActive', function() return Horde.active end)
