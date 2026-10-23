-- BeyondSurvival - core admin/debug commands. Gameplay modules register their own.

-- Registers a command guarded by an ACE permission (nil ace = everyone).
-- Thin wrapper over BSB.RegisterCommand (shared/sh_bridge.lua) that resolves player and logs via BS.Log.
-- @param name string
-- @param ace string|nil
-- @param help string
-- @param args table
-- @param handler function(src, args, raw, player)
function BS.RegisterCommand(name, ace, help, args, handler)
    BSB.RegisterCommand(name, ace, help, args, function(src, rawArgs, raw)
        local player = src > 0 and BS.GetPlayer(src) or nil
        local ok, err = pcall(handler, src, rawArgs, raw, player)
        if not ok then BS.Log.error('command', ('/%s failed: %s'):format(name, err)) end
    end)
end

BS.RegisterCommand('bs', 'bs.admin', 'BeyondSurvival framework status', {}, function(src)
    local lines = {
        ('%s v%s'):format(BS.Name, BS.Version),
        ('ready: %s | players loaded: %d'):format(tostring(BS.Ready), BS.GetPlayerCount()),
        ('modules: %s'):format(table.concat(BS.Util.Keys(BS.Modules), ', ')),
    }
    for _, line in ipairs(lines) do
        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, { args = { '^5[BS]', line } })
        else
            print(line)
        end
    end
end)

BS.RegisterCommand('whoami', nil, 'Show your identifiers and permission tier', {}, function(src, _, _, player)
    if src <= 0 then return print('console has every permission') end
    local ids = BS.Identity.GetIdentifiers(src)
    local role = player and player:GetRole() or
        (IsPlayerAceAllowed(src, 'bs.superadmin') and 'superadmin'
         or IsPlayerAceAllowed(src, 'bs.admin') and 'admin' or 'player')
    local lines = {
        ('role: %s'):format(role),
        ('steam: %s'):format(ids.steam or 'not linked'),
        ('license: %s'):format(ids.license or '?'),
    }
    for _, line in ipairs(lines) do
        TriggerClientEvent('chat:addMessage', src, { args = { '^5[BS]', line } })
    end
end)

BS.RegisterCommand('logout', nil, 'Return to the character selection screen', {}, function(src)
    if src <= 0 then return end
    TriggerEvent(BS.Events.CharacterLogout)
    BS.UnloadPlayer(src, 'logout')
    TriggerClientEvent(BS.Events.SessionState, src, 'select')
end)

BS.RegisterCommand('savechar', 'bs.admin', 'Force-save your character', {}, function(src, _, _, player)
    if not player then return end
    player:Save(true)
    TriggerClientEvent(BS.Events.UiNotify, src, { type = 'success', message = Lp(src, 'char.saved') })
end)

BS.RegisterCommand('givexp', 'bs.admin', 'Grant XP to a player',
    { { name = 'id', help = 'server id' }, { name = 'amount', help = 'xp' } },
    function(src, args)
        local target = BS.GetPlayer(tonumber(args[1]))
        local amount = tonumber(args[2])
        if not target or not amount then return end
        target:AddXP(amount, 'admin')
    end)

-- /givemoney moved to bs_admin (server/sv_commands.lua): it takes "me", reports back and is logged.

BS.RegisterCommand('setneeds', 'bs.admin', 'Set your hunger and thirst',
    { { name = 'hunger', help = '0-100' }, { name = 'thirst', help = '0-100' } },
    function(src, args, _, player)
        if not player then return end
        player:SetNeeds(tonumber(args[1]) or 100, tonumber(args[2]) or 100)
    end)
