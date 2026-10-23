-- bs_medical - conditions on the client: what you feel (limp, sway, blur,
-- coughing), what hit you (reported to the server), the HUD icons, the
-- Medical tab in the inventory and the paid doctors.
-- Nothing here decides an outcome; the server does.

local SYS = Medical.System
local Cur = { on = false }          -- last state from the server
local View = { target = nil }       -- who the Medical tab is looking at
local Fx = { limp = false, shake = nil, amp = 0.0, blur = 0.0, sprintBlock = false }
local busy = false

local function me() return GetPlayerServerId(PlayerId()) end
local function on() return Cur.on == true and GlobalState.bsMedicalOn == true end

local function notify(kind, msg)
    TriggerEvent('bs:ui:notify', { type = kind, message = msg, title = L('title') })
end

local function isDowned()
    local ok, d = pcall(function() return exports.bs_medical:IsDowned() end)
    return ok and d
end

-- Summary flags

local function flags(st)
    local f = { bleed = 0, legFrac = false, legSplint = false, armFrac = false, armSplint = false, bullet = false }
    if not st or not st.parts then return f end
    for name, p in pairs(st.parts) do
        if p.bleed > f.bleed then f.bleed = p.bleed end
        if p.bullet then f.bullet = true end
        if p.frac then
            local leg = name == 'lleg' or name == 'rleg'
            local arm = name == 'larm' or name == 'rarm'
            if leg then if p.splint > 0 then f.legSplint = true else f.legFrac = true end end
            if arm then if p.splint > 0 then f.armSplint = true else f.armFrac = true end end
        end
    end
    return f
end

-- HUD icons

local function pushHud()
    if GetResourceState('bs_ui') ~= 'started' then return end
    local list = {}
    if on() then
        local f = flags(Cur)
        if f.bleed > 0 then list[#list + 1] = { id = 'bleed', level = f.bleed, label = L(f.bleed == 2 and 'cond_bleed_heavy' or 'cond_bleed_light') } end
        if f.legFrac or f.armFrac or f.legSplint or f.armSplint then
            list[#list + 1] = { id = 'fracture', level = (f.legFrac or f.armFrac) and 2 or 1, label = L('cond_fracture') }
        end
        if (Cur.stage or 0) > 0 then list[#list + 1] = { id = 'infected', level = Cur.stage, label = L('stage_' .. Cur.stage) } end
        if (Cur.food or 0) > 0 then list[#list + 1] = { id = 'sick', level = 1, label = L('cond_food') } end
        if (Cur.cold or 0) > 0 then list[#list + 1] = { id = 'cold', level = 1, label = L('cond_cold') } end
        if (Cur.pain or 0) > 0 then
            local masked = (Cur.pk or 0) > 0
            list[#list + 1] = { id = 'pain', level = masked and 1 or ((Cur.pain >= 50) and 2 or 1),
                label = masked and L('cond_pain_masked') or (L('cond_pain') .. ' ' .. Cur.pain) }
        end
        if (Cur.blood or 100) < SYS.bloodLowAt then
            list[#list + 1] = { id = 'blood', level = (Cur.blood < SYS.bloodCriticalAt) and 2 or 1, label = L('cond_low_blood') }
        end
    end
    pcall(function() exports.bs_ui:Send({ action = 'medConds', list = list }) end)
end

-- Inventory Medical tab

local PART_KEYS = { head = 'part_head', torso = 'part_torso', larm = 'part_larm', rarm = 'part_rarm', lleg = 'part_lleg', rleg = 'part_rleg' }

local function strings()
    local t = {}
    for _, k in ipairs({ 'tab_title', 'tab_self', 'tab_patient', 'tab_pick_part', 'tab_pick_item', 'tab_apply', 'tab_no_items',
        'tab_blood', 'tab_pain', 'tab_infection', 'tab_sickness', 'tab_healthy', 'tab_off', 'tab_whole', 'tab_others_only',
        'cond_bleed_light', 'cond_bleed_heavy', 'cond_fracture', 'cond_splinted', 'cond_bullet', 'cond_food', 'cond_cold',
        'cond_low_blood', 'cond_pain', 'cond_pain_masked', 'stage_0', 'stage_1', 'stage_2', 'stage_3', 'tab_hint', 'tab_back_self', 'tab_skill' }) do
        t[k] = L(k)
    end
    for p, k in pairs(PART_KEYS) do t['part_' .. p] = L(k) end
    return t
end

local function carried()
    local out = {}
    for name, def in pairs(Medical.Items) do
        local ok, n = pcall(function() return exports.bs_inventory:CountLocal(name) end)
        n = ok and tonumber(n) or 0
        if n > 0 then
            out[#out + 1] = { name = name, count = n, label = L('item_' .. name), self = def.self, whole = def.whole == true,
                limbs = def.limbs == true, desc = L('use_' .. def.does) }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function pushTab(extra)
    local selfView = (View.target == nil or View.target == me())
    local payload = {
        action = 'medical', on = on(), t = strings(), items = carried(),
        view = { self = selfView, target = View.target or me(), name = View.name, skill = View.skill or 0 },
        state = selfView and Cur or View.state,
    }
    -- Extra read-only info for the tab's readout: item names for treatment tips, rates, own health.
    local names = {}
    for name in pairs(Medical.Items) do names[name] = L('item_' .. name) end
    payload.names = names
    payload.cfg = { bleedLight = SYS.bleedLight, bleedHeavy = SYS.bleedHeavy, regen = SYS.bloodRegen,
        lowAt = SYS.bloodLowAt, critAt = SYS.bloodCriticalAt, stage2 = SYS.stage2At, stage3 = SYS.stage3At,
        infRate = SYS.infectionPerMinute, antiviralMax = SYS.antiviralMaxStage }
    if selfView then
        local ped = PlayerPedId()
        payload.hp = { cur = math.max(0, GetEntityHealth(ped) - 100), max = math.max(1, GetEntityMaxHealth(ped) - 100) }
    end
    if extra then for k, v in pairs(extra) do payload[k] = v end end
    TriggerEvent('bs:inventory:nui', payload)
end

local function invOpen()
    local ok, o = pcall(function() return exports.bs_inventory:IsOpen() end)
    return ok and o
end

AddEventHandler('bs:ui:opened', function(name)
    if name ~= 'inventory' then return end
    if not View.keep then View = { target = nil } end
    View.keep = nil
    pushTab(View.select and { select = View.select } or nil)
    View.select = nil
end)

-- Keeps a patient's view fresh while the tab is up.
CreateThread(function()
    while true do
        Wait(2000)
        if View.target and View.target ~= me() and invOpen() then
            local r = BSB.Await('medical:examine', 4000, View.target)
            if r and r.ok then View.state = r.state pushTab()
            else View = { target = nil } pushTab() end
        end
    end
end)

local function openFor(target, item)
    if target and target ~= me() then
        local r = BSB.Await('medical:examine', 5000, target)
        if not r or not r.ok then return notify('warn', (r and r.error) or L('err_too_far')) end
        View = { target = target, name = r.name, state = r.state, skill = r.skill, keep = true }
    else
        View = { target = nil, keep = true }
    end
    View.select = item
    if invOpen() then
        View.keep = nil
        pushTab({ select = item, focus = true })
    else
        exports.bs_inventory:Open('medical')
    end
end

RegisterNetEvent('bs:medical:openTab', function(target, item)
    CreateThread(function() openFor(tonumber(target), item) end)
end)

AddEventHandler('bs:medical:dot:examine', function(payload)
    if not payload or not payload.entity or not on() then return end
    local idx = NetworkGetPlayerIndexFromPed(payload.entity)
    if not idx or idx == -1 then return end
    local sid = GetPlayerServerId(idx)
    CreateThread(function() openFor(sid) end)
end)

-- Treatment

local function playTreatAnim(kind)
    local a = Medical.TreatAnims[kind]
    if not a then return end
    RequestAnimDict(a.dict)
    local waited = 0
    while not HasAnimDictLoaded(a.dict) and waited < 2000 do Wait(10) waited = waited + 10 end
    if HasAnimDictLoaded(a.dict) then
        TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 3.0, 3.0, -1, a.flag or 49, 0.0, false, false, false)
    end
end

local function treat(target, part, item)
    if busy then return end
    busy = true
    target = tonumber(target) or me()
    local start = BSB.Await('medical:treatStart', 6000, target, part, item)
    if not start or not start.ok then
        busy = false
        return pushTab({ error = (start and start.error) or L('err_cannot_use') })
    end

    -- The bag closes so the bar can be cancelled by moving.
    pcall(function() exports.bs_inventory:Close() end)
    playTreatAnim(start.anim)
    local done = true
    if GetResourceState('bs_interactions') == 'started' then
        local ok, r = pcall(function()
            return exports.bs_interactions:RunSearch(L('item_' .. item), start.time, { pose = 'none' })
        end)
        done = ok and r and true or false
    else
        Wait(start.time)
    end
    ClearPedTasks(PlayerPedId())

    if not done then
        BSB.Await('medical:treatCancel', 4000)
        busy = false
        return notify('warn', L('treat_cancelled'))
    end
    local r = BSB.Await('medical:treat', 8000, target, part, item)
    busy = false
    notify((r and r.ok) and 'success' or 'warn', (r and (r.message or r.error)) or L('err_cannot_use'))
    if r and r.ok and target ~= me() and item ~= 'defibrillator' then
        View = { target = target, name = View.name, state = r.state, skill = View.skill, keep = true }
        Wait(300)
        exports.bs_inventory:Open('medical')
    end
end

-- From the Medical tab (relayed by bs_inventory).
AddEventHandler('bs:medical:nui', function(data)
    if type(data) ~= 'table' then return end
    if data.op == 'refresh' then
        pushTab()
    elseif data.op == 'self' then
        View = { target = nil }
        pushTab()
    elseif data.op == 'apply' then
        CreateThread(function() treat(View.target or me(), data.part, data.item) end)
    end
end)

-- State from the server

RegisterNetEvent('bs:medical:state', function(st)
    if type(st) ~= 'table' then return end
    Cur = st
    LocalPlayer.state:set('bsMedOn', st.on == true, false)
    pushHud()
    if invOpen() and (View.target == nil or View.target == me()) then pushTab() end
end)

RegisterNetEvent('bs:medical:hurt', function(amount)
    local ped = PlayerPedId()
    if isDowned() or IsEntityDead(ped) then return end
    local hp = GetEntityHealth(ped)
    SetEntityHealth(ped, math.max(0, hp - math.floor(tonumber(amount) or 0)))
end)

RegisterNetEvent('bs:medical:heal', function(amount)
    local ped = PlayerPedId()
    if isDowned() or IsEntityDead(ped) then return end
    local max = GetEntityMaxHealth(ped)
    -- amount is a percent of max health (pool above the 100 death line)
    local pts = math.floor(math.max(0, max - 100) * (tonumber(amount) or 0) / 100 + 0.5)
    SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + pts))
end)

RegisterNetEvent('bs:medical:symptom', function(kind, radius)
    local ped = PlayerPedId()
    if isDowned() or IsPedInAnyVehicle(ped, false) then return end
    if kind == 'vomit' then
        playTreatAnim('vomit')
        notify('warn', L('symptom_vomit'))
        SetTimeout(4500, function() StopAnimTask(PlayerPedId(), Medical.TreatAnims.vomit.dict, Medical.TreatAnims.vomit.clip, 1.0) end)
    elseif kind == 'cough' then
        playTreatAnim('cough')
        local c = GetEntityCoords(ped)
        if GetResourceState('bs_emotes') == 'started' then
            pcall(function() exports.bs_emotes:MakeNoise('shout', c, tonumber(radius) or SYS.coughNoise) end)
        end
        SetTimeout(3000, function() StopAnimTask(PlayerPedId(), Medical.TreatAnims.cough.dict, Medical.TreatAnims.cough.clip, 1.0) end)
    end
end)

-- Effects. One 500 ms loop; a per-frame loop runs only while a leg is broken.

local LIMP = 'move_m@injured'

local function setLimp(want)
    if want == Fx.limp then return end
    Fx.limp = want
    local ped = PlayerPedId()
    if want then
        RequestClipSet(LIMP)
        local w = 0
        while not HasClipSetLoaded(LIMP) and w < 1500 do Wait(10) w = w + 10 end
        SetPedMovementClipset(ped, LIMP, 0.5)
    else
        ResetPedMovementClipset(ped, 0.5)
    end
end

local function setBlur(strength)
    if math.abs(strength - Fx.blur) < 0.02 then return end
    if strength <= 0 then
        ClearExtraTimecycleModifier()
    else
        if Fx.blur <= 0 then SetExtraTimecycleModifier('hud_def_blur') end
        SetExtraTimecycleModifierStrength(strength)
    end
    Fx.blur = strength
end

local function sprintBlocker()
    if Fx.sprintBlock then return end
    Fx.sprintBlock = true
    CreateThread(function()
        while Fx.sprintBlock do
            Wait(0)
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
        end
    end)
end

local function clearFx()
    setLimp(false)
    setBlur(0.0)
    Fx.sprintBlock = false
    if Fx.shake then StopGameplayCamShaking(false) Fx.shake = nil Fx.amp = 0.0 end
    LocalPlayer.state:set('bsMedStaminaCap', nil, false)
end

CreateThread(function()
    while true do
        Wait(500)
        if not on() or isDowned() then
            clearFx()
        else
            local f = flags(Cur)
            local ped = PlayerPedId()
            local inCar = IsPedInAnyVehicle(ped, false)

            setLimp((f.legFrac or f.legSplint) and not inCar)
            if f.legFrac and not inCar then sprintBlocker() else Fx.sprintBlock = false end

            -- Shake: a broken arm or pain sways the aim; pain alone shakes the view.
            -- Painkillers mask the pain part.
            local pain = ((Cur.pk or 0) > 0) and 0 or (Cur.pain or 0)
            local aiming = IsPlayerFreeAiming(PlayerId())
            local kind, amp = nil, 0.0
            if aiming then
                amp = (f.armFrac and 1.8 or (f.armSplint and 0.7 or 0.0)) + pain * 0.02
                if amp > 0.05 then kind = 'HAND_SHAKE' end
            elseif pain >= 15 then
                kind, amp = 'DRUNK_SHAKE', math.min(1.0, pain * 0.009)
            end
            if kind ~= Fx.shake then
                if Fx.shake then StopGameplayCamShaking(false) end
                if kind then ShakeGameplayCam(kind, amp) end
                Fx.shake, Fx.amp = kind, amp
            elseif kind and math.abs(amp - Fx.amp) > 0.05 then
                SetGameplayCamShakeAmplitude(amp)
                Fx.amp = amp
            end

            -- Blur: low blood and the later infection stages.
            local blur = 0.0
            local blood = Cur.blood or 100
            if blood < SYS.bloodLowAt then blur = math.min(0.8, (SYS.bloodLowAt - blood) / SYS.bloodLowAt * 1.2) end
            if (Cur.stage or 0) == 2 then blur = math.max(blur, 0.25 + 0.2 * math.abs(math.sin(GetGameTimer() / 1800))) end
            if (Cur.stage or 0) >= 3 then blur = math.max(blur, 0.6) end
            setBlur(blur)

            -- Low blood caps stamina (bs_core reads this).
            local cap = nil
            if blood < SYS.bloodLowAt then cap = math.max(15.0, blood) end
            if LocalPlayer.state.bsMedStaminaCap ~= cap then LocalPlayer.state:set('bsMedStaminaCap', cap, false) end
        end
    end
end)

-- Slow health regen when fed, watered and not bleeding.
CreateThread(function()
    while true do
        Wait(10000)
        if on() and not isDowned() then
            local ped = PlayerPedId()
            local f = flags(Cur)
            if f.bleed == 0 and (Cur.stage or 0) < 2 and (Cur.blood or 100) >= SYS.bloodLowAt and not IsEntityDead(ped) then
                local ok, d = pcall(function() return exports.bs_core:GetData() end)
                local n = ok and type(d) == 'table' and d.needs or {}
                local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
                if (n.hunger or 0) >= SYS.regenNeedsAt and (n.thirst or 0) >= SYS.regenNeedsAt and hp > 125 and hp < max then
                    SetEntityHealth(ped, math.min(max, hp + (SYS.regenHp or 1)))
                end
            end
        end
    end
end)

-- What hit you

local BONES = {
    [31086] = 'head', [39317] = 'head', [12844] = 'head', [65068] = 'head',
    [18905] = 'larm', [45509] = 'larm', [61163] = 'larm', [26610] = 'larm', [4089] = 'larm',
    [57005] = 'rarm', [40269] = 'rarm', [28252] = 'rarm', [58866] = 'rarm', [64016] = 'rarm',
    [58271] = 'lleg', [63931] = 'lleg', [14201] = 'lleg', [2108] = 'lleg', [65245] = 'lleg',
    [51826] = 'rleg', [36864] = 'rleg', [52301] = 'rleg', [20781] = 'rleg', [35502] = 'rleg',
}
local BLADES = {}
for _, w in ipairs({ 'WEAPON_KNIFE', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_BOTTLE', 'WEAPON_DAGGER',
    'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET' }) do BLADES[GetHashKey(w)] = true end
local FALL = GetHashKey('WEAPON_FALL')

local lastHp = 200
local airTop, lastAirTop = nil, nil

CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        if on() then
            local z = GetEntityCoords(ped).z
            if IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedInParachuteFreeFall(ped) then
                airTop = math.max(airTop or z, z)
            elseif airTop then
                lastAirTop, airTop = airTop, nil
                SetTimeout(600, function() lastAirTop = nil end)
            end
            lastHp = GetEntityHealth(ped)
        end
    end
end)

local function partOf(ped)
    local ok, bone = GetPedLastDamageBone(ped)
    return (ok and BONES[bone]) or 'torso'
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not on() then return end
    local ped = PlayerPedId()
    if args[1] ~= ped or isDowned() then return end
    local weapon = args[7]
    local attacker = args[2]
    -- Walkers are handled by bs_zombies' hit event.
    if attacker and attacker ~= 0 and DoesEntityExist(attacker) and IsEntityAPed(attacker) and not IsPedAPlayer(attacker) then
        local st = Entity(attacker).state
        if st and st.bsZombie then return end
    end
    local taken = math.max(0, lastHp - GetEntityHealth(ped))
    local kind
    if weapon == FALL then
        local z = GetEntityCoords(ped).z
        local top = airTop or lastAirTop or z
        return TriggerServerEvent('bs:medical:injury', 'lleg', 'fall', top - z)
    elseif BLADES[weapon] then kind = 'blade'
    else
        local dt = GetWeaponDamageType(weapon)
        if dt == 3 then kind = 'bullet' elseif dt == 2 then kind = 'blunt' end
    end
    if kind then TriggerServerEvent('bs:medical:injury', partOf(ped), kind, taken) end
end)

-- Vehicle crashes: a sudden loss of speed against something.
CreateThread(function()
    local prev = 0.0
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and on() then
            Wait(200)
            local kmh = GetEntitySpeed(veh) * 3.6
            local drop = prev - kmh
            if drop >= SYS.crashFractureKmh and HasEntityCollidedWithAnything(veh) then
                TriggerServerEvent('bs:medical:injury', 'torso', 'crash', drop)
            end
            prev = kmh
        else
            prev = 0.0
            Wait(1000)
        end
    end
end)

-- Wet at night catches a cold; a fire warms you. Checked once a minute.
local FIRES = { GetHashKey('prop_beach_fire'), GetHashKey('prop_hobo_stove_01') }
local wetUntil = 0

CreateThread(function()
    while true do
        Wait(15000)
        if on() then
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local inside = GetInteriorFromEntity(ped) ~= 0 or IsPedInAnyVehicle(ped, false)
            if IsEntityInWater(ped) or IsPedSwimming(ped) or (GetRainLevel() > 0.3 and not inside) then
                wetUntil = now + 10 * 60000
            end
            local c = GetEntityCoords(ped)
            local fire = false
            for _, h in ipairs(FIRES) do
                if GetClosestObjectOfType(c.x, c.y, c.z, 5.0, h, false, false, false) ~= 0 then fire = true break end
            end
            if fire then wetUntil = 0 end
            local hour = GetClockHours()
            local night = hour >= 21 or hour < 6
            if (now // 15000) % 4 == 0 then
                TriggerServerEvent('bs:medical:env', now < wetUntil, night, fire)
            end
        end
    end
end)

-- Interaction dot: check someone's injuries (opens their body in your Medical tab).
CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(1000) end
    Wait(500)
    exports.bs_interactions:AddType('ped', {
        {
            label    = L('dot_examine'),
            icon     = 'medical',
            distance = 2.5,
            event    = 'bs:medical:dot:examine',
            filters  = { playerPed = true, stateFalse = 'bsZombie', playerStateTrue = 'bsMedOn', maxDistance = 2.5 },
        },
    })
end)

-- Doctors in safe zones

local docPeds = {}

local function spawnDoctor(i, d)
    local model = GetHashKey(Medical.DoctorModel)
    RequestModel(model)
    local w = 0
    while not HasModelLoaded(model) and w < 3000 do Wait(20) w = w + 20 end
    if not HasModelLoaded(model) then return end
    local ped = CreatePed(4, model, d.x, d.y, d.z - 1.0, d.h, false, false)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 then return end
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    docPeds[i] = ped
    if GetResourceState('bs_interactions') == 'started' then
        exports.bs_interactions:AddEntity(ped, {
            { label = L('dot_doctor', { price = SYS.doctorPrice }), icon = 'medical', distance = 2.5, event = 'bs:medical:dot:doctor' },
        })
    end
end

local function despawnDoctor(i)
    local ped = docPeds[i]
    docPeds[i] = nil
    if ped and DoesEntityExist(ped) then
        if GetResourceState('bs_interactions') == 'started' then pcall(function() exports.bs_interactions:RemoveEntity(ped) end) end
        DeleteEntity(ped)
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        local list = GlobalState.bsMedDoctors or {}
        local at = GetEntityCoords(PlayerPedId())
        for i, d in ipairs(list) do
            local near = GlobalState.bsMedicalOn and #(at - vector3(d.x, d.y, d.z)) < 60.0
            if near and not docPeds[i] then spawnDoctor(i, d)
            elseif not near and docPeds[i] then despawnDoctor(i) end
        end
    end
end)

AddEventHandler('bs:medical:dot:doctor', function()
    CreateThread(function()
        local r = BSB.Await('medical:doctor', 8000)
        notify((r and r.ok) and 'success' or 'warn', (r and (r.message or r.error)) or L('err_cannot_use'))
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearFx()
    for i in pairs(docPeds) do despawnDoctor(i) end
    pcall(function() exports.bs_ui:Send({ action = 'medConds', list = {} }) end)
end)

AddEventHandler('bs:hook:player:unloaded', function()
    Cur = { on = false }
    clearFx()
    pushHud()
end)
