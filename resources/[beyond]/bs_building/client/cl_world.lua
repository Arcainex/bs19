-- bs_building world: streams nearby cells from the server, spawns local props, hooks interactions, draws power

local S = Building.Settings
local P = Building.Pieces

World = { pieces = {}, ents = {}, extra = {}, cells = {}, rubble = {}, wires = {}, myFaction = nil, myChar = nil, raids = false, cfg = {} }
local CELL = 128.0

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 4500 }) end
Building.Notify = notify

-- First model of a tier the game actually has.
local modelCache = {}
function Building.ModelFor(pieceId, tier)
    local key = pieceId .. ':' .. tostring(tier or '')
    if modelCache[key] ~= nil then return modelCache[key] end
    local d = P[pieceId]
    local sp = Building.Spec(d, tier) or d
    local found = false
    for _, m in ipairs((sp and sp.models) or (d and d.models) or {}) do
        local hash = GetHashKey(m)
        if IsModelInCdimage(hash) and IsModelValid(hash) then found = hash break end
    end
    if not found then found = GetHashKey('prop_woodpile_04a') end
    modelCache[key] = found
    return found
end

function Building.LoadModel(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash)
end

-- Model size, cached. Returns min and max corners.
local dimCache = {}
function Building.Dims(hash)
    local c = dimCache[hash]
    if c then return c[1], c[2] end
    if not HasModelLoaded(hash) and not Building.LoadModel(hash) then return vector3(-0.5, -0.5, 0.0), vector3(0.5, 0.5, 1.0) end
    local mn, mx = GetModelDimensions(hash)
    dimCache[hash] = { mn, mx }
    return mn, mx
end

-- Width, depth, height of a piece at a tier from its real model, falling back to the config size
function Building.SizeOf(pieceId, tier, pitch)
    local d = P[pieceId]
    if not d then return 1, 1, 1 end
    local hash = Building.ModelFor(pieceId, tier)
    local mn, mx = Building.Dims(hash)
    local w, dp, h = mx.x - mn.x, mx.y - mn.y, mx.z - mn.z
    if w <= 0.05 or h <= 0.02 then return d.size[1], d.size[2], d.size[3] end
    local sp = Building.Spec(d, tier) or d
    -- door frame posts: the frame is as wide as the config says
    if sp.parts then return d.size[1], d.size[2], h end
    -- laid flat: height becomes depth
    if (pitch or d.pitch or 0) > 45 then return w, h, dp end
    return w, dp, h
end

-- Put a prop so its bounding box bottom-centre sits on the piece origin, whatever its pivot.
function Building.Align(obj, x, y, z, h, pitch)
    SetEntityRotation(obj, pitch or 0.0, 0.0, h or 0.0, 2, true)
    SetEntityCoordsNoOffset(obj, x, y, z, false, false, false)
    local mn, mx = Building.Dims(GetEntityModel(obj))
    local c = GetOffsetFromEntityInWorldCoords(obj, (mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2)
    local low = math.huge
    for _, cx in ipairs({ mn.x, mx.x }) do
        for _, cy in ipairs({ mn.y, mx.y }) do
            for _, cz in ipairs({ mn.z, mx.z }) do
                local w = GetOffsetFromEntityInWorldCoords(obj, cx, cy, cz)
                if w.z < low then low = w.z end
            end
        end
    end
    SetEntityCoordsNoOffset(obj, x + (x - c.x), y + (y - c.y), z + (z - low), false, false, false)
end

local function rotate(lx, ly, h)
    local a = math.rad(h)
    return lx * math.cos(a) - ly * math.sin(a), lx * math.sin(a) + ly * math.cos(a)
end
Building.Rotate = rotate

-- Extra copies of the model (door frame posts) at their local offsets
function Building.PartOffsets(pieceId, tier)
    local sp = Building.Spec(P[pieceId], tier) or P[pieceId]
    return sp and sp.parts or nil
end

-- Mine = I placed it or it belongs to my faction. Owner = I manage its lock and prices.
function Building.IsMine(r)
    if r.ow ~= nil and r.ow == World.myChar then return true end
    return r.f ~= nil and r.f == World.myFaction
end
function Building.IsOwner(r)
    if r.ow ~= nil then return r.ow == World.myChar end
    return r.f ~= nil and r.f == World.myFaction
end

function Building.LabelOf(r)
    local tier = r.t
    if tier then
        local k = ('piece.%s.%s'):format(r.p, tier)
        local s = L(k)
        if s ~= k then return s end
    end
    return L('piece.' .. r.p)
end

-- Interactions

local function opt(label, icon, ev, id, dist) return { label = label, icon = icon, distance = dist or 2.8, event = ev, args = { id = id } } end

local function options(r)
    local d = P[r.p]
    local o = {}
    local mine = Building.IsMine(r)
    if not r.b then
        if mine then
            o[#o + 1] = opt(L('build.opt.deposit'), 'box', 'bs:building:act:deposit', r.id)
            o[#o + 1] = opt(L('build.opt.finish'), 'hammer', 'bs:building:act:hammer', r.id)
            o[#o + 1] = opt(L('build.opt.demolish'), 'trash', 'bs:building:act:demolish', r.id)
        end
        o[#o + 1] = opt(L('build.opt.inspect'), 'search', 'bs:building:act:inspect', r.id)
        return o
    end
    local owner = Building.IsOwner(r)
    if d.door then o[#o + 1] = opt(r.o and L('build.opt.close') or L('build.opt.open'), 'door', 'bs:building:act:door', r.id) end
    if d.vending then
        o[#o + 1] = opt(L('build.opt.vend_browse'), 'bag', 'bs:building:act:vend', r.id)
        if owner then o[#o + 1] = opt(L('build.opt.vend_stock'), 'box', 'bs:building:act:vendStock', r.id) end
    elseif d.storage then
        o[#o + 1] = opt(L('build.opt.storage'), 'bag', 'bs:building:act:storage', r.id)
    end
    if d.generator and mine then
        o[#o + 1] = opt(L('build.opt.generator'), 'power', 'bs:building:act:generator', r.id)
        o[#o + 1] = opt(L('build.opt.fuel'), 'fuel', 'bs:building:act:fuel', r.id)
    end
    if d.power and mine then
        o[#o + 1] = opt(r.lit and L('build.opt.light_off') or L('build.opt.light_on'), 'power', 'bs:building:act:light', r.id)
    end
    if (d.node or d.generator) and mine and World.cfg.wires then
        o[#o + 1] = opt(L('build.opt.wire'), 'power', 'bs:building:act:wire', r.id)
        o[#o + 1] = opt(L('build.opt.unwire'), 'power', 'bs:building:act:unwire', r.id)
    end
    if d.rain then o[#o + 1] = opt(L('build.opt.water'), 'water', 'bs:building:act:water', r.id) end
    if d.respawn and mine then o[#o + 1] = opt(L('build.opt.bed'), 'heart', 'bs:building:act:bed', r.id) end
    -- stations get their own options from bs_crafting
    if d.lock and owner then
        o[#o + 1] = opt(L('build.opt.lock_code'), 'lock', 'bs:building:act:code', r.id)
        if r.lm ~= 'faction' then o[#o + 1] = opt(L('build.opt.lock_faction'), 'lock', 'bs:building:act:lockFaction', r.id) end
        if r.lm ~= 'none' then o[#o + 1] = opt(L('build.opt.lock_none'), 'lock', 'bs:building:act:lockNone', r.id) end
    end
    if mine and not r.ab then
        if Building.NextTier(d, r.t) then o[#o + 1] = opt(L('build.opt.upgrade'), 'hammer', 'bs:building:act:upgrade', r.id) end
        if r.hp < r.mhp then o[#o + 1] = opt(L('build.opt.repair'), 'hammer', 'bs:building:act:hammer', r.id) end
    end
    if mine then
        o[#o + 1] = opt(L('build.opt.demolish'), 'trash', 'bs:building:act:demolish', r.id)
    elseif World.raids then
        o[#o + 1] = opt(L('build.opt.sledge'), 'hammer', 'bs:building:act:sledge', r.id)
        if r.lk then o[#o + 1] = opt(L('build.opt.grind'), 'gear', 'bs:building:act:grind', r.id) end
    end
    o[#o + 1] = opt(L('build.opt.inspect'), 'search', 'bs:building:act:inspect', r.id)
    return o
end

-- Only rebuild the option list when something it shows changed
local hookKey = {}
local function hook(obj, r, force)
    if GetResourceState('bs_interactions') ~= 'started' then return end
    local k = table.concat({ tostring(r.b), tostring(r.o), tostring(r.lit), tostring(r.t), tostring(r.lm), tostring(r.lk), tostring(r.hp < r.mhp), tostring(r.ab), tostring(World.myChar), tostring(World.myFaction), tostring(World.raids), tostring(World.cfg.wires) }, '|')
    if not force and hookKey[obj] == k then return end
    hookKey[obj] = k
    pcall(function() exports.bs_interactions:RemoveEntity(obj) end)
    pcall(function() exports.bs_interactions:AddEntity(obj, options(r)) end)
end
Building.Hook = hook

-- Props

local function despawn(id)
    local e = World.ents[id]
    if e and DoesEntityExist(e) then
        if GetResourceState('bs_interactions') == 'started' then pcall(function() exports.bs_interactions:RemoveEntity(e) end) end
        hookKey[e] = nil
        DeleteEntity(e)
    end
    for _, x in ipairs(World.extra[id] or {}) do if DoesEntityExist(x) then DeleteEntity(x) end end
    World.extra[id] = nil
    World.ents[id] = nil
end

-- Where a piece stands, with doors swung open on their hinge and gates slid aside
local function placeOf(r)
    local d = P[r.p]
    local x, y, h = r.x, r.y, r.h
    if r.o and d.door then
        if d.slide then
            local sx, sy = rotate(d.size[1] * 0.9, 0, r.h)
            x, y = r.x + sx, r.y + sy
        else
            local w = Building.SizeOf(r.p, r.t)
            local hx, hy = rotate(-w / 2, 0, r.h)
            local nx, ny = rotate(w / 2, 0, r.h + 90)
            x, y, h = r.x + hx + nx, r.y + hy + ny, r.h + 90
        end
    end
    return x, y, h
end

local function pose(obj, r)
    local d = P[r.p]
    local x, y, h = placeOf(r)
    local parts = Building.PartOffsets(r.p, r.t)
    local first = parts and parts[1]
    if first then
        local ox, oy = rotate(first.x or 0, first.y or 0, h)
        Building.Align(obj, x + ox, y + oy, r.z + (first.z or 0), h, d.pitch)
    else
        Building.Align(obj, x, y, r.z, h, d.pitch)
    end
    SetEntityCollision(obj, true, true)
    -- Frames are see-through until hammered, abandoned pieces fade.
    if not r.b then SetEntityAlpha(obj, 150, false)
    elseif r.ab then SetEntityAlpha(obj, 200, false)
    else ResetEntityAlpha(obj) end
    for i, e in ipairs(World.extra[r.id] or {}) do
        local pt = parts and parts[i + 1]
        if pt and DoesEntityExist(e) then
            local ox, oy = rotate(pt.x or 0, pt.y or 0, h)
            Building.Align(e, x + ox, y + oy, r.z + (pt.z or 0), h, d.pitch)
            if not r.b then SetEntityAlpha(e, 150, false) else ResetEntityAlpha(e) end
        end
    end
end

local function makeObj(hash, x, y, z)
    local obj = CreateObjectNoOffset(hash, x, y, z, false, false, false)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    return obj
end

local function spawn(r)
    local d = P[r.p]
    if not d then return end
    local e = World.ents[r.id]
    if e and DoesEntityExist(e) then pose(e, r); hook(e, r) return end
    local hash = Building.ModelFor(r.p, r.t)
    if not Building.LoadModel(hash) then return end
    if not World.pieces[r.id] or World.ents[r.id] then return end
    local obj = makeObj(hash, r.x, r.y, r.z)
    World.ents[r.id] = obj
    local parts = Building.PartOffsets(r.p, r.t)
    if parts and #parts > 1 then
        local list = {}
        for i = 2, #parts do list[#list + 1] = makeObj(hash, r.x, r.y, r.z) end
        World.extra[r.id] = list
    end
    SetModelAsNoLongerNeeded(hash)
    pose(obj, r)
    hook(obj, r)
end

function Building.EntityOf(id) return World.ents[id] end
function Building.PieceOfEntity(ent)
    for id, e in pairs(World.ents) do if e == ent and type(id) == 'number' then return World.pieces[id] end end
    for id, list in pairs(World.extra) do for _, x in ipairs(list) do if x == ent then return World.pieces[id] end end end
    return nil
end

RegisterNetEvent('bs:building:upsert', function(v)
    if type(v) ~= 'table' or not v.id then return end
    local old = World.pieces[v.id]
    World.pieces[v.id] = v
    local e = World.ents[v.id]
    if e and DoesEntityExist(e) then
        -- an upgrade swaps the model
        if old and old.t ~= v.t then despawn(v.id); CreateThread(function() spawn(v) end)
        else pose(e, v); hook(e, v) end
    end
end)

RegisterNetEvent('bs:building:remove', function(id, how)
    local r = World.pieces[id]
    World.pieces[id] = nil
    local e = World.ents[id]
    if r and e and DoesEntityExist(e) and how ~= 'demolish' and how ~= 'admin' then
        -- a little dust where it fell
        local c = GetEntityCoords(e)
        RequestNamedPtfxAsset('core')
        local t = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < t do Wait(0) end
        UseParticleFxAssetNextCall('core')
        StartParticleFxNonLoopedAtCoord('ent_dst_rocks', c.x, c.y, c.z + 0.5, 0.0, 0.0, 0.0, 2.0, false, false, false)
    end
    despawn(id)
end)

RegisterNetEvent('bs:building:reset', function()
    for id in pairs(World.pieces) do despawn(id) end
    World.pieces, World.cells, World.wires = {}, {}, {}
end)

RegisterNetEvent('bs:building:def', function(id, def) P[id] = def; for k in pairs(modelCache) do if k:find('^' .. id .. ':') then modelCache[k] = nil end end end)

RegisterNetEvent('bs:building:rubble', function(id, rb) World.rubble[id] = rb end)

RegisterNetEvent('bs:building:wire', function(w) if type(w) == 'table' and w.id then World.wires[w.id] = w end end)
RegisterNetEvent('bs:building:unwire', function(id) World.wires[id] = nil end)

-- Cell streaming: ask for the 3x3 cells around us, drop ones far behind.
CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(500) end
    local defs = BSB.Await('build:defs', 10000)
    if defs and defs.ok then
        for id, d in pairs(defs.pieces or {}) do if not P[id] then P[id] = d end end
        World.rubble = defs.rubble or {}
    end
    while true do
        local at = GetEntityCoords(PlayerPedId())
        local cx, cy = math.floor(at.x / CELL), math.floor(at.y / CELL)
        for dx = -1, 1 do
            for dy = -1, 1 do
                local k = (cx + dx) .. '|' .. (cy + dy)
                if not World.cells[k] then
                    local res = BSB.Await('build:cell', 8000, cx + dx, cy + dy)
                    if res and res.ok then
                        World.cells[k] = true
                        for _, v in ipairs(res.list or {}) do World.pieces[v.id] = v end
                        for _, w in ipairs(res.wires or {}) do World.wires[w.id] = w end
                    end
                end
            end
        end
        for k in pairs(World.cells) do
            local x, y = k:match('^(-?%d+)|(-?%d+)$')
            if math.abs(tonumber(x) - cx) > 2 or math.abs(tonumber(y) - cy) > 2 then
                World.cells[k] = nil
                for id, r in pairs(World.pieces) do
                    if math.floor(r.x / CELL) == tonumber(x) and math.floor(r.y / CELL) == tonumber(y) then
                        World.pieces[id] = nil; despawn(id)
                    end
                end
            end
        end
        for id, w in pairs(World.wires) do
            if not World.pieces[w.a] and not World.pieces[w.b] then World.wires[id] = nil end
        end
        -- spawn and despawn by distance, a few per pass to avoid hitches
        local budget = 12
        for id, r in pairs(World.pieces) do
            local d = #(at - vector3(r.x, r.y, r.z))
            if d <= S.streamDistance then
                if not World.ents[id] and budget > 0 then spawn(r); budget = budget - 1 end
            elseif World.ents[id] then despawn(id) end
        end
        Wait(1500)
    end
end)

-- Our faction, for the interaction options, plus the server switches the client needs.
CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(500) end
    while true do
        local res = BSB.Await('build:catalogue', 8000)
        if res and res.ok then
            World.cfg = { wires = res.wires == true, sound = res.sound ~= false, soundRange = tonumber(res.soundRange) or 45.0,
                          powerRadius = tonumber(res.powerRadius) or 20.0, poleRadius = tonumber(res.poleRadius) or 12.0,
                          wireMax = tonumber(res.wireMax) or 40.0, instant = res.instant == true }
        end
        local f = res and res.faction or nil
        local c = res and res.charId or World.myChar
        local raids = res and res.raids == true or false
        World.myFaction, World.myChar, World.raids = f, c, raids
        for id, e in pairs(World.ents) do
            if type(id) == 'number' and DoesEntityExist(e) and World.pieces[id] then hook(e, World.pieces[id]) end
        end
        Wait(60000)
    end
end)

-- Lights, generator lamps and hum, wires

local function topOf(r)
    local e = World.ents[r.id]
    if e and DoesEntityExist(e) then
        local mn, mx = Building.Dims(GetEntityModel(e))
        return GetOffsetFromEntityInWorldCoords(e, 0.0, 0.0, mx.z), GetEntityForwardVector(e), mx.z - mn.z
    end
    local d = P[r.p]
    return vector3(r.x, r.y, r.z + d.size[3]), vector3(0.0, 1.0, 0.0), d.size[3]
end
Building.TopOf = topOf

-- Where a cable attaches: near the top of a pole, the top of a generator, the middle of a box
function Building.WirePoint(r)
    local d = P[r.p]
    local top, _, h = topOf(r)
    if d and d.wireZ then return top + vector3(0.0, 0.0, d.wireZ) end
    if d and d.generator then return top end
    return top - vector3(0.0, 0.0, h * 0.45)
end

local hum = {}   -- running generators we sent to the NUI
CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        local lit = {}
        for _, r in pairs(World.pieces) do
            local d = P[r.p]
            if d and r.b and #(at - vector3(r.x, r.y, r.z)) < S.streamDistance then
                if d.light and r.lit and r.pw then lit[#lit + 1] = r
                elseif d.generator and r.on and (r.fuel or 0) > 0 and d.generator.topLights then lit[#lit + 1] = r
                elseif d.fire then lit[#lit + 1] = r end
            end
        end
        if #lit > 0 then sleep = 0 end
        for _, r in ipairs(lit) do
            local d = P[r.p]
            local top, fwd = topOf(r)
            if d.fire then
                local f = 0.85 + math.sin(GetGameTimer() / 90.0) * 0.1 + math.sin(GetGameTimer() / 37.0) * 0.05
                DrawLightWithRange(top.x, top.y, top.z + 0.3, 255, 150, 60, 7.0, 4.0 * f)
            elseif d.generator then
                -- the lamps on top of the large generator
                DrawLightWithRange(top.x, top.y, top.z + 0.2, 255, 230, 190, 14.0, 5.0)
                DrawSpotLight(top.x, top.y, top.z + 0.1, fwd.x, fwd.y, -0.35, 255, 236, 200, 22.0, 6.0, 0.0, 40.0, 25.0)
            else
                local L1 = d.light
                DrawLightWithRange(top.x, top.y, top.z - 0.1, 255, 232, 196, L1.range * 0.55, L1.intensity * 0.5)
                if L1.spot then
                    DrawSpotLight(top.x, top.y, top.z - 0.05, fwd.x, fwd.y, -0.45, 255, 236, 205, L1.range, L1.intensity, 0.0, 45.0, L1.range * 0.6)
                end
            end
        end
        Wait(sleep)
    end
end)

-- Generator hum: the NUI plays a loop per running generator, volume and pan from distance and camera angle.
CreateThread(function()
    while true do
        Wait(250)
        local list = {}
        if World.cfg.sound ~= false then
            local cam = GetGameplayCamCoord()
            local rot = GetGameplayCamRot(2)
            local range = World.cfg.soundRange or 45.0
            for _, r in pairs(World.pieces) do
                local d = P[r.p]
                if d and d.generator and r.b and r.on and (r.fuel or 0) > 0 then
                    local pos = vector3(r.x, r.y, r.z + 0.5)
                    local dist = #(cam - pos)
                    if dist < range then
                        local ang = math.deg(math.atan(pos.y - cam.y, pos.x - cam.x)) - 90.0
                        local rel = math.rad((ang - rot.z + 540.0) % 360.0 - 180.0)
                        local fall = 1.0 - dist / range
                        local size = d.generator.output >= 16 and 1.0 or (d.generator.output >= 8 and 0.8 or 0.6)
                        list[#list + 1] = { id = r.id, vol = math.max(0, fall * fall) * size, pan = math.max(-1, math.min(1, -math.sin(rel))) }
                    end
                end
            end
            table.sort(list, function(a, b) return a.vol > b.vol end)
            while #list > 3 do table.remove(list) end
        end
        local changed = #list ~= #hum
        if not changed then for i, h in ipairs(list) do if not hum[i] or hum[i].id ~= h.id or math.abs(hum[i].vol - h.vol) > 0.02 or math.abs(hum[i].pan - h.pan) > 0.05 then changed = true break end end end
        if changed then hum = list; SendNUIMessage({ action = 'hum', list = list }) end
    end
end)

-- Cables: a sagging line between the two ends
CreateThread(function()
    while true do
        local sleep = 800
        if next(World.wires) then
            local at = GetEntityCoords(PlayerPedId())
            for _, w in pairs(World.wires) do
                local a, b = World.pieces[w.a], World.pieces[w.b]
                if a and b and World.ents[w.a] and World.ents[w.b] and #(at - vector3(a.x, a.y, a.z)) < 140.0 then
                    sleep = 0
                    local p1, p2 = Building.WirePoint(a), Building.WirePoint(b)
                    local len = #(p2 - p1)
                    local sag = math.min(2.5, len * 0.05)
                    local live = a.pw or b.pw
                    local cr, cg, cb = live and 40 or 18, live and 34 or 18, live and 20 or 18
                    local prev = p1
                    for i = 1, 10 do
                        local t = i / 10
                        local p = p1 + (p2 - p1) * t - vector3(0.0, 0.0, sag * 4.0 * t * (1.0 - t))
                        DrawLine(prev.x, prev.y, prev.z, p.x, p.y, p.z, cr, cg, cb, 255)
                        prev = p
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Spikes, ramming

CreateThread(function()
    local lastRam = 0
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        local veh = GetVehiclePedIsIn(ped, false)
        for id, r in pairs(World.pieces) do
            local d = P[r.p]
            if d and r.b and not Building.IsMine(r) then
                local dist = #(at - vector3(r.x, r.y, r.z))
                if d.spikes and veh == 0 and dist < 1.6 then TriggerServerEvent('bs:building:spike', id) end
                if d.ram and World.raids and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and dist < 6.0 then
                    local e = World.ents[id]
                    if e and GetEntitySpeed(veh) >= S.ramMinSpeed * 0.6 and IsEntityTouchingEntity(veh, e)
                        and GetGameTimer() - lastRam > 1500 then
                        lastRam = GetGameTimer()
                        TriggerServerEvent('bs:building:ram', id)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('bs:building:hurt', function(n)
    local ped = PlayerPedId()
    ApplyDamageToPed(ped, math.min(25, tonumber(n) or 5), false)
end)

-- Rubble from a broken storage box: a marker you can search.
CreateThread(function()
    while true do
        local sleep = 1000
        local at = GetEntityCoords(PlayerPedId())
        for id, rb in pairs(World.rubble) do
            local d = #(at - vector3(rb.x, rb.y, rb.z))
            if d < 20.0 then
                sleep = 0
                DrawMarker(2, rb.x, rb.y, rb.z + 0.6, 0, 0, 0, 0, 180.0, 0, 0.3, 0.3, 0.3, 224, 140, 70, 160, true, true, 2, false, nil, nil, false)
                if d < 2.0 then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(L('build.rubble_help'))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustPressed(0, 38) then
                        CreateThread(function() BSB.Await('build:rubble', 6000, id) end)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

local pings = {}
RegisterNetEvent('bs:building:raidPing', function(x, y, z)
    local b = AddBlipForRadius(x, y, z, 60.0)
    SetBlipColour(b, 1); SetBlipAlpha(b, 140)
    local c = AddBlipForCoord(x, y, z)
    SetBlipSprite(c, 437); SetBlipColour(c, 1); SetBlipFlashes(c, true); SetBlipScale(c, 1.0)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(L('build.raid_blip')); EndTextCommandSetBlipName(c)
    pings[#pings + 1] = { b, c }
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    SetTimeout(120000, function() RemoveBlip(b); RemoveBlip(c) end)
end)

-- /buildzone list: show the build areas on the map for a minute (staff only, the server decides who gets this)
local zoneBlips = {}
RegisterNetEvent('bs:building:zones', function(list)
    for _, b in ipairs(zoneBlips) do RemoveBlip(b) end
    zoneBlips = {}
    for _, z in ipairs(list or {}) do
        local b = AddBlipForRadius(z.x + 0.0, z.y + 0.0, 0.0, (tonumber(z.radius) or 50) + 0.0)
        SetBlipColour(b, z.kind == 'allow' and 2 or 1); SetBlipAlpha(b, 110)
        zoneBlips[#zoneBlips + 1] = b
    end
    SetTimeout(60000, function() for _, b in ipairs(zoneBlips) do RemoveBlip(b) end zoneBlips = {} end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for _, b in ipairs(zoneBlips) do RemoveBlip(b) end
    for id in pairs(World.pieces) do despawn(id) end
    for _, p in ipairs(pings) do RemoveBlip(p[1]); RemoveBlip(p[2]) end
end)
