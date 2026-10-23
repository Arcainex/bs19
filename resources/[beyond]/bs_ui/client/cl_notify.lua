-- Cross-resource rule: talk to bs_core through exports (values) and 'bs:hook:*' events (callbacks). Lua functions don't survive export marshalling.

local Events = exports.bs_core:GetEvents()

--- payload: { type = 'info'|'success'|'warn'|'error', title, message, duration, icon }
-- Toasts are dropped while a full-screen scene owns the screen (the tutorial tour).
local muteFor = { tutorial = true }
local muted = nil
AddEventHandler('bs:ui:opened', function(panel) if panel and muteFor[panel] then muted = panel end end)
AddEventHandler('bs:ui:closed', function(panel) if panel == nil or panel == muted then muted = nil end end)
AddEventHandler('bs:ui:panic', function() muted = nil end)
exports('SetNotificationsMuted', function(on) muted = on and 'manual' or nil end)

function Notify(payload)
    if muted then return end
    if type(payload) == 'string' then payload = { message = payload } end
    Nui.Send({
        action = 'notify',
        notification = {
            type     = payload.type or 'info',
            title    = payload.title,
            message  = payload.message or '',
            -- Guarded as well as configured so a missing config table can't swallow every toast.
            duration = payload.duration
                or (UI.Notifications and UI.Notifications.defaultDuration)
                or 3200,
            icon     = payload.icon,
        },
    })
end

RegisterNetEvent(Events.UiNotify, function(payload) Notify(payload) end)

exports('Notify', Notify)

AddEventHandler('bs:hook:player:levelUp', function(level)
    Notify({
        type = 'success',
        title = L('ui.level_up'),
        message = L('ui.reached_level', { n = level }),
        duration = 6000,
    })
end)

AddEventHandler('bs:hook:player:money', function(account, _, delta)
    if not delta or delta == 0 then return end
    Notify({
        type = delta > 0 and 'success' or 'warn',
        message = ('%s%s%d'):format(delta > 0 and '+' or '-', UI.Settings.currencySymbol, math.abs(delta)),
        duration = 2500,
    })
end)

-- Chat box: the base `chat` resource binds L to toggleChat and saves the state in KVP, which can leave chat hidden. We can't write that KVP, so a hint is shown once on first spawn (T opens chat, L cycles visibility).

local toldAboutChat = false

AddEventHandler('bs:hook:player:spawned', function()
    if toldAboutChat then return end
    toldAboutChat = true

    if GetResourceState('chat') ~= 'started' then return end

    CreateThread(function()
        Wait(4000)
        Notify({
            type = 'info',
            title = L('ui.chat_title'),
            message = L('ui.chat_hint'),
            duration = 7000,
        })
    end)
end)
