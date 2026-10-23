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

function Hotbar.Push(src)
    TriggerClientEvent('bs:hotbar:state', src, Hotbar.Payload(src))
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
