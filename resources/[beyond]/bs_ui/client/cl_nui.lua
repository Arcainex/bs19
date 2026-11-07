-- BeyondSurvival - one NUI frame for the whole interface. Panels are routed by an `action` field, so there is only one browser instance.

local Events = exports.bs_core:GetEvents()

Nui = { focused = false, openPanel = nil }

function Nui.Send(payload)
    SendNUIMessage(payload)
end

function Nui.SetFocus(state, cursor)
    Nui.focused = state and true or false
    SetNuiFocus(Nui.focused, cursor ~= false and Nui.focused or false)
    SetNuiFocusKeepInput(false)
end

function Nui.Open(panel, data)
    Nui.openPanel = panel
    Nui.Send({ action = 'open', panel = panel, data = data })
    Nui.SetFocus(true, true)
    TriggerEvent('bs:ui:opened', panel)
end

function Nui.Close(panel)
    Nui.openPanel = nil
    Nui.Send({ action = 'close', panel = panel })
    Nui.SetFocus(false)
    TriggerEvent('bs:ui:closed', panel)
end

RegisterNUICallback('close', function(data, cb)
    Nui.Close(data and data.panel)
    cb({ ok = true })
end)

-- Names the bs_ui page may reach through the bridge. None yet; add a name when a panel needs one.
local CallbackAllow = {}

-- Generic bridge so panels can hit server callbacks without new Lua per panel.
RegisterNUICallback('callback', function(data, cb)
    local name = type(data) == 'table' and data.callback or nil
    if type(name) ~= 'string' or not CallbackAllow[name] then
        return cb({ ok = false, error = 'callback not allowed' })
    end
    if type(data.args) ~= 'table' then data.args = {} end
    CreateThread(function()
        local result = BSB.Await(data.callback, 10000, table.unpack(data.args or {}))
        cb(result or { ok = false, error = 'no response' })
    end)
end)

RegisterNetEvent(Events.UiOpen,  function(panel, data) Nui.Open(panel, data) end)
RegisterNetEvent(Events.UiClose, function(panel) Nui.Close(panel) end)

-- Escape always releases focus so a broken panel can never trap the player.
CreateThread(function()
    while true do
        Wait(0)
        if Nui.focused then
            if IsControlJustReleased(0, 200) then Nui.Close(Nui.openPanel) end
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)

-- /refreshui - panic button for every player. Drops NUI focus no matter what is thought to be open and tells every NUI-owning resource to close its panels, so a stuck panel does not need a relog.
RegisterCommand('refreshui', function()
    Nui.openPanel = nil
    SendNUIMessage({ action = 'close' })
    Nui.SetFocus(false)
    TriggerEvent('bs:ui:panic')
    TriggerEvent('bs:ui:closed', nil)
    TriggerEvent('bs:ui:notify', {
        type = 'info', message = L('ui.reset'), duration = 2200,
    })
end, false)

exports('Open', Nui.Open)
exports('Close', Nui.Close)
exports('Send', Nui.Send)
exports('IsFocused', function() return Nui.focused end)
