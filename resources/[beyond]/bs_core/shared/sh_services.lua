-- shared - service layer: one way for resources to reach each other.
-- Cross-resource calls fail silently (missing export, another resource's global,
-- a typo'd name). BS.Provide / BS.Use give one object with a known set of functions.
-- Provider: BS.Provide('inventory', { 'GiveItem', 'RemoveItem' })
-- Consumer: local inv = BS.Use('inventory'); if inv then inv.GiveItem(src, 'bandage', 1) end
-- BS.Use returns nil and logs the caller when the provider is missing, stopped
-- or lacks a promised export. Additive: direct exports keep working.

-- Self-contained on purpose: consumers include this file directly and do not load sh_framework.lua,
-- so BS, BS.Log and BS.Assert may not exist here. Local fallbacks below keep behaviour the same either way.
BS = BS or {}

BS.Services = BS.Services or {}     -- [name] = { resource, functions = {} }

local function logWarn(msg)
    if BS.Log and BS.Log.warn then return BS.Log.warn('services', msg) end
    print(('^3[BS SERVICES]^7 %s'):format(msg))
end

local function logError(msg)
    if BS.Log and BS.Log.error then return BS.Log.error('services', msg) end
    print(('^1[BS SERVICES]^7 %s'):format(msg))
end

local function logDebug(msg)
    if BS.Log and BS.Log.debug then return BS.Log.debug('services', msg) end
end

--------------------------------------------------------------------------------
-- Providing
--------------------------------------------------------------------------------

-- Declares that this resource offers a named service.
-- @param name string  service name consumers ask for
-- @param fns table    export names the service promises (checked at boot)
function BS.Provide(name, fns)
    if type(name) ~= 'string' or name == '' then
        return logError('BS.Provide(name, fns): name must be a non-empty string')
    end
    if type(fns) ~= 'table' then
        return logError(('BS.Provide("%s"): must declare its functions as a table'):format(name))
    end

    BS.Services[name] = {
        resource  = GetCurrentResourceName(),
        functions = fns,
    }

    logDebug(('service provided: %s (%d functions) by %s')
        :format(name, #fns, GetCurrentResourceName()))
end

--------------------------------------------------------------------------------
-- Consuming
--------------------------------------------------------------------------------

-- Where a service lives, for consumers that cannot ask bs_core (the registry is per Lua state).
-- Kept as plain data since tables of functions do not cross resources.
local KNOWN = {
    core        = 'bs_core',
    inventory   = 'bs_inventory',
    building    = 'bs_building',
    zombies     = 'bs_zombies',
    weapons     = 'bs_weapons',
    vip         = 'bs_vip',
    skills      = 'bs_skills',
    admin       = 'bs_admin',
    economy     = 'bs_economy',
    medical     = 'bs_medical',
    emotes      = 'bs_emotes',
    vehicles    = 'bs_vehicles',
    factions    = 'bs_factions',
    ui          = 'bs_ui',
    radial      = 'bs_radial',
    scenes      = 'bs_scenes',
    interactions = 'bs_interactions',
    extraction  = 'bs_extraction',
    scoreboard  = 'bs_scoreboard',
    world       = 'bs_world',
}

local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    logWarn(message)
end

-- Resolves a service into a callable handle, or nil.
-- Calls are wrapped: a provider error or missing export is logged with both resource names instead of returning nil.
-- @param name string
-- @return table|nil
function BS.Use(name)
    local resource = KNOWN[name]

    if not resource then
        warnOnce('unknown:' .. tostring(name),
            ('%s asked for unknown service "%s" - add it to KNOWN in sh_services.lua')
            :format(GetCurrentResourceName(), tostring(name)))
        return nil
    end

    if GetResourceState(resource) ~= 'started' then
        warnOnce('down:' .. resource,
            ('%s wanted service "%s" but %s is not started')
            :format(GetCurrentResourceName(), name, resource))
        return nil
    end

    local target = exports[resource]
    if not target then return nil end

    -- Thin proxy: exports are resolved on each call, so a restarted provider is picked up.
    return setmetatable({}, {
        __index = function(_, fn)
            return function(...)
                local ok, result, extra = pcall(function(...)
                    return target[fn](target, ...)
                end, ...)

                if not ok then
                    logError(('%s -> %s:%s failed: %s')
                        :format(GetCurrentResourceName(), resource, tostring(fn), tostring(result)))
                    return nil
                end

                return result, extra
            end
        end,
    })
end

-- True when a service is available right now. For optional features that should degrade instead of fail.
-- @return boolean
function BS.Has(name)
    local resource = KNOWN[name]
    return resource ~= nil and GetResourceState(resource) == 'started'
end

exports('Use', function(name) return BS.Use(name) end)
exports('HasService', function(name) return BS.Has(name) end)
