-- bs_fighting v3 - clips, lunge, paired contact (synced scene with fallback), hit-stop.
-- Only our own ped is ever moved by us. A walker is posed only while bs_zombies has handed us its control.
-- Every clip ends with a blend-out, never an instant clear, so nobody is left without a pose.

FFA = { align = {} }     -- align = last few scene alignment errors, printed by /fftest

local S = Freeflow.Settings
local durCache = {}
local wanted = {}        -- dicts we keep loaded while fighting

-- Loads a dict and waits a little. Called before every play, so a dict the game streamed out is back first.
function FFA.Load(dict, maxMs)
    if not dict or not DoesAnimDictExist(dict) then return false end
    wanted[dict] = true
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + (maxMs or 1000)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- Keep every dict we used loaded (re-requested now and then)
CreateThread(function()
    while true do
        Wait(5000)
        for dict in pairs(wanted) do
            if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
        end
    end
end)

function FFA.Ms(dict, clip)
    if not dict or not clip then return 0 end
    local k = dict .. '/' .. clip
    if durCache[k] then return durCache[k] end
    if not FFA.Load(dict) then return 0 end
    local d = GetAnimDuration(dict, clip) or 0.0
    local ms = d > 0.0 and math.floor(d * 1000) or 0
    if ms > 0 then durCache[k] = ms end
    return ms
end

-- Ready to play right now: dict loaded and the clip really exists in it
function FFA.Ready(dict, clip)
    if FFA.Ms(dict, clip) <= 0 then return false end
    return FFA.Load(dict, 300) and (GetAnimDuration(dict, clip) or 0) > 0
end

-- A usable clip from a list. needVictim drops entries without a victim clip. avoid = clip name to skip.
function FFA.Pick(list, needVictim, index, avoid)
    if type(list) ~= 'table' then return nil end
    if list.dict then list = { list } end
    local ok = {}
    for _, c in ipairs(list) do
        if FFA.Usable(c.dict, c.plyr) and (not needVictim or (c.victim and FFA.Usable(c.dict, c.victim))) then ok[#ok + 1] = c end
    end
    if #ok == 0 then return nil end
    if #ok > 1 and avoid then
        for i = #ok, 1, -1 do if ok[i].plyr == avoid then table.remove(ok, i) end end
    end
    if index then return ok[((index - 1) % #ok) + 1] end
    return ok[math.random(#ok)]
end

-- GTA heading 0 faces +Y, positive turns left
local function rot2(x, y, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    return x * c - y * s, x * s + y * c
end
local function headingOf(x, y) return GetHeadingFromVector_2d(x, y) end
FFA.HeadingOf = headingOf

-- Clip-space offsets of a pair: gap length, attacker offset, victim offset, gap vector
function FFA.PairGap(c)
    if not c or not c.victim or FFA.Ms(c.dict, c.victim) <= 0 then return nil end
    local P = GetAnimInitialOffsetPosition(c.dict, c.plyr, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    local V = GetAnimInitialOffsetPosition(c.dict, c.victim, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    if not P or not V then return nil end
    local dx, dy = V.x - P.x, V.y - P.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.2 or len > 2.5 then return nil end
    return len, P, V, dx, dy
end

-- Hit-stop: local time scale, always put back
local stopToken = 0
function FFA.HitStop(ms)
    if not ms or ms <= 0 then return end
    stopToken = stopToken + 1
    local mine = stopToken
    SetTimeScale(S.hitStopScale or 0.2)
    SetTimeout(ms, function() if stopToken == mine then SetTimeScale(1.0) end end)
    SetTimeout(ms + 400, function() if stopToken == mine then SetTimeScale(1.0) end end)
end

function FFA.Shake(amp)
    if FF.FirstPerson() then amp = amp * (S.shakeFirstPerson or 1.5) end
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', amp)
end

local function outQuad(t) return 1.0 - (1.0 - t) * (1.0 - t) end
local function turnTo(cur, want, k)
    local d = ((want - cur + 540.0) % 360.0) - 180.0
    return cur + d * k
end
FFA.TurnTo = turnTo

-- What we last started on our own ped; the T-pose watchdog compares it with what is really playing
FFA.current = nil      -- { dict, clip, untilAt }

-- Ends our clip with a blend, then drops any upper-body layer. Locomotion takes over by itself.
function FFA.End(ped, dict, clip)
    if not DoesEntityExist(ped) then return end
    if dict and clip and IsEntityPlayingAnim(ped, dict, clip, 3) then StopAnimTask(ped, dict, clip, S.blendOut or 3.0) end
    ClearPedSecondaryTask(ped)
    if ped == PlayerPedId() then FFA.current = nil end
end

-- Lunge our own ped toward the target until `gap` metres remain. The end point follows the target every frame.
function FFA.Lunge(me, target, gap)
    -- kill the run first: momentum plus our position drive plus a clip is what twisted the body
    local v = GetEntityVelocity(me)
    if #(vector2(v.x, v.y)) > 2.0 then
        SetEntityVelocity(me, v.x * 0.15, v.y * 0.15, v.z)
        Wait(0)
    end
    local start = GetEntityCoords(me)
    local to = GetEntityCoords(target)
    local dist = #(vector2(to.x - start.x, to.y - start.y))
    local maxL = math.min(S.lungeMax, S.lungeBase + FF.Level() * S.lungePerLevel)
    if FF.FirstPerson() then maxL = math.min(maxL, S.lungeFirstPerson) end
    if dist - gap <= 0.05 then
        SetEntityHeading(me, headingOf(to.x - start.x, to.y - start.y))
        return true
    end
    -- stop short of walls and props
    local nx, ny = (to.x - start.x) / dist, (to.y - start.y) / dist
    local probe = math.min(maxL, dist - gap) + 0.4
    local ray = StartExpensiveSynchronousShapeTestLosProbe(start.x, start.y, start.z, start.x + nx * probe, start.y + ny * probe, start.z, 1 | 16, me, 7)
    local _, hit, hitAt = GetShapeTestResult(ray)
    local wallCap = maxL
    if hit == 1 or hit == true then wallCap = math.max(0.0, #(vector2(hitAt.x - start.x, hitAt.y - start.y)) - 0.45) end
    local t0 = GetGameTimer()
    while true do
        local el = GetGameTimer() - t0
        if el > (S.lungeTimeoutMs or 450) then break end
        if IsPedRagdoll(me) or IsPedDeadOrDying(me, true) or not DoesEntityExist(target) then return false end
        local k = outQuad(math.min(1.0, el / S.lungeMs))
        -- re-aim at where the target is now
        local tp = GetEntityCoords(target)
        local vx, vy = tp.x - start.x, tp.y - start.y
        local d = math.max(0.01, math.sqrt(vx * vx + vy * vy))
        local travel = math.max(0.0, math.min(maxL, wallCap, d - gap))
        local cur = GetEntityCoords(me)
        SetEntityCoordsNoOffset(me, start.x + vx / d * travel * k, start.y + vy / d * travel * k, cur.z, false, false, false)
        SetEntityHeading(me, headingOf(vx, vy))
        if k >= 1.0 then break end
        Wait(0)
    end
    local tp = GetEntityCoords(target)
    local a = GetEntityCoords(me)
    SetEntityHeading(me, headingOf(tp.x - a.x, tp.y - a.y))
    return true
end

-- Ask bs_zombies for the walker's control, waiting a few frames at most
function FFA.Victim(t, holdMs)
    if t.kind ~= 'zombie' or not FF.Zombies() then return nil end
    local untilAt = GetGameTimer() + (S.controlWaitMs or 250)
    repeat
        local ok, ped = pcall(function() return exports.bs_zombies:RequestVictim(t.id, holdMs) end)
        if ok and ped and ped ~= 0 then
            -- held: it stops walking for the strike
            if not IsPedRagdoll(ped) then TaskStandStill(ped, holdMs or 2500) end
            return ped
        end
        Wait(0)
    until GetGameTimer() > untilAt
    return nil
end

function FFA.Release(t)
    if t and t.kind == 'zombie' and FF.Zombies() then
        pcall(function() exports.bs_zombies:ReleaseVictim(t.id) end)
    end
end

-- T-pose check by bones (same test as bs_parkour): both hands far out sideways at shoulder height
local L_HAND, R_HAND = 18905, 57005
function FFA.Hands(ped)
    local l = GetPedBoneCoords(ped, L_HAND, 0.0, 0.0, 0.0)
    local r = GetPedBoneCoords(ped, R_HAND, 0.0, 0.0, 0.0)
    return GetOffsetFromEntityGivenWorldCoords(ped, l.x, l.y, l.z), GetOffsetFromEntityGivenWorldCoords(ped, r.x, r.y, r.z)
end
-- Both arms out, or one arm held dead straight out sideways (a weapon clip animates the weapon arm only)
local function armOut(h) return math.abs(h.x) > 0.62 and math.abs(h.y) < 0.25 and h.z > 0.25 and h.z < 0.65 end
function FFA.IsTPose(ped)
    local l, r = FFA.Hands(ped)
    if math.abs(l.x) > 0.55 and math.abs(r.x) > 0.55 and l.z > 0.2 and r.z > 0.2 and (l.x * r.x) < 0 then return true end
    return armOut(l) or armOut(r)
end

-- How a clip may be played: a flag (0 = full body, 48 = upper body over movement, 'adv'), 'test' = not known
-- yet, nil = banned. Bans and results are kept in this client's KVP and banned clips are shared by the server.
FFA.verified, FFA.bad = {}, {}

local function loadKvp(name)
    local ok, v = pcall(function() return json.decode(GetResourceKvpString(name) or '') end)
    return (ok and type(v) == 'table') and v or {}
end
local function saveKvp(name, t) pcall(function() SetResourceKvp(name, json.encode(t)) end) end

CreateThread(function()
    for k in pairs(loadKvp('ff_bans')) do FFA.bad[k] = true end
    for k, f in pairs(loadKvp('ff_verified')) do if f == 0 or f == 48 then FFA.verified[k] = f end end
end)

-- The safe set is for fists only: weapon dicts are always tested first
local function isSafe(dict, clip)
    if dict:find('@unarmed@', 1, true) == nil then return false end
    for _, pat in ipairs(Freeflow.SafePatterns or {}) do if clip:find(pat) then return true end end
    return false
end

function FFA.FlagFor(dict, clip)
    local key = dict .. '/' .. clip
    if FFA.bad[key] then return nil end
    local f = FFA.verified[key]
    if f == nil then f = (Freeflow.SafeClips or {})[key] end
    if f == false then return nil end
    if f ~= nil then return f end
    if isSafe(dict, clip) then return 0 end
    -- weapon clips never go full body until they have passed: upper-body layer only
    if dict:find('@unarmed@', 1, true) == nil then return 'layer' end
    return 'test'
end
function FFA.Usable(dict, clip) return FFA.Ms(dict, clip) > 0 and FFA.FlagFor(dict, clip) ~= nil end

local lastReport = 0
function FFA.Ban(key, why)
    if FFA.bad[key] then return end
    FFA.bad[key] = true
    FFA.verified[key] = nil
    local bans = loadKvp('ff_bans'); bans[key] = true; saveKvp('ff_bans', bans)
    local ver = loadKvp('ff_verified'); ver[key] = nil; saveKvp('ff_verified', ver)
    print(('[bs_fighting] clip %s banned (%s)'):format(key, why or 'T-pose'))
    if GetGameTimer() - lastReport > 3000 then
        lastReport = GetGameTimer()
        TriggerServerEvent('bs:fighting:clipBad', key)
    end
end

local function remember(key, flag)
    if FFA.verified[key] == flag then return end
    FFA.verified[key] = flag
    local ver = loadKvp('ff_verified'); ver[key] = flag; saveKvp('ff_verified', ver)
end

-- shared list from the server (on join and whenever someone's client bans a clip)
RegisterNetEvent('bs:fighting:clipBans', function(list)
    if type(list) ~= 'table' then return end
    for k, v in pairs(list) do if v and type(k) == 'string' then FFA.bad[k] = true; FFA.verified[k] = nil end end
end)
CreateThread(function() Wait(3000) TriggerServerEvent('bs:fighting:clipBansGet') end)
RegisterNetEvent('bs:fighting:clipUnban', function(key)
    if type(key) ~= 'string' then return end
    local bans = loadKvp('ff_bans')
    if key == 'all' then FFA.bad, bans = {}, {} else FFA.bad[key], bans[key] = nil, nil end
    saveKvp('ff_bans', bans)
end)

local INSTANT = 1000.0
local function issue(ped, dict, clip, flag, ms, blendIn)
    blendIn = blendIn or 8.0
    if flag == 'adv' then
        local p = GetEntityCoords(ped)
        TaskPlayAnimAdvanced(ped, dict, clip, p.x, p.y, p.z, 0.0, 0.0, GetEntityHeading(ped), blendIn, -(S.blendOut or 3.0), ms, 0, 0.0, 0, 0)
    else
        TaskPlayAnim(ped, dict, clip, blendIn, -(S.blendOut or 3.0), ms, flag, 0.0, false, false, false)
    end
end

-- Solo clip on a ped we control. Returns its play length in ms (0 = nothing played).
-- Unknown clips start as an upper-body layer, are checked for 2 frames, then go full body.
-- Every frame of the first poseCheckMs is checked; a T-pose is dropped at once (layer, then ban).
function FFA.Solo(ped, dict, clip, speed, portion)
    if not FFA.Ready(dict, clip) then return 0 end
    local flag = FFA.FlagFor(dict, clip)
    if flag == nil then return 0 end
    local full = FFA.Ms(dict, clip)
    speed = speed or 1.0
    local ms = math.floor(full * (portion or 1.0) / speed)
    local key = dict .. '/' .. clip
    local testing = flag == 'test'
    local layerOnly = flag == 'layer'
    local cur = (testing or layerOnly) and 48 or flag
    issue(ped, dict, clip, cur, ms)
    local mine = { dict = dict, clip = clip, untilAt = GetGameTimer() + ms }
    if ped == PlayerPedId() then FFA.current = mine end

    local function drop(why)
        StopAnimTask(ped, dict, clip, INSTANT)
        ClearPedSecondaryTask(ped)
        if ped == PlayerPedId() then FFA.failedAt = GetGameTimer() end
        if FFA.current == mine then FFA.current = nil end
        FFA.Ban(key, why)
    end
    local function reissue(f)
        local ph = IsEntityPlayingAnim(ped, dict, clip, 3) and GetEntityAnimCurrentTime(ped, dict, clip) or 0.0
        issue(ped, dict, clip, f, math.max(100, math.floor(ms * (1.0 - ph))), INSTANT)
        SetEntityAnimCurrentTime(ped, dict, clip, ph)
        if speed ~= 1.0 then SetEntityAnimSpeed(ped, dict, clip, speed) end
        cur = f
    end

    CreateThread(function()
        Wait(0)
        if speed ~= 1.0 and IsEntityPlayingAnim(ped, dict, clip, 3) then SetEntityAnimSpeed(ped, dict, clip, speed) end
        local t0, frames, fullFrames = GetGameTimer(), 0, 0
        while GetGameTimer() - t0 < (S.poseCheckMs or 300) and DoesEntityExist(ped) do
            if not IsEntityPlayingAnim(ped, dict, clip, 3) then return end
            frames = frames + 1
            local bad = FFA.IsTPose(ped)
            if bad then
                -- full body failed: fall back to the layer once; a layer that fails is banned
                if cur ~= 48 and frames > 0 then
                    reissue(48)
                    remember(key, 48)
                    testing = false
                else
                    return drop('T-pose as upper body')
                end
            elseif testing and frames >= 2 then
                testing = false
                reissue(0)
            elseif cur == 0 then
                fullFrames = fullFrames + 1
            end
            Wait(0)
        end
        -- passed the whole check full body: next time it starts full body straight away
        if cur == 0 and fullFrames > 5 then remember(key, 0) end
        if layerOnly and cur == 48 and frames > 5 then remember(key, 48) end
    end)
    return ms
end

local UNARMED = `WEAPON_UNARMED`
local function weaponNow(ped)
    local w = GetSelectedPedWeapon(ped)
    return (w == 0) and UNARMED or w
end

local function logAlign(kind, err, extra)
    local a = FFA.align
    a[#a + 1] = { kind = kind, err = err, extra = extra, at = GetGameTimer() }
    if #a > 8 then table.remove(a, 1) end
end

-- Plays the attacker clip (and the victim reaction when we hold the walker).
-- Gap and alignment are measured here, when the clip starts. onImpact() runs once at the impact moment.
-- opts: speed, portion, victimPed (held walker), trackPed (unheld target to keep facing), weapon, cancel()
function FFA.Strike(me, t, c, opts)
    opts = opts or {}
    local speed = opts.speed or 1.0
    local portion = opts.portion or 1.0
    if not FFA.Ready(c.dict, c.plyr) or not FFA.FlagFor(c.dict, c.plyr) then return false end
    local full = FFA.Ms(c.dict, c.plyr)
    local vped = opts.victimPed
    if FF.debug then
        local cls = FF.WeaponClass(me)
        print(('[bs_fighting] strike %s/%s class=%s speed=%.1f flag=%s'):format(c.dict, c.plyr, tostring(cls),
            GetEntitySpeed(me), tostring(FFA.FlagFor(c.dict, c.plyr))))
    end
    -- face the target before the clip starts
    local face = vped or (t and t.ped) or nil
    if face and DoesEntityExist(face) then
        local a, b = GetEntityCoords(me), GetEntityCoords(face)
        SetEntityHeading(me, headingOf(b.x - a.x, b.y - a.y))
    end
    if vped and (not DoesEntityExist(vped) or IsEntityDead(vped) or IsPedRagdoll(vped)) then vped = nil end
    local length = math.floor(full * portion / speed)
    local impactAt = math.floor(full * (c.hitAt or S.impactAt) / speed)
    local scene, usedScene, expectV = nil, false, nil

    -- paired: one networked scene anchored on the walker where it stands now, so it never slides;
    -- we move by the small error instead (capped by maxAttackerShift)
    if vped and S.pairs and S.pairScene and c.victim and FFA.Ready(c.dict, c.victim) then
        local gap, P, V, dx, dy = FFA.PairGap(c)
        if gap then
            local A = GetEntityCoords(me)
            local Vw = GetEntityCoords(vped)
            local R = headingOf(Vw.x - A.x, Vw.y - A.y) - headingOf(dx, dy)
            local gx, gy = rot2(dx, dy, R)
            local err = #(vector2(A.x + gx - Vw.x, A.y + gy - Vw.y))
            logAlign('pre', err)
            if err <= (S.maxAttackerShift or 0.5) then
                local vx, vy = rot2(V.x, V.y, R)
                local ground = Vw.z - GetEntityHeightAboveGround(vped)
                local ox, oy, oz = Vw.x - vx, Vw.y - vy, ground - V.z
                scene = NetworkCreateSynchronisedScene(ox, oy, oz, 0.0, 0.0, R, 2, false, false, 1.0, 0.0, 1.0)
                NetworkAddPedToSynchronisedScene(me, scene, c.dict, c.plyr, 8.0, -(S.blendOut or 3.0), 0, 0, 1000.0, 0)
                NetworkAddPedToSynchronisedScene(vped, scene, c.dict, c.victim, 8.0, -(S.blendOut or 3.0), 0, 0, 1000.0, 0)
                NetworkStartSynchronisedScene(scene)
                usedScene, expectV = true, Vw
                FFA.current = { dict = c.dict, clip = c.plyr, untilAt = GetGameTimer() + full, scene = true }
                length = math.floor(full * portion)
                impactAt = math.floor(full * (c.hitAt or S.impactAt))
            end
        end
    end

    local function unpaired()
        FFA.Solo(me, c.dict, c.plyr, speed, portion)
        if vped and DoesEntityExist(vped) and not IsPedRagdoll(vped) then
            local A = GetEntityCoords(me)
            -- turn the walker to face us, then nudge it to the clip gap if it is close
            local Vw = GetEntityCoords(vped)
            SetEntityHeading(vped, headingOf(A.x - Vw.x, A.y - Vw.y))
            local f = GetEntityForwardVector(me)
            local gap = FFA.PairGap(c) or S.lungeStopGap
            local want = vector3(A.x + f.x * gap, A.y + f.y * gap, Vw.z)
            if #(want - Vw) <= (S.fallbackSnap or 0.45) then
                SetEntityCoordsNoOffset(vped, want.x, want.y, want.z, false, false, false)
            end
            if c.victim and FFA.Ready(c.dict, c.victim) and FFA.FlagFor(c.dict, c.victim) then
                FFA.Solo(vped, c.dict, c.victim, speed, portion)
            elseif opts.stagger then
                local a = Freeflow.PlayerReact.light
                FFA.Solo(vped, a.dict, a.clip, 1.0, 0.7)
            end
        end
    end
    if not usedScene then unpaired() end

    local t0 = GetGameTimer()
    local hitDone, checked, frames = false, false, 0
    local ok = true
    local startedAt = GetGameTimer()
    local track = (not vped) and opts.trackPed or nil
    local faceEnt = vped or opts.trackPed
    while true do
        Wait(0)
        frames = frames + 1
        local el = GetGameTimer() - t0
        if IsPedDeadOrDying(me, true) or IsPedRagdoll(me) or (opts.cancel and opts.cancel())
            or (opts.weapon and weaponNow(me) ~= opts.weapon) then ok = false break end
        -- our clip failed the bone check: GTA's own melee swings this once
        if (FFA.failedAt or 0) >= startedAt then
            ok = false
            FFA.NativeSwing(me, t and t.ped)
            break
        end
        -- a scene that did not take shows as a T-pose: check within a few frames, not later
        if usedScene and not checked and (frames >= 3 or el >= (S.sceneCheckMs or 120)) then
            local playing = IsEntityPlayingAnim(me, c.dict, c.plyr, 3)
            if playing or el >= (S.sceneCheckMs or 120) then
                checked = true
                if playing and expectV and DoesEntityExist(vped) then
                    logAlign('scene', #(GetEntityCoords(vped) - expectV))
                end
                if not playing then
                    logAlign('scene', -1, 'not playing')
                    NetworkStopSynchronisedScene(scene); scene = nil; usedScene = false
                    ClearPedTasks(me)
                    if DoesEntityExist(vped) and not IsEntityDead(vped) then ClearPedTasks(vped) end
                    unpaired()
                    length = math.floor(full * portion / speed)
                    impactAt = math.floor(full * (c.hitAt or S.impactAt) / speed)
                    t0 = GetGameTimer()
                end
            end
        end
        -- keep facing the target until impact; a held walker keeps facing us
        if not usedScene and not hitDone and faceEnt and DoesEntityExist(faceEnt) then
            local a, b = GetEntityCoords(me), GetEntityCoords(faceEnt)
            SetEntityHeading(me, headingOf(b.x - a.x, b.y - a.y))
            if vped and NetworkHasControlOfEntity(vped) then SetEntityHeading(vped, headingOf(a.x - b.x, a.y - b.y)) end
        end
        -- not held: close the gap until impact
        if track and not hitDone and DoesEntityExist(track) then
            local a, b = GetEntityCoords(me), GetEntityCoords(track)
            local vx, vy = b.x - a.x, b.y - a.y
            local d = math.sqrt(vx * vx + vy * vy)
            local want = (opts.gap or S.lungeStopGap) + 0.15
            if d > want and d < want + 2.0 then
                local step = math.min(d - want, (S.trackSpeed or 3.0) * GetFrameTime())
                SetEntityCoordsNoOffset(me, a.x + vx / d * step, a.y + vy / d * step, a.z, false, false, false)
            end
        end
        if not hitDone and el >= impactAt then
            hitDone = true
            if opts.onImpact then opts.onImpact(usedScene) end
        end
        if el >= length then break end
    end
    if not hitDone and ok and opts.onImpact then opts.onImpact(usedScene) end
    if usedScene then
        NetworkStopSynchronisedScene(scene)
        -- a stopped scene leaves the ped without a task: blend back to normal
        ClearPedTasks(me)
        if vped and DoesEntityExist(vped) and not IsEntityDead(vped) then ClearPedTasks(vped) end
        FFA.current = nil
    else
        FFA.End(me, c.dict, c.plyr)
    end
    return true
end

-- One native melee swing at the target when our clip can't be shown safely (weapon in hand)
function FFA.NativeSwing(me, target)
    FF.nativeUntil = GetGameTimer() + 800
    if not target or not DoesEntityExist(target) or IsEntityDead(target) then return end
    if FF.debug then print('[bs_fighting] native melee fallback for this swing') end
    TaskCombatPed(me, target, 0, 16)
    SetTimeout(600, function()
        local p = PlayerPedId()
        if DoesEntityExist(p) and not IsPedRagdoll(p) then ClearPedTasks(p) end
    end)
end
