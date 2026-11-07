-- bs_factions - faction levels, mission board, skill tree and cosmetic tag styles.
-- XP comes only from faction missions and treasury donations. Config: config/config_progression.lua.

local P = Factions.Progression
local Data, Ready, Dirty = {}, false, {}
local LastBag = {}

local function q(sql, params) return exports.oxmysql:query_async(sql, params or {}) or {} end
local function x(sql, params) return exports.oxmysql:execute_async(sql, params or {}) end

-- Callbacks may get a table or positional args.
local function args(names, a, ...)
    if type(a) == 'table' then return a end
    local out, rest = {}, { a, ... }
    for i, n in ipairs(names) do out[n] = rest[i] end
    return out
end

local function notify(src, msg, kind)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = msg, duration = 6000 })
end

local function summaryOf(src)
    local ok, s = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end)
    if ok and type(s) == 'table' and s.factionId then return s end
    return nil
end

local function charOf(src)
    local ok, s = pcall(function() return exports.bs_core:GetPlayerSummary(tonumber(src)) end)
    return ok and type(s) == 'table' and tonumber(s.charId) or nil
end

-- Curve
local function xpToNext(level)
    if level >= P.maxLevel then return 0 end
    return math.floor(P.curve.base * (level ^ P.curve.exponent))
end

-- Total XP needed to reach `level` from level 1.
local function xpForLevel(level)
    local t = 0
    for l = 1, math.min(level, P.maxLevel) - 1 do t = t + xpToNext(l) end
    return t
end

local function levelFromXp(xp)
    local level, need = 1, 0
    while level < P.maxLevel do
        need = need + xpToNext(level)
        if xp < need then break end
        level = level + 1
    end
    return level
end

-- Periods (UTC). Weeks roll over Monday 00:00 UTC.
local function dayKey() return math.floor(os.time() / 86400) end
local function weekKey() return math.floor((os.time() - 345600) / 604800) end

local SkillById, DefById = {}, {}
for _, s in ipairs(P.Skills) do SkillById[s.id] = s end
for period, list in pairs(P.Missions) do for _, m in ipairs(list) do m.period = period; DefById[m.id] = m end end

-- Storage
local function blank(fid)
    return { id = fid, xp = 0, level = 1, bonus = 0, colour = 'amber', style = 'plain', skills = {}, board = { daily = {}, weekly = {} }, dayKey = -1, weekKey = -1 }
end

local function load(fid)
    if not fid then return nil end
    if Data[fid] then return Data[fid] end
    local d = blank(fid)
    local row = q('SELECT xp, colour, style, day_key, week_key, bonus_points FROM bs_faction_progress WHERE faction_id=? LIMIT 1', { fid })[1]
    if row then
        d.xp = tonumber(row.xp) or 0
        d.bonus = tonumber(row.bonus_points) or 0
        d.colour = row.colour or d.colour
        d.style = row.style or d.style
        d.dayKey = tonumber(row.day_key) or -1
        d.weekKey = tonumber(row.week_key) or -1
    end
    d.level = levelFromXp(d.xp)
    for _, r in ipairs(q('SELECT skill_id, `rank` FROM bs_faction_skills WHERE faction_id=?', { fid })) do
        if SkillById[r.skill_id] then d.skills[r.skill_id] = tonumber(r.rank) or 0 end
    end
    for _, r in ipairs(q('SELECT period, slot, mission_id, target, progress, done, xp_reward, money_reward FROM bs_faction_missions WHERE faction_id=?', { fid })) do
        local list = d.board[r.period]
        if list and DefById[r.mission_id] then
            list[tonumber(r.slot)] = { slot = tonumber(r.slot), id = r.mission_id, target = tonumber(r.target), progress = tonumber(r.progress) or 0,
                done = r.done == true or tonumber(r.done) == 1, xp = tonumber(r.xp_reward) or 0, money = tonumber(r.money_reward) or 0 }
        end
    end
    Data[fid] = d
    return d
end

local function saveCore(d)
    x([[INSERT INTO bs_faction_progress (faction_id, xp, colour, style, day_key, week_key, bonus_points) VALUES (?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE xp=VALUES(xp), colour=VALUES(colour), style=VALUES(style), day_key=VALUES(day_key), week_key=VALUES(week_key), bonus_points=VALUES(bonus_points)]],
        { d.id, d.xp, d.colour, d.style, d.dayKey, d.weekKey, d.bonus or 0 })
end

local function saveMission(d, period, m)
    x([[INSERT INTO bs_faction_missions (faction_id, period, slot, mission_id, target, progress, done, xp_reward, money_reward) VALUES (?,?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE mission_id=VALUES(mission_id), target=VALUES(target), progress=VALUES(progress), done=VALUES(done), xp_reward=VALUES(xp_reward), money_reward=VALUES(money_reward)]],
        { d.id, period, m.slot, m.id, m.target, m.progress, m.done and 1 or 0, m.xp, m.money })
end

-- Skills
local function skillRank(d, id) return d and d.skills[id] or 0 end
local function skillValue(d, id)
    local s = SkillById[id]
    return s and skillRank(d, id) * (s.value or 0) or 0
end
local function pointsSpent(d) local n = 0; for _, r in pairs(d.skills) do n = n + r end; return n end
local function pointsTotal(d) return d.level - 1 + (d.bonus or 0) end

-- Members / sync
local function onlineMembers(fid)
    local out = {}
    for _, v in ipairs(GetPlayers()) do
        local s = summaryOf(tonumber(v))
        if s and s.factionId == fid then out[#out + 1] = tonumber(v) end
    end
    return out
end

local function styleBag(d)
    local hex
    for _, c in ipairs(P.Unlocks.colours) do if c.id == d.colour then hex = c.hex end end
    return { level = d.level, colour = d.colour, hex = hex or '#e08c46', style = d.style }
end

-- Server-owned statebag read by cl_tags: Player(sid).state.bsFactionStyle.
local function pushBag(src, d)
    local bag = d and styleBag(d) or nil
    local key = bag and (bag.level .. bag.colour .. bag.style) or ''
    if LastBag[src] == key then return end
    LastBag[src] = key
    Player(src).state:set('bsFactionStyle', bag, true)
end

local function broadcast(d)
    for _, src in ipairs(onlineMembers(d.id)) do
        pushBag(src, d)
        TriggerClientEvent('bs:factions:progress', src, { level = d.level, xp = d.xp, style = styleBag(d) })
    end
end

-- XP (missions and donations only)
local function addXp(d, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or d.level >= P.maxLevel then return 0 end
    local before = d.level
    d.xp = math.min(d.xp + amount, xpForLevel(P.maxLevel))
    d.level = levelFromXp(d.xp)
    saveCore(d)
    if d.level > before then
        for _, src in ipairs(onlineMembers(d.id)) do
            notify(src, Lp(src, 'fac.level_up', { level = d.level, n = d.level - before }), 'success')
        end
        TriggerEvent('bs:factions:levelUp', d.id, d.level, before)
    end
    broadcast(d)
    return amount
end

-- Board
local function roll(d, period)
    local pool, picked = {}, {}
    for _, m in ipairs(P.Missions[period] or {}) do pool[#pool + 1] = m end
    local payBonus = 1 + skillValue(d, 'mission_pay') / 100
    for slot = 1, math.min(P.board[period] or 0, #pool) do
        local i = math.random(#pool)
        local def = table.remove(pool, i)
        local target = math.random(def.n[1], def.n[2])
        picked[slot] = { slot = slot, id = def.id, target = target, progress = 0, done = false,
            xp = target * (def.xpPer or 0), money = math.floor(target * (def.moneyPer or 0) * payBonus) }
    end
    d.board[period] = picked
    x('DELETE FROM bs_faction_missions WHERE faction_id=? AND period=?', { d.id, period })
    for _, m in ipairs(picked) do saveMission(d, period, m) end
end

local function freshBoard(d)
    local changed = false
    if d.dayKey ~= dayKey() then roll(d, 'daily'); d.dayKey = dayKey(); changed = true end
    if d.weekKey ~= weekKey() then roll(d, 'weekly'); d.weekKey = weekKey(); changed = true end
    if changed then saveCore(d) end
    return d
end

local function complete(d, period, m)
    m.done = true
    saveMission(d, period, m)
    local def = DefById[m.id]
    pcall(function() exports.bs_factions:TreasuryDeposit(d.id, m.money, nil, 'mission', 'Mission: ' .. (def and def.label or m.id)) end)
    for _, src in ipairs(onlineMembers(d.id)) do
        notify(src, Lp(src, 'fac.mission_done', { name = def and def.label or m.id, xp = m.xp, money = m.money }), 'success')
    end
    addXp(d, m.xp, 'mission')
end

-- Adds `n` to every open mission of this kind; `match(def)` filters.
local function bump(fid, kind, n, match)
    local d = fid and load(fid)
    if not d then return end
    freshBoard(d)
    for period, list in pairs(d.board) do
        for _, m in ipairs(list) do
            local def = DefById[m.id]
            if def and def.kind == kind and not m.done and (not match or match(def)) then
                m.progress = math.min(m.target, m.progress + n)
                if m.progress >= m.target then complete(d, period, m) else Dirty[d.id .. ':' .. period .. ':' .. m.slot] = { d, period, m } end
            end
        end
    end
end

-- Hooks
AddEventHandler('bs:hook:player:action', function(player, actionId)
    if not Ready or not player or not player.source then return end
    local s = summaryOf(player.source)
    if not s then return end
    bump(s.factionId, 'action', 1, function(def)
        for _, a in ipairs(def.actions or {}) do if a == actionId then return true end end
        return false
    end)
end)

-- Fired by bs_extraction on a successful extraction (server-only event).
AddEventHandler('bs:extraction:completed', function(src)
    if not Ready then return end
    local s = summaryOf(src)
    if s then bump(s.factionId, 'extract', 1) end
end)

-- Progress is flushed in batches, completions are written at once.
CreateThread(function()
    while true do
        Wait(30000)
        for k, v in pairs(Dirty) do saveMission(v[1], v[2], v[3]); Dirty[k] = nil end
    end
end)

-- Payload builders
local function missionView(d)
    local out = {}
    for _, period in ipairs({ 'daily', 'weekly' }) do
        local list = {}
        for _, m in ipairs(d.board[period]) do
            local def = DefById[m.id] or {}
            list[#list + 1] = { slot = m.slot, id = m.id, label = def.label, kind = def.kind, item = def.item,
                target = m.target, progress = m.progress, done = m.done, xp = m.xp, money = m.money }
        end
        out[period] = list
    end
    out.resetsDaily = (dayKey() + 1) * 86400
    out.resetsWeekly = (weekKey() + 1) * 604800 + 345600
    return out
end

local function canSpend(src, s)
    if s.rank == 'owner' then return true end
    local ok, r = pcall(function() return exports.bs_factions:RankAllowed(src, P.skillPerm) end)
    return ok and r == true
end

local function skillsView(src, s, d)
    local list = {}
    for _, sk in ipairs(P.Skills) do
        list[#list + 1] = { id = sk.id, label = sk.label, desc = sk.desc, ranks = sk.ranks, value = sk.value, level = sk.level or 1,
            requires = sk.requires or {}, rank = skillRank(d, sk.id) }
    end
    return { ok = true, skills = list, level = d.level, points = pointsTotal(d) - pointsSpent(d), spent = pointsSpent(d), canSpend = canSpend(src, s) }
end

local function cosmeticsView(d)
    local colours, styles = {}, {}
    for _, c in ipairs(P.Unlocks.colours) do colours[#colours + 1] = { id = c.id, hex = c.hex, level = c.level, unlocked = d.level >= c.level } end
    for _, st in ipairs(P.Unlocks.styles) do styles[#styles + 1] = { id = st.id, label = st.label, level = st.level, unlocked = d.level >= st.level } end
    return { colour = d.colour, style = d.style, colours = colours, styles = styles }
end

local function myFaction(src)
    if not Ready then return nil, nil, { ok = false, error = Lp(src, 'fac.faction_progression_is_starting') } end
    local s = summaryOf(src)
    if not s then return nil, nil, { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') } end
    return s, freshBoard(load(s.factionId)), nil
end

-- Callbacks
BSB.RegisterCallback('factions:progress:get', function(src)
    local s, d, err = myFaction(src)
    if err then return err end
    local base = xpForLevel(d.level)
    local nextNeed = xpToNext(d.level)
    return { ok = true, factionId = d.id, level = d.level, maxLevel = P.maxLevel, xp = d.xp,
        xpIntoLevel = d.xp - base, xpToNext = nextNeed, points = pointsTotal(d) - pointsSpent(d),
        cosmetics = cosmeticsView(d), base = P.Unlocks.base, donation = P.donation, canSpend = canSpend(src, s) }
end)

BSB.RegisterCallback('factions:missions:get', function(src)
    local _, d, err = myFaction(src)
    if err then return err end
    local out = missionView(d); out.ok = true
    return out
end)

-- Hand in items for a 'deliver' mission. Must stand inside one of your faction's flags.
BSB.RegisterCallback('factions:missions:deliver', function(src, ...)
    local s, d, err = myFaction(src)
    if err then return err end
    local a = args({ 'period', 'slot' }, ...)
    local period = tostring(a.period or '')
    local m = d.board[period] and d.board[period][tonumber(a.slot) or 0]
    local def = m and DefById[m.id]
    if not m or not def or def.kind ~= 'deliver' then return { ok = false, error = Lp(src, 'fac.that_mission_does_not_take_deliverie') } end
    if m.done then return { ok = false, error = Lp(src, 'fac.already_complete') } end
    local okFlag, flag = pcall(function() return exports.bs_faction_bases:FlagAt(src) end)
    if not okFlag or type(flag) ~= 'table' or flag.factionId ~= s.factionId then return { ok = false, error = Lp(src, 'fac.deliver_at_one_of_your_faction_flags') } end
    local have = tonumber(exports.bs_inventory:CountItem(src, def.item)) or 0
    local give = math.min(have, m.target - m.progress)
    if give < 1 then return { ok = false, error = Lp(src, 'fac.you_have_nothing_to_deliver_for_this') } end
    if not exports.bs_inventory:RemoveItem(src, def.item, give) then return { ok = false, error = Lp(src, 'fac.items_could_not_be_taken') } end
    m.progress = m.progress + give
    if m.progress >= m.target then complete(d, period, m) else saveMission(d, period, m) end
    local out = missionView(d); out.ok = true; out.delivered = give
    return out
end)

BSB.RegisterCallback('factions:skills:get', function(src)
    local s, d, err = myFaction(src)
    if err then return err end
    return skillsView(src, s, d)
end)

BSB.RegisterCallback('factions:skills:spend', function(src, ...)
    local s, d, err = myFaction(src)
    if err then return err end
    if not canSpend(src, s) then return { ok = false, error = Lp(src, 'fac.your_rank_may_not_spend_skill_points') } end
    local a = args({ 'skillId' }, ...)
    local sk = SkillById[tostring(a.skillId or a.id or '')]
    if not sk then return { ok = false, error = Lp(src, 'fac.unknown_skill') } end
    if pointsTotal(d) - pointsSpent(d) < 1 then return { ok = false, error = Lp(src, 'fac.no_skill_points_left') } end
    if d.level < (sk.level or 1) then return { ok = false, error = Lp(src, 'fac.req_level', { level = sk.level }) } end
    local r = skillRank(d, sk.id)
    if r >= sk.ranks then return { ok = false, error = Lp(src, 'fac.skill_is_maxed') } end
    for req, min in pairs(sk.requires or {}) do
        if skillRank(d, req) < min then return { ok = false, error = Lp(src, 'fac.req_skill', { skill = SkillById[req] and SkillById[req].label or req, rank = min }) } end
    end
    d.skills[sk.id] = r + 1
    x('INSERT INTO bs_faction_skills (faction_id, skill_id, `rank`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `rank`=VALUES(`rank`)', { d.id, sk.id, r + 1 })
    TriggerEvent('bs:factions:skillChanged', d.id, sk.id, r + 1)
    return skillsView(src, s, d)
end)

BSB.RegisterCallback('factions:cosmetics:set', function(src, ...)
    local s, d, err = myFaction(src)
    if err then return err end
    -- Leader and the rank right under them (custom ranks, see sv_service.lua)
    if s.rank ~= 'owner' and FactionsCore.rankIdx(s.factionId, s.rank) > 2 then return { ok = false, error = Lp(src, 'fac.only_the_leader_or_vice_leader_may_c') } end
    local a = args({ 'colour', 'style' }, ...)
    local colour, style = a.colour or a.color, a.style
    if colour then
        local found
        for _, c in ipairs(P.Unlocks.colours) do if c.id == colour then found = c end end
        if not found then return { ok = false, error = Lp(src, 'fac.unknown_colour') } end
        if d.level < found.level then return { ok = false, error = Lp(src, 'fac.colour_level', { level = found.level }) } end
        d.colour = found.id
    end
    if style then
        local found
        for _, st in ipairs(P.Unlocks.styles) do if st.id == style then found = st end end
        if not found then return { ok = false, error = Lp(src, 'fac.unknown_style') } end
        if d.level < found.level then return { ok = false, error = Lp(src, 'fac.style_level', { level = found.level }) } end
        d.style = found.id
    end
    saveCore(d)
    broadcast(d)
    local out = cosmeticsView(d); out.ok = true
    return out
end)

-- Cash -> treasury, a little XP back (daily cap per member).
BSB.RegisterCallback('factions:donate', function(src, ...)
    local _, d, err = myFaction(src)
    if err then return err end
    local cid = charOf(src)
    if not cid then return { ok = false, error = Lp(src, 'fac.character_is_unavailable') } end
    local a = args({ 'amount' }, ...)
    local cfg = P.donation
    local amount = math.floor(tonumber(a.amount) or 0)
    if amount < cfg.min or amount > cfg.max then return { ok = false, error = Lp(src, 'fac.donate_range', { min = cfg.min, max = cfg.max }) } end
    local row = q('SELECT xp FROM bs_faction_donations WHERE faction_id=? AND character_id=? AND day=CURDATE() LIMIT 1', { d.id, cid })[1]
    local used = row and tonumber(row.xp) or 0
    if not exports.bs_core:RemoveMoney(src, 'cash', amount, 'faction donation') then return { ok = false, error = Lp(src, 'fac.you_do_not_have_enough_cash') } end
    pcall(function() exports.bs_factions:TreasuryDeposit(d.id, amount, cid, 'donation', 'Member donation') end)
    local rate = 1 + skillValue(d, 'donation_rate') / 100
    local xp = math.min(math.floor(amount / cfg.dollarsPerXp * rate), math.max(0, cfg.dailyXpCap - used))
    if xp > 0 then
        x('INSERT INTO bs_faction_donations (faction_id, character_id, day, xp) VALUES (?,?,CURDATE(),?) ON DUPLICATE KEY UPDATE xp=xp+VALUES(xp)', { d.id, cid, xp })
        addXp(d, xp, 'donation')
    end
    return { ok = true, donated = amount, xp = xp, xpLeftToday = math.max(0, cfg.dailyXpCap - used - xp), level = d.level }
end)

-- Exports
exports('GetFactionLevel', function(fid) local d = Ready and load(fid); return d and d.level or 1 end)
exports('HasFactionSkill', function(fid, skillId) local d = Ready and load(fid); return skillRank(d, tostring(skillId or '')) > 0 end)
exports('GetSkillValue', function(fid, skillId) local d = Ready and load(fid); return d and skillValue(d, tostring(skillId or '')) or 0 end)
-- Faction XP from outside (bs_events tokens). Returns XP actually added.
exports('AddFactionXP', function(fid, amount, reason) local d = Ready and fid and load(fid); if not d then return 0 end; return addXp(d, amount, reason or 'external') end)
exports('GetFactionStyle', function(fid) local d = Ready and load(fid); return d and styleBag(d) or nil end)

-- Base gates for bs_faction_bases. key = 'flag_main' | 'flag_outpost'.
exports('FactionLevelAllows', function(fid, key)
    local need = P.Unlocks.base[tostring(key or '')]
    if type(need) ~= 'number' then return true, 1 end
    local d = Ready and load(fid)
    local level = d and d.level or 1
    return level >= need, need
end)
exports('FactionFlagBonus', function(fid)
    local d = Ready and load(fid)
    local level, n = d and d.level or 1, 0
    for at, add in pairs(P.Unlocks.base.extraFlags or {}) do if level >= at then n = n + add end end
    return n
end)

-- Keep tag statebags right after joins/leaves (membership has no server hook).
CreateThread(function()
    while not Ready do Wait(500) end
    while true do
        for _, v in ipairs(GetPlayers()) do
            local src = tonumber(v)
            local s = summaryOf(src)
            pushBag(src, s and load(s.factionId) or nil)
        end
        Wait(15000)
    end
end)

AddEventHandler('playerDropped', function() LastBag[source] = nil end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    -- Mirrors bs_core/sql/024_faction_progression.sql so a fresh DB still works.
    x([[CREATE TABLE IF NOT EXISTS bs_faction_progress (faction_id VARCHAR(32) NOT NULL, xp INT UNSIGNED NOT NULL DEFAULT 0,
        colour VARCHAR(16) NOT NULL DEFAULT 'amber', style VARCHAR(16) NOT NULL DEFAULT 'plain', day_key INT NOT NULL DEFAULT -1,
        week_key INT NOT NULL DEFAULT -1, PRIMARY KEY (faction_id))]])
    x([[CREATE TABLE IF NOT EXISTS bs_faction_skills (faction_id VARCHAR(32) NOT NULL, skill_id VARCHAR(32) NOT NULL,
        `rank` TINYINT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (faction_id, skill_id))]])
    x([[CREATE TABLE IF NOT EXISTS bs_faction_missions (faction_id VARCHAR(32) NOT NULL, period VARCHAR(8) NOT NULL, slot TINYINT UNSIGNED NOT NULL,
        mission_id VARCHAR(32) NOT NULL, target INT UNSIGNED NOT NULL, progress INT UNSIGNED NOT NULL DEFAULT 0, done TINYINT(1) NOT NULL DEFAULT 0,
        xp_reward INT UNSIGNED NOT NULL DEFAULT 0, money_reward INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (faction_id, period, slot))]])
    x([[CREATE TABLE IF NOT EXISTS bs_faction_donations (faction_id VARCHAR(32) NOT NULL, character_id INT UNSIGNED NOT NULL, day DATE NOT NULL,
        xp INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (faction_id, character_id, day))]])
    -- admin-granted skill points on top of level - 1
    pcall(x, 'ALTER TABLE bs_faction_progress ADD COLUMN IF NOT EXISTS bonus_points INT NOT NULL DEFAULT 0')
    math.randomseed(os.time())
    Ready = true
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for k, v in pairs(Dirty) do saveMission(v[1], v[2], v[3]); Dirty[k] = nil end
end)

-- Top factions for the F9 scoreboard. Cached 60 s so F9 spam never hits the DB.
local TopCache, TopAt = nil, 0
local function topFactions(n)
    n = math.max(1, math.min(25, tonumber(n) or 10))
    if TopCache and os.time() - TopAt < 60 then return { table.unpack(TopCache, 1, math.min(n, #TopCache)) } end
    local rows = q([[
        SELECT r.faction_id, r.label, r.short, COALESCE(p.xp, 0) AS xp,
               (SELECT COUNT(*) FROM bs_faction_members m WHERE m.faction_id = r.faction_id) AS members,
               (SELECT COALESCE(SUM(fr.reputation), 0) FROM bs_faction_reputation fr WHERE fr.faction_id = r.faction_id) AS rep
        FROM bs_faction_registry r LEFT JOIN bs_faction_progress p ON p.faction_id = r.faction_id
        ORDER BY xp DESC LIMIT 25]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        -- live xp wins over the DB row if it's loaded (may not be flushed yet)
        local xp = (Data[r.faction_id] and Data[r.faction_id].xp) or tonumber(r.xp) or 0
        out[#out + 1] = { id = r.faction_id, name = r.label, tag = r.short, xp = xp, level = levelFromXp(xp),
            members = tonumber(r.members) or 0, rep = tonumber(r.rep) or 0 }
    end
    table.sort(out, function(a, b) return a.xp > b.xp end)
    for i, f in ipairs(out) do f.rank = i end
    TopCache, TopAt = out, os.time()
    return { table.unpack(out, 1, math.min(n, #out)) }
end
exports('GetTopFactions', function(n) local ok, r = pcall(topFactions, n); return ok and r or {} end)

-- Shared with sv_admin.lua. Admin tooling only.
FactionsProg = {
    P = P, Data = Data, SkillById = SkillById, DefById = DefById,
    load = load, saveCore = saveCore, saveMission = saveMission, freshBoard = freshBoard, roll = roll,
    complete = complete, broadcast = broadcast, addXp = addXp, xpForLevel = xpForLevel, levelFromXp = levelFromXp,
    xpToNext = xpToNext, pointsTotal = pointsTotal, pointsSpent = pointsSpent, missionView = missionView,
    styleBag = styleBag, ready = function() return Ready end,
}

-- Mission Log (bs_inventory): read-only list of the faction board. Paid automatically, nothing to claim.
exports('MissionLogList', function(src)
    local _, d, err = myFaction(tonumber(src))
    if err or not d then return {} end
    local out = {}
    for _, period in ipairs({ 'daily', 'weekly' }) do
        for _, m in ipairs(d.board[period] or {}) do
            local def = DefById[m.id] or {}
            local vars = { xp = m.xp, money = m.money }
            out[#out + 1] = {
                id = ('fac:%s:%d'):format(period, m.slot), title = def.label or m.id,
                group = Lp(src, period == 'daily' and 'mlog.fac_daily' or 'mlog.fac_weekly'),
                steps = { { label = ('%s (%d/%d)'):format(def.label or m.id, m.progress, m.target), done = m.done == true } },
                complete = m.done == true, claimed = m.done == true, noClaim = true,
                hint = Lp(src, def.kind == 'deliver' and 'mlog.fac_deliver' or 'mlog.fac_auto', vars),
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
