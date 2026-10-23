-- bs_radio client: in a running vehicle with any station picked, the NUI plays the broadcast at (server time % duration).
-- Vanilla music is muted by bs_vehicles/cl_noradio, so every station sounds the same. Station OFF = silence.

local KVP_VOL = 'bs_radio_volume'
local clockEpoch, clockAt = nil, 0
local playing = false
local volume = GetResourceKvpInt(KVP_VOL)
local volumeSet = GetResourceKvpString(KVP_VOL .. '_set') == '1'

local function currentVolume()
    if volumeSet then return volume end
    return tonumber(Radio.Settings.defaultVolume) or 40
end

local function serverNow()
    if not clockEpoch then
        local e = GlobalState.bsRadioEpoch
        if not e then return nil end
        clockEpoch, clockAt = e, GetGameTimer()
    end
    return clockEpoch + (GetGameTimer() - clockAt) / 1000.0
end

local function position()
    local now = serverNow() or 0
    return now % (tonumber(Radio.duration) or 7220.62)
end

local function start()
    playing = true
    SendNUIMessage({ action = 'play', pos = position(), volume = currentVolume() / 100 })
end

local function stop()
    if not playing then return end
    playing = false
    SendNUIMessage({ action = 'stop' })
end

RegisterNetEvent('bs:radio:clock', function(epoch)
    clockEpoch, clockAt = tonumber(epoch), GetGameTimer()
    if playing then SendNUIMessage({ action = 'seek', pos = position() }) end
end)

CreateThread(function()
    TriggerServerEvent('bs:radio:sync')
    SetAudioFlag('DisableFlightMusic', true)
    SetAudioFlag('WantedMusicDisabled', true)
    local lastResync = GetGameTimer()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and Radio.Settings.enabled then
            local want = GetIsVehicleEngineRunning(veh) and GetPlayerRadioStationName() ~= nil
                and GetPlayerRadioStationName() ~= 'OFF' and not IsPauseMenuActive()
            if want and not playing then start() elseif not want then stop() end
            if playing and GetGameTimer() - lastResync > 300000 then
                lastResync = GetGameTimer()
                TriggerServerEvent('bs:radio:sync')
            end
            Wait(200)
        else
            stop()
            Wait(500)
        end
    end
end)

-- Settings (bs_inventory Settings tab and bs_pause read/write these).
exports('GetVolume', function() return currentVolume() end)
exports('SetVolume', function(v)
    v = math.max(0, math.min(100, math.floor(tonumber(v) or 40)))
    volume, volumeSet = v, true
    SetResourceKvpInt(KVP_VOL, v)
    SetResourceKvp(KVP_VOL .. '_set', '1')
    SendNUIMessage({ action = 'volume', volume = v / 100 })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SendNUIMessage({ action = 'stop' }) end
end)
