-- bs_world - the grid is always down

Blackout = { powered = nil, zone = nil, strength = 0.0, hold = false }

-- Flicker timing is keyed by zone id so each zone's generator has its own clock.
local flickerByZone = {} -- [zoneId] = { until_ = 0, state = true }

-- Exception: the character screen is an interior with no daylight. bs_multichar raises this hold while its scene is up.
AddEventHandler('bs:world:blackoutHold', function(on)
    Blackout.hold = on and true or false
    Blackout.powered = nil
end)

-- The map-wide flag. lit is true only for the character screen.
local function setLights(lit)
    -- NB: the second argument keeps vehicle lights alive. Passing false there breaks them.
    SetArtificialLightsState(not lit)

    if Power.Settings.keepVehicleLights then
        SetArtificialLightsStateAffectsVehicles(false)
    end
end

-- Is this square of ground powered

-- Zones staff have cut
local cut = {}

RegisterNetEvent('bs:world:zoneState', function(zoneId, powered)
    if type(zoneId) ~= 'string' then return end
    cut[zoneId] = (powered == false) or nil
end)

CreateThread(function()
    Wait(3500)
    local result = BSB.Await('world:powerCuts', 6000)
    if result and result.ok then
        for _, id in ipairs(result.cuts or {}) do cut[id] = true end
    end
end)

-- The zone's flicker state right now
local function flickerOn(zone)
    -- Safe zones stay stable
    return not cut[zone.id]
end

-- State tick
-- Slow, and only about where the player is: which zone they are in, and telling the rest of the framework when that changes

CreateThread(function()
    if not Power.Settings.enabled then return end

    while true do
        Wait(Power.Settings.tick or 1000)

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        -- The frame thread above owns the light flag, hold included.
        if Blackout.hold then goto continue end

        -- The light flag is set by the frame thread below, not here

        local zone, strength = Power.ZoneAt(GetEntityCoords(ped))
        Blackout.zone = zone
        Blackout.strength = strength

        local powered = zone ~= nil and not cut[zone.id]

        if powered ~= Blackout.powered then
            Blackout.powered = powered
            TriggerEvent('bs:world:power', powered, zone and zone.id or nil)
        end

        ::continue::
    end
end)

-- Holding the world dark
-- The engine and other resources (weather, time, blackout) can turn artificial lights back on

CreateThread(function()
    if not Power.Settings.enabled then
        setLights(true)
        return
    end

    while true do
        Wait(0)

        -- The character screen wants light
        setLights(Blackout.hold)
    end
end)

-- The lights themselves
-- DrawLightWithRange must be called every frame

CreateThread(function()
    if not Power.Settings.enabled then return end

    local near, nearAt = {}, 0

    while true do
        local ped = PlayerPedId()

        if Blackout.hold or not DoesEntityExist(ped) then
            Wait(500)
            goto continue
        end

        -- The lamp list only needs refreshing as the player moves; drawing is still per frame.
        local nowT = GetGameTimer()
        if nowT >= nearAt then
            nearAt = nowT + 500
            near = Power.LightsNear(GetEntityCoords(ped), Power.Settings.lightDraw or 120.0)
        end

        if #near == 0 then
            -- Nothing lit in sight: sleep instead of spinning at frame rate.
            nearAt = 0
            Wait(400)
            goto continue
        end

        for _, lamp in ipairs(near) do
            if flickerOn(lamp.zone) then
                local c = lamp.colour
                DrawLightWithRange(lamp.x, lamp.y, lamp.z,
                    c[1], c[2], c[3], lamp.range, lamp.intensity)
            end
        end

        Wait(0)
        ::continue::
    end
end)

-- Re-assert on spawn and after a resource restart; the engine resets the artificial-light flags on respawn
AddEventHandler('bs:hook:player:spawned', function()
    Blackout.powered = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then setLights(true) end
end)

-- Placing a lamp: prints the config line for exactly where you stand and look
RegisterCommand('powerlight', function()
    local c = GetEntityCoords(PlayerPedId())
    local line = ('        vector3(%.1f, %.1f, %.1f),'):format(c.x, c.y, c.z + 2.2)

    print('^2[BeyondSurvival]^7 (power) lamp line for config_power.lua:')
    print(line)

    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = 'Lamp position printed to F8 - paste it into the zone\'s lights table.',
        duration = 5000,
    })
end, false)

exports('IsPowered', function() return Blackout.powered end)
exports('CurrentPowerZone', function() return Blackout.zone end)

