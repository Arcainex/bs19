-- BeyondSurvival - captures worn clothing and carried weapon for the character-select preview. Stored in character metadata.

BS.Outfit = {}

-- Freemode component/prop ids. Names are for readability in the saved JSON.
local COMPONENTS = {
    [0] = 'face', [1] = 'mask', [2] = 'hair', [3] = 'arms', [4] = 'legs',
    [6] = 'shoes', [7] = 'accessory', [8] = 'undershirt',
    [9] = 'armour', [10] = 'decal', [11] = 'top',
}

-- Component 5 is the parachute slot on freemode models. The engine sets it on its own, so it is never captured or applied.
local PARACHUTE_COMPONENT = 5
local PROPS = { [0] = 'hat', [1] = 'glasses', [2] = 'ear', [6] = 'watch', [7] = 'bracelet' }

-- Starting clothes: jbib 0 with matching arms 0, undershirt/none 15 (same bare value as bs_traders), jeans, plain worn shoes per sex (shoe drawable 0 on both models is a checkered skate shoe).
local DEFAULTS_BY_SEX = {
    male   = { [3] = 0, [4] = 0, [6] = 1, [8] = 15, [11] = 0 },
    female = { [3] = 0, [4] = 0, [6] = 1, [8] = 15, [11] = 0 },
}
local FEMALE_HASH = GetHashKey('mp_f_freemode_01')
local UPPER = { 3, 8, 11 }

local function defaultsFor(ped)
    return GetEntityModel(ped) == FEMALE_HASH and DEFAULTS_BY_SEX.female or DEFAULTS_BY_SEX.male
end

--- Puts the default complete outfit on a ped (any freemode model).
function BS.Outfit.ApplyDefaults(ped)
    for comp, drawable in pairs(defaultsFor(ped)) do
        local count = GetNumberOfPedDrawableVariations(ped, comp)
        if count > 0 then
            SetPedComponentVariation(ped, comp, math.min(drawable, count - 1), 0, 2)
        end
    end
end

-- Repairs a saved outfit in a copy. Old creator saved 3/8/11 all at 0 (arms and undershirt not matching), which leaves the chest bare.
local function repaired(ped, outfit)
    local comps = {}
    for id, v in pairs(outfit.components or {}) do comps[id] = v end
    local function d(id) local v = comps[tostring(id)]; return v and tonumber(v.drawable) end

    local bad = (d(3) == nil or d(11) == nil or d(8) == nil)
    if d(3) == 0 and d(8) == 0 and d(11) == 0 then bad = true end
    for _, id in ipairs(UPPER) do
        local count = GetNumberOfPedDrawableVariations(ped, id)
        local val = d(id)
        if val and count > 0 and (val < 0 or val >= count) then bad = true end
    end
    if bad then
        for _, id in ipairs(UPPER) do
            comps[tostring(id)] = { drawable = defaultsFor(ped)[id], texture = 0, palette = 2 }
        end
    end
    return { components = comps, props = outfit.props }
end

-- Arms that fit each plain top (same table as bs_multichar's armsFor). Used to repair new characters saved with arms = top id.
local TORSO = {
    male = {
        [0] = 0, [1] = 0, [2] = 2, [3] = 14, [4] = 14, [5] = 5, [6] = 14, [7] = 14, [8] = 8, [9] = 0, [10] = 14,
        [11] = 15, [12] = 12, [13] = 11, [14] = 12, [15] = 15, [16] = 0, [17] = 5, [18] = 0, [19] = 14, [20] = 14, [21] = 15,
        [22] = 0, [23] = 14, [24] = 14, [25] = 15, [26] = 11, [27] = 14, [28] = 14, [29] = 14, [30] = 14,
    },
    female = {
        [0] = 0, [1] = 5, [2] = 2, [3] = 3, [4] = 4, [5] = 4, [6] = 5, [7] = 5, [8] = 5, [9] = 0, [10] = 5,
        [11] = 4, [12] = 12, [13] = 15, [14] = 14, [15] = 15, [16] = 15, [17] = 0, [18] = 15, [19] = 0, [20] = 5, [21] = 0,
        [22] = 4, [23] = 4, [24] = 5, [25] = 5, [26] = 12, [27] = 0, [28] = 15, [29] = 9, [30] = 2,
    },
}
-- Bare upper body (arms/undershirt/top 15): always valid on both freemode models, last resort.
local BARE = { [3] = 15, [8] = 15, [11] = 15 }
local MALE_HASH = GetHashKey('mp_m_freemode_01')

local function compOk(ped, comp)
    local d = GetPedDrawableVariation(ped, comp)
    local count = GetNumberOfPedDrawableVariations(ped, comp)
    if d < 0 or count <= 0 or d >= count then return false end
    return IsPedComponentVariationValid(ped, comp, d, math.max(0, GetPedTextureVariation(ped, comp)))
end

local function upperOk(ped)
    for _, id in ipairs(UPPER) do
        if not compOk(ped, id) then return false end
    end
    return true
end

--- Snapshot of arms/undershirt/top drawables, to spot a later overwrite.
function BS.Outfit.UpperSnapshot(ped)
    local snap = {}
    for _, id in ipairs(UPPER) do
        snap[id] = { GetPedDrawableVariation(ped, id), GetPedTextureVariation(ped, id) }
    end
    return snap
end

--- Makes sure a freemode ped has a complete upper body.
--- fixArms: also replace arms that only copy the top id (old creator bug) with the matching torso.
--- @return string|nil what was changed
function BS.Outfit.EnsureUpper(ped, outfit, fixArms)
    if not ped or not DoesEntityExist(ped) then return nil end
    local model = GetEntityModel(ped)
    if model ~= MALE_HASH and model ~= FEMALE_HASH then return nil end
    local fixed

    -- Engine refused part of the outfit (model not ready yet): put it on again.
    if outfit and not upperOk(ped) then
        BS.Outfit.Apply(ped, outfit)
        fixed = 'reapplied'
    end

    if fixArms then
        local top, arms = GetPedDrawableVariation(ped, 11), GetPedDrawableVariation(ped, 3)
        local want = TORSO[model == FEMALE_HASH and 'female' or 'male'][top]
        if want and arms == top and arms ~= want and want < GetNumberOfPedDrawableVariations(ped, 3) then
            SetPedComponentVariation(ped, 3, want, 0, 2)
            fixed = 'arms'
        end
    end

    if not upperOk(ped) then
        BS.Outfit.ApplyDefaults(ped)
        fixed = 'defaults'
        if not upperOk(ped) then
            for comp, d in pairs(BARE) do SetPedComponentVariation(ped, comp, d, 0, 2) end
            fixed = 'bare'
        end
    end
    return fixed
end

--- Reads the local ped's full clothing state.
function BS.Outfit.Capture()
    local ped = PlayerPedId()
    local out = { components = {}, props = {} }

    for id in pairs(COMPONENTS) do
        out.components[tostring(id)] = {
            drawable = GetPedDrawableVariation(ped, id),
            texture  = GetPedTextureVariation(ped, id),
            palette  = GetPedPaletteVariation(ped, id),
        }
    end

    for id in pairs(PROPS) do
        local drawable = GetPedPropIndex(ped, id)
        out.props[tostring(id)] = {
            drawable = drawable,
            texture  = drawable == -1 and -1 or GetPedPropTextureIndex(ped, id),
        }
    end

    return out
end

-- Applies an outfit to any ped. Drawable/texture indexes are clamped to what the model has, because invalid ones are refused by the engine ("Invalid variation") and half-apply the outfit.
function BS.Outfit.Apply(ped, outfit)
    if not outfit or not DoesEntityExist(ped) then return false end
    outfit = repaired(ped, outfit)

    for id, v in pairs(outfit.components or {}) do
        local slot = tonumber(id)
        -- Old saved outfits may still carry component 5; skipping it keeps the parachute off.
        -- Components are 0-11 only, anything else causes the "Invalid variation" spam.
        if slot and slot >= 0 and slot <= 11 and slot ~= PARACHUTE_COMPONENT then
            local count = GetNumberOfPedDrawableVariations(ped, slot)
            if count > 0 then
                local drawable = math.max(0, math.min(math.floor(v.drawable or 0), count - 1))
                local textures = GetNumberOfPedTextureVariations(ped, slot, drawable)
                local texture = math.max(0, math.min(math.floor(v.texture or 0), math.max(0, textures - 1)))
                SetPedComponentVariation(ped, slot, drawable, texture, v.palette or 2)
            end
        end
    end

    for id, v in pairs(outfit.props or {}) do
        local slot = tonumber(id)
        -- Props are 0-7.
        if slot and slot >= 0 and slot <= 7 then
            if (v.drawable or -1) < 0 then
                ClearPedProp(ped, slot)
            else
                local count = GetNumberOfPedPropDrawableVariations(ped, slot)
                if count > 0 then
                    local drawable = math.max(0, math.min(math.floor(v.drawable), count - 1))
                    local textures = GetNumberOfPedPropTextureVariations(ped, slot, drawable)
                    local texture = math.max(0, math.min(math.floor(v.texture or 0), math.max(0, textures - 1)))
                    SetPedPropIndex(ped, slot, drawable, texture, true)
                else
                    ClearPedProp(ped, slot)
                end
            end
        end
    end

    return true
end

--- The weapon currently in hand, or nil when unarmed.
function BS.Outfit.CurrentWeapon()
    local ped = PlayerPedId()
    local _, hash = GetCurrentPedWeapon(ped, true)
    if not hash or hash == GetHashKey('WEAPON_UNARMED') then return nil end
    return hash
end

--- Pushes the current outfit + weapon to the server. Called on a timer and
--- whenever the character is about to be unloaded.
function BS.Outfit.Push()
    if not BS.IsLoaded() then return end
    TriggerServerEvent(BS.Events.UpdateOutfit, BS.Outfit.Capture(), BS.Outfit.CurrentWeapon())
end

CreateThread(function()
    while true do
        Wait(60000)
        BS.Outfit.Push()
    end
end)

BS.On('player:unloaded', function() end)   -- placeholder: unload already saved server-side

--- Anything that changes what the player is wearing raises this, and the
--- server gets the new outfit without that resource needing to know how it is
--- stored. bs_emotes uses it after taking a jacket off.
AddEventHandler('bs:outfit:push', function() BS.Outfit.Push() end)

exports('CaptureOutfit', BS.Outfit.Capture)
exports('ApplyOutfit', BS.Outfit.Apply)
