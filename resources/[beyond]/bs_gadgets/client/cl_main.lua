-- Gadget keys, loadout mirror, HUD bridge and the small shared helpers.

GadgetCl = GadgetCl or {}
local G = GadgetCl

G.Loadout = {}
G.Busy = false          -- placing or flying: keys ignored
G.Stops = {}            -- kind -> function(reason) that tears that gadget down locally
G.Spawned = {}          -- every entity we made, for resource stop
G.Blips = {}

function G.Notify(msg, kind)
    TriggerEvent('bs:ui:notify', { type = kind or 'info', message = msg, duration = 2500 })
end

-- Gadget name in the player's language, config label as fallback.
function G.Name(t)
    if not t then return '' end
    local key = 'gadget.' .. tostring(t.kind)
    local text = L(key)
    return text ~= key and text or (t.label or tostring(t.kind))
end

function G.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function G.LoadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

function G.LoadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

function G.LoadFx(asset)
    RequestNamedPtfxAsset(asset)
    local t = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < t do Wait(0) end
    return HasNamedPtfxAssetLoaded(asset)
end

-- Networked prop, tracked for cleanup. Returns entity, netId.
function G.SpawnNet(model, pos, heading)
    local hash = G.LoadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, pos.x, pos.y, pos.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil end
    SetEntityHeading(obj, heading or 0.0)
    local netId = NetworkGetNetworkIdFromEntity(obj)
    SetNetworkIdCanMigrate(netId, false)
    G.Spawned[obj] = true
    return obj, netId
end

function G.Delete(obj)
    if obj and obj ~= 0 and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
    if obj then G.Spawned[obj] = nil end
end

function G.IsZombie(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or IsEntityDead(ped) then return false end
    if GetResourceState('bs_zombies') ~= 'started' then return false end
    local ok, yes = pcall(function() return exports.bs_zombies:IsWalkerPed(ped) end)
    return ok and yes == true
end

function G.Downed()
    local ped = PlayerPedId()
    return IsEntityDead(ped) or LocalPlayer.state.bsDowned == true
end

function G.Nui(msg) SendNUIMessage(msg) end

-- Clear line from a to b, ignoring `ignore`.
function G.Los(a, b, ignore)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 1 + 16, ignore or 0, 7)
    local _, hit = GetShapeTestResult(ray)
    return hit == 0 or hit == false
end

-------------------------------------------------------------------- keys

local function keyLabels()
    local out = {}
    for i = 1, Gadgets.Slots do
        local hash = joaat(Gadgets.Command:format(i)) | 0x80000000
        local raw = GetControlInstructionalButton(0, hash, true) or ''
        local label = raw:gsub('^t_', ''):gsub('^b_%d+', '')
        if label == '' then label = Gadgets.DefaultKeys[i] or tostring(i) end
        out[i] = label:upper()
    end
    return out
end
exports('KeyLabels', keyLabels)

RegisterNetEvent('bs:gadgets:loadout', function(lo)
    G.Loadout = type(lo) == 'table' and lo or {}
    TriggerEvent('bs:gadgets:loadoutChanged', G.Loadout, keyLabels())
end)
exports('GetLoadout', function() return G.Loadout end)

for i = 1, Gadgets.Slots do
    local cmd = Gadgets.Command:format(i)
    RegisterCommand(cmd, function()
        if LocalPlayer.state.bsDrone then return end -- flying the drone
        if IsNuiFocused() or IsPauseMenuActive() then return end
        -- same key puts the shield away
        if G.ShieldToggle and G.ShieldToggle(i) then return end
        if G.Busy then return end
        if G.Downed() or IsPedInAnyVehicle(PlayerPedId(), false) then return end
        -- no local loadout gate: the mirror can be stale, the server answers
        TriggerServerEvent('bs:gadgets:use', i)
    end, false)
    RegisterKeyMapping(cmd, L('gad.keymap', { n = i }), 'keyboard', Gadgets.DefaultKeys[i] or tostring(i))
end

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('bs:gadgets:request')
end)

--------------------------------------------------------------- dispatch

RegisterNetEvent('bs:gadgets:begin', function(item, t, token)
    if type(t) ~= 'table' or G.Busy then TriggerServerEvent('bs:gadgets:cancel'); return end
    if t.kind == 'shield' then
        TriggerServerEvent('bs:gadgets:deploy', token, nil, GetEntityHeading(PlayerPedId()))
    elseif t.kind == 'drone' then
        -- launches from your hands, no placement
        local c = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('bs:gadgets:deploy', token, { x = c.x, y = c.y, z = c.z }, GetEntityHeading(PlayerPedId()))
    else
        G.Place(t, token)
    end
end)

RegisterNetEvent('bs:gadgets:deployed', function(item, t, pos, heading, extra)
    if type(t) ~= 'table' then return end
    if t.kind == 'drone' then G.DroneStart(t, extra)
    elseif t.kind == 'turret' then G.TurretStart(t, pos, heading)
    elseif t.kind == 'medic' then G.BeaconStart(t, pos, heading)
    elseif t.kind == 'decoy' then G.DecoyStart(t, pos, heading)
    elseif t.kind == 'shield' then G.ShieldStart(t, item, extra)
    end
end)

local stopMsg = {
    time = 'g.stop_time', ammo = 'g.stop_ammo', down = 'g.stop_down',
    destroyed = 'g.stop_destroyed', broke = 'g.stop_broke', stow = 'g.stop_stow', twohand = 'g.stop_twohand', battery = 'g.stop_battery', signal = 'g.stop_signal',
}

RegisterNetEvent('bs:gadgets:stop', function(kind, reason)
    local f = G.Stops[kind]
    G.Stops[kind] = nil
    if f then pcall(f, reason) end
    local fmt = stopMsg[reason]
    local t
    for _, v in pairs(Gadgets.Types) do if v.kind == kind then t = v end end
    if fmt and t then G.Notify(L(fmt, { name = t.label })) end
end)

RegisterNetEvent('bs:gadgets:active', function(list)
    G.Nui({ action = 'active', list = type(list) == 'table' and list or {} })
end)

-------------------------------------------------------------------- heal

RegisterNetEvent('bs:gadgets:heal', function(amount)
    local ped = PlayerPedId()
    if G.Downed() then return end
    local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
    if hp < max then SetEntityHealth(ped, math.min(max, hp + (tonumber(amount) or 0))) end
end)

-------------------------------------------------------------------- pings

RegisterNetEvent('bs:gadgets:pinged', function(pos, name, secs)
    if type(pos) ~= 'vector3' and type(pos) ~= 'table' then return end
    local b = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(b, 162); SetBlipColour(b, 5); SetBlipScale(b, 0.9)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L('gad.ping', { name = name or '?' })); EndTextCommandSetBlipName(b)
    G.Blips[b] = true
    PlaySoundFrontend(-1, Gadgets.Fx.pingSound, Gadgets.Fx.pingSet, true)
    G.Notify(L('gad.marked', { name = name or L('gad.squad') }))
    SetTimeout((tonumber(secs) or 30) * 1000, function()
        if DoesBlipExist(b) then RemoveBlip(b) end
        G.Blips[b] = nil
    end)
end)

------------------------------------------------------------------ cleanup

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for kind, f in pairs(G.Stops) do pcall(f, 'stop') end
    G.Stops = {}
    for obj in pairs(G.Spawned) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    for b in pairs(G.Blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
end)
