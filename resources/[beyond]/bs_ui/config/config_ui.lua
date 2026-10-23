-- bs_ui - HUD defaults. Entries marked player-overridable can be changed in inventory -> Settings and are saved per character; these are the starting values.

UI = {}

UI.Settings = {
    hudEnabled      = true,
    hudPushRate     = 200,          -- ms between state pushes to the NUI
    hideInCutscene  = true,
    scale           = 1.0,
    currencySymbol  = '$',

    -- Player-overridable.
    -- 'full' = everything, with labels and identity line
    -- 'minimal' = icons and bars only, no panel
    hudMode         = 'full',
    -- Where the survival cluster sits: 'bottom-left' | 'bottom-right'
    hudAnchor       = 'bottom-left',
    -- 0.0 fully transparent, 1.0 solid. Applies to panel backgrounds.
    hudOpacity      = 0.72,
    -- Hide a bar while it is full, so a healthy player sees almost nothing.
    hideWhenFull    = false,

    -- Zombie voice volume, 0.0 to 1.0. Default 0.15 on purpose: the voices are 3D sources (up to twelve at once) and at full volume a street of walkers is a wall of noise. At 0.15 you hear one zombie from a direction before you see it. The player's slider (Settings -> zombieVoiceVolume) still spans 0-1 and overrides this.
    zombieVoiceVolume = 0.15,
}

-- 3D audio engine: settings for the Web Audio spatialiser in html/js/sound.js (HRTF panner, listener follows the camera). Pushed to the page once when bs_ui starts, so changes need `restart bs_ui`.
-- Hitmarkers, level-up sting, level music and other feedback sounds are not spatialised on purpose.
UI.Audio = {
    -- 'HRTF' or 'equalpower'. HRTF can place a sound behind, above or below you; equalpower is left/right only and cheaper per voice. If the client refuses HRTF it logs once and falls back. Use equalpower only on very low-end clients.
    panningModel  = 'HRTF',

    -- 'inverse' | 'linear' | 'exponential': how loudness falls with distance. 'inverse' (1/distance) is the default and keeps sounds present mid-range; 'linear' reaches zero at maxDistance (sounds like a fader); 'exponential' drops off too fast up close. 'inverse' never reaches zero, so maxDistance is also a hard cull on the Lua side.
    distanceModel = 'inverse',

    -- Metres inside which a sound is at full volume (3 is roughly 'in the room'). Lower = walkers get shrill as they close; higher = nearby sounds flatten.
    refDistance   = 3.0,

    -- Falloff speed past refDistance. 1.0 is physically correct, 1.1 is slightly tighter. Raise toward 1.6 if the world sounds crowded, lower toward 0.8 if sounds vanish too fast.
    rolloffFactor = 1.1,

    -- Default audible radius in metres for callers that do not set their own. Nothing beyond it is sent to the page. Individual sounds override it (lurk voice 34 m, feeding 30 m, see Zombies.Voices).
    maxDistance   = 45.0,

    -- Max world sounds audible at once. HRTF has a cost and too many growls turn into noise. When full, the farthest voice is dropped, not the newest, so a close walker is never starved out. Enforced here and again in the page.
    maxVoices     = 12,

    -- Max feedback sounds at once. Counted separately and never spatialised, so a horde cannot drown out hitmarkers.
    maxUiVoices   = 6,

    -- Default stop fade in ms, used when a caller gives none. A hard cut clicks; 120 removes it. Death uses its own longer fade (Zombies.Voices.deathFade).
    defaultFadeMs = 120,

    -- How often a moving emitter's position is re-sent, in ms. The page interpolates between updates. 150 is smooth; above ~400 the sound starts to skate.
    moveInterval  = 150,

    -- How often the listener is pushed while nothing is playing, in ms. While sounds play it updates every frame.
    listenerIdleInterval = 500,

    -- Safety net in ms: a source still marked as playing after this long is dropped (covers a lost 'finished' callback after a reload or restart). Must exceed the longest clip in bs_ui/html/sound/ (eating files are up to ~20 s). Raise it if you add longer sounds.
    voiceTimeout  = 30000,
}

-- Notifications.
-- Screen filters: a personal look (grain, vignette, tint, desaturation) chosen in Settings, stored on the character, visible only to that player. No gameplay effect, so no 'clear fog' preset.
-- Two layers: `timecycle` (changes game rendering; candidate names are probed at runtime, a preset whose names all fail just loses its grade) and `overlay` (HUD-page layer for grain, vignette, tint, scanlines).
-- Fields: id (stored), label/note (Settings), tc (timecycle names, best first), strength 0-1, grain 0-1, vignette 0-1, tint { r, g, b, a } (keep a low), scanlines 0-1 (VHS only).
-- Add presets freely; the picker is built from this list.
UI.Filters = {
    {
        id = 'off', label = 'None', note = 'The world as the server renders it.',
    },
    {
        id = 'stock', label = 'Film Stock',
        note = 'Grain and a soft vignette. The default if you want one.',
        tc = { 'NG_filmic01', 'MP_corona_heist', 'hud_def_desat_Neutral' }, strength = 0.35,
        grain = 0.45, vignette = 0.30,
        tint = { r = 232, g = 214, b = 184, a = 0.05 },
    },
    {
        id = 'bleak', label = 'Bleak',
        note = 'Cold and washed out. Everything looks like February.',
        tc = { 'hud_def_desat_Neutral', 'prologue_reflection_hack' }, strength = 0.55,
        grain = 0.30, vignette = 0.35,
        tint = { r = 150, g = 176, b = 200, a = 0.10 },
    },
    {
        id = 'ash', label = 'Ash',
        note = 'Warm dust in the air, like the light after a fire.',
        tc = { 'NG_filmic10', 'MP_corona_tournament', 'hud_def_desat_Neutral' }, strength = 0.48,
        grain = 0.40, vignette = 0.30,
        tint = { r = 214, g = 150, b = 92, a = 0.12 },
    },
    {
        id = 'toxic', label = 'Toxic',
        note = 'A sick green cast. Unpleasant on purpose.',
        tc = { 'NG_filmic16', 'MP_Bull_tost', 'hud_def_desat_Neutral' }, strength = 0.42,
        grain = 0.35, vignette = 0.40,
        tint = { r = 120, g = 190, b = 110, a = 0.13 },
    },
    {
        id = 'noir', label = 'Noir',
        note = 'Black and white, hard vignette, heavy grain.',
        tc = { 'CAMERA_BW', 'phone_cam11', 'hud_def_desat_Neutral' }, strength = 1.0,
        grain = 0.60, vignette = 0.55,
    },
    {
        id = 'vhs', label = 'VHS',
        note = 'Scanlines and noise. Best in small doses.',
        grain = 0.70, vignette = 0.45, scanlines = 0.55,
        tint = { r = 120, g = 130, b = 190, a = 0.07 },
    },
    {
        id = 'gold', label = 'Golden Hour',
        note = 'Warm and bright at the edges, low grain.',
        tc = { 'NG_filmic06', 'MP_corona_heist', 'hud_def_desat_Neutral' }, strength = 0.30,
        grain = 0.18, vignette = 0.18,
        tint = { r = 255, g = 196, b = 120, a = 0.09 },
    },
    {
        id = 'dust', label = 'Dust',
        note = 'Dry air, faded colour and a hard road ahead.',
        tc = { 'NG_filmic13', 'MP_corona_tournament', 'hud_def_desat_Neutral' }, strength = 0.52,
        grain = 0.28, vignette = 0.32,
        tint = { r = 198, g = 164, b = 112, a = 0.10 },
    },
    {
        id = 'storm', label = 'Storm',
        note = 'Cold skies and the feeling that rain is coming.',
        tc = { 'NG_filmic18', 'MP_corona_switch', 'hud_def_desat_Neutral' }, strength = 0.52,
        grain = 0.24, vignette = 0.42,
        tint = { r = 112, g = 136, b = 164, a = 0.10 },
    },
    {
        id = 'decay', label = 'Decay',
        note = 'Faded colour, old film and a world left behind.',
        tc = { 'NG_filmic22', 'hud_def_desat_Neutral' }, strength = 0.62,
        grain = 0.46, vignette = 0.46,
        tint = { r = 144, g = 124, b = 94, a = 0.08 },
    },
    {
        id = 'outbreak', label = 'Outbreak',
        note = 'Sickly light and a little too much static.',
        tc = { 'NG_filmic29', 'MP_Bull_tost', 'hud_def_desat_Neutral' }, strength = 0.58,
        grain = 0.52, vignette = 0.44, scanlines = 0.14,
        tint = { r = 132, g = 164, b = 102, a = 0.12 },
    },
}

-- Overall filter strength, 0-1, on top of the preset's own values. Lets a player keep a look but turn it down.
UI.FilterDefaults = {
    filter         = 'off',
    filterStrength = 0.8,
}

UI.Notifications = {
    -- Long enough to read a short sentence, short enough not to stack up
    -- during a fight.
    defaultDuration = 3200,
}

UI.XPBar = {
    enabled     = true,
    -- PLAYER-OVERRIDABLE: 'top' | 'bottom'
    position    = 'top',
    -- 0.0 - 1.0, independent of the survival cluster.
    opacity     = 0.55,
    -- How wide the strip is, as a percentage of the screen.
    width       = 46,
    -- Show a floating "+25 XP" every time XP is awarded.
    popups      = true,
    popupDuration = 2200,
    -- Fade the whole bar out when nothing has happened for this long (ms).
    -- 0 keeps it on screen permanently.
    idleFade    = 0,
}

UI.Minimap = {
    -- Live corner map: off on purpose. This is a survival game, the field map (M) is the only map. Set to true for the corner radar; everything it needs is built.
    alwaysHidden    = true,
    showWithInventory = false,

    -- Corner map zoom. GTA's default is too tight, 1100 shows too much; this is a middle value.
    zoom            = 900,
}

-- The field map: a large stylised version of the vanilla map (GTA's expanded bigmap radar, see HudSetBigmap in cl_hud.lua), framed like a journal page. Gameplay keeps running underneath.
UI.FieldMap = {
    key     = 'M',
    command = 'bs_fieldmap',

    -- Which map the M key opens.
    -- 'pause' - GTA's full map as in the pause menu (zoom, legend, blips, waypoints). No paper frame.
    -- 'radar' - the corner radar enlarged into a framed box. The vanilla radar is semi-transparent and its terrain fill does not scale up, so it looks like road lines floating over the world; blur and a backing only help so much.
    -- Set to 'radar' if you prefer the frame.
    mode         = 'pause',

    -- Field map readability. The map itself is GTA's and cannot be redrawn, so two layers sit between it and the world:
    --   blurWorld - blurs the game behind the map (TriggerScreenblur, like the radial wheel; NUI cannot do this)
    --   backing - a dark rectangle under the map area
    -- `backingAlpha` is 0..255. If the backing draws over the map on your build, set backing = false and keep the blur.
    blurWorld    = true,
    backing      = true,
    backingAlpha = 214,

    -- Starting zoom. Lower is more zoomed in; the scroll wheel moves it.
    zoom         = 460.0,
}

UI.Theme = {
    accent          = '#c8763a',    -- amber: the world telling you something
    accentGood      = '#7fd4a2',
    accentDanger    = '#b4574a',
    accentWarn      = '#d9a441',
    background      = '#0a0a09',
    text            = '#d8d2c2',
    textMuted       = '#6f6a5c',
    blood           = '#6e2b21',
    radius          = '2px',
    fontMono        = "'Courier New', 'Consolas', monospace",
    fontSerif       = "'Times New Roman', Georgia, serif",
}

--- The survival bars, in display order. `critical` drives the pulsing warning.
UI.Bars = {
    { key = 'health',    label = 'Health',    color = '#b4574a', icon = 'heart',  show = true,  critical = 25 },
    { key = 'armour',    label = 'Armour',    color = '#5b7d9d', icon = 'shield', show = true,  critical = 0, hideAtZero = true },
    { key = 'stamina',   label = 'Stamina',   color = '#7fd4a2', icon = 'bolt',   show = true,  critical = 15 },
    { key = 'hunger',    label = 'Hunger',    color = '#d99b5b', icon = 'food',   show = true,  critical = 20 },
    { key = 'thirst',    label = 'Thirst',    color = '#5bc8d9', icon = 'drop',   show = true,  critical = 20 },
    -- Infection fills UP, so its warning is inverted: high is bad.
    { key = 'infection', label = 'Infection', color = '#8d6bb0', icon = 'virus',  show = true,  critical = 60, inverted = true, hideAtZero = true },
}

--- Which bars survive in minimal mode.
UI.MinimalBars = { 'health', 'stamina', 'infection' }

-- Panels the HUD hides itself for. A full-screen NUI panel already shows name, class, hunger, thirst and cash, so the survival cluster underneath would duplicate it.
-- Keyed by the panel name passed to TriggerEvent('bs:ui:opened', <name>); the value is the resource that owns the panel, used by cl_hud.lua's watchdog in case that resource stops while its panel is open.
-- Not listed on purpose: fieldmap (gameplay continues, the HUD belongs there) and radial (brief, flickering the HUD would be worse).
-- Add a panel by name only; both ends already use bs:ui:opened/closed.
UI.HideHudFor = {
    inventory = 'bs_inventory',
    menu      = 'bs_menu',
    vip       = 'bs_vip',
    admin     = 'bs_admin',

    -- Not a panel: bs_cinecam fires this pair around /hidehud and cinematic camera mode, so a clean screen goes through the same latch as real panels (including release on death, character switch and bs_cinecam stopping).
    cinecam   = 'bs_cinecam',

    -- bs_gadgets fires this pair while flying the scout drone
    drone     = 'bs_gadgets',

    -- bs_tutorial tour: a clean screen while the camera flies
    tutorial  = 'bs_tutorial',
}

--- Status HUD looks. `vip` styles lock for non-VIP players; with the VIP system off (bs_vip) everyone counts as VIP.
UI.HudStyles = {
    { id = 'classic', label = 'Classic' },
    { id = 'slim',    label = 'Slim' },
    { id = 'blocks',  label = 'Blocks' },
    { id = 'capsule', label = 'Capsule' },
    { id = 'glow',    label = 'Glow',  vip = true },
    { id = 'plate',   label = 'Plate', vip = true },
}

--- Menu palettes. `vars` are hex colours pushed to every NUI through bs_ui/html/shared/palette.js:
--- accent, hi (accent highlight), bg, text, muted, blood. 'default' keeps each menu's own colours.
UI.Palettes = {
    { id = 'default', label = 'Rust', sw = { '#e08c46', '#0a0a09', '#f0ebdd' } },
    { id = 'frost',   label = 'Frost',   vars = { accent = '#5fa8d3', hi = '#8cc6e8', bg = '#090c0e', text = '#e6eef2', muted = '#8fa0aa', blood = '#2b4a6e' } },
    { id = 'verdant', label = 'Verdant', vars = { accent = '#7fb069', hi = '#a3cf8d', bg = '#0a0c09', text = '#e9efdf', muted = '#9aa58c', blood = '#2f4a2a' } },
    { id = 'crimson', label = 'Crimson', vars = { accent = '#c4493d', hi = '#e0685a', bg = '#0c0909', text = '#f0e4e0', muted = '#a89490', blood = '#7a1f1a' } },
    { id = 'royal',   label = 'Royal',   vip = true, vars = { accent = '#a074d6', hi = '#bf9ae8', bg = '#0b090e', text = '#efe9f5', muted = '#a39aae', blood = '#4a2a6e' } },
    { id = 'aurum',   label = 'Aurum',   vip = true, vars = { accent = '#e0b341', hi = '#f2cf6e', bg = '#0d0b07', text = '#f5edd8', muted = '#b0a584', blood = '#6e5a21' } },
}
