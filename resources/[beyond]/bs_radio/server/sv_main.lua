-- bs_radio server: hands out the clock everyone's playback position is derived from.
GlobalState.bsRadioEpoch = os.time()

RegisterNetEvent('bs:radio:sync', function()
    TriggerClientEvent('bs:radio:clock', source, os.time())
end)

CreateThread(function()
    while true do
        Wait(60000)
        GlobalState.bsRadioEpoch = os.time()
    end
end)
