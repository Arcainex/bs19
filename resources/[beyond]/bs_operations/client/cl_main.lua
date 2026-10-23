-- bs_operations client: blips, interactions, status HUD, mission tracker, board, panel puzzle, escort and the buff light

local PowerV, PointsV, Track = nil, nil, nil
local blips = { power = nil, powerArea = nil, points = {}, track = nil, trackArea = nil }
local zones = {}
local nuiOpen = false

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg }) end
local function myFaction() return LocalPlayer.state.bsOpsFaction or nil end
local function nui(action, data) SendNUIMessage({ action = action, data = data }) end

local function blipName(b, text)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandSetBlipName(b)
end
local function rmBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end

local function zone(id, pos, r, opts)
    if zones[id] then pcall(function() exports.bs_interactions:RemoveZone(id) end); zones[id] = nil end
    if opts and #opts > 0 then
        local ok = pcall(function() exports.bs_interactions:AddZone(id, pos, r, opts) end)
        if ok then zones[id] = true end
    end
end

-- Power station
local function powerZones()
    local v = PowerV
    if not v or not v.enabled then
        zone('bsops:power', nil); for i = 1, 8 do zone('bsops:panel' .. i, nil) end
        return
    end
    local opts = {}
    if v.phase == 'idle' then
        opts[#opts + 1] = { label = L('ops.o_start'), icon = 'hand', event = 'bs:ops:powerStart' }
    end
    if v.crate and v.crate.faction == myFaction() then
        opts[#opts + 1] = { label = L('ops.o_crate'), icon = 'bag', event = 'bs:ops:powerCrate' }
    end
    zone('bsops:power', vector3(v.x, v.y, v.z + 1.0), 2.5, opts)
    for i = 1, 8 do
        local p = v.panels[i]
        if p and v.phase == 'repair' and not p.done and v.starter == myFaction() then
            zone('bsops:panel' .. i, vector3(p.x, p.y, p.z + 1.0), 1.8, { { label = L('ops.o_repair'), icon = 'wrench', event = 'bs:ops:repair', args = i } })
        else
            zone('bsops:panel' .. i, nil)
        end
    end
end

local function powerBlips()
    local v = PowerV
    if not v or not v.enabled then rmBlip(blips.power); rmBlip(blips.powerArea); blips.power, blips.powerArea = nil, nil; return end
    if not blips.power then
        blips.power = AddBlipForCoord(v.x, v.y, v.z)
        SetBlipSprite(blips.power, 354); SetBlipScale(blips.power, 0.85); SetBlipAsShortRange(blips.power, true)
        blipName(blips.power, v.label)
    end
    SetBlipColour(blips.power, v.phase == 'idle' and 4 or (v.contested and 1 or 46))
    if v.phase ~= 'idle' and not blips.powerArea then
        blips.powerArea = AddBlipForRadius(v.x, v.y, v.z, v.r)
        SetBlipColour(blips.powerArea, 46); SetBlipAlpha(blips.powerArea, 90)
    elseif v.phase == 'idle' and blips.powerArea then
        rmBlip(blips.powerArea); blips.powerArea = nil
    end
end

local lastSig = nil
local function powerSig(v)
    local t = { tostring(v.enabled), v.phase, tostring(v.starter), tostring(v.crate and v.crate.faction), tostring(myFaction()) }
    for _, p in ipairs(v.panels or {}) do t[#t + 1] = ('%.1f,%.1f,%s'):format(p.x, p.y, tostring(p.done)) end
    return table.concat(t, '|')
end

RegisterNetEvent('bs:ops:power', function(v)
    PowerV = v
    powerBlips()
    local sig = powerSig(v)
    if sig ~= lastSig then lastSig = sig; powerZones() end
end)

AddEventHandler('bs:ops:powerStart', function()
    local r = BSB.Await('ops:power:start', 8000)
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

AddEventHandler('bs:ops:powerCrate', function()
    local r = BSB.Await('ops:power:crate', 8000)
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

-- Panel: wire puzzle in the NUI, then hold until the server minimum is up.
local puzzle = nil
AddEventHandler('bs:ops:repair', function(p)
    local idx = type(p) == 'table' and p.args or p
    if puzzle then return end
    local r = BSB.Await('ops:power:repairBegin', 6000, idx)
    if not r or not r.ok then if r and r.msg then notify('error', r.msg) end return end
    puzzle = { idx = idx, t = GetGameTimer(), seconds = r.seconds or 10 }
    nuiOpen = true
    SetNuiFocus(true, true)
    nui('puzzle', { title = L('ops.o_repair'), hint = L('ops.puzzle_hint') })
end)

RegisterNUICallback('puzzle', function(d, cb)
    cb({})
    SetNuiFocus(false, false); nuiOpen = false
    local pz = puzzle
    if not pz then return end
    if not d or not d.ok then puzzle = nil; return end
    CreateThread(function()
        local left = pz.seconds * 1000 - (GetGameTimer() - pz.t) + 300
        if left > 0 then
            pcall(function() exports.bs_interactions:Progress(L('ops.o_repair'), left) end)
            local ped = PlayerPedId()
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_WELDING', 0, true)
            Wait(left)
            ClearPedTasks(ped)
        end
        local r = BSB.Await('ops:power:repairDone', 6000, pz.idx)
        puzzle = nil
        if r and r.ok then notify('success', L('ops.panel_fixed')) elseif r and r.msg then notify('error', r.msg) end
    end)
end)

-- Control points
local function pointsDraw()
    for id, b in pairs(blips.points) do rmBlip(b); blips.points[id] = nil end
    for i = 1, 40 do if zones['bsops:cp' .. i] then zone('bsops:cp' .. i, nil) end end
    local v = PointsV
    if not v or not v.enabled then return end
    local mine = myFaction()
    for i, p in ipairs(v.list) do
        local b = AddBlipForCoord(p.x, p.y, p.z)
        SetBlipSprite(b, 543); SetBlipScale(b, 0.75); SetBlipAsShortRange(b, true)
        SetBlipColour(b, not p.owner and 1 or (p.owner == mine and 2 or 49))
        blipName(b, p.owner and ('%s (%s)'):format(p.label, p.ownerLabel) or p.label)
        blips.points[p.id] = b
        if p.owner and p.owner == mine and i <= 40 then
            zone('bsops:cp' .. i, vector3(p.x, p.y, p.z + 1.0), 3.0, { { label = L('ops.o_cache'), icon = 'bag', event = 'bs:ops:cache', args = p.id } })
        end
    end
end

-- Blips only change with owners or the list, not with capture progress.
local pointsSig = nil
RegisterNetEvent('bs:ops:points', function(v)
    PointsV = v
    local t = { tostring(v and v.enabled), tostring(myFaction()) }
    for _, p in ipairs((v and v.list) or {}) do t[#t + 1] = ('%s,%s,%s,%.0f,%.0f'):format(p.id, tostring(p.owner), p.label, p.x, p.y) end
    local sig = table.concat(t, '|')
    if sig ~= pointsSig then pointsSig = sig; pointsDraw() end
end)

AddEventHandler('bs:ops:cache', function(p)
    local r = BSB.Await('ops:cp:cache', 6000, type(p) == 'table' and p.args or p)
    if r and not r.ok and r.msg then notify('error', r.msg) end
end)

-- Owners get a short-lived flashing blip when a rival attacks their point.
RegisterNetEvent('bs:ops:alert', function(a)
    if type(a) ~= 'table' then return end
    local b = AddBlipForCoord(a.x, a.y, 0.0)
    SetBlipSprite(b, 161); SetBlipColour(b, 1); SetBlipScale(b, 1.1); SetBlipFlashes(b, true)
    blipName(b, a.label or '')
    SetTimeout(120000, function() rmBlip(b) end)
end)

-- Mission tracker
local function trackBlips()
    rmBlip(blips.track); rmBlip(blips.trackArea); blips.track, blips.trackArea = nil, nil
    local t = Track
    if not t or not t.x then return end
    blips.track = AddBlipForCoord(t.x, t.y, t.z or 0.0)
    SetBlipSprite(blips.track, 1); SetBlipColour(blips.track, 5); SetBlipRoute(blips.track, true); SetBlipRouteColour(blips.track, 5)
    blipName(blips.track, t.title)
    blips.trackArea = AddBlipForRadius(t.x, t.y, t.z or 0.0, (t.r or 25.0) + 0.0)
    SetBlipColour(blips.trackArea, 5); SetBlipAlpha(blips.trackArea, 80)
end

RegisterNetEvent('bs:ops:track', function(t)
    local key = t and (t.title .. t.step .. tostring(t.x) .. tostring(t.y)) or nil
    local old = Track and (Track.title .. Track.step .. tostring(Track.x) .. tostring(Track.y)) or nil
    Track = t
    if key ~= old then trackBlips() end
    nui('track', t)
end)

-- Board (from a faction quest trader)
local boardNpc = nil
AddEventHandler('bs:ops:board', function(p)
    local npcId = type(p) == 'table' and p.args or p
    local r = BSB.Await('ops:m:board', 8000, npcId)
    if not r or not r.ok then notify('error', (r and r.msg) or L('ops.m_wrong_npc')); return end
    boardNpc = npcId
    nuiOpen = true
    SetNuiFocus(true, true)
    nui('board', { list = r.list, busy = r.busy, labels = {
        title = L('ops.board'), accept = L('ops.accept'), abandon = L('ops.abandon'), close = L('ops.close'),
        reward = L('ops.reward'), rep = L('ops.rep'), done = L('ops.done_n'), steps = L('ops.steps'), locked = L('ops.locked'), active = L('ops.active') } })
end)

RegisterNUICallback('board', function(d, cb)
    d = type(d) == 'table' and d or {}
    if d.op == 'close' then
        SetNuiFocus(false, false); nuiOpen = false; cb({}); return
    end
    local r
    if d.op == 'accept' then r = BSB.Await('ops:m:accept', 8000, boardNpc, d.id)
    elseif d.op == 'abandon' then r = BSB.Await('ops:m:abandon', 8000) end
    if r and r.ok then
        SetNuiFocus(false, false); nuiOpen = false
        nui('close')
        notify('success', d.op == 'accept' and L('ops.m_started') or L('ops.m_abandoned'))
    elseif r and r.msg then
        notify('error', r.msg)
    end
    cb({ ok = r and r.ok or false })
end)

-- Status HUD: power station and nearby control point
local function fmt(s) s = math.max(0, math.floor(s or 0)); return ('%d:%02d'):format(s // 60, s % 60) end

CreateThread(function()
    while true do
        Wait(1000)
        local pos = GetEntityCoords(PlayerPedId())
        local lines = {}
        local v = PowerV
        if v and v.enabled and v.phase ~= 'idle' and #(pos.xy - vector2(v.x, v.y)) < 600.0 then
            lines[#lines + 1] = { h = v.label }
            if v.phase == 'repair' then
                local done = 0; for _, p in ipairs(v.panels) do if p.done then done = done + 1 end end
                lines[#lines + 1] = { t = L('ops.h_repair', { n = done, total = #v.panels, time = fmt(v.left) }) }
            else
                lines[#lines + 1] = { t = L('ops.h_hold', { time = fmt(v.left) }) }
                lines[#lines + 1] = { t = v.contested and L('ops.h_contested') or L('ops.h_control', { faction = v.controllerLabel or '-' }), warn = v.contested }
                if v.flipBy then lines[#lines + 1] = { bar = v.flip / math.max(1, v.flipNeed), t = L('ops.h_flip') } end
                for i = 1, math.min(3, #v.hold) do lines[#lines + 1] = { t = ('%s  %s'):format(v.hold[i].label, fmt(v.hold[i].s)), dim = true } end
            end
        end
        local pv = PointsV
        if pv and pv.enabled then
            for _, p in ipairs(pv.list) do
                if #(pos.xy - vector2(p.x, p.y)) < (p.r + 60.0) then
                    lines[#lines + 1] = { h = p.label }
                    lines[#lines + 1] = { t = p.owner and L('ops.h_owned', { faction = p.ownerLabel }) or L('ops.h_hostile') }
                    if p.phase == 'assault' then lines[#lines + 1] = { t = L('ops.h_clear'), warn = true }
                    elseif p.phase == 'capture' then lines[#lines + 1] = { bar = p.progress / math.max(1, p.need), t = L('ops.h_capture') } end
                    break
                end
            end
        end
        local b = LocalPlayer.state.bsOpsBuff
        if type(b) == 'table' and (b.untilT or 0) > GetCloudTimeAsInt() then
            lines[#lines + 1] = { t = L('ops.h_buff', { pct = b.xp or 0, time = fmt(b.untilT - GetCloudTimeAsInt()) }), dim = true }
        end
        nui('status', lines)
    end
end)

-- Escort NPC: whoever owns the ped makes it follow the mission owner.
local tasked = {}
CreateThread(function()
    while true do
        Wait(1500)
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
                local owner = Entity(ped).state.bsOpsEscort
                if owner and NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true) then
                    local pl = GetPlayerFromServerId(owner)
                    local target = pl ~= -1 and GetPlayerPed(pl) or 0
                    if target ~= 0 and (not tasked[ped] or GetGameTimer() - tasked[ped] > 8000) then
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedFleeAttributes(ped, 0, false)
                        SetPedKeepTask(ped, true)
                        SetPedRelationshipGroupHash(ped, joaat('PLAYER'))
                        if IsPedInAnyVehicle(target, false) then
                            local veh = GetVehiclePedIsIn(target, false)
                            if not IsPedInVehicle(ped, veh, false) and #(GetEntityCoords(ped) - GetEntityCoords(target)) < 12.0 then
                                TaskEnterVehicle(ped, veh, 10000, 0, 2.0, 1, 0)
                            end
                        elseif IsPedInAnyVehicle(ped, false) then
                            TaskLeaveAnyVehicle(ped, 0, 0)
                        else
                            TaskFollowToOffsetOfEntity(ped, target, 0.5, -1.5, 0.0, 3.0, -1, 2.0, true)
                        end
                        tasked[ped] = GetGameTimer()
                    end
                end
            end
        end
        for ped in pairs(tasked) do if not DoesEntityExist(ped) then tasked[ped] = nil end end
    end
end)

-- Buff: the winning faction's safezone gets lit.
CreateThread(function()
    while true do
        local sleep = 2000
        local b = LocalPlayer.state.bsOpsBuff
        if type(b) == 'table' and b.light and (b.untilT or 0) > GetCloudTimeAsInt() then
            local pos = GetEntityCoords(PlayerPedId())
            for _, z in ipairs((Zones and Zones.FactionSafe) or {}) do
                if z.faction == b.faction and z.enabled ~= false then
                    local c = z.coords
                    local r = (z.radius and z.radius > 0) and z.radius or 60.0
                    if #(pos.xy - c.xy) < r + 80.0 then
                        sleep = 0
                        DrawLightWithRange(c.x, c.y, c.z + 14.0, 255, 214, 150, r * 1.1, 2.2)
                        DrawLightWithRange(c.x + r * 0.5, c.y, c.z + 8.0, 255, 214, 150, r * 0.6, 1.4)
                        DrawLightWithRange(c.x - r * 0.5, c.y, c.z + 8.0, 255, 214, 150, r * 0.6, 1.4)
                        DrawLightWithRange(c.x, c.y + r * 0.5, c.z + 8.0, 255, 214, 150, r * 0.6, 1.4)
                        DrawLightWithRange(c.x, c.y - r * 0.5, c.z + 8.0, 255, 214, 150, r * 0.6, 1.4)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Markers on power panels during repair.
CreateThread(function()
    while true do
        local sleep = 1000
        local v = PowerV
        if v and v.phase == 'repair' and v.starter == myFaction() then
            local pos = GetEntityCoords(PlayerPedId())
            for _, p in ipairs(v.panels) do
                if not p.done and #(pos - vector3(p.x, p.y, p.z)) < 40.0 then
                    sleep = 0
                    DrawMarker(1, p.x, p.y, p.z - 0.2, 0, 0, 0, 0, 0, 0, 1.2, 1.2, 0.6, 240, 190, 60, 140, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(sleep)
    end
end)

AddStateBagChangeHandler('bsOpsFaction', nil, function(bag)
    if bag ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
    SetTimeout(200, function() pointsSig = nil; pointsDraw(); powerZones() end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    Wait(4000)
    local v = BSB.Await('ops:power:view', 8000); if v then PowerV = v; powerBlips(); powerZones() end
    local p = BSB.Await('ops:cp:view', 8000); if p then PointsV = p; pointsDraw() end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'bs_interactions' then SetTimeout(2000, function() powerZones(); pointsDraw() end) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if nuiOpen then SetNuiFocus(false, false) end
    for id in pairs(zones) do pcall(function() exports.bs_interactions:RemoveZone(id) end) end
end)
