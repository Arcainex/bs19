-- bs_inventory - server authority on what anyone carries. The client asks and is told; every move is re-validated against real rows, weight is checked against the class carry limit, containers are shared.

Inv = {}
local cache = {}        -- [invKey] = { id, ownerType, ownerId, slots = {}, maxWeight, size }
Inv.TradeLock = {}      -- A live trade freezes ordinary inventory changes.
Inv.TradeLockedOwner = {} -- Character lock also survives a source-id reconnect.
local pendingWrites = {} -- Outstanding slot writes must settle before a trade commits.
local openContainers = {}  -- [src] = invKey the player currently has open
local openedAt = {}        -- [src] = { pos = vector3, bagId = string|nil } where/what that open was
local containerGrants = {} -- [src] = { [containerId] = { expires = ms, pos = vector3 } }
local GRANT_TTL = 10000     -- a grant is only good for the open it was issued for
local CONTAINER_REACH = 5.0 -- step further than this (m) and the container is out of reach

-- Deep copy so a split stack or a world drop never shares a table with its source.
local function copyTable(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copyTable(v) end
    return out
end

-- Who may open what: the server side that decided an open was legitimate (boot unlocked, stash owned, bag worn) grants it here, for that player, briefly, at where they stand.
local function grantContainer(src, containerId)
    src = tonumber(src)
    if not src or type(containerId) ~= 'string' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    containerGrants[src] = containerGrants[src] or {}
    containerGrants[src][containerId] = { expires = GetGameTimer() + GRANT_TTL, pos = GetEntityCoords(ped) }
    return true
end

-- Container specs are registered server-side. Size and max weight come from the registry, never from client arguments.
local containerSpecs = {}  -- [containerId] = { size, maxWeight, label }

exports('RegisterContainer', function(containerId, spec, src)
    if type(containerId) ~= 'string' or #containerId > 64 then return false end
    -- An optional third argument grants the open to that player in the same call.
    if src then grantContainer(src, containerId) end
    spec = spec or {}

    -- A container has its own grid size (width/height in its spec). Do not use the player's 8x5 for every inventory.
    local w = tonumber(spec.width)
    local h = tonumber(spec.height)
    local size = tonumber(spec.size)

    if not w or not h then
        size = math.max(1, math.min(200, size or 40))
        w = math.max(1, math.min(12, math.ceil(math.sqrt(size))))
        h = math.max(1, math.ceil(size / w))
    end

    w = math.max(1, math.min(12, math.floor(w)))
    h = math.max(1, math.min(20, math.floor(h)))

    containerSpecs[containerId] = {
        width = w, height = h,
        size      = w * h,
        maxWeight = math.max(1.0, math.min(500.0, tonumber(spec.maxWeight) or 100.0)),
        label     = type(spec.label) == 'string' and spec.label:sub(1, 48) or 'Container',
        compact   = spec.compact == true,  -- panel shows only the rows in use
    }
    return true
end)

exports('GrantContainer', grantContainer)

-- Grant and open in one step, for resources that own a container.
exports('OpenContainerFor', function(src, containerId)
    if not containerSpecs[containerId] then return false end
    if not grantContainer(src, containerId) then return false end
    TriggerClientEvent('bs:inventory:openContainer', src, containerId)
    return true
end)

local function key(ownerType, ownerId) return ('%s:%s'):format(ownerType, ownerId) end

-- Stack ids 1-40 (+ extra ids 101-199) are the bag, then the bar and equipment. This stays at the
-- old 8x5 layout on purpose: the grid size is only cells now, so a bigger or F1-changed grid never
-- renumbers the bar or equipment in saved inventories.
local SLOT_BASE = 40
local function slotCount()
    return SLOT_BASE
end

-- The hotbar is 5 more slots of the same inventory, so bar items are real stacks with weight and metadata instead of name references.
local BAR_SLOTS = 5

local function barFrom() return slotCount() + 1 end

-- Equipment is more slots of the same inventory, so worn items have weight, can be looted and share the same stacking and persistence. A character inventory is three regions of one array: bag, bar, equipment.
local function equipCount() return Clothing and Clothing.Count() or 0 end
local function equipFrom() return slotCount() + BAR_SLOTS + 1 end
local function playerSize() return slotCount() + BAR_SLOTS + equipCount() end

-- Which equipment slot a given inventory index is, or nil if it is bag/bar.
local function equipSlotAt(slot)
    if not Clothing then return nil end
    local offset = slot - equipFrom() + 1
    if offset < 1 then return nil end
    return Clothing.Slots[offset]
end

-- Extra bag ids (101-199) so a bigger grid is not capped at 40 stacks.
-- Loadout ids (901+) hold boosters/gadgets off the grid; weight still counts.
local EXTRA_FROM, EXTRA_TO = 101, 199
local LOADOUT = { booster = { from = 901, count = 3 }, gadget = { from = 911, count = 2 } }

local function isBagSlot(inv, slot)
    if slot >= 1 and slot <= (inv.gridSlots or inv.size) then return true end
    return inv.ownerType == 'character' and inv.gridSlots ~= nil
        and slot >= EXTRA_FROM and slot <= EXTRA_TO
end

local function bagSlotList(inv)
    local out = {}
    for s = 1, (inv.gridSlots or inv.size) do out[#out + 1] = s end
    if inv.ownerType == 'character' and inv.gridSlots then
        for s = EXTRA_FROM, EXTRA_TO do out[#out + 1] = s end
    end
    return out
end

-- Any slot a move may target: the normal range or an extra bag id.
local function validSlot(inv, slot)
    if slot % 1 ~= 0 then return false end
    if slot >= 1 and slot <= inv.size then return true end
    return isBagSlot(inv, slot)
end

local function sortedSlots(inv)
    local keys = {}
    for s in pairs(inv.slots) do keys[#keys + 1] = s end
    table.sort(keys)
    return keys
end

-- Worn backpack's equip slot index, and the grid rows it adds (data.rows).
local function packSlot()
    if not Clothing then return nil end
    for i, def in ipairs(Clothing.Slots) do
        if def.id == 'backpack' then return equipFrom() + i - 1 end
    end
end

local function rowsOf(entry)
    local def = entry and Items.Get(entry.item)
    return (def and def.data and tonumber(def.data.rows)) or 0
end

-- What is worn, as slot id -> item name plus that garment's condition (the shape Clothing.Aggregate wants). Separate from equipmentOf below, which returns names only for the client.
local function equipmentEntries(inv)
    local out = {}
    if not Clothing then return out end

    for i, def in ipairs(Clothing.Slots) do
        local entry = inv.slots[slotCount() + BAR_SLOTS + i]
        if entry then
            out[def.id] = {
                item = entry.item,
                -- nil, not a default, when the row has no durability: the aggregate treats no condition as pristine.
                condition = entry.durability,
            }
        end
    end

    return out
end

-- What the character is wearing: slot id -> item name.
local function equipmentOf(inv)
    local out = {}
    if not Clothing then return out end
    for i, def in ipairs(Clothing.Slots) do
        local entry = inv.slots[equipFrom() + i - 1]
        if entry then out[def.id] = entry.item end
    end
    return out
end

-- Loading

local function loadInventory(ownerType, ownerId, maxWeight, size, dims)
    local k = key(ownerType, ownerId)
    if cache[k] then return cache[k] end

    local row = exports.oxmysql:single_async(
        'SELECT * FROM `bs_inventories` WHERE `owner_type` = ? AND `owner_id` = ? LIMIT 1',
        { ownerType, tostring(ownerId) })

    if not row then
        local id = exports.oxmysql:insert_async([[
            INSERT INTO `bs_inventories` (`owner_type`, `owner_id`, `grid_width`, `grid_height`, `max_weight`)
            VALUES (?, ?, ?, ?, ?)
        ]], { ownerType, tostring(ownerId),
              Inventory.Settings.gridWidth, Inventory.Settings.gridHeight, maxWeight or 40.0 })
        row = { id = id, grid_width = Inventory.Settings.gridWidth,
                grid_height = Inventory.Settings.gridHeight, max_weight = maxWeight or 40.0 }
    end

    local items = exports.oxmysql:query_async(
        'SELECT * FROM `bs_inventory_items` WHERE `inventory_id` = ?', { row.id }) or {}

    local slots = {}
    for _, item in ipairs(items) do
        slots[item.slot_x] = {
            id = item.id,
            item = item.item,
            amount = item.amount,
            slot = item.slot_x,
            durability = item.durability,
            metadata = item.metadata and json.decode(item.metadata) or {},

            -- Where the item physically sits (see 017_inventory_grid.sql). `slot` is the identity (hotbar, crafting and moves key on it); x/y is the top-left cell it occupies. 0 means never placed.
            x   = (item.grid_x and item.grid_x > 0) and item.grid_x or nil,
            y   = (item.grid_y and item.grid_y > 0) and item.grid_y or nil,
            rot = item.rotated == true or item.rotated == 1, -- oxmysql returns TINYINT(1) as boolean
        }
    end

    -- Rows clamped to 255 earlier: put them back in a free loadout slot.
    if ownerType == 'character' and slots[255] then
        local e = slots[255]
        local def = Items.Get(e.item) or {}
        local L = LOADOUT[def.category or '']
        if L then
            for i = L.from, L.from + L.count - 1 do
                if not slots[i] then
                    slots[255], slots[i], e.slot = nil, e, i
                    exports.oxmysql:update_async('UPDATE `bs_inventory_items` SET `slot_x` = ? WHERE `id` = ?', { i, e.id })
                    break
                end
            end
        end
    end

    cache[k] = {
        id = row.id, ownerType = ownerType, ownerId = tostring(ownerId),
        slots = slots,
        maxWeight = maxWeight or row.max_weight or 40.0,
        size = size or slotCount(),

        -- Grid shape of this inventory, carried on the inventory itself so containers can differ from the player's bag (see RegisterContainer).
        gridW = (dims and dims.width)  or Inventory.Settings.gridWidth,
        gridH = (dims and dims.height) or Inventory.Settings.gridHeight,
    }
    return cache[k]
end

-- Forward declared on purpose: playerInventory calls ensurePlaced, which needs persistSlot, which is defined below. Without it the call compiles as a global lookup.
-- The character's carry limit comes from their class.
local ensurePlaced

local function playerInventory(src, tradeRead)
    if Inv.TradeLock[src] and not tradeRead then return nil end
    local player = exports.bs_core:GetPlayer(src)
    if not player then return nil end
    if Inv.TradeLockedOwner[tostring(player.charId)] and not tradeRead then return nil end
    local carry = (player.class and player.class.stats and player.class.stats.carryWeight) or 40.0

    local inv = loadInventory('character', player.charId, carry, playerSize())

    -- A cached inventory from before a reload may have the old size. Fix it here instead of clearing the cache so a live `restart bs_inventory` does not drop items.
    if inv.size < playerSize() then inv.size = playerSize() end
    inv.gridSlots = slotCount()

    -- A backpack raises the carry limit. Recomputed on every access from the class limit plus equipment, never added/subtracted in place, so it cannot drift.
    inv.maxWeight = carry

    -- Worn clothing goes through Clothing.Aggregate (stats scaled by rarity and condition). The panel and bs_zombies use the same function, so numbers always agree.
    inv.equipStats = {}

    if Clothing and Clothing.Aggregate then
        local totals = Clothing.Aggregate(equipmentEntries(inv))
        inv.equipStats = totals
        inv.maxWeight = inv.maxWeight + (totals.carry or 0.0)
    end

    -- A worn backpack adds grid rows (see data.rows in config_clothing).
    local ps = packSlot()
    local extra = ps and rowsOf(inv.slots[ps]) or 0
    -- Old packs added rows to this grid. A row that still holds items stays until it is emptied, so nothing is hidden.
    for s, e in pairs(inv.slots) do
        if e.y and isBagSlot(inv, s) then
            local d = Items.Get(e.item) or {}
            local _, fh = Grid.Footprint({ w = d.w or 1, h = d.h or 1, rot = e.rot })
            extra = math.max(extra, e.y + fh - 1 - Inventory.Settings.gridHeight)
        end
    end
    inv.gridW = Inventory.Settings.gridWidth
    inv.gridH = Inventory.Settings.gridHeight + extra
    inv.src = src

    -- Old items have no coordinates. This places them once and is a no-op afterwards, so it is safe to call on every access.
    ensurePlaced(inv)

    return inv, player
end

-- Persistence

local function persistSlot(inv, slot)
    pendingWrites[inv.id] = (pendingWrites[inv.id] or 0) + 1
    local entry = inv.slots[slot]

    if not entry then
        exports.oxmysql:update_async(
            'DELETE FROM `bs_inventory_items` WHERE `inventory_id` = ? AND `slot_x` = ?',
            { inv.id, slot })
        pendingWrites[inv.id] = pendingWrites[inv.id] - 1
        return
    end

    if entry.id then
        exports.oxmysql:update_async([[
            UPDATE `bs_inventory_items`
               SET `item` = ?, `amount` = ?, `slot_x` = ?, `grid_x` = ?, `grid_y` = ?,
                   `rotated` = ?, `durability` = ?, `metadata` = ?
             WHERE `id` = ?
        ]], { entry.item, entry.amount, slot, entry.x or 0, entry.y or 0,
              entry.rot and 1 or 0, entry.durability,
              json.encode(entry.metadata or {}), entry.id })
    else
        entry.id = exports.oxmysql:insert_async([[
            INSERT INTO `bs_inventory_items`
                (`inventory_id`, `item`, `amount`, `slot_x`, `slot_y`,
                 `grid_x`, `grid_y`, `rotated`, `durability`, `metadata`)
            VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?)
        ]], { inv.id, entry.item, entry.amount, slot, entry.x or 0, entry.y or 0,
              entry.rot and 1 or 0, entry.durability,
              json.encode(entry.metadata or {}) })
    end
    pendingWrites[inv.id] = pendingWrites[inv.id] - 1
end

-- Grid placement

-- The grid part of an inventory for the packing engine. The last `hotbarSlots` entries are the bar and are excluded so the packer never fills it. `def` is looked up per entry, so size changes in config_items apply on next load.
local function gridEntries(inv)
    local limit = inv.gridSlots or inv.size
    local out = {}

    for slot, entry in pairs(inv.slots) do
        if slot <= limit or isBagSlot(inv, slot) then
            local def = Items.Get(entry.item) or {}
            out[#out + 1] = {
                id  = slot,                 -- the slot is the identity
                w   = def.w or 1,
                h   = def.h or 1,
                x   = entry.x,
                y   = entry.y,
                rot = entry.rot,
            }
        end
    end

    return out
end

local function gridBounds(inv)
    return {
        width  = (inv and inv.gridW) or Inventory.Settings.gridWidth,
        height = (inv and inv.gridH) or Inventory.Settings.gridHeight,
    }
end

-- Items without coordinates are packed once on load, biggest first. Grid.Repack returns overflow instead of dropping it.
ensurePlaced = function(inv)
    local entries = gridEntries(inv)

    -- A placement can also be wrong, not just missing. Overlapping items from old 1x1 sizes are detected here and repacked.
    local needsWork = false
    local bounds = gridBounds(inv)

    -- Only the placed items are checked for a broken layout. An item without coordinates (just added or moved in) is fitted around them below, so it never reshuffles items that already have a spot.
    local placedNow, loose = {}, {}
    for _, e in ipairs(entries) do
        if e.x and e.y and e.x > 0 and e.y > 0 then
            placedNow[#placedNow + 1] = e
        else
            e.x, e.y = nil, nil
            loose[#loose + 1] = e
        end
    end

    do
        for i = 1, #placedNow do
            local a = placedNow[i]
            local aw, ah = Grid.Footprint(a)

            -- Off the edge: legal when it was 1x1, not legal now.
            if a.x + aw - 1 > bounds.width or a.y + ah - 1 > bounds.height then
                needsWork = true
                break
            end

            for j = i + 1, #placedNow do
                local b = placedNow[j]
                local bw, bh = Grid.Footprint(b)
                if Grid.Overlaps(a.x, a.y, aw, ah, b.x, b.y, bw, bh) then
                    needsWork = true
                    break
                end
            end

            if needsWork then break end
        end

        if needsWork then
            print(('^3[BeyondSurvival]^7 (inventory) inventory %s has an illegal layout '
                .. '(overlapping or out-of-bounds items, almost certainly placed while '
                .. 'every item was being sized 1x1) - re-packing it once. Nothing is '
                .. 'deleted.'):format(tostring(inv.id)))

            -- Cleared before the repack. Grid.Repack starts from an empty container; clearing bad coordinates just makes that explicit.
            for _, e in ipairs(entries) do e.x, e.y = nil, nil end
        end
    end

    if not needsWork then
        if #loose == 0 then return 0 end
        -- Fit each loose item into the first free gap. Nothing already placed moves.
        local count = 0
        for _, e in ipairs(loose) do
            local x, y, rotated = Grid.FirstFit(bounds, placedNow, { id = e.id, w = e.w, h = e.h, rot = false }, true)
            local entry = inv.slots[e.id]
            if x and entry then
                e.x, e.y, e.rot = x, y, rotated
                placedNow[#placedNow + 1] = e
                entry.x, entry.y, entry.rot = x, y, rotated
                persistSlot(inv, e.id)
                count = count + 1
            end
        end
        return count
    end

    for _, e in ipairs(entries) do e.x, e.y = nil, nil end
    local placed, overflow = Grid.Repack(bounds, entries)

    for _, e in ipairs(placed) do
        local entry = inv.slots[e.id]
        if entry then
            entry.x, entry.y, entry.rot = e.x, e.y, e.rot
            persistSlot(inv, e.id)
        end
    end

    if #overflow > 0 then
        print(('^3[BeyondSurvival]^7 (inventory) %d item(s) in inventory %s did not fit '
            .. 'the grid on repack and are being kept unplaced - nothing was deleted.')
            :format(#overflow, tostring(inv.id)))
    end

    return #placed
end

Inv.EnsurePlaced = ensurePlaced

-- Weight and space

function Inv.Weight(inv)
    local total = 0.0
    for _, entry in pairs(inv.slots) do
        local def = Items.Get(entry.item)
        total = total + ((def and def.weight or 0.5) * entry.amount)
    end
    return total
end

-- Last slot automatic placement may use. For a player this is the end of the grid, not the bar, so pickups never rearrange quick slots.
local function autoLimit(inv)
    return inv.gridSlots or inv.size
end

local function firstFreeSlot(inv)
    for _, slot in ipairs(bagSlotList(inv)) do
        if not inv.slots[slot] then return slot end
    end
    return nil
end

-- Would every bag item still fit with the grid at base height + rows?
local function packFits(inv, rows)
    local H = Inventory.Settings.gridHeight + (rows or 0)
    for slot, e in pairs(inv.slots) do
        if isBagSlot(inv, slot) and e.y then
            local def = Items.Get(e.item) or {}
            local _, fh = Grid.Footprint({ w = def.w or 1, h = def.h or 1, rot = e.rot })
            if e.y + fh - 1 > H then return false end
        end
    end
    return true
end

-- Taking the backpack off (drop/give/move) is refused while its rows hold items.
local function packCanLeave(inv, slot)
    if inv.ownerType ~= 'character' or slot ~= packSlot() then return true end
    return packFits(inv, 0)
end
local PACK_FULL = 'empty the backpack rows first'

-- Finds an existing stack of this item with room left in it.
local function stackWithRoom(inv, itemName)
    local def = Items.Get(itemName)
    local max = def and def.stack or 1
    if max <= 1 then return nil end

    -- Grid-only on purpose, like firstFreeSlot, so the bar does not hoover up everything you pick up.
    for _, slot in ipairs(bagSlotList(inv)) do
        local entry = inv.slots[slot]
        if entry and entry.item == itemName and entry.amount < max then return slot end
    end
    return nil
end

-- Public operations

-- Adds items to any inventory, player or container. Split from Inv.Give so the recycler can put output into the machine and keep one copy of the stacking logic.
local function addToInv(inv, itemName, amount, metadata)
    local def = Items.Get(itemName)
    if not def then return false, 'unknown item' end

    amount = math.max(1, math.floor(tonumber(amount) or 1))

    -- Items that carry state (drone battery) start with their default metadata.
    if (not metadata or next(metadata) == nil) and def.data and type(def.data.defaultMeta) == 'table' then
        metadata = def.data.defaultMeta
    end

    if Inv.Weight(inv) + (def.weight * amount) > inv.maxWeight then
        return false, 'too heavy'
    end

    local remaining = amount
    while remaining > 0 do
        -- An item with its own metadata (a dropped bag, a named note) never merges into a plain stack, or the metadata would be lost.
        local slot = nil
        if not metadata or next(metadata) == nil then slot = stackWithRoom(inv, itemName) end

        if slot then
            local room = def.stack - inv.slots[slot].amount
            local put = math.min(room, remaining)
            inv.slots[slot].amount = inv.slots[slot].amount + put
            remaining = remaining - put
            persistSlot(inv, slot)
        else
            slot = firstFreeSlot(inv)
            if not slot then return false, 'no room' end
            local put = math.min(def.stack, remaining)
            -- Needs a free spot on the grid, not just a slot number. Checked before the entry is created so a full container refuses honestly.
            local pdef = Items.Get(itemName) or {}
            local px, py, prot = Grid.FirstFit(gridBounds(inv), gridEntries(inv),
                { id = slot, w = pdef.w or 1, h = pdef.h or 1 }, true)
            if not px then return false, 'no room' end

            inv.slots[slot] = {
                item = itemName, amount = put, slot = slot, metadata = copyTable(metadata) or {},
                x = px, y = py, rot = prot,
                -- A tool arrives with its durability from the item definition.
                durability = (def.data and tonumber(def.data.durability)) or nil,
            }
            remaining = remaining - put
            persistSlot(inv, slot)
        end
    end

    return true, def.label
end

-- Adds items, stacking where possible. Returns ok, label.
function Inv.Give(src, itemName, amount, metadata)
    local inv = playerInventory(src)
    if not inv then return false, 'no character' end

    local ok, label = addToInv(inv, itemName, amount, metadata)
    Inv.Push(src)              -- push even on a partial add: some went in
    return ok, label
end

-- Places a garment straight into its equipment slot, bypassing the bag. Only for dressing a brand new character; it refuses to replace anything already worn.
function Inv.Equip(src, itemName)
    local inv = playerInventory(src)
    if not inv then return false end

    local def = Items.Get(itemName)
    if not def then return false end

    local slotId = Clothing and Clothing.SlotFor(itemName)
    if not slotId then return false end   -- not a garment at all

    local order = Clothing.OrderOf[slotId]
    if not order then return false end

    local slot = equipFrom() + order - 1
    if inv.slots[slot] then return false end   -- something is already worn there

    inv.slots[slot] = {
        item = itemName, amount = 1, slot = slot, metadata = {},
        durability = (def.data and tonumber(def.data.durability)) or nil,
    }
    persistSlot(inv, slot)
    return true
end

-- Removes items across stacks. Returns true only if the full amount was taken.
function Inv.Remove(src, itemName, amount)
    local inv = playerInventory(src)
    if not inv then return false end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if Inv.Count(src, itemName) < amount then return false end

    -- Grid first, bar last, so crafting and trades empty loose stacks before touching items you bound to the bar.
    local order = {}
    local bag = bagSlotList(inv)
    for i = #bag, 1, -1 do order[#order + 1] = bag[i] end
    for slot = inv.size, autoLimit(inv) + 1, -1 do order[#order + 1] = slot end
    -- Loadout last: a recipe only eats a slotted booster when nothing else is left.
    for slot in pairs(inv.slots) do
        if slot > inv.size and not isBagSlot(inv, slot) then order[#order + 1] = slot end
    end

    local remaining = amount
    for _, slot in ipairs(order) do
        local entry = inv.slots[slot]
        if entry and entry.item == itemName then
            local take = math.min(entry.amount, remaining)
            entry.amount = entry.amount - take
            remaining = remaining - take
            if entry.amount <= 0 then inv.slots[slot] = nil end
            persistSlot(inv, slot)
            if remaining <= 0 then break end
        end
    end

    Inv.Push(src)
    return true
end

-- Empties every slot in a player's inventory (hotbar included). Only called by the admin wipeInventory action in bs_admin, which re-checks the requester's ACE.
function Inv.Wipe(src)
    local inv = playerInventory(src)
    if not inv then return false end

    for _, slot in ipairs(sortedSlots(inv)) do
        inv.slots[slot] = nil
        persistSlot(inv, slot)
    end

    if Hotbar and Hotbar.Wipe then Hotbar.Wipe(src) end
    -- Booster and gadget slots are inventory slots too, but their bars only redraw when told.
    for _, res in ipairs({ 'bs_boosters', 'bs_gadgets' }) do
        if GetResourceState(res) == 'started' then pcall(function() exports[res]:Push(src) end) end
    end

    -- Also removes weapons from the ped, since GiveWeaponToPed weapons live on the ped and not in the inventory rows.
    -- Clear the core's persisted lastWeapon too. Otherwise cl_spawn.lua can re-arm the
    -- weapon after a death wipe even though the inventory is already empty.
    if GetResourceState('bs_core') == 'started' then
        pcall(function() exports.bs_core:SetPlayerMeta(src, 'lastWeapon', nil) end)
        pcall(function() exports.bs_core:SavePlayer(src, true) end)
    end
    TriggerClientEvent('bs:inventory:wiped', src)

    Inv.Push(src)
    return true
end

exports('WipeInventory', function(src) return Inv.Wipe(src) end)

function Inv.Count(src, itemName)
    local inv = playerInventory(src)
    if not inv then return 0 end
    local total = 0
    for _, entry in pairs(inv.slots) do
        if entry.item == itemName then total = total + entry.amount end
    end
    return total
end

-- Worn bags. A pack or vest with data.bag owns the container 'bag:<bagId>'. The id is on the item, so the contents travel with it (drop, trade, stash).
local serialise

local function bagIdFor(entry)
    entry.metadata = entry.metadata or {}
    if entry.metadata.bagId then return entry.metadata.bagId, false end
    -- Time plus randomness instead of a counter, so a new pack can never reuse an old id.
    entry.metadata.bagId = ('%x%04x%04x'):format(os.time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
    return entry.metadata.bagId, true
end

-- The container behind a bag item, sized from its definition.
local function bagInv(bagId, def)
    local bag = def.data.bag
    local w, h = bag.width or 4, bag.height or 4
    local cid = 'bag:' .. bagId
    exports.bs_inventory:RegisterContainer(cid, { label = def.label or 'Bag', width = w, height = h, maxWeight = bag.maxWeight or 20.0 })
    local b = loadInventory('container', cid, bag.maxWeight or 20.0, w * h, bag)
    b.label = def.label or 'Bag'
    b.gridW, b.gridH, b.size, b.maxWeight = w, h, w * h, bag.maxWeight or 20.0
    b.bagId, b.wornBy = bagId, nil
    return b
end
Inv.BagInv = bagInv

local function equipIndex(id)
    return Clothing and Clothing.OrderOf[id] and (equipFrom() + Clothing.OrderOf[id] - 1) or nil
end

-- The grid of the bag worn in gear slot `id` ('backpack' or 'armour'), or nil.
local function wornBag(inv, id)
    if not inv or inv.ownerType ~= 'character' then return nil end
    local slot = equipIndex(id)
    local e = slot and inv.slots[slot]
    if not e then return nil end
    local def = Items.Get(e.item)
    if not (def and def.data and def.data.bag) then return nil end
    local bagId, created = bagIdFor(e)
    if created then persistSlot(inv, slot) end
    local b = bagInv(bagId, def)
    b.wornBy = inv
    return b, e, def, slot
end
Inv.WornBag = wornBag

-- Is a bag item's own grid empty? Only empty bags may go into containers or other bags.
local function bagEmpty(entry)
    local id = entry and entry.metadata and entry.metadata.bagId
    if not id then return true end
    local ok, has = pcall(function() return exports.bs_inventory:ContainerHasItems('bag:' .. id) end)
    return ok and not has
end

-- Pockets plus whatever is in the worn pack and vest. Drives the weight bar and the heavy-load sprint penalty.
local function carriedWeight(inv)
    local total = Inv.Weight(inv)
    for _, id in ipairs({ 'backpack', 'armour' }) do
        local b = wornBag(inv, id)
        if b then total = total + Inv.Weight(b) end
    end
    return total
end
Inv.CarriedWeight = carriedWeight

-- Looks a pack tier may use (indices into Clothing.PackLooks).
local function packLooks(tier)
    local out = {}
    for i, look in ipairs(Clothing.PackLooks or {}) do
        if (look.tier or 1) <= (tier or 1) then out[#out + 1] = { i = i, id = look.id } end
    end
    return out
end

local function bagView(inv, id)
    local b, e, def = wornBag(inv, id)
    if not b then return nil end
    local v = serialise(b)
    v.label, v.item, v.vest = def.label or e.item, e.item, def.data.vest or nil
    if id == 'backpack' then
        local tier = tonumber(def.data.tier) or 1
        v.tier = tier
        v.looks = packLooks(tier)
        v.look = tonumber(e.metadata.look) or (Clothing.PackDefaultLook or {})[tier] or 1
        v.hidden = e.metadata.hidden == true
    end
    return v
end

-- What the client puts on component 5: the chosen look, or nothing when hidden.
local function packVisual(inv)
    local slot = equipIndex('backpack')
    local e = slot and inv.slots[slot]
    if not e then return nil end
    local def = Items.Get(e.item)
    if not (def and def.data and def.data.bag) then return nil end
    local meta = e.metadata or {}
    if meta.hidden then return { hidden = true } end
    local tier = tonumber(def.data.tier) or 1
    local idx = tonumber(meta.look) or (Clothing.PackDefaultLook or {})[tier]
    local look = idx and Clothing.PackLooks and Clothing.PackLooks[idx]
    if not look or (look.tier or 1) > tier then return nil end
    return { male = look.male, female = look.female }
end

-- Client-facing shape

function serialise(inv)
    local out = {
        slots = {}, weight = Inv.Weight(inv), maxWeight = inv.maxWeight, size = inv.size,
        -- Where the grid stops and the bar starts. Sent so the panel never needs the grid dimensions.
        gridSlots = inv.gridSlots or inv.size,

        -- Grid shape, so the panel lays out cells without hardcoding it and containers can differ from the bag.
        grid = { w = inv.gridW or Inventory.Settings.gridWidth,
                 h = inv.gridH or Inventory.Settings.gridHeight },
        -- First free bag id, so the panel never guesses one.
        freeSlot = firstFreeSlot(inv) or false,
        baseRows = inv.ownerType == 'character' and Inventory.Settings.gridHeight or nil,
    }
    local cspec = inv.ownerType == 'container' and containerSpecs[inv.ownerId] or nil
    if cspec and cspec.compact then out.compact = true end

    -- Which indices are equipment frames and what is worn. Derived on the server so the client config cannot disagree after a slot is added.
    if inv.ownerType == 'character' and Clothing then
        out.equipFrom = equipFrom()
        out.equip = {}
        for i, def in ipairs(Clothing.Slots) do
            out.equip[#out.equip + 1] = {
                id = def.id, label = def.label, ui = def.ui,
                slot = equipFrom() + i - 1,
            }
        end
        out.worn = equipmentOf(inv)

        -- Totals and per-garment breakdown, so the character sheet can show both the bonus and which item gives it.
        local totals, breakdown = Clothing.Aggregate(equipmentEntries(inv))
        out.equipStats = totals
        out.equipBreakdown = breakdown

        -- Worn pack and vest grids, drawn as their own boxes under the pockets.
        out.pack = bagView(inv, 'backpack')
        out.vest = bagView(inv, 'armour')
        out.ownWeight = out.weight
        out.weight = carriedWeight(inv)
        out.packVisual = packVisual(inv)
    end
    for slot, entry in pairs(inv.slots) do
        local def = Items.Get(entry.item) or {}
        out.slots[tostring(slot)] = {
            slot = slot,
            item = entry.item,
            -- Dynamic book titles are stored per copy; the underlying item remains 'book'.
            label = (entry.item == 'book' and type(entry.metadata) == 'table'
                and type(entry.metadata.bookTitle) == 'string' and entry.metadata.bookTitle ~= ''
                and entry.metadata.bookTitle:sub(1, 100)) or def.label or entry.item,
            ongrid = isBagSlot(inv, slot),

            -- Where and how big, for the grid renderer. w/h are the natural size; `rot` tells the panel to swap them.
            x = entry.x, y = entry.y, rot = entry.rot or false,
            w = def.w or 1, h = def.h or 1,
            amount = entry.amount,
            weight = def.weight or 0.5,
            category = def.category or 'misc',
            usable = def.usable or false,
            stack = def.stack or 1,
            description = def.description,  -- tooltip; nil for most items
            durability = entry.durability,
            -- drone battery %, shown on the slot and tooltip
            battery = def.data and def.data.battery and tonumber((entry.metadata or {}).battery or 100) or nil,
            batteryCap = def.data and def.data.battery and ((entry.metadata or {}).capacity or 'small') or nil,
            -- Level of a measured container (jerrycan): raw amount and capacity, so the panel can draw a percentage.
            fill = def.data and def.data.capacity and (entry.durability or 0) or nil,
            capacity = def.data and def.data.capacity or nil,

            -- True for anything that opens as its own grid. The panel uses it to decide whether clicking a worn item does anything. Size is only sent once it is opened.
            bag = (def.data and def.data.bag) and true or nil,

            -- Rarity and condition for garments. Sent as the tier name, not a colour; the stylesheet owns the palette.
            rarity = def.rarity,
            condition = def.equipSlot and (entry.durability
                or (def.data and def.data.durability)) or nil,

            -- Which body slot this goes on, so the panel can offer double-click to wear it. Only a hint; the server still validates.
            equipSlot = def.equipSlot,
        }
    end
    return out
end

-- Pushes the player's inventory (and any open container) to their client.
-- The hotbar lives in sv_hotbar.lua; declared here so both files share it.
Hotbar = Hotbar or {}

-- playerInventory is local to this file, so sv_hotbar.lua gets it through Inv.Of instead of a nonexistent global.
Inv.Of = playerInventory

-- One-shot tokens for ammunition that turned out not to fit. See the use path.
AmmoPending = AmmoPending or {}
AmmoToken = AmmoToken or 0

RegisterNetEvent('bs:inventory:ammoRefund', function(token)
    local src = source
    local pending = AmmoPending[src]
    AmmoPending[src] = nil

    if not pending then return end
    if tonumber(token) ~= pending.token then return end

    Inv.Give(src, pending.item, pending.count or 1)
    Inv.Push(src)
end)

AddEventHandler('playerDropped', function() AmmoPending[source] = nil end)

-- Reloading is an item transaction. GTA's native reload moves rounds from the ped's reserve and consumes nothing, so ammo items are spent here instead.
BSB.RegisterCallback('inventory:reload', function(src, need)
    local inv = Inv.Of and Inv.Of(src)
    if not inv then return { ok = false, error = 'no character' } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'no ped' } end

    local hash = GetSelectedPedWeapon(ped)
    if not hash or hash == GetHashKey('WEAPON_UNARMED') then
        return { ok = false, error = Lp(src, 'inv.e_hands') }
    end

    -- The ped gives a weapon hash; `ammoFor` is keyed by model name. Match on hash against the player's own slots so the item registry stays the single source for which rounds fit which gun.
    local item, def, model = nil, nil, nil

    for _, slot in ipairs(sortedSlots(inv)) do
        local entry = inv.slots[slot]
        if entry then
            local d = Items.Get(entry.item)
            local data = d and d.data
            if data and tonumber(data.rounds) and type(data.ammoFor) == 'table' then
                for _, name in ipairs(data.ammoFor) do
                    if GetHashKey(name) == hash then
                        item, def, model = entry.item, d, name
                        break
                    end
                end
            end
        end
        if item then break end
    end

    if not item then return { ok = false, error = Lp(src, 'inv.e_no_rounds') } end

    -- Enough boxes to fill the mag, never more than one mag (size from bs_weapons config, extended mag aware). Leftover of the last box stays on the ped as reserve.
    local per = tonumber(def.data.rounds) or 1
    local mag = nil
    if GetResourceState('bs_weapons') == 'started' then
        local ok, m = pcall(function() return exports.bs_weapons:MagSize(src, model) end)
        if ok then mag = tonumber(m) end
    end
    need = math.floor(tonumber(need) or per)
    need = math.max(1, math.min(need, mag or per))
    local boxes = math.min(math.ceil(need / per), Inv.Count(src, item))
    if boxes < 1 then boxes = 1 end

    -- Taken before the rounds are sent, so rounds only come from a spent box. The refund path above makes this safe.
    if not Inv.Remove(src, item, boxes) then
        return { ok = false, error = Lp(src, 'inv.e_rounds') }
    end

    AmmoToken = (AmmoToken or 0) + 1
    AmmoPending[src] = { item = item, token = AmmoToken, count = boxes }

    TriggerClientEvent('bs:inventory:loadAmmo', src,
        AmmoToken, def.data.ammoFor, per * boxes)

    return { ok = true, rounds = per * boxes, label = ItemLabel(item, src) }
end)

function Inv.Push(src)
    local inv = playerInventory(src, true)
    if not inv then return end

    -- Booster counts come from the bag, so any bag change refreshes them.
    if GetResourceState('bs_boosters') == 'started' then
        pcall(function() exports.bs_boosters:Push(src) end)
    end
    if GetResourceState('bs_gadgets') == 'started' then
        pcall(function() exports.bs_gadgets:Push(src) end)
    end

    -- If the open bag is no longer on your body (moved, dropped, given) you cannot reach into it. Checked here because every change ends in a Push.
    local opened = openedAt[src]
    if opened and opened.bagId then
        local worn = false
        if Clothing then
            for i = 1, #Clothing.Slots do
                local e = inv.slots[equipFrom() + i - 1]
                if e and e.metadata and e.metadata.bagId == opened.bagId then worn = true break end
            end
        end
        if not worn then
            openContainers[src], openedAt[src] = nil, nil
        end
    end

    local payload = { action = 'inventory', player = serialise(inv) }

    local openKey = openContainers[src]
    if openKey and cache[openKey] then
        payload.container = serialise(cache[openKey])
        payload.containerLabel = cache[openKey].label
    end

    TriggerClientEvent('bs:inventory:state', src, payload)

    -- The bar reflects the bag: counts change, slots grey out, bindings stay.
    if Hotbar.Push then Hotbar.Push(src) end
end

Inv.TradeInternals = {
    of = function(src) return playerInventory(src, true) end,
    serialise = serialise,
    gridEntries = gridEntries,
    gridBounds = gridBounds,
    slotLimit = autoLimit,
    isBag = isBagSlot,
    bagSlots = bagSlotList,
    pending = function(inv) return pendingWrites[inv.id] or 0 end,
    evict = function(charId) cache[key('character', charId)] = nil end,
}

-- Callbacks

BSB.RegisterCallback('inventory:open', function(src)
    local inv, player = playerInventory(src, true)
    if not inv then return { ok = false, error = 'no character' } end
    return {
        ok = true,
        player = serialise(inv),
        settings = player.hudSettings,
        grid = { w = Inventory.Settings.gridWidth, h = Inventory.Settings.gridHeight },
    }
end)

-- Moving between slots, and between the player and an open container.
BSB.RegisterCallback('inventory:move', function(src, from, to, amount)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end

    local containerKey = openContainers[src]

    -- Opening a container does not allow using it from across the map.
    local opened = openedAt[src]
    if containerKey and (from.inv == 'container' or to.inv == 'container') then
        if not opened then return { ok = false, error = Lp(src, 'inv.e_bad_inv') } end
        if not opened.bagId then
            local here = GetEntityCoords(GetPlayerPed(src))
            if #(here - opened.pos) > CONTAINER_REACH then
                openContainers[src], openedAt[src] = nil, nil
                return { ok = false, error = Lp(src, 'inv.e_far') }
            end
        end
    end

    local function resolve(which)
        if which == 'player' then return inv end
        if which == 'container' and containerKey then return cache[containerKey] end
        -- Your own worn pack / vest pockets.
        if which == 'pack' then return (wornBag(inv, 'backpack')) end
        if which == 'vest' then return (wornBag(inv, 'armour')) end
        return nil
    end

    local srcInv = resolve(from.inv)
    local dstInv = resolve(to.inv)
    if not srcInv or not dstInv then return { ok = false, error = Lp(src, 'inv.e_bad_inv') } end

    local fromSlot, toSlot = tonumber(from.slot), tonumber(to.slot)
    if not fromSlot or not toSlot then return { ok = false, error = Lp(src, 'inv.e_bad_slot') } end
    -- A cell drop into a smaller inventory arrives with a slot id it does not have. Give it a free one there.
    if srcInv ~= dstInv and tonumber(to.x) and tonumber(to.y) and not validSlot(dstInv, toSlot) then
        toSlot = firstFreeSlot(dstInv) or toSlot
    end
    if not validSlot(dstInv, toSlot) then return { ok = false, error = Lp(src, 'inv.e_bad_slot') } end

    local moving = srcInv.slots[fromSlot]
    if not moving then return { ok = false, error = 'nothing there' } end

    -- A split, or a stack dropped on an empty cell of another inventory, arrives with the source slot id. The new stack needs its own free slot id there,
    -- otherwise it hits the "moved within its own slot" case (nothing happens) or lands on whatever owns that id in the other inventory.
    local splitting = (tonumber(amount) or moving.amount) < moving.amount
    if tonumber(to.x) and tonumber(to.y) and isBagSlot(dstInv, toSlot) then
        local there = dstInv.slots[toSlot]
        if (splitting and there == moving) or (srcInv ~= dstInv and there and toSlot == fromSlot) then
            local free = firstFreeSlot(dstInv)
            if not free then return { ok = false, error = Lp(src, 'inv.e_room') } end
            toSlot = free
        end
    end

    -- A bag cannot go inside itself: it would vanish with its contents.
    if to.inv == 'container' and opened and opened.bagId and moving.metadata
        and moving.metadata.bagId == opened.bagId then
        return { ok = false, error = Lp(src, 'inv.e_itself') }
    end
    if dstInv.bagId and moving.metadata and moving.metadata.bagId == dstInv.bagId then
        return { ok = false, error = Lp(src, 'inv.e_itself') }
    end
    -- Only an empty bag goes into a container, stash or another bag (SCUM rule).
    if dstInv.ownerType == 'container' and srcInv ~= dstInv then
        local mdef = Items.Get(moving.item)
        if mdef and mdef.data and mdef.data.bag and not bagEmpty(moving) then
            return { ok = false, error = Lp(src, 'inv.e_bag_not_empty') }
        end
    end

    -- An equipment frame only accepts items for that body part. Enforced on the server, since the panel refusing a drop is only a courtesy.
    if Clothing then
        -- Swapping out of a gear slot would put the other item on your body unchecked.
        local fromGear = srcInv.ownerType == 'character' and equipSlotAt(fromSlot)
        local swapIn = dstInv.slots[toSlot]
        if fromGear and swapIn and (srcInv ~= dstInv or toSlot ~= fromSlot) then
            local sdef = Items.Get(swapIn.item)
            if not sdef or sdef.equipSlot ~= fromGear.id then
                return { ok = false, error = Lp(src, 'inv.e_take_off') }
            end
        end
    end

    -- Pack leaving (or swapped for a smaller one): its extra rows must be empty and the pack must land inside what is left.
    local packLeaving = srcInv.ownerType == 'character' and fromSlot == packSlot()
        and (srcInv ~= dstInv or toSlot ~= fromSlot)
    local keepRows = 0
    if packLeaving then
        keepRows = rowsOf(dstInv.slots[toSlot])
        if not packFits(srcInv, keepRows) then return { ok = false, error = PACK_FULL } end
    end
    -- Swapping a smaller pack on: the current extra rows must still fit.
    if dstInv.ownerType == 'character' and toSlot == packSlot() and dstInv.slots[toSlot]
        and (srcInv ~= dstInv or fromSlot ~= toSlot)
        and not packFits(dstInv, rowsOf(moving)) then
        return { ok = false, error = PACK_FULL }
    end

    if dstInv.ownerType == 'character' and Clothing then
        local wantSlot = equipSlotAt(toSlot)
        -- Only armour and backpack are live gear slots; the clothing ones stay reserved.
        if wantSlot and Clothing.IsActiveSlot and not Clothing.IsActiveSlot(wantSlot) then
            return { ok = false, error = Lp(src, 'inv.e_slot_unused') }
        end
        if wantSlot then
            local def = Items.Get(moving.item)
            local goesIn = def and def.equipSlot

            if not goesIn then
                return { ok = false, error = Lp(src, 'inv.e_not_wear') }
            end
            if goesIn ~= wantSlot.id then
                return { ok = false, error = Lp(src, 'inv.e_goes_on', { slot = Clothing.BySlot[goesIn] and Clothing.BySlot[goesIn].label or goesIn }) }
            end
            -- Never a partial stack into a body slot: you wear one coat.
            if (tonumber(amount) or moving.amount) ~= moving.amount then
                return { ok = false, error = Lp(src, 'inv.e_whole') }
            end
        end
    end

    -- Grid position is always validated on the server. The panel's x/y is only a request, so the destination is re-tested against the real rows with Grid.Fits.
    local wantX, wantY = tonumber(to.x), tonumber(to.y)
    local wantRot = to.rot == true
    local toBag = isBagSlot(dstInv, toSlot)

    -- Coming onto the grid from bar/gear/loadout with no cell picked: find one.
    if toBag and not (wantX and wantY) and not dstInv.slots[toSlot]
        and (srcInv ~= dstInv or not isBagSlot(srcInv, fromSlot)) then
        local mdef = Items.Get(moving.item) or {}
        local bounds = gridBounds(dstInv)
        if packLeaving and srcInv == dstInv then bounds.height = Inventory.Settings.gridHeight + keepRows end
        local fx, fy, frot = Grid.FirstFit(bounds, gridEntries(dstInv),
            { id = fromSlot, w = mdef.w or 1, h = mdef.h or 1 }, true)
        if not fx then return { ok = false, error = Lp(src, 'inv.e_room') } end
        wantX, wantY, wantRot = fx, fy, frot
    end

    if packLeaving and srcInv == dstInv and toBag and wantY then
        local mdef = Items.Get(moving.item) or {}
        local _, fh = Grid.Footprint({ w = mdef.w or 1, h = mdef.h or 1, rot = wantRot })
        if wantY + fh - 1 > Inventory.Settings.gridHeight + keepRows then
            return { ok = false, error = Lp(src, 'inv.e_room_out') }
        end
    end

    -- Where the item sat before the move. A split leaves the rest of the stack here.
    local fromX, fromY, fromRot = moving.x, moving.y, moving.rot
    local placeX, placeY, placeRot = nil, nil, nil

    if wantX and wantY and toBag then
        local mdef = Items.Get(moving.item) or {}
        local okFit, why = Grid.Fits(
            gridBounds(dstInv), gridEntries(dstInv),
            { id = fromSlot, w = mdef.w or 1, h = mdef.h or 1, rot = wantRot },
            wantX, wantY,
            -- A split leaves the rest where it is, so its own cells are not free.
            (srcInv == dstInv and not splitting) and fromSlot or nil)

        if not okFit then return { ok = false, error = why or 'it does not fit there' } end

        placeX, placeY, placeRot = wantX, wantY, wantRot
        if not splitting then moving.x, moving.y, moving.rot = wantX, wantY, wantRot end
    end

    amount = math.floor(tonumber(amount) or moving.amount)
    amount = math.max(1, math.min(amount, moving.amount))

    local def = Items.Get(moving.item)
    local target = dstInv.slots[toSlot]

    -- Weight check when the item crosses into another inventory.
    if srcInv ~= dstInv then
        local incoming = (def and def.weight or 0.5) * amount
        if Inv.Weight(dstInv) + incoming > dstInv.maxWeight then
            return { ok = false, error = Lp(src, 'inv.e_heavy') }
        end
        -- Into your pack from outside you: the whole load counts, not just the pack.
        if dstInv.wornBy == inv and srcInv ~= inv and srcInv.wornBy ~= inv
            and carriedWeight(inv) + incoming > inv.maxWeight then
            return { ok = false, error = Lp(src, 'inv.e_heavy') }
        end
    end

    if target == moving then
        -- Moved within its own slot (just a new spot in the grid). Coordinates were set above; nothing else changes.
    elseif target and target.item == moving.item and def and def.stack > 1 then
        -- Merge into the stack, up to its limit.
        local room = def.stack - target.amount
        local put = math.min(room, amount)
        if put <= 0 then return { ok = false, error = Lp(src, 'inv.e_stack') } end
        target.amount = target.amount + put
        moving.amount = moving.amount - put
        if moving.amount <= 0 then
            srcInv.slots[fromSlot] = nil
        else
            -- What is left over did not move.
            moving.x, moving.y, moving.rot = fromX, fromY, fromRot
        end
    elseif target then
        -- Swap, but only when the whole stack is being moved.
        if amount ~= moving.amount then return { ok = false, error = Lp(src, 'inv.e_split') } end
        srcInv.slots[fromSlot], dstInv.slots[toSlot] = target, moving
        target.slot, moving.slot = fromSlot, toSlot
        target.id, moving.id = nil, nil       -- rows are rewritten below
    else
        if amount == moving.amount then
            srcInv.slots[fromSlot] = nil
            moving.slot = toSlot
            moving.id = nil
            dstInv.slots[toSlot] = moving
        else
            moving.amount = moving.amount - amount
            -- The rest of the stack stays where it was; only the split half goes to the picked cell. Otherwise both sat on the same cells and the whole grid was repacked.
            moving.x, moving.y, moving.rot = fromX, fromY, fromRot
            -- The split half is the same stuff, so it keeps the same metadata.
            dstInv.slots[toSlot] = { item = moving.item, amount = amount, slot = toSlot,
                x = placeX, y = placeY, rot = placeRot,
                metadata = copyTable(moving.metadata) or {} }
        end
    end

    persistSlot(srcInv, fromSlot)
    persistSlot(dstInv, toSlot)
    Inv.Push(src)
    -- Someone looting a downed player's pack: the owner sees it change too.
    for _, b in ipairs({ srcInv, dstInv }) do
        local owner = b.wornBy and b.wornBy.src
        if owner and owner ~= src then Inv.Push(owner) end
    end
    return { ok = true }
end)

BSB.RegisterCallback('inventory:use', function(src, slot)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end

    local entry = inv.slots[tonumber(slot)]
    if not entry then return { ok = false, error = 'nothing there' } end

    local def = Items.Get(entry.item)
    if not def or not def.usable then return { ok = false, error = Lp(src, 'inv.e_cant_use') } end

    -- Medical system on: medical items open the Medical tab instead (bs_medical decides).
    if def.category == 'medical' and GetResourceState('bs_medical') == 'started' then
        local okM, took = pcall(function() return exports.bs_medical:InterceptUse(src, entry.item) end)
        if okM and took then return { ok = true, label = ItemLabel(entry.item, src), consumed = false, medical = true } end
    end

    local data = def.data or {}

    -- Downed players may never use a revive-capable item on themselves.
    -- This check happens before animation/effects/consumption, so a medkit is kept.
    if data.revive and GetResourceState('bs_medical') == 'started' then
        local okD, down = pcall(function() return exports.bs_medical:IsDowned(src) end)
        if okD and down then
            return { ok = false, error = 'Du kannst dich nicht selbst wiederbeleben.' }
        end
    end

    local consumed = true

    -- animKind says which use animation to play (eat, heal, ...), decided from the item data. The client (cl_main.lua) picks the actual anim/scenario.
    local animKind = nil
    if data.heal then
        animKind = 'heal'
    elseif data.hunger then
        animKind = 'eat'
    elseif data.thirst then
        animKind = 'drink'
    end
    if animKind then TriggerClientEvent('bs:inventory:useAnim', src, animKind) end

    if data.hunger or data.thirst then
        exports.bs_core:RestoreNeeds(src, data.hunger or 0, data.thirst or 0)
    end
    if data.heal then
        -- data.heal is a percent of max health. Triage: the perk lives in bs_skills, the decision lives here, so a client never says how much it healed.
        local heal = data.heal
        if GetResourceState('bs_skills') == 'started' then
            local ok, has = pcall(function() return exports.bs_skills:HasPerk(src, 'triage') end)
            if ok and has then heal = math.floor(heal * 1.25) end
        end

        TriggerClientEvent('bs:inventory:heal', src, heal)
        exports.bs_core:AwardAction(src, 'wound_treated')
    end
    if data.cure then
        exports.bs_core:ChangeInfection(src, -math.abs(data.cure))
    end
    if data.armour then
        TriggerClientEvent('bs:inventory:armour', src, data.armour)
    end
    if data.weapon then
        -- Use the ammo left in the weapon (remembered by bs_weapons), not the static data.ammo default.
        local savedAmmo = nil
        if type(data.weapon) == 'string' and GetResourceState('bs_weapons') == 'started' then
            local ok, saved = pcall(function() return exports.bs_weapons:SavedAmmo(src, data.weapon) end)
            if ok then savedAmmo = saved end
        end

        -- Tell bs_weapons which gun this is, so its own attachments are used.
        if type(data.weapon) == 'string' and GetResourceState('bs_weapons') == 'started' then
            pcall(function() exports.bs_weapons:SetActive(src, data.weapon, tonumber(slot)) end)
        end
        if data.throwable then
            -- Throwables: equip with ammo = stack count and keep the item. One is removed per throw (bs:inventory:thrown).
            TriggerClientEvent('bs:inventory:equipWeapon', src, data.weapon, entry.amount or 1)
            consumed = false
        else
            TriggerClientEvent('bs:inventory:equipWeapon', src, data.weapon, savedAmmo or data.ammo)
            -- A thrown weapon is consumed, a bat is not. The item's own definition decides.
            consumed = (data.ammo ~= nil)
        end
    end

    -- Loading rounds: the box is consumed here and handed back if it does not fit. The hand-back needs a one-shot token issued with the load, so a client cannot request a refund twice.
    if data.rounds and data.ammoFor then
        AmmoToken = (AmmoToken or 0) + 1
        AmmoPending[src] = { item = entry.item, token = AmmoToken }

        TriggerClientEvent('bs:inventory:loadAmmo', src,
            AmmoToken, data.ammoFor, data.rounds)

        consumed = true
    end
    if data.craftingStation then consumed = false end
    -- Items another resource handles (bs_events tokens): it removes them itself.
    if data.handled then consumed = false end
    -- Drugs/cigarettes: bs_drugs checks, removes the item and runs the effect itself.
    if data.drug then
        consumed = false
        TriggerEvent('bs:drugs:use', src, entry.item)
    end

    -- ESX compatibility hook (see ESX.RegisterUsableItem in bs_esx_bridge). Same-side TriggerEvent, silent if nobody listens. Fires after the item's own effects, not instead of them.
    TriggerEvent('bsesx:useItem:' .. entry.item, src)
    -- Items another resource reacts to (bs_crafting kits, traps, raw meat).
    if type(data.useEvent) == 'string' then TriggerEvent(data.useEvent, src, entry.item, slot) end

    if consumed then Inv.Remove(src, entry.item, 1) end
    Inv.Push(src)
    return { ok = true, label = ItemLabel(entry.item, src), consumed = consumed }
end)

-- A throwable left the hand (ammo went down on the client): take one from the stack. Needs a held throwable of that weapon, one per call, rate limited.
local LastThrow = {}
RegisterNetEvent('bs:inventory:thrown', function(weapon)
    local src = source
    if type(weapon) ~= 'string' or #weapon > 48 then return end
    local now = GetGameTimer()
    if LastThrow[src] and now - LastThrow[src] < 250 then return end
    LastThrow[src] = now
    local inv = playerInventory(src)
    if not inv then return end
    for _, entry in pairs(inv.slots) do
        local def = entry and Items.Get(entry.item)
        local data = def and def.data
        if data and data.throwable and data.weapon == weapon then
            Inv.Remove(src, entry.item, 1)
            Inv.Push(src)
            return
        end
    end
end)
AddEventHandler('playerDropped', function() LastThrow[source] = nil end)

BSB.RegisterCallback('inventory:drop', function(src, slot, amount)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end
    local entry = inv.slots[tonumber(slot)]
    if not entry then return { ok = false } end
    if not packCanLeave(inv, tonumber(slot)) then return { ok = false, error = PACK_FULL } end

    amount = math.max(1, math.min(math.floor(tonumber(amount) or entry.amount), entry.amount))
    local item = entry.item

    entry.amount = entry.amount - amount
    if entry.amount <= 0 then inv.slots[tonumber(slot)] = nil end
    persistSlot(inv, tonumber(slot))
    Inv.Push(src)

    -- The world drop itself is bs_economy's business; for now it simply leaves the character's hands.
    TriggerEvent('bs:inventory:dropped', src, item, amount)
    return { ok = true }
end)

-- Opens a shared container (stash, searched crate). label/size/maxWeight arguments are kept for compatibility but are ignored. A containerId with no registered spec is refused.
BSB.RegisterCallback('inventory:openContainer', function(src, containerId)
    if type(containerId) ~= 'string' or #containerId > 64 then return { ok = false } end

    local spec = containerSpecs[containerId]
    if not spec then return { ok = false, error = Lp(src, 'inv.e_container') } end

    -- Only what the server just granted this player; one use, then it is spent.
    local grants = containerGrants[src]
    local grant = grants and grants[containerId]
    if grants then grants[containerId] = nil end
    if not grant or GetGameTimer() > grant.expires then
        return { ok = false, error = Lp(src, 'inv.e_cant_open') }
    end

    local inv = loadInventory('container', containerId, spec.maxWeight, spec.size, spec)
    inv.label = spec.label
    -- A spec can change between restarts (bag config edited, boot resized) while the inventory is still cached from the old one.
    inv.gridW, inv.gridH, inv.size = spec.width, spec.height, spec.size
    openContainers[src] = key('container', containerId)
    openedAt[src] = { pos = grant.pos }
    Inv.Push(src)
    return { ok = true, container = serialise(inv), label = inv.label }
end)

-- Opening the bag you are wearing. The container is keyed to the pack item (metadata bagId), not the player or slot, so contents travel with the pack when it is dropped or stashed.
local function bagIdFor(entry)
    entry.metadata = entry.metadata or {}
    if entry.metadata.bagId then return entry.metadata.bagId, false end

    -- Time plus randomness instead of a counter, so a new pack can never reuse the id of an older one.
    entry.metadata.bagId = ('%x%04x%04x'):format(
        os.time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF))

    return entry.metadata.bagId, true
end

BSB.RegisterCallback('inventory:openBag', function(src, slot)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end

    slot = tonumber(slot)
    if not slot then return { ok = false, error = Lp(src, 'inv.e_bad_slot') } end

    -- Must be a slot on your body, not a bag slot or an open container. This keeps bags from nesting.
    if not equipSlotAt(slot) then return { ok = false, error = Lp(src, 'inv.e_not_worn') } end

    local entry = inv.slots[slot]
    if not entry then return { ok = false, error = 'nothing there' } end

    local def = Items.Get(entry.item)
    local bag = def and def.data and def.data.bag
    if not bag then return { ok = false, error = Lp(src, 'inv.e_no_open') } end

    local bagId, created = bagIdFor(entry)
    if created then persistSlot(inv, slot) end

    local containerId = 'bag:' .. bagId

    exports.bs_inventory:RegisterContainer(containerId, {
        label     = def.label or 'Bag',
        width     = bag.width,
        height    = bag.height,
        maxWeight = bag.maxWeight or 20.0,
    })

    local container = loadInventory('container', containerId,
        bag.maxWeight or 20.0, (bag.width or 4) * (bag.height or 4), bag)
    container.label = def.label or 'Bag'
    container.gridW, container.gridH = bag.width, bag.height

    openContainers[src] = key('container', containerId)
    openedAt[src] = { pos = GetEntityCoords(GetPlayerPed(src)), bagId = bagId }
    Inv.Push(src)

    return { ok = true, container = serialise(container), label = container.label }
end)

-- Walking away from a body, stash or boot closes it on screen too, not just on the next move.
CreateThread(function()
    while true do
        Wait(1000)
        for src, opened in pairs(openedAt) do
            if opened and not opened.bagId and opened.pos and openContainers[src] then
                local ped = GetPlayerPed(src)
                if ped == 0 or #(GetEntityCoords(ped) - opened.pos) > CONTAINER_REACH then
                    openContainers[src], openedAt[src] = nil, nil
                    if ped ~= 0 then
                        Inv.Push(src)
                    end
                end
            end
        end
    end
end)

BSB.RegisterCallback('inventory:closeContainer', function(src)
    openContainers[src], openedAt[src] = nil, nil
    return { ok = true }
end)

-- Is there anything in it? bs_vehicles asks before cleaning up a car. Reads the database if the container is not in memory. Returns a plain boolean.
exports('ContainerHasItems', function(containerId)
    if type(containerId) ~= 'string' then return false end

    local k = key('container', containerId)
    local inv = cache[k]

    if inv then
        for _ in pairs(inv.slots) do return true end
        return false
    end

    local rows = exports.oxmysql:query_async([[
        SELECT i.`id` FROM `bs_inventory_items` i
        JOIN `bs_inventories` v ON v.`id` = i.`inventory_id`
        WHERE v.`owner_type` = 'container' AND v.`owner_id` = ?
        LIMIT 1
    ]], { containerId }) or {}

    return #rows > 0
end)

-- Containers as machines (bs_recycler): exports to read what is inside a container, take it, and put something back. Exports because the caller is a resource, not a client.

local function containerInv(containerId)
    if type(containerId) ~= 'string' then return nil end
    local spec = containerSpecs[containerId]
    if not spec then return nil end
    local inv = loadInventory('container', containerId, spec.maxWeight, spec.size, spec)
    -- Cached from an older spec: keep the grid in step so gives use the real bounds.
    inv.gridW, inv.gridH, inv.size = spec.width, spec.height, spec.size
    return inv
end

-- Anyone with this container open sees the change immediately.
local function pushContainer(containerId)
    local k = key('container', containerId)
    for src, openKey in pairs(openContainers) do
        if openKey == k then Inv.Push(src) end
    end
end

exports('ContainerContents', function(containerId)
    local inv = containerInv(containerId)
    if not inv then return {} end

    local out = {}
    for slot, entry in pairs(inv.slots) do
        out[#out + 1] = { slot = slot, item = entry.item, amount = entry.amount }
    end
    return out
end)

-- Empties the container and returns its contents in one step, so a second player cannot take an item that was already counted.
exports('ContainerTakeAll', function(containerId)
    local inv = containerInv(containerId)
    if not inv then return {} end

    local out = {}
    for slot = 1, inv.size do
        local entry = inv.slots[slot]
        if entry then
            out[#out + 1] = { item = entry.item, amount = entry.amount }
            inv.slots[slot] = nil
            persistSlot(inv, slot)
        end
    end

    pushContainer(containerId)
    return out
end)

exports('ContainerGive', function(containerId, item, amount)
    local inv = containerInv(containerId)
    if not inv then return false, 'unknown container' end

    local ok, label = addToInv(inv, item, amount)
    pushContainer(containerId)
    return ok, label
end)

-- Death: moves every row a player owns (grid, bar, worn gear) into a corpse container, keeping metadata and durability. Rows are copied; the caller wipes the player side with WipeInventory. Returns moved row count.
exports('DeathTransfer', function(src, containerId, label)
    if type(containerId) ~= 'string' then return 0 end
    local inv = playerInventory(src)
    if not inv then return 0 end

    -- The worn pack falls next to the body as its own lootable bag (contents stay in its bag container).
    local ps = packSlot()
    local packEntry = ps and inv.slots[ps]
    if packEntry and Inv.DropPackOnDeath then
        local ok = pcall(Inv.DropPackOnDeath, src, packEntry)
        if not ok then packEntry = nil end
    else
        packEntry = nil
    end

    local rows, cells = {}, 0
    for _, slot in ipairs(sortedSlots(inv)) do
        local e = inv.slots[slot]
        if e and e ~= packEntry then
            rows[#rows + 1] = e
            local d = Items.Get(e.item) or {}
            cells = cells + (d.w or 1) * (d.h or 1)
        end
    end
    if #rows == 0 then return 0 end

    -- Wide and tall enough for everything, with slack for awkward shapes.
    local w = 12
    local h = math.max(4, math.min(20, math.ceil(cells * 1.4 / w) + 1))
    exports.bs_inventory:RegisterContainer(containerId, {
        label = label or 'Body', width = w, height = h, maxWeight = 500.0,
    })
    local box = containerInv(containerId)
    if not box then return 0 end

    -- Biggest first so a rifle is not left out by a pile of bandages.
    table.sort(rows, function(a, b)
        local da, db = Items.Get(a.item) or {}, Items.Get(b.item) or {}
        return (da.w or 1) * (da.h or 1) > (db.w or 1) * (db.h or 1)
    end)

    local moved = 0
    for _, e in ipairs(rows) do
        local slot
        for i = 1, box.size do if not box.slots[i] then slot = i break end end
        if not slot then break end
        local d = Items.Get(e.item) or {}
        local x, y, rot = Grid.FirstFit(gridBounds(box), gridEntries(box),
            { id = slot, w = d.w or 1, h = d.h or 1 }, true)
        if x then
            box.slots[slot] = {
                item = e.item, amount = e.amount, slot = slot,
                metadata = copyTable(e.metadata) or {}, durability = e.durability,
                x = x, y = y, rot = rot,
            }
            persistSlot(box, slot)
            moved = moved + 1
        end
    end
    return moved
end)

-- Lifecycle

AddEventHandler('bs:hook:player:spawned', function(player)
    -- Hook payloads are serialised copies without methods, so the meta flag is cleared through bs_core's export instead of player:SetMeta.
    local pending = player.metadata and player.metadata.pendingLoadout

    if pending and #pending > 0 then
        -- Cleared first, so a second spawn event cannot grant the same list again.
        exports.bs_core:SetPlayerMeta(player.source, 'pendingLoadout', nil)
        for _, entry in ipairs(pending) do
            Inv.Give(player.source, entry.item, entry.amount or 1)
        end
    end

    -- pendingLoadout lands in the bag; pendingEquip is for garments that should already be worn when the character is created.
    local pendingEquip = player.metadata and player.metadata.pendingEquip

    if pendingEquip and #pendingEquip > 0 then
        for _, itemName in ipairs(pendingEquip) do
            Inv.Equip(player.source, itemName)
        end
        exports.bs_core:SetPlayerMeta(player.source, 'pendingEquip', nil)
    end

    Inv.Push(player.source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    openContainers[src], openedAt[src], containerGrants[src] = nil, nil, nil
    local player = exports.bs_core:GetPlayer(src)
    -- A committing trade still owns this cache until its transaction resolves; dropping it now would leave the other trader with stale rows.
    if player and not Inv.TradeLockedOwner[tostring(player.charId)] then
        cache[key('character', player.charId)] = nil
    end
end)

-- Using a tool up. Called by whatever made the tool work (mining, felling), never by the client. Wears the most worn copy first and returns the life left and whether it just broke.
exports('WearItem', function(src, itemName, amount)
    local inv = playerInventory(src)
    if not inv then return false end

    local def = Items.Get(itemName)
    local max = def and def.data and tonumber(def.data.durability)
    if not max then return false end

    amount = math.max(1, math.floor(tonumber(amount) or 1))

    local worst, worstSlot = nil, nil
    for _, slot in ipairs(sortedSlots(inv)) do
        local entry = inv.slots[slot]
        if entry and entry.item == itemName then
            local life = tonumber(entry.durability) or max
            if not worst or life < worst then worst, worstSlot = life, slot end
        end
    end

    if not worstSlot then return false end

    local left = worst - amount
    local broke = left <= 0

    if broke then
        local entry = inv.slots[worstSlot]
        entry.amount = entry.amount - 1
        if entry.amount <= 0 then
            inv.slots[worstSlot] = nil
        else
            -- A stack of tools: the broken one goes, the next is fresh.
            entry.durability = max
        end
        left = 0
    else
        inv.slots[worstSlot].durability = left
    end

    persistSlot(inv, worstSlot)
    Inv.Push(src)

    return true, left, broke
end)

-- Wears out clothing after a hit (called by bs_zombies on a bite). Only garments that actually stopped damage take wear.
exports('WearEquipment', function(src, amount)
    if not Clothing or not Clothing.Aggregate then return false end

    local inv = playerInventory(src)
    if not inv then return false end

    amount = tonumber(amount) or (Clothing.Condition.perBite or 1.5)
    if amount <= 0 then return false end

    local _, breakdown = Clothing.Aggregate(equipmentEntries(inv))

    -- Who stopped anything, and how much of the total each was worth.
    local contributors, sum = {}, 0.0
    for slotId, one in pairs(breakdown) do
        local stopped = tonumber(one.armour) or 0.0
        if stopped > 0 then
            contributors[#contributors + 1] = { slot = slotId, share = stopped }
            sum = sum + stopped
        end
    end

    if sum <= 0 then return false end

    local max = Clothing.Condition.max or 100
    local touched = false

    for _, c in ipairs(contributors) do
        local index = Clothing.OrderOf[c.slot]
        local slot = index and (slotCount() + BAR_SLOTS + index)
        local entry = slot and inv.slots[slot]

        if entry then
            local now = tonumber(entry.durability) or max
            local cost = amount * (c.share / sum)
            local left = math.max(0, now - cost)

            if left ~= now then
                entry.durability = left
                persistSlot(inv, slot)
                touched = true
            end
        end
    end

    if touched then Inv.Push(src) end
    return touched
end)

-- Net entry point for the above. The amount is not trusted but only lightly guarded: lying only wears your own clothes faster. The rate limit protects the database; the clamp is secondary.
local wearRate = {}

RegisterNetEvent('bs:inventory:wearWorn', function(stopped)
    local src = source
    local now = os.time()

    if wearRate[src] == now then return end
    wearRate[src] = now

    local amount = tonumber(stopped)
    if not amount or amount <= 0 then return end

    -- The bite wears the coat, not the number the client sent.
    local per = (Clothing and Clothing.Condition and Clothing.Condition.perBite) or 1.5
    exports.bs_inventory:WearEquipment(src, math.min(per, amount))
end)

AddEventHandler('playerDropped', function() wearRate[source] = nil end)

-- Measured containers (jerrycan, bottle): fuel is a quantity held in a container, not an item. All diesel is gathered with a jerrycan or an empty bottle, and pouring empties the container instead of consuming it.

local function measuredCapacity(itemName)
    local def = Items.Get(itemName)
    local cap = def and def.data and tonumber(def.data.capacity)
    return (cap and cap > 0) and cap or nil
end

-- Every container slot for these item names, fullest first.
local function containersFor(inv, names)
    local want = {}
    if type(names) == 'string' then want[names] = true
    else for _, n in ipairs(names or {}) do want[n] = true end end

    local out = {}
    for _, slot in ipairs(sortedSlots(inv)) do
        local entry = inv.slots[slot]
        if entry and want[entry.item] then
            local cap = measuredCapacity(entry.item)
            if cap then
                out[#out + 1] = { slot = slot, entry = entry, cap = cap,
                                  level = tonumber(entry.durability) or 0 }
            end
        end
    end

    table.sort(out, function(a, b) return a.level > b.level end)
    return out
end

-- How much of a thing the player is carrying, and how much room is left.
exports('MeasuredInfo', function(src, names)
    local inv = playerInventory(src)
    if not inv then return { held = 0, room = 0, containers = 0 } end

    local held, room, count = 0, 0, 0
    for _, c in ipairs(containersFor(inv, names)) do
        held = held + c.level
        room = room + (c.cap - c.level)
        count = count + 1
    end

    return { held = held, room = room, containers = count }
end)

-- Pours in. Tops up the fullest container first. Returns how much actually went in, so callers can tell when the source had more than you could carry.
exports('PourInto', function(src, names, amount)
    local inv = playerInventory(src)
    if not inv then return 0 end

    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    local stored = 0
    for _, c in ipairs(containersFor(inv, names)) do
        if stored >= amount then break end

        local room = c.cap - c.level
        if room > 0 then
            local put = math.min(room, amount - stored)
            c.entry.durability = c.level + put
            stored = stored + put
            persistSlot(inv, c.slot)
        end
    end

    if stored > 0 then Inv.Push(src) end
    return stored
end)

-- Draws out from the fullest container first, which keeps the most containers usable.
exports('PourOut', function(src, names, amount)
    local inv = playerInventory(src)
    if not inv then return 0 end

    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    local drawn = 0
    for _, c in ipairs(containersFor(inv, names)) do
        if drawn >= amount then break end

        if c.level > 0 then
            local take = math.min(c.level, amount - drawn)
            c.entry.durability = c.level - take
            drawn = drawn + take
            persistSlot(inv, c.slot)
        end
    end

    if drawn > 0 then Inv.Push(src) end
    return drawn
end)

-- Which box of rounds feeds a weapon. Lives here because `Items` is global only in this resource's Lua state; other resources must use this export.
local ammoByWeapon = nil

exports('AmmoItemFor', function(weaponName)
    if type(weaponName) ~= 'string' or weaponName == '' then return nil end

    if not ammoByWeapon then
        ammoByWeapon = {}
        for itemName, def in pairs(Items.Definitions or {}) do
            local list = def.data and def.data.ammoFor
            if type(list) == 'table' then
                for _, weapon in ipairs(list) do
                    ammoByWeapon[string.upper(weapon)] = itemName
                end
            end
        end
    end

    return ammoByWeapon[string.upper(weaponName)]
end)

-- The label and rounds-per-box for an item, so a caller can describe what it handed over without needing Items.
exports('ItemBlurb', function(itemName, src)
    local def = Items.Definitions and Items.Definitions[itemName]
    if not def then return nil end
    return { label = ItemLabel(itemName, tonumber(src)),
             rounds = def.data and def.data.rounds or nil }
end)

exports('GiveItem', function(src, item, amount, metadata)
    return Inv.Give(src, item, amount, type(metadata) == 'table' and metadata or nil)
end)

-- Same add logic as GiveItem, but without an immediate inventory sync.
-- Used by container looting so several loot rolls can be inserted first and
-- the complete inventory is pushed to the client only once at the end.
exports('GiveItemSilent', function(src, item, amount, metadata)
    local inv = playerInventory(src)
    if not inv then return false, 'no character' end
    return addToInv(inv, item, amount, type(metadata) == 'table' and metadata or nil)
end)
exports('RemoveItem', function(src, item, amount) return Inv.Remove(src, item, amount) end)

-- Booster / gadget loadout: the item itself sits in a 901+ slot, off the grid.

local function loadoutSlot(kind, index)
    local L = LOADOUT[kind]
    index = math.tointeger(tonumber(index))
    if not L or not index or index < 1 or index > L.count then return nil end
    return L.from + index - 1
end

local function relocate(inv, fromSlot, toSlot, entry)
    inv.slots[fromSlot] = nil
    entry.slot, entry.id = toSlot, nil
    inv.slots[toSlot] = entry
    persistSlot(inv, fromSlot)
    persistSlot(inv, toSlot)
end

-- Back to the first free grid space; false when the bag is full.
local function backToGrid(inv, slot)
    local entry = inv.slots[slot]
    if not entry then return true end
    local free = firstFreeSlot(inv)
    if not free then return false end
    local def = Items.Get(entry.item) or {}
    local x, y, rot = Grid.FirstFit(gridBounds(inv), gridEntries(inv),
        { id = free, w = def.w or 1, h = def.h or 1 }, true)
    if not x then return false end
    entry.x, entry.y, entry.rot = x, y, rot
    relocate(inv, slot, free, entry)
    return true
end

exports('LoadoutGet', function(src, kind)
    local out, L = {}, LOADOUT[kind]
    local inv = playerInventory(src, true)
    if not inv or not L then return out end
    for i = 1, L.count do
        local e = inv.slots[L.from + i - 1]
        out[i] = e and { item = e.item, amount = e.amount, metadata = copyTable(e.metadata) } or false
    end
    return out
end)

-- Moves a stack of `item` out of the bag/bar into the slot. Returns ok, err.
exports('LoadoutSet', function(src, kind, index, item, silent)
    local inv = playerInventory(src)
    if not inv then return false, 'no character' end
    local slot = loadoutSlot(kind, index)
    if not slot or type(item) ~= 'string' then return false, 'bad slot' end

    local def = Items.Get(item) or {}
    local cur = inv.slots[slot]
    local pick, bar = nil, (inv.gridSlots or 0)
    for _, s in ipairs(sortedSlots(inv)) do
        local e = inv.slots[s]
        if e.item == item and (isBagSlot(inv, s) or (s > bar and s <= bar + BAR_SLOTS)) then
            pick = s break
        end
    end
    if not pick then return false, 'You are not carrying that.' end

    if cur and cur.item == item then
        -- Top up the slotted stack.
        local room = (def.stack or 1) - cur.amount
        if room <= 0 then return false, 'That slot is full.' end
        local e = inv.slots[pick]
        local put = math.min(room, e.amount)
        cur.amount, e.amount = cur.amount + put, e.amount - put
        if e.amount <= 0 then inv.slots[pick] = nil end
        persistSlot(inv, pick); persistSlot(inv, slot)
    else
        if cur and not backToGrid(inv, slot) then return false, 'No room in your bag to swap.' end
        local e = inv.slots[pick]
        e.x, e.y, e.rot = nil, nil, false
        relocate(inv, pick, slot, e)
    end
    if not silent then Inv.Push(src) end
    return true
end)

exports('LoadoutClear', function(src, kind, index)
    local inv = playerInventory(src)
    if not inv then return false, 'no character' end
    local slot = loadoutSlot(kind, index)
    if not slot then return false, 'bad slot' end
    if not backToGrid(inv, slot) then return false, 'No room in your bag.' end
    Inv.Push(src)
    return true
end)

-- Spends from the slotted stack. Returns true only if the full amount was there.
exports('LoadoutTake', function(src, kind, index, amount, item)
    local inv = playerInventory(src)
    if not inv then return false end
    local slot = loadoutSlot(kind, index)
    local e = slot and inv.slots[slot]
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if not e or e.amount < amount or (item and e.item ~= item) then return false end
    local meta = copyTable(e.metadata) or {}
    e.amount = e.amount - amount
    if e.amount <= 0 then inv.slots[slot] = nil end
    persistSlot(inv, slot)
    Inv.Push(src)
    return true, meta
end)

-- Puts one item (with metadata) straight back into an empty loadout slot.
exports('LoadoutPut', function(src, kind, index, item, metadata)
    local inv = playerInventory(src)
    if not inv then return false end
    local slot = loadoutSlot(kind, index)
    if not slot or inv.slots[slot] or not Items.Get(item) then return false end
    inv.slots[slot] = { item = item, amount = 1, slot = slot, metadata = copyTable(metadata) or {}, x = nil, y = nil, rot = false }
    persistSlot(inv, slot)
    Inv.Push(src)
    return true
end)

-- Every stack of `item` the player holds (bag, bar, loadout): { slot, amount, metadata }.
exports('ItemMetaList', function(src, item)
    local out = {}
    local inv = playerInventory(src, true)
    if not inv then return out end
    for slot, e in pairs(inv.slots) do
        if e.item == item then out[#out + 1] = { slot = slot, amount = e.amount, metadata = copyTable(e.metadata) or {} } end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end)

-- Replaces the metadata of one slot, if it still holds `item`.
exports('SetItemMeta', function(src, slot, item, metadata, silent)
    local inv = playerInventory(src)
    slot = math.tointeger(tonumber(slot))
    local e = inv and slot and inv.slots[slot]
    if not e or e.item ~= item or type(metadata) ~= 'table' then return false end
    e.metadata = copyTable(metadata)
    persistSlot(inv, slot)
    if not silent then Inv.Push(src) end
    return true
end)
-- Removes one unit from a given slot, if it still holds `item`. For items whose metadata matters (batteries).
exports('RemoveSlot', function(src, slot, item)
    local inv = playerInventory(src)
    slot = math.tointeger(tonumber(slot))
    local e = inv and slot and inv.slots[slot]
    if not e or e.item ~= item then return false end
    e.amount = e.amount - 1
    if e.amount <= 0 then inv.slots[slot] = nil end
    persistSlot(inv, slot)
    Inv.Push(src)
    return true
end)
exports('CountItem', function(src, item) return Inv.Count(src, item) end)
exports('Refresh', function(src) return Inv.Push(src) end)

exports.bs_core:RegisterModule('inventory', { side = 'server', version = '0.2.0' })

-- World drops. A dropped stack becomes an object anyone can pick up. The server owns the list; clients spawn props for nearby drops locally, so a drop costs no networked entity.

local drops = {}          -- [dropId] = { id, item, amount, coords, at, by }
local dropMeta = {}       -- [dropId] = metadata, kept server-side (never broadcast)
local dropSeq = 0

-- Caps the nearby-drop payload per call; the decay thread keeps the total count sane over time.
local NEARBY_DROPS_MAX = 150

local function nearbyDrops(coords, radius)
    local out = {}
    local n = 0
    for _, drop in pairs(drops) do
        local dx, dy, dz = drop.coords.x - coords.x, drop.coords.y - coords.y, drop.coords.z - coords.z
        if (dx * dx + dy * dy + dz * dz) <= radius * radius then
            n = n + 1
            out[n] = drop
            if n >= NEARBY_DROPS_MAX then break end
        end
    end
    return out
end

-- Broadcasts the drop list to everyone near it. The list is tiny, so sending the whole nearby set is simpler than deltas.
local function broadcastDrop(drop, removed)
    TriggerClientEvent('bs:inventory:drop' .. (removed and 'Removed' or 'Added'), -1, drop)
end

BSB.RegisterCallback('inventory:dropWorld', function(src, slot, amount, coords)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end

    local entry = inv.slots[tonumber(slot)]
    if not entry then return { ok = false, error = 'nothing there' } end
    if not packCanLeave(inv, tonumber(slot)) then return { ok = false, error = PACK_FULL } end

    amount = math.max(1, math.min(math.floor(tonumber(amount) or entry.amount), entry.amount))

    -- The drop must be within a couple of metres of where the server thinks the player is, Z included, so a client cannot drop items on other floors.
    local ped = GetPlayerPed(src)
    local real = GetEntityCoords(ped)
    if type(coords) ~= 'table' then coords = { x = real.x, y = real.y, z = real.z } end
    local dx, dy, dz = (coords.x or 0) - real.x, (coords.y or 0) - real.y, (coords.z or 0) - real.z
    if (dx * dx + dy * dy + dz * dz) > 9.0 then
        coords = { x = real.x, y = real.y, z = real.z }
    end

    entry.amount = entry.amount - amount
    local item = entry.item
    local meta = copyTable(entry.metadata)
    if entry.amount <= 0 then inv.slots[tonumber(slot)] = nil end
    persistSlot(inv, tonumber(slot))
    Inv.Push(src)

    dropSeq = dropSeq + 1
    local def = Items.Get(item) or {}
    local drop = {
        id = ('d%d'):format(dropSeq),
        item = item,
        label = def.label or item,
        category = def.category or 'misc',
        amount = amount,
        coords = coords,
        at = os.time(),
    }
    drops[drop.id] = drop
    -- A dropped bag has to still be the same bag when it is picked up.
    if meta and next(meta) ~= nil then dropMeta[drop.id] = meta end
    broadcastDrop(drop, false)

    return { ok = true, drop = drop }
end)

BSB.RegisterCallback('inventory:pickup', function(src, dropId)
    local drop = drops[dropId]
    if not drop then return { ok = false, error = Lp(src, 'inv.e_gone') } end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = drop.coords.x - coords.x, drop.coords.y - coords.y, drop.coords.z - coords.z
    if (dx * dx + dy * dy + dz * dz) > 9.0 then return { ok = false, error = Lp(src, 'inv.e_far') } end

    local ok, label = Inv.Give(src, drop.item, drop.amount, dropMeta[dropId])
    if not ok then return { ok = false, error = label } end

    drops[dropId] = nil
    dropMeta[dropId] = nil
    broadcastDrop(drop, true)
    return { ok = true, label = label, amount = drop.amount, item = drop.item }
end)

BSB.RegisterCallback('inventory:nearbyDrops', function(src)
    local coords = GetEntityCoords(GetPlayerPed(src))
    return { ok = true, drops = nearbyDrops(coords, 120.0) }
end)

-- Giving to another player: both must be close, and the receiver must have room.
BSB.RegisterCallback('inventory:give', function(src, slot, amount, targetSrc)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end

    targetSrc = tonumber(targetSrc)
    local target = targetSrc and exports.bs_core:GetPlayer(targetSrc)
    if not target then return { ok = false, error = Lp(src, 'inv.e_not_here') } end
    if targetSrc == src then return { ok = false, error = Lp(src, 'inv.e_you') } end

    local a, b = GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(targetSrc))
    if #(a - b) > 3.5 then return { ok = false, error = Lp(src, 'trade.e_closer') } end

    local entry = inv.slots[tonumber(slot)]
    if not entry then return { ok = false, error = 'nothing there' } end
    if not packCanLeave(inv, tonumber(slot)) then return { ok = false, error = PACK_FULL } end

    amount = math.max(1, math.min(math.floor(tonumber(amount) or entry.amount), entry.amount))
    local item = entry.item

    local ok, label = Inv.Give(targetSrc, item, amount)
    if not ok then return { ok = false, error = Lp(src, 'inv.e_cant_carry', { why = label or '' }) } end

    entry.amount = entry.amount - amount
    if entry.amount <= 0 then inv.slots[tonumber(slot)] = nil end
    persistSlot(inv, tonumber(slot))
    Inv.Push(src)

    TriggerClientEvent('bs:ui:notify', targetSrc, {
        type = 'success',
        message = Lp(targetSrc, 'inv.gave_you', {
            name = (exports.bs_core:GetPlayer(src) or {}).name or Lp(targetSrc, 'inv.someone'),
            n = amount, item = ItemLabel(item, targetSrc) }),
        itemImage = item,
    })
    return { ok = true }
end)

-- Who is standing close enough to hand something to.
BSB.RegisterCallback('inventory:nearbyPlayers', function(src)
    local coords = GetEntityCoords(GetPlayerPed(src))
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src then
            local player = exports.bs_core:GetPlayer(id)
            if player and #(GetEntityCoords(GetPlayerPed(id)) - coords) <= 3.5 then
                out[#out + 1] = { source = id, name = player.name }
            end
        end
    end
    return { ok = true, players = out }
end)

-- New arrivals need the drops that already exist near them.
AddEventHandler('bs:hook:player:spawned', function(player)
    local coords = GetEntityCoords(GetPlayerPed(player.source))
    TriggerClientEvent('bs:inventory:dropSync', player.source, nearbyDrops(coords, 200.0))
end)

-- Drops decay so the map does not fill with backpacks forever.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local life = Inventory.Settings.dropLifetime or 1800
        for id, drop in pairs(drops) do
            -- A backpack dropped on death stays until restart, unless the F1 option says 30 minutes.
            local keep = drop.pack and not Inventory.Settings.packDropDespawn
            local limit = drop.pack and (Inventory.Settings.packDropLifetime or 1800) or life
            if not keep and now - drop.at > limit then
                local meta = dropMeta[id]
                drops[id] = nil
                dropMeta[id] = nil
                broadcastDrop(drop, true)
                -- A despawned pack takes its contents with it.
                if drop.pack and meta and meta.bagId then
                    pcall(function() exports.bs_inventory:ContainerTakeAll('bag:' .. meta.bagId) end)
                end
            end
        end
    end
end)

-- Container helpers for bs_crafting / bs_recycler. All-or-nothing adds so a full box never eats half a stack.

local function removeFromInv(inv, itemName, amount)
    local have = 0
    for _, e in pairs(inv.slots) do if e.item == itemName then have = have + e.amount end end
    if have < amount then return false end
    local slots = {}
    for slot in pairs(inv.slots) do slots[#slots + 1] = slot end
    table.sort(slots, function(a, b) return a > b end)
    local left = amount
    for _, slot in ipairs(slots) do
        local e = inv.slots[slot]
        if e and e.item == itemName then
            local take = math.min(e.amount, left)
            e.amount = e.amount - take
            left = left - take
            if e.amount <= 0 then inv.slots[slot] = nil end
            persistSlot(inv, slot)
            if left <= 0 then break end
        end
    end
    return true
end

local function countIn(inv, itemName)
    local n = 0
    for _, e in pairs(inv.slots) do if e.item == itemName then n = n + e.amount end end
    return n
end

local function addAll(inv, itemName, amount, metadata)
    local before = countIn(inv, itemName)
    local ok = addToInv(inv, itemName, amount, metadata)
    if ok then return true end
    local delta = countIn(inv, itemName) - before
    if delta > 0 then removeFromInv(inv, itemName, delta) end
    return false
end

exports('ContainerCount', function(containerId, item)
    local inv = containerInv(containerId)
    return inv and countIn(inv, item) or 0
end)

exports('ContainerRemove', function(containerId, item, amount)
    local inv = containerInv(containerId)
    if not inv then return false end
    local ok = removeFromInv(inv, item, math.max(1, math.floor(tonumber(amount) or 1)))
    if ok then pushContainer(containerId) end
    return ok
end)

exports('ContainerGiveAll', function(containerId, item, amount, metadata)
    local inv = containerInv(containerId)
    if not inv then return false end
    local ok = addAll(inv, item, math.max(1, math.floor(tonumber(amount) or 1)), metadata)
    if ok then pushContainer(containerId) end
    return ok
end)

-- One unit off the first stack, metadata included (weapons keep their fitted attachments).
exports('ContainerTakeOne', function(containerId)
    local inv = containerInv(containerId)
    if not inv then return nil end
    local slots = {}
    for slot in pairs(inv.slots) do slots[#slots + 1] = slot end
    table.sort(slots)
    local slot = slots[1]
    if not slot then return nil end
    local e = inv.slots[slot]
    local out = { item = e.item, amount = 1, metadata = copyTable(e.metadata) }
    e.amount = e.amount - 1
    if e.amount <= 0 then inv.slots[slot] = nil end
    persistSlot(inv, slot)
    pushContainer(containerId)
    return out
end)

exports('GiveAll', function(src, item, amount, metadata)
    local inv = playerInventory(src)
    if not inv then return false end
    local ok = addAll(inv, item, math.max(1, math.floor(tonumber(amount) or 1)), metadata)
    Inv.Push(src)
    return ok
end)

-- Player bag move to/from a container in one server call (machine panels without drag and drop).
exports('MoveToContainer', function(src, item, amount, containerId)
    local inv = playerInventory(src)
    local box = containerInv(containerId)
    if not inv or not box then return false end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if Inv.Count(src, item) < amount then return false end
    if not addAll(box, item, amount) then return false end
    Inv.Remove(src, item, amount)
    pushContainer(containerId)
    return true
end)

exports('MoveFromContainer', function(src, item, amount, containerId)
    local inv = playerInventory(src)
    local box = containerInv(containerId)
    if not inv or not box then return false end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if countIn(box, item) < amount then return false end
    if not addAll(inv, item, amount) then return false end
    removeFromInv(box, item, amount)
    pushContainer(containerId)
    Inv.Push(src)
    return true
end)

-- Bag contents as { [item] = count }, bag and bar only (worn gear is left out).
exports('ItemCounts', function(src)
    local inv = playerInventory(src)
    local out = {}
    if not inv then return out end
    for slot, e in pairs(inv.slots) do
        if isBagSlot(inv, slot) or (slot > (inv.gridSlots or inv.size) and slot <= (inv.gridSlots or inv.size) + BAR_SLOTS) then
            out[e.item] = (out[e.item] or 0) + e.amount
        end
    end
    return out
end)


--------------------------------------------------------------------------------
-- Backpacks: death drop, looting a dropped pack, looting a downed player's pack, look picker
--------------------------------------------------------------------------------

local function guardLog(src, detail)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local player = exports.bs_core:GetPlayer(src)
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), player and player.charId or nil, (GetPlayerName(src) or '?'):sub(1, 64),
          'inventory', 50, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

-- Called from DeathTransfer before the wipe. The pack row is copied to a world drop with its metadata, so the bag id (and the contents) survive.
function Inv.DropPackOnDeath(src, entry)
    local def = Items.Get(entry.item) or {}
    entry.metadata = entry.metadata or {}
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector and GetEntityForwardVector(ped) or vector3(0, 0, 0)
    dropSeq = dropSeq + 1
    local drop = {
        id = ('d%d'):format(dropSeq),
        item = entry.item,
        label = def.label or entry.item,
        category = def.category or 'clothing',
        amount = 1,
        coords = { x = c.x - fwd.x * 0.8, y = c.y - fwd.y * 0.8, z = c.z },
        at = os.time(),
        pack = true,
    }
    drops[drop.id] = drop
    dropMeta[drop.id] = copyTable(entry.metadata)
    broadcastDrop(drop, false)
    return drop.id
end

-- Open a dropped pack where it lies, without picking it up.
BSB.RegisterCallback('inventory:openDropPack', function(src, dropId)
    local drop = drops[dropId]
    if not drop or not drop.pack then return { ok = false, error = Lp(src, 'inv.e_gone') } end
    local here = GetEntityCoords(GetPlayerPed(src))
    local dc = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    if #(here - dc) > 3.0 then return { ok = false, error = Lp(src, 'inv.e_far') } end
    local meta = dropMeta[dropId] or {}
    local def = Items.Get(drop.item)
    if not (def and def.data and def.data.bag) then return { ok = false } end
    if not meta.bagId then
        meta.bagId = ('%x%04x%04x'):format(os.time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
        dropMeta[dropId] = meta
    end
    local b = Inv.BagInv(meta.bagId, def)
    openContainers[src] = key('container', 'bag:' .. meta.bagId)
    -- pos, not bagId: walking away closes it like any other container.
    openedAt[src] = { pos = dc }
    Inv.Push(src)
    return { ok = true, container = serialise(b), label = b.label }
end)

-- Open another player's worn pack. Only while they are downed or cuffed (dead players drop theirs).
BSB.RegisterCallback('inventory:openPlayerPack', function(src, target)
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return { ok = false } end
    local st = Player(target).state
    if not (st.bsDowned or st.bsCuffed) then
        guardLog(src, ('openPlayerPack on %d who is not downed or cuffed'):format(target))
        return { ok = false, error = Lp(src, 'inv.e_pack_locked') }
    end
    local ped, tped = GetPlayerPed(src), GetPlayerPed(target)
    if ped == 0 or tped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(tped)) > 3.0 then
        return { ok = false, error = Lp(src, 'inv.e_far') }
    end
    local tinv = playerInventory(target, true)
    local b = tinv and wornBag(tinv, 'backpack')
    if not b then return { ok = false, error = Lp(src, 'inv.e_no_pack') } end
    openContainers[src] = key('container', 'bag:' .. b.bagId)
    openedAt[src] = { pos = GetEntityCoords(tped) }
    Inv.Push(src)
    return { ok = true, container = serialise(b), label = b.label }
end)

-- Pick a look for the worn pack, or hide it. The look must be unlocked by the pack's tier.
BSB.RegisterCallback('inventory:packLook', function(src, look, hidden)
    local inv = playerInventory(src)
    if not inv then return { ok = false } end
    local slot = packSlot()
    local e = slot and inv.slots[slot]
    local def = e and Items.Get(e.item)
    if not (def and def.data and def.data.bag) then return { ok = false, error = Lp(src, 'inv.e_no_pack') } end
    e.metadata = e.metadata or {}
    look = tonumber(look)
    if look then
        local L = Clothing.PackLooks and Clothing.PackLooks[look]
        if not L or (L.tier or 1) > (tonumber(def.data.tier) or 1) then
            return { ok = false, error = Lp(src, 'inv.e_look_locked') }
        end
        e.metadata.look = look
    end
    if hidden ~= nil then e.metadata.hidden = hidden == true or nil end
    persistSlot(inv, slot)
    Inv.Push(src)
    return { ok = true }
end)

-- A revive from the downed/bleedout state bypasses the full death inventory wipe.
-- Clear only the persisted equipped-weapon metadata; keep every inventory item.
RegisterNetEvent('bs:inventory:reviveHandCleanup', function()
    local src = source
    if GetResourceState('bs_core') ~= 'started' then return end
    pcall(function() exports.bs_core:SetPlayerMeta(src, 'lastWeapon', nil) end)
    pcall(function() exports.bs_core:SavePlayer(src, true) end)
end)
