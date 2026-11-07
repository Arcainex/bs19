local busy = false

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        if ped ~= 0 then
            local here = GetEntityCoords(ped)
            local dist = #(here - PersonalStorage.Position)

            if dist < 12.0 then
                sleep = 0
                if dist <= PersonalStorage.InteractDistance then
                    BeginTextCommandDisplayHelp('STRING')
                    -- Alpha-Z olive accent for the storage name. ~v~ uses the script-variable HUD colour.
                    SetScriptVariableHudColour(126, 128, 62, 255)
                    AddTextComponentSubstringPlayerName('Drücke ~INPUT_CONTEXT~ um dein ~v~persönliches Lager~s~ zu öffnen')
                    -- beep=false: no frontend sound when entering/showing the storage interaction zone.
                    EndTextCommandDisplayHelp(0, false, false, -1)

                    if IsControlJustReleased(0, 38) and not busy then
                        busy = true
                        TriggerServerEvent('bs:personalStorage:open')
                        SetTimeout(750, function() busy = false end)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
