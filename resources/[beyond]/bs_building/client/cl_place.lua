-- bs_building placing: build wheel (F2), ghost preview, snapping, scroll to rotate.

local S = Building.Settings
local P = Building.Pieces
local K = Building.Keys

local Place = { active = false }
local openWheel -- forward declaration for ESC / single-item return
local altWalk = false
local altToggleArmed = false
local walkPlaceArmed = true
local walkCancelArmed = true
local magneticSnap = true
local foundationHeight = 0.0
local overlayCursor = false
local collisionDecision = nil
local collisionPending = false
local placementInput = { rotate = false, place = false, cancel = false, magnet = false, wheel = 0 }
local WALLS = { wall = true, wall_doorway = true, wall_window = true }
local BUILD_PARTS = {foundation=true, wall=true, wall_doorway=true, wall_window=true,
    roof=true, floor=true, floor_frame=true, stairs=true, ceiling=true, support_beam=true}

-- Modular geometry: Align() centres each model's visible XY bounds and puts its
-- lowest point at placement Z. Snap sockets therefore use visible half-extents,
-- not the model pivot. All tiers keep the same 3 x 3 m connection grid.
local modelExtentsCache = {}
local function modelExtents(pieceId, fallbackX, fallbackY, fallbackZ)
    local hash = Building.ModelFor(pieceId)
    if not hash or not IsModelInCdimage(hash) or not HasModelLoaded(hash) then
        return fallbackX, fallbackY, fallbackZ
    end
    if not modelExtentsCache[hash] then
        local mn, mx = GetModelDimensions(hash)
        modelExtentsCache[hash] = {
            x = math.max(0.01, mx.x - mn.x),
            y = math.max(0.01, mx.y - mn.y),
            z = math.max(0.01, mx.z - mn.z)
        }
    end
    local bounds = modelExtentsCache[hash]
    return bounds.x, bounds.y, bounds.z
end
local function foundationTop()
    -- The custom foundation top is exactly 0.32m above its placement anchor.
    -- Never infer snap socket Z from a newly decorated YDR bounding box.
    -- Non-BS19 fallback models keep their old dimension-based behaviour.
    if Building.ModelFor('foundation') == GetHashKey('bs_foundation_t1') then
        return 0.32
    end
    local _, _, height = modelExtents('foundation', 3.0, 3.0, P.foundation.size[3])
    return height
end
local function wallHalfThickness(pieceId)
    -- Use the modular *attachment* depth, not decorative trims or actual
    -- YDR bounds. V19 snapping must not move when the Asset Forge adds detail.
    local def = P[pieceId] or {}
    local depth = tonumber(def.snapThickness) or 0.32
    return math.min(0.75, math.max(0.05, depth * 0.5))
end
local function deckHalfExtents(pieceId)
    -- T1/T2/T3 all use the exact 3 x 3 m socket grid even if trim extends
    -- beyond a mesh bounding box. This is independent of LOD/polycount.
    return 1.5, 1.5
end
local FLOORS = { floor = true, floor_frame = true }

-- Sockets: where a piece of kind k can sit relative to an existing piece (local x, y, z, extra heading)
-- Resolve persisted legacy/custom piece identifiers to the modular snap family.
local function snapKind(id)
    local v = tostring(id or ''):lower()
    -- V15: 'bs_k_wall' and 'bs_k_floor' must share the old structure/multi-place
    -- behavior, rather than silently falling through as unknown prop IDs.
    -- Door panels, trim and details are NOT structural walls.
    if Building.KenneySnap and Building.KenneySnap.isKenney(v) then
        local family = Building.KenneySnap.family(v)
        if family == 'deck' then return v:find('^bs_k_roof') and 'roof' or 'foundation' end
        if family == 'wall' or family == 'cornerwall' then
            if v:find('doorway',1,true) then return 'wall_doorway' end
            if v:find('window',1,true) then return 'wall_window' end
            return 'wall'
        end
        if family == 'stair' then return 'stairs' end
        if family == 'post' then return 'support_beam' end
        return v
    end
    if v == 'foundation' or v:find('fundament', 1, true) or v:find('foundation', 1, true) then return 'foundation' end
    if v == 'wall_doorway' or v:find('doorframe', 1, true) or v:find('doorway', 1, true) then return 'wall_doorway' end
    if v == 'wall_window' or v:find('windowwall', 1, true) or v:find('window_wall', 1, true) then return 'wall_window' end
    if v:find('fenster', 1, true) or v:find('window', 1, true) then return 'wall_window' end
    if v:find('tuer', 1, true) or v:find('turrahmen', 1, true) or v:find('door', 1, true) then return 'wall_doorway' end
    if v:find('wand', 1, true) then return 'wall' end
    if v == 'wall' or v:match('^wall[_%-]') then return 'wall' end
    if v == 'roof' or v:find('roof', 1, true) or v:find('dach', 1, true) then return 'roof' end
    if v == 'stairs' or v == 'stairs_z' or v:find('stairs', 1, true) or v:find('treppe', 1, true) then return 'stairs' end
    if v == 'ceiling' or v:find('ceiling', 1, true) or v:find('decke', 1, true) then return 'floor' end
    return v
end
-- Per-placement height offset. Foundation retains its existing limits.
local function heightLimits()
    if Place and Place.pieceId and snapKind(Place.pieceId) == 'foundation' then return -1.0, 2.0 end
    return -0.50, 0.50
end
local snapStats = { kind = '-', pieces = 0, nearby = 0, compatible = 0, reason = 'Noch keine Prüfung' }
-- Keep the last Kenney socket for a small hysteresis margin. Without this,
-- pairs(World.pieces) order makes the ghost jump between close corners.
local lastKenneySocket = nil
-- Newly placed structures may reach the client through the server upsert
-- after the next preview frame. Keep a short-lived local snap target until
-- World.pieces receives the authoritative entity.
local pendingSnapPieces = {}
local function snapTargets()
    local out = {}
    for _, r in pairs(World.pieces) do out[#out+1] = r end
    local now = GetGameTimer()
    for i=#pendingSnapPieces,1,-1 do
        local pending = pendingSnapPieces[i]
        local acknowledged = false
        for _, r in pairs(World.pieces) do
            if r.p == pending.p and math.abs(r.x-pending.x)<0.04
                and math.abs(r.y-pending.y)<0.04 and math.abs(r.z-pending.z)<0.04
                and math.abs(((r.h-pending.h+180)%360)-180)<1 then
                acknowledged = true; break
            end
        end
        if acknowledged or now >= pending.expires then
            table.remove(pendingSnapPieces,i)
        else
            out[#out+1] = pending
        end
    end
    return out
end
local function snapshotSnapStats()
    local copy = {}
    for k,v in pairs(snapStats) do copy[k] = v end
    return copy
end
exports('getBuildingSnapDebug', snapshotSnapStats)
local buildTrace = { events = {}, state = {phase='Bereit', lastError='-', enter=false, server='-', preview=false} }
local function traceBuild(step, detail, level)
    local entry = {time=GetGameTimer(), step=tostring(step), detail=tostring(detail or ''), level=level or 'info'}
    table.insert(buildTrace.events, 1, entry)
    if #buildTrace.events > 45 then table.remove(buildTrace.events) end
    buildTrace.state.phase = entry.step
    if level == 'error' then
        buildTrace.state.lastError = entry.detail
        TriggerEvent('bs:admin:propStudioError', entry.step..': '..entry.detail, 'F2 Bausystem')
    end
end
RegisterNetEvent('bs:building:diagnostic', function(step, detail, level)
    traceBuild('SERVER · '..tostring(step), detail, level)
    buildTrace.state.server = tostring(step)..' · '..tostring(detail or '')
end)
exports('getBuildingFullDebug', function()
    return {snap=snapshotSnapStats(), state=buildTrace.state, events=buildTrace.events, active=Place.active, magnet=magneticSnap}
end)


local function socketsOf(r, requestedPieceId, rotationOffset)
    if Building.KenneySnap and (Building.KenneySnap.isKenney(r.p) or Building.KenneySnap.isKenney(requestedPieceId)) then
        return Building.KenneySnap.sockets(r, requestedPieceId, rotationOffset)
    end
    local out = {}
    local function add(kinds, lx, ly, lz, dh)
        local wx, wy = Building.Rotate(lx, ly, r.h)
        out[#out + 1] = { kinds = kinds, x = r.x + wx, y = r.y + wy, z = r.z + lz, h = (r.h + (dh or 0)) % 360 }
    end
    local p = snapKind(r.p)
    if p == 'foundation' then
        local f = { foundation = true }
        local t = foundationTop()
        local halfX, halfY = deckHalfExtents('foundation')
        -- Foundation neighbours remain centre-to-centre on the shared 3 m grid.
        add(f, 3, 0, 0); add(f, -3, 0, 0); add(f, 0, 3, 0); add(f, 0, -3, 0)
        -- Wall centre sits INWARD from the deck edge by half its thickness:
        -- its outward face is flush with the foundation's visible outer edge.
        -- The 0/180/270/90 headings also point each wall's front outward.
        local inset = wallHalfThickness(requestedPieceId)
        add(WALLS, 0, halfY - inset, t, 0)
        add(WALLS, 0, -halfY + inset, t, 180)
        add(WALLS, halfX - inset, 0, t, 270)
        add(WALLS, -halfX + inset, 0, t, 90)
        add({ stairs = true }, 0, 0, t)
        -- Roof and ceiling both cap the SAME foundation module at wall top.
        add({ roof = true, floor = true }, 0, 0, t + 3.0)
        -- Beams attach at the four corners, entirely inside the 3x3 square.
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                add({ support_beam = true }, sx * 1.335, sy * 1.335, t)
            end
        end
    elseif WALLS[p] then
        add(WALLS, 0, 0, 3); add(WALLS, 3, 0, 0); add(WALLS, -3, 0, 0)
        -- A wall sits 1.5m minus half its thickness from the foundation
        -- centre, not 1.5m. Previous +/-1.5 sockets shifted roofs/ceilings
        -- horizontally by 0.16m depending on whether you snapped to the
        -- foundation or the wall (visible in corner/edge connections).
        -- Local negative Y is always inward for our four wall headings.
        local inset = wallHalfThickness(r.p)
        local top = { floor = true, roof = true }
        add(top, 0, -(1.5 - inset), 3) -- THIS foundation module's centre
        add(top, 0, 1.5 + inset, 3)   -- adjacent 3m grid module's centre
        add({ walkway = true }, 0, 0.875, 3); add({ walkway = true }, 0, -0.875, 3)
        if p == 'wall_doorway' then add({ door = true }, 0, 0, 0) end
        if p == 'wall_window' then add({ window = true }, 0, 0, 0.9) end
    elseif p == 'roof' then
        add({ roof = true }, 3, 0, 0); add({ roof = true }, -3, 0, 0)
        add({ roof = true }, 0, 3, 0); add({ roof = true }, 0, -3, 0)
    elseif FLOORS[p] then
        add(FLOORS, 3, 0, 0); add(FLOORS, -3, 0, 0); add(FLOORS, 0, 3, 0); add(FLOORS, 0, -3, 0)
        local halfX, halfY = deckHalfExtents(r.p)
        local _, _, deckHeight = modelExtents(r.p, 3.0, 3.0, 0.2)
        if r.p == 'ceiling' and Building.ModelFor('ceiling') == GetHashKey('bs_ceiling_t1') then
            deckHeight = 0.25
        end
        local inset = wallHalfThickness(requestedPieceId)
        add(WALLS, 0, halfY - inset, deckHeight, 0)
        add(WALLS, 0, -halfY + inset, deckHeight, 180)
        add(WALLS, halfX - inset, 0, deckHeight, 270)
        add(WALLS, -halfX + inset, 0, deckHeight, 90)
        add({ stairs = true }, 0, 0, deckHeight)
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                add({ support_beam = true }, sx * 1.335, sy * 1.335, deckHeight)
            end
        end
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

local function bestSnap(kind, aim, rotationOffset)
    kind = snapKind(kind)
    local isKenney = Building.KenneySnap and Building.KenneySnap.isKenney(Place.pieceId)
    local snapShape = isKenney and Building.KenneySnap.dimensions(Place.pieceId) or nil
    local snapRadius = isKenney and math.min(4.20, math.max(2.35, (snapShape and snapShape.family=='stair') and snapShape.x*0.5+0.45 or 2.35))
        or ((kind == 'foundation') and 2.0 or (WALLS[kind] and 3.0 or (kind == 'roof' and 3.0 or 1.75)))
    local best, bestD = nil, snapRadius
    -- V21.1: For railings, prefer the deck level the builder is standing on.
    -- Camera rays may hit the street beyond an elevated deck; comparing their
    -- ground Z against roof sockets incorrectly attracts the railing downstairs.
    -- Only activate when an actual deck socket is near the player's feet.
    local railDeckLevel = nil
    if isKenney and snapShape and snapShape.family == 'rail' then
        local feetZ = GetEntityCoords(PlayerPedId()).z
        local nearest = 0.85
        for _, deck in ipairs(snapTargets()) do
            local dims = Building.KenneySnap.dimensions(deck.p)
            if dims and dims.family == 'deck' then
                local deckTop = deck.z + ((deck.p == 'foundation' and 0.32) or (deck.p == 'ceiling' and 0.25) or dims.z)
                local dz = math.abs(feetZ - deckTop)
                local dx,dy = aim.x-deck.x, aim.y-deck.y
                if dz < nearest and dx*dx+dy*dy < 36.0 then
                    nearest = dz
                    railDeckLevel = deckTop
                end
            end
        end
    end
    local total, nearby, compatible = 0, 0, 0
    -- Deck-Kollisionen nur einmal vorbereiten. Nicht fuer jeden Socket erneut
    -- alle 100+ Welt-Props durchsuchen (V16-FPS-Fix).
    local blockers = {}
    if isKenney and snapShape and (snapShape.family=='deck' or snapShape.family=='wall' or snapShape.family=='cornerwall') then
        for _, other in ipairs(snapTargets()) do
            local family = Building.KenneySnap.family(other.p)
            if family==snapShape.family then
                local dx,dy=aim.x-other.x,aim.y-other.y
                if dx*dx+dy*dy<100 then blockers[#blockers+1]=other end
            end
        end
    end
    for _, r in ipairs(snapTargets()) do
        total = total + 1
        if #(aim - vector3(r.x, r.y, r.z)) < 9.0 then
            nearby = nearby + 1
            for _, s in ipairs(socketsOf(r, Place.pieceId, rotationOffset)) do
                if s.kinds[kind] or s.kinds[Place.pieceId] then
                    compatible = compatible + 1
                    -- Match sockets horizontally, then enforce a vertical safety limit.
                    -- Roofs and walls are often dragged at ground height before
                    -- their first snap; a full 3D distance would reject them.
                    local dx, dy = aim.x - s.x, aim.y - s.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    local dz = math.abs((railDeckLevel or aim.z) - s.z)
                    local verticalLimit = isKenney and 4.5 or ((kind == 'roof') and 5.0 or (WALLS[kind] and 3.5 or 1.5))
                    if dz > verticalLimit then d = math.huge end
                    if isKenney then d = d + dz * 0.38 end
                    local rawDistance = d
                    if isKenney and lastKenneySocket
                        and math.abs(lastKenneySocket.x-s.x)<0.045
                        and math.abs(lastKenneySocket.y-s.y)<0.045
                        and math.abs(lastKenneySocket.z-s.z)<0.045
                        and math.abs(math.cos(math.rad(lastKenneySocket.h-s.h))-1)<0.002 then
                        d = d - 0.18 -- 18cm anti-flicker bonus, NEVER bypass the snap radius
                    end
                    local limit = snapRadius
                    if rawDistance < limit and d < bestD then
                        -- Kein gruenes "Anschluss gefunden" bei physischer
                        -- Ueberlappung von Bodenplatten. Pruefung aller bereits
                        -- platzierten Kenney-Bodenobjekte, nicht nur des Elternteils.
                        local candidate = {x=s.x,y=s.y,z=s.z,h=s.h}
                        local blocked = false
                        if isKenney and s.requiresCoverage and not Building.KenneySnap.covered(s, Place.pieceId, World.pieces) then
                            blocked=true
                        end
                        -- ALPHA-Z V29: Nur fuer diese Komforttreppe beide
                        -- Anschluesse pruefen. V28-Dachueberstand wird NICHT benutzt.
                        -- Anderen Kenney-/T1-Bauteilen niemals im Weg stehen.
                        if isKenney and not blocked
                            and Place.pieceId == 'bs_k_stairs_az_straight_wide_t1'
                            and Building.KenneySnap.azStairSupported
                            and not Building.KenneySnap.azStairSupported(candidate, World.pieces) then
                            blocked=true
                        end
                        if isKenney and not blocked then
                            for _,other in ipairs(blockers) do
                                if Building.KenneySnap.overlaps(candidate, Place.pieceId, other, other.p) then
                                    blocked=true; break
                                end
                            end
                        end
                        if not blocked then best,bestD=s,d end
                    end
                end
            end
        end
    end
    lastKenneySocket = (best and isKenney) and {x=best.x,y=best.y,z=best.z,h=best.h} or nil
    snapStats = {kind = kind, pieces = total, nearby = nearby, compatible = compatible,
        reason = best and 'SNAP GEFUNDEN' or (compatible == 0 and 'Keine kompatiblen Anschlüsse' or 'Außerhalb des Fangradius'),
        result = best and {x=best.x,y=best.y,z=best.z,h=best.h} or nil,
        aim = {x=aim.x,y=aim.y,z=aim.z}}
    return best
end

-- Cursor ray: NUI pointer controls the world target without moving the GTA camera.
local function aimPoint(ignore)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local forward = vector3(-math.sin(rz)*math.cos(rx), math.cos(rz)*math.cos(rx), math.sin(rx))
    local right = vector3(math.cos(rz), math.sin(rz), 0.0)
    local up = vector3(math.sin(rz)*math.sin(rx), -math.cos(rz)*math.sin(rx), math.cos(rx))
    local sw, sh = GetActiveScreenResolution()
    local mx, my = GetNuiCursorPosition()
    if altWalk then mx, my = sw * 0.5, sh * 0.5 end
    local nx = (2.0*mx/math.max(sw,1) - 1.0)
    local ny = (1.0 - 2.0*my/math.max(sh,1))
    local spread = math.tan(math.rad(GetGameplayCamFov())*0.5)
    local dir = forward + right*(nx*spread*sw/math.max(sh,1)) + up*(ny*spread)
    dir = dir / #dir
    local to = cam + dir * (S.placeDistance + 6.0)
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x,cam.y,cam.z,to.x,to.y,to.z,1 | 16,ignore,4)
    local _, hit, at = GetShapeTestResult(h)
    return hit == 1 and at or to
end

-- For small ground-only objects, use the surface directly below the aim point.
-- This avoids floating when the camera ray misses and returns a point in mid-air.
-- Other pieces retain their original placement (including elevated floors).
local function groundPlacement(pieceId, aim)
    local rule = Building.PlacementRule(pieceId)
    if not rule.ground then return aim, true end
    -- Do not accept a camera ray endpoint floating in mid-air.
    local probe = StartExpensiveSynchronousShapeTestLosProbe(
        aim.x, aim.y, aim.z + 2.5, aim.x, aim.y, aim.z - 8.0,
        1 | 16, PlayerPedId(), 4)
    local _, hit, at = GetShapeTestResult(probe)
    if hit == 1 and math.abs(aim.z - at.z) < 3.0 then
        return vector3(aim.x, aim.y, at.z), true
    end
    return aim, false
end

-- V20: A utility needs a real horizontal support surface, regardless of free placement.
-- Check five underside points. Decorative props and structural walls must not
-- count as a floor merely because the centre ray happens to hit them.
local function utilitySupport(pieceId, at, heading, ghost)
    local def = P[pieceId]
    if not def or def.cat ~= 'utility' then return true end
    local w = math.max(0.20, tonumber(def.size and def.size[1]) or 1.0)
    local depth = math.max(0.20, tonumber(def.size and def.size[2]) or 1.0)
    local c, sn = math.cos(math.rad(heading)), math.sin(math.rad(heading))
    local points = {{0,0},{-0.35,-0.35},{-0.35,0.35},{0.35,-0.35},{0.35,0.35}}
    local supported = 0
    for _, q in ipairs(points) do
        local lx, ly = q[1]*w, q[2]*depth
        local px, py = at.x + lx*c - ly*sn, at.y + lx*sn + ly*c
        local ray = StartExpensiveSynchronousShapeTestLosProbe(
            px,py,at.z+0.35,px,py,at.z-0.65,1 | 16,ghost or PlayerPedId(),4)
        local _, hit, surface, normal = GetShapeTestResult(ray)
        -- Near-horizontal contact at the actual underside; no floating and
        -- no using the vertical side of a wall as an apparent support.
        if hit == 1 and surface and normal and normal.z >= 0.75
            and math.abs(surface.z-at.z) <= 0.18 then
            supported = supported + 1
        end
    end
    return supported >= 4
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

-- Never permit intentional placement through players, NPCs or vehicles.
local function occupiedByEntity(d, x, y, z)
    local radius = math.max(1.0, math.min(3.0, math.max(d.size[1], d.size[2]) * 0.45))
    local center = vector3(x,y,z)
    for _, entity in ipairs(GetGamePool('CPed')) do
        if entity ~= PlayerPedId() and DoesEntityExist(entity) and #(GetEntityCoords(entity)-center) < radius then return true end
    end
    for _, entity in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(entity) and #(GetEntityCoords(entity)-center) < radius + 1.0 then return true end
    end
    return false
end

local function hint(state) SendNUIMessage({ action = 'hint', state = state }) end
local function closePlacementCursor()
    overlayCursor = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end
RegisterNUICallback('placementAction', function(data, cb)
    if Place.active then
        local action = tostring(data and data.action or '')
        if action == 'rotate' then placementInput.rotate = true
        elseif action == 'place' then placementInput.place = true
        elseif action == 'cancel' then placementInput.cancel = true
        elseif action == 'walk' then
            altWalk = not altWalk
            walkPlaceArmed = false
            walkCancelArmed = false
            SetNuiFocus(not altWalk, not altWalk)
            SetNuiFocusKeepInput(false)
        elseif action == 'magnet' then placementInput.magnet = true
        elseif action == 'reset' then placementInput.reset = true
        elseif action == 'wheel' then
            local delta = tonumber(data.delta) or 0
            local step = data.fine and 1 or 5
            placementInput.wheel = math.max(-180, math.min(180, (placementInput.wheel or 0) + (delta > 0 and step or delta < 0 and -step or 0))) end
    end
    cb({ok=true})
end)
RegisterNUICallback('placementCollisionDecision', function(data, cb)
    if collisionPending then collisionDecision = data and data.accept == true end
    cb({ok=true})
end)

local function confirmRiskyPlacement(reason)
    collisionPending = true
    collisionDecision = nil
    -- Even if ALT walk mode was active, the dialog must remain clickable.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({action='placementCollisionPrompt', visible=true,
        text=reason or 'Hier steht möglicherweise bereits etwas. Willst du das wirklich hier platzieren?'})
    local deadline = GetGameTimer() + 30000
    while collisionDecision == nil and GetGameTimer() < deadline and Place.active do Wait(0) end
    local accepted = collisionDecision == true and Place.active
    collisionPending, collisionDecision = false, nil
    SendNUIMessage({action='placementCollisionPrompt', visible=false})
    if Place.active then
        SetNuiFocus(not altWalk, not altWalk)
        SetNuiFocusKeepInput(false)
    end
    return accepted
end

-- One height controller for every F2 placement (modular and ordinary props).
local function adjustPlacementHeight(op, fine)
    if not Place.active then return end
    local lo, hi = heightLimits()
    local step = fine and 0.01 or 0.10
    if op == 'reset' then
        foundationHeight = 0.0
    elseif op == 'up' or op == 'down' then
        local direction = op == 'up' and 1 or -1
        local nextHeight = math.floor((foundationHeight + direction * step) * 100 + 0.5) / 100
        foundationHeight = math.max(lo, math.min(hi, nextHeight))
    else
        return
    end
    traceBuild('Bauhöhe', ('%.2f m'):format(foundationHeight))
end
RegisterNUICallback('placementHeight', function(data, cb)
    if Place.active then
        adjustPlacementHeight(tostring(data and data.op or ''), data and data.fine == true)
    end
    cb({ok=true, height=foundationHeight})
end)
-- Key mappings are active only while placing; otherwise they do nothing.
-- PLUS/MINUS are the primary keys, with PAGEUP/PAGEDOWN as fallbacks.
RegisterCommand('+bs_height_up', function()
    adjustPlacementHeight('up', IsControlPressed(0,21) or IsDisabledControlPressed(0,21))
end, false)
RegisterCommand('-bs_height_up', function() end, false)
RegisterCommand('+bs_height_down', function()
    adjustPlacementHeight('down', IsControlPressed(0,21) or IsDisabledControlPressed(0,21))
end, false)
RegisterCommand('-bs_height_down', function() end, false)
RegisterKeyMapping('+bs_height_up', 'BS19 Bauhöhe + (nur beim Platzieren)', 'keyboard', 'PLUS')
RegisterKeyMapping('+bs_height_down', 'BS19 Bauhöhe - (nur beim Platzieren)', 'keyboard', 'MINUS')
RegisterNUICallback('placementCursorClose', function(_, cb) placementInput.cancel=true; cb({ok=true}) end)

-- F2-only Gizmo adapter. F10 / prop studio / bs_gizmo remain untouched.
RegisterCommand('buildmagnet', function()
    magneticSnap = not magneticSnap
    traceBuild("Snapping umgeschaltet", tostring(magneticSnap))
    Building.Notify('info', 'Snapping: ' .. (magneticSnap and 'AN' or 'AUS'))
end, false)

-- Standalone survival placement: F2 does not start or modify bs_gizmo.
-- F10 retains the original gizmo and its independent editor.
local function drawSocketMarker(x, y, z, selected)
    DrawMarker(28, x, y, z + 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        selected and 0.048 or 0.032, selected and 0.048 or 0.032, selected and 0.048 or 0.032,
        selected and 60 or 90, selected and 160 or 180, selected and 255 or 145, selected and 115 or 60,
        false, false, 2, false, nil, nil, false)
end

-- Preview-only oriented bounding box for regular props. Uses the model's
-- local-space bounds and the actual aligned ghost transform (F10 offsets included).
-- No collision, snapping or placement rules are changed by these guide lines.
local function drawPropBounds(entity, modelHash, canPlace)
    local mn, mx = GetModelDimensions(modelHash)
    if not mn or not mx then return end
    local pad = 0.02
    local loX, loY, loZ = mn.x-pad, mn.y-pad, mn.z-pad
    local hiX, hiY, hiZ = mx.x+pad, mx.y+pad, mx.z+pad
    local corners = {
        GetOffsetFromEntityInWorldCoords(entity, loX, loY, loZ),
        GetOffsetFromEntityInWorldCoords(entity, hiX, loY, loZ),
        GetOffsetFromEntityInWorldCoords(entity, hiX, hiY, loZ),
        GetOffsetFromEntityInWorldCoords(entity, loX, hiY, loZ),
        GetOffsetFromEntityInWorldCoords(entity, loX, loY, hiZ),
        GetOffsetFromEntityInWorldCoords(entity, hiX, loY, hiZ),
        GetOffsetFromEntityInWorldCoords(entity, hiX, hiY, hiZ),
        GetOffsetFromEntityInWorldCoords(entity, loX, hiY, hiZ),
    }
    local r, g, b = 65, 215, 110
    if not canPlace then r, g, b = 240, 65, 65 end
    local edges = {{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
    for _, edge in ipairs(edges) do
        local a, z = corners[edge[1]], corners[edge[2]]
        DrawLine(a.x, a.y, a.z, z.x, z.y, z.z, r, g, b, 145)
    end
end

local function drawNearbySockets(kind, aim, selected, rotationOffset)
    if not magneticSnap then return end
    kind = snapKind(kind)
    for _, r in pairs(World.pieces) do
        if #(aim - vector3(r.x, r.y, r.z)) < 9.0 then
            for _, s in ipairs(socketsOf(r, Place.pieceId, rotationOffset)) do
                if s.kinds[kind] or s.kinds[Place.pieceId] then
                    local distance = #(vector3(s.x, s.y, s.z) - aim)
                    if distance < 7.0 and (not s.requiresCoverage or Building.KenneySnap.covered(s, Place.pieceId, World.pieces)) then
                        local active = selected and math.abs(selected.x-s.x)<0.03 and math.abs(selected.y-s.y)<0.03 and math.abs(selected.z-s.z)<0.03
                        drawSocketMarker(s.x, s.y, s.z, active)
                    end
                end
            end
        end
    end
end

function Building.StartPlacing(pieceId)
    local d = P[pieceId]
    if not d or Place.active then return {ok=false} end
    Place.active = true
    altWalk = false
    altToggleArmed = false
    walkPlaceArmed = true
    walkCancelArmed = true
    Place.pieceId = pieceId
    lastKenneySocket = nil
    foundationHeight = 0.0
    placementInput = {rotate=false,place=false,cancel=false,magnet=false,wheel=0,reset=false}
    overlayCursor = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    buildTrace.state.enter=false
    buildTrace.state.preview=false
    buildTrace.state.server='-'
    traceBuild('F2 Survival-Placement gestartet', tostring(pieceId))
    CreateThread(function()
        local ghost
        local ok, err = pcall(function()
            local hash = Building.ModelFor(pieceId)
            if not hash or not Building.LoadModel(hash) then
                traceBuild('Modell laden', tostring(pieceId), 'error'); return
            end
            local ped = PlayerPedId()
            local start = GetEntityCoords(ped)
            ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            if not DoesEntityExist(ghost) then
                traceBuild('Vorschau erstellen', tostring(pieceId), 'error'); return
            end
            SetEntityCollision(ghost, false, false)
            -- World props are frozen BEFORE Align. Use the same entity state for
            -- the preview: unfrozen objects may be moved by GTA physics between
            -- the two native coordinate writes in Building.Align.
            FreezeEntityPosition(ghost, true)
            SetEntityAlpha(ghost, 175, false)
            SetEntityInvincible(ghost, true)
            local heading = GetEntityHeading(ped)
            -- A snap socket provides a base heading. Keep the player's rotation
            -- separately: otherwise the socket overwrites R / mouse wheel every frame.
            local snapRotateOffset = 0.0
            local wasSnapped = false
            local flipped = false
            local currentHash = hash
            local finalPlacement
            local validGround = true
            local lastSnapKey = ''
            traceBuild('Vorschau erstellt', tostring(pieceId))
            SendNUIMessage({action='survivalOverlay', visible=true, label=(d.label or pieceId), foundation=(snapKind(pieceId)=='foundation')})
            while Place.active do
                Wait(0)
                -- GTA gameplay is disabled only while an actual piece is being positioned.
                DisableAllControlActions(0)
                DisableAllControlActions(1)
                DisableAllControlActions(2)
                if altWalk then
                    -- ALT is a toggle. While NUI focus is released GTA receives ALT.
                    -- Require a fresh key press, not the key held during activation.
                    if not altToggleArmed then
                        if not IsDisabledControlPressed(0, 19) then altToggleArmed = true end
                    elseif IsDisabledControlJustPressed(0, 19) then
                        altWalk = false
                        altToggleArmed = false
                        SetNuiFocus(true, true)
                        SetNuiFocusKeepInput(false)
                    end
                    if altWalk then
                        -- NUI has no keyboard focus in walk mode. Read E and ESC directly
                        -- from disabled GTA controls; require a release between actions.
                        if not IsDisabledControlPressed(0, 38) then walkPlaceArmed = true end
                        if walkPlaceArmed and IsDisabledControlJustPressed(0, 38) then
                            placementInput.place = true
                            walkPlaceArmed = false
                        end
                        if not IsDisabledControlPressed(0, 200) and not IsDisabledControlPressed(0, 322) then walkCancelArmed = true end
                        -- Right mouse button also returns from the ghost preview to F2
                        -- when ALT walk mode has released NUI focus.
                        if IsDisabledControlJustPressed(0, 25) then
                            placementInput.cancel = true
                        end
                        if walkCancelArmed and (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322)) then
                            placementInput.cancel = true
                            walkCancelArmed = false
                        end
                        -- V7: build controls remain available with NUI focus released.
                        -- Read disabled controls directly; never enable GTA actions for R/X/E.
                        if IsDisabledControlJustPressed(0, 45) then -- INPUT_RELOAD / R
                            placementInput.rotate = true
                        end
                        if IsDisabledControlJustPressed(0, 178) then -- INPUT_CELLPHONE_OPTION / DELETE
                            placementInput.reset = true
                        end
                        if IsDisabledControlJustPressed(0, 73) then -- INPUT_VEH_DUCK / X
                            placementInput.magnet = true
                        end
                        local fineRotate = IsDisabledControlPressed(0, 21) -- SHIFT
                        local stepRotate = fineRotate and 1 or 5
                        if IsDisabledControlJustPressed(0, 15) then -- wheel up
                            placementInput.wheel = (placementInput.wheel or 0) + stepRotate
                        end
                        if IsDisabledControlJustPressed(0, 14) then -- wheel down
                            placementInput.wheel = (placementInput.wheel or 0) - stepRotate
                        end
                        -- Height uses the same mapped +/- commands in both modes.
                        -- Voice key mappings require a separate guard in their resource.
                        -- Walking and camera only; sprint/jump/attack remain blocked.
                        for _, control in ipairs({1,2,30,31,32,33,34,35}) do
                            EnableControlAction(0, control, true)
                            EnableControlAction(1, control, true)
                            EnableControlAction(2, control, true)
                        end
                    end
                else
                    altToggleArmed = false
                end
                if placementInput.reset then
                    placementInput.reset = false
                    heading = GetEntityHeading(ped)
                    snapRotateOffset = 0.0
                    lastKenneySocket = nil
                    wasSnapped = false
                    flipped = false
                    foundationHeight = 0.0
                    magneticSnap = true
                    placementInput.wheel = 0
                    placementInput.rotate = false
                    placementInput.magnet = false
                    if altWalk then
                        altWalk = false
                        altToggleArmed = false
                        SetNuiFocus(true, true)
                        SetNuiFocusKeepInput(false)
                    end
                    traceBuild('Vorschau zurückgesetzt', tostring(pieceId))
                end
                if placementInput.cancel then
                    traceBuild('Platzierung abgebrochen', tostring(pieceId))
                    break
                end
                if placementInput.rotate then
                    placementInput.rotate = false
                    local family = snapKind(pieceId)
                    if WALLS[family] and not (Building.KenneySnap and Building.KenneySnap.isKenney(pieceId)) and magneticSnap and wasSnapped then
                        -- Legacy T1 V19: R flips the face without breaking its socket.
                        -- Kenney uses rotated bounding geometry and must rotate
                        -- the whole 90 degrees (R) like other modular pieces.
                        flipped = not flipped
                    else
                        heading = (heading + 90) % 360
                        snapRotateOffset = (snapRotateOffset + 90) % 360
                    end
                end
                if placementInput.wheel ~= 0 then
                    local delta = placementInput.wheel
                    heading = (heading + delta) % 360
                    snapRotateOffset = (snapRotateOffset + delta) % 360
                    placementInput.wheel = 0
                end
                if placementInput.magnet then
                    placementInput.magnet = false
                    magneticSnap = not magneticSnap
                    lastKenneySocket = nil
                    Building.Notify('info','Snapping: '..(magneticSnap and 'AN' or 'AUS'))
                end
                -- F10 can update a prop while F2 is already open. Recreate preview if model changes.
                d = P[pieceId] or d
                local latestHash = Building.ModelFor(pieceId)
                if latestHash and latestHash ~= currentHash and Building.LoadModel(latestHash) then
                    if DoesEntityExist(ghost) then DeleteEntity(ghost) end
                    ghost = CreateObjectNoOffset(latestHash, start.x,start.y,start.z,false,false,false)
                    SetEntityCollision(ghost,false,false)
                    FreezeEntityPosition(ghost,true)
                    SetEntityAlpha(ghost,175,false)
                    SetEntityInvincible(ghost,true)
                    currentHash = latestHash
                    SetModelAsNoLongerNeeded(latestHash)
                end
                local aim = aimPoint(ghost)
                -- Clamp free placement to the same distance accepted by server checks.
                local me = GetEntityCoords(ped)
                local delta = aim - me
                local dist = #delta
                if dist > S.placeDistance - 0.4 then
                    aim = me + delta * ((S.placeDistance - 0.4) / dist)
                end
                local socket = magneticSnap and bestSnap(pieceId, aim, snapRotateOffset) or nil
                wasSnapped = socket ~= nil
                validGround = true
                if not socket then
                    aim, validGround = groundPlacement(pieceId, aim)
                    -- Apply the same height offset to every freely placed object.
                    aim = vector3(aim.x, aim.y, aim.z + foundationHeight)
                end
                local x, y, z = aim.x, aim.y, aim.z
                local h = heading
                if socket then
                    x,y,z = socket.x,socket.y,socket.z
                    -- Keep the socket position, rotate the *model* relative to
                    -- its base heading. Applied to preview AND saved placement.
                    h = socket.oriented and socket.h or (socket.h + snapRotateOffset) % 360
                    z = z + foundationHeight
                end
                if flipped then h = (h + 180) % 360 end
                -- Support validation is independent of magnetic snapping.
                -- Do not let a utility inherit a "valid" status from a socket.
                if d.cat == 'utility' then
                    validGround = validGround and utilitySupport(pieceId, vector3(x,y,z), h, ghost)
                end
                finalPlacement = {x=x,y=y,z=z,h=h,snapped=socket ~= nil}
                SetEntityAlpha(ghost, validGround and 175 or 115, false)
                -- A restrained coloured outline gives the transparent ghost a green/red
                -- preview tint without changing its original material textures.
                SetEntityDrawOutlineColor(validGround and 65 or 235, validGround and 195 or 65, validGround and 95 or 65, 110)
                SetEntityDrawOutlineShader(1)
                SetEntityDrawOutline(ghost, true)
                if not validGround then
                    DrawMarker(1,x,y,z+0.12,0,0,0,0,0,0,0.75,0.75,0.12,240,45,45,170,false,false,2,false,nil,nil,false)
                end
                -- Same Align routine, F10 studio settings and frozen transform
                -- as the final world object. Never add preview-only Z offsets.
                Building.Align(ghost, x, y, z, h, d.pitch or 0, pieceId)
                -- The preview's rendered coordinates are the result of the
                -- identical Align call used when the server-spawned prop appears.
                -- V6: native GTA chevron marker instead of DrawPoly triangles.
                -- Marker type 2 is rendered by the engine with explicit RGB colour.
                -- Keep it slightly outside the model face to avoid z-fighting.
                if BUILD_PARTS[snapKind(pieceId)] then
                    local mn, mx = GetModelDimensions(currentHash)
                    local gp = GetEntityCoords(ghost)
                    local height = math.max(0.25, mx.z - mn.z)
                    local modelHeading = GetEntityHeading(ghost)
                    local headingRad = math.rad(modelHeading)
                    local fx, fy = -math.sin(headingRad), math.cos(headingRad)
                    local front = math.max(math.abs(mn.y), math.abs(mx.y)) + 0.20
                    local markerX = gp.x + fx * front
                    local markerY = gp.y + fy * front
                    local markerZ = gp.z + mn.z + height * 0.20
                    -- V15: rotate the existing chevron 90 degrees around its
                    -- horizontal axis. Use explicit Euler rotation: a nonzero dir
                    -- vector would override the marker's rotX/rotY/rotZ fields.
                    DrawMarker(2, markerX, markerY, markerZ,
                        0.0, 0.0, 0.0,
                        90.0, 0.0, (modelHeading + 90.0) % 360.0,
                        0.22, 0.22, 0.22, 30, 255, 65, 235,
                        false, false, 2, false, nil, nil, false)
                else
                    -- Regular survival props: a thin, rotated wireframe box only
                    -- while previewing. Red when ground placement is invalid.
                    drawPropBounds(ghost, currentHash, validGround)
                end
                buildTrace.state.preview=true
                buildTrace.state.previewPosition=finalPlacement
                buildTrace.state.snapped=socket ~= nil
                if socket then
                    local key = ('%.2f/%.2f/%.2f'):format(x,y,z)
                    if key ~= lastSnapKey then traceBuild('Live-Snap angewendet', key); lastSnapKey=key end
                else
                    lastSnapKey=''
                end
                drawNearbySockets(pieceId, aim, socket, snapRotateOffset)
                if GetGameTimer() % 180 < 20 then
                    SendNUIMessage({action='survivalState', snapped=socket~=nil, magnet=magneticSnap,
                        height=foundationHeight, walking=altWalk, cursor=overlayCursor, foundation=snapKind(pieceId)=='foundation'})
                end
                if placementInput.place then
                    placementInput.place = false
                    buildTrace.state.enter=true
                    traceBuild('E erkannt', tostring(pieceId))
                    local pos = vector3(x,y,z)
                    -- Map ground probes may miss player-built floors. Explicit
                    -- confirmation also covers those cases; never silently place.
                    local surfaceConfirmed = false
                    if not validGround and d.cat ~= 'utility' then
                        surfaceConfirmed = confirmRiskyPlacement(
                            'Der Untergrund wurde nicht sicher erkannt. Willst du das wirklich hier platzieren?')
                        traceBuild('Unsicherer Untergrund bestätigt', tostring(surfaceConfirmed))
                    end
                    if not validGround and not surfaceConfirmed then
                        traceBuild('Bodenprüfung', 'Keine tragfähige Standfläche', 'error')
                        Building.Notify('warn', 'Dieses Objekt benötigt einen festen Boden oder eine Bodenplatte.')
                    elseif #(GetEntityCoords(ped)-pos) > S.placeDistance then
                        traceBuild('Distanzprüfung', 'Zu weit entfernt', 'error')
                        Building.Notify('warn', L('build.err.far'))
                    elseif d.attach and not socket then
                        traceBuild('Anschlussprüfung', 'Kein gültiger Snap-Anschluss', 'error')
                        Building.Notify('warn', L('build.err.attach'))
                    elseif not d.flag and occupiedByEntity(d,x,y,z) then
                        Building.Notify('warn', 'Spieler oder Fahrzeug im Baubereich')
                    elseif nearLoot(pos) then
                        traceBuild('Loot-Abstand', 'Zu nah an Loot', 'error')
                        Building.Notify('warn', L('build.err.loot'))
                    else
                        -- Ask the server first. A confirmed "already occupied"
                        -- condition is a deliberately permitted SOFT collision.
                        -- Ownership, flags, faction, materials and distance remain enforced.
                        local check = BSB.Await('build:check', 10000, pieceId, {x=x,y=y,z=z,h=h})
                        local confirmed = surfaceConfirmed
                        local aborted = false
                        if not check or not check.ok then
                            if check and check.overrideAllowed then
                                if not confirmed then confirmed = confirmRiskyPlacement('Hier steht bereits etwas. Willst du das wirklich hier platzieren?') end
                                aborted = not confirmed
                                if aborted then traceBuild('Kollision abgebrochen', tostring(pieceId), 'info') end
                            else
                                local reason = tostring(check and check.error or ('Server antwortet nicht auf Baupruefung ('..tostring(pieceId)..')'))
                                traceBuild('Serverprüfung abgelehnt', reason, 'error')
                                Building.Notify('warn', reason)
                                aborted = true
                            end
                        end
                        -- GTA map collisions (separate to the BS19 server occupancy
                        -- check) use the SAME dialog, never a native Windows popup.
                        if not aborted and not confirmed and not d.flag and clips(d,x,y,z,h,ghost) then
                            confirmed = confirmRiskyPlacement('Das Bauteil berührt möglicherweise ein anderes Objekt. Willst du es wirklich hier platzieren?')
                            aborted = not confirmed
                        end
                        if not aborted then
                            local payload = {x=x,y=y,z=z,h=h,confirmOverlap=confirmed}
                            traceBuild('Platzierung gesendet', tostring(pieceId))
                            local res = BSB.Await('build:place', 15000, pieceId, payload)
                            if res and res.ok then
                                traceBuild('Platzierung bestätigt', tostring(pieceId))
                                if Building.KenneySnap and Building.KenneySnap.isKenney(pieceId) then
                                    pendingSnapPieces[#pendingSnapPieces+1] = {
                                        p=pieceId,x=x,y=y,z=z,h=h,
                                        expires=GetGameTimer()+12000
                                    }
                                    -- A new piece must be available as a snap target
                                    -- immediately, without returning to the F2 menu.
                                    lastKenneySocket=nil
                                end
                                PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                                Building.Notify('success', d.flag and L('build.flag_placed') or L('build.frame_placed'))
                                if not BUILD_PARTS[snapKind(pieceId)] then break end
                                placementInput.place = false
                            else
                                local reason = tostring(res and res.error or ('Server antwortet nicht auf Platzierung ('..tostring(pieceId)..')'))
                                traceBuild('Platzierung abgelehnt', reason, 'error')
                                Building.Notify('warn', reason)
                            end
                        end
                    end
                end
            end
        end)
        collisionPending = false
        collisionDecision = nil
        SendNUIMessage({action='placementCollisionPrompt', visible=false})
        altWalk = false
        closePlacementCursor()
        SendNUIMessage({action='survivalOverlay', visible=false})
        Place.pieceId = nil
        if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
        hint(nil)
        Place.active=false
        if ok and openWheel then CreateThread(function() Wait(100); openWheel() end) end
        if not ok then
            traceBuild('Lua Ausnahme', tostring(err), 'error')
            print('[bs_building] Survival placement error: '..tostring(err))
            Building.Notify('warn', 'Platzierung fehlgeschlagen (Details im F10-Debugger).')
        end
    end)
    return {ok=true}
end
exports('StartPlacing', function(id) return Building.StartPlacing(id) end)
exports('IsPlacing', function() return Place.active end)

-- Build wheel (F2)

local wheelOpen = false
openWheel = function()
    if wheelOpen or Place.active then return end
    local res = BSB.Await('build:catalogue', 8000)
    if not res or not res.ok then return end
    if res.mode == 'claim' and not res.faction then return Building.Notify('warn', L('build.err.no_faction')) end
    wheelOpen = true
    TriggerEvent('bs:ui:opened', 'building')
    SetNuiFocus(true, true)
    -- Check real streamed model availability on the client before displaying F2.
    -- Unlike the historical woodpile fallback, missing Kenney assets are visibly marked.
    for _, item in ipairs(res.pieces or {}) do
        if Building.KenneySnap and Building.KenneySnap.isKenney(item.id) then
            local model = P[item.id] and P[item.id].models and P[item.id].models[1]
            local hash = model and GetHashKey(model)
            item.modelAvailable = hash and IsModelInCdimage(hash) and IsModelValid(hash) or false
            item.blurb = (item.modelAvailable and 'Kenney-Bauteil' or 'MODELL FEHLT - bs_building_assets prüfen')
        end
    end
    SendNUIMessage({ action = 'wheel', data = res, cats = res.categories or Building.Categories })
end
local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wheelClose' })
    TriggerEvent('bs:ui:closed', 'building')
end

RegisterNUICallback('wheelPick', function(data, cb)
    closeWheel()
    cb({ ok = true })
    if data and P[data.id] and not P[data.id].disabled then
        local model = Building.ModelFor(data.id)
        if not model then Building.Notify('error', 'Bauteilmodell fehlt: '..tostring(data.id)..' · bs_building_assets prüfen')
        else Building.StartPlacing(data.id) end
    end
end)
RegisterNUICallback('wheelClose', function(_, cb) closeWheel(); cb({ ok = true }) end)
AddEventHandler('bs:ui:opened', function(what) if what ~= 'building' then closeWheel() end end)

-- Same command name as before so old F2 binds still work.
RegisterCommand('+factionbuild', function() CreateThread(openWheel) end, false)
RegisterCommand('-factionbuild', function() end, false)
RegisterKeyMapping('+factionbuild', L('keymap.build_wheel'), 'keyboard', 'F2')
