-- bs_factions - squads: state from `bs:squad:sync`, "Invite to squad" on the ALT dot, invitations, and map blips for squad members only (KVP `bs_squad_blips`: 0 = unset = on, 1 = on, 2 = off).

local Cfg = Factions.Squad or {}
local BlipCfg = Cfg.blip or {}
local Squad = nil
local Pending = nil
local Blips = {} -- serverId -> blip
local ConsoleOpen = false
local UI_KEY = Cfg.uiKey or 'F3'
local UI_CMD = Cfg.uiCommand or 'squadconsole'

local function notify(t, msg) TriggerEvent('bs:ui:notify', { type = t, message = msg }) end

local function blipsEnabled()
    local ok, v = pcall(GetResourceKvpInt, 'bs_squad_blips')
    return not ok or v ~= 2
end

local function clearBlips()
    for id, b in pairs(Blips) do if DoesBlipExist(b) then RemoveBlip(b) end; Blips[id] = nil end
end

-- VIP blip color (bsVipTag.blip) or the config default.
local function blipColourFor(sid)
    local vt = Player(sid).state.bsVipTag
    return (type(vt) == 'table' and tonumber(vt.blip)) or BlipCfg.colour or 2
end

local function refreshBlips()
    if not Squad or not blipsEnabled() then return clearBlips() end
    local me = GetPlayerServerId(PlayerId())
    local want = {}
    for _, m in ipairs(Squad.members or {}) do
        if m.online and m.src and m.src ~= me then
            local pl = GetPlayerFromServerId(m.src)
            local ped = pl ~= -1 and GetPlayerPed(pl) or 0
            if ped ~= 0 and DoesEntityExist(ped) then
                want[m.src] = true
                local b = Blips[m.src]
                if not b or not DoesBlipExist(b) or GetBlipInfoIdEntityIndex(b) ~= ped then
                    if b and DoesBlipExist(b) then RemoveBlip(b) end
                    b = AddBlipForEntity(ped)
                    SetBlipSprite(b, BlipCfg.sprite or 1)
                    SetBlipScale(b, BlipCfg.scale or 0.85)
                    SetBlipAsShortRange(b, false)
                    ShowHeadingIndicatorOnBlip(b, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(('[%s] %s'):format(m.rankLabel or L('squad.blip'), m.name or '?'))
                    EndTextCommandSetBlipName(b)
                    Blips[m.src] = b
                end
                SetBlipColour(b, blipColourFor(m.src))
            end
        end
    end
    for id, b in pairs(Blips) do
        if not want[id] then if DoesBlipExist(b) then RemoveBlip(b) end; Blips[id] = nil end
    end
end

RegisterNetEvent('bs:squad:sync', function(payload)
    Squad = payload and payload.squad or nil
    if Squad then Pending = nil end
    clearBlips() -- labels / ranks may have changed; the loop rebuilds them
    refreshBlips()
    if ConsoleOpen then SendNUIMessage({ action = 'squadSync' }) end
end)

CreateThread(function()
    while true do
        Wait(BlipCfg.refreshMs or 1000)
        if Squad then refreshBlips() elseif next(Blips) then clearBlips() end
    end
end)

--------------------------------------------------------------------------- invitations
local function answer(yes)
    if not Pending then return notify('warn', L('squad.no_pending')) end
    Pending = nil
    CreateThread(function()
        local r = BSB.Await(yes and 'squad:accept' or 'squad:decline', 8000)
        if yes then
            notify((r and r.ok) and 'success' or 'warn', (r and r.ok) and L('squad.joined') or ((r and r.error) or L('squad.cant_join')))
        end
    end)
end

RegisterNetEvent('bs:squad:invite', function(data)
    if type(data) ~= 'table' then return end
    local seconds = tonumber(data.seconds) or 60
    Pending = { name = data.name, until_ = GetGameTimer() + seconds * 1000 }
    TriggerEvent('bs:ui:notify', {
        type = 'info', title = L('squad.invite_title'), duration = 10000,
        message = L('squad.invite_msg', { from = tostring(data.from or '?'), name = tostring(data.name or '?'), key = UI_KEY, sec = seconds }),
    })
    SendNUIMessage({ action = 'squadInvite', from = tostring(data.from or '?'), name = tostring(data.name or '?'), seconds = seconds, key = UI_KEY })
    local token = Pending
    SetTimeout(seconds * 1000, function() if Pending == token then Pending = nil end end)
end)

RegisterCommand('squadaccept', function() answer(true) end, false)
RegisterCommand('squaddecline', function() answer(false) end, false)

AddEventHandler('bs:squad:dot:invite', function(payload)
    if not payload or not payload.entity or not DoesEntityExist(payload.entity) or not IsPedAPlayer(payload.entity) then return end
    local pl = NetworkGetPlayerIndexFromPed(payload.entity)
    if not pl or pl == -1 then return end
    local target = GetPlayerServerId(pl)
    if target <= 0 then return end
    CreateThread(function()
        local r = BSB.Await('squad:invite', 8000, { target = target })
        notify((r and r.ok) and 'success' or 'warn', (r and r.ok) and L('squad.inv_sent') or ((r and r.error) or L('squad.inv_failed')))
    end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(1000) end
    exports.bs_interactions:AddType('ped', {
        {
            label    = L('squad.invite_option'),
            labelKey = 'squad.invite_option',
            icon     = 'npc',
            distance = 4.0,
            event    = 'bs:squad:dot:invite',
            filters  = { playerPed = true, stateFalse = 'bsZombie', maxDistance = 4.0 },
        },
    })
end)

--------------------------------------------------------------------------- exports
exports('GetSquadState', function() return Squad end)
exports('GetSquadBlips', function() return blipsEnabled() end)
exports('SetSquadBlips', function(on)
    pcall(SetResourceKvpInt, 'bs_squad_blips', on and 1 or 2)
    refreshBlips()
end)

-- console
-- Only squad callbacks get through the page.
local FX = {}
for _, n in ipairs({ 'squad:get', 'squad:create', 'squad:invite', 'squad:accept', 'squad:decline', 'squad:leave', 'squad:kick',
    'squad:setRank', 'squad:saveRanks', 'squad:rename', 'squad:disband', 'squad:transfer', 'squad:nearby' }) do FX[n] = true end

local function closeConsole()
    if not ConsoleOpen then return end
    ConsoleOpen = false
    SendNUIMessage({ action = 'squadClose' })
    SetNuiFocus(false, false)
    TriggerEvent('bs:ui:closed', 'squad')
end

local function openConsole()
    if ConsoleOpen then return closeConsole() end
    if IsPauseMenuActive() then return end
    ConsoleOpen = true
    TriggerEvent('bs:ui:opened', 'squad')
    SendNUIMessage({ action = 'squadOpen', key = UI_KEY })
    SetNuiFocus(true, true)
end

-- F2 opened this console because old 'squad' / 'squadmenu' binds were still saved on F2 by FiveM.
-- Those commands are gone on purpose, so the stale binds do nothing and F2 is the build wheel only.
RegisterCommand(UI_CMD, openConsole, false)
RegisterKeyMapping(UI_CMD, L('squad.keymap'), 'keyboard', UI_KEY)

RegisterNUICallback('squadClose', function(_, cb) closeConsole(); cb({ ok = true }) end)
RegisterNUICallback('squadFx', function(data, cb)
    local name = type(data) == 'table' and data.name or nil
    if not FX[name] then return cb({ ok = false, error = L('squad.not_avail') }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local r = BSB.Await(name, 8000, args)
        if type(r) ~= 'table' then r = { ok = false, error = L('squad.no_answer') } end
        if (name == 'squad:accept' or name == 'squad:decline') and r.ok then Pending = nil end
        cb(r)
    end)
end)

-- another screen took over
AddEventHandler('bs:ui:opened', function(what) if what ~= 'squad' and ConsoleOpen then closeConsole() end end)

exports('OpenSquadConsole', function() if not ConsoleOpen then openConsole() end end)
exports('CloseSquadConsole', closeConsole)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then clearBlips(); closeConsole() end end)
AddEventHandler('bs:hook:player:unloaded', function() Squad = nil; Pending = nil; clearBlips(); closeConsole() end)
