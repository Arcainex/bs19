-- bs_guard - money: bs_core has no server money hook

local G = GuardCore
local E = Guard.Economy
local last = {}      -- [src] = { charId, total }
local items = {}     -- [src] = { n, top = {item=amount} }

local function totalMoney(p)
    local a = type(p.accounts) == 'table' and p.accounts or {}
    return (tonumber(a.cash) or 0) + (tonumber(a.bank) or 0)
end

local function reportItem(src, item, amount)
    src, amount = tonumber(src), tonumber(amount) or 0
    if not src or amount <= 0 then return end
    local r = items[src] or { n = 0, top = {} }
    items[src] = r
    r.n = r.n + amount
    item = tostring(item or '?')
    r.top[item] = (r.top[item] or 0) + amount
end
exports('ReportItem', reportItem)
AddEventHandler('bs_guard:itemDelta', reportItem)

CreateThread(function()
    while true do
        Wait(E.pollMs or 60000)
        if Guard.Settings.enabled and E.enabled then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                local p = src and G.charInfo(src)
                if p and p.charId then
                    local total = totalMoney(p)
                    local l = last[src]
                    if l and l.charId == p.charId then
                        local gain = total - l.total
                        if gain > (E.moneyPerMinute or 25000) then
                            G.Flag(src, 'money', ('+%d money in ~%ds (now %d)'):format(gain, math.floor((E.pollMs or 60000) / 1000), total),
                                gain > (E.moneyPerMinute or 25000) * 4 and 85 or 60)
                        end
                    end
                    last[src] = { charId = p.charId, total = total }
                end
                local r = src and items[src]
                if r and r.n > (E.itemsPerMinute or 250) then
                    local best, bestN = '?', 0
                    for k, v in pairs(r.top) do if v > bestN then best, bestN = k, v end end
                    G.Flag(src, 'items', ('+%d items in a minute (most: %s x%d)'):format(r.n, best, bestN), 60)
                end
            end
            items = {}
        end
    end
end)

G.onDrop[#G.onDrop + 1] = function(src) last[src], items[src] = nil, nil end
