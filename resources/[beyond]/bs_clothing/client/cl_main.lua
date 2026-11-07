local open = false
local original = nil
local cam = nil
local selected = 'top'
local editorMode = false
local disabled = {}
local disabledTextures = {}
local favorite = {}
local torsoMappings = {}
local freeMoveMode = false
-- ALT-Orbit-Kamera: 0 Grad = ursprüngliche Frontansicht.
local orbitYaw = 0.0
local orbitPitch = 0.0
local orbitSensitivityX = 5.5
local orbitSensitivityY = 4.0
local orbitPitchMin = -22.0
local orbitPitchMax = 28.0
local handsUpActive = false
local playerLoaded = false
local ensureCurrentOutfitAllowed = nil
local startCategoryAtModelOne = nil


local categories = {
    { key='mask', label='Maske', kind='component', id=1 },
    { key='arms', label='Arme', kind='component', id=3 },
    { key='pants', label='Hose', kind='component', id=4 },
    { key='bag', label='Tasche', kind='component', id=5 },
    { key='shoes', label='Schuhe', kind='component', id=6 },
    { key='accessory', label='Accessoires', kind='component', id=7 },
    { key='undershirt', label='Untershirt', kind='component', id=8 },
    { key='top', label='Oberteil', kind='component', id=11 },
    { key='hat', label='Kopfbedeckung', kind='prop', id=0 },
    { key='glasses', label='Brille', kind='prop', id=1 },
    { key='ears', label='Ohren', kind='prop', id=2 },
    { key='watch', label='Uhr', kind='prop', id=6 },
    { key='bracelet', label='Armband', kind='prop', id=7 },
}

local function notify(msg)
    TriggerEvent('bs:notify', msg)
    TriggerEvent('chat:addMessage', { args = { '^5Beyond', msg } })
end

local function category(key)
    for _, c in ipairs(categories) do if c.key == key then return c end end
end

local function pedGenderKey(ped)
    return GetEntityModel(ped) == joaat('mp_f_freemode_01') and 'female' or 'male'
end

local function collectionInfo(ped, c, drawable)
    if drawable == nil or drawable < 0 then return '', -1 end
    if c.kind == 'component' then
        return GetPedDrawableVariationCollectionName(ped, c.id) or '', GetPedDrawableVariationCollectionLocalIndex(ped, c.id)
    end
    return GetPedPropCollectionName(ped, c.id) or '', GetPedPropCollectionLocalIndex(ped, c.id)
end

local function collectionInfoForDrawable(ped, c, drawable)
    if drawable == nil or drawable < 0 then return '', -1 end
    -- Temporarily derive stable collection/local IDs from a global drawable without changing persistence format.
    -- Cfx collection conversion natives are client-side and stable across title updates.
    if c.kind == 'component' then
        local current = GetPedDrawableVariation(ped, c.id)
        if drawable == current then
            return GetPedDrawableVariationCollectionName(ped, c.id) or '', GetPedDrawableVariationCollectionLocalIndex(ped, c.id)
        end
        -- Conversion natives for global -> collection/local.
        local name = GetPedCollectionNameFromDrawable(ped, c.id, drawable) or ''
        local idx = GetPedCollectionLocalIndexFromDrawable(ped, c.id, drawable)
        return name, idx
    end
    local current = GetPedPropIndex(ped, c.id)
    if drawable == current then
        return GetPedPropCollectionName(ped, c.id) or '', GetPedPropCollectionLocalIndex(ped, c.id)
    end
    local name = GetPedCollectionNameFromProp(ped, c.id, drawable) or ''
    local idx = GetPedCollectionLocalIndexFromProp(ped, c.id, drawable)
    return name, idx
end

-- Belegte Kleidungsmodelle werden collection-basiert aufgebaut.
-- Dadurch gibt es keine Lücken mehr in der Navigation: wenn eine Collection
-- endet, folgt direkt das erste tatsächlich vorhandene Modell der nächsten.
local occupiedModelCache = {}
-- Eintraege, die FiveM trotz vorhandener Collection-IDs nicht anwenden kann.
-- Diese werden fuer die restliche Sitzung NICHT mehr mitgezaehlt.
local rejectedModelEntries = {}
local function entryIdentity(ped, c, entry)
    return table.concat({tostring(GetEntityModel(ped)), c.kind, tostring(c.id),
        tostring(entry.collection), tostring(entry.localIndex)}, '|')
end


local function occupiedModelCacheKey(ped, c)
    return table.concat({ tostring(GetEntityModel(ped)), c.kind, tostring(c.id) }, '|')
end

local function occupiedModels(ped, c)
    local key = occupiedModelCacheKey(ped, c)
    if occupiedModelCache[key] then return occupiedModelCache[key] end

    local list, seen = {}, {}
    local collectionCount = math.max(0, GetPedCollectionsCount(ped))

    for collectionIndex = 0, collectionCount - 1 do
        local collectionName = GetPedCollectionName(ped, collectionIndex) or ''
        local count = 0

        if c.kind == 'component' then
            count = math.max(0, GetNumberOfPedCollectionDrawableVariations(ped, c.id, collectionName))
        else
            count = math.max(0, GetNumberOfPedCollectionPropDrawableVariations(ped, c.id, collectionName))
        end

        for localIndex = 0, count - 1 do
            local globalIndex
            if c.kind == 'component' then
                globalIndex = GetPedDrawableGlobalIndexFromCollection(ped, c.id, collectionName, localIndex)
            else
                globalIndex = GetPedPropGlobalIndexFromCollection(ped, c.id, collectionName, localIndex)
            end

            globalIndex = tonumber(globalIndex)
            if globalIndex and globalIndex >= 0 and not seen[globalIndex] then
                -- Gemeldete Collection-Slots koennen unbenutzbare leere
                -- Eintraege sein. Nur tatsaechlich gueltige Modelle auflisten.
                local occupied = false
                if c.kind == 'component' then
                    local textures = math.max(0, GetNumberOfPedCollectionTextureVariations(
                        ped, c.id, collectionName, localIndex))
                    for texture = 0, textures - 1 do
                        if IsPedCollectionComponentVariationValid(
                            ped, c.id, collectionName, localIndex, texture, 2) then
                            occupied = true
                            break
                        end
                    end
                else
                    occupied = GetNumberOfPedCollectionPropTextureVariations(
                        ped, c.id, collectionName, localIndex) > 0
                end
                if occupied then
                    seen[globalIndex] = true
                    list[#list + 1] = {
                        global = math.floor(globalIndex),
                        collection = collectionName,
                        localIndex = localIndex,
                    }
                end
            end
        end
    end

    -- Die Global-ID-Reihenfolge entspricht GTA/DLC/Custom-Reihenfolge.
    -- Sortieren schützt zusätzlich vor Packs, die Collections ungewöhnlich melden.
    table.sort(list, function(a, b)
        if a.global == b.global then return a.localIndex < b.localIndex end
        return a.global < b.global
    end)

    occupiedModelCache[key] = list
    return list
end

local function entryForGlobal(ped, c, globalDrawable)
    globalDrawable = tonumber(globalDrawable)
    if not globalDrawable or globalDrawable < 0 then return nil end
    for _, entry in ipairs(occupiedModels(ped, c)) do
        if entry.global == globalDrawable then return entry end
    end
    return nil
end

local function setCategoryEntry(ped, c, entry, texture)
    if not entry then return false end
    texture = math.max(0, math.floor(tonumber(texture) or 0))

    if c.kind == 'component' then
        local tc = math.max(1, GetNumberOfPedCollectionTextureVariations(
            ped, c.id, entry.collection, entry.localIndex))
        texture = math.min(texture, tc - 1)

        -- FiveM requires the palette as the final argument here.
        -- If the requested texture is invalid, try the other textures of this
        -- exact model instead of rejecting the entire drawable.
        local chosen = nil
        if IsPedCollectionComponentVariationValid(
            ped, c.id, entry.collection, entry.localIndex, texture, 2) then
            chosen = texture
        else
            for tex = 0, tc - 1 do
                if IsPedCollectionComponentVariationValid(
                    ped, c.id, entry.collection, entry.localIndex, tex, 2) then
                    chosen = tex
                    break
                end
            end
        end

        if chosen == nil then
            return false
        end

        SetPedCollectionComponentVariation(
            ped, c.id, entry.collection, entry.localIndex, chosen, 2)

        -- Verify that the engine really accepted the collection/local drawable.
        local gotCollection = GetPedDrawableVariationCollectionName(ped, c.id) or ''
        local gotLocal = GetPedDrawableVariationCollectionLocalIndex(ped, c.id)
        return gotCollection == entry.collection and gotLocal == entry.localIndex
    end

    local tc = math.max(1, GetNumberOfPedCollectionPropTextureVariations(
        ped, c.id, entry.collection, entry.localIndex))
    texture = math.min(texture, tc - 1)

    SetPedCollectionPropIndex(
        ped, c.id, entry.collection, entry.localIndex, texture, true)

    local gotCollection = GetPedPropCollectionName(ped, c.id) or ''
    local gotLocal = GetPedPropCollectionLocalIndex(ped, c.id)
    return gotCollection == entry.collection and gotLocal == entry.localIndex
end

local function setCategoryVariation(ped, c, globalDrawable, texture)
    if c.kind == 'prop' and (globalDrawable == nil or globalDrawable < 0) then
        ClearPedProp(ped, c.id)
        return true
    end

    local entry = entryForGlobal(ped, c, globalDrawable)
    if not entry then return false end
    return setCategoryEntry(ped, c, entry, texture)
end

local function itemKey(ped, c, drawable)
    if drawable == nil or drawable < 0 then return nil end
    local collection, localIndex = collectionInfoForDrawable(ped, c, drawable)
    return table.concat({pedGenderKey(ped), c.kind, tostring(c.id), collection, tostring(localIndex)}, '|')
end

local function textureKey(ped, c, drawable, texture)
    local k = itemKey(ped, c, drawable)
    if not k or texture == nil or texture < 0 then return nil end
    return k .. '|texture|' .. tostring(texture)
end

local function isDisabled(ped,c,d)
    local k=itemKey(ped,c,d); return k and disabled[k] == true or false
end
local function isTextureDisabled(ped,c,d,t)
    local k=textureKey(ped,c,d,t); return k and disabledTextures[k] == true or false
end
local function isFavorite(ped,c,d)
    local k=itemKey(ped,c,d); return k and favorite[k] == true or false
end

-- Fester Arme/Torso-Wert (Component 3) pro Oberteil (Component 11).
-- Gespeichert wird über den stabilen Collection/Local-Key des Oberteils.
local function getTorsoRule(ped, topDrawable)
    local top = category('top')
    local k = top and itemKey(ped, top, topDrawable) or nil
    local rule = k and torsoMappings[k] or nil
    if type(rule) ~= 'table' then return nil, k end
    return rule, k
end

local function applyTorsoRule(ped, topDrawable)
    local rule = getTorsoRule(ped, topDrawable)
    if not rule then return false end
    local drawable = math.floor(tonumber(rule.drawable) or 0)
    local maxDrawables = math.max(1, GetNumberOfPedDrawableVariations(ped, 3))
    drawable = math.max(0, math.min(drawable, maxDrawables - 1))
    local maxTextures = math.max(1, GetNumberOfPedTextureVariations(ped, 3, drawable))
    local texture = math.floor(tonumber(rule.texture) or 0)
    texture = math.max(0, math.min(texture, maxTextures - 1))
    SetPedComponentVariation(ped, 3, drawable, texture, 2)
    return true
end

-- Auch andere Ressourcen (z.B. bs_multichar) können exakt dieselbe
-- Oberteil->Torso-Regel auf einen beliebigen Freemode-Ped anwenden.
exports('ApplyTorsoForPed', function(ped)
    ped = tonumber(ped)
    if not ped or not DoesEntityExist(ped) then return false end
    local topDrawable = GetPedDrawableVariation(ped, 11)
    return applyTorsoRule(ped, topDrawable)
end)

local function currentTorsoData(ped)
    local d = GetPedDrawableVariation(ped, 3)
    local t = GetPedTextureVariation(ped, 3)
    local dc = math.max(1, GetNumberOfPedDrawableVariations(ped, 3))
    local tc = math.max(1, GetNumberOfPedTextureVariations(ped, 3, d))
    return d, t, dc, tc
end

local function textureCount(ped,c,d)
    if d == nil or d < 0 then return 1 end

    local entry = entryForGlobal(ped, c, d)
    if entry then
        if c.kind == 'component' then
            return math.max(1, GetNumberOfPedCollectionTextureVariations(
                ped, c.id, entry.collection, entry.localIndex))
        end
        return math.max(1, GetNumberOfPedCollectionPropTextureVariations(
            ped, c.id, entry.collection, entry.localIndex))
    end

    -- Fallback
    if c.kind == 'component' then
        return math.max(1, GetNumberOfPedTextureVariations(ped,c.id,d))
    end
    return math.max(1, GetNumberOfPedPropTextureVariations(ped,c.id,d))
end

-- Ein Modell wird in der Spieler-Umkleide exakt einmal und nur dann
-- gezählt, wenn es freigegeben UND mit mindestens einer gültigen, freigegebenen
-- Textur tatsächlich auswählbar ist. Der Editor behält die komplette Liste,
-- damit gesperrte Modelle weiterhin aktiviert werden können.
local activeModelCache = {}

local function entryRuleKey(ped, c, entry)
    return table.concat({pedGenderKey(ped), c.kind, tostring(c.id),
        entry.collection, tostring(entry.localIndex)}, '|')
end

local function entryTextureAllowed(ped, c, entry, texture, ruleKey)
    if not entry or texture == nil or texture < 0 then return false end
    local key = ruleKey or entryRuleKey(ped, c, entry)
    if disabledTextures[key .. '|texture|' .. tostring(texture)] == true then
        return false
    end
    if c.kind == 'component' then
        -- Manche Collection-Einträge melden Drawables, die die Engine nicht
        -- setzen kann. Diese dürfen KEINE Nummer im Spielerzähler belegen.
        return IsPedCollectionComponentVariationValid(
            ped, c.id, entry.collection, entry.localIndex, texture, 2)
    end
    return true
end

local function entryHasAllowedTexture(ped, c, entry)
    if not entry then return false end
    local ruleKey = entryRuleKey(ped, c, entry)
    if disabled[ruleKey] == true then return false end
    local count
    if c.kind == 'component' then
        count = GetNumberOfPedCollectionTextureVariations(
            ped, c.id, entry.collection, entry.localIndex)
    else
        count = GetNumberOfPedCollectionPropTextureVariations(
            ped, c.id, entry.collection, entry.localIndex)
    end
    for texture = 0, math.max(0, tonumber(count) or 0) - 1 do
        if entryTextureAllowed(ped, c, entry, texture, ruleKey) then
            return true
        end
    end
    return false
end

local function hasAllowedTexture(ped, c, d)
    if d == nil or d < 0 then return true end
    return entryHasAllowedTexture(ped, c, entryForGlobal(ped, c, d))
end

local function browsableModels(ped, c, includeDisabled)
    local base = occupiedModels(ped, c)
    -- Auch im Admin-Editor bleiben deaktivierte, aber wirklich vorhandene
    -- Modelle sichtbar. Fehlschlaege beim Anlegen zaehlen in keinem Modus.
    local list = {}
    if includeDisabled then
        for _, entry in ipairs(base) do
            if not rejectedModelEntries[entryIdentity(ped, c, entry)] then
                list[#list + 1] = entry
            end
        end
        return list
    end

    -- Keine gecachte Freigabeliste: Server-Regeln und Texture-Freigaben
    -- koennen sich jederzeit aendern. Immer die AKTUELLEN Regeln zaehlen.
    list = {}
    for _, entry in ipairs(base) do
        -- Gleicher stabiler Key wie beim Deaktivieren im Editor.
        -- Der Global-Index ist nur fuer die Engine, niemals fuer die Anzeige.
        if not rejectedModelEntries[entryIdentity(ped, c, entry)]
            and not isDisabled(ped, c, entry.global)
            and entryHasAllowedTexture(ped, c, entry) then
            list[#list + 1] = entry
        end
    end
    -- Index 1..#list ist die einzige sichtbare Modellnummer. Die realen
    -- GTA-Global-IDs können dabei beliebig große Lücken haben.
    return list
end

local function modelPositionInList(list, globalDrawable)
    globalDrawable = tonumber(globalDrawable)
    if not globalDrawable or globalDrawable < 0 then return 0 end
    for i, entry in ipairs(list or {}) do
        if entry.global == globalDrawable then return i end
    end
    return 0
end

local function modelEntryAtPosition(list, position)
    position = math.floor(tonumber(position) or 1)
    return list and list[position] or nil
end

local function modelAtPosition(list, position)
    local entry = modelEntryAtPosition(list, position)
    return entry and entry.global or nil
end

local function firstAllowedTexture(ped,c,d)
    if d == nil or d < 0 then return 0 end
    local entry = entryForGlobal(ped, c, d)
    local tc = textureCount(ped,c,d)
    for t=0,tc-1 do
        if entryTextureAllowed(ped, c, entry, t) then return t end
    end
    return 0
end

local function nextAllowedTexture(ped,c,d,current,step)
    if d == nil or d < 0 then return 0 end
    local entry = entryForGlobal(ped, c, d)
    local tc = textureCount(ped,c,d)
    if tc <= 1 then return 0 end
    local t=current
    for _=1,tc do
        t=t+step
        if t<0 then t=tc-1 elseif t>=tc then t=0 end
        if entryTextureAllowed(ped, c, entry, t) then return t end
    end
    return current
end

local function allowedTextureList(ped,c,d)
    local list = {}
    if d == nil or d < 0 then
        list[1] = 0
        return list
    end
    local entry = entryForGlobal(ped, c, d)
    local tc = textureCount(ped,c,d)
    for t=0,tc-1 do
        if entryTextureAllowed(ped, c, entry, t) then
            list[#list+1] = t
        end
    end
    return list
end

local function activeTexturePosition(list, actualTexture)
    for i, value in ipairs(list or {}) do
        if value == actualTexture then return i - 1 end
    end
    return 0
end

local function currentData(c)
    local ped = PlayerPedId()
    if c.kind == 'component' then
        local d = GetPedDrawableVariation(ped, c.id)
        local t = GetPedTextureVariation(ped, c.id)
        return d, t, GetNumberOfPedDrawableVariations(ped, c.id), GetNumberOfPedTextureVariations(ped, c.id, d)
    end
    local d = GetPedPropIndex(ped, c.id)
    local t = d < 0 and 0 or GetPedPropTextureIndex(ped, c.id)
    local dc = GetNumberOfPedPropDrawableVariations(ped, c.id)
    local tc = d < 0 and 1 or GetNumberOfPedPropTextureVariations(ped, c.id, d)
    return d, t, dc, tc
end

local function updateCam()
    if not cam then return end
    local ped = PlayerPedId()
    local c = category(selected)
    local z, targetZ, distance, fov = 0.62, 0.58, 2.35, 40.0
    if c then
        if c.key == 'pants' then z, targetZ, distance, fov = 0.45, 0.25, 2.55, 48.0
        elseif c.key == 'shoes' then z, targetZ, distance, fov = 0.18, -0.55, 2.30, 43.0
        elseif c.key == 'hat' or c.key == 'glasses' or c.key == 'ears' or c.key == 'mask' then z, targetZ, distance, fov = 0.78, 0.72, 1.75, 34.0
        elseif c.key == 'watch' or c.key == 'bracelet' then z, targetZ, distance, fov = 0.62, 0.38, 2.05, 38.0 end
    end

    -- Im ALT-Freimodus kann die Kamera mit der Maus frei um den Charakter
    -- gedreht werden. Die Position bleibt relativ zum Ped, daher folgt sie
    -- beim Laufen ohne die Script-Kamera neu zu starten.
    local yaw = math.rad(orbitYaw)
    local pitch = math.rad(orbitPitch)
    local horizontalDistance = distance * math.cos(pitch)
    local localX = math.sin(yaw) * horizontalDistance
    local localY = math.cos(yaw) * horizontalDistance
    local camZ = z + math.sin(pitch) * distance

    local pos = GetOffsetFromEntityInWorldCoords(ped, localX, localY, camZ)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    PointCamAtEntity(cam,ped,0.0,0.0,targetZ,true)
    SetCamFov(cam,fov)
end

local function sendState()
    local c=category(selected) or categories[1]
    local ped=PlayerPedId()
    local d,t,dc,tc=currentData(c)
    local models = browsableModels(ped, c, editorMode)
    local modelPosition = modelPositionInList(models, d)
    if c.kind ~= 'prop' and modelPosition == 0 and #models > 0 then modelPosition = 1 end
    local collection, localIndex = collectionInfo(ped,c,d)
    local texDisabled = d >= 0 and isTextureDisabled(ped,c,d,t) or false
    local allowedTextures = allowedTextureList(ped,c,d)
    local activeTextureCount = #allowedTextures
    local activeTextureIndex = activeTexturePosition(allowedTextures, t)
    local currentTop = GetPedDrawableVariation(ped, 11)
    local torsoRule = getTorsoRule(ped, currentTop)
    local torsoD, torsoT, torsoDC, torsoTC = currentTorsoData(ped)
    SendNUIMessage({
        action='state', categories=categories, selected=c.key, drawable=d, texture=t,
        drawableCount=dc, textureCount=tc, isProp=(c.kind=='prop'),
        modelPosition=modelPosition, modelCount=#models,
        activeTextureCount=activeTextureCount, activeTextureIndex=activeTextureIndex,
        allowedTextures=allowedTextures,
        editorMode=editorMode, disabled=isDisabled(ped,c,d), textureDisabled=texDisabled,
        favorite=isFavorite(ped,c,d), canTextureRule=(d >= 0 and tc > 0),
        collection=collection, localIndex=localIndex, gender=pedGenderKey(ped),
        componentId=c.id, kind=c.kind,
        torsoRuleActive=(torsoRule ~= nil),
        torsoDrawable=torsoD, torsoTexture=torsoT,
        torsoDrawableCount=torsoDC, torsoTextureCount=torsoTC,
        savedTorsoDrawable=torsoRule and tonumber(torsoRule.drawable) or nil,
        savedTorsoTexture=torsoRule and tonumber(torsoRule.texture) or nil,
        torsoLocked=(torsoRule ~= nil)
    })
    updateCam()
end

-- Outfit-Persistenz wird bewusst NICHT in bs_clothing dupliziert.
-- BeyondSurvival bs_core besitzt den Charakterzustand und speichert Kleidung
-- über das lokale Event `bs:outfit:push` in der Charakter-Datenbank.
-- Dadurch verwenden Spawn und bs_multichar dieselbe Quelle.

local function startCam()
    cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    updateCam(); RenderScriptCams(true,true,350,true,true)
end
local function stopCam()
    RenderScriptCams(false,true,250,true,true)
    if cam then DestroyCam(cam,false); cam=nil end
end


local function stopEditorHandsUp()
    if not handsUpActive then return end
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        StopAnimTask(ped, 'random@mugging3', 'handsup_standing_base', 2.0)
        ClearPedSecondaryTask(ped)
    end
    handsUpActive = false
end

local function startEditorHandsUp()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    local dict = 'random@mugging3'
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'handsup_standing_base', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        handsUpActive = true
    end
end

local function enterFreeMoveMode()
    if not open or freeMoveMode then return end
    freeMoveMode = true
    local ped = PlayerPedId()

    -- WICHTIG: Kamera und NUI bleiben dauerhaft aktiv/sichtbar.
    -- Wir lösen nur den NUI-Fokus, damit Tastatur/Maus wieder ans Spiel gehen.
    FreezeEntityPosition(ped, false)
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    if cam then
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        updateCam()
    end
    SendNUIMessage({ action='freeMove', active=true })
end

local function exitFreeMoveMode()
    if not open or not freeMoveMode then return end
    freeMoveMode = false
    local ped = PlayerPedId()

    -- Kein Kamera-Neustart: dieselbe Kleidungskamera läuft ohne Bildwechsel weiter.
    FreezeEntityPosition(ped, true)
    if cam then
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        updateCam()
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action='freeMove', active=false })
    sendState()
end

-- ALT wird als + / - Keymapping behandelt. Das ist stabiler als ein
-- Frame-fuer-Frame-Umschalten beim Wechsel des NUI-Fokus.
RegisterCommand('+bs_clothing_freemove', function()
    if open and (not Config.Clothing.editor or Config.Clothing.editor.freeMoveWithAlt ~= false) then
        enterFreeMoveMode()
    end
end, false)

RegisterCommand('-bs_clothing_freemove', function()
    if open and freeMoveMode then
        exitFreeMoveMode()
    end
end, false)

RegisterKeyMapping('+bs_clothing_freemove', 'Alpha-Z Kleidung: ALT Freimodus', 'keyboard', 'LMENU')
local function persistCurrentOutfit(reason)
    if GetResourceState('bs_core') ~= 'started' then return end
    local ok, outfit = pcall(function() return exports.bs_core:CaptureOutfit() end)
    if not ok or type(outfit) ~= 'table' then return end
    TriggerServerEvent('bs_clothing:saveOutfit', outfit, reason or 'wardrobe')
end

local function closeMenu(save)
    if not open then return end
    if not save and original then exports.bs_core:ApplyOutfit(PlayerPedId(), original) end

    -- Deaktivierte Modelle/Texturen dürfen auch nach ABBRECHEN nicht als
    -- getragenes Outfit bestehen bleiben. Regeln sind serverweit und werden
    -- unabhängig von den Outfit-Änderungen des Editors gespeichert.
    local repaired = false
    if ensureCurrentOutfitAllowed then repaired = ensureCurrentOutfitAllowed() end

    if save or repaired then
        -- Direkter, serverseitiger Charakter-Save über bs_core:SetCharacterOutfit.
        -- Das umgeht absichtlich die Händler-/Kaufprüfung von bs:outfit:push,
        -- weil diese Umkleide GTA-/Custom-Kleidung frei verwaltet.
        persistCurrentOutfit(save and 'wardrobe_save' or 'disabled_rule_repair')
    end
    stopEditorHandsUp()
    freeMoveMode=false
    open=false; editorMode=false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false,false); FreezeEntityPosition(PlayerPedId(),false); stopCam()
    SendNUIMessage({action='freeMove', active=false})
    SendNUIMessage({action='close'})
end
local function openMenu(asEditor)
    if open then return end
    local ped=PlayerPedId(); if IsPedInAnyVehicle(ped,false) then return end
    if ensureCurrentOutfitAllowed and not asEditor then
        if ensureCurrentOutfitAllowed() then persistCurrentOutfit('wardrobe_open_repair') end
    end
    original=exports.bs_core:CaptureOutfit(); open=true; editorMode=asEditor==true; selected='top'; freeMoveMode=false
    orbitYaw = 0.0
    orbitPitch = 0.0
    FreezeEntityPosition(ped,true)
    SetNuiFocus(true,true)
    -- ALT muss trotz NUI-Fokus vom Client erkannt werden können. Alle anderen
    -- Game-Controls werden im Hauptthread blockiert, solange ALT nicht gehalten wird.
    SetNuiFocusKeepInput(true)
    startCam()

    -- Alpha-Z: the currently worn outfit is the preview baseline.
    -- Do not change top or any other category merely by opening the wardrobe.

    SendNUIMessage({action='open', editorMode=editorMode}); sendState()
end

local function nextAllowedDrawable(c, current, step)
    local ped = PlayerPedId()
    local models = browsableModels(ped, c, false)
    if #models == 0 then return c.kind == 'prop' and -1 or 0 end

    local pos = modelPositionInList(models, current)
    if pos == 0 then
        return step < 0 and models[#models].global or models[1].global
    end

    pos = pos + (step < 0 and -1 or 1)
    if pos < 1 then pos = #models end
    if pos > #models then pos = 1 end
    return models[pos].global
end

-- Beim Öffnen / Wechsel einer Kategorie beginnt die Vorschau immer bei Modell 1.
-- Das beim Öffnen getragene Outfit steckt bereits in `original` und wird bei
-- ABBRECHEN vollständig wiederhergestellt.
startCategoryAtModelOne = function(c)
    if not c then return end
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    local models = browsableModels(ped, c, editorMode)
    if #models == 0 then
        if c.kind == 'prop' then ClearPedProp(ped, c.id) end
        return
    end

    -- "Modell 1" ist das erste wirklich belegte Modell, nicht Global-ID 1.
    local entry = models[1]
    local d = entry.global
    local t = editorMode and 0 or firstAllowedTexture(ped, c, d)

    setCategoryEntry(ped, c, entry, t)
    if c.key == 'top' then applyTorsoRule(ped, d) end
end

-- Entfernt aktuell getragene Modelle/Texturen, die im Alpha-Z Editor
-- deaktiviert wurden. Dadurch kann ein altes gespeichertes Outfit nie wieder
-- als "verbotenes" Teil in der normalen Umkleide hängen bleiben.
ensureCurrentOutfitAllowed = function()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    local changed = false

    for _, c in ipairs(categories) do
        local d, t = currentData(c)

        -- Ein fester Torso gehört zum Oberteil und hat Vorrang vor der normalen
        -- Arme-Liste. Sonst würde ein bewusst hinterlegter Torso weggesprungen.
        if not (c.key == 'arms' and getTorsoRule(ped, GetPedDrawableVariation(ped, 11))) then
            if c.kind == 'component' then
                local needModel = isDisabled(ped,c,d) or not hasAllowedTexture(ped,c,d)
                if needModel then
                    local nd = nextAllowedDrawable(c,d,1)
                    if nd ~= d or hasAllowedTexture(ped,c,nd) then
                        d = nd
                        t = firstAllowedTexture(ped,c,d)
                        setCategoryVariation(ped,c,d,t)
                        changed = true
                    end
                elseif isTextureDisabled(ped,c,d,t) then
                    local nt = nextAllowedTexture(ped,c,d,t,1)
                    if nt ~= t then
                        setCategoryVariation(ped,c,d,nt)
                        changed = true
                    end
                end
            else
                if d >= 0 then
                    local needModel = isDisabled(ped,c,d) or not hasAllowedTexture(ped,c,d)
                    if needModel then
                        local nd = nextAllowedDrawable(c,d,1)
                        if nd < 0 then
                            ClearPedProp(ped,c.id)
                        else
                            local nt = firstAllowedTexture(ped,c,nd)
                            setCategoryVariation(ped,c,nd,nt)
                        end
                        changed = true
                    elseif isTextureDisabled(ped,c,d,t) then
                        local nt = nextAllowedTexture(ped,c,d,t,1)
                        if nt ~= t then
                            setCategoryVariation(ped,c,d,nt)
                            changed = true
                        end
                    end
                end
            end
        end
    end

    local topDrawable = GetPedDrawableVariation(ped,11)
    if applyTorsoRule(ped, topDrawable) then
        -- Torso-Anwendung selbst ist kein Grund zum Speichern, wenn bereits gleich;
        -- Capture unten nimmt ihn bei einer anderen Reparatur aber korrekt mit.
    end
    return changed
end

RegisterNetEvent('bs_clothing:rules', function(d,dt,f,tm)
    disabled=d or {}; disabledTextures=dt or {}; favorite=f or {}; torsoMappings=tm or {}
    -- Änderungen im Clothing-Editor müssen den Spielerzähler sofort neu aufbauen.
    activeModelCache = {}
    if not (open and editorMode) then
        local ped=PlayerPedId()
        applyTorsoRule(ped, GetPedDrawableVariation(ped, 11))
    end
    if playerLoaded and not (open and editorMode) then
        CreateThread(function()
            Wait(150)
            if ensureCurrentOutfitAllowed and ensureCurrentOutfitAllowed() then
                persistCurrentOutfit('rules_repair')
            end
        end)
    end
    if open then sendState() end
end)
CreateThread(function() Wait(1000); TriggerServerEvent('bs_clothing:requestRules') end)

RegisterNUICallback('select',function(data,cb)
    selected=tostring(data.key or 'top')
    -- Keep the currently worn/previewed piece when switching categories.
    -- Only pressing the navigation arrows changes the selected garment.
    sendState()
    cb('ok')
end)

RegisterNUICallback('change',function(data,cb)
    local c=category(selected); if not c then cb('bad'); return end
    local ped=PlayerPedId()
    local oldD,oldT=select(1,currentData(c)),select(2,currentData(c))

    local d=oldD
    local t=math.floor(tonumber(data.texture) or oldT or 0)
    local drawableStep=tonumber(data.drawableStep) or 0
    local textureStep=tonumber(data.textureStep) or 0
    local requestedPosition=tonumber(data.modelPosition)

    if c.key == 'arms' and not editorMode then
        local topDrawable = GetPedDrawableVariation(ped, 11)
        if getTorsoRule(ped, topDrawable) then
            applyTorsoRule(ped, topDrawable)
            sendState(); cb('locked'); return
        end
    end

    -- Editor: alle belegten Modelle einschliesslich deaktivierter.
    -- Spieler: nur freigegebene Modelle, Positionen 1..N ohne Collection-Luecken.
    local models = browsableModels(ped, c, editorMode)
    if #models == 0 then
        if c.kind == 'prop' then ClearPedProp(ped,c.id) end
        sendState(); cb('empty'); return
    end

    local oldPos = modelPositionInList(models, oldD)
    local targetPos = oldPos
    local modelChanged = false

    if drawableStep ~= 0 then
        if c.kind == 'prop' then
            -- Props bekommen zusätzlich Position 0 = "nichts".
            -- /N zählt trotzdem ausschließlich echte belegte Modelle.
            if oldD < 0 then
                targetPos = drawableStep < 0 and #models or 1
            else
                targetPos = oldPos > 0 and oldPos or 1
                targetPos = targetPos + (drawableStep < 0 and -1 or 1)
                if targetPos < 0 then targetPos = #models end
                if targetPos > #models then targetPos = 0 end
            end
        else
            targetPos = oldPos > 0 and oldPos or (drawableStep < 0 and 1 or 0)
            targetPos = targetPos + (drawableStep < 0 and -1 or 1)
            if targetPos < 1 then targetPos = #models end
            if targetPos > #models then targetPos = 1 end
        end
        modelChanged = true
    elseif requestedPosition ~= nil then
        requestedPosition = math.floor(requestedPosition)
        if c.kind == 'prop' then
            targetPos = math.max(0, math.min(requestedPosition, #models))
        else
            targetPos = math.max(1, math.min(requestedPosition, #models))
        end
        modelChanged = targetPos ~= oldPos
    end

    local targetEntry = nil
    if modelChanged then
        if c.kind == 'prop' and targetPos == 0 then
            d = -1
            t = 0
        else
            targetEntry = modelEntryAtPosition(models, targetPos)
            d = targetEntry and targetEntry.global or oldD
            t = editorMode and 0 or firstAllowedTexture(ped,c,d)
        end
    else
        targetEntry = entryForGlobal(ped, c, oldD)
    end

    if c.kind=='component' then
        -- Falls nur die Textur verändert wird, auf dem aktuellen realen Modell bleiben.
        if not modelChanged then d = oldD end

        if not editorMode then
            if not hasAllowedTexture(ped,c,d) then
                d=nextAllowedDrawable(c,oldD,drawableStep < 0 and -1 or 1)
                t=firstAllowedTexture(ped,c,d)
            elseif not modelChanged then
                local tc=textureCount(ped,c,d)
                t=((t%tc)+tc)%tc
                if isTextureDisabled(ped,c,d,t) then
                    t=nextAllowedTexture(ped,c,d,oldT,textureStep < 0 and -1 or 1)
                end
            end
        end

        local tc=textureCount(ped,c,d); t=((t%tc)+tc)%tc
        targetEntry = entryForGlobal(ped, c, d)

        local applied = setCategoryEntry(ped, c, targetEntry, t)
        if not applied then
            -- Slot ist trotz Collection-Metadaten in FiveM nicht setzbar.
            -- Sofort aus dem sichtbaren Modellzaehler ausschliessen.
            if targetEntry then
                rejectedModelEntries[entryIdentity(ped, c, targetEntry)] = true
            end
            -- Ausschliesslich durch die sichtbare, dicht nummerierte Liste
            -- weitersuchen. Kein globaler GTA-ID-Sprung beim Collectionwechsel.
            local direction = drawableStep < 0 and -1 or 1
            local startPosition = targetPos > 0 and targetPos or modelPositionInList(models, d)
            for offset = 1, #models do
                local candidatePosition = ((startPosition - 1 + direction * offset) % #models) + 1
                local candidate = models[candidatePosition]
                local candidateTexture = editorMode and 0 or firstAllowedTexture(ped, c, candidate.global)
                if not rejectedModelEntries[entryIdentity(ped, c, candidate)] then
                    if setCategoryEntry(ped, c, candidate, candidateTexture) then
                        d, t, targetEntry = candidate.global, candidateTexture, candidate
                        applied = true
                        break
                    end
                    rejectedModelEntries[entryIdentity(ped, c, candidate)] = true
                end
            end
        end

        if c.key == 'top' then
            applyTorsoRule(ped, GetPedDrawableVariation(ped, c.id))
        end
    else
        if modelChanged and targetPos == 0 then
            ClearPedProp(ped,c.id)
            t=0
        else
            if not modelChanged then d = oldD end
            if d < 0 then
                ClearPedProp(ped,c.id); t=0
            else
                if not editorMode then
                    if not hasAllowedTexture(ped,c,d) then
                        d=nextAllowedDrawable(c,oldD,drawableStep < 0 and -1 or 1)
                        t=firstAllowedTexture(ped,c,d)
                    elseif not modelChanged then
                        local tc=textureCount(ped,c,d)
                        t=((t%tc)+tc)%tc
                        if isTextureDisabled(ped,c,d,t) then
                            t=nextAllowedTexture(ped,c,d,oldT,textureStep < 0 and -1 or 1)
                        end
                    end
                end
                local tc=textureCount(ped,c,d); t=((t%tc)+tc)%tc
                targetEntry = entryForGlobal(ped, c, d)
                if targetEntry then
                    setCategoryEntry(ped,c,targetEntry,t)
                end
            end
        end
    end

    sendState(); cb('ok')
end)

RegisterNUICallback('toggleDisabled' ,function(_,cb)
    if not editorMode then cb('no'); return end
    local c=category(selected); local ped=PlayerPedId(); local d=select(1,currentData(c)); local k=itemKey(ped,c,d)
    if k then TriggerServerEvent('bs_clothing:setRule',k,'disabled',not isDisabled(ped,c,d)) end
    cb('ok')
end)
RegisterNUICallback('toggleTextureDisabled',function(_,cb)
    if not editorMode then cb('no'); return end
    local c=category(selected); local ped=PlayerPedId(); local d,t=select(1,currentData(c)),select(2,currentData(c))
    local k=textureKey(ped,c,d,t)
    if k then TriggerServerEvent('bs_clothing:setRule',k,'disabledTexture',not isTextureDisabled(ped,c,d,t)) end
    cb('ok')
end)
RegisterNUICallback('toggleFavorite',function(_,cb)
    if not editorMode then cb('no'); return end
    local c=category(selected); local ped=PlayerPedId(); local d=select(1,currentData(c)); local k=itemKey(ped,c,d)
    if k then TriggerServerEvent('bs_clothing:setRule',k,'favorite',not isFavorite(ped,c,d)) end
    cb('ok')
end)

RegisterNUICallback('changeTorso',function(data,cb)
    if not editorMode or selected ~= 'top' then cb('no'); return end
    local ped=PlayerPedId()
    local oldD, oldT = currentTorsoData(ped)
    local d=math.floor(tonumber(data.drawable) or oldD)
    local t=math.floor(tonumber(data.texture) or oldT)
    local drawableStep=tonumber(data.drawableStep) or 0
    local textureStep=tonumber(data.textureStep) or 0
    local dc=math.max(1,GetNumberOfPedDrawableVariations(ped,3))
    d=((d%dc)+dc)%dc
    if drawableStep ~= 0 or d ~= oldD then t=0 end
    local tc=math.max(1,GetNumberOfPedTextureVariations(ped,3,d))
    t=((t%tc)+tc)%tc
    SetPedComponentVariation(ped,3,d,t,2)
    sendState(); cb('ok')
end)

RegisterNUICallback('saveTorso',function(_,cb)
    if not editorMode or selected ~= 'top' then cb('no'); return end
    local ped=PlayerPedId()
    local topDrawable=GetPedDrawableVariation(ped,11)
    local _, key=getTorsoRule(ped,topDrawable)
    local d,t=currentTorsoData(ped)
    if key then TriggerServerEvent('bs_clothing:setTorsoRule',key,d,t) end
    cb('ok')
end)

RegisterNUICallback('clearTorso',function(_,cb)
    if not editorMode or selected ~= 'top' then cb('no'); return end
    local ped=PlayerPedId()
    local topDrawable=GetPedDrawableVariation(ped,11)
    local _, key=getTorsoRule(ped,topDrawable)
    if key then TriggerServerEvent('bs_clothing:clearTorsoRule',key) end
    cb('ok')
end)

RegisterNUICallback('rotate',function(data,cb)
    SetEntityHeading(PlayerPedId(),GetEntityHeading(PlayerPedId())+(tonumber(data.delta) or 0)); updateCam(); cb('ok')
end)
RegisterNUICallback('save',function(_,cb) closeMenu(true); cb('ok') end)
RegisterNetEvent('bs_clothing:saveResult', function(ok, message)
    notify(message or (ok and 'Outfit gespeichert.' or 'Outfit konnte nicht gespeichert werden.'))
end)
RegisterNUICallback('cancel',function(_,cb) closeMenu(false); cb('ok') end)

RegisterCommand('clothingcollections', function()
    local ped = PlayerPedId()
    local c = category(selected) or category('top')
    local models = occupiedModels(ped, c)

    print(('^5[bs_clothing]^7 %s: %d belegte Modelle'):format(c.label, #models))
    local lastCollection = nil
    for i, e in ipairs(models) do
        if e.collection ~= lastCollection then
            if i > 1 then
                local prev = models[i - 1]
                print(('^5[bs_clothing]^7 Ende  #%d global=%d collection="%s" local=%d')
                    :format(i - 1, prev.global, prev.collection, prev.localIndex))
            end
            print(('^5[bs_clothing]^7 Start #%d global=%d collection="%s" local=%d')
                :format(i, e.global, e.collection, e.localIndex))
            lastCollection = e.collection
        end
    end
    if #models > 0 then
        local e = models[#models]
        print(('^5[bs_clothing]^7 Ende  #%d global=%d collection="%s" local=%d')
            :format(#models, e.global, e.collection, e.localIndex))
    end
end, false)

RegisterCommand('clothingnexttest', function()
    local ped = PlayerPedId()
    local c = category(selected) or category('top')
    local current = c.kind == 'component' and GetPedDrawableVariation(ped, c.id) or GetPedPropIndex(ped, c.id)
    local models = occupiedModels(ped, c)
    local pos = modelPositionInList(models, current)
    local nextPos = pos > 0 and (pos % #models) + 1 or 1
    local e = models[nextPos]
    if not e then
        print('^1[bs_clothing]^7 Kein nächstes Modell gefunden')
        return
    end
    local ok = setCategoryEntry(ped, c, e, 0)
    print(('^5[bs_clothing]^7 NEXT TEST #%d global=%d collection="%s" local=%d -> %s')
        :format(nextPos, e.global, e.collection, e.localIndex, ok and 'OK' or 'ABGELEHNT'))
end, false)

RegisterCommand('clothingeditor',function()
    if not Config.Clothing.editor or not Config.Clothing.editor.enabled then return end
    TriggerServerEvent('bs_clothing:requestEditor')
end,false)
RegisterNetEvent('bs_clothing:openEditor',function() openMenu(true) end)
RegisterNetEvent('bs_clothing:editorDenied',function() notify('Keine Berechtigung für den Kleidungseditor.') end)

-- bs_core lädt das gespeicherte Charakter-Outfit beim Character-Spawn selbst.
-- Wir greifen hier nur nach dem Laden die Torso-Regeln auf, ohne das Core-Outfit
-- mit einer zweiten Speicherquelle zu überschreiben.
AddEventHandler('bs:hook:player:loaded', function()
    playerLoaded = true
    CreateThread(function()
        -- bs_core setzt erst Modell/Appearance/Outfit; danach reparieren wir
        -- eventuell inzwischen deaktivierte Teile und schreiben genau diesen
        -- Zustand zurück in denselben Charakterdatensatz.
        Wait(1200)
        TriggerServerEvent('bs_clothing:requestRules')
        for _, delay in ipairs({ 250, 2500, 3500 }) do
            Wait(delay)
            if not playerLoaded then return end
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                applyTorsoRule(ped, GetPedDrawableVariation(ped, 11))
                if ensureCurrentOutfitAllowed and ensureCurrentOutfitAllowed() then
                    persistCurrentOutfit('spawn_repair')
                end
            end
        end
    end)
end)

AddEventHandler('bs:hook:player:unloaded', function()
    playerLoaded = false
end)

-- Erzwingt den serverseitig hinterlegten Arme/Torso-Wert auch nach Spawn,
-- Outfit-Load oder Änderungen durch andere Scripts. Im Editor ist die Vorschau frei.
CreateThread(function()
    while true do
        Wait(750)
        if not (open and editorMode) then
            local ped=PlayerPedId()
            if DoesEntityExist(ped) and not IsEntityDead(ped) then
                local topDrawable=GetPedDrawableVariation(ped,11)
                local rule=getTorsoRule(ped,topDrawable)
                if rule then
                    local wantedD=math.floor(tonumber(rule.drawable) or 0)
                    local wantedT=math.floor(tonumber(rule.texture) or 0)
                    if GetPedDrawableVariation(ped,3) ~= wantedD or GetPedTextureVariation(ped,3) ~= wantedT then
                        applyTorsoRule(ped,topDrawable)
                    end
                end
            end
        end
    end
end)

-- Charakterauswahl / Charaktereditor benutzen in bs_multichar einen eigenen
-- Preview-Ped. Dieser Ped bekommt Kleidung direkt vom Creator und würde dadurch
-- die Alpha-Z Torso-Zuordnung nicht kennen. bs_multichar markiert seinen Preview-
-- Ped mit StateBag `bsProtected`; genau diesen Freemode-Ped korrigieren wir hier.
--
-- Es wird nur reagiert, wenn sich das Oberteil des Preview-Peds geändert hat.
-- Dadurch läuft kein permanentes SetPedComponentVariation-Spam.
local previewTorsoState = {}
local previewTorsoLastCheck = {}

CreateThread(function()
    while true do
        local sessionState = nil
        if GetResourceState('bs_core') == 'started' then
            local ok, state = pcall(function()
                return exports.bs_core:GetSessionState()
            end)
            if ok then sessionState = state end
        end

        if sessionState == 'select' then
            local pool = GetGamePool('CPed')
            local foundPreview = false

            for _, ped in ipairs(pool or {}) do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    local model = GetEntityModel(ped)
                    if model == joaat('mp_m_freemode_01') or model == joaat('mp_f_freemode_01') then
                        local protected = false
                        local okState, state = pcall(function() return Entity(ped).state end)
                        if okState and state then
                            protected = state.bsProtected == true
                        end

                        if protected then
                            foundPreview = true
                            local top = GetPedDrawableVariation(ped, 11)
                            local topTex = GetPedTextureVariation(ped, 11)
                            local signature = ('%d:%d'):format(top, topTex)

                            -- Preview-Outfits werden teils verzögert oder mehrfach
                            -- aufgetragen. Deshalb auch bei unveraendertem Oberteil
                            -- regelmaessig kontrollieren, ob Arme/Torso abweichen.
                            local rule = getTorsoRule(ped, top)
                            local mismatch = rule and (
                                GetPedDrawableVariation(ped, 3) ~= math.floor(tonumber(rule.drawable) or 0)
                                or GetPedTextureVariation(ped, 3) ~= math.floor(tonumber(rule.texture) or 0))
                            local now = GetGameTimer()
                            if previewTorsoState[ped] ~= signature
                                or (mismatch and now - (previewTorsoLastCheck[ped] or 0) >= 350) then
                                previewTorsoState[ped] = signature
                                previewTorsoLastCheck[ped] = now

                                -- Einen Frame warten, damit der Creator zuerst sein komplettes
                                -- Outfit (3/8/11) auftragen kann. Danach gewinnt die Alpha-Z-Regel.
                                CreateThread(function()
                                    Wait(0)
                                    if DoesEntityExist(ped) then
                                        local currentTop = GetPedDrawableVariation(ped, 11)
                                        applyTorsoRule(ped, currentTop)
                                    end
                                end)
                            end
                        end
                    end
                end
            end

            -- Alte Entity-Handles vergessen, wenn Preview-Peds neu gebaut wurden.
            if not foundPreview then previewTorsoState = {}; previewTorsoLastCheck = {} end
            Wait(100)
        else
            previewTorsoState = {}
            previewTorsoLastCheck = {}
            Wait(750)
        end
    end
end)

CreateThread(function()
    while true do
        local wait=1000
        if not open then
            local ped=PlayerPedId(); local pos=GetEntityCoords(ped)
            for _,loc in ipairs(Config.Clothing.locations) do
                local dist=#(pos-loc.coords)
                if dist<Config.Clothing.drawDistance then
                    wait=0
                    DrawMarker(2,loc.coords.x,loc.coords.y,loc.coords.z+0.18,0,0,0,0,180.0,0,0.20,0.20,0.20,255,255,255,150,false,true,2,false,nil,nil,false)
                    if dist<Config.Clothing.interactDistance then
                        SetScriptVariableHudColour(126, 128, 62, 255)
                        BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName('Drücke ~INPUT_CONTEXT~ um die ~v~Umkleide~s~ zu öffnen'); EndTextCommandDisplayHelp(0,false,false,-1)
                        if IsControlJustReleased(0,38) then openMenu(false) end
                    end
                end
            end
        else
            wait=0
            if not freeMoveMode then
                -- Normaler Editorbetrieb: nur das NUI bekommt Eingaben.
                -- ALT selbst bleibt aktiv, damit das Keymapping den Freimodus starten kann.
                DisableAllControlActions(0)
                EnableControlAction(0,19,true)
            else
                -- ALT-Freimodus: NUI bleibt sichtbar und dieselbe Script-Kamera bleibt an.
                -- WASD/Keybinds gehen ans Spiel; Mausbewegung steuert ausschließlich die
                -- Orbit-Kamera um den Charakter.
                DisableControlAction(0, 1, true) -- LOOK_LR
                DisableControlAction(0, 2, true) -- LOOK_UD

                local lookX = GetDisabledControlNormal(0, 1)
                local lookY = GetDisabledControlNormal(0, 2)
                if math.abs(lookX) > 0.0001 then
                    orbitYaw = orbitYaw - (lookX * orbitSensitivityX)
                    if orbitYaw > 180.0 then orbitYaw = orbitYaw - 360.0 end
                    if orbitYaw < -180.0 then orbitYaw = orbitYaw + 360.0 end
                end
                if math.abs(lookY) > 0.0001 then
                    orbitPitch = orbitPitch - (lookY * orbitSensitivityY)
                    orbitPitch = math.max(orbitPitchMin, math.min(orbitPitchMax, orbitPitch))
                end

                if cam then updateCam() end

                -- H = Hände hoch. X = Animation abbrechen. Andere Server-Keybinds bleiben
                -- ebenfalls frei, weil das NUI während ALT keinen Keyboard-Fokus besitzt.
                if (not Config.Clothing.editor or Config.Clothing.editor.freeMoveHandsUp ~= false) and IsControlJustPressed(0,74) and not handsUpActive then
                    CreateThread(startEditorHandsUp)
                end
                if IsControlJustPressed(0,73) then
                    if handsUpActive then
                        stopEditorHandsUp()
                    else
                        ClearPedTasks(PlayerPedId())
                    end
                end
            end
        end
        Wait(wait)
    end
end)


-- ALPHA-Z GULAG PACKS: cache refresh + client diagnostics.
-- Existing collection navigation, model numbering, editor permissions and saved rules stay unchanged.
local gulagResourceTokens = {
    { resource='gulag_cloth1', token='siycclothes1', label='SIYC 1 (Maenner/Frauen)' },
    { resource='gulag_cloth2', token='siycclothes2', label='SIYC 2 (Frauen)' },
    { resource='gulag_cloth3', token='navyaus', label='Navy AUS (Maenner)' },
    { resource='gulag_cloth4', token='opforclothing', label='OPFOR (Maenner)' },
    { resource='gulag_cloth5', token='', label='Vanilla-Ersatz, kein Add-on' },
    { resource='gulag_cloth6', token='deadlands', label='Deadlands (Maenner/Frauen)' },
}

local function isGulagResource(resource)
    return type(resource) == 'string' and resource:match('^gulag_cloth[1-6]$') ~= nil
end

local function clearGulagCollectionCache(resource)
    if not isGulagResource(resource) then return end
    occupiedModelCache = {}
    rejectedModelEntries = {}
    print(('[bs_clothing] Collection-Cache aktualisiert nach %s.'):format(resource))
end

AddEventHandler('onClientResourceStart', clearGulagCollectionCache)
AddEventHandler('onClientResourceStop', clearGulagCollectionCache)

-- /clothingpacks: F8 status for each streamed Gulag collection on the CURRENT ped.
-- Male-only packs won't appear on a female ped and vice versa.
RegisterCommand('clothingpacks', function()
    local ped = PlayerPedId()
    local count = math.max(0, tonumber(GetPedCollectionsCount(ped)) or 0)
    local gender = pedGenderKey(ped)
    local names = {}
    for i = 0, count - 1 do
        names[#names + 1] = tostring(GetPedCollectionName(ped, i) or '')
    end

    print(('^5[Alpha-Z Gulag]^7 Ped=%s, Collections=%d'):format(gender, count))
    for _, pack in ipairs(gulagResourceTokens) do
        local state = GetResourceState(pack.resource)
        if pack.resource == 'gulag_cloth5' then
            print(('^3[Alpha-Z Gulag]^7 %s: %s | keine neue Collection (Vanilla-Ersatz)')
                :format(pack.resource, state))
        else
            local matched = {}
            for _, name in ipairs(names) do
                if name:lower():find(pack.token, 1, true) then
                    local models = 0
                    for _, c in ipairs(categories) do
                        local n = c.kind == 'component'
                            and GetNumberOfPedCollectionDrawableVariations(ped, c.id, name)
                            or GetNumberOfPedCollectionPropDrawableVariations(ped, c.id, name)
                        models = models + math.max(0, tonumber(n) or 0)
                    end
                    matched[#matched + 1] = ('%s (%d Slots)'):format(name, models)
                end
            end
            local result = #matched > 0 and table.concat(matched, ', ')
                or 'keine passende Collection fuer dieses Ped erkannt'
            print(('^5[Alpha-Z Gulag]^7 %s: %s | %s'):format(pack.resource, state, result))
        end
    end
    print('^5[Alpha-Z Gulag]^7 Mit /clothingcollections die Grenzen der aktuell ausgewaehlten Kategorie pruefen.')
end, false)
