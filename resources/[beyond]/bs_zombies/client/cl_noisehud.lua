-- Carry comes from the same accepted noise event as zombie hearing.
local enabled, showRadius, lastPublish = true, true, 0
-- bs_ui draws this as the NOISE row of the survival HUD now; the event below keeps feeding it.
local drawNative = false
local sound = { radius=0, at=0, kind='' }
AddEventHandler('bs:combatfx:options', function(options)
    enabled=options.zombieNoiseHud ~= false
    showRadius=options.zombieNoiseRadius ~= false
end)
AddEventHandler('bs:world:noise', function(payload)
    if type(payload) ~= 'table' or tonumber(payload.source) ~= GetPlayerServerId(PlayerId()) then return end
    local radius=tonumber(payload.radius)
    if not radius or radius ~= radius or radius < 0 then return end
    local now=GetGameTimer()
    if now-sound.at > 1500 or radius >= sound.radius then
        sound={radius=radius,at=now,kind=tostring(payload.kind or '')}
    end
end)
local function text(x,y,value)
    SetTextFont(4); SetTextScale(0.0,0.27); SetTextColour(218,207,180,230)
    SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(value); EndTextCommandDisplayText(x,y)
end
CreateThread(function()
    while true do
        local now=GetGameTimer()
        local fade=math.max(0,1-(now-sound.at)/2400)
        local carry=sound.radius*fade
        if now-lastPublish >= 200 then
            lastPublish=now
            TriggerEvent('bs:zombies:noiseHud',{visible=enabled,radius=sound.radius,level=math.min(1,carry/180),kind=sound.kind,active=fade>0})
        end
        if drawNative and enabled and not IsPauseMenuActive() and NetworkIsPlayerActive(PlayerId()) then
            local x,y=0.184,0.948
            DrawRect(x+0.036,y,0.085,0.041,13,14,12,190)
            for i=1,5 do
                local lit=carry > (i-1)*36+0.1
                DrawRect(x+i*0.009,y+0.006-i*0.002,0.005,0.007+i*0.004,lit and 212 or 64,lit and 146 or 65,lit and 65 or 57,220)
            end
            if showRadius then text(x+0.052,y-0.010,fade>0 and ('%.0fm'):format(sound.radius) or '0m') end
            Wait(0)
        else Wait(250) end
    end
end)
