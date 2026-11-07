// Simple mode for the F1 console.
// The advanced list shows all ~375 tunables with config paths. This is a short
// page of plain questions, each setting the real tunables through the same
// pending/apply flow, so profiles, presets, the audit log and Apply still work.
// Entry kinds:
//   choice  named buttons; each option sets values or `mul` x the file default
//   single  one real setting with a friendly name and help text
// Entries whose setting does not exist on this server are skipped.
window.BSSimple = [
  { section: 'Zombies', items: [
    { kind: 'choice', label: 'How many zombies', help: 'How crowded the world feels around players.',
      options: [
        { label: 'Few',    mul: 0.5 }, { label: 'Normal', mul: 1.0 }, { label: 'Many', mul: 1.5 }, { label: 'Swarm', mul: 2.0 } ],
      ids: ['bs_zombies:Zombies.Net.baseCap', 'bs_zombies:Zombies.Net.perPlayerCap', 'bs_zombies:Zombies.Net.hardCap', 'bs_zombies:Zombies.Net.perPlayerNear'] },
    { kind: 'choice', label: 'Zombie toughness', help: 'How many hits they take. Headshots still kill fastest.',
      options: [ { label: 'Weak', mul: 0.6 }, { label: 'Normal', mul: 1.0 }, { label: 'Tough', mul: 1.5 }, { label: 'Brutal', mul: 2.0 } ],
      ids: ['bs_zombies:Zombies.Types.walker.health', 'bs_zombies:Zombies.Types.brute.health', 'bs_zombies:Zombies.Types.crawler.health'] },
    { kind: 'choice', label: 'Zombie damage', help: 'How much a grab or hit hurts.',
      options: [ { label: 'Low', mul: 0.5 }, { label: 'Normal', mul: 1.0 }, { label: 'High', mul: 1.5 }, { label: 'Deadly', mul: 2.0 } ],
      ids: ['bs_zombies:Zombies.Types.walker.damage', 'bs_zombies:Zombies.Types.brute.damage'] },
    // Each preset moves the whole set together: the ring, the three floors that
    // would otherwise block it, and the cleanup/despawn distances, which must stay
    // outside the furthest spawn (ring + 120m open-ground push).
    { kind: 'choice', label: 'Spawn distance', help: 'How far away zombies appear. They always appear out of sight and walk in. Needs a bs_zombies restart.',
      options: [
        { label: 'Very close (50-130m)', set: { 'bs_zombies:Streaming.spawnMin': 50, 'bs_zombies:Streaming.spawnMax': 130, 'bs_zombies:Streaming.spawnFloor': 50, 'bs_zombies:Streaming.Placement.minPlayerDistance': 50, 'bs_zombies:Noise.Materialise.hardFloor': 50, 'bs_zombies:Streaming.cleanupDistance': 400, 'bs_zombies:Zombies.Settings.despawnDistance': 420 } },
        { label: 'Close (75-165m)', set: { 'bs_zombies:Streaming.spawnMin': 75, 'bs_zombies:Streaming.spawnMax': 165, 'bs_zombies:Streaming.spawnFloor': 75, 'bs_zombies:Streaming.Placement.minPlayerDistance': 75, 'bs_zombies:Noise.Materialise.hardFloor': 75, 'bs_zombies:Streaming.cleanupDistance': 400, 'bs_zombies:Zombies.Settings.despawnDistance': 420 } },
        { label: 'Default (100-200m)', set: { 'bs_zombies:Streaming.spawnMin': 100, 'bs_zombies:Streaming.spawnMax': 200, 'bs_zombies:Streaming.spawnFloor': 100, 'bs_zombies:Streaming.Placement.minPlayerDistance': 100, 'bs_zombies:Noise.Materialise.hardFloor': 100, 'bs_zombies:Streaming.cleanupDistance': 400, 'bs_zombies:Zombies.Settings.despawnDistance': 420 } },
        { label: 'Medium (125-225m)', set: { 'bs_zombies:Streaming.spawnMin': 125, 'bs_zombies:Streaming.spawnMax': 225, 'bs_zombies:Streaming.spawnFloor': 125, 'bs_zombies:Streaming.Placement.minPlayerDistance': 125, 'bs_zombies:Noise.Materialise.hardFloor': 125, 'bs_zombies:Streaming.cleanupDistance': 405, 'bs_zombies:Zombies.Settings.despawnDistance': 425 } },
        { label: 'Normal (150-250m)', set: { 'bs_zombies:Streaming.spawnMin': 150, 'bs_zombies:Streaming.spawnMax': 250, 'bs_zombies:Streaming.spawnFloor': 150, 'bs_zombies:Streaming.Placement.minPlayerDistance': 150, 'bs_zombies:Noise.Materialise.hardFloor': 150, 'bs_zombies:Streaming.cleanupDistance': 430, 'bs_zombies:Zombies.Settings.despawnDistance': 450 } },
        { label: 'Far (200-300m)', set: { 'bs_zombies:Streaming.spawnMin': 200, 'bs_zombies:Streaming.spawnMax': 300, 'bs_zombies:Streaming.spawnFloor': 200, 'bs_zombies:Streaming.Placement.minPlayerDistance': 200, 'bs_zombies:Noise.Materialise.hardFloor': 200, 'bs_zombies:Streaming.cleanupDistance': 480, 'bs_zombies:Zombies.Settings.despawnDistance': 500 } },
        { label: 'Very far (250-350m)', set: { 'bs_zombies:Streaming.spawnMin': 250, 'bs_zombies:Streaming.spawnMax': 350, 'bs_zombies:Streaming.spawnFloor': 250, 'bs_zombies:Streaming.Placement.minPlayerDistance': 250, 'bs_zombies:Noise.Materialise.hardFloor': 250, 'bs_zombies:Streaming.cleanupDistance': 530, 'bs_zombies:Zombies.Settings.despawnDistance': 550 } },
      ] },
    { kind: 'single', id: 'bs_zombies:Streaming.spawnMin', label: 'Closest spawn (m)', help: 'Fine-tune after picking a preset. Keep the three floors in Advanced equal to this.' },
    { kind: 'single', id: 'bs_zombies:Streaming.spawnMax', label: 'Farthest spawn (m)', help: 'Fine-tune after picking a preset.' },
    { kind: 'single', id: 'bs_zombies:Zombies.Settings.headshotMultiplier', label: 'Headshot damage', help: 'Multiplier for hits to the head.' },
    { kind: 'single', id: 'bs_zombies:Zones.Scaling.nightMultiplier', label: 'Extra zombies at night', help: '1 = same as day. 1.5 = half as many again.' },
    { kind: 'single', id: 'bs_zombies:Zombies.Horde.enabled', label: 'Random hordes', help: 'Big groups that build up where players make lots of noise.' },
    { kind: 'choice', label: 'Zombie difficulty', help: 'Health, damage, horde size and density together. Fine tune in the advanced list.',
      options: [
        { label: 'Weak', set: { 'bs_zombies:Zombies.Difficulty.healthMult': 0.8, 'bs_zombies:Zombies.Difficulty.speedMult': 0.9, 'bs_zombies:Zombies.Difficulty.damageMult': 0.75, 'bs_zombies:Zombies.Difficulty.hordeMult': 0.75, 'bs_zombies:Zombies.Difficulty.densityMult': 0.85 } },
        { label: 'Normal', set: { 'bs_zombies:Zombies.Difficulty.healthMult': 1, 'bs_zombies:Zombies.Difficulty.speedMult': 1, 'bs_zombies:Zombies.Difficulty.damageMult': 1, 'bs_zombies:Zombies.Difficulty.hordeMult': 1, 'bs_zombies:Zombies.Difficulty.densityMult': 1 } },
        { label: 'Tough', set: { 'bs_zombies:Zombies.Difficulty.healthMult': 1.25, 'bs_zombies:Zombies.Difficulty.speedMult': 1.1, 'bs_zombies:Zombies.Difficulty.damageMult': 1.3, 'bs_zombies:Zombies.Difficulty.hordeMult': 1.35, 'bs_zombies:Zombies.Difficulty.densityMult': 1.2 } },
        { label: 'Brutal', set: { 'bs_zombies:Zombies.Difficulty.healthMult': 1.6, 'bs_zombies:Zombies.Difficulty.speedMult': 1.15, 'bs_zombies:Zombies.Difficulty.damageMult': 1.6, 'bs_zombies:Zombies.Difficulty.hordeMult': 1.7, 'bs_zombies:Zombies.Difficulty.densityMult': 1.4 } },
      ] },
    { kind: 'single', id: 'bs_zombies:Zombies.Difficulty.Progression.enabled', label: 'Zombies scale with player level', help: 'Tougher walkers around higher level players.' },
  ]},
  { section: 'Survival', items: [
    { kind: 'choice', label: 'Hunger and thirst', help: 'How fast players get hungry and thirsty.',
      options: [ { label: 'Relaxed', set: { '_global:Global.hungerRateMultiplier': 0.6, '_global:Global.thirstRateMultiplier': 0.6 } },
                 { label: 'Normal',  set: { '_global:Global.hungerRateMultiplier': 1.0, '_global:Global.thirstRateMultiplier': 1.0 } },
                 { label: 'Harsh',   set: { '_global:Global.hungerRateMultiplier': 1.5, '_global:Global.thirstRateMultiplier': 1.5 } } ] },
    { kind: 'single', id: 'bs_core:Config.Infection.enabled', label: 'Infection from bites', help: 'Zombie hits slowly infect the player.' },
    { kind: 'single', id: 'bs_medical:Medical.Settings.bleedoutTime', label: 'Time before bleeding out (seconds)', help: 'How long a downed player waits for help.' },
    { kind: 'single', id: 'bs_core:Config.Death.keepInventory', label: 'Keep inventory on death', help: 'Off = you drop everything where you died.' },
  ]},
  { section: 'Loot and progress', items: [
    { kind: 'choice', label: 'Loot', help: 'How much you find in containers and on zombies.',
      options: [ { label: 'Scarce', set: { '_global:Global.lootMultiplier': 0.6, '_global:Global.lootRollsMultiplier': 0.8 } },
                 { label: 'Normal', set: { '_global:Global.lootMultiplier': 1.0, '_global:Global.lootRollsMultiplier': 1.0 } },
                 { label: 'Plenty', set: { '_global:Global.lootMultiplier': 1.5, '_global:Global.lootRollsMultiplier': 1.25 } } ] },
    { kind: 'single', id: '_global:Global.xpMultiplier', label: 'XP speed', help: '2 = level up twice as fast.' },
    { kind: 'single', id: '_global:Global.traderPriceMultiplier', label: 'Trader prices', help: '0.5 = half price, 2 = double.' },
    { kind: 'single', id: '_global:Global.recoilMultiplier', label: 'Weapon recoil', help: 'Lower = easier to control.' },
  ]},
  { section: 'World', items: [
    { kind: 'single', id: 'bs_world:World.Time.rate', label: 'Time speed', help: 'Game minutes per real minute. 12 = a day lasts 2 hours.' },
    { kind: 'single', id: 'bs_world:World.Time.frozen', label: 'Freeze time', help: 'Stops the clock where it is.' },
    { kind: 'single', id: 'bs_world:World.Weather.frozen', label: 'Freeze weather', help: 'Keeps the current weather.' },
    { kind: 'single', id: 'bs_world:World.Weather.startWith', label: 'Starting weather', help: 'Weather when the server starts.' },
  ]},
  { section: 'Vanilla Faction Safezones', items: [
    { kind: 'single', id: '_global:Global.FactionSafe.military.enabled', label: 'Military Safezone on' },
    { kind: 'single', id: '_global:Global.FactionSafe.military.x', label: 'Military Safezone X' },
    { kind: 'single', id: '_global:Global.FactionSafe.military.y', label: 'Military Safezone Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.military.z', label: 'Military Safezone Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.military.radius', label: 'Military Safezone radius (m)' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels.enabled', label: 'Rebels Safezone on' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels.x', label: 'Rebels Safezone X' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels.y', label: 'Rebels Safezone Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels.z', label: 'Rebels Safezone Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels_outpost.enabled', label: 'Rebels Outpost on' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels_outpost.x', label: 'Rebels Outpost X' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels_outpost.y', label: 'Rebels Outpost Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels_outpost.z', label: 'Rebels Outpost Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.rebels_outpost.radius', label: 'Rebels Outpost radius (m)' },
    { kind: 'single', id: '_global:Global.FactionSafe.civilians.enabled', label: 'Civilians Safezone on' },
    { kind: 'single', id: '_global:Global.FactionSafe.civilians.x', label: 'Civilians Safezone X' },
    { kind: 'single', id: '_global:Global.FactionSafe.civilians.y', label: 'Civilians Safezone Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.civilians.z', label: 'Civilians Safezone Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.civilians.radius', label: 'Civilians Safezone radius (m)' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers.enabled', label: 'Bikers Safezone on' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers.x', label: 'Bikers Safezone X' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers.y', label: 'Bikers Safezone Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers.z', label: 'Bikers Safezone Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers.radius', label: 'Bikers Safezone radius (m)' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers_outpost.enabled', label: 'Bikers Outpost on' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers_outpost.x', label: 'Bikers Outpost X' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers_outpost.y', label: 'Bikers Outpost Y' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers_outpost.z', label: 'Bikers Outpost Z' },
    { kind: 'single', id: '_global:Global.FactionSafe.bikers_outpost.radius', label: 'Bikers Outpost radius (m)' },
  ] },
  { section: 'Events', items: [
    { kind: 'single', id: 'bs_events:Events.Settings.enabled', label: 'Scheduled events', help: 'Master switch for airdrops, stashes, convoys and hordes.' },
    { kind: 'single', id: 'bs_events:Events.Schedule.airdrop.enabled', label: 'Airdrops', help: '' },
    { kind: 'single', id: 'bs_events:Events.Schedule.stash.enabled', label: 'Supply stashes', help: '' },
    { kind: 'single', id: 'bs_events:Events.Schedule.convoy.enabled', label: 'Military convoys', help: '' },
    { kind: 'single', id: 'bs_events:Events.Schedule.horde.enabled', label: 'Horde waves', help: '' },
  ]},
];
