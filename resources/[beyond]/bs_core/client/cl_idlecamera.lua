-- BeyondSurvival: disable GTA V idle/cinematic camera
-- Prevents the automatic camera movement after player inactivity.

CreateThread(function()
    while true do
        -- Reset both idle camera timers continuously.
        InvalidateIdleCam()
        InvalidateVehicleIdleCam()

        -- Once per second is enough to keep GTA's idle camera from activating.
        Wait(1000)
    end
end)
