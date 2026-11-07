-- bs_pause server: the Server tab numbers and the Quit button.

local startedAt = os.time()

BSB.RegisterCallback('pause:info', function(src)
    return {
        online = #GetPlayers(),
        max    = GetConvarInt('sv_maxclients', 32),
        name   = GetConvar('sv_projectName', GetConvar('sv_hostname', 'BeyondSurvival')),
        uptime = os.time() - startedAt,
    }
end)

-- Leaving from the menu. playerDropped saves the character like any other disconnect.
RegisterNetEvent('bs:pause:quit', function()
    local src = source
    if GetPlayerName(src) then DropPlayer(src, 'Left from the pause menu. See you soon.') end
end)
