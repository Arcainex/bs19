-- Trainer NPCs: local peds, spawned when you get close. Talk to learn moves or take a trial.

local Peds, Blips = {}, {}
local SPAWN, DESPAWN = 90.0, 120.0

local function notify(r)
    if type(r) ~= 'table' then return end
    TriggerEvent('bs:ui:notify', { type = r.ok and 'success' or 'warn', message = r.msg or L(r.ok and 'pk.done' or 'pk.failed'), duration = 4500 })
end

local function options(t)
    local opts = {
        { label = L(t.tier == 'advanced' and 'pk.opt_learn_adv' or 'pk.opt_learn'), icon = 'hand', distance = 2.5, event = 'bs:parkour:learn', args = { id = t.id } },
    }
    for _, cid in ipairs(t.chains or {}) do
        opts[#opts + 1] = { label = L('pk.opt_trial', { title = L('ch.' .. cid .. '.t') }), icon = 'hand', distance = 2.5, event = 'bs:parkour:trial', args = { id = t.id, chain = cid } }
    end
    return opts
end

local function spawn(t)
    local model = joaat(t.model)
    if not IsModelInCdimage(model) then model = joaat('a_m_y_runner_01') end
    RequestModel(model)
    local wait = GetGameTimer() + 4000
    while not HasModelLoaded(model) and GetGameTimer() < wait do Wait(20) end
    if not HasModelLoaded(model) then return end
    local z = t.z
    local found, gz = GetGroundZFor_3dCoord(t.x, t.y, t.z + 50.0, false)
    if found and math.abs(gz - t.z) < 60.0 then z = gz end
    local ped = CreatePed(4, model, t.x, t.y, z, t.h or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 or not DoesEntityExist(ped)then return end
    Entity(ped).state:set('bsProtected',true,false)
    SetEntityAsMissionEntity(ped,true,true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS', 0, true)
    Peds[t.id] = ped
    if GetResourceState('bs_interactions') == 'started' then
        pcall(function() exports.bs_interactions:AddEntity(ped, options(t)) end)
    end
end

local function despawn(id)
    local ped = Peds[id]
    if ped and DoesEntityExist(ped) then
        pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
        ClearPedTasksImmediately(ped)
        DeleteEntity(ped)
    end
    Peds[id] = nil
end

CreateThread(function()
    for _, t in ipairs(Parkour.Trainers) do
        if t.blip then
            local b = AddBlipForCoord(t.x, t.y, t.z)
            SetBlipSprite(b, 126)
            SetBlipColour(b, 47)
            SetBlipScale(b, 0.7)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(L('pk.blip'))
            EndTextCommandSetBlipName(b)
            Blips[#Blips + 1] = b
        end
    end
    while true do
        local me = GetEntityCoords(PlayerPedId())
        for _, t in ipairs(Parkour.Trainers) do
            local existing=Peds[t.id]
            if existing and not DoesEntityExist(existing)then
                pcall(function()exports.bs_interactions:RemoveEntity(existing)end)
                Peds[t.id]=nil
            end
            local d = #(me - vector3(t.x, t.y, t.z))
            if Parkour.Settings.enabled and d < SPAWN and not Peds[t.id] then spawn(t)
            elseif (d > DESPAWN or not Parkour.Settings.enabled) and Peds[t.id] then despawn(t.id) end
        end
        Wait(1500)
    end
end)

AddEventHandler('bs:parkour:learn', function(p)
    local id = p and p.args and p.args.id
    if not id then return end
    notify(BSB.Await('parkour:learn', 8000, id))
end)

AddEventHandler('bs:parkour:trial', function(p)
    local a = p and p.args
    if not a then return end
    notify(BSB.Await('parkour:accept', 8000, a.id, a.chain))
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Peds) do despawn(id) end
    for _, b in ipairs(Blips) do RemoveBlip(b) end
end)
