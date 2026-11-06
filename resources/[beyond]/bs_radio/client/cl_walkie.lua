local open, transmitting, radioState, debugBlips = false,false,{},{}
local function close()
    open=false;SetNuiFocus(false,false);SendNUIMessage({action='walkieClose'});TriggerEvent('bs:ui:closed','walkie')
end
local function stopTransmitting()
    local wasTransmitting=transmitting
    transmitting=false
    TriggerEvent('bs:voice:radioPtt',false)
    if wasTransmitting then TriggerServerEvent('bs:walkie:transmit',false)end
end

local function canTransmit()
    local ped=PlayerPedId()
    local channel=tonumber(radioState.channel)
    return type(radioState.tier)=='number' and channel and channel>0
        and (tonumber(radioState.battery) or 0)>0
        and not IsEntityDead(ped) and not LocalPlayer.state.bsDowned
        and not IsNuiFocused()
end

local function requestOpen()
    if open then close();return end
    TriggerServerEvent('bs:walkie:requestOpen')
end

-- Old saved bindings may still invoke these names. Retire them without deleting a player's bindings.
RegisterCommand('walkie',function()end,false)
RegisterCommand('+walkietalk',function()end,false)
RegisterCommand('-walkietalk',stopTransmitting,false)

RegisterCommand('+bs_radio_ptt',function()
    if not canTransmit() then return end
    transmitting=true
    TriggerEvent('bs:voice:radioPtt',true)
    TriggerServerEvent('bs:walkie:transmit',true)
end,false)
RegisterCommand('-bs_radio_ptt',stopTransmitting,false)
RegisterKeyMapping('+bs_radio_ptt','Transmit on equipped radio','keyboard','N')
RegisterNUICallback('walkieClose',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('walkieJoin',function(data,cb) TriggerServerEvent('bs:walkie:join',data.channel);cb({ok=true}) end)
RegisterNUICallback('walkieFaction',function(data,cb) TriggerServerEvent('bs:walkie:factionChannel',data.channel);cb({ok=true}) end)
RegisterNetEvent('bs:walkie:state',function(s)
    if type(s)~='table' then return end
    radioState=s
    if not s.tier or (tonumber(s.battery) or 0)<=0 then
        stopTransmitting()
        if not s.tier and open then close()end
    end
    SendNUIMessage({action='walkieState',state=s})
    TriggerEvent('bs:radio:hud',s)
end)
RegisterNetEvent('bs:walkie:notice',function(message) SendNUIMessage({action='walkieNotice',message=message}) end)
RegisterNetEvent('bs:walkie:offer',function(offer) TriggerEvent('bs:missions:radioOffer',offer) end)
RegisterNetEvent('bs:walkie:debugNodes',function(nodes)
    for _,blip in ipairs(debugBlips) do RemoveBlip(blip) end
    debugBlips={}
    for _,n in ipairs(nodes) do
        local b=AddBlipForCoord(n.x,n.y,n.z);SetBlipSprite(b,459);SetBlipColour(b,n.disrupted and 1 or 47)
        BeginTextCommandSetBlipName('STRING');AddTextComponentString(n.label);EndTextCommandSetBlipName(b);debugBlips[#debugBlips+1]=b
        b=AddBlipForRadius(n.x,n.y,n.z,n.range+0.0);SetBlipColour(b,47);SetBlipAlpha(b,35);debugBlips[#debugBlips+1]=b
    end
end)
RegisterCommand('radioDebug',function() if #debugBlips>0 then for _,b in ipairs(debugBlips) do RemoveBlip(b) end;debugBlips={} else TriggerServerEvent('bs:walkie:debug') end end,false)
CreateThread(function()
    while true do
        if transmitting then
            if canTransmit() then TriggerServerEvent('bs:walkie:transmit',true)
            else stopTransmitting()end
        end
        Wait(250)
    end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then close();for _,b in ipairs(debugBlips) do RemoveBlip(b) end end end)

RegisterNetEvent('bs:walkie:open',requestOpen)
local portable, props = {}, {}
RegisterNetEvent('bs:walkie:portable',function(nodes) portable=nodes end)
CreateThread(function()
    local model=`prop_radio_01`
    while true do
        local position=GetEntityCoords(PlayerPedId());local present={}
        for _,n in ipairs(portable) do
            local distance=#(position-vector3(n.x,n.y,n.z))
            if distance<75 then
                present[n.id]=true
                if not props[n.id] then
                    RequestModel(model);local untilAt=GetGameTimer()+1500
                    while not HasModelLoaded(model) and GetGameTimer()<untilAt do Wait(10) end
                    if HasModelLoaded(model) then
                        local obj=CreateObject(model,n.x,n.y,n.z,false,false,false)
                        PlaceObjectOnGroundProperly(obj);FreezeEntityPosition(obj,true);props[n.id]=obj;SetModelAsNoLongerNeeded(model)
                    end
                end
                if distance<2.5 then
                    BeginTextCommandDisplayHelp('STRING');AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to recover the portable relay.');EndTextCommandDisplayHelp(0,false,true,-1)
                    if IsControlJustReleased(0,38) then TriggerServerEvent('bs:walkie:recover',n.id) end
                end
            end
        end
        for id,obj in pairs(props) do if not present[id] then DeleteEntity(obj);props[id]=nil end end
        Wait(next(present) and 0 or 500)
    end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for _,obj in pairs(props) do DeleteEntity(obj) end end end)

RegisterNUICallback('walkieMissions',function(_,cb) close();exports.bs_inventory:Open('missions');cb({ok=true}) end)

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then stopTransmitting()end end)

RegisterNetEvent('bs:walkie:openGranted',function()
    if open then return end
    stopTransmitting()
    TriggerEvent('bs:ui:opened','walkie')
    open=true;SetNuiFocus(true,true);SendNUIMessage({action='walkieOpen',state=radioState})
end)

RegisterNUICallback('walkieCharge',function(data,cb)
    local source=type(data)=='table' and data.source or nil
    if source~='vehicle' and source~='mains'then return cb({ok=false})end
    TriggerServerEvent('bs:walkie:charge',source)
    cb({ok=true})
end)
RegisterNUICallback('walkieStopCharge',function(_,cb)
    TriggerServerEvent('bs:walkie:stopCharge')
    cb({ok=true})
end)
AddEventHandler('bs:ui:opened',function(name)
    if transmitting then stopTransmitting()end
    if name~='walkie' and open then close()end
end)
AddEventHandler('bs:hook:player:unloaded',function()
    stopTransmitting()
    if open then close()end
    radioState={}
end)
AddEventHandler('bs:hook:player:died',stopTransmitting)
