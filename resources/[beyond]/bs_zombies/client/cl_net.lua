-- bs_zombies - client side of networked walkers (Zombies.Mode = 'networked')

if (Zombies.Mode or 'networked') ~= 'networked' then return end

local function N() return Zombies.Net or {} end
local ENGINE_HP = (Zombies.Detector and Zombies.Detector.engineHealthPool) or 20000

Zed.netRemoved = Zed.netRemoved or {}   -- [id] = true: server said rm/dead; do not re-adopt

-- Identification

--- Walker id of a networked zombie ped from its state bag, or nil.
--- @param includeDead boolean  also answer for corpses (IsWalkerPed)
function Zed.NetIdOf(ped, includeDead)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    local ok, id, dead = pcall(function()
        local st = Entity(ped).state
        if not st then return nil, nil end
        if st.fnpc or st.bsFnpc or st.fnpc_o then return nil, nil end   -- faction NPC, never a walker
        local m = GetEntityModel(ped)
        if m == GetHashKey('mp_m_freemode_01') or m == GetHashKey('mp_f_freemode_01') then return nil, nil end   -- humans
        return st.bsZombie, st.bsZombieDead
    end)
    if not ok or id == nil then return nil end
    if dead and not includeDead then return nil end
    return tonumber(id)
end

function Zed.NetVisibleCount()
    local n = 0
    local ok, pool = pcall(GetGamePool, 'CPed')
    for _, ped in ipairs(ok and pool or {}) do
        if Zed.NetIdOf(ped, false) then n = n + 1 end
    end
    return n
end

local function bags(ped)
    local ok, st = pcall(function() return Entity(ped).state end)
    return ok and st or nil
end

-- Owner-side setup (only the controlling client may run these)

local function try(id, name, fn, ...)
    if type(fn) ~= 'function' then
        if behaviourFailed then behaviourFailed(id, name, 'no such native on this build') end
        return false
    end
    local ok, err = pcall(fn, ...)
    if not ok and behaviourFailed then behaviourFailed(id, name, err) end
    return ok
end

local function applyAppearance(ped, id)
    pcall(SetPedDefaultComponentVariation, ped)
    pcall(function()
        -- Same seeded generator as cl_sync spawn(): a walker keeps its look.
        local app = (Zombies and Zombies.Appearance) or {}
        local excl = app.exclude or {}
        local tries = app.tries or 4
        local idn = tonumber(id) or GetHashKey(tostring(id))
        local st = (math.floor(idn) * 2654435761 + 12345) % 2147483648
        local function rnd(n)
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
                            break
                        end
                    end
                end
            end
        end
        for _, prop in ipairs({ 0, 1, 2, 6, 7 }) do
            local np = GetNumberOfPedPropDrawableVariations(ped, prop) or 0
            local d = np > 0 and (rnd(np + 1) - 1) or -1
            if d >= 0 then
                local nt = GetNumberOfPedPropTextureVariations(ped, prop, d) or 0
                local t = nt > 0 and rnd(nt) or 0
                SetPedPropIndex(ped, prop, d, t, true)
            else
                ClearPedProp(ped, prop)
            end
        end
    end)
end

Zed = Zed or {}

local function configureOwned(entry)
    local ped, id, def = entry.ped, entry.id, entry.def or {}
    if not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return false end

    try(id, 'SetEntityAsMissionEntity', SetEntityAsMissionEntity, ped, true, true)
    -- Optional debug mask that skips groups of flags. Always 0 in normal play.
    local skip = entry.cfgSkip or 0
    local function on(b) return (skip & b) == 0 end
    if on(1) then
    try(id, 'SetPedDropsWeaponsWhenDead', SetPedDropsWeaponsWhenDead, ped, false)
    try(id, 'SetPedDiesWhenInjured', SetPedDiesWhenInjured, ped, false)
    try(id, 'SetPedSuffersCriticalHits', SetPedSuffersCriticalHits, ped, false)
    try(id, 'SetPedCanEvasiveDive', SetPedCanEvasiveDive, ped, false)
    try(id, 'SetPedFleeAttributes', SetPedFleeAttributes, ped, 0, false)
    try(id, 'SetPedCombatAttributes', SetPedCombatAttributes, ped, 46, true)
    try(id, 'SetPedAlertness', SetPedAlertness, ped, 0)
    try(id, 'SetBlockingOfNonTemporaryEvents', SetBlockingOfNonTemporaryEvents, ped, true)
    try(id, 'SetPedRelationshipGroupHash', SetPedRelationshipGroupHash, ped, GetHashKey('BS_ZOMBIE'))
    end

    if on(2) then
    local mob = Zombies.Mobility or {}
    try(id, 'SetPedPathCanUseClimbovers', SetPedPathCanUseClimbovers, ped, mob.pathClimbovers == true)
    try(id, 'SetPedPathCanUseLadders', SetPedPathCanUseLadders, ped, mob.pathLadders == true)
    try(id, 'SetPedPathCanDropFromHeight', SetPedPathCanDropFromHeight, ped, mob.pathDropFromHeight == true)
    try(id, 'SetPedPathClimbCostModifier', SetPedPathClimbCostModifier, ped, (mob.climbCostModifier or 10.0) + 0.0)
    for _, pair in ipairs(mob.configFlags or {}) do
        if type(pair[1]) == 'number' then
            try(id, ('SetPedConfigFlag(%d)'):format(pair[1]), SetPedConfigFlag, ped, pair[1], pair[2] == true)
        end
    end
    try(id, 'SetPedCanRagdollFromPlayerImpact', SetPedCanRagdollFromPlayerImpact, ped, false)
    end

    if on(4) then
    try(id, 'SetEntityInvincible', SetEntityInvincible, ped, false)
    try(id, 'SetEntityProofs', SetEntityProofs, ped, false, false, false, false, false, false, false, false)
    try(id, 'SetEntityCanBeDamaged', SetEntityCanBeDamaged, ped, true)
    -- The engine pool only drives the hit detector's range; real health lives in the registry
    if GetEntityMaxHealth(ped) < ENGINE_HP then
        try(id, 'SetPedMaxHealth', SetPedMaxHealth, ped, ENGINE_HP)
        try(id, 'SetEntityHealth', SetEntityHealth, ped, ENGINE_HP)
    end
    end
    if on(8) then
    try(id, 'DisablePedPainAudio', DisablePedPainAudio, ped, true)
    try(id, 'SetAmbientVoiceName', SetAmbientVoiceName, ped, 'ALIENS')
    end

    if on(16) then pcall(function()
        if def.senseRadius then SetPedSeeingRange(ped, def.senseRadius + 0.0) end
        if def.hearRadius then SetPedHearingRange(ped, def.hearRadius + 0.0) end
        SetPedConfigFlag(ped, 281, true)    -- no writhe
        -- Flags 166 and 208 are off for walkers
        if (Zombies.Settings or {}).legacyPedFlags == true then
            SetPedConfigFlag(ped, 166, true)
            SetPedConfigFlag(ped, 208, true)
        end
        local render = Zombies.Render or {}
        SetEntityLodDist(ped, render.lodDistance or 325)
        SetPedLodMultiplier(ped, render.lodMultiplier or 3.5)
    end) end

    local st = bags(ped)
    if st and not st.zApp then
        applyAppearance(ped, id)
        TriggerServerEvent('bs:z:net:app', id)
    end
    entry.configuredBy = GetGameTimer()
    return true
end


-- Gait - every client, owner or not

local function setLoaded(name)
    if type(name) ~= 'string' or name == '' then return false end
    if HasAnimSetLoaded(name) then return true end
    RequestAnimSet(name)
    return false
end

local function applyGait(entry)
    local set = entry.gait
    local ped = entry.ped
    if type(set) ~= 'string' or not DoesEntityExist(ped) then return end
    if IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) then return end
    if not setLoaded(set) then return end
    local ok, cur = pcall(GetPedMovementClipset, ped)
    local want = GetHashKey(set)
    if ok and type(cur) == 'number' and (cur & 0xFFFFFFFF) == (want & 0xFFFFFFFF) then return end
    SetPedMovementClipset(ped, set, 0.25)
    entry.appliedGait = set
    entry.gaitFixes = (entry.gaitFixes or 0) + 1
end

-- Ground: a ped the server created without a known z (frozen at z=0)

local grounding = {}

local function groundIt(entry)
    local ped, id = entry.ped, entry.id
    if grounding[ped] then return end
    grounding[ped] = true
    CreateThread(function()
        local untilT = GetGameTimer() + 8000
        local at = GetEntityCoords(ped)
        local gz
        -- Avoid rooftop spawns: a top-down probe from 1000 m finds the highest surface, which in a town is a roof
        local gx, gy = at.x, at.y
        while GetGameTimer() < untilT and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) do
            RequestCollisionAtCoord(at.x, at.y, at.z)
            local okS, c = GetSafeCoordForPed(at.x, at.y, at.z, true, 16)
            if okS and c and #(vector2(c.x, c.y) - vector2(at.x, at.y)) < 25.0 then
                gx, gy, gz = c.x, c.y, c.z
                break
            end
            local found, z = GetGroundZFor_3dCoord(at.x, at.y, at.z + 3.0, false)
            if found and z and z > -100.0 then gz = z break end
            if GetGameTimer() > untilT - 4000 then
                found, z = GetGroundZFor_3dCoord(at.x, at.y, 1000.0, false)
                if found and z and z > -100.0 then gz = z break end
            end
            Wait(250)
        end
        if gz and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            at = vector3(gx, gy, at.z)
            SetEntityCoordsNoOffset(ped, at.x, at.y, gz + 0.05, false, false, false)
            FreezeEntityPosition(ped, false)
            TriggerServerEvent('bs:z:net:grounded', id, gz + 0.05)
        end
        grounding[ped] = nil
    end)
end

-- Adoption

local function recordFor(id, ped, st)
    local rec = Zed.shadow and Zed.shadow[id]
    local at = GetEntityCoords(ped)
    if not rec then
        rec = {
            id = id, t = st.zType or 'walker', m = nil,
            hp = nil, mhp = st.zMhp, s = st.zState or 'idle',
            r = st.zReach and 1 or 0, e = st.zFeed and 1 or 0, p = 'net',
        }
    end
    rec.x, rec.y, rec.z, rec.h = at.x, at.y, at.z, GetEntityHeading(ped)
    return rec
end

local function adopt(ped, id)
    local st = bags(ped)
    if not st then return end
    local rec = recordFor(id, ped, st)
    local def = Zombies.Types[rec.t] or Zombies.Types.walker
    local crippled = false
    if st.zCrawl and Zombies.Types.crawler then def = Zombies.Types.crawler; crippled = true end
    local voiceLurk, voiceEat, voicePitch
    if Zombies.VoicesFor then voiceLurk, voiceEat, voicePitch = Zombies.VoicesFor(id) end

    Zed.owned[ped] = id
    local entry = {
        id = id, ped = ped, rec = rec, def = def,
        bornAt = GetGameTimer(),
        typeId = rec.t, model = rec.m, key = tostring(id),
        gait = st.zGait or nil,
        voiceLurk = voiceLurk, voiceEat = voiceEat, voicePitch = voicePitch,
        reacher = rec.r == 1 or st.zReach == true,
        path = 'net',
        -- Never grab from a bag
        state = ((st.zState ~= 'grab') and st.zState) or ((rec.s ~= 'grab') and rec.s) or 'idle',
        sync = { x = rec.x, y = rec.y, z = rec.z, h = rec.h },
        hp = rec.hp,
        hosted = false,
        crippled = crippled or nil,
        net = NetworkGetNetworkIdFromEntity(ped),
        nextSound = GetGameTimer() + math.random(2000, 12000),
        nextThink = GetGameTimer() + math.random(0, (Zombies.Settings.aiTick or 400)),
    }
    if entry.gait == false then entry.gait = nil end
    Zed.live[id] = entry
    Zed.count = (Zed.count or 0) + 1
    applyGait(entry)
    -- A freshly created server ped is a plain civilian until configured, and the ownership loop only does that on its next 200 ms pass
    if NetworkGetEntityOwner(ped) == PlayerId() and NetworkHasControlOfEntity(ped) then
        entry.hosted = true
        Zed.hosted[id] = true
        configureOwned(entry)
        entry.nextThink = GetGameTimer()
        if st.zGround then groundIt(entry) end
        TriggerServerEvent('bs:z:materialised', id)
    end
end

local function drop(id, entry)
    if Zombies.ClearMeal then pcall(Zombies.ClearMeal, entry) end
    if entry.ped then Zed.ForgetPed(entry.ped) end
    Zed.live[id] = nil
    Zed.hosted[id] = nil
    Zed.count = math.max(0, (Zed.count or 0) - 1)
end

-- Pool scan: every bsZombie ped this client can see becomes a live entry.
CreateThread(function()
    while true do
        Wait(300)
        local ok, pool = pcall(GetGamePool, 'CPed')
        if ok and type(pool) == 'table' then
            for _, ped in ipairs(pool) do
                if NetworkGetEntityIsNetworked(ped) and not Zed.owned[ped]
                   and IsPedHuman(ped) and GetPedType(ped) ~= 28 then
                    local id = Zed.NetIdOf(ped, false)
                    if id and Zed.netRemoved[id] and NetworkGetEntityOwner(ped) == PlayerId() then
                        Zed.netRemoved[id] = nil
                    end
                    if id and not Zed.netRemoved[id] then
                        local cur = Zed.live[id]
                        if cur and cur.ped ~= ped then
                            -- replaced by the server (old entity deleted)
                            if not DoesEntityExist(cur.ped) or not cur.net then drop(id, cur); cur = nil end
                        end
                        if not cur then adopt(ped, id) end
                    end
                end
            end
        end
    end
end)

-- Ownership / bags / gait, five times a second.
CreateThread(function()
    local me = PlayerId()
    while true do
        Wait(200)
        me = PlayerId()
        for id, entry in pairs(Zed.live) do
            local ped = entry.ped
            if entry.net and ped and DoesEntityExist(ped) and not entry.dying then
                local st = bags(ped)
                if st and st.bsZombieDead then
                    -- became a corpse without our bs:z:dead (late join): stop driving it
                    entry.hosted = false
                    Zed.hosted[id] = nil
                else
                    local mine = NetworkGetEntityOwner(ped) == me and NetworkHasControlOfEntity(ped)
                    if mine ~= entry.hosted then
                        entry.hosted = mine
                        Zed.hosted[id] = mine or nil
                        if mine then
                            if entry.state == 'grab' then entry.state = 'idle' end
                            configureOwned(entry)
                            entry.nextThink = GetGameTimer()
                            if st and st.zGround then groundIt(entry) end
                            TriggerServerEvent('bs:z:materialised', id)
                            -- pick up where the last owner left off
                            if st and st.zFeed and entry.state ~= 'feeding' and Zombies.GoFeed then
                                pcall(Zombies.GoFeed, entry)
                            end
                        end
                    end
                    if st then
                        local g = st.zGait
                        if g == false then g = nil end
                        if g ~= entry.gait then entry.gait = g end
                        -- zType is set right after CreatePed in a separate bag write
                        if st.zType and st.zType ~= entry.typeId and not entry.crippled
                           and Zombies.Types[st.zType] then
                            entry.typeId = st.zType
                            entry.def = Zombies.Types[st.zType]
                            if entry.rec then entry.rec.t = st.zType end
                        end
                        if st.zCrawl and not entry.crippled and Zombies.Types.crawler then
                            entry.def = Zombies.Types.crawler
                            entry.crippled = true
                            entry.gait = nil
                        end
                        if not entry.hosted and type(st.zState) == 'string' and st.zState ~= 'grab' then
                            entry.state = st.zState
                        end
                    end
                    if not entry.hosted then applyGait(entry) end
                end
            end
        end
    end
end)

-- The server removed / killed it: never re-adopt that id until it is announced again.
AddEventHandler('bs:z:rm', function(ids, reason)
    -- A removal without a reason is the registry's per-player stream drop (out of its 360 m list), not a deletion
    if reason == nil then return end
    if type(ids) == 'number' then ids = { ids } end
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        if id then Zed.netRemoved[id] = true end
    end
end)
AddEventHandler('bs:z:dead', function(id)
    id = tonumber(id)
    if id then Zed.netRemoved[id] = true end
end)
AddEventHandler('bs:z:add', function(list)
    for _, rec in ipairs(list or {}) do
        if rec and rec.id then Zed.netRemoved[rec.id] = nil end
    end
end)

-- A corpse that nobody killed: the server asks its owner to.
RegisterNetEvent('bs:z:netkill', function(netId)
    netId = tonumber(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return end
    local ped = NetToPed(netId)
    if ped ~= 0 and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and not IsEntityDead(ped) then
        ClearPedTasks(ped)
        SetEntityHealth(ped, 0)
    end
end)

-- FPS report (server caps zombies around low-FPS clients)

local frames = 0
CreateThread(function()
    while true do
        Wait(0)
        frames = frames + 1
    end
end)
CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(math.max(2000, math.floor(tonumber(N().fpsReportMs) or 5000)))
        local now = GetGameTimer()
        local fps = frames * 1000.0 / math.max(1, now - last)
        frames, last = 0, now
        TriggerServerEvent('bs:z:net:fps', math.floor(fps + 0.5))
    end
end)

-- /znetc - this client's view

RegisterCommand('znetc', function()
    local me = GetEntityCoords(PlayerPedId())
    local n, mine = 0, 0
    for id, entry in pairs(Zed.live) do
        if entry.net and DoesEntityExist(entry.ped) then
            n = n + 1
            if entry.hosted then mine = mine + 1 end
            local ok, cur = pcall(GetPedMovementClipset, entry.ped)
            print(('[znet] #%s net=%s d=%.0f owner=%s mine=%s state=%s gait=%s clip=%s'):format(
                tostring(id), tostring(entry.net), #(GetEntityCoords(entry.ped) - me),
                tostring(NetworkGetEntityOwner(entry.ped)), tostring(entry.hosted),
                tostring(entry.state), tostring(entry.gait), ok and tostring(cur) or 'ERR'))
        end
    end
    print(('[znet] adopted %d networked walker(s), %d owned by me, %d bsZombie peds in pool')
        :format(n, mine, Zed.NetVisibleCount()))
end, false)
