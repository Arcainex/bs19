-- ZProbe stays as an empty table so /zgait keeps working.
ZProbe = ZProbe or { task = {}, driven = {}, rate = {} }

-- bs_zombies - zombie damage and death handling

local S = Zombies.Settings

local HEAD_BONES = { [31086] = true, [39317] = true }
local corpses = {}

-- File-local state. deathTally is the death summary bucket (see the summary thread at the bottom).
local Combat = { deathTally = nil }

-- Helpers

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

local function hasExecutioner()
    if GetResourceState('bs_skills') ~= 'started' then return false end
    local ok, value = pcall(function() return exports.bs_skills:HasFlag('executioner') end)
    return ok and value == true
end

local function weaponName()
    local ok, hash = pcall(GetSelectedPedWeapon, PlayerPedId())
    return ok and tostring(hash) or 'unknown'
end

-- Melee is one hit
local GROUP_MELEE   = GetHashKey('GROUP_MELEE')
local GROUP_UNARMED = GetHashKey('GROUP_UNARMED')

local function meleeScale(weaponHash)
    if not weaponHash or weaponHash == 0 then return nil end
    local ok, group = pcall(GetWeapontypeGroup, weaponHash)
    if not ok then return nil end
    if group == GROUP_MELEE then return S.meleeDamageScale or 12.0 end
    if group == GROUP_UNARMED then return S.unarmedDamageScale or 2.0 end
    return nil
end

-- Corpses

-- Corpse cap: bodies are peds and the ped pool is limited, so the cap is enforced when a body is created
local function corpseCount()
    local n = 0
    for _ in pairs(corpses) do n = n + 1 end
    return n
end

-- The body this player is kneeling over
local lootingPed = nil

-- Bodies someone is kneeling over right now (search or skin): [ped] = hold expiry.
local heldPeds = {}

local function isHeld(ped)
    if ped == lootingPed then return true end
    local untilAt = heldPeds[ped]
    if not untilAt then return false end
    if GetGameTimer() < untilAt then return true end
    heldPeds[ped] = nil
    return false
end

local function holdCorpse(ped, ms)
    heldPeds[ped] = GetGameTimer() + (ms or 20000)
end

local function releaseCorpse(ped)
    if isHeld(ped) and DoesEntityExist(ped) then return end
    heldPeds[ped] = nil
    -- Remove the row first, then the entity
    corpses[ped] = nil

    if Zed and Zed.DestroyPed then
        Zed.DestroyPed(ped)
        return
    end

    -- Fallback for a load order where cl_sync has not defined it yet
    if GetResourceState('bs_interactions') == 'started' then
        pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
    end
    if DoesEntityExist(ped) then
        SetEntityAsNoLongerNeeded(ped)
        DeleteEntity(ped)
    end
end

-- Register the corpse table with Zed
if Zed and Zed.OnPedForgotten then
    Zed.OnPedForgotten('cl_combat corpses', function(ped)
        corpses[ped] = nil
        heldPeds[ped] = nil
    end)
end

-- Removes the n oldest bodies
local function cullCorpses(n)
    if n <= 0 then return 0 end

    local order = {}
    for ped, record in pairs(corpses) do
        if not isHeld(ped) then
            order[#order + 1] = { ped = ped, at = record.diesAt }
        end
    end

    -- diesAt is set at death, so the smallest is the oldest body.
    table.sort(order, function(a, b) return a.at < b.at end)

    local taken = 0
    for i = 1, math.min(n, #order) do
        releaseCorpse(order[i].ped)
        taken = taken + 1
    end

    return taken
end

Zed = Zed or {}
Zed.CorpseCount = corpseCount
Zed.CullCorpses = cullCorpses

local function registerCorpse(ped, id, loot)
    Crumb('corpse', 'zombie id=%s ped=%s', tostring(id), tostring(ped))
    corpses[ped] = { id = id, loot = loot or 'walker', diesAt = GetGameTimer() + (S.corpseLifetime * 1000) }

    -- Apply the corpse ceiling immediately.
    local most = S.maxCorpses or 10
    local over = corpseCount() - most
    if over > 0 then cullCorpses(over) end

    if GetResourceState('bs_interactions') ~= 'started' then return end

    -- Use an event name, not a closure: functions do not survive the call into bs_interactions
    pcall(function()
        exports.bs_interactions:AddEntity(ped, {
            {
                label = L('zed.search_body'),
                labelKey = 'zed.search_body',
                icon  = 'hand',
                distance = 2.0,
                event = 'bs:zombies:dot:loot',
            },
            -- Handled by bs_crafting (rotten flesh, bones, rags). Needs a knife.
            {
                label = L('zed.skin'),
                labelKey = 'zed.skin',
                icon  = 'hand',
                distance = 2.0,
                event = 'bs:crafting:skinZombie',
                args  = { zid = tostring(id) },
            },
        })
    end)
end

-- Searching a body

local looting = false

AddEventHandler('bs:zombies:dot:loot', function(payload)
    local ped = payload and payload.entity
    if not ped or looting then return end

    local record = corpses[ped]
    if not record or not DoesEntityExist(ped) then return notify('warn', L('zed.nothing_left')) end

    looting = true
    lootingPed = ped
    holdCorpse(ped, 20000)

    CreateThread(function()
        -- Bodies are shared: the server decides whether this one was already searched, by anyone.
        local check = BSB.Await('zombies:lootCheck', 6000, tostring(record.id))
        if not check or not check.ok or not DoesEntityExist(ped) then
            looting, lootingPed = false, nil
            heldPeds[ped] = nil
            return notify('warn', (check and check.error) or L('zed.picked'))
        end

        -- Kneeling pose for the search
        local done = exports.bs_interactions:RunSearch('Searching body', 3200, { pose = 'kneel', entity = ped })
        lootingPed = nil
        heldPeds[ped] = nil
        if not done then looting = false return end

        local result = BSB.Await('zombies:loot', 10000, tostring(record.id), record.loot)

        looting = false

        if not result or not result.ok then
            return notify('warn', (result and result.error) or L('zed.nothing_worth'))
        end
        if #(result.items or {}) == 0 then return notify('info', L('zed.rags')) end

        -- items holds two shapes: { item, amount, label } and { cash, label }
        for _, entry in ipairs(result.items) do
            if entry.cash then
                notify('success', ('+%s'):format(entry.label or ('$' .. tostring(entry.cash))), 2200)
            else
                local amount = tonumber(entry.amount) or 1
                notify('success', ('+%d %s'):format(amount, entry.label or entry.item or 'item'), 2200)
            end
            Wait(120)
        end
    end)
end)

-- Skinning is run by bs_crafting
AddEventHandler('bs:crafting:skinZombie', function(payload)
    local ped = payload and payload.entity
    if not ped or not corpses[ped] then return end
    local ms = 20000
    holdCorpse(ped, ms)
    TriggerServerEvent('bs:zombies:holdCorpse', tostring(corpses[ped].id), ms)
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for ped, record in pairs(corpses) do
            if not DoesEntityExist(ped) then
                -- Gone already (reclaimed by the engine or a resource restart)
                releaseCorpse(ped)
            elseif now >= record.diesAt then
                releaseCorpse(ped)
            end
        end
    end
end)

-- Our damage, to them

-- Sample interval and revive budget live in Zombies.Detector
local SAMPLE_MS   = (Zombies.Detector and Zombies.Detector.sampleInterval) or 80
local MAX_REVIVES = (Zombies.Detector and Zombies.Detector.maxEngineRevives) or 3

-- Unkillable walker recovery

-- Some walkers could not be killed

local D               = Zombies.Detector or {}
local STUCK_HITS      = D.stuckHits or 4
local STUCK_WINDOW    = D.stuckWindowMs or 4000
local REASSERT_FLAGS  = D.reassertFlags ~= false
local VERIFY_SERVER   = D.verifyWithServer ~= false
local DROP_AFTER      = D.dropAfterCycles or 3

-- Called on every hit this client reports

-- Damage now comes from the shooter side

-- Roadkill and environment deaths are victim-side: a car or a fall has no shooter to raycast
local ENV_WATCH_MS = 250

CreateThread(function()
    while true do
        Wait(ENV_WATCH_MS)

        local playerPed = PlayerPedId()
        local playerVeh = GetVehiclePedIsIn(playerPed, false)

        for id, entry in pairs(Zed.live) do
            if entry.ped and DoesEntityExist(entry.ped) and not entry.dying then
                if IsEntityDead(entry.ped) or GetEntityHealth(entry.ped) <= 0 then
                    -- Attribution is asked once here; a wrong answer only costs a kill credit.
                    local byVehicle = playerVeh ~= 0
                        and HasEntityBeenDamagedByEntity(entry.ped, playerVeh, true)
                    local hitByCar = byVehicle or HasEntityBeenDamagedByAnyVehicle(entry.ped)

                    if hitByCar and not entry.vehKillOk then
                        -- Engine crash death our thresholds did not approve: undo it.
                        entry.vehUndos = (entry.vehUndos or 0) + 1
                        -- Only resurrect peds we own; a remote clone must not be revived here.
                        if entry.vehUndos <= 3 and DoesEntityExist(entry.ped)
                            and (not NetworkGetEntityIsNetworked(entry.ped) or NetworkHasControlOfEntity(entry.ped)) then
                            local pos = GetEntityCoords(entry.ped)
                            ResurrectPed(entry.ped)
                            SetEntityHealth(entry.ped, (Zombies.Detector and Zombies.Detector.engineHealthPool) or 20000)
                            ClearPedTasksImmediately(entry.ped)
                            SetEntityCoordsNoOffset(entry.ped, pos.x, pos.y, pos.z, false, false, false)
                            ClearEntityLastDamageEntity(entry.ped)
                            goto continue
                        end
                        -- Resurrect keeps failing; treat as the world, no credit.
                        entry.dying = true
                        TriggerServerEvent('bs:z:envdeath', id)
                        goto continue
                    end

                    entry.dying = true

                    if byVehicle and entry.vehKillOk then
                        -- bs_vehicles damps roll/pitch on this, see cl_parts.lua (car flipping onto its side when hitting a walker)
                        TriggerEvent('bs:vehicles:roadkill')
                        -- bs:z:dmg refuses region 'vehicle'; roadkill has its own validated door.
                        TriggerServerEvent('bs:z:vehhit', id, 'kill')
                    else
                        TriggerServerEvent('bs:z:envdeath', id)
                    end
                end
            end
            ::continue::
        end
    end
end)


-- Death - announced by the server, played by everyone

local cleanShotCount = 0
local cleanShotTicket = 0

local function queueCleanShotNotice()
    cleanShotCount = cleanShotCount + 1
    cleanShotTicket = cleanShotTicket + 1
    local ticket = cleanShotTicket

    SetTimeout(350, function()
        if ticket ~= cleanShotTicket then return end
        local count = cleanShotCount
        cleanShotCount = 0
        notify('success', count > 1 and L('zed.clean_shots', { n = count }) or L('zed.clean_shot'), 1500)
    end)
end

local function handleDeath(id, info, cachedEntry)
    -- The live slot is released immediately; this cached entry owns the corpse work.
    local entry = cachedEntry or Zed.live[id]
    Crumb('zdeath', 'id=%s entry=%s', tostring(id), tostring(entry ~= nil))
    if not entry then return end

    entry.dying = true
    local ped = entry.ped

    -- A dying walker's voice fades out over Zombies.Voices.deathFade (600ms) instead of being cut
    if Zombies.Silence then
        Zombies.Silence(id, (Zombies.Voices or {}).deathFade)
    end

    if DoesEntityExist(ped) then
        Zombies.Growl(entry, 'death')
        if not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped) then
            -- already dead: no ClearPedTasks, no ragdoll on a corpse
            if not IsEntityDead(ped) then
                ClearPedTasks(ped)
                SetEntityHealth(ped, 0)
            end
            if not IsEntityDead(ped) and not IsPedRagdoll(ped) then
                Crumb('zragdoll', 'death ped=%s', tostring(ped))
                SetPedToRagdoll(ped, 2500, 2500, 0, false, false, false)
            end
        end

        registerCorpse(ped, id, info and info.loot)

        -- Corpse noise is a config decision, off by default
        local sources = Zombies.NoiseSources
        if sources and sources.corpse then
            local coords = GetEntityCoords(ped)
            TriggerEvent('bs:world:noise', {
                kind = 'body', radius = sources.corpseRadius or 14.0,
                coords = { x = coords.x, y = coords.y, z = coords.z },
            })
        end
    end

    -- The live slot was released before this queued corpse work began.

    if info and info.killer == GetPlayerServerId(PlayerId()) then
        local _, w = GetCurrentPedWeapon(PlayerPedId(), true)
        if not (Zombies.IsMeleeWeapon and Zombies.IsMeleeWeapon(w)) then
            Zombies.KillMarker()
        end
        if info.headshot then queueCleanShotNotice() end
    end
end

-- A horde can die in one network frame, so the expensive ped, ragdoll, corpse, interaction and NUI work is paced through a queue
local deathQueue = {}
local deathHead = 1
local deathTail = 0
local deathWorker = false
local queuedDeaths = {}

RegisterNetEvent('bs:z:dead', function(id, info)
    if queuedDeaths[id] then return end
    local entry = Zed.live[id]
    if not entry then return end

    entry.dying = true

    -- A dead walker keeps its body but no longer occupies an active-zombie slot.
    Zed.Despawn(id, true)

    queuedDeaths[id] = true
    deathTail = deathTail + 1
    deathQueue[deathTail] = { id = id, info = info, entry = entry }

    if deathWorker then return end
    deathWorker = true

    CreateThread(function()
        while deathHead <= deathTail do
            local item = deathQueue[deathHead]
            deathQueue[deathHead] = nil
            deathHead = deathHead + 1
            queuedDeaths[item.id] = nil

            handleDeath(item.id, item.info, item.entry)
            Wait(S.deathBatchGapMs or 35)
        end

        deathQueue = {}
        deathHead = 1
        deathTail = 0
        deathWorker = false
    end)
end)

-- Zed.Corpses must be assigned: cl_sync's IsWalkerPed export reads it to recognise kept corpses
Zed.Corpses = function() return corpses end

exports('Corpses', function() return corpses end)

-- Delete corpses on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- On stop everything goes, held or not.
    lootingPed, heldPeds = nil, {}
    local all = {}
    for ped in pairs(corpses) do all[#all + 1] = ped end
    for _, ped in ipairs(all) do releaseCorpse(ped) end

    if #all > 0 then
        print(('^3[BeyondSurvival]^7 (zombies) released %d corpse(s) on shutdown.'):format(#all))
    end
end)


-- Engine-death summary

-- One line per distinct cause every 15 seconds instead of two lines per death
CreateThread(function()
    while true do
        Wait(15000)

        local tally = Combat.deathTally
        if tally then
            local lines, total = {}, 0
            for key, count in pairs(tally) do
                lines[#lines + 1] = ('   %d x  %s'):format(count, key)
                total = total + count
            end

            if #lines > 0 then
                table.sort(lines)
                print(('^3[BeyondSurvival]^7 (zombies) %d walker ped(s) died while the server '
                    .. 'had them alive, in the last 15s. They were revived; this is the breakdown:')
                    :format(total))
                for _, line in ipairs(lines) do print('^3[BeyondSurvival]^7 ' .. line) end
                print('^3[BeyondSurvival]^7    (hash 0 + source none = script-set health, not the engine. '
                    .. 'Compare the NODE and sector counts - a one-sided split names the culprit.)')
            end

            Combat.deathTally = nil
        end
    end
end)
