-- bs_interactions - the dot. Hold LALT to cast a ray from the camera; if it hits something with options the dot opens into a ring
-- with the option list. E or click runs the highlighted one. Own raycast, registry and UI (not ox_target).

Target = { active = false, entity = nil, options = {}, index = 1, open = false }

local S = Interactions.Settings
local lastScan = 0
local lastTargetSig = nil   -- last options pushed to the page
local outlined = nil
local lastHide = 0
local lastScanError = 0

local function send(p) SendNUIMessage(p) end

-- Raycast

-- Two fixes so ALT works without aiming:
-- 1. Use the synchronous probe and check its status; the async ray was read on the frame it started and a pending result looked like a miss.
-- 2. Add the camera-to-player gap to the ray length so maxDistance is measured from the player, not the camera.
local function castFromCamera()
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)

    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(
        -math.sin(yaw) * math.abs(math.cos(pitch)),
         math.cos(yaw) * math.abs(math.cos(pitch)),
         math.sin(pitch)
    )

    -- Camera-to-player gap, added on top of the reach.
    local gap = #(camCoords - GetEntityCoords(ped))
    local dest = camCoords + dir * (gap + S.maxDistance + (S.camPadding or 1.0))

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camCoords.x, camCoords.y, camCoords.z,
        dest.x, dest.y, dest.z,
        S.traceFlags, ped, 4)

    local status, hit, endCoords, _, entity = GetShapeTestResult(ray)
    -- A pending or failed probe is not a miss.
    if status ~= 2 then return nil end
    if hit == 0 or hit == false then return nil end
    -- Map geometry hits return handles that are not entities; never pass those on.
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil, endCoords end
    -- The camera can sit past a wall in tight rooms: the player must see it too
    if not HasEntityClearLosToEntity(ped, entity, 17) then return nil, endCoords end
    return entity, endCoords
end

-- Second cast from the player: a fan of three synchronous probes angled downward (no sync capsule native exists).
-- Catches low things like bodies, bins and boot lids. Only runs when the camera probe found nothing.
local function castFromPlayer()
    local ped = PlayerPedId()
    local at  = GetEntityCoords(ped)

    -- Chest height.
    local from = vector3(at.x, at.y, at.z + (S.probeStartHeight or 0.35))

    local heading = math.rad(GetEntityHeading(ped))
    local reach = S.maxDistance
    local side  = S.probeSpread or 0.5
    local drop  = S.probeDrop or 0.95

    -- Centre, then half a metre either side at the far end, to stand in for capsule radius.
    for _, spread in ipairs({ 0.0, -side, side }) do
        local sx = math.cos(heading) * spread
        local sy = math.sin(heading) * spread

        local to = vector3(
            from.x - math.sin(heading) * reach + sx,
            from.y + math.cos(heading) * reach + sy,
            from.z - drop)

        local ray = StartExpensiveSynchronousShapeTestLosProbe(
            from.x, from.y, from.z,
            to.x, to.y, to.z,
            S.traceFlags, ped, 4)

        local status, hit, endCoords, _, entity = GetShapeTestResult(ray)
        if status == 2 and hit ~= 0 and hit ~= false
           and entity and entity ~= 0 and DoesEntityExist(entity) then
            return entity, endCoords
        end
    end

    return nil
end

-- noOutline per entity: skips SetEntityDrawOutline for peds with an unusual flag combination (frozen, invincible, untargetable, mission entity), e.g. bs_traders peds, as a suspected crash cause.
local function setOutline(entity)
    if outlined == entity then return end

    if outlined and DoesEntityExist(outlined) then
        SetEntityDrawOutline(outlined, false)
    end
    outlined = nil

    local flags = Registry.entityFlags and Registry.entityFlags[entity]
    -- No outline on bodies: a corpse can be deleted by the server or the cleanup at any
    -- moment, and an outline left on a removed ped took the client down.
    if S.useOutline and entity and entity ~= 0 and DoesEntityExist(entity)
       and not (flags and flags.noOutline)
       and not IsEntityAPed(entity) then
        SetEntityDrawOutlineColor(S.outline.r, S.outline.g, S.outline.b, S.outline.a)
        SetEntityDrawOutline(entity, true)
        outlined = entity
    end
end

-- Blocking conditions

-- Cross-resource exports are not free and this loop runs every frame, so the loaded flag is re-read from bs_core at most every 250ms.
local _perfLoadedAt, _perfLoaded = 0, false
local function loadedCached()
    local now = GetGameTimer()
    if now - _perfLoadedAt >= 250 then
        _perfLoadedAt = now
        local ok, v = pcall(function() return exports.bs_core:IsLoaded() end)
        _perfLoaded = ok and v == true
    end
    return _perfLoaded
end

local function blocked()
    if LocalPlayer.state.bsDrone then return true end   -- ALT zooms the drone camera
    local ped = PlayerPedId()
    if S.blockWhenDead and IsEntityDead(ped) then return true end
    if S.blockWhenCuffed and IsPedCuffed(ped) then return true end
    if S.blockInVehicle and IsPedInAnyVehicle(ped, false) then return true end
    if not exports.bs_core:IsLoaded() then return true end

    -- Disabled while a firearm is aimed or firing. A freshly deleted ped (shot zombie) can leave a stale entity handle, and reading it can crash the game.
    -- Melee is not blocked. If crashes continue with melee, widen this check.
    if S.blockWhileAiming ~= false then
        if IsPlayerFreeAiming(PlayerId()) then return true end
        if IsPedShooting(ped) then return true end

        -- Read the aim control through both accessors, since other systems disable it.
        if IsControlPressed(0, 25) or IsDisabledControlPressed(0, 25) then
            -- Only block when the held item can be aimed (GetMaxAmmoInClip > 0). Control 25 is also cover/vehicle aim, so unarmed RMB must not block looting.
            local _, hash = GetCurrentPedWeapon(ped, true)
            if hash and hash ~= 0 and IsWeaponValid(hash)
                and GetMaxAmmoInClip(ped, hash, 0) > 1 then
                return true
            end
        end
    end

    return false
end

-- Proximity fallback: anything registered that is standing right next to you

-- Proximity scan for registered entities or entities with a registered model. Containers are registered by model and had no fallback.
-- Uses GetGamePool, never the Find/EndFind iterators (use-after-free risk). Throttled by `poolInterval` in config.lua.
local poolCacheAt = 0
local poolCache = nil

local function registeredNearby(pedCoords)
    local now = GetGameTimer()

    if not poolCache or now - poolCacheAt > (S.poolInterval or 250) then
        poolCacheAt = now
        poolCache = {}

        for _, pool in ipairs({ 'CObject', 'CPed', 'CVehicle' }) do
            local ok, list = pcall(GetGamePool, pool)
            if ok and type(list) == 'table' then
                for _, entity in ipairs(list) do
                    poolCache[#poolCache + 1] = entity
                end
            end
        end
    end

    -- Returns every candidate in reach, nearest first, so the caller can walk the list until one offers options. Registered handles sort ahead of model matches at equal distance.
    local candidates = {}

    for entityId in pairs(Registry.entities) do
        if DoesEntityExist(entityId) then
            local d = #(pedCoords - GetEntityCoords(entityId))
            if d <= S.maxDistance then
                candidates[#candidates + 1] = { entity = entityId, dist = d, rank = 0 }
            end
        end
    end

    for _, entity in ipairs(poolCache) do
        if DoesEntityExist(entity) and not Registry.entities[entity] then
            local d = #(pedCoords - GetEntityCoords(entity))
            if d <= S.maxDistance then
                -- ModelOf, not GetEntityModel: the latter faults on entities whose archetype is not resolved, which pool snapshots can contain.
                local model = BS.Util.ModelOf(entity)
                if model and Registry.models[model] then
                    candidates[#candidates + 1] = { entity = entity, dist = d, rank = 1 }
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.dist < b.dist
    end)

    return candidates
end

-- Aiming loop

-- Compare options by value, not identity: tables crossing an export boundary are copies, so the same drop registered via AddEntity and AddZone would otherwise show up twice.
local function sameOption(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end

    if a.label ~= b.label then return false end
    if a.event ~= b.event or a.serverEvent ~= b.serverEvent then return false end
    if a.action ~= b.action then return false end

    local aa, ba = a.args, b.args
    if aa == ba then return true end
    if type(aa) == 'table' and type(ba) == 'table' then
        -- Shallow compare: drop ids, npc ids, container keys are flat.
        for k, v in pairs(aa) do if ba[k] ~= v then return false end end
        for k, v in pairs(ba) do if aa[k] ~= v then return false end end
        return true
    end

    return aa == ba
end

local function addUnique(options, opt)
    for _, existing in ipairs(options) do
        if sameOption(existing, opt) then return end
    end
    options[#options + 1] = opt
end

local function clearTarget()
    if not Target.active and not Target.entity then return end
    Target.active = false
    Target.entity = nil
    Target.options = {}
    Target.index = 1
    lastTargetSig = nil
    setOutline(nil)
    send({ action = 'target', state = 'idle' })
end

-- Called by Registry.RemoveEntity while the handle is still valid, so the outline can be switched off before the caller deletes the entity.
function Target.ForceRelease(entity)
    if entity and (entity == Target.entity or entity == outlined) then
        clearTarget()
    end
end

CreateThread(function()
    send({ action = 'dot', settings = {
        size = S.dotSize, ring = S.ringSize,
        idle = S.dotIdleAlpha, active = S.dotActiveAlpha,
    } })

    local wasAiming = false

    while true do
        -- LALT is INPUT_CHARACTER_WHEEL, which freezes the camera and slows time. Disable it every frame and read it through the disabled check.
        if loadedCached() then
            DisableControlAction(0, S.targetKey, true)
            DisableControlAction(0, 20, true)      -- multiplayer info / char wheel sibling
        end

        local aiming = (IsDisabledControlPressed(0, S.targetKey)
                        or IsControlPressed(0, S.targetKey)) and not blocked()

        if aiming ~= wasAiming then
            wasAiming = aiming
            send({ action = 'dot', visible = aiming })
        end

        -- Re-send "hidden" a few times a second while not aiming, so a dropped message can never leave the dot stuck on screen.
        if not aiming and GetGameTimer() - (lastHide or 0) > 400 then
            lastHide = GetGameTimer()
            lastTargetSig = nil
            send({ action = 'dot', visible = false })
            send({ action = 'target', state = 'idle' })
        end

        if aiming then
            -- Keys are read every frame; only the scan below is throttled by scanInterval.
            Wait(0)

            if GetGameTimer() - lastScan >= (S.scanInterval or 0) then
                lastScan = GetGameTimer()

                -- The whole scan is in a pcall: if this thread dies the dot freezes until restart.
                local scanned, scanErr = pcall(function()

                -- Outlined thing went away under us: forget the handle, it may be reused.
                if outlined and not DoesEntityExist(outlined) then outlined = nil end
                if Target.entity and not DoesEntityExist(Target.entity) then
                    Target.entity = nil
                    Target.options = {}
                    Target.active = false
                end

                local entity, coords = castFromCamera()
                local ped = PlayerPedId()
                local pedCoords = GetEntityCoords(ped)
                local distance = coords and #(pedCoords - coords) or 999.0

                -- Entity options need a real raycast hit. Zone options are resolved around the player, not the ray (see Registry.ResolveZones). checkZones = false avoids a second ray-centred zone check.
                local options = {}
                local hitEntity = nil

                -- Fallbacks are gated on "no options yet", not on "the ray hit something": in third person the ray usually hits some unrelated entity past the target and the fallbacks were being skipped.
                -- An entity that offers nothing is not claimed as the target.
                if entity and entity ~= 0 and distance <= S.maxDistance then
                    local hitOptions = Registry.Resolve(entity, coords, distance, false)
                    if #hitOptions > 0 then
                        hitEntity = entity
                        for _, opt in ipairs(hitOptions) do
                            options[#options + 1] = opt
                        end
                    end
                end

                -- Vehicles are found by proximity to the player, since the camera ray passes over low bonnets and boot lids. Only fills in when the ray found nothing.
                -- General fallback, tried first of the three; it also covers props. The two below catch cars beside you and bodies underfoot.
                -- Gated on "no options yet", not "no raycast hit".
                if #options == 0 then
                    local entity2, coords2 = castFromPlayer()
                    if entity2 then
                        local d = coords2 and #(pedCoords - coords2) or 0.0
                        local probeOptions = Registry.Resolve(entity2, coords2 or pedCoords, d, false)
                        -- An entity that offers nothing is not a target, and must not stop the fallbacks.
                        if #probeOptions > 0 then
                            hitEntity = entity2
                            for _, opt in ipairs(probeOptions) do
                                options[#options + 1] = opt
                            end
                        end
                    end
                end

                -- Bodies are low, so the camera ray passes over them. Scan Registry.entities (small set) by distance. A real ray hit still wins.
                if #options == 0 then
                    -- Registered entities and registered models by proximity, nearest first, until one offers something.
                    for _, candidate in ipairs(registeredNearby(pedCoords)) do
                        local nearOptions = Registry.Resolve(
                            candidate.entity, pedCoords, candidate.dist, false)

                        if #nearOptions > 0 then
                            hitEntity = candidate.entity
                            for _, opt in ipairs(nearOptions) do
                                options[#options + 1] = opt
                            end
                            break
                        end
                    end
                end

                if #options == 0 then
                    local nearVehicle = GetClosestVehicle(pedCoords.x, pedCoords.y, pedCoords.z,
                        S.maxDistance, 0, 71)

                    if nearVehicle and nearVehicle ~= 0 and DoesEntityExist(nearVehicle) then
                        local vDist = #(pedCoords - GetEntityCoords(nearVehicle))

                        if vDist <= S.maxDistance then
                            local vehOptions = Registry.Resolve(nearVehicle, pedCoords, vDist, false)
                            for _, opt in ipairs(vehOptions) do
                                addUnique(options, opt)
                            end
                            -- Only claim the car if it offered something, so a rejected boot option leaves the target free.
                            if #options > 0 then hitEntity = nearVehicle end
                        end
                    end
                end

                for _, opt in ipairs(Registry.ResolveZones(pedCoords)) do
                    addUnique(options, opt)
                end

                if #options > 0 then
                    local changed = hitEntity ~= Target.entity or #options ~= #Target.options
                    Target.entity = hitEntity
                    Target.options = options
                    Target.active = true
                    if changed then Target.index = 1 end

                    setOutline(hitEntity)

                    local list, sig = {}, {}
                    for i, o in ipairs(options) do
                        local label = Registry.Label(o)
                        list[i] = { label = label, icon = o.icon, hint = o.hint }
                        sig[i] = tostring(label) .. '|' .. tostring(o.icon) .. '|' .. tostring(o.hint)
                    end
                    sig = Target.index .. '#' .. table.concat(sig, ';')

                    -- Same options as the last scan: the page already has them, skip the message.
                    if sig ~= lastTargetSig then
                        lastTargetSig = sig
                        send({
                            action = 'target',
                            state = 'live',
                            options = list,
                            index = Target.index,
                        })
                    end
                else
                    clearTarget()
                end

                end)   -- pcall

                if not scanned then
                    clearTarget()
                    if GetGameTimer() - (lastScanError or 0) > 5000 then
                        lastScanError = GetGameTimer()
                        print(('^1[BeyondSurvival]^7 (interactions) scan failed: %s')
                            :format(tostring(scanErr)))
                    end
                end
            end

            -- Cycle options with the wheel when there is more than one.
            if #Target.options > 1 then
                if IsControlJustPressed(0, 241) then
                    Target.index = Target.index > 1 and Target.index - 1 or #Target.options
                    send({ action = 'index', index = Target.index })
                elseif IsControlJustPressed(0, 242) then
                    Target.index = Target.index < #Target.options and Target.index + 1 or 1
                    send({ action = 'index', index = Target.index })
                end
            end

            if Target.active and IsControlJustPressed(0, S.interactKey) then
                Target.Run(Target.index)
            end
        else
            if Target.active or Target.entity then clearTarget() end
            Wait(0)
        end
    end
end)

-- Running an option

function Target.Run(index)
    local option = Target.options[index or Target.index]
    local entity = Target.entity
    if not option then return end

    clearTarget()

    -- The body or prop was removed between the scan and the key press. Running the option
    -- would hand a dead handle to the kneel and loot code.
    if entity and not DoesEntityExist(entity) then return end

    local netId = 0
    if entity and NetworkGetEntityIsNetworked(entity) then
        netId = NetworkGetNetworkIdFromEntity(entity)
    end

    local payload = {
        entity = entity,
        netId = netId,
        coords = entity and DoesEntityExist(entity) and GetEntityCoords(entity) or nil,
        -- Runs on every scan tick. ModelOf guards the call and names this resource on failure.
        model = entity and BS.Util.ModelOf(entity) or nil,
        args = option.args,
    }

    if type(option.action) == 'function' then
        CreateThread(function()
            local ok, err = pcall(option.action, payload)
            if not ok then
                print(('[bs_interactions] action failed: %s'):format(tostring(err)))
                TriggerEvent('bs:ui:notify', {
                    type = 'warn', title = L('interact.title'),
                    message = L('interact.failed'),
                    duration = 4000,
                })
            end
        end)
    end
    if option.event then TriggerEvent(option.event, payload) end
    if option.serverEvent then
        TriggerServerEvent(option.serverEvent, netId, option.args)
    end
end

-- The dot only shows while the target key is held.

AddEventHandler('bs:hook:player:unloaded', function()
    clearTarget()
    send({ action = 'dot', visible = false })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then setOutline(nil) end
end)

exports('IsTargeting', function() return Target.active end)
exports('CurrentEntity', function() return Target.entity end)

-- Prop debug overlay. Lives in this file to use the file-local castFromCamera/castFromPlayer. Kept at the bottom because a local function referenced above its declaration is nil at runtime.
-- Shows model name (if resolvable), model hash (always, paste it into configs), entity type, handle, distance and whether the registry has options for the model.

local debugOn = false

-- Names cannot be recovered from hashes. Sources: GetEntityArchetypeName if the build has it (called via _G in pcall), then model names this resource registered earlier.
local function modelName(entity, hash)
    local native = rawget(_G, 'GetEntityArchetypeName')
    if type(native) == 'function' then
        local ok, name = pcall(native, entity)
        if ok and type(name) == 'string' and name ~= '' then return name end
    end

    if Registry.modelNames and hash then return Registry.modelNames[hash] end
    return nil
end

local typeNames = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

-- Nearest entity of any kind, registered or not (the overlay identifies props the registry does not know yet).
-- Uses GetGamePool, never the Find/EndFind iterators, and reuses poolCache.
local function debugNearest(pedCoords)
    -- Refreshes poolCache on the poolInterval throttle when the aiming loop is not doing it.
    registeredNearby(pedCoords)

    local best, bestDist = nil, math.huge
    for _, entity in ipairs(poolCache or {}) do
        if DoesEntityExist(entity) then
            local d = #(pedCoords - GetEntityCoords(entity))
            if d <= S.maxDistance and d < bestDist then
                best, bestDist = entity, d
            end
        end
    end

    return best, bestDist
end

-- Debug pick does not use Target.entity (only set for entities with options). Both ray and pool sources are collected and the closest to the player wins.
-- Separate debug ray: uses S.debugDistance instead of maxDistance; ray first since static map props are not in the object pool, pool as fallback; uses S.traceFlags (all bits).
-- Terrain and baked building shells have no entity, so that case reports hit position and surface material instead.
-- Returns entity|nil, distance|nil, worldHit|nil.
local function debugCast()
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)

    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(
        -math.sin(yaw) * math.abs(math.cos(pitch)),
         math.cos(yaw) * math.abs(math.cos(pitch)),
         math.sin(pitch))

    local reach = S.debugDistance or 250.0
    local dest = camCoords + dir * reach

    -- IncludingMaterial form: the material hash is all there is to show for terrain hits.
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camCoords.x, camCoords.y, camCoords.z,
        dest.x, dest.y, dest.z,
        S.traceFlags, ped, 4)

    local status, hit, endCoords, _, material, entity =
        GetShapeTestResultIncludingMaterial(ray)

    if status ~= 2 or hit == 0 or hit == false then return nil end

    local pedCoords = GetEntityCoords(ped)
    local distance = endCoords and #(pedCoords - vector3(endCoords.x, endCoords.y, endCoords.z)) or nil

    if entity and entity ~= 0 and entity ~= ped and DoesEntityExist(entity) then
        return entity, distance
    end

    -- Hit something with no entity behind it. Not a miss.
    return nil, distance, { coords = endCoords, material = material }
end

local function debugPick()
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    -- The ray first, and it wins outright when it finds an entity. It sees map props the pool cannot.
    local entity, distance, worldHit = debugCast()
    if entity then return entity, distance end

    -- Then the pool, at debug range. Second on purpose, so a far pool object does not beat the thing you point at.
    registeredNearby(pedCoords)

    local best, bestDist = nil, math.huge
    local reach = S.debugDistance or 250.0

    for _, candidate in ipairs(poolCache or {}) do
        if candidate ~= ped and DoesEntityExist(candidate) then
            local d = #(pedCoords - GetEntityCoords(candidate))
            if d <= reach and d < bestDist then best, bestDist = candidate, d end
        end
    end

    -- Only if roughly where we are looking: half a metre of tolerance per metre of distance (narrow cone).
    if best and worldHit and worldHit.coords then
        local aimAt = vector3(worldHit.coords.x, worldHit.coords.y, worldHit.coords.z)
        if #(GetEntityCoords(best) - aimAt) > math.max(1.5, bestDist * 0.5) then
            best = nil
        end
    end

    if best then return best, bestDist end

    -- Nothing with a handle: return the world-geometry answer.
    return nil, distance, worldHit
end

local function drawDebugLine(text, y)
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.015, y)
end

CreateThread(function()
    while true do
        if not debugOn then
            -- Idle at half a second so an overlay that is off costs nothing.
            Wait(500)
        else
            Wait(0)

            -- Inside a pcall: a stale handle would otherwise kill this draw thread silently.
            local ok = pcall(function()
                local entity, dist, worldHit = debugPick()

                DrawRect(0.115, 0.055, 0.215, 0.085, 0, 0, 0, 150)
                drawDebugLine('~y~BS TARGET DEBUG~s~', 0.020)

                if not entity then
                    -- A terrain hit (no entity) and a total miss are different. A world hit reports position, distance and surface material.
                    if worldHit then
                        drawDebugLine('~o~map geometry~s~ (no entity, no model)', 0.040)
                        drawDebugLine(('material: ~g~%s~s~')
                            :format(tostring(worldHit.material or 'unknown')), 0.055)
                        local c = worldHit.coords
                        drawDebugLine(('%.2f, %.2f, %.2f  |  %.1fm')
                            :format(c and c.x or 0.0, c and c.y or 0.0,
                                    c and c.z or 0.0, dist or 0.0), 0.070)
                    else
                        drawDebugLine(('nothing within %.0fm'):format(S.debugDistance or 250.0), 0.040)
                    end
                    return
                end

                -- ModelOf, not GetEntityModel (faults on unresolved archetypes).
                local hash = BS.Util.ModelOf(entity)
                local name = hash and modelName(entity, hash) or nil
                local eType = typeNames[GetEntityType(entity)] or 'unknown'

                -- Name and hash lines are separate on purpose: the hash is what you paste into a config, so it must show even if the name lookup fails.
                drawDebugLine(('model: ~b~%s~s~'):format(name or 'unresolved'), 0.040)
                drawDebugLine(('hash : ~g~%s~s~'):format(
                    hash and tostring(hash) or 'UNREADABLE'), 0.055)

                local known = hash and Registry.models[hash] and #Registry.models[hash] or 0
                drawDebugLine(('%s | %.2fm | handle %d | %d option(s)')
                    :format(eType, dist or 0.0, entity, known), 0.070)
            end)

            if not ok then Wait(250) end
        end
    end
end)

-- Toggled from the server only (see sv_main.lua), since the client cannot test an ACE. Off by default.
-- Exports the debug pick (long-range ray plus pool fallback, see debugCast) for overlays like bs_admin's prop-ID tool.
-- Returns entity|nil, distance|nil, worldHit|nil. worldHit is set when the ray hit map geometry with no entity.
exports('DebugLookAt', function()
    local ok, entity, distance, worldHit = pcall(debugPick)
    if not ok then return nil end
    return entity, distance, worldHit
end)

RegisterNetEvent('bs_interactions:debug:toggle', function(state)
    debugOn = state and true or false
    print(('^5[BeyondSurvival]^7 (interactions) target debug %s')
        :format(debugOn and 'ON' or 'OFF'))
end)

AddEventHandler('bs:hook:player:unloaded', function() debugOn = false end)
