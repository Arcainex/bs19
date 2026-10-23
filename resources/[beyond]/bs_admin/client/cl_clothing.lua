-- bs_admin - live clothing tuner for staff

-- Components worth tuning: 11 top
local COMPONENTS = {
    { id = 'top',        index = 11, label = 'Top (11)' },
    { id = 'arms',       index = 3,  label = 'Arms / torso (3)' },
    { id = 'undershirt', index = 8,  label = 'Undershirt (8)' },
    { id = 'legs',       index = 4,  label = 'Legs (4)' },
    { id = 'shoes',      index = 6,  label = 'Shoes (6)' },
    { id = 'mask',       index = 1,  label = 'Mask (1)' },
}

local function ped() return PlayerPedId() end

-- Male or female by the model on the player right now, not by stored data.
local function genderOf()
    local model = GetEntityModel(ped())
    if model == GetHashKey('mp_f_freemode_01') then return 'female' end
    return 'male'
end

-- Current state and bounds of every tunable component. max is the real ceiling so the panel can show e.g. 5 / 34.
local function readAll()
    local p = ped()
    local out = {}

    for _, c in ipairs(COMPONENTS) do
        local drawable = GetPedDrawableVariation(p, c.index)
        local count = GetNumberOfPedDrawableVariations(p, c.index)
        out[#out + 1] = {
            id = c.id, index = c.index, label = c.label,
            drawable = drawable,
            texture = GetPedTextureVariation(p, c.index),
            max = math.max(0, count - 1),
            textureMax = math.max(0, GetNumberOfPedTextureVariations(p, c.index, drawable) - 1),
        }
    end

    return { ok = true, gender = genderOf(), components = out }
end

RegisterNUICallback('clothRead', function(_, cb) cb(readAll()) end)

-- Set one component, clamped to what the model has so a held stepper stops at the end of the list
RegisterNUICallback('clothSet', function(data, cb)
    local p = ped()
    local index = tonumber(data and data.index)
    if not index then return cb({ ok = false, error = 'no component index' }) end

    local count = GetNumberOfPedDrawableVariations(p, index)
    if count <= 0 then return cb({ ok = false, error = 'model has no variations for that component' }) end

    local drawable = math.max(0, math.min(math.floor(tonumber(data.drawable) or 0), count - 1))
    local texCount = GetNumberOfPedTextureVariations(p, index, drawable)
    local texture = math.max(0, math.min(math.floor(tonumber(data.texture) or 0), math.max(0, texCount - 1)))

    SetPedComponentVariation(p, index, drawable, texture, 2)
    cb(readAll())
end)

-- Strip to bare
RegisterNUICallback('clothStrip', function(_, cb)
    if not Clothing or not Clothing.Slots then
        return cb({ ok = false, error = 'Clothing config not loaded - is bs_inventory present?' })
    end

    local p = ped()
    local gender = genderOf()

    for _, slot in ipairs(Clothing.Slots) do
        if slot.kind == 'component' and slot.off then
            local bare = slot.off[gender]
            if bare then
                local count = GetNumberOfPedDrawableVariations(p, slot.index)
                if count > 0 then
                    SetPedComponentVariation(p, slot.index,
                        math.max(0, math.min(math.floor(bare), count - 1)), 0, 2)
                end
            end

            -- The arms follow the top down, same as the real apply path.
            if slot.arms and slot.arms[gender] then
                local armsCount = GetNumberOfPedDrawableVariations(p, 3)
                if armsCount > 0 then
                    SetPedComponentVariation(p, 3,
                        math.max(0, math.min(math.floor(slot.arms[gender]), armsCount - 1)), 0, 2)
                end
            end
        elseif slot.kind == 'prop' then
            ClearPedProp(p, slot.index)
        end
    end

    local state = readAll()
    state.stripped = true
    cb(state)
end)

-- Read the tuner state back after a restore
RegisterNUICallback('clothScan', function(data, cb)
    local p = ped()
    local index = tonumber(data and data.index) or 3
    local count = GetNumberOfPedDrawableVariations(p, index)
    if count <= 0 then return cb({ ok = false, error = 'no variations for that component' }) end

    local valid = {}
    for d = 0, math.min(count - 1, 255) do
        local ok, isValid = pcall(IsPedComponentVariationValid, p, index, d, 0)
        -- Unknown counts as usable, so a possible match is never hidden.
        if not ok or isValid ~= false then valid[#valid + 1] = d end
    end

    cb({ ok = true, index = index, total = count, valid = valid })
end)

RegisterNUICallback('clothPoll', function(_, cb) cb(readAll()) end)
