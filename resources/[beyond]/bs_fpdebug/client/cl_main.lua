-- bs_fpdebug - client. /fightparkdebug opens the menu; the server only opens it for admins.

local open, granted = false, false

local function send(d) SendNUIMessage(d) end

local function closeMenu()
    if not open then return end
    open, granted = false, false
    send({ action = 'close' })
    SetNuiFocus(false, false)
end

local function collect()
    local data = { fight = { styles = {}, weapon = {}, failed = {} }, park = { kinds = {}, failed = {} } }
    if GetResourceState('bs_fighting') == 'started' then
        local ok, r = pcall(function() return exports.bs_fighting:DebugData() end)
        if ok and r then data.fight = r end
    end
    if GetResourceState('bs_parkour') == 'started' then
        local ok, r = pcall(function() return exports.bs_parkour:DebugData() end)
        if ok and r then data.park = r end
    end
    return data
end

RegisterNetEvent('bs:fpdebug:open', function()
    if open then return closeMenu() end
    CreateThread(function()
        local d = collect()
        open, granted = true, true
        send({ action = 'open', data = d })
        SetNuiFocus(true, true)
    end)
end)

RegisterCommand('fightparkdebug', function()
    if open then closeMenu() else TriggerServerEvent('bs:fpdebug:request') end
end, false)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)

RegisterNUICallback('do', function(d, cb)
    if not granted or type(d) ~= 'table' then return cb({ ok = false }) end
    local n = d.name
    if n == 'cmd' then
        TriggerServerEvent('bs:fpdebug:run', d.cmd, d.a)
    elseif n == 'style' then
        ExecuteCommand('fightstyle ' .. tostring(d.id or ''):gsub('[^%w_]', ''))
    elseif n == 'fight' then
        local ok, r = pcall(function() return exports.bs_fighting:DebugPlay(tostring(d.id)) end)
        return cb({ ok = ok and r == true })
    elseif n == 'park' then
        local ok, r = pcall(function() return exports.bs_parkour:DebugPlay(tostring(d.id)) end)
        return cb({ ok = ok and r == true })
    end
    cb({ ok = true })
end)
