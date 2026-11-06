-- bs_weapons - attachment config
-- Attachments are inventory items: fitting one consumes it, removing it returns it

Weapons = {}

Weapons.Settings = {
    editorEnabled = true,
    -- O. Opens the wheel for whatever is in your hands.
    openKey     = 'O',
    openCommand = 'weaponwheel',

    -- How long fitting or removing takes, ms.
    workTime    = 1800,
    -- Same, from the O attachment view. 0 = the part goes on the moment you drop it.
    viewWorkTime = 0,

    -- You cannot work on a weapon while running, in a vehicle, or in a fight you are losing
    requireStill = true,
}

-- The six attachment slots. Order is the order they appear in the wheel.
Weapons.Slots = {
    { id = 'muzzle', label = 'Muzzle',   icon = 'silencer' },
    { id = 'scope',  label = 'Optic',    icon = 'scope' },
    { id = 'grip',   label = 'Grip',     icon = 'grip' },
    { id = 'light',  label = 'Light',    icon = 'weapon_light' },
    { id = 'laser',  label = 'Laser',    icon = 'laser' },
    { id = 'mag',    label = 'Magazine', icon = 'magazine' },
}

-- item is the inventory item consumed to fit it. components maps a weapon to the component used on THAT weapon
-- A wrong WEAPON_X = 'COMPONENT_Y' pair is harmless: DoesWeaponTakeWeaponComponent never offers that slot
Weapons.Attachments = {
    suppressor = {
        slot  = 'muzzle',
        item  = 'att_suppressor',
        label = 'Suppressor',
        icon  = 'silencer',
        blurb = 'Drops a gunshot from 90 metres of noise to 25.',
        components = {
            -- The base Pistol's suppressor is COMPONENT_AT_PI_SUPP_02 (the other base pistols use plain _SUPP)
            -- The earlier swap to _SUPP is why the O menu could never fit it on the tutorial pistol
            WEAPON_PISTOL        = 'COMPONENT_AT_PI_SUPP_02',
            WEAPON_COMBATPISTOL  = 'COMPONENT_AT_PI_SUPP',
            WEAPON_APPISTOL      = 'COMPONENT_AT_PI_SUPP',
            WEAPON_HEAVYPISTOL   = 'COMPONENT_AT_PI_SUPP',
            WEAPON_MACHINEPISTOL = 'COMPONENT_AT_PI_SUPP',
            WEAPON_CARBINERIFLE  = 'COMPONENT_AT_AR_SUPP',
            WEAPON_ASSAULTRIFLE  = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_AR_SUPP',
            WEAPON_SPECIALCARBINE= 'COMPONENT_AT_AR_SUPP',
            WEAPON_BULLPUPRIFLE  = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_MARKSMANRIFLE = 'COMPONENT_AT_AR_SUPP',
            WEAPON_SNIPERRIFLE   = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_PUMPSHOTGUN   = 'COMPONENT_AT_SR_SUPP',
            WEAPON_MICROSMG      = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_SMG           = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_ASSAULTSMG    = 'COMPONENT_AT_AR_SUPP_02',
        },
    },

    scope = {
        slot  = 'scope',
        item  = 'att_scope',
        label = 'Optic',
        icon  = 'scope',
        blurb = 'Something to look through. Tighter than iron sights.',
        components = {
            WEAPON_CARBINERIFLE  = 'COMPONENT_AT_SCOPE_MEDIUM',
            WEAPON_ASSAULTRIFLE  = 'COMPONENT_AT_SCOPE_MACRO',
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_SCOPE_MACRO',
            WEAPON_SPECIALCARBINE= 'COMPONENT_AT_SCOPE_MEDIUM',
            WEAPON_BULLPUPRIFLE  = 'COMPONENT_AT_SCOPE_MACRO_02',
            WEAPON_MARKSMANRIFLE = 'COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM',
            WEAPON_SNIPERRIFLE   = 'COMPONENT_AT_SCOPE_LARGE',
            WEAPON_HEAVYSNIPER   = 'COMPONENT_AT_SCOPE_LARGE',
            WEAPON_MICROSMG      = 'COMPONENT_AT_SCOPE_MACRO',
            WEAPON_SMG           = 'COMPONENT_AT_SCOPE_MACRO_02',
            WEAPON_ASSAULTSMG    = 'COMPONENT_AT_SCOPE_MACRO_02',
            WEAPON_MACHINEPISTOL = 'COMPONENT_AT_SCOPE_MACRO',
        },
    },

    grip = {
        slot  = 'grip',
        item  = 'att_grip',
        label = 'Foregrip',
        icon  = 'grip',
        blurb = 'Steadier under recoil.',
        components = {
            WEAPON_CARBINERIFLE  = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_ASSAULTRIFLE  = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_SPECIALCARBINE= 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_BULLPUPRIFLE  = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_MARKSMANRIFLE = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_SMG           = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_ASSAULTSMG    = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_COMPACTRIFLE  = 'COMPONENT_AT_AR_AFGRIP',
        },
    },

    flashlight = {
        slot  = 'light',
        item  = 'att_flashlight',
        label = 'Flashlight',
        icon  = 'weapon_light',
        blurb = 'Sees in the dark. So does everything else, now.',
        components = {
            WEAPON_PISTOL        = 'COMPONENT_AT_PI_FLSH',
            WEAPON_COMBATPISTOL  = 'COMPONENT_AT_PI_FLSH',
            WEAPON_APPISTOL      = 'COMPONENT_AT_PI_FLSH',
            WEAPON_HEAVYPISTOL   = 'COMPONENT_AT_PI_FLSH',
            WEAPON_SNSPISTOL     = 'COMPONENT_AT_PI_FLSH',
            WEAPON_MACHINEPISTOL = 'COMPONENT_AT_PI_FLSH',
            WEAPON_CARBINERIFLE  = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ASSAULTRIFLE  = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_AR_FLSH',
            WEAPON_SPECIALCARBINE= 'COMPONENT_AT_AR_FLSH',
            WEAPON_BULLPUPRIFLE  = 'COMPONENT_AT_AR_FLSH',
            WEAPON_PUMPSHOTGUN   = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ASSAULTSHOTGUN= 'COMPONENT_AT_AR_FLSH',
            WEAPON_BULLPUPSHOTGUN= 'COMPONENT_AT_AR_FLSH',
            WEAPON_MICROSMG      = 'COMPONENT_AT_PI_FLSH',
            WEAPON_SMG           = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ASSAULTSMG    = 'COMPONENT_AT_AR_FLSH',
        },
    },

    -- Laser sight: cosmetic plus a tiny hip-fire accuracy bonus, same tier as the grip.
    laser = {
        slot  = 'laser',
        item  = 'att_laser',
        label = 'Laser sight',
        icon  = 'laser',
        blurb = 'A dot to walk the shot in with, and something to see across a dark room.',
        components = {
            WEAPON_PISTOL        = 'COMPONENT_AT_PI_RAIL',
            WEAPON_COMBATPISTOL  = 'COMPONENT_AT_PI_RAIL',
            WEAPON_APPISTOL      = 'COMPONENT_AT_PI_RAIL',
            WEAPON_HEAVYPISTOL   = 'COMPONENT_AT_PI_RAIL',
            WEAPON_SNSPISTOL     = 'COMPONENT_AT_PI_RAIL',
            WEAPON_MICROSMG      = 'COMPONENT_AT_AR_LSR',
            WEAPON_SMG           = 'COMPONENT_AT_AR_LSR',
            WEAPON_ASSAULTSMG    = 'COMPONENT_AT_AR_LSR',
            WEAPON_MACHINEPISTOL = 'COMPONENT_AT_PI_RAIL',
        },
    },

    extmag = {
        slot  = 'mag',
        item  = 'att_extmag',
        label = 'Extended magazine',
        icon  = 'magazine',
        blurb = 'More rounds between reloads.',
        components = {
            WEAPON_PISTOL        = 'COMPONENT_PISTOL_CLIP_02',
            WEAPON_COMBATPISTOL  = 'COMPONENT_COMBATPISTOL_CLIP_02',
            WEAPON_APPISTOL      = 'COMPONENT_APPISTOL_CLIP_02',
            WEAPON_HEAVYPISTOL   = 'COMPONENT_HEAVYPISTOL_CLIP_02',
            WEAPON_SNSPISTOL     = 'COMPONENT_SNSPISTOL_CLIP_02',
            WEAPON_MACHINEPISTOL = 'COMPONENT_MACHINEPISTOL_CLIP_02',
            WEAPON_CARBINERIFLE  = 'COMPONENT_CARBINERIFLE_CLIP_02',
            WEAPON_ASSAULTRIFLE  = 'COMPONENT_ASSAULTRIFLE_CLIP_02',
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_ADVANCEDRIFLE_CLIP_02',
            WEAPON_SPECIALCARBINE= 'COMPONENT_SPECIALCARBINE_CLIP_02',
            WEAPON_BULLPUPRIFLE  = 'COMPONENT_BULLPUPRIFLE_CLIP_02',
            WEAPON_COMPACTRIFLE  = 'COMPONENT_COMPACTRIFLE_CLIP_02',
            WEAPON_MARKSMANRIFLE = 'COMPONENT_MARKSMANRIFLE_CLIP_02',
            WEAPON_MICROSMG      = 'COMPONENT_MICROSMG_CLIP_02',
            WEAPON_SMG           = 'COMPONENT_SMG_CLIP_02',
            WEAPON_ASSAULTSMG    = 'COMPONENT_ASSAULTSMG_CLIP_02',
            WEAPON_PUMPSHOTGUN   = 'COMPONENT_PUMPSHOTGUN_CLIP_01',
            WEAPON_ASSAULTSHOTGUN= 'COMPONENT_ASSAULTSHOTGUN_CLIP_02',
        },
    },
}

-- Every weapon the wheel can name
-- Used to turn the hash in your hands back into a name; an unlisted weapon just shows 'nothing fits'
Weapons.Known = {
    'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50',
    'WEAPON_SNSPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_REVOLVER',
    'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_ASSAULTSMG', 'WEAPON_MACHINEPISTOL',
    'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_ADVANCEDRIFLE',
    'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE',
    'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN',
    'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET', 'WEAPON_DBSHOTGUN',
    'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE',
    'WEAPON_MG', 'WEAPON_COMBATMG',
    'WEAPON_COMBATPDW', 'WEAPON_MILITARYRIFLE', 'WEAPON_HEAVYSHOTGUN',
    'WEAPON_BAT', 'WEAPON_CROWBAR', 'WEAPON_HAMMER', 'WEAPON_GOLFCLUB',
    'WEAPON_KNIFE', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_BATTLEAXE',
    'WEAPON_WRENCH', 'WEAPON_POOLCUE', 'WEAPON_SWITCHBLADE', 'WEAPON_DAGGER',
    'WEAPON_FLASHLIGHT', 'WEAPON_NIGHTSTICK', 'WEAPON_STONE_HATCHET',
    'WEAPON_MOLOTOV', 'WEAPON_GRENADE', 'WEAPON_PETROLCAN', 'WEAPON_FIREEXTINGUISHER',
}

-- Gameplay effects of attachments
-- The game handles visuals and ballistics; these are the parts the framework cares about
Weapons.Effects = {
    suppressor = { noiseScale = 0.28 },     -- 90 m becomes ~25 m
    grip       = { recoil = 0.85 },
    scope      = { zoom = 1.0 },
    flashlight = { light = true },
    laser      = { hipfireAccuracy = 1.1 },  -- the game's own component, cosmetic + a small nudge
    extmag     = { ammo = 1.5 },
}

-- Animation for working on a weapon: a candidate list in preference order
-- A dict can load without containing the clip
Weapons.Anims = {
    { dict = 'weapons@rifle@lo@',                clip = 'reload_low', flag = 49 },
    { dict = 'weapons@pistol@pistol_str@',       clip = 'reload_aim', flag = 49 },
    { dict = 'anim@weapons@sniper@sniper_rifle@', clip = 'reload_low', flag = 49 },
    { dict = 'reload@rifle',                     clip = 'reload',     flag = 49 },
    -- Last resort: a clip known to work, so something always plays.
    { dict = 'anim@heists@ornate_bank@grab_cash_heels', clip = 'grab', flag = 49 },
}

--- Back-compatibility: anything still reading Weapons.Anim gets the fallback.
Weapons.Anim = { dict = 'anim@heists@ornate_bank@grab_cash_heels', clip = 'grab', flag = 49 }

-- Inspect animation. Cosmetic only.
Weapons.Inspect = {
    dict = 'anim@mp_fm_event@intro',
    clip = 'intro',
    time = 2600,
    flag = 48,
}

-- Shift + R: check the magazine. The count appears part way through the gesture.
-- GTA has no magazine-inspect clip, so anims is a candidate list probed in order; the last entry is known to work
Weapons.MagCheck = {
    -- How long the whole gesture runs, in ms.
    time = 2200,

    -- Fraction of the gesture at which the magazine is visible and the readout appears.
    look = 0.45,

    -- false = report the magazine in words ('over half', 'nearly empty'); true = exact count ('17 / 30'). The loose-round count is exact either way.
    exact = false,

    -- Anti-spam. R is a key people hold; this is the gap between checks.
    cooldown = 900,

    notifyTime = 3000,

    anims = {
        -- Hand comes up, thumb works at something, eyes follow it down.
        { dict = 'anim@mp_player_intmenu@key_fob@', clip = 'fob_click', flag = 48 },
        -- Looking down at something held in front of the chest.
        { dict = 'amb@world_human_clipboard@male@idle_a', clip = 'idle_c', flag = 48 },
        -- Known-good last resort: the clip the wheel's inspect already plays.
        { dict = 'anim@mp_fm_event@intro', clip = 'intro', flag = 48 },
    },
}

-- Live preview: while the wheel is open the camera moves in on the weapon (left half of the screen, wheel on the right)
-- Values are metres relative to the weapon, not the player. enabled = false puts the wheel back in the middle with no camera.
Weapons.Preview = {
    enabled  = true,

    -- Which side of the screen the GUN gets. The wheel takes the other one.
    weaponSide = 'left',

    -- Where the camera sits, measured from the weapon, in the player's own frame: out to their right, forward past the muzzle, and a little up
    offsetRight   = 0.42,
    offsetForward = 0.58,
    offsetUp      = 0.10,

    -- Narrow lens: a gun shot at 50 degrees looks like a toy.
    fov      = 36.0,

    -- Degrees the camera turns away from the weapon
    -- Aiming slightly past it pushes the gun to one side so the wheel has room. Bigger = further over.
    swing    = 15.0,

    -- Ease in / out, ms. Snapping straight to a scripted camera is jarring.
    easeIn   = 420,
    easeOut  = 320,

    -- Shallow depth of field, so the world behind the gun falls away.
    dof      = true,
    dofNear  = 0.25,
    dofFar   = 2.20,

    -- Hard ceiling on camera time in ms. A last-resort guard so a scripted camera can never stay up.
    maxHold  = 90000,

    -- O attachment view: front three-quarter camera facing the player, aimed at the gun in their hands.
    -- yaw: degrees from straight in front toward the weapon (right) side. pitch: degrees above the gun.
    -- Zoom 1 fits the whole weapon between the side panels; maxZoom is how far out the wheel can go.
    -- Uses the ped's own heading, so it frames the same way in first person.
    shoulder = {
        yaw = 38.0, pitch = 12.0, minPitch = -15.0, maxPitch = 60.0, orbitLimit = 75.0,
        fov = 38.0, margin = 1.08, usableWidth = 0.55, minDistance = 0.55, maxZoom = 1.9,
        follow = 0.22,
    },
}

-- O menu sounds: 'gear' = the game's weapon-mod clicks on fit and remove, 'off' = silent.
-- (A separate setting, not Weapons.Attachments.sounds: that table is the attachment list itself.)
Weapons.AttachmentSounds = 'gear'

-- Experimental: left hand onto a fitted foregrip (third person), applied to every nearby player holding one.
-- ikPart is the SET_IK_TARGET arm index; offset is metres from the weapon's WAPGrip bone.
Weapons.GripPose = {
    enabled = true,
    ikPart = 3,
    offset = { x = 0.0, y = 0.0, z = -0.035 },
    blendIn = 180, blendOut = 180,
    distance = 40.0,
    skipSprint = true,
}

-- Noise: what a muzzle device does
-- When suppressorIsSilent is true, a weapon with an attachment whose noiseScale is at or below silentAtOrBelow emits no noise event at all

Weapons.Noise = {
    suppressorIsSilent = true,

    -- Threshold on noiseScale rather than a specific attachment, so quieter future attachments are covered. 0.30 sits just above the suppressor's 0.28.
    silentAtOrBelow = 0.30,

    -- Also trust IsPedCurrentWeaponSilenced()
    -- It is true for any suppressed weapon, including ones not fitted by this framework; when true it silences the shot on its own
    engineSilencerCounts = true,
}

-- Magazines: rounds a weapon holds loaded
-- This table is authoritative: the client trims the loaded mag to it, reload fills to it, and admin tools count ammo in mags of it
Weapons.Magazines = {
    -- pistols
    WEAPON_PISTOL        = { base = 12, ext = 16, ammo = 'ammo_pistol' },           -- GTA 12/16
    WEAPON_COMBATPISTOL  = { base = 12, ext = 16, ammo = 'ammo_pistol' },           -- GTA 12/16
    WEAPON_APPISTOL      = { base = 18, ext = 27, ammo = 'ammo_pistol' },           -- GTA 18/36
    WEAPON_HEAVYPISTOL   = { base = 18, ext = 27, ammo = 'ammo_pistol' },           -- GTA 18/36
    WEAPON_SNSPISTOL     = { base = 6,  ext = 9,  ammo = 'ammo_pistol' },           -- GTA 6/12
    WEAPON_VINTAGEPISTOL = { base = 7,  ext = 10, ammo = 'ammo_pistol' },           -- GTA 7/14
    WEAPON_PISTOL50      = { base = 9,  ext = 12, ammo = 'ammo_magnum' },           -- GTA 9/12
    WEAPON_REVOLVER      = { base = 6,            ammo = 'ammo_magnum' },           -- cylinder
    -- SMGs
    WEAPON_MACHINEPISTOL = { base = 12, ext = 18, drum = 30, ammo = 'ammo_pistol' },-- GTA 12/20/30
    WEAPON_MICROSMG      = { base = 16, ext = 24, ammo = 'ammo_pistol' },           -- GTA 16/30
    WEAPON_SMG           = { base = 30, ext = 45, drum = 100, ammo = 'ammo_pistol' },-- GTA 30/60/100
    WEAPON_ASSAULTSMG    = { base = 30, ext = 45, ammo = 'ammo_pistol' },           -- GTA 30/60
    -- rifles
    WEAPON_ASSAULTRIFLE  = { base = 30, ext = 45, drum = 100, ammo = 'ammo_rifle' },-- GTA 30/60/100
    WEAPON_CARBINERIFLE  = { base = 30, ext = 45, drum = 100, ammo = 'ammo_rifle' },-- GTA 30/60/100 (box)
    WEAPON_ADVANCEDRIFLE = { base = 30, ext = 45, ammo = 'ammo_rifle' },            -- GTA 30/60
    WEAPON_SPECIALCARBINE= { base = 30, ext = 45, drum = 100, ammo = 'ammo_rifle' },-- GTA 30/60/100
    WEAPON_BULLPUPRIFLE  = { base = 30, ext = 45, ammo = 'ammo_rifle' },            -- GTA 30/60
    WEAPON_COMPACTRIFLE  = { base = 30, ext = 45, drum = 100, ammo = 'ammo_rifle' },-- GTA 30/60/100
    -- shotguns (tube / barrels)
    WEAPON_PUMPSHOTGUN   = { base = 8,            ammo = 'ammo_shotgun' },          -- GTA 8
    WEAPON_SAWNOFFSHOTGUN= { base = 6,            ammo = 'ammo_shotgun' },          -- GTA 8, shorter tube here
    WEAPON_ASSAULTSHOTGUN= { base = 8,  ext = 12, drum = 32, ammo = 'ammo_shotgun' },-- GTA 8/32
    WEAPON_BULLPUPSHOTGUN= { base = 14,           ammo = 'ammo_shotgun' },          -- GTA 14
    WEAPON_DBSHOTGUN     = { base = 2,            ammo = 'ammo_shotgun' },          -- two barrels
    WEAPON_MUSKET        = { base = 1,            ammo = 'ammo_shotgun' },          -- single shot
    -- snipers / marksman
    WEAPON_SNIPERRIFLE   = { base = 10,           ammo = 'ammo_rifle' },            -- GTA 10
    WEAPON_HEAVYSNIPER   = { base = 6,            ammo = 'ammo_rifle' },            -- GTA 6
    WEAPON_MARKSMANRIFLE = { base = 8,  ext = 12, ammo = 'ammo_rifle' },            -- GTA 8/16
    -- machine guns
    WEAPON_MG            = { base = 54, ext = 81, ammo = 'ammo_rifle' },            -- GTA 54/100
    WEAPON_COMBATMG      = { base = 100, ext = 150, ammo = 'ammo_rifle' },          -- GTA 100/200
    -- Dark Zone named weapons (bs_darkzone)
    WEAPON_COMBATPDW     = { base = 30, ext = 45, ammo = 'ammo_pistol' },           -- GTA 30/60
    WEAPON_MILITARYRIFLE = { base = 30, ext = 45, ammo = 'ammo_rifle' },            -- GTA 30/45
    WEAPON_HEAVYSHOTGUN  = { base = 6,  ext = 12, ammo = 'ammo_shotgun' },          -- GTA 6/12
}

-- Mag size from config for a weapon name and its fitted set ({ mag = 'extmag' })
-- Returns nil when the weapon is not in the table (caller falls back to engine)
function Weapons.MagSizeFor(weaponName, fitted)
    local m = Weapons.Magazines[weaponName]
    if not m then return nil end
    if fitted and fitted.mag == 'extmag' and m.ext then return m.ext end
    return m.base
end

-- Dark Zone named weapons (bs_darkzone). A pair a gun does not take is never offered by the wheel.
do
    local add = {
        suppressor = { WEAPON_COMBATPDW = 'COMPONENT_AT_AR_SUPP', WEAPON_MILITARYRIFLE = 'COMPONENT_AT_AR_SUPP', WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_SUPP_02' },
        scope      = { WEAPON_COMBATPDW = 'COMPONENT_AT_SCOPE_SMALL', WEAPON_MILITARYRIFLE = 'COMPONENT_AT_SCOPE_SMALL' },
        grip       = { WEAPON_COMBATPDW = 'COMPONENT_AT_AR_AFGRIP', WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_AFGRIP' },
        flashlight = { WEAPON_COMBATPDW = 'COMPONENT_AT_AR_FLSH', WEAPON_MILITARYRIFLE = 'COMPONENT_AT_AR_FLSH', WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_FLSH' },
        extmag     = { WEAPON_COMBATPDW = 'COMPONENT_COMBATPDW_CLIP_02', WEAPON_MILITARYRIFLE = 'COMPONENT_MILITARYRIFLE_CLIP_02', WEAPON_HEAVYSHOTGUN = 'COMPONENT_HEAVYSHOTGUN_CLIP_02' },
    }
    for att, list in pairs(add) do
        local a = Weapons.Attachments[att]
        if a then
            a.components = a.components or {}
            for w, c in pairs(list) do if a.components[w] == nil then a.components[w] = c end end
        end
    end
end

-- Native attachment choices for the expanded firearm catalogue.
do
    Weapons.Attachments.muzzle_brake = {item='att_muzzle_brake',label='Muzzle brake',slot='muzzle',icon='silencer',blurb='A native muzzle brake or compensator for supported weapons.',components={}}
    Weapons.Attachments.reflex = {item='att_reflex',label='Reflex sight',slot='scope',icon='scope',blurb='An open sight for supported Mk II weapons.',components={}}
    Weapons.Attachments.scope_long = {item='att_scope_long',label='Long-range scope',slot='scope',icon='scope',blurb='Higher magnification where the weapon supports a separate scope.',components={}}
    local components = {
        suppressor = {
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_AR_SUPP',
            WEAPON_APPISTOL = 'COMPONENT_AT_PI_SUPP',
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_ASSAULTSHOTGUN = 'COMPONENT_AT_AR_SUPP',
            WEAPON_ASSAULTSMG = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_BULLPUPRIFLE = 'COMPONENT_AT_AR_SUPP',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_AR_SUPP',
            WEAPON_BULLPUPSHOTGUN = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_AR_SUPP',
            WEAPON_HEAVYPISTOL = 'COMPONENT_AT_PI_SUPP',
            WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_HEAVYSNIPER_MK2 = 'COMPONENT_AT_SR_SUPP_03',
            WEAPON_MACHINEPISTOL = 'COMPONENT_AT_PI_SUPP',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_AR_SUPP',
            WEAPON_MICROSMG = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_MILITARYRIFLE = 'COMPONENT_AT_AR_SUPP',
            WEAPON_PISTOL50 = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_PISTOL_MK2 = 'COMPONENT_AT_PI_SUPP_02',
            WEAPON_PUMPSHOTGUN_MK2 = 'COMPONENT_AT_SR_SUPP_03',
            WEAPON_SMG_MK2 = 'COMPONENT_AT_PI_SUPP',
            WEAPON_SNSPISTOL_MK2 = 'COMPONENT_AT_PI_SUPP_02',
            WEAPON_SPECIALCARBINE = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_AR_SUPP_02',
            WEAPON_VINTAGEPISTOL = 'COMPONENT_AT_PI_SUPP',
        },
        scope = {
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_SCOPE_SMALL',
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
            WEAPON_ASSAULTSMG = 'COMPONENT_AT_SCOPE_MACRO',
            WEAPON_BULLPUPRIFLE = 'COMPONENT_AT_SCOPE_SMALL',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_SCOPE_SMALL_MK2',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
            WEAPON_COMBATMG = 'COMPONENT_AT_SCOPE_MEDIUM',
            WEAPON_COMBATMG_MK2 = 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
            WEAPON_COMBATPDW = 'COMPONENT_AT_SCOPE_SMALL',
            WEAPON_HEAVYSNIPER = 'COMPONENT_AT_SCOPE_LARGE',
            WEAPON_HEAVYSNIPER_MK2 = 'COMPONENT_AT_SCOPE_LARGE_MK2',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
            WEAPON_MICROSMG = 'COMPONENT_AT_SCOPE_MACRO',
            WEAPON_MILITARYRIFLE = 'COMPONENT_AT_SCOPE_SMALL',
            WEAPON_PUMPSHOTGUN_MK2 = 'COMPONENT_AT_SCOPE_SMALL_MK2',
            WEAPON_REVOLVER_MK2 = 'COMPONENT_AT_SCOPE_MACRO_MK2',
            WEAPON_SMG_MK2 = 'COMPONENT_AT_SCOPE_SMALL_SMG_MK2',
            WEAPON_SPECIALCARBINE = 'COMPONENT_AT_SCOPE_MEDIUM',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_SCOPE_MEDIUM_MK2',
        },
        grip = {
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
            WEAPON_ASSAULTSHOTGUN = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_BULLPUPRIFLE = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
            WEAPON_BULLPUPSHOTGUN = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
            WEAPON_COMBATMG = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_COMBATMG_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
            WEAPON_COMBATPDW = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
            WEAPON_SPECIALCARBINE = 'COMPONENT_AT_AR_AFGRIP',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_AR_AFGRIP_02',
        },
        flashlight = {
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_AT_AR_FLSH',
            WEAPON_APPISTOL = 'COMPONENT_AT_PI_FLSH',
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ASSAULTSHOTGUN = 'COMPONENT_AT_AR_FLSH',
            WEAPON_ASSAULTSMG = 'COMPONENT_AT_AR_FLSH',
            WEAPON_BULLPUPRIFLE = 'COMPONENT_AT_AR_FLSH',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_BULLPUPSHOTGUN = 'COMPONENT_AT_AR_FLSH',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_COMBATPDW = 'COMPONENT_AT_AR_FLSH',
            WEAPON_HEAVYPISTOL = 'COMPONENT_AT_PI_FLSH',
            WEAPON_HEAVYSHOTGUN = 'COMPONENT_AT_AR_FLSH',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_MICROSMG = 'COMPONENT_AT_PI_FLSH',
            WEAPON_MILITARYRIFLE = 'COMPONENT_AT_AR_FLSH',
            WEAPON_PISTOL50 = 'COMPONENT_AT_PI_FLSH',
            WEAPON_PISTOL_MK2 = 'COMPONENT_AT_PI_FLSH_02',
            WEAPON_PUMPSHOTGUN_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_REVOLVER_MK2 = 'COMPONENT_AT_PI_FLSH',
            WEAPON_SMG_MK2 = 'COMPONENT_AT_AR_FLSH',
            WEAPON_SNSPISTOL_MK2 = 'COMPONENT_AT_PI_FLSH_03',
            WEAPON_SPECIALCARBINE = 'COMPONENT_AT_AR_FLSH',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_AR_FLSH',
        },
        extmag = {
            WEAPON_ADVANCEDRIFLE = 'COMPONENT_ADVANCEDRIFLE_CLIP_02',
            WEAPON_APPISTOL = 'COMPONENT_APPISTOL_CLIP_02',
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_ASSAULTRIFLE_MK2_CLIP_02',
            WEAPON_ASSAULTSHOTGUN = 'COMPONENT_ASSAULTSHOTGUN_CLIP_02',
            WEAPON_ASSAULTSMG = 'COMPONENT_ASSAULTSMG_CLIP_02',
            WEAPON_BULLPUPRIFLE = 'COMPONENT_BULLPUPRIFLE_CLIP_02',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_BULLPUPRIFLE_MK2_CLIP_02',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_CARBINERIFLE_MK2_CLIP_02',
            WEAPON_COMBATMG = 'COMPONENT_COMBATMG_CLIP_02',
            WEAPON_COMBATMG_MK2 = 'COMPONENT_COMBATMG_MK2_CLIP_02',
            WEAPON_COMBATPDW = 'COMPONENT_COMBATPDW_CLIP_02',
            WEAPON_COMPACTRIFLE = 'COMPONENT_COMPACTRIFLE_CLIP_02',
            WEAPON_GUSENBERG = 'COMPONENT_GUSENBERG_CLIP_02',
            WEAPON_HEAVYPISTOL = 'COMPONENT_HEAVYPISTOL_CLIP_02',
            WEAPON_HEAVYSHOTGUN = 'COMPONENT_HEAVYSHOTGUN_CLIP_02',
            WEAPON_HEAVYSNIPER_MK2 = 'COMPONENT_HEAVYSNIPER_MK2_CLIP_02',
            WEAPON_MACHINEPISTOL = 'COMPONENT_MACHINEPISTOL_CLIP_02',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_MARKSMANRIFLE_MK2_CLIP_02',
            WEAPON_MG = 'COMPONENT_MG_CLIP_02',
            WEAPON_MICROSMG = 'COMPONENT_MICROSMG_CLIP_02',
            WEAPON_MILITARYRIFLE = 'COMPONENT_MILITARYRIFLE_CLIP_02',
            WEAPON_PISTOL50 = 'COMPONENT_PISTOL50_CLIP_02',
            WEAPON_PISTOL_MK2 = 'COMPONENT_PISTOL_MK2_CLIP_02',
            WEAPON_SMG_MK2 = 'COMPONENT_SMG_MK2_CLIP_02',
            WEAPON_SNSPISTOL_MK2 = 'COMPONENT_SNSPISTOL_MK2_CLIP_02',
            WEAPON_SPECIALCARBINE = 'COMPONENT_SPECIALCARBINE_CLIP_02',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_SPECIALCARBINE_MK2_CLIP_02',
            WEAPON_VINTAGEPISTOL = 'COMPONENT_VINTAGEPISTOL_CLIP_02',
        },
        muzzle_brake = {
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_COMBATMG_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_HEAVYSNIPER_MK2 = 'COMPONENT_AT_MUZZLE_08',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_PISTOL_MK2 = 'COMPONENT_AT_PI_COMP',
            WEAPON_PUMPSHOTGUN_MK2 = 'COMPONENT_AT_MUZZLE_08',
            WEAPON_REVOLVER_MK2 = 'COMPONENT_AT_PI_COMP_03',
            WEAPON_SMG_MK2 = 'COMPONENT_AT_MUZZLE_01',
            WEAPON_SNSPISTOL_MK2 = 'COMPONENT_AT_PI_COMP_02',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_MUZZLE_01',
        },
        reflex = {
            WEAPON_ASSAULTRIFLE_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_BULLPUPRIFLE_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_CARBINERIFLE_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_COMBATMG_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_PISTOL_MK2 = 'COMPONENT_AT_PI_RAIL',
            WEAPON_PUMPSHOTGUN_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_REVOLVER_MK2 = 'COMPONENT_AT_SIGHTS',
            WEAPON_SMG_MK2 = 'COMPONENT_AT_SIGHTS_SMG',
            WEAPON_SNSPISTOL_MK2 = 'COMPONENT_AT_PI_RAIL_02',
            WEAPON_SPECIALCARBINE_MK2 = 'COMPONENT_AT_SIGHTS',
        },
        scope_long = {
            WEAPON_HEAVYSNIPER = 'COMPONENT_AT_SCOPE_MAX',
            WEAPON_HEAVYSNIPER_MK2 = 'COMPONENT_AT_SCOPE_MAX',
            WEAPON_MARKSMANRIFLE_MK2 = 'COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM_MK2',
        },
    }
    for id,mapping in pairs(components)do
        for weapon,component in pairs(mapping)do Weapons.Attachments[id].components[weapon]=component end
    end
    local known={};for _,weapon in ipairs(Weapons.Known)do known[weapon]=true end
    local magazines={
        WEAPON_GUSENBERG = {base=30,ext=50,ammo='ammo_pistol'},
        WEAPON_PISTOL_MK2 = {base=12,ext=16,ammo='ammo_pistol'},
        WEAPON_SNSPISTOL_MK2 = {base=6,ext=12,ammo='ammo_pistol'},
        WEAPON_REVOLVER_MK2 = {base=6,ammo='ammo_magnum'},
        WEAPON_SMG_MK2 = {base=30,ext=45,ammo='ammo_pistol'},
        WEAPON_ASSAULTRIFLE_MK2 = {base=30,ext=45,ammo='ammo_rifle'},
        WEAPON_CARBINERIFLE_MK2 = {base=30,ext=45,ammo='ammo_rifle'},
        WEAPON_SPECIALCARBINE_MK2 = {base=30,ext=45,ammo='ammo_rifle'},
        WEAPON_BULLPUPRIFLE_MK2 = {base=30,ext=45,ammo='ammo_rifle'},
        WEAPON_COMBATMG_MK2 = {base=100,ext=150,ammo='ammo_rifle'},
        WEAPON_PUMPSHOTGUN_MK2 = {base=8,ammo='ammo_shotgun'},
        WEAPON_HEAVYSNIPER_MK2 = {base=6,ext=8,ammo='ammo_rifle'},
        WEAPON_MARKSMANRIFLE_MK2 = {base=8,ext=12,ammo='ammo_rifle'},
    }
    for weapon,definition in pairs(magazines)do
        Weapons.Magazines[weapon]=definition
        if not known[weapon]then Weapons.Known[#Weapons.Known+1]=weapon;known[weapon]=true end
    end
    Weapons.Effects.muzzle_brake={}
    Weapons.Effects.reflex={zoom=1.0}
    Weapons.Effects.scope_long={zoom=1.0}
end

-- Optics and grips also remain available on the original firearm catalogue.
do
    local add={
        scope={WEAPON_MG='COMPONENT_AT_SCOPE_SMALL_02'},
        scope_long={WEAPON_SNIPERRIFLE='COMPONENT_AT_SCOPE_MAX'},
    }
    for id,mapping in pairs(add)do for weapon,component in pairs(mapping)do Weapons.Attachments[id].components[weapon]=component end end
end

-- Customize Weapon workbench backdrops. A place is streamed in behind the gun, thrown out of focus (camera depth of
-- field) and darkened by a see-through veil behind the weapon, so only a dark hint of it shows.
-- camera / lookAt: where the backdrop camera stands and what it looks at. darkness: 0 (none) to 1 (black).
-- blur: depth-of-field strength 0-1. interior = true pins the interior at lookAt while open.
-- solid = plain black. capture = the older blurred snapshot of where you stand.
-- Coordinates are vanilla GTA spots; move them to places on your own map.
Weapons.Workbench = {
    backdrop = 'workshop',
    backdrops = {
        { id = 'workshop',  label = 'Workshop',
          camera = { x = -338.6, y = -136.9, z = 39.6 }, lookAt = { x = -330.0, y = -139.5, z = 38.9 },
          interior = true, darkness = 0.72, blur = 1.0 },
        { id = 'grapeseed', label = 'Grapeseed street',
          camera = { x = 1666.0, y = 4857.8, z = 43.2 }, lookAt = { x = 1667.4, y = 4874.0, z = 42.4 },
          darkness = 0.78, blur = 1.0 },
        { id = 'bunker',    label = 'Bunker',
          camera = { x = -2145.5, y = 3146.0, z = 33.6 }, lookAt = { x = -2135.0, y = 3156.0, z = 33.0 },
          darkness = 0.80, blur = 1.0 },
        { id = 'here',      label = 'Where I stand', capture = true },
        { id = 'black',     label = 'Black', solid = true },
    },
}
