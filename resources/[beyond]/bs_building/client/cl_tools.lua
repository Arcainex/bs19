-- bs_building actions from the interaction dot: deposit, hammer, doors, code locks, utilities, raid tools

local S = Building.Settings
local P = Building.Pieces
local notify = function(k, m) TriggerEvent('bs:ui:notify', { type = k, message = m, duration = 4500 }) end
local busy = false

local function idOf(payload) return payload and payload.args and payload.args.id end
local function say(res, okKey, vars)
    if res and res.ok then if okKey then notify('success', L(okKey, vars)) end
    else notify('warn', (res and res.error) or L('build.err.failed')) end
end

local function loadDict(d)
    RequestAnimDict(d)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(d)
end

-- Hammer work: anim, knock sound, dust, progress bar. Returns true if not cancelled.
local function work(labelKey, ms, entity)
    local ped = PlayerPedId()
    local dict, clip = 'amb@world_human_hammering@male@base', 'base'
    if loadDict(dict) then TaskPlayAnim(ped, dict, clip, 3.0, 3.0, ms, 1, 0, false, false, false) end
    local running = true
    CreateThread(function()
        RequestNamedPtfxAsset('core')
        local t = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < t do Wait(0) end
        while running do
            SendNUIMessage({ action = 'sound', name = 'hammer', volume = 0.55 })
            local c = (entity and DoesEntityExist(entity)) and GetEntityCoords(entity) or GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, 0.0)
            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedAtCoord('ent_dst_rocks', c.x, c.y, c.z + 0.4, 0.0, 0.0, 0.0, 0.6, false, false, false)
            Wait(850)
        end
    end)
    local done = exports.bs_interactions:RunSearch(L(labelKey), ms, { pose = 'none' })
    running = false
    ClearPedTasks(ped)
    return done
end

local function askCode()
    local p = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'keypad' })
    Building._codeCb = function(code) p:resolve(code) end
    local code = Citizen.Await(p)
    SetNuiFocus(false, false)
    return code
end
RegisterNUICallback('keypad', function(data, cb)
    cb({ ok = true })
    local f = Building._codeCb; Building._codeCb = nil
    if f then f(data and data.code or false) end
end)

local function act(fn)
    return function(payload)
        local id = idOf(payload)
        if not id or busy then return end
        busy = true
        CreateThread(function()
            local ok, e = pcall(fn, id, World.pieces[id])
            if not ok then print('^1[bs_building]^7 ' .. tostring(e)) end
            busy = false
        end)
    end
end

AddEventHandler('bs:building:act:deposit', act(function(id)
    local res = BSB.Await('build:deposit', 6000, id)
    say(res, 'build.deposited', { n = res and res.moved or 0 })
    if res and res.ok and res.missing then Building.Notify('warn', res.missing) end
end))

AddEventHandler('bs:building:act:hammer', act(function(id, r)
    local res = BSB.Await('build:hammerStart', 6000, id)
    if not res or not res.ok then return say(res) end
    if not work(r and r.b and 'build.repairing' or 'build.building', res.duration, Building.EntityOf(id)) then
        return notify('warn', L('build.cancelled'))
    end
    local done = BSB.Await('build:hammerDone', 6000, id)
    say(done, done and done.built and 'build.built' or 'build.repaired')
end))

AddEventHandler('bs:building:act:demolish', act(function(id)
    if not work('build.demolishing', 3000, Building.EntityOf(id)) then return end
    local res = BSB.Await('build:demolish', 6000, id)
    say(res, 'build.demolished')
    if res and res.ok and (res.takings or 0) > 0 then notify('success', L('build.vend_collected', { amount = res.takings })) end
end))

local function withCode(cbName, id)
    local res = BSB.Await(cbName, 6000, id)
    if res and res.needCode then
        local code = askCode()
        if not code then return nil end
        res = BSB.Await(cbName, 6000, id, code)
    end
    return res
end

AddEventHandler('bs:building:act:door', act(function(id)
    local res = withCode('build:door', id)
    if res and res.ok then PlaySoundFrontend(-1, 'Door_Open', 'Long_Player_Switch_Sounds', true) elseif res then say(res) end
end))

AddEventHandler('bs:building:act:storage', act(function(id)
    local res = withCode('build:storage', id)
    if res and not res.ok then say(res) end
end))

AddEventHandler('bs:building:act:code', act(function(id)
    local code = askCode()
    if code == false or code == nil then return end
    say(BSB.Await('build:setCode', 6000, id, code), code == '' and 'build.lock_none' or 'build.code_set')
end))
AddEventHandler('bs:building:act:lockFaction', act(function(id)
    say(BSB.Await('build:setLock', 6000, id, 'faction'), 'build.lock_faction')
end))
AddEventHandler('bs:building:act:lockNone', act(function(id)
    say(BSB.Await('build:setLock', 6000, id, 'none'), 'build.lock_none')
end))

AddEventHandler('bs:building:act:fuel', act(function(id)
    local res = BSB.Await('build:fuel', 6000, id)
    say(res, 'build.fuelled', { fuel = res and math.floor(res.fuel or 0) or 0 })
end))
AddEventHandler('bs:building:act:power', act(function(id)
    local res = BSB.Await('build:power', 6000, id)
    say(res, res and res.on and 'build.power_on' or 'build.power_off')
end))
AddEventHandler('bs:building:act:water', act(function(id)
    local res = BSB.Await('build:water', 6000, id)
    say(res, 'build.water_taken', { n = res and res.bottles or 0 })
end))
AddEventHandler('bs:building:act:bed', act(function(id)
    say(BSB.Await('build:claimBed', 6000, id), 'build.bed_set')
end))

AddEventHandler('bs:building:act:inspect', act(function(id)
    local res = BSB.Await('build:info', 6000, id)
    if not res or not res.ok then return end
    SendNUIMessage({ action = 'inspect', piece = res.piece, label = L('piece.' .. res.piece.p), water = res.water,
                     costs = P[res.piece.p] and P[res.piece.p].cost or {} })
end))

local function raid(tool, labelKey)
    return act(function(id)
        local res = BSB.Await('build:raidStart', 6000, id, tool)
        if not res or not res.ok then return say(res) end
        local ped = PlayerPedId()
        local dict = tool == 'grinder' and 'anim@heists@fleeca_bank@drilling' or 'melee@large_wpn@streamed_core'
        local clip = tool == 'grinder' and 'drill_straight_idle' or 'ground_attack_on_spot'
        if loadDict(dict) then TaskPlayAnim(ped, dict, clip, 3.0, 3.0, res.duration, 1, 0, false, false, false) end
        local done = exports.bs_interactions:RunSearch(L(labelKey), res.duration, { pose = 'none' })
        ClearPedTasks(ped)
        if not done then return end
        say(BSB.Await('build:raidDone', 6000, id), tool == 'grinder' and 'build.lock_cut' or nil)
    end)
end
AddEventHandler('bs:building:act:sledge', raid('sledge', 'build.smashing'))
AddEventHandler('bs:building:act:grind', raid('grinder', 'build.grinding'))
