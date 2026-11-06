local saved=GetResourceKvpString('voice_ranges')
if saved then
    local ok,r=pcall(json.decode,saved)
    if ok and type(r)=='table' and #r==3 then
        local valid=true
        for i=1,3 do if type(r[i])~='number' or r[i]<1 or r[i]>100 then valid=false end end
        if valid then Voice.ranges=r end
    end
end
local modes, radio, rate, muted = {}, {}, {}, {}
local function loaded(src)
    local ok, player = pcall(function() return exports.bs_core:GetPlayer(src) end)
    return ok and player and player.charId
end
RegisterNetEvent('bs:voice:mute',function(value) muted[source]=value==true end)
RegisterNetEvent('bs:voice:mode', function(mode)
    local src = source
    if rate[src] and GetGameTimer() - rate[src] < 300 then return end
    rate[src] = GetGameTimer()
    mode = tonumber(mode)
    if mode and mode % 1 == 0 and Voice.ranges[mode] then modes[src] = mode end
end)
exports('SetRadioRecipients', function(src, recipients)
    if GetInvokingResource() ~= 'bs_radio' then return false end
    radio[tonumber(src)] = recipients or {}
    return true
end)
exports('SetRanges', function(ranges)
    for i=1,3 do if type(ranges[i]) ~= 'number' or ranges[i] < 1 or ranges[i] > 100 then return false end end
    Voice.ranges = {ranges[1], ranges[2], ranges[3]}
    SetResourceKvp('voice_ranges',json.encode(Voice.ranges))
    TriggerClientEvent('bs:voice:ranges', -1, Voice.ranges)
    return true
end)
AddEventHandler('playerDropped', function() modes[source],radio[source],rate[source],muted[source]=nil,nil,nil,nil end)
CreateThread(function()
    while true do
        local players, positions = GetPlayers(), {}
        for _, id in ipairs(players) do
            local src = tonumber(id)
            if loaded(src) and not muted[src] and GetPlayerPed(src) ~= 0 then positions[src] = GetEntityCoords(GetPlayerPed(src)) end
        end
        for _, id in ipairs(players) do
            local src, peers, incoming = tonumber(id), {}, {}
            local pos = positions[src]
            if pos then
                for other, at in pairs(positions) do
                    if other ~= src and GetPlayerRoutingBucket(src) == GetPlayerRoutingBucket(other) then
                        if #(pos-at) <= Voice.ranges[modes[src] or 2] then peers[#peers+1] = other end
                        local transmission = radio[other] and radio[other][src]
                        if transmission then incoming[tostring(other)] = transmission end
                    end
                end
                for key in pairs(radio[src] or {}) do
                    local other = tonumber(key)
                    if positions[other] and GetPlayerRoutingBucket(src) == GetPlayerRoutingBucket(other) then
                        local found=false
                        for _, peer in ipairs(peers) do if peer==other then found=true end end
                        if not found then peers[#peers+1]=other end
                    end
                end
            end
            TriggerClientEvent('bs:voice:route', src, peers, incoming, modes[src] or 2, Voice.ranges)
        end
        Wait(Voice.refresh)
    end
end)

exports('GetRanges',function() return Voice.ranges end)
