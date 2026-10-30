-- bs_pause - our ESC menu. Takes over ESC/P (controls 200/199) while a character is loaded and no other menu has focus.
-- Map and GTA settings open the vanilla pause menu; while it is up we leave ESC alone so it closes normally.
-- Other resources add buttons with exports.bs_pause:AddPauseTab({ id, label, icon, order, event, closeMenu }).

local open = false
local quietUntil = 0
local tabs = {}         -- [id] = def
local PAUSE_MENU = GetHashKey('FE_MENU_VERSION_SP_PAUSE')

local function send(p) SendNUIMessage(p) end
local function started(res) return GetResourceState(res) == 'started' end
local function now() return GetGameTimer() end

-- Locale key or plain text.
local function T(v)
    if type(v) ~= 'string' then return '' end
    local t = L(v)
    return t ~= v and t or v
end

local function tabList()
    local out = {}
    for _, d in pairs(tabs) do
        out[#out + 1] = { id = d.id, label = T(d.label), icon = d.icon, order = d.order or 50, badge = d.badge }
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

-- Real key for a command, read from the game so player rebinds show up.
local function boundKey(cmd, fallback)
    local ok, s = pcall(GetControlInstructionalButton, 0, GetHashKey(cmd) | 0x80000000, true)
    if ok and type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    if ok and type(s) == 'string' and s:sub(1, 2) == 'b_' then return fallback end
    return fallback
end

local function keybinds()
    local out = {}
    for _, k in ipairs(Pause.Keybinds or {}) do
        out[#out + 1] = { label = T(k.label), key = boundKey(k.cmd, k.key) }
    end
    return out
end

local function playerSettings()
    if not started('bs_inventory') then return {} end
    local ok, s = pcall(function() return exports.bs_inventory:GetPlayerSettings() end)
    return ok and s or {}
end

-- HUD styles and menu palettes from bs_ui, with VIP flags.
local function uiChoices()
    if not started('bs_ui') then return nil end
    local ok, v = pcall(function() return exports.bs_ui:UiChoices() end)
    return ok and v or nil
end

local function staticInfo()
    local rules, news = {}, {}
    for _, r in ipairs(Pause.Rules or {}) do rules[#rules + 1] = T(r) end
    for _, n in ipairs(Pause.News or {}) do news[#news + 1] = { date = n.date, title = T(n.title), text = T(n.text) } end
    return {
        rules = rules, news = news, discord = Pause.Settings.discord, website = Pause.Settings.website,
        devlog = Pause.Settings.devlog and Pause.Settings.devlogUrl or nil,
    }
end

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local function closeMenu(silent)
    if not open then return end
    open = false
    quietUntil = now() + 400
    setFocus(false)
    if Pause.Settings.blur then TriggerScreenblurFadeOut(200) end
    send({ action = 'close' })
    if not silent then TriggerEvent('bs:ui:closed', 'pause') end
end

local function openMenu()
    if open then return end
    open = true
    TriggerEvent('bs:ui:opened', 'pause')
    if Pause.Settings.blur then TriggerScreenblurFadeIn(250) end
    setFocus(true)
    send({
        action = 'open', strings = BSLocale.Dict(BSLocale.Lang()), tabs = tabList(),
        settings = playerSettings(), presets = PausePresets.Get(), keybinds = keybinds(),
        info = staticInfo(), languages = BSLocale.Languages, native = BSLocale.Native,
        choices = uiChoices(),
    })
    CreateThread(function()
        local info = BSB.Await('pause:info', 5000)
        if open and info then send({ action = 'serverInfo', info = info }) end
    end)
end

local function openVanilla(component)
    closeMenu()
    quietUntil = now() + 800
    CreateThread(function()
        Wait(50)
        pcall(ActivateFrontendMenu, PAUSE_MENU, false, component or -1)
    end)
end

local function canOpen()
    if not Pause.Settings.enabled or open then return false end
    if now() < quietUntil then return false end
    if not exports.bs_core:IsLoaded() then return false end
    if IsNuiFocused() or IsPauseMenuActive() then return false end
    if LocalPlayer.state.bs_tutorial then return false end
    return true
end

-- Loaded state, polled slowly so the frame loop below does not call an export every frame.
local loaded = false
CreateThread(function()
    while true do
        loaded = exports.bs_core:IsLoaded() == true
        Wait(500)
    end
end)

-- ESC / P takeover.
CreateThread(function()
    while true do
        if Pause.Settings.enabled and loaded and not LocalPlayer.state.bs_tutorial then
            if IsPauseMenuActive() then
                quietUntil = now() + 500
                Wait(100)
            else
                DisableControlAction(0, 200, true)
                DisableControlAction(0, 199, true)
                if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 199) then
                    if canOpen() then openMenu() end
                end
                Wait(0)
            end
        else
            Wait(250)
        end
    end
end)

-- One menu at a time.
AddEventHandler('bs:ui:opened', function(what) if what ~= 'pause' and open then closeMenu() end end)
AddEventHandler('bs:ui:closed', function() quietUntil = math.max(quietUntil, now() + 350) end)
AddEventHandler('bs:ui:requestClose', function(who) if who ~= 'pause' and open then closeMenu() end end)
AddEventHandler('bs:ui:panic', function() open = true; closeMenu(true) end)
AddEventHandler('bs:hook:player:unloaded', function() closeMenu(true) end)

-- NUI

RegisterNUICallback('close', function(_, cb) cb({}); closeMenu() end)

RegisterNUICallback('map', function(_, cb) cb({}); openVanilla(4) end)
RegisterNUICallback('gta', function(_, cb) cb({}); openVanilla(-1) end)
RegisterNUICallback('quit', function(_, cb) cb({}); closeMenu(); TriggerServerEvent('bs:pause:quit') end)

RegisterNUICallback('settings', function(data, cb)
    if started('bs_inventory') and type(data) == 'table' and type(data.patch) == 'table' then
        local ok, err = pcall(function() exports.bs_inventory:ApplyPlayerSettings(data.patch) end)
        if not ok then print(('^3[bs_pause] settings apply failed: %s^7'):format(tostring(err))) end
    end
    cb({ settings = playerSettings() })
    -- A language change reloads the strings.
    if type(data) == 'table' and type(data.patch) == 'table' and data.patch.language then
        CreateThread(function()
            Wait(600)
            if open then send({ action = 'strings', strings = BSLocale.Dict(BSLocale.Lang()), tabs = tabList(), keybinds = keybinds(), info = staticInfo() }) end
        end)
    end
end)

RegisterNUICallback('fix', function(data, cb)
    cb({})
    local name = type(data) == 'table' and data.name or nil
    if name == 'refreshtextures' then
        closeMenu()
        pcall(function() exports.bs_core:RefreshTextures() end)
        return
    end
    if started('bs_inventory') then pcall(function() exports.bs_inventory:RunSettingsAction(name) end) end
end)

RegisterNUICallback('presets', function(data, cb)
    local ok, err = pcall(PausePresets.Set, type(data) == 'table' and data.patch or nil)
    if not ok then print(('^3[bs_pause] preset apply failed: %s^7'):format(tostring(err))) end
    cb({ presets = PausePresets.Get() })
end)

RegisterNUICallback('tab', function(data, cb)
    cb({})
    local def = tabs[type(data) == 'table' and data.id or '']
    if not def then return end
    if def.closeMenu ~= false then closeMenu() end
    if def.event then TriggerEvent(def.event, def.id) end
    if type(def.onSelect) == 'function' or type(def.onSelect) == 'table' then pcall(def.onSelect, def.id) end
end)

-- Exports for other resources

local function refreshTabs() if open then send({ action = 'tabs', tabs = tabList() }) end end

--- def = { id, label (locale key of the calling resource is not visible here, so pass translated text), icon, order, event, closeMenu, badge, onSelect }
exports('AddPauseTab', function(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or def.id == '' then return false end
    tabs[def.id] = {
        id = def.id:sub(1, 32), label = tostring(def.label or def.id):sub(1, 40), icon = def.icon and tostring(def.icon):sub(1, 16) or nil,
        order = tonumber(def.order) or 50, event = type(def.event) == 'string' and def.event or nil,
        closeMenu = def.closeMenu, badge = def.badge and tostring(def.badge):sub(1, 12) or nil,
        onSelect = def.onSelect, owner = GetInvokingResource(),
    }
    refreshTabs()
    return true
end)

exports('RemovePauseTab', function(id) tabs[tostring(id)] = nil; refreshTabs() end)
exports('SetPauseTabBadge', function(id, badge)
    local d = tabs[tostring(id)]
    if d then d.badge = badge and tostring(badge):sub(1, 12) or nil; refreshTabs() end
end)
exports('IsPauseOpen', function() return open end)
exports('OpenPause', function() if canOpen() then openMenu() end end)
exports('ClosePause', function() closeMenu() end)

-- Tabs vanish with the resource that added them.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if open then setFocus(false); TriggerScreenblurFadeOut(0) end
        return
    end
    local changed = false
    for id, d in pairs(tabs) do if d.owner == res then tabs[id] = nil; changed = true end end
    if changed then refreshTabs() end
end)
