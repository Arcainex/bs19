-- bs_world - displays what the server says

local State = {
    minutes = 8 * 60,   -- our own copy, advanced locally between syncs
    rate    = 12.0,
    frozen  = false,
    weather = nil,
    weatherNext = nil,
    transitioningTo = nil,
    transitionId = 0,
    haveSync = false,
}

local lastLocal = GetGameTimer()

-- What the server says

-- A transition is a single operation, never a recurring sync action
local function transitionTo(weather, seconds)
    seconds = math.max(1.0, tonumber(seconds) or 90.0)
    State.weather = weather
    State.weatherNext = weather
    State.transitioningTo = weather
    State.transitionId = State.transitionId + 1
    local ticket = State.transitionId

    ClearOverrideWeather()
    SetWeatherTypeOvertimePersist(weather, seconds + 0.0)

    CreateThread(function()
        Wait((seconds + 2.0) * 1000)
        if State.transitionId == ticket and State.transitioningTo == weather then
            State.weather = weather
            State.weatherNext = nil
            State.transitioningTo = nil
            SetOverrideWeather(weather)
        end
    end)
end

RegisterNetEvent('bs:world:sync', function(s)
    if type(s) ~= 'table' then return end

    State.minutes  = (tonumber(s.hour) or 0) * 60 + (tonumber(s.minute) or 0)
    State.rate     = tonumber(s.rate) or 12.0
    State.frozen   = s.frozen == true
    State.haveSync = true
    lastLocal      = GetGameTimer()

    -- Natural weather changes are announced in sync as weatherNext
    if s.weatherNext then
        -- A joining player needs the server's transition origin to blend the remaining time, otherwise GTA's random local weather is used
        if State.weather == nil and s.weather then
            ClearOverrideWeather()
            SetWeatherTypeNow(s.weather)
            State.weather = s.weather
        end
        local duration = tonumber(s.transition) or 90.0
        local now = GetCloudTimeAsInt()
        local elapsed = math.max(0, now - (tonumber(s.weatherSince) or now))
        local remaining = math.max(1.0, duration - elapsed)
        if State.transitioningTo ~= s.weatherNext then
            transitionTo(s.weatherNext, remaining)
        end
    elseif not State.transitioningTo and s.weather and s.weather ~= State.weather then
        State.weather = s.weather
        State.weatherNext = nil
        SetOverrideWeather(s.weather)
    end
end)

-- Staff-set weather has its own event because it carries the full transition duration
RegisterNetEvent('bs:world:weather', function(weather, seconds)
    if not weather then return end
    seconds = tonumber(seconds) or 0

    if seconds <= 0 then
        State.transitionId = State.transitionId + 1
        State.weather = weather
        State.weatherNext = nil
        State.transitioningTo = nil
        ClearOverrideWeather()
        SetWeatherTypeNow(weather)
        SetOverrideWeather(weather)
        return
    end

    transitionTo(weather, seconds)
end)

-- Holding the clock

CreateThread(function()
    -- Ask immediately instead of waiting for the first periodic sync, so a joining client does not see the sky snap
    while not State.haveSync do
        TriggerServerEvent('bs:world:request')
        Wait(2000)
    end
end)

CreateThread(function()
    local onCharScreen = false
    local lastCheck = 0

    while true do
        Wait(0)

        if State.haveSync then
            local now = GetGameTimer()

            -- Advance our own copy between syncs, otherwise the clock jumps every syncSeconds and shadows move in steps
            if not State.frozen then
                local dt = (now - lastLocal) / 1000.0
                State.minutes = (State.minutes + (dt / 60.0) * State.rate) % 1440
            end
            lastLocal = now

            -- Stood down while the character screen is up: bs_multichar sets its own clock for the scene
            if now - lastCheck > 1000 then
                lastCheck = now
                onCharScreen = false
                if GetResourceState('bs_core') == 'started' then
                    local ok, st = pcall(function()
                        return exports.bs_core:GetSessionState()
                    end)
                    onCharScreen = ok and st == 'select'
                end
            end

            if not onCharScreen then
                local total = State.minutes % 1440
                local h = math.floor(total / 60)
                local m = math.floor(total % 60)
                local sec = math.floor((total % 1) * 60)
                NetworkOverrideClockTime(h, m, sec)
            end
        end
    end
end)

-- Holding the weather

CreateThread(function()
    while true do
        Wait(5000)

        -- The engine's weather system keeps running underneath and will drift off what we set
        if State.weather and not State.transitioningTo then SetOverrideWeather(State.weather) end
    end
end)
