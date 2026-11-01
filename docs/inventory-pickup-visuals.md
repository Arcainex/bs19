# Inventory pickup visuals

This is an extension of [BeyondSurvival](https://bs19.org), under the repository's existing license. It adds a cosmetic receipt to the existing inventory NUI. Existing text notifications and inventory authority are unchanged. There is no new resource, image library, database query, client inventory simulation, or client-to-server inventory event.

## Native appearance

`bs_inventory/html/js/slots.js` is the shared plate renderer. The normal inventory grid and pickup visuals both use it, the original `BSIcons.get` artwork, and the existing `.grid`, `.cell`, `.slot.has-item`, `.slot__icon`, `.slot__foot`, and `.slot__amount` CSS rules. No pickup-specific plate colors, borders, fonts, image sizes, shadows or rounding are defined. The pickup wrapper owns only placement, input pass-through and opacity fade.

The footprint comes from the confirmed item definition's `w`/`h`, not a fixed new card size. Thus a 1×1 item uses one native cell and a multi-cell item uses its native unrotated grid footprint and gap. Receipt quantities describe the incoming operation, not the final stack total. The receipt intentionally contains only original artwork and `xN`: no item name, fuel/battery percentage, durability bar or additional description. The inventory's existing capacity/battery displays remain unchanged.

The shared renderer also replaces a broken raster image with the existing category SVG fallback from `BSIcons`; it never accepts image URLs or HTML from a network receipt. Item labels in the native renderer use `textContent`. Pickups do not contain a label node or request NUI focus.

## Authoritative integration

`server/sv_pickups.lua` records presentation receipts after successful inventory operations and drains them into the next existing `bs:inventory:state` packet as optional `pickups` metadata. The original packet fields and all inventory/export return values remain compatible. Only a short item descriptor is added; clients do not compute gains by subtracting inventory snapshots.

Covered commit paths in `server/sv_main.lua`:

- `Inv.Give` / `GiveItem`: ordinary loot, crafting results, purchases, rewards and existing server grants.
- `GiveAll`: only after its existing atomic add/rollback succeeds.
- Validated `inventory:move`: entry into the actor's carried inventory from an external container, including partial stack merges and swaps. The recorded amount is the actual committed amount, not the requested merge amount.
- `MoveFromContainer`: after its successful existing operation.
- Optional removals through `Inv.Remove` / `RemoveItem`, `RemoveSlot`, inventory drops and carried/external moves. Specialized wear/death paths are not reclassified as pickup operations.

The bag, bar, equipment and currently worn pack/vest count as one carried inventory. Repositioning, splitting and moving between those regions is silent. Direct player handovers, the existing trade commit, ammo refunds and pending starter loadout are also silent. Accessing an external container counts as an incoming carried-inventory receipt; this layer does not guess ownership of arbitrary vehicle trunks/private storage because the current container registry does not provide that semantic distinction. It does not add a “looted” text notification.

The optional fifth argument to the existing `GiveItem` export can suppress a cosmetic receipt for a caller that already knows it is returning/refunding items:

```lua
exports.bs_inventory:GiveItem(source, item, amount, metadata, { pickup = false })
```

Old four-argument callers continue unchanged. No loot resource needs an individual hook. Receipt records bind to the character who owns the mutated inventory and are checked again when flushed. A logout/character switch during a yielding inventory operation cannot show the old operation to the replacement character. The client also validates the server source, current character, session state and receipt sequence. Pending records are cleared on logout/disconnect.

The original `GiveItem` can partially add items and still return false when later placement fails. This patch deliberately does not change that existing inventory behavior. Such failed operations produce no success visual, rather than claiming the requested amount or announcing a grant that the caller may roll back. `GiveAll` rollback is separately tested. SQL/database failures and transactions retain their existing framework semantics.

## Progress owns the area

`bs_interactions` owns the existing search/progress UI in a different NUI page. Its client now exposes `GetProgressState()` and the local `bs:interactions:progress` event. Starting progress marks the area busy immediately, before its NUI message is sent. Ending it releases the area only after its page actually hides the progress element. A local progress ID prevents an older completion/cancel from releasing a newer bar.

The page reports its actual computed `bottom` placement on startup, progress changes, UI-scale changes and viewport resize. Equal reports are deduplicated. Pickups use this value, so future progress layout edits do not require a matching pickup constant. The current 22vh position is retained only as a fallback when there is no progress owner/initial placement yet. Both pages keep the existing shared UI scale behavior. No additional permanent poll is introduced; the existing shared scale helper is unchanged.

If an older running `bs_interactions` has no state export, the inventory conservatively holds the visuals instead of overlapping an unknown progress bar. If the owner stops/is absent, it releases the area. Updating both changed resources enables the complete feature without a new manifest dependency.

## Configuration

The existing shared inventory configuration file defines `Inventory.PickupVisuals`:

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Enable visual receipts |
| `duration` | `2500` | Visible duration in milliseconds, followed by a 180ms opacity fade |
| `mergeWindow` | `400` | Merge equal item/kind/rarity receipts within this many milliseconds; zero disables merging |
| `maxQueue` | `20` | Maximum waiting visuals, in addition to a currently displayed/paused visual |
| `showReceived` | `true` | Show successful incoming operations |
| `showRemoved` | `false` | Opt in to the supported removal paths above |
| `showAmount` | `true` | Draw the native quantity badge |

These use the existing shared configuration convention, not a new preference store. Edit the configuration and reload the inventory to apply it to all clients. No extra F1 schema or unrelated settings resource is modified. The NUI defensively bounds duration to 100–30000ms, merge window to 0–5000ms and queue size to 1–100.

When full, the queue drops its oldest waiting visual and retains newer receipts; the active/paused slot is preserved. Dropping a visual never changes actual items or original notifications. Merged amounts are exact sums. A same-item receipt that arrives during fade is queued separately. Progress immediately hides a currently displayed receipt, preserving its remaining visible time; it resumes only after the area is free. Reset/logout/resource stop clears pending UI state. There is no idle queue timer, render loop or polling thread.

## Applying an update

Only `bs_inventory` and `bs_interactions` need to be reloaded. Close open inventory windows, then use the normal server console:

```text
refresh
ensure bs_interactions
ensure bs_inventory
```

`refresh` discovers the inventory's added Lua/JS files. The existing UI asset query versions are bumped to avoid an old cached bundle. No full server restart or database migration is required. The inventory prints `pickup visuals ready` when the module loads. This feature does not automatically execute resource restarts.

## Validation

The self-contained tests require Lua 5.4 and Node.js (the browser test uses built-in `WebSocket`, available in current Node releases). No npm dependencies are introduced. Set `CHROME_BIN` when Chromium/Chrome is not at a default location.

```text
lua tests/inventory_pickups/server.lua .
lua tests/inventory_pickups/client.lua .
node tests/inventory_pickups/queue.cjs .
node tests/inventory_pickups/progress.cjs .
node tests/inventory_pickups/browser.cjs . <output-directory>
```

The server tests execute the actual inventory mutation and grid code against a fake SQL adapter. They cover committed amounts, full grids, legacy partial failure, atomic rollback, internal moves, player handovers, bounded merges, separate players/characters and disabled-mode mechanics/query parity. The client/queue/progress tests cover readiness buffering, duplicate packets, ordered/merged items, overflow, missing owner compatibility, pause/resume, stale progress cancellation, reset and safe NUI content.

The real-browser test loads the actual inventory HTML/CSS, original icons and inventory grid renderer alongside the pickup module. It captures the opened inventory, pickup-only, neutral side-by-side comparison, broken-image fallback and actual interaction-progress priority. Three comparison cases cover 1280×720, 1920×1080 and 2560×1440, including a 1.25 UI scale and non-square multi-cell footprint. All plate CSS, dimensions, artwork URLs and quantity styling must match exactly. Neutral screenshot comparisons allow at most 4/255 per color channel for Chromium layer/raster rounding; the 1080p baseline is pixel-identical. This tolerance does not relax CSS or geometry equality. A green embedded-frame background checks that pickup-only does not paint a fullscreen opaque layer. Screenshot artifacts are written outside source control and are not part of the patch.

The server operator has separately confirmed these FiveM ingame results:

- Normal loot/pickup flow works.
- The pickup appears after the progress bar completes.
- The existing text notification remains present.
- Crafting works.
- Full-inventory behavior works.
- Cancelling a search works.

The automated/browser results above are distinct from these operator-reported checks. Zombie-specific loot, rewards/purchases, multiple simultaneous players, player transfers, interruption by a new progress bar, resource restart during an active receipt and disabled mode have not been individually confirmed ingame. Their covered inventory/queue/lifecycle paths have automated checks; resource-specific callers are not claimed as end-to-end tested. Compare native and pickup slots in actual FiveM screenshots too, especially with custom palettes/UI scales or runtime icon registration. The committed test suite contains no private server data or ingame screenshots.

## Suggested pull request

Title: `feat(inventory): add item pickup visuals using native inventory slot design`

Description:

> Successful server inventory operations now attach optional visual receipts to the existing inventory-state packet. The inventory NUI queues the original item artwork and received quantity for 2.5 seconds using the same renderer, grid footprint and CSS as native inventory slots. Existing text notifications remain unchanged.
>
> Internal rearrangement, direct player handovers, trade commits and known refunds stay silent. The existing interaction progress UI retains priority through a small local state/placement bridge; waiting or interrupted visuals resume when its area is free. Shared inventory configuration controls activation, duration, merging, queue capacity and optional removals.
>
> Validation: 500 assertions across the actual Lua inventory code, client lifecycle, queue, progress ownership and real-browser visual checks. Seven screenshots cover native-slot comparison at three viewport/scale combinations, the open inventory, pickup-only rendering, missing artwork and actual progress priority. The operator additionally confirmed normal loot/pickup, display after progress, unchanged notifications, crafting, full inventory and cancelled search ingame. Other ingame cases remain explicitly unconfirmed. No new SQL queries, network event, resource or runtime dependency; see the documented container/legacy partial-add limitations.
