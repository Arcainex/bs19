-- bs_recycler client: machine props, interaction zones, loop sound and smoke. The panel itself is the CRAFT tab
-- in the inventory (bs_inventory/html/js/craft.js), which calls the NUI callbacks below by resource name.

local S = Recycler.Settings
local machines = {}     -- [id] = point
local spawned = {}      -- [id] = { obj, sound, fx, at = vector3 }
local running = {}      -- [id] = bool

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg }) end

local function modelFor()
    for _, m in ipairs(S.models) do if IsModelInCdimage(m) then return m end end
end

local function stopFx(s)
    if s.sound then StopSound(s.sound); ReleaseSoundId(s.sound); s.sound = nil end
    if s.fx then StopParticleFxLooped(s.fx, false); s.fx = nil end
end

local function startFx(s)
    if s.sound or not s.at then return end
    s.sound = GetSoundId()
    PlaySoundFromCoord(s.sound, 'Drill', s.at.x, s.at.y, s.at.z + 0.8, 'DLC_HEIST_FLEECA_SOUNDSET', false, 40, false)
    RequestNamedPtfxAsset('core')
    local t = GetGameTimer() + 2000
    while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < t do Wait(10) end
    UseParticleFxAssetNextCall('core')
    s.fx = StartParticleFxLoopedAtCoord('ent_amb_smoke_foundry', s.at.x, s.at.y, s.at.z + 2.0, 0.0, 0.0, 0.0, 0.6, false, false, false, false)
end

local function despawn(id)
    local s = spawned[id]
    if not s then return end
    stopFx(s)
    exports.bs_interactions:RemoveZone('recycler:' .. id)
    if s.obj and DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
    spawned[id] = nil
end

local function spawn(m)
    local model = modelFor()
    local x, y, z = m.x + 0.0, m.y + 0.0, m.z + 0.0
    local found, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if found then z = gz end
    local s = { at = vector3(x, y, z) }
    if model then
        RequestModel(model)
        local t = GetGameTimer() + 3000
        while not HasModelLoaded(model) and GetGameTimer() < t do Wait(10) end
        s.obj = CreateObject(GetHashKey(model), x, y, z, false, false, false)
        SetEntityHeading(s.obj, (m.h or 0.0) + 0.0)
        PlaceObjectOnGroundProperly(s.obj)
        FreezeEntityPosition(s.obj, true)
        SetModelAsNoLongerNeeded(model)
    end
    exports.bs_interactions:AddZone('recycler:' .. m.id, vector3(x, y, z + 0.8), S.radius, {
        { label = L('use_recycler'), icon = 'recycle', event = 'bs:recycler:use', args = { id = m.id } },
    })
    spawned[m.id] = s
end

RegisterNetEvent('bs:recycler:points', function(list)
    for id in pairs(spawned) do despawn(id) end
    machines, running = {}, {}
    for _, m in ipairs(list or {}) do machines[m.id] = m; running[m.id] = m.running end
end)

RegisterNetEvent('bs:recycler:running', function(id, on) running[id] = on end)

-- Stream props, zones and the running noise around the player.
CreateThread(function()
    while true do
        local me = GetEntityCoords(PlayerPedId())
        for id, m in pairs(machines) do
            local d = #(me - vector3(m.x, m.y, m.z))
            if d < S.drawDistance and not spawned[id] then spawn(m)
            elseif d > S.drawDistance + 20.0 and spawned[id] then despawn(id) end
            local s = spawned[id]
            if s then
                if running[id] and d < 70.0 then startFx(s) else stopFx(s) end
            end
        end
        Wait(1500)
    end
end)

AddEventHandler('bs:recycler:use', function(payload)
    local id = payload and payload.args and payload.args.id
    if id and GetResourceState('bs_crafting') == 'started' then
        pcall(function() exports.bs_crafting:OpenContext('recycler', id) end)
    end
end)

-- NUI (craft.js machine view)
local function ctxId()
    if GetResourceState('bs_crafting') ~= 'started' then return nil end
    local ok, c = pcall(function() return exports.bs_crafting:Context() end)
    return ok and c and c.kind == 'recycler' and c.id or nil
end

RegisterNUICallback('state', function(_, cb)
    CreateThread(function()
        local id = ctxId()
        if not id then return cb({ dict = BSLocale.Dict(), data = { ok = false } }) end
        cb({ dict = BSLocale.Dict(), data = BSB.Await('recycler:state', 8000, id) })
    end)
end)

for _, action in ipairs({ 'load', 'unload', 'takeOutput', 'start', 'stop', 'fuel' }) do
    RegisterNUICallback(action, function(d, cb)
        CreateThread(function()
            local id = ctxId()
            if not id then return cb({ ok = false }) end
            cb(BSB.Await('recycler:act', 8000, id, action, d.item, d.all) or { ok = false })
        end)
    end)
end

CreateThread(function()
    Wait(2000)
    local r = BSB.Await('recycler:points', 8000)
    if r and r.ok then TriggerEvent('bs:recycler:points', r.points) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)
