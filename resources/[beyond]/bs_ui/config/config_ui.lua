-- bs_ui - HUD defaults: entries marked player-overridable can be changed in inventory to Settings and are saved

UI = {}

UI.Settings = {
    hudEnabled      = true,
    hudProvider     = 'auto',       -- auto hides this HUD when a supported replacement is running
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

    -- Zombie voice volume, 0.0 to 1.0.
    zombieVoiceVolume = 0.15,
}

-- 3D audio engine: settings for the Web Audio spatialiser in html/js/sound.js (HRTF panner, listener follows the camera).
UI.Audio = {
    -- 'HRTF' or 'equalpower': hRTF can place a sound behind, above or below you
    panningModel  = 'HRTF',

    -- 'inverse' | 'linear' | 'exponential': how loudness falls with distance. 'inverse' (1/distance) is the default
    distanceModel = 'inverse',

    -- Metres inside which a sound is at full volume (3 is roughly 'in the room'). Lower = walkers get shrill as they close; higher = nearby sounds flatten.
    refDistance   = 3.0,

    -- Falloff speed past refDistance. 1.0 is physically correct, 1.1 is slightly tighter.
    rolloffFactor = 1.1,

    -- Default audible radius in metres for callers that do not set their own. Nothing beyond it is sent to the page.
    maxDistance   = 45.0,

    -- Max world sounds audible at once. HRTF has a cost and too many growls turn into noise.
    maxVoices     = 12,

    -- Max feedback sounds at once. Counted separately and never spatialised, so a horde cannot drown out hitmarkers.
    maxUiVoices   = 6,

    -- Default stop fade in ms, used when a caller gives none. A hard cut clicks; 120 removes it.
    defaultFadeMs = 120,

    -- How often a moving emitter's position is re-sent, in ms.
    moveInterval  = 150,

    -- How often the listener is pushed while nothing is playing, in ms. While sounds play it updates every frame.
    listenerIdleInterval = 500,

    -- Safety net in ms: a source still marked as playing after this long is dropped
    voiceTimeout  = 30000,
}

-- Notifications: screen filters: a personal look (grain, vignette, tint, desaturation) chosen in Settings
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
    -- Long enough to read a short sentence, short enough not to stack up during a fight.
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
    -- Fade the whole bar out when nothing has happened for this long (ms). 0 keeps it on screen permanently.
    idleFade    = 0,
}

UI.Minimap = {
    -- Live corner map: off: this is a survival game, the field map (M) is the only map.
    alwaysHidden    = true,
    showWithInventory = false,

    -- Corner map zoom. GTA's default is too tight, 1100 shows too much; this is a middle value.
    zoom            = 900,
}

-- The field map: a large stylised version of the vanilla map
UI.FieldMap = {
    key     = 'M',
    command = 'bs_fieldmap',

    -- Which map the M key opens. 'pause' - GTA's full map as in the pause menu (zoom, legend, blips, waypoints).
    mode         = 'pause',

    -- Field map readability. The map itself is GTA's and cannot be redrawn, so two layers sit between it and the world:
    -- blurWorld - blurs the game behind the map (TriggerScreenblur, like the radial wheel; NUI cannot do this)
    -- backing - a dark rectangle under the map area
    -- `backingAlpha` is 0..255. If the backing draws over the map on your build, set backing = false and keep the blur.
    blurWorld    = true,
    backing      = true,
    backingAlpha = 214,

    -- Starting zoom. Lower is more zoomed in; the scroll wheel moves it.
    zoom         = 460.0,
}

-- UI theme pack for every NUI page: 'dossier' (default), 'classic', 'fieldradio', 'rustbelt', 'quarantine' or 'nightops'. F1 > Themes & UI can override it.
UI.ThemePack = 'classic'

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
    -- How far your last sound carried (bs_zombies noise event). Value reads in metres; never pulses.
    { key = 'noise',     label = 'Noise',     color = '#c9a35a', icon = 'sound',  show = true,  critical = 101, inverted = true, unit = 'm' },
    -- Infection fills UP, so its warning is inverted: high is bad.
    { key = 'infection', label = 'Infection', color = '#8d6bb0', icon = 'virus',  show = true,  critical = 60, inverted = true, hideAtZero = true },
}

--- Which bars survive in minimal mode.
UI.MinimalBars = { 'health', 'stamina', 'infection' }

-- Panels the HUD hides itself for.
UI.HideHudFor = {
    survivorLink = 'bs_survivor_link',
    inventory = 'bs_inventory',
    menu      = 'bs_menu',
    vip       = 'bs_vip',
    admin     = 'bs_admin',

    -- Not a panel: bs_cinecam fires this pair around /hidehud and cinematic camera mode
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

--- Menu palettes. `vars` are hex colours pushed to every NUI through bs_ui/html/shared/palette.js: accent
UI.Palettes = {
    { id='custom', label='Custom', sw={'#e08c46','#0a0a09','#f0ebdd'} },
    { id = 'default', label = 'Rust', sw = { '#e08c46', '#0a0a09', '#f0ebdd' } },
    { id = 'frost',   label = 'Frost',   vars = { accent = '#5fa8d3', hi = '#8cc6e8', bg = '#090c0e', text = '#e6eef2', muted = '#8fa0aa', blood = '#2b4a6e' } },
    { id = 'verdant', label = 'Verdant', vars = { accent = '#7fb069', hi = '#a3cf8d', bg = '#0a0c09', text = '#e9efdf', muted = '#9aa58c', blood = '#2f4a2a' } },
    { id = 'crimson', label = 'Crimson', vars = { accent = '#c4493d', hi = '#e0685a', bg = '#0c0909', text = '#f0e4e0', muted = '#a89490', blood = '#7a1f1a' } },
    { id = 'royal',   label = 'Royal',   vip = true, vars = { accent = '#a074d6', hi = '#bf9ae8', bg = '#0b090e', text = '#efe9f5', muted = '#a39aae', blood = '#4a2a6e' } },
    { id = 'aurum',   label = 'Aurum',   vip = true, vars = { accent = '#e0b341', hi = '#f2cf6e', bg = '#0d0b07', text = '#f5edd8', muted = '#b0a584', blood = '#6e5a21' } },
}
