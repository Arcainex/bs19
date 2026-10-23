-- bs_events - the four world events. Each registers start / think / stop in EV.Kinds.

local function now() return GetGameTimer() end

local function pick(list) return list[math.random(#list)] end

local function zombiesUp() return GetResourceState('bs_zombies') == 'started' end

local function fuzz(x, y, r)
    local a, d = math.random() * math.pi * 2, math.random() * r
    return x + math.cos(a) * d, y + math.sin(a) * d
end

-- 1. Airdrop

EV.Kinds.airdrop = {
    usesCrates = true,
    atOk = true,
    start = function(ev, opts)
        local cfg = Events.Airdrop
        if not cfg.enabled then return false, 'disabled' end
        local area, p
        if opts and opts.at then
            area, p = { label = 'loc:ev.admin_pos' }, vector3(opts.at.x, opts.at.y, opts.at.z)
        end
        for _ = 1, p and 0 or 12 do
            area = pick(cfg.areas)
            p = pick(area.points)
            if not EV.InSafeZone(p.x, p.y) then break end
            p = nil
        end
        if not p then return false, 'no drop point outside safe zones' end

        local heading = math.random() * 360.0
        local run = 2500.0
        local flyMs = math.floor(run / cfg.planeSpeed * 1000)
        local fallMs = math.floor(cfg.flightHeight / cfg.fallSpeed * 1000)
        local landAt = ev.t0 + flyMs + fallMs

        ev.label = area.label
        ev.crates[1] = {
            x = p.x, y = p.y, z = p.z, h = heading, model = cfg.crateModel,
            landAt = landAt, openSeconds = cfg.openSeconds, openLabel = 'ev.opening_airdrop',
            label = 'loc:ev.crate_airdrop',
        }
        ev.crates[1].container = EV.MakeContainer(ev.id, 1, 'loc:inv.cont.airdrop', EV.RollLoot(Events.Loot.airdrop))
        ev.cratesReady = true
        ev.endsAt = landAt + cfg.timeoutMinutes * 60000
        local bx, by = fuzz(p.x, p.y, cfg.blipFuzz or 150.0)
        ev.area = { x = bx, y = by, radius = (cfg.blipFuzz or 150.0) + 60.0 }
        ev.visual = {
            plane = cfg.planeModel, chute = cfg.chuteModel,
            x = p.x, y = p.y, z = p.z, heading = heading, height = cfg.flightHeight,
            speed = cfg.planeSpeed, run = run, flyMs = flyMs, fallMs = fallMs,
        }
        EV.Announce('airdrop', 'ev.airdrop_t', 'ev.airdrop_b', { place = area.label },
            { x = bx, y = by })
        return true
    end,
    think = function(ev)
        local c = ev.crates[1]
        if not c or c.gone or now() < c.landAt then return end
        if not ev.landed then
            ev.landed = true
            EV.Announce('airdrop', 'ev.landed_t', 'ev.landed_b', { place = ev.label }, c)
        end
        if not ev.noiseAt or now() >= ev.noiseAt then
            ev.noiseAt = now() + 60000
            EV.Noise(c.x, c.y, c.z, Events.Airdrop.noiseLoudness)
        end
    end,
}

-- 2. Supply broadcast (hidden stash)

local function spotBusy(spot)
    for _, ev in pairs(EV.Active) do
        if ev.kind == 'stash' and ev.spot == spot then return true end
    end
    return false
end

EV.Kinds.stash = {
    usesCrates = true,
    atOk = true,
    start = function(ev, opts)
        local cfg = Events.Stash
        if not cfg.enabled then return false, 'disabled' end
        local spot
        if opts and opts.at then
            spot = { label = 'loc:ev.admin_pos', coords = vector3(opts.at.x, opts.at.y, opts.at.z) }
        end
        for _ = 1, spot and 0 or 10 do
            spot = pick(cfg.spots)
            if not spotBusy(spot) then break end
            spot = nil
        end
        if not spot then return false, 'every stash spot is in use' end
        local c = spot.coords
        ev.spot, ev.label = spot, spot.label
        ev.crates[1] = { x = c.x, y = c.y, z = c.z, h = math.random() * 360.0, model = cfg.model,
                         openSeconds = cfg.openSeconds, openLabel = 'ev.digging_stash', label = 'loc:ev.crate_stash' }
        ev.crates[1].container = EV.MakeContainer(ev.id, 1, 'loc:inv.cont.stash', EV.RollLoot(Events.Loot.stash))
        ev.cratesReady = true
        ev.endsAt = ev.t0 + cfg.timeoutMinutes * 60000
        ev.area = { x = c.x, y = c.y, radius = 40.0 }
        EV.Announce('stash', 'ev.stash_t', 'ev.stash_b', { place = spot.label }, c)
        return true
    end,
}

-- 3. Military convoy.

local function buildRoute(site, opts)
    local s = site.coords
    local pts = { vector3(s.x, s.y, s.z) }
    for _, p in ipairs(site.route or {}) do pts[#pts + 1] = vector3(p.x, p.y, p.z) end
    if #pts == 1 then
        local rad = math.rad(s.w)
        local d = Events.Convoy.routeFallback or 600.0
        pts[2] = vector3(s.x - math.sin(rad) * d, s.y + math.cos(rad) * d, s.z)
    end
    return pts
end

local function routeLen(pts)
    local n = 0.0
    for i = 2, #pts do n = n + EV.Dist2D(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y) end
    return n
end

local function nearestPlayer(x, y)
    local best, bd
    for _, p in ipairs(EV.Players()) do
        local d = EV.Dist2D(x, y, p.x, p.y)
        if not bd or d < bd then best, bd = p.src, d end
    end
    return best
end

local function clog(msg, ...) print(('^3[convoy]^7 ' .. msg):format(...)) end
EV.ConvoyLog = clog

local function waitEnt(e, ms)
    local t = GetGameTimer() + ms
    while (not e or e == 0 or not DoesEntityExist(e)) and GetGameTimer() < t do Wait(50) end
    return e and e ~= 0 and DoesEntityExist(e)
end

local function protect(ent, evId)
    pcall(SetEntityOrphanMode, ent, 2)
    local st = Entity(ent).state
    st:set('bsProtected', true, true)
    st:set('bsConvoy', evId, true)
end

-- create a ped in a seat; retries because the ped can fail right after the vehicle spawns
local function makePed(veh, model, seat, tries)
    for try = 1, tries or 4 do
        local ped = CreatePedInsideVehicle(veh, 4, joaat(model), seat, true, true)
        waitEnt(ped, 3000)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            Wait(100)
            local seated = GetPedInVehicleSeat(veh, seat) == ped
            clog('ped seat %d try %d ped=%s net=%s seated=%s', seat, try, tostring(ped), tostring(NetworkGetNetworkIdFromEntity(ped)), tostring(seated))
            if seated or seat == -1 then return ped end
            DeleteEntity(ped)
            return nil
        end
        clog('ped seat %d try %d failed (veh=%s exists=%s)', seat, try, tostring(veh), tostring(DoesEntityExist(veh)))
        if not DoesEntityExist(veh) then return nil end
        Wait(250)
    end
    return nil
end

local function pedDead(p) return not p or not DoesEntityExist(p) or GetEntityHealth(p) < 100 end
local function vehDead(v)
    return not v or not DoesEntityExist(v) or GetEntityHealth(v) <= 0 or GetVehicleEngineHealth(v) <= 0
end

-- true while a living escort NPC is within guardRadius of the truck
local function guarded(cv, k)
    local tp = cv.tpos[k]
    if not tp then return false end
    local r = Events.Convoy.escort.guardRadius or 40.0
    for _, p in ipairs(cv.peds) do
        if not pedDead(p) then
            local c = GetEntityCoords(p)
            if EV.Dist2D(c.x, c.y, tp.x, tp.y) <= r then return true end
        end
    end
    return false
end

local function driveOrder(ev, owner, resume)
    local cv = ev.cv
    local ids = {}
    clog('#%d drive order to owner %s resume=%s units=%d', ev.id, tostring(owner), tostring(resume), #cv.veh)
    for i, v in ipairs(cv.veh) do
        local gun = {}
        for _, g in ipairs(cv.gun[i] or {}) do
            if DoesEntityExist(g) then gun[#gun + 1] = NetworkGetNetworkIdFromEntity(g) end
        end
        ids[i] = { veh = NetworkGetNetworkIdFromEntity(v), ped = NetworkGetNetworkIdFromEntity(cv.ped[i]),
                   x = cv.spawn[i].x, y = cv.spawn[i].y, z = cv.spawn[i].z, h = cv.spawn[i].h,
                   kind = cv.kind[i], model = cv.model[i], gunners = gun }
    end
    local route = {}
    for i, p in ipairs(cv.route) do route[i] = { x = p.x, y = p.y, z = p.z } end
    TriggerClientEvent('bs_events:convoyDrive', owner, {
        id = ev.id, units = ids, route = route, wp = cv.wp or 1, resume = resume or false,
        speed = Events.Convoy.speed, style = Events.Convoy.driveStyle, gap = Events.Convoy.gap,
        arrive = Events.Convoy.arriveRadius, wpRadius = Events.Convoy.waypointRadius or 25.0, fight = cv.arrived or false,
    })
end

local function arrive(ev)
    local cv = ev.cv
    if cv.arrived then return end
    cv.arrived = true
    cv.pedOwner = {}            -- owners get the fight order again
    EV.Log('convoy #%d stopped', ev.id)
end

RegisterNetEvent('bs_events:convoyReady', function(evId)
    local ev = EV.Active[tonumber(evId)]
    if not ev or not ev.cv or ev.cv.owner ~= source then return end
    ev.cv.ready = true
    EV.ConvoyLog('#%d client %s ready', ev.id, tostring(source))
end)

RegisterNetEvent('bs_events:convoyLog', function(evId, msg)
    local ev = EV.Active[tonumber(evId)]
    if not ev or not ev.cv then return end
    EV.ConvoyLog('#%d client %s: %s', ev.id, tostring(source), tostring(msg):sub(1, 160))
end)

RegisterNetEvent('bs_events:convoyProgress', function(evId, wp, done)
    local ev = EV.Active[tonumber(evId)]
    if not ev or not ev.cv or ev.cv.owner ~= source then return end
    ev.cv.wp = math.max(ev.cv.wp or 1, tonumber(wp) or 1)
    if done then arrive(ev) end
end)

-- remember who last hit a convoy driver, for the lead-driver bonus
AddEventHandler('weaponDamageEvent', function(sender, data)
    pcall(function()
        local ent = NetworkGetEntityFromNetworkId(data.hitGlobalId)
        if not ent or ent == 0 then return end
        for _, ev in pairs(EV.Active) do
            if ev.cv and ev.cv.ped[1] == ent then ev.cv.lastHit = sender end
        end
    end)
end)

local function leadReward(ev)
    local cv = ev.cv
    local cfg = Events.Convoy.leadKill
    if not cfg or not cfg.enabled then return end
    local killer = cv.lastHit
    if not killer or not GetPlayerName(killer) then
        local ok, s = pcall(GetPedSourceOfDeath, cv.ped[1])
        if ok and s and s ~= 0 then
            if IsPedAPlayer(s) then killer = NetworkGetEntityOwner(s)
            elseif IsPedInAnyVehicle(s, false) then
                local d = GetPedInVehicleSeat(GetVehiclePedIsIn(s, false), -1)
                if d and d ~= 0 and IsPedAPlayer(d) then killer = NetworkGetEntityOwner(d) end
            end
        end
    end
    if not killer or not GetPlayerName(killer) then return end
    local rep, xp = cfg.rep or 0, cfg.xp or 0
    if GetResourceState('bs_factions') ~= 'started' then return end
    local fid
    pcall(function() fid = exports.bs_factions:GetFaction(killer) end)
    if not fid then return end
    if rep > 0 then pcall(function() exports.bs_factions:AddReputation(killer, rep, 'convoy_lead') end) end
    if xp > 0 then pcall(function() exports.bs_factions:AddFactionXP(fid, xp, 'convoy_lead') end) end
    TriggerClientEvent('bs:ui:notify', killer, { type = 'success', message = Lp(killer, 'ev.lead_reward', { rep = rep, xp = xp }) })
    clog('#%d lead driver killed by %s (+%d rep, +%d xp)', ev.id, tostring(killer), rep, xp)
end

-- A dead escort leaves a lootable body: its own server container plus a little cash.
local function trackBodies(ev, cv)
    cv.bodies = cv.bodies or {}
    local cfg = Events.Loot.convoy_npc
    if not cfg then return end
    for _, p in ipairs(cv.peds) do
        -- bsArmed is set by the client once the escort was armed, so a ped that never spawned is not a body
        if not cv.bodies[p] and DoesEntityExist(p) and GetEntityHealth(p) < 100 and Entity(p).state.bsArmed then
            cv.bodies[p] = true
            cv.bodyN = (cv.bodyN or 0) + 1
            local cid = 100 + cv.bodyN
            local pc = GetEntityCoords(p)
            local cash = 0
            local cc = cfg.cash
            if cc and math.random() <= (cc.chance or 1.0) then cash = math.random(cc.min or 1, cc.max or cc.min or 1) end
            local c = { x = pc.x, y = pc.y, z = pc.z, h = 0.0, kind = 'body', body = true, ped = p,
                        net = NetworkGetNetworkIdFromEntity(p), cash = cash,
                        openSeconds = 3, openLabel = 'ev.opening_body', labelKey = 'ev.body' }
            c.container = EV.MakeContainer(ev.id, cid, 'loc:inv.cont.escort', EV.RollLoot(cfg))
            ev.crates[cid] = c
            TriggerClientEvent('bs_events:body', -1, ev.id, { id = cid, net = c.net, kind = 'body', x = pc.x, y = pc.y, z = pc.z })
            clog('#%d escort body %d (cash %d)', ev.id, cid, cash)
        end
    end
end

EV.Kinds.convoy = {
    usesCrates = true,
    atOk = true,
    start = function(ev, opts)
        local cfg = Events.Convoy
        local esc = cfg.escort
        if not cfg.enabled then return false, 'disabled' end
        local site, route
        if opts and opts.at then
            site = { label = 'loc:ev.admin_pos', coords = vector4(opts.at.x, opts.at.y, opts.at.z, opts.at.h or 0.0) }
        else
            -- fixed routes (config + recorded): random enabled one, spawn at its first point
            local list = EV.EnabledRoutes and EV.EnabledRoutes() or {}
            local pool = {}
            for _, r in ipairs(list) do
                if not EV.InSafeZone(r.points[1].x, r.points[1].y) then pool[#pool + 1] = r end
            end
            if #pool > 0 then
                local r = pick(pool)
                local p1 = r.points[1]
                site = { label = r.name, coords = vector4(p1.x, p1.y, p1.z, 0.0) }
                route = {}
                for i, p in ipairs(r.points) do route[i] = vector3(p.x, p.y, p.z) end
            elseif cfg.sites and #cfg.sites > 0 then
                site = pick(cfg.sites)
            else
                return false, 'no convoy routes or sites configured'
            end
        end
        local s = site.coords
        route = route or buildRoute(site)
        local owner = nearestPlayer(s.x, s.y)
        if not owner then return false, 'no players online to drive the convoy' end

        -- direction of the first leg, for the spawn line
        local dx, dy = route[2].x - s.x, route[2].y - s.y
        local dl = math.max(1.0, math.sqrt(dx * dx + dy * dy))
        local fx, fy = dx / dl, dy / dl
        local heading = math.deg(math.atan(-fx, fy)) % 360.0

        ev.label = site.label
        local cv = { veh = {}, ped = {}, spawn = {}, kind = {}, model = {}, gun = {}, peds = {}, pedUnit = {},
                     tpos = {}, pedOwner = {}, route = route, owner = owner, wp = 1 }
        local drivers = cfg.driverModels or { cfg.driverModel or 's_m_y_marine_01' }

        -- line-up: truck, escort car, truck, escort car ...
        local nT, nE = math.max(1, cfg.truckCount or 2), math.random(esc.vehicleMin or 1, esc.vehicleMax or 2)
        local plan, t, e = {}, 0, 0
        while t < nT or e < nE do
            if t < nT then t = t + 1; plan[#plan + 1] = { kind = 'truck', model = cfg.trucks[((t + ev.id) % #cfg.trucks) + 1] } end
            if e < nE then e = e + 1; plan[#plan + 1] = { kind = 'escort', model = esc.vehicles[((e + ev.id) % #esc.vehicles) + 1] } end
        end

        local function arm(ped)
            protect(ped, ev.id)
            local w = esc.weapons[math.random(#esc.weapons)]
            pcall(GiveWeaponToPed, ped, joaat(w), esc.ammo or 400, false, true)
            cv.peds[#cv.peds + 1] = ped
        end

        for i, u in ipairs(plan) do
            local back = (i - 1) * 13.0
            local sp = { x = s.x - fx * back, y = s.y - fy * back, z = s.z, h = heading }
            local veh = CreateVehicleServerSetter(joaat(u.model), 'automobile', sp.x, sp.y, sp.z + 0.5, heading)
            if waitEnt(veh, 5000) then
                FreezeEntityPosition(veh, true)              -- held until the client finds ground
                protect(veh, ev.id)
                clog('#%d %s %d model=%s ent=%s net=%s', ev.id, u.kind, i, u.model, tostring(veh), tostring(NetworkGetNetworkIdFromEntity(veh)))
                local ped = makePed(veh, drivers[((i - 1) % #drivers) + 1], -1, 4)
                if ped then
                    arm(ped)
                    cv.veh[#cv.veh + 1], cv.ped[#cv.ped + 1], cv.spawn[#cv.spawn + 1] = veh, ped, sp
                    local k = #cv.veh
                    cv.kind[k], cv.model[k], cv.gun[k] = u.kind, u.model, {}
                    cv.pedUnit[ped] = k
                    local seats = u.kind == 'truck' and (esc.gunnersPerTruck or 1) or (esc.gunnersPerVehicle or 3)
                    for seat = 0, seats - 1 do
                        local g = makePed(veh, drivers[((i + seat) % #drivers) + 1], seat, 1)
                        if g then arm(g); cv.gun[k][#cv.gun[k] + 1] = g; cv.pedUnit[g] = k end
                    end
                    cv.tpos[k] = { x = sp.x, y = sp.y, z = sp.z, h = heading }
                else
                    clog('#%d veh %d: no driver after retries, removing vehicle', ev.id, i)
                    DeleteEntity(veh)
                end
            else
                clog('#%d veh %d (%s) never appeared on server', ev.id, i, u.model)
            end
        end

        -- the loot lives in the cargo trucks: one server container per truck
        local ncr = 0
        for k = 1, #cv.veh do
            if cv.kind[k] == 'truck' then
                ncr = ncr + 1
                local sp = cv.spawn[k]
                ev.crates[ncr] = { x = sp.x, y = sp.y, z = sp.z, h = 0.0, model = cv.model[k], kind = 'truck',
                                   truck = k, net = NetworkGetNetworkIdFromEntity(cv.veh[k]),
                                   guarded = true, locked = cfg.requireTool ~= false,
                                   reach = (cfg.cargo and cfg.cargo.reach) or 7.0,
                                   openSeconds = 3, openLabel = 'ev.opening_crate', labelKey = 'ev.cargo' }
                ev.crates[ncr].container = EV.MakeContainer(ev.id, ncr, 'loc:inv.cont.cargo', EV.RollLoot(Events.Loot.convoy))
            end
        end
        if #cv.veh == 0 or ncr == 0 then
            for _, p in ipairs(cv.peds) do if DoesEntityExist(p) then DeleteEntity(p) end end
            for _, v in ipairs(cv.veh) do if DoesEntityExist(v) then DeleteEntity(v) end end
            for _, c in pairs(ev.crates) do
                if c.container then pcall(function() exports.bs_inventory:ContainerTakeAll(c.container) end) end
            end
            ev.crates = {}
            return false, 'could not create convoy vehicles or cargo trucks'
        end
        ev.cv = cv

        local last = route[#route]
        ev.cratesReady = true
        ev.endsAt = ev.t0 + cfg.timeoutMinutes * 60000
        cv.arriveBy = ev.t0 + math.floor(routeLen(route) / math.max(4.0, cfg.speed * 0.5) * 1000 * 1.5) + 30000
        ev.area = { x = last.x, y = last.y, radius = 120.0 }
        ev.visual = {}

        if zombiesUp() then
            for i = 1, cfg.guards do
                local a, d = math.random() * math.pi * 2, 18.0 + math.random() * 25.0
                local armoured = i % 2 == 1
                pcall(function()
                    exports.bs_zombies:EventSpawn(last.x + math.cos(a) * d, last.y + math.sin(a) * d,
                        armoured and cfg.guardType or 'walker',
                        { tag = ev.tag, hpScale = armoured and cfg.guardHpScale or 1.5 })
                end)
            end
        end
        cv.ackBy = now() + 8000
        cv.tries = 0
        driveOrder(ev, owner, false)
        if cfg.announce ~= false then
            EV.Announce('convoy', 'ev.convoy_t', 'ev.convoy_b', { place = site.label }, last)
        end
        return true
    end,
    think = function(ev)
        local cv = ev.cv
        if not cv then return end
        local lead
        for _, v in ipairs(cv.veh) do if DoesEntityExist(v) then lead = v; break end end

        -- track the trucks, escorts and the lead driver
        for k, v in ipairs(cv.veh) do
            if DoesEntityExist(v) then
                local c = GetEntityCoords(v)
                cv.tpos[k] = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(v) }
            end
        end
        if not cv.leadPaid and cv.ped[1] and DoesEntityExist(cv.ped[1]) and GetEntityHealth(cv.ped[1]) < 100 then
            cv.leadPaid = true
            pcall(leadReward, ev)
        end

        if lead and not cv.arrived then
            if now() >= cv.arriveBy then arrive(ev) end
        end

        trackBodies(ev, cv)
        for cid, c in pairs(ev.crates) do
            local v = c.truck and cv.veh[c.truck]
            if c.truck and not c.gone then
                if v and DoesEntityExist(v) then
                    local pc = GetEntityCoords(v)
                    c.x, c.y, c.z = pc.x, pc.y, pc.z
                end
                if vehDead(v) then
                    -- truck destroyed: the cargo is lost
                    c.gone = true
                    if c.container then pcall(function() exports.bs_inventory:ContainerTakeAll(c.container) end) end
                    EV.CratePatch(ev, cid, { gone = true })
                    clog('#%d cargo truck %d destroyed, loot lost', ev.id, c.truck)
                else
                    local g = guarded(cv, c.truck)
                    local stopped = cv.arrived or pedDead(cv.ped[c.truck])
                    c.stopped = stopped
                    local open = (not g) and stopped
                    if g ~= c.guarded then
                        c.guarded = g
                        EV.CratePatch(ev, cid, { guarded = g })
                    end
                    if open ~= c.openState and DoesEntityExist(v) then
                        c.openState = open
                        Entity(v).state:set('bsCargoOpen', open, true)
                    end
                end
            end
        end

        -- whoever owns an escort ped now gets the arming (and fight) order
        local batch = {}
        for _, p in ipairs(cv.peds) do
            if DoesEntityExist(p) and GetEntityHealth(p) >= 100 then
                local o = NetworkGetEntityOwner(p)
                if o and o > 0 and cv.pedOwner[p] ~= o then
                    cv.pedOwner[p] = o
                    local v = cv.veh[cv.pedUnit[p]]
                    batch[o] = batch[o] or {}
                    batch[o][#batch[o] + 1] = { ped = NetworkGetNetworkIdFromEntity(p),
                        veh = (v and DoesEntityExist(v)) and NetworkGetNetworkIdFromEntity(v) or nil,
                        drv = cv.ped[cv.pedUnit[p]] == p, kind = cv.kind[cv.pedUnit[p]] }
                end
            end
        end
        for o, list in pairs(batch) do
            TriggerClientEvent('bs_events:convoyArm', o, { id = ev.id, peds = list, fight = cv.arrived or false })
        end

        if not lead then return end
        -- no ready ack from the client yet: send the order again (owner may not exist yet)
        if not cv.arrived and not cv.ready and now() >= (cv.ackBy or 0) and (cv.tries or 0) < 8 then
            cv.tries = (cv.tries or 0) + 1
            cv.ackBy = now() + 8000
            local o2 = NetworkGetEntityOwner(lead)
            if o2 and o2 > 0 then cv.owner = o2 end
            driveOrder(ev, cv.owner, false)
        end
        -- ownership migration: re-task whoever owns the lead vehicle now
        local o = NetworkGetEntityOwner(lead)
        if o and o > 0 and o ~= cv.owner then
            cv.owner = o
            driveOrder(ev, o, cv.ready and true or false)
        elseif not o or o <= 0 or not GetPlayerName(cv.owner) then
            local lc = GetEntityCoords(lead)
            local p = nearestPlayer(lc.x, lc.y)
            if p and p ~= cv.owner then cv.owner = p; driveOrder(ev, p, true) end
        end
    end,
    stop = function(ev)
        if ev.cv then
            clog('#%d stop: deleting %d veh / %d ped (arrived=%s)', ev.id, #ev.cv.veh, #ev.cv.peds, tostring(ev.cv.arrived))
            for _, e in ipairs(ev.cv.peds) do if DoesEntityExist(e) then DeleteEntity(e) end end
            for _, e in ipairs(ev.cv.veh) do if DoesEntityExist(e) then DeleteEntity(e) end end
        end
        for _, c in pairs(ev.crates) do
            if c.obj and DoesEntityExist(c.obj) then DeleteEntity(c.obj) end
        end
        if zombiesUp() then pcall(function() exports.bs_zombies:EventClear(ev.tag, true) end) end
    end,
}

-- convoy blip follows the lead truck (every 2 s)
CreateThread(function()
    while true do
        Wait(2000)
        for id, ev in pairs(EV.Active) do
            local cv = ev.kind == 'convoy' and ev.cv
            if cv then
                for _, v in ipairs(cv.veh) do
                    if DoesEntityExist(v) then
                        local c = GetEntityCoords(v)
                        if ev.area then ev.area.x, ev.area.y = c.x, c.y end
                        TriggerClientEvent('bs_events:convoyPos', -1, id, c.x, c.y)
                        break
                    end
                end
            end
        end
    end
end)

-- 4. Horde waves toward a safe zone's outskirts

EV.Kinds.horde = {
    usesCrates = false,
    start = function(ev)
        local cfg = Events.Horde
        if not cfg.enabled then return false, 'disabled' end
        if not zombiesUp() then return false, 'bs_zombies is not running' end
        local region = pick(cfg.regions)
        local zone
        for _, z in ipairs(EV.SafeZones()) do if z.id == region.target then zone = z end end
        if not zone then return false, 'safe zone ' .. tostring(region.target) .. ' not found' end

        local dx, dy = region.from.x - zone.x, region.from.y - zone.y
        local len = math.max(1.0, math.sqrt(dx * dx + dy * dy))
        local edge = (zone.padded or zone.radius) + (cfg.outskirts or 30.0)
        ev.target = { x = zone.x + dx / len * edge, y = zone.y + dy / len * edge, z = region.from.z }
        ev.from = region.from
        ev.label = region.label
        ev.zoneLabel = zone.label
        ev.wavesLeft = cfg.waves
        ev.nextWave = now()
        ev.endsAt = ev.t0 + cfg.durationMinutes * 60000
        ev.area = { x = region.from.x, y = region.from.y, radius = 220.0 }
        ev.visual = { tx = ev.target.x, ty = ev.target.y }
        EV.Announce('horde', 'ev.horde_t', 'ev.horde_b', { from = region.label, to = zone.label }, region.from)
        return true
    end,
    think = function(ev)
        local cfg = Events.Horde
        if ev.wavesLeft > 0 and now() >= ev.nextWave then
            ev.wavesLeft = ev.wavesLeft - 1
            ev.nextWave = now() + cfg.waveInterval * 1000
            local made = 0
            -- Wave size follows the zombie difficulty (F1 horde multiplier and progression).
            local size = cfg.waveSize
            pcall(function() size = exports.bs_zombies:HordeSizeScale(cfg.waveSize, ev.from.x, ev.from.y) or size end)
            for _ = 1, size do
                local x, y = fuzz(ev.from.x, ev.from.y, cfg.spread)
                local brute = math.random() < (cfg.bruteChance or 0.1)
                local ok, id = pcall(function()
                    return exports.bs_zombies:EventSpawn(x, y, brute and 'brute' or 'walker', { tag = ev.tag })
                end)
                if ok and id then made = made + 1 end
            end
            EV.Log('horde #%d wave: %d walkers (%d waves left)', ev.id, made, ev.wavesLeft)
            ev.driveAt = 0
        end
        if not ev.driveAt or now() >= ev.driveAt then
            ev.driveAt = now() + 15000
            pcall(function() exports.bs_zombies:EventDrive(ev.tag, ev.target.x, ev.target.y, ev.target.z, 600) end)
        end
    end,
    stop = function(ev)
        -- not cleared: they stay in the world as ordinary walkers
        if zombiesUp() then pcall(function() exports.bs_zombies:EventClear(ev.tag, true) end) end
    end,
}
