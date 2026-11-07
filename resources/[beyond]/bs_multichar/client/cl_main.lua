-- bs_multichar - join flow. Takes over when bs_core says the session is at 'select', drives the NUI, and hands control back once a character is chosen.
-- Talks to bs_core through exports and 'bs:hook:*' events only, never by passing functions across resources.

local State = { open = false, characters = {}, classes = {}, loadingClosed = false }

local function send(payload) SendNUIMessage(payload) end

local function focus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

--------------------------------------------------------------------------------
-- Opening / closing
--------------------------------------------------------------------------------

local function refresh()
    local data = BSB.Await('characters:list', 10000)
    if not data then return false end

    State.characters = data.characters or {}
    State.classes    = data.classes or {}
    State.maxSlots   = data.maxSlots or 3
    State.appearance = data.appearance or {}

    send({
        action     = 'setData',
        characters = State.characters,
        classes    = State.classes,
        maxSlots   = State.maxSlots,
        appearance = State.appearance,
    })
    return true
end

--- Shows the ped for a slot (or a blank one when there are no characters yet).
local previewGeneration=0
local previewCharacterId=nil
local currentCarryItems=nil
local currentCarryPed=nil
local function clearSceneCarry()
 currentCarryItems=nil
 currentCarryPed=nil
 if GetResourceState('alpha_z_weaponcarry')=='started' then
  pcall(function() exports.alpha_z_weaponcarry:ClearPreviewPedWeapons() end)
 end
end

local function putSceneCarry(ped,items)
 if not State.open or ped==0 or not DoesEntityExist(ped) then return end
 if GetResourceState('alpha_z_weaponcarry')~='started' then return end
 -- The preview should be holstered, even if lastWeapon metadata had a gun in hand.
 if #items>0 then RemoveAllPedWeapons(ped,true) end
 local ok,result=pcall(function()
  return exports.alpha_z_weaponcarry:SetPreviewPedWeapons(ped,items)
 end)
 if ok and result then currentCarryPed=ped end
end

local function preview(index)
    previewGeneration=previewGeneration+1
    local generation=previewGeneration
    clearSceneCarry()
    local char = State.characters[index]
    if char then
        Scene.SpawnPed(char.gender)
        Scene.Dress(char)
    else
        -- An empty slot shows a plain freemode ped. Its face is whatever the
        -- engine defaults to, which is correct: there is no character here yet.
        Scene.SpawnPed('male')
    end
    previewCharacterId=char and tonumber(char.id) or nil
    if not previewCharacterId or not Scene.ped or not DoesEntityExist(Scene.ped) then return end
    local ped=Scene.ped
    local charId=previewCharacterId
    -- Do not block the survivor list while the inventory DB is queried.
    CreateThread(function()
        local data=BSB.Await('multichar:previewCarry',10000,charId)
        if generation~=previewGeneration or not State.open or
           previewCharacterId~=charId or Scene.ped~=ped or not DoesEntityExist(ped) then return end
        if not data or data.ok~=true or type(data.items)~='table' then return end
        currentCarryItems=data.items
        putSceneCarry(ped,currentCarryItems)
    end)
end

function OpenSelect()
    if State.open then return end
    State.open = true
    -- Other Alpha-Z resources may mute their screen messages while customizing.
    if LocalPlayer and LocalPlayer.state then LocalPlayer.state:set('azCharacterEditor', true, false) end
    TriggerEvent('bs:alphaweather:creatorQuiet', true)

    Scene.Build()
    DoScreenFadeIn(Multichar.Scene.fadeIn)

    if not refresh() then
        print('^1[BeyondSurvival]^7 character list never arrived - is bs_core running?')
    end

    preview(1)
    send({ action = 'open' })
    focus(true)
end

-- The browser acknowledges that the character selection is visible.
RegisterNUICallback('selectionReady', function(_, cb)
    if State.open and not State.loadingClosed then
        State.loadingClosed = true

        -- The loading screen owns the cursor while loadscreen_cursor is enabled.
        -- Fully release that cursor/focus first, then give NUI focus back to
        -- bs_multichar after the loadscreen has finished shutting down.
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()

        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)

        CreateThread(function()
            Wait(500)
            if not State.open then return end

            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            SetMouseCursorVisibleInMenus(true)
            SetCursorLocation(0.5, 0.5)

            -- One more explicit false -> true transition after the loadscreen
            -- teardown, because simply repeating "true" does not recreate the
            -- FiveM cursor in some loadscreen hand-offs.
            Wait(500)
            if not State.open then return end
            SetNuiFocus(false, false)
            Wait(0)
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            SetMouseCursorVisibleInMenus(true)
            SetCursorLocation(0.5, 0.5)
        end)
    end
    cb({ ok = true })
end)

-- @param takeover boolean|nil  true when bs_core is taking the player over.
function CloseSelect(handoff)
    if not State.open then return end
    State.open = false
    if LocalPlayer and LocalPlayer.state then LocalPlayer.state:set('azCharacterEditor', false, false) end
    TriggerEvent('bs:alphaweather:creatorQuiet', false)
    previewGeneration=previewGeneration+1
    previewCharacterId=nil
    clearSceneCarry()
    send({ action = 'close' })

    -- Only at the final character -> gameplay handoff, briefly return the cursor
    -- to the game window so GTA/FiveM reacquires mouse capture. Loading screen and
    -- character selection/creator stay unrestricted for multi-monitor use.
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SetMouseCursorVisibleInMenus(false)
    SetCursorLocation(0.5, 0.5)

    CreateThread(function()
        for i = 1, 30 do
            Wait(0)
            SetNuiFocusKeepInput(false)
            SetMouseCursorVisibleInMenus(false)
            if i == 1 or i == 5 or i == 15 then
                SetCursorLocation(0.5, 0.5)
            end
        end
    end)

    Scene.Destroy(handoff)
end

-- The selection scene's watchdog can rebuild its ped after streaming changes.
-- Reattach the CURRENT character's saved props to its new local-only ped.
CreateThread(function()
    while true do
        Wait(750)
        if State.open and currentCarryItems and previewCharacterId and
           Scene.ped and DoesEntityExist(Scene.ped) and Scene.ped~=currentCarryPed then
            putSceneCarry(Scene.ped,currentCarryItems)
        end
    end
end)

-- bs_core broadcasts its hooks as events; this is where control passes over.
AddEventHandler('bs:hook:session:state', function(state)
    if state == 'select' then
        CreateThread(OpenSelect)
    end
end)

-- The character is chosen and bs_core is already swapping the model, teleporting
-- and fading. Hand off rather than tearing the player ped about ourselves.
AddEventHandler('bs:hook:player:loaded', function()
    CloseSelect(true)
end)

--- Catch-up. If this resource starts (or is restarted) while the player is
--- already sitting at 'select', the state event has long since been and gone -
--- so ask, rather than waiting for an event that will never fire again.
CreateThread(function()
    Wait(1200)
    if State.open then return end
    if GetResourceState('bs_core') ~= 'started' then return end

    local ok, state = pcall(function() return exports.bs_core:GetSessionState() end)
    if ok and state == 'select' then
        print('^3[BeyondSurvival]^7 (multichar) started mid-select - opening the screen')
        OpenSelect()
    end
end)

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------

-- Every handler that can reach Scene.SpawnPed runs in its own thread:
-- SpawnPed waits on the model loading, and yielding directly inside an NUI
-- callback raises "attempt to yield across a C-call boundary".
RegisterNUICallback('preview', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then return cb({ ok = true }) end
    CreateThread(function() preview(tonumber(data.index) or 1) end)
    cb({ ok = true })
end)

-- Leaving the creator re-frames the survivor list (zoom/rotation persist while browsing, but not when coming back from the creator). See Scene.ResetView.
RegisterNUICallback('resetView', function(_, cb)
    if AppearanceEdit and AppearanceEdit.active then return cb({ ok = true }) end
    Scene.ResetView()
    cb({ ok = true })
end)

RegisterNUICallback('rotate', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then AppearanceEdit.Rotate(data.delta); return cb({ ok = true }) end
    Scene.Rotate(tonumber(data.delta) or 0)
    cb({ ok = true })
end)

RegisterNUICallback('zoom', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then AppearanceEdit.Zoom(data.delta); return cb({ ok = true }) end
    Scene.SetZoom(tonumber(data.delta) or 0)
    cb({ ok = true })
end)

RegisterNUICallback('focus', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then return cb({ ok = true }) end
    -- A missing mode is a UI bug, not a request to reset the camera. Ignoring
    -- it keeps a stray click from yanking the framing back to full body.
    if type(data.mode) ~= 'string' then return cb({ ok = false }) end
    Scene.SetFocus(data.mode)
    cb({ ok = true })
end)

RegisterNUICallback('play', function(data, cb)
    local id = tonumber(data.id)
    if not id then return cb({ ok = false, error = 'no character' }) end

    -- Safe spawn: announced before the character is selected, because bs_core's player:loaded handler starts as soon as the server answers.
    -- An event rather than a shared value (two resources). bs_core arms a one-shot flag and clears it on use.
    TriggerEvent('bs:core:safeSpawn', data.safeSpawn and true or false)

    CreateThread(function()
        local result = BSB.Await('characters:select', 15000, id)
        if not result or not result.ok then
            return cb({ ok = false, error = (result and result.error) or 'no response' })
        end

        DoScreenFadeOut(Multichar.Scene.fadeOut)
        Wait(Multichar.Scene.fadeOut)
        -- bs_core's player:loaded handler owns the player ped from here.
        CloseSelect(true)
        cb({ ok = true })
    end)
end)

RegisterNUICallback('delete', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('characters:delete', 10000, tonumber(data.id))
        if result and result.ok then
            State.characters = result.characters or {}
            send({ action = 'setData', characters = State.characters })
            preview(1)
        end
        cb(result or { ok = false })
    end)
end)

--- Live preview while the creator is open: rebuild the ped from the draft.
RegisterNUICallback('draft', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then AppearanceEdit.Draft(data.draft); return cb({ ok = true }) end
    CreateThread(function()
        local draft = data.draft or {}

        if data.rebuild or not Scene.ped or not DoesEntityExist(Scene.ped) then
            Scene.SpawnPed(draft.gender or 'male')
        end

        -- Guard: ApplyAppearanceTo falls back to the LOCAL PLAYER's ped when
        -- given nil, which would silently restyle the hidden real character
        -- instead of the preview.
        if not Scene.ped or not DoesEntityExist(Scene.ped) then
            return cb({ ok = false, error = 'no preview ped' })
        end

        -- Start from a clean ped: the creator reuses the preview ped between drafts, so a draft would inherit the previous weapon and props. See Scene.StripPed.
        Scene.StripPed(Scene.ped)

        exports.bs_core:ApplyAppearanceTo(Scene.ped, draft.appearance)

        -- The CLOTHING step sends the outfit it is building; Scene.ApplyLook skips any drawable this model lacks. Without one the preview keeps bs_core's default outfit.
        local outfit = draft.outfit
        if type(outfit) == 'table' then Scene.ApplyLook(outfit.components, outfit.props) end

        -- Built hidden, shown once dressed - see the note in Scene.Build.
        Scene.Reveal()

        -- Tell the creator what this model has, so its clothing arrows skip drawables that do not exist.
        local counts, tex = Scene.Report(Scene.ped)
        cb({ ok = true, counts = counts, tex = tex })
    end)
end)

-- Enumerate only when the wardrobe step is entered, not on each face slider.
RegisterNUICallback('wardrobeCatalog', function(data, cb)
    CreateThread(function()
        local ped = Scene.ped
        if not ped or not DoesEntityExist(ped) then return cb({ ok = false, error = 'Vorschau wird geladen.' }) end
        local wanted = data and data.gender == 'female' and 'female' or 'male'
        local current = GetEntityModel(ped) == joaat('mp_f_freemode_01') and 'female' or 'male'
        if wanted ~= current then return cb({ ok = false, error = 'Charaktermodell wird geladen.' }) end
        -- Rules originate on the server on creatorData; the server checks again on save.
        local catalog, gender = Scene.WardrobeCatalog(data and data.rules or {})
        if not catalog then return cb({ ok = false }) end
        -- Server remembers only the latest catalog for this player and sex.
        local registered = BSB.Await('multichar:registerCatalog', 15000, gender, catalog)
        if not registered or registered.ok ~= true then return cb({ ok = false, error = 'Kleidungskatalog konnte nicht freigegeben werden.' }) end
        cb({ ok = true, gender = gender, catalog = catalog })
    end)
end)

-- Creator lists (factions, kit, clothes, roll tables, identity limits) come from the server, which validates the choices against the same config.
RegisterNUICallback('creatorData', function(_, cb)
    CreateThread(function()
        local r = BSB.Await('multichar:creatorData', 8000)
        cb(r or { ok = false })
    end)
end)

RegisterNUICallback('saveDefaultOutfit', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('multichar:saveDefaultOutfit', 10000, data.gender, data.outfit)
        cb(result or { ok = false, error = 'Keine Serverantwort.' })
    end)
end)

-- Hands up / down on the preview ped, to check how clothes clip.
RegisterNUICallback('handsUp', function(data, cb)
    CreateThread(function() Scene.SetHandsUp(data and data.on == true) end)
    cb({ ok = true })
end)

RegisterNUICallback('create', function(data, cb)
    CreateThread(function()
        local payload = data.character or {}

        local result = BSB.Await('multichar:create', 15000, payload)
        if not result or not result.ok then
            return cb({ ok = false, error = (result and result.error) or 'no response' })
        end

        State.characters = result.characters or State.characters
        send({ action = 'setData', characters = State.characters })
        -- Returned as well as broadcast so the NUI does not read a stale copy and select the wrong slot.
        cb({ ok = true, charId = result.charId, characters = State.characters })
    end)
end)

-- Language picked in the creator: saved per account by bs_core, the state bag change relabels the page.
RegisterNUICallback('setLang', function(data, cb)
    local l = type(data) == 'table' and data.lang
    if type(l) == 'string' and BSLocale.IsValid(l) then BSLocale.Set(l) end
    cb({ ok = true, lang = BSLocale.Lang() })
end)

RegisterNUICallback('close', function(_, cb)
    -- The select screen cannot be dismissed - there is nowhere to go back to.
    cb({ ok = false })
end)

--------------------------------------------------------------------------------
-- Safety net
--------------------------------------------------------------------------------

-- If bs_core is restarted while the screen is open, do not strand the player.
AddEventHandler('onResourceStop', function(resource)
    -- ...or if this resource itself is stopped with it open.
    if resource == 'bs_core' or resource == GetCurrentResourceName() then CloseSelect() end
end)


-- ESC opens the GTA pause menu while character selection remains active.
local azPauseOpen = false
RegisterNUICallback('azOpenPauseMenu', function(_, cb)
    if not State.open or azPauseOpen then return cb({ok=false}) end
    azPauseOpen = true
    cb({ok=true})
    CreateThread(function()
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
        Wait(0)
        SetPauseMenuActive(true)
        local deadline = GetGameTimer() + 1800
        local appeared = false
        while State.open and GetGameTimer() < deadline do
            Wait(0)
            if IsPauseMenuActive() then appeared = true; break end
        end
        if appeared then
            while State.open and IsPauseMenuActive() do Wait(100) end
        end
        if State.open then
            Wait(150)
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            SetMouseCursorVisibleInMenus(true)
        end
        azPauseOpen = false
    end)
end)

-- Quiet editing: do not let GTA's standard notifications obscure the model.
CreateThread(function()
    while true do
        if State.open or (AppearanceEdit and AppearanceEdit.active) then
            Wait(0)
            ThefeedHideThisFrame()
            HideHudAndRadarThisFrame()
        else
            Wait(500)
        end
    end
end)

exports('IsCharacterScreenOpen', function() return State.open end)
