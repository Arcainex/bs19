local busy, rod = false, nil
local function notify(kind, message) JC.Notify(kind,message) end
local function cleanup()
    ClearPedTasks(PlayerPedId())
    if rod and DoesEntityExist(rod) then DeleteEntity(rod) end
    rod, busy = nil, false
    SendNUIMessage({ action = 'fishingClose' })
end
local function facingWater()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped,false) or IsPedSwimming(ped) or IsEntityDead(ped) then return nil end
    local at = GetPedBoneCoords(ped,31086,0.0,0.0,0.0)
    local ahead = GetOffsetFromEntityInWorldCoords(ped,0.0,25.0,-12.0)
    local hit, point = TestProbeAgainstWater(at.x,at.y,at.z,ahead.x,ahead.y,ahead.z)
    if hit then return {x=point.x,y=point.y,z=point.z} end
end
local function startRod()
    local model = GetHashKey('prop_fishing_rod_01')
    RequestModel(model)
    local deadline = GetGameTimer()+2000
    while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    rod = CreateObject(model,at.x,at.y,at.z,false,false,false)
    AttachEntityToEntity(rod,ped,GetPedBoneIndex(ped,60309),0.0,0.0,0.0,0.0,0.0,0.0,true,true,false,true,1,true)
    SetModelAsNoLongerNeeded(model)
    local dict = 'amb@world_human_stand_fishing@idle_a'
    RequestAnimDict(dict)
    deadline = GetGameTimer()+2000
    while not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(0) end
    if HasAnimDictLoaded(dict) then TaskPlayAnim(ped,dict,'idle_c',3.0,3.0,-1,49,0.0,false,false,false) end
end
local function fish()
    if busy then return end
    local water = facingWater()
    if not water then return notify('warn','Face nearby water while standing on dry ground.') end
    busy = true
    exports.bs_inventory:Close()
    Wait(150)
    local result = BSB.Await('jobs:fish:start',8000,water)
    if not result or not result.ok then busy=false; return notify('warn',result and result.error or 'Could not start fishing.') end
    startRod()
    local origin, started = GetEntityCoords(PlayerPedId()), GetGameTimer()
    local score, cursor, direction, target = 0,0.0,1,0.35+math.random()*.3
    local width = .22+result.skill*.005
    local last = GetGameTimer()
    local lastTap = 0
    local success = false
    SendNUIMessage({action='fishingOpen'})
    while busy do
        Wait(0)
        local now = GetGameTimer()
        local dt = math.min(.05,(now-last)/1000)
        last = now
        cursor = cursor+direction*dt*(.68-result.skill*.008)
        if cursor >= 1 then cursor=1;direction=-1 elseif cursor <= 0 then cursor=0;direction=1 end
        DisableControlAction(0,24,true); DisableControlAction(0,25,true); DisableControlAction(0,38,true)
        DisableControlAction(0,37,true); DisableControlAction(0,44,true)
        if IsDisabledControlJustPressed(0,38) and now-lastTap > 450 and score<3 then
            lastTap = now
            if math.abs(cursor-target)<=width/2 then score=score+1 else score=math.max(0,score-1) end
            target=.2+math.random()*.6
        end
        if now-lastTap<70 or now%100<17 then
            SendNUIMessage({action='fishingTick',cursor=cursor,target=target,width=width,score=score,ready=score>=3})
        end
        if IsControlJustPressed(0,177) or IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false)
            or #(GetEntityCoords(PlayerPedId())-origin)>2.5 or now-started>35000 then break end
        if score>=3 and now-started>=result.ms then success=true;break end
    end
    cleanup()
    local finish = BSB.Await(success and 'jobs:fish:finish' or 'jobs:fish:cancel',8000)
    if success and finish and finish.ok then notify('success','Caught '..(finish.label or finish.item)..'.')
    elseif success then notify('warn',finish and finish.error or 'The catch could not be confirmed.')
    else notify('info','Cast cancelled. The bait was used.') end
end
RegisterNetEvent('bs:jobs:fish:use',function() CreateThread(fish) end)
RegisterCommand('fish',function() CreateThread(fish) end,false)

-- Foraging. Whitelisted bushes keep their own cooldown; any other plant or foliage the player
-- stands in falls back to "undergrowth", which the server cools down per grid cell.
local F = Jobs.Foraging
local ZONE_ID = 'bs_jobs:forage'
local whitelist, hashes, nameCache = {}, {}, {}
for _, name in ipairs(F.models) do
    local h = GetHashKey(name)
    whitelist[h] = name
    hashes[#hashes + 1] = h
end
for _, name in ipairs(F.extraModels or {}) do
    local h = GetHashKey(name)
    if not whitelist[h] then hashes[#hashes + 1] = h; nameCache[h] = name end
end
local foliageMaterial = {}
for _, m in ipairs(F.materials or {}) do foliageMaterial[m] = true end

local function archetype(entity, model)
    if whitelist[model] then return whitelist[model] end
    if nameCache[model] ~= nil then return nameCache[model] or nil end
    local name
    local native = rawget(_G, 'GetEntityArchetypeName')
    if native then
        local ok, n = pcall(native, entity)
        if ok and type(n) == 'string' and n ~= '' then name = n:lower() end
    end
    nameCache[model] = name or false
    return name
end

local function plantName(name)
    if not name then return false end
    for _, ex in ipairs(F.nameExcludes or {}) do if name:find(ex, 1, true) then return false end end
    for _, pat in ipairs(F.namePatterns or {}) do if name:find(pat, 1, true) then return true end end
    return false
end

-- Short foliage-aware probes around the feet and chest; returns hit point, material, entity.
local function probeFoliage(ped, at)
    local probes = {
        { 0.0, 1.2, 0.6, 0.0, 2.4, -0.9 },
        { 0.0, 0.0, 0.6, 0.0, 0.0, -1.2 },
        { -0.6, 0.6, 0.5, -1.6, 1.8, -0.9 },
        { 0.6, 0.6, 0.5, 1.6, 1.8, -0.9 },
    }
    local last
    for _, p in ipairs(probes) do
        local a = GetOffsetFromEntityInWorldCoords(ped, p[1], p[2], p[3])
        local b = GetOffsetFromEntityInWorldCoords(ped, p[4], p[5], p[6])
        local ray = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 1 + 16 + 256, ped, 7)
        local status, hit, coords, _, material, entity = GetShapeTestResultIncludingMaterial(ray)
        if status == 2 and hit ~= 0 and hit ~= false then
            last = { coords = coords, material = material, entity = entity }
            if foliageMaterial[material] then return last, true end
        end
    end
    return last, false
end

-- Works out what the player could search here, plus details for /bushdebug.
local function scan(withInfo)
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    local radius = F.scanRadius or 3.5
    local info = withInfo and { lines = {} } or nil

    -- 1. Spawned/procedural props in the object pool, by model list or by name.
    local best, bestDist, bestName
    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) then
            local d = #(at - GetEntityCoords(obj))
            if d <= radius and d < (bestDist or math.huge) then
                local okModel, model = pcall(GetEntityModel, obj)
                local name = okModel and archetype(obj, model) or nil
                if okModel and (whitelist[model] or plantName(name)) then best, bestDist, bestName = obj, d, name end
            end
        end
    end
    -- 2. Closest-object search for every known hash (also finds dummy map props).
    if not best then
        for _, h in ipairs(hashes) do
            local obj = GetClosestObjectOfType(at.x, at.y, at.z, radius, h, false, false, false)
            if obj and obj ~= 0 and DoesEntityExist(obj) then
                best, bestDist, bestName = obj, #(at - GetEntityCoords(obj)), whitelist[h] or nameCache[h]
                break
            end
        end
    end
    if best then
        local c = GetEntityCoords(best)
        local model = GetEntityModel(best)
        if info then
            info.entity, info.model, info.name = best, model, bestName
            info.reason = whitelist[model] and 'listed bush (own cooldown)' or 'plant by name (undergrowth cell)'
        end
        return { kind = whitelist[model] and 'bush' or 'plant', x = c.x, y = c.y, z = c.z, model = model }, info
    end

    -- 3. Foliage surface under or in front of the player.
    local hit, foliage = probeFoliage(ped, at)
    if info and hit then
        info.material = hit.material
        if hit.entity and hit.entity ~= 0 and DoesEntityExist(hit.entity) then
            info.entity = hit.entity
            info.model = GetEntityModel(hit.entity)
            info.name = archetype(hit.entity, info.model)
        end
    end
    if F.undergrowth and foliage then
        if info then info.reason = 'foliage material (undergrowth cell)' end
        return { kind = 'undergrowth', x = hit.coords.x, y = hit.coords.y, z = hit.coords.z }, info
    end

    -- 4. Hand-placed foraging areas.
    if F.undergrowth then
        for _, z in ipairs(F.zones or {}) do
            if #(vector2(at.x, at.y) - vector2(z.x, z.y)) <= (z.radius or 10.0)
                and (not z.z or math.abs(at.z - z.z) < 15.0) then
                if info then info.reason = 'inside a configured foraging zone' end
                return { kind = 'undergrowth', x = at.x, y = at.y, z = at.z }, info
            end
        end
    end
    if info then
        info.reason = not F.undergrowth and 'no listed bush nearby and undergrowth is off'
            or (hit and 'surface material is not in the foliage list')
            or 'nothing hit: no plant prop, foliage or zone nearby'
    end
    return nil, info
end

local function startForage(data)
    if busy or not data then return end
    busy = true
    CreateThread(function()
        local result = BSB.Await('jobs:forage:start', 8000, data)
        if not result or not result.ok then busy = false; return notify('warn', result and result.error or L('forage.unavailable')) end
        local label = data.kind == 'bush' and L('forage.progress_bush') or L('forage.progress_undergrowth')
        local done = JC.Timed(label, result.ms, nil, 'search')
        local finish = BSB.Await(done and 'jobs:forage:finish' or 'jobs:forage:cancel', 8000)
        busy = false
        if done and finish and finish.ok then notify('success', L('forage.found', { n = finish.amount, item = finish.label }))
        elseif done then notify('warn', finish and finish.error or L('forage.interrupted')) end
    end)
end

-- Old entity payloads still work; zone payloads carry the scan result in args.
AddEventHandler('bs:jobs:forage', function(payload)
    if type(payload) ~= 'table' then return end
    if type(payload.args) == 'table' and payload.args.kind then return startForage(payload.args) end
    local entity = payload.entity
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local at = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    startForage({ kind = whitelist[model] and 'bush' or 'plant', x = at.x, y = at.y, z = at.z, model = model })
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    local shown
    while true do
        Wait(F.scanInterval or 900)
        local ped = PlayerPedId()
        local found
        if not busy and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
            local ok, res = pcall(scan, false)
            found = ok and res or nil
        end
        if found then
            local key = found.kind == 'bush' and 'forage.search_bush' or 'forage.search_undergrowth'
            exports.bs_interactions:AddZone(ZONE_ID, vector3(found.x, found.y, found.z), (F.scanRadius or 3.5) + 1.0, {
                { label = L(key), labelKey = key, event = 'bs:jobs:forage', icon = 'hand', args = found },
            })
            shown = true
        elseif shown then
            exports.bs_interactions:RemoveZone(ZONE_ID)
            shown = false
        end
    end
end)

-- Admin only: the server checks permission and sends this back.
local function drawLine(text, y)
    SetTextFont(4); SetTextScale(0.34, 0.34); SetTextColour(255, 255, 255, 230); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(0.015, y)
end
local bushDebug = false
RegisterNetEvent('bs:jobs:bushdebug', function()
    bushDebug = not bushDebug
    notify('info', bushDebug and L('forage.debug_on') or L('forage.debug_off'))
    if not bushDebug then return end
    CreateThread(function()
        local info, nextScan, printed = nil, 0, false
        while bushDebug do
            Wait(0)
            if GetGameTimer() >= nextScan then
                nextScan = GetGameTimer() + 500
                local ok, res, i = pcall(scan, true)
                info = ok and i or { reason = 'scan error: ' .. tostring(res) }
                info.result = ok and res or nil
                if not printed then
                    printed = true
                    print(('[bushdebug] entity=%s model=%s name=%s material=%s searchable=%s reason=%s'):format(
                        tostring(info.entity), tostring(info.model), tostring(info.name), tostring(info.material),
                        tostring(info.result ~= nil), tostring(info.reason)))
                end
            end
            if info then
                drawLine(('BUSH DEBUG  searchable: %s (%s)'):format(info.result and 'YES' or 'NO', info.result and info.result.kind or '-'), 0.30)
                drawLine(('entity: %s  model: %s'):format(tostring(info.entity or '-'), tostring(info.model or '-')), 0.325)
                drawLine(('name: %s'):format(tostring(info.name or 'unknown (map geometry or no archetype name)')), 0.35)
                drawLine(('material: %s'):format(tostring(info.material or '-')), 0.375)
                drawLine(('why: %s'):format(tostring(info.reason)), 0.40)
            end
        end
    end)
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then cleanup() end
end)
