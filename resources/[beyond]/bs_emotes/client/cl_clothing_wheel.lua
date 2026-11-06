local hidden = {}
local busy = false

-- Wheel order, clockwise from the top. `off` is the drawable worn when the piece is taken off;
-- male/female give it per freemode model when the two differ.
local choices = {
    { id = 'hat', label = 'Headwear', icon = 'hat', prop = 0 },
    { id = 'glasses', label = 'Glasses', icon = 'glasses', prop = 1 },
    { id = 'mask', label = 'Face covering', icon = 'mask', component = 1, off = 0 },
    { id = 'coat', label = 'Outer layer', icon = 'jacket', component = 11, off = 15 },
    { id = 'vest', label = 'Vest', icon = 'vest', component = 9, off = 0 },
    { id = 'gloves', label = 'Gloves', icon = 'gloves', component = 3, off = 15 },
    { id = 'pants', label = 'Trousers', icon = 'pants', component = 4, male = 61, female = 14 },
    { id = 'shoes', label = 'Footwear', icon = 'shoes', component = 6, male = 34, female = 35 },
    { id = 'backpack', label = 'Backpack', icon = 'bag', component = 5, off = 0 },
}

local function freemode(ped)
    local model = GetEntityModel(ped)
    return model == joaat('mp_m_freemode_01') or model == joaat('mp_f_freemode_01')
end

local function itemFor(id)
    for _, item in ipairs(choices) do
        if item.id == id then return item end
    end
end

local function offFor(item, ped)
    return item.off or (GetEntityModel(ped) == joaat('mp_f_freemode_01') and item.female or item.male)
end

local function toggle(item, ped)
    if item.id == 'backpack' then
        hidden.backpack = not hidden.backpack
        TriggerEvent('bs:inventory:backpackAppearance', hidden.backpack)
        return
    end

    local saved = hidden[item.id]
    if saved and saved.ped == ped then
        if item.prop then
            SetPedPropIndex(ped, item.prop, saved.drawable, saved.texture, true)
        else
            SetPedComponentVariation(ped, item.component, saved.drawable, saved.texture, saved.palette)
        end
        hidden[item.id] = nil
        return
    end

    if item.prop then
        local drawable = GetPedPropIndex(ped, item.prop)
        if drawable < 0 then return end
        hidden[item.id] = { ped = ped, drawable = drawable, texture = GetPedPropTextureIndex(ped, item.prop) }
        ClearPedProp(ped, item.prop)
    else
        local drawable = GetPedDrawableVariation(ped, item.component)
        local off = offFor(item, ped)
        if drawable == off then return end
        hidden[item.id] = {
            ped = ped, drawable = drawable,
            texture = GetPedTextureVariation(ped, item.component),
            palette = GetPedPaletteVariation(ped, item.component),
        }
        SetPedComponentVariation(ped, item.component, off, 0, 0)
    end
end

-- 'on' worn, 'off' taken off here and can go back on, 'none' nothing in that slot to take off.
local function stateOf(item, ped)
    if item.id == 'backpack' then return hidden.backpack and 'off' or 'on' end
    local saved = hidden[item.id]
    if saved and saved.ped == ped then return 'off' end
    if item.prop then
        return GetPedPropIndex(ped, item.prop) >= 0 and 'on' or 'none'
    end
    return GetPedDrawableVariation(ped, item.component) ~= offFor(item, ped) and 'on' or 'none'
end

local function slots(ped)
    local out = {}
    for _, item in ipairs(choices) do
        out[#out + 1] = { id = item.id, label = item.label, icon = item.icon, state = stateOf(item, ped) }
    end
    return out
end

-- The wheel has its own page layer in html/ (clothing.css / clothing.js), so the shared bs_radial look stays as it is.
local wheel = { open = false, token = 0, ped = nil, blurred = false }

local function close(token)
    if not wheel.open then return end
    if token ~= nil and token ~= wheel.token then return end
    wheel.open = false
    busy = false
    SendNUIMessage({ action = 'clothingClose' })
    SetNuiFocus(false, false)
    if wheel.blurred then
        TriggerScreenblurFadeOut(90)
        wheel.blurred = false
    end
    TriggerEvent('bs:ui:closed', 'clothing')
end

local function open()
    if busy or wheel.open then return end
    local ped = PlayerPedId()
    if not freemode(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then return end
    busy = true

    -- Announce first so the F5 menu, the emote list or a radial closes before this takes focus.
    TriggerEvent('bs:ui:opened', 'clothing')
    TriggerEvent('bs:ui:requestClose', 'clothing')

    wheel.token = wheel.token + 1
    wheel.open = true
    wheel.ped = ped
    SendNUIMessage({ action = 'clothingOpen', token = wheel.token, title = 'CLOTHING', slots = slots(ped) })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    TriggerScreenblurFadeIn(120)
    wheel.blurred = true

    local token = wheel.token
    CreateThread(function()
        while wheel.open and wheel.token == token do
            Wait(250)
            local now = PlayerPedId()
            if now ~= wheel.ped or IsPedDeadOrDying(now, true) or IsPedInAnyVehicle(now, false) then close() end
        end
    end)
end

RegisterNUICallback('clothingPick', function(data, cb)
    local token = data and tonumber(data.token)
    local item = data and itemFor(tostring(data.id or ''))
    if not wheel.open or token ~= wheel.token or not item or wheel.ped ~= PlayerPedId() then
        cb({ ok = false })
        return
    end
    toggle(item, wheel.ped)
    -- The wheel stays open, so several pieces can be swapped in one go.
    cb({ ok = true, slots = slots(wheel.ped) })
end)

RegisterNUICallback('clothingClose', function(data, cb)
    close(data and tonumber(data.token) or nil)
    cb({ ok = true })
end)

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'clothing' then close() end
end)
AddEventHandler('bs:ui:requestClose', function(who)
    if who ~= 'clothing' then close() end
end)
AddEventHandler('bs:hook:player:unloaded', function() close() end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not wheel.open then return end
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0)
    TriggerEvent('bs:ui:closed', 'clothing')
end)

-- No key of its own (F3 is the squad menu, F7 the VIP menu): opened from the F5 menu, or /bs_clotheswheel.
RegisterCommand('bs_clotheswheel', open, false)
exports('OpenClothingWheel', open)

AddEventHandler('playerSpawned', function() hidden = {} end)
