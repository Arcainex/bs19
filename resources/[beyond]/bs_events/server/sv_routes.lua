-- bs_events - convoy routes: config routes + routes recorded by admins (/convoyroute), stored in bs_convoy_routes

local DB = {}                 -- loaded rows: { id, name, points = {vector3}, enabled, by }
local Rec = {}                -- [src] = { name, pts = {{x,y,z}}, last = vector3 }
local STEP, MAXPTS = 40.0, 500

local function ox() return exports.oxmysql end

local function ensureTable()
    pcall(function()
        ox():query_async([[CREATE TABLE IF NOT EXISTS `bs_convoy_routes` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `name` VARCHAR(64) NOT NULL, `points` MEDIUMTEXT NOT NULL,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1, `created_by` VARCHAR(64) NOT NULL DEFAULT '',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`))
            ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    end)
end

local function reload()
    local ok, rows = pcall(function() return ox():query_async('SELECT id, name, points, enabled, created_by FROM bs_convoy_routes ORDER BY id') end)
    if not ok or type(rows) ~= 'table' then return end
    local out = {}
    for _, r in ipairs(rows) do
        local okj, arr = pcall(json.decode, r.points or '[]')
        if okj and type(arr) == 'table' then
            local pts = {}
            for _, p in ipairs(arr) do
                if type(p) == 'table' and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
                    pts[#pts + 1] = vector3(p[1] + 0.0, p[2] + 0.0, p[3] + 0.0)
                end
            end
            out[#out + 1] = { id = r.id, name = r.name, points = pts, enabled = r.enabled == 1 or r.enabled == true, by = r.created_by }
        end
    end
    DB = out
end

CreateThread(function()
    Wait(3000)
    ensureTable()
    reload()
end)

-- config routes + DB routes with 2+ points that are enabled
function EV.EnabledRoutes()
    local out = {}
    for _, r in ipairs((Events.Convoy and Events.Convoy.routes) or {}) do
        if r.enabled ~= false and r.points and #r.points >= 2 then out[#out + 1] = { name = r.name, points = r.points } end
    end
    for _, r in ipairs(DB) do
        if r.enabled and #r.points >= 2 then out[#out + 1] = { name = r.name, points = r.points } end
    end
    return out
end

-- staff action line in bs_guard_log (kind admin)
local function guardLog(src, detail)
    print(('^3[bs_events]^7 %s'):format(detail))
    if not src or src == 0 then return end
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local char
    pcall(function() char = exports.bs_core:GetPlayer(src) end)
    pcall(function()
        ox():insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
            { src, GetPlayerIdentifierByType(src, 'license'), char and char.charId or nil, (GetPlayerName(src) or '?'):sub(1, 64),
              'admin', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
    end)
end

local function who(src) return src == 0 and 'console' or (GetPlayerName(src) or '?') end

-- sample the recording admin's vehicle every second; keep a point each STEP metres
CreateThread(function()
    while true do
        Wait(1000)
        for src, r in pairs(Rec) do
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then
                Rec[src] = nil
            elseif #r.pts < MAXPTS then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                    local c = GetEntityCoords(veh)
                    if not r.last or #(vector3(c.x, c.y, 0.0) - vector3(r.last.x, r.last.y, 0.0)) >= STEP then
                        r.last = c
                        r.pts[#r.pts + 1] = { math.floor(c.x * 10 + 0.5) / 10, math.floor(c.y * 10 + 0.5) / 10, math.floor(c.z * 10 + 0.5) / 10 }
                        if #r.pts % 10 == 0 then EV.Reply(src, L(src, 'ev.cr_progress', { n = #r.pts })) end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local r = Rec[source]
    if r then
        Rec[source] = nil
        guardLog(0, ('convoyroute recording "%s" dropped with %d points (not saved)'):format(r.name, #r.pts))
    end
end)

local function findRow(id)
    for i, r in ipairs(DB) do if r.id == id then return r, i end end
end

RegisterCommand('convoyroute', function(src, args)
    if not EV.IsAdmin(src) then return EV.Reply(src, L(src, 'ev.admins_only')) end
    local sub = (args[1] or ''):lower()
    if sub == 'start' then
        if src == 0 then return EV.Reply(src, L(src, 'ev.cr_ingame')) end
        local name = table.concat(args, ' ', 2):gsub('[%c]', ''):sub(1, 64)
        name = name:gsub('^%s+', ''):gsub('%s+$', '')
        if #name < 2 then return EV.Reply(src, L(src, 'ev.cr_usage')) end
        if Rec[src] then return EV.Reply(src, L(src, 'ev.cr_already', { name = Rec[src].name })) end
        Rec[src] = { name = name, pts = {} }
        guardLog(src, ('convoyroute start "%s"'):format(name))
        EV.Reply(src, L(src, 'ev.cr_started', { name = name, m = math.floor(STEP) }))
    elseif sub == 'stop' then
        local r = Rec[src]
        if not r then return EV.Reply(src, L(src, 'ev.cr_not_rec')) end
        Rec[src] = nil
        if #r.pts < 2 then
            guardLog(src, ('convoyroute "%s" discarded, %d points'):format(r.name, #r.pts))
            return EV.Reply(src, L(src, 'ev.cr_too_short'))
        end
        local ok, id = pcall(function()
            return ox():insert_async('INSERT INTO bs_convoy_routes (name, points, enabled, created_by) VALUES (?, ?, 1, ?)',
                { r.name, json.encode(r.pts), who(src):sub(1, 64) })
        end)
        if not ok or not id then return EV.Reply(src, L(src, 'ev.cr_db_fail')) end
        reload()
        guardLog(src, ('convoyroute saved #%s "%s" with %d points'):format(tostring(id), r.name, #r.pts))
        EV.Reply(src, L(src, 'ev.cr_saved', { id = id, name = r.name, n = #r.pts }))
    elseif sub == 'list' then
        local any = false
        for i, r in ipairs((Events.Convoy and Events.Convoy.routes) or {}) do
            any = true
            EV.Reply(src, L(src, 'ev.cr_row_cfg', { name = r.name, n = #(r.points or {}), s = L(src, r.enabled == false and 'ev.cr_off' or 'ev.cr_on') }))
        end
        for _, r in ipairs(DB) do
            any = true
            EV.Reply(src, L(src, 'ev.cr_row', { id = r.id, name = r.name, n = #r.points, s = L(src, r.enabled and 'ev.cr_on' or 'ev.cr_off'), by = r.by }))
        end
        if not any then EV.Reply(src, L(src, 'ev.cr_none')) end
    elseif sub == 'delete' or sub == 'toggle' then
        local id = tonumber(args[2])
        local row = id and findRow(id)
        if not row then return EV.Reply(src, L(src, 'ev.cr_notfound')) end
        if sub == 'delete' then
            pcall(function() ox():query_async('DELETE FROM bs_convoy_routes WHERE id = ?', { id }) end)
            reload()
            guardLog(src, ('convoyroute deleted #%d "%s"'):format(id, row.name))
            EV.Reply(src, L(src, 'ev.cr_deleted', { id = id, name = row.name }))
        else
            local v = row.enabled and 0 or 1
            pcall(function() ox():query_async('UPDATE bs_convoy_routes SET enabled = ? WHERE id = ?', { v, id }) end)
            reload()
            guardLog(src, ('convoyroute #%d "%s" %s'):format(id, row.name, v == 1 and 'enabled' or 'disabled'))
            EV.Reply(src, L(src, 'ev.cr_toggled', { id = id, name = row.name, s = L(src, v == 1 and 'ev.cr_on' or 'ev.cr_off') }))
        end
    else
        EV.Reply(src, L(src, 'ev.cr_usage'))
    end
end, false)
