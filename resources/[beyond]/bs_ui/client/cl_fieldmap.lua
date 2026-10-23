-- bs_ui - field map (M). Expands GTA's own map to most of the screen inside a paper-style frame. Gameplay continues underneath. Only HudSetBigmap and HudSetMinimapRect (cl_hud.lua) can change the map itself.

local F = UI.FieldMap

local open = false
local zoom = F.zoom or 460.0    -- lower = more zoomed in. Scroll adjusts this.
local ZOOM_MIN, ZOOM_MAX = 100.0, 1400.0

-- Map box. These four numbers must match the `.fieldmap` rule in bs_ui/html/css/hud.css by hand (currently left 8vw, top 8vh, 84vw x 84vh). If the map sits off inside the frame, adjust these, not the CSS. The minimap may overshoot on some aspect ratios, so keep the rect generous.
local RECT = { x = 0.08, y = 0.08, w = 0.84, h = 0.84 }

local function send(p) SendNUIMessage(p) end

-- Uses GTA's own bigmap: a custom-sized radar box draws nothing past a certain size, and SetRadarBigmapEnabled ignores a custom minimap rect. Component 4 opens straight on the MAP tab. The world does not pause, so do not open it mid-fight. GetHashKey is used instead of backtick literals so files stay checkable with luac.
local PAUSE_MENU = GetHashKey('FE_MENU_VERSION_SP_PAUSE')
local MAP_COMPONENT = 4

local function openPauseMap()
    if not exports.bs_core:IsLoaded() then return end
    if IsPedDeadOrDying(PlayerPedId(), true) then return end

    -- Nothing else may be holding NUI focus behind a full-screen game menu.
    TriggerEvent('bs:ui:opened', 'fieldmap')

    pcall(ActivateFrontendMenu, PAUSE_MENU, false, MAP_COMPONENT)

    -- The game closes the pause menu itself. This thread waits for that so the rest of the project gets a matching bs:ui:closed.
    CreateThread(function()
        Wait(400)
        while IsPauseMenuActive() do Wait(150) end
        TriggerEvent('bs:ui:closed', 'fieldmap')
    end)
end

local function openMap()
    if F.mode == 'pause' then return openPauseMap() end

    if open then return end
    if not exports.bs_core:IsLoaded() then return end
    if IsPedDeadOrDying(PlayerPedId(), true) then return end

    open = true
    zoom = F.zoom or 460.0

    -- Order matters: claim the radar, announce (other panels close themselves on bs:ui:opened, and cl_hud.lua turns the radar off on their bs:ui:closed), and only then touch the radar.

    -- 1. Claim it. bigmapForced is read by cl_hud.lua's bs:ui:closed guard, so it must be true before the announcement below.
    HudSetBigmap(true)   -- also tells the strip-back thread to leave bigmap alone

    -- 2. Announce, so every other panel closes now.
    TriggerEvent('bs:ui:opened', 'fieldmap')

    -- 3. Set up the map. Bigmap is not used here: it renders at GTA's own footprint in the corner and ignores SetMinimapComponentPosition. The relocated radar works because HudSetMinimapRect moves the mask and blur too (see cl_hud.lua).
    HudSetMinimap(true, false)
    DisplayRadar(true)
    pcall(SetRadarBigmapEnabled, false, false)
    HudSetMinimapRect(RECT)
    pcall(SetRadarZoom, math.floor(zoom))

    -- Blur: use the game's blur (TriggerScreenblurFadeIn, same as bs_radial). A CSS backdrop-filter has no game pixels to sample in NUI.
    if F.blurWorld then TriggerScreenblurFadeIn(160) end

    send({ action = 'fieldmap', show = true })
end

local function closeMap()
    if not open then return end
    open = false

    -- Mirror of openMap: release the claim (HudSetBigmap(false)) before the announcement, so cl_hud.lua's guard lets the map close normally.
    if F.blurWorld then TriggerScreenblurFadeOut(120) end

    pcall(SetRadarBigmapEnabled, false, false)
    HudSetBigmap(false)
    HudResetMinimapRect()
    HudSetMinimap(false)

    send({ action = 'fieldmap', show = false })
    TriggerEvent('bs:ui:closed', 'fieldmap')
end

RegisterCommand(F.command, function()
    if F.mode == 'pause' then
        -- Toggle: pressing M again closes it.
        if IsPauseMenuActive() then
            pcall(ActivateFrontendMenu, PAUSE_MENU, true, -1)
        else
            CreateThread(openMap)
        end
        return
    end

    if open then closeMap() else CreateThread(openMap) end
end, false)
RegisterKeyMapping(F.command, L('ui.key_fieldmap'), 'keyboard', F.key)

--------------------------------------------------------------------------------
-- While it is open
--------------------------------------------------------------------------------

-- ESC closes it. Scroll zooms with the vanilla controls (241 up, 242 down).
CreateThread(function()
    while true do
        if open then
            Wait(0)

            -- Backing: a dark rectangle under the map. DrawRect takes a centre and size, hence the halves. Slightly larger than RECT because the minimap does not honour its position exactly on every aspect ratio. If it draws over the map, set UI.FieldMap.backing = false.
            if F.backing then
                local pad = 0.006
                DrawRect(RECT.x + RECT.w * 0.5, RECT.y + RECT.h * 0.5,
                         RECT.w + pad * 2, RECT.h + pad * 2,
                         8, 8, 7, F.backingAlpha or 214)
            end

            if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) then
                closeMap()
            elseif IsControlJustPressed(0, 241) then
                zoom = math.max(ZOOM_MIN, zoom - 60.0)
                pcall(SetRadarZoom, math.floor(zoom))
            elseif IsControlJustPressed(0, 242) then
                zoom = math.min(ZOOM_MAX, zoom + 60.0)
                pcall(SetRadarZoom, math.floor(zoom))
            end
        else
            Wait(250)
        end
    end
end)

-- Never leave anything open behind.

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'fieldmap' and open then closeMap() end
end)

AddEventHandler('bs:hook:player:unloaded', closeMap)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    pcall(SetRadarBigmapEnabled, false, false)
    -- A blur left faded in is a permanent soft-focus game.
    pcall(TriggerScreenblurFadeOut, 0)
end)

-- Dying with the map up must not strand it on screen.
CreateThread(function()
    while true do
        Wait(500)
        if open and IsPedDeadOrDying(PlayerPedId(), true) then closeMap() end
    end
end)

exports('OpenFieldMap', function() CreateThread(openMap) end)
exports('CloseFieldMap', closeMap)
exports('IsFieldMapOpen', function() return open end)
