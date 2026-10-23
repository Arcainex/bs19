-- bs_zombies - ped pool watchdog

local S = Zombies.Settings

-- Thresholds: the ped pool is 256
local PED_POOL      = 256
local SOFT_LIMIT    = 190
local HARD_LIMIT    = 215
local CHECK_EVERY   = 2000

local lastReport = 0

local function count(pool)
    local ok, list = pcall(GetGamePool, pool)
    return (ok and type(list) == 'table') and #list or 0
end

-- What is in there

-- The models filling a pool, most common first
local function census(pool, limit)
    local ok, list = pcall(GetGamePool, pool)
    if not ok or type(list) ~= 'table' then return {} end

    -- Uses BS.Util.ModelOf, not GetEntityModel
    local byModel = {}
    for _, entity in ipairs(list) do
        local model = BS.Util.ModelOf(entity)
        if model then byModel[model] = (byModel[model] or 0) + 1 end
    end

    local out = {}
    for model, n in pairs(byModel) do out[#out + 1] = { model = model, n = n } end
    table.sort(out, function(a, b) return a.n > b.n end)

    while #out > (limit or 8) do table.remove(out) end
    return out
end

local function report(reason, peds)
    -- Once a minute at most
    if GetGameTimer() - lastReport < 60000 then return end
    lastReport = GetGameTimer()

    print(('^3[BeyondSurvival]^7 (pools) %s - peds %d/%d, objects %d, vehicles %d')
        :format(reason, peds, PED_POOL, count('CObject'), count('CVehicle')))

    for _, row in ipairs(census('CPed', 6)) do
        print(('^3[BeyondSurvival]^7 (pools)   %d x model %s'):format(row.n, row.model))
    end

    print(('^3[BeyondSurvival]^7 (pools)   ours: %d walker(s), %d corpse(s)')
        :format(Zed.count or 0, Zed.CorpseCount and Zed.CorpseCount() or -1))
end

-- Making room

-- The walkers furthest from the player, in order
local function furthestFirst()
    local at = GetEntityCoords(PlayerPedId())
    local out = {}

    for id, entry in pairs(Zed.live or {}) do
        -- Networked walkers are server entities
        if entry.ped and not entry.net and DoesEntityExist(entry.ped) then
            local d = #(at - GetEntityCoords(entry.ped))
            -- never cull a walker that is close or fighting someone
            local busy = entry.state == 'hunting' or entry.state == 'grab'
                      or entry.state == 'drawn' or entry.state == 'disturbed'
            if d > 60.0 and not busy then
                out[#out + 1] = { id = id, d = d }
            end
        end
    end

    table.sort(out, function(a, b) return a.d > b.d end)
    return out
end

CreateThread(function()
    while true do
        Wait(CHECK_EVERY)

        local peds = count('CPed')
        if peds < SOFT_LIMIT then goto continue end

        report('ped pool filling up', peds)

        -- Corpses first, oldest first, and as many as it takes
        local freed = Zed.CullCorpses and Zed.CullCorpses(peds - SOFT_LIMIT + 10) or 0

        peds = count('CPed')

        -- If still too full, remove live walkers, farthest first
        if peds >= HARD_LIMIT then
            local list = furthestFirst()
            local want = peds - SOFT_LIMIT

            for i = 1, math.min(want, #list) do
                Zed.Despawn(list[i].id)
                freed = freed + 1
            end
        end

        if freed > 0 then
            print(('^3[BeyondSurvival]^7 (pools) freed %d ped(s) to stay under the pool limit')
                :format(freed))
        end

        ::continue::
    end
end)

-- Asking it directly

RegisterCommand('pools', function()
    local peds = count('CPed')

    print('^5[BS POOLS]^7 -------------------------------------------')
    print(('^5[BS POOLS]^7 peds      %d / %d'):format(peds, PED_POOL))
    print(('^5[BS POOLS]^7 objects   %d'):format(count('CObject')))
    print(('^5[BS POOLS]^7 vehicles  %d'):format(count('CVehicle')))
    print(('^5[BS POOLS]^7 pickups   %d'):format(count('CPickup')))
    print(('^5[BS POOLS]^7 ours      %d walker(s), %d corpse(s)')
        :format(Zed.count or 0, Zed.CorpseCount and Zed.CorpseCount() or -1))

    print('^5[BS POOLS]^7 --- what the ped pool is full of ---')
    for _, row in ipairs(census('CPed', 10)) do
        print(('^5[BS POOLS]^7   %d x model %s'):format(row.n, row.model))
    end

    print('^5[BS POOLS]^7 --- and the object pool ---')
    for _, row in ipairs(census('CObject', 10)) do
        print(('^5[BS POOLS]^7   %d x model %s'):format(row.n, row.model))
    end

    TriggerEvent('bs:ui:notify', {
        type = peds >= SOFT_LIMIT and 'warn' or 'info',
        message = ('Peds %d/%d - full listing in F8.'):format(peds, PED_POOL),
        duration = 4000,
    })
end, false)

-- Spawn window
-- Prints a census every 400ms for the first 12 seconds in the world, to catch a pool crash right after the character loads

-- Hooked to :loaded instead of :spawned, because the pool crash lands before the spawn sequence finishes
local SPAWN_CENSUS = false

AddEventHandler('bs:hook:player:loaded', function()
    if not SPAWN_CENSUS then return end
    CreateThread(function()
        for i = 1, 90 do
            print(('^5[BS POOLS]^7 t+%.1fs  peds %d  vehicles %d  objects %d  pickups %d  (ours: %d walkers, %d corpses)')
                :format(i * 0.2,
                    count('CPed'), count('CVehicle'), count('CObject'), count('CPickup'),
                    Zed.count or 0, Zed.CorpseCount and Zed.CorpseCount() or -1))
            Wait(200)
        end

        print('^5[BS POOLS]^7 spawn window survived - census off')
    end)
end)
