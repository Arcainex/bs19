-- BeyondSurvival - zombies: takedowns from the ALT menu on a walker that is down, staggered,
-- or has not noticed you standing behind it. Both peds play a matching pair of vanilla melee clips,
-- then the server kills it like any other walker (loot, XP, body).

local E = Zombies.Execute
local T = E.takedown or {}
local nextExecute = 0
local busy = false
local refused = {}      -- [id] = true once the server said no to the current attempt
local offered = {}      -- [ped] = id we put a "Take down" option on

local MELEE   = GetHashKey('GROUP_MELEE')
local UNARMED = GetHashKey('GROUP_UNARMED')

-- Takedowns need a living, standing player: not dead, downed, ragdolled, carrying or being carried
local function canTakedown()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 or IsPedRagdoll(ped) then return false end
    if LocalPlayer.state.bsDowned then return false end
    if IsEntityAttached(ped) or IsPedInAnyVehicle(ped, false) then return false end
    if GetResourceState('bs_medical') == 'started' then
        local ok, v = pcall(function() return exports.bs_medical:IsDowned() end)
        if ok and v then return false end
        ok, v = pcall(function() return exports.bs_medical:IsCarrying() end)
        if ok and v then return false end
    end
    return true
end

local kindByHash = {}
for kind, list in pairs(T.weapons or (Zombies.Finisher and Zombies.Finisher.weapons) or {}) do
    for _, name in ipairs(list) do kindByHash[GetHashKey(name)] = kind end
end

-- fists | knife | small | hatchet | large. Guns count as fists (holstered for the move).
local function weaponKind(ped)
    local _, w = GetCurrentPedWeapon(ped, true)
    if not w or w == 0 then return 'fists', false end
    local group = GetWeapontypeGroup(w)
    if group == UNARMED then return 'fists', false end
    if group ~= MELEE then return 'fists', true end
    return kindByHash[w] or 'large', false
end

local function isCrawler(entry)
    return entry.def ~= nil and entry.def.crawls == true
end

-- Is the player in the walker's rear arc?
local function behindOf(zed, at)
    local zAt = GetEntityCoords(zed)
    local f = GetEntityForwardVector(zed)
    local tx, ty = at.x - zAt.x, at.y - zAt.y
    local len = math.sqrt(tx * tx + ty * ty)
    if len < 0.01 then return true end
    return (f.x * tx + f.y * ty) / len <= (E.behindDot or -0.1)
end

-- Why this walker can be taken down right now: 'down', 'stagger', 'behind', or nil.
local function reasonFor(entry, at)
    local zed = entry.ped
    if entry.dying or not zed or not DoesEntityExist(zed) or IsEntityDead(zed) then return nil end
    if isCrawler(entry) or IsPedRagdoll(zed) or IsPedGettingUp(zed) then return 'down' end
    if (entry.staggerUntil or 0) > GetGameTimer() then return 'stagger' end
    if E.onlyUnaware and (entry.state == 'hunting' or entry.state == 'hunt' or entry.state == 'grab') then return nil end
    if behindOf(zed, at) then return 'behind' end
    return nil
end

local function entryByPed(ped)
    if not Zed or not Zed.live or not ped then return nil end
    for _, entry in pairs(Zed.live) do
        if entry.ped == ped then return entry end
    end
end

-- Animations

local function loadDict(dict)
    if not dict or not DoesAnimDictExist(dict) then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function clipMs(dict, clip)
    local d = GetAnimDuration(dict, clip) or 0.0
    return d > 0.0 and math.floor(d * 1000) or 0
end

-- First pair in the list whose dict and both clips are really there
local function pickPair(list)
    for _, a in ipairs(list or {}) do
        if loadDict(a.dict) and clipMs(a.dict, a.plyr) > 0 and clipMs(a.dict, a.victim) > 0 then return a end
    end
end

local function pickSolo(list)
    for _, a in ipairs(list or {}) do
        if loadDict(a.dict) and clipMs(a.dict, a.clip) > 0 then return a end
    end
end

local function takeControl(ped, ms)
    if not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped) then return true end
    local t = GetGameTimer() + ms
    repeat
        NetworkRequestControlOfEntity(ped)
        Wait(0)
    until NetworkHasControlOfEntity(ped) or GetGameTimer() > t
    return NetworkHasControlOfEntity(ped)
end

local function sendKill(entry)
    if refused[entry.id] or not canTakedown() then return end
    -- Reported like any other kill, so the server owns the death and everybody sees the same body
    TriggerServerEvent('bs:z:hit', entry.id, (entry.def and entry.def.health or 220) * 10, true, 'execution')
end

-- Both peds in one networked scene at the player's feet, so the pair lines up exactly
local function playPair(entry, pair)
    -- Vanilla mission pairs carry their own world offsets and threw both peds across the map. Off until a pair is verified.
    if not T.syncedScene then return false end
    local player, zed = PlayerPedId(), entry.ped
    local at = GetEntityCoords(player)
    local heading = GetEntityHeading(player)
    local off = pair.offset or T.sceneOffset or vector3(0.0, 0.0, -1.0)

    if IsPedRagdoll(zed) then return false end
    ClearPedTasks(zed)
    -- Lined up before the scene starts, so a slow start never shows the walker sliding
    local fwd = GetEntityForwardVector(player)
    local gap = pair.gap or 0.8
    SetEntityCoordsNoOffset(zed, at.x + fwd.x * gap, at.y + fwd.y * gap, at.z, false, false, false)
    SetEntityHeading(zed, pair.facing == 'player' and (heading + 180.0) % 360.0 or heading)

    local scene = NetworkCreateSynchronisedScene(at.x + off.x, at.y + off.y, at.z + off.z,
        0.0, 0.0, heading, 2, false, false, 1.0, 0.0, 1.0)
    NetworkAddPedToSynchronisedScene(player, scene, pair.dict, pair.plyr, 8.0, -8.0, 0, 0, 1000.0, 0)
    NetworkAddPedToSynchronisedScene(zed, scene, pair.dict, pair.victim, 8.0, -8.0, 0, 0, 1000.0, 0)
    NetworkStartSynchronisedScene(scene)

    local length = math.max(800, math.min(5000, clipMs(pair.dict, pair.plyr)))
    local killAt = math.floor(length * (pair.killAt or T.killAt or 0.75))
    local started = GetGameTimer()
    local sent, playing = false, false

    while true do
        Wait(0)
        local t = GetGameTimer() - started
        if refused[entry.id] or not canTakedown() or not DoesEntityExist(zed) then break end
        if not playing and t > 400 then
            playing = IsEntityPlayingAnim(player, pair.dict, pair.plyr, 3)
            -- Scene never took: undo it and let the caller use the short clip instead
            if not playing then
                NetworkStopSynchronisedScene(scene)
                ClearPedTasks(player)
                if DoesEntityExist(zed) and not IsEntityDead(zed) then ClearPedTasks(zed) end
                return false
            end
        end
        if not sent and t >= killAt then sent = true; sendKill(entry) end
        if t >= length then break end
    end

    NetworkStopSynchronisedScene(scene)
    ClearPedTasks(player)
    if not sent then sendKill(entry) end
    -- The body falls on its own once the server kills it; one that was refused just walks away
    if DoesEntityExist(zed) and not IsEntityDead(zed) then
        if entry.dying then
            pcall(SetPedToRagdoll, zed, 1500, 2000, 0, false, false, false)
        elseif refused[entry.id] then
            ClearPedTasks(zed)
        end
    end
    return true
end

-- Player-only clip (stomp or knife on a body on the ground, or the fallback)
local function playSolo(entry, anim)
    local player = PlayerPedId()
    local length = anim.time or clipMs(anim.dict, anim.clip)
    length = math.max(600, math.min(3000, length))
    TaskPlayAnim(player, anim.dict, anim.clip, 8.0, -8.0, length, 0, 0.0, false, false, false)
    if entry.hosted and DoesEntityExist(entry.ped) and not IsPedRagdoll(entry.ped) and not isCrawler(entry) then
        ClearPedTasks(entry.ped)
    end
    local started = GetGameTimer()
    local sent = false
    while GetGameTimer() - started < length do
        Wait(0)
        if refused[entry.id] or not canTakedown() then break end
        if not sent and GetGameTimer() - started >= length * (anim.killAt or 0.55) then
            sent = true
            sendKill(entry)
        end
    end
    if refused[entry.id] or not sent then StopAnimTask(player, anim.dict, anim.clip, 4.0) end
end

local function run(entry, reason)
    local player = PlayerPedId()
    local zed = entry.ped
    local kind, gun = weaponKind(player)
    if gun then SetCurrentPedWeapon(player, GetHashKey('WEAPON_UNARMED'), true) end

    local zAt, at = GetEntityCoords(zed), GetEntityCoords(player)
    SetEntityHeading(player, GetHeadingFromVector_2d(zAt.x - at.x, zAt.y - at.y))
    if Zombies.Growl then Zombies.Growl(entry, 'death') end

    if reason ~= 'down' then
        local rear = reason == 'behind' or behindOf(zed, at)
        local set = rear and T.rear or T.front
        local pair = set and (pickPair(set[kind]) or pickPair(set.fists))
        if pair then
            pair.facing = rear and 'same' or 'player'
            if takeControl(zed, T.controlMs or 350) and playPair(entry, pair) then return end
        end
    end

    local solo = pickSolo((T.ground or {})[kind == 'knife' and 'knife' or 'fists'])
        or pickSolo(T.fallback)
    if solo then playSolo(entry, solo) else sendKill(entry) end
end

--- Starts a takedown on this walker. Returns true if it started.
local function takedown(entry)
    if busy or not E.enabled or not entry then return false end
    local now = GetGameTimer()
    if now < nextExecute or not canTakedown() then return false end
    local player = PlayerPedId()
    local at = GetEntityCoords(player)
    local reason = reasonFor(entry, at)
    if not reason then return false end
    if #(GetEntityCoords(entry.ped) - at) > (E.range or 2.0) + 0.3 then return false end

    busy = true
    nextExecute = now + (E.cooldown or 1200)
    refused[entry.id] = nil
    entry.takedownUntil = now + 6000
    Crumb('execute', 'id=%s %s', tostring(entry.id), reason)

    -- Knocked over by anything: the server only knows about fighting hits, so say so first
    if reason == 'down' and not isCrawler(entry) then TriggerServerEvent('bs:z:staggered', entry.id) end
    -- The server judges the takedown now, not when the hit lands
    TriggerServerEvent('bs:z:takedownStart', entry.id)

    LocalPlayer.state:set('bsTakedown', true, false)
    CreateThread(function()
        local ok, err = pcall(run, entry, reason)
        if not ok then
            print(('[BS ZOMBIES] takedown failed: %s'):format(tostring(err)))
            ClearPedTasks(PlayerPedId())
        end
        entry.takedownUntil = nil
        LocalPlayer.state:set('bsTakedown', false, false)
        busy = false
    end)
    return true
end

Zombies.Takedown = takedown

exports('Takedown', function(ped)
    return takedown(entryByPed(ped)) == true
end)

exports('CanTakedown', function(ped)
    local entry = entryByPed(ped)
    return entry ~= nil and not busy and canTakedown() and reasonFor(entry, GetEntityCoords(PlayerPedId())) ~= nil
end)

RegisterNetEvent('bs:z:takedownRefused', function(id)
    id = tonumber(id)
    if id then refused[id] = true end
end)

-- A fighting hit staggered or floored this walker (bs_fighting raises this on the attacker's client)
AddEventHandler('bs:zombies:fightReact', function(ped, kind)
    if kind ~= 'stumble' and kind ~= 'stagger' and kind ~= 'down' and kind ~= 'throw' then return end
    local entry = entryByPed(ped)
    if not entry then return end
    local now = GetGameTimer()
    entry.staggerUntil = now + (kind == 'stumble' and 450 or E.staggerWindow or 3000)
    -- cl_attack holds its swings until it has stood up again
    entry.recoverUntil = math.max(entry.recoverUntil or 0, now + (kind == 'stumble' and 450 or kind == 'stagger' and 900 or 600))
    TriggerServerEvent('bs:z:staggered', entry.id)
end)

-- The ALT menu option

AddEventHandler('bs:zombies:takedown', function(payload)
    local ped = payload and payload.entity
    local id = payload and payload.args and tonumber(payload.args.id)
    local entry = id and Zed and Zed.live[id]
    if not entry or entry.ped ~= ped then entry = entryByPed(ped) end
    takedown(entry)
end)

local function option(id)
    return { {
        label    = L('zed.takedown_opt'),
        labelKey = 'zed.takedown_opt',
        icon     = 'fist',
        distance = E.range or 2.0,
        event    = 'bs:zombies:takedown',
        args     = { id = id },
    } }
end

CreateThread(function()
    while true do
        local wait = 500
        if E.enabled and Zed and Zed.live and GetResourceState('bs_interactions') == 'started' then
            local want = {}
            if not busy and canTakedown() then
                local at = GetEntityCoords(PlayerPedId())
                for _, entry in pairs(Zed.live) do
                    local ped = entry.ped
                    if ped and DoesEntityExist(ped) and #(GetEntityCoords(ped) - at) <= 6.0 and reasonFor(entry, at) then
                        want[ped] = entry.id
                    end
                end
            end
            for ped, id in pairs(want) do
                wait = 250
                if offered[ped] ~= id then
                    if pcall(function() exports.bs_interactions:AddEntity(ped, option(id)) end) then offered[ped] = id end
                end
            end
            for ped, id in pairs(offered) do
                if not want[ped] then
                    offered[ped] = nil
                    -- A dead walker's body carries cl_combat's loot options by now: leave those alone
                    local entry = Zed.live[id]
                    if DoesEntityExist(ped) and not IsEntityDead(ped) and not (Zed.netRemoved and Zed.netRemoved[id])
                       and not (entry and entry.dying) then
                        pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- Dev check: which takedown dicts and clips this client can load
RegisterCommand('ztakedownanims', function()
    local checked, missing = 0, 0
    local function check(dict, clip)
        checked = checked + 1
        local ok = loadDict(dict) and clipMs(dict, clip) > 0
        if not ok then missing = missing + 1 end
        print(('[takedown] %s  %s / %s  %s'):format(ok and 'ok  ' or 'MISS', dict, clip, ok and (clipMs(dict, clip) .. 'ms') or ''))
    end
    for _, setName in ipairs({ 'rear', 'front' }) do
        for kind, list in pairs(T[setName] or {}) do
            for _, a in ipairs(list) do
                print(('[takedown] %s %s'):format(setName, kind))
                check(a.dict, a.plyr); check(a.dict, a.victim)
            end
        end
    end
    for _, list in pairs(T.ground or {}) do for _, a in ipairs(list) do check(a.dict, a.clip) end end
    for _, a in ipairs(T.fallback or {}) do check(a.dict, a.clip) end
    print(('[takedown] %d checked, %d missing'):format(checked, missing))
end, false)
