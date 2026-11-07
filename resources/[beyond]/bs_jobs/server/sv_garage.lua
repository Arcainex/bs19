-- bs_jobs mechanic garage. The server checks the job, the place, the vehicle type and takes the materials;
-- the mechanic's client paints and bolts things on. Owned cars keep everything.

local G = Jobs.Garage
local q, x = J.q, J.x
local INV = exports.bs_inventory

local Cosmetics = {}   -- [plate] = { paint = { p1, p2 }, props = { id = true } }
local Bills = {}       -- [customerSrc] = { mech, amount, at }

local function def(list, id) for _, o in ipairs(list) do if o.id == id then return o end end end

-- Who may work on this vehicle here. Returns job def, entity, plate, kind ('car'|'bike') or nil, error.
local function check(src, netId)
    local job = J.JobOf(src)
    local jd = job and Jobs.Defs[job]
    if not jd or not jd.garage then return nil, Lp(src, 'err.not_mechanic') end
    local fid = J.Faction(src)
    if not J.NearStation(src, fid, G.radius or 14.0, 'yard') then return nil, Lp(src, 'err.not_at_station') end
    local ent, plate = J.VehicleNear(src, netId, 8.0)
    if not ent then return nil, Lp(src, 'err.not_there') end
    local vtype = GetVehicleType(ent)
    local kind = vtype == 'bike' and 'bike' or (vtype == 'automobile' and 'car' or nil)
    if not kind then return nil, Lp(src, 'err.garage_type') end
    if kind == 'bike' and jd.garage ~= 'bike' then return nil, Lp(src, 'err.bikes_bikers') end
    if kind == 'car' and jd.garage ~= 'car' then return nil, Lp(src, 'err.cars_only_mech') end
    return jd, ent, plate, kind, job
end

local function costText(src, cost, mult)
    local out = {}
    for _, c in ipairs(cost or {}) do
        out[#out + 1] = { item = c.item, label = INV:ItemLabel(c.item, src) or c.item, amount = c.amount * (mult or 1), have = INV:CountItem(src, c.item) }
    end
    return out
end

local function pay(src, cost, mult)
    mult = mult or 1
    for _, c in ipairs(cost or {}) do
        if INV:CountItem(src, c.item) < c.amount * mult then
            return false, Lp(src, 'err.missing_items', { item = INV:ItemLabel(c.item, src) or c.item, n = c.amount * mult })
        end
    end
    for _, c in ipairs(cost or {}) do INV:RemoveItem(src, c.item, c.amount * mult) end
    return true
end

BSB.RegisterCallback('jobs:garage:open', function(src, netId)
    local jd, ent, plate, kind = check(src, netId)
    if not jd then return { ok = false, error = ent } end
    local info = exports.bs_vehicles:JobInfo(plate) or {}
    local L = function(k) return Lp(src, k) end
    local out = { ok = true, plate = plate, kind = kind, owned = info.owner ~= nil, mods = info.mods or {}, cosmetic = Cosmetics[plate],
                  repair = { cost = costText(src, G.repair.cost) }, paints = {}, slots = {}, props = {}, maxBill = G.maxBill }
    for _, p in ipairs(G.paints) do out.paints[#out.paints + 1] = { id = p.id, label = L('paint.' .. p.id), p1 = p.p1, p2 = p.p2, cost = costText(src, G.paintCost) } end
    for _, m in ipairs(G.mods) do out.slots[#out.slots + 1] = { id = m.id, label = L('mod.' .. m.id), slot = m.slot, max = m.max, cost = costText(src, m.cost) } end
    if kind == 'car' then
        for _, p in ipairs(G.props) do out.props[#out.props + 1] = { id = p.id, label = L('prop.' .. p.id), cost = costText(src, p.cost) } end
    end
    return out
end)

local function persist(plate, owned)
    local c = Cosmetics[plate]
    if owned then
        if c then
            x('INSERT INTO bs_job_vehicle_mods (plate, paint, props, updated_at) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE paint = VALUES(paint), props = VALUES(props), updated_at = VALUES(updated_at)',
                { plate, json.encode(c.paint or {}), json.encode(c.props or {}), J.Now() })
        else
            x('DELETE FROM bs_job_vehicle_mods WHERE plate = ?', { plate })
        end
    end
    TriggerClientEvent('bs:jobs:cosmetic', -1, plate, c or false)
end

-- One garage job. what = repair | paint | mod | prop | clearprops; id = option id; level for mods.
BSB.RegisterCallback('jobs:garage:apply', function(src, a)
    a = type(a) == 'table' and a or {}
    local jd, ent, plate, kind, job = check(src, a.netId)
    if not jd then return { ok = false, error = ent } end
    local info = exports.bs_vehicles:JobInfo(plate) or {}
    local owned = info.owner ~= nil
    local out = { ok = true, what = a.what }
    if a.what == 'repair' then
        local ok, err = pay(src, G.repair.cost)
        if not ok then return { ok = false, error = err } end
        pcall(function() exports.bs_core:AwardAction(src, 'vehicle_repaired') end)
        TriggerEvent('bs:jobs:event', src, 'vehicle_repaired', 1)   -- counts on mechanic contracts
    elseif a.what == 'paint' then
        local p = def(G.paints, tostring(a.id))
        if not p then return { ok = false } end
        local ok, err = pay(src, G.paintCost)
        if not ok then return { ok = false, error = err } end
        Cosmetics[plate] = Cosmetics[plate] or { props = {} }
        Cosmetics[plate].paint = { p1 = p.p1, p2 = p.p2 }
        out.p1, out.p2 = p.p1, p.p2
        persist(plate, owned)
    elseif a.what == 'mod' then
        local m = def(G.mods, tostring(a.id))
        if not m then return { ok = false } end
        local level = math.floor(tonumber(a.level) or 0)
        if level < 0 or level > m.max then return { ok = false } end
        local cur = tonumber((info.mods or {})[tostring(m.slot)]) or -1
        -- Stock (level 0) is free and gives nothing back. Higher levels cost per level.
        if level > 0 then
            local ok, err = pay(src, m.cost, level)
            if not ok then return { ok = false, error = err } end
        end
        out.slot, out.index = m.slot, level - 1
        if owned then exports.bs_vehicles:JobMergeMods(plate, { [m.slot] = level - 1 }) end
        J.Log(src, 'garage', ('%s %s %d -> %d'):format(plate, m.id, cur, level - 1))
    elseif a.what == 'prop' then
        if kind ~= 'car' then return { ok = false, error = Lp(src, 'err.garage_type') } end
        local p = def(G.props, tostring(a.id))
        if not p then return { ok = false } end
        Cosmetics[plate] = Cosmetics[plate] or { props = {} }
        if Cosmetics[plate].props[p.id] then return { ok = false, error = Lp(src, 'err.already_fitted') } end
        local ok, err = pay(src, p.cost)
        if not ok then return { ok = false, error = err } end
        Cosmetics[plate].props[p.id] = true
        persist(plate, owned)
    elseif a.what == 'clearprops' then
        if Cosmetics[plate] then Cosmetics[plate].props = {}; persist(plate, owned) end
    else
        return { ok = false }
    end
    if a.what ~= 'clearprops' then J.Progress(src, kind == 'bike' and 'garage_bike' or 'garage_car', 1) end
    out.saved = owned
    return out
end)

BSB.RegisterCallback('jobs:cosmetics', function() return { ok = true, list = Cosmetics } end)

--------------------------------------------------------------------------------
-- Bills: the mechanic asks the owner (or the driver) to pay. They answer with Y or N.
--------------------------------------------------------------------------------

BSB.RegisterCallback('jobs:garage:bill', function(src, a)
    a = type(a) == 'table' and a or {}
    local jd, ent, plate = check(src, a.netId)
    if not jd then return { ok = false, error = ent } end
    local amount = math.floor(tonumber(a.amount) or 0)
    if amount < 1 or amount > (tonumber(G.maxBill) or 5000) then return { ok = false, error = Lp(src, 'err.bill_range', { n = G.maxBill }) } end
    local info = exports.bs_vehicles:JobInfo(plate) or {}
    local customer = info.owner and J.SrcOf(info.owner)
    if not customer then
        local driver = GetPedInVehicleSeat(ent, -1)
        for _, v in ipairs(GetPlayers()) do if GetPlayerPed(tonumber(v)) == driver and driver ~= 0 then customer = tonumber(v) end end
    end
    if not customer or customer == src then return { ok = false, error = Lp(src, 'err.no_customer') } end
    local cp, mp = J.PedPos(customer), J.PedPos(src)
    if not cp or not mp or #(cp - mp) > 30.0 then return { ok = false, error = Lp(src, 'err.no_customer') } end
    Bills[customer] = { mech = src, amount = amount, at = GetGameTimer() }
    TriggerClientEvent('bs:jobs:prompt', customer, { kind = 'bill', text = Lp(customer, 'n.bill', { name = J.Name(src), n = amount }) })
    return { ok = true }
end)

RegisterNetEvent('bs:jobs:answer', function(kind, yes)
    local src = source
    if kind ~= 'bill' then return end
    local b = Bills[src]
    Bills[src] = nil
    if not b or GetGameTimer() - b.at > 30000 or not GetPlayerName(b.mech) then return end
    if yes ~= true then J.Notify(b.mech, 'warn', 'n.bill_declined'); return end
    if not exports.bs_core:RemoveMoney(src, 'cash', b.amount, 'mechanic bill') then
        J.Notify(src, 'error', 'err.no_money'); J.Notify(b.mech, 'warn', 'n.bill_declined'); return
    end
    exports.bs_core:AddMoney(b.mech, 'cash', b.amount, 'mechanic bill')
    J.Notify(b.mech, 'success', 'n.bill_paid', { n = b.amount })
    J.Log(src, 'bill', ('paid %d to %d'):format(b.amount, J.CharId(b.mech) or 0))
end)

AddEventHandler('playerDropped', function() Bills[source] = nil end)

CreateThread(function()
    while not J.Ready do Wait(500) end
    for _, r in ipairs(q('SELECT plate, paint, props FROM bs_job_vehicle_mods')) do
        local ok1, paint = pcall(json.decode, r.paint or 'null')
        local ok2, props = pcall(json.decode, r.props or '{}')
        Cosmetics[r.plate] = { paint = ok1 and type(paint) == 'table' and paint.p1 and paint or nil, props = ok2 and type(props) == 'table' and props or {} }
    end
end)
