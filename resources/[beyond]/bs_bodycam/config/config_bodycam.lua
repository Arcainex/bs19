-- Bodycam view. Players opt in under ESC > Settings > Camera; staff can forbid it in F1.
-- Built on GTA's own first-person camera: it already draws the first-person arms and weapon,
-- hides the head and body from the inside, and keeps sights and recoil exact.
-- A scripted camera can't do that: the moment one renders, GTA draws the full third-person
-- body around the lens. The bodycam look is added on top: shake, jolts, colour grade and the lens overlay.

Bodycam = {
    allowed = true,                -- F1: players may turn the bodycam on

    -- Hand shake (scaled by the player's shake setting), multiplied while a walker holds you
    handShake = 0.35,
    grabbedMult = 3.0,
    aimShakeMult = 0.4,            -- steadier on the sights

    -- Body motion (scaled by the player's motion setting), added to the hand shake by gait
    moveShake = { walk = 0.35, run = 0.75, sprint = 1.25 },

    -- One-off jolts (scaled by the shake setting)
    landShake = 0.35,              -- hard landing, at one second of fall or more
    hitShake = 0.12,               -- your melee hits
    damageShake = 0.40,            -- at 40+ damage in one go
    grabShake = 0.25,              -- a walker grabs you (medium explosion shake)

    -- Colour grade. Skipped while another script has its own filter running.
    timecycle = 'CAMERA_secuirity',

    -- Overlay stamp
    stampLabel = 'BS19 CAM',

    -- Keep the view while driving when the player picked "Bodycam in vehicles"
    vehicleFirstPerson = true,
}
