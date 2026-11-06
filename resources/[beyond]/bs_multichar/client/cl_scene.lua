-- bs_multichar - the 3D half of the character screen: a preview ped with a scripted camera.

Scene = { active = false, ped = nil, cam = nil, rotation = 0.0, zoom = 1.0, focus = 'full',
          gender = nil, handsUp = false }

local baseHeading = Multichar.Scene.ped.h

-- Declared up here: SpawnPed and Dress assign to them and the watchdog reads them.
local lastGender = 'male'
local lastCharacter = nil

-- Model helpers

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        print(('^1[BeyondSurvival]^7 (multichar) model "%s" is not valid on this build'):format(tostring(model)))
        return nil
    end
    if not HasModelLoaded(hash) then RequestModel(hash) end
    local waited = 0
    while not HasModelLoaded(hash) and waited < 10000 do
        Wait(10); waited = waited + 10
    end
    if not HasModelLoaded(hash) then
        print(('^1[BeyondSurvival]^7 (multichar) model "%s" would not load'):format(tostring(model)))
        return nil
    end
    return hash
end

local function loadAnim(dict)
    if not dict or HasAnimDictLoaded(dict) then return true end
    if not HasAnimDictLoaded(dict) then RequestAnimDict(dict) end
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 5000 do
        Wait(10); waited = waited + 10
    end
    return HasAnimDictLoaded(dict)
end

-- Camera

-- Framing is measured from the ped's actual soles to crown instead of mixing the entity origin with a head bone
local ANKLE_TO_SOLE = 0.09
local HEAD_BONE_TO_CROWN = 0.13

local function bodySpan(ped, fallbackZ)
    if not ped or not DoesEntityExist(ped) then
        return fallbackZ, fallbackZ + 1.78
    end

    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local lf   = GetPedBoneCoords(ped, 14201, 0.0, 0.0, 0.0)
    local rf   = GetPedBoneCoords(ped, 52301, 0.0, 0.0, 0.0)

    if head and lf and rf then
        local footZ = math.min(lf.z, rf.z) - ANKLE_TO_SOLE
        local headZ = head.z + HEAD_BONE_TO_CROWN

        -- A person is 1.2m to 2.4m tall. Anything else is a skeleton that has not loaded; framing on it would put the camera in a wall.
        local span = headZ - footZ
        if span > 1.2 and span < 2.4 then return footZ, headZ end
    end

    return fallbackZ, fallbackZ + 1.78
end

-- Camera motion: a short ease-in when the scene opens or the survivor changes, then a slow drift of a few centimetres.
local motion = { from = 0, start = 0, ms = 0 }

local function motionOn()
    local cfg = Multichar.Selection or {}
    return cfg.cameraMotion ~= false and not cfg.reducedMotion and GetResourceKvpInt('selectorMotionOff') ~= 1
end

-- 0 at rest, up to 1 at the start of an ease-in.
local function easeLeft()
    if motion.ms <= 0 then return 0.0 end
    local t = (GetGameTimer() - motion.start) / motion.ms
    if t >= 1.0 then motion.ms = 0; return 0.0 end
    local k = 1.0 - t
    return motion.from * k * k * k
end

local function applyCam()
    if not Scene.cam then return end

    local focus = Multichar.Settings.focus[Scene.focus] or Multichar.Settings.focus.full

    -- Uses the configured x/y, not GetEntityCoords(Scene.ped): if the ped is missing for a frame it returns 0,0,0
    local s = Multichar.Scene.ped

    local footZ, headZ = bodySpan(Scene.ped, s.z)
    local height = headZ - footZ

    -- The camera does not orbit. It sits at a fixed spot due south and the ped turns, so the character always faces the viewer.
    local dist = (focus.offset.y or 2.4) * Scene.zoom
    local fov  = focus.fov or 34.0

    local drift, rise = 0.0, 0.0
    if motionOn() then
        local left = easeLeft()
        dist = dist * (1.0 + 0.16 * left)
        rise = 0.10 * left
        drift = math.sin(GetGameTimer() / 1600.0) * 0.035
    end

    -- Clamped to the room (Multichar.Scene.maxCamDistance), otherwise the camera backs out of the lineup room.
    local ceiling = Multichar.Scene.maxCamDistance
    if ceiling and dist > ceiling then dist = ceiling end

    -- Parallel shift as a fraction of the visible half-width. offset.x moves the camera and its look-at point
    local halfHeight = dist * math.tan(math.rad(fov * 0.5))

    local aspect = 16.0 / 9.0
    local okAspect, measuredAspect = pcall(GetAspectRatio, false)
    if okAspect and type(measuredAspect) == 'number'
       and measuredAspect > 0.5 and measuredAspect < 4.0 then
        aspect = measuredAspect
    end

    local lateral = (focus.offset.x or 0.0) * halfHeight * aspect
    local camLateral = lateral + drift

    -- Fractions of the measured body from the soles up: 0 is the floor under the boots, 1 is the crown of the head.
    local camZ  = footZ + height * (focus.offset.z or 0.50) + rise
    local lookZ = footZ + height * (focus.look.z or 0.50)

    local rad=math.rad(Scene.cameraHeading or 0)
    SetCamCoord(Scene.cam,
        s.x+camLateral*math.cos(rad)+dist*math.sin(rad),
        s.y+camLateral*math.sin(rad)-dist*math.cos(rad),camZ)

    PointCamAtCoord(Scene.cam,
        s.x+lateral*math.cos(rad)+(focus.look.x or 0.0),
        s.y+lateral*math.sin(rad)+(focus.look.y or 0.0),
        lookZ)

    SetCamFov(Scene.cam, fov)

    -- Debug output: one F8 line per framing change naming the shot, the measured body and the camera position.
    if Scene.debugCam and Scene.debugCamOnce then
        Scene.debugCamOnce = false
        print(('^5[BeyondSurvival]^7 (multichar) %s: foot=%.2f head=%.2f (%.2fm) cam z=%.2f look z=%.2f d=%.2f fov=%.0f')
            :format(Scene.focus, footZ, headZ, height, camZ, lookZ, dist, fov))
    end
end

-- Starts an ease-in of the given strength (1 = opening shot, smaller for a survivor swap).
function Scene.Glide(strength, ms)
    if not motionOn() then motion.ms = 0; return end
    motion.from = math.max(easeLeft(), strength or 1.0)
    motion.start = GetGameTimer()
    motion.ms = ms or 1400
end

-- Drives the camera every frame while it moves; idle otherwise.
CreateThread(function()
    while true do
        if Scene.active and Scene.cam and motionOn() then
            applyCam()
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- /camdebug - print the framing numbers on every camera change.
RegisterCommand('camdebug', function()
    Scene.debugCam = not Scene.debugCam
    Scene.debugCamOnce = Scene.debugCam
    print(('^5[BeyondSurvival]^7 (multichar) camera debug %s')
        :format(Scene.debugCam and 'ON' or 'OFF'))
    if Scene.debugCam then applyCam() end
end, false)

-- Heading 180 is due south, so at rotation 0 the ped faces the camera.
local function applyPedHeading()
    if not Scene.ped or not DoesEntityExist(Scene.ped) then return end
    SetEntityHeading(Scene.ped, ((Multichar.Scene.ped.h or 180.0) + Scene.rotation) % 360.0)
end

-- Turns the character only (positive = to their left). The camera is fixed, see applyCam.
function Scene.Rotate(delta)
    Scene.rotation = (Scene.rotation + (tonumber(delta) or 0)) % 360.0
    applyPedHeading()
end

function Scene.SetZoom(delta)
    Scene.zoom = math.max(Multichar.Scene.zoomMin,
                 math.min(Multichar.Scene.zoomMax, Scene.zoom + (tonumber(delta) or 0)))
    Scene.debugCamOnce = Scene.debugCam
    applyCam()
end

function Scene.SetFocus(name)
    Scene.focus = Multichar.Settings.focus[name] and name or 'full'
    Scene.debugCamOnce = Scene.debugCam
    Scene.Glide(0.35, 700)
    applyCam()
end

-- Build / teardown

local function modelFor(gender)
    local models = exports.bs_core:GetConfig('Character.pedModels',
        { male = 'mp_m_freemode_01', female = 'mp_f_freemode_01' })
    return models[gender] or models.male or 'mp_m_freemode_01'
end

-- Starts streaming the stage and the preview assets while the server is still answering. Nothing moves the player here.
function Scene.Prestream()
    local s = Multichar.Scene.ped
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(s.x, s.y, s.z)
    if not IsNewLoadSceneActive() then NewLoadSceneStart(s.x, s.y, s.z, 0.0, 0.0, 0.0, 50.0, 0) end
    for _, gender in ipairs({ 'male', 'female' }) do
        local hash = GetHashKey(modelFor(gender))
        if IsModelInCdimage(hash) then RequestModel(hash) end
    end
    local idle = Multichar.Settings.idleAnim
    if idle and idle.dict then RequestAnimDict(idle.dict) end
end

-- Undoes Prestream when the scene is never built (bucket refused, selector closed).
function Scene.CancelPrestream()
    if Scene.active then return end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    ClearFocus()
end

-- Spawns the preview ped and camera. Safe to call repeatedly.
function Scene.Build()
    if Scene.active then return true end
    -- Bumped by Destroy: a close during the waits below must not leave a live scene behind.
    local gen = Scene.gen or 0

    local s = Multichar.Scene
    TriggerEvent('bs:world:selectionWeather',true,{weather=s.weather,hour=s.hour,minute=s.minute})

    -- Park the player's own ped at the scene and hide it; the camera sees the preview ped.
    local playerPed = PlayerPedId()

    -- Two-step teleport: going straight to z = -98.5 drops you into a room that has not loaded. Standing at z = 30 first makes the engine cache the column. Same technique as BigDaddy-CharacterManager.
    local pre = s.precache or { x = s.ped.x, y = s.ped.y, z = 30.0 }

    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)
    SetEntityInvincible(playerPed, true)
    SetPlayerControl(PlayerId(), false, 0)

    -- The cache-in step only matters for the shell under the map; outdoor scenes go straight to the stage.
    if not Scene.outdoor then
        RequestCollisionAtCoord(pre.x, pre.y, pre.z)
        SetEntityCoordsNoOffset(playerPed, pre.x, pre.y, pre.z, false, false, false)
        local untilAt = GetGameTimer() + 600
        repeat Wait(50) until HasCollisionLoadedAroundEntity(playerPed) or GetGameTimer() >= untilAt
    end

    RequestCollisionAtCoord(s.ped.x, s.ped.y, s.ped.z)
    SetEntityCoordsNoOffset(playerPed, s.ped.x, s.ped.y, s.ped.z, false, false, false)

    -- Force the world to stream around the scene, not the player. Prestream may already have started this.
    SetFocusPosAndVel(s.ped.x, s.ped.y, s.ped.z, 0.0, 0.0, 0.0)
    if not IsNewLoadSceneActive() then NewLoadSceneStart(s.ped.x, s.ped.y, s.ped.z, 0.0, 0.0, 0.0, 50.0, 0) end

    -- Collision is required; the wider scene gets a short grace after it and keeps streaming behind the camera (the watchdog pins the focus).
    -- Requested every two seconds, not every 50ms: each streaming request takes a script-resource slot.
    local startAt = GetGameTimer()
    local hardStop = startAt + 5000
    local nextAsk, collisionAt = 0, nil

    while GetGameTimer() < hardStop do
        local now = GetGameTimer()
        if now >= nextAsk then
            RequestCollisionAtCoord(s.ped.x, s.ped.y, s.ped.z)
            nextAsk = now + 2000
        end
        if HasCollisionLoadedAroundEntity(playerPed) then
            collisionAt = collisionAt or now
            if not IsNewLoadSceneActive() or IsNewLoadSceneLoaded() or now - collisionAt >= 1500 then break end
        end
        Wait(50)
    end
    NewLoadSceneStop()
    Scene.lastStreamMs = GetGameTimer() - startAt

    if gen ~= (Scene.gen or 0) then
        ClearFocus()
        return false
    end

    if Scene.outdoor and Scene.ResolveOutdoorSet then Scene.ResolveOutdoorSet()end
    if gen ~= (Scene.gen or 0)then ClearFocus();return false end
    Scene.rotation = 0.0
    Scene.zoom = 1.0
    Scene.focus = 'full'
    Scene.rebuilds = 0
    Scene.nextRebuild = 0

    -- Framed before it is rendered: the camera starts from a default guess and is re-aimed on the first applyCam
    Scene.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        s.ped.x, s.ped.y - (s.cam.offset and s.cam.offset.y or 2.75), s.ped.z + 0.89,
        0.0, 0.0, 0.0, s.cam.fov or 50.0, false, 0)
    SetCamActive(Scene.cam, true)
    Scene.Glide(1.0, 1800)
    applyCam()
    RenderScriptCams(true, false, 0, true, true)

    -- Local-only mood. The server's weather is untouched.
    SetOverrideWeather(s.weather or 'OVERCAST')
    NetworkOverrideClockTime(s.hour or 21, s.minute or 40, 0)

    -- bs_world turns every map light off, which leaves a black room
    TriggerEvent('bs:world:blackoutHold', true)

    Scene.active = true
    return true
end


-- Hands-up pose for checking clothing clipping. Each candidate is checked for the clip, since a dict can load without containing it.
local HANDS_UP = {
    { dict = 'random@mugging3',     clip = 'handsup_standing_base' },
    { dict = 'missminuteman_1ig_2', clip = 'handsup_base' },
}

-- Never holds up the preview: when the dictionary is not in memory yet the pose starts once it arrives.
local function playIdle(ped)
    local anim = Multichar.Settings.idleAnim
    if not anim or not anim.dict then return end
    if HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, 2.0, -1, 1, 0, false, false, false)
        return
    end
    CreateThread(function()
        if loadAnim(anim.dict) and DoesEntityExist(ped) and Scene.ped == ped and not Scene.handsUp then
            TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, 2.0, -1, 1, 0, false, false, false)
        end
    end)
end

local function playHandsUp(ped)
    for _, a in ipairs(HANDS_UP) do
        if loadAnim(a.dict) and GetAnimDuration(a.dict, a.clip) > 0.0 then
            -- 49 = loop + upper body + keep playing
            TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, -1, 49, 0, false, false, false)
            return true
        end
    end
    return false
end

function Scene.SetHandsUp(on)
    Scene.handsUp = on and true or false
    local ped = Scene.ped
    if not ped or not DoesEntityExist(ped) then return end
    ClearPedTasks(ped)
    if Scene.handsUp then
        if not playHandsUp(ped) then Scene.handsUp = false; playIdle(ped) end
    else
        playIdle(ped)
    end
end

function Scene.SpawnPed(gender, force)
    gender = gender or 'male'
    -- A late preview after the scene closed would re-pin streaming to the stage with nothing to undo it.
    if not Scene.active then return nil end
    lastGender = gender

    -- Re-dressing an existing ped is instant, respawning pops. Only rebuild when the model has to change.
    if not force and Scene.gender == gender and Scene.ped and DoesEntityExist(Scene.ped) then
        SetPedDefaultComponentVariation(Scene.ped)
        applyPedHeading()
        applyCam()
        return Scene.ped
    end

    -- Fallback chain: an empty screen looks like a crash, so if the configured model will not load, use any ped.
    local model, hash
    for _, candidate in ipairs({ modelFor(gender), 'mp_m_freemode_01', 'a_m_m_farmer_01' }) do
        hash = loadModel(candidate)
        if hash then model = candidate break end
    end

    -- The model load waits, the player may have spawned meanwhile.
    if not Scene.active then
        if hash then SetModelAsNoLongerNeeded(hash) end
        return nil
    end

    if not hash then
        print('^1[BeyondSurvival]^7 (multichar) no preview ped would load - the screen will be empty')
        return nil
    end
    if model ~= modelFor(gender) then
        print(('^3[BeyondSurvival]^7 (multichar) fell back to "%s" for the preview'):format(model))
    end

    if Scene.ped and DoesEntityExist(Scene.ped) then
        DeleteEntity(Scene.ped)
        Scene.ped = nil
    end

    local s = Multichar.Scene.ped

    -- No ground probe: GetGroundZFor_3dCoord in this interior returns the first collision hit
    local spawnZ = s.z

    Scene.ped = CreatePed(4, hash, s.x, s.y, spawnZ, s.h or 180.0, false, true)
    Scene.gender = gender
    SetModelAsNoLongerNeeded(hash)

    -- Hidden until finished: a freemode ped has no head until head-blend data is written
    SetEntityVisible(Scene.ped, false, false)

    -- Default face applied immediately.
    pcall(SetPedHeadBlendData, Scene.ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)

    SetEntityInvincible(Scene.ped, true)
    FreezeEntityPosition(Scene.ped, true)
    SetBlockingOfNonTemporaryEvents(Scene.ped, true)
    SetPedCanRagdoll(Scene.ped, false)
    SetPedDefaultComponentVariation(Scene.ped)

    -- Do not delete this ped. bs_world sweeps non-player peds once a second; this tag is honoured by every sweep in the project.
    local state = Entity(Scene.ped).state
    if state then state:set('bsProtected', true, false) end

    if not (Scene.handsUp and playHandsUp(Scene.ped)) then playIdle(Scene.ped) end

    -- Lit and not culled. Visibility is restored later by Scene.Reveal() once the ped is dressed.
    SetEntityAlpha(Scene.ped, 255, false)
    SetPedAoBlobRendering(Scene.ped, false)
    SetEntityLodDist(Scene.ped, 1000)

    -- Do not call ClearFocus() here.
    SetFocusPosAndVel(s.x, s.y, spawnZ, 0.0, 0.0, 0.0)
    SetEntityCoordsNoOffset(Scene.ped, s.x, s.y, spawnZ, false, false, false)
    if ClearRoomForEntity then pcall(ClearRoomForEntity, Scene.ped) end

    applyPedHeading()
    applyCam()

    -- Log whether the ped actually rendered, so an empty creator can be diagnosed.
    local at = GetEntityCoords(Scene.ped)
    print(('^2[BeyondSurvival]^7 (multichar) preview ped %s at %.2f %.2f %.2f (visible=%s, interior=%d)')
        :format(model, at.x, at.y, at.z,
                tostring(IsEntityVisible(Scene.ped)), GetInteriorFromEntity(Scene.ped)))

    return Scene.ped
end

-- Show the ped now that it is finished.
-- A fresh survivor fades in over a quarter second; re-dressing the creator draft stays instant.
local revealToken = 0
function Scene.Reveal(fade)
    local ped = Scene.ped
    if not ped or not DoesEntityExist(ped) then return end
    revealToken = revealToken + 1
    local token = revealToken
    if not fade or not motionOn() then
        ResetEntityAlpha(ped)
        SetEntityVisible(ped, true, false)
        return
    end
    SetEntityAlpha(ped, 0, false)
    SetEntityVisible(ped, true, false)
    CreateThread(function()
        local start = GetGameTimer()
        while token == revealToken and DoesEntityExist(ped) do
            local t = (GetGameTimer() - start) / 260.0
            if t >= 1.0 then break end
            SetEntityAlpha(ped, math.floor(255 * t), false)
            Wait(0)
        end
        if DoesEntityExist(ped) then ResetEntityAlpha(ped) end
    end)
end

-- Clear everything the previous character left behind (weapon, props like goggles).
local function stripPed(ped)
    if not ped or not DoesEntityExist(ped) then return end

    RemoveAllPedWeapons(ped, true)

    -- All prop slots on freemode models: hat, glasses, ears, mouth, left hand, right hand, watch, bracelet.
    if not pcall(ClearAllPedProps, ped) then
        for slot = 0, 7 do pcall(ClearPedProp, ped, slot) end
    end
end

Scene.StripPed = stripPed

-- Dresses the preview ped: face, clothes, and the weapon it last held.
function Scene.Dress(character)
    lastCharacter = character
    if not Scene.ped or not DoesEntityExist(Scene.ped) then return end

    -- Nothing from the last character survives into this one.
    stripPed(Scene.ped)

    exports.bs_core:ApplyAppearanceTo(Scene.ped, character.appearance)

    if character.outfit then
        exports.bs_core:ApplyOutfit(Scene.ped, character.outfit)
    end

    -- Only a saved character gets a weapon.
    local saved = character.id ~= nil

    if saved and Multichar.Settings.showLastWeapon and character.lastWeapon then
        GiveWeaponToPed(Scene.ped, character.lastWeapon, 1, false, true)
        SetCurrentPedWeapon(Scene.ped, character.lastWeapon, true)
    end

    Scene.Reveal(character.id ~= nil)
end

-- Drawable and texture counts of what the preview ped has / wears, for the creator's clothing step (keys c<component>, p<prop>).
function Scene.Report(ped)
    local counts, tex = {}, {}
    if not ped or not DoesEntityExist(ped) then return counts, tex end
    for _, slot in ipairs({ 3, 4, 6, 7, 8, 11 }) do
        counts['c' .. slot] = GetNumberOfPedDrawableVariations(ped, slot)
        tex['c' .. slot] = GetNumberOfPedTextureVariations(ped, slot, GetPedDrawableVariation(ped, slot))
    end
    for _, slot in ipairs({ 0, 1 }) do
        counts['p' .. slot] = GetNumberOfPedPropDrawableVariations(ped, slot)
        local idx = GetPedPropIndex(ped, slot)
        if idx >= 0 then tex['p' .. slot] = GetNumberOfPedPropTextureVariations(ped, slot, idx) end
    end
    return counts, tex
end

-- Back to the survivor list.
function Scene.ResetView()
    if Scene.handsUp then CreateThread(function() Scene.SetHandsUp(false) end) end
    Scene.rotation = 0.0
    Scene.zoom = 1.0
    Scene.focus = 'full'
    applyPedHeading()
    applyCam()
end

-- Validated dressing. "CPed::SetVariation: Invalid variation" in the console means a drawable that does not

-- Out-of-range drawables are rejected, not clamped. Clamping to the last item gave unrelated clothes on the other model.
local reported = {}

local function safeComponent(ped, slot, drawable, texture)
    if slot < 0 or slot > 11 then return nil end
    local count = GetNumberOfPedDrawableVariations(ped, slot)
    if count <= 0 then return nil end

    drawable = math.floor(drawable or 0)

    if drawable < 0 or drawable >= count then
        local key = ('c%d:%d'):format(slot, drawable)
        if not reported[key] then
            reported[key] = true
            print(('^3[BeyondSurvival]^7 (multichar) a preset asked for component %d drawable %d, but this model only has %d (0-%d). Left as-is rather than substituting an unrelated garment.')
                :format(slot, drawable, count, count - 1))
        end
        return nil
    end

    local textures = GetNumberOfPedTextureVariations(ped, slot, drawable)
    texture = math.max(0, math.min(math.floor(texture or 0), math.max(0, textures - 1)))

    return drawable, texture
end

local function safeProp(ped, slot, drawable, texture)
    if (drawable or -1) < 0 or slot < 0 or slot > 7 then return -1, 0 end

    local count = GetNumberOfPedPropDrawableVariations(ped, slot)
    if count <= 0 then return -1, 0 end

    -- Same rule as components: an out-of-range hat is no hat. -1 clears the slot, the correct "nothing" for a prop.
    drawable = math.floor(drawable)
    if drawable < 0 or drawable >= count then
        local key = ('p%d:%d'):format(slot, drawable)
        if not reported[key] then
            reported[key] = true
            print(('^3[BeyondSurvival]^7 (multichar) a preset asked for prop %d drawable %d, but this model only has %d. Left empty.')
                :format(slot, drawable, count))
        end
        return -1, 0
    end

    local textures = GetNumberOfPedPropTextureVariations(ped, slot, drawable)
    texture = math.max(0, math.min(math.floor(texture or 0), math.max(0, textures - 1)))

    return drawable, texture
end

Scene.SafeComponent = safeComponent
Scene.SafeProp = safeProp

-- Applies raw component/prop tables (used live by the creator's presets).
function Scene.ApplyLook(components, props)
    local ped = Scene.ped
    if not ped or not DoesEntityExist(ped) then return end

    for id, v in pairs(components or {}) do
        local slot = tonumber(id)
        if slot then
            local drawable, texture = safeComponent(ped, slot, v.drawable, v.texture)
            if drawable then
                SetPedComponentVariation(ped, slot, drawable, texture, v.palette or 2)
            end
        end
    end

    for id, v in pairs(props or {}) do
        local slot = tonumber(id)
        if slot and slot >= 0 and slot <= 7 then
            local drawable, texture = safeProp(ped, slot, v.drawable, v.texture)
            if drawable < 0 then
                ClearPedProp(ped, slot)
            else
                SetPedPropIndex(ped, slot, drawable, texture, true)
            end
        end
    end
end

-- Pass true when bs_core is about to respawn the player (model swap, teleport, fade).
function Scene.Destroy(handoff)
    Scene.gen = (Scene.gen or 0) + 1
    TriggerEvent('bs:world:selectionWeather',false)
    if not Scene.active then
        ClearFocus()
        return
    end

    if Scene.ped and DoesEntityExist(Scene.ped) then DeleteEntity(Scene.ped) end
    Scene.ped = nil
    Scene.gender = nil

    if Scene.cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(Scene.cam, true)
        Scene.cam = nil
    end

    ClearOverrideWeather()
    NetworkClearClockTimeOverride()

    -- The exception ends with the scene.
    TriggerEvent('bs:world:blackoutHold', false)

    -- Unconditional and before the hand-off check: leaving streaming focus on the stage stops the world loading textures afterwards.
    ClearFocus()
    Scene.active = false

    if handoff then return end

    -- Only when nothing else is taking over: restore the player.
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true, false)
    SetEntityInvincible(playerPed, false)
    SetPlayerControl(PlayerId(), true, 0)
end

-- Scene lighting. bs_world turns map lights off, which left the preview in flat grey.

CreateThread(function()
    while true do
        if Scene.active and Scene.ped and DoesEntityExist(Scene.ped) then
            Wait(0)

            local at = GetEntityCoords(Scene.ped)
            local L = Multichar.Scene.lights or {}

            if L.enabled ~= false then
                for _, key in ipairs({ 'key', 'rim', 'bounce' }) do
                    local light = L[key]
                    if light then
                        -- Offsets are written for a camera due south; turn them with the scene's camera heading.
                        local rad = math.rad(Scene.cameraHeading or 0)
                        local lx, ly = light.x or 0.0, light.y or 0.0
                        DrawLightWithRange(
                            at.x + lx * math.cos(rad) - ly * math.sin(rad),
                            at.y + lx * math.sin(rad) + ly * math.cos(rad),
                            at.z + (light.z or 0.0),
                            light.r or 255, light.g or 255, light.b or 255,
                            light.range or 5.0, light.intensity or 2.0)
                    end
                end
            end
        else
            Wait(300)
        end
    end
end)

-- Watchdog: the world can unstream (grey void) or the preview ped can vanish.

CreateThread(function()
    while true do
        Wait(500)

        if Scene.active then
            local s = Multichar.Scene.ped

            -- Keep streaming pinned to the stage, not the player.
            SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)

            -- Late cleanup from a previous menu can deactivate scripted rendering.
            if Scene.cam and DoesCamExist(Scene.cam) and GetRenderingCam()~=Scene.cam then
                SetCamActive(Scene.cam,true)
                RenderScriptCams(true,false,0,true,true)
            end

            if IsScreenFadedOut() then DoScreenFadeIn(250)end

            -- Re-aim: the head bone is not measurable on the frame the ped is created
            if Scene.ped and DoesEntityExist(Scene.ped) and not motionOn() then applyCam() end

            local now = GetGameTimer()

            if (not Scene.ped or not DoesEntityExist(Scene.ped))
               and now >= (Scene.nextRebuild or 0) then

                -- Rate limited: a rebuild that fails for the same reason must not retry twice a second.
                Scene.rebuilds = (Scene.rebuilds or 0) + 1
                Scene.nextRebuild = now + 2500

                if Scene.rebuilds <= 3 then
                    print(('^3[BeyondSurvival]^7 (multichar) preview ped gone - rebuilding (%d/3)')
                        :format(Scene.rebuilds))
                    Scene.SpawnPed(lastGender, true)
                    if lastCharacter then Scene.Dress(lastCharacter) end
                elseif Scene.rebuilds == 4 then
                    print('^1[BeyondSurvival]^7 (multichar) preview ped will not stay - giving up rather than flickering')
                end
            end
        end
    end
end)

-- Rotation and zoom come from the NUI (buttons, drag, keyboard) because the game never sees the mouse while the

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Scene.Destroy() end
end)

-- Card snapshots do not touch the selected ped or the character creator.
function Scene.MakePortraitPed(character,current)
    local hash=GetHashKey(modelFor(character.gender or 'male'))
    RequestModel(hash)
    local deadline=GetGameTimer()+2500
    while current() and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(25)end
    if not current() or not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);return nil end
    local at=Multichar.Scene.ped
    local ped=CreatePed(4,hash,at.x,at.y,at.z+12,180.0,false,false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped==0 then return nil end
    SetEntityAsMissionEntity(ped,true,true)
    Entity(ped).state:set('bsProtected',true,false)
    SetEntityCollision(ped,false,false);FreezeEntityPosition(ped,true)
    SetEntityInvincible(ped,true);SetBlockingOfNonTemporaryEvents(ped,true)
    SetPedDefaultComponentVariation(ped)
    local ok=pcall(function()
        exports.bs_core:ApplyAppearanceTo(ped,character.appearance)
        if character.outfit then exports.bs_core:ApplyOutfit(ped,character.outfit)end
    end)
    if not ok then DeleteEntity(ped);return nil end
    return ped
end
