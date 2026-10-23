-- BeyondSurvival | bs_guard/server/sv_combat.lua God mode, unowned weapons, explosion / ptfx spam and client entity spawns

local G = GuardCore

local function counter(tbl, src, key, windowMs)
    local t = GetGameTimer()
    tbl[src] = tbl[src] or {}
    local c = tbl[src][key]
    if not c or t - c.start > windowMs then c = { start = t, n = 0 }; tbl[src][key] = c end
    c.n = c.n + 1
    return c.n
end

local function playerFromPed(ped)
    if not ped or ped == 0 or not IsPedAPlayer(ped) then return nil end
    local owner = NetworkGetEntityOwner(ped)
    if owner and owner > 0 and GetPlayerPed(owner) == ped then return owner end
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if GetPlayerPed(s) == ped then return s end
    end
    return nil
end

-- god mode

local godHits = {}   -- [victim] = { n, start }

local function testerGod(src)
    if GetResourceState('bs_tester') ~= 'started' then return false end
    local ok, r = pcall(function() return exports.bs_tester:IsGodMode(src) end)
    return ok and r == true
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    local C = Guard.God
    if not (Guard.Settings.enabled and C.enabled) or type(data) ~= 'table' then return end
    local dmg = tonumber(data.weaponDamage) or 0
    if dmg < (C.minDamage or 10) then return end
    local netId = data.hitGlobalId or (data.hitGlobalIds and data.hitGlobalIds[1])
    if not netId then return end
    local ped = NetworkGetEntityFromNetworkId(netId)
    if not ped or ped == 0 or GetEntityType(ped) ~= 1 then return end
    local victim = playerFromPed(ped)
    if not victim or victim == tonumber(sender) or G.isExempt(victim) or testerGod(victim) then return end
    local before = GetEntityHealth(ped)
    local armourBefore = GetPedArmour(ped)
    if before <= 0 then return end
    SetTimeout(C.checkDelayMs or 1200, function()
        if not DoesEntityExist(ped) or GetPlayerPed(victim) ~= ped then return end
        local after, armourAfter = GetEntityHealth(ped), GetPedArmour(ped)
        if after <= 0 or after < before or armourAfter < armourBefore then
            godHits[victim] = nil
            return
        end
        local t = GetGameTimer()
        local h = godHits[victim]
        if not h or t - h.start > (C.windowMs or 60000) then h = { start = t, n = 0 }; godHits[victim] = h end
        h.n = h.n + 1
        if h.n >= (C.strikes or 4) then
            G.Flag(victim, 'godmode', ('%d hits (last %d dmg from [%s]) left health at %d'):format(h.n, dmg, tostring(sender), after),
                h.n >= (C.strikes or 4) * 2 and 85 or 65)
            godHits[victim] = nil
        end
    end)
end)

-- health / armour ceilings and the invincible flag, sampled with the weapons check
local function checkVitals(src, ped)
    local C = Guard.God
    if not C.enabled or testerGod(src) then return end
    local hp, ar = GetEntityHealth(ped), GetPedArmour(ped)
    if hp > (C.maxHealth or 200) then G.Flag(src, 'godmode', ('health %d above max %d'):format(hp, C.maxHealth or 200), 80) end
    if ar > (C.maxArmour or 100) then G.Flag(src, 'godmode', ('armour %d above max %d'):format(ar, C.maxArmour or 100), 80) end
    local ok, inv = pcall(GetPlayerInvincible, src)
    if ok and inv then G.Flag(src, 'godmode', 'player invincible flag set', 75) end
end

-- weapons the player does not own

local weaponItems, ignoreHash, builtAt = {}, {}, 0

local function buildWeaponMap()
    weaponItems, ignoreHash = {}, {}
    for _, w in ipairs(Guard.Weapons.ignore or {}) do ignoreHash[joaat(w)] = true end
    if GetResourceState('bs_inventory') ~= 'started' then return end
    local ok, items = pcall(function() return exports.bs_inventory:GetItems() end)
    if not ok or type(items) ~= 'table' then return end
    for name, def in pairs(items) do
        local data = type(def) == 'table' and def.data or nil
        if type(data) == 'string' then data = json.decode(data) end
        local w = type(data) == 'table' and data.weapon or nil
        if type(w) == 'string' then
            local h = joaat(w)
            weaponItems[h] = weaponItems[h] or {}
            table.insert(weaponItems[h], name)
        end
    end
    builtAt = GetGameTimer()
end

local weaponStrikes = {}

local function checkWeapon(src, ped)
    local W = Guard.Weapons
    if not W.enabled or GetResourceState('bs_inventory') ~= 'started' then return end
    if next(weaponItems) == nil or GetGameTimer() - builtAt > 300000 then buildWeaponMap() end
    local hash = GetSelectedPedWeapon(ped)
    if not hash or hash == 0 or ignoreHash[hash] then weaponStrikes[src] = nil return end
    local names = weaponItems[hash]
    local owned = false
    if names then
        for _, item in ipairs(names) do
            local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
            if not ok or (tonumber(n) or 0) > 0 then owned = true break end
        end
    end
    if owned then weaponStrikes[src] = nil return end
    local n = (weaponStrikes[src] or 0) + 1
    weaponStrikes[src] = n
    if n >= (W.strikes or 2) then
        local hex = ('0x%08X'):format(hash & 0xFFFFFFFF)
        if names then
            G.Flag(src, 'weapon', ('holding %s (%s) with none in inventory'):format(names[1], hex), 75)
        else
            G.Flag(src, 'weapon', ('holding weapon %s that no item grants'):format(hex), 60)
        end
        weaponStrikes[src] = nil
    end
end

G.onDrop[#G.onDrop + 1] = function(src) weaponStrikes[src], godHits[src] = nil, nil end

CreateThread(function()
    while true do
        Wait(Guard.Weapons.checkMs or 5000)
        if Guard.Settings.enabled then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                if src and not G.isExempt(src) and not G.inGrace(src) then
                    local ped = GetPlayerPed(src)
                    if ped and ped ~= 0 and GetEntityHealth(ped) > 0 then
                        pcall(checkVitals, src, ped)
                        local ok, err = pcall(checkWeapon, src, ped)
                        if not ok then G.dbg('weapon check failed: %s', tostring(err)) end
                    end
                end
            end
        end
    end
end)

-- explosions / ptfx

local boom = {}
local suspicious = {}
local function refreshSuspicious()
    suspicious = {}
    for _, t in ipairs(Guard.Explosions.suspiciousTypes or {}) do suspicious[t] = true end
end
refreshSuspicious()
AddEventHandler('bs_config:changed:bs_guard', refreshSuspicious)

AddEventHandler('explosionEvent', function(sender, ev)
    local E = Guard.Explosions
    if not (Guard.Settings.enabled and E.enabled) then return end
    sender = tonumber(sender)
    if not sender or G.isExempt(sender) or type(ev) ~= 'table' then return end
    local et = tonumber(ev.explosionType) or -1
    if suspicious[et] then
        G.Flag(sender, 'explosion', ('suspicious explosion type %d (scale %.1f)'):format(et, tonumber(ev.damageScale) or 0), 85)
    end
    if ev.isInvisible and (tonumber(ev.damageScale) or 0) > 0 then
        G.Flag(sender, 'explosion', ('invisible damaging explosion type %d'):format(et), 80)
    end
    local n = counter(boom, sender, 'x', E.windowMs or 10000)
    if n == (E.maxPerWindow or 6) + 1 then
        G.Flag(sender, 'explosion', ('%d explosions in %ds (last type %d)'):format(n, math.floor((E.windowMs or 10000) / 1000), et), 70)
    end
end)

AddEventHandler('ptFxEvent', function(sender, data)
    local E = Guard.Explosions
    if not (Guard.Settings.enabled and E.enabled) then return end
    sender = tonumber(sender)
    if not sender or G.isExempt(sender) then return end
    local n = counter(boom, sender, 'p', E.windowMs or 10000)
    if n == (E.ptfxPerWindow or 25) + 1 then
        G.Flag(sender, 'ptfx', ('%d particle effects in %ds'):format(n, math.floor((E.windowMs or 10000) / 1000)), 60)
    end
end)

-- client entity creation

local spawns = {}
local whiteHash, blackHash = {}, {}
local function refreshModels()
    whiteHash, blackHash = {}, {}
    for _, m in ipairs(Guard.Entities.modelWhitelist or {}) do whiteHash[type(m) == 'number' and m or joaat(m)] = m end
    for _, m in ipairs(Guard.Entities.modelBlacklist or {}) do blackHash[type(m) == 'number' and m or joaat(m)] = m end
end
refreshModels()
AddEventHandler('bs_config:changed:bs_guard', refreshModels)

local TYPE = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

AddEventHandler('entityCreating', function(entity)
    local N = Guard.Entities
    if not (Guard.Settings.enabled and N.enabled) then return end
    if not DoesEntityExist(entity) then return end
    local owner = NetworkGetEntityOwner(entity)
    if not owner or owner <= 0 or not GetPlayerName(owner) then return end
    -- only script-created (mission) entities; ambient population is the game's
    local pop = GetEntityPopulationType(entity)
    if pop ~= 6 and pop ~= 7 then return end
    if G.isExempt(owner) then return end
    local kind = TYPE[GetEntityType(entity)]
    if not kind then return end
    local model = GetEntityModel(entity)
    local hex = ('0x%08X'):format(model & 0xFFFFFFFF)

    if blackHash[model] then
        G.Flag(owner, 'entity', ('spawned blacklisted %s %s'):format(kind, tostring(blackHash[model])), 90)
    elseif N.whitelistOnly and kind ~= 'object' and not whiteHash[model] then
        G.Flag(owner, 'entity', ('spawned non-whitelisted %s %s'):format(kind, hex), 60)
    end

    local limit = (kind == 'vehicle' and N.maxVehicles) or (kind == 'ped' and N.maxPeds) or N.maxObjects or 60
    local n = counter(spawns, owner, kind, N.windowMs or 10000)
    if n == (limit or 60) + 1 then
        G.Flag(owner, 'entity', ('%d %ss created in %ds (last %s)'):format(n, kind, math.floor((N.windowMs or 10000) / 1000), hex), 70)
    end
end)

G.onDrop[#G.onDrop + 1] = function(src) boom[src], spawns[src] = nil, nil end
