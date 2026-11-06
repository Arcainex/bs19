-- bs_zombies - networked walkers: one server-created OneSync ped per walker

ZNet = {
    enabled  = (Zombies.Mode or 'networked') ~= 'legacy',
    ents     = {},   -- [entity] = record id (live walkers)
    corpses  = {},   -- [entity] = { id =, untilAt =, killCheckAt = }
    expected = {},   -- [entity] = reason, for deletes this file made itself
    expectedAt = {}, -- [entity] = ms the delete was asked (a delete that never lands must not hide the ped forever)
    fps      = {},   -- [src] = { fps =, at = }
    count    = 0,
    cap      = 0,
    perf     = { avg = 0.0, samples = 0 },
    entities = { total = 0, peds = 0, objects = 0, vehicles = 0, at = 0 },
    stats    = { created = 0, failed = 0, demoted = 0, shed = 0, unexpected = 0,
                 replaced = 0, orphans = 0, corpses = 0,
                 deathAcked = 0, deathForced = 0, deathReplaced = 0 },
}

-- Clients read this at load to run the same mode (config_net.lua).
GlobalState.bsZombieMode = Zombies.Mode

if not ZNet.enabled then
    print('^3[BS ZNET]^7 Zombies.Mode = legacy - networked walkers OFF (client-local peds).')
    return
end

local function N() return Zombies.Net or {} end
local function num(v, d) v = tonumber(v); if v == nil then return d end return v end

-- NPC ped load pushed by an external NPC resource (none shipped now): { [src] = n } NPC peds materialised around that player
local npcLoad, npcTotal, npcAt = {}, 0, 0
local function npcLoadOf(src)
    if GetGameTimer() - npcAt > 15000 then return 0 end
    return npcLoad[src] or 0
end
local function npcLoadSum()
    if GetGameTimer() - npcAt > 15000 then return 0 end
    return npcTotal
end
exports('SetNpcLoad', function(map)
    local m, t = {}, 0
    if type(map) == 'table' then
        for k, v in pairs(map) do
            local s, n = tonumber(k), math.floor(tonumber(v) or 0)
            if s and n > 0 and n <= 60 then m[s] = n; t = t + n end
        end
    end
    npcLoad, npcTotal, npcAt = m, t, GetGameTimer()
    return true
end)

local CORPSE_REASONS = { dead = true, environment = true, engine = true }

local function log(fmt, ...)
    print(('^5[BS ZNET]^7 ' .. fmt):format(...))
end

-- Players

local function players()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = src and GetPlayerPed(src)
        if ZStream and ZStream.InGame and not ZStream.InGame(src, ped) then ped = nil end
        -- Walkers live in bucket 0; a player in a private bucket cannot see them
        local okB, bucket = pcall(GetPlayerRoutingBucket, src)
        if okB and tonumber(bucket) and tonumber(bucket) ~= 0 then ped = nil end
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local at = GetEntityCoords(ped)
            if not (at.x == 0.0 and at.y == 0.0) then
                out[#out + 1] = { src = src, x = at.x, y = at.y, z = at.z, near = 0 }
            end
        end
    end
    return out
end

local function nearest(list, x, y)
    local best, who = math.huge, nil
    for _, p in ipairs(list) do
        local dx, dy = p.x - x, p.y - y
        local d = dx * dx + dy * dy
        if d < best then best, who = d, p end
    end
    return math.sqrt(best), who
end

-- Gait - same deterministic pick as cl_sync gaitFor()

local function isFemaleModel(model)
    local m = tostring(model or ''):lower()
    return m:find('^[a-z]_f_') ~= nil or m:find('^mp_f_') ~= nil
end

local function gaitFor(id, model, typeId, crawler)
    local def = Zombies.Types[typeId] or Zombies.Types.walker or {}
    if crawler or def.noClipset then return false end
    local a = Zombies.Anims or {}
    local list = a.shambleSet or { a.shamble }
    if isFemaleModel(model) and type(a.femaleShambleSet) == 'table' and #a.femaleShambleSet > 0 then
        list = a.femaleShambleSet
    end
    id = math.floor(tonumber(id) or 0)
    local drunk = list[(id % math.max(1, #list)) + 1] or a.shamble
    local r = ((id * 2654435761) % 1000) / 1000.0
    -- Always drunk: the DLC zombie clipset walks upright and looks normal. drunkShare is unused.
    local _ = r
    return drunk or 'move_m@drunk@verydrunk'
end

-- State bags

local function bag(ent, key, value)
    local ok = pcall(function() Entity(ent).state:set(key, value, true) end)
    return ok
end

local function feedingOf(record)
    if record.state == 'feeding' then return true end
    return record.feeding == true and record.lastReport == nil
end

local function mirrorBags(record, ent, force)
    local m = record._bags or {}
    record._bags = m
    local crawl = record.crawler == true
    local feed = feedingOf(record)
    local st = tostring(record.state or 'idle')
    if force or m.crawl ~= crawl then
        m.crawl = crawl
        bag(ent, 'zCrawl', crawl)
        if crawl then bag(ent, 'zGait', false) end
    end
    if force or m.feed ~= feed then m.feed = feed; bag(ent, 'zFeed', feed) end
    if force or m.state ~= st then m.state = st; bag(ent, 'zState', st) end
    if force or m.mhp ~= record.maxHp then m.mhp = record.maxHp; bag(ent, 'zMhp', record.maxHp) end
    -- Server hp for the health bar on every client
    if force or m.hp ~= record.hp then m.hp = record.hp; bag(ent, 'zHp', record.hp) end
end

function ZNet.MirrorHp(record)
    if not record or not record.ent or not DoesEntityExist(record.ent) then return end
    local m = record._bags or {}
    record._bags = m
    m.hp = record.hp
    bag(record.ent, 'zHp', record.hp)
end

-- Create / delete

local function deleteEnt(ent, reason)
    if not ent or ent == 0 then return end
    ZNet.ents[ent] = nil
    ZNet.corpses[ent] = nil
    -- Only expect an entityRemoved for an entity that still exists
    if DoesEntityExist(ent) then
        ZNet.expected[ent] = reason or 'server'
        ZNet.expectedAt[ent] = GetGameTimer()
        DeleteEntity(ent)
    end
end

local function clearRecordEnt(record)
    if record.ent and ZNet.ents[record.ent] then
        ZNet.ents[record.ent] = nil
        ZNet.count = math.max(0, ZNet.count - 1)
    end
    record.ent, record.net, record.netOwner, record._bags = nil, nil, nil, nil
end

local function demote(record, reason)
    local ent = record.ent
    -- A demoted record may get a ped again later; any other second create is refused (spawnEnt)
    record.demotedAt = GetGameTimer()
    clearRecordEnt(record)
    deleteEnt(ent, reason or 'demote')
    ZNet.stats.demoted = ZNet.stats.demoted + 1
    ZNet.demotedBy = ZNet.demotedBy or {}
    ZNet.demotedBy[reason or 'demote'] = (ZNet.demotedBy[reason or 'demote'] or 0) + 1
end

local function spawnEnt(record)
    -- Hard guard: an id that died never gets a ped again, and a ped is created once (again only after a demote)
    if record.dead or (Registry.endedIds and Registry.endedIds[record.id]) then
        print(('[BS ZOMBIES] RESPAWN BLOCKED id=%s (already dead/removed)'):format(tostring(record.id)))
        return false
    end
    if (record.entCreated or 0) > 0 and not record.demotedAt then
        print(('[BS ZOMBIES] RESPAWN BLOCKED id=%s (second create without a demote)'):format(tostring(record.id)))
        return false
    end
    -- A promoted filler keeps its exact model and look, so no archetype swap
    local variant = Zombies.Mode == 'networked_plus' and not record.look and Zombies.PickArchetype(record) or nil
    if variant and variant.models and #variant.models > 0 then
        record.model = variant.models[(math.floor(record.id or 0) % #variant.models) + 1]
    end
    local model = record.model or (Zombies.Models or {})[1] or 'u_m_y_zombie_01'
    local hash = type(model) == 'number' and model or GetHashKey(model)
    local z = tonumber(record.z) or 0.0
    local needsGround = record.needsGround == true or z < 1.0 or z > 2000.0
    if needsGround then z = 0.0 end

    local ent = CreatePed(4, hash, record.x + 0.0, record.y + 0.0, z + 0.0, (record.h or 0.0) + 0.0, true, true)
    if (not ent or ent == 0) and variant then
        -- An unavailable add-on must not stall the promotion queue.
        record.model = 'u_m_y_zombie_01'
        ent = CreatePed(4, GetHashKey(record.model), record.x + 0.0, record.y + 0.0, z + 0.0, (record.h or 0.0) + 0.0, true, true)
    end
    if not ent or ent == 0 then
        ZNet.stats.failed = ZNet.stats.failed + 1
        return false
    end
    -- the server entity exists synchronously; a few frames for safety
    local tries = 0
    while not DoesEntityExist(ent) and tries < 20 do Wait(0); tries = tries + 1 end
    if not DoesEntityExist(ent) then
        ZNet.stats.failed = ZNet.stats.failed + 1
        return false
    end
    -- The record may have been removed while we waited.
    if Registry.zombies[record.id] ~= record or record.ent then
        deleteEnt(ent, 'raced')
        return false
    end

    -- KeepEntity (2): the server never culls it on its own; deleting is ours.
    SetEntityOrphanMode(ent, 2)
    local cull = num(N().cullingRadius, 0.0)
    if cull > 0 then SetEntityDistanceCullingRadius(ent, cull + 0.0) end
    if needsGround then FreezeEntityPosition(ent, true) end

    record.ent = ent
    record.entCreated = (record.entCreated or 0) + 1
    record.demotedAt = nil
    record.farSince = nil
    record.net = NetworkGetNetworkIdFromEntity(ent)
    record.materialisedAt = record.materialisedAt or GetGameTimer()
    ZNet.ents[ent] = record.id
    ZNet.count = ZNet.count + 1
    ZNet.stats.created = ZNet.stats.created + 1

    bag(ent, 'bsZombie', record.id)
    bag(ent, 'zType', tostring(record.typeId or 'walker'))
    bag(ent, 'zGait', (variant and not record.crawler and variant.gait) or gaitFor(record.id, model, record.typeId, record.crawler))
    if variant then bag(ent, 'zArchetype', variant.id); bag(ent, 'zPace', variant.speed) end
    bag(ent, 'zReach', record.reacher == true)
    if record.look then bag(ent, 'zLook', record.look) end
    bag(ent, 'zGround', needsGround)
    mirrorBags(record, ent, true)
    return true
end

-- Hybrid population: a promoted filler walker gets its ped now, not on the next pass
function ZNet.SpawnNow(record)
    if not record or record.ent then return record and record.ent ~= nil end
    return spawnEnt(record)
end

-- Caps

-- Server frame time: how long one Wait(0) really takes, smoothed.
CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(0)
        local now = GetGameTimer()
        local dt = now - last
        last = now
        local p = ZNet.perf
        if p.samples < 20 then
            p.avg = ((p.avg * p.samples) + dt) / (p.samples + 1)
            p.samples = p.samples + 1
        else
            p.avg = p.avg * 0.98 + dt * 0.02
        end
    end
end)

-- Whole-server entity census, every 5 s (GetAll* allocate a table each call)
CreateThread(function()
    while true do
        local e = ZNet.entities
        local okP, peds = pcall(GetAllPeds)
        local okO, objs = pcall(GetAllObjects)
        local okV, vehs = pcall(GetAllVehicles)
        e.peds     = okP and type(peds) == 'table' and #peds or 0
        e.objects  = okO and type(objs) == 'table' and #objs or 0
        e.vehicles = okV and type(vehs) == 'table' and #vehs or 0
        e.total    = e.peds + e.objects + e.vehicles
        e.at       = GetGameTimer()
        Wait(5000)
    end
end)

local function fpsFactor(src)
    local n = N()
    local r = ZNet.fps[src]
    if not r or (GetGameTimer() - r.at) > (num(n.fpsReportMs, 5000) * 4) then return 1.0 end
    local good, low = num(n.fpsGood, 45), num(n.fpsLow, 25)
    local lowF = num(n.lowFpsFactor, 0.5)
    if r.fps >= good then return 1.0 end
    if r.fps <= low then return lowF end
    local t = (r.fps - low) / math.max(1, good - low)
    return lowF + (1.0 - lowF) * t
end

local function computeCap(nPlayers)
    local n = N()
    if nPlayers <= 0 then return 0, 'no players' end
    local base = num(n.baseCap, 24) + num(n.perPlayerCap, 18) * (nPlayers - 1)
    -- Difficulty density scales the cap; the hard cap stays absolute.
    local dens = ZDiff and ZDiff.Density() or 1.0
    base = math.min(math.floor(base * dens + 0.5), num(n.hardCap, 160))
    local why = {}
    -- Hybrid population: the shared cap eases off with a crowded server and at night (config_filler.lua)
    if ZFiller and ZFiller.Enabled() then
        local k = ZFiller.PlayerScale(#GetPlayers())
            * ZFiller.NightFactor(ZFiller.ServerHour and ZFiller.ServerHour() or nil)
        if k ~= 1.0 then
            base = math.floor(base * k + 0.5)
            why[#why + 1] = ('hybrid x%.2f'):format(k)
        end
    end
    local f = 1.0
    local budget = num(n.perfBudgetMs, 70.0)
    if ZNet.perf.avg > budget then
        f = math.max(num(n.perfMinFactor, 0.35), budget / ZNet.perf.avg)
        why[#why + 1] = ('perf %.0fms'):format(ZNet.perf.avg)
    end
    local soft, hard = num(n.entitySoft, 1400), num(n.entityHard, 1900)
    local tot = ZNet.entities.total
    if tot > soft and hard > soft then
        -- Floor like perf: objects from other resources must not zero the cap.
        local ef = math.max(num(n.perfMinFactor, 0.35), (hard - tot) / (hard - soft))
        if ef < f then f = ef end
        why[#why + 1] = ('entities %d'):format(tot)
    end
    local minimum = ZStream and ZStream.PresenceMin and ZStream.PresenceMin() or 0
    local floor = math.min(num(n.hardCap, 160), minimum * nPlayers)
    return math.max(floor, math.floor(base * f)), (#why > 0 and table.concat(why, ', ') or 'ok')
end

-- The pass

local lastCapWhy = 'ok'

local function pass()
    local n = N()
    local list = players()
    local now = GetGameTimer()
    if #list > 0 then
        ZNet.lastObserverAt = now
    elseif #GetPlayers() > 0 and ZNet.lastObserverAt and now - ZNet.lastObserverAt < num(n.demoteGraceMs, 10000) then
        return
    end
    local promoteR = num(n.promoteRadius, 300.0)
    local keepR = promoteR + num(n.demoteHysteresis, 60.0)
    local cap, why = computeCap(#list)
    local npcSum = npcLoadSum()
    -- NPC load never takes more than 3/4 of the cap.
    if npcSum > 0 then cap = math.max(math.floor(cap * 0.25), cap - npcSum) end
    ZNet.cap, lastCapWhy = cap, why
    ZNet.capWhy = why

    -- 1. SYNC every networked walker from its entity.
    local live = {}
    local lost = {}
    for ent, id in pairs(ZNet.ents) do
        local record = Registry.zombies[id]
        if not record or record.ent ~= ent then
            -- record vanished without OnRemove (should not happen) - clean up
            ZNet.ents[ent] = nil
            ZNet.count = math.max(0, ZNet.count - 1)
            deleteEnt(ent, 'stale')
        elseif not DoesEntityExist(ent) then
            -- entityRemoved normally handles this first. The walker is over: it never comes back with a new ped.
            lost[#lost + 1] = record.id
        else
            local at = GetEntityCoords(ent)
            if not (at.x == 0.0 and at.y == 0.0) then
                record.x, record.y = at.x, at.y
                if at.z > 1.0 then record.z = at.z; record.needsGround = false end
                record.h = GetEntityHeading(ent)
                record.movedBy = 'net'
                record.movedAt = now
                if Registry.GridPut then Registry.GridPut(record) end
            end
            local owner = NetworkGetEntityOwner(ent)
            owner = (owner and owner > 0) and owner or nil
            if owner ~= record.netOwner then
                record.netOwner = owner
                if Registry.AssignHost then pcall(Registry.AssignHost, record) end
            end
            mirrorBags(record, ent, false)
            local d, who = nearest(list, record.x, record.y)
            if d > keepR and not record.event then
                record.farSince = record.farSince or now
                if now - record.farSince >= num(n.demoteGraceMs, 10000) then
                    demote(record, 'far')
                else
                    live[#live + 1] = { record = record, d = d }
                end
            else
                record.farSince = nil
                if who and d <= promoteR then who.near = who.near + 1 end
                live[#live + 1] = { record = record, d = d }
            end
        end
    end

    for _, id in ipairs(lost) do
        local record = Registry.zombies[id]
        if record then clearRecordEnt(record); Registry.Remove(id, 'entity-lost') end
    end

    -- 2. SHED over the cap / entity hard limit, farthest first.
    local over = #live - cap
    local hyst = num(n.capHysteresis, 4)
    if over > 0 and over <= hyst and cap > 0 then over = 0 end
    local hardEnt = ZNet.entities.total >= num(n.entityHard, 1900)
    if hardEnt and (ZNet.entities.at or 0) > (ZNet.lastHardShedAt or 0) then
        over = math.max(over, num(n.shedPerTick, 6))
        ZNet.lastHardShedAt = GetGameTimer()
    end
    local minimum = ZStream and ZStream.PresenceMin and ZStream.PresenceMin() or 0
    over = math.min(over, math.max(0, #live - minimum * #list))
    if over > 0 then
        table.sort(live, function(a, b) return a.d > b.d end)
        local shed = math.min(over, num(n.shedPerTick, 6))
        for i = 1, shed do
            local r = live[i] and live[i].record
            if r and r.ent then
                demote(r, 'cap')
                ZNet.stats.shed = ZNet.stats.shed + 1
            end
        end
        return
    end

    -- 3. PROMOTE nearest records first.
    local room = math.min(cap - ZNet.count, num(n.spawnPerTick, 4))
    if room <= 0 or #list == 0 then return end
    local cands = {}
    for _, record in pairs(Registry.zombies) do
        if not record.ent and not record.dead and record.hp and record.hp > 0 then
            local d, who = nearest(list, record.x, record.y)
            if d <= promoteR and who then cands[#cands + 1] = { record = record, d = d, who = who } end
        end
    end
    if #cands == 0 then return end
    if ZNet.count == 0 and now - (ZNet.lastWarnAt or 0) > 30000 then
        ZNet.lastWarnAt = now
        print(('^3[BS ZNET]^7 %d record(s) in range, 0 peds: cap=%d (%s) room=%d npcLoad=%d entities=%d')
            :format(#cands, cap, lastCapWhy, room, npcSum, ZNet.entities.total))
    end
    for _, p in ipairs(list) do
        p.close = ZStream and ZStream.PedsNear
            and ZStream.PedsNear(p.x,p.y,p.z,tonumber((Zombies.Ambient or {}).radius) or 200.0) or p.near
    end
    table.sort(cands, function(a, b)
        local an, bn = a.who.close or 0, b.who.close or 0
        if (an < minimum) ~= (bn < minimum) then return an < minimum end
        if an < minimum and bn < minimum and an ~= bn then return an < bn end
        return a.d < b.d
    end)
    local perNear = math.floor(num(n.perPlayerNear, 34) * (ZDiff and ZDiff.Density() or 1.0) + 0.5)
    for _, c in ipairs(cands) do
        if room <= 0 then break end
        local fq = math.floor(perNear * fpsFactor(c.who.src))
        local quota = math.max(math.floor(fq * 0.25), fq - npcLoadOf(c.who.src))
        quota = math.max(minimum, quota)
        if c.who.near < quota then
            if spawnEnt(c.record) then
                c.who.near = c.who.near + 1
                room = room - 1
            end
        end
    end
end

CreateThread(function()
    -- Leftovers from a previous run of this resource (state bags survive a restart).
    Wait(2000)
    local ok, peds = pcall(GetAllPeds)
    local n = 0
    for _, p in ipairs(ok and peds or {}) do
        local st = Entity(p).state
        if st and st.bsZombie ~= nil then deleteEnt(p, 'boot'); n = n + 1 end
    end
    if n > 0 then log('removed %d networked walker ped(s) left over from a previous run', n) end
    while true do
        Wait(math.max(150, math.floor(num(N().tickMs, 500))))
        if Zombies.Settings.enabled ~= false then
            local okP, err = pcall(pass)
            if not okP then print('^1[BS ZNET]^7 pass error: ' .. tostring(err)) end
        end
    end
end)

-- Registry hooks

function ZNet.CorpseLifetime(playerCount, pedCount, looted)
    local c = N().corpseRetention or {}
    local soft, hard = num(c.poolSoft, 128), num(c.poolHard, 215)
    local pool = math.max(0.0, math.min(1.0, (pedCount - soft) / math.max(1, hard - soft)))
    local crowd = math.max(0.0, math.min(1.0, (playerCount - 1) / math.max(1, num(c.playersAtMinimum, 32) - 1)))
    local pressure = math.max(pool, crowd)
    local longest = looted and num(c.lootedSeconds, 60) or num(N().corpseSeconds, 300)
    local shortest = looted and num(c.lootedMinSeconds, 15) or num(c.minSeconds, 45)
    return math.max(5, longest + (math.min(longest, shortest) - longest) * pressure)
end

local function corpsePressure(ent, list)
    local peds = 0
    local count = #list
    local at, now = GetEntityCoords(ent), GetGameTimer()
    for _, p in ipairs(list) do
        local t = ZStream and ZStream.telemetry and ZStream.telemetry[p.src]
        if t and now - t.updatedAt <= 10000 and (p.x-at.x)^2 + (p.y-at.y)^2 <= 474.0^2 then
            peds = math.max(peds, t.pedCount or 0)
        end
    end
    if count <= 1 then peds = math.max(peds, ZNet.entities.peds or 0) end
    return count, peds
end

function ZNet.LootCorpse(id)
    for _, c in pairs(ZNet.corpses) do
        if tostring(c.id) == tostring(id) then c.lootedAt = GetGameTimer(); return true end
    end
    return false
end

-- Called by sv_registry removeZombie() BEFORE the record is dropped.
function ZNet.OnRemove(record, reason)
    local ent = record and record.ent
    if not ent then return end
    clearRecordEnt(record)
    if CORPSE_REASONS[reason] and DoesEntityExist(ent) then
        bag(ent, 'bsZombieDead', true)
        bag(ent, 'zState', 'dead')
        ZNet.corpses[ent] = {
            id = record.id,
            bornAt = GetGameTimer(),
            untilAt = GetGameTimer() + num(N().corpseSeconds, 120) * 1000,
            -- The owner must confirm the ped really died (bs:z:net:deadAck), see the death confirmation below
            deathAt = GetGameTimer(),
            net = NetworkGetNetworkIdFromEntity(ent),
        }
        ZNet.stats.corpses = ZNet.stats.corpses + 1
        -- Corpses have their own cap (corpseCap) so dead bodies do not fill client ped pools
        local capN = num(N().corpseCap, 96)
        -- A body someone is searching or skinning is never picked by the cap.
        local now = GetGameTimer()
        local n, oldestEnt, oldestAt = 0, nil, math.huge
        for e, c in pairs(ZNet.corpses) do
            n = n + 1
            if (c.heldUntil or 0) <= now and c.untilAt < oldestAt then oldestEnt, oldestAt = e, c.untilAt end
        end
        while n > capN and oldestEnt do
            deleteEnt(oldestEnt, 'corpse-cap')
            n = n - 1
            oldestEnt, oldestAt = nil, math.huge
            for e, c in pairs(ZNet.corpses) do
                if (c.heldUntil or 0) <= now and c.untilAt < oldestAt then oldestEnt, oldestAt = e, c.untilAt end
            end
        end
    else
        deleteEnt(ent, reason or 'removed')
    end
end

-- For assignHost(): the engine owner IS the host of a networked walker.
function ZNet.HostCandidates(record)
    if not record.ent then return nil end
    if record.netOwner then return { { src = record.netOwner, dist = 0.0 } } end
    return {}
end

-- A body being searched must outlive the search
function ZNet.HoldCorpse(id, ms)
    id = tostring(id)
    local untilAt = GetGameTimer() + math.min(tonumber(ms) or 20000, 30000)
    for _, c in pairs(ZNet.corpses) do
        if tostring(c.id) == id then
            if c.untilAt < untilAt then c.untilAt = untilAt end
            -- heldUntil also keeps it out of the cap and the timed delete below.
            if (c.heldUntil or 0) < untilAt then c.heldUntil = untilAt end
            return true
        end
    end
    return false
end

-- Corpses: make sure they are dead, then delete them on time.
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        local observers = players()
        local trimmed = {}
        local order = {}
        for ent, c in pairs(ZNet.corpses) do order[#order + 1] = { ent = ent, c = c } end
        table.sort(order, function(a, b)
            if (a.c.lootedAt ~= nil) ~= (b.c.lootedAt ~= nil) then return a.c.lootedAt ~= nil end
            return (a.c.bornAt or 0) < (b.c.bornAt or 0)
        end)
        for _, row in ipairs(order) do
            local ent, c = row.ent, row.c
            if DoesEntityExist(ent) and (c.heldUntil or 0) <= now then
                local at = GetEntityCoords(ent)
                for _, p in ipairs(observers) do
                    local t = ZStream and ZStream.telemetry and ZStream.telemetry[p.src]
                    if t and now-t.updatedAt <= 10000 and (p.x-at.x)^2+(p.y-at.y)^2 <= 474.0^2
                       and t.pedCount >= num((N().corpseRetention or {}).poolHard, 215)
                       and (trimmed[p.src] or 0) < t.pedCount - 190 then
                        deleteEnt(ent, 'corpse-pressure')
                        for _, observer in ipairs(observers) do
                            if (observer.x-at.x)^2+(observer.y-at.y)^2 <= 474.0^2 then
                                trimmed[observer.src] = (trimmed[observer.src] or 0) + 1
                            end
                        end
                        break
                    end
                end
            end
        end
        for ent, c in pairs(ZNet.corpses) do
            local deadline = c.untilAt
            if DoesEntityExist(ent) and c.bornAt then
                local count, peds = corpsePressure(ent, observers)
                deadline = math.min(deadline, (c.lootedAt or c.bornAt)
                    + ZNet.CorpseLifetime(count, peds, c.lootedAt ~= nil) * 1000)
            end
            if not DoesEntityExist(ent) then
                ZNet.corpses[ent] = nil
            elseif now >= deadline and (c.heldUntil or 0) <= now then
                deleteEnt(ent, 'corpse')
            end
        end
    end
end)

-- Death confirmation. The server decides a walker is dead; the ped only dies on the client that owns it.
-- The server copy of a walker's engine health is not trustworthy (live walkers read 0 there), so the owner
-- confirms instead. No confirmation within deathConfirmMs: every client is told to kill or drop it.
-- Still none after deathReplaceMs more: the entity is deleted, so no walker stays standing after it died.
RegisterNetEvent('bs:z:net:deadAck', function(id, net)
    local src = source
    local ent = NetworkGetEntityFromNetworkId(tonumber(net) or 0)
    if not ent or ent == 0 then return end
    local c = ZNet.corpses[ent]
    if not c or tostring(c.id) ~= tostring(id) or c.ack then return end
    if NetworkGetEntityOwner(ent) ~= src and c.forcedAt == nil then return end
    c.ack, c.ackAt = src, GetGameTimer()
    ZNet.stats.deathAcked = ZNet.stats.deathAcked + 1
end)

CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        local confirmMs = num(N().deathConfirmMs, 1500)
        local replaceMs = num(N().deathReplaceMs, 2500)
        for ent, c in pairs(ZNet.corpses) do
            if c.deathAt and not c.ack and DoesEntityExist(ent) then
                if not c.forcedAt and now - c.deathAt >= confirmMs then
                    c.forcedAt = now
                    ZNet.stats.deathForced = ZNet.stats.deathForced + 1
                    local owner = NetworkGetEntityOwner(ent)
                    if not owner or owner <= 0 then
                        -- nobody can kill it (server-owned): a standing corpse is worse than none
                        deleteEnt(ent, 'corpse-unowned')
                    else
                        TriggerClientEvent('bs:z:netkill', -1, c.net, c.id)
                    end
                elseif c.forcedAt and now - c.forcedAt >= replaceMs then
                    ZNet.stats.deathReplaced = ZNet.stats.deathReplaced + 1
                    print(('^3[BS ZNET]^7 walker %s died on the server but its owner (src %s) never confirmed the ped died - entity deleted (%d so far)')
                        :format(tostring(c.id), tostring(NetworkGetEntityOwner(ent)), ZNet.stats.deathReplaced))
                    deleteEnt(ent, 'corpse-unconfirmed')
                end
            end
        end
    end
end)

-- Deletion guard

AddEventHandler('entityRemoved', function(ent)
    local expectedWhy = ZNet.expected[ent]
    ZNet.expectedAt[ent] = nil
    if expectedWhy then ZNet.expected[ent] = nil; return end
    if ZNet.corpses[ent] then ZNet.corpses[ent] = nil; return end
    local id = ZNet.ents[ent]
    if not id then return end
    local record = Registry.zombies[id]
    local owner = record and record.netOwner
    ZNet.ents[ent] = nil
    ZNet.count = math.max(0, ZNet.count - 1)
    ZNet.stats.unexpected = ZNet.stats.unexpected + 1
    if record and record.ent == ent then
        record.ent, record.net, record.netOwner, record._bags = nil, nil, nil, nil
    end
    print(('^1[BS ZNET]^7 walker %s entity removed WITHOUT a server reason (owner src %s) - %d so far')
        :format(tostring(id), tostring(owner), ZNet.stats.unexpected))
    -- Logged, not flagged: walkers can vanish without cheating. The record ends with its ped: re-creating it
    -- under the same id gave a "new" walker at the same spot (a killed walker coming back with another look).
    if record then Registry.Remove(id, 'entity-deleted') end
end)

-- Orphans: bsZombie peds the registry does not know (resource restarts, races).
CreateThread(function()
    while true do
        Wait(math.max(2000, math.floor(num(N().orphanSweepMs, 10000))))
        local ok, peds = pcall(GetAllPeds)
        local now = GetGameTimer()
        for _, p in ipairs(ok and peds or {}) do
            -- A delete that has not landed after 15 s did not work: the ped is an orphan again
            if ZNet.expected[p] and now - (ZNet.expectedAt[p] or now) > 15000 then
                ZNet.expected[p], ZNet.expectedAt[p] = nil, nil
                ZNet.stats.staleDeletes = (ZNet.stats.staleDeletes or 0) + 1
            end
            if not ZNet.ents[p] and not ZNet.corpses[p] and not ZNet.expected[p] then
                local st = Entity(p).state
                local id = st and st.bsZombie
                if id ~= nil then
                    local record = Registry.zombies[tonumber(id) or -1]
                    if not (record and record.ent == p) then
                        ZNet.stats.orphans = ZNet.stats.orphans + 1
                        deleteEnt(p, 'orphan')
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ent in pairs(ZNet.ents) do ZNet.expected[ent] = 'stop'; if DoesEntityExist(ent) then DeleteEntity(ent) end end
    for ent in pairs(ZNet.corpses) do ZNet.expected[ent] = 'stop'; if DoesEntityExist(ent) then DeleteEntity(ent) end end
end)

-- Client reports

RegisterNetEvent('bs:z:net:fps', function(fps)
    local src = source
    fps = tonumber(fps)
    if not fps then return end
    local r = ZNet.fps[src]
    local now = GetGameTimer()
    if r and now - r.at < 1000 then return end
    ZNet.fps[src] = { fps = math.max(0, math.min(500, fps)), at = now }
end)

AddEventHandler('playerDropped', function() ZNet.fps[source] = nil end)

RegisterNetEvent('bs:z:net:grounded', function(id, z)
    local src = source
    local record = Registry.zombies[tonumber(id) or -1]
    if not record or not record.ent or record.netOwner ~= src then return end
    z = tonumber(z)
    if z and z > -100.0 and z < 2000.0 then record.z = z; record.needsGround = false end
    bag(record.ent, 'zGround', false)
end)

RegisterNetEvent('bs:z:net:groundFailed', function(id)
    local record = Registry.zombies[tonumber(id) or -1]
    if not record or not record.ent or record.netOwner ~= source then return end
    demote(record, 'noGround')
end)

RegisterNetEvent('bs:z:net:app', function(id)
    local src = source
    local record = Registry.zombies[tonumber(id) or -1]
    if not record or not record.ent or record.netOwner ~= src then return end
    bag(record.ent, 'zApp', true)
end)

-- Diagnostics (/zdiag appends these, /znet prints them)

function ZNet.NearCount(src, radius)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return 0 end
    local at = GetEntityCoords(ped)
    local n = 0
    radius = radius or 424.0
    for ent in pairs(ZNet.ents) do
        if DoesEntityExist(ent) then
            local p = GetEntityCoords(ent)
            if (p.x - at.x) ^ 2 + (p.y - at.y) ^ 2 <= radius * radius then n = n + 1 end
        end
    end
    return n
end

function ZNet.DiagLines(src)
    local s, e = ZNet.stats, ZNet.entities
    local out = {}
    out[#out + 1] = ('^5[BS ZNET]^7 networked=%d cap=%d (%s) | frame avg %.1fms | entities %d (peds %d obj %d veh %d)')
        :format(ZNet.count, ZNet.cap, lastCapWhy, ZNet.perf.avg, e.total, e.peds, e.objects, e.vehicles)
    local c = 0
    for _ in pairs(ZNet.corpses) do c = c + 1 end
    out[#out + 1] = ('   created %d | failed %d | demoted %d | shed %d | corpses now %d (total %d) | unexpected deletes %d (replaced %d) | orphans %d')
        :format(s.created, s.failed, s.demoted, s.shed, c, s.corpses, s.unexpected, s.replaced, s.orphans)
    if src and src > 0 then
        local r = ZNet.fps[src]
        out[#out + 1] = ('   you: %d networked walker(s) within 424m | fps %s (factor %.2f)')
            :format(ZNet.NearCount(src), r and tostring(math.floor(r.fps)) or '?', fpsFactor(src))
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local at = GetEntityCoords(ped)
            local owned, low, high, grounding, zeroHealth, unreported = 0, 0, 0, 0, 0, 0
            for ent, id in pairs(ZNet.ents) do
                if DoesEntityExist(ent) then
                    local p = GetEntityCoords(ent)
                    if (p.x-at.x)^2 + (p.y-at.y)^2 <= 200.0^2 then
                        if NetworkGetEntityOwner(ent) and NetworkGetEntityOwner(ent) > 0 then owned = owned + 1 end
                        if p.z < at.z - 40.0 then low = low + 1 end
                        if p.z > at.z + 40.0 then high = high + 1 end
                        if Entity(ent).state.zGround then grounding = grounding + 1 end
                        if GetEntityHealth(ent) <= 0 then zeroHealth = zeroHealth + 1 end
                        if not (Registry.zombies[id] or {}).lastReport then unreported = unreported + 1 end
                    end
                end
            end
            local actual = ZStream and ZStream.PedsNear and ZStream.PedsNear(at.x,at.y,at.z,200.0) or 0
            out[#out+1] = ('   encounter: %d grounded/alive within 200m | owned %d | below %d above %d grounding %d | bucket %s')
                :format(actual,owned,low,high,grounding,tostring(GetPlayerRoutingBucket(src)))
            out[#out+1] = ('   entity checks: server-health-zero=%d (server copy only, not used for deaths) owner-never-reported=%d'):format(zeroHealth,unreported)
        end
    end
    local d = ZNet.demotedBy or {}
    out[#out+1] = ('   demotions: far=%d cap=%d'):format(d.far or 0,d.cap or 0)
    local hs = Registry.hitStats or {}
    local refused = {}
    for k, v in pairs(hs.refused or {}) do refused[#refused + 1] = k .. '=' .. v end
    table.sort(refused)
    out[#out+1] = ('   hits: received %d applied %d deaths %d | refused %s'):format(hs.received or 0, hs.applied or 0,
        hs.deaths or 0, #refused > 0 and table.concat(refused, ' ') or 'none')
    out[#out+1] = ('   deaths: owner-confirmed %d forced %d deleted-unconfirmed %d | reports healed %d refused %d | stale deletes %d')
        :format(s.deathAcked or 0, s.deathForced or 0, s.deathReplaced or 0, Registry.reportHealed or 0,
                Registry.reportRefused or 0, s.staleDeletes or 0)
    return out
end

RegisterCommand('znet', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    for _, line in ipairs(ZNet.DiagLines(src)) do
        print(line)
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { line } }) end
    end
end, false)

log('networked walkers ON (promote %.0fm, base cap %d, hard cap %d)',
    num(N().promoteRadius, 300.0), num(N().baseCap, 24), num(N().hardCap, 160))
