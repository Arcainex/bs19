-- bs_cinecam - config. Everything here is a default. Menu changes are saved per client (KVP), so editing a value only changes fresh installs. Use "Reset to defaults" in the menu to pull these back in.

Cine = {}

Cine.Settings = {
    -- The command is what RegisterKeyMapping binds. The key is only the default: once bound, FiveM remembers the player's choice.
    openCommand = 'bs_cinecam',
    openKey     = 'F3',

    -- F3 is unused by this framework (F7 VIP panel, F10 staff menu, F8 FiveM console, F5/F6 often taken by other resources). If you rebind, avoid F1-F4 in the pause menu context.

    -- Who may fly the camera. A free camera is a wallhack in a survival game, so this is checked server-side on entering.
    aces = { 'bs.admin', 'bs.superadmin', 'command' },

    -- Set false to let anyone use it (test servers only).
    requirePermission = true,

    -- Raw key codes, used only while the camera is flying. All controls are disabled in cinematic mode (including key mappings), so these read the keyboard below the control system.
    -- They are Windows virtual-key codes and do not follow rebinds made in the FiveM key-binding menu. If you rebind the menu key, change rawMenu to match.
    -- 0x72 = F3, 0x2E = DELETE.
    rawMenu = 0x72,
    rawExit = 0x2E,   -- emergency: leave the camera outright
}

-- Camera defaults

Cine.Defaults = {
    -- movement
    speed         = 6.0,     -- metres/second at neutral throttle
    fastMult      = 4.0,     -- LSHIFT
    slowMult      = 0.2,     -- LCTRL

    -- Smoothing. Values are time constants in seconds, not per-frame blend factors, so the feel is frame-rate independent (about 63% of the way to the target in that many seconds).
    -- 0.0 = no smoothing, 0.2-0.4 = handheld but steady, 0.8+ = heavy dolly.
    moveSmooth    = 0.35,    -- seconds; position/velocity easing
    lookSmooth    = 0.22,    -- seconds; mouse-look easing
    fovSmooth     = 0.30,    -- seconds; zoom easing
    rollSmooth    = 0.40,    -- seconds; dutch-angle easing

    -- optics
    fov           = 50.0,    -- degrees; GTA's gameplay camera sits near 50
    fovMin        = 6.0,
    fovMax        = 110.0,
    roll          = 0.0,     -- dutch angle, degrees

    -- Look speed is scaled by FOV: at 10 degrees the same mouse movement sweeps five times more of the frame than at 50, which makes slow pans unusable otherwise.
    sensitivity   = 1.0,
    scaleLookByFov = true,
    invertY       = false,

    -- dof
    dofEnabled    = false,
    dofNear       = 0.6,     -- metres; anything nearer blurs
    dofFar        = 25.0,    -- metres; anything further blurs
    dofStrength   = 1.0,     -- 0-1

    -- grade

    -- The shot's own color grade, separate from the player's filter (bs_ui UI.Filters). Applied only while flying, restored on landing.
    -- '' means leave the player's filter alone (not the same as 'off'). The picker is built from bs_ui's list at runtime.
    filter         = '',
    filterStrength = 0.8,

    -- world
    timescale     = 1.0,     -- 0.05 - 1.0; slow motion
    hideHud       = true,    -- hide framework HUD + radar while flying

    -- false: entering cinematic mode disables every control (no menu, emote, inventory or weapon keys).
    -- true: only the controls the camera needs are taken, so normal keybinds still work (useful for filming a menu).
    allowMenuHotkeys = false,

    -- Collision off lets the camera fly through walls and terrain: good for establishing shots, bad for handheld follow.
    collide       = false,

    -- limits
    -- The camera will not go below this. The world streams badly under the map and the ocean floor renders black.
    minZ          = -220.0,
    maxZ          = 2200.0,
}

-- Path playback

Cine.Path = {
    -- Seconds the whole path takes from first to last keyframe.
    duration   = 12.0,
    loop       = false,

    -- Ease in/out over this fraction of the run at each end. 0 = constant speed with abrupt start/stop, 0.5 = full sine ease.
    ease       = 0.25,

    -- A Catmull-Rom spline needs a point before the first and after the last for its tangents. Both are mirrored, so a two-keyframe path is a straight line and three or more curve.
    maxNodes   = 64,
}

-- Presets offered in the menu

Cine.Presets = {
    { label = 'Snap (no smoothing)',
      patch = { moveSmooth = 0.0,  lookSmooth = 0.0,  fovSmooth = 0.1, speed = 8.0 } },

    { label = 'Handheld',
      patch = { moveSmooth = 0.18, lookSmooth = 0.14, fovSmooth = 0.25, speed = 4.0 } },

    { label = 'Dolly',
      patch = { moveSmooth = 0.55, lookSmooth = 0.45, fovSmooth = 0.5,  speed = 3.0 } },

    { label = 'Crane (heavy)',
      patch = { moveSmooth = 1.1,  lookSmooth = 0.8,  fovSmooth = 0.8,  speed = 9.0 } },

    { label = 'Long lens',
      patch = { fov = 18.0, moveSmooth = 0.7, lookSmooth = 0.6, sensitivity = 0.6 } },

    { label = 'Wide establishing',
      patch = { fov = 78.0, moveSmooth = 0.5, lookSmooth = 0.35, speed = 14.0 } },
}
