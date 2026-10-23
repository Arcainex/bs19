-- BeyondSurvival - bs_vehicles keys: handing keys over face to face, lockpicking and hotwiring locked cars (slow and loud)

Keys = {}

local working = false

-- Handing one over

--- Nearest OTHER player, within arm's reach.
local function nearestPlayer(range)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)

    local best, bestDist
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped ~= me and DoesEntityExist(ped) then
            local dist = #(GetEntityCoords(ped) - at)
            if dist <= (range or 3.0) and (not bestDist or dist < bestDist) then
                best, bestDist = playerId, dist
            end
        end
    end

    return best
end

function Keys.GiveNearest(plate)
    local playerId = nearestPlayer(3.0)

    if not playerId then
        return TriggerEvent('bs:ui:notify', {
            type = 'warn', message = L('keys.nobody'), duration = 3000,
        })
    end

    local serverId = GetPlayerServerId(playerId)
    local result = BSB.Await('vehicles:giveKey', 6000, plate, serverId)

    TriggerEvent('bs:ui:notify', {
        type = (result and result.ok) and 'success' or 'warn',
        message = (result and result.ok)
            and L('keys.handed', { plate = plate })
            or ((result and result.error) or L('keys.refused')),
        duration = 3200,
    })
end

-- Getting in without one

-- Hotwiring. Long, loud and interruptible: moving cancels it.
function Keys.Hotwire(vehicle)
    if working then return end

    local plate = Veh.Plate(vehicle)
    if not plate then return end

    if GetResourceState('bs_inventory') == 'started' then
        local ok, count = pcall(function()
            return exports.bs_inventory:CountLocal('lockpick')
        end)
        -- The client mirror can be empty before the bag was ever opened, so zero is only a hint
        if ok and type(count) == 'number' and count == 0 then
            TriggerEvent('bs:ui:notify', {
                type = 'info', message = L('keys.want_pick'), duration = 3000,
            })
        end
    end

    working = true

    local ped = PlayerPedId()
    local dict = 'veh@break_in@0h@p_m_one@'

    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'low_force_entry_ds', 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end

    local total = Vehicles.Settings.hotwireTime or 12000
    local started = GetGameTimer()
    local cancelled = false

    TriggerEvent('bs:ui:notify', { type = 'info', message = L('keys.working'), duration = 2500 })

    while GetGameTimer() - started < total do
        Wait(100)

        -- Moving away, or being knocked down, ends it.
        if not DoesEntityExist(vehicle)
           or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 4.0
           or IsPedRagdoll(ped) or IsEntityDead(ped) then
            cancelled = true
            break
        end

        -- Noise carries. bs_emotes owns the noise channel and bs_zombies listens to it.
        if math.random() < 0.08 and GetResourceState('bs_emotes') == 'started' then
            pcall(function()
                exports.bs_emotes:MakeNoise('melee', GetEntityCoords(ped), 22.0)
            end)
        end
    end

    ClearPedTasks(ped)
    working = false

    if cancelled then
        return TriggerEvent('bs:ui:notify', {
            type = 'warn', message = L('keys.lost'), duration = 2600,
        })
    end

    local result = BSB.Await('vehicles:hotwire', 8000, plate)

    TriggerEvent('bs:ui:notify', {
        type = (result and result.ok) and 'success' or 'warn',
        message = (result and result.ok) and L('keys.gives')
            or ((result and result.error) or L('keys.wont_give')),
        duration = 3000,
    })
end

RegisterCommand('hotwire', function()
    CreateThread(function()
        local vehicle = Veh.Nearby(4.0)
        if not vehicle then
            return TriggerEvent('bs:ui:notify', {
                type = 'info', message = L('common.nothing_reach'), duration = 2400,
            })
        end
        Keys.Hotwire(vehicle)
    end)
end, false)

exports('GiveKey', function(plate) CreateThread(function() Keys.GiveNearest(plate) end) end)
exports('Hotwire', function(vehicle) CreateThread(function() Keys.Hotwire(vehicle) end) end)
