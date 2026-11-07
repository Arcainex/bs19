-- bs_zombies - client side of networked walkers (Zombies.Mode = 'networked')

if Zombies.Mode == 'legacy' then return end

local function N() return Zombies.Net or {} end
local ENGINE_HP = (Zombies.Detector and Zombies.Detector.engineHealthPool) or 20000

Zed.netRemoved = Zed.netRemoved or {}   -- [id] = true: server said rm/dead; do not re-adopt
Zed.deadIds = Zed.deadIds or {}         -- [id] = ms: died; never a live walker again, whatever its bags say
local blockedLog = {}
local function respawnBlocked(id, why)
    if blockedLog[id] then return end
    blockedLog[id] = true
    print(('[BS ZOMBIES] RESPAWN BLOCKED id=%s (%s)'):format(tostring(id), why))
end

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

local function applyLook(ped, look)
    if type(look) ~= 'table' or type(look.c) ~= 'table' or #look.c < 12 then return false end
    for comp = 0, 11 do
        local e = look.c[comp + 1]
        local d, t = tonumber(e and e[1]), tonumber(e and e[2])
        if d and t and IsPedComponentVariationValid(ped, comp, d, t) then SetPedComponentVariation(ped, comp, d, t, 0) end
    end
    for _, e in ipairs(type(look.p) == 'table' and look.p or {}) do
        local prop, d, t = tonumber(e[1]), tonumber(e[2]), tonumber(e[3])
        if prop then
            if d and d >= 0 then SetPedPropIndex(ped, prop, d, math.max(0, t or 0), true) else ClearPedProp(ped, prop) end
        end
    end
    return true
end

local function applyAppearance(ped, id)
    -- A promoted filler walker keeps the exact look it had as filler
    local st = Entity(ped).state
    if st and st.zLook and applyLook(ped, st.zLook) then return end
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
        try(id, 'SetEntityMaxHealth', SetEntityMaxHealth, ped, ENGINE_HP)
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

local function inWater(x, y, z)
    local okW, has, wz = pcall(GetWaterHeight, x, y, z + 2.0)
    if okW and has and tonumber(wz) and wz > z - 0.4 then return true end
    local okP, hit, hz = pcall(TestVerticalProbeAgainstAllWater, x, y, z + 2.0, 0)
    if okP and (hit == true or hit == 1) and tonumber(hz) and hz > z - 0.4 then return true end
    return false
end

-- The ped was created frozen at its spawn level (a road node, navmesh or the filler's feet), or at z 0 with no level.
-- Ground is only accepted at that level: a bridge deck stays a deck, a tunnel floor stays a tunnel floor, and a
-- roof or the sea is refused. Nothing is unfrozen until this succeeds, so no walker ever drops from the sky.
local function groundIt(entry)
    local ped, id = entry.ped, entry.id
    if grounding[ped] then return end
    grounding[ped] = true
    CreateThread(function()
        local untilT = GetGameTimer() + 8000
        local at = GetEntityCoords(ped)
        local level = at.z > 1.0 and at.z or nil
        local gx, gy, gz
        local why = 'noGround'
        while GetGameTimer() < untilT and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) do
            if not level then
                -- No level from the server: the nearest road node gives it (never the player's height)
                local me = GetEntityCoords(PlayerPedId())
                local okR, road = GetClosestVehicleNode(at.x, at.y, me.z, 1, 3.0, 0)
                if okR and road and road.x and (road.x - at.x) ^ 2 + (road.y - at.y) ^ 2 <= 70.0 * 70.0 then level = road.z end
            end
            if level then
                RequestCollisionAtCoord(at.x, at.y, level)
                local okS, c = GetSafeCoordForPed(at.x, at.y, level, true, 16)
                if okS and c then
                    local d = #(vector2(c.x, c.y) - vector2(at.x, at.y))
                    if d < 25.0 and math.abs(c.z - level) <= 2.5 + d * 0.12 then
                        if inWater(c.x, c.y, c.z) then why = 'water' else gx, gy, gz = c.x, c.y, c.z break end
                    end
                end
                local found, z = GetGroundZFor_3dCoord(at.x, at.y, level + 3.0, false)
                if found and z and z > -100.0 and math.abs(z - level) <= 3.0 then
                    if inWater(at.x, at.y, z) then why = 'water' else gx, gy, gz = at.x, at.y, z break end
                end
            end
            Wait(250)
        end
        if gz and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            SetEntityCoordsNoOffset(ped, gx, gy, gz + 0.05, false, false, false)
            FreezeEntityPosition(ped, false)
            TriggerServerEvent('bs:z:net:grounded', id, gz + 0.05)
        elseif DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            TriggerServerEvent('bs:z:net:groundFailed', id, why)
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
        pace = Zombies.Mode == 'networked_plus' and st.zPace or nil,
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
                -- A recycled handle still claimed by a walker that is gone would hide this ped forever
                local claim = Zed.owned[ped]
                if claim and NetworkGetEntityIsNetworked(ped) then
                    local bagId = Zed.NetIdOf(ped, false)
                    if bagId and bagId ~= claim then
                        -- A recycled handle: the claim (and a live entry pointing at it) belongs to a walker that is gone.
                        -- Hits on this ped were reported under the wrong id and never counted.
                        local stale = Zed.live[claim]
                        if stale and stale.ped == ped then
                            Zed.live[claim] = nil
                            Zed.hosted[claim] = nil
                            Zed.count = math.max(0, (Zed.count or 0) - 1)
                        end
                        Zed.owned[ped] = nil
                    end
                end
                if NetworkGetEntityIsNetworked(ped) and not Zed.owned[ped]
                   and IsPedHuman(ped) and GetPedType(ped) ~= 28 and not IsEntityDead(ped) then
                    local id = Zed.NetIdOf(ped, false)
                    if id and Zed.deadIds[id] then
                        respawnBlocked(id, 'client: a dead walker id showed up alive')
                        id = nil
                    end
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
                    -- Still waiting for ground (a first try may have run before control arrived)
                    if mine and st and st.zGround and not grounding[ped] then groundIt(entry) end
                    if st then
                        entry.pace = Zombies.Mode == 'networked_plus' and st.zPace or nil
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
-- Death on this client: the owner makes sure the ped really dies and tells the server (bs:z:net:deadAck).
-- Runs for every death, also for a ped that never became a live entry here (cl_combat only handles those).
local function pedFor(net, id)
    net = tonumber(net)
    if net and net > 0 and NetworkDoesNetworkIdExist(net) then
        local p = NetToPed(net)
        if p and p ~= 0 and DoesEntityExist(p) then return p end
    end
    local e = id and Zed.live[id]
    if e and e.ped and DoesEntityExist(e.ped) then return e.ped end
    return nil
end

-- Net ids are reused: only act on a ped that still carries this walker's id
local function isWalker(ped, id)
    if not ped or not id then return false end
    local st = bags(ped)
    return st ~= nil and tonumber(st.bsZombie) == id
end

local function killPed(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    -- Anything that could keep it standing goes first
    pcall(SetEntityInvincible, ped, false)
    pcall(SetEntityCanBeDamaged, ped, true)
    pcall(SetEntityProofs, ped, false, false, false, false, false, false, false, false)
    pcall(FreezeEntityPosition, ped, false)
    pcall(ClearPedTasks, ped)
    pcall(SetEntityHealth, ped, 0)
end

local confirming = {}
local function confirmDeath(id, net)
    if confirming[id] then return end
    confirming[id] = true
    CreateThread(function()
        -- cl_combat's death queue kills it first with the proper ragdoll; this only finishes the job
        Wait(300)
        local untilAt = GetGameTimer() + 4000
        while GetGameTimer() < untilAt do
            local ped = pedFor(net, id)
            if not ped then break end
            if not NetworkGetEntityIsNetworked(ped) or not isWalker(ped, id) then break end
            if NetworkHasControlOfEntity(ped) then
                if not IsEntityDead(ped) then killPed(ped) end
                if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
                    TriggerServerEvent('bs:z:net:deadAck', id, NetworkGetNetworkIdFromEntity(ped))
                    break
                end
            end
            Wait(150)
        end
        confirming[id] = nil
    end)
end

AddEventHandler('bs:z:dead', function(id, info)
    id = tonumber(id)
    if not id then return end
    Zed.netRemoved[id] = true
    Zed.deadIds[id] = GetGameTimer()
    local e = Zed.live[id]
    local net = (type(info) == 'table' and tonumber(info.net)) or (e and e.net) or nil
    confirmDeath(id, net)
end)
AddEventHandler('bs:z:add', function(list)
    for _, rec in ipairs(list or {}) do
        if rec and rec.id then Zed.netRemoved[rec.id] = nil end
    end
end)

-- The server killed this walker and nobody confirmed the ped died: whoever controls it kills it,
-- everyone else stops treating it as a live walker. The server deletes it if that is still not enough.
RegisterNetEvent('bs:z:netkill', function(netId, id)
    netId, id = tonumber(netId), tonumber(id)
    if id then
        Zed.netRemoved[id] = true
        -- Still a live entry here: our bs:z:dead never ran for it, so run the normal death (body, loot) now
        local e = Zed.live[id]
        if e and not e.dying then TriggerEvent('bs:z:dead', id, { net = netId, forced = true }) end
    end
    if not netId or not NetworkDoesNetworkIdExist(netId) then return end
    local ped = NetToPed(netId)
    if id and not isWalker(ped, id) then return end
    if ped ~= 0 and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
        killPed(ped)
        if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
            TriggerServerEvent('bs:z:net:deadAck', id or 0, netId)
        end
    end
end)

-- The server has no record for a walker we shot: the ped is a leftover. Drop it, and delete it if it is ours.
RegisterNetEvent('bs:z:nosuch', function(id)
    id = tonumber(id)
    local e = id and Zed.live[id]
    if not e or not e.net then return end
    local ped = e.ped
    Zed.netRemoved[id] = true
    Zed.nosuchDropped = (Zed.nosuchDropped or 0) + 1
    if not (ped and DoesEntityExist(ped) and isWalker(ped, id)) then
        -- The entry is stale and its handle now belongs to another walker: drop the entry, leave that ped alone
        Zed.live[id] = nil
        Zed.hosted[id] = nil
        Zed.count = math.max(0, (Zed.count or 0) - 1)
        if ped and Zed.owned[ped] == id then Zed.owned[ped] = nil end
        return
    end
    print(('[BS ZNET] walker %d has no server record - dropped the leftover ped'):format(id))
    drop(id, e)
    if ped and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and not IsEntityDead(ped) then
        pcall(SetEntityAsMissionEntity, ped, true, true)
        pcall(DeleteEntity, ped)
    end
end)

-- /zinspect: this client's view of one walker
local function inspectView(id)
    local e = Zed.live[id]
    local ped = e and e.ped
    if not (ped and DoesEntityExist(ped)) then
        ped = nil
        local ok, pool = pcall(GetGamePool, 'CPed')
        for _, p in ipairs(ok and pool or {}) do
            local st = NetworkGetEntityIsNetworked(p) and bags(p)
            if st and tonumber(st.bsZombie) == id then ped = p break end
        end
    end
    local head = ('live entry %s hosted %s dying %s state %s entry.hp %s | removed flag %s')
        :format(tostring(e ~= nil), tostring(e and e.hosted), tostring(e and e.dying), tostring(e and e.state),
                tostring(e and e.hp), tostring(Zed.netRemoved[id] == true))
    if not ped then return head .. ' | no ped with this id here' end
    local st = bags(ped) or {}
    local okD, canDmg = pcall(function() return GetEntityCanBeDamaged(ped) end)
    local proofs = '?'
    pcall(function()
        local r = table.pack(GetEntityProofs(ped))
        local t = {}
        for i = 2, math.min(r.n, 9) do t[#t + 1] = (r[i] == true or r[i] == 1) and '1' or '0' end
        if #t > 0 then proofs = table.concat(t) end
    end)
    local me = PlayerId()
    return head .. (' | ped net %s owner me %s control %s | dead %s health %d/%d | canBeDamaged %s proofs(b,f,e,c,m,s,..) %s | ragdoll %s frozen? %s anim %s | bags zHp %s zMhp %s dead %s zFeed %s zCrawl %s | claim %s')
        :format(tostring(NetworkGetEntityIsNetworked(ped) and NetworkGetNetworkIdFromEntity(ped) or 'local'),
                tostring(NetworkGetEntityOwner(ped) == me), tostring(NetworkHasControlOfEntity(ped)),
                tostring(IsEntityDead(ped)), GetEntityHealth(ped), GetEntityMaxHealth(ped),
                okD and tostring(canDmg) or '?', proofs, tostring(IsPedRagdoll(ped)),
                tostring(IsEntityPositionFrozen and IsEntityPositionFrozen(ped) or '?'),
                tostring(GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_PLAY_ANIM')) ~= 7),
                tostring(st.zHp), tostring(st.zMhp), tostring(st.bsZombieDead), tostring(st.zFeed), tostring(st.zCrawl),
                tostring(Zed.owned[ped]))
end

RegisterNetEvent('bs:z:inspectq', function(id, requester)
    id = tonumber(id)
    if not id then return end
    local ok, view = pcall(inspectView, id)
    TriggerServerEvent('bs:z:inspecta', id, requester, ok and view or ('error: ' .. tostring(view)))
end)

-- No id given: the walker in the crosshair (prone and feeding walkers miss a plain ray, so the nearest one to the ray counts too)
RegisterNetEvent('bs:z:inspectcast', function()
    local from = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local to = from + dir * 80.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, -1, PlayerPedId(), 4)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    local id
    if (hit == 1 or hit == true) and ent and ent ~= 0 and IsEntityAPed(ent) then
        id = Zed.owned[ent] or Zed.NetIdOf(ent, true)
    end
    if not id then
        local best = 1.5
        for wid, e in pairs(Zed.live) do
            if e.ped and DoesEntityExist(e.ped) then
                local p = GetEntityCoords(e.ped)
                local t = (p - from).x * dir.x + (p - from).y * dir.y + (p - from).z * dir.z
                if t > 0.0 and t < 80.0 then
                    local d = #(p - (from + dir * t))
                    if d < best then best, id = d, wid end
                end
            end
        end
    end
    TriggerServerEvent('bs:z:inspecthit', id or 0)
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

-- Why bsZombie peds near this client are not live entries (F10 diagnostics)
function Zed.NetDiag(radius)
    local me = GetEntityCoords(PlayerPedId())
    local r2 = (radius or 120.0) ^ 2
    local out = { bagged = 0, adopted = 0, removed = 0, claimed = 0, notHuman = 0, dead = 0 }
    local ok, pool = pcall(GetGamePool, 'CPed')
    for _, ped in ipairs(ok and pool or {}) do
        local c = GetEntityCoords(ped)
        if (c.x - me.x) ^ 2 + (c.y - me.y) ^ 2 <= r2 then
            local id = Zed.NetIdOf(ped, false)
            if id then
                out.bagged = out.bagged + 1
                local e = Zed.live[id]
                if e and e.ped == ped then out.adopted = out.adopted + 1
                elseif Zed.netRemoved[id] then out.removed = out.removed + 1
                elseif Zed.owned[ped] then out.claimed = out.claimed + 1
                elseif not IsPedHuman(ped) or GetPedType(ped) == 28 then out.notHuman = out.notHuman + 1 end
                if IsEntityDead(ped) then out.dead = out.dead + 1 end
            end
        end
    end
    return out
end
exports('NetDiag', function(radius) return Zed.NetDiag(radius) end)

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

-- F1 validates custom ped choices locally before submitting a population recipe.
exports('ValidateArchetypeModels', function(models)
    local invalid = {}
    if type(models) ~= 'table' then return { ok=false, invalid={'Invalid model list'} } end
    for _, name in ipairs(models) do
        if type(name) ~= 'string' or #name > 99 or not name:match('^[%w_]+$') then
            invalid[#invalid+1] = tostring(name)
        else
            local hash=GetHashKey(name)
            if not IsModelInCdimage(hash) or not IsModelValid(hash) or not IsModelAPed(hash) then invalid[#invalid+1]=name end
        end
    end
    return {ok=#invalid==0,invalid=invalid}
end)
