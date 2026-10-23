-- bs_admin - server side of the staff menu

local function hasAny(src, aces)
    for _, ace in ipairs(aces) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

local function isAdmin(src)      return hasAny(src, Admin.Settings.openAces) end
local function isSuperAdmin(src) return IsPlayerAceAllowed(src, 'bs.superadmin') end

local function mayUse(src, action)
    if not isAdmin(src) then return false end
    for _, restricted in ipairs(Admin.Settings.superAdminOnly) do
        if restricted == action then return isSuperAdmin(src) end
    end
    return true
end

local function audit(src, action, detail)
    local player = exports.bs_core:GetPlayer(src)
    print(('^3[BS ADMIN]^7 %s (%s) -> %s %s'):format(
        GetPlayerName(src), player and player.name or 'no character',
        action, detail or ''))
end

-- Staff actions worth keeping go to bs_guard_log (kind admin), shown in the GUARD tab.
-- The console has no ped or license, so its actions are only printed.
local function guardLog(src, detail)
    if not src or src == 0 then
        print(('^3[BS ADMIN]^7 console -> %s'):format(tostring(detail)))
        return
    end
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local player = exports.bs_core:GetPlayer(src)
    exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        { src, GetPlayerIdentifierByType(src, 'license'), player and player.charId or nil, (GetPlayerName(src) or '?'):sub(1, 64),
          'admin', 0, tostring(detail):sub(1, 512), c.x, c.y, c.z })
end

BSB.RegisterCallback('admin:whoami', function(src)
    return { admin = isAdmin(src), superadmin = isSuperAdmin(src) }
end)

-- Give the prefs store this file's staff check. sv_prefs.lua has no permission logic of its own, to avoid two copies drifting apart.
if BSAdminPrefs then BSAdminPrefs.IsStaff = isAdmin end

-- Export: is this player staff
exports('IsAdmin', function(src)
    src = tonumber(src)
    if not src then return false end
    return isAdmin(src) and true or false
end)

exports('IsSuperAdmin', function(src)
    src = tonumber(src)
    if not src then return false end
    return isSuperAdmin(src) and true or false
end)

BSB.RegisterCallback('admin:players', function(src)
    if not isAdmin(src) then return {} end

    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local player = exports.bs_core:GetPlayer(id)
        out[#out + 1] = {
            source    = id,
            name      = GetPlayerName(id),
            character = player and player.name or nil,
            class     = player and player.classId or nil,
            level     = player and player.level or nil,
            ping      = GetPlayerPing(id),
            tester    = GetResourceState('bs_tester') == 'started'
                and (function()
                    local ok, on = pcall(function() return exports.bs_tester:IsTester(id) end)
                    return ok and on == true
                end)() or false,
        }
    end
    table.sort(out, function(a, b) return a.source < b.source end)
    return out
end)


local actions = {}

-- Heal on a downed or dead player goes through bs_medical's Revive export first
function actions.heal(src, args)
    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'no such player' } end

    if GetResourceState('bs_medical') == 'started' then
        -- pcall: bs_medical may be restarting; a failed top-up is better than the action erroring.
        local ok, downed = pcall(function() return exports.bs_medical:IsDowned(target) end)
        if ok and downed then
            pcall(function() return exports.bs_medical:Revive(target) end)
        end
    end

    TriggerClientEvent('bs:admin:heal', target)
    return { ok = true }
end

-- Test kit: gives enough of every material the build menu can ask for
function actions.giveBuildMats(src, args)
    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end

    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'player not found' } end

    -- Ask bs_building for piece costs via export;
    local building = BS.Use('building')
    if not building then
        return { ok = false, error = 'bs_building is not running' }
    end

    local costs = building.Materials()
    if type(costs) ~= 'table' or not next(costs) then
        return { ok = false, error = 'could not read build costs from bs_building' }
    end

    -- Amount is 4x the largest single-piece cost, capped at 12, so the kit fits the lightest class's carry limit
    local given, failed = 0, {}
    for item, amount in pairs(costs) do
        local want = math.min(12, math.max(2, (tonumber(amount) or 1) * 4))
        if exports.bs_inventory:GiveItem(target, item, want) then
            given = given + 1
        else
            failed[#failed + 1] = item
        end
    end

    if #failed > 0 then
        return {
            ok = given > 0,
            count = given,
            error = ('no room for: %s'):format(table.concat(failed, ', ')),
        }
    end

    if given == 0 then
        return { ok = false, error = 'bag too full - nothing fitted' }
    end

    return { ok = true, count = given }
end

-- Wipe inventory
function actions.wipeInventory(src, args)
    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end

    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'player not found' } end

    local ok = exports.bs_inventory:WipeInventory(target)
    if not ok then return { ok = false, error = 'that player has no character loaded' } end

    TriggerClientEvent('bs:ui:notify', target, {
        type = 'warn', message = 'Your inventory was wiped by an admin.', duration = 3000,
    })

    return { ok = true }
end

-- Grant VIP from the menu
function actions.grantvip(src, args)
    if GetResourceState('bs_vip') ~= 'started' then
        return { ok = false, error = 'bs_vip is not running' }
    end

    local target = tonumber(args.target)
    if not target then return { ok = false, error = 'pick a target player first' } end

    local tierId = args.tier and tostring(args.tier):lower()

    local days = tonumber(args.days)
    if days and days <= 0 then days = nil end   -- 0/blank = no expiry

    -- GrantVIP validates the tier and target itself; just report the error it returns.
    local granted = exports.bs_vip:GrantVIP(target, tierId, days)
    if not granted then
        return { ok = false, error = 'could not grant - bad tier, or that player is not loaded' }
    end

    return { ok = true }
end

function actions.revokevip(src, args)
    if GetResourceState('bs_vip') ~= 'started' then
        return { ok = false, error = 'bs_vip is not running' }
    end

    local target = tonumber(args.target)
    if not target then return { ok = false, error = 'pick a target player first' } end

    exports.bs_vip:RevokeVIP(target)
    return { ok = true }
end

-- Stored per account by bs_tester; this only flips it
function actions.toggleTester(src, args)
    if GetResourceState('bs_tester') ~= 'started' then
        return { ok = false, error = 'bs_tester is not running' }
    end
    local target = tonumber(args.target)
    if not target then return { ok = false, error = 'pick a player first' } end
    local okc, on, err = pcall(function() return exports.bs_tester:SetTester(target, nil, src) end)
    if not okc then on = nil end
    if on == nil then return { ok = false, error = err or 'could not change tester access' } end
    return { ok = true, tester = on }
end

-- World events (bs_events)
local function eventsUp() return GetResourceState('bs_events') == 'started' end

function actions.eventList(src)
    if not eventsUp() then return { ok = false, error = 'bs_events is not running' } end
    local ok, kinds = pcall(function() return exports.bs_events:EventKinds() end)
    if not ok then return { ok = false, error = 'could not read events' } end
    return { ok = true, kinds = kinds }
end

function actions.eventStart(src, args)
    if not eventsUp() then return { ok = false, error = 'bs_events is not running' } end
    local kind = tostring(args.kind or ''):lower():gsub('[^%w_]', '')
    local at
    if args.here then
        if src == 0 then return { ok = false, error = 'in-game only' } end
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return { ok = false, error = 'no ped' } end
        local c = GetEntityCoords(ped)
        at = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) }
    end
    local name = src == 0 and 'console' or (GetPlayerName(src) or 'admin')
    local ok, started, res = pcall(function() return exports.bs_events:StartEvent(kind, name, at) end)
    if not ok then return { ok = false, error = 'start failed' } end
    if not started then return { ok = false, error = tostring(res or 'could not start') } end
    return { ok = true, id = res }
end

function actions.eventStop(src)
    if not eventsUp() then return { ok = false, error = 'bs_events is not running' } end
    local ok, n = pcall(function() return exports.bs_events:StopAllEvents() end)
    if not ok then return { ok = false, error = 'stop failed' } end
    return { ok = true, stopped = n }
end

-- Deletes unowned world cars and respawns them over the map anchors (bs_vehicles does the work).
function actions.worldCarsReset(src)
    if GetResourceState('bs_vehicles') ~= 'started' then return { ok = false, error = 'bs_vehicles is not running' } end
    local ok, removed, owedNow = pcall(function() return exports.bs_vehicles:ResetWorldCars() end)
    if not ok then return { ok = false, error = 'reset failed' } end
    guardLog(src, ('world cars reset: removed %d, respawning %d'):format(removed or 0, owedNow or 0))
    return { ok = true, note = Lp(src, 'admin.ev.cars_done', { n = removed or 0, m = owedNow or 0 }) }
end

-- Opens the bs_traders editor on the caller's own client. bs_traders re-checks access itself.
function actions.openTraderEditor(src)
    if src == 0 then return { ok = false, error = 'in-game only' } end
    if GetResourceState('bs_traders') ~= 'started' then
        return { ok = false, error = 'bs_traders is not running' }
    end
    TriggerClientEvent('bs:admin:openTraderEditor', src)
    return { ok = true }
end

-- Test server status for the F10 Test server tab (read only).
function actions.testServerState(src)
    if GetResourceState('bs_tester') ~= 'started' then
        return { ok = false, error = 'bs_tester is not running' }
    end
    local ok, st = pcall(function() return exports.bs_tester:TestServerState() end)
    if not ok or type(st) ~= 'table' then return { ok = false, error = 'no answer from bs_tester' } end
    return { ok = true, state = st }
end

function actions.grantappearance(src, args)
    if GetResourceState('bs_vip') ~= 'started' then
        return { ok = false, error = 'bs_vip is not running' }
    end
    local target = tonumber(args.target)
    if not target then return { ok = false, error = 'pick a target player first' } end
    local count = math.max(1, math.min(10, math.floor(tonumber(args.count) or 1)))
    if not exports.bs_vip:GrantAppearanceTicket(target, count) then
        return { ok = false, error = 'that player is not loaded' }
    end
    return { ok = true }
end

-- ESX-style commands (/car, /dv, /heal). They use the same admin:action gate as the menu.

-- /dv and the F10 vehicle tools
function actions.deleteVehicles(src, args)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'no ped' } end
    local at = GetEntityCoords(ped)

    local occupied = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src then
            local veh = GetVehiclePedIsIn(GetPlayerPed(id), false)
            if veh and veh ~= 0 then occupied[veh] = true end
        end
    end

    local targets = {}
    local radius = tonumber(args.radius)
    if radius then
        radius = math.max(1.0, math.min(500.0, radius))
        for _, veh in ipairs(GetAllVehicles()) do
            if #(GetEntityCoords(veh) - at) <= radius then targets[#targets + 1] = veh end
        end
    else
        local veh = tonumber(args.netId) and NetworkGetEntityFromNetworkId(tonumber(args.netId)) or 0
        if not veh or veh == 0 or not DoesEntityExist(veh) or #(GetEntityCoords(veh) - at) > 25.0 then
            return { ok = false, error = Lp(src, 'admin.c.dv_none') }
        end
        if occupied[veh] then return { ok = false, error = Lp(src, 'admin.c.dv_occupied') } end
        targets[1] = veh
    end

    local vehiclesUp = GetResourceState('bs_vehicles') == 'started'
    local removed, stored, skipped = 0, 0, 0
    for _, veh in ipairs(targets) do
        if occupied[veh] then
            skipped = skipped + 1
        else
            local kind = nil
            if vehiclesUp then
                local plate = GetVehicleNumberPlateText(veh)
                local ok, res = pcall(function() return exports.bs_vehicles:AdminRemove(plate) end)
                kind = ok and res or nil
            end
            if kind == 'stored' then stored = stored + 1 else removed = removed + 1 end
            DeleteEntity(veh)
        end
    end

    return { ok = true, count = removed, stored = stored, skipped = skipped }
end

-- actions['goto'] needs bracket syntax, goto is a reserved word in Lua 5.4
actions['goto'] = function(src, args)
    local target = tonumber(args.target)
    local ped = target and GetPlayerPed(target)
    if not ped or ped == 0 then return { ok = false, error = 'player not found' } end
    local c = GetEntityCoords(ped)
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 10000) end) end
    TriggerClientEvent('bs:admin:teleportTo', src, c.x, c.y, c.z)
    return { ok = true }
end

-- Teleport yourself to typed coords
function actions.tpCoords(src, args)
    if src == 0 then return { ok = false, error = 'in game only' } end
    local x, y = tonumber(args.x), tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or x ~= x or y ~= y or math.abs(x) > 10000 or math.abs(y) > 10000 then
        return { ok = false, error = 'invalid coords' }
    end
    if z and (z ~= z or z < -200 or z > 2000) then return { ok = false, error = 'invalid Z' } end
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 15000) end) end
    TriggerClientEvent('bs:admin:tpCoords', src, x + 0.0, y + 0.0, z and (z + 0.0) or false)
    return { ok = true, note = ('%.1f, %.1f, %s'):format(x, y, z and ('%.1f'):format(z) or 'ground') }
end

-- Full repair of the car the admin is in or looking at (client sends its net id). bs_vehicles
function actions.repairVehicle(src, args)
    if src == 0 then return { ok = false, error = 'in game only' } end
    local netId = tonumber(args.netId)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then
        return { ok = false, error = 'no vehicle' }
    end
    if #(GetEntityCoords(veh) - GetEntityCoords(GetPlayerPed(src))) > 40.0 then
        return { ok = false, error = 'too far' }
    end
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()
    args.plate = plate
    local record = nil
    if plate ~= '' and GetResourceState('bs_vehicles') == 'started' then
        local ok, r = pcall(function() return exports.bs_vehicles:AdminRepair(plate) end)
        if ok then record = r end
    end
    local sent = {}
    local function tell(id)
        if id and id > 0 and not sent[id] then sent[id] = true; TriggerClientEvent('bs:admin:repairVehicle', id, netId, record) end
    end
    tell(NetworkGetEntityOwner(veh))
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver and driver ~= 0 and IsPedAPlayer(driver) then tell(NetworkGetEntityOwner(driver)) end
    tell(src)
    return { ok = true, plate = plate }
end

function actions.bring(src, args)
    local target = tonumber(args.target)
    if not target then return { ok = false, error = 'player not found' } end
    local c = GetEntityCoords(GetPlayerPed(src))
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(target, 'teleport', 10000) end) end
    TriggerClientEvent('bs:admin:teleportTo', target, c.x, c.y, c.z)
    return { ok = true }
end

function actions.kick(src, args)
    local target = tonumber(args.target)
    if not target or target == src then return { ok = false, error = 'pick someone else' } end
    DropPlayer(target, ('Kicked by staff: %s'):format(args.reason or 'no reason given'))
    return { ok = true }
end

-- exports.bs_core:GetPlayer returns a serialised copy without methods

function actions.givemoney(src, args)
    local target = tonumber(args.target) or src
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return { ok = false, error = 'bad amount' } end

    if not exports.bs_core:AddMoney(target, args.account == 'bank' and 'bank' or 'cash',
                                    amount, 'admin menu') then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end

function actions.givexp(src, args)
    local target = tonumber(args.target) or src
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return { ok = false, error = 'bad amount' } end

    if not exports.bs_core:AddXP(target, amount, 'admin menu') then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end

function actions.setlevel(src, args)
    local target = tonumber(args.target) or src
    local level = math.floor(tonumber(args.level) or 0)
    if level < 1 then return { ok = false, error = 'bad level' } end

    if not exports.bs_core:SetLevel(target, level) then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end

-- Debug: class list from bs_core's Config.Classes, so the dropdown matches it.
function actions.classes(src, args)
    local list = {}
    local ok, classes = pcall(function() return exports.bs_core:ClassList() end)
    if ok and type(classes) == 'table' then list = classes end
    return { ok = true, classes = list }
end

-- Debug: change a character's class (self or target). Updates DB and live state.
function actions.setclass(src, args)
    local target = tonumber(args.target) or src
    if type(args.class) ~= 'string' then return { ok = false, error = 'pick a class' } end
    local ok, done, err = pcall(function() return exports.bs_core:SetClass(target, args.class) end)
    if not ok then return { ok = false, error = 'bs_core refused' } end
    if not done then return { ok = false, error = err or 'no character loaded' } end
    return { ok = true }
end

-- Weather and time go through bs_world, which owns that state
local function world(fn, ...)
    if GetResourceState('bs_world') ~= 'started' then
        return nil, 'bs_world is not running'
    end
    local ok, res = pcall(function(...) return exports.bs_world[fn](exports.bs_world, ...) end, ...)
    if not ok then return nil, tostring(res) end
    return res
end

function actions.setWeather(src, args)
    local ok = false
    for _, w in ipairs(Admin.Weather) do if w == args.weather then ok = true end end
    if not ok then return { ok = false, error = 'unknown weather' } end

    -- freeze defaults to true. args.freeze == false sets the weather and lets the natural cycle continue.
    local res, err = world('SetWeather', args.weather, args.freeze ~= false, args.instant == true)
    if not res then return { ok = false, error = err or 'bs_world refused' } end

    return { ok = true, note = res.frozen and 'set and frozen' or 'set, cycle still running' }
end

function actions.freezeWeather(src, args)
    local res, err = world('FreezeWeather', args.on == true)
    if not res then return { ok = false, error = err or 'bs_world refused' } end
    return { ok = true, note = res.frozen and 'weather frozen' or 'weather cycle running' }
end

function actions.freezeTime(src, args)
    local res, err = world('FreezeTime', args.on == true)
    if not res then return { ok = false, error = err or 'bs_world refused' } end
    return { ok = true, note = res.frozen and 'clock frozen' or 'clock running' }
end

function actions.setTime(src, args)
    local hour = math.floor(tonumber(args.hour) or -99)

    -- -1 means let the clock run again; anything else must be 0-23.
    if hour ~= -1 and (hour < 0 or hour > 23) then
        return { ok = false, error = 'hour must be 0-23, or -1 for real time' }
    end

    -- -1 means unfreeze
    if hour == -1 then
        local res, err = world('FreezeTime', false)
        if not res then return { ok = false, error = err or 'bs_world refused' } end
        return { ok = true, note = 'clock running' }
    end

    local res, err = world('SetTime', hour, tonumber(args.minute) or 0)
    if not res then return { ok = false, error = err or 'bs_world refused' } end

    -- Setting the time shifts the clock offset and it keeps running. Freezing is separate.
    return {
        ok = true,
        note = ('set to %02d:%02d%s'):format(res.hour, res.minute,
            res.frozen and ' (clock is FROZEN - unfreeze to let it run)' or ' and running'),
    }
end

-- Shared by spawnVehicle and devcar
local function freshPlate()
    if GetResourceState('bs_vehicles') ~= 'started' then return nil end
    local ok, plate = pcall(function() return exports.bs_vehicles:GeneratePlate() end)
    return ok and plate or nil
end

function actions.spawnVehicle(src, args)
    -- Authorisation only; the client creates the entity
    local allowed = Admin.VehicleByModel[args.model] ~= nil
    if not allowed and not isSuperAdmin(src) then
        return { ok = false, error = 'that model is not on the list' }
    end
    local plate = freshPlate()
    if not plate then return { ok = false, error = 'could not generate a plate - is bs_vehicles running?' } end
    return { ok = true, plate = plate }
end

-- /devcar: ownerless vehicle with its own plate and DB row, like one found in the world
function actions.devcar(src, args)
    if type(args) ~= 'table' or type(args.model) ~= 'string' or args.model == '' then
        return { ok = false, error = 'no model given' }
    end
    local plate = freshPlate()
    if not plate then return { ok = false, error = 'could not generate a plate - is bs_vehicles running?' } end
    return { ok = true, plate = plate }
end

function actions.save(src)
    if not exports.bs_core:SavePlayer(src, true) then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end


-- Testing the systems: skills, perks, items, weapons, needs and hordes.

-- Spawned weapons go into the bag as an item, not straight onto the ped, so they can be dropped, weighed and wiped
local function weaponItemFor(model)
    -- Reference for the service layer (bs_core/shared/sh_services.lua)
    local inv = BS.Use('inventory')
    if not inv then return nil end
    return inv.ItemForWeapon(model)
end

-- Which ammo item a weapon uses
local function ammoItemFor(model)
    if GetResourceState('bs_inventory') ~= 'started' then return nil end
    local item = exports.bs_inventory:AmmoItemFor(model)
    if not item then return nil end
    local def = exports.bs_inventory:GetItem(item)
    return item, def and def.label
end

-- Mag info from bs_weapons (size, ammo item, rounds per box). nil if unknown.
local function magInfo(target, weapon)
    if GetResourceState('bs_weapons') ~= 'started' then return nil end
    local ok, info = pcall(function() return exports.bs_weapons:MagInfo(target, weapon) end)
    return ok and info or nil
end

-- Give rounds worth of ammo boxes (rounded up to whole boxes)
local function giveRounds(target, info, rounds)
    local boxes = math.max(1, math.ceil(rounds / info.boxRounds))
    if not exports.bs_inventory:GiveItem(target, info.ammoItem, boxes) then return nil end
    return boxes
end

function actions.giveweapon(src, args)
    -- Authorisation only
    local allowed = false
    for _, group in ipairs(Admin.Weapons) do
        for _, w in ipairs(group.items) do
            if w.model == args.model then allowed = true end
        end
    end
    if not allowed and not isSuperAdmin(src) then
        return { ok = false, error = 'that weapon is not on the list' }
    end

    local target = tonumber(args.target) or src

    -- Bag only, no ped fallback: a weapon with no item cannot be dropped or wiped
    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end

    local itemName = weaponItemFor(args.model)
    if not itemName then
        return { ok = false, error = ('%s has no inventory item - add one to bs_inventory/config/config_items.lua with data.weapon set to that model'):format(tostring(args.model)) }
    end

    if not exports.bs_inventory:GiveItem(target, itemName, 1) then
        return { ok = false, error = 'no room in the bag for that' }
    end

    -- Plain give includes a few boxes of ammo
    local ammoNote = nil
    local info = magInfo(target, args.model)
    local ammoItem = info and info.ammoItem

    if info and not giveRounds(target, info, info.base * 2) then
        ammoNote = ('%s would not fit in the bag'):format(info.ammoLabel or info.ammoItem)
    end

    -- The weapon arrives loaded: the saved-ammo store in bs_weapons is seeded rather than the ped, so the bag stays the source of truth
    local def = exports.bs_inventory:GetItem(itemName)
    local rounds = (info and info.base) or (def and def.data and tonumber(def.data.spawnRounds))

    if ammoItem and rounds and rounds > 0 then
        if GetResourceState('bs_weapons') ~= 'started' then
            ammoNote = ammoNote or 'bs_weapons is not running, so it spawned empty'
        else
            local ok, done = pcall(function()
                return exports.bs_weapons:SetSavedAmmo(target, args.model, rounds)
            end)
            if not ok or not done then
                ammoNote = ammoNote or 'could not preload the magazine'
            end
        end
    end

    return { ok = true, item = itemName, note = ammoNote, rounds = rounds }
end

-- Top up the weapon in hand
function actions.giveammo(src, args)
    local target = tonumber(args and args.target) or src

    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end

    -- Weapon: the one passed (must be on the admin list), else the one in hand.
    local weapon = args and args.model
    if weapon ~= nil then
        local listed = false
        for _, group in ipairs(Admin.Weapons) do
            for _, w in ipairs(group.items) do if w.model == weapon then listed = true end end
        end
        if not listed and not isSuperAdmin(src) then
            return { ok = false, error = 'that weapon is not on the list' }
        end
    else
        local ped = GetPlayerPed(target)
        if not ped or ped == 0 then return { ok = false, error = 'no ped' } end
        weapon = GetSelectedPedWeapon(ped)
        if not weapon or weapon == GetHashKey('WEAPON_UNARMED') then
            return { ok = false, error = 'nothing in your hands' }
        end
    end

    local info = magInfo(target, weapon)
    if not info then
        return { ok = false, error = 'that weapon has no magazine/ammo configured (bs_weapons Weapons.Magazines)' }
    end

    -- amount = mags (1-20, default 3). rounds = exact rounds, clamped to 1-20 mags. /ammo 2 to 2 mags, /ammo 45r to 45 rounds.
    local rounds
    local raw = args and args.amount
    local r = type(raw) == 'string' and tonumber(raw:match('^(%d+)[rR]$'))
    if args and tonumber(args.rounds) then r = tonumber(args.rounds) end
    if r then
        rounds = math.max(1, math.min(info.current * 20, math.floor(r)))
    else
        local mags = math.max(1, math.min(20, math.floor(tonumber(raw) or 3)))
        rounds = mags * info.current
    end

    local boxes = giveRounds(target, info, rounds)
    if not boxes then return { ok = false, error = 'no room in the bag for that' } end

    return { ok = true, note = ('%d x %s (%d rounds, mag %d)'):format(
        boxes, info.ammoLabel or info.ammoItem, boxes * info.boxRounds, info.current) }
end

-- Weapon kit: the weapon, its ammunition and every attachment that fits, in one click.
function actions.weaponkit(src, args)
    local model = args and args.model
    if type(model) ~= 'string' then return { ok = false, error = 'no weapon' } end

    local allowed = false
    for _, group in ipairs(Admin.Weapons) do
        for _, w in ipairs(group.items) do
            if w.model == model then allowed = true end
        end
    end
    if not allowed and not isSuperAdmin(src) then
        return { ok = false, error = 'that weapon is not on the list' }
    end

    if GetResourceState('bs_weapons') ~= 'started'
       or GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_weapons and bs_inventory must both be running' }
    end

    local target = tonumber(args.target) or src
    local given = {}

    -- Find the weapon item by scanning each item's data.weapon for this model (item names do not match models 1:1)
    local weaponItem = weaponItemFor(model)

    -- Some admin-only test weapons (flaregun, grenade, flashlight, extinguisher) have no inventory item
    local weaponNote = nil

    if not weaponItem then
        weaponNote = ('%s has no inventory item, so the gun itself was NOT given - add one to config_items.lua'):format(model)
    else
        local okWeapon, label = exports.bs_inventory:GiveItem(target, weaponItem, 1)
        if okWeapon then
            given[#given + 1] = label or weaponItem
        else
            weaponNote = 'the weapon would not fit in the bag (too heavy, or no free slot)'
        end
    end

    -- Every GiveItem result is checked
    local parts = exports.bs_weapons:AttachmentsFor(model) or {}
    local skipped = {}

    for _, part in ipairs(parts) do
        if exports.bs_inventory:GiveItem(target, part.item, 1) then
            given[#given + 1] = part.label
        else
            skipped[#skipped + 1] = part.label or part.item
        end
    end

    -- Ammo: two spare mags of boxes, and the gun loaded with one standard mag (the extmag item is in the bag, not fitted)
    local info = magInfo(target, model)
    if info then
        if giveRounds(target, info, info.base * 2) then
            given[#given + 1] = info.ammoLabel or info.ammoItem
        else
            skipped[#skipped + 1] = info.ammoLabel or info.ammoItem
        end
        if weaponItem then
            local ok, done = pcall(function()
                return exports.bs_weapons:SetSavedAmmo(target, model, info.base)
            end)
            if not ok or not done then skipped[#skipped + 1] = 'magazine preload' end
        end
    end

    -- Nothing may fail quietly here - see skipped above
    if weaponNote then skipped[#skipped + 1] = weaponNote end

    if #skipped > 0 then
        return {
            ok = true,
            given = given,
            count = #given,
            error = ('no room for: %s - bag is full, drop something and re-run the kit')
                :format(table.concat(skipped, ', ')),
        }
    end

    return { ok = true, given = given, count = #given }
end

function actions.giveitem(src, args)
    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end

    local target = tonumber(args.target) or src
    local amount = math.max(1, math.floor(tonumber(args.amount) or 1))

    local def = exports.bs_inventory:GetItem(args.item)
    if not def then return { ok = false, error = 'unknown item' } end

    local ok, label = exports.bs_inventory:GiveItem(target, args.item, amount)
    if not ok then return { ok = false, error = label or 'it would not fit' } end

    -- Admin-spawned measured containers (jerrycan, bottle) arrive full
    if def.data and tonumber(def.data.capacity) then
        pcall(function()
            exports.bs_inventory:PourInto(target, args.item,
                tonumber(def.data.capacity) * amount)
        end)
    end

    guardLog(src, ('giveitem %dx %s to %d'):format(amount, tostring(args.item), target))
    return { ok = true, label = label, amount = amount }
end

-- Undo a clothing-bench session without a relog
function actions.clothRestore(src)
    if GetResourceState('bs_inventory') ~= 'started' then
        return { ok = false, error = 'bs_inventory is not running' }
    end
    local ok = pcall(function() exports.bs_inventory:Refresh(src) end)
    if not ok then return { ok = false, error = 'Refresh export failed' } end
    return { ok = true }
end

function actions.items(src)
    if GetResourceState('bs_inventory') ~= 'started' then return { ok = true, items = {} } end

    local out = {}
    for name, def in pairs(exports.bs_inventory:GetItems() or {}) do
        -- equipSlot lets the CLOTHING panel group garments by body slot.
        out[#out + 1] = { item = name, label = def.label or name,
            category = def.category, equipSlot = def.equipSlot }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return { ok = true, items = out }
end

-- Skills

function actions.skills(src, args)
    if GetResourceState('bs_skills') ~= 'started' then
        return { ok = false, error = 'bs_skills is not running' }
    end

    local target = tonumber(args.target) or src
    local skills = exports.bs_skills:GetSkills(target)
    if not skills then return { ok = false, error = 'that character is not loaded' } end

    return {
        ok = true,
        skills = skills,
        points = exports.bs_core:GetSkillPoints(target),
    }
end

function actions.perks(src)
    if GetResourceState('bs_skills') ~= 'started' then return { ok = true, perks = {} } end
    return { ok = true, perks = exports.bs_skills:PerkCatalogue() }
end

function actions.skillxp(src, args)
    if GetResourceState('bs_skills') ~= 'started' then
        return { ok = false, error = 'bs_skills is not running' }
    end

    local target = tonumber(args.target) or src
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount == 0 then return { ok = false, error = 'bad amount' } end

    exports.bs_skills:AddSkillXP(target, args.skill, amount)
    return { ok = true }
end

function actions.setskill(src, args)
    if GetResourceState('bs_skills') ~= 'started' then
        return { ok = false, error = 'bs_skills is not running' }
    end

    local target = tonumber(args.target) or src
    local level  = math.floor(tonumber(args.level) or 0)

    local ok, err = exports.bs_skills:SetSkillLevel(target, args.skill, level)
    if not ok then return { ok = false, error = err or 'could not set that' } end
    return { ok = true }
end

function actions.perk(src, args)
    if GetResourceState('bs_skills') ~= 'started' then
        return { ok = false, error = 'bs_skills is not running' }
    end

    local target = tonumber(args.target) or src
    local ok, err

    if args.remove then
        ok, err = exports.bs_skills:RevokePerk(target, args.perk)
    else
        -- Staff grants bypass the level requirement and point cost, since the button is for testing perks
        ok, err = exports.bs_skills:GrantPerk(target, args.perk)
    end

    if not ok then return { ok = false, error = err or 'could not change that perk' } end
    return { ok = true }
end

function actions.givepoints(src, args)
    local target = tonumber(args.target) or src
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount == 0 then return { ok = false, error = 'bad amount' } end

    if not exports.bs_core:GrantSkillPoints(target, amount) then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end

function actions.respec(src, args)
    if GetResourceState('bs_skills') ~= 'started' then
        return { ok = false, error = 'bs_skills is not running' }
    end
    local target = tonumber(args.target) or src
    local refunded = exports.bs_skills:ForceRespec(target)
    return { ok = true, refunded = refunded or 0 }
end

-- Condition

function actions.setneeds(src, args)
    local target = tonumber(args.target) or src
    if not exports.bs_core:SetNeedsFor(target,
        tonumber(args.hunger), tonumber(args.thirst), tonumber(args.infection)) then
        return { ok = false, error = 'no character loaded' }
    end
    return { ok = true }
end

function actions.infect(src, args)
    local target = tonumber(args.target) or src
    -- bs_medical owns infection when it runs.
    if GetResourceState('bs_medical') == 'started' then
        local amount = tonumber(args.amount) or 25
        if amount < 0 then
            pcall(function() exports.bs_medical:Inflict(target, 'cure') end)
        else
            pcall(function() exports.bs_medical:Inflict(target, 'infect') end)
        end
        return { ok = true }
    end
    exports.bs_core:ChangeInfection(target, tonumber(args.amount) or 25)
    return { ok = true }
end

-- Medical conditions (bs_medical): heal and clear, or inflict one for testing
function actions.medical(src, args)
    if GetResourceState('bs_medical') ~= 'started' then
        return { ok = false, error = 'bs_medical is not running' }
    end
    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'no such player' } end
    local op = tostring(args.op or '')
    local ok, res, err
    if op == 'clear' then
        ok, res = pcall(function() return exports.bs_medical:ClearConditions(target) end)
        if ok and res then TriggerClientEvent('bs:medical:heal', target, 1000) end
    else
        ok, res, err = pcall(function() return exports.bs_medical:Inflict(target, op) end)
    end
    if not ok or not res then return { ok = false, error = err or 'could not do that' } end
    pcall(function() exports.bs_medical:Log(src, ('staff %s on %s'):format(op, target)) end)
    return { ok = true }
end

-- Starts the tutorial on a player (bs_tutorial checks combat itself and skips it for staff force)
function actions.forceTutorial(src, args)
    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'no such player' } end
    if GetResourceState('bs_tutorial') ~= 'started' then return { ok = false, error = 'bs_tutorial is not running' } end
    local ok, res = pcall(function() return exports.bs_tutorial:ForceTutorial(target) end)
    if not ok or not res then return { ok = false, error = 'could not start it' } end
    return { ok = true }
end

-- Uses bs_medical's single Revive export (same as the interaction dot and console command)
function actions.revive(src, args)
    if GetResourceState('bs_medical') ~= 'started' then
        return { ok = false, error = 'bs_medical is not running' }
    end

    -- No target selected means yourself, like the other actions here.
    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'no such player' } end

    local ok, revived = pcall(function() return exports.bs_medical:Revive(target) end)
    if not ok then return { ok = false, error = 'bs_medical refused the revive' } end
    if not revived then return { ok = false, error = 'that player is not connected' } end

    return { ok = true }
end

-- World tests

-- zhorde only starts a horde when a player is inside a Zones.Spawn zone, otherwise it prints to the server console
function actions.horde(src)
    if GetResourceState('bs_zombies') ~= 'started' then
        return { ok = false, error = 'bs_zombies is not running' }
    end
    ExecuteCommand('zhorde')
    return { ok = true,
             note = 'horde requested - if nobody is inside a spawn zone the server console says so' }
end

-- Runs zclear (see sv_director.lua): removes every live walker and lets the world repopulate from the cells
function actions.zombieReset(src)
    if GetResourceState('bs_zombies') ~= 'started' then
        return { ok = false, error = 'bs_zombies is not running' }
    end

    ExecuteCommand('zclear')

    print(('^2[BS ADMIN]^7 %s cleared every live walker (reseed)')
        :format(GetPlayerName(src) or src))

    return { ok = true, note = 'clear requested - watch the server console for the count' }
end

function actions.openBases(src)
    if GetResourceState('bs_building') ~= 'started' then
        return { ok = false, error = 'bs_building is not running' }
    end
    TriggerClientEvent('bs:building:admin:open', src)
    return { ok = true }
end

function actions.wipeBuilds(src, args)
    if GetResourceState('bs_building') ~= 'started' then
        return { ok = false, error = 'bs_building is not running' }
    end
    ExecuteCommand(('clearbuilds %s'):format(tonumber(args.radius) or 50))
    return { ok = true }
end

-- Switch the zombie spawn mode (node simulation or ring spawner) without a restart
function actions.zspawnmode(src, args)
    if GetResourceState('bs_zombies') ~= 'started' then
        return { ok = false, error = 'bs_zombies is not running' }
    end

    local wanted = tostring(args and args.mode or ''):lower()

    if wanted == 'local' or wanted == 'simulation' then
        local ok = pcall(function()
            return exports.bs_zombies:SetSpawnMode(wanted)
        end)
        if not ok then return { ok = false, error = 'bs_zombies refused the switch' } end

        print(('^2[BS ADMIN]^7 %s switched the zombie spawn mode to %s')
            :format(GetPlayerName(src) or src, wanted))
    end

    local current = 'unknown'
    pcall(function() current = exports.bs_zombies:SpawnMode() end)

    return {
        ok = true,
        mode = current,
        note = ('spawn mode: %s'):format(current),
    }
end

function actions.diagnostics(src)
    local out = {
        players   = 0,
        resources = {},
    }

    for _ in ipairs(GetPlayers()) do out.players = out.players + 1 end

    for _, name in ipairs({ 'bs_core', 'bs_ui', 'bs_inventory', 'bs_skills', 'bs_zombies',
                            'bs_medical', 'bs_building', 'bs_economy', 'bs_interactions',
                            'bs_emotes', 'bs_menu', 'bs_world', 'bs_multichar', 'oxmysql' }) do
        out.resources[#out.resources + 1] = { name = name, state = GetResourceState(name) }
    end

    if GetResourceState('bs_zombies') == 'started' then
        local ok, snap = pcall(function() return exports.bs_zombies:Snapshot() end)
        if ok and type(snap) == 'table' then
            out.walkers   = snap.total
            out.worldSeed = snap.seed
            out.byType    = snap.byType

            -- Who is simulating what
            local hosts = {}
            for host, n in pairs(snap.hosted or {}) do
                hosts[#hosts + 1] = { name = GetPlayerName(host) or host, walkers = n }
            end
            out.hosts = hosts
        end
    end

    if GetResourceState('bs_building') == 'started' then
        local player = exports.bs_core:GetPlayer(src)
        if player then
            local ok, count = pcall(function() return exports.bs_building:Count(player.charId) end)
            out.yourBuilds = ok and count or 0
        end
    end

    return { ok = true, info = out }
end


-- Building tab (F10 > BUILD)


local function buildingUp() return GetResourceState('bs_building') == 'started' end

local function itemLabel(src, item)
    local ok, label = pcall(function() return exports.bs_inventory:ItemLabel(item, src) end)
    return (ok and type(label) == 'string' and label ~= '') and label or item
end

local function costText(src, list)
    local parts = {}
    for _, c in ipairs(list or {}) do parts[#parts + 1] = ('%dx %s'):format(c.amount, itemLabel(src, c.item)) end
    return table.concat(parts, ', ')
end

function actions.buildData(src)
    local out = { ok = true, pieces = {}, recipes = {} }
    if buildingUp() then
        local ok, list = pcall(function() return exports.bs_building:PieceCosts() end)
        for _, p in ipairs(ok and list or {}) do
            out.pieces[#out.pieces + 1] = { id = p.id, label = p.label or p.id, cost = costText(src, p.cost) }
        end
        out.raidAlways = exports.bs_building:RaidAlways()
        out.freeBuild = exports.bs_building:FreeBuildOn(src)
    end
    if GetResourceState('bs_crafting') == 'started' then
        local ok, map = pcall(function() return exports.bs_crafting:Recipes() end)
        for id, r in pairs(ok and map or {}) do
            if type(r) == 'table' and r.result then
                out.recipes[#out.recipes + 1] = { id = id, station = r.station or '', cost = costText(src, r.cost),
                    label = ('%s x%d'):format(itemLabel(src, r.result.item), r.result.amount or 1) }
            end
        end
        table.sort(out.recipes, function(a, b) return a.label < b.label end)
    end
    return out
end

-- Materials for N of a piece, or ingredients for N crafts of a recipe, to self or the selected player
function actions.giveFor(src, args)
    if GetResourceState('bs_inventory') ~= 'started' then return { ok = false, error = 'bs_inventory is not running' } end
    local target = tonumber(args.target) or src
    if not GetPlayerName(target) then return { ok = false, error = 'player not found' } end
    local n = math.max(1, math.min(50, math.floor(tonumber(args.times) or 1)))
    local list
    if args.kind == 'piece' and buildingUp() then
        list = exports.bs_building:CostOf(tostring(args.id))
    elseif args.kind == 'recipe' and GetResourceState('bs_crafting') == 'started' then
        local okr, map = pcall(function() return exports.bs_crafting:Recipes() end)
        local r = okr and type(map) == 'table' and map[tostring(args.id)] or nil
        list = type(r) == 'table' and r.cost or nil
    end
    if type(list) ~= 'table' then return { ok = false, error = Lp(src, 'admin.unknown') } end
    local given, failed = {}, {}
    for _, c in ipairs(list) do
        local total = (tonumber(c.amount) or 1) * n
        if exports.bs_inventory:GiveItem(target, c.item, total) then given[#given + 1] = ('%dx %s'):format(total, c.item)
        else failed[#failed + 1] = c.item end
    end
    guardLog(src, ('giveFor %s %s x%d to %d: %s%s'):format(tostring(args.kind), tostring(args.id), n, target,
        table.concat(given, ', '), #failed > 0 and (' | no room: ' .. table.concat(failed, ', ')) or ''))
    if #given == 0 then return { ok = false, error = Lp(src, 'admin.no_room', { list = table.concat(failed, ', ') }) } end
    local note = Lp(src, 'admin.gave', { list = table.concat(given, ', ') })
    if #failed > 0 then note = note .. ' - ' .. Lp(src, 'admin.no_room', { list = table.concat(failed, ', ') }) end
    return { ok = true, note = note }
end

function actions.raidAlways(src)
    if not buildingUp() then return { ok = false, error = 'bs_building is not running' } end
    local on = exports.bs_building:SetRaidAlways(not exports.bs_building:RaidAlways(), src)
    guardLog(src, 'raids always open ' .. (on and 'on' or 'off'))
    return { ok = true, on = on, note = Lp(src, on and 'admin.raid_on' or 'admin.raid_off') }
end

function actions.freeBuild(src)
    if not buildingUp() then return { ok = false, error = 'bs_building is not running' } end
    local on = exports.bs_building:SetFreeBuild(src, not exports.bs_building:FreeBuildOn(src))
    guardLog(src, 'free build ' .. (on and 'on' or 'off'))
    return { ok = true, on = on, note = Lp(src, on and 'admin.free_on' or 'admin.free_off') }
end

function actions.resetDecayAll(src)
    if not buildingUp() then return { ok = false, error = 'bs_building is not running' } end
    local n = exports.bs_building:ResetDecayAll(src)
    guardLog(src, ('reset decay on %d bases'):format(n or 0))
    return { ok = true, note = Lp(src, 'admin.decay_reset', { n = n or 0 }) }
end

function actions.finishFrames(src, args)
    if not buildingUp() then return { ok = false, error = 'bs_building is not running' } end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'no ped' } end
    local c = GetEntityCoords(ped)
    local radius = math.max(1, math.min(200, tonumber(args.radius) or 25))
    local n = exports.bs_building:FinishInRadius(c.x, c.y, c.z, radius, src)
    guardLog(src, ('finished %d frames within %dm'):format(n or 0, radius))
    return { ok = true, note = Lp(src, 'admin.finished', { n = n or 0 }) }
end

-- Warns at resource start if Admin.Settings.superAdminOnly names an action that does not exist
CreateThread(function()
    for _, name in ipairs(Admin.Settings.superAdminOnly) do
        if not actions[name] then
            print(('^1[BS ADMIN]^7 config error: superAdminOnly lists "%s" but no such action exists in sv_main.lua - this gate is doing NOTHING for that name.'):format(name))
        end
    end
end)

-- Lookups that change nothing, so they are not written to bs_guard_log.
local READ_ONLY = {
    items = true, perks = true, skills = true, classes = true, buildData = true, diagnostics = true,
    playerInfo = true, testServerState = true, playerLogs = true, serverStats = true, worldState = true, invView = true,
    eventList = true, bans = true, factionList = true, storedCars = true, zspawnmode = true, powerList = true, pumpList = true,
}
-- These write their own, more detailed line.
local SELF_LOGGED = { giveitem = true, giveFor = true, raidAlways = true, freeBuild = true, resetDecayAll = true, finishFrames = true, worldCarsReset = true }

-- One line per staff action
local function describe(action, args)
    local parts = { action }
    for k, v in pairs(args or {}) do
        if k ~= 'target' and (type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean') then
            parts[#parts + 1] = ('%s=%s'):format(k, tostring(v):sub(1, 80))
        end
    end
    local t = tonumber(args and args.target)
    if t and GetPlayerName(t) then
        parts[#parts + 1] = ('| target %s %s'):format(GetPlayerName(t), GetPlayerIdentifierByType(t, 'license') or '?')
    end
    return table.concat(parts, ' ')
end

-- Shared by the F10 callback and the chat commands (sv_commands.lua). src 0 is the server console.
local function run(src, action, args)
    if src ~= 0 and not mayUse(src, action) then
        return { ok = false, error = 'not allowed' }
    end

    local fn = actions[action]
    if not fn then return { ok = false, error = 'unknown action' } end

    args = type(args) == 'table' and args or {}
    local ok, result = pcall(fn, src, args)
    if not ok then
        print(('^1[BS ADMIN]^7 %s failed: %s'):format(action, result))
        return { ok = false, error = 'action errored' }
    end

    if src ~= 0 then audit(src, action, args.target and ('target=' .. tostring(args.target)) or '') end
    if type(result) == 'table' and result.ok ~= false and not READ_ONLY[action] and not SELF_LOGGED[action] then
        guardLog(src, describe(action, args))
    end
    return result
end

BSB.RegisterCallback('admin:action', function(src, action, args)
    return run(src, action, args)
end)

-- Same Lua state as sv_staff.lua and sv_commands.lua, which add actions and chat commands.
BSAdmin = {
    actions = actions, run = run, isAdmin = isAdmin, isSuperAdmin = isSuperAdmin,
    guardLog = guardLog, world = world,
}

exports.bs_core:RegisterModule('admin', { side = 'server', version = '0.1.0' })

-- Boot check: every data-server name in index.html must have a handler

CreateThread(function()
    Wait(5000)   -- let every action definition in this file finish loading

    local html = LoadResourceFile(GetCurrentResourceName(), 'html/index.html')
    if not html then
        print('^3[BS ADMIN]^7 could not read html/index.html to verify the menu buttons.')
        return
    end

    local missing, seen, checked = {}, {}, 0
    for name in html:gmatch('data%-server="([%w_]+)"') do
        if not seen[name] then
            seen[name] = true
            checked = checked + 1
            if type(actions[name]) ~= 'function' then
                missing[#missing + 1] = name
            end
        end
    end

    if #missing > 0 then
        print(('^1[BS ADMIN]^7 %d MENU BUTTON(S) HAVE NO HANDLER and will silently do nothing when pressed: %s')
            :format(#missing, table.concat(missing, ', ')))
        print('^1[BS ADMIN]^7 Either add the action to server/sv_main.lua or take the button out of html/index.html.')
    else
        print(('^2[BS ADMIN]^7 all %d menu actions resolve.'):format(checked))
    end
end)
