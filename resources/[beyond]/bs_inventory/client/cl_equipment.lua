-- bs_inventory - equipment state: what your gear does (carry weight, armour, stealth), not how it looks.
-- This file never touches the ped. Appearance comes only from the wardrobe (bs_traders, saved by bs_core's outfit layer); gear slots are invisible stat items. Writing components from here used to overwrite bought clothes.

local Equip = { last = nil, stats = {}, backpackBase = nil }

-- Wardrobe clothing stays authoritative. The backpack is the only inventory item that is visible: it uses the GTA bag component, never writes an outfit snapshot, and restores what the wardrobe had there when unequipped.
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

-- Bookkeeping only. `worn` is slot id -> item name for everything equipped, replaced as a whole because that is what the server sends.
-- Nothing is pushed to the outfit store from here; bs_core's outfit layer is written only by the wardrobe on purchase plus its 60-second autosave, so there is a single writer.
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

-- Gear stats for other systems. bs_zombies reads them for the bite (armour) and sight range (stealth), both client-side decisions.
-- Returns a copy so consumers cannot edit this resource's state.
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
-- Stamina, not move rate, so this never fights bs_core's winded move-rate override.
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
