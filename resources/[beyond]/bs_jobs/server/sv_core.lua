-- bs_jobs server core: who holds which job, applications, approvals, rewards and logging.
-- Everything is decided here. Clients only ask.

J = J or {}
local S = Jobs.Settings

J.Members = {}   -- [cid] = { cid, fid, job, status, applied, joined }
J.Picks = {}     -- [fid] = { [jobId] = true } for player factions
J.Ready = false

local function q(sql, p) return MySQL.query.await(sql, p or {}) or {} end
local function x(sql, p) return MySQL.update.await(sql, p or {}) end
J.q, J.x = q, x

function J.Now() return os.time() end
-- Week number used for the weekly scoreboard (UTC, weeks start Monday).
function J.Week() return tonumber(os.date('!%Y%W')) end

function J.Notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars), duration = 5000 })
end

function J.Player(src) local ok, p = pcall(function() return exports.bs_core:GetPlayer(tonumber(src)) end); return ok and p or nil end
function J.CharId(src) local p = J.Player(src); return p and tonumber(p.charId) or nil end
function J.Name(src)
    local ok, s = pcall(function() return exports.bs_core:GetPlayerSummary(tonumber(src)) end)
    return (ok and s and s.name) or GetPlayerName(src) or '?'
end
function J.SrcOf(cid)
    for _, v in ipairs(GetPlayers()) do
        local s = tonumber(v)
        if J.CharId(s) == cid then return s end
    end
end
function J.Faction(src)
    if GetResourceState('bs_factions') ~= 'started' then return nil end
    local ok, f = pcall(function() return exports.bs_factions:GetFaction(src) end)
    return ok and f or nil
end
function J.IsVanilla(fid)
    if not fid then return false end
    if Jobs.Vanilla[fid] then return true end
    local ok, v = pcall(function() return exports.bs_faction_bases:IsVanilla(fid) end)
    return ok and v == true
end
function J.IsAdmin(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
-- Leader, or a rank with the 'jobs' permission.
function J.CanManage(src)
    local ok, r = pcall(function() return exports.bs_factions:RankAllowed(src, 'jobs') end)
    return ok and r == true
end

function J.PedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function J.InSafeZone(x, y)
    if GetResourceState('bs_zombies') ~= 'started' then return false end
    local ok, inside = pcall(function() return exports.bs_zombies:InSafeZone(x, y, 0.0) end)
    return ok and inside == true
end

-- Jobs a faction offers. Vanilla factions get their fixed list, player factions their picks.
function J.JobsOf(fid)
    if not fid then return {} end
    if J.IsVanilla(fid) then return Jobs.Vanilla[fid] or Jobs.VanillaFallback end
    local out = {}
    for _, id in ipairs(Jobs.PlayerPool) do
        if J.Picks[fid] and J.Picks[fid][id] then out[#out + 1] = id end
    end
    return out
end
function J.Offers(fid, job)
    for _, id in ipairs(J.JobsOf(fid)) do if id == job then return true end end
    return false
end

function J.Cap(job) return math.max(1, math.floor(tonumber(Jobs.Caps[job]) or 2)) end

function J.Count(fid, job)
    local n = 0
    for _, m in pairs(J.Members) do if m.fid == fid and m.job == job and m.status == 'active' then n = n + 1 end end
    return n
end

-- Active job of an online player (nil when none or only applied).
function J.JobOf(src)
    local cid = J.CharId(src)
    local m = cid and J.Members[cid]
    if not m or m.status ~= 'active' then return nil end
    if J.Faction(src) ~= m.fid then return nil end
    return m.job, m
end
function J.Does(src, cap)
    local job = J.JobOf(src)
    if not job then return false end
    if job == cap then return true end
    return (Jobs.Does[job] or {})[cap] == true
end

-- Logging: job actions go to bs_guard_log so staff see them next to detections. Confidence 0 = info only.
function J.Log(src, kind, details)
    local c = src and J.PedPos(src)
    local license
    pcall(function() license = exports.bs_core:PrimaryIdentifier(src) end)
    MySQL.insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)', {
        src, license, src and J.CharId(src), src and (GetPlayerName(src) or '?'):sub(1, 64) or 'server',
        ('job_' .. tostring(kind)):sub(1, 32), 0, tostring(details or ''):sub(1, 512),
        c and c.x or nil, c and c.y or nil, c and c.z or nil,
    })
end
-- Something a client should never be able to ask for. Goes through bs_guard so staff get the alert.
function J.Flag(src, kind, details)
    if GetResourceState('bs_guard') == 'started' then
        pcall(function() exports.bs_guard:Flag(src, ('jobs_' .. tostring(kind)):sub(1, 32), details, 60) end)
    else
        J.Log(src, 'flag_' .. tostring(kind), details)
    end
end

-- Replicated flags on the player, for the interaction filters (bsJob, bsJ_<cap>).
local CAPS = { 'hunt', 'fish', 'water', 'chop', 'siphon', 'kidnap', 'rob', 'smuggle', 'gunsmith' }
function J.SyncState(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    local job = J.JobOf(src)
    local st = Player(src).state
    st:set('bsJob', job, true)
    for _, c in ipairs(CAPS) do st:set('bsJ_' .. c, job and J.Does(src, c) or nil, true) end
    st:set('bsJ_garage', job and Jobs.Defs[job] and Jobs.Defs[job].garage and true or nil, true)
    TriggerClientEvent('bs:jobs:self', src, { job = job, label = job and J.JobLabel(src, job) or nil })
    if J.PushStations then J.PushStations(src) end
end

function J.JobLabel(src, job)
    local def = Jobs.Defs[job]
    return Lp(src, 'job.' .. tostring(job), { fallback = def and def.label or job })
end

-- Rewards for one finished contract. Vanilla factions are paid more.
function J.Reward(src, cid, fid, tpl, job)
    local mult = J.IsVanilla(fid) and (tonumber(S.vanillaRewardMult) or 1.5) or (tonumber(S.playerRewardMult) or 1.0)
    local rep = math.floor((tpl.rep or 0) * mult)
    local xp = math.floor((tpl.xp or 0) * mult)
    local sxp = math.floor((tpl.sxp or 0) * mult)
    local fxp = math.floor((tpl.fxp or 0) * mult)
    if rep > 0 then pcall(function() exports.bs_factions:AdjustReputation(cid, rep) end) end
    if xp > 0 and src then pcall(function() exports.bs_core:AddXP(src, xp, 'job_contract') end) end
    local skill = (Jobs.Defs[job] or {}).skill
    if sxp > 0 and src and skill and GetResourceState('bs_skills') == 'started' then
        pcall(function() exports.bs_skills:AddSkillXP(src, skill, sxp) end)
    end
    if fxp > 0 then pcall(function() exports.bs_factions:AddFactionXP(fid, fxp, 'job contract') end) end
    x('INSERT INTO `bs_job_stats` (`character_id`,`faction_id`,`week`,`rep`,`contracts`) VALUES (?,?,?,?,1) ON DUPLICATE KEY UPDATE `rep` = `rep` + VALUES(`rep`), `contracts` = `contracts` + 1',
        { cid, fid, J.Week(), rep })
    return { rep = rep, xp = xp, sxp = sxp }
end

--------------------------------------------------------------------------------
-- Membership
--------------------------------------------------------------------------------

local function cooldownLeft(cid)
    local r = q('SELECT until_ts FROM bs_job_cooldowns WHERE character_id = ? LIMIT 1', { cid })[1]
    local left = (r and tonumber(r.until_ts) or 0) - J.Now()
    return left > 0 and left or 0
end
J.CooldownLeft = cooldownLeft

local function setMember(m)
    J.Members[m.cid] = m
    x('INSERT INTO bs_job_members (character_id, faction_id, job_id, status, applied_at, joined_at, approved_by) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE faction_id = VALUES(faction_id), job_id = VALUES(job_id), status = VALUES(status), applied_at = VALUES(applied_at), joined_at = VALUES(joined_at), approved_by = VALUES(approved_by)',
        { m.cid, m.fid, m.job, m.status, m.applied or 0, m.joined or 0, m.approvedBy })
end

-- Drops a job (leaving, kicked, or no longer in that faction). cooldown = start the wait.
function J.DropMember(cid, cooldown, reason)
    local m = J.Members[cid]
    if not m then return end
    J.Members[cid] = nil
    x('DELETE FROM bs_job_members WHERE character_id = ?', { cid })
    if cooldown and m.status == 'active' then
        local hours = tonumber(S.leaveCooldownHours) or 24
        if hours > 0 then
            x('INSERT INTO bs_job_cooldowns (character_id, until_ts) VALUES (?, ?) ON DUPLICATE KEY UPDATE until_ts = VALUES(until_ts)', { cid, J.Now() + math.floor(hours * 3600) })
        end
    end
    if J.OnDropped then J.OnDropped(cid, m) end
    local src = J.SrcOf(cid)
    if src then J.SyncState(src) end
    J.Log(src, 'leave', ('%s %s/%s (%s)'):format(cid, m.fid, m.job, reason or 'left'))
end

local function apply(src, a)
    a = type(a) == 'table' and a or {}
    if not S.enabled then return { ok = false, error = Lp(src, 'err.disabled') } end
    local cid, fid, job = J.CharId(src), J.Faction(src), tostring(a.job or '')
    if not cid then return { ok = false, error = Lp(src, 'err.loading') } end
    if not fid then return { ok = false, error = Lp(src, 'err.no_faction') } end
    if not J.Offers(fid, job) then return { ok = false, error = Lp(src, 'err.not_offered') } end
    local cur = J.Members[cid]
    if cur and cur.status == 'active' and cur.fid == fid then return { ok = false, error = Lp(src, 'err.have_job') } end
    local left = cooldownLeft(cid)
    if left > 0 then return { ok = false, error = Lp(src, 'err.cooldown', { h = left // 3600, m = (left % 3600) // 60 }) } end
    if J.Count(fid, job) >= J.Cap(job) then return { ok = false, error = Lp(src, 'err.full') } end
    local m = { cid = cid, fid = fid, job = job, status = 'pending', applied = J.Now(), joined = 0 }
    -- Leaders and job managers take a job straight away.
    if J.CanManage(src) then m.status, m.joined, m.approvedBy = 'active', J.Now(), cid end
    setMember(m)
    J.SyncState(src)
    J.Log(src, 'apply', ('%s/%s %s'):format(fid, job, m.status))
    return { ok = true, status = m.status }
end

local function withdraw(src)
    local cid = J.CharId(src)
    local m = cid and J.Members[cid]
    if not m or m.status ~= 'pending' then return { ok = false, error = Lp(src, 'err.no_application') } end
    J.DropMember(cid, false, 'withdrawn')
    return { ok = true }
end

local function leave(src)
    local cid = J.CharId(src)
    local m = cid and J.Members[cid]
    if not m or m.status ~= 'active' then return { ok = false, error = Lp(src, 'err.no_job') } end
    J.DropMember(cid, true, 'left')
    return { ok = true }
end

local function approve(src, a)
    a = type(a) == 'table' and a or {}
    local fid = J.Faction(src)
    if not fid or not J.CanManage(src) then return { ok = false, error = Lp(src, 'err.no_perm') } end
    local cid = tonumber(a.cid)
    local m = cid and J.Members[cid]
    if not m or m.fid ~= fid or m.status ~= 'pending' then return { ok = false, error = Lp(src, 'err.no_application') } end
    if a.yes ~= true then
        J.DropMember(cid, false, 'declined')
        local t = J.SrcOf(cid); if t then J.Notify(t, 'warn', 'n.declined', { job = J.JobLabel(t, m.job) }) end
        return { ok = true }
    end
    if J.Count(fid, m.job) >= J.Cap(m.job) then return { ok = false, error = Lp(src, 'err.full') } end
    m.status, m.joined, m.approvedBy = 'active', J.Now(), J.CharId(src)
    setMember(m)
    local t = J.SrcOf(cid)
    if t then J.SyncState(t); J.Notify(t, 'success', 'n.approved', { job = J.JobLabel(t, m.job) }) end
    J.Log(src, 'approve', ('%s -> %s/%s'):format(cid, fid, m.job))
    return { ok = true }
end

local function kick(src, a)
    a = type(a) == 'table' and a or {}
    local fid = J.Faction(src)
    if not fid or not J.CanManage(src) then return { ok = false, error = Lp(src, 'err.no_perm') } end
    local cid = tonumber(a.cid)
    local m = cid and J.Members[cid]
    if not m or m.fid ~= fid then return { ok = false, error = Lp(src, 'err.no_job') } end
    J.DropMember(cid, false, 'removed by ' .. tostring(J.CharId(src)))
    return { ok = true }
end

-- Player factions pick up to playerMaxPicks jobs from the pool. Unpicking drops its members.
local function pick(src, a)
    a = type(a) == 'table' and a or {}
    local fid, job = J.Faction(src), tostring(a.job or '')
    if not fid or not J.CanManage(src) then return { ok = false, error = Lp(src, 'err.no_perm') } end
    if J.IsVanilla(fid) then return { ok = false, error = Lp(src, 'err.vanilla_fixed') } end
    local inPool = false
    for _, id in ipairs(Jobs.PlayerPool) do if id == job then inPool = true end end
    if not inPool or (Jobs.Defs[job] or {}).special then return { ok = false, error = Lp(src, 'err.not_offered') } end
    J.Picks[fid] = J.Picks[fid] or {}
    if a.on == true then
        local n = 0
        for _ in pairs(J.Picks[fid]) do n = n + 1 end
        if not J.Picks[fid][job] and n >= (tonumber(S.playerMaxPicks) or 2) then return { ok = false, error = Lp(src, 'err.max_picks', { n = S.playerMaxPicks }) } end
        J.Picks[fid][job] = true
        x('INSERT IGNORE INTO bs_job_faction_picks (faction_id, job_id, picked_at) VALUES (?,?,?)', { fid, job, J.Now() })
    else
        J.Picks[fid][job] = nil
        x('DELETE FROM bs_job_faction_picks WHERE faction_id = ? AND job_id = ?', { fid, job })
        for cid, m in pairs(J.Members) do if m.fid == fid and m.job == job then J.DropMember(cid, false, 'job removed') end end
        if J.OnUnpicked then J.OnUnpicked(fid, job) end
    end
    J.Log(src, 'pick', ('%s %s %s'):format(fid, job, a.on == true and 'on' or 'off'))
    return { ok = true }
end

-- Names for a list of character ids (one query).
function J.Names(cids)
    local out = {}
    if #cids == 0 then return out end
    local marks = {}
    for i = 1, #cids do marks[i] = '?' end
    for _, r in ipairs(q(('SELECT id, first_name, last_name FROM bs_characters WHERE id IN (%s)'):format(table.concat(marks, ',')), cids)) do
        out[tonumber(r.id)] = ((r.first_name or '?') .. ' ' .. (r.last_name or '')):gsub('%s+$', '')
    end
    return out
end

-- Everything the JOBS tab shows.
local function overview(src)
    local cid, fid = J.CharId(src), J.Faction(src)
    if not cid then return { ok = false, error = Lp(src, 'err.loading') } end
    if not fid then return { ok = false, error = Lp(src, 'err.no_faction') } end
    local vanilla = J.IsVanilla(fid)
    local manage = J.CanManage(src)
    local ids, online = {}, {}
    for _, v in ipairs(GetPlayers()) do local c = J.CharId(tonumber(v)); if c then online[c] = true end end
    for c, m in pairs(J.Members) do if m.fid == fid then ids[#ids + 1] = c end end
    local names = J.Names(ids)
    local jobs = {}
    for _, job in ipairs(J.JobsOf(fid)) do
        local def = Jobs.Defs[job] or {}
        local members = {}
        for c, m in pairs(J.Members) do
            if m.fid == fid and m.job == job and m.status == 'active' then
                members[#members + 1] = { cid = c, name = names[c] or ('#' .. c), online = online[c] == true, you = c == cid }
            end
        end
        jobs[#jobs + 1] = { id = job, label = J.JobLabel(src, job), blurb = Lp(src, 'jobd.' .. job), special = def.special == true,
                            cap = J.Cap(job), members = members, garage = def.garage }
    end
    local apps = {}
    if manage then
        for c, m in pairs(J.Members) do
            if m.fid == fid and m.status == 'pending' then
                apps[#apps + 1] = { cid = c, name = names[c] or ('#' .. c), job = m.job, jobLabel = J.JobLabel(src, m.job), at = m.applied }
            end
        end
        table.sort(apps, function(a, b) return a.at < b.at end)
    end
    local mine = J.Members[cid]
    local out = {
        ok = true, factionId = fid, vanilla = vanilla, canManage = manage, jobs = jobs, applications = apps,
        mine = mine and mine.fid == fid and { job = mine.job, label = J.JobLabel(src, mine.job), status = mine.status, since = mine.joined } or nil,
        cooldown = cooldownLeft(cid),
        settings = { leaveHours = S.leaveCooldownHours, maxPicks = S.playerMaxPicks, ransomCap = S.ransomCap },
    }
    if not vanilla then
        local pool = {}
        for _, job in ipairs(Jobs.PlayerPool) do
            pool[#pool + 1] = { id = job, label = J.JobLabel(src, job), picked = J.Picks[fid] and J.Picks[fid][job] == true }
        end
        out.pool = pool
    end
    if J.OverviewExtra then J.OverviewExtra(src, cid, fid, out) end
    return out
end

BSB.RegisterCallback('jobs:overview', overview)
BSB.RegisterCallback('jobs:apply', apply)
BSB.RegisterCallback('jobs:withdraw', withdraw)
BSB.RegisterCallback('jobs:leave', leave)
BSB.RegisterCallback('jobs:approve', approve)
BSB.RegisterCallback('jobs:kick', kick)
BSB.RegisterCallback('jobs:pick', pick)

-- A member who left the faction (or whose faction is gone) loses the job. Checked for online players.
CreateThread(function()
    while not J.Ready do Wait(500) end
    while true do
        Wait(60000)
        for _, v in ipairs(GetPlayers()) do
            local src = tonumber(v)
            local cid = J.CharId(src)
            local m = cid and J.Members[cid]
            if m then
                local fid = J.Faction(src)
                if fid ~= m.fid or not J.Offers(m.fid, m.job) then J.DropMember(cid, false, 'faction changed') end
            end
        end
    end
end)

AddEventHandler('bs:hook:player:loaded', function(player)
    local src = type(player) == 'table' and tonumber(player.source)
    if src then SetTimeout(3000, function() J.SyncState(src) end) end
end)

exports('GetJob', function(src) return J.JobOf(tonumber(src)) end)
exports('HasJob', function(src, job) return J.JobOf(tonumber(src)) == job end)
exports('Does', function(src, cap) return J.Does(tonumber(src), cap) end)

-- Tables (also in bs_core/sql/035_faction_jobs.sql), then the caches.
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    local sql = LoadResourceFile('bs_core', 'sql/035_faction_jobs.sql')
    if sql then
        for stmt in sql:gsub('%-%-[^\n]*', ''):gmatch('[^;]+') do
            if stmt:find('%S') then pcall(function() MySQL.query.await(stmt) end) end
        end
    end
    for _, r in ipairs(q('SELECT * FROM bs_job_members')) do
        local cid = tonumber(r.character_id)
        J.Members[cid] = { cid = cid, fid = r.faction_id, job = r.job_id, status = r.status,
                           applied = tonumber(r.applied_at) or 0, joined = tonumber(r.joined_at) or 0, approvedBy = tonumber(r.approved_by) }
    end
    for _, r in ipairs(q('SELECT faction_id, job_id FROM bs_job_faction_picks')) do
        J.Picks[r.faction_id] = J.Picks[r.faction_id] or {}
        J.Picks[r.faction_id][r.job_id] = true
    end
    J.Ready = true
    TriggerEvent('bs:jobs:ready')
    for _, v in ipairs(GetPlayers()) do J.SyncState(tonumber(v)) end
end)
