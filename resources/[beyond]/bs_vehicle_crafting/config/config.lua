VehicleCraft = {}
VehicleCraft.Job = 'mechanic' -- job remains available; workshop access uses faction membership
VehicleCraft.Faction = 'mechanic_workshop'
VehicleCraft.Storage = { x = 1683.68, y = 3278.41, z = 40.95, radius = 2.4 }
VehicleCraft.Build = { x = 1692.19, y = 3282.08, z = 41.14, h = 349.5, radius = 2.8 }
VehicleCraft.BuildSeconds = 60
VehicleCraft.Parts = {
  { item='engine_part', label='Motor' }, { item='gearbox', label='Getriebe' },
  { item='bonnet', label='Motorhaube' }, { item='rear_bumper', label='Heckstoßstange' },
  { item='tyre', label='Reifen' }, { item='exhaust', label='Auspuff' },
  { item='fuel_tank', label='Benzintank' }, { item='car_door', label='Autotür' },
  { item='battery', label='Autobatterie' },

  -- Motorrad-Komponenten aus der Loot-Tabelle
  { item='motorcycle_handlebar', label='Motorrad Lenker' },
  { item='motorcycle_tank', label='Motorrad Tank' },
  { item='motorcycle_seat', label='Motorrad Sitz' },
  { item='motorcycle_brakes', label='Motorrad Bremsen' },
  { item='motorcycle_engine', label='Motorrad Motor' },
  { item='motorcycle_chassis', label='Motorrad Chassis' },

  -- Fahrrad-Komponenten aus der Loot-Tabelle
  { item='bicycle_handlebar', label='Fahrradlenker' },
  { item='bicycle_tyre', label='Fahrradreifen' },
  { item='bicycle_frame', label='Fahrradrahmen' },
  { item='bicycle_saddle', label='Fahrradsattel' },
  { item='bicycle_chain', label='Fahrradkette' },
  { item='bicycle_pedals', label='Fahrradpedale' },
}
local function r(engine,gearbox,bonnet,bumper,tyre,exhaust,tank,door,battery)
 return {engine_part=engine,gearbox=gearbox,bonnet=bonnet,rear_bumper=bumper,tyre=tyre,exhaust=exhaust,fuel_tank=tank,car_door=door,battery=battery}
end
local function motorcycleRecipe()
 return {
  motorcycle_handlebar=1, motorcycle_tank=1, motorcycle_seat=1,
  motorcycle_brakes=1, motorcycle_engine=1, motorcycle_chassis=1, tyre=2
 }
end
local function bicycleRecipe()
 return {
  bicycle_handlebar=1, bicycle_tyre=2, bicycle_frame=1,
  bicycle_saddle=1, bicycle_chain=1, bicycle_pedals=1
 }
end
VehicleCraft.Recipes = {
 {id='emperor2',label='Emperor',recipe=r(1,1,1,1,4,1,1,4,1)},
 {id='tornado3',label='Tornado',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='tornado4',label='Tornado Cabrio',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='voodoo2',label='Voodoo',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='ratloader',label='Rat-Loader',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='rebel',label='Rebel',recipe=r(1,1,1,1,4,1,1,4,1)},
 {id='surfer2',label='Surfer',recipe=r(1,1,1,1,4,1,1,4,1)},
 {id='journey',label='Journey',recipe=r(1,1,1,1,4,1,1,3,1)},
 {id='flatbed',label='Flatbed',recipe=r(2,1,1,1,6,2,1,2,2)},
 {id='bodhi2',label='Bodhi',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='dloader',label='Duneloader',recipe=r(1,1,1,1,4,1,1,2,1)},
 {id='wastelander',label='Wastelander',recipe=r(2,2,1,1,6,2,2,2,2)},
 {id='ratbike',label='Rat Bike',recipe=motorcycleRecipe()},
 {id='deathbike',label='Deathbike',recipe=motorcycleRecipe()},
 {id='bmx',label='BMX',recipe=bicycleRecipe()},
}
