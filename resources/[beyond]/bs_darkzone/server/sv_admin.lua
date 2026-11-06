-- F1 > Dark Zone editor (bs_config extension page) and the /darkzone staff command. Every action is logged.

local function zoneRows()
    local out = {}
    for id, z in pairs(Zone.list) do
        out[#out + 1] = { id = id, label = z.label, x = z.x, y = z.y, z = z.z, radius = z.radius, enabled = z.enabled,
            builtin = z.builtin, edited = z.edited == true, conflict = Zone.Conflict(z),
            heli = z.heli ~= nil, walks = z.walks and #z.walks or 0, active = Zone.active and Zone.active.id == id or false }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function state()
    local a = Zone.active
    return { ok = true, enabled = DZU.on(), paused = Zone.paused,
        active = a and { id = a.id, label = a.label, left = math.max(0, Zone.nextAt - os.time()), inside = (function() local n = 0 for _ in pairs(Zone.inside) do n = n + 1 end return n end)() } or nil,
        heli = Extract.View(), zones = zoneRows() }
end

local function myPos(src)
    local p = src > 0 and DZU.pos(src)
    return p and { x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10, z = math.floor((p.z - 1.0) * 10 + 0.5) / 10 } or nil
end

local function saveEdit(id, data)
    Zone.edits[id] = data
    exports.oxmysql:execute('INSERT INTO `bs_dz_zones` (`id`,`data`) VALUES (?,?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)', { id, json.encode(data) })
    Zone.Rebuild()
end

local function editOf(id)
    local e = {}
    for k, v in pairs(Zone.edits[id] or {}) do e[k] = v end
    return e
end

local function handle(src, action, a)
    if not DZU.isAdmin(src) then return { ok = false, error = 'Admins only.' } end
    a = type(a) == 'table' and a or {}
    if action == 'state' then return state() end
    if action == 'goto' then
        local x, y, z = tonumber(a.x), tonumber(a.y), tonumber(a.z)
        if src <= 0 or not (x and y and z) then return { ok = false, error = 'No position.' } end
        TriggerClientEvent('bs:core:safeTp', src, x + 0.0, y + 0.0, z + 0.0)
        if DZU.started('bs_guard') then pcall(function() exports.bs_guard:Allow(src, 'teleport', 15000) end) end
        DZU.log(src, ('teleport %.0f %.0f %.0f'):format(x, y, z))
        return { ok = true }
    end

    local id = tostring(a.id or ''):lower()
    local detail
    if action == 'start' then
        if not DZU.on() then return { ok = false, error = 'Turn on F1 > Dark Zone > Dark Zone first.' } end
        Zone.SetPaused(false)
        if not Zone.active and not Zone.Next() then return { ok = false, error = 'No valid zone (all off or too close to a safezone).' } end
        detail = 'dz start'
    elseif action == 'stop' then
        Zone.SetPaused(true); detail = 'dz stop'
    elseif action == 'next' then
        if not DZU.on() then return { ok = false, error = 'Dark Zone is off.' } end
        Zone.SetPaused(false)
        if not Zone.Next() then return { ok = false, error = 'No valid zone.' } end
        detail = 'dz next -> ' .. Zone.active.id
    elseif action == 'move' then
        if not DZU.on() then return { ok = false, error = 'Dark Zone is off.' } end
        local z = Zone.list[id]
        if not z then return { ok = false, error = 'No such zone.' } end
        local c = Zone.Conflict(z)
        if c then return { ok = false, error = 'Too close to ' .. tostring(c) .. '.' } end
        Zone.SetPaused(false)
        Zone.Activate(id)
        detail = 'dz move -> ' .. id
    elseif action == 'zoneSave' then
        if not id:match('^[a-z0-9_]+$') or #id > 32 then return { ok = false, error = 'Id: a-z 0-9 _ only.' } end
        local e = editOf(id)
        if a.label and tostring(a.label) ~= '' then e.label = tostring(a.label):sub(1, 48) end
        if tonumber(a.radius) then e.radius = math.max(60, math.min(1500, tonumber(a.radius))) end
        if a.enabled ~= nil then e.enabled = a.enabled == true end
        if a.here then
            local p = myPos(src)
            if not p then return { ok = false, error = 'No position.' } end
            e.x, e.y, e.z = p.x, p.y, p.z
            e.heli, e.walks = nil, nil
        end
        e.deleted = nil
        if not Zone.list[id] and not (e.x and e.y) then return { ok = false, error = 'A new zone needs a position (stand there).' } end
        saveEdit(id, e)
        detail = 'zone saved ' .. id
    elseif action == 'heliHere' or action == 'walkAdd' then
        local z = Zone.list[id]
        local p = myPos(src)
        if not z or not p then return { ok = false, error = 'No such zone or no position.' } end
        if DZU.d2(p.x, p.y, z.x, z.y) > Zone.Radius(z) then return { ok = false, error = 'Stand inside that zone.' } end
        local e = editOf(id)
        if action == 'heliHere' then
            e.heli = p
        else
            e.walks = e.walks or {}
            if #e.walks >= 6 then return { ok = false, error = 'Six walk-out points at most.' } end
            e.walks[#e.walks + 1] = p
        end
        saveEdit(id, e)
        detail = ('zone %s %s'):format(id, action)
    elseif action == 'walkClear' then
        local e = editOf(id)
        e.walks, e.heli = nil, nil
        saveEdit(id, e)
        detail = 'zone points cleared ' .. id
    elseif action == 'zoneReset' then
        if not Zone.edits[id] then return { ok = false, error = 'No editor changes on this zone.' } end
        Zone.edits[id] = nil
        exports.oxmysql:execute('DELETE FROM `bs_dz_zones` WHERE `id` = ?', { id })
        Zone.Rebuild()
        detail = 'zone reset ' .. id
    elseif action == 'zoneDelete' then
        local z = Zone.list[id]
        if not z then return { ok = false, error = 'No such zone.' } end
        if Zone.active and Zone.active.id == id then return { ok = false, error = 'Move the Dark Zone away first.' } end
        if z.builtin then saveEdit(id, { deleted = true }) else
            Zone.edits[id] = nil
            exports.oxmysql:execute('DELETE FROM `bs_dz_zones` WHERE `id` = ?', { id })
            Zone.Rebuild()
        end
        detail = 'zone deleted ' .. id
    else
        return { ok = false, error = 'Unknown action.' }
    end
    DZU.log(src, detail)
    local st = state()
    st.msg = detail
    return st
end

exports('ConfigExt', function(src, action, a)
    local ok, res = pcall(handle, tonumber(src) or 0, tostring(action or ''), a)
    if not ok then print('^1[bs_darkzone]^7 F1: ' .. tostring(res)); return { ok = false, error = 'Server error, see console.' } end
    return res
end)

-- /darkzone start | stop | next | move <id> | list
RegisterCommand('darkzone', function(src, args)
    if not DZU.isAdmin(src) then return end
    local function say(msg)
        if src > 0 then TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = msg, duration = 8000 }) else print(msg) end
    end
    local sub = tostring(args[1] or 'status'):lower()
    if sub == 'start' or sub == 'stop' or sub == 'next' then
        local r = handle(src, sub, {})
        say(r.ok and (r.msg or 'ok') or tostring(r.error))
    elseif sub == 'move' then
        local r = handle(src, 'move', { id = args[2] })
        say(r.ok and (r.msg or 'ok') or tostring(r.error))
    elseif sub == 'list' then
        local lines = {}
        for _, z in ipairs(zoneRows()) do
            lines[#lines + 1] = ('%s%s%s%s'):format(z.id, z.active and ' [active]' or '', z.enabled and '' or ' [off]', z.conflict and (' [near ' .. z.conflict .. ']') or '')
        end
        say(#lines > 0 and table.concat(lines, ', ') or 'no zones')
        DZU.log(src, 'dz list')
    else
        local st = state()
        say(('Dark Zone: %s%s | active: %s | moves in %d min'):format(st.enabled and 'on' or 'off', st.paused and ' (stopped)' or '',
            st.active and st.active.id or '-', st.active and math.floor(st.active.left / 60) or 0))
        DZU.log(src, 'dz status')
    end
end, false)

exports.bs_core:RegisterModule('darkzone', { side = 'server', version = '1.0.0', ready = true })
