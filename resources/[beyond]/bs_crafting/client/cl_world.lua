-- bs_crafting client: skinning, foraging, wreck salvage, traps and crop props.

local S = Crafting.Settings
local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg }) end
local busy = false

local function showItems(items)
    if #(items or {}) == 0 then return notify('info', L('nothing_useful')) end
    for _, it in ipairs(items) do notify('success', ('+%d %s'):format(it.amount, it.label)); Wait(120) end
end

-- start -> kneel/work for the server's time -> finish
local function timed(startCb, finishCb, label, opts, ...)
    if busy then return end
    busy = true
    local r = BSB.Await(startCb, 8000, ...)
    if not r or not r.ok then busy = false; return notify('warn', (r and r.error) or L('failed')) end
    local done = exports.bs_interactions:RunSearch(label, r.ms, opts or { pose = 'kneel' })
    local f = BSB.Await(finishCb, 8000)
    busy = false
    if not done then return notify('warn', L('interrupted')) end
    if not f or not f.ok then return notify('warn', (f and f.error) or L('failed')) end
    showItems(f.items)
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

-- Zombie corpses: bs_zombies adds this option next to "Search body" with args.zid.
AddEventHandler('bs:crafting:skinZombie', function(payload)
    local zid = payload and payload.args and payload.args.zid
    if not zid then return end
    -- The body can be cleaned up between the dot and here; never kneel on a dead handle.
    local ent = payload.entity
    if not ent or not DoesEntityExist(ent) then return notify('warn', L('failed')) end
    CreateThread(function()
        timed('crafting:skinStart', 'crafting:skinFinish', L('skinning'), { pose = 'kneel', entity = payload.entity }, 'zombie', zid)
    end)
end)

local animalModels = {}
for m in pairs(Crafting.Animals) do animalModels[#animalModels + 1] = m end

AddEventHandler('bs:crafting:skinAnimal', function(payload)
    local ent = payload and payload.entity
    if not ent or not DoesEntityExist(ent) or not IsEntityDead(ent) then return end
    local model
    for _, m in ipairs(animalModels) do if GetEntityModel(ent) == GetHashKey(m) then model = m end end
    if not model then return end
    local key = NetworkGetEntityIsNetworked(ent) and ('n' .. NetworkGetNetworkIdFromEntity(ent))
        or ('p%d_%d'):format(GetPlayerServerId(PlayerId()), ent)
    CreateThread(function()
        timed('crafting:skinStart', 'crafting:skinFinish', L('skinning'), { pose = 'kneel', entity = ent }, 'animal', key, model)
        if DoesEntityExist(ent) and not NetworkGetEntityIsNetworked(ent) then SetEntityAsMissionEntity(ent, true, true); DeleteEntity(ent) end
    end)
end)

--------------------------------------------------------------------------------
-- Foraging and salvage
--------------------------------------------------------------------------------

AddEventHandler('bs:crafting:forage', function(payload)
    local ent = payload and payload.entity
    if not ent or not DoesEntityExist(ent) then return end
    local c = GetEntityCoords(ent)
    CreateThread(function() timed('crafting:forageStart', 'crafting:forageFinish', L('foraging'), { pose = 'kneel' }, c.x, c.y) end)
end)

AddEventHandler('bs:crafting:salvage', function(payload)
    local veh = payload and payload.entity
    if not veh or not DoesEntityExist(veh) then return end
    local plate = GetVehicleNumberPlateText(veh)
    CreateThread(function() timed('crafting:salvageStart', 'crafting:salvageFinish', L('salvaging'), { pose = 'kneel' }, plate) end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    Wait(1000)
    exports.bs_interactions:AddModel(animalModels, {
        { label = L('skin_animal'), icon = 'hand', distance = 2.0, event = 'bs:crafting:skinAnimal', filters = { dead = true, onFoot = true } },
    })
    exports.bs_interactions:AddModel(Crafting.ForageModels, {
        { label = L('forage'), icon = 'hand', distance = 2.5, event = 'bs:crafting:forage', filters = { onFoot = true } },
    })
    exports.bs_interactions:AddType('vehicle', {
        { label = L('salvage_wreck'), icon = 'wrench', distance = 3.0, event = 'bs:crafting:salvage', filters = { wreck = true, onFoot = true } },
    })
end)

--------------------------------------------------------------------------------
-- Traps
--------------------------------------------------------------------------------

local traps, props = {}, {}
local myChar = nil

local function modelFor(list)
    for _, m in ipairs(list) do if IsModelInCdimage(m) then return m end end
end

local function spawnProp(t)
    local def = Crafting.Traps[t.kind]
    local model = def and modelFor(def.model)
    if not model then return end
    RequestModel(model)
    local w = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < w do Wait(10) end
    local obj = CreateObject(GetHashKey(model), t.x, t.y, t.z, false, false, false)
    SetEntityHeading(obj, t.h or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetModelAsNoLongerNeeded(model)
    props[t.id] = obj
    if t.kind ~= 'zombie_bait' then
        exports.bs_interactions:AddEntity(obj, { { label = L('pick_up_trap'), icon = 'hand', distance = 2.0, event = 'bs:crafting:pickupTrap', args = { id = t.id } } })
    end
end

RegisterNetEvent('bs:crafting:traps', function(list)
    local keep = {}
    for _, t in ipairs(list or {}) do keep[t.id] = t end
    for id, obj in pairs(props) do
        if not keep[id] then
            exports.bs_interactions:RemoveEntity(obj)
            if DoesEntityExist(obj) then DeleteEntity(obj) end
            props[id] = nil
        end
    end
    traps = keep
    for id, t in pairs(traps) do if not props[id] then CreateThread(function() spawnProp(t) end) end end
end)

AddEventHandler('bs:crafting:pickupTrap', function(payload)
    local id = payload and payload.args and payload.args.id
    if not id then return end
    CreateThread(function()
        local r = BSB.Await('crafting:pickupTrap', 6000, id)
        if not r or not r.ok then notify('warn', (r and r.error) or L('failed')) end
    end)
end)

RegisterNetEvent('bs:crafting:placeTrap', function(kind)
    CreateThread(function()
        local ped = PlayerPedId()
        local c = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
        local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
        local done = exports.bs_interactions:RunSearch(L('placing_trap'), 2500, { pose = 'kneel' })
        if not done then return end
        local r = BSB.Await('crafting:placeTrap', 6000, kind, c.x, c.y, found and gz or c.z - 1.0, GetEntityHeading(ped))
        if not r or not r.ok then return notify('warn', (r and r.error) or L('failed')) end
        notify('success', L('trap_placed'))
    end)
end)

-- Watch nearby traps for something stepping in.
local reported = {}
CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local me = GetEntityCoords(ped)
        if not myChar then local ok, d = pcall(function() return exports.bs_core:GetData() end); myChar = ok and d and d.charId end
        for id, t in pairs(traps) do
            local def = Crafting.Traps[t.kind]
            local tp = vector3(t.x, t.y, t.z)
            if def.radius and #(me - tp) < 60.0 then
                wait = 250
                if (reported[id] or 0) < GetGameTimer() then
                    -- the player
                    if t.owner ~= myChar and #(me - tp) < def.radius and not IsPedInAnyVehicle(ped, false) then
                        reported[id] = GetGameTimer() + 5000
                        TriggerServerEvent('bs:crafting:trapHit', id, 'self')
                    else
                        -- walkers near the trap
                        for _, p in ipairs(GetGamePool('CPed')) do
                            if p ~= ped and not IsPedAPlayer(p) and not IsPedDeadOrDying(p, true)
                                and #(GetEntityCoords(p) - tp) < def.radius then
                                reported[id] = GetGameTimer() + 5000
                                TriggerServerEvent('bs:crafting:trapHit', id, 'ped', NetworkGetEntityIsNetworked(p) and NetworkGetNetworkIdFromEntity(p) or 0)
                                if t.kind == 'bear_trap' then
                                    SetPedToRagdoll(p, 6000, 6000, 0, false, false, false)
                                    ApplyDamageToPed(p, def.damage or 45, false)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('bs:crafting:trapped', function(damage, holdMs)
    local ped = PlayerPedId()
    ApplyDamageToPed(ped, damage, false)
    PlaySoundFrontend(-1, 'Bed', 'WastedSounds', true)
    notify('error', L('caught_trap'))
    local untilT = GetGameTimer() + holdMs
    CreateThread(function()
        while GetGameTimer() < untilT do
            DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true); DisableControlAction(0, 22, true)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('bs:crafting:trapSnap', function(netId, x, y, z, holdMs)
    if not netId or netId == 0 or not NetworkDoesNetworkIdExist(netId) then return end
    local p = NetToPed(netId)
    if DoesEntityExist(p) and NetworkHasControlOfEntity(p) then
        SetPedToRagdoll(p, holdMs, holdMs, 0, false, false, false)
    end
end)

RegisterNetEvent('bs:crafting:alarm', function(x, y, z)
    if #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) > 120.0 then return end
    PlaySoundFromCoord(-1, 'Beep_Red', x, y, z, 'DLC_HEIST_HACKING_SNAKE_SOUNDS', false, 60, false)
end)

--------------------------------------------------------------------------------
-- Crops on farm plots
--------------------------------------------------------------------------------

local crops = {}   -- [id] = { obj, stage }

local function cropModel(stage)
    local list = Crafting.CropProps
    local i = math.max(1, math.min(#list, math.floor(stage * #list) + 1))
    if stage >= 1.0 then i = #list end
    return list[i]
end

local function drawCrop(id, x, y, z, stage)
    local model = cropModel(stage)
    local cur = crops[id]
    if cur and cur.model == model then return end
    if cur and DoesEntityExist(cur.obj) then DeleteEntity(cur.obj) end
    crops[id] = nil
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local w = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < w do Wait(10) end
    local obj = CreateObject(GetHashKey(model), x, y, z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetModelAsNoLongerNeeded(model)
    crops[id] = { obj = obj, model = model }
end

CreateThread(function()
    Wait(6000)
    while true do
        local r = BSB.Await('crafting:crops', 6000)
        if r and r.ok then
            local seen = {}
            for _, c in ipairs(r.list or {}) do
                seen[c.id] = true
                drawCrop(c.id, c.x, c.y, c.z + 0.1, c.stage)
            end
            for id, c in pairs(crops) do
                if not seen[id] then if DoesEntityExist(c.obj) then DeleteEntity(c.obj) end crops[id] = nil end
            end
        end
        Wait(20000)
    end
end)

RegisterNetEvent('bs:crafting:farmChanged', function(id, info)
    if not info and crops[id] then
        if DoesEntityExist(crops[id].obj) then DeleteEntity(crops[id].obj) end
        crops[id] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, obj in pairs(props) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    for _, c in pairs(crops) do if DoesEntityExist(c.obj) then DeleteEntity(c.obj) end end
end)
