-- bs_building vending crate panel. Prices, stock and money all live on the server.

local open = nil   -- crate id while the panel is up
local notify = function(k, m) TriggerEvent('bs:ui:notify', { type = k, message = m, duration = 4500 }) end

local function close()
    if not open then return end
    open = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'vendClose' })
end

local function show(res)
    if not res or not res.ok then
        notify('warn', (res and res.error) or L('build.err.failed'))
        return false
    end
    open = res.id
    TriggerEvent('bs:ui:opened', 'building_vend')
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'vend', data = res })
    return true
end

AddEventHandler('bs:building:act:vend', function(payload)
    local id = payload and payload.args and payload.args.id
    if not id then return end
    CreateThread(function() show(BSB.Await('build:vend:open', 6000, id)) end)
end)

AddEventHandler('bs:building:act:vendStock', function(payload)
    local id = payload and payload.args and payload.args.id
    if not id then return end
    CreateThread(function()
        local res = BSB.Await('build:vend:stock', 6000, id)
        if not res or not res.ok then notify('warn', (res and res.error) or L('build.err.failed')) end
    end)
end)

AddEventHandler('bs:ui:opened', function(what) if what ~= 'building_vend' then close() end end)

-- Every panel action answers with the fresh crate view (or an error), so the list never goes stale
local function relay(cbName, extra)
    return function(data, cb)
        if not open then return cb({ ok = false }) end
        local id = open
        CreateThread(function()
            local res = BSB.Await(cbName, 6000, id, data and data.item, data and (data.qty or data.price))
            if res and res.ok and extra then extra(res) end
            cb(res or { ok = false })
        end)
    end
end

RegisterNUICallback('vendBuy', relay('build:vend:buy', function(res)
    if res.bought then
        PlaySoundFrontend(-1, 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET', true)
        notify('success', L('build.vend_bought', { n = res.bought.n, item = res.bought.label, cost = res.bought.cost }))
    end
end))
RegisterNUICallback('vendPrice', relay('build:vend:price', function() notify('success', L('build.vend_price_set')) end))
RegisterNUICallback('vendCollect', relay('build:vend:collect', function(res)
    notify('success', L('build.vend_collected', { amount = res.collected or 0 }))
end))
RegisterNUICallback('vendStock', function(_, cb)
    local id = open
    cb({ ok = true })
    close()
    if id then CreateThread(function()
        local res = BSB.Await('build:vend:stock', 6000, id)
        if not res or not res.ok then notify('warn', (res and res.error) or L('build.err.failed')) end
    end) end
end)
RegisterNUICallback('vendClose', function(_, cb) close(); cb({ ok = true }) end)

-- Walked away: drop the panel.
CreateThread(function()
    while true do
        Wait(1000)
        if open then
            local e = Building.EntityOf(open)
            if not e or not DoesEntityExist(e) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(e)) > 5.0 then close() end
        end
    end
end)

AddEventHandler('onResourceStop', function(name) if name == GetCurrentResourceName() and open then SetNuiFocus(false, false) end end)
