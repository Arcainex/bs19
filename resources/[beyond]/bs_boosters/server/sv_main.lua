-- Server authority for boosters: loadout, item consumption, cooldowns. Nothing here targets or damages a player.

local lastUse = {}      -- src -> GetGameTimer() of last accepted use
-- Cooldowns live in character metadata as { [item] = readyAt (os.time) } so a relog cannot reset them.
local CD_KEY = 'booster_cd'

local function notify(src, msg, kind)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = msg, duration = 3000 })
end

local function inv() return GetResourceState('bs_inventory') == 'started' end

-- Faction skills booster_cd/booster_cd2: % off booster cooldown (max 60%).
local function cdCut(src)
    if GetResourceState('bs_factions') ~= 'started' then return 0 end
    local ok, n = pcall(function()
        local s = exports.bs_factions:GetFactionSummary(tonumber(src))
        if type(s) ~= 'table' or not s.factionId then return 0 end
        return (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'booster_cd')) or 0)
             + (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'booster_cd2')) or 0)
    end)
    return ok and math.max(0, math.min(60, tonumber(n) or 0)) or 0
end

local function countOf(src, item)
    if not inv() then return 0 end
    local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
    return (ok and tonumber(n)) or 0
end

-- The loadout lives in bs_inventory (items in off-grid slots). Old metadata loadouts are migrated once and the carried items leave the grid.
local function migrate(src)
    local raw = exports.bs_core:GetPlayerMeta(src, Boosters.MetaKey, nil)
    if type(raw) ~= 'table' or next(raw) == nil then return false end
    local busy = false
    for i = 1, Boosters.Slots do
        local v = raw[i] or raw[tostring(i)]
        if type(v) == 'string' and Boosters.IsBooster(v) then
            local ok, done, err = pcall(function() return exports.bs_inventory:LoadoutSet(src, 'booster', i, v, true) end)
            if ok and not done and err == 'no character' then busy = true end
        end
    end
    -- Keep the old list if the inventory was locked (mid-trade); retry later.
    if busy then return false end
    exports.bs_core:SetPlayerMeta(src, Boosters.MetaKey, nil)
    return true
end

-- index -> { item, amount } or false
local function slots(src)
    local out = {}
    if not inv() then return out end
    local get = function() return exports.bs_inventory:LoadoutGet(src, 'booster') end
    local ok, lo = pcall(get)
    -- Only migrate once the character's inventory is loaded.
    if ok and type(lo) == 'table' and lo[1] ~= nil and migrate(src) then ok, lo = pcall(get) end
    for i = 1, Boosters.Slots do
        local e = ok and type(lo) == 'table' and lo[i] or nil
        if type(e) == 'table' and e.item and not Boosters.IsBooster(e.item) then
            -- No longer a booster (riot shield is a gadget): back to the bag.
            pcall(function() exports.bs_inventory:LoadoutClear(src, 'booster', i) end)
            e = nil
        end
        out[i] = (type(e) == 'table' and Boosters.IsBooster(e.item)) and e or false
    end
    return out
end

local function loadout(src)
    local out = {}
    for i, e in ipairs(slots(src)) do out[i] = e and e.item or false end
    return out
end

local function getCds(src)
    local raw = exports.bs_core:GetPlayerMeta(src, CD_KEY, nil)
    local out, now = {}, os.time()
    if type(raw) == 'table' then
        for item, t in pairs(raw) do
            t = tonumber(t)
            if t and t > now and Boosters.IsBooster(item) then out[item] = t end
        end
    end
    return out
end

local function setCd(src, item, readyAt)
    local cds = getCds(src)   -- also drops expired entries
    cds[item] = readyAt
    exports.bs_core:SetPlayerMeta(src, CD_KEY, cds)
end

local function payload(src)
    local lo = slots(src)
    local now = os.time()
    local cds = getCds(src)
    local out = {}
    for i = 1, Boosters.Slots do
        local e = lo[i]
        local item = e and e.item
        if item then
            local t = Boosters.Types[item]
            out[tostring(i)] = {
                item = item, label = t.label, kind = t.kind,
                count = e.amount or 0,
                cooldown = math.max(0, (cds[item] or 0) - now),
            }
        else
            out[tostring(i)] = false
        end
    end
    return out
end

local function push(src)
    TriggerClientEvent('bs:boosters:loadout', src, payload(src))
end
exports('Push', push)
exports('Loadout', loadout)

RegisterNetEvent('bs:boosters:request', function() push(source) end)

RegisterNetEvent('bs:boosters:setSlot', function(index, item)
    local src = source
    index = math.tointeger(tonumber(index))
    if not index or index < 1 or index > Boosters.Slots or not inv() then return end
    local ok, err
    if item == nil or item == false or item == '' then
        ok, err = exports.bs_inventory:LoadoutClear(src, 'booster', index)
    elseif type(item) ~= 'string' or not Boosters.IsBooster(item) then
        ok, err = false, 'Only boosters fit in a booster slot.'
    else
        ok, err = exports.bs_inventory:LoadoutSet(src, 'booster', index, item)
    end
    if not ok then notify(src, err or Lp(src, 'bo.could_not'), 'error') end
    push(src)
end)

RegisterNetEvent('bs:boosters:use', function(index)
    local src = source
    index = math.tointeger(tonumber(index))
    if not index or index < 1 or index > Boosters.Slots then return end

    local now = GetGameTimer()
    if lastUse[src] and now - lastUse[src] < Boosters.UseDelayMs then return end

    local item = loadout(src)[index]
    if not item then notify(src, Lp(src, 'bo.slot_empty')); return end
    local t = Boosters.Types[item]

    local ready = getCds(src)[item] or 0
    if os.time() < ready then
        notify(src, Lp(src, 'boost.recharging', { name = t.label, n = ready - os.time() }), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped ~= 0 and GetEntityHealth(ped) <= 0 then return end

    local ok = false
    if inv() then
        local okCall, res = pcall(function() return exports.bs_inventory:LoadoutTake(src, 'booster', index, 1, item) end)
        ok = okCall and res and true or false
    end
    if not ok then notify(src, Lp(src, 'bo.none_left', { name = (function() local k = 'booster.' .. tostring(t.kind); local s = Lp(src, k); return s ~= k and s or t.label end)() }), 'error'); push(src); return end

    lastUse[src] = now
    setCd(src, item, os.time() + math.max(1, math.floor(t.cooldown * (1 - cdCut(src) / 100))))

    TriggerClientEvent('bs:boosters:activate', src, item, t)
    push(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastUse[src] = nil
end)
