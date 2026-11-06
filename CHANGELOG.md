# Changelog

## BS19 v1.1.0

The first big content update since the beta. It adds parkour, a new fighting system, Survivor Link companions, a Dark Zone, proximity voice with radios, a weapon customizer and a lot of fixes. Several of these systems are new and only lightly tested, so read the known issues below before you put it on a live server.

### New

- Parkour: vaults, climbs, wall kicks, ledge hangs, landing rolls and the Mouse 4 slide. Built on the game's own climb with a stuck-move guard (`/parkourreset`).
- Fighting: freeflow melee against zombies and players. Tap LMB for light hits, hold it for heavy hits and finishers, RMB to lock on, plus Q and R. Each weapon has its own hits-to-kill (blades 1, blunt 3-4, fists 6).
- Fighting and parkour test menu for admins (bs_fpdebug).
- Survivor Link: an NPC companion who follows or holds position, trades with you, joins your squad frames and can be revived. Has its own admin tab in F10.
- Dark Zone: a rotating PvP area with contaminated loot, extraction points and its own ranks and gear. Off by default (F1 > Dark Zone).
- Proximity voice and radios (bs_voice, bs_radio): walkie-talkies, batteries, relay coverage and radio power. bs_voice replaces pma-voice.
- Relay sabotage and restoration contracts (bs_missions).
- Wasteland Pass: a free 100-tier season pass with challenges.
- Survivor condition and character record (bs_survivor).
- Bodycam camera mode: a chest-mounted view with lens overlay, switchable in ESC settings and F1.
- Customize Weapon: a workbench with a front camera, drag-to-mount attachments, RGB paint per part, stickers, undo/redo and dark backdrops. The O menu mounts attachments in the field.
- Original weapon attachment models (three sets, loaded automatically with bs_weapons).
- Hybrid zombie population: cheap local walkers fill the streets and become full networked zombies when they notice you. Busier towns, hot zones, fewer walkers at night. F1 switch, on by default.
- Building v2: power, generators, faction flags and new pieces.
- Faction emblems: build your own emblem or pick a preset; banners and flags use it in the world.
- UI themes, new fonts, a clothing wheel in the F5 menu and a vMenu-style F10 noclip (with an optional backslash key).
- Ground loot, scavenging and the inventory vicinity strip with drag-to-ground and pickups.
- Fishing and outdoor jobs, more firearms, attachments and armorer stock, and painted icons for every item and attachment.
- First compatibility layer for ESX and Qbox scripts (bs_esx_bridge, qbx_core). Shipped but not started; see server.cfg.

### Improved

- Character selector loads faster, with new scenes (Grapeseed by default) and cleaner camera handoff on spawn.
- First-person view no longer clips through the body.
- Zombie hit effects land on the impact point, with optional damage feedback.
- Squad and faction frames include linked companions.
- HUD detects replacement HUDs, with an F1 override.
- Loading screen and Atlas follow the server language.

### Fixed

- Zombies that could not be killed: death is now confirmed by the server and leftover peds are cleaned up (`/zinspect` for staff).
- Zombies no longer stand on rooftops.
- Interactions no longer target through walls or outline vehicles.
- Faction poles no longer snap onto raised ground.
- Trainer, doctor and service NPCs are no longer removed by ambient cleanup.
- Backpack windows, storage scrolling and equipped backpacks seen by other players.
- Noclip resets properly on exit and places you on the ground.

### Database

Four new migrations (045 Dark Zone, 046 building v2, 047 faction emblems, 048 backpack items). They run on their own the first time bs_core starts. 048 renames the old backpack items and keeps their contents.

### Known issues

- Fighting: some attack clips can still T-pose the character. A guard catches most of them, but not all.
- Parkour: lightly tested. Some moves fail on certain walls and ledges.
- Weapon stickers: orientation and depth can be wrong on some weapons. Off by default (F1 > Weapons).
- Bodycam: framing and the third-person toggle are not fully tested.
- Hybrid zombies: new and untested at full player counts. If you see problems, switch it off in F1 to go back to the old spawner.
- ESX and Qbox bridges are partial. Many scripts will not work yet.
- Survivor Link, Dark Zone, the Wasteland Pass and voice/radio have had little testing with many players.
- Issues from 1.0.0-beta that are still open: convoy routes and power station panels are estimates, boars may not attack, mission kill steps can finish early when the zombie cap blocks spawns, and skinning needs the server to see the animal dead.

Please report anything else on [Discord](https://discord.gg/aBkCNgmDZ).


## BS19 v1.05 Hotfix

Fixes for the public release. No v1.1 systems are included.

- Fixed NPC targeting crashes, targeting through walls and progress bars staying on screen.
- Fixed refused inventory moves and unreliable character captures.
- Fixed selector camera/fade races and streaming focus left behind after spawning.
- Chat recovers from lost focus, stale panels and an unresponsive page.
- Fixed unavailable clothing entries and hard-to-reach checkout controls.
- Improved zombie hit/death reporting, takedown checks and recovery after knockdowns.
- Protected service NPCs from cleanup and corrected faction pole placement.
- Fixed interrupted give-up holds and repeated tutorial prompts for established characters.
- Staff teleports wait for collision; texture recovery is available in troubleshooting settings.
- Reduced repeated HUD, interaction and population work.

Read `How to update.txt` before copying files onto an existing server. Edited scripts need a comparison and merge; this update does not replace your database or server configuration.

## BS19 1.0.0-beta

First public release of BS19 (BeyondSurvival), a from-scratch RPG and zombie survival framework for FiveM. It installs with a single txAdmin recipe and runs with its own database tables, so there is nothing to convert from another framework.

### Highlights

- Networked zombies with difficulty scaling.
- Survival needs: hunger, thirst and the rest of the body upkeep.
- Inventory, traders and a working economy.
- Skills, factions and squads.
- Building with locks and vending crates.
- Operations: a power station, control points, and mission chains with an in-game editor.
- Convoys (off by default).
- The Apocalypse Project map is not bundled (https://github.com/Arcainex/The-Apocalypse-Project). It is an optional step in the install guide: download it, put it in resources/[map] and uncomment its ensure line in server.cfg.
- Hunting.
- Vehicles.
- F1 config console with presets (Default, Easy, Hardcore, PvP), so you can tune the server without editing files.
- 9 languages: English, German, Spanish, French, Italian, Polish, Portuguese, Russian and Turkish.
- Install through the txAdmin recipe. See docs/INSTALL.en.md.

### Known issues

This is a beta. Everything new in it is only lightly tested, so expect rough edges.

- Convoy default routes and power station panel positions are estimates. Fix them for your map with /convoyroute and F1 > Operations > Move here.
- Boars may not attack.
- Mission kill steps can complete early if the zombie cap blocks spawns.
- Skinning needs the server to see the animal dead, so a carcass that only the client thinks is dead cannot be skinned.

Please report anything else you find on the issue tracker.
