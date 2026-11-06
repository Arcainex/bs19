-- bs_fighting - the fight: tap attack for lights, hold for a charged heavy, kick key, guard/parry on the right mouse,
-- stomp anything on the ground, takedowns from behind (Soldier). Walker hits use bs_zombies' own doors
-- (bs:z:dmg, bs:z:hit 'execution'); player hits are capped by our server before the victim takes anything.

Fight = {
    style = 'untrained', styles = { untrained = true }, level = 0,
    chain = 0, combo = 0, lastHitAt = 0, busyUntil = 0, staggerUntil = 0,
    blocking = false, blockAt = 0, counterUntil = 0, nextTakedown = 0,
    holding = false, holdAt = 0, charging = false, queued = false,
    lastSwitchAt = 0, lastActionAt = 0, guardAnim = nil,
}

local S = Fighting.Settings
local UNARMED = `WEAPON_UNARMED`
local GROUP_MELEE, GROUP_UNARMED = `GROUP_MELEE`, `GROUP_UNARMED`
local lastComplaint = 0

local function has(flag)
    local ok, v = pcall(function() return exports.bs_skills:HasFlag(flag) end)
    return ok and v == true
end
Fight.Has = has

local function level()
    local ok, v = pcall(function() return exports.bs_skills:GetSkillLevel('fighting') end)
    if ok and type(v) == 'number' then Fight.level = v end
    return Fight.level
end

local function style() return Fighting.Styles[Fight.style] or Fighting.Styles.untrained end
Fight.StyleDef = style

local function complain(key, vars)
    local now = GetGameTimer()
    if now - lastComplaint < 2500 then return end
    lastComplaint = now
    TriggerEvent('bs:ui:notify', { type = 'warn', message = L(key, vars), duration = 2400 })
end

local function stamina()
    local ok, n = pcall(function() return exports.bs_core:GetNeeds() end)
    return (ok and type(n) == 'table' and tonumber(n.stamina)) or 100.0
end
Fight.Stamina = stamina

local function spend(cost) pcall(function() exports.bs_core:AdjustStamina(-cost) end) end
Fight.Spend = spend

-- 'fists' | 'one' | 'two' | 'knife' | nil (gun or nothing we handle), plus the weapon hash
local function weaponClass(ped)
    local w = GetSelectedPedWeapon(ped)
    if w == 0 or w == UNARMED then return 'fists', UNARMED end
    local known = Fighting.ClassOfHash(w)
    if known then return known, w end
    local g = GetWeapontypeGroup(w)
    if g == GROUP_UNARMED then return 'fists', w end
    if g == GROUP_MELEE then return 'one', w end
    return nil, w
end
Fight.WeaponClass = weaponClass

local function dodging()
    local ok, v = pcall(function() return exports.bs_skills:IsDodging() end)
    return ok and v == true
end

function Fight.CanFight(ped)
    if not S.enabled then return false end
    if IsNuiFocused() or IsPauseMenuActive() then return false end
    if IsPedInAnyVehicle(ped, true) or not IsPedOnFoot(ped) then return false end
    if IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or IsPedGettingUp(ped) then return false end
    if IsPedSwimming(ped) or IsPedFalling(ped) or IsPedClimbing(ped) or IsPedCuffed(ped) then return false end
    if LocalPlayer.state.bsDowned or IsEntityAttached(ped) then return false end
    -- other systems that own the mouse or the body right now
    local ls = LocalPlayer.state
    if ls.bsDrone or ls.bsSitting or ls.bsTakedown or (type(ls.bsParkour) == 'table' and ls.bsParkour.active) then return false end
    if GetResourceState('bs_building') == 'started' then
        local ok, placing = pcall(function() return exports.bs_building:IsPlacing() end)
        if ok and placing then return false end
    end
    local class=weaponClass(ped)
    if not class then return false end
    -- A fresh survivor keeps GTA's basic weapon swings until a fighting style is learned.
    if class~='fists'and Fight.style=='untrained'then return false end
    if class~='fists'and not FightAnim.WeaponReady(Fight.style,class)then return false end
    return true
end

-- Targets

local function flatDot(ped, to)
    local f = GetEntityForwardVector(ped)
    local d = to - GetEntityCoords(ped)
    local len = #(vector2(d.x, d.y))
    if len < 0.01 then return 1.0 end
    return (f.x * d.x + f.y * d.y) / len
end

local function classify(p)
    if IsPedAPlayer(p) then
        local idx = NetworkGetPlayerIndexFromPed(p)
        if idx and idx ~= -1 then return 'player', GetPlayerServerId(idx) end
        return nil
    end
    local tid = FightTrainers and FightTrainers.SparTarget and FightTrainers.SparTarget(p)
    if tid then return 'trainer', tid end
    if GetResourceState('bs_zombies') == 'started' then
        local ok, id = pcall(function() return exports.bs_zombies:WalkerIdOf(p) end)
        if ok and id then return 'zombie', id end
    end
    return nil
end

local function isDown(p, kind)
    if IsPedRagdoll(p) or IsPedGettingUp(p) then return true end
    if kind == 'zombie' and GetResourceState('bs_zombies') == 'started' then
        local ok, c = pcall(function() return exports.bs_zombies:IsCrawlerPed(p) end)
        if ok and c then return true end
    end
    return false
end

-- Targets in a cone, nearest first.
function Fight.Targets(range, halfAngle, all, wantDown)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    halfAngle = halfAngle or S.hitHalfAngle
    local cos = math.cos(math.rad(halfAngle))
    local out = {}
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= me and DoesEntityExist(p) and not IsEntityDead(p) then
            local to = GetEntityCoords(p)
            local d = #(to - at)
            if d <= range and math.abs(to.z - at.z) < 2.0 and (halfAngle >= 180 or flatDot(me, to) >= cos) then
                local kind, id = classify(p)
                if kind then
                    local down = isDown(p, kind)
                    if wantDown == nil or wantDown == down then
                        out[#out + 1] = { ped = p, kind = kind, id = id, dist = d, down = down }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    if all then return out end
    return out[1] and { out[1] } or {}
end

local function behind(me, target)
    local tf = GetEntityForwardVector(target)
    local d = GetEntityCoords(me) - GetEntityCoords(target)
    local len = #(vector2(d.x, d.y))
    if len < 0.01 then return false end
    return (tf.x * d.x + tf.y * d.y) / len <= (S.takedownBehindDot or -0.3)
end

local function stompTarget()
    local range = S.stompRange * (has('fight_stomp') and 1.3 or 1.0)
    return Fight.Targets(range, 80.0, false, true)[1]
end

local function takedownTarget()
    if not style().takedowns then return nil end
    local t = Fight.Targets(S.takedownRange, 70.0, false, false)[1]
    if t and (t.kind == 'zombie' or t.kind == 'player') and behind(PlayerPedId(), t.ped) then return t end
    return nil
end

-- Swings go where you look: snap to the nearest target in front of the camera, else to the camera heading.
local function faceAim(reach, target)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local tp = target and target.ped
    if not tp then
        local rot = GetGameplayCamRot(2)
        local rz = math.rad(rot.z)
        local cx, cy = -math.sin(rz), math.cos(rz)
        local best, bestD
        for _, p in ipairs(GetGamePool('CPed')) do
            if p ~= me and not IsEntityDead(p) then
                local to = GetEntityCoords(p)
                local d = #(to - at)
                if d <= reach + 0.8 and math.abs(to.z - at.z) < 2.0 then
                    local dx, dy = (to.x - at.x) / math.max(d, 0.01), (to.y - at.y) / math.max(d, 0.01)
                    if dx * cx + dy * cy > 0.55 and (not bestD or d < bestD) and classify(p) then best, bestD = p, d end
                end
            end
        end
        tp = best
        if not tp then SetEntityHeading(me, rot.z) return end
    end
    local to = GetEntityCoords(tp)
    SetEntityHeading(me, GetHeadingFromVector_2d(to.x - at.x, to.y - at.y))
end

-- Feel: hit-stop, shake, slow-down, sound

local function impact(a, kind, strength)
    local st = style()
    local hs = (kind == 'heavy' and S.hitStopHeavy) or (kind == 'kick' and S.hitStopKick) or S.hitStopLight
    FightAnim.Freeze(a, math.floor(hs * (st.hitStop or 1.0)))
    local amp = ((kind == 'light') and S.shakeLight or S.shakeHeavy) * (st.shake or 1.0)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', amp)
    if S.timeScaleOnHeavy and (kind == 'heavy' or kind == 'kick' or kind == 'stomp') then
        SetTimeScale(S.timeScale or 0.35)
        SetTimeout(S.timeScaleMs or 70, function() SetTimeScale(1.0) end)
    end
    FightHud.Impact(strength)
end

-- Landing

local function reactFor(move, kind, charge, tired)
    local r = move.react or 'stumble'
    if kind == 'heavy' and style().weaponDown and Fight.class ~= 'fists' then r = 'down' end
    if kind == 'heavy' and charge and charge < 0.5 and (r == 'down' or r == 'throw') then r = 'stagger' end
    if tired then
        if r == 'down' or r == 'throw' then r = 'stagger' elseif r == 'stagger' then r = 'stumble' end
    end
    return r
end

local function hitZombie(t, moveId, move, kind, opts, weaponHash)
    local n = move.zHits or 1
    if kind == 'heavy' then
        n = Fighting.Zombies.heavyHits or n
        if (opts.charge or 1) < 0.95 then n = math.max(1, n - 1) end
    end
    if moveId == 'kn_light' and has('sol_knife') then n = n + 1 end
    if moveId == 'kick_low' and has('sol_breaker') then n = 2 end
    if opts.tired then n = math.min(n, 1) end
    local region = move.region or 'torso'
    for i = 1, n do
        TriggerServerEvent('bs:z:dmg', t.id, region, 0, weaponHash, t.dist)
        if i < n then Wait(40) end
    end
    TriggerServerEvent('bs:fighting:struck', t.id, moveId)
end

local function land(moveId, kind, opts)
    local move = Fighting.Moves[moveId]
    local me = PlayerPedId()
    local class, weaponHash = weaponClass(me)
    local wc = Fighting.WeaponClasses[class or 'fists'] or Fighting.WeaponClasses.fists
    local reach = move.reach or wc.reach
    local aoe = (moveId == 'dropkick' or moveId == 'haymaker') and has('brw_bulldozer')
    local targets = Fight.Targets(reach, aoe and 75.0 or S.hitHalfAngle, aoe, false)
    local react = reactFor(move, kind, opts.charge, opts.tired)
    local force = (move.push or 0) * ((moveId == 'throw' and has('grp_throw')) and 1.5 or 1.0)
    local landed = 0
    for _, t in ipairs(targets) do
        if FightContact.Test(me,t.ped,class,kind)then
        local offset = GetEntityCoords(t.ped) - GetEntityCoords(me)
        local length = math.max(0.01, #(vector2(offset.x, offset.y)))
        local hitX, hitY = offset.x / length, offset.y / length
        if t.kind == 'zombie' and Fighting.Zombies.enabled then
            CreateThread(function() hitZombie(t, moveId, move, kind, opts, weaponHash) end)
            if Fighting.Zombies.knockdowns or (react ~= 'down' and react ~= 'throw') then
                FightReact.Request(t.ped, react, force, hitX, hitY)
            end
            if moveId == 'throw' then Fight.ThrowInto(t.ped, vector3(hitX, hitY, 0.0)) end
            landed = landed + 1
        elseif t.kind == 'player' and Fighting.PvP.enabled then
            local id = moveId
            if moveId == 'throw' and style().choke and (opts.charge or 0) >= 0.95 then id = 'choke' end
            TriggerServerEvent('bs:fighting:hitPlayer', t.id, id, Fight.combo + 1, opts.counter == true, opts.charge, opts.tired == true)
            if id == 'choke' then
                local a = FightAnim.Play(me, 'choke', { flag = 1, loop = true })
                Fight.busyUntil = GetGameTimer() + (Fighting.PvP.chokeMs or 4200)
                SetTimeout(Fighting.PvP.chokeMs or 4200, function() FightAnim.Stop(a, 4.0) end)
            end
            landed = landed + 1
        elseif t.kind == 'trainer' then
            TriggerServerEvent('bs:fighting:sparHit', t.id, moveId)
            FightReact.Ped(t.ped, react == 'down' and 'stagger' or react, force, hitX, hitY)
            landed = landed + 1
        end
        end
    end
    return landed
end

-- Grappler throw: whoever the thrown body crashes into goes down too.
function Fight.ThrowInto(thrown, f)
    CreateThread(function()
        local hit, untilAt = { [thrown] = true, [PlayerPedId()] = true }, GetGameTimer() + 900
        while GetGameTimer() < untilAt and DoesEntityExist(thrown) do
            local at = GetEntityCoords(thrown)
            for _, p in ipairs(GetGamePool('CPed')) do
                if not hit[p] and not IsEntityDead(p) and #(GetEntityCoords(p) - at) < 1.3 then
                    hit[p] = true
                    local kind = classify(p)
                    if kind == 'zombie' then FightReact.Request(p, 'down', 3.0, f.x, f.y) end
                end
            end
            Wait(50)
        end
    end)
end

-- One swing. kind = 'light' | 'heavy' | 'kick' | 'stomp' | 'takedown'
local function swing(kind, moveId, opts)
    opts = opts or {}
    local me = PlayerPedId()
    local st = style()
    local move = Fighting.Moves[moveId]
    if not move then return false end
    local lvl = level()

    local cost = Fighting.Math.Stamina(kind, Fight.style, lvl, has, opts.charge)
    local have = stamina()
    if have < 1.0 and kind ~= 'light' then complain('fight.tired') return false end
    opts.tired = have < (S.tiredAt or 20.0)
    local class,attackWeapon = weaponClass(me)
    Fight.class = class
    local wc = Fighting.WeaponClasses[class or 'fists'] or Fighting.WeaponClasses.fists
    local speed = (st.speed or 1.0) * (wc.speed or 1.0)
    if kind == 'light' and has('box_quick_hands') then speed = speed * 1.15 end
    if opts.tired then speed = speed * (S.tiredSpeed or 0.72) end
    if kind == 'stomp' or kind == 'takedown' then speed = 1.0 end

    faceAim(Fighting.Moves[moveId].reach or wc.reach, opts.target)
    local moving = GetEntitySpeed(me) > 1.0
    local flag = (kind == 'light' and moving) and 48 or 0
    local a = FightAnim.Play(me, moveId, { flag = flag, speed = speed })
    if not a then return false end
    spend(cost)
    local token = {}; Fight.attackToken = token; Fight.attackAnim = a
    local ms = a.ms
    FightAnim.Guard(a)
    FightContact.Begin()
    local now = GetGameTimer()
    Fight.busyUntil = now + ms
    Fight.lastActionAt = now
    FightHud.Active(true)

    CreateThread(function()
        local contactAt=math.floor(ms*(move.hitAt or .5))
        Wait(opts.target and contactAt or math.max(0,contactAt-60))
        if Fight.attackToken ~= token or PlayerPedId() ~= me or GetSelectedPedWeapon(me)~=attackWeapon or not Fight.CanFight(me) then return end
        local landed=0
        if opts.target then
            landed = opts.onHit(opts.target) and 1 or 0
        else
            local untilAt=GetGameTimer()+math.max(60,math.min(300,S.contactWindowMs or 180))
            repeat
                if Fight.attackToken~=token or PlayerPedId()~=me or GetSelectedPedWeapon(me)~=attackWeapon or not Fight.CanFight(me)then return end
                landed=land(moveId,kind,opts)
                if landed>0 then break end
                Wait(0)
            until GetGameTimer()>=untilAt
        end
        if landed > 0 then
            impact(a, kind, (kind == 'light') and 0.35 or 0.9)
            local t = GetGameTimer()
            if t - Fight.lastHitAt <= S.comboWindowMs + ms then Fight.combo = Fight.combo + 1 else Fight.combo = 1 end
            Fight.lastHitAt = t
            FightHud.Combo(Fight.combo)
            if opts.counter then FightHud.Flash('counter') end
            if (move.react == 'down' or kind == 'stomp') and has('fight_second_wind') then spend(-6.0) end
        end
    end)
    return true
end

local function ready()
    local now = GetGameTimer()
    return now >= Fight.busyUntil and now >= Fight.staggerUntil
end

local function counterReady()
    if GetGameTimer() < Fight.counterUntil then Fight.counterUntil = 0 return true end
    return false
end

-- Moves

local function doStomp(t)
    local class = weaponClass(PlayerPedId())
    local moveId = Fighting.MoveFor(Fight.style, class, 'stomp')
    return swing('stomp', moveId, { target = t, onHit = function(tg)
        if tg.kind == 'zombie' then
            local _, w = weaponClass(PlayerPedId())
            if Fighting.Zombies.stompKills then
                TriggerServerEvent('bs:z:dmg', tg.id, 'head', 1, w, tg.dist)
            else
                TriggerServerEvent('bs:z:dmg', tg.id, 'torso', 0, w, tg.dist)
            end
            TriggerServerEvent('bs:fighting:struck', tg.id, moveId)
        elseif tg.kind == 'player' then
            TriggerServerEvent('bs:fighting:stomp', tg.id)
        elseif tg.kind == 'trainer' then
            TriggerServerEvent('bs:fighting:sparHit', tg.id, moveId)
        end
        return true
    end })
end

local function doTakedown(t)
    local now = GetGameTimer()
    if now < Fight.nextTakedown then return false end
    Fight.nextTakedown = now + math.floor(S.takedownCooldownMs * (has('sol_silent') and 0.5 or 1.0))
    local class = weaponClass(PlayerPedId())
    local moveId = Fighting.MoveFor(Fight.style, class, 'takedown')
    if t.kind == 'zombie' and Fighting.Zombies.takedowns and GetResourceState('bs_zombies') == 'started' then
        -- One takedown for walkers: same paired clips and server check as the ALT menu option
        local ok, started = pcall(function() return exports.bs_zombies:Takedown(t.ped) end)
        if ok then
            if started then TriggerServerEvent('bs:fighting:struck', t.id, moveId) else Fight.nextTakedown = now end
            return started
        end
        TriggerServerEvent('bs:z:takedownStart', t.id)
    end
    return swing('takedown', moveId, { target = t, onHit = function(tg)
        if tg.kind == 'zombie' and Fighting.Zombies.takedowns then
            -- same server door and checks as the E execution
            TriggerServerEvent('bs:z:hit', tg.id, 100000, true, 'execution')
            TriggerServerEvent('bs:fighting:struck', tg.id, 'takedown')
        elseif tg.kind == 'player' and Fighting.PvP.enabled then
            TriggerServerEvent('bs:fighting:takedown', tg.id)
        end
        return true
    end })
end

function Fight.Light()
    local me = PlayerPedId()
    if not ready() then
        -- one press buffered near the end of a swing keeps chains smooth
        if Fight.busyUntil - GetGameTimer() < 220 then Fight.queued = true end
        return
    end
    if GetGameTimer() - Fight.lastHitAt > S.comboWindowMs * 1.6 then Fight.chain = 0; Fight.combo = 0 end
    local class = weaponClass(me)
    if counterReady() and class == 'fists' then
        swing('light', 'counter', { counter = true })
        return
    end
    Fight.chain = Fight.chain + 1
    local moveId = Fighting.MoveFor(Fight.style, class, 'light', Fight.chain)
    swing('light', moveId, { counter = false })
end

function Fight.Heavy(charge)
    if not ready() then return end
    local class = weaponClass(PlayerPedId())
    local moveId = Fighting.MoveFor(Fight.style, class, 'heavy')
    if swing('heavy', moveId, { charge = charge, counter = counterReady() }) then Fight.chain = 0 end
end

function Fight.Kick()
    local me = PlayerPedId()
    if not Fight.CanFight(me) or Fight.blocking or not ready() then return end
    local t = stompTarget()
    if t then doStomp(t) return end
    local class = weaponClass(me)
    swing('kick', Fighting.MoveFor(Fight.style, class, 'kick'), { counter = counterReady() })
end

-- Attack key: press decides context, release decides light or heavy.
local function attackDown()
    local me = PlayerPedId()
    if not Fight.CanFight(me) or Fight.blocking then return end
    if ready() then
        local t = stompTarget()
        if t then doStomp(t) return end
        t = takedownTarget()
        if t and doTakedown(t) then return end
    end
    if Fight.holding then return end
    Fight.holding, Fight.charging = true, false
    local token = {}; Fight.holdToken = token
    Fight.holdAt = GetGameTimer()
    CreateThread(function()
        local full = S.chargeFullMs * (has('brw_heavy_hands') and 0.65 or 1.0)
        while Fight.holding and Fight.holdToken == token do
            local held = GetGameTimer() - Fight.holdAt
            if held >= S.holdHeavyMs then
                Fight.charging = true
                FightHud.Charge(math.min(1.0, (held - S.holdHeavyMs) / full))
                if held > 4000 or not Fight.CanFight(me) then
                    Fight.holding, Fight.charging = false, false
                    break
                end
            end
            Wait(0)
        end
        -- charging blocks sprint every frame, so it must never outlive the hold
        if Fight.holdToken == token then
            if not Fight.holding then Fight.charging = false end
            FightHud.Charge(nil)
        end
    end)
end

local function attackUp()
    Fight.charging = false
    if not Fight.holding then return end
    Fight.holding = false
    local held = GetGameTimer() - Fight.holdAt
    if not Fight.CanFight(PlayerPedId()) or Fight.blocking then return end
    if held >= S.holdHeavyMs then
        local full = S.chargeFullMs * (has('brw_heavy_hands') and 0.65 or 1.0)
        Fight.Heavy(math.min(1.0, (held - S.holdHeavyMs) / full))
    else
        Fight.Light()
    end
end

-- buffered light
CreateThread(function()
    while true do
        if Fight.queued and ready() then
            Fight.queued = false
            if Fight.CanFight(PlayerPedId()) and not Fight.blocking then Fight.Light() end
        end
        Wait(Fight.queued and 0 or 100)
    end
end)

-- Guard

local function guardOn()
    local me = PlayerPedId()
    if not Fight.CanFight(me) then return end
    Fight.blocking = true
    Fight.holding, Fight.charging = false, false
    Fight.blockAt = GetGameTimer()
    Fight.lastActionAt = Fight.blockAt
    FightHud.Active(true)
    if weaponClass(me) == 'fists' then
        Fight.guardAnim = FightAnim.Play(me, 'guard', { flag = 49, loop = true, blendIn = 8.0 })
    end
end

local function guardOff()
    Fight.blocking = false
    if Fight.guardAnim then FightAnim.Stop(Fight.guardAnim, 6.0); Fight.guardAnim = nil end
end
Fight.GuardOff = guardOff

function Fight.ParryWindow()
    local w = (S.parryWindowMs + level() * (S.parryPerLevelMs or 0)) * (style().parry or 1.0)
    return math.min(S.parryMaxMs or 400, w)
end

-- Incoming hit from a player (server checked and capped).
RegisterNetEvent('bs:fighting:hit', function(data)
    if type(data) ~= 'table' then return end
    local me = PlayerPedId()
    if IsPedDeadOrDying(me, true) then return end
    local dmg = math.max(0, math.floor(tonumber(data.dmg) or 0))
    local now = GetGameTimer()
    local from = data.from and GetPlayerFromServerId(data.from)
    local fromPed = (from and from ~= -1) and GetPlayerPed(from) or 0
    local react = data.react

    if data.kind == 'hit' and dodging() then FightHud.Flash('escape') return end

    local facing = fromPed ~= 0 and flatDot(me, GetEntityCoords(fromPed)) > 0.2
    if Fight.blocking and facing and data.kind == 'hit' then
        if now - Fight.blockAt <= Fight.ParryWindow() then
            FightHud.Flash('parry')
            local what = style().parryDo or 'none'
            if what == 'counter' then Fight.counterUntil = now + S.counterWindowMs * (has('box_counter') and 1.4 or 1.0) end
            if has('box_slip') then spend(-8.0) end
            TriggerServerEvent('bs:fighting:parried', data.from, what)
            FightHud.Impact(0.3)
            return
        end
        local cost = S.staminaBlockHit * (has('fight_iron_guard') and 0.5 or 1.0)
        if stamina() >= cost then
            spend(cost)
            local through = has('brw_thick_skin') and math.min(0.10, style().guard or 0.3) or (style().guard or S.blockReduce)
            dmg = math.floor(dmg * through + 0.5)
            react = (react == 'down' or react == 'throw') and 'stumble' or 'none'
            FightHud.Flash('block')
            FightHud.Impact(0.2)
        else
            FightHud.Flash('broken')
            guardOff()
        end
    end

    if dmg > 0 then ApplyDamageToPed(me, dmg, false) end
    if react and react ~= 'none' then FightReact.Self(react, tonumber(data.force) or 0, fromPed) end
    if data.disarm then Fight.Disarm() end
end)

function Fight.Disarm()
    local me = PlayerPedId()
    local _, w = GetCurrentPedWeapon(me, true)
    if w and w ~= UNARMED then
        if GetResourceState('bs_weapons') == 'started' then
            pcall(function() exports.bs_weapons:Holster() end)
        else
            SetCurrentPedWeapon(me, UNARMED, true)
        end
    end
end

-- Our swing got parried: recoil, and whatever the defender's style does.
RegisterNetEvent('bs:fighting:staggered', function(what)
    local me = PlayerPedId()
    Fight.staggerUntil = GetGameTimer() + 750
    Fight.combo, Fight.chain = 0, 0
    FightHud.Combo(0)
    FightHud.Flash('broken')
    local a = FightAnim.Play(me, 'recoil', { flag = 0, portion = 0.8 })
    FightAnim.Guard(a)
    if what == 'disarm' then Fight.Disarm()
    elseif what == 'shove' then FightReact.Self('stagger', 0) end
end)

-- A dodge opens the counter window with Footwork.
AddEventHandler('bs:skills:dodged', function()
    if S.enabled and has('fight_footwork') then Fight.counterUntil = GetGameTimer() + S.counterWindowMs end
end)

-- Styles

function Fight.SetStyle(id, quiet)
    if not Fighting.Styles[id] or not Fight.styles[id] then return false end
    local now = GetGameTimer()
    if not quiet and now - Fight.lastSwitchAt < S.switchCooldownMs then return false end
    Fight.lastSwitchAt = now
    Fight.style = id
    Fight.combo, Fight.chain = 0, 0
    if not quiet then
        TriggerServerEvent('bs:fighting:setStyle', id)
        FightHud.Style(id, true)
    end
    return true
end

local function cycleStyle()
    local ids = Fighting.StyleIds()
    local start = 1
    for i, id in ipairs(ids) do if id == Fight.style then start = i break end end
    for step = 1, #ids do
        local id = ids[((start - 1 + step) % #ids) + 1]
        if Fight.styles[id] then
            if id ~= Fight.style then Fight.SetStyle(id) end
            return
        end
    end
end

local function applyState(st)
    if type(st) ~= 'table' then return end
    Fight.styles = { untrained = true }
    for id, v in pairs(st.styles or {}) do if v and Fighting.Styles[id] then Fight.styles[id] = true end end
    if st.active and Fight.styles[st.active] then Fight.style = st.active else Fight.style = 'untrained' end
    if type(st.enabled) == 'boolean' then S.enabled = st.enabled end
end

RegisterNetEvent('bs:fighting:state', function(st)
    applyState(st)
    if st and st.learned then FightHud.Style(st.learned, true) end
end)

local function refresh()
    CreateThread(function()
        applyState(BSB.Await('fighting:state', 8000))
        level()
    end)
end
AddEventHandler('bs:hook:player:spawned', refresh)
CreateThread(function() Wait(5000) refresh() end)

-- Keys

local K = Fighting.Keys
RegisterCommand('+fight_attack', attackDown, false)
RegisterCommand('-fight_attack', attackUp, false)
RegisterCommand('+fight_kick', function() Fight.Kick() end, false)
RegisterCommand('-fight_kick', function() end, false)
RegisterCommand('+fight_block', guardOn, false)
RegisterCommand('-fight_block', guardOff, false)
RegisterCommand('fight_style', function() cycleStyle() end, false)
RegisterCommand('fightstyle', function(_, args)
    local id = args and args[1] and tostring(args[1]):lower()
    if not id then cycleStyle() return end
    if not Fight.SetStyle(id) then complain('fight.unknown_style') end
end, false)

RegisterKeyMapping('+fight_attack', L('key.attack'), K.attack.mapper, K.attack.key)
RegisterKeyMapping('+fight_kick', L('key.kick'), K.kick.mapper, K.kick.key)
RegisterKeyMapping('+fight_block', L('key.block'), K.block.mapper, K.block.key)
RegisterKeyMapping('fight_style', L('key.style'), K.style.mapper, K.style.key)

-- Vanilla melee, aim lock-on and reload are off while we own the fight.
CreateThread(function()
    local wasActive = false
    while true do
        local ped = PlayerPedId()
        if S.replaceVanillaMelee and Fight.CanFight(ped) then
            DisableControlAction(0, 24, true);  DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true); DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true); DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true); DisableControlAction(0, 264, true)
            DisableControlAction(0, 45, true)
            if Fight.blocking or Fight.charging then DisableControlAction(0, 21, true); DisableControlAction(0, 22, true) end
            local active = GetGameTimer() - Fight.lastActionAt < 8000
            if active ~= wasActive then wasActive = active; FightHud.Active(active) end
            Wait(0)
        else
            if Fight.blocking then guardOff() end
            Fight.holding, Fight.charging, Fight.queued = false, false, false
            Fight.holdToken, Fight.attackToken = nil, nil
            if Fight.attackAnim then FightAnim.Stop(Fight.attackAnim); Fight.attackAnim = nil end
            FightHud.Charge(nil)
            if wasActive then wasActive = false; FightHud.Active(false) end
            Wait(250)
        end
    end
end)

-- Context prompt: stomp a downed target, takedown from behind.
CreateThread(function()
    while true do
        local me = PlayerPedId()
        local shown = nil
        if S.enabled and Fight.CanFight(me) and not Fight.blocking then
            if stompTarget() then
                shown = 'stomp'
            else
                -- Walker takedowns are offered in the ALT menu, so no prompt for those
                local t = takedownTarget()
                if t and t.kind ~= 'zombie' then shown = 'takedown' end
            end
        end
        FightHud.Prompt(shown)
        Wait(shown and 100 or 200)
    end
end)

local function resetCombat(clearStyles)
    guardOff()
    Fight.holding,Fight.charging,Fight.queued=false,false,false
    Fight.holdToken,Fight.attackToken=nil,nil
    if Fight.attackAnim then FightAnim.Stop(Fight.attackAnim);Fight.attackAnim=nil end
    Fight.chain,Fight.combo,Fight.lastHitAt=0,0,0
    Fight.busyUntil,Fight.staggerUntil,Fight.counterUntil,Fight.nextTakedown=0,0,0,0
    if clearStyles then Fight.style='untrained';Fight.styles={untrained=true};Fight.level=0 end
    FightHud.Charge(nil);FightHud.Active(false)
end
AddEventHandler('bs:hook:player:unloaded',function()resetCombat(true)end)
AddEventHandler('bs:hook:player:spawned',function()resetCombat(false)end)

-- Never stuck: anything ours comes off on death, ragdoll, vehicle, menu or stop.
CreateThread(function()
    while true do
        local me = PlayerPedId()
        if Fight.blocking and (IsPedRagdoll(me) or IsPedInAnyVehicle(me, false) or IsPedDeadOrDying(me, true)) then guardOff() end
        if Fight.busyUntil > 0 and GetGameTimer() > Fight.busyUntil + 1500 then Fight.busyUntil = 0 end
        Wait(300)
    end
end)

RegisterCommand('fighttest', function()
    local me = PlayerPedId()
    print(('[bs_fighting] enabled=%s style=%s level=%d canFight=%s class=%s stamina=%.0f styles=%s'):format(
        tostring(S.enabled), Fight.style, level(), tostring(Fight.CanFight(me)), tostring(weaponClass(me)), stamina(),
        json.encode(Fight.styles)))
    for _, slot in ipairs({ 'light', 'heavy', 'kick', 'stomp', 'takedown' }) do
        local id = Fighting.MoveFor(Fight.style, weaponClass(me), slot, 1)
        local d, c = FightAnim.ClipOf(id or '')
        print(('  %s -> %s (%s / %s, %d ms)'):format(slot, tostring(id), tostring(d), tostring(c), d and FightAnim.Length(d, c) or 0))
    end
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('fight.test_done'), duration = 3000 })
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    guardOff()
    SetTimeScale(1.0)
    FightReact.ReleaseChoke()
end)

exports('GetStyle', function() return Fight.style end)
exports('IsBlocking', function() return Fight.blocking == true end)
