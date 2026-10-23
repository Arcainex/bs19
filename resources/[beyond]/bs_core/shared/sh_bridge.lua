-- Cross-resource bridge. Other resources include this file in their manifest (shared_scripts { '@bs_core/shared/sh_bridge.lua' }) so handlers live in their own Lua state; functions cannot cross an export boundary.
-- Server: BSB.RegisterCallback('my:thing', function(src, a, b) return { ok = true } end)
-- Client: local result = BSB.Await('my:thing', 5000, a, b)
-- A request is broadcast, the owning resource answers and the rest stay silent, so an unknown name times out instead of erroring.

BSB = BSB or {}

local REQUEST  = 'bs:callback:request'
local RESPONSE = 'bs:callback:response'

-- Server asking one specific client:
-- Server: local result = BSB.AwaitClient(targetSrc, 'my:thing', 5000, a, b)
-- Client: BSB.RegisterClientCallback('my:thing', function(a, b) return { ok = true } end)
-- Uses the same event names as bs_core's own client callbacks (CallbackClientReq/CallbackClientRes), so nothing on the wire changed.
local CLIENT_REQUEST  = 'bs:callback:clientRequest'
local CLIENT_RESPONSE = 'bs:callback:clientResponse'

if IsDuplicityVersion() then
    -- server
    local handlers = {}

    -- fn(source, ...) -> any. Return values are sent back to the caller.
    function BSB.RegisterCallback(name, fn)
        if type(name) ~= 'string' or type(fn) ~= 'function' then
            return error('BSB.RegisterCallback(name:string, fn:function)', 2)
        end
        handlers[name] = fn
    end

    -- Rate limit on bs:callback:request, checked after the "is this ours" test so a flood aimed at one resource only throttles that resource's own handlers. Without it a client could spawn unbounded handler coroutines (often DB queries).
    local requestRate = {} -- [src] = { at = GetGameTimer() window start, n = count }
    local RATE_WINDOW_MS = 1000
    local RATE_MAX       = 40

    local function underRequestLimit(src)
        local now = GetGameTimer()
        local rec = requestRate[src]
        if not rec or (now - rec.at) >= RATE_WINDOW_MS then
            requestRate[src] = { at = now, n = 1 }
            return true
        end
        rec.n = rec.n + 1
        return rec.n <= RATE_MAX
    end

    RegisterNetEvent(REQUEST, function(name, token, ...)
        local handler = handlers[name]
        -- Not ours. Staying silent is deliberate: another resource owns it.
        if not handler then return end

        local src = source
        if not underRequestLimit(src) then return end

        local args = table.pack(...)

        CreateThread(function()
            local results = table.pack(pcall(handler, src, table.unpack(args, 1, args.n)))
            if not results[1] then
                print(('^1[BeyondSurvival]^7 callback "%s" errored: %s'):format(name, tostring(results[2])))
                return TriggerClientEvent(RESPONSE, src, token, nil)
            end
            TriggerClientEvent(RESPONSE, src, token, table.unpack(results, 2, results.n))
        end)
    end)

    AddEventHandler('playerDropped', function()
        requestRate[source] = nil
    end)

    local pendingClient   = {}
    local clientSequence  = 0

    -- Calls a callback registered on one specific client (BSB.RegisterClientCallback) and yields until it answers, or the timeout elapses (returns nil).
    function BSB.AwaitClient(target, name, timeoutMs, ...)
        clientSequence = clientSequence + 1
        local token = ('s%d'):format(clientSequence)
        local done, response = false, nil

        pendingClient[token] = function(...)
            response = table.pack(...)
            done = true
        end

        TriggerClientEvent(CLIENT_REQUEST, target, name, token, ...)

        local waited = 0
        timeoutMs = timeoutMs or 10000
        while not done and waited < timeoutMs do
            Wait(10)
            waited = waited + 10
        end
        pendingClient[token] = nil

        if not done then
            print(('^3[BeyondSurvival]^7 client callback "%s" timed out for %s'):format(name, tostring(target)))
            return nil
        end
        return table.unpack(response, 1, response.n)
    end

    RegisterNetEvent(CLIENT_RESPONSE, function(token, ...)
        local resolve = pendingClient[token]
        if resolve then resolve(...) end
    end)

    -- Command wrapper (ACE check, pcall, chat suggestion). It lives in this shared file because a handler function cannot cross an export boundary, so it could not live in bs_core.
    -- BSB.RegisterCommand('kick', 'bs.superadmin', 'Kick a player', { { name = 'id', help = 'server id' } }, function(src, args, raw, player) ... end)
    -- New commands should use this instead of a raw RegisterCommand.
    function BSB.RegisterCommand(name, ace, help, args, handler)
        if type(name) ~= 'string' or type(handler) ~= 'function' then
            return error('BSB.RegisterCommand(name:string, ace, help, args, handler:function)', 2)
        end

        RegisterCommand(name, function(src, rawArgs, raw)
            if src > 0 and ace and not IsPlayerAceAllowed(src, ace) then
                return TriggerClientEvent('bs:ui:notify', src, {
                    type = 'error', title = exports.bs_core:Tr(src, 'core.denied_title'), message = exports.bs_core:Tr(src, 'core.denied_msg')
                })
            end

            local ok, err = pcall(handler, src, rawArgs, raw)
            if not ok then
                print(('^1[%s]^7 /%s failed: %s'):format(GetCurrentResourceName(), name, tostring(err)))
            end
        end, false)

        TriggerEvent('chat:addSuggestion', '/' .. name, help or '', args or {})
    end
else
    -- client
    local pending  = {}
    local sequence = 0

    -- Blocks the calling thread until the owning resource answers, or the timeout elapses (returns nil).
    function BSB.Await(name, timeout, ...)
        sequence = sequence + 1
        -- Tokens carry the resource name: the response event reaches every resource and tokens numbered from 1 would collide.
        local token = ('%s:%d'):format(GetCurrentResourceName(), sequence)

        local done, response = false, nil
        pending[token] = function(...)
            response = table.pack(...)
            done = true
        end

        TriggerServerEvent(REQUEST, name, token, ...)

        local waited = 0
        timeout = timeout or 10000
        while not done and waited < timeout do
            Wait(5)
            waited = waited + 5
        end
        pending[token] = nil

        if not done then
            print(('^3[BeyondSurvival]^7 callback "%s" timed out after %dms'):format(name, timeout))
            return nil
        end
        return table.unpack(response, 1, response.n)
    end

    -- Registers a callback the server may invoke on this client via BSB.AwaitClient. Any resource may own any name; an unowned name stays silent.
    local clientHandlers = {}
    function BSB.RegisterClientCallback(name, fn)
        if type(name) ~= 'string' or type(fn) ~= 'function' then
            return error('BSB.RegisterClientCallback(name:string, fn:function)', 2)
        end
        clientHandlers[name] = fn
    end

    RegisterNetEvent(CLIENT_REQUEST, function(name, token, ...)
        local handler = clientHandlers[name]
        if not handler then return end -- another resource owns this name

        local results = table.pack(pcall(handler, ...))
        if not results[1] then
            print(('^1[BeyondSurvival]^7 client callback "%s" errored: %s'):format(name, tostring(results[2])))
            return TriggerServerEvent(CLIENT_RESPONSE, token, nil)
        end
        TriggerServerEvent(CLIENT_RESPONSE, token, table.unpack(results, 2, results.n))
    end)

    RegisterNetEvent(RESPONSE, function(token, ...)
        local resolve = pending[token]
        if resolve then resolve(...) end
    end)

    -- BSB.Radial: blocking radial wheel that waits in the caller's resource. exports.bs_radial:Open(spec) blocks, but a Wait inside an export runs in the callee's runtime and throws, leaving the wheel open and NUI focus held. bs_radial hands out a token and answers Poll; this spins on it.
    -- local picked = BSB.Radial({ title = 'BOOT', items = { ... } })
    -- Returns the slice id, or nil if cancelled, timed out or the wheel resource is not running.

    -- @param spec table  same shape bs_radial:Open takes
    -- @param timeout number|nil  ms; defaults to 30 seconds
    -- @return string|nil
    function BSB.Radial(spec, timeout)
        if GetResourceState('bs_radial') ~= 'started' then return nil end

        local ok, token = pcall(function()
            return exports.bs_radial:Begin(spec)
        end)

        if not ok or not token then return nil end

        timeout = timeout or 30000
        local waited = 0

        while waited < timeout do
            Wait(20)
            waited = waited + 20

            local answered, answer = pcall(function()
                return exports.bs_radial:Poll(token)
            end)

            if not answered then break end
            if answer and answer.done then return answer.id end
        end

        -- Our timeout, not the wheel's. Take it down rather than leave the player on a dead menu.
        pcall(function() exports.bs_radial:Abandon(token) end)
        return nil
    end
end
