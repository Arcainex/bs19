-- /pkmeasure <dict> <clip> (admin, sent by the server): plays a clip where you stand, with no script movement,
-- and prints how far it moves you (right / forward / up) and how long it lasts, as a line ready to paste
-- into Parkour.ClipOffsets. The result is also used right away for this session.
-- /pkmeasure dump prints every line measured this session.

local measured = {}

local function fmt(v) return ('%.3f'):format(v) end

local function line(key, e)
    local pts = {}
    for _, c in ipairs(e.curve or {}) do pts[#pts + 1] = ('{%s,%s}'):format(fmt(c[1]), fmt(c[2])) end
    return ("Parkour.ClipOffsets['%s'] = { fwd = %s, up = %s, right = %s, dur = %s, upEnd = %s, curve = { %s } },")
        :format(key, fmt(e.fwd), fmt(e.up), fmt(e.right), fmt(e.dur), fmt(e.upEnd), table.concat(pts, ', '))
end

-- Where the clip's root sits at a phase, in the clip's own frame (x = right, y = forward, z = up)
local function rootAt(dict, clip, phase)
    local ok, v = pcall(GetAnimInitialOffsetPosition, dict, clip, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, phase, 2)
    if ok and v then return v end
    return nil
end

local function measure(dict, clip)
    if PK.busy then return print('^3[pkmeasure] finish the current move first^7') end
    if not PK.LoadDict(dict) then return print(('^1[pkmeasure] dict %s does not load^7'):format(dict)) end
    local dur = GetAnimDuration(dict, clip)
    if dur <= 0.0 then return print(('^1[pkmeasure] clip %s/%s not found^7'):format(dict, clip)) end
    local key = dict .. '/' .. clip

    -- 1) offsets stored in the clip itself, sampled every 10%
    local curve, base = {}, rootAt(dict, clip, 0.0)
    if base then
        for i = 0, 10 do
            local v = rootAt(dict, clip, i / 10.0)
            if not v then curve = {} break end
            curve[#curve + 1] = { v.y - base.y, v.z - base.z, v.x - base.x }
        end
    end

    -- 2) the clip played in place, no script movement
    local ped = PlayerPedId()
    local s = GetEntityCoords(ped)
    local fwd = Detect.Flat(GetEntityForwardVector(ped))
    local right = vector3(fwd.y, -fwd.x, 0.0)
    ClearPedTasks(ped)
    PK.testing = true
    SetTimeout(math.floor(dur * 1000) + 2500, function() PK.testing = nil end)
    PK.debugUntil = GetGameTimer() + math.floor(dur * 1000) + 2500
    TaskPlayAnim(ped, dict, clip, 8.0, -4.0, -1, 2, 0.0, false, false, false)
    local by = GetGameTimer() + 500
    while not IsEntityPlayingAnim(ped, dict, clip, 3) and GetGameTimer() < by do Wait(0) end
    if not IsEntityPlayingAnim(ped, dict, clip, 3) then
        return print(('^1[pkmeasure] %s did not start playing on your ped^7'):format(key))
    end
    local t0 = GetGameTimer()
    local maxUp, live = 0.0, {}
    while GetGameTimer() - t0 < dur * 1000 + 400 do
        local p = GetEntityCoords(ped) - s
        maxUp = math.max(maxUp, p.z)
        live[#live + 1] = { Detect.Dot2(p, fwd), p.z, GetEntityAnimCurrentTime(ped, dict, clip) }
        if not IsEntityPlayingAnim(ped, dict, clip, 3) or GetEntityAnimCurrentTime(ped, dict, clip) >= 0.99 then break end
        Wait(0)
    end
    local d = GetEntityCoords(ped) - s
    local liveEnd = { fwd = Detect.Dot2(d, fwd), right = Detect.Dot2(d, right), up = d.z }
    StopAnimTask(ped, dict, clip, 4.0)

    -- prefer the clip data; fall back to the live run if the clip carries no root motion
    local e
    local last = curve[#curve]
    if last and (math.abs(last[1]) > 0.05 or math.abs(last[2]) > 0.05) then
        e = { fwd = last[1], up = last[2], right = last[3], dur = dur, curve = {} }
        for _, c in ipairs(curve) do e.curve[#e.curve + 1] = { c[1], c[2] } end
    else
        e = { fwd = liveEnd.fwd, up = liveEnd.up, right = liveEnd.right, dur = dur, curve = {} }
        if #live >= 3 and (math.abs(liveEnd.fwd) > 0.05 or math.abs(liveEnd.up) > 0.05) then
            -- resample the live run to 11 points by clip phase
            for i = 0, 10 do
                local ph, pick = i / 10.0, live[#live]
                for _, r in ipairs(live) do if r[3] >= ph then pick = r break end end
                e.curve[#e.curve + 1] = { pick[1], pick[2] }
            end
        end
    end
    -- phase where 90% of the rise is done (shapes the default climb path)
    e.upEnd = 0.6
    for i, c in ipairs(e.curve) do
        if e.up > 0.1 and c[2] >= e.up * 0.9 then e.upEnd = (i - 1) / 10.0 break end
    end

    Parkour.ClipOffsets = Parkour.ClipOffsets or {}
    Parkour.ClipOffsets[key] = e
    measured[key] = e
    print(('^3[pkmeasure] %s  %.2fs^7'):format(key, dur))
    print(('  clip data : fwd %.2f  up %.2f  right %.2f'):format(last and last[1] or 0.0, last and last[2] or 0.0, last and last[3] or 0.0))
    print(('  played    : fwd %.2f  up %.2f  right %.2f  (peak up %.2f)'):format(liveEnd.fwd, liveEnd.up, liveEnd.right, maxUp))
    print('  paste into config/config_parkour.lua:')
    print('  ' .. line(key, e))
    TriggerEvent('bs:ui:notify', { type = 'info', message = ('Measured %s, see F8.'):format(clip), duration = 3000 })
end

RegisterNetEvent('bs:parkour:measure', function(dict, clip)
    if dict == 'dump' then
        print('^3[pkmeasure] measured this session:^7')
        for k, e in pairs(measured) do print('  ' .. line(k, e)) end
        return
    end
    if type(dict) ~= 'string' or type(clip) ~= 'string' then
        return print('usage: /pkmeasure <dict> <clip>   or   /pkmeasure dump')
    end
    CreateThread(function() measure(dict, clip) end)
end)

-- /pkcliptest <dict> <clip> (admin): plays the clip with each flag set where you stand and reports, per set,
-- whether it plays, whether the body really moves (hand bones compared frame to frame) and whether it shows
-- the T-pose. A full-body set that passes is used for the rest of the session and printed as a config line.
local SETS = {
    { id = 0,     label = 'full body' },
    { id = 2,     label = 'full body, hold last frame' },
    { id = 1,     label = 'full body loop' },
    { id = 16,    label = 'upper body' },
    { id = 48,    label = 'upper body + secondary' },
    { id = 'adv', label = 'TaskPlayAnimAdvanced, hold' },
}
local FULL = { [0] = true, [1] = true, [2] = true, adv = true }

local function testOne(ped, dict, clip, set, dur)
    local home, hdg = GetEntityCoords(ped), GetEntityHeading(ped)
    ClearPedTasksImmediately(ped)
    Wait(250)
    if set.id == 'adv' then
        TaskPlayAnimAdvanced(ped, dict, clip, home.x, home.y, home.z, 0.0, 0.0, hdg, 8.0, -4.0, -1, 2, 0.0, 0, 0)
    else
        TaskPlayAnim(ped, dict, clip, 8.0, -4.0, -1, set.id, 0.0, false, false, false)
    end
    local t0 = GetGameTimer()
    local span = math.min(2500, math.max(800, math.floor(dur * 1000)))
    local frames, playing, tpose, moved = 0, 0, 0, 0.0
    local firstL, firstR, lastL
    while GetGameTimer() - t0 < span do
        Wait(0)
        frames = frames + 1
        if IsEntityPlayingAnim(ped, dict, clip, 3) then playing = playing + 1 end
        if GetGameTimer() - t0 > 180 then
            if PK3.IsTPose(ped) then tpose = tpose + 1 end
            local l, r = PK3.Hands(ped)
            if not firstL then firstL, firstR = l, r end
            moved = math.max(moved, #(l - firstL), #(r - firstR))
            lastL = l
        end
    end
    StopAnimTask(ped, dict, clip, 8.0)
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, home.x, home.y, home.z, false, false, false)
    SetEntityHeading(ped, hdg)
    local verdict
    if playing < frames * 0.5 then verdict = 'NOT PLAYING'
    elseif tpose > 2 then verdict = 'T-POSE'
    elseif moved < 0.05 then verdict = 'STATIC'
    else verdict = 'OK' end
    return verdict, playing, frames, tpose, moved
end

RegisterNetEvent('bs:parkour:cliptest', function(dict, clip)
    if type(dict) ~= 'string' or type(clip) ~= 'string' then return print('usage: /pkcliptest <dict> <clip>') end
    CreateThread(function()
        if PK.busy then return print('^3[pkcliptest] finish the current move first^7') end
        if not PK.LoadDict(dict) then return print(('^1[pkcliptest] dict %s does not load^7'):format(dict)) end
        local dur = GetAnimDuration(dict, clip)
        if dur <= 0.0 then return print(('^1[pkcliptest] clip %s/%s not found^7'):format(dict, clip)) end
        local ped = PlayerPedId()
        local key = dict .. '/' .. clip
        PK.testing = true
        print(('^3[pkcliptest] %s (%.2fs). Stand still in open ground.^7'):format(key, dur))
        local best
        for _, set in ipairs(SETS) do
            local ok, verdict, playing, frames, tpose, moved = pcall(testOne, ped, dict, clip, set, dur)
            if not ok then verdict, playing, frames, tpose, moved = 'ERROR ' .. tostring(verdict), 0, 1, 0, 0.0 end
            print(('  %-6s %-28s %-12s playing %d/%d  tpose %d  hand moved %.2f m'):format(
                tostring(set.id), set.label, verdict, playing, frames, tpose, moved))
            if verdict == 'OK' and FULL[set.id] and best == nil then best = set.id end
        end
        PK.testing = nil
        if best ~= nil then
            PK3.verified[key] = best
            PK3.bad[key] = nil
            local v = type(best) == 'string' and ("'" .. best .. "'") or tostring(best)
            print(('^2  safe standalone. Add to Parkour.Pk3.Standalone:  [\'%s\'] = %s,^7'):format(key, v))
        else
            PK3.verified[key] = false
            print(('^1  not safe standalone: keep it out of Parkour.Pk3.Standalone (or set [\'%s\'] = false)^7'):format(key))
        end
        TriggerEvent('bs:ui:notify', { type = 'info', message = ('Clip test %s done, see F8.'):format(clip), duration = 3000 })
    end)
end)
