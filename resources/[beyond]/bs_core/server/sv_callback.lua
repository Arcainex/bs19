-- Request/response over network events, both directions.

BS.Callbacks = {}
local handlers = {}
local pending  = {}
local sequence = 0

--- Registers a server callback a client can request.
--- fn(source, ...) -> any (return values are sent back)
function BS.Callbacks.Register(name, fn)
    BS.Assert(type(name) == 'string', 'callback name must be a string')
    BS.Assert(type(fn) == 'function', 'callback handler must be a function')
    if handlers[name] then
        BS.Log.warn('callback', ('overwriting server callback "%s"'):format(name))
    end
    handlers[name] = fn
end

RegisterNetEvent(BS.Events.CallbackRequest, function(name, token, ...)
    local src = source
    local handler = handlers[name]
    -- Stay silent: this event reaches every resource that includes sh_bridge.lua and only the owner of the name may answer.
    if not handler then return end
    local args = table.pack(...)
    CreateThread(function()
        local results = table.pack(pcall(handler, src, table.unpack(args, 1, args.n)))
        if not results[1] then
            BS.Log.error('callback', ('"%s" errored: %s'):format(name, tostring(results[2])))
            return TriggerClientEvent(BS.Events.CallbackResponse, src, token, nil)
        end
        TriggerClientEvent(BS.Events.CallbackResponse, src, token, table.unpack(results, 2, results.n))
    end)
end)

--- Calls a client callback and yields until it answers (or times out).
function BS.Callbacks.Await(target, name, timeoutMs, ...)
    sequence = sequence + 1
    local token = ('s%d'):format(sequence)
    local done, response = false, nil

    pending[token] = function(...)
        response = table.pack(...)
        done = true
    end

    TriggerClientEvent(BS.Events.CallbackClientReq, target, name, token, ...)

    local waited = 0
    timeoutMs = timeoutMs or 10000
    while not done and waited < timeoutMs do
        Wait(10)
        waited = waited + 10
    end
    pending[token] = nil

    if not done then
        BS.Log.warn('callback', ('client callback "%s" timed out for %s'):format(name, target))
        return nil
    end
    return table.unpack(response, 1, response.n)
end

RegisterNetEvent(BS.Events.CallbackClientRes, function(token, ...)
    local resolve = pending[token]
    if resolve then resolve(...) end
end)

exports('RegisterCallback', BS.Callbacks.Register)
exports('AwaitClientCallback', BS.Callbacks.Await)
