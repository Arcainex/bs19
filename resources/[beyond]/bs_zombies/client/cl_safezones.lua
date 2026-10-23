-- bs_zombies - safe zones drawn on the map. Debug tool, and it is loud.

local SafeZoneMap = { blips = {}, shown = false }

-- Map look per faction: blip colour (GTA blip colour ids) and the area tint.
local STYLE = {
    military  = 52,  -- olive
    rebels    = 1,   -- red
    civilians = 5,   -- yellow
    bikers    = 38,  -- dark blue
}
local DEFAULT_COLOUR = 2
local SPRITE = { safezone = 487, outpost = 557 }

local function clearBlips()
    for _, blip in ipairs(SafeZoneMap.blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    SafeZoneMap.blips = {}
end

-- Shaped zones are drawn as a rotated rectangle along their longest edge.
local function polyArea(poly)
    local n, best, ax, ay = #poly, 0, 1, 0
    for i = 1, n do
        local p, q = poly[i], poly[i % n + 1]
        local len = #(q - p)
        if len > best then best = len; ax, ay = (q.x - p.x) / len, (q.y - p.y) / len end
    end
    local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(poly) do
        local u, v = p.x * ax + p.y * ay, -p.x * ay + p.y * ax
        minU, maxU = math.min(minU, u), math.max(maxU, u)
        minV, maxV = math.min(minV, v), math.max(maxV, v)
    end
    local cu, cv = (minU + maxU) / 2, (minV + maxV) / 2
    return cu * ax - cv * ay, cu * ay + cv * ax, maxU - minU, maxV - minV, math.deg(math.atan(ay, ax))
end

local function drawZone(zone)
    local at = zone.coords
    if not at then return end
    local colour = STYLE[zone.faction or ''] or DEFAULT_COLOUR
    local blips = SafeZoneMap.blips
    local area
    if zone.poly then
        local cx, cy, w, h, rot = polyArea(zone.poly)
        area = AddBlipForArea(cx, cy, at.z, w, h)
        SetBlipRotation(area, math.floor(rot))
    else
        area = AddBlipForRadius(at.x, at.y, at.z, zone.radius)
    end
    SetBlipColour(area, colour)
    SetBlipAlpha(area, 90)
    blips[#blips + 1] = area

    local marker = AddBlipForCoord(at.x, at.y, at.z)
    SetBlipSprite(marker, SPRITE[zone.kind or 'safezone'] or 487)
    SetBlipColour(marker, colour)
    SetBlipScale(marker, zone.kind == 'outpost' and 0.75 or 0.9)
    SetBlipAsShortRange(marker, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(zone.label or L('zed.safezone'))
    EndTextCommandSetBlipName(marker)
    blips[#blips + 1] = marker
end

function SafeZoneMap.Show()
    clearBlips()

    for _, zone in ipairs((Zones and Zones.Safe) or {}) do
        drawZone(zone)
    end

    SafeZoneMap.shown = true
    return #(Zones and Zones.Safe or {})
end

function SafeZoneMap.Hide()
    clearBlips()
    SafeZoneMap.shown = false
end


-- On by default, /safezones turns it off. KVP 2 = off, so a missing key means on.
local KVP_SHOWN = 'bs_safezones_shown'

local function setShown(on)
    SetResourceKvpInt(KVP_SHOWN, on and 1 or 2)
    if on then return SafeZoneMap.Show() end
    SafeZoneMap.Hide()
    return 0
end

-- Waits for Zones to load, since blip natives need a started session or the map discards the blips
CreateThread(function()
    Wait(2500)
    if GetResourceKvpInt(KVP_SHOWN) ~= 2 then SafeZoneMap.Show() end
end)

-- /safezones - toggle
RegisterCommand('safezones', function()
    if SafeZoneMap.shown then
        setShown(false)
        TriggerEvent('bs:ui:notify', { type = 'info', duration = 2500,
            message = L('zed.markers_off') })
        return
    end

    local count = setShown(true)
    TriggerEvent('bs:ui:notify', { type = 'info', duration = 4000,
        message = L('zed.markers_on', { n = count }) })
end, false)

-- Used by the Settings tab in bs_inventory.
exports('SafeZoneMarkersShown', function() return SafeZoneMap.shown end)
exports('SetSafeZoneMarkersShown', function(on) setShown(on and true or false) end)

-- Re-drawn on respawn so a resource restart in between cannot leave it missing.
AddEventHandler('bs:hook:player:spawned', function()
    if SafeZoneMap.shown then SafeZoneMap.Show() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearBlips() end
end)

BSSafeZoneMap = SafeZoneMap

-- Redraw when the zones are edited in F1.
AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function()
    if SafeZoneMap.shown then SafeZoneMap.Show() end
end)

-- Player faction flags arrive from bs_faction_bases.
RegisterNetEvent('bs:factionBases:sync', function(flags)
    Zones.SetFlagZones(flags)
    if SafeZoneMap.shown then SafeZoneMap.Show() end
end)
