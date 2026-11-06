WalkieBattery={}
local B=WalkieBattery
local charging,working={},{}
local function equipped(src)
    local ok,radio=pcall(function()return exports.bs_inventory:EquippedRadio(src)end)
    return ok and radio or nil
end
local function percent(radio)
    return radio and math.max(0,math.min(100,tonumber(radio.metadata.radioCharge)or 100))or 0
end
function B.snapshot(src)
    local radio=equipped(src);local charge=charging[src]
    if charge and (not radio or radio.id~=charge.id)then charging[src]=nil;charge=nil end
    return {battery=percent(radio),charging=charge~=nil,source=charge and charge.source or nil,equipped=radio~=nil}
end
function B.powered(src)return percent(equipped(src))>0 end
local function notify(src,message)TriggerClientEvent('bs:walkie:notice',src,message)end
local function power(src,source,draw)
    if source=='vehicle'and GetResourceState('bs_vehicles')=='started'then
        local ok,available=pcall(function()return exports.bs_vehicles:PortableChargingPower(src,draw or 0)end)
        return ok and available==true
    end
    if source~='mains'then return false end
    if GetResourceState('bs_building')=='started'and GetPlayerRoutingBucket(src)==0 then
        local ok,available=pcall(function()return exports.bs_building:ChargingPowerNear(src,RadioPower.powerDistance)end)
        if ok and available then return true end
    end
    local at=GetEntityCoords(GetPlayerPed(src))
    for _,p in ipairs(RadioPower.points or {})do
        if type(p)=='table'and p.enabled~=false and (p.bucket or 0)==GetPlayerRoutingBucket(src)and tonumber(p.x)and tonumber(p.y)and tonumber(p.z)then
            local dx,dy,dz=at.x-p.x,at.y-p.y,at.z-p.z
            if dx*dx+dy*dy+dz*dz<=RadioPower.powerDistance^2 then return true end
        end
    end
    return false
end
RegisterNetEvent('bs:walkie:charge',function(sourceType)
    local src=source
    if working[src]then return end
    working[src]=true
    local ok,err=pcall(function()
        local radio=equipped(src)
        if not radio then notify(src,'Equip a radio before connecting a charger.');return end
        if percent(radio)>=100 then notify(src,'The radio battery is full.');return end
        if not power(src,sourceType,0)then notify(src,sourceType=='vehicle'and 'Sit in a vehicle with an installed inverter and a charged battery.'or 'Move beside a powered socket, building device or running generator.');return end
        charging[src]={id=radio.id,source=sourceType,at=GetGameTimer()}
        TriggerEvent('bs:radio:equipmentChanged',src)
        notify(src,'Charging connected. Stay beside the power source.')
    end)
    working[src]=nil
    if not ok then print('[bs_radio] charger request failed: '..tostring(err))end
end)
RegisterNetEvent('bs:walkie:stopCharge',function()charging[source]=nil;TriggerEvent('bs:radio:equipmentChanged',source)end)
function B.tick(src,seconds,on,transmitting)
    local radio=equipped(src)
    if not radio then charging[src]=nil;return end
    local charge=charging[src]
    if charge and charge.id~=radio.id then charging[src]=nil;charge=nil end
    local delta=0
    if on then delta=-seconds/(math.max(1,transmitting and RadioPower.transmitHours or RadioPower.standbyHours)*3600)*100 end
    if charge then
        if percent(radio)>=100 or not power(src,charge.source,charge.source=='vehicle'and RadioPower.vehicleDrawPerMinute*seconds/60 or 0)then
            charging[src]=nil;charge=nil
            notify(src,'Charging stopped: full battery or power source unavailable.')
        else delta=delta+seconds/(math.max(1,RadioPower.chargeMinutes)*60)*100 end
    end
    if delta~=0 then
        local ok,value=pcall(function()return exports.bs_inventory:AdjustRadioCharge(src,radio.id,delta)end)
        if ok and value then
            if value<=0 then notify(src,'Radio battery empty. Connect it to a charger.')end
            if value>=100 then charging[src]=nil end
            TriggerEvent('bs:radio:equipmentChanged',src)
        end
    end
end
AddEventHandler('bs:hook:player:unloaded',function(p)if p then charging[p.source]=nil;working[p.source]=nil end end)
AddEventHandler('playerDropped',function()charging[source]=nil;working[source]=nil end)
