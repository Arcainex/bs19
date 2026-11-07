-- Alpha-Z hard recovery: independent minimap suppression + survival HUD feed.
-- Deliberately does not depend on cl_hud.lua being healthy.

local function send(p) SendNUIMessage(p) end

local function pushLayout()
    send({
        action = 'settings',
        settings = {
            hudMode='full', hudAnchor='bottom-left', hudOpacity=0.72,
            hideWhenFull=false, xpPosition='bottom', xpOpacity=1.0,
            xpPopups=false, hudStyle='slim', menuPalette='default', dodge=true
        },
        theme = UI.Theme,
        bars = UI.Bars,
        minimal = UI.MinimalBars,
        xp = UI.XPBar,
    })
end

local function snapshot()
    local ped = PlayerPedId()
    local okD, data = pcall(function() return exports.bs_core:GetData() end)
    local okN, needs = pcall(function() return exports.bs_core:GetNeeds() end)
    data = okD and type(data)=='table' and data or {}
    needs = okN and type(needs)=='table' and needs or {}

    local maxHealth = GetEntityMaxHealth(ped)
    local hp = math.max(0, GetEntityHealth(ped) - 100)
    local range = math.max(1, maxHealth - 100)

    return {
        health = math.floor(hp / range * 100),
        healthNow = math.max(0, GetEntityHealth(ped)),
        healthMax = maxHealth,
        armour = math.floor(GetPedArmour(ped)),
        stamina = math.floor(tonumber(needs.stamina) or 100),
        hunger = math.floor(tonumber(needs.hunger) or 100),
        thirst = math.floor(tonumber(needs.thirst) or 100),
        infection = math.floor(tonumber(needs.infection) or 0),
        level = tonumber(data.level) or 1,
        xp = tonumber(data.xp) or 0,
        xpToNext = tonumber(data.xpToNext) or 1,
        cash = (type(data.accounts)=='table' and tonumber(data.accounts.cash)) or 0,
        inVehicle = IsPedInAnyVehicle(ped, false),
        speed = math.floor(GetEntitySpeed(ped) * 3.6),
    }
end

-- GTA corner minimap is never part of normal Alpha-Z gameplay.
CreateThread(function()
    while true do
        Wait(0)
        DisplayRadar(false)
        SetRadarBigmapEnabled(false, false)
        HideHudComponentThisFrame(1)
        HideHudComponentThisFrame(2)
        HideHudComponentThisFrame(3)
        HideHudComponentThisFrame(4)
        HideHudComponentThisFrame(7)
        HideHudComponentThisFrame(9)
        HideHudComponentThisFrame(13)
        HideHudComponentThisFrame(19)
        HideHudComponentThisFrame(20)
        pcall(SetMinimapComponent, 13, false)
        pcall(SetMinimapComponent, 14, false)
        pcall(SetMinimapComponent, 15, false)
    end
end)

-- Independent custom HUD feed. This restores the olive Alpha-Z health/status HUD
-- even if another bs_ui HUD driver stopped after an error.
CreateThread(function()
    Wait(1000)
    pushLayout()
    local tick = 0
    while true do
        Wait(200)
        local ok, loaded = pcall(function() return exports.bs_core:IsLoaded() end)
        if ok and loaded and not IsPauseMenuActive() then
            if tick % 25 == 0 then pushLayout() end
            send({ action='hud', visible=true })
            send({ action='hudData', data=snapshot() })
        else
            send({ action='hud', visible=false })
        end
        tick = tick + 1
    end
end)


-- YaCA voice range recovery. The hard HUD recovery must also own the voice
-- indicator because the original HUD driver may be the part that failed.
CreateThread(function()
    local lastMuted, lastRange = nil, nil
    while true do
        Wait(250)
        local muted, range = true, 0

        if GetResourceState('yaca-voice') == 'started' then
            local okMute, isMuted = pcall(function()
                return exports['yaca-voice']:getMicrophoneMuteState()
            end)
            local okDisabled, isDisabled = pcall(function()
                return exports['yaca-voice']:getMicrophoneDisabledState()
            end)
            local okRange, voiceRange = pcall(function()
                return exports['yaca-voice']:getVoiceRange()
            end)

            muted = (okMute and isMuted == true) or (okDisabled and isDisabled == true)
            if okRange then range = tonumber(voiceRange) or 0 end
        end

        if muted ~= lastMuted or range ~= lastRange then
            lastMuted, lastRange = muted, range
            SendNUIMessage({ action='yacaVoice', muted=muted, range=range })
        end
    end
end)
