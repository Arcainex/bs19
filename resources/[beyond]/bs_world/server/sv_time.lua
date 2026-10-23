-- bs_world - authority for time and weather

local Time = {
    -- Minutes past midnight, fractional. Single source of truth.
    minutes = World.Time.startAt or (8 * 60),
    frozen  = World.Time.frozen == true,
    lastTick = os.clock(),
}

local Weather = {
    current = World.Weather.startWith or 'OVERCAST',
    -- What we are blending to, nil when nothing is in progress.
    next    = nil,
    -- os.time() when the current weather became settled.
    since   = os.time(),
    frozen  = World.Weather.frozen == true,
}

-- The clock

-- Advanced from the real elapsed delta, not a fixed step per tick, so server load does not make the clock drift
local function advanceClock()
    local now = os.clock()
    local dt  = now - Time.lastTick
    Time.lastTick = now

    if Time.frozen then return end
    if dt <= 0 or dt > 60 then return end   -- a hitch or a debugger pause

    Time.minutes = (Time.minutes + (dt / 60.0) * (World.Time.rate or 1.0)) % 1440
end

local function clockParts()
    local total = Time.minutes % 1440
    local h = math.floor(total / 60)
    local m = math.floor(total % 60)
    return h, m
end

-- The weather cycle

local function pickWeather(avoid)
    local cycle = World.Weather.cycle or {}
    if #cycle == 0 then return Weather.current end

    local total = 0
    for _, e in ipairs(cycle) do
        if not (World.Weather.noRepeat and avoid and e.type == avoid) then
            total = total + (e.weight or 1)
        end
    end
    if total <= 0 then return Weather.current end

    local roll = math.random() * total
    for _, e in ipairs(cycle) do
        if not (World.Weather.noRepeat and avoid and e.type == avoid) then
            roll = roll - (e.weight or 1)
            if roll <= 0 then return e.type end
        end
    end

    return cycle[#cycle].type
end

-- Telling everyone

--- @param target number|nil  a server id, or nil for everyone
local function broadcast(target)
    local h, m = clockParts()

    TriggerClientEvent('bs:world:sync', target or -1, {
        hour    = h,
        minute  = m,
        rate    = World.Time.rate or 1.0,
        frozen  = Time.frozen,

        weather        = Weather.current,
        weatherNext    = Weather.next,
        weatherSince   = Weather.since,
        weatherFrozen  = Weather.frozen,
        transition     = World.Weather.transitionSeconds or 90,
    })
end

-- A newly connected client asks and is told immediately, so it does not join into the wrong sky
RegisterNetEvent('bs:world:request', function()
    broadcast(source)
end)

-- The loops

CreateThread(function()
    while true do
        Wait(1000)
        advanceClock()
    end
end)

CreateThread(function()
    while true do
        Wait((World.Time.syncSeconds or 10) * 1000)
        broadcast()
    end
end)

CreateThread(function()
    while true do
        Wait(5000)

        if not Weather.frozen then
            local holdFor = (World.Weather.holdMinutes or 30) * 60

            -- A finished transition becomes the settled weather
            if Weather.next then
                local blend = World.Weather.transitionSeconds or 90
                if os.time() - Weather.since >= blend then
                    Weather.current = Weather.next
                    Weather.next    = nil
                    Weather.since   = os.time()
                    broadcast()
                end
            elseif os.time() - Weather.since >= holdFor then
                Weather.next  = pickWeather(Weather.current)
                Weather.since = os.time()
                print(('^5[BS WORLD]^7 weather drifting %s -> %s over %ds')
                    :format(Weather.current, Weather.next,
                            World.Weather.transitionSeconds or 90))
                broadcast()
            end
        end
    end
end)

-- What staff can do to it

-- Set the time and let it run; freezing is a separate choice.
exports('SetTime', function(hour, minute)
    hour = math.floor(tonumber(hour) or 0) % 24
    minute = math.floor(tonumber(minute) or 0) % 60

    Time.minutes = hour * 60 + minute
    Time.lastTick = os.clock()
    broadcast()

    return { ok = true, hour = hour, minute = minute, frozen = Time.frozen }
end)

exports('FreezeTime', function(on)
    Time.frozen = on == true
    Time.lastTick = os.clock()
    broadcast()
    return { ok = true, frozen = Time.frozen }
end)

-- Set the weather and freeze it unless told otherwise (a staff-chosen weather is usually deliberate)
exports('SetWeather', function(weather, freeze, instant)
    weather = tostring(weather or ''):upper()

    Weather.current = weather
    Weather.next    = nil
    Weather.since   = os.time()
    if freeze ~= false then Weather.frozen = true end

    TriggerClientEvent('bs:world:weather', -1, weather,
        instant and 0 or (World.Weather.transitionSeconds or 90))
    broadcast()

    return { ok = true, weather = weather, frozen = Weather.frozen }
end)

exports('FreezeWeather', function(on)
    Weather.frozen = on == true
    -- Unfreezing restarts the hold from now, so it does not change on the first tick.
    Weather.since = os.time()
    broadcast()
    return { ok = true, frozen = Weather.frozen }
end)

exports('WorldState', function()
    local h, m = clockParts()
    return {
        hour = h, minute = m, timeFrozen = Time.frozen,
        weather = Weather.current, weatherNext = Weather.next,
        weatherFrozen = Weather.frozen,
        heldFor = os.time() - Weather.since,
        holdFor = (World.Weather.holdMinutes or 30) * 60,
    }
end)
