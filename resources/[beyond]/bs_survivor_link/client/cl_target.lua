-- Only the owning player's current companion gets these ALT options.
local companion, registered, registrationKey

local function interactionsReady()
    return GetResourceState('bs_interactions') == 'started'
end

local function clear()
    if registered and interactionsReady() then
        pcall(function() exports.bs_interactions:RemoveEntity(registered) end)
    end
    registered, registrationKey = nil, nil
end

local function ownedPed()
    if not SurvivorLink.enabled or not companion or not companion.net then return nil end
    local ped = NetworkGetEntityFromNetworkId(companion.net)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) then return nil end
    local identity = Entity(ped).state.bsSurvivorLink
    if type(identity) ~= 'table' or tonumber(identity.owner) ~= GetPlayerServerId(PlayerId())
        or tonumber(identity.charId) ~= tonumber(companion.id) then return nil end
    return ped
end

local function optionsFor(status)
    local options = {}
    local function add(label, event)
        options[#options + 1] = {
            label = label, event = event, icon = 'hand', distance = 3.0,
            filters = { onFoot = true, stateTrue = 'bsSurvivorLink', playerStateFalse = 'bsCuffed' },
        }
    end
    if status == 'alive' then
        add('Give orders', 'bs:link:target:orders')
        if SurvivorLink.allowTrade then add('Propose trade', 'bs:link:target:trade') end
        add('Switch survivor', 'bs:link:target:switch')
        add(L('link.alt_gear'), 'bs:link:target:gear')
        add(L('link.alt_squad'), 'bs:link:target:squad')
    elseif status == 'downed' and not (companion.life and companion.life.flat) then
        add('Revive survivor', 'bs:link:target:revive')
        add('Give orders', 'bs:link:target:orders')
        add(L('link.alt_gear'), 'bs:link:target:gear')
    end
    return options
end

local function refresh()
    if not interactionsReady() then registered, registrationKey = nil, nil; return end
    local ped = ownedPed()
    if not ped then clear(); return end
    local status = companion.life and companion.life.status or 'alive'
    local key = table.concat({ tostring(ped), status, tostring(SurvivorLink.allowTrade),
        tostring(companion.life and companion.life.flat) }, ':')
    if key == registrationKey then return end
    clear()
    local options = optionsFor(status)
    if #options == 0 then return end
    if exports.bs_interactions:AddEntity(ped, options, { raycastOnly = true }) then
        registered, registrationKey = ped, key
    end
end

local function accepts(payload, status)
    local ped = ownedPed()
    if not ped or not payload or payload.entity ~= ped then return false end
    if not companion.life or companion.life.status ~= status then return false end
    local me = PlayerPedId()
    if IsEntityDead(me) or LocalPlayer.state.bsDowned or LocalPlayer.state.bsCuffed
        or LocalPlayer.state.bsRestrained then return false end
    return #(GetEntityCoords(me) - GetEntityCoords(ped)) <= 3.0
end

AddEventHandler('bs:link:target:orders', function(payload)
    if accepts(payload, 'alive') or accepts(payload, 'downed') then TriggerEvent('bs:link:openTab', 'commands') end
end)
AddEventHandler('bs:link:target:trade', function(payload)
    if SurvivorLink.allowTrade and accepts(payload, 'alive') then TriggerEvent('bs:link:openTab', 'trade') end
end)
AddEventHandler('bs:link:target:switch', function(payload)
    if accepts(payload, 'alive') then TriggerEvent('bs:link:action', 'switch') end
end)
AddEventHandler('bs:link:target:gear', function(payload)
    if accepts(payload, 'alive') or accepts(payload, 'downed') then TriggerEvent('bs:link:action', 'gear') end
end)
AddEventHandler('bs:link:target:squad', function(payload)
    if accepts(payload, 'alive') then TriggerEvent('bs:link:action', 'squad') end
end)
AddEventHandler('bs:link:target:revive', function(payload)
    if accepts(payload, 'downed') then TriggerEvent('bs:link:action', 'revive') end
end)

RegisterNetEvent('bs:link:state', function(data)
    companion = type(data) == 'table' and data or nil
    refresh()
end)
AddEventHandler('bs:hook:player:unloaded', function()
    companion = nil
    clear()
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'bs_interactions' then registered, registrationKey = nil, nil; refresh() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clear()
    elseif resource == 'bs_interactions' then registered, registrationKey = nil, nil end
end)
CreateThread(function()
    while true do
        Wait(companion and 750 or 2000)
        refresh()
    end
end)
