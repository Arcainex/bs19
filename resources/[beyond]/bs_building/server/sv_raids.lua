-- Declared raids

local S = Building.Settings
local Raids = {}   -- active declarations { id, attacker, target, ends }
local Ready = false

local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end

local function summary(src)
    local ok, f = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end)
    return ok and f or nil
end

local labels = {}
local function labelOf(fac)
    if not fac then return '?' end
    if labels[fac] then return labels[fac] end
    local row = q('SELECT label FROM bs_faction_registry WHERE faction_id = ? LIMIT 1', { fac })[1]
    labels[fac] = row and row.label or fac
    return labels[fac]
end

local function prune()
    local now = os.time()
    for i = #Raids, 1, -1 do if Raids[i].ends <= now then table.remove(Raids, i) end end
end

function Building.RaidDeclared(attacker, target)
    if not attacker or not target or attacker == target then return false end
    local now = os.time()
    for _, r in ipairs(Raids) do
        if r.attacker == attacker and r.target == target and r.ends > now then return true end
    end
    return false
end

local function outposts()
    local out = {}
    if GetResourceState('bs_faction_bases') ~= 'started' then return out end
    local ok, list = pcall(function() return exports.bs_faction_bases:ListFlags() end)
    for _, f in ipairs(ok and list or {}) do
        if f.kind == 'outpost' and f.status ~= 'removed' then
            local e = out[f.factionId] or { id = f.factionId, label = f.label or labelOf(f.factionId), outposts = 0 }
            e.outposts = e.outposts + 1
            out[f.factionId] = e
        end
    end
    return out
end

local function cooldownLeft(fac)
    local row = q('SELECT MAX(declared_at) AS last FROM bs_build_raids WHERE attacker_id = ?', { fac })[1]
    local last = row and tonumber(row.last) or 0
    return math.max(0, last + S.raidCooldownMinutes * 60 - os.time())
end

local function tellFaction(fac, kind, key, vars)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if Building.FactionOf(pid) == fac then
            TriggerClientEvent('bs:ui:notify', pid, { type = kind, message = Lp(pid, key, vars), duration = 8000 })
        end
    end
end

local function canDeclare(src)
    local f = summary(src)
    if not (f and f.factionId) then return false, f end
    -- 'raid' rank permission (custom faction ranks); older bs_factions without it falls back to leader/officer
    local okR, allowed = pcall(function() return exports.bs_factions:RankAllowed(src, 'raid') end)
    if okR and allowed ~= nil then return allowed == true, f end
    return (f.rank == 'owner' or f.rank == 'officer'), f
end

BSB.RegisterCallback('raids:get', function(src)
    if not S.raidsEnabled then return { ok = false, error = Lp(src, 'build.err.no_raiding') } end
    if not Ready then return { ok = false, error = Lp(src, 'build.raid.starting') } end
    prune()
    local can, f = canDeclare(src)
    if not f or not f.factionId then return { ok = false, error = Lp(src, 'build.err.no_faction') } end
    local now = os.time()
    local targets, outgoing, incoming = {}, {}, {}
    for id, e in pairs(outposts()) do
        if id ~= f.factionId then
            e.declared = Building.RaidDeclared(f.factionId, id)
            targets[#targets + 1] = e
        end
    end
    table.sort(targets, function(a, b) return tostring(a.label) < tostring(b.label) end)
    for _, r in ipairs(Raids) do
        if r.attacker == f.factionId then outgoing[#outgoing + 1] = { id = r.target, label = labelOf(r.target), left = r.ends - now } end
        if r.target == f.factionId then incoming[#incoming + 1] = { id = r.attacker, label = labelOf(r.attacker), left = r.ends - now } end
    end
    return {
        ok = true, canDeclare = can == true, targets = targets, outgoing = outgoing, incoming = incoming,
        open = Building.RaidOpen(), window = ('%02d:00-%02d:00'):format(S.raidStartHour, S.raidEndHour),
        duration = S.raidDeclareMinutes, cooldown = can and cooldownLeft(f.factionId) or 0,
    }
end)

BSB.RegisterCallback('raids:declare', function(src, args)
    if not S.raidsEnabled then return { ok = false, error = Lp(src, 'build.err.no_raiding') } end
    if not Ready then return { ok = false, error = Lp(src, 'build.raid.starting') } end
    local target = type(args) == 'table' and tostring(args.id or '') or ''
    local can, f = canDeclare(src)
    if not f or not f.factionId then return { ok = false, error = Lp(src, 'build.err.no_faction') } end
    if not can then return { ok = false, error = Lp(src, 'build.raid.rank') } end
    if target == '' or target == f.factionId then return { ok = false, error = Lp(src, 'build.raid.bad_target') } end
    if not outposts()[target] then return { ok = false, error = Lp(src, 'build.raid.no_outposts') } end
    if Building.RaidDeclared(f.factionId, target) then return { ok = false, error = Lp(src, 'build.raid.already') } end
    local left = cooldownLeft(f.factionId)
    if left > 0 then return { ok = false, error = Lp(src, 'build.raid.cooldown', { m = math.ceil(left / 60) }) } end
    local now = os.time()
    local ends = now + S.raidDeclareMinutes * 60
    local p = (function() local ok, pl = pcall(function() return exports.bs_core:GetPlayer(src) end); return ok and pl or nil end)()
    local id = exports.oxmysql:insert_async('INSERT INTO `bs_build_raids` (`attacker_id`,`target_id`,`declared_by`,`declared_at`,`ends_at`) VALUES (?,?,?,?,?)',
        { f.factionId, target, p and p.charId, now, ends })
    Raids[#Raids + 1] = { id = id, attacker = f.factionId, target = target, ends = ends }
    Store.log(src, 'raid_declare', ('%s declared on %s for %d min'):format(f.factionId, target, S.raidDeclareMinutes))
    local window = ('%02d:00-%02d:00'):format(S.raidStartHour, S.raidEndHour)
    tellFaction(target, 'error', 'build.raid.incoming', { name = labelOf(f.factionId), m = S.raidDeclareMinutes, w = window })
    tellFaction(f.factionId, 'success', 'build.raid.declared', { name = labelOf(target), m = S.raidDeclareMinutes, w = window })
    return { ok = true, ends = ends }
end)

exports('RaidDeclared', function(attacker, target) return Building.RaidDeclared(attacker, target) end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    -- migration 034 makes this too; created here as well so a fresh server works before bs_core runs it
    exports.oxmysql:execute_async([[CREATE TABLE IF NOT EXISTS `bs_build_raids` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `attacker_id` VARCHAR(32) NOT NULL, `target_id` VARCHAR(32) NOT NULL,
        `declared_by` INT UNSIGNED NULL, `declared_at` BIGINT NOT NULL, `ends_at` BIGINT NOT NULL,
        PRIMARY KEY (`id`), KEY `attacker_id` (`attacker_id`), KEY `target_id` (`target_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    for _, r in ipairs(q('SELECT id, attacker_id, target_id, ends_at FROM bs_build_raids WHERE ends_at > ?', { os.time() })) do
        Raids[#Raids + 1] = { id = tonumber(r.id), attacker = r.attacker_id, target = r.target_id, ends = tonumber(r.ends_at) }
    end
    Ready = true
end)
