-- bs_building actions from the interaction dot: deposit, hammer, upgrade, doors, code locks, power, raid tools

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

-- A prop in the right hand for the length of a job
local function holdProp(model, x, y, z, rx, ry, rz)
    local hash = GetHashKey(model)
    if not Building.LoadModel(hash) then return nil end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 57005), x, y, z, rx, ry, rz, true, true, false, true, 1, true)
    return obj
end

-- Hammer work: hammer in hand, swing, knock sound, dust, progress bar. quick = no bar (after an instant place).
-- Returns true if not cancelled.
function Building.HammerWork(labelKey, ms, entity, quick)
    local ped = PlayerPedId()
    -- holster whatever is in hand so the hammer prop is the only thing held
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    local hammer = holdProp('prop_tool_hammer', 0.10, 0.02, -0.02, -80.0, 0.0, 0.0)
    local dict, clip = 'amb@world_human_hammering@male@base', 'base'
    if loadDict(dict) then TaskPlayAnim(ped, dict, clip, 3.0, 3.0, ms, 1, 0, false, false, false) end
    local running = true
    CreateThread(function()
        RequestNamedPtfxAsset('core')
        local t = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < t do Wait(0) end
        Wait(250)
        while running do
            SendNUIMessage({ action = 'sound', name = 'hammer', volume = 0.55 })
            local c = (entity and DoesEntityExist(entity)) and GetEntityCoords(entity) or GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, 0.0)
            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedAtCoord('ent_dst_rocks', c.x, c.y, c.z + 0.4, 0.0, 0.0, 0.0, 0.6, false, false, false)
            Wait(850)
        end
    end)
    local done
    if quick then
        Wait(ms)
        done = true
    else
        done = exports.bs_interactions:RunSearch(L(labelKey), ms, { pose = 'none' })
    end
    running = false
    StopAnimTask(ped, dict, clip, 2.0)
    if hammer and DoesEntityExist(hammer) then DetachEntity(hammer, true, false); DeleteEntity(hammer) end
    return done
end
local work = function(labelKey, ms, entity) return Building.HammerWork(labelKey, ms, entity) end

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

-- Upgrade: shows the next tier and its cost first, the second press within 6 s does it
local confirmUp = {}
AddEventHandler('bs:building:act:upgrade', act(function(id)
    local info = BSB.Await('build:upgradeInfo', 6000, id)
    if not info or not info.ok then return say(info) end
    if not confirmUp[id] or GetGameTimer() > confirmUp[id] then
        confirmUp[id] = GetGameTimer() + 6000
        local parts = {}
        for _, c in ipairs(info.costs or {}) do parts[#parts + 1] = ('%s %d/%d'):format(c.label, c.have, c.need) end
        notify('info', L('build.upgrade_ask', { name = info.label, tier = info.tierLabel, cost = info.free and L('ui.free_build') or table.concat(parts, ', ') }))
        return
    end
    confirmUp[id] = nil
    local res = BSB.Await('build:upgradeStart', 6000, id)
    if not res or not res.ok then return say(res) end
    if not work('build.upgrading', res.duration, Building.EntityOf(id)) then return notify('warn', L('build.cancelled')) end
    local done = BSB.Await('build:hammerDone', 6000, id)
    if done and done.ok then
        PlaySoundFrontend(-1, 'PROPERTY_PURCHASE', 'HUD_AWARDS', true)
        notify('success', L('build.upgraded', { name = done.label or '' }))
    else say(done) end
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
    SendNUIMessage({ action = 'inspect', piece = res.piece, label = res.label or L('piece.' .. res.piece.p), tierLabel = res.tierLabel,
                     water = res.water, costs = res.costs or {}, power = res.power })
end))

-- Power: lights, generator panel, refuel, wires

AddEventHandler('bs:building:act:light', act(function(id)
    local res = BSB.Await('build:light', 6000, id)
    if not res or not res.ok then return say(res) end
    PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    if res.lit and not res.pw then notify('warn', L('build.light_no_power'))
    else notify('success', L(res.lit and 'build.light_on' or 'build.light_off')) end
end))

local genOpen = nil
local function genClose()
    if not genOpen then return end
    genOpen = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'genClose' })
end

local function genShow(res)
    if not res or not res.ok then return say(res) end
    genOpen = res.id
    TriggerEvent('bs:ui:opened', 'building_gen')
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'gen', data = res })
end
AddEventHandler('bs:ui:opened', function(what) if what ~= 'building_gen' then genClose() end end)

AddEventHandler('bs:building:act:generator', act(function(id)
    genShow(BSB.Await('build:gen:open', 6000, id))
end))

RegisterNUICallback('genAct', function(data, cb)
    if not genOpen then return cb({ ok = false }) end
    local id = genOpen
    CreateThread(function()
        local res = BSB.Await('build:gen:act', 6000, id, data and data.action, data and data.slot)
        if res and res.ok and data.action == 'toggle' then PlaySoundFrontend(-1, res.on and 'Hack_Success' or 'Hack_Failed', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true) end
        cb(res or { ok = false })
    end)
end)
RegisterNUICallback('genClose', function(_, cb) genClose(); cb({ ok = true }) end)

-- Refuel: jerrycan in hand, pour animation, and a small pour game (stop the needle in the green, four pours)
local function pourGame()
    local p = promise.new()
    Building._pourCb = function(score) p:resolve(score) end
    SetNuiFocus(true, false)
    SendNUIMessage({ action = 'pour', rounds = 4 })
    local score = Citizen.Await(p)
    SetNuiFocus(false, false)
    return score
end
RegisterNUICallback('pourDone', function(data, cb)
    cb({ ok = true })
    local f = Building._pourCb; Building._pourCb = nil
    if f then f(tonumber(data and data.score) or 0) end
end)

local function refuel(id)
    local start = BSB.Await('build:gen:refuelStart', 6000, id)
    if not start or not start.ok then return say(start) end
    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    local e = Building.EntityOf(id)
    if e and DoesEntityExist(e) then TaskTurnPedToFaceEntity(ped, e, 800); Wait(800) end
    local can = holdProp('w_am_jerrycan', 0.18, 0.0, -0.05, 0.0, -90.0, 0.0)
    local dict, clip = 'weapon@w_sp_jerrycan', 'fire'
    if loadDict(dict) then TaskPlayAnim(ped, dict, clip, 2.0, 2.0, -1, 49, 0, false, false, false) end
    local t0 = GetGameTimer()
    local score = pourGame()
    -- the server wants the pour to take a moment
    local left = 3600 - (GetGameTimer() - t0)
    if left > 0 then Wait(left) end
    StopAnimTask(ped, dict, clip, 2.0)
    if can and DoesEntityExist(can) then DetachEntity(can, true, false); DeleteEntity(can) end
    local res = BSB.Await('build:gen:refuelDone', 6000, id, score)
    if res and res.ok then
        if (res.spilled or 0) > 0 then notify('warn', L('build.fuel_spilled', { added = res.added, spilled = res.spilled, fuel = res.fuel }))
        else notify('success', L('build.fuelled', { fuel = res.fuel })) end
    else say(res) end
    return res
end

AddEventHandler('bs:building:act:fuel', act(function(id) refuel(id) end))
RegisterNUICallback('genRefuel', function(_, cb)
    cb({ ok = true })
    local id = genOpen
    genClose()
    if id and not busy then
        busy = true
        CreateThread(function()
            pcall(refuel, id)
            busy = false
            genShow(BSB.Await('build:gen:open', 6000, id))
        end)
    end
end)

-- Wire mode: pick the other end with the crosshair, the cable follows your aim until you click
local function nodeAtCrosshair()
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    local to = cam + dir * 60.0
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 | 16, PlayerPedId(), 4)
    local _, hit, at, _, ent = GetShapeTestResult(h)
    local r = hit == 1 and ent ~= 0 and Building.PieceOfEntity(ent) or nil
    return r, hit == 1 and at or to
end

AddEventHandler('bs:building:act:wire', act(function(id)
    local from = World.pieces[id]
    if not from then return end
    notify('info', L('build.wire_help', { max = math.floor((World.cfg and World.cfg.wireMax) or S.wireMaxLength) }))
    local deadline = GetGameTimer() + 60000
    while GetGameTimer() < deadline do
        Wait(0)
        DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 140, true)
        local target, at = nodeAtCrosshair()
        local p1 = Building.WirePoint(from)
        local good = target and target.id ~= from.id and P[target.p] and (P[target.p].node or P[target.p].generator)
        local p2 = good and Building.WirePoint(target) or at
        local far = #(p2 - p1) > ((World.cfg and World.cfg.wireMax) or S.wireMaxLength)
        local cr, cg = (good and not far) and 90 or 230, (good and not far) and 230 or 80
        DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, cr, cg, 80, 255)
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(L('build.wire_hint', { m = math.floor(#(p2 - p1)) }))
        EndTextCommandDisplayHelp(0, false, false, -1)
        if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then notify('info', L('build.cancelled')) return end
        if IsDisabledControlJustPressed(0, 24) then
            if not good then notify('warn', L('build.err.wire_bad'))
            else
                local res = BSB.Await('build:wire', 6000, from.id, target.id)
                if res and res.ok then
                    PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
                    notify('success', L('build.wired', { n = res.used or 1 }))
                    return
                end
                say(res)
            end
        end
    end
end))

AddEventHandler('bs:building:act:unwire', act(function(id)
    local res = BSB.Await('build:unwire', 6000, id)
    say(res, 'build.unwired', { n = res and res.n or 0, back = res and res.back or 0 })
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

-- Walked away from the generator panel
CreateThread(function()
    while true do
        Wait(1000)
        if genOpen then
            local e = Building.EntityOf(genOpen)
            if not e or not DoesEntityExist(e) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(e)) > 5.0 then genClose() end
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and genOpen then SetNuiFocus(false, false) end
end)
