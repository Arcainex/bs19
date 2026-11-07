-- BeyondSurvival - framework object: module registry, hooks and public exports. Other resources use exports.bs_core:GetFramework() instead of requiring core files.

BS = BS or {}

BS.Name     = Config.Framework.name
BS.Version  = Config.Framework.version
BS.Side     = IsDuplicityVersion() and 'server' or 'client'
BS.Ready    = false

BS.Modules  = {}
BS.Hooks    = {}

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

-- Registers a named module table so resources can attach to the core without circular requires.
-- Pass plain data only: tables with functions do not survive the export boundary. Drive behaviour from 'bs:hook:*' events instead.
function BS.RegisterModule(name, module)
    BS.Assert(type(name) == 'string' and name ~= '', 'module name must be a string')
    module = module or {}
    BS.Assert(type(module) == 'table', 'module "%s" must be a table', name)
    if BS.Modules[name] then
        BS.Log.warn('core', ('module "%s" re-registered, replacing previous'):format(name))
    end
    module.__name = name
    BS.Modules[name] = module
    BS.Log.debug('core', ('module registered: %s'):format(name))
    if type(module.OnRegister) == 'function' then
        local ok, err = pcall(module.OnRegister, module)
        if not ok then BS.Log.error('core', ('module "%s" OnRegister failed: %s'):format(name, err)) end
    end
    return module
end

--- @return table|nil
function BS.GetModule(name)
    return BS.Modules[name]
end

--- Blocks the current thread until a module registers (or the timeout elapses).
function BS.WaitForModule(name, timeoutMs)
    local waited = 0
    timeoutMs = timeoutMs or 15000
    while not BS.Modules[name] and waited < timeoutMs do
        Wait(50)
        waited = waited + 50
    end
    if not BS.Modules[name] then
        BS.Log.warn('core', ('timed out waiting for module "%s"'):format(name))
    end
    return BS.Modules[name]
end

-- Hooks (simple pub/sub, in-process, both sides)

--- Subscribes to a framework hook. Returns an unsubscribe function.
--- Known core hooks:
---   'core:ready'              ()
---   'player:loaded'           (player)          server / (data) client
---   'player:unloaded'         (player)
---   'player:levelUp'          (player, level)
---   'character:selected'      (player, charId)
---   'character:created'       (player, charId)
function BS.On(hook, fn)
    BS.Assert(type(fn) == 'function', 'hook handler must be a function')
    BS.Hooks[hook] = BS.Hooks[hook] or {}
    local list = BS.Hooks[hook]
    list[#list + 1] = fn
    return function()
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end
end

-- Fires a hook. Handlers in this resource are called directly, then it is re-broadcast as the event 'bs:hook:<name>'.
-- Other resources must listen to that event, not BS.On: functions do not survive export marshalling ("error object is not a string").
function BS.Emit(hook, ...)
    for _, fn in ipairs(BS.Hooks[hook] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            BS.Log.error('core', ('hook "%s" handler failed: %s'):format(hook, err))
        end
    end

    -- Cross-resource broadcast. TriggerEvent reaches every resource on this side.
    local ok, err = pcall(TriggerEvent, 'bs:hook:' .. hook, ...)
    if not ok then
        BS.Log.error('core', ('hook "%s" broadcast failed: %s'):format(hook, tostring(err)))
    end
end

--------------------------------------------------------------------------------
-- Config access
--------------------------------------------------------------------------------

BS.Config = Config

--- Dotted-path config read: BS.GetConfig('Session.maxCharacters', 1)
function BS.GetConfig(path, fallback)
    local node = Config
    for segment in tostring(path):gmatch('[^%.]+') do
        if type(node) ~= 'table' then return fallback end
        node = node[segment]
        if node == nil then return fallback end
    end
    return node
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

exports('GetFramework', function() return BS end)
exports('RegisterModule', function(name, module) return BS.RegisterModule(name, module) end)
exports('GetEvents', function() return BS.Events end)
exports('GetVersion', function() return BS.Version end)
exports('GetConfig', BS.GetConfig)
exports('IsReady', function() return BS.Ready end)
