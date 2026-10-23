# bs_building

Player bases built from GTA props. You place a frame, put the materials in it and finish it with a hammer.
Default rules: no raiding, no decay, zombies never touch bases.

## Player flow
- **F2** opens the build wheel: pick a category, then a piece. Each piece shows its cost.
- Placing: the ghost turns green or red and says why. Mouse wheel rotates, Shift toggles snapping, left click places, right click cancels.
- Foundations, walls, doorways, window walls, floors, hatch floors, roofs, stairs and walkways snap to each other. Doors, windows and hatches snap into their slot.
- A frame needs the materials deposited, then "Hammer it together". Frames and repairs also take materials from your own boxes within 10 m.
- Demolish = pick up: 100% refund within 10 minutes of placing, 50% after (F1). Only the owner (or a faction rank with `demolish`) can do it.
- Limits: 150 pieces per player (F1 `playerPieceCap`), some pieces have their own limit (3 vending crates).
- Where you can build (F1 Building): not in safezones and outposts (plus padding), not in staff blocked areas, not inside another faction's flag. With `allowedOnly` on, only inside staff allowed areas.

## Locks
Doors, gates, hatches and boxes start with a **faction lock**: the owner and the owner's faction.
The owner can switch to a **code lock** (4 digits, anyone who enters it once is remembered; changing the code forgets them) or remove the lock.

## Storage and vending
- Small and large boxes are persisted containers that respect the lock.
- **Vending crate**: the owner fills it with "Stock crate" and sets a price per item in "Browse crate" (0 = not for sale).
  Anyone else buys from the same panel, also while the owner is offline. Money goes into the crate; the owner collects it later
  (or gets it when picking the crate up). Only stackable items can be sold. F1: on/off, max price, tax.

## Materials
Planks, logs, nails, scrap metal and the hammer: found in loot (workshop, rural, urban), gathered (wood piles, trees),
crafted (planks, nails, hammer at the workbench) and sold by junk dealers and camp traders.

## Staff
- F10 > World > Bases (or `/buildbases`): bases grouped by owner, teleport, delete a piece or a whole base, move to a faction.
- `/removebase <charId>` removes one player's base. `/clearbuilds [radius]` clears around you.
- `/buildzone add block|allow <radius> [name]` at your position, `/buildzone remove <id>`, `/buildzone list` (shows them on the map for 60 s).
  Fixed areas can also go in `Building.Zones` in the config.
- Every staff action and every zone change is logged to `bs_guard_log` (kinds `build_*`).

## Optional (F1, off by default)
- `raidsEnabled`: raid window, declared raids, sledgehammer, angle grinder, explosives and ramming.
- `decayEnabled`: faction bases nobody visits for `decayDays` lose HP.
- `buildMode = claim`: the old faction-flag rule (build only inside your flag, limit per faction).

## For other resources
Server exports:
```lua
exports.bs_building:RegisterPlaceable({
    id = 'workbench', cat = 'utility', size = { 1.6, 0.8, 1.0 }, health = 500,
    models = { 'prop_tool_bench02' }, cost = { { item = 'wood_plank', amount = 5 } },
    support = 'any', station = 'workbench',
})
exports.bs_building:PiecesInRadius(x, y, z, r) -- views: id, p (def id), f (faction), ow (owner char), b (built) ...
exports.bs_building:NearStation(src, 'workbench', 4.0)
exports.bs_building:RaidOpen()
exports.bs_building:GetRespawnPoint(charId)       -- used by bs_medical
```
You can also add pieces straight into `Building.Pieces` in `config/config_building.lua`.
At start, `exports.bs_crafting:StationDefs()` is read if that resource is running.

Server event: `bs:building:pieceRemoved (id, defId)` fires on every removal.

Client export: `exports.bs_building:StartPlacing(defId)`.

## Data
Migration `bs_core/sql/031_building.sql` adds `bs_build_pieces` and `bs_build_bases` and moves the old per-character structures from `bs_world_objects` over. `042_build_zones.sql` adds `bs_build_zones` and an owner index.
Raids, demolitions and staff actions are logged to `bs_guard_log` with kinds `build_*`.

## Props
Each piece lists several base-game models, and the first one the game has is used. If a prop looks wrong, swap the models list.
