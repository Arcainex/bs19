-- bs_medical - moving the wounded.
-- Anyone can drag a downed survivor (slow, backwards). Carrying needs the Fireman carry perk (bs_skills Survival tree): L1 slow shuffle (move rate ~0.6), L2 normal walk, L3 can jog.
-- The server validates downed state, distance and perk (medical:carryStart) and tells the victim's client to attach; each client only moves its own ped. Drop with the same key, or on ragdoll, death, vehicle or the victim getting up. Bleedout while carried uses Medical.Carry.bleedoutRate.

local C = Medical.Carry or {}
local Carry = nil     -- carrier side: { target = serverId, mode, level, since }
local Victim = nil    -- victim side:  { carrier = serverId, mode }

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 3000 do Wait(10) waited = waited + 10 end
    return HasAnimDictLoaded(dict)
end

local function loadClipset(set)
    if not set then return false end
    RequestAnimSet(set)
    local waited = 0
    while not HasAnimSetLoaded(set) and waited < 3000 do Wait(10) waited = waited + 10 end
    return HasAnimSetLoaded(set)
end

local function serverIdOf(ped)
    if not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return nil end
    local idx = NetworkGetPlayerIndexFromPed(ped)
    if not idx or idx == -1 then return nil end
    local id = GetPlayerServerId(idx)
    return id > 0 and id or nil
end

local function isDownedId(id)
    local st = id and Player(id).state
    return st and st.bsDowned == true
end

local function hint(text)
    SetTextFont(4)
    SetTextScale(0.0, 0.34)
    SetTextColour(216, 210, 194, 220)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.5, 0.88)
end

--------------------------------------------------------------------------------
-- Carrier side
--------------------------------------------------------------------------------

local function cleanupCarrier()
    if not Carry then return end
    local ped = PlayerPedId()
    local cfg = C[Carry.mode] or {}
    if cfg.carrier then StopAnimTask(ped, cfg.carrier.dict, cfg.carrier.clip, 2.0) end
    ResetPedMovementClipset(ped, 0.5)
    SetPedMoveRateOverride(ped, 1.0)
    Carry = nil
end

local function stopCarrying(reason)
    if not Carry then return end
    cleanupCarrier()
    if reason then notify('info', reason, 3000) end
    CreateThread(function() BSB.Await('medical:carryStop', 5000) end)
end

local function startCarrying(targetPed, mode)
    if Carry or Victim then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local target = serverIdOf(targetPed)
    if not target or not isDownedId(target) then return end

    local r = BSB.Await('medical:carryStart', 6000, target, mode)
    if not (r and r.ok) then
        return notify('warn', (r and r.error) or L('med.you_cannot_move_them'), 4000)
    end

    local cfg = C[mode]
    Carry = { target = target, mode = mode, level = r.level or 0, since = GetGameTimer() }

    local ped = PlayerPedId()
    if loadDict(cfg.carrier.dict) then
        TaskPlayAnim(ped, cfg.carrier.dict, cfg.carrier.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
    if mode == 'carry' then
        local lv = cfg.levels[Carry.level] or cfg.levels[1]
        if lv.tired and loadClipset(cfg.tiredClipset) then
            SetPedMovementClipset(ped, cfg.tiredClipset, 0.5)
        end
    end
    notify('info', mode == 'carry' and L('med.you_hoisted_them_over_your_shoulder') or L('med.you_grab_them_under_the_arms'), 3000)
end

CreateThread(function()
    while true do
        if Carry then
            Wait(0)
            local ped = PlayerPedId()
            local cfg = C[Carry.mode]

            DisableControlAction(0, 24, true)    -- attack
            DisableControlAction(0, 25, true)    -- aim
            DisableControlAction(0, 22, true)    -- jump
            DisableControlAction(0, 23, true)    -- enter vehicle
            DisableControlAction(0, 44, true)    -- cover
            DisableControlAction(0, 37, true)    -- weapon wheel
            DisablePlayerFiring(PlayerId(), true)

            local rate, jog = cfg.moveRate or 1.0, false
            if Carry.mode == 'carry' then
                local lv = cfg.levels[Carry.level] or cfg.levels[1]
                rate, jog = lv.moveRate or 1.0, lv.jog
            end
            if not jog then DisableControlAction(0, 21, true) end    -- sprint
            SetPedMoveRateOverride(ped, rate)

            if not IsEntityPlayingAnim(ped, cfg.carrier.dict, cfg.carrier.clip, 3) and HasAnimDictLoaded(cfg.carrier.dict) then
                TaskPlayAnim(ped, cfg.carrier.dict, cfg.carrier.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end

            hint(L('med.put_down', { key = C.dropLabel or 'E' }))

            local key = C.dropControl or 38
            if GetGameTimer() - Carry.since > 800
               and (IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key)) then
                stopCarrying()
            elseif IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
                stopCarrying(L('med.you_lost_your_grip'))
            elseif exports.bs_medical:IsDowned() then
                stopCarrying()
            elseif not isDownedId(Carry.target) then
                stopCarrying()
            end
        else
            Wait(250)
        end
    end
end)

--------------------------------------------------------------------------------
-- Victim side
--------------------------------------------------------------------------------

local function cleanupVictim()
    if not Victim then return end
    local ped = PlayerPedId()
    local cfg = C[Victim.mode] or {}
    DetachEntity(ped, true, false)
    if cfg.victim then StopAnimTask(ped, cfg.victim.dict, cfg.victim.clip, 2.0) end
    SetPedCanRagdoll(ped, true)
    Victim = nil
    Medical.BeingCarried = false
    -- Still down: put the writhe pose straight back (the downed loop would
    -- within a frame anyway, this just avoids a T-pose flash). If we were
    -- revived, leaveDowned/standUp owns the ped and this is skipped.
    if exports.bs_medical:IsDowned() then
        ClearPedTasksImmediately(ped)
        local a = Medical.Anims.downed
        if loadDict(a.dict) then
            TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        end
    end
end

RegisterNetEvent('bs:medical:carry:victim', function(carrier, mode)
    if not C[mode] then return end
    if Victim then cleanupVictim() end
    Victim = { carrier = tonumber(carrier), mode = mode }
    Medical.BeingCarried = true

    CreateThread(function()
        local cfg = C[mode]
        local me = PlayerPedId()
        local idx = GetPlayerFromServerId(Victim.carrier)
        local waited = 0
        while (idx == -1 or not DoesEntityExist(GetPlayerPed(idx))) and waited < 3000 do
            Wait(100) waited = waited + 100
            idx = GetPlayerFromServerId(Victim.carrier)
        end
        if idx == -1 then
            cleanupVictim()
            BSB.Await('medical:carryStop', 5000)
            return
        end
        local carrierPed = GetPlayerPed(idx)
        local flag = cfg.victimFlag or 1
        -- Load BEFORE clearing: the downed writhe/ragdoll must be replaced by
        -- the drag/carry clip in the same frame, or the ped is attached in
        -- its stiff floor pose and floats sideways off the carrier's hip.
        loadDict(cfg.victim.dict)
        if not Victim then return end
        if IsPedRagdoll(me) then SetPedToRagdoll(me, 1, 1, 0, false, false, false) end
        SetPedCanRagdoll(me, false)
        ClearPedTasksImmediately(me)
        TaskPlayAnim(me, cfg.victim.dict, cfg.victim.clip, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        local o, r = cfg.offset, cfg.rot
        AttachEntityToEntity(me, carrierPed, GetPedBoneIndex(carrierPed, cfg.bone or 0),
            o[1], o[2], o[3], r[1], r[2], r[3], false, false, false, false, 2, false)

        while Victim and Victim.mode == mode do
            Wait(0)
            me = PlayerPedId()
            if HasAnimDictLoaded(cfg.victim.dict)
               and not IsEntityPlayingAnim(me, cfg.victim.dict, cfg.victim.clip, 3) then
                TaskPlayAnim(me, cfg.victim.dict, cfg.victim.clip, 8.0, -8.0, -1, flag, 0.0, false, false, false)
            end
            if not DoesEntityExist(carrierPed) or not IsEntityAttachedToEntity(me, carrierPed) then
                cleanupVictim()
                BSB.Await('medical:carryStop', 5000)
                break
            end
        end
    end)
end)

RegisterNetEvent('bs:medical:carry:stop', function()
    cleanupCarrier()
    cleanupVictim()
end)

AddEventHandler('bs:hook:player:unloaded', function() cleanupCarrier() cleanupVictim() end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then cleanupCarrier() cleanupVictim() end
end)

--------------------------------------------------------------------------------
-- The dot
--------------------------------------------------------------------------------

CreateThread(function()
    if not C.enabled then return end
    while GetResourceState('bs_interactions') ~= 'started' do Wait(1000) end

    local filters = {
        playerPed      = true,
        stateFalse     = 'bsZombie',
        ownerStateTrue = 'bsDowned',
        maxDistance    = C.distance or 2.0,
    }
    exports.bs_interactions:AddType('ped', {
        { label = L('med.drag'), labelKey = 'med.drag',  icon = 'hand', distance = C.distance or 2.0,
          event = 'bs:medical:dot:drag',  filters = filters },
        { label = L('med.carry'), labelKey = 'med.carry', icon = 'hand', distance = C.distance or 2.0,
          event = 'bs:medical:dot:carry', filters = filters },
    })
end)

AddEventHandler('bs:medical:dot:drag', function(payload)
    if payload and payload.entity then CreateThread(function() startCarrying(payload.entity, 'drag') end) end
end)
AddEventHandler('bs:medical:dot:carry', function(payload)
    if payload and payload.entity then CreateThread(function() startCarrying(payload.entity, 'carry') end) end
end)

exports('IsCarrying', function() return Carry ~= nil end)
