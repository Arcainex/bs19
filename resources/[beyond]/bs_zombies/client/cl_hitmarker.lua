-- bs_zombies - hit marker

local M = Zombies.HitMarker or {}

-- These are pushed from bs_vip (owner of the F7 menu) instead of being read per shot
local Opt = {
    vip = false, hitMarker = false, hitMarkerHead = true, hitMarkerKill = true,
    hitMarkerHeadOnly = false,
}

-- Enabled for everyone (see cl_options.lua). vip is kept as the on-switch name below.
Opt.vip = true
local crossRgb = { 230, 220, 198 }   -- bone
local crossUntil, crossHead = 0, false

AddEventHandler('bs:combatfx:options', function(o)
    if type(o) ~= 'table' then return end
    Opt.vip = true
    Opt.visual = o.hitMarkerVisual ~= false
    crossRgb = { 230, 220, 198 }
    if o.custom == true and type(o.hmHex) == 'string' then
        local r, g, b = o.hmHex:match('^#(%x%x)(%x%x)(%x%x)$')
        if r then crossRgb = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) } end
    end
    if o.hitMarker ~= nil then Opt.hitMarker = o.hitMarker == true end
    if o.hitMarkerHead ~= nil then Opt.hitMarkerHead = o.hitMarkerHead == true end
    if o.hitMarkerKill ~= nil then Opt.hitMarkerKill = o.hitMarkerKill == true end
    if o.hitMarkerHeadOnly ~= nil then
        Opt.hitMarkerHeadOnly = o.hitMarkerHeadOnly == true
    end
end)

-- Rate floor
local lastAt = 0
local FLOOR = 70

local soundQueue = {}
local soundHead = 1
local soundTail = 0
local soundWorker = false
local MAX_QUEUED = 64
local QUEUE_GAP = tonumber(M.queueGapMs) or 45

local function drainSounds()
    if soundWorker then return end
    soundWorker = true

    CreateThread(function()
        while soundHead <= soundTail do
            local item = soundQueue[soundHead]
            soundQueue[soundHead] = nil
            soundHead = soundHead + 1

            if GetResourceState('bs_ui') == 'started' then
                pcall(function()
                    exports.bs_ui:PlaySound2D(item.file, {
                        volume = item.volume,
                        rate = item.rate,
                        priority = 'feedback',
                    })
                end)
            end

            Wait(QUEUE_GAP)
        end

        soundQueue = {}
        soundHead = 1
        soundTail = 0
        soundWorker = false
    end)
end

local function play(file, volume, rate)
    -- Spread mass-kill feedback over a few frames
    local queued = soundTail - soundHead + 1
    if queued >= MAX_QUEUED then return end

    soundTail = soundTail + 1
    soundQueue[soundTail] = {
        file = file,
        volume = volume,
        rate = rate,
    }
    drainSounds()
end

-- A shot landed. headshot picks the brighter sound.
function Zombies.HitMarker(headshot)
    if not Opt.vip or not Opt.hitMarker then return end

    -- Headshots-only check runs before the rate floor
    if Opt.hitMarkerHeadOnly and not headshot then return end

    -- Keep the anti-buzz floor for body hits in automatic fire
    if not headshot then
        local now = GetGameTimer()
        if now - lastAt < FLOOR then return end
        lastAt = now
    end

    if Opt.visual ~= false then
        crossUntil = GetGameTimer() + 140
        crossHead = headshot and true or false
    end

    if headshot and Opt.hitMarkerHead then
        play(M.headFile or 'hitmarker_head.wav', M.headVolume or 0.85, 1.0)
    else
        -- Slight pitch variation (+/- 4%) on the body tick so repeats do not sound synthetic
        local rate = 0.96 + math.random() * 0.08
        play(M.file or 'hitmarker.wav', M.volume or 0.7, rate)
    end
end

-- Kill confirmation.
function Zombies.KillMarker()
    if not Opt.vip or not Opt.hitMarker or not Opt.hitMarkerKill then return end
    play(M.killFile or 'hitmarker_kill.wav', M.killVolume or 0.8, 1.0)
end

-- /hitmarkertest - plays the three sounds without needing a zombie, weapon or VIP.
RegisterCommand('hitmarkertest', function()
    CreateThread(function()
        play(M.file or 'hitmarker.wav', M.volume or 0.7, 1.0)
        Wait(400)
        play(M.headFile or 'hitmarker_head.wav', M.headVolume or 0.85, 1.0)
        Wait(500)
        play(M.killFile or 'hitmarker_kill.wav', M.killVolume or 0.8, 1.0)
        print('^5[BeyondSurvival]^7 (zombies) played hit / headshot / kill - F8 will say if a file is missing')
    end)
end, false)

-- Small cross at the crosshair, shown briefly after a hit.
CreateThread(function()
    while true do
        if GetGameTimer() < crossUntil then
            Wait(0)
            local s = crossHead and 0.0105 or 0.0085
            local a = crossHead and 255 or 220
            local r, g, b = crossRgb[1], crossRgb[2], crossRgb[3]
            if crossHead and crossRgb[1] == 230 then r, g, b = 224, 140, 70 end
            -- four short ticks, like an X with the centre cut out
            for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
                DrawRect(0.5 + d[1] * s, 0.5 + d[2] * s * 1.7, 0.006, 0.0022, r, g, b, a)
            end
        else
            Wait(50)
        end
    end
end)
