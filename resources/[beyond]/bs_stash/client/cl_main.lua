-- bs_stash - client side: dig animation, owner name labels and the shovel probe. The stash list from the server only contains your own stashes.

local S = Stash.Settings

local mine = {}          -- your own stashes, from the server
local found = nil        -- somebody else's, under your feet right now
local busy = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 3000 })
end

-- Animation candidates are checked with GetAnimDuration: a dict can load without containing the clip, and TaskPlayAnim then fails silently.

local digAnim, digAnimChecked = nil, false

local function resolveAnim()
    if digAnimChecked then return digAnim end
    digAnimChecked = true

    for _, c in ipairs(S.anim or {}) do
        if c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end

            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    digAnim = c
                    print(('^2[BeyondSurvival]^7 (stash) digging animation: %s / %s')
                        :format(c.dict, c.clip))
                    return digAnim
                end
            end
        end
    end

    print('^3[BeyondSurvival]^7 (stash) no digging animation resolved - digging will be still')
    return nil
end

--- @return boolean finished
local function dig(label)
    local ped = PlayerPedId()
    local anim = resolveAnim()
    local duration = S.digMs or 6000

    if anim then
        TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0, duration, anim.flag or 49,
            0.0, false, false, false)
    end

    exports.bs_interactions:Progress(label, duration)

    if S.noise and GetResourceState('bs_emotes') == 'started' then
        pcall(function()
            exports.bs_emotes:MakeNoise(S.noise, GetEntityCoords(ped))
        end)
    end

    local start = GetEntityCoords(ped)
    local waited, cancelled = 0, false

    while waited < duration do
        Wait(100)
        waited = waited + 100

        if #(GetEntityCoords(ped) - start) > 1.5 then cancelled = true break end
        if IsEntityDead(ped) then cancelled = true break end
        if IsControlJustPressed(0, 202) then cancelled = true break end
    end

    ClearPedTasks(ped)
    exports.bs_interactions:CancelProgress()

    return not cancelled
end

--------------------------------------------------------------------------------
-- Yours
--------------------------------------------------------------------------------

local function refresh()
    local result = BSB.Await('stash:mine', 8000)
    if result and result.ok then mine = result.stashes or {} end
end

-- Zones on your own holes, re-registered on every refresh so a filled-in stash stops offering anything.
local registered = {}

local function syncZones()
    for id in pairs(registered) do
        exports.bs_interactions:RemoveZone('stash:' .. id)
    end
    registered = {}

    for _, stash in ipairs(mine) do
        local id = 'stash:' .. stash.id
        exports.bs_interactions:AddZone(id,
            vector3(stash.x + 0.0, stash.y + 0.0, stash.z + 0.0), 2.2, {
                {
                    label = L('st.dig_up', { name = stash.label }),
                    icon  = 'dig',
                    event = 'bs:stash:open',
                    args  = { id = stash.id, label = stash.label },
                },
                {
                    label = L('st.fill'), labelKey = 'st.fill',
                    icon  = 'fill',
                    event = 'bs:stash:fill',
                    args  = { id = stash.id },
                },
            })
        registered[stash.id] = true
    end
end

-- Name over the spot: visible to the owner up to 50m. Drawn instead of a blip so you still have to remember roughly where you buried it.
CreateThread(function()
    while true do
        local wait = 500

        if #mine > 0 then
            local at = GetEntityCoords(PlayerPedId())
            local sight = S.ownerSight or 50.0

            for _, stash in ipairs(mine) do
                local d = #(at - vector3(stash.x, stash.y, stash.z))
                if d <= sight then
                    wait = 0

                    -- Fades with distance.
                    local alpha = math.floor(90 + (1.0 - (d / sight)) * 130)

                    SetTextFont(4)
                    SetTextScale(0.0, math.max(0.24, 0.42 - (d / sight) * 0.18))
                    SetTextColour(216, 210, 194, alpha)
                    SetTextOutline()
                    SetTextCentre(true)
                    SetDrawOrigin(stash.x, stash.y, stash.z + 0.35, 0)
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(stash.label)
                    EndTextCommandDisplayText(0.0, 0.0)
                    ClearDrawOrigin()
                end
            end
        end

        Wait(wait)
    end
end)

-- VIP stash marker (bs_vip 'stashSkin'): a local prop only the owner sees, within sight range.

local markers = {}   -- [stashId] = entity

local function clearMarkers()
    for id, ent in pairs(markers) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
        markers[id] = nil
    end
end

local function skinModel()
    if GetResourceState('bs_vip') ~= 'started' then return nil end
    local ok, model = pcall(function() return exports.bs_vip:StashSkinModel() end)
    return ok and type(model) == 'string' and model or nil
end

CreateThread(function()
    local lastModel = nil
    while true do
        Wait(1500)
        local model = skinModel()
        if model ~= lastModel then clearMarkers(); lastModel = model end
        if not model or #mine == 0 then
            if next(markers) then clearMarkers() end
        else
            local at = GetEntityCoords(PlayerPedId())
            local sight = S.ownerSight or 50.0
            local keep = {}
            for _, stash in ipairs(mine) do
                local pos = vector3(stash.x, stash.y, stash.z)
                if #(at - pos) <= sight then
                    keep[stash.id] = true
                    if not markers[stash.id] or not DoesEntityExist(markers[stash.id]) then
                        local hash = GetHashKey(model)
                        if IsModelInCdimage(hash) then
                            RequestModel(hash)
                            local t = GetGameTimer() + 3000
                            while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(0) end
                            if HasModelLoaded(hash) then
                                local obj = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
                                PlaceObjectOnGroundProperly(obj)
                                FreezeEntityPosition(obj, true)
                                SetEntityCollision(obj, false, false)
                                SetModelAsNoLongerNeeded(hash)
                                markers[stash.id] = obj
                            end
                        end
                    end
                end
            end
            for id, ent in pairs(markers) do
                if not keep[id] then
                    if DoesEntityExist(ent) then DeleteEntity(ent) end
                    markers[id] = nil
                end
            end
        end
    end
end)

-- bs_vip renamed a stash: pull the new names.
AddEventHandler('bs:stash:refresh', function() CreateThread(function() refresh(); syncZones() end) end)

-- Other people's stashes: only with a shovel in the bag and only the square metre under your feet. The server uses its own idea of your position and rate-limits the query.

CreateThread(function()
    while true do
        Wait(S.probeInterval or 900)

        if not S.enabled or busy then goto continue end
        if GetResourceState('bs_inventory') ~= 'started' then goto continue end

        -- Cheap local check first so the server is not asked when you carry no shovel.
        local carrying = 0
        pcall(function()
            carrying = exports.bs_inventory:CountLocal(S.tool) or 0
        end)
        if carrying < 1 then
            if found then
                exports.bs_interactions:RemoveZone('stash:found')
                found = nil
            end
            goto continue
        end

        local result = BSB.Await('stash:probe', 5000)

        if result and result.ok and result.found then
            if not found or found.id ~= result.id then
                found = { id = result.id, coords = result.coords }

                exports.bs_interactions:AddZone('stash:found',
                    vector3(result.coords.x + 0.0, result.coords.y + 0.0, result.coords.z + 0.0),
                    2.0, { {
                        -- No name and no owner shown until the stash is dug up.
                        label = L('st.disturbed'),
                        icon  = 'search',
                        event = 'bs:stash:open',
                        args  = { id = result.id, label = L('st.disturbed') },
                    } })

                notify('info', L('st.dug_recently'), 3000)
            end
        elseif found then
            exports.bs_interactions:RemoveZone('stash:found')
            found = nil
        end

        ::continue::
    end
end)

--------------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------------

RegisterNetEvent('bs:stash:open', function(payload)
    local args = payload and payload.args
    if not args or busy then return end

    CreateThread(function()
        busy = true

        if not dig(L('st.digging', { name = args.label or L('st.it') })) then
            busy = false
            return
        end

        local result = BSB.Await('stash:open', 8000, args.id)
        busy = false

        if not result or not result.ok then
            notify('warn', (result and result.error) or L('st.nothing'))
        end
        -- The server opens the panel because it knows the real capacity.
    end)
end)

RegisterNetEvent('bs:stash:fill', function(payload)
    local args = payload and payload.args
    if not args or busy then return end

    CreateThread(function()
        busy = true

        if not dig(L('st.filling')) then
            busy = false
            return
        end

        local result = BSB.Await('stash:fill', 8000, args.id)
        busy = false

        if not result or not result.ok then
            return notify('warn', (result and result.error) or L('st.wont_fill'))
        end

        notify('success', L('st.filled'))
        refresh()
        syncZones()
    end)
end)

-- Burying is a command (/bury <name>) since there is nothing in the world to target yet: it uses the spot you stand on.

RegisterCommand('bury', function(_, args)
    if busy then return end

    CreateThread(function()
        busy = true

        local label = table.concat(args or {}, ' ')
        if label == '' then label = L('st.default_label') end

        if not dig(L('st.digging_plain')) then
            busy = false
            return
        end

        local result = BSB.Await('stash:bury', 8000, label)
        busy = false

        if not result or not result.ok then
            return notify('warn', (result and result.error) or L('st.wont_take'))
        end

        notify('success', L('st.buried', { name = result.label }), 4200)
        if result.broke then notify('error', L('st.shovel_broke')) end

        refresh()
        syncZones()
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/bury', L('stash.sugg_bury'),
    { { name = 'name', help = L('stash.sugg_bury_arg') } })

RegisterCommand('mystashes', function()
    CreateThread(function()
        refresh()
        syncZones()

        if #mine == 0 then
            return notify('info', L('st.none_buried'))
        end

        local at = GetEntityCoords(PlayerPedId())
        for _, stash in ipairs(mine) do
            local d = #(at - vector3(stash.x, stash.y, stash.z))
            notify('info', L('stash.dist', { name = stash.label, n = math.floor(d) }), 4000)
            Wait(120)
        end
    end)
end, false)

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

CreateThread(function()
    Wait(4000)
    refresh()
    syncZones()
end)

AddEventHandler('bs:hook:player:spawned', function()
    CreateThread(function()
        Wait(2000)
        refresh()
        syncZones()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(registered) do exports.bs_interactions:RemoveZone('stash:' .. id) end
    if found then exports.bs_interactions:RemoveZone('stash:found') end
    clearMarkers()
end)
