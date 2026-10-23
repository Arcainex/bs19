fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_traders'
author 'BeyondSurvival'
description 'BeyondSurvival - SCUM-style NPC traders and mission givers'
version '0.1.0'

shared_scripts {
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_bridge.lua',
    -- Zones.Safe, read directly rather than copied (see config/config_traders.lua). Must come before it.
    '@bs_zombies/config/config_zones.lua',
    'config/config_traders.lua',
    'config/config_junk_trader.lua',
    -- Clothing shop categories, prices and gating. Shared: the client previews, the server authorises.
    'config/config_wardrobe.lua',
}

client_scripts {
    'client/cl_peds.lua',   -- spawns/culls the peds, registers bs_interactions
    'client/cl_main.lua',   -- player-facing shop/mission NUI + callbacks
    'client/cl_debug.lua',  -- /traderdebug, the separate staff-only live editor
    'client/cl_wardrobe.lua',  -- the clothing shop: preview, camera, fitting
}

server_scripts {
    'server/sv_stock.lua',     -- trader stock/restock state
    'server/sv_registry.lua',  -- config + DB override merge - before sv_traders uses it
    'server/sv_flagnpcs.lua',  -- copies of town NPCs at faction safezone flags, after sv_registry
    'server/sv_traders.lua',      -- shop transactions + mission lifecycle
    -- After sv_traders: it uses NearNpc/WithTxLock, which that file publishes as globals. Same Lua state, so no export needed.
    'server/sv_wardrobe.lua',     -- the clothing shop's pricing and gating
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    -- In-game garment names, generated from the game's own text tables. Must be listed before wardrobe.js reads it.
    'html/js/clothingnames.js',
    'html/js/wardrobe.js',
    'html/js/debug.js',
}

-- Dependencies: FXServer stops every resource that declares a dependency on a stopped one, transitively. Only list what is truly required, otherwise restarting bs_inventory also stops bs_traders and its peds.
dependencies {
    'bs_core',      -- @-included shared files (sh_util, sh_bridge)
    'bs_zombies',   -- @-included config_zones.lua; NPCs anchor to Zones.Safe
    'oxmysql',      -- live overrides queried at start (server/sv_registry.lua)
}

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'

-- translations (bs_core), strings in locales/<lang>.lua
shared_script '@bs_core/shared/sh_locale.lua'
files { 'locales/*.lua' }
