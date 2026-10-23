-- bs_extraction - client: reports the current zone, reports your own death to another player, and runs the stand-still timer at extraction points.
-- The server checks all of it (zone jumps, distance at extraction time).

local currentZone   = nil
local rogue         = false
local extracting    = false

-- Zone membership is polled and reported, never assumed locally.

CreateThread(function()
    while true do
        Wait(Extraction.Settings.zoneUpdateIntervalMs or 2000)

        local ped = PlayerPedId()
        if ped and ped ~= 0 and not IsEntityDead(ped) then
            local at = GetEntityCoords(ped)
            local zone = Extraction.ZoneFor(at.x, at.y, at.z)
            local zoneId = zone and zone.id or nil

            if zoneId ~= currentZone then
                currentZone = zoneId
                if zone then
                    TriggerEvent('bs:ui:notify', {
                        type = 'warn', message = L('ex.entering', { zone = zone.label }), duration = 3400,
                    })
                end
            end

            TriggerServerEvent('bs:extraction:zoneUpdate', zoneId, at.x, at.y, at.z)
        end
    end
end)

-- Rogue state, replicated from the server as a state bag.

AddStateBagChangeHandler('bsRogue', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    rogue = value or false
end)

-- Report our own death by another player. Only fires when the victim is our own ped.

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim, attacker, victimDied = args[1], args[2], args[3]
    if not victimDied or victimDied == 0 then return end
    if victim ~= PlayerPedId() then return end
    if not attacker or attacker == 0 or attacker == victim then return end
    if not IsPedAPlayer(attacker) then return end

    local attackerPlayer = NetworkGetPlayerIndexFromPed(attacker)
    if not attackerPlayer or attackerPlayer == -1 then return end

    local attackerServerId = GetPlayerServerId(attackerPlayer)
    if attackerServerId and attackerServerId > 0 then
        TriggerServerEvent('bs:extraction:playerKilled', attackerServerId)
    end
end)

-- Extraction points: proximity + hold still; cancels on moving away or dying.

local function attemptExtraction(zone, point)
    if extracting then return end
    extracting = true

    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = L('ex.extracting', { place = point.label, s = point.dwellSeconds }),
        duration = point.dwellSeconds * 1000,
    })

    local started = GetGameTimer()
    local needed = (point.dwellSeconds or 25) * 1000
    local cancelled = false

    while GetGameTimer() - started < needed do
        Wait(250)
        local ped = PlayerPedId()
        if IsEntityDead(ped) then cancelled = true; break end

        local at = GetEntityCoords(ped)
        local dx, dy, dz = at.x - point.coords.x, at.y - point.coords.y, at.z - point.coords.z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > (Extraction.Settings.dwellCancelDistance or 8.0) then
            cancelled = true
            break
        end
    end

    if cancelled then
        extracting = false
        return TriggerEvent('bs:ui:notify', {
            type = 'warn', message = L('ex.cancel'), duration = 2600,
        })
    end

    local result = BSB.Await('extraction:complete', 8000, zone.id, point.id)
    extracting = false

    if result and result.ok then
        TriggerEvent('bs:ui:notify', {
            type = 'success',
            message = L('ex.clean', { money = result.money or 0, xp = result.xp or 0 }),
            duration = 4200,
        })
    else
        TriggerEvent('bs:ui:notify', {
            type = 'warn',
            message = (result and result.error) or L('ex.failed'),
            duration = 3200,
        })
    end
end

-- Marker + prompt loop. The nearby check only runs inside a zone.
CreateThread(function()
    while true do
        if not currentZone then
            Wait(1000)
        else
            Wait(0)
            local zone = Extraction.GetZone(currentZone)
            if zone then
                local ped = PlayerPedId()
                local at = GetEntityCoords(ped)

                for _, point in ipairs(zone.extractionPoints) do
                    local dx, dy, dz = at.x - point.coords.x, at.y - point.coords.y, at.z - point.coords.z
                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                    if dist <= (point.radius or 6.0) then
                        DrawMarker(1, point.coords.x, point.coords.y, point.coords.z - 1.0,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, point.radius * 2, point.radius * 2, 1.0,
                            80, 180, 120, 120, false, true, 2, false, nil, nil, false)

                        if not extracting and dist <= (point.radius * 0.6) then
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName(L('ex.hold_still', { n = point.dwellSeconds }))
                            EndTextCommandDisplayHelp(0, false, true, -1)

                            if IsControlJustReleased(0, 38) then -- E
                                CreateThread(function() attemptExtraction(zone, point) end)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Exports

exports('CurrentZone', function() return currentZone end)
exports('IsRogue', function() return rogue end)
