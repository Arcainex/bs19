# Changelog

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
