-- bs_guard - server callbacks behind the F10 GUARD tab. Each callback re-checks staff.

local G = GuardCore

local function deny(src) return { ok = false, error = Lp(src, 'guard.err_denied') } end

BSB.RegisterCallback('guard:list', function(src, args)
    if not G.isStaff(src) then return deny(src) end
    args = type(args) == 'table' and args or {}
    local limit = math.max(10, math.min(1000, tonumber(args.limit) or Guard.Alerts.listLimit or 200))
    local rows
    if G.dbReady then
        local kind = type(args.kind) == 'string' and args.kind ~= '' and args.kind or nil
        local ok, r = pcall(function()
            if kind then
                return MySQL.query.await('SELECT `id`,UNIX_TIMESTAMP(`created_at`) AS `time`,`src`,`license`,`char_id` AS `charId`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z` FROM `bs_guard_log` WHERE `kind` = ? ORDER BY `id` DESC LIMIT ?', { kind, limit })
            end
            return MySQL.query.await('SELECT `id`,UNIX_TIMESTAMP(`created_at`) AS `time`,`src`,`license`,`char_id` AS `charId`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z` FROM `bs_guard_log` ORDER BY `id` DESC LIMIT ?', { limit })
        end)
        if ok then rows = r end
    end
    if not rows then
        rows = {}
        local rec = G.Recent()
        for i = #rec, math.max(1, #rec - limit + 1), -1 do rows[#rows + 1] = rec[i] end
    end
    -- mark who is still online (same license on the same server id)
    for _, row in ipairs(rows) do
        local s = tonumber(row.src)
        row.online = s ~= nil and GetPlayerName(s) ~= nil and G.license(s) == row.license
    end
    return { ok = true, rows = rows }
end)

local function targetCoords(args)
    local s = tonumber(args.src)
    if s and GetPlayerName(s) and (not args.license or G.license(s) == args.license) then
        local ped = GetPlayerPed(s)
        if ped and ped ~= 0 then return GetEntityCoords(ped), s end
    end
    if tonumber(args.x) and tonumber(args.y) and tonumber(args.z) then
        return vector3(tonumber(args.x), tonumber(args.y), tonumber(args.z)), nil
    end
    return nil
end

BSB.RegisterCallback('guard:goto', function(src, args)
    if not G.isStaff(src) then return deny(src) end
    local c, online = targetCoords(type(args) == 'table' and args or {})
    if not c then return { ok = false, error = Lp(src, 'guard.err_nopos') } end
    G.Allow(src, 'teleport', 5000)
    -- bs_admin's client already owns this teleport handler
    TriggerClientEvent('bs:admin:teleportTo', src, c.x, c.y, c.z)
    return { ok = true, online = online ~= nil }
end)

BSB.RegisterCallback('guard:spectate', function(src, args)
    if not G.isStaff(src) then return deny(src) end
    args = type(args) == 'table' and args or {}
    local c, target = targetCoords(args)
    if not target then return { ok = false, error = Lp(src, 'guard.err_offline') } end
    if target == src then return { ok = false, error = Lp(src, 'guard.err_self') } end
    G.Allow(src, 'teleport', 15000)
    TriggerClientEvent('bs_guard:spectate', src, target, c.x, c.y, c.z)
    print(('^3[BS GUARD]^7 %s spectates [%d]'):format(GetPlayerName(src), target))
    return { ok = true }
end)

-- /guardspec stops spectating (also toggled from the GUARD tab)
RegisterCommand('guardspec', function(src)
    if src > 0 and G.isStaff(src) then TriggerClientEvent('bs_guard:spectateStop', src) end
end, false)

-- Paged, filtered log query for the full-screen Guard logs viewer (staff only).
local SORT = { time = '`id`', player = '`name`', char = '`char_id`', kind = '`kind`', confidence = '`confidence`' }
local COLS = '`id`,UNIX_TIMESTAMP(`created_at`) AS `time`,`src`,`license`,`char_id` AS `charId`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`'

local function likeEsc(s) return (s:gsub('[\\%%_]', '\\%0')) end

local function pageFromMemory(f, sortKey, desc)
    local out = {}
    local q = f.q and f.q:lower() or nil
    for _, e in ipairs(G.Recent()) do
        local ok = true
        if f.kind and e.kind ~= f.kind then ok = false end
        if f.minConf and (e.confidence or 0) < f.minConf then ok = false end
        if f.from and (e.time or 0) < f.from then ok = false end
        if f.to and (e.time or 0) > f.to then ok = false end
        if q and not ((e.name or ''):lower():find(q, 1, true) or (e.license or ''):lower():find(q, 1, true)
            or tostring(e.charId or '') == q) then ok = false end
        if ok then out[#out + 1] = e end
    end
    local keyMap = { time = 'time', player = 'name', char = 'charId', kind = 'kind', confidence = 'confidence' }
    local k = keyMap[sortKey] or 'time'
    table.sort(out, function(a, b)
        local x, y = a[k] or 0, b[k] or 0
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if x == y then return (a.time or 0) > (b.time or 0) end
        if desc then return x > y end
        return x < y
    end)
    return out
end

BSB.RegisterCallback('guard:page', function(src, args)
    if not G.isStaff(src) then return deny(src) end
    args = type(args) == 'table' and args or {}
    local per = math.max(10, math.min(100, math.floor(tonumber(args.per) or 25)))
    local page = math.max(1, math.floor(tonumber(args.page) or 1))
    local sortKey = SORT[args.sort] and args.sort or 'time'
    local desc = args.dir ~= 'asc'
    local f = {
        kind = type(args.kind) == 'string' and args.kind ~= '' and args.kind:sub(1, 32) or nil,
        q = type(args.q) == 'string' and args.q:match('%S') and args.q:sub(1, 64) or nil,
        minConf = tonumber(args.minConf) and math.max(0, math.min(100, math.floor(tonumber(args.minConf)))) or nil,
        from = tonumber(args.from), to = tonumber(args.to),
    }
    if f.minConf == 0 then f.minConf = nil end

    local rows, total
    if G.dbReady then
        local where, params = {}, {}
        if f.kind then where[#where + 1] = '`kind` = ?'; params[#params + 1] = f.kind end
        if f.minConf then where[#where + 1] = '`confidence` >= ?'; params[#params + 1] = f.minConf end
        if f.from then where[#where + 1] = '`created_at` >= FROM_UNIXTIME(?)'; params[#params + 1] = f.from end
        if f.to then where[#where + 1] = '`created_at` <= FROM_UNIXTIME(?)'; params[#params + 1] = f.to end
        if f.q then
            local like = '%' .. likeEsc(f.q) .. '%'
            where[#where + 1] = '(`name` LIKE ? OR `license` LIKE ? OR `char_id` = ?)'
            params[#params + 1] = like; params[#params + 1] = like; params[#params + 1] = tonumber(f.q) or -1
        end
        local w = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
        local ok, err = pcall(function()
            total = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `bs_guard_log`' .. w, params)) or 0
            local p2 = { table.unpack(params) }
            p2[#p2 + 1] = per; p2[#p2 + 1] = (page - 1) * per
            local order = SORT[sortKey] .. (desc and ' DESC' or ' ASC') .. ', `id` DESC'
            rows = MySQL.query.await('SELECT ' .. COLS .. ' FROM `bs_guard_log`' .. w .. ' ORDER BY ' .. order .. ' LIMIT ? OFFSET ?', p2)
        end)
        if not ok then rows, total = nil, nil end
    end
    if not rows then
        local all = pageFromMemory(f, sortKey, desc)
        total = #all
        rows = {}
        for i = (page - 1) * per + 1, math.min(#all, page * per) do rows[#rows + 1] = all[i] end
    end
    for _, row in ipairs(rows) do
        local s = tonumber(row.src)
        row.online = s ~= nil and GetPlayerName(s) ~= nil and G.license(s) == row.license
    end
    return { ok = true, rows = rows, total = total or 0, page = page, per = per }
end)
