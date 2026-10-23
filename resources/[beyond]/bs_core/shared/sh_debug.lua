-- Logging + assertion helpers. Loaded first.

BS = BS or {}
BS.Log = {}

local LEVELS = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, none = 99 }
local COLORS = {
    trace = '^7', debug = '^6', info = '^2', warn = '^3', error = '^1',
}

-- Overwritten by config/config.lua once it loads.
BS.Log.level = 'info'
BS.Log.prefix = '^5[BeyondSurvival]^7'

local function shouldLog(level)
    return (LEVELS[level] or 3) >= (LEVELS[BS.Log.level] or 3)
end

local function stringify(v)
    local t = type(v)
    if t == 'table' then
        local ok, encoded = pcall(json.encode, v)
        return ok and encoded or tostring(v)
    end
    return tostring(v)
end

function BS.Log.write(level, module, ...)
    if not shouldLog(level) then return end
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = stringify((select(i, ...)))
    end
    print(('%s %s[%s]^7 ^7(%s) %s'):format(
        BS.Log.prefix, COLORS[level] or '^7', level:upper(), module or 'core',
        table.concat(parts, ' ')
    ))
end

function BS.Log.trace(module, ...) BS.Log.write('trace', module, ...) end
function BS.Log.debug(module, ...) BS.Log.write('debug', module, ...) end
function BS.Log.info(module, ...)  BS.Log.write('info',  module, ...) end
function BS.Log.warn(module, ...)  BS.Log.write('warn',  module, ...) end
function BS.Log.error(module, ...) BS.Log.write('error', module, ...) end

--- Throws with a framework-tagged message when cond is falsy.
function BS.Assert(cond, msg, ...)
    if not cond then
        error(('[BeyondSurvival] ' .. (msg or 'assertion failed')):format(...), 2)
    end
    return cond
end
