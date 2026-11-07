-- bs_traders - vendor stock, server-side only. Loaded before sv_traders.lua because every buy goes through Stock.Take.
-- Restock runs per trader: npc.restock seconds (0 = Traders.Settings.restockInterval). A row with
-- restockAmount adds that many per interval up to its stock; without it the shelf is refilled in full.

Stock = {}

local current = {}   -- [npcId] = { items = { [item] = n|nil }, nextAt = os.time() }

local function intervalOf(npc)
    local n = tonumber(npc and npc.restock) or 0
    if n >= 30 then return n end
    return Traders.Settings.restockInterval or 3600
end

-- Seeded from the effective npc (config + editor overrides), so editor-made npcs also get a shelf.
local function seedOne(npcId)
    local npc = Registry.EffectiveNpc(npcId)
    if not npc then current[npcId] = nil; return end
    local items = {}
    for _, entry in ipairs(npc.sells or {}) do
        items[entry.item] = entry.stock   -- nil stays nil = unlimited
    end
    current[npcId] = { items = items, nextAt = os.time() + intervalOf(npc) }
end

local function seed()
    current = {}
    for _, npcId in ipairs(Registry.AllNpcIds()) do seedOne(npcId) end
end

local function restockOne(npcId)
    local npc = Registry.EffectiveNpc(npcId)
    local shelf = current[npcId]
    if not npc or not shelf then return end
    for _, entry in ipairs(npc.sells or {}) do
        local max = tonumber(entry.stock)
        if max then
            local add = tonumber(entry.restockAmount) or 0
            if add > 0 then
                shelf.items[entry.item] = math.min(max, (shelf.items[entry.item] or 0) + add)
            else
                shelf.items[entry.item] = max
            end
        else
            shelf.items[entry.item] = nil
        end
    end
    shelf.nextAt = os.time() + intervalOf(npc)
end

--- Refills one npc's shelf from its current definition. Called after an
--- editor save, duplicate or reset.
function Stock.Reseed(npcId)
    seedOne(npcId)
end

-- Overrides load asynchronously, so seed on first touch instead of refusing.
local function shelfOf(npcId)
    if current[npcId] == nil then seedOne(npcId) end
    return current[npcId] and current[npcId].items
end

-- Remaining stock for one item, or nil if not sold here or unlimited. Check separately that the item is sold here.
function Stock.Get(npcId, item)
    local shelf = shelfOf(npcId)
    return shelf and shelf[item]
end

--- Attempts to take `qty` off the shelf. Returns true and decrements if
--- unlimited or sufficient; returns false and changes nothing otherwise.
function Stock.Take(npcId, item, qty)
    local shelf = shelfOf(npcId)
    if not shelf then return false end

    local have = shelf[item]
    if have == nil then return true end          -- unlimited stock
    if have < qty then return false end

    shelf[item] = have - qty
    return true
end

CreateThread(function()
    seed()
    while true do
        Wait(15000)
        local now = os.time()
        for npcId, shelf in pairs(current) do
            if shelf.nextAt <= now then restockOne(npcId) end
        end
    end
end)
