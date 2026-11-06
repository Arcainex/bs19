-- The moves themselves. Each one runs in its own thread, holds PK.busy and reports to the server when it lands.

PK = { busy = false, move = nil, last = {}, penaltyUntil = 0, weight = 0.0, airRuns = 0, chasing = false }

local T = Parkour.Tuning

-- Perks and level, refreshed by cl_main
PK.perks, PK.level = {}, 0
function PK.Has(id) return PK.perks[id] == true end

function PK.Allowed(kind)
    local m = Parkour.Moves[kind]
    if not Parkour.Settings.enabled or not m or not m.enabled then return false end
    local tier = Parkour.MoveTier[kind]
    return tier ~= nil and PK.Has(Parkour.TierPerk[tier])
end

function PK.Ready(kind)
    local m = Parkour.Moves[kind]
    local cd = m.cooldown or 0
    if PK.chasing and PK.Has('pk_shake_off') then cd = cd * 0.7 end
    return GetGameTimer() - (PK.last[kind] or 0) >= cd
end

-- Carry weight never blocks a move, it only slows it down
function PK.Slow()
    local f = Parkour.Settings.weightSlowAtFull or 0.0
    if PK.Has('pk_pack_mule') then f = f * 0.5 end
    return 1.0 + f * math.max(0.0, math.min(1.0, PK.weight or 0.0))
end

function PK.Stamina()
    local ok, n = pcall(function() return exports.bs_core:GetNeeds() end)
    if ok and type(n) == 'table' and type(n.stamina) == 'number' then return n.stamina end
    return 100.0
end

function PK.Cost(kind, base)
    local c = base or (Parkour.Moves[kind] or {}).stamina or 0
    if c <= 0 then return 0 end
    local mult = 1.0
    if PK.Has('pk_steady_breath') then mult = mult - 0.15 end
    if PK.Has('pk_marathon') then mult = mult - 0.20 end
    if PK.chasing and PK.Has('pk_adrenaline') then mult = mult - 0.30 end
    return c * math.max(0.2, mult)
end

function PK.Spend(kind, base)
    local c = PK.Cost(kind, base)
    if c <= 0 then return true end
    if PK.Stamina() < c then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = L('pk.winded'), duration = 1800 })
        return false
    end
    pcall(function() exports.bs_core:AdjustStamina(-c) end)
    return true
end

-- Animations: custom pack first, then the GTA list. Resolved once per move kind.
local resolved = {}
local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

function PK.AnimFor(kind)
    if resolved[kind] ~= nil then return resolved[kind] end
    local list = {}
    for _, pack in ipairs(Parkour.CustomAnims or {}) do
        if pack.dict and pack.clips and pack.clips[kind] then list[#list + 1] = { dict = pack.dict, clip = pack.clips[kind] } end
    end
    for _, a in ipairs(Parkour.Anims[kind] or {}) do list[#list + 1] = a end
    for _, a in ipairs(list) do
        if loadDict(a.dict) and GetAnimDuration(a.dict, a.clip) > 0.0 then
            resolved[kind] = a
            return a
        end
    end
    resolved[kind] = false
    return false
end

-- Airborne moves loop their clip (flag 1) and re-issue it if the engine's fall task takes over, so it lasts as long as the move.
-- One-shots hold the last frame (flag 2) until we stop them. Blend out slowly so the end is not a snap.
local playing = {}
function PK.Play(ped, kind, loop, rate)
    if not PK.Live() then return end
    local a = PK.AnimFor(kind)
    if not a or not loadDict(a.dict) then playing[kind] = nil return false end
    if not PK.Live() then return false end
    local flag = loop and 1 or 2
    TaskPlayAnim(ped, a.dict, a.clip, 6.0, 3.0, -1, flag, rate or 0.0, false, false, false)
    playing[kind] = { a = a, flag = flag, rate = rate or 0.0 }
    return true
end

function PK.Keep(ped, kind)
    if not PK.Live() then return end
    local p = playing[kind]
    if p and not IsEntityPlayingAnim(ped, p.a.dict, p.a.clip, 3) then
        TaskPlayAnim(ped, p.a.dict, p.a.clip, 8.0, 3.0, -1, p.flag, p.rate, false, false, false)
    end
end

function PK.Stop(ped, kind)
    if not PK.Live() then return end
    local p = playing[kind]
    if p then StopAnimTask(ped, p.a.dict, p.a.clip, 3.0) end
    playing[kind] = nil
end

-- Every clip a move has used, for the watchdog
function PK.KnownClips()
    local out = {}
    for _, a in pairs(resolved) do if a then out[#out + 1] = a end end
    return out
end

-- Dev check: which candidate of each move loads, and its length
function PK.AnimReport()
    local out = {}
    local kinds = {}
    for k in pairs(Parkour.Anims) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, kind in ipairs(kinds) do
        local list = {}
        for _, pack in ipairs(Parkour.CustomAnims or {}) do
            if pack.dict and pack.clips and pack.clips[kind] then list[#list + 1] = { dict = pack.dict, clip = pack.clips[kind], custom = true } end
        end
        for _, a in ipairs(Parkour.Anims[kind]) do list[#list + 1] = a end
        for _, a in ipairs(list) do
            local exists = DoesAnimDictExist(a.dict)
            local loaded = exists and loadDict(a.dict)
            local len = loaded and GetAnimDuration(a.dict, a.clip) or 0.0
            out[#out + 1] = { kind = kind, dict = a.dict, clip = a.clip, exists = exists, loaded = loaded, length = len, custom = a.custom }
        end
    end
    resolved = {}
    return out
end

local function setState(kind)
    LocalPlayer.state:set('bsParkour', kind and { active = true, move = kind } or { active = false }, true)
end

-- Longest a move may run before the watchdog cancels it (ms). Hanging can legitimately last 20 s.
PK.MaxMs = { vault = 3000, climb = 3000, climbHigh = 3500, slide = 2500, roll = 2000, wallrun = 3500, walljump = 2000, ledge = 23000, shimmy = 23000 }

-- Only the thread that owns the current move may touch the ped. A cancelled move's thread sees Live() == false and stops.
function PK.Live() return PK.thread ~= nil and coroutine.running() == PK.thread end

function PK.Freeze(ped, on)
    if not PK.Live() then return end
    FreezeEntityPosition(ped, on)
    PK.frozen = on or nil
end

-- keep = a one-shot left to finish on its own timer (the wall jump flip)
function PK.StopAll(ped, keep)
    for kind, p in pairs(playing) do
        if kind ~= keep then
            StopAnimTask(ped, p.a.dict, p.a.clip, 3.0)
            playing[kind] = nil
        end
    end
end

-- Puts the ped back to normal. hard = also drop whatever task it is stuck in.
function PK.Cleanup(hard)
    local ped = PlayerPedId()
    PK.thread = nil; PK.run = nil
    PK.StopAll(ped, not hard and 'walljump' or nil)
    if PK.frozen then FreezeEntityPosition(ped, false) PK.frozen = nil end
    if PK.ragdoll ~= nil then SetPedCanRagdoll(ped, PK.ragdoll) PK.ragdoll = nil end
    if hard then
        SetEntityCollision(ped, true, true)
        if not IsPedInAnyVehicle(ped, false) then ClearPedTasks(ped) end
        local v = GetEntityVelocity(ped)
        SetEntityVelocity(ped, 0.0, 0.0, math.min(v.z, 0.0))
    end
    PK.busy, PK.move, PK.startedAt = false, nil, nil
    setState(nil)
end

-- Gate for every move: nothing while another move runs, ragdolled, in a vehicle or water, dead, or aiming.
function PK.CanStart(ped, airborne)
    if PK.busy or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, true) or IsEntityDead(ped) then return false end
    if IsPedSwimming(ped) or IsEntityInWater(ped) or IsPedInParachuteFreeFall(ped) then return false end
    if IsPlayerFreeAiming(PlayerId()) or IsPedShooting(ped) then return false end
    if not airborne and (IsPedFalling(ped) or IsPedJumping(ped)) then return false end
    return true
end

-- Runs a move in its own thread. busy is taken right away so a second key press cannot start another one,
-- and whatever happens inside (error, early return, forgotten End) the ped is restored afterwards.
function PK.Start(kind, fn, ...)
    local ped = PlayerPedId()
    if not PK.CanStart(ped, kind == 'wallrun' or kind == 'roll') then return false end
    PK.busy, PK.move, PK.startedAt = true, kind, GetGameTimer()
    local token = {}; PK.run = token
    local args = table.pack(...)
    CreateThread(function()
        if PK.run ~= token then return end
        PK.thread = coroutine.running()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then print(('^1[bs_parkour] %s failed: %s^7'):format(kind, tostring(err))) end
        if PK.thread == coroutine.running() then PK.Cleanup(not ok) end
    end)
    return true
end

function PK.Begin(kind)
    if not PK.Live() then error('cancelled', 0) end
    PK.busy, PK.move, PK.startedAt = true, kind, GetGameTimer()
    local ped = PlayerPedId()
    if PK.ragdoll == nil then PK.ragdoll = CanPedRagdoll(ped) end
    SetPedCanRagdoll(ped, false)
    setState(kind)
end

function PK.End(kind, ok, from)
    if not PK.Live() then return end
    PK.last[kind] = GetGameTimer()
    PK.StopAll(PlayerPedId(), 'walljump')
    if PK.frozen then FreezeEntityPosition(PlayerPedId(), false) PK.frozen = nil end
    if PK.ragdoll ~= nil then SetPedCanRagdoll(PlayerPedId(), PK.ragdoll) PK.ragdoll = nil end
    PK.move = nil
    setState(nil)
    local pen = Parkour.Settings.aimPenaltyMs or 0
    if PK.Has('pk_quick_recovery') then pen = pen * 0.5 end
    if PK.Has('pk_ghost_runner') then pen = 0 end
    PK.penaltyUntil = GetGameTimer() + pen
    if ok then
        local to = GetEntityCoords(PlayerPedId())
        from = from or to
        TriggerServerEvent('bs:parkour:move', kind, { from.x, from.y, from.z }, { to.x, to.y, to.z })
        TriggerEvent('bs:parkour:moved', kind)
    end
end

local function face(ped, dir)
    SetEntityHeading(ped, GetHeadingFromVector_2d(dir.x, dir.y))
end

-- Smooth slide along a list of points with the ped frozen, so gravity does not fight the path.
local function path(ped, points, ms, keep)
    PK.Freeze(ped, true)
    local start = GetGameTimer()
    local seg = #points - 1
    while PK.Live() do
        local t = math.min(1.0, (GetGameTimer() - start) / ms)
        local f = t * seg
        local i = math.min(seg, math.floor(f) + 1)
        local k = f - (i - 1)
        local a, b = points[i], points[i + 1]
        local p = a + (b - a) * k
        SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, true, true, false)
        if keep then PK.Keep(ped, keep) end
        if t >= 1.0 then break end
        Wait(0)
    end
    if not PK.Live() then return end
    PK.Freeze(ped, false)
end

-- Vault and normal climb: the engine's own climb, so the animation fits the obstacle.
function PK.Native(kind, info)
    local ped = PlayerPedId()
    if not PK.Spend(kind) then return end
    PK.Begin(kind)
    local from = GetEntityCoords(ped)
    TaskClimb(ped, false)
    local t = GetGameTimer() + math.floor(2200 * PK.Slow())
    Wait(150)
    while PK.Live() and GetGameTimer() < t and (IsPedClimbing(ped) or IsPedVaulting(ped)) do Wait(0) end
    if not PK.Live() then return end
    if IsPedClimbing(ped) or IsPedVaulting(ped) then ClearPedTasks(ped) end
    local ok = #(GetEntityCoords(ped) - from) > 0.8
    PK.End(kind, ok, from)
end

-- Up a wall that is too high for the engine climb.
function PK.ClimbHigh(info)
    local clip = PK.AnimFor('climbHigh')
    local custom = false
    for _, pack in ipairs(Parkour.CustomAnims or {}) do
        if pack.dict == (clip and clip.dict) and pack.clips and pack.clips.climbHigh == clip.clip then
            custom = true
            break
        end
    end
    if not custom then return PK.Native('climbHigh', info) end
    local ped = PlayerPedId()
    if not PK.Spend('climbHigh') then return end
    PK.Begin('climbHigh')
    local from = GetEntityCoords(ped)
    local n = info.normal
    face(ped, -n)
    local wall = vector3(info.wall.x, info.wall.y, 0.0) + n * 0.38
    local over = vector3(info.stand.x, info.stand.y, 0.0)
    local ms = math.floor(950 * PK.Slow())
    if not PK.Play(ped, 'climbHigh', false) then return end
    local clip = PK.AnimFor('climbHigh')
    ms = math.max(ms, math.min(2400, math.floor(GetAnimDuration(clip.dict, clip.clip) * 1000 * PK.Slow())))
    path(ped, {
        from,
        vector3(wall.x, wall.y, info.top - 0.55),
        vector3(wall.x, wall.y, info.top + 0.6),
        vector3(over.x, over.y, info.top + 1.0),
    }, ms, 'climbHigh')
    PK.Stop(ped, 'climbHigh')
    PK.End('climbHigh', true, from)
end

function PK.Slide()
    local ped = PlayerPedId()
    if not PK.Spend('slide') then return end
    PK.Begin('slide')
    local from = GetEntityCoords(ped)
    local fwd = Detect.Flat(GetEntityForwardVector(ped))
    local dur = T.slideSeconds * 1000 * (PK.Has('pk_long_slide') and 1.35 or 1.0)
    local speed = T.slideSpeed / PK.Slow()
    if not PK.Play(ped, 'slide', true) then return end
    local start = GetGameTimer()
    while PK.Live() and GetGameTimer() - start < dur do
        local k = 1.0 - (GetGameTimer() - start) / dur * 0.6
        local v = GetEntityVelocity(ped)
        SetEntityVelocity(ped, fwd.x * speed * k, fwd.y * speed * k, math.min(v.z, 0.0))
        PK.Keep(ped, 'slide')
        DisableControlAction(0, 22, true)
        -- stop at a wall
        if Detect.Ray(GetEntityCoords(ped), GetEntityCoords(ped) + fwd * 0.7, ped) then break end
        Wait(0)
    end
    PK.Stop(ped, 'slide')
    PK.End('slide', true, from)
end

function PK.Roll()
    local ped = PlayerPedId()
    PK.Begin('roll')
    local from = GetEntityCoords(ped)
    local fwd = Detect.Flat(GetEntityForwardVector(ped))
    if not PK.Play(ped, 'roll', false) then return end
    local start = GetGameTimer()
    while PK.Live() and GetGameTimer() - start < 600 do
        local v = GetEntityVelocity(ped)
        SetEntityVelocity(ped, fwd.x * 4.0, fwd.y * 4.0, v.z)
        Wait(0)
    end
    PK.Stop(ped, 'roll')
    PK.End('roll', true, from)
end

-- Moves the frozen ped by a velocity for one frame. Frozen, the engine never swaps in its fall task,
-- so the clip keeps playing to the end. Returns false when something solid is in the way.
local function step(ped, vel)
    if not PK.Live() then return false end
    local dt = math.min(GetFrameTime(), 0.05)
    local cur = GetEntityCoords(ped)
    local nxt = cur + vel * dt
    local dir = vel * (1.0 / math.max(0.001, #vel))
    if Detect.Ray(cur, nxt + dir * 0.35, ped) then return false end
    SetEntityCoordsNoOffset(ped, nxt.x, nxt.y, nxt.z, true, true, false)
    return true
end

local function wallJump(ped, n, tangent)
    if not PK.Allowed('walljump') or not PK.Spend('walljump') then return false end
    local push, lift = T.wallJumpPush, T.wallJumpLift
    if PK.Has('pk_spring_heels') then push, lift = push * 1.25, lift * 1.25 end
    lift = lift / PK.Slow()
    PK.StopAll(ped)
    if not PK.Play(ped, 'walljump', false) then return false end
    local record = playing.walljump
    local a = record and record.a
    if a then
        PK.debugUntil = GetGameTimer() + 900
        SetTimeout(700, function()
            if playing.walljump == record then
                StopAnimTask(ped, a.dict, a.clip, 3.0)
                playing.walljump = nil
            end
        end)
    end
    SetEntityVelocity(ped, n.x * push + tangent.x * 3.0, n.y * push + tangent.y * 3.0, lift)
    face(ped, n + tangent * 0.5)
    return true
end

-- Run along a wall beside you. Space during the run kicks off it.
function PK.WallRun(side, n)
    local ped = PlayerPedId()
    if not PK.Spend('wallrun') then return end
    PK.Begin('wallrun')
    local from = GetEntityCoords(ped)
    PK.airRuns = PK.airRuns + 1
    local fwd = Detect.Flat(GetEntityForwardVector(ped))
    local dot = fwd.x * n.x + fwd.y * n.y
    local t = Detect.Flat(vector3(fwd.x - n.x * dot, fwd.y - n.y * dot, 0.0))
    local dur = T.wallRunSeconds * 1000 * (PK.Has('pk_wall_runner') and 1.4 or 1.0)
    local speed = T.wallRunSpeed / PK.Slow()
    if not PK.Play(ped, 'wallrun', true) then return end
    face(ped, t)
    local start, jumped, ran = GetGameTimer(), false, 0.0
    local vel = vector3(0.0, 0.0, 0.0)
    while PK.Live() and GetGameTimer() - start < dur do
        local k = (GetGameTimer() - start) / dur
        local current = GetEntityVelocity(ped)
        -- Keep forward momentum beside the wall without moving the ped through collision.
        -- The upward help fades quickly; gravity and collision remain in charge.
        vel = vector3(t.x * speed, t.y * speed, math.max(current.z, 1.2 - 3.0 * k))
        PK.Keep(ped, 'wallrun')
        DisableControlAction(0, 22, true)
        if IsDisabledControlJustPressed(0, 22) then
            jumped = wallJump(ped, n, t)
            if jumped then break end
        end
        if not Detect.Side(ped, 1.4) then break end
        SetEntityVelocity(ped, vel.x, vel.y, vel.z)
        ran = k
        Wait(0)
    end
    if not PK.Live() then return end
    if not jumped then PK.Stop(ped, 'wallrun') end
    PK.End('wallrun', ran > 0.35 or jumped, from)
    if jumped then
        PK.last.walljump = GetGameTimer()
        local to = GetEntityCoords(ped)
        TriggerServerEvent('bs:parkour:move', 'walljump', { from.x, from.y, from.z }, { to.x, to.y, to.z })
        TriggerEvent('bs:parkour:moved', 'walljump')
    end
end

-- Hang on a ledge: A / D shimmy, Space climbs up, S or the move key drops.
function PK.Hang(info)
    local ped = PlayerPedId()
    if not PK.Spend('ledge') then return end
    PK.Begin('ledge')
    local from = GetEntityCoords(ped)
    local n, top = info.normal, info.top
    local spot = vector3(info.wall.x, info.wall.y, 0.0)
    face(ped, -n)
    local function hangPos() return vector3(spot.x, spot.y, top) + n * 0.34 - vector3(0.0, 0.0, 1.15) end
    if not PK.Play(ped, 'ledge', true) then return end
    path(ped, { from, hangPos() }, 260, 'ledge')
    PK.Freeze(ped, true)
    PK.Play(ped, 'ledge', true)
    face(ped, -n)
    local drain = T.ledgeDrainPerSec * (PK.Has('pk_iron_grip') and 0.6 or 1.0)
    local right = vector3(-n.y, n.x, 0.0)
    local started, lastTick, result = GetGameTimer(), GetGameTimer(), 'drop'
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('pk.hang_help'), duration = 3500 })
    while true do
        Wait(0)
        if not PK.Live() then return end
        DisableControlAction(0, 22, true)
        DisableControlAction(0, 30, true)
        DisableControlAction(0, 31, true)
        local now = GetGameTimer()
        if now - lastTick >= 1000 then
            lastTick = now
            pcall(function() exports.bs_core:AdjustStamina(-PK.Cost('ledge', drain)) end)
            if PK.Stamina() <= 1.0 then break end
        end
        if now - started > 20000 or IsEntityDead(ped) then break end
        local dir = (IsDisabledControlPressed(0, 34) and -1) or (IsDisabledControlPressed(0, 35) and 1) or 0
        if dir ~= 0 and PK.Allowed('shimmy') and PK.Ready('shimmy') then
            local at = spot + right * dir * T.shimmyStep
            local z, face2 = Detect.LedgeAt(ped, at, n, top)
            if z and math.abs(z - top) < 0.4 then
                local a = hangPos()
                spot, top = vector3(face2.x, face2.y, 0.0), z
                path(ped, { a, hangPos() }, math.floor(330 * PK.Slow() * (PK.Has('pk_cat_balance') and 0.5 or 1.0)))
                PK.Freeze(ped, true)
                PK.End('shimmy', true, a)
                PK.Begin('ledge')
                PK.Freeze(ped, true)
                PK.Play(ped, 'ledge', true)
                face(ped, -n)
            end
        end
        if IsDisabledControlJustPressed(0, 22) then
            local stand = vector3(spot.x, spot.y, 0.0) - n * 0.45
            local room = not Detect.Ray(vector3(stand.x, stand.y, top + 0.1), vector3(stand.x, stand.y, top + 1.85), ped)
            if room and PK.Spend('ledge', T.ledgeClimbCost) then result = 'up' break end
        end
        PK.Keep(ped, 'ledge')
        face(ped, -n)
        if IsDisabledControlJustPressed(0, 33) or (PK.keyAt and PK.keyAt > started) then break end
    end
    PK.Stop(ped, 'ledge')
    PK.Freeze(ped, false)
    if result == 'up' then
        -- Let the native climb solve the ledge. The fallback climbHigh clip does
        -- not match the old scripted path and made the ped float through the wall.
        local before = GetEntityCoords(ped)
        face(ped, -n)
        TaskClimb(ped, false)
        Wait(150)
        local timeout = GetGameTimer() + 1700
        while PK.Live() and GetGameTimer() < timeout and (IsPedClimbing(ped) or IsPedVaulting(ped)) do Wait(0) end
        if not PK.Live() then return end
        result = GetEntityCoords(ped).z - before.z > 0.55 and 'up' or 'drop'
    end
    PK.End('ledge', GetGameTimer() - started > 400 or result == 'up', from)
end

-- Kick away from a front wall. The engine owns the jump and fall, so the ped never
-- has to be carried up the wall by frame-by-frame position changes.
function PK.WallUp(info)
    local ped = PlayerPedId()
    if not PK.Allowed('walljump') or not PK.Ready('walljump') then return end
    if not PK.Spend('walljump') then return end
    PK.Begin('walljump')
    local from = GetEntityCoords(ped)
    local n = info.normal
    face(ped, -n)
    if not PK.Play(ped, 'walljump', false) then return end
    local push = T.wallJumpPush or 4.0
    local lift = (T.wallJumpLift or 4.0) / PK.Slow()
    SetEntityVelocity(ped, n.x * push, n.y * push, lift)
    local started = GetGameTimer()
    while PK.Live() and GetGameTimer() - started < 450 do
        Wait(0)
    end
    if not PK.Live() then return end
    PK.Stop(ped, 'walljump')
    PK.End('walljump', true, from)
end
