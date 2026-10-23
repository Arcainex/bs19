--[[ bs_config client: F1 console + local copy of the active overrides. ]]

local payload = nil
local isOpen = false
local pending, seq = {}, 0

RegisterNetEvent('bs_config:apply', function(p)
    if type(p) == 'table' then payload = p end
end)

exports('GetPayload', function() return payload end)
exports('Get', function(path, default)
    if not payload then return default end
    local res, p = tostring(path):match('^([^:]+):(.+)$')
    local v
    if res then v = payload[res] and payload[res][p] else v = payload._global and payload._global[path] end
    if v == nil then return default end
    return v
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('bs_config:hello')
end)

--------------------------------------------------------------------------------
-- RPC to the server

RegisterNetEvent('bs_config:rpc:res', function(id, res)
    local p = pending[id]
    if p then pending[id] = nil; p:resolve(res) end
end)

local function rpc(action, a, b, c)
    seq = seq + 1
    local id = seq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('bs_config:rpc', id, action, a, b, c)
    SetTimeout(10000, function()
        if pending[id] then pending[id] = nil; p:resolve({ ok = false, error = L('cfg.e.noanswer') }) end
    end)
    return Citizen.Await(p)
end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

--------------------------------------------------------------------------------
-- Open / close

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('bs:ui:closed', 'config')
end

local function open()
    if isOpen then return close() end
    local data = rpc('open')
    if not data or data.ok == false then
        if data and not data.denied then notify('~r~' .. L('cfg.e.prefix') .. ': ~s~' .. tostring(data.error)) end
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
    TriggerEvent('bs:ui:opened', 'config')
end

RegisterCommand('+bsconfig', function() open() end, false)
RegisterCommand('-bsconfig', function() end, false)
RegisterKeyMapping('+bsconfig', 'Server config console (admin)', 'keyboard', BSConfig.Settings.key or 'F1')

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)

-- generic bridge: the page names the action, the server checks the rights
RegisterNUICallback('rpc', function(d, cb)
    if type(d) ~= 'table' or type(d.action) ~= 'string' then return cb({ ok = false }) end
    cb(rpc(d.action, d.a, d.b, d.c) or { ok = false })
end)

-- another UI took over: step aside cleanly
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'config' and isOpen then close() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
        TriggerEvent('bs:ui:closed', 'config')
    end
end)
