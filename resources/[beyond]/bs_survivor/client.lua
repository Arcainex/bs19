local opened, refreshing = false, false

-- Headshot for the photo on the record; the page shows a silhouette until it is ready.
local shot = nil

local function dropShot()
    if shot then UnregisterPedheadshot(shot); shot = nil end
end

local function takePortrait()
    dropShot()
    local handle = RegisterPedheadshotTransparent(PlayerPedId())
    if not handle or handle < 0 then return end
    shot = handle
    local untilAt = GetGameTimer() + 3000
    while opened and shot == handle and not IsPedheadshotReady(handle) and GetGameTimer() < untilAt do Wait(50) end
    if not opened or shot ~= handle then return end
    if not IsPedheadshotValid(handle) or not IsPedheadshotReady(handle) then dropShot(); return end
    local txd = GetPedheadshotTxdString(handle)
    if type(txd) == 'string' and txd ~= '' then
        SendNUIMessage({ action = 'portrait', url = ('https://nui-img/%s/%s'):format(txd, txd) })
    end
end

local function close()
    if not opened then return end
    opened = false
    dropShot()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function vitals()
    local ped = PlayerPedId()
    local needs = exports.bs_core:GetNeeds() or {}
    local effects = {}
    if GetResourceState('bs_skills') == 'started' then
        local ok, result = pcall(function() return exports.bs_skills:GetEffects() end)
        if ok then effects = result or {} end
    end
    local downed = false
    if GetResourceState('bs_medical') == 'started' then
        local ok, value = pcall(function() return exports.bs_medical:IsDowned() end)
        downed = ok and value == true
    end
    local max = GetEntityMaxHealth(ped)
    return { health = math.max(0, math.min(100, (GetEntityHealth(ped) - 100) / math.max(1, max - 100) * 100)),
        armour = GetPedArmour(ped), hunger = needs.hunger, thirst = needs.thirst,
        infection = needs.infection, stamina = needs.stamina, effects = effects,
        downed = downed, dead = IsEntityDead(ped) }
end

local function refresh()
    if refreshing then return end
    refreshing = true
    local result = BSB.Await('survivor:snapshot', 7000)
    refreshing = false
    if not opened then return end
    if result and result.ok then
        result.action = 'snapshot'
        result.vitals = vitals()
        SendNUIMessage(result)
    else SendNUIMessage({ action = 'error', message = L('sv.unavailable') }) end
end

local function open()
    if opened or not exports.bs_core:IsLoaded() then return end
    TriggerEvent('bs:ui:requestClose', 'inventory')
    TriggerEvent('bs:ui:opened', 'survivor')
    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    CreateThread(refresh)
    CreateThread(takePortrait)
end

exports('Open', open)
exports('Close', close)
RegisterNetEvent('bs:survivor:open', open)
RegisterCommand('survivor', open, false)
RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) CreateThread(refresh); cb({ ok = true }) end)
AddEventHandler('bs:ui:requestClose', function(who) if opened and who == 'survivor' then close() end end)
AddEventHandler('bs:ui:opened', function(who) if opened and who ~= 'survivor' then close() end end)
AddEventHandler('bs:hook:player:unloaded', close)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then if opened then close() else dropShot() end end end)

CreateThread(function()
    local ticks = 0
    while true do
        Wait(opened and 500 or 1000)
        if opened then
            SendNUIMessage({ action = 'vitals', vitals = vitals() })
            ticks = ticks + 1
            if ticks >= 30 then ticks = 0; CreateThread(refresh) end
        else ticks = 0 end
    end
end)

RegisterNUICallback('survivorLink',function(_,cb)close();TriggerEvent('bs:link:open');cb({ok=true})end)
