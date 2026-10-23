-- bs_medical - conditions: wounds, fractures, infection, sickness, blood.
-- The server owns all of it. Clients only report what hit them and ask to
-- treat; every result is decided here. One 5 s loop for everyone.

local SYS   = Medical.System
local PARTS = Medical.Parts
local ITEMS = Medical.Items
local LIMB  = { larm = true, rarm = true, lleg = true, rleg = true }
local LEGS  = { 'lleg', 'rleg' }
local ARMS  = { 'larm', 'rarm' }
local TICK  = 5

Med = {}                 -- [src] = state
local charOf  = {}       -- [src] = charId
local dirty   = {}       -- [src] = true when it needs saving
local pending = {}       -- [src] = treatment started, waiting to finish
local lastHit = {}       -- [src] = GetGameTimer of the last accepted report

function MedicalOn() return SYS.enabled == true end

local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars), title = Lp(src, 'title') })
end

-- Medical log, kept with the guard log so staff have one place to look.
local function logMed(src, details)
    src = tonumber(src) or 0
    local ped = src > 0 and GetPlayerPed(src) or 0
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local lic = src > 0 and GetPlayerIdentifierByType(src, 'license') or nil
    local name = src > 0 and (GetPlayerName(src) or '?') or 'console'
    TriggerEvent('bs:db:insert', 'INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, lic, charOf[src], name:sub(1, 64), 'medical', 0, tostring(details):sub(1, 512), c.x, c.y, c.z })
end
MedicalLog = logMed

-- State

local function newState()
    local parts = {}
    for _, p in ipairs(PARTS) do
        parts[p] = { bleed = 0, frac = false, splint = 0, bullet = false, rebleed = 0 }
    end
    return { parts = parts, inf = 0.0, food = 0, cold = 0, blood = 100.0, hit = 0.0, pk = 0 }
end

local function stageOf(inf)
    if inf <= 0 then return 0 end
    if inf < SYS.stage2At then return 1 end
    if inf < SYS.stage3At then return 2 end
    return 3
end

local function bleedLoss(st)
    local loss = 0.0
    for _, p in pairs(st.parts) do
        if p.bleed == 2 then loss = loss + SYS.bleedHeavy
        elseif p.bleed == 1 then loss = loss + SYS.bleedLight end
    end
    return loss
end

-- Pain per part and overall. Hits add to `hit`, which fades on its own.
local PAIN = { light = 15, heavy = 30, frac = 35, splint = 12, bullet = 20 }
local function painOf(st)
    local per, total = {}, 0
    for name, p in pairs(st.parts) do
        local v = 0
        if p.bleed == 2 then v = v + PAIN.heavy elseif p.bleed == 1 then v = v + PAIN.light end
        if p.frac then v = v + (p.splint > 0 and PAIN.splint or PAIN.frac) end
        if p.bullet then v = v + PAIN.bullet end
        per[name] = v
        total = total + v
    end
    total = (total + (st.hit or 0)) * (SYS.painMult or 1.0)
    return math.min(100, math.floor(total)), per
end

local function snapshot(st)
    if not MedicalOn() then return { on = false } end
    local now = os.time()
    local parts = {}
    for name, p in pairs(st.parts) do
        parts[name] = { bleed = p.bleed, frac = p.frac, bullet = p.bullet,
            splint = p.splint > 0 and math.max(0, p.splint - now) or 0 }
    end
    local pain, per = painOf(st)
    for name, v in pairs(per) do parts[name].pain = v end
    return {
        on = true, parts = parts,
        pain = pain, pk = (st.pk or 0) > now and (st.pk - now) or 0,
        inf = math.floor(st.inf * 10) / 10, stage = stageOf(st.inf),
        food = st.food > 0 and math.max(0, st.food - now) or 0,
        cold = st.cold > 0 and math.max(0, st.cold - now) or 0,
        blood = math.floor(st.blood * 10) / 10,
        bleeding = bleedLoss(st) > 0,
    }
end
MedicalSnapshot = function(src) return Med[src] and snapshot(Med[src]) or { on = MedicalOn() } end

-- The HUD infection bar is bs_core's number; keep it in step with ours.
local function mirrorInfection(src, st)
    local player = exports.bs_core:GetPlayer(src)
    if not player or not player.needs then return end
    local want = MedicalOn() and st and st.inf or 0.0
    local have = player.needs.infection or 0.0
    if math.abs(want - have) >= 0.5 or (want == 0 and have > 0) then
        exports.bs_core:ChangeInfection(src, want - have)
    end
end

local function push(src)
    local st = Med[src]
    TriggerClientEvent('bs:medical:state', src, st and snapshot(st) or { on = MedicalOn() })
    mirrorInfection(src, st)
end
MedicalPush = push

local function touch(src) dirty[src] = true push(src) end

-- Saving. Timers are stored as seconds left, so time offline does not heal.

local function encode(st)
    local now, out = os.time(), { inf = st.inf, blood = st.blood, hit = st.hit or 0, parts = {} }
    out.pk = (st.pk or 0) > now and (st.pk - now) or 0
    out.food = st.food > 0 and math.max(0, st.food - now) or 0
    out.cold = st.cold > 0 and math.max(0, st.cold - now) or 0
    for name, p in pairs(st.parts) do
        out.parts[name] = { bleed = p.bleed, frac = p.frac, bullet = p.bullet,
            splint = p.splint > 0 and math.max(1, p.splint - now) or 0,
            rebleed = p.rebleed > 0 and math.max(1, p.rebleed - now) or 0 }
    end
    return json.encode(out)
end

local function decode(raw)
    local st = newState()
    local ok, d = pcall(json.decode, raw or '')
    if not ok or type(d) ~= 'table' then return st end
    local now = os.time()
    st.inf   = math.max(0.0, math.min(100.0, tonumber(d.inf) or 0.0))
    st.blood = math.max(1.0, math.min(100.0, tonumber(d.blood) or 100.0))
    st.food  = (tonumber(d.food) or 0) > 0 and now + d.food or 0
    st.cold  = (tonumber(d.cold) or 0) > 0 and now + d.cold or 0
    st.hit   = math.max(0.0, math.min(100.0, tonumber(d.hit) or 0.0))
    st.pk    = (tonumber(d.pk) or 0) > 0 and now + d.pk or 0
    for name, p in pairs(type(d.parts) == 'table' and d.parts or {}) do
        local t = st.parts[name]
        if t and type(p) == 'table' then
            t.bleed  = math.max(0, math.min(2, math.floor(tonumber(p.bleed) or 0)))
            t.frac   = p.frac == true
            t.bullet = p.bullet == true
            t.splint = (tonumber(p.splint) or 0) > 0 and now + p.splint or 0
            t.rebleed = (tonumber(p.rebleed) or 0) > 0 and now + p.rebleed or 0
        end
    end
    return st
end

local function save(src)
    local cid, st = charOf[src], Med[src]
    if not cid or not st then return end
    dirty[src] = nil
    MySQL.prepare('INSERT INTO `bs_character_medical` (`character_id`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
        { cid, encode(st) })
end

local function load(src, charId)
    if not charId then return end
    charOf[src] = charId
    MySQL.scalar('SELECT `data` FROM `bs_character_medical` WHERE `character_id` = ? LIMIT 1', { charId }, function(raw)
        if charOf[src] ~= charId then return end
        Med[src] = raw and decode(raw) or newState()
        push(src)
    end)
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `bs_character_medical` (
            `character_id` INT UNSIGNED NOT NULL,
            `data` TEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`character_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    -- Players already in when the resource (re)starts.
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local p = exports.bs_core:GetPlayer(id)
        if p and p.charId then load(id, p.charId) end
    end
end)

AddEventHandler('bs:hook:player:spawned', function(player)
    if player and player.source and player.charId and charOf[player.source] ~= player.charId then
        load(player.source, player.charId)
    end
end)

-- respawn grace table must exist before the drop handler uses it
local respawnGrace = {}   -- [src] = os.time() until which hurt() does nothing

local function forget(src)
    if dirty[src] then save(src) end
    Med[src], charOf[src], dirty[src], pending[src], lastHit[src] = nil, nil, nil, nil, nil
end

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source then forget(player.source) end
end)
AddEventHandler('playerDropped', function() respawnGrace[source] = nil forget(source) end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(dirty) do save(src) end
    GlobalState.bsMedicalInfection = false
end)

-- Switch

local lastOn = nil
local function publishSwitch()
    local on = MedicalOn()
    GlobalState.bsMedicalOn = on
    -- bs_medical owns infection whether the system is on or off (off = none).
    GlobalState.bsMedicalInfection = true
    if lastOn ~= nil and lastOn ~= on then
        for src in pairs(Med) do push(src) end
        print(('^3[BS MEDICAL]^7 medical system %s'):format(on and 'enabled' or 'disabled'))
    end
    lastOn = on
end
CreateThread(publishSwitch)
AddEventHandler('bs_config:changed:bs_medical', publishSwitch)

-- Respawned players take no condition damage for a few seconds.

-- Death clears everything; a revive keeps it.
function MedicalOnDeath(src)
    respawnGrace[src] = os.time() + 10
    if not Med[src] then return end
    Med[src] = newState()
    pending[src] = nil
    touch(src)
end

-- Inflicting

local function pick(list) return list[math.random(#list)] end

local function openWound(st, part, heavy)
    local p = st.parts[part]
    if not p then return false end
    local want = heavy and 2 or 1
    if p.bleed >= want then return false end
    p.bleed = want
    return true
end

local function breakBone(st, part)
    local p = st.parts[part]
    if not p or p.frac then return false end
    p.frac, p.splint = true, 0
    return true
end

local function infect(st)
    if st.inf > 0 then return false end
    st.inf = 1.0
    return true
end

local KINDS = {}
function KINDS.bleed(st) return openWound(st, pick(PARTS), false) end
function KINDS.bleed_heavy(st) return openWound(st, pick(PARTS), true) end
function KINDS.fracture_leg(st) return breakBone(st, pick(LEGS)) end
function KINDS.fracture_arm(st) return breakBone(st, pick(ARMS)) end
function KINDS.bullet(st)
    local part = pick(ARMS)
    st.parts[part].bullet = true
    st.parts[part].rebleed = 0
    return openWound(st, part, true) or true
end
function KINDS.infect(st) return infect(st) end
function KINDS.food(st) st.food = os.time() + SYS.foodPoisonMinutes * 60 return true end
function KINDS.cold(st) st.cold = os.time() + SYS.coldMinutes * 60 return true end
function KINDS.lowblood(st) st.blood = 35.0 return true end
function KINDS.cure(st) st.inf = 0.0 return true end
function KINDS.pain(st) st.hit = math.min(100.0, (st.hit or 0) + 60.0) st.pk = 0 return true end

-- For staff and testing. Returns ok, error.
function MedicalInflict(src, kind)
    src = tonumber(src)
    if not MedicalOn() then return false, 'medical system is off' end
    local st = Med[src]
    if not st then return false, 'no character loaded' end
    local fn = KINDS[kind]
    if not fn then return false, 'unknown condition' end
    fn(st)
    touch(src)
    return true
end

function MedicalClear(src)
    src = tonumber(src)
    if not Med[src] then return false end
    Med[src] = newState()
    pending[src] = nil
    touch(src)
    return true
end

-- Something hit me (client report). Rate limited; outcomes rolled here.
local BULLET_LODGE = 0.5

RegisterNetEvent('bs:medical:injury', function(part, kind, amount)
    local src = source
    if not MedicalOn() then return end
    local st = Med[src]
    if not st or not st.parts[part] then return end
    local now = GetGameTimer()
    if lastHit[src] and now - lastHit[src] < 300 then return end
    lastHit[src] = now
    amount = math.min(200, tonumber(amount) or 0)

    local changed = false
    -- Anything that lands hard hurts for a while.
    local add = (kind == 'bullet' and 25) or (kind == 'crash' and amount * 0.5) or (kind == 'fall' and amount * 5) or (amount >= 20 and amount * 0.6) or 0
    if add > 0 then st.hit = math.min(100.0, (st.hit or 0) + add) changed = true end
    if kind == 'bullet' then
        changed = openWound(st, part, true) or changed
        if LIMB[part] and math.random() < 0.35 then changed = breakBone(st, part) or changed end
        if part ~= 'head' and math.random() < BULLET_LODGE and not st.parts[part].bullet then
            st.parts[part].bullet = true
            st.parts[part].rebleed = 0
            changed = true
            notify(src, 'warn', 'bullet_lodged')
        end
    elseif kind == 'blade' then
        changed = openWound(st, part, math.random() < 0.3)
    elseif kind == 'blunt' then
        if amount >= 25 and LIMB[part] and math.random() < 0.25 then changed = breakBone(st, part) end
    elseif kind == 'fall' then
        if amount >= SYS.fallFractureHeight and math.random() < 0.6 then changed = breakBone(st, pick(LEGS)) end
    elseif kind == 'crash' then
        if amount >= SYS.crashFractureKmh then
            if math.random() < 0.4 then changed = breakBone(st, pick({ 'larm', 'rarm', 'lleg', 'rleg' })) or changed end
            if math.random() < 0.3 then changed = openWound(st, 'head', false) or changed end
        end
    else
        return
    end
    if changed then touch(src) end
end)

-- Zombie hits. bs_zombies still sends this; with bs_medical running it no
-- longer touches infection itself.
local lastBite = {}
RegisterNetEvent('bs:zombies:bitten', function(typeId)
    local src = source
    if not MedicalOn() then return end
    local st = Med[src]
    if not st then return end
    local now = os.time()
    if lastBite[src] and now - lastBite[src] < 1 then return end
    lastBite[src] = now

    local changed = false
    if typeId == 'brute' then st.hit = math.min(100.0, (st.hit or 0) + 20) changed = true end
    if math.random() < SYS.scratchChance then changed = openWound(st, pick(PARTS), false) or changed end
    if typeId == 'brute' and math.random() < SYS.bruteFractureChance then
        changed = breakBone(st, pick({ 'larm', 'rarm', 'lleg', 'rleg', 'torso' })) or changed
    end
    local chance = SYS.infectChance
    if bleedLoss(st) > 0 then chance = chance * SYS.bleedInfectMult end
    if math.random() < chance and infect(st) then
        changed = true
        logMed(src, 'infected by a zombie hit')
    end
    if changed then touch(src) end
end)

-- Raw meat, dirty water and the like (fired by bs_crafting and others).
AddEventHandler('bs:medical:sicken', function(src, reason)
    src = tonumber(src)
    if not src or not MedicalOn() or not Med[src] then return end
    if reason == 'cold' then KINDS.cold(Med[src]) else KINDS.food(Med[src]) end
    notify(src, 'warn', reason == 'cold' and 'got_cold' or 'got_sick')
    logMed(src, 'sickened: ' .. tostring(reason))
    touch(src)
end)

-- Wet at night, away from a fire: a chance to catch a cold. Sent once a minute.
local lastEnv = {}
RegisterNetEvent('bs:medical:env', function(wet, night, fire)
    local src = source
    if not MedicalOn() or not Med[src] then return end
    local now = os.time()
    if lastEnv[src] and now - lastEnv[src] < 50 then return end
    lastEnv[src] = now
    local st = Med[src]
    if fire and st.cold > 0 then
        -- A fire burns the cold off three times as fast.
        st.cold = math.max(now + 1, st.cold - 120)
        touch(src)
    elseif wet and night and not fire and st.cold == 0 and math.random() < SYS.coldChance then
        st.cold = now + SYS.coldMinutes * 60
        notify(src, 'warn', 'got_cold')
        touch(src)
    end
end)

-- The loop

local function hurt(src, amount)
    if MedicalIsDown and MedicalIsDown(src) then return end
    if (respawnGrace[src] or 0) > os.time() then return end
    TriggerClientEvent('bs:medical:hurt', src, amount)
end

CreateThread(function()
    while true do
        Wait(TICK * 1000)
        if MedicalOn() then
            local now, dt = os.time(), TICK / 60.0
            for src, st in pairs(Med) do
                if GetPlayerName(src) then
                    local down = MedicalIsDown and MedicalIsDown(src)
                    local active = false

                    for _, p in pairs(st.parts) do
                        if p.splint > 0 and now >= p.splint then
                            p.frac, p.splint = false, 0
                            notify(src, 'success', 'bone_healed')
                            dirty[src] = true
                        end
                        if p.bullet and p.bleed == 0 then
                            if p.rebleed == 0 then
                                p.rebleed = now + SYS.bulletRebleedMin * 60
                            elseif now >= p.rebleed then
                                p.bleed, p.rebleed = 1, 0
                                notify(src, 'warn', 'wound_reopened')
                                dirty[src] = true
                            end
                        end
                        if p.bleed > 0 or p.frac or p.bullet then active = true end
                    end

                    if (st.hit or 0) > 0 then
                        st.hit = math.max(0.0, st.hit - (SYS.hitPainDecay or 6.0) * dt)
                        active = true
                        dirty[src] = true
                    end
                    if (st.pk or 0) > 0 then
                        active = true
                        if now >= st.pk then st.pk = 0 dirty[src] = true end
                    end

                    local loss = bleedLoss(st)
                    if loss > 0 then
                        st.blood = math.max(0.0, st.blood - loss * dt)
                        dirty[src] = true
                    elseif st.blood < 100.0 then
                        local p = exports.bs_core:GetPlayer(src)
                        local n = p and p.needs or {}
                        if (n.hunger or 0) >= SYS.regenNeedsAt and (n.thirst or 0) >= SYS.regenNeedsAt then
                            st.blood = math.min(100.0, st.blood + SYS.bloodRegen * dt)
                            dirty[src] = true
                        end
                    end
                    if st.blood < 100.0 then active = true end
                    if st.blood < SYS.bloodCriticalAt then hurt(src, st.blood <= 5 and 15 or 3) end

                    if st.inf > 0 and not down then
                        active = true
                        st.inf = math.min(100.0, st.inf + SYS.infectionPerMinute * dt)
                        dirty[src] = true
                        if st.inf >= 100.0 and (respawnGrace[src] or 0) <= now then
                            logMed(src, 'collapsed from the infection')
                            TriggerClientEvent('bs:medical:hurt', src, 500)
                            -- Brought back, they are still dying, just not instantly again.
                            st.inf = SYS.stage3At
                        elseif stageOf(st.inf) >= 3 then
                            hurt(src, 2)
                        end
                    end

                    if st.food > 0 then
                        active = true
                        if now >= st.food then st.food = 0 dirty[src] = true
                        elseif not down and math.random() < TICK / 150 then
                            exports.bs_core:RestoreNeeds(src, -SYS.vomitLoss, -SYS.vomitLoss)
                            TriggerClientEvent('bs:medical:symptom', src, 'vomit')
                        end
                    end
                    if st.cold > 0 then
                        active = true
                        if now >= st.cold then st.cold = 0 dirty[src] = true
                        elseif not down and math.random() < TICK / 90 then
                            TriggerClientEvent('bs:medical:symptom', src, 'cough', SYS.coughNoise)
                        end
                    end

                    if active or dirty[src] then push(src) end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        for src in pairs(dirty) do save(src) end
    end
end)

-- Treatment

local function distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function skillOf(src)
    if GetResourceState('bs_skills') ~= 'started' then return 0 end
    local ok, lv = pcall(function() return exports.bs_skills:GetSkillLevel(src, 'medical') end)
    return ok and tonumber(lv) or 0
end

local function treatTime(src, def, other)
    local t = def.time
    if other then t = t * SYS.otherSpeed end
    t = t * (1.0 - math.min(0.5, skillOf(src) * SYS.skillSpeedPerLevel))
    return math.floor(t)
end

-- Can this item do anything here? Returns nil or an error key.
local function applicable(st, def, part, target, src)
    local p = st and st.parts[part]
    local d = def.does
    if not def.whole and not p then return 'pick_part' end
    if def.limbs and not LIMB[part] then return 'limbs_only' end
    if d == 'bleed_light' then
        if p.bleed == 0 then return 'not_bleeding' end
        if p.bleed == 2 then return 'too_heavy' end
    elseif d == 'bleed' or d == 'tourniquet' or d == 'medkit' then
        if p.bleed == 0 and d ~= 'medkit' then return 'not_bleeding' end
    elseif d == 'splint' then
        if not p.frac then return 'not_broken' end
        if p.splint > 0 then return 'already_splinted' end
    elseif d == 'antibiotics' then
        if st.food == 0 and st.cold == 0 then return 'nothing_to_treat' end
    elseif d == 'antiviral' then
        if st.inf <= 0 then return 'not_infected' end
        if stageOf(st.inf) > SYS.antiviralMaxStage then return 'too_late' end
    elseif d == 'antiseptic' then
        if st.inf <= 0 and p.bleed == 0 then return 'nothing_to_treat' end
    elseif d == 'painkillers' then
        if painOf(st) <= 0 then return 'no_pain' end
    elseif d == 'saline' or d == 'transfusion' then
        if st.blood >= 99.5 then return 'blood_full' end
    elseif d == 'surgery' then
        if not p.bullet then return 'no_bullet' end
    elseif d == 'defib' then
        if not (MedicalCanDefib and MedicalCanDefib(target)) then return 'no_flatline' end
    end
    return nil
end

local function check(src, target, part, item)
    if not MedicalOn() then return nil, 'system_off' end
    local def = ITEMS[item]
    if not def then return nil, 'cannot_use' end
    target = tonumber(target) or src
    local other = target ~= src
    if not other and not def.self then return nil, 'others_only' end
    if other then
        if not GetPlayerName(target) then return nil, 'too_far' end
        if distance(src, target) > 3.5 then return nil, 'too_far' end
    end
    if MedicalIsDown and MedicalIsDown(src) then return nil, 'you_are_down' end
    local st = Med[target]
    if not st then return nil, 'cannot_use' end
    if exports.bs_inventory:CountItem(src, item) < 1 then return nil, 'no_item' end
    if def.needs and exports.bs_inventory:CountItem(src, def.needs) < 1 then return nil, 'need_kit' end
    local err = applicable(st, def, part, target, src)
    if err then return nil, err end
    return { def = def, st = st, target = target, other = other }
end

BSB.RegisterCallback('medical:treatStart', function(src, target, part, item)
    local c, err = check(src, target, part, item)
    if not c then return { ok = false, error = Lp(src, 'err_' .. err) } end
    local ms = treatTime(src, c.def, c.other)
    pending[src] = { target = c.target, part = part, item = item, at = GetGameTimer(), ms = ms }
    return { ok = true, time = ms, anim = c.def.anim }
end)

BSB.RegisterCallback('medical:treatCancel', function(src) pending[src] = nil return { ok = true } end)

local function apply(src, c, part)
    local st, d, p = c.st, c.def.does, c.st.parts[part]
    local skill = skillOf(src)
    if d == 'bleed_light' then p.bleed = 0
    elseif d == 'bleed' then
        -- A good medic closes a heavy bleed in one go.
        if p.bleed == 2 and skill < 5 then p.bleed = 1 else p.bleed = 0 end
    elseif d == 'tourniquet' or d == 'medkit' then
        p.bleed = 0
        if d == 'medkit' then TriggerClientEvent('bs:medical:heal', c.target, 25 + skill * 2) end
    elseif d == 'splint' then
        local mins = SYS.splintHealMinutes * (1.0 - math.min(0.4, skill * 0.03))
        p.splint = os.time() + math.floor(mins * 60)
    elseif d == 'antibiotics' then st.food, st.cold = 0, 0
    elseif d == 'antiviral' then st.inf = 0.0
    elseif d == 'antiseptic' then
        if st.inf > 0 then st.inf = math.max(0.0, st.inf - 15.0) end
        if p.bleed == 1 then p.bleed = 0 end
    elseif d == 'painkillers' then st.pk = os.time() + math.floor((SYS.painkillerMinutes or 10) * 60)
    elseif d == 'saline' then st.blood = math.min(100.0, st.blood + 15.0)
    elseif d == 'transfusion' then st.blood = math.min(100.0, st.blood + 50.0 + skill)
    elseif d == 'surgery' then
        p.bullet, p.rebleed = false, 0
        if p.bleed > 0 then p.bleed = p.bleed - 1 end
    elseif d == 'defib' then
        MedicalDefibRevive(c.target)
    end
end

BSB.RegisterCallback('medical:treat', function(src, target, part, item)
    local job = pending[src]
    pending[src] = nil
    target = tonumber(target) or src
    if not job or job.target ~= target or job.part ~= part or job.item ~= item then
        return { ok = false, error = Lp(src, 'err_cannot_use') }
    end
    -- Finished too early to be real.
    if GetGameTimer() - job.at < job.ms * 0.85 then
        return { ok = false, error = Lp(src, 'err_cannot_use') }
    end
    local c, err = check(src, target, part, item)
    if not c then return { ok = false, error = Lp(src, 'err_' .. err) } end

    if not c.def.keep then exports.bs_inventory:RemoveItem(src, item, 1) end
    apply(src, c, part)
    if c.st == Med[c.target] then touch(c.target) end

    if c.other then
        exports.bs_core:AwardAction(src, 'wound_treated')
        notify(c.target, 'success', 'treated_by', { name = GetPlayerName(src) or '?' })
    end
    logMed(src, ('%s on %s (%s) target %s'):format(item, tostring(part), c.def.does, c.other and tostring(c.target) or 'self'))
    return { ok = true, message = Lp(src, 'done_' .. c.def.does), state = snapshot(Med[c.target] or newState()) }
end)

-- What the diagram needs.
BSB.RegisterCallback('medical:examine', function(src, target)
    target = tonumber(target) or src
    if not MedicalOn() then return { ok = false, error = Lp(src, 'err_system_off') } end
    if target ~= src and distance(src, target) > 4.0 then return { ok = false, error = Lp(src, 'err_too_far') } end
    local st = Med[target]
    if not st then return { ok = false, error = Lp(src, 'err_cannot_use') } end
    local p = exports.bs_core:GetPlayer(target)
    return { ok = true, target = target, self = target == src,
        name = target == src and nil or ((p and p.name) or GetPlayerName(target)),
        state = snapshot(st), skill = skillOf(src) }
end)

-- Using a medical item from the bag: bs_inventory asks first. True = we took
-- it (the medical tab opens), false = let the inventory do its old thing.
exports('InterceptUse', function(src, item)
    src = tonumber(src)
    if not MedicalOn() or not ITEMS[item] or not Med[src] then return false end
    if MedicalIsDown and MedicalIsDown(src) then return false end
    TriggerClientEvent('bs:medical:openTab', src, src, item)
    return true
end)

-- NPC doctors

local doctors = {}
CreateThread(function()
    Wait(2000)
    local zones = {}
    if GetResourceState('bs_zombies') == 'started' then
        local ok, list = pcall(function() return exports.bs_zombies:SafeZones() end)
        if ok and type(list) == 'table' then for _, z in ipairs(list) do zones[z.id] = z end end
    end
    for _, d in ipairs(Medical.Doctors or {}) do
        local z = zones[d.zone]
        if z then
            doctors[#doctors + 1] = { x = z.x + d.offset.x, y = z.y + d.offset.y, z = z.z + d.offset.z, h = d.heading or 0.0 }
        end
    end
    GlobalState.bsMedDoctors = doctors
end)

BSB.RegisterCallback('medical:doctor', function(src)
    if not MedicalOn() then return { ok = false, error = Lp(src, 'err_system_off') } end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false } end
    local at, near = GetEntityCoords(ped), false
    for _, d in ipairs(doctors) do
        if #(at - vector3(d.x, d.y, d.z)) <= 5.0 then near = true break end
    end
    if not near then return { ok = false, error = Lp(src, 'err_too_far') } end
    local price = math.floor(SYS.doctorPrice or 0)
    if price > 0 and not exports.bs_core:RemoveMoney(src, 'cash', price, 'medical doctor') then
        return { ok = false, error = Lp(src, 'err_money', { price = price }) }
    end
    MedicalClear(src)
    TriggerClientEvent('bs:medical:heal', src, 1000)
    logMed(src, ('doctor full heal for $%d'):format(price))
    return { ok = true, message = Lp(src, 'doctor_done') }
end)

exports('ClearConditions', function(src) return MedicalClear(src) end)
exports('Inflict', function(src, kind) return MedicalInflict(src, kind) end)
exports('GetConditions', function(src) return MedicalSnapshot(tonumber(src)) end)
exports('IsSystemOn', MedicalOn)
exports('Log', function(src, details) logMed(src, details) end)
