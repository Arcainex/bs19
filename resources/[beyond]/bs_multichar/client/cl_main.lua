-- bs_multichar - join flow.

local State = { open = false, characters = {}, classes = {} }
local selectionRun=0

local function send(payload) SendNUIMessage(payload) end

local function focus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

-- Screen grade while choosing. 'crisp' clears every engine grade, 'cinematic' adds a light filmic one, 'legacy' is the old soft haze.
local GRADES = {
    cinematic = { names = { 'NG_filmic01', 'MP_corona_heist' }, strength = 0.22 },
    legacy    = { names = { 'spectator5' }, strength = 0.32 },
}

local function clearGrade()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    pcall(function() SetNoiseOveride(false); SetNoisinessOveride(0.0) end)
end

local function applyGrade()
    clearGrade()
    local grade = GRADES[tostring(Multichar.Selection.grade or 'crisp')]
    if not grade then return end
    for _, name in ipairs(grade.names) do
        SetTimecycleModifier(name)
        if GetTimecycleModifierIndex() ~= -1 then
            SetTimecycleModifierStrength(grade.strength)
            return
        end
    end
    ClearTimecycleModifier()
end

-- The player's own screen filter (bs_ui) must not lay grain or a vignette over the selector.
local function suspendFilter(on)
    if GetResourceState('bs_ui') ~= 'started' then return end
    pcall(function() exports.bs_ui:SuspendFilter(on) end)
end

-- Opening / closing

local function refresh(current)
    local data = BSB.Await('characters:list', 10000)
    if not data or not current()then return false end

    State.characters = data.characters or {}
    State.classes    = data.classes or {}
    State.maxSlots   = data.maxSlots or 3
    State.appearance = data.appearance or {}

    State.cards = {}

    send({
        action     = 'setData',
        characters = State.characters,
        classes    = State.classes,
        maxSlots   = State.maxSlots,
        appearance = State.appearance,
        cards      = State.cards,
    })
    -- Extra card details should never delay a usable character list.
    CreateThread(function()
        local extra=BSB.Await('multichar:cards',6000)
        if not current()then return end
        State.cards=(extra and extra.cards)or {}
        send({action='setData',cards=State.cards})
    end)
    return true
end

-- Portraits: a headshot of the preview ped, taken the first time each survivor is shown.
local Shots = {}
local portraitGeneration = 0

local function releasePortrait(id, shot)
    if shot.ped and DoesEntityExist(shot.ped) then DeleteEntity(shot.ped);shot.ped=nil end
    if shot.handle then
        UnregisterPedheadshot(shot.handle)
        shot.handle = nil
    end
    if Shots[id] == shot then Shots[id] = nil end
end

local function cancelPendingPortraits()
    portraitGeneration = portraitGeneration + 1
    for id, shot in pairs(Shots) do
        if shot.pending and not shot.ped then releasePortrait(id, shot) end
    end
    return portraitGeneration
end

local function portrait(char, generation, ped, background)
    if not char or not char.id or Shots[char.id] or not ped then return end
    local id = char.id
    local shot = { pending = true, ped = background and ped or nil }
    Shots[id] = shot
    local function current()
        return State.open and (background or (portraitGeneration == generation and Scene.ped == ped))
            and DoesEntityExist(ped) and Shots[id] == shot
    end
    CreateThread(function()
        Wait(250) -- let the outfit settle; portrait peds are frozen and never animate
        if not current() then releasePortrait(id, shot); return end
        local handle = RegisterPedheadshot(ped)
        if not handle or handle < 0 then releasePortrait(id, shot); return end
        shot.handle = handle
        local untilAt = GetGameTimer() + 4000
        while current() and not IsPedheadshotReady(shot.handle) and GetGameTimer() < untilAt do Wait(50) end
        if not current() or not IsPedheadshotValid(shot.handle) or not IsPedheadshotReady(shot.handle) then
            releasePortrait(id, shot)
            return
        end
        local txd = GetPedheadshotTxdString(shot.handle)
        if type(txd) ~= 'string' or txd == '' then releasePortrait(id, shot); return end
        shot.pending = false
        send({ action = 'portrait', id = id, url = ('https://nui-img/%s/%s'):format(txd, txd) })
    end)
end

local function dropPortraits()
    cancelPendingPortraits()
    for id, shot in pairs(Shots) do releasePortrait(id, shot) end
end

local portraitQueue = 0
local function preparePortraits()
    portraitQueue=portraitQueue+1
    local token=portraitQueue
    -- Every survivor is shot at once rather than one after another; the head-shot pool easily covers the slot limit.
    for _,char in ipairs(State.characters)do
        if char.id and not Shots[char.id] then
            CreateThread(function()
                if not State.open or token~=portraitQueue or Shots[char.id] then return end
                local ped=Scene.MakePortraitPed(char,function()return State.open and token==portraitQueue end)
                if not ped then return end
                if not State.open or token~=portraitQueue or Shots[char.id] then DeleteEntity(ped);return end
                portrait(char,portraitGeneration,ped,true)
            end)
        end
    end
end

--- Shows the ped for a slot (or a blank one when there are no characters yet).
local function preview(index)
    local generation = cancelPendingPortraits()
    if not State.open then return end
    local char = State.characters[index]
    if char then
        local card=State.cards and State.cards[tostring(char.id)]
        if Scene.SelectSet(card and card.faction)then Scene.ClearSet();Scene.Destroy(true);Scene.Build()end
        if not State.open or generation~=portraitGeneration then return end
        Scene.SpawnPed(char.gender)
        if not State.open or generation ~= portraitGeneration then return end
        Scene.Dress(char)
        Scene.Glide(0.3, 900)
        Scene.BuildSet(State.characters,index)
        -- Card portraits use independent peds so changing selection cannot cancel them.
    else
        -- An empty slot shows a plain freemode ped.
        Scene.SpawnPed('male')
    end
end

function OpenSelect()
    if State.open then return end
    State.open = true
    selectionRun=selectionRun+1
    local run=selectionRun
    local function current()return State.open and selectionRun==run end
    local openedAt=GetGameTimer()
    State.ready=false
    State.loading='Loading survivors…'
    State.characters={};State.cards={}
    send({action='loading',text=State.loading})
    focus(true)
    -- NUI may still be starting on a cold join; resend the same shell until ready.
    CreateThread(function()
        while current()and not State.ready do
            send({action='loading',text=State.loading})
            Wait(500)
        end
    end)
    -- The character list, the private bucket and the stage streaming all start together; only the teleport waits for the bucket.
    local listDone,listOk=false,false
    CreateThread(function()
        local ok,result=pcall(refresh,current)
        listOk=ok and result==true;listDone=true
    end)
    Scene.EndArrival();Scene.SelectSet()
    Scene.Prestream()
    suspendFilter(true)
    local entered=BSB.Await('multichar:sceneEnter',6000)
    -- A newer run (retry) owns the streaming focus by now; only undo it when the selector really closed.
    if not current()then if not State.open then Scene.CancelPrestream()end;return end
    if not entered or not entered.ok then Scene.CancelPrestream();State.loading='Unable to load survivors. Please retry.';return end
    -- Close inspection/inventory cameras before taking ownership of the lineup scene.
    TriggerEvent('bs:ui:opened','multichar')

    local built=Scene.Build()
    if not current()then return end
    if not built then State.loading='Unable to prepare the scene. Please retry.';return end
    applyGrade()
    DoScreenFadeIn(Multichar.Scene.fadeIn)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    focus(true)
    while current()and not listDone do Wait(0)end
    if not current()then return end
    if not listOk then
        State.loading='Unable to load survivors. Please retry.'
        print('^1[BeyondSurvival]^7 character list never arrived - is bs_core running?')
        return
    end
    State.loading='Preparing character preview…'
    preview(1)
    if not current()then return end
    State.ready=true
    send({ action = 'open' })
    -- One F8 line per open, so a slow join can be told apart from a slow stage.
    print(('^2[BeyondSurvival]^7 (multichar) selector ready in %d ms (stage %d ms)'):format(GetGameTimer()-openedAt,Scene.lastStreamMs or -1))
    send({action='selectionOptions',sound=Multichar.Selection.sound and GetResourceKvpInt('selectorMute')~=1,reducedMotion=Multichar.Selection.reducedMotion or GetResourceKvpInt('selectorMotionOff')==1})
    focus(true)
    preparePortraits()
end

-- @param takeover boolean|nil  true when bs_core is taking the player over.
function CloseSelect(handoff)
    if not State.open then return end
    State.open = false
    selectionRun=selectionRun+1
    portraitQueue=portraitQueue+1
    clearGrade()
    suspendFilter(false)
    dropPortraits()
    send({ action = 'close' })
    focus(false)
    Scene.ClearSet()
    Scene.Destroy(handoff)
    TriggerServerEvent('bs:multichar:sceneLeave')
    TriggerEvent('bs:ui:closed','multichar')
end

local function releaseSelectionForSpawn()
    selectionRun=selectionRun+1
    if State.open then CloseSelect(true)end
    Scene.ClearSet();Scene.EndArrival();Scene.Destroy(true)
    send({action='close'});focus(false);ClearTimecycleModifier()
end
AddEventHandler('bs:multichar:spawnRelease',releaseSelectionForSpawn)

-- bs_core broadcasts its hooks as events; this is where control passes over.
AddEventHandler('bs:hook:session:state', function(state)
    if state == 'select' then
        CreateThread(OpenSelect)
    end
end)

-- The character is chosen and bs_core is already swapping the model, teleporting and fading.
AddEventHandler('bs:hook:player:loaded', function()
    CloseSelect(true)
end)

--- Catch-up: if this resource starts (or is restarted) while the player is already sitting at 'select'
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

-- NUI callbacks

-- Every handler that can reach Scene.SpawnPed runs in its own thread: SpawnPed waits on the model loading
RegisterNUICallback('preview', function(data, cb)
    if AppearanceEdit and AppearanceEdit.active then return cb({ ok = true }) end
    CreateThread(function() preview(tonumber(data.index) or 1) end)
    cb({ ok = true })
end)

-- Leaving the creator re-frames the survivor list
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
    -- A missing mode is a UI bug, not a request to reset the camera.
    if type(data.mode) ~= 'string' then return cb({ ok = false }) end
    Scene.SetFocus(data.mode)
    cb({ ok = true })
end)

RegisterNUICallback('play', function(data, cb)
    local id = tonumber(data.id)
    if not id then return cb({ ok = false, error = 'no character' }) end

    -- Safe spawn: announced before the character is selected
    TriggerEvent('bs:core:safeSpawn', data.safeSpawn and true or false)

    CreateThread(function()
        local result = BSB.Await('characters:select', 15000, id)
        if not result or not result.ok then
            return cb({ ok = false, error = (result and result.error) or 'no response' })
        end

        -- PlayerLoaded may precede this callback, even by several seconds. The core owns
        -- the spawn fade; fading here can black out a spawn that has already completed.
        cb({ ok = true })
    end)
end)

RegisterNUICallback('delete', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('characters:delete', 10000, tonumber(data.id))
        if result and result.ok then
            State.characters = result.characters or {}
            send({ action = 'setData', characters = State.characters, cards = State.cards })
        preparePortraits()
            preview(1)
        end
        cb(result or { ok = false })
    end)
end)

--- Live preview while the creator is open: rebuild the ped from the draft.
RegisterNUICallback('draft', function(data, cb)
    cancelPendingPortraits()
    if AppearanceEdit and AppearanceEdit.active then AppearanceEdit.Draft(data.draft); return cb({ ok = true }) end
    CreateThread(function()
        local draft = data.draft or {}

        if data.rebuild or not Scene.ped or not DoesEntityExist(Scene.ped) then
            Scene.SpawnPed(draft.gender or 'male')
        end

        -- Guard: ApplyAppearanceTo falls back to the LOCAL PLAYER's ped when given nil
        if not Scene.ped or not DoesEntityExist(Scene.ped) then
            return cb({ ok = false, error = 'no preview ped' })
        end

        -- Start from a clean ped: the creator reuses the preview ped between drafts
        Scene.StripPed(Scene.ped)

        exports.bs_core:ApplyAppearanceTo(Scene.ped, draft.appearance)

        -- The CLOTHING step sends the outfit it is building; Scene.ApplyLook skips any drawable this model lacks.
        local outfit = draft.outfit
        if type(outfit) == 'table' then Scene.ApplyLook(outfit.components, outfit.props) end

        -- Built hidden, shown once dressed - see the note in Scene.Build.
        Scene.Reveal()

        -- Tell the creator what this model has, so its clothing arrows skip drawables that do not exist.
        local counts, tex = Scene.Report(Scene.ped)
        cb({ ok = true, counts = counts, tex = tex })
    end)
end)

-- Creator lists (factions, kit, clothes, roll tables, identity limits) come from the server
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
        local extra = BSB.Await('multichar:cards', 6000)
        State.cards = (extra and extra.cards) or State.cards
        send({ action = 'setData', characters = State.characters, cards = State.cards })
        preparePortraits()
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

-- Safety net

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

RegisterNUICallback('selectionPreferences',function(data,cb)
    if type(data)=='table'then
        if type(data.sound)=='boolean'then SetResourceKvpInt('selectorMute',data.sound and 0 or 1)end
        if type(data.reducedMotion)=='boolean'then SetResourceKvpInt('selectorMotionOff',data.reducedMotion and 1 or 0)end
    end
    cb({ok=true})
end)
RegisterNUICallback('selectionSound',function(_,cb)
    if State.open and Multichar.Selection.sound and GetResourceKvpInt('selectorMute')~=1 then PlaySoundFrontend(-1,'NAV_UP_DOWN','HUD_FRONTEND_DEFAULT_SOUNDSET',false)end
    cb({ok=true})
end)

-- An F1 change to the grade shows at once on an open selector.
AddEventHandler('bs_config:changed:bs_multichar',function()
    if State.open and State.ready then applyGrade() end
end)

RegisterNUICallback('selectorRetry',function(_,cb)
    if State.open and not State.ready then
        CloseSelect(false)
        CreateThread(OpenSelect)
    end
    cb({ok=true})
end)
