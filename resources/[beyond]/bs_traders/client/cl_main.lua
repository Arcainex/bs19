-- bs_traders - client menu.

local open = false
local currentNpc = nil

-- Tracker state is declared at the top of the file: a `local` used above its declaration compiles to a global
local tracked = {}          -- active missions, as last pushed by the server
-- /missions toggle; survives mission changes. KVP 1 = hidden, so a missing key means shown.
local KVP_TRACKER = 'bs_traders_tracker_hidden'
local trackerHidden = GetResourceKvpInt(KVP_TRACKER) == 1
local pushTracker           -- assigned in the tracker section below

local function send(p) SendNUIMessage(p) end

local function say(text)
    TriggerEvent('chat:addMessage', { args = { '^5[npc]', text } })
end

function OpenNpcMenu(npcId)
    if open or not npcId then return end

    local result = BSB.Await('traders:open', 5000, npcId)
    if not result or not result.ok then
        -- Print the reason in chat. `reason` comes from traders:open in sv_traders.lua and tells apart a timeout
        say(L('trd.cant_reach', { why = result and result.reason or L('trd.timeout') }))
        return
    end

    currentNpc = npcId
    open = true
    -- The tracker suppresses itself while the menu is up (see pushTracker's `hidden` argument) - tell it the menu just opened.
    if pushTracker then pushTracker() end
    send({ action = 'open', data = result })
    SetNuiFocus(true, true)
    TriggerEvent('bs:ui:opened', 'npcs')
end

local function closeMenu()
    if not open then return end
    open = false
    currentNpc = nil
    if pushTracker then pushTracker() end
    send({ action = 'close' })
    SetNuiFocus(false, false)
    TriggerEvent('bs:ui:closed', 'npcs')
end

-- NUI callbacks

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)

RegisterNUICallback('buy', function(data, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:buy', 6000, currentNpc, data.item, data.qty)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('sell', function(data, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:sell', 6000, currentNpc, data.item, data.qty)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('missionAccept', function(data, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:missionAccept', 6000, currentNpc, data.missionId)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('missionAbandon', function(data, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:missionAbandon', 6000, currentNpc, data.missionId)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('missionTurnIn', function(data, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:missionTurnIn', 6000, currentNpc, data.missionId)
        cb(r or { ok = false, reason = 'timeout' })
        if r and r.ok then
            say(L('trd.turned_in', { xp = (r.reward and r.reward.xp) or 0, money = (r.reward and r.reward.money) or 0 }))
        end
    end)
end)

--- Refreshes the payload after any action that could have changed it
RegisterNUICallback('refresh', function(_, cb)
    if not currentNpc then cb({ ok = false }); return end
    CreateThread(function()
        local r = BSB.Await('traders:open', 5000, currentNpc)
        cb(r or { ok = false })
    end)
end)

-- Live progress toast, fired by sv_traders.lua on every kill that advances a mission - useful even with the

RegisterNetEvent('bs:traders:progress', function(missionId, progress, target)
    if open then send({ action = 'progress', missionId = missionId, progress = progress, target = target }) end

    -- Feed the on-screen tracker too, not just the menu.
    for _, m in ipairs(tracked) do
        if m.id == missionId then m.progress = progress end
    end
    pushTracker()

    if progress == target then
        say(L('trd.ready', { id = missionId, n = progress, total = target }))
    end
end)

-- Objective tracker (on-screen mission rows with kill counts). kill: the server is the authority and pushes the

pushTracker = function()
    -- Gather progress is read from the local bag at draw time. pcall'd because bs_inventory may be restarting.
    for _, m in ipairs(tracked) do
        if m.kind == 'gather' and m.item then
            local ok, n = pcall(function() return exports.bs_inventory:CountLocal(m.item) end)
            if ok and tonumber(n) then m.progress = tonumber(n) end
        end
    end

    -- The tracker hides for every full-screen menu, not just the trade menu.
    local wardrobe = WardrobeIsOpen

    send({ action = 'tracker', missions = tracked, hidden = trackerHidden or open or wardrobe })
end

--- Let cl_wardrobe.lua re-evaluate the line above when its own screen opens or closes.
RefreshTracker = function() pushTracker() end

RegisterNetEvent('bs:traders:tracker', function(list)
    tracked = type(list) == 'table' and list or {}
    pushTracker()
end)

--- bs_inventory fires this on its own client whenever the bag changes.
RegisterNetEvent('bs:inventory:state', function()
    if #tracked > 0 then pushTracker() end
end)

-- Short poll for gather missions. bs:inventory:state only fires on a server push
CreateThread(function()
    while true do
        Wait(250)

        local changed = false

        for _, m in ipairs(tracked) do
            if m.kind == 'gather' and m.item then
                local ok, n = pcall(function()
                    return exports.bs_inventory:CountLocal(m.item)
                end)
                n = ok and tonumber(n) or nil
                if n and n ~= m.progress then
                    m.progress = n
                    changed = true
                end
            end
        end

        if changed then pushTracker() end
    end
end)

--- Toggle the tracker without losing the missions behind it - some players want a clean screen
local function setTrackerHidden(value)
    trackerHidden = value and true or false
    SetResourceKvpInt(KVP_TRACKER, trackerHidden and 1 or 0)
    pushTracker()
end

RegisterCommand('missions', function()
    setTrackerHidden(not trackerHidden)
    say(trackerHidden and L('trd.tracker_hidden')
                       or L('trd.tracker_shown'))
end, false)
TriggerEvent('chat:addSuggestion', '/missions', 'Show or hide the on-screen objective tracker')

-- Used by the Settings tab in bs_inventory.
exports('TrackerShown', function() return not trackerHidden end)
exports('SetTrackerShown', function(on) setTrackerHidden(not on) end)

AddEventHandler('bs:hook:player:unloaded', function()
    tracked = {}
    pushTracker()
end)

-- Safety

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'npcs' and open then closeMenu() end
end)

AddEventHandler('bs:ui:panic', closeMenu)
AddEventHandler('bs:hook:player:unloaded', closeMenu)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

for _, action in ipairs({'weaponQuote','weaponBuy'}) do
    RegisterNUICallback(action,function(data,cb)
        if not currentNpc then cb({ok=false});return end
        CreateThread(function()
            cb(BSB.Await('traders:'..action,10000,currentNpc,data.item,data.attachments or {},data.price) or {ok=false,reason='Request timed out; check inventory before retrying'})
        end)
    end)
end
