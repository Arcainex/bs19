-- bs_vehicles - vehicle registry, one record per plate

local Registry = {}     -- [plate] = record
local dirty = {}        -- [plate] = true
local driver = {}       -- [plate] = src currently reporting

-- Part and item names in a given player's language (sv_pumps and sv_world use these too).
function VehPartName(src, def)
    if not def then return '' end
    local key = 'part.' .. tostring(def.id)
    local text = Lp(src, key)
    return text ~= key and text or (def.label or tostring(def.id))
end

function VehItemName(src, item)
    local ok, label = pcall(function() return exports.bs_inventory:ItemLabel(item, src) end)
    if ok and type(label) == 'string' and label ~= '' then return label end
    local def = exports.bs_inventory:GetItem(item)
    return def and def.label or tostring(item)
end

-- Helpers

local function now() return os.time() end

-- MySQL returns DATETIME as 'YYYY-MM-DD HH:MM:SS'
local function parseDatetime(s)
    -- oxmysql hands DATETIME back as epoch milliseconds, older setups as a string.
    if type(s) == 'number' then return math.floor(s / 1000) end
    if type(s) ~= 'string' then return nil end
    local y, mo, d, h, mi, se = s:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(se),
    })
end

-- oxmysql returns TINYINT(1) as a boolean, plain ints as numbers.
local function flag(v) return v == true or v == 1 or v == '1' end

local function clean(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('%s+', ''):upper()
    if plate == '' or #plate > 12 then return nil end
    return plate
end

local function decode(raw, fallback)
    if type(raw) ~= 'string' or raw == '' then return fallback end
    local ok, value = pcall(json.decode, raw)
    return (ok and type(value) == 'table') and value or fallback
end

-- Plates for a car nobody owns yet
local PLATE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local function randomPlate()
    local body = {}
    for i = 1, (Vehicles.Plate.length or 6) do
        local idx = math.random(1, #PLATE_CHARS)
        body[i] = PLATE_CHARS:sub(idx, idx)
    end
    return (Vehicles.Plate.prefix or '') .. table.concat(body)
end

-- A plate nothing in memory or the database uses
local function generatePlate()
    for _ = 1, 8 do
        local plate = clean(randomPlate())
        if plate and not Registry[plate] then
            local rows = exports.oxmysql:query_async(
                'SELECT 1 FROM `bs_vehicles` WHERE `plate` = ? LIMIT 1', { plate })
            if not rows or #rows == 0 then return plate end
        end
    end
    return nil
end

exports('GeneratePlate', generatePlate)

-- Every part at full health. Used for a vehicle nobody has seen before.
local function freshParts()
    local out = {}
    for _, part in ipairs(Vehicles.Parts) do out[part.id] = 100.0 end
    return out
end

-- Fills in anything a record is missing, so callers never nil-check parts.
local function normalise(record)
    record.parts = record.parts or {}
    for _, part in ipairs(Vehicles.Parts) do
        local value = tonumber(record.parts[part.id])
        record.parts[part.id] = math.max(0.0, math.min(100.0, value or 100.0))
    end
    record.fuel = math.max(0.0, math.min(100.0, tonumber(record.fuel) or 60.0))
    record.locked = record.locked and true or false

    -- Parts not fitted at all (world spawns start without them). Stored as a list, kept as a set.
    local missing = {}
    for k, v in pairs(record.missing or {}) do
        if type(k) == 'number' and type(v) == 'string' then missing[v] = true
        elseif type(k) == 'string' and v then missing[k] = true end
    end
    record.missing = missing

    -- Per-wheel state, index to 0 fine / 1 burst / 2 detached
    record.tyres = record.tyres or {}
    for idx, value in pairs(record.tyres) do
        value = tonumber(value) or 0
        if value < 1 or value > 2 then
            record.tyres[idx] = nil
        else
            record.tyres[idx] = value
        end
    end

    -- Performance/visual mods for the admin Car Tuning menu
    record.mods = record.mods or {}
    for modType, index in pairs(record.mods) do
        index = tonumber(index)
        if not index then record.mods[modType] = nil end
    end

    return record
end

-- Loading and saving

local function rowToRecord(row)
    return normalise({
        id       = row.id,
        plate    = row.plate,
        model    = row.model,
        owner    = row.owner_character_id,
        fuel     = row.fuel,
        body     = row.body_health,
        engine   = row.engine_health,
        tank     = row.tank_health,
        parts    = decode(row.parts, freshParts()),
        missing  = decode(row.missing, {}),
        worldSpawn = flag(row.world_spawn),
        category   = row.category,
        wreckedAt  = parseDatetime(row.wrecked_at),
        mods     = decode(row.mods, {}),
        tyres    = decode(row.tyres_burst, {}),
        props    = decode(row.props, nil),
        position = decode(row.position, nil),
        locked     = flag(row.locked),
        stored     = flag(row.stored),
        scrapped   = flag(row.scrapped),
        strippedAt = parseDatetime(row.stripped_at),
        keys       = {},   -- filled below
    })
end

local function loadKeys(record)
    local rows = exports.oxmysql:query_async(
        'SELECT `character_id` FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?',
        { record.id }) or {}

    record.keys = {}
    for _, row in ipairs(rows) do record.keys[tonumber(row.character_id)] = true end
end

-- Reads a vehicle by plate, creating the record on first sight
local function get(plate, model)
    plate = clean(plate)
    if not plate then return nil end
    if Registry[plate] then return Registry[plate] end

    local row = exports.oxmysql:single_async(
        'SELECT * FROM `bs_vehicles` WHERE `plate` = ? LIMIT 1', { plate })

    if not row then
        if not model then return nil end

        -- Found cars start used but not broken
        local parts = freshParts()
        for _, part in ipairs(Vehicles.Parts) do
            -- Just above the symptom line at worst, near-new at best.
            local floor = (part.warn or 50) + 4
            parts[part.id] = math.random(math.floor(floor), 96) + 0.0
        end

        local id = exports.oxmysql:insert_async([[
            INSERT INTO `bs_vehicles` (`plate`, `model`, `fuel`, `parts`, `locked`)
            VALUES (?, ?, ?, ?, 0)
        ]], { plate, tostring(model), math.random(10, 65) + 0.0, json.encode(parts) })

        row = {
            id = id, plate = plate, model = tostring(model),
            fuel = 40.0, body_health = 1000.0, engine_health = 1000.0,
            tank_health = 1000.0, parts = json.encode(parts),
            locked = 0, stored = 0, scrapped = 0,
        }
    end

    local record = rowToRecord(row)
    loadKeys(record)
    Registry[plate] = record
    return record
end

local function missingList(record)
    local out = {}
    for id in pairs(record.missing or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function save(record)
    if not record or not record.id then return end

    exports.oxmysql:execute_async([[
        UPDATE `bs_vehicles` SET
            `owner_character_id` = ?, `fuel` = ?, `body_health` = ?,
            `engine_health` = ?, `tank_health` = ?, `parts` = ?, `mods` = ?, `tyres_burst` = ?,
            `props` = ?, `position` = ?, `locked` = ?, `stored` = ?, `scrapped` = ?,
            `stripped_at` = ?, `missing` = ?, `wrecked_at` = ?
        WHERE `id` = ?
    ]], {
        record.owner, record.fuel, record.body or 1000.0,
        record.engine or 1000.0, record.tank or 1000.0,
        json.encode(record.parts or {}),
        json.encode(record.mods or {}),
        json.encode(record.tyres or {}),
        record.props and json.encode(record.props) or nil,
        record.position and json.encode(record.position) or nil,
        record.locked and 1 or 0, record.stored and 1 or 0,
        record.scrapped and 1 or 0,
        record.strippedAt and os.date('%Y-%m-%d %H:%M:%S', record.strippedAt) or nil,
        json.encode(missingList(record)),
        record.wreckedAt and os.date('%Y-%m-%d %H:%M:%S', record.wreckedAt) or nil,
        record.id,
    })
end

-- Batched writes: fuel changing several times a second must not mean that many DB round trips.
CreateThread(function()
    while true do
        Wait(Vehicles.Settings.persistInterval or 30000)

        local wrote = 0
        for plate in pairs(dirty) do
            dirty[plate] = nil
            local record = Registry[plate]
            if record then save(record); wrote = wrote + 1 end
        end

        -- Silent unless something happens: this runs every 30 s and a heartbeat line would bury real errors
        if wrote > 3 then
            print(('^2[BeyondSurvival]^7 (vehicles) persisted %d vehicles'):format(wrote))
        end
    end
end)

local function touch(plate) dirty[plate] = true end

-- Stripped hulks and exploded wrecks are deleted after Vehicles.World.wreckMinutes (F1)
local function wreckMinutes() return math.max(5, tonumber(Vehicles.World and Vehicles.World.wreckMinutes) or 120) end

CreateThread(function()
    while true do
        Wait(5 * 60000)

        local mins = wreckMinutes()
        local where = [[
            (`scrapped` = 1 AND `stripped_at` IS NOT NULL AND `stripped_at` <= (NOW() - INTERVAL ? MINUTE))
            OR (`wrecked_at` IS NOT NULL AND `wrecked_at` <= (NOW() - INTERVAL ? MINUTE))
        ]]
        local rows = exports.oxmysql:query_async('SELECT `id`, `plate` FROM `bs_vehicles` WHERE ' .. where, { mins, mins }) or {}

        if #rows > 0 then
            for _, row in ipairs(rows) do
                exports.oxmysql:execute_async('DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { row.id })
                Registry[row.plate] = nil
                dirty[row.plate] = nil
            end
            exports.oxmysql:execute_async('DELETE FROM `bs_vehicles` WHERE ' .. where, { mins, mins })
            TriggerClientEvent('bs:vehicles:removed', -1, (function()
                local list = {}
                for _, row in ipairs(rows) do list[#list + 1] = row.plate end
                return list
            end)())

            print(('^2[BeyondSurvival]^7 (vehicles) removed %d wreck(s) past %d minutes'):format(#rows, mins))
        end
    end
end)

-- Who may open it

-- Is a vehicle with this plate within radius of the caller's ped (or are they in it)?
local function nearPlate(src, plate, radius)
    local want = clean(plate)
    local ped = GetPlayerPed(src)
    if not want or not ped or ped == 0 then return false end
    local from = GetEntityCoords(ped)
    local inside = GetVehiclePedIsIn(ped, false)
    for _, veh in ipairs(GetAllVehicles()) do
        if clean(GetVehicleNumberPlateText(veh)) == want then
            if veh == inside then return true end
            if #(GetEntityCoords(veh) - from) <= radius then return true end
        end
    end
    return false
end

local function charIdOf(src)
    local player = exports.bs_core:GetPlayer(src)
    return player and player.charId or nil
end

-- An unowned car can't be locked, so abandoned cars stay usable
local function hasKey(record, charId)
    if not record or not charId then return false end
    if not record.owner then return true end
    if tonumber(record.owner) == tonumber(charId) then return true end
    return record.keys[tonumber(charId)] == true
end

-- The state a client needs

-- Plain data only. Nothing with a method crosses this boundary.
local function payload(record, charId)
    return {
        plate  = record.plate,
        model  = record.model,
        owned  = record.owner ~= nil,
        mine   = record.owner ~= nil and tonumber(record.owner) == tonumber(charId or -1),
        key    = hasKey(record, charId),
        locked = record.locked,
        fuel   = record.fuel,
        parts  = record.parts,
        tyres  = record.tyres,
        scrapped = record.scrapped,
        missing  = missingList(record),
        wrecked  = record.wreckedAt ~= nil,
    }
end

-- Callbacks

BSB.RegisterCallback('vehicles:state', function(src, plate, model)
    local record = get(plate, model)
    if not record then return { ok = false } end
    return { ok = true, vehicle = payload(record, charIdOf(src)) }
end)

BSB.RegisterCallback('vehicles:lock', function(src, plate, wanted)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local charId = charIdOf(src)
    if not hasKey(record, charId) then
        return { ok = false, error = Lp(src, 'srv.no_key') }
    end

    record.locked = (wanted == nil) and (not record.locked) or (wanted and true or false)
    touch(record.plate)

    TriggerClientEvent('bs:vehicles:lockState', -1, record.plate, record.locked)

    return { ok = true, locked = record.locked }
end)

-- Claiming an unowned car: this is how a vehicle enters the economy. It becomes yours with a key.
BSB.RegisterCallback('vehicles:claim', function(src, plate, model)
    if not nearPlate(src, plate, 4.0) then return { ok = false, error = Lp(src, 'srv.not_at') } end
    local record = get(plate, model)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end
    if record.scrapped then return { ok = false, error = Lp(src, 'srv.nothing_left') } end

    local charId = charIdOf(src)
    if not charId then return { ok = false, error = 'no character' } end

    if record.owner then
        if tonumber(record.owner) == tonumber(charId) then
            return { ok = false, error = Lp(src, 'srv.yours') }
        end
        return { ok = false, error = Lp(src, 'srv.owned') }
    end

    record.owner = charId
    record.locked = true
    touch(record.plate)
    save(record)

    TriggerClientEvent('bs:vehicles:lockState', -1, record.plate, true)

    return { ok = true, vehicle = payload(record, charId) }
end)

-- Handing over a key
BSB.RegisterCallback('vehicles:giveKey', function(src, plate, targetSrc)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local charId = charIdOf(src)
    if not record.owner or tonumber(record.owner) ~= tonumber(charId) then
        return { ok = false, error = Lp(src, 'srv.not_yours_keys') }
    end

    local targetChar = charIdOf(tonumber(targetSrc) or -1)
    if not targetChar then return { ok = false, error = Lp(src, 'srv.not_here') } end
    if tonumber(targetChar) == tonumber(charId) then
        return { ok = false, error = Lp(src, 'srv.have_one') }
    end

    exports.oxmysql:execute_async([[
        INSERT IGNORE INTO `bs_vehicle_keys` (`vehicle_id`, `character_id`, `granted_by`)
        VALUES (?, ?, ?)
    ]], { record.id, targetChar, charId })

    record.keys[tonumber(targetChar)] = true

    TriggerClientEvent('bs:ui:notify', tonumber(targetSrc), {
        type = 'success',
        message = Lp(tonumber(targetSrc), 'keys.given', { plate = record.plate }),
        duration = 4000,
    })

    return { ok = true }
end)

BSB.RegisterCallback('vehicles:revokeKeys', function(src, plate)
    local record = get(plate)
    if not record then return { ok = false } end

    local charId = charIdOf(src)
    if not record.owner or tonumber(record.owner) ~= tonumber(charId) then
        return { ok = false, error = Lp(src, 'srv.not_yours') }
    end

    exports.oxmysql:execute_async(
        'DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    record.keys = {}

    return { ok = true }
end)

-- Every vehicle this character can open. Feeds the "my vehicles" list.
BSB.RegisterCallback('vehicles:mine', function(src)
    local charId = charIdOf(src)
    if not charId then return { ok = true, vehicles = {} } end

    local rows = exports.oxmysql:query_async([[
        SELECT v.`plate`, v.`model`, v.`fuel`, v.`locked`, v.`scrapped`,
               (v.`owner_character_id` = ?) AS `mine`
        FROM `bs_vehicles` v
        LEFT JOIN `bs_vehicle_keys` k ON k.`vehicle_id` = v.`id` AND k.`character_id` = ?
        WHERE (v.`owner_character_id` = ? OR k.`character_id` IS NOT NULL)
          AND v.`scrapped` = 0
        ORDER BY v.`updated_at` DESC
    ]], { charId, charId, charId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            plate = row.plate, model = row.model,
            fuel = row.fuel, locked = flag(row.locked),
            mine = tonumber(row.mine) == 1,
        }
    end

    return { ok = true, vehicles = out }
end)

-- VIP plate text (bs_vip 'plateText')
local plateCooldown = {}

BSB.RegisterCallback('vehicles:setPlate', function(src, netId, text)
    local ok, perk = pcall(function() return exports.bs_vip:HasPerk(src, 'plateText') end)
    if not ok or perk ~= true then return { ok = false, error = Lp(src, 'srv.vip_plate') } end

    local okText, newPlate, why = pcall(function() return exports.bs_vip:ValidatePlateText(text, src) end)
    if not okText or not newPlate then return { ok = false, error = why or Lp(src, 'srv.plate_bad') } end

    local now = os.time()
    if plateCooldown[src] and now - plateCooldown[src] < ((Vip and Vip.Plate and Vip.Plate.cooldownSec) or 60) then
        return { ok = false, error = Lp(src, 'srv.plate_wait') }
    end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return { ok = false, error = Lp(src, 'srv.veh_not_found') } end
    if GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return { ok = false, error = Lp(src, 'srv.must_drive') } end

    local oldPlate = clean(GetVehicleNumberPlateText(veh))
    local record = oldPlate and get(oldPlate)
    local charId = charIdOf(src)
    if not record or not charId or record.owner ~= charId then return { ok = false, error = Lp(src, 'srv.dont_own') } end

    local key = clean(newPlate)
    if not key then return { ok = false, error = Lp(src, 'srv.plate_bad') } end
    if key == oldPlate then return { ok = false, error = Lp(src, 'srv.plate_same') } end
    if Registry[key] then return { ok = false, error = Lp(src, 'srv.plate_taken') } end
    local taken = exports.oxmysql:query_async('SELECT 1 FROM `bs_vehicles` WHERE `plate` = ? LIMIT 1', { key })
    if taken and #taken > 0 then return { ok = false, error = Lp(src, 'srv.plate_taken') } end

    local hasItems = false
    pcall(function() hasItems = exports.bs_inventory:ContainerHasItems('veh:' .. oldPlate) == true end)
    if hasItems then return { ok = false, error = Lp(src, 'srv.empty_boot') } end

    local done = exports.oxmysql:update_async('UPDATE `bs_vehicles` SET `plate` = ? WHERE `id` = ?', { key, record.id })
    if not done or done < 1 then return { ok = false, error = Lp(src, 'srv.plate_save') } end

    Registry[oldPlate] = nil
    dirty[oldPlate] = nil
    driver[oldPlate] = nil
    record.plate = key
    if type(record.props) == 'table' then record.props.plate = newPlate end
    Registry[key] = record
    touch(key)

    SetVehicleNumberPlateText(veh, newPlate)
    plateCooldown[src] = now
    return { ok = true, plate = newPlate }
end)

AddEventHandler('playerDropped', function() plateCooldown[source] = nil end)

-- Lockpicking (vehicles:lockpickStart / vehicles:hotwire) lives in sv_world.lua.

-- Fuel and wear, reported by whoever is driving

-- Plausibility gate: a report is accepted only if it is a decrease no larger than the config's
RegisterNetEvent('bs:vehicles:report', function(plate, fuel, parts, body, engine, tyres)
    local src = source
    plate = clean(plate)
    if not plate then return end

    local record = Registry[plate]
    if not record then return end

    -- One reporter at a time: whoever is driving. Everyone else is ignored.
    if driver[plate] and driver[plate] ~= src then return end
    driver[plate] = src

    local elapsed = math.max(0.2, (now() - (record.reportedAt or now())))
    record.reportedAt = now()

    local maxDrain = ((Vehicles.Fuel.drain + Vehicles.Fuel.leakDrain) / 60.0)
        * elapsed * 1.5 + 0.5

    local reported = tonumber(fuel)
    if reported then
        reported = math.max(0.0, math.min(100.0, reported))
        local drop = record.fuel - reported
        if drop > 0 and drop <= maxDrain then
            record.fuel = reported
            touch(plate)

            -- Burning fuel means the engine runs, so the alternator tops the battery up to its capacity.
            local perMin = tonumber(((Vehicles.Pumps or {}).recharge or {}).drivingPerMinute) or 0
            if perMin > 0 and not record.missing.battery then
                local cap = tonumber(record.parts.batteryCap) or 100.0
                local before = record.parts.battery or 100.0
                if before < cap then
                    record.parts.battery = math.min(cap, before + perMin * elapsed / 60.0)
                    if math.floor(record.parts.battery) ~= math.floor(before) then
                        TriggerClientEvent('bs:vehicles:battery', src, plate, record.parts.battery)
                    end
                end
            end
        end
    end

    if type(parts) == 'table' then
        for _, part in ipairs(Vehicles.Parts) do
            local value = part.id ~= 'battery' and tonumber(parts[part.id]) or nil
            if value then
                value = math.max(0.0, math.min(100.0, value))
                -- Same rule: wear only goes down by report
                if value < record.parts[part.id] then
                    record.parts[part.id] = value
                    touch(plate)
                end
            end
        end
    end

    -- Body/engine health, same decrease-only gate as fuel
    local reportedBody = tonumber(body)
    if reportedBody then
        reportedBody = math.max(0.0, math.min(1000.0, reportedBody))
        if reportedBody < (record.body or 1000.0) then
            record.body = reportedBody
            touch(plate)
        end
    end

    local reportedEngine = tonumber(engine)
    if reportedEngine then
        reportedEngine = math.max(0.0, math.min(1000.0, reportedEngine))
        if reportedEngine < (record.engine or 1000.0) then
            record.engine = reportedEngine
            touch(plate)
        end
    end

    -- Wheels: 0 fine, 1 burst, 2 detached
    if type(tyres) == 'table' then
        for idx, value in pairs(tyres) do
            local key = tostring(tonumber(idx) or idx)
            value = tonumber(value)
            if value and value >= 0 and value <= 2 then
                local current = tonumber(record.tyres[key]) or 0
                if value > current then
                    record.tyres[key] = value
                    touch(plate)
                end
            end
        end
    end
end)

RegisterNetEvent('bs:vehicles:position', function(plate, x, y, z, h)
    local src = source
    plate = clean(plate)
    local record = plate and Registry[plate]
    if not record then return end
    if driver[plate] and driver[plate] ~= src then return end

    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end

    record.position = { x = x, y = y, z = z, h = tonumber(h) or 0.0, placed = true }
    touch(plate)
end)


AddEventHandler('playerDropped', function()
    local src = source
    for plate, who in pairs(driver) do
        if who == src then driver[plate] = nil end
    end
end)

-- Refuelling and repair

-- Refuelling from a container (see the measured container note in bs_inventory)
BSB.RegisterCallback('vehicles:refuel', function(src, plate)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end
    if record.missing.fueltank then return { ok = false, error = Lp(src, 'srv.no_tank') } end
    if record.fuel >= 99.5 then return { ok = false, error = Lp(src, 'srv.tank_full') } end

    local containers = Vehicles.Fuel.containers or { Vehicles.Fuel.canItem or 'fuel_can' }

    local info = exports.bs_inventory:MeasuredInfo(src, containers)
    if not info or (info.containers or 0) < 1 then
        return { ok = false, error = Lp(src, 'srv.need_can') }
    end
    if (info.held or 0) <= 0 then
        return { ok = false, error = Lp(src, 'srv.can_empty') }
    end

    -- Only what the tank can actually take, so a full can poured into a nearly full tank isn't wasted
    local wanted = math.min(100.0 - record.fuel, info.held)
    local drawn = exports.bs_inventory:PourOut(src, containers, wanted)
    if drawn <= 0 then return { ok = false, error = Lp(src, 'srv.nothing_out') } end

    record.fuel = math.min(100.0, record.fuel + drawn)
    touch(record.plate)

    return { ok = true, fuel = record.fuel, poured = drawn }
end)

-- Exposes the fuel level to sv_pumps.lua. get and touch are locals here and an export would only
function VehPumpFuelOf(plate)
    local record = get(plate)
    return record and (record.fuel or 0.0) or nil
end

-- Battery charge and capacity. parts.battery is the charge, parts.batteryCap the most it can hold (wears down with jump-starts).
function VehPumpBatteryOf(plate)
    local record = get(plate)
    if not record then return nil end
    if record.missing.battery then return 0.0, 0.0 end
    local cap = tonumber(record.parts.batteryCap) or 100.0
    return math.min(cap, record.parts.battery or 100.0), cap
end

function VehPumpDrainBattery(plate, amount)
    local record = get(plate)
    if not record then return nil end
    local level = record.parts.battery or 100.0
    record.parts.battery = math.max(0.0, level - math.max(0.0, tonumber(amount) or 0.0))
    touch(record.plate)
    return record.parts.battery
end

-- Sets charge and capacity in one go. Cap 0 means the battery is junk: it comes out of the car.
function VehPumpSetBattery(plate, charge, cap)
    local record = get(plate)
    if not record then return nil end
    cap = math.max(0.0, math.min(100.0, tonumber(cap) or 100.0))
    record.parts.batteryCap = cap
    record.parts.battery = math.max(0.0, math.min(cap, tonumber(charge) or 0.0))
    if cap <= 0 then record.missing.battery = true end
    touch(record.plate)
    save(record)
    if driver[plate] then TriggerClientEvent('bs:vehicles:battery', driver[plate], plate, record.parts.battery) end
    return record.parts.battery
end

function VehPumpMissing(plate, id)
    local record = get(plate)
    return record and record.missing[id] == true or false
end

function VehPumpApplyFuel(plate, amount)
    local record = get(plate)
    if not record then return nil end
    if record.missing.fueltank then return record.fuel end

    record.fuel = math.min(100.0, (record.fuel or 0.0) + math.max(0.0, tonumber(amount) or 0.0))
    touch(record.plate)

    return record.fuel
end

-- Siphoning: no money changes hands (see config_vehicles.lua)
local function siphonCheck(src, plate)
    local record = get(plate)
    if not record then return nil, Lp(src, 'srv.unknown') end
    if record.owner then return nil, Lp(src, 'srv.someone_got') end
    if record.missing.fueltank then return nil, Lp(src, 'srv.no_tank_fuel') end
    if record.fuel <= 5.0 then return nil, Lp(src, 'fuel.nothing_drain') end

    -- Fuel leaves the tank and goes into a container you brought. No container, no siphon.
    local containers = Vehicles.Fuel.containers or { Vehicles.Fuel.canItem or 'fuel_can' }
    local missing = {}
    local tool = Vehicles.Fuel.siphonTool
    if tool and exports.bs_inventory:CountItem(src, tool) < 1 then
        missing[#missing + 1] = VehItemName(src, tool)
    end
    local info = exports.bs_inventory:MeasuredInfo(src, containers)
    if not info or (info.containers or 0) < 1 then
        missing[#missing + 1] = Lp(src, 'srv.need_can_bottle')
    end
    if #missing > 0 then return nil, table.concat(missing, ' ') end
    if (info.room or 0) <= 0 then return nil, Lp(src, 'srv.nothing_fill') end
    return record, containers, info
end

BSB.RegisterCallback('vehicles:siphonCheck', function(src, plate)
    local record, err = siphonCheck(src, plate)
    if not record then return { ok = false, error = err } end
    return { ok = true }
end)

BSB.RegisterCallback('vehicles:siphon', function(src, plate)
    local record, containers, info = siphonCheck(src, plate)
    if not record then return { ok = false, error = containers } end

    local available = math.min(record.fuel, Vehicles.Fuel.siphonAmount or 35.0)
    local stored = exports.bs_inventory:PourInto(src, containers, math.min(available, info.room))
    if stored <= 0 then return { ok = false, error = Lp(src, 'srv.nothing_fill') } end

    record.fuel = math.max(0.0, record.fuel - stored)
    touch(record.plate)

    return { ok = true, taken = stored }
end)

-- Searching a station: a chance, with a cooldown per station (findChance / cooldown in config_vehicles.lua)
local stationCooldowns = {}   -- [index] = os.time() this station is free again

local function nearestStation(x, y, z)
    local best, bestDist, bestIndex
    for i, station in ipairs(Vehicles.Stations or {}) do
        local dist = #(vector3(x, y, z) - vector3(station.x, station.y, station.z))
        if not bestDist or dist < bestDist then best, bestDist, bestIndex = station, dist, i end
    end
    return best, bestDist, bestIndex
end

BSB.RegisterCallback('vehicles:searchStation', function(src, index, x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then
        return { ok = false, error = 'no fix on you' }
    end

    local station, dist, foundIndex = nearestStation(x, y, z)
    if not station or dist > (Vehicles.StationSettings.radius or 15.0) then
        return { ok = false, error = Lp(src, 'srv.no_station') }
    end
    -- The client's guess at the station and the server's nearest match should agree; if not, trust the server
    index = foundIndex

    local readyAt = stationCooldowns[index] or 0
    if now() < readyAt then
        return { ok = false, error = Lp(src, 'srv.picked') }
    end
    stationCooldowns[index] = now() + (Vehicles.StationSettings.cooldown or 600)

    if math.random() > (Vehicles.StationSettings.findChance or 0.55) then
        return { ok = true, found = false }
    end

    local ok = exports.bs_inventory:GiveItem(src, Vehicles.Fuel.canItem or 'fuel_can', 1)
    if not ok then return { ok = false, error = Lp(src, 'srv.no_room') } end

    return { ok = true, found = true }
end)

-- Staff: print your position ready to paste as a Vehicles.Stations row, for fixing a misplaced station
RegisterCommand('bs_station_here', function(src)
    if src == 0 then return print('^3[BS VEHICLES]^7 run this in-game, not from the console.') end
    if not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    print(('^5[BS VEHICLES]^7 { label = \'name me\', x = %.1f, y = %.1f, z = %.1f },')
        :format(at.x, at.y, at.z))
    TriggerClientEvent('bs:ui:notify', src, {
        type = 'info', message = 'Coordinates printed to server console.', duration = 3000,
    })
end, false)

local function partById(id)
    for _, part in ipairs(Vehicles.Parts) do
        if part.id == id then return part end
    end
end

-- Any part repair or fit: XP/skill via bs_core, and one step on mechanic repair contracts (bs_jobs)
function VehRepaired(src)
    exports.bs_core:AwardAction(src, 'vehicle_repaired')
    TriggerEvent('bs:jobs:event', src, 'vehicle_repaired', 1)
end

BSB.RegisterCallback('vehicles:repair', function(src, plate, partId)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local part = partById(partId)
    if not part then return { ok = false, error = Lp(src, 'srv.unknown_part') } end
    if (record.parts[part.id] or 100) >= 99.0 then
        return { ok = false, error = Lp(src, 'srv.part_fine', { part = VehPartName(src, part) }) }
    end

    -- Check everything before taking anything, so a repair never eats half the parts and then fails.
    for _, cost in ipairs(part.repair or {}) do
        if exports.bs_inventory:CountItem(src, cost.item) < cost.amount then
            return { ok = false, error = Lp(src, 'srv.need_items', { n = cost.amount, item = VehItemName(src, cost.item) }) }
        end
    end

    for _, cost in ipairs(part.repair or {}) do
        exports.bs_inventory:RemoveItem(src, cost.item, cost.amount)
    end

    record.parts[part.id] = 100.0
    if part.id == 'battery' then record.parts.batteryCap = 100.0 end
    touch(record.plate)
    save(record)

    VehRepaired(src)

    return { ok = true, part = part.id, label = part.label, parts = record.parts }
end)

-- Repair everything: same contract as the single-part version
BSB.RegisterCallback('vehicles:repairAll', function(src, plate)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local due = {}
    for _, part in ipairs(Vehicles.Parts) do
        if (record.parts[part.id] or 100) < 99.0 then due[#due + 1] = part end
    end

    if #due == 0 then
        return { ok = false, error = Lp(src, 'srv.nothing_fix') }
    end

    -- Total cost across every part, checked before taking anything
    local totals = {}
    for _, part in ipairs(due) do
        for _, cost in ipairs(part.repair or {}) do
            totals[cost.item] = (totals[cost.item] or 0) + cost.amount
        end
    end

    for item, amount in pairs(totals) do
        if exports.bs_inventory:CountItem(src, item) < amount then
            return { ok = false, error = Lp(src, 'srv.need_items_all', { n = amount, item = VehItemName(src, item) }) }
        end
    end

    for item, amount in pairs(totals) do
        exports.bs_inventory:RemoveItem(src, item, amount)
    end

    for _, part in ipairs(due) do
        record.parts[part.id] = 100.0
        VehRepaired(src)
    end

    touch(record.plate)
    save(record)

    return { ok = true, fixed = #due, parts = record.parts }
end)

-- Admin Car Tuning menu

local function isVehicleAdmin(src) return IsPlayerAceAllowed(src, 'bs.admin') end

BSB.RegisterCallback('vehicles:tuningRead', function(src, plate)
    if not isVehicleAdmin(src) then return { ok = false, error = 'not allowed' } end

    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    return { ok = true, mods = record.mods or {} }
end)

BSB.RegisterCallback('vehicles:tuningSave', function(src, plate, mods)
    if not isVehicleAdmin(src) then return { ok = false, error = 'not allowed' } end
    if type(mods) ~= 'table' then return { ok = false, error = 'bad mods table' } end

    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    -- Keys come back from the client's JSON round trip as numbers or numeric strings
    local clean = {}
    for modType, index in pairs(mods) do
        index = tonumber(index)
        if index and index >= -1 then clean[tostring(modType)] = index end
    end

    record.mods = clean
    touch(record.plate)
    save(record)

    local count = 0
    for _ in pairs(clean) do count = count + 1 end
    print(('^3[BS VEHICLES]^7 %s saved a tune for %s (%d mod slot%s)')
        :format(GetPlayerName(src), plate, count, count == 1 and '' or 's'))

    return { ok = true, mods = record.mods }
end)

-- Temporary fix, see Vehicles.Settings.tempFixTime
local tempFixCooldowns = {} -- [plate][partId] = os.time() of the last attempt

BSB.RegisterCallback('vehicles:tempfix', function(src, plate, partId)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local part = partById(partId)
    if not part then return { ok = false, error = Lp(src, 'srv.unknown_part') } end
    if (record.parts[part.id] or 100) > (part.fail or 0) then
        return { ok = false, error = Lp(src, 'srv.not_failed', { part = VehPartName(src, part) }) }
    end

    local cooldown = Vehicles.Settings.tempFixCooldown or 300
    local last = tempFixCooldowns[record.plate] and tempFixCooldowns[record.plate][part.id]
    if last and now() - last < cooldown then
        local wait = cooldown - (now() - last)
        return { ok = false, error = Lp(src, 'srv.patch_wait', { part = VehPartName(src, part), min = math.ceil(wait / 60) }) }
    end

    -- A configured cost is still charged, but the default is none.
    local cost = Vehicles.Settings.tempFixCost or {}
    for _, c in ipairs(cost) do
        if exports.bs_inventory:CountItem(src, c.item) < c.amount then
            return { ok = false, error = Lp(src, 'srv.need_items', { n = c.amount, item = VehItemName(src, c.item) }) }
        end
    end
    for _, c in ipairs(cost) do
        exports.bs_inventory:RemoveItem(src, c.item, c.amount)
    end

    tempFixCooldowns[record.plate] = tempFixCooldowns[record.plate] or {}
    tempFixCooldowns[record.plate][part.id] = now()

    -- Engineers (and any class with the perk) are better at this gamble
    local chance = Vehicles.Settings.tempFixSuccessChance or 0.4
    local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if ok and summary and summary.stats and type(summary.stats.tempFixBonus) == 'number' then
        chance = math.min(0.95, chance + summary.stats.tempFixBonus)
    end

    local success = math.random() < chance
    if success then
        record.parts[part.id] = (part.fail or 0) + (Vehicles.Settings.tempFixMargin or 14)
        touch(record.plate)
        save(record)
        VehRepaired(src)   -- a field patch is a repair too
    end

    return {
        ok = true, success = success,
        part = part.id, label = part.label, parts = record.parts,
    }
end)

-- Scrapping

-- Stripping leaves a hulk (no wheels, doors or bonnet, see bs_vehicles/client/cl_strip.lua) that
local ScrapSessions = {}

local function sg() return Vehicles.ScrapGame end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Best tool carried (first match in config order is the best).
local function scrapTool(src)
    for _, tool in ipairs(sg().tools or {}) do
        local n = 0
        pcall(function() n = exports.bs_inventory:CountItem(src, tool.item) or 0 end)
        if n > 0 then return tool end
    end
    return nil
end

local function scrapSkill(src)
    local lvl = 0
    pcall(function() lvl = exports.bs_skills:GetSkillLevel(src, sg().xpTree) or 0 end)
    return lvl
end

-- Builds the next check for a session and remembers it server side.
local function nextChallenge(sess)
    local part = sess.parts[sess.idx]
    if not part then return nil end
    local cfg = sg()
    local zone = clamp(part.zone + sess.zoneBonus, 0.06, 0.5)
    local lo, hi = 0.30, 0.88
    if part.mode == 'hold' then lo, hi = 0.45, 0.90 end
    local center = lo + math.random() * (hi - lo)
    sess.cur = {
        part = part, zone = zone, center = center, period = part.period,
        issued = GetGameTimer(),
    }
    return { index = sess.idx, id = part.id, mode = part.mode, zone = zone, center = center,
             period = part.period, laps = cfg.maxLaps, perfect = cfg.perfectFrac }
end

local function scrapPos(mode, period, t)
    if mode == 'hold' then return t / period end
    local x = (t / period) % 2
    return x <= 1 and x or 2 - x
end

local function finishScrap(src, sess, record)
    ScrapSessions[src] = nil
    local cfg = sg()

    local condition = 0.0
    for _, part in ipairs(Vehicles.Parts) do
        condition = condition + (record.parts[part.id] or 0)
    end
    condition = condition / (#Vehicles.Parts * 100.0)
    local condMult = 0.4 + condition * 0.6

    local totals, order = {}, {}
    for _, res in ipairs(sess.results) do
        if res.salvaged then
            for _, entry in ipairs(res.part.yield) do
                if math.random() <= (entry.chance or 1.0) then
                    local amount = math.random(entry.min or 0, entry.max or 1)
                    amount = math.floor(amount * res.mult * sess.toolMult * condMult + 0.5)
                    if amount > 0 then
                        if not totals[entry.item] then totals[entry.item] = 0; order[#order + 1] = entry.item end
                        totals[entry.item] = totals[entry.item] + amount
                    end
                end
            end
        end
    end

    local yield = {}
    for _, item in ipairs(order) do
        if exports.bs_inventory:GiveItem(src, item, totals[item]) then
            yield[#yield + 1] = { item = item, amount = totals[item] }
        end
    end

    record.scrapped = true
    record.strippedAt = now()
    record.owner = nil
    record.locked = false
    touch(record.plate)
    save(record)

    exports.oxmysql:execute_async(
        'DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    record.keys = {}

    exports.bs_core:AwardAction(src, 'vehicle_scrapped')
    pcall(function()
        exports.bs_skills:AddSkillXP(src, cfg.xpTree, (cfg.xpPerPart or 0) * #sess.results)
    end)

    -- Broadcast so anyone near the entity right now sees it stripped at once (listener in cl_strip.lua)
    TriggerClientEvent('bs:vehicles:scrapped', -1, record.plate)
    return yield
end

-- Starts a job: checks the car, picks the parts, issues the first check.
BSB.RegisterCallback('vehicles:scrapBegin', function(src, plate)
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end
    if record.scrapped then return { ok = false, error = Lp(src, 'srv.stripped') } end

    local charId = charIdOf(src)
    if record.owner and tonumber(record.owner) ~= tonumber(charId) then
        return { ok = false, error = Lp(src, 'srv.someone_else') }
    end
    if not nearPlate(src, record.plate, (Vehicles.Settings.scrapRange or 4.0) + 1.5) then
        return { ok = false, error = Lp(src, 'srv.not_at') }
    end
    if exports.bs_inventory:ContainerHasItems('veh:' .. record.plate) then
        return { ok = false, error = Lp(src, 'srv.boot_items') }
    end

    local cfg = sg()
    local old = ScrapSessions[src]
    if old and GetGameTimer() < old.deadline + 5000 then
        return { ok = false, error = Lp(src, 'scrap.busy') }
    end
    for other, s2 in pairs(ScrapSessions) do
        if other ~= src and s2.plate == record.plate and GetGameTimer() < s2.deadline + 5000 then
            return { ok = false, error = Lp(src, 'scrap.busy') }
        end
    end

    local tool = scrapTool(src)
    local level = scrapSkill(src)
    local sess = {
        plate = record.plate, parts = {}, results = {}, idx = 1,
        started = GetGameTimer(), deadline = GetGameTimer() + cfg.totalTime,
        chanceBonus = (tool and tool.chance or 0) + level * (cfg.skill.chancePerLevel or 0),
        zoneBonus   = (tool and tool.zone or 0) + level * (cfg.skill.zonePerLevel or 0),
        toolMult    = tool and tool.mult or 1.0,
        toolItem    = tool and tool.item or nil,
    }
    for _, part in ipairs(cfg.parts) do
        -- A part that was never fitted cannot come out.
        if not (part.missing and record.missing and record.missing[part.missing]) then
            sess.parts[#sess.parts + 1] = part
        end
    end
    if #sess.parts == 0 then return { ok = false, error = Lp(src, 'radial.nothing_usable') } end
    ScrapSessions[src] = sess

    local list = {}
    for i, part in ipairs(sess.parts) do list[i] = { id = part.id, mode = part.mode } end
    return {
        ok = true, parts = list, tool = sess.toolItem, skill = level,
        total = cfg.totalTime, challenge = nextChallenge(sess),
    }
end)

-- Validates the reported timing for the current part and issues the next one. t = ms (client clock), -1 = gave up.
BSB.RegisterCallback('vehicles:scrapStep', function(src, index, t)
    local sess = ScrapSessions[src]
    if not sess or not sess.cur or sess.cur.part ~= sess.parts[sess.idx] or tonumber(index) ~= sess.idx then
        return { ok = false, error = Lp(src, 'scrap.no_job') }
    end
    local cfg = sg()
    local record = get(sess.plate)
    if not record or record.scrapped then
        ScrapSessions[src] = nil
        return { ok = false, error = Lp(src, 'srv.stripped') }
    end
    if not nearPlate(src, sess.plate, (Vehicles.Settings.scrapRange or 4.0) + 3.0) then
        ScrapSessions[src] = nil
        return { ok = false, error = Lp(src, 'srv.not_at') }
    end

    local cur = sess.cur
    local nowMs = GetGameTimer()
    local elapsed = nowMs - cur.issued
    local outcome = 'miss'

    if nowMs > sess.deadline + (cfg.graceMs or 700) then
        outcome = 'timeout'
    elseif type(t) == 'number' and t == t and t >= 0 then
        local limit = cur.period * (cur.part.mode == 'hold' and 1.25 or (cfg.maxLaps * 2))
        if t < (cfg.minReactMs or 180) or t > elapsed + (cfg.graceMs or 700) then
            outcome = 'miss'      -- too fast to be real, or longer than the check has been open
        elseif t <= limit then
            local pos = scrapPos(cur.part.mode, cur.period, t)
            local half = cur.zone / 2
            local d = math.abs(pos - cur.center)
            if d <= half * (cfg.perfectFrac or 0.25) then outcome = 'perfect'
            elseif d <= half then outcome = 'good' end
        end
    end

    local salvaged = false
    local mult = cfg.mult[outcome] or cfg.mult.miss
    if outcome ~= 'timeout' then
        local chance = cur.part.chance + sess.chanceBonus
        if outcome == 'miss' then chance = chance * (cfg.missChance or 0.5) end
        salvaged = math.random() <= clamp(chance, cfg.minChance or 0.05, cfg.maxChance or 0.97)
    end
    sess.results[#sess.results + 1] = { part = cur.part, outcome = outcome, salvaged = salvaged, mult = mult }
    sess.cur = nil
    sess.idx = sess.idx + 1

    local reply = { ok = true, outcome = outcome, salvaged = salvaged }
    if outcome == 'timeout' or not sess.parts[sess.idx] then
        reply.done = true
        reply.yield = finishScrap(src, sess, record)
        reply.timeout = outcome == 'timeout'
    else
        reply.challenge = nextChallenge(sess)
    end
    return reply
end)

-- The player backed out: nothing is taken, nothing is given, the car stays as it was.
BSB.RegisterCallback('vehicles:scrapCancel', function(src)
    ScrapSessions[src] = nil
    return { ok = true }
end)

AddEventHandler('playerDropped', function() ScrapSessions[source] = nil end)

-- The boot

BSB.RegisterCallback('vehicles:trunk', function(src, plate)
    -- Prevents opening a boot from anywhere just by knowing the plate.
    if not nearPlate(src, plate, 4.0) then return { ok = false, error = Lp(src, 'srv.not_at') } end
    local record = get(plate)
    if not record then return { ok = false, error = Lp(src, 'srv.unknown') } end

    local charId = charIdOf(src)
    if record.locked and not hasKey(record, charId) then
        return { ok = false, error = Lp(src, 'srv.locked') }
    end

    local containerId = 'veh:' .. record.plate

    -- Registers the real spec server-side after the lock/ownership check. bs_inventory only trusts this, never a client's claim.
    exports.bs_inventory:RegisterContainer(containerId, {
        size      = Vehicles.Settings.trunkSize or 60,
        maxWeight = Vehicles.Settings.trunkWeight or 200.0,
        label     = Lp(src, 'srv.boot_label', { plate = record.plate }),
    }, src)  -- src grants this player the open; without it bs_inventory refuses

    TriggerClientEvent('bs:inventory:openContainer', src, containerId)

    return { ok = true }
end)

-- Asked by the client before it lets a vehicle be cleaned up.
BSB.RegisterCallback('vehicles:keep', function(_, plate)
    plate = clean(plate)
    if not plate then return { ok = true, keep = false } end

    local record = Registry[plate] or get(plate)
    -- A stripped hulk has no owner and an empty boot, so the checks below would let it despawn
    local owned = record and (record.owner ~= nil or record.scrapped or record.worldSpawn or record.wreckedAt ~= nil)

    local hasStuff = false
    local ok, answer = pcall(function()
        return exports.bs_inventory:ContainerHasItems('veh:' .. plate)
    end)
    if ok then hasStuff = answer and true or false end

    return { ok = true, keep = (owned or hasStuff) and true or false }
end)

-- Bringing a saved vehicle back

local lease = {}        -- [plate] = { src, until }

local function leaseFree(plate, src)
    local held = lease[plate]
    if held and held.src ~= src and held.expires > now() then return false end
    lease[plate] = { src = src, expires = now() + 20 }
    return true
end

BSB.RegisterCallback('vehicles:around', function(src, x, y, z, radius)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then
        return { ok = false }
    end

    radius = math.min(400.0, math.max(20.0, tonumber(radius) or 200.0))

    -- Stripped wrecks are included while inside their 3-day window and restored as hulks
    local rows = exports.oxmysql:query_async([[
        SELECT `plate`, `model`, `fuel`, `parts`, `mods`, `tyres_burst`, `position`, `locked`,
               `owner_character_id`, `body_health`, `engine_health`, `scrapped`, `world_spawn`, `wrecked_at`
        FROM `bs_vehicles`
        WHERE `stored` = 0 AND `position` IS NOT NULL
    ]]) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local pos = decode(row.position, nil)

        if pos and pos.x then
            local dx, dy, dz = pos.x - x, pos.y - y, pos.z - z
            if (dx * dx + dy * dy + dz * dz) <= radius * radius then

                -- Only cars worth restoring: owned, something in the boot, or a stripped hulk inside its window
                local keep = row.owner_character_id ~= nil or flag(row.scrapped)
                    or flag(row.world_spawn) or row.wrecked_at ~= nil
                if not keep then
                    local ok, answer = pcall(function()
                        return exports.bs_inventory:ContainerHasItems('veh:' .. row.plate)
                    end)
                    keep = ok and answer or false
                end

                if keep and leaseFree(row.plate, src) then
                    out[#out + 1] = {
                        plate = row.plate,
                        model = row.model,
                        fuel  = row.fuel,
                        parts = decode(row.parts, nil),
                        mods  = decode(row.mods, nil),
                        tyres = decode(row.tyres_burst, nil),
                        locked = flag(row.locked),
                        position = pos,
                        body   = tonumber(row.body_health) or 1000.0,
                        engine = tonumber(row.engine_health) or 1000.0,
                        stripped = flag(row.scrapped),
                        wrecked  = row.wrecked_at ~= nil,
                        -- A world spawn nobody has seen yet: the client re-checks the spot before placing it.
                        fresh    = flag(row.world_spawn) and not pos.placed,
                    }
                end
            end
        end

        -- A single client is never asked to rebuild a whole car park at once.
        if #out >= 6 then break end
    end

    return { ok = true, vehicles = out }
end)

-- The client is done (or failed). The lease is returned either way so someone else can retry.
RegisterNetEvent('bs:vehicles:spawned', function(plate, success)
    local src = source
    plate = clean(plate)
    if not plate then return end

    local held = lease[plate]
    if held and held.src ~= src then return end

    if success then
        -- Held for a while: the car exists now, and a second request shortly after must not create another
        lease[plate] = { src = src, expires = now() + 120 }
    else
        lease[plate] = nil
    end
end)

-- The restoring client re-checked a fresh world spawn and may have moved it to a clear spot.
RegisterNetEvent('bs:vehicles:placed', function(plate, x, y, z, h)
    local src = source
    plate = clean(plate)
    if not plate or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    local held = lease[plate]
    if not held or held.src ~= src then return end
    local record = get(plate)
    if not record or not record.position then return end
    -- A nudge along the road, not a teleport.
    if #(vector2(record.position.x, record.position.y) - vector2(x, y)) > 120.0 then return end
    record.position = { x = x, y = y, z = z, h = tonumber(h) or 0.0, placed = true }
    touch(plate)
    save(record)
end)

-- Staff

RegisterCommand('vehinfo', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local plate = clean(args[1])
    local record = plate and Registry[plate]

    if not record then return print('^1[BS VEHICLES]^7 not loaded: ' .. tostring(args[1])) end

    print(('^5[BS VEHICLES]^7 %s (%s)  owner=%s  locked=%s  fuel=%.1f')
        :format(record.plate, record.model, tostring(record.owner),
                tostring(record.locked), record.fuel))
    for _, part in ipairs(Vehicles.Parts) do
        print(('   %-14s %5.1f'):format(part.label, record.parts[part.id] or 0))
    end
end, false)

-- Exports

-- Staff removal for /dv and the F10 vehicle tools
local function adminRemove(plate)
    plate = clean(plate)
    local record = plate and get(plate)
    if not record then return false end
    lease[plate] = nil
    driver[plate] = nil

    exports.oxmysql:execute_async('DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    exports.oxmysql:execute_async('DELETE FROM `bs_vehicles` WHERE `id` = ?', { record.id })
    Registry[plate] = nil
    dirty[plate] = nil
    TriggerClientEvent('bs:vehicles:removed', -1, { plate })
    return 'removed'
end

exports('AdminRemove', adminRemove)
-- Old name, kept for anything still calling it.
exports('AdminDelete', function(plate) return adminRemove(plate) ~= false end)

-- Brings a stored owned car back out at the given spot
exports('AdminUnstore', function(plate, x, y, z, h)
    plate = clean(plate)
    local record = plate and get(plate)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not record or not record.stored or not x or not y or not z then return false end
    record.stored = false
    record.position = { x = x, y = y, z = z, h = tonumber(h) or 0.0, placed = true }
    lease[plate] = nil
    save(record)
    return true, record.model
end)

-- bs_crafting wreck salvage. Only a burnt-out wreck the player stands next to.
exports('IsWreckNear', function(src, plate)
    local record = get(clean(plate) or '')
    return record ~= nil and record.wreckedAt ~= nil and nearPlate(src, plate, 6.0)
end)

exports('SalvageWreck', function(src, plate)
    plate = clean(plate)
    local record = plate and get(plate)
    if not record or not record.wreckedAt or not nearPlate(src, plate, 6.0) then return false end
    for _, veh in ipairs(GetAllVehicles()) do
        if clean(GetVehicleNumberPlateText(veh)) == plate then DeleteEntity(veh) end
    end
    exports.oxmysql:execute_async('DELETE FROM `bs_vehicle_keys` WHERE `vehicle_id` = ?', { record.id })
    exports.oxmysql:execute_async('DELETE FROM `bs_vehicles` WHERE `id` = ?', { record.id })
    Registry[plate] = nil
    dirty[plate] = nil
    TriggerClientEvent('bs:vehicles:removed', -1, { plate })
    return true, record.model
end)

exports('Get', function(plate) local r = get(plate); return r and payload(r, nil) or nil end)

-- Faction jobs (bs_jobs). The garage writes mod slots here so a tune persists like the admin one.
exports('JobInfo', function(plate)
    local r = get(clean(plate) or '')
    if not r then return nil end
    return { owner = r.owner and tonumber(r.owner) or nil, model = r.model, mods = r.mods, fuel = r.fuel,
             wrecked = r.wreckedAt ~= nil, scrapped = r.scrapped == true, missing = missingList(r) }
end)
exports('JobMergeMods', function(plate, mods)
    local r = get(clean(plate) or '')
    if not r or type(mods) ~= 'table' then return false end
    for k, v in pairs(mods) do
        v = tonumber(v)
        if tonumber(k) and v then r.mods[tostring(math.floor(tonumber(k)))] = v end
    end
    touch(r.plate)
    save(r)
    return true
end)
-- Returns the part ids taken
exports('JobChop', function(plate, ids)
    local r = get(clean(plate) or '')
    if not r or r.scrapped or r.wreckedAt then return {} end
    local took = {}
    for _, id in ipairs(ids or {}) do
        if not r.missing[id] then r.missing[id] = true; took[#took + 1] = id end
    end
    if #took > 0 then touch(r.plate); save(r) end
    return took
end)
-- Fuel siphon. Takes up to amount (tank percent) and returns what came out.
exports('JobTakeFuel', function(plate, amount)
    local r = get(clean(plate) or '')
    if not r or r.scrapped then return 0 end
    local take = math.max(0, math.min(r.fuel or 0, tonumber(amount) or 0))
    if take <= 0 then return 0 end
    r.fuel = r.fuel - take
    touch(r.plate)
    return take
end)
exports('HasKey', function(src, plate)
    local record = Registry[clean(plate) or '']
    return record and hasKey(record, charIdOf(src)) or false
end)
exports('Fuel', function(plate)
    local record = Registry[clean(plate) or '']
    return record and record.fuel or nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Never lose a tank of fuel to a resource restart.
    for _, record in pairs(Registry) do save(record) end
end)

exports.bs_core:RegisterModule('vehicles', { side = 'server', version = '1.0.0', ready = true })

-- Narrow globals for sv_world.lua, which adds world spawns, fitting, wrecks and lockpicking on top of the registry
VehReg = {
    get = get, save = save, touch = touch, clean = clean, payload = payload,
    charIdOf = charIdOf, hasKey = hasKey, nearPlate = nearPlate,
    registry = Registry, dirty = dirty, generatePlate = generatePlate, normalise = normalise,
}

-- bs_tester hooks
exports('TesterRegister', function(plate, model, charId)
    plate = clean(plate)
    if not plate or type(model) ~= 'string' or model == '' then return nil end
    if Registry[plate] then return nil end
    local id = exports.oxmysql:insert_async([[
        INSERT INTO `bs_vehicles` (`plate`, `model`, `fuel`, `parts`, `missing`, `owner_character_id`, `locked`, `world_spawn`)
        VALUES (?, ?, 100.0, ?, '[]', ?, 0, 0)
    ]], { plate, model, json.encode(freshParts()), tonumber(charId) })
    if not id then return nil end
    local record = get(plate)
    return record and payload(record, charId) or nil
end)

-- Returns the new client payload
exports('TesterRestore', function(plate)
    local record = get(plate)
    if not record or record.scrapped then return nil end
    for _, part in ipairs(Vehicles.Parts) do record.parts[part.id] = 100.0 end
    record.missing, record.tyres = {}, {}
    record.fuel = 100.0
    record.body, record.engine, record.tank = 1000.0, 1000.0, 1000.0
    local wasWreck = record.wreckedAt ~= nil
    record.wreckedAt = nil
    touch(record.plate)
    save(record)
    if wasWreck then TriggerClientEvent('bs:vehicles:unwrecked', -1, record.plate) end
    return payload(record, record.owner)
end)

-- Admin /repair: every part, missing part, tyre and health back to full. Fuel is left alone.
exports('AdminRepair', function(plate)
    local record = get(plate)
    if not record or record.scrapped then return nil end
    for _, part in ipairs(Vehicles.Parts) do record.parts[part.id] = 100.0 end
    record.missing, record.tyres = {}, {}
    record.body, record.engine, record.tank = 1000.0, 1000.0, 1000.0
    local wasWreck = record.wreckedAt ~= nil
    record.wreckedAt = nil
    touch(record.plate)
    save(record)
    if wasWreck then TriggerClientEvent('bs:vehicles:unwrecked', -1, record.plate) end
    return payload(record, record.owner)
end)

-- The live world pool (F1 edits included) as { model, category } rows.
exports('TesterPool', function()
    local out = {}
    for category, text in pairs((Vehicles.World and Vehicles.World.pool) or {}) do
        for chunk in tostring(text or ''):gmatch('[^,]+') do
            local model = chunk:match('^%s*([%w_]+)')
            if model then out[#out + 1] = { model = model:lower(), category = category } end
        end
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.model < b.model
    end)
    return out
end)
