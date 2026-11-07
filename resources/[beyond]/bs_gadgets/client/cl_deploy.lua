-- Placement ghost and placed gadgets: turret, medic beacon, decoy.
-- The turret only shoots peds bs_zombies says are its walkers; the server applies the damage.

local G = GadgetCl

local function camDir()
    local r = GetGameplayCamRot(2)
    local x, z = math.rad(r.x), math.rad(r.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

-- Where the crosshair meets the ground, and whether something may be placed there.
local function aimSpot(t, ghost)
    local ped = PlayerPedId()
    local from = GetGameplayCamCoord()
    local to = from + camDir() * (t.placeRange + 8.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, ghost or ped, 7)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit ~= 1 and hit ~= true then return nil, false end
    local me = GetEntityCoords(ped)
    local ok = #(pos - me) <= t.placeRange and normal.z >= (t.maxSlope or 0.7)
    return pos, ok
end

-- Attack, aim, E/Q, cover, wheel, scroll, arrows, backspace and esc are blocked while placing.
local PLACE_BLOCK = { 24, 25, 37, 38, 44, 45, 140, 141, 142, 257, 263, 14, 15, 16, 17, 172, 173, 174, 175, 177, 199, 200, 51, 52, 22 }

-- Bottom-right key hints (instructional_buttons scaleform).
local function hintsScaleform(label)
    local sf = RequestScaleformMovie('instructional_buttons')
    local t = GetGameTimer() + 2000
    while not HasScaleformMovieLoaded(sf) and GetGameTimer() < t do Wait(0) end
    if not HasScaleformMovieLoaded(sf) then return nil end
    local function btn(slot, ctl, text)
        BeginScaleformMovieMethod(sf, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(slot)
        ScaleformMovieMethodAddParamPlayerNameString(GetControlInstructionalButton(0, ctl, true))
        BeginTextCommandScaleformString('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandScaleformString()
        EndScaleformMovieMethod()
    end
    BeginScaleformMovieMethod(sf, 'CLEAR_ALL'); EndScaleformMovieMethod()
    btn(0, 44, L('gad.cancel'))          -- Q
    btn(1, 175, L('gad.rotate'))         -- arrow right
    btn(2, 174, '')               -- arrow left
    btn(3, 38, L('gad.place', { name = label })) -- E
    BeginScaleformMovieMethod(sf, 'DRAW_INSTRUCTIONAL_BUTTONS'); EndScaleformMovieMethod()
    return sf
end

-- Ghost preview. E places, Q cancels, scroll or arrows rotate.
function G.Place(t, token)
    G.Busy = true
    CreateThread(function()
        local hash = G.LoadModel(t.model)
        if not hash then G.Busy = false; TriggerServerEvent('bs:gadgets:cancel'); return end
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local ghost = CreateObject(hash, c.x, c.y, c.z - 5.0, false, false, false)
        SetEntityAlpha(ghost, 160, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        -- turret: show the gun on the ghost too
        local ghostHead, hh = nil, t.headModel and G.LoadModel(t.headModel)
        if hh then
            ghostHead = CreateObject(hh, c.x, c.y, c.z - 5.0, false, false, false)
            SetEntityAlpha(ghostHead, 160, false)
            SetEntityCollision(ghostHead, false, false)
            local _, top = GetModelDimensions(hash)
            AttachEntityToEntity(ghostHead, ghost, 0, 0.0, 0.0, top.z + (t.headZ or 0.1), 0.0, 0.0, t.gunYaw or 90.0, false, false, false, false, 2, true)
        end
        local sf = hintsScaleform(G.Name(t))
        local heading = GetEntityHeading(ped)
        local placed, pos = false, nil
        local untilAt = GetGameTimer() + 45000
        while GetGameTimer() < untilAt do
            Wait(0)
            if G.Downed() or IsPedInAnyVehicle(PlayerPedId(), false) then break end
            for _, ctl in ipairs(PLACE_BLOCK) do DisableControlAction(0, ctl, true) end
            local spot, ok = aimSpot(t, ghost)
            if IsDisabledControlPressed(0, 14) or IsDisabledControlPressed(0, 174) then heading = heading - (IsDisabledControlPressed(0, 174) and 2.0 or 5.0) end
            if IsDisabledControlPressed(0, 15) or IsDisabledControlPressed(0, 175) then heading = heading + (IsDisabledControlPressed(0, 175) and 2.0 or 5.0) end
            if spot then
                SetEntityCoordsNoOffset(ghost, spot.x, spot.y, spot.z, false, false, false)
                SetEntityHeading(ghost, heading)
                local r, g = ok and 80 or 230, ok and 230 or 60
                DrawMarker(25, spot.x, spot.y, spot.z + 0.02, 0, 0, 0, 0, 0, 0, 0.9, 0.9, 0.9, r, g, 60, 140, false, false, 2, false, nil, nil, false)
                if t.kind == 'turret' then
                    DrawMarker(1, spot.x, spot.y, spot.z - 0.5, 0, 0, 0, 0, 0, 0, t.range * 2.0, t.range * 2.0, 0.6, 255, 170, 60, 30, false, false, 2, false, nil, nil, false)
                elseif t.kind == 'medic' then
                    DrawMarker(1, spot.x, spot.y, spot.z - 0.5, 0, 0, 0, 0, 0, 0, t.radius * 2.0, t.radius * 2.0, 0.6, 80, 255, 140, 30, false, false, 2, false, nil, nil, false)
                end
            end
            SetEntityVisible(ghost, spot ~= nil, false)
            if ghostHead then SetEntityVisible(ghostHead, spot ~= nil, false) end
            if sf then DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0) end
            if IsDisabledControlJustPressed(0, 44) or IsDisabledControlJustPressed(0, 177) then break end
            if IsDisabledControlJustPressed(0, 38) then
                if spot and ok then placed, pos = true, spot; break
                else PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
            end
        end
        if sf then SetScaleformMovieAsNoLongerNeeded(sf) end
        if ghostHead then DeleteEntity(ghostHead); SetModelAsNoLongerNeeded(hh) end
        DeleteEntity(ghost)
        SetModelAsNoLongerNeeded(hash)
        -- E/Q are still held this frame; keep them off a moment so nothing else reacts.
        local releaseAt = GetGameTimer() + 400
        while GetGameTimer() < releaseAt do
            DisableControlAction(0, 38, true); DisableControlAction(0, 44, true)
            Wait(0)
        end
        G.Busy = false
        if placed then
            TriggerServerEvent('bs:gadgets:deploy', token, { x = pos.x, y = pos.y, z = pos.z }, heading)
        else
            TriggerServerEvent('bs:gadgets:cancel')
        end
    end)
end

local function putDownAnim()
    local ped = PlayerPedId()
    if G.LoadDict('pickup_object') then
        TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 1000, 48, 0, false, false, false)
    end
end

local function placeProp(model, pos, heading)
    local obj, netId = G.SpawnNet(model, pos, heading)
    if not obj then return nil end
    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    return obj, netId
end

-- Object health watcher: true once it has been broken locally. Hits from other players are handled by the server (sv_main PvP), so only own shots, fire and falls are counted here. Nothing in safe zones.
local function hitByOtherPlayer(obj)
    local me = PlayerId()
    for _, p in ipairs(GetActivePlayers()) do
        if p ~= me and HasEntityBeenDamagedByEntity(obj, GetPlayerPed(p), true) then return true end
    end
    return false
end
G.HitByOtherPlayer = hitByOtherPlayer

local function makeHealth(obj, hp)
    SetEntityCanBeDamaged(obj, true)
    SetEntityMaxHealth(obj, 1000)
    SetEntityHealth(obj, 1000)
    local left = hp or 100
    return function()
        if not DoesEntityExist(obj) then return true end
        local h = GetEntityHealth(obj)
        local byPed = HasEntityBeenDamagedByAnyPed(obj)
        if h < 1000 or byPed then
            local skip = LocalPlayer.state.bsFactionSafeZone == true or hitByOtherPlayer(obj)
            if not skip then
                left = left - math.max(0, 1000 - h)
                if byPed and h >= 1000 then left = left - 20 end
            end
            SetEntityHealth(obj, 1000)
            ClearEntityLastDamageEntity(obj)
        end
        return left <= 0
    end
end
G.MakeHealth = makeHealth

-- Sparks and smoke (plus a bang for drones) where a gadget was destroyed. Everyone nearby sees it.
RegisterNetEvent('bs:gadgets:breakFx', function(kind, pos)
    if type(pos) ~= 'vector3' then return end
    local fx = Gadgets.Fx
    Crumb('gadget', 'breakFx %s', tostring(kind))
    if G.LoadFx(fx.breakAsset) then
        UseParticleFxAsset(fx.breakAsset)
        StartParticleFxNonLoopedAtCoord(fx.breakName, pos.x, pos.y, pos.z + 0.3, 0.0, 0.0, 0.0, 1.0, false, false, false)
        UseParticleFxAsset(fx.breakAsset)
        StartParticleFxNonLoopedAtCoord(fx.sparkName, pos.x, pos.y, pos.z + 0.3, 0.0, 0.0, 0.0, 1.0, false, false, false)
        UseParticleFxAsset(fx.breakAsset)
        StartParticleFxNonLoopedAtCoord(fx.smokeName, pos.x, pos.y, pos.z + 0.2, 0.0, 0.0, 0.0, kind == 'drone' and 0.6 or 0.4, false, false, false)
    end
    if kind == 'drone' or kind == 'turret' then
        PlaySoundFromCoord(-1, fx.boomSound, pos.x, pos.y, pos.z, fx.boomSet, false, 60, false)
    end
end)

------------------------------------------------------------------ turret

local function yawTo(from, to) return GetHeadingFromVector_2d(to.x - from.x, to.y - from.y) end
local function angDiff(a, b) return (b - a + 540.0) % 360.0 - 180.0 end

-- Any player standing close to the a->b line (a real bullet could clip them).
local function playerNearLine(a, b, pad)
    local ab = b - a
    local len2 = math.max(0.0001, ab.x * ab.x + ab.y * ab.y + ab.z * ab.z)
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= 0 and not IsEntityDead(ped) then
            local c = GetEntityCoords(ped)
            local k = math.max(0.0, math.min(1.0, ((c - a).x * ab.x + (c - a).y * ab.y + (c - a).z * ab.z) / len2))
            if #(c - (a + ab * k)) < (pad or 1.2) then return true end
        end
    end
    return false
end
G.PlayerNearLine = playerNearLine

-- Static base prop + a separate gun on top. Only the gun turns.
function G.TurretStart(t, pos, heading)
    putDownAnim()
    Wait(700)
    Crumb('gadget', 'turret deploy')
    local base, baseNet = placeProp(t.model, pos, heading)
    if not base then TriggerServerEvent('bs:gadgets:ended', 'turret', 'failed'); return end
    SetEntityCollision(base, true, true)
    local _, top = GetModelDimensions(GetEntityModel(base))
    local gunZ = top.z + (t.headZ or 0.1)
    local gun, gunNet = G.SpawnNet(t.headModel, GetEntityCoords(base) + vector3(0.0, 0.0, gunZ), heading)
    if not gun then G.Delete(base); TriggerServerEvent('bs:gadgets:ended', 'turret', 'failed'); return end
    SetEntityCollision(gun, false, false)
    local fx = Gadgets.Fx
    if fx.deploySound then PlaySoundFromEntity(-1, fx.deploySound, base, fx.deploySet, true, 0) end
    -- VIP cosmetic finish (bs_vip), looks only
    if GetResourceState('bs_vip') == 'started' then
        local ok, skin = pcall(function() return exports.bs_vip:BoosterSkin('turret') end)
        if ok and type(skin) == 'table' then pcall(SetObjectTintIndex, base, skin.tint or 0) end
    end
    TriggerServerEvent('bs:gadgets:attach', 'turret', { baseNet, gunNet })

    local running = true
    G.Stops.turret = function(reason)
        running = false
        G.Delete(gun)
        G.Delete(base)
    end

    local dead = makeHealth(base, t.health)
    local origin = GetEntityCoords(base)
    local baseHead = GetEntityHeading(base)
    local gunYaw = t.gunYaw or 90.0
    local curYaw, wantYaw = baseHead, baseHead      -- world headings
    local curPitch, wantPitch = 0.0, 0.0
    local maxPitch = t.maxPitch or 20.0
    local muzBone = GetEntityBoneIndexByName(gun, 'gun_muzzle')

    local function aimGun()
        AttachEntityToEntity(gun, base, 0, 0.0, 0.0, gunZ, 0.0, -curPitch * (t.pitchSign or 1.0),
            (curYaw - baseHead) + gunYaw, false, false, false, false, 2, true)
    end
    aimGun()

    local function muzzle()
        if muzBone and muzBone ~= -1 then return GetWorldPositionOfEntityBone(gun, muzBone) end
        local mn, mx = GetModelDimensions(GetEntityModel(gun))
        return GetOffsetFromEntityInWorldCoords(gun, mx.x, 0.0, 0.05)
    end

    -- Smooth gun turning, every frame while it has somewhere to turn to.
    CreateThread(function()
        while running do
            local d = angDiff(curYaw, wantYaw)
            local dp = wantPitch - curPitch
            if (math.abs(d) > 0.3 or math.abs(dp) > 0.3) and DoesEntityExist(gun) then
                local step = (t.turnSpeed or 180.0) * GetFrameTime()
                curYaw = (curYaw + math.max(-step, math.min(step, d))) % 360.0
                curPitch = curPitch + math.max(-step, math.min(step, dp))
                aimGun()
                Wait(0)
            else
                Wait(50)
            end
        end
    end)

    -- Scan / fire loop.
    CreateThread(function()
        local nextShot, sweepDir = 0, 1.0
        local sweep = t.sweep or 40.0
        while running do
            local now = GetGameTimer()
            if dead() then
                running = false
                TriggerServerEvent('bs:gadgets:ended', 'turret', 'destroyed')
                break
            end
            local m = muzzle()
            local best, bestD
            for _, ped in ipairs(GetGamePool('CPed')) do
                if G.IsZombie(ped) then
                    local d = #(GetEntityCoords(ped) - origin)
                    if d <= t.range and (not bestD or d < bestD) then best, bestD = ped, d end
                end
            end
            if best then
                -- chest height
                local c = GetPedBoneCoords(best, 24818, 0.0, 0.0, 0.0)
                wantYaw = yawTo(origin, c)
                local flat = math.sqrt((c.x - m.x) ^ 2 + (c.y - m.y) ^ 2)
                wantPitch = math.max(-maxPitch, math.min(maxPitch, math.deg(math.atan(c.z - m.z, flat))))
                local onTarget = math.abs(angDiff(curYaw, wantYaw)) <= (t.fireArc or 15.0)
                if onTarget and now >= nextShot and G.Los(m, c, gun) and not playerNearLine(m, c, 1.2) then
                    local id
                    pcall(function() id = exports.bs_zombies:WalkerIdOf(best) end)
                    if id then
                        TriggerServerEvent('bs:gadgets:turretShot', id, c.x, c.y, c.z, m.x, m.y, m.z)
                        nextShot = now + t.fireMs
                    end
                end
                Wait(50)
            else
                -- idle: slow sweep either side of where it was placed
                wantPitch = 0.0
                local off = angDiff(baseHead, curYaw)
                if off >= sweep - 1.0 then sweepDir = -1.0 elseif off <= -sweep + 1.0 then sweepDir = 1.0 end
                wantYaw = (baseHead + math.max(-sweep, math.min(sweep, off + sweepDir * (t.scanSpeed or 20.0) * 0.5))) % 360.0
                Wait(100)
            end
        end
    end)

    -- Owner pickup prompt.
    CreateThread(function()
        while running do
            local d = #(GetEntityCoords(PlayerPedId()) - origin)
            if d <= Gadgets.PickupDist and not G.Busy then
                G.Help(L('gad.pack_turret'))
                if IsControlJustPressed(0, Gadgets.PickupKey) and not G.Downed() then
                    local a = t.pickupAnim
                    if a and G.LoadDict(a.dict) then
                        TaskPlayAnim(PlayerPedId(), a.dict, a.name, 8.0, -8.0, 1000, 48, 0, false, false, false)
                    end
                    Wait(600)
                    TriggerServerEvent('bs:gadgets:pickup')
                    Wait(1000)
                end
                Wait(0)
            else
                Wait(400)
            end
        end
    end)
end

-- Anyone near a turret sees and hears it fire; `from` is the barrel tip. A local harmless bullet gives the gunshot sound, tracer and impact. The server does the damage (GadgetHit).
RegisterNetEvent('bs:gadgets:shotFx', function(from, to)
    if type(from) ~= 'vector3' or type(to) ~= 'vector3' then return end
    local fx = Gadgets.Fx
    local dir = to - from
    local len = #dir
    if len < 0.5 then return end
    dir = dir / len
    local a = from + dir * 0.25            -- clear of the gun model
    local b = to + dir * 0.6
    local w = joaat(fx.shotWeapon or 'WEAPON_COMBATMG')
    if not HasWeaponAssetLoaded(w) then
        RequestWeaponAsset(w, 31, 0)
        local t = GetGameTimer() + 1000
        while not HasWeaponAssetLoaded(w) and GetGameTimer() < t do Wait(0) end
    end
    if G.LoadFx(fx.muzzleAsset) then
        UseParticleFxAsset(fx.muzzleAsset)
        StartParticleFxNonLoopedAtCoord(fx.muzzleName, from.x, from.y, from.z, 0.0, 0.0, GetHeadingFromVector_2d(dir.x, dir.y), 1.0, false, false, false)
    end
    if HasWeaponAssetLoaded(w) and not playerNearLine(a, b, 1.0) then
        ShootSingleBulletBetweenCoordsIgnoreEntity(a.x, a.y, a.z, b.x, b.y, b.z, 0, true, w, 0, true, false, -1.0, 0, false)
    else
        -- player in the way: just a tracer line, no bullet
        CreateThread(function()
            local tEnd = GetGameTimer() + 60
            while GetGameTimer() < tEnd do
                DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, 255, 190, 90, 200)
                Wait(0)
            end
        end)
    end
end)

------------------------------------------------------------------ beacon

local function ring(pos, radius, untilAt)
    CreateThread(function()
        while GetGameTimer() < untilAt do
            local k = 0.5 + 0.5 * math.sin(GetGameTimer() / 300.0)
            local r = radius * (0.35 + 0.65 * ((GetGameTimer() % 1600) / 1600))
            DrawMarker(25, pos.x, pos.y, pos.z + 0.05, 0, 0, 0, 0, 0, 0, r * 2.0, r * 2.0, 1.0, 80, 255, 140, math.floor(140 * (1.0 - r / radius)) + 20, false, false, 2, false, nil, nil, false)
            DrawMarker(1, pos.x, pos.y, pos.z - 0.9, 0, 0, 0, 0, 0, 0, radius * 2.0, radius * 2.0, 0.8, 80, 255, 140, 28, false, false, 2, false, nil, nil, false)
            DrawLightWithRange(pos.x, pos.y, pos.z + 0.4, 80, 255, 140, 3.0 + k * 2.0, 1.5 + k)
            Wait(0)
        end
    end)
end

function G.BeaconStart(t, pos, heading)
    putDownAnim()
    Wait(700)
    local obj, netId = placeProp(t.model, pos, heading)
    if netId then TriggerServerEvent('bs:gadgets:attach', 'medic', { netId }) end
    local untilAt = GetGameTimer() + t.duration * 1000
    local stopped = false
    G.Stops.medic = function() stopped = true; untilAt = 0; G.Delete(obj) end
    ring(obj and GetEntityCoords(obj) or pos, t.radius, untilAt)
    local dead = obj and makeHealth(obj, t.health) or nil
    CreateThread(function()
        while not stopped and GetGameTimer() < untilAt do
            Wait(300)
            if dead and not stopped and dead() then
                stopped = true; untilAt = 0
                TriggerServerEvent('bs:gadgets:ended', 'medic', 'destroyed')
            end
        end
        if not stopped then untilAt = 0 end
    end)
end

-- Squad mates see the ring too.
RegisterNetEvent('bs:gadgets:beaconFx', function(pos, radius, secs)
    if type(pos) ~= 'vector3' then return end
    ring(pos, tonumber(radius) or 10.0, GetGameTimer() + (tonumber(secs) or 30) * 1000)
end)

------------------------------------------------------------------- decoy

function G.DecoyStart(t, pos, heading)
    putDownAnim()
    Wait(500)
    local obj, netId = placeProp(t.model, pos, heading)
    if not obj then TriggerServerEvent('bs:gadgets:ended', 'decoy', 'failed'); return end
    Crumb('gadget', 'decoy deploy')
    TriggerServerEvent('bs:gadgets:attach', 'decoy', { netId })
    local b = AddBlipForEntity(obj)
    SetBlipSprite(b, 459); SetBlipColour(b, 47); SetBlipScale(b, 0.7)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L('g.blip_decoy')); EndTextCommandSetBlipName(b)
    G.Blips[b] = true

    local running = true
    G.Stops.decoy = function(reason)
        running = false
        if DoesBlipExist(b) then RemoveBlip(b) end
        G.Blips[b] = nil
        G.Delete(obj)
    end

    local dead = makeHealth(obj, t.health)
    CreateThread(function()
        local nextBeep = 0
        while running do
            if dead() then
                running = false
                TriggerServerEvent('bs:gadgets:ended', 'decoy', 'destroyed')
                break
            end
            if GetGameTimer() >= nextBeep and t.sound then
                -- networked, so everyone near it hears the beep
                PlaySoundFromEntity(-1, t.sound, obj, t.soundSet, true, 0)
                nextBeep = GetGameTimer() + t.pulseMs
            end
            Wait(200)
        end
    end)
end
