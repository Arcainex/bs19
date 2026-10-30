-- Walk-speed probe removed. ZProbe stays as an empty table so /zgait keeps working.
ZProbe = ZProbe or { task = {}, driven = {}, rate = {} }

-- bs_zombies - client side sync of server-owned walkers

Zed = {
    live    = {},     -- [id] = { ped, rec, hosted, target = {x,y,z,h} }
    hosted  = {},     -- [id] = true
    -- [id] = true for walkers the server removed while still queued or loading their model (no Zed.live entry yet).
    dropped = {},
    -- [id] = record for walkers whose ground height was not found yet. Retried when closer.
    reground = {},
    -- [ped] = true, set as soon as CreatePed returns. spawn() yields
    owned   = {},
    -- [id] = true for walkers spawned before their movement clipset finished loading.
    needGait = {},
    ready   = false,
    count   = 0,
}

-- Crash guard: only touch peds that exist, are alive, not ragdolling, and that we own.
local function pedOk(ped, allowDown)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if not allowDown and (IsPedRagdoll(ped) or IsPedGettingUp(ped)) then return false end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return false end
    return true
end

local S = Zombies.Settings

-- Single exit point for every ped this resource deletes

-- Crash seen after mass spawns: GET_ENTITY_MODEL faulted on a handle that passed DoesEntityExist

local pedForgetters = {}

-- Register a cleaner that runs for every ped this resource forgets or destroys. fn(ped) is
function Zed.OnPedForgotten(name, fn)
    if type(fn) ~= 'function' then return end
    pedForgetters[#pedForgetters + 1] = { name = tostring(name or '?'), fn = fn }
end

-- Forget a ped everywhere without deleting it (for peds destroyed by something else, e.g. bs_world sweep, vMenu, resource restart).
function Zed.ForgetPed(ped)
    if not ped or ped == 0 then return end

    Zed.owned[ped] = nil

    for _, cleaner in ipairs(pedForgetters) do
        local ok, err = pcall(cleaner.fn, ped)
        if not ok then
            print(('^1[BeyondSurvival]^7 (zombies) ped cache cleaner "%s" threw for ped %s: %s')
                :format(cleaner.name, tostring(ped), tostring(err)))
        end
    end

    -- Also drop the bs_interactions registration, which reads the entity model every frame
    if GetResourceState('bs_interactions') == 'started' then
        pcall(function() exports.bs_interactions:RemoveEntity(ped) end)
    end
end

-- Forget first, then delete, with no yield in between
function Zed.DestroyPed(ped)
    if not ped or ped == 0 then return false end
    if DoesEntityExist(ped)then
        local state=Entity(ped).state
        if IsPedAPlayer(ped)or (state and (state.bsProtected or state.bsConvoy))then
            Zed.owned[ped]=nil
            return false
        end
    end

    Zed.ForgetPed(ped)

    -- Checked on the frame of the delete, not by the caller, to avoid deleting another resource's entity through a stale handle
    if not DoesEntityExist(ped) then return false end

    -- Networked walkers and corpses are deleted by the server (sv_net.lua)
    if NetworkGetEntityIsNetworked(ped) then
        local okBag, isZombie = pcall(function()
            local st = Entity(ped).state
            return st and st.bsZombie ~= nil
        end)
        if okBag and isZombie then return false end
    end

    pcall(SetEntityAsNoLongerNeeded, ped)
    pcall(DeleteEntity, ped)
    return true
end


-- How hard a non-hosted ped is pulled toward the synced position (0-1)
local LERP        = 0.16
-- Beyond this distance (m) the ped is snapped instead of walked.
local SNAP_AT     = 6.0
local REPORT_RATE = 250
local PG = (Streaming and Streaming.PoolGuard) or {}
-- states where a walker is engaging a player; never teleport these
local COMBAT_STATES = { hunting = true, grab = true, drawn = true, disturbed = true, attacking = true }

-- Engine health pool given to every walker
local ENGINE_HP = (Zombies.Detector and Zombies.Detector.engineHealthPool) or 20000

-- A native that makes the walker behave like one failed
local behaviourFails = {}

function behaviourFailed(id, name, err)
    behaviourFails[name] = (behaviourFails[name] or 0) + 1
    local n = behaviourFails[name]
    if n == 1 or n % 50 == 0 then
        print(('^1[BeyondSurvival]^7 (zombies) walker %s: %s failed (%d so far) - %s. This walker will behave like an ordinary ped in that respect.')
            :format(tostring(id), name, n, tostring(err)))
        TriggerServerEvent('bs:z:badnative', name, n, tostring(err))
    end
end

-- Models

local badModels, modelCache = {}, {}

local function loadModel(name)
    local hash = GetHashKey(name)

    -- The cache is only a hint: the streamer can evict a model after SetModelAsNoLongerNeeded
    if modelCache[hash] then
        if HasModelLoaded(hash) then return hash end
        -- Evicted under us. Fall through and ask for it again.
        modelCache[hash] = nil
    end

    if badModels[name] and GetGameTimer() < badModels[name] then return nil end
    badModels[name] = nil

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        badModels[name] = GetGameTimer() + 30000
        Zed.failed = Zed.failed or {}
        Zed.failed['notInCdimage'] = (Zed.failed['notInCdimage'] or 0) + 1
        print(('^3[BeyondSurvival]^7 (zombies) model "%s" is not on this build'):format(name))
        return nil
    end

    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 8000 do Wait(10); waited = waited + 10 end
    if not HasModelLoaded(hash) then
        badModels[name] = GetGameTimer() + 30000
        Zed.failed = Zed.failed or {}
        Zed.failed['loadTimeout'] = (Zed.failed['loadTimeout'] or 0) + 1
        return nil
    end

    modelCache[hash] = true
    return hash
end

-- Building the ped

-- Finding the floor
local function groundAt(x, y, z)
    local me = GetEntityCoords(PlayerPedId())

    -- Probe order: just above the player, level with them, below them (slopes, basements), then high up for far-away walkers
    local probes = { me.z + 20.0, me.z, me.z - 30.0, me.z + 120.0 }
    if z and z > 1.0 then table.insert(probes, 1, z + 2.0) end

    for _, from in ipairs(probes) do
        local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, from + 0.0, false)
        if found and math.abs(gz - me.z) < 80.0 then return gz end
    end

    -- No plausible answer
    return nil
end

-- Fall-through guard
local function surfaceAbove(x, y, z)
    -- Probe from just above z only; high probes hit roofs.
    for _, up in ipairs({ 2.0 }) do
        local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + up, false)
        if found then return gz end
    end
    return nil
end
local function safeZ(x, y, z)
    if not z or z < 1.0 then return groundAt(x, y, nil) end
    local gz = surfaceAbove(x, y, z)
    -- Lift at most 1.5m; never snap onto a roof.
    if gz and z < gz - 0.5 and gz - z <= 1.5 then return gz end
    return z
end
Zed.SafeZ = safeZ

-- Clipsets are requested once here, not per walker
CreateThread(function()
    local preload = { Zombies.Anims.zombieCore, Zombies.Anims.zombieStrafe,
                      table.unpack(Zombies.Anims.shambleSet or {}) }
    for _, fs in ipairs(Zombies.Anims.femaleShambleSet or {}) do preload[#preload + 1] = fs end
    for _, set in ipairs(preload) do
        if set then
            -- Request both ways: clip sets and anim sets are not the same store on every build.
            pcall(RequestAnimSet, set)
            pcall(RequestClipSet, set)

            local waited = 0
            while waited < 10000 do
                local ready = false
                pcall(function() if HasAnimSetLoaded(set) then ready = true end end)
                if not ready then
                    pcall(function() if HasClipSetLoaded(set) then ready = true end end)
                end
                if ready then break end
                Wait(50); waited = waited + 50
            end
        end
    end
end)

-- Clip sets vs anim sets: SetPedMovementClipset needs a clip set
local function clipSetReady(name)
    if not name then return false end

    local loaded = false
    pcall(function() if HasAnimSetLoaded(name) then loaded = true end end)
    if not loaded then
        pcall(function() if HasClipSetLoaded(name) then loaded = true end end)
    end

    -- Not here yet: keep asking, so the repair pass finds it next time round.
    if not loaded then
        pcall(RequestAnimSet, name)
        pcall(RequestClipSet, name)
    end

    return loaded
end

-- Which walk a walker gets
local function gaitFor(id, female)
    local a = Zombies.Anims
    local list = a.shambleSet or { a.shamble }
    if female and type(a.femaleShambleSet) == 'table' and #a.femaleShambleSet > 0 then
        list = a.femaleShambleSet
    end
    local drunk = list[(id % math.max(1, #list)) + 1] or a.shamble

    -- Cheap deterministic hash so consecutive ids do not alternate.
    local r = ((id * 2654435761) % 1000) / 1000.0

    if r < (a.drunkShare or 0.0) then
        return drunk, a.zombieCore
    end
    return a.zombieCore, drunk
end

-- Give a walker its walk
local function applyGait(ped, id, def)
    -- Types with noClipset (e.g. crawler) get no movement clipset: it would override the crawl animation.
    if def and def.noClipset then return nil end

    -- per-model gait: female models get the female drunk set, falling back to the male sets while it streams / if it will not load
    local female = pedOk(ped) and not IsPedMale(ped)
    local first, second = gaitFor(id, female)
    local third = female and (gaitFor(id, false)) or nil

    local pick = nil
    if clipSetReady(first) then pick = first
    elseif clipSetReady(second) then pick = second
    elseif third and clipSetReady(third) then pick = third end

    if not pick then return nil end

    if not pedOk(ped) then return nil end
    -- 0.25 blend, to keep the stagger.
    local ok = pcall(SetPedMovementClipset, ped, pick, 0.25)
    if not ok then return nil end
    -- No SetPedIsDrunk: it hands locomotion to the engine's drunk handling, which ignores the clipset and walks normally

    -- The matching strafe, for the zombie walk only
    if pick == Zombies.Anims.zombieCore then
        local zs = Zombies.Anims.zombieStrafe
        if clipSetReady(zs) then pcall(SetPedStrafeClipset, ped, zs) end
    end

    return pick
end

-- Repair pass: gives the clipset to walkers built before it was available. Slow.
CreateThread(function()
    while true do
        Wait(1500)

        for id in pairs(Zed.needGait) do
            local entry = Zed.live[id]
            if not entry or not DoesEntityExist(entry.ped) then
                Zed.needGait[id] = nil
            else
                local set = applyGait(entry.ped, id, entry.def)
                if set then
                    entry.gait = set
                    Zed.needGait[id] = nil
                end
            end
        end
    end
end)

local pending = {}

-- Forward declarations, so spawn() can re-queue itself on failure.
local finalSpawnGate
local spawnRetry

-- Forward declaration, assigned next to the materialisation gate below
local regate

-- Keeps the position of records that have no ped yet (queued, held by the gate, waiting on ground)
local shadow = {}
Zed.shadow = shadow   -- cl_net.lua reads announced records from here

-- Is this walker part-way through being built? pending is a local, and the removal handler further down needs the answer
function pendingSpawn(id) return pending[id] ~= nil end

local function spawn(rec)
    if Zed.live[rec.id] or pending[rec.id] then return end

    -- Model loading yields, so two adds for the same walker in the same frame would both get past the live check and build two peds
    local ticket = {}
    pending[rec.id] = ticket

    local def = Zombies.Types[rec.t] or Zombies.Types.walker

    -- /zvanilla forces the base-game model, to rule out the replaced ped pack without a restart.
    local wanted = Zed.forceVanilla and 'u_m_y_zombie_01' or rec.m

    local hash = loadModel(wanted)
    -- An add-on ped that will not load must not cost a zombie: try the fallbacks, then up to 4 other pool models
    local tried = { [wanted] = true }
    local function nextModel()
        local list = {}
        for _, n in ipairs(Zombies.FallbackModels or { 'u_m_y_zombie_01' }) do list[#list + 1] = n end
        local pool = Zombies.Models or {}
        -- Deterministic per id so every client picks the same substitute.
        local start = #pool > 0 and ((tonumber(rec.id) or 0) % #pool) or 0
        for i = 0, math.min(#pool, 4) - 1 do list[#list + 1] = pool[(start + i) % #pool + 1] end
        for _, n in ipairs(list) do
            if not tried[n] then
                tried[n] = true
                local h = loadModel(n)
                if h then
                    Zed.failed = Zed.failed or {}
                    Zed.failed.substituted = (Zed.failed.substituted or 0) + 1
                    return h, n
                end
            end
        end
        return nil
    end
    if not hash then hash, wanted = nextModel() end
    wanted = wanted or rec.m
    -- Keep the model actually used so rebuilds reuse it, never a new roll.
    if hash and wanted and not Zed.forceVanilla then rec.m = wanted end
    -- A remove/re-add may happen while loading
    if pending[rec.id] ~= ticket then return end

    -- Both failures below were silent
    if not hash then
        Zed.failed = Zed.failed or {}
        local k = 'model:' .. tostring(wanted)
        Zed.failed[k] = (Zed.failed[k] or 0) + 1
        if Zed.failed[k] == 1 or Zed.failed[k] % 25 == 0 then
            print(('^1[BeyondSurvival]^7 (zombies) model "%s" would not load - %d walker(s) have no ped because of it. Try /zvanilla.')
                :format(tostring(wanted), Zed.failed[k]))
        end

        pending[rec.id] = nil

        -- Failed records are put back for retry
        rec._tries = (rec._tries or 0) + 1
        if rec._tries < 3 then
            CreateThread(function()
                Wait(2000 * rec._tries)
                if not Zed.live[rec.id] and not Zed.dropped[rec.id] then
                    -- THE GATE, on the model-load retry too. See regate.
                    if regate then regate(rec) else spawnRetry(rec) end
                end
            end)
        end

        return
    end

    local z = rec.z
    if not z or z < 1.0 then z = groundAt(rec.x, rec.y, rec.z)
    else z = safeZ(rec.x, rec.y, z) end

    if not z then
        -- Usually distance: ground collision is only known for streamed areas
        Zed.failed = Zed.failed or {}
        Zed.failed.ground = (Zed.failed.ground or 0) + 1
        if Zed.failed.ground % 50 == 1 then
            print(('^3[BeyondSurvival]^7 (zombies) no ground under a walker yet (%d so far) - usually just distance, retrying as you approach')
                :format(Zed.failed.ground))
        end

        Zed.reground[rec.id] = rec
        pending[rec.id] = nil
        return
    end

    -- Removed while the model was loading
    if pending[rec.id] ~= ticket then return end
    if Zed.dropped[rec.id] then
        Zed.dropped[rec.id] = nil
        pending[rec.id] = nil
        return
    end

    -- Model/ground loading yields. First appearance must be safe NOW, not when queued.
    if finalSpawnGate and not finalSpawnGate(rec, z) then
        pending[rec.id] = nil
        SetModelAsNoLongerNeeded(hash)
        return
    end
    -- Pool guard: refuse near the CPed limit or our local cap; retry later.
    local okPool, pool = pcall(GetGamePool, 'CPed')
    if (okPool and type(pool) == 'table' and #pool >= (PG.clientPedLimit or 180))
       or (Zed.count or 0) >= (PG.clientMaxLocal or 40) then
        Zed.failed = Zed.failed or {}
        Zed.failed.pool = (Zed.failed.pool or 0) + 1
        Zed.reground[rec.id] = rec
        pending[rec.id] = nil
        SetModelAsNoLongerNeeded(hash)
        return
    end
    Crumb('zspawn:create', 'id=%s model=%s loaded=%s', tostring(rec.id), tostring(wanted), tostring(HasModelLoaded(hash)))
    local ped = CreatePed(4, hash, rec.x + 0.0, rec.y + 0.0, z + 0.0, rec.h + 0.0, false, false)
    Crumb('zspawn', 'id=%s model=%s ped=%s', tostring(rec.id), tostring(wanted), tostring(ped))
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        -- Refused: count it and retry once with another model.
        Zed.failed = Zed.failed or {}
        Zed.failed.createPed = (Zed.failed.createPed or 0) + 1
        local h2, n2 = nextModel()
        if h2 then
            hash, wanted = h2, n2
            ped = CreatePed(4, hash, rec.x + 0.0, rec.y + 0.0, z + 0.0, rec.h + 0.0, false, false)
        end
    end

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        -- The one remaining silent path
        print(('^1[BeyondSurvival]^7 (zombies) CreatePed refused for "%s"'):format(tostring(wanted)))
        Crumb('zspawn', 'refused %s', tostring(wanted))
        pending[rec.id] = nil
        return
    end
    if not ped or ped == 0 then pending[rec.id] = nil return end

    -- Claimed first, before anything that yields (see Zed.owned)
    Zed.owned[ped] = rec.id

    -- Stamped here, not at registration, so ped age is measured from birth.
    local bornAt = GetGameTimer()

    -- Collision under a ped 50-100m out may not be streamed yet; a ped created there falls straight through
    do
        local cped, cx, cy, cz = ped, rec.x + 0.0, rec.y + 0.0, z + 0.0
        pcall(RequestCollisionAtCoord, cx, cy, cz)
        if not HasCollisionLoadedAroundEntity(cped) then
            pcall(FreezeEntityPosition, cped, true)
            Zed.collFrozen = Zed.collFrozen or {}
            Zed.collFrozen[cped] = true
            CreateThread(function()
                local untilT = GetGameTimer() + 10000
                while DoesEntityExist(cped) and not HasCollisionLoadedAroundEntity(cped)
                      and GetGameTimer() < untilT do
                    RequestCollisionAtCoord(cx, cy, cz)
                    Wait(100)
                end
                if DoesEntityExist(cped) and Zed.collFrozen[cped] then
                    local at = GetEntityCoords(cped)
                    local gz = surfaceAbove(at.x, at.y, at.z - 1.0)
                    if gz and gz < at.z + 1.5 and math.abs(gz - at.z) > 1.5 then
                        SetEntityCoordsNoOffset(cped, at.x, at.y, gz + 0.05, false, false, false)
                    end
                    FreezeEntityPosition(cped, false)
                end
                Zed.collFrozen[cped] = nil
            end)
        end
    end

    -- Behaviour natives (relationship group, flee, events, speed) are guarded one call at a time
    local function try(name, fn, ...)
        if type(fn) ~= 'function' then
            behaviourFailed(rec.id, name, 'no such native on this build')
            return false
        end
        local ok, err = pcall(fn, ...)
        if not ok then behaviourFailed(rec.id, name, err) end
        return ok
    end

    Crumb('zspawn:behav', 'id=%s', tostring(rec.id))
    try('SetEntityAsMissionEntity', SetEntityAsMissionEntity, ped, true, true)
    try('SetPedDropsWeaponsWhenDead', SetPedDropsWeaponsWhenDead, ped, false)
    try('SetPedDiesWhenInjured', SetPedDiesWhenInjured, ped, false)
    try('SetPedSuffersCriticalHits', SetPedSuffersCriticalHits, ped, false)
    try('SetPedCanEvasiveDive', SetPedCanEvasiveDive, ped, false)
    try('SetPedFleeAttributes', SetPedFleeAttributes, ped, 0, false)
    try('SetPedCombatAttributes', SetPedCombatAttributes, ped, 46, true)
    try('SetPedAlertness', SetPedAlertness, ped, 0)

    -- Most important two: without the first gunfire makes it flee, without the second it does not treat the player as an enemy
    try('SetBlockingOfNonTemporaryEvents', SetBlockingOfNonTemporaryEvents, ped, true)
    try('SetPedRelationshipGroupHash', SetPedRelationshipGroupHash, ped, GetHashKey('BS_ZOMBIE'))

    -- No climbing, vaulting or ladders
    local mob = Zombies.Mobility or {}

    try('SetPedPathCanUseClimbovers', SetPedPathCanUseClimbovers, ped,
        mob.pathClimbovers == true)
    try('SetPedPathCanUseLadders', SetPedPathCanUseLadders, ped,
        mob.pathLadders == true)
    try('SetPedPathCanDropFromHeight', SetPedPathCanDropFromHeight, ped,
        mob.pathDropFromHeight == true)
    try('SetPedPathClimbCostModifier', SetPedPathClimbCostModifier, ped,
        (mob.climbCostModifier or 10.0) + 0.0)

    -- Extra config flags by index. Empty by default - do not guess indexes.
    for _, pair in ipairs(mob.configFlags or {}) do
        local index, value = pair[1], pair[2]
        if type(index) == 'number' then
            try(('SetPedConfigFlag(%d)'):format(index),
                SetPedConfigFlag, ped, index, value == true)
        end
    end

    try('SetPedCanRagdollFromPlayerImpact', SetPedCanRagdollFromPlayerImpact, ped, false)
    -- SetPedCanClimbLadders does not exist on this build (logged as an error)

    -- SetPedMoveRateOverride moved below applyGait: drunk walkers get none.

    -- Walk ceiling from the first frame

    -- Explicitly not invincible
    try('SetEntityInvincible', SetEntityInvincible, ped, false)
    try('SetEntityProofs', SetEntityProofs, ped, false, false, false, false, false, false, false, false)
    try('SetEntityCanBeDamaged', SetEntityCanBeDamaged, ped, true)

    -- Detector pool, not toughness. See ENGINE_HP.
    try('SetPedMaxHealth', SetPedMaxHealth, ped, ENGINE_HP)
    try('SetEntityHealth', SetEntityHealth, ped, ENGINE_HP)

    -- No human screaming from a corpse.
    try('DisablePedPainAudio', DisablePedPainAudio, ped, true)
    try('SetAmbientVoiceName', SetAmbientVoiceName, ped, 'ALIENS')

    -- Declared outside the pcall so the live entry can store it
    local gait = nil

    -- Everything up to registration is wrapped in pcall

    local configOk, configErr = pcall(function()


    -- Critical hits off

    -- Also no bleeding out
    SetPedSeeingRange(ped, def.senseRadius + 0.0)
    SetPedHearingRange(ped, def.hearRadius + 0.0)

    -- Health is the server's number


    SetPedConfigFlag(ped, 281, true)    -- no writhe
    -- Flags 166 and 208 are off: they turned the drunk walk into the injured walk on server-made
    if (Zombies.Settings or {}).legacyPedFlags == true then
        SetPedConfigFlag(ped, 166, true)
        SetPedConfigFlag(ped, 208, true)
    end

    -- Human scream when shot: flag 166 only suppresses part of the pain speech

    -- One gait per walker, for life, zombie clipset first
    Crumb('zspawn:gait', 'id=%s', tostring(rec.id))
    gait = applyGait(ped, rec.id, def)
    -- Drunk walkers get their clipset once (blend 0.25) and no rate / blend-ratio override
    if not (type(gait) == 'string' and gait:find('drunk', 1, true)) then
        try('SetPedMoveRateOverride', SetPedMoveRateOverride, ped, def.shambleRate)
        try('SetPedMaxMoveBlendRatio', SetPedMaxMoveBlendRatio, ped, def.maxBlend or 1.0)
    end

    -- Melee animation override: swaps the unarmed set for the DLC zombie one
    if gait == Zombies.Anims.zombieCore then
        pcall(SetWeaponAnimationOverride, ped, GetHashKey('ZOMBIE'))
    end
    -- No 'Default' override for other gaits: it swaps in the generic unarmed motion group, which beats the drunk clipset


    -- Voice: pain/scream sounds come from the model's own voice

    -- One face per walker, bounds-checked
    pcall(SetPedDefaultComponentVariation, ped)
    local nComp, nProp = 0, 0
    pcall(function()
        local app = (Zombies and Zombies.Appearance) or {}
        local excl = app.exclude or {}
        local tries = app.tries or 4
        local idn = tonumber(rec.id) or GetHashKey(tostring(rec.id))
        local st = (math.floor(idn) * 2654435761 + 12345) % 2147483648
        local function rnd(n)   -- 0..n-1
            st = (st * 1103515245 + 12345) % 2147483648
            return (st // 65536) % n
        end
        local function excluded(comp, d)
            local l = excl[comp]
            if l then for _, x in ipairs(l) do if x == d then return true end end end
            return false
        end
        for comp = 0, 11 do
            local nd = GetNumberOfPedDrawableVariations(ped, comp) or 0
            if nd > 0 then
                for _ = 1, tries do
                    local d = rnd(nd)
                    if not excluded(comp, d) then
                        local nt = GetNumberOfPedTextureVariations(ped, comp, d) or 0
                        local t = nt > 0 and rnd(nt) or 0
                        if IsPedComponentVariationValid(ped, comp, d, t) then
                            SetPedComponentVariation(ped, comp, d, t, 0)
                            nComp = nComp + 1
                            break
                        end
                    end
                end
            end
        end
        for _, prop in ipairs({ 0, 1, 2, 6, 7 }) do
            local np = GetNumberOfPedPropDrawableVariations(ped, prop) or 0
            -- one extra slot = "no prop"
            local d = np > 0 and (rnd(np + 1) - 1) or -1
            if d >= 0 then
                local nt = GetNumberOfPedPropTextureVariations(ped, prop, d) or 0
                local t = nt > 0 and rnd(nt) or 0
                SetPedPropIndex(ped, prop, d, t, true)
                nProp = nProp + 1
            else
                ClearPedProp(ped, prop)
            end
        end
    end)
    Crumb('zspawn:comp', 'id=%s comps=%d props=%d', tostring(rec.id), nComp, nProp)

    -- Distance model swap: past a certain range the engine swaps to SLOD_HUMAN, which looks like the model changing
    local render = Zombies.Render or {}
    pcall(SetEntityLodDist, ped, render.lodDistance or 325)
    pcall(SetPedLodMultiplier, ped, render.lodMultiplier or 3.5)

    end)

    -- Failure is counted and named
    if not configOk then
        Zed.failed = Zed.failed or {}
        Zed.failed.config = (Zed.failed.config or 0) + 1
        if Zed.failed.config == 1 or Zed.failed.config % 25 == 0 then
            print(('^1[BeyondSurvival]^7 (zombies) walker %d was built but could not be fully configured (%d so far): %s')
                :format(rec.id, Zed.failed.config, tostring(configErr)))
        end
    end

    -- Late walk: the clipset is applied once at spawn
    if not gait and not def.noClipset then Zed.needGait[rec.id] = true end

    local state = Entity(ped).state
    if state then state:set('bsZombie', true, false) end

    -- Two voices per walker, lurk and eat, chosen once from the id so every client hears the same thing
    local voiceLurk, voiceEat, voicePitch = Zombies.VoicesFor(rec.id)

    -- Setup can yield too. Do not resurrect a record removed during setup.
    if pending[rec.id] ~= ticket or Zed.dropped[rec.id] then
        Zed.DestroyPed(ped)
        if pending[rec.id] == ticket then pending[rec.id] = nil end
        return
    end
    Zed.live[rec.id] = {
        id = rec.id, ped = ped, rec = rec, def = def,
        -- When this ped was BUILT - see the note where bornAt is taken.
        bornAt = bornAt,
        typeId = rec.t, model = rec.m, key = tostring(rec.id),
        gait = gait,   -- this walker's own shamble clipset, see above
        voiceLurk = voiceLurk,
        voiceEat  = voiceEat,
        -- This walker's own pitch, for life
        voicePitch = voicePitch,
        reacher = rec.r == 1,
        -- 'n' node path, 's' sector path
        path = rec.p or '?',
        state = rec.s or 'idle',
        -- Server position
        sync = { x = rec.x, y = rec.y, z = z, h = rec.h },
        hosted = Zed.hosted[rec.id] or false,
        nextSound = GetGameTimer() + math.random(2000, 12000),
        nextThink = GetGameTimer() + math.random(0, S.aiTick),
    }
    Zed.count = Zed.count + 1
    pending[rec.id] = nil
    TriggerServerEvent('bs:z:materialised', rec.id)
    Crumb('zspawn:done', 'id=%s gait=%s', tostring(rec.id), tostring(gait))

    -- Feeders: started after registration
    if rec.e == 1 and Zombies.GoFeed then
        CreateThread(function()
            local entry = Zed.live[rec.id]
            if entry and DoesEntityExist(entry.ped) then
                Zombies.GoFeed(entry)
            end
        end)
    end
end

local function despawn(id, keepBody)
    pending[id] = nil
    Crumb('zdespawn', '%s body=%s', tostring(id), tostring(keepBody))

    local entry = Zed.live[id]
    if not entry then return end

    -- Meal cleanup: deleted with the walker when it despawns
    if keepBody and Zombies.RelinquishMeal then
        pcall(Zombies.RelinquishMeal, entry)
    elseif Zombies.ClearMeal then
        pcall(Zombies.ClearMeal, entry)
    end

    -- Rule: any native that gives the engine a handle to hold (e.g

    if not keepBody then
        -- Goes through Zed.DestroyPed: clears every ped-keyed cache (including bs_interactions) first, then deletes
        Zed.DestroyPed(entry.ped)

    elseif entry.ped then
        -- The body stays, so the ped is not destroyed, but the claim is dropped; cl_combat's corpse list covers it from here
        Zed.owned[entry.ped] = nil
    end
    Zed.needGait[id] = nil

    Zed.live[id] = nil
    Zed.count = math.max(0, Zed.count - 1)
end

Zed.Despawn = despawn

-- Server messages

-- Spawning is queued
spawnRetry = spawn

local queue, queued = {}, {}

-- Materialisation gate

-- Second gate, separate from cl_spawner.lua's

local held = {}       -- [id] = { rec, since } waiting for a moment to appear
local ledger = {}     -- the last N materialisations, for /zwhy

local function mcfg()
    return (Noise and Noise.Materialise) or nil
end

-- Is this point inside the local camera view?
local function pointVisible(x, y, z)
    local c = mcfg()
    local placement = Streaming and Streaming.Placement
    if placement then
        local cam = GetGameplayCamCoord()
        local dx, dy = x - cam.x, y - cam.y
        local distance2 = dx * dx + dy * dy
        local forwardRange = placement.localViewRange or 300.0
        if distance2 > 0.01 and distance2 <= forwardRange * forwardRange then
            local yaw = math.rad(GetGameplayCamRot(2).z)
            local dot = (-dx * math.sin(yaw) + dy * math.cos(yaw)) / math.sqrt(distance2)
            if dot >= math.cos(math.rad(placement.localViewHalfAngle or 65.0)) then
                return true
            end
        end
    end
    return IsSphereVisible(x + 0.0, y + 0.0, (z or 0.0) + ((c and c.viewHeight) or 0.9),
                           (c and c.viewSphereRadius) or 1.6)
end

-- Ledger: one row per ped this client created. how is the path
local lastGate = 'n/a'
local function noteAppearance(rec, how, dist, inView)
    if not (Noise and Noise.Ledger and Noise.Ledger.enabled) then return end
    print(('[BS APPEAR] walker=%s mode=%s distance=%.1fm view=%s gate=%s')
        :format(tostring(rec.id), tostring(how), dist, tostring(inView), tostring(lastGate)))
    ledger[#ledger + 1] = {
        id = rec.id, how = how, d = dist, view = inView,
        born = rec.b or '?', age = (rec.a or 0) / 10.0, moved = rec.w,
        -- Gate decision that allowed the creation
        gate = lastGate,
        at = GetGameTimer(),
    }
    local keep = Noise.Ledger.keep or 40
    while #ledger > keep do table.remove(ledger, 1) end
end

-- The gate: nothing may appear on top of a player

-- Why a creation was allowed, for the ledger. Set by materialiseVerdict.
local function materialiseVerdict(rec, wasHeld)
    local me = PlayerPedId()
    local at = GetEntityCoords(me)
    -- 2D distance, like other record proximity checks: records carry z = 0.0 until a host reports ground height
    local dx, dy = (rec.x or 0.0) - at.x, (rec.y or 0.0) - at.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Path from the record's own age: under ~3s old counts as a real spawn.
    local how = ((rec.a or 9999) <= 30) and 'spawn' or 'streamin'
    if rec.b == 'staff' then how = 'staff' end

    -- Min-distance and view holds apply only to creating new records
    if how ~= 'spawn' and how ~= 'staff' then
        rec._fade = true
        lastGate = 'stream(fade)'
        return how, dist, false, false
    end
    -- A newborn held past maxHoldMs is released with a fade, never hidden forever.
    local c0 = mcfg()
    if wasHeld and (GetGameTimer() - wasHeld) > ((c0 and c0.maxHoldMs) or 9000) then
        rec._fade = true
        lastGate = 'forced(fade)'
        return how, dist, false, false
    end

    local c = mcfg()
    if not (c and c.enabled) or not (Noise and Noise.enabled) then
        -- Gate off: the floor still applies
        local floor_ = math.max((c and c.hardFloor) or 50.0, (Streaming and Streaming.spawnMin) or 110.0)
        if dist < floor_ then
            lastGate = 'floor(nocfg)'
            return how, dist, pointVisible(rec.x, rec.y, rec.z), true
        end
        lastGate = 'gate-off'
        return how, dist, false, false
    end

    -- Rule zero: the hard floor is checked first, before visibility and hold timers
    local floor_ = c.hardFloor or 50.0

    if dist < floor_ and how ~= 'staff' then
        lastGate = ('floor<%.0fm'):format(floor_)
        -- inView is for the ledger only; it changes no decision.
        return how, dist, pointVisible(rec.x, rec.y, rec.z), true
    end

    if how == 'staff' then
        lastGate = 'staff(exempt)'
        return how, dist, pointVisible(rec.x, rec.y, rec.z), false
    end

    -- View rule: a new walker is never created in the player's view, at any distance (no distance exemption)
    local inView = pointVisible(rec.x, rec.y, rec.z)
    if not inView then
        lastGate = 'hidden'
        return how, dist, false, false
    end

    lastGate = 'held(inview)'
    return how, dist, true, true
end

-- Escalation (Noise.Materialise.escalateAfterMs)
local escalated = {}

local function escalate(id, dist)
    -- Local visibility is not authority to move or delete a zombie for everyone.
    if escalated[id] then return end
    escalated[id] = GetGameTimer()
    print(('[BS ZOMBIES] holding unseen record %s at %.1fm; no global relocation'):format(id,dist))
end

finalSpawnGate = function(rec, z)
    if not ZPolicy.Point(rec.x, rec.y, z) then return false end
    rec.z = z
    local how, dist, inView, hold = materialiseVerdict(rec, nil)
    -- Also check every other locally streamed player at the moment of creation.
    local floor = math.max((Streaming and Streaming.spawnMin) or 110, (mcfg() or {}).hardFloor or 0)
    if rec.b ~= 'staff' and how == 'spawn' and not rec._fade then
        for _, player in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local at = GetEntityCoords(ped)
                if (rec.x-at.x)^2+(rec.y-at.y)^2 < floor^2 then hold = true break end
            end
        end
    end
    if hold then
        shadow[rec.id] = rec
        held[rec.id] = {rec=rec,since=GetGameTimer()}
        return false
    end
    noteAppearance(rec, how, dist, inView)
    return true
end

-- Create the ped and write the ledger row. The only creation door in this file.
local function fadeIn(id)
    CreateThread(function()
        local t0 = GetGameTimer()
        local e = Zed.live[id]
        while not (e and e.ped and DoesEntityExist(e.ped)) do
            if GetGameTimer() - t0 > 5000 then return end
            Wait(50); e = Zed.live[id]
        end
        local ped = e.ped
        for a = 0, 255, 17 do
            if not DoesEntityExist(ped) then return end
            SetEntityAlpha(ped, a, false); Wait(40)
        end
        if DoesEntityExist(ped) then ResetEntityAlpha(ped) end
    end)
end

local function materialise(rec, how, dist, inView)
    spawn(rec)
    if rec._fade then rec._fade = nil; fadeIn(rec.id) end
end

-- Way back in for the model-load retry
regate = function(rec)
    local how, dist, inView, hold = materialiseVerdict(rec, nil)
    if hold then
        shadow[rec.id] = rec
        held[rec.id] = { rec = rec, since = GetGameTimer() }
    else
        materialise(rec, how, dist, inView)
    end
end

RegisterNetEvent('bs:z:add', function(list)
    -- Networked mode: nothing is built here. cl_net.lua adopts the server ped when it streams in and reads fields from shadow.
    if Zombies.Mode == 'networked' then
        for _, rec in ipairs(list or {}) do
            if rec and rec.id then shadow[rec.id] = rec end
        end
        return
    end
    for _, rec in ipairs(list or {}) do
        if rec and rec.id and not Zed.live[rec.id] and not queued[rec.id] and not held[rec.id] then
            queued[rec.id] = true
            queue[#queue + 1] = rec
            -- Indexed so bs:z:upd can keep it current while it waits (see shadow).
            shadow[rec.id] = rec
        end
    end
end)

-- Far first: draining the queue farthest-first fills the horizon before your feet, instead of creating the nearest walkers first
local function sortFarFirst()
    local c = mcfg()
    if not (c and c.farFirst) then return end
    if #queue < 2 then return end

    local at = GetEntityCoords(PlayerPedId())
    table.sort(queue, function(a, b)
        local ax, ay = (a.x or 0.0) - at.x, (a.y or 0.0) - at.y
        local bx, by = (b.x or 0.0) - at.x, (b.y or 0.0) - at.y
        return (ax * ax + ay * ay) > (bx * bx + by * by)
    end)
end

-- Held records are retried in their own thread, paced by the player's view, not by model streaming, so neither waits on the other
CreateThread(function()
    while true do
        local c = mcfg()
        Wait((c and c.retryMs) or 250)

        if next(held) then
            local ready = {}
            for id, entry in pairs(held) do
                if Zed.dropped[id] then
                    -- The server removed it while held. Nothing to show or report.
                    held[id] = nil
                    Zed.dropped[id] = nil
                elseif Zed.live[id] then
                    held[id] = nil
                else
                    local how, dist, inView, hold = materialiseVerdict(entry.rec, entry.since)
                    if not hold then
                        held[id] = nil
                        ready[#ready + 1] = { entry.rec, how, dist, inView }
                    else
                        -- Still held
                        local c = mcfg()
                        local floor_ = (c and c.hardFloor) or 50.0
                        local after = (c and c.escalateAfterMs) or 12000
                        if dist < floor_ and (GetGameTimer() - (entry.since or 0)) > after then
                            escalate(id, dist)
                        end
                    end
                end
            end

            for i = 1, #ready do
                local r = ready[i]
                materialise(r[1], r[2], r[3], r[4])
            end
        end

        -- Rare sweep of the shadow index
        if math.random() < 0.02 then
            for id in pairs(shadow) do
                if Zed.live[id] and not held[id] and not queued[id] then
                    shadow[id] = nil
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if #queue == 0 then
            Wait(150)
        else
            local per = Zombies.Settings.spawnPerPass or 2

            sortFarFirst()

            for _ = 1, per do
                local rec = table.remove(queue, 1)
                if not rec then break end

                queued[rec.id] = nil

                -- It may have been removed again while queued
                if not Zed.dropped[rec.id] then
                    -- The gate. The only CreatePed path for a server record (see the note above bs:z:add).
                    local how, dist, inView, hold = materialiseVerdict(rec, nil)
                    if hold then
                        held[rec.id] = { rec = rec, since = GetGameTimer() }
                    else
                        materialise(rec, how, dist, inView)
                    end
                else
                    Zed.dropped[rec.id] = nil
                end
            end

            Wait(90)
        end
    end
end)

-- Walkers vanished when you got close
RegisterNetEvent('bs:z:upd', function(batch)
    for _, row in ipairs(batch or {}) do
        local entry = Zed.live[row[1]]

        -- Write-through: a record with no ped yet keeps moving, so its position is updated here for the gate to use
        if not entry then
            local rec = shadow[row[1]]
            if rec then
                rec.x = tonumber(row[2]) or rec.x
                rec.y = tonumber(row[3]) or rec.y
                local rz = tonumber(row[4])
                if rz and rz > 1.0 then rec.z = rz end
                rec.h = tonumber(row[5]) or rec.h
                if row[6] then rec.s = row[6] end
            end
        else
            -- It has a ped now; the live entry is the authority.
            shadow[row[1]] = nil
        end

        if entry then
            entry.sync = entry.sync or {}
            entry.sync.x = row[2]
            entry.sync.y = row[3]

            local z = row[4]
            if z and z > 1.0 then
                entry.sync.z = z
            elseif not entry.sync.z then
                -- Nothing trusted either: fall back to the ground under the position we do trust, not zero.
                entry.sync.z = groundAt(row[2], row[3], nil) or 0.0
            end

            entry.sync.h = row[5]
            entry.state    = row[6] or entry.state
            entry.hp       = row[7]
        end
    end
end)

RegisterNetEvent('bs:z:rm', function(ids, reason)
    if type(ids) == 'number' then ids = { ids } end
    for _, id in ipairs(ids or {}) do
        -- Remember removals for records with no entry yet (queued or loading a model)
        if queued[id] or pendingSpawn(id) or held[id] then Zed.dropped[id] = true end
        -- Drop held records here so a forgotten record cannot appear when the hold lifts.
        held[id] = nil

        -- Stop retrying the ground for it.
        Zed.reground[id] = nil
        -- Drop the position index entry.
        shadow[id] = nil
        -- Drop any hold or escalation state for it.
        held[id] = nil
        escalated[id] = nil

        -- A removal after a kill is not a normal despawn
        if reason == 'dead' and Zed.live[id] then
            -- The queued death handler releases this entry as a corpse.
        else
            despawn(id)
        end
    end
end)

-- Ground retry
CreateThread(function()
    while true do
        Wait(3000)

        local waiting = Zed.reground
        if next(waiting) then
            Zed.reground = {}

            for id, rec in pairs(waiting) do
                if not Zed.live[id] and not Zed.dropped[id] then
                    -- This path goes through the gate too
                    local how, dist, inView, hold = materialiseVerdict(rec, nil)
                    if hold then
                        shadow[id] = rec
                        held[id] = { rec = rec, since = GetGameTimer() }
                    else
                        materialise(rec, 'reground', dist, inView)
                    end
                end
            end
        end
    end
end)

-- Who this client is responsible for.
RegisterNetEvent('bs:z:host', function(list)
    local now = {}
    for _, id in ipairs(list or {}) do now[id] = true end

    for id, entry in pairs(Zed.live) do
        local hosted = now[id] or false
        -- Networked: hosting is engine ownership, tracked by cl_net.lua.
        if entry.net then hosted = entry.hosted end
        if hosted ~= entry.hosted then
            entry.hosted = hosted
            if not hosted then
                -- Handing over: stop giving it orders so the two clients do not fight over it.
                if DoesEntityExist(entry.ped) then ClearPedTasks(entry.ped) end
                entry.state = entry.state == 'hunting' and 'hunting' or 'idle'
            end
        end
    end

    if Zombies.Mode == 'networked' then
        now = {}
        for id, entry in pairs(Zed.live) do
            if entry.hosted then now[id] = true end
        end
    end
    Zed.hosted = now
    if not Zed.ready then Zed.readyAt = GetGameTimer() end
    Zed.ready = true
end)

RegisterNetEvent('bs:z:correctHost', function(id, x, y, z)
    local entry = Zed.live[tonumber(id)]
    if not entry or not entry.hosted or entry.dying or entry.net
       or not DoesEntityExist(entry.ped) then return end
    -- Never yank a walker that is engaging a player.
    if COMBAT_STATES[entry.state] then return end
    local at = GetEntityCoords(entry.ped)
    local dx, dy = at.x - x, at.y - y
    local snapAt = PG.hostSnapDistance or 120.0
    if dx * dx + dy * dy < snapAt * snapAt then return end
    ClearPedTasks(entry.ped)
    z = safeZ(x, y, z) or at.z
    SetEntityCoordsNoOffset(entry.ped, x + 0.0, y + 0.0, z + 0.0,
        false, false, false)
    entry.sync = {x=x,y=y,z=z,h=entry.sync and entry.sync.h or 0.0}
end)

-- Following the server (non-hosted copies)

CreateThread(function()
    while true do
        Wait(0)

        local any = false

        for id, entry in pairs(Zed.live) do
            if entry.net and not DoesEntityExist(entry.ped) then
                -- Networked walker left this client's scope or was deleted by the server
                if Zombies.RelinquishMeal then pcall(Zombies.RelinquishMeal, entry)
                elseif Zombies.ClearMeal then pcall(Zombies.ClearMeal, entry) end
                if entry.ped then Zed.ForgetPed(entry.ped) end
                Zed.live[id] = nil
                Zed.hosted[id] = nil
                Zed.count = math.max(0, Zed.count - 1)
            elseif not DoesEntityExist(entry.ped) then
                -- Something else deleted our ped
                Zed.failed = Zed.failed or {}
                Zed.failed.pedDeletedByOthers = (Zed.failed.pedDeletedByOthers or 0) + 1

                if Zed.failed.pedDeletedByOthers == 1
                   or Zed.failed.pedDeletedByOthers % 20 == 0 then
                    print(('^1[BeyondSurvival]^7 (zombies) walker %d had its ped DELETED by something else - %d so far.')
                        :format(id, Zed.failed.pedDeletedByOthers))

                    -- Also reported to the server so it lands in the server log
                    local age = entry.bornAt and (GetGameTimer() - entry.bornAt) or -1
                    TriggerServerEvent('bs:z:pedlost', id, Zed.failed.pedDeletedByOthers, age)
                end

                -- Its meal goes with it
                if Zombies.RelinquishMeal then pcall(Zombies.RelinquishMeal, entry)
                elseif Zombies.ClearMeal then pcall(Zombies.ClearMeal, entry) end

                -- An outside party (bs_world sweep, vMenu, another script) destroyed the ped, so its handle can be reissued
                if entry.ped then Zed.ForgetPed(entry.ped) end
                Zed.live[id] = nil
                Zed.count = math.max(0, Zed.count - 1)
            elseif not entry.hosted and not entry.dying and entry.sync and not entry.net then
                any = true

                local at = GetEntityCoords(entry.ped)
                local to = entry.sync
                local dist = #(at - vector3(to.x, to.y, to.z))

                if dist > SNAP_AT then
                    -- No guard against snaps ending inside the hard floor: it despawned every walker that streamed in at 75m and then walked closer
                    local sz = safeZ(to.x, to.y, to.z) or at.z
                    to.z = sz
                    SetEntityCoordsNoOffset(entry.ped, to.x, to.y, sz, false, false, false)
                    SetEntityHeading(entry.ped, to.h)
                elseif dist > 0.05 then
                    -- Walk it in with a real task so the legs play the clip; a plain coord lerp left it sliding in its idle pose
                    local gt = GetGameTimer()
                    if dist > 0.6 and (not entry.followAt or gt - entry.followAt > 400) and pedOk(entry.ped) then
                        entry.followAt = gt
                        TaskGoStraightToCoord(entry.ped, to.x, to.y, to.z, 1.0, -1, to.h, 0.3)
                    end
                    -- Only drag the position if the legs are falling behind.
                    if dist > 2.0 then
                    local nx = at.x + (to.x - at.x) * LERP
                    local ny = at.y + (to.y - at.y) * LERP
                    -- Never drag downward: a stale server z under the terrain would pull the ped through the floor.
                    local nz = to.z > at.z and (at.z + (to.z - at.z) * LERP) or at.z
                    SetEntityCoordsNoOffset(entry.ped, nx, ny, nz, false, false, false)

                    local heading = GetEntityHeading(entry.ped)
                    local diff = (to.h - heading + 540.0) % 360.0 - 180.0
                    SetEntityHeading(entry.ped, heading + diff * 0.2)

                    -- Chasing copies move at chase pace so the legs match.
                    end
                    local fg = entry.gait
                    if not (type(fg) == 'string' and fg:find('drunk', 1, true)) then
                        SetPedMoveRateOverride(entry.ped,
                            entry.state == 'hunting' and entry.def.chaseRate or entry.def.shambleRate)
                    end
                end
            end
        end

        if not any then Wait(120) end
    end
end)

-- Reporting (hosted copies)

CreateThread(function()
    while true do
        Wait(REPORT_RATE)

        local batch = {}

        for id, entry in pairs(Zed.live) do
            if entry.hosted and not entry.dying and DoesEntityExist(entry.ped) then
                local at = GetEntityCoords(entry.ped)
                -- A GTA task can displace a local ped far beyond walking speed
                local sync = entry.sync
                if sync and sync.x and sync.y and not entry.net then
                    local dx, dy = at.x - sync.x, at.y - sync.y
                    -- Only a real warp (past hostSnapDistance, not in combat) is undone
                    local snapAt = PG.hostSnapDistance or 120.0
                    if dx * dx + dy * dy > snapAt * snapAt
                       and not COMBAT_STATES[entry.state] then
                        if not entry.warnedWarp then
                            entry.warnedWarp = true
                            print(('[BS ZOMBIES] walker %s local ped jumped %.0fm; restoring authoritative position')
                                :format(tostring(id), math.sqrt(dx * dx + dy * dy)))
                        end
                        ClearPedTasks(entry.ped)
                        SetEntityCoordsNoOffset(entry.ped, sync.x, sync.y,
                            safeZ(sync.x, sync.y, sync.z) or at.z, false, false, false)
                        at = GetEntityCoords(entry.ped)
                    end
                end
                batch[#batch + 1] = {
                    id, at.x, at.y, at.z, GetEntityHeading(entry.ped), entry.state,
                }
            end
        end

        if #batch > 0 then TriggerServerEvent('bs:z:report', batch) end
    end
end)

-- The default spawn point (bs_core Config.Session.defaultSpawn) is the centre of the Sandy
local inSafe = nil

CreateThread(function()
    while true do
        Wait(3000)
        if exports.bs_core:IsLoaded() then
            -- Zones.Safe is shared config (config_zones.lua is a shared_script)
            local at = GetEntityCoords(PlayerPedId())
            local here = false
            for _, zone in ipairs(Zones.Safe or {}) do
                local dx, dy = zone.coords.x - at.x, zone.coords.y - at.y
                if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then here = true break end
            end

            if here ~= inSafe then
                if inSafe ~= nil then
                    TriggerEvent('bs:ui:notify', {
                        type = here and 'info' or 'warn',
                        message = here and L('zed.entering')
                            or L('zed.leaving'),
                        duration = 3200,
                    })
                end
                inSafe = here
            end
        end
    end
end)

-- Housekeeping

-- Release every ped this resource claimed, not just the registered ones
local function releaseEverything()
    for id in pairs(Zed.live) do despawn(id) end

    -- Catch whatever the loop above missed
    local leaked = 0
    local all = {}
    for ped in pairs(Zed.owned) do all[#all + 1] = ped end

    for _, ped in ipairs(all) do
        if Zed.DestroyPed(ped) then leaked = leaked + 1 end
        Zed.owned[ped] = nil
    end

    if leaked > 0 then
        print(('^3[BeyondSurvival]^7 (zombies) released %d ped(s) that were not in the live table - mid-spawn walkers or their meals. Without this they would have held ped-pool slots for the rest of the session.')
            :format(leaked))
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    releaseEverything()
end)

AddEventHandler('bs:hook:player:unloaded', function()
    releaseEverything()
end)

-- Counts why walkers have no ped ('model:<name>' and 'ground'), shown in the staff menu
exports('IsWalkerPed', function(ped)
    if not ped or ped == 0 then return false end

    -- Networked walker or corpse, adopted or not: the state bag says so.
    if Zed.NetIdOf and Zed.NetIdOf(ped, true) then return true end

    -- Check the claim table first: it is written when CreatePed returns, so it covers the birth window
    local ownerId = Zed.owned[ped]
    if ownerId then
        -- A live owner vouches for itself and its meal.
        if Zed.live[ownerId] then return true end

        -- No live entry does not mean not ours: between CreatePed and the live write the walker is only pending
        if pendingSpawn(ownerId) then return true end

        -- A meal can outlive its eater: on a kill it goes to cl_ai's linger list
        if Zombies.IsLingeringMeal and Zombies.IsLingeringMeal(ped) then
            return true
        end

        -- Neither live nor being born: the handle was probably recycled by the engine
        Zed.owned[ped] = nil
    end

    for _, entry in pairs(Zed.live) do
        if entry.ped == ped then return true end
    end

    -- Corpses are keyed by ped (cl_combat's registerCorpse stores { id, loot, diesAt } as the value)
    if Zed.Corpses then
        local ok, corpses = pcall(Zed.Corpses)
        if ok and type(corpses) == 'table' and corpses[ped] then return true end
    end

    return false
end)

-- Did this walker get a ped on this client?
exports('HasWalker', function(id)
    local entry = Zed.live[tonumber(id) or -1]
    return entry ~= nil and entry.ped ~= nil and DoesEntityExist(entry.ped)
end)

-- List of walker types, for anything that offers a choice (staff menu spawn buttons)
exports('Types', function()
    local out = {}
    for id, def in pairs(Zombies.Types or {}) do
        out[#out + 1] = {
            id     = id,
            label  = def.label or id,
            health = def.health,
            -- True for types the world never produces on its own (currently the crawler), so staff can tell them apart
            crawls = def.crawls == true,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

exports('Failures', function() return Zed.failed or {} end)

exports('Count', function() return Zed.count end)
exports('Live', function() return Zed.live end)
exports('HostedCount', function()
    local n = 0
    for _ in pairs(Zed.hosted) do n = n + 1 end
    return n
end)

-- /zdebug - what is happening around you

local function band(d)
    if d < 50 then return '  <50m' end
    if d < 100 then return ' <100m' end
    if d < 200 then return ' <200m' end
    if d < 400 then return ' <400m' end
    return '  400m+'
end

RegisterCommand('zdebug', function()
    local me = GetEntityCoords(PlayerPedId())

    local rows, counts, states = {}, {}, {}
    local live, missing, invisible, offGround = 0, 0, 0, 0

    for id, entry in pairs(Zed.live) do
        local exists = entry.ped and entry.ped ~= 0 and DoesEntityExist(entry.ped)

        -- The record's coordinates, not the ped's: if the ped is gone, the server position is what identifies the problem
        local rx = entry.rec and entry.rec.x or 0.0
        local ry = entry.rec and entry.rec.y or 0.0
        local dist = #(vector3(rx, ry, me.z) - me)

        local b = band(dist)
        counts[b] = (counts[b] or 0) + 1

        local st = entry.state or 'idle'
        states[st] = (states[st] or 0) + 1

        if exists then
            live = live + 1
            if not IsEntityVisible(entry.ped) then invisible = invisible + 1 end

            -- Where the ped actually is, which can differ from the record (e.g. placed on a roof or tunnel and unfindable).
            local pc = GetEntityCoords(entry.ped)
            local flat = #(vector3(pc.x, pc.y, me.z) - me)
            local dz = pc.z - me.z

            if flat < 60.0 and math.abs(dz) > 15.0 then
                offGround = offGround + 1
                rows[#rows + 1] = ('    id %d  %.0fm away but %+.0fm VERTICALLY (ped z %.1f, you %.1f)')
                    :format(id, flat, dz, pc.z, me.z)
            end
        else
            missing = missing + 1
            -- The interesting ones: the server says this walker exists but this client has no ped for it.
            rows[#rows + 1] = ('    id %d  %s  %.0fm  model %s  hosted=%s')
                :format(id, st, dist, tostring(entry.model), tostring(entry.hosted))
        end
    end

    print('^5' .. string.rep('-', 66) .. '^7')
    print(('^5[BS ZDEBUG]^7 records=%d  peds alive=%d  ^3peds MISSING=%d^7  invisible=%d  ^3WRONG HEIGHT=%d^7')
        :format(live + missing, live, missing, invisible, offGround))

    local byBand = {}
    for _, b in ipairs({ '  <50m', ' <100m', ' <200m', ' <400m', '  400m+' }) do
        if counts[b] then byBand[#byBand + 1] = ('%s:%d'):format(b:gsub('%s', ''), counts[b]) end
    end
    print('   distance   ' .. (#byBand > 0 and table.concat(byBand, '  ') or 'nothing near you'))

    local byState = {}
    for st, n in pairs(states) do byState[#byState + 1] = ('%s:%d'):format(st, n) end
    print('   states     ' .. (#byState > 0 and table.concat(byState, '  ') or '-'))

    if #rows > 0 then
        print('^3   records with no ped on this client:^7')
        for i = 1, math.min(#rows, 12) do print(rows[i]) end
        if #rows > 12 then print(('    ...and %d more'):format(#rows - 12)) end
        print('^3   ^7If these are the ones vanishing, the SERVER still has them and')
        print('   the ped failed on this client - a model or streaming problem.')
        print('   If a vanishing walker leaves this list entirely, the SERVER')
        print('   dropped it - a cull or sector problem instead.')
    end

    print('^5' .. string.rep('-', 66) .. '^7')
end, false)

-- /zvanilla - respawn every walker on this client with the base-game model
RegisterCommand('zvanilla', function()
    Zed.forceVanilla = not Zed.forceVanilla
    print(('^5[BS ZDEBUG]^7 forcing the base-game ped model: %s'):format(
        Zed.forceVanilla and 'ON - rejoin or wait for respawns' or 'off'))
    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = Zed.forceVanilla and 'Walkers: vanilla model' or 'Walkers: pack model',
        duration = 2600,
    })
end, false)

-- /zanim - asks the engine directly
RegisterCommand('zanim', function()
    local a = Zombies.Anims
    local lines = {}

    local function report(label, name)
        if not name then
            lines[#lines + 1] = ('%s: NOT CONFIGURED'):format(label)
            return
        end

        local anim, clip = false, false
        pcall(function() anim = HasAnimSetLoaded(name) and true or false end)
        pcall(function() clip = HasClipSetLoaded(name) and true or false end)

        lines[#lines + 1] = ('%s "%s": anim=%s clip=%s%s')
            :format(label, name, tostring(anim), tostring(clip),
                    (anim or clip) and '' or '  <-- NOT AVAILABLE ON THIS BUILD')
    end

    report('zombieCore  ', a.zombieCore)
    report('zombieStrafe', a.zombieStrafe)

    for i, set in ipairs(a.shambleSet or {}) do
        report(('drunk[%d]    '):format(i), set)
    end
    for i, set in ipairs(a.femaleShambleSet or {}) do
        report(('drunkF[%d]   '):format(i), set)
    end

    lines[#lines + 1] = ('drunkShare: %.2f   maxMoveRate: %s')
        :format(a.drunkShare or 0.0, tostring(Zombies.Settings.maxMoveRate))

    -- The nearest walker.
    local me = GetEntityCoords(PlayerPedId())
    local best, bestD = nil, math.huge
    for _, entry in pairs(Zed.live) do
        if entry.ped and DoesEntityExist(entry.ped) then
            local d = #(me - GetEntityCoords(entry.ped))
            if d < bestD then best, bestD = entry, d end
        end
    end

    if best then
        lines[#lines + 1] = ('nearest walker %s (%s) %.0fm: gait=%s state=%s awaiting-repair=%s')
            :format(tostring(best.id), tostring(best.typeId), bestD,
                    tostring(best.gait), tostring(best.state),
                    tostring(Zed.needGait[best.id] == true))
    else
        lines[#lines + 1] = 'no walkers on this client to inspect'
    end

    for _, l in ipairs(lines) do print('^5[BS ANIM]^7 ' .. l) end
    TriggerServerEvent('bs:z:animreport', table.concat(lines, ' | '))
end, false)

TriggerEvent('chat:addSuggestion', '/zanim',
    'Report which zombie clipsets are loaded and what the nearest walker is using')


-- /zwhy - which door did that walker come through?

-- /zwhy prints the last 40 peds this client created
RegisterCommand('zwhy', function()
    if not (Noise and Noise.Ledger and Noise.Ledger.enabled) then
        print('^1[BS WHY]^7 Noise.Ledger.enabled is false in config_noise.lua - nothing is being recorded.')
        return
    end

    local c = mcfg()
    local heldN, heldFloor = 0, 0
    local floor_ = (c and c.hardFloor) or 50.0
    local me = GetEntityCoords(PlayerPedId())
    for _, entry in pairs(held) do
        heldN = heldN + 1
        local dx, dy = (entry.rec.x or 0.0) - me.x, (entry.rec.y or 0.0) - me.y
        if (dx * dx + dy * dy) < floor_ * floor_ then heldFloor = heldFloor + 1 end
    end

    print(('^5[BS WHY]^7 last %d walker(s) to appear on this client. gate=%s hardFloor=%.0fm holdRadius=%.0fm maxHold=%dms escalate=%s@%dms | held now: %d (%d inside the floor)')
        :format(#ledger,
                (c and c.enabled and Noise.enabled) and '^2ON^7' or '^1OFF^7',
                floor_,
                (c and c.holdRadius) or 0.0,
                (c and c.maxHoldMs) or 0,
                (c and c.escalate ~= false) and 'on' or 'off',
                (c and c.escalateAfterMs) or 0,
                heldN, heldFloor))

    if c and (c.showAnywayRadius or 0.0) > 0.0 then
        print(('^1[BS WHY]^7 Noise.Materialise.showAnywayRadius is %.1f. That setting is the bug "a zombie spawned on top of me" and it must be 0.0. See the paragraph beside it in config_noise.lua.')
            :format(c.showAnywayRadius))
    end

    if #ledger == 0 then
        print('   nothing yet. Walk somewhere, or wait for one to arrive, then run this again.')
        return
    end

    local now = GetGameTimer()
    for i = #ledger, 1, -1 do
        local e = ledger[i]
        print(('   %5.1fs ago  id=%-5d %-8s %6.1fm  %-8s  gate=%-12s born=%-6s age=%.0fs moved=%s')
            :format((now - e.at) / 1000.0, e.id, e.how, e.d,
                    e.view and '^1IN VIEW^7' or 'hidden',
                    tostring(e.gate or '?'),
                    tostring(e.born), e.age, tostring(e.moved or '-')))
    end

    print('   spawn = created for this moment. streamin = it already existed and came to you. See the block comment above this command in cl_sync.lua.')
end, false)

-- Same table as data for other resources (e.g. the admin debug panel). Returns a copy.
exports('AppearanceLedger', function()
    local out = {}
    for i = 1, #ledger do
        local e = ledger[i]
        out[i] = { id = e.id, how = e.how, d = e.d, view = e.view, gate = e.gate,
                   born = e.born, age = e.age, moved = e.moved, at = e.at }
    end
    return out
end)

-- /zmodelinfo - how much variety a model has

RegisterCommand('zmodelinfo', function(_, args)
    local COMPONENTS = {
        [0]  = 'head / face',
        [3]  = 'torso / arms',
        [4]  = 'legs',
        [6]  = 'feet',
        [8]  = 'undershirt',
        [11] = 'top / jacket',
    }

    -- An explicit model name tests one that is not in the roster
    local names = {}
    if args and args[1] and args[1] ~= '' then
        names[1] = tostring(args[1])
        print(('^5[BS MODELS]^7 testing "%s" (not from the roster)'):format(names[1]))
    else
        for _, m in ipairs(Zombies.Models or {}) do names[#names + 1] = m end
        print(('^5[BS MODELS]^7 roster has %d model(s): %s  -  pass a name to test one that is not in it, e.g. /zmodelinfo ywr_zombies')
            :format(#names, table.concat(names, ', ')))
    end

    for _, wanted in ipairs(names) do
        local hash = GetHashKey(wanted)

        if not IsModelInCdimage(hash) or not IsModelValid(hash) then
            print(('^1[BS MODELS]^7 "%s" is not on this build at all.'):format(wanted))
            goto nextModel
        end

        RequestModel(hash)
        local waited = 0
        while not HasModelLoaded(hash) and waited < 5000 do Wait(50); waited = waited + 50 end
        if not HasModelLoaded(hash) then
            print(('^1[BS MODELS]^7 "%s" would not stream in 5s - THIS is why walkers look vanilla. The engine substitutes the base-game ped below Lua where no script can see it.'):format(wanted))
            goto nextModel
        end

        do
            -- Built under the map so nobody sees the probe ped appear.
            local at = GetEntityCoords(PlayerPedId())
            local probe = CreatePed(4, hash, at.x, at.y, at.z - 200.0, 0.0, false, false)
            if not probe or probe == 0 then
                print(('^1[BS MODELS]^7 could not build a probe ped for "%s".'):format(wanted))
                goto nextModel
            end

            local total = 1
            print(('^5[BS MODELS]^7 %s:'):format(wanted))
            for comp, label in pairs(COMPONENTS) do
                local n = GetNumberOfPedDrawableVariations(probe, comp) or 0
                local tex = n > 0 and (GetNumberOfPedTextureVariations(probe, comp, 0) or 0) or 0
                total = total * math.max(1, n)
                print(('   component %-2d %-14s %d drawable(s), %d texture(s) on #0   %s')
                    :format(comp, label, n, tex,
                            n > 1 and '^2varies^7' or '^3FIXED - every walker identical here^7'))
            end

            print(('   -> roughly %d distinct bodies possible from components alone'):format(total))
            if total <= 2 then
                print('^3[BS MODELS]^7 That is the answer: this model carries no component variety, so one roster entry means one look. Enabling ywr_zombies (23 head variants) is the fix - see docs/ZOMBIE_REBUILD_SPEC.md section 7.')
            end

            DeleteEntity(probe)
        end

        SetModelAsNoLongerNeeded(hash)
        ::nextModel::
    end
end, false)

-- Coherence check

CreateThread(function()
    Wait(2000)   -- let every config file finish loading

    local c = (Noise and Noise.Materialise) or {}
    local floor_ = c.hardFloor or 50.0
    local ringMin = (Streaming and Streaming.spawnMin) or 0.0
    local ringMax = (Streaming and Streaming.spawnMax) or 0.0
    local ok = true

    if ringMin > 0 and ringMin < floor_ then
        ok = false
        print(('^1[BS SPAWN]^7 CONFIG CANNOT PRODUCE A WALKER. Streaming.spawnMin is %.0fm but Noise.Materialise.hardFloor is %.0fm - every candidate is drawn INSIDE a floor it can never satisfy, so every record will be held and no ped will ever be built. Raise spawnMin above the floor, or lower the floor.')
            :format(ringMin, floor_))
    end

    if ringMax > 0 and ringMax <= ringMin then
        ok = false
        print(('^1[BS SPAWN]^7 Streaming.spawnMax (%.0f) is not above spawnMin (%.0f) - the ring has no width.')
            :format(ringMax, ringMin))
    end

    local push = (Sim and Sim.spawn and Sim.spawn.openPushMax) or 0.0

    -- Furthest a walker can be born is ringMax + push (openPushMax), not ringMax
    local bornMax = ringMax + push

    local cleanup = (Streaming and Streaming.cleanupDistance) or 0.0
    if cleanup > 0 and cleanup <= bornMax then
        ok = false
        print(('^1[BS SPAWN]^7 Streaming.cleanupDistance (%.0f) is INSIDE the range walkers are born in (ring max %.0f + open-ground push %.0f = %.0fm). Everything born past %.0fm is culled on the tick it arrives, which reads in game as a crowd appearing and vanishing in under a second. Raise cleanupDistance above %.0f, or lower Sim.spawn.openPushMax.')
            :format(cleanup, ringMax, push, bornMax, cleanup, bornMax))
    end

    -- Must also stay inside what the server will keep.
    local despawn = (Zombies and Zombies.Settings and Zombies.Settings.despawnDistance) or 0.0
    if despawn > 0 and cleanup > 0 and cleanup >= despawn then
        ok = false
        print(('^1[BS SPAWN]^7 Streaming.cleanupDistance (%.0f) is at or beyond the servers despawnDistance (%.0f) - the client would be holding walkers the server has already deleted.')
            :format(cleanup, despawn))
    end

    if ok then
        print(('^2[BS SPAWN]^7 spawn config is coherent: floor %.0fm, ring %.0f-%.0fm, open-ground push to %.0fm, cull at %.0fm (%.0fm of clearance).')
            :format(floor_, ringMin, ringMax, bornMax, cleanup, cleanup - bornMax))
    end
end)

-- /ztestspawn - runs the view rule against a ring of points around the player and prints the gate decision for each

RegisterCommand('ztestspawn', function()
    local me = PlayerPedId()
    local at = GetEntityCoords(me)

    local c = (Noise and Noise.Materialise) or {}
    local floor_ = c.hardFloor or 50.0
    local ringMin = (Streaming and Streaming.spawnMin) or 110.0
    local ringMax = (Streaming and Streaming.spawnMax) or 200.0

    local visible, hidden, tooClose = 0, 0, 0
    local samples = 0

    for bearing = 0, 350, 10 do
        for _, r in ipairs({ ringMin, (ringMin + ringMax) / 2, ringMax }) do
            samples = samples + 1
            local a = math.rad(bearing)
            local x = at.x + math.cos(a) * r
            local y = at.y + math.sin(a) * r
            local z = at.z

            if r < floor_ then
                tooClose = tooClose + 1
            elseif pointVisible(x, y, z) then
                visible = visible + 1
            else
                hidden = hidden + 1
            end
        end
    end

    print(('^5[BS SPAWN]^7 %d ring points tested around you'):format(samples))
    print(('   %d would be REFUSED as visible (the player can see that spot)'):format(visible))
    print(('   %d are hidden and therefore legal'):format(hidden))
    print(('   %d are inside the %.0fm floor and refused outright'):format(tooClose, floor_))

    if hidden == 0 then
        print('^3[BS SPAWN]^7 NOTHING around you is legal right now - you are in the open with clear sight in every direction. That is exactly the case Sim.spawn.openGroundFallback exists for: candidates get pushed out past view distance and walk in. If the world stays empty here, that push is what to look at, not this gate.')
    else
        print(('^2[BS SPAWN]^7 %.0f%% of the ring is currently legal.'):format(hidden / math.max(1, samples - tooClose) * 100))
    end
end, false)

-- Walker id for a ped we can see, or nil (used by bs_gadgets turret).
exports('WalkerIdOf', function(ped)
    local id = ped and Zed.owned[ped]
    local e = id and Zed.live[id]
    if e and e.ped == ped then return id end
    -- Networked walker not adopted yet (still streaming in): id from its state bag.
    if ped and Zed.NetIdOf then return Zed.NetIdOf(ped, false) end
    return nil
end)


-- Fall-through safety net, every 1s for each hosted walker
CreateThread(function()
    Zed.collFrozen = Zed.collFrozen or {}
    while true do
        Wait(1000)
        for _, entry in pairs(Zed.live or {}) do
            local ped = entry.ped
            if entry.hosted and not entry.dying and ped and DoesEntityExist(ped)
               and not IsPedDeadOrDying(ped, true) and not IsPedRagdoll(ped)
               and not (entry.def and entry.def.noClipset) then
                local ok, err = pcall(function()
                    local at = GetEntityCoords(ped)
                    if not HasCollisionLoadedAroundEntity(ped) then
                        RequestCollisionAtCoord(at.x, at.y, at.z)
                        if not Zed.collFrozen[ped] then
                            FreezeEntityPosition(ped, true)
                            Zed.collFrozen[ped] = 'net'
                        end
                        return
                    end
                    if Zed.collFrozen[ped] == 'net' then
                        FreezeEntityPosition(ped, false)
                        Zed.collFrozen[ped] = nil
                    end
                    local gz = surfaceAbove(at.x, at.y, at.z)
                    if gz and at.z < gz - 2.0 then
                        SetEntityCoordsNoOffset(ped, at.x, at.y, gz + 0.05, false, false, false)
                        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                        Zed.failed = Zed.failed or {}
                        Zed.failed.fellThrough = (Zed.failed.fellThrough or 0) + 1
                        if Zed.failed.fellThrough == 1 or Zed.failed.fellThrough % 20 == 0 then
                            print(('[BS ZOMBIES] walker under the map (z=%.1f, floor=%.1f) - put back (%d so far)')
                                :format(at.z, gz, Zed.failed.fellThrough))
                        end
                    end
                end)
            end
        end
        for ped in pairs(Zed.collFrozen) do
            if not DoesEntityExist(ped) then Zed.collFrozen[ped] = nil end
        end
    end
end)

-- /zsync: the server asks, we answer with what exists locally.
RegisterNetEvent('bs:z:syncq', function()
    local live, peds, h, q = 0, 0, 0, 0
    for _, e in pairs(Zed.live) do
        live = live + 1
        if e.ped and DoesEntityExist(e.ped) then peds = peds + 1 end
    end
    for _ in pairs(held) do h = h + 1 end
    for _ in pairs(queued) do q = q + 1 end
    local netVisible = Zed.NetVisibleCount and Zed.NetVisibleCount() or 0
    TriggerServerEvent('bs:z:synca', live, peds, h, q, netVisible)
end)
