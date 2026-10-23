ZProbe = ZProbe or { task = {}, driven = {}, rate = {} }

-- bs_zombies - crawlers: zombies that drag themselves along the floor

-- Crash guard: only touch peds that exist
local function pedOk(ped, allowDown)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if not allowDown and (IsPedRagdoll(ped) or IsPedGettingUp(ped)) then return false end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return false end
    return true
end

local C = Zombies.Crawl or {}
local S = Zombies.Settings or {}

-- The dictionary

-- If nutria_crawl_anims isn't started (not installed, misspelled, or ensured after bs_zombies) the dict never loads
local dictReady = false
local nextTry   = 0
local warned    = false

-- Non-blocking. True only when the dictionary is resident.
local function dictAvailable()
    if dictReady then return true end

    local dict = C.dict
    if not dict then return false end
    -- Dict not streamed at all: never request it or play from it.
    if not DoesAnimDictExist(dict) then
        if not warned then
            warned = true
            print(('^1[BeyondSurvival]^7 (zombies) anim dict "%s" does not exist - is nutria_crawl_anims started?'):format(dict))
        end
        return false
    end

    if HasAnimDictLoaded(dict) then
        dictReady = true
        return true
    end

    local now = GetGameTimer()
    if now < nextTry then return false end
    nextTry = now + (C.dictRetry or 15000)

    RequestAnimDict(dict)

    if not warned then
        warned = true
        print(('^3[BeyondSurvival]^7 (zombies) anim dict "%s" is not loaded yet. '
            .. 'Crawlers will drag themselves around without their crawl pose '
            .. 'until it is. It is streamed by [third-party]/nutria_crawl_anims '
            .. '- check that "ensure nutria_crawl_anims" is in server.cfg ABOVE '
            .. '"ensure bs_zombies".'):format(tostring(dict)))
    end

    return false
end

-- Small shared predicates

-- Is this entry something that crawls?
local function crawls(entry)
    return entry ~= nil and entry.def ~= nil and entry.def.crawls == true
end

-- Same safe-zone rule as cl_spawner.lua, against the shared Zones.Safe (config_zones.lua is a shared_script)
local function inSafeZone(x, y)
    local padding = S.safeZonePadding
        or (Streaming and Streaming.safeZonePaddingFallback)
        or 55.0

    for _, zone in ipairs((Zones and Zones.Safe) or {}) do
        local r  = (zone.radius or 0.0) + padding
        local dx = zone.coords.x - x
        local dy = zone.coords.y - y
        if (dx * dx + dy * dy) <= (r * r) then return true end
    end
    return false
end

-- Speed in metres per second, all in one function
local function crawlSpeed(entry)
    local def  = entry.def
    local rate = def.shambleRate or 0.2

    if entry.state == 'hunting' then
        rate = def.chaseRate or rate
    elseif entry.state == 'drawn' then
        rate = def.drawnRate or rate
    end

    if S.maxMoveRate and rate > S.maxMoveRate then rate = S.maxMoveRate end
    rate = ZDiff.Rate(rate, ZDiff.Local('speed'))

    local mps = (C.metresPerSecond or 1.45) * rate
    local cap = (C.maxSpeed or 0.9) * math.max(1.0, math.min(1.35, ZDiff.Local('speed')))
    if mps > cap then mps = cap end
    return mps
end

-- The pose

-- Which clip: loop unless a turn clip is configured and the ped is turning hard. turnClip is nil by default.
local function clipFor(turning)
    if turning and C.turnClip then return C.turnClip end
    return C.loop
end

-- Puts the crawl on and keeps it on
-- @param moving true if the ped is travelling this frame
-- @param turning true if the ped is rotating hard toward its goal
local function applyCrawl(entry, moving, turning)
    local ped = entry.ped
    -- Never task an anim on a body the engine owns (dead, ragdoll, getting up).
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    if IsPedRagdoll(ped) or IsPedGettingUp(ped) then return end
    if not HasAnimDictLoaded(C.dict or '') then dictReady = false; return end

    local dict = C.dict
    local clip = clipFor(turning)
    if not dict or not clip then return end

    -- Phase preservation: only matters on the rare outside task clear (revive, ragdoll recovery)
    local preserve = C.preservePhase ~= false

    if IsEntityPlayingAnim(ped, dict, clip, 3) then
        if preserve then
            local ok, phase = pcall(GetEntityAnimCurrentTime, ped, dict, clip)
            if ok and type(phase) == 'number' and phase >= 0.0 and phase <= 1.0 then
                entry.crawlPhase = phase
            end
        end

        -- Prone freeze, set every frame: the engine restores the clip's own rate whenever the task is refreshed (see cl_prone.lua)
        pcall(SetEntityAnimSpeed, ped, dict, clip,
            moving and (C.speed or 1.0) or 0.0)
        return
    end

    local lock  = C.lockRootMotion ~= false
    local phase = preserve and entry.crawlPhase or nil

    -- TaskPlayAnim(ped, dict, clip, blendIn, blendOut, duration, flag, startPhase, lockX, lockY, lock
    if not pedOk(ped, true) or not HasAnimDictLoaded(dict) then return end
    TaskPlayAnim(ped, dict, clip,
        C.blendIn or 8.0, C.blendOut or -8.0,
        -1, C.flag or 1, phase or 0.0,
        lock, lock, lock)

    if phase then
        pcall(SetEntityAnimCurrentTime, ped, dict, clip, phase)
    end

    pcall(SetEntityAnimSpeed, ped, dict, clip,
        moving and (C.speed or 1.0) or 0.0)
end

-- Take the crawl off, for states that own the body (grab, feeding)
local function stopCrawl(entry)
    local ped = entry.ped
    if not ped or not DoesEntityExist(ped) then return end
    if not C.dict then return end

    if C.loop then pcall(StopAnimTask, ped, C.dict, C.loop, 2.0) end
    if C.turnClip then pcall(StopAnimTask, ped, C.dict, C.turnClip, 2.0) end
    entry.crawlPhase = nil
end

-- Where it is trying to get to

-- Idle drift, replacing cl_ai.lua's driftStep() (its TaskGoStraightToCoord is no use to a crawler)
local function driftGoal(entry, now)
    local at = GetEntityCoords(entry.ped)

    if not entry.crawlAnchor then
        entry.crawlAnchor = at
    else
        local a = entry.crawlAnchor
        local lerp = C.anchorLerp or 0.02
        entry.crawlAnchor = vector3(
            a.x + (at.x - a.x) * lerp,
            a.y + (at.y - a.y) * lerp,
            a.z + (at.z - a.z) * lerp)
    end

    -- Stand still between legs: a crawler that never stops looks driven.
    if entry.crawlPause then
        if now < entry.crawlPause then return nil end
        entry.crawlPause = nil
    end

    local goal = entry.crawlGoal
    if goal and now < (entry.crawlLegUntil or 0)
       and #(at - goal) > (C.arrive or 1.0) then
        return goal
    end

    -- Leg over (arrived, or timed out against a fence)
    if goal then
        entry.crawlGoal = nil
        entry.crawlPause = now + math.random(C.pauseMin or 2400, C.pauseMax or 7000)
        return nil
    end

    local legMin = C.legMin or 3.0
    local legMax = C.legMax or 9.0
    local dist    = legMin + math.random() * (legMax - legMin)
    local bearing = math.random() * math.pi * 2.0

    local tx = at.x - math.sin(bearing) * dist
    local ty = at.y + math.cos(bearing) * dist

    -- The leash, same as walker drift
    local anchor = entry.crawlAnchor
    local ax, ay = tx - anchor.x, ty - anchor.y
    local leash  = C.leash or 12.0
    if (ax * ax + ay * ay) > (leash * leash) then
        local home = math.atan(anchor.y - at.y, anchor.x - at.x)
            + (math.random() * 1.6 - 0.8)
        tx = at.x + math.cos(home) * dist
        ty = at.y + math.sin(home) * dist
    end

    entry.crawlGoal = vector3(tx, ty, at.z)
    -- Generous: a timeout for being stuck, not a travel budget.
    entry.crawlLegUntil = now + (C.legTimeout or 20000)
    return entry.crawlGoal
end

-- What this crawler wants to be next to this frame
local function goalFor(entry, now)
    local state = entry.state

    if state == 'hunting' then
        local t = entry.hunted
        if t and DoesEntityExist(t) then return GetEntityCoords(t) end
        return nil
    end

    if state == 'drawn' then
        return entry.drawnTo
    end

    if state == 'idle' then
        return driftGoal(entry, now)
    end

    -- 'grab', 'feeding', 'disturbed' and anything new: not ours to move.
    return nil
end

-- Not crawling into things

-- Three whiskers (left, centre, right) instead of one probe

-- Bearing offsets for the three whiskers, in firing order.
local WHISKERS = { 0.0, -1.0, 1.0 }     -- centre, left, right (x whiskerAngle)

-- Fresh whisker state for one crawler. hit is nil for "never measured"
local function whiskerState(entry)
    local w = entry.crawlWhiskers
    if not w then
        w = { {}, {}, {} }
        entry.crawlWhiskers = w
        entry.crawlWhiskerNext = 1
    end
    return w
end

-- Obstacle handling, not pathfinding
-- @return number steer offset in degrees to add to the goal bearing; 0 means clear, bounded by avoidAngle.
local function probeAhead(entry, now, heading)
    local ped = entry.ped
    local w = whiskerState(entry)

    -- Read back a probe fired on an earlier frame.
    if entry.crawlProbe then
        local status, hit, _, _, entityHit = GetShapeTestResult(entry.crawlProbe)

        -- 1 = still working. Leave it and look again next frame.
        if status ~= 1 then
            local slot = entry.crawlProbeSlot or 1
            entry.crawlProbe = nil

            -- A hit on the ped itself or on its target is not an obstacle. entityHit is compared by handle
            w[slot].hit = (hit == 1 and entityHit ~= ped and entityHit ~= entry.hunted)
            w[slot].until_ = now + (C.whiskerMemory or 1200)
        end
    end

    if now >= (entry.crawlProbeAt or 0) then
        entry.crawlProbeAt = now + (C.probeEvery or 220)

        -- One probe, three directions taking turns
        local slot = entry.crawlWhiskerNext or 1
        entry.crawlWhiskerNext = (slot % #WHISKERS) + 1
        entry.crawlProbeSlot = slot

        local at   = GetEntityCoords(ped)
        local rad  = math.rad(heading + WHISKERS[slot] * (C.whiskerAngle or 42.0))
        local dist = C.probeDistance or 1.1
        local z    = at.z + (C.probeHeight or 0.35)

        -- A capsule, not a ray: a crawler is wide and low, and a thin ray slips between railings and table legs
        entry.crawlProbe = StartShapeTestCapsule(
            at.x, at.y, z,
            at.x - math.sin(rad) * dist, at.y + math.cos(rad) * dist, z,
            C.probeRadius or 0.35,
            C.probeFlags or 17,
            ped, 4)
    end

    -- Combine the three answers into one angle
    local function live(slot)
        local s = w[slot]
        if s.hit == nil then return nil end
        if s.until_ and now > s.until_ then return nil end
        return s.hit
    end

    local centre, left, right = live(1), live(2), live(3)
    local steer = 0.0

    if left  == true then steer = steer + 1.0 end   -- pushed away from the left
    if right == true then steer = steer - 1.0 end
    if left  == false and right == true then steer = steer - 0.5 end
    if right == false and left  == true then steer = steer + 0.5 end

    if centre == true then
        -- Straight ahead is blocked and the flanks didn't decide
        if steer == 0.0 then
            if not entry.crawlAvoidSign or now > (entry.crawlBlockedUntil or 0) then
                entry.crawlAvoidSign = (math.random(2) == 1) and 1.0 or -1.0
            end
            entry.crawlBlockedUntil = now + (C.avoidFor or 900)
            steer = entry.crawlAvoidSign
        end
        -- Blocked ahead means lean harder, whichever way was chosen.
        steer = steer * 1.6
    elseif centre == false and steer == 0.0 then
        entry.crawlAvoidSign = nil
    end

    if steer == 0.0 then return 0.0 end
    if steer >  1.0 then steer =  1.0 end
    if steer < -1.0 then steer = -1.0 end

    return steer * (C.avoidAngle or 55.0)
end

-- Something the whiskers can't see refused the move (wall, step, missing floor)
local function markBlocked(entry, now)
    local w = whiskerState(entry)
    w[1].hit = true
    w[1].until_ = now + (C.whiskerMemory or 1200)

    if not entry.crawlAvoidSign or now > (entry.crawlBlockedUntil or 0) then
        entry.crawlAvoidSign = (math.random(2) == 1) and 1.0 or -1.0
    end
    entry.crawlBlockedUntil = now + (C.avoidFor or 900)
end

-- Moving one crawler, one frame

-- Turn toward a bearing at a bounded rate
local function turnCrawler(ped, wantHeading, dt)
    local heading = GetEntityHeading(ped)
    local diff    = (wantHeading - heading + 540.0) % 360.0 - 180.0
    local step    = (C.turnRate or 90.0) * dt

    if math.abs(diff) <= step then
        SetEntityHeading(ped, wantHeading)
        return 0.0
    end

    SetEntityHeading(ped, heading + (diff > 0 and step or -step))
    return math.abs(diff) - step
end

-- Ground handling
-- @return number|nil the z to move to, or nil to refuse this move
-- Ped coords are the pelvis (~1m above the feet); the anim lowers the body itself.
local function rootOff() return C.crawlZOffset or 1.0 end

local function groundFor(entry, at, nx, ny, dt)
    local off = rootOff()
    at = vector3(at.x, at.y, at.z - off) -- work in feet height
    local anchor = entry.crawlGroundZ

    -- Probe from above the higher of the two, so a ped that has sunk can still see its surface.
    local from = math.max(at.z, anchor or at.z) + 1.0
    local found, gz = GetGroundZFor_3dCoord(nx, ny, from, false)

    if not found then
        -- No floor at all: a cliff edge, hole or unstreamed collision
        return nil
    end

    local rise = gz - at.z

    if rise > (C.stepUp or 0.45) then
        -- Too tall to climb
        return nil
    end

    if rise < -(C.stepDown or 1.2) then
        -- A real drop: a crawler must not dive off a roof to reach you.
        return nil
    end

    -- Eased, not snapped: even an accepted drop is taken at a bounded rate, so a surface a metre down is met over several frames
    local maxFall = (C.maxDescentPerSec or 3.0) * dt
    if rise < -maxFall then
        return at.z - maxFall + off
    end

    return gz + off
end

-- Try to translate one crawler toward goal
local function driveCrawler(entry, goal, now, dt)
    local ped = entry.ped
    local at  = GetEntityCoords(ped)

    -- Rescue first: if the body is well below its last known ground, its own coordinates are what is wrong
    local anchor = entry.crawlGroundZ
    if anchor and at.z < (anchor - (C.fallRescue or 1.8)) then
        local found, gz = GetGroundZFor_3dCoord(at.x, at.y, anchor + 2.0 - rootOff(), false)
        local to = found and (gz + rootOff()) or anchor
        SetEntityCollision(ped, true, true)
        SetEntityCoordsNoOffset(ped, at.x, at.y, to, false, false, true)
        entry.crawlGroundZ = to
        entry.crawlRescues = (entry.crawlRescues or 0) + 1
        return false, false
    end

    local dx, dy = goal.x - at.x, goal.y - at.y
    local flat = math.sqrt(dx * dx + dy * dy)

    -- Close enough: stop short instead of occupying the target's spot. cl_attack's TryStrike reaches
    if flat <= (C.arrive or 1.0) then return false, false end

    local want = GetHeadingFromVector_2d(dx, dy)

    -- Lean off whatever the whiskers feel. A real number, not a sign.
    want = (want + probeAhead(entry, now, GetEntityHeading(ped))) % 360.0

    local err = turnCrawler(ped, want, dt)
    local turning = err > (C.turnClipAngle or 25.0)

    -- It arcs instead of stopping to pivot
    local stopAt = C.stopAngle or 120.0
    if err >= stopAt then return false, turning end

    local factor = 1.0 - (err / stopAt)
    factor = factor * factor
    local floor = C.minMoveFactor or 0.08
    if factor < floor then factor = floor end

    local speed = crawlSpeed(entry) * dt * factor
    local rad   = math.rad(GetEntityHeading(ped))
    local nx    = at.x - math.sin(rad) * speed
    local ny    = at.y + math.cos(rad) * speed

    -- Safe zone line: a hand-moved ped answers to no navmesh, so this is what keeps crawlers out of camp
    if inSafeZone(nx, ny) then return false, turning end

    local nz = groundFor(entry, at, nx, ny, dt)
    if not nz then
        -- No floor, too tall, or too far down. Feed it to the whiskers so steering curves around it.
        markBlocked(entry, now)
        return false, turning
    end

    -- Same native cl_sync.lua uses to place non-hosted zombies and cl_prone uses for prone players
    SetEntityCoordsNoOffset(ped, nx, ny, nz, false, false, true)

    -- The anchor moves with it
    entry.crawlGroundZ = nz
    return true, turning
end

-- One crawler, one frame. No yields in here.
local function stepCrawler(entry, now, dt)
    local ped = entry.ped
    if not ped or not DoesEntityExist(ped) then return end
    if entry.net and not entry.hosted then return end

    -- A dead crawler is left alone; corpses are cl_combat's business, and a crawling corpse looks like a zombie that won't die
    if entry.dying or IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
        return
    end

    -- Also left alone: the states that own the body
    local state = entry.state
    if state == 'grab' or state == 'feeding' then
        if not entry.crawlOff then
            stopCrawl(entry)
            entry.crawlOff = true
        end
        return
    end
    entry.crawlOff = nil

    -- Already on the floor: a ragdolled crawler is mid-flop, and posing or dragging it would fight the physics
    if IsPedRagdoll(ped) then
        -- keep the last good height; if the body drops way under it, it went through the floor
        entry.crawlLastZ = entry.crawlGroundZ or entry.crawlLastZ
        entry.crawlGroundZ = nil
        local last = entry.crawlLastZ
        local p = GetEntityCoords(ped)
        if last and p.z < last - 3.0 then
            local found, gz = GetGroundZFor_3dCoord(p.x, p.y, last + 1.0, false)
            SetEntityCollision(ped, true, true)
            SetEntityCoordsNoOffset(ped, p.x, p.y, (found and gz or last - rootOff()) + 0.3, false, false, true)
        end
        return
    end

    -- Seed the ground anchor here, not at spawn
    if not entry.crawlGroundZ then
        local where = GetEntityCoords(ped)
        local found, gz = GetGroundZFor_3dCoord(where.x, where.y, where.z + 2.0, false)
        if found and math.abs(gz + rootOff() - where.z) <= 1.0 then
            entry.crawlGroundZ = gz + rootOff()
        elseif found and where.z < gz + rootOff() - 0.3 then
            -- already sunk (old saves/sync): lift it back out
            SetEntityCoordsNoOffset(ped, where.x, where.y, gz + rootOff(), false, false, true)
            entry.crawlGroundZ = gz + rootOff()
        end
    end

    local moving  = false
    local turning = false

    -- Movement is the host's job: other clients' copies are lerped to the host position by
    if entry.hosted then
        local goal = goalFor(entry, now)
        if goal then
            moving, turning = driveCrawler(entry, goal, now, dt)
        end
    end

    if not entry.dying and dictAvailable() then
        applyCrawl(entry, moving, turning)
    end
end

-- The pass

-- Per frame: movement written 10 times a second would be teleports
CreateThread(function()
    -- Nothing to do if the crawl is not configured; the thread just sleeps.
    if not C.dict or not C.loop then
        print('^3[BeyondSurvival]^7 (zombies) Zombies.Crawl is not configured; '
            .. 'crawlers will not crawl.')
        return
    end

    local last = GetGameTimer()

    -- IsLoaded is an export (resource boundary call), so the result is cached and refreshed once a second
    local coreReady   = false
    local coreCheckAt = 0

    while true do
        Wait(0)

        local now = GetGameTimer()

        if now >= coreCheckAt then
            coreCheckAt = now + 1000
            local ok, loaded = pcall(function() return exports.bs_core:IsLoaded() end)
            coreReady = ok and loaded == true
        end

        -- Real elapsed time, clamped to 0.1s
        local dt = (now - last) / 1000.0
        last = now
        if dt > 0.1 then dt = 0.1 end

        local live = Zed and Zed.live
        local any = false

        if live and coreReady then
            for _, entry in pairs(live) do
                if crawls(entry) then
                    any = true

                    -- Clear entry.reacher so cl_attack's SetReaching (upper-body anim) never plays over the crawl.
                    if entry.reacher then entry.reacher = false end

                    -- pcall per zombie: one bad ped handle only costs that crawler a frame.
                    pcall(stepCrawler, entry, now, dt)
                end
            end
        end

        -- No crawlers nearby: sleep. last is reset so the sleep is not counted in the next dt.
        if not any then
            Wait(250)
            last = GetGameTimer()
        end
    end
end)

-- Diagnostics

exports('IsCrawlerPed', function(ped)
    local live = Zed and Zed.live
    if not live or not ped then return false end
    for _, entry in pairs(live) do
        if entry.ped == ped then return crawls(entry) end
    end
    return false
end)

-- Same idea as /zanims in cl_sync.lua: check that the animation is there and something is moving it
RegisterCommand('zcrawl', function()
    local dict = C.dict or '(unset)'
    local lines = {
        ('dict %s: %s'):format(dict,
            HasAnimDictLoaded(C.dict or '') and 'LOADED' or 'NOT LOADED'),
        ('clip: %s   turnClip: %s   flag: %s (1 = REPEAT, PRIMARY)')
            :format(tostring(C.loop), tostring(C.turnClip), tostring(C.flag)),
        ('lockRootMotion: %s   clip rate: %s   ground: %.2f m/s ceiling')
            :format(tostring(C.lockRootMotion ~= false), tostring(C.speed),
                    C.maxSpeed or 0.9),
        ('turnRate: %s deg/s   stopAngle: %s   arrive: %s m')
            :format(tostring(C.turnRate), tostring(C.stopAngle or 120.0),
                    tostring(C.arrive)),
        ('whiskers: 3 @ %s deg, memory %s ms | descent cap %s m/s, rescue at %s m')
            :format(tostring(C.whiskerAngle or 42.0), tostring(C.whiskerMemory or 1200),
                    tostring(C.maxDescentPerSec or 3.0), tostring(C.fallRescue or 1.8)),
        ('step clips: %d   turn clips: %d   (listed in config, none used)')
            :format(#(C.steps or {}), #(C.turns or {})),
    }

    local total, crawling, hosted, rescues, sunk = 0, 0, 0, 0, 0
    for _, entry in pairs((Zed and Zed.live) or {}) do
        if crawls(entry) then
            total = total + 1
            if entry.hosted then hosted = hosted + 1 end
            rescues = rescues + (entry.crawlRescues or 0)

            -- Crawlers below the ground they last stood on
            if entry.crawlGroundZ and entry.ped and DoesEntityExist(entry.ped)
               and GetEntityCoords(entry.ped).z < (entry.crawlGroundZ - 0.5) then
                sunk = sunk + 1
            end
            if entry.ped and DoesEntityExist(entry.ped)
               and IsEntityPlayingAnim(entry.ped, C.dict or '', C.loop or '', 3) then
                crawling = crawling + 1
            end
        end
    end
    lines[#lines + 1] = ('crawlers near you: %d (%d hosted here), %d playing the clip')
        :format(total, hosted, crawling)
    lines[#lines + 1] = ('fall rescues this session: %d   below ground right now: %d')
        :format(rescues, sunk)

    for _, line in ipairs(lines) do
        print('^2[BeyondSurvival]^7 (crawl) ' .. line)
    end
    TriggerEvent('bs:ui:notify', { type = 'info', duration = 6000,
        message = table.concat(lines, '\n') })
end, false)

-- Warm the crawl dict at start (bounded), so the first crawler has its pose.
CreateThread(function()
    local dict = C and C.dict
    if not dict or not DoesAnimDictExist(dict) then return end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
end)
