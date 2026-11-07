-- bs_stash - buried stashes.
-- A shovel is required to bury and dig. Other players can find one only by standing on it with a shovel (no prop or marker). Capped per character.

Stash = {}

Stash.Settings = {
    enabled = true,

    -- Item required to dig. Wears a little each time.
    tool     = 'shovel',
    toolWear = 1,

    -- How many a character may have buried at once.
    maxPerCharacter = 5,

    -- Time to dig, ms - burying and opening both.
    digMs = 6000,

    -- Distance (m) at which the owner sees their stash name.
    ownerSight = 50.0,

    -- Distance (m) a stranger must be within, and only with a shovel.
    strangerSight = 1.4,
    -- How often (ms) a stranger's shovel probes the ground. Also rate-limited on the server.
    probeInterval = 900,

    -- Two holes cannot be dug on top of each other.
    minSpacing = 4.0,

    -- The hole itself, as an inventory container.
    size      = 20,
    maxWeight = 160.0,

    -- Noise level. Quiet by design, see Emotes.Noise.digging.
    noise = 'digging',

    -- Candidate digging animations, tried in order and checked with GetAnimDuration (a dict can load without containing the clip).
    anim = {
        { dict = 'amb@world_human_gardener_plant@male@base',       clip = 'base' },
        { dict = 'random@burial',                                  clip = 'a_burial' },
        { dict = 'amb@world_human_const_drill@male@drill@base',    clip = 'base' },
        { dict = 'missheistdockssetup1clipboard@base',             clip = 'base' },
    },
}
