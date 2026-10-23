-- BeyondSurvival - bs_zombies: zombies vault over low fences and small walls only (no vehicles, no tall walls)

local V = function() return Zombies.Vault or {} end
local track = {}   -- [id] = { x, y, z, at, cool }

local function num(v, d) v = tonumber(v); return v or d end

local function ray(x1, y1, z1, x2, y2, z2, ignore)
    -- 1 = world, 16 = objects. Vehicles (2) and peds (4/8) are not tested.
    local h = StartExpensiveSynchronousShapeTestLosProbe(x1, y1, z1, x2, y2, z2, 1 | 16, ignore, 7)
    local _, hit, at, _, ent = GetShapeTestResult(h)
    return hit == 1 or hit == true, at, ent
end

local function lowObstacleAhead(ped)
    local cfg = V()
    local pos = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local reach = num(cfg.reach, 1.1)
    local groundZ = pos.z - 0.95                         -- ped origin is at the pelvis
    local kneeZ = groundZ + num(cfg.kneeHeight, 0.45)
    local topZ = groundZ + num(cfg.maxHeight, 1.25)

    local hitKnee, at, ent = ray(pos.x, pos.y, kneeZ, pos.x + fwd.x * reach, pos.y + fwd.y * reach, kneeZ, ped)
    if not hitKnee then return false end
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        local t = GetEntityType(ent)
        if t == 1 or t == 2 then return false end      -- ped or vehicle: never
    end
    local hitTop = ray(pos.x, pos.y, topZ, pos.x + fwd.x * (reach + 0.4), pos.y + fwd.y * (reach + 0.4), topZ, ped)
    if hitTop then return false end                     -- taller than a small fence

    -- Landing check: clear at chest height over the top, and ground within 0.5m of where we stand, about 1.6m past the fence
    local lx, ly = pos.x + fwd.x * (reach + 1.6), pos.y + fwd.y * (reach + 1.6)
    if ray(pos.x, pos.y, topZ, lx, ly, topZ, ped) then return false end
    local found, gz = GetGroundZFor_3dCoord(lx, ly, topZ + 0.5, false)
    if not found or math.abs(gz - groundZ) > num(cfg.maxDrop, 0.6) then return false end
    return true
end

CreateThread(function()
    while true do
        Wait(num(V().checkMs, 700))
        if V().enabled ~= false then
            local now = GetGameTimer()
            for id, entry in pairs(Zed.live or {}) do
                local ped = entry.ped
                local busy = entry.state == 'hunting' or entry.state == 'drawn'
                if busy and entry.hosted and not entry.crippled and not entry.dying
                   and ped and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped)
                   and not IsPedDeadOrDying(ped, true) and not IsPedRagdoll(ped)
                   and not IsPedClimbing(ped) and not IsPedVaulting(ped) then
                    local p = GetEntityCoords(ped)
                    local t = track[id]
                    if not t then
                        track[id] = { x = p.x, y = p.y, z = p.z, at = now, cool = 0 }
                    else
                        local dx, dy = p.x - t.x, p.y - t.y
                        if dx * dx + dy * dy > num(V().stuckMove, 0.4) ^ 2 then
                            t.x, t.y, t.z, t.at = p.x, p.y, p.z, now
                        elseif now - t.at >= num(V().stuckMs, 1500) and now >= t.cool then
                            t.cool = now + num(V().cooldownMs, 4000)
                            if lowObstacleAhead(ped) then
                                TaskClimb(ped, false)
                                entry.nextThink = now + 2200   -- let it finish before re-tasking
                                t.at = now
                            end
                        end
                    end
                else
                    track[id] = nil
                end
            end
            for id in pairs(track) do if not (Zed.live and Zed.live[id]) then track[id] = nil end end
        end
    end
end)
