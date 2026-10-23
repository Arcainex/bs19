-- zwalk-speed probe: the native shims are gone
ZProbe = ZProbe or { task = {}, driven = {}, rate = {} }

-- Only the host of a walker runs this

-- Crash guard: only touch peds that exist
local function pedOk(ped, allowDown)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if not allowDown and (IsPedRagdoll(ped) or IsPedGettingUp(ped)) then return false end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return false end
    return true
end

local S = Zombies.Settings
local function sameHashEarly(a, b)
    if type(a) ~= 'number' or type(b) ~= 'number' then return false end
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end
local relationshipsSet = false

-- The only place that knows about crawlers
local function isCrawler(entry)
    return entry ~= nil and entry.def ~= nil and entry.def.crawls == true
end

-- How far a walker can see you, 1.0 = normal
local function stealthMultiplier(playerId)
    if playerId ~= PlayerId() then return 1.0 end

    local mult = 1.0

    if GetResourceState('bs_skills') == 'started' then
        local ok, value = pcall(function() return exports.bs_skills:StealthMultiplier() end)
        if ok and type(value) == 'number' then mult = mult * value end
    end

    if GetResourceState('bs_inventory') == 'started' then
        local ok, stats = pcall(function() return exports.bs_inventory:EquipmentStats() end)
        if ok and type(stats) == 'table' then
            local hidden = tonumber(stats.stealth) or 0.0
            -- Already capped in Clothing.Aggregate; clamped again here since this is the consumer.
            mult = mult * (1.0 - math.max(0.0, math.min(0.9, hidden)))
        end
    end

    return mult
end

-- Relationship groups

CreateThread(function()
    if relationshipsSet then return end
    AddRelationshipGroup('BS_ZOMBIE')
    local zombie, player = GetHashKey('BS_ZOMBIE'), GetHashKey('PLAYER')
    SetRelationshipBetweenGroups(5, zombie, player)
    SetRelationshipBetweenGroups(5, player, zombie)
    SetRelationshipBetweenGroups(0, zombie, zombie)
    relationshipsSet = true
end)

-- Voice

-- Two voices per walker, picked once at spawn from a hash of the id (not math.random) so each zombie keeps its sound and pitch

-- Scatter an id so consecutive ids land far apart (Knuth multiplicative constant, use the fractional part)
local function hash01(id, salt)
    local x = (id * 2654435761 + (salt or 0) * 40503) % 4294967296
    return (x % 100003) / 100003.0
end

local function voicesFor(id)
    local V = Zombies.Voices or {}
    local lurk = V.lurk or {}
    local eat  = V.eat or {}

    local lurkFile = #lurk > 0
        and lurk[math.floor(hash01(id, 11) * #lurk) + 1] or nil
    -- Different salt, so the two pools are uncorrelated and a given groan does not always pair with the same chewing sound
    local eatFile = #eat > 0
        and eat[math.floor(hash01(id, 37) * #eat) + 1] or nil

    -- This walker's own pitch for life, a multiplier on top of each cue's range
    local pitch = (V.voicePitchRange or 0.18)
    local voicePitch = 1.0 + (hash01(id, 71) * 2.0 - 1.0) * pitch

    return lurkFile, eatFile, voicePitch
end

Zombies.VoicesFor = voicesFor

local function soundsFor(model)
    return Zombies.Sounds[model] or Zombies.Sounds.default
end

-- The voice
local voicing = {}

local function growl(entry, cue)
    local ped = entry.ped
    if not DoesEntityExist(ped) then return end

    local cfg = cue and Zombies.Cues[cue] or nil
    local V   = Zombies.Voices or {}

    -- Which of the two voices this moment wants. Only the eating cue uses the eat voice.
    local file
    if cfg and cfg.voice == 'eat' then
        file = entry.voiceEat
    else
        file = entry.voiceLurk
    end

    -- Dedicated clip for this moment, if one exists
    if cue then
        local pool = V[cue]
        if type(pool) == 'table' and #pool > 0 then
            file = pool[math.floor(hash01(entry.id, 97 + #cue) * #pool) + 1] or file
        end
    end

    -- Only audible close by: skip when the local player is beyond the cap.
    local hearCap = V.hearDistance or 30.0
    do
        local me = GetEntityCoords(PlayerPedId())
        if #(me - GetEntityCoords(ped)) > hearCap then return end
    end

    local volume, maxDistance, pitch
    if cfg then
        volume      = cfg.volume
        maxDistance = cfg.maxDistance
        pitch       = cfg.pitch
    else
        -- No cue: the ambient shamble groan.
        volume      = V.lurkVolume
        maxDistance = V.lurkMaxDistance
        pitch       = V.lurkPitch
    end
    maxDistance = math.min(maxDistance or hearCap, hearCap)

    if file and GetResourceState('bs_ui') == 'started' then
        local rate = 1.0
        if pitch and pitch[1] and pitch[2] then
            rate = pitch[1] + math.random() * (pitch[2] - pitch[1])
        end

        -- Multiplied by this walker's own pitch
        rate = rate * (entry.voicePitch or 1.0)

        local at = GetEntityCoords(ped)
        local ok, played = pcall(function()
            -- Tagged with the walker so it can be stopped
            return exports.bs_ui:PlaySoundAt(file, { x = at.x, y = at.y, z = at.z },
                { volume = volume or 0.55, maxDistance = maxDistance or 30.0,
                  rate = rate, id = 'zed:' .. tostring(entry.id), category = 'zombie' })
        end)

        -- Track the emitter's position only if the sound was accepted (played)
        if ok and played == true then
            voicing[entry.id] = { entry = entry, until_ = GetGameTimer()
                + ((Zombies.Voices or {}).voiceTrackTimeout or 30000) }
        end

        -- Too far to be heard is not a failure. A base-game grunt would be worse than silence.
        if ok and played ~= nil then return end
    end

    -- Base-game ped pain voice, off by default (see the config note)
    if not S.enginePainFallback then return end

    local ids = (cfg and cfg.pain) or soundsFor(entry.model).pain or { 6 }
    PlayPain(ped, ids[math.random(#ids)], 0, false, false)
end

Zombies.Growl = growl

-- Stops everything this walker is saying. Called on death and when it stops feeding.
function Zombies.Silence(id, fadeMs)
    if id == nil then return end
    voicing[id] = nil
    if GetResourceState('bs_ui') ~= 'started' then return end

    -- Ramp, not a cut. fadeMs nil uses the short default in UI.Audio (state change, e.g. stopped feeding).
    local V = Zombies.Voices or {}
    local fade = tonumber(fadeMs) or tonumber(V.stopFade) or 150
    pcall(function() exports.bs_ui:StopSoundTag('zed:' .. tostring(id), fade) end)
end

-- The emitter moved, update the audio engine
CreateThread(function()
    while true do
        local V = Zombies.Voices or {}
        local interval = math.max(50, math.floor(tonumber(V.moveInterval) or 200))
        Wait(interval)

        if next(voicing) ~= nil and GetResourceState('bs_ui') == 'started' then
            local now = GetGameTimer()
            for id, rec in pairs(voicing) do
                local entry = rec.entry
                if now >= rec.until_
                    or entry == nil
                    or not DoesEntityExist(entry.ped) then
                    voicing[id] = nil
                else
                    local at = GetEntityCoords(entry.ped)
                    pcall(function()
                        exports.bs_ui:MoveSoundAt('zed:' .. tostring(id),
                            { x = at.x, y = at.y, z = at.z })
                    end)
                end
            end
        end
    end
end)

-- The page finished a clip, stop moving a sound nobody hears. bs_ui raises this from the audio onended callback.
AddEventHandler('bs:ui:soundEnded', function(soundId)
    if type(soundId) ~= 'string' then return end
    local id = soundId:match('^zed:(.+)$')
    if not id then return end
    voicing[tonumber(id) or id] = nil
end)

-- Perception

-- "Zombie godmode" is its own toggle in bs_admin
local function isZombieGodmoded(playerId)
    local serverId = GetPlayerServerId(playerId)
    if not serverId or serverId == 0 then return false end
    local ok, state = pcall(function() return Player(serverId).state end)
    return ok and state and state.bsZombieGodmode == true
end

-- A replicated statebag lets the client hosting a walker smell a soiled survivor even when that survivor is not the local player
local function soiledScentMultiplier(playerId)
    local serverId = GetPlayerServerId(playerId)
    if not serverId or serverId == 0 then return 1.0 end
    local ok, state = pcall(function() return Player(serverId).state end)
    return ok and state and state.bsSoiled == true and 1.65 or 1.0
end

-- The local player's stealth as one number, sent by cl_sim_stance.lua
Zombies.LocalStealthMultiplier = function()
    local me = PlayerId()
    local a = stealthMultiplier(me) or 1.0
    local ok, b = pcall(soiledScentMultiplier, me)
    return a * ((ok and b) or 1.0)
end

local function findTarget(entry)
    local zPed = entry.ped
    local zCoords = GetEntityCoords(zPed)
    local def = entry.def

    -- A feeding walker barely looks up
    local DET = (Noise and Noise.Detection) or {}
    local SG  = DET.sight or {}

    local typeScale = (def.senseRadius or 28.0)
                    / (SG.referenceSenseRadius or 28.0)

    -- A feeding walker barely looks up: applied to every stance, not only standing.
    local feedScale = (entry.state == 'feeding')
                      and (Zombies.Feeding.senseScale or 0.2) or 1.0

    -- The search bound must be the largest reach any player could have
    local maxReach = (SG.standing or 50.0) * typeScale * feedScale
    local best, bestDist = nil, maxReach + 1.0

    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 and not IsEntityDead(ped) and not isZombieGodmoded(playerId) then
            local dist = #(GetEntityCoords(ped) - zCoords)

            if dist < bestDist then
                -- Stance picks the range outright instead of scaling it
                local prone = false
                if GetResourceState('bs_emotes') == 'started' and playerId == PlayerId() then
                    local ok, isProne = pcall(function() return exports.bs_emotes:IsProne() end)
                    prone = (ok and isProne) and true or false
                end

                local ducking = IsPedDucking(ped) and true or false
                local low = prone or ducking

                local stanceRange
                if prone then stanceRange = SG.prone or 6.0
                elseif ducking then stanceRange = SG.crouched or 10.0
                else stanceRange = SG.standing or 50.0 end

                -- Learned and worn stealth still apply on top, multiplied (see stealthMultiplier).
                local reach = stanceRange * typeScale * feedScale
                            * stealthMultiplier(playerId)
                            * soiledScentMultiplier(playerId)

                -- Vision cone, kept here and not in the noise code: a noise only makes a walker walk somewhere and must never give it a target
                local det = (Noise and Noise.Detection) or nil
                local sensed = dist <= reach

                -- Crouched and behind a walker should be zero range. contactRadius (3.5m) is the grace where
                local contact = low
                    and ((det and det.sight and det.sight.crouchedContactRadius) or 1.2)
                    or ((det and det.contactRadius) or 3.5)

                if sensed and det and dist > contact then
                    local fwd = GetEntityForwardVector(zPed)
                    local ddx, ddy = GetEntityCoords(ped).x - zCoords.x,
                                     GetEntityCoords(ped).y - zCoords.y
                    local flen = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
                    local dlen = math.sqrt(ddx * ddx + ddy * ddy)

                    -- A zero-length forward vector, or a target directly underfoot, means unknown facing
                    if flen > 0.01 and dlen > 0.01 then
                        local dot = ((ddx / dlen) * (fwd.x / flen))
                                  + ((ddy / dlen) * (fwd.y / flen))
                        if dot < math.cos(math.rad(det.visionHalfAngle or 80.0)) then
                            sensed = false
                        end
                    end
                end

                if sensed and HasEntityClearLosToEntity(zPed, ped, 17) then
                    best, bestDist = ped, dist
                end
            end
        end
    end

    return best, bestDist
end

-- Behaviour

-- Three speeds: shamble, investigate, chase
local function setChase(entry, on)
    local rate
    if on == 'drawn' then
        rate = entry.def.drawnRate or entry.def.chaseRate or entry.def.shambleRate
    elseif on then
        rate = entry.def.chaseRate
    else
        rate = entry.def.shambleRate
    end

    -- The ceiling, see Settings.maxMoveRate
    if S.maxMoveRate and rate and rate > S.maxMoveRate then
        rate = S.maxMoveRate
    end
    -- Difficulty speed, capped by Difficulty.speedCeiling.
    local zf = ZDiff.Local('speed')
    if rate and zf ~= 1.0 then rate = ZDiff.Rate(rate, zf) end

    entry.moveRate = rate
    -- Drunk walkers: no move-rate override at all unless the F1 drunk speed option is on.
    local g0 = entry.gait
    if rate and (not (type(g0) == 'string' and g0:find('drunk', 1, true)) or (zf ~= 1.0 and ZDiff.SpeedOnDrunk())) then
        SetPedMoveRateOverride(entry.ped, rate)
    end

    -- entry.gait is this walker's own drunk clipset, picked at spawn
    if entry.def.noClipset then return end

    local set
    if on == true then
        -- chaseAnim is ignored while the ceiling is on
        local chaseAnim = (not S.maxMoveRate) and entry.def.chaseAnim or nil
        -- Keep its own drunk walk while chasing (switching sets mid-chase resets the blend).
        set = chaseAnim or entry.gait or Zombies.Anims.shamble
    else
        -- Investigating keeps its own walk. Only committing to a target changes how a walker moves.
        set = entry.gait or Zombies.Anims.shamble
    end

    if not HasAnimSetLoaded(set) then
        RequestAnimSet(set)
    end
    if HasAnimSetLoaded(set) and pedOk(entry.ped) then
        -- Only when it differs: re-applying restarts the clipset blend and the stagger never settles.
        local ok, cur = pcall(GetPedMovementClipset, entry.ped)
        if not (ok and sameHashEarly(cur, GetHashKey(set))) then
            SetPedMovementClipset(entry.ped, set, 0.25)
        end
    end
end

-- Drifting, not wandering

-- Walk there, but go around obstacles
local function blockedBetween(ped, a, x, y, z)
    local h = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z + 0.3, x, y, (z or a.z) + 0.3, 1 | 16, ped, 7)
    local _, hit = GetShapeTestResult(h)
    return hit == 1 or hit == true
end

local function walkTo(ped, x, y, z, timeout, slide)
    local a = GetEntityCoords(ped)
    if (Zombies.Settings or {}).contourObstacles ~= false and blockedBetween(ped, a, x, y, z) then
        TaskFollowNavMeshToCoord(ped, x, y, z or a.z, 1.0, (timeout and timeout > 0) and timeout or 8000, slide or 1.0, false, 0.0)
    else
        TaskGoStraightToCoord(ped, x, y, z or a.z, 1.0, timeout or -1, 0.0, slide or 0.5)
    end
end

local DRIFT = {
    legMin      = 3.0,     -- shortest aimless leg, metres
    legMax      = 11.0,
    longLegMin  = 18.0,    -- the "keeps walking forward" leg
    longLegMax  = 34.0,
    longChance  = 0.14,    -- how often a leg is a long committed one
    pauseMin    = 1200,    -- standing still between legs, ms
    pauseMax    = 5200,
    leash       = 25.0,    -- how far a walker strays from its drift anchor
    anchorLerp  = 0.02,    -- how fast the anchor follows the walker
}

-- Pick the next aimless destination for a walker and task it there
local function driftStep(entry, now)
    local at = GetEntityCoords(entry.ped)

    -- The anchor is created on first use and creeps toward the walker
    if not entry.driftAnchor then
        entry.driftAnchor = at
    else
        local a = entry.driftAnchor
        entry.driftAnchor = vector3(
            a.x + (at.x - a.x) * DRIFT.anchorLerp,
            a.y + (at.y - a.y) * DRIFT.anchorLerp,
            a.z + (at.z - a.z) * DRIFT.anchorLerp)
    end

    local long = math.random() < DRIFT.longChance
    local dist = long
        and (DRIFT.longLegMin + math.random() * (DRIFT.longLegMax - DRIFT.longLegMin))
        or  (DRIFT.legMin + math.random() * (DRIFT.legMax - DRIFT.legMin))

    -- A long leg keeps roughly its previous heading (+/-40 degrees) so it reads as still going
    local bearing
    if long then
        bearing = math.rad(GetEntityHeading(entry.ped) + (math.random() * 80.0 - 40.0))
    else
        bearing = math.random() * math.pi * 2.0
    end

    local tx = at.x - math.sin(bearing) * dist
    local ty = at.y + math.cos(bearing) * dist

    -- Leash: a destination outside the home radius is replaced by one aimed back toward the anchor
    local anchor = entry.driftAnchor
    local ax, ay = tx - anchor.x, ty - anchor.y
    if (ax * ax + ay * ay) > (DRIFT.leash * DRIFT.leash) then
        local home = math.atan(anchor.y - at.y, anchor.x - at.x)
            + (math.random() * 1.6 - 0.8)
        tx = at.x + math.cos(home) * dist
        ty = at.y + math.sin(home) * dist
    end

    -- z is left as the walker's own: TaskGoStraightToCoord walks the ground it finds
    if not pedOk(entry.ped) then return end
    walkTo(entry.ped, tx, ty, at.z, 8000, 1.5)

    entry.driftUntil = now + (long and 14000 or 9000)
    entry.driftPause = nil
end

-- Milling state is cleared by goIdle and goHunt
local function goIdle(entry)
    if entry.state == 'idle' then return end
    entry.state = 'idle'
    entry.hunted = nil
    entry.drawnTo = nil
    entry.millUntil, entry.millAt, entry.nextLeg = nil, nil, nil
    entry.chasingSince = nil
    setChase(entry, false)
    if Zombies.SetReaching then Zombies.SetReaching(entry, false) end

    -- A crawler is not cleared and not drift-tasked
    if isCrawler(entry) then return end

    ClearPedTasks(entry.ped)

    -- Straight into a leg rather than a pause, so a walker that loses you shambles off instead of standing where it gave up
    entry.driftUntil = nil
    entry.driftPause = nil
    driftStep(entry, GetGameTimer())
end

-- Feeding

-- The meal: a dead body for the walker to crouch over
local function mealFor(id)
    local meals = Zombies.Feeding.meals or {}
    if #meals == 0 then return nil end

    local total = 0
    for _, m in ipairs(meals) do total = total + (m.weight or 1) end

    -- A deterministic roll from the id, not math.random.
    local roll = ((id * 1103515245 + 12345) % 10000) / 10000.0 * total
    for _, m in ipairs(meals) do
        roll = roll - (m.weight or 1)
        if roll <= 0 then return m end
    end
    return meals[#meals]
end

-- Player bodies (bs_medical) a walker can feed on instead of a spawned meal.
local function playerCorpseNear(coords, radius)
    local best, bestD = nil, radius
    for _, ped in ipairs(GetGamePool('CPed')) do
        local st = Entity(ped).state
        if st and st.bsCorpse then
            local d = #(GetEntityCoords(ped) - coords)
            if d <= bestD then best, bestD = ped, d end
        end
    end
    return best, bestD
end

local function spawnMeal(entry)
    if entry.meal and DoesEntityExist(entry.meal) then return entry.meal end

    local pick = mealFor(entry.id)
    if not pick then return nil end

    local hash = GetHashKey(pick.model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 3000 do Wait(50); waited = waited + 50 end
    if not HasModelLoaded(hash) then return nil end

    -- The walker may be gone after the 3 second wait in that loop (mass spawns are dense with deaths)
    if Zed.live[entry.id] ~= entry
       or entry.dying
       or entry.state ~= 'feeding'
       or not entry.ped
       or not DoesEntityExist(entry.ped) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    -- Placed by the meal's actual size, not a fixed 0.7m: a deer is about two metres long and a walker at 0.7m would stand inside it
    local at  = GetEntityCoords(entry.ped)
    local h   = GetEntityHeading(entry.ped)
    local rad = math.rad(h)

    local reach, mealHeading = 0.7, h + 180.0

-- Guarded: GetModelDimensions faults inside the streamer when the model is not resident. pcall
    local resident = false
    do
        local okValid, valid = pcall(IsModelValid, hash)
        if okValid and valid then
            local okLoaded, loaded = pcall(HasModelLoaded, hash)
            resident = okLoaded and loaded or false
        end
    end

    local okDim, mn, mx3 = false, nil, nil
    if resident then okDim, mn, mx3 = pcall(GetModelDimensions, hash) end

    if okDim and mn and mx3 then
        local dims = { math.abs(mx3.x - mn.x), math.abs(mx3.y - mn.y), math.abs(mx3.z - mn.z) }
        table.sort(dims)
        local width, length = dims[2], dims[3]

        -- Half its width (it lies across the walker's line of sight), plus a little room to kneel.
        reach = 0.45 + (width * 0.5)

        -- Broadside for anything longer than a large dog: 90 degrees from the walker's heading puts its flank across the front
        if length > 1.2 then mealHeading = h + 90.0 end
    end

    local mx = at.x - math.sin(rad) * reach
    local my = at.y + math.cos(rad) * reach

    -- On the ground, not a guessed offset
    local mz = at.z - 0.9
    local okGround, groundZ = GetGroundZFor_3dCoord(mx + 0.0, my + 0.0, at.z + 1.0, false)
    if okGround and math.abs(groundZ - at.z) < 5.0 then mz = groundZ end

    local ped = CreatePed(4, hash, mx, my, mz, mealHeading % 360.0, false, false)

    -- Do not call SetModelAsNoLongerNeeded here
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    -- Claimed in the same table the walkers use so bs_world's ambient sweep leaves it alone.
    Zed.owned[ped] = entry.id

    pcall(SetEntityAsMissionEntity, ped, true, true)

    -- Silence the ped before killing it: a death on a fresh civilian plays its death vocal, which sounds like the zombie
    pcall(DisablePedPainAudio, ped, true)
    pcall(SetAmbientVoiceName, ped, 'ALIENS')
    pcall(SetPedConfigFlag, ped, 166, true)

    pcall(SetEntityHealth, ped, 0)          -- dead on arrival, it is a corpse
    pcall(SetEntityInvincible, ped, true)   -- and nothing may interact with it
    -- Collision on and not frozen, so the corpse settles on the ground instead of hovering or sinking
    pcall(SetEntityCollision, ped, true, true)
    pcall(SetPedCanRagdoll, ped, true)

    -- No collision between corpse and walker, otherwise a big corpse pushes the walker upward
    pcall(SetEntityNoCollisionEntity, ped, entry.ped, true)
    pcall(SetEntityNoCollisionEntity, entry.ped, ped, true)
    pcall(SetBlockingOfNonTemporaryEvents, ped, true)

    -- Civilians get stacked damage packs so they look mauled. Animals are left alone.
    if pick.civilian then
        pcall(ApplyPedDamagePack, ped, 'BigHitByVehicle', 0.0, 9.0)
        pcall(ApplyPedDamagePack, ped, 'SCR_Dst_Shot_Torso', 0.0, 9.0)
        pcall(ApplyPedDamagePack, ped, 'Explosion_Med', 0.0, 9.0)
        pcall(SetPedBloodDamageByZone, ped, 3, 0.0, 0.0, 0.0)
    end

    -- Small animal: held in the walker's hand instead of lying on the ground.
    local held = (Zombies.Feeding.handHeld or {})[pick.model]
    if held then
        local pos, rot = held.pos or { 0.12, 0.02, -0.02 }, held.rot or { 0.0, -90.0, 0.0 }
        local okBone, bone = pcall(GetPedBoneIndex, entry.ped, held.bone or 57005)
        if okBone and bone then
            pcall(SetEntityCollision, ped, false, false)
            pcall(AttachEntityToEntity, ped, entry.ped, bone,
                pos[1] + 0.0, pos[2] + 0.0, pos[3] + 0.0, rot[1] + 0.0, rot[2] + 0.0, rot[3] + 0.0,
                false, false, false, false, 2, true)
            entry.mealHeld = true
        end
    end

    entry.meal = ped
    return ped
end

local function clearMeal(entry)
    entry.feedOn = nil   -- a player body is never ours to delete
    if entry.meal then
        -- Detach a held meal first so it is not deleted while attached to a walker.
        if entry.mealHeld and DoesEntityExist(entry.meal) then pcall(DetachEntity, entry.meal, true, false) end
        -- Delete through Zed.DestroyPed so every ped-keyed cache is cleared before the handle is released
        Zed.DestroyPed(entry.meal)
        entry.meal = nil
        entry.mealHeld = nil
    end
end

Zombies.ClearMeal = clearMeal

-- On death the meal is handed over instead of deleted
local lingering = {}

local function relinquishMeal(entry)
    entry.feedOn = nil   -- a player body is never ours to delete
    if not entry.meal then return end

    if DoesEntityExist(entry.meal) then
        -- Held animal falls out of the hands as decoration.
        if entry.mealHeld then
            pcall(DetachEntity, entry.meal, true, false)
            pcall(SetEntityCollision, entry.meal, true, true)
            if NetworkHasControlOfEntity(entry.meal) or not NetworkGetEntityIsNetworked(entry.meal) then
                pcall(SetPedToRagdoll, entry.meal, 2000, 2000, 0, false, false, false)
            end
        end
        -- The model is stored with the deadline so the sweep can tell our meal from a recycled handle.
        lingering[entry.meal] = {
            diesAt = GetGameTimer()
                + ((Zombies.Feeding.mealLingerSeconds or 90) * 1000),
            model  = BS.Util.ModelOf(entry.meal),
        }
    else
        Zed.ForgetPed(entry.meal)
    end

    entry.meal = nil
    entry.mealHeld = nil
end

Zombies.RelinquishMeal = relinquishMeal

-- IsWalkerPed also accepts lingering meals
function Zombies.IsLingeringMeal(ped)
    return ped ~= nil and lingering[ped] ~= nil and DoesEntityExist(ped)
end

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        -- Iterate a copy of the keys and delete through Zed.DestroyPed
        local stale = {}
        for ped in pairs(lingering) do stale[#stale + 1] = ped end

        for _, ped in ipairs(stale) do
            local row = lingering[ped]
            local diesAt = type(row) == 'table' and row.diesAt or row

            if not DoesEntityExist(ped) then
                lingering[ped] = nil
                Zed.ForgetPed(ped)

            elseif type(row) == 'table' and row.model
                   and BS.Util.ModelOf(ped) ~= row.model then
                -- The handle now belongs to something else: forget it, do not delete.
                lingering[ped] = nil

            elseif now >= (diesAt or 0) then
                lingering[ped] = nil
                Zed.DestroyPed(ped)
            end
        end
    end
end)

-- Register this file's ped-keyed caches with Zed.OnPedForgotten so any delete clears them first.
if Zed and Zed.OnPedForgotten then
    Zed.OnPedForgotten('cl_ai meals', function(ped)
        for _, entry in pairs(Zed.live or {}) do
            if entry.meal == ped then entry.meal = nil end
        end
        lingering[ped] = nil
    end)
end

-- On shutdown Zed.owned still has the meals so releaseEverything() collects them; this only clears the timer table
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then lingering = {} end
end)

-- Eating uses a played animation
local EAT_CANDIDATES = {
    { 'amb@medic@standing@kneel@idle_a',        'idle_a' },
    { 'anim@gangops@facility@servers@bodysearch@', 'player_search' },
    { 'amb@medic@standing@kneel@base',          'base' },
}

local EAT_DICT, EAT_ANIM = EAT_CANDIDATES[1][1], EAT_CANDIDATES[1][2]
local eatAnnounced = false

local function playEating(entry)
    local ped = entry.ped
    if not DoesEntityExist(ped) then return end
    -- Tasking a remote clone can crash the game
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    if IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) then return end

    for _, pair in ipairs(EAT_CANDIDATES) do
        local dict, anim = pair[1], pair[2]

        if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end

        if HasAnimDictLoaded(dict) then
            -- Flag 1 loops. Duration -1 runs until stopFeeding or the reconciler stops it.
            local ok = pcall(TaskPlayAnim, ped, dict, anim,
                             8.0, -8.0, -1, 1, 0.0, false, false, false)
            if ok then
                EAT_DICT, EAT_ANIM = dict, anim
                entry.eatAnim = true

                if not eatAnnounced then
                    eatAnnounced = true
                    print(('^5[BeyondSurvival]^7 (zombies) eating animation: %s / %s')
                        :format(dict, anim))
                end
                return
            end
        end
    end

    -- Dict not loaded yet: just wait, the think loop retries shortly
end

-- Feeding visuals (meal ped and kneel) run on every client
local function applyFeedingVisuals(entry)
    playEating(entry)

    if entry.meal and DoesEntityExist(entry.meal) then return end
    if entry.feedOn and DoesEntityExist(entry.feedOn) then return end

    -- Kneeling at a player body: that is the meal, nothing to spawn.
    local body = DoesEntityExist(entry.ped) and playerCorpseNear(GetEntityCoords(entry.ped), 3.0)
    if body then entry.feedOn = body return end

    if entry.mealPending then return end
    entry.mealPending = true

    CreateThread(function()
        local ok, err = pcall(spawnMeal, entry)
        entry.mealPending = nil

        if not ok then
            print(('^1[BeyondSurvival]^7 (zombies) meal for walker %s failed: %s')
                :format(tostring(entry.id), tostring(err)))
        end
    end)
end

local function clearFeedingVisuals(entry)
    -- Stop the eating voice right away instead of letting the clip run out.
    Zombies.Silence(entry.id, (Zombies.Voices or {}).stopFade)
    relinquishMeal(entry)  -- corpse stays as decoration
    if DoesEntityExist(entry.ped) then pcall(ClearPedTasks, entry.ped) end
    entry.eatAnim = nil
end

Zombies.ApplyFeedingVisuals = applyFeedingVisuals
Zombies.ClearFeedingVisuals = clearFeedingVisuals

local function goFeed(entry)
    if entry.state == 'feeding' then return end
    Crumb('zfeed', 'start id=%s', tostring(entry.id))

    entry.state = 'feeding'
    entry.hunted = nil
    entry.drawnTo = nil
    entry.chasingSince = nil

    setChase(entry, false)
    if Zombies.SetReaching then Zombies.SetReaching(entry, false) end

    ClearPedTasks(entry.ped)
    applyFeedingVisuals(entry)

    -- Next noise is an eating one, soon (see the voice branch in the think loop).
    entry.nextSound = GetGameTimer() + math.random(400, 1800)
end

Zombies.GoFeed = goFeed

-- Single exit for stopping a feed: cleans up the meal, drops the scenario and returns to idle
local function stopFeeding(entry)
    if entry.state ~= 'feeding' then return end
    Crumb('zfeed', 'stop id=%s', tostring(entry.id))

    clearFeedingVisuals(entry)

    -- goIdle returns early when already idle, so force another state first.
    entry.state = 'disturbed'
    goIdle(entry)
end

Zombies.StopFeeding = stopFeeding

-- The server picks targets (sv_net_target.lua); this turns the zTarget/zTgtWhy bags into a ped
local nolosSentAt = {}
local function serverTarget(entry, now)
    local okS, st = pcall(function() return Entity(entry.ped).state end)
    if not okS or not st then return nil end
    local who = st.zTarget
    if type(who) ~= 'number' then return nil end
    local pl = GetPlayerFromServerId(who)
    if not pl or pl == -1 then return nil end
    local ped = GetPlayerPed(pl)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return nil end
    if st.zTgtWhy == 'sight' and not HasEntityClearLosToEntity(entry.ped, ped, 17) then
        local key = entry.id .. ':' .. who
        if now - (nolosSentAt[key] or 0) > 1000 then
            nolosSentAt[key] = now
            TriggerServerEvent('bs:z:nolos', entry.id, who)
        end
        return nil
    end
    entry.lastSeen = now
    return ped
end

local function goHunt(entry, target)
    -- Acquiring a player ends any investigation.
    entry.millUntil, entry.millAt, entry.nextLeg = nil, nil, nil
    local now = GetGameTimer()

    if entry.state ~= 'hunting' then
        -- Lurch: a short delay before committing to the chase.
        if not entry.aggroAt then
            entry.aggroAt = now + (entry.def.aggroDelay or 900)
            growl(entry, 'alerted')
            return
        end
        if now < entry.aggroAt then return end

        entry.state = 'hunting'
        entry.aggroAt = nil
        setChase(entry, true)
        if Zombies.SetReaching then Zombies.SetReaching(entry, true) end
        if entry.def.screams then Zombies.Scream(entry) end
    end

    entry.hunted = target
    entry.lastSeen = now

    -- Grabbing is decided by the grabbed client, usually the host, so try here first.
    if Zombies.TryGrab and target == PlayerPedId() and Zombies.TryGrab(entry) then return end

    -- GO_TO, never COMBAT (combat makes peds box and circle)
    if isCrawler(entry) then return end

    if not entry.chasingSince or (now - entry.chasingSince) > 900 then
        entry.chasingSince = now
        -- Speed 1.0 = walk, 2.0 = run (move-blend ratio, not a multiplier).
    if pedOk(entry.ped) and DoesEntityExist(target) then
        TaskGoToEntity(entry.ped, target, -1, 0.8, 1.0, 0.0, 0)
    end
    end

    -- TaskGoToEntity gives up when the target is off the navmesh (on a prop, over a wall)
    if pedOk(entry.ped) and DoesEntityExist(target) then
        local d = #(GetEntityCoords(entry.ped) - GetEntityCoords(target))
        if d > 2.0 and GetEntitySpeed(entry.ped) < 0.3 then
            entry.huntStuckSince = entry.huntStuckSince or now
            if now - entry.huntStuckSince > 1500 then
                local p = GetEntityCoords(target)
                TaskGoStraightToCoord(entry.ped, p.x, p.y, p.z, 1.0, -1, 0.0, 0.5)
                entry.huntStuckSince = nil
                entry.chasingSince = now + 1600   -- let the straight walk run before re-pathing
            end
        else
            entry.huntStuckSince = nil
        end
    end
end

-- Deadline is computed from the real distance and travel speed with a margin, capped, so far-away noises still get reached
local function investigatePoint(entry, coords)
    local inv = (Noise and Noise.Investigate) or {}
    local lo = inv.spreadMin or 8.0
    local hi = math.max(lo, inv.spreadMax or 22.0)
    if hi <= 0.0 then return coords end

    -- Hash the id with primes so consecutive ids do not give consecutive angles.
    local id = tonumber(entry.id) or 0
    local a = ((id * 2654435761) % 3600) / 3600.0
    local r = ((id * 40503) % 997) / 997.0

    local angle = a * math.pi * 2.0
    local radius = lo + r * (hi - lo)

    return vector3(coords.x + math.cos(angle) * radius,
                   coords.y + math.sin(angle) * radius,
                   coords.z)
end

local function goDrawn(entry, coords)
    if entry.state == 'hunting' or entry.state == 'grab' then return end

    -- Constant noise must not pin a walker in 'drawn': repeats of the same spot are ignored and a short cooldown follows investigating
    local nowT = GetGameTimer()
    if nowT < (entry.drawnCooldown or 0) then return end
    if entry.state == 'drawn' and entry.drawnOrigin
       and #(entry.drawnOrigin - coords) < 20.0 then return end
    entry.drawnOrigin = coords

    -- The offset point is stored once here; drawnTo is read by the arrival test and cl_crawl.
    coords = investigatePoint(entry, coords)

    -- A noise loud enough to get here wakes a feeder off its meal.
    if entry.state == 'feeding' then relinquishMeal(entry) end

    entry.state = 'drawn'
    entry.drawnTo = coords
    -- A re-point restarts the walk, not the mill.
    entry.millUntil, entry.millAt, entry.nextLeg = nil, nil, nil

    local at = GetEntityCoords(entry.ped)
    local distance = #(at - coords)

    -- Rough metres per second at the investigating rate (1.45 is the base walk)
    local rate = entry.def.drawnRate or entry.def.chaseRate or 0.6
    local seconds = (distance / math.max(0.2, 1.45 * rate)) * 2.0

    entry.drawnUntil = GetGameTimer()
        + math.floor(math.max(20000, math.min(180000, seconds * 1000)))

    setChase(entry, 'drawn')

    -- Crawlers investigate via entry.drawnTo alone (cl_crawl.lua drags them there); clearing tasks would cancel the crawl animation
    if isCrawler(entry) then growl(entry); return end

    ClearPedTasks(entry.ped)
    -- Straight walk, not navmesh: the navmesh task ignores the drunk clipset stagger
    TaskGoStraightToCoord(entry.ped, coords.x, coords.y, coords.z, 1.0, -1, 0.0, 0.5)
    entry.drawnStraightAt = nowT
    entry.drawnBest, entry.drawnBestAt, entry.drawnHopUntil = distance, nowT, nil
    growl(entry)
end

Zombies.Draw = goDrawn

-- Think loop - hosted walkers only

CreateThread(function()
    while true do
        Wait(90)

        if not exports.bs_core:IsLoaded() then goto continue end

        local now = GetGameTimer()

        for id, entry in pairs(Zed.live) do
            if not DoesEntityExist(entry.ped) then goto nextZombie end
            if IsEntityDead(entry.ped) or entry.dying then goto nextZombie end
            -- Down but not dead: let it lie there instead of chasing while it cannot stand.
            if IsPedRagdoll(entry.ped) then goto nextZombie end

            -- Voice runs on every client, hosted or not.
            if now >= entry.nextSound then
                -- Feeding walkers use the eating sound on a shorter interval than the ambient groan
                local feeding = entry.state == 'feeding'
                local V = Zombies.Voices or {}

                local range = feeding
                    and (V.eatInterval or { 6000, 11000 })
                    or  (V.lurkInterval or { 14000, 26000 })
                entry.nextSound = now + math.random(range[1], range[2])

                local cfg = feeding
                    and (Zombies.Cues.eating or {})
                    or  { maxDistance = V.lurkMaxDistance }

                -- Check earshot before speaking so out-of-range walkers do not cross the resource boundary or
                local heard = cfg.maxDistance or 24.0
                local me = GetEntityCoords(PlayerPedId())
                if #(GetEntityCoords(entry.ped) - me) <= heard then
                    growl(entry, feeding and 'eating' or nil)
                end
            end

            -- Feeding visuals are reconciled against entry.state on every client, so this sits above the host gate
            if entry.state == 'feeding' then
                if not IsPedRagdoll(entry.ped) then
                    if (not entry.meal or not DoesEntityExist(entry.meal))
                       and (not entry.feedOn or not DoesEntityExist(entry.feedOn)) then
                        applyFeedingVisuals(entry)
                    elseif not IsEntityPlayingAnim(entry.ped, EAT_DICT, EAT_ANIM, 3)
                           and not IsPedActiveInScenario(entry.ped) then
                        playEating(entry)
                    end
                end
            elseif entry.meal or entry.feedOn then
                clearFeedingVisuals(entry)
            end

            -- Everything below is thinking, which belongs to the host.
            if not entry.hosted then goto nextZombie end
            if entry.state == 'grab' then
                entry.grabSince = entry.grabSince or now
                if now - entry.grabSince > 3000 then
                    entry.state, entry.grabSince = 'hunting', nil
                else
                    goto nextZombie
                end
            else
                entry.grabSince = nil
            end

            if now < entry.nextThink then goto nextZombie end
            entry.nextThink = now + S.aiTick + math.random(-60, 60)

            -- The move rate is re-applied every think tick: SetPedMoveRateOverride resets on task changes, which happen constantly
            do
                local want = entry.def.shambleRate
                if entry.state == 'hunting' then
                    want = entry.def.chaseRate or want
                elseif entry.state == 'drawn' then
                    want = entry.def.drawnRate or want
                end

                if S.maxMoveRate and want and want > S.maxMoveRate then
                    want = S.maxMoveRate
                end
                local zf = ZDiff.Local('speed')
                if want and zf ~= 1.0 then want = ZDiff.Rate(want, zf) end

                -- Drunk gaits carry their own speed; a move-rate override pushes the ped onto generic locomotion
                local g = entry.gait or Zombies.Anims.shamble
                if want and (not (type(g) == 'string' and g:find('drunk', 1, true)) or (zf ~= 1.0 and ZDiff.SpeedOnDrunk())) then
                    pcall(SetPedMoveRateOverride, entry.ped, want)
                    entry.moveRate = want
                end

                -- SetPedMaxMoveBlendRatio caps what the ped can do (1 walk, 2 run, 3 sprint), which keeps walkers from running
                if not (type(g) == 'string' and g:find('drunk', 1, true)) then
                    pcall(SetPedMaxMoveBlendRatio, entry.ped, entry.def.maxBlend or 1.0)
                end

                -- No climbing/vaulting/ladders, ever. Re-applied here since task changes can reset it.
                local mob = Zombies.Mobility
                if mob and mob.reassertOnThink ~= false then
                    pcall(SetPedPathCanUseClimbovers, entry.ped, mob.pathClimbovers == true)
                    pcall(SetPedPathCanUseLadders, entry.ped, mob.pathLadders == true)
                    pcall(SetPedPathCanDropFromHeight, entry.ped, mob.pathDropFromHeight == true)
                    for _, pair in ipairs(mob.configFlags or {}) do
                        pcall(SetPedConfigFlag, entry.ped, pair[1], pair[2] == true)
                    end
                end

                -- Re-apply the gait: ClearPedTasksImmediately strips the movement clipset on revive and hard re-tasks
            end

            local target
            if entry.net and GlobalState.bsZTargetServer then
                target = serverTarget(entry, now)
            else
                target = findTarget(entry)
            end

            if target then
                goHunt(entry, target)
            elseif entry.state == 'hunting' then
                local since = now - (entry.lastSeen or 0)
                if since > (entry.def.persistence or 9000) then
                    goIdle(entry)
                elseif entry.hunted and DoesEntityExist(entry.hunted)
                       and not isCrawler(entry) then
                    -- Not for a crawler: a task would cancel its crawl. cl_crawl.lua keeps it walking to entry.hunted for as long as persistence lasts.
                    local last = GetEntityCoords(entry.hunted)
                    -- 1.0 = walk.
                    if pedOk(entry.ped) then
                        walkTo(entry.ped, last.x, last.y, last.z, -1, 2.0)
                    end
                end
            elseif entry.state == 'drawn' then
                -- Arrival is the middle of the behaviour
                local inv = (Noise and Noise.Investigate) or {}

                if now > (entry.drawnUntil or 0) then
                    entry.drawnOrigin = nil
                    entry.drawnCooldown = now + (inv.cooldownMs or 15000)
                    goIdle(entry)
                elseif entry.drawnTo and not entry.millUntil and not isCrawler(entry)
                       and pedOk(entry.ped)
                       and #(GetEntityCoords(entry.ped) - entry.drawnTo) >= (inv.arriveDistance or 6.0) then
                    -- En route: straight walk (keeps the stagger), progress watchdog, rare navmesh hop around obstacles
                    local pos = GetEntityCoords(entry.ped)
                    local d = #(pos - entry.drawnTo)
                    if d < (entry.drawnBest or math.huge) - 0.5 then
                        entry.drawnBest, entry.drawnBestAt = d, now
                    end
                    if entry.drawnHopUntil and now < entry.drawnHopUntil then
                        -- hopping; leave the navmesh task alone
                    elseif now - (entry.drawnBestAt or now) > 4000 then
                        local dir = entry.drawnTo - pos
                        local len = math.max(0.01, #dir)
                        local step = math.min(8.0, len)
                        local hx, hy = pos.x + dir.x / len * step, pos.y + dir.y / len * step
                        TaskFollowNavMeshToCoord(entry.ped, hx, hy, entry.drawnTo.z, 1.0, 5000, 1.0, false, 0.0)
                        entry.drawnHopUntil = now + 5000
                        entry.drawnBest, entry.drawnBestAt = d, now + 5000
                        entry.drawnStraightAt = now + 5000
                    elseif now - (entry.drawnStraightAt or 0) > 2500 then
                        entry.drawnHopUntil = nil
                        local c = entry.drawnTo
                        walkTo(entry.ped, c.x, c.y, c.z, -1, 0.5)
                        entry.drawnStraightAt = now
                    end
                elseif entry.drawnTo
                       and #(GetEntityCoords(entry.ped) - entry.drawnTo) < (inv.arriveDistance or 6.0) then
                    if not entry.millUntil then
                        -- Arrived. Roll this walker's own mill length.
                        local base = (inv.millSeconds or 70) * 1000
                        local jit = inv.millJitter or 0.45
                        entry.millUntil = now + math.floor(base * (1.0 - jit + math.random() * jit * 2.0))
                        entry.millAt = entry.drawnTo
                        entry.nextLeg = 0
                    end

                    if now > entry.millUntil then
                        entry.millUntil, entry.millAt, entry.nextLeg = nil, nil, nil
                        entry.drawnOrigin = nil
                        entry.drawnCooldown = now + (inv.cooldownMs or 15000)
                        goIdle(entry)
                    elseif now > (entry.nextLeg or 0) then
                        -- One short leg around the point
                        local pause = inv.legPauseMs or { 1200, 4200 }
                        entry.nextLeg = now + math.random(pause[1] or 1200, pause[2] or 4200)

                        if not isCrawler(entry) and pedOk(entry.ped) then
                            local leg = inv.legDistance or 9.0
                            local a = math.random() * math.pi * 2.0
                            local r = leg * (0.3 + math.random() * 0.7)
                            local c = entry.millAt
                            walkTo(entry.ped, c.x + math.cos(a) * r, c.y + math.sin(a) * r, c.z, -1, 1.5)
                        end
                        growl(entry)
                    end
                end
            elseif entry.state == 'feeding' then
                -- Feeding is left alone, and this branch must come first, otherwise the catch-all below would stand the feeder straight back up
                if not IsPedRagdoll(entry.ped)
                   and not IsPedActiveInScenario(entry.ped)
                   and not IsEntityPlayingAnim(entry.ped, EAT_DICT, EAT_ANIM, 3) then
                    playEating(entry)
                end
            elseif entry.state ~= 'idle' then
                goIdle(entry)
            elseif isCrawler(entry) then
                -- Idle crawler: cl_crawl.lua drifts it
                do end
            elseif not IsPedActiveInScenario(entry.ped) then
                -- The drift, one leg at a time
                local walking = GetIsTaskActive(entry.ped, 224)
                local expired = entry.driftUntil and now > entry.driftUntil

                if not walking or expired then
                    if not entry.driftPause then
                        -- Just finished a leg: stand still for a beat.
                        entry.driftPause = now
                            + math.random(DRIFT.pauseMin, DRIFT.pauseMax)
                        ClearPedTasks(entry.ped)
                    elseif now > entry.driftPause then
                        driftStep(entry, now)
                    end
                end
            end

            ::nextZombie::
        end

        ::continue::
    end
end)

-- Noise

AddEventHandler('bs:world:noise', function(payload)
    if not payload or not payload.coords then return end

    local origin = vector3(payload.coords.x, payload.coords.y, payload.coords.z)
    local radius = payload.radius or 20.0

    -- Noise radius is scaled by this walker's hearing relative to a 48 m baseline
    local BASELINE_HEARING = 48.0

    for _, entry in pairs(Zed.live) do
        -- Only pull the ones we are steering; other copies follow through the host's decision via the server
        if entry.hosted and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped) then
            local acuity = (entry.def.hearRadius or BASELINE_HEARING) / BASELINE_HEARING
            acuity = math.max(0.7, math.min(1.5, acuity))

            -- Feeding walkers hear a third as well
            if entry.state == 'feeding' then
                acuity = acuity * (Zombies.Feeding.hearScale or 0.33)
            end

            local dist = #(GetEntityCoords(entry.ped) - origin)
            if dist <= radius * acuity then
                goDrawn(entry, origin)
            end
        end
    end
end)

-- Screamers

function Zombies.Scream(entry)
    local now = GetGameTimer()
    if entry.lastScream and (now - entry.lastScream) < (entry.def.screamCooldown or 25000) then return end
    entry.lastScream = now

    local coords = GetEntityCoords(entry.ped)
    growl(entry, 'alerted')

    TriggerEvent('bs:world:noise', {
        kind = 'scream',
        radius = entry.def.screamRadius or 120.0,
        coords = { x = coords.x, y = coords.y, z = coords.z },
    })

    if GetResourceState('bs_emotes') == 'started' then
        pcall(function()
            exports.bs_emotes:MakeNoise('scream', coords, entry.def.screamRadius or 120.0)
        end)
    end
end

-- A hit anywhere pulls the ones this client steers, whoever fired.
RegisterNetEvent('bs:z:hurt', function(id, hp, shooter)
    local entry = Zed.live[id]
    if not entry then return end

    entry.hp = hp
    growl(entry, 'alerted')

    if not entry.hosted then return end
    -- Networked: the server already turned this hit into zTarget.
    if entry.net then return end

    -- GetPlayerFromServerId returns -1 for a shooter out of scope, and GetPlayerPed(-1) is our own ped
    local pl = GetPlayerFromServerId(shooter)
    if not pl or pl == -1 then return end
    local ped = GetPlayerPed(pl)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        entry.aggroAt = GetGameTimer()   -- skip the lurch
        goHunt(entry, ped)
    end
end)

-- Exported so bs_admin's debug button uses the same spawn distance instead of a duplicated number
exports('FeedingConfig', function()
    return Zombies.Feeding or {}
end)


-- /ztestsenses - prints what a walker's sight range resolves to for your current stance on this

RegisterCommand('ztestsenses', function()
    local DET = (Noise and Noise.Detection) or {}
    local SG  = DET.sight or {}
    local ped = PlayerPedId()

    local prone = false
    if GetResourceState('bs_emotes') == 'started' then
        local ok, isProne = pcall(function() return exports.bs_emotes:IsProne() end)
        prone = (ok and isProne) and true or false
    end
    local ducking = IsPedDucking(ped) and true or false

    local stance = prone and 'PRONE' or (ducking and 'CROUCHED' or 'STANDING')
    local base   = prone and (SG.prone or 6.0)
                 or (ducking and (SG.crouched or 10.0) or (SG.standing or 50.0))

    local stealth = 1.0
    if GetResourceState('bs_skills') == 'started' then
        local ok, v = pcall(function() return exports.bs_skills:StealthMultiplier() end)
        if ok and type(v) == 'number' then stealth = stealth * v end
    end
    if GetResourceState('bs_inventory') == 'started' then
        local ok, st = pcall(function() return exports.bs_inventory:EquipmentStats() end)
        if ok and type(st) == 'table' then
            stealth = stealth * (1.0 - math.max(0.0, math.min(0.9, tonumber(st.stealth) or 0.0)))
        end
    end

    local def = (Zombies.Types and Zombies.Types.walker) or {}
    local typeScale = (def.senseRadius or 28.0) / (SG.referenceSenseRadius or 28.0)
    local effective = base * typeScale * stealth

    print(('^5[BS SENSES]^7 you are %s'):format(stance))
    print(('   config says      %.1fm for this stance'):format(base))
    print(('   walker type x%.2f  (senseRadius %.0f vs reference %.0f)')
        :format(typeScale, def.senseRadius or 28.0, SG.referenceSenseRadius or 28.0))
    print(('   your stealth x%.2f (perks and clothing)'):format(stealth))
    print(('   ^2A WALKER SEES YOU AT %.1f METRES^7'):format(effective))
    print(('   behind it, it notices you only inside %.1fm')
        :format((prone or ducking) and (SG.crouchedContactRadius or 1.2)
                                   or (DET.contactRadius or 3.5)))

    local simRange = (Sim and Sim.sense and Sim.sense.sightRange) or -1
    local simCrouch = (Sim and Sim.sense and Sim.sense.crouchSightMultiplier) or -1
    print(('   simulation agrees: sightRange %.1f, crouch x%.2f = %.1fm')
        :format(simRange, simCrouch, simRange * simCrouch))

    if math.abs(simRange - (SG.standing or 50.0)) > 0.5 then
        print('^1[BS SENSES]^7 THE TWO SYSTEMS DISAGREE. An agent and the ped it becomes will notice you at different distances. config_sim.lua should be deriving its range from Noise.Detection.sight.')
    end
end, false)

-- Horde bed: one looping emitter for a crowd, placed at its centroid (see Zombies.Voices.horde)

CreateThread(function()
    local TAG = 'zed:horde'
    local playing = false

    while true do
        local H = (Zombies.Voices or {}).horde or {}
        Wait(H.checkMs or 1500)

        if H.enabled == false or not H.file then
            if playing then
                pcall(function() exports.bs_ui:StopSoundTag(TAG, H.fadeOut or 3500) end)
                playing = false
            end
            goto continue
        end

        do
            local me = GetEntityCoords(PlayerPedId())
            local radius = H.radius or 45.0
            local r2 = radius * radius

            -- Count and centroid in one pass
            local n, sx, sy, sz = 0, 0.0, 0.0, 0.0
            for _, entry in pairs(Zed.live) do
                if entry.ped and DoesEntityExist(entry.ped) and not entry.dying then
                    local at = GetEntityCoords(entry.ped)
                    local dx, dy = at.x - me.x, at.y - me.y
                    if (dx * dx + dy * dy) <= r2 then
                        n = n + 1
                        sx, sy, sz = sx + at.x, sy + at.y, sz + at.z
                    end
                end
            end

            local start = H.count or 20
            -- Hysteresis, so a crowd sitting at the threshold does not toggle the bed every pass.
            local stop = math.max(1, start - (H.dropoff or 5))

            if n >= start and not playing then
                local ok = pcall(function()
                    return exports.bs_ui:PlaySoundAt(H.file,
                        { x = sx / n, y = sy / n, z = sz / n },
                        { id = TAG, category = 'zombie', loop = true,
                          volume = H.volume or 0.5,
                          maxDistance = math.min(H.maxDistance or 70.0, (Zombies.Voices or {}).hearDistance or 30.0) })
                end)
                if ok then playing = true end

            elseif playing and n < stop then
                pcall(function() exports.bs_ui:StopSoundTag(TAG, H.fadeOut or 3500) end)
                playing = false

            elseif playing and n > 0 then
                -- Follow the crowd as it moves.
                pcall(function()
                    exports.bs_ui:MoveSoundAt(TAG, { x = sx / n, y = sy / n, z = sz / n })
                end)
            end
        end

        ::continue::
    end
end)

-- The bed is not a walker, so stop it on resource stop or it stays as an orphaned voice in the UI
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    pcall(function() exports.bs_ui:StopSoundTag('zed:horde', 0) end)
end)


-- What this walker should be wearing right now (nil = leave it alone)
local function wantedGait(entry)
    if not entry.def or entry.def.noClipset or isCrawler(entry) then return nil end
    return entry.gait or Zombies.Anims.shamble
end

-- GetPedMovementClipset returns a signed int; normalise both sides before comparing.
local function sameHash(a, b)
    if type(a) ~= 'number' or type(b) ~= 'number' then return false end
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

-- Clipsets get stripped by ragdoll/revive
CreateThread(function()
    while true do
        Wait(500)
        for _, entry in pairs(Zed.live or {}) do
            local ped = entry.ped
            local set = ped and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and wantedGait(entry)
            if set then
                if IsPedUsingActionMode(ped) then
                    SetPedUsingActionMode(ped, false, -1, 'DEFAULT_ACTION')
                end
                if not HasAnimSetLoaded(set) then
                    RequestAnimSet(set)
                elseif pedOk(ped) then
                    local ok, cur = pcall(GetPedMovementClipset, ped)
                    if (ok and not sameHash(cur, GetHashKey(set))) or (not ok and entry.appliedGait ~= set) then
                        -- no SetWeaponAnimationOverride('Default') here: its unarmed motion group replaces the drunk clipset
                        ResetPedStrafeClipset(ped)
                        ResetPedWeaponMovementClipset(ped)
                        SetPedMovementClipset(ped, set, 0.25)
                        entry.appliedGait = set
                        entry.gaitFixes = (entry.gaitFixes or 0) + 1
                    end
                end
            end
        end
    end
end)

-- /zgait: one line per nearby walker
RegisterCommand('zgait', function()
    local me = GetEntityCoords(PlayerPedId())
    local n = 0
    local errs = 0
    for id, entry in pairs(Zed.live or {}) do
        local ped = entry.ped
        if ped and DoesEntityExist(ped) then
          local okW, errW = pcall(function()
            local want = wantedGait(entry)
            local ok, cur = pcall(GetPedMovementClipset, ped)
            local task = 'none'
            if GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_GO_TO_ENTITY')) ~= 7 then task = 'goToEntity'
            elseif GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_GO_STRAIGHT_TO_COORD')) ~= 7 then task = 'goStraight'
            elseif GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD')) ~= 7 then task = 'navmesh'
            elseif GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_PLAY_ANIM')) ~= 7 then task = 'anim' end
            print(('[zgait] #%s d=%.0f host=%s state=%s task=%s combat=%s action=%s ragdoll=%s want=%s loaded=%s cur=%s exp=%s match=%s blend=%.2f spd=%.2f rate=%.2f tgt~%.2f fixes=%d')
                :format(tostring(id), #(GetEntityCoords(ped) - me), tostring(entry.hosted), tostring(entry.state), task,
                    tostring(IsPedInCombat(ped, 0)), tostring(IsPedUsingActionMode(ped)), tostring(IsPedRagdoll(ped)),
                    tostring(want), tostring(want and HasAnimSetLoaded(want)), ok and tostring(cur) or 'ERR',
                    want and tostring(GetHashKey(want)) or '-', tostring(ok and want and sameHash(cur, GetHashKey(want))),
                    GetPedDesiredMoveBlendRatio(ped), GetEntitySpeed(ped), entry.moveRate or 0, 1.45 * (entry.moveRate or 1.0), entry.gaitFixes or 0))
            if entry.net then
                print(('[zgait]   #%s NETWORKED netId=%s owner=%s mine=%s control=%s'):format(tostring(id),
                    tostring(entry.net), tostring(NetworkGetEntityOwner(ped)), tostring(entry.hosted),
                    tostring(NetworkHasControlOfEntity(ped))))
            end
            local now = GetGameTimer()
            local zp = ZProbe or {}
            local tk, dr, rt = (zp.task or {})[ped], (zp.driven or {})[ped], (zp.rate or {})[ped]
            print(('[zgait]   #%s model=%s(%s) walking=%s running=%s sprinting=%s | lastTask=%s speedArg=%s timeoutArg=%s age=%dms src=%s | driven<1s=%s (%s, %dms ago) | lastRate=%s age=%dms src=%s')
                :format(tostring(id), tostring(entry.model or GetEntityModel(ped)), IsPedMale(ped) and 'male' or 'female',
                    tostring(IsPedWalking(ped)), tostring(IsPedRunning(ped)), tostring(IsPedSprinting(ped)),
                    tk and tk.kind or '-', tk and tostring(tk.speed) or '-', tk and tostring(tk.timeout) or '-',
                    tk and (now - tk.t) or -1, tk and tk.src or '-',
                    tostring(dr ~= nil and now - dr.t < 1000), dr and dr.why or '-', dr and (now - dr.t) or -1,
                    rt and tostring(rt.r) or '-', rt and (now - rt.t) or -1, rt and rt.src or '-'))
          end)
            n = n + 1
            if not okW then
                errs = errs + 1
                print(('[zgait] #%s error: %s'):format(tostring(id), tostring(errW)))
            end
        end
    end
    print(('[zgait] %d walkers, %d errors'):format(n, errs))
end, false)


-- Player bodies draw walkers in (host only)

CreateThread(function()
    local lastBite = {}
    while true do
        Wait(2000)
        local P = (Zombies.Feeding and Zombies.Feeding.playerCorpses) or {}
        if P.enabled ~= false then
            local radius, most = P.radius or 35.0, P.maxFeeders or 3
            local bodies = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                local st = Entity(ped).state
                if st and st.bsCorpse then bodies[#bodies + 1] = ped end
            end

            if #bodies > 0 then
                local now = GetGameTimer()
                local taken = {}
                for _, entry in pairs(Zed.live or {}) do
                    local b = entry.feedOn or entry.corpseTarget
                    if b then taken[b] = (taken[b] or 0) + 1 end
                end

                local list = {}
                for _, entry in pairs(Zed.live or {}) do list[#list + 1] = entry end

                for _, entry in ipairs(list) do
                    if entry.hosted and not entry.dying and entry.ped and DoesEntityExist(entry.ped) then
                        local at = GetEntityCoords(entry.ped)
                        local target = entry.corpseTarget

                        if target and (not DoesEntityExist(target) or entry.state ~= 'drawn') then
                            entry.corpseTarget, target = nil, nil
                        end

                        if not target and entry.state == 'idle' then
                            for _, body in ipairs(bodies) do
                                if (taken[body] or 0) < most and #(GetEntityCoords(body) - at) <= radius then
                                    goDrawn(entry, GetEntityCoords(body))
                                    if entry.state == 'drawn' then
                                        entry.drawnTo = GetEntityCoords(body)
                                        entry.corpseTarget = body
                                        taken[body] = (taken[body] or 0) + 1
                                    end
                                    break
                                end
                            end
                        elseif target then
                            local bpos = GetEntityCoords(target)
                            local d = #(bpos - at)
                            if d <= 1.8 then
                                entry.corpseTarget = nil
                                SetEntityHeading(entry.ped,
                                    GetHeadingFromVector_2d(bpos.x - at.x, bpos.y - at.y))
                                goFeed(entry)
                            elseif d <= 8.0 and not isCrawler(entry) and pedOk(entry.ped) then
                                -- Straight in, not the usual milling around the spot.
                                TaskGoStraightToCoord(entry.ped, bpos.x, bpos.y, bpos.z, 1.0, 6000, 0.0, 1.2)
                                entry.nextLeg = now + 2500
                                entry.millUntil = entry.millUntil or (now + 60000)
                            end
                        end

                        local body = entry.state == 'feeding' and entry.feedOn
                        if body and DoesEntityExist(body) and NetworkGetEntityIsNetworked(body)
                           and now - (lastBite[body] or 0) > 8000 then
                            lastBite[body] = now
                            TriggerServerEvent('bs:medical:corpse:bite', NetworkGetNetworkIdFromEntity(body))
                        end
                    end
                end
                for b in pairs(lastBite) do if not DoesEntityExist(b) then lastBite[b] = nil end end
            end
        end
    end
end)
