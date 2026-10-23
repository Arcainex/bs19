-- bs_building placing: build wheel (F2), ghost preview, snapping, scroll to rotate.

local S = Building.Settings
local P = Building.Pieces
local K = Building.Keys

local Place = { active = false }
local WALLS = { wall = true, wall_doorway = true, wall_window = true }

-- Real deck height of the foundation model, so walls sit on top of whatever prop the game picked.
local deckTop
local function foundationTop()
    if deckTop then return deckTop end
    local hash = Building.ModelFor('foundation')
    if not IsModelInCdimage(hash) or not HasModelLoaded(hash) then return P.foundation.size[3] end -- try again once loaded
    local mn, mx = GetModelDimensions(hash)
    deckTop = math.max(0.1, math.min(1.0, mx.z - mn.z))
    return deckTop
end
local FLOORS = { floor = true, floor_frame = true }

-- Sockets: where a piece of kind k can sit relative to an existing piece (local x, y, z, extra heading)
local function socketsOf(r)
    local out = {}
    local function add(kinds, lx, ly, lz, dh)
        local wx, wy = Building.Rotate(lx, ly, r.h)
        out[#out + 1] = { kinds = kinds, x = r.x + wx, y = r.y + wy, z = r.z + lz, h = (r.h + (dh or 0)) % 360 }
    end
    local p = r.p
    if p == 'foundation' then
        local f = { foundation = true }
        local t = foundationTop()
        add(f, 3, 0, 0); add(f, -3, 0, 0); add(f, 0, 3, 0); add(f, 0, -3, 0)
        add(WALLS, 0, 1.5, t); add(WALLS, 0, -1.5, t); add(WALLS, 1.5, 0, t, 90); add(WALLS, -1.5, 0, t, 90)
        add({ stairs = true }, 0, 0, t)
    elseif WALLS[p] then
        add(WALLS, 0, 0, 3); add(WALLS, 3, 0, 0); add(WALLS, -3, 0, 0)
        local top = { floor = true, floor_frame = true, roof = true }
        add(top, 0, 1.5, 3); add(top, 0, -1.5, 3)
        add({ walkway = true }, 0, 0.875, 3); add({ walkway = true }, 0, -0.875, 3)
        if p == 'wall_doorway' then add({ door = true }, 0, 0, 0) end
        if p == 'wall_window' then add({ window = true }, 0, 0, 0.9) end
    elseif FLOORS[p] then
        add(FLOORS, 3, 0, 0); add(FLOORS, -3, 0, 0); add(FLOORS, 0, 3, 0); add(FLOORS, 0, -3, 0)
        add(WALLS, 0, 1.5, 0.2); add(WALLS, 0, -1.5, 0.2); add(WALLS, 1.5, 0, 0.2, 90); add(WALLS, -1.5, 0, 0.2, 90)
        add({ stairs = true }, 0, 0, 0.2)
        if p == 'floor_frame' then add({ hatch = true }, 0, 0, 0) end
    elseif p == 'walkway' then
        add({ walkway = true }, 3, 0, 0); add({ walkway = true }, -3, 0, 0)
    elseif p == 'watchtower' then
        add({ walkway = true }, 0, 2.25, 6); add({ walkway = true }, 0, -2.25, 6)
    elseif p == 'fence' then
        add({ fence = true }, 3, 0, 0); add({ fence = true }, -3, 0, 0)
    end
    return out
end

local function bestSnap(kind, aim)
    local best, bestD = nil, 2.2
    for _, r in pairs(World.pieces) do
        if #(aim - vector3(r.x, r.y, r.z)) < 9.0 then
            for _, s in ipairs(socketsOf(r)) do
                if s.kinds[kind] then
                    local d = #(aim - vector3(s.x, s.y, s.z))
                    if d < bestD then best, bestD = s, d end
                end
            end
        end
    end
    return best
end

local function aimPoint(ignore)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    local to = cam + dir * (S.placeDistance + 6.0)
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 | 16, ignore, 4)
    local _, hit, at = GetShapeTestResult(h)
    if hit == 1 then return at end
    return to
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
    for _, e in pairs(World.ents) do if e == ent then return true end end
    return false
end

-- Does the piece box cut into map geometry or a map prop?
local function clips(d, x, y, z, h, ghost)
    local w, dp, ht = d.size[1] * 0.8, d.size[2] * 0.8, d.size[3] * 0.75
    if d.pitch and d.pitch > 45 then ht = 0.1 end
    local handle = StartShapeTestBox(x, y, z + d.size[3] / 2 + 0.25, w, dp, math.max(ht, 0.1), 0.0, 0.0, h, 2, 1 | 16, ghost, 4)
    local status, hit, _, _, ent = GetShapeTestResult(handle)
    local t = GetGameTimer() + 200
    while status == 1 and GetGameTimer() < t do Wait(0); status, hit, _, _, ent = GetShapeTestResult(handle) end
    return hit == 1 and not ours(ent)
end

local function hint(state) SendNUIMessage({ action = 'hint', state = state }) end

function Building.StartPlacing(pieceId)
    local d = P[pieceId]
    if not d or Place.active then return { ok = false } end
    Place.active = true
    CreateThread(function()
        local hash = Building.ModelFor(pieceId)
        if not Building.LoadModel(hash) then Place.active = false return end
        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        local ghost = CreateObjectNoOffset(hash, at.x, at.y, at.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        SetEntityAlpha(ghost, 170, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)

        local heading, snapOn, rotOff = GetEntityHeading(ped), true, 0.0
        local pos, valid, why = nil, false, nil
        local lastCheck, lastPos = 0, nil
        local serverOk, serverErr = false, nil
        -- have/need for the prompt, refreshed every 2 s (bag plus nearby storage)
        local costs, free, lastCost = nil, false, 0

        while Place.active do
            Wait(0)
            DisableControlAction(0, K.place, true); DisableControlAction(0, K.cancel, true)
            DisableControlAction(0, K.rotL, true); DisableControlAction(0, K.rotR, true)
            DisableControlAction(0, 16, true); DisableControlAction(0, 17, true)
            DisableControlAction(0, 37, true); DisableControlAction(0, 140, true); DisableControlAction(0, 141, true); DisableControlAction(0, 142, true)

            if IsDisabledControlJustPressed(0, K.rotL) or IsDisabledControlJustPressed(0, 16) then rotOff = rotOff + (snapOn and 90 or 15) end
            if IsDisabledControlJustPressed(0, K.rotR) or IsDisabledControlJustPressed(0, 17) then rotOff = rotOff - (snapOn and 90 or 15) end
            if IsControlJustPressed(0, K.snap) then snapOn = not snapOn end

            local aim = aimPoint(ghost)
            local s = snapOn and bestSnap(pieceId, aim)
            local h
            if s then
                pos = vector3(s.x, s.y, s.z); h = (s.h + rotOff) % 360
            else
                pos = aim; h = (GetGameplayCamRot(2).z + rotOff) % 360
            end
            heading = h
            Building.Align(ghost, pos.x, pos.y, pos.z, h, d.pitch)

            -- local checks every frame-ish, server rules a few times a second
            local me = GetEntityCoords(PlayerPedId())
            why = nil
            if #(me - pos) > S.placeDistance then why = L('build.err.far')
            elseif d.attach and not s then why = L('build.err.attach') -- doors and windows need their slot, nothing else needs support
            end
            if GetGameTimer() - lastCheck > 350 then
                lastCheck = GetGameTimer()
                if not why and clips(d, pos.x, pos.y, pos.z, h, ghost) then Place.clip = true else Place.clip = false end
                if not why and nearLoot(pos) then Place.loot = true else Place.loot = false end
                if not lastPos or #(lastPos - pos) > 0.2 then
                    lastPos = pos
                    local p0 = pos
                    CreateThread(function()
                        local r = BSB.Await('build:check', 4000, pieceId, { x = p0.x, y = p0.y, z = p0.z })
                        if lastPos == p0 then serverOk, serverErr = r and r.ok, r and r.error end
                    end)
                end
            end
            if GetGameTimer() - lastCost > 2000 then
                lastCost = GetGameTimer()
                CreateThread(function()
                    local r = BSB.Await('build:costs', 4000, pieceId)
                    if r and r.ok then costs, free = r.costs, r.free end
                end)
            end
            if not why and Place.clip and not d.flag then why = L('build.err.clip') end
            if not why and Place.loot then why = L('build.err.loot') end
            if not why and not serverOk then why = serverErr or L('build.checking') end
            valid = why == nil

            DrawMarker(25, pos.x, pos.y, pos.z + 0.03, 0, 0, 0, 0, 0, 0, d.size[1], math.max(d.size[2], 0.6), 1.0,
                valid and 127 or 180, valid and 212 or 87, valid and 162 or 74, 140, false, false, 2, false, nil, nil, false)
            if GetGameTimer() - (Place.lastHint or 0) > 120 then
                Place.lastHint = GetGameTimer()
                hint({ label = L('piece.' .. pieceId), valid = valid, reason = why, snap = snapOn, costs = costs, free = free })
            end

            if IsDisabledControlJustPressed(0, K.cancel) or IsControlJustPressed(0, 177) then break end
            if IsDisabledControlJustPressed(0, K.place) then
                if not valid then
                    Building.Notify('warn', why or L('build.err.failed'))
                else
                    local res = BSB.Await('build:place', 8000, pieceId, { x = pos.x, y = pos.y, z = pos.z, h = heading })
                    if res and res.ok then
                        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                        Building.Notify('success', d.flag and L('build.flag_placed') or L('build.frame_placed'))
                        if d.flag then break end
                        lastPos = nil
                    else
                        Building.Notify('warn', res and res.error or L('build.err.failed'))
                    end
                end
            end
        end
        DeleteEntity(ghost)
        hint(nil)
        Place.active = false
    end)
    return { ok = true }
end
exports('StartPlacing', function(id) return Building.StartPlacing(id) end)
exports('IsPlacing', function() return Place.active end)

-- Build wheel (F2)

local wheelOpen = false
local function openWheel()
    if wheelOpen or Place.active then return end
    local res = BSB.Await('build:catalogue', 8000)
    if not res or not res.ok then return end
    if res.mode == 'claim' and not res.faction then return Building.Notify('warn', L('build.err.no_faction')) end
    wheelOpen = true
    TriggerEvent('bs:ui:opened', 'building')
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'wheel', data = res, cats = Building.Categories })
end
local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wheelClose' })
end

RegisterNUICallback('wheelPick', function(data, cb)
    closeWheel()
    cb({ ok = true })
    if data and P[data.id] then Building.StartPlacing(data.id) end
end)
RegisterNUICallback('wheelClose', function(_, cb) closeWheel(); cb({ ok = true }) end)
AddEventHandler('bs:ui:opened', function(what) if what ~= 'building' then closeWheel() end end)

-- Same command name as before so old F2 binds still work.
RegisterCommand('+factionbuild', function() CreateThread(openWheel) end, false)
RegisterCommand('-factionbuild', function() end, false)
RegisterKeyMapping('+factionbuild', L('keymap.build_wheel'), 'keyboard', 'F2')
