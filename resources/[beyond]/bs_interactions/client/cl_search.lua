-- BeyondSurvival - cl_search.lua. Searching containers (bins, dumpsters, fridges, lockers, toolboxes, vending machines, car boots).
-- Every model in config_containers.lua is registered with the target registry at boot. The client plays the animation and progress bar; the server decides what comes out.

local searching = false

--------------------------------------------------------------------------------
-- The weapon in your hands while you are using them for something else
--------------------------------------------------------------------------------

-- Hide the held weapon while searching, otherwise the search clip swings the rifle around with the hand.
-- Uses SetPedCurrentWeaponVisible instead of switching to WEAPON_UNARMED: bs_weapons reads a weapon switch as a holster, which would fire spurious ammo events for every bin. This only hides the model; the weapon stays equipped with its ammo.
local function hideWeapon(ped, hidden)
    -- Last args are (visible, deselectWeapon, unk, unk). The third must stay false, otherwise the weapon is put away (holster path) instead of just hidden.
    SetPedCurrentWeaponVisible(ped, not hidden, true, false, false)
end

-- Load an anim dict and return whether it arrived, instead of blocking forever on a dict missing from this build.
local function loadDict(dict)
    if not dict then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 3000 do
        Wait(10); waited = waited + 10
    end
    return HasAnimDictLoaded(dict)
end

-- Kneel pose is two clips: amb@medic@standing@kneel@base holds the kneel, and the tendtodead idle supplies the hand motion. Play the kneel first, then the idle on top.
-- Flag 1 (full-body) instead of 49, so the player is pinned while kneeling. Cancel by movement keys, see runSearch.
local function playKneelAnim(duration)
    local cfg = Containers.Settings.kneelAnim
    if not cfg or not cfg.base then return false end

    if not loadDict(cfg.base.dict) then return false end

    local ped = PlayerPedId()

    -- -1 instead of `duration`: ClearPedTasks ends the pose, so the clip must not expire while the bar is still running.
    TaskPlayAnim(ped, cfg.base.dict, cfg.base.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)

    -- The working idle is best-effort on top of the kneel. If its dict is missing the player still kneels.
    if cfg.work and loadDict(cfg.work.dict) then
        TaskPlayAnim(ped, cfg.work.dict, cfg.work.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end

    return true
end

--- The standing rummage: reaching into a bin, a boot, a locker.
local function playSearchAnim(duration)
    local anim = Containers.Settings.anim
    if not anim or not loadDict(anim.dict) then return false end

    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, 3.0, duration, 49, 0, false, false, false)
    return true
end

-- Runs a timed search with a progress bar. `opts` is optional; old callers pass (label, duration).
-- opts.pose: nil/'search' standing rummage (bins, lockers, boots, fridges); 'kneel' on one knee (bodies, ground level), see playKneelAnim; 'none' plays nothing and leaves the caller's own animation alone (bs_medical's revive).
-- @return boolean completed
local function runSearch(label, duration, opts)
    if searching then return false end
    searching = true

    opts = opts or {}

    local ped = PlayerPedId()
    local startCoords = GetEntityCoords(ped)

    SendNUIMessage({ action = 'progress', label = label, duration = duration })

    -- Hidden before the clip starts so there is no frame of the search pose with the weapon still visible.
    hideWeapon(ped, true)

    -- A kneel that fails to load falls back to the standing rummage, not to nothing.
    local kneeling = false
    if opts.pose == 'kneel' then
        kneeling = playKneelAnim(duration)
    end
    if not kneeling and opts.pose ~= 'none' then
        playSearchAnim(duration)
    end

    local elapsed = 0
    local cancelled = false

    while elapsed < duration do
        Wait(50)
        elapsed = elapsed + 50

        if Containers.Settings.cancelOnMove then
            if kneeling then
                -- A full-body pose pins the ped, so displacement-based cancel cannot work. Watch the movement inputs instead: pressing a direction stands up and cancels, same as the standing search.
                if IsDisabledControlPressed(0, 32) or IsDisabledControlPressed(0, 33)
                    or IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 35)
                    or IsDisabledControlJustPressed(0, 22) then   -- jump
                    cancelled = true break
                end
            elseif #(GetEntityCoords(ped) - startCoords) > 1.4 then
                cancelled = true break
            end
        end
        if IsControlJustPressed(0, 202) then cancelled = true break end   -- backspace
        if IsEntityDead(ped) then cancelled = true break end
        -- The thing being searched was deleted (body despawned): stand up now instead of kneeling over nothing.
        if opts.entity and not DoesEntityExist(opts.entity) then cancelled = true break end
    end

    -- A caller that owns its animation also ends it. Clearing here would cut bs_medical's revive short.
    if opts.pose ~= 'none' then ClearPedTasks(ped) end

    -- Shown again on every exit. PlayerPedId() is re-read because death replaces the ped, and the new ped's weapon would stay hidden.
    hideWeapon(PlayerPedId(), false)

    SendNUIMessage({ action = 'progress', cancel = true })
    searching = false

    return not cancelled
end

-- On a resource restart mid-search the thread dies with the weapon still hidden. This restores it.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if searching then hideWeapon(PlayerPedId(), false) end
end)

exports('RunSearch', runSearch)

-- Standalone progress bar, no animation and no movement cancel (for machines that run on their own).
-- bs_recycler needs this here: SendNUIMessage reaches the calling resource's page, and a resource without a ui_page cannot show a bar.
exports('Progress', function(label, duration)
    SendNUIMessage({ action = 'progress', label = label, duration = duration })
    return true
end)

exports('CancelProgress', function()
    SendNUIMessage({ action = 'progress', cancel = true })
    return true
end)

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- A container is identified server-side by its rounded world position, so the same bin is the same for everyone and across restarts.
local function containerKey(coords)
    return ('%.1f:%.1f:%.1f'):format(coords.x, coords.y, coords.z)
end

-- Item names in the player's language when bs_inventory knows them.
local function itemLabel(entry)
    local ok, label = pcall(function() return exports.bs_inventory:ItemLabel(entry.item) end)
    if ok and type(label) == 'string' and label ~= '' and label ~= entry.item then return label end
    return entry.label or entry.item or L('search.item')
end

local function containerLabel(typeId, def)
    return Registry.Label({ label = def.label, labelKey = 'container.' .. typeId })
end

local function searchOption(typeId, def)
    return {
        label = def.label,
        labelKey = 'container.' .. typeId,
        icon  = def.icon,
        distance = 2.4,
        action = function(payload)
            local coords = payload.coords or GetEntityCoords(PlayerPedId())
            local key = containerKey(coords)

            -- Some sealed props require a specific weapon/tool to be actively held.
            if def.requiredWeapon then
                local held = GetSelectedPedWeapon(PlayerPedId())
                if held ~= GetHashKey(def.requiredWeapon) then
                    return TriggerEvent('bs:ui:notify', {
                        type = 'warn',
                        message = def.requiredWeaponError or 'Benötigtes Werkzeug muss in der Hand sein.',
                    })
                end
            end

            -- Ask first: no point playing a 5 second animation on an empty bin.
            local check = BSB.Await('containers:check', 6000, typeId, key)
            if not check or not check.ok then
                return TriggerEvent('bs:ui:notify', {
                    type = 'warn',
                    message = (check and check.error) or L('search.nothing_here'),
                })
            end

            if not runSearch(containerLabel(typeId, def), def.time or 4000) then return end

            local result = BSB.Await('containers:loot', 10000, typeId, key)
            if not result or not result.ok then
                return TriggerEvent('bs:ui:notify', {
                    type = 'warn',
                    message = (result and result.error) or L('search.nothing_worth'),
                })
            end

            -- Fuel is reported separately: it goes into a can, not a slot, so a plain '+12 diesel' with nothing in the bag would look like a bug.
            local fuel = result.diesel
            if fuel then
                if (fuel.stored or 0) > 0 then
                    TriggerEvent('bs:ui:notify', {
                        type = 'success',
                        message = L('search.diesel_drained', { n = fuel.stored }),
                        duration = 2600,
                    })
                else
                    TriggerEvent('bs:ui:notify', {
                        type = 'warn',
                        message = L('search.diesel_left', { reason = L('search.reason_' .. (fuel.reason or 'no_can')) }),
                        duration = 3200,
                    })
                end
                Wait(140)
            end

            local cash = tonumber(result.cash) or 0
            if cash > 0 then
                TriggerEvent('bs:ui:notify', {
                    type = 'success',
                    message = ('+$%d'):format(cash),
                    duration = 2200,
                })
                Wait(120)
            end

            if #(result.items or {}) == 0 then
                if result.inventoryFull then
                    return TriggerEvent('bs:ui:notify', { type = 'warn', message = 'Dein Inventar ist Voll.' })
                end
                if fuel or cash > 0 then return end
                return TriggerEvent('bs:ui:notify', { type = 'info', message = L('search.empty') })
            end

            -- Defensive: an entry whose `amount` is not a number throws here and aborts the loop, so later items lose their notification. Container loot resolves a numeric amount first, so this should not fire.
            for _, entry in ipairs(result.items) do
                TriggerEvent('bs:ui:notify', {
                    type = 'success',
                    message = ('+%d %s'):format(tonumber(entry.amount) or 1,
                        itemLabel(entry)),
                    itemImage = entry.item,
                    duration = 2200,
                })
                Wait(120)
            end

            if result.inventoryFull then
                TriggerEvent('bs:ui:notify', { type = 'warn', message = 'Dein Inventar ist Voll.' })
            end
        end,
    }
end

CreateThread(function()
    for typeId, def in pairs(Containers.Types) do
        if def.models then
            Registry.AddModel(def.models, { searchOption(typeId, def) })
        end
    end

    -- Car boots are matched by type, and only from behind the vehicle.
    local boot = Containers.Types.car_boot
    if boot then
        local option = searchOption('car_boot', boot)
        option.canInteract = function(entity)
            if GetEntityType(entity) ~= 2 then return false end

            -- Owned player vehicles are not searchable. A boot search is for abandoned vehicles; an owned car already has storage through the vehicle wheel.
            -- bs_vehicles publishes ownership on the entity state bag (bsOwned), like bsLocked. The server refuses the search too; this only decides what is offered.
            local state = Entity(entity).state
            if state and state.bsOwned then return false end

            if not boot.rearOnly then return true end

            -- Wrecks are searchable from any side. rearOnly suits an intact abandoned car, but a burnt-out shell has no boot lid.
            -- IsVehicleDriveable is false for burnt, wrecked and undriveable vehicles, so no model list is needed and it works on other maps.
            local okDrive, driveable = pcall(IsVehicleDriveable, entity, true)
            if okDrive and not driveable then return true end

            -- Behind the vehicle: negative Y in its local space.
            local offset = GetOffsetFromEntityGivenWorldCoords(entity, GetEntityCoords(PlayerPedId()))
            return offset.y < -0.5
        end
        Registry.AddType('vehicle', { option })
    end

    -- Wreck props matched by shape instead of name (see car_wreck.matchBySize). A model hash cannot be turned back into a name at runtime, so other maps' wrecks cannot be listed.
    -- Registered against the OBJECT type so only static props are asked; real vehicles already have the boot search.
    local wreck = Containers.Types.car_wreck
    local size  = wreck and wreck.matchBySize

    if wreck and size and size.enabled then
        local option = searchOption('car_wreck', wreck)

        -- Measured once per model, not per entity. This runs inside the aim scan, so caching by hash avoids a native call per frame per prop.
        local sized = {}

        option.canInteract = function(entity)
            if GetEntityType(entity) ~= 3 then return false end
            -- Script props (built fences, base pieces) are not map wrecks, even when their size matches
            if Registry.entities[entity] then return false end

-- Guarded: reading a model off an entity handle that was already deleted faults inside the streamer (native 9f47b058362c84b5 is GET_ENTITY_MODEL) and floods the console.
-- pcall catches it but the fault is still logged and costs frame time. Check the entity still exists right before reading, with nothing that can yield in between.
            local model = BS.Util.ModelOf(entity)
            if not model then return false end
            local cached = sized[model]

            if cached == nil then
                -- Guarded, because pcall does not make this cheap: GET_MODEL_DIMENSIONS faults inside the streamer when the archetype is not resident, which is common at the edge of scan range.
                -- Ask first, answer 'not a wreck' for now and let the next scan decide. Do not cache a refusal, or the miss becomes permanent.
                local okValid, valid = pcall(IsModelValid, model)
                if not okValid or not valid then
                    sized[model] = false
                    return false
                end

                local okLoaded, loaded = pcall(HasModelLoaded, model)
                if not okLoaded or not loaded then return false end

                local okDim, mn, mx = pcall(GetModelDimensions, model)
                if not okDim or not mn or not mx then
                    sized[model] = false
                    return false
                end

                -- Dimensions come back as two bounding box corners in model space, and which axis is length depends on the model. Sorting the three extents fixes that: longest is length, shortest is height.
                local dims = { math.abs(mx.x - mn.x), math.abs(mx.y - mn.y), math.abs(mx.z - mn.z) }
                table.sort(dims)
                local height, width, length = dims[1], dims[2], dims[3]

                cached = length >= size.minLength and length <= size.maxLength
                     and width  >= size.minWidth  and width  <= size.maxWidth
                     and height <= size.maxHeight

                sized[model] = cached
            end

            return cached
        end

        Registry.AddType('object', { option })
    end
end)

-- Notifications are not re-handled here. bs_ui already listens on 'bs:ui:notify', and forwarding it again printed every toast twice.
