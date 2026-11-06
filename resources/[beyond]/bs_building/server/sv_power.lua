-- bs_building power: generators, batteries, lights, poles and wires. The server decides what has power.
-- A running generator powers small devices within powerRadius. Poles and junction boxes wired to it
-- carry that power further and feed devices within poleRadius. Output is shared out by piece id.

local S = Building.Settings
local P = Building.Pieces

local function err(src, key, vars) return { ok = false, error = Lp(src, key, vars) } end

local dirty = true
function Building.PowerDirty() dirty = true end

local function genOf(r) local d = P[r.piece]; return d and d.generator or nil end

-- Pieces share power when they have the same owner or the same faction
local function sameCrew(a, b)
    if a.owner ~= nil and b.owner ~= nil and a.owner == b.owner then return true end
    return a.fac ~= nil and a.fac == b.fac
end

local function running(r)
    return r.built and r.data.on == true and (tonumber(r.data.fuel) or 0) > 0
end

-- What a generator gives right now: its engine, or its charged batteries while the engine is not running
local function sourceOutput(r)
    local g = genOf(r)
    if not g or not r.built or (r.data and r.data.ab) then return 0, nil end
    if running(r) then return g.output, 'fuel' end
    local n = 0
    for _, b in ipairs(r.data.bats or {}) do if (tonumber(b.charge) or 0) > 0 then n = n + 1 end end
    if n > 0 then return n * (tonumber(S.batteryOutput) or 2), 'battery' end
    return 0, nil
end

local function compute()
    dirty = false
    local nodes, parent = {}, {}
    for _, r in pairs(Store.pieces) do
        local d = P[r.piece]
        if d and r.built and (d.generator or d.node) then nodes[#nodes + 1] = r; parent[r.id] = r.id end
    end
    local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    if S.wiresEnabled then
        for _, w in pairs(Store.wires) do
            if parent[w.a] and parent[w.b] then
                local ra, rb = find(w.a), find(w.b)
                if ra ~= rb then parent[ra] = rb end
            end
        end
    end
    local nets = {}
    for _, n in ipairs(nodes) do
        local root = find(n.id)
        local net = nets[root]
        if not net then net = { out = 0, used = 0, nodes = {}, root = root }; nets[root] = net end
        net.nodes[#net.nodes + 1] = n
        local o = sourceOutput(n)
        net.out = net.out + o
    end
    local order = {}
    for _, net in pairs(nets) do order[#order + 1] = net end
    table.sort(order, function(a, b) return a.root < b.root end)

    local consumers = {}
    for _, r in pairs(Store.pieces) do
        local d = P[r.piece]
        if d and d.power and r.built then consumers[#consumers + 1] = r end
    end
    table.sort(consumers, function(a, b) return a.id < b.id end)

    local changed = {}
    for _, r in ipairs(consumers) do
        local pw = false
        if r.data.lit ~= false and not r.data.ab then
            local need = P[r.piece].power
            for _, net in ipairs(order) do
                if net.out - net.used >= need then
                    for _, n in ipairs(net.nodes) do
                        local reach = genOf(n) and S.powerRadius or S.poleRadius
                        -- a node only feeds others when it has power itself
                        if sameCrew(n, r) and Store.dist(n, r) <= reach then pw = true break end
                    end
                    if pw then net.used = net.used + need break end
                end
            end
        end
        if (r.pw == true) ~= pw then r.pw = pw; changed[#changed + 1] = r end
    end
    for _, net in ipairs(order) do
        local live = net.out > 0
        for _, n in ipairs(net.nodes) do
            n.net = { out = net.out, used = net.used }
            if (n.pw == true) ~= live then n.pw = live; changed[#changed + 1] = n end
        end
    end
    for _, r in ipairs(changed) do Store.push(r) end
end

-- What the inspect card shows
function Building.PowerInfo(r)
    local d = P[r.piece]
    if not d then return nil end
    if d.generator then
        local net = r.net or {}
        return { gen = true, out = net.out or 0, used = net.used or 0, running = running(r) }
    end
    if d.power then return { need = d.power, pw = r.pw == true, lit = r.data.lit ~= false } end
    if d.node then return { node = true, pw = r.pw == true, wires = #Store.wiresOf(r.id) } end
    return nil
end

-- Fuel burn, batteries, auto refuel from the jerrycan slot. Once a minute.
local function tickMinute()
    for _, r in pairs(Store.pieces) do
        local g = genOf(r)
        if g and r.built then
            local d = r.data
            local before = math.floor(tonumber(d.fuel) or 0)
            local net = r.net or { out = 0, used = 0 }
            if d.on then
                -- top up from the jerrycan slot before the tank runs dry
                if (tonumber(d.fuel) or 0) < (tonumber(S.autoRefuelAt) or 10) and (tonumber(d.res) or 0) > 0 then
                    local move = math.min(d.res, g.tank - (d.fuel or 0))
                    if move > 0 then d.fuel = (d.fuel or 0) + move; d.res = d.res - move end
                end
                if (tonumber(d.fuel) or 0) > 0 then
                    local load = net.out > 0 and math.min(1, net.used / net.out) or 0
                    d.fuel = math.max(0, d.fuel - g.fuelHour / 60 * (0.4 + 0.6 * load))
                    -- spare output charges the batteries
                    for _, b in ipairs(d.bats or {}) do
                        b.charge = math.min(tonumber(b.cap) or 100, (tonumber(b.charge) or 0) + (tonumber(S.batteryChargeMin) or 2))
                    end
                end
                if (tonumber(d.fuel) or 0) <= 0 then
                    d.fuel = 0
                    d.on = false
                    dirty = true
                end
            elseif net.used > 0 then
                -- batteries carry the load while the engine is off
                local share = net.out > 0 and math.min(1, net.used / net.out) or 1
                for _, b in ipairs(d.bats or {}) do
                    if (tonumber(b.charge) or 0) > 0 then
                        b.charge = math.max(0, b.charge - (tonumber(S.batteryDrainMin) or 1) * share)
                        if b.charge <= 0 then dirty = true end
                    end
                end
            end
            if math.floor(tonumber(d.fuel) or 0) ~= before or d.on then Store.save(r); Store.push(r) end
        end
    end
end

CreateThread(function()
    local last = os.time()
    while true do
        Wait(5000)
        if Store.ready then
            if os.time() - last >= 60 then
                last = os.time()
                tickMinute()
                dirty = true
            end
            if dirty then compute() end
        end
    end
end)

-- Generator panel

local function gen(id)
    local r = Store.pieces[tonumber(id)]
    if r and r.built and genOf(r) then return r end
    return nil
end

local function fuelHeld(src)
    local ok, info = pcall(function() return exports.bs_inventory:MeasuredInfo(src, S.fuelItems) end)
    return ok and type(info) == 'table' and math.floor(tonumber(info.held) or 0) or 0
end

local function bestBattery(src)
    local best, bm
    local ok, list = pcall(function() return exports.bs_inventory:ItemMetaList(src, S.batteryItem) end)
    for _, e in ipairs(ok and list or {}) do
        local m = type(e.metadata) == 'table' and e.metadata or {}
        local cap = math.max(0, math.min(100, tonumber(m.cap) or 100))
        local charge = math.max(0, math.min(cap, tonumber(m.charge) or cap))
        if not bm or charge > bm.charge then best, bm = e.slot, { charge = charge, cap = cap } end
    end
    return best, bm
end

local function batteryCount(src)
    local ok, list = pcall(function() return exports.bs_inventory:ItemMetaList(src, S.batteryItem) end)
    return (ok and type(list) == 'table') and #list or 0
end

local function batteryMeta(b)
    local charge = math.floor((tonumber(b.charge) or 0) * 10 + 0.5) / 10
    local cap = math.floor((tonumber(b.cap) or 100) * 10 + 0.5) / 10
    return { charge = charge, cap = cap, battery = math.floor(charge), capacity = ('max %d%%'):format(math.floor(cap)) }
end

local function genView(src, r)
    local g = genOf(r)
    local d = r.data
    local bats = {}
    for i = 1, g.bats do
        local b = d.bats and d.bats[i]
        bats[i] = b and { charge = math.floor(tonumber(b.charge) or 0), cap = math.floor(tonumber(b.cap) or 100) } or false
    end
    local net = r.net or { out = 0, used = 0 }
    local _, mode = sourceOutput(r)
    return {
        ok = true, id = r.id, label = Building.PieceLabel(src, r.piece), on = d.on == true, running = running(r),
        fuel = math.floor(tonumber(d.fuel) or 0), tank = g.tank, res = math.floor(tonumber(d.res) or 0), resCap = S.reserveCap,
        output = g.output, fuelHour = g.fuelHour, bats = bats, out = net.out, used = net.used, mode = mode,
        held = fuelHeld(src), batteries = batteryCount(src),
        manage = Building.Member(src, r),
    }
end

local function usable(src, r)
    if not Building.Member(src, r) then return 'build.err.no_perm' end
    if not Building.Near(src, r, 3.5) then return 'build.err.far' end
    if r.data.ab then return 'build.err.abandoned' end
    return nil
end

BSB.RegisterCallback('build:gen:open', function(src, id)
    local r = gen(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    return genView(src, r)
end)

BSB.RegisterCallback('build:gen:act', function(src, id, action, slot)
    local r = gen(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    local g, d = genOf(r), r.data
    if action == 'toggle' then
        if not d.on then
            if (tonumber(d.fuel) or 0) <= 0 and (tonumber(d.res) or 0) > 0 then
                local move = math.min(d.res, g.tank)
                d.fuel, d.res = move, d.res - move
            end
            if (tonumber(d.fuel) or 0) <= 0 then return err(src, 'build.err.no_fuel') end
            d.on = true
        else
            d.on = false
        end
        Store.log(src, 'power', ('%s #%d %s'):format(r.piece, r.id, d.on and 'on' or 'off'), r)
    elseif action == 'reserve' then
        local room = math.max(0, (tonumber(S.reserveCap) or 100) - (tonumber(d.res) or 0))
        if room <= 0 then return err(src, 'build.err.full') end
        local got = exports.bs_inventory:PourOut(src, S.fuelItems, room) or 0
        if got <= 0 then return err(src, 'build.err.no_fuel') end
        d.res = (tonumber(d.res) or 0) + got
    elseif action == 'reserveTake' then
        local have = math.floor(tonumber(d.res) or 0)
        if have <= 0 then return err(src, 'build.err.nothing') end
        local put = exports.bs_inventory:PourInto(src, S.fuelItems, have) or 0
        if put <= 0 then return err(src, 'build.err.no_can') end
        d.res = have - put
    elseif action == 'batIn' then
        d.bats = d.bats or {}
        if #d.bats >= g.bats then return err(src, 'build.err.full') end
        local slotId, meta = bestBattery(src)
        if not slotId then return err(src, 'build.err.no_battery') end
        if not exports.bs_inventory:RemoveSlot(src, slotId, S.batteryItem) then return err(src, 'build.err.failed') end
        d.bats[#d.bats + 1] = meta
        Store.log(src, 'power', ('battery in %s #%d (%d%%)'):format(r.piece, r.id, math.floor(meta.charge)), r)
    elseif action == 'batOut' then
        local i = math.tointeger(tonumber(slot))
        local b = i and d.bats and d.bats[i]
        if not b then return { ok = false } end
        if not exports.bs_inventory:GiveItem(src, S.batteryItem, 1, batteryMeta(b)) then return err(src, 'build.err.space') end
        table.remove(d.bats, i)
    else
        return { ok = false }
    end
    Store.save(r, true)
    Store.push(r)
    compute()
    return genView(src, r)
end)

-- Refuel with the pour minigame. The score only decides how much is spilled, never more than the cans hold.
BSB.RegisterCallback('build:gen:refuelStart', function(src, id)
    local r = gen(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    local room = genOf(r).tank - (tonumber(r.data.fuel) or 0)
    if room < 1 then return err(src, 'build.err.full') end
    if fuelHeld(src) <= 0 then return err(src, 'build.err.no_fuel') end
    return Building.StartTimed(src, 'refuel', r.id, 3500)
end)

BSB.RegisterCallback('build:gen:refuelDone', function(src, id, score)
    local r = gen(id)
    if not r then return { ok = false } end
    if not Building.FinishTimed(src, 'refuel', r.id) then return err(src, 'build.err.too_quick') end
    local e = usable(src, r)
    if e then return err(src, e) end
    score = math.max(0, math.min(1, tonumber(score) or 0))
    local room = math.floor(genOf(r).tank - (tonumber(r.data.fuel) or 0))
    if room < 1 then return err(src, 'build.err.full') end
    local got = exports.bs_inventory:PourOut(src, S.fuelItems, room) or 0
    if got <= 0 then return err(src, 'build.err.no_fuel') end
    local kept = math.max(1, math.floor(got * (0.7 + 0.3 * score) + 0.5))
    r.data.fuel = math.min(genOf(r).tank, (tonumber(r.data.fuel) or 0) + kept)
    Store.save(r, true)
    Store.push(r)
    Building.PowerDirty()
    return { ok = true, fuel = math.floor(r.data.fuel), added = kept, spilled = got - kept }
end)

-- Batteries and the jerrycan slot go back to whoever takes the generator down
function Building.GeneratorEmpty(src, r)
    for _, b in ipairs(r.data.bats or {}) do
        pcall(function() exports.bs_inventory:GiveItem(src, S.batteryItem, 1, batteryMeta(b)) end)
    end
    r.data.bats = {}
    if (tonumber(r.data.res) or 0) > 0 then pcall(function() exports.bs_inventory:PourInto(src, S.fuelItems, r.data.res) end) end
    r.data.res = 0
end

-- Lights: on/off switch. They only glow with power.
BSB.RegisterCallback('build:light', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.built or not P[r.piece].power then return { ok = false } end
    if not Building.Member(src, r) then return err(src, 'build.err.no_perm') end
    if not Building.Near(src, r, 3.5) then return err(src, 'build.err.far') end
    r.data.lit = r.data.lit == false
    Store.save(r)
    compute()
    Store.push(r)
    return { ok = true, lit = r.data.lit, pw = r.pw == true }
end)

-- Wires between generators, poles and junction boxes

local function isNode(r) local d = r and P[r.piece]; return d and r.built and (d.generator or d.node) end

BSB.RegisterCallback('build:wire', function(src, aId, bId)
    if not S.wiresEnabled or not Store.wiresReady then return err(src, 'build.err.wires_off') end
    local a, b = Store.pieces[tonumber(aId)], Store.pieces[tonumber(bId)]
    if not isNode(a) or not isNode(b) or a.id == b.id then return err(src, 'build.err.wire_bad') end
    if not Building.Crew(src, a, 'build') or not Building.Crew(src, b, 'build') then return err(src, 'build.err.no_perm') end
    if not (Building.Near(src, a, 8.0) or Building.Near(src, b, 8.0)) then return err(src, 'build.err.far') end
    local len = Store.dist(a, b)
    if len > (tonumber(S.wireMaxLength) or 40) then return err(src, 'build.err.wire_long', { max = math.floor(S.wireMaxLength) }) end
    local na, nb = Store.wiresOf(a.id), Store.wiresOf(b.id)
    for _, w in ipairs(na) do if w.a == b.id or w.b == b.id then return err(src, 'build.err.wire_dup') end end
    local max = tonumber(S.maxWiresPerNode) or 4
    if #na >= max or #nb >= max then return err(src, 'build.err.wire_max', { n = max }) end
    local need = math.max(1, math.ceil(len / (tonumber(S.wirePerMetres) or 10)))
    if not Building.IsFree(src) then
        if Building.Count(src, S.wireItem) < need then
            return err(src, 'build.err.missing', { list = ('%dx %s'):format(need, Building.ItemLabel(src, S.wireItem)) })
        end
        if not exports.bs_inventory:RemoveItem(src, S.wireItem, need) then return err(src, 'build.err.failed') end
    end
    local owner = Building.CharOf(src)
    local fac = Building.FactionOf(src)
    local id = exports.oxmysql:insert_async('INSERT INTO `bs_build_wires` (`a_id`,`b_id`,`owner_char`,`faction_id`) VALUES (?,?,?,?)', { a.id, b.id, owner, fac })
    if not id then
        if not Building.IsFree(src) then Building.Give(src, S.wireItem, need) end
        return err(src, 'build.err.failed')
    end
    Store.addWire({ id = id, a = a.id, b = b.id, owner = owner, fac = fac })
    Store.log(src, 'wire', ('wire #%d %s #%d - %s #%d %.1fm'):format(id, a.piece, a.id, b.piece, b.id, len), a)
    compute()
    return { ok = true, id = id, used = need }
end)

-- Cuts every wire on a node. Half the wire comes back.
BSB.RegisterCallback('build:unwire', function(src, id)
    local r = Store.pieces[tonumber(id)]
    if not isNode(r) then return { ok = false } end
    if not Building.Crew(src, r, 'build') then return err(src, 'build.err.no_perm') end
    if not Building.Near(src, r, 5.0) then return err(src, 'build.err.far') end
    local list = Store.wiresOf(r.id)
    if #list == 0 then return err(src, 'build.err.nothing') end
    local back = 0
    for _, w in ipairs(list) do
        local a, b = Store.pieces[w.a], Store.pieces[w.b]
        if a and b then back = back + math.floor(math.ceil(Store.dist(a, b) / (tonumber(S.wirePerMetres) or 10)) / 2) end
        Store.removeWire(w)
    end
    if back > 0 then Building.Give(src, S.wireItem, back) end
    Store.log(src, 'wire', ('cut %d wires on %s #%d'):format(#list, r.piece, r.id), r)
    compute()
    return { ok = true, n = #list, back = back }
end)

-- Battery charging (bs_vehicles): a running, fuelled generator near the player
exports('RunningGeneratorNear', function(src, radius)
    local at = Building.PedPos(tonumber(src))
    if not at then return nil end
    for _, r in ipairs(Store.near(at.x, at.y, at.z, tonumber(radius) or 4.0)) do
        if genOf(r) and running(r) then return r.id end
    end
end)

-- Burns generator fuel for a charge. Switches it off when it runs dry, like the hourly burn.
exports('UseGeneratorFuel', function(id, amount)
    local r = Store.pieces[tonumber(id)]
    if not r or not r.data then return false end
    r.data.fuel = math.max(0, (r.data.fuel or 0) - (tonumber(amount) or 0))
    if r.data.fuel <= 0 then r.data.on = false; dirty = true end
    Store.save(r)
    Store.push(r)
    return true
end)

exports('HasPower', function(id) local r = Store.pieces[tonumber(id)]; return r ~= nil and r.pw == true end)

exports('ChargingPowerNear',function(src,radius)
    local at=Building.PedPos(tonumber(src));if not at then return false end
    for _,piece in ipairs(Store.near(at.x,at.y,at.z,math.min(10,tonumber(radius)or 4)))do
        if piece.pw==true or (genOf(piece)and running(piece))then return true end
    end
    return false
end)
