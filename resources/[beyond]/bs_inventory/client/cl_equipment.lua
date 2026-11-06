-- bs_inventory - equipment state: what your gear does (carry weight, armour, stealth), not how it looks.

local Equip = { last = nil, stats = {}, backpackBase = nil }

local function clearBackpackProp()
    if Equip.backpackProp and DoesEntityExist(Equip.backpackProp) then
        DeleteEntity(Equip.backpackProp)
    end
    Equip.backpackProp, Equip.backpackModel, Equip.backpackPed = nil, nil, nil
end

local function showBackpackProp(ped, family, stage, fit)
    stage = math.max(1, math.min(5, tonumber(stage) or 1))
    local model = GetHashKey(('bs_pack_%s_%d'):format(family, stage))
    if Equip.backpackModel == model and Equip.backpackPed == ped
        and Equip.backpackProp and DoesEntityExist(Equip.backpackProp) then return true end
    clearBackpackProp()
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return false end
    local at = GetEntityCoords(ped)
    local object = CreateObjectNoOffset(model, at.x, at.y, at.z, true, true, false)
    SetModelAsNoLongerNeeded(model)
    if object == 0 or not DoesEntityExist(object) then return false end
    SetEntityCollision(object, false, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 24818),
        fit.x, fit.y, fit.z, fit.rx, fit.ry, fit.rz,
        false, false, false, false, 2, true)
    Equip.backpackProp, Equip.backpackModel, Equip.backpackPed = object, model, ped
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearBackpackProp() end
end)

-- Wardrobe clothing stays authoritative.
local function syncBackpackVisual()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    -- The server sends the chosen look (packVisual), or hidden. Falls back to the item's default look.
    local itemName = Equip.last and Equip.last.backpack
    local def = itemName and Clothing and Clothing.Items and Clothing.Items[itemName]
    local vis = Equip.packVisual
    local wear = (vis and not vis.hidden and vis) or (not vis and def and def.data and def.data.wear) or nil
    local model = GetEntityModel(ped)
    local key = model == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
    local look = wear and wear[key]
    if Equip.basePed and Equip.basePed ~= ped then Equip.backpackBase = nil end
    Equip.basePed = ped
    local family = vis and vis.family
    local fit = Clothing.BackpackFit and Clothing.BackpackFit[key]
    local useProp = Clothing.UseCustomBackpackProps and family and fit and not Equip.hiddenOverride and not vis.hidden
        and showBackpackProp(ped, family, vis.fillStage, fit)
    if not useProp then clearBackpackProp() end

    if useProp then
        if not Equip.backpackBase then
            Equip.backpackBase = {
                drawable = GetPedDrawableVariation(ped, 5),
                texture = GetPedTextureVariation(ped, 5),
                palette = GetPedPaletteVariation(ped, 5),
            }
        end
        if GetPedDrawableVariation(ped, 5) ~= 0 then
            SetPedComponentVariation(ped, 5, 0, 0, 0)
        end
        return
    end
    if Equip.hiddenOverride then look = nil end
    if look then
        if not Equip.backpackBase then
            Equip.backpackBase = {
                drawable = GetPedDrawableVariation(ped, 5),
                texture = GetPedTextureVariation(ped, 5),
                palette = GetPedPaletteVariation(ped, 5),
            }
        end
        SetPedComponentVariation(ped, 5, look.d or 0, look.t or 0, 0)
    elseif Equip.backpackBase then
        local base = Equip.backpackBase
        SetPedComponentVariation(ped, 5, base.drawable, base.texture, base.palette or 0)
        Equip.backpackBase = nil
    end
end

RegisterNetEvent('bs:inventory:backpackAppearance', function(hidden)
    Equip.hiddenOverride = hidden and true or false
    syncBackpackVisual()
end)

CreateThread(function()
    while true do
        Wait(1000)
        if Equip.basePed and Equip.basePed ~= PlayerPedId() then syncBackpackVisual() end
    end
end)
-- Bookkeeping only. `worn` is slot id to item name for everything equipped
function Equip.Apply(worn)
    Equip.last = worn or {}
    syncBackpackVisual()
end

RegisterNetEvent('bs:inventory:state', function(payload)
    if type(payload) ~= 'table' or type(payload.player) ~= 'table' then return end
    if payload.player.worn == nil then return end

    -- Totals come down with the state. The server already ran Clothing.Aggregate for the carry limit; recomputing here could disagree.
    Equip.stats = payload.player.equipStats or {}
    Equip.packVisual = payload.player.packVisual
    Equip.weight, Equip.maxWeight = tonumber(payload.player.weight) or 0, tonumber(payload.player.maxWeight) or 40

    Equip.Apply(payload.player.worn)
end)

-- Gear stats for other systems. bs_zombies reads them for the bite (armour) and sight range (stealth)
exports('EquipmentStats', function()
    local out = {}
    for k, v in pairs(Equip.stats or {}) do out[k] = v end
    return out
end)

-- What is worn right now, for anything that wants to ask (armour, warmth).
exports('WornItems', function()
    local out = {}
    for k, v in pairs(Equip.last or {}) do out[k] = v end
    return out
end)

exports('IsWearing', function(itemName)
    for _, item in pairs(Equip.last or {}) do
        if item == itemName then return true end
    end
    return false
end)

BSInvEquipment = Equip

-- Heavy load: above heavyLoadAt of the carry limit sprinting drains stamina faster; over the limit you cannot sprint.
CreateThread(function()
    local toldAt = -60000
    while true do
        local ratio = (Equip.maxWeight and Equip.maxWeight > 0) and (Equip.weight or 0) / Equip.maxWeight or 0
        local from = Inventory.Settings.heavyLoadAt or 0.8
        if ratio >= 1.0 then
            Wait(0)
            DisableControlAction(0, 21, true)   -- sprint, must be every frame
            -- Say why, otherwise it looks like a stuck sprint
            if IsDisabledControlJustPressed(0, 21) and GetGameTimer() - toldAt > 15000 then
                toldAt = GetGameTimer()
                TriggerEvent('bs:ui:notify', { type = 'warn', message = L('inv.cant_sprint_heavy'), duration = 4000 })
            end
        else
            Wait(250)
            if ratio >= from and IsPedSprinting(PlayerPedId()) then
                -- Extra drain per 250 ms, growing to heavySprintDrain at the limit.
                local drain = (ratio - from) / (1.0 - from) * (Inventory.Settings.heavySprintDrain or 1.5)
                pcall(function() exports.bs_core:AdjustStamina(-drain) end)
            end
        end
    end
end)
