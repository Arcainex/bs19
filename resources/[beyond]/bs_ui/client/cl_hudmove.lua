-- bs_ui - move HUD elements: with the setting on, CTRL toggles a cursor so HUD pieces can be dragged.
-- Positions live in the NUI (localStorage) with a KVP copy here as fallback.

local KVP_ON, KVP_POS = 'bs_hudmove_on', 'bs_hudpos'
local enabled = GetResourceKvpInt(KVP_ON) == 1 -- default OFF
local active = false

local function setActive(on)
    on = on and true or false
    if on == active then return end
    active = on
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(on)
    SendNUIMessage({ action = 'hudMove', on = on })
end

exports('GetMoveHud', function() return enabled end)
exports('SetMoveHud', function(v)
    enabled = v == true
    SetResourceKvpInt(KVP_ON, enabled and 1 or 2)
    if not enabled then setActive(false) end
end)

RegisterNUICallback('hudPosSave', function(data, cb)
    if type(data) == 'table' and type(data.pos) == 'table' then
        SetResourceKvp(KVP_POS, json.encode(data.pos))
    end
    cb({ ok = true })
end)
RegisterNUICallback('hudMoveExit', function(_, cb) setActive(false); cb({ ok = true }) end)

-- hand the saved layout to the page (it prefers its own localStorage copy)
CreateThread(function()
    local raw = GetResourceKvpString(KVP_POS)
    local pos = raw and json.decode(raw) or nil
    for _ = 1, 4 do
        Wait(2500)
        SendNUIMessage({ action = 'hudPos', pos = pos or {} })
    end
end)

AddEventHandler('bs:ui:opened', function() setActive(false) end)

CreateThread(function()
    while true do
        if not enabled then
            Wait(500)
        else
            Wait(0)
            if active then
                DisableControlAction(0, 1, true); DisableControlAction(0, 2, true)
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                DisableControlAction(0, 142, true); DisableControlAction(0, 106, true)
                if not IsNuiFocused() or IsPauseMenuActive() or IsDisabledControlJustPressed(0, 200) then
                    setActive(false)
                elseif IsDisabledControlJustPressed(0, 36) or IsControlJustPressed(0, 36) then
                    setActive(false)
                end
            elseif not IsNuiFocused() and not IsPauseMenuActive() and IsControlJustPressed(0, 36) then
                setActive(true)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() and active then SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end
end)
