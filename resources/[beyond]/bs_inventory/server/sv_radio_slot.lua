local SLOT = 921
local T = Inv.TradeInternals
local radios = { radio = true, radio_advanced = true, radio_military = true }
local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = clone(child) end
    return out
end

exports('EquippedRadio',function(src)
    local snapshot=Inv.RadioSnapshot(tonumber(src))
    return snapshot and snapshot.radio or nil
end)

BSB.RegisterCallback('inventory:radioSlot', function(src, sourceSlot)
    sourceSlot = math.tointeger(tonumber(sourceSlot))
    if not sourceSlot then return { ok = false, error = 'Invalid radio slot.' } end
    local inv, player = T.of(src)
    if not inv or not player or Inv.TradeLock[src] or Inv.TradeLockedOwner[tostring(player.charId)]
        or T.pending(inv) > 0 then return { ok = false, error = 'Inventory is busy.' } end
    local owner = tostring(player.charId)
    Inv.MutationOwners = Inv.MutationOwners or {}
    if Inv.MutationOwners[owner] then return { ok = false, error = 'Inventory is busy.' } end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then return { ok = false, error = 'You cannot change equipment now.' } end
    Inv.MutationOwners[owner] = true
    local ok, result = pcall(function()
        local draft = clone(inv)
        local incoming = sourceSlot ~= 0 and draft.slots[sourceSlot] or nil
        if sourceSlot ~= 0 then
            local inBag = T.isBag(inv, sourceSlot)
            local inBar = sourceSlot > inv.gridSlots and sourceSlot <= inv.gridSlots + 5
            if not incoming or not radios[incoming.item] or incoming.amount ~= 1 or not (inBag or inBar) then
                return { ok = false, error = 'Choose a radio from your bag or quick bar.' }
            end
        end
        local worn = draft.slots[SLOT]
        if sourceSlot == 0 and not worn then return { ok = true } end
        if worn and not radios[worn.item] then return { ok = false, error = 'The equipment slot needs repair.' } end
        local changed = { [SLOT] = true }
        if incoming then draft.slots[sourceSlot] = nil; changed[sourceSlot] = true end
        draft.slots[SLOT] = nil
        if worn then
            local free
            for _, slot in ipairs(T.bagSlots(draft)) do if not draft.slots[slot] then free = slot; break end end
            if not free then return { ok = false, error = 'Make room in your bag before removing the radio.' } end
            local def = Items.Get(worn.item)
            local x, y, rot = Grid.FirstFit(T.gridBounds(draft), T.gridEntries(draft), { id = free, w = def.w or 1, h = def.h or 1 }, true)
            if not x then return { ok = false, error = 'Make room in your bag before removing the radio.' } end
            worn.slot, worn.x, worn.y, worn.rot = free, x, y, rot
            draft.slots[free] = worn
            changed[free] = true
        end
        if incoming then
            incoming.slot, incoming.x, incoming.y, incoming.rot = SLOT, nil, nil, false
            draft.slots[SLOT] = incoming
        end
        local queries = {}
        for slot in pairs(changed) do
            queries[#queries + 1] = { query = 'DELETE FROM bs_inventory_items WHERE inventory_id = ? AND slot_x = ?', values = { inv.id, slot } }
            local entry = draft.slots[slot]
            if entry then
                queries[#queries + 1] = {
                    query = 'INSERT INTO bs_inventory_items (inventory_id,item,amount,slot_x,slot_y,grid_x,grid_y,rotated,durability,metadata) VALUES (?,?,?,?,0,?,?,?,?,?)',
                    values = { inv.id, entry.item, entry.amount, slot, entry.x or 0, entry.y or 0, entry.rot and 1 or 0, entry.durability, json.encode(entry.metadata or {}) },
                }
            end
        end
        if not MySQL.transaction.await(queries) then return { ok = false, error = 'Could not save radio equipment.' } end
        T.evict(player.charId)
        return { ok = true }
    end)
    Inv.MutationOwners[owner] = nil
    if not ok then
        print(('[bs_inventory] radio equipment failed for %s: %s'):format(owner, tostring(result)))
        return { ok = false, error = 'Could not save radio equipment.' }
    end
    if result.ok then Inv.Push(src); TriggerEvent('bs:radio:equipmentChanged', src) end
    return result
end)
