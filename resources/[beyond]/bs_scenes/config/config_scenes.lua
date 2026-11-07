-- bs_scenes - notes survivors leave behind. They cost time to write, are capped per character, fade, and can be reported.

Scenes = {}

Scenes.Settings = {
    -- How far away a note can be read at all.
    drawDistance    = 24.0,
    -- Fully lit within this distance, fades to nothing beyond it.
    fadeDistance    = 14.0,

    -- Writing one takes this long, standing still.
    writeTime       = 4200,
    -- How many a single character may have in the world at once.
    perCharacter    = 8,
    -- Longest a note can be.
    maxLength       = 140,
    -- Notes older than this are swept. 0 = they stay forever.
    lifetimeDays    = 21,

    -- No note may be written this close to an existing one.
    minSpacing      = 2.0,

    -- How often the client asks for the notes around it, ms.
    refreshMs       = 20000,
    -- And how far around it.
    streamRadius    = 300.0,
}

-- Note kinds. Colour and shape carry the meaning; `prefix` is drawn before the text.
Scenes.Kinds = {
    note = {
        label = 'Note', icon = 'dot',
        colour = { r = 216, g = 210, b = 194 },
        prefix = '',
        blurb = 'Something worth writing down.',
    },
    warning = {
        label = 'Warning', icon = 'dot',
        colour = { r = 180, g = 87, b = 74 },
        prefix = '! ',
        blurb = 'Something worth not walking into.',
    },
    safe = {
        label = 'Safe', icon = 'dot',
        colour = { r = 127, g = 212, b = 162 },
        prefix = '+ ',
        blurb = 'Cleared, or somewhere to rest.',
    },
    supplies = {
        label = 'Supplies', icon = 'dot',
        colour = { r = 200, g = 118, b = 58 },
        prefix = '> ',
        blurb = 'Something is here, or was.',
    },
}

--- Writing looks like writing.
Scenes.Anim = {
    dict = 'missfbi3_party_d',
    clip = 'stand_talk_loop_a_male3',
    flag = 49,
}

Scenes.Keys = {
    -- Key that opens the write dialogue. Empty by default (slash command only).
    write = '',
}
