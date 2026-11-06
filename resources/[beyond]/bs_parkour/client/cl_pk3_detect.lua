-- Parkour v3 obstacle reading. A column of rays finds the face in front of the ped and how high it goes,
-- downward rays find the top surface and the landing, and a capsule checks the body has room to pass.
-- Detect.Front returns one plain table; the move runner only trusts what is in it.

Detect = {}

local FLAGS = 1 | 2 | 16   -- map, vehicles, objects

local function didHit(h) return h == 1 or h == true end

local function ray(a, b, ped)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, FLAGS, ped, 7)
    local _, hit, pos, normal, ent = GetShapeTestResult(handle)
    if didHit(hit) then return pos, normal, ent end
    return nil
end
Detect.Ray = ray

-- Capsule sweep for the body path. The test is async, so it waits a few frames.
-- true = blocked, false = clear, nil = no answer (callers treat that as clear and rely on the rays).
local function capsule(a, b, radius, ped)
    local handle = StartShapeTestCapsule(a.x, a.y, a.z, b.x, b.y, b.z, radius, FLAGS, ped, 7)
    for _ = 1, 8 do
        local status, hit = GetShapeTestResult(handle)
        if status == 2 then return didHit(hit) end
        if status == 0 then return nil end
        Wait(0)
    end
    return nil
end
Detect.Capsule = capsule

local function flat(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y)
    if l < 0.001 then return vector3(0.0, 1.0, 0.0) end
    return vector3(v.x / l, v.y / l, 0.0)
end
Detect.Flat = flat

local function dot2(a, b) return a.x * b.x + a.y * b.y end
Detect.Dot2 = dot2

-- Ground under the ped and the height of the ped origin above it (about 1 m standing).
-- Works while airborne too (coyote time, buffered jumps): heights are read from the ground, not the feet.
function Detect.Feet(ped)
    local p = GetEntityCoords(ped)
    local g = ray(p, p - vector3(0.0, 0.0, 2.6), ped)
    if g and p.z - g.z <= 1.15 then
        local off = p.z - g.z
        if off < 0.85 then off = 0.98 end
        return g.z, off
    end
    if g and p.z - g.z <= 2.6 then return g.z, 0.98 end
    return p.z - 0.98, 0.98
end

-- Ray heights above the ground (knee, waist, chest, head, above head, and two for high climbs)
local LEVELS = { 0.4, 0.9, 1.3, 1.7, 2.2, 2.8, 3.4 }

-- limits = { stepMin, stepMax, vault, vaultDepth, climb, climbHigh, bonnetMin, bonnetMax, bonnetDepth, maxDrop }
-- Returns nil or { kind = step|vault|bonnet|climb|climbHigh|native|wall, height, top, wall, normal, dist,
--                  feet, off, edge, land, stand, vehicle, ent }
function Detect.Front(ped, reach, limits)
    local pos = GetEntityCoords(ped)
    local feet, off = Detect.Feet(ped)
    local fwd = flat(GetEntityForwardVector(ped))

    -- 1) The face: nearest wall-like hit at knee, waist or chest. Nothing low = overhead, leave it (slide under).
    local face, faceN, faceD, faceEnt, faceLevel
    for i = 1, 3 do
        local a = vector3(pos.x, pos.y, feet + LEVELS[i])
        local p, n, e = ray(a, a + fwd * reach, ped)
        if p and math.abs(n.z) < 0.55 then
            local d = dot2(p - a, fwd)
            if not faceD or d < faceD - 0.05 then face, faceN, faceD, faceEnt, faceLevel = p, n, d, e, i end
        end
    end
    if not face then return nil end
    local n = flat(faceN)
    -- only obstacles we face, not walls we brush past
    if dot2(fwd, n) > -0.5 then return nil end

    local vehicle = false
    if faceEnt and faceEnt ~= 0 and DoesEntityExist(faceEnt) and GetEntityType(faceEnt) == 2 then vehicle = true end
    local info = {
        feet = feet, off = off, start = pos, normal = n, dist = faceD,
        wall = vector3(face.x, face.y, feet), vehicle = vehicle, ent = vehicle and faceEnt or nil,
    }
    local faceXY = vector3(face.x, face.y, 0.0)

    -- 2) How high the face goes: the first level above it that is clear just past the face
    local maxH = (limits.climbHigh or 3.2) + 0.3
    local clearAt, lastHit = nil, LEVELS[faceLevel]
    for i = faceLevel + 1, #LEVELS do
        local h = LEVELS[i]
        local a = vector3(pos.x, pos.y, feet + h)
        if not ray(a, a + fwd * (faceD + 0.45), ped) then clearAt = h break end
        lastHit = h
        if h > maxH then break end
    end
    if not clearAt then
        info.kind, info.height = 'wall', maxH
        return info
    end

    -- 3) Top surface: rays down just behind the face, at several depths (thin rails, rounded edges)
    local startZ = feet + clearAt + 0.05
    local top, anyZ
    for _, depth in ipairs({ 0.02, 0.06, 0.12, 0.2, 0.32, 0.48 }) do
        local at = faceXY - n * depth
        local p, nn = ray(vector3(at.x, at.y, startZ), vector3(at.x, at.y, feet + 0.15), ped)
        if p then
            if not anyZ or p.z > anyZ then anyZ = p.z end
            if nn.z > 0.7 and (not top or p.z > top) then top = p.z end
        end
    end
    local rounded = false
    if not top then
        rounded = true
        if anyZ then
            top = anyZ
        else
            -- very thin fence: no ray lands on it, so narrow the top down with forward rays
            local lo, hi = lastHit, clearAt
            for _ = 1, 4 do
                local mid = (lo + hi) * 0.5
                local a = vector3(pos.x, pos.y, feet + mid)
                if ray(a, a + fwd * (faceD + 0.3), ped) then lo = mid else hi = mid end
            end
            top = feet + (lo + hi) * 0.5
        end
    end
    info.top, info.height, info.rounded = top, top - feet, rounded
    local h = info.height
    if h < (limits.stepMin or 0.3) then return nil end

    -- 4) Depth: walk across the top until it drops away. nil = deep (roof, container, ledge to stand on)
    local edge
    for d = 0.25, (limits.bonnetDepth or 3.2), 0.25 do
        local at = faceXY - n * d
        if not ray(vector3(at.x, at.y, top + 0.6), vector3(at.x, at.y, top - 0.45), ped) then edge = d break end
        if not vehicle and d >= (limits.vaultDepth or 1.0) + 0.25 then break end
    end
    info.edge = edge

    -- 5) Landing past the obstacle (vaults): flat floor, not too far down, room to stand
    if edge then
        local at = faceXY - n * (edge + 0.55)
        local p, nn = ray(vector3(at.x, at.y, top + 0.5), vector3(at.x, at.y, feet - (limits.maxDrop or 2.5)), ped)
        if p and nn.z > 0.7 and not ray(p + vector3(0.0, 0.0, 0.1), p + vector3(0.0, 0.0, 1.8), ped) then
            info.land = vector3(p.x, p.y, p.z)
        end
    end

    -- 6) Standing spot on top (climbs, steps): flat, level with the top, headroom
    if not rounded and (not edge or edge >= 0.5) then
        local at = faceXY - n * 0.45
        local p, nn = ray(vector3(at.x, at.y, top + 0.5), vector3(at.x, at.y, top - 0.3), ped)
        if p and nn.z > 0.7 and math.abs(p.z - top) < 0.3
           and not ray(p + vector3(0.0, 0.0, 0.1), p + vector3(0.0, 0.0, 1.8), ped) then
            info.stand = vector3(p.x, p.y, p.z)
        end
    end

    -- 7) Roof over where we stand now
    local head = vector3(pos.x, pos.y, feet + 1.75)
    local function roofBelow(z)
        if z <= head.z then return false end
        return ray(head, vector3(pos.x, pos.y, z), ped) ~= nil
    end

    -- 8) Classify
    if h <= (limits.stepMax or 0.5) then
        if info.stand then info.kind = 'step' return info end
        return nil
    end
    if vehicle and edge and info.land and h >= (limits.bonnetMin or 0.6) and h <= (limits.bonnetMax or 1.25) then
        local blocked = capsule(vector3(pos.x, pos.y, top + 0.6), vector3(info.land.x, info.land.y, top + 0.6), 0.25, ped)
        if not blocked and not roofBelow(top + 1.1) then info.kind = 'bonnet' return info end
    end
    if edge and edge <= (limits.vaultDepth or 1.0) then
        if info.land and h <= (limits.vault or 1.35) and not roofBelow(top + 1.1) then
            local blocked = capsule(vector3(pos.x, pos.y, top + 0.65), vector3(info.land.x, info.land.y, top + 0.65), 0.25, ped)
            if not blocked then info.kind = 'vault' return info end
        end
        -- a tall fence: GTA's own climb goes over it
        if h <= (limits.climb or 2.4) then info.kind = 'native' return info end
        return nil
    end
    if info.stand and h <= (limits.climbHigh or 3.2) and not roofBelow(top + 1.9) then
        local blocked = capsule(vector3(pos.x, pos.y, top + 1.0), vector3(info.stand.x, info.stand.y, top + 1.0), 0.28, ped)
        if not blocked then
            info.kind = h <= (limits.climb or 2.4) and 'climb' or 'climbHigh'
            return info
        end
    end
    if h <= (limits.climb or 2.4) then info.kind = 'native' return info end
    info.kind = 'wall'
    return info
end
