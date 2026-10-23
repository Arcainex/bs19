-- bs_emotes - sitting on existing benches and seats.
-- Uses the engine's seated scenarios (walk-in, sit, idle, get up) instead of
-- the sit emote that spawns a chair. The seat point is computed in the prop's
-- local space so it works at any angle.

Seats = { active = false }

-- What can be sat on

-- `scenario` is the pose. `depth` is how far in from the object's centre along
-- its local Y (negative = towards the front edge). `flip` faces away from the back rest.
local SEATS = {
    -- Park and street benches.
    { models = {
        'prop_bench_01a', 'prop_bench_01b', 'prop_bench_01c',
        'prop_bench_02', 'prop_bench_03', 'prop_bench_04',
        'prop_bench_05', 'prop_bench_06', 'prop_bench_07',
        'prop_bench_08', 'prop_bench_09', 'prop_bench_10',
        'prop_bench_11', 'prop_fib_3b_bench',
        'prop_ld_bench01',
      },
      label = L('emo.sit'), scenario = 'PROP_HUMAN_SEAT_BENCH',
      depth = -0.05, height = 0.5 },

    -- Bus stop seating.
    { models = { 'prop_busstop_02', 'prop_busstop_04', 'prop_busstop_05' },
      label = L('emo.sit_wait'), scenario = 'PROP_HUMAN_SEAT_BENCH',
      depth = -0.1, height = 0.5 },

    -- Chairs, indoors and out.
    { models = {
        'prop_chair_01a', 'prop_chair_01b', 'prop_chair_02', 'prop_chair_03',
        'prop_chair_04a', 'prop_chair_04b', 'prop_chair_05', 'prop_chair_06',
        'prop_chair_07', 'prop_chair_08', 'prop_chair_09', 'prop_chair_10',
        'prop_off_chair_01', 'prop_off_chair_03', 'prop_off_chair_04',
        'prop_off_chair_04b', 'prop_off_chair_05', 'prop_table_04_chr',
        'prop_table_05_chr', 'prop_table_06_chr', 'prop_wheelchair_01',
        'v_ilev_leath_chair', 'prop_direct_chair_01', 'prop_direct_chair_02',
      },
      label = L('emo.sit'), scenario = 'PROP_HUMAN_SEAT_CHAIR',
      depth = -0.02, height = 0.5 },

    -- Deck chairs and sun loungers (lying back).
    { models = { 'prop_sunlounger_01a', 'prop_beach_lounge_01' },
      label = L('emo.lie'), scenario = 'PROP_HUMAN_SEAT_SUNLOUNGER',
      depth = 0.0, height = 0.4 },

    -- Steps, kerbs and low walls.
    { models = { 'prop_bench_low_01', 'prop_ld_bench02' },
      label = L('emo.edge'), scenario = 'PROP_HUMAN_SEAT_STEPS',
      depth = 0.0, height = 0.4 },
}

-- Sitting

local function stand()
    if not Seats.active then return end
    Seats.active = false

    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
end

Seats.Stand = stand

--- @param entity number  the bench
--- @param seat table     the SEATS entry it matched
local function sit(entity, seat)
    if Seats.active then return stand() end
    if not DoesEntityExist(entity) then return end

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) or IsPedDeadOrDying(ped, true) then return end
    if Prone and Prone.active then
        return TriggerEvent('bs:ui:notify', {
            type = 'info', message = L('emo.get_up'), duration = 2200,
        })
    end

    -- Seat point in the bench's own space, so it works at any heading. Using the
    -- player's position would land on the arm rest when approaching from the side.
    local at = GetOffsetFromEntityInWorldCoords(entity,
        0.0, seat.depth or 0.0, seat.height or 0.5)

    -- A bench's back is at +Y in local space, so sitting faces -Y (heading + 180).
    local heading = (GetEntityHeading(entity) + 180.0) % 360.0

    ClearPedTasks(ped)
    TaskStartScenarioAtPosition(ped, seat.scenario or 'PROP_HUMAN_SEAT_BENCH',
        at.x, at.y, at.z, heading, 0, true, false)

    Seats.active = true

    TriggerEvent('bs:ui:notify', {
        type = 'info', message = L('emo.sitting'), duration = 2600,
    })
end

-- Getting up: any movement input, damage or death.

CreateThread(function()
    while true do
        if Seats.active then
            Wait(120)

            local ped = PlayerPedId()

            if IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
                stand()
            elseif IsControlPressed(0, 32) or IsControlPressed(0, 33)
                or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                or IsControlJustPressed(0, 22) then
                stand()
            end
        else
            Wait(400)
        end
    end
end)

RegisterCommand('standup2', function() stand() end, false)

AddEventHandler('bs:hook:player:unloaded', stand)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stand() end
end)

-- Dot options
-- Data only: closures do not survive an export boundary, so the condition is a
-- `filters` table that bs_interactions evaluates and the action is an event
-- name handled here. The matching SEATS entry is found from the model.

-- The SEATS entry for a model, or nil.
local function seatFor(entity)
    local model = BS.Util.ModelOf(entity)
    if not model then return nil end

    for _, seat in ipairs(SEATS) do
        for _, name in ipairs(seat.models) do
            if GetHashKey(name) == model then return seat end
        end
    end

    return nil
end

AddEventHandler('bs:emotes:dot:sit', function(payload)
    if not payload or not payload.entity then return end

    local seat = seatFor(payload.entity)
    if not seat then return end

    CreateThread(function() sit(payload.entity, seat) end)
end)

-- Sitting is kept on the player's state bag so the filter can hide the option
-- while already seated.
local function publish()
    LocalPlayer.state:set('bsSitting', Seats.active and true or false, false)
end

CreateThread(function()
    local waited = 0
    while GetResourceState('bs_interactions') ~= 'started' and waited < 20000 do
        Wait(500); waited = waited + 500
    end
    if GetResourceState('bs_interactions') ~= 'started' then
        return print('^3[BeyondSurvival]^7 (emotes) bs_interactions never started - no seating on the dot')
    end

    publish()

    for _, seat in ipairs(SEATS) do
        local ok, err = pcall(function()
            exports.bs_interactions:AddModel(seat.models, {
                {
                    label   = seat.label,
                    icon    = 'dot',
                    event   = 'bs:emotes:dot:sit',
                    filters = {
                        onFoot = true,
                        maxDistance = 2.6,
                        playerStateFalse = 'bsSitting',
                    },
                },
            })
        end)

        if not ok then
            print(('^1[BeyondSurvival]^7 (emotes) seating registration failed: %s'):format(tostring(err)))
            return
        end
    end

    print('^2[BeyondSurvival]^7 (emotes) seating registered on the dot')
end)

-- Clear the flag however sitting ended.
CreateThread(function()
    local last = nil
    while true do
        Wait(500)
        if Seats.active ~= last then
            last = Seats.active
            publish()
        end
    end
end)

exports('Sit', function(entity)
    local model = BS.Util.ModelOf(entity)
    if not model then return false end

    for _, seat in ipairs(SEATS) do
        for _, name in ipairs(seat.models) do
            if GetHashKey(name) == model then
                CreateThread(function() sit(entity, seat) end)
                return true
            end
        end
    end

    return false
end)

exports('IsSitting', function() return Seats.active end)
