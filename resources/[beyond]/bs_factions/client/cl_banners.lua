-- bs_factions - faction banners in the world. Each faction's emblem is rendered once into a DUI texture
-- and drawn as a waving cloth from the top of a pole: safezone banners (config or /factionbanner) and
-- the flags placed through bs_faction_bases.

local CFG = Factions.Banners or {}
local RANGE = (CFG.drawRange or 90.0) + 0.0
local W, H, STRIPS = 2.3, 1.45, 10
local MAX_DUI = 8

local Banners = {}      -- from the server: { id, factionId, x, y, z, heading }
local Poles = {}        -- [banner id] = entity we spawned
local Emblems = {}      -- [factionId] = { emblem, logo } (false while asking)
local Tex = {}          -- [factionId] = { dui, txn, used }
local txd, texN = nil, 0
local poleHash
local Grounded={}
local generation=0

local function firstModel(list)
    for _, m in ipairs(list or {}) do
        local h = GetHashKey(m)
        if IsModelInCdimage(h) then return h end
    end
end

local function ask(ids)
    local want = {}
    for _, id in ipairs(ids) do if Emblems[id] == nil then Emblems[id] = false; want[#want + 1] = id end end
    if #want == 0 then return end
    local r = BSB.Await('factions:emblems', 6000, want)
    for _, id in ipairs(want) do
        if type(r) == 'table' and r[id] then Emblems[id] = r[id] else Emblems[id] = nil end
    end
end

local function urlFor(fid,token)
    local e = Emblems[fid] or {}
    local data = json.encode({ id = fid, emblem = e.emblem, logo = e.logo, token=token, resource=GetCurrentResourceName() })
    return 'https://cfx-nui-' .. GetCurrentResourceName() .. '/html/banner.html?d=' .. (data:gsub('[^%w%-_%.~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

local function dropTex(fid)
    local t = Tex[fid]
    if t and t.dui then DestroyDui(t.dui) end
    Tex[fid] = nil
end

RegisterNUICallback('bannerReady',function(data,cb)
    local record=type(data)=='table'and Tex[tostring(data.id)]
    if record and data.token==record.token then record.painted=true end
    cb({ok=true})
end)
local function texFor(fid)
    fid=tostring(fid)
    local t=Tex[fid]
    if t then
        t.used=GetGameTimer()
        if t.ready then return t.txn end
        if not t.failed or GetGameTimer()<(t.retryAt or 0)then return nil end
        Tex[fid]=nil
    end
    if not Emblems[fid]then return nil end
    local n=0;for _ in pairs(Tex)do n=n+1 end
    if n>=MAX_DUI then
        local oldId,oldTime
        for id,v in pairs(Tex)do if not oldTime or v.used<oldTime then oldId,oldTime=id,v.used end end
        dropTex(oldId)
    end
    texN=texN+1
    local record={token=texN,used=GetGameTimer(),ready=false}
    Tex[fid]=record
    CreateThread(function()
        local ok,reason=pcall(function()
            txd=txd or CreateRuntimeTxd('bs_banners')
            if not txd or txd==0 then error('Texture dictionary unavailable')end
            record.dui=CreateDui(urlFor(fid,record.token),512,320)
            if not record.dui or record.dui==0 then error('Banner browser unavailable')end
            local deadline=GetGameTimer()+7000
            while Tex[fid]==record and GetGameTimer()<deadline and (not IsDuiAvailable(record.dui)or not record.painted)do Wait(25)end
            if Tex[fid]~=record then return end
            if not IsDuiAvailable(record.dui)or not record.painted then error('Faction emblem page did not become ready')end
            record.txn=('f%d'):format(record.token)
            local texture=CreateRuntimeTextureFromDuiHandle(txd,record.txn,GetDuiHandle(record.dui))
            if not texture or texture==0 then error('Banner texture unavailable')end
            record.ready=true
        end)
        if not ok and Tex[fid]==record then
            if record.dui then DestroyDui(record.dui);record.dui=nil end
            record.failed=true;record.retryAt=GetGameTimer()+5000
            print(('[bs_factions] banner %s: %s; retrying'):format(fid,tostring(reason)))
        end
    end)
    return nil
end

-- A new emblem: rebuild that faction's cloth.
RegisterNetEvent('bs:factions:emblem', function(fid, emblem, logo)
    if type(fid) ~= 'string' then return end
    Emblems[fid] = { emblem = emblem, logo = logo }
    if Tex[fid] then dropTex(fid) end
end)

local function removePoles()
    for id, e in pairs(Poles) do if DoesEntityExist(e) then DeleteEntity(e) end; Poles[id] = nil end
end

RegisterNetEvent('bs:factions:banners', function(list)
    if type(list) ~= 'table' then return end
    generation=generation+1
    removePoles()
    Grounded={}
    Banners = list
end)

local function spawnPole(b)
    if Poles[b.id]and DoesEntityExist(Poles[b.id])then return end
    Poles[b.id]=nil;Grounded[b.id]=nil
    if not poleHash then return end
    local version=generation
    RequestModel(poleHash)
    local untilAt = GetGameTimer() + 4000
    while not HasModelLoaded(poleHash) and GetGameTimer() < untilAt do Wait(0) end
    if not HasModelLoaded(poleHash)then return end
    if version~=generation then SetModelAsNoLongerNeeded(poleHash);return end
    local mn = GetModelDimensions(poleHash)
    local obj = CreateObjectNoOffset(poleHash, b.x, b.y, b.z - mn.z, false, false, false)
    if not obj or obj==0 or not DoesEntityExist(obj)then SetModelAsNoLongerNeeded(poleHash);return end
    SetEntityAsMissionEntity(obj,true,true)
    SetEntityCollision(obj,false,false)
    Entity(obj).state:set('bsProtected',true,false)
    SetEntityHeading(obj, b.heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(poleHash)
    Poles[b.id] = obj
end

local function groundPole(b)
    local object=Poles[b.id]
    if Grounded[b.id]or not object or not DoesEntityExist(object)then return end
    RequestCollisionAtCoord(b.x,b.y,b.z)
    if not HasCollisionLoadedAroundEntity(object)then return end
    local found,z=GetGroundZFor_3dCoord(b.x,b.y,b.z+2.0,false)
    if not found or z > b.z+2.0 or z < b.z-20.0 then return end
    local low=GetModelDimensions(GetEntityModel(object))
    SetEntityCoordsNoOffset(object,b.x,b.y,z-low.z,false,false,false)
    Grounded[b.id]=true
end

-- Where the cloth hangs: just under the top of the pole, flying to the pole's right.
local function anchorOf(entity, x, y, z, heading)
    if entity and DoesEntityExist(entity) then
        local _, mx = GetModelDimensions(GetEntityModel(entity))
        local c = GetEntityCoords(entity)
        return vector3(c.x, c.y, c.z + mx.z - 0.25), GetEntityHeading(entity)
    end
    return vector3(x, y, z + 4.2), heading or 0.0
end

local function drawCloth(top, heading, txn, t, seed)
    local rad = math.rad(heading)
    local right = vector3(math.cos(rad), math.sin(rad), 0.0)
    local normal = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local hr = GetClockHours()
    local lit = (hr >= 20 or hr < 6) and 95 or 235
    local prev
    for i = 0, STRIPS do
        local u = i / STRIPS
        local wave = math.sin(t * 2.4 + u * 6.0 + seed) * 0.16 * u + math.sin(t * 4.1 + u * 11.0 + seed) * 0.04 * u
        local droop = -0.10 * u * u
        local base = top + right * (u * W) + normal * wave + vector3(0.0, 0.0, droop)
        local p = { a = base, b = base - vector3(0.0, 0.0, H), u = u, s = math.floor(lit - math.abs(math.cos(t * 2.4 + u * 6.0 + seed)) * 40 * u) }
        if prev then
            local s = math.max(40, p.s)
            -- front
            DrawSpritePoly(prev.a.x, prev.a.y, prev.a.z, p.a.x, p.a.y, p.a.z, prev.b.x, prev.b.y, prev.b.z, s, s, s, 255, 'bs_banners', txn, prev.u, 0.0, 1.0, p.u, 0.0, 1.0, prev.u, 1.0, 1.0)
            DrawSpritePoly(p.a.x, p.a.y, p.a.z, p.b.x, p.b.y, p.b.z, prev.b.x, prev.b.y, prev.b.z, s, s, s, 255, 'bs_banners', txn, p.u, 0.0, 1.0, p.u, 1.0, 1.0, prev.u, 1.0, 1.0)
            -- back (reversed winding, so it is seen from the other side, mirrored like real cloth)
            DrawSpritePoly(prev.a.x, prev.a.y, prev.a.z, prev.b.x, prev.b.y, prev.b.z, p.a.x, p.a.y, p.a.z, s, s, s, 255, 'bs_banners', txn, prev.u, 0.0, 1.0, prev.u, 1.0, 1.0, p.u, 0.0, 1.0)
            DrawSpritePoly(p.a.x, p.a.y, p.a.z, prev.b.x, prev.b.y, prev.b.z, p.b.x, p.b.y, p.b.z, s, s, s, 255, 'bs_banners', txn, p.u, 0.0, 1.0, prev.u, 1.0, 1.0, p.u, 1.0, 1.0)
        end
        prev = p
    end
end

-- Everything that should fly a cloth right now, near the player.
local visible = {}
CreateThread(function()
    if CFG.enabled == false then return end
    if type(DrawSpritePoly) ~= 'function' then
        print('^3[bs_factions]^7 this game build has no DrawSpritePoly, banners stay off')
        return
    end
    poleHash = firstModel(CFG.poleModels)
    Wait(3000)
    local r = BSB.Await('factions:banners', 8000)
    if type(r) == 'table' and r.list then Banners = r.list end
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local list, ids = {}, {}
        for _, b in ipairs(Banners) do
            local d = #(me - vector3(b.x, b.y, b.z))
            if d < RANGE * 1.4 then
                spawnPole(b)
                groundPole(b)
                if d < RANGE then list[#list + 1] = { fid = b.factionId, entity = Poles[b.id], x = b.x, y = b.y, z = b.z, h = b.heading, seed = (b.x % 7) }; ids[#ids + 1] = b.factionId end
            elseif Poles[b.id] then
                if DoesEntityExist(Poles[b.id]) then DeleteEntity(Poles[b.id]) end
                Poles[b.id] = nil
            end
        end
        if GetResourceState('bs_faction_bases') == 'started' then
            local ok, flags = pcall(function() return exports.bs_faction_bases:FlagList() end)
            for _, f in ipairs(ok and type(flags) == 'table' and flags or {}) do
                if f.factionId and #(me - vector3(f.x, f.y, f.z)) < RANGE then
                    list[#list + 1] = { fid = f.factionId, entity = f.entity, x = f.x, y = f.y, z = f.z, h = f.heading, seed = (f.x % 7) }
                    ids[#ids + 1] = f.factionId
                end
            end
        end
        ask(ids)
        visible = list
        -- textures nobody has looked at for a minute are freed
        local now = GetGameTimer()
        for fid, t in pairs(Tex) do if now - t.used > 60000 then dropTex(fid) end end
        Wait(1500)
    end
end)

CreateThread(function()
    while true do
        if #visible == 0 then
            Wait(500)
        else
            local t = GetGameTimer() / 1000.0
            for _, v in ipairs(visible) do
                local txn = texFor(v.fid)
                if txn then
                    local top, heading = anchorOf(v.entity, v.x, v.y, v.z, v.h)
                    drawCloth(top, heading, txn, t, v.seed)
                end
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    removePoles()
    for fid in pairs(Tex) do dropTex(fid) end
end)
