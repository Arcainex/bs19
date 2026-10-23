-- bs_ui - server-side notification helper other resources can call.

local Events = exports.bs_core:GetEvents()

--- exports.bs_ui:Notify(source, { type = 'success', title = ..., message = ... })
local function Notify(src, payload)
    if type(payload) == 'string' then payload = { message = payload } end
    TriggerClientEvent(Events.UiNotify, src, payload)
end

--- Same notification to everyone with a loaded character.
local function NotifyAll(payload)
    for src in pairs(exports.bs_core:GetPlayers() or {}) do Notify(src, payload) end
end

exports('Notify', Notify)
exports('NotifyAll', NotifyAll)

-- Registered as plain data: a module table containing functions does not survive the export boundary.
exports.bs_core:RegisterModule('ui', { side = 'server', version = '0.1.0' })
