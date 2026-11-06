fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bs_darkzone'
author 'BeyondSurvival'
description 'BeyondSurvival - rotating Dark Zone: PvP, contaminated loot, extraction, DZ ranks'
version '1.0.0'

shared_scripts {
    '@bs_core/shared/sh_bridge.lua',
    -- Zones.FactionSafe: safezones and outposts the zone must stay away from
    '@bs_zombies/config/config_zones.lua',
    'config/config_darkzone.lua',
    -- F1 console overrides (bs_config), after the config it patches
    '@bs_config/shared/apply.lua',
    '@bs_core/shared/sh_locale.lua',
}

client_scripts { 'client/cl_main.lua' }

server_scripts {
    'server/sv_util.lua',
    'server/sv_zone.lua',
    'server/sv_progress.lua',
    'server/sv_bag.lua',
    'server/sv_admin.lua',
}

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'locales/*.lua' }

dependencies { 'oxmysql', 'bs_core', 'bs_inventory', 'bs_interactions', 'bs_zombies' }
