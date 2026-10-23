-- bs_zombies - director: heat, hordes, bodies and bites

local Heat      = {}     -- [zoneId] = number
local LastHorde = {}     -- [zoneId] = os.time
local Looted    = {}     -- [zombieId] = os.time

-- Heat

local function zoneFor(x, y)
    local best
    for _, zone in ipairs(Zones.Spawn or {}) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
            if not best or (zone.difficulty or 1) > (best.difficulty or 1) then best = zone end
        end
    end
    return best
end

-- Global: sv_registry calls this when a kill lands
function Director_AddHeat(zone, amount)
    if not zone then return end
    Heat[zone.id] = math.min(Zones.Scaling.heatMax or 100.0, (Heat[zone.id] or 0.0) + amount)
end

CreateThread(function()
    while true do
        Wait(60000)
        for id, value in pairs(Heat) do
            Heat[id] = math.max(0.0, value - (Zones.Scaling.heatDecayPerMinute or 3.0))
        end
    end
end)

-- Noise is the one event that moves the whole world, so it is validated hard

-- Kinds the world does not hear, whatever a client sends
local SILENT_KINDS = {
    melee    = true,
    body     = true,
    -- Silenced weapons and melee never attract zombies. bs_emotes already refuses to emit them
    silenced = true,
}

local noiseRate = {}          -- [src] = { at = os.time(), n = count }
Director_NoiseRejected = 0    -- surfaced by the diagnostics command

-- Generous: an automatic weapon at 700rpm fires ~12 shots a second, all legitimate.
local NOISE_PER_SECOND = 25

-- Max distance between a reported noise and the player reporting it. 50m covers muzzle offset
local NOISE_MAX_RANGE = 50.0

-- Bounded noise response. Problem: noise had no end condition.

-- [key] = { x, y, opensAt, expiresAt
local Responses = {}

local function responseConfig()
    return (Sectors and Sectors.NoiseResponse) or nil
end

local function responseKey(x, y, radius)
    return ('%d:%d'):format(math.floor(x / radius), math.floor(y / radius))
end

-- Find the response covering this point, opening one if the area is free
local function responseFor(x, y)
    local cfg = responseConfig()
    if not cfg or not cfg.enabled then return nil end

    local now = os.time()
    local radius = cfg.radius or 220.0
    local key = responseKey(x, y, radius)
    local r = Responses[key]

    if r then
        if r.open then
            -- Still open: did it lapse? A spent budget closes immediately, so only time can end it here.
            if now >= r.expiresAt then
                r.open = false
                r.cooldownUntil = now + (cfg.cooldownSeconds or 120)
                return nil
            end
            return r
        end

        -- Closed. The entry survives only to hold the cooldown.
        if now < (r.cooldownUntil or 0) then return nil end
        Responses[key] = nil
    end

    local fresh = {
        x = x, y = y,
        opensAt = now,
        expiresAt = now + (cfg.openSeconds or 90),
        spawns = 0,
        alerts = 0, lastAlertAt = 0,
        lures = 0, lastLureAt = 0,
        cooldownUntil = 0,
        open = true,
    }
    Responses[key] = fresh
    return fresh
end

-- Close a response and start its cooldown. Called on budget exhaustion and on expiry.
local function closeResponse(r)
    local cfg = responseConfig()
    r.open = false
    r.cooldownUntil = os.time() + ((cfg and cfg.cooldownSeconds) or 120)
end

-- The spawn claim - sv_streaming calls this before creating a walker
function Director_ClaimNoiseSpawn(x, y)
    -- Under the migration model (Noise.enabled) noise buys nothing, so this returns true for everything
    if Noise and Noise.enabled then return true end

    local cfg = responseConfig()
    if not cfg or not cfg.enabled then return true end

    x, y = tonumber(x), tonumber(y)
    if not x or not y then return true end

    local radius = cfg.radius or 220.0
    local r = Responses[responseKey(x, y, radius)]
    if not r or not r.open then return true end

    if os.time() >= r.expiresAt then
        closeResponse(r)
        return true
    end

    if r.spawns >= (cfg.spawnBudget or 6) then
        closeResponse(r)
        Director_NoiseCapped = (Director_NoiseCapped or 0) + 1
        return false
    end

    r.spawns = r.spawns + 1
    if r.spawns >= (cfg.spawnBudget or 6) then
        -- Closed as soon as the last spawn is spent, so the cooldown starts when the group is complete.
        closeResponse(r)
    end
    return true
end

-- Spawns refused for this noise event. Shown by /zstatus.
Director_NoiseCapped = 0

-- Swept periodically so the table does not grow on a long-running server.
CreateThread(function()
    while true do
        Wait(120000)
        local now = os.time()
        for key, r in pairs(Responses) do
            if not r.open and now >= (r.cooldownUntil or 0) then Responses[key] = nil end
        end
    end
end)


-- Gunfire is the loudest way to tell a zone you are in it. radius is the third argument clients
RegisterNetEvent('bs:world:noise', function(kind, coords, radius)
    local src = source
    if type(coords) ~= 'table' then return end

    -- 1. Rate.
    local now = os.time()
    local rate = noiseRate[src]
    if not rate or rate.at ~= now then
        noiseRate[src] = { at = now, n = 1 }
    else
        rate.n = rate.n + 1
        if rate.n > NOISE_PER_SECOND then
            Director_NoiseRejected = Director_NoiseRejected + 1
            return
        end
    end

    -- 2. Kind. Only what the config prices.
    kind = tostring(kind or '')
    local weights = (Sectors and Sectors.Settings and Sectors.Settings.noiseWeights) or {}
    if not weights[kind] then
        Director_NoiseRejected = Director_NoiseRejected + 1
        return
    end

    -- 2b
    if SILENT_KINDS[kind] then return end

    -- Fields are coerced, not defaulted
    local nx, ny = tonumber(coords.x), tonumber(coords.y)
    if not nx or not ny then
        Director_NoiseRejected = Director_NoiseRejected + 1
        return
    end

    -- 3. Proximity. You may only make noise where you are.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    local dx, dy = nx - at.x, ny - at.y
    if (dx * dx + dy * dy) > (NOISE_MAX_RANGE * NOISE_MAX_RANGE) then
        Director_NoiseRejected = Director_NoiseRejected + 1
        return
    end

    coords = { x = nx, y = ny, z = tonumber(coords.z) or at.z }

    -- Noise no longer raises a sector's target
    local sectorCap = (Noise and Noise.sectorTargetMultiplierCap) or 3.0
    if ZSectors and (not (Noise and Noise.enabled) or sectorCap > 1.0) then
        ZSectors.AddNoise(nx, ny, kind)
    end

    -- The whole noise response under the new model
    if ZPOI and ZPOI.Publish then
        local carry = tonumber(radius)
        if not carry or carry <= 0 then
            local w = (Sectors and Sectors.Settings and Sectors.Settings.noiseWeights) or {}
            carry = 120.0 * (w[kind] or 1.0)
        end
        -- src added: the sense ladder scores a point higher when the zombie can see its source
        pcall(ZPOI.Publish, nx, ny, tonumber(coords.z) or 0.0, carry, kind, src)
    end

    -- Stage 5: herds turn toward the noise
    local response = responseFor(nx, ny)
    local rcfg = responseConfig()
    local nowSec = os.time()

    if ZNodes and ZNodes.ready then
        local reach = tonumber(radius)
        if not reach or reach <= 0 then
            local weights = (Sectors and Sectors.Settings and Sectors.Settings.noiseWeights) or {}
            reach = 120.0 * (weights[kind] or 1.0)
        end

        -- Alert allowance: ApplyNoise overrides a herd's target and refreshes its expiry
        local mayAlert = response ~= nil
        if mayAlert and rcfg then
            if response.alerts >= (rcfg.alertsPerResponse or 3) then
                mayAlert = false
            elseif (nowSec - (response.lastAlertAt or 0)) < (rcfg.alertMinGapSeconds or 8) then
                mayAlert = false
            end
        end

    -- Herds do not react to noise
        if Noise and Noise.enabled and not Noise.herdMigration then
            mayAlert = false
        end

        if mayAlert then
            if response then
                response.alerts = response.alerts + 1
                response.lastAlertAt = nowSec
            end
            pcall(ZNodes.ApplyNoise, coords, reach, kind)
        end
    end

    -- Records nobody is simulating start walking
    if Registry and Registry.Lure then
        local mayLure = response ~= nil
        if mayLure and rcfg then
            if response.lures >= (rcfg.luresPerResponse or 2) then
                mayLure = false
            elseif (nowSec - (response.lastLureAt or 0)) < (rcfg.lureMinGapSeconds or 10) then
                mayLure = false
            end
        end

    -- Registry.Lure is now driven by sv_poi.lua's board, which re-applies it while the point is interesting
        if ZPOI and Noise and Noise.enabled then mayLure = false end

        if mayLure then
            if response then
                response.lures = response.lures + 1
                response.lastLureAt = nowSec
            end
            local carry = tonumber(radius) or 60.0
            pcall(Registry.Lure, nx, ny, carry)
        end
    end

    -- Zone heat stays gunfire-only: it drives hordes and difficulty, and an idling engine should not raise threat
    if kind ~= 'gunshot' and kind ~= 'silenced' then return end

    local zone = zoneFor(nx, ny)
    if not zone then return end

    Director_AddHeat(zone, kind == 'gunshot'
        and (Zones.Scaling.heatPerGunshot or 0.15) * 3.0
        or  (Zones.Scaling.heatPerGunshot or 0.15))
end)

-- Hordes
-- A horde is a short-lived increase in the per-player budget plus a notice to everything nearby

Registry.hordeBonus = Registry.hordeBonus or {}    -- [src] = { until_, extra }

local function playersInZone(zone)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)
            local dx, dy = at.x - zone.coords.x, at.y - zone.coords.y
            if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
                out[#out + 1] = { src = id, coords = at }
            end
        end
    end
    return out
end

local function startHorde(zone, players)
    LastHorde[zone.id] = os.time()
    Heat[zone.id] = math.max(0.0, (Heat[zone.id] or 0) - 45.0)

    local sx, sy, sz = 0.0, 0.0, 0.0
    for _, p in ipairs(players) do
        sx, sy, sz = sx + p.coords.x, sy + p.coords.y, sz + p.coords.z
    end
    local n = #players
    local focus = { x = sx / n, y = sy / n, z = sz / n }

    local size = math.random(Zombies.Horde.size.min, Zombies.Horde.size.max)
    size = ZDiff.HordeSize(size, focus.x, focus.y)
    local warning = Zombies.Horde.warning or 12
    -- Remembered for the atlas's hordes layer (DirectorState below).
    ZHordes = ZHordes or {}
    ZHordes['zone:' .. zone.id] = { source = 'heat', zone = zone.id, x = focus.x, y = focus.y,
                                    size = size, players = n, startedAt = os.time(),
                                    endsAt = os.time() + warning + 180 }

    for _, p in ipairs(players) do
        TriggerClientEvent('bs:z:horde', p.src, {
            coords = focus, warning = warning, duration = 180,
        })

        -- A horde is an observation, not a product
        if not (Noise and Noise.enabled) then
            -- The budget rises after the warning so the wave arrives with it.
            Registry.hordeBonus[p.src] = {
                until_ = os.time() + warning + 180,
                startsAt = os.time() + warning,
                extra = math.floor(size * 0.7),
            }
        end
    end

    -- Everything already in the area starts walking toward the noise
    if ZPOI and ZPOI.Publish and Noise and Noise.enabled then
        pcall(ZPOI.Publish, focus.x, focus.y, focus.z, 320.0, 'horde')
    else
        for _, record in ipairs(Registry.NearbyZombies(focus.x, focus.y, 220.0)) do
            record.state = 'drawn'
            if record.host then
                TriggerClientEvent('bs:z:draw', record.host, record.id, focus)
            end
        end
    end

    print(('^1[BeyondSurvival]^7 (zombies) horde of ~%d in %s, %d player(s)')
        :format(size, zone.id, n))

    TriggerEvent('bs:db:update', [[
        INSERT INTO `bs_zone_state` (`zone`, `difficulty`, `heat`, `last_horde`)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE `heat` = VALUES(`heat`), `last_horde` = NOW()
    ]], { zone.id, zone.difficulty or 1.0, Heat[zone.id] or 0.0 })

    CreateThread(function()
        Wait((warning + 180) * 1000)
        for _, p in ipairs(players) do
            Registry.hordeBonus[p.src] = nil
            TriggerClientEvent('bs:z:hordeOver', p.src)
            if exports.bs_core:GetPlayer(p.src) then
                exports.bs_core:AwardAction(p.src, 'horde_cleared', zone.difficulty or 1.0)
            end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(60000)
        if not Zombies.Horde.enabled then goto continue end

        for _, zone in ipairs(Zones.Spawn or {}) do
            local heat = Heat[zone.id] or 0.0
            local cooled = (os.time() - (LastHorde[zone.id] or 0)) >= (Zombies.Horde.cooldown or 900)

            if heat > 25.0 and cooled then
                local chance = (Zombies.Horde.baseChance or 0.018) * (heat / 10.0)
                if math.random() < chance then
                    local players = playersInZone(zone)
                    if #players > 0 then startHorde(zone, players) end
                end
            end
        end

        ::continue::
    end
end)

-- Bodies

BSB.RegisterCallback('zombies:lootCheck', function(src, id)
    id = tostring(id)
    if Looted[id] then return { ok = false, error = Lp(src, 'zed.picked') } end
    -- Keep the body alive while this player kneels over it.
    if ZNet and ZNet.HoldCorpse then ZNet.HoldCorpse(id, 20000) end
    return { ok = true }
end)

-- Skinning kneels over the body too (bs_crafting). Only holds it, gives nothing.
local holdAsk = {}
RegisterNetEvent('bs:zombies:holdCorpse', function(id, ms)
    local src = source
    local now = GetGameTimer()
    if holdAsk[src] and now - holdAsk[src] < 500 then return end
    holdAsk[src] = now
    if type(id) ~= 'string' and type(id) ~= 'number' then return end
    if ZNet and ZNet.HoldCorpse then ZNet.HoldCorpse(tostring(id), math.min(tonumber(ms) or 20000, 30000)) end
end)
AddEventHandler('playerDropped', function() holdAsk[source] = nil end)

BSB.RegisterCallback('zombies:loot', function(src, id, lootTable)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = 'no character' } end

    id = tostring(id)
    if Looted[id] then return { ok = false, error = Lp(src, 'zed.picked') } end
    Looted[id] = os.time()

    local tbl = exports.bs_economy:GetLootTable(lootTable)
        or exports.bs_economy:GetLootTable('walker')
    if not tbl then return { ok = true, items = {} } end

    local rolls = math.random(tbl.rolls and tbl.rolls.min or 0, tbl.rolls and tbl.rolls.max or 1)

    if GetResourceState('bs_skills') == 'started' then
        local ok, bonus = pcall(function() return exports.bs_skills:LootBonus(src) end)
        if ok and type(bonus) == 'number' then rolls = rolls + bonus end
    end

    local given = {}
    -- Faction sanction drop_penalty: chance each rolled item is kept.
    local keep = 1.0
    if GetResourceState('bs_faction_bases') == 'started' then
        local okKeep, value = pcall(function() return exports.bs_faction_bases:DropMultiplier(src) end)
        if okKeep and type(value) == 'number' then keep = value end
    end

    -- Cash on a body is rare by design (max 800)
    local cashChance = tbl.cashChance or 0.0
    if cashChance > 0 and math.random() < cashChance then
        local maxCash = tbl.cashMax or 800
        local roll = math.random() ^ 3          -- heavy bias to small amounts
        local amount = math.max(1, math.floor(roll * maxCash))

        -- bs_core owns money (bs_economy only owns loot tables). Uses 'cash', not 'bank'.
        local okCash, added = pcall(function()
            return exports.bs_core:AddMoney(src, 'cash', amount, 'zombie_loot')
        end)
        if okCash and added then
            given[#given + 1] = { cash = amount, label = ('$%d'):format(amount) }
        end
    end

    for _ = 1, rolls do
        local total = 0
        for _, entry in ipairs(tbl.entries or {}) do total = total + (entry.weight or 0) end
        if total <= 0 then break end

        local pick, acc = math.random() * total, 0
        for _, entry in ipairs(tbl.entries) do
            acc = acc + (entry.weight or 0)
            if pick <= acc then
                local min = entry.amount and entry.amount[1] or 1
                local max = entry.amount and entry.amount[2] or 1
                local amount = math.random(min, max)
                if keep >= 1.0 or math.random() < keep then
                    local ok, label = exports.bs_inventory:GiveItem(src, entry.item, amount)
                    if ok then given[#given + 1] = { item = entry.item, amount = amount, label = label } end
                end
                break
            end
        end
    end

    if #given > 0 then exports.bs_core:AwardAction(src, 'resource_gathered') end
    return { ok = true, items = given }
end)

-- Looted ids only matter while the body is on the ground.
CreateThread(function()
    while true do
        Wait(120000)
        local now = os.time()
        for id, at in pairs(Looted) do
            if now - at > 900 then Looted[id] = nil end
        end
    end
end)

-- Bites

local INFECTION_PER_BITE = 4.0
local lastBite = {}

RegisterNetEvent('bs:zombies:bitten', function(typeId)
    local src = source
    local now = os.time()

    if lastBite[src] and (now - lastBite[src]) < 1 then return end
    lastBite[src] = now

    if not exports.bs_core:GetPlayer(src) then return end
    -- bs_medical handles infection from hits when it is running.
    if GlobalState.bsMedicalInfection then return end

    local def = Zombies.Types[typeId] or Zombies.Types.walker
    local amount = INFECTION_PER_BITE
    if def.damage and def.damage > 30 then amount = amount * 1.6 end

    exports.bs_core:ChangeInfection(src, amount)
end)

AddEventHandler('playerDropped', function()
    lastBite[source] = nil
    Registry.hordeBonus[source] = nil
end)

-- Staff

RegisterCommand('zhorde', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local zoneId = args[1]
    for _, zone in ipairs(Zones.Spawn or {}) do
        if not zoneId or zone.id == zoneId then
            local players = playersInZone(zone)
            if #players > 0 then return startHorde(zone, players) end
        end
    end
    print('^3[BS ZOMBIES]^7 nobody is standing in that zone')
end, false)

RegisterCommand('zstatus', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local snap = exports.bs_zombies:Snapshot()
    local line = ('seed %d | %d walkers alive | hosts:'):format(snap.seed, snap.total)
    for host, n in pairs(snap.hosted) do
        line = line .. (' %s=%d'):format(GetPlayerName(host) or host, n)
    end
    print('^5[BS ZOMBIES]^7 ' .. line)

    for typeId, n in pairs(snap.byType) do
        print(('   %-10s %d'):format(typeId, n))
    end
    for id, heat in pairs(Heat) do
        print(('   heat %-14s %.0f'):format(id, heat))
    end

    -- Noise response state: open/cooling/spent per area, plus the count of spawns this bound has refused
    local open, cooling = 0, 0
    local nowSec = os.time()
    for _, r in pairs(Responses) do
        if r.open then open = open + 1 elseif nowSec < (r.cooldownUntil or 0) then cooling = cooling + 1 end
    end
    print(('   noise responses: %d open, %d cooling | %d spawn(s) refused by the cap | %d report(s) rejected')
        :format(open, cooling, Director_NoiseCapped or 0, Director_NoiseRejected or 0))
    for _, r in pairs(Responses) do
        if r.open then
            print(('      open at %.0f,%.0f - %d/%d spawned, %d alert(s), %d lure(s), %ds left')
                :format(r.x, r.y, r.spawns,
                        (responseConfig() and responseConfig().spawnBudget) or 6,
                        r.alerts, r.lures, math.max(0, r.expiresAt - nowSec)))
        end
    end
end, false)

RegisterCommand('zclear', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local n = 0
    for id in pairs(Registry.zombies) do
        Registry.Remove(id, 'staff')
        n = n + 1
    end
    print(('^2[BS ZOMBIES]^7 removed %d walkers - they will repopulate'):format(n))
end, false)

-- Staff /dz: removes every walker within radius of x
exports('ClearRadius', function(x, y, radius)
    x, y, radius = tonumber(x), tonumber(y), tonumber(radius)
    if not x or not y or not radius or radius <= 0 then return 0 end
    local r2, ids = radius * radius, {}
    for id, record in pairs(Registry.zombies) do
        local dx, dy = (record.x or 0) - x, (record.y or 0) - y
        if dx * dx + dy * dy <= r2 then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do Registry.Remove(id, 'staff') end
    return #ids
end)

exports('Heat', function(zoneId) return Heat[zoneId] or 0.0 end)

-- Director state for the atlas heat and hordes layers
function DirectorState()
    local now = os.time()
    local zones = {}
    for _, zone in ipairs(Zones.Spawn or {}) do
        zones[#zones + 1] = {
            id = zone.id, x = zone.coords.x, y = zone.coords.y, radius = zone.radius,
            difficulty = zone.difficulty, heat = Heat[zone.id] or 0.0,
            heatMax = (Zones.Scaling and Zones.Scaling.heatMax) or 100.0,
            lastHorde = LastHorde[zone.id],
        }
    end
    local hordes = {}
    for key, h in pairs(ZHordes or {}) do
        if (h.endsAt or 0) < now then ZHordes[key] = nil
        else
            hordes[#hordes + 1] = { id = key, source = h.source, zone = h.zone, x = h.x, y = h.y,
                                    size = h.size, players = h.players, kind = h.kind,
                                    secondsLeft = h.endsAt - now }
        end
    end
    return { zones = zones, hordes = hordes }
end
exports('DirectorState', DirectorState)
exports.bs_core:RegisterModule('zombies', { side = 'server', version = '2.0.0', ready = true })


-- A disconnecting player's noise record is dropped so the table does not grow forever.
AddEventHandler('playerDropped', function()
    noiseRate[source] = nil
end)
