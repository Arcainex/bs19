-- bs_medical - client side of the player body the server leaves behind (sv_corpse.lua): dressing it as the dead player, keeping it dead, the "Search body" option, rot from walkers feeding, and the owner's map blip.

local C = Medical.Corpse or {}
local templates = {}   -- [id] = { outfit, appearance } captured at death
local blips = {}       -- [id] = blip
local rotDrawn = {}    -- [ped] = rot already applied

local function notify(kind, message)
    TriggerEvent('bs:ui:notify', { type = kind, message = message })
end

local function dropTemplate(id)
    templates[id] = nil
end

-- Captured at death before the wipe strips clothes: plain data, no clone ped. ClonePedToTarget copied junk slots and caused "Invalid variation" spam.
RegisterNetEvent('bs:medical:corpse:snapshot', function(id)
    local okO, outfit = pcall(function() return exports.bs_core:CaptureOutfit() end)
    local okD, data = pcall(function() return exports.bs_core:GetData() end)
    templates[id] = {
        outfit = okO and outfit or nil,
        appearance = okD and type(data) == 'table' and data.appearance or nil,
    }
    SetTimeout(30000, function() dropTemplate(id) end)
end)

RegisterNetEvent('bs:medical:corpse:dress', function(id, net)
    Crumb('corpse', 'player body id=%s net=%s', tostring(id), tostring(net))
    CreateThread(function()
        local waited = 0
        while (not net or not NetworkDoesEntityExistWithNetworkId(net)) and waited < 8000 do
            Wait(100) waited = waited + 100
        end
        if not net or not NetworkDoesEntityExistWithNetworkId(net) then return dropTemplate(id) end
        local body = NetToPed(net)

        waited = 0
        while DoesEntityExist(body) and not NetworkHasControlOfEntity(body) and waited < 3000 do
            NetworkRequestControlOfEntity(body)
            Wait(100) waited = waited + 100
        end

        local t = templates[id]
        if t and DoesEntityExist(body) then
            if t.appearance then pcall(function() exports.bs_core:ApplyAppearanceTo(body, t.appearance) end) end
            if t.outfit then pcall(function() exports.bs_core:ApplyOutfit(body, t.outfit) end) end
        end
        dropTemplate(id)

        if DoesEntityExist(body) and NetworkHasControlOfEntity(body) then
            SetBlockingOfNonTemporaryEvents(body, true)
            SetEntityHealth(body, 0)
            if not IsPedRagdoll(body) then SetPedToRagdoll(body, 4000, 4000, 0, false, false, false) end
        end
    end)
end)

-- Rot. Damage packs stack, so each step only adds the next layer.

local ROT_STEPS = {
    { at = 0.05, pack = 'Dirt_Mud' },
    { at = 0.15, pack = 'SCR_DogAttack' },
    { at = 0.35, pack = 'BigHitByVehicle' },
    { at = 0.55, pack = 'SCR_Torture' },
    { at = 0.75, pack = 'BigRunOverByVehicle' },
    { at = 0.90, pack = 'Car_Crash_Heavy' },
}

local function drawRot(ped, rot)
    local done = rotDrawn[ped] or -1
    if rot <= done then return end
    for _, step in ipairs(ROT_STEPS) do
        if rot >= step.at and done < step.at then
            if not DoesEntityExist(ped) then return end
            ApplyPedDamagePack(ped, step.pack, 0.0, 1.0)
            ApplyPedBlood(ped, GetPedBoneIndex(ped, 24818), 0.0, 0.0, 0.0, 'wound_sheet')
        end
    end
    SetPedWetnessHeight(ped, math.min(1.0, rot * 1.2))
    rotDrawn[ped] = rot
end

-- Every body in range: kept dead by its owner and drawn at its rot level.
CreateThread(function()
    while true do
        Wait(1000)
        local seen = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            local st = Entity(ped).state
            local info = st and st.bsCorpse
            if info then
                seen[ped] = true
                if NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true) then
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetEntityHealth(ped, 0)
                end
                drawRot(ped, tonumber(info.rot) or 0.0)
            end
        end
        for ped in pairs(rotDrawn) do if not seen[ped] then rotDrawn[ped] = nil end end
    end
end)

-- Search body

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(1000) end
    exports.bs_interactions:AddType('ped', {{
        label    = L('med.search_body'),
        labelKey = 'med.search_body',
        icon     = 'hand',
        distance = C.searchDistance or 2.5,
        event    = 'bs:medical:corpse:search',
        filters  = { stateTrue = 'bsCorpse', onFoot = true, maxDistance = C.searchDistance or 2.5 },
    }})
end)

local searching = false

AddEventHandler('bs:medical:corpse:search', function(payload)
    local ped = payload and payload.entity
    if searching or not ped or not DoesEntityExist(ped) or not NetworkGetEntityIsNetworked(ped) then return end
    local info = Entity(ped).state.bsCorpse
    if not info then return end

    searching = true
    CreateThread(function()
        local done = exports.bs_interactions:RunSearch(L('med.searching_body'), C.searchTime or 3500, { pose = 'kneel' })
        if done then
            local r = BSB.Await('medical:corpseSearch', 6000, info.id)
            if not r or not r.ok then notify('warn', (r and r.error) or L('med.nothing_left_on_them')) end
        end
        searching = false
    end)
end)

-- Owner blip

RegisterNetEvent('bs:medical:corpse:blip', function(id, pos)
    if blips[id] or not pos then return end
    local b = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(b, C.blipSprite or 310)
    SetBlipColour(b, C.blipColour or 1)
    SetBlipScale(b, 0.85)
    SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(C.blipLabel or L('med.your_body'))
    EndTextCommandSetBlipName(b)
    blips[id] = b
end)

RegisterNetEvent('bs:medical:corpse:gone', function(id)
    if blips[id] then RemoveBlip(blips[id]) blips[id] = nil end
    dropTemplate(id)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(blips) do RemoveBlip(b) end
    for id in pairs(templates) do dropTemplate(id) end
end)
