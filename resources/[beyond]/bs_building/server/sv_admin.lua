-- bs_building staff tools (F10 > Bases). Every callback checks the ace itself.

local function isAdmin(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
local S = Building.Settings

local function label(fac)
    local row = fac and Store.q('SELECT `label` FROM `bs_faction_registry` WHERE `faction_id` = ? LIMIT 1', { fac })[1]
    return row and row.label or (fac or 'none')
end

-- Bases are grouped by owner (character). Old pieces with no owner group under their faction.
local function keyOf(r)
    if r.owner then return 'c:' .. r.owner end
    return 'f:' .. (r.fac or 'none')
end

local function names(ids)
    local out = {}
    if #ids == 0 then return out end
    local marks = {}
    for i = 1, #ids do marks[i] = '?' end
    for _, row in ipairs(Store.q(('SELECT `id`, `first_name`, `last_name` FROM `bs_characters` WHERE `id` IN (%s)'):format(table.concat(marks, ',')), ids)) do
        out[tonumber(row.id)] = ('%s %s'):format(row.first_name or '', row.last_name or '')
    end
    return out
end

function Building.AdminBases()
    local bases, ids, seen = {}, {}, {}
    for _, r in pairs(Store.pieces) do
        local k = keyOf(r)
        local b = bases[k]
        if not b then
            b = { key = k, owner = r.owner, fac = r.fac, count = 0, frames = 0, x = r.x, y = r.y, z = r.z, lastVisit = Store.bases[r.fac or ''], balance = 0 }
            bases[k] = b
            if r.owner and not seen[r.owner] then seen[r.owner] = true; ids[#ids + 1] = r.owner end
        end
        b.count = b.count + 1
        if not r.built then b.frames = b.frames + 1 end
        if r.decaying then b.decaying = true end
        if r.data and tonumber(r.data.bal) then b.balance = b.balance + math.floor(tonumber(r.data.bal)) end
    end
    local who = names(ids)
    local out = {}
    for _, b in pairs(bases) do
        local facLabel = b.fac and label(b.fac) or nil
        if b.owner then
            b.label = (who[b.owner] or ('#' .. b.owner)) .. (facLabel and (' (' .. facLabel .. ')') or '')
        else
            b.label = facLabel or 'none'
        end
        out[#out + 1] = b
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

BSB.RegisterCallback('build:admin:list', function(src)
    if not isAdmin(src) then return { ok = false } end
    local facs = {}
    for _, row in ipairs(Store.q('SELECT `faction_id`, `label` FROM `bs_faction_registry` ORDER BY `label`')) do
        facs[#facs + 1] = { id = row.faction_id, label = row.label }
    end
    return { ok = true, bases = Building.AdminBases(), factions = facs, raidOpen = Building.RaidOpen(),
             raids = S.raidsEnabled == true, decay = S.decayEnabled == true, decayDays = S.decayDays }
end)

BSB.RegisterCallback('build:admin:pieces', function(src, key)
    if not isAdmin(src) then return { ok = false } end
    local out = {}
    for _, r in pairs(Store.pieces) do
        if keyOf(r) == key then
            out[#out + 1] = { id = r.id, piece = r.piece, x = r.x, y = r.y, z = r.z, hp = math.floor(r.health), mhp = math.floor(Store.maxHp(r)), built = r.built }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return { ok = true, pieces = out }
end)

-- Removes every piece of one base. Storage contents go with it.
function Building.RemoveBase(key, by)
    local list = {}
    for _, r in pairs(Store.pieces) do if keyOf(r) == key then list[#list + 1] = r end end
    for _, r in ipairs(list) do
        local d = Building.Pieces[r.piece]
        if d and d.storage then pcall(function() exports.bs_inventory:ContainerTakeAll('build:' .. r.id) end) end
        Store.remove(r, 'admin')
    end
    Store.log(by, 'admin', ('deleted base %s (%d pieces)'):format(tostring(key), #list), list[1])
    return #list
end

BSB.RegisterCallback('build:admin:act', function(src, action, a, b)
    if not isAdmin(src) then return { ok = false } end
    if action == 'deletePiece' then
        local r = Store.pieces[tonumber(a)]
        if not r then return { ok = false } end
        Store.remove(r, 'admin')
        Store.log(src, 'admin', ('deleted piece #%d %s of %s'):format(r.id, r.piece, keyOf(r)), r)
        return { ok = true }
    elseif action == 'deleteBase' then
        if type(a) ~= 'string' then return { ok = false } end
        return { ok = true, count = Building.RemoveBase(a, src) }
    elseif action == 'transfer' then
        if type(b) ~= 'string' or b == '' then return { ok = false } end
        local n = 0
        for _, r in pairs(Store.pieces) do
            if keyOf(r) == a then r.fac = b; Store.save(r, true); Store.push(r); n = n + 1 end
        end
        Store.bases[b] = os.time()
        Store.log(src, 'admin', ('transferred base %s to %s (%d pieces)'):format(tostring(a), b, n))
        return { ok = true, count = n }
    elseif action == 'resetDecay' then
        if type(a) ~= 'string' then return { ok = false } end
        local fac
        if a:sub(1, 2) == 'f:' then fac = a:sub(3)
        else for _, r in pairs(Store.pieces) do if keyOf(r) == a then fac = r.fac break end end end
        if not fac or fac == 'none' then return { ok = false } end
        a = fac
        Store.bases[a] = os.time()
        Store.x('INSERT INTO `bs_build_bases` (`faction_id`,`last_visit`) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE `last_visit` = NOW()', { a })
        for _, r in pairs(Store.pieces) do
            if r.fac == a and r.decaying then r.decaying = false; Store.push(r) end
        end
        Store.log(src, 'admin', ('reset decay for %s'):format(tostring(a)))
        return { ok = true }
    elseif action == 'teleport' then
        local x, y, z = tonumber(a), tonumber(b), nil
        if type(a) == 'table' then x, y, z = tonumber(a.x), tonumber(a.y), tonumber(a.z) end
        if not x then return { ok = false } end
        TriggerClientEvent('bs:admin:teleportTo', src, x, y, (z or 0) + 1.0)
        return { ok = true }
    end
    return { ok = false }
end)

-- /buildbases: biggest bases in the server console. /removebase <charId>: removes that player's whole base.
RegisterCommand('buildbases', function(src)
    if src ~= 0 and not isAdmin(src) then return end
    if src ~= 0 then TriggerClientEvent('bs:building:admin:open', src) return end
    for i, b in ipairs(Building.AdminBases()) do
        if i > 40 then break end
        print(('[bs_building] %-10s %-32s %4d pieces at %.0f %.0f %.0f'):format(b.key, b.label, b.count, b.x, b.y, b.z))
    end
end, false)

RegisterCommand('removebase', function(src, args)
    if src ~= 0 and not isAdmin(src) then return end
    local charId = tonumber(args[1])
    if not charId then
        if src == 0 then print('[bs_building] removebase <charId>') end
        return
    end
    local n = Building.RemoveBase('c:' .. charId, src)
    if src == 0 then print(('[bs_building] removed %d pieces of character %d'):format(n, charId))
    else TriggerClientEvent('bs:ui:notify', src, { type = 'success', message = Lp(src, 'build.admin.removed', { n = n }), duration = 6000 }) end
end, false)

-- Old staff command, still used by the F10 "clear structures" button.
RegisterCommand('clearbuilds', function(src, args)
    if src ~= 0 and not isAdmin(src) then return end
    local radius = tonumber(args[1])
    local from
    if src ~= 0 then local c = GetEntityCoords(GetPlayerPed(src)); from = { x = c.x, y = c.y, z = c.z } end
    local n = 0
    local list = {}
    for _, r in pairs(Store.pieces) do list[#list + 1] = r end
    for _, r in ipairs(list) do
        if not radius or not from or Store.dist(from, r) <= radius then Store.remove(r, 'admin'); n = n + 1 end
    end
    Store.log(src, 'admin', ('clearbuilds removed %d'):format(n), from)
    print(('^2[BS BUILDING]^7 removed %d pieces'):format(n))
end, false)

-- Quick tools for the F10 BUILD tab (bs_admin calls these after its own staff check)

-- A finished piece with no materials taken. Used by free build.
function Building.PlaceFinished(src, pieceId, pos, h, fac, charId)
    local d = Building.Pieces[pieceId]
    if not d then return nil end
    local dep = {}
    for _, c in ipairs(Building.CostOf(d)) do dep[c.item] = c.amount end
    local id = exports.oxmysql:insert_async(
        'INSERT INTO `bs_build_pieces` (`piece`,`faction_id`,`owner_char`,`x`,`y`,`z`,`h`,`health`,`built`,`deposited`,`data`) VALUES (?,?,?,?,?,?,?,?,1,?,?)',
        { pieceId, fac, charId, pos.x, pos.y, pos.z, h, d.health, json.encode(dep), json.encode(Building.NewData(pieceId)) })
    if not id then return nil end
    local r = { id = id, piece = pieceId, fac = fac, owner = charId, x = pos.x, y = pos.y, z = pos.z, h = h,
                health = d.health, built = true, dep = dep, data = Building.NewData(pieceId), placedAt = os.time() }
    Store.add(r)
    r.health = Store.maxHp(r)
    Store.push(r)
    Store.log(src, 'admin', ('free build %s #%d'):format(pieceId, id), pos)
    return r
end

exports('SetFreeBuild', function(src, on)
    src = tonumber(src)
    if not src or not isAdmin(src) then return false end
    Building.FreeBuild[src] = on and true or nil
    Store.log(src, 'admin', 'free build ' .. (on and 'on' or 'off'))
    return Building.FreeBuild[src] == true
end)
exports('FreeBuildOn', function(src) return Building.FreeBuild[tonumber(src)] == true end)
-- These setters are restricted to bs_admin. Do not expose permission changes to clients.
exports('SetFreeBuildPlayer', function(target, on)
    if GetInvokingResource() ~= 'bs_admin' then return false end
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    local identifier
    for _, id in ipairs(GetPlayerIdentifiers(target)) do
        if id:sub(1, 8) == 'license:' then identifier = id break end
    end
    if not identifier then return false end
    Building.FreeBuildGrants = Building.FreeBuildGrants or {}
    Building.FreeBuildGrants[identifier] = on and { name = GetPlayerName(target) } or nil
    return true
end)
exports('RemoveFreeBuildGrant', function(identifier)
    if GetInvokingResource() ~= 'bs_admin' then return false end
    if type(identifier) ~= 'string' or identifier:sub(1, 8) ~= 'license:' then return false end
    Building.FreeBuildGrants[identifier] = nil
    return true
end)
exports('FreeBuildGrants', function()
    local list = {}
    for identifier, entry in pairs(Building.FreeBuildGrants or {}) do
        local onlineId = nil
        for _, id in ipairs(GetPlayers()) do
            for _, playerIdentifier in ipairs(GetPlayerIdentifiers(tonumber(id))) do
                if playerIdentifier == identifier then onlineId = tonumber(id) break end
            end
            if onlineId then break end
        end
        list[#list + 1] = { identifier = identifier, name = entry.name, source = onlineId }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)
exports('SetFreeBuildAll', function(on)
    if GetInvokingResource() ~= 'bs_admin' then return false end
    Building.FreeBuildAll = on == true
    return true
end)
exports('FreeBuildAllOn', function() return Building.FreeBuildAll == true end)

-- Live only, same switch as F1 "Raids always open".
exports('SetRaidAlways', function(on, by)
    S.raidAlways = on and true or false
    Store.log(by, 'admin', 'raids always open ' .. (S.raidAlways and 'on' or 'off'))
    return S.raidAlways
end)
exports('RaidAlways', function() return S.raidAlways == true end)

-- Every base counts as visited now.
exports('ResetDecayAll', function(by)
    local n, seen = 0, {}
    for _, r in pairs(Store.pieces) do
        if r.fac and not seen[r.fac] then
            seen[r.fac] = true
            Store.bases[r.fac] = os.time()
            Store.x('INSERT INTO `bs_build_bases` (`faction_id`,`last_visit`) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE `last_visit` = NOW()', { r.fac })
            n = n + 1
        end
        if r.decaying then r.decaying = false; Store.push(r) end
    end
    Store.log(by, 'admin', ('reset decay on all bases (%d)'):format(n))
    return n
end)

-- Frames within radius are finished on the spot, materials or not.
exports('FinishInRadius', function(x, y, z, radius, by)
    local n = 0
    for _, r in ipairs(Store.near(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, math.min(tonumber(radius) or 20, 200))) do
        local d = Building.Pieces[r.piece]
        if d and not r.built then
            for _, c in ipairs(Building.CostOf(d)) do r.dep[c.item] = c.amount end
            r.built = true
            r.health = Store.maxHp(r)
            Store.save(r, true)
            Store.push(r)
            n = n + 1
        end
    end
    Store.log(by, 'admin', ('finished %d frames in %.0fm'):format(n, tonumber(radius) or 20), { x = x, y = y, z = z })
    return n
end)

-- F10: individual placed-world objects (not catalogue definitions).
BSB.RegisterCallback('build:admin:placedNearby', function(src)
    if not isAdmin(src) then return {ok=false,error='Keine Berechtigung'} end
    local ped=GetPlayerPed(src)
    if ped == 0 then return {ok=false,error='Spieler nicht geladen'} end
    local pos=GetEntityCoords(ped)
    local list={}
    for _,r in ipairs(Store.near(pos.x,pos.y,pos.z,75.0)) do
        list[#list+1]={id=r.id,piece=r.piece,x=r.x,y=r.y,z=r.z,h=r.h,built=r.built}
    end
    table.sort(list,function(x,y)return x.id<y.id end)
    return {ok=true,list=list}
end)
BSB.RegisterCallback('build:admin:placedAction', function(src, action, id, coords)
    if not isAdmin(src) then return {ok=false,error='Keine Berechtigung'} end
    local r=Store.pieces[tonumber(id)]
    if not r then return {ok=false,error='Objekt nicht gefunden'} end
    local ped=GetPlayerPed(src)
    if ped==0 then return {ok=false,error='Spieler nicht geladen'} end
    local pos=GetEntityCoords(ped)
    if Store.dist(pos,r)>90.0 then return {ok=false,error='Objekt zu weit entfernt'} end
    if action=='delete' then
        Store.log(src,'admin',('deleted placed piece #%d %s'):format(r.id,r.piece),r)
        Store.remove(r,'admin')
        return {ok=true}
    elseif action=='move' then
        if type(coords)~='table' then return {ok=false,error='Position fehlt'} end
        local x,y,z,h=tonumber(coords.x),tonumber(coords.y),tonumber(coords.z),tonumber(coords.h)
        if not x or not y or not z or not h or x~=x or y~=y or z~=z or h~=h then return {ok=false,error='Ungueltige Koordinaten'} end
        if math.abs(x)>10000 or math.abs(y)>10000 or z< -500 or z>2000 then return {ok=false,error='Position ausserhalb Karte'} end
        if Store.dist(pos,{x=x,y=y,z=z})>90 then return {ok=false,error='Ziel zu weit entfernt'} end
        -- Explicitly remove old stream entry before moving between cells.
        Store.pushRemove(r,'admin_move')
        Store.reposition(r,x,y,z,h%360)
        Store.log(src,'admin',('moved placed piece #%d %s'):format(r.id,r.piece),r)
        return {ok=true}
    end
    return {ok=false,error='Unbekannte Aktion'}
end)
