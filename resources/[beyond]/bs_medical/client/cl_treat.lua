-- bs_medical - reviving downed players.
-- Hold the interaction dot on a downed player to treat wounds. Takes 12
-- seconds, costs a medkit, fails if either player moves. The Field medic perk
-- shortens it. The server checks distance, medkit and downed state.

local S = Medical.Settings
local treating = false

-- Who is down

-- Downed state is a state bag on the player, readable by any client.
local function isDownedPed(ped)
    if not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return false end

    -- Walkers are peds too; do not offer to bandage them.
    local state = Entity(ped).state
    if state and state.bsZombie then return false end

    local playerId = NetworkGetPlayerIndexFromPed(ped)
    if not playerId or playerId == -1 then return false end

    local serverId = GetPlayerServerId(playerId)
    if serverId <= 0 then return false end

    local state = Player(serverId).state
    return state and state.bsDowned == true
end

-- Down or on the death screen (not respawned), read from the state bag.
local function isRevivablePed(ped)
    if isDownedPed(ped) then return true end
    if not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return false end
    local playerId = NetworkGetPlayerIndexFromPed(ped)
    if not playerId or playerId == -1 then return false end
    local serverId = GetPlayerServerId(playerId)
    if serverId <= 0 then return false end
    local state = Player(serverId).state
    return state and (state.bsRevivable == true or state.bsDead == true)
end

local function reviveDuration()
    local time = S.reviveTime
    if GetResourceState('bs_skills') == 'started' then
        local ok, has = pcall(function() return exports.bs_skills:HasPerk('field_medic') end)
        if ok and has then time = math.floor(time * 0.7) end
    end
    return time
end

-- The revive itself

-- The busy flag covers the whole attempt, including network round trips, and is
-- cleared on every exit. Otherwise a second press re-runs the function, or an
-- error leaves it latched and revive silently does nothing.
local function runRevive(targetPed)
    if treating then return end
    treating = true

    local me = PlayerPedId()
    local playerId = NetworkGetPlayerIndexFromPed(targetPed)
    local serverId = GetPlayerServerId(playerId)

    -- Check for a medkit before kneeling down.
    local check = BSB.Await('medical:reviveCheck', 6000, serverId)
    if not check or not check.ok then
        treating = false
        return TriggerEvent('bs:ui:notify', {
            type = 'warn', message = (check and check.error) or L('med.you_cannot_help_them'),
        })
    end

    local duration = reviveDuration()

    -- bs_interactions owns the progress bar so the server has only one.
    local anim = Medical.Anims.reviving
    if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) end
    local waited = 0
    while not HasAnimDictLoaded(anim.dict) and waited < 2000 do Wait(10); waited = waited + 10 end
    if HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(me, anim.dict, anim.clip, 3.0, 3.0, duration, 1, 0.0, false, false, false)
    end

    -- pcall'd because the bar lives in another resource; a raise here would leave
    -- `treating` latched (see above).
    local completed = true
    if GetResourceState('bs_interactions') == 'started' then
        local ok, result = pcall(function()
            -- pose = 'none': this file plays Medical.Anims.reviving itself.
            return exports.bs_interactions:RunSearch(L('med.treating_wounds'), duration,
                { pose = 'none' })
        end)
        completed = ok and result and true or false
    else
        Wait(duration)
    end

    ClearPedTasks(me)

    if not completed then
        treating = false
        return TriggerEvent('bs:ui:notify', { type = 'warn', message = L('med.stopped') })
    end

    -- Still in reach? The server checks too; this gives a clear message.
    if not DoesEntityExist(targetPed)
       or #(GetEntityCoords(me) - GetEntityCoords(targetPed)) > (S.reviveDistance + 1.0) then
        treating = false
        return TriggerEvent('bs:ui:notify', { type = 'warn', message = L('med.not_there') })
    end

    local result = BSB.Await('medical:revive', 8000, serverId)
    treating = false

    TriggerEvent('bs:ui:notify', {
        type = (result and result.ok) and 'success' or 'warn',
        message = (result and result.ok) and L('med.they_are_breathing')
            or ((result and result.error) or L('med.it_did_not_take')),
    })
end

-- A bandage on someone else buys time. Shares the busy flag with the revive so
-- only one action runs at a time.
local function runStabilise(targetPed)
    if treating then return end
    treating = true

    local playerId = NetworkGetPlayerIndexFromPed(targetPed)
    local serverId = GetPlayerServerId(playerId)

    local result = BSB.Await('medical:stabiliseOther', 8000, serverId)
    treating = false

    TriggerEvent('bs:ui:notify', {
        type = (result and result.ok) and 'success' or 'warn',
        message = (result and result.ok) and L('med.packed_the_wound_they_have_longer_no')
            or ((result and result.error) or L('med.you_have_nothing_to_pack_it_with')),
    })
end

-- Registration with the dot

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(1000) end

    -- Data, not closures: functions do not survive being passed to another
    -- resource. The condition is a filter table (a player ped, not a walker, with
    -- bsDowned set) and the action is an event name handled below.
    local filters = {
        playerPed      = true,
        stateFalse     = 'bsZombie',
        ownerStateTrue = 'bsDowned',
        maxDistance    = S.reviveDistance,
    }
    local reviveFilters = {
        playerPed      = true,
        stateFalse     = 'bsZombie',
        ownerStateTrue = 'bsRevivable',
        maxDistance    = S.reviveDistance,
    }

    exports.bs_interactions:AddType('ped', {
        {
            label    = L('med.treat_wounds'),
            labelKey = 'med.treat_wounds',
            icon     = 'medical',
            distance = S.reviveDistance,
            event    = 'bs:medical:dot:revive',
            filters  = reviveFilters,
        },
        {
            label    = L('med.pack_the_wound'),
            labelKey = 'med.pack_the_wound',
            icon     = 'medical',
            distance = S.reviveDistance,
            event    = 'bs:medical:dot:stabilise',
            filters  = filters,
        },
    })

    print('^2[BeyondSurvival]^7 (medical) treatment registered on the dot')
end)

-- The flag is per body, not per session: death, unload or resource restart end
-- an attempt without its code finishing.
AddEventHandler('bs:hook:player:unloaded', function() treating = false end)

AddEventHandler('bs:medical:dot:revive', function(payload)
    if not payload or not payload.entity then return end
    -- Checked again here: a player can go from down to dead before E is pressed.
    if not isRevivablePed(payload.entity) then return end
    CreateThread(function() runRevive(payload.entity) end)
end)

AddEventHandler('bs:medical:dot:stabilise', function(payload)
    if not payload or not payload.entity then return end
    if not isDownedPed(payload.entity) then return end
    CreateThread(function() runStabilise(payload.entity) end)
end)
