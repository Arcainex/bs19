-- BeyondSurvival - session state machine: loading -> select -> playing. bs_ui draws the screens via 'session:state'; the core owns state, camera and freeze.

BS.Session = { state = 'loading', payload = nil }

local S = BS.Session
local selectCam

local function destroySelectCam()
    if selectCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(selectCam, true)
        selectCam = nil
    end
end

local function createSelectCam()
    local c = Config.Session.selectCam
    destroySelectCam()
    selectCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z + 1.0, 0.0, 0.0, c.h, 50.0, false, 0)
    SetCamActive(selectCam, true)
    RenderScriptCams(true, false, 0, true, true)
end

-- Puts the local player into an invisible holding state while no character is selected.
-- If bs_multichar is running it owns the camera, ped preview and UI, so the core must not create its own camera.
local function multicharPresent()
    return GetResourceState('bs_multichar') == 'started'
end

local function enterLimbo()
    local ped = PlayerPedId()
    local c = Config.Session.selectCam
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    if Config.Session.useMultichar and not multicharPresent() then
        createSelectCam()
    end
end

BS.MulticharPresent = multicharPresent

local function leaveLimbo()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    destroySelectCam()
end

function BS.SetSessionState(state, payload)
    S.state = state
    S.payload = payload
    BS.Emit('session:state', state, payload)
    BS.Log.debug('session', ('state -> %s'):format(state))
end

RegisterNetEvent(BS.Events.SessionState, function(state, payload)
    if state == 'select' then
        enterLimbo()
        -- bs_multichar fades in itself once its scene is built; fading here would show the world for a frame first.
        if not multicharPresent() then
            DoScreenFadeIn(500)
            ShutdownLoadingScreen()
            ShutdownLoadingScreenNui()
        end
    end
    BS.SetSessionState(state, payload)
end)

BS.On('player:loaded', function()
    leaveLimbo()
    BS.SetSessionState('playing')
end)

--------------------------------------------------------------------------------
-- Handshake
--------------------------------------------------------------------------------

CreateThread(function()
    BS.Log.info('core', ('%s v%s starting (client)'):format(BS.Name, BS.Version))

    -- Disable vanilla auto-spawn. spawnmanager is optional and may not be started yet, so this is in a pcall; the framework spawns players itself either way.
    CreateThread(function()
        if GetResourceState('spawnmanager') ~= 'started' then return end
        for _ = 1, 20 do
            if pcall(function() exports.spawnmanager:setAutoSpawn(false) end) then
                BS.Log.debug('core', 'spawnmanager auto-spawn disabled')
                return
            end
            Wait(250)
        end
    end)

    while not NetworkIsSessionStarted() do Wait(100) end

    DoScreenFadeOut(0)
    enterLimbo()

    -- Kill the vanilla HUD pieces the custom HUD replaces.
    CreateThread(function()
        while true do
            Wait(0)
            HideHudComponentThisFrame(1)  -- wanted stars
            HideHudComponentThisFrame(2)  -- weapon icon
            HideHudComponentThisFrame(3)  -- cash
            HideHudComponentThisFrame(4)  -- mp cash
            HideHudComponentThisFrame(13) -- cash change
            HideHudComponentThisFrame(19) -- weapon wheel stats

            -- Not calling SetPedCanPlayAmbientAnims: disabling it every frame interferes with engine states such as the dry-fire reaction and can leave a ped stuck.
        end
    end)

    Wait(500)
    TriggerServerEvent(BS.Events.ClientReady)
    BS.Ready = true
    BS.Emit('core:ready')
end)

-- Current session state, for resources that start after the state event was already sent (e.g. restarting bs_multichar on the character screen).
exports('GetSessionState', function() return S.state end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    destroySelectCam()
    leaveLimbo()
end)
