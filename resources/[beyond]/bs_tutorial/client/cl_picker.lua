-- bs_tutorial client helpers (camera, hiding the ped) and the first-join faction picker.

TutUtil = {}
local cam = nil

function TutUtil.send(p) SendNUIMessage(p) end

-- Locale key or plain text.
function TutUtil.T(v, vars)
    if type(v) ~= 'string' then return '' end
    local t = L(v, vars)
    return t ~= v and t or v
end

-- Frozen, hidden and unhurt while a camera sequence runs. The server has already moved us to a private bucket.
function TutUtil.hidePlayer(on)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, on)
    SetEntityVisible(ped, not on, false)
    SetEntityInvincible(ped, on)
    SetEntityCollision(ped, not on, not on)
    if on then ClearPedTasksImmediately(ped) end
    TutUtil.voice(on)   -- also set directly, the state bag can arrive a moment later
end

local function v(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

-- Camera point kept between 5 m above the ground under it and 45 m above its target (more when walls block), then
-- checked with line-of-sight probes to the target (feet and head) and, when `other` is given, along the flight path.
-- Blocked: lift 6 m (up to 8 times), then back off 12 m away from the target and lift again (up to 4 times).
local function clearAt(x, y, z, look, mid)
    local ped = PlayerPedId()
    local aims = { look, look + vector3(0.0, 0.0, 1.7) }
    local froms = { vector3(x, y, z) }
    if mid then froms[2] = vector3(mid.x, mid.y, z) end
    for _, f in ipairs(froms) do
        for _, t in ipairs(aims) do
            local stop = f + (t - f) * 0.94
            local h = StartExpensiveSynchronousShapeTestLosProbe(f.x, f.y, f.z, stop.x, stop.y, stop.z, 1 | 16, ped, 4)
            local _, hit = GetShapeTestResult(h)
            if hit == 1 then return false end
        end
    end
    return true
end

function TutUtil.safeCam(p, other)
    local pos, look = v(p.pos), v(p.look)
    RequestCollisionAtCoord(pos.x, pos.y, pos.z); RequestCollisionAtCoord(look.x, look.y, look.z)
    Wait(300)
    local gz = TutUtil.groundZ(pos.x, pos.y, pos.z, 1200)
    local lo, hi = gz + 5.0, look.z + 45.0
    if hi < lo then hi = lo end
    local x, y, z = pos.x, pos.y, math.min(math.max(pos.z, lo), hi)
    local mid = other and (v(other.pos) + pos) * 0.5 or nil
    local away = vector3(pos.x - look.x, pos.y - look.y, 0.0)
    local len = #away
    away = len > 0.1 and away / len or vector3(1.0, 0.0, 0.0)
    for back = 0, 4 do
        for _ = 1, 8 do
            if clearAt(x, y, z, look, mid) then return { pos = vector3(x, y, z), look = look } end
            z = z + 6.0
        end
        x, y = x + away.x * 12.0, y + away.y * 12.0
        if mid then mid = vector3(mid.x + away.x * 12.0, mid.y + away.y * 12.0, mid.z) end
        z = math.max(look.z + 20.0, gz + 5.0)
        RequestCollisionAtCoord(x, y, z)
    end
    -- Nothing was clear: high above the target looking down is the last resort.
    return { pos = vector3(pos.x, pos.y, look.z + 70.0), look = look }
end

-- Voice follows the private bucket: others cannot hear us while the state bag 'bs_tutorial' is set by the server.
local voiceOn = false
local function pma() return GetResourceState('pma-voice') == 'started' end
function TutUtil.voice(on)
    if on == voiceOn then return end
    voiceOn = on
    if on then
        if pma() then pcall(function() exports['pma-voice']:overrideProximityRange(0.01, true) end)
        else MumbleSetVoiceChannel(1000000 + GetPlayerServerId(PlayerId())) end
    else
        if pma() then pcall(function() exports['pma-voice']:clearProximityOverride() end)
        else MumbleClearVoiceChannel() end
    end
end

AddStateBagChangeHandler('bs_tutorial', nil, function(bag, _, value)
    if bag ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
    TutUtil.voice(value == 'tour' or value == 'pick')
end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and voiceOn then TutUtil.voice(false) end
end)
CreateThread(function()
    Wait(2000)
    local st = LocalPlayer.state.bs_tutorial
    if st == 'tour' or st == 'pick' then TutUtil.voice(true) end
end)

-- Fly from the current camera to pos looking at look over ms (0 = cut).
function TutUtil.camTo(pos, look, ms)
    pos, look = v(pos), v(look)
    local nc = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 55.0, false, 2)
    PointCamAtCoord(nc, look.x, look.y, look.z)
    SetFocusPosAndVel(look.x, look.y, look.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(look.x, look.y, look.z)
    if cam and ms and ms > 0 then
        SetCamActiveWithInterp(nc, cam, ms, 1, 1)
        local old = cam
        SetTimeout(ms + 100, function() if DoesCamExist(old) and old ~= cam then DestroyCam(old, false) end end)
    else
        if cam then DestroyCam(cam, false) end
        SetCamActive(nc, true)
        RenderScriptCams(true, false, 0, true, true)
    end
    cam = nc
end

function TutUtil.camStop()
    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
    cam = nil
    DestroyAllCams(true)
    ClearFocus()
end

function TutUtil.groundZ(x, y, z, waitMs)
    local t = 0
    while t < (waitMs or 1500) do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
        if ok then return gz end
        Wait(100); t = t + 100
    end
    return z
end

-- Places the ped on solid ground at a spot that may not be streamed yet.
function TutUtil.teleport(p)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
    SetFocusPosAndVel(p.x, p.y, p.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(p.x, p.y, p.z)
    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 6000 do Wait(100); t = t + 100 end
    local gz = TutUtil.groundZ(p.x, p.y, p.z, 2000)
    SetEntityCoordsNoOffset(ped, p.x, p.y, gz + 0.1, false, false, false)
    SetEntityHeading(ped, (p.h or 0.0) + 0.0)
    ClearFocus()
end

-- Faction picker

TutPicker = { active = false }
local pick = nil

local function card(id)
    for _, f in ipairs(Tutorial.Factions) do if f.id == id then return f end end
end

local function cards(data)
    local out = {}
    for _, f in ipairs(data.factions or {}) do
        local id = f.id
        out[#out + 1] = {
            id = id, colour = f.colour, members = f.members, bonus = f.bonus,
            name = TutUtil.T('fac.' .. id .. '.n'), desc = TutUtil.T('fac.' .. id .. '.d'),
            perks = { TutUtil.T('fac.' .. id .. '.p1'), TutUtil.T('fac.' .. id .. '.p2'), TutUtil.T('fac.' .. id .. '.p3') },
            jobs = TutUtil.T('fac.' .. id .. '.jobs'),
        }
    end
    return out
end

--- Runs the picker until a faction is chosen. Returns the server answer.
function TutPicker.Run(data)
    if TutPicker.active then return nil end
    TutPicker.active = true
    pick = { done = false }

    DoScreenFadeOut(400); Wait(450)
    TriggerEvent('bs:ui:opened', 'tutorial')
    TutUtil.hidePlayer(true)
    local first = card((data.factions[1] or {}).id)
    if first then local c = TutUtil.safeCam(first.cam); TutUtil.camTo(c.pos, c.look, 0) end

    TutUtil.send({ action = 'picker', show = true, strings = BSLocale.Dict(BSLocale.Lang()), cards = cards(data),
                   bonusCash = data.bonusCash, bonusXp = data.bonusXp })
    SetNuiFocus(true, true)
    Wait(800)
    DoScreenFadeIn(700)

    CreateThread(function()
        while TutPicker.active do
            DisableControlAction(0, 200, true); DisableControlAction(0, 199, true)
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)

    while not pick.done do Wait(100) end
    local res = pick.result

    DoScreenFadeOut(500); Wait(550)
    TutUtil.send({ action = 'picker', show = false })
    SetNuiFocus(false, false)
    TutUtil.camStop()
    if res and res.spawn then TutUtil.teleport(res.spawn) end
    TutUtil.hidePlayer(false)
    TutPicker.active = false
    TriggerEvent('bs:ui:closed', 'tutorial')
    Wait(300)
    DoScreenFadeIn(800)

    if res and res.ok then
        TriggerEvent('bs:ui:notify', { type = 'success', duration = 8000, message = L('pick.joined', { name = res.label or '' }) })
        if res.bonus then
            TriggerEvent('bs:ui:notify', { type = 'info', duration = 8000,
                message = L('pick.bonus_got', { cash = Tutorial.Settings.smallestBonusCash, xp = Tutorial.Settings.smallestBonusXp }) })
        end
    end
    return res
end

RegisterNUICallback('pickSelect', function(data, cb)
    cb({})
    local f = card(type(data) == 'table' and data.id or '')
    if f and TutPicker.active then local c = TutUtil.safeCam(f.cam); TutUtil.camTo(c.pos, c.look, 1800) end
end)

RegisterNUICallback('pickConfirm', function(data, cb)
    if not pick or pick.done or pick.busy then return cb({ ok = false }) end
    pick.busy = true
    local res = BSB.Await('tutorial:pick', 10000, type(data) == 'table' and data.id or '')
    pick.busy = false
    if res and res.ok then
        pick.result = res
        pick.done = true
    end
    cb(res or { ok = false })
end)
