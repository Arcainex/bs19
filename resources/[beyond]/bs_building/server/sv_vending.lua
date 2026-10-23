-- bs_building vending crate

local S = Building.Settings
local P = Building.Pieces
local busy = {}

local function err(src, key, vars) return { ok = false, error = Lp(src, key, vars) } end

local function crate(id)
    local r = Store.pieces[tonumber(id)]
    if r and r.built and P[r.piece] and P[r.piece].vending then return r end
    return nil
end

local function cid(r) return 'build:' .. r.id end

local function register(src, r)
    local d = P[r.piece]
    exports.bs_inventory:RegisterContainer(cid(r), { width = d.storage.w, height = d.storage.h, maxWeight = d.storage.weight, label = Lp(src, 'piece.' .. r.piece) })
end

-- Stackable items only: the shelf hands out plain units, so weapons and gear with their own state stay out
local function sellable(item)
    local ok, def = pcall(function() return exports.bs_inventory:GetItem(item) end)
    return ok and type(def) == 'table' and (tonumber(def.stack) or 1) > 1
end

local function cashOf(src)
    local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if not ok or type(summary) ~= 'table' then return 0 end
    return tonumber(summary.accounts and summary.accounts.cash) or 0
end

local function shelf(src, r, forOwner)
    register(src, r)
    local counts = {}
    for _, e in ipairs(exports.bs_inventory:ContainerContents(cid(r)) or {}) do
        counts[e.item] = (counts[e.item] or 0) + (tonumber(e.amount) or 0)
    end
    local prices = r.data.prices or {}
    local out = {}
    for item, n in pairs(counts) do
        local price = math.floor(tonumber(prices[item]) or 0)
        local ok = sellable(item)
        if forOwner or (ok and price > 0) then
            out[#out + 1] = { item = item, amount = n, price = price, label = Building.ItemLabel(src, item), sellable = ok }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function view(src, r)
    local owner = Building.Manager(src, r)
    return {
        ok = true, id = r.id, owner = owner, items = shelf(src, r, owner), cash = cashOf(src),
        balance = owner and math.floor(tonumber(r.data.bal) or 0) or nil,
        sales = owner and (r.data.sales or 0) or nil, maxPrice = S.vendingMaxPrice,
    }
end

local function usable(src, r)
    if not S.vendingEnabled then return 'build.err.vending_off' end
    if not Building.Near(src, r, 3.5) then return 'build.err.far' end
    return nil
end

BSB.RegisterCallback('build:vend:open', function(src, id)
    local r = crate(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    return view(src, r)
end)

BSB.RegisterCallback('build:vend:stock', function(src, id)
    local r = crate(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    if not Building.Manager(src, r) then return err(src, 'build.err.no_perm') end
    register(src, r)
    exports.bs_inventory:OpenContainerFor(src, cid(r))
    return { ok = true }
end)

BSB.RegisterCallback('build:vend:price', function(src, id, item, price)
    local r = crate(id)
    if not r or type(item) ~= 'string' or #item > 64 then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    if not Building.Manager(src, r) then return err(src, 'build.err.no_perm') end
    price = math.floor(tonumber(price) or -1)
    local max = math.floor(tonumber(S.vendingMaxPrice) or 100000)
    if price < 0 or price > max then return err(src, 'build.err.price', { max = max }) end
    if price > 0 and not sellable(item) then return err(src, 'build.err.vend_items') end
    r.data.prices = r.data.prices or {}
    r.data.prices[item] = price > 0 and price or nil
    Store.save(r, true)
    return view(src, r)
end)

BSB.RegisterCallback('build:vend:buy', function(src, id, item, qty)
    local r = crate(id)
    if not r or type(item) ~= 'string' then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    if Building.IsOwner(src, r) then return err(src, 'build.err.own_crate') end
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or qty > 1000 then return { ok = false } end
    local price = math.floor(tonumber(r.data.prices and r.data.prices[item]) or 0)
    if price <= 0 or not sellable(item) then return err(src, 'build.err.not_for_sale') end
    if busy[r.id] then return err(src, 'build.err.too_quick') end
    busy[r.id] = true
    -- pcall so an error never leaves the crate stuck on busy
    local okRun, res = pcall(function()
        register(src, r)
        local cost = price * qty
        if exports.bs_inventory:ContainerCount(cid(r), item) < qty then return err(src, 'build.err.stock') end
        if cashOf(src) < cost then return err(src, 'build.err.cash') end
        -- Shelf first, then the bag, then the money. Every failed step puts back what moved.
        if not exports.bs_inventory:ContainerRemove(cid(r), item, qty) then return err(src, 'build.err.stock') end
        local before = exports.bs_inventory:CountItem(src, item)
        local given = exports.bs_inventory:GiveItem(src, item, qty)
        if not given then
            local added = exports.bs_inventory:CountItem(src, item) - before
            if added > 0 then exports.bs_inventory:RemoveItem(src, item, added) end
            exports.bs_inventory:ContainerGiveAll(cid(r), item, qty)
            return err(src, 'build.err.space')
        end
        if not exports.bs_core:RemoveMoney(src, 'cash', cost, 'build_vend_buy_' .. r.id) then
            exports.bs_inventory:RemoveItem(src, item, qty)
            exports.bs_inventory:ContainerGiveAll(cid(r), item, qty)
            return err(src, 'build.err.cash')
        end
        local tax = math.floor(cost * math.max(0, math.min(100, tonumber(S.vendingTaxPct) or 0)) / 100)
        r.data.bal = math.floor(tonumber(r.data.bal) or 0) + (cost - tax)
        r.data.sales = (r.data.sales or 0) + qty
        Store.save(r, true)
        local out = view(src, r)
        out.bought = { n = qty, label = Building.ItemLabel(src, item), cost = cost }
        return out
    end)
    busy[r.id] = nil
    if not okRun then print('^1[bs_building]^7 vend buy: ' .. tostring(res)); return err(src, 'build.err.failed') end
    return res
end)

BSB.RegisterCallback('build:vend:collect', function(src, id)
    local r = crate(id)
    if not r then return { ok = false } end
    local e = usable(src, r)
    if e then return err(src, e) end
    if not Building.Manager(src, r) then return err(src, 'build.err.no_perm') end
    local amount = math.floor(tonumber(r.data.bal) or 0)
    if amount <= 0 then return err(src, 'build.err.nothing') end
    if busy[r.id] then return err(src, 'build.err.too_quick') end
    busy[r.id] = true
    r.data.bal = 0
    Store.save(r, true)
    local ok = exports.bs_core:AddMoney(src, 'cash', amount, 'build_vend_collect_' .. r.id)
    if not ok then
        r.data.bal = amount
        Store.save(r, true)
        busy[r.id] = nil
        return err(src, 'build.err.failed')
    end
    busy[r.id] = nil
    Store.log(src, 'vend_collect', ('crate #%d paid %d'):format(r.id, amount), r)
    local out = view(src, r)
    out.collected = amount
    return out
end)
