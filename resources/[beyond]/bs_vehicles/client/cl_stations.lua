-- BeyondSurvival - bs_vehicles stations: the pumps do not work

Stations = {}

-- Nearest listed station to a set of coords and its distance, or nil if none is within Vehicles.StationSettings.radius
function Stations.Nearest(coords)
    if not coords then return nil end

    local best, bestDist
    for _, station in ipairs(Vehicles.Stations or {}) do
        local dist = #(coords - vector3(station.x, station.y, station.z))
        if not bestDist or dist < bestDist then
            best, bestDist = station, dist
        end
    end

    if not best then return nil end
    if bestDist > (Vehicles.StationSettings.radius or 15.0) then return nil end

    return best, bestDist
end

exports('NearestStation', function(x, y, z)
    local station, dist = Stations.Nearest(vector3(x, y, z))
    if not station then return nil end
    return { label = station.label, x = station.x, y = station.y, z = station.z, distance = dist }
end)

-- One zone per listed station, registered once.

CreateThread(function()
    if GetResourceState('bs_interactions') ~= 'started' then return end

    for i, station in ipairs(Vehicles.Stations or {}) do
        exports.bs_interactions:AddZone('bs_station_' .. i,
            vector3(station.x, station.y, station.z),
            Vehicles.StationSettings.radius or 15.0,
            {
                {
                    label    = L('station.search'),
                    labelKey = 'station.search',
                    icon     = 'fuel_pump',
                    distance = Vehicles.StationSettings.radius or 15.0,
                    event    = 'bs:vehicles:dot:station',
                    filters  = { onFoot = true },
                },
            })
    end
end)

-- Searching one

local searching = false

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

AddEventHandler('bs:vehicles:dot:station', function(payload)
    if searching then return end

    -- Find which station this is by looking up the nearest one again, since the zone payload is not entity-shaped
    local at = GetEntityCoords(PlayerPedId())
    local station, dist = Stations.Nearest(at)
    if not station then return end

    local index
    for i, s in ipairs(Vehicles.Stations) do
        if s == station then index = i break end
    end
    if not index then return end

    searching = true

    CreateThread(function()
        local done = exports.bs_interactions:RunSearch(
            L('station.checking', { name = station.label }), Vehicles.StationSettings.searchTime or 6500)

        if not done then searching = false return end

        local result = BSB.Await('vehicles:searchStation', 8000, index, at.x, at.y, at.z)
        searching = false

        if not result or not result.ok then
            return notify('warn', (result and result.error) or L('pump.nothing'), 2600)
        end

        if result.found then
            notify('success', L('station.jerry'), 2800)
        else
            notify('info', L('station.dust'), 2600)
        end
    end)
end)

exports('CloseSearch', function() searching = false end)
