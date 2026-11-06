-- Parkour v3 moves. One thread owns the ped per move (PK.Live). Obstacle moves start a clip, wait until the
-- engine confirms it is playing, and only then move the ped along a path to the target Detect found.
-- Every exit (finish, abort, error, watchdog) goes through End or Cleanup, which put collision and control back.

PK = { busy = false, move = nil, last = {}, penaltyUntil = 0, weight = 0.0, airRuns = 0, chasing = false }
PK3 = {}

local T = Parkour.Tuning
local P3 = Parkour.Pk3 or {}

-- Perks and level, refreshed by cl_pk3_main
PK.perks, PK.level = {}, 0
function PK.Has(id) return PK.perks[id] == true end

-- Everyone can vault, climb, slide and roll. Advanced moves need the parkour level or the advanced perk.
function PK.Advanced()
    return (PK.level or 0) >= (P3.advancedLevel or 3) or PK.Has(Parkour.TierPerk.advanced)
end

function PK.Allowed(kind)
    local m = Parkour.Moves[kind]
    if not Parkour.Settings.enabled or not m or not m.enabled then return false end
    if (P3.AdvancedMoves or {})[kind] then return PK.Advanced() end
    return true
end

function PK.Ready(kind)
    local m = Parkour.Moves[kind]
    local cd = m and m.cooldown or 0
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

local function winded()
    TriggerEvent('bs:ui:notify', { type = 'warn', message = L('pk.winded'), duration = 1800 })
end

function PK.CanAfford(kind)
    local c = PK.Cost(kind)
    if c > 0 and PK.Stamina() < c then winded() return false end
    return true
end

function PK.Spend(kind, base)
    local c = PK.Cost(kind, base)
    if c <= 0 then return true end
    if PK.Stamina() < c then winded() return false end
    pcall(function() exports.bs_core:AdjustStamina(-c) end)
    return true
end

-- Animations: custom pack first, then the GTA list. Resolved once per move kind (slide, roll, wall jump).
local resolved = {}
local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end
PK.LoadDict = loadDict

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

-- Airborne moves loop their clip (flag 1) and re-issue it if the engine's fall task takes over.
-- One-shots hold the last frame (flag 2) until we stop them.
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
local used3 = {}
function PK.KnownClips()
    local out = {}
    for _, a in pairs(resolved) do if a then out[#out + 1] = a end end
    for _, a in pairs(used3) do out[#out + 1] = a end
    return out
end

local function setState(kind)
    LocalPlayer.state:set('bsParkour', kind and { active = true, move = kind } or { active = false }, true)
end

-- Longest a move may run before the watchdog cancels it (ms). Obstacle moves raise it to their own timeout.
PK.MaxMs = { vault = 3500, climb = 4000, climbHigh = 4500, bonnet = 4500, step = 1200, slide = 2500, roll = 2000, walljump = 2000 }

-- Only the thread that owns the current move may touch the ped. A cancelled move's thread sees Live() == false and stops.
function PK.Live() return PK.thread ~= nil and coroutine.running() == PK.thread end

function PK.SetCollision(ped, on)
    if on then
        SetEntityCollision(ped, true, true)
        PK.colOff = nil
    else
        -- no collision and no physics: gravity cannot start a fall task while we carry the ped
        SetEntityCollision(ped, false, false)
        PK.colOff = true
    end
end

function PK.StopAll(ped, keep)
    for kind, p in pairs(playing) do
        if kind ~= keep then
            StopAnimTask(ped, p.a.dict, p.a.clip, 3.0)
            playing[kind] = nil
        end
    end
    if PK3.clip then
        StopAnimTask(ped, PK3.clip.dict, PK3.clip.clip, 4.0)
        PK3.clip = nil
    end
end

-- Puts the ped back to normal. hard = also drop whatever task it is stuck in.
function PK.Cleanup(hard)
    local ped = PlayerPedId()
    PK.thread = nil; PK.run = nil
    PK.StopAll(ped, not hard and 'walljump' or nil)
    if PK.colOff then PK.SetCollision(ped, true) end
    if PK.frozen then FreezeEntityPosition(ped, false) PK.frozen = nil end
    if PK.ragdoll ~= nil then SetPedCanRagdoll(ped, PK.ragdoll) PK.ragdoll = nil end
    if hard then
        SetEntityCollision(ped, true, true)
        if not IsPedInAnyVehicle(ped, false) then ClearPedTasks(ped) end
        local v = GetEntityVelocity(ped)
        SetEntityVelocity(ped, 0.0, 0.0, math.min(v.z, 0.0))
    end
    PK.busy, PK.move, PK.startedAt, PK.expectMs = false, nil, nil, nil
    PK.endedAt = GetGameTimer()
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

-- Moves that may start just after leaving the ground (coyote time, buffered jump) or in the air
local AIR_OK = { roll = true, vault = true, climb = true, climbHigh = true, bonnet = true }

-- Runs a move in its own thread. busy is taken right away so a second key press cannot start another one,
-- and whatever happens inside (error, early return, forgotten End) the ped is restored afterwards.
function PK.Start(kind, fn, ...)
    local ped = PlayerPedId()
    if not PK.CanStart(ped, AIR_OK[kind]) then return false end
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

-- quiet = no XP report and no aim shake (auto step)
function PK.End(kind, ok, from, quiet)
    if not PK.Live() then return end
    local ped = PlayerPedId()
    PK.last[kind] = GetGameTimer()
    PK.StopAll(ped, 'walljump')
    if PK.colOff then PK.SetCollision(ped, true) end
    if PK.frozen then FreezeEntityPosition(ped, false) PK.frozen = nil end
    if PK.ragdoll ~= nil then SetPedCanRagdoll(ped, PK.ragdoll) PK.ragdoll = nil end
    PK.move, PK.expectMs = nil, nil
    PK.endedAt = GetGameTimer()
    setState(nil)
    if quiet then return end
    local pen = Parkour.Settings.aimPenaltyMs or 0
    if PK.Has('pk_quick_recovery') then pen = pen * 0.5 end
    if PK.Has('pk_ghost_runner') then pen = 0 end
    PK.penaltyUntil = GetGameTimer() + pen
    if ok then
        local to = GetEntityCoords(ped)
        from = from or to
        TriggerServerEvent('bs:parkour:move', kind, { from.x, from.y, from.z }, { to.x, to.y, to.z })
        TriggerEvent('bs:parkour:moved', kind)
    end
end

local function face(ped, dir)
    SetEntityHeading(ped, GetHeadingFromVector_2d(dir.x, dir.y))
end

---------------------------------------------------------------------------------------------------
-- v1 moves kept as they were: sprint slide (Mouse 4), landing roll, wall bounce
---------------------------------------------------------------------------------------------------

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

-- Kick off a wall ahead that is too high to climb (advanced). The engine owns the jump and the fall.
function PK.WallUp(info)
    local ped = PlayerPedId()
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
    while PK.Live() and GetGameTimer() - started < 450 do Wait(0) end
    if not PK.Live() then return end
    PK.Stop(ped, 'walljump')
    PK.End('walljump', true, from)
end

---------------------------------------------------------------------------------------------------
-- v3 obstacle moves
---------------------------------------------------------------------------------------------------

local function list(dict, names)
    local out = {}
    for _, c in ipairs(names or {}) do out[#out + 1] = { dict = dict, clip = c } end
    return out
end

-- First candidate whose dict loads and whose clip exists
function PK3.Resolve(cands)
    for _, a in ipairs(cands or {}) do
        if loadDict(a.dict) and GetAnimDuration(a.dict, a.clip) > 0.0 then return a end
    end
    return nil
end

-- Climb clips whose height label is closest to the obstacle (0.8 / 1.4 / 1.8 / 2.2 / 2.95 m)
function PK3.ClimbClips(h, running)
    local best, bd
    for _, b in ipairs(P3.ClimbBands or {}) do
        local d = math.abs(h - b.label)
        if not bd or d < bd then best, bd = b, d end
    end
    if not best then return {} end
    local dict = best.dict or 'move_climb'
    local a, b = list(dict, running and best.run or best.stand), list(dict, running and best.stand or best.run)
    for _, x in ipairs(b) do a[#a + 1] = x end
    return a
end

function PK3.VaultClips(running)
    local v = P3.VaultClips or {}
    local a, b = running and v.run or v.stand, running and v.stand or v.run
    local out = {}
    for _, x in ipairs(a or {}) do out[#out + 1] = x end
    for _, x in ipairs(b or {}) do out[#out + 1] = x end
    return out
end

local function offsetsFor(a) return (Parkour.ClipOffsets or {})[a.dict .. '/' .. a.clip] end

local function clipMs(a)
    local o = offsetsFor(a)
    local d = (o and tonumber(o.dur)) or GetAnimDuration(a.dict, a.clip)
    return math.max(250, math.floor(d * 1000))
end

local function smooth(t) return t * t * (3.0 - 2.0 * t) end

-- Path through points at the given time marks, eased overall
local function polyline(points, marks)
    return function(t)
        t = smooth(math.max(0.0, math.min(1.0, t)))
        for i = 1, #points - 1 do
            if t <= marks[i + 1] or i == #points - 1 then
                local span = marks[i + 1] - marks[i]
                local k = span > 0 and (t - marks[i]) / span or 1.0
                k = math.max(0.0, math.min(1.0, k))
                return points[i] + (points[i + 1] - points[i]) * k
            end
        end
        return points[#points]
    end
end

-- Measured curve (from /pkmeasure), normalised: returns f, u progress 0..1 at phase t, or nil
local function curveAt(curve, t, axis)
    local n = #curve
    if n < 2 then return nil end
    local endV = curve[n][axis]
    if math.abs(endV) < 0.15 then return nil end
    local x = math.max(0.0, math.min(1.0, t)) * (n - 1)
    local i = math.min(n - 2, math.floor(x))
    local k = x - i
    local a, b = curve[i + 1][axis], curve[i + 2][axis]
    return (a + (b - a) * k) / endV
end

-- Climb path: up the face first, then over the edge, never through it
local function climbPath(S, info, clip)
    local n, off, top = info.normal, info.off, info.top
    local faceXY = vector3(info.wall.x, info.wall.y, 0.0)
    local T3 = vector3(info.stand.x, info.stand.y, info.stand.z + off)
    local o = offsetsFor(clip)
    local guard = function(p)
        -- keep the body in front of the face until the feet clear the top
        local s = Detect.Dot2(p - faceXY, n)
        if s < 0.25 and p.z - off < top + 0.05 then
            local back = 0.25 - s
            p = vector3(p.x + n.x * back, p.y + n.y * back, p.z)
        end
        return p
    end
    if o and type(o.curve) == 'table' and #o.curve >= 3 then
        local flatD = vector3(T3.x - S.x, T3.y - S.y, 0.0)
        local up = T3.z - S.z
        return function(t)
            local f = curveAt(o.curve, t, 1) or smooth(math.max(0.0, (t - 0.35) / 0.65))
            local u = curveAt(o.curve, t, 2) or smooth(math.min(1.0, t / 0.6))
            f, u = math.max(0.0, math.min(1.0, f)), math.max(0.0, math.min(1.0, u))
            return guard(vector3(S.x + flatD.x * f, S.y + flatD.y * f, S.z + up * u))
        end
    end
    local upEnd = (o and tonumber(o.upEnd)) or 0.6
    local p1 = faceXY + n * 0.32
    local p2 = faceXY - n * 0.05
    local base = polyline({
        S,
        vector3(p1.x, p1.y, math.max(S.z, top + off - 0.55)),
        vector3(p2.x, p2.y, top + off + 0.12),
        T3,
    }, { 0.0, upEnd * 0.75, upEnd + 0.12, 1.0 })
    return function(t) return guard(base(t)) end
end

-- Vault / bonnet path: rise to the top, pass over it, drop to the landing
local function overPath(S, info, apex, inMark, outMark)
    local n, off, top = info.normal, info.off, info.top
    local faceXY = vector3(info.wall.x, info.wall.y, 0.0)
    local p1 = faceXY + n * 0.28
    local p2 = faceXY - n * (info.edge or 0.3)
    local L3 = vector3(info.land.x, info.land.y, info.land.z + off)
    return polyline({
        S,
        vector3(p1.x, p1.y, math.max(S.z, top + apex)),
        vector3(p2.x, p2.y, top + apex),
        L3,
    }, { 0.0, inMark, outMark, 1.0 })
end

-- GTA's own climb, for when our clip cannot start (or the safe mode setting). Assumes Begin was called.
function PK3.Native(kind, from, info)
    local ped = PlayerPedId()
    if info and info.normal and GetFollowPedCamViewMode() ~= 4 then
        SetEntityHeading(ped, GetHeadingFromVector_2d(-info.normal.x, -info.normal.y))
    end
    local function started() return IsPedClimbing(ped) or IsPedVaulting(ped) end
    TaskClimb(ped, false)
    local by = GetGameTimer() + 350
    while PK.Live() and not started() and GetGameTimer() < by do Wait(0) end
    if not PK.Live() then return end
    if not started() then
        TaskClimb(ped, false)
        by = GetGameTimer() + 300
        while PK.Live() and not started() and GetGameTimer() < by do Wait(0) end
        if not PK.Live() then return end
    end
    local t = GetGameTimer() + math.floor(2200 * PK.Slow())
    while PK.Live() and GetGameTimer() < t and (IsPedClimbing(ped) or IsPedVaulting(ped)) do Wait(0) end
    if not PK.Live() then return end
    if IsPedClimbing(ped) or IsPedVaulting(ped) then ClearPedTasks(ped) end
    local ok = #(GetEntityCoords(ped) - from) > 0.8
    if ok then PK.Spend(kind) end
    PK.End(kind, ok, from)
end

function PK3.NativeMove(kind, info)
    if not PK.CanAfford(kind) then return end
    PK.Begin(kind)
    PK3.Native(kind, GetEntityCoords(PlayerPedId()), info)
end

local function firstPerson() return GetFollowPedCamViewMode() == 4 end

-- Hands in the ped's own frame (x = right, z = up). In the bind pose (T-pose) both hands are
-- far out to the sides at shoulder height; no real move holds that pose.
local L_HAND, R_HAND = 18905, 57005
function PK3.Hands(ped)
    local l = GetPedBoneCoords(ped, L_HAND, 0.0, 0.0, 0.0)
    local r = GetPedBoneCoords(ped, R_HAND, 0.0, 0.0, 0.0)
    return GetOffsetFromEntityGivenWorldCoords(ped, l.x, l.y, l.z), GetOffsetFromEntityGivenWorldCoords(ped, r.x, r.y, r.z)
end

function PK3.IsTPose(ped)
    local l, r = PK3.Hands(ped)
    return math.abs(l.x) > 0.55 and math.abs(r.x) > 0.55 and l.z > 0.2 and r.z > 0.2 and (l.x * r.x) < 0
end

-- Clips that really animate the whole body when played on their own. move_climb clips are made for
-- GTA's climb task and can play as a bare T-pose, so a clip is only used once it is listed here
-- (Parkour.Pk3.Standalone, filled from /pkcliptest) or passed /pkcliptest this session.
-- A clip caught in a T-pose is banned for the session.
PK3.verified, PK3.bad = {}, {}
function PK3.FlagFor(a)
    local key = a.dict .. '/' .. a.clip
    if PK3.bad[key] then return nil end
    local f = PK3.verified[key]
    if f == nil then f = (P3.Standalone or {})[key] end
    if f == false then return nil end
    return f
end

local function playClip(ped, a)
    local f = a.flag or PK3.FlagFor(a) or 2
    if f == 'adv' then
        local p = GetEntityCoords(ped)
        TaskPlayAnimAdvanced(ped, a.dict, a.clip, p.x, p.y, p.z, 0.0, 0.0, GetEntityHeading(ped), 8.0, -4.0, -1, 2, 0.0, 0, 0)
    else
        TaskPlayAnim(ped, a.dict, a.clip, 8.0, -4.0, -1, f, 0.0, false, false, false)
    end
    PK3.clip = a
    PK3.lastClip = a.dict .. '/' .. a.clip
    used3[a.dict .. '/' .. a.clip] = a
end

-- The runner. slots = list of candidate lists, played in order (the first must start or nothing moves).
-- buildPath(S, firstClip) returns function(t) -> ped origin position. fallback = 'native' or nil.
function PK3.Perform(kind, info, slots, buildPath, fallback)
    local ped = PlayerPedId()
    if not PK.CanAfford(kind) then return end
    PK.Begin(kind)
    local from = GetEntityCoords(ped)
    local function giveUp(why)
        if Parkour.Settings.debug then print(('^3[bs_parkour] %s: %s^7'):format(kind, why)) end
        if fallback == 'native' then return PK3.Native(kind, from, info) end
        PK.End(kind, false, from, true)
    end
    if P3.useNative then return giveUp('safe mode') end
    if firstPerson() and P3.firstPerson == 'native' then return giveUp('first person uses the GTA climb') end

    local seq = {}
    for i, cands in ipairs(slots) do
        local ok = {}
        for _, c in ipairs(cands) do if PK3.FlagFor(c) ~= nil then ok[#ok + 1] = c end end
        local a = PK3.Resolve(ok)
        if a then seq[#seq + 1] = { dict = a.dict, clip = a.clip, flag = PK3.FlagFor(a), ms = clipMs(a) }
        elseif i == 1 then return giveUp('no clip verified as standalone (see /pkcliptest)') end
    end
    if not PK.Live() then return end

    -- 1) start the clip and wait for the engine to confirm it. Nothing moves before this.
    local first = seq[1]
    playClip(ped, first)
    local confirmBy = GetGameTimer() + (P3.confirmMs or 250)
    while PK.Live() and not IsEntityPlayingAnim(ped, first.dict, first.clip, 3) and GetGameTimer() < confirmBy do Wait(0) end
    if not PK.Live() then return end
    if not IsEntityPlayingAnim(ped, first.dict, first.clip, 3) then
        StopAnimTask(ped, first.dict, first.clip, 4.0)
        PK3.clip = nil
        return giveUp(('clip did not start: %s/%s'):format(first.dict, first.clip))
    end
    -- give the blend in a moment, then make sure the body really took the clip
    local poseBy = GetGameTimer() + (P3.poseCheckMs or 160)
    while PK.Live() and GetGameTimer() < poseBy do Wait(0) end
    if not PK.Live() then return end
    if PK3.IsTPose(ped) then
        local key = first.dict .. '/' .. first.clip
        PK3.bad[key] = true
        print(('^1[bs_parkour] T-pose on %s (flag %s), clip banned for this session^7'):format(key, tostring(first.flag)))
        StopAnimTask(ped, first.dict, first.clip, 8.0)
        ClearPedTasks(ped)
        PK3.clip = nil
        return giveUp('T-pose')
    end

    -- 2) committed: stamina once, then carry the ped
    PK.Spend(kind)
    local slow = PK.Slow()
    local total = 0
    for _, s in ipairs(seq) do s.ms = math.floor(s.ms * slow) total = total + s.ms end
    if slow > 1.0 then SetEntityAnimSpeed(ped, first.dict, first.clip, 1.0 / slow) end
    PK.expectMs = total + (P3.timeoutPadMs or 600) + 400
    -- the path starts where the ped is now (it kept moving while the clip started)
    local path = buildPath(GetEntityCoords(ped), first)
    local target = path(1.0)
    local wantH = GetHeadingFromVector_2d(-info.normal.x, -info.normal.y)
    local align = not firstPerson() or P3.firstPersonAlign
    local startH = GetEntityHeading(ped)

    PK.SetCollision(ped, false)
    local start = GetGameTimer()
    local deadline = start + total + (P3.timeoutPadMs or 600)
    local idx, idxEnd, switchedAt = 1, seq[1].ms, start
    local rushAt, rushT0, retries = nil, 0.0, P3.retries or 1
    while PK.Live() do
        local now = GetGameTimer()
        local el = now - start
        if idx < #seq and el >= idxEnd and not rushAt then
            idx = idx + 1
            playClip(ped, seq[idx])
            if slow > 1.0 then SetEntityAnimSpeed(ped, seq[idx].dict, seq[idx].clip, 1.0 / slow) end
            idxEnd, switchedAt = idxEnd + seq[idx].ms, now
        end
        local cur = seq[idx]
        local t = rushAt and (rushT0 + (1.0 - rushT0) * math.min(1.0, (now - rushAt) / 150.0)) or math.min(1.0, el / total)
        -- the engine dropped the clip: restart it at the right phase once, then finish quickly
        if not rushAt and now - switchedAt > 200 and not IsEntityPlayingAnim(ped, cur.dict, cur.clip, 3) then
            if retries > 0 then
                retries = retries - 1
                playClip(ped, cur)
                local segStart = idxEnd - cur.ms
                SetEntityAnimCurrentTime(ped, cur.dict, cur.clip, math.max(0.0, math.min(0.98, (el - segStart) / cur.ms)))
                switchedAt = now
            else
                rushAt, rushT0 = now, t
            end
        end
        local p = path(t)
        SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        if align then
            local d = ((wantH - startH + 540.0) % 360.0) - 180.0
            SetEntityHeading(ped, startH + d * math.min(1.0, el / 180.0))
        end
        DisableControlAction(0, 22, true)
        if t >= 1.0 or now > deadline then break end
        Wait(0)
    end
    if not PK.Live() then return end
    -- 3) land on the checked spot, collision back, clip out
    SetEntityCoordsNoOffset(ped, target.x, target.y, target.z + 0.02, false, false, false)
    PK.SetCollision(ped, true)
    PK.End(kind, true, from)
end

function PK3.Vault(info)
    local running = GetEntitySpeed(PlayerPedId()) > 3.0
    return PK3.Perform('vault', info, { PK3.VaultClips(running) }, function(S)
        return overPath(S, info, P3.vaultApex or 0.35, 0.38, 0.62)
    end, 'native')
end

function PK3.Climb(info, kind)
    local running = GetEntitySpeed(PlayerPedId()) > 3.0
    local h = info.height
    if kind == 'climbHigh' then h = math.max(h, 2.9) end
    return PK3.Perform(kind, info, { PK3.ClimbClips(h, running) }, function(S, clip)
        return climbPath(S, info, clip)
    end, 'native')
end

function PK3.Bonnet(info)
    local ped = PlayerPedId()
    local side = P3.bonnetSide or 'auto'
    if side == 'auto' then
        side = 'l'
        if info.ent and DoesEntityExist(info.ent) then
            local c, p = GetEntityCoords(info.ent), GetEntityCoords(ped)
            local dir = -info.normal
            local right = vector3(dir.y, -dir.x, 0.0)
            if Detect.Dot2(c - p, right) > 0 then side = 'r' end
        end
    end
    local set = (P3.BonnetClips or {})[side] or {}
    local slots = {}
    for _, c in ipairs(set) do slots[#slots + 1] = { { dict = 'move_climb', clip = c } } end
    if #slots == 0 then return PK3.Vault(info) end
    return PK3.Perform('bonnet', info, slots, function(S)
        return overPath(S, info, P3.bonnetApex or 0.3, 0.25, 0.8)
    end, 'native')
end

-- Small step up (under half a metre) while walking or running: no clip, no input, no XP.
function PK3.Step(info)
    local ped = PlayerPedId()
    PK.Begin('step')
    local from = GetEntityCoords(ped)
    local off = info.off
    local top = info.stand.z + off + 0.03
    local fwdXY = vector3(info.stand.x, info.stand.y, 0.0)
    local path = polyline({ from, vector3(from.x, from.y, top), vector3(fwdXY.x, fwdXY.y, top) }, { 0.0, 0.55, 1.0 })
    local ms = math.floor((P3.stepMs or 220) * PK.Slow())
    PK.expectMs = ms + 800
    local start = GetGameTimer()
    while PK.Live() do
        local t = math.min(1.0, (GetGameTimer() - start) / ms)
        local p = path(t)
        SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
        if t >= 1.0 then break end
        Wait(0)
    end
    if not PK.Live() then return end
    PK.End('step', true, from, true)
end

-- Clip lists for the debug menu and the animation check
function PK3.DebugSets()
    local out = { { id = 'vault', cands = PK3.VaultClips(false) } }
    for _, b in ipairs(P3.ClimbBands or {}) do
        local id = ('climb_%d'):format(math.floor(b.label * 100 + 0.5))
        local c = list(b.dict or 'move_climb', b.stand)
        for _, x in ipairs(list(b.dict or 'move_climb', b.run)) do c[#c + 1] = x end
        out[#out + 1] = { id = id, cands = c }
    end
    for side, set in pairs(P3.BonnetClips or {}) do
        out[#out + 1] = { id = 'bonnet_' .. side, cands = list('move_climb', set) }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Dev check: which candidate of each move loads, and its length
function PK.AnimReport()
    local out = {}
    local kinds = {}
    for k in pairs(Parkour.Anims) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, kind in ipairs(kinds) do
        local l = {}
        for _, pack in ipairs(Parkour.CustomAnims or {}) do
            if pack.dict and pack.clips and pack.clips[kind] then l[#l + 1] = { dict = pack.dict, clip = pack.clips[kind], custom = true } end
        end
        for _, a in ipairs(Parkour.Anims[kind]) do l[#l + 1] = a end
        for _, a in ipairs(l) do
            local exists = DoesAnimDictExist(a.dict)
            local loaded = exists and loadDict(a.dict)
            local len = loaded and GetAnimDuration(a.dict, a.clip) or 0.0
            out[#out + 1] = { kind = kind, dict = a.dict, clip = a.clip, exists = exists, loaded = loaded, length = len, custom = a.custom }
        end
    end
    for _, set in ipairs(PK3.DebugSets()) do
        for _, a in ipairs(set.cands) do
            local exists = DoesAnimDictExist(a.dict)
            local loaded = exists and loadDict(a.dict)
            local len = loaded and GetAnimDuration(a.dict, a.clip) or 0.0
            out[#out + 1] = { kind = set.id, dict = a.dict, clip = a.clip, exists = exists, loaded = loaded, length = len }
        end
    end
    resolved = {}
    return out
end
