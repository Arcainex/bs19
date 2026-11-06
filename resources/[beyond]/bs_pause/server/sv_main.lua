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

-- Change Character: only for a loaded survivor who is not downed, one try every few seconds.
local switchCool = {}
BSB.RegisterCallback('pause:canSwitch', function(src)
    local now = GetGameTimer()
    if (switchCool[src] or 0) > now then return { ok = false, reason = 'p.change_char_busy' } end
    switchCool[src] = now + 5000
    if not exports.bs_core:GetPlayer(src) then return { ok = false, reason = 'p.change_char_busy' } end
    if GetResourceState('bs_medical') == 'started' then
        local ok, down = pcall(function() return exports.bs_medical:IsDowned(src) end)
        if ok and down then return { ok = false, reason = 'p.change_char_downed' } end
    end
    return { ok = true }
end)
AddEventHandler('playerDropped', function() switchCool[source] = nil end)
