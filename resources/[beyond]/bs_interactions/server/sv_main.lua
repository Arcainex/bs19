-- bs_interactions - container state and loot rolls.

local searched = {}     -- [key] = os.time() when it was emptied
local inFlight = {}     -- [key] = source, while a search is running
local tickets = {}
local checkedAt = {}    -- [key] = os.time() when containers:check last succeeded

local function typeDef(typeId) return Containers.Types[typeId] end

-- `key` ("x.x:y.y:z.z") is built client-side from the targeted entity
local CONTAINER_PROXIMITY = 4.0 -- matches cl_search.lua's searchOption distance (2.4) plus movement slack

local function parseKey(key)
    if type(key) ~= 'string' or #key > 64 then return nil end
    local x, y, z = key:match('^(%-?%d+%.?%d*):(%-?%d+%.?%d*):(%-?%d+%.?%d*)$')
    if not x then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

local function nearKey(src, key)
    local x, y, z = parseKey(key)
    if not x then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped)<=0 then return false end

    local at = GetEntityCoords(ped)
    local dx, dy, dz = at.x - x, at.y - y, at.z - z
    return (dx * dx + dy * dy + dz * dz) <= (CONTAINER_PROXIMITY * CONTAINER_PROXIMITY)
end

-- Ownership check: is the boot at this key somebody's own car?
local function bootIsOwned(key)
    if GetResourceState('bs_vehicles') ~= 'started' then return false end

    local x, y, z = parseKey(key)
    if not x then return false end

    local ok, owned = pcall(function()
        local best, bestDist = nil, 9.0        -- 3m, squared

        for _, vehicle in ipairs(GetAllVehicles()) do
            if DoesEntityExist(vehicle) then
                local c = GetEntityCoords(vehicle)
                local dx, dy, dz = c.x - x, c.y - y, c.z - z
                local d = dx * dx + dy * dy + dz * dz
                if d < bestDist then best, bestDist = vehicle, d end
            end
        end

        if not best then return false end

        local plate = GetVehicleNumberPlateText(best)
        if type(plate) ~= 'string' then return false end
        plate = plate:gsub('%s+$', '')

        local record = exports.bs_vehicles:Get(plate)
        return (record and record.owned) and true or false
    end)

    return ok and owned or false
end

local function cooldownLeft(typeId, key)
    local at = searched[key]
    if not at then return 0 end
    local def = typeDef(typeId)
    local window = (def and def.respawn) or Containers.Settings.defaultRespawn
    local left = (at + window) - os.time()
    return left > 0 and left or 0
end

-- Sweep old entries so `searched` and `checkedAt` do not grow forever.
local MAX_RESPAWN = Containers.Settings.defaultRespawn or 1800
for _, def in pairs(Containers.Types) do
    if def.respawn and def.respawn > MAX_RESPAWN then MAX_RESPAWN = def.respawn end
end

CreateThread(function()
    while true do
        Wait(300000) -- five minutes: this is cold housekeeping, not a hot path

        local cutoff = os.time() - MAX_RESPAWN
        for key, at in pairs(searched) do
            if at < cutoff then searched[key] = nil end
        end

        local now = os.time()
        for key, at in pairs(checkedAt) do
            if (now - at) > 600 then checkedAt[key] = nil end
        end
    end
end)

-- Rolls a loot table from bs_economy's config, server-side so the table never reaches a player.
local function lootBonus(src)
    if GetResourceState('bs_skills') ~= 'started' then return 0 end
    local ok, value = pcall(function() return exports.bs_skills:LootBonus(src) end)
    return (ok and type(value) == 'number') and value or 0
end

-- Faction sanction drop_penalty: chance each rolled item is kept (1.0 = all).
local function dropKeep(src)
    if GetResourceState('bs_faction_bases') ~= 'started' then return 1.0 end
    local ok, value = pcall(function() return exports.bs_faction_bases:DropMultiplier(src) end)
    return (ok and type(value) == 'number') and value or 1.0
end

local function lootPreset()
    local id=BSConfigGet and BSConfigGet('Scavenge.difficulty',Scavenge.difficulty)or Scavenge.difficulty
    return Scavenge.presets[id]or Scavenge.presets.medium
end
local function itemWeight(entry,preset)
    local definition=exports.bs_inventory:GetItem(entry.item)
    if not definition then return 0 end
    local data=definition.data or {}
    local firearm=type(data.spawnRounds)=='number'and not data.throwable
    local multiplier=firearm and preset.firearms or (definition.category=='attachment'or entry.item=='gun_parts')and preset.parts or definition.category=='ammo'and preset.ammo or 1
    return math.max(0,tonumber(entry.weight)or 0)*multiplier
end
local function rollLoot(tableId, src, single)
    local tbl = exports.bs_economy:GetLootTable(tableId)
    if not tbl then return {} end
    local preset=lootPreset()
    local keep = single and 1 or dropKeep(src)

    local rolls = math.random(tbl.rolls and tbl.rolls.min or 0, tbl.rolls and tbl.rolls.max or 1)
        + (single and 0 or lootBonus(src))
    -- bs_config loot multipliers
    local lootMult = BSConfigGet and tonumber(BSConfigGet('Global.lootMultiplier', 1.0)) or 1.0
    local rollMult = BSConfigGet and tonumber(BSConfigGet('Global.lootRollsMultiplier', 1.0)) or 1.0
    rollMult=rollMult*preset.rolls
    if rollMult ~= 1.0 then rolls = math.floor(rolls * rollMult + math.random()) end
    if single then rolls=1 end
    rolls=math.max(0,math.min(32,rolls))
    local out = {}

    for _ = 1, rolls do
        local total = 0
        for _, entry in ipairs(tbl.entries or {}) do total = total + itemWeight(entry,preset) end
        if total <= 0 then break end

        local pick, acc = math.random() * total, 0
        for _, entry in ipairs(tbl.entries) do
            acc = acc + itemWeight(entry,preset)
            if pick <= acc then
                local min, max = entry.amount and entry.amount[1] or 1, entry.amount and entry.amount[2] or 1
                if keep >= 1.0 or math.random() < keep then
                    local amt = math.random(min, max)
                    if preset.amount~=1 then amt=math.max(1,math.floor(amt*preset.amount+math.random()))end
                    if lootMult ~= 1.0 then amt = math.max(1, math.floor(amt * lootMult + math.random())) end
                    local definition=exports.bs_inventory:GetItem(entry.item)
                    if definition and definition.data and definition.data.weapon then amt=1 end
                    out[#out + 1] = { item = entry.item, amount = amt }
                end
                break
            end
        end
    end

    return out
end

Containers.RollLoot=rollLoot

BSB.RegisterCallback('containers:check', function(src, typeId, key, model)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = Lp(src, 'search.no_character') } end

    local def = typeDef(typeId)
    if not def then return { ok = false, error = 'unknown container' } end
    if type(key) ~= 'string' or #key > 64 then return { ok = false, error = 'bad container' } end
    if not nearKey(src, key) then return { ok = false, error = Lp(src, 'search.too_far') } end

    if typeId == 'car_boot' and bootIsOwned(key) then
        return { ok = false, error = Lp(src, 'search.owned') }
    end

    if inFlight[key] and tickets[key] and GetGameTimer()>tickets[key].expires then inFlight[key]=nil;tickets[key]=nil end
    if inFlight[key] then return { ok = false, error = Lp(src, 'search.busy') } end

    local left = cooldownLeft(typeId, key)
    if left > 0 then
        return { ok = false, error = Lp(src, 'search.cooldown', { min = math.ceil(left / 60) }) }
    end

    if Containers.ResolveLoot then def=Containers.ResolveLoot(def,key,model) end
    if not def then return {ok=false,error='No searchable furniture here'} end
    for other,holder in pairs(inFlight) do if holder==src then inFlight[other]=nil;tickets[other]=nil end end
    tickets[key]={typeId=typeId,bucket=GetPlayerRoutingBucket(src),def=def,ready=GetGameTimer()+math.max(0,(def.time or 4000)-250),expires=GetGameTimer()+math.max(30000,(def.time or 4000)+15000)}
    inFlight[key] = src
    checkedAt[key] = os.time()
    return { ok = true, time = def.time }
end)

BSB.RegisterCallback('containers:loot', function(src, typeId, key)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = Lp(src, 'search.no_character') } end

    -- Only the player who reserved this container may collect from it.
    if inFlight[key] ~= src then return { ok = false, error = Lp(src, 'search.interrupted') } end
    inFlight[key] = nil
    local ticket=tickets[key];tickets[key]=nil
    if not ticket or ticket.typeId~=typeId or ticket.bucket~=GetPlayerRoutingBucket(src) or GetGameTimer()>ticket.expires or GetGameTimer()<ticket.ready then return {ok=false,error='Search expired'} end

    local def = ticket.def
    if not def then return { ok = false, error = 'unknown container' } end
    if cooldownLeft(typeId, key) > 0 then return { ok = false, error = Lp(src, 'search.emptied') } end
    if not nearKey(src, key) then return { ok = false, error = Lp(src, 'search.too_far') } end

    -- The client plays a def.time ms search animation between check and loot
    local minWait = math.max(0, ((def.time or 0) / 1000) - 1.5)
    if not checkedAt[key] or (os.time() - checkedAt[key]) < minWait then
        return { ok = false, error = Lp(src, 'search.too_soon') }
    end
    checkedAt[key] = nil

    searched[key] = os.time()

    local rolled = rollLoot(def.lootTable, src)
    local given = {}

    for _, entry in ipairs(rolled) do
        local ok, label = exports.bs_inventory:GiveItem(src, entry.item, entry.amount)
        if ok then
            given[#given + 1] = { item = entry.item, amount = entry.amount, label = label }
        end
    end

    -- Diesel in the barrel: not a loot-table entry
    local diesel = nil

    if def.diesel and Containers.Diesel then
        local D = Containers.Diesel
        if math.random() <= (D.chance or 0.2) then
            local lo = math.floor((D.amount and D.amount[1]) or 5)
            local hi = math.floor((D.amount and D.amount[2]) or 15)
            local found = (hi > lo) and math.random(lo, hi) or lo

            local info = exports.bs_inventory:MeasuredInfo(src, D.containers)
            if not info or (info.containers or 0) < 1 then
                diesel = { found = found, stored = 0, reason = 'no_can' }
            elseif (info.room or 0) <= 0 then
                diesel = { found = found, stored = 0, reason = 'cans_full' }
            else
                local stored = exports.bs_inventory:PourInto(src, D.containers,
                    math.min(found, info.room))
                diesel = { found = found, stored = stored }
            end
        end
    end

    -- Searching is a survival skill; doing it teaches you to do it faster.
    if #given > 0 or (diesel and diesel.stored > 0) then
        exports.bs_core:AwardAction(src, 'resource_gathered')
    end

    BS_LogSearch(src, player, typeId, key, given)
    TriggerEvent('bs:tutorial:event', src, 'loot', typeId)
    return { ok = true, items = given, diesel = diesel }
end)

function BS_LogSearch(src, player, typeId, key, given)
    local names = {}
    for _, g in ipairs(given) do names[#names + 1] = ('%dx %s'):format(g.amount, g.item) end
    print(('^5[BS LOOT]^7 %s searched %s -> %s'):format(
        player.name, typeId, #names > 0 and table.concat(names, ', ') or 'nothing'))
end

-- A player leaving must not lock a container forever.
AddEventHandler('playerDropped', function()
    local src = source
    for key, holder in pairs(inFlight) do
        if holder == src then inFlight[key] = nil;tickets[key]=nil end
    end
end)

-- Staff reset, for testing loot tables without waiting out cooldowns.
BSB.RegisterCallback('containers:reset', function(src)
    if not IsPlayerAceAllowed(src, 'bs.admin') and not IsPlayerAceAllowed(src, 'bs.superadmin') then
        return { ok = false, error = 'not allowed' }
    end
    local count = 0
    for _ in pairs(searched) do count = count + 1 end
    searched = {}
    inFlight = {}
    return { ok = true, cleared = count }
end)

exports.bs_core:RegisterModule('interactions', { side = 'server', version = '0.2.0' })

-- /targetdebug - prop identification overlay (cl_target.lua).
local targetDebug = {}      -- [src] = true while that player's overlay is on

RegisterCommand('targetdebug', function(src)
    if src == 0 then
        print('^3[BeyondSurvival]^7 /targetdebug is an in-game overlay and needs a player.')
        return
    end

    if not IsPlayerAceAllowed(src, 'bs.admin') and not IsPlayerAceAllowed(src, 'bs.superadmin') then
        return
    end

    targetDebug[src] = not targetDebug[src]
    TriggerClientEvent('bs_interactions:debug:toggle', src, targetDebug[src])
end, false)

-- Ids are reused, so a fresh join must not inherit the last holder's state.
AddEventHandler('playerDropped', function()
    targetDebug[source] = nil
end)

RegisterNetEvent('bs:containers:cancel',function(key)
    local src=source
    if inFlight[key]==src then inFlight[key]=nil;tickets[key]=nil;checkedAt[key]=nil end
end)
