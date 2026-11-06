-- bs_building: what happens to a base when its faction flag is removed.
-- 'all'   = every piece of that faction inside the flag radius comes down now, part of the materials go into a salvage crate.
-- 'decay' = the pieces are abandoned and fall apart over abandonDecayHours; each one drops its share into the crate as it goes.
-- Storage contents never vanish: they go into the salvage crate too.

local S = Building.Settings
local P = Building.Pieces

local function refundPct() return math.max(0, math.min(100, tonumber(S.flagRemoveRefundPct) or 50)) / 100 end

local function cid(r) return 'build:' .. r.id end

local function registerBox(r)
    local d = P[r.piece]
    exports.bs_inventory:RegisterContainer(cid(r), { width = d.storage.w, height = d.storage.h, maxWeight = d.storage.weight, label = L('piece.' .. r.piece) })
end

-- The salvage crate for a removed flag. Made on first use, reused while it stands.
local function salvageCrate(flag, fac)
    for _, r in ipairs(Store.near(flag.x, flag.y, flag.z, 3.0)) do
        if r.piece == 'salvage_crate' and r.fac == fac then return r end
    end
    local r = Building.InsertBuilt(nil, 'salvage_crate', { x = flag.x, y = flag.y, z = flag.z }, tonumber(flag.heading) or 0.0, fac, nil, 'salvage')
    if r then registerBox(r) end
    return r
end

-- Moves items into the crate. What does not fit stays in the crate's owed list and goes in once there is room.
local function putIn(box, item, n)
    if n <= 0 then return end
    registerBox(box)
    local ok = exports.bs_inventory:ContainerGive(cid(box), item, n)
    if not ok then
        box.data.owed = box.data.owed or {}
        box.data.owed[item] = (box.data.owed[item] or 0) + n
        Store.save(box, true)
    end
end

local function refundInto(box, r)
    local d = P[r.piece]
    if not d or d.salvage then return end
    local k = refundPct()
    if r.built then
        for _, c in ipairs(Building.CostOf(d, Store.tier(r))) do putIn(box, c.item, math.floor(c.amount * k)) end
    else
        for item, n in pairs(r.dep or {}) do putIn(box, item, math.floor(n * k)) end
    end
    if d.storage then
        registerBox(r)
        for _, it in ipairs(exports.bs_inventory:ContainerTakeAll(cid(r)) or {}) do putIn(box, it.item, it.amount) end
    end
    if d.generator then
        local S2 = Building.Settings
        for _ in ipairs(r.data.bats or {}) do putIn(box, S2.batteryItem, 1) end
    end
    -- vending takings go to the faction treasury
    local bal = d.vending and math.floor(tonumber(r.data.bal) or 0) or 0
    if bal > 0 and r.fac and GetResourceState('bs_factions') == 'started' then
        pcall(function() exports.bs_factions:TreasuryDeposit(r.fac, bal, r.owner, 'deposit', 'Vending crate (flag removed)') end)
    end
end

local function piecesOf(flag)
    local out = {}
    local radius = tonumber(flag.radius) or S.flagRadius
    for _, r in ipairs(Store.near(flag.x, flag.y, flag.z, radius + 30.0)) do
        local d = P[r.piece]
        if d and not d.salvage and r.fac == flag.factionId and Building.Flat(r, flag) <= radius then out[#out + 1] = r end
    end
    return out
end

-- Called by bs_faction_bases after the flag row is marked removed.
exports('FlagRemoved', function(flag, mode, src)
    if type(flag) ~= 'table' or not flag.factionId or not tonumber(flag.x) then return { ok = false } end
    mode = mode == 'all' and 'all' or 'decay'
    local list = piecesOf(flag)
    if #list == 0 then return { ok = true, n = 0 } end
    local box = salvageCrate(flag, flag.factionId)
    if not box then return { ok = false } end
    local now = os.time()
    if mode == 'all' then
        for _, r in ipairs(list) do
            refundInto(box, r)
            Store.remove(r, 'flag')
        end
    else
        local hours = math.max(1, tonumber(S.abandonDecayHours) or 24)
        for _, r in ipairs(list) do
            r.data.ab = { at = now, ends = now + hours * 3600, box = box.id, hp = r.health }
            r.data.sleeper = nil
            if P[r.piece].generator then r.data.on = false end
            Store.save(r, true)
            Store.push(r)
        end
        Building.PowerDirty()
    end
    Store.log(src, 'flag_remove', ('%s flag #%s of %s: %s, %d pieces, salvage #%d'):format(tostring(flag.kind), tostring(flag.id), flag.factionId, mode, #list, box.id), flag)
    return { ok = true, n = #list, box = box.id }
end)

exports('FlagRemoveSettings', function()
    return { pct = math.floor(refundPct() * 100), hours = math.max(1, tonumber(S.abandonDecayHours) or 24) }
end)

-- How many pieces a flag removal would touch (the leader sees this before choosing)
exports('FlagPieces', function(flag)
    if type(flag) ~= 'table' or not tonumber(flag.x) then return 0 end
    return #piecesOf(flag)
end)

-- Abandoned pieces lose HP until they are gone. A new flag of the same faction over them saves them.
CreateThread(function()
    while true do
        Wait(60000)
        if Store.ready then
            local now = os.time()
            local allFlags = Building.Flags(nil)
            local list = {}
            for _, r in pairs(Store.pieces) do if r.data and r.data.ab then list[#list + 1] = r end end
            for _, r in ipairs(list) do
                local ab = r.data.ab
                local claim = Building.ClaimAt(r, allFlags)
                if claim and claim.factionId == r.fac then
                    r.data.ab = nil
                    Store.save(r, true)
                    Store.push(r)
                    Building.PowerDirty()
                elseif now >= (tonumber(ab.ends) or 0) then
                    local box = Store.pieces[tonumber(ab.box) or -1]
                    if not box then box = salvageCrate({ x = r.x, y = r.y, z = r.z, heading = 0 }, r.fac) end
                    if box then refundInto(box, r) end
                    Store.remove(r, 'decay')
                else
                    local span = math.max(1, (tonumber(ab.ends) or now) - (tonumber(ab.at) or now))
                    local left = ((tonumber(ab.ends) or now) - now) / span
                    local hp = math.max(1, (tonumber(ab.hp) or Store.maxHp(r)) * left)
                    if math.floor(hp) ~= math.floor(r.health) then
                        r.health = hp
                        Store.save(r)
                        Store.push(r)
                    end
                end
            end
            -- owed items go in as the crate gets emptied
            for _, r in pairs(Store.pieces) do
                if r.data and r.data.owed and next(r.data.owed) then
                    registerBox(r)
                    local left = {}
                    for item, n in pairs(r.data.owed) do
                        if not exports.bs_inventory:ContainerGive(cid(r), item, n) then left[item] = n end
                    end
                    r.data.owed = next(left) and left or nil
                    Store.save(r, true)
                end
            end
        end
    end
end)
