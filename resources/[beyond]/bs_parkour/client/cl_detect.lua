-- Obstacle probes: a few rays in front of the ped measure how far, how high and how deep an obstacle is.

Detect = {}

local FLAGS = 1 | 2 | 16   -- map, vehicles, objects

local function ray(a, b, ped)
    local h = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, FLAGS, ped, 7)
    local _, hit, pos, normal = GetShapeTestResult(h)
    if hit == 1 then return pos, normal end
    return nil
end
Detect.Ray = ray

local function flat(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y)
    if l < 0.001 then return vector3(0.0, 1.0, 0.0) end
    return vector3(v.x / l, v.y / l, 0.0)
end
Detect.Flat = flat

function Detect.Feet(ped)
    local p = GetEntityCoords(ped)
    return vector3(p.x, p.y, p.z - 0.98)
end

-- Something in front within reach. Returns nil or a table: kind, height, top, wall, normal, thin, room.
-- `limits` = { vault, climb, climbHigh, hang } in metres.
function Detect.Front(ped, reach, limits)
    local feet = Detect.Feet(ped)
    local fwd = flat(GetEntityForwardVector(ped))
    local best, bestN, bestD
    for _, h in ipairs({ 0.35, 0.9, 1.5 }) do
        local a = feet + vector3(0.0, 0.0, h)
        local p, n = ray(a, a + fwd * reach, ped)
        if p then
            local d = #(vector3(p.x, p.y, 0.0) - vector3(a.x, a.y, 0.0))
            if not bestD or d < bestD then best, bestN, bestD = p, n, d end
        end
    end
    if not best then return nil end

    local n = flat(bestN)
    -- Only obstacles we face, not walls we brush past
    if (fwd.x * -n.x + fwd.y * -n.y) < 0.55 then return nil end
    -- A steep slope is not a wall
    if math.abs(bestN.z) > 0.55 then return nil end

    -- Thin fences are a few cm deep, so probe just behind the face as well as further in; keep the highest top
    local ceiling = (limits.hang or 4.2) + 0.6
    local into, top
    for _, depth in ipairs({ 0.06, 0.15, 0.3 }) do
        local at = vector3(best.x, best.y, feet.z) - n * depth
        local hit = ray(at + vector3(0.0, 0.0, ceiling), at + vector3(0.0, 0.0, 0.2), ped)
        if hit and (not top or hit.z > top.z) then top, into = hit, at end
    end
    into = into or (vector3(best.x, best.y, feet.z) - n * 0.3)
    local info = { wall = vector3(best.x, best.y, feet.z), normal = n, dist = bestD, feet = feet }

    if not top then
        info.kind, info.height = 'wall', ceiling
        return info
    end

    info.top = top.z
    info.height = top.z - feet.z
    if info.height < 0.45 then return nil end

    -- Depth: is there floor a metre past the edge?
    local far = vector3(best.x, best.y, 0.0) - n * 1.1
    local floor = ray(vector3(far.x, far.y, top.z + 0.5), vector3(far.x, far.y, top.z - 0.6), ped)
    info.thin = floor == nil
    -- Room to stand on top
    local standAt = vector3(into.x, into.y, top.z) - n * 0.35
    info.room = ray(standAt + vector3(0.0, 0.0, 0.1), standAt + vector3(0.0, 0.0, 1.85), ped) == nil
    info.stand = standAt

    if info.height <= limits.vault and info.thin then info.kind = 'vault'
    elseif info.height <= limits.climb then info.kind = 'climb'
    elseif info.height <= limits.climbHigh and info.room then info.kind = 'climbHigh'
    elseif info.height <= limits.hang then info.kind = 'ledge'
    else info.kind = 'wall' end
    return info
end

-- Wall beside the ped (for wall runs). Returns side (-1 left, 1 right), normal, point.
function Detect.Side(ped, reach)
    local p = GetEntityCoords(ped)
    local fwd = flat(GetEntityForwardVector(ped))
    local right = vector3(fwd.y, -fwd.x, 0.0)
    for _, side in ipairs({ 1, -1 }) do
        local hit, n = ray(p, p + right * side * reach, ped)
        if hit and math.abs(n.z) < 0.4 then
            -- tall enough to run on
            local high = ray(p + vector3(0.0, 0.0, 1.2), p + vector3(0.0, 0.0, 1.2) + right * side * (reach + 0.3), ped)
            if high then return side, flat(n), hit end
        end
    end
    return nil
end

-- Ledge at a spot along the wall, used while hanging. Returns the top z or nil.
function Detect.LedgeAt(ped, at, normal, topZ)
    local face = ray(vector3(at.x, at.y, topZ - 0.2) + normal * 0.6, vector3(at.x, at.y, topZ - 0.2) - normal * 0.5, ped)
    if not face then return nil end
    local probe = vector3(face.x, face.y, 0.0) - normal * 0.2
    local top = ray(vector3(probe.x, probe.y, topZ + 0.6), vector3(probe.x, probe.y, topZ - 0.45), ped)
    if not top then return nil end
    return top.z, face
end
