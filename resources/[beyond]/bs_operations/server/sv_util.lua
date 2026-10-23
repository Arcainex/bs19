-- Shared server helpers for bs_operations.

OpsU = {}

function OpsU.now() return os.time() end

function OpsU.started(res) return GetResourceState(res) == 'started' end

function OpsU.isAdmin(src)
    if src == 0 then return true end
    if OpsU.started('bs_admin') then
        local ok, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and yes == true then return true end
    end
    for _, ace in ipairs(Ops.Settings.adminAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

-- Admin actions go to bs_guard_log (kind ops_admin), like the other F1 editors.
function OpsU.log(src, detail, kind)
    local c = vector3(0, 0, 0)
    local lic, cid, name = nil, nil, 'console'
    if src and src > 0 then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then c = GetEntityCoords(ped) end
        lic = GetPlayerIdentifierByType(src, 'license')
        local p = exports.bs_core:GetPlayer(src)
        cid = p and p.charId or nil
        name = (GetPlayerName(src) or '?'):sub(1, 64)
    end
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src or 0, lic, cid, name, kind or 'ops_admin', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

function OpsU.player(src)
    local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
    return ok and p or nil
end

function OpsU.charId(src)
    local p = OpsU.player(src)
    return p and p.charId or nil
end

function OpsU.faction(src)
    if not OpsU.started('bs_factions') then return nil end
    local ok, f = pcall(function() return exports.bs_factions:GetFaction(src) end)
    return ok and type(f) == 'string' and f ~= '' and f or nil
end

function OpsU.pos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function OpsU.alive(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if GetEntityHealth(ped) <= 0 then return false end
    local st = Player(src).state
    return not (st.bsDead or st.bsDowned)
end

function OpsU.dead(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return GetEntityHealth(ped) <= 0 or Player(src).state.bsDead == true
end

function OpsU.dist2(a, x, y)
    local dx, dy = a.x - x, a.y - y
    return math.sqrt(dx * dx + dy * dy)
end

function OpsU.players()
    local out = {}
    for _, v in ipairs(GetPlayers()) do out[#out + 1] = tonumber(v) end
    return out
end

function OpsU.notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = Lp(src, key, vars) })
end

-- Same message to everyone, each in their own language. Chat too when bs_chat runs.
function OpsU.broadcast(key, vars, kind, filter)
    for _, p in ipairs(OpsU.players()) do
        if not filter or filter(p) then
            OpsU.notify(p, kind or 'info', key, vars)
            if OpsU.started('bs_chat') then
                pcall(function() exports.bs_chat:Send(p, Lp(p, 'ops.radio'), Lp(p, key, vars), { 230, 160, 60 }) end)
            end
        end
    end
end

function OpsU.factionLabel(fid)
    if not fid then return '?' end
    for _, z in ipairs((Zones and Zones.FactionSafe) or {}) do
        if z.faction == fid and z.kind == 'safezone' then return (z.label:gsub(' Safezone$', '')) end
    end
    return fid
end

function OpsU.rollLoot(tbl)
    local out = {}
    for _, row in ipairs(tbl or {}) do
        if math.random() <= (row.chance or 1.0) then
            out[#out + 1] = { item = row.item, amount = math.random(row.min or 1, math.max(row.min or 1, row.max or 1)) }
        end
    end
    return out
end

-- Pays a player. xp gets the power station buff on top.
function OpsU.pay(src, r, reason)
    if not r then return end
    -- server-side buff state, not the statebag (clients can write their own)
    local mult = 1.0 + ((Power and Power.XpPct and Power.XpPct(src)) or 0) / 100
    if (r.xp or 0) > 0 then pcall(function() exports.bs_core:AddXP(src, math.floor(r.xp * mult), reason) end) end
    if (r.money or 0) > 0 then pcall(function() exports.bs_core:AddMoney(src, 'cash', math.floor(r.money), reason) end) end
    if (r.rep or 0) > 0 and OpsU.started('bs_factions') then
        pcall(function() exports.bs_factions:AddReputation(src, math.floor(r.rep), reason) end)
    end
    for _, it in ipairs(r.items or {}) do
        pcall(function() exports.bs_inventory:GiveItem(src, it.item, it.amount or 1) end)
    end
end

function OpsU.factionXp(fid, amount, reason)
    if not fid or (amount or 0) <= 0 or not OpsU.started('bs_factions') then return end
    pcall(function() exports.bs_factions:AddFactionXP(fid, math.floor(amount), reason) end)
end

function OpsU.spawn(x, y, brute, tag, hpScale)
    if not OpsU.started('bs_zombies') then return nil end
    local ok, id = pcall(function()
        return exports.bs_zombies:EventSpawn(x, y, brute and 'brute' or 'walker', { tag = tag, hpScale = hpScale })
    end)
    return ok and id or nil
end

function OpsU.ring(x, y, rmin, rmax)
    local a = math.random() * math.pi * 2
    local d = rmin + math.random() * math.max(0.0, rmax - rmin)
    return x + math.cos(a) * d, y + math.sin(a) * d
end

function OpsU.alive_count(tag)
    if not OpsU.started('bs_zombies') then return 0 end
    local ok, n = pcall(function() return exports.bs_zombies:EventCount(tag) end)
    return ok and tonumber(n) or 0
end

function OpsU.drive(tag, x, y, z)
    if not OpsU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventDrive(tag, x, y, z, 300) end)
end

function OpsU.clear(tag, keep)
    if not OpsU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventClear(tag, keep) end)
end

function OpsU.noise(x, y, z, loud)
    if not OpsU.started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventNoise(x, y, z, loud or 200.0, 'event') end)
end

-- Members of one faction online.
function OpsU.factionMembers(fid)
    local out = {}
    for _, p in ipairs(OpsU.players()) do if OpsU.faction(p) == fid then out[#out + 1] = p end end
    return out
end

-- Simple key/value rows in bs_ops_state.
function OpsU.stateSave(k, v)
    exports.oxmysql:execute('INSERT INTO `bs_ops_state` (`k`,`v`) VALUES (?,?) ON DUPLICATE KEY UPDATE `v` = VALUES(`v`)', { k, json.encode(v) })
end

function OpsU.stateLoad(k)
    local row = exports.oxmysql:single_async('SELECT `v` FROM `bs_ops_state` WHERE `k` = ?', { k })
    if not row then return nil end
    local ok, v = pcall(json.decode, row.v)
    return ok and v or nil
end
