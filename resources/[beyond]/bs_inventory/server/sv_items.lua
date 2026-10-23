-- BeyondSurvival - bs_inventory: item definitions are synced from config into `bs_item_definitions` on start, so the database and config cannot drift. The definitions are the source of truth for weight, stack size and behaviour.

Items.Runtime = {}

CreateThread(function()
    while GetResourceState('bs_core') ~= 'started' do Wait(200) end
    Wait(1500)   -- let bs_core finish its migrations

    local count = 0
    for name, def in pairs(Items.Definitions) do
        Items.Runtime[name] = {
            name      = name,
            label     = def.label or name,
            category  = def.category or 'misc',
            weight    = def.weight or 0.5,
            stack     = def.stack or 1,
            usable    = def.usable or false,
            value     = def.value or 0,
            icon      = def.icon or name,
            data      = def.data or {},

            -- Items.Runtime (what Items.Get returns) now also carries size and body slot, which were previously dropped when the definition was copied.
            w         = def.w or 1,
            h         = def.h or 1,
            equipSlot = def.equipSlot,
        }

        exports.oxmysql:execute_async([[
            INSERT INTO `bs_item_definitions`
                (`name`, `label`, `category`, `weight`, `grid_w`, `grid_h`,
                 `stack_size`, `usable`, `base_value`, `icon`, `data`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `label` = VALUES(`label`), `category` = VALUES(`category`),
                `weight` = VALUES(`weight`), `stack_size` = VALUES(`stack_size`),
                `usable` = VALUES(`usable`), `base_value` = VALUES(`base_value`),
                `data` = VALUES(`data`)
        ]], {
            name, def.label or name, def.category or 'misc', def.weight or 0.5,
            def.w or 1, def.h or 1, def.stack or 1, def.usable and 1 or 0,
            def.value or 0, def.icon or name, json.encode(def.data or {}),
        })
        count = count + 1
    end

    print(('^2[BeyondSurvival]^7 (inventory) %d item definitions synced'):format(count))
end)

function Items.Get(name) return Items.Runtime[name] end

-- Item names and descriptions in a player's language (server default without src).
-- Locale keys item.<name> and item.<name>.desc, config label as the English fallback.
local function itemText(src, name, suffix, fallback)
    local key = 'item.' .. tostring(name) .. (suffix or '')
    local text = src and Lp(src, key) or L(key)
    if text ~= key then return text end
    return fallback
end

function ItemLabel(name, src)
    local def = Items.Runtime[name] or Items.Definitions[name]
    return itemText(src, name, nil, def and def.label or tostring(name))
end

function ItemDescription(name, src)
    local def = Items.Definitions[name]
    return itemText(src, name, '.desc', def and (def.description or def.desc) or nil)
end

exports('ItemLabel', function(name, src) return ItemLabel(name, tonumber(src)) end)
exports('ItemDescription', function(name, src) return ItemDescription(name, tonumber(src)) end)

exports('GetItem', function(name) return Items.Runtime[name] end)
exports('GetItems', function() return Items.Runtime end)

-- Returns the inventory item for a weapon model, or nil. Exported because Items.Definitions lives in this resource's Lua state; bs_admin uses it to put a spawned weapon in the bag.
exports('ItemForWeapon', function(model)
    if type(model) ~= 'string' then return nil end
    for name, def in pairs(Items.Definitions or {}) do
        if def.data and def.data.weapon == model then return name end
    end
    return nil
end)

-- Service contract (see bs_core/shared/sh_services.lua). Declares what this resource offers so a consumer asking for something missing finds out at the call site instead of getting nil.
if BS and BS.Provide then
    BS.Provide('inventory', {
        'GiveItem', 'RemoveItem', 'CountItem', 'Refresh',
        'WipeInventory', 'ItemForWeapon', 'RegisterContainer', 'ContainerHasItems',
    })
end
