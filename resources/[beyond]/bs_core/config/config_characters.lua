-- Character creation rules and the appearance schema the NUI creator renders.

Config = Config or {}

Config.Character = {
    nameMinLength   = 2,
    nameMaxLength   = 24,
    minAge          = 18,
    maxAge          = 90,
    genders         = { 'male', 'female' },
    -- Ped models used per gender. Freemode peds keep appearance data portable.
    pedModels = {
        male   = 'mp_m_freemode_01',
        female = 'mp_f_freemode_01',
    },
    -- Deleting a character requires typing its first name in the UI.
    confirmDeleteByName = true,
}

-- Appearance schema. The creator UI is generated from it and the server validates against it, so adding a slider here exposes a new option.
Config.Appearance = {
    { key = 'motherIndex',   label = 'Mother',        type = 'index',  min = 0, max = 45, default = 0 },
    { key = 'fatherIndex',   label = 'Father',        type = 'index',  min = 0, max = 45, default = 0 },
    { key = 'shapeMix',      label = 'Face blend',    type = 'float',  min = 0.0, max = 1.0, default = 0.5 },
    { key = 'skinMix',       label = 'Skin blend',    type = 'float',  min = 0.0, max = 1.0, default = 0.5 },
    { key = 'hairStyle',     label = 'Hair',          type = 'index',  min = 0, max = 76, default = 0 },
    { key = 'hairColor',     label = 'Hair colour',   type = 'index',  min = 0, max = 63, default = 0 },
    { key = 'hairHighlight', label = 'Highlights',    type = 'index',  min = 0, max = 63, default = 0 },
    { key = 'beardStyle',    label = 'Beard',         type = 'index',  min = -1, max = 28, default = -1 },
    { key = 'beardColor',    label = 'Beard colour',  type = 'index',  min = 0, max = 63, default = 0 },
    { key = 'beardOpacity',  label = 'Beard opacity', type = 'float',  min = 0.0, max = 1.0, default = 1.0 },
    { key = 'eyebrowStyle',  label = 'Eyebrows',      type = 'index',  min = -1, max = 33, default = -1 },
    { key = 'eyebrowColor',  label = 'Brow colour',   type = 'index',  min = 0, max = 63, default = 0 },
    { key = 'eyeColor',      label = 'Eyes',          type = 'index',  min = 0, max = 31, default = 0 },
    { key = 'blemishStyle',  label = 'Blemishes',     type = 'index',  min = -1, max = 23, default = -1 },
    { key = 'ageingStyle',   label = 'Ageing',        type = 'index',  min = -1, max = 14, default = -1 },
    { key = 'complexion',    label = 'Complexion',    type = 'index',  min = -1, max = 11, default = -1 },
    { key = 'sunDamage',     label = 'Sun damage',    type = 'index',  min = -1, max = 10, default = -1 },
    { key = 'freckles',      label = 'Freckles',      type = 'index',  min = -1, max = 17, default = -1 },
    { key = 'bodyBlemish',   label = 'Body marks',    type = 'index',  min = -1, max = 11, default = -1 },
    -- Face shape details (SetPedFaceFeature index in feature), -1..1, 0 = parents' shape untouched.
    { key = 'ffNoseWidth',   label = 'Nose width',    type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 0 },
    { key = 'ffNosePeak',    label = 'Nose bridge',   type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 1 },
    { key = 'ffNoseLength',  label = 'Nose length',   type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 2 },
    { key = 'ffBrowHeight',  label = 'Brow height',   type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 6 },
    { key = 'ffCheekHeight', label = 'Cheekbone height', type = 'float', min = -1.0, max = 1.0, default = 0.0, feature = 8 },
    { key = 'ffCheekWidth',  label = 'Cheekbone width',  type = 'float', min = -1.0, max = 1.0, default = 0.0, feature = 9 },
    { key = 'ffEyes',        label = 'Eye opening',   type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 11 },
    { key = 'ffLips',        label = 'Lip fullness',  type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 12 },
    { key = 'ffJawWidth',    label = 'Jaw width',     type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 13 },
    { key = 'ffJawHeight',   label = 'Jaw height',    type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 14 },
    { key = 'ffChinLength',  label = 'Chin length',   type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 15 },
    { key = 'ffChinWidth',   label = 'Chin width',    type = 'float',  min = -1.0, max = 1.0, default = 0.0, feature = 17 },
    -- Makeup overlays (4 makeup, 8 lipstick, 5 blush). -1 = none.
    { key = 'makeupStyle',   label = 'Makeup',        type = 'index',  min = -1, max = 74, default = -1 },
    { key = 'lipstickStyle', label = 'Lipstick',      type = 'index',  min = -1, max = 9,  default = -1 },
    { key = 'lipstickColor', label = 'Lipstick colour', type = 'index', min = 0, max = 63, default = 0 },
    { key = 'blushStyle',    label = 'Blush',         type = 'index',  min = -1, max = 6,  default = -1 },
    { key = 'blushColor',    label = 'Blush colour',  type = 'index',  min = 0, max = 63, default = 0 },
}

-- Per-sex starting look: parents, hair and brows that read as that sex. Used when a character is created without a full appearance and by the creator when the sex is switched (mother 21-41 / father 0-20 are the female / male parent faces; shapeMix 0 = all first parent).
Config.DefaultLook = {
    male   = { motherIndex = 21, fatherIndex = 0, shapeMix = 0.70, skinMix = 0.60, hairStyle = 2, hairColor = 1, hairHighlight = 1,
               beardStyle = -1, eyebrowStyle = 0, eyebrowColor = 1, eyeColor = 4 },
    female = { motherIndex = 21, fatherIndex = 0, shapeMix = 0.30, skinMix = 0.40, hairStyle = 4, hairColor = 3, hairHighlight = 3,
               beardStyle = -1, eyebrowStyle = 4, eyebrowColor = 3, eyeColor = 4,
               makeupStyle = -1, lipstickStyle = -1, blushStyle = -1 },
}

--- Default appearance table built straight from the schema.
function Config.DefaultAppearance(gender)
    local out = { gender = gender or 'male' }
    for _, field in ipairs(Config.Appearance) do
        out[field.key] = field.default
    end
    for k, v in pairs(Config.DefaultLook[gender == 'female' and 'female' or 'male'] or {}) do out[k] = v end
    return out
end
