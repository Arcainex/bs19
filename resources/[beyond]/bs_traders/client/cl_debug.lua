-- bs_traders - /traderdebug, a staff menu separate from the player shop menu in
-- cl_main.lua. Shares the NUI page but has its own container in html/index.html
-- and script html/js/debug.js.
-- Nothing shown here is trusted: every save is re-checked server-side with
-- isStaff() (sv_traders.lua). The mayuse check below only decides whether to
-- open the menu.

local open = false

local function send(p) SendNUIMessage(p) end

local function say(text)
    TriggerEvent('chat:addMessage', { args = { '^3[traderdebug]', text } })
end

-- Model preview
-- There is no supported way to get a live game texture into the NUI browser, so
-- the preview is a real frozen, invincible ped standing beside the staff member
-- (same approach as bs_multichar's cl_scene.lua). The #dbgRoot panel is fixed
-- width, so there is screen on both sides to see it.

local previewPed = nil
local previewModel = nil

local function clearPreview()
    if previewPed and DoesEntityExist(previewPed) then
        SetEntityAsMissionEntity(previewPed, false, true)
        DeleteEntity(previewPed)
    end
    previewPed = nil
    previewModel = nil
end

-- Spawns (or re-skins) a preview ped beside the player.
-- @return boolean ok, string|nil reason
local function showPreview(modelName)
    modelName = tostring(modelName or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if modelName == '' then return false, 'no model' end

    local hash = joaat(modelName)
    -- Ped models only, so a bad hash is not loaded as a vehicle or object.
    if not IsModelValid(hash) or not IsModelAPed(hash) then
        return false, 'not a ped model'
    end

    if previewModel == modelName and previewPed and DoesEntityExist(previewPed) then
        return true
    end

    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return false, 'model failed to load'
    end

    clearPreview()

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    -- Off to the player's right so it clears the centred panel.
    local right = GetEntityForwardVector(ped)
    local spot = vector3(
        coords.x + right.y * 1.6,
        coords.y - right.x * 1.6,
        coords.z)

    previewPed = CreatePed(4, hash, spot.x, spot.y, spot.z - 1.0,
        (GetEntityHeading(ped) + 180.0) % 360.0, false, true)

    SetEntityInvincible(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedCanRagdoll(previewPed, false)
    SetPedCanBeTargetted(previewPed, false)
    FreezeEntityPosition(previewPed, true)
    SetEntityAsMissionEntity(previewPed, true, true)

    SetModelAsNoLongerNeeded(hash)
    previewModel = modelName
    return true
end

local function closeMenu()
    if not open then return end
    open = false
    clearPreview()
    send({ action = 'debugClose' })
    SetNuiFocus(false, false)
    TriggerEvent('bs:ui:closed', 'traderdebug')
end

local function openMenu()
    if open then return end

    local allowed = BSB.Await('traders:debug:mayuse', 4000)
    if not allowed then
        say(L('trd.e_noperm'))
        return
    end

    local result = BSB.Await('traders:debug:list', 6000)
    if not result or not result.ok then
        say(L('trd.e_unreachable'))
        return
    end

    open = true
    send({ action = 'debugOpen', npcs = result.npcs, missions = result.missions,
        zones = result.zones, factions = result.factions, defaultCategories = result.defaultCategories })
    SetNuiFocus(true, true)
    TriggerEvent('bs:ui:opened', 'traderdebug')
end

RegisterCommand('traderdebug', function() openMenu() end, false)
RegisterKeyMapping('traderdebug', 'Open the trader editor (admin)', 'keyboard', '')

-- Other UIs (F10 panel) open the editor with this event; the server re-checks admin.
RegisterNetEvent('bs:traders:openEditor', function() openMenu() end)

-- NUI callbacks

RegisterNUICallback('debugClose', function(_, cb) closeMenu(); cb({ ok = true }) end)

RegisterNUICallback('debugRefresh', function(_, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:list', 6000)
        cb(r or { ok = false })
    end)
end)

RegisterNUICallback('debugHere', function(_, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:here', 3000)
        cb(r or { ok = false })
    end)
end)

-- Teleport to NPC. The server decides if this player is allowed (isAdmin() in
-- sv_traders.lua) and returns the coordinate, since the cached copy may be stale.
RegisterNUICallback('debugTeleport', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:teleport', 5000, data.npcId)
        if not r or not r.ok then
            cb(r or { ok = false, reason = 'timeout' })
            return
        end

        -- Shared helper fades, loads collision and finds the ground
        exports.bs_core:SafeTeleport(r.x, r.y, r.z, { heading = r.heading or 0.0 })

        cb({ ok = true })
    end)
end)

-- Model preview: a real ped next to the player, see showPreview.
RegisterNUICallback('debugPreviewModel', function(data, cb)
    CreateThread(function()
        local ok, reason = showPreview(data and data.model)
        cb({ ok = ok, reason = reason })
    end)
end)

RegisterNUICallback('debugPreviewClear', function(_, cb)
    clearPreview()
    cb({ ok = true })
end)

RegisterNUICallback('debugSaveNpc', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:saveNpc', 6000, data.npcId, data.patch)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('debugDuplicateNpc', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:duplicateNpc', 6000, data.npcId, data.newId)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('debugResetNpc', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:resetNpc', 6000, data.npcId)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('debugSaveMission', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:saveMission', 6000, data.missionId, data.patch)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

RegisterNUICallback('debugResetMission', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('traders:debug:resetMission', 6000, data.missionId)
        cb(r or { ok = false, reason = 'timeout' })
    end)
end)

-- Safety

-- The shop menu closes itself when anything else opens (cl_main.lua); this does
-- the same back, so the two never fight for NUI focus.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'traderdebug' and open then closeMenu() end
end)

AddEventHandler('bs:ui:panic', closeMenu)
AddEventHandler('bs:hook:player:unloaded', closeMenu)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
    -- The preview ped is a mission entity; remove it on restart.
    clearPreview()
end)
