-- Faction flags on the client: the flag prop, plus blip, edge ring and entering notice for your own faction's flags.
-- The server only sends safezone flags to their own members, so others never learn where they are.
local Flags = {}
local Props = {}
local Blips = {}
local Inside = {}
local Grounded = {}
local S = FactionBases.Settings

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 5000 }) end

local function remove(id)
    local p = Props[id]
    if p and DoesEntityExist(p) then
        if GetResourceState('bs_interactions') == 'started' then exports.bs_interactions:RemoveEntity(p) end
        DeleteEntity(p)
    end
    Props[id] = nil
    Grounded[id] = nil
    for _, b in ipairs(Blips[id] or {}) do RemoveBlip(b) end
    Blips[id] = nil
end

local function addBlips(flag)
    local safe = flag.kind == 'safezone'
    local area = AddBlipForRadius(flag.x, flag.y, flag.z, (flag.radius or 50.0) + 0.0)
    SetBlipColour(area, safe and 2 or 47); SetBlipAlpha(area, 90)
    local pin = AddBlipForCoord(flag.x, flag.y, flag.z)
    SetBlipSprite(pin, safe and 40 or 38); SetBlipColour(pin, safe and 2 or 47); SetBlipScale(pin, 0.85); SetBlipAsShortRange(pin, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L(safe and 'fb.blip_safezone' or 'fb.blip_outpost'))
    EndTextCommandSetBlipName(pin)
    Blips[flag.id] = { area, pin }
end

local function spawn(flag)
    remove(flag.id)
    if flag.mine then addBlips(flag) end
    local hash = GetHashKey(S.flagModel)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local untilAt = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < untilAt do Wait(0) end
    if not HasModelLoaded(hash) then return end
    local low = GetModelDimensions(hash)
    local object = CreateObjectNoOffset(hash, flag.x, flag.y, flag.z-low.z, false, false, false)
    if not object or object==0 or not DoesEntityExist(object) then SetModelAsNoLongerNeeded(hash);return end
    SetEntityAsMissionEntity(object,true,true)
    Entity(object).state:set('bsProtected',true,false)
    SetEntityCollision(object,false,false)
    SetEntityHeading(object, flag.heading or 0.0); FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(hash)
    Props[flag.id] = object
    if GetResourceState('bs_interactions') == 'started' then
        local opts = { { label = L('fb.i_status'), icon = 'flag', event = 'bs:factionBases:flagStatus', payload = { id = flag.id } } }
        if flag.mine then
            opts[#opts + 1] = { label = L('fb.i_pickup'), icon = 'hand', event = 'bs:factionBases:pickup', payload = { id = flag.id } }
        elseif flag.kind == 'outpost' then
            opts[#opts + 1] = { label = L('fb.i_reclaim'), icon = 'warning', event = 'bs:factionBases:reclaim', payload = { id = flag.id } }
        end
        exports.bs_interactions:AddEntity(object, opts)
    end
end

local lastKey
local function sync(list)
    local key = json.encode(list or {})
    if key == lastKey then return end -- the 30 s refresh is usually a no-op
    lastKey = key
    for id in pairs(Props) do remove(id) end
    for id in pairs(Blips) do remove(id) end
    Flags = list or {}
    for _, flag in ipairs(Flags) do spawn(flag) end -- server sets flag.mine
end
RegisterNetEvent('bs:factionBases:sync', function(list) CreateThread(function() sync(list) end) end)

AddEventHandler('bs:factionBases:flagStatus', function()
    CreateThread(function()
        local r = BSB.Await('factionBases:status', 6000)
        if r and r.nearby then
            notify('info', L('fb.flag_info', { kind = L('fb.kind_' .. tostring(r.nearby.kind)), r = math.floor(r.nearby.radius or 0) }))
        end
    end)
end)
AddEventHandler('bs:factionBases:reclaim', function(data)
    CreateThread(function()
        local r = BSB.Await('factionBases:reclaim', 8000, data.id)
        if r and r.error then notify('warn', r.error) elseif r and r.ok then notify('success', L('fb.reclaim_started')) end
    end)
end)
AddEventHandler('bs:factionBases:pickup', function(data)
    CreateThread(function()
        local r = BSB.Await('factionBases:pickupFlag', 8000, data.id)
        if r and r.error then notify('warn', r.error) elseif r and r.ok then notify('success', L('fb.picked_up')) end
    end)
end)

local function refresh()
    local r = BSB.Await('factionBases:status', 8000)
    if r and r.ok then sync(r.flags) end
end

-- Faction changes have no event, so ask again now and then.
CreateThread(function()
    Wait(1200)
    while true do
        refresh()
        Wait(30000)
    end
end)

-- Entering notice and edge ring, own safezone flags only.
CreateThread(function()
    while true do
        local sleep = 1000
        local me = GetEntityCoords(PlayerPedId())
        for _, flag in ipairs(Flags) do
            if flag.mine and flag.kind == 'safezone' then
                local r = (flag.radius or 50.0) + 0.0
                local d = #(vector2(me.x, me.y) - vector2(flag.x, flag.y))
                local inside = d <= r
                if inside ~= (Inside[flag.id] or false) then
                    Inside[flag.id] = inside
                    notify(inside and 'success' or 'info', L(inside and 'fb.enter_safezone' or 'fb.leave_safezone'))
                end
                if S.edgeMarker and math.abs(d - r) < 40.0 then
                    sleep = 0
                    DrawMarker(1, flag.x, flag.y, flag.z - 2.0, 0, 0, 0, 0, 0, 0, r * 2.0, r * 2.0, 4.0, 90, 200, 120, 40, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then for id in pairs(Props) do remove(id) end; for id in pairs(Blips) do remove(id) end end
end)

-- Seat the model foot once nearby map collision has streamed in.
CreateThread(function()
    while true do
        Wait(2000)
        local me=GetEntityCoords(PlayerPedId())
        for _,flag in ipairs(Flags)do
            local object=Props[flag.id]
            if object and not Grounded[flag.id] and DoesEntityExist(object) and #(me-vector3(flag.x,flag.y,flag.z))<80.0 then
                RequestCollisionAtCoord(flag.x,flag.y,flag.z)
                if HasCollisionLoadedAroundEntity(object) then
                    local found,z=GetGroundZFor_3dCoord(flag.x,flag.y,flag.z+2.0,false)
                    if found and z<=flag.z+2.0 and z>=flag.z-20.0 then
                        local low=GetModelDimensions(GetEntityModel(object))
                        SetEntityCoordsNoOffset(object,flag.x,flag.y,z-low.z,false,false,false)
                        Grounded[flag.id]=true
                    end
                end
            end
        end
    end
end)
