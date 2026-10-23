# Changelog

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
