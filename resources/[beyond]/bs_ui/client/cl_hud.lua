-- bs_ui - HUD driver. Pushes state to the NUI on a timer, hides the vanilla minimap and replaced HUD components, and re-applies saved player preferences (mode, anchor, opacity, XP bar) on spawn.

local visible = false
local settings = nil          -- resolved player preferences
local minimapForced = false   -- true while something wants the map back
local bigmapForced = false    -- true while something wants the EXPANDED map

local function send(p) SendNUIMessage(p) end

-- Preferences

local function defaults()
    return {
        hudMode      = UI.Settings.hudMode,
        hudAnchor    = UI.Settings.hudAnchor,
        hudOpacity   = UI.Settings.hudOpacity,
        hideWhenFull = UI.Settings.hideWhenFull,
        xpPosition   = UI.XPBar.position,
        xpOpacity    = UI.XPBar.opacity,
        xpPopups     = UI.XPBar.popups,
        hudStyle     = 'classic',   -- status HUD look, see UI.HudStyles
        menuPalette  = 'default',   -- menu colours, see UI.Palettes
        dodge        = true,   -- Shift + double-tap roll (bs_skills); a player can switch it off

        -- Personal screen filter (see cl_filter.lua), stored with the other per-character display preferences.
        filter         = UI.FilterDefaults.filter,
        filterStrength = UI.FilterDefaults.filterStrength,

        -- Zombie voice volume. Must be in this table or it is never pushed to the page nor saved, and the slider (read by cl_sound.lua, default 0.15) does nothing.
        zombieVoiceVolume = UI.Settings.zombieVoiceVolume,
    }
end

-- VIP lookup. With the VIP system off bs_vip reports everyone as VIP, so locks open by themselves.
local function isVip()
    if GetResourceState('bs_vip') ~= 'started' then return false end
    local ok, v = pcall(function() return exports.bs_vip:IsVIP() end)
    return ok and v == true
end

local function findDef(list, id)
    for _, d in ipairs(list or {}) do
        if d.id == id then return d end
    end
end

-- A VIP look the player cannot use falls back to the default; the saved choice is kept.
local function effective(list, id, fallback)
    local d = findDef(list, id)
    if not d or (d.vip and not isVip()) then return fallback end
    return id
end

function HudEffectivePalette()
    local id = effective(UI.Palettes, settings and settings.menuPalette, 'default')
    local d = findDef(UI.Palettes, id)
    return id, d and d.vars or nil
end

local function pushSettings()
    -- Filter is applied here because every settings change (settings pane, spawn hook, cinematic camera picker) ends up in this function. Guarded on the global so the HUD still works if cl_filter.lua failed to load.
    if FilterApply then
        FilterApply(settings and settings.filter, settings and settings.filterStrength)
    end

    local shown = {}
    for k, v in pairs(settings or {}) do shown[k] = v end
    shown.hudStyle = effective(UI.HudStyles, shown.hudStyle, 'classic')
    local palId, palVars = HudEffectivePalette()
    shown.menuPalette = palId

    send({
        action   = 'settings',
        settings = shown,
        paletteVars = palVars or false,
        theme    = UI.Theme,
        bars     = UI.Bars,
        minimal  = UI.MinimalBars,
        xp       = UI.XPBar,
    })

    -- Raise bs:ui:settingsChanged for listeners such as the zombie mixer in cl_sound.lua. Fired last, after the page is updated, so a throwing handler cannot cost the HUD its update.
    TriggerEvent('bs:ui:settingsChanged', settings)
end

-- Merges a partial update, applies it and saves it to the character.
function HudApplySettings(patch, persist)
    settings = settings or defaults()
    for k, v in pairs(patch or {}) do
        if k == 'hudStyle' or k == 'menuPalette' then
            -- unknown ids and locked VIP looks are ignored
            local def = findDef(k == 'hudStyle' and UI.HudStyles or UI.Palettes, v)
            if def and (not def.vip or isVip()) then settings[k] = v end
        else
            settings[k] = v
        end
    end
    pushSettings()

    if persist then
        CreateThread(function() BSB.Await('core:saveHudSettings', 5000, settings) end)
    end
    return settings
end

exports('ApplyHudSettings', function(patch, persist) return HudApplySettings(patch, persist) end)
exports('GetHudSettings', function() return settings or defaults() end)

-- Lists for the settings screens (inventory, pause). vip = whether the locks are open for this player.
exports('UiChoices', function()
    local pal = {}
    for _, d in ipairs(UI.Palettes) do
        local v = d.vars
        pal[#pal + 1] = { id = d.id, label = d.label, vip = d.vip == true,
            sw = v and { v.accent, v.bg, v.text } or d.sw, vars = v }
    end
    local sty = {}
    for _, d in ipairs(UI.HudStyles) do sty[#sty + 1] = { id = d.id, label = d.label, vip = d.vip == true } end
    return { styles = sty, palettes = pal, vip = isVip() }
end)

-- Resolved settings for same-resource callers (cl_filter). A global rather than an export to avoid serialisation cost.
function HudGetSettings() return settings or defaults() end

-- Minimap

-- Turns the game's radar on/off. The paper frame around it is drawn by the NUI, since the page cannot recolour the radar itself. The vanilla ring, health bar and sonar cone are removed and zoom is pulled back.
-- @param show boolean turn the vanilla radar on/off.
-- @param showFrame boolean|nil whether the corner paper-frame follows it (default true). The field map passes false because it moves the radar to its own box (HudSetMinimapRect) while the corner frame is pinned in CSS. See openMap() in cl_fieldmap.lua.
function HudSetMinimap(show, showFrame)
    minimapForced = show and true or false
    if showFrame == nil then showFrame = true end

    local visible = minimapForced or not UI.Minimap.alwaysHidden
    DisplayRadar(visible)

    -- The frame follows the map unless the caller opts out (the field map).
    send({ action = 'mapframe', show = visible and showFrame })

    -- Whoever relocated the map (the inventory's MAP tab) is done when it turns off; put it back in its normal place.
    if not visible then HudResetMinimapRect() end
end

-- Strip vanilla map pieces. Re-applied on a loop because the engine restores several on respawn and interior transitions.
CreateThread(function()
    while true do
        Wait(1500)

        -- Health/armour ring around the minimap.
        pcall(SetMinimapComponent, 13, false)   -- ring
        pcall(SetMinimapComponent, 14, false)
        pcall(SetMinimapComponent, 15, false)

        -- Square map instead of the round one. Skipped while the field map wants the expanded view, or this thread would force it back off.
        if not bigmapForced then
            pcall(SetRadarBigmapEnabled, false, false)
            -- Zoom pulled back (default 900; GTA's default is too zoomed in, 1100 too far out). Configurable via UI.Minimap.zoom.
            pcall(SetRadarZoom, UI.Minimap.zoom or 900)
        end
    end
end)

-- Expanded map. This no longer calls SetRadarBigmapEnabled: in bigmap mode the game ignores SetMinimapComponentPosition, so the custom rect never applied.
-- Instead the normal radar component is resized through HudSetMinimapRect, and this only sets the flag the strip-back thread checks so its zoom reset does not fight the field map's scroll-to-zoom.
function HudSetBigmap(on)
    bigmapForced = on and true or false
end

exports('SetBigmap', HudSetBigmap)

-- Relocate the radar (SET_MINIMAP_COMPONENT_POSITION). Coordinates are screen fractions (0..1, top-left origin), so callers can pass getBoundingClientRect() values straight through.
local DEFAULT_MINIMAP = { alignX = 'L', alignY = 'B', pivotX = 0.0, pivotY = -0.047, sizeX = 0.1638, sizeY = 0.183 }
local customRect = nil     -- non-nil while something has relocated the map

-- Moves the whole radar (map, mask and glow) to one rect. Moving only `minimap` does not work; see the note below HudSetMinimapRect.
local function applyRect(r)
    -- Square clip so a big map is not cut into a circle inside the rectangular frame.
    pcall(SetMinimapClipType, 1)
    pcall(SetMinimapComponentPosition, 'minimap',      'L', 'T', r.x, r.y, r.w, r.h)
    pcall(SetMinimapComponentPosition, 'minimap_mask', 'L', 'T', r.x, r.y, r.w, r.h)
    -- The glow overhangs the window rather than sitting on it.
    pcall(SetMinimapComponentPosition, 'minimap_blur', 'L', 'T',
        r.x - 0.01, r.y - 0.01, r.w + 0.02, r.h + 0.02)
end

-- The vanilla radar is three scaleform components: minimap (imagery), minimap_mask (visible window) and minimap_blur (glow). All three must move together, otherwise the map is moved but still masked to the corner and shows an empty box. The glow gets a slightly larger rect.

-- @param rect table|nil { x, y, w, h } as 0..1 screen fractions, top-left origin. Falls back to the vanilla corner if nil.
function HudSetMinimapRect(rect)
    if type(rect) ~= 'table' or not rect.w or not rect.h then
        customRect = nil
        return HudResetMinimapRect()
    end

    customRect = {
        x = tonumber(rect.x) or 0.0, y = tonumber(rect.y) or 0.0,
        w = tonumber(rect.w) or DEFAULT_MINIMAP.sizeX, h = tonumber(rect.h) or DEFAULT_MINIMAP.sizeY,
    }
    applyRect(customRect)
end

-- Back to the default GTA position. Call when whoever moved the map is done. Resets all three components.
function HudResetMinimapRect()
    customRect = nil
    pcall(SetMinimapComponentPosition, 'minimap', DEFAULT_MINIMAP.alignX, DEFAULT_MINIMAP.alignY,
        DEFAULT_MINIMAP.pivotX, DEFAULT_MINIMAP.pivotY, DEFAULT_MINIMAP.sizeX, DEFAULT_MINIMAP.sizeY)
    pcall(SetMinimapComponentPosition, 'minimap_mask', DEFAULT_MINIMAP.alignX, DEFAULT_MINIMAP.alignY,
        DEFAULT_MINIMAP.pivotX, DEFAULT_MINIMAP.pivotY, DEFAULT_MINIMAP.sizeX, DEFAULT_MINIMAP.sizeY)
    pcall(SetMinimapComponentPosition, 'minimap_blur', DEFAULT_MINIMAP.alignX, DEFAULT_MINIMAP.alignY,
        DEFAULT_MINIMAP.pivotX, DEFAULT_MINIMAP.pivotY, DEFAULT_MINIMAP.sizeX, DEFAULT_MINIMAP.sizeY)
    pcall(SetMinimapClipType, 0)
end

-- Reassert the custom rect every frame while one is active; the engine can reset HUD flags on its own and a one-shot call may silently show nothing.
CreateThread(function()
    while true do
        if customRect then
            applyRect(customRect)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

exports('SetMinimapRect', HudSetMinimapRect)
exports('ResetMinimapRect', HudResetMinimapRect)
exports('SetMinimap', HudSetMinimap)

AddEventHandler('bs:ui:opened', function(panel)
    if panel == 'inventory' and UI.Minimap.showWithInventory then HudSetMinimap(true) end
end)

-- Another panel closing must not switch the radar off while the field map owns it. openMap() turns the radar on, then announces bs:ui:opened, which makes other open panels close themselves and fire bs:ui:closed, which used to turn the radar off again.
-- bigmapForced is set only by the field map, so it doubles as "the field map owns the radar".
AddEventHandler('bs:ui:closed', function(panel)
    if bigmapForced and panel ~= 'fieldmap' then return end
    HudSetMinimap(false)
end)

-- State collection

-- The HUD hides while a full-screen panel is open, so the survival cluster does not duplicate the inventory's own stats block.
-- Driven by the existing bs:ui:opened/closed events. Which panels count is data: UI.HideHudFor in config_ui.lua (it stores the owning resource name too).
-- A hidden HUD is worse than an overlapping one, so every exit path is covered: matching bs:ui:closed, closed with no name (/refreshui), bs:ui:panic, player unload, death, and the owning resource no longer being 'started' (re-checked on the push loop).
-- No timeout, since players can sit in the inventory for minutes.
local hidePanel = nil    -- name of the open panel the HUD is standing down for

local function clearHidePanel() hidePanel = nil end

-- True while a listed panel is open and its owning resource is still running.
local function panelSuppressed()
    if not hidePanel then return false end

    local owner = (UI.HideHudFor or {})[hidePanel]
    if owner and GetResourceState(owner) ~= 'started' then
        clearHidePanel()
        return false
    end
    return true
end

AddEventHandler('bs:ui:opened', function(panel)
    if panel and (UI.HideHudFor or {})[panel] then hidePanel = panel end
end)

-- A nil panel name means everything is closed (/refreshui), so clear the latch too, otherwise the HUD stays hidden after the panic button.
AddEventHandler('bs:ui:closed', function(panel)
    if panel == nil or panel == hidePanel then clearHidePanel() end
end)

AddEventHandler('bs:ui:panic', clearHidePanel)

local function setVisible(state)
    if visible == state then return end
    visible = state
    send({ action = 'hud', visible = state })
end

local function collect()
    local ped = PlayerPedId()
    local data  = exports.bs_core:GetData() or {}
    local needs = exports.bs_core:GetNeeds() or {}

    -- GTA health runs 100..200 for a default ped; the bar wants 0..100.
    local maxHealth = GetEntityMaxHealth(ped)
    local health = math.max(0, GetEntityHealth(ped) - 100)
    local healthRange = math.max(1, maxHealth - 100)

    return {
        health    = math.floor(health / healthRange * 100),
        -- Real engine values for the readout (e.g. 200/200 for a Survivor), so the HUD agrees with the origin's HP stat.
        healthNow = math.max(0, GetEntityHealth(ped)),
        healthMax = maxHealth,
        armour    = math.floor(GetPedArmour(ped)),
        stamina   = math.floor(needs.stamina or 100),
        hunger    = math.floor(needs.hunger or 100),
        thirst    = math.floor(needs.thirst or 100),
        infection = math.floor(needs.infection or 0),

        level     = data.level or 1,
        xp        = data.xp or 0,
        xpToNext  = data.xpToNext or 1,
        cash      = (data.accounts and data.accounts.cash) or 0,
        name      = data.name,
        class     = data.class and data.class.label or nil,

        inVehicle = IsPedInAnyVehicle(ped, false),
        speed     = math.floor(GetEntitySpeed(ped) * 3.6),
    }
end

-- Loops

local lastHud, lastHudAt = nil, 0

CreateThread(function()
    settings = defaults()
    pushSettings()
    HudSetMinimap(false)

    while true do
        Wait(UI.Settings.hudPushRate or 200)

        local loaded = exports.bs_core:IsLoaded()

        if not UI.Settings.hudEnabled or not loaded then
            setVisible(false)
        else
            -- The pause menu always wins over the cutscene setting.
            -- Death releases the panel latch outright so the HUD is not suppressed after respawn.
            if IsEntityDead(PlayerPedId()) then clearHidePanel() end

            local hide = IsPauseMenuActive()
                or panelSuppressed()
                or (UI.Settings.hideInCutscene and IsCutsceneActive())
            setVisible(not hide)
            if not hide then
                -- Same numbers as last tick: skip the message, but refresh once a second.
                local d, now = collect(), GetGameTimer()
                local same = lastHud ~= nil and now - lastHudAt < 1000
                if same then
                    for k, v in pairs(d) do
                        if lastHud[k] ~= v then same = false break end
                    end
                end
                if not same then
                    lastHud, lastHudAt = d, now
                    send({ action = 'hudData', data = d })
                end
            else
                lastHud = nil
            end
        end
    end
end)

-- Vanilla HUD components the custom HUD replaces. Runs every frame because the engine re-enables them; not gated on the radar being forced, so opening the field map does not bring them back.
-- The health/armour bars belong to the minimap scaleform, so SetMinimapComponent 13/14/15 are also asserted every frame here.
CreateThread(function()
    while true do
        Wait(0)

        HideHudComponentThisFrame(19)   -- weapon wheel stats
        HideHudComponentThisFrame(20)   -- multiplayer cash
        HideHudComponentThisFrame(1)    -- wanted stars
        HideHudComponentThisFrame(2)    -- weapon icon
        HideHudComponentThisFrame(3)    -- cash
        HideHudComponentThisFrame(4)    -- mp cash
        HideHudComponentThisFrame(13)   -- cash change
        HideHudComponentThisFrame(7)    -- area name
        HideHudComponentThisFrame(9)    -- street name

        -- Ring, health bar and armour bar that ride along with the radar. Needed while the field map has the radar on.
        if minimapForced then
            SetMinimapComponent(13, false)
            SetMinimapComponent(14, false)
            SetMinimapComponent(15, false)
        end
    end
end)

-- Reactions

AddEventHandler('bs:hook:player:loaded', function(data)
    -- A character's saved layout wins over the server defaults.
    settings = defaults()
    for k, v in pairs((data and data.hudSettings) or {}) do settings[k] = v end
    pushSettings()
end)

-- VIP state changed (or the owner toggled the VIP system): re-evaluate locks.
AddEventHandler('bs:vip:changed', function()
    if settings then pushSettings() end
end)

AddEventHandler('bs:hook:player:unloaded', function()
    -- Nothing may carry a suppressed HUD across a character switch.
    clearHidePanel()
    setVisible(false)
    HudSetMinimap(false)
end)

-- XP popup: the moment the player sees the reward land.
AddEventHandler('bs:hook:player:xp', function(xp, xpToNext, level, gained)
    if not gained or gained <= 0 then return end
    send({ action = 'xpGain', amount = gained, xp = xp, xpToNext = xpToNext, level = level })
end)

-- The card is drawn here; the sequence (card, sound, music) is owned by cl_levelup.lua via bs:ui:levelCard.
AddEventHandler('bs:ui:levelCard', function(data)
    if type(data) ~= 'table' then return end
    send({
        action = 'levelUp',
        level  = data.level,
        from   = data.from,
        skill  = data.skill == true,
    })
end)

-- Remembers the previous level (bs:hook:player:levelUp only carries the new one) so the card can show the change.
local lastLevel = nil

-- Hook args are (xp, xpToNext, level, gained); level is the third (see BS.Emit('player:xp') in bs_core/client/cl_player.lua).
AddEventHandler('bs:hook:player:xp', function(_, _, level)
    if type(level) == 'number' then lastLevel = level end
end)

AddEventHandler('bs:hook:player:levelUp', function(level)
    local from = lastLevel
    lastLevel = level

    -- Never show "3 -> 3": a missing or stale previous level falls back to level - 1.
    if type(from) ~= 'number' or from >= level then from = level - 1 end

    if BSLevelUpSequence then
        BSLevelUpSequence(level, from)
    else
        send({ action = 'levelUp', level = level, from = from })
    end
end)

-- Commands (until the inventory Settings panel lands)

RegisterCommand('hud', function(_, args)
    local mode = args[1]
    if mode == 'full' or mode == 'minimal' then
        HudApplySettings({ hudMode = mode }, true)
    elseif mode == 'xp' and (args[2] == 'top' or args[2] == 'bottom') then
        HudApplySettings({ xpPosition = args[2] }, true)
    elseif mode == 'opacity' and tonumber(args[2]) then
        HudApplySettings({ hudOpacity = math.max(0.0, math.min(1.0, tonumber(args[2]))) }, true)
    else
        TriggerEvent('chat:addMessage', { args = { '^5[BS]',
            L('ui.hud_usage') } })
    end
end, false)
