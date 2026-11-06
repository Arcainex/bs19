-- bs_emotes - finger pointing that follows the camera and lets you keep walking.

Point = { active = false }

-- When the move network first reported itself gone. A timestamp, since a single false frame is normal.
local deadSince = nil

local DICT = 'anim@mp_point'

local function loadDict()
    if HasAnimDictLoaded(DICT) then return true end
    if not HasAnimDictLoaded(DICT) then RequestAnimDict(DICT) end
    local waited = 0
    while not HasAnimDictLoaded(DICT) and waited < 3000 do Wait(10); waited = waited + 10 end
    return HasAnimDictLoaded(DICT)
end

local function canPoint()
    local ped = PlayerPedId()
    if not exports.bs_core:IsLoaded() then return false end
    if IsEntityDead(ped) then return false end
    if IsPedInAnyVehicle(ped, false) then return false end
    if Prone and Prone.active then return false end
    if Actions and Actions.handsUp then return false end
    return true
end

function Point.Stop()
    if not Point.active then return end
    Point.active = false

    local ped = PlayerPedId()
    RequestTaskMoveNetworkStateTransition(ped, 'Stop')
    ClearPedSecondaryTask(ped)
    if not IsPedInjured(ped) then SetPedCurrentWeaponVisible(ped, true, true, true, true) end
    SetPedConfigFlag(ped, 36, false)
    RemoveAnimDict(DICT)
end

-- Starts (or restarts) the move network. Split out because it must be re-issued whenever something clears the ped's tasks.
local function beginNetwork(ped)
    if not loadDict() then return false end

    SetPedCurrentWeaponVisible(ped, false, true, true, true)
    SetPedConfigFlag(ped, 36, true)          -- block weapon switching
    TaskMoveNetworkByName(ped, 'task_mp_pointing', 0.5, false, DICT, 24)

    -- Signals set before the network is live are dropped, so wait for it to come up or the arm stays at the default pose.
    local waited = 0
    while not IsTaskMoveNetworkActive(ped) and waited < 1000 do
        Wait(10); waited = waited + 10
    end

    return IsTaskMoveNetworkActive(ped)
end

function Point.Start()
    if Point.active or not canPoint() then return end

    local ped = PlayerPedId()
    if not beginNetwork(ped) then return end
    Point.active = true
end

-- In a thread: Start waits for the anim dict and the move network, and a command handler cannot yield.
RegisterCommand('bs_point', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    CreateThread(function()
        if Point.active then Point.Stop() else Point.Start() end
    end)
end, false)
RegisterKeyMapping('bs_point', L('emote.key_point'), 'keyboard', Emotes.Keys.point)

-- The signal feed. Without it the arm sits at a default angle.
CreateThread(function()
    while true do
        if Point.active then
            Wait(0)
            local ped = PlayerPedId()

            if not canPoint() then
                Point.Stop()
                goto continue
            end

            -- ClearPedTasks from other scripts kills the move network, so it is restarted.
            if not IsTaskMoveNetworkActive(ped) then
                deadSince = deadSince or GetGameTimer()

                if GetGameTimer() - deadSince > 350 then
                    deadSince = nil
                    if not beginNetwork(ped) then Point.Stop() end
                    goto continue
                end
            else
                deadSince = nil
            end

            -- Signals are normalised 0..1.

            local rawPitch = GetGameplayCamRelativePitch()
            rawPitch = math.max(-70.0, math.min(42.0, rawPitch))
            local pitch = (rawPitch + 70.0) / 112.0

            -- Clamped to a narrower window than the camera: at extreme headings (about +-180) the stock task_mp_pointing
            local rawHeading = GetGameplayCamRelativeHeading()
            rawHeading = math.max(-95.0, math.min(95.0, rawHeading))
            local heading = (rawHeading + 180.0) / 360.0

            -- Hand position in ped space, rotated by the camera heading: x = -0.2 cos - reach sin, y = -0.2 sin + reach cos.
            local rad = math.rad(rawHeading)
            local cos, sin = math.cos(rad), math.sin(rad)
            local reach = 0.3 + (0.4 * heading)

            local hand = GetOffsetFromEntityInWorldCoords(ped,
                (cos * -0.2) - (sin * reach),
                (sin * -0.2) + (cos * reach),
                0.6)

            local ray = StartShapeTestCapsule(hand.x, hand.y, hand.z - 0.2,
                hand.x, hand.y, hand.z + 0.2, 1.0, 95, ped, 7)
            local _, blocked = GetShapeTestResult(ray)

            -- Sent every frame, unconditionally: the frame a blend finishes decides the pose.
            SetTaskMoveNetworkSignalFloat(ped, 'Pitch', pitch)
            SetTaskMoveNetworkSignalFloat(ped, 'Heading', 1.0 - heading)
            SetTaskMoveNetworkSignalBool(ped, 'isBlocked', blocked == 1)
            SetTaskMoveNetworkSignalBool(ped, 'isFirstPerson',
                GetFollowPedCamViewMode() == 4)
        else
            Wait(250)
        end
        ::continue::
    end
end)

-- Debug command: prints the ped heading, camera heading
RegisterCommand('pointdebug', function()
    CreateThread(function()
        local ped = PlayerPedId()

        for _ = 1, 16 do
            local rawHeading = GetGameplayCamRelativeHeading()
            local clampedHeading = math.max(-95.0, math.min(95.0, rawHeading))
            local signal = (clampedHeading + 180.0) / 360.0

            local rawPitch = GetGameplayCamRelativePitch()
            local clampedPitch = math.max(-70.0, math.min(42.0, rawPitch))
            local pitchSignal = (clampedPitch + 70.0) / 112.0

            print(('^5[BS POINT]^7 active=%s network=%s  ped=%.1f  cam=%.1f  ' ..
                   'rel=%.1f  heading=%.3f  pitch=%.1f->%.3f')
                :format(tostring(Point.active),
                        tostring(IsTaskMoveNetworkActive(ped)),
                        GetEntityHeading(ped),
                        GetGameplayCamRot(2).z,
                        rawHeading,
                        signal,
                        rawPitch,
                        pitchSignal))

            Wait(250)
        end
    end)
end, false)

AddEventHandler('bs:hook:player:unloaded', Point.Stop)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Point.Stop() end
end)

exports('IsPointing', function() return Point.active end)
