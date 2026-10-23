-- bs_vehicles - stripping a car as a run of skill checks (html/scrap.*)

Scrap = {}

local KEY_USE, KEY_BACK = 38, 177
local KEYS = { 'title', 'tool', 'no_tool', 'skill', 'time', 'hint_timing', 'hint_hold', 'cancel',
               'perfect', 'good', 'miss', 'salvaged', 'ruined', 'pending',
               'part_doors', 'part_hood', 'part_trunk', 'part_wheels', 'part_engine', 'part_battery',
               'part_seats', 'part_exhaust', 'part_tank' }

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 3000 })
end

local function texts()
    local out = {}
    for _, k in ipairs(KEYS) do out[k] = L('scrap.' .. k) end
    return out
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 1500 do Wait(10); t = t + 10 end
    return HasAnimDictLoaded(dict)
end

local function blockControls()
    DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
    DisableControlAction(0, 140, true); DisableControlAction(0, 141, true); DisableControlAction(0, 142, true)
    DisableControlAction(0, 257, true); DisableControlAction(0, 263, true)
    DisableControlAction(0, 200, true)
end

-- Runs one check
local function runCheck(ch, deadline, vehicle)
    local start = GetGameTimer()
    local holdFrom
    local period = ch.period
    local maxWait = ch.mode == 'hold' and 8000 or period * ch.laps
    SendNUIMessage({ action = 'scrapCheck', challenge = ch })

    while true do
        Wait(0)
        blockControls()
        local now = GetGameTimer()
        local ped = PlayerPedId()

        if IsControlJustPressed(0, KEY_BACK) or IsDisabledControlJustPressed(0, KEY_BACK) then return nil end
        if IsEntityDead(ped) or not DoesEntityExist(vehicle)
            or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Vehicles.Settings.scrapRange or 4.0) + 3.0 then
            return nil
        end

        local left = math.max(0, deadline - now)
        if ch.mode == 'hold' then
            if not holdFrom then
                SendNUIMessage({ action = 'scrapPos', pos = 0.0, left = left })
                if IsControlJustPressed(0, KEY_USE) then holdFrom = now end
                if now - start > maxWait then return -1 end
            else
                local held = now - holdFrom
                SendNUIMessage({ action = 'scrapPos', pos = math.min(1.0, held / period), left = left })
                if not IsControlPressed(0, KEY_USE) then return held end
                if held > period * 1.25 then return -1 end
            end
        else
            local t = now - start
            local x = (t / period) % 2
            local pos = x <= 1 and x or 2 - x
            SendNUIMessage({ action = 'scrapPos', pos = pos, left = left })
            if IsControlJustPressed(0, KEY_USE) then return t end
            if t > maxWait then return -1 end
        end
        if left <= 0 then return -1 end
    end
end

function Scrap.Run(vehicle)
    local plate = Veh.Plate(vehicle)
    local begin = BSB.Await('vehicles:scrapBegin', 10000, plate)
    if not begin or not begin.ok then
        return notify('warn', (begin and begin.error) or L('search.nothing_worth'))
    end

    local ped = PlayerPedId()
    if loadDict('mini@repair') then
        TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, -1, 1, 0.0, false, false, false)
    end

    SendNUIMessage({
        action = 'scrapShow', text = texts(), parts = begin.parts, skill = begin.skill,
        tool = begin.tool and Veh.ItemLabel(begin.tool) or nil, total = begin.total,
    })

    local deadline = GetGameTimer() + begin.total
    local challenge = begin.challenge
    local final, aborted

    while challenge do
        local t = runCheck(challenge, deadline, vehicle)
        if t == nil then aborted = true; break end
        local res = BSB.Await('vehicles:scrapStep', 8000, challenge.index, t)
        if not res or not res.ok then
            aborted = true
            notify('warn', (res and res.error) or L('search.nothing_worth'))
            break
        end
        SendNUIMessage({ action = 'scrapResult', index = challenge.index, outcome = res.outcome, salvaged = res.salvaged })
        if res.done then final = res; break end
        Wait(450)
        challenge = res.challenge
    end

    ClearPedTasks(ped)
    SendNUIMessage({ action = 'scrapHide' })

    if aborted then
        BSB.Await('vehicles:scrapCancel', 4000)
        return notify('info', L('scrap.cancelled'))
    end
    if not final then return end

    local list = {}
    for _, entry in ipairs(final.yield or {}) do
        list[#list + 1] = ('%dx %s'):format(entry.amount, Veh.ItemLabel(entry.item))
    end
    local msg = #list > 0 and table.concat(list, ', ') or L('radial.nothing_usable')
    if final.timeout then msg = L('scrap.timeout') .. ' ' .. msg end
    notify('success', msg, 6000)

    -- The wreck stays, stripped but not deleted, for three days (see cl_strip.lua).
    if DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        Strip.Apply(vehicle)
    end
end
