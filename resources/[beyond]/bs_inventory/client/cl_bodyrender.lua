-- bs_inventory - body status snapshots plus injury/drug/booster tracking for Field Medical.
-- Snapshots: four frozen local clones (front, right, back, left) in the sky, lit, in front of a flat magenta wall, filmed by a scripted camera. The page grabs the game frame via the NUI game-view texture, keys out the magenta and shows the figures as images. Captured unarmed, once per session (REFRESH redoes it).

local CFG = Inventory.BodyRender or {}

local Body = { sig = nil, busy = false, stale = true }
local ANGLES = { 180.0, 270.0, 0.0, 90.0 }   -- front, right side, back, left side
local POSE_DICT, POSE_ANIM = 'mp_character_creation@customise@male_a', 'loop'

local function dbg(msg)
    if CFG.debug then print('[bs_inventory] body: ' .. msg) end
end

local function available()
    if CFG.enabled == false then return false end
    if CFG.captureMode == 'screenshot-basic' then
        return GetResourceState('screenshot-basic') == 'started'
    end
    return true   -- 'internal': the page does the grab
end

-- page answers 'bodyGrab' once it has read the frame
local grabReply = nil
RegisterNUICallback('bodyGrabbed', function(data, cb)
    grabReply = data or {}
    cb({ ok = true })
end)

-- outfit + weapon fingerprint, recapture only when it changes
local function signature(ped)
    local t = { tostring(GetEntityModel(ped)) }
    for c = 0, 11 do t[#t + 1] = GetPedDrawableVariation(ped, c) .. ':' .. GetPedTextureVariation(ped, c) end
    for p = 0, 7 do t[#t + 1] = GetPedPropIndex(ped, p, 0) .. ':' .. GetPedPropTextureIndex(ped, p) end
    return table.concat(t, ',')
end

local function killAll(list)
    for _, c in ipairs(list or {}) do
        if DoesEntityExist(c) then
            SetEntityAsMissionEntity(c, true, true)
            DeleteEntity(c)
        end
    end
end

local function makeClone(src, x, y, z, heading)
    Crumb('bodycap', 'clone src=%s', tostring(src))
    local c = ClonePed(src, false, false, true)
    if not c or c == 0 then return nil end
    SetEntityAsMissionEntity(c, true, true)
    local st = Entity(c).state
    if st then st:set('bsProtected', true, false) end   -- bs_world's sweep skips it
    SetEntityCollision(c, false, false)
    SetEntityInvincible(c, true)
    SetBlockingOfNonTemporaryEvents(c, true)
    SetPedCanRagdoll(c, false)
    SetEntityCoordsNoOffset(c, x, y, z, false, false, false)
    SetEntityHeading(c, heading)
    FreezeEntityPosition(c, true)
    -- always unarmed, weapon poses looked odd
    RemoveAllPedWeapons(c, true)
    SetCurrentPedWeapon(c, `WEAPON_UNARMED`, true)
    if HasAnimDictLoaded(POSE_DICT) then
        TaskPlayAnim(c, POSE_DICT, POSE_ANIM, 8.0, 8.0, -1, 1, 0.0, false, false, false)
    end
    SetEntityVisible(c, true, false)
    return c
end

-- both windings so it shows whichever way the engine culls
local function quad(a, b, c, d, col)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, col[1], col[2], col[3], 255)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, col[1], col[2], col[3], 255)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, col[1], col[2], col[3], 255)
    DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, col[1], col[2], col[3], 255)
end

-- Takes the four snapshots. Yields; call from a thread. Returns true when a screenshot was sent to the page.
function Body.Capture()
    if Body.busy or not available() then return false end
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then return false end
    Body.busy = true

    RequestAnimDict(POSE_DICT)
    local t = GetGameTimer() + 500
    while not HasAnimDictLoaded(POSE_DICT) and GetGameTimer() < t do Wait(0) end

    local at = GetEntityCoords(ped)
    local bx, by, bz = at.x, at.y, at.z + (CFG.height or 400.0)
    local D, fov = CFG.distance or 8.0, CFG.fov or 22.0
    -- frame width at the clones, so each gets a quarter of it
    local W = 2.0 * D * math.tan(math.rad(fov) / 2.0) * GetAspectRatio(false)
    local spacing = CFG.spacing or (W / 4.0)

    local clones = {}
    for i, h in ipairs(ANGLES) do
        local c = makeClone(ped, bx + (i - 2.5) * spacing, by, bz, h)
        if c then clones[#clones + 1] = c end
    end
    if #clones < 4 then killAll(clones); Body.busy = false; return false end

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', bx, by - D, bz - 0.05, 0.0, 0.0, 0.0, fov, false, 0)
    local pedCam = BSInvPedCam and BSInvPedCam.active and BSInvPedCam.handle or nil
    SetCamActive(cam, true)
    if not pedCam then RenderScriptCams(true, false, 0, true, true) end

    local col = CFG.chroma or { 255, 0, 255 }
    local back = by + 2.5
    local A, B = vector3(bx - 20.0, back, bz - 12.0), vector3(bx + 20.0, back, bz - 12.0)
    local C, Dd = vector3(bx + 20.0, back, bz + 12.0), vector3(bx - 20.0, back, bz + 12.0)

    local drawing = true
    CreateThread(function()
        while drawing do
            HideHudAndRadarThisFrame()
            quad(A, B, C, Dd, col)
            DrawLightWithRange(bx, by - 3.0, bz + 1.0, 255, 250, 240, 12.0, 3.0)
            DrawLightWithRange(bx, by + 1.5, bz + 1.5, 200, 210, 255, 6.0, 1.0)
            Wait(0)
        end
    end)

    Wait(CFG.settleMs or 350)

    -- where each clone landed on screen (0..1)
    local marks = {}
    for i, c in ipairs(clones) do
        local p = GetEntityCoords(c)
        local _, sx = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
        local _, _, hy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.95)
        local _, _, fy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z - 1.05)
        marks[i] = { x = sx, top = hy, bottom = fy }
    end

    local got, done, internal = nil, false, CFG.captureMode ~= 'screenshot-basic'
    local ok
    if internal then
        grabReply = nil
        SendNUIMessage({ action = 'bodyGrab', marks = marks })
        ok = true
    else
        ok = pcall(function()
            exports['screenshot-basic']:requestScreenshot({ encoding = CFG.encoding or 'jpg', quality = CFG.quality or 0.95 }, function(data)
                got, done = data, true
            end)
        end)
    end
    local deadline = GetGameTimer() + (CFG.timeoutMs or 3000)
    while ok and GetGameTimer() < deadline do
        if internal and grabReply then done = true end
        if done then break end
        Wait(0)
    end

    drawing = false
    if pedCam and DoesCamExist(pedCam) then SetCamActive(pedCam, true)
    else RenderScriptCams(false, false, 0, true, true) end
    DestroyCam(cam, false)
    killAll(clones)
    RemoveAnimDict(POSE_DICT)
    Body.busy = false

    if internal then
        if not (grabReply and grabReply.ok) then dbg('game view grab failed'); return false end
        Body.sig = signature(ped)
        Body.stale = false
        dbg('captured (internal)')
        return true
    end
    if type(got) ~= 'string' or #got < 1000 then dbg('screenshot failed'); return false end
    Body.sig = signature(ped)
    Body.stale = false
    SendNUIMessage({ action = 'bodyShots', image = got, marks = marks })
    dbg('captured ' .. #got .. ' bytes')
    return true
end

function Body.NeedsCapture()
    if not available() then return false end
    -- once per session; the REFRESH button forces a new one
    return Body.stale
end

-- Called by cl_main when the page painted. Covers the screen, shoots if needed, then hands over to the portrait camera. cb runs either way.
function Body.Prepare(cb)
    SendNUIMessage({ action = 'bodyMode', available = available() })
    if not Body.NeedsCapture() then cb(); return end
    SendNUIMessage({ action = 'captureCover', on = true })
    Wait(60)   -- two painted frames of the cover before the camera moves
    local okc = pcall(Body.Capture)
    if not okc then Body.busy = false end
    cb()
    SendNUIMessage({ action = 'captureCover', on = false })
end

-- REFRESH button in Field Medical (10 s cooldown)
local lastRefresh = 0
RegisterNUICallback('bodyRefresh', function(_, cb)
    local cd = (CFG.refreshCooldown or 10) * 1000
    if Body.busy or not available() or GetGameTimer() - lastRefresh < cd then
        cb({ ok = false, wait = math.max(0, cd - (GetGameTimer() - lastRefresh)) }); return
    end
    lastRefresh = GetGameTimer()
    cb({ ok = true, cooldown = cd })
    CreateThread(function()
        SendNUIMessage({ action = 'captureCover', on = true })
        Wait(60)
        pcall(Body.Capture)
        Body.busy = false
        SendNUIMessage({ action = 'captureCover', on = false })
        SendNUIMessage({ action = 'bodyRefreshDone' })
    end)
end)

-- Injuries per body zone (from the last damaged bone), cleared on heal

local BONE_ZONE = {
    [31086] = 'head', [39317] = 'head', [12844] = 'head', [65068] = 'head',
    [45509] = 'larm', [61163] = 'larm', [18905] = 'larm', [64729] = 'larm',
    [40269] = 'rarm', [28252] = 'rarm', [57005] = 'rarm', [10706] = 'rarm',
    [58271] = 'lleg', [63931] = 'lleg', [14201] = 'lleg', [65245] = 'lleg',
    [51826] = 'rleg', [36864] = 'rleg', [52301] = 'rleg', [35502] = 'rleg',
}
local injuries = {}
local lastHp = nil

local function pushInjuries()
    SendNUIMessage({ action = 'injuries', zones = injuries })
end

local function clearInjuries()
    if next(injuries) == nil then return end
    injuries = {}
    pushInjuries()
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local ped = PlayerPedId()
    if args[1] ~= ped then return end
    local hit, bone = GetPedLastDamageBone(ped)
    local zone = (hit and BONE_ZONE[bone]) or 'torso'
    injuries[zone] = math.min(3, (injuries[zone] or 0) + 1)
    pushInjuries()
end)

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
        -- healed: a clear jump up, or back to full
        if lastHp and (hp >= max or hp - lastHp >= 10) then clearInjuries() end
        lastHp = hp
    end
end)

AddEventHandler('bs:hook:player:died', clearInjuries)

-- Active drugs and boosters, as chips

local active = { drugs = {}, boosters = {} }

local function pretty(id)
    return (tostring(id):gsub('_', ' '):upper())
end

local function pushActive()
    local now, list = GetGameTimer(), {}
    for kind, set in pairs(active) do
        for id, a in pairs(set) do
            if a.untilAt > now then
                list[#list + 1] = { kind = kind == 'drugs' and 'drug' or 'booster', label = a.label,
                                    left = math.floor((a.untilAt - now) / 1000) }
            else
                set[id] = nil
            end
        end
    end
    SendNUIMessage({ action = 'activeEffects', list = list })
end

RegisterNetEvent('bs:drugs:apply', function(drug, _, duration)
    duration = tonumber(duration) or 0
    if duration <= 0 then return end
    active.drugs[drug] = { label = pretty(drug), untilAt = GetGameTimer() + duration * 1000 }
    pushActive()
end)

RegisterNetEvent('bs:drugs:state', function(st)
    if type(st) ~= 'table' then return end
    for drug in pairs(active.drugs) do
        if not (st.active and st.active[drug]) then active.drugs[drug] = nil end
    end
    for drug, a in pairs(st.active or {}) do
        if type(a) == 'table' and tonumber(a.rem) then
            active.drugs[drug] = { label = pretty(drug), untilAt = GetGameTimer() + tonumber(a.rem) * 1000 }
        end
    end
    pushActive()
end)

RegisterNetEvent('bs:boosters:activate', function(item, t)
    if type(t) ~= 'table' or not tonumber(t.duration) then return end
    active.boosters[item] = { label = (t.label or pretty(item)):upper(), untilAt = GetGameTimer() + tonumber(t.duration) * 1000 }
    pushActive()
end)

-- Everything Field Medical needs on open.
function Body.Snapshot()
    pushInjuries()
    pushActive()
end

AddEventHandler('onResourceStop', function(resource)
    -- only if we died mid-capture; the portrait camera cleans up after itself
    if resource == GetCurrentResourceName() and Body.busy then
        RenderScriptCams(false, false, 0, true, true)
    end
end)

-- kept for compatibility with anything still calling them
function Body.Start() end
function Body.Stop() end
function Body.Turn() end
exports('BodyRenderActive', function() return false end)

BSInvBody = Body
