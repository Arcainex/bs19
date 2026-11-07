-- bs_tutorial client: the guided tour (/tutorial, pause menu, first-spawn offer), the first mission tracker and the spawn flow.
-- While it plays the ped is frozen and hidden in a private bucket (server side); ESC leaves at any time.

local S = Tutorial.Settings
local Tour = { on = false, idx = 1, list = {}, token = 0, ents = {}, done = {} }
local overrides = {}
local lastHit = -600000
local hintAt = nil
local lastMission = nil   -- { mission, done, claimed } so the tracker comes back after the tour

local send, T = TutUtil.send, TutUtil.T

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 7000 }) end

AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and args[1] == PlayerPedId() then lastHit = GetGameTimer() end
end)

-- Chapter list with staff edits applied.

local function camOf(c, o)
    local cam = (o and o.cam) or c.cam or {}
    return cam[1], cam[2] or cam[1]
end

local function buildList()
    local lang, out = BSLocale.Lang(), {}
    local function add(c, builtin)
        local o = overrides[c.id] or {}
        if o.disabled then return end
        local txt = o.text and o.text[lang]
        local title, lines
        if txt then title, lines = txt.title, txt.lines
        elseif builtin then
            title = L(('ch.%s.t'):format(c.id))
            lines = {}
            for i = 1, 3 do lines[i] = L(('ch.%s.%d'):format(c.id, i)) end
        else
            title, lines = T(c.title or c.id), {}
            for i, l in ipairs(c.lines or {}) do lines[i] = T(l) end
        end
        local keys = {}
        for _, k in ipairs(c.keys or {}) do keys[#keys + 1] = { key = k[1], label = T(k[2]) } end
        local a, b = camOf(c, o)
        if a then
            out[#out + 1] = { id = c.id, icon = c.icon or 'info', title = title, lines = lines, keys = keys, a = a, b = b, demo = c.demo or {} }
        end
    end
    for _, c in ipairs(Tutorial.Chapters) do add(c, true) end
    for _, c in ipairs(Tutorial.CustomChapters or {}) do add(c, false) end
    return out
end

-- Demo peds and props, local only.

local function loadModel(m)
    local h = type(m) == 'number' and m or GetHashKey(m)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = 0
    while not HasModelLoaded(h) and t < 3000 do Wait(50); t = t + 50 end
    return HasModelLoaded(h) and h or nil
end

local function playAnim(ped, dict, name)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 2000 do Wait(50); t = t + 50 end
    if HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, name, 4.0, -4.0, -1, 1, 0.0, false, false, false) end
end

local function clearDemo()
    for _, e in ipairs(Tour.ents) do if DoesEntityExist(e) then DeleteEntity(e) end end
    Tour.ents = {}
end

-- Feet on the ground: ped origins sit at the hip, so measure the height above ground and correct.
local function snapPed(e, x, y, gz, h)
    SetEntityCoordsNoOffset(e, x, y, gz + 1.0, false, false, false)
    if h then SetEntityHeading(e, h) end
    Wait(0)
    local above = GetEntityHeightAboveGround(e)
    if above and above > 0.05 and above < 5.0 then SetEntityCoordsNoOffset(e, x, y, gz + 1.0 - above + 0.02, false, false, false) end
end

-- Spot next to the fuel cap of a demo vehicle (bone, else rear left), and the heading that faces the car.
local function fuelSpot(veh)
    local bone = GetEntityBoneIndexByName(veh, 'petrolcap')
    if bone == -1 then bone = GetEntityBoneIndexByName(veh, 'petroltank') end
    local pos = bone ~= -1 and GetWorldPositionOfEntityBone(veh, bone) or GetOffsetFromEntityInWorldCoords(veh, -1.0, -1.8, 0.0)
    local side = GetOffsetFromEntityGivenWorldCoords(veh, pos.x, pos.y, pos.z)
    local out = GetOffsetFromEntityInWorldCoords(veh, side.x < 0 and side.x - 0.8 or side.x + 0.8, side.y, 0.0)
    local hd = GetHeadingFromVector_2d(pos.x - out.x, pos.y - out.y)
    return out, hd
end

local function spawnDemo(ch, token)
    local lastVeh
    for _, d in ipairs(ch.demo or {}) do
        if Tour.token ~= token then return end
        local h = d.model and loadModel(d.model)
        if h and d.at then
            local x, y, hd = d.at.x, d.at.y, d.h or 0.0
            local z = TutUtil.groundZ(x, y, d.at.z, 1200)
            local e
            if d.kind == 'prop' then
                e = CreateObject(h, x, y, z, false, false, false)   -- local only
                PlaceObjectOnGroundProperly(e)
                FreezeEntityPosition(e, true)
            elseif d.kind == 'vehicle' then
                e = CreateVehicle(h, x, y, z, hd, false, false)     -- local only
                SetVehicleOnGroundProperly(e)
                SetEntityInvincible(e, true)
                FreezeEntityPosition(e, true)
                lastVeh = e
            else
                if d.fuel and lastVeh and DoesEntityExist(lastVeh) then
                    local out, fh = fuelSpot(lastVeh)
                    x, y, hd = out.x, out.y, fh
                    z = TutUtil.groundZ(x, y, out.z + 1.0, 800)
                end
                e = CreatePed(4, h, x, y, z, hd, false, true)       -- local only
                SetEntityInvincible(e, true)
                SetBlockingOfNonTemporaryEvents(e, true)
                snapPed(e, x, y, z, hd)
                FreezeEntityPosition(e, true)
                if d.kind == 'zombie' then
                    FreezeEntityPosition(e, false)
                    RequestAnimSet('move_m@drunk@verydrunk')
                    local t = 0
                    while not HasAnimSetLoaded('move_m@drunk@verydrunk') and t < 1500 do Wait(50); t = t + 50 end
                    SetPedMovementClipset(e, 'move_m@drunk@verydrunk', 1.0)
                    local f = GetEntityForwardVector(e)
                    TaskGoStraightToCoord(e, x + f.x * 12.0, y + f.y * 12.0, z, 0.6, -1, hd, 0.0)
                elseif d.anim then
                    playAnim(e, d.anim[1], d.anim[2])
                end
            end
            SetModelAsNoLongerNeeded(h)
            if e and e ~= 0 then Tour.ents[#Tour.ents + 1] = e end
        end
    end
end

-- Camera points are checked by TutUtil.safeCam (cl_picker.lua).
local clearCam = TutUtil.safeCam

-- Playing

local stopTour

local function play(i)
    if not Tour.on then return end
    if i < 1 then i = 1 end
    if i > #Tour.list then
        Tour.token = Tour.token + 1
        send({ action = 'tourEnd', done = Tour.done })
        return
    end
    Tour.idx = i
    Tour.token = Tour.token + 1
    local token, ch = Tour.token, Tour.list[i]
    clearDemo()
    local a, b = clearCam(ch.a, ch.b), clearCam(ch.b, ch.a)
    TutUtil.camTo(a.pos, a.look, 0)
    TutUtil.camTo(b.pos, b.look, math.floor(S.chapterSeconds * 1000))
    send({ action = 'chapter', index = i, seconds = S.chapterSeconds })
    CreateThread(function() Wait(400); spawnDemo(ch, token) end)
    CreateThread(function()
        local t0 = GetGameTimer()
        local marked = false
        while Tour.on and Tour.token == token do
            local el = (GetGameTimer() - t0) / 1000
            if not marked and el >= (S.doneAfterSeconds or 8) then
                marked = true
                local r = BSB.Await('tutorial:chapterDone', 8000, ch.id)
                if r and r.ok then
                    Tour.done = r.done or Tour.done
                    send({ action = 'done', done = Tour.done })
                    if r.reward then notify('success', L('tut.reward', { xp = S.completionXp })) end
                end
            end
            if el >= S.chapterSeconds then
                if Tour.token == token then play(i + 1) end
                return
            end
            Wait(250)
        end
    end)
end

local function canStart(forced)
    if Tour.on or TutPicker.active then return false end
    if not exports.bs_core:IsLoaded() then return false end
    if forced then return true end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then notify('warn', L('tut.not_now')) return false end
    if IsPedInMeleeCombat(ped) or IsPedShooting(ped)
        or (GetGameTimer() - lastHit) < (S.combatCooldown or 30) * 1000 then
        notify('warn', L('tut.combat')) return false
    end
    return true
end

local function startTour(startId, forced)
    if not canStart(forced) then return end
    local res = BSB.Await('tutorial:begin', 8000, forced == true)
    if not res or not res.ok then
        if res and res.error then notify('warn', res.error) end
        return
    end
    overrides = res.overrides or overrides
    Tour.list = buildList()
    if #Tour.list == 0 then
        BSB.Await('tutorial:end', 5000)
        TriggerServerEvent('bs:tutorial:leave')
        return
    end
    Tour.done = type(res.done) == 'table' and res.done or {}
    Tour.on = true
    hintAt = nil

    DoScreenFadeOut(400); Wait(450)
    TriggerEvent('bs:ui:opened', 'tutorial')   -- bs_ui hides HUD, toasts and chat for this panel
    send({ action = 'mission', show = false })
    TutUtil.hidePlayer(true)
    StartAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE')

    local chapters = {}
    local first = 1
    for i, c in ipairs(Tour.list) do
        chapters[i] = { id = c.id, icon = c.icon, title = c.title, lines = c.lines, keys = c.keys }
        if c.id == startId then first = i end
    end
    send({ action = 'tour', show = true, strings = BSLocale.Dict(BSLocale.Lang()), chapters = chapters, done = Tour.done,
           ambient = S.ambientVolume or 0, mission = res.missionAvailable == true })
    SetNuiFocus(true, true)
    play(first)
    Wait(600)
    DoScreenFadeIn(700)

    CreateThread(function()
        while Tour.on do
            DisableControlAction(0, 200, true); DisableControlAction(0, 199, true)
            HideHudAndRadarThisFrame()
            DisplayRadar(false)
            if IsEntityDead(PlayerPedId()) then stopTour() end
            Wait(0)
        end
    end)
end

stopTour = function()
    if not Tour.on then return end
    Tour.on = false
    Tour.token = Tour.token + 1
    DoScreenFadeOut(300); Wait(320)
    clearDemo()
    send({ action = 'tour', show = false })
    SetNuiFocus(false, false)
    TutUtil.camStop()
    StopAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE')
    TutUtil.hidePlayer(false)
    BSB.Await('tutorial:end', 5000)
    TriggerServerEvent('bs:tutorial:leave')
    TriggerEvent('bs:ui:closed', 'tutorial')
    if lastMission then TriggerEvent('bs:tutorial:mission', lastMission[1], lastMission[2], lastMission[3]) end
    Wait(200)
    DoScreenFadeIn(500)
end

RegisterNUICallback('tourGo', function(data, cb)
    cb({})
    if not Tour.on or type(data) ~= 'table' then return end
    if data.dir == 'next' then play(Tour.idx + 1)
    elseif data.dir == 'prev' then play(Tour.idx - 1)
    elseif tonumber(data.index) then play(math.floor(tonumber(data.index))) end
end)

RegisterNUICallback('tourExit', function(_, cb) cb({}); CreateThread(stopTour) end)

-- First mission

local function startMission()
    local r = BSB.Await('tutorial:missionStart', 8000)
    if r and r.ok then notify('info', L('mis.started')) elseif r and r.error then notify('warn', r.error) end
end

RegisterNUICallback('tourMission', function(_, cb)
    cb({})
    CreateThread(function() stopTour(); startMission() end)
end)

RegisterNetEvent('bs:tutorial:mission', function(m, done, claimed)
    if type(m) ~= 'table' then return end
    if claimed then lastMission = nil; send({ action = 'mission', show = false }) return end
    lastMission = { m, done, claimed }
    if Tour.on then return end
    send({ action = 'mission', show = true, strings = BSLocale.Dict(BSLocale.Lang()), loot = m.loot == true, craft = m.craft == true,
           kills = tonumber(m.kills) or 0, need = Tutorial.Mission.kills, done = done == true })
end)

-- Offer after the first spawn

local offerWait = nil
local function offer()
    offerWait = true
    send({ action = 'offer', show = true, strings = BSLocale.Dict(BSLocale.Lang()) })
    SetNuiFocus(true, true)
end

RegisterNUICallback('offerAnswer', function(data, cb)
    cb({})
    if not offerWait then return end
    offerWait = nil
    send({ action = 'offer', show = false })
    SetNuiFocus(false, false)
    local yes = type(data) == 'table' and data.yes == true
    CreateThread(function()
        BSB.Await('tutorial:offer', 5000, yes)
        if yes then startTour(nil, false)
        else hintAt = GetGameTimer() + (S.hintMinutes or 10) * 60000 end
    end)
end)

-- Later hint after Skip.
CreateThread(function()
    while true do
        Wait(15000)
        if hintAt and GetGameTimer() >= hintAt then
            hintAt = nil
            notify('info', L('tut.hint', { cmd = '/' .. S.command }))
        end
    end
end)

AddEventHandler('bs:hook:player:unloaded', function() lastMission = nil; send({ action = 'mission', show = false }) end)

AddEventHandler('bs:hook:player:spawned', function()
    CreateThread(function()
        Wait(1500)
        local st = BSB.Await('tutorial:spawnState', 8000)
        if not st or not st.ok then return end
        local doOffer = st.offer
        if st.pick then
            local res = TutPicker.Run(st.pick)
            doOffer = res and res.offer
        end
        if st.mission and not st.missionClaimed then TriggerEvent('bs:tutorial:mission', st.mission, st.missionDone == true, false)
        else lastMission = nil; send({ action = 'mission', show = false }) end
        if doOffer and S.enabled and S.firstSpawnPrompt then Wait(2500) offer() end
    end)
end)

-- Ways in

RegisterCommand(S.command, function()
    if not S.enabled then return notify('warn', L('tut.disabled')) end
    CreateThread(function() startTour(nil, false) end)
end, false)

RegisterNetEvent('bs:tutorial:force', function(chapterId)
    CreateThread(function()
        if Tour.on then stopTour() end
        startTour(type(chapterId) == 'string' and chapterId or nil, true)
    end)
end)

AddEventHandler('bs:tutorial:fromPause', function()
    if not S.enabled then return notify('warn', L('tut.disabled')) end
    CreateThread(function() Wait(300); startTour(nil, false) end)
end)

local function addPauseTab()
    if GetResourceState('bs_pause') ~= 'started' then return end
    pcall(function()
        exports.bs_pause:AddPauseTab({ id = 'tutorial', label = L('tut.pause_tab'), icon = '?', order = 60, event = 'bs:tutorial:fromPause' })
    end)
end
CreateThread(function() Wait(2000); addPauseTab() end)
AddEventHandler('onClientResourceStart', function(res) if res == 'bs_pause' then SetTimeout(500, addPauseTab) end end)
BSLocale.OnChange(function() addPauseTab() end)

RegisterNetEvent('bs:tutorial:overrides', function(o) if type(o) == 'table' then overrides = o end end)
CreateThread(function()
    local o = BSB.Await('tutorial:overrides', 10000)
    if type(o) == 'table' then overrides = o end
end)

-- F1 editor asks where the staff member is looking.
BSB.RegisterClientCallback('tutorial:camNow', function()
    local p = GetGameplayCamCoord()
    local r = GetGameplayCamRot(2)
    local rx, rz = math.rad(r.x), math.rad(r.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local look = p + dir * 30.0
    return { pos = { x = p.x, y = p.y, z = p.z }, look = { x = look.x, y = look.y, z = look.z } }
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Tour.on or TutPicker.active then
        clearDemo(); TutUtil.camStop(); TutUtil.hidePlayer(false); SetNuiFocus(false, false)
        StopAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE'); DoScreenFadeIn(0)
    end
end)
