-- BS19 Prop Studio: server-authoritative definitions; no model scale/collision/bounds modification.
local file = 'data/prop_studio.json'
local overrides = {}
-- Pristine built-in definitions, captured before studio overrides are applied.
local originalDefinitions = {}
local categoryFile = 'data/prop_categories.json'
local builtInCategories = {structure=true, openings=true, defense=true, utility=true, claim=true}
local categories = {structure='Struktur', openings='Öffnungen', defense='Verteidigung', utility='Utility', claim='Claim'}
local function saveCategories() return SaveResourceFile(GetCurrentResourceName(), categoryFile, json.encode(categories), -1) end
local function loadCategories()
    local raw = LoadResourceFile(GetCurrentResourceName(), categoryFile)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
        for k,v in pairs(data) do
            if type(k)=='string' and k:match('^[a-z][a-z0-9_]*$') and type(v)=='string' and #v<=40 then categories[k]=v end
        end
    end
end
loadCategories()
local function staff(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
BSB.RegisterCallback('build:studio:categories', function(src)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    return {ok=true,categories=categories}
end)
BSB.RegisterCallback('build:studio:categoryCreate', function(src, payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local label = type(payload)=='table' and tostring(payload.label or '') or ''
    label=label:gsub('^%s+',''):gsub('%s+$','')
    if #label<2 or #label>40 then return {ok=false,error='Kategoriename muss 2–40 Zeichen haben'} end
    local id=label:lower():gsub('ä','ae'):gsub('ö','oe'):gsub('ü','ue'):gsub('ß','ss'):gsub('[^a-z0-9]+','_'):gsub('^_+',''):gsub('_+$','')
    if not id:match('^[a-z][a-z0-9_]*$') or #id>40 then return {ok=false,error='Ungültiger Kategoriename'} end
    if categories[id] then return {ok=false,error='Kategorie existiert bereits'} end
    categories[id]=label
    if not saveCategories() then categories[id]=nil;return {ok=false,error='Speichern fehlgeschlagen'} end
    return {ok=true,id=id,categories=categories}
end)

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if not raw or raw == '' then return end
    local ok, obj = pcall(json.decode, raw)
    if ok and type(obj) == 'table' then overrides = obj end
end
local function copy(t)
    local o = {}; for k,v in pairs(t or {}) do o[k] = type(v) == 'table' and copy(v) or v end; return o
end
-- Registered pieces may arrive after this file has loaded. Preserve their true
-- unmodified definition before applying any studio override.
function Building.RememberStudioOriginal(id, definition)
    if not originalDefinitions[id] and type(definition) == 'table' then
        originalDefinitions[id] = copy(definition)
    end
end
local function apply(id)
    local override = overrides[id]; if not override then return end
    local d = Building.Pieces[id] or {}
    for k,v in pairs(override) do if k ~= 'id' and k ~= 'new' then d[k] = v end end
    Building.Pieces[id] = d
    -- Reconcile placements loaded before a custom definition became available.
    if Store and Store.waiting and Store.waiting[id] and Store.add then
        for _, placed in ipairs(Store.waiting[id]) do Store.add(placed) end
        Store.waiting[id] = nil
    end
    TriggerClientEvent('bs:building:def', -1, id, d)
end
-- Called when another resource re-registers a piece, so its default values
-- cannot silently overwrite a saved studio adjustment.
function Building.ApplyStudioOverride(id)
    if overrides[id] then apply(id) end
end
local function sync()
    for id in pairs(overrides) do apply(id) end
end
load()
-- Config pieces are available at startup. Take the snapshot BEFORE sync().
for id, definition in pairs(Building.Pieces) do
    if not (overrides[id] and overrides[id].new == true) then
        Building.RememberStudioOriginal(id, definition)
    end
end
-- Definitions must exist BEFORE sv_store's delayed database restoration.
-- Waiting 5.5 seconds made custom pieces appear missing at server restart.
sync()
AddEventHandler('onResourceStart', function(res)
    if res == 'bs_crafting' then SetTimeout(1500, sync) end
end)
local function validNumber(n, limit)
    n = tonumber(n)
    return n and n == n and math.abs(n) <= limit and n or nil
end
local function validVec(v, limit)
    if type(v) ~= 'table' then return nil end
    local t = {}
    for i=1,3 do t[i] = validNumber(v[i], limit); if not t[i] then return nil end end
    return t
end
-- Status is derived from the persisted override, not from the test flag.
-- For legacy custom pieces without a recorded baseline, zero transform is the
-- same baseline used by the existing reset callback.
local function studioChanged(override)
    if type(override) ~= 'table' then return false end
    if override.new ~= true then return true end
    local initial = override.initialStudio or {offset={0,0,0},rotation={0,0,0}}
    local current = override.studio or {}
    for _, key in ipairs({'offset','rotation'}) do
        local a, b = current[key] or {0,0,0}, initial[key] or {0,0,0}
        for i=1,3 do
            if math.abs((tonumber(a[i]) or 0)-(tonumber(b[i]) or 0)) > 0.0001 then return true end
        end
    end
    return false
end
BSB.RegisterCallback('build:studio:list', function(src)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local out = {}
    for id,d in pairs(Building.Pieces) do
        out[#out+1] = {id=id, label=d.label or id, cat=d.cat or 'utility', models=d.models or {}, size=d.size or {1,1,1},
            pitch=d.pitch or 0, studio=d.studio or {}, cost=d.cost or {}, health=d.health or 400, support=d.support or 'any',
            custom=overrides[id] ~= nil, modified=studioChanged(overrides[id]), isNew=overrides[id] and overrides[id].new == true or false, disabled=overrides[id] and overrides[id].disabled == true or false, tested=overrides[id] and overrides[id].tested == true or false}
    end
    table.sort(out,function(x,y) return x.id < y.id end)
    return {ok=true,pieces=out}
end)
BSB.RegisterCallback('build:studio:save', function(src, payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    if type(payload) ~= 'table' then return {ok=false,error='Ungültige Daten'} end
    local id = tostring(payload.id or '')
    if not id:match('^[a-z][a-z0-9_]*$') or #id > 48 then return {ok=false,error='Ungültige Prop-ID'} end
    local original = Building.Pieces[id]
    if not original and not payload.create then return {ok=false,error='Prop existiert nicht'} end
    if original and payload.create then return {ok=false,error='ID bereits vorhanden'} end
    local model = tostring(payload.model or '')
    if not model:match('^[%w_]+$') or #model > 90 then return {ok=false,error='Ungültiger Modellname'} end
    local offset = validVec(payload.offset or {0,0,0}, 10)
    local rotation = validVec(payload.rotation or {0,0,0}, 360)
    local size = validVec(payload.size or (original and original.size) or {1,1,1}, 30)
    if not offset or not rotation or not size or math.min(table.unpack(size)) <= 0 then return {ok=false,error='Ungültige Werte'} end
    local label = tostring(payload.label or id):sub(1,80)
    local cat = tostring(payload.cat or (original and original.cat) or 'utility')
    if not categories[cat] then return {ok=false,error='Ungültige Kategorie'} end
    local base = overrides[id] or {}
    -- preserve gameplay attributes of existing pieces; only studio fields and model may change.
    base.models = {model}; base.studio = {offset=offset, rotation=rotation}
    base.size = size; base.cat = cat
    if payload.tested ~= nil then base.tested = payload.tested == true end
    if not original then
        base.new = true; base.label=label; base.health=400; base.cost={}; base.support='any'
        -- Capture the initial studio transform for future custom-prop resets.
        base.initialStudio = {offset=copy(offset), rotation=copy(rotation)}
    elseif original.label then base.label = label end
    local previous = overrides[id]
    overrides[id] = base
    local saved = SaveResourceFile(GetCurrentResourceName(), file, json.encode(overrides), -1)
    if not saved then overrides[id]=previous; return {ok=false,error='Speichern fehlgeschlagen'} end
    apply(id)
    return {ok=true}
end)
BSB.RegisterCallback('build:studio:reset', function(src, id)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    id = tostring(id or '')
    if not overrides[id] then return {ok=false,error='Kein Override vorhanden'} end
    -- User-created pieces have no built-in definition to fall back to.
    -- Reset only their studio transform, preserving model, category and placements.
    if overrides[id].new == true then
        local previous = copy(overrides[id])
        local initial = overrides[id].initialStudio or {offset={0,0,0}, rotation={0,0,0}}
        overrides[id].studio = {offset=copy(initial.offset or {0,0,0}), rotation=copy(initial.rotation or {0,0,0})}
        if not SaveResourceFile(GetCurrentResourceName(), file, json.encode(overrides), -1) then
            overrides[id] = previous
            return {ok=false,error='Speichern fehlgeschlagen'}
        end
        apply(id)
        return {ok=true,restart=false,legacyBaseline=previous.initialStudio == nil}
    end
    -- Restore the original definition immediately, without restarting the resource.
    local original = originalDefinitions[id]
    if not original then
        return {ok=false,error='Originaldefinition nicht verfügbar. Bitte zuerst die registrierende Resource prüfen.'}
    end
    local previous = overrides[id]
    overrides[id] = nil
    if not SaveResourceFile(GetCurrentResourceName(), file, json.encode(overrides), -1) then
        overrides[id] = previous
        return {ok=false,error='Speichern fehlgeschlagen'}
    end
    Building.Pieces[id] = copy(original)
    TriggerClientEvent('bs:building:def', -1, id, Building.Pieces[id])
    return {ok=true,restart=false}

end)

-- v6: persistent catalogue operations. No changes to placed world entities.
local function persistOverrides() return SaveResourceFile(GetCurrentResourceName(), file, json.encode(overrides), -1) end
BSB.RegisterCallback('build:studio:remove', function(src, payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id = type(payload)=='table' and tostring(payload.id or '') or ''
    local def = Building.Pieces[id]
    if not def then return {ok=false,error='Prop nicht gefunden'} end
    local previous = copy(overrides[id] or {})
    -- Tombstone even for custom definitions: keep historical placed entities resolvable.
    -- A true hard-delete requires migration of existing world placements.
    local updated=copy(previous); updated.disabled=true; overrides[id]=updated
    if not persistOverrides() then overrides[id]=previous;return {ok=false,error='Speichern fehlgeschlagen'} end
    apply(id)
    return {ok=true,disabled=true}
end)
BSB.RegisterCallback('build:studio:restore', function(src, payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id=type(payload)=='table' and tostring(payload.id or '') or ''
    if not Building.Pieces[id] or not overrides[id] or not overrides[id].disabled then return {ok=false,error='Nicht deaktiviert'} end
    local previous=copy(overrides[id]);overrides[id].disabled=nil
    if not persistOverrides() then overrides[id]=previous;return {ok=false,error='Speichern fehlgeschlagen'} end
    apply(id);return {ok=true}
end)
BSB.RegisterCallback('build:studio:categoryRename',function(src,payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id=type(payload)=='table' and tostring(payload.id or '') or ''
    local label=type(payload)=='table' and tostring(payload.label or ''):gsub('^%s+',''):gsub('%s+$','') or ''
    if builtInCategories[id] or not categories[id] then return {ok=false,error='Standardkategorie oder unbekannte Kategorie'} end
    if #label<2 or #label>40 then return {ok=false,error='Name muss 2–40 Zeichen haben'} end
    local old=categories[id];categories[id]=label
    if not saveCategories() then categories[id]=old;return {ok=false,error='Speichern fehlgeschlagen'} end
    return {ok=true,categories=categories}
end)
BSB.RegisterCallback('build:studio:categoryDelete',function(src,payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id=type(payload)=='table' and tostring(payload.id or '') or ''
    local target=type(payload)=='table' and tostring(payload.target or '') or ''
    if builtInCategories[id] or not categories[id] then return {ok=false,error='Standardkategorie kann nicht gelöscht werden'} end
    if not categories[target] or target==id then return {ok=false,error='Bitte gültige Zielkategorie wählen'} end
    local oldOverrides=copy(overrides); local oldCategories=copy(categories)
    for propId,def in pairs(Building.Pieces) do
        if def.cat==id then
            overrides[propId]=overrides[propId] or {}
            overrides[propId].cat=target
        end
    end
    categories[id]=nil
    if not persistOverrides() then overrides=oldOverrides;categories=oldCategories;return {ok=false,error='Prop-Zuordnungen konnten nicht gespeichert werden'} end
    if not saveCategories() then overrides=oldOverrides;categories=oldCategories;persistOverrides();return {ok=false,error='Kategorien konnten nicht gespeichert werden'} end
    sync();return {ok=true,categories=categories}
end)
