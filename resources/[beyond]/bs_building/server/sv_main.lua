-- bs_building rules. Every request is re-checked here; the client ghost is only a preview.

local S = Building.Settings
local P = Building.Pieces

local function err(src, key, vars) return { ok = false, error = Lp(src, key, vars) } end
local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars), duration = 5000 })
end

local function pedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end
local function dead(src) local ped = GetPlayerPed(src); return not ped or ped == 0 or GetEntityHealth(ped) <= 0 end
local function isAdmin(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
local function player(src) local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end); return ok and p or nil end
local function count(src, item) local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end); return ok and tonumber(n) or 0 end
local function take(src, item, n) local ok, r = pcall(function() return exports.bs_inventory:RemoveItem(src, item, n) end); return ok and r end
local function give(src, item, n) pcall(function() exports.bs_inventory:GiveItem(src, item, n) end) end
local function charOf(src) local p = player(src); return p and p.charId or nil end
local function claimMode() return S.buildMode == 'claim' end

function Building.FactionOf(src)
    local ok, f = pcall(function() return exports.bs_factions:GetFactionSummary(tonumber(src)) end)
    return ok and f and f.factionId or nil
end
local factionOf = Building.FactionOf

-- Rank permission from bs_factions (build / demolish / storage). The Leader has all.
local function can(src, perm)
    local ok, r = pcall(function() return exports.bs_factions:RankAllowed(tonumber(src), perm) end)
    if ok and r ~= nil then return r == true end
    return perm == 'build'
end

local function sanctioned(src)
    if GetResourceState('bs_faction_bases') ~= 'started' then return false end
    local fac = factionOf(src)
    local ok, r = pcall(function() return exports.bs_faction_bases:FactionSanctioned(fac, 'build_lock') end)
    return ok and r == true
end

local function flags(fac)
    if GetResourceState('bs_faction_bases') ~= 'started' then return {} end
    local ok, list = pcall(function() return exports.bs_faction_bases:ListFlags(fac) end)
    local out = {}
    if ok and type(list) == 'table' then
        for _, f in ipairs(list) do if f.status ~= 'removed' then out[#out + 1] = f end end
    end
    return out
end

local function flat(a, b) local dx, dy = a.x - b.x, a.y - b.y; return math.sqrt(dx * dx + dy * dy) end

-- Whose claim covers this point, if any. list = flags(nil) when the caller already has it.
function Building.ClaimAt(at, list)
    for _, f in ipairs(list or flags(nil)) do
        if f.status ~= 'removed' and flat(at, f) <= S.flagRadius then return f end
    end
    return nil
end

-- Pieces inside a safezone flag can never be raided.
function Building.Protected(r)
    local c = Building.ClaimAt(r)
    return c ~= nil and c.kind == 'safezone'
end

local function isVanillaFac(fac)
    if not fac or GetResourceState('bs_faction_bases') ~= 'started' then return false end
    local ok, v = pcall(function() return exports.bs_faction_bases:IsVanilla(fac) end)
    return ok and v == true
end

-- Vanilla safezones and outposts (circles and shapes)
local function inSafeZone(at)
    if GetResourceState('bs_zombies') ~= 'started' then return false end
    local pad = tonumber(S.safeZonePadding) or 0.0
    local ok, hit = pcall(function() return exports.bs_zombies:InSafeZone(at.x, at.y, pad) end)
    if not ok then return true end
    if not hit then return false end
    local okz, zones = pcall(function() return exports.bs_zombies:SafeZones() end)
    if not okz or type(zones) ~= 'table' then return true end
    for _, z in ipairs(zones) do
        -- flags never overlap a vanilla zone, so a hit inside a flag circle came from the flag
        if z.flag and flat(at, z) <= (z.radius or 0) + pad then return false end
    end
    return true
end

function Building.RaidOpen()
    if not S.raidsEnabled then return false end
    if S.raidAlways then return true end
    local h = tonumber(os.date('%H'))
    local a, b = S.raidStartHour, S.raidEndHour
    if a == b then return false end
    if a < b then return h >= a and h < b end
    return h >= a or h < b
end

local function sizeOf(d) return math.max(d.size[1], d.size[2], d.size[3]) end

-- No stability: pieces stand anywhere. Only attachments (door, window, hatch) need their slot.
function Building.Supported(r, ignoreId)
    local d = P[r.piece]
    if not d then return false end
    if d.attach then
        for _, o in ipairs(Store.near(r.x, r.y, r.z, 1.2)) do
            if o.id ~= r.id and o.id ~= ignoreId and o.piece == d.attach then return true end
        end
        return false
    end
    return true
end

function Building.NewData(pieceId)
    local d = P[pieceId]
    if d and (d.lock or d.door) then return { lock = 'faction' } end
    return {}
end

local Pending = {}   -- [src] = { kind, id, readyAt }
AddEventHandler('playerDropped', function() Pending[source] = nil end)

local function startTimed(src, kind, id, ms)
    Pending[src] = { kind = kind, id = id, readyAt = GetGameTimer() + ms - 600 }
    return { ok = true, duration = ms }
end
local function finishTimed(src, kind, id)
    local p = Pending[src]; Pending[src] = nil
    return p and p.kind == kind and p.id == id and GetGameTimer() >= p.readyAt
end

local function near(src, r, max)
    local at = pedPos(src)
    return at and Store.dist(at, r) <= (max or 4.0)
end

-- Pieces belong to the player who placed them. Their faction (at placing time) shares them.
local function isOwner(src, r)
    local c = charOf(src)
    return c ~= nil and r.owner ~= nil and r.owner == c
end
local function member(src, r)
    if isOwner(src, r) then return true end
    return r.fac ~= nil and factionOf(src) == r.fac
end
-- Owner always; faction members need the rank permission.
local function crew(src, r, perm)
    if isOwner(src, r) then return true end
    return r.fac ~= nil and factionOf(src) == r.fac and can(src, perm)
end
local function manager(src, r)
    if r.owner ~= nil then return isOwner(src, r) end
    return crew(src, r, 'build')
end
Building.IsOwner, Building.Member, Building.Manager, Building.CharOf = isOwner, member, manager, charOf
Building.Near = function(src, r, max) return near(src, r, max) end

-- Raid alert to everyone online in the defending faction, at most once a minute per base.
local lastAlert = {}
local function raidAlert(r)
    if not r.fac then return end
    local now = os.time()
    if lastAlert[r.fac] and now - lastAlert[r.fac] < S.raidAlertCooldown then return end
    lastAlert[r.fac] = now
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if factionOf(pid) == r.fac then
            notify(pid, 'error', 'build.raid_alert')
            TriggerClientEvent('bs:building:raidPing', pid, r.x, r.y, r.z)
        end
    end
end

-- Storage spills into rubble anyone can search for 30 minutes.
local Rubble = {}
local function spill(r)
    local d = P[r.piece]
    if not d.storage then return end
    local items = exports.bs_inventory:ContainerTakeAll('build:' .. r.id)
    if #items == 0 then return end
    local cid = 'build:rubble:' .. r.id
    exports.bs_inventory:RegisterContainer(cid, { width = 10, height = 8, maxWeight = 500, label = L('label.rubble') })
    for _, it in ipairs(items) do exports.bs_inventory:ContainerGive(cid, it.item, it.amount) end
    Rubble[r.id] = { x = r.x, y = r.y, z = r.z, cid = cid, ends = os.time() + 1800 }
    TriggerClientEvent('bs:building:rubble', -1, r.id, Rubble[r.id])
end

function Building.Destroy(r, how)
    if not Store.pieces[r.id] then return end
    spill(r)
    Store.remove(r, how)
end

-- Damage from raids and decay. src nil for decay.
function Building.Damage(r, amount, how, src)
    if not Store.pieces[r.id] then return end
    r.health = r.health - amount
    if r.health <= 0 then
        Store.log(src, 'destroyed', ('%s #%d (%s) fac=%s by %s'):format(r.piece, r.id, how, tostring(r.fac), tostring(src and factionOf(src))), r)
        Building.Destroy(r, how)
        return
    end
    Store.save(r)
    Store.push(r)
end

-- Can src attack or loot piece r right now?. Safezone: never.
function Building.CanRaid(src, r)
    if not S.raidsEnabled then return false, 'build.err.no_raiding' end
    if isOwner(src, r) then return false, 'build.err.own_base' end
    local fac = factionOf(src)
    if fac and fac == r.fac then return false, 'build.err.own_base' end
    local claim = Building.ClaimAt(r)
    if claim and claim.kind == 'safezone' then return false, 'build.err.safezone_base' end
    if not Building.RaidOpen() then return false, 'build.err.raid_closed' end
    if claim and not Building.RaidDeclared(fac, claim.factionId) then return false, 'build.err.no_raid' end
    return true
end

local function raidHit(src, r, amount, how)
    local okRaid, why = Building.CanRaid(src, r)
    if not okRaid then return false, why end
    Store.log(src, 'raid', ('%s %s #%d -%d'):format(how, r.piece, r.id, amount), r)
    raidAlert(r)
    Building.Damage(r, amount, how, src)
    return true
end
Building.RaidHit = raidHit

-- Catalogue and placing

-- Real cost of a piece after the F1 cost scale. Always at least 1 of each.
local function costOf(d)
    local out, k = {}, tonumber(S.costScale) or 1.0
    for _, c in ipairs(d.cost or {}) do
        out[#out + 1] = { item = c.item, amount = math.max(1, math.ceil(c.amount * k)) }
    end
    return out
end
Building.CostOf = costOf

local function itemLabel(src, item)
    local ok, label = pcall(function() return exports.bs_inventory:ItemLabel(item, src) end)
    if ok and type(label) == 'string' and label ~= '' and label ~= item then return label end
    label = Lp(src, 'item.' .. item)
    if label == 'item.' .. item then label = item:gsub('_', ' ') end
    return label
end
Building.ItemLabel = itemLabel

-- Storage boxes and crafting stations of your faction within storageRadius
local function storages(src)
    if not S.pullFromStorage then return {} end
    local at = pedPos(src)
    if not at then return {} end
    local fac = factionOf(src)
    local me = charOf(src)
    local facOk = fac ~= nil and can(src, 'storage')
    local out = {}
    for _, r in ipairs(Store.near(at.x, at.y, at.z, tonumber(S.storageRadius) or 10.0)) do
        local d = P[r.piece]
        -- vending stock is for sale, never building material
        if r.built and d and not d.vending and ((me ~= nil and r.owner == me) or (facOk and r.fac == fac)) then
            if d.storage then
                local cid = 'build:' .. r.id
                exports.bs_inventory:RegisterContainer(cid, { width = d.storage.w, height = d.storage.h, maxWeight = d.storage.weight, label = Lp(src, 'piece.' .. r.piece) })
                out[#out + 1] = cid
            elseif d.station and GetResourceState('bs_crafting') == 'started' then
                out[#out + 1] = 'craftst:' .. r.id
            end
        end
    end
    return out
end

local function cCount(cid, item)
    local ok, n = pcall(function() return exports.bs_inventory:ContainerCount(cid, item) end)
    return ok and tonumber(n) or 0
end

-- Bag plus nearby storage.
local function haveTotal(src, item, srcs)
    local n = count(src, item)
    for _, cid in ipairs(srcs or {}) do n = n + cCount(cid, item) end
    return n
end

-- Takes from the bag first, then from storage. Returns how many were taken.
local function takeAny(src, item, n, srcs)
    local got = 0
    local inBag = math.min(n, count(src, item))
    if inBag > 0 and take(src, item, inBag) then got = inBag end
    for _, cid in ipairs(srcs or {}) do
        if got >= n then break end
        local want = math.min(n - got, cCount(cid, item))
        if want > 0 then
            local ok, r = pcall(function() return exports.bs_inventory:ContainerRemove(cid, item, want) end)
            if ok and r then got = got + want end
        end
    end
    return got
end

-- Admins with free build on (F10) or the F1 switch place finished pieces at no cost.
Building.FreeBuild = Building.FreeBuild or {}
local function freeBuild(src)
    if not isAdmin(src) then return false end
    return S.freeBuildAdmins == true or Building.FreeBuild[src] == true
end
AddEventHandler('playerDropped', function() Building.FreeBuild[source] = nil end)

local function costList(src, d, have, srcs)
    local out = {}
    for _, c in ipairs(costOf(d)) do
        out[#out + 1] = { item = c.item, need = c.amount, have = have and haveTotal(src, c.item, srcs) or nil, label = itemLabel(src, c.item) }
    end
    return out
end

-- "Missing: 4x Plank, 2x Nails". dep = what a frame already holds.
local function missingError(src, list, dep)
    local parts = {}
    for _, c in ipairs(list) do
        local short = c.need - (dep and (dep[c.item] or 0) or 0) - (c.have or 0)
        if short > 0 then parts[#parts + 1] = ('%dx %s'):format(short, c.label) end
    end
    if #parts == 0 then return err(src, 'build.err.materials') end
    return { ok = false, error = Lp(src, 'build.err.missing', { list = table.concat(parts, ', ') }) }
end

local function canPlaceHere(src, pieceId, at)
    local d = P[pieceId]
    if not d then return 'build.err.unknown' end
    local fac = factionOf(src)
    if d.flag then
        if not fac then return 'build.err.no_faction' end
        if not can(src, 'build') or sanctioned(src) then return 'build.err.no_perm' end
        if inSafeZone(at) then return 'build.err.safezone' end
        if d.flag == 'safezone' and isVanillaFac(fac) then return 'build.err.vanilla_safezone' end
        -- flag areas may not overlap: centres at least both radii apart
        for _, f in ipairs(flags(nil)) do
            if flat(at, f) < (tonumber(f.radius) or S.flagRadius) + S.flagRadius then return 'build.err.flag_overlap' end
        end
        return nil
    end
    if claimMode() then
        if not fac then return 'build.err.no_faction' end
        if not can(src, 'build') then return 'build.err.no_perm' end
    end
    if fac and sanctioned(src) then return 'build.err.no_perm' end
    if d.vending and not S.vendingEnabled then return 'build.err.vending_off' end
    local zoneErr = Building.ZoneError(at)
    if zoneErr then return zoneErr end
    local claim = Building.ClaimAt(at)
    if claimMode() then
        if not claim or claim.factionId ~= fac then return 'build.err.territory' end
        if Store.countFaction(fac) >= S.pieceCap then return 'build.err.cap' end
    elseif claim and claim.factionId ~= fac then
        return 'build.err.other_claim'
    end
    -- Safezone flags are a safe haven, not a stash: no storage boxes, no stations (they all hold output)
    if claim and claim.kind == 'safezone' and (d.storage or d.station) then return 'build.err.safezone_storage' end
    local me = charOf(src)
    if not me then return 'build.err.failed' end
    if not d.noCap and Store.countOwner(me) >= (tonumber(S.playerPieceCap) or 150) then return 'build.err.player_cap' end
    if d.limit then
        local n = 0
        for _, r in pairs(Store.pieces) do if r.owner == me and r.piece == pieceId then n = n + 1 end end
        if n >= d.limit then return 'build.err.limit' end
    end
    -- Same kind on the same spot, or anything stacked inside each other.
    for _, o in ipairs(Store.near(at.x, at.y, at.z, 0.45)) do
        local od = P[o.piece]
        if not (d.attach == o.piece or (od and od.attach == pieceId)) then return 'build.err.occupied' end
    end
    local probe = { id = -1, piece = pieceId, x = at.x, y = at.y, z = at.z }
    if not Building.Supported(probe) then return d.attach and 'build.err.attach' or 'build.err.support' end
    return nil
end
Building.InSafeZone = inSafeZone

BSB.RegisterCallback('build:catalogue', function(src)
    local fac = factionOf(src)
    local at = pedPos(src)
    local claim = at and Building.ClaimAt(at)
    local list = {}
    local srcs = storages(src)
    local free = freeBuild(src)
    local vanilla = isVanillaFac(fac)
    local inSafe = claim ~= nil and claim.kind == 'safezone' and claim.factionId == fac
    local me = charOf(src)
    for id, d in pairs(P) do
        local hide = (vanilla and d.flag == 'safezone') or (d.flag and not fac) or (d.vending and not S.vendingEnabled)
        if not d.hidden and not hide then
            local costs = costList(src, d, true, srcs)
            local afford = true
            for _, c in ipairs(costs) do if c.have < c.need and not free then afford = false end end
            local blocked = inSafe and (d.storage or d.station) and Lp(src, 'build.err.safezone_storage') or nil
            list[#list + 1] = { id = id, cat = d.cat, label = Lp(src, 'piece.' .. id), blurb = Lp(src, 'piece.' .. id .. '.d'),
                                costs = costs, canBuild = blocked == nil, blocked = blocked, afford = afford, size = d.size }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    local cm = claimMode()
    return {
        ok = true, pieces = list, faction = fac, charId = me, mode = cm and 'claim' or 'anywhere',
        canBuild = (cm and fac ~= nil and can(src, 'build')) or (not cm and me ~= nil),
        inClaim = claim ~= nil and claim.factionId == fac, hasFlag = fac ~= nil and #flags(fac) > 0,
        built = cm and (fac and Store.countFaction(fac) or 0) or Store.countOwner(me),
        max = cm and S.pieceCap or (tonumber(S.playerPieceCap) or 150),
        raids = S.raidsEnabled == true, raidOpen = Building.RaidOpen(),
        raidWindow = ('%02d:00-%02d:00'):format(S.raidStartHour, S.raidEndHour), freeBuild = free,
    }
end)

-- Cost list with have/need for the placement prompt. have counts the bag plus nearby storage.
BSB.RegisterCallback('build:costs', function(src, pieceId)
    local d = P[pieceId]
    if not d then return { ok = false } end
    return { ok = true, costs = costList(src, d, true, storages(src)), free = freeBuild(src) }
end)

BSB.RegisterCallback('build:check', function(src, pieceId, at)
    if type(at) ~= 'table' then return { ok = false } end
    local e = canPlaceHere(src, pieceId, { x = tonumber(at.x) or 0, y = tonumber(at.y) or 0, z = tonumber(at.z) or 0 })
    return { ok = e == nil, error = e and Lp(src, e) or nil }
end)

BSB.RegisterCallback('build:place', function(src, pieceId, at)
    if not S.enabled or not Store.ready then return err(src, 'build.err.disabled') end
    if dead(src) or type(at) ~= 'table' or type(pieceId) ~= 'string' then return { ok = false } end
    local pos = { x = tonumber(at.x), y = tonumber(at.y), z = tonumber(at.z) }
    if not pos.x or not pos.y or not pos.z then return { ok = false } end
    local h = (tonumber(at.h) or 0.0) % 360.0
    local me = pedPos(src)
    if not me or Store.dist(me, pos) > S.placeDistance + 3.0 then
        Store.flag(src, 'far', ('place %s %.1fm away'):format(pieceId, me and Store.dist(me, pos) or -1))
        return err(src, 'build.err.far')
    end
    local e = canPlaceHere(src, pieceId, pos)
    if e then return err(src, e) end
    local d = P[pieceId]
    local free = freeBuild(src)
    if count(src, S.hammerItem) < 1 and not d.flag and not free then return err(src, 'build.err.hammer') end

    if d.flag then
        local item = d.flag == 'safezone' and S.safezoneFlagItem or S.flagItem
        if count(src, item) < 1 and not free then
            return missingError(src, { { item = item, need = 1, have = 0, label = itemLabel(src, item) } })
        end
        local ok, res = pcall(function()
            return exports.bs_faction_bases:PlaceFlagAt(src, pos.x, pos.y, pos.z, h, S.flagRadius, d.flag,
                { maxOutposts = S.maxOutposts, free = free and count(src, item) < 1 })
        end)
        if not ok or type(res) ~= 'table' then return err(src, 'build.err.failed') end
        if res.ok then
            Store.log(src, 'flag', ('placed %s flag%s'):format(d.flag, free and ' (free build)' or ''), pos)
            -- picking the flag back up should start the decay clock fresh, not inherit an old one
            local fac = factionOf(src)
            if fac then Store.bases[fac] = os.time() end
        end
        return res
    end

    local p = player(src)
    local fac = factionOf(src)
    if free then
        local r = Building.PlaceFinished(src, pieceId, pos, h, fac, p and p.charId)
        if not r then return err(src, 'build.err.failed') end
        return { ok = true, id = r.id, built = true }
    end
    local data = Building.NewData(pieceId)
    local id = exports.oxmysql:insert_async(
        'INSERT INTO `bs_build_pieces` (`piece`,`faction_id`,`owner_char`,`x`,`y`,`z`,`h`,`health`,`built`,`deposited`,`data`) VALUES (?,?,?,?,?,?,?,?,0,?,?)',
        { pieceId, fac, p and p.charId, pos.x, pos.y, pos.z, h, math.floor(d.health * 0.1), '{}', json.encode(data) })
    if not id then return err(src, 'build.err.failed') end
    local r = { id = id, piece = pieceId, fac = fac, owner = p and p.charId, x = pos.x, y = pos.y, z = pos.z, h = h,
                health = math.floor(d.health * 0.1), built = false, dep = {}, data = data, placedAt = os.time() }
    Store.add(r)
    Store.push(r)
    Store.log(src, 'place', ('%s #%d'):format(pieceId, id), pos)
    return { ok = true, id = id }
end)

-- Put materials into a frame. Takes what you have, up to what is missing.
BSB.RegisterCallback('build:deposit', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r or r.built then return { ok = false } end
    if not crew(src, r, 'build') then return err(src, 'build.err.no_perm') end
    if not near(src, r, 5.0) then return err(src, 'build.err.far') end
    local d = P[r.piece]
    local srcs = storages(src)
    local moved = 0
    for _, c in ipairs(costOf(d)) do
        local missing = c.amount - (r.dep[c.item] or 0)
        if missing > 0 then
            local n = takeAny(src, c.item, missing, srcs)
            if n > 0 then
                r.dep[c.item] = (r.dep[c.item] or 0) + n
                moved = moved + n
            end
        end
    end
    -- What is still short after this deposit.
    local short = {}
    for _, c in ipairs(costOf(d)) do
        if (r.dep[c.item] or 0) < c.amount then short[#short + 1] = { item = c.item, need = c.amount, have = 0, label = itemLabel(src, c.item) } end
    end
    if moved == 0 then return missingError(src, short, r.dep) end
    Store.save(r, true)
    Store.push(r)
    local res = { ok = true, moved = moved }
    if #short > 0 then res.missing = missingError(src, short, r.dep).error end
    return res
end)

local function complete(r)
    for _, c in ipairs(costOf(P[r.piece])) do
        if (r.dep[c.item] or 0) < c.amount then return false end
    end
    return true
end

-- Hammer: finish a frame or repair a built piece.
BSB.RegisterCallback('build:hammerStart', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r then return { ok = false } end
    if not crew(src, r, 'build') then return err(src, 'build.err.no_perm') end
    if count(src, S.hammerItem) < 1 then return err(src, 'build.err.hammer') end
    if not near(src, r, 5.0) then return err(src, 'build.err.far') end
    if not r.built then
        if not complete(r) then return err(src, 'build.err.deposit_first') end
        return startTimed(src, 'finish', r.id, S.hammerMs)
    end
    if r.health >= Store.maxHp(r) then return err(src, 'build.err.full_hp') end
    if r.lastHit and os.time() - r.lastHit < 30 then return err(src, 'build.err.recent_damage') end
    return startTimed(src, 'repair', r.id, S.repairMs)
end)

BSB.RegisterCallback('build:hammerDone', function(src, id)
    id = tonumber(id)
    local r = Store.pieces[id]
    local p = Pending[src]
    if not r or not p or p.id ~= id then return { ok = false } end
    local kind = p.kind
    if not finishTimed(src, kind, id) then return err(src, 'build.err.too_quick') end
    if not near(src, r, 5.0) then return err(src, 'build.err.far') end
    if kind == 'finish' then
        if r.built or not complete(r) then return { ok = false } end
        r.built = true
        r.health = Store.maxHp(r)
        if GetResourceState('bs_skills') == 'started' then
            local ok, has = pcall(function() return exports.bs_skills:HasPerk(src, 'fortifier') end)
            if ok and has then r.data.fort = true; r.health = Store.maxHp(r) end
        end
        Store.save(r, true)
        Store.push(r)
        pcall(function() exports.bs_core:AwardAction(src, 'item_crafted') end)
        return { ok = true, built = true }
    elseif kind == 'repair' then
        -- Repair costs a share of the build price, scaled by missing HP.
        local missing = 1 - r.health / Store.maxHp(r)
        local srcs = storages(src)
        local need = {}
        for _, c in ipairs(costOf(P[r.piece])) do
            local n = math.ceil(c.amount * S.repairCostPct / 100 * missing)
            if n > 0 then need[#need + 1] = { item = c.item, need = n, have = haveTotal(src, c.item, srcs), label = itemLabel(src, c.item) } end
        end
        if not freeBuild(src) then
            for _, c in ipairs(need) do
                if c.have < c.need then return missingError(src, need) end
            end
            for _, c in ipairs(need) do takeAny(src, c.item, c.need, srcs) end
        end
        r.health = Store.maxHp(r)
        Store.save(r, true)
        Store.push(r)
        return { ok = true, repaired = true }
    end
    return { ok = false }
end)

-- Demolish: full refund for 10 minutes after placing, then half. Frames give back what went in.
BSB.RegisterCallback('build:demolish', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r then return { ok = false } end
    if not crew(src, r, 'demolish') then return err(src, 'build.err.no_perm') end
    local d = P[r.piece]
    -- a crate's takings go to whoever picks it up, so only its owner may
    if d and d.vending and r.owner ~= nil and not isOwner(src, r) then return err(src, 'build.err.no_perm') end
    if count(src, S.hammerItem) < 1 then return err(src, 'build.err.hammer') end
    if not near(src, r, 5.0) then return err(src, 'build.err.far') end
    if r.lastHit and os.time() - r.lastHit < 60 then return err(src, 'build.err.recent_damage') end
    local frac = (os.time() - (r.placedAt or 0) <= S.fullRefundMinutes * 60) and 1.0 or S.lateRefund
    local refund = {}
    if r.built then
        for _, c in ipairs(costOf(d)) do refund[c.item] = math.floor(c.amount * frac) end
    else
        for item, n in pairs(r.dep or {}) do refund[item] = n end
    end
    if d.storage and exports.bs_inventory:ContainerHasItems('build:' .. r.id) then return err(src, 'build.err.not_empty') end
    local takings = d.vending and math.floor(tonumber(r.data and r.data.bal) or 0) or 0
    Store.remove(r, 'demolish')
    for item, n in pairs(refund) do if n > 0 then give(src, item, n) end end
    if takings > 0 then pcall(function() exports.bs_core:AddMoney(src, 'cash', takings, 'build_vend_pickup') end) end
    Store.log(src, 'demolish', ('%s #%d refund %.0f%%%s'):format(r.piece, r.id, frac * 100, takings > 0 and (' takings ' .. takings) or ''), r)
    return { ok = true, refund = refund, takings = takings }
end)

-- Doors and code locks

local tries = {}   -- [src] = { n, since }
local function codeTry(src, r, code)
    local t = tries[src] or { n = 0, since = os.time() }
    if os.time() - t.since > 60 then t = { n = 0, since = os.time() } end
    if t.n >= 5 then return false, 'build.err.code_wait' end
    if tostring(code or '') == r.code then return true end
    t.n = t.n + 1
    tries[src] = t
    if t.n == 5 then Store.flag(src, 'code_guess', ('5 wrong codes on #%d'):format(r.id)) end
    return false, 'build.err.code_wrong'
end
AddEventHandler('playerDropped', function() tries[source] = nil end)

-- Pieces from before lock modes: faction members pass, others need the code
local function unlock(src, r, code)
    if isOwner(src, r) then return true end
    local mode = r.data and r.data.lock
    local sameFac = r.fac ~= nil and factionOf(src) == r.fac
    if mode == 'none' then return true end
    if mode == 'faction' then
        if sameFac then return true end
        return false, 'build.err.locked'
    end
    if mode ~= 'code' and sameFac then return true end
    if not r.code then return false, 'build.err.locked' end
    local me = charOf(src)
    if mode == 'code' and me and r.data.auth and r.data.auth[tostring(me)] then return true end
    if code == nil then return false, nil, true end
    local ok, e = codeTry(src, r, code)
    if ok and mode == 'code' and me then
        r.data.auth = r.data.auth or {}
        r.data.auth[tostring(me)] = true
        Store.save(r)
    end
    return ok, e
end
Building.Unlock = unlock

BSB.RegisterCallback('build:door', function(src, id, code)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].door then return { ok = false } end
    if not near(src, r, 4.0) then return err(src, 'build.err.far') end
    local ok, e, need = unlock(src, r, code)
    if not ok then
        -- raids on: an unlocked-looking door of a raidable base still opens
        if not (r.code == nil and Building.CanRaid(src, r)) then
            if need then return { ok = false, needCode = true } end
            return err(src, e or 'build.err.locked')
        end
    end
    r.data.open = not r.data.open
    Store.save(r)
    Store.push(r)
    return { ok = true, open = r.data.open }
end)

-- mode = 'code' | 'faction' | 'none'. Changing the code forgets everyone who knew the old one.
local function setLock(src, id, mode, code)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].lock then return { ok = false } end
    if not manager(src, r) then return err(src, 'build.err.no_perm') end
    if not near(src, r, 4.0) then return err(src, 'build.err.far') end
    if mode == 'code' then
        code = tostring(code or '')
        if not code:match('^%d%d%d%d$') then return err(src, 'build.err.code_format') end
        r.code, r.data.lock, r.data.auth = code, 'code', {}
    elseif mode == 'faction' then
        r.code, r.data.lock, r.data.auth = nil, 'faction', nil
    elseif mode == 'none' then
        r.code, r.data.lock, r.data.auth = nil, 'none', nil
    else
        return { ok = false }
    end
    Store.save(r, true)
    Store.push(r)
    Store.log(src, 'code', ('%s #%d lock %s'):format(r.piece, r.id, mode), r)
    return { ok = true, mode = mode }
end

BSB.RegisterCallback('build:setLock', function(src, id, mode, code) return setLock(src, id, mode, code) end)
-- Old keypad call: empty code removes the lock.
BSB.RegisterCallback('build:setCode', function(src, id, code)
    code = tostring(code or '')
    return setLock(src, id, code == '' and 'none' or 'code', code)
end)

-- Utilities

BSB.RegisterCallback('build:storage', function(src, id, code)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built then return { ok = false } end
    local d = P[r.piece]
    if not d.storage then return { ok = false } end
    if not near(src, r, 3.0) then return err(src, 'build.err.far') end
    if d.vending and not manager(src, r) then return err(src, 'build.err.no_perm') end
    local ok, e, need = unlock(src, r, code)
    if ok then
        if not isOwner(src, r) and r.fac ~= nil and factionOf(src) == r.fac and not can(src, 'storage') then
            return err(src, 'build.err.no_perm')
        end
    else
        local okRaid = Building.CanRaid(src, r)
        if not okRaid then
            if need then return { ok = false, needCode = true } end
            return err(src, e or 'build.err.locked')
        end
        Store.log(src, 'loot', ('opened %s #%d of %s'):format(r.piece, r.id, tostring(r.fac)), r)
    end
    local cid = 'build:' .. r.id
    exports.bs_inventory:RegisterContainer(cid, { width = d.storage.w, height = d.storage.h, maxWeight = d.storage.weight, label = Lp(src, 'piece.' .. r.piece) })
    exports.bs_inventory:OpenContainerFor(src, cid)
    return { ok = true }
end)

BSB.RegisterCallback('build:rubble', function(src, id)
    local rb = Rubble[tonumber(id)]
    if not rb then return { ok = false } end
    local at = pedPos(src)
    if not at or Store.dist(at, rb) > 3.5 then return err(src, 'build.err.far') end
    exports.bs_inventory:OpenContainerFor(src, rb.cid)
    return { ok = true }
end)

BSB.RegisterCallback('build:fuel', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].generator then return { ok = false } end
    if not member(src, r) then return err(src, 'build.err.no_perm') end
    if not near(src, r, 3.0) then return err(src, 'build.err.far') end
    local room = 100 - (r.data.fuel or 0)
    if room <= 0 then return err(src, 'build.err.full') end
    local got = exports.bs_inventory:PourOut(src, { 'fuel_can', 'empty_bottle' }, room)
    if (got or 0) <= 0 then return err(src, 'build.err.no_fuel') end
    r.data.fuel = (r.data.fuel or 0) + got
    Store.save(r, true)
    Store.push(r)
    return { ok = true, fuel = r.data.fuel }
end)

BSB.RegisterCallback('build:power', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].generator then return { ok = false } end
    if not member(src, r) then return err(src, 'build.err.no_perm') end
    if not near(src, r, 3.0) then return err(src, 'build.err.far') end
    if not r.data.on and (r.data.fuel or 0) <= 0 then return err(src, 'build.err.no_fuel') end
    r.data.on = not r.data.on
    Store.save(r)
    Store.push(r)
    return { ok = true, on = r.data.on }
end)

BSB.RegisterCallback('build:water', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].rain then return { ok = false } end
    if not near(src, r, 3.0) then return err(src, 'build.err.far') end
    local n = math.floor((r.data.water or 0) / S.waterPerBottle)
    if n <= 0 then return err(src, 'build.err.no_water', { amount = math.floor(r.data.water or 0) }) end
    r.data.water = (r.data.water or 0) - n * S.waterPerBottle
    give(src, 'water_bottle', n)
    Store.save(r)
    return { ok = true, bottles = n }
end)

BSB.RegisterCallback('build:info', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r then return { ok = false } end
    return { ok = true, piece = Store.view(r), member = member(src, r), owner = isOwner(src, r), water = r.data.water or 0 }
end)

-- Beds and respawn

local lastRespawn = {}   -- [charId] = os.time()

BSB.RegisterCallback('build:claimBed', function(src, id)
    local r = Store.pieces[tonumber(id)]
    local p = player(src)
    if not r or not p or not r.built or not P[r.piece].respawn then return { ok = false } end
    if not member(src, r) then return err(src, 'build.err.no_perm') end
    if not near(src, r, 3.0) then return err(src, 'build.err.far') end
    for _, o in pairs(Store.pieces) do
        if o.data and o.data.sleeper == p.charId then o.data.sleeper = nil; Store.save(o) end
    end
    r.data.sleeper = p.charId
    Store.save(r, true)
    return { ok = true }
end)

-- bs_medical asks this when a player respawns. Nil = no bed or on cooldown.
exports('GetRespawnPoint', function(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    local last = lastRespawn[charId]
    if last and os.time() - last < S.respawnCooldownMin * 60 then return nil end
    for _, r in pairs(Store.pieces) do
        if r.built and r.data and r.data.sleeper == charId and P[r.piece] and P[r.piece].respawn then
            lastRespawn[charId] = os.time()
            return { x = r.x, y = r.y, z = r.z + 0.5, h = r.h or 0.0, label = 'Base' }
        end
    end
    return nil
end)

-- Raid tools

BSB.RegisterCallback('build:raidStart', function(src, id, tool)
    local r = Store.pieces[tonumber(id)]
    if not r then return { ok = false } end
    local okRaid, why = Building.CanRaid(src, r)
    if not okRaid then return err(src, why) end
    if not near(src, r, 4.0) then return err(src, 'build.err.far') end
    if tool == 'sledge' then
        if count(src, S.sledgeItem) < 1 then return err(src, 'build.err.tool') end
        return startTimed(src, 'sledge', r.id, S.sledgeMs)
    elseif tool == 'grinder' then
        if not r.code then return err(src, 'build.err.no_lock') end
        if count(src, S.grinderItem) < 1 then return err(src, 'build.err.tool') end
        raidAlert(r)
        return startTimed(src, 'grinder', r.id, S.grinderMs)
    end
    return { ok = false }
end)

BSB.RegisterCallback('build:raidDone', function(src, id)
    id = tonumber(id)
    local r = Store.pieces[id]
    local p = Pending[src]
    if not r or not p or p.id ~= id then return { ok = false } end
    local kind = p.kind
    if not finishTimed(src, kind, id) then return err(src, 'build.err.too_quick') end
    if not near(src, r, 4.0) then return err(src, 'build.err.far') end
    if kind == 'sledge' then
        r.lastHit = os.time()
        local ok, e = raidHit(src, r, S.sledgeDamage, 'sledge')
        if not ok then return err(src, e) end
        return { ok = true }
    elseif kind == 'grinder' then
        local okRaid, why = Building.CanRaid(src, r)
        if not okRaid then return err(src, why) end
        r.code = nil
        Store.save(r, true)
        Store.push(r)
        Store.log(src, 'grind', ('lock cut on %s #%d'):format(r.piece, r.id), r)
        return { ok = true }
    end
    return { ok = false }
end)

-- Vehicle ramming
local lastRam = {}
RegisterNetEvent('bs:building:ram', function(id)
    local src = source
    local r = Store.pieces[tonumber(id)]
    if not r or not P[r.piece].ram then return end
    local now = GetGameTimer()
    if lastRam[src] and now - lastRam[src] < 1500 then return end
    lastRam[src] = now
    local ped = GetPlayerPed(src)
    local veh = ped and GetVehiclePedIsIn(ped, false) or 0
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local c = GetEntityCoords(veh)
    if Store.dist({ x = c.x, y = c.y, z = c.z }, r) > 8.0 then return end
    r.lastHit = os.time()
    raidHit(src, r, S.ramDamage, 'ram')
end)

-- Explosives (c4, pipe bombs, grenades). The game reports these server side.
AddEventHandler('explosionEvent', function(sender, ev)
    local dmg = Building.Explosions[tonumber(ev.explosionType) or -1]
    if not dmg or not Building.RaidOpen() then return end -- raidHit checks safezone and declaration per piece
    local at = { x = ev.posX, y = ev.posY, z = ev.posZ }
    if not at.x then return end
    local hits = Store.near(at.x, at.y, at.z, Building.ExplosionRadius)
    for _, r in ipairs(hits) do
        local fall = 1 - math.min(1, Store.dist(at, r) / Building.ExplosionRadius) * 0.6
        r.lastHit = os.time()
        raidHit(tonumber(sender), r, math.floor(dmg * fall), 'explosive')
    end
end)

-- Spikes: a stranger standing on them gets hurt. Client asks, server agrees.
local lastSpike = {}
RegisterNetEvent('bs:building:spike', function(id)
    local src = source
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].spikes or member(src, r) then return end
    if not near(src, r, 2.5) then return end
    local now = GetGameTimer()
    if lastSpike[src] and now - lastSpike[src] < 1000 then return end
    lastSpike[src] = now
    TriggerClientEvent('bs:building:hurt', src, S.spikeDamage)
end)

-- Zombies leave bases alone. Old clients may still send this.
RegisterNetEvent('bs:building:hit', function() end)

-- Loops: visits, decay, generators, rain

local visitSaved = {}
CreateThread(function()
    local tick = 0
    while true do
        Wait(60000)
        if Store.ready then
            tick = tick + 1
            local now = os.time()
            -- A member near their flag or any of their pieces counts as a visit.
            for _, pid in ipairs(GetPlayers()) do
                pid = tonumber(pid)
                local fac = factionOf(pid)
                local at = fac and pedPos(pid)
                if at then
                    local here = false
                    for _, f in ipairs(flags(fac)) do if flat(at, f) <= S.flagRadius + 20 then here = true break end end
                    if not here then
                        for _, r in ipairs(Store.near(at.x, at.y, at.z, 30.0)) do if r.fac == fac then here = true break end end
                    end
                    if here then
                        Store.bases[fac] = now
                        if not visitSaved[fac] or now - visitSaved[fac] > 300 then
                            visitSaved[fac] = now
                            Store.x('INSERT INTO `bs_build_bases` (`faction_id`,`last_visit`) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE `last_visit` = NOW()', { fac })
                        end
                    end
                end
            end

            local decayTick = tick % math.max(1, S.decayTickMinutes) == 0
            local raining = false
            if GetResourceState('bs_world') == 'started' then
                local ok, w = pcall(function() return exports.bs_world:WorldState() end)
                local wt = ok and w and tostring(w.weather or ''):upper() or ''
                raining = wt == 'RAIN' or wt == 'THUNDER' or wt == 'CLEARING' or wt == 'RAINING'
            end
            local list = {}
            for _, r in pairs(Store.pieces) do list[#list + 1] = r end
            local allFlags = flags(nil)
            for _, r in ipairs(list) do
                if Store.pieces[r.id] then
                    local d = P[r.piece]
                    -- Decay: no visit for decayDays. Unknown bases start their clock now.
                    if r.fac and not S.decayEnabled then
                        if r.decaying then r.decaying = false; Store.push(r) end
                    elseif r.fac then
                        Store.bases[r.fac] = Store.bases[r.fac] or now
                        -- No flag of its own faction over it (picked up or lost) = decays now, slowly.
                        local claim = Building.ClaimAt(r, allFlags)
                        local unclaimed = claimMode() and (not claim or claim.factionId ~= r.fac)
                        local idle = unclaimed or now - Store.bases[r.fac] > S.decayDays * 86400
                        if r.decaying ~= idle then r.decaying = idle; Store.push(r) end
                        if idle and decayTick then
                            Building.Damage(r, Store.maxHp(r) * S.decayDamagePct / 100, 'decay')
                        end
                    end
                    if Store.pieces[r.id] and d.generator and r.data.on then
                        r.data.fuel = math.max(0, (r.data.fuel or 0) - S.generatorFuelHour / 60)
                        if r.data.fuel <= 0 then r.data.on = false; Store.push(r) end
                        Store.save(r)
                    end
                    if raining and d.rain and r.built then
                        r.data.water = math.min(200, (r.data.water or 0) + S.rainPerMinute)
                        Store.save(r)
                    end
                end
            end
            for id, rb in pairs(Rubble) do
                if rb.ends <= now then Rubble[id] = nil; TriggerClientEvent('bs:building:rubble', -1, id, nil) end
            end
        end
    end
end)

-- Streaming and exports

BSB.RegisterCallback('build:cell', function(src, cx, cy)
    cx, cy = tonumber(cx), tonumber(cy)
    if not cx or not cy or not Store.ready then return { ok = false } end
    local at = pedPos(src)
    if at then
        local mx, my = Store.cellOf(at.x, at.y)
        if math.abs(mx - cx) > 2 or math.abs(my - cy) > 2 then return { ok = false } end
    end
    return { ok = true, list = Store.cellList(cx, cy) }
end)

BSB.RegisterCallback('build:defs', function()
    return { ok = true, pieces = P, rubble = Rubble }
end)

-- Other resources register their own placeables (stations etc). def = { id
local function register(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' then return false end
    local id = def.id
    def.cat = def.cat or 'utility'
    def.size = def.size or { 1, 1, 1 }
    def.health = def.health or 400
    def.support = def.support or 'any'
    def.models = def.models or (def.model and { def.model }) or {}
    def.cost = def.cost or {}
    def.owner = GetInvokingResource()
    P[id] = def
    for _, r in ipairs(Store.waiting[id] or {}) do Store.add(r) end
    Store.waiting[id] = nil
    TriggerClientEvent('bs:building:def', -1, id, def)
    return true
end
exports('RegisterPlaceable', register)

CreateThread(function()
    Wait(4000)
    if GetResourceState('bs_crafting') == 'started' then
        local ok, defs = pcall(function() return exports.bs_crafting:StationDefs() end)
        if ok and type(defs) == 'table' then
            for k, d in pairs(defs) do if type(d) == 'table' then d.id = d.id or k; register(d) end end
        end
    end
end)

exports('Count', function(charId)
    local n = 0
    for _, r in pairs(Store.pieces) do if r.owner == tonumber(charId) then n = n + 1 end end
    return n
end)

-- Is this player standing at a built station of that kind?
exports('NearStation', function(src, station, radius)
    local at = pedPos(tonumber(src))
    if not at then return false end
    for _, r in ipairs(Store.near(at.x, at.y, at.z, tonumber(radius) or 4.0)) do
        local d = P[r.piece]
        if r.built and d and (d.station == station or r.piece == station) then return true end
    end
    return false
end)

exports('Materials', function()
    local out = {}
    for _, d in pairs(P) do
        for _, c in ipairs(costOf(d)) do out[c.item] = math.max(out[c.item] or 0, c.amount) end
    end
    out[S.hammerItem] = 1
    return out
end)

exports('PiecesInRadius', function(x, y, z, radius)
    local out = {}
    for _, r in ipairs(Store.near(x, y, z, radius)) do out[#out + 1] = Store.view(r) end
    return out
end)
exports('RaidOpen', function() return Building.RaidOpen() end)
-- bs_faction_bases asks this before an outpost reclaim.
exports('RaidAllowed', function(attacker, target) return Building.RaidOpen() and Building.RaidDeclared(attacker, target) end)

exports('PieceCosts', function()
    local out = {}
    for id, d in pairs(P) do
        if not d.hidden then out[#out + 1] = { id = id, cat = d.cat, label = L('piece.' .. id), cost = costOf(d) } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)
exports('CostOf', function(pieceId) local d = P[pieceId]; return d and costOf(d) or nil end)

exports.bs_core:RegisterModule('building', { side = 'server', version = '2.0.0', ready = true })
if BS and BS.Provide then BS.Provide('building', { 'Materials', 'NearStation', 'Count' }) end

-- Battery charging (bs_vehicles): a running, fuelled generator near the player
exports('RunningGeneratorNear', function(src, radius)
    local at = pedPos(tonumber(src))
    if not at then return nil end
    for _, r in ipairs(Store.near(at.x, at.y, at.z, tonumber(radius) or 4.0)) do
        local d = P[r.piece]
        if r.built and d and d.generator and r.data.on and (r.data.fuel or 0) > 0 then return r.id end
    end
end)

-- Burns generator fuel for a charge. Switches it off when it runs dry, like the hourly burn.
exports('UseGeneratorFuel', function(id, amount)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.data then return false end
    r.data.fuel = math.max(0, (r.data.fuel or 0) - (tonumber(amount) or 0))
    if r.data.fuel <= 0 then r.data.on = false end
    Store.save(r)
    Store.push(r)
    return true
end)
