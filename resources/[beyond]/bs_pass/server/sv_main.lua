-- Wasteland Pass server. Everything is decided here: XP, challenges, claims, spins, season end.
local P = {}          -- [cid] = progress row (online characters)
local srcOf = {}      -- [cid] = src
local season = nil    -- { id, started, ends }
local dirty = {}
local busy = {}       -- per src action lock

local function now() return os.time() end
local function dayKey() return now() // 86400 end
local function weekKey() return (now() // 86400 + 3) // 7 end
local function S() return Pass.Settings end

local function charId(src)
    local ok, p = pcall(function() return exports.bs_core:GetPlayer(tonumber(src)) end)
    return ok and p and tonumber(p.charId) or nil
end

local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_pass_season` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `started_at` INT UNSIGNED NOT NULL, `ends_at` INT UNSIGNED NOT NULL,
        `closed` TINYINT(1) NOT NULL DEFAULT 0, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_pass_progress` (
        `char_id` INT UNSIGNED NOT NULL, `season` INT UNSIGNED NOT NULL, `xp` INT UNSIGNED NOT NULL DEFAULT 0,
        `tokens` INT UNSIGNED NOT NULL DEFAULT 0, `claimed` VARCHAR(255) NOT NULL DEFAULT '',
        `day_key` INT NOT NULL DEFAULT 0, `day_xp` INT UNSIGNED NOT NULL DEFAULT 0, `rerolls` TINYINT UNSIGNED NOT NULL DEFAULT 0,
        `week_key` INT NOT NULL DEFAULT 0, `dailies` TEXT NULL, `weeklies` TEXT NULL, `spins` INT UNSIGNED NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`char_id`), KEY `idx_bs_pass_rank` (`season`, `xp`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_pass_pending` (
        `char_id` INT UNSIGNED NOT NULL, `cash` INT UNSIGNED NOT NULL DEFAULT 0, `xp` INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`char_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bs_pass_vehicles` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `char_id` INT UNSIGNED NOT NULL, `plate` VARCHAR(16) NOT NULL,
        `model` VARCHAR(32) NOT NULL, `delivered` TINYINT(1) NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `idx_bs_pass_veh_char` (`char_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

-- Season

local function newSeason()
    local st = now()
    local en = st + math.max(1, math.floor(S().seasonDays or 30)) * 86400
    local id = MySQL.insert.await('INSERT INTO `bs_pass_season` (`started_at`,`ends_at`) VALUES (?,?)', { st, en })
    season = { id = id, started = st, ends = en }
    print(('^5[bs_pass]^7 season %d started, ends %s'):format(id, os.date('!%Y-%m-%d %H:%M', en)))
end

local function loadSeason()
    local row = MySQL.single.await('SELECT * FROM `bs_pass_season` WHERE `closed` = 0 ORDER BY `id` DESC LIMIT 1')
    if row then season = { id = row.id, started = row.started_at, ends = row.ends_at } else newSeason() end
end

-- Progress

local function tierOf(xp) return math.min(S().tiers, xp // math.max(1, S().xpPerTier)) end

local function pickChallenges(pool, n, exclude)
    local bag, out = {}, {}
    for _, c in ipairs(pool) do if not (exclude and exclude[c.id]) then bag[#bag + 1] = c end end
    for _ = 1, math.min(n, #bag) do
        local c = table.remove(bag, math.random(#bag))
        local steps = math.max(0, (c.max - c.min) // math.max(1, c.step))
        out[#out + 1] = { id = c.id, kind = c.kind, target = c.min + math.random(0, steps) * c.step, xp = c.xp, p = 0, done = false, accepted = false }
    end
    return out
end

local function fresh(cid)
    return { char_id = cid, season = season.id, xp = 0, tokens = 0, claimed = '', day_key = 0, day_xp = 0, rerolls = 0,
             week_key = 0, dailies = {}, weeklies = {}, spins = 0 }
end

-- Day/week rollover and season change, applied on every touch.
local function roll(p)
    if p.season ~= season.id then
        local keep = p.char_id
        for k, v in pairs(fresh(keep)) do p[k] = v end
    end
    local d, w = dayKey(), weekKey()
    if p.day_key ~= d then
        p.day_key, p.day_xp, p.rerolls = d, 0, 0
        p.dailies = pickChallenges(Pass.Challenges.Daily, Pass.Challenges.daily)
        dirty[p.char_id] = true
    end
    if p.week_key ~= w then
        p.week_key = w
        p.weeklies = pickChallenges(Pass.Challenges.Weekly, Pass.Challenges.weekly)
        dirty[p.char_id] = true
    end
end

local function decode(s) local ok, t = pcall(json.decode, s or '[]'); return (ok and type(t) == 'table') and t or {} end

local function load(cid)
    local row = MySQL.single.await('SELECT * FROM `bs_pass_progress` WHERE `char_id` = ?', { cid })
    local p
    if row then
        p = row
        p.dailies, p.weeklies = decode(row.dailies), decode(row.weeklies)
        p.updated_at = nil
    else
        p = fresh(cid)
    end
    roll(p)
    dirty[cid] = true
    return p
end

local function save(cid)
    local p = P[cid]
    if not p then return end
    dirty[cid] = nil
    MySQL.query('INSERT INTO `bs_pass_progress` (`char_id`,`season`,`xp`,`tokens`,`claimed`,`day_key`,`day_xp`,`rerolls`,`week_key`,`dailies`,`weeklies`,`spins`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE `season`=VALUES(`season`),`xp`=VALUES(`xp`),`tokens`=VALUES(`tokens`),`claimed`=VALUES(`claimed`),`day_key`=VALUES(`day_key`),`day_xp`=VALUES(`day_xp`),`rerolls`=VALUES(`rerolls`),`week_key`=VALUES(`week_key`),`dailies`=VALUES(`dailies`),`weeklies`=VALUES(`weeklies`),`spins`=VALUES(`spins`)',
        { cid, p.season, p.xp, p.tokens, p.claimed, p.day_key, p.day_xp, p.rerolls, p.week_key, json.encode(p.dailies), json.encode(p.weeklies), p.spins })
end

local function get(src)
    local cid = charId(src)
    if not cid or not season then return nil end
    local p = P[cid]
    if not p then
        p = load(cid)
        P[cid], srcOf[cid] = p, src
        PS.EnsureMail(cid)
        PS.PayPending(src, cid)
    end
    srcOf[cid] = src
    roll(p)
    return p, cid
end

local function isClaimed(p, t) return p.claimed:sub(t, t) == '1' end
local function setClaimed(p, t)
    local s = p.claimed
    if #s < t then s = s .. string.rep('0', t - #s) end
    p.claimed = s:sub(1, t - 1) .. '1' .. s:sub(t + 1)
end

-- Client view

local function view(src, p, cid)
    local tiers = {}
    for t = 1, S().tiers do tiers[t] = PS.Tier(t) end
    local cars = MySQL.query.await('SELECT `id`,`plate`,`model` FROM `bs_pass_vehicles` WHERE `char_id` = ? AND (`delivered` = 0 OR `delivered` IS NULL)', { cid }) or {}
    return {
        season = season.id, ends = season.ends, now = now(), xp = p.xp, tier = tierOf(p.xp), xpPerTier = S().xpPerTier,
        maxTier = S().tiers, tokens = p.tokens, claimed = p.claimed, dayXp = p.day_xp, dayCap = S().dailyXpCap,
        dayKey = p.day_key, weekKey = p.week_key, dailies = p.dailies, weeklies = p.weeklies, rerollsLeft = math.max(0, Pass.Challenges.rerollsPerDay - p.rerolls),
        tiersList = tiers, symbols = Pass.Slot.Symbols, cars = cars,
        nextDay = (dayKey() + 1) * 86400, nextWeek = ((weekKey() + 1) * 7 - 3) * 86400,
    }
end

local function push(src, cid)
    local p = P[cid]
    if p then TriggerClientEvent('bs_pass:progress', src, { xp = p.xp, tier = tierOf(p.xp), tokens = p.tokens, dayXp = p.day_xp, dailies = p.dailies, weeklies = p.weeklies }) end
end

-- XP

local function addXp(src, p, cid, amount, capped)
    amount = math.floor(amount or 0)
    if amount <= 0 or not S().enabled then return 0 end
    if capped then
        local room = math.max(0, (S().dailyXpCap or 0) - p.day_xp)
        amount = math.min(amount, room)
        if amount <= 0 then return 0 end
        p.day_xp = p.day_xp + amount
    end
    local before = tierOf(p.xp)
    p.xp = math.min(p.xp + amount, S().tiers * S().xpPerTier)
    dirty[cid] = true
    local after = tierOf(p.xp)
    if after > before and src then
        TriggerClientEvent('bs_pass:tierUp', src, after)
        TriggerClientEvent('bs:ui:notify', src, { type = 'success', title = Lp(src, 'pass.title'), message = Lp(src, 'pass.n_tier', { tier = after }) })
    end
    return amount
end

-- Challenges: progress `kind` by n.
local function progress(src, kind, n)
    local p, cid = get(src)
    if not p then return end
    n = n or 1
    local changed = false
    for _, list in ipairs({ p.dailies, p.weeklies }) do
        for _, c in ipairs(list) do
            if c.accepted == true and not c.done and c.kind == kind then
                c.p = math.min(c.target, c.p + n)
                changed = true
                if c.p >= c.target then
                    c.done = true
                    addXp(src, p, cid, c.xp, false)
                    local weekly = list == p.weeklies
                    if weekly then p.tokens = p.tokens + (Pass.Challenges.weeklyTokens or 0) end
                    TriggerClientEvent('bs:ui:notify', src, { type = 'success', title = Lp(src, 'pass.title'), message = Lp(src, 'pass.n_challenge', { xp = c.xp }) })
                    PS.Log(src, 'pass_challenge', ('%s done (+%d xp%s)'):format(c.id, c.xp, weekly and ', +token' or ''), cid)
                end
            end
        end
    end
    if changed then dirty[cid] = true end
    local xp = Pass.XP[kind]
    if xp and xp > 0 then addXp(src, p, cid, xp * n, true) end
    push(src, cid)
end
PS.Progress = progress

-- Hooks

local ACTION = {
    zombie_kill = 'zombie_kill', zombie_kill_brute = 'zombie_kill', zombie_kill_headshot = 'headshot',
    item_crafted = 'craft', resource_gathered = 'gather', wound_treated = 'heal', player_revived = 'heal',
    vehicle_repaired = 'vehicle', horde_cleared = 'event',
}
AddEventHandler('bs:hook:player:action', function(player, actionId)
    local src = type(player) == 'table' and tonumber(player.source)
    local kind = ACTION[actionId]
    if not src or not kind then return end
    progress(src, kind, 1)
    if kind == 'headshot' then progress(src, 'zombie_kill', 1) end
end)

AddEventHandler('bs:jobs:completed', function(src)
    src = tonumber(src)
    if src then progress(src, 'contract', 1) end
end)

-- bs_events fires this the first time a player opens an event crate.
local crateSeen = {}
AddEventHandler('bs:events:crateOpened', function(src, evKey)
    src = tonumber(src)
    if not src then return end
    local k = tostring(src) .. ':' .. tostring(evKey)
    if crateSeen[k] then return end
    crateSeen[k] = true
    progress(src, 'event', 1)
end)

-- Playtime with an AFK check: the server watches the ped, the client is never asked.
local lastPos, lastMove = {}, {}
CreateThread(function()
    while true do
        Wait(60000)
        if S().enabled and season then
            for _, s in ipairs(GetPlayers()) do
                local src = tonumber(s)
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 and charId(src) then
                    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
                    local lp = lastPos[src]
                    if not lp or #(c - lp.c) > (Pass.Afk.moveMeters or 1.5) or math.abs(h - lp.h) > 25.0 then lastMove[src] = now() end
                    lastPos[src] = { c = c, h = h }
                    if now() - (lastMove[src] or 0) < (Pass.Afk.minutes or 5) * 60 then progress(src, 'playtime', 1) end
                end
            end
        end
    end
end)

-- Saves
CreateThread(function()
    while true do
        Wait(15000)
        for cid in pairs(dirty) do save(cid) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for cid, s in pairs(srcOf) do
        if s == src then save(cid); P[cid], srcOf[cid] = nil, nil end
    end
    lastPos[src], lastMove[src], busy[src] = nil, nil, nil
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    local cid = type(player) == 'table' and tonumber(player.charId)
    if cid and P[cid] then save(cid); P[cid], srcOf[cid] = nil, nil end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for cid in pairs(P) do save(cid) end
end)

-- Player actions (all through server callbacks)

local function lock(src)
    if busy[src] and GetGameTimer() - busy[src] < 400 then return false end
    busy[src] = GetGameTimer()
    return true
end

local function acceptChallenge(src, id)
    if not lock(src) or type(id) ~= 'string' then return { ok = false } end
    local cadence, stamp, index, challenge = id:match('^pass:([dw]):(%d+):(%d+):([%w_%-]+)$')
    if not cadence then return { ok = false, error = 'That offer is no longer available.' } end
    local p, cid = get(src)
    if not p then return { ok = false } end
    local period = cadence == 'd' and p.day_key or p.week_key
    local list = cadence == 'd' and p.dailies or p.weeklies
    local c = list[tonumber(index)]
    if tonumber(stamp) ~= period or not c or c.id ~= challenge or c.done then
        return { ok = false, error = 'That offer is no longer available.' }
    end
    c.accepted = true
    dirty[cid] = true
    save(cid)
    push(src, cid)
    return { ok = true, data = view(src, p, cid) }
end
BSB.RegisterCallback('bs_pass:accept', acceptChallenge)
exports('MissionLogAccept', acceptChallenge)

BSB.RegisterCallback('bs_pass:get', function(src)
    if S().menuEnabled == false then return { ok = false } end   -- menu switched off in F1
    local p, cid = get(src)
    if not p then return { ok = false } end
    return { ok = true, data = view(src, p, cid) }
end)

local function claimTier(src, p, cid, t)
    if t < 1 or t > tierOf(p.xp) or isClaimed(p, t) then return nil end
    setClaimed(p, t)
    dirty[cid] = true
    local text, mailed = PS.Deliver(src, cid, PS.Tier(t), function(n) p.tokens = p.tokens + n end)
    PS.Log(src, 'pass_claim', ('S%d tier %d: %s%s'):format(season.id, t, text, mailed and ' (mailbox)' or ''), cid)
    return mailed
end

BSB.RegisterCallback('bs_pass:claim', function(src, tier)
    if not lock(src) then return { ok = false } end
    local p, cid = get(src)
    if not p then return { ok = false } end
    local mailed, n = false, 0
    local from, to = 1, tierOf(p.xp)
    if tier ~= 'all' then from = math.floor(tonumber(tier) or 0); to = from end
    for t = math.max(1, from), to do
        local m = claimTier(src, p, cid, t)
        if m ~= nil then n = n + 1; mailed = mailed or m end
    end
    save(cid)
    return { ok = n > 0, claimed = n, mailed = mailed, data = view(src, p, cid) }
end)

BSB.RegisterCallback('bs_pass:spin', function(src)
    if not lock(src) then return { ok = false } end
    local p, cid = get(src)
    if not p or p.tokens < 1 then return { ok = false, error = 'no_tokens' } end
    p.tokens = p.tokens - 1
    p.spins = p.spins + 1
    local reels, pool, rewards = PS.Spin()
    local text, mailed = PS.Deliver(src, cid, rewards, function(n) p.tokens = p.tokens + n end)
    save(cid)
    PS.Log(src, 'pass_spin', ('S%d %s/%s/%s -> %s: %s%s'):format(season.id, reels[1], reels[2], reels[3], pool, text, mailed and ' (mailbox)' or ''), cid)
    if pool == 'jackpot' then
        TriggerClientEvent('bs:ui:notify', -1, { type = 'info', title = Lp(src, 'pass.title'), message = Lp(src, 'pass.n_jackpot_all', { name = GetPlayerName(src) or '?' }) })
    end
    progress(src, 'spin', 1)
    return { ok = true, reels = reels, pool = pool, rewards = rewards, mailed = mailed, data = view(src, p, cid) }
end)

BSB.RegisterCallback('bs_pass:reroll', function(src, idx)
    if not lock(src) then return { ok = false } end
    local p, cid = get(src)
    idx = math.floor(tonumber(idx) or 0)
    local c = p and p.dailies[idx]
    if not c or c.done or p.rerolls >= Pass.Challenges.rerollsPerDay then return { ok = false } end
    local have = {}
    for _, d in ipairs(p.dailies) do have[d.id] = true end
    local new = pickChallenges(Pass.Challenges.Daily, 1, have)[1]
    if not new then return { ok = false } end
    p.dailies[idx] = new
    p.rerolls = p.rerolls + 1
    save(cid)
    PS.Log(src, 'pass_reroll', ('%s -> %s'):format(c.id, new.id), cid)
    return { ok = true, data = view(src, p, cid) }
end)

BSB.RegisterCallback('bs_pass:mailbox', function(src)
    local p, cid = get(src)
    if not p then return { ok = false } end
    PS.EnsureMail(cid)
    PS.PayPending(src, cid)  -- cash/XP owed from offline deliveries
    exports.bs_inventory:OpenContainerFor(src, PS.MailId(cid))
    return { ok = true }
end)

-- Brings a pass car out next to the player.
BSB.RegisterCallback('bs_pass:car', function(src, id)
    if not lock(src) then return { ok = false } end
    local p, cid = get(src)
    if not p or GetResourceState('bs_vehicles') ~= 'started' then return { ok = false } end
    local row = MySQL.single.await('SELECT * FROM `bs_pass_vehicles` WHERE `id` = ? AND `char_id` = ? AND `delivered` = 0', { tonumber(id), cid })
    if not row then return { ok = false } end
    local ped = GetPlayerPed(src)
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local r = math.rad(h)
    local ok = exports.bs_vehicles:AdminUnstore(row.plate, c.x - math.sin(r) * 4.0, c.y + math.cos(r) * 4.0, c.z, h)
    if not ok then return { ok = false } end
    MySQL.update.await('UPDATE `bs_pass_vehicles` SET `delivered` = 1 WHERE `id` = ?', { row.id })
    PS.Log(src, 'pass_car', ('delivered %s [%s]'):format(row.model, row.plate), cid)
    return { ok = true, data = view(src, p, cid) }
end)

local board, boardAt = {}, 0
BSB.RegisterCallback('bs_pass:leaderboard', function(src)
    if now() - boardAt > 60 then
        boardAt = now()
        board = MySQL.query.await([[SELECT p.`xp`, c.`first_name`, c.`last_name` FROM `bs_pass_progress` p
            JOIN `bs_characters` c ON c.`id` = p.`char_id` WHERE p.`season` = ? ORDER BY p.`xp` DESC LIMIT ?]],
            { season.id, S().leaderboardSize or 25 }) or {}
        for _, r in ipairs(board) do r.tier = tierOf(r.xp); r.name = ('%s %s'):format(r.first_name, r.last_name); r.first_name, r.last_name = nil, nil end
    end
    return { ok = true, rows = board }
end)

-- Season end: every unclaimed reached tier goes to the mailbox, leftover tokens are spun into it.
local function closeSeason()
    local old = season
    for cid in pairs(P) do save(cid) end
    local rows = MySQL.query.await('SELECT * FROM `bs_pass_progress` WHERE `season` = ?', { old.id }) or {}
    for _, row in ipairs(rows) do
        local cid = row.char_id
        local p = P[cid] or row
        local tokens = p.tokens or 0
        local function addTok(n) tokens = tokens + n end
        for t = 1, tierOf(p.xp) do
            if p.claimed:sub(t, t) ~= '1' then
                local text = PS.Deliver(nil, cid, PS.Tier(t), addTok)
                PS.Log(nil, 'pass_autoclaim', ('S%d tier %d: %s'):format(old.id, t, text), cid)
            end
        end
        local guard = 0
        while tokens > 0 and guard < 200 do
            tokens, guard = tokens - 1, guard + 1
            local reels, pool, rewards = PS.Spin()
            local text = PS.Deliver(nil, cid, rewards, addTok)
            PS.Log(nil, 'pass_autospin', ('S%d %s/%s/%s -> %s: %s'):format(old.id, reels[1], reels[2], reels[3], pool, text), cid)
        end
        Wait(0)
    end
    MySQL.update.await('UPDATE `bs_pass_season` SET `closed` = 1 WHERE `id` = ?', { old.id })
    newSeason()
    P = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        TriggerClientEvent('bs:ui:notify', src, { type = 'info', title = Lp(src, 'pass.title'), message = Lp(src, 'pass.n_season') })
    end
end

CreateThread(function()
    ensureTables()
    loadSeason()
    while true do
        Wait(60000)
        if season and now() >= season.ends then
            local ok, err = pcall(closeSeason)
            if not ok then print('^1[bs_pass] season close failed: ' .. tostring(err) .. '^7') end
        end
    end
end)

-- F1 page: tier editor + season tools. bs_config already checked the caller is staff.
local function itemList()
    local ok, items = pcall(function() return exports.bs_inventory:GetItems() end)
    local out = {}
    if ok and type(items) == 'table' then
        for id, d in pairs(items) do out[#out + 1] = { id = id, label = type(d) == 'table' and d.label or id } end
        table.sort(out, function(a, b) return a.id < b.id end)
    end
    return out
end

local function adminState()
    local tiers = {}
    local custom = PS.CustomTiers()
    for t = 1, S().tiers do tiers[t] = { tier = t, rewards = PS.Tier(t), custom = custom[tostring(t)] ~= nil } end
    return { ok = true, tiers = tiers, items = itemList(), season = season }
end

local function cleanRewards(list)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, r in ipairs(list) do
        local t = tostring(r.type or '')
        if t == 'item' and type(r.item) == 'string' then out[#out + 1] = { type = 'item', item = r.item:sub(1, 48), amount = math.max(1, math.floor(tonumber(r.amount) or 1)) }
        elseif t == 'cash' or t == 'xp' or t == 'token' then out[#out + 1] = { type = t, amount = math.max(1, math.floor(tonumber(r.amount) or 1)) }
        elseif t == 'car' and type(r.model) == 'string' then out[#out + 1] = { type = 'car', model = r.model:sub(1, 32) } end
        if #out >= 6 then break end
    end
    return out
end

exports('ConfigExt', function(src, action, a)
    if action == 'state' then return adminState() end
    if action == 'saveTier' and type(a) == 'table' then
        local t = math.floor(tonumber(a.tier) or 0)
        if t < 1 or t > S().tiers then return { ok = false, error = 'Bad tier.' } end
        PS.CustomTiers()[tostring(t)] = cleanRewards(a.rewards)
        PS.SaveCustom()
        PS.Log(src, 'pass_admin', ('tier %d edited'):format(t))
        return adminState()
    elseif action == 'resetTier' then
        PS.CustomTiers()[tostring(math.floor(tonumber(a) or 0))] = nil
        PS.SaveCustom()
        return adminState()
    elseif action == 'endSeason' then
        PS.Log(src, 'pass_admin', 'season ended by staff')
        season.ends = now()
        local ok, err = pcall(closeSeason)
        if not ok then return { ok = false, error = tostring(err) } end
        return adminState()
    elseif action == 'giveXp' then
        local p, cid = get(src)
        if p then addXp(src, p, cid, math.floor(tonumber(a) or 0), false); save(cid) end
        PS.Log(src, 'pass_admin', 'self xp ' .. tostring(a))
        return adminState()
    end
    return { ok = false, error = 'Unknown action.' }
end)

exports('AddXP', function(src, n) local p, cid = get(src); if p then return addXp(src, p, cid, n, true) end end)
exports('Progress', function(src, kind, n) progress(tonumber(src), tostring(kind), tonumber(n) or 1) end)

-- Mission Log (bs_inventory): today's and this week's challenges. XP is paid on completion, nothing to claim.
exports('MissionLogList', function(src)
    src = tonumber(src)
    local p = src and get(src)
    if not p then return {} end
    local out = {}
    for _, set in ipairs({ { p.dailies, 'mlog.pass_daily', 'd' }, { p.weeklies, 'mlog.pass_weekly', 'w' } }) do
        for i, c in ipairs(set[1] or {}) do
            local label = Lp(src, 'ch.' .. tostring(c.kind), { n = c.target })
            out[#out + 1] = {
                id = ('pass:%s:%d:%d:%s'):format(set[3], set[3] == 'd' and p.day_key or p.week_key, i, c.id),
                offer = c.accepted ~= true and c.done ~= true, title = label, group = Lp(src, set[2]),
                steps = { { label = ('%s (%d/%d)'):format(label, c.p or 0, c.target), done = c.done == true } },
                complete = c.done == true, claimed = c.done == true, noClaim = true,
                hint = Lp(src, 'mlog.pass_hint', { xp = c.xp }),
            }
        end
    end
    return out
end)
exports('MissionLogClaim', function() return { ok = false } end)

local function registerLog()
    if GetResourceState('bs_inventory') == 'started' then
        pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end)
    end
end
CreateThread(function() Wait(1500); registerLog() end)
AddEventHandler('onResourceStart', function(res) if res == 'bs_inventory' then SetTimeout(1000, registerLog) end end)
