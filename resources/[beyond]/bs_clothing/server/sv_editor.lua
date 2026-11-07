local RESOURCE = GetCurrentResourceName()
local FILE = 'data/clothing_rules.json'
local rules = { disabled = {}, disabledTextures = {}, favorite = {}, torsoMappings = {} }

local function loadRules()
    local raw = LoadResourceFile(RESOURCE, FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data)=='table' then
            rules.disabled = type(data.disabled)=='table' and data.disabled or {}
            rules.disabledTextures = type(data.disabledTextures)=='table' and data.disabledTextures or {}
            rules.favorite = type(data.favorite)=='table' and data.favorite or {}
            rules.torsoMappings = type(data.torsoMappings)=='table' and data.torsoMappings or {}
        end
    end
end
local function saveRules()
    SaveResourceFile(RESOURCE, FILE, json.encode(rules), -1)
end
local function broadcast()
    TriggerClientEvent('bs_clothing:rules', -1, rules.disabled, rules.disabledTextures, rules.favorite, rules.torsoMappings)
end
local function canEdit(src)
    local e = Config.Clothing.editor
    if not e or not e.enabled then return false end
    if not e.restricted then return true end
    return IsPlayerAceAllowed(src, e.ace or 'bs.clothing.admin')
end

loadRules()

RegisterNetEvent('bs_clothing:requestRules', function()
    TriggerClientEvent('bs_clothing:rules', source, rules.disabled, rules.disabledTextures, rules.favorite, rules.torsoMappings)
end)
RegisterNetEvent('bs_clothing:requestEditor', function()
    if canEdit(source) then TriggerClientEvent('bs_clothing:openEditor', source)
    else TriggerClientEvent('bs_clothing:editorDenied', source) end
end)
RegisterNetEvent('bs_clothing:setRule', function(key, rule, value)
    local src=source
    if not canEdit(src) or type(key)~='string' or #key>280 then return end
    local bucket
    if rule=='disabled' then bucket=rules.disabled
    elseif rule=='disabledTexture' then bucket=rules.disabledTextures
    elseif rule=='favorite' then bucket=rules.favorite
    else return end
    bucket[key] = value == true or nil
    saveRules(); broadcast()
end)


RegisterNetEvent('bs_clothing:setTorsoRule', function(key, drawable, texture)
    local src=source
    if not canEdit(src) or type(key)~='string' or #key>280 then return end
    drawable=math.floor(tonumber(drawable) or -1)
    texture=math.floor(tonumber(texture) or -1)
    if drawable < 0 or drawable > 1000 or texture < 0 or texture > 250 then return end
    rules.torsoMappings[key] = { drawable=drawable, texture=texture }
    saveRules(); broadcast()
end)

RegisterNetEvent('bs_clothing:clearTorsoRule', function(key)
    local src=source
    if not canEdit(src) or type(key)~='string' or #key>280 then return end
    rules.torsoMappings[key] = nil
    saveRules(); broadcast()
end)


--------------------------------------------------------------------------------
-- Persistent outfit: Alpha-Z wardrobe is authoritative for freely available
-- GTA/DLC/custom clothing. Do NOT route this through bs_core's normal
-- bs:player:updateOutfit handler, because that handler intentionally rejects
-- unpurchased bs_traders wardrobe pieces.
--------------------------------------------------------------------------------
local function sanitizeOutfit(outfit)
    if type(outfit) ~= 'table' then return nil end
    local clean = { components = {}, props = {} }

    for id, v in pairs(outfit.components or {}) do
        local n = tonumber(id)
        -- Face/hair belong to character appearance, component 5 is parachute.
        if n and n >= 0 and n <= 11 and n ~= 0 and n ~= 2 and n ~= 5 and type(v) == 'table' then
            clean.components[tostring(math.floor(n))] = {
                drawable = math.max(0, math.min(2000, math.floor(tonumber(v.drawable) or 0))),
                texture  = math.max(0, math.min(500, math.floor(tonumber(v.texture) or 0))),
                palette  = math.max(0, math.min(3, math.floor(tonumber(v.palette) or 2))),
            }
        end
    end

    for id, v in pairs(outfit.props or {}) do
        local n = tonumber(id)
        if n and n >= 0 and n <= 7 and type(v) == 'table' then
            local d = math.floor(tonumber(v.drawable) or -1)
            clean.props[tostring(math.floor(n))] = {
                drawable = math.max(-1, math.min(2000, d)),
                texture  = d < 0 and -1 or math.max(0, math.min(500, math.floor(tonumber(v.texture) or 0))),
            }
        end
    end
    return clean
end

RegisterNetEvent('bs_clothing:saveOutfit', function(outfit, reason)
    local src = source
    if GetResourceState('bs_core') ~= 'started' then
        TriggerClientEvent('bs_clothing:saveResult', src, false, 'bs_core läuft nicht – Outfit nicht gespeichert.')
        return
    end

    local clean = sanitizeOutfit(outfit)
    if not clean then
        TriggerClientEvent('bs_clothing:saveResult', src, false, 'Ungültiges Outfit – nicht gespeichert.')
        return
    end

    local okSummary, summary = pcall(function()
        return exports.bs_core:GetPlayerSummary(src)
    end)
    local charId = okSummary and type(summary) == 'table' and tonumber(summary.charId) or nil
    if not charId then
        TriggerClientEvent('bs_clothing:saveResult', src, false, 'Kein geladener Charakter – Outfit nicht gespeichert.')
        return
    end

    local okSave, saved = pcall(function()
        return exports.bs_core:SetCharacterOutfit(charId, clean)
    end)
    if not okSave or saved ~= true then
        print(('^1[bs_clothing]^7 Outfit-Save fehlgeschlagen src=%s char=%s reason=%s'):format(src, tostring(charId), tostring(reason)))
        TriggerClientEvent('bs_clothing:saveResult', src, false, 'Outfit konnte nicht in der Charakter-Datenbank gespeichert werden.')
        return
    end

    print(('^2[bs_clothing]^7 Outfit gespeichert src=%s char=%s reason=%s'):format(src, charId, tostring(reason or 'wardrobe')))
    TriggerClientEvent('bs_clothing:saveResult', src, true, 'Outfit gespeichert.')
end)
