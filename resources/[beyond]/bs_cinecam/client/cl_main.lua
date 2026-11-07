--[[ BeyondSurvival | bs_cinecam/client/cl_main.lua

     The F3 menu, the commands, and the permission check.                     ]]

local open = false

-- Shared with cl_camera.lua so the camera knows the menu is up. A shared global rather than an event, since the camera loop reads it every frame.
CineMenu = { open = false }
local mayUse = nil        -- nil = not asked yet, true/false = server's answer

local function send(payload) SendNUIMessage(payload) end

local function say(text)
    TriggerEvent('chat:addMessage', { args = { '^5[cine]', text } })
end

--------------------------------------------------------------------------------
-- Permission
--------------------------------------------------------------------------------

-- Asked once and cached. The real check is on the server (server/sv_main.lua re-checks before acknowledging anything); the client answer only decides whether to open the menu.
local function mayFly()
    if not Cine.Settings.requirePermission then return true end
    if mayUse ~= nil then return mayUse end

    local answer = BSB.Await('cinecam:mayuse', 8000)
    mayUse = answer == true
    return mayUse
end

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------

local function payload()
    return {
        settings = CineState.s,
        defaults = Cine.Defaults,
        presets  = Cine.Presets,
        --[[ bs_ui's filter presets, sent as data. This resource defines no
             looks of its own - see cl_grade.lua's header for why that is a
             rule rather than a convenience. ]]
        filters  = CineGrade and CineGrade.Presets() or {},
        path     = CinePath.Summary(),
        camera   = { active = CineCam.active, hud = CineLock.hud },
    }
end

local function openMenu()
    if open then return end
    if not mayFly() then
        say(L('cine.no_perm'))
        return
    end

    open = true

    CineMenu.open = true
    send({ action = 'open', data = payload() })

    -- Focus with input kept: SetNuiFocus alone takes the keyboard too and the camera would stop. SetNuiFocusKeepInput lets you fly and tune sliders at the same time.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(CineCam.active)

    -- Deliberately NOT announced as bs:ui:opened when the camera is running:
    -- that event closes every other panel and hides the HUD, which is already
    -- handled, and the camera's own lockout owns the screen at that point.
    if not CineCam.active then TriggerEvent('bs:ui:opened', 'cinecam-menu') end
end

local function closeMenu()
    if not open then return end
    open = false
    CineMenu.open = false
    send({ action = 'close' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if not CineCam.active then TriggerEvent('bs:ui:closed', 'cinecam-menu') end
end

local function toggleMenu()
    if open then closeMenu() else CreateThread(openMenu) end
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

RegisterCommand(Cine.Settings.openCommand, toggleMenu, false)
RegisterKeyMapping(Cine.Settings.openCommand,
    L('cine.keymap'), 'keyboard', Cine.Settings.openKey)

-- Raw-key path. Cinematic mode disables all controls, including key mappings, so without this loop nothing could open the menu to leave the camera.
-- IsRawKeyJustPressed ignores DisableAllControlActions. Only runs while the camera is active, so it never double-fires with the key mapping above.
CreateThread(function()
    while true do
        if CineCam.active then
            Wait(0)

            if IsRawKeyJustPressed(Cine.Settings.rawMenu) then
                toggleMenu()
            elseif IsRawKeyJustPressed(Cine.Settings.rawExit) then
                closeMenu()
                CineCam.Leave()
                say(L('cine.off'))
            end
        else
            Wait(200)
        end
    end
end)

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

RegisterNUICallback('apply', function(data, cb)
    local s = CineState.Apply(data and data.patch, true)

    -- Live-apply the ones that are not read fresh every frame.
    if CineCam.active then
        if data and data.patch and data.patch.fov then CineCam.tFov = s.fov end
        -- Grading is something you judge by looking, so it has to land on the
        -- click rather than on the next time the camera is entered.
        if CineGrade then CineGrade.Set(s) end
        SetTimeScale(s.timescale)
        CineLock.SetLocked(not s.allowMenuHotkeys)
        CineLock.SetHud(s.hideHud)
        SetNuiFocusKeepInput(true)
    end

    cb({ ok = true, settings = s })
end)

RegisterNUICallback('preset', function(data, cb)
    local index = tonumber(data and data.index)
    local preset = index and Cine.Presets[index]
    if not preset then cb({ ok = false }); return end

    local s = CineState.Apply(preset.patch, true)
    if CineCam.active and preset.patch.fov then CineCam.tFov = s.fov end

    cb({ ok = true, settings = s })
end)

RegisterNUICallback('reset', function(_, cb)
    local s = CineState.Reset(true)
    if CineCam.active then
        CineCam.tFov = s.fov
        SetTimeScale(s.timescale)
    end
    cb({ ok = true, settings = s })
end)

RegisterNUICallback('camera', function(data, cb)
    local want = data and data.on
    if want == nil then want = not CineCam.active end

    if want and not CineCam.active then
        if not mayFly() then
            cb({ ok = false, reason = 'no permission' })
            return
        end
        CineCam.Enter()
        SetNuiFocusKeepInput(true)
    elseif not want and CineCam.active then
        CineCam.Leave()
        SetNuiFocusKeepInput(false)
    end

    cb({ ok = true, camera = { active = CineCam.active, hud = CineLock.hud } })
end)

RegisterNUICallback('hud', function(data, cb)
    local hidden = CineLock.SetHud(data and data.hidden or false)
    cb({ ok = true, hud = hidden })
end)

RegisterNUICallback('path', function(data, cb)
    local op = data and data.op

    if op == 'add' then
        CinePath.Add()
    elseif op == 'pop' then
        CinePath.Pop()
    elseif op == 'clear' then
        CinePath.Clear()
    elseif op == 'play' then
        CinePath.Play()
    elseif op == 'stop' then
        CinePath.Stop()
    elseif op == 'set' then
        --[[ These live on Cine.Path rather than in CineState because they are
             properties of the SHOT, not of the camera - you want them reset
             when you start a new one, not remembered from last week. ]]
        local d = tonumber(data.duration)
        local e = tonumber(data.ease)
        if d then Cine.Path.duration = math.max(0.5, math.min(600.0, d)) end
        if e then Cine.Path.ease = math.max(0.0, math.min(0.5, e)) end
        if data.loop ~= nil then Cine.Path.loop = data.loop and true or false end
    end

    cb({ ok = true, path = CinePath.Summary() })
end)

--------------------------------------------------------------------------------
-- Live state push, so the menu is not lying while you fly
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(200)
        if open then
            send({
                action = 'live',
                data = {
                    x = CineCam.x, y = CineCam.y, z = CineCam.z,
                    pitch = CineCam.pitch, yaw = CineCam.yaw,
                    fov = CineCam.fov, roll = CineCam.roll,
                    speed = math.sqrt(CineCam.vx ^ 2 + CineCam.vy ^ 2 + CineCam.vz ^ 2),
                    camera = { active = CineCam.active, hud = CineLock.hud },
                    path = CinePath.Summary(),
                },
            })
        end
    end
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--[[ Every one of these answers, always. A silent return on a permission
     failure is indistinguishable from a missing command or a dead resource,
     which is exactly how /zstream burned an afternoon. ]]

RegisterCommand('cine', function(_, args)
    local sub = args[1]

    if sub == 'on' or sub == 'off' or sub == nil then
        CreateThread(function()
            if not mayFly() then
                say(L('cine.no_perm'))
                return
            end

            local want
            if sub == 'on' then want = true
            elseif sub == 'off' then want = false
            else want = not CineCam.active end

            if want then CineCam.Enter() else CineCam.Leave() end
            say(want and L('cine.on') or L('cine.off'))
        end)
    elseif sub == 'menu' then
        toggleMenu()
    elseif sub == 'reset' then
        CineState.Reset(true)
        say(L('cine.reset'))
    else
        say(L('cine.usage'))
    end
end, false)

RegisterCommand('cinediag', function()
    local s = CineState.s
    say(('active=%s locked=%s hud=%s keyframes=%d playing=%s')
        :format(tostring(CineCam.active), tostring(CineLock.locked),
                tostring(CineLock.hud), #CinePath.nodes, tostring(CinePath.playing)))
    say(('move=%.2fs look=%.2fs fov=%.1f speed=%.1f timescale=%.2f')
        :format(s.moveSmooth, s.lookSmooth, CineCam.fov, s.speed, s.timescale))
    say(('permission=%s  bs_ui=%s  bs_chat=%s')
        :format(tostring(mayUse), GetResourceState('bs_ui'), GetResourceState('bs_chat')))
end, false)

--------------------------------------------------------------------------------
-- Safety
--------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)

AddEventHandler('bs:ui:panic', function()
    -- Our own broadcast on entering camera mode - see CineLock.SetLocked.
    -- Closing the menu here would close it the instant the camera comes on.
    if CineLock.selfPanic then return end

    open = false

    CineMenu.open = false
    send({ action = 'close' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
