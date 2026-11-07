-- bs_tutorial config. Text is a locale key (locales/<lang>.lua) or plain text for your own chapters.
-- Camera points: pos = where the camera sits, look = what it looks at. Each chapter flies from point 1 to point 2.
Tutorial = {}
local v3 = vector3

Tutorial.Settings = {
    enabled          = true,   -- /tutorial, pause menu button and the first-spawn offer
    firstSpawnPrompt = true,   -- offer the tutorial to new characters after their first spawn
    factionPicker    = true,   -- new characters choose a vanilla faction before playing
    missionEnabled   = true,   -- opt-in first mission checklist
    command          = 'tutorial',
    chapterSeconds   = 24,     -- auto-advance time per chapter
    doneAfterSeconds = 8,      -- a chapter counts as seen after this long
    combatCooldown   = 30,     -- seconds since last damage before it can start
    hintMinutes      = 10,     -- after Skip, remind "type /tutorial anytime" this much later
    completionXp     = 300,    -- once, first full completion
    smallestBonusCash = 250,   -- once, for joining the faction with the fewest members
    smallestBonusXp   = 150,
    ambientVolume    = 0.22,   -- soft music bed while it plays (0 = off)
    bucketBase       = 30000,  -- private routing bucket = bucketBase + server id
}

-- First full completion.
Tutorial.StarterKit = {
    { item = 'bandage', amount = 2 },
    { item = 'water_bottle', amount = 1 },
    { item = 'canned_food', amount = 1 },
    { item = 'rags', amount = 4 },
}

-- Opt-in first mission: loot any container, craft a bandage, kill zombies outside a safezone.
Tutorial.Mission = {
    kills = 3,
    craftItem = 'bandage',
    reward = {
        { item = 'pistol', amount = 1 },
        { item = 'att_flashlight', amount = 1 },
        { item = 'att_suppressor', amount = 1 },
        { item = 'att_extmag', amount = 1 },
        { item = 'ammo_pistol', amount = 60 },
    },
}

-- Faction picker cards. Ids must match bs_factions vanilla factions. spawn = first spawn point (safezone).
Tutorial.Factions = {
    { id = 'military',  colour = '#7c8f52', spawn = vector4(1744.0, 3265.0, 41.25, 105.0),
      cam = { pos = v3(1680.0, 3190.0, 105.0), look = v3(1744.0, 3265.0, 41.0) } },
    { id = 'rebels',    colour = '#a8453a', spawn = vector4(1015.0, -318.0, 67.0, 0.0),
      cam = { pos = v3(1085.0, -390.0, 120.0), look = v3(1015.0, -318.0, 67.0) } },
    { id = 'civilians', colour = '#c9a24d', spawn = vector4(-266.0, -2049.0, 27.0, 0.0),
      cam = { pos = v3(-335.0, -1975.0, 90.0), look = v3(-266.0, -2049.0, 27.0) } },
    { id = 'bikers',    colour = '#5a6f8a', spawn = vector4(957.24, -206.17, 72.05, 0.0),
      cam = { pos = v3(1025.0, -265.0, 125.0), look = v3(957.0, -206.0, 72.0) } },
}

-- Built-in chapters, in order. Text keys: ch.<id>.t (title) and ch.<id>.1 .. ch.<id>.3.
-- demo: things placed at the scene while it plays. kind = ped | zombie | prop | vehicle. Missing models are skipped.
-- All demo entities are local to the viewer. fuel = true puts a ped at the fuel cap of the vehicle listed before it.
Tutorial.Chapters = {
    { id = 'basics', icon = 'heart',
      keys = { { 'F5', 'k.menu' }, { 'N', 'k.needs' }, { 'M', 'k.map' }, { 'Z', 'k.prone' } },
      cam = { { pos = v3(245.0, -870.0, 72.0), look = v3(195.0, -934.0, 30.0) }, { pos = v3(150.0, -895.0, 52.0), look = v3(195.0, -934.0, 30.0) } },
      demo = { { kind = 'ped', model = 'a_m_y_hiker_01', at = v3(195.0, -934.0, 30.7), h = 140.0, anim = { 'amb@world_human_stand_impatient@male@no_sign@base', 'base' } } } },
    { id = 'inventory', icon = 'bag',
      keys = { { 'I', 'k.inventory' }, { 'TAB', 'k.focus' } },
      -- Open runway apron at LSIA (no walls around it); the runtime check still lifts the camera if anything blocks.
      cam = { { pos = v3(-1260.0, -2985.0, 58.0), look = v3(-1296.0, -3016.0, 13.9) }, { pos = v3(-1350.0, -2985.0, 56.0), look = v3(-1296.0, -3016.0, 13.9) } },
      demo = { { kind = 'prop', model = 'prop_box_wood05a', at = v3(-1294.0, -3014.0, 13.9) },
               { kind = 'ped', model = 'a_m_m_hillbilly_01', at = v3(-1296.0, -3016.0, 13.9), h = 300.0, anim = { 'amb@prop_human_bum_bin@base', 'base' } } } },
    { id = 'zombies', icon = 'skull',
      keys = { { 'ALT', 'k.interact' }, { 'O', 'k.weapons' }, { 'H', 'k.whistle' } },
      -- Los Santos International: high over the runway, open air.
      cam = { { pos = v3(-1270.0, -2985.0, 74.0), look = v3(-1336.0, -3044.0, 13.9) }, { pos = v3(-1405.0, -2990.0, 70.0), look = v3(-1336.0, -3044.0, 13.9) } },
      demo = { { kind = 'zombie', model = 'a_m_m_tramp_01', at = v3(-1334.0, -3040.0, 13.9), h = 200.0 },
               { kind = 'zombie', model = 'a_m_m_hillbilly_02', at = v3(-1340.0, -3042.0, 13.9), h = 210.0 },
               { kind = 'zombie', model = 'a_f_m_tramp_01', at = v3(-1337.0, -3036.0, 13.9), h = 190.0 } } },
    { id = 'medical', icon = 'cross',
      keys = { { 'I', 'k.inventory' } },
      cam = { { pos = v3(345.0, -545.0, 95.0), look = v3(300.0, -584.0, 43.3) }, { pos = v3(265.0, -545.0, 90.0), look = v3(300.0, -584.0, 43.3) } },
      demo = { { kind = 'ped', model = 's_m_m_paramedic_01', at = v3(300.0, -584.0, 43.3), h = 70.0, anim = { 'amb@medic@standing@kneel@base', 'base' } },
               { kind = 'ped', model = 'a_m_y_genstreet_01', at = v3(299.0, -584.2, 43.3), h = 250.0, anim = { 'combat@damage@writhe', 'writhe_loop' } } } },
    { id = 'vehicles', icon = 'fuel',
      keys = { { 'G', 'k.vehicle' } },
      cam = { { pos = v3(-40.0, -1735.0, 45.0), look = v3(-70.0, -1760.0, 29.3) }, { pos = v3(-100.0, -1745.0, 38.0), look = v3(-70.0, -1760.0, 29.3) } },
      demo = { { kind = 'vehicle', model = 'rebel', at = v3(-72.0, -1762.0, 29.3), h = 340.0 },
               { kind = 'ped', model = 's_m_y_xmech_02', at = v3(-69.5, -1763.5, 29.3), h = 70.0, fuel = true, anim = { 'mini@repair', 'fixing_a_ped' } } } },
    { id = 'crafting', icon = 'gear',
      keys = { { 'Y', 'k.craft' } },
      cam = { { pos = v3(1725.0, 3720.0, 52.0), look = v3(1700.0, 3700.0, 34.4) }, { pos = v3(1680.0, 3725.0, 45.0), look = v3(1700.0, 3700.0, 34.4) } },
      demo = { { kind = 'prop', model = 'prop_tool_bench02', at = v3(1700.0, 3700.0, 34.4) },
               { kind = 'ped', model = 'a_m_m_farmer_01', at = v3(1700.0, 3698.8, 34.4), h = 0.0, anim = { 'mini@repair', 'fixing_a_ped' } } } },
    { id = 'factions', icon = 'flag',
      keys = { { 'U', 'k.faction' }, { 'F3', 'k.squad' } },
      cam = { { pos = v3(1680.0, 3190.0, 95.0), look = v3(1744.0, 3265.0, 41.0) }, { pos = v3(1800.0, 3200.0, 80.0), look = v3(1744.0, 3265.0, 41.0) } },
      demo = { { kind = 'ped', model = 's_m_y_marine_01', at = v3(1744.0, 3265.0, 41.2), h = 200.0, anim = { 'mp_player_int_uppersalute', 'mp_player_int_salute' } } } },
    { id = 'building', icon = 'hammer',
      keys = { { 'F2', 'k.build' } },
      cam = { { pos = v3(1535.0, 3635.0, 95.0), look = v3(1500.0, 3600.0, 35.0) }, { pos = v3(1465.0, 3635.0, 90.0), look = v3(1500.0, 3600.0, 35.0) } },
      demo = { { kind = 'prop', model = 'prop_fncwood_16b', at = v3(1500.0, 3602.0, 35.0) },
               { kind = 'prop', model = 'prop_flagpole_1a', at = v3(1503.0, 3598.0, 35.0) } } },
    { id = 'traders', icon = 'coin',
      keys = { { 'ALT', 'k.interact' } },
      -- The fallen bridge ([map] thefallofthebridge, ~ -340, -2370).
      cam = { { pos = v3(-245.0, -2285.0, 95.0), look = v3(-345.0, -2370.0, 40.0) }, { pos = v3(-435.0, -2290.0, 90.0), look = v3(-345.0, -2370.0, 40.0) } },
      demo = {} },
    { id = 'safezones', icon = 'shield',
      keys = {},
      cam = { { pos = v3(1090.0, -380.0, 125.0), look = v3(1015.0, -318.0, 67.0) }, { pos = v3(950.0, -380.0, 115.0), look = v3(1015.0, -318.0, 67.0) } },
      demo = {} },
    { id = 'events', icon = 'drop',
      keys = {},
      cam = { { pos = v3(-1250.0, -2850.0, 60.0), look = v3(-1300.0, -2900.0, 13.9) }, { pos = v3(-1350.0, -2850.0, 40.0), look = v3(-1300.0, -2900.0, 13.9) } },
      demo = { { kind = 'prop', model = 'prop_drop_armscrate_01', at = v3(-1300.0, -2900.0, 13.9) },
               { kind = 'prop', model = 'prop_box_ammo04a', at = v3(-1302.0, -2898.0, 13.9) } } },
    { id = 'settings', icon = 'sliders',
      keys = { { 'ESC', 'k.pause' }, { 'I', 'k.inventory' } },
      cam = { { pos = v3(760.0, 1100.0, 380.0), look = v3(720.0, 1200.0, 330.0) }, { pos = v3(650.0, 1090.0, 360.0), look = v3(720.0, 1200.0, 330.0) } },
      demo = {} },
}

-- Your own chapters, played after the built-in ones. Plain text works here, no locale file needed.
-- Example:
-- { id = 'ourrules', icon = 'shield', title = 'Our house rules', lines = { 'Be nice.', 'Have fun.' },
--   keys = {}, cam = { { pos = vector3(0.0, 0.0, 100.0), look = vector3(10.0, 10.0, 70.0) }, { pos = vector3(20.0, 0.0, 100.0), look = vector3(10.0, 10.0, 70.0) } } },
Tutorial.CustomChapters = {}
