-- client/cl_spawn.lua - applies appearance, model and position once a character is selected, and runs the position heartbeat.
-- bs_ui provides the selection screen; /characters and /play <slot> work from chat as a fallback.

-- Position sanity check, used both when saving (heartbeat) and when spawning, so a bad stored position cannot poison later sessions.
-- Only two things are refused: coordinates that are not numbers or not in the world, and the character-selection stage. Tunnels, ocean etc. are fine.
-- @return boolean ok
-- @return string|nil why
function BS.PositionIsSane(x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then
        return false, 'not numbers'
    end

    -- NaN fails every comparison including with itself, which is the only
    -- reliable way to catch it.
    if x ~= x or y ~= y or z ~= z then return false, 'NaN' end

    local b = Config.Session.worldBounds or { xy = 8500.0, zMin = -800.0, zMax = 2500.0 }
    if math.abs(x) > b.xy or math.abs(y) > b.xy or z < b.zMin or z > b.zMax then
        return false, 'outside the world'
    end

    for _, zone in ipairs(Config.Session.forbiddenSpawns or {}) do
        local dx, dy, dz = x - zone.x, y - zone.y, z - zone.z
        if (dx * dx + dy * dy + dz * dz) <= (zone.radius * zone.radius) then
            return false, 'the character-selection stage'
        end
    end

    return true, nil
end

-- The heartbeat must not run during a spawn. BS.IsLoaded() turns true before the ped is moved, so a heartbeat in that window would save the character-selection stage (or mid-air coordinates) as the character's position.
local spawnReady = false

-- One-shot rescue, set by the SAFE SPAWN box on the character screen (bs_multichar), read once by the spawn and cleared right after.
-- For a stored position that crashes the client every time it streams. One-shot on purpose so normal logout positions are not discarded.
local safeSpawnOnce = false
local PENDING_SPAWN_KVP = 'bs_core:pendingCharacterSpawn'
local autoSafeSpawn = false

AddEventHandler('bs:core:safeSpawn', function(on)
    safeSpawnOnce = on and true or false
end)

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end
    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 10000 do
        Wait(10); waited = waited + 10
    end
    return HasModelLoaded(hash), hash
end

--- Applies a Config.Appearance-shaped table to any ped.
--- @param ped number|nil  defaults to the local player's ped
--- @param appearance table
function BS.ApplyAppearanceTo(ped, appearance)
    appearance = appearance or {}
    ped = ped or PlayerPedId()
    if not DoesEntityExist(ped) then return false end

    SetPedHeadBlendData(ped,
        appearance.motherIndex or 0, appearance.fatherIndex or 0, 0,
        appearance.motherIndex or 0, appearance.fatherIndex or 0, 0,
        appearance.shapeMix or 0.5, appearance.skinMix or 0.5, 0.0, false)

    -- Hair is a component like any other, and asking for hairstyle 76 on a
    -- model that has 40 is the same invalid-variation error as anything else.
    local hairCount = GetNumberOfPedDrawableVariations(ped, 2)
    local hair = math.max(0, math.min(math.floor(appearance.hairStyle or 0),
        math.max(0, hairCount - 1)))
    SetPedComponentVariation(ped, 2, hair, 0, 0)
    SetPedHairColor(ped, appearance.hairColor or 0, appearance.hairHighlight or 0)

    -- Overlay ids: 1 beard, 2 eyebrows, 0 blemishes, 3 ageing, 6 complexion,
    -- 7 sun damage, 9 freckles, 11 body blemishes.
    local overlays = {
        { id = 0,  style = appearance.blemishStyle, opacity = 1.0 },
        { id = 1,  style = appearance.beardStyle,   opacity = appearance.beardOpacity or 1.0, colorType = 1, color = appearance.beardColor },
        { id = 2,  style = appearance.eyebrowStyle, opacity = 1.0, colorType = 1, color = appearance.eyebrowColor },
        { id = 3,  style = appearance.ageingStyle,  opacity = 1.0 },
        { id = 6,  style = appearance.complexion,   opacity = 1.0 },
        { id = 7,  style = appearance.sunDamage,    opacity = 1.0 },
        { id = 9,  style = appearance.freckles,     opacity = 1.0 },
        { id = 11, style = appearance.bodyBlemish,  opacity = 1.0 },
        -- Makeup family: soft opacity so it reads as makeup, not paint. Colour type 2 is the makeup palette.
        { id = 4,  style = appearance.makeupStyle,   opacity = 0.6 },
        { id = 5,  style = appearance.blushStyle,    opacity = 0.5, colorType = 2, color = appearance.blushColor },
        { id = 8,  style = appearance.lipstickStyle, opacity = 0.7, colorType = 2, color = appearance.lipstickColor },
    }

    for _, o in ipairs(overlays) do
        local style = o.style

        -- 255 is "none". Anything else is clamped to what this head actually
        -- offers, because an out-of-range overlay is refused outright.
        if style == nil or style < 0 then
            SetPedHeadOverlay(ped, o.id, 255, 0.0)
        else
            local available = GetPedHeadOverlayNum(o.id)
            if available and available > 0 then
                style = math.max(0, math.min(math.floor(style), available - 1))
            end

            SetPedHeadOverlay(ped, o.id, style, (o.opacity or 1.0) + 0.0)
            if o.colorType then
                SetPedHeadOverlayColor(ped, o.id, o.colorType, o.color or 0, o.color or 0)
            end
        end
    end

    SetPedEyeColor(ped, appearance.eyeColor or 0)

    -- Face shape details (schema entries that carry a feature index). Must come after the head blend.
    for _, f in ipairs(Config.Appearance or {}) do
        if f.feature then
            local v = tonumber(appearance[f.key]) or 0.0
            SetPedFaceFeature(ped, f.feature, math.max(-1.0, math.min(1.0, v + 0.0)))
        end
    end

    -- Sensible default clothing so a fresh character is never naked.
    if BS.Outfit and BS.Outfit.ApplyDefaults then
        BS.Outfit.ApplyDefaults(ped)
    else
        for _, comp in ipairs({ 3, 4, 6, 8, 11 }) do SetPedComponentVariation(ped, comp, 0, 0, 2) end
    end

    return true
end

--- Backwards-compatible wrapper for the local ped.
function BS.ApplyAppearance(appearance)
    return BS.ApplyAppearanceTo(PlayerPedId(), appearance)
end

exports('ApplyAppearanceTo', function(ped, appearance)
    return BS.ApplyAppearanceTo(ped, appearance)
end)

BS.On('player:loaded', function(data)
    -- A client crash during this character's previous load leaves this
    -- marker behind. Only that character gets one safe-spawn recovery;
    -- another character/account on the same client keeps its own position.
    local charKey = data.charId and tostring(data.charId) or nil
    autoSafeSpawn = charKey ~= nil
        and GetResourceKvpString(PENDING_SPAWN_KVP) == charKey
    if autoSafeSpawn then
        safeSpawnOnce = true
        BS.Log.warn('spawn', ('previous load of character %s did not finish - using Safe Spawn once')
            :format(charKey))
    end
    if charKey then SetResourceKvp(PENDING_SPAWN_KVP, charKey) end

    CreateThread(function()
        DoScreenFadeOut(250)
        Wait(300)

        -- Failsafe: 25 seconds after the fade-out the screen comes back no matter what, so a stuck load never leaves a black screen.
        CreateThread(function()
            Wait(25000)
            if IsScreenFadedOut() or IsScreenFadingOut() then
                BS.Log.warn('spawn', 'spawn took too long - forcing the screen back')
                DoScreenFadeIn(500)
            end
        end)

        local modelName = Config.Character.pedModels[data.gender] or Config.Character.pedModels.male
        local ok, hash = loadModel(modelName)
        if ok then
            SetPlayerModel(PlayerId(), hash)
            SetModelAsNoLongerNeeded(hash)
        else
            BS.Log.error('spawn', ('could not load ped model "%s"'):format(tostring(modelName)))
        end

        local ped = PlayerPedId()
        BS.ApplyAppearanceTo(ped, data.appearance)

        -- Restore the clothes and weapon this character was last seen in.
        local meta = data.metadata or {}
        if meta.outfit then BS.Outfit.Apply(ped, meta.outfit) end
        -- New characters: check the upper body really took (arms/undershirt/top), else fall back to a valid default.
        local isNewChar = type(meta.firstSpawn) == 'table'
        local upperFix = BS.Outfit.EnsureUpper(ped, meta.outfit, isNewChar)
        if upperFix then BS.Log.warn('spawn', ('upper body fixed on spawn (%s)'):format(upperFix)) end
        if meta.lastWeapon then
            -- Re-arming here bypasses bs_weapons' normal draw flow, so restore the saved ammo explicitly. bs_weapons syncs its saved ammo on player load too, so wait briefly for it before falling back to empty.
            -- meta.lastWeapon is a hash but SyncedAmmo is keyed by weapon name; use SyncedAmmoByHash.
            local rounds = 0
            if GetResourceState('bs_weapons') == 'started' then
                local waited = 0
                while waited < 1500 do
                    local ok, saved = pcall(function()
                        return exports.bs_weapons:SyncedAmmoByHash(meta.lastWeapon)
                    end)
                    if ok and type(saved) == 'number' then rounds = saved break end
                    Wait(100); waited = waited + 100
                end
            end

            GiveWeaponToPed(ped, meta.lastWeapon, 0, false, true)
            SetPedAmmo(ped, meta.lastWeapon, rounds)
        end

        -- See Config.Session.spawnForceDefault. Off by default: it discards the player's real position.
        local pos = data.position or Config.Session.defaultSpawn
        -- First spawn of a new character: the chosen start point wins over safe spawn and the saved position.
        local fs = type(data.metadata) == 'table' and data.metadata.firstSpawn or nil
        local firstSpawn = type(fs) == 'table' and BS.PositionIsSane(fs.x, fs.y, fs.z) and fs or nil
        if firstSpawn then safeSpawnOnce = false; autoSafeSpawn = false; pos = firstSpawn end

        if firstSpawn then
            BS.Log.info('spawn', ('first spawn at the chosen start %.1f %.1f %.1f'):format(pos.x, pos.y, pos.z))
        elseif safeSpawnOnce then
            safeSpawnOnce = false          -- consumed, whatever happens next
            pos = Config.Session.defaultSpawn
            BS.Log.warn('spawn', autoSafeSpawn
                and 'automatic crash recovery - starting at the camp'
                or 'SAFE SPAWN was requested - starting at the camp')

            CreateThread(function()
                Wait(4000)
                TriggerEvent('bs:ui:notify', {
                    type = 'info', duration = 7000,
                    message = autoSafeSpawn
                        and L('spawn.recovered')
                        or L('spawn.safe'),
                })
            end)

        elseif Config.Session.spawnForceDefault then
            pos = Config.Session.defaultSpawn
            BS.Log.warn('spawn', 'spawnForceDefault is ON - ignoring the saved position')
        else
            local sane, why = BS.PositionIsSane(pos.x, pos.y, pos.z)
            if not sane then
                BS.Log.warn('spawn', ('stored position %.1f %.1f %.1f is %s - using the default spawn')
                    :format(tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0, why))
                pos = Config.Session.defaultSpawn
            end
        end

        -- One compact breadcrumb survives in the client log if the game
        -- crashes during world streaming before the spawned hook can fire.
        local poolOk, pedPool = pcall(GetGamePool, 'CPed')
        BS.Log.info('spawn', ('character %s destination %.1f %.1f %.1f; safe=%s; local peds=%s')
            :format(tostring(data.charId), pos.x, pos.y, pos.z,
                tostring(pos == Config.Session.defaultSpawn),
                poolOk and type(pedPool) == 'table' and tostring(#pedPool) or '?'))

        -- Do not release the ped until: 1. collision is loaded around the point, 2. the ground is found there (GetGroundZFor_3dCoord returns false over unloaded terrain, and a stored Z can be under the surface), 3. the ped stands on that ground.
        -- Streaming focus is pinned to the destination during the wait and released once the ped is standing.

        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)

        SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ped, pos.h or 0.0)

        -- Load the destination, not the origin.
        SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)

        -- Load scene is off on purpose: NewLoadSceneStart forces a load of everything in range, and with ~63k static map entities with large ymap bounds that burst crashed clients right after spawn.
        -- The loop below still waits for collision and ground, so nobody falls through the map. Kept as a switch in case the map extents get fixed.
        if Config.Session.spawnLoadScene then
            NewLoadSceneStart(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 50.0, 0)
        end

        -- Do not call RequestCollisionAtCoord every pass: each request takes a slot in a 256-entry script resource pool and the game crashes when it is full. One request pins the coordinate; it is re-issued every 2 s in case the engine drops it, which caps usage at about 8 slots.
        local waited, groundZ = 0, nil
        local nextAsk = 2000

        while waited < 15000 do
            if waited >= nextAsk then
                RequestCollisionAtCoord(pos.x, pos.y, pos.z)
                nextAsk = waited + 2000
            end

            local collided = HasCollisionLoadedAroundEntity(ped)
            local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 3.0, false)
            -- Probe from higher up too, a stored Z can sit under a roof or below the surface.
            if not found then found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 60.0, false) end
            if found then groundZ = z end

            -- Both, not either. Collision can report ready while the terrain
            -- mesh under this exact point still has not arrived.
            -- IsNewLoadSceneActive is false when no scene was started, so
            -- this reads correctly either way round.
            if collided and groundZ and not IsNewLoadSceneActive() then break end

            Wait(50); waited = waited + 50
        end

        if Config.Session.spawnLoadScene then NewLoadSceneStop() end
        ClearFocus()

        if groundZ then
            SetEntityCoordsNoOffset(ped, pos.x, pos.y, groundZ + 0.1, false, false, false)
        elseif firstSpawn then
            -- Ground never answered: stay at the chosen start (frozen until the catch net below).
            BS.Log.warn('spawn', 'no ground at the chosen start - keeping its stored height')
            SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z + 0.5, false, false, false)
            Wait(500)
        else
            -- The ground never answered. Rather than dropping the player into
            -- the void, put them at the configured default spawn and say so.
            local fallback = Config.Session.defaultSpawn
            BS.Log.warn('spawn', ('no ground at %.1f %.1f - using the default spawn')
                :format(pos.x, pos.y))
            SetEntityCoordsNoOffset(ped, fallback.x, fallback.y, fallback.z, false, false, false)
            Wait(500)
        end

        SetEntityCollision(ped, true, true)

        local stats = (data.class and data.class.stats) or {}
        SetEntityMaxHealth(ped, stats.maxHealth or 200)
        SetEntityHealth(ped, stats.maxHealth or 200)
        SetPlayerMaxArmour(PlayerId(), stats.armorCap or 100)

        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, false)
        SetPlayerControl(PlayerId(), true, 0)
        ClearPedTasksImmediately(ped)

        -- Re-check the clothes once after the spawn settles: a late model load or another script can drop or overwrite them.
        CreateThread(function()
            local snap = BS.Outfit.UpperSnapshot(ped)
            Wait(3000)
            local p = PlayerPedId()
            if not DoesEntityExist(p) then return end
            local changed = p ~= ped
            for id, v in pairs(snap) do
                if GetPedDrawableVariation(p, id) ~= v[1] then changed = true end
            end
            if changed then
                for id, v in pairs(snap) do SetPedComponentVariation(p, id, v[1], math.max(0, v[2]), 2) end
            end
            local late = BS.Outfit.EnsureUpper(p, meta.outfit, isNewChar)
            if changed or late then
                BS.Log.warn('spawn', ('upper body fixed after spawn (%s)'):format(late or 'restored'))
            end
            if upperFix or changed or late then BS.Outfit.Push() end
        end)

        -- Catch net: if the ped is still falling 3 s after release, put it back on the ground instead of letting it fall through the map.
        CreateThread(function()
            local start = GetGameTimer()

            while GetGameTimer() - start < 12000 do
                Wait(500)
                local me = PlayerPedId()
                if not DoesEntityExist(me) then return end

                local at = GetEntityCoords(me)
                local found, z = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)

                -- Below the ground, or falling with nothing under us at all.
                if (found and at.z < z - 3.0) or (not found and at.z < -50.0) then
                    BS.Log.warn('spawn', 'caught the player falling through the map')
                    local target = found and z or (Config.Session.defaultSpawn.z)
                    local tx = found and at.x or Config.Session.defaultSpawn.x
                    local ty = found and at.y or Config.Session.defaultSpawn.y

                    FreezeEntityPosition(me, true)
                    SetEntityCoordsNoOffset(me, tx, ty, target + 1.0, false, false, false)
                    Wait(300)
                    FreezeEntityPosition(me, false)
                    return
                end
            end
        end)

        -- Fade back in before the hooks run: BS.Emit calls handlers inline, and one yielding handler would hold this thread and leave a black screen.
        DoScreenFadeIn(750)

        -- Only now is the ped somewhere worth remembering.
        spawnReady = true
        if charKey then DeleteResourceKvp(PENDING_SPAWN_KVP) end
        autoSafeSpawn = false

        TriggerServerEvent(BS.Events.CharacterSpawned, data.charId)
        BS.Emit('player:spawned', data)
    end)
end)

-- Goes false again when the character leaves, so switching characters does not save the stage as the outgoing character's position.
AddEventHandler('bs:hook:player:unloaded', function() spawnReady = false end)

-- Position heartbeat.
CreateThread(function()
    local interval = (Config.Framework.positionSyncInterval or 30) * 1000
    while true do
        Wait(interval)

        -- spawnReady, not just IsLoaded. See the note above the flag.
        if BS.IsLoaded() and spawnReady then
            local ped = PlayerPedId()
            if not IsEntityDead(ped) then
                local c = GetEntityCoords(ped)

                -- Checked on the way out too: noclip, bad teleports or a ped falling out of the world could also store a bad position.
                if BS.PositionIsSane(c.x, c.y, c.z) then
                    TriggerServerEvent(BS.Events.UpdatePosition,
                        c.x, c.y, c.z, GetEntityHeading(ped))
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Fallback character selection (chat-based) until bs_ui ships the NUI screen.
--------------------------------------------------------------------------------

local cachedList

local function printChat(text)
    TriggerEvent('chat:addMessage', { args = { '^5[BeyondSurvival]^7', text } })
end

RegisterCommand('characters', function()
    local data = BSB.Await('characters:list')
    if not data then return printChat('Server did not respond.') end
    cachedList = data.characters or {}
    printChat(('Slots: %d/%d'):format(#cachedList, data.maxSlots))
    for i, char in ipairs(cachedList) do
        printChat(('  [%d] %s %s - %s, level %d'):format(
            i, char.first_name, char.last_name, char.classLabel or char.class, char.level))
    end
    if #cachedList == 0 then
        printChat('No characters yet. Use: /newchar <first> <last> <male|female> <YYYY-MM-DD> <class>')
        printChat('Classes: ' .. table.concat(BS.Util.Keys(Config.Classes), ', '))
    else
        printChat('Use /play <slot> to spawn, /delchar <slot> to delete.')
    end
end, false)

RegisterCommand('newchar', function(_, args)
    if #args < 5 then
        return printChat('Usage: /newchar <first> <last> <male|female> <YYYY-MM-DD> <class>')
    end
    local result = BSB.Await('characters:create', 10000, {
        firstName = args[1], lastName = args[2], gender = args[3],
        dob = args[4], class = args[5],
        appearance = Config.DefaultAppearance(args[3]),
    })
    if not result or not result.ok then
        return printChat('^1Failed:^7 ' .. ((result and result.error) or 'no response'))
    end
    printChat(('Character created (#%d). Use /characters then /play <slot>.'):format(result.charId))
end, false)

RegisterCommand('play', function(_, args)
    local slot = tonumber(args[1])
    if not cachedList then
        local data = BSB.Await('characters:list')
        cachedList = data and data.characters or {}
    end
    local char = slot and cachedList[slot]
    if not char then return printChat('Unknown slot. Run /characters first.') end
    local result = BSB.Await('characters:select', 10000, char.id)
    if not result or not result.ok then
        printChat('^1Failed:^7 ' .. ((result and result.error) or 'no response'))
    end
end, false)

RegisterCommand('delchar', function(_, args)
    local slot = tonumber(args[1])
    local char = slot and cachedList and cachedList[slot]
    if not char then return printChat('Unknown slot. Run /characters first.') end
    local result = BSB.Await('characters:delete', 10000, char.id)
    if result and result.ok then
        cachedList = result.characters
        printChat('Character deleted.')
    end
end, false)

-- The chat commands stay available as a fallback, but stay quiet when
-- bs_multichar is providing a real screen.
BS.On('session:state', function(state)
    if state ~= 'select' then return end
    if GetResourceState('bs_multichar') == 'started' then return end
    printChat('Type ^2/characters^7 to pick or create a character.')
end)
