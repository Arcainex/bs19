-- bs_factions - squads: 1..Factions.Squad.maxSize characters of the same faction.
-- Memory is authoritative while running; changes are written to bs_squads / bs_squad_members (022_squads.sql) and pushed to online members as `bs:squad:sync`. Offline members stay in their squad.

local Cfg = Factions.Squad or {}
-- read live so bs_config can change it without a restart
local function maxSize()
    local v = BSConfigGet and BSConfigGet('Factions.Squad.maxSize', nil)
    return math.floor(tonumber(v) or tonumber(Cfg.maxSize) or 5)
end
local MAXRANKS = tonumber(Cfg.maxRanks) or 6
local NAMEMAX = tonumber(Cfg.nameMax) or 24

local Squads = {}   -- id -> { id, name, factionId, leader, ranks, members = { [charId] = { rankId, name } } }
local ByChar = {}   -- charId -> squadId
local Online = {}   -- src -> charId
local SrcOf = {}    -- charId -> src
local Invites = {}  -- src -> { squadId, by, byName, until_ }
local Loaded = false

local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end
local function x(sql, p) return exports.oxmysql:execute_async(sql, p or {}) end
local function ins(sql, p) return exports.oxmysql:insert_async(sql, p or {}) end

local function summary(src)
    local ok, s = pcall(function() return exports.bs_core:GetPlayerSummary(tonumber(src)) end)
    return ok and s or nil
end
local function factionOf(src)
    local ok, f = pcall(function() return exports.bs_factions:GetFaction(tonumber(src)) end)
    return ok and f or nil
end
local function arg(v, k) if type(v) == 'table' then return v[k] end return v end

local function defaultRanks()
    local out = {}
    for i, r in ipairs(Cfg.defaultRanks or { { id = 1, label = 'Lead' }, { id = 2, label = 'Second' }, { id = 3, label = 'Member' } }) do
        out[i] = { id = r.id, label = r.label }
    end
    return out
end

local function cleanName(v)
    v = tostring(v or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #v < 2 then return nil end
    return v:sub(1, NAMEMAX)
end

local function rankLabel(sq, id)
    for _, r in ipairs(sq.ranks) do if r.id == id then return r.label end end
    return '?'
end
local function lastRankId(sq) return sq.ranks[#sq.ranks] and sq.ranks[#sq.ranks].id or 1 end
local function rankOrder(sq, id)
    for i, r in ipairs(sq.ranks) do if r.id == id then return i end end
    return 99
end
local function count(sq) local n = 0; for _ in pairs(sq.members) do n = n + 1 end; return n end

local function charOf(src)
    src = tonumber(src); if not src then return nil end
    if Online[src] then return Online[src] end
    local s = summary(src); local cid = s and tonumber(s.charId)
    if cid then Online[src] = cid; SrcOf[cid] = src end
    return cid
end

-- 0..100, nil when unknown
local function healthOf(src)
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return nil end
    local ok, h, mx = pcall(function() return GetEntityHealth(ped), GetEntityMaxHealth(ped) end)
    if not ok or not h then return nil end
    mx = (mx and mx > 100) and mx or 200
    return math.max(0, math.min(100, math.floor((h - 100) / (mx - 100) * 100 + 0.5)))
end
local function fullState(src)
    local cid = charOf(src); local id = cid and ByChar[cid]; local sq = id and Squads[id]
    if not sq then return nil end
    local list = {}
    for mcid, m in pairs(sq.members) do
        local msrc = SrcOf[mcid]; local s = msrc and summary(msrc)
        list[#list + 1] = { charId = mcid, name = (s and s.name) or m.name, level = s and s.level or nil,
            rankId = m.rankId, rankLabel = rankLabel(sq, m.rankId), isLeader = mcid == sq.leader,
            online = msrc ~= nil, src = msrc, health = msrc and healthOf(msrc) or nil }
    end
    table.sort(list, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        local ra, rb = rankOrder(sq, a.rankId), rankOrder(sq, b.rankId)
        if ra ~= rb then return ra < rb end
        return tostring(a.name) < tostring(b.name)
    end)
    local me = sq.members[cid]
    return { id = sq.id, name = sq.name, factionId = sq.factionId, leaderCharId = sq.leader,
        isLeader = cid == sq.leader, myCharId = cid, rankId = me.rankId, rankLabel = rankLabel(sq, me.rankId),
        ranks = sq.ranks, members = list, maxSize = maxSize(), maxRanks = MAXRANKS }
end

local function push(src)
    src = tonumber(src); if not src then return end
    local st = fullState(src)
    Player(src).state:set('bsSquad', st and { id = st.id, name = st.name, rank = st.rankLabel } or nil, true)
    TriggerClientEvent('bs:squad:sync', src, { squad = st })
end
local function pushSquad(sq)
    for mcid in pairs(sq.members) do if SrcOf[mcid] then push(SrcOf[mcid]) end end
end

--------------------------------------------------------------------------- persistence
local function saveRanks(sq) x('UPDATE bs_squads SET ranks=?, name=?, leader_char=? WHERE id=?', { json.encode(sq.ranks), sq.name, sq.leader, sq.id }) end

local function removeMember(sq, cid)
    sq.members[cid] = nil; ByChar[cid] = nil
    x('DELETE FROM bs_squad_members WHERE character_id=?', { cid })
    if count(sq) == 0 then
        Squads[sq.id] = nil
        x('DELETE FROM bs_squads WHERE id=?', { sq.id })
        return
    end
    if sq.leader == cid then
        local best, bestOrder
        for mcid, m in pairs(sq.members) do
            local o = rankOrder(sq, m.rankId) + (SrcOf[mcid] and 0 or 0.5)
            if not best or o < bestOrder then best, bestOrder = mcid, o end
        end
        sq.leader = best
        sq.members[best].rankId = sq.ranks[1].id
        x('UPDATE bs_squad_members SET rank_id=? WHERE character_id=?', { sq.members[best].rankId, best })
        saveRanks(sq)
    end
end

local function ensureTables()
    -- No FK to bs_characters: a type mismatch there made the whole CREATE fail.
    x([[CREATE TABLE IF NOT EXISTS `bs_squads` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `name` VARCHAR(32) NOT NULL,
        `faction_id` VARCHAR(32) NOT NULL, `leader_char` INT UNSIGNED NOT NULL,
        `ranks` TEXT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `ix_bs_squads_faction` (`faction_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    x([[CREATE TABLE IF NOT EXISTS `bs_squad_members` (
        `character_id` INT UNSIGNED NOT NULL, `squad_id` INT UNSIGNED NOT NULL,
        `rank_id` INT UNSIGNED NOT NULL DEFAULT 3, `name` VARCHAR(64) NOT NULL DEFAULT '',
        `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`character_id`), KEY `ix_bs_squad_members_squad` (`squad_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

local loadRows
local function loadAll()
    local ok, err = pcall(function() ensureTables(); loadRows() end)
    if not ok then print(('^1[bs_factions]^7 squad load failed: %s'):format(tostring(err))) end
    -- never leave the squad menu stuck on "still loading"
    Loaded = true
end

loadRows = function()
    local rows = q('SELECT id, name, faction_id, leader_char, ranks FROM bs_squads', {})
    for _, r in ipairs(rows) do
        local ok, ranks = pcall(json.decode, r.ranks or '')
        if not ok or type(ranks) ~= 'table' or #ranks == 0 then ranks = defaultRanks() end
        Squads[tonumber(r.id)] = { id = tonumber(r.id), name = r.name, factionId = r.faction_id,
            leader = tonumber(r.leader_char), ranks = ranks, members = {} }
    end
    for _, m in ipairs(q('SELECT character_id, squad_id, rank_id, name FROM bs_squad_members', {})) do
        local sq = Squads[tonumber(m.squad_id)]
        if sq then
            local cid = tonumber(m.character_id)
            sq.members[cid] = { rankId = tonumber(m.rank_id), name = m.name }
            ByChar[cid] = sq.id
        end
    end
    for id, sq in pairs(Squads) do
        if count(sq) == 0 then Squads[id] = nil; x('DELETE FROM bs_squads WHERE id=?', { id })
        elseif not sq.members[sq.leader] then local l = next(sq.members); sq.leader = l; saveRanks(sq) end
    end
end

-- A member whose faction no longer matches (left, kicked, disbanded) leaves the squad.
local function validate(src)
    local cid = charOf(src); local id = cid and ByChar[cid]; local sq = id and Squads[id]
    if not sq then return end
    if factionOf(src) ~= sq.factionId then
        removeMember(sq, cid)
        if Squads[id] then pushSquad(sq) end
        push(src)
        TriggerClientEvent('bs:ui:notify', src, { type = 'warn', message = Lp(src, 'fac.you_left_your_squad_with_your_factio') })
    end
end

--------------------------------------------------------------------------- actions
local function mine(src)
    local cid = charOf(src); local id = cid and ByChar[cid]
    return cid, id and Squads[id]
end
local function fail(msg) return { ok = false, error = msg } end

local function create(src, data)
    local cid, sq = mine(src)
    if not cid then return fail(Lp(src, 'fac.character_not_loaded')) end
    if sq then return fail(Lp(src, 'fac.you_are_already_in_a_squad')) end
    local fid = factionOf(src); if not fid then return fail(Lp(src, 'fac.join_a_faction_first')) end
    local name = cleanName(arg(data, 'name')); if not name then return fail(Lp(src, 'fac.pick_a_squad_name_2_characters')) end
    local s = summary(src)
    local ranks = defaultRanks()
    local id = ins('INSERT INTO bs_squads(name, faction_id, leader_char, ranks) VALUES(?,?,?,?)', { name, fid, cid, json.encode(ranks) })
    id = tonumber(id); if not id then return fail(Lp(src, 'fac.could_not_create_the_squad')) end
    local nsq = { id = id, name = name, factionId = fid, leader = cid, ranks = ranks, members = {} }
    nsq.members[cid] = { rankId = ranks[1].id, name = s and s.name or '' }
    Squads[id] = nsq; ByChar[cid] = id
    x('INSERT INTO bs_squad_members(character_id, squad_id, rank_id, name) VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE squad_id=VALUES(squad_id), rank_id=VALUES(rank_id), name=VALUES(name)', { cid, id, ranks[1].id, s and s.name or '' })
    Invites[tonumber(src)] = nil
    push(src)
    return { ok = true, squad = fullState(src) }
end

local function invite(src, data)
    local cid, sq = mine(src)
    if not sq then return fail(Lp(src, 'fac.you_are_not_in_a_squad')) end
    if sq.leader ~= cid then return fail(Lp(src, 'fac.only_the_squad_leader_may_invite')) end
    local target = tonumber(arg(data, 'target'))
    if not target or target == tonumber(src) or not GetPlayerName(target) then return fail(Lp(src, 'fac.that_survivor_is_unavailable')) end
    local tcid = charOf(target); if not tcid then return fail(Lp(src, 'fac.that_survivor_is_unavailable')) end
    if ByChar[tcid] then return fail(Lp(src, 'fac.they_are_already_in_a_squad')) end
    if factionOf(target) ~= sq.factionId or factionOf(src) ~= sq.factionId then return fail(Lp(src, 'fac.only_members_of_your_faction_can_joi')) end
    if count(sq) >= maxSize() then return fail(Lp(src, 'squad.full_n', { n = maxSize() })) end
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if not a or a == 0 or not b or b == 0 or #(GetEntityCoords(a) - GetEntityCoords(b)) > (tonumber(Cfg.inviteDistance) or 25.0) then
        return fail(Lp(src, 'fac.stand_closer_to_invite_them'))
    end
    local s = summary(src)
    Invites[target] = { squadId = sq.id, by = cid, byName = s and s.name or 'A survivor', until_ = os.time() + (tonumber(Cfg.inviteSeconds) or 60) }
    TriggerClientEvent('bs:squad:invite', target, { squadId = sq.id, name = sq.name, from = Invites[target].byName, seconds = tonumber(Cfg.inviteSeconds) or 60 })
    return { ok = true }
end

local function accept(src)
    src = tonumber(src)
    local cid, cur = mine(src)
    local i = Invites[src]; Invites[src] = nil
    if not cid then return fail(Lp(src, 'fac.character_not_loaded')) end
    if cur then return fail(Lp(src, 'fac.you_are_already_in_a_squad')) end
    local sq = i and Squads[i.squadId]
    if not i or i.until_ < os.time() or not sq then return fail(Lp(src, 'fac.invitation_expired')) end
    if factionOf(src) ~= sq.factionId then return fail(Lp(src, 'fac.that_squad_belongs_to_another_factio')) end
    if count(sq) >= maxSize() then return fail(Lp(src, 'fac.that_squad_is_full')) end
    local s = summary(src)
    local rid = lastRankId(sq)
    sq.members[cid] = { rankId = rid, name = s and s.name or '' }; ByChar[cid] = sq.id
    x('INSERT INTO bs_squad_members(character_id, squad_id, rank_id, name) VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE squad_id=VALUES(squad_id), rank_id=VALUES(rank_id), name=VALUES(name)', { cid, sq.id, rid, s and s.name or '' })
    pushSquad(sq)
    return { ok = true, squad = fullState(src) }
end

local function decline(src)
    src = tonumber(src)
    local i = Invites[src]; Invites[src] = nil
    if not i then return fail(Lp(src, 'fac.no_pending_invitation')) end
    local by = SrcOf[i.by]
    if by then TriggerClientEvent('bs:ui:notify', by, { type = 'warn', message = Lp(by, 'fac.your_squad_invitation_was_declined') }) end
    return { ok = true }
end

local function leave(src)
    local cid, sq = mine(src)
    if not sq then return fail(Lp(src, 'fac.you_are_not_in_a_squad')) end
    removeMember(sq, cid)
    if Squads[sq.id] then pushSquad(sq) end
    push(src)
    return { ok = true }
end

local function leaderOnly(src)
    local cid, sq = mine(src)
    if not sq then return nil, nil, fail(Lp(src, 'fac.you_are_not_in_a_squad')) end
    if sq.leader ~= cid then return nil, nil, fail(Lp(src, 'fac.only_the_squad_leader_can_do_that')) end
    return cid, sq
end

local function kick(src, data)
    local cid, sq, err = leaderOnly(src); if err then return err end
    local t = tonumber(arg(data, 'charId'))
    if not t or t == cid or not sq.members[t] then return fail(Lp(src, 'fac.that_member_is_not_in_your_squad')) end
    local tsrc = SrcOf[t]
    removeMember(sq, t)
    pushSquad(sq)
    if tsrc then push(tsrc); TriggerClientEvent('bs:ui:notify', tsrc, { type = 'warn', message = Lp(tsrc, 'fac.you_were_removed_from_the_squad') }) end
    return { ok = true }
end

local function setRank(src, data, rankArg)
    local _, sq, err = leaderOnly(src); if err then return err end
    local t = tonumber(arg(data, 'charId')); local r = tonumber(type(data) == 'table' and data.rankId or rankArg)
    if not t or not sq.members[t] then return fail(Lp(src, 'fac.that_member_is_not_in_your_squad')) end
    if not r or rankOrder(sq, r) == 99 then return fail(Lp(src, 'fac.unknown_rank')) end
    sq.members[t].rankId = r
    x('UPDATE bs_squad_members SET rank_id=? WHERE character_id=?', { r, t })
    pushSquad(sq)
    return { ok = true }
end

local function saveRanksCb(src, data)
    local _, sq, err = leaderOnly(src); if err then return err end
    local list = type(data) == 'table' and (data.ranks or data) or nil
    if type(list) ~= 'table' or #list == 0 then return fail(Lp(src, 'fac.at_least_one_rank_is_required')) end
    if #list > MAXRANKS then return fail(Lp(src, 'squad.max_ranks', { n = MAXRANKS })) end
    local out, used, nextId = {}, {}, 1
    for _, r in ipairs(list) do if type(r) == 'table' and tonumber(r.id) then nextId = math.max(nextId, math.floor(tonumber(r.id)) + 1) end end
    for _, r in ipairs(list) do
        if type(r) ~= 'table' then return fail(Lp(src, 'fac.invalid_rank')) end
        local label = cleanName(r.label); if not label then return fail(Lp(src, 'fac.rank_names_need_2_characters')) end
        local id = tonumber(r.id); id = id and math.floor(id) or nil
        if not id or id < 1 or used[id] then id = nextId; nextId = nextId + 1 end
        used[id] = true
        out[#out + 1] = { id = id, label = label:sub(1, 20) }
    end
    sq.ranks = out
    local last = out[#out].id
    for mcid, m in pairs(sq.members) do
        if not used[m.rankId] then
            m.rankId = (mcid == sq.leader) and out[1].id or last
            x('UPDATE bs_squad_members SET rank_id=? WHERE character_id=?', { m.rankId, mcid })
        end
    end
    saveRanks(sq)
    pushSquad(sq)
    return { ok = true, ranks = out }
end

local function rename(src, data)
    local _, sq, err = leaderOnly(src); if err then return err end
    local name = cleanName(arg(data, 'name')); if not name then return fail(Lp(src, 'fac.pick_a_squad_name_2_characters')) end
    sq.name = name; saveRanks(sq); pushSquad(sq)
    return { ok = true }
end

local function disband(src)
    local _, sq, err = leaderOnly(src); if err then return err end
    local srcs = {}
    for mcid in pairs(sq.members) do ByChar[mcid] = nil; if SrcOf[mcid] then srcs[#srcs + 1] = SrcOf[mcid] end end
    sq.members = {}; Squads[sq.id] = nil
    x('DELETE FROM bs_squad_members WHERE squad_id=?', { sq.id })
    x('DELETE FROM bs_squads WHERE id=?', { sq.id })
    for _, s in ipairs(srcs) do push(s) end
    return { ok = true }
end

local function transfer(src, data)
    local cid, sq, err = leaderOnly(src); if err then return err end
    local t = tonumber(arg(data, 'charId'))
    if not t or t == cid or not sq.members[t] then return fail(Lp(src, 'fac.that_member_is_not_in_your_squad')) end
    local old = sq.members[t].rankId
    sq.leader = t
    sq.members[t].rankId = sq.ranks[1].id
    sq.members[cid].rankId = (old ~= sq.ranks[1].id) and old or (sq.ranks[2] and sq.ranks[2].id or old)
    x('UPDATE bs_squad_members SET rank_id=? WHERE character_id=?', { sq.members[t].rankId, t })
    x('UPDATE bs_squad_members SET rank_id=? WHERE character_id=?', { sq.members[cid].rankId, cid })
    saveRanks(sq); pushSquad(sq)
    return { ok = true }
end

-- Faction mates close enough to invite, for the console's invite list.
local function nearby(src)
    local cid, sq = mine(src)
    if not sq then return fail(Lp(src, 'fac.you_are_not_in_a_squad')) end
    local me = GetPlayerPed(src); if not me or me == 0 then return { ok = true, players = {} } end
    local pos = GetEntityCoords(me); local range = tonumber(Cfg.inviteDistance) or 25.0
    local out = {}
    for _, v in ipairs(GetPlayers()) do
        local t = tonumber(v)
        if t ~= tonumber(src) then
            local ped = GetPlayerPed(t)
            if ped and ped ~= 0 then
                local d = #(GetEntityCoords(ped) - pos)
                local tcid = d <= range and charOf(t)
                if tcid and not ByChar[tcid] and factionOf(t) == sq.factionId then
                    local s = summary(t)
                    out[#out + 1] = { src = t, name = s and s.name or GetPlayerName(t), level = s and s.level or nil, dist = math.floor(d) }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return { ok = true, players = out, range = range, isLeader = sq.leader == cid }
end

local function get(src)
    validate(src)
    local st = fullState(src)
    local i = Invites[tonumber(src)]
    local pending = nil
    if i and i.until_ >= os.time() and Squads[i.squadId] then
        pending = { squadId = i.squadId, name = Squads[i.squadId].name, from = i.byName, expiresIn = i.until_ - os.time() }
    end
    return { ok = true, squad = st, invite = pending, maxSize = maxSize(), maxRanks = MAXRANKS }
end

local function guard(fn)
    return function(src, ...)
        if not Loaded then return fail(Lp(src, 'fac.squads_are_still_loading')) end
        return fn(src, ...)
    end
end
BSB.RegisterCallback('squad:get', guard(get))
BSB.RegisterCallback('squad:create', guard(create))
BSB.RegisterCallback('squad:invite', guard(invite))
BSB.RegisterCallback('squad:accept', guard(accept))
BSB.RegisterCallback('squad:decline', guard(decline))
BSB.RegisterCallback('squad:leave', guard(leave))
BSB.RegisterCallback('squad:kick', guard(kick))
BSB.RegisterCallback('squad:setRank', guard(setRank))
BSB.RegisterCallback('squad:saveRanks', guard(saveRanksCb))
BSB.RegisterCallback('squad:rename', guard(rename))
BSB.RegisterCallback('squad:disband', guard(disband))
BSB.RegisterCallback('squad:transfer', guard(transfer))
BSB.RegisterCallback('squad:nearby', guard(nearby))

-- exports
-- Drops a character from their squad (online or not). Used by faction kicks.
function SquadRemoveChar(cid)
    cid = tonumber(cid); local id = cid and ByChar[cid]; local sq = id and Squads[id]
    if not sq then return false end
    removeMember(sq, cid)
    if Squads[sq.id] then pushSquad(sq) end
    return true
end
exports('RemoveCharFromSquad', SquadRemoveChar)
exports('GetSquad', function(src)
    local cid, sq = mine(src); if not sq then return nil end
    local m = sq.members[cid]
    return { id = sq.id, name = sq.name, rankId = m.rankId, rankLabel = rankLabel(sq, m.rankId), isLeader = sq.leader == cid }
end)
exports('GetSquadMembers', function(src)
    local _, sq = mine(src); if not sq then return {} end
    local out = {}
    for mcid, m in pairs(sq.members) do
        local msrc = SrcOf[mcid]; local s = msrc and summary(msrc)
        out[#out + 1] = { src = msrc, charId = mcid, name = (s and s.name) or m.name, level = s and s.level or nil,
            rankId = m.rankId, rankLabel = rankLabel(sq, m.rankId) }
    end
    return out
end)
exports('SameSquad', function(a, b)
    local ca, cb = charOf(a), charOf(b)
    return ca ~= nil and cb ~= nil and ByChar[ca] ~= nil and ByChar[ca] == ByChar[cb]
end)

--------------------------------------------------------------------------- lifecycle
local function onLoaded(src)
    src = tonumber(src); if not src then return end
    local old = Online[src]
    if old and SrcOf[old] == src then SrcOf[old] = nil end
    Online[src] = nil
    local cid = charOf(src)
    if not cid then return end
    local id = ByChar[cid]; local sq = id and Squads[id]
    if sq then
        local s = summary(src)
        if s and s.name and sq.members[cid].name ~= s.name then
            sq.members[cid].name = s.name
            x('UPDATE bs_squad_members SET name=? WHERE character_id=?', { s.name, cid })
        end
    end
    validate(src)
    local nid = ByChar[cid]
    if nid and Squads[nid] then pushSquad(Squads[nid]) else push(src) end
end

AddEventHandler('bs:hook:player:loaded', function(pl)
    if not (pl and pl.source) then return end
    local src = pl.source
    CreateThread(function()
        while not Loaded do Wait(250) end
        Wait(500) -- let sv_service load the faction state first
        onLoaded(src)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not src then return end
    local cid = Online[src]
    Online[src] = nil; Invites[src] = nil
    if cid and SrcOf[cid] == src then SrcOf[cid] = nil end
    local id = cid and ByChar[cid]
    if id and Squads[id] then pushSquad(Squads[id]) end
end)

CreateThread(function()
    loadAll()
    for _, v in ipairs(GetPlayers()) do onLoaded(tonumber(v)) end
    while true do
        Wait(tonumber(Cfg.revalidateMs) or 30000)
        for src in pairs(Online) do
            if GetPlayerName(src) then validate(src) else local c = Online[src]; Online[src] = nil; if c and SrcOf[c] == src then SrcOf[c] = nil end end
        end
        for src, i in pairs(Invites) do if i.until_ < os.time() then Invites[src] = nil end end
    end
end)
