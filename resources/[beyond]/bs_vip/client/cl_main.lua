-- bs_vip - local mirror of the account's VIP state, exports other resources
-- read (non-yielding), and the F7 panel.

local current = { tier = nil, level = 0, prefs = {}, unlocks = {}, appearance = {} }

RegisterNetEvent('bs:vip:sync', function(payload)
    if type(payload) ~= 'table' then return end
    payload.level = tonumber(payload.level) or 0
    payload.prefs = payload.prefs or {}
    current = payload
    TriggerEvent('bs:vip:changed', payload)
end)

-- Exports

local function hasPerk(perk) return Vip.PerkAllowed(current.level or 0, perk) end

exports('Current', function() return current end)
exports('IsVIP', function() return current.tier ~= nil end)
exports('GetTier', function() return current.tier end)
exports('TierLevel', function() return current.level or 0 end)
exports('HasPerk', hasPerk)
exports('PerkValue', function(perk, key, default)
    if not hasPerk(perk) then return default end
    local v = Vip.Perks[perk] and Vip.Perks[perk][key or 'bonus']
    if v == nil then return default end
    return v
end)
-- Saved choice if the perk is active, else nil.
exports('Pref', function(key, perk)
    if perk and not hasPerk(perk) then return nil end
    local v = current.prefs and current.prefs[key]
    if v == '' then return nil end
    return v
end)
-- Chosen booster skin ('drone'|'turret') as its config row, or nil.
exports('BoosterSkin', function(kind)
    if not hasPerk('boosterSkins') then return nil end
    local list = kind == 'drone' and Vip.DroneSkins or Vip.TurretSkins
    local id = current.prefs and current.prefs[kind == 'drone' and 'droneSkin' or 'turretSkin']
    local row = id and Vip.FindById(list, id)
    if not row or row.id == 'default' then return nil end
    return row
end)

-- Chosen stash marker model, or nil.
exports('StashSkinModel', function()
    if not hasPerk('stashSkin') then return nil end
    local row = Vip.FindById(Vip.StashSkins, current.prefs and current.prefs.stashSkin)
    return row and row.model or nil
end)

exports('AllowedColours', function() return Vip.AllowedColours(current.level or 0) end)
exports('Status', function() return BSB.Await('vip:status', 6000) end)

-- Panel

local open = false

local function send(p) SendNUIMessage(p) end

local function closePanel()
    if not open then return end
    open = false
    send({ action = 'close' })
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(200)
    TriggerEvent('bs:ui:closed', 'vip')
end

local function started(res) return GetResourceState(res) == 'started' end

local function fxOptions()
    if not started('bs_zombies') then return nil end
    local ok, o = pcall(function() return exports.bs_zombies:GetFxOptions() end)
    return ok and o or nil
end

local function chatView()
    if not started('bs_chat') then return nil end
    local ok, v = pcall(function() return exports.bs_chat:GetVipStyles() end)
    if not ok then return nil end
    return v ~= false
end

-- The vehicle you are driving, if any. Plates are changed on that car.
local function myVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

local function vehicleInfo()
    local veh = myVehicle()
    if not veh then return nil end
    return {
        plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
    }
end

-- Config the page needs for pickers and locks. Sent once per open.
local function staticData()
    local tiers = {}
    for _, id in ipairs(Vip.Order) do
        local t = Vip.Tiers[id]
        tiers[#tiers + 1] = { id = t.id, level = t.level, label = t.label, colour = t.colour }
    end
    local perks = {}
    for _, id in ipairs(Vip.PerkOrder) do
        local p = Vip.Perks[id]
        perks[#perks + 1] = { id = id, label = p.label, minTier = p.minTier, bonus = p.bonus, pct = p.pct }
    end
    return {
        tiers = tiers, perks = perks, palette = Vip.Palette,
        tagStyles = Vip.TagStyles, blipColours = Vip.BlipColours, stashSkins = Vip.StashSkins,
        droneSkins = Vip.DroneSkins, turretSkins = Vip.TurretSkins,
        killfeed = Vip.KillfeedStyles, deathscreen = Vip.DeathStyles, banners = Vip.Banners,
        plate = { min = Vip.Plate.minLength, max = Vip.Plate.maxLength },
        key = Vip.Settings.panelKey or 'F7',
    }
end

local function dynamicData()
    local status = BSB.Await('vip:status', 6000)
    local stashes = nil
    if started('bs_stash') then
        local r = BSB.Await('stash:mine', 5000)
        stashes = (r and r.ok) and r.stashes or nil
    end
    local name = nil
    pcall(function()
        local p = exports.bs_core:GetData()
        if p then name = ((p.firstName or '') .. ' ' .. (p.lastName or '')):gsub('^%s+', '') end
    end)
    return {
        status = status, fx = fxOptions(), chatView = chatView(),
        vehicle = vehicleInfo(), stashes = stashes, name = name ~= '' and name or GetPlayerName(PlayerId()),
    }
end

local function openPanel()
    if open then return end
    if not exports.bs_core:IsLoaded() then return end
    local data = dynamicData()
    open = true
    TriggerScreenblurFadeIn(300)
    send({ action = 'open', config = staticData(), data = data })
    SetNuiFocus(true, true)
    TriggerEvent('bs:ui:opened', 'vip')
end

RegisterCommand(Vip.Settings.panelCommand or 'bs_vippanel', function()
    if open then closePanel() else CreateThread(openPanel) end
end, false)
RegisterKeyMapping(Vip.Settings.panelCommand or 'bs_vippanel', L('vip.keymap'), 'keyboard', Vip.Settings.panelKey or 'F7')

-- ESC / backspace close; never leave the player stuck with focus.
CreateThread(function()
    while true do
        if open then
            Wait(0)
            if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then closePanel() end
        else
            Wait(250)
        end
    end
end)

RegisterNUICallback('close', function(_, cb) closePanel(); cb({ ok = true }) end)

RegisterNUICallback('refresh', function(_, cb)
    CreateThread(function() cb({ ok = true, data = dynamicData() }) end)
end)

RegisterNUICallback('setPref', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('vip:setPref', 6000, data and data.key, data and data.value)
        cb(r or { ok = false, error = L('vip.no_answer') })
    end)
end)

-- General combat feedback settings (everyone) + VIP colours. Owned by bs_zombies.
RegisterNUICallback('setFx', function(data, cb)
    if not started('bs_zombies') then return cb({ ok = false, error = 'bs_zombies is not running.' }) end
    local ok, r = pcall(function() return exports.bs_zombies:SetFxOption(data.key, data.value) end)
    if not ok or type(r) ~= 'table' then return cb({ ok = false, error = L('vip.cant_change') }) end
    cb(r)
end)

RegisterNUICallback('setChatView', function(data, cb)
    if not started('bs_chat') then return cb({ ok = false }) end
    pcall(function() exports.bs_chat:SetVipStyles(data and data.on == true) end)
    cb({ ok = true, on = chatView() })
end)

RegisterNUICallback('setPlate', function(data, cb)
    local veh = myVehicle()
    if not veh then return cb({ ok = false, error = L('vip.sit_driver2') }) end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    CreateThread(function()
        local r = BSB.Await('vehicles:setPlate', 8000, netId, data and data.text)
        cb(r or { ok = false, error = L('vip.no_answer') })
    end)
end)

RegisterNUICallback('renameStash', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('stash:rename', 6000, tonumber(data and data.id), data and data.label)
        if r and r.ok then TriggerEvent('bs:stash:refresh') end
        cb(r or { ok = false, error = L('vip.no_answer') })
    end)
end)

RegisterNUICallback('appearance', function(_, cb)
    if not started('bs_multichar') then return cb({ ok = false, error = L('vip.no_creator') }) end
    closePanel()
    pcall(function() exports.bs_multichar:OpenAppearanceEditor() end)
    cb({ ok = true })
end)

-- The live preview of emote / walk locks is in bs_emotes; this just opens it.
RegisterNUICallback('openEmotes', function(_, cb)
    closePanel()
    ExecuteCommand('emotemenu')
    cb({ ok = true })
end)

AddEventHandler('bs:ui:opened', function(what) if what ~= 'vip' and open then closePanel() end end)
AddEventHandler('bs:ui:requestClose', function(who) if who ~= 'vip' and open then closePanel() end end)
AddEventHandler('bs:hook:player:unloaded', function()
    closePanel()
    current = { tier = nil, level = 0, prefs = {}, unlocks = {}, appearance = {} }
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false); TriggerScreenblurFadeOut(0); TriggerEvent('bs:ui:closed', 'vip') end
end)

exports('OpenPanel', function() CreateThread(openPanel) end)
exports('ClosePanel', closePanel)
