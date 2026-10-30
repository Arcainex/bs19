-- bs_atlas - client half of the Node Atlas

local open          = false
local observer      = nil    -- { x, y, radius } while one is registered, else nil
local observerEpoch = 0

local function send(payload) SendNUIMessage(payload) end

-- Notification convention: an event
local function notify(message)
    TriggerEvent('bs:ui:notify', { type = 'error', message = message, duration = 4000 })
    print(('^3[BS ATLAS]^7 %s'):format(message))
end

-- Callback whitelist: exactly the six names sv_sim_atlas.lua registers

local callable = {
    ['zombies:atlas:snapshot']   = true,
    ['zombies:atlas:inspect']    = true,
    ['zombies:atlas:edit']       = true,
    ['zombies:atlas:repopulate'] = true,
    ['zombies:atlas:observe']    = true,
    ['zombies:atlas:config']     = true,
    -- Point survey (in game only; the server refuses the web door).
    ['zombies:atlas:survey']     = true,
    -- World cars from bs_vehicles (staff-gated server side).
    ['bs_atlas:cars']            = true,
}

-- One call, two distinguishable failures
local function callAtlas(name, args)
    if not callable[name] then
        return { ok = false, error = L('atlas.lua.local') }
    end

    if name ~= 'bs_atlas:cars' and GetResourceState('bs_zombies') ~= 'started' then
        return { ok = false, error = L('atlas.lua.nozombies') }
    end

    local res = BSB.Await(name, AtlasUI.callTimeoutMs or 8000, args or {})
    if type(res) ~= 'table' then
        return { ok = false, error = L('atlas.no_answer'), timedOut = true }
    end
    return res
end

-- Observer lifetime

-- Clear the held observer, if any. Safe when there is none.
local function clearObserver()
    if not observer then return end
    local at = observer
    observer = nil
    observerEpoch = observerEpoch + 1
    -- Threaded: BSB.Await yields, and this is called from close paths that must not block (including resource stop)
    CreateThread(function()
        callAtlas('zombies:atlas:observe', { x = at.x, y = at.y, radius = at.radius, on = false })
    end)
end

-- Refresh thread, one per registration, ended by the epoch check
local function startObserverRefresh(epoch)
    CreateThread(function()
        local period = (AtlasUI.observerRefreshSeconds or 100) * 1000
        while true do
            Wait(period)
            if observerEpoch ~= epoch or not open or not observer then return end

            local res = callAtlas('zombies:atlas:observe', {
                x = observer.x, y = observer.y, radius = observer.radius, on = true,
            })

            -- Report the refresh either way so a silent failure does not look like the simulation going quiet
            send({ action = 'observerState', ok = res.ok == true, res = res,
                   observer = observer })

            -- A failed refresh does not drop the point; the next one lands well inside the 300s TTL
        end
    end)
end

-- Open / close

-- Place names for the map, flattened from ZAtlas.points
local function placeLabels()
    local out = {}
    if type(ZAtlas) ~= 'table' or type(ZAtlas.points) ~= 'table' then return out end
    for i = 1, #ZAtlas.points do
        local p = ZAtlas.points[i]
        out[i] = { id = p.id, x = p.x, y = p.y, d = p.d, t = p.t }
    end
    return out
end

local function worldBounds()
    if type(ZAtlas) == 'table' and type(ZAtlas.bounds) == 'table' then
        return ZAtlas.bounds
    end
    -- bs_zombies missing: the panel still opens and says why nothing answers, with no place names and a guessed world box
    return { minX = -4000.0, maxX = 5000.0, minY = -4000.0, maxY = 8000.0 }
end

local closeAtlas    -- forward declaration: openAtlas's refusal path calls it
                    -- Lua 5.4: a local referenced above its declaration is a nil global, not a forward reference.

local function openAtlas()
    if open then return end

    -- Courtesy staff check, not the security
    if GetResourceState('bs_admin') ~= 'started' then
        if AtlasUI.requireAdminResource ~= false then
            notify(L('atlas.lua.noadmin'))
            return
        end
    else
        local who = BSB.Await('admin:whoami', 8000)
        if not (who and who.admin) then
            notify(L('atlas.lua.staffonly'))
            return
        end
    end

    -- Real map image: nodes/html/img/map.png, loaded as nui://nodes/html/img/map.png
    local map
    if GetResourceState('nodes') ~= 'started' then
        map = { error = L('atlas.lua.nonodes') }
    else
        local info = BSB.Await('bs_atlas:mapinfo', AtlasUI.callTimeoutMs or 8000)
        if type(info) ~= 'table' then
            map = { url = 'nui://nodes/html/img/map.png', calib = nil,
                    note = L('atlas.lua.mapnoans') }
        elseif not info.ok then
            map = { url = 'nui://nodes/html/img/map.png', calib = nil,
                    note = '(' .. tostring(info.error) .. ')' }
        else
            map = { url = info.url or 'nui://nodes/html/img/map.png', calib = info.calib, note = info.note }
        end
    end

    open = true
    TriggerEvent('bs:ui:opened', 'atlas')

    local me = GetEntityCoords(PlayerPedId())

    send({
        action = 'open',
        world  = worldBounds(),
        map    = map,
        points = placeLabels(),
        me     = { x = me.x, y = me.y, h = GetEntityHeading(PlayerPedId()) },
        cfg    = {
            pollMs                 = AtlasUI.pollMs or 500,
            pollMsMin              = AtlasUI.pollMsMin or 150,
            pollMsMax              = AtlasUI.pollMsMax or 5000,
            staleAfterPolls        = AtlasUI.staleAfterPolls or 2,
            openSpanMetres         = AtlasUI.openSpanMetres or 3000.0,
            minSpanMetres          = AtlasUI.minSpanMetres or 120.0,
            maxSpanMetres          = AtlasUI.maxSpanMetres or 16000.0,
            fetchMargin            = AtlasUI.fetchMargin or 0.15,
            observerRadius         = AtlasUI.observerRadius or 300,
            observerRadiusMin      = AtlasUI.observerRadiusMin or 50,
            observerRadiusMax      = AtlasUI.observerRadiusMax or 1200,
            observerRefreshSeconds = AtlasUI.observerRefreshSeconds or 100,
        },
    })

    SetNuiFocus(true, true)
end

-- Assigns the forward-declared local; local function closeAtlas would create a second local and leave the first nil
closeAtlas = function()
    if not open then return end
    open = false
    clearObserver()          -- before the page goes away, while we still can
    send({ action = 'close' })
    SetNuiFocus(false, false)
    TriggerEvent('bs:ui:closed', 'atlas')
end

-- Toggle command, no key mapping (see config_atlas_ui.lua for the double-fire precedent).

RegisterCommand(AtlasUI.openCommand or 'atlas', function()
    if open then
        closeAtlas()
    else
        CreateThread(openAtlas)   -- openAtlas awaits, so it needs its own thread
    end
end, false)

-- Hook used by bs_admin's DEBUG pane (see MANIFEST.txt)
RegisterNetEvent('bs:atlas:open')   -- also reachable from the server if wanted
AddEventHandler('bs:atlas:open', function()
    if not open then CreateThread(openAtlas) end
end)

-- NUI bridge

RegisterNUICallback('close', function(_, cb)
    closeAtlas()
    cb({ ok = true })
end)

-- The one data path: { name = <one of the six>, args = {...} }
RegisterNUICallback('call', function(data, cb)
    CreateThread(function()
        cb(callAtlas(data and data.name, data and data.args))
    end)
end)

-- Observer: register / move / clear from the panel
RegisterNUICallback('observer', function(data, cb)
    CreateThread(function()
        if not data or data.on == false then
            clearObserver()
            return cb({ ok = true, cleared = true })
        end

        local x = tonumber(data.x)
        local y = tonumber(data.y)
        local r = tonumber(data.radius) or (AtlasUI.observerRadius or 300)
        if not x or not y then return cb({ ok = false, error = L('atlas.lua.xy') }) end

        local res = callAtlas('zombies:atlas:observe', { x = x, y = y, radius = r, on = true })
        if not res.ok then
            -- Do not keep a local observer the server never accepted, or the refresh thread keeps re-asking for it
            return cb(res)
        end

        observer = { x = res.x or x, y = res.y or y, radius = res.radius or r }
        observerEpoch = observerEpoch + 1
        startObserverRefresh(observerEpoch)

        res.observer = observer
        cb(res)
    end)
end)

-- Sets the in-game waypoint from the map
RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)

-- Teleport from the map
RegisterNUICallback('teleport', function(data, cb)
    CreateThread(function()
        local x, y = tonumber(data and data.x), tonumber(data and data.y)
        if not x or not y then return cb({ ok = false, error = L('atlas.lua.xy') }) end

        local res = BSB.Await('bs_atlas:teleport', AtlasUI.callTimeoutMs or 8000, { x = x, y = y })
        if type(res) ~= 'table' then return cb({ ok = false, error = L('atlas.no_answer') }) end
        if not res.ok then return cb(res) end

        -- Shared helper: collision, ground probes, vehicle aware
        local tpOk, finalZ = exports.bs_core:SafeTeleport(x, y, nil)
        res.z = finalZ and (finalZ - 1.0) or nil
        if not tpOk then res.ok = false; res.error = 'No ground found there, held safely in the air' end
        res.z = gz
        cb(res)
    end)
end)

-- Player position push (not polled by the page), 4Hz

CreateThread(function()
    while true do
        if open then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            send({ action = 'me', x = c.x, y = c.y, h = GetEntityHeading(ped) })
            Wait(250)
        else
            Wait(500)
        end
    end
end)

-- Teardown: on resource stop, release NUI focus and clear the observer

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if not open then return end
    open = false
    clearObserver()
    SetNuiFocus(false, false)
end)

-- Another UI took over (bs_admin, inventory, cutscene); honour the broadcast so two full-screen pages do not both hold focus
AddEventHandler('bs:ui:opened', function(which)
    if which ~= 'atlas' and open then closeAtlas() end
end)
