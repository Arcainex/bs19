local settings={enabled=true,radio=true,scale=1.0,opacity=0.9,margin=24,x=0.94,y=0.80}
local editing=false
local function save() SetResourceKvp('bs_voice_radio_hud',json.encode(settings)) end
local function update(patch)
    if type(patch)~='table' then return false end
    for _,k in ipairs({'enabled','radio'}) do if type(patch[k])=='boolean' then settings[k]=patch[k] end end
    for k,bounds in pairs({scale={0.65,2.0},opacity={0.3,1.0},margin={8,96},x={0,1},y={0,1}}) do
        if type(patch[k])=='number' and patch[k]==patch[k] then settings[k]=math.max(bounds[1],math.min(bounds[2],patch[k])) end
    end
    save();SendNUIMessage({action='voiceRadioPrefs',settings=settings});return true
end
local function close(release)
    if not editing then return end
    editing=false;SendNUIMessage({action='voiceRadioEdit',on=false})
    if release~=false then SetNuiFocus(false,false);SetNuiFocusKeepInput(false);TriggerEvent('bs:ui:closed','voicehud') end
end
local function open()
    if editing then close();return end
    TriggerEvent('bs:ui:opened','voicehud');editing=true;SetNuiFocus(true,true)
    SendNUIMessage({action='voiceRadioEdit',on=true,settings=settings})
end
exports('OpenVoiceRadioSettings',open)
exports('GetVoiceRadioSettings',function() return settings end)
exports('SetVoiceRadioSettings',update)
RegisterCommand('voicehud',open,false)
RegisterNUICallback('voiceRadioSave',function(data,cb) cb({ok=update(data)}) end)
RegisterNUICallback('voiceRadioClose',function(_,cb) close();cb({ok=true}) end)
AddEventHandler('bs:voice:hud',function(state) SendNUIMessage({action='voiceRadioState',voice=state}) end)
AddEventHandler('bs:radio:hud',function(state) SendNUIMessage({action='voiceRadioState',radio=state}) end)
AddEventHandler('bs:ui:opened',function(name) if name~='voicehud' then close(false) end end)
CreateThread(function()
    local raw=GetResourceKvpString('bs_voice_radio_hud')
    if raw then local ok,prefs=pcall(json.decode,raw);if ok then update(prefs) end end
    for i=1,4 do Wait(2000);SendNUIMessage({action='voiceRadioPrefs',settings=settings}) end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then close() end end)
