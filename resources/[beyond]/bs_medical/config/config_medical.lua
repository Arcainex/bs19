-- bs_medical - downed state, bleedout and revive settings.
-- At zero health you go down instead of respawning. You can call for help,
-- bandage yourself, or bleed out and wake up at a clinic.

Medical = {}

Medical.Settings = {
    enabled          = true,

    -- Seconds on the floor before bleeding out. Mirrors Config.Death in bs_core.
    bleedoutTime     = 300,

    -- Health at or below which you are put into the downed state (GTA floor is
    -- 100, max player health is usually 200). Higher = more of the bar counts as
    -- downed. The server accepts 'medical:down' up to catchHealth + 5.
    catchHealth      = 125,

    -- Lethal damage goes to downed first, whatever the cause, except the causes
    -- switched off below.
    catchAllDeaths   = true,
    hardDeathOnExplosion = true,    -- explosions still kill outright
    hardDeathOnDrown     = true,    -- drowning still kills outright
    hardDeathFallHeight  = 15.0,    -- falls from higher than this (m) kill outright

    -- A player on the death screen (not yet respawned) can still be revived with a
    -- medkit. Their items stay with them until they respawn.
    reviveDead       = true,

    -- Bandage packs (self or other) are not limited per downing.
    stabiliseUnlimited = true,

    -- Health restored on revive. Kept low on purpose.
    reviveHealth     = 30,

    -- Revive duration in ms. Field medic shortens it.
    reviveTime       = 12000,
    -- Max distance a revive can start and be held at.
    reviveDistance   = 2.0,

    -- Cost to the reviver. Set to nil for free revives.
    reviveItem       = 'medkit',
    -- A bandage does not revive, but buys time.
    stabiliseItem    = 'bandage',
    -- Seconds a bandage adds to the timer (repeatable if stabiliseUnlimited).
    stabiliseBonus   = 90,

    -- Shouting for help.
    shoutNoise       = 45.0,
    shoutCooldown    = 6000,

    -- Wake-up points if nobody came. Mirrors Config.Death.respawnPoints.
    respawnPoints = {
        { x = 1839.5, y = 3672.9, z = 34.28, h = 210.0, label = 'Sandy Shores Medical' },
        { x = 297.5,  y = -584.6, z = 43.26, h = 70.0,  label = 'Pillbox Hill Medical' },
    },

    -- Item loss on death (default ON).
    -- bs_inventory's WipeInventory empties every slot, including the equipment
    -- slots, so worn clothing is lost too. This is intended and not separable
    -- without a second wipe implementation.
    -- No player-corpse container exists on the death path; if one is added,
    -- sv_main.lua fires `bs:medical:death:beforeWipe` first so it can be filled
    -- from the full inventory.
    wipeOnDeath      = true,

    -- Death penalty. Infection survives death.
    respawnHealth    = 120,
    respawnHunger    = 45.0,
    respawnThirst    = 45.0,
}

-- Player bodies. On a real death everything carried (bag, bar, worn gear) goes
-- into the corpse, which stays where you fell until looted or `lifetime`
-- runs out. Lost on resource restart.
Medical.Corpse = {
    enabled        = true,
    lifetime       = 3600,   -- seconds, hard cap
    emptyGrace     = 20,     -- seconds a looted-out body lingers
    searchDistance = 2.5,
    searchTime     = 3500,   -- ms kneeling before the body opens
    label          = 'Body of %s',
    blip           = true,   -- owner only
    blipSprite     = 310,
    blipColour     = 1,
    blipLabel      = 'Your body',
    -- Walkers feeding on it: each report from a feeding host rots it a bit.
    rotPerBite     = 0.08,
    biteInterval   = 10,     -- seconds between accepted rot steps per body
}

-- Downed animation (base game, no streamed assets).
Medical.Anims = {
    downed   = { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
    dying    = { dict = 'combat@damage@writhe', clip = 'writhe_loop_dying' },
    reviving = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
    shout    = { dict = 'random@arrests', clip = 'generic_radio_chatter' },
}

-- Keys used while downed.
Medical.Keys = {
    -- Shout for help.
    shout     = 'E',
    -- Use a bandage on yourself.
    stabilise = 'G',
    -- HOLD for 2.5s to give up and bleed out. A hold, so it is not triggered by
    -- accident. Hold length and key are in cl_downed.lua.
    giveUp    = 'X (hold)',
    -- Ask for help: see Medical.Help below.
    help      = 'H',
}

-- Wake-up spot after a real death: random open ground this far from where you
-- fell. Bedrolls still win; the clinics above are the fallback.
Medical.Respawn = {
    minDistance = 500.0,
    maxDistance = 1000.0,
    tries       = 14,
    -- No wake-ups inside these (PvP / extraction zones). x, y, radius.
    avoidZones  = {
        { x = 200.0, y = -900.0, r = 450.0 },   -- bs_extraction downtown zone + margin
    },
}

-- Calling for help while down: pings nearby players, your squad and faction
-- on the map.
Medical.Help = {
    control   = 74,        -- H (INPUT_VEH_HEADLIGHT)
    label     = 'H',
    radius    = 250.0,     -- anyone this close hears it
    cooldown  = 30,        -- seconds between calls
    blipTime  = 90,        -- seconds the ping stays on their map
}

-- Self-revive: a medkit used while down (R on the downed screen, or 'use' in
-- the inventory) goes through the normal revive path.
Medical.SelfRevive = {
    enabled  = false,
    item     = 'medkit',
    control  = 45,         -- R (INPUT_RELOAD)
    label    = 'R',
    time     = 6000,       -- ms of patching yourself before you get up
}

-- Being shot down by another player. One bullet can exceed the catch window
-- (headshots, most rifles) and kill outright. With downFirst on, a death caused
-- by another player is caught and the player goes into the downed state.
Medical.PvP = {
    downFirst       = true,
    -- false: a downed player cannot be finished off; only the clock, giving up or
    -- a revive ends it. true: other players can kill them for real.
    allowExecution  = false,
}

-- Dragging and carrying downed players (client/cl_carry.lua). Anyone can drag.
-- Carrying needs the Fireman carry perk (bs_skills Survival tree): level 1
-- shuffle, 2 normal walk, 3 can jog.
Medical.Carry = {
    enabled       = true,
    distance      = 2.0,       -- to start
    serverMaxDist = 4.0,       -- server check when starting
    dropControl   = 38,        -- E (same key that started it via the dot)
    dropLabel     = 'E',
    -- Bleedout while dragged/carried: 0 = paused, 0.5 = half speed, 1 = normal.
    bleedoutRate  = 0.0,
    drag  = {
        carrier = { dict = 'combat@drag_ped@', clip = 'injured_drag_plyr' },
        victim  = { dict = 'combat@drag_ped@', clip = 'injured_drag_ped' },
        bone = 11816, offset = { 0.0, 0.48, 0.0 }, rot = { 0.0, 0.0, 0.0 }, victimFlag = 1,
        moveRate = 0.5,
    },
    carry = {
        carrier = { dict = 'missfinale_c2mcs_1', clip = 'fin_c2_mcs_1_camman' },
        victim  = { dict = 'nm', clip = 'firemans_carry' },
        bone = 0, offset = { 0.27, 0.15, 0.63 }, rot = { 0.5, 0.5, 180.0 }, victimFlag = 33,
        tiredClipset = 'move_m@injured',
        -- per perk level: movement rate multiplier and whether sprint (jog) is allowed
        levels = {
            [1] = { moveRate = 0.6, tired = true,  jog = false },
            [2] = { moveRate = 1.0, tired = false, jog = false },
            [3] = { moveRate = 1.0, tired = false, jog = true  },
        },
    },
}
