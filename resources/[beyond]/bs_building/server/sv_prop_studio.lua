-- BS19 Prop Studio: server-authoritative definitions; no model scale/collision/bounds modification.
local file = 'data/prop_studio.json'
local overrides = {}
-- Pristine built-in definitions, captured before studio overrides are applied.
local originalDefinitions = {}
local categoryFile = 'data/prop_categories.json'
local categories = {structure='Struktur', openings='Öffnungen', defense='Verteidigung', utility='Utility', claim='Claim'}
-- v12 category file format: an explicit list, so removing a built-in category
-- survives resource restarts. Legacy flat dictionaries are still supported.
local function saveCategories()
    return SaveResourceFile(GetCurrentResourceName(), categoryFile, json.encode({version=2,entries=categories}), -1)
end
local function loadCategories()
    local raw = LoadResourceFile(GetCurrentResourceName(), categoryFile)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return end
    local incoming = data.version == 2 and data.entries or data
    if type(incoming) ~= 'table' then return end
    local out = {}
    for k,v in pairs(incoming) do
        if type(k)=='string' and k:match('^[a-z][a-z0-9_]*$')
          and type(v)=='string' and #v>=2 and #v<=40 then out[k]=v end
    end
    if data.version == 2 and not next(out) then return end
    if data.version == 2 then categories=out
    else for k,v in pairs(out) do categories[k]=v end end
end
loadCategories()
-- ALPHA-Z V19: Funktionale Legacy-Kategorien wieder einblenden, ohne die
-- existierende F10-Konfiguration oder benutzerdefinierte Kategorien zu
-- ueberschreiben. Einmalig nur fehlende Eintraege hinzufuegen.
do
    local required = {utility='Utility', defense='Verteidigung', openings='Öffnungen'}
    local restored = false
    for id, label in pairs(required) do
        if categories[id] == nil then categories[id] = label; restored = true end
    end
    if restored and not saveCategories() then
        print('[bs_building] WARN: Funktionale Kategorien nur im Speicher wiederhergestellt.')
    end
end
-- F2 must receive these dynamic categories, not the five hard-coded entries
-- from config_building.lua. Deleted categories must disappear there too.
function Building.StudioCategoryList()
    local list = {}
    for id, label in pairs(categories) do list[#list + 1] = {id=id,label=label} end
    table.sort(list,function(a,b) return a.label < b.label end)
    return list
end
-- Use the same staff authority as the actual F10 menu. Its openAces can
-- also contain command.zombiemenu, so checking only bs.admin causes F10
-- to open while every Prop Studio write fails with "Keine Berechtigung".
local function staff(src)
    if GetResourceState('bs_admin') == 'started' then
        local ok, allowed = pcall(function() return exports['bs_admin']:IsAdmin(src) end)
        if ok then return allowed == true end
    end
    return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin')
end
-- Read the real inventory configuration at request time, not a second hard-coded list.
BSB.RegisterCallback('build:studio:materials', function(src)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    if GetResourceState('bs_inventory') ~= 'started' then
        return {ok=false,error='Inventar ist nicht gestartet'}
    end
    local ok, definitions = pcall(function()
        return exports['bs_inventory']:GetItems()
    end)
    if not ok or type(definitions) ~= 'table' then
        return {ok=false,error='Inventar-Items konnten nicht geladen werden'}
    end
    local items = {}
    for id, def in pairs(definitions) do
        if type(id) == 'string' and type(def) == 'table' then
            items[#items+1] = {id=id,label=tostring(def.label or id),category=tostring(def.category or 'item')}
        end
    end
    table.sort(items, function(a,b)
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.id < b.id or al < bl
    end)
    return {ok=true,items=items}
end)
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
    -- V15: Legacy categories are archived, NOT silently moved to Claim or Kenney.
    -- Their piece definitions (and all existing world objects) remain loadable.
    -- F10 can explicitly reveal old props if an admin needs to inspect one.
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
-- Cost definitions are shared by F10 catalogue, F2 preview and server-side placement.
local function validateCost(value)
    if type(value) ~= 'table' then return nil, 'Materialliste fehlt' end
    local out, seen = {}, {}
    if #value > 24 then return nil, 'Maximal 24 Materialien pro Prop' end
    for _, entry in ipairs(value) do
        if type(entry) ~= 'table' then return nil, 'Ungültiger Materialeintrag' end
        local item = tostring(entry.item or '')
        local amount = tonumber(entry.amount)
        if not item:match('^[a-z][a-z0-9_]*$') or #item > 80 or seen[item] then
            return nil, 'Ungültiges oder doppeltes Material: '..item
        end
        if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 100000 then
            return nil, 'Materialmenge muss zwischen 1 und 100000 liegen'
        end
        -- ItemLabel is the inventory's canonical lookup; unknown IDs return their own ID.
        local ok, def = pcall(function() return exports.bs_inventory:GetItem(item) end)
        if not ok or type(def) ~= 'table' then
            return nil, 'Unbekanntes Inventar-Item: '..item
        end
        seen[item] = true
        out[#out+1] = {item=item, amount=amount}
    end
    return out
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
-- Only actual 3D transform changes mark a prop as ANGEPASST.
-- Catalogue visibility and other administrative overrides do not change this badge.
local function studioChanged(override, id)
    if type(override) ~= 'table' then return false end
    local initial
    if override.new == true then
        initial = override.initialStudio or {offset={0,0,0},rotation={0,0,0}}
    else
        local original = originalDefinitions[id]
        initial = (original and original.studio) or {offset={0,0,0},rotation={0,0,0}}
    end
    local current = override.studio or initial
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
        -- Permanently deleted catalogue entries must not reappear in F10.
        -- Keep their internal definition only when required by existing world objects.
        if not (overrides[id] and overrides[id].deleted == true) then
        out[#out+1] = {id=id, label=d.label or id, cat=d.cat or 'utility', models=d.models or {}, size=d.size or {1,1,1},
            pitch=d.pitch or 0, studio=d.studio or {}, cost=d.cost or {}, health=d.health or 400, support=d.support or 'any',
            custom=overrides[id] ~= nil, modified=(studioChanged(overrides[id], id) or (overrides[id] and overrides[id].cat ~= nil and (not originalDefinitions[id] or overrides[id].cat ~= originalDefinitions[id].cat)) == true), isNew=overrides[id] and overrides[id].new == true or false, disabled=overrides[id] and overrides[id].disabled == true or false, tested=overrides[id] and overrides[id].tested == true or false}
        end
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
    if overrides[id] and overrides[id].deleted == true then
        return {ok=false,error='Diese Prop-ID wurde dauerhaft aus dem Baukatalog entfernt'}
    end
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
    local cost
    if payload.cost ~= nil then
        local err
        cost, err = validateCost(payload.cost)
        if not cost then return {ok=false,error=err} end
    elseif not original then
        return {ok=false,error='Bitte Baukosten festlegen (Material und Menge)'}
    end
    if not original and (not cost or #cost == 0) then
        return {ok=false,error='Neue Props benötigen mindestens ein Baumaterial'}
    end
    local base = copy(overrides[id] or {})
    if cost then base.cost = cost end
    -- preserve gameplay attributes of existing pieces; only studio fields and model may change.
    base.models = {model}; base.studio = {offset=offset, rotation=rotation}
    base.size = size; base.cat = cat
    if payload.tested ~= nil then base.tested = payload.tested == true end
    if not original then
        base.new = true; base.label=label; base.health=400; base.support='any'
        -- Capture the initial studio transform for future custom-prop resets.
        base.initialStudio = {offset=copy(offset), rotation=copy(rotation)}
    else base.label = label end
    -- Allow catalogue ID renames only for custom definitions. Core IDs such as
    -- foundation/wall/door carry gameplay and snapping semantics and must be stable.
    local newId = tostring(payload.newId or id)
    if not newId:match('^[a-z][a-z0-9_]*$') or #newId > 48 then
        return {ok=false,error='Ungültige neue Prop-ID (a-z, 0-9, _)'}
    end
    local renaming = newId ~= id
    if renaming then
        if not (overrides[id] and overrides[id].new == true) then
            return {ok=false,error='System-Prop-IDs sind geschützt. Eigene Prop-IDs kannst du ändern.'}
        end
        if Building.Pieces[newId] or overrides[newId] or originalDefinitions[newId] then
            return {ok=false,error='Die neue Prop-ID ist bereits vergeben'}
        end
        if not Store or not Store.ready then
            return {ok=false,error='Bau-Datenbank lädt noch. Bitte erneut versuchen.'}
        end
        base.new = true
        base.label = label
        base.initialStudio = base.initialStudio or {offset=copy(offset),rotation=copy(rotation)}
    end
    local previous = overrides[id]
    if renaming then
        local tombstone = copy(previous or {})
        tombstone.deleted = true; tombstone.disabled = true
        overrides[id] = tombstone
        overrides[newId] = base
    else
        overrides[id] = base
    end
    local saved = SaveResourceFile(GetCurrentResourceName(), file, json.encode(overrides), -1)
    if not saved then
        overrides[id] = previous
        if renaming then overrides[newId]=nil end
        return {ok=false,error='Speichern fehlgeschlagen'}
    end
    if renaming then
        Building.Pieces[newId] = copy(original)
        apply(id) -- old built-ins/custom IDs are hidden from F2, existing objects survive
        apply(newId)
    else
        apply(id)
    end
    return {ok=true,id=newId,renamed=renaming,definition=Building.Pieces[newId]}
end)
BSB.RegisterCallback('build:studio:reset', function(src, id)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    id = tostring(id or '')
    if overrides[id] and overrides[id].deleted == true then
        return {ok=false,error='Ein dauerhaft gelöschter Eintrag kann nicht zurückgesetzt werden'}
    end
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
    if not def or (overrides[id] and overrides[id].deleted == true) then return {ok=false,error='Prop nicht gefunden'} end
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
    if not Building.Pieces[id] or not overrides[id] or not overrides[id].disabled or overrides[id].deleted then
        return {ok=false,error='Kein wiederherstellbarer Eintrag'}
    end
    local previous=copy(overrides[id]);overrides[id].disabled=nil
    if not persistOverrides() then overrides[id]=previous;return {ok=false,error='Speichern fehlgeschlagen'} end
    apply(id);return {ok=true}
end)
-- True catalogue delete, separate from the reversible "remove"/"restore" actions.
-- Built-in and already-placed pieces retain only an internal tombstone so saved
-- world objects remain loadable. New, unused F10 props are removed entirely.
BSB.RegisterCallback('build:studio:deletePermanent', function(src, payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id = type(payload)=='table' and tostring(payload.id or '') or ''
    if not id:match('^[a-z][a-z0-9_]*$') or #id > 48 then
        return {ok=false,error='Ungültige Prop-ID'}
    end
    local d = Building.Pieces[id]
    if not d or (overrides[id] and overrides[id].deleted == true) then
        return {ok=false,error='Prop wurde bereits gelöscht oder existiert nicht'}
    end
    -- Do not hard-delete a saved definition before the database restoration is complete.
    if not Store or not Store.ready then
        return {ok=false,error='Bau-Datenbank lädt noch. Bitte erneut versuchen.'}
    end

    local inWorld = 0
    for _, placed in pairs(Store.pieces or {}) do
        if placed.piece == id then inWorld = inWorld + 1 end
    end
    for _, placed in ipairs((Store.waiting and Store.waiting[id]) or {}) do
        if placed.piece == id then inWorld = inWorld + 1 end
    end

    local previous = overrides[id]
    local createdInF10 = previous and previous.new == true and originalDefinitions[id] == nil
    local hardDelete = createdInF10 and inWorld == 0

    if hardDelete then
        -- No config registration and no DB references: really remove this definition.
        overrides[id] = nil
    else
        -- Core/config definitions will be re-registered on restart. Persist an
        -- irreversible catalogue exclusion without destroying old placed objects.
        local tombstone = copy(previous or {})
        tombstone.deleted = true
        tombstone.disabled = true
        overrides[id] = tombstone
    end

    if not persistOverrides() then
        overrides[id] = previous
        return {ok=false,error='Löschung konnte nicht dauerhaft gespeichert werden'}
    end

    if hardDelete then
        Building.Pieces[id] = nil
        TriggerClientEvent('bs:building:forgetDefinition', -1, id)
    else
        apply(id) -- immediately hides it from F2; preserves historical placements
    end
    if Store.log then
        Store.log(src, 'admin', ('deleted catalogue prop %s (placed=%d, hard=%s)'):format(id,inWorld,tostring(hardDelete)))
    end
    return {ok=true,deleted=true,hardDeleted=hardDelete,placedCount=inWorld}
end)

-- ALPHA-Z: Props ohne 3D-Editor/Material-Dialog in andere Kategorien schieben.
-- Alle Aenderungen in einem persistierten Write, erst danach synchronisieren.
BSB.RegisterCallback('build:studio:categoryMove',function(src,payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    if type(payload) ~= 'table' then return {ok=false,error='Ungueltige Anfrage'} end
    local target=tostring(payload.target or '')
    if not categories[target] then return {ok=false,error='Bitte gueltige Zielkategorie waehlen'} end
    local ids=payload.ids
    if type(ids)~='table' or #ids<1 or #ids>100 then
        return {ok=false,error='Bitte 1 bis 100 Props auswaehlen'}
    end
    local seen,updates={},{}
    for _,value in ipairs(ids) do
        local id=tostring(value or '')
        if not id:match('^[a-z][a-z0-9_]*$') or #id>48 or seen[id] then
            return {ok=false,error='Ungueltige oder doppelte Prop-ID: '..id}
        end
        seen[id]=true
        if not Building.Pieces[id] or (overrides[id] and overrides[id].deleted==true) then
            return {ok=false,error='Prop existiert nicht im Katalog: '..id}
        end
        if id=='claim' then return {ok=false,error='Claim ist ein geschuetztes System-Prop'} end
        if Building.Pieces[id].cat~=target then updates[#updates+1]=id end
    end
    if #updates==0 then return {ok=true,moved=0,category=categories[target]} end
    local before=copy(overrides)
    for _,id in ipairs(updates) do
        overrides[id]=overrides[id] or {}
        overrides[id].cat=target
    end
    if not persistOverrides() then
        overrides=before
        return {ok=false,error='Speichern der Kategorien fehlgeschlagen'}
    end
    for _,id in ipairs(updates) do apply(id) end
    if Store and Store.log then
        Store.log(src,'admin',('moved %d catalogue props into %s'):format(#updates,target))
    end
    return {ok=true,moved=#updates,category=categories[target]}
end)

BSB.RegisterCallback('build:studio:categoryRename',function(src,payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id=type(payload)=='table' and tostring(payload.id or '') or ''
    local label=type(payload)=='table' and tostring(payload.label or ''):gsub('^%s+',''):gsub('%s+$','') or ''
    if not categories[id] then return {ok=false,error='Unbekannte Kategorie'} end
    if #label<2 or #label>40 then return {ok=false,error='Name muss 2–40 Zeichen haben'} end
    local old=categories[id];categories[id]=label
    if not saveCategories() then categories[id]=old;return {ok=false,error='Speichern fehlgeschlagen'} end
    return {ok=true,categories=categories}
end)
BSB.RegisterCallback('build:studio:categoryDelete',function(src,payload)
    if not staff(src) then return {ok=false,error='Keine Berechtigung'} end
    local id=type(payload)=='table' and tostring(payload.id or '') or ''
    local target=type(payload)=='table' and tostring(payload.target or '') or ''
    if not categories[id] then return {ok=false,error='Kategorie nicht gefunden'} end
    if id == 'claim' then return {ok=false,error='Claim ist geschützt und bleibt erhalten'} end
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
