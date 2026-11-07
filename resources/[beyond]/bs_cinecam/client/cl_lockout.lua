-- bs_cinecam - lockout and HUD hide.
-- LOCKOUT: block the player's keys while the camera flies (a key opening the inventory or firing would ruin the take).
-- HUD HIDE: follows the camera menu setting while filming.
-- They share the clean-screen question but neither turns the other on.

CineLock = { locked = false, hud = false, selfPanic = false }

-- HUD

-- The bs_ui HUD is hidden through events, not an export: bs_ui hides its HUD for panels in UI.HideHudFor on bs:ui:opened/closed <name>, and already handles death, character switch, panic and resource stop. Needs `cinecam = 'bs_cinecam'` in bs_ui/config/config_ui.lua; if missing the HUD just stays visible.
local function frameworkHud(show)
    if show then
        TriggerEvent('bs:ui:closed', 'cinecam')
    else
        TriggerEvent('bs:ui:opened', 'cinecam')
    end
end

local function chatVisibility(show)
    if GetResourceState('bs_chat') ~= 'started' then return end
    -- /chat is bs_chat's own command; ExecuteCommand runs it client-side here, no export needed.
    ExecuteCommand(show and 'chat fade' or 'chat hidden')
end

-- Vanilla HUD and radar. Runs every frame: HideHudAndRadar is a this-frame native and the engine re-enables things constantly.
CreateThread(function()
    while true do
        if CineLock.hud then
            Wait(0)
            HideHudAndRadarThisFrame()
        else
            Wait(200)
        end
    end
end)

function CineLock.SetHud(hidden)
    if CineLock.hud == hidden then return CineLock.hud end
    CineLock.hud = hidden

    frameworkHud(not hidden)
    chatVisibility(not hidden)

    -- bs_ui owns the radar; ask it instead of fighting it with DisplayRadar every frame.
    if GetResourceState('bs_ui') == 'started' then
        pcall(function() exports.bs_ui:SetMinimap(not hidden) end)
    end

    return CineLock.hud
end

-- Input lockout

-- Controls the camera itself uses stay enabled (re-enabled after the blanket disable). Read with IsDisabledControlPressed, since a disabled control reads as not pressed through IsControlPressed.
CineLock.CameraControls = {
    32, 33, 34, 35,     -- W A S D
    22,                 -- SPACE       up
    36,                 -- LCTRL       down / slow
    21,                 -- LSHIFT      fast
    1, 2,               -- mouse look
    14, 15,             -- mouse wheel (FOV)
    44, 38,             -- Q / E       roll
    47,                 -- G          drop a keyframe
    246,                -- Y          play the path
    -- 1-9 stay disabled as gameplay controls; cl_camera reads them raw.
    157, 158, 159, 160, 161, 162, 163, 164, 165
}

-- DisableAllControlActions(0) covers gameplay controls and every RegisterKeyMapping binding. Groups 1 and 2 are disabled too (vehicle and mounted-weapon controls) so a driver has no live throttle. F8 and the pause menu are client-level and cannot be blocked. If a menu still opens under lockout, it is not opening on a control and needs an explicit gate.
CreateThread(function()
    while true do
        if CineLock.locked then
            Wait(0)

            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)

            for _, control in ipairs(CineLock.CameraControls) do
                EnableControlAction(0, control, true)
            end
        else
            Wait(200)
        end
    end
end)

function CineLock.SetLocked(locked)
    CineLock.locked = locked

    -- Cinecam only owns its own menu. Do not broadcast bs:ui:panic here: it force-closes unrelated panels and can desync their state.
    return CineLock.locked
end

-- Commands

-- Always answers: a silent return looks like a missing command or dead resource.
local function say(text)
    TriggerEvent('chat:addMessage', { args = { '^5[cine]', text } })
end


-- A HUD hidden forever is worse than an overlapping one. Every exit, including ungraceful ones, restores it.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CineLock.SetHud(false)
    CineLock.locked = false
end)

AddEventHandler('bs:hook:player:unloaded', function()
    CineLock.SetHud(false)
    CineLock.locked = false
end)
