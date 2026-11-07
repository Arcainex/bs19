-- Alpha-Z Weather V23 / authoritative siren + repeating shelter countdown.
-- 56s siren; acidrain 540s (no rain until 300s), other events 180s; 60s fade.
local active = 'none'
local activeRevision = 0
local activeSince = 0
local activeBaseWeather = nil
local pending = nil
local pendingUntil = 0
local pendingBaseWeather = nil
local pendingTicket = nil
local ending = false
local endingSince = 0
local endingStartIntensity = 1.0
local sequence = 0

local valid = { acidrain=true, toxicfog=true, ashstorm=true }
local WARNING_MS = 56000
local DEFAULT_BUILDUP_MS = 180000
local ACID_BUILDUP_MS = 540000
local OUTRO_MS = 60000
local COUNTDOWN_INTERVAL_MS = 120000  -- repeat every 2 minutes
local COUNTDOWN_DISPLAY_MS = 10000   -- on-screen for 10 seconds
local countdownTicket = nil
local countdownKind = nil
local countdownStartedAt = 0

local function buildupMs(kind)
    return kind == 'acidrain' and ACID_BUILDUP_MS or DEFAULT_BUILDUP_MS
end

local function worldAvailable()
    return GetResourceState('bs_world') == 'started'
end
local function lockWorld(on)
    if not worldAvailable() then return end
    local ok, err = pcall(function() exports.bs_world:SetAlphaWeatherLock(on) end)
    if not ok then
        print(('^1[Alpha-Z Wetter]^7 bs_world lock failed: %s'):format(tostring(err)))
    end
end
local function worldWeather()
    if not worldAvailable() then return nil end
    local ok, state = pcall(function() return exports.bs_world:WorldState() end)
    if ok and type(state) == 'table' and type(state.weather) == 'string' then
        return state.weather
    end
    return nil
end
local function sync(target)
    local elapsed = activeSince > 0 and math.max(0, (os.time() - activeSince) * 1000) or 0
    local endElapsed = ending and math.max(0, (os.time() - endingSince) * 1000) or 0
    TriggerClientEvent('bs:alphaweather:set', target or -1,
        active, activeRevision, elapsed, activeBaseWeather,
        ending, endElapsed, endingStartIntensity)
end
-- One authoritative server countdown: 56s siren + full weather build.
-- Acid rain takes 9m56s including its siren, so whole-minute warnings read
-- 10 / 8 / 6 / 4 / 2. The UI also renders the exact MM:SS remaining.
local function countdownTotalMs(kind)
    return WARNING_MS + buildupMs(kind)
end

local function countdownStillValid(ticket, kind)
    if sequence ~= ticket or countdownTicket ~= ticket or countdownKind ~= kind then
        return false
    end
    return (pending == kind and pendingTicket == ticket)
        or (active == kind and activeRevision == ticket and not ending)
end

local function sendCountdown(target, ticket, kind, step, remainder, duration)
    if not countdownStillValid(ticket, kind) then return end
    if remainder <= 0 or duration <= 0 then return end
    TriggerClientEvent('bs:alphaweather:countdown', target,
        ticket, step, math.floor(remainder), math.floor(duration))
end

local function startCountdown(ticket, kind)
    countdownTicket = ticket
    countdownKind = kind
    countdownStartedAt = os.time()
    local total = countdownTotalMs(kind)
    sendCountdown(-1, ticket, kind, 0, total, COUNTDOWN_DISPLAY_MS)
    local maxSteps = math.floor((total - 1) / COUNTDOWN_INTERVAL_MS)
    for step = 1, maxSteps do
        local timeOffset = step * COUNTDOWN_INTERVAL_MS
        SetTimeout(timeOffset, function()
            if not countdownStillValid(ticket, kind) then return end
            local elapsed = math.max(timeOffset, (os.time() - countdownStartedAt) * 1000)
            local remaining = math.max(0, total - elapsed)
            sendCountdown(-1, ticket, kind, step, remaining, COUNTDOWN_DISPLAY_MS)
        end)
    end
end

-- Late join / UI reconnect: show only the remainder of an already-running
-- 10-second notification, not a fresh 10-second pop-up.
local function syncCountdown(target)
    local ticket, kind = countdownTicket, countdownKind
    if not ticket or not kind or not countdownStillValid(ticket, kind) then return end
    local elapsed = math.max(0, (os.time() - countdownStartedAt) * 1000)
    local step = math.floor(elapsed / COUNTDOWN_INTERVAL_MS)
    local sinceStep = elapsed - (step * COUNTDOWN_INTERVAL_MS)
    if sinceStep < COUNTDOWN_DISPLAY_MS then
        local remaining = countdownTotalMs(kind) - elapsed
        sendCountdown(target, ticket, kind, step,
            remaining, COUNTDOWN_DISPLAY_MS - sinceStep)
    end
end

local function stopWarning(ticket, target)
    if not ticket then return end
    TriggerClientEvent('bs:alphaweather:warningStop', target or -1, ticket)
end

exports('Start', function(kind)
    kind = tostring(kind or ''):lower()
    if not valid[kind] then return false, 'unknown Alpha-Z weather' end
    if ending then return false, 'Das Wetter baut sich noch 60 Sekunden ab.' end
    if pending then return false, 'Eine Warnsirene laeuft bereits.' end
    if active ~= 'none' then return false, 'Zuerst das aktive Wetterereignis beenden.' end

    sequence = sequence + 1
    local ticket = sequence
    pending = kind
    pendingTicket = ticket
    pendingUntil = os.time() + WARNING_MS / 1000
    pendingBaseWeather = worldWeather() or 'OVERCAST'
    -- Lock weather before the first siren tone. Normal world weather is held.
    lockWorld(true)
    TriggerClientEvent('bs:alphaweather:warning', -1, kind, WARNING_MS, ticket)
    startCountdown(ticket, kind)

    SetTimeout(WARNING_MS, function()
        if sequence ~= ticket or pending ~= kind or pendingTicket ~= ticket then return end
        pending = nil
        pendingTicket = nil
        pendingUntil = 0
        stopWarning(ticket, -1)
        active = kind
        activeRevision = ticket
        activeSince = os.time()
        activeBaseWeather = pendingBaseWeather or 'OVERCAST'
        pendingBaseWeather = nil
        ending = false
        endingSince = 0
        endingStartIntensity = 1.0
        sync(-1)
    end)
    return true, 'warning:' .. kind
end)

exports('Stop', function()
    if ending then return true, 'ending:' .. active end
    sequence = sequence + 1
    local ticket = sequence
    local cancelTicket = pendingTicket
    pending, pendingTicket, pendingUntil, pendingBaseWeather = nil, nil, 0, nil
    if countdownTicket then
        TriggerClientEvent('bs:alphaweather:countdownCancel', -1, countdownTicket)
    end
    countdownTicket, countdownKind, countdownStartedAt = nil, nil, 0
    stopWarning(cancelTicket, -1)

    if active == 'none' then
        -- Warning cancelled. There is no effect yet: no visual fade is necessary.
        if cancelTicket then lockWorld(false) end
        return true, 'none'
    end

    -- Server does NOT send 'none' or unlock until the entire 60s fade completes.
    ending = true
    endingSince = os.time()
    endingStartIntensity = math.min(1.0, math.max(0.0,
        (endingSince - activeSince) * 1000 / buildupMs(active)))
    activeBaseWeather = activeBaseWeather or worldWeather() or 'OVERCAST'
    sync(-1)

    SetTimeout(OUTRO_MS, function()
        if sequence ~= ticket or not ending then return end
        ending = false
        endingSince = 0
        endingStartIntensity = 1.0
        active = 'none'
        countdownTicket, countdownKind, countdownStartedAt = nil, nil, 0
        activeRevision = ticket
        activeSince = 0
        activeBaseWeather = nil
        sync(-1)
        SetTimeout(350, function()
            if sequence == ticket and active == 'none' and not pending then
                lockWorld(false)
            end
        end)
    end)
    return true, 'ending'
end)

exports('State', function()
    if ending then return active end
    if pending then return 'warning:' .. pending end
    return active
end)

RegisterNetEvent('bs:alphaweather:request', function()
    local src = source
    sync(src)
    if pending then
        local remaining = math.max(0, pendingUntil - os.time()) * 1000
        if remaining > 0 then
            TriggerClientEvent('bs:alphaweather:warning', src, pending, remaining, pendingTicket)
        end
    end
    syncCountdown(src)
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(4000, function()
        if not GetPlayerName(src) then return end
        sync(src)
        if pending then
            local remaining = math.max(0, pendingUntil - os.time()) * 1000
            if remaining > 0 then
                TriggerClientEvent('bs:alphaweather:warning', src, pending, remaining, pendingTicket)
            end
        end
        syncCountdown(src)
    end)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'bs_world' and (pending or active ~= 'none') then
        SetTimeout(500, function()
            if pending or active ~= 'none' then lockWorld(true) end
        end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then lockWorld(false) end
end)
