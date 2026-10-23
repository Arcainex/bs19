-- bs_vehicles - lockpicking minigame. Replaces the old timed hotwire in cl_keys.lua.

local LP = Vehicles.Lockpick or {}
local working = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 2800 })
end

local function lerp(a, b, t) return a + (b - a) * t end

local function text(x, y, scale, str)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
end

local function noise(ped)
    if GetResourceState('bs_emotes') == 'started' then
        pcall(function() exports.bs_emotes:MakeNoise('melee', GetEntityCoords(ped), 22.0) end)
    end
end

-- Returns true (open), false (failed) or nil (walked away).
local function minigame(vehicle, level)
    local t = math.min(1.0, math.max(0.0, (level or 0) / (LP.maxLevel or 20)))
    local zoneW = lerp(LP.zoneMin or 0.08, LP.zoneMax or 0.22, t)
    local speed = lerp(LP.speedMin or 1.35, LP.speedMax or 0.75, t)
    local pins, misses = LP.pins or 3, 0
    local ped = PlayerPedId()

    local barX, barY, barW, barH = 0.5, 0.82, 0.26, 0.022

    for pin = 1, pins do
        local zoneStart = 0.1 + math.random() * (0.9 - zoneW - 0.1)
        local pos, dir = 0.0, 1
        local last = GetGameTimer()
        local set = false

        while not set do
            Wait(0)
            local nowMs = GetGameTimer()
            local dt = (nowMs - last) / 1000.0
            last = nowMs

            if not DoesEntityExist(vehicle) or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 4.0
               or IsPedRagdoll(ped) or IsEntityDead(ped) or IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 177) then
                return nil
            end

            pos = pos + dir * speed * dt
            if pos >= 1.0 then pos, dir = 1.0, -1 elseif pos <= 0.0 then pos, dir = 0.0, 1 end

            -- Bar, sweet spot, marker.
            DrawRect(barX, barY, barW + 0.006, barH + 0.01, 0, 0, 0, 170)
            DrawRect(barX, barY, barW, barH, 60, 60, 60, 220)
            local zx = barX - barW / 2 + (zoneStart + zoneW / 2) * barW
            DrawRect(zx, barY, zoneW * barW, barH, 90, 190, 110, 230)
            DrawRect(barX - barW / 2 + pos * barW, barY, 0.003, barH + 0.012, 255, 255, 255, 255)
            text(barX, barY - 0.05, 0.38, L('lockpick.hud', { pin = pin, pins = pins, misses = misses, max = LP.misses or 2 }))

            DisableControlAction(0, 38, true)
            if IsDisabledControlJustPressed(0, 38) then
                if pos >= zoneStart and pos <= zoneStart + zoneW then
                    set = true
                    PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
                else
                    misses = misses + 1
                    PlaySoundFrontend(-1, 'Hack_Failed', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
                    noise(ped)
                    if misses > (LP.misses or 2) then return false end
                end
            end
        end
    end

    return true
end

function Keys.Hotwire(vehicle)
    if working then return end
    local plate = Veh.Plate(vehicle)
    if not plate then return end

    local start = BSB.Await('vehicles:lockpickStart', 8000, plate)
    if not start or not start.ok then
        return notify('warn', (start and start.error) or L('keys.wont_give'))
    end
    if start.unlocked then return notify('success', L('common.unlocked')) end

    working = true
    local ped = PlayerPedId()
    local dict = 'veh@break_in@0h@p_m_one@'
    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'low_force_entry_ds', 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end

    local result = minigame(vehicle, start.level or 0)
    ClearPedTasks(ped)
    working = false

    if result == nil then return notify('warn', L('common.stopped')) end

    local answer = BSB.Await('vehicles:hotwire', 8000, plate, start.token, result == true)
    if answer and answer.ok then
        notify('success', L('keys.gives_free'), 3500)
    else
        notify('warn', (answer and answer.error) or L('keys.wont_give'), 3000)
    end
end
