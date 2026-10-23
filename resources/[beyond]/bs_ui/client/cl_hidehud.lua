-- bs_ui - /hidehud. Clean screen for screenshots: hides every HUD layer for a while, never persists.
-- Pages hide on the 'bsHideAll' NUI message (bs_ui, bs_inventory); other resources can listen to 'bs:hud:hideAll' (bool) or call exports.bs_ui:IsHudHidden().
-- Restores on: /hidehud again, any panel opening (inventory, pause, phone...), the GTA pause menu, death or downed, taking damage, 10 minutes, unload, resource stop.

local hidden = false
local hiddenAt = 0
local hintUntil = 0
local MAX_MS = 10 * 60 * 1000

local function setHidden(state)
    if hidden == state then return end
    hidden = state
    hiddenAt = GetGameTimer()
    hintUntil = state and (GetGameTimer() + 2000) or 0
    SendNUIMessage({ action = 'bsHideAll', hidden = state })
    TriggerEvent('bs:hud:hideAll', state)
    if GetResourceState('bs_inventory') == 'started' then TriggerEvent('bs:inventory:hideAll', state) end
    if GetResourceState('bs_chat') == 'started' then ExecuteCommand(state and 'chat hidden' or 'chat fade') end
    if state then TriggerEvent('bs:ui:opened', 'cinecam') else TriggerEvent('bs:ui:closed', 'cinecam') end
    if not state then DisplayHud(true); DisplayRadar(false) end
end

local function restore() setHidden(false) end

RegisterCommand('hidehud', function() setHidden(not hidden) end, false)
RegisterKeyMapping('hidehud', L('ui.hidehud_key'), 'keyboard', '')
CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/hidehud', L('ui.sugg_hidehud'))
end)

exports('IsHudHidden', function() return hidden end)
exports('SetHudHidden', function(state) setHidden(state == true) end)

-- Any panel opening brings the HUD back. The 'cinecam' pair is our own latch, so ignore it.
AddEventHandler('bs:ui:opened', function(panel) if hidden and panel ~= 'cinecam' then restore() end end)
AddEventHandler('bs:ui:panic', restore)
AddEventHandler('bs:hook:player:unloaded', restore)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and hidden then restore() end end)

local function drawHint()
    SetTextFont(4); SetTextScale(0.0, 0.38); SetTextColour(232, 226, 212, 220)
    SetTextOutline(); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(L('ui.hidehud_hint'))
    EndTextCommandDisplayText(0.5, 0.92)
end

CreateThread(function()
    local lastHealth = 0
    while true do
        if hidden then
            Wait(0)
            HideHudAndRadarThisFrame()
            DisplayHud(false)
            if GetGameTimer() < hintUntil then drawHint() end

            local ped = PlayerPedId()
            local hp = GetEntityHealth(ped) + GetPedArmour(ped)
            if IsEntityDead(ped) or LocalPlayer.state.bsDowned == true or IsPauseMenuActive()
                or IsNuiFocused() or (lastHealth > 0 and hp < lastHealth)
                or GetGameTimer() - hiddenAt > MAX_MS then
                restore()
            end
            lastHealth = hp
        else
            lastHealth = 0
            Wait(250)
        end
    end
end)
