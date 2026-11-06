-- bs_building placing: ghost preview, Rust style sockets for structure pieces, free placing for the rest.
-- The ghost is green or red with the reason under it. The server checks everything again on place.

local S = Building.Settings
local P = Building.Pieces
local K = Building.Keys

local Place = { active = false }
Building.Place = Place

local EDGE = { wall = true, doorway = true }

-- Sockets: where a ghost of piece g (id, tier) can sit relative to a placed piece r. Sizes come from the real models.
local function socketsOf(r, gId, gTier)
    local out = {}
    local rd, gd = P[r.p], P[gId]
    if not rd or not gd or not rd.snap or not gd.snap then return out end
    local kind = gd.snap
    local rw, rdp, rh = Building.SizeOf(r.p, r.t)
    local gw, gdp, gh = Building.SizeOf(gId, gTier)
    local function add(lx, ly, lz, dh)
        local wx, wy = Building.Rotate(lx, ly, r.h)
        out[#out + 1] = { x = r.x + wx, y = r.y + wy, z = r.z + lz, h = (r.h + (dh or 0)) % 360, host = r.id }
    end
    -- a row of edge slots along one side: as many ghost widths as fit
    local function edge(len, fixed, alongX, z, dh)
        local n = math.max(1, math.floor(len / math.max(0.5, gw) + 0.35))
        local step = len / n
        for i = 1, n do
            local o = -len / 2 + step * (i - 0.5)
            if alongX then add(o, fixed, z, dh) else add(fixed, o, z, dh + 90) end
        end
    end
    local rs = rd.snap
    if rs == 'foundation' or rs == 'floor' then
        if kind == rs or (rs == 'foundation' and kind == 'foundation') then
            add(rw, 0, 0); add(-rw, 0, 0); add(0, rdp, 0); add(0, -rdp, 0)
        elseif rs == 'floor' and kind == 'floor' then
            add(rw, 0, 0); add(-rw, 0, 0); add(0, rdp, 0); add(0, -rdp, 0)
        elseif EDGE[kind] or kind == 'gate' then
            edge(rw, rdp / 2, true, rh, 0); edge(rw, -rdp / 2, true, rh, 180)
            edge(rdp, rw / 2, false, rh, 0); edge(rdp, -rw / 2, false, rh, 180)
        elseif kind == 'stairs' then
            add(0, 0, rh)
        end
    elseif EDGE[rs] then
        if EDGE[kind] then
            add(0, 0, rh)
            add(rw / 2 + gw / 2, 0, 0); add(-(rw / 2 + gw / 2), 0, 0)
        elseif kind == 'floor' or kind == 'roof' or kind == 'walkway' then
            add(0, gdp / 2, rh); add(0, -gdp / 2, rh)
        elseif kind == 'door' and rs == 'doorway' then
            add(0, 0, 0)
        elseif kind == 'gate' then
            add(rw / 2 + gw / 2, 0, 0); add(-(rw / 2 + gw / 2), 0, 0)
        end
    elseif rs == 'walkway' and kind == 'walkway' then
        add(rw, 0, 0); add(-rw, 0, 0)
    elseif rs == 'gate' and (kind == 'gate' or EDGE[kind]) then
        add(rw / 2 + gw / 2, 0, 0); add(-(rw / 2 + gw / 2), 0, 0)
    end
    return out
end

-- Is a socket already taken by a piece of the same kind?
local function taken(s, kind)
    for _, o in pairs(World.pieces) do
        local od = P[o.p]
        if od and od.snap == kind and math.abs(o.x - s.x) < 0.3 and math.abs(o.y - s.y) < 0.3 and math.abs(o.z - s.z) < 0.4 then return true end
    end
    return false
end

local function bestSnap(gId, gTier, aim)
    local gd = P[gId]
    local best, bestD = nil, 2.6
    for _, r in pairs(World.pieces) do
        if r.b ~= nil and #(aim - vector3(r.x, r.y, r.z)) < 16.0 then
            for _, s in ipairs(socketsOf(r, gId, gTier)) do
                local dz = math.abs(aim.z - s.z) * 0.6
                local d = math.sqrt((aim.x - s.x) ^ 2 + (aim.y - s.y) ^ 2 + dz * dz)
                if d < bestD and not taken(s, gd.snap) then best, bestD = s, d end
            end
        end
    end
    return best
end

local function camDir()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    return vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
end

-- What the crosshair hits (world and objects), ignoring the ghost. Returns point, hit, normal, entity.
local function aimPoint(ignore)
    local cam = GetGameplayCamCoord()
    local to = cam + camDir() * (S.placeDistance + 6.0)
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 | 16, ignore, 4)
    local _, hit, at, normal, ent = GetShapeTestResult(h)
    if hit == 1 then return at, true, normal, ent end
    return to, false, vector3(0.0, 0.0, 1.0), 0
end

-- Ground under a point, for foundations
local function groundAt(p)
    local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
    if ok then return z end
    return nil
end

-- Lootable world props (bins, lockers...) from bs_interactions, read once.
local lootModels
local function loadLootModels()
    lootModels = {}
    local src = LoadResourceFile('bs_interactions', 'config/config_containers.lua')
    if not src then return end
    local env = { vector3 = vector3, pairs = pairs, ipairs = ipairs, GetHashKey = GetHashKey, joaat = joaat, tostring = tostring, table = table, math = math }
    local fn = load(src, '@containers', 't', env)
    if not fn or not pcall(fn) or type(env.Containers) ~= 'table' then return end
    for _, t in pairs(env.Containers.Types or {}) do
        for _, m in ipairs(t.models or {}) do lootModels[#lootModels + 1] = GetHashKey(m) end
    end
end

local function nearLoot(at)
    if not lootModels then loadLootModels() end
    for _, hash in ipairs(lootModels) do
        if GetClosestObjectOfType(at.x, at.y, at.z, S.lootPadding, hash, false, false, false) ~= 0 then return true end
    end
    return false
end

local function ours(ent)
    if ent == 0 then return false end
    return Building.PieceOfEntity(ent) ~= nil
end

-- Does the piece box cut into map geometry or a map prop? Our own pieces never block.
local function clips(gId, tier, x, y, z, h, ghost)
    local d = P[gId]
    local w, dp, ht = Building.SizeOf(gId, tier)
    w, dp, ht = w * 0.8, dp * 0.8, ht * 0.7
    if d.pitch and d.pitch > 45 then ht = 0.1 end
    local handle = StartShapeTestBox(x, y, z + ht / 2 + 0.3, w, dp, math.max(ht - 0.3, 0.1), 0.0, 0.0, h, 2, 1 | 16, ghost, 4)
    local status, hit, _, _, ent = GetShapeTestResult(handle)
    local t = GetGameTimer() + 200
    while status == 1 and GetGameTimer() < t do Wait(0); status, hit, _, _, ent = GetShapeTestResult(handle) end
    return hit == 1 and not ours(ent)
end

local function hint(state) SendNUIMessage({ action = 'hint', state = state }) end

-- Bounding box of the ghost in green or red
local function drawBox(ent, good)
    local mn, mx = Building.Dims(GetEntityModel(ent))
    local r, g, b = good and 90 or 230, good and 230 or 70, good and 120 or 60
    local c = {}
    for i, v in ipairs({ { mn.x, mn.y, mn.z }, { mx.x, mn.y, mn.z }, { mx.x, mx.y, mn.z }, { mn.x, mx.y, mn.z },
                         { mn.x, mn.y, mx.z }, { mx.x, mn.y, mx.z }, { mx.x, mx.y, mx.z }, { mn.x, mx.y, mx.z } }) do
        c[i] = GetOffsetFromEntityInWorldCoords(ent, v[1], v[2], v[3])
    end
    local e = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
    for _, p in ipairs(e) do
        local a, bb = c[p[1]], c[p[2]]
        DrawLine(a.x, a.y, a.z, bb.x, bb.y, bb.z, r, g, b, 220)
    end
end

local function tint(ents, good)
    for _, e in ipairs(ents) do
        if SetEntityDrawOutline then
            SetEntityDrawOutline(e, true)
            SetEntityDrawOutlineColor(good and 90 or 230, good and 230 or 70, good and 120 or 60, 200)
        end
    end
end

local function makeGhost(pieceId, tier, at)
    local hash = Building.ModelFor(pieceId, tier)
    if not Building.LoadModel(hash) then return nil end
    local list = {}
    local parts = Building.PartOffsets(pieceId, tier)
    local n = (parts and #parts) or 1
    for i = 1, n do
        local g = CreateObjectNoOffset(hash, at.x, at.y, at.z, false, false, false)
        SetEntityAlpha(g, 170, false)
        SetEntityCollision(g, false, false)
        FreezeEntityPosition(g, true)
        list[i] = g
    end
    SetModelAsNoLongerNeeded(hash)
    return list
end

local function dropGhost(list)
    for _, g in ipairs(list or {}) do
        if SetEntityDrawOutline then SetEntityDrawOutline(g, false) end
        if DoesEntityExist(g) then DeleteEntity(g) end
    end
end

local function alignGhost(list, pieceId, tier, pos, h)
    local d = P[pieceId]
    local parts = Building.PartOffsets(pieceId, tier)
    for i, g in ipairs(list) do
        local pt = parts and parts[i]
        if pt then
            local ox, oy = Building.Rotate(pt.x or 0, pt.y or 0, h)
            Building.Align(g, pos.x + ox, pos.y + oy, pos.z + (pt.z or 0), h, d.pitch)
        else
            Building.Align(g, pos.x, pos.y, pos.z, h, d.pitch)
        end
    end
end

-- Short hammer swing after an instant place
local function swing(ms, ent)
    if not ms or ms <= 0 then return end
    CreateThread(function() Building.HammerWork(nil, ms, ent, true) end)
end

-- Place a piece. opts.bar = the bottom bar stays up and can swap the piece while placing.
function Building.StartPlacing(pieceId, opts)
    local d = P[pieceId]
    if not d then return { ok = false } end
    if Place.active then Place.want = pieceId; return { ok = true } end
    opts = opts or {}
    Place.active, Place.want, Place.bar = true, nil, opts.bar == true
    CreateThread(function()
        local tier = Building.BaseTier(d)
        local ped = PlayerPedId()
        local ghosts = makeGhost(pieceId, tier, GetEntityCoords(ped))
        if not ghosts then Place.active = false return end

        local snapOn, rotOff, lift, nudge = true, 0.0, 0.0, vector3(0.0, 0.0, 0.0)
        local pos, heading, valid, why = nil, 0.0, false, nil
        local lastCheck, lastPos, lastH = 0, nil, nil
        local serverOk, serverErr = false, nil
        local costs, free, lastCost = nil, false, 0
        local s = nil

        local function switch(newId)
            if not P[newId] then return end
            dropGhost(ghosts)
            pieceId, d = newId, P[newId]
            tier = Building.BaseTier(d)
            ghosts = makeGhost(pieceId, tier, GetEntityCoords(PlayerPedId())) or {}
            rotOff, lift, nudge = 0.0, 0.0, vector3(0.0, 0.0, 0.0)
            lastPos, serverOk, serverErr, costs, lastCost = nil, false, nil, nil, 0
        end

        while Place.active do
            Wait(0)
            if Place.want then local w = Place.want; Place.want = nil; switch(w) end
            if #ghosts == 0 then break end
            local ghost = ghosts[1]
            for _, c in ipairs({ K.place, K.cancel, K.rotL, K.rotR, 16, 17, 37, 140, 141, 142, K.raise, K.lower, K.reset, 44, 81, 82, 99, 100 }) do DisableControlAction(0, c, true) end
            for _, c in ipairs({ K.npLeft, K.npRight, K.npUp, K.npDown }) do DisableControlAction(0, c, true) end
            if not Place.bar then for _, c in ipairs({ K.left, K.right, K.up, K.down }) do DisableControlAction(0, c, true) end end

            local snaps = d.snap ~= nil
            local fine = IsControlPressed(0, K.fine) or IsDisabledControlPressed(0, K.fine)
            local stepRot = snaps and snapOn and ((EDGE[d.snap] or d.snap == 'door' or d.snap == 'gate') and 180 or 90) or (fine and 1 or 15)
            if IsDisabledControlJustPressed(0, K.rotL) or IsDisabledControlJustPressed(0, 16) then rotOff = rotOff + stepRot end
            if IsDisabledControlJustPressed(0, K.rotR) or IsDisabledControlJustPressed(0, 17) then rotOff = rotOff - stepRot end
            if IsControlJustPressed(0, K.snap) then snapOn = not snapOn end
            local step = fine and 0.01 or 0.05
            if IsDisabledControlPressed(0, K.raise) then lift = math.min(3.0, lift + step * 0.5) end
            if IsDisabledControlPressed(0, K.lower) then lift = math.max(-1.5, lift - step * 0.5) end
            if IsDisabledControlJustPressed(0, K.reset) then lift, nudge, rotOff = 0.0, vector3(0.0, 0.0, 0.0), 0.0 end
            local nx, ny = 0.0, 0.0
            local function pressed(c) return IsDisabledControlJustPressed(0, c) end
            if pressed(K.npLeft) or (not Place.bar and pressed(K.left)) then nx = -step end
            if pressed(K.npRight) or (not Place.bar and pressed(K.right)) then nx = step end
            if pressed(K.npUp) or (not Place.bar and pressed(K.up)) then ny = step end
            if pressed(K.npDown) or (not Place.bar and pressed(K.down)) then ny = -step end
            if nx ~= 0.0 or ny ~= 0.0 then nudge = nudge + vector3(nx, ny, 0.0) end

            local aim, hit = aimPoint(ghost)
            s = (snaps and snapOn) and bestSnap(pieceId, tier, aim) or nil
            local camH = GetGameplayCamRot(2).z
            local h
            if s then
                pos = vector3(s.x, s.y, s.z); h = (s.h + rotOff) % 360
            else
                h = (camH + rotOff) % 360
                -- nudge is relative to where you look
                local ox, oy = Building.Rotate(nudge.x, nudge.y, camH)
                if snapOn or snaps then
                    pos = aim + vector3(ox, oy, lift)
                else
                    -- surface snap off: the piece floats at the height you set, from your feet
                    local feet = GetEntityCoords(PlayerPedId()) - vector3(0.0, 0.0, 1.0)
                    pos = vector3(aim.x + ox, aim.y + oy, feet.z + lift)
                end
            end
            heading = h
            alignGhost(ghosts, pieceId, tier, pos, h)

            -- local checks every frame-ish, server rules a few times a second
            local me = GetEntityCoords(PlayerPedId())
            why = nil
            local needSup = type(d.support) == 'table' and S.needSupport ~= false
            if #(me - pos) > S.placeDistance then why = L('build.err.far')
            elseif snaps and d.snap ~= 'foundation' and d.snap ~= 'gate' and needSup and not s then
                why = d.snap == 'door' and L('build.err.attach') or L('build.err.support')
            elseif d.snap == 'foundation' and not s and not hit then why = L('build.err.no_ground')
            elseif d.snap == 'foundation' and not s then
                local gz = groundAt(pos)
                if not gz or pos.z - gz > 1.2 then why = L('build.err.no_ground') end
            end
            if GetGameTimer() - lastCheck > 300 then
                lastCheck = GetGameTimer()
                Place.clip = not why and not s and not d.flag and clips(pieceId, tier, pos.x, pos.y, pos.z, h, ghost) or false
                Place.loot = not why and nearLoot(pos) or false
                if not lastPos or #(lastPos - pos) > 0.15 or lastH ~= h then
                    lastPos, lastH = pos, h
                    local p0, id0 = pos, pieceId
                    CreateThread(function()
                        local r = BSB.Await('build:check', 4000, id0, { x = p0.x, y = p0.y, z = p0.z })
                        if lastPos == p0 and pieceId == id0 then serverOk, serverErr = r and r.ok, r and r.error end
                    end)
                end
            end
            if GetGameTimer() - lastCost > 2000 then
                lastCost = GetGameTimer()
                local id0 = pieceId
                CreateThread(function()
                    local r = BSB.Await('build:costs', 4000, id0)
                    if r and r.ok and pieceId == id0 then costs, free = r.costs, r.free end
                end)
            end
            if not why and Place.clip then why = L('build.err.clip') end
            if not why and Place.loot then why = L('build.err.loot') end
            if not why and not serverOk then why = serverErr or L('build.checking') end
            valid = why == nil

            tint(ghosts, valid)
            drawBox(ghost, valid)
            if GetGameTimer() - (Place.lastHint or 0) > 120 then
                Place.lastHint = GetGameTimer()
                local tLabel = tier and L('tier.' .. tier) or nil
                hint({ label = Building.LabelOf({ p = pieceId, t = tier }), tier = tLabel, valid = valid, reason = why,
                       snap = snapOn, snaps = snaps, snapped = s ~= nil, costs = costs, free = free, bar = Place.bar,
                       lift = math.floor(lift * 100 + 0.5) })
            end

            local cancel = IsDisabledControlJustPressed(0, K.cancel) or IsControlJustPressed(0, K.back) or IsDisabledControlJustPressed(0, K.back)
            if cancel then break end
            if IsDisabledControlJustPressed(0, K.place) then
                if not valid then
                    Building.Notify('warn', why or L('build.err.failed'))
                    PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                else
                    local res = BSB.Await('build:place', 8000, pieceId, { x = pos.x, y = pos.y, z = pos.z, h = heading })
                    if res and res.ok then
                        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                        if d.flag then Building.Notify('success', L('build.flag_placed'))
                        elseif res.built then swing(res.swing, ghost)
                        else Building.Notify('success', L('build.frame_placed')) end
                        if d.flag then break end
                        lastPos, lastCost = nil, 0
                    else
                        Building.Notify('warn', res and res.error or L('build.err.failed'))
                    end
                end
            end
        end
        dropGhost(ghosts)
        hint(nil)
        Place.active, Place.want = false, nil
        if Place.bar then Place.bar = false; TriggerEvent('bs:building:placeEnded') end
    end)
    return { ok = true }
end
exports('StartPlacing', function(id) return Building.StartPlacing(id) end)
exports('IsPlacing', function() return Place.active end)
function Building.StopPlacing() Place.active = false end
