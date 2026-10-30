-- bs_zombies - damage detection from the shooter

local D = Zombies.Damage or {}

-- Standard GTA V ped skeleton bone ids. Same on every ped, modded or not.

local BONE_HEAD = 31086          -- SKEL_Head

-- Bones a hit can be attributed to. Flat list: we walk all of them per shot and pick the nearest.
local BONES = {
    { 31086, 'head'  },  -- SKEL_Head
    { 39317, 'head'  },  -- SKEL_Neck_1 - see the strict-headshot note below
    { 24818, 'torso' },  -- SKEL_Spine3
    { 24817, 'torso' },  -- SKEL_Spine2
    { 24816, 'torso' },  -- SKEL_Spine1
    { 23553, 'torso' },  -- SKEL_Spine0
    { 11816, 'torso' },  -- SKEL_Pelvis
    { 45509, 'arm'   },  -- SKEL_L_UpperArm
    { 61163, 'arm'   },  -- SKEL_L_Forearm
    { 18905, 'arm'   },  -- SKEL_L_Hand
    { 40269, 'arm'   },  -- SKEL_R_UpperArm
    { 28252, 'arm'   },  -- SKEL_R_Forearm
    { 57005, 'arm'   },  -- SKEL_R_Hand
    { 58271, 'leg'   },  -- SKEL_L_Thigh
    { 63931, 'leg'   },  -- SKEL_L_Calf
    { 14201, 'leg'   },  -- SKEL_L_Foot
    { 51826, 'leg'   },  -- SKEL_R_Thigh
    { 36864, 'leg'   },  -- SKEL_R_Calf
    { 52301, 'leg'   },  -- SKEL_R_Foot
}

-- Resolve which region an impact landed in: nearest bone to the impact point (not GetPedLastDamageBone, which is unreliable)
local function regionForImpact(ped, hit)
    local bestRegion, bestBone, bestDist2 = 'torso', nil, math.huge

    for i = 1, #BONES do
        local boneId, region = BONES[i][1], BONES[i][2]
        local at = GetPedBoneCoords(ped, boneId, 0.0, 0.0, 0.0)
        if at then
            local dx, dy, dz = hit.x - at.x, hit.y - at.y, hit.z - at.z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 < bestDist2 then
                bestDist2, bestRegion, bestBone = d2, region, boneId
            end
        end
    end

    local headshot = false
    if bestBone == BONE_HEAD then
        if D.strictHeadshot == false then
            headshot = true
        else
            local r = D.headRadius or 0.14
            headshot = bestDist2 <= (r * r)
        end
        -- Nearest to the head but outside the radius counts as a torso hit
        if not headshot then bestRegion = 'torso' end
    elseif bestRegion == 'head' then
        -- Neck: resolves here so it does not fall through to the spine. Torso damage, not a headshot.
        bestRegion = 'torso'
    end

    return bestRegion, headshot
end

-- Bones the engine can report for a head hit
local ENGINE_HEAD = { [31086] = true, [12844] = true }
local HEAD_POINTS = { 31086 }
local BONE_REGION = {}
for i = 1, #BONES do BONE_REGION[BONES[i][1]] = BONES[i][2] end
BONE_REGION[39317] = 'torso'   -- neck is never a head

-- Shortest distance from the shot ray to any head bone, within headRadius.
local function rayNearHead(ped, from, to)
    local r = D.headRadius or 0.14
    local seg = to - from
    local len2 = seg.x * seg.x + seg.y * seg.y + seg.z * seg.z
    if len2 <= 0.0 then return false end
    for i = 1, #HEAD_POINTS do
        local p = GetPedBoneCoords(ped, HEAD_POINTS[i], 0.0, 0.0, 0.0)
        local t = ((p.x - from.x) * seg.x + (p.y - from.y) * seg.y + (p.z - from.z) * seg.z) / len2
        if t > 0.0 then
            local c = from + seg * t
            if #(p - c) <= r then return true end
        end
    end
    return false
end

-- Check whether the engine registered a player hit on a head bone for this ped
local function engineHit(ped, shooter)
    if not DoesEntityExist(ped) or not HasEntityBeenDamagedByEntity(ped, shooter, true) then return false end
    local ok, bone = GetPedLastDamageBone(ped)
    if not ok then return true, false, 'torso' end
    if ENGINE_HEAD[bone] then return true, true, 'head' end
    return true, false, BONE_REGION[bone] or 'torso'
end
local function engineHeadHit(ped, shooter)
    local hit, head = engineHit(ped, shooter)
    return hit == true and head == true
end

local function clearEngineHit(ped)
    if DoesEntityExist(ped) then
        ClearPedLastDamageBone(ped)
        ClearEntityLastDamageEntity(ped)
    end
end

-- IS THIS ONE OF OURS

-- Zed.owned is set right after CreatePed returns, before anything can yield, so a walker can be shot before its live entry exists
local function walkerIdFor(entity)
    if not entity or entity == 0 then return nil end
    if not Zed or not Zed.owned then return nil end
    local id = Zed.owned[entity]
    -- Networked peds must still carry the zombie marker (handles get reused; faction NPCs are never walkers)
    if NetworkGetEntityIsNetworked(entity) then
        local okS, st = pcall(function() return Entity(entity).state end)
        if not okS or not st or st.fnpc or st.bsFnpc or st.bsZombie == nil or st.bsZombieDead then return nil end
        -- Not adopted yet (another client owns it): fall back to the id in the state bag.
        if not id then id = tonumber(st.bsZombie) end
        if id and NetworkHasControlOfEntity(entity) then
            SetEntityInvincible(entity, false)
            SetEntityCanBeDamaged(entity, true)
        end
    end
    return id
end

-- THE TRACE

-- Synchronous probe: StartShapeTestRay is async and the walker moves before the result arrives
local function traceShot(from, to, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, -1, ignore, 4)

    local _, didHit, endCoords, _, entityHit = GetShapeTestResult(handle)
    if not didHit then return nil end
    return entityHit, endCoords
end

-- Trace from the rendered camera, not the muzzle or head
local function cameraRay()
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)

    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cosRx = math.abs(math.cos(rx))
    local dir = vector3(-math.sin(rz) * cosRx, math.cos(rz) * cosRx, math.sin(rx))

    local range = D.maxRange or 250.0
    return cam, cam + (dir * range)
end

-- REPORTING

local lastShotAt = 0
local shotsThisSecond, shotWindow = 0, 0

-- Local rate gate so automatic weapons do not flood the network
local function rateOk()
    local now = GetGameTimer()
    if now - shotWindow >= 1000 then
        shotWindow, shotsThisSecond = now, 0
    end
    shotsThisSecond = shotsThisSecond + 1
    return shotsThisSecond <= ((D.maxShotsPerSecond or 30) + 10)
end

-- True for melee weapons and bare hands (hit sounds are guns only).
local MELEE_GROUPS = { [GetHashKey('GROUP_MELEE')] = true, [GetHashKey('GROUP_UNARMED')] = true }
function Zombies.IsMeleeWeapon(hash)
    if not hash or hash == 0 then return false end
    return MELEE_GROUPS[GetWeapontypeGroup(hash)] == true
end

local function report(id, region, headshot, weaponHash, dist)
    if Zombies.IsMeleeWeapon and Zombies.IsMeleeWeapon(weaponHash) then
        Crumb('melee', 'hit id=%s region=%s', tostring(id), tostring(region))
    end
    TriggerServerEvent('bs:z:dmg', id, region, headshot and 1 or 0,
                       weaponHash, dist)

    -- Fire the hitmarker here instead of waiting for the server, so it does not feel laggy
    if Zombies.HitMarker and not Zombies.IsMeleeWeapon(weaponHash) then
        Zombies.HitMarker(headshot)
    end
end

-- Crippled walker (legs gone)

RegisterNetEvent('bs:z:crippled', function(id)
    id = tonumber(id)
    Crumb('zcrawl', 'crippled id=%s', tostring(id))
    if not id or not Zed or not Zed.live then return end

    local entry = Zed.live[id]
    if not entry or entry.dying then return end

    local crawler = Zombies.Types and Zombies.Types.crawler
    if not crawler then return end

    -- The def is swapped, not merged. entry.hp stays as it was.
    entry.def = crawler
    entry.crippled = true

    -- Deferred a moment: ragdolling a ped mid melee impact can crash the engine.
    local ped = entry.ped
    CreateThread(function()
        local waited = 0
        while waited < 1500 and IsPedPerformingMeleeAction(PlayerPedId()) do
            Wait(50); waited = waited + 50
        end
        Wait(100)
        if entry.dying or entry.ped ~= ped then return end
        if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
        if IsPedRagdoll(ped) or not CanPedRagdoll(ped) then return end
        if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
        pcall(SetPedToRagdoll, ped, 1200, 1200, 0, false, false, false)
    end)
end)

-- GUNFIRE

-- Two sources: IsPedShooting (any weapon the engine considers fired) and bs:weapons:shot
local function onShotFired(impact)
    local now = GetGameTimer()
    if now - lastShotAt < 30 then return end   -- same trigger pull, both paths
    lastShotAt = now

    if not rateOk() then return end

    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end

    local from, to
    local impactPoint
    if type(impact) == 'table' and tonumber(impact.x) and tonumber(impact.y) and tonumber(impact.z) then
        from = GetFinalRenderedCamCoord()
        impactPoint = vector3(tonumber(impact.x), tonumber(impact.y), tonumber(impact.z))
        local travel = impactPoint - from
        local length = #travel
        to = length > 0.01 and (impactPoint + (travel / length) * 0.35) or impactPoint
    else
        from, to = cameraRay()
    end
    local entity, hit = traceShot(from, to, ped)
    if entity and impactPoint then hit = impactPoint end
    local id = entity and walkerIdFor(entity)
    if not id then
        -- Our ray missed but the real bullet (spread/recoil) may still have hit the head. Ask the engine.
        local myPos = GetEntityCoords(ped)
        CreateThread(function()
            local deadline = GetGameTimer() + 150
            repeat
                for wid, entry in pairs((Zed and Zed.live) or {}) do
                    local zp = entry.ped
                    if zp and not entry.dying and #(GetEntityCoords(zp) - myPos) < (D.maxRange or 250.0) then
                        local hitIt, isHead, reg = engineHit(zp, ped)
                        if hitIt then
                            clearEngineHit(zp)
                            local _, w = GetCurrentPedWeapon(ped, true)
                            report(wid, isHead and 'head' or reg, isHead == true, w or 0, #(GetEntityCoords(zp) - myPos))
                            return
                        end
                    end
                end
                Wait(0)
            until GetGameTimer() > deadline
        end)
        return
    end

    local region, headshot = regionForImpact(entity, hit)

    -- The probe stops on the ped capsule, outside the skull, so face shots often landed beyond headRadius
    if not headshot and rayNearHead(entity, from, to) then
        region, headshot = 'head', true
    end

    local _, weaponHash = GetCurrentPedWeapon(ped, true)
    local at = GetEntityCoords(ped)
    local dist = #(at - vector3(hit.x, hit.y, hit.z))

    if headshot then
        clearEngineHit(entity)
        report(id, region, headshot, weaponHash or 0, dist)
        return
    end

    -- The engine gets the last word: the real bullet may have hit the head even if our ray did not
    CreateThread(function()
        local deadline = GetGameTimer() + 150
        repeat
            if engineHeadHit(entity, ped) then region, headshot = 'head', true; break end
            Wait(0)
        until GetGameTimer() > deadline
        clearEngineHit(entity)
        report(id, region, headshot, weaponHash or 0, dist)
    end)
end

AddEventHandler('bs:weapons:shot', onShotFired)

CreateThread(function()
    local wasShooting = false
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local shooting = IsPedShooting(ped)

        -- Rising edge only
        if shooting and not wasShooting then onShotFired() end
        wasShooting = shooting

        if not shooting then Wait(50) end
    end
end)

-- MELEE

-- Melee sweeps an arc in front of the player instead of tracing a ray
local function onMeleeSwing()
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)

    local range = D.meleeRange or 2.4
    local halfAngle = math.rad(D.meleeHalfAngle or 60.0)

    local bestId, bestPed, bestDist = nil, nil, math.huge

    for _, entry in pairs(Zed.live or {}) do
        if entry.ped and DoesEntityExist(entry.ped) and not entry.dying then
            local to = GetEntityCoords(entry.ped)
            local d = #(to - at)
            if d <= range and d < bestDist then
                local dir = (to - at)
                local len = #dir
                if len > 0.01 then
                    dir = dir / len
                    local dot = (dir.x * fwd.x) + (dir.y * fwd.y)
                    if dot > math.cos(halfAngle) then
                        bestId, bestPed, bestDist = entry.id, entry.ped, d
                    end
                end
            end
        end
    end

    if not bestId then return end

    -- Melee region comes from where the swing lands: chest height on a standing walker is a torso hit
    local aim = GetEntityCoords(bestPed) + vector3(0.0, 0.0, 0.45)
    local region, headshot = regionForImpact(bestPed, aim)

    local _, weaponHash = GetCurrentPedWeapon(ped, true)
    report(bestId, region, headshot, weaponHash or 0, bestDist)
end

CreateThread(function()
    local wasSwinging = false
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local swinging = IsPedPerformingMeleeAction(ped)

        if swinging and not wasSwinging then onMeleeSwing() end
        wasSwinging = swinging

        if not swinging then Wait(80) end
    end
end)

-- /ztest damage - checks every rule in this file against a real walker and prints pass or fail.

RegisterCommand('ztestdamage', function()
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)

    local nearest, nd = nil, math.huge
    for _, entry in pairs(Zed.live or {}) do
        if entry.ped and DoesEntityExist(entry.ped) then
            local d = #(GetEntityCoords(entry.ped) - at)
            if d < nd then nearest, nd = entry, d end
        end
    end

    if not nearest then
        print('^3[BS DAMAGE]^7 no walker near you - stand next to one and run this again.')
        return
    end

    print(('^5[BS DAMAGE]^7 testing against walker %d at %.1fm'):format(nearest.id, nd))

    local checks = {
        { 'head',  BONE_HEAD, true  },
        { 'torso', 24818,     false },
        { 'arm',   45509,     false },
        { 'leg',   58271,     false },
    }

    local pass, fail = 0, 0
    for _, c in ipairs(checks) do
        local want, boneId, wantHead = c[1], c[2], c[3]
        local bonePos = GetPedBoneCoords(nearest.ped, boneId, 0.0, 0.0, 0.0)
        local got, headshot = regionForImpact(nearest.ped, bonePos)

        local ok = (got == want) and (headshot == wantHead)
        if ok then pass = pass + 1 else fail = fail + 1 end

        print(('   %s bone %d -> region %s, headshot %s  %s')
            :format(want, boneId, got, tostring(headshot),
                    ok and '^2PASS^7' or '^1FAIL^7'))
    end

    -- A point a metre to the side of the head must not count as a headshot.
    local head = GetPedBoneCoords(nearest.ped, BONE_HEAD, 0.0, 0.0, 0.0)
    local _, wideHead = regionForImpact(nearest.ped, head + vector3(1.0, 0.0, 0.0))
    if not wideHead then
        pass = pass + 1
        print('   a metre off the skull -> not a headshot  ^2PASS^7')
    else
        fail = fail + 1
        print('   a metre off the skull -> HEADSHOT  ^1FAIL^7 - headRadius is too large')
    end

    print(('^5[BS DAMAGE]^7 %d passed, %d failed. bodyFloor=%d strictHeadshot=%s headRadius=%.2f')
        :format(pass, fail, D.bodyFloor or 10, tostring(D.strictHeadshot ~= false),
                D.headRadius or 0.22))
end, false)


-- Floating damage numbers (on by default;. KVP 2 = player turned them off).
local KVP_NUMS = 'bs_dmgnums'
local numsOn = GetResourceKvpInt(KVP_NUMS) ~= 2
local nums = {}

exports('DamageNumbersShown', function() return numsOn end)
exports('SetDamageNumbersShown', function(on)
    numsOn = on and true or false
    SetResourceKvpInt(KVP_NUMS, numsOn and 1 or 2)
    if not numsOn then nums = {} end
end)

RegisterNetEvent('bs:z:dmgnum', function(id, amount, kind)
    if not numsOn then return end
    local entry = Zed and Zed.live and Zed.live[tonumber(id)]
    if not entry or not entry.ped or not DoesEntityExist(entry.ped) then return end
    local p = GetEntityCoords(entry.ped)
    local dz = kind == 'head' and 0.85 or 0.4
    nums[#nums + 1] = { x = p.x + (math.random() - 0.5) * 0.4, y = p.y + (math.random() - 0.5) * 0.4, z = p.z + dz,
        t = GetGameTimer(), amount = math.floor((tonumber(amount) or 0) + 0.5), kind = kind }
    if #nums > 30 then table.remove(nums, 1) end
end)

CreateThread(function()
    while true do
        if numsOn and #nums > 0 then
            local now = GetGameTimer()
            for i = #nums, 1, -1 do
                local n = nums[i]
                local age = now - n.t
                if age > 900 then
                    table.remove(nums, i)
                else
                    local on, sx, sy = GetScreenCoordFromWorldCoord(n.x, n.y, n.z + age * 0.0008)
                    if on then
                        local r, g, b = 255, 215, 60
                        if n.kind == 'head' then r, g, b = 255, 140, 20
                        elseif n.kind == 'floored' then r, g, b = 170, 170, 170 end
                        SetTextFont(4)
                        SetTextScale(0.0, n.kind == 'head' and 0.5 or 0.38)
                        SetTextColour(r, g, b, math.floor(255 * (1 - age / 900)))
                        SetTextOutline()
                        SetTextCentre(true)
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName(tostring(n.amount))
                        EndTextCommandDisplayText(sx, sy)
                    end
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Staff /zkill: the server asks for a camera ray (~60 m); the walker id it hits goes back for the staff check and the kill
RegisterNetEvent('bs:z:zkillcast', function()
    local from = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local to = from + dir * 60.0
    local me = PlayerPedId()
    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 13, me, 0)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    local id
    if hit == 1 and ent and ent ~= 0 and IsEntityAPed(ent) and not IsPedAPlayer(ent) then
        id = Zed and Zed.owned and Zed.owned[ent]
        local okS, st = pcall(function() return Entity(ent).state end)
        if okS and st then
            if st.fnpc then id = nil
            elseif not id and tonumber(st.bsZombie) then id = tonumber(st.bsZombie) end
        elseif not id then id = nil end
    end
    TriggerServerEvent('bs:z:zkillhit', id or 0)
end)
