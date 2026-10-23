-- bs_world - power grid config
-- The world is permanently dark; a generator zone is a set of real lamps drawn where they are hung

Power = {}

Power.Settings = {
    enabled          = true,
    -- Street lamps, building windows, signs - everything mains-powered.
    killStreetLights = true,
    killBuildingLights = true,
    -- Kept alive. These are not the grid.
    keepVehicleLights = true,
    keepFlashlights   = true,
    keepMuzzleFlash   = true,
    keepFires         = true,
    -- How often to re-assert the blackout (ms)
    -- The engine re-enables lights on streaming, so it runs as a loop every tick
    tick             = 1000,
    -- Fade distance (metres) into a powered zone, so its edge is not a hard line.
    edgeFade         = 40.0,

    -- Max draw distance of a lamp
    -- Beyond it the render loop sleeps, keeping the per-frame light loop cheap on the dark parts of the map
    lightDraw        = 140.0,

    -- Default lamp look, unless a zone or lamp overrides it. Warm and slightly dirty, like a work light on a stand.
    lightColour      = { 255, 186, 96 },
    lightRange       = 16.0,
    lightIntensity   = 3.2,

    -- Generator fuel burnt per hour while a zone runs (0-100 tank). 0 = generators never run dry.
    fuelDrainPerHour = 0.0,
    -- Fuel one generator service (Fuel Runner job) puts back.
    serviceRefuel    = 50.0,
}

-- Places with a running generator. lights is a list of real lamp positions (on actual poles).
-- A zone with no lights gets one lamp at its centre. /powerlight in game prints a ready-made line for where you stand.
Power.Zones = {
    -- sandy_camp removed: Sandy Shores PD is no longer a safezone.
    {
        id      = 'paleto_refuge',
        label   = 'Paleto Refuge',
        postal  = '48',
        coords  = vector3(-448.0, 6013.0, 31.72),
        radius  = 110.0,
        flicker = 0.0,
        lights  = {
            vector3(-448.0, 6013.0, 33.9),
            vector3(-436.0, 6002.0, 33.0),
            vector3(-460.0, 6024.0, 33.0),
        },
    },
    {
        id      = 'hospital_block',
        label   = 'Pillbox Generator Block',
        postal  = '218',
        coords  = vector3(297.5, -584.6, 43.26),
        radius  = 90.0,
        flicker = 0.0,
        lights  = {
            vector3(297.5, -584.6, 45.4),
            vector3(310.0, -595.0, 44.5),
            vector3(285.0, -574.0, 44.5),
        },
    },
}

-- True when a point is inside a powered zone
-- Returns the zone and how far inside it is (0..1) for the soft edge
function Power.ZoneAt(coords)
    for _, zone in ipairs(Power.Zones) do
        local dist = #(coords - zone.coords)
        if dist <= zone.radius then
            local fade = Power.Settings.edgeFade or 0.0
            local strength = 1.0
            if fade > 0 and dist > (zone.radius - fade) then
                strength = (zone.radius - dist) / fade
            end
            return zone, math.max(0.0, math.min(1.0, strength))
        end
    end
    return nil, 0.0
end

-- Every lamp within distance of a point, with colour and size already resolved
-- Done here so the per-frame render loop only draws
function Power.LightsNear(coords, distance)
    local out = {}
    local s = Power.Settings

    for _, zone in ipairs(Power.Zones) do
        -- Cheap reject on the zone before looking at its lamps.
        if #(coords - zone.coords) <= (zone.radius + distance) then
            local lamps = zone.lights
            if not lamps or #lamps == 0 then lamps = { zone.coords } end

            for _, lamp in ipairs(lamps) do
                if #(coords - lamp) <= distance then
                    local colour = zone.lightColour or s.lightColour
                    out[#out + 1] = {
                        x = lamp.x, y = lamp.y, z = lamp.z,
                        colour    = colour,
                        range     = zone.lightRange or s.lightRange or 16.0,
                        intensity = zone.lightIntensity or s.lightIntensity or 3.2,
                        zone      = zone,
                    }
                end
            end
        end
    end

    return out
end


