-- BeyondSurvival: gameplay mouse/NUI focus cleanup
-- Prevents a stale NUI/menu cursor from remaining active after UI hand-offs.
-- Important: do not run a permanent SetNuiFocus(false,false) loop; that would
-- break bs_multichar and other legitimate NUI screens.

local uiDepth = 0

AddEventHandler('bs:ui:opened', function()
    uiDepth = uiDepth + 1
end)

AddEventHandler('bs:ui:closed', function()
    uiDepth = math.max(0, uiDepth - 1)

    CreateThread(function()
        Wait(100)
        if uiDepth == 0 and not IsPauseMenuActive() then
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            SetMouseCursorVisibleInMenus(false)
        end
    end)
end)

local function releaseGameplayCursor()
    if uiDepth ~= 0 or IsPauseMenuActive() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SetMouseCursorVisibleInMenus(false)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        releaseGameplayCursor()
    end)
end)

AddEventHandler('playerSpawned', function()
    CreateThread(function()
        Wait(1000)
        releaseGameplayCursor()
    end)
end)

-- Safety cleanup when returning from the native pause/frontend state.
CreateThread(function()
    local wasPaused = false
    while true do
        local paused = IsPauseMenuActive()
        if wasPaused and not paused then
            Wait(100)
            releaseGameplayCursor()
        end
        wasPaused = paused
        Wait(250)
    end
end)
