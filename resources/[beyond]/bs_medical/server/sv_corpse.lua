-- bs_medical - player bodies. On death the whole inventory moves into a container tied to a server-created ped copy left where they fell. The body outlives respawn and goes when looted out or after Medical.Corpse.lifetime. Nothing survives a resource restart.

Corpse = {}
local C = Medical.Corpse or {}
local bodies = {}   -- [id] = { id, cid, ent, charId, owner, name, pos, t, emptySince, rot, lastBite }

local function netOf(ent)
    local ok, net = pcall(NetworkGetNetworkIdFromEntity, ent)
    return ok and net or nil
end

local function stateOf(b)
    return { id = b.id, name = b.name, charId = b.charId, t = b.t, rot = b.rot or 0.0 }
end

local function publish(b)
    if b.ent and DoesEntityExist(b.ent) then
        Entity(b.ent).state:set('bsCorpse', stateOf(b), true)
    end
end

local function sendBlip(b, src)
    if not C.blip or not src then return end
    TriggerClientEvent('bs:medical:corpse:blip', src, b.id, b.pos)
end

local function remove(id, why)
    local b = bodies[id]
    if not b then return end
    bodies[id] = nil
    if b.ent and DoesEntityExist(b.ent) then DeleteEntity(b.ent) end
    -- Whatever is left goes with it.
    pcall(function() exports.bs_inventory:ContainerTakeAll(b.cid) end)
    TriggerClientEvent('bs:medical:corpse:gone', -1, id)
    print(('^3[BS MEDICAL]^7 body of %s removed (%s)'):format(b.name, why))
end

-- Called from the death path while the inventory is still full. Returns the body id, or nil when nothing was carried or the body could not be made.
function Corpse.FromDeath(src)
    if not C.enabled or GetResourceState('bs_inventory') ~= 'started' then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local player = exports.bs_core:GetPlayer(src)
    local id = ('%x%04x'):format(os.time(), math.random(0, 0xFFFF))
    local cid = 'corpse:' .. id
    local name = (player and player.name) or GetPlayerName(src) or 'someone'
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local model = GetEntityModel(ped)

    -- First, so the client captures its look before the wipe strips it.
    TriggerClientEvent('bs:medical:corpse:snapshot', src, id)

    local ok, moved = pcall(function()
        return exports.bs_inventory:DeathTransfer(src, cid, (C.label or 'Body of %s'):format(name))
    end)
    if not ok then
        print(('^1[BS MEDICAL]^7 body transfer failed for %s: %s'):format(src, tostring(moved)))
        return nil
    end
    if (moved or 0) == 0 then
        TriggerClientEvent('bs:medical:corpse:gone', src, id)
        return nil
    end

    local b = {
        id = id, cid = cid, charId = player and player.charId, owner = src,
        name = name, pos = vector3(pos.x, pos.y, pos.z), t = os.time(), rot = 0.0, lastBite = 0,
    }
    bodies[id] = b

    local ent = CreatePed(4, model, pos.x, pos.y, pos.z - 0.9, heading, true, true)
    local waited = 0
    while not DoesEntityExist(ent) and waited < 3000 do Wait(50) waited = waited + 50 end
    if not DoesEntityExist(ent) then
        -- Loot is in the container either way, but unreachable without a body, so warn loudly.
        print(('^1[BS MEDICAL]^7 could not spawn body for %s (container %s kept)'):format(name, cid))
        return id
    end
    b.ent = ent
    pcall(SetEntityOrphanMode, ent, 2)            -- keep it when nobody is near
    pcall(SetEntityDistanceCullingRadius, ent, 300.0)
    Entity(ent).state:set('bsProtected', true, true)
    publish(b)

    TriggerClientEvent('bs:medical:corpse:dress', src, id, netOf(ent))
    sendBlip(b, src)

    -- Freeze it once the ragdoll has settled.
    SetTimeout(8000, function()
        if bodies[id] and DoesEntityExist(ent) then FreezeEntityPosition(ent, true) end
    end)

    print(('^3[BS MEDICAL]^7 body of %s left at %.1f %.1f %.1f (%d stacks)')
        :format(name, pos.x, pos.y, pos.z, moved))
    return id
end

-- Upkeep: empty bodies go after a short grace, everything after lifetime.
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        local ids = {}
        for id in pairs(bodies) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            local b = bodies[id]
            if b then
                if now - b.t >= (C.lifetime or 3600) then
                    remove(id, 'expired')
                else
                    local ok, has = pcall(function() return exports.bs_inventory:ContainerHasItems(b.cid) end)
                    if ok and not has then
                        b.emptySince = b.emptySince or now
                        if now - b.emptySince >= (C.emptyGrace or 20) then remove(id, 'looted') end
                    else
                        b.emptySince = nil
                    end
                end
            end
        end
    end
end)

local function bodyFromNet(net)
    local ent = tonumber(net) and NetworkGetEntityFromNetworkId(tonumber(net))
    if not ent or ent == 0 then return nil end
    for _, b in pairs(bodies) do if b.ent == ent then return b end end
end

BSB.RegisterCallback('medical:corpseSearch', function(src, id)
    local b = bodies[tostring(id)]
    if not b or not b.ent or not DoesEntityExist(b.ent) then
        return { ok = false, error = Lp(src, 'med.nothing_left_on_them') }
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = Lp(src, 'med.get_closer') } end
    if #(GetEntityCoords(ped) - GetEntityCoords(b.ent)) > (C.searchDistance or 2.5) + 1.5 then
        return { ok = false, error = Lp(src, 'med.get_closer') }
    end
    if not exports.bs_inventory:OpenContainerFor(src, b.cid) then
        return { ok = false, error = Lp(src, 'med.nothing_left_on_them') }
    end
    return { ok = true }
end)

-- A walker host reports feeding on a body; the rot is server-held so every client draws the same state.
RegisterNetEvent('bs:medical:corpse:bite', function(net)
    local src = source
    local b = bodyFromNet(net)
    if not b then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(b.ent)) > 150.0 then return end
    local now = os.time()
    if now - (b.lastBite or 0) < (C.biteInterval or 10) then return end
    b.lastBite = now
    b.rot = math.min(1.0, (b.rot or 0) + (C.rotPerBite or 0.08))
    publish(b)
end)

-- The owner gets their blip back after a relog.
AddEventHandler('bs:hook:player:spawned', function(player)
    if not player or not player.source or not player.charId then return end
    for _, b in pairs(bodies) do
        if b.charId == player.charId then b.owner = player.source sendBlip(b, player.source) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(bodies) do
        if b.ent and DoesEntityExist(b.ent) then DeleteEntity(b.ent) end
    end
end)

-- Bodies do not survive a restart, so neither does what was in them.
CreateThread(function()
    Wait(2000)
    pcall(function()
        exports.oxmysql:update_async([[
            DELETE i FROM `bs_inventory_items` i
            JOIN `bs_inventories` v ON v.`id` = i.`inventory_id`
            WHERE v.`owner_type` = 'container' AND v.`owner_id` LIKE 'corpse:%'
        ]])
        exports.oxmysql:update_async(
            "DELETE FROM `bs_inventories` WHERE `owner_type` = 'container' AND `owner_id` LIKE 'corpse:%'")
    end)
end)

exports('Corpses', function()
    local out = {}
    for id, b in pairs(bodies) do out[#out + 1] = { id = id, name = b.name, pos = b.pos, t = b.t } end
    return out
end)
