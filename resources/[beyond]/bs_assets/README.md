# bs_assets

Streaming container for everything the framework needs shipped to clients:
custom models, textures, audio banks and animation dictionaries.

## Rules for this folder

- Drop `.ydr` / `.ytd` / `.yft` / `.ycd` files into `stream/`. FiveM serves that
  directory recursively with no manifest changes needed.
- Custom audio needs a `data_file` line in `fxmanifest.lua` next to the commented
  examples.
- **Licensing**: only add assets you are allowed to redistribute. For anything
  pulled from the internet, record where it came from and its licence in
  `CREDITS.md` beside the file. Assets scraped from other servers, ripped from
  other games, or posted without a licence do not go in here.

## Currently shipped

Nothing. The framework runs entirely on base-game assets today:

| Need              | Base-game asset used                            |
| ----------------- | ----------------------------------------------- |
| Zombie peds       | `s_m_y_zombie_01`, `u_m_y_zombie_01`            |
| Shamble / attack  | `move_m@drunk@verydrunk`, `melee@unarmed@...`   |
| UI icons          | Inline SVG in `bs_ui/html/js/nui.js`            |
| UI font           | System stack (`Inter` -> `Segoe UI` -> system-ui) |

That keeps the first-run download at zero MB. Replace any row above by adding the
asset here and pointing the matching config at it.
