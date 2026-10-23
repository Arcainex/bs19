-- bs_faction_bases - per-player and faction-wide sanctions, faction/global jails.
-- Tables: migration 023_faction_sanctions.sql (also created here if absent).
-- Ranks: owner = Leader, officer = Vice Leader (sanction and jail permissions on by default), member = Member. Admins = bs.admin ace.

local J = FactionBases.Jail
local GLOBAL = J.globalScope
local Active, Jails, Inmates, CharFaction, Ready = {}, {}, {}, {}, false
local RankLevel = { owner=3, officer=2, member=1 }

local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end
local function one(sql, p) return q(sql, p)[1] end
local function x(sql, p) return exports.oxmysql:execute_async(sql, p or {}) end
local function upd(sql, p) return tonumber(exports.oxmysql:update_async(sql, p or {})) or 0 end
local function ins(sql, p) return tonumber(exports.oxmysql:insert_async(sql, p or {})) end
local function admin(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
local function notify(src, msg, kind) if src then TriggerClientEvent('bs:ui:notify', src, { type=kind or 'info', message=msg, duration=6000 }) end end
local function summary(src) local ok, s = pcall(function() return exports.bs_core:GetPlayerSummary(tonumber(src)) end); return ok and s or nil end
local function charOf(src) local s = summary(src); return s and tonumber(s.charId) or nil end
local function srcOfChar(charId)
    charId = tonumber(charId); if not charId then return nil end
    for _, id in ipairs(GetPlayers()) do if charOf(tonumber(id)) == charId then return tonumber(id) end end
    return nil
end
local function facInfo(src) local ok, f = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end); return ok and f or nil end
local function rankAllowed(src, perm) local ok, r = pcall(function() return exports.bs_factions:RankAllowed(tonumber(src), perm) end); return ok and r == true end
local function norm(effect) effect = tostring(effect or ''); return FactionBases.SanctionAliases[effect] or effect end
local function pos(src)
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped); return { x=c.x, y=c.y, z=c.z, h=GetEntityHeading(ped) }
end
local function dist(a, b) local dx, dy, dz = a.x-b.x, a.y-b.y, a.z-b.z; return math.sqrt(dx*dx+dy*dy+dz*dz) end
local function template(id) for _, t in ipairs(FactionBases.SanctionTemplates) do if t.id == id then return t end end; return nil end
-- Callbacks accept either one table ({targetCharId=..}) or positional args.
local function args(names, a, ...)
    if type(a) == 'table' then return a end
    local out, rest = {}, { a, ... }
    for i, n in ipairs(names) do out[n] = rest[i] end
    return out
end

-- Faction of a character (members table), cached briefly.
local function factionOfChar(charId)
    charId = tonumber(charId); if not charId then return nil end
    local c = CharFaction[charId]
    if c and c.at > os.time() - 30 then return c end
    local row = one('SELECT faction_id, `rank` FROM bs_faction_members WHERE character_id=? LIMIT 1', { charId })
    c = { at=os.time(), factionId=row and row.faction_id or nil, rank=row and row.rank or nil }
    CharFaction[charId] = c
    return c
end

---------------------------------------------------------------------- lookups
local function live(row, now) return row and not row.liftedAt and row.endsAt > now end
local function hasFactionWide()
    for _, r in pairs(Active) do if not r.charId then return true end end
    return false
end
-- Strongest value of `effect` on a character: number (percent/amount), true, or nil.
local function playerEffect(charId, effect)
    charId = tonumber(charId); if not charId then return nil end
    effect = norm(effect)
    local now, best, fid = os.time(), nil, nil
    local needFaction = hasFactionWide()
    if needFaction then local f = factionOfChar(charId); fid = f and f.factionId end
    for _, r in pairs(Active) do
        if live(r, now) and (r.charId == charId or (not r.charId and fid and r.factionId == fid)) then
            local v = r.effects[effect]
            if v ~= nil and v ~= false then
                if type(v) == 'number' then best = math.max(type(best) == 'number' and best or 0, v)
                elseif best == nil then best = true end
            end
        end
    end
    if effect == 'jail' and Inmates[charId] then best = best or true end
    return best
end
local function factionEffect(factionId, effect)
    if not factionId then return false end
    effect = norm(effect); local now = os.time()
    for _, r in pairs(Active) do
        if live(r, now) and not r.charId and r.factionId == factionId then
            local v = r.effects[effect]; if v ~= nil and v ~= false then return true end
        end
    end
    return false
end
local function pct(src, effect)
    local cid = charOf(src); if not cid then return 1.0 end
    local v = playerEffect(cid, effect)
    if type(v) ~= 'number' then return 1.0 end
    return math.max(0.0, math.min(1.0, 1.0 - v / 100.0))
end
BSSanctions = { PlayerEffect = playerEffect, FactionEffect = factionEffect, CharOf = charOf }

exports('PlayerSanctioned', function(charId, effect) local v = playerEffect(charId, effect); return v ~= nil and v ~= false end)
exports('PlayerSanctionValue', function(charId, effect) local v = playerEffect(charId, effect); return type(v) == 'number' and v or (v and 1 or 0) end)
exports('XpMultiplier', function(src) return pct(src, 'xp_penalty') end)
exports('DropMultiplier', function(src) return pct(src, 'drop_penalty') end)
exports('IsJailed', function(charId) return Inmates[tonumber(charId) or -1] ~= nil end)

----------------------------------------------------------------------- jails
local function jailOf(scope) return Jails[scope] end
local function cellCount(j) local n = 0; for _ in pairs(j and j.cells or {}) do n = n + 1 end; return n end
local function usableScope(scope)
    if scope and Jails[scope] and cellCount(Jails[scope]) > 0 then return scope end
    if Jails[GLOBAL] and cellCount(Jails[GLOBAL]) > 0 then return GLOBAL end
    return nil
end
local function pickCell(scope)
    local j = Jails[scope]; if not j then return nil end
    local load = {}
    for _, inm in pairs(Inmates) do if inm.scope == scope then load[inm.cell] = (load[inm.cell] or 0) + 1 end end
    local best, bestLoad = nil, math.huge
    for n in pairs(j.cells) do
        local l = load[n] or 0
        if l < bestLoad or (l == bestLoad and n < best) then best, bestLoad = n, l end
    end
    return best
end
local function sendEnter(inm)
    if not inm or not inm.src then return end
    local j = Jails[inm.scope]
    if not j or not j.cells[inm.cell] then
        local scope = usableScope(inm.scope)
        if not scope then return end
        inm.scope = scope; inm.cell = pickCell(scope)
        x('UPDATE bs_jail_inmates SET scope=?, cell=? WHERE character_id=?', { inm.scope, inm.cell, inm.charId })
        j = Jails[scope]
    end
    local c = j.cells[inm.cell]
    TriggerClientEvent('bs:jail:enter', inm.src, { cell=c, cellNo=inm.cell, origin=j.origin, radius=j.radius, remaining=inm.remaining, scope=inm.scope })
end
local function release(charId, why)
    local inm = Inmates[charId]; if not inm then return end
    Inmates[charId] = nil
    x('DELETE FROM bs_jail_inmates WHERE character_id=?', { charId })
    local src = inm.src or srcOfChar(charId)
    if src then
        local j = Jails[inm.scope]
        local exit = j and (j.exit or j.origin) or nil
        TriggerClientEvent('bs:jail:release', src, exit)
        notify(src, why and Lp(src, why) or Lp(src, 'fb.released'), 'success')
    end
end
local function jailChar(charId, sanctionId, scope, seconds)
    scope = usableScope(scope); if not scope then return false, Lp(src, 'fb.no_cells2') end
    local prev = Inmates[charId]
    if prev then seconds = math.max(seconds, prev.remaining) end
    local cell = prev and prev.scope == scope and prev.cell or pickCell(scope)
    x('INSERT INTO bs_jail_inmates(character_id,sanction_id,scope,cell,remaining) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE sanction_id=VALUES(sanction_id),scope=VALUES(scope),cell=VALUES(cell),remaining=VALUES(remaining)', { charId, sanctionId, scope, cell, seconds })
    local inm = { charId=charId, sanctionId=sanctionId, scope=scope, cell=cell, remaining=seconds, src=srcOfChar(charId) }
    Inmates[charId] = inm
    sendEnter(inm)
    return true
end

--------------------------------------------------------------- issue / lift
local function rowOut(r, names)
    local t = template(r.template)
    local name = names and names[r.charId or -1] or nil
    return { id=r.id, charId=r.charId, name=name, factionId=r.factionId, template=r.template, label=t and t.label or r.template, tier=t and t.tier or nil,
        effects=r.effects, reason=r.reason, issuedBy=r.issuedByName, admin=r.admin, createdAt=r.createdAt, endsAt=r.endsAt,
        active=live(r, os.time()), remaining=math.max(0, r.endsAt - os.time()), jailed=r.charId and Inmates[r.charId] and Inmates[r.charId].sanctionId == r.id and Inmates[r.charId].remaining or nil }
end
local function fromDb(v)
    local ok, eff = pcall(json.decode, v.effects_json or '{}')
    return { id=tonumber(v.id), factionId=v.faction_id, charId=tonumber(v.character_id), template=v.template_id, effects=(ok and type(eff) == 'table') and eff or {},
        reason=v.reason, issuedBy=tonumber(v.issued_by), issuedByName=v.issued_by_name, admin=(v.issued_admin == true or tonumber(v.issued_admin) == 1),
        createdAt=tonumber(v.created_at) or 0, endsAt=tonumber(v.ends_at) or 0, fineDue=tonumber(v.fine_due) or 0, liftedAt=tonumber(v.lifted_at) }
end
-- May `src` sanction `charId`? Returns ok, isAdmin, target faction.
local function mayIssue(src, charId)
    local tf = factionOfChar(charId)
    if admin(src) then return true, true, tf end
    local me = facInfo(src); local myChar = charOf(src)
    if not me or not me.factionId or not myChar or myChar == charId then return false end
    if not tf or tf.factionId ~= me.factionId then return false end
    if not (me.rank == 'owner' or rankAllowed(src, 'sanction')) then return false end
    -- only someone strictly below you (custom ranks come from bs_factions' RankIndex, 1 = Leader)
    local okI, mine, theirs = pcall(function()
        return exports.bs_factions:RankIndex(me.factionId, me.rank), exports.bs_factions:RankIndex(me.factionId, tf.rank)
    end)
    if okI and mine and theirs then
        if mine >= theirs then return false end
    elseif (RankLevel[me.rank] or 0) <= (RankLevel[tf.rank] or 0) then return false end
    return true, false, tf
end
local function collectFine(row, src)
    if (row.fineDue or 0) < 1 then return end
    src = src or srcOfChar(row.charId); if not src then return end
    local s = summary(src); local cash = s and s.accounts and tonumber(s.accounts.cash) or 0
    local take = math.min(cash, row.fineDue); if take < 1 then return end
    if not exports.bs_core:RemoveMoney(src, 'cash', take, 'faction sanction fine') then return end
    local left = upd('UPDATE bs_sanctions SET fine_due=GREATEST(0,fine_due-?) WHERE id=?', { take, row.id })
    row.fineDue = row.fineDue - take
    if left > 0 and row.factionId then pcall(function() exports.bs_factions:TreasuryCredit(row.factionId, take, row.charId, 'Sanction fine #' .. row.id) end) end
    notify(src, Lp(src, 'fb.fine', { n = take }) .. (row.fineDue > 0 and (' ' .. Lp(src, 'fb.owed', { n = row.fineDue })) or ''), 'warn')
end

local function issue(src, ...)
    local a = args({ 'targetCharId', 'template', 'minutes', 'reason' }, ...)
    if not Ready then return { ok=false, error=Lp(src, 'fb.sanc_starting') } end
    local t = template(tostring(a.template or '')); if not t then return { ok=false, error=Lp(src, 'fb.unk_tpl') } end
    local isAdmin = admin(src)
    local target = tonumber(a.targetCharId)
    if not target and a.targetSrc then target = charOf(tonumber(a.targetSrc)) end
    local factionWide = isAdmin and not target and a.targetFactionId and tostring(a.targetFactionId) or nil
    if not target and not factionWide then return { ok=false, error=Lp(src, 'fb.target') } end
    local tf
    if target then
        local ok, _, f = mayIssue(src, target)
        if not ok then return { ok=false, error=Lp(src, 'fb.no_sanction') } end
        tf = f
    end
    local minutes = math.floor(tonumber(a.minutes) or t.default)
    minutes = math.max(t.min, math.min(t.max, minutes))
    local reason = tostring(a.reason or ''):gsub('[%c]', ' '):sub(1, 255)
    local effects = {}; for k, v in pairs(t.effects) do effects[k] = v end
    if factionWide then effects.jail = nil end
    local factionId = factionWide or (tf and tf.factionId) or nil
    local jailScope
    if effects.jail then
        local wanted = isAdmin and a.jailScope and tostring(a.jailScope) or factionId
        if wanted == 'global' then wanted = GLOBAL end
        jailScope = usableScope(wanted)
        if not jailScope then return { ok=false, error=Lp(src, 'fb.no_cells') } end
    end
    local now = os.time(); local endsAt = now + minutes * 60
    local by = charOf(src); local bySum = summary(src)
    local byName = isAdmin and ('Admin ' .. (GetPlayerName(src) or '')) or (bySum and bySum.name) or GetPlayerName(src)
    local fine = (not factionWide and tonumber(effects.fine)) or 0
    local id = ins('INSERT INTO bs_sanctions(faction_id,character_id,template_id,effects_json,reason,issued_by,issued_by_name,issued_admin,created_at,ends_at,fine_due) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        { factionId, target, t.id, json.encode(effects), reason, by, tostring(byName or ''):sub(1, 64), isAdmin and 1 or 0, now, endsAt, fine })
    if not id then return { ok=false, error=Lp(src, 'fb.sanc_save') } end
    local row = { id=id, factionId=factionId, charId=target, template=t.id, effects=effects, reason=reason, issuedBy=by, issuedByName=byName, admin=isAdmin, createdAt=now, endsAt=endsAt, fineDue=fine }
    Active[id] = row
    -- Instant effects.
    local repPenalty = tonumber(effects.rep_penalty) or 0
    if repPenalty > 0 then
        if target then pcall(function() exports.bs_factions:AdjustReputation(target, -repPenalty) end)
        else x('UPDATE bs_faction_reputation SET reputation=GREATEST(0,reputation-?) WHERE faction_id=?', { repPenalty, factionId }) end
    end
    if factionWide and (tonumber(effects.fine) or 0) > 0 then
        pcall(function() exports.bs_factions:TreasuryDebit(factionWide, tonumber(effects.fine), 'Sanction fine #' .. id) end)
    end
    local tsrc = target and srcOfChar(target)
    if fine > 0 then collectFine(row, tsrc) end
    if effects.jail and target then
        jailChar(target, id, jailScope, math.min(minutes, t.jailMax or minutes) * 60)
    end
    if tsrc then
        notify(tsrc, Lp(tsrc, 'fb.sanctioned', { name = t.label, min = minutes }) .. (reason ~= '' and (' ' .. Lp(tsrc, 'fb.reason', { why = reason })) or ''), 'error')
        TriggerClientEvent('bs:sanctions:changed', tsrc)
    end
    return { ok=true, id=id, minutes=minutes }
end

local function lift(src, ...)
    local a = args({ 'id' }, ...)
    local id = tonumber(a.id); if not id then return { ok=false, error=Lp(src, 'fb.unk_sanc') } end
    local row = Active[id]
    if not row then local v = one('SELECT * FROM bs_sanctions WHERE id=? LIMIT 1', { id }); row = v and fromDb(v) end
    if not row or row.liftedAt then return { ok=false, error=Lp(src, 'fb.not_active') } end
    local isAdmin = admin(src)
    if not isAdmin then
        if row.admin or not row.charId then return { ok=false, error=Lp(src, 'fb.admin_lift') } end
        if not mayIssue(src, row.charId) then return { ok=false, error=Lp(src, 'fb.no_lift') } end
    end
    local now = os.time()
    upd('UPDATE bs_sanctions SET lifted_at=?, lifted_by=?, fine_due=0 WHERE id=? AND lifted_at IS NULL', { now, charOf(src), id })
    row.liftedAt = now; Active[id] = nil
    if row.charId and Inmates[row.charId] and Inmates[row.charId].sanctionId == id then release(row.charId, 'fb.sentence_lifted') end
    local tsrc = row.charId and srcOfChar(row.charId)
    if tsrc then notify(tsrc, Lp(tsrc, 'fb.lifted'), 'success'); TriggerClientEvent('bs:sanctions:changed', tsrc) end
    return { ok=true }
end

local function list(src, ...)
    local a = args({ 'factionId' }, ...)
    local isAdmin = admin(src); local me = facInfo(src); local myChar = charOf(src)
    local where, params = {}, {}
    if isAdmin then
        if a.factionId and a.factionId ~= '' then where[#where+1] = 's.faction_id=?'; params[#params+1] = tostring(a.factionId) end
        if a.charId then where[#where+1] = 's.character_id=?'; params[#params+1] = tonumber(a.charId) end
    elseif me and me.factionId and (me.rank == 'owner' or rankAllowed(src, 'sanction')) then
        where[#where+1] = 's.faction_id=?'; params[#params+1] = me.factionId
    else
        where[#where+1] = 's.character_id=?'; params[#params+1] = myChar or -1
    end
    if a.activeOnly then where[#where+1] = 's.lifted_at IS NULL AND s.ends_at>?'; params[#params+1] = os.time() end
    local sql = 'SELECT s.*, c.first_name, c.last_name FROM bs_sanctions s LEFT JOIN bs_characters c ON c.id=s.character_id'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    local rows = q(sql .. ' ORDER BY s.id DESC LIMIT 100', params)
    local out, names = {}, {}
    for _, v in ipairs(rows) do
        local r = fromDb(v)
        if r.charId then names[r.charId] = ((v.first_name or '?') .. ' ' .. (v.last_name or '')):gsub('%s+$', '') end
        local o = rowOut(r, names); o.canLift = o.active and (isAdmin or (not r.admin and r.charId ~= nil and r.charId ~= myChar))
        out[#out+1] = o
    end
    return { ok=true, sanctions=out, isAdmin=isAdmin }
end

-- jail management
local function scopeFor(src, a)
    if admin(src) then
        local s = a.scope and tostring(a.scope) or nil
        if s == 'global' or s == GLOBAL then return GLOBAL end
        if s and s ~= '' then return s end
        local me = facInfo(src); return me and me.factionId or GLOBAL
    end
    local me = facInfo(src)
    if me and me.factionId and (me.rank == 'owner' or rankAllowed(src, 'jail')) then return me.factionId end
    return nil
end
local function jailView(scope)
    local j = Jails[scope]; if not j then return nil end
    local occ = {}; for _, inm in pairs(Inmates) do if inm.scope == scope then occ[inm.cell] = (occ[inm.cell] or 0) + 1 end end
    local cells = {}
    for n, c in pairs(j.cells) do cells[#cells+1] = { n=n, x=c.x, y=c.y, z=c.z, h=c.h, occupied=occ[n] or 0 } end
    table.sort(cells, function(p1, p2) return p1.n < p2.n end)
    return { origin=j.origin, radius=j.radius, exit=j.exit, cells=cells }
end
BSB.RegisterCallback('jail:get', function(src, ...)
    local a = args({ 'scope' }, ...)
    local myChar = charOf(src); local mine = myChar and Inmates[myChar]
    local scope = scopeFor(src, a)
    local out = { ok=true, scope=scope, canManage=scope ~= nil, isAdmin=admin(src), jailed=mine and { remaining=mine.remaining, cell=mine.cell } or nil }
    if scope then
        out.jail = jailView(scope)
        local inm = {}
        for cid, v in pairs(Inmates) do if v.scope == scope then inm[#inm+1] = { charId=cid, cell=v.cell, remaining=v.remaining, online=v.src ~= nil, sanctionId=v.sanctionId } end end
        for _, v in ipairs(inm) do local row = one('SELECT first_name,last_name FROM bs_characters WHERE id=? LIMIT 1', { v.charId }); v.name = row and ((row.first_name or '?') .. ' ' .. (row.last_name or '')) or ('#' .. v.charId) end
        out.inmates = inm
    end
    if out.isAdmin then
        local scopes = {}; for s, j in pairs(Jails) do scopes[#scopes+1] = { scope=s, cells=cellCount(j) } end
        out.scopes = scopes
    end
    return out
end)
BSB.RegisterCallback('jail:setOrigin', function(src, ...)
    local a = args({ 'radius', 'scope' }, ...)
    local scope = scopeFor(src, a); if not scope then return { ok=false, error=Lp(src, 'fb.no_jail') } end
    local at = pos(src); if not at then return { ok=false, error=Lp(src, 'fb.pos') } end
    local radius = math.max(5.0, math.min(J.maxRadius, tonumber(a.radius) or (Jails[scope] and Jails[scope].radius) or J.defaultRadius))
    x('INSERT INTO bs_jails(scope,x,y,z,h,radius) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE x=VALUES(x),y=VALUES(y),z=VALUES(z),h=VALUES(h),radius=VALUES(radius)', { scope, at.x, at.y, at.z, at.h, radius })
    local j = Jails[scope] or { cells={} }; j.origin = at; j.radius = radius; Jails[scope] = j
    return { ok=true, jail=jailView(scope) }
end)
BSB.RegisterCallback('jail:setExit', function(src, ...)
    local a = args({ 'scope' }, ...)
    local scope = scopeFor(src, a); if not scope then return { ok=false, error=Lp(src, 'fb.no_jail') } end
    local j = Jails[scope]; if not j then return { ok=false, error=Lp(src, 'fb.origin_first') } end
    local at = pos(src); if not at then return { ok=false, error=Lp(src, 'fb.pos') } end
    x('UPDATE bs_jails SET exit_x=?,exit_y=?,exit_z=?,exit_h=? WHERE scope=?', { at.x, at.y, at.z, at.h, scope })
    j.exit = at; return { ok=true, jail=jailView(scope) }
end)
BSB.RegisterCallback('jail:addCell', function(src, ...)
    local a = args({ 'scope' }, ...)
    local scope = scopeFor(src, a); if not scope then return { ok=false, error=Lp(src, 'fb.no_jail') } end
    local j = Jails[scope]; if not j then return { ok=false, error=Lp(src, 'fb.origin_first') } end
    local at = pos(src); if not at then return { ok=false, error=Lp(src, 'fb.pos') } end
    if dist(at, j.origin) > j.radius then return { ok=false, error=Lp(src, 'fb.cells_radius') } end
    if cellCount(j) >= J.maxCells then return { ok=false, error=Lp(src, 'fb.max_cells') } end
    local n = 1; while j.cells[n] do n = n + 1 end
    x('INSERT INTO bs_jail_cells(scope,n,x,y,z,h) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE x=VALUES(x),y=VALUES(y),z=VALUES(z),h=VALUES(h)', { scope, n, at.x, at.y, at.z, at.h })
    j.cells[n] = at
    return { ok=true, n=n, jail=jailView(scope) }
end)
BSB.RegisterCallback('jail:removeCell', function(src, ...)
    local a = args({ 'n', 'scope' }, ...)
    local scope = scopeFor(src, a); if not scope then return { ok=false, error=Lp(src, 'fb.no_jail') } end
    local j = Jails[scope]; local n = tonumber(a.n)
    if not j or not n or not j.cells[n] then return { ok=false, error=Lp(src, 'fb.no_cell') } end
    for _, inm in pairs(Inmates) do if inm.scope == scope and inm.cell == n then return { ok=false, error=Lp(src, 'fb.occupied') } end end
    x('DELETE FROM bs_jail_cells WHERE scope=? AND n=?', { scope, n })
    j.cells[n] = nil
    return { ok=true, jail=jailView(scope) }
end)
BSB.RegisterCallback('jail:release', function(src, ...)
    local a = args({ 'charId', 'scope' }, ...)
    local cid = tonumber(a.charId); local inm = cid and Inmates[cid]
    if not inm then return { ok=false, error=Lp(src, 'fb.not_jailed') } end
    if not admin(src) then
        local scope = scopeFor(src, a)
        if not scope or inm.scope ~= scope or not mayIssue(src, cid) then return { ok=false, error=Lp(src, 'fb.no_release') } end
    end
    release(cid, 'fb.released_early')
    return { ok=true }
end)

BSB.RegisterCallback('sanctions:templates', function(src)
    local me = facInfo(src); local isAdmin = admin(src)
    return { ok=true, tiers=FactionBases.SanctionTiers, templates=FactionBases.SanctionTemplates, isAdmin=isAdmin,
        canIssue=isAdmin or (me and me.factionId and (me.rank == 'owner' or rankAllowed(src, 'sanction'))) or false }
end)
BSB.RegisterCallback('sanctions:list', list)
BSB.RegisterCallback('sanctions:issue', issue)
BSB.RegisterCallback('sanctions:lift', lift)
BSB.RegisterCallback('sanctions:mine', function(src)
    local cid = charOf(src); local out = {}
    local now = os.time()
    for _, r in pairs(Active) do if live(r, now) and r.charId == cid then out[#out+1] = rowOut(r) end end
    return { ok=true, sanctions=out, jailed=cid and Inmates[cid] and Inmates[cid].remaining or nil }
end)

-- lifecycle
local function onLoaded(src)
    src = tonumber(src); local cid = charOf(src); if not cid then return end
    CharFaction[cid] = nil
    local inm = Inmates[cid]
    if inm then inm.src = src; SetTimeout(3000, function() if Inmates[cid] == inm then sendEnter(inm) end end) end
    for _, r in pairs(Active) do if r.charId == cid and (r.fineDue or 0) > 0 then collectFine(r, src) end end
    local n = 0; local now = os.time()
    for _, r in pairs(Active) do if live(r, now) and r.charId == cid then n = n + 1 end end
    if n > 0 then notify(src, Lp(src, 'fb.active_n', { n = n }), 'warn') end
end
AddEventHandler('bs:hook:player:loaded', function(pl) if pl and pl.source then onLoaded(pl.source) end end)
AddEventHandler('playerDropped', function()
    local src = source
    for cid, inm in pairs(Inmates) do
        if inm.src == src then
            inm.src = nil
            x('UPDATE bs_jail_inmates SET remaining=? WHERE character_id=?', { inm.remaining, cid })
        end
    end
end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    x([[CREATE TABLE IF NOT EXISTS bs_sanctions (id INT UNSIGNED NOT NULL AUTO_INCREMENT, faction_id VARCHAR(32) NULL, character_id INT UNSIGNED NULL, template_id VARCHAR(48) NOT NULL, effects_json TEXT NOT NULL, reason VARCHAR(255) NULL, issued_by INT UNSIGNED NULL, issued_by_name VARCHAR(64) NULL, issued_admin TINYINT(1) NOT NULL DEFAULT 0, created_at BIGINT NOT NULL, ends_at BIGINT NOT NULL, fine_due INT NOT NULL DEFAULT 0, lifted_at BIGINT NULL, lifted_by INT UNSIGNED NULL, PRIMARY KEY(id), KEY ix_bs_sanctions_char(character_id), KEY ix_bs_sanctions_faction(faction_id))]])
    x([[CREATE TABLE IF NOT EXISTS bs_jails (scope VARCHAR(32) NOT NULL, x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, h FLOAT NOT NULL DEFAULT 0, radius FLOAT NOT NULL DEFAULT 25, exit_x DOUBLE NULL, exit_y DOUBLE NULL, exit_z DOUBLE NULL, exit_h FLOAT NULL, PRIMARY KEY(scope))]])
    x([[CREATE TABLE IF NOT EXISTS bs_jail_cells (scope VARCHAR(32) NOT NULL, n INT UNSIGNED NOT NULL, x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, h FLOAT NOT NULL DEFAULT 0, PRIMARY KEY(scope,n))]])
    x([[CREATE TABLE IF NOT EXISTS bs_jail_inmates (character_id INT UNSIGNED NOT NULL, sanction_id INT UNSIGNED NULL, scope VARCHAR(32) NOT NULL, cell INT UNSIGNED NOT NULL, remaining INT NOT NULL, PRIMARY KEY(character_id))]])
    for _, v in ipairs(q('SELECT * FROM bs_sanctions WHERE lifted_at IS NULL AND (ends_at>? OR fine_due>0)', { os.time() })) do local r = fromDb(v); Active[r.id] = r end
    for _, v in ipairs(q('SELECT * FROM bs_jails')) do
        Jails[v.scope] = { origin={ x=tonumber(v.x), y=tonumber(v.y), z=tonumber(v.z), h=tonumber(v.h) or 0 }, radius=tonumber(v.radius) or J.defaultRadius,
            exit=v.exit_x and { x=tonumber(v.exit_x), y=tonumber(v.exit_y), z=tonumber(v.exit_z), h=tonumber(v.exit_h) or 0 } or nil, cells={} }
    end
    for _, v in ipairs(q('SELECT * FROM bs_jail_cells')) do
        local j = Jails[v.scope]; if j then j.cells[tonumber(v.n)] = { x=tonumber(v.x), y=tonumber(v.y), z=tonumber(v.z), h=tonumber(v.h) or 0 } end
    end
    for _, v in ipairs(q('SELECT * FROM bs_jail_inmates')) do
        local cid = tonumber(v.character_id)
        Inmates[cid] = { charId=cid, sanctionId=tonumber(v.sanction_id), scope=v.scope, cell=tonumber(v.cell), remaining=tonumber(v.remaining) or 0 }
    end
    Ready = true
    for _, id in ipairs(GetPlayers()) do onLoaded(tonumber(id)) end
    print('^2[BeyondSurvival]^7 sanctions + jails ready')
end)

-- Jail clock (online time only), radius watchdog, persistence, expiry sweep.
CreateThread(function()
    local tick = 0
    while true do
        Wait(1000)
        if Ready then
            tick = tick + 1
            local done = {}
            for cid, inm in pairs(Inmates) do
                if inm.src and GetPlayerName(inm.src) then
                    inm.remaining = inm.remaining - 1
                    if inm.remaining <= 0 then done[#done+1] = cid
                    elseif tick % 5 == 0 then
                        local j = Jails[inm.scope]; local at = pos(inm.src)
                        if j and at and dist(at, j.origin) > j.radius + 10.0 then sendEnter(inm) end
                    end
                elseif inm.src then inm.src = nil end
            end
            for _, cid in ipairs(done) do release(cid, 'fb.sentence_served') end
            if tick % J.saveEvery == 0 then
                for cid, inm in pairs(Inmates) do if inm.src then x('UPDATE bs_jail_inmates SET remaining=? WHERE character_id=?', { inm.remaining, cid }) end end
            end
            if tick % 30 == 0 then
                local now = os.time()
                for id, r in pairs(Active) do if not live(r, now) and (r.fineDue or 0) < 1 then Active[id] = nil end end
                for cid, c in pairs(CharFaction) do if c.at < now - 60 then CharFaction[cid] = nil end end
            end
        end
    end
end)
