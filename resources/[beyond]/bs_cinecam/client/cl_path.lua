-- bs_cinecam - keyframes and playback.
-- Playing back keyframes gives the same move every time, including straight or
-- circular dollies that are hard to do by hand.

CinePath = {
    nodes   = {},
    playing = false,
    startAt = 0,
    token   = 0,      -- invalidates an in-flight playback when a new one starts
}

local function S() return CineState.s end

-- Keyframes

function CinePath.Add()
    if #CinePath.nodes >= Cine.Path.maxNodes then return false, 'path is full' end
    if not CineCam.active then return false, 'not in camera mode' end

    CinePath.nodes[#CinePath.nodes + 1] = {
        x = CineCam.x, y = CineCam.y, z = CineCam.z,
        pitch = CineCam.pitch, yaw = CineCam.yaw, roll = CineCam.roll,
        fov = CineCam.fov,
    }

    return true, #CinePath.nodes
end

function CinePath.Pop()
    if #CinePath.nodes == 0 then return false end
    CinePath.nodes[#CinePath.nodes] = nil
    return true, #CinePath.nodes
end

function CinePath.Clear()
    CinePath.nodes = {}
    return true
end

-- Interpolation

-- Catmull-Rom for position only. It passes through every keyframe with a
-- continuous tangent, so there is no corner at each point. It needs a point
-- before the first and after the last; both are made by mirroring the neighbour.
local function catmull(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t

    return 0.5 * ((2.0 * p1)
        + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
end

local function nodeAt(index)
    local n = CinePath.nodes
    local count = #n
    if count == 0 then return nil end
    if index < 1 then index = 1 end
    if index > count then index = count end
    return n[index]
end

-- Easing: a sine ease over the first and last `ease` fraction of the run, constant
-- speed in the middle, so the dolly does not start and stop with a jerk.
local function easeProgress(t, ease)
    if ease <= 0.0 then return t end
    ease = math.min(0.5, ease)

    if t < ease then
        local k = t / ease
        return ease * (1.0 - math.cos(k * math.pi * 0.5))
    elseif t > 1.0 - ease then
        local k = (1.0 - t) / ease
        return 1.0 - ease * (1.0 - math.cos(k * math.pi * 0.5))
    end

    return t
end

-- Position, angles and FOV at progress t in 0..1 across the whole path.
function CinePath.Sample(t)
    local nodes = CinePath.nodes
    local count = #nodes
    if count == 0 then return nil end
    if count == 1 then return nodes[1] end

    t = math.max(0.0, math.min(1.0, t))

    -- Which segment, and how far along it.
    local scaled = t * (count - 1)
    local i = math.floor(scaled) + 1
    if i > count - 1 then i = count - 1 end
    local local_t = scaled - (i - 1)

    local p1 = nodes[i]
    local p2 = nodes[i + 1]

    -- Mirrored virtual endpoints, as described above.
    local p0 = nodeAt(i - 1)
    local p3 = nodeAt(i + 2)
    if i == 1 then
        p0 = { x = p1.x * 2 - p2.x, y = p1.y * 2 - p2.y, z = p1.z * 2 - p2.z }
    end
    if i + 2 > count then
        p3 = { x = p2.x * 2 - p1.x, y = p2.y * 2 - p1.y, z = p2.z * 2 - p1.z }
    end

    -- Angles are lerped, not splined: a Catmull-Rom overshoots each keyframe, which
    -- looks like the camera changing its mind on a heading. Shortest-arc lerp (plus
    -- the smoothing in cl_camera) gives a clean pan and avoids a 359 degree spin
    -- through north.
    local lerpAngle = CineCam.LerpAngle
    local lerp = CineCam.Lerp

    return {
        x = catmull(p0.x, p1.x, p2.x, p3.x, local_t),
        y = catmull(p0.y, p1.y, p2.y, p3.y, local_t),
        z = catmull(p0.z, p1.z, p2.z, p3.z, local_t),

        pitch = lerpAngle(p1.pitch, p2.pitch, local_t),
        yaw   = lerpAngle(p1.yaw,   p2.yaw,   local_t),
        roll  = lerp(p1.roll, p2.roll, local_t),
        fov   = lerp(p1.fov,  p2.fov,  local_t),
    }
end

-- Playback

function CinePath.Stop()
    if not CinePath.playing then return false end
    CinePath.playing = false
    CinePath.token = CinePath.token + 1
    CineCam.scripted = false

    -- Hand the manual controls back at the position the path ended on, not where
    -- playback started.
    CineCam.tPitch = CineCam.pitch
    CineCam.tYaw   = CineCam.yaw
    CineCam.tRoll  = CineCam.roll
    CineCam.tFov   = CineCam.fov
    CineCam.vx, CineCam.vy, CineCam.vz = 0.0, 0.0, 0.0

    return true
end

function CinePath.Play()
    if #CinePath.nodes < 2 then return false, 'need at least two keyframes' end
    if not CineCam.active then return false, 'not in camera mode' end

    CinePath.Stop()

    CinePath.token = CinePath.token + 1
    local token = CinePath.token
    CinePath.playing = true
    CineCam.scripted = true

    CreateThread(function()
        local duration = math.max(0.5, Cine.Path.duration)
        local started = GetGameTimer()

        while CinePath.playing and CinePath.token == token and CineCam.active do
            Wait(0)

            -- Wall-clock time, not accumulated frame times (those drift per machine).
            -- GetGameTimer() is scaled by SetTimeScale, so slow motion plays the same move
            -- over more real seconds.
            local elapsed = (GetGameTimer() - started) / 1000.0
            local raw = elapsed / duration

            if raw >= 1.0 then
                if Cine.Path.loop then
                    started = GetGameTimer()
                    raw = 0.0
                else
                    raw = 1.0
                end
            end

            local sample = CinePath.Sample(easeProgress(raw, Cine.Path.ease))
            if sample then
                CineCam.x, CineCam.y, CineCam.z = sample.x, sample.y, sample.z
                CineCam.pitch = sample.pitch
                CineCam.yaw   = sample.yaw
                CineCam.roll  = sample.roll
                CineCam.fov   = sample.fov
                CineCam.Push()
            end

            if raw >= 1.0 and not Cine.Path.loop then
                CinePath.Stop()
                break
            end
        end
    end)

    return true
end

function CinePath.Toggle()
    if CinePath.playing then
        CinePath.Stop()
        return false
    end
    return CinePath.Play()
end

-- What the menu shows. A count is not enough: 'no keyframes' and 'one keyframe'
-- are different reasons play does nothing.
function CinePath.Summary()
    return {
        count    = #CinePath.nodes,
        playing  = CinePath.playing,
        duration = Cine.Path.duration,
        loop     = Cine.Path.loop,
        ease     = Cine.Path.ease,
    }
end

-- Keys, while flying

-- G and Y are read from the camera loop's enabled controls (CineLock.CameraControls)
-- rather than key mappings, because commands are what lockout blocks. They only
-- work while the camera is active.
CreateThread(function()
    while true do
        if CineCam.active then
            Wait(0)
            if IsDisabledControlJustPressed(0, 47) then       -- G
                CinePath.Add()
            elseif IsDisabledControlJustPressed(0, 246) then  -- Y
                CinePath.Toggle()
            end
        else
            Wait(200)
        end
    end
end)
