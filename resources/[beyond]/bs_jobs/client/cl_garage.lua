-- bs_jobs client: mechanic garage and gunsmith panels (NUI), and the paint/props every client draws on modded cars.

local notify = JC.Notify
local G = Jobs.Garage
local uiOpen, garageVeh = false, nil

local function focus(on)
    uiOpen = on
    SetNuiFocus(on, on)
    if not on then SendNUIMessage({ action = 'close' }) end
end

local function control(ent)
    if not DoesEntityExist(ent) then return false end
    local t = GetGameTimer()
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() - t < 1500 do
        NetworkRequestControlOfEntity(ent)
        Wait(50)
    end
    return NetworkHasControlOfEntity(ent)
end

-- What this car can take: slots with real mods only, and the level fitted now.
local function enrich(veh, data)
    SetVehicleModKit(veh, 0)
    local slots = {}
    for _, s in ipairs(data.slots or {}) do
        local num = GetNumVehicleMods(veh, s.slot)
        if num and num > 0 then
            s.max = math.min(s.max, num)
            s.level = GetVehicleMod(veh, s.slot) + 1
            slots[#slots + 1] = s
        end
    end
    data.slots = slots
    local p1, p2 = GetVehicleColours(veh)
    data.colours = { p1 = p1, p2 = p2 }
    return data
end

AddEventHandler('bs:jobs:openGarage', function()
    local veh = JC.NearestVehicle(8.0)
    if not veh or not NetworkGetEntityIsNetworked(veh) then return notify('warn', L('err.no_vehicle')) end
    CreateThread(function()
        local r = BSB.Await('jobs:garage:open', 8000, NetworkGetNetworkIdFromEntity(veh))
        if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
        garageVeh = veh
        SendNUIMessage({ action = 'garage', data = enrich(veh, r) })
        focus(true)
    end)
end)

RegisterNUICallback('garage', function(d, cb)
    local veh = garageVeh
    if not veh or not DoesEntityExist(veh) or type(d) ~= 'table' then return cb({ ok = false }) end
    CreateThread(function()
        local r = BSB.Await('jobs:garage:apply', 8000, { netId = NetworkGetNetworkIdFromEntity(veh), what = d.what, id = d.id, level = d.level })
        if not r or not r.ok then return cb({ ok = false, error = (r and r.error) or L('err.failed') }) end
        if control(veh) then
            if r.what == 'repair' then
                SetVehicleFixed(veh); SetVehicleDeformationFixed(veh)
                SetVehicleEngineHealth(veh, 1000.0); SetVehicleBodyHealth(veh, 1000.0)
            elseif r.what == 'paint' then
                SetVehicleColours(veh, r.p1, r.p2)
            elseif r.what == 'mod' then
                SetVehicleModKit(veh, 0)
                if r.index < 0 then RemoveVehicleMod(veh, r.slot) else SetVehicleMod(veh, r.slot, r.index, false) end
            end
        end
        local again = BSB.Await('jobs:garage:open', 8000, NetworkGetNetworkIdFromEntity(veh))
        cb({ ok = true, saved = r.saved, data = again and again.ok and enrich(veh, again) or nil })
    end)
end)

RegisterNUICallback('bill', function(d, cb)
    local veh = garageVeh
    if not veh or not DoesEntityExist(veh) then return cb({ ok = false }) end
    CreateThread(function()
        local r = BSB.Await('jobs:garage:bill', 8000, { netId = NetworkGetNetworkIdFromEntity(veh), amount = tonumber(d and d.amount) or 0 })
        cb(r or { ok = false })
    end)
end)

RegisterNUICallback('close', function(_, cb) focus(false); garageVeh = nil; cb({ ok = true }) end)

--------------------------------------------------------------------------------
-- Gunsmith bench
--------------------------------------------------------------------------------

local function openGunsmith()
    local r = BSB.Await('jobs:gs:list', 8000)
    if not r or not r.ok then return notify('error', (r and r.error) or L('err.failed')) end
    SendNUIMessage({ action = 'gunsmith', list = r.list })
    focus(true)
end
AddEventHandler('bs:jobs:openGunsmith', function() CreateThread(openGunsmith) end)

RegisterNUICallback('gsCraft', function(d, cb)
    cb({ ok = true })
    focus(false)
    CreateThread(function()
        local f = JC.TimedCall('jobs:gs:start', 'jobs:gs:finish', L('prog.gunsmith'), JC.Anim.bench, nil, tostring(d and d.id or ''))
        if f then notify('success', L('n.crafted', { item = f.label or '', n = f.amount or 1 })) end
        Wait(300)
        openGunsmith()
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and uiOpen then SetNuiFocus(false, false) end
end)

--------------------------------------------------------------------------------
-- Paint and props on modded cars, drawn locally by every client near them.
--------------------------------------------------------------------------------

local Cos = {}        -- [plate] = { paint, props }
local Fitted = {}     -- [veh] = { sig, objs }

local function plateOf(veh) return ((GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local PROP = {}
for _, p in ipairs(G.props) do PROP[p.id] = p end

local function firstModel(list)
    for _, m in ipairs(list or {}) do
        local h = joaat(m)
        if IsModelInCdimage(h) and IsModelValid(h) then return h end
    end
end

local function removeFitted(veh)
    local f = Fitted[veh]
    if f then for _, o in ipairs(f.objs) do if DoesEntityExist(o) then DeleteObject(o) end end end
    Fitted[veh] = nil
end

local function anchor(veh, at)
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    if at == 'roof' then return vector3(0.0, 0.0, mx.z + 0.02)
    elseif at == 'front' then return vector3(0.0, mx.y + 0.05, mn.z + 0.45)
    elseif at == 'left' then return vector3(mn.x - 0.02, 0.0, (mn.z + mx.z) * 0.5)
    elseif at == 'right' then return vector3(mx.x + 0.02, 0.0, (mn.z + mx.z) * 0.5) end
    return vector3(0.0, 0.0, 0.0)
end

local function fit(veh, props)
    removeFitted(veh)
    local objs, ids = {}, {}
    for id in pairs(props or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, part in ipairs((PROP[id] or {}).parts or {}) do
            local h = firstModel(part.models)
            if h then
                RequestModel(h)
                local t = GetGameTimer()
                while not HasModelLoaded(h) and GetGameTimer() - t < 2000 do Wait(20) end
                if HasModelLoaded(h) then
                    local base = anchor(veh, part.at)
                    local o = CreateObject(h, GetEntityCoords(veh), false, false, false)
                    SetEntityCollision(o, false, false)
                    local off, rot = part.off or { 0, 0, 0 }, part.rot or { 0, 0, 0 }
                    AttachEntityToEntity(o, veh, 0, base.x + off[1], base.y + off[2], base.z + off[3], rot[1] + 0.0, rot[2] + 0.0, rot[3] + 0.0, false, false, false, false, 2, true)
                    objs[#objs + 1] = o
                    SetModelAsNoLongerNeeded(h)
                end
            end
        end
    end
    Fitted[veh] = { sig = table.concat(ids, ','), objs = objs }
end

RegisterNetEvent('bs:jobs:cosmetic', function(plate, data)
    Cos[tostring(plate)] = type(data) == 'table' and data or nil
end)

CreateThread(function()
    while GetResourceState('bs_core') ~= 'started' or not exports.bs_core:IsLoaded() do Wait(1000) end
    local r = BSB.Await('jobs:cosmetics', 8000)
    if r and r.ok and type(r.list) == 'table' then for k, v in pairs(r.list) do Cos[k] = v end end
    while true do
        Wait(1500)
        local at = GetEntityCoords(PlayerPedId())
        local seen = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(veh) - at) < 150.0 then
                local c = Cos[plateOf(veh)]
                if c then
                    seen[veh] = true
                    if c.paint and c.paint.p1 then
                        local p1, p2 = GetVehicleColours(veh)
                        if p1 ~= c.paint.p1 or p2 ~= c.paint.p2 then SetVehicleColours(veh, c.paint.p1, c.paint.p2) end
                    end
                    local ids = {}
                    for id in pairs(c.props or {}) do ids[#ids + 1] = id end
                    table.sort(ids)
                    local sig = table.concat(ids, ',')
                    if (Fitted[veh] and Fitted[veh].sig or '') ~= sig then fit(veh, c.props) end
                end
            end
        end
        for veh in pairs(Fitted) do if not seen[veh] or not DoesEntityExist(veh) then removeFitted(veh) end end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for veh in pairs(Fitted) do removeFitted(veh) end
end)
