-- bs_factions - staff console behind the hub's ADMIN tab. Every callback re-checks the ACE (bs.admin / bs.superadmin) and logs one audit line.

local C, G = FactionsCore, FactionsProg
local MARKS = { wolf = true, skull = true, claw = true, shield = true, eye = true, bolt = true, crown = true, serpent = true }

local function fail(key) return { ok = false, errKey = key } end
local function int(v) local n = tonumber(v); return n and math.floor(n) or nil end

local function audit(src, what, fid, detail)
    print(('^3[BS FACTION ADMIN]^7 %s (#%s) -> %s [%s] %s'):format(GetPlayerName(src) or '?', tostring(src), what, tostring(fid or '-'), detail or ''))
end

-- Online source for a character, if any.
local function srcOf(cid)
    for s, st in pairs(C.State) do if st.cid == cid then return s end end
end

-- Push tag/state to every online member of a faction (and to one extra src).
local function resync(fid, extra)
    for s, st in pairs(C.State) do if st.id == fid or s == extra then C.sync(s) end end
end

local function progress(fid)
    if not G or not G.ready() then return nil end
    return G.freshBoard(G.load(fid))
end

-- Wraps a handler: ACE gate, faction lookup, audit line, errors never escape.
local function admin(name, needFaction, fn)
    local function handle(src, a)
        if not C.isAdmin(src) then return fail('fac.adm.notallowed') end
        if not C.ready() then return fail('fac.adm.starting') end
        a = type(a) == 'table' and a or {}
        local f
        if needFaction then
            f = C.Registry[tostring(a.id or '')]
            if not f then return fail('fac.adm.nofaction') end
        end
        local ok, res = pcall(fn, src, a, f)
        if not ok then
            print(('^1[BS FACTION ADMIN]^7 %s failed: %s'):format(name, tostring(res)))
            return fail('fac.adm.errored')
        end
        if type(res) == 'table' and res.ok ~= false and name ~= 'overview' and name ~= 'detail' then
            audit(src, name, f and f.id, json.encode(a))
        end
        return res
    end
    BSB.RegisterCallback('factions:admin:' .. name, function(src, a)
        local res = handle(src, a)
        if type(res) == 'table' and res.errKey then
            res.error = Lp(src, res.errKey)
            res.errKey = nil
        end
        return res
    end)
end

--------------------------------------------------------------------- reads
admin('overview', false, function()
    local counts = {}
    for _, r in ipairs(C.q('SELECT faction_id, COUNT(*) AS n FROM bs_faction_members GROUP BY faction_id')) do counts[r.faction_id] = tonumber(r.n) or 0 end
    local list = {}
    for id, f in pairs(C.Registry) do
        local d = G and G.ready() and G.load(id)
        list[#list + 1] = { id = id, label = f.label, short = f.short, logo = f.logo, isConfig = f.config, members = counts[id] or 0, level = d and d.level or 1 }
    end
    table.sort(list, function(a, b) if a.isConfig ~= b.isConfig then return a.isConfig end return a.label < b.label end)
    local online = {}
    for s, st in pairs(C.State) do
        online[#online + 1] = { src = s, charId = st.cid, name = GetPlayerName(s) or ('#' .. s), factionId = st.id }
    end
    table.sort(online, function(a, b) return a.src < b.src end)
    return { ok = true, factions = list, online = online }
end)

admin('detail', true, function(_, _, f)
    local reps = {}
    for _, r in ipairs(C.q('SELECT character_id, reputation FROM bs_faction_reputation WHERE faction_id=?', { f.id })) do reps[tonumber(r.character_id)] = tonumber(r.reputation) or 0 end
    local roster = C.members(f.id)
    for _, m in ipairs(roster) do
        local st = m.src and C.State[m.src]
        m.rep = (st and st.rep) or reps[m.charId] or 0
    end
    local out = { ok = true, id = f.id, label = f.label, short = f.short, description = f.description or '', logo = f.logo,
        isConfig = f.config, owner = f.owner, members = roster, treasury = C.treasury(f.id).balance, ranks = {} }
    for _, r in ipairs(C.ranksOf(f.id)) do out.ranks[#out.ranks + 1] = { id = r.id, label = r.label } end
    local d = progress(f.id)
    if d then
        local skills = {}
        for _, sk in ipairs(G.P.Skills) do skills[#skills + 1] = { id = sk.id, label = sk.label, ranks = sk.ranks, rank = d.skills[sk.id] or 0 } end
        local colours = {}
        for _, c in ipairs(G.P.Unlocks.colours) do colours[#colours + 1] = { id = c.id, hex = c.hex } end
        out.progress = { level = d.level, maxLevel = G.P.maxLevel, xp = d.xp, xpIntoLevel = d.xp - G.xpForLevel(d.level), xpToNext = G.xpToNext(d.level),
            points = G.pointsTotal(d) - G.pointsSpent(d), bonus = d.bonus or 0, colour = d.colour, colours = colours, skills = skills }
        out.missions = G.missionView(d)
    end
    local okF, flags = pcall(function() return exports.bs_faction_bases:ListFlags(f.id) end)
    out.flags = okF and flags or {}
    return out
end)

----------------------------------------------------------------- progression
admin('progress', true, function(_, a, f)
    local d = progress(f.id); if not d then return fail('fac.adm.progstart') end
    local op, v = tostring(a.op or ''), int(a.value)
    if not v then return fail('fac.adm.num') end
    local cap = G.xpForLevel(G.P.maxLevel)
    if op == 'setXp' then d.xp = v
    elseif op == 'addXp' then d.xp = d.xp + v
    elseif op == 'setLevel' then d.xp = G.xpForLevel(math.max(1, math.min(G.P.maxLevel, v)))
    else return fail('fac.adm.badop') end
    d.xp = math.max(0, math.min(cap, d.xp))
    local before = d.level
    d.level = G.levelFromXp(d.xp)
    G.saveCore(d); G.broadcast(d)
    if d.level ~= before then TriggerEvent('bs:factions:levelUp', d.id, d.level, before) end
    return { ok = true, level = d.level, xp = d.xp }
end)

admin('points', true, function(_, a, f)
    local d = progress(f.id); if not d then return fail('fac.adm.progstart') end
    local v = int(a.value); if not v then return fail('fac.adm.num') end
    -- "set" means free points; the stored value is the bonus on top of level - 1
    if a.op == 'set' then d.bonus = (d.bonus or 0) + (v - (G.pointsTotal(d) - G.pointsSpent(d)))
    else d.bonus = (d.bonus or 0) + v end
    G.saveCore(d)
    return { ok = true, points = G.pointsTotal(d) - G.pointsSpent(d) }
end)

admin('skill', true, function(_, a, f)
    local d = progress(f.id); if not d then return fail('fac.adm.progstart') end
    local sk = G.SkillById[tostring(a.skillId or '')]; if not sk then return fail('fac.adm.badskill') end
    local r = math.max(0, math.min(sk.ranks, int(a.rank) or 0))
    if r == 0 then
        d.skills[sk.id] = nil
        C.x('DELETE FROM bs_faction_skills WHERE faction_id=? AND skill_id=?', { d.id, sk.id })
    else
        d.skills[sk.id] = r
        C.x('INSERT INTO bs_faction_skills (faction_id, skill_id, `rank`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `rank`=VALUES(`rank`)', { d.id, sk.id, r })
    end
    TriggerEvent('bs:factions:skillChanged', d.id, sk.id, r)
    return { ok = true, rank = r }
end)

admin('reputation', true, function(_, a, f)
    local v = int(a.value); if not v then return fail('fac.adm.num') end
    local maxRep = (Factions.Settings and Factions.Settings.maxReputation) or 1000000
    local targets = {}
    if int(a.charId) then targets[1] = int(a.charId)
    else for _, m in ipairs(C.members(f.id)) do targets[#targets + 1] = m.charId end end
    for _, cid in ipairs(targets) do
        local s = srcOf(cid); local st = s and C.State[s]
        if st and st.id == f.id then
            st.rep = math.max(0, math.min(maxRep, a.op == 'set' and v or (st.rep or 0) + v))
            C.save(st); C.sync(s)
        elseif a.op == 'set' then
            C.x('INSERT INTO bs_faction_reputation(character_id,faction_id,reputation) VALUES(?,?,?) ON DUPLICATE KEY UPDATE reputation=VALUES(reputation)', { cid, f.id, math.max(0, v) })
        else
            C.x('INSERT INTO bs_faction_reputation(character_id,faction_id,reputation) VALUES(?,?,GREATEST(0,?)) ON DUPLICATE KEY UPDATE reputation=GREATEST(0,reputation+?)', { cid, f.id, v, v })
        end
    end
    return { ok = true, count = #targets }
end)

admin('treasury', true, function(src, a, f)
    local v = int(a.value); if not v then return fail('fac.adm.num') end
    local bal = C.treasury(f.id).balance
    local want = math.max(0, a.op == 'set' and v or bal + v)
    C.x('INSERT INTO bs_faction_banks(faction_id,balance) VALUES(?,?) ON DUPLICATE KEY UPDATE balance=VALUES(balance)', { f.id, want })
    C.BankBalances[f.id] = want
    local delta = want - bal
    if delta ~= 0 then
        C.x('INSERT INTO bs_faction_bank_log(faction_id,character_id,direction,amount,note) VALUES(?,NULL,?,?,?)',
            { f.id, delta > 0 and 'deposit' or 'withdraw', math.abs(delta), ('Admin adjust by %s'):format(GetPlayerName(src) or '?'):sub(1, 96) })
    end
    return { ok = true, balance = want }
end)

--------------------------------------------------------------------- members
local function detach(cid)
    C.x('DELETE FROM bs_faction_members WHERE character_id=?', { cid })
    if SquadRemoveChar then pcall(SquadRemoveChar, cid) end
    local s = srcOf(cid)
    if s then local st = C.State[s]; C.save(st); st.id = nil; st.rank = nil; st.rep = 0; C.sync(s) end
end

admin('addMember', true, function(_, a, f)
    local cid = int(a.charId)
    if not cid and int(a.serverId) then local st = C.State[int(a.serverId)]; cid = st and st.cid end
    if not cid then return fail('fac.adm.pickchar') end
    local row = C.one('SELECT id FROM bs_characters WHERE id=? AND deleted_at IS NULL LIMIT 1', { cid })
    if not row then return fail('fac.adm.nochar') end
    local rank = tostring(a.rank or '')
    if rank == 'owner' or not C.rankValid(f.id, rank) then rank = C.lowestRank(f.id) end
    detach(cid) -- moves them out of any current faction first
    C.x('INSERT INTO bs_faction_members(character_id,faction_id,rank) VALUES(?,?,?)', { cid, f.id, rank })
    local s = srcOf(cid)
    if s then local st = C.State[s]; st.id = f.id; st.rank = rank; st.rep = 0; C.sync(s) end
    return { ok = true }
end)

admin('removeMember', true, function(_, a, f)
    local cid = int(a.charId); if not cid then return fail('fac.adm.pickmember') end
    local m = C.one('SELECT rank FROM bs_faction_members WHERE character_id=? AND faction_id=? LIMIT 1', { cid, f.id })
    if not m then return fail('fac.adm.notmember') end
    detach(cid)
    if m.rank == 'owner' then
        C.x('UPDATE bs_faction_registry SET owner_character_id=NULL WHERE faction_id=?', { f.id }); f.owner = nil
    end
    return { ok = true }
end)

local function transfer(f, cid)
    local second = C.secondRank(f.id)
    C.x("UPDATE bs_faction_members SET rank=? WHERE faction_id=? AND rank='owner'", { second, f.id })
    C.x("UPDATE bs_faction_members SET rank='owner' WHERE faction_id=? AND character_id=?", { f.id, cid })
    C.x('UPDATE bs_faction_registry SET owner_character_id=? WHERE faction_id=?', { cid, f.id })
    f.owner = cid
    for s, st in pairs(C.State) do
        if st.id == f.id then
            if st.cid == cid then st.rank = 'owner' elseif st.rank == 'owner' then st.rank = second end
            C.sync(s)
        end
    end
end

admin('setRank', true, function(_, a, f)
    local cid, rank = int(a.charId), tostring(a.rank or '')
    if not cid or (rank ~= 'owner' and not C.rankValid(f.id, rank)) then return fail('fac.adm.pickrank') end
    local m = C.one('SELECT rank FROM bs_faction_members WHERE character_id=? AND faction_id=? LIMIT 1', { cid, f.id })
    if not m then return fail('fac.adm.notmember') end
    if rank == 'owner' then transfer(f, cid); return { ok = true } end
    if m.rank == 'owner' then return fail('fac.adm.ownerfirst') end
    C.x('UPDATE bs_faction_members SET rank=? WHERE character_id=? AND faction_id=?', { rank, cid, f.id })
    local s = srcOf(cid); if s then C.State[s].rank = rank; C.sync(s) end
    return { ok = true }
end)

admin('transfer', true, function(_, a, f)
    local cid = int(a.charId); if not cid then return fail('fac.adm.pickmember') end
    if not C.one('SELECT 1 AS y FROM bs_faction_members WHERE character_id=? AND faction_id=? LIMIT 1', { cid, f.id }) then
        return fail('fac.adm.leadermember')
    end
    transfer(f, cid)
    return { ok = true }
end)

admin('disband', true, function(_, _, f)
    for _, m in ipairs(C.members(f.id)) do if SquadRemoveChar then pcall(SquadRemoveChar, m.charId) end end
    for s, st in pairs(C.State) do if st.id == f.id then C.save(st); st.id = nil; st.rank = nil; st.rep = 0; C.sync(s) end end
    C.x('DELETE FROM bs_faction_members WHERE faction_id=?', { f.id })
    pcall(function() exports.bs_faction_bases:ClearFaction(f.id) end)
    if f.config then
        -- lore factions stay in the registry, just emptied
        C.x('UPDATE bs_faction_registry SET owner_character_id=NULL WHERE faction_id=?', { f.id }); f.owner = nil
        return { ok = true, emptied = true }
    end
    C.x('DELETE FROM bs_faction_registry WHERE faction_id=?', { f.id })
    C.x('DELETE FROM bs_faction_rank_perms WHERE faction_id=?', { f.id })
    C.x('DELETE FROM bs_faction_ranks WHERE faction_id=?', { f.id })
    C.PermCache[f.id] = nil
    C.Registry[f.id] = nil
    return { ok = true, removed = true }
end)

--------------------------------------------------------------------- missions
admin('reroll', true, function(_, a, f)
    local d = progress(f.id); if not d then return fail('fac.adm.progstart') end
    local period = tostring(a.period or '')
    if period ~= 'daily' and period ~= 'weekly' then return fail('fac.adm.period') end
    G.roll(d, period)
    return { ok = true }
end)

admin('completeMission', true, function(_, a, f)
    local d = progress(f.id); if not d then return fail('fac.adm.progstart') end
    local period = tostring(a.period or '')
    local m = d.board[period] and d.board[period][int(a.slot) or 0]
    if not m then return fail('fac.adm.nomission') end
    if m.done then return fail('fac.adm.done') end
    m.progress = m.target
    G.complete(d, period, m)
    return { ok = true }
end)

-- Today's donation XP caps and withdraw caps for the whole faction.
admin('resetCooldowns', true, function(_, _, f)
    C.x('DELETE FROM bs_faction_donations WHERE faction_id=? AND day=CURDATE()', { f.id })
    C.x('DELETE FROM bs_faction_bank_daily WHERE faction_id=? AND day=CURDATE()', { f.id })
    return { ok = true }
end)

------------------------------------------------------------------------ flags
admin('flagTeleport', false, function(src, a)
    local ok, flags = pcall(function() return exports.bs_faction_bases:ListFlags() end)
    if not ok then return fail('fac.adm.nobases') end
    for _, fl in ipairs(flags or {}) do
        if fl.id == int(a.flagId) then
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then return fail('fac.adm.noped') end
            SetEntityCoords(ped, fl.x + 0.0, fl.y + 0.0, fl.z + 1.0, false, false, false, false)
            return { ok = true }
        end
    end
    return fail('fac.adm.noflag')
end)

admin('flagRemove', false, function(_, a)
    local ok, done = pcall(function() return exports.bs_faction_bases:AdminRemoveFlag(int(a.flagId)) end)
    if not ok then return fail('fac.adm.nobases') end
    return done and { ok = true } or fail('fac.adm.noflag')
end)

--------------------------------------------------------------------- identity
admin('identity', true, function(_, a, f)
    local label = tostring(a.label or f.label):gsub('[%c]', ''):sub(1, 48)
    local short = tostring(a.short or f.short):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
    if #label < 3 or #short < 2 then return fail('fac.adm.namelen') end
    local logo = f.logo
    if a.mark or a.color then
        local mark, color = tostring(a.mark or ''):lower(), tostring(a.color or ''):lower()
        if not MARKS[mark] or not color:match('^#%x%x%x%x%x%x$') then return fail('fac.adm.emblem') end
        logo = json.encode({ mark = mark, color = color })
    end
    C.x('UPDATE bs_faction_registry SET label=?, short=?, logo=? WHERE faction_id=?', { label, short, logo, f.id })
    f.label, f.short, f.logo = label, short, logo
    -- tag colour ignores the level gate for staff
    if a.tagColour and G and G.ready() then
        local d = G.load(f.id)
        for _, c in ipairs(G.P.Unlocks.colours) do if c.id == a.tagColour then d.colour = c.id end end
        G.saveCore(d); G.broadcast(d)
    end
    resync(f.id)
    return { ok = true }
end)

admin('clearBriefing', true, function(_, _, f)
    C.x('UPDATE bs_faction_registry SET description=? WHERE faction_id=?', { '', f.id })
    f.description = ''
    return { ok = true }
end)

-------------------------------------------------------- bs_admin F10 exports
-- Plain data for the staff menu's PLAYER view. bs_admin does the staff check and the logging; these only apply.
exports('AdminFactionList', function()
    local out = {}
    for id, f in pairs(C.Registry) do
        local ranks = {}
        for _, r in ipairs(C.ranksOf(id)) do ranks[#ranks + 1] = { id = r.id, label = r.label } end
        out[#out + 1] = { id = id, label = f.label, isConfig = f.config, ranks = ranks }
    end
    table.sort(out, function(a, b) if a.isConfig ~= b.isConfig then return a.isConfig end return a.label < b.label end)
    return out
end)

-- A leader who leaves takes the leader seat with them.
local function releaseLeader(cid)
    for _, f in pairs(C.Registry) do
        if f.owner == cid then
            C.x('UPDATE bs_faction_registry SET owner_character_id=NULL WHERE faction_id=?', { f.id })
            f.owner = nil
        end
    end
end

-- factionId nil = out of any faction. rank 'owner' makes them the Leader; an unknown rank means the bottom one.
exports('AdminSetMember', function(charId, factionId, rank)
    charId = int(charId)
    if not charId or not C.ready() then return false, 'Faction service is starting.' end
    if not factionId then releaseLeader(charId); detach(charId); return true end

    local f = C.Registry[tostring(factionId)]
    if not f then return false, 'Faction not found.' end
    rank = tostring(rank or '')

    local cur = C.one('SELECT faction_id FROM bs_faction_members WHERE character_id=? LIMIT 1', { charId })
    if not cur or cur.faction_id ~= f.id then
        releaseLeader(charId)
        detach(charId)
        local low = C.lowestRank(f.id)
        C.x('INSERT INTO bs_faction_members(character_id,faction_id,rank) VALUES(?,?,?)', { charId, f.id, low })
        local s = srcOf(charId)
        if s then local st = C.State[s]; st.id = f.id; st.rank = low; st.rep = 0; C.sync(s) end
    end

    if rank == 'owner' then transfer(f, charId); return true end
    if not C.rankValid(f.id, rank) then return true end
    if f.owner == charId then return false, 'Make someone else the leader first.' end
    C.x('UPDATE bs_faction_members SET rank=? WHERE character_id=? AND faction_id=?', { rank, charId, f.id })
    local s = srcOf(charId)
    if s then C.State[s].rank = rank; C.sync(s) end
    return true
end)
