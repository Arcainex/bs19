-- Dark Zone: the contaminated bag, dropped bags, crates, death and extraction.

Bag = {}
Extract = { heli = nil, heliCd = {}, walk = {} }

local S = function() return DZ.Settings end
local drops = {}        -- [id] = { id, cid, x, y, z, at }
local lastNote = {}     -- [src] = os.time of the last "contaminated" note
local pairKill = {}     -- ['a>b'] = os.time, kill XP anti-farm

function Bag.Id(cid) return 'dzbag:' .. tostring(cid) end

local function spec(label, sealed)
    return { width = math.max(2, math.min(12, math.floor(tonumber(S().bagWidth) or 6))),
             height = math.max(2, math.min(20, math.floor(tonumber(S().bagHeight) or 4))),
             maxWeight = math.max(5.0, math.min(500.0, tonumber(S().bagMaxWeight) or 40.0)),
             label = label, sealed = sealed }
end

-- Registered on every use so F1 size changes and the player's language apply.
function Bag.Ensure(src)
    local cid = DZU.charId(src)
    if not cid then return nil end
    local id = Bag.Id(cid)
    exports.bs_inventory:RegisterContainer(id, spec(Lp(src, 'dz.bag_label'), true))
    return id
end

-- stacks, weight
function Bag.Stats(id)
    local ok, list = pcall(function() return exports.bs_inventory:ContainerContents(id) end)
    local n, w = 0, 0.0
    for _, e in ipairs(ok and list or {}) do
        n = n + 1
        local okd, def = pcall(function() return exports.bs_inventory:GetItem(e.item) end)
        w = w + ((okd and def and tonumber(def.weight)) or 0.5) * (tonumber(e.amount) or 1)
    end
    return n, math.floor(w * 10 + 0.5) / 10
end

function Bag.Push(src)
    if not DZU.on() then TriggerClientEvent('bs:dz:bag', src, nil); return end
    local id = Bag.Ensure(src)
    if not id then return end
    local n, w = Bag.Stats(id)
    TriggerClientEvent('bs:dz:bag', src, { stacks = n, weight = w, max = spec('', true).maxWeight,
        walkOk = n <= (tonumber(S().walkMaxStacks) or 4) and w <= (tonumber(S().walkMaxWeight) or 8.0) })
end

-- bs_inventory asks this on every take from a container (and world pickup, fromId nil).
-- Returns the bag container id when the item must go into the contaminated bag.
exports('BagFor', function(src, fromId)
    src = tonumber(src)
    if not src or not DZU.on() then return nil end
    if type(fromId) == 'string' then
        if fromId:sub(1, 6) == 'dzbag:' then return nil end
        if fromId:sub(1, 7) == 'dzdrop:' then return Bag.Ensure(src) end
    end
    if Zone.inside[src] then return Bag.Ensure(src) end
    return nil
end)

AddEventHandler('bs:darkzone:contaminated', function(src)
    src = tonumber(src)
    if not src then return end
    local now = os.time()
    if not lastNote[src] or now - lastNote[src] > 45 then
        lastNote[src] = now
        DZU.notify(src, 'warn', 'dz.contaminated')
    end
    Bag.Push(src)
end)

BSB.RegisterCallback('dz:openBag', function(src)
    if not DZU.on() then return { ok = false, msg = Lp(src, 'dz.off') } end
    local id = Bag.Ensure(src)
    if not id then return { ok = false } end
    exports.bs_inventory:OpenContainerFor(src, id)
    return { ok = true }
end)

--------------------------------------------------------------------------------
-- Crates
--------------------------------------------------------------------------------

BSB.RegisterCallback('dz:crateOpen', function(src, aid)
    if not DZU.on() or not Zone.active then return { ok = false, msg = Lp(src, 'dz.off') } end
    if not Zone.inside[src] then return { ok = false, msg = Lp(src, 'dz.not_inside') } end
    local a = Zone.anchors[tostring(aid or '')]
    local c = a and Zone.crates[a.id]
    if not a or a.kind ~= 'crate' or not a.x or not c then return { ok = false, msg = Lp(src, 'dz.gone') } end
    local p = DZU.pos(src)
    if not p or DZU.d2(p.x, p.y, a.x, a.y) > 3.5 or math.abs(p.z - a.z) > 4.0 then return { ok = false, msg = Lp(src, 'dz.far') } end
    exports.bs_inventory:RegisterContainer(c.cid, { width = 5, height = 4, maxWeight = 80.0, label = Lp(src, 'dz.crate_label') })
    exports.bs_inventory:OpenContainerFor(src, c.cid)
    return { ok = true }
end)

--------------------------------------------------------------------------------
-- Dropped bags
--------------------------------------------------------------------------------

local function dropView()
    local out = {}
    for _, d in pairs(drops) do out[#out + 1] = { id = d.id, x = d.x, y = d.y, z = d.z } end
    return out
end
function Bag.Drops() return dropView() end

local function pushDrops() TriggerClientEvent('bs:dz:drops', -1, dropView()) end

local function removeDrop(id)
    local d = drops[id]
    if not d then return end
    drops[id] = nil
    pcall(function() exports.bs_inventory:ContainerTakeAll(d.cid) end)
    pushDrops()
end

BSB.RegisterCallback('dz:dropOpen', function(src, id)
    if not DZU.on() then return { ok = false, msg = Lp(src, 'dz.off') } end
    local d = drops[tostring(id or '')]
    if not d then return { ok = false, msg = Lp(src, 'dz.gone') } end
    local p = DZU.pos(src)
    if not p or DZU.d2(p.x, p.y, d.x, d.y) > 3.0 or math.abs(p.z - d.z) > 4.0 then return { ok = false, msg = Lp(src, 'dz.far') } end
    if not DZU.alive(src) then return { ok = false } end
    exports.bs_inventory:RegisterContainer(d.cid, spec(Lp(src, 'dz.drop_label'), false))
    exports.bs_inventory:OpenContainerFor(src, d.cid)
    return { ok = true }
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        local life = (tonumber(S().dropMinutes) or 30) * 60
        local ids = {}
        for id in pairs(drops) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            local d = drops[id]
            if d then
                local ok, has = pcall(function() return exports.bs_inventory:ContainerHasItems(d.cid) end)
                if now - d.at >= life or (ok and not has and now - d.at > 10) then removeDrop(id) end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Death inside: only the contaminated bag drops, the rest is kept.
--------------------------------------------------------------------------------

local function killerOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local ok, ent = pcall(GetPedSourceOfDeath, ped)
    if not ok or not ent or ent == 0 then return nil end
    for _, p in ipairs(DZU.players()) do
        if p ~= src then
            local pp = GetPlayerPed(p)
            if pp == ent then return p end
            local okv, veh = pcall(GetVehiclePedIsIn, pp, false)
            if okv and veh ~= 0 and veh == ent then return p end
        end
    end
    return nil
end

-- Called by bs_medical before its corpse and wipe. true = handled here, keep the inventory.
exports('OnDeath', function(src)
    src = tonumber(src)
    if not src or not DZU.on() or not Zone.active then return false end
    local p = DZU.pos(src) or Zone.lastPos[src]
    if not p then return false end
    if not Zone.inside[src] and not Zone.Contains(p.x, p.y) then return false end

    Extract.Cancel(src)
    local bag = Bag.Ensure(src)
    local moved = 0
    if bag then
        local n = Bag.Stats(bag)
        if n > 0 then
            local id = ('%x%04x'):format(os.time(), math.random(0, 0xFFFF))
            local cid = 'dzdrop:' .. id
            exports.bs_inventory:RegisterContainer(cid, spec(L('dz.drop_label'), false))
            local ok, res = pcall(function() return exports.bs_inventory:ContainerTransfer(bag, cid) end)
            moved = ok and type(res) == 'table' and (res.moved or 0) or 0
            if moved > 0 then
                drops[id] = { id = id, cid = cid, x = p.x, y = p.y, z = p.z - 0.95, at = os.time() }
                pushDrops()
            end
        end
    end
    DZU.notify(src, 'error', moved > 0 and 'dz.died_bag' or 'dz.died_clean', nil, 7000)
    Bag.Push(src)

    Prog.Count(src, 'deaths')
    local killer = killerOf(src)
    if killer and Zone.inside[killer] then
        local key = ('%d>%d'):format(killer, src)
        local now = os.time()
        if not pairKill[key] or now - pairKill[key] > 600 then
            pairKill[key] = now
            Prog.Count(killer, 'kills')
            Prog.Add(killer, tonumber(S().xpPlayerKill) or 0, 'pvp')
        end
    end
    print(('^3[bs_darkzone]^7 %s died inside, bag stacks dropped: %d'):format(GetPlayerName(src) or src, moved))
    return true
end)

--------------------------------------------------------------------------------
-- Extraction
--------------------------------------------------------------------------------

local function extract(src, kind)
    local bag = Bag.Ensure(src)
    if not bag then return end
    local ok, res = pcall(function() return exports.bs_inventory:ContainerToPlayer(bag, src) end)
    local moved = ok and type(res) == 'table' and (res.moved or 0) or 0
    local left = ok and type(res) == 'table' and (res.left or 0) or 0
    if moved > 0 then
        local xp = (tonumber(S().xpExtract) or 0) + (tonumber(S().xpPerStack) or 0) * moved
        if kind == 'heli' then xp = xp + (tonumber(S().xpHeliBonus) or 0) end
        local got = Prog.Add(src, xp, 'extract_' .. kind)
        Prog.Count(src, 'extracts')
        local cx = math.floor(tonumber(S().charXpExtract) or 0)
        if cx > 0 then pcall(function() exports.bs_core:AddXP(src, cx, 'darkzone_extract') end) end
        DZU.notify(src, 'success', 'dz.extracted', { n = moved, xp = got }, 7000)
        local cid = DZU.charId(src)
        if cid then
            exports.oxmysql:insert('INSERT INTO `bs_dz_log` (`character_id`,`kind`,`zone`,`stacks`,`xp`) VALUES (?,?,?,?,?)',
                { cid, kind, Zone.active and Zone.active.id or '', moved, got })
        end
        TriggerEvent('bs:darkzone:extracted', src, kind, moved)
        Prog.Deliver(src)
    elseif left == 0 then
        DZU.notify(src, 'info', 'dz.bag_empty')
    end
    if left > 0 then DZU.notify(src, 'warn', 'dz.extract_left', { n = left }, 7000) end
    Bag.Push(src)
end

local function anchorAt(src, aid, kind, reach)
    local a = Zone.anchors[tostring(aid or '')]
    if not a or a.kind ~= kind or not a.x then return nil, 'dz.gone' end
    local p = DZU.pos(src)
    if not p or DZU.d2(p.x, p.y, a.x, a.y) > reach or math.abs(p.z - a.z) > 6.0 then return nil, 'dz.far' end
    return a
end

function Extract.Busy() return Extract.heli ~= nil end

function Extract.Cancel(src)
    if Extract.walk[src] then
        Extract.walk[src] = nil
        TriggerClientEvent('bs:dz:walk', src, nil)
    end
end

function Extract.AbortAll(why)
    for src in pairs(Extract.walk) do Extract.Cancel(src) end
    if Extract.heli then
        Extract.heli = nil
        DZU.untag('dz_heli')
        TriggerClientEvent('bs:dz:heli', -1, { phase = 'abort' })
    end
end

BSB.RegisterCallback('dz:heliCall', function(src, aid)
    if not DZU.on() or not Zone.active then return { ok = false, msg = Lp(src, 'dz.off') } end
    if not DZU.alive(src) then return { ok = false } end
    local a, err = anchorAt(src, aid, 'heli', 8.0)
    if not a then return { ok = false, msg = Lp(src, err) } end
    if Extract.heli then return { ok = false, msg = Lp(src, 'dz.heli_busy') } end
    local now = os.time()
    local cd = Extract.heliCd[Zone.gen]
    if cd and now < cd then return { ok = false, msg = Lp(src, 'dz.heli_cd', { s = cd - now }) } end
    if S().requireFlare == true then
        local okc, n = pcall(function() return exports.bs_inventory:CountItem(src, 'dz_flare') end)
        if not okc or (tonumber(n) or 0) < 1 then return { ok = false, msg = Lp(src, 'dz.need_flare') } end
        exports.bs_inventory:RemoveItem(src, 'dz_flare', 1)
    end
    local secs = math.max(20, math.floor(tonumber(S().heliSeconds) or 90))
    Extract.heli = { aid = a.id, x = a.x, y = a.y, z = a.z, endsAt = now + secs, caller = src,
                     nextWave = now + 5, gen = Zone.gen }
    DZU.noise(a.x, a.y, a.z, 320.0)
    TriggerClientEvent('bs:dz:heli', -1, { phase = 'called', x = a.x, y = a.y, z = a.z, left = secs, caller = src })
    for _, p in ipairs(DZU.players()) do
        local pp = DZU.pos(p)
        if Zone.inside[p] or (pp and DZU.d2(pp.x, pp.y, a.x, a.y) < 600.0) then
            DZU.notify(p, 'warn', 'dz.heli_called', { s = secs }, 8000)
        end
    end
    print(('^3[bs_darkzone]^7 heli called by %s'):format(GetPlayerName(src) or src))
    return { ok = true }
end)

BSB.RegisterCallback('dz:walkStart', function(src, aid)
    if not DZU.on() or not Zone.active then return { ok = false, msg = Lp(src, 'dz.off') } end
    if not DZU.alive(src) then return { ok = false } end
    if Extract.walk[src] then return { ok = false, msg = Lp(src, 'dz.walk_busy') } end
    local a, err = anchorAt(src, aid, 'walk', (tonumber(S().walkRadius) or 6.0) + 1.0)
    if not a then return { ok = false, msg = Lp(src, err) } end
    local bag = Bag.Ensure(src)
    local n, w = Bag.Stats(bag)
    if n == 0 then return { ok = false, msg = Lp(src, 'dz.bag_empty') } end
    local maxN, maxW = tonumber(S().walkMaxStacks) or 4, tonumber(S().walkMaxWeight) or 8.0
    if n > maxN or w > maxW then return { ok = false, msg = Lp(src, 'dz.walk_big', { n = maxN, kg = maxW }) } end
    local secs = math.max(10, math.floor(tonumber(S().walkSeconds) or 120))
    Extract.walk[src] = { aid = a.id, x = a.x, y = a.y, z = a.z, endsAt = os.time() + secs }
    TriggerClientEvent('bs:dz:walk', src, { left = secs, x = a.x, y = a.y, z = a.z })
    return { ok = true, seconds = secs }
end)

BSB.RegisterCallback('dz:walkCancel', function(src)
    Extract.Cancel(src)
    return { ok = true }
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        local h = Extract.heli
        if h then
            if not Zone.active or h.gen ~= Zone.gen then
                Extract.AbortAll('gone')
            elseif now >= h.endsAt then
                Extract.heli = nil
                Extract.heliCd[h.gen] = now + math.floor(tonumber(S().heliCooldown) or 300)
                local r = tonumber(S().heliRadius) or 15.0
                local done = {}
                for _, p in ipairs(DZU.players()) do
                    local pos = DZU.pos(p)
                    local ped = GetPlayerPed(p)
                    if pos and DZU.alive(p) and DZU.d2(pos.x, pos.y, h.x, h.y) <= r and math.abs(pos.z - h.z) < 12.0
                        and GetVehiclePedIsIn(ped, false) == 0 then
                        done[#done + 1] = p
                    end
                end
                for _, p in ipairs(done) do extract(p, 'heli') end
                for p in pairs(Zone.inside) do DZU.notify(p, 'info', 'dz.heli_left', { n = #done }) end
                TriggerClientEvent('bs:dz:heli', -1, { phase = 'done', x = h.x, y = h.y, z = h.z })
                DZU.untag('dz_heli')
            elseif now >= h.nextWave then
                h.nextWave = now + math.max(5, math.floor(tonumber(S().heliWaveSeconds) or 20))
                local size = math.max(0, math.floor(tonumber(S().heliWaveSize) or 6))
                if DZU.count('dz_heli') < size * 3 then
                    for _ = 1, size do
                        local x, y = DZU.ring(h.x, h.y, 70.0, 100.0)
                        DZU.spawn(x, y, math.random() < (tonumber(S().bruteChance) or 0.15) and 'brute' or 'walker', 'dz_heli')
                    end
                end
                DZU.drive('dz_heli', h.x, h.y, h.z)
            end
        end
        for src, w in pairs(Extract.walk) do
            local pos = DZU.pos(src)
            if not GetPlayerName(src) then
                Extract.walk[src] = nil
            elseif not pos or not DZU.alive(src) or DZU.d2(pos.x, pos.y, w.x, w.y) > (tonumber(S().walkRadius) or 6.0) + 2.0 then
                Extract.Cancel(src)
                DZU.notify(src, 'warn', 'dz.walk_cancel')
            elseif now >= w.endsAt then
                Extract.walk[src] = nil
                TriggerClientEvent('bs:dz:walk', src, nil)
                extract(src, 'walk')
            end
        end
    end
end)

function Extract.View()
    local h = Extract.heli
    return h and { x = h.x, y = h.y, z = h.z, left = math.max(0, h.endsAt - os.time()) } or nil
end

AddEventHandler('bs:hook:player:loaded', function(player)
    local src = player and tonumber(player.source)
    if not src then return end
    SetTimeout(3000, function()
        if GetPlayerName(src) then Bag.Push(src); TriggerClientEvent('bs:dz:drops', src, dropView()) end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    Extract.walk[src] = nil
    lastNote[src] = nil
end)

-- /dzbag: look into your contaminated bag (nothing can be taken out until extraction)
RegisterCommand('dzbag', function(src)
    if src <= 0 or not DZU.on() then return end
    local id = Bag.Ensure(src)
    if id then exports.bs_inventory:OpenContainerFor(src, id) end
end, false)
