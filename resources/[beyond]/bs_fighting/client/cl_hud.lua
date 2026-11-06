-- bs_fighting - small HUD: combo counter, block/parry flash, style tag. Player settings live in bs_ui (Settings > Gameplay).

FightHud = {}

local prefs = { mode = 'minimal', combo = true, parry = true, style = true }

local function readPrefs(s)
    if type(s) ~= 'table' then
        local ok, got = pcall(function() return exports.bs_ui:GetHudSettings() end)
        s = ok and got or {}
    end
    local mode = s.fightHud
    if mode ~= 'full' and mode ~= 'off' and mode ~= 'minimal' then mode = 'minimal' end
    prefs.mode  = mode
    prefs.combo = s.fightCombo ~= false
    prefs.parry = s.fightParry ~= false
    prefs.style = s.fightStyle ~= false
    SendNUIMessage({ action = 'prefs', prefs = prefs })
end

AddEventHandler('bs:ui:settingsChanged', function(s) readPrefs(s) end)
AddEventHandler('bs:hook:player:spawned', function() readPrefs() end)
CreateThread(function() Wait(3000) readPrefs() end)

function FightHud.Off() return prefs.mode == 'off' end

function FightHud.Combo(n)
    if prefs.mode == 'off' or not prefs.combo then return end
    SendNUIMessage({ action = 'combo', n = n })
end

function FightHud.Flash(kind)
    if prefs.mode == 'off' or not prefs.parry then return end
    SendNUIMessage({ action = 'flash', kind = kind, label = L('hud.' .. kind) })
end

function FightHud.Style(id, sticky)
    if prefs.mode == 'off' or not prefs.style then return end
    local s = Fighting.Styles[id]
    SendNUIMessage({ action = 'style', id = id, icon = s and s.icon or 'fist', label = L('style.' .. id), sticky = sticky == true })
end

function FightHud.Active(on)
    SendNUIMessage({ action = 'active', on = on and true or false })
end

-- charge meter while holding attack (0..1, nil hides it)
function FightHud.Charge(frac)
    if prefs.mode == 'off' then return end
    SendNUIMessage({ action = 'charge', v = frac })
end

-- context prompt (stomp, takedown)
local promptShown = nil
function FightHud.Prompt(key)
    if key == promptShown then return end
    promptShown = key
    if prefs.mode == 'off' and key then return end
    SendNUIMessage({ action = 'prompt', text = key and L('prompt.' .. key) or nil })
end

-- impact thump, made in the page (no sound files)
function FightHud.Impact(strength)
    if not Fighting.Settings.sound then return end
    SendNUIMessage({ action = 'impact', s = strength or 0.5, vol = Fighting.Settings.soundVolume or 0.6 })
end
