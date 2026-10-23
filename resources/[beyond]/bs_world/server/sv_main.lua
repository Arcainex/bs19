-- bs_world - world state is client-simulated; the server answers questions about it and lets staff toggle a zone's power

local disabled = {}   -- [zoneId] = true when staff have cut a zone's power
local gen = {}        -- [zoneId] = { fuel = 0-100, health = 0-100, owner = string|nil }
local blackout = false
local KVP = 'bs_power_state'

local function zoneById(id)
    for _, zone in ipairs(Power.Zones) do if zone.id == id then return zone end end
end

local function genOf(id)
    local g = gen[id]
    if not g then g = { fuel = 100.0, health = 100.0 }; gen[id] = g end
    return g
end

-- Lit = switched on, not in blackout, has fuel and is not broken.
local function lit(id)
    local g = genOf(id)
    return not disabled[id] and g.fuel > 0 and g.health > 0
end

local function save()
    local out = { blackout = blackout, zones = {} }
    for _, zone in ipairs(Power.Zones) do
        local g = genOf(zone.id)
        out.zones[zone.id] = { off = disabled[zone.id] or false, fuel = g.fuel, health = g.health, owner = g.owner }
    end
    SetResourceKvp(KVP, json.encode(out))
end

-- Generator state survives a restart.
do
    local ok, data = pcall(json.decode, GetResourceKvpString(KVP) or '')
    if ok and type(data) == 'table' then
        blackout = data.blackout == true
        for id, z in pairs(data.zones or {}) do
            if zoneById(id) then
                disabled[id] = z.off == true or nil
                gen[id] = { fuel = tonumber(z.fuel) or 100.0, health = tonumber(z.health) or 100.0, owner = z.owner }
            end
        end
    end
end

local function push(id)
    TriggerClientEvent('bs:world:zoneState', -1, id, lit(id))
end

local function zoneInfo(zone)
    local g = genOf(zone.id)
    return {
        id = zone.id, label = zone.label, postal = zone.postal, radius = zone.radius,
        x = zone.coords.x, y = zone.coords.y, z = zone.coords.z,
        on = not disabled[zone.id], powered = lit(zone.id),
        fuel = math.floor(g.fuel + 0.5), health = math.floor(g.health + 0.5), owner = g.owner,
        disabled = disabled[zone.id] or false,
    }
end

BSB.RegisterCallback('world:powerZones', function()
    local out = {}
    for _, zone in ipairs(Power.Zones) do out[#out + 1] = zoneInfo(zone) end
    return out
end)

local function setZonePower(id, on)
    if not zoneById(id) then return nil end
    disabled[id] = (not on) or nil
    push(id)
    save()
    return lit(id)
end

BSB.RegisterCallback('world:togglePower', function(src, zoneId)
    if not IsPlayerAceAllowed(src, 'bs.admin') and not IsPlayerAceAllowed(src, 'bs.superadmin') then
        return { ok = false, error = 'not allowed' }
    end
    local found = zoneById(zoneId)
    if not found then return { ok = false, error = 'unknown zone' } end
    setZonePower(zoneId, disabled[zoneId] == true)
    print(('^3[BS WORLD]^7 %s %s power in %s'):format(
        GetPlayerName(src), disabled[zoneId] and 'cut' or 'restored', found.label))
    return { ok = true, powered = lit(zoneId) }
end)

-- Staff blackout (/blackout, F10): cuts every generator zone at once, or brings them all back
exports('SetBlackout', function(on)
    blackout = on == true
    for _, zone in ipairs(Power.Zones) do
        disabled[zone.id] = blackout or nil
        push(zone.id)
    end
    save()
    print(('^3[BS WORLD]^7 blackout %s'):format(blackout and 'on' or 'off'))
    return blackout
end)

exports('Blackout', function() return blackout end)

-- Admin POWER tab and other resources (jobs, events).
exports('PowerZones', function()
    local out = {}
    for _, zone in ipairs(Power.Zones) do out[#out + 1] = zoneInfo(zone) end
    return out
end)
exports('PowerZone', function(id) local z = zoneById(id); return z and zoneInfo(z) or nil end)
exports('SetZonePower', setZonePower)
exports('RefuelZone', function(id, amount)
    if not zoneById(id) then return nil end
    local g = genOf(id)
    g.fuel = math.min(100.0, g.fuel + math.max(0.0, tonumber(amount) or 100.0))
    push(id); save()
    return g.fuel
end)
-- Fuel Runner generator service: puts back Power.Settings.serviceRefuel.
exports('ServiceZone', function(id)
    if not zoneById(id) then return nil end
    local g = genOf(id)
    g.fuel = math.min(100.0, g.fuel + (tonumber(Power.Settings.serviceRefuel) or 50.0))
    push(id); save()
    return g.fuel
end)
exports('RepairZone', function(id)
    if not zoneById(id) then return nil end
    genOf(id).health = 100.0
    push(id); save()
    return true
end)
exports('DamageZone', function(id, amount)
    if not zoneById(id) then return nil end
    local g = genOf(id)
    g.health = math.max(0.0, g.health - math.max(0.0, tonumber(amount) or 0.0))
    push(id); save()
    return g.health
end)
exports('SetZoneOwner', function(id, owner)
    if not zoneById(id) then return nil end
    genOf(id).owner = (type(owner) == 'string' and owner ~= '') and owner:sub(1, 48) or nil
    save()
    return true
end)
-- Everything back on: blackout off, every zone switched on, refuelled and repaired.
exports('RestoreAll', function()
    blackout = false
    for _, zone in ipairs(Power.Zones) do
        disabled[zone.id] = nil
        local g = genOf(zone.id)
        g.fuel, g.health = 100.0, 100.0
        push(zone.id)
    end
    save()
    print('^3[BS WORLD]^7 power restored everywhere')
    return true
end)

-- Generators burn fuel while lit, only when fuelDrainPerHour > 0. One cheap pass a minute.
CreateThread(function()
    while true do
        Wait(60000)
        local rate = tonumber(Power.Settings.fuelDrainPerHour) or 0
        if rate > 0 then
            for _, zone in ipairs(Power.Zones) do
                if lit(zone.id) then
                    local g = genOf(zone.id)
                    g.fuel = math.max(0.0, g.fuel - rate / 60)
                    if g.fuel <= 0 then push(zone.id) end
                end
            end
            save()
        end
    end
end)

-- Is this spot powered?
exports('PoweredAt', function(x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return nil end

    if not Power.Settings.enabled then return nil end

    local zone = Power.ZoneAt(vector3(x, y, z))
    if not zone or not lit(zone.id) then return nil end

    return zone.id
end)

-- Zones that are dark, so joining clients match the server.
BSB.RegisterCallback('world:powerCuts', function()
    local out = {}
    for _, zone in ipairs(Power.Zones) do
        if not lit(zone.id) then out[#out + 1] = zone.id end
    end
    return { ok = true, cuts = out }
end)

exports.bs_core:RegisterModule('world', { side = 'server', version = '0.1.0' })
