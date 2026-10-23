-- bs_ui - plays our own sound files at a world position through the browser (GTA's audio cannot easily take custom .ogg). Spatialisation is done by Web Audio in html/js/sound.js; this file sends world coordinates, the listener position and culls by distance.
-- exports.bs_ui:PlaySoundAt(file, coords, { id, volume, maxDistance, rate, loop, category })
-- exports.bs_ui:MoveSoundAt(id, coords)
-- exports.bs_ui:StopSoundTag(id, fadeMs)
-- Files go in bs_ui/html/sound/ (restart the resource to pick them up). A missing file is reported once and is not fatal.

local Sound = {}

-- Read UI.Audio defensively so an older config still works (sounds play, bs_ui does not fail to start).
local A = (type(UI) == 'table' and type(UI.Audio) == 'table') and UI.Audio or {}

local DEFAULT_MAX_DISTANCE = tonumber(A.maxDistance) or 45.0
local MAX_WORLD_VOICES     = math.max(1, math.floor(tonumber(A.maxVoices) or 12))
local DEFAULT_FADE_MS      = math.max(0, math.floor(tonumber(A.defaultFadeMs) or 120))
local MOVE_INTERVAL_MS     = math.max(50, math.floor(tonumber(A.moveInterval) or 150))
local LISTENER_IDLE_MS     = math.max(50, math.floor(tonumber(A.listenerIdleInterval) or 500))
local VOICE_TIMEOUT_MS     = math.max(1000, math.floor(tonumber(A.voiceTimeout) or 30000))

-- Default zombie voice level 0.15, deliberately quiet: many overlapping HRTF sources at 1.0 become a wall of noise. Only a default; the Settings slider (`zombieVoiceVolume`) spans 0..1 and is not clamped here.
local DEFAULT_ZOMBIE_VOLUME = 0.15

local function clamp01(n, fallback)
    n = tonumber(n)
    if n == nil then return fallback end
    if n < 0.0 then return 0.0 end
    if n > 1.0 then return 1.0 end
    return n
end

local zombieVoiceVolume = clamp01(
    (type(UI) == 'table' and type(UI.Settings) == 'table') and UI.Settings.zombieVoiceVolume or nil,
    DEFAULT_ZOMBIE_VOLUME)

-- Player preferences arrive after the HUD state is restored. Keep this mixer
-- local: it changes only custom zombie voices, never menus or world ambience.
AddEventHandler('bs:ui:settingsChanged', function(settings)
    local fromPlayer = settings and settings.zombieVoiceVolume
    local fromConfig = (type(UI) == 'table' and type(UI.Settings) == 'table')
        and UI.Settings.zombieVoiceVolume or nil
    -- Order matters: a player who set the slider to 0 must stay at 0, so do not treat 0 as unset.
    zombieVoiceVolume = clamp01(fromPlayer, clamp01(fromConfig, DEFAULT_ZOMBIE_VOLUME))
end)

-- Live sources: everything believed to be making noise, keyed by caller id. The page is the authority on what plays (it reports ends via the soundEnded NUI callback); this side keeps its own view to cull, cap and send position updates.
-- Each entry also has an expiry (voiceTimeout) so a lost soundEnded callback cannot hold a voice slot forever.
local active = {}       -- id -> { x, y, z, distance, expires, spatial }
local activeCount = 0

local function forget(id)
    if active[id] then
        active[id] = nil
        activeCount = math.max(0, activeCount - 1)
    end
end

local function remember(id, x, y, z, distance, spatial)
    if not active[id] then activeCount = activeCount + 1 end
    active[id] = {
        x = x, y = y, z = z,
        distance = distance or 0.0,
        spatial = spatial and true or false,
        expires = GetGameTimer() + VOICE_TIMEOUT_MS,
    }
end

RegisterNUICallback('soundEnded', function(data, cb)
    local id = data and data.id and tostring(data.id) or nil
    if id then
        forget(id)
        -- Announced as an event so bs_zombies knows when to stop moving a playing voice with its walker (no need to model clip lengths). Other resources can listen too.
        TriggerEvent('bs:ui:soundEnded', id)
    end
    cb('ok')
end)

-- Reported once in the client console with the file name, so a missing sound is not a silent failure.
local missingReported = {}
RegisterNUICallback('soundMissing', function(data, cb)
    local file = data and data.file and tostring(data.file) or nil
    if file and not missingReported[file] then
        missingReported[file] = true
        print(('^3[BeyondSurvival]^7 (ui) sound file "%s" is missing or unreadable - that sound is off, everything else still works. Check bs_ui/html/sound/ and restart bs_ui.')
            :format(file))
    end
    cb('ok')
end)

-- The listener: position plus forward and up vectors, taken from the camera rather than the ped (in third person they differ, so sounds would land on the wrong side). Sent every frame while anything plays, otherwise on a slow heartbeat.
-- GetGameplayCamRot(2) gives the ZXY euler rotation; forward and up are derived from it since no native returns a camera basis.
local function cameraBasis()
    local rot = GetGameplayCamRot(2)
    local pitch = math.rad(rot.x)
    local roll  = math.rad(rot.y)
    local yaw   = math.rad(rot.z)

    local cp, sp = math.cos(pitch), math.sin(pitch)
    local cy, sy = math.cos(yaw),   math.sin(yaw)
    local cr, sr = math.cos(roll),  math.sin(roll)

    -- GTA heading: 0 is +Y and increases anticlockwise, so forward is (-sin yaw, cos yaw) flattened and lifted by pitch.
    local fx = -sy * cp
    local fy =  cy * cp
    local fz =  sp

    -- Up vector: forward rotated 90 degrees vertically, plus roll (cinematic and some vehicle cameras roll, and a mismatched up vector puts sounds above you).
    local ux0 =  sy * sp
    local uy0 = -cy * sp
    local uz0 =  cp

    -- Right vector, needed only to apply roll to the up vector.
    local rx, ry, rz = cy, sy, 0.0

    local ux = ux0 * cr + rx * sr
    local uy = uy0 * cr + ry * sr
    local uz = uz0 * cr + rz * sr

    return GetGameplayCamCoord(), fx, fy, fz, ux, uy, uz
end

local function pushListener()
    local at, fx, fy, fz, ux, uy, uz = cameraBasis()
    SendNUIMessage({
        action = 'soundlistener',
        x = at.x, y = at.y, z = at.z,
        fx = fx, fy = fy, fz = fz,
        ux = ux, uy = uy, uz = uz,
    })
end

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

-- Culling stays here: a sound that will never be heard should not cost a NUI message, fetch, decode and panner. Anything past maxDistance is not sent. This is a yes/no cut, the falloff curve is the panner's job (see sound.js).

--- @param file string   file name inside bs_ui/html/sound/
--- @param coords vector3|nil  where it happens; nil means "not in the world"
--- @param opts table|nil { id/tag, volume, maxDistance, rate, loop, category }
--- @return boolean  false when it was too far away, too quiet, or capped out
function Sound.PlayAt(file, coords, opts)
    if type(file) ~= 'string' or file == '' then return false end
    opts = opts or {}

    local volume = tonumber(opts.volume) or 1.0
    if opts.category == 'zombie' then volume = volume * zombieVoiceVolume end
    if volume <= 0.001 then return false end

    local id = opts.id or opts.tag
    id = id ~= nil and tostring(id) or nil

    local pos, distance
    if coords then
        local ear = GetGameplayCamCoord()
        local at  = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        distance = #(at - ear)

        local maxDistance = tonumber(opts.maxDistance) or DEFAULT_MAX_DISTANCE
        if distance >= maxDistance then return false end

        -- Voice cap: when full, the farthest live voice loses, not the newest, so a close walker is never starved out by distant ones.
        if activeCount >= MAX_WORLD_VOICES and (id == nil or active[id] == nil) then
            local worstId, worstD = nil, distance
            for otherId, rec in pairs(active) do
                if rec.spatial and rec.distance > worstD then
                    worstId, worstD = otherId, rec.distance
                end
            end
            if not worstId then return false end   -- everything live is closer
            SendNUIMessage({ action = 'soundstop', id = worstId, fadeMs = DEFAULT_FADE_MS })
            forget(worstId)
        end

        pos = { x = at.x, y = at.y, z = at.z }
    end

    SendNUIMessage({
        action = 'sound',
        file   = file,
        volume = volume,
        rate   = tonumber(opts.rate) or 1.0,
        loop   = opts.loop and true or false,
        pos    = pos,   -- absent => a UI sound, NOT spatialised. See sound.js.
        id     = id,
        maxDistance   = tonumber(opts.maxDistance) or nil,
        refDistance   = tonumber(opts.refDistance) or nil,
        rolloffFactor = tonumber(opts.rolloffFactor) or nil,
    })

    if id then remember(id, pos and pos.x, pos and pos.y, pos and pos.z, distance, pos ~= nil) end
    return true
end

-- Safe to call for an id that is not playing, so callers never need to know if a clip is still in flight.
function Sound.MoveAt(id, coords)
    if id == nil or coords == nil then return false end
    id = tostring(id)

    local rec = active[id]
    if not rec or not rec.spatial then return false end

    local x, y, z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
    rec.x, rec.y, rec.z = x, y, z
    rec.distance = #(vector3(x, y, z) - GetGameplayCamCoord())

    SendNUIMessage({ action = 'soundmove', id = id, x = x, y = y, z = z, overMs = MOVE_INTERVAL_MS })
    return true
end

-- Stops everything playing under an id with a fade. Sounds are handed to the browser and forgotten, so they have to be labelled to be stopped (bs_zombies uses one id per walker and calls this on death). The fade runs in the page (gain automation); a hard stop clicks and a death should sag away rather than switch off. nil fadeMs = short default ramp.
function Sound.StopTag(id, fadeMs)
    if id == nil then return false end
    id = tostring(id)
    SendNUIMessage({
        action = 'soundstop',
        id = id,
        fadeMs = math.max(0, math.floor(tonumber(fadeMs) or DEFAULT_FADE_MS)),
    })
    forget(id)
    return true
end

-- Listener pump and expiry sweep share one thread, since both depend on 'is anything playing?'.
CreateThread(function()
    -- Send the page its tuning before anything plays. Sent on every resource start, so a config edit needs a bs_ui restart.
    Wait(500)
    SendNUIMessage({
        action = 'audiocfg',
        cfg = {
            panningModel  = tostring(A.panningModel or 'HRTF'),
            distanceModel = tostring(A.distanceModel or 'inverse'),
            refDistance   = tonumber(A.refDistance) or 3.0,
            rolloffFactor = tonumber(A.rolloffFactor) or 1.1,
            maxDistance   = DEFAULT_MAX_DISTANCE,
            maxVoices     = MAX_WORLD_VOICES,
            maxUiVoices   = math.max(1, math.floor(tonumber(A.maxUiVoices) or 6)),
            defaultFadeMs = DEFAULT_FADE_MS,
        },
    })

    while true do
        if activeCount > 0 then
            -- Every frame while the mixer is busy; this is what keeps the world from swimming when you turn.
            pushListener()

            local now = GetGameTimer()
            for id, rec in pairs(active) do
                if now >= rec.expires then forget(id) end
            end

            Wait(0)
        else
            -- Nothing playing: keep the listener roughly current so the next sound does not start from a stale position.
            pushListener()
            Wait(LISTENER_IDLE_MS)
        end
    end
end)

-- A page reload discards all audio sources, so drop our view of them instead of leaving phantom voices in the cap.
RegisterNUICallback('soundReady', function(_, cb)
    active, activeCount = {}, 0
    cb('ok')
end)

-- Exports: plain data in, boolean out. `coords` may arrive as a plain table from another resource, so it is read by field.

local function asCoords(coords)
    if type(coords) == 'table' or type(coords) == 'vector3' then
        local x, y, z = coords.x, coords.y, coords.z
        if x and y and z then return vector3(x + 0.0, y + 0.0, z + 0.0) end
    end
    return nil
end

exports('PlaySoundAt', function(file, coords, opts)
    return Sound.PlayAt(file, asCoords(coords), type(opts) == 'table' and opts or nil)
end)

-- Move a playing sound. Cheap, no-op if the id is not playing.
exports('MoveSoundAt', function(id, coords)
    local at = asCoords(coords)
    if not at then return false end
    return Sound.MoveAt(id, at)
end)

-- Stop with a fade. `fadeMs` is optional; nil uses the short default.
exports('StopSoundTag', function(tag, fadeMs) return Sound.StopTag(tag, fadeMs) end)

-- Is anything still playing under this id? Lets callers stop sending position updates without modelling clip lengths.
exports('IsSoundLive', function(id)
    return id ~= nil and active[tostring(id)] ~= nil
end)

-- Non-positional sound (menus, notifications, hitmarkers, level-up sting). Sends no coordinates, so the page never spatialises it.
exports('PlaySound2D', function(file, opts)
    return Sound.PlayAt(file, nil, type(opts) == 'table' and opts or nil)
end)

BS = BS or {}
if BS.Provide then
    BS.Provide('ui', {
        PlaySoundAt  = Sound.PlayAt,
        MoveSoundAt  = Sound.MoveAt,
        StopSoundTag = Sound.StopTag,
    })
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

-- /soundtest <file> [distance] - plays a file to check it is present and audible. With a distance it is placed in front of the camera and swept around you, which shows whether HRTF works on this machine (a sound stuck in the middle of your head means fallback to equal power).
RegisterCommand('soundtest', function(_, args)
    local file = args[1]
    if not file then
        print('^3[BeyondSurvival]^7 (ui) usage: /soundtest <file.ogg> [metres]  (from bs_ui/html/sound/)')
        return
    end

    local metres = tonumber(args[2])
    if not metres then
        Sound.PlayAt(file, nil, { volume = 1.0 })
        print(('^5[BeyondSurvival]^7 (ui) asked the page to play "%s" flat (no spatialisation) - if you hear nothing, F8 will say why')
            :format(file))
        return
    end

    local id = 'soundtest'
    local ear = GetGameplayCamCoord()
    Sound.PlayAt(file, vector3(ear.x, ear.y + metres, ear.z), {
        id = id, volume = 1.0, maxDistance = math.max(10.0, metres * 3.0),
    })
    print(('^5[BeyondSurvival]^7 (ui) "%s" placed %.1fm away and orbiting - it should travel around your head')
        :format(file, metres))

    CreateThread(function()
        local started = GetGameTimer()
        while GetGameTimer() - started < 8000 do
            local t = (GetGameTimer() - started) / 2000.0
            local here = GetGameplayCamCoord()
            Sound.MoveAt(id, vector3(
                here.x + math.sin(t) * metres,
                here.y + math.cos(t) * metres,
                here.z))
            Wait(MOVE_INTERVAL_MS)
        end
        Sound.StopTag(id, 400)
    end)
end, false)

-- /soundstat - shows what the mixer is doing. First thing to check for 'I cannot hear zombies' reports (is the cap full?).
RegisterCommand('soundstat', function()
    print(('^5[BeyondSurvival]^7 (ui) %d/%d world voices live, zombie mixer at %.0f%%')
        :format(activeCount, MAX_WORLD_VOICES, zombieVoiceVolume * 100.0))
    for id, rec in pairs(active) do
        print(('        %s  %.1fm'):format(id, rec.distance or 0.0))
    end
end, false)
