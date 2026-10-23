-- BeyondSurvival - bs_world clock and weather
-- Both are kept as ongoing server-driven state; one-shot overrides would slide back within seconds

World = World or {}

World.Time = {
    -- World clock speed as a multiple of real time (1.0 = real 24h day). 12 gives a full day/night cycle in two real hours.
    rate = 12.0,

    -- Start time on a cold boot, in minutes past midnight.
    startAt = 8 * 60,

    -- Frozen = the clock does not advance. Staff can toggle it from the menu.
    frozen = false,

    -- Seconds between server clock syncs. Clients advance their own copy in between, so this is a correction rate.
    syncSeconds = 10,
}

World.Weather = {
    -- Minimum time one weather type lasts before drifting to the next, in minutes.
    holdMinutes = 30,

    -- Duration of the crossfade between two weathers, in seconds. A native blend looks smoother than a hard cut.
    transitionSeconds = 90,

    -- Frozen = weather never changes on its own. Staff-set weather turns this on by default (see setWeather in sv_time.lua).
    frozen = false,

    -- Weather on a cold boot.
    startWith = 'EXTRASUNNY',

    -- Weighted weather cycle
    -- Grim and overcast is common; rain and thunder are rare because they mask the sound cues zombies use
    cycle = {
        { type = 'OVERCAST',   weight = 26 },
        { type = 'CLOUDS',     weight = 22 },
        { type = 'SMOG',       weight = 14 },
        { type = 'FOGGY',      weight = 10 },
        { type = 'EXTRASUNNY', weight = 10 },
        { type = 'CLEARING',   weight = 8 },
        { type = 'RAIN',       weight = 6 },
        { type = 'THUNDER',    weight = 4 },
    },

    -- Weather that may not follow itself, so the cycle never picks the same type twice in a row.
    noRepeat = true,
}
