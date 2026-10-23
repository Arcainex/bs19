-- bs_vehicles - vanilla station music is muted

CreateThread(function()
    SetUserRadioControlEnabled(true)
    while true do
        if GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then
            if not IsAudioSceneActive('CAR_MOD_RADIO_MUTE_SCENE') then
                StartAudioScene('CAR_MOD_RADIO_MUTE_SCENE')
            end
            Wait(250)
        else
            if IsAudioSceneActive('CAR_MOD_RADIO_MUTE_SCENE') then
                StopAudioScene('CAR_MOD_RADIO_MUTE_SCENE')
            end
            Wait(500)
        end
    end
end)
