-- bs_multichar - the 3D half of the character screen: a preview ped with a scripted camera. The player's own ped is hidden elsewhere, so sliders restyle the preview without touching the character.

Scene = { active = false, ped = nil, cam = nil, rotation = 0.0, zoom = 1.0, focus = 'full',
          gender = nil, handsUp = false }

local baseHeading = Multichar.Scene.ped.h

-- Declared up here on purpose: SpawnPed and Dress assign to them and the watchdog reads them. Declaring lower would create globals and a shadowed copy.
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

-- Framing is measured from the ped's actual soles to crown instead of mixing the entity origin with a head bone, which can disagree about where zero is.
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

local function applyCam()
    if not Scene.cam then return end

    local focus = Multichar.Settings.focus[Scene.focus] or Multichar.Settings.focus.full

    -- Uses the configured x/y, not GetEntityCoords(Scene.ped): if the ped is missing for a frame it returns 0,0,0 and the camera jumps to the map origin. The stage never moves.
    local s = Multichar.Scene.ped

    local footZ, headZ = bodySpan(Scene.ped, s.z)
    local height = headZ - footZ

    -- The camera does not orbit. It sits at a fixed spot due south and the ped turns, so the character always faces the viewer.
    local dist = (focus.offset.y or 2.4) * Scene.zoom
    local fov  = focus.fov or 34.0

    -- Clamped to the room (Multichar.Scene.maxCamDistance), otherwise the camera backs out of the lineup room. The distance is clamped rather than the zoom, so zooming back in works right away.
    local ceiling = Multichar.Scene.maxCamDistance
    if ceiling and dist > ceiling then dist = ceiling end

    -- Parallel shift as a fraction of the visible half-width. offset.x moves the camera and its look-at point together, so the character stays viewed dead-on and sits off-centre, clear of the survivor list.
    local halfHeight = dist * math.tan(math.rad(fov * 0.5))

    local aspect = 16.0 / 9.0
    local okAspect, measuredAspect = pcall(GetAspectRatio, false)
    if okAspect and type(measuredAspect) == 'number'
       and measuredAspect > 0.5 and measuredAspect < 4.0 then
        aspect = measuredAspect
    end

    local lateral = (focus.offset.x or 0.0) * halfHeight * aspect

    -- Fractions of the measured body from the soles up: 0 is the floor under the boots, 1 is the crown of the head.
    local camZ  = footZ + height * (focus.offset.z or 0.50)
    local lookZ = footZ + height * (focus.look.z or 0.50)

    SetCamCoord(Scene.cam,
        s.x + lateral,
        s.y - dist,
        camZ)

    PointCamAtCoord(Scene.cam,
        s.x + lateral + (focus.look.x or 0.0),
        s.y + (focus.look.y or 0.0),
        lookZ)

    SetCamFov(Scene.cam, fov)

    -- Debug output: one F8 line per framing change naming the shot, the measured body and the camera position.
    if Scene.debugCam then
        print(('^5[BeyondSurvival]^7 (multichar) %s: foot=%.2f head=%.2f (%.2fm) cam z=%.2f look z=%.2f d=%.2f fov=%.0f')
            :format(Scene.focus, footZ, headZ, height, camZ, lookZ, dist, fov))
    end
end

-- /camdebug - print the framing numbers on every camera change.
RegisterCommand('camdebug', function()
    Scene.debugCam = not Scene.debugCam
    print(('^5[BeyondSurvival]^7 (multichar) camera debug %s')
        :format(Scene.debugCam and 'ON' or 'OFF'))
    if Scene.debugCam then applyCam() end
end, false)

-- Heading 180 is due south, so at rotation 0 the ped faces the camera.
local function applyPedHeading()
    if not Scene.ped or not DoesEntityExist(Scene.ped) then return end
    SetEntityHeading(Scene.ped, (180.0 + Scene.rotation) % 360.0)
end

-- Turns the character only (positive = to their left). The camera is fixed, see applyCam.
function Scene.Rotate(delta)
    Scene.rotation = (Scene.rotation + (tonumber(delta) or 0)) % 360.0
    applyPedHeading()
end

function Scene.SetZoom(delta)
    Scene.zoom = math.max(Multichar.Scene.zoomMin,
                 math.min(Multichar.Scene.zoomMax, Scene.zoom + (tonumber(delta) or 0)))
    applyCam()
end

function Scene.SetFocus(name)
    Scene.focus = Multichar.Settings.focus[name] and name or 'full'
    applyCam()
end

-- Build / teardown

-- Spawns the preview ped and camera. Safe to call repeatedly.
function Scene.Build()
    if Scene.active then return true end

    local s = Multichar.Scene

    -- Park the player's own ped at the scene and hide it; the camera sees the preview ped. Collision is loaded first so the ped does not fall.
    local playerPed = PlayerPedId()

    -- Two-step teleport: going straight to z = -98.5 drops you into a room that has not loaded. Standing at z = 30 first makes the engine cache the column. Same technique as BigDaddy-CharacterManager.
    local pre = s.precache or { x = s.ped.x, y = s.ped.y, z = 30.0 }

    RequestCollisionAtCoord(pre.x, pre.y, pre.z)
    SetEntityCoordsNoOffset(playerPed, pre.x, pre.y, pre.z, false, false, false)
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)
    SetEntityInvincible(playerPed, true)
    SetPlayerControl(PlayerId(), false, 0)

    Wait(600)

    RequestCollisionAtCoord(s.ped.x, s.ped.y, s.ped.z)
    SetEntityCoordsNoOffset(playerPed, s.ped.x, s.ped.y, s.ped.z, false, false, false)
    Wait(300)

    -- Force the world to stream around the scene, not the player. With a scripted camera the engine keeps streaming around the player ped, which can leave a grey LOD void.
    SetFocusPosAndVel(s.ped.x, s.ped.y, s.ped.z, 0.0, 0.0, 0.0)
    NewLoadSceneStart(s.ped.x, s.ped.y, s.ped.z, 0.0, 0.0, 0.0, 50.0, 0)

    -- Requested every two seconds, not every 50ms: each streaming request takes a script-resource slot and the pool is 256 per resource (see the note in bs_core/client/cl_spawn.lua).
    local waited = 0
    local nextAsk = 0

    while waited < 8000 do
        if waited >= nextAsk then
            RequestCollisionAtCoord(s.ped.x, s.ped.y, s.ped.z)
            nextAsk = waited + 2000
        end

        if HasCollisionLoadedAroundEntity(playerPed) and not IsNewLoadSceneActive() then break end
        Wait(50); waited = waited + 50
    end
    NewLoadSceneStop()

    Scene.rotation = 0.0
    Scene.zoom = 1.0
    Scene.focus = 'full'
    Scene.rebuilds = 0
    Scene.nextRebuild = 0

    -- Framed before it is rendered: the camera starts from a default guess and is re-aimed on the first applyCam once a ped exists to measure, so set the initial frame from the default height.
    Scene.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        s.ped.x, s.ped.y - (s.cam.offset and s.cam.offset.y or 2.75), s.ped.z + 0.89,
        0.0, 0.0, 0.0, s.cam.fov or 50.0, false, 0)
    SetCamActive(Scene.cam, true)
    applyCam()
    RenderScriptCams(true, false, 0, true, true)

    -- Local-only mood. The server's weather is untouched.
    SetOverrideWeather(s.weather or 'OVERCAST')
    NetworkOverrideClockTime(s.hour or 21, s.minute or 40, 0)

    -- bs_world turns every map light off, which leaves a black room, so the blackout is lifted while the character screen is up and restored on close. The only exception in the project.
    TriggerEvent('bs:world:blackoutHold', true)

    Scene.active = true
    return true
end

-- Creates (or replaces) the preview ped for a gender. Uses the same models the player spawns as; bs_core owns that list, so read it instead of hardcoding.
local function modelFor(gender)
    local models = exports.bs_core:GetConfig('Character.pedModels',
        { male = 'mp_m_freemode_01', female = 'mp_f_freemode_01' })
    return models[gender] or models.male or 'mp_m_freemode_01'
end

-- Hands-up pose for checking clothing clipping. Each candidate is checked for the clip, since a dict can load without containing it.
local HANDS_UP = {
    { dict = 'random@mugging3',     clip = 'handsup_standing_base' },
    { dict = 'missminuteman_1ig_2', clip = 'handsup_base' },
}

local function playIdle(ped)
    local anim = Multichar.Settings.idleAnim
    if anim and loadAnim(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, 2.0, -1, 1, 0, false, false, false)
    end
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

    -- No ground probe: GetGroundZFor_3dCoord in this interior returns the first collision hit (worktop, sill, bath rim) instead of the floor, which left the character standing on furniture.
    local spawnZ = s.z

    Scene.ped = CreatePed(4, hash, s.x, s.y, spawnZ, 180.0, false, true)
    Scene.gender = gender
    SetModelAsNoLongerNeeded(hash)

    -- Hidden until finished: a freemode ped has no head until head-blend data is written, so showing it straight from CreatePed gives a headless body for a few seconds. Scene.Reveal() shows it once dressed.
    SetEntityVisible(Scene.ped, false, false)

    -- Default face applied immediately. A freemode ped with no head blend stays headless; zeroes give a neutral base face that ApplyAppearanceTo then overwrites.
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

    -- Do not call ClearFocus() here. Streaming focus must stay pinned to the stage; ClearFocus returns it to the player ped, the engine can then cull the preview ped, and the watchdog rebuilds it in a loop.
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

-- Show the ped now that it is finished. Pairs with SetEntityVisible(false) in Build; nothing else turns visibility on, so a preview ped is only visible after it has a face and clothes.
function Scene.Reveal()
    if Scene.ped and DoesEntityExist(Scene.ped) then
        SetEntityVisible(Scene.ped, true, false)
    end
end

-- Clear everything the previous character left behind (weapon, props like goggles). The preview ped is rebuilt per character, but Dress only added to it.
local function stripPed(ped)
    if not ped or not DoesEntityExist(ped) then return end

    RemoveAllPedWeapons(ped, true)

    -- All prop slots on freemode models: hat, glasses, ears, mouth, left hand, right hand, watch, bracelet. ClearAllPedProps covers them on current builds; the loop is a free fallback.
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

    -- Only a saved character gets a weapon. A draft in the creator can carry a stale character.lastWeapon from the previous selection; a character with no id was never holding anything.
    local saved = character.id ~= nil

    if saved and Multichar.Settings.showLastWeapon and character.lastWeapon then
        GiveWeaponToPed(Scene.ped, character.lastWeapon, 1, false, true)
        SetCurrentPedWeapon(Scene.ped, character.lastWeapon, true)
    end

    Scene.Reveal()
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

-- Back to the survivor list. Scene.zoom and Scene.rotation are only reset in Build(), and cancelling the creator returns to the list without a rebuild, so reset them here.
function Scene.ResetView()
    if Scene.handsUp then CreateThread(function() Scene.SetHandsUp(false) end) end
    Scene.rotation = 0.0
    Scene.zoom = 1.0
    Scene.focus = 'full'
    applyPedHeading()
    applyCam()
end

-- Validated dressing. "CPed::SetVariation: Invalid variation" in the console means a drawable that does not exist on this model (e.g. a preset jacket index the female ped lacks). The write is dropped and the old item stays, so check ranges first.

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

-- Pass true when bs_core is about to respawn the player (model swap, teleport, fade). Then do not touch the player ped: unfreezing mid-teleport drops people through the map. Only tear down the camera and preview ped.
function Scene.Destroy(handoff)
    if not Scene.active then return end

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

-- Scene lighting
-- bs_world turns map lights off, which left the preview in flat grey. These are local lights drawn only while the scene is up and around the stage: key light, cold fill from behind, low warm bounce.

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
                        DrawLightWithRange(
                            at.x + (light.x or 0.0),
                            at.y + (light.y or 0.0),
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

-- Watchdog
-- The world can unstream (grey void) or the preview ped can vanish. Both look the same to the player, so this re-asserts both a few times a second while the scene is up.

CreateThread(function()
    while true do
        Wait(500)

        if Scene.active then
            local s = Multichar.Scene.ped

            -- Keep streaming pinned to the stage, not the player.
            SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)

            -- Re-aim. The head bone is not measurable on the frame the ped is created, so the first framing uses the default height; this corrects it once the skeleton exists and after a model swap.
            if Scene.ped and DoesEntityExist(Scene.ped) then applyCam() end

            local now = GetGameTimer()

            if (not Scene.ped or not DoesEntityExist(Scene.ped))
               and now >= (Scene.nextRebuild or 0) then

                -- Rate limited on purpose: a rebuild that fails for the same reason must not retry twice a second.
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

-- Rotation and zoom come from the NUI (buttons, drag, keyboard) because the game never sees the mouse while the cursor is captured. See the pointer handlers in html/js/app.js.

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Scene.Destroy() end
end)
