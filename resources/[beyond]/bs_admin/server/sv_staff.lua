-- bs_admin - player management behind the F10 Advanced view, plus the actions the chat commands use

local A = BSAdmin
local actions = A.actions

local lastPos = {}   -- [src] = where they were before the last goto/bring, for RETURN
local frozen = {}    -- [src] = true while frozen by staff

local function fail(src, key, vars) return { ok = false, error = Lp(src, key, vars) } end
local function online(id) id = tonumber(id); return (id and GetPlayerName(id)) and id or nil end
local function staffName(src) return src == 0 and 'console' or (GetPlayerName(src) or '?') end
local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end
local function x(sql, p) return exports.oxmysql:execute_async(sql, p or {}) end
local function cleanText(s, max) return tostring(s or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, max) end
local function up(res) return GetResourceState(res) == 'started' end

local function pedPos(id)
    local ped = GetPlayerPed(id)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function allowTeleport(id)
    if up('bs_guard') then pcall(function() exports.bs_guard:Allow(id, 'teleport', 10000) end) end
end

local function identifierOf(src)
    local ok, id = pcall(function() return exports.bs_core:PrimaryIdentifier(src) end)
    return ok and id or nil
end

local function userIdOf(identifier)
    if not identifier then return nil end
    local row = q('SELECT `id` FROM `bs_users` WHERE `identifier` = ? LIMIT 1', { identifier })[1]
    return row and tonumber(row.id) or nil
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    Wait(3000)
    x([[CREATE TABLE IF NOT EXISTS `bs_admin_notes` (
        `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier`  VARCHAR(191) NOT NULL,
        `kind`        VARCHAR(8) NOT NULL DEFAULT 'note',
        `text`        VARCHAR(400) NOT NULL,
        `by_name`     VARCHAR(64) NULL,
        `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `ix_bs_admin_notes_identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
end)

AddEventHandler('playerDropped', function()
    lastPos[source] = nil
    frozen[source] = nil
end)

-- Teleports: remember where people were so RETURN can put them back.

local baseGoto, baseBring = actions['goto'], actions.bring

actions['goto'] = function(src, args)
    local before = pedPos(src)
    local res = baseGoto(src, args)
    if res and res.ok and before then lastPos[src] = before end
    return res
end

actions.bring = function(src, args)
    local target = online(args.target)
    local before = target and pedPos(target)
    local res = baseBring(src, args)
    if res and res.ok and before then lastPos[target] = before end
    return res
end

function actions.returnPlayer(src, args)
    local target = online(args.target) or src
    local p = lastPos[target]
    if not p then return fail(src, 'admin.u.no_return') end
    allowTeleport(target)
    -- teleportTo adds 1 m, the stored point is the ped's centre
    TriggerClientEvent('bs:admin:teleportTo', target, p.x, p.y, p.z - 1.0)
    lastPos[target] = nil
    return { ok = true }
end

function actions.freeze(src, args)
    local target = online(args.target)
    if not target or target == src then return fail(src, 'admin.u.pick_other') end
    frozen[target] = (not frozen[target]) or nil
    TriggerClientEvent('bs:admin:freeze', target, frozen[target] == true)
    TriggerClientEvent('bs:ui:notify', target, { type = 'warn', duration = 5000,
        message = Lp(target, frozen[target] and 'admin.u.you_frozen' or 'admin.u.you_unfrozen') })
    return { ok = true, frozen = frozen[target] == true }
end

function actions.kill(src, args)
    local target = online(args.target)
    if not target then return fail(src, 'admin.c.no_player') end
    TriggerClientEvent('bs:admin:kill', target)
    return { ok = true }
end

-- Bans use bs_bans (checked by bs_core on connect). hours 0 = permanent.

function actions.ban(src, args)
    local target = online(args.target)
    if not target or target == src then return fail(src, 'admin.u.pick_other') end
    local hours = math.max(0, math.min(24 * 365, math.floor(tonumber(args.hours) or 0)))
    local reason = cleanText(args.reason, 200)
    if reason == '' then reason = 'No reason given' end
    local uid = userIdOf(identifierOf(target))
    if not uid then return fail(src, 'admin.u.no_account') end

    exports.oxmysql:insert_async(
        'INSERT INTO `bs_bans` (`user_id`, `reason`, `issued_by`, `expires_at`) VALUES (?, ?, ?, IF(? > 0, DATE_ADD(NOW(), INTERVAL ? HOUR), NULL))',
        { uid, reason, staffName(src):sub(1, 96), hours, hours })
    DropPlayer(target, ('Banned: %s (%s)'):format(reason, hours > 0 and (hours .. 'h') or 'permanent'))
    return { ok = true }
end

function actions.unban(src, args)
    local id = math.floor(tonumber(args.id) or 0)
    if id < 1 then return fail(src, 'admin.u.bad_input') end
    x('UPDATE `bs_bans` SET `expires_at` = NOW() WHERE `id` = ? AND (`expires_at` IS NULL OR `expires_at` > NOW())', { id })
    return { ok = true }
end

local BAN_COLS = 'b.`id`, b.`reason`, b.`issued_by` AS `by`, UNIX_TIMESTAMP(b.`created_at`) AS `at`, UNIX_TIMESTAMP(b.`expires_at`) AS `expires`, (b.`expires_at` IS NULL OR b.`expires_at` > NOW()) AS `active`'

-- Active bans on the server, newest first.
function actions.bans()
    local rows = q('SELECT ' .. BAN_COLS .. ', u.`name` FROM `bs_bans` b JOIN `bs_users` u ON u.`id` = b.`user_id` WHERE (b.`expires_at` IS NULL OR b.`expires_at` > NOW()) ORDER BY b.`id` DESC LIMIT 60')
    for _, r in ipairs(rows) do r.active = tonumber(r.active) == 1 end
    return { ok = true, bans = rows }
end

-- Warnings and notes, kept per account. A warning is also shown to the player.

function actions.addNote(src, args)
    local target = online(args.target)
    if not target then return fail(src, 'admin.c.no_player') end
    local kind = args.kind == 'warn' and 'warn' or 'note'
    local text = cleanText(args.text, 400)
    if #text < 2 then return fail(src, 'admin.u.bad_input') end
    local ident = identifierOf(target)
    if not ident then return fail(src, 'admin.u.no_account') end
    exports.oxmysql:insert_async('INSERT INTO `bs_admin_notes` (`identifier`, `kind`, `text`, `by_name`) VALUES (?, ?, ?, ?)',
        { ident, kind, text, staffName(src):sub(1, 64) })
    if kind == 'warn' then
        TriggerClientEvent('bs:ui:announce', target, { title = Lp(target, 'admin.u.warn_title'), text = text, duration = 12 })
    end
    return { ok = true }
end

function actions.delNote(src, args)
    local id = math.floor(tonumber(args.id) or 0)
    if id < 1 then return fail(src, 'admin.u.bad_input') end
    x('DELETE FROM `bs_admin_notes` WHERE `id` = ?', { id })
    return { ok = true }
end

-- Everything the PLAYER view shows about one online player.
function actions.playerInfo(src, args)
    local target = online(args.target)
    if not target then return fail(src, 'admin.c.no_player') end

    local ped = GetPlayerPed(target)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local okS, sum = pcall(function() return exports.bs_core:GetPlayerSummary(target) end)
    sum = okS and sum or nil
    local fac = nil
    if up('bs_factions') then
        local okF, f = pcall(function() return exports.bs_factions:GetFactionSummary(target) end)
        if okF and f and f.factionId then
            local okL, label = pcall(function() return exports.bs_factions:RankLabel(f.rank, f.factionId) end)
            fac = { id = f.factionId, label = f.label, rank = f.rank, rankLabel = okL and label or f.rank }
        end
    end

    local ident = identifierOf(target)
    local uid = userIdOf(ident)
    local notes = ident and q('SELECT `id`, `kind`, `text`, `by_name` AS `by`, UNIX_TIMESTAMP(`created_at`) AS `at` FROM `bs_admin_notes` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT 40', { ident }) or {}
    local bans = uid and q('SELECT ' .. BAN_COLS .. ' FROM `bs_bans` b WHERE b.`user_id` = ? ORDER BY b.`id` DESC LIMIT 10', { uid }) or {}
    for _, r in ipairs(bans) do r.active = tonumber(r.active) == 1 end
    local warns = 0
    for _, n in ipairs(notes) do if n.kind == 'warn' then warns = warns + 1 end end

    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(target)) do
        if not id:find('^ip:') then ids[#ids + 1] = id end
    end

    return { ok = true, info = {
        source = target, name = GetPlayerName(target), ping = GetPlayerPing(target),
        character = sum and sum.name, charId = sum and sum.charId, level = sum and sum.level,
        class = sum and sum.class, cash = sum and sum.accounts and sum.accounts.cash,
        bank = sum and sum.accounts and sum.accounts.bank, playtime = sum and sum.playtime,
        health = (ped and ped ~= 0) and GetEntityHealth(ped) or 0,
        armour = (ped and ped ~= 0) and GetPedArmour(ped) or 0,
        coords = { x = c.x, y = c.y, z = c.z },
        faction = fac, frozen = frozen[target] == true, canReturn = lastPos[target] ~= nil,
        identifiers = ids, notes = notes, bans = bans, warnings = warns,
    } }
end

-- bs_guard_log rows about this player: their own detections and staff actions aimed at them.
function actions.playerLogs(src, args)
    local target = online(args.target)
    if not target then return fail(src, 'admin.c.no_player') end
    local lic = GetPlayerIdentifierByType(target, 'license')
    if not lic then return { ok = true, rows = {} } end
    local rows = q('SELECT `id`, UNIX_TIMESTAMP(`created_at`) AS `at`, `kind`, `confidence`, `name`, `details` FROM `bs_guard_log` WHERE `license` = ? OR `details` LIKE ? ORDER BY `id` DESC LIMIT 40',
        { lic, '%' .. lic .. '%' })
    return { ok = true, rows = rows }
end

-- Inventory view / edit

function actions.invView(src, args)
    if not up('bs_inventory') then return fail(src, 'admin.c.not_running', { res = 'bs_inventory' }) end
    local target = online(args.target) or src
    local counts = exports.bs_inventory:ItemCounts(target) or {}
    local out = {}
    for item, n in pairs(counts) do
        local def = exports.bs_inventory:GetItem(item)
        out[#out + 1] = { item = item, label = def and def.label or item, amount = n }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return { ok = true, items = out }
end

function actions.removeitem(src, args)
    if not up('bs_inventory') then return fail(src, 'admin.c.not_running', { res = 'bs_inventory' }) end
    local target = online(args.target) or src
    local item = tostring(args.item or '')
    if not exports.bs_inventory:GetItem(item) then return fail(src, 'admin.c.unknown_item', { item = item }) end
    local have = exports.bs_inventory:CountItem(target, item) or 0
    local amount = args.all and have or math.max(1, math.floor(tonumber(args.amount) or 1))
    amount = math.min(amount, have)
    if amount < 1 then return fail(src, 'admin.u.none_left') end
    if not exports.bs_inventory:RemoveItem(target, item, amount) then return fail(src, 'admin.u.bad_input') end
    return { ok = true, amount = amount }
end

function actions.takemoney(src, args)
    local target = online(args.target) or src
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return fail(src, 'admin.u.bad_input') end
    if not exports.bs_core:RemoveMoney(target, args.account == 'bank' and 'bank' or 'cash', amount, 'admin menu') then
        return fail(src, 'admin.u.not_enough')
    end
    return { ok = true }
end

-- Faction and rank, through bs_factions' own rank rules.

function actions.factionList(src)
    if not up('bs_factions') then return { ok = true, factions = {} } end
    local ok, list = pcall(function() return exports.bs_factions:AdminFactionList() end)
    return { ok = true, factions = ok and list or {} }
end

function actions.setFaction(src, args)
    if not up('bs_factions') then return fail(src, 'admin.c.not_running', { res = 'bs_factions' }) end
    local target = online(args.target)
    local okS, sum = pcall(function() return exports.bs_core:GetPlayerSummary(target or -1) end)
    local charId = okS and sum and sum.charId
    if not charId then return fail(src, 'admin.c.no_player') end
    local factionId = args.faction ~= '' and args.faction or nil
    local ok, done, err = pcall(function() return exports.bs_factions:AdminSetMember(charId, factionId, args.rank) end)
    if not ok or not done then return { ok = false, error = (ok and err) or 'bs_factions refused' } end
    return { ok = true }
end

-- Server, world and broadcast.

function actions.announce(src, args)
    local text = cleanText(args.text, 400)
    if #text < 1 then return fail(src, 'admin.u.bad_input') end
    local title = cleanText(args.title, 60)
    local seconds = math.max(3, math.min(30, math.floor(tonumber(args.duration) or 10)))
    TriggerClientEvent('bs:ui:announce', -1, { title = title ~= '' and title or nil, text = text, duration = seconds, by = staffName(src) })
    return { ok = true }
end

function actions.clearZombies(src, args)
    if not up('bs_zombies') then return fail(src, 'admin.c.not_running', { res = 'bs_zombies' }) end
    local p = pedPos(src)
    if not p then return fail(src, 'admin.u.ingame') end
    local radius = math.max(1, math.min(500, tonumber(args.radius) or 50))
    local ok, n = pcall(function() return exports.bs_zombies:ClearRadius(p.x, p.y, radius) end)
    if not ok then return fail(src, 'admin.c.failed', { err = 'bs_zombies' }) end
    return { ok = true, count = n or 0, radius = radius }
end

function actions.blackout(src, args)
    if not up('bs_world') then return fail(src, 'admin.c.not_running', { res = 'bs_world' }) end
    local on = args.on
    if on == nil then on = not exports.bs_world:Blackout() end
    local now = exports.bs_world:SetBlackout(on == true)
    return { ok = true, on = now, note = Lp(src, now and 'admin.c.blackout_on' or 'admin.c.blackout_off') }
end

-- POWER tab: generator zones from bs_world
local function powerZone(src, args)
    if not up('bs_world') then return nil, fail(src, 'admin.c.not_running', { res = 'bs_world' }) end
    local id = tostring(args.zone or '')
    local z = exports.bs_world:PowerZone(id)
    if not z then return nil, { ok = false, error = 'unknown zone' } end
    return z
end

function actions.powerList(src)
    if not up('bs_world') then return fail(src, 'admin.c.not_running', { res = 'bs_world' }) end
    return { ok = true, zones = exports.bs_world:PowerZones() or {}, blackout = exports.bs_world:Blackout() }
end

function actions.powerToggle(src, args)
    local z, err = powerZone(src, args)
    if not z then return err end
    local on = args.on
    if type(on) ~= 'boolean' then on = not z.on end
    exports.bs_world:SetZonePower(z.id, on)
    return { ok = true, note = ('%s: %s'):format(z.label, on and 'ON' or 'OFF') }
end

function actions.powerRefuel(src, args)
    local z, err = powerZone(src, args)
    if not z then return err end
    exports.bs_world:RefuelZone(z.id, 100.0)
    return { ok = true, note = ('%s: fuel 100%%'):format(z.label) }
end

function actions.powerRepair(src, args)
    local z, err = powerZone(src, args)
    if not z then return err end
    exports.bs_world:RepairZone(z.id)
    return { ok = true, note = ('%s: repaired'):format(z.label) }
end

function actions.powerTp(src, args)
    if src == 0 then return fail(src, 'admin.u.ingame') end
    local z, err = powerZone(src, args)
    if not z then return err end
    allowTeleport(src)
    TriggerClientEvent('bs:admin:tpCoords', src, z.x + 0.0, z.y + 0.0, z.z + 0.0)
    return { ok = true, note = z.label }
end

function actions.powerRestore(src)
    if not up('bs_world') then return fail(src, 'admin.c.not_running', { res = 'bs_world' }) end
    exports.bs_world:RestoreAll()
    return { ok = true, note = Lp(src, 'admin.p_restored') }
end

-- Gas station fuel (bs_vehicles). Resets on restart; this sets it for the running session.
function actions.pumpList(src)
    if not up('bs_vehicles') then return fail(src, 'admin.c.not_running', { res = 'bs_vehicles' }) end
    return { ok = true, stations = exports.bs_vehicles:PumpStations() or {} }
end

function actions.pumpSet(src, args)
    if not up('bs_vehicles') then return fail(src, 'admin.c.not_running', { res = 'bs_vehicles' }) end
    local liters = tonumber(args.liters)
    if not liters or not exports.bs_vehicles:PumpSetFuel(tostring(args.station or ''), liters) then
        return { ok = false, error = 'unknown station' }
    end
    return { ok = true, note = ('%s: %d L'):format(tostring(args.station), math.floor(liters)) }
end

function actions.worldState(src)
    if not up('bs_world') then return fail(src, 'admin.c.not_running', { res = 'bs_world' }) end
    local st = exports.bs_world:WorldState() or {}
    st.blackout = exports.bs_world:Blackout()
    return { ok = true, world = st }
end

function actions.serverStats(src)
    local players = #GetPlayers()
    local started = 0
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and GetResourceState(name) == 'started' then started = started + 1 end
    end
    local walkers = nil
    if up('bs_zombies') then
        local ok, n = pcall(function() return exports.bs_zombies:Total() end)
        walkers = ok and n or nil
    end
    local world = actions.worldState(src)
    local active = q('SELECT COUNT(*) AS `n` FROM `bs_bans` WHERE `expires_at` IS NULL OR `expires_at` > NOW()')[1]
    return { ok = true, stats = {
        players = players, maxPlayers = GetConvarInt('sv_maxclients', 32),
        uptime = math.floor(GetGameTimer() / 1000),
        vehicles = #GetAllVehicles(), peds = #GetAllPeds(), objects = #GetAllObjects(),
        walkers = walkers, resources = started,
        activeBans = active and tonumber(active.n) or 0,
        world = world.ok and world.world or nil,
    } }
end

-- Owned cars that /dv put away, and a way to bring one back out where you stand.
function actions.storedCars()
    local rows = q([[SELECT v.`plate`, v.`model`, c.`first_name`, c.`last_name`
        FROM `bs_vehicles` v LEFT JOIN `bs_characters` c ON c.`id` = v.`owner_character_id`
        WHERE v.`stored` = 1 ORDER BY v.`id` DESC LIMIT 60]])
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { plate = r.plate, model = r.model,
            owner = r.first_name and ((r.first_name .. ' ' .. (r.last_name or '')):gsub('%s+$', '')) or '-' }
    end
    return { ok = true, cars = out }
end

function actions.unstoreVehicle(src, args)
    if not up('bs_vehicles') then return fail(src, 'admin.c.not_running', { res = 'bs_vehicles' }) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return fail(src, 'admin.u.ingame') end
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local rad = math.rad(h)
    local ok, done = pcall(function()
        return exports.bs_vehicles:AdminUnstore(tostring(args.plate or ''), c.x - math.sin(rad) * 4.0, c.y + math.cos(rad) * 4.0, c.z, h)
    end)
    if not ok or not done then return fail(src, 'admin.u.not_stored') end
    return { ok = true }
end
