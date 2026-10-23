-- bs_zombies - spawn zones and difficulty
-- Zones are circles and may overlap; the director picks the highest difficulty containing the player

Zones = {}

-- Generic safe zones (no faction). Faction safezones and outposts are below.
Zones.Safe = {
    { id = 'paleto', label = 'Paleto Refuge', coords = vector3(-448.0, 6013.0, 31.72), radius = 100.0 },
}

-- Vanilla faction safezones and outposts
-- Added to Zones.Safe when enabled, so zombies never spawn inside them (they can still follow a player in)
Zones.FactionSafe = {
    { id = 'military',        faction = 'military',  kind = 'safezone', label = 'Military Safezone', enabled = true, coords = vector3(1744.0, 3265.0, 41.25), radius = 75.0 },
    { id = 'rebels',          faction = 'rebels',    kind = 'safezone', label = 'Rebels Safezone',   enabled = true, coords = vector3(1015.0, -318.0, 67.0),  radius = 0.0,
      poly = { vector2(871.0, -310.0), vector2(1047.0, -359.0), vector2(1065.0, -331.0), vector2(988.0, -284.0) } },
    { id = 'rebels_outpost',  faction = 'rebels',    kind = 'outpost',  label = 'Rebels Outpost',    enabled = true, coords = vector3(-1107.0, 4920.0, 217.0), radius = 50.0 },
    { id = 'civilians',       faction = 'civilians', kind = 'safezone', label = 'Civilians Safezone',enabled = true, coords = vector3(-266.0, -2049.0, 27.0), radius = 75.0 },
    { id = 'bikers',          faction = 'bikers',    kind = 'safezone', label = 'Bikers Safezone',   enabled = true, coords = vector3(957.24, -206.17, 72.05), radius = 75.0 },
    { id = 'bikers_outpost',  faction = 'bikers',    kind = 'outpost',  label = 'Bikers Outpost',    enabled = true, coords = vector3(1993.0, 3060.0, 47.0),   radius = 50.0 },
}

-- Point in polygon (vector2 list). Used for shaped zones.
function Zones.InPoly(poly, x, y)
    local inside, j = false, #poly
    for i = 1, #poly do
        local a, b = poly[i], poly[j]
        if ((a.y > y) ~= (b.y > y)) and (x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) then inside = not inside end
        j = i
    end
    return inside
end

-- Is x,y inside the zone (plus optional padding in metres).
function Zones.Contains(zone, x, y, pad)
    pad = pad or 0.0
    if zone.poly then
        if Zones.InPoly(zone.poly, x, y) then return true end
        if pad <= 0 then return false end
        local n = #zone.poly
        for i = 1, n do
            local a, b = zone.poly[i], zone.poly[i % n + 1]
            local dx, dy = b.x - a.x, b.y - a.y
            local t = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
            local px, py = a.x + dx * t - x, a.y + dy * t - y
            if px * px + py * py <= pad * pad then return true end
        end
        return false
    end
    local dx, dy = zone.coords.x - x, zone.coords.y - y
    local r = zone.radius + pad
    return dx * dx + dy * dy <= r * r
end

-- Rebuilds the faction entries inside Zones.Safe from the config plus F1 overrides (Global.FactionSafe.<id>.enabled / x / y / z / radius)
function Zones.SyncFactionSafe()
    local get = BSConfigGet or function(_, d) return d end
    for i = #Zones.Safe, 1, -1 do
        if Zones.Safe[i].faction then table.remove(Zones.Safe, i) end
    end
    for _, f in ipairs(Zones.FactionSafe) do
        local key = 'Global.FactionSafe.' .. f.id .. '.'
        if get(key .. 'enabled', f.enabled) then
            local x = get(key .. 'x', f.coords.x) + 0.0
            local y = get(key .. 'y', f.coords.y) + 0.0
            local z = get(key .. 'z', f.coords.z) + 0.0
            local zone = { id = 'faction_' .. f.id, label = f.label, faction = f.faction, kind = f.kind,
                           coords = vector3(x, y, z), radius = get(key .. 'radius', f.radius) + 0.0 }
            if f.poly then
                -- the shape moves with the centre; radius becomes the circle around it (spawn checks use that)
                local ox, oy = x - f.coords.x, y - f.coords.y
                zone.poly, zone.radius = {}, 0.0
                for i, p in ipairs(f.poly) do
                    zone.poly[i] = vector2(p.x + ox, p.y + oy)
                    zone.radius = math.max(zone.radius, #(vector2(x, y) - zone.poly[i]))
                end
            end
            Zones.Safe[#Zones.Safe + 1] = zone
        end
    end
end
-- Player safezone flags (bs_faction_bases) are safezones as well: no spawns, no PvP. Outposts are not.
-- Called with the flag list
function Zones.SetFlagZones(flags)
    for i = #Zones.Safe, 1, -1 do
        if Zones.Safe[i].flag then table.remove(Zones.Safe, i) end
    end
    for _, f in ipairs(flags or {}) do
        if f.status ~= 'removed' and f.kind == 'safezone' and f.x and f.y then
            Zones.Safe[#Zones.Safe + 1] = {
                id = 'flag_' .. tostring(f.id), flag = true, kind = 'safezone', playerFaction = f.factionId,
                label = (f.label or f.factionId or 'Faction') .. ' Safezone',
                coords = vector3(f.x + 0.0, f.y + 0.0, (f.z or 0.0) + 0.0), radius = (f.radius or 100.0) + 0.0,
            }
        end
    end
end

Zones.SyncFactionSafe()
AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function() Zones.SyncFactionSafe() end)

-- The screamer archetype was removed; its 3-6% per zone was added to walker so zone weights still total the same
Zones.Spawn = {
    {
        id          = 'blaine_county',
        label       = 'Blaine County',
        coords      = vector3(1400.0, 3600.0, 35.0),
        radius      = 1500.0,
        difficulty  = 1.0,
        density     = 0.6,               -- multiplier on the per-client budget
        types       = { walker = 98, brute = 2 },
        lootTable   = 'rural',
    },
    {
        id          = 'los_santos',
        label       = 'Los Santos',
        coords      = vector3(200.0, -900.0, 30.0),
        radius      = 2500.0,
        difficulty  = 1.6,
        density     = 1.0,
        types       = { walker = 95, brute = 5 },
        lootTable   = 'urban',
    },
    {
        id          = 'military',
        label       = 'Fort Zancudo',
        coords      = vector3(-2100.0, 3100.0, 32.0),
        radius      = 900.0,
        difficulty  = 2.4,
        density     = 1.4,
        types       = { walker = 88, brute = 12 },
        lootTable   = 'military',
    },
    {
        id          = 'hospital',
        label       = 'Central Hospital',
        coords      = vector3(340.0, -1400.0, 32.0),
        radius      = 300.0,
        difficulty  = 2.0,
        density     = 1.3,
        types       = { walker = 94, brute = 6 },
        lootTable   = 'medical',
    },
}

--- Difficulty scaling applied on top of the zone value.
Zones.Scaling = {
    -- Night is worse.
    nightMultiplier     = 1.35,
    nightHours          = { from = 20, to = 6 },
    -- Each additional player inside a zone adds this much density.
    perPlayerDensity    = 0.08,
    -- Heat rises with gunfire and kills, and decays over time.
    heatPerKill         = 0.4,
    heatPerGunshot      = 0.15,
    heatDecayPerMinute  = 3.0,
    heatMax             = 100.0,
}
