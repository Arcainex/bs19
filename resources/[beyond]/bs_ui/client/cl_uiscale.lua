-- bs_ui - per-player NUI scale for html/shared/scale.js. 0 = auto (fit 1920x1080), 0.6-1.4 = fixed. Stored in client KVP; pages poll the `uiScaleGet` callback (https://bs_ui/uiScaleGet).

local KVP = 'bs_ui_scale'
local MIN, MAX = 0.6, 1.4

local function sanitize(v)
    v = tonumber(v) or 0
    if v <= 0 then return 0 end
    v = math.max(MIN, math.min(MAX, v))
    return math.floor(v * 100 + 0.5) / 100
end

local current = sanitize(GetResourceKvpFloat(KVP))

local function set(v)
    current = sanitize(v)
    SetResourceKvpFloat(KVP, current)
    SendNUIMessage({ action = 'bsUiScale', scale = current })
    TriggerEvent('bs:ui:scaleChanged', current)
    return current
end

RegisterNUICallback('uiScaleGet', function(_, cb)
    cb({ ok = true, scale = current })
end)

-- Menu palette for html/shared/palette.js. vars = false means each menu keeps its own colours.
RegisterNUICallback('uiPaletteGet', function(_, cb)
    local id, vars = 'default', nil
    if HudEffectivePalette then id, vars = HudEffectivePalette() end
    cb({ ok = true, id = id, vars = vars or false })
end)

RegisterNUICallback('uiScaleSet', function(data, cb)
    local v = type(data) == 'table' and data.scale or 0
    cb({ ok = true, scale = set(v) })
end)

exports('GetUiScale', function() return current end)
exports('SetUiScale', function(v) return set(v) end)

RegisterCommand('uiscale', function(_, args)
    local a = args[1]
    if not a or a == 'auto' or a == '0' then
        set(0)
        print('[bs_ui] UI scale: auto')
    else
        local v = set(a)
        print(('[bs_ui] UI scale: %s'):format(v == 0 and 'auto' or tostring(v)))
    end
end, false)
TriggerEvent('chat:addSuggestion', '/uiscale', L('ui.sugg_uiscale'), { { name = 'scale', help = L('ui.sugg_uiscale_arg') } })
