-- Bodycam view. Players opt in under ESC > Settings > Camera; staff can forbid it in F1.

Bodycam = {
    allowed = true,                -- F1: players may turn the bodycam on

    -- Camera mount, metres from the chest bone in body space (x right, y forward, z up)
    bone = 24818,                  -- SKEL_Spine3 (24817 = SKEL_Spine2)
    offset = { x = 0.0, y = 0.36, z = 0.14 },   -- in front of the vest, not inside it
    pitch = -8.0,                                -- look slightly down so the held weapon shows at the bottom
    lag = 14.0,                    -- how fast the mount catches up with the body (higher = stiffer)
    maxLag = 0.08,                 -- metres the mount may trail behind
    nearClip = 0.18,   -- clips straps and collars that sit right in front of the lens

    -- Looking around: past this many degrees from the chest the body turns with you
    yawClamp = 70.0,

    -- Aiming: the view rises to the sights unless the player picked realistic aim
    aimFov = 62.0,
    aimSpeed = 9.0,
    aimOffset = { side = 0.05, forward = 0.10, up = 0.0 },   -- from the head bone, along the look direction
    nativeScopes = true,           -- snipers use the normal scope while aiming

    -- Motion (scaled by the player's motion setting)
    bob = { walk = 0.010, run = 0.022, sprint = 0.034 },
    strafeRoll = 4.0,              -- degrees at full strafe speed
    landing = 0.08,                -- metres of dip on a hard landing

    -- Shake (scaled by the player's shake setting)
    handShake = 0.30,
    hitShake = 0.10,               -- your melee hits
    damageShake = 0.35,            -- at 40+ damage in one go
    grabShake = 0.45,              -- a walker grabs you
    shotShake = 0.04,

    -- Colour grade. Skipped while another script has its own filter running.
    timecycle = 'CAMERA_secuirity',

    -- Overlay stamp
    stampLabel = 'BS19 CAM',

    -- Turn off while a parkour move runs, even if it leaves the camera alone
    pauseOnParkour = false,
}
