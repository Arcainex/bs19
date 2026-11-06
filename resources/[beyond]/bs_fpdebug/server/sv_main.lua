-- bs_fpdebug - server. The admin check lives here; the commands it runs re-check staff rights themselves.

local function isAdmin(src)
    if GetResourceState('bs_admin') ~= 'started' then return IsPlayerAceAllowed(src, 'bs.admin') end
    local ok, r = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return ok and r == true
end

RegisterNetEvent('bs:fpdebug:request', function()
    local src = source
    if not isAdmin(src) then return end
    TriggerClientEvent('bs:fpdebug:open', src)
end)

local ALLOW = { fightlearn = true, fightforget = true, fightreset = true, parkourperk = true, parkourlevel = true }
RegisterNetEvent('bs:fpdebug:run', function(cmd, a)
    local src = source
    if not isAdmin(src) or not ALLOW[cmd] then return end
    a = tostring(a or ''):gsub('[^%w_]', '')
    local line
    if cmd == 'fightlearn' or cmd == 'fightforget' then line = ('%s %s %d'):format(cmd, a, src)
    elseif cmd == 'fightreset' then line = ('fightreset %d'):format(src)
    else line = ('%s %d %s'):format(cmd, src, a) end
    ExecuteCommand(line)
end)
