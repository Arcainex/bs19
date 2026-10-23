-- bs_core - startup order, connection handshake, autosave and shutdown.

local resourceName = GetCurrentResourceName()

-- Startup

AddEventHandler('onResourceStart', function(resource)
    if resource ~= resourceName then return end

    CreateThread(function()
        BS.Log.info('core', ('%s v%s starting (server)'):format(BS.Name, BS.Version))

        local tries = 0
        while not BS.DB.Ping() do
            tries = tries + 1
            if tries > 20 then
                BS.Log.error('core', 'database unreachable - framework halted')
                return
            end
            BS.Log.warn('core', 'waiting for database...')
            Wait(1000)
        end

        if not BS.Migrations.Run() then
            BS.Log.error('core', 'migrations failed - framework halted')
            return
        end

        BS.Ready = true
        BS.Emit('core:ready')
        BS.Log.info('core', 'framework ready')

        -- Re-bind players already connected (resource restart on a live server).
        for _, src in ipairs(GetPlayers()) do
            src = tonumber(src)
            local user = BS.Identity.Resolve(src)
            if user then
                BS.Characters.BindSession(src, user)
                BS.Locale.Apply(src, user)
                TriggerClientEvent(BS.Events.SessionState, src, 'select')
            end
        end
    end)
end)

-- Connection handshake

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update(L('conn.checking', { name = BS.Name }))

    if not BS.Ready then
        return deferrals.done(L('conn.starting', { name = BS.Name }))
    end

    local user, err = BS.Identity.Resolve(src)
    if not user then
        return deferrals.done(L('conn.no_account', { name = BS.Name, err = tostring(err) }))
    end

    local ban = BS.Identity.CheckBan(user.id)
    if ban then
        -- The account row knows the player's language even before the state bag exists.
        local lang = BSLocale.IsValid(user.language) and user.language or BSLocale.Default()
        local until_ = ban.expires_at and BSLocale.T(lang, 'conn.ban_until', { date = tostring(ban.expires_at) })
            or BSLocale.T(lang, 'conn.ban_forever')
        return deferrals.done(BSLocale.T(lang, 'conn.banned', { name = BS.Name, until_ = until_,
            reason = ban.reason or BSLocale.T(lang, 'conn.no_reason') }))
    end

    deferrals.done()
end)

-- Client finished loading and is ready for the character list.
RegisterNetEvent(BS.Events.ClientReady, function()
    local src = source
    local user = BS.Identity.Resolve(src)
    if not user then
        return DropPlayer(src, L('conn.resolve_failed', { name = BS.Name }))
    end
    BS.Characters.BindSession(src, user)
    BS.Locale.Apply(src, user)
    TriggerClientEvent(BS.Events.SessionState, src, 'select', {
        framework = { name = BS.Name, version = BS.Version },
    })
    BS.Log.debug('core', ('client %s ready'):format(src))
end)

-- Disconnect

AddEventHandler('playerDropped', function(reason)
    local src = source
    BS.UnloadPlayer(src, reason)
    BS.Characters.ClearSession(src)
end)

RegisterNetEvent(BS.Events.CharacterLogout, function()
    local src = source
    BS.UnloadPlayer(src, 'logout')
    TriggerClientEvent(BS.Events.SessionState, src, 'select')
end)

-- Position heartbeat + autosave

-- The heartbeat position becomes the saved spawn point, so validate it. The
-- bounds are generous (a jet at top speed over the full interval, see
-- Config.Framework.positionSyncInterval, 30s default); this only catches
-- obvious lies like underground or off the map.
local lastPositionReport = {} -- [src] = { x, y, z, at = GetGameTimer() }

-- The playable world is roughly +-8000 on x/y; leave headroom for edge terrain.
local WORLD_BOUND_XY = 12000.0
local WORLD_BOUND_Z_MIN, WORLD_BOUND_Z_MAX = -500.0, 2200.0
-- A jet cruises well under this.
local MAX_PLAUSIBLE_SPEED = 140.0 -- units/second

RegisterNetEvent(BS.Events.UpdatePosition, function(x, y, z, h)
    local src = source
    local player = BS.GetPlayer(src)
    if not player then return end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    if x ~= x or y ~= y or z ~= z then return end -- NaN

    if math.abs(x) > WORLD_BOUND_XY or math.abs(y) > WORLD_BOUND_XY
        or z < WORLD_BOUND_Z_MIN or z > WORLD_BOUND_Z_MAX then
        return
    end

    local now = GetGameTimer()
    local last = lastPositionReport[src]
    if last then
        local dt = math.max(1.0, (now - last.at) / 1000.0)
        local dx, dy, dz = x - last.x, y - last.y, z - last.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if (dist / dt) > MAX_PLAUSIBLE_SPEED then
            -- Implausible jump for this interval: drop the claim, keep the last accepted
            -- position and do not advance the clock.
            return
        end
    end

    lastPositionReport[src] = { x = x, y = y, z = z, at = now }

    if type(h) ~= 'number' or h ~= h then h = nil end

    player:SetPosition(x, y, z, h)
end)

AddEventHandler('playerDropped', function()
    lastPositionReport[source] = nil
end)

CreateThread(function()
    while true do
        Wait((Config.Framework.autoSaveInterval or 300) * 1000)
        if BS.Ready then
            local saved = 0
            for _, player in pairs(BS.Players) do
                if player:Save() then saved = saved + 1 end
            end
            if saved > 0 then BS.Log.debug('core', ('autosave wrote %d characters'):format(saved)) end
        end
    end
end)

-- Shutdown

AddEventHandler('onResourceStop', function(resource)
    if resource ~= resourceName then return end
    for src, player in pairs(BS.Players) do
        player:Save(true)
        TriggerClientEvent(BS.Events.PlayerUnloaded, src, 'resource_stop')
    end
    BS.Log.info('core', 'saved all players on shutdown')
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    for _, player in pairs(BS.Players) do player:Save(true) end
end)

-- Wiring check. Runs once shortly after boot and warns about missing exports,
-- globals and ensure lines in other resources. It only warns: optional
-- resources (bs_vip, bs_extraction) may legitimately be missing.
CreateThread(function()
    -- Wait for other resources to finish starting.
    Wait(8000)

    local expected = {
        -- Everything the framework's own code calls into.
        'bs_ui', 'bs_inventory', 'bs_zombies', 'bs_economy', 'bs_skills',
        'bs_medical', 'bs_weapons', 'bs_vehicles', 'bs_building', 'bs_admin',
        'bs_emotes', 'bs_radial', 'bs_interactions', 'bs_world', 'bs_menu',
        'bs_multichar', 'bs_factions', 'bs_scenes', 'bs_scoreboard',
    }

    local missing = {}
    for _, resource in ipairs(expected) do
        if GetResourceState(resource) ~= 'started' then
            missing[#missing + 1] = ('%s (%s)'):format(resource, GetResourceState(resource))
        end
    end

    if #missing == 0 then
        print(('^2[BS CORE]^7 wiring check: all %d framework resources started.'):format(#expected))
        return
    end

    print('^3[BS CORE]^7 wiring check: these framework resources are NOT started -')
    for _, entry in ipairs(missing) do
        print(('  ^3-^7 %s'):format(entry))
    end
    print('^3[BS CORE]^7 anything that calls into them will silently do nothing.')
    print('^3[BS CORE]^7 If that is deliberate, ignore this. If not, the usual cause is a')
    print('^3[BS CORE]^7 missing `ensure` line in server.cfg - see the note above the')
    print('^3[BS CORE]^7 resource list there.')
end)
