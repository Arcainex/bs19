-- Drone battery charging: automatic in a running vehicle, or press E next to a
-- running vehicle / generator. Server adds the % and says when all drones are full.

local G = GadgetCl
local C = Gadgets.Charge

local genHashes = {}
for _, m in ipairs(C.generatorModels or {}) do genHashes[#genHashes + 1] = GetHashKey(m) end

local charging = nil      -- 'vehicle' | 'generator' | nil
local manual = false      -- started with E on foot
local pct = nil           -- last % the server reported
local fullUntil = 0       -- server said everything is full; rest a while

local function nearGenerator(c)
    for _, h in ipairs(genHashes) do
        local obj = GetClosestObjectOfType(c.x, c.y, c.z, C.generatorRange, h, false, false, false)
        if obj ~= 0 then return true end
    end
    return false
end

local function nearRunningVehicle(ped, c)
    local veh = GetClosestVehicle(c.x, c.y, c.z, C.vehicleRange, 0, 70)
    return veh ~= 0 and GetIsVehicleEngineRunning(veh)
end

-- on-foot prompt only when a drone sits in a gadget slot
local function hasDrone()
    for _, e in pairs(G.Loadout or {}) do
        if type(e) == 'table' and e.kind == 'drone' then return true end
    end
    return false
end

local function stop()
    if charging then TriggerServerEvent('bs:gadgets:chargeStop') end
    charging, manual, pct = nil, false, nil
end

RegisterNetEvent('bs:gadgets:charged', function(p, done)
    pct = tonumber(p)
    if done then
        if manual then G.Notify(L('gad.batt_full')) end
        stop()
        fullUntil = GetGameTimer() + 60000
    end
end)

CreateThread(function()
    local nextTick = 0
    while true do
        local wait = 500
        local ped = PlayerPedId()
        local now = GetGameTimer()
        if G.Busy or G.Downed() then
            if charging then stop() end
        else
            local c = GetEntityCoords(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            local src = nil
            if veh ~= 0 then
                -- in a car with the engine on: automatic
                if GetIsVehicleEngineRunning(veh) and now >= fullUntil then src = 'vehicle' end
                if charging and charging ~= 'vehicle' then stop() end
                if src and not charging then charging, manual = 'vehicle', false end
                if not src and charging then stop() end
            else
                if charging == 'vehicle' and not manual then stop() end
                local armed = hasDrone()
                local atGen = armed and nearGenerator(c)
                local atVeh = armed and not atGen and nearRunningVehicle(ped, c)
                local here = atGen and 'generator' or (atVeh and 'vehicle') or nil
                if charging and charging ~= here then stop() end
                if here then
                    wait = 0
                    if charging then
                        G.Help(L('gad.charging', { pct = pct and (math.floor(pct) .. '%') or '...' }))
                        if IsControlJustPressed(0, C.key) then stop() end
                    else
                        G.Help(L('gad.charge_hint'))
                        if IsControlJustPressed(0, C.key) then charging, manual, fullUntil = here, true, 0 end
                    end
                end
            end
            if charging and now >= nextTick then
                nextTick = now + C.tickMs
                TriggerServerEvent('bs:gadgets:charge', charging)
            end
        end
        Wait(wait)
    end
end)
