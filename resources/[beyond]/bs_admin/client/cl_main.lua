-- bs_admin - client menu

local open = false
local godmode = false
local zombieGodmode = false   -- separate from godmode: walkers do not perceive you
local invisible = false
local coordsOverlay = false
local propIdOverlay = false
local guardAlerts = false    -- guard toasts for this admin, saved with the other toggles
local advancedMode = false   -- F10 Simple / Advanced view, remembered per account through sv_prefs
local isAdmin = false

local function send(p) SendNUIMessage(p) end

local function refreshRights()
    local info = BSB.Await('admin:whoami', 8000)
    isAdmin = info and info.admin or false
    send({ action = 'rights', admin = isAdmin, superadmin = info and info.superadmin or false })
    if isAdmin then AdminAddSuggestions() end
    return isAdmin
end

-- Chat hints for the staff commands, only on staff clients.
local suggested = false
function AdminAddSuggestions()
    if suggested then return end
    suggested = true
    local list = {
        { '/dv', 'admin.s.dv', { { name = 'radius', help = 'm' } } },
        { '/dz', 'admin.s.dz', { { name = 'radius', help = 'm (50)' } } },
        { '/ann', 'admin.s.ann', { { name = '-t Title', help = '' }, { name = 'text', help = '' } } },
        { '/announce', 'admin.s.ann', { { name = '-t Title', help = '' }, { name = 'text', help = '' } } },
        { '/weather', 'admin.s.weather', { { name = 'type', help = table.concat(Admin.Weather, ' ') } } },
        { '/time', 'admin.s.time', { { name = 'hour', help = '0-23' }, { name = 'minute', help = '0-59' } } },
        { '/freezetime', 'admin.s.freezetime', { { name = 'on|off', help = '' } } },
        { '/freezeweather', 'admin.s.freezeweather', { { name = 'on|off', help = '' } } },
        { '/blackout', 'admin.s.blackout', { { name = 'on|off', help = '' } } },
        { '/giveitem', 'admin.s.giveitem', { { name = 'id|me', help = '' }, { name = 'item', help = '' }, { name = 'amount', help = '' } } },
        { '/givemoney', 'admin.s.givemoney', { { name = 'id|me', help = '' }, { name = 'amount', help = '' }, { name = 'cash|bank', help = '' } } },
        { '/car', 'admin.s.car', { { name = 'model', help = '' } } },
        { '/heal', 'admin.s.heal', { { name = 'id', help = '' } } },
        { '/tpc', 'admin.s.tpc', { { name = 'x', help = '' }, { name = 'y', help = '' }, { name = 'z', help = 'optional' } } },
    }
    for _, s in ipairs(list) do TriggerEvent('chat:addSuggestion', s[1], L(s[2]), s[3]) end
end

-- Weapon list joined with the attachments that fit each one (from bs_weapons), so staff can give a whole kit in one click
local function weaponsWithParts()
    local out = {}

    local haveWeapons = GetResourceState('bs_weapons') == 'started'

    for _, group in ipairs(Admin.Weapons) do
        local items = {}

        for _, w in ipairs(group.items) do
            local parts = {}
            if haveWeapons then
                local ok, list = pcall(function()
                    return exports.bs_weapons:AttachmentsFor(w.model)
                end)
                if ok and type(list) == 'table' then parts = list end
            end

            items[#items + 1] = {
                label = w.label, model = w.model, ammo = w.ammo,
                attachments = parts,
            }
        end

        out[#out + 1] = { label = group.label, items = items }
    end

    return out
end

local function openMenu()
    if open then return end
    if not refreshRights() then return end

    local players = BSB.Await('admin:players', 8000) or {}

    open = true
    TriggerEvent('bs:ui:opened', 'admin')
    send({
        action    = 'open',
        players   = players,
        -- Grouped { label, items } sections
        vehicles  = Admin.Vehicles,
        weapons   = weaponsWithParts(),
        weather   = Admin.Weather,
        times     = Admin.TimePresets,
        skills    = Admin.Skills,
        mapTeleports = AdminMapTeleports or {},
        -- Spawn-a-zombie rows, read from the bs_zombies config
        zombieTypes = (function()
            if GetResourceState('bs_zombies') ~= 'started' then return {} end
            local ok, list = pcall(function() return exports.bs_zombies:Types() end)
            return (ok and list) or {}
        end)(),
        state     = { godmode = godmode, zombieGodmode = zombieGodmode, noclip = Noclip.active,
                      invisible = invisible, coords = coordsOverlay, propid = propIdOverlay,
                      advanced = advancedMode, guardAlerts = guardAlerts },
    })
    SetNuiFocus(true, true)

    -- Only the game's own blur works in NUI: backdrop-filter has nothing to sample over a transparent page
    TriggerScreenblurFadeIn(300)
end

local function closeMenu()
    if not open then return end
    open = false
    send({ action = 'close' })
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(250)
    TriggerEvent('bs:ui:closed', 'admin')
end

-- The key toggles: pressing F10 again closes the menu.
RegisterCommand(Admin.Settings.openCommand, function()
    if open then
        closeMenu()
    else
        CreateThread(openMenu)   -- openMenu awaits, so it needs its own thread
    end
end, false)
RegisterKeyMapping(Admin.Settings.openCommand, 'Open the staff menu', 'keyboard', 'F10')

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)

-- Threaded because BSB.Await yields.
RegisterNUICallback('factionsAdmin', function(_, cb)
    CreateThread(function()
        cb(BSB.Await('factions:admin:list', 8000) or { ok = false, error = 'bs_factions did not answer' })
    end)
end)

RegisterNUICallback('factionsAdminDelete', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('factions:admin:delete', 8000, data.id) or { ok = false, error = 'bs_factions did not answer' })
    end)
end)

RegisterNUICallback('factionsAdminReset', function(_, cb)
    CreateThread(function()
        cb(BSB.Await('factions:admin:reset', 8000) or { ok = false, error = 'bs_factions did not answer' })
    end)
end)
-- SANCTIONS tab: thin pass-through to bs_faction_bases (server re-checks the ace).
local SanctionCallbacks = {
    ['sanctions:templates']=true, ['sanctions:list']=true, ['sanctions:issue']=true, ['sanctions:lift']=true,
    ['jail:get']=true, ['jail:setOrigin']=true, ['jail:setExit']=true, ['jail:addCell']=true, ['jail:removeCell']=true, ['jail:release']=true,
}
RegisterNUICallback('sanctions', function(data, cb)
    local name = type(data) == 'table' and data.cb or nil
    if not SanctionCallbacks[name] then cb({ ok = false, error = 'unknown action' }); return end
    CreateThread(function()
        cb(BSB.Await(name, 10000, type(data.args) == 'table' and data.args or {}) or { ok = false, error = 'bs_faction_bases did not answer' })
    end)
end)
-- Guard logs viewer: thin pass-through to bs_guard (server re-checks staff).
local GuardCallbacks = { ['guard:list']=true, ['guard:page']=true, ['guard:goto']=true, ['guard:spectate']=true }
RegisterNUICallback('guard', function(data, cb)
    local name = type(data) == 'table' and data.cb or nil
    if not GuardCallbacks[name] then cb({ ok = false, error = 'unknown action' }); return end
    if name == 'guard:spectate' then closeMenu() end
    CreateThread(function()
        cb(BSB.Await(name, 10000, type(data.args) == 'table' and data.args or {}) or { ok = false, error = 'bs_guard did not answer' })
    end)
end)
RegisterNUICallback('guardStop', function(_, cb)
    ExecuteCommand('guardspec')
    cb({ ok = true })
end)
-- live refresh of the Guard logs viewer when bs_guard reports a new detection
RegisterNetEvent('bs_guard:detection', function()
    SendNUIMessage({ action = 'guardDetection' })
end)
RegisterNUICallback('refreshPlayers', function(_, cb)
    CreateThread(function() cb(BSB.Await('admin:players', 8000) or {}) end)
end)

-- Local-only actions (nothing the server needs to agree to)

-- Spawns one walker in front of you through the real pipeline
-- @param feeding boolean|nil spawn it already crouched over a meal
-- @param typeId string|nil archetype, defaults to 'walker'
-- typeId is not validated here: the zombies:force callback in sv_registry.lua falls back to
function AdminForceZombie(feeding, typeId)
    local ped = PlayerPedId()
    local at  = GetEntityCoords(ped)
    local h   = GetEntityHeading(ped)
    local rad = math.rad(h)

    -- 5 m normally, 22 m for a feeder
    local distance = 5.0
    if feeding then
        local ok, cfg = pcall(function() return exports.bs_zombies:FeedingConfig() end)
        distance = (ok and cfg and cfg.debugDistance) or 22.0
    end

    local x = at.x - math.sin(rad) * distance
    local y = at.y + math.cos(rad) * distance

    -- Ground the point first: request collision, then probe above the player.
    RequestCollisionAtCoord(x, y, at.z)
    local gz
    for _, from in ipairs({ at.z + 30.0, at.z + 10.0, at.z + 2.0, at.z - 10.0 }) do
        local t = GetGameTimer() + 600
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do
            RequestCollisionAtCoord(x, y, at.z); Wait(50)
        end
        local ok, z = GetGroundZFor_3dCoord(x, y, from, false)
        if ok and math.abs(z - at.z) < 40.0 then gz = z; break end
    end
    local z = gz or (at.z - 1.0)

    local result = BSB.Await('zombies:force', 8000, x, y, (h + 180.0) % 360.0,
                             typeId or 'walker', feeding == true, gz and (gz + 0.0) or nil)
    if not result or not result.ok then
        return { error = (result and result.error) or 'no answer from the registry' }
    end

    -- Check that a ped actually appeared: the server saying "spawned" only means a row exists
    local waited, arrived = 0, false

    while waited < 6000 do
        Wait(250); waited = waited + 250
        pcall(function() arrived = exports.bs_zombies:HasWalker(result.id) end)
        if arrived then break end
    end

    -- Notified, not returned: the menu closes and the wait can run up to 6 s, so there is nothing left to write the answer into
    if arrived then
        local drawn = 0
        pcall(function() drawn = exports.bs_zombies:Count() or 0 end)

        -- A ped can exist and collide while rendering nothing
        local vis, alpha = 'unknown', -1
        pcall(function()
            local live = exports.bs_zombies:Live()
            local entry = live and live[result.id]
            if entry and entry.ped and DoesEntityExist(entry.ped) then
                vis = tostring(IsEntityVisible(entry.ped))
                alpha = GetEntityAlpha(entry.ped)
            end
        end)

        TriggerEvent('bs:ui:notify', {
            type = 'success', duration = 7000,
            message = ('Walker %d DREW after %dms (%s). visible=%s alpha=%d. %d on this client.')
                :format(result.id, waited, tostring(result.model), vis, alpha, drawn),
        })
        return { ok = true }
    end

    -- The failure this button exists to catch: the server has the record but this client never built the ped
    TriggerEvent('bs:ui:notify', {
        type = 'error', duration = 9000,
        message = ('Record %d exists on the server but NO ped appeared in %ds - %s')
            :format(result.id, math.floor(waited / 1000), AdminZSpectateDiagnose()),
    })
    return { ok = true }
end

local localActions = {
    -- Simple / Advanced switch
    advanced = function()
        advancedMode = not advancedMode
        send({ action = 'mode', advanced = advancedMode })
        return { advanced = advancedMode }
    end,

    guardAlerts = function()
        guardAlerts = not guardAlerts
        return { guardAlerts = guardAlerts }
    end,

    noclip = function()
        return { noclip = Noclip.Toggle() }
    end,

    -- Two separate godmodes
    godmode = function()
        godmode = not godmode
        SetPlayerInvincible(PlayerId(), godmode)
        SetEntityInvincible(PlayerPedId(), godmode)
        return { godmode = godmode }
    end,

    zombieGodmode = function()
        zombieGodmode = not zombieGodmode
        LocalPlayer.state:set('bsZombieGodmode', zombieGodmode, true)
        return { zombieGodmode = zombieGodmode }
    end,

    tpWaypoint = function()
        local blip = GetFirstBlipInfoId(8)
        if not DoesBlipExist(blip) then return { error = 'no waypoint set' } end

        local coords = GetBlipInfoIdCoord(blip)
        local ped = PlayerPedId()

        -- Probe downwards for ground; the Z from a blip is always 0.
        for z = 1000, 0, -25 do
            SetEntityCoordsNoOffset(ped, coords.x, coords.y, z + 0.0, false, false, false)
            Wait(20)
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, z + 0.0, false)
            if found then
                SetEntityCoordsNoOffset(ped, coords.x, coords.y, groundZ + 1.0, false, false, false)
                return { ok = true }
            end
        end
        return { error = 'could not find ground there' }
    end,

    mapTeleport = function(data)
        if not isAdmin then return { error = 'admin access required' } end
        local x = tonumber(data and data.x)
        local y = tonumber(data and data.y)
        local z = tonumber(data and data.z)
        if not x or not y or not z or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then
            return { error = 'invalid map destination' }
        end

        local ped = PlayerPedId()
        local entity = ped
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then entity = vehicle end

        DoScreenFadeOut(180)
        while not IsScreenFadedOut() do Wait(0) end
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoordsNoOffset(entity, x + 0.0, y + 0.0, z + 1.5, false, false, false)
        SetFocusPosAndVel(x + 0.0, y + 0.0, z + 1.5, 0.0, 0.0, 0.0)

        local deadline = GetGameTimer() + 2500
        while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do Wait(50) end
        ClearFocus()
        DoScreenFadeIn(220)
        return { ok = true, note = 'map teleport complete' }
    end,
    invisible = function()
        invisible = not invisible
        SetEntityVisible(PlayerPedId(), not invisible, false)
        return { invisible = invisible }
    end,

    -- Permanent readout of where you are standing. Bare text, no panel, same as the HUD.
    coords = function()
        coordsOverlay = not coordsOverlay
        return { coords = coordsOverlay }
    end,

    -- Prop id toggle (admin only). bs_interactions already raycasts every frame for its ALT-interact
    propId = function()
        propIdOverlay = not propIdOverlay
        return { propid = propIdOverlay }
    end,

    copyCoords = function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local h = GetEntityHeading(ped)
        local line = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, h)
        print(('^5[BS ADMIN]^7 %s'):format(line))
        return { ok = true, text = line, x = c.x, y = c.y, z = c.z, h = h, note = 'printed to F8' }
    end,

    -- What is around you. The ped count is usually what matters when the frame rate drops.
    entities = function()
        local peds, vehicles, objects, zombies, built = 0, 0, 0, 0, 0

        for _, ped in ipairs(GetGamePool('CPed')) do
            peds = peds + 1
            local state = Entity(ped).state
            if state and state.bsZombie then zombies = zombies + 1 end
        end
        for _ in ipairs(GetGamePool('CVehicle')) do vehicles = vehicles + 1 end
        for _, obj in ipairs(GetGamePool('CObject')) do
            objects = objects + 1
            local state = Entity(obj).state
            if state and state.bsBuilt then built = built + 1 end
        end

        return { ok = true, text = ('peds        %d (walkers %d)\nvehicles    %d\nobjects     %d (built %d)')
            :format(peds, zombies, vehicles, objects, built) }
    end,

    -- The zombie simulation from this client's point of view.
    zombieInfo = function()
        if GetResourceState('bs_zombies') ~= 'started' then
            return { error = 'bs_zombies is not running' }
        end

        local count  = exports.bs_zombies:Count()
        local live   = exports.bs_zombies:Live()
        local horde  = exports.bs_zombies:HordeActive()
        local hosted = exports.bs_zombies:HostedCount()

        local byType, byState = {}, {}
        for _, entry in pairs(live) do
            byType[entry.typeId] = (byType[entry.typeId] or 0) + 1
            byState[entry.state] = (byState[entry.state] or 0) + 1
        end

        local lines = {
            ('walkers on screen: %d%s'):format(count, horde and '  (HORDE ACTIVE)' or ''),
            ('this client is thinking for: %d (the rest are steered by the server)')
                :format(hosted),
        }
        for typeId, n in pairs(byType) do lines[#lines + 1] = ('  %-10s %d'):format(typeId, n) end
        lines[#lines + 1] = 'states:'
        for state, n in pairs(byState) do lines[#lines + 1] = ('  %-10s %d'):format(state, n) end

        return { ok = true, text = table.concat(lines, '\n') }
    end,

    -- Car tuning menu
    tuningRead = function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return { error = 'not in a vehicle' } end

        local plate = GetVehicleNumberPlateText(veh)
        plate = plate and plate:gsub('%s+', ''):upper() or ''
        if plate == '' then return { error = 'this car has no plate' } end

        local mods = {}
        for modType = 0, 49 do
            local ok, index = pcall(GetVehicleMod, veh, modType)
            if ok and index and index > -1 then mods[tostring(modType)] = index end
        end

        local result = BSB.Await('vehicles:tuningSave', 8000, plate, mods)
        if not result or not result.ok then
            return { error = (result and result.error) or 'could not save the tune' }
        end

        local count = 0
        for _ in pairs(result.mods or {}) do count = count + 1 end
        return { ok = true, text = ('Saved %d mod slot%s for %s.\nThis tune now applies every time the car is restored.')
            :format(count, count == 1 and '' or 's', plate) }
    end,

    tuningApply = function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return { error = 'not in a vehicle' } end

        local plate = GetVehicleNumberPlateText(veh)
        plate = plate and plate:gsub('%s+', ''):upper() or ''
        if plate == '' then return { error = 'this car has no plate' } end

        local result = BSB.Await('vehicles:tuningRead', 8000, plate)
        if not result or not result.ok then
            return { error = (result and result.error) or 'no saved tune for this car' }
        end

        local mods = result.mods or {}
        if not next(mods) then
            return { error = 'nothing saved for this car yet - use "Read this car\'s tune" first' }
        end

        SetVehicleModKit(veh, 0)
        for modType, index in pairs(mods) do
            pcall(SetVehicleMod, veh, tonumber(modType), tonumber(index), false)
        end

        local count = 0
        for _ in pairs(mods) do count = count + 1 end
        return { ok = true, note = ('Applied %d saved mod slot%s.'):format(count, count == 1 and '' or 's') }
    end,

    -- Same server path as /repair: admin-checked, logged, saved wear reset too.
    repairVehicle = function()
        return AdminRepairLooked()
    end,

    -- Same server path as /dv, so an owned car is stored rather than respawned or lost.
    deleteVehicle = function(data)
        local radius = tonumber(data and data.radius)
        local payload
        if radius and radius > 0 then
            payload = { radius = radius }
        else
            local veh = AdminLookedAtVehicle()
            if veh == 0 then return { error = L('admin.c.dv_none') } end
            if not NetworkGetEntityIsNetworked(veh) then
                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
                return { ok = true }
            end
            payload = { netId = NetworkGetNetworkIdFromEntity(veh) }
        end
        local r = BSB.Await('admin:action', 10000, 'deleteVehicles', payload)
        if not r or not r.ok then return { error = (r and r.error) or 'denied' } end
        return { ok = true, note = L('admin.c.dv_done', { n = r.count or 0, s = r.stored or 0, k = r.skipped or 0 }) }
    end,

    -- Debug only: breaks the car you are driving down after a delay, to test failure symptoms without waiting for wear
    failVehicle = function(data)
        if GetVehiclePedIsIn(PlayerPedId(), false) == 0 then
            return { error = 'not in a vehicle' }
        end
        if GetResourceState('bs_vehicles') ~= 'started' then
            return { error = 'bs_vehicles is not running' }
        end

        local seconds = math.max(1, math.min(tonumber(data and data.seconds) or 10, 60))
        local ok = exports.bs_vehicles:ScheduleFailure(seconds)
        if not ok then return { error = 'could not schedule it' } end

        return { ok = true, text = ('This car will break down in %ds.'):format(seconds) }
    end,

    -- Cosmetic/informational only, see bs_zombies/client/cl_healthbar.lua
    tpNearestZombie = function()
        local result = BSB.Await('zombies:nearest', 8000)
        if not result or not result.ok then
            return { error = (result and result.error) or 'no answer from the registry' }
        end

        local ped = PlayerPedId()
        local at  = GetEntityCoords(ped)

        -- Prefer a walker whose ped exists here, is visible, alive and sane in height
        pcall(function()
            local live = exports.bs_zombies:Live()
            for _, zid in ipairs(result.ids or {}) do
                local e = live and live[zid]
                local zp = e and e.ped
                if zp and DoesEntityExist(zp) and IsEntityVisible(zp) and not IsEntityDead(zp) then
                    local c = GetEntityCoords(zp)
                    if c.z > -50.0 and c.z < 1500.0 and math.abs(c.z - at.z) < 150.0 then
                        result.x, result.y, result.z, result.grounded = c.x, c.y, c.z, true
                        result.id = zid
                        break
                    end
                end
            end
        end)

        -- Approach from where we already are
        local dx, dy = at.x - result.x, at.y - result.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.01 then dx, dy, len = 1.0, 0.0, 1.0 end

        local tx = result.x + (dx / len) * 5.0
        local ty = result.y + (dy / len) * 5.0

        -- The record's Z is 0.0 until a host reports real ground (the server has no collision)
        if result.grounded then
            SetEntityCoordsNoOffset(ped, tx, ty, result.z + 1.0, false, false, false)
            Wait(150)
        end

        local found, groundZ = GetGroundZFor_3dCoord(tx, ty, (result.z or 0.0) + 3.0, false)
        if not found then
            for z = 1000, 0, -25 do
                SetEntityCoordsNoOffset(ped, tx, ty, z + 0.0, false, false, false)
                Wait(20)
                found, groundZ = GetGroundZFor_3dCoord(tx, ty, z + 0.0, false)
                if found then break end
            end
        end

        if not found then
            return { error = ('found one %.0fm away but no ground under it'):format(result.distance or 0) }
        end

        SetEntityCoordsNoOffset(ped, tx, ty, groundZ + 1.0, false, false, false)

        -- Face it, so it is on screen when the teleport lands.
        SetEntityHeading(ped, GetHeadingFromVector_2d(result.x - tx, result.y - ty))

        -- Notified rather than returned: this button closes the menu, so the panel's debug box is hidden.
        TriggerEvent('bs:ui:notify', {
            type = 'success',
            duration = 4200,
            message = ('%s (%s) %d/%d HP, %.0fm away. %d walker(s) within 100m.')
                :format(result.typeId or 'walker', result.state or 'idle',
                        result.hp or 0, result.maxHp or 0, result.distance or 0,
                        result.near or 0),
        })

        -- Also check whether any walker exists here
        CreateThread(function()
            Wait(2500)          -- long enough for the queue to drain

            local drawn = 0
            pcall(function() drawn = exports.bs_zombies:Count() or 0 end)

            if drawn == 0 and (result.near or 0) > 0 then
                TriggerEvent('bs:ui:notify', {
                    type = 'error', duration = 7000,
                    message = AdminZSpectateDiagnose(),
                })
            end
        end)

        return { ok = true }
    end,

    -- The body lives above the table as AdminForceZombie so /zforce can call the same code.
    forceZombie = function() return AdminForceZombie(false) end,

    -- One action for every archetype, driven by the config
    forceZombieType = function(data)
        return AdminForceZombie(false, data and data.type)
    end,

    -- Same path, but asks for one that is already eating
    forceEatingZombie = function() return AdminForceZombie(true) end,

    -- Toggles: pressing it while the camera is up stops it, same as ESC.
    spectateNearestZombie = function()
        local result = AdminZSpectateNearest()
        if result.error then return result end

        if result.text then
            TriggerEvent('bs:ui:notify',
                { type = 'info', message = result.text, duration = 4200 })
        end
        return { ok = true }
    end,

    zombieHealthbars = function()
        if GetResourceState('bs_zombies') ~= 'started' then
            return { error = 'bs_zombies is not running' }
        end
        local on = not exports.bs_zombies:HealthBarsVisible()
        local applied = exports.bs_zombies:SetHealthBarsVisible(on)
        if not applied then return { error = 'could not toggle that' } end
        return { zombiehp = on }
    end,
}

-- Remembering the toggles: they live in this file's locals, so a relog or resource restart reset them

-- Everything worth remembering as one table, read from the same locals the menu uses.
local function currentToggles()
    return {
        godmode       = godmode,
        zombieGodmode = zombieGodmode,
        invisible     = invisible,
        coords        = coordsOverlay,
        propid        = propIdOverlay,
        advanced      = advancedMode,
        guardAlerts   = guardAlerts,
    }
end

-- Sent to the server after every toggle. Whole state, not a delta (five booleans).
local function reportToggles()
    TriggerServerEvent('bs:admin:prefs:save', currentToggles())
end

-- Each toggle is applied by calling its own action, not by repeating the natives, so the logic stays in one place
RegisterNetEvent('bs:admin:prefs:apply', function(saved)
    if type(saved) ~= 'table' then return end

    CreateThread(function()
        -- Wait for a real ped
        local waited = 0
        while (PlayerPedId() == 0 or not DoesEntityExist(PlayerPedId())) and waited < 15000 do
            Wait(250)
            waited = waited + 250
        end
        if waited >= 15000 then return end

        local now = currentToggles()
        local applied = {}

        for key, wanted in pairs(saved) do
            -- Overlays are session only, even if an old saved row still has them on.
            if key ~= 'coords' and key ~= 'propid' and type(wanted) == 'boolean' and now[key] ~= nil and now[key] ~= wanted then
                -- Action names don't always match the state keys (propid is toggled by propId), so they are mapped explicitly
                local action = (key == 'propid') and 'propId' or key
                local fn = localActions[action]
                if fn then
                    pcall(fn)
                    -- the view mode is not worth a toast
                    if key ~= 'advanced' and key ~= 'guardAlerts' then applied[#applied + 1] = key end
                end
            end
        end

        -- Said out loud: spawning with godmode already on and no hint why would look like a bug when damage does nothing
        if #applied > 0 then
            TriggerEvent('bs:ui:notify', { type = 'info', duration = 5000,
                message = ('Staff toggles restored: %s'):format(table.concat(applied, ', ')) })
        end
    end)
end)

-- Requested by the client once loaded, since only it knows when a real ped exists
local function askForPrefs()
    TriggerServerEvent('bs:admin:prefs:request')
end

AddEventHandler('bs:hook:player:spawned', function()
    CreateThread(function()
        Wait(2500)
        askForPrefs()
        Wait(5000)
        askForPrefs()
    end)
end)

-- Also on a plain resource restart, which does not re-fire player:spawned.
CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(500) end
    Wait(3000)
    askForPrefs()
end)

RegisterNUICallback('local', function(data, cb)
    local fn = localActions[data.action]
    if not fn then return cb({ error = 'unknown action' }) end
    -- tpWaypoint probes for ground with Wait(), so this is threaded too.
    CreateThread(function()
        local result = fn(data) or { ok = true }

        -- Reported after every local action
        reportToggles()

        cb(result)
    end)
end)

-- Server-checked actions

RegisterNUICallback('server', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('admin:action', 10000, data.action, data.args or {})
        cb(result or { ok = false, error = 'no response' })
    end)
end)

-- Sector callbacks are answered by bs_zombies
RegisterNUICallback('sectorsList', function(_, cb)
    CreateThread(function()
        local result = BSB.Await('zombies:sectors:list', 8000)
        cb(result or { ok = false, error = 'bs_zombies did not answer' })
    end)
end)

RegisterNUICallback('sectorSet', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('zombies:sectors:set', 8000,
            data.key, data.field, data.value)
        cb(result or { ok = false, error = 'bs_zombies did not answer' })
    end)
end)

RegisterNUICallback('sectorClearDebt', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('zombies:sectors:cleardebt', 8000, data.key)
        cb(result or { ok = false, error = 'bs_zombies did not answer' })
    end)
end)

-- Spawning a vehicle needs the model loaded client-side; the server still authorises it first.
RegisterNUICallback('spawnVehicle', function(data, cb)
  CreateThread(function()
    local allowed = BSB.Await('admin:action', 10000, 'spawnVehicle', { model = data.model })
    if not allowed or not allowed.ok then
        return cb(allowed or { ok = false, error = 'denied' })
    end

    local hash = GetHashKey(data.model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return cb({ ok = false, error = 'unknown vehicle model' })
    end

    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 8000 do Wait(10); waited = waited + 10 end
    if not HasModelLoaded(hash) then return cb({ ok = false, error = 'model would not load' }) end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, veh, -1)
    -- Every spawn gets its own plate, generated and reserved by the server
    SetVehicleNumberPlateText(veh, allowed.plate or 'BS000000')
    SetModelAsNoLongerNeeded(hash)

    cb({ ok = true })
  end)
end)

-- Weapons go into the inventory, not straight into the ped's hands
RegisterNUICallback('giveWeapon', function(data, cb)
    CreateThread(function()
        -- The server puts the weapon in the bag and nothing else (see actions.giveweapon)
        local result = BSB.Await('admin:action', 10000, 'giveweapon', { model = data.model })

        -- Report what actually happened, including ammo
        if result and result.ok then
            local message = 'Added to your inventory.'

            if result.rounds and result.rounds > 0 then
                message = ('Added to your inventory, loaded with %d.'):format(result.rounds)
            end

            TriggerEvent('bs:ui:notify', {
                type = 'success', message = message, duration = 2400,
            })

            -- Separate warmer-coloured line, since a failure is a different fact from the success.
            if result.note then
                TriggerEvent('bs:ui:notify', {
                    type = 'warn', message = result.note, duration = 3600,
                })
            end
        end

        cb(result or { ok = false, error = 'no response' })
    end)
end)

-- ESX-style chat commands (/car, /dv, /heal), admin only

local function notifyLocal(kind, message)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = 3200 })
end

RegisterCommand('car', function(_, args)
    local model = args[1]
    if not model then return notifyLocal('warn', 'Usage: /car <model>') end

    CreateThread(function()
        local allowed = BSB.Await('admin:action', 10000, 'spawnVehicle', { model = model })
        if not allowed or not allowed.ok then
            return notifyLocal('warn', (allowed and allowed.error) or 'Not allowed.')
        end

        local hash = GetHashKey(model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            return notifyLocal('warn', 'Unknown vehicle model.')
        end

        if not HasModelLoaded(hash) then RequestModel(hash) end
        local waited = 0
        while not HasModelLoaded(hash) and waited < 8000 do Wait(10); waited = waited + 10 end
        if not HasModelLoaded(hash) then return notifyLocal('warn', 'Model would not load.') end

        local ped = PlayerPedId()
        local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        SetPedIntoVehicle(ped, veh, -1)
        SetVehicleNumberPlateText(veh, allowed.plate or 'BS000000')
        SetModelAsNoLongerNeeded(hash)
    end)
end, false)

-- /devcar <model> - spawns a car like the world would: its own generated plate and DB row, no key in your pocket
RegisterCommand('devcar', function(_, args)
    local model = args[1]
    if not model then return notifyLocal('warn', 'Usage: /devcar <model>') end

    CreateThread(function()
        local allowed = BSB.Await('admin:action', 10000, 'devcar', { model = model })
        if not allowed or not allowed.ok then
            return notifyLocal('warn', (allowed and allowed.error) or 'Not allowed.')
        end

        local hash = GetHashKey(model)
        if not HasModelLoaded(hash) then RequestModel(hash) end
        local waited = 0
        while not HasModelLoaded(hash) and waited < 8000 do Wait(10); waited = waited + 10 end
        if not HasModelLoaded(hash) then return notifyLocal('warn', 'Model would not load.') end

        local ped = PlayerPedId()
        local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 0.0)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        SetVehicleNumberPlateText(veh, allowed.plate or 'BS000000')
        SetVehicleOnGroundProperly(veh)
        SetModelAsNoLongerNeeded(hash)
        notifyLocal('success', ('Dropped a %s - plate %s, unclaimed.'):format(model, allowed.plate or '?'))
    end)
end, false)

-- The car you sit in, else the one under the crosshair (12 m), else one touching you.
function AdminLookedAtVehicle()
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 then return inside end

    local from = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local n = math.abs(math.cos(rx))
    local to = from + vector3(-math.sin(rz) * n, math.cos(rz) * n, math.sin(rx)) * 14.0
    local probe = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 3, ped, 7)
    local status, hit, _, _, entity = GetShapeTestResult(probe)
    local waited = 0
    while status == 1 and waited < 20 do
        Wait(0); waited = waited + 1
        status, hit, _, _, entity = GetShapeTestResult(probe)
    end
    if (hit == 1 or hit == true) and entity and entity ~= 0 and GetEntityType(entity) == 2 then return entity end

    local at, best, bestDist = GetEntityCoords(ped), 0, 4.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(at - GetEntityCoords(v))
        if d < bestDist then best, bestDist = v, d end
    end
    return best
end

-- /dv [radius]
RegisterCommand('dv', function(_, args)
    CreateThread(function()
        local radius = tonumber(args[1])
        local payload

        if radius and radius > 0 then
            payload = { radius = radius }
        else
            local veh = AdminLookedAtVehicle()
            if veh == 0 then return notifyLocal('warn', L('admin.c.dv_none')) end
            if not NetworkGetEntityIsNetworked(veh) then
                -- local-only prop car, nothing on the server to clean up
                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
                return notifyLocal('success', L('admin.c.dv_done', { n = 1, s = 0, k = 0 }))
            end
            payload = { netId = NetworkGetNetworkIdFromEntity(veh) }
        end

        local result = BSB.Await('admin:action', 10000, 'deleteVehicles', payload)
        if not result or not result.ok then
            return notifyLocal('warn', (result and result.error) or L('admin.c.denied'))
        end
        notifyLocal('success', L('admin.c.dv_done', { n = result.count or 0, s = result.stored or 0, k = result.skipped or 0 }))
    end)
end, false)

RegisterCommand('heal', function(_, args)
    CreateThread(function()
        local target = tonumber(args[1])
        local result = BSB.Await('admin:action', 10000, 'heal', { target = target })
        if not result or not result.ok then
            return notifyLocal('warn', (result and result.error) or 'Not allowed.')
        end
        notifyLocal('success', target and ('Healed %d.'):format(target) or 'Healed.')
    end)
end, false)

-- The coords overlay

CreateThread(function()
    while true do
        if coordsOverlay then
            Wait(0)
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)

            SetTextFont(4)
            SetTextScale(0.0, 0.34)
            SetTextColour(216, 210, 194, 220)
            SetTextDropshadow(2, 0, 0, 0, 255)
            SetTextOutline()
            SetTextEntry('STRING')
            AddTextComponentString(('%.2f  %.2f  %.2f   H %.1f   ZONE %s')
                :format(c.x, c.y, c.z, GetEntityHeading(ped),
                        GetLabelText(GetNameOfZone(c.x, c.y, c.z))))
            DrawText(0.012, 0.055)
        else
            Wait(400)
        end
    end
end)

-- Prop ID overlay, see localActions.propId above

-- Uses DebugLookAt, not CurrentEntity
CreateThread(function()
    local line = nil
    local nextRead = 0

    while true do
        if propIdOverlay and isAdmin then
            Wait(0)

            local now = GetGameTimer()
            if now >= nextRead then
                nextRead = now + 100

                local entity, distance, worldHit
                if GetResourceState('bs_interactions') == 'started' then
                    local ok, a, b, c = pcall(function()
                        return exports.bs_interactions:DebugLookAt()
                    end)
                    if ok then entity, distance, worldHit = a, b, c end
                end

                -- Type 0 means the handle is not a ped, vehicle or object (stale or non-networked), so there is no model to read
                local etype = (entity and entity ~= 0 and DoesEntityExist(entity)) and GetEntityType(entity) or 0
                if etype ~= 0 then
                    -- ModelOf, not GetEntityModel: that native faults on an entity whose archetype the streamer
                    local hash = BS.Util.ModelOf(entity)
                    local kind = ({ [1] = 'ped', [2] = 'vehicle', [3] = 'object' })[etype] or '?'

                    -- The engine has no hash to name lookup, so the hash is shown
                    line = ('LOOKING AT (%s)  model %s  entity %d  %.1fm')
                        :format(kind, hash and tostring(hash) or 'unknown', entity, distance or 0.0)

                elseif worldHit then
                    -- Two kinds of nothing: here the ray hit terrain or a building shell (collision with no entity), so there is no handle and no model
                    local c = worldHit.coords
                    line = ('LOOKING AT map geometry - no entity  |  %s  |  %.2f %.2f %.2f')
                        :format(tostring(worldHit.material or 'unknown material'),
                                c and c.x or 0.0, c and c.y or 0.0, c and c.z or 0.0)
                else
                    line = 'LOOKING AT (nothing in range)'
                end
            end

            if line then
                SetTextFont(4)
                SetTextScale(0.0, 0.34)
                SetTextColour(200, 118, 58, 220)
                SetTextDropshadow(2, 0, 0, 0, 255)
                SetTextOutline()
                SetTextEntry('STRING')
                AddTextComponentString(line)
                DrawText(0.012, 0.09)
            end
        else
            line, nextRead = nil, 0
            Wait(300)
        end
    end
end)

-- Server-driven effects

-- Teleport to coords, sent by the server tpCoords action (F10 or /tpc)
local tpBusy = false
-- Repair: the car I am in or looking at, through the server action (admin check + bs_guard_log).
function AdminRepairLooked()
    local veh = AdminLookedAtVehicle()
    if veh == 0 then return { error = L('admin.c.repair_none') } end
    if not NetworkGetEntityIsNetworked(veh) then return { error = L('admin.c.repair_none') } end
    local r = BSB.Await('admin:action', 10000, 'repairVehicle', { netId = NetworkGetNetworkIdFromEntity(veh) })
    if not r or not r.ok then return { error = (r and r.error) or L('admin.c.denied') } end
    return { ok = true, note = L('admin.c.repair_done', { plate = r.plate or '?' }) }
end

RegisterCommand('repair', function()
    CreateThread(function()
        local r = AdminRepairLooked()
        notifyLocal(r.ok and 'success' or 'warn', r.ok and r.note or r.error)
    end)
end, false)

-- Sent by the server repairVehicle action to the entity owner (and the driver/admin).
RegisterNetEvent('bs:admin:repairVehicle', function(netId, record)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
    for wheel = 0, 7 do SetVehicleTyreFixed(veh, wheel) end
    for window = 0, 7 do FixVehicleWindow(veh, window) end
    -- driver re-syncs bs_vehicles fuel/wear trackers with the repaired record
    if record and GetPedInVehicleSeat(veh, -1) == PlayerPedId() then
        TriggerEvent('bs:vehicles:entered', record, veh)
    end
end)

-- F10 > Trader editor button: close the menu, then run bs_traders' own debug command.
RegisterNetEvent('bs:admin:openTraderEditor', function()
    closeMenu()
    Wait(150)
    ExecuteCommand('traderdebug')
end)

RegisterNetEvent('bs:admin:tpCoords', function(x, y, z)
    if tpBusy then return end
    tpBusy = true
    local ped = PlayerPedId()
    local entity = ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then entity = vehicle end

    DoScreenFadeOut(180)
    local fadeEnd = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < fadeEnd do Wait(0) end
    FreezeEntityPosition(entity, true)

    local targetZ = z
    if not targetZ then
        local found, groundZ = false, 0.0
        for probe = 1000, -100, -25 do
            RequestCollisionAtCoord(x, y, probe + 0.0)
            SetEntityCoordsNoOffset(entity, x, y, probe + 0.0, false, false, false)
            Wait(20)
            found, groundZ = GetGroundZFor_3dCoord(x, y, probe + 0.0, false)
            if found then break end
        end
        targetZ = found and groundZ or 100.0
    end

    RequestCollisionAtCoord(x, y, targetZ)
    SetEntityCoordsNoOffset(entity, x, y, targetZ + 1.0, false, false, false)
    local deadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do Wait(50) end
    if entity == vehicle then SetVehicleOnGroundProperly(vehicle) end

    FreezeEntityPosition(entity, false)
    DoScreenFadeIn(220)
    tpBusy = false
end)

RegisterNetEvent('bs:admin:teleportTo', function(x, y, z)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 1.0, false, false, false)
end)

-- Broadcast so /dv (and the menu's delete) removes the car for everyone watching
RegisterNetEvent('bs:admin:vehiclesDeleted', function(list)
    for _, entry in ipairs(list or {}) do
        local veh = entry.netId and NetworkGetEntityFromNetworkId(entry.netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            DeleteEntity(veh)
        end
    end
end)

-- Staff freeze. Re-applied every half second, since a ragdoll or a new ped would drop it.
local frozenByStaff = false
RegisterNetEvent('bs:admin:freeze', function(on)
    frozenByStaff = on == true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, frozenByStaff)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then FreezeEntityPosition(veh, frozenByStaff) end
    if frozenByStaff then
        CreateThread(function()
            while frozenByStaff do
                local p = PlayerPedId()
                FreezeEntityPosition(p, true)
                local v = GetVehiclePedIsIn(p, false)
                if v ~= 0 then FreezeEntityPosition(v, true) end
                Wait(500)
            end
        end)
    end
end)

RegisterNetEvent('bs:admin:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('bs:admin:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

-- Clock and weather are handled by bs_world (client/cl_time.lua, server/sv_time.lua)

-- The menu must never survive into a state where the player can't close it.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        TriggerScreenblurFadeOut(0)
    end
end)

-- One menu at a time, see the note in bs_inventory.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'admin' and open then closeMenu() end
end)

-- /refreshui hard reset, see bs_inventory
AddEventHandler('bs:ui:panic', function()
    open = false
    send({ action = 'close' })
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0)
end)

AddEventHandler('bs:hook:player:unloaded', function() closeMenu() end)

-- SetPlayerInvincible/SetEntityInvincible only block damage that goes through the engine pipeline
CreateThread(function()
    while true do
        Wait(1000)
        if godmode then
            local ped = PlayerPedId()
            SetPlayerInvincible(PlayerId(), true)
            if DoesEntityExist(ped) then SetEntityInvincible(ped, true) end
        end
    end
end)

exports('IsGodmode', function() return godmode end)

-- /ammo - same action as the menu button, for topping up mid-test with the menu closed
RegisterCommand('ammo', function(_, args)
    CreateThread(function()
        local amount = args[1]  -- '3' = mags, '45r' = rounds; server parses
        local result = BSB.Await('admin:action', 10000, 'giveammo', { amount = amount })

        if result and result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'success',
                message = result.note and ('Added ' .. result.note) or 'Ammo added.',
                duration = 2600,
            })
        else
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or 'Not allowed.',
                duration = 3000,
            })
        end
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/ammo',
    'Add ammunition for the weapon in your hands (staff)', {
        { name = 'mags', help = 'full mags, 1-20 (default 3), or rounds like 45r' },
    })

-- Books editor: the server callback in bs_books checks staff permissions again.
RegisterNUICallback('booksAdmin', function(data, cb)
    CreateThread(function()
        local action = type(data) == 'table' and data.action or nil
        local args = type(data) == 'table' and data.args or {}
        cb(BSB.Await('books:admin', 15000, action, args) or {ok=false,error='Keine Antwort von bs_books'})
    end)
end)

-- Prop Studio NUI bridge: every mutation is authorized by bs_building server.
RegisterNUICallback('propStudio', function(data, cb)
    CreateThread(function()
        if not isAdmin then cb({ok=false,error='Keine Berechtigung'}); return end
        local action = type(data) == 'table' and data.action or nil
        if action == 'validateModel' then
            local model = type(data.payload)=='table' and data.payload.model or nil
            if type(model)~='string' or not model:match('^[%w_]+$') or #model>90 then cb({ok=false,error='Ungültiger Modellname'}); return end
            local hash=GetHashKey(model)
            cb(IsModelInCdimage(hash) and IsModelValid(hash) and {ok=true} or {ok=false,error='GTA-Modell nicht vorhanden: '..model})
            return
        end
        local name = ({list='build:studio:list',save='build:studio:save',reset='build:studio:reset',categories='build:studio:categories',categoryCreate='build:studio:categoryCreate',categoryRename='build:studio:categoryRename',categoryDelete='build:studio:categoryDelete',remove='build:studio:remove',restore='build:studio:restore',placedNearby='build:admin:placedNearby'})[action or '']
        if not name then cb({ok=false,error='Ungültige Aktion'}); return end
        local arg = action == 'reset' and data.id or data.payload
        cb(BSB.Await(name, 10000, arg) or {ok=false,error='Keine Antwort von bs_building'})
    end)
end)

RegisterNUICallback('propStudioPreview', function(data, cb)
    if not isAdmin or GetResourceState('bs_building') ~= 'started' then cb({ok=false,error='Nicht verfügbar'});return end
    if type(data) ~= 'table' then cb({ok=false,error='Ungültige Daten'});return end
    closeMenu()
    TriggerEvent('bs:building:studio:edit', data)
    cb({ok=true})
end)

-- Prop editor errors are retained in the F10 Debug / Fehlerprotokoll.
AddEventHandler('bs:admin:propStudioError', function(message)
    SendNUIMessage({ action = 'propStudioError', message = tostring(message or 'Unbekannter Fehler') })
end)

RegisterNUICallback('propPlacedAction', function(data, cb)
    CreateThread(function()
        if not isAdmin then cb({ok=false,error='Keine Berechtigung'});return end
        local action=data and data.action
        local id=tonumber(data and data.id)
        if not id or (action~='delete' and action~='move') then cb({ok=false,error='Ungueltige Aktion'});return end
        cb(BSB.Await('build:admin:placedAction',12000,action,id,data.coords) or {ok=false,error='Keine Antwort'})
    end)
end)
RegisterNUICallback('propPlacedEdit', function(data,cb)
    if not isAdmin or not data or not tonumber(data.id) then cb({ok=false,error='Keine Berechtigung'});return end
    closeMenu()
    TriggerEvent('bs:building:admin:editPlaced',tonumber(data.id))
    cb({ok=true})
end)
