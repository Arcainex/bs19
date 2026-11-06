local target, received, mode, lastRoute = 29, {}, 2, 0
local effects, muted = {}, false
exports('SetMuted',function(value) muted=value==true;TriggerServerEvent('bs:voice:mute',muted);if muted then MumbleClearVoiceTarget(29) end end)
local function clear()
    MumbleClearVoiceTarget(target)
    MumbleSetVoiceTarget(target)
    for id in pairs(received) do
        MumbleSetVolumeOverrideByServerId(tonumber(id), -1.0)
        MumbleSetSubmixForServerId(tonumber(id), -1)
    end
    received = {}
end
local function initialise()
    clear()
    -- Each player has a private source channel. Only explicit targets carry audio.
    MumbleSetVoiceChannel(10000 + GetPlayerServerId(PlayerId()))
    MumbleSetTalkerProximity(Voice.ranges[mode] + 0.0)
end
CreateThread(function()
    for tier=1,3 do
        local mix = CreateAudioSubmix('bs_walkie_'..tier)
        if mix ~= -1 then
            SetAudioSubmixEffectRadioFx(mix,0)
            SetAudioSubmixEffectParamInt(mix,0,`default`,1)
            SetAudioSubmixEffectParamFloat(mix,0,`freq_low`,({500.0,300.0,150.0})[tier])
            SetAudioSubmixEffectParamFloat(mix,0,`freq_hi`,({2800.0,4000.0,6500.0})[tier])
            AddAudioSubmixOutput(mix,0)
            effects[tier]=mix
        end
    end
    muted=LocalPlayer.state.bs_tutorial=='tour' or LocalPlayer.state.bs_tutorial=='pick'
    initialise()
    TriggerServerEvent('bs:voice:mute',muted)
    TriggerServerEvent('bs:voice:mode',mode)
    while true do
        if GetGameTimer()-lastRoute > 1500 then clear() end
        TriggerEvent('bs:voice:hud',{mode=Voice.names[mode],range=Voice.ranges[mode],talking=NetworkIsPlayerTalking(PlayerId()),connected=GetGameTimer()-lastRoute<=1500})
        Wait(250)
    end
end)
AddEventHandler('mumbleConnected', initialise)
RegisterNetEvent('bs:voice:ranges', function(ranges) Voice.ranges=ranges;MumbleSetTalkerProximity(Voice.ranges[mode]+0.0) end)
RegisterNetEvent('bs:voice:route', function(peers, incoming, selected, ranges)
    if ranges then Voice.ranges=ranges end
    lastRoute=GetGameTimer();mode=selected
    MumbleClearVoiceTarget(target)
    MumbleSetVoiceTarget(target)
    MumbleSetTalkerProximity(Voice.ranges[mode]+0.0)
    for _,id in ipairs(muted and {} or peers) do MumbleAddVoiceTargetPlayerByServerId(target,id) end
    for id in pairs(received) do
        if not incoming[id] then MumbleSetVolumeOverrideByServerId(tonumber(id),-1.0);MumbleSetSubmixForServerId(tonumber(id),-1) end
    end
    for id,tier in pairs(incoming) do
        MumbleSetVolumeOverrideByServerId(tonumber(id),1.0)
        MumbleSetSubmixForServerId(tonumber(id),effects[tonumber(tier)] or -1)
    end
    received=incoming
end)
RegisterCommand('voicecycle',function() mode=mode%3+1;TriggerServerEvent('bs:voice:mode',mode) end,false)
RegisterKeyMapping('voicecycle','Change speaking distance','keyboard','CAPITAL')
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then clear();MumbleSetVoiceChannel(10000+GetPlayerServerId(PlayerId()));MumbleSetTalkerProximity(0.0) end end)

local proximityHeld, radioHeld = false, false
RegisterCommand('+bsproximitytalk',function() proximityHeld=true end,false)
RegisterCommand('-bsproximitytalk',function() proximityHeld=false end,false)
RegisterKeyMapping('+bsproximitytalk','Speak nearby','keyboard','K')
AddEventHandler('bs:voice:radioPtt',function(held) radioHeld=held==true end)
CreateThread(function()
    while true do
        DisableControlAction(0,249,true)
        if not muted and (proximityHeld or radioHeld) then SetControlNormal(0,249,1.0) end
        Wait(0)
    end
end)
