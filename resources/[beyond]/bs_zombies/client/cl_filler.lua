-- bs_zombies - hybrid population, client half: local filler walkers
-- Filler peds are not networked and never fight. When one notices the player it is promoted: the
-- server creates a real walker on the same spot, this ped fades out, and any hit it took is replayed
-- as bs:z:dmg on the new walker. Config: config_filler.lua, regions and hot zones: config_zones.lua.

local function F() return Zombies.Filler or {} end
local S = Zombies.Settings
local D = Zombies.Damage or {}

Zed = Zed or {}

local filler = {}        -- [ped] = record
local count = 0
local nextToken = 0
local pending = {}       -- [token] = record
local queue = {}         -- records waiting to be sent
local promoTimes = {}    -- acked promotions, GetGameTimer()
local sentTimes = {}
local stats = { spawned = 0, removed = 0, promoted = 0, refused = 0, noSpot = 0, refusedBy = {} }
local area = { want = 0, effective = 0, kind = 'wilds', id = nil, hot = nil, at = 0 }
local GROUP = GetHashKey('BS_FILLER')

local function now() return GetGameTimer() end

-- Where walkers just died: no filler is promoted (or kept) on top of a body
local deathMarks = {}   -- { x, y, at }
local function nearDeath(x, y)
    local cfg = Zombies.Filler or {}
    local r = tonumber(cfg.deathExclusionRadius) or 4.0
    local ms = tonumber(cfg.deathExclusionMs) or 20000
    local t = now()
    for i = #deathMarks, 1, -1 do
        local m = deathMarks[i]
        if t - m.at > ms then table.remove(deathMarks, i)
        elseif (m.x - x) ^ 2 + (m.y - y) ^ 2 <= r * r then return true end
    end
    return false
end

-- The filler's clothes and props, so its networked twin looks exactly the same
local LOOK_PROPS = { 0, 1, 2, 6, 7 }
local function lookOf(ped)
    local c, p = {}, {}
    for comp = 0, 11 do c[#c + 1] = { GetPedDrawableVariation(ped, comp), GetPedTextureVariation(ped, comp) } end
    for _, prop in ipairs(LOOK_PROPS) do p[#p + 1] = { prop, GetPedPropIndex(ped, prop), GetPedPropTextureIndex(ped, prop) } end
    return { c = c, p = p }
end

function Zed.FillerCount() return count end
function Zed.IsFiller(ped) return ped ~= nil and filler[ped] ~= nil end

CreateThread(function()
    AddRelationshipGroup('BS_FILLER')
    local player = GetHashKey('PLAYER')
    SetRelationshipBetweenGroups(1, GROUP, player)
    SetRelationshipBetweenGroups(1, player, GROUP)
    SetRelationshipBetweenGroups(1, GROUP, GetHashKey('BS_ZOMBIE'))
    SetRelationshipBetweenGroups(1, GetHashKey('BS_ZOMBIE'), GROUP)
end)

-- Who may have filler

local sessionOk, sessionAt = false, 0
local function inWorld()
    local t = now()
    if t - sessionAt > 1000 then
        sessionAt = t
        sessionOk = true
        if GetResourceState('bs_core') == 'started' then
            local ok, st = pcall(function() return exports.bs_core:GetSessionState() end)
            sessionOk = ok and st == 'playing'
        end
    end
    return sessionOk
end

-- The server sets zFiller per player: hybrid on, routing bucket 0, in the world
local function enabled()
    if not (ZFiller and ZFiller.Enabled()) then return false end
    if LocalPlayer.state.zFiller ~= true then return false end
    return inWorld()
end

-- Removal

local function removeFiller(f)
    if filler[f.ped] ~= f then return end
    filler[f.ped] = nil
    count = math.max(0, count - 1)
    stats.removed = stats.removed + 1
    if f.token then pending[f.token] = nil end
    local ped = f.ped
    if DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function fadeOut(f, ms)
    local ped = f.ped
    f.leaving = true
    CreateThread(function()
        if DoesEntityExist(ped) then
            FreezeEntityPosition(ped, true)
            SetEntityCollision(ped, false, false)
            local steps = math.max(1, math.floor((ms or 300) / 50))
            for i = steps - 1, 0, -1 do
                if not DoesEntityExist(ped) then break end
                SetEntityAlpha(ped, math.floor(255 * i / steps), false)
                Wait(50)
            end
        end
        removeFiller(f)
    end)
end

local function clearAll()
    local all = {}
    for _, f in pairs(filler) do all[#all + 1] = f end
    for _, f in ipairs(all) do removeFiller(f) end
    queue = {}
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)

-- Placement: streets only, never a roof, never an interior, never in sight

local function roadNear(x, y, z, within)
    local ok, pos = GetClosestVehicleNode(x, y, z, 1, 3.0, 0)
    if ok and pos and pos.x and ((pos.x - x) ^ 2 + (pos.y - y) ^ 2) <= within * within then return pos end
    return nil
end

-- Same roof rules as the networked spawner (cl_spawner.lua): well above the road, or above a lower floor
local function aboveRoad(c, road)
    local d = math.sqrt((c.x - road.x) ^ 2 + (c.y - road.y) ^ 2)
    return c.z > road.z + 4.0 + d * 0.15
end

local function aboveLowerSurface(c)
    local found, lower = GetGroundZFor_3dCoord(c.x, c.y, c.z - 3.0, false)
    return found and lower and c.z - lower > 3.0
end

local function inSafeZone(x, y)
    local pad = S.safeZonePadding or 55.0
    for _, zone in ipairs(Zones.Safe or {}) do
        if Zones.Contains(zone, x, y, pad) then return true end
    end
    return false
end

local function nearAnyPlayer(x, y, minD)
    local m2 = minD * minD
    for _, pid in ipairs(GetActivePlayers()) do
        local p = GetEntityCoords(GetPlayerPed(pid))
        if (p.x - x) ^ 2 + (p.y - y) ^ 2 < m2 then return true end
    end
    return false
end

local function seen(c)
    local onScreen = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.0)
    if not onScreen then return false end
    local cam = GetFinalRenderedCamCoord()
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, c.x, c.y, c.z + 1.0, 17, PlayerPedId(), 4)
    local _, hit = GetShapeTestResult(h)
    return not (hit == true or hit == 1)
end

local function standable(x, y, z, road)
    for _, flags in ipairs({ 16, 0 }) do
        local found, c = GetSafeCoordForPed(x, y, z, true, flags)
        if found and c and ((c.x - x) ^ 2 + (c.y - y) ^ 2) <= 20.0 * 20.0 then
            if math.abs(c.z - road.z) <= 6.0 and not aboveRoad(c, road) and not aboveLowerSurface(c)
               and GetInteriorAtCoords(c.x, c.y, c.z) == 0 then
                return c
            end
        end
    end
    return nil
end

local function findSpot(at)
    local cfg = F()
    local minD = math.max(tonumber(cfg.spawnMin) or 55.0, S.spawnDistanceMin or 50.0)
    local maxD = math.max(minD + 10.0, tonumber(cfg.spawnMax) or 165.0)
    local ang = math.random() * math.pi * 2.0
    local d = minD + math.random() * (maxD - minD)
    local x, y = at.x + math.cos(ang) * d, at.y + math.sin(ang) * d
    local road = roadNear(x, y, at.z, tonumber(cfg.roadSnap) or 35.0)
    if not road then return nil end
    -- off the centre line, toward the pavement
    local c = standable(road.x + (math.random() - 0.5) * 14.0, road.y + (math.random() - 0.5) * 14.0, road.z, road)
    if not c then return nil end
    if inSafeZone(c.x, c.y) or nearAnyPlayer(c.x, c.y, minD) or seen(c) then return nil end
    return c, road
end

-- Building one

local function loadModel(name)
    local hash = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then return nil end
    RequestModel(hash)
    local deadline = now() + 3000
    while not HasModelLoaded(hash) do
        if now() > deadline then return nil end
        Wait(20)
    end
    return hash
end

local function gaitFor(ped)
    local a = Zombies.Anims or {}
    local list = a.shambleSet or { a.shamble }
    if not IsPedMale(ped) and type(a.femaleShambleSet) == 'table' and #a.femaleShambleSet > 0 then
        list = a.femaleShambleSet
    end
    local set = list[math.random(1, math.max(1, #list))] or 'move_m@drunk@verydrunk'
    return (type(set) == 'string' and set:find('drunk', 1, true)) and set or 'move_m@drunk@verydrunk'
end

local function idle(f)
    local ped = f.ped
    if not DoesEntityExist(ped) then return end
    if math.random() < 0.65 then
        TaskWanderInArea(ped, f.home.x, f.home.y, f.home.z, 12.0 + math.random() * 10.0, 3.0, 6.0 + math.random() * 8.0)
    else
        SetEntityHeading(ped, math.random() * 360.0)
        TaskStandStill(ped, math.random(8000, 20000))
    end
    f.nextThink = now() + math.random(9000, 20000)
end

local function spawnOne(c, model)
    local hash = loadModel(model)
    if not hash then return nil end
    local ped = CreatePed(4, hash, c.x, c.y, c.z, math.random() * 360.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GROUP)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, false)
    SetPedAlertness(ped, 0)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedCanEvasiveDive(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedSuffersCriticalHits(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedConfigFlag(ped, 281, true)
    -- a big local pool so nothing kills it before the server walker takes over
    SetEntityMaxHealth(ped, 5000)
    SetEntityHealth(ped, 5000)
    RemoveAllPedWeapons(ped, true)
    SetPedDropsWeaponsWhenDead(ped, false)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    SetAmbientVoiceName(ped, 'ALIENS')
    SetPedPathCanUseClimbovers(ped, false)
    SetPedPathCanUseLadders(ped, false)
    SetPedPathCanDropFromHeight(ped, false)
    pcall(SetPedRandomComponentVariation, ped, 0)

    local set = gaitFor(ped)
    RequestAnimSet(set)
    local deadline = now() + 1000
    while not HasAnimSetLoaded(set) and now() < deadline do Wait(20) end
    if HasAnimSetLoaded(set) then SetPedMovementClipset(ped, set, 0.0) end

    local f = { ped = ped, model = model, home = c, born = now(), hits = {}, hp = GetEntityHealth(ped), nextThink = 0 }
    filler[ped] = f
    count = count + 1
    stats.spawned = stats.spawned + 1
    idle(f)
    return f
end

local function spawnGroup(c)
    local cfg = F()
    local g = cfg.groupSize or { 1, 4 }
    local n = math.random(math.max(1, g[1] or 1), math.max(1, g[2] or g[1] or 1))
    local made = 0
    for i = 1, n do
        local at = c
        if i > 1 then
            local found, o = GetSafeCoordForPed(c.x + (math.random() - 0.5) * 6.0, c.y + (math.random() - 0.5) * 6.0, c.z, true, 16)
            at = (found and o and math.abs(o.z - c.z) <= 1.5 and GetInteriorAtCoords(o.x, o.y, o.z) == 0) and o or nil
        end
        if at then
            local model = Zombies.PickModel(at.x, at.y, 'walker')
            if model and spawnOne(at, model) then made = made + 1 end
        end
    end
    return made
end

-- Leaving: farthest and out of sight first
local function shed(n, at, force)
    local list = {}
    for _, f in pairs(filler) do
        if not f.promoting and not f.leaving and DoesEntityExist(f.ped) then
            local p = GetEntityCoords(f.ped)
            list[#list + 1] = { f = f, d = #(p - at), vis = IsEntityOnScreen(f.ped) }
        end
    end
    table.sort(list, function(a, b)
        if a.vis ~= b.vis then return not a.vis end
        return a.d > b.d
    end)
    local done = 0
    for _, e in ipairs(list) do
        if done >= n then break end
        if not e.vis then removeFiller(e.f); done = done + 1
        elseif force then fadeOut(e.f, 600); done = done + 1 end
    end
end

local function poolCount()
    local ok, list = pcall(GetGamePool, 'CPed')
    return (ok and type(list) == 'table') and #list or 0
end

-- Spawn / cleanup pass
CreateThread(function()
    while true do
        Wait(math.max(150, math.floor(tonumber(F().passMs) or 450)))
        if not enabled() then
            if count > 0 then clearAll() end
            area.want, area.effective = 0, 0
            Wait(1000)
        else
            local cfg = F()
            local me = PlayerPedId()
            local at = GetEntityCoords(me)
            local t = now()
            if t - area.at > 3000 then
                area.at = t
                area.want, area.kind, area.id, area.hot = ZFiller.TargetAt(at.x, at.y, GetClockHours())
            end

            local cleanup = tonumber(cfg.cleanupDistance) or 180.0
            local gone = {}
            for ped, f in pairs(filler) do
                if not f.promoting and not f.leaving then
                    if not DoesEntityExist(ped) or IsEntityDead(ped) or #(GetEntityCoords(ped) - at) > cleanup then
                        gone[#gone + 1] = f
                    end
                end
            end
            for _, f in ipairs(gone) do removeFiller(f) end

            -- Filler gets whatever the pool has left after everything else
            local peds = poolCount()
            local others = peds - count
            local ceiling = math.floor(tonumber(cfg.poolCeiling) or 165)
            local want = math.min(area.want, math.floor(tonumber(cfg.hardCap) or 70), math.max(0, ceiling - others))
            if inSafeZone(at.x, at.y) then want = 0 end
            area.effective = want

            if count > want then
                shed(math.min(4, count - want), at, peds > ceiling + 15)
            elseif count < want and not IsEntityDead(me) then
                local budget = math.max(1, math.floor(tonumber(cfg.spawnPerPass) or 2))
                local made, tries = 0, 0
                while made < budget and tries < 6 and count < want do
                    tries = tries + 1
                    local c = findSpot(at)
                    if c then made = made + spawnGroup(c) else stats.noSpot = stats.noSpot + 1 end
                end
            end
        end
    end
end)

-- Promotion

local function promote(f, reason, hit, target)
    if filler[f.ped] ~= f or f.leaving then return end
    -- One promotion per filler ped, ever; never a dying one, never on top of a fresh body
    if f.sentOnce and not f.promoting then fadeOut(f, F().refusedFadeMs or 1500) return end
    local ped = f.ped
    if not DoesEntityExist(ped) or IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then removeFiller(f) return end
    if not f.promoting then
        local p = GetEntityCoords(ped)
        if nearDeath(p.x, p.y) then fadeOut(f, 600) return end
    end
    local t = now()
    if hit and #f.hits < 3 then f.hits[#f.hits + 1] = hit; f.lastHitAt = t end
    if f.promoting then return end
    if not hit and f.refusedUntil and t < f.refusedUntil then return end
    f.promoting, f.reason, f.target = true, reason, target
    local me = PlayerPedId()
    if reason ~= 'noise' and DoesEntityExist(f.ped) then TaskTurnPedToFaceEntity(f.ped, me, 1500) end
    if hit then table.insert(queue, 1, f) else queue[#queue + 1] = f end
end

local function refused(f, why)
    -- A timed-out request may still be answered: keep the token so a late ack still swaps, and never resend
    if why == 'timeout' then
        f.promoting = false
        stats.refused = stats.refused + 1
        stats.refusedBy.timeout = (stats.refusedBy.timeout or 0) + 1
        fadeOut(f, F().refusedFadeMs or 1500)
        return
    end
    f.promoting, f.token, f.sentAt = false, nil, nil
    f.refusedUntil = now() + 8000
    stats.refused = stats.refused + 1
    stats.refusedBy[tostring(why)] = (stats.refusedBy[tostring(why)] or 0) + 1
    if not DoesEntityExist(f.ped) then removeFiller(f) return end
    -- A walker that cannot become real must not stand next to the player as a harmless dummy
    local d = #(GetEntityCoords(f.ped) - GetEntityCoords(PlayerPedId()))
    if #f.hits > 0 or d < 15.0 then
        f.hits = {}
        fadeOut(f, F().refusedFadeMs or 1500)
    else
        idle(f)
    end
end

local function prune(list, window)
    local t = now() - window
    local keep = {}
    for _, v in ipairs(list) do if v >= t then keep[#keep + 1] = v end end
    return keep
end

-- Sender: spaced requests, client-side rate limit
CreateThread(function()
    while true do
        Wait(math.max(50, math.floor(tonumber(F().gapMs) or 120)))
        local f = table.remove(queue, 1)
        if f and filler[f.ped] == f and f.promoting and not f.token and not f.sentOnce then
            sentTimes = prune(sentTimes, 60000)
            local limit = math.floor(tonumber(F().maxPerMinute) or 40)
            if #sentTimes >= limit and #f.hits == 0 then
                refused(f, 'clientRate')
            elseif DoesEntityExist(f.ped) then
                nextToken = nextToken + 1
                f.token, f.sentAt, f.sentOnce = nextToken, now(), true
                pending[nextToken] = f
                sentTimes[#sentTimes + 1] = now()
                local p = GetEntityCoords(f.ped)
                TriggerServerEvent('bs:z:filler:promote', nextToken, p.x, p.y, p.z, GetEntityHeading(f.ped),
                    f.model, f.reason, tonumber(f.target) or 0, lookOf(f.ped))
            else
                removeFiller(f)
            end
        end
    end
end)

local function swap(f, id, net)
    local deadline = now() + (tonumber(F().swapTimeoutMs) or 3000)
    local twin
    repeat
        if net > 0 and NetworkDoesEntityExistWithNetworkId(net) then twin = NetToPed(net) end
        if (not twin or twin == 0) and Zed.live and Zed.live[id] then twin = Zed.live[id].ped end
        if twin and twin ~= 0 and DoesEntityExist(twin) then break end
        twin = nil
        Wait(50)
    until now() > deadline

    local ped = f.ped
    if DoesEntityExist(ped) then
        if twin then SetEntityNoCollisionEntity(ped, twin, false) end
        fadeOut(f, F().fadeMs or 300)
    else
        removeFiller(f)
    end

    -- Hits taken as filler land on the real walker once it is known here, so the body and loot exist
    if #f.hits > 0 then
        local wait = now() + 1500
        while not (Zed.live and Zed.live[id]) and now() < wait do Wait(50) end
        for _, h in ipairs(f.hits) do
            TriggerServerEvent('bs:z:dmg', id, h.region or 'torso', h.headshot and 1 or 0, h.weapon or 0, h.dist or 0.0)
            Wait(60)
        end
        f.hits = {}
    end
end

RegisterNetEvent('bs:z:filler:ack', function(token, id, net)
    local f = pending[token]
    pending[token] = nil
    if not f or filler[f.ped] ~= f then return end
    if not id and f.sentOnce and f.leaving then return end
    if not id then refused(f, net) return end
    f.acked = true
    promoTimes[#promoTimes + 1] = now()
    stats.promoted = stats.promoted + 1
    CreateThread(function() swap(f, tonumber(id), tonumber(net) or 0) end)
end)

AddEventHandler('bs:z:dead', function(_, info)
    if type(info) ~= 'table' or not tonumber(info.x) or not tonumber(info.y) then return end
    local x, y = tonumber(info.x), tonumber(info.y)
    deathMarks[#deathMarks + 1] = { x = x, y = y, at = now() }
    local r = tonumber((Zombies.Filler or {}).deathExclusionRadius) or 4.0
    for ped, f in pairs(filler) do
        if not f.promoting and not f.leaving and DoesEntityExist(ped) then
            local p = GetEntityCoords(ped)
            if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= r * r then fadeOut(f, 600) end
        end
    end
end)

-- Senses: a slice of the filler every tick, never per frame per ped

local stance, stanceAt = { crouched = false, prone = false }, 0
local function readStance()
    local t = now()
    if t - stanceAt < 500 then return stance end
    stanceAt = t
    local function flag(name)
        if GetResourceState('bs_emotes') ~= 'started' then return nil end
        local ok, v = pcall(function() return exports.bs_emotes[name](exports.bs_emotes) end)
        return ok and v == true
    end
    local me = PlayerPedId()
    stance.prone = flag('IsProne') == true
    stance.crouched = flag('IsCrouched') == true or IsPedDucking(me) or GetPedStealthMovement(me) == true
    return stance
end

local function facing(ped, from, to, half)
    local fwd = GetEntityForwardVector(ped)
    local dx, dy = to.x - from.x, to.y - from.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return true end
    return (dx / len) * fwd.x + (dy / len) * fwd.y >= math.cos(math.rad(half))
end

local slot = 0
CreateThread(function()
    while true do
        Wait(250)
        if count > 0 and enabled() then
            local cfg = F()
            local me = PlayerPedId()
            local at = GetEntityCoords(me)
            local alive = not IsEntityDead(me)
            local t = now()
            local st = readStance()
            local sg = cfg.sight or {}
            local sight = st.prone and (sg.prone or 5.0) or (st.crouched and (sg.crouched or 9.0)) or (sg.standing or 24.0)
            local contact = tonumber(cfg.contactRadius) or 6.0
            if st.prone or st.crouched then contact = math.min(contact, 3.0) end
            local veh = GetVehiclePedIsIn(me, false)
            local fast = veh ~= 0 and GetEntitySpeed(veh) > 8.0
            local sprint = IsPedSprinting(me)
            local ackTimeout = tonumber(cfg.ackTimeoutMs) or 4000

            -- Snapshot, so promotions and removals during the pass cannot upset the walk
            local list = {}
            for _, f in pairs(filler) do list[#list + 1] = f end
            local total = #list
            for i = 1, math.min(20, total) do
                slot = slot % total + 1
                local f = list[slot]
                local ped = f.ped
                if filler[ped] ~= f then
                    -- already gone
                elseif f.promoting then
                    if f.sentAt and not f.acked and t - f.sentAt > ackTimeout then refused(f, 'timeout') end
                elseif not f.leaving and DoesEntityExist(ped) then
                    local p = GetEntityCoords(ped)
                    local d = #(p - at)
                    if GetEntityHealth(ped) < f.hp - 1 then
                        -- hurt by something the shot trace did not see (spread, explosion, a car)
                        SetEntityHealth(ped, f.hp)
                        local recent = f.lastHitAt and t - f.lastHitAt < 400
                        local hit
                        if not recent and veh == 0 then
                            local _, w = GetCurrentPedWeapon(me, true)
                            hit = { region = 'torso', headshot = false, weapon = w or 0, dist = d }
                        end
                        promote(f, 'hit', hit)
                    elseif alive then
                        if d <= contact and not fast then
                            promote(f, 'contact')
                        elseif sprint and d <= (tonumber(cfg.sprintHear) or 14.0) then
                            promote(f, 'heard')
                        elseif d <= sight and facing(ped, p, at, sg.halfAngle or 70.0)
                               and HasEntityClearLosToEntity(ped, me, 17) then
                            promote(f, 'sight')
                        elseif t >= f.nextThink then
                            idle(f)
                        end
                    end
                end
            end
        end
    end
end)

-- Shots, swings and aim aimed at filler promote it at once and keep the hit for replay

local lastShotAt = 0
local function onShot()
    if count == 0 then return end
    local t = now()
    if t - lastShotAt < 30 then return end
    lastShotAt = t
    local me = PlayerPedId()
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    local dir = vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx))
    local to = cam + dir * (D.maxRange or 250.0)
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, -1, me, 4)
    local _, didHit, hit, _, ent = GetShapeTestResult(h)
    if not didHit or not ent or ent == 0 then return end
    local f = filler[ent]
    if not f then return end
    local region, headshot = 'torso', false
    if Zombies.RegionForImpact then region, headshot = Zombies.RegionForImpact(ent, hit) end
    local _, w = GetCurrentPedWeapon(me, true)
    if Zombies.HitMarker and not (Zombies.IsMeleeWeapon and Zombies.IsMeleeWeapon(w)) then Zombies.HitMarker(headshot) end
    promote(f, 'hit', { region = region, headshot = headshot, weapon = w or 0, dist = #(GetEntityCoords(me) - hit) })
end
AddEventHandler('bs:weapons:shot', function() onShot() end)

local function onSwing()
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    local fwd = GetEntityForwardVector(me)
    local range = D.meleeRange or 2.4
    local cosHalf = math.cos(math.rad(D.meleeHalfAngle or 60.0))
    local best, bestD
    for ped, f in pairs(filler) do
        if DoesEntityExist(ped) and not f.leaving then
            local v = GetEntityCoords(ped) - at
            local d = #v
            if d <= range and d > 0.01 and (v.x / d) * fwd.x + (v.y / d) * fwd.y > cosHalf and (not bestD or d < bestD) then
                best, bestD = f, d
            end
        end
    end
    if not best then return end
    local aim = GetEntityCoords(best.ped) + vector3(0.0, 0.0, 0.45)
    local region, headshot = 'torso', false
    if Zombies.RegionForImpact then region, headshot = Zombies.RegionForImpact(best.ped, aim) end
    local _, w = GetCurrentPedWeapon(me, true)
    promote(best, 'hit', { region = region, headshot = headshot, weapon = w or 0, dist = bestD })
end

CreateThread(function()
    local wasShooting, wasSwinging, aimAt = false, false, 0
    while true do
        if count == 0 then
            wasShooting, wasSwinging = false, false
            Wait(500)
        else
            Wait(0)
            local me = PlayerPedId()
            local shooting = IsPedShooting(me)
            if shooting and not wasShooting then onShot() end
            wasShooting = shooting
            local swinging = IsPedPerformingMeleeAction(me)
            if swinging and not wasSwinging then onSwing() end
            wasSwinging = swinging
            local t = now()
            if t - aimAt > 100 then
                aimAt = t
                local ok, ent = GetEntityPlayerIsFreeAimingAt(PlayerId())
                local f = ok and ent and filler[ent]
                if f and #(GetEntityCoords(ent) - GetEntityCoords(me)) <= (tonumber(F().aimPromote) or 120.0) then
                    promote(f, 'aim')
                end
            end
        end
    end
end)

-- Noise: inside the radius it is promoted (a few per noise), a bit further out it shuffles toward the sound
AddEventHandler('bs:world:noise', function(payload)
    if count == 0 or type(payload) ~= 'table' or type(payload.coords) ~= 'table' then return end
    if not enabled() then return end
    local cfg = F()
    local o = vector3(tonumber(payload.coords.x) or 0.0, tonumber(payload.coords.y) or 0.0, tonumber(payload.coords.z) or 0.0)
    local r = (tonumber(payload.radius) or 20.0) * (tonumber(cfg.noiseScale) or 1.0)
    local outer = r * (tonumber(cfg.turnScale) or 1.8)
    local list = {}
    for ped, f in pairs(filler) do
        if not f.promoting and not f.leaving and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - o)
            if d <= outer then list[#list + 1] = { f = f, d = d } end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local most, made = math.floor(tonumber(cfg.perNoise) or 6), 0
    for _, e in ipairs(list) do
        if e.d <= r and made < most then
            promote(e.f, 'noise', nil, tonumber(payload.source))
            made = made + 1
        else
            local ped = e.f.ped
            TaskFollowNavMeshToCoord(ped, o.x + (math.random() - 0.5) * 8.0, o.y + (math.random() - 0.5) * 8.0, o.z,
                1.0, 25000, 4.0, 0, 0.0)
            e.f.nextThink = now() + 25000
        end
    end
end)

-- Debug (/zfiller is a staff command on the server; it sends its half here)

RegisterNetEvent('bs:z:filler:diag', function(sv)
    sv = type(sv) == 'table' and sv or {}
    promoTimes = prune(promoTimes, 60000)
    local net = 0
    for _ in pairs(Zed.live or {}) do net = net + 1 end
    local hour = GetClockHours()
    local refusedBy = {}
    for k, v in pairs(stats.refusedBy) do refusedBy[#refusedBy + 1] = k .. '=' .. v end
    local lines = {
        ('^5[BS FILLER]^7 hybrid %s | here: %s | filler %d | networked %d | promotions/min %d (server %s)')
            :format(tostring(ZFiller.Enabled()), tostring(enabled()), count, net, #promoTimes, tostring(sv.perMinute or '?')),
        ('   region %s (%s)%s | target %d -> %d after pool limits | peds in pool %d | hour %d night x%.2f')
            :format(area.kind, tostring(area.id or '-'), area.hot and (' hot ' .. area.hot) or '', area.want, area.effective,
                    poolCount(), hour, ZFiller.NightFactor(hour)),
        ('   players %s | net cap %s (%s) | player scale x%.2f | networked within 120m of you %s')
            :format(tostring(sv.players or '?'), tostring(sv.cap or '?'), tostring(sv.capWhy or '?'),
                    tonumber(sv.scale) or 1.0, tostring(sv.near or '?')),
        ('   spawned %d removed %d promoted %d refused %d (%s) | no spot %d | queued %d')
            :format(stats.spawned, stats.removed, stats.promoted, stats.refused, table.concat(refusedBy, ' '),
                    stats.noSpot, #queue),
    }
    if sv.refused then lines[#lines + 1] = '   server refusals: ' .. tostring(sv.refused) end
    for _, line in ipairs(lines) do
        print(line)
        TriggerEvent('chat:addMessage', { args = { line } })
    end
end)
