-- bs_building world: streams nearby cells from the server, spawns local props, hooks interactions

local S = Building.Settings
local P = Building.Pieces

World = { pieces = {}, ents = {}, cells = {}, rubble = {}, myFaction = nil, myChar = nil, raids = false }
local CELL = 128.0

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 4500 }) end
Building.Notify = notify

-- First model the game actually has.
local modelCache = {}
function Building.ModelFor(pieceId)
    if modelCache[pieceId] ~= nil then return modelCache[pieceId] end
    local d = P[pieceId]
    local found = false
    for _, m in ipairs((d and d.models) or {}) do
        local hash = GetHashKey(m)
        if IsModelInCdimage(hash) and IsModelValid(hash) then found = hash break end
    end
    if not found then found = GetHashKey('prop_woodpile_04a') end
    modelCache[pieceId] = found
    return found
end

function Building.LoadModel(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash)
end

-- Put a prop so its bounding box bottom-centre sits on the piece origin, whatever its pivot.
function Building.Align(obj, x, y, z, h, pitch)
    SetEntityRotation(obj, pitch or 0.0, 0.0, h or 0.0, 2, true)
    SetEntityCoordsNoOffset(obj, x, y, z, false, false, false)
    local mn, mx = GetModelDimensions(GetEntityModel(obj))
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

-- Mine = I placed it or it belongs to my faction. Owner = I manage its lock and prices.
function Building.IsMine(r)
    if r.ow ~= nil and r.ow == World.myChar then return true end
    return r.f ~= nil and r.f == World.myFaction
end
function Building.IsOwner(r)
    if r.ow ~= nil then return r.ow == World.myChar end
    return r.f ~= nil and r.f == World.myFaction
end

local function rotate(lx, ly, h)
    local a = math.rad(h)
    return lx * math.cos(a) - ly * math.sin(a), lx * math.sin(a) + ly * math.cos(a)
end
Building.Rotate = rotate

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
        o[#o + 1] = opt(L('build.opt.fuel'), 'fuel', 'bs:building:act:fuel', r.id)
        o[#o + 1] = opt(r.on and L('build.opt.power_off') or L('build.opt.power_on'), 'power', 'bs:building:act:power', r.id)
    end
    if d.rain then o[#o + 1] = opt(L('build.opt.water'), 'water', 'bs:building:act:water', r.id) end
    if d.respawn and mine then o[#o + 1] = opt(L('build.opt.bed'), 'heart', 'bs:building:act:bed', r.id) end
    -- stations get their own options from bs_crafting
    if d.lock and owner then
        o[#o + 1] = opt(L('build.opt.lock_code'), 'lock', 'bs:building:act:code', r.id)
        if r.lm ~= 'faction' then o[#o + 1] = opt(L('build.opt.lock_faction'), 'lock', 'bs:building:act:lockFaction', r.id) end
        if r.lm ~= 'none' then o[#o + 1] = opt(L('build.opt.lock_none'), 'lock', 'bs:building:act:lockNone', r.id) end
    end
    if mine then
        if r.hp < r.mhp then o[#o + 1] = opt(L('build.opt.repair'), 'hammer', 'bs:building:act:hammer', r.id) end
        o[#o + 1] = opt(L('build.opt.demolish'), 'trash', 'bs:building:act:demolish', r.id)
    elseif World.raids then
        o[#o + 1] = opt(L('build.opt.sledge'), 'hammer', 'bs:building:act:sledge', r.id)
        if r.lk then o[#o + 1] = opt(L('build.opt.grind'), 'gear', 'bs:building:act:grind', r.id) end
    end
    o[#o + 1] = opt(L('build.opt.inspect'), 'search', 'bs:building:act:inspect', r.id)
    return o
end

local function hook(obj, r)
    if GetResourceState('bs_interactions') ~= 'started' then return end
    pcall(function() exports.bs_interactions:RemoveEntity(obj) end)
    pcall(function() exports.bs_interactions:AddEntity(obj, options(r)) end)
end

-- Props

local function despawn(id)
    local e = World.ents[id]
    if e and DoesEntityExist(e) then
        if GetResourceState('bs_interactions') == 'started' then pcall(function() exports.bs_interactions:RemoveEntity(e) end) end
        DeleteEntity(e)
    end
    World.ents[id] = nil
end

local function pose(obj, r)
    local d = P[r.p]
    local x, y, h = r.x, r.y, r.h
    if r.o and d.door and not d.attach or (r.o and r.p == 'door') then
        -- swing on the left edge
        local hx, hy = rotate(-d.size[1] / 2, 0, r.h)
        local nx, ny = rotate(d.size[1] / 2, 0, r.h + 90)
        x, y, h = r.x + hx + nx, r.y + hy + ny, r.h + 90
    end
    Building.Align(obj, x, y, r.z, h, d.pitch)
    if r.o and r.p == 'hatch' then SetEntityCollision(obj, false, false); SetEntityAlpha(obj, 90, false)
    else SetEntityCollision(obj, true, true) end
    -- Frames are see-through until hammered.
    if not r.b then SetEntityAlpha(obj, 150, false) elseif not (r.o and r.p == 'hatch') then ResetEntityAlpha(obj) end
end

local function spawn(r)
    local d = P[r.p]
    if not d then return end
    local e = World.ents[r.id]
    if e and DoesEntityExist(e) then pose(e, r); hook(e, r) return end
    local hash = Building.ModelFor(r.p)
    if not Building.LoadModel(hash) then return end
    if not World.pieces[r.id] or World.ents[r.id] then return end
    local obj = CreateObjectNoOffset(hash, r.x, r.y, r.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    pose(obj, r)
    World.ents[r.id] = obj
    hook(obj, r)
end

function Building.EntityOf(id) return World.ents[id] end
function Building.PieceOfEntity(ent)
    for id, e in pairs(World.ents) do if e == ent then return World.pieces[id] end end
    return nil
end

RegisterNetEvent('bs:building:upsert', function(v)
    if type(v) ~= 'table' or not v.id then return end
    World.pieces[v.id] = v
    local e = World.ents[v.id]
    if e and DoesEntityExist(e) then pose(e, v); hook(e, v) end
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
    for id in pairs(World.ents) do despawn(id) end
    World.pieces, World.cells = {}, {}
end)

RegisterNetEvent('bs:building:def', function(id, def) P[id] = def; modelCache[id] = nil end)

RegisterNetEvent('bs:building:rubble', function(id, rb) World.rubble[id] = rb end)

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

-- Our faction, for the interaction options.
CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(500) end
    while true do
        local res = BSB.Await('build:catalogue', 8000)
        local f = res and res.faction or nil
        local c = res and res.charId or World.myChar
        local raids = res and res.raids == true or false
        if f ~= World.myFaction or c ~= World.myChar or raids ~= World.raids then
            World.myFaction, World.myChar, World.raids = f, c, raids
            for id, e in pairs(World.ents) do if DoesEntityExist(e) and World.pieces[id] then hook(e, World.pieces[id]) end end
        end
        Wait(60000)
    end
end)

-- Lights, spikes, ramming, rubble, raid ping

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        local gens = {}
        for _, r in pairs(World.pieces) do
            if r.on and r.b and P[r.p] and P[r.p].generator then gens[#gens + 1] = r end
        end
        if #gens > 0 then
            for _, r in pairs(World.pieces) do
                local d = P[r.p]
                if d and d.light and r.b and #(at - vector3(r.x, r.y, r.z)) < S.streamDistance then
                    for _, g in ipairs(gens) do
                        if g.f == r.f and #(vector3(g.x, g.y, g.z) - vector3(r.x, r.y, r.z)) <= S.lightRange then
                            DrawLightWithRange(r.x, r.y, r.z + d.size[3], 255, 214, 160, 14.0, 3.0)
                            sleep = 0
                            break
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

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
    for id in pairs(World.ents) do despawn(id) end
    for _, p in ipairs(pings) do RemoveBlip(p[1]); RemoveBlip(p[2]) end
end)
