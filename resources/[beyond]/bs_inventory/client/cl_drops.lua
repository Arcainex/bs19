-- bs_inventory - dropped stacks you can see and pick up.
-- Props are spawned locally from a server-owned list, so a drop costs no networked entity. Each registers with the dot target system.

local drops = {}      -- [dropId] = { data, object }

local function modelFor(category)
    local models = Inventory.Settings.dropModels or {}
    return models[category] or Inventory.Settings.dropModel or 'prop_michael_backpack'
end

local function spawnDrop(data)
    if drops[data.id] and DoesEntityExist(drops[data.id].object) then return end

    -- A backpack dropped on death looks like a backpack.
    local model = data.pack and (Inventory.Settings.packDropModel or 'p_michael_backpack_s') or modelFor(data.category)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then hash = GetHashKey('prop_michael_backpack') end

    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 5000 do Wait(10); waited = waited + 10 end
    if not HasModelLoaded(hash) then return end

    local c = data.coords
    local object = CreateObject(hash, c.x + 0.0, c.y + 0.0, c.z - 0.9, false, false, false)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)

    -- Collision stays on: the interaction dot uses a shape test, which passes through entities with collision disabled. The prop is frozen so it cannot be kicked.
    SetEntityCollision(object, true, true)
    SetEntityCompletelyDisableCollision(object, false, true)
    SetModelAsNoLongerNeeded(hash)

    drops[data.id] = { data = data, object = object }

    -- Pass an event name, not a closure: a function handed to bs_interactions does not survive the export boundary and cannot be called. The drop id travels in `args`.
    if GetResourceState('bs_interactions') == 'started' then
        local option = {
            label = L('drop.pickup', { n = data.amount, item = data.item and ItemLabel(data.item) or data.label }),
            icon  = 'bag',
            distance = Inventory.Settings.pickupRange or 1.8,
            event = 'bs:inventory:dot:pickup',
            args  = { id = data.id },
        }

        -- A sphere at the drop as well as the prop, since aiming at a small bag in grass is hard.
        local options = { option }
        if data.pack then
            options[2] = {
                label = L('drop.open_pack'), icon = 'bag',
                distance = Inventory.Settings.pickupRange or 1.8,
                event = 'bs:inventory:dot:openPack', args = { id = data.id },
            }
        end

        exports.bs_interactions:AddZone('bs_drop_' .. data.id,
            vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), 1.2, options)

        exports.bs_interactions:AddEntity(object, options)
    end
end

local function removeDrop(id)
    local entry = drops[id]
    if not entry then return end

    -- Two registrations, two removals: spawnDrop adds an entity option and a zone sphere keyed 'bs_drop_'..id (the ResolveZones fallback). Both must be removed, or the zone option stays in the ALT menu after pickup.
    if GetResourceState('bs_interactions') == 'started' then
        exports.bs_interactions:RemoveZone('bs_drop_' .. id)
        if DoesEntityExist(entry.object) then
            exports.bs_interactions:RemoveEntity(entry.object)
        end
    end
    if DoesEntityExist(entry.object) then DeleteEntity(entry.object) end
    drops[id] = nil
end

RegisterNetEvent('bs:inventory:dropAdded', function(data)
    CreateThread(function() spawnDrop(data) end)
end)

RegisterNetEvent('bs:inventory:dropRemoved', function(data)
    removeDrop(data.id)
end)

RegisterNetEvent('bs:inventory:dropSync', function(list)
    CreateThread(function()
        for _, data in ipairs(list or {}) do spawnDrop(data) end
    end)
end)

-- Ask for nearby drops on spawn, and again if the resource restarts.
CreateThread(function()
    while true do
        Wait(15000)
        if exports.bs_core:IsLoaded() then
            local result = BSB.Await('inventory:nearbyDrops', 6000)
            if result and result.ok then
                local seen = {}
                for _, data in ipairs(result.drops or {}) do
                    seen[data.id] = true
                    spawnDrop(data)
                end
                -- Anything we hold that the server no longer lists is gone.
                for id in pairs(drops) do
                    if not seen[id] then removeDrop(id) end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(drops) do removeDrop(id) end
end)

-- Pick up: one handler for every drop. bs_interactions passes back the registered `args`, so the drop is identified by data, not an upvalue.

AddEventHandler('bs:inventory:dot:pickup', function(payload)
    local id = payload and payload.args and payload.args.id
    if not id then return end

    CreateThread(function()
        local result = BSB.Await('inventory:pickup', 6000, id)

        TriggerEvent('bs:ui:notify', {
            type = (result and result.ok) and 'success' or 'warn',
            message = (result and result.ok)
                and ('+%d %s'):format(result.amount, result.label)
                or ((result and result.error) or 'gone'),
        })
    end)
end)
