-- bs_building build areas: block zones (no building) and allow zones (the only places to build when allowedOnly is on)

local S = Building.Settings
local Zones = { db = {} }

local function isAdmin(src) return src == 0 or IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
local function flat(a, b) local dx, dy = a.x - b.x, a.y - b.y; return math.sqrt(dx * dx + dy * dy) end

local function all()
    local out = {}
    for _, z in ipairs(Building.Zones or {}) do
        if type(z) == 'table' and tonumber(z.x) and tonumber(z.y) then
            out[#out + 1] = { id = 'cfg', kind = z.kind == 'allow' and 'allow' or 'block', label = z.label or '',
                              x = tonumber(z.x), y = tonumber(z.y), radius = tonumber(z.radius) or 50.0 }
        end
    end
    for _, z in ipairs(Zones.db) do out[#out + 1] = z end
    return out
end

-- Why this spot is off limits, or nil. Faction claims are checked by the caller.
function Building.ZoneError(at)
    if S.blockSafezones ~= false and Building.InSafeZone(at) then return 'build.err.safezone' end
    local list = all()
    local allowed = false
    for _, z in ipairs(list) do
        if flat(at, z) <= z.radius then
            if z.kind == 'block' then return 'build.err.blocked_zone' end
            allowed = true
        end
    end
    if S.allowedOnly and not allowed then return 'build.err.not_allowed_zone' end
    return nil
end

local function reload()
    local rows = Store.q('SELECT `id`,`kind`,`label`,`x`,`y`,`z`,`radius` FROM `bs_build_zones`')
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = tonumber(r.id), kind = r.kind == 'allow' and 'allow' or 'block', label = r.label or '',
                          x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) or 0.0, radius = tonumber(r.radius) or 50.0 }
    end
    Zones.db = out
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    -- migration 042 makes it; wait for bs_core like the piece loader does
    for _ = 1, 60 do
        local ok = pcall(function() return exports.oxmysql:query_async('SELECT 1 FROM `bs_build_zones` LIMIT 1') end)
        if ok then break end
        Wait(1000)
    end
    pcall(reload)
end)

local function tell(src, key, vars, kind)
    if src == 0 then print('[bs_building] ' .. L(key, vars)) return end
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = Lp(src, key, vars), duration = 7000 })
end

-- /buildzone add block|allow <radius> [name] | remove <id> | list
RegisterCommand('buildzone', function(src, args)
    if not isAdmin(src) then return end
    local sub = tostring(args[1] or ''):lower()
    if sub == 'add' and src ~= 0 then
        local kind = tostring(args[2] or ''):lower()
        local radius = tonumber(args[3])
        if (kind ~= 'block' and kind ~= 'allow') or not radius or radius < 5 or radius > 5000 then
            return tell(src, 'build.zone.usage', nil, 'warn')
        end
        local c = GetEntityCoords(GetPlayerPed(src))
        local label = table.concat(args, ' ', 4):sub(1, 64)
        local id = exports.oxmysql:insert_async('INSERT INTO `bs_build_zones` (`kind`,`label`,`x`,`y`,`z`,`radius`,`created_by`) VALUES (?,?,?,?,?,?,?)',
            { kind, label, c.x, c.y, c.z, radius, (GetPlayerName(src) or '?'):sub(1, 64) })
        if not id then return tell(src, 'build.err.failed', nil, 'error') end
        reload()
        Store.log(src, 'zone', ('added %s zone #%d r=%.0f %s'):format(kind, id, radius, label), { x = c.x, y = c.y, z = c.z })
        return tell(src, 'build.zone.added', { id = id, kind = kind, r = math.floor(radius) }, 'success')
    elseif sub == 'remove' then
        local id = tonumber(args[2])
        if not id then return tell(src, 'build.zone.usage', nil, 'warn') end
        Store.x('DELETE FROM `bs_build_zones` WHERE `id` = ?', { id })
        reload()
        Store.log(src, 'zone', ('removed zone #%d'):format(id))
        return tell(src, 'build.zone.removed', { id = id }, 'success')
    elseif sub == 'list' then
        local list = all()
        if src == 0 then
            for _, z in ipairs(list) do print(('[bs_building] zone %s %s r=%.0f at %.0f %.0f %s'):format(tostring(z.id), z.kind, z.radius, z.x, z.y, z.label)) end
        else
            TriggerClientEvent('bs:building:zones', src, list)
        end
        return tell(src, 'build.zone.list', { n = #list })
    end
    tell(src, 'build.zone.usage', nil, 'warn')
end, false)

exports('BuildZones', function() return all() end)
