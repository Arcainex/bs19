-- bs_multichar - join flow. Takes over when bs_core says the session is at 'select', drives the NUI, and hands control back once a character is chosen.
-- Talks to bs_core through exports and 'bs:hook:*' events only, never by passing functions across resources.

local State = { open = false, characters = {}, classes = {} }

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
local function preview(index)
    local char = State.characters[index]
    if char then
        Scene.SpawnPed(char.gender)
        Scene.Dress(char)
    else
        -- An empty slot shows a plain freemode ped. Its face is whatever the
        -- engine defaults to, which is correct: there is no character here yet.
        Scene.SpawnPed('male')
    end
end

function OpenSelect()
    if State.open then return end
    State.open = true

    Scene.Build()
    DoScreenFadeIn(Multichar.Scene.fadeIn)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    if not refresh() then
        print('^1[BeyondSurvival]^7 character list never arrived - is bs_core running?')
    end

    preview(1)
    send({ action = 'open' })
    focus(true)
end

-- @param takeover boolean|nil  true when bs_core is taking the player over.
function CloseSelect(handoff)
    if not State.open then return end
    State.open = false
    send({ action = 'close' })
    focus(false)
    Scene.Destroy(handoff)
end

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

-- Creator lists (factions, kit, clothes, roll tables, identity limits) come from the server, which validates the choices against the same config.
RegisterNUICallback('creatorData', function(_, cb)
    CreateThread(function()
        local r = BSB.Await('multichar:creatorData', 8000)
        cb(r or { ok = false })
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

-- Escape must never leave the player frozen with no UI.
CreateThread(function()
    -- Disables only last one frame, so every frame while open.
    while true do
        if State.open then
            Wait(0)
            DisableControlAction(0, 200, true)   -- pause menu
            DisableControlAction(0, 199, true)
        else
            Wait(250)
        end
    end
end)
