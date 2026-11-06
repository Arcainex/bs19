-- Reward delivery: items to the bag (overflow to the mailbox), cash/XP paid now or kept until next login, cars as owned stored vehicles.
PS = PS or {}

function PS.Log(src, kind, details, cid)
    local name = src and GetPlayerName(src) or ('char ' .. tostring(cid))
    print(('^5[bs_pass]^7 %s %s %s'):format(name, kind, details))
    MySQL.insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`) VALUES (?,?,?,?,?,?,?)',
        { src, src and GetPlayerIdentifierByType(src, 'license') or nil, cid, tostring(name):sub(1, 64), kind, 0, tostring(details):sub(1, 512) })
end

function PS.MailId(cid) return 'pass_mail:' .. tostring(cid) end

function PS.EnsureMail(cid)
    local S = Pass.Settings
    exports.bs_inventory:RegisterContainer(PS.MailId(cid), { width = 10, height = math.max(2, math.ceil((S.mailboxSlots or 100) / 10)), maxWeight = S.mailboxWeight, label = 'Wasteland Pass mailbox', compact = true })
end

local function toMail(cid, item, amount)
    PS.EnsureMail(cid)
    local ok, why = exports.bs_inventory:ContainerGive(PS.MailId(cid), item, amount)
    if not ok then print(('^1[bs_pass]^7 mailbox give failed char %s %s x%s: %s'):format(tostring(cid), tostring(item), tostring(amount), tostring(why))) end
    return ok
end

-- Cash/XP owed to a character that was offline.
local function addPending(cid, cash, xp)
    MySQL.query.await('INSERT INTO `bs_pass_pending` (`char_id`,`cash`,`xp`) VALUES (?,?,?) ON DUPLICATE KEY UPDATE `cash`=`cash`+VALUES(`cash`), `xp`=`xp`+VALUES(`xp`)',
        { cid, cash or 0, xp or 0 })
end

function PS.PayPending(src, cid)
    local row = MySQL.single.await('SELECT `cash`,`xp` FROM `bs_pass_pending` WHERE `char_id` = ?', { cid })
    if not row or ((row.cash or 0) <= 0 and (row.xp or 0) <= 0) then return end
    MySQL.query.await('DELETE FROM `bs_pass_pending` WHERE `char_id` = ?', { cid })
    if row.cash > 0 then exports.bs_core:AddMoney(src, 'cash', row.cash, 'pass_pending') end
    if row.xp > 0 then exports.bs_core:AddXP(src, row.xp, 'pass_pending') end
end

-- Owned car, put away. The player brings it out from the pass menu.
local function grantCar(cid, model)
    if GetResourceState('bs_vehicles') ~= 'started' then return false end
    local plate = exports.bs_vehicles:GeneratePlate()
    local rec = plate and exports.bs_vehicles:TesterRegister(plate, model, cid)
    if not rec then return false end
    exports.bs_vehicles:AdminRemove(plate)  -- owned, so this stores it
    MySQL.insert.await('INSERT INTO `bs_pass_vehicles` (`char_id`,`plate`,`model`) VALUES (?,?,?)', { cid, plate, model })
    return plate
end

-- Delivers a list of rewards. src may be nil (offline). Returns a short text for the log and a mail flag.
function PS.Deliver(src, cid, list, tokensFn)
    local parts, mailed = {}, false
    for _, r in ipairs(list or {}) do
        local t = r.type
        if t == 'item' and r.item then
            local amount = math.max(1, math.floor(tonumber(r.amount) or 1))
            local given = 0
            if src then
                local before = exports.bs_inventory:CountItem(src, r.item) or 0
                exports.bs_inventory:GiveItem(src, r.item, amount)
                given = math.max(0, math.min(amount, (exports.bs_inventory:CountItem(src, r.item) or 0) - before))
            end
            if given < amount then toMail(cid, r.item, amount - given); mailed = true end
            parts[#parts + 1] = ('%s x%d'):format(r.item, amount)
        elseif t == 'cash' or t == 'xp' then
            local n = math.floor(tonumber(r.amount) or 0)
            if n > 0 then
                if src then
                    if t == 'cash' then exports.bs_core:AddMoney(src, 'cash', n, 'pass') else exports.bs_core:AddXP(src, n, 'pass') end
                else
                    addPending(cid, t == 'cash' and n or 0, t == 'xp' and n or 0)
                end
                parts[#parts + 1] = ('%s %d'):format(t, n)
            end
        elseif t == 'token' then
            local n = math.floor(tonumber(r.amount) or 1)
            if tokensFn then tokensFn(n) end
            parts[#parts + 1] = ('token %d'):format(n)
        elseif t == 'car' and r.model then
            local plate = grantCar(cid, r.model)
            if plate then parts[#parts + 1] = ('car %s [%s]'):format(r.model, plate)
            else toMail(cid, 'canned_food', 5); parts[#parts + 1] = 'car failed, consolation'; mailed = true end
        end
    end
    return table.concat(parts, ', '), mailed
end

-- Tier table: rotations from the config, single tiers replaced by data/tiers.json (F1 editor).
local custom = {}
local function loadCustom()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/tiers.json')
    local ok, t = pcall(json.decode, raw or '{}')
    custom = (ok and type(t) == 'table') and t or {}
end
loadCustom()

function PS.SaveCustom()
    SaveResourceFile(GetCurrentResourceName(), 'data/tiers.json', json.encode(custom), -1)
end

function PS.CustomTiers() return custom end

local function copy(list)
    local out = {}
    for i, r in ipairs(list or {}) do out[i] = { type = r.type, item = r.item, amount = r.amount, model = r.model } end
    return out
end

function PS.TierBase(t)
    local R, S = Pass.Rotation, Pass.Settings
    local list
    if t % 10 == 0 then
        list = copy(R.gear[math.min(#R.gear, t // 10)])
    elseif t % 2 == 0 then
        list = copy(R.cash[((t // 2) % #R.cash) + 1])
    else
        list = copy(R.supplies[((t // 2) % #R.supplies) + 1])
    end
    if t % (S.tokenEvery or 5) == 0 then list[#list + 1] = { type = 'token', amount = 1 } end
    return list
end

function PS.Tier(t)
    local c = custom[tostring(t)]
    if type(c) == 'table' then return copy(c) end
    return PS.TierBase(t)
end

-- Weighted pick, server side.
function PS.Pick(list)
    local total = 0
    for _, e in ipairs(list) do total = total + math.max(0, tonumber(e.w) or 0) end
    if total <= 0 then return list[1] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - math.max(0, tonumber(e.w) or 0)
        if r <= 0 then return e end
    end
    return list[#list]
end

-- One spin: three reels, then the pool. Odds come from Pass.Slot (F1 editable).
function PS.Spin()
    local syms = Pass.Slot.Symbols
    local reels = { PS.Pick(syms), PS.Pick(syms), PS.Pick(syms) }
    local a, b, c = reels[1].id, reels[2].id, reels[3].id
    local pool
    if a == b and b == c then pool = reels[1].pool
    elseif a == b or b == c or a == c then pool = 'pair'
    else pool = 'consolation' end
    local list = Pass.Slot.Pools[pool] or Pass.Slot.Pools.consolation
    local bundle = PS.Pick(list)
    return { a, b, c }, pool, copy(bundle and bundle.r or {})
end
