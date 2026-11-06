-- bs_skills - non-perk abilities (dodge and weapon sway). Both scale continuously with a skill level, so they live here next to the trees rather than in Skills.Trees, and read the level from this resource's client cache.
-- Load order: config_skills.lua declares `Skills = {}`, so this file must come after it in the fxmanifest shared_scripts or every tunable here becomes nil.

Skills = Skills or {}

-- The dodge

-- Shift + double-tap a movement key to throw yourself that way.
Skills.Dodge = {
    enabled = true,

    -- Survival tree level needed before the dodge works (skill tree level, not character level).
    minLevel = 0,

    -- ms allowed between the two taps. 420 matches bs_emotes' double-tap jump.
    doubleTapMs = 420,

    -- Stamina cost at minimum skill, instant (0-100 scale). 22 is about four dodges from full.
    staminaCost  = 22.0,
    staminaFloor = 15.0,

    -- Stamina cost at max survival level; interpolated linearly from minLevel to the tree's maxLevel.
    staminaCostAtMax = 9.0,

    -- Cooldown in ms at minimum skill (here) and at max, interpolated the same way. 1600 makes a dodge a decision
    cooldownMs      = 1600,
    cooldownMsAtMax = 700,

    -- Push speed in m/s, min skill to max. 7.0 covers about 3m, 9.5 about 4m.
    speed      = 7.0,
    speedAtMax = 9.5,

    -- ms the push is applied (the window where the player is not fully in control; not the animation length).
    pushMs = 340,

    -- Roll timing.
    playGetUp     = true,
    p1Portion     = 1.0,
    chainOverlapMs = 60,
    chainBlendIn  = 4.0,
    blendOut      = -2.0,  -- 0 = input can't cut the roll (32 lets it)
    rollFlag      = 0,     -- 0 = input can't cut the roll (32 let it)
    lockControls  = true,
    extraLockMs   = 0,

    -- Small upward push in m/s so the ped skims instead of grinding along the ground (also helps with kerbs). 0.0 disables.
    lift = 1.1,

    -- Fraction taken off stamina cost and cooldown when the `break_fall` perk is owned.
    perkBonus = 0.25,

    -- Animation. Read before changing a clip name.
    -- The GTA Online combat roll lives in move_strafe@roll (and move_strafe@roll_fps): combatroll_fwd_p1_* / combatroll_bwd_p1_* plus a _p2_ variant of each; the number is the roll angle. Melee slips come from melee@unarmed@streamed_core (dodge_generic_l / _r / _centre).
    -- Flag 48 = upper body only + player control, so the legs follow the real movement.
    -- Tested on build b3258, base game only.
    -- A wrong full-body clip is worse than none: with no clip the dodge is just a fast sidestep.

    -- Which animation tiers are acceptable: 'roll' (default) - combat roll first, then melee slips
    animStyle = 'roll',

    -- Set true if left and right dodges come out reversed.
    mirrorSides = false,

    -- Hold the ped's facing during the push.
    lockHeading = true,

    -- Allow dodging while aiming down sights.
    allowWhileAiming = false,

    -- Tell the player why a dodge was refused (level, stamina, cooldown, aiming), rate-limited.
    announceRefusals = true,

    -- ms minimum gap between two refusal notifications.
    announceCooldownMs = 2500,

    -- Print the resolved animation and each refused dodge to F8.
    debug = false,
}

-- Weapon sway

-- Weapon sway: the lower the skill, the more the aim wanders. Uses the `combat` tree.
Skills.Sway = {
    enabled = true,

    -- Which tree steadies your hands (so re-cut trees do not need cl_sway.lua edits).
    tree = 'combat',

    -- 'aim' - nudge the point of aim only (in third person the horizontal part is mostly absorbed by the game camera, so it can be barely visible). 'crosshair' - aim untouched, only the reticle wobbles (cosmetic, gentlest). 'both' (default) - reticle follows the real aim error.
    mode = 'both',

    -- Peak aim excursion in degrees at zero combat skill (how far the muzzle can be from where you pointed). 1.8 is
    maxDegrees = 1.8,

    -- Combat level where sway reaches exactly zero. Must be <= the combat tree's maxLevel or it never fully clears.
    zeroAtLevel = 20,

    -- Falloff shape. 1.0 = linear (level 10 of 20 = half the sway). Above 1 the sway drops fast at first, so early levels feel like a real improvement.
    curve = 1.6,

    -- Fraction removed from the remaining sway when the `steady_hands` perk is owned.
    perkBonus = 0.30,

    -- Wander speed in cycles per second for the two layers.
    slowHz = 0.31,
    fastHz = 0.79,

    -- Vertical excursion as a fraction of horizontal.
    verticalRatio = 0.85,

    -- Multipliers on top of the skill-derived amount. Set all to 1.0 for skill-only sway.
    movingMultiplier = 1.8,   -- walking or running while aiming
    crouchMultiplier = 0.65,  -- a braced, low stance is steadier
    windedMultiplier = 1.6,   -- at zero stamina; scales in from `windedFrom`
    windedFrom       = 25.0,  -- stamina at which the winded penalty starts

    -- Crosshair drawing (modes 'crosshair' and 'both').
    crosshair = {
        gapBase   = 0.006,  -- centre gap, half-width, in screen fractions
        length    = 0.010,  -- length of each tick
        thickness = 0.0016, -- and its thickness
        colour    = { 235, 235, 235, 170 },
        dot       = true,   -- a centre dot, which stays put and gives the eye
                            -- Reticle wobble in screen fractions at zero skill (independent of maxDegrees, which is an angle). 0.011 is
        maxOffset = 0.011,
    },

    -- ms between aim nudges. 0 = every frame. Raise to 16 or 33 on low-end clients with camera stutter; above ~50 it reads as a jerk.
    stepMs = 0,

    -- Recoil moved to config/config_recoil.lua (Skills.Recoil).

    -- Print the computed sway factor once per second to F8. cl_sway always prints one boot line (mode and level-0 amplitude).
    debug = false,
}
