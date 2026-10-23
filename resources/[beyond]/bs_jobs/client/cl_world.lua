-- bs_jobs client world: ground height for the animal spawner, animal behaviour, fishing, purifier, siphon, chop.

local notify = JC.Notify

-- The server spawns animals; it asks a nearby client where the ground is.
BSB.RegisterClientCallback('jobs:groundZ', function(x, y)
    x, y = tonumber(x) or 0.0, tonumber(y) or 0.0
    RequestCollisionAtCoord(x, y, 100.0)
    for _ = 1, 10 do
        local found, z = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, 1000.0, false)
        if found then
            local water, wz = GetWaterHeight(x + 0.0, y + 0.0, z + 0.0)
            if water and wz > z then return {} end
            return { z = z }
        end
        Wait(100)
    end
    return {}
end)

-- Animals the server made start idle; whoever owns one runs its behaviour.
-- Predators (bsAnimalKind = predator) charge players close by; the rest wander and run from people.
local AN = {}   -- [ped] = { mode, target }
local predGroup
local function predatorGroup()
    if not predGroup then
        local _, h = AddRelationshipGroup('BS_PREDATOR')
        predGroup = h
        SetRelationshipBetweenGroups(5, h, GetHashKey('PLAYER'))
    end
    return predGroup
end

-- Nearest live player ped. Predators skip players in vehicles or in a safezone.
local function nearestPlayer(pos, forAttack)
    local best, bestD
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        if p ~= 0 and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) then
            local ok = true
            if forAttack then
                local st = Player(GetPlayerServerId(pl)).state
                ok = not IsPedInAnyVehicle(p, false) and not (st and st.bsFactionSafeZone)
            end
            if ok then
                local d = #(GetEntityCoords(p) - pos)
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
    end
    return best, bestD
end

local function think(ped, st)
    local S = Jobs.Settings
    local a = AN[ped]
    local pred = st.bsAnimalKind == 'predator' and S.huntPredators ~= false
    if not a or a.pred ~= pred then
        a = { mode = 'none', pred = pred }
        AN[ped] = a
        if pred then
            SetPedRelationshipGroupHash(ped, predatorGroup())
            SetPedCombatAttributes(ped, 46, true)
            SetPedCombatAttributes(ped, 5, true)
            SetPedFleeAttributes(ped, 0, false)
        else
            SetPedFleeAttributes(ped, 0, true)
        end
    end
    local pos = GetEntityCoords(ped)
    local hurt = HasEntityBeenDamagedByAnyPed(ped)
    if hurt then ClearEntityLastDamageEntity(ped) end
    if pred then
        local tgt, d = nearestPlayer(pos, true)
        local aggro = tonumber(S.huntAggroRadius) or 25.0
        if a.mode == 'attack' then
            if not tgt or d > (tonumber(S.huntLeash) or 70.0) then
                a.mode, a.target = 'none', nil
                ClearPedTasks(ped)
            elseif tgt ~= a.target and d <= aggro then
                a.target = tgt
                TaskCombatPed(ped, tgt, 0, 16)
            end
        elseif tgt and (d <= aggro or (hurt and d <= (tonumber(S.huntLeash) or 70.0))) then
            a.mode, a.target = 'attack', tgt
            TaskCombatPed(ped, tgt, 0, 16)
        end
    else
        local tgt, d = nearestPlayer(pos, false)
        local flee = tonumber(S.huntFleeRadius) or 30.0
        if tgt and (d <= flee or hurt) then
            if a.mode ~= 'flee' then
                a.mode = 'flee'
                TaskSmartFleePed(ped, tgt, 150.0, -1, false, false)
            end
        elseif a.mode == 'flee' and (not tgt or d > flee * 3) then
            a.mode = 'none'
        end
    end
    if a.mode == 'none' then
        TaskWanderStandard(ped, 10.0, 10)
        a.mode = 'wander'
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local ok, pool = pcall(GetGamePool, 'CPed')
        if ok then
            for _, ped in ipairs(pool) do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
                    local st = Entity(ped).state
                    if st and st.bsAnimal then
                        if NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true) then
                            think(ped, st)
                        else
                            AN[ped] = nil
                        end
                    end
                end
            end
        end
        for ped in pairs(AN) do if not DoesEntityExist(ped) then AN[ped] = nil end end
    end
end)

--------------------------------------------------------------------------------
-- Fishing spots
--------------------------------------------------------------------------------

AddEventHandler('bs:jobs:fish', function()
    CreateThread(function()
        local f = JC.TimedCall('jobs:fish:start', 'jobs:fish:finish', L('prog.fish'), JC.Anim.fish, 'none')
        if f then
            if f.item then notify('success', L('n.caught', { item = f.label or f.item })) else notify('info', L('n.no_bite')) end
        end
    end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    Wait(1500)
    for i, s in ipairs(Jobs.Fishing.spots) do
        exports.bs_interactions:AddZone('bsjob:fish' .. i, vector3(s.x, s.y, s.z), s.r or 25.0, {
            { labelKey = 'opt.fish', label = 'Fish here', icon = 'hand', event = 'bs:jobs:fish', filters = { onFoot = true } },
        })
        local b = AddBlipForCoord(s.x, s.y, s.z)
        SetBlipSprite(b, 68); SetBlipScale(b, 0.6); SetBlipColour(b, 3); SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L('blip.fish')); EndTextCommandSetBlipName(b)
    end
    -- Siphon fuel from parked cars (Fuel Runner).
    exports.bs_interactions:AddType('vehicle', {
        { labelKey = 'opt.siphon', label = 'Siphon fuel', icon = 'hand', distance = 3.0, event = 'bs:jobs:siphon', filters = { onFoot = true, playerStateTrue = 'bsJ_siphon' } },
    })
end)

--------------------------------------------------------------------------------
-- Purifier, siphon, chop
--------------------------------------------------------------------------------

AddEventHandler('bs:jobs:purify', function()
    CreateThread(function()
        local f = JC.TimedCall('jobs:water:start', 'jobs:water:finish', L('prog.water'), JC.Anim.repair)
        if f then notify('success', L('n.purified')) end
    end)
end)

AddEventHandler('bs:jobs:siphon', function(payload)
    local veh = payload and payload.entity
    if not veh or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    CreateThread(function()
        local f = JC.TimedCall('jobs:siphon:start', 'jobs:siphon:finish', L('prog.siphon'), nil, 'kneel', netId)
        if f then notify('success', L('n.siphoned')) end
    end)
end)

local function nearestVehicle(maxDist)
    local at = GetEntityCoords(PlayerPedId())
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then return veh end
    local best, bd
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - at)
        if d < (maxDist or 6.0) and (not bd or d < bd) then best, bd = v, d end
    end
    return best
end
JC.NearestVehicle = nearestVehicle

AddEventHandler('bs:jobs:chop', function()
    local veh = nearestVehicle(8.0)
    if not veh or not NetworkGetEntityIsNetworked(veh) then return notify('warn', L('err.no_vehicle')) end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    CreateThread(function()
        if not JC.Timed(L('prog.chop'), 15000, JC.Anim.weld) then return notify('warn', L('err.interrupted')) end
        local r = BSB.Await('jobs:chop', 8000, netId)
        if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
        notify('success', L('n.chopped', { n = r.parts or 0 }))
    end)
end)
