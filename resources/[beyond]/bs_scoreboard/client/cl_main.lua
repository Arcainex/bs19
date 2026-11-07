-- BeyondSurvival - bs_scoreboard client. F9 is held, not toggled: it can never stay on screen. The page is display-only and takes no NUI focus, so it cannot trap the player.

local shown = false
local fetching = false
local lastFetch = 0

local function send(payload)
    if payload.data then payload.data.self = GetPlayerServerId(PlayerId()) end
    SendNUIMessage(payload)
end


local function show()
    if shown or fetching then return end
    if not exports.bs_core:IsLoaded() then return end

    -- Cheap re-show: no need to ask the server again for a board shown a second ago.
    fetching = true
    local data = BSB.Await('scoreboard:get', 6000)
    fetching = false

    if not data or not data.ok then return end
    lastFetch = GetGameTimer()

    shown = true
    TriggerScreenblurFadeIn(150)
    send({ action = 'open', data = data })
end

local function hide()
    if not shown then return end
    shown = false
    TriggerScreenblurFadeOut(150)
    send({ action = 'close' })
end

-- The key. RegisterKeyMapping gives the press; the release has to be watched in the thread below, since a command only fires on the way down.

local wanted = false

RegisterCommand('+' .. Scoreboard.Settings.command, function()
    wanted = true
    if Scoreboard.Settings.hold then
        CreateThread(show)
    else
        CreateThread(function() if shown then hide() else show() end end)
    end
end, false)

RegisterCommand('-' .. Scoreboard.Settings.command, function()
    wanted = false
    if Scoreboard.Settings.hold then hide() end
end, false)

RegisterKeyMapping('+' .. Scoreboard.Settings.command, 'Scoreboard',
    'keyboard', Scoreboard.Settings.key)

-- Safety net: a +command/-command pair loses its release if the window loses focus (alt-tab with F9 held). This notices the key is no longer down and closes the board.
CreateThread(function()
    while true do
        Wait(250)

        if shown and Scoreboard.Settings.hold and not wanted then
            hide()
        end

        -- Dying with it up, or unloading, closes it too.
        if shown and IsPedDeadOrDying(PlayerPedId(), true) then hide() end
    end
end)

-- Refresh while held so joining players appear.
CreateThread(function()
    while true do
        Wait(3000)

        if shown and GetGameTimer() - lastFetch > 4000 then
            local data = BSB.Await('scoreboard:get', 6000)
            if data and data.ok and shown then
                lastFetch = GetGameTimer()
                send({ action = 'update', data = data })
            end
        end
    end
end)

AddEventHandler('bs:hook:player:unloaded', hide)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then hide() end
end)

exports('IsOpen', function() return shown end)
