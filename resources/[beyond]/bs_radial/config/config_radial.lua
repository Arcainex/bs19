-- bs_radial - the wheel. One component for every menu (clothing, vehicles, attachments, ...); callers only differ in what they put in it.
-- Usage: local pick = exports.bs_radial:Open({ title = 'CLOTHING', items = { { id = 'hat', label = 'Hat', icon = 'hat' }, { id = 'jacket', label = 'Jacket', icon = 'jacket', disabled = true, note = 'not wearing one' }, { id = 'more', label = 'More', icon = 'dots', submenu = { ... } } } })
-- Open blocks until the player picks or cancels and returns the slice id (or nil), so the callback runs in the calling resource; functions do not cross resource boundaries.

Radial = {}

Radial.Settings = {
    -- Hold this to keep it open; releasing picks whatever is under the cursor.
    -- Set to nil for click-to-pick menus opened from code.
    holdToPick   = true,

    -- Fade in / out, ms.
    fadeIn       = 120,
    fadeOut      = 90,

    -- Blur the world behind it like the hub does. NUI cannot blur game pixels, so the game does it.
    blurWorld    = true,

    -- Nothing else may be open at the same time.
    exclusive    = true,

    -- Wheel geometry, in vh units.
    outerRadius  = 21.0,
    innerRadius  = 7.4,
    -- Dead zone in the middle: releasing here cancels rather than picking.
    deadZone     = 6.0,

    -- How long the wheel waits for the player before giving up, ms.
    timeout      = 30000,

    -- Screen position. 'centre' is the default. A caller can pass anchor = 'right' (or 'left') in its spec to keep half the screen clear (the weapon wheel does this). It only moves the wheel in CSS; slice hit-testing uses the wheel's own bounding box.
    anchor       = 'centre',
}

-- Icons: inline SVG paths, so there are no image files to stream. A slice names one of these; unknown names fall back to `dot`.
Radial.Icons = {
    dot      = 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
    hat      = 'M4 17h16M7 17V9a5 5 0 0 1 10 0v8',
    glasses  = 'M2 12h4m12 0h4M6 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0zm6 0a3 3 0 1 0 6 0 3 3 0 0 0-6 0z',
    mask     = 'M4 9c4-2 12-2 16 0v4c0 3-4 6-8 6s-8-3-8-6V9zM2 10v3m20-3v3',
    jacket   = 'M8 3l4 3 4-3 4 3-2 4v11H6V10L4 6l4-3zm4 3v15',
    shirt    = 'M8 3l4 2 4-2 4 3-2.5 3L17 21H7l-.5-12L4 6l4-3z',
    gloves   = 'M7 20V10a2 2 0 0 1 4 0V6a2 2 0 0 1 4 0v5m0-1a2 2 0 0 1 4 0v6a4 4 0 0 1-4 4H9',
    bag      = 'M6 8h12l-1 12H7L6 8zm3 0V6a3 3 0 0 1 6 0v2',
    vest     = 'M8 3l4 2 4-2 3 3v15H5V6l3-3zm4 2v16',
    shoe     = 'M3 17h13l4-3-2-3h-6l-3-3H3v9z',
    watch    = 'M9 3h6v3M9 18v3h6v-3M12 8v4l2 2M6 12a6 6 0 1 0 12 0 6 6 0 0 0-12 0z',

    engine   = 'M4 9h3l2-2h6l2 2h3v6h-3l-2 2H9l-2-2H4V9z',
    door     = 'M5 3h9l5 5v13H5V3zm9 0v5h5M9 13h1',
    boot     = 'M3 13h18v6H3v-6zm2-6h14l2 6H3l2-6z',
    lock     = 'M7 11V8a5 5 0 0 1 10 0v3M5 11h14v10H5V11z',
    unlock   = 'M7 11V8a5 5 0 0 1 9-3M5 11h14v10H5V11z',
    fuel     = 'M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16M4 12h10M17 8l3 3v7a2 2 0 0 1-4 0V6',
    wrench   = 'M15 3a5 5 0 0 0-4 8L3 19l2 2 8-8a5 5 0 0 0 6-6l-3 3-3-1-1-3 3-3z',

    weapon   = 'M3 10h13l3 3h2v3h-6l-2-2H8l-2 3H3v-7z',
    scope    = 'M12 4v3m0 10v3M4 12h3m10 0h3M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
    silencer = 'M2 10h10v4H2v-4zm10 1h9v2h-9',
    light    = 'M9 21h6M10 17h4a5 5 0 1 0-4 0zM12 2v2M4 8l1.5 1M20 8l-1.5 1',
    ammo     = 'M8 21h8V9l-4-6-4 6v12zM8 15h8',

    hand     = 'M8 13V5.5a1.5 1.5 0 0 1 3 0V12m0-1.5a1.5 1.5 0 0 1 3 0V12m0-1a1.5 1.5 0 0 1 3 0v5a5 5 0 0 1-5 5h-1a5 5 0 0 1-4.3-2.5L5 15.5a1.6 1.6 0 0 1 2.6-1.8L8 14',
    heart    = 'M12 20s-7-4.35-7-9a4 4 0 0 1 7-2.65A4 4 0 0 1 19 11c0 4.65-7 9-7 9z',
    gear     = 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2',
    key      = 'M14 4a5 5 0 1 1-4.6 6.9L3 17.3V21h4v-2h2v-2h2l1.4-1.4A5 5 0 0 1 14 4zm1.5 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z',
    scrap    = 'M4 8h16l-1.2 12H5.2L4 8zm5-3h6l1 3H8l1-3zM9.5 11v6m5-6v6',
    trunk    = 'M3 13h18v6H3v-6zm2-6h14l2 6H3l2-6zM9 16h6',
    tyre     = 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm0 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
    battery  = 'M3 9h18v10H3V9zm4 0V6h3v3m4 0V6h3v3M7 14h3m-1.5-1.5v3M14 14h3',
    refuel      = 'M3 19h9v-8H3v8zm3-8V7h5l2 3m3-5 3 3v8a2 2 0 0 1-4 0v-4m3 8c1.5-2 2-3 2-4 1.5 2 2 3 2 4a2 2 0 0 1-4 0z',
    siphon      = 'M4 9h10l1 11H3L4 9zm3 0V6h4v3m4-3c4-2 6 0 6 3v6m-3-1h4',
    inspect_car = 'M3 14l2-5h9l2 5M3 14h12v4H3v-4zm2 4v2m8-2v2M13 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm3 7 4 4',
    repair_all  = 'M4 4l6 6m4 4 6 6M3 3l3 1 1 3-3 1-1-2V3zm8 8 8-8 2 2-8 8m-2 2-7 7-2-2 7-7',
    duct_tape   = 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zm0 4a3 3 0 1 0 0 6 3 3 0 0 0 0-6zm7 3h3v9l-2-1-2 2-2-2',
    car_door    = 'M4 20V8l4-4h9l3 4v12H4zm0-10h16M8 7h5m2 9h3',
    bonnet      = 'M3 18h18v2H3v-2zm2 0 2-5h10l2 5M7 13 4 5l2-1 4 8m8 0 1 5',
    boot_lid    = 'M3 18h18v2H3v-2zm2 0 2-5h10l2 5M7 13 5 4h12l2 9m-10 4h4',
    window      = 'M4 5h16v12H4V5zm2 9h12M12 8v4m-3-3 3 3 3-3m-9 11h12',
    ignition    = 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm0 5a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm0 4v5m0-2h4',
    seat_swap   = 'M5 4v9h8v5H4v-4m1 6h11M14 7h7m-2-2 2 2-2 2m-5 4h7m-5-2-2 2 2 2',
    claim       = 'M9 8a4 4 0 1 0-3.7 5.5L3 16v4h4v-2h2l2-3M8 7h.1m5 10 2 2 5-5',
    key_give    = 'M4 17h5l3-2 3 1 5-2m-16 3-1 3h12l6-4M15 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0-3h5v3h-2',
    strip       = 'M3 15l2-5h11l2 5H3zm1 0v3h14v-3m-12 3v2m10-2v2M17 5l3 3m-4 4 5-5m-3-3 3 3m-2 11v3',
    fuel_pump   = 'M4 21V5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v16M4 21h12M6 7h7v5H6V7zm9 0 4 3v8a2 2 0 0 0 4 0v-5m-4-3 2-2',
    grip        = 'M3 7h18v3H3V7zm6 3v11h6V10m-8 4h10m-8 4h6',
    weapon_light= 'M3 9h10l3 3-3 3H3V9zm13 1 5-3m-5 5h6m-6 2 5 3',
    laser       = 'M3 9h9v6H3V9zm9 2h3m2 1h1m2 0h2M5 12h4',
    magazine    = 'M7 4h10v12c0 3-4 5-8 5V8H7V4zm3 3h4m-2-3V2',
    inspect     = 'M3 7c3-3 7-3 10 0 2 2 4 4 8 5-3 4-7 5-10 3-3-1-5-4-8-8zm8 1a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM4 19h12l2 2h3',
    emote       = 'M13 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm-1 5-3 5 4 2 3-4m-3 4-4 6m4-6 6 5M10 9 5 7m10 1 4-4',
    walk        = 'M7 4a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM4 10c0-2 5-2 6 0l1 3-2 3-3-1-2-5zm11 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm-2 6c1-2 5-2 6 0l1 2h-7v-2',
    face        = 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM8 10h.1m8 0h.1M8 15c2 3 6 3 8 0',
    close       = 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM9 9l6 6m0-6-6 6',
    needs       = 'M5 3v8m3-8v8M2 3v6a4 4 0 0 0 8 0V3M6 13v8m12-17c-2 4-4 6-4 10a4 4 0 0 0 8 0c0-4-2-6-4-10z',
    pee         = 'M4 4h10v7a5 5 0 0 1-5 5H4V4zm10 3h4v4a4 4 0 0 1-4 4m-8 1v4h12M3 20h16',
    poop        = 'M9 4h7v5H9V4zm7 1a6 6 0 0 1 0 12H9a6 6 0 0 1 0-12m0 12v3h9m-7-11v4m3-4v4',
    warn        = 'M12 3 2 21h20L12 3zm0 6v6m0 3h.1',
    back     = 'M11 5l-7 7 7 7M4 12h16',
    dots     = 'M6 12a1 1 0 1 0 2 0 1 1 0 0 0-2 0zm5 0a1 1 0 1 0 2 0 1 1 0 0 0-2 0zm5 0a1 1 0 1 0 2 0 1 1 0 0 0-2 0z',
}
