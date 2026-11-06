-- Cosmetic, server-confirmed receipts. Never compares client inventory snapshots.
local pageReady, buffered, lastEpoch, lastSequence = false, {}, nil, 0
local progress = { active = false }
local function settings()
    local c = Inventory.PickupVisuals or {}
    return { enabled = c.enabled ~= false, duration = c.duration or 2500,
        mergeWindow = c.mergeWindow or 400, maxQueue = c.maxQueue or 20,
        showReceived = c.showReceived ~= false, showRemoved = c.showRemoved == true,
        showAmount = c.showAmount ~= false }
end
local function reset()
    buffered = {}
    SendNUIMessage({ action = 'pickupReset' })
end
local function updateProgress(state)
    if type(state) ~= 'table' then return end
    progress = { active = state.active == true, bottom = state.bottom }
    SendNUIMessage({ action = 'pickupProgress', state = progress })
end
local function progressSnapshot()
    if GetResourceState('bs_interactions') ~= 'started' then updateProgress({ active = false }); return end
    local ok, state = pcall(function() return exports.bs_interactions:GetProgressState() end)
    if ok and type(state) == 'table' then updateProgress(state)
    else updateProgress({ active = true }) end -- an older progress owner cannot safely share its occupied area
end
local function deliver(packet)
    SendNUIMessage({ action = 'pickups', packet = packet, settings = settings() })
end
AddEventHandler('bs:inventory:state', function(payload)
    if source ~= 65535 or type(payload) ~= 'table' or type(payload.pickups) ~= 'table' then return end
    if GetResourceState('bs_core') ~= 'started' then return end
    local packet = payload.pickups
    local data = exports.bs_core:GetData()
    if not data or packet.character ~= data.charId or exports.bs_core:GetSessionState() ~= 'playing' then return end
    if type(packet.epoch) ~= 'string' or #packet.epoch > 64 or type(packet.sequence) ~= 'number'
        or type(packet.changes) ~= 'table' then return end
    if packet.epoch == lastEpoch and packet.sequence <= lastSequence then return end
    lastEpoch, lastSequence = packet.epoch, packet.sequence
    if not settings().enabled then reset(); return end
    if pageReady then deliver(packet)
    else
        if #buffered >= 20 then table.remove(buffered, 1) end
        buffered[#buffered + 1] = packet
    end
end)
RegisterNUICallback('pickupReady', function(_, cb)
    pageReady = true; cb({ ok = true })
    progressSnapshot()
    SendNUIMessage({ action = 'pickupProgress', state = progress })
    for _, packet in ipairs(buffered) do deliver(packet) end
    buffered = {}
end)
AddEventHandler('bs:interactions:progress', updateProgress)
AddEventHandler('bs:hook:player:unloaded', function() reset(); lastEpoch, lastSequence = nil, 0 end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'bs_interactions' or resource == GetCurrentResourceName() then progressSnapshot() end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'bs_interactions' then updateProgress({ active = false }) end
    if resource == GetCurrentResourceName() or resource == 'bs_core' then reset() end
end)
