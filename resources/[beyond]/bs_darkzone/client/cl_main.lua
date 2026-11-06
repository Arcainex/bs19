-- bs_darkzone client: blips, boundary wall, HUD, crates, extraction points, dropped bags, heli and flare, named weapons.

local V = nil              -- last state from the server
local inside = false
local bag, prog = nil, nil
local heli = nil           -- { x, y, z, endsAt, phase }
local walk = nil           -- { x, y, z, endsAt }
local drops = {}
local blips = { area = nil, center = nil, points = {} }
local zones = {}           -- interaction zone ids we own
local props = {}           -- [key] = entity
local reported = {}        -- [gen:id] = true

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg }) end
local function nui(action, data) SendNUIMessage({ action = action, data = data }) end
local function rmBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end
local function blipName(b, text) BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandSetBlipName(b) end

local function zone(id, pos, r, opts)
    if zones[id] then pcall(function() exports.bs_interactions:RemoveZone(id) end); zones[id] = nil end
    if pos and opts and #opts > 0 then
        if pcall(function() exports.bs_interactions:AddZone(id, pos, r, opts) end) then zones[id] = true end
    end
end

local function clearZones(prefix)
    for id in pairs(zones) do if not prefix or id:sub(1, #prefix) == prefix then zone(id, nil) end end
end

local function delProp(key)
    local e = props[key]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    props[key] = nil
end

local function clearProps(prefix)
    for k in pairs(props) do if not prefix or k:sub(1, #prefix) == prefix then delProp(k) end end
end

local function loadModel(m)
    local h = type(m) == 'number' and m or joaat(m)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(h) and h or nil
end

local function spawnProp(key, model, x, y, z)
    if props[key] and DoesEntityExist(props[key]) then return props[key] end
    local h = loadModel(model)
    if not h then return nil end
    local e = CreateObjectNoOffset(h, x, y, z, false, false, false)
    if e and e ~= 0 then
        PlaceObjectOnGroundProperly(e)
        FreezeEntityPosition(e, true)
        props[key] = e
    end
    SetModelAsNoLongerNeeded(h)
    return e
end

--------------------------------------------------------------------------------
-- State and blips
--------------------------------------------------------------------------------

local function anchors() return (V and V.anchors) or {} end

local function drawBlips()
    rmBlip(blips.area); rmBlip(blips.center); blips.area, blips.center = nil, nil
    for _, b in pairs(blips.points) do rmBlip(b) end
    blips.points = {}
    if not V or not V.on or not V.zone then return end
    local z = V.zone
    blips.area = AddBlipForRadius(z.x, z.y, z.z, z.r)
    SetBlipColour(blips.area, 1); SetBlipAlpha(blips.area, 110)
    blips.center = AddBlipForCoord(z.x, z.y, z.z)
    SetBlipSprite(blips.center, 303); SetBlipColour(blips.center, 1); SetBlipScale(blips.center, 0.9)
    blipName(blips.center, L('dz.blip', { zone = z.label }))
    for _, a in ipairs(anchors()) do
        if a.kind ~= 'crate' then
            local b = AddBlipForCoord(a.x or a.sx, a.y or a.sy, a.z or a.sz or z.z)
            SetBlipSprite(b, a.kind == 'heli' and 43 or 38); SetBlipScale(b, 0.7); SetBlipAsShortRange(b, true)
            SetBlipColour(b, a.kind == 'heli' and 5 or 2)
            blipName(b, a.kind == 'heli' and L('dz.blip_heli') or L('dz.blip_walk'))
            blips.points[a.id] = b
        end
    end
end

local function pointZones()
    clearZones('bsdz:a:')
    if not V or not V.on then return end
    for _, a in ipairs(anchors()) do
        if a.x then
            local pos = vector3(a.x, a.y, a.z + 1.0)
            if a.kind == 'heli' then
                zone('bsdz:a:' .. a.id, pos, 3.0, { { label = L('dz.o_heli'), icon = 'hand', event = 'bs:dz:heliCall', args = a.id } })
            elseif a.kind == 'walk' then
                zone('bsdz:a:' .. a.id, pos, 3.0, { { label = L('dz.o_walk'), icon = 'hand', event = 'bs:dz:walkStart', args = a.id } })
            end
        end
    end
end

local function apply(v)
    local oldGen = V and V.gen
    V = v
    drawBlips()
    pointZones()
    if not v or not v.on or v.gen ~= oldGen then clearProps('crate:'); clearZones('bsdz:c:') end
    nui('state', v and v.on and { zone = v.zone and v.zone.label, leftMs = (v.left or 0) * 1000 } or nil)
end

RegisterNetEvent('bs:dz:state', function(v) apply(v) end)

RegisterNetEvent('bs:dz:anchorSet', function(gen, id, x, y, z)
    if not V or V.gen ~= gen then return end
    for _, a in ipairs(V.anchors or {}) do
        if a.id == id then a.x, a.y, a.z = x, y, z end
    end
    drawBlips(); pointZones()
end)

RegisterNetEvent('bs:dz:inside', function(yes, label)
    inside = yes == true
    if inside then
        notify('warn', L('dz.enter', { zone = label }))
        PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
    else
        notify('info', L('dz.exit'))
    end
    nui('inside', inside)
end)

RegisterNetEvent('bs:dz:bag', function(b) bag = b; nui('bag', b) end)
RegisterNetEvent('bs:dz:prog', function(p) prog = p; nui('prog', p) end)
RegisterNetEvent('bs:dz:xp', function(n) nui('xp', n) end)

RegisterNetEvent('bs:dz:drops', function(list)
    drops = {}
    for _, d in ipairs(list or {}) do drops[d.id] = d end
    clearZones('bsdz:d:')
    for k in pairs(props) do
        if k:sub(1, 5) == 'drop:' and not drops[k:sub(6)] then delProp(k) end
    end
end)

--------------------------------------------------------------------------------
-- Seeds: put extraction points and crates on the nearest road, then tell the server.
--------------------------------------------------------------------------------

local function resolve(a)
    local z = a.sz or (V.zone and V.zone.z) or 0.0
    local ok, node = GetClosestVehicleNode(a.sx, a.sy, z, 1, 3.0, 0)
    if not ok or not node or node.x == 0.0 or #(vector2(node.x, node.y) - vector2(a.sx, a.sy)) > 150.0 then
        -- no road close by: the ground under the seed, once its collision is loaded
        local okg, gz = GetGroundZFor_3dCoord(a.sx, a.sy, z + 60.0, false)
        if not okg then return nil end
        return a.sx, a.sy, gz
    end
    local x, y, nz = node.x, node.y, node.z
    if a.kind == 'crate' then
        -- off to the roadside so the crate does not sit on the lane
        local okh, _, heading = GetClosestVehicleNodeWithHeading(a.sx, a.sy, z, 1, 3.0, 0)
        local hd = math.rad((okh and heading or 0.0) + 90.0)
        x, y = x + math.cos(hd) * 4.5, y + math.sin(hd) * 4.5
        local okg, gz = GetGroundZFor_3dCoord(x, y, nz + 4.0, false)
        if okg then nz = gz end
    end
    return x, y, nz
end

CreateThread(function()
    while true do
        Wait(2500)
        if V and V.on then
            local p = GetEntityCoords(PlayerPedId())
            for _, a in ipairs(V.anchors or {}) do
                local key = V.gen .. ':' .. a.id
                if not a.x and not reported[key] and #(p.xy - vector2(a.sx, a.sy)) < 320.0 then
                    local x, y, z = resolve(a)
                    if x then
                        reported[key] = true
                        TriggerServerEvent('bs:dz:anchor', V.gen, a.id, x, y, z)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Nearby props: crates and dropped bags (local only)
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1500)
        local p = GetEntityCoords(PlayerPedId())
        if V and V.on then
            for _, a in ipairs(V.anchors or {}) do
                if a.kind == 'crate' and a.x then
                    local key = 'crate:' .. a.id
                    local near = #(p - vector3(a.x, a.y, a.z)) < 150.0
                    if near and not props[key] then
                        spawnProp(key, DZ.Models.crate, a.x, a.y, a.z)
                        zone('bsdz:c:' .. a.id, vector3(a.x, a.y, a.z + 0.6), 2.0, { { label = L('dz.o_crate'), icon = 'bag', event = 'bs:dz:crate', args = a.id } })
                    elseif not near and props[key] then
                        delProp(key); zone('bsdz:c:' .. a.id, nil)
                    end
                end
            end
        end
        for id, d in pairs(drops) do
            local key = 'drop:' .. id
            local near = #(p - vector3(d.x, d.y, d.z)) < 120.0
            if near and not props[key] then
                spawnProp(key, DZ.Models.drop, d.x, d.y, d.z + 0.3)
                zone('bsdz:d:' .. id, vector3(d.x, d.y, d.z + 0.5), 2.0, { { label = L('dz.o_drop'), icon = 'bag', event = 'bs:dz:drop', args = id } })
            elseif not near and props[key] then
                delProp(key); zone('bsdz:d:' .. id, nil)
            end
        end
    end
end)

local function argOf(p) return type(p) == 'table' and p.args or p end

AddEventHandler('bs:dz:crate', function(p)
    local r = BSB.Await('dz:crateOpen', 6000, argOf(p))
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

AddEventHandler('bs:dz:drop', function(p)
    local r = BSB.Await('dz:dropOpen', 6000, argOf(p))
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

AddEventHandler('bs:dz:heliCall', function(p)
    local r = BSB.Await('dz:heliCall', 6000, argOf(p))
    if r and not r.ok and r.msg then notify('error', r.msg) return end
    if r and r.ok then
        -- the flare goes up from the caller (a real projectile, everyone sees it)
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local fg = joaat('WEAPON_FLAREGUN')
        pcall(function() ShootSingleBulletBetweenCoords(c.x, c.y, c.z + 0.6, c.x + 0.5, c.y + 0.5, c.z + 80.0, 0, true, fg, ped, true, false, 120.0) end)
    end
end)

AddEventHandler('bs:dz:walkStart', function(p)
    local r = BSB.Await('dz:walkStart', 6000, argOf(p))
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

RegisterNetEvent('bs:dz:walk', function(w)
    if w then
        walk = { x = w.x, y = w.y, z = w.z, endsAt = GetGameTimer() + (w.left or 0) * 1000, total = w.left or 1 }
        notify('info', L('dz.walk_started', { s = w.left or 0 }))
    else
        walk = nil
    end
    nui('walk', w and { left = w.left } or nil)
end)

--------------------------------------------------------------------------------
-- Heli and flare (cosmetic, never decides anything)
--------------------------------------------------------------------------------

local heliEnts = {}
local flareFx = nil

local function heliCleanup()
    for _, e in ipairs(heliEnts) do if DoesEntityExist(e) then DeleteEntity(e) end end
    heliEnts = {}
    if flareFx then StopParticleFxLooped(flareFx, false); flareFx = nil end
end

local function startFlare(x, y, z)
    if flareFx then return end
    RequestNamedPtfxAsset('core')
    local t = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < t do Wait(50) end
    if not HasNamedPtfxAssetLoaded('core') then return end
    UseParticleFxAsset('core')
    flareFx = StartParticleFxLoopedAtCoord('exp_grd_flare', x, y, z + 0.1, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
end

local function heliFlyIn(x, y, z, arriveIn)
    if not (V and V.heliVisual) then return end
    CreateThread(function()
        local wait = math.max(0, arriveIn - 35) * 1000
        local token = heli
        Wait(wait)
        if heli ~= token or not heli then return end
        local mh, ph = loadModel(DZ.Models.heli), loadModel(DZ.Models.pilot)
        if not mh or not ph then return end
        local a = math.random() * math.pi * 2
        local sx, sy, sz = x + math.cos(a) * 550.0, y + math.sin(a) * 550.0, z + 120.0
        local veh = CreateVehicle(mh, sx, sy, sz, 0.0, false, false)
        if not veh or veh == 0 then return end
        heliEnts[#heliEnts + 1] = veh
        SetEntityInvincible(veh, true); SetVehicleEngineOn(veh, true, true, false); SetHeliBladesFullSpeed(veh)
        local pilot = CreatePedInsideVehicle(veh, 26, ph, -1, false, false)
        if pilot and pilot ~= 0 then
            heliEnts[#heliEnts + 1] = pilot
            SetBlockingOfNonTemporaryEvents(pilot, true); SetEntityInvincible(pilot, true)
            TaskHeliMission(pilot, veh, 0, 0, x, y, z + 22.0, 4, 25.0, 8.0, -1.0, 25, 18, -1.0, 0)
        end
        SetModelAsNoLongerNeeded(mh); SetModelAsNoLongerNeeded(ph)
        -- hard stop so nothing is left behind
        SetTimeout(240000, function() if heliEnts[1] == veh then heliCleanup() end end)
    end)
end

local function heliLeave()
    local veh, pilot = heliEnts[1], heliEnts[2]
    if veh and DoesEntityExist(veh) and pilot and DoesEntityExist(pilot) then
        local c = GetEntityCoords(veh)
        TaskHeliMission(pilot, veh, 0, 0, c.x + 800.0, c.y + 800.0, c.z + 150.0, 4, 40.0, 10.0, -1.0, 150, 100, -1.0, 0)
    end
    if flareFx then StopParticleFxLooped(flareFx, false); flareFx = nil end
    SetTimeout(25000, heliCleanup)
end

RegisterNetEvent('bs:dz:heli', function(h)
    if not h then return end
    if h.phase == 'called' then
        heliCleanup()
        local d = #(GetEntityCoords(PlayerPedId()) - vector3(h.x, h.y, h.z))
        if d >= 900.0 and not inside then return end
        heli = { x = h.x, y = h.y, z = h.z, endsAt = GetGameTimer() + (h.left or 0) * 1000 }
        if d < 900.0 then
            startFlare(h.x, h.y, h.z)
            heliFlyIn(h.x, h.y, h.z, h.left or 90)
        end
        nui('heli', { left = h.left })
    else
        heli = nil
        nui('heli', nil)
        if h.phase == 'done' then heliLeave() else heliCleanup() end
    end
end)

--------------------------------------------------------------------------------
-- Boundary wall and point markers
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = 500
        if V and V.on and V.zone then
            local z = V.zone
            local p = GetEntityCoords(PlayerPedId())
            local d = #(p.xy - vector2(z.x, z.y))
            if V.boundary and math.abs(d - z.r) < (V.boundaryDistance or 120.0) then
                sleep = 0
                DrawMarker(1, z.x, z.y, p.z - 60.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, z.r * 2.0, z.r * 2.0, 160.0, 200, 30, 30, 45, false, false, 2, false, nil, nil, false)
            end
            for _, a in ipairs(V.anchors or {}) do
                if a.x and a.kind ~= 'crate' and #(p - vector3(a.x, a.y, a.z)) < 60.0 then
                    sleep = 0
                    local r = a.kind == 'heli' and (V.heliRadius or 15.0) or (V.walkRadius or 6.0)
                    local col = a.kind == 'heli' and { 240, 180, 40 } or { 60, 200, 90 }
                    DrawMarker(1, a.x, a.y, a.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r * 2.0, r * 2.0, 0.6, col[1], col[2], col[3], 90, false, false, 2, false, nil, nil, false)
                end
            end
        end
        if walk then
            sleep = 0
            DrawMarker(1, walk.x, walk.y, walk.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (V and V.walkRadius or 6.0) * 2.0, (V and V.walkRadius or 6.0) * 2.0, 0.4, 60, 200, 90, 120, false, false, 2, false, nil, nil, false)
        end
        Wait(sleep)
    end
end)

--------------------------------------------------------------------------------
-- Named weapons: tint and a small damage bonus while held
--------------------------------------------------------------------------------

local variants = {}
for name, cfg in pairs(DZ.Variants or {}) do variants[GetHashKey(name)] = cfg end

CreateThread(function()
    for h, cfg in pairs(variants) do pcall(function() SetWeaponDamageModifier(h, cfg.damage or 1.0) end) end
    local lastTint = 0
    while true do
        Wait(700)
        local ped = PlayerPedId()
        local w = GetSelectedPedWeapon(ped)
        local cfg = variants[w]
        if cfg and cfg.tint and lastTint ~= w then
            SetPedWeaponTintIndex(ped, w, cfg.tint)
            lastTint = w
        elseif not cfg then
            lastTint = 0
        end
    end
end)

--------------------------------------------------------------------------------
-- HUD clock
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)
        if walk then
            local left = math.max(0, math.ceil((walk.endsAt - GetGameTimer()) / 1000))
            nui('walkLeft', { left = left, total = walk.total })
        end
        if heli then nui('heliLeft', math.max(0, math.ceil((heli.endsAt - GetGameTimer()) / 1000))) end
    end
end)

--------------------------------------------------------------------------------
-- Boot and cleanup
--------------------------------------------------------------------------------

local function labels()
    nui('labels', { title = L('dz.hud_title'), moves = L('dz.hud_moves'), bag = L('dz.hud_bag'), rank = L('dz.hud_rank'),
        heli = L('dz.hud_heli'), walk = L('dz.hud_walk'), walkOk = L('dz.hud_walk_ok'), walkBig = L('dz.hud_walk_big'),
        inside = L('dz.hud_inside'), hint = L('dz.hud_hint'), xp = L('dz.hud_xp') })
end

local function boot()
    labels()
    local v = BSB.Await('dz:view', 8000)
    if v then apply(v) end
    local p = BSB.Await('dz:prog', 8000)
    if p then prog = p; nui('prog', p) end
end

CreateThread(function()
    while not BSB or not BSB.Await do Wait(200) end
    Wait(3000)
    boot()
end)

AddEventHandler('bs:hook:player:spawned', function() SetTimeout(2000, boot) end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'bs_interactions' then SetTimeout(2000, function() pointZones() end) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    heliCleanup()
    clearProps()
    for id in pairs(zones) do pcall(function() exports.bs_interactions:RemoveZone(id) end) end
    rmBlip(blips.area); rmBlip(blips.center)
    for _, b in pairs(blips.points) do rmBlip(b) end
end)
