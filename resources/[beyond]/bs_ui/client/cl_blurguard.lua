-- bs_ui - blur guard: keeps the screen from staying blurred.

-- Grace period before treating a blur with no focus as a leak.
local GRACE_MS = 1500

-- There is no native to read the blur back, so the guard tracks whether any of our menus held focus since the last clear.
local sawFocus = false
local lostAt = nil

CreateThread(function()
    while true do
        Wait(250)

        if IsNuiFocused() then
            sawFocus = true
            lostAt = nil
        elseif sawFocus then
            local now = GetGameTimer()
            lostAt = lostAt or now

            if (now - lostAt) >= GRACE_MS then
                -- Focus was held, has been gone for the grace period, and nothing claimed it.
                pcall(TriggerScreenblurFadeOut, 0)
                sawFocus = false
                lostAt = nil
            end
        end
    end
end)

-- Case the watchdog misses: a resource that faded the blur in and then stopped, so its close handler never runs.
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        pcall(TriggerScreenblurFadeOut, 0)
        return
    end

    -- Any BeyondSurvival resource stopping is a reason to check.
    if resource:sub(1, 3) == 'bs_' then
        CreateThread(function()
            Wait(200)
            if not IsNuiFocused() then
                pcall(TriggerScreenblurFadeOut, 0)
                pcall(SetNuiFocus, false, false)
                sawFocus = false
            end
        end)
    end
end)

-- /unblur - manual escape hatch if the watchdog misses something. Clears focus too.
RegisterCommand('unblur', function()
    pcall(TriggerScreenblurFadeOut, 0)
    pcall(SetNuiFocus, false, false)
    sawFocus, lostAt = false, nil
    -- Ask every Beyond UI owner to release its own state too; clearing browser focus alone cannot release a camera or menu coroutine.
    TriggerEvent('bs:ui:panic')
    -- panic alone left bs_chat's open-panel list full, so T stayed dead
    TriggerEvent('bs:ui:closed', nil)

    TriggerEvent('bs:ui:notify', { type = 'info', duration = 2500,
        message = L('ui.blur_cleared') })
end, false)
