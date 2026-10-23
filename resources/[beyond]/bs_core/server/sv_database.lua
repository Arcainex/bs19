-- BeyondSurvival - thin database layer. Everything talks to BS.DB, so swapping oxmysql only touches this file.

BS.DB = {}
local DB = BS.DB
local driverName = Config.Database.driver

local driver

local function resolveDriver()
    if driverName == 'oxmysql' then
        BS.Assert(GetResourceState('oxmysql') == 'started',
            'oxmysql is not started - BeyondSurvival needs it for persistence')
        driver = {
            query   = function(sql, params) return exports.oxmysql:query_async(sql, params) end,
            single  = function(sql, params) return exports.oxmysql:single_async(sql, params) end,
            scalar  = function(sql, params) return exports.oxmysql:scalar_async(sql, params) end,
            insert  = function(sql, params) return exports.oxmysql:insert_async(sql, params) end,
            update  = function(sql, params) return exports.oxmysql:update_async(sql, params) end,
            prepare = function(sql, params) return exports.oxmysql:prepare_async(sql, params) end,
        }
    else
        error(('[BeyondSurvival] unsupported database driver "%s"'):format(tostring(driverName)))
    end
end

local function timed(kind, sql, params)
    if not driver then resolveDriver() end
    local started = GetGameTimer()
    local ok, result = pcall(driver[kind], sql, params or {})
    local took = GetGameTimer() - started
    if not ok then
        BS.Log.error('db', ('query failed (%s): %s'):format(kind, result))
        BS.Log.error('db', sql)
        return nil, result
    end
    if took >= (Config.Database.slowQueryMs or 250) then
        BS.Log.warn('db', ('slow query %dms: %s'):format(took, sql:sub(1, 160)))
    end
    return result
end

--- Returns every row.
function DB.Query(sql, params)  return timed('query', sql, params) end
--- Returns the first row, or nil.
function DB.Single(sql, params) return timed('single', sql, params) end
--- Returns the first column of the first row.
function DB.Scalar(sql, params) return timed('scalar', sql, params) end
--- Returns the new AUTO_INCREMENT id.
function DB.Insert(sql, params) return timed('insert', sql, params) end
--- Returns the affected row count.
function DB.Update(sql, params) return timed('update', sql, params) end
--- Executes a statement for each parameter set. Returns true on success.
function DB.Prepare(sql, paramSets) return timed('prepare', sql, paramSets) end

-- Executes raw SQL with several ';' separated statements. Used by the migration runner, not for gameplay code.
function DB.Execute(rawSql)
    local statements = {}
    for statement in (rawSql .. '\n'):gmatch('(.-);%s*\n') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        -- Strip comment-only chunks.
        local meaningful = trimmed:gsub('%-%-[^\n]*', ''):gsub('%s+', '')
        if meaningful ~= '' then statements[#statements + 1] = trimmed end
    end
    for _, statement in ipairs(statements) do
        local _, err = DB.Query(statement)
        if err then return false, err end
    end
    return true, #statements
end

--- Simple connectivity probe used during bootstrap.
function DB.Ping()
    local value = DB.Scalar('SELECT 1')
    return value ~= nil
end

-- Write channel for other resources. BS.DB cannot be exported (a yielding export would block the caller), so telemetry arrives as a server-side event (never a net event) and runs on our own thread:
-- TriggerEvent('bs:db:insert', 'INSERT INTO ...', { params })

AddEventHandler('bs:db:insert', function(sql, params)
    if type(sql) ~= 'string' then return end
    CreateThread(function()
        local _, err = DB.Insert(sql, params or {})
        if err then BS.Log.warn('db', ('telemetry insert failed: %s'):format(tostring(err))) end
    end)
end)

AddEventHandler('bs:db:update', function(sql, params)
    if type(sql) ~= 'string' then return end
    CreateThread(function()
        local _, err = DB.Update(sql, params or {})
        if err then BS.Log.warn('db', ('telemetry update failed: %s'):format(tostring(err))) end
    end)
end)
