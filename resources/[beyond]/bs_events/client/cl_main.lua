-- bs_events - client: builds each event's scene locally (plane, crates, wrecks, flare, blips)

local Scenes = {}          -- [evId] = scene
local busy = false
local dropTarget       -- defined with the target helpers below

local SOUNDS = {
    airdrop = { 'Flyover', 'DLC_Exec_Buy_Air_Drop_Sounds' },
    stash   = { 'Event_Message_Purple', 'GTAO_FM_Events_Soundset' },
    convoy  = { 'Air_Defences_Activated', 'DLC_sum20_Business_Battle_AC_Sounds' },
    horde   = { 'Distant_Sirens', 'FBI_04_HEAT_SOUNDS' },
}

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(20) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadPtfx(dict)
    RequestNamedPtfxAsset(dict)
    local t = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(dict) and GetGameTimer() < t do Wait(20) end
    return HasNamedPtfxAssetLoaded(dict)
end

local function groundZ(x, y, z)
    for _, probe in ipairs({ z + 50.0, z + 150.0, 1000.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(x, y, probe, false)
        if ok then return gz end
    end
    return z
end

local function remove(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function loc(s)
    if type(s) == 'string' and s:sub(1, 4) == 'loc:' then return L(s:sub(5)) end
    return s
end

local function blipName(blip, text)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandSetBlipName(blip)
end

-- Scene pieces

local function crateFx(scene, c)
    if c.fx then return end
    c.fx = {}
    if scene.kind == 'airdrop' and loadPtfx('scr_oddjobtraffickingair') then
        UseParticleFxAsset('scr_oddjobtraffickingair')
        local h = StartParticleFxLoopedAtCoord('scr_crate_drop_flare', c.x, c.y, c.gz + 0.3, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
        if h then SetParticleFxLoopedColour(h, 1.0, 0.12, 0.08, false); c.fx[#c.fx + 1] = h end
    end
    if scene.kind == 'airdrop' and loadPtfx('core') then
        UseParticleFxAsset('core')
        local h = StartParticleFxLoopedAtCoord('ent_amb_smoke_foundry', c.x, c.y, c.gz + 0.5, 0.0, 0.0, 0.0, 1.2, false, false, false, false)
        if h then c.fx[#c.fx + 1] = h end
    end
    if scene.kind == 'airdrop' then
        c.sound = GetSoundId()
        PlaySoundFromCoord(c.sound, 'Crate_Beeps', c.x, c.y, c.gz, 'MP_CRATE_DROP_SOUNDS', false, 40, false)
    end
end

local function crateBlip(scene, c)
    if c.blip or scene.kind == 'horde' then return end
    if scene.kind == 'airdrop' and not c.landed then return end
    local b = Events.Blips[scene.kind] or {}
    c.blip = AddBlipForCoord(c.x, c.y, c.gz or c.z)
    SetBlipSprite(c.blip, b.sprite or 1)
    SetBlipColour(c.blip, b.colour or 1)
    SetBlipScale(c.blip, 0.85)
    SetBlipAsShortRange(c.blip, false)
    blipName(c.blip, loc(c.label) or L('ev.event'))
end

local function placeCrate(scene, c)
    if c.ent or c.gone then return end
    local hash = loadModel(c.model)
    if not hash then return end
    c.gz = c.gz or groundZ(c.x, c.y, c.z)
    c.ent = CreateObject(hash, c.x, c.y, c.gz, false, false, false)
    SetEntityHeading(c.ent, c.h or 0.0)
    PlaceObjectOnGroundProperly(c.ent)
    FreezeEntityPosition(c.ent, true)
    SetModelAsNoLongerNeeded(hash)
    c.landed = true
    crateFx(scene, c)
    crateBlip(scene, c)
end

local function dropCrate(scene, c)
    c.label = L('ev.crate_airdrop')
    CreateThread(function()
        local v = scene.visual
        local hash = loadModel(c.model)
        local chuteHash = loadModel(v.chute)
        if not hash then return end
        local gz = groundZ(c.x, c.y, c.z)
        c.gz = gz
        local top = gz + v.height
        local ent = CreateObject(hash, c.x, c.y, top, false, false, false)
        FreezeEntityPosition(ent, true)
        SetEntityCollision(ent, false, false)
        local chute
        if chuteHash then
            chute = CreateObject(chuteHash, c.x, c.y, top, false, false, false)
            AttachEntityToEntity(chute, ent, 0, 0.0, 0.0, 0.2, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        end
        PlaySoundFromCoord(-1, 'Air_Drop_Parachute', c.x, c.y, top, 'DLC_SM_Generic_Mission_Sounds', false, 0, false)
        c.falling = { ent = ent, chute = chute }
        while Scenes[scene.id] == scene and not c.gone do
            local t = GetGameTimer() - c.landLocal + v.fallMs
            if t >= v.fallMs then break end
            local z = top - (top - gz) * (t / v.fallMs)
            SetEntityCoordsNoOffset(ent, c.x, c.y, z, false, false, false)
            SetEntityHeading(ent, (c.h or 0.0) + t * 0.004)
            Wait(0)
        end
        remove(chute); remove(ent)
        c.falling = nil
        if Scenes[scene.id] == scene and not c.gone then
            PlaySoundFromCoord(-1, 'Parachute_Land', c.x, c.y, gz, 'DLC_Exec_Air_Drop_Sounds', false, 0, false)
            placeCrate(scene, c)
        end
    end)
end

local function flyPlane(scene)
    local v = scene.visual
    local elapsed = GetGameTimer() - scene.t0
    local total = v.flyMs + 25000
    if elapsed > total then return end
    CreateThread(function()
        local hash = loadModel(v.plane)
        if not hash then return end
        local rad = math.rad(v.heading)
        local fx, fy = -math.sin(rad), math.cos(rad)
        local gz = groundZ(v.x, v.y, v.z)
        local z = gz + v.height + 20.0
        local sx, sy = v.x - fx * v.run, v.y - fy * v.run
        local veh = CreateVehicle(hash, sx, sy, z, v.heading, false, false)
        SetModelAsNoLongerNeeded(hash)
        SetEntityCollision(veh, false, false)
        FreezeEntityPosition(veh, true)
        SetVehicleEngineOn(veh, true, true, false)
        ControlLandingGear(veh, 3)
        SetEntityLodDist(veh, 3000)
        scene.plane = veh
        while Scenes[scene.id] == scene do
            local t = (GetGameTimer() - scene.t0) / 1000.0
            if t * 1000 > total then break end
            local d = t * v.speed
            SetEntityCoordsNoOffset(veh, sx + fx * d, sy + fy * d, z, false, false, false)
            SetEntityHeading(veh, v.heading)
            Wait(0)
        end
        remove(veh)
        scene.plane = nil
    end)
end

-- Convoy driving
local Convoys = {}          -- [evId] = run token

local function netEnt(netId, ms)
    local t = GetGameTimer() + (ms or 6000)
    while GetGameTimer() < t do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local e = NetworkGetEntityFromNetworkId(netId)
            if e ~= 0 and DoesEntityExist(e) then return e end
        end
        Wait(100)
    end
    return nil
end

local function control(ent)
    local t = GetGameTimer() + 3000
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(ent)
        Wait(50)
    end
    return NetworkHasControlOfEntity(ent)
end

-- Ground under a point: load collision, probe from above, retry until found.
local function findGround(x, y, z, ms)
    local t = GetGameTimer() + (ms or 10000)
    while GetGameTimer() < t do
        RequestCollisionAtCoord(x, y, z)
        for _, probe in ipairs({ z + 30.0, z + 120.0, 800.0 }) do
            local ok, gz = GetGroundZFor_3dCoord(x, y, probe, false)
            if ok then return gz end
        end
        Wait(100)
    end
    return nil
end

local function clog(id, msg)
    TriggerServerEvent('bs_events:convoyLog', id, msg)
end

-- Ground under the truck: keep collision requested at the spot, probe, place, wait for collision.
local function snap(veh, u)
    local gz = findGround(u.x, u.y, u.z)
    if not gz then return false end
    SetEntityCoordsNoOffset(veh, u.x, u.y, gz + 1.0, false, false, false)
    SetEntityHeading(veh, u.h)
    local t = GetGameTimer() + 6000
    while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < t do
        RequestCollisionAtCoord(u.x, u.y, gz)
        Wait(50)
    end
    SetVehicleOnGroundProperly(veh)
    return true
end

local function driveTo(ped, veh, p, o)
    TaskVehicleDriveToCoordLongrange(ped, veh, p.x, p.y, p.z, o.speed, o.style, 12.0)
end

local function rnd(a, b) return a + (b - a) * math.random() end

-- Escort gunner setup: tough, accurate, never flees, hates players and zombies.
local function armPed(ped)
    local e = Events.Convoy.escort
    local grp = GetHashKey(e.group or 'BS_CONVOY')
    AddRelationshipGroup(e.group or 'BS_CONVOY')
    SetPedRelationshipGroupHash(ped, grp)
    SetRelationshipBetweenGroups(0, grp, grp)
    for _, other in ipairs({ GetHashKey('PLAYER'), GetHashKey('BS_ZOMBIE') }) do
        SetRelationshipBetweenGroups(5, grp, other)
        SetRelationshipBetweenGroups(5, other, grp)
    end
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityCanBeDamaged(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    if not Entity(ped).state.bsArmed then
        local hp = math.floor(rnd(e.healthMin or 300, e.healthMax or 400))
        SetPedMaxHealth(ped, hp)
        SetEntityHealth(ped, hp)
        SetPedArmour(ped, e.armour or 100)
        pcall(function() Entity(ped).state:set('bsArmed', true, true) end)
    end
    SetCurrentPedWeapon(ped, GetBestPedWeapon(ped, false), true)
    SetPedAccuracy(ped, math.floor(rnd(e.accuracyMin or 45, e.accuracyMax or 60)))
    SetPedCombatAbility(ped, e.ability or 2)
    SetPedCombatRange(ped, math.random(e.rangeMin or 1, e.rangeMax or 2))
    SetPedCombatMovement(ped, e.movement or 1)
    SetPedAlertness(ped, 3)
    SetPedSuffersCriticalHits(ped, false)
    SetPedCanBeDraggedOut(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)       -- fight to the end
    SetPedCombatAttributes(ped, 5, true)        -- always fight
    SetPedCombatAttributes(ped, 17, false)      -- never flee
    SetPedCombatAttributes(ped, 0, true)        -- use cover
    SetPedCombatAttributes(ped, 1, true)
    SetPedCombatAttributes(ped, 2, true)        -- drive-bys
    SetPedCombatAttributes(ped, 3, true)        -- may leave the vehicle
end

-- Stop the vehicles, escorts bail out and fight. f = { ped, veh, drv, kind }
local function engage(list, firstTime)
    local e = Events.Convoy.escort
    if firstTime then
        for _, f in ipairs(list) do
            if f.drv and f.veh and DoesEntityExist(f.veh) then
                TaskVehicleTempAction(f.ped, f.veh, 27, 20000)
                SetVehicleHandbrake(f.veh, true)
            end
            if DoesEntityExist(f.ped) and not IsPedDeadOrDying(f.ped, true) and IsPedInAnyVehicle(f.ped, false)
               and (not f.drv or f.kind == 'escort') and f.veh and DoesEntityExist(f.veh) then
                TaskLeaveVehicle(f.ped, f.veh, 0)
            end
        end
        Wait(2500)
    end
    for _, f in ipairs(list) do
        if DoesEntityExist(f.ped) and not IsPedDeadOrDying(f.ped, true) and not IsPedInCombat(f.ped, 0)
           and (not IsPedInAnyVehicle(f.ped, false) or f.kind == 'truck') then
            TaskCombatHatedTargetsAroundPed(f.ped, e.hateRadius or 120.0, 0)
        end
    end
end

local Arming = {}           -- [evId] = token, escorts this client fights with after a stop

RegisterNetEvent('bs_events:convoyArm', function(o)
    local token = {}
    Arming[o.id] = token
    CreateThread(function()
        local list = {}
        for _, d in ipairs(o.peds or {}) do
            local ped = netEnt(d.ped, 4000)
            if ped and control(ped) then
                armPed(ped)
                list[#list + 1] = { ped = ped, veh = d.veh and netEnt(d.veh, 1500) or nil, drv = d.drv, kind = d.kind }
            end
        end
        if not o.fight then return end
        engage(list, true)
        while Arming[o.id] == token do
            Wait(3000)
            local mine = 0
            for _, f in ipairs(list) do
                if DoesEntityExist(f.ped) and NetworkGetEntityOwner(f.ped) == PlayerId() then mine = mine + 1 end
            end
            if mine == 0 then return end
            engage(list, false)
        end
    end)
end)

-- Cargo trucks are tough: players must stop them (kill the driver, shoot the tyres), not wreck them
local function makeSturdy(veh)
    local cg = Events.Convoy.cargo or {}
    if not Entity(veh).state.bsSturdy then
        SetVehicleEngineHealth(veh, cg.engineHealth or 3000.0)
        SetVehicleBodyHealth(veh, cg.bodyHealth or 3000.0)
        SetVehiclePetrolTankHealth(veh, cg.tankHealth or 3000.0)
        pcall(function() Entity(veh).state:set('bsSturdy', true, true) end)
    end
    SetVehicleStrong(veh, cg.strong ~= false)
    SetVehicleHasStrongAxles(veh, true)
    SetVehicleTyresCanBurst(veh, cg.tyresCanBurst ~= false)
    SetVehicleExplodesOnHighExplosionDamage(veh, false)
    pcall(SetVehicleDamageModifier, veh, cg.damageScale or 0.25)
end

RegisterNetEvent('bs_events:convoyDrive', function(o)
    local token = {}
    Convoys[o.id] = token
    CreateThread(function()
        local units = {}
        local fighters = {}
        for i, u in ipairs(o.units) do
            local veh, ped = netEnt(u.veh, 10000), netEnt(u.ped, 10000)
            if not veh or not ped then
                clog(o.id, ('unit %d entity missing veh=%s ped=%s (net %s/%s)'):format(i, tostring(veh), tostring(ped), tostring(u.veh), tostring(u.ped)))
                return          -- server resends
            end
            control(veh); control(ped)
            if NetworkGetEntityOwner(veh) ~= PlayerId() then clog(o.id, 'not owner, leaving it to the owner'); return end
            if not o.resume then
                -- stays frozen until real ground is found, then snaps onto it
                local t = GetGameTimer() + 20000
                local snapped = false
                while GetGameTimer() < t do
                    RequestCollisionAtCoord(u.x, u.y, u.z)
                    if snap(veh, u) then snapped = true; break end
                    Wait(250)
                end
                if not snapped then
                    -- timeout: put it down at the spawn height anyway, never leave it hovering
                    RequestCollisionAtCoord(u.x, u.y, u.z)
                    SetEntityCoordsNoOffset(veh, u.x, u.y, u.z + 1.0, false, false, false)
                    SetEntityHeading(veh, u.h)
                    Wait(500)
                    SetVehicleOnGroundProperly(veh)
                end
                clog(o.id, ('unit %d snapped=%s'):format(i, tostring(snapped)))
            end
            FreezeEntityPosition(veh, false)
            SetEntityAsMissionEntity(veh, true, true)
            armPed(ped)
            if GetPedInVehicleSeat(veh, -1) ~= ped then
                SetPedIntoVehicle(ped, veh, -1)
                Wait(100)
                if GetPedInVehicleSeat(veh, -1) ~= ped then TaskWarpPedIntoVehicle(ped, veh, -1) end
            end
            SetDriverAbility(ped, 0.8)
            SetDriverAggressiveness(ped, 0.0)
            SetVehicleEngineOn(veh, true, true, false)
            fighters[#fighters + 1] = { ped = ped, veh = veh, drv = true, kind = u.kind }
            for _, gn in ipairs(u.gunners or {}) do
                local g = netEnt(gn, 3000)
                if g and control(g) then
                    armPed(g)
                    fighters[#fighters + 1] = { ped = g, veh = veh, drv = false, kind = u.kind }
                end
            end
            if u.kind == 'truck' then makeSturdy(veh) end
            units[i] = { veh = veh, ped = ped, u = u }
        end
        if not units[1] then return end
        TriggerServerEvent('bs_events:convoyReady', o.id)
        clog(o.id, ('tasking %d units'):format(#units))

        local leader = units[1]
        local wp = o.wp or 1
        local fight = false
        local function startFight(why)
            if fight then return end
            fight = true
            clog(o.id, 'fight: ' .. why)
            TriggerServerEvent('bs_events:convoyProgress', o.id, wp, true)
            CreateThread(function() engage(fighters, true) end)
        end
        local function orderAll()
            driveTo(leader.ped, leader.veh, o.route[wp], o)
            for i = 2, #units do
                -- trailing vehicles follow the one ahead
                TaskVehicleEscort(units[i].ped, units[i].veh, units[i - 1].veh, -1, o.speed, o.style, o.gap or 9.0, 0, 15.0)
            end
        end
        if o.fight then
            fight = true
            CreateThread(function() engage(fighters, true) end)
        else
            orderAll()
        end

        local last = #o.route
        local stall = 0
        while Convoys[o.id] == token do
            Wait(1500)
            if not DoesEntityExist(leader.veh) then return end
            -- lost ownership: the new owner is re-tasked by the server
            if NetworkGetEntityOwner(leader.veh) ~= PlayerId() then return end
            if fight then
                engage(fighters, false)
            else
                -- attacked: any unit hurt, or a truck disabled
                for _, un in ipairs(units) do
                    if HasEntityBeenDamagedByAnyPed(un.veh) or HasEntityBeenDamagedByAnyPed(un.ped)
                       or IsPedDeadOrDying(un.ped, true) then
                        startFight('attacked')
                        break
                    end
                end
                for _, f in ipairs(fighters) do
                    if not fight and not f.drv and HasEntityBeenDamagedByAnyPed(f.ped) then startFight('attacked') end
                end
                -- a unit that could not snap earlier tries again once its area has loaded
                for _, un in ipairs(units) do
                    if un.u.retry and snap(un.veh, un.u) then un.u.retry = nil end
                end
                -- stuck: speed under 1 for 8 s to reverse briefly, then drive on to the waypoint
                if GetEntitySpeed(leader.veh) < 1.0 then
                    stall = stall + 1
                    if stall >= 6 then
                        stall = 0
                        TaskVehicleTempAction(leader.ped, leader.veh, 3, 1800)
                        Wait(2000)
                        orderAll()
                    end
                else
                    stall = 0
                end
                local c = GetEntityCoords(leader.veh)
                local p = o.route[wp]
                local d = #(vector3(c.x, c.y, 0.0) - vector3(p.x, p.y, 0.0))
                if fight then
                    -- already handled above
                elseif wp < last then
                    if d < (o.wpRadius or 25.0) then
                        wp = wp + 1
                        TriggerServerEvent('bs_events:convoyProgress', o.id, wp, false)
                        orderAll()
                    end
                elseif d < (o.arrive or 25.0) then
                    startFight('arrived')
                elseif IsVehicleStuckOnRoof(leader.veh) or not IsVehicleDriveable(leader.veh, false) then
                    startFight('disabled')
                end
            end
        end
    end)
end)

RegisterNetEvent('bs_events:convoyPos', function(id, x, y)
    local s = Scenes[id]
    if not s or s.kind ~= 'convoy' then return end
    for _, b in ipairs(s.blips) do SetBlipCoords(b, x + 0.0, y + 0.0, 0.0) end
end)

RegisterNetEvent('bs_events:ended', function(id) Convoys[id] = nil; Arming[id] = nil end)


-- Build / tear down

local function destroy(id)
    local s = Scenes[id]
    if not s then return end
    Scenes[id] = nil
    for _, c in pairs(s.crates) do
        if not c.net then remove(c.ent) end
        dropTarget(c)
        if c.falling then remove(c.falling.chute); remove(c.falling.ent) end
        for _, h in ipairs(c.fx or {}) do RemoveParticleFx(h, false) end
        if c.sound then StopSound(c.sound); ReleaseSoundId(c.sound) end
        if c.blip then RemoveBlip(c.blip) end
    end
    remove(s.plane)
    for _, b in ipairs(s.blips) do RemoveBlip(b) end
end

local function build(ev)
    destroy(ev.id)
    local s = { id = ev.id, kind = ev.kind, label = ev.label, visual = ev.visual,
                t0 = GetGameTimer() - (ev.ago or 0), crates = {}, blips = {} }
    Scenes[ev.id] = s

    if ev.area then
        local b = Events.Blips[ev.kind] or {}
        local r = AddBlipForRadius(ev.area.x, ev.area.y, 0.0, ev.area.radius)
        SetBlipColour(r, b.colour or 1)
        SetBlipAlpha(r, 90)
        s.blips[#s.blips + 1] = r
        local icon = AddBlipForCoord(ev.area.x, ev.area.y, 0.0)
        SetBlipSprite(icon, b.sprite or 1)
        SetBlipColour(icon, b.colour or 1)
        SetBlipScale(icon, 1.0)
        SetBlipAsShortRange(icon, false)
        blipName(icon, ('%s - %s'):format(ev.kind:upper(), loc(ev.label) or ''))
        s.blips[#s.blips + 1] = icon
    end
    if ev.kind == 'horde' and ev.visual then
        local t = AddBlipForCoord(ev.visual.tx, ev.visual.ty, 0.0)
        SetBlipSprite(t, 305)
        SetBlipColour(t, 1)
        SetBlipScale(t, 0.7)
        blipName(t, L('ev.horde_here'))
        s.blips[#s.blips + 1] = t
    end

    for _, c in ipairs(ev.crates or {}) do
        c.label = L('ev.crate_' .. (ev.kind == 'stash' and 'stash' or ev.kind == 'convoy' and 'convoy' or 'airdrop'))
        s.crates[c.id] = c
        if ev.kind == 'airdrop' and c.landAgo and c.landAgo < 0 then
            c.landLocal = GetGameTimer() - c.landAgo
            local v = ev.visual
            -- the crate leaves the plane fallMs before landing
            CreateThread(function()
                while Scenes[s.id] == s and GetGameTimer() < c.landLocal - v.fallMs do Wait(250) end
                if Scenes[s.id] == s then dropCrate(s, c) end
            end)
        else
            if c.net then
                if c.dropped then crateBlip(s, c) end
            elseif not c.wait then CreateThread(function() placeCrate(s, c) end) end
        end
    end
    if ev.kind == 'airdrop' and ev.visual then flyPlane(s) end
end

RegisterNetEvent('bs_events:state', function(list)
    local seen = {}
    for _, ev in ipairs(list or {}) do
        seen[ev.id] = true
        if not Scenes[ev.id] then build(ev) end
    end
    for id in pairs(Scenes) do if not seen[id] then destroy(id) end end
end)

RegisterNetEvent('bs_events:ended', function(id) destroy(id) end)

RegisterNetEvent('bs_events:crate', function(evId, cid, patch)
    local s = Scenes[evId]
    local c = s and s.crates[cid]
    if not c then return end
    if patch.locked ~= nil then c.locked = patch.locked end
    if patch.guarded ~= nil then c.guarded = patch.guarded end
    if patch.net then c.net = patch.net; c.ent = nil end
    if patch.x then
        c.x, c.y, c.z = patch.x, patch.y, patch.z
        c.gz = patch.z
        if patch.dropped then c.dropped = true; crateBlip(s, c) end
    end
    if patch.wait == false and c.wait then
        c.wait = false
        CreateThread(function() placeCrate(s, c) end)
    end
    if patch.gone then
        c.gone = true
        dropTarget(c)
        if not c.net then remove(c.ent) end
        c.ent = nil
        for _, h in ipairs(c.fx or {}) do RemoveParticleFx(h, false) end
        c.fx = {}
        if c.sound then StopSound(c.sound); ReleaseSoundId(c.sound); c.sound = nil end
        if c.blip then RemoveBlip(c.blip); c.blip = nil end
    end
end)

-- Radio popup + sound cue

RegisterNetEvent('bs_events:radio', function(msg)
    PlaySoundFrontend(-1, 'Start_Squelch', 'CB_RADIO_SFX', true)
    local cue = SOUNDS[msg.kind]
    if cue then PlaySoundFrontend(-1, cue[1], cue[2], true) end
    SendNUIMessage({ action = 'radio', kind = msg.kind, title = msg.title, body = msg.body,
                     grid = msg.grid, seconds = msg.seconds })
    SetTimeout(((msg.seconds or 16) * 1000), function()
        PlaySoundFrontend(-1, 'End_Squelch', 'CB_RADIO_SFX', true)
    end)
end)

-- Crate interaction

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function openCrate(evId, cid, ent)
    busy = true
    local res = BSB.Await('events:begin', 8000, evId, cid)
    if not res or not res.ok then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = (res and res.error) or L('ev.nothing_happens') })
        busy = false
        return
    end
    local ok = false
    local done, result = pcall(function() return exports.bs_interactions:RunSearch(res.label, res.duration, { pose = 'kneel', entity = ent }) end)
    ok = done and result == true
    if ok then
        local fin = BSB.Await('events:finish', 8000)
        if fin and not fin.ok and fin.error then TriggerEvent('bs:ui:notify', { type = 'warn', message = fin.error }) end
    else
        TriggerServerEvent('bs_events:cancel')
    end
    busy = false
end

-- Cargo trucks and escort bodies are offered through the target system (bs_interactions).
local function targetOptions(evId, cid, c)
    local args = { ev = evId, cid = cid }
    if c.kind == 'truck' then
        return { { label = L('ev.loot_crates'), labelKey = 'ev.loot_crates', icon = 'hand', distance = 3.5,
                   event = 'bs:events:dot:loot', args = args, filters = { stateTrue = 'bsCargoOpen', onFoot = true } } }
    end
    return { { label = L('ev.search_body'), labelKey = 'ev.search_body', icon = 'hand', distance = 2.0,
               event = 'bs:events:dot:loot', args = args, filters = { stateFalse = 'bsBodyLooted', onFoot = true } } }
end

dropTarget = function(c)
    if c.reg then
        local e = c.reg
        c.reg = nil
        pcall(function() exports.bs_interactions:RemoveEntity(e) end)
    end
end

local function syncTarget(evId, cid, c)
    if c.gone then return dropTarget(c) end
    if not c.ent or not DoesEntityExist(c.ent) then
        c.ent = nil
        if c.net and NetworkDoesEntityExistWithNetworkId(c.net) then
            local e = NetworkGetEntityFromNetworkId(c.net)
            if e ~= 0 and DoesEntityExist(e) then c.ent = e end
        end
    end
    if c.ent and c.reg ~= c.ent then
        dropTarget(c)
        local ok = pcall(function() return exports.bs_interactions:AddEntity(c.ent, targetOptions(evId, cid, c)) end)
        if ok then c.reg = c.ent end
    end
end

AddEventHandler('bs:events:dot:loot', function(payload)
    local a = payload and payload.args
    if not a or busy then return end
    CreateThread(function() openCrate(a.ev, a.cid, payload.entity) end)
end)

RegisterNetEvent('bs_events:body', function(evId, entry)
    local s = Scenes[evId]
    if s and entry and entry.id then s.crates[entry.id] = entry end
end)

CreateThread(function()
    while true do
        local sleep = 800
        for evId, s in pairs(Scenes) do
            for cid, c in pairs(s.crates) do
                if c.kind then syncTarget(evId, cid, c) end
            end
        end
        if not busy then
            local at = GetEntityCoords(PlayerPedId())
            for evId, s in pairs(Scenes) do
                for cid, c in pairs(s.crates) do
                    if c.kind then
                        -- truck / body: handled by the target system
                    elseif c.net and not c.gone then
                        if not (c.ent and DoesEntityExist(c.ent)) then
                            c.ent = nil
                            if NetworkDoesEntityExistWithNetworkId(c.net) then
                                local e = NetworkGetEntityFromNetworkId(c.net)
                                if e ~= 0 and DoesEntityExist(e) then c.ent = e end
                            end
                        end
                        if c.ent then
                            local p = GetEntityCoords(c.ent)
                            c.x, c.y, c.z = p.x, p.y, p.z
                        end
                    end
                    if not c.kind and c.ent and not c.gone and not IsPedInAnyVehicle(PlayerPedId(), false) then
                        local dx, dy = at.x - c.x, at.y - c.y
                        local d = math.sqrt(dx * dx + dy * dy)
                        if d < 25.0 then sleep = 0 end
                        if d < 2.2 then
                            help(c.guarded and L('ev.guarded_help') or c.locked and L('ev.force_help') or L('ev.open_help', { name = loc(c.label) or L('ev.crate') }))
                            if IsControlJustReleased(0, 38) then
                                CreateThread(function() openCrate(evId, cid) end)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Startup

CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(1000) end
    TriggerServerEvent('bs_events:hello')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Scenes) do destroy(id) end
end)
