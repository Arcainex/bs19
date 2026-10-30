local function safeExport(name, ...)
    local resource = GetCurrentResourceName()
    local args = {...}
    local ok, result = pcall(function()
        return exports[resource][name](table.unpack(args))
    end)
    if ok then return tostring(result) end
    return 'ERROR: ' .. tostring(result)
end

RegisterCommand('yacadebug', function()
    print('^2========== YaCA DEBUG ==========^7')
    print(('Resource: %s | state: %s'):format(GetCurrentResourceName(), GetResourceState(GetCurrentResourceName())))
    print('Plugin State: ' .. safeExport('getPluginState'))
    print('TeamSpeak UID: ' .. safeExport('getTeamSpeakUniqueIdentifier'))
    print('YaCA enabled: ' .. safeExport('isEnabled'))
    print('Voice range: ' .. safeExport('getVoiceRange'))
    print('Global error level: ' .. safeExport('getGlobalErrorLevel'))
    print('Configured TS server UUID: 0nC2x7QV8p11IALDw0xH81vW22g=')
    print('Configured ingame channel: 4')
    print('Configured default channel: 1')
    print('^2================================^7')
end, false)

CreateThread(function()
    Wait(5000)
    print('^3[YaCA Debug]^7 /yacadebug ist geladen.')
end)
