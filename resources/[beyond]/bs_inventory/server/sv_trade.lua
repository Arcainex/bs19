-- Bilateral player trade. Offers refer to original inventory rows, never to client-supplied item names. Only complete stacks can be offered; split a stack with the inventory split gesture before trading.
local T = Inv.TradeInternals
local sessions = {} -- [source] = shared session
local nextId = 0

local function nearby(a, b)
    if not GetPlayerName(a) or not GetPlayerName(b) then return false end
    local pa, pb = exports.bs_core:GetPlayer(a), exports.bs_core:GetPlayer(b)
    if not pa or not pb or not pa.charId or not pb.charId then return false end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or not pedB or pedA == 0 or pedB == 0 then return false end
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    if GetEntityHealth(pedA) <= 0 or GetEntityHealth(pedB) <= 0 then return false end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
        <= (Inventory.Settings.tradeDistance or 3.0)
end

local function other(s, src) return s.a == src and s.b or s.a end

local function view(s, src)
    local peer = other(s, src)
    local mine, theirs = {}, {}
    for slot, offer in pairs(s.offers[src]) do
        mine[#mine + 1] = {
            slot = slot, item = offer.item, label = offer.label, amount = offer.amount,
            category = offer.category, durability = offer.durability,
            capacity = offer.capacity,
        }
    end
    for slot, offer in pairs(s.offers[peer]) do
        theirs[#theirs + 1] = {
            slot = slot, item = offer.item, label = offer.label, amount = offer.amount,
            category = offer.category, durability = offer.durability,
            capacity = offer.capacity,
        }
    end
    table.sort(mine, function(x, y) return x.slot < y.slot end)
    table.sort(theirs, function(x, y) return x.slot < y.slot end)
    return {
        id = s.id, phase = s.phase, peer = peer,
        invitedToYou = s.b == src,
        peerName = (exports.bs_core:GetPlayer(peer) or {}).name or Lp(src, 'trade.survivor_name'),
        mine = mine, theirs = theirs,
        myCash = s.cash[src], peerCash = s.cash[peer],
        availableCash = (function()
            local player = exports.bs_core:GetPlayer(src)
            return player and player.accounts and tonumber(player.accounts.cash) or 0
        end)(),
        confirmed = s.confirmed[src], peerConfirmed = s.confirmed[peer],
    }
end

local function push(s)
    for _, src in ipairs({ s.a, s.b }) do
        if GetPlayerName(src) then
            TriggerClientEvent('bs:inventory:tradeState', src, view(s, src))
        end
    end
end

-- Close reasons are English internally; each player sees them in their own language.
local REASON_KEYS = {
    ['Trade cancelled'] = 'trade.r_cancelled',
    ['Too far apart'] = 'trade.r_far',
    ['Trade declined'] = 'trade.r_declined',
    ['Trade unavailable'] = 'trade.r_unavail',
    ['Player disconnected'] = 'trade.r_disc',
    ['Character changed'] = 'trade.r_char',
    ['Trade timed out'] = 'trade.r_timeout',
    ['not enough carry weight'] = 'trade.r_weight',
    ['not enough bag slots'] = 'trade.r_slots',
    ['not enough bag space'] = 'trade.r_space',
    ['an offered item changed'] = 'trade.r_changed',
    ['not enough cash'] = 'trade.e_no_cash',
    ['character unavailable'] = 'trade.e_char',
    ['inventory is busy'] = 'trade.e_busy',
}

local function finish(s, reason, complete)
    if sessions[s.a] ~= s then return end
    sessions[s.a], sessions[s.b] = nil, nil
    Inv.TradeLock[s.a], Inv.TradeLock[s.b] = nil, nil
    Inv.TradeLockedOwner[tostring(s.charA)] = nil
    Inv.TradeLockedOwner[tostring(s.charB)] = nil
    for _, src in ipairs({ s.a, s.b }) do
        local player = exports.bs_core:GetPlayer(src)
        local expected = src == s.a and s.charA or s.charB
        if GetPlayerName(src) and player and player.charId == expected then
            TriggerClientEvent('bs:inventory:tradeState', src, {
                phase = 'closed', reason = reason and (REASON_KEYS[reason] and Lp(src, REASON_KEYS[reason]) or reason) or nil,
                complete = complete or false,
            })
            Inv.Push(src)
        else
            T.evict(expected)
        end
    end
end

local function cancel(s, reason)
    if s.busy then
        s.cancelled = reason or 'Trade cancelled'
    else
        finish(s, reason or 'Trade cancelled')
    end
end

local function idle(inv)
    local deadline = GetGameTimer() + 10000
    while T.pending(inv) > 0 and GetGameTimer() < deadline do Wait(0) end
    return T.pending(inv) == 0
end

local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, value in pairs(a) do
        if not sameValue(value, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

BSB.RegisterCallback('inventory:tradeRequest', function(src, target)
    target = tonumber(target)
    if not target or target == src or sessions[src] or sessions[target] then
        return { ok = false, error = Lp(src, 'trade.e_already') }
    end
    if not nearby(src, target) then return { ok = false, error = Lp(src, 'trade.e_3m') } end
    local a, pa = T.of(src)
    local b, pb = T.of(target)
    if not a or not b or pa.charId == pb.charId then
        return { ok = false, error = Lp(src, 'trade.e_char') }
    end
    if not idle(a) or not idle(b) then
        return { ok = false, error = Lp(src, 'trade.e_busy') }
    end
    if sessions[src] or sessions[target] or not nearby(src, target) then
        return { ok = false, error = Lp(src, 'trade.e_unavail') }
    end
    nextId = nextId + 1
    local s = {
        id = nextId, a = src, b = target, charA = pa.charId, charB = pb.charId,
        phase = 'invited', offers = { [src] = {}, [target] = {} },
        cash = { [src] = 0, [target] = 0 },
        confirmed = { [src] = false, [target] = false },
        expires = GetGameTimer() + 30000,
    }
    sessions[src], sessions[target] = s, s
    push(s)
    return { ok = true }
end)

BSB.RegisterCallback('inventory:tradeMoney', function(src, amount)
    local s = sessions[src]
    if not s or s.phase ~= 'offering' or s.busy then
        return { ok = false, error = Lp(src, 'trade.e_none') }
    end
    amount = tonumber(amount)
    if not amount or amount % 1 ~= 0 or amount < 0 or amount > 100000000 then
        return { ok = false, error = Lp(src, 'trade.e_cash') }
    end
    if not nearby(s.a, s.b) then
        cancel(s, 'Too far apart')
        return { ok = false, error = Lp(src, 'trade.e_closer') }
    end
    local player = exports.bs_core:GetPlayer(src)
    if not player or player.charId ~= (src == s.a and s.charA or s.charB)
        or not player.accounts or (tonumber(player.accounts.cash) or 0) < amount then
        return { ok = false, error = Lp(src, 'trade.e_no_cash') }
    end
    s.cash[src] = amount
    s.confirmed[s.a], s.confirmed[s.b] = false, false
    s.expires = GetGameTimer() + 120000
    push(s)
    return { ok = true }
end)

BSB.RegisterCallback('inventory:tradeRespond', function(src, accept)
    local s = sessions[src]
    if not s or s.b ~= src or s.phase ~= 'invited' then
        return { ok = false, error = Lp(src, 'trade.expired') }
    end
    if not accept then cancel(s, 'Trade declined'); return { ok = true } end
    if not nearby(s.a, s.b) then
        cancel(s, 'Too far apart')
        return { ok = false, error = Lp(src, 'trade.e_closer') }
    end
    local a, pa = T.of(s.a)
    local b, pb = T.of(s.b)
    if not a or not b or not pa or not pb or pa.charId ~= s.charA
        or pb.charId ~= s.charB or not idle(a) or not idle(b)
        or sessions[s.a] ~= s or sessions[s.b] ~= s or s.phase ~= 'invited'
        or not nearby(s.a, s.b) then
        cancel(s, 'Trade unavailable')
        return { ok = false, error = Lp(src, 'trade.unavailable') }
    end
    Inv.TradeLock[s.a], Inv.TradeLock[s.b] = true, true
    Inv.TradeLockedOwner[tostring(s.charA)] = true
    Inv.TradeLockedOwner[tostring(s.charB)] = true
    s.phase = 'offering'
    s.expires = GetGameTimer() + 120000
    push(s)
    return { ok = true }
end)

BSB.RegisterCallback('inventory:tradeOffer', function(src, slot, add)
    local s = sessions[src]
    if not s or s.phase ~= 'offering' or s.busy then
        return { ok = false, error = Lp(src, 'trade.e_none') }
    end
    if not nearby(s.a, s.b) then
        cancel(s, 'Too far apart')
        return { ok = false, error = Lp(src, 'trade.e_closer') }
    end
    local inv = T.of(src)
    slot = tonumber(slot)
    if not inv or not slot or slot % 1 ~= 0 or slot < 1
        or (slot > T.slotLimit(inv) + 5 and not T.isBag(inv, slot)) then
        return { ok = false, error = Lp(src, 'trade.e_bad_slot') }
    end
    if add then
        local entry = inv.slots[slot]
        if not entry or not entry.id or entry.amount < 1 then
            return { ok = false, error = Lp(src, 'trade.e_item') }
        end
        local count = 0
        for _ in pairs(s.offers[src]) do count = count + 1 end
        if count >= 12 and not s.offers[src][slot] then
            return { ok = false, error = Lp(src, 'trade.e_full') }
        end
        local def = Items.Get(entry.item) or {}
        s.offers[src][slot] = {
            id = entry.id, item = entry.item, amount = entry.amount,
            label = ItemLabel(entry.item, src),
            category = def.category,
            durability = entry.durability,
            metadata = json.encode(entry.metadata or {}),
            capacity = def.data and def.data.capacity or nil,
        }
    else
        s.offers[src][slot] = nil
    end
    s.confirmed[s.a], s.confirmed[s.b] = false, false
    s.expires = GetGameTimer() + 120000
    push(s)
    return { ok = true }
end)

local function plan(s)
    local invs = { [s.a] = T.of(s.a), [s.b] = T.of(s.b) }
    if not invs[s.a] or not invs[s.b] then return nil, 'character unavailable' end
    if not idle(invs[s.a]) or not idle(invs[s.b]) then return nil, 'inventory is busy' end

    local outgoing, incoming, remaining = {}, {}, {}
    for _, src in ipairs({ s.a, s.b }) do
        local inv = invs[src]
        outgoing[src], incoming[src], remaining[src] = {}, {}, {}
        for slot, entry in pairs(inv.slots) do remaining[src][slot] = entry end
        for slot, offer in pairs(s.offers[src]) do
            local entry = inv.slots[slot]
            if not entry or entry.id ~= offer.id or entry.item ~= offer.item
                or entry.amount ~= offer.amount or entry.durability ~= offer.durability
                or not sameValue(entry.metadata or {}, json.decode(offer.metadata)) then
                return nil, 'an offered item changed'
            end
            outgoing[src][#outgoing[src] + 1] = { slot = slot, entry = entry }
            remaining[src][slot] = nil
        end
    end
    for _, src in ipairs({ s.a, s.b }) do
        local peer = other(s, src)
        local inv = invs[src]
        local weight = 0
        for _, entry in pairs(remaining[src]) do
            local def = Items.Get(entry.item) or {}
            weight = weight + (def.weight or 0.5) * entry.amount
        end
        table.sort(outgoing[peer], function(x, y)
            local a, b = Items.Get(x.entry.item) or {}, Items.Get(y.entry.item) or {}
            return (a.w or 1) * (a.h or 1) > (b.w or 1) * (b.h or 1)
        end)
        local occupied = {}
        for slot, entry in pairs(remaining[src]) do
            if T.isBag(inv, slot) then
                local def = Items.Get(entry.item) or {}
                occupied[#occupied + 1] = {
                    id = slot, x = entry.x, y = entry.y, rot = entry.rot,
                    w = def.w or 1, h = def.h or 1,
                }
            end
        end
        for _, offered in ipairs(outgoing[peer]) do
            local entry = offered.entry
            local def = Items.Get(entry.item) or {}
            weight = weight + (def.weight or 0.5) * entry.amount
            if weight > inv.maxWeight + 0.001 then return nil, 'not enough carry weight' end
            local slot
            for _, n in ipairs(T.bagSlots(inv)) do
                if not remaining[src][n] then slot = n; break end
            end
            if not slot then return nil, 'not enough bag slots' end
            local x, y, rot = Grid.FirstFit(T.gridBounds(inv), occupied, {
                id = slot, w = def.w or 1, h = def.h or 1,
            }, true)
            if not x then return nil, 'not enough bag space' end
            remaining[src][slot] = entry
            occupied[#occupied + 1] = {
                id = slot, x = x, y = y, rot = rot,
                w = def.w or 1, h = def.h or 1,
            }
            incoming[src][#incoming[src] + 1] = {
                from = peer, oldSlot = offered.slot, slot = slot,
                entry = entry, x = x, y = y, rot = rot,
            }
        end
    end
    return { invs = invs, incoming = incoming, outgoing = outgoing }
end

local function commit(s)
    local p, reason = plan(s)
    if not p then return false, reason end
    if not nearby(s.a, s.b) or s.cancelled then return false, 'Trade cancelled' end
    local pa, pb = exports.bs_core:GetPlayer(s.a), exports.bs_core:GetPlayer(s.b)
    if not pa or not pb or pa.charId ~= s.charA or pb.charId ~= s.charB then
        return false, 'character changed'
    end
    local cashA = pa.accounts and tonumber(pa.accounts.cash) or 0
    local cashB = pb.accounts and tonumber(pb.accounts.cash) or 0
    if cashA < s.cash[s.a] or cashB < s.cash[s.b] then
        return false, 'not enough cash'
    end

    -- startTransaction's callback runs outside a Lua thread, so query() returns an unresolved promise there. Check first with plain awaits, then write everything in one atomic transaction. The trade holds both caches (busy + idle + TradeLockedOwner), so nothing else writes these rows meanwhile.
    local function fail(why)
        print(('^3[BeyondSurvival]^7 trade %s refused: %s'):format(s.id, why))
        return false
    end
    local dbOk, committed = pcall(function()
        local balances = MySQL.query.await('SELECT id, cash FROM bs_characters WHERE id IN (?, ?)',
            { s.charA, s.charB })
        if type(balances) ~= 'table' or #balances ~= 2 then return fail('characters missing') end
        local dbCash = {}
        for _, r in ipairs(balances) do dbCash[r.id] = tonumber(r.cash) or 0 end
        if (dbCash[s.charA] or 0) < s.cash[s.a] or (dbCash[s.charB] or 0) < s.cash[s.b] then
            return fail('not enough cash in db')
        end

        -- only the rows that actually change hands need to match
        for _, src in ipairs({ s.a, s.b }) do
            for _, move in ipairs(p.incoming[src]) do
                local e = move.entry
                local row = MySQL.single.await(
                    'SELECT inventory_id, item, amount FROM bs_inventory_items WHERE id = ?', { e.id })
                if not row then return fail(('item %s has no row'):format(tostring(e.id))) end
                if tonumber(row.inventory_id) ~= tonumber(p.invs[move.from].id)
                    or row.item ~= e.item or tonumber(row.amount) ~= tonumber(e.amount) then
                    return fail(('item %s changed in db'):format(tostring(e.id)))
                end
            end
        end
        if s.cancelled or not nearby(s.a, s.b) then return fail('cancelled') end

        local queries = {}
        if s.cash[s.a] > 0 or s.cash[s.b] > 0 then
            local nextA = cashA - s.cash[s.a] + s.cash[s.b]
            local nextB = cashB - s.cash[s.b] + s.cash[s.a]
            if nextA < 0 or nextB < 0 then return fail('negative cash') end
            queries[#queries + 1] = { query = 'UPDATE bs_characters SET cash = ? WHERE id = ?', values = { nextA, s.charA } }
            queries[#queries + 1] = { query = 'UPDATE bs_characters SET cash = ? WHERE id = ?', values = { nextB, s.charB } }
        end
        for _, src in ipairs({ s.a, s.b }) do
            for _, move in ipairs(p.incoming[src]) do
                queries[#queries + 1] = {
                    query = [[UPDATE bs_inventory_items
                                 SET inventory_id = ?, slot_x = ?, grid_x = ?, grid_y = ?, rotated = ?
                               WHERE id = ?]],
                    values = { p.invs[src].id, move.slot, move.x or 0, move.y or 0,
                               move.rot and 1 or 0, move.entry.id },
                }
            end
        end
        if #queries == 0 then return true end
        if not MySQL.transaction.await(queries) then return fail('transaction rolled back') end
        return true
    end)
    if not dbOk then print(('^1[BeyondSurvival]^7 trade %s db error: %s'):format(s.id, tostring(committed))) end
    if not dbOk or not committed then
        return false, dbOk and 'database refused trade' or 'database error'
    end
    for _, src in ipairs({ s.a, s.b }) do
        for _, offer in ipairs(p.outgoing[src]) do
            p.invs[src].slots[offer.slot] = nil
        end
    end
    for _, src in ipairs({ s.a, s.b }) do
        for _, move in ipairs(p.incoming[src]) do
            local entry = move.entry
            entry.slot, entry.x, entry.y, entry.rot = move.slot, move.x, move.y, move.rot
            p.invs[src].slots[move.slot] = entry
        end
    end
    -- Keep core's live account/HUD in step with the committed rows. Delta APIs also write the cash audit trail.
    if s.cash[s.a] > 0 then
        exports.bs_core:RemoveMoney(s.a, 'cash', s.cash[s.a], 'player trade')
        exports.bs_core:AddMoney(s.b, 'cash', s.cash[s.a], 'player trade')
    end
    if s.cash[s.b] > 0 then
        exports.bs_core:RemoveMoney(s.b, 'cash', s.cash[s.b], 'player trade')
        exports.bs_core:AddMoney(s.a, 'cash', s.cash[s.b], 'player trade')
    end
    return true
end

BSB.RegisterCallback('inventory:tradeConfirm', function(src)
    local s = sessions[src]
    if not s or s.phase ~= 'offering' or s.busy then
        return { ok = false, error = Lp(src, 'trade.e_none') }
    end
    if not nearby(s.a, s.b) then
        cancel(s, 'Too far apart')
        return { ok = false, error = Lp(src, 'trade.e_closer') }
    end
    s.confirmed[src] = true
    push(s)
    if not s.confirmed[other(s, src)] then return { ok = true } end
    s.busy = true
    local callOk, ok, reason = pcall(commit, s)
    s.busy = false
    if not callOk then
        print(('^1[BeyondSurvival]^7 trade %s failed: %s'):format(s.id, tostring(ok)))
        -- Failure may have happened after a database commit, so discard both caches; the next push reads committed data.
        T.evict(s.charA)
        T.evict(s.charB)
        reason, ok = 'Trade failed; inventory reloaded', false
    end
    finish(s, ok and 'Trade completed' or (reason or 'Trade failed'), ok)
    return { ok = ok, error = ok and nil or reason }
end)

BSB.RegisterCallback('inventory:tradeCancel', function(src)
    local s = sessions[src]
    if s then cancel(s, 'Trade cancelled') end
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    local s = sessions[source]
    if s then cancel(s, 'Player disconnected') end
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    local s = player and sessions[player.source]
    if s then cancel(s, 'Character changed') end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local checked = {}
        for _, s in pairs(sessions) do
            if not checked[s.id] then
                checked[s.id] = true
                if GetGameTimer() > s.expires then cancel(s, 'Trade timed out')
                elseif not nearby(s.a, s.b) then cancel(s, 'Too far apart')
                else
                    local a, b = exports.bs_core:GetPlayer(s.a), exports.bs_core:GetPlayer(s.b)
                    if not a or not b or a.charId ~= s.charA or b.charId ~= s.charB then
                        cancel(s, 'Character changed')
                    end
                end
            end
        end
    end
end)
