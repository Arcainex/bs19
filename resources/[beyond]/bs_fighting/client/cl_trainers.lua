-- bs_fighting - trainer NPCs (local peds, spawned near you) and sparring.

FightTrainers = { peds = {}, spar = nil }

local Spar = Fighting.Spar
local blips = {}

local function trainerPos(t)
    if t.at then return vector3(t.at[1] + 0.0, t.at[2] + 0.0, t.at[3] + 0.0) end
    for _, z in ipairs((Zones and Zones.FactionSafe) or {}) do
        if z.id == t.zone then
            local o = t.offset or { 0.0, 0.0 }
            return vector3(z.coords.x + o[1], z.coords.y + o[2], z.coords.z)
        end
    end
    return nil
end

function FightTrainers.SparTarget(ped)
    local sp = FightTrainers.spar
    if sp and sp.ped == ped then return sp.tid end
    return nil
end

local function options(t)
    local o = {}
    for _, s in ipairs(t.teaches or {}) do
        if not Fight.styles[s] then
            o[#o + 1] = { label = L('trainer.spar', { style = L('style.' .. s) }), icon = 'fist', event = 'bs:fighting:askSpar', args = { tid = t.id, style = s } }
        else
            o[#o + 1] = { label = L('trainer.use', { style = L('style.' .. s) }), icon = 'fist', event = 'bs:fighting:useStyle', args = { style = s } }
        end
    end
    return o
end

local function addTarget(t, ped)
    if GetResourceState('bs_interactions') ~= 'started' then return end
    pcall(function() exports.bs_interactions:AddEntity(ped, options(t), { noOutline = true }) end)
end

local function spawn(t, pos)
    local model = joaat(t.model or 'a_m_y_musclbeac_01')
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local w = GetGameTimer() + 4000
    while not HasModelLoaded(model) and GetGameTimer() < w do Wait(20) end
    if not HasModelLoaded(model) then return nil end
    local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 30.0, false)
    local z = (found and gz or pos.z) + 1.0
    local ped = CreatePed(4, model, pos.x, pos.y, z, t.heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then return nil end
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    -- let it land before pinning it in place
    Wait(600)
    if not DoesEntityExist(ped) then return nil end
    FreezeEntityPosition(ped, true)
    RemoveAllPedWeapons(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS', 0, true)
    addTarget(t, ped)
    return ped
end

local function despawn(id)
    local ped = FightTrainers.peds[id]
    if ped and DoesEntityExist(ped) then
        pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
        DeleteEntity(ped)
    end
    FightTrainers.peds[id] = nil
end

local function refreshTargets()
    for _, t in ipairs(Fighting.Trainers) do
        local ped = FightTrainers.peds[t.id]
        if ped and DoesEntityExist(ped) then addTarget(t, ped) end
    end
end
FightTrainers.Refresh = refreshTargets
RegisterNetEvent('bs:fighting:state', function() Wait(100); refreshTargets() end)

CreateThread(function()
    Wait(6000)
    for _, t in ipairs(Fighting.Trainers) do
        local pos = trainerPos(t)
        if pos and t.blip then
            local b = AddBlipForCoord(pos.x, pos.y, pos.z)
            SetBlipSprite(b, 311); SetBlipScale(b, 0.7); SetBlipColour(b, 47); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L('trainer.blip')); EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
    while true do
        if Fighting.Settings.enabled then
            local at = GetEntityCoords(PlayerPedId())
            for _, t in ipairs(Fighting.Trainers) do
                local pos = trainerPos(t)
                if pos then
                    local d = #(at - pos)
                    local ped = FightTrainers.peds[t.id]
                    if d < 70.0 and not (ped and DoesEntityExist(ped)) then
                        FightTrainers.peds[t.id] = spawn(t, pos)
                    elseif d > 110.0 and ped and not (FightTrainers.spar and FightTrainers.spar.tid == t.id) then
                        despawn(t.id)
                    end
                end
            end
        else
            for id in pairs(FightTrainers.peds) do despawn(id) end
        end
        Wait(2000)
    end
end)

AddEventHandler('bs:fighting:askSpar', function(payload)
    local a = payload and payload.args or {}
    if FightTrainers.spar then return end
    TriggerServerEvent('bs:fighting:sparStart', a.tid, a.style)
end)

AddEventHandler('bs:fighting:useStyle', function(payload)
    local a = payload and payload.args or {}
    if a.style then Fight.SetStyle(a.style) end
end)

-- Sparring

local function endSpar()
    local sp = FightTrainers.spar
    FightTrainers.spar = nil
    SetPlayerMeleeWeaponDefenseModifier(PlayerId(), 1.0)
    if sp and sp.ped and DoesEntityExist(sp.ped) then
        ClearPedTasksImmediately(sp.ped)
        FreezeEntityPosition(sp.ped, true)
        SetBlockingOfNonTemporaryEvents(sp.ped, true)
        TaskStartScenarioInPlace(sp.ped, 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS', 0, true)
    end
end

RegisterNetEvent('bs:fighting:sparBegin', function(tid, styleId, need, seconds)
    local ped = FightTrainers.peds[tid]
    if not ped or not DoesEntityExist(ped) then
        TriggerServerEvent('bs:fighting:sparEnd', 'gone')
        return
    end
    FightTrainers.spar = { tid = tid, ped = ped, style = styleId, need = need, ends = GetGameTimer() + seconds * 1000 }
    SetPlayerMeleeWeaponDefenseModifier(PlayerId(), Spar.defenseMod or 4.0)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAbility(ped, 1)
    TaskCombatPed(ped, PlayerPedId(), 0, 16)
    TriggerEvent('bs:ui:notify', { type = 'info', message = L('spar.begin', { n = need, s = seconds }), duration = 5000 })

    CreateThread(function()
        while FightTrainers.spar and FightTrainers.spar.tid == tid do
            local me = PlayerPedId()
            local hp = GetEntityHealth(me) - 100
            if IsPedDeadOrDying(me, true) or hp <= (Spar.loseAt or 35) then
                TriggerServerEvent('bs:fighting:sparEnd', 'lost'); endSpar(); break
            end
            if GetGameTimer() > FightTrainers.spar.ends then
                TriggerServerEvent('bs:fighting:sparEnd', 'time'); endSpar(); break
            end
            if #(GetEntityCoords(me) - GetEntityCoords(ped)) > (Spar.range or 30.0) then
                TriggerServerEvent('bs:fighting:sparEnd', 'left'); endSpar(); break
            end
            Wait(200)
        end
    end)
end)

RegisterNetEvent('bs:fighting:sparProgress', function(hits, need)
    if hits % 2 == 0 or hits == need - 1 then
        TriggerEvent('bs:ui:notify', { type = 'info', message = L('spar.progress', { n = hits, need = need }), duration = 1500 })
    end
end)

RegisterNetEvent('bs:fighting:sparResult', function(won, styleId)
    endSpar()
    TriggerEvent('bs:ui:notify', { type = won and 'success' or 'warn',
        message = won and L('spar.won', { style = L('style.' .. tostring(styleId)) }) or L('spar.lost'), duration = 5000 })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    endSpar()
    for id in pairs(FightTrainers.peds) do despawn(id) end
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
