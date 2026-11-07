-- bs_inventory - the five hotbar slots hold the actual items.
-- The bar is slots 41-45 of the same inventory (see BAR_SLOTS in sv_main.lua), not a second store. Moving an item onto the bar is the normal inventory move, so stacking, durability, fill level, weight and saving all apply. This file only tells the client what is in those slots and fires one of them.
-- The old name-based bindings in character metadata are cleared on first load, not migrated, since a name cannot say which bandage.

local MAX_SLOTS = 5

-- Where bar slot `index` lives in the inventory. One function so the arithmetic exists once.
local function slotFor(inv, index)
    return (inv.gridSlots or inv.size) + index
end

-- Clears the old name-only bindings once per character, so unused metadata does not confuse anyone later.
local cleared = {}

local function clearLegacy(src)
    if cleared[src] then return end
    cleared[src] = true

    pcall(function()
        local stored = exports.bs_core:GetPlayerMeta(src, 'hotbar', nil)
        if type(stored) == 'table' and next(stored) then
            exports.bs_core:SetPlayerMeta(src, 'hotbar', nil)
        end
    end)
end

AddEventHandler('playerDropped', function() cleared[source] = nil end)

-- What the client draws, straight from the inventory slots, so stack counts, tool wear and can fill levels are always accurate.
function Hotbar.Payload(src)
    local out = {}

    local inv = Inv.Of and Inv.Of(src)
    if not inv then
        for index = 1, MAX_SLOTS do out[tostring(index)] = false end
        return out
    end

    clearLegacy(src)

    for index = 1, MAX_SLOTS do
        local entry = inv.slots[slotFor(inv, index)]
        local key = tostring(index)

        -- Keyed by string, never by number: a Lua table keyed 1..5 serialises as a JSON array and JS arrays are 0-indexed, which shifts every reader by one.
        if entry then
            local def = Items.Get(entry.item) or {}

            out[key] = {
                item = entry.item,
                label = ItemLabel(entry.item, src),
                category = def.category or 'misc',
                count = entry.amount or 1,
                durability = entry.durability,
                maxDurability = def.data and tonumber(def.data.durability) or nil,
                -- A measured container shows its level rather than its count, like in the bag.
                fill = def.data and def.data.capacity and (entry.durability or 0) or nil,
                capacity = def.data and def.data.capacity or nil,
                empty = false,
            }
        else
            out[key] = false
        end
    end

    return out
end

local function fourCarriedWeapons(src)
    local result = {}
    local inv = Inv.Of and Inv.Of(src)
    if not inv then return result end
    for index = 1, 4 do
        local entry = inv.slots[slotFor(inv, index)]
        if entry and (entry.amount or 1) > 0 then
            local def = Items.Get(entry.item)
            local model = def and def.data and def.data.weapon
            if def and def.category == 'weapon'
                and type(model) == 'string' and model:sub(1, 7) == 'WEAPON_' then
                result[tostring(index)] = model
            end
        end
    end
    return result
end

-- Carry editor consumes exact inventory item IDs for each physical weapon slot.
-- Keeping indices allows two copies of the same item to display separately.
exports('WeaponCarryHotbarSlotItems', function(src)
    local out = {}
    local inv = Inv.Of and Inv.Of(src)
    if not inv then return out end
    for index = 1, 4 do
        local entry = inv.slots[slotFor(inv, index)]
        local def = entry and Items.Get(entry.item)
        if def and def.category == 'weapon' and (entry.amount or 1) > 0 then
            out[tostring(index)] = entry.item
        end
    end
    return out
end)

function Hotbar.Push(src)
    TriggerClientEvent('bs:hotbar:state', src, Hotbar.Payload(src))
    -- Replicated state is consumed by nearby clients to render every weapon
    -- on its OWN physical body slot (spine / spine / left belt / right belt).
    local player = Player(src)
    if player then player.state:set('alphaZCarriedWeapons', fourCarriedWeapons(src), true) end
end

-- Called by Inv.Wipe (sv_main.lua). There are no bindings to clear; this just makes the client redraw an empty bar.
function Hotbar.Wipe(src)
    Hotbar.Push(src)
end

-- Firing a slot
-- No hotbar:set / hotbar:swap: putting something on the bar is an ordinary inventory move between two slots, so there is only one way to move an item.

BSB.RegisterCallback('hotbar:use', function(src, index)
    index = math.floor(tonumber(index) or 0)
    if index < 1 or index > MAX_SLOTS then return { ok = false } end

    local inv = Inv.Of and Inv.Of(src)
    if not inv then return { ok = false } end

    local slot = slotFor(inv, index)
    local entry = inv.slots[slot]

    if not entry then return { ok = false, error = 'nothing there' } end

    -- The slot is unambiguous: the item in the slot is the item used. No lookup by name, so pressing 2 cannot pick a different stack than the one the bar shows.
    local def = Items.Get(entry.item)
    local weapon = def and def.data and def.data.weapon or nil

    if type(weapon) == 'string' and GetResourceState('bs_weapons') == 'started' then
        pcall(function() exports.bs_weapons:SetActive(src, weapon, slot) end)
    end

    return { ok = true, slot = slot, item = entry.item, weapon = weapon }
end)

BSB.RegisterCallback('hotbar:get', function(src)
    return { ok = true, slots = Hotbar.Payload(src) }
end)

RegisterCommand('hotbardebug', function(src)
    if src == 0 then return print('^3[BS INVENTORY]^7 run this in-game, not from the console.') end

    local inv = Inv.Of and Inv.Of(src)
    if not inv then return end

    print(('^5[BS INVENTORY]^7 --- bar, inventory slots %d-%d, server truth ---')
        :format(slotFor(inv, 1), slotFor(inv, MAX_SLOTS)))

    for index = 1, MAX_SLOTS do
        local entry = inv.slots[slotFor(inv, index)]
        print(('  slot %d (inv %d): %s x%s'):format(
            index, slotFor(inv, index),
            entry and entry.item or 'empty',
            entry and tostring(entry.amount) or '-'))
    end

    TriggerClientEvent('bs:ui:notify', src, {
        type = 'info', message = Lp(src, 'inv.bar_printed'), duration = 3000,
    })
end, false)

-- The bar follows the bag because it is the bag: any inventory push redraws it. This only covers the first draw after spawning.
AddEventHandler('bs:hook:player:spawned', function(player)
    if player and player.source then
        CreateThread(function()
            Wait(1500)
            Hotbar.Push(player.source)
        end)
    end
end)

-- Alpha-Z Weapon Carry: authoritative items in the five physical hotbar slots.
-- Read-only export; does not alter inventory or hotbar behaviour.
exports('WeaponCarryHotbarItems', function(src)
    local result = {}
    local inv = Inv.Of and Inv.Of(src)
    if not inv then return result end
    for index = 1, MAX_SLOTS do
        local entry = inv.slots[slotFor(inv, index)]
        if entry and type(entry.item) == 'string' and (entry.amount or 1) > 0 then
            result[entry.item] = true
        end
    end
    return result
end)

-- Alpha-Z character selection: read saved HOTBAR items from the selected
-- character's inventory, without loading that character into a session.
-- Call only from a server resource which has verified character ownership.
exports('WeaponCarryCharacterPreviewItems', function(charId)
    local id = tonumber(charId)
    if not id or id < 1 or id % 1 ~= 0 then return {} end
    local rows = exports.oxmysql:query_async([[
        SELECT ii.`item`, ii.`slot_x`
          FROM `bs_inventory_items` ii
          JOIN `bs_inventories` inv ON inv.`id` = ii.`inventory_id`
         WHERE inv.`owner_type` = 'character'
           AND inv.`owner_id` = ?
           AND ii.`slot_x` BETWEEN 41 AND 44
         ORDER BY ii.`slot_x` ASC
         LIMIT 4
    ]], { tostring(id) }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        if type(row.item) == 'string' and #row.item <= 80 then
            result[#result+1] = row.item
        end
    end
    return result
end)

-- Optional structured export for character-selection resources: all four slots,
-- without collapsing weapons of the same type/name. Ownership must be checked
-- by the calling resource before requesting a character ID.
exports('WeaponCarryCharacterPreviewSlots', function(charId)
    local id = tonumber(charId)
    if not id or id < 1 or id % 1 ~= 0 then return {} end
    local rows = exports.oxmysql:query_async([[
        SELECT ii.`item`, ii.`slot_x`
          FROM `bs_inventory_items` ii
          JOIN `bs_inventories` inv ON inv.`id` = ii.`inventory_id`
         WHERE inv.`owner_type` = 'character'
           AND inv.`owner_id` = ?
           AND ii.`slot_x` BETWEEN 41 AND 44
         ORDER BY ii.`slot_x` ASC LIMIT 4
    ]], { tostring(id) }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local def = Items.Get(row.item)
        if def and def.category == 'weapon' and def.data and type(def.data.weapon) == 'string' then
            out[tostring(tonumber(row.slot_x) - 40)] = def.data.weapon
        end
    end
    return out
end)

-- Character-selection server code MUST verify ownership of charId before using this export.
-- Returns slot numbers 1..4 -> inventory item ID, preserving belt-left/right exactly.
exports('WeaponCarryCharacterPreviewSlotItems', function(charId)
    local id = tonumber(charId)
    if not id or id < 1 or id % 1 ~= 0 then return {} end
    local rows = exports.oxmysql:query_async([[
        SELECT ii.`item`, ii.`slot_x`
          FROM `bs_inventory_items` ii
          JOIN `bs_inventories` inv ON inv.`id` = ii.`inventory_id`
         WHERE inv.`owner_type` = 'character' AND inv.`owner_id` = ?
           AND ii.`slot_x` BETWEEN 41 AND 44
         ORDER BY ii.`slot_x` ASC LIMIT 4
    ]], { tostring(id) }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        local def = Items.Get(row.item)
        local n = tonumber(row.slot_x)
        if n and def and def.category == 'weapon' then
            result[tostring(n - 40)] = row.item
        end
    end
    return result
end)
