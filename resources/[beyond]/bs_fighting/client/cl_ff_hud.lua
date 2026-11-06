-- bs_fighting v3 - HUD bridge: combo counter, counter prompt, finisher tag, flashes.
-- Player settings come from bs_ui (Settings > Gameplay): fightHud off/minimal/full, fightCombo, fightParry.

FFHud = {}

local prefs = { mode = 'minimal', combo = true, flash = true }

local function readPrefs(s)
    if type(s) ~= 'table' then
        local ok, got = pcall(function() return exports.bs_ui:GetHudSettings() end)
        s = ok and got or {}
    end
    local mode = s.fightHud
    if mode ~= 'full' and mode ~= 'off' and mode ~= 'minimal' then mode = 'minimal' end
    prefs.mode, prefs.combo, prefs.flash = mode, s.fightCombo ~= false, s.fightParry ~= false
    SendNUIMessage({ action = 'prefs', prefs = prefs, labels = {
        hits = L('hud.hits'), counter = L('prompt.counter'), finisher = L('hud.finisher'), locked = L('hud.locked'),
    } })
end

AddEventHandler('bs:ui:settingsChanged', function(s) readPrefs(s) end)
AddEventHandler('bs:hook:player:spawned', function() readPrefs() end)
CreateThread(function() Wait(3000) readPrefs() end)

function FFHud.Combo(n)
    if prefs.mode == 'off' or not prefs.combo then return end
    SendNUIMessage({ action = 'combo', n = n })
end

-- key prompt with a ring that empties over the window. key = the bound key label.
function FFHud.Counter(on, ms, key)
    if prefs.mode == 'off' and on then return end
    SendNUIMessage({ action = 'counter', on = on and true or false, ms = ms or 0, key = key or 'E' })
end

function FFHud.Finisher(on)
    if prefs.mode == 'off' and on then return end
    SendNUIMessage({ action = 'finisher', on = on and true or false })
end

function FFHud.Locked(on)
    if prefs.mode == 'off' and on then return end
    SendNUIMessage({ action = 'locked', on = on and true or false })
end

function FFHud.Flash(kind)
    if prefs.mode == 'off' or not prefs.flash then return end
    SendNUIMessage({ action = 'flash', kind = kind, label = L('hud.' .. kind) })
end

function FFHud.Impact(strength)
    if not (Fighting.Settings and Fighting.Settings.sound) then return end
    SendNUIMessage({ action = 'impact', s = strength or 0.5, vol = Fighting.Settings.soundVolume or 0.6 })
end
