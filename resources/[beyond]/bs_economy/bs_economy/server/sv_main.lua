-- bs_economy - loot tables, vendor stock and prices. Server side only.

-- Read-only access to a loot table, for bs_interactions' container rolls.
exports('GetLootTable', function(id) return Economy.GetLootTable(id) end)

--- Rolls a table server-side and returns the resulting item list.
exports('RollLoot', function(id)
    local tbl = Economy.GetLootTable(id)
    if not tbl then return {} end

    local rolls = math.random(tbl.rolls and tbl.rolls.min or 0, tbl.rolls and tbl.rolls.max or 1)
    local out = {}

    for _ = 1, rolls do
        local total = 0
        for _, entry in ipairs(tbl.entries or {}) do total = total + (entry.weight or 0) end
        if total <= 0 then break end

        local pick, acc = math.random() * total, 0
        for _, entry in ipairs(tbl.entries) do
            acc = acc + (entry.weight or 0)
            if pick <= acc then
                out[#out + 1] = {
                    item = entry.item,
                    amount = math.random(entry.amount and entry.amount[1] or 1,
                                         entry.amount and entry.amount[2] or 1),
                }
                break
            end
        end
    end
    return out
end)

exports.bs_core:RegisterModule('economy', { side = 'server', version = '0.2.0' })
