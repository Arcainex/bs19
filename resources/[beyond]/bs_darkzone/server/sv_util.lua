-- Shared server helpers for bs_darkzone.

DZU = {}

function DZU.S() return DZ.Settings end
function DZU.on() return DZ.Settings.enabled == true end
function DZU.started(res) return GetResourceState(res) == 'started' end

function DZU.isAdmin(src)
    if src == 0 then return true end
    if DZU.started('bs_admin') then
        local ok, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and yes == true then return true end
    end
    for _, ace in ipairs(DZ.Settings.adminAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

function DZU.player(src)
    local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
    return ok and p or nil
end

function DZU.charId(src)
    local p = DZU.player(src)
    return p and p.charId or nil
end

-- Admin actions go to bs_guard_log (kind dz_admin), like the other F1 editors.
function DZU.log(src, detail, kind)
    local c = vector3(0, 0, 0)
    local lic, cid, name = nil, nil, 'console'
    if src and src > 0 then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then c = GetEntityCoords(ped) end
        lic = GetPlayerIdentifierByType(src, 'license')
        cid = DZU.charId(src)
        name = (GetPlayerName(src) or '?'):sub(1, 64)
    end
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src or 0, lic, cid, name, kind or 'dz_admin', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

function DZU.pos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function DZU.alive(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then return false end
    local st = Player(src).state
    return not (st.bsDead or st.bsDowned)
end

function DZU.d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function DZU.players()
    local out = {}
    for _, v in ipairs(GetPlayers()) do out[#out + 1] = tonumber(v) end
    return out
end

function DZU.notify(src, kind, key, vars, duration)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = Lp(src, key, vars), duration = duration })
end

-- Same message to a set of players, each in their own language. Chat too when bs_chat runs.
function DZU.broadcast(key, vars, kind, filter)
    for _, p in ipairs(DZU.players()) do
        if not filter or filter(p) then
            DZU.notify(p, kind or 'info', key, vars, 6000)
            if DZU.started('bs_chat') then
                pcall(function() exports.bs_chat:Send(p, Lp(p, 'dz.radio'), Lp(p, key, vars), { 200, 60, 60 }) end)
            end
        end
    end
end

function DZU.roll(tbl)
    local out = {}
    for _, row in ipairs(tbl or {}) do
        if math.random() <= (row.chance or 1.0) then
            out[#out + 1] = { item = row.item, amount = math.random(row.min or 1, math.max(row.min or 1, row.max or 1)) }
        end
    end
    return out
end

function DZU.itemExists(name)
    local ok, def = pcall(function() return exports.bs_inventory:GetItem(name) end)
    return ok and def ~= nil
end

-- bs_zombies event spawns, all guarded.
function DZU.spawn(x, y, kind, tag, hpScale)
    if not DZU.started('bs_zombies') then return nil end
    local ok, id = pcall(function()
        return exports.bs_zombies:EventSpawn(x, y, kind or 'walker', { tag = tag, hpScale = hpScale })
    end)
    return ok and id or nil
end

function DZU.count(tag)
    if not DZU.started('bs_zombies') then return 0 end
    local ok, n = pcall(function() return exports.bs_zombies:EventCount(tag) end)
    return ok and tonumber(n) or 0
end

function DZU.drive(tag, x, y, z)
    if not DZU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventDrive(tag, x, y, z, 120) end)
end

function DZU.untag(tag)
    if not DZU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventClear(tag, true) end)
end

function DZU.noise(x, y, z, loud)
    if not DZU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventNoise(x, y, z, loud or 200.0, 'event') end)
end

function DZU.ring(x, y, rmin, rmax)
    local a = math.random() * math.pi * 2
    local d = rmin + math.random() * math.max(0.0, rmax - rmin)
    return x + math.cos(a) * d, y + math.sin(a) * d
end

function DZU.stateSave(k, v)
    exports.oxmysql:execute('INSERT INTO `bs_dz_state` (`k`,`v`) VALUES (?,?) ON DUPLICATE KEY UPDATE `v` = VALUES(`v`)', { k, json.encode(v) })
end

function DZU.stateLoad(k)
    local row = exports.oxmysql:single_async('SELECT `v` FROM `bs_dz_state` WHERE `k` = ?', { k })
    if not row then return nil end
    local ok, v = pcall(json.decode, row.v)
    return ok and v or nil
end
