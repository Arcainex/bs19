-- BeyondSurvival - bs_economy ATM check. The server hears an explosion and asks this client if a cash machine was there; only the client can see it, since ATMs are map geometry.

local A = Economy.ATM or { enabled = false }

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration or 3000 })
end

--- The cash machine nearest a point, if there is one at all.
local function machineAt(x, y, z, radius)
    for _, model in ipairs(A.models or {}) do
        local hash = GetHashKey(model)
        local object = GetClosestObjectOfType(x, y, z, radius, hash, false, false, false)
        if object and object ~= 0 and DoesEntityExist(object) then
            return object
        end
    end
    return nil
end

-- Money in the air is a particle effect, not a prop, so nothing needs to be owned or cleaned up.
local function spray(coords)
    local dict = 'scr_bike_business'
    if not HasNamedPtfxAssetLoaded(dict) then RequestNamedPtfxAsset(dict) end

    local waited = 0
    while not HasNamedPtfxAssetLoaded(dict) and waited < 1500 do
        Wait(10); waited = waited + 10
    end
    if not HasNamedPtfxAssetLoaded(dict) then return end

    UseParticleFxAssetNextCall(dict)
    StartParticleFxNonLoopedAtCoord('scr_bike_bus_cash_burst',
        coords.x, coords.y, coords.z + 0.4, 0.0, 0.0, 0.0, 1.4, false, false, false)
end

RegisterNetEvent('bs:atm:blast', function(x, y, z)
    if not A.enabled then return end

    local object = machineAt(x, y, z, A.blastRadius or 4.0)
    if not object then return end

    local coords = GetEntityCoords(object)

    CreateThread(function()
        -- Report the machine's position, not the blast's, so two players blowing the same machine share one cooldown key.
        local result = BSB.Await('atm:crack', 8000, coords.x, coords.y, coords.z)

        if not result or not result.ok then
            if result and result.error then notify('warn', result.error) end
            return
        end

        spray(coords)

        -- The prop cannot be deleted (map geometry), so it is pushed over on this client while it stays loaded.
        if DoesEntityExist(object) then
            SetEntityAsMissionEntity(object, true, true)
            BreakEntityGlass(object, coords.x, coords.y, coords.z, 1.0, 0.0, 0.0, 0.0, 100.0, true)

            -- SetEntityAsMissionEntity takes a script resource slot (pool of 256). Map props are never deleted, so the slot is handed back explicitly.
            SetEntityAsNoLongerNeeded(object)
        end

        notify('success', L('eco.atm_cash', { n = result.cash }), 3600)

        if (result.scrap or 0) > 0 then
            Wait(220)
            notify('success', L('eco.scrap', { n = result.scrap }), 2600)
        end
    end)
end)
