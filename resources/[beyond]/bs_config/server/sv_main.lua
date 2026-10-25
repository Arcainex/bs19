-- bs_config server: owns profiles, active overrides and the audit log.

local S = BSConfig.Settings
local SCHEMA, BYID, RESOURCES = BSConfigSchema, {}, {}
for _, e in ipairs(SCHEMA) do
    BYID[e.id] = e
    if e.res ~= '_global' then RESOURCES[e.res] = true end
end
local BUILTIN = {}
for _, n in ipairs(BSConfig.Builtin) do BUILTIN[n] = true end

local profiles = {}      -- name -> { overrides = {id=value}, updated = ts, by = name }
local active = 'Default'
local defaults = {}      -- id -> value read from the config files
local payload = { _global = {} }
local ready = false

-- Access

local function hasAny(src, aces)
    for _, a in ipairs(aces or {}) do
        if IsPlayerAceAllowed(src, a) then return true end
    end
    return false
end

local function isOwner(src)
    if src == 0 then return true end
    return hasAny(src, S.ownerAces)
end

local function isAdmin(src)
    if src == 0 or isOwner(src) then return true end
    if GetResourceState('bs_admin') == 'started' then
        local ok, r = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and r then return true end
    end
    return hasAny(src, S.adminAces)
end

local function who(src)
    if src == 0 then return 'console', 'console' end
    local ident = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license') or nil
    return GetPlayerName(src) or ('#' .. src), ident or ('src:' .. src)
end

-- Defaults: load each resource's config files in a sandbox

local function sandbox()
    local stub
    stub = setmetatable({}, {
        __call = function() return stub end,
        __index = function() return stub end,
        __newindex = function() end,
    })
    local vec = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    local safe = {
        math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select, pcall = pcall,
        setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
        print = function() end, vector2 = vec, vector3 = vec, vector4 = vec, vec3 = vec, vec = vec,
        GetHashKey = function() return 0 end, joaat = function() return 0 end,
        IsDuplicityVersion = function() return true end,
    }
    local env = {}
    setmetatable(env, { __index = function(t, k)
        if safe[k] ~= nil then return safe[k] end
        if type(k) == 'string' and k:match('^%u') then
            local tb = {}
            rawset(t, k, tb)
            return tb
        end
        return stub
    end })
    return env
end

local function configFiles(res)
    local mf = LoadResourceFile(res, 'fxmanifest.lua') or ''
    local list, seen = {}, {}
    for f in mf:gmatch("['\"](config/[%w_%-/]+%.lua)['\"]") do
        if not seen[f] then seen[f] = true; list[#list + 1] = f end
    end
    return list
end

local function lookup(env, path)
    local t = env
    for s in path:gmatch('[^%.]+') do
        if type(t) ~= 'table' then return nil end
        t = rawget(t, math.tointeger(tonumber(s)) or s)
    end
    if type(t) == 'table' then return nil end
    return t
end

local function readDefaults()
    local envs = {}
    for res in pairs(RESOURCES) do
        local env = sandbox()
        for _, f in ipairs(configFiles(res)) do
            local src = LoadResourceFile(res, f)
            if src then
                local chunk = load(src, '@' .. res .. '/' .. f, 't', env)
                if chunk then pcall(chunk) end
            end
        end
        envs[res] = env
    end
    for _, e in ipairs(SCHEMA) do
        local v
        if envs[e.res] then v = lookup(envs[e.res], e.path) end
        if v == nil or type(v) ~= type(e.fb) then v = e.fb end
        defaults[e.id] = v
    end
end

-- Validation

local function validate(id, v)
    local e = BYID[id]
    if not e then return nil end
    local t = e.type
    if t == 'bool' then
        if type(v) == 'boolean' then return v end
        return nil
    elseif t == 'int' or t == 'number' then
        v = tonumber(v)
        if not v or v ~= v then return nil end
        if e.min then v = math.max(e.min, v) end
        if e.max then v = math.min(e.max, v) end
        if t == 'int' then return math.tointeger(math.floor(v + 0.5)) end
        return v + 0.0
    elseif t == 'enum' then
        for _, o in ipairs(e.opts or {}) do if o == v then return v end end
        return nil
    else
        if type(v) ~= 'string' then return nil end
        return v:sub(1, 32)
    end
end

local function cleanOverrides(tbl)
    local out = {}
    if type(tbl) ~= 'table' then return out end
    for id, v in pairs(tbl) do
        local ok = validate(id, v)
        if ok ~= nil then out[id] = ok end
    end
    return out
end

local function validName(n)
    if type(n) ~= 'string' then return nil end
    n = n:gsub('^%s+', ''):gsub('%s+$', '')
    if #n < 1 or #n > S.nameMax or not n:match('^[%w _%-%.]+$') then return nil end
    return n
end

-- Storage

local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_config_profiles` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(64) NOT NULL,
        `data` LONGTEXT NOT NULL,
        `created_by` VARCHAR(128) NULL,
        `updated_by` VARCHAR(128) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), UNIQUE KEY `uq_bs_config_profiles_name` (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_config_state` (
        `k` VARCHAR(64) NOT NULL, `v` TEXT NULL, PRIMARY KEY (`k`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_config_audit` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `actor` VARCHAR(128) NULL, `actor_ident` VARCHAR(128) NULL,
        `action` VARCHAR(24) NOT NULL DEFAULT 'set',
        `profile` VARCHAR(64) NULL, `setting` VARCHAR(191) NULL,
        `old_value` TEXT NULL, `new_value` TEXT NULL,
        PRIMARY KEY (`id`), KEY `idx_bs_config_audit_at` (`at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

local function loadAll()
    profiles = {}
    for name, ov in pairs(BSConfigPresets) do
        profiles[name] = { overrides = cleanOverrides(ov), builtin = true }
    end
    local rows = MySQL.query.await('SELECT `name`, `data`, `updated_by`, UNIX_TIMESTAMP(`updated_at`) AS ts FROM `bs_config_profiles`') or {}
    for _, r in ipairs(rows) do
        if not BUILTIN[r.name] then
            local ok, data = pcall(json.decode, r.data or '{}')
            profiles[r.name] = { overrides = cleanOverrides(ok and data or {}), by = r.updated_by, updated = r.ts }
        end
    end
    local st = MySQL.single.await('SELECT `v` FROM `bs_config_state` WHERE `k` = ?', { 'active' })
    active = (st and profiles[st.v]) and st.v or 'Default'
end

local function persist(name)
    local p = profiles[name]
    if not p or p.builtin then return end
    MySQL.query.await([[INSERT INTO `bs_config_profiles` (`name`, `data`, `created_by`, `updated_by`) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `updated_by` = VALUES(`updated_by`)]],
        { name, json.encode(p.overrides), p.by, p.by })
    p.updated = os.time()
end

local function enc(v) if v == nil then return nil end return json.encode(v) end

local function audit(src, action, profile, setting, old, new)
    local name, ident = who(src)
    MySQL.insert('INSERT INTO `bs_config_audit` (`actor`, `actor_ident`, `action`, `profile`, `setting`, `old_value`, `new_value`) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { name, ident, action, profile, setting, enc(old), enc(new) })
end

-- Broadcast

local function rebuild()
    local p = { _global = {} }
    local ov = profiles[active] and profiles[active].overrides or {}
    for id, v in pairs(ov) do
        local e = BYID[id]
        if e then
            p[e.res] = p[e.res] or {}
            p[e.res][e.path] = v
        end
    end
    payload = p
end

local function broadcast()
    rebuild()
    TriggerEvent('bs_config:apply', payload)
    TriggerClientEvent('bs_config:apply', -1, payload)
end

exports('GetPayload', function() return ready and payload or nil end)
exports('GetActiveProfile', function() return active end)
exports('Get', function(path, default)
    local res, p = tostring(path):match('^([^:]+):(.+)$')
    if res then
        local t = payload[res]
        if t and t[p] ~= nil then return t[p] end
        return default
    end
    local v = payload._global[path]
    if v == nil then return default end
    return v
end)

-- Actions

local function profileList()
    local list = {}
    for name, p in pairs(profiles) do
        local n = 0
        for _ in pairs(p.overrides) do n = n + 1 end
        list[#list + 1] = { name = name, builtin = p.builtin or false, count = n, by = p.by, updated = p.updated }
    end
    table.sort(list, function(a, b)
        if a.builtin ~= b.builtin then return a.builtin end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

local function state(src)
    return { profiles = profileList(), active = active, isOwner = isOwner(src) }
end

local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

local A = {}

function A.open(src)
    local cats = BSConfig.Categories
    local st = state(src)
    st.schema, st.defaults, st.categories = SCHEMA, defaults, cats
    st.overrides = profiles[active].overrides
    return st
end

function A.getProfile(src, name)
    local p = profiles[name]
    if not p then return { ok = false, error = Lp(src, 'cfg.e.nosuch') } end
    return { ok = true, name = name, overrides = p.overrides, builtin = p.builtin or false }
end

function A.save(src, name, changes)
    local p = profiles[name]
    if not p then return { ok = false, error = Lp(src, 'cfg.e.nosuch') } end
    if p.builtin then return { ok = false, error = Lp(src, 'cfg.e.readonly') } end
    if type(changes) ~= 'table' then return { ok = false, error = Lp(src, 'cfg.e.nothing_save') } end
    local n = 0
    for id, v in pairs(changes) do
        if BYID[id] then
            local old = p.overrides[id]
            local new, valid = nil, true
            if v ~= '__reset__' then     -- '__reset__' clears the override
                new = validate(id, v)
                valid = new ~= nil
            end
            if new ~= nil and new == defaults[id] then new = nil end
            if valid and old ~= new then
                p.overrides[id] = new
                audit(src, 'set', name, id, old, new)
                n = n + 1
            end
        end
    end
    p.by = (who(src))
    persist(name)
    if name == active then broadcast() end
    return { ok = true, changed = n, overrides = p.overrides, state = state(src) }
end

function A.saveAs(src, newName, overrides)
    newName = validName(newName)
    if not newName then return { ok = false, error = Lp(src, 'cfg.e.badname') } end
    if profiles[newName] then return { ok = false, error = Lp(src, 'cfg.e.taken') } end
    local ov = cleanOverrides(overrides)
    for id, v in pairs(ov) do if v == defaults[id] then ov[id] = nil end end
    profiles[newName] = { overrides = ov, by = (who(src)) }
    persist(newName)
    audit(src, 'create', newName, nil, nil, nil)
    return { ok = true, name = newName, state = state(src) }
end

function A.duplicate(src, name, newName)
    local p = profiles[name]
    if not p then return { ok = false, error = Lp(src, 'cfg.e.nosuch') } end
    return A.saveAs(src, newName, copy(p.overrides))
end

function A.rename(src, name, newName)
    local p = profiles[name]
    if not p or p.builtin then return { ok = false, error = Lp(src, 'cfg.e.norename') } end
    newName = validName(newName)
    if not newName then return { ok = false, error = Lp(src, 'cfg.e.badname2') } end
    if profiles[newName] then return { ok = false, error = Lp(src, 'cfg.e.taken') } end
    MySQL.update.await('UPDATE `bs_config_profiles` SET `name` = ? WHERE `name` = ?', { newName, name })
    profiles[newName], profiles[name] = p, nil
    if active == name then
        active = newName
        MySQL.query.await('REPLACE INTO `bs_config_state` (`k`, `v`) VALUES (?, ?)', { 'active', active })
    end
    audit(src, 'rename', newName, nil, name, newName)
    return { ok = true, name = newName, state = state(src) }
end

function A.delete(src, name)
    if not isOwner(src) then return { ok = false, error = Lp(src, 'cfg.e.ownerdel') } end
    local p = profiles[name]
    if not p or p.builtin then return { ok = false, error = Lp(src, 'cfg.e.nodelete') } end
    if name == active then return { ok = false, error = Lp(src, 'cfg.e.activate_first') } end
    MySQL.query.await('DELETE FROM `bs_config_profiles` WHERE `name` = ?', { name })
    profiles[name] = nil
    audit(src, 'delete', name, nil, nil, nil)
    return { ok = true, state = state(src) }
end

function A.setActive(src, name)
    if not profiles[name] then return { ok = false, error = Lp(src, 'cfg.e.nosuch') } end
    local old = active
    active = name
    MySQL.query.await('REPLACE INTO `bs_config_state` (`k`, `v`) VALUES (?, ?)', { 'active', active })
    audit(src, 'activate', name, nil, old, name)
    broadcast()
    return { ok = true, state = state(src), overrides = profiles[name].overrides }
end

function A.audit(src)
    local rows = MySQL.query.await(('SELECT `id`, UNIX_TIMESTAMP(`at`) AS ts, `actor`, `action`, `profile`, `setting`, `old_value`, `new_value` FROM `bs_config_audit` ORDER BY `id` DESC LIMIT %d'):format(S.auditLimit)) or {}
    return { ok = true, rows = rows }
end

function A.revert(src, auditId)
    local row = MySQL.single.await('SELECT * FROM `bs_config_audit` WHERE `id` = ?', { tonumber(auditId) or 0 })
    if not row or row.action ~= 'set' and row.action ~= 'revert' then return { ok = false, error = Lp(src, 'cfg.e.revert_only') } end
    local p = profiles[row.profile]
    if not p or p.builtin then return { ok = false, error = Lp(src, 'cfg.e.profile_gone') } end
    local id = row.setting
    if not BYID[id] then return { ok = false, error = Lp(src, 'cfg.e.unknown_setting') } end
    local target = nil
    if row.old_value then
        local ok, v = pcall(json.decode, row.old_value)
        if ok then target = validate(id, v) end
    end
    local old = p.overrides[id]
    p.overrides[id] = target
    p.by = (who(src))
    persist(row.profile)
    audit(src, 'revert', row.profile, id, old, target)
    if row.profile == active then broadcast() end
    return { ok = true, state = state(src) }
end

function A.restart(src, res)
    if type(res) ~= 'string' or not RESOURCES[res] then return { ok = false, error = Lp(src, 'cfg.e.notres') } end
    if GetResourceState(res) == 'missing' then return { ok = false, error = Lp(src, 'cfg.e.resmissing') } end
    audit(src, 'restart', active, res, nil, nil)
    CreateThread(function() Wait(100); ExecuteCommand('ensure ' .. res) end)
    return { ok = true }
end

function A.export(src, name)
    local p = profiles[name]
    if not p then return { ok = false, error = Lp(src, 'cfg.e.nosuch') } end
    local doc = { format = 'bs_config', version = 1, name = name, exported = os.date('!%Y-%m-%dT%H:%M:%SZ'), overrides = p.overrides }
    local text = json.encode(doc)
    local file = ('exports/%s.json'):format(name:gsub('[^%w_%-]', '_'))
    SaveResourceFile(GetCurrentResourceName(), file, text, -1)
    return { ok = true, json = text, file = file }
end

function A.import(src, name, text)
    if type(text) ~= 'string' or #text > 200000 then return { ok = false, error = Lp(src, 'cfg.e.noimport') } end
    local ok, doc = pcall(json.decode, text)
    if not ok or type(doc) ~= 'table' then return { ok = false, error = Lp(src, 'cfg.e.badjson') } end
    local ov = doc.overrides or doc
    local res = A.saveAs(src, name or doc.name, ov)
    if res.ok then
        local n = 0
        for _ in pairs(profiles[res.name].overrides) do n = n + 1 end
        res.count = n
    end
    return res
end

-- Extension pages: other resources answer their own F1 page through a ConfigExt export.
function A.ext(src, res, action, payload)
    if type(res) ~= 'string' or not (BSConfig.Extensions or {})[res] then return { ok = false, error = Lp(src, 'cfg.e.unknown_page') } end
    if GetResourceState(res) ~= 'started' then return { ok = false, error = Lp(src, 'cfg.e.notrunning', { res = res }) } end
    return exports[res]:ConfigExt(src, tostring(action or ''), payload)
end

-- RPC

local vehicleConfirm = {}
function A.vehiclePreview(src, scope, operation)
    if scope ~= 'unclaimed' and scope ~= 'claimed' and scope ~= 'all' then return { ok = false, error = 'Choose a vehicle group' } end
    if operation ~= 'wipe' and operation ~= 'repopulate' then return { ok = false, error = 'Choose wipe or repopulate' } end
    if scope ~= 'unclaimed' and not isOwner(src) then return { ok = false, error = 'Only a server owner may remove claimed vehicles' } end
    if GetResourceState('bs_vehicles') ~= 'started' then return { ok = false, error = 'bs_vehicles is not running' } end
    local count = exports.bs_vehicles:PreviewWorldCars(scope)
    if count == nil then return { ok = false, error = 'Vehicle preview failed' } end
    vehicleConfirm[src] = { scope = scope, operation = operation, count = count, expires = GetGameTimer() + 30000 }
    return { ok = true, count = count }
end

function A.vehicleManage(src, scope, operation)
    local preview = vehicleConfirm[src]
    vehicleConfirm[src] = nil
    if not preview or preview.scope ~= scope or preview.operation ~= operation or preview.expires < GetGameTimer() then
        return { ok = false, error = 'Preview the vehicle operation again before confirming' }
    end
    if scope ~= 'unclaimed' and not isOwner(src) then return { ok = false, error = 'Only a server owner may remove claimed vehicles' } end
    if GetResourceState('bs_vehicles') ~= 'started' then return { ok = false, error = 'bs_vehicles is not running' } end
    if exports.bs_vehicles:PreviewWorldCars(scope) ~= preview.count then return { ok = false, error = 'Vehicle count changed. Preview again.' } end
    audit(src, 'vehicle_request', active, scope, nil, operation)
    local result = exports.bs_vehicles:ManageWorldCars(scope, operation)
    if result.ok then audit(src, 'vehicle_' .. operation, active, scope, result.removed, result.queued) end
    return result
end
AddEventHandler('playerDropped', function() vehicleConfirm[source] = nil end)

RegisterNetEvent('bs_config:rpc', function(reqId, action, a, b, c)
    local src = source
    local fn = A[action]
    local res
    if not isAdmin(src) then
        res = { ok = false, denied = true, error = Lp(src, 'cfg.e.admins') }
    elseif not ready then
        res = { ok = false, error = Lp(src, 'cfg.e.starting') }
    elseif not fn then
        res = { ok = false, error = Lp(src, 'cfg.e.unknown_action') }
    else
        local ok, r = pcall(fn, src, a, b, c)
        res = ok and r or { ok = false, error = Lp(src, 'cfg.e.server', { err = tostring(r) }) }
    end
    TriggerClientEvent('bs_config:rpc:res', src, reqId, res)
end)

-- clients ask once when bs_config's client starts
RegisterNetEvent('bs_config:hello', function()
    if ready then TriggerClientEvent('bs_config:apply', source, payload) end
end)

-- Boot

CreateThread(function()
    local ok, err = pcall(ensureTables)
    if not ok then print('^1[bs_config] table setup failed: ' .. tostring(err) .. '^7') end
    readDefaults()
    ok, err = pcall(loadAll)
    if not ok then print('^1[bs_config] load failed: ' .. tostring(err) .. '^7') end
    ready = true
    broadcast()
    print(('[bs_config] %d settings, %d profiles, active = %s'):format(#SCHEMA, #profileList(), active))
end)

RegisterCommand('bsconfig_active', function(src, args)
    if src ~= 0 and not isAdmin(src) then return end
    if args[1] then
        local r = A.setActive(src, table.concat(args, ' '))
        print('[bs_config] ' .. (r.ok and ('active = ' .. active) or r.error))
    else
        print('[bs_config] active = ' .. active)
    end
end, true)
