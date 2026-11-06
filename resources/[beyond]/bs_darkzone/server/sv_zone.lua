-- Dark Zone: candidate list, rotation, who is inside, extraction/crate points, zombies.

Zone = {
    list = {},        -- [id] = zone (config merged with F1 edits)
    edits = {},       -- [id] = data from bs_dz_zones
    active = nil,     -- the zone in play, a copy
    gen = 0,          -- bumps on every activation, old reports are ignored
    startedAt = 0, nextAt = 0, warned = false, paused = false,
    anchors = {},     -- [id] = { id, kind, sx, sy, x, y, z }
    crates = {},      -- [anchorId] = { cid, emptySince }
    inside = {},      -- [src] = zone id
    lastPos = {},     -- [src] = vector3, kept for disconnects
}

local S = function() return DZ.Settings end
local ready = false

local function radiusOf(z)
    local o = tonumber(S().radiusOverride) or 0
    return o > 0 and o or (tonumber(z.radius) or 300.0)
end
Zone.Radius = radiusOf

local function clean(id, d)
    if type(d) ~= 'table' then return nil end
    local z = {
        id = id, label = tostring(d.label or id):sub(1, 48),
        x = tonumber(d.x) or 0.0, y = tonumber(d.y) or 0.0, z = tonumber(d.z) or 0.0,
        radius = math.max(60.0, math.min(1500.0, tonumber(d.radius) or 300.0)),
        enabled = d.enabled ~= false, builtin = d.builtin == true,
    }
    if type(d.heli) == 'table' and tonumber(d.heli.x) then z.heli = { x = d.heli.x + 0.0, y = d.heli.y + 0.0, z = (tonumber(d.heli.z) or z.z) + 0.0 } end
    if type(d.walks) == 'table' and #d.walks > 0 then
        z.walks = {}
        for i = 1, math.min(6, #d.walks) do
            local w = d.walks[i]
            if type(w) == 'table' and tonumber(w.x) then z.walks[#z.walks + 1] = { x = w.x + 0.0, y = w.y + 0.0, z = (tonumber(w.z) or z.z) + 0.0 } end
        end
        if #z.walks == 0 then z.walks = nil end
    end
    return z
end
Zone.Clean = clean

function Zone.Rebuild()
    local list = {}
    for _, d in ipairs(DZ.Zones or {}) do
        local c = {}
        for k, v in pairs(d) do c[k] = v end
        c.builtin = true
        list[d.id] = clean(d.id, c)
    end
    for id, e in pairs(Zone.edits) do
        if e.deleted then
            list[id] = nil
        else
            local base = list[id]
            local merged = {}
            if base then for k, v in pairs(base) do merged[k] = v end end
            for k, v in pairs(e) do merged[k] = v end
            merged.builtin = base ~= nil
            local z = clean(id, merged)
            if z then z.edited = true; list[id] = z end
        end
    end
    Zone.list = list
end

-- Safezones, outposts and faction flags too close to a zone. Returns the label of the first one or nil.
function Zone.Conflict(z)
    local r = radiusOf(z)
    local pad = tonumber(S().safePad) or 150.0
    if DZU.started('bs_zombies') then
        local ok, list = pcall(function() return exports.bs_zombies:SafeZones() end)
        for _, s in ipairs(ok and list or {}) do
            if DZU.d2(z.x, z.y, s.x, s.y) < r + (tonumber(s.radius) or 0) + pad then return s.label or s.id end
        end
    end
    for _, s in ipairs((Zones and Zones.FactionSafe) or {}) do
        if s.coords and DZU.d2(z.x, z.y, s.coords.x, s.coords.y) < r + (tonumber(s.radius) or 75.0) + pad then return s.label end
    end
    if DZU.started('bs_faction_bases') then
        local ok, flags = pcall(function() return exports.bs_faction_bases:ListFlags() end)
        for _, f in ipairs(ok and flags or {}) do
            if f.status ~= 'removed' and tonumber(f.x) and DZU.d2(z.x, z.y, f.x, f.y) < r + (tonumber(f.radius) or 100.0) + pad then
                return ('%s %s'):format(tostring(f.factionId or 'faction'), tostring(f.kind or 'base'))
            end
        end
    end
    return nil
end

local function pick(exclude)
    local ids = {}
    for id, z in pairs(Zone.list) do
        if z.enabled and id ~= exclude and not Zone.Conflict(z) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    if #ids == 0 then
        local z = exclude and Zone.list[exclude]
        if z and z.enabled and not Zone.Conflict(z) then return exclude end
        return nil
    end
    return ids[math.random(1, #ids)]
end

--------------------------------------------------------------------------------
-- Points: heli, walk-out, crates. Seeds are put on a road by the first client near them.
--------------------------------------------------------------------------------

local function buildAnchors(z)
    local a = {}
    local r = radiusOf(z)
    if z.heli then
        a.h1 = { id = 'h1', kind = 'heli', sx = z.heli.x, sy = z.heli.y, x = z.heli.x, y = z.heli.y, z = z.heli.z }
    else
        a.h1 = { id = 'h1', kind = 'heli', sx = z.x, sy = z.y, sz = z.z }
    end
    if z.walks then
        for i, w in ipairs(z.walks) do a['w' .. i] = { id = 'w' .. i, kind = 'walk', sx = w.x, sy = w.y, x = w.x, y = w.y, z = w.z } end
    else
        local base = math.random() * math.pi * 2
        for i = 1, 3 do
            local ang = base + (i - 1) * (math.pi * 2 / 3)
            a['w' .. i] = { id = 'w' .. i, kind = 'walk', sx = z.x + math.cos(ang) * r * 0.88, sy = z.y + math.sin(ang) * r * 0.88, sz = z.z }
        end
    end
    for i = 1, math.max(0, math.min(30, math.floor(tonumber(S().crateCount) or 8))) do
        local ang = math.random() * math.pi * 2
        local d = r * (0.15 + math.random() * 0.6)
        a['c' .. i] = { id = 'c' .. i, kind = 'crate', sx = z.x + math.cos(ang) * d, sy = z.y + math.sin(ang) * d, sz = z.z }
    end
    return a
end

function Zone.AnchorView()
    local out = {}
    for _, a in pairs(Zone.anchors) do
        out[#out + 1] = { id = a.id, kind = a.kind, sx = a.sx, sy = a.sy, sz = a.sz or (Zone.active and Zone.active.z) or 0.0, x = a.x, y = a.y, z = a.z }
    end
    table.sort(out, function(p, q) return p.id < q.id end)
    return out
end

local function crateFill(a)
    local c = Zone.crates[a.id]
    if not c then return end
    local tier = math.max(1, math.min(3, math.floor(tonumber(S().lootTier) or 3)))
    pcall(function() exports.bs_inventory:ContainerTakeAll(c.cid) end)
    for _, it in ipairs(DZU.roll(DZ.Loot[tier])) do
        if DZU.itemExists(it.item) then
            pcall(function() exports.bs_inventory:ContainerGiveAll(c.cid, it.item, it.amount) end)
        end
    end
    c.emptySince = nil
end

local function crateMake(a)
    if Zone.crates[a.id] then return end
    local cid = ('dzcrate:%d:%s'):format(Zone.gen, a.id)
    exports.bs_inventory:RegisterContainer(cid, { width = 5, height = 4, maxWeight = 80.0, label = L('dz.crate_label') })
    Zone.crates[a.id] = { cid = cid }
    crateFill(a)
end

-- A client put a seed on the ground. First plausible answer wins.
RegisterNetEvent('bs:dz:anchor', function(gen, id, x, y, z)
    local src = source
    if not DZU.on() or not Zone.active or tonumber(gen) ~= Zone.gen then return end
    local a = Zone.anchors[tostring(id or '')]
    if not a or a.x then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return end
    if DZU.d2(x, y, a.sx, a.sy) > 200.0 then return end
    if a.kind == 'crate' and not Zone.Contains(x, y) then return end
    local p = DZU.pos(src)
    if not p or DZU.d2(p.x, p.y, x, y) > 500.0 then return end
    a.x, a.y, a.z = x, y, z
    if a.kind == 'crate' then crateMake(a) end
    TriggerClientEvent('bs:dz:anchorSet', -1, Zone.gen, a.id, x, y, z)
end)

--------------------------------------------------------------------------------
-- Activation and rotation
--------------------------------------------------------------------------------

local function zombieRegion()
    if not DZU.started('bs_zombies') then return end
    local z = Zone.active
    pcall(function()
        if not z then return exports.bs_zombies:SetRegion('darkzone', nil) end
        exports.bs_zombies:SetRegion('darkzone', { x = z.x, y = z.y, radius = radiusOf(z),
            health = S().zHealth, damage = S().zDamage, speed = S().zSpeed, horde = S().zHorde })
    end)
end

function Zone.View()
    local z = Zone.active
    return {
        on = DZU.on() and z ~= nil, gen = Zone.gen,
        zone = z and { id = z.id, label = z.label, x = z.x, y = z.y, z = z.z, r = radiusOf(z) } or nil,
        left = z and math.max(0, Zone.nextAt - os.time()) or 0,
        anchors = z and Zone.AnchorView() or {},
        boundary = S().showBoundary == true, boundaryDistance = tonumber(S().boundaryDistance) or 120.0,
        heliVisual = S().heliVisual == true,
        walkRadius = tonumber(S().walkRadius) or 6.0, heliRadius = tonumber(S().heliRadius) or 15.0,
    }
end

function Zone.Push(target)
    TriggerClientEvent('bs:dz:state', target or -1, Zone.View())
end

local function save()
    DZU.stateSave('rot', { zone = Zone.active and Zone.active.id or nil, startedAt = Zone.startedAt, nextAt = Zone.nextAt, paused = Zone.paused })
end

function Zone.Deactivate(why)
    if Extract and Extract.AbortAll then Extract.AbortAll(why) end
    for _, c in pairs(Zone.crates) do pcall(function() exports.bs_inventory:ContainerTakeAll(c.cid) end) end
    Zone.crates, Zone.anchors = {}, {}
    DZU.untag('dz'); DZU.untag('dz_elite'); DZU.untag('dz_heli')
    Zone.active = nil
    for src in pairs(Zone.inside) do
        Zone.inside[src] = nil
        Player(src).state:set('bsDarkZone', false, true)
    end
    zombieRegion()
    Zone.Push()
end

-- keepTimer: resume after a restart without resetting the clock
function Zone.Activate(id, keepTimer)
    local z = id and Zone.list[id]
    if not z then return false end
    Zone.Deactivate('move')
    Zone.gen = Zone.gen + 1
    Zone.active = {}
    for k, v in pairs(z) do Zone.active[k] = v end
    Zone.anchors = buildAnchors(Zone.active)
    for _, a in pairs(Zone.anchors) do if a.kind == 'crate' and a.x then crateMake(a) end end
    local now = os.time()
    if not keepTimer then
        Zone.startedAt = now
        Zone.nextAt = now + math.floor((tonumber(S().rotationHours) or 4.0) * 3600)
    end
    Zone.warned = (Zone.nextAt - now) <= (tonumber(S().warningMinutes) or 10) * 60
    zombieRegion()
    save()
    Zone.Push()
    if not keepTimer then DZU.broadcast('dz.moved', { zone = z.label }, 'warn') end
    print(('^3[bs_darkzone]^7 active zone: %s'):format(z.id))
    return true
end

function Zone.Next()
    local id = pick(Zone.active and Zone.active.id)
    if not id then print('^1[bs_darkzone]^7 no valid zone to activate (all disabled or too close to a safezone)'); return false end
    return Zone.Activate(id)
end

function Zone.SetPaused(p)
    Zone.paused = p == true
    if Zone.paused then Zone.Deactivate('stop') end
    save()
end

--------------------------------------------------------------------------------
-- Ticks
--------------------------------------------------------------------------------

local function inZone(x, y)
    local z = Zone.active
    return z and DZU.d2(x, y, z.x, z.y) <= radiusOf(z)
end
Zone.Contains = inZone

-- Membership, server side only. Clients are told, never asked.
CreateThread(function()
    while true do
        Wait(1000)
        if ready then
            for _, src in ipairs(DZU.players()) do
                local p = DZU.pos(src)
                if p then
                    Zone.lastPos[src] = p
                    local now = (DZU.on() and Zone.active and inZone(p.x, p.y)) and Zone.active.id or nil
                    if Zone.inside[src] ~= now then
                        Zone.inside[src] = now
                        Player(src).state:set('bsDarkZone', now or false, true)
                        TriggerClientEvent('bs:dz:inside', src, now ~= nil, Zone.active and Zone.active.label or '')
                        if Bag and Bag.Push then Bag.Push(src) end
                    end
                end
            end
        end
    end
end)

-- Rotation, warnings, crate refills, zombie region refresh.
CreateThread(function()
    while not ready do Wait(500) end
    local lastRegion, lastCrates = 0, 0
    while true do
        Wait(5000)
        local now = os.time()
        if not DZU.on() then
            if Zone.active then Zone.Deactivate('off') end
        elseif not Zone.paused then
            if not Zone.active then
                Zone.Next()
            else
                local warnAt = Zone.nextAt - (tonumber(S().warningMinutes) or 10) * 60
                if not Zone.warned and now >= warnAt then
                    Zone.warned = true
                    DZU.broadcast('dz.warn', { zone = Zone.active.label, min = math.max(1, math.ceil((Zone.nextAt - now) / 60)) }, 'warn')
                end
                if now >= Zone.nextAt then
                    if Extract and Extract.Busy and Extract.Busy() then
                        Zone.nextAt = now + 30
                    else
                        Zone.Next()
                    end
                end
            end
        end
        if Zone.active and now - lastRegion >= 30 then lastRegion = now; zombieRegion() end
        if Zone.active and now - lastCrates >= 30 then
            lastCrates = now
            local wait = (tonumber(S().crateMinutes) or 20) * 60
            for aid, c in pairs(Zone.crates) do
                local ok, has = pcall(function() return exports.bs_inventory:ContainerHasItems(c.cid) end)
                if ok and not has then
                    c.emptySince = c.emptySince or now
                    if now - c.emptySince >= wait then crateFill(Zone.anchors[aid]) end
                else
                    c.emptySince = nil
                end
            end
        end
    end
end)

-- Extra infected around players inside. Elites are brutes with a lot more health.
CreateThread(function()
    while true do
        Wait(math.max(10, tonumber(S().spawnSeconds) or 40) * 1000)
        if ready and DZU.on() and Zone.active then
            local cap = tonumber(S().spawnMaxAlive) or 40
            for src in pairs(Zone.inside) do
                local alive = DZU.count('dz') + DZU.count('dz_elite')
                if alive >= cap then break end
                local p = DZU.pos(src)
                if p and DZU.alive(src) then
                    for _ = 1, math.min(cap - alive, math.max(0, math.floor(tonumber(S().spawnGroup) or 5))) do
                        local x, y = DZU.ring(p.x, p.y, 80.0, 125.0)
                        if inZone(x, y) then
                            if math.random() < (tonumber(S().eliteChance) or 0.08) then
                                DZU.spawn(x, y, 'brute', 'dz_elite', tonumber(S().eliteHp) or 4.0)
                            else
                                DZU.spawn(x, y, math.random() < (tonumber(S().bruteChance) or 0.15) and 'brute' or 'walker', 'dz')
                            end
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    -- lastPos is read by the death path first (bs_medical runs on the same event)
    SetTimeout(5000, function() Zone.lastPos[src] = nil end)
    Zone.inside[src] = nil
end)

BSB.RegisterCallback('dz:view', function(src)
    return Zone.View()
end)

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

function Zone.LoadEdits()
    local rows = exports.oxmysql:query_async('SELECT `id`, `data` FROM `bs_dz_zones`') or {}
    Zone.edits = {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data)
        if ok and type(d) == 'table' then Zone.edits[r.id] = d end
    end
    Zone.Rebuild()
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    -- the migration may still be running on a fresh database
    local tries = 0
    while tries < 40 do
        local ok = pcall(function() exports.oxmysql:query_async('SELECT 1 FROM `bs_dz_state` LIMIT 1') end)
        if ok then break end
        tries = tries + 1
        Wait(1500)
    end
    Zone.LoadEdits()
    local st = DZU.stateLoad('rot') or {}
    Zone.paused = st.paused == true
    ready = true
    if DZU.on() and not Zone.paused and st.zone and Zone.list[st.zone] and tonumber(st.nextAt) and st.nextAt > os.time() then
        Zone.startedAt, Zone.nextAt = tonumber(st.startedAt) or os.time(), st.nextAt
        Zone.Activate(st.zone, true)
    end
end)

function Zone.Ready() return ready end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if DZU.started('bs_zombies') then pcall(function() exports.bs_zombies:SetRegion('darkzone', nil) end) end
end)
