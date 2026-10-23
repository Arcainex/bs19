-- Chat tunables. See client/cl_main.lua for why this resource exists.

Chat = {}

Chat.Settings = {
    -- How long (about 12 s) a message stays on screen once the box is closed. Opening the box brings everything back.
    fadeAfter = 12000,

    --- Lines kept in the scrollback. Beyond this the oldest are dropped.
    history = 120,

    --- Characters one message may carry. Anything longer is truncated rather
    --- than refused: losing the end of a sentence beats losing all of it.
    maxLength = 220,

    -- Messages per player per ten seconds. Extra ones are dropped silently.
    rateLimit = 12,

    -- Proximity chat, off by default. When enabled, only players within `range` metres hear you; staff and system messages are unaffected.
    proximity = {
        enabled = false,
        range   = 40.0,
    },
}

-- Default colour for messages without one, and the named channels. `system` is for our own resources (the ^5[BS] prefix).
Chat.Channels = {
    say    = { label = nil,        colour = { 240, 235, 221 } },
    system = { label = '[SYSTEM]', colour = { 224, 140, 70 } },
    staff  = { label = '[STAFF]',  colour = { 217, 164, 65 } },
    death  = { label = nil,        colour = { 180, 87, 74 } },
}
