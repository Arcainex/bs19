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

-- Always read the CURRENT wardrobe rules; no restart is needed after an admin disables a texture.
local function currentClothingRules()
    local raw = LoadResourceFile('bs_clothing', 'data/clothing_rules.json')
    if not raw then return { disabled = {}, disabledTextures = {}, torsoMappings = {} } end
    local ok, rules = pcall(json.decode, raw)
    if not ok or type(rules) ~= 'table' then return { disabled = {}, disabledTextures = {}, torsoMappings = {} } end
    return {
        disabled = type(rules.disabled) == 'table' and rules.disabled or {},
        disabledTextures = type(rules.disabledTextures) == 'table' and rules.disabledTextures or {},
        torsoMappings = type(rules.torsoMappings) == 'table' and rules.torsoMappings or {},
    }
end

-- The scene uses a separate non-player ped. Provide the stored weapons
-- for ONLY a character belonging to this connected account.
BSB.RegisterCallback('multichar:previewCarry', function(src, charId)
    charId = tonumber(charId)
    if not charId or charId < 1 or charId % 1 ~= 0 then
        return { ok = false, items = {} }
    end
    local owned = false
    local okList, characters = pcall(function() return exports.bs_core:ListCharacters(src) end)
    if not okList or type(characters) ~= 'table' then return { ok = false, items = {} } end
    for _, char in ipairs(characters) do
        if tonumber(char.id) == charId then owned = true; break end
    end
    if not owned then return { ok = false, items = {} } end
    if GetResourceState('bs_inventory') ~= 'started' then return { ok = false, items = {} } end
    local ok, items = pcall(function()
        return exports.bs_inventory:WeaponCarryCharacterPreviewItems(charId)
    end)
    if not ok or type(items) ~= 'table' then
        print('^3[Alpha-Z]^7 Konnte Hotbar fuer Vorschau nicht laden: '..tostring(items))
        return { ok = false, items = {} }
    end
    return { ok = true, items = items }
end)

local function readDefaultOutfits()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/default_outfits.json')
    local ok, data = pcall(json.decode, raw or '{}')
    return ok and type(data) == 'table' and data or {}
end
local function canSetDefault(src)
    return src > 0 and IsPlayerAceAllowed(src, 'alphaz.outfit.admin')
end

BSB.RegisterCallback('multichar:creatorData', function(src)
    local fac = creatorFactions()
    return {
        ok = true,
        clothingStep = clothingOn(),
        identity = Multichar.Identity,
        kit = Multichar.Kit,
        clothes = Multichar.Clothes,
        clothingRules = currentClothingRules(),
        defaults = Multichar.Defaults,
        defaultOutfits = readDefaultOutfits(),
        canSaveDefaultOutfit = canSetDefault(src),
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

    -- Fixed starter weapon. Never trust a client weapon selection; grant once on
    -- successful character creation, independently of payload.kit.melee.
    out[#out + 1] = { item = 'hunting_knife', amount = 1 }

    local seen, count = {}, 0
    for _, id in ipairs(type(kit.goodies) == 'table' and kit.goodies or {}) do
        local g
        for _, c in ipairs(K.goodies) do if c.id == id then g = c end end
        if not g or seen[id] then return nil, Lp(src, 'mc.bad_kit') end
        seen[id] = true
        count = count + 1
        if count > (K.maxGoodies or 2) then return nil, Lp(src, 'mc.bad_kit') end
        out[#out + 1] = { item = g.item, amount = g.amount or 1 }
    end
    return out
end

-- Server checks the chosen rule identity and active texture against the current rules.
-- FiveM's collection-to-global native is client only; validation also uses a
-- per-player catalog generated from the current preview ped; current rule bans
-- are re-checked on every save (global indices are client-side native data).
local catalogBySource = {}
local function validRuleKey(key, gender, def)
    if type(key) ~= 'string' or #key > 280 then return false end
    local kind = def.c ~= nil and 'component' or 'prop'
    local slot = tostring(def.c or def.p)
    local prefix = gender .. '|' .. kind .. '|' .. slot .. '|'
    return key:sub(1, #prefix) == prefix and key:match('^.-|.-|.-|.-|%d+$') ~= nil
end

-- Catalog is freshly generated by the client from actual collections. Registration
-- validates *shape* and prevents value swapping after the character changes sex.
BSB.RegisterCallback('multichar:registerCatalog', function(src, gender, list)
    gender = gender == 'female' and 'female' or 'male'
    if type(list) ~= 'table' then return { ok = false } end
    local allowed = {}
    local total = 0
    for cat, entries in pairs(list) do
        local def = Multichar.Clothes[cat]
        if not def or type(def) ~= 'table' or (not def.c and not def.p) or type(entries) ~= 'table' then return { ok = false } end
        local sub = {}
        for _, entry in ipairs(entries) do
            total = total + 1
            if total > 12000 then return { ok = false } end
            local d = math.floor(tonumber(entry.d) or -999)
            local key = entry.k
            if d >= 0 and d <= 15000 and validRuleKey(key, gender, def) and type(entry.ts)=='table' then
                local ts = {}
                for _, v in ipairs(entry.ts) do
                    local n = tonumber(v)
                    if n and n >= 0 and n <= 255 then ts[math.floor(n)] = true end
                end
                sub[d] = { k = key, ts = ts }
            elseif def.p ~= nil and d == -1 then sub[-1] = { k = '', ts = { [0] = true } }
            end
        end
        allowed[cat] = sub
    end
    catalogBySource[src] = catalogBySource[src] or {}
    catalogBySource[src][gender] = allowed
    return { ok = true }
end)
AddEventHandler('playerDropped', function() catalogBySource[source] = nil end)

local function validateOutfit(src, o, gender)
    local C = Multichar.Clothes
    if type(o) ~= 'table' then return nil, Lp(src, 'mc.bad_outfit') end
    local sex = gender == 'female' and 'female' or 'male'
    local saved = catalogBySource[src] and catalogBySource[src][sex]
    if type(saved) ~= 'table' then return nil, Lp(src, 'mc.bad_outfit') end
    local rules = currentClothingRules()
    local comps, props = {}, {}
    for id, def in pairs(C) do
        if type(def) == 'table' and (def.c ~= nil or def.p ~= nil) then
            local pick = o[id]
            if type(pick) ~= 'table' then return nil, Lp(src, 'mc.bad_outfit') end
            local d, tex = tonumber(pick.d), tonumber(pick.t)
            if not d or d ~= math.floor(d) or not tex or tex ~= math.floor(tex) then return nil, Lp(src, 'mc.bad_outfit') end
            local entry = saved[id] and saved[id][d]
            if not entry or tex < 0 or tex > 255 or not entry.ts[tex] then return nil, Lp(src, 'mc.bad_outfit') end
            if d >= 0 then
                if not validRuleKey(pick.k, sex, def) or entry.k ~= pick.k then return nil, Lp(src, 'mc.bad_outfit') end
                if rules.disabled[entry.k] or rules.disabledTextures[entry.k .. '|texture|' .. tostring(tex)] then
                    return nil, Lp(src, 'mc.bad_outfit')
                end
                -- exclude gulag collection names even if a manipulated client sends a catalog
                local lowered = entry.k:lower()
                for _, fragment in ipairs(C.excludedCollections or {}) do
                    if lowered:find(fragment:lower(), 1, true) then return nil, Lp(src, 'mc.bad_outfit') end
                end
            end
            if def.c ~= nil then
                comps[tostring(def.c)] = { drawable = d, texture = tex, palette = 2 }
            else
                props[tostring(def.p)] = { drawable = d, texture = d < 0 and -1 or tex }
            end
        end
    end
    -- Bag/backpack slot cannot be selected or saved from character creation.
    comps['5'] = { drawable = 0, texture = 0, palette = 2 }
    return { components = comps, props = props }
end

BSB.RegisterCallback('multichar:saveDefaultOutfit', function(src, gender, choices)
    if not canSetDefault(src) then return { ok = false, error = 'Keine Adminberechtigung (alphaz.outfit.admin).' } end
    gender = gender == 'female' and 'female' or 'male'
    local validated, err = validateOutfit(src, choices, gender)
    if not validated then return { ok = false, error = err or 'Ungültiges Outfit.' } end
    local defaults = readDefaultOutfits()
    defaults[gender] = choices
    local ok = SaveResourceFile(GetCurrentResourceName(), 'data/default_outfits.json', json.encode(defaults), -1)
    if not ok then return { ok = false, error = 'Outfit konnte nicht gespeichert werden.' } end
    print(('[Alpha-Z] Standard-Outfit (%s) durch Spieler %s gespeichert.'):format(gender, src))
    return { ok = true }
end)

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

    -- Guaranteed starter supplies for every newly created character.
    -- These are granted in addition to any optional creator extras selected above.
    -- If the player also selects food/water/bandages as extras, the amounts stack.
    loadout[#loadout + 1] = { item = 'canned_food',  amount = 2 }
    loadout[#loadout + 1] = { item = 'water_bottle', amount = 2 }
    loadout[#loadout + 1] = { item = 'bandage',      amount = 1 }

    local outfit
    if clothingOn() then
        local oErr
        outfit, oErr = validateOutfit(src, payload.outfit, gender)
        if not outfit then return { ok = false, error = oErr } end
    end

    -- Alpha-Z: ein einziger Erstspawn-Bereich, unabhängig von der Fraktion.
-- Radius per sqrt(uniform) -> gleichmäßige Verteilung über die Kreisfläche.
-- Die einmalige Position wird beim Erstellen gespeichert und von bs_core
-- nur beim ersten Spawn benutzt; alte Charaktere bleiben unverändert.
local function newCharacterSpawn()
    local cfg = Multichar.FirstSpawn
    local r = math.sqrt(math.random()) * math.max(0.0, math.min(10.0, tonumber(cfg.radius) or 10.0))
    local a = math.random() * math.pi * 2.0
    return {
        x = cfg.x + math.cos(a) * r,
        y = cfg.y + math.sin(a) * r,
        z = cfg.z,
        h = cfg.h,
    }
end

-- Every newly created character starts as a Civilian.
    -- The canonical faction id in bs_factions is "civilians" (plural).
    -- Ignore any faction id supplied by the client so character creation cannot override it.
    local fac = creatorFactions()
    local chosen
    for _, f in ipairs(fac.factions or {}) do
        if f.id == 'civilians' or f.id == 'civilian' or f.id == 'zivilisten' then
            chosen = f
            break
        end
    end

    -- Guaranteed starter supplies are already appended to loadout above.

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
        spawn = newCharacterSpawn(),
        pendingFaction = chosen and chosen.id or 'civilians',
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