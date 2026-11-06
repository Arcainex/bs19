local companion,hiddenFor
-- Lift above the head bone (m), full size range and fade-out range, matching bs_zombies HealthBars.
local LIFT,FULL,RANGE=.45,12.0,35.0
local stateAt=0
RegisterNetEvent('bs:link:state',function(data)companion=data or nil;stateAt=GetGameTimer()end)
RegisterNetEvent('bs:link:grabbed',function(net,grabNet,seconds)
    if companion and companion.net==net and companion.life then companion.life.status='grabbed';companion.life.grabLeft=seconds;stateAt=GetGameTimer()end
end)
local function clock(s)return ('%d:%02d'):format(s//60,s%60)end

local function label(value,x,y,scale,rgb)
    SetTextFont(4);SetTextScale(0.0,scale)
    SetTextColour(rgb[1],rgb[2],rgb[3],240)
    SetTextCentre(true);SetTextOutline()
    SetTextEntry('STRING');AddTextComponentString(value);DrawText(x,y)
end

-- Same segmented readout used by the in-world zombie health bars.
local function drawBar(x,y,width,height,fraction,rgb)
    local segments,gap=10,.0009
    DrawRect(x,y,width+gap*2,height+.0022,16,11,8,170)
    local segmentWidth=(width-gap*(segments-1))/segments
    local left=x-width/2
    for i=0,segments-1 do
        local fill=math.max(0,math.min(1,fraction*segments-i))
        if fill>0 then
            local drawnWidth=segmentWidth*fill
            DrawRect(left+i*(segmentWidth+gap)+drawnWidth/2,y,drawnWidth,height,rgb[1],rgb[2],rgb[3],235)
        end
    end
end

CreateThread(function()
    while true do
        local delay=500
        if not hiddenFor and SurvivorLink.showHud and companion and companion.net then
            local ped=NetworkGetEntityFromNetworkId(companion.net)
            local identity=ped~=0 and DoesEntityExist(ped)and Entity(ped).state.bsSurvivorLink
            local mine=type(identity)=='table'and tonumber(identity.owner)==GetPlayerServerId(PlayerId())
                and tonumber(identity.charId)==tonumber(companion.id)
            local me=PlayerPedId()
            -- Name, tag and level come from the normal player nametag (bs_factions); here only the grab countdown.
            if mine and ped~=me and companion.life and companion.life.status=='grabbed'then
                -- Head bone in world space, then lift straight up. The bone offset is local and tilts with the head.
                local head=GetPedBoneCoords(ped,31086,0.0,0.0,0.0)
                local distance=#(GetGameplayCamCoord()-head)
                if distance<RANGE and not IsEntityOccluded(ped)and HasEntityClearLosToEntity(me,ped,17)then
                    delay=0
                    local visible,x,y=GetScreenCoordFromWorldCoord(head.x,head.y,head.z+LIFT)
                    if visible then
                        -- Same shrink curve as the walker bars.
                        local scale=1.0
                        if distance>FULL then scale=.34+.66*math.max(0.0,1.0-(distance-FULL)/(RANGE-FULL))end
                        local health=math.max(0,GetEntityHealth(ped)-100)
                        local maximum=math.max(1,GetEntityMaxHealth(ped)-100)
                        local fraction=math.min(1,health/maximum)
                        local status=companion.life and companion.life.status or 'alive'
                        if status~='alive'then fraction=0 end
                        local rgb=fraction>.6 and {200,118,58}or fraction>.28 and {176,84,36}or {150,52,40}
                        drawBar(x,y,.055*scale,.0075*scale,fraction,rgb)
                        label((companion.name or 'Survivor'):upper(),x,y-.030*scale,.30*scale,{216,210,194})
                        local value=status=='alive'and ('%d / %d'):format(math.floor(health),maximum)
                            or status=='downed'and 'INCAPACITATED'or status~='grabbed'and 'DEAD'or nil
                        if status=='grabbed'then
                            -- Rescue clock counts down locally between server pushes.
                            local left=math.max(0,math.floor((companion.life.grabLeft or 0)-(GetGameTimer()-stateAt)/1000))
                            value=L('link.grab_bar',{t=clock(left)})
                            rgb={226,64,40}
                        end
                        label(value,x,y+.006*scale,.24*scale,rgb)
                    end
                end
            end
        end
        Wait(delay)
    end
end)
AddEventHandler('bs:hook:player:unloaded',function()companion=nil end)
AddEventHandler('bs:ui:opened',function(name)hiddenFor=name end)
AddEventHandler('bs:ui:closed',function(name)if name==nil or name==hiddenFor then hiddenFor=nil end end)
