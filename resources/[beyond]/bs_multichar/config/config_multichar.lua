--[[ BeyondSurvival | bs_multichar/config/config_multichar.lua
     Where the character-select scene is staged and how it looks.              ]]

Multichar = {}

Multichar.Scene = {
    -- The lineup shell: the enclosed interior under the map (402.88, -996.45, -99.0), also used by BigDaddy-CharacterManager. Always loaded, enclosed, empty. It is pitch dark under the world blackout, hence Multichar.Scene.lights.
    -- Entered in two steps (z = 30 first so the column caches, then dropped). z is -99.0 not -98.5 because the preview ped is frozen and would hover half a metre up.
    ped     = { x = 402.88, y = -996.45, z = -99.0, h = 180.0 },

    -- The cache-in point directly above the shell. Never a spawn point; the
    -- ped is here for a second on the way down.
    precache = { x = 402.88, y = -996.45, z = 30.0 },

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
    maxCamDistance = 3.4,

    -- Mood while choosing. Local only - does not touch the server's weather.
    -- Underground there is no sky to speak of, but the clock still drives the
    -- ambient tone, and a dead hour reads better than noon.
    weather = 'OVERCAST',
    hour    = 21,
    minute  = 40,

    -- Lights: the world blackout kills every map light, but the lineup shell has no daylight. These are local lights around the stage only; bs_world leaves its blackout off while the scene is up.
    lights  = {
        enabled = true,
        -- Key light, in front and above: the direction the camera looks from.
        key     = { x = 0.0,  y = -2.2, z = 1.9, r = 240, g = 232, b = 214, range = 6.5, intensity = 3.0 },
        -- Cold rim from behind, so the silhouette separates from the dark.
        rim     = { x = 1.5,  y = 1.9,  z = 1.7, r = 120, g = 145, b = 180, range = 5.0, intensity = 1.6 },
        -- Warm bounce off the floor.
        bounce  = { x = 0.0,  y = -0.7, z = 0.15, r = 205, g = 155, b = 110, range = 3.4, intensity = 1.0 },
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

-- Starting kit: one melee weapon and up to maxGoodies basic extras. item is a bs_inventory item name; labels are locale keys item.<item>. No firearms here.
-- Food and water picks give x5 (amount below). The server rebuilds the loadout from these ids only.
Multichar.Kit = {
    enabled    = true,
    maxGoodies = 5,
    melee = {
        { id = 'knife',    item = 'hunting_knife' },
        { id = 'bat',      item = 'reinforced_bat' },
        { id = 'crowbar',  item = 'crowbar' },
        { id = 'machete',  item = 'machete' },
        { id = 'hatchet',  item = 'hatchet' },
    },
    goodies = {
        { id = 'water',      item = 'water_bottle', amount = 5 },
        { id = 'canned',     item = 'canned_food',  amount = 5 },
        { id = 'bandage',    item = 'bandage',      amount = 2 },
        { id = 'painkiller', item = 'painkillers',  amount = 1 },
        { id = 'antiseptic', item = 'antiseptic',   amount = 1 },
        { id = 'repair',     item = 'repair_kit',   amount = 1 },
        { id = 'flashlight', item = 'flashlight',   amount = 1 },
        { id = 'lockpick',   item = 'lockpick',     amount = 1 },
        { id = 'matches',    item = 'matches',      amount = 1 },
        { id = 'rags',       item = 'rags',         amount = 3 },
    },
}

-- Clothing slots in the creator: top, legs, shoes and gloves/arms only. Freemode drawable ids per sex (base game), plain everyday pieces only. none is the bare / empty value.
-- top: arms (component 3) follow the top (same id unless armsFor has a row), the player may still adjust arms by hand inside armsRange.
-- Tune any list here, the server only accepts what is listed.
local function R(a, b) local t = {} for i = a, b do t[#t + 1] = i end return t end
local function cat(...) local t = {} for _, l in ipairs({ ... }) do for _, v in ipairs(l) do t[#t + 1] = v end end return t end

Multichar.Clothes = {
    maxTexture = 24,
    armsRange  = { 0, 40 },
    -- [topDrawable] = arms drawable. Arms must match the top's cut: the top id itself is wrong for most tops and leaves holes in the upper body.
    armsFor    = {
        male = {
            [0] = 0, [1] = 0, [2] = 2, [3] = 14, [4] = 14, [5] = 5, [6] = 14, [7] = 14, [8] = 8, [9] = 0, [10] = 14,
            [11] = 15, [12] = 12, [13] = 11, [14] = 12, [16] = 0, [17] = 5, [18] = 0, [19] = 14, [20] = 14, [21] = 15,
            [22] = 0, [23] = 14, [24] = 14, [25] = 15, [26] = 11, [27] = 14, [28] = 14, [29] = 14, [30] = 14,
        },
        female = {
            [0] = 0, [1] = 5, [2] = 2, [3] = 3, [4] = 4, [5] = 4, [6] = 5, [7] = 5, [8] = 5, [9] = 0, [10] = 5,
            [11] = 4, [12] = 12, [13] = 15, [14] = 14, [16] = 15, [17] = 0, [18] = 15, [19] = 0, [20] = 5, [21] = 0,
            [22] = 4, [23] = 4, [24] = 5, [25] = 5, [26] = 12, [27] = 0, [28] = 15, [29] = 9, [30] = 2,
        },
    },
    -- kind: c = component, p = prop. none per sex; props use -1.
    top        = { c = 11, male = cat(R(0, 14), R(16, 30)), female = cat(R(0, 14), R(16, 30)) },
    legs       = { c = 4,  male = cat(R(0, 10), { 12, 13, 14 }), female = cat(R(0, 10), { 12, 13, 14 }) },
    shoes      = { c = 6,  male = { 1, 5, 6, 10, 12, 24, 25, 27 }, female = { 1, 2, 5, 6, 9, 10, 24, 25 } },
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
