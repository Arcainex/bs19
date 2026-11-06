-- bs_building store: pieces and wires in memory, grid lookups, DB writes, pushes to nearby players.

local S = Building.Settings
Building.PowerDirty = Building.PowerDirty or function() end
Store = { pieces = {}, grid = {}, ready = false, bases = {}, waiting = {}, wires = {}, wiresReady = false }

local CELL = 128.0
Store.CELL = CELL

local function q(sql, p) return exports.oxmysql:query_async(sql, p or {}) or {} end
local function x(sql, p) return exports.oxmysql:execute_async(sql, p or {}) end
Store.q, Store.x = q, x

function Store.cellOf(px, py) return math.floor(px / CELL), math.floor(py / CELL) end
local function key(cx, cy) return cx .. '|' .. cy end

local function gridAdd(r)
    local cx, cy = Store.cellOf(r.x, r.y)
    r.cell = key(cx, cy)
    Store.grid[r.cell] = Store.grid[r.cell] or {}
    Store.grid[r.cell][r.id] = true
end
local function gridDel(r)
    local b = r.cell and Store.grid[r.cell]
    if b then b[r.id] = nil; if next(b) == nil then Store.grid[r.cell] = nil end end
end

function Store.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Pieces within radius of a point (exact distance).
function Store.near(px, py, pz, radius)
    local out, span = {}, math.ceil(radius / CELL)
    local cx, cy = Store.cellOf(px, py)
    local at = { x = px, y = py, z = pz }
    for dx = -span, span do
        for dy = -span, span do
            local b = Store.grid[key(cx + dx, cy + dy)]
            if b then
                for id in pairs(b) do
                    local r = Store.pieces[id]
                    if r and Store.dist(at, r) <= radius then out[#out + 1] = r end
                end
            end
        end
    end
    return out
end

function Store.def(r) return Building.Pieces[r.piece] end

-- Tier the piece is at (nil for pieces without tiers)
function Store.tier(r)
    return Building.TierOfData(Store.def(r), r.data and r.data.tier)
end

function Store.spec(r) return Building.Spec(Store.def(r), r.data and r.data.tier) end

function Store.maxHp(r)
    local sp = Store.spec(r)
    return (sp and sp.health or 500) * ((r.data and r.data.fort) and 1.25 or 1)
end

-- What a client is allowed to see. The code never leaves the server.
function Store.view(r)
    local d = r.data or {}
    local def = Store.def(r)
    local v = {
        id = r.id, p = r.piece, f = r.fac, ow = r.owner, x = r.x, y = r.y, z = r.z, h = r.h,
        hp = math.floor(r.health), mhp = math.floor(Store.maxHp(r)), b = r.built,
        dep = (not r.built) and r.dep or nil, o = d.open or false, lk = r.code ~= nil,
        on = d.on or false, fuel = d.fuel, w = d.water, decay = r.decaying or false,
        lm = d.lock, t = Store.tier(r),
        ab = d.ab and d.ab.ends or nil,
    }
    if def and (def.power or def.light) then v.lit = d.lit ~= false; v.pw = r.pw == true end
    if def and def.node then v.pw = r.pw == true end
    if def and def.generator then
        v.res = d.res or 0
        v.pw = r.pw == true
        local n, charge = 0, 0
        for _, b in ipairs(d.bats or {}) do n = n + 1; charge = charge + (tonumber(b.charge) or 0) end
        v.bat = n > 0 and math.floor(charge / n) or nil
    end
    return v
end

function Store.wireView(w) return { id = w.id, a = w.a, b = w.b } end

-- Wires whose first end sits in this cell
function Store.cellWires(cx, cy)
    local out = {}
    for _, w in pairs(Store.wires) do
        local a = Store.pieces[w.a]
        if a then
            local ax, ay = Store.cellOf(a.x, a.y)
            if ax == cx and ay == cy then out[#out + 1] = Store.wireView(w) end
        end
    end
    return out
end

function Store.cellList(cx, cy)
    local out, b = {}, Store.grid[key(cx, cy)]
    if b then for id in pairs(b) do local r = Store.pieces[id]; if r then out[#out + 1] = Store.view(r) end end end
    return out
end

-- Send to players close enough to have this cell streamed.
local PUSH = 460.0
local function nearbyPlayers(r)
    local out = {}
    for _, pid in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pid)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            local dx, dy = c.x - r.x, c.y - r.y
            if dx * dx + dy * dy <= PUSH * PUSH then out[#out + 1] = tonumber(pid) end
        end
    end
    return out
end
Store.nearbyPlayers = nearbyPlayers
function Store.push(r)
    local v = Store.view(r)
    for _, pid in ipairs(nearbyPlayers(r)) do TriggerClientEvent('bs:building:upsert', pid, v) end
end
function Store.pushRemove(r, how)
    for _, pid in ipairs(nearbyPlayers(r)) do TriggerClientEvent('bs:building:remove', pid, r.id, how) end
end

local function decode(s)
    if type(s) ~= 'string' or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return (ok and type(v) == 'table') and v or {}
end

function Store.fromRow(row)
    return {
        id = tonumber(row.id), piece = row.piece, fac = row.faction_id, owner = tonumber(row.owner_char),
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) or 0.0,
        health = tonumber(row.health) or 100, built = row.built == true or tonumber(row.built) == 1,
        dep = decode(row.deposited), code = row.code, data = decode(row.data),
        -- oxmysql hands DATETIME back as ms
        placedAt = math.floor((tonumber(row.placed_at) or (os.time() * 1000)) / 1000),
    }
end

function Store.add(r)
    Store.pieces[r.id] = r
    gridAdd(r)
end

-- Wires

function Store.wiresOf(id)
    local out = {}
    for _, w in pairs(Store.wires) do if w.a == id or w.b == id then out[#out + 1] = w end end
    return out
end

function Store.addWire(w)
    Store.wires[w.id] = w
    local a = Store.pieces[w.a]
    if a then
        local v = Store.wireView(w)
        for _, pid in ipairs(nearbyPlayers(a)) do TriggerClientEvent('bs:building:wire', pid, v) end
    end
    Building.PowerDirty()
end

function Store.removeWire(w)
    if not Store.wires[w.id] then return end
    Store.wires[w.id] = nil
    x('DELETE FROM `bs_build_wires` WHERE `id` = ?', { w.id })
    local a = Store.pieces[w.a] or Store.pieces[w.b]
    if a then for _, pid in ipairs(nearbyPlayers(a)) do TriggerClientEvent('bs:building:unwire', pid, w.id) end end
    Building.PowerDirty()
end

function Store.remove(r, how)
    for _, w in ipairs(Store.wiresOf(r.id)) do Store.removeWire(w) end
    gridDel(r)
    Store.pieces[r.id] = nil
    x('DELETE FROM `bs_build_pieces` WHERE `id` = ?', { r.id })
    Store.pushRemove(r, how)
    TriggerEvent('bs:building:pieceRemoved', r.id, r.piece)
    Building.PowerDirty()
end

-- Debounced writes: health and data change often during raids.
local dirty = {}
function Store.save(r, now)
    if now then
        dirty[r.id] = nil
        x('UPDATE `bs_build_pieces` SET `health`=?,`built`=?,`deposited`=?,`code`=?,`data`=?,`faction_id`=? WHERE `id`=?',
            { r.health, r.built and 1 or 0, json.encode(r.dep or {}), r.code, json.encode(r.data or {}), r.fac, r.id })
    else
        dirty[r.id] = true
    end
end
CreateThread(function()
    while true do
        Wait(15000)
        for id in pairs(dirty) do
            local r = Store.pieces[id]
            if r then Store.save(r, true) else dirty[id] = nil end
        end
    end
end)

function Store.countFaction(fac)
    local n = 0
    for _, r in pairs(Store.pieces) do local d = Building.Pieces[r.piece]
        if r.fac == fac and d and not d.noCap then n = n + 1 end end
    return n
end

function Store.countOwner(charId)
    local n = 0
    if not charId then return 0 end
    for _, r in pairs(Store.pieces) do local d = Building.Pieces[r.piece]
        if r.owner == charId and d and not d.noCap then n = n + 1 end end
    return n
end

-- Guard log row for building events. Not a cheat flag, so nobody gets toasted.
function Store.log(src, kind, details, at)
    src = tonumber(src) or 0
    local charId, name, lic = nil, src > 0 and GetPlayerName(src) or 'server', nil
    if src > 0 then
        local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
        if ok and p then charId = p.charId end
        lic = GetPlayerIdentifierByType and GetPlayerIdentifierByType(tostring(src), 'license') or nil
    end
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, lic, charId, (name or '?'):sub(1, 64), ('build_' .. kind):sub(1, 32), 0, tostring(details or ''):sub(1, 512),
          at and at.x or nil, at and at.y or nil, at and at.z or nil })
end

-- Cheating-looking requests go through bs_guard so staff hear about them.
function Store.flag(src, kind, details)
    if GetResourceState('bs_guard') == 'started' then
        pcall(function() exports.bs_guard:Flag(src, 'build_' .. kind, details, 70) end)
    end
end

-- v1 ids that were replaced (migration 046 renames the rows, this covers a server that skipped it)
local Renamed = { wall_window = 'wall', floor_frame = 'floor', window = 'mesh_panel', hatch = 'ladder' }

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    -- migration 031 makes these; wait for bs_core to have run it
    for _ = 1, 60 do
        local ok = pcall(function() return exports.oxmysql:query_async('SELECT 1 FROM `bs_build_pieces` LIMIT 1') end)
        if ok then break end
        Wait(1000)
    end
    Wait(1500)
    local n = 0
    for _, row in ipairs(q('SELECT * FROM `bs_build_pieces`')) do
        local r = Store.fromRow(row)
        if Renamed[r.piece] then
            r.piece = Renamed[r.piece]
            x('UPDATE `bs_build_pieces` SET `piece` = ? WHERE `id` = ?', { r.piece, r.id })
        end
        if Building.Pieces[r.piece] then Store.add(r); n = n + 1
        else
            -- piece from another resource that has not registered yet
            Store.waiting[r.piece] = Store.waiting[r.piece] or {}
            table.insert(Store.waiting[r.piece], r)
        end
    end
    for _, row in ipairs(q('SELECT `faction_id`, `last_visit` FROM `bs_build_bases`')) do
        Store.bases[row.faction_id] = math.floor((tonumber(row.last_visit) or os.time() * 1000) / 1000)
    end
    -- wires come with migration 046; without the table there are simply no wires
    local okW, rows = pcall(function() return exports.oxmysql:query_async('SELECT * FROM `bs_build_wires`') end)
    if okW and type(rows) == 'table' then
        for _, row in ipairs(rows) do
            local w = { id = tonumber(row.id), a = tonumber(row.a_id), b = tonumber(row.b_id), owner = tonumber(row.owner_char), fac = row.faction_id }
            if Store.pieces[w.a] and Store.pieces[w.b] then Store.wires[w.id] = w
            else x('DELETE FROM `bs_build_wires` WHERE `id` = ?', { w.id }) end
        end
        Store.wiresReady = true
    end
    Store.ready = true
    print(('^2[BeyondSurvival]^7 (building) %d pieces loaded'):format(n))
    TriggerClientEvent('bs:building:reset', -1)
    Building.PowerDirty()
end)
