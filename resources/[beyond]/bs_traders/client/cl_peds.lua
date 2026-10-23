-- bs_traders - spawns and culls NPC peds, and registers each with bs_interactions while it exists.
-- The list comes from the server (`npcs:list` BSB callback), which merges config with live debug-menu overrides, so repositioned or disabled NPCs update without a restart.
-- Spawn radius 60m, despawn 80m on purpose (hysteresis), so standing at the boundary does not flicker the ped.

local spawned = {}    -- [npcId] = { entity = handle }
local npcList = {}     -- [npcId] = { id, label, role, model, scenario, heading, coords }
local listReady = false

-- Spawn queue instead of one CreateThread per NPC: concurrent RequestModel/CreatePed calls for the same model hash caused native-side crashes (EXCEPTION_ACCESS_VIOLATION) when several NPCs came into range at once.
local spawnQueue = {}      -- array of { npcId, npc }
local queuedIds = {}        -- [npcId] = true, so the same NPC is never queued twice
local queueRunning = false

--------------------------------------------------------------------------------
-- Fetching the live list
--------------------------------------------------------------------------------

-- Map blips, one per listed trader that has `blip` set. Rebuilt on every fetch.
local blips = {}
local function clearBlips()
    for _, b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end
local function buildBlips()
    clearBlips()
    for id, npc in pairs(npcList) do
        if npc.blip and not npc.disabled then
            local b = AddBlipForCoord(npc.coords.x, npc.coords.y, npc.coords.z)
            SetBlipSprite(b, tonumber(npc.blip.sprite) or 52)
            SetBlipColour(b, tonumber(npc.blip.color) or 2)
            SetBlipScale(b, 0.8)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(npc.label or id)
            EndTextCommandSetBlipName(b)
            blips[id] = b
        end
    end
end

local function fetchList()
    local result = BSB.Await('traders:list', 8000)
    if type(result) ~= 'table' then
        print('^1[bs_traders]^7 npcs:list callback timed out or returned nothing - is bs_traders running server-side?')
        return
    end

    npcList = {}
    for _, npc in ipairs(result) do
        if npc.coords then
            npc.coords = vector3(npc.coords.x, npc.coords.y, npc.coords.z)
            npcList[npc.id] = npc
        end
    end
    listReady = true
    buildBlips()
end

CreateThread(fetchList)

--------------------------------------------------------------------------------
-- Spawn / despawn
--------------------------------------------------------------------------------

-- Registration lives in one place because it happens from two: on ped spawn and when bs_interactions restarts (see onClientResourceStart at the bottom). Both must build the same option list.
local function registerWithInteractions(npcId, npc, ped)
    local options = {}

    -- Buying, selling and contracts: one entry, worded for what they do.
    if npc.role == 'trader' or npc.role == 'quest' or npc.role == 'both' then
        options[#options + 1] = {
            label    = npc.role == 'quest' and L('trd.talk_to', { name = npc.label })
                        or L('trd.trade_with', { name = npc.label }),
            icon     = 'npc',
            distance = Traders.Settings.interactDistance,
            event    = 'bs:traders:talk',
            args     = npcId,
        }
    end

    -- Faction mission chains (bs_operations). The server decides if this NPC has any for the player.
    if (npc.role == 'quest' or npc.role == 'both') and GetResourceState('bs_operations') == 'started' then
        options[#options + 1] = {
            label    = L('trd.operations'),
            icon     = 'npc',
            distance = Traders.Settings.interactDistance,
            event    = 'bs:ops:board',
            args     = npcId,
        }
    end

    -- The wardrobe, for a dedicated tailor OR anyone flagged to do clothes.
    if npc.role == 'clothing' or npc.clothing then
        options[#options + 1] = {
            label    = L('trd.change_clothes'),
            labelKey = 'trd.change_clothes',
            icon     = 'hanger',
            distance = Traders.Settings.interactDistance,
            event    = 'bs:traders:wardrobe',
            args     = npcId,
        }
    end

    -- An npc with no recognised service still gets the trade menu option, so the ped is never non-interactive with no explanation.
    if #options == 0 then
        options[#options + 1] = {
            label    = L('trd.speak_with', { name = npc.label }),
            icon     = 'npc',
            distance = Traders.Settings.interactDistance,
            event    = 'bs:traders:talk',
            args     = npcId,
        }
    end

    print(('^5[bs_traders]^7 registering %s - role=%s clothing=%s -> %d option(s)')
        :format(tostring(npcId), tostring(npc.role), tostring(npc.clothing), #options))

    return pcall(function()
        return exports.bs_interactions:AddEntity(ped, options, { noOutline = true })
    end)
end

local function spawnOne(npcId, npc)
    if spawned[npcId] then return end

    local model = joaat(npc.model)

    -- Reject a model hash CreatePed cannot use: `npc.model` is free-typed in the debug menu (cl_debug.lua showPreview validates the same way). Prints once and skips that NPC.
    if not IsModelValid(model) or not IsModelAPed(model) then
        print(('^1[bs_traders]^7 "%s" is not a valid ped model - skipping %s')
            :format(tostring(npc.model), tostring(npcId)))
        return
    end

    RequestModel(model)

    local waited = 0
    while not HasModelLoaded(model) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    if not HasModelLoaded(model) then return end

    -- The list may have been reloaded while the model was loading (debug save, resource restart). Bail instead of spawning something stale.
    if spawned[npcId] or npcList[npcId] ~= npc then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local ped = CreatePed(4, model, npc.coords.x, npc.coords.y, npc.coords.z - 1.0,
        npc.heading or 0.0, false, true)

    if not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return
    end

    -- Everything from here to registration runs inside one pcall; on any error the half-built ped is deleted instead of being left in the world without its safety flags.
    local ok, err = pcall(function()

    -- Set bsProtected first: the sweep in bs_world/client/cl_population.lua deletes every non-player ped that has neither `bsProtected` nor `bsZombie`, which made traders vanish. bs_multichar tags its preview ped the same way.
    local pedState = Entity(ped).state
    if pedState then pedState:set('bsProtected', true, false) end

    -- Safety flags are applied before the ground snap. PlaceEntityOnGroundProperly is not available as a global in this build; an error there would leave a created ped visible but not invincible, frozen or registered with bs_interactions.
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanBeTargetted(ped, false)     -- not a combat target for anything
    SetEntityAsMissionEntity(ped, true, true)

    -- Ground-snap is guarded: not every runtime exposes this native as a global, so use rawget and skip it if missing (ped keeps its configured Z).
    local groundSnap = rawget(_G, 'PlaceEntityOnGroundProperly')
    if type(groundSnap) == 'function' then pcall(groundSnap, ped) end

    -- Scenarios are off by default (Traders.Settings.useScenarios, see config_traders.lua). They drive the ped/task code that was crashing, so they stay disabled.
    if Traders.Settings.useScenarios and npc.scenario then
        TaskStartScenarioInPlace(ped, npc.scenario, 0, true)
        Wait(0)
    end

    if DoesEntityExist(ped) then FreezeEntityPosition(ped, true) end

    SetModelAsNoLongerNeeded(model)
    spawned[npcId] = { entity = ped }

    -- Data, not closures. `event` is a client event handled below; `filters.maxDistance` mirrors the despawn radius so the prompt cannot linger if the settings drift apart.
    -- noOutline = true skips SetEntityDrawOutline for traders (alive, frozen, invincible, untargetable); the 'Trade with X' option is unaffected.
    -- The AddEntity result is captured and printed once per NPC so a failed registration is visible.
    local regOk, regResult = registerWithInteractions(npcId, npc, ped)
    if not regOk or regResult == false then
        print(('^1[bs_traders]^7 %s spawned but could not register with bs_interactions (%s) - '
            .. 'it will exist but ALT will never find it (it will be re-registered '
            .. 'automatically if bs_interactions starts later).')
            :format(tostring(npcId), tostring(not regOk and regResult or 'AddEntity returned false')))
    end

    end)   -- pcall

    if not ok then
        print(('^1[bs_traders]^7 spawn of %s failed after CreatePed (%s) - deleting the '
            .. 'half-built ped rather than leaving an unprotected one in the world.')
            :format(tostring(npcId), tostring(err)))
        spawned[npcId] = nil
        if DoesEntityExist(ped) then
            pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
            SetEntityAsMissionEntity(ped, false, true)
            DeleteEntity(ped)
        end
    end
end

--- Drains spawnQueue one NPC at a time. Never more than one of these running
--- (guarded by queueRunning) - that is the whole point of the queue.
local function runQueue()
    if queueRunning then return end
    queueRunning = true

    while #spawnQueue > 0 do
        local job = table.remove(spawnQueue, 1)
        queuedIds[job.npcId] = nil

        -- Still wanted? It may have gone out of range, been disabled, or
        -- been deleted entirely while it sat in the queue.
        if not spawned[job.npcId] and npcList[job.npcId] == job.npc and not job.npc.disabled then
            spawnOne(job.npcId, job.npc)
        end

        -- The gap that actually prevents the concurrent-CreatePed burst.
        Wait(150)
    end

    queueRunning = false
end

local function queueSpawn(npcId, npc)
    if spawned[npcId] or queuedIds[npcId] then return end
    queuedIds[npcId] = true
    spawnQueue[#spawnQueue + 1] = { npcId = npcId, npc = npc }
    CreateThread(runQueue)
end

-- `reason` is diagnostic only, printed so unexpected despawns show up in the console.
local function despawnOne(npcId, reason)
    queuedIds[npcId] = nil   -- if it was still queued (never actually spawned), drop it now

    local rec = spawned[npcId]
    if not rec then return end

    print(('^3[bs_traders]^7 despawning %s (%s)'):format(tostring(npcId), reason or 'unspecified'))

    pcall(function() exports.bs_interactions:RemoveEntity(rec.entity) end)

    if DoesEntityExist(rec.entity) then
        SetEntityAsMissionEntity(rec.entity, false, true)
        DeleteEntity(rec.entity)
    end

    spawned[npcId] = nil
end

local function despawnAll(reason)
    for npcId in pairs(spawned) do despawnOne(npcId, reason or 'despawnAll') end
end

CreateThread(function()
    while true do
        Wait(1000)

        -- Wait until the player is actually loaded, not just until the list is fetched. Before that PlayerPedId() can sit at the default spawn position, which can spawn a trader for one tick and despawn it the next.
        if listReady and exports.bs_core:IsLoaded() then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            -- Horizontal distance, not 3D (same as nearNpc() on the server). Config Z can differ from the ground-snapped Z by a few metres, which caused false despawns.
            for npcId, npc in pairs(npcList) do
                local horizontal = #(vector2(pos.x, pos.y) - vector2(npc.coords.x, npc.coords.y))
                local vertical = math.abs(pos.z - npc.coords.z)
                local inRange = horizontal <= Traders.Settings.spawnDistance and vertical <= 15.0
                local outOfRange = horizontal > Traders.Settings.despawnDistance or vertical > 20.0

                if not spawned[npcId] and not npc.disabled and inRange then
                    queueSpawn(npcId, npc)
                elseif spawned[npcId] and (npc.disabled or outOfRange) then
                    despawnOne(npcId, npc.disabled and 'disabled'
                        or ('out of range, %.1fm horizontal / %.1fm vertical'):format(horizontal, vertical))
                end
            end

            -- An id present in `spawned` but no longer in npcList at all
            -- (deleted, not merely disabled) has to be culled here too.
            for npcId in pairs(spawned) do
                if not npcList[npcId] then despawnOne(npcId, 'no longer in npcList') end
            end
        end
    end
end)

-- Broadcast by the debug menu after save/reset/create/delete so live edits show up for nearby players without a restart. Drops everything and refetches: the NPC list is small, and it keeps one code path deciding what is on screen.
RegisterNetEvent('bs:traders:reload', function()
    despawnAll('bs:traders:reload received')
    listReady = false
    fetchList()
end)

--- bs_interactions wraps every triggered option in one payload table rather
--- than passing `args` on its own - see Target.Run in cl_target.lua - so the
--- npcId set as `args` above arrives as payload.args, not as a bare argument.
RegisterNetEvent('bs:traders:talk', function(payload)
    OpenNpcMenu(payload and payload.args)   -- defined in cl_main.lua, same resource
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    despawnAll()
end)

-- bs_interactions restart: its Registry.entities table is rebuilt empty, leaving trader peds with no ALT prompt. bs_interactions is not a hard dependency of this resource, so re-register here. Re-adding an already registered entity is harmless.
AddEventHandler('onClientResourceStart', function(resource)
    -- bs_operations too: quest NPCs spawned before it started miss the Operations option
    if resource ~= 'bs_interactions' and resource ~= 'bs_operations' then return end

    local restored = 0
    for npcId, rec in pairs(spawned) do
        local npc = npcList[npcId]
        if npc and rec.entity and DoesEntityExist(rec.entity) then
            local ok, result = registerWithInteractions(npcId, npc, rec.entity)
            if ok and result ~= false then restored = restored + 1 end
        end
    end

    if restored > 0 then
        print(('^2[bs_traders]^7 bs_interactions restarted - re-registered %d trader ped(s) with it')
            :format(restored))
    end
end)
