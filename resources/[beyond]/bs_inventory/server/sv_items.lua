-- BeyondSurvival - bs_inventory: item definitions are synced from config into `bs_item_definitions` on start, so the database and config cannot drift. The definitions are the source of truth for weight, stack size and behaviour.

Items.Runtime = {}

-- ALPHA-Z F10 food editor. Config remains authoritative for built-in item IDs;
-- only food/drink fields are overlaid. Custom food IDs are persisted separately.
local RES = GetCurrentResourceName()
local FOOD_FILE = 'data/foods.json'
local baseFood = {}
local foodOverrides = {}
local itemsReady = false

local function clone(t)
    local o = {}
    for k, v in pairs(t or {}) do
        if type(v) == 'table' then o[k] = clone(v) else o[k] = v end
    end
    return o
end

for id, def in pairs(Items.Definitions) do
    if def.category == 'food' or def.category == 'drink' then baseFood[id] = clone(def) end
end

local function validFoodId(id)
    return type(id) == 'string' and #id >= 2 and #id <= 48
        and id:match('^[a-z][a-z0-9_]*$') ~= nil
end

local function applyFood(id, fields)
    local base = baseFood[id]
    if not base and Items.Definitions[id] and not foodOverrides[id] then return false end
    local def = base and clone(base) or {
        label = id, category = 'food', usable = true, value = 0,
        data = {}, w = 1, h = 1,
    }
    def.label = fields.label
    def.weight = fields.weight
    def.stack = fields.stack
    def.icon = fields.icon
    def.value = fields.value
    def.data = def.data or {}
    -- Lua treats 0 as truthy; omit empty effects so water uses the drink animation.
    def.data.hunger = fields.hunger > 0 and fields.hunger or nil
    def.data.thirst = fields.thirst > 0 and fields.thirst or nil
    def.usable = true
    Items.Definitions[id] = def
    if itemsReady then
        -- Other inventory functions read Items.Get(), so update this same runtime table.
        Items.Runtime[id] = {
            name = id, label = def.label, category = def.category,
            weight = def.weight, stack = def.stack, usable = def.usable,
            value = def.value, icon = def.icon, data = clone(def.data),
            w = 1, h = 1, equipSlot = def.equipSlot,
            description = def.description,
        }
    end
    return true
end

local function runtimeDef(id, def)
    return {
        name = id, label = def.label or id, category = def.category or 'misc',
        weight = def.weight or 0.5, stack = def.stack or 1,
        usable = def.usable or false, value = def.value or 0,
        icon = def.icon or id, data = def.data or {},
        w = def.w or 1, h = def.h or 1, equipSlot = def.equipSlot,
        description = def.description,
    }
end

local function foodRecord(id, def)
    local data = def.data or {}
    return {
        id = id, label = def.label or id, category = def.category,
        weight = def.weight or 0.5, stack = def.stack or 1,
        icon = def.icon or id, value = def.value or 0,
        hunger = tonumber(data.hunger) or 0, thirst = tonumber(data.thirst) or 0,
        edited = foodOverrides[id] ~= nil, custom = baseFood[id] == nil,
    }
end

local function readFoods()
    local raw = LoadResourceFile(RES, FOOD_FILE)
    local ok, loaded = pcall(json.decode, raw or '')
    if not ok or type(loaded) ~= 'table' then return end
    for id, data in pairs(loaded) do
        if validFoodId(id) and type(data) == 'table'
            and (baseFood[id] or not Items.Definitions[id]) then
            foodOverrides[id] = data
            applyFood(id, data)
        end
    end
end
readFoods()

local function upsertFoodDb(id, def)
    return MySQL.update.await([[
        INSERT INTO `bs_item_definitions`
            (`name`,`label`,`category`,`weight`,`grid_w`,`grid_h`,
             `stack_size`,`usable`,`base_value`,`icon`,`data`)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
            `label`=VALUES(`label`),`category`=VALUES(`category`),
            `weight`=VALUES(`weight`),`grid_w`=VALUES(`grid_w`),`grid_h`=VALUES(`grid_h`),
            `stack_size`=VALUES(`stack_size`),`usable`=VALUES(`usable`),
            `base_value`=VALUES(`base_value`),`icon`=VALUES(`icon`),`data`=VALUES(`data`)
    ]], { id, def.label or id, def.category or 'food', def.weight or 0.5,
        1, 1, def.stack or 1, def.usable and 1 or 0, def.value or 0,
        def.icon or id, json.encode(def.data or {}) })
end

local function pushFoodClients(id)
    TriggerClientEvent('bs:inventory:foodDef', -1, id, Items.Definitions[id], foodOverrides[id] ~= nil)
end

-- Client receives item labels/description for definitions added while running.
RegisterNetEvent('bs:inventory:foodSync', function()
    local src = source
    if not itemsReady then return end
    for id in pairs(foodOverrides) do
        TriggerClientEvent('bs:inventory:foodDef', src, id, Items.Definitions[id], true)
    end
    TriggerClientEvent('bs:inventory:foodSyncDone', src)
end)

local function foodAdmin(src)
    return GetResourceState('bs_admin') == 'started'
        and exports.bs_admin:IsAdmin(tonumber(src) or -1)
end

exports('FoodEditor', function(src, action, payload)
    if not foodAdmin(src) then return { ok = false, error = 'Keine Admin-Berechtigung.' } end
    if not itemsReady then return { ok = false, error = 'Inventar wird noch geladen.' } end
    if action == 'list' then
        local rows = {}
        for id, def in pairs(Items.Runtime) do
            if (def.category == 'food' or def.category == 'drink')
                and (def.usable or foodOverrides[id]) then rows[#rows + 1] = foodRecord(id, def) end
        end
        table.sort(rows, function(a, b) return (a.label or '') < (b.label or '') end)
        return { ok = true, foods = rows }
    end
    local id = type(payload) == 'table' and payload.id or nil
    if not validFoodId(id) then return { ok = false, error = 'Ungültige Item-ID (a-z, 0-9, _).' } end
    if action == 'save' then
        if Items.Definitions[id] and not baseFood[id] and not foodOverrides[id] then
            return { ok = false, error = 'Diese Item-ID gehört bereits zu einem anderen Item.' }
        end
        local d = payload
        local label = type(d.label) == 'string' and d.label:match('^%s*(.-)%s*$') or ''
        local weight = tonumber(d.weight)
        local stack = tonumber(d.stack)
        local hunger = tonumber(d.hunger)
        local thirst = tonumber(d.thirst)
        local value = tonumber(d.value)
        local icon = type(d.icon) == 'string' and d.icon or ''
        if #label < 2 or #label > 60 or not weight or weight < 0.01 or weight > 25
            or not stack or stack ~= math.floor(stack) or stack < 1 or stack > 100
            or not hunger or hunger < 0 or hunger > 100
            or not thirst or thirst < 0 or thirst > 100
            or not value or value < 0 or value > 10000
            or not icon:match('^[a-zA-Z0-9_]+$') or #icon > 64
            or (not Items.Definitions[icon] and icon ~= id) then
            return { ok = false, error = 'Ungültige Lebensmittelwerte. Prüfe Name, Gewicht, Stapel und Effekte.' }
        end
        local fields = { label = label, weight = weight, stack = stack, hunger = hunger,
            thirst = thirst, value = math.floor(value), icon = icon }
        local nextOverrides = clone(foodOverrides)
        nextOverrides[id] = fields
        if not SaveResourceFile(RES, FOOD_FILE, json.encode(nextOverrides, { indent = true }), -1) then
            return { ok = false, error = 'Konnte data/foods.json nicht speichern.' }
        end
        local oldDef = Items.Definitions[id]
        local oldRuntime = Items.Runtime[id]
        local oldOverride = foodOverrides[id]
        foodOverrides[id] = fields
        applyFood(id, fields)
        local okDb, dbError = pcall(upsertFoodDb, id, Items.Definitions[id])
        if not okDb then
            foodOverrides[id] = oldOverride
            Items.Definitions[id] = oldDef
            Items.Runtime[id] = oldRuntime
            local rollback = clone(nextOverrides); rollback[id] = oldOverride
            SaveResourceFile(RES, FOOD_FILE, json.encode(rollback, { indent = true }), -1)
            print('[bs_inventory] F10 food DB error: ' .. tostring(dbError))
            return { ok = false, error = 'Datenbankfehler. Änderung zurückgenommen.' }
        end
        pushFoodClients(id)
        print(('[bs_inventory] F10 food saved: %s by %s'):format(id, GetPlayerName(src) or src))
        return { ok = true }
    elseif action == 'delete' then
        if baseFood[id] then
            return { ok = false, error = 'Original-Items sind geschützt. Anpassungen können zurückgesetzt werden.' }
        end
        if not foodOverrides[id] then
            return { ok = false, error = 'Dieses Item wurde nicht über den F10-Lebensmittel-Editor erstellt.' }
        end
        -- Check recipes first. Never leave a live recipe with a missing ingredient/output.
        if GetResourceState('bs_crafting') ~= 'started' then
            return { ok = false, error = 'bs_crafting läuft nicht. Löschen zur Sicherheit abgebrochen.' }
        end
        local craftOk, referenced = pcall(function()
            return exports.bs_crafting:ItemInRecipes(id)
        end)
        if not craftOk then
            return { ok = false, error = 'Rezeptprüfung fehlgeschlagen. Löschen zur Sicherheit abgebrochen.' }
        end
        if referenced then
            return { ok = false, error = 'Wird noch in Rezept "' .. tostring(referenced) .. '" verwendet. Rezept zuerst entfernen oder ändern.' }
        end
        local pendingOk, pending = pcall(function()
            return exports.bs_crafting:ItemInPendingCraft(id)
        end)
        if not pendingOk then
            return { ok = false, error = 'Laufende Crafting-Aufträge konnten nicht geprüft werden.' }
        end
        if pending then
            return { ok = false, error = 'Das Item wird noch hergestellt (' .. tostring(pending) .. '). Erst fertigstellen.' }
        end
        local free, reason = Inv.FoodDeletionSafety(id)
        if not free then return { ok = false, error = reason } end
        local queryOk, stock = pcall(function()
            return MySQL.scalar.await('SELECT COUNT(*) FROM `bs_inventory_items` WHERE `item` = ?', { id })
        end)
        if not queryOk then
            return { ok = false, error = 'Inventarprüfung der Datenbank fehlgeschlagen. Löschen abgebrochen.' }
        end
        if tonumber(stock) == nil then
            return { ok = false, error = 'Inventarprüfung lieferte kein Ergebnis. Löschen abgebrochen.' }
        end
        if tonumber(stock) > 0 then
            return { ok = false, error = 'Noch ' .. tostring(stock) .. ' Inventarstapel vorhanden. Erst aufbrauchen oder entfernen.' }
        end
        -- Safeguard against an in-flight inventory update while the database query runs.
        free, reason = Inv.FoodDeletionSafety(id)
        if not free then return { ok = false, error = reason } end
        local nextOverrides = clone(foodOverrides)
        nextOverrides[id] = nil
        local encoded = json.encode(nextOverrides, { indent = true })
        -- Persist the new authoritative file first, restore it if DB delete fails.
        if not SaveResourceFile(RES, FOOD_FILE, encoded, -1) then
            return { ok = false, error = 'foods.json konnte nicht gespeichert werden.' }
        end
        local dbOk, dbErr = pcall(function()
            MySQL.update.await('DELETE FROM `bs_item_definitions` WHERE `name` = ?', { id })
        end)
        if not dbOk then
            SaveResourceFile(RES, FOOD_FILE, json.encode(foodOverrides, { indent = true }), -1)
            print('[bs_inventory] F10 food delete DB error: ' .. tostring(dbErr))
            return { ok = false, error = 'Datenbankfehler. Item bleibt erhalten.' }
        end
        foodOverrides[id] = nil
        Items.Runtime[id] = nil
        Items.Definitions[id] = nil
        TriggerClientEvent('bs:inventory:foodRemoved', -1, id)
        print(('[bs_inventory] F10 food deleted: %s by %s'):format(id, GetPlayerName(src) or src))
        return { ok = true }
    elseif action == 'reset' then
        if not baseFood[id] then return { ok = false, error = 'Neue Items können nicht zurückgesetzt werden (bestehende Inventare schützen).' } end
        if not foodOverrides[id] then return { ok = false, error = 'Keine Anpassung vorhanden.' } end
        local nextOverrides = clone(foodOverrides); nextOverrides[id] = nil
        if not SaveResourceFile(RES, FOOD_FILE, json.encode(nextOverrides, { indent = true }), -1) then
            return { ok = false, error = 'Konnte data/foods.json nicht speichern.' }
        end
        local oldDef, oldRuntime, oldOverride = Items.Definitions[id], Items.Runtime[id], foodOverrides[id]
        foodOverrides[id] = nil
        Items.Definitions[id] = clone(baseFood[id])
        Items.Runtime[id] = runtimeDef(id, Items.Definitions[id])
        local okDb, dbError = pcall(upsertFoodDb, id, Items.Definitions[id])
        if not okDb then
            foodOverrides[id] = oldOverride
            Items.Definitions[id], Items.Runtime[id] = oldDef, oldRuntime
            SaveResourceFile(RES, FOOD_FILE, json.encode(foodOverrides, { indent = true }), -1)
            print('[bs_inventory] F10 food DB reset error: ' .. tostring(dbError))
            return { ok = false, error = 'Datenbankfehler. Änderung zurückgenommen.' }
        end
        pushFoodClients(id)
        return { ok = true }
    end
    return { ok = false, error = 'Unbekannte Lebensmittelaktion.' }
end)

CreateThread(function()
    while GetResourceState('bs_core') ~= 'started' do Wait(200) end
    Wait(1500)   -- let bs_core finish its migrations

    local count = 0
    for name, def in pairs(Items.Definitions) do
        -- Alpha-Z inventory presentation: always one cell; no effect on weight or
        -- on backpack/vest inner containers.
        def.w, def.h = 1, 1
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
            description = def.description,
        }

        exports.oxmysql:execute_async([[
            INSERT INTO `bs_item_definitions`
                (`name`, `label`, `category`, `weight`, `grid_w`, `grid_h`,
                 `stack_size`, `usable`, `base_value`, `icon`, `data`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `label` = VALUES(`label`), `category` = VALUES(`category`),
                `weight` = VALUES(`weight`), `grid_w` = VALUES(`grid_w`), `grid_h` = VALUES(`grid_h`),
                `stack_size` = VALUES(`stack_size`), `usable` = VALUES(`usable`),
                `base_value` = VALUES(`base_value`), `icon` = VALUES(`icon`), `data` = VALUES(`data`)
        ]], {
            name, def.label or name, def.category or 'misc', def.weight or 0.5,
            def.w or 1, def.h or 1, def.stack or 1, def.usable and 1 or 0,
            def.value or 0, def.icon or name, json.encode(def.data or {}),
        })
        count = count + 1
    end

    itemsReady = true
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
    if foodOverrides[name] and def then return def.label end
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
