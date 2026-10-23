-- BeyondSurvival - bs_multichar server: validates the creator choices (identity, kit, outfit, faction) and creates characters through bs_core.

-- Creator data and validation. The client only ever sends choices (ids); every list below is checked against config here.

local function creatorFactions()
    if GetResourceState('bs_tutorial') ~= 'started' then return { factions = {} } end
    local ok, data = pcall(function() return exports.bs_tutorial:CreatorFactions() end)
    if not ok or type(data) ~= 'table' or type(data.factions) ~= 'table' then return { factions = {} } end
    return data
end

local function clothingOn()
    return Multichar.Creator and Multichar.Creator.clothingStep ~= false
end

BSB.RegisterCallback('multichar:creatorData', function(src)
    local fac = creatorFactions()
    return {
        ok = true,
        clothingStep = clothingOn(),
        identity = Multichar.Identity,
        kit = Multichar.Kit,
        clothes = Multichar.Clothes,
        defaults = Multichar.Defaults,
        roll = Multichar.Roll,
        factions = fac.factions,
        bonusCash = fac.bonusCash, bonusXp = fac.bonusXp,
    }
end)

-- Text field: control characters and angle brackets removed, whitespace collapsed, length counted in characters (accents count once).
local function cleanText(v, maxChars)
    if type(v) ~= 'string' then return '' end
    v = v:gsub('[%c<>]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local n = utf8.len(v)
    if not n then return '' end
    if n > maxChars then v = v:sub(1, (utf8.offset(v, maxChars + 1) or (#v + 1)) - 1) end
    return v
end

local function inList(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

local function validateIdentity(src, p)
    local I = Multichar.Identity
    p = type(p) == 'table' and p or {}
    local nick = cleanText(p.nickname, I.nicknameMax)
    if nick ~= '' and (utf8.len(nick) or 0) < 2 then return nil, Lp(src, 'mc.bad_nick') end
    local height = math.floor(tonumber(p.height) or I.heightDefault)
    if height < I.heightMin or height > I.heightMax then return nil, Lp(src, 'mc.bad_height') end
    local blood = tostring(p.bloodType or '')
    if not inList(I.bloodTypes, blood) then return nil, Lp(src, 'mc.bad_blood') end
    local occ = tostring(p.occupation or '')
    if not inList(I.occupations, occ) then return nil, Lp(src, 'mc.bad_occ') end
    local story = cleanText(p.backstory, I.backstoryMax)
    return { nickname = nick, height = height, bloodType = blood, occupation = occ, backstory = story }
end

local function classItems(classId)
    local ok, items = pcall(function() return exports.bs_core:GetConfig('Classes.' .. tostring(classId) .. '.startingItems', {}) end)
    return ok and type(items) == 'table' and items or {}
end

local function validateKit(src, kit, classId)
    local K = Multichar.Kit
    if not K or K.enabled == false then return {} end
    kit = type(kit) == 'table' and kit or {}

    local out = {}
    local own = {}
    for _, e in ipairs(classItems(classId)) do own[e.item] = true end

    local melee
    for _, m in ipairs(K.melee) do if m.id == kit.melee then melee = m end end
    if not melee then return nil, Lp(src, 'mc.bad_kit') end
    -- Already part of the origin's own kit: refused, so it is never granted twice.
    if own[melee.item] then return nil, Lp(src, 'mc.kit_dup') end
    out[#out + 1] = { item = melee.item, amount = 1 }

    local seen, count = {}, 0
    for _, id in ipairs(type(kit.goodies) == 'table' and kit.goodies or {}) do
        local g
        for _, c in ipairs(K.goodies) do if c.id == id then g = c end end
        if not g or seen[id] then return nil, Lp(src, 'mc.bad_kit') end
        -- Already part of the origin's own kit: refused, so it is never stacked twice.
        if own[g.item] then return nil, Lp(src, 'mc.kit_dup_goodie') end
        seen[id] = true
        count = count + 1
        if count > (K.maxGoodies or 2) then return nil, Lp(src, 'mc.bad_kit') end
        out[#out + 1] = { item = g.item, amount = g.amount or 1 }
    end
    return out
end

local DEFAULT_PICK = { top = 0, legs = 0, shoes = 1 }

local function validateOutfit(src, o, gender)
    local C = Multichar.Clothes
    if type(o) ~= 'table' then return nil, Lp(src, 'mc.bad_outfit') end
    local sex = gender == 'female' and 'female' or 'male'
    local comps, props = {}, {}
    local function tex(v) return math.max(0, math.min(C.maxTexture or 24, math.floor(tonumber(v) or 0))) end

    for id, def in pairs(C) do
        if type(def) == 'table' and (def.c or def.p) then
            local pick = type(o[id]) == 'table' and o[id] or {}
            local d = math.floor(tonumber(pick.d) or (def.p and -1) or (DEFAULT_PICK[id] or 0))
            if not inList(def[sex], d) then return nil, Lp(src, 'mc.bad_outfit') end
            if def.c then
                comps[tostring(def.c)] = { drawable = d, texture = tex(pick.t), palette = 2 }
            else
                props[tostring(def.p)] = { drawable = d, texture = d < 0 and -1 or tex(pick.t) }
            end
        end
    end

    -- Fixed bare undershirt (no creator slot for it).
    comps['8'] = { drawable = 15, texture = 0, palette = 2 }

    -- Arms follow the top unless the player set them; always inside armsRange.
    local topD = comps['11'].drawable
    local arms = tonumber(o.arms)
    if arms == nil then arms = C.armsFor[sex][topD] or topD end
    arms = math.floor(arms)
    if arms < C.armsRange[1] or arms > C.armsRange[2] then return nil, Lp(src, 'mc.bad_outfit') end
    comps['3'] = { drawable = arms, texture = 0, palette = 2 }
    return { components = comps, props = props }
end

BSB.RegisterCallback('multichar:create', function(src, payload)
    payload = type(payload) == 'table' and payload or {}

    local gender = payload.gender == 'female' and 'female' or 'male'

    local identity, err = validateIdentity(src, payload.identity)
    if not identity then return { ok = false, error = err } end

    -- Class id is checked by bs_core; it is read back from the same config for the kit.
    local classId = tostring(payload.class or '')
    local okc, classCfg = pcall(function() return exports.bs_core:GetConfig('Classes.' .. classId .. '.label', nil) end)
    if not okc or classCfg == nil then return { ok = false, error = Lp(src, 'ui.pick_origin') } end

    local loadout, kitErr = validateKit(src, payload.kit, classId)
    if not loadout then return { ok = false, error = kitErr } end

    local outfit
    if clothingOn() then
        local oErr
        outfit, oErr = validateOutfit(src, payload.outfit, gender)
        if not outfit then return { ok = false, error = oErr } end
    end

    -- Faction: required when the step exists (the list comes from bs_tutorial and is empty when the picker is off).
    local fac = creatorFactions()
    local chosen
    if #fac.factions > 0 then
        for _, f in ipairs(fac.factions) do if f.id == payload.faction then chosen = f end end
        if not chosen then return { ok = false, error = Lp(src, 'mc.bad_faction') } end
    end

    -- bs_core owns validation and the row itself.
    local result = exports.bs_core:CreateCharacterFor(src, {
        firstName  = payload.firstName,
        lastName   = payload.lastName,
        gender     = payload.gender,
        dob        = payload.dob,
        class      = payload.class,
        appearance = payload.appearance,
    }, {
        outfit = outfit,
        loadout = loadout,
        identity = identity,
        spawn = chosen and chosen.spawn or nil,
        pendingFaction = chosen and chosen.id or nil,
    })

    if not result or not result.ok then
        return { ok = false, error = (result and result.error) or 'could not create character' }
    end

    -- This character already has a faction: the in-game picker must not ask again.
    if chosen and GetResourceState('bs_tutorial') == 'started' then
        pcall(function() exports.bs_tutorial:CreatorFactionChosen(result.charId) end)
    end

    -- bs_guard: the first spawn of a new character is a legit teleport
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 60000) end) end
    return { ok = true, charId = result.charId, characters = exports.bs_core:ListCharacters(src) }
end)

-- In-game appearance edit. bs_vip decides who may (monthly VIP change or staff ticket); bs_core sanitises and stores. Checked again on save.

local function canChange(src)
    if GetResourceState('bs_vip') ~= 'started' then return false, Lp(src, 'mc.na') end
    local ok, can, kind = pcall(function() return exports.bs_vip:CanChangeAppearance(src) end)
    if not ok then return false, Lp(src, 'mc.na') end
    return can == true, kind
end

BSB.RegisterCallback('multichar:appearanceBegin', function(src)
    local can, kind = canChange(src)
    if not can then return { ok = false, error = kind } end
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = Lp(src, 'mc.not_loaded') } end
    -- bs_guard: the appearance booth moves the ped and back
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 600000) end) end
    return {
        ok = true, kind = kind, gender = player.gender,
        appearance = player.appearance or {},
        schema = exports.bs_core:AppearanceSchema(),
    }
end)

BSB.RegisterCallback('multichar:appearanceSave', function(src, appearance)
    if type(appearance) ~= 'table' then return { ok = false, error = Lp(src, 'mc.nothing_save') } end
    local can, kind = canChange(src)
    if not can then return { ok = false, error = kind } end

    local set, clean = exports.bs_core:SetCharacterAppearance(src, appearance)
    if not set then return { ok = false, error = Lp(src, 'mc.cant_save') } end

    local spent = exports.bs_vip:ConsumeAppearanceChange(src)
    if not spent then return { ok = false, error = Lp(src, 'mc.gone') } end
    if GetResourceState('bs_guard') == 'started' then pcall(function() exports.bs_guard:Allow(src, 'teleport', 30000) end) end
    return { ok = true, kind = kind, appearance = clean }
end)

exports.bs_core:RegisterModule('multichar', { side = 'server', version = '0.1.0' })
