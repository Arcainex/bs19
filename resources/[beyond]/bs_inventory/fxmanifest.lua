fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_inventory'
author 'BeyondSurvival'
description 'BeyondSurvival - grid inventory, containers, crafting and settings'
version '0.2.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    '@bs_core/shared/sh_services.lua',
    -- cl_equipment calls BS.Util.ModelOf. A shared @-script is a per-resource include, not a global, so list it or BS.Util is nil.
    '@bs_core/shared/sh_util.lua',
    '@bs_core/shared/sh_locale.lua',
    'config/config_items.lua',
    'config/config_items_crafting.lua',
    'config/config_items_jobs.lua',
    -- After config_items: it merges garments into Items.Definitions and won't overwrite an existing id.
    'config/config_clothing.lua',
    'config/config_inventory.lua',
}

client_scripts {
    -- Before cl_main: publishes BSInvPedCam, used by cl_main's open path.
    'client/cl_pedcam.lua',
    'client/cl_bodyrender.lua',   -- BSInvBody, also used by cl_main
    'client/cl_main.lua',
    'client/cl_equipment.lua',
    'client/cl_drops.lua',
    'client/cl_hotbar.lua',
    'client/cl_missions.lua',
    'client/cl_camera.lua',   -- optional smooth camera settings
}
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- 2D placement engine: pure geometry, no state or events. Not wired in yet. Handles bounds, collision, row-major first fit, rotation fallback, and repacking existing items (slot_y = 0 means not placed).
    'server/sv_grid.lua',
    'server/sv_items.lua',
    'server/sv_main.lua',
    'server/sv_trade.lua',
    'server/sv_hotbar.lua',
    'server/sv_missions.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/medical.js',
    'html/css/medical.css',
    'html/js/craft.js',
    'html/js/missions.js',
    'html/css/missions.css',
    'html/css/craft.css',
    'locales/*.lua',
}

dependencies { 'bs_core', 'oxmysql' }

-- crash breadcrumbs (bs_core)
client_script '@bs_core/shared/sh_crumbs.lua'

-- live overrides from the F1 config console (bs_config); after the config files
shared_script '@bs_config/shared/apply.lua'
