-- Client half of the callback transport.

BS.Callbacks = {}
local pending  = {}
local handlers = {}
local sequence = 0

--- Calls a server callback and yields until it answers.
--- Usage: local data = BS.Callbacks.Await('characters:list')
function BS.Callbacks.Await(name, timeoutMs, ...)
    sequence = sequence + 1
    -- Resource-prefixed because the response event reaches every resource.
    local token = ('%s:%d'):format(GetCurrentResourceName(), sequence)
    local done, response = false, nil

    pending[token] = function(...)
        response = table.pack(...)
        done = true
    end

    TriggerServerEvent(BS.Events.CallbackRequest, name, token, ...)

    local waited = 0
    timeoutMs = timeoutMs or 10000
    while not done and waited < timeoutMs do
        Wait(5)
        waited = waited + 5
    end
    pending[token] = nil

    if not done then
        BS.Log.warn('callback', ('server callback "%s" timed out'):format(name))
        return nil
    end
    return table.unpack(response, 1, response.n)
end

RegisterNetEvent(BS.Events.CallbackResponse, function(token, ...)
    local resolve = pending[token]
    if resolve then resolve(...) end
end)

--- Registers a callback the server may invoke on this client.
function BS.Callbacks.Register(name, fn)
    handlers[name] = fn
end

RegisterNetEvent(BS.Events.CallbackClientReq, function(name, token, ...)
    local handler = handlers[name]
    if not handler then return end   -- another resource owns this name
    local results = table.pack(pcall(handler, ...))
    if not results[1] then
        BS.Log.error('callback', ('client callback "%s" errored: %s'):format(name, tostring(results[2])))
        return TriggerServerEvent(BS.Events.CallbackClientRes, token, nil)
    end
    TriggerServerEvent(BS.Events.CallbackClientRes, token, table.unpack(results, 2, results.n))
end)

exports('AwaitCallback', BS.Callbacks.Await)
exports('RegisterClientCallback', BS.Callbacks.Register)
