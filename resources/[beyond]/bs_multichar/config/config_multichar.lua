--[[ BeyondSurvival | bs_multichar/config/config_multichar.lua
     Where the character-select scene is staged and how it looks.              ]]

Multichar = {}

-- Alpha-Z: einziger Erstspawn für NEU erstellte Charaktere.
-- Die Charaktervorschau nutzt weiterhin Multichar.Scene (unverändert).
Multichar.FirstSpawn = {
    x = 1741.80,
    y = 3274.91,
    z = 41.14,
    h = 326.4,
    radius = 10.0,
}

Multichar.Scene = {
    -- Exact in-game /coords position on the rock; preserve custom-map collision height.
    -- Heading is the measured in-game player orientation.
    ped     = { x = 1528.94, y = 3199.54, z = 41.60, h = 98.72 },

    -- Precache the outdoor scene before moving the hidden player to the preview spot.
    precache = { x = 1528.94, y = 3199.54, z = 52.0 },

    -- Camera framing. A ped's origin is at its feet and an adult is ~1.8m, so every z is measured up from the ground.
    -- offset.x slides the camera and look-at target sideways together (parallel shift, no angle) so the character sits clear of the survivor list on the left. Negative x puts the ped right of centre.
    -- Shift as a fraction of half-screen = offset.x / (d*tan(fov/2)*aspect). At d=2.55, fov 36, 16:9 the half-width is ~1.47m, so -0.42 is ~14% right of centre.
    cam     = {
        offset = { x = -0.27, y = 2.75, z = 0.50 },
        look   = { x = 0.0,   y = 0.0,  z = 0.50 },
        fov    = 50.0,
    },

    rotateSpeed = 0.65,
    zoomSpeed   = 0.18,
    zoomMin     = 0.75,
    zoomMax     = 2.2,

    -- Max camera distance from the ped. The camera sits focus.offset.y * zoom metres south of the ped and the room has walls: FULL at max zoom needs 6.05m, through the south wall. 3.4m is safely short of it. Raise it if the stage moves somewhere roomier; /camdebug prints the distance used.
    maxCamDistance = 5.5,

    -- Mood while choosing. Local only - does not touch the server's weather.
    -- Underground there is no sky to speak of, but the clock still drives the
    -- ambient tone, and a dead hour reads better than noon.
    -- Nur fuer den Vorschau-Bildschirm; Weltwetter und Weltzeit laufen unbeeinflusst weiter.
    weather = 'FOGGY',
    hour    = 12,
    minute  = 30,
    weatherLock = { enabled = true, tickMs = 100 },

    -- Lights: the world blackout kills every map light, but the lineup shell has no daylight. These are local lights around the stage only; bs_world leaves its blackout off while the scene is up.
    lights  = {
        enabled = true,
        -- Key light, in front and above: the direction the camera looks from.
        key     = { x = 0.0, y = 0.0, z = 1.75, r = 248, g = 243, b = 229, range = 6.0, intensity = 3.4 },
        -- Cold rim from behind, so the silhouette separates from the dark.
        rim     = { x = 1.3, y = 1.2, z = 1.65, r = 163, g = 188, b = 202, range = 4.5, intensity = 1.4 },
        -- Warm bounce off the floor.
        bounce  = { x = 0.0, y = 0.0, z = 0.25, r = 211, g = 190, b = 155, range = 3.3, intensity = 1.1 },
    },

    fadeIn  = 600,
    fadeOut = 400,
}

Multichar.Settings = {
    -- Camera angles the UI can jump to.
    --- y is metres back, z is a fraction of the measured body height, and
    --- x is a fraction of the visible half-width. See the note on
    --- Multichar.Scene.cam above for where each distance comes from.
    focus = {
        -- z is a fraction of the measured body, 0 at the soles and 1 at the crown (taken from bones, see bodySpan() in cl_scene.lua).
        -- Distances and fov: see Multichar.Scene.cam above. Long lens close by fits in the room.

        -- head to toe, with headroom: 2.57m of subject, centred at mid-body
        full = { offset = { x = -0.27, y = 2.75, z = 0.50 }, look = { x = 0.0, y = 0.0, z = 0.50 }, fov = 50.0 },
        -- waist to just over the head: 1.53m, centred at the sternum
        body = { offset = { x = -0.27, y = 1.90, z = 0.74 }, look = { x = 0.0, y = 0.0, z = 0.74 }, fov = 44.0 },
        -- Legs and boots only; cam and look stay on the lower half.
        legs = { offset = { x = -0.27, y = 1.32, z = 0.27 }, look = { x = 0.0, y = 0.0, z = 0.27 }, fov = 43.0 },
        -- head and shoulders: 0.67m, centred on the face
        face = { offset = { x = -0.27, y = 1.10, z = 0.92 }, look = { x = 0.0, y = 0.0, z = 0.92 }, fov = 34.0 },
    },
    -- Idle animation for the preview ped.
    idleAnim = { dict = 'anim@heists@heist_corona@team_idle_a', clip = 'idle_a_m2' },
    -- Show the weapon the character last had in hand.
    showLastWeapon = true,
}

--------------------------------------------------------------------------------
-- Character creator rework
--------------------------------------------------------------------------------

-- F1 setting: show the CLOTHING step. Off = the step is hidden and the default outfit is used.
Multichar.Creator = {
    clothingStep = true,
}

-- Identity extras, saved in metadata.identity. Lengths are enforced by the server.
Multichar.Identity = {
    nicknameMax  = 20,
    backstoryMax = 200,
    heightMin = 150, heightMax = 205, heightDefault = 175,   -- cm, cosmetic text only
    bloodTypes  = { 'O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-' },
    -- Labels are locale keys occ.<id>.
    occupations = { 'unemployed', 'mechanic', 'nurse', 'teacher', 'soldier', 'farmer', 'police', 'cook', 'driver', 'student', 'office', 'builder' },
}

-- Starting kit: hunting knife is automatic, players choose only extras.
-- Item amounts below are the amount granted when that extra is selected.
Multichar.Kit = {
    enabled    = true,
    maxGoodies = 2,
    -- No player-selectable weapons. The server always grants exactly one hunting_knife.
    melee = {},
    goodies = {
        { id = 'food',       item = 'canned_food',  amount = 3 },
        { id = 'water',      item = 'water_bottle', amount = 3 },
        { id = 'bandage',    item = 'bandage',      amount = 3 },
        { id = 'flashlight', item = 'flashlight',   amount = 1 },
        { id = 'matches',    item = 'matches',      amount = 1 },
        { id = 'lockpick',   item = 'lockpick',     amount = 3 },
        { id = 'medkit',     item = 'medkit',       amount = 1 },
        { id = 'gasmask',    item = 'gas_mask',     amount = 1, label = 'Gasmaske' },
        { id = 'smallpack',  item = 'pack_small',    amount = 1, label = 'Kleiner Rucksack' },
    },
}

-- Creator uses the same valid collection slots as bs_clothing, not a fixed GTA list.
-- CFX client natives enumerate GTA, DLC and installed addon collections.
-- Component 5 (bags/backpacks) intentionally excluded; also no armour component 9.
Multichar.Clothes = {
    maxTexture = 255,
    armsFor = {
        male = { [0]=0, [1]=0, [2]=2, [3]=14, [4]=14, [5]=5, [6]=14, [7]=14, [8]=8, [9]=0, [10]=14 },
        female = { [0]=0, [1]=5, [2]=2, [3]=3, [4]=4, [5]=4, [6]=5, [7]=5, [8]=5, [9]=0, [10]=5 },
    },
    -- category, component / prop, reasonable preview default
    mask       = { c = 1, default = 0 },
    top        = { c = 11, default = 0 },
    undershirt = { c = 8, default = 15 },
    arms       = { c = 3, default = 0 },
    legs       = { c = 4, default = 0 },
    shoes      = { c = 6, default = 1 },
    accessory  = { c = 7, default = 0 },
    hat        = { p = 0, default = -1 },
    glasses    = { p = 1, default = -1 },
    ears       = { p = 2, default = -1 },
    watch      = { p = 6, default = -1 },
    bracelet   = { p = 7, default = -1 },
    -- these are collection fragments, not numeric drawable indices
    -- Gulag cloth 5 replaces a vanilla asset, so there is no independent collection to hide.
    excludedCollections = {
        'siycclothes2', 'mp_f_siycclothes2', 'navyaus',
        'opforclothing', 'deadlands',
    },
}

-- Starting look per sex (applied when the creator opens and on every sex switch). Merged over bs_core's Config.DefaultLook.
Multichar.Defaults = {
    male   = { motherIndex = 21, fatherIndex = 0, shapeMix = 0.70, skinMix = 0.60, hairStyle = 2, hairColor = 1, hairHighlight = 1,
               beardStyle = -1, beardColor = 1, beardOpacity = 0.8, eyebrowStyle = 0, eyebrowColor = 1, eyeColor = 4 },
    female = { motherIndex = 21, fatherIndex = 0, shapeMix = 0.30, skinMix = 0.40, hairStyle = 4, hairColor = 3, hairHighlight = 3,
               beardStyle = -1, eyebrowStyle = 4, eyebrowColor = 3, eyeColor = 4,
               makeupStyle = -1, lipstickStyle = -1, blushStyle = -1 },
}

-- ROLL A FACE. Everything is picked from these lists, so results stay natural. Pairs are { mother index (21-41), father index (0-20) }.
-- shape = range of shapeMix (0 = mother's shape, 1 = father's). skin follows the dominant parent: skinMix = shapeMix +- skinSpread, clamped to skinMin..skinMax.
Multichar.Roll = {
    featureRange = 0.35,   -- face details are rolled within +-this
    male = {
        pairs = { {21,0}, {22,1}, {25,3}, {26,5}, {28,4}, {29,12}, {31,2}, {37,8}, {38,9}, {40,6}, {41,7}, {24,19}, {34,15}, {35,17}, {23,10}, {39,14} },
        shape = { 0.60, 0.85 }, skinSpread = 0.12, skinMin = 0.45, skinMax = 0.95,
        hair = { 1, 2, 3, 4, 5, 9, 10, 12, 13, 15, 16, 18 },
        hairColors = { 0, 1, 1, 2, 2, 3, 3, 4, 5, 8, 9 },
        browStyles = { 0, 1, 2, 3, 4, 7, 10, 12 },
        eyeColors  = { 0, 2, 3, 4, 4, 5, 5, 5, 6, 7, 8 },
        beard = { chance = 0.45, styles = { 0, 1, 2, 3, 4, 5, 6, 8 }, opacity = { 0.6, 1.0 } },
        lipstick = { chance = 0.0 },
    },
    female = {
        pairs = { {21,1}, {22,3}, {23,0}, {25,4}, {26,9}, {28,8}, {29,12}, {31,2}, {37,7}, {38,10}, {39,6}, {40,9}, {41,3}, {24,18}, {34,15}, {35,17} },
        shape = { 0.15, 0.40 }, skinSpread = 0.12, skinMin = 0.05, skinMax = 0.55,
        hair = { 1, 2, 3, 4, 7, 9, 10, 11, 15, 16, 18, 19 },
        hairColors = { 0, 1, 1, 2, 2, 3, 3, 4, 5, 8, 9, 10 },
        browStyles = { 1, 4, 5, 8, 9, 10, 14 },
        eyeColors  = { 0, 2, 3, 4, 4, 5, 5, 6, 7, 8 },
        beard = { chance = 0.0 },
        lipstick = { chance = 0.0, styles = { 0 }, colors = { 5 } },
    },
}
