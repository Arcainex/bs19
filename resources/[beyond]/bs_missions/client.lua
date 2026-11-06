local objectives,blips,working,lastPulse = {},{},nil,0
local function remove(id) if blips[id] then RemoveBlip(blips[id]);blips[id]=nil end;objectives[id]=nil;if working==id then working=nil end end
RegisterNetEvent('bs:relay:objective',function(m)
    remove(m.id);objectives[m.id]=m
    local b=AddBlipForCoord(m.x,m.y,m.z);SetBlipSprite(b,459);SetBlipColour(b,47);SetBlipRoute(b,true)
    BeginTextCommandSetBlipName('STRING');AddTextComponentString(m.label);EndTextCommandSetBlipName(b);blips[m.id]=b
end)
RegisterNetEvent('bs:relay:stopped',function(id,complete) working=nil;if complete then remove(id) end end)
CreateThread(function()
    while true do
        local sleep=500;local pos=GetEntityCoords(PlayerPedId())
        for id,m in pairs(objectives) do
            if GetCloudTimeAsInt()>m.expires then remove(id)
            elseif #(pos-vector3(m.x,m.y,m.z))<5.0 then
                sleep=0
                BeginTextCommandDisplayHelp('STRING');AddTextComponentSubstringPlayerName(working==id and 'Hold ~INPUT_CONTEXT~ to work on the relay.' or 'Hold ~INPUT_CONTEXT~ to begin the relay objective.');EndTextCommandDisplayHelp(0,false,true,-1)
                if IsControlPressed(0,38) and not working then working=id;TriggerServerEvent('bs:relay:begin',id) end
                if working==id and IsControlPressed(0,38) and GetGameTimer()-lastPulse>500 then lastPulse=GetGameTimer();TriggerServerEvent('bs:relay:begin',id) end
                if working==id and not IsControlPressed(0,38) then working=nil;TriggerServerEvent('bs:relay:cancel',id) end
            elseif working==id then working=nil;TriggerServerEvent('bs:relay:cancel',id) end
        end
        Wait(sleep)
    end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for id in pairs(blips) do remove(id) end end end)

AddEventHandler('bs:missions:radioOffer',function(offer)
    BeginTextCommandThefeedPost('STRING');AddTextComponentSubstringPlayerName(tostring(offer.title or 'Radio contract available')..' — open Radio > Contracts to review.');EndTextCommandThefeedPostTicker(false,false)
end)

RegisterNetEvent('bs:relay:reset',function()
    local ids={};for id in pairs(objectives) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do remove(id) end
end)
CreateThread(function() Wait(2000);TriggerServerEvent('bs:relay:sync') end)
