-- bs_jobs client: stations, the active contract (blips, points, turn-ins), hands up relay and Y/N prompts.

JC = JC or { job = nil, stations = {}, active = nil }

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 5000 }) end
JC.Notify = notify

-- Plays an animation (scenario or dict/clip, first that loads), runs the progress bar, then stops it.
function JC.Timed(label, ms, anims, pose)
    local ped = PlayerPedId()
    local playing = false
    for _, a in ipairs(anims or {}) do
        if a.scenario then
            TaskStartScenarioInPlace(ped, a.scenario, 0, true)
            playing = true
            break
        elseif a.dict and DoesAnimDictExist(a.dict) then
            RequestAnimDict(a.dict)
            local t = GetGameTimer()
            while not HasAnimDictLoaded(a.dict) and GetGameTimer() - t < 2000 do Wait(20) end
            if HasAnimDictLoaded(a.dict) then
                TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag or 1, 0.0, false, false, false)
                playing = true
                break
            end
        end
    end
    local done = exports.bs_interactions:RunSearch(label, ms, { pose = (playing and 'none') or pose or 'search' })
    if playing then ClearPedTasks(PlayerPedId()) end
    return done
end

-- Calls start, plays the bar for the time the server asked, then calls finish.
function JC.TimedCall(startName, finishName, label, anims, pose, ...)
    local r = BSB.Await(startName, 8000, ...)
    if not r or not r.ok then notify('error', (r and r.error) or L('err.failed')); return nil end
    if not JC.Timed(label, r.ms or 3000, anims, pose) then notify('warn', L('err.interrupted')); return nil end
    local f = BSB.Await(finishName, 8000)
    if not f or not f.ok then notify('error', (f and f.error) or L('err.failed')); return nil end
    return f
end

JC.Anim = {
    repair   = { { dict = 'mini@repair', clip = 'fixing_a_player' }, { scenario = 'PROP_HUMAN_BUM_BIN' } },
    weld     = { { scenario = 'WORLD_HUMAN_WELDING' }, { dict = 'mini@repair', clip = 'fixing_a_player' } },
    bench    = { { dict = 'anim@amb@machinery@weapon_machinery@', clip = 'operate_02_hi_amy_skater_01' }, { dict = 'mini@repair', clip = 'fixing_a_player' } },
    fish     = { { scenario = 'WORLD_HUMAN_STAND_FISHING' } },
}

--------------------------------------------------------------------------------
-- Stations
--------------------------------------------------------------------------------

local blips, zones = {}, {}
local BLIP = { yard = { 446, 'blip.yard' }, gunsmith = { 110, 'blip.gunsmith' }, chop = { 380, 'blip.chop' }, water = { 361, 'blip.water' } }

local function stationOptions(s)
    if s.kind == 'yard' then
        return {
            { labelKey = 'opt.garage', label = 'Mechanic garage', icon = 'wrench', event = 'bs:jobs:openGarage', filters = { playerStateTrue = 'bsJ_garage' } },
            { labelKey = 'opt.turnin', label = 'Turn in contract', icon = 'bag', event = 'bs:jobs:turnin', filters = { playerStateTrue = 'bsJob' } },
        }
    elseif s.kind == 'gunsmith' then
        return { { labelKey = 'opt.gunsmith', label = 'Gunsmith bench', icon = 'wrench', event = 'bs:jobs:openGunsmith', filters = { playerStateTrue = 'bsJ_gunsmith' } } }
    elseif s.kind == 'water' then
        return { { labelKey = 'opt.water', label = 'Purify water', icon = 'hand', event = 'bs:jobs:purify', filters = { playerStateTrue = 'bsJ_water' } },
                 { labelKey = 'opt.turnin', label = 'Turn in contract', icon = 'bag', event = 'bs:jobs:turnin', filters = { playerStateTrue = 'bsJob' } } }
    elseif s.kind == 'chop' then
        return { { labelKey = 'opt.chop', label = 'Chop the car', icon = 'wrench', event = 'bs:jobs:chop', filters = { playerStateTrue = 'bsJ_chop' } } }
    end
    return {}
end

local function clearStations()
    for _, b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    for id in pairs(zones) do pcall(function() exports.bs_interactions:RemoveZone('bsjob:' .. id) end) end
    blips, zones = {}, {}
end

local function setStations(list)
    clearStations()
    JC.stations = type(list) == 'table' and list or {}
    for _, s in ipairs(JC.stations) do
        local pos = vector3(s.x, s.y, s.z)
        local b = BLIP[s.kind]
        if b then
            local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
            SetBlipSprite(blip, b[1]); SetBlipScale(blip, 0.7); SetBlipColour(blip, 47); SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L(b[2])); EndTextCommandSetBlipName(blip)
            blips[s.id] = blip
        end
        exports.bs_interactions:AddZone('bsjob:' .. s.id, pos + vector3(0.0, 0.0, 1.0), 2.5, stationOptions(s))
        zones[s.id] = true
    end
end

RegisterNetEvent('bs:jobs:stations', setStations)
RegisterNetEvent('bs:jobs:self', function(d) JC.job = type(d) == 'table' and d.job or nil end)

-- Markers so people find the spot (positions are approximate).
CreateThread(function()
    while true do
        local sleep = 1000
        local at = GetEntityCoords(PlayerPedId())
        for _, s in ipairs(JC.stations) do
            local d = #(at - vector3(s.x, s.y, s.z))
            if d < 25.0 then
                sleep = 0
                DrawMarker(27, s.x, s.y, s.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 1.6, 1.0, 224, 140, 70, 120, false, false, 2, false, nil, nil, false)
            end
        end
        Wait(sleep)
    end
end)

--------------------------------------------------------------------------------
-- Active contract
--------------------------------------------------------------------------------

local cblips = {}
local function clearContractBlips()
    for _, b in ipairs(cblips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    cblips = {}
end

local function nextIndex(a)
    if not a or not a.points then return nil end
    if a.kind == 'route' then return (a.progress or 0) + 1 end
    if a.kind == 'supply' then return (a.progress or 0) < 1 and 1 or nil end
    return 1
end

local function drawContract(a)
    clearContractBlips()
    if not a or not a.points then return end
    local idx = nextIndex(a)
    local p = idx and a.points[idx]
    if not p then
        -- supply crate in hand: route home to the nearest station
        local best, bd
        local at = GetEntityCoords(PlayerPedId())
        for _, s in ipairs(JC.stations) do
            local d = #(at - vector3(s.x, s.y, s.z))
            if s.kind == 'yard' and (not bd or d < bd) then best, bd = s, d end
        end
        if best then SetNewWaypoint(best.x, best.y) end
        return
    end
    if a.kind == 'nest' then
        local r = AddBlipForRadius(p.x, p.y, p.z, 80.0)
        SetBlipColour(r, 1); SetBlipAlpha(r, 90)
        cblips[#cblips + 1] = r
    end
    local b = AddBlipForCoord(p.x, p.y, p.z)
    SetBlipSprite(b, a.kind == 'nest' and 303 or (a.kind == 'smuggle' and 501 or 1)); SetBlipColour(b, 47); SetBlipRoute(b, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(a.label or 'Contract'); EndTextCommandSetBlipName(b)
    cblips[#cblips + 1] = b
end

RegisterNetEvent('bs:jobs:active', function(a)
    JC.active = type(a) == 'table' and a or nil
    drawContract(JC.active)
end)

local function help(text)
    BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayHelp(0, false, false, -1)
end

local busy = false
local function reach(a, idx)
    if busy then return end
    busy = true
    CreateThread(function()
        local r = BSB.Await('jobs:reachStart', 8000, a.id, idx)
        if r and r.ok then
            local ok = true
            if (r.ms or 0) > 0 then
                local anim = a.kind == 'service' and JC.Anim.weld or nil
                ok = JC.Timed(L('prog.' .. a.kind), r.ms, anim, 'kneel')
            end
            if ok then
                local f = BSB.Await('jobs:reach', 8000, a.id, idx)
                if not f or not f.ok then notify('error', (f and f.error) or L('err.failed')) end
            end
        elseif r and r.error then
            notify('error', r.error)
        end
        Wait(1500)
        busy = false
    end)
end

-- Walk/drive to the next point. Routes count on arrival; the rest need E.
CreateThread(function()
    while true do
        local a = JC.active
        local sleep = 1000
        if a and a.points then
            local idx = nextIndex(a)
            local p = idx and a.points[idx]
            if p then
                local d = #(GetEntityCoords(PlayerPedId()).xy - vector2(p.x, p.y))
                if d < 60.0 then sleep = 0 end
                if a.kind == 'route' and d < 12.0 then
                    reach(a, idx)
                elseif (a.kind == 'supply' or a.kind == 'service' or a.kind == 'smuggle') and d < 10.0 then
                    help(L('help.' .. a.kind))
                    if IsControlJustPressed(0, 38) then reach(a, idx) end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('bs:jobs:turnin', function()
    local a = JC.active
    if not a then return notify('warn', L('err.no_contract')) end
    CreateThread(function()
        local r = BSB.Await('jobs:turnin', 8000, { id = a.id })
        if not r or not r.ok then notify('error', (r and r.error) or L('err.failed')) end
    end)
end)

--------------------------------------------------------------------------------
-- Hands up goes to the server (robbery and zip ties check it)
--------------------------------------------------------------------------------

AddEventHandler('bs:emotes:handsUp', function(on) TriggerServerEvent('bs:jobs:handsUp', on == true) end)

--------------------------------------------------------------------------------
-- Y / N prompts (mechanic bills)
--------------------------------------------------------------------------------

local prompt = nil
RegisterNetEvent('bs:jobs:prompt', function(p)
    if type(p) ~= 'table' then return end
    prompt = { kind = p.kind, until_ = GetGameTimer() + 25000 }
    notify('info', ('%s  [Y] / [N]'):format(p.text or ''))
end)
local function answer(yes)
    if not prompt or GetGameTimer() > prompt.until_ then prompt = nil; return end
    TriggerServerEvent('bs:jobs:answer', prompt.kind, yes)
    prompt = nil
end
RegisterCommand('bsjobs_yes', function() answer(true) end, false)
RegisterCommand('bsjobs_no', function() answer(false) end, false)
RegisterKeyMapping('bsjobs_yes', L('jobs.key_yes'), 'keyboard', 'Y')
RegisterKeyMapping('bsjobs_no', L('jobs.key_no'), 'keyboard', 'N')

-- Smuggler spotted: a short-lived area blip.
RegisterNetEvent('bs:jobs:smugglePing', function(p)
    if type(p) ~= 'table' then return end
    local b = AddBlipForRadius(p.x + 0.0, p.y + 0.0, (p.z or 0.0) + 0.0, 120.0)
    SetBlipColour(b, 1); SetBlipAlpha(b, 110)
    notify('warn', L('n.smuggler_spotted'))
    SetTimeout(30000, function() if DoesBlipExist(b) then RemoveBlip(b) end end)
end)

-- First sync once the character is in.
CreateThread(function()
    while GetResourceState('bs_core') ~= 'started' or not exports.bs_core:IsLoaded() do Wait(1000) end
    Wait(2000)
    local r = BSB.Await('jobs:stations', 8000)
    if r and r.ok then setStations(r.list) end
    BSB.Await('jobs:active', 8000)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearStations(); clearContractBlips()
end)
