-- bs_vehicles - fuel pumps, client side

local function Pc() return Vehicles.Pumps or {} end
local function J() return Pc().jump or {} end

local busy = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 3000 })
end

-- Panel (html/pump.html)

local panelAt = 0
local function panel(data, force)
    local now = GetGameTimer()
    if not force and now - panelAt < 33 then return end
    panelAt = now
    data.action = 'pump'
    SendNUIMessage(data)
end

local function panelHide() SendNUIMessage({ action = 'pumpHide' }) end

local function strings()
    local keys = { 'title', 'volts', 'clamps', 'red', 'black', 'battery', 'cap', 'station', 'liters', 'zone',
                   'rain', 'pump', 'skill', 'powered', 'grid', 'progress', 'off', 'crank' }
    local out = {}
    for _, k in ipairs(keys) do out[k] = L('pj.ui_' .. k) end
    return out
end

-- Small helpers

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 1500 do Wait(10); t = t + 10 end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    model = type(model) == 'string' and joaat(model) or model
    if HasModelLoaded(model) then return model end
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 2000 do Wait(10); t = t + 10 end
    return HasModelLoaded(model) and model or nil
end

local function loadRopes()
    if RopeAreTexturesLoaded() then return end
    RopeLoadTextures()
    local t = 0
    while not RopeAreTexturesLoaded() and t < 2000 do Wait(10); t = t + 10 end
end

-- Rope kinds: 1 is the thick dark rubber look (hose), 4 the thinner insulated cable (jumper leads)
local ROPE_HOSE, ROPE_CABLE = 1, 4

-- Slack: a bit longer than the straight line so the rope sags instead of standing stiff.
local function slackLen(p1, p2, maxLen)
    local l = #(p1 - p2) * 1.18 + 0.35
    if maxLen and l > maxLen then l = maxLen end
    return math.max(l, 0.8)
end

local function makeRope(e1, p1, e2, p2, len, kind)
    len = slackLen(p1, p2, len)
    local rope = AddRope(p1.x, p1.y, p1.z, 0.0, 0.0, 0.0, len, kind or ROPE_CABLE, len, 0.25, 1.0, false, false, false, 1.0, false, 0)
    AttachEntitiesToRope(rope, e1, e2, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, len, false, false, nil, nil)
    StartRopeUnwindingFront(rope)
    StopRopeUnwindingFront(rope)
    return rope
end

-- Small clamp-like prop at a cable end, if the model exists in this build.
local CLAMPS = { 'prop_tool_pliers', 'prop_cs_pliers' }
local function clampAt(ent, pos)
    for _, m in ipairs(CLAMPS) do
        if IsModelInCdimage(joaat(m)) then
            local model = loadModel(m)
            if model then
                local o = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
                SetModelAsNoLongerNeeded(model)
                local off = GetOffsetFromEntityGivenWorldCoords(ent, pos.x, pos.y, pos.z)
                AttachEntityToEntity(o, ent, 0, off.x, off.y, off.z, 90.0, 0.0, 0.0, false, false, false, false, 2, true)
                return o
            end
        end
    end
end

local function dropRope(rope)
    if rope and DoesRopeExist(rope) then DeleteRope(rope) end
end

-- The pump prop at these coords, found by model.
local function pumpEntity(x, y, z)
    for _, m in ipairs(Pc().models or {}) do
        local obj = GetClosestObjectOfType(x, y, z, 1.5, joaat(m), false, false, false)
        if obj and obj ~= 0 then return obj end
    end
end

-- Where the cables bite on a car: the battery corner of the engine bay (engine bone, nudged up to the bonnet line)
local function engineSpot(veh)
    local bone = GetEntityBoneIndexByName(veh, 'engine')
    if bone ~= -1 then
        local e = GetWorldPositionOfEntityBone(veh, bone)
        local off = GetOffsetFromEntityGivenWorldCoords(veh, e.x, e.y, e.z)
        return GetOffsetFromEntityInWorldCoords(veh, off.x + 0.25, off.y + 0.1, off.z + 0.22)
    end
    return GetOffsetFromEntityInWorldCoords(veh, 0.25, 1.8, 0.45)
end

-- The filler cap: petrolcap/petroltank bones if the model has them, else the rear wheel side.
local function fuelCapSpot(veh)
    for _, name in ipairs({ 'petrolcap', 'petroltank', 'petroltank_l', 'petroltank_r' }) do
        local bone = GetEntityBoneIndexByName(veh, name)
        if bone ~= -1 then return GetWorldPositionOfEntityBone(veh, bone) end
    end
    local bone = GetEntityBoneIndexByName(veh, 'wheel_lr')
    if bone ~= -1 then return GetWorldPositionOfEntityBone(veh, bone) + vector3(0.0, 0.0, 0.5) end
    return GetOffsetFromEntityInWorldCoords(veh, -1.0, -1.2, 0.4)
end

local function nearestCar(coords, range)
    local veh = GetClosestVehicle(coords.x, coords.y, coords.z, range, 0, 71)
    if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
end

-- Cables everyone can see: the server sends the live sessions, each client draws the ones near it

local sessions = {}   -- list from the server
local drawn = {}      -- [id] = { ropes = {}, prop = obj }

local function undraw(id)
    local d = drawn[id]
    if not d then return end
    for _, r in ipairs(d.ropes) do dropRope(r) end
    if d.prop and DoesEntityExist(d.prop) then DeleteObject(d.prop) end
    for _, o in ipairs(d.clamps or {}) do if DoesEntityExist(o) then DeleteObject(o) end end
    drawn[id] = nil
end

local function draw(s)
    local pump = pumpEntity(s.x, s.y, s.z)
    if not pump then return end
    loadRopes()
    local top = GetOffsetFromEntityInWorldCoords(pump, 0.0, 0.0, 1.1)
    local d = { ropes = {}, clamps = {} }
    local len = (J().cableLength or 6.0) + 1.0
    -- the leads leave the pump on its side, one above the other (red over black)
    local red, black = GetOffsetFromEntityInWorldCoords(pump, 0.32, 0.0, 1.05), GetOffsetFromEntityInWorldCoords(pump, 0.32, 0.0, 0.92)

    if s.kind == 'car' then
        local veh = s.netId and NetworkDoesNetworkIdExist(s.netId) and NetToVeh(s.netId) or 0
        if veh == 0 or not DoesEntityExist(veh) then return end
        SetVehicleDoorOpen(veh, 4, false, false)   -- bonnet up while clamped on
        local spot = engineSpot(veh)
        local pos, neg = spot + vector3(0.0, 0.0, 0.0), GetOffsetFromEntityGivenWorldCoords(veh, spot.x, spot.y, spot.z)
        neg = GetOffsetFromEntityInWorldCoords(veh, neg.x - 0.22, neg.y, neg.z)
        d.ropes[1] = makeRope(pump, red, veh, pos, len, ROPE_CABLE)
        d.ropes[2] = makeRope(pump, black, veh, neg, len, ROPE_CABLE)
        d.clamps[1], d.clamps[2] = clampAt(veh, pos), clampAt(veh, neg)
    else
        local model = loadModel('prop_car_battery_01')
        if not model then return end
        local at = GetOffsetFromEntityInWorldCoords(pump, 0.0, -0.9, 0.0)
        d.prop = CreateObject(model, at.x, at.y, at.z, false, false, false)
        PlaceObjectOnGroundProperly(d.prop)
        FreezeEntityPosition(d.prop, true)
        SetModelAsNoLongerNeeded(model)
        local b = GetEntityCoords(d.prop) + vector3(0.0, 0.0, 0.2)
        d.ropes[1] = makeRope(pump, red, d.prop, b + vector3(0.08, 0.0, 0.0), 2.5, ROPE_CABLE)
        d.ropes[2] = makeRope(pump, black, d.prop, b - vector3(0.08, 0.0, 0.0), 2.5, ROPE_CABLE)
        d.clamps[1], d.clamps[2] = clampAt(d.prop, b + vector3(0.08, 0.0, 0.0)), clampAt(d.prop, b - vector3(0.08, 0.0, 0.0))
    end
    drawn[s.id] = d
end

RegisterNetEvent('bs:vehicles:jump:sessions', function(list)
    sessions = type(list) == 'table' and list or {}
    local live = {}
    for _, s in ipairs(sessions) do live[s.id] = true end
    for id in pairs(drawn) do if not live[id] then undraw(id) end end
end)

RegisterNetEvent('bs:vehicles:jump:ended', function(id, x, y, z)
    undraw(id)
    -- A spark where the clamps came off.
    if x and #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) < 60.0 then
        RequestNamedPtfxAsset('core')
        local t = 0
        while not HasNamedPtfxAssetLoaded('core') and t < 1000 do Wait(10); t = t + 10 end
        UseParticleFxAssetNextCall('core')
        StartParticleFxNonLoopedAtCoord('ent_brk_sparking_wires', x, y, z + 1.0, 0.0, 0.0, 0.0, 0.8, false, false, false)
    end
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('bs:vehicles:jump:ask')
    while true do
        Wait(750)
        local me = GetEntityCoords(PlayerPedId())
        for _, s in ipairs(sessions) do
            local near = #(me - vector3(s.x, s.y, s.z)) < 80.0
            if near and not drawn[s.id] then draw(s)
            elseif not near and drawn[s.id] then undraw(s.id) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(drawn) do undraw(id) end
    panelHide()
end)

-- Shock and battery sync

RegisterNetEvent('bs:vehicles:pump:shock', function(mode, damage)
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    RequestNamedPtfxAsset('core')
    local t = 0
    while not HasNamedPtfxAssetLoaded('core') and t < 1000 do Wait(10); t = t + 10 end
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_brk_sparking_wires', at.x, at.y, at.z + 0.6, 0.0, 0.0, 0.0, 1.2, false, false, false)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.25)
    ApplyDamageToPed(ped, math.floor(tonumber(damage) or 15), false)
    if mode == 'ragdoll' then
        SetPedToRagdoll(ped, 3500, 3500, 0, false, false, false)
    elseif loadDict('reaction@shove') then
        TaskPlayAnim(ped, 'reaction@shove', 'shoved_back', 8.0, -8.0, 1200, 0, 0.0, false, false, false)
    end
    notify('error', L(mode == 'ragdoll' and 'pj.shock_hard' or 'pj.shock'), 3500)
end)

RegisterNetEvent('bs:vehicles:battery', function(plate, charge)
    if Veh.current and Veh.current.plate == plate and Wear and Wear.Apply then
        Wear.Apply({ battery = tonumber(charge) or 0 })
    end
end)

-- Jump-starting

local function waitKey(hintKey, base)
    while true do
        Wait(0)
        base.hint = L(hintKey)
        panel(base)
        DisableControlAction(0, 38, true)
        if IsDisabledControlJustPressed(0, 38) then return true end
        if IsControlJustPressed(0, 202) or IsEntityDead(PlayerPedId()) then return false end
    end
end

local function clampAnim(ms)
    local ped = PlayerPedId()
    if loadDict('mini@repair') then
        TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, ms, 49, 0.0, false, false, false)
    end
    Wait(ms)
    ClearPedTasks(ped)
end

-- The needle game. Hold SPACE to push the voltage up, let go and it sags. Keep it in the green.
local function crank(diff, base)
    local v, held, t, over = 0.15, 0.0, 0.0, 0.0
    local center = 0.62
    local zone = diff.zone or 0.18
    local drift = diff.drift or 0.25
    local holdMs = diff.holdMs or 3500
    local windowMs = diff.windowMs or 18000

    base.stage = 'crank'
    while true do
        Wait(0)
        local dt = GetFrameTime()
        t = t + dt
        DisableControlAction(0, 22, true)
        local push = IsDisabledControlPressed(0, 22)
        local wobble = (math.sin(t * 2.3) * 0.6 + math.sin(t * 5.7) * 0.4) * drift + (math.random() - 0.5) * drift * 2.0
        v = math.max(0.0, math.min(1.0, v + ((push and 0.55 or -0.45) + wobble) * dt))

        if math.abs(v - center) <= zone / 2 then
            held = held + dt * 1000
        else
            held = math.max(0.0, held - dt * 400)
        end
        over = v >= 0.97 and over + dt or 0.0

        base.needle, base.volts = v, 9.0 + v * 6.0
        base.zone = { center = center, width = zone }
        base.progress = held / holdMs
        base.left = math.max(0, math.ceil((windowMs - t * 1000) / 1000))
        base.hint = L('pj.hint_crank')
        panel(base)

        if held >= holdMs then return true end
        if over > 0.6 then return false, 'pj.overvolt' end
        if t * 1000 >= windowMs then return false, 'pj.timeout' end
        if IsControlJustPressed(0, 202) or IsEntityDead(PlayerPedId()) then return nil end
    end
end

local function jumpFlow(coords)
    local j = J()
    local veh = nearestCar(coords, j.cableLength or 6.0)
    local plate

    if veh then
        -- Cables go on the engine battery, so the bonnet has to be up.
        if GetVehicleDoorAngleRatio(veh, 4) < 0.1 then
            NetworkRequestControlOfEntity(veh)
            SetVehicleDoorOpen(veh, 4, false, false)
            Wait(400)
        end
        if GetVehicleDoorAngleRatio(veh, 4) < 0.1 then return notify('warn', L('pj.open_bonnet'), 3500) end
        plate = Veh.Plate(veh)
    end

    local res = BSB.Await('vehicles:jumpConnect', 8000, coords.x, coords.y, coords.z, plate)
    if not res or not res.ok then return notify('warn', (res and res.error) or L('pump.cant_here'), 4000) end

    local base = { mode = 'jump', stage = 'clamps', red = false, black = false, charge = res.charge, cap = res.cap,
                   source = res.kind, text = strings(), needle = 0.0, volts = 0.0 }
    panel(base, true)

    -- Clamps: red first, then black.
    for i = 1, 2 do
        if not waitKey(i == 1 and 'pj.hint_red' or 'pj.hint_black', base) then
            BSB.Await('vehicles:jumpDisconnect', 5000)
            return panelHide()
        end
        clampAnim(res.clampMs or 1400)
        local c = BSB.Await('vehicles:jumpClamp', 5000, res.id)
        if not c or not c.ok then
            notify('warn', (c and c.error) or L('pump.dropped'))
            BSB.Await('vehicles:jumpDisconnect', 5000)
            return panelHide()
        end
        if i == 1 then base.red = true else base.black = true end
        base.diff = c.diff
        panel(base, true)
    end

    local diff = base.diff or {}
    while true do
        base.rain, base.pump, base.skill = diff.rain, diff.pump, diff.skill
        if not waitKey('pj.hint_start', base) then
            BSB.Await('vehicles:jumpDisconnect', 5000)
            return panelHide()
        end
        local ok, why = crank(diff, base)
        if ok == nil then
            BSB.Await('vehicles:jumpDisconnect', 5000)
            return panelHide()
        end
        local r = BSB.Await('vehicles:jumpCrank', 8000, res.id, ok)
        if not r or not r.ok then notify('warn', L('pump.dropped')); return panelHide() end
        base.charge, base.cap = r.charge, r.cap
        if r.success then
            base.stage, base.hint = 'powered', L('pj.hint_powered')
            panel(base, true)
            notify('success', L('pj.powered'), 4000)
            Wait(2200)
            return panelHide()
        end
        notify('warn', L(why or 'pj.failed'), 3500)
        if r.junk or r.ended then
            Wait(1500)
            return panelHide()
        end
        diff = r.diff or diff
        base.stage = 'crank'
    end
end

-- The hose: nozzle in hand, hose from the pump, hold E to pump

local function hoseFlow(coords, target)
    local state = BSB.Await('vehicles:pumpState', 8000, coords.x, coords.y, coords.z)
    if not state or not state.ok then return notify('warn', (state and state.error) or L('pump.dead')) end
    if not state.powered then return notify('warn', L('pj.dead_hint'), 4500) end

    local veh, plate
    if target == 'tank' then
        veh = nearestCar(coords, (Pc().hoseLength or 6.0) + 1.0)
        if not veh then return notify('warn', L('pump.pull_up')) end
        plate = Veh.Plate(veh)
        if not plate then return end
    end

    local ped = PlayerPedId()
    local pump = pumpEntity(coords.x, coords.y, coords.z)
    local model = loadModel('prop_cs_fuel_nozle')
    if not pump or not model then return end

    local nozzle = CreateObject(model, GetEntityCoords(ped), false, false, false)
    SetModelAsNoLongerNeeded(model)
    -- nozzle in the right hand
    local function toHand()
        DetachEntity(nozzle, true, false)
        AttachEntityToEntity(nozzle, ped, GetPedBoneIndex(ped, 18905), 0.13, 0.04, 0.01, -42.0, -115.0, -63.0, true, true, false, true, 1, true)
    end
    -- nozzle pushed into the filler neck
    local function toCar()
        local bone = -1
        for _, n in ipairs({ 'petrolcap', 'petroltank', 'petroltank_l', 'petroltank_r' }) do
            bone = GetEntityBoneIndexByName(veh, n)
            if bone ~= -1 then break end
        end
        DetachEntity(nozzle, true, false)
        if bone ~= -1 then
            AttachEntityToEntity(nozzle, veh, bone, 0.0, -0.05, 0.12, -125.0, 0.0, 90.0, true, true, false, false, 1, true)
        else
            local c = fuelCapSpot(veh)
            local off = GetOffsetFromEntityGivenWorldCoords(veh, c.x, c.y, c.z)
            AttachEntityToEntity(nozzle, veh, 0, off.x, off.y, off.z, -125.0, 0.0, 90.0, true, true, false, false, 1, true)
        end
    end
    toHand()
    loadRopes()
    -- hose leaves from the pump's nozzle holder (side of the pump), thick black rubber, hanging with slack
    local top = GetOffsetFromEntityInWorldCoords(pump, -0.32, 0.0, 1.0)
    local hose = makeRope(pump, top, nozzle, GetEntityCoords(nozzle), (Pc().hoseLength or 6.0) + 0.5, ROPE_HOSE)
    local function rehose()
        dropRope(hose)
        hose = makeRope(pump, top, nozzle, GetEntityCoords(nozzle), (Pc().hoseLength or 6.0) + 0.5, ROPE_HOSE)
    end

    local base = { mode = 'fuel', target = target, liters = 0, text = strings(), powered = state.powered,
                   station = state.station, charge = state.session and state.session.charge, cap = state.session and state.session.cap }
    local nextTick, pumping, why = 0, false, nil
    local dict = 'timetable@gardener@filling_can'
    loadDict(dict)

    while true do
        Wait(0)
        local me = GetEntityCoords(ped)
        if #(me - vector3(coords.x, coords.y, coords.z)) > (Pc().hoseLength or 6.0) + 1.0 then why = L('pj.hose_reach') break end
        if IsControlJustPressed(0, 202) or IsEntityDead(ped) then break end

        local atCap = true
        if veh then
            if not DoesEntityExist(veh) then break end
            atCap = #(me - fuelCapSpot(veh)) <= 2.2
        end

        DisableControlAction(0, 38, true)
        local hold = IsDisabledControlPressed(0, 38) and atCap
        if hold ~= pumping then
            pumping = hold
            if hold then TaskPlayAnim(ped, dict, 'gar_ig_5_filling_can', 4.0, -4.0, -1, 49, 0.0, false, false, false)
            else StopAnimTask(ped, dict, 'gar_ig_5_filling_can', 2.0) end
            -- car filling: the nozzle sits in the tank while pumping, back in hand after
            if veh then if hold then toCar() else toHand() end rehose() end
        end

        if hold and GetGameTimer() >= nextTick then
            nextTick = GetGameTimer() + (Pc().tickMs or 500)
            local r = BSB.Await('vehicles:pumpTick', 5000, coords.x, coords.y, coords.z, target, plate)
            if not r or not r.ok then
                why = (r and r.error) or L('pump.dropped')
                break
            end
            if not r.skipped then
                base.liters = base.liters + (r.moved or 0)
                base.station = r.station or base.station
                base.powered = r.powered or base.powered
                if r.charge then base.charge, base.cap = r.charge, r.cap end
                if r.fuel then base.tank = r.fuel end
                if r.dead then why = L('pj.flat') break end
            end
        end

        base.pumping = pumping
        base.hint = (veh and not atCap) and L('pj.hint_cap') or L('pj.hint_pump')
        panel(base)
    end

    StopAnimTask(ped, dict, 'gar_ig_5_filling_can', 2.0)
    dropRope(hose)
    if DoesEntityExist(nozzle) then DeleteObject(nozzle) end
    panelHide()

    if why then notify('warn', why, 3500) end
    if base.liters > 0 then notify('success', L('pj.pumped', { n = math.floor(base.liters) }), 3500) end
end

-- Options on every pump (shown everywhere so the live grid is not leaked)

local function run(fn, ...)
    if busy then return end
    local args = { ... }
    CreateThread(function()
        busy = true
        local ok, err = pcall(fn, table.unpack(args))
        if not ok then print('[bs_vehicles] pump: ' .. tostring(err)); panelHide() end
        busy = false
    end)
end

RegisterNetEvent('bs:vehicles:pump:jump', function(payload)
    if not payload or not payload.coords or not J().enabled then return end
    run(jumpFlow, payload.coords)
end)

RegisterNetEvent('bs:vehicles:pump:vehicle', function(payload)
    if payload and payload.coords then run(hoseFlow, payload.coords, 'tank') end
end)

RegisterNetEvent('bs:vehicles:pump:fill', function(payload)
    if payload and payload.coords then run(hoseFlow, payload.coords, 'can') end
end)

RegisterNetEvent('bs:vehicles:pump:unclamp', function()
    CreateThread(function()
        local r = BSB.Await('vehicles:jumpDisconnect', 5000)
        if not r or not r.ok then notify('info', L('pj.not_yours')) end
    end)
end)

-- Charging batteries at a running base generator.
RegisterNetEvent('bs:vehicles:charge', function()
    if busy then return end
    run(function()
        local r = BSB.Await('vehicles:chargeStart', 8000)
        if not r or not r.ok then return notify('warn', (r and r.error) or L('pj.no_generator')) end
        local ped = PlayerPedId()
        if loadDict('mini@repair') then TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, r.ms, 49, 0.0, false, false, false) end
        exports.bs_interactions:Progress(L('pj.charging'), r.ms)
        local start, elapsed = GetEntityCoords(ped), 0
        while elapsed < r.ms do
            Wait(100); elapsed = elapsed + 100
            if #(GetEntityCoords(ped) - start) > 2.0 or IsControlJustPressed(0, 202) then
                ClearPedTasks(ped); exports.bs_interactions:CancelProgress()
                return notify('info', L('common.stopped'))
            end
        end
        ClearPedTasks(ped)
        local f = BSB.Await('vehicles:chargeFinish', 8000)
        if not f or not f.ok then return notify('warn', (f and f.error) or L('pj.no_generator')) end
        notify('success', L('pj.charged', { n = f.n }), 3500)
    end)
end)

CreateThread(function()
    if not Pc().enabled then return end
    local d = Pc().distance or 2.6
    exports.bs_interactions:AddModel(Pc().models or {}, {
        { label = L('pj.opt_refuel'), labelKey = 'pj.opt_refuel', icon = 'drop', distance = d, event = 'bs:vehicles:pump:vehicle' },
        { label = L('pj.opt_can'), labelKey = 'pj.opt_can', icon = 'drop', distance = d, event = 'bs:vehicles:pump:fill' },
        { label = L('pj.opt_connect'), labelKey = 'pj.opt_connect', icon = 'tool', distance = d, event = 'bs:vehicles:pump:jump' },
        { label = L('pj.opt_unclamp'), labelKey = 'pj.opt_unclamp', icon = 'tool', distance = d, event = 'bs:vehicles:pump:unclamp' },
    })
    local R = Pc().recharge or {}
    if R.generatorModels then
        exports.bs_interactions:AddModel(R.generatorModels, {
            { label = L('pj.opt_charge'), labelKey = 'pj.opt_charge', icon = 'power', distance = 2.5, event = 'bs:vehicles:charge' },
        })
    end
end)
