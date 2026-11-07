AZTester = {}
AZTester.Ace = 'alpha_z.tester'
AZTester.Command = 'alpha_z_testmenu'
AZTester.VehicleCooldownMs = 12000
AZTester.ItemCooldownMs = 3500
AZTester.UtilityCooldownMs = 5000
AZTester.MaxVehiclesPerTester = 2
AZTester.MaxItemAmount = 5
AZTester.EnableSelfHeal = true
AZTester.EnableRepair = true
AZTester.EnableCoords = true
-- Server authoritative, explicit allowlists; never grant bs.admin or bs.superadmin.
-- Only add models/items you intentionally want testers to use.
AZTester.Vehicles = {
 {label='Überlebensfahrzeuge', entries={
  {model='emperor2',label='Emperor'}, {model='tornado3',label='Tornado'},
  {model='voodoo2',label='Voodoo'}, {model='ratloader',label='Rat-Loader'},
  {model='rebel',label='Rebel'}, {model='surfer2',label='Surfer'},
  {model='journey',label='Journey'}, {model='flatbed',label='Flatbed'},
  {model='bodhi2',label='Bodhi'}, {model='dloader',label='Duneloader'},
  {model='wastelander',label='Wastelander'}, {model='ratbike',label='Rat Bike'},
  {model='bmx',label='BMX'}
 }},
 {label='Fahrzeugtests',entries={
  {model='sandking',label='Sandking'}, {model='kamacho',label='Kamacho'},
  {model='ambulance',label='Krankenwagen'}
 }}
}
-- Only tester-approved items. Verified against bs_inventory config_items / config_clothing.
-- Weapon IDs are inventory item IDs, NOT GTA weapon hashes.
AZTester.Items = {
 {label='Überleben & Ausrüstung',entries={
  {name='bandage',label='Verband'}, {name='medkit',label='Medkit'},
  {name='water_bottle',label='Wasserflasche'}, {name='canned_food',label='Konserve'},
  {name='repair_kit',label='Reparaturset'}, {name='lockpick',label='Dietrich'},
  {name='toolbox',label='Werkzeugkoffer'},
  {name='phone',label='Handy'},
  {name='pack_small',label='Kleine Tasche'},
  {name='pack_medium',label='Mittlere Tasche'},
  {name='pack_large',label='Große Tasche'}
 }},
 {label='Herstellung (ohne Autoteile)', entries={
  {name='scrap_metal',label='Schrottmetall'}, {name='cloth',label='Stoff'},
  {name='wood_plank',label='Holzbrett'}
 }},
 {label='Waffen',entries={
  {name='hunting_knife',label='Jagdmesser'}, {name='hammer',label='Hammer'},
  {name='weapon_stone_hatchet',label='Stone Hatchet'},
  {name='crossbow',label='Armbrust'},
  {name='weapon_poolcue',label='Barbed Wire Bat'}
 }}
}

-- Own-account building waiver. Requires bs_building's material checks to consume this export.
AZTester.EnableFreeBuild = true
