-- bs_fighting v3 - freeflow combat: light, heavy, counter, dodge, finishers, PvP.
-- Walker damage goes through bs_zombies' own server doors (bs:z:dmg, bs:z:hit 'execution').
-- Player hits go to our server, which caps them and tells the victim's client to react.

local S = Freeflow.Settings
local K = Freeflow.Keys
local refused = {}          -- [walkerId] = ms the server refused a finisher
local lastTired = 0
local cancelSwing = false
local heavy = { down = false, at = 0, used = false, token = 0 }
local chain = 0

local function now() return GetGameTimer() end

local function counterWindowMs()
    return math.floor(1000 * math.min(S.counterMax, S.counterBase + FF.Level() * S.counterPerLevel))
end

local function staminaOk()
    if FF.Stamina() >= S.minStamina then return true end
    if now() - lastTired > 1500 then lastTired = now(); FFHud.Flash('tired') end
    return false
end

local function keyLabel(cmd, fallback)
    local ok, s = pcall(function() return GetControlInstructionalButton(0, GetHashKey(cmd) | 0x80000000, true) end)
    if ok and type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    return fallback
end

-- Combo

local function setCombo(n)
    FF.combo = n
    FFHud.Combo(n)
end

local function resetCombo()
    if FF.combo ~= 0 then setCombo(0) end
    chain = 0
end
FF.ResetCombo = resetCombo

local function addCombo()
    local t = now()
    if t - FF.lastHitAt > S.comboResetMs then FF.combo = 0 end
    FF.lastHitAt = t
    setCombo(FF.combo + 1)
end

-- Landing a hit

local function feel(kind)
    local heavyish = kind ~= 'light'
    FFA.HitStop(heavyish and S.hitStopHeavy or S.hitStopLight)
    FFA.Shake(heavyish and S.shakeHeavy or S.shakeLight)
    FFHud.Impact(heavyish and 0.9 or 0.4)
end

local function staggerWalker(t, ms, held, kind)
    if t.kind ~= 'zombie' or not FF.Zombies() then return end
    pcall(function() exports.bs_zombies:SetStaggered(t.id, ms, held) end)
    -- not ours: the owner plays the stumble
    if not held and DoesEntityExist(t.ped) and NetworkGetEntityIsNetworked(t.ped) and not NetworkHasControlOfEntity(t.ped) then
        local a, b = GetEntityCoords(PlayerPedId()), GetEntityCoords(t.ped)
        local d = math.max(0.01, #(vector2(b.x - a.x, b.y - a.y)))
        TriggerServerEvent('bs:fighting:react', PedToNet(t.ped), kind == 'light' and 'stumble' or 'stagger', 0.0,
            (b.x - a.x) / d, (b.y - a.y) / d)
    end
end

local function reportWalker(t, kind, weaponHash)
    local me = PlayerPedId()
    local d = #(GetEntityCoords(t.ped) - GetEntityCoords(me))
    local point = GetEntityCoords(t.ped) + vector3(0.0, 0.0, 0.45)
    TriggerEvent('bs:z:localImpact', t.id, false, true, point)
    TriggerServerEvent('bs:z:dmg', t.id, 'torso', 0, weaponHash, d)
    TriggerServerEvent('bs:fighting:ffLanded', t.id, kind)
end

-- Is the target still in reach at the impact moment?
local function inReach(t, reach)
    if not t or not DoesEntityExist(t.ped) or IsEntityDead(t.ped) then return false end
    return #(GetEntityCoords(t.ped) - GetEntityCoords(PlayerPedId())) <= reach
end

local function land(t, kind, weaponHash, held, reach)
    if not inReach(t, reach) then return false end
    if t.kind == 'zombie' then
        reportWalker(t, kind, weaponHash)
        local ms = (kind == 'light' and S.staggerLight) or (kind == 'counter' and S.staggerCounter) or S.staggerHeavy
        staggerWalker(t, ms, held, kind)
    elseif t.kind == 'player' then
        TriggerServerEvent('bs:fighting:ffHitPlayer', t.id, kind == 'counter' and 'heavy' or kind, FF.combo + 1)
    end
    feel(kind)
    addCombo()
    return true
end

-- Runs one action on a thread; FF.busy covers it and every exit clears it
local endedAt = 0
local function run(fn)
    FF.busy = true
    cancelSwing = false
    FF.lastActionAt = now()
    CreateThread(function()
        -- never start a clip on the frame the last one ended
        if now() - endedAt < 20 then Wait(0) end
        local ok, err = pcall(fn)
        if not ok then
            print(('[bs_fighting] freeflow action failed: %s'):format(tostring(err)))
            ClearPedTasks(PlayerPedId())
            FFA.current = nil
        end
        FF.busy = false
        endedAt = now()
        FF.lastActionAt = now()
    end)
end

local function bandList(clips, kind, dist)
    return clips[kind] or clips.light
end

-- Light / heavy

local queuedAt = 0
local lastClip = nil
local function strike(kind)
    local me = PlayerPedId()
    if FF.busy and kind == 'light' then queuedAt = now() return end
    if not FF.CanFight(me) or FF.busy or not staminaOk() then return end
    local t = FF.Pick()
    if t and t.dist > S.lungeBand then
        -- too far for a short lunge: swing in place, but facing it
        local a, b = GetEntityCoords(me), GetEntityCoords(t.ped)
        SetEntityHeading(me, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
        t = nil
    end
    local class, weaponHash = FF.WeaponClass(me)
    local clips = FF.Clips(class)
    if kind == 'light' then chain = chain + 1 end
    run(function()
        FF.Spend(S.stamina[kind] or 6.0)
        local speed = kind == 'light' and S.lightSpeed or S.heavySpeed
        local portion = kind == 'light' and S.lightPortion or S.heavyPortion
        local list = bandList(clips, kind, t and t.dist or 0)
        local idx = kind == 'light' and chain or nil
        local cancel = function() return cancelSwing end
        if not t then
            local c = FFA.Pick(list, false, idx, lastClip)
            if c then lastClip = c.plyr; FFA.Strike(me, nil, c, { speed = speed, portion = portion, weapon = weaponHash, cancel = cancel }) end
            return
        end
        -- hold the walker first, so it stops walking before we close in
        local vped = (t.kind == 'zombie' and S.pairs) and FFA.Victim(t, 2500) or nil
        local c = (vped and FFA.Pick(list, true, idx, lastClip)) or FFA.Pick(list, false, idx, lastClip)
        if not c then FFA.Release(t) return end
        lastClip = c.plyr
        local gap = FFA.PairGap(c) or S.lungeStopGap
        local d = #(GetEntityCoords(t.ped) - GetEntityCoords(me))
        if d > gap + 0.25 and not FFA.Lunge(me, t.ped, gap) then FFA.Release(t) return end
        local reach = gap + 0.9
        FFA.Strike(me, t, c, {
            speed = speed, portion = portion, victimPed = vped, stagger = true, weapon = weaponHash,
            trackPed = t.ped, gap = gap, cancel = cancel,
            onImpact = function() land(t, kind, weaponHash, vped ~= nil, reach) end,
        })
        FFA.Release(t)
    end)
end

-- one light pressed near the end of a swing fires when it ends, so chains flow
CreateThread(function()
    while true do
        if queuedAt > 0 then
            if now() - queuedAt > 350 then queuedAt = 0
            elseif not FF.busy then queuedAt = 0; strike('light') end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

-- Finishers

local function canFinish(t)
    if not t or t.kind ~= 'zombie' or not DoesEntityExist(t.ped) or IsEntityDead(t.ped) then return false end
    if not (FF.Level() >= S.finisherLevel or FF.HasPerk(S.finisherPerk)) then return false end
    return FF.combo >= S.finisherCombo or FF.IsStaggered(t) or FF.IsDown(t)
end
FF.CanFinish = canFinish

local function behindOf(zed, me)
    local f = GetEntityForwardVector(zed)
    local d = GetEntityCoords(me) - GetEntityCoords(zed)
    local len = math.max(0.01, #(vector2(d.x, d.y)))
    return (f.x * d.x + f.y * d.y) / len <= -0.1
end

local function finisher(t)
    local me = PlayerPedId()
    local class, weaponHash = FF.WeaponClass(me)
    local clips = FF.Clips(class)
    run(function()
        local id = t.id
        local down = FF.IsDown(t)
        refused[id] = nil
        -- the server judges a finisher like a takedown: staggered first, then the start
        pcall(function() exports.bs_zombies:SetStaggered(id, 3000, true) end)
        -- sent once we are close (the server checks range on both)
        local function start()
            TriggerServerEvent('bs:z:staggered', id)
            TriggerServerEvent('bs:z:takedownStart', id)
        end
        LocalPlayer.state:set('bsTakedown', true, false)
        local function kill()
            if refused[id] then
                reportWalker(t, 'heavy', weaponHash)
            else
                TriggerServerEvent('bs:z:hit', id, 100000, true, 'execution')
                TriggerServerEvent('bs:fighting:ffFinisher', id)
            end
            feel('heavy')
            FFHud.Flash('finisher')
        end
        local ok, err = pcall(function()
            if down then
                local g = clips.ground or Freeflow.Clips.unarmed.ground
                local dist = #(GetEntityCoords(t.ped) - GetEntityCoords(me))
                if dist > 1.1 then FFA.Lunge(me, t.ped, 0.9) end
                start()
                local clip = dist < 0.7 and g.spot or g.front
                if not FFA.Strike(me, t, { dict = g.dict, plyr = clip, hitAt = g.hitAt }, { onImpact = kill }) then kill() end
            else
                local list = behindOf(t.ped, me) and clips.rear or clips.front
                local vped = FFA.Victim(t, 3000)
                -- never fall back to unarmed clips with a weapon in hand
                local c = (vped and FFA.Pick(list, true)) or FFA.Pick(list, false)
                    or (class == 'unarmed' and FFA.Pick(Freeflow.Clips.unarmed.front, false) or nil)
                if not c then start(); kill() return end
                local gap = FFA.PairGap(c) or S.lungeStopGap
                if t.dist > gap + 0.25 then FFA.Lunge(me, t.ped, gap) end
                start()
                if not FFA.Strike(me, t, c, { victimPed = vped, onImpact = kill }) then kill() end
            end
        end)
        LocalPlayer.state:set('bsTakedown', false, false)
        FFA.Release(t)
        resetCombo()
        FFHud.Finisher(false)
        if not ok then error(err) end
    end)
end

-- Counter

local function counter()
    local me = PlayerPedId()
    local w = FF.windup
    if not w or not FF.CanFight(me) then return end
    local t0 = now()
    if t0 < w.hitAt - counterWindowMs() or t0 > w.hitAt + 60 then return end
    if not staminaOk() then return end
    if FF.busy then cancelSwing = true end
    FF.windup = nil
    FFHud.Counter(false)
    -- stagger now: the walker's swing checks it before it lands
    pcall(function() exports.bs_zombies:SetStaggered(w.id, S.staggerCounter, true) end)
    CreateThread(function()
        local untilAt = now() + 200
        while FF.busy and now() < untilAt do Wait(0) end
        if FF.busy then return end
        local ped = w.ped
        if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
        local t = { ped = ped, kind = 'zombie', id = w.id, dist = #(GetEntityCoords(ped) - GetEntityCoords(me)) }
        FF.target = t
        local class, weaponHash = FF.WeaponClass(me)
        local clips = FF.Clips(class)
        run(function()
            FF.Spend(S.stamina.counter)
            -- side from where the walker stands
            local f = GetEntityForwardVector(me)
            local d = GetEntityCoords(ped) - GetEntityCoords(me)
            local side = (f.x * d.y - f.y * d.x) > 0 and 'l' or 'r'
            local set = clips.counter or Freeflow.Clips.unarmed.counter
            local c = set[side] or set.r
            if (not c or FFA.Ms(c.dict, c.plyr) <= 0) and class == 'unarmed' then c = Freeflow.Clips.unarmed.counter[side] end
            if not c then return end
            local vped = FFA.Victim(t, 2500)
            SetEntityHeading(me, GetHeadingFromVector_2d(d.x, d.y))
            FFHud.Flash('counter')
            FFA.Strike(me, t, c, { victimPed = vped, stagger = true, portion = S.heavyPortion,
                onImpact = function()
                    if S.counterDamage then land(t, 'counter', weaponHash, vped ~= nil, 2.6)
                    else feel('counter'); addCombo() end
                end })
            FFA.Release(t)
        end)
    end)
end

-- Dodge

local nextDodge = 0
local function dodge()
    local me = PlayerPedId()
    if not FF.CanFight(me) or not FF.InCombat() or FF.busy or now() < nextDodge then return end
    if FF.Stamina() < S.stamina.dodge then staminaOk() return end
    nextDodge = now() + S.dodgeCooldownMs
    local class = FF.WeaponClass(me)
    local d = FF.Clips(class).dodge or Freeflow.Clips.unarmed.dodge
    if FF.Clips(class).dodge == nil and class ~= 'unarmed' then return end
    local x = GetDisabledControlNormal(0, 30)
    local clip = (x < -0.3 and d.l) or (x > 0.3 and d.r) or d.c
    run(function()
        FF.Spend(S.stamina.dodge)
        pcall(function() exports.bs_skills:GrantEvade(S.dodgeIframesMs) end)
        if FF.windup then FF.windup = nil; FFHud.Counter(false) end
        FFHud.Flash('dodge')
        local ms = FFA.Solo(me, d.dict, clip, 1.0, 0.85)
        local untilAt = now() + ms
        while now() < untilAt do
            if IsPedRagdoll(me) or IsPedDeadOrDying(me, true) then break end
            Wait(0)
        end
        FFA.End(me, d.dict, clip)
    end)
end

-- Walker wind-up from bs_zombies (cl_attack, on the victim's client)

AddEventHandler('bs:z:windup', function(id, ms)
    if not S.enabled then return end
    id, ms = tonumber(id), tonumber(ms) or 420
    if not id then return end
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local ped
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(p) and #(GetEntityCoords(p) - at) < 4.0 then
            local ok, wid = pcall(function() return exports.bs_zombies:WalkerIdOf(p) end)
            if ok and wid == id then ped = p break end
        end
    end
    if not ped then return end
    FF.windup = { id = id, ped = ped, at = now(), hitAt = now() + ms }
end)

-- Counter prompt timing
CreateThread(function()
    local shown = false
    while true do
        local w = FF.windup
        local wait = 100
        if w then
            wait = 0
            local t = now()
            local openAt = w.hitAt - counterWindowMs()
            if t > w.hitAt + 60 then
                FF.windup = nil
                if shown then shown = false; FFHud.Counter(false) end
            elseif not shown and t >= openAt and FF.CanFight(PlayerPedId()) then
                shown = true
                FFHud.Counter(true, w.hitAt - t, keyLabel('+ff3_counter', 'Q'))
            end
        elseif shown then
            shown = false
            FFHud.Counter(false)
        end
        Wait(wait)
    end
end)

-- Finisher tag, combo timeout, combo break when we get hurt
CreateThread(function()
    local lastHp = GetEntityHealth(PlayerPedId())
    local ready = false
    while true do
        local me = PlayerPedId()
        local hp = GetEntityHealth(me)
        if hp < lastHp then resetCombo() end
        lastHp = hp
        if FF.combo > 0 and now() - FF.lastHitAt > S.comboResetMs then resetCombo() end
        local r = FF.InCombat() and FF.CanFight(me) and canFinish(FF.target) or false
        if r ~= ready then ready = r; FFHud.Finisher(r) end
        Wait(150)
    end
end)

-- Keys

-- Heavy key: tap = heavy (on release), hold heavyHoldMs = finisher if one is open, else heavy
local function heavyDown()
    if heavy.down then return end
    heavy.down, heavy.at, heavy.used = true, now(), false
    heavy.token = heavy.token + 1
    local token = heavy.token
    CreateThread(function()
        while heavy.down and heavy.token == token do
            if not heavy.used and now() - heavy.at >= S.heavyHoldMs then
                heavy.used = true
                local me = PlayerPedId()
                local t = FF.Pick()
                if t and t.dist <= S.lungeBand and not FF.busy and FF.CanFight(me) and canFinish(t) then
                    finisher(t)
                else
                    strike('heavy')
                end
                break
            end
            Wait(0)
        end
    end)
end

local function heavyUp()
    if not heavy.down then return end
    heavy.down = false
    if not heavy.used then heavy.used = true; strike('heavy') end
end

local function lockDown()
    if S.lockMode == 'hold' then FF.Lock() return end
    if FF.lock then FF.Unlock() else FF.Lock() end
end
local function lockUp()
    if S.lockMode == 'hold' then FF.Unlock() end
end

-- New command names, so bindings saved from the earlier layouts don't carry over
RegisterCommand('+ff3_light', function() strike('light') end, false)
RegisterCommand('-ff3_light', function() end, false)
RegisterCommand('+ff3_heavy', heavyDown, false)
RegisterCommand('-ff3_heavy', heavyUp, false)
RegisterCommand('+ff_lock', lockDown, false)
RegisterCommand('-ff_lock', lockUp, false)
RegisterCommand('+ff3_counter', counter, false)
RegisterCommand('-ff3_counter', function() end, false)
RegisterCommand('+ff_dodge', dodge, false)
RegisterCommand('-ff_dodge', function() end, false)
RegisterKeyMapping('+ff3_light', L('key.ff_light'), K.light.mapper, K.light.key)
RegisterKeyMapping('+ff3_heavy', L('key.ff_heavy'), K.heavy.mapper, K.heavy.key)
RegisterKeyMapping('+ff_lock', L('key.ff_lock'), K.lock.mapper, K.lock.key)
RegisterKeyMapping('+ff3_counter', L('key.ff_counter'), K.counter.mapper, K.counter.key)
RegisterKeyMapping('+ff_dodge', L('key.ff_dodge'), K.dodge.mapper, K.dodge.key)

-- GTA melee and melee lock-on stay off while we own the fight; jump is off in combat (Space dodges)
CreateThread(function()
    while true do
        local me = PlayerPedId()
        if S.enabled and S.disableNative and FF.CanFight(me) then
            DisableControlAction(0, 24, true);  DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true); DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true); DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true); DisableControlAction(0, 264, true)
            -- Q (cover) and R (reload) are ours while fists or a melee weapon are out
            DisableControlAction(0, 44, true);  DisableControlAction(0, 45, true)
            if FF.busy or FF.InCombat() then DisableControlAction(0, 22, true) end
            -- while a move runs the run input stays off, so locomotion never fights the clip
            if FF.busy then
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
            end
            Wait(0)
        else
            if heavy.down and not FF.CanFight(me) then heavy.down = false end
            if FF.lock and not FF.busy and not FF.CanFight(me) then FF.Unlock() end
            Wait(200)
        end
    end
end)

-- Server answers

RegisterNetEvent('bs:z:takedownRefused', function(id)
    id = tonumber(id)
    if id then refused[id] = now() end
end)

-- A walker we own was hit by someone else: stumble it here
RegisterNetEvent('bs:fighting:reactOwned', function(netId, kind)
    if not NetworkDoesNetworkIdExist(netId) or not FF.Zombies() then return end
    local ped = NetToPed(netId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local ok, id = pcall(function() return exports.bs_zombies:WalkerIdOf(ped) end)
    if not ok or not id then return end
    local ms = kind == 'stumble' and S.staggerLight or S.staggerHeavy
    pcall(function() exports.bs_zombies:SetStaggered(id, ms, false) end)
end)

-- A player hit us (server checked and capped). We play our own reaction; nobody else moves us.
RegisterNetEvent('bs:fighting:ffHit', function(data)
    if type(data) ~= 'table' then return end
    local me = PlayerPedId()
    if IsPedDeadOrDying(me, true) then return end
    local okD, dodging = pcall(function() return exports.bs_skills:IsDodging() end)
    if okD and dodging then FFHud.Flash('dodge') return end
    local dmg = math.max(0, math.floor(tonumber(data.dmg) or 0))
    if dmg > 0 then ApplyDamageToPed(me, dmg, false) end
    resetCombo()
    if FF.busy then cancelSwing = true end
    local r = Freeflow.PlayerReact[data.kind] or Freeflow.PlayerReact.light
    CreateThread(function()
        local from = data.from and GetPlayerFromServerId(data.from)
        local fp = (from and from ~= -1) and GetPlayerPed(from) or 0
        if fp ~= 0 then
            local a, b = GetEntityCoords(me), GetEntityCoords(fp)
            SetEntityHeading(me, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
        end
        if not IsPedRagdoll(me) then FFA.Solo(me, r.dict, r.clip, 1.0, math.min(1.0, (r.ms or 800) / math.max(1, FFA.Ms(r.dict, r.clip)))) end
    end)
end)

RegisterNetEvent('bs:fighting:state', function(st)
    if type(st) == 'table' and type(st.enabled) == 'boolean' then Fighting.Settings.enabled = st.enabled end
end)

-- /fightanims (staff, server side) asks every freeflow clip to be checked here
local function eachClip(fn)
    for class, set in pairs(Freeflow.Clips) do
        for slot, v in pairs(set) do
            if slot == 'ground' or slot == 'dodge' then
                for k, clip in pairs(v) do if k ~= 'dict' and k ~= 'hitAt' then fn(class, slot .. '.' .. k, v.dict, clip) end end
            elseif slot == 'counter' then
                for side, c in pairs(v) do fn(class, 'counter.' .. side, c.dict, c.plyr); if c.victim then fn(class, 'counter.' .. side .. '.victim', c.dict, c.victim) end end
            else
                for i, c in ipairs(v) do fn(class, slot .. i, c.dict, c.plyr); if c.victim then fn(class, slot .. i .. '.victim', c.dict, c.victim) end end
            end
        end
    end
end

RegisterNetEvent('bs:fighting:animCheck', function()
    CreateThread(function()
        local n, bad = 0, {}
        eachClip(function(class, slot, dict, clip)
            n = n + 1
            if FFA.Ms(dict, clip) <= 0 then bad[#bad + 1] = ('%s %s: %s / %s'):format(class, slot, dict, clip) end
        end)
        print(('[bs_fighting] freeflow clips: %d checked, %d missing'):format(n, #bad))
        for _, line in ipairs(bad) do print('  MISSING ' .. line) end
        TriggerEvent('bs:ui:notify', { type = #bad == 0 and 'success' or 'warn', message = L('fight.anim_check', { n = n, bad = #bad }), duration = 6000 })
    end)
end)

-- Preload, so the first swing and the debug menu don't wait on dicts
CreateThread(function()
    Wait(6000)
    local seen = {}
    eachClip(function(_, _, dict, clip)
        if not seen[dict] then seen[dict] = true; FFA.Load(dict) end
        FFA.Ms(dict, clip)
    end)
end)

-- Debug menu (bs_fpdebug): one block per weapon class, play any clip in place
local ORDER = { unarmed = 0, small_wpn = 1, large_wpn = 2, knife = 3 }
local debugIndex = {}
exports('DebugData', function()
    local styles, bad, byClass = {}, {}, {}
    debugIndex = {}
    eachClip(function(class, slot, dict, clip)
        local id = class .. ':' .. slot
        debugIndex[id] = { dict = dict, clip = clip }
        byClass[class] = byClass[class] or {}
        if not slot:find('victim', 1, true) then table.insert(byClass[class], { slot, id }) end
        local k = dict .. '/' .. clip
        if HasAnimDictLoaded(dict) and (GetAnimDuration(dict, clip) or 0) <= 0 then bad[#bad + 1] = id .. ' ' .. k end
    end)
    for class, slots in pairs(byClass) do
        table.sort(slots, function(a, b) return a[1] < b[1] end)
        styles[#styles + 1] = { id = class, order = ORDER[class] or 9, slots = slots }
    end
    table.sort(styles, function(a, b) return a.order < b.order end)
    table.sort(bad)
    return { styles = styles, weapon = {}, failed = bad }
end)

exports('DebugPlay', function(id)
    if not next(debugIndex) then eachClip(function(class, slot, dict, clip) debugIndex[class .. ':' .. slot] = { dict = dict, clip = clip } end) end
    local a = debugIndex[tostring(id)]
    if not a then return false end
    CreateThread(function()
        local me = PlayerPedId()
        local ms = FFA.Solo(me, a.dict, a.clip, 1.0, 1.0)
        Wait(ms)
        FFA.End(me, a.dict, a.clip)
    end)
    return true
end)

-- Never stuck

local function cleanup()
    SetTimeScale(1.0)
    heavy.down = false
    FF.windup = nil
    FF.target = nil
    FF.Unlock()
    resetCombo()
    FFHud.Counter(false)
    FFHud.Finisher(false)
    if LocalPlayer.state.bsTakedown and FF.busy then LocalPlayer.state:set('bsTakedown', false, false) end
end
AddEventHandler('bs:hook:player:unloaded', cleanup)
AddEventHandler('bs:hook:player:spawned', cleanup)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetTimeScale(1.0)
    if FF.busy then ClearPedTasks(PlayerPedId()) end
    if FF.busy and LocalPlayer.state.bsTakedown then LocalPlayer.state:set('bsTakedown', false, false) end
end)

-- a busy flag that outlives any clip is cleared
CreateThread(function()
    local since = 0
    while true do
        if FF.busy and not FF.testing then
            if since == 0 then since = now() elseif now() - since > 6000 then
                FF.busy = false
                SetTimeScale(1.0)
                ClearPedTasks(PlayerPedId())
                FFA.current = nil
                since = 0
            end
        else since = 0 end
        Wait(500)
    end
end)

RegisterCommand('fftest', function()
    local me = PlayerPedId()
    local class = FF.WeaponClass(me)
    print(('[bs_fighting] freeflow enabled=%s canFight=%s class=%s level=%d stamina=%.0f combo=%d window=%dms target=%s'):format(
        tostring(S.enabled), tostring(FF.CanFight(me)), tostring(class), FF.Level(), FF.Stamina(), FF.combo,
        counterWindowMs(), FF.target and (FF.target.kind .. ':' .. tostring(FF.target.id)) or 'none'))
    local bans = {}
    for k in pairs(FFA.bad) do bans[#bans + 1] = k end
    table.sort(bans)
    print(('  banned clips (%d): %s'):format(#bans, #bans > 0 and table.concat(bans, ', ') or 'none'))
    local ok = {}
    for k, f in pairs(FFA.verified) do ok[#ok + 1] = k .. '=' .. tostring(f) end
    table.sort(ok)
    print(('  learned clips (%d): %s'):format(#ok, #ok > 0 and table.concat(ok, ', ') or 'none'))
    print(('  lock=%s  tpose resets=%d'):format(FF.lock and (FF.lock.kind .. ':' .. tostring(FF.lock.id)) or 'none', FF.tposeResets or 0))
    -- pre = walker distance from where the pair wants it (we shift by this), scene = where it really is once playing
    for _, a in ipairs(FFA.align) do
        print(('  align %-5s err=%.2fm %s (%ds ago)'):format(a.kind, a.err, a.extra or '', math.floor((now() - a.at) / 1000)))
    end
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('fight.test_done'), duration = 3000 })
end, false)

exports('GetStyle', function() return 'freeflow' end)
exports('IsBlocking', function() return false end)
exports('IsBusy', function() return FF.busy == true end)

-- T-pose watchdog. Two symptoms: our clip dropped while we think it plays, or the bones show the pose
-- itself (both hands far out sideways at shoulder height) during or just after a fight move.
FF.tposeResets = 0
CreateThread(function()
    local missing, odd = 0, 0
    while true do
        local me = PlayerPedId()
        local cur = FFA.current
        local t = now()
        local wait = 250
        if cur and not cur.scene and t < cur.untilAt - 80 then
            wait = 100
            if not IsEntityPlayingAnim(me, cur.dict, cur.clip, 3) and not IsPedRagdoll(me) then missing = missing + 1 else missing = 0 end
        else
            missing = 0
        end
        if (FF.busy or cur or t - endedAt < 2000) and IsPedOnFoot(me) and not IsPedRagdoll(me)
            and not IsPedDeadOrDying(me, true) then
            wait = 100
            if FFA.IsTPose(me) then odd = odd + 1 else odd = 0 end
        else
            odd = 0
        end
        if FF.testing then missing, odd = 0, 0 end
        if missing >= 3 or odd >= 3 then
            FF.tposeResets = FF.tposeResets + 1
            local why = missing >= 3 and 'clip dropped' or 'T-pose bones'
            print(('[bs_fighting] pose reset (%s) during %s'):format(why, cur and (cur.dict .. '/' .. cur.clip) or 'nothing'))
            if odd >= 3 and cur then FFA.Ban(cur.dict .. '/' .. cur.clip, 'watchdog') end
            ClearPedTasks(me)
            FFA.current = nil
            missing, odd = 0, 0
            if FF.busy then cancelSwing = true end
        end
        Wait(wait)
    end
end)


-- /ffcliptest [all | unarmed | small_wpn | large_wpn | knife | <dict> <clip>] (staff, sent by the server).
-- Plays each clip on you with several flag sets and checks the bones: playing, T-pose, hands really moving.
-- Prints the Freeflow.SafeClips lines to paste; the results are also used for the rest of this session.
local SETS = {
    { id = 0,     label = 'full body' },
    { id = 2,     label = 'full body, hold' },
    { id = 'adv', label = 'advanced, full body' },
    { id = 48,    label = 'upper body over movement' },
}

local function testOne(ped, dict, clip, set, dur)
    local home, hdg = GetEntityCoords(ped), GetEntityHeading(ped)
    ClearPedTasks(ped)
    Wait(300)
    if set.id == 'adv' then
        TaskPlayAnimAdvanced(ped, dict, clip, home.x, home.y, home.z, 0.0, 0.0, hdg, 8.0, -4.0, -1, 0, 0.0, 0, 0)
    else
        TaskPlayAnim(ped, dict, clip, 8.0, -4.0, -1, set.id, 0.0, false, false, false)
    end
    local t0 = now()
    local span = math.min(1500, math.max(600, math.floor(dur * 1000)))
    local frames, playing, tpose, moved = 0, 0, 0, 0.0
    local firstL, firstR
    while now() - t0 < span do
        Wait(0)
        frames = frames + 1
        if IsEntityPlayingAnim(ped, dict, clip, 3) then playing = playing + 1 end
        if now() - t0 > 120 then
            if FFA.IsTPose(ped) then tpose = tpose + 1 end
            local l, r = FFA.Hands(ped)
            if not firstL then firstL, firstR = l, r end
            moved = math.max(moved, #(l - firstL), #(r - firstR))
        end
    end
    StopAnimTask(ped, dict, clip, 4.0)
    ClearPedTasks(ped)
    Wait(200)
    SetEntityCoordsNoOffset(ped, home.x, home.y, home.z, false, false, false)
    SetEntityHeading(ped, hdg)
    if playing < frames * 0.5 then return 'NOT PLAYING', playing, frames, tpose, moved end
    if tpose > 2 then return 'T-POSE', playing, frames, tpose, moved end
    if moved < 0.05 then return 'STATIC', playing, frames, tpose, moved end
    return 'OK', playing, frames, tpose, moved
end

local function testClip(dict, clip, lines)
    local key = dict .. '/' .. clip
    if not FFA.Load(dict) then print(('^1  %s: dict does not load^7'):format(key)) lines[#lines + 1] = ("    ['%s'] = false,"):format(key) return end
    local dur = GetAnimDuration(dict, clip) or 0.0
    if dur <= 0.0 then print(('^1  %s: clip not in dict^7'):format(key)) lines[#lines + 1] = ("    ['%s'] = false,"):format(key) return end
    local ped = PlayerPedId()
    print(('^3[ffcliptest] %s (%.2fs)^7'):format(key, dur))
    local best
    for _, set in ipairs(SETS) do
        local ok, verdict, playing, frames, tpose, moved = pcall(testOne, ped, dict, clip, set, dur)
        if not ok then verdict, playing, frames, tpose, moved = 'ERROR ' .. tostring(verdict), 0, 1, 0, 0.0 end
        print(('  %-4s %-26s %-12s playing %d/%d  tpose %d  hands moved %.2f m'):format(tostring(set.id), set.label, verdict, playing, frames, tpose, moved))
        if verdict == 'OK' and best == nil then best = set.id end
    end
    if best ~= nil then
        FFA.verified[key], FFA.bad[key] = best, nil
        lines[#lines + 1] = ("    ['%s'] = %s,"):format(key, type(best) == 'string' and ("'" .. best .. "'") or tostring(best))
    else
        FFA.Ban(key, '/ffcliptest')
        lines[#lines + 1] = ("    ['%s'] = false,"):format(key)
    end
end

RegisterNetEvent('bs:fighting:cliptest', function(a, b)
    if FF.busy or FF.testing then return print('^3[ffcliptest] finish the current move first^7') end
    CreateThread(function()
        local list = {}
        if a and b and a ~= '' and b ~= '' and Freeflow.Clips[a] == nil then
            list[1] = { a, b }
        else
            local seen = {}
            eachClip(function(class, _, dict, clip)
                if (not a or a == '' or a == 'all' or a == class) and not seen[dict .. clip] then
                    seen[dict .. clip] = true
                    list[#list + 1] = { dict, clip }
                end
            end)
            table.sort(list, function(x, y) return x[1] .. x[2] < y[1] .. y[2] end)
        end
        FF.testing, FF.busy = true, true
        FF.Unlock()
        print(('^3[ffcliptest] %d clips, about %d s. Stand still in open ground, fists out.^7'):format(#list, #list * 7))
        local lines = {}
        for _, c in ipairs(list) do testClip(c[1], c[2], lines) end
        FF.testing, FF.busy = false, false
        print('^2[ffcliptest] paste into Freeflow.SafeClips (config/config_freeflow.lua):^7')
        for _, l in ipairs(lines) do print(l) end
        TriggerEvent('bs:ui:notify', { type = 'info', message = L('fight.test_done'), duration = 4000 })
    end)
end)
