-- bs_skills - non-perk abilities (dodge and weapon sway). Both scale continuously with a skill level, so they live here next to the trees rather than in Skills.Trees, and read the level from this resource's client cache.
-- Load order: config_skills.lua declares `Skills = {}`, so this file must come after it in the fxmanifest shared_scripts or every tunable here becomes nil.

Skills = Skills or {}

-- The dodge

-- Shift + double-tap a movement key to throw yourself that way. Scales with the `survival` tree (the break_fall perk, same tree, also counts as a bonus; see perkBonus).
Skills.Dodge = {
    enabled = true,

    -- Survival tree level needed before the dodge works (skill tree level, not character level). Default 0 so it works out of the box and the level only improves quality. Raise it (e.g. 4) to lock it; the refusal is shown on screen.
    minLevel = 0,

    -- ms allowed between the two taps. 420 matches bs_emotes' double-tap jump. Under ~250 is hard to hit, over ~600 normal strafing triggers a dodge.
    doubleTapMs = 420,

    -- Stamina cost at minimum skill, instant (0-100 scale). 22 is about four dodges from full. Below `staminaFloor` an untrained character is refused.
    staminaCost  = 22.0,
    staminaFloor = 15.0,

    -- Stamina cost at max survival level; interpolated linearly from minLevel to the tree's maxLevel.
    staminaCostAtMax = 9.0,

    -- Cooldown in ms at minimum skill (here) and at max, interpolated the same way. 1600 makes a dodge a decision; 700 lets a trained character chain two.
    cooldownMs      = 1600,
    cooldownMsAtMax = 700,

    -- Push speed in m/s, min skill -> max. 7.0 covers about 3m, 9.5 about 4m. Keep under ~12 or the ped slides and clips through thin geometry.
    speed      = 7.0,
    speedAtMax = 9.5,

    -- ms the push is applied (the window where the player is not fully in control; not the animation length). Keep it short, 340 is about one long step.
    pushMs = 340,

    -- Roll timing. Controls stay locked for the full clip length (GetAnimDuration of p1, plus the p2 get-up when playGetUp is on).
    playGetUp     = true,  -- chain combatroll_*_p2_* after p1
    p1Portion     = 1.0,   -- fraction of p1 to play before p2 starts
    chainOverlapMs = 60,   -- start p2 this much before p1 ends
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

    -- Which animation tiers are acceptable:
    -- 'roll' (default) - combat roll first, then melee slips, then no clip.
    -- 'sidestep' - melee slips only (less acrobatic).
    -- 'none' - never play a clip; pure fast movement.
    -- Anything else is treated as 'roll'.
    animStyle = 'roll',

    -- Set true if left and right dodges come out reversed. Swaps the two sideways clips after the probe; movement itself is unaffected. Restart the resource.
    mirrorSides = false,

    -- Hold the ped's facing during the push. Roll clips rotate the body, so without this the player ends up facing a random way. Set false to allow free turning mid-dodge.
    lockHeading = true,

    -- Allow dodging while aiming down sights. Off by default: A/D are strafe keys while aiming (accidental triggers), SHIFT is already used by bs_weapons (SHIFT+R), and the push yanks the aim. A melee-heavy server may want it on.
    allowWhileAiming = false,

    -- Tell the player why a dodge was refused (level, stamina, cooldown, aiming), rate-limited. Obvious cases (in a vehicle, in a menu, dead) stay quiet; see `quietReasons` in cl_dodge.lua. Set false for silence.
    announceRefusals = true,

    -- ms minimum gap between two refusal notifications.
    announceCooldownMs = 2500,

    -- Print the resolved animation and each refused dodge to F8. Useful on a new build. cl_dodge.lua and cl_sway.lua always print one boot line regardless.
    debug = false,
}

-- Weapon sway

-- Weapon sway: the lower the skill, the more the aim wanders. Uses the `combat` tree.
-- The camera's relative pitch and heading get a small per-frame delta, so mouse input is untouched and the total stays bounded. ShakeGameplayCam is not used (shakes the whole view, causes motion sickness).
Skills.Sway = {
    enabled = true,

    -- Which tree steadies your hands (so re-cut trees do not need cl_sway.lua edits).
    tree = 'combat',

    -- 'aim' - nudge the point of aim only (in third person the horizontal part is mostly absorbed by the game camera, so it can be barely visible).
    -- 'crosshair' - aim untouched, only the reticle wobbles (cosmetic, gentlest).
    -- 'both' (default) - reticle follows the real aim error.
    -- Use /skilltest while aiming to see the resolved amplitude.
    mode = 'both',

    -- Peak aim excursion in degrees at zero combat skill (how far the muzzle can be from where you pointed). 1.8 is about 3cm at 1m.
    -- This is the nausea dial: past ~2.5 it reads as broken. The horizontal part is largely eaten by the aim camera, so the vertical part (see verticalRatio) carries the effect, with the drawn reticle showing the error.
    maxDegrees = 1.8,

    -- Combat level where sway reaches exactly zero. Must be <= the combat tree's maxLevel or it never fully clears.
    zeroAtLevel = 20,

    -- Falloff shape. 1.0 = linear (level 10 of 20 = half the sway). Above 1 the sway drops fast at first, so early levels feel like a real improvement.
    curve = 1.6,

    -- Fraction removed from the remaining sway when the `steady_hands` perk is owned.
    perkBonus = 0.30,

    -- Wander speed in cycles per second for the two layers. Two slow sines read as a living hand; one is a metronome, random is a vibration. Keep both under ~1.5 or it becomes a tremor.
    slowHz = 0.31,
    fastHz = 0.79,

    -- Vertical excursion as a fraction of horizontal. Below 1.0 because a real hold wanders more sideways; raised to 0.85 because the vertical axis survives the camera best. First number to lower if players feel discomfort.
    verticalRatio = 0.85,

    -- Multipliers on top of the skill-derived amount. Set all to 1.0 for skill-only sway.
    movingMultiplier = 1.8,   -- walking or running while aiming
    crouchMultiplier = 0.65,  -- a braced, low stance is steadier
    windedMultiplier = 1.6,   -- at zero stamina; scales in from `windedFrom`
    windedFrom       = 25.0,  -- stamina at which the winded penalty starts

    -- Crosshair drawing (modes 'crosshair' and 'both'). Drawn with DrawRect instead of NUI so it moves at frame rate. Sizes are fractions of the screen (resolution independent).
    crosshair = {
        gapBase   = 0.006,  -- centre gap, half-width, in screen fractions
        length    = 0.010,  -- length of each tick
        thickness = 0.0016, -- and its thickness
        colour    = { 235, 235, 235, 170 },
        dot       = true,   -- a centre dot, which stays put and gives the eye
                            -- Reticle wobble in screen fractions at zero skill (independent of maxDegrees, which is an angle). 0.011 is about 1cm on a 1080p screen.
        maxOffset = 0.011,
    },

    -- ms between aim nudges. 0 = every frame. Raise to 16 or 33 on low-end clients with camera stutter; above ~50 it reads as a jerk.
    stepMs = 0,

    -- Recoil moved to config/config_recoil.lua (Skills.Recoil).

    -- Print the computed sway factor once per second to F8. cl_sway always prints one boot line (mode and level-0 amplitude).
    debug = false,
}
